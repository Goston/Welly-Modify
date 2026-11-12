//
//  WLTelnetRelay.c
//  Welly
//
//  telnet 程式與 BBS 伺服器之間的轉送層，說明見 WLTelnetRelay.h。
//

#include "WLTelnetRelay.h"

#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/un.h>

// 等待 telnet 程式連進來的時間上限（wss:// 會先等 websocket 轉接程式啟動，約需 2 秒）
#define WL_RELAY_ACCEPT_TIMEOUT_MS  30000
// 連到 unix socket 目的地時，等對方把 socket 建好的時間上限
#define WL_RELAY_UNIX_RETRY_MS      5000

struct WLTelnetRelay {
    pthread_mutex_t lock;   // 保護 refCount、cancelled、serverFd，以及對 serverFd 的寫入
    int refCount;           // 擁有者與轉送執行緒各持有一份
    int cancelled;
    int cancelPipe[2];      // 用來叫醒等待中的轉送執行緒
    int listenFd;
    int serverFd;           // 伺服器那一端；連上之前是 -1
    int port;
    char listenPath[sizeof(((struct sockaddr_un *)0)->sun_path)];
    char targetHost[256];
    char targetPort[16];    // 空字串表示 targetHost 是 unix socket 的路徑
};

#pragma mark - 小工具

// 這些 fd 不能被之後 fork 出來的 telnet / ssh 繼承，否則連線關閉時對方收不到 EOF
static void WLRelayPrepareFd(int fd, int isSocket) {
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    if (isSocket) {
        int on = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
    }
}

static int WLRelayWriteAll(int fd, const void *bytes, size_t length) {
    const unsigned char *p = bytes;
    while (length > 0) {
        ssize_t n = write(fd, p, length);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return 0;
        }
        p += n;
        length -= (size_t)n;
    }
    return 1;
}

static int WLRelayIsCancelled(WLTelnetRelay *relay) {
    pthread_mutex_lock(&relay->lock);
    int cancelled = relay->cancelled;
    pthread_mutex_unlock(&relay->lock);
    return cancelled;
}

// 等 fd 出現 events（或錯誤）。回傳 1 表示可以處理了；逾時或已取消回傳 0。timeoutMs < 0 表示不限時。
static int WLRelayWait(WLTelnetRelay *relay, int fd, short events, int timeoutMs) {
    struct pollfd fds[2] = {
        { .fd = fd, .events = events },
        { .fd = relay->cancelPipe[0], .events = POLLIN },
    };
    for (;;) {
        int n = poll(fds, 2, timeoutMs);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0 || fds[1].revents)
            return 0;
        return 1;
    }
}

static void WLRelayCloseListener(WLTelnetRelay *relay) {
    if (relay->listenFd >= 0) {
        close(relay->listenFd);
        relay->listenFd = -1;
        if (relay->listenPath[0])
            unlink(relay->listenPath);
    }
}

static void WLRelayRelease(WLTelnetRelay *relay) {
    pthread_mutex_lock(&relay->lock);
    int remaining = --relay->refCount;
    pthread_mutex_unlock(&relay->lock);
    if (remaining > 0)
        return;
    WLRelayCloseListener(relay);
    close(relay->cancelPipe[0]);
    close(relay->cancelPipe[1]);
    pthread_mutex_destroy(&relay->lock);
    free(relay);
}

#pragma mark - 連到目的地

static int WLRelayConnectTCP(WLTelnetRelay *relay) {
    struct addrinfo hints, *list = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;      // 與原本的 telnet -4 一致
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(relay->targetHost, relay->targetPort, &hints, &list) != 0)
        return -1;

    int result = -1;
    for (struct addrinfo *ai = list; ai != NULL && result < 0 && !WLRelayIsCancelled(relay); ai = ai->ai_next) {
        int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0)
            continue;
        WLRelayPrepareFd(fd, 1);
        // 以非阻塞方式連線，等待期間才能被取消
        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        int connected = (connect(fd, ai->ai_addr, ai->ai_addrlen) == 0);
        if (!connected && errno == EINPROGRESS && WLRelayWait(relay, fd, POLLOUT, -1)) {
            int error = 0;
            socklen_t length = sizeof(error);
            connected = (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 && error == 0);
        }
        if (connected) {
            fcntl(fd, F_SETFL, flags);
            result = fd;
        } else {
            close(fd);
        }
    }
    freeaddrinfo(list);
    return result;
}

static int WLRelayConnectUnix(WLTelnetRelay *relay) {
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, relay->targetHost, sizeof(address.sun_path));

    // 對方可能還沒把 socket 建好，稍等再試
    for (int waited = 0; waited <= WL_RELAY_UNIX_RETRY_MS && !WLRelayIsCancelled(relay); waited += 200) {
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0)
            return -1;
        WLRelayPrepareFd(fd, 1);
        if (connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0)
            return fd;
        close(fd);
        usleep(200 * 1000);
    }
    return -1;
}

#pragma mark - 轉送執行緒

static void WLRelayPump(WLTelnetRelay *relay, int clientFd, int serverFd) {
    unsigned char buffer[8192];
    struct pollfd fds[3] = {
        { .fd = clientFd, .events = POLLIN },
        { .fd = serverFd, .events = POLLIN },
        { .fd = relay->cancelPipe[0], .events = POLLIN },
    };
    for (;;) {
        int n = poll(fds, 3, -1);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0 || fds[2].revents)
            return;
        if (fds[0].revents) {
            // telnet 程式 → 伺服器
            ssize_t length = read(clientFd, buffer, sizeof(buffer));
            if (length < 0 && errno == EINTR)
                continue;
            if (length <= 0)
                return;
            pthread_mutex_lock(&relay->lock);
            int ok = WLRelayWriteAll(serverFd, buffer, (size_t)length);
            pthread_mutex_unlock(&relay->lock);
            if (!ok)
                return;
        }
        if (fds[1].revents) {
            // 伺服器 → telnet 程式
            ssize_t length = read(serverFd, buffer, sizeof(buffer));
            if (length < 0 && errno == EINTR)
                continue;
            if (length <= 0 || !WLRelayWriteAll(clientFd, buffer, (size_t)length))
                return;
        }
    }
}

static void *WLRelayMain(void *context) {
    WLTelnetRelay *relay = context;
    int clientFd = -1, serverFd = -1;

    // 只接受第一個連進來的連線（也就是 Welly 自己啟動的 telnet 程式），之後就不再監聽
    if (WLRelayWait(relay, relay->listenFd, POLLIN, WL_RELAY_ACCEPT_TIMEOUT_MS))
        clientFd = accept(relay->listenFd, NULL, NULL);
    WLRelayCloseListener(relay);

    if (clientFd >= 0) {
        WLRelayPrepareFd(clientFd, 1);
        if (relay->targetPort[0]) {
            // telnet 程式此時顯示的是「Connected to localhost」，補上實際連線的對象
            char message[320];
            int length = snprintf(message, sizeof(message), "Connecting to %s:%s...\r\n", relay->targetHost, relay->targetPort);
            WLRelayWriteAll(clientFd, message, (size_t)length);
            serverFd = WLRelayConnectTCP(relay);
        } else {
            serverFd = WLRelayConnectUnix(relay);
        }
    }

    if (serverFd >= 0) {
        pthread_mutex_lock(&relay->lock);
        relay->serverFd = serverFd;
        pthread_mutex_unlock(&relay->lock);

        WLRelayPump(relay, clientFd, serverFd);

        pthread_mutex_lock(&relay->lock);
        relay->serverFd = -1;
        pthread_mutex_unlock(&relay->lock);
        close(serverFd);
    }
    // 關掉 telnet 程式這一端，它就會自行結束，Welly 也就知道連線中斷了
    if (clientFd >= 0)
        close(clientFd);
    WLRelayRelease(relay);
    return NULL;
}

#pragma mark - 對外介面

static int WLRelayListenTCP(WLTelnetRelay *relay) {
    struct sockaddr_in address;
    socklen_t length = sizeof(address);
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;

    relay->listenFd = socket(AF_INET, SOCK_STREAM, 0);
    if (relay->listenFd < 0)
        return 0;
    WLRelayPrepareFd(relay->listenFd, 1);
    if (bind(relay->listenFd, (struct sockaddr *)&address, sizeof(address)) != 0 ||
        listen(relay->listenFd, 1) != 0 ||
        getsockname(relay->listenFd, (struct sockaddr *)&address, &length) != 0)
        return 0;
    relay->port = ntohs(address.sin_port);
    return 1;
}

static int WLRelayListenUnix(WLTelnetRelay *relay, const char *path) {
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    if (strlen(path) >= sizeof(address.sun_path))
        return 0;
    strlcpy(address.sun_path, path, sizeof(address.sun_path));

    relay->listenFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (relay->listenFd < 0)
        return 0;
    WLRelayPrepareFd(relay->listenFd, 1);
    unlink(path);
    if (bind(relay->listenFd, (struct sockaddr *)&address, sizeof(address)) != 0)
        return 0;
    // bind 成功之後才記下路徑，結束時才會刪除自己建立的檔案
    strlcpy(relay->listenPath, path, sizeof(relay->listenPath));
    return listen(relay->listenFd, 1) == 0;
}

WLTelnetRelay *WLTelnetRelayCreate(const char *listenPath, const char *targetHost, const char *targetPort) {
    if (targetHost == NULL)
        return NULL;
    WLTelnetRelay *relay = calloc(1, sizeof(WLTelnetRelay));
    if (relay == NULL)
        return NULL;
    relay->listenFd = -1;
    relay->serverFd = -1;
    if (pipe(relay->cancelPipe) != 0) {
        free(relay);
        return NULL;
    }
    WLRelayPrepareFd(relay->cancelPipe[0], 0);
    WLRelayPrepareFd(relay->cancelPipe[1], 0);
    pthread_mutex_init(&relay->lock, NULL);
    relay->refCount = 1;

    int ok = strlcpy(relay->targetHost, targetHost, sizeof(relay->targetHost)) < sizeof(relay->targetHost);
    if (ok && targetPort != NULL)
        ok = strlcpy(relay->targetPort, targetPort, sizeof(relay->targetPort)) < sizeof(relay->targetPort);
    if (ok)
        ok = (listenPath != NULL) ? WLRelayListenUnix(relay, listenPath) : WLRelayListenTCP(relay);
    if (ok) {
        pthread_t thread;
        relay->refCount = 2;
        ok = (pthread_create(&thread, NULL, WLRelayMain, relay) == 0);
        if (ok)
            pthread_detach(thread);
        else
            relay->refCount = 1;
    }
    if (!ok) {
        WLRelayRelease(relay);
        return NULL;
    }
    return relay;
}

int WLTelnetRelayPort(const WLTelnetRelay *relay) {
    return relay->port;
}

int WLTelnetRelaySend(WLTelnetRelay *relay, const void *bytes, size_t length) {
    // 轉送執行緒正在寫入時不等待，放棄這一次，避免卡住呼叫端（主執行緒）
    if (pthread_mutex_trylock(&relay->lock) != 0)
        return 0;
    int ok = 0;
    if (!relay->cancelled && relay->serverFd >= 0)
        ok = WLRelayWriteAll(relay->serverFd, bytes, length);
    pthread_mutex_unlock(&relay->lock);
    return ok;
}

void WLTelnetRelayClose(WLTelnetRelay *relay) {
    pthread_mutex_lock(&relay->lock);
    relay->cancelled = 1;
    pthread_mutex_unlock(&relay->lock);
    // 叫醒轉送執行緒，讓它關閉連線後結束
    char wake = 0;
    while (write(relay->cancelPipe[1], &wake, 1) < 0 && errno == EINTR)
        ;
    WLRelayRelease(relay);
}

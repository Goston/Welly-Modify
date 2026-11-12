//
//  WLTelnetRelay.h
//  Welly
//
//  telnet 程式與 BBS 伺服器之間的轉送層。
//
//  Welly 是透過外部的 telnet 程式連線的，而 telnet 程式會把寫入的 0xFF 轉義成
//  0xFF 0xFF，因此無法經由它送出真正的 Telnet 指令（例如防閒置用的 IAC DO TIMING-MARK）。
//  轉送層讓 telnet 程式改連到本機，再由轉送層連到實際的伺服器並原封不動地雙向轉送，
//  需要時就能把原始位元組直接送往伺服器。
//

#ifndef WLTelnetRelay_h
#define WLTelnetRelay_h

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct WLTelnetRelay WLTelnetRelay;

// 建立轉送層，並在背景執行緒等待 telnet 程式連進來，之後連到目的地開始轉送。
// - listenPath 為 NULL：在 127.0.0.1 的隨機連接埠監聽（以 WLTelnetRelayPort 取得）；
//   否則在該路徑的 unix socket 監聽。
// - targetPort 為 NULL：targetHost 是 unix socket 的路徑；否則以 TCP（IPv4）連到 targetHost:targetPort。
// 失敗時回傳 NULL。
WLTelnetRelay *WLTelnetRelayCreate(const char *listenPath, const char *targetHost, const char *targetPort);

// 轉送層監聽的 TCP 連接埠；以 unix socket 監聽時為 0。
int WLTelnetRelayPort(const WLTelnetRelay *relay);

// 把位元組原封不動地送往伺服器（不經過 telnet 程式，不會被轉義）。
// 成功回傳 1；尚未連上伺服器、連線已結束或轉送中來不及送出時回傳 0。
int WLTelnetRelaySend(WLTelnetRelay *relay, const void *bytes, size_t length);

// 結束轉送並釋放資源，之後不可再使用 relay。
void WLTelnetRelayClose(WLTelnetRelay *relay);

#ifdef __cplusplus
}
#endif

#endif /* WLTelnetRelay_h */

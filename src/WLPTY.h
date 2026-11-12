//
//  XIPTY.h
//  Welly
//
//  Created by boost @ 9# on 7/13/08.
//  Copyright 2008 Xi Wang. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "WLProtocol.h"
#import "WLTelnetRelay.h"

@interface WLPTY : NSObject <WLProtocol> {
    pid_t _pid;
    int _fd;
    id _delegate;
    BOOL _connecting;
    WLProxyType _proxyType;
    NSString *_proxyAddress;
    // telnet://、wss:// 連線時，telnet 程式與伺服器之間的轉送層；其他連線方式為 NULL
    WLTelnetRelay *_relay;
    // 連線程式是 ssh（寫入 PTY 的位元組會原封不動送到伺服器）
    BOOL _isSSH;
}
@property (readwrite, assign) id delegate;
@property (readwrite, assign) WLProxyType proxyType;
@property (readwrite, copy) NSString *proxyAddress;
@end

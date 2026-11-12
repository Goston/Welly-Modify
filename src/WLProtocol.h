//
//  WLProtocol.h
//  Welly
//
//  Created by boost @ 9# on 7/13/08.
//  Copyright 2008 Xi Wang. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol WLProtocol
- (BOOL)connect:(NSString *)addr;
- (void)close;
- (void)recv:(NSData *)data;
- (void)send:(NSData *)data;
// 把位元組原封不動地送到伺服器，用於 Telnet 指令（例如防閒置），不會被當成按鍵轉義
- (void)sendRaw:(NSData *)data;
@end

@interface NSObject (WLProtocolDelegate)
- (void)protocolWillConnect:(id)protocol;
- (void)protocolDidConnect:(id)protocol;
- (void)protocolDidRecv:(id)protocol data:(NSData*)data;
- (void)protocolWillSend:(id)protocol data:(NSData*)data;
- (void)protocolDidClose:(id)protocol;
@end

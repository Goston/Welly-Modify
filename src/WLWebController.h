//
//  WLWebController.h
//  Welly
//
//  以 Welly 自己的視窗開啟一般網頁連結（「預設處理網址連結方式」設為 Quick Look 時使用）。
//  Quick Look 的 HTML 預覽禁止執行 JavaScript，多數網站顯示不出來，所以另開網頁視窗。
//

#import <Cocoa/Cocoa.h>

@interface WLWebController : NSObject

// 是 http／https 連結就在網頁視窗開啟並回傳 YES；其他種類的連結回傳 NO，不做任何事。
// http 連結會先改成 https 載入，載入失敗才交給外部瀏覽器開啟原本的網址
+ (BOOL)openURL:(NSURL *)URL;

@end

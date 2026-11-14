//
//  WLYouTubeController.h
//  Welly
//
//  以 YouTube 官方內嵌播放器，在 Welly 自己的視窗播放影片。
//  Quick Look 的 HTML 預覽禁止執行 JavaScript，無法載入播放器，所以另開視窗。
//

#import <Cocoa/Cocoa.h>

@interface WLYouTubeController : NSObject

// 是 YouTube 影片連結就開啟播放視窗並回傳 YES；否則回傳 NO，不做任何事
+ (BOOL)openURL:(NSURL *)URL;

@end

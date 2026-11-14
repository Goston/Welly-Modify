//
//  WLYouTubeController.m
//  Welly
//

#import "WLYouTubeController.h"
#import <WebKit/WebKit.h>

@interface WLYouTubeController () <NSWindowDelegate, WKNavigationDelegate, WKUIDelegate> {
    NSWindow *_window;
    WKWebView *_webView;
}
- (void)play:(NSURL *)embedURL;
@end

@implementation WLYouTubeController

+ (WLYouTubeController *)sharedInstance {
    static WLYouTubeController *instance = nil;
    if (instance == nil) {
        instance = [WLYouTubeController new];
    }
    return instance;
}

// 把網址中的起始時間（"90"、"90s"、"1m30s"、"1h2m3s"）換算成秒數
static NSInteger secondsFromTimeString(NSString *string) {
    NSScanner *scanner = [NSScanner scannerWithString:[string lowercaseString]];
    NSInteger total = 0, value;
    while ([scanner scanInteger:&value]) {
        if ([scanner scanString:@"h" intoString:NULL])
            total += value * 3600;
        else if ([scanner scanString:@"m" intoString:NULL])
            total += value * 60;
        else {
            [scanner scanString:@"s" intoString:NULL];
            total += value;
        }
    }
    return total;
}

// 把 YouTube 的影片連結轉成內嵌播放器的網址；不是影片連結時回傳 nil。
// 支援 youtube.com/watch?v=、youtu.be/、/shorts/、/live/、/embed/，以及 t=／start= 起始時間。
+ (NSURL *)embedURLForURL:(NSURL *)URL {
    if (URL == nil)
        return nil;
    NSString *host = [[URL host] lowercaseString];
    // -path 不含查詢字串與結尾的斜線；"/shorts/xxx" 會拆成 ("/", "shorts", "xxx")
    NSArray *parts = [[URL path] pathComponents];
    NSString *queryVideoID = nil, *start = nil;
    for (NSURLQueryItem *item in [[NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO] queryItems]) {
        if ([[item name] isEqualToString:@"v"])
            queryVideoID = [item value];
        else if ([[item name] isEqualToString:@"t"] || [[item name] isEqualToString:@"start"])
            start = [item value];
    }

    NSString *videoID = nil;
    if ([host isEqualToString:@"youtu.be"]) {
        if ([parts count] == 2)
            videoID = [parts objectAtIndex:1];
    } else if ([[NSArray arrayWithObjects:@"youtube.com", @"www.youtube.com", @"m.youtube.com", nil] containsObject:host]) {
        if ([parts count] == 2 && [[parts objectAtIndex:1] isEqualToString:@"watch"])
            videoID = queryVideoID;
        else if ([parts count] == 3 && [[NSArray arrayWithObjects:@"shorts", @"live", @"embed", nil] containsObject:[parts objectAtIndex:1]])
            videoID = [parts objectAtIndex:2];
    }
    if (videoID == nil || [videoID rangeOfString:@"^[A-Za-z0-9_-]{11}$" options:NSRegularExpressionSearch].location == NSNotFound)
        return nil;

    NSString *embed = [@"https://www.youtube.com/embed/" stringByAppendingString:videoID];
    NSInteger seconds = start ? secondsFromTimeString(start) : 0;
    if (seconds > 0)
        embed = [embed stringByAppendingFormat:@"?start=%ld", (long)seconds];
    return [NSURL URLWithString:embed];
}

+ (BOOL)openURL:(NSURL *)URL {
    NSURL *embedURL = [self embedURLForURL:URL];
    if (embedURL == nil)
        return NO;
    [[self sharedInstance] play:embedURL];
    return YES;
}

- (void)play:(NSURL *)embedURL {
    // 只用一個視窗；再點別的影片連結就換成新的影片
    if (_window == nil) {
        WKWebViewConfiguration *configuration = [[[WKWebViewConfiguration alloc] init] autorelease];
        // 讓播放器上的全螢幕按鈕可用
        if (@available(macOS 12.3, *))
            [[configuration preferences] setElementFullscreenEnabled:YES];
        NSRect frame = NSMakeRect(0, 0, 854, 480);
        _webView = [[WKWebView alloc] initWithFrame:frame configuration:configuration];
        [_webView setNavigationDelegate:self];
        [_webView setUIDelegate:self];

        _window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
        [_window setReleasedWhenClosed:NO];
        [_window setDelegate:self];
        [_window setTitle:@"YouTube"];
        [_window setContentAspectRatio:frame.size];
        // YouTube 建議 16:9 的播放器至少 480x270
        [_window setContentMinSize:NSMakeSize(480, 270)];
        [_window setContentView:_webView];
        [_window center];
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:embedURL];
    // YouTube 要求內嵌播放器的用戶端以 Referer 表明身分，桌面 App 的格式是 https://<bundle ID 小寫>；
    // 沒有這個標頭時播放器會顯示「錯誤 153」
    NSString *referer = [@"https://" stringByAppendingString:[[[NSBundle mainBundle] bundleIdentifier] lowercaseString]];
    [request setValue:referer forHTTPHeaderField:@"Referer"];
    [_webView loadRequest:request];
    [_window makeKeyAndOrderFront:nil];
}

#pragma mark -
#pragma mark NSWindowDelegate protocol

// 關閉視窗時換成空白頁，影片才會停止播放
- (void)windowWillClose:(NSNotification *)notification {
    [_webView loadHTMLString:@"" baseURL:nil];
}

#pragma mark -
#pragma mark WKNavigationDelegate / WKUIDelegate protocol

// 播放器內的連結（例如「前往 YouTube 觀看」）交給瀏覽器，不在播放視窗內瀏覽
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if ([navigationAction navigationType] == WKNavigationTypeLinkActivated) {
        [[NSWorkspace sharedWorkspace] openURL:[[navigationAction request] URL]];
        decisionHandler(WKNavigationActionPolicyCancel);
    } else {
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}

// 播放器要求開新視窗的連結同樣交給瀏覽器
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    [[NSWorkspace sharedWorkspace] openURL:[[navigationAction request] URL]];
    return nil;
}

@end

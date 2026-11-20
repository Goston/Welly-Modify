//
//  WLWebController.m
//  Welly
//

#import "WLWebController.h"
#import <WebKit/WebKit.h>

static NSString *const WLWebToolbarIdentifier = @"WLWebToolbar";
static NSString *const WLWebBackItemIdentifier = @"WLWebBack";
static NSString *const WLWebForwardItemIdentifier = @"WLWebForward";
static NSString *const WLWebReloadItemIdentifier = @"WLWebReload";
static NSString *const WLWebBrowserItemIdentifier = @"WLWebBrowser";

@interface WLWebController () <NSWindowDelegate, NSToolbarDelegate, NSToolbarItemValidation, WKNavigationDelegate, WKUIDelegate> {
    NSWindow *_window;
    WKWebView *_webView;
    // 這一次載入失敗時，要交給瀏覽器開啟的網址（使用者點的原始連結）
    NSURL *_fallbackURL;
    // 這一次載入中已經由 http 改成 https 試過的網址；網站把 https 又轉回 http 時用來避免無窮迴圈
    NSMutableSet *_upgradedURLs;
    // 視窗裡是否已經有載入成功的頁面
    BOOL _hasContent;
}
@property (retain) NSURL *fallbackURL;
- (void)load:(NSURL *)URL;
- (void)destroyWebView;
@end

@implementation WLWebController
@synthesize fallbackURL = _fallbackURL;

+ (WLWebController *)sharedInstance {
    static WLWebController *instance = nil;
    if (instance == nil) {
        instance = [WLWebController new];
    }
    return instance;
}

+ (BOOL)openURL:(NSURL *)URL {
    NSString *scheme = [[URL scheme] lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])
        return NO;
    [[self sharedInstance] load:URL];
    return YES;
}

- (id)init {
    self = [super init];
    if (self) {
        _upgradedURLs = [[NSMutableSet alloc] init];
    }
    return self;
}

- (void)dealloc {
    [self destroyWebView];
    [_window release];
    [_fallbackURL release];
    [_upgradedURLs release];
    [super dealloc];
}

// App 沒有開放 http 連線（App Transport Security），http 網址改成 https 再載入
static NSURL *secureURLForURL(NSURL *URL) {
    NSURLComponents *components = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
    [components setScheme:@"https"];
    // 網址明確寫了 80 埠時，改成 https 不能沿用
    if ([[components port] integerValue] == 80)
        [components setPort:nil];
    return [components URL];
}

#pragma mark -
#pragma mark Window

- (void)createWindow {
    NSRect frame = NSMakeRect(0, 0, 1000, 720);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setReleasedWhenClosed:NO];
    [_window setDelegate:self];
    [_window setContentMinSize:NSMakeSize(480, 320)];
    [_window center];
    // 記住使用者調整過的視窗位置與大小
    [_window setFrameAutosaveName:@"WLWebWindow"];

    NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier:WLWebToolbarIdentifier] autorelease];
    [toolbar setDelegate:self];
    [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
    [toolbar setAllowsUserCustomization:NO];
    [_window setToolbar:toolbar];
    // 標題獨立一列，工具列在下方由左排起（上一頁、下一頁、重新載入在左，以瀏覽器開啟在右）
    [_window setToolbarStyle:NSWindowToolbarStyleExpanded];
}

// 每次開啟視窗都用新的網頁檢視，上一頁／下一頁的紀錄才不會留著上次關閉前的頁面
- (void)createWebView {
    WKWebViewConfiguration *configuration = [[[WKWebViewConfiguration alloc] init] autorelease];
    // WKWebView 預設的 User-Agent 沒有瀏覽器名稱，部分網站會當成不支援的瀏覽器；補上與 Safari 相同的結尾
    [configuration setApplicationNameForUserAgent:@"Version/17.6 Safari/605.1.15"];
    if (@available(macOS 12.3, *))
        [[configuration preferences] setElementFullscreenEnabled:YES];
    _webView = [[WKWebView alloc] initWithFrame:[[_window contentView] bounds] configuration:configuration];
    [_webView setNavigationDelegate:self];
    [_webView setUIDelegate:self];
    [_webView setAllowsBackForwardNavigationGestures:YES];
    [_webView addObserver:self forKeyPath:@"title" options:0 context:NULL];
    [_webView addObserver:self forKeyPath:@"canGoBack" options:0 context:NULL];
    [_webView addObserver:self forKeyPath:@"canGoForward" options:0 context:NULL];
    [_window setContentView:_webView];
}

- (void)destroyWebView {
    if (_webView == nil)
        return;
    [_webView removeObserver:self forKeyPath:@"title"];
    [_webView removeObserver:self forKeyPath:@"canGoBack"];
    [_webView removeObserver:self forKeyPath:@"canGoForward"];
    [_webView setNavigationDelegate:nil];
    [_webView setUIDelegate:nil];
    [_webView stopLoading];
    [_window setContentView:[[[NSView alloc] initWithFrame:NSZeroRect] autorelease]];
    [_webView release];
    _webView = nil;
}

// 標題一律帶出目前頁面的網域：網頁標題是網站自己給的，只顯示它的話可以冒充成別的網站
- (void)updateTitle {
    NSString *title = [_webView title];
    NSString *host = [[_webView URL] host];
    if ([host length] == 0)
        [_window setTitle:@"Welly"];
    else if ([title length] == 0)
        [_window setTitle:host];
    else
        [_window setTitle:[NSString stringWithFormat:@"%@ — %@", host, title]];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object != _webView)
        return;
    if ([keyPath isEqualToString:@"title"])
        [self updateTitle];
    else
        [[_window toolbar] validateVisibleItems];
}

- (void)load:(NSURL *)URL {
    if (_window == nil)
        [self createWindow];
    // 只用一個視窗；再點別的連結就換成新的網頁
    if (_webView == nil)
        [self createWebView];
    [_upgradedURLs removeAllObjects];
    [self setFallbackURL:URL];
    [self updateTitle];
    // http 網址會在 decidePolicyForNavigationAction 改成 https
    [_webView loadRequest:[NSURLRequest requestWithURL:URL]];
    [_window makeKeyAndOrderFront:nil];
}

// 這個網址無法在視窗內顯示，交給外部瀏覽器；視窗裡如果還沒有任何頁面就一併關掉，不留空白視窗
- (void)handOverToBrowser:(NSURL *)URL {
    // 網址可能來自網頁內容（轉址、指令碼），只允許把網頁交給瀏覽器；
    // file:// 或其他 App 的網址協定一律不開
    NSString *scheme = [[URL scheme] lowercaseString];
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
        [[NSWorkspace sharedWorkspace] openURL:URL];
    // 這裡是從網頁檢視的回呼進來的；關閉視窗會釋放網頁檢視，要等回呼結束後再做
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!_hasContent)
            [_window close];
    });
}

#pragma mark -
#pragma mark NSWindowDelegate protocol

// 關閉視窗時丟掉網頁檢視，正在播放的影音才會停止
- (void)windowWillClose:(NSNotification *)notification {
    [self destroyWebView];
    [self setFallbackURL:nil];
    [_upgradedURLs removeAllObjects];
    _hasContent = NO;
}

#pragma mark -
#pragma mark Toolbar

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return [NSArray arrayWithObjects:WLWebBackItemIdentifier, WLWebForwardItemIdentifier, WLWebReloadItemIdentifier,
            NSToolbarFlexibleSpaceItemIdentifier, WLWebBrowserItemIdentifier, nil];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSString *symbol, *label;
    SEL action;
    if ([identifier isEqualToString:WLWebBackItemIdentifier]) {
        symbol = @"chevron.left";
        label = NSLocalizedString(@"Back", @"Web Window Toolbar");
        action = @selector(goBack:);
    } else if ([identifier isEqualToString:WLWebForwardItemIdentifier]) {
        symbol = @"chevron.right";
        label = NSLocalizedString(@"Forward", @"Web Window Toolbar");
        action = @selector(goForward:);
    } else if ([identifier isEqualToString:WLWebReloadItemIdentifier]) {
        symbol = @"arrow.clockwise";
        label = NSLocalizedString(@"Reload", @"Web Window Toolbar");
        action = @selector(reload:);
    } else if ([identifier isEqualToString:WLWebBrowserItemIdentifier]) {
        symbol = @"safari";
        label = NSLocalizedString(@"Open in Browser", @"Web Window Toolbar");
        action = @selector(openInBrowser:);
    } else {
        return nil;
    }
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
    [item setImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label]];
    [item setLabel:label];
    [item setPaletteLabel:label];
    [item setToolTip:label];
    [item setBordered:YES];
    [item setTarget:self];
    [item setAction:action];
    return item;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    NSString *identifier = [item itemIdentifier];
    if ([identifier isEqualToString:WLWebBackItemIdentifier])
        return [_webView canGoBack];
    if ([identifier isEqualToString:WLWebForwardItemIdentifier])
        return [_webView canGoForward];
    return [_webView URL] != nil;
}

- (void)goBack:(id)sender {
    [_webView goBack];
}

- (void)goForward:(id)sender {
    [_webView goForward];
}

- (void)reload:(id)sender {
    [_webView reload];
}

- (void)openInBrowser:(id)sender {
    NSString *scheme = [[[_webView URL] scheme] lowercaseString];
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
        [[NSWorkspace sharedWorkspace] openURL:[_webView URL]];
}

#pragma mark -
#pragma mark WKNavigationDelegate / WKUIDelegate protocol

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *URL = [[navigationAction request] URL];
    NSString *scheme = [[URL scheme] lowercaseString];
    // targetFrame 是 nil 代表要開新視窗，會由 createWebViewWithConfiguration 改在同一個視窗載入
    BOOL isMainFrame = [navigationAction targetFrame] == nil || [[navigationAction targetFrame] isMainFrame];
    if (!isMainFrame) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    // 使用者在頁面裡點連結、送出表單、按上一頁等等：這一次載入失敗時交給瀏覽器的是這個新網址。
    // 轉址與我們自己發出的載入（WKNavigationTypeOther）則沿用原本的
    if ([navigationAction navigationType] != WKNavigationTypeOther) {
        [self setFallbackURL:URL];
        [_upgradedURLs removeAllObjects];
    }

    if ([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"about"] || [scheme isEqualToString:@"blob"] || [scheme isEqualToString:@"data"]) {
        decisionHandler(WKNavigationActionPolicyAllow);
    } else if ([scheme isEqualToString:@"http"]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        if ([_upgradedURLs containsObject:[URL absoluteString]]) {
            // 已經改成 https 試過，網站又轉回 http：這個網站只能用 http，交給瀏覽器
            [self handOverToBrowser:(_fallbackURL ?: URL)];
        } else {
            [_upgradedURLs addObject:[URL absoluteString]];
            NSURLRequest *request = [NSURLRequest requestWithURL:secureURLForURL(URL)];
            // 等這一次的取消處理完再載入
            dispatch_async(dispatch_get_main_queue(), ^{
                [_webView loadRequest:request];
            });
        }
    } else {
        // 其他種類的連結不在視窗內載入。只有使用者親自點的 mailto: 連結交給系統；
        // 網頁自己觸發的、或 file:// 與其他 App 的網址協定一律不處理
        decisionHandler(WKNavigationActionPolicyCancel);
        if ([scheme isEqualToString:@"mailto"] && [navigationAction navigationType] == WKNavigationTypeLinkActivated)
            [[NSWorkspace sharedWorkspace] openURL:URL];
        // 視窗裡還沒有任何頁面時不留空白視窗
        [self handOverToBrowser:nil];
    }
}

// 無法在網頁檢視顯示的內容（例如壓縮檔）交給瀏覽器下載
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if ([navigationResponse isForMainFrame] && ![navigationResponse canShowMIMEType]) {
        decisionHandler(WKNavigationResponsePolicyCancel);
        [self handOverToBrowser:[[navigationResponse response] URL]];
    } else {
        decisionHandler(WKNavigationResponsePolicyAllow);
    }
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    // 關閉視窗時不會有載入；about:blank 之類的空白頁不算有內容
    if ([[[[webView URL] scheme] lowercaseString] isEqualToString:@"https"])
        _hasContent = YES;
    [self updateTitle];
    [[_window toolbar] validateVisibleItems];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [_upgradedURLs removeAllObjects];
}

// 連不上、憑證有問題、網站不支援 https 等等：交給瀏覽器開啟使用者原本點的網址
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    // 被新的載入取代，或是我們自己在 decidePolicy 取消的，都不算失敗
    if ([[error domain] isEqualToString:NSURLErrorDomain] && [error code] == NSURLErrorCancelled)
        return;
    if ([[error domain] isEqualToString:@"WebKitErrorDomain"])
        return;
    NSURL *URL = _fallbackURL;
    if (URL == nil)
        URL = [[error userInfo] objectForKey:NSURLErrorFailingURLErrorKey];
    [self handOverToBrowser:URL];
}

// 頁面要求開新視窗的連結（target="_blank"、window.open）改在同一個視窗載入
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    [webView loadRequest:[navigationAction request]];
    return nil;
}

@end

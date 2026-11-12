//
//  XITabBarControl.m
//  Welly
//
//  Created by boost @ 9# on 7/14/08.
//  Copyright 2008 Xi Wang. All rights reserved.
//

#import "WLTabBarControl.h"
#import "WLMainFrameController.h"
#import "CommonType.h"

// suppress warnings
@interface PSMTabBarControl ()
- (NSArray *)cells;
- (id)cellForPoint:(NSPoint)mousePt 
		 cellFrame:(NSRect *)cellFrame;
- (void)closeTabClick:(id)sender;

@end

const CGFloat WLTabBarHeight = 34.0;

#pragma mark - 膠囊式分頁樣式

// 膠囊軌道的高度（「＋」按鈕的直徑與此相同）
static const CGFloat WLCapsuleTrackHeight = 26.0;
// 分頁列左右兩側的留白
static const CGFloat WLCapsuleSideMargin = 8.0;
// 作用中分頁的白色膠囊相對於軌道的內縮
static const CGFloat WLCapsuleSelectionInset = 2.0;
// 關閉按鈕的邊長，以及它與分頁左緣的距離
static const CGFloat WLCapsuleCloseButtonSize = 14.0;
static const CGFloat WLCapsuleCloseButtonInset = 10.0;
// 溢位選單按鈕與軌道右緣的距離
static const CGFloat WLCapsuleOverflowButtonInset = 6.0;
static const CGFloat WLCapsuleTitleFontSize = 12.0;
// 分頁寬度上限設得比任何分頁列都寬，讓所有分頁平均分配整條軌道
static const NSInteger WLCapsuleUnlimitedCellWidth = 100000;

// PSMTabBarControl.framework 沒有附上 PSMTabBarCell 的標頭檔，這裡只宣告樣式會用到的方法
@interface PSMTabBarCell : NSActionCell
- (NSRect)frame;
- (BOOL)shouldDrawCloseButton;
- (BOOL)closeButtonOver;
- (BOOL)closeButtonPressed;
- (NSRect)closeButtonRectForBounds:(NSRect)theRect;
- (NSRect)iconRectForBounds:(NSRect)theRect;
- (NSRect)indicatorRectForBounds:(NSRect)theRect;
- (NSRect)objectCounterRectForBounds:(NSRect)theRect;
- (NSRect)titleRectForBounds:(NSRect)theRect;
@end

static BOOL WLIsDarkAppearance(NSAppearance *appearance)
{
    NSAppearanceName match = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

// 以指定顏色把 SF Symbol 畫在 bounds 的正中央
static void WLDrawSymbol(NSString *name, CGFloat pointSize, NSFontWeight weight, NSColor *color, NSRect bounds)
{
    NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    NSImage *symbol = [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil] imageWithSymbolConfiguration:configuration];
    if (symbol == nil)
        return;

    NSSize size = [symbol size];
    NSRect rect = NSMakeRect(NSMidX(bounds) - size.width / 2, NSMidY(bounds) - size.height / 2, size.width, size.height);

    // 先在透明圖層內畫出符號再上色，SourceAtop 才不會染到圖層外已經畫好的底色
    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
    CGContextBeginTransparencyLayer(context, NULL);
    [symbol drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
    [color set];
    NSRectFillUsingOperation(rect, NSCompositingOperationSourceAtop);
    CGContextEndTransparencyLayer(context);
}

// 圓形的「＋」按鈕圖；overlayAlpha 是滑鼠移入或按下時額外疊上的深色程度
static NSImage *WLAddTabButtonImage(CGFloat overlayAlpha)
{
    NSSize size = NSMakeSize(WLCapsuleTrackHeight, WLCapsuleTrackHeight);
    return [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        BOOL dark = WLIsDarkAppearance([NSAppearance currentDrawingAppearance]);
        NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(dstRect, 0.5, 0.5)];

        [(dark ? [NSColor colorWithCalibratedWhite:1.0 alpha:0.12] : [NSColor whiteColor]) set];
        [circle fill];
        if (overlayAlpha > 0) {
            [[[NSColor labelColor] colorWithAlphaComponent:overlayAlpha] set];
            [circle fill];
        }
        [[[NSColor labelColor] colorWithAlphaComponent:0.12] set];
        [circle setLineWidth:1.0];
        [circle stroke];

        WLDrawSymbol(@"plus", 12.0, NSFontWeightMedium, [NSColor labelColor], dstRect);
        return YES;
    }];
}

// 仿 Finder 分頁列的樣式：淺灰膠囊軌道、作用中分頁為白色膠囊、右側圓形「＋」按鈕。
// PSMTabBarControl 會以 respondsToSelector: 逐一詢問樣式物件，未實作的方法會退回框架預設行為。
@interface WLCapsuleTabStyle : NSObject
@end

@implementation WLCapsuleTabStyle

+ (NSString *)name
{
    return @"Capsule";
}

- (NSString *)name
{
    return [[self class] name];
}

#pragma mark 版面

- (CGFloat)heightOfTabCellsForTabBarControl:(PSMTabBarControl *)tabBarControl
{
    return WLTabBarHeight;
}

- (CGFloat)leftMarginForTabBarControl:(PSMTabBarControl *)tabBarControl
{
    return WLCapsuleSideMargin;
}

- (CGFloat)rightMarginForTabBarControl:(PSMTabBarControl *)tabBarControl
{
    return WLCapsuleSideMargin;
}

// 軌道的水平範圍就是框架排放分頁的範圍，垂直方向則置中於分頁列
- (NSRect)trackRectForTabBarControl:(PSMTabBarControl *)tabBarControl
{
    NSRect cellRect = [tabBarControl genericCellRect];
    NSRect bounds = [tabBarControl bounds];
    return NSMakeRect(NSMinX(cellRect), NSMidY(bounds) - WLCapsuleTrackHeight / 2, NSWidth(cellRect), WLCapsuleTrackHeight);
}

- (NSSize)addTabButtonSizeForTabBarControl:(PSMTabBarControl *)tabBarControl
{
    return NSMakeSize(WLCapsuleTrackHeight, WLCapsuleTrackHeight);
}

- (NSRect)addTabButtonRectForTabBarControl:(PSMTabBarControl *)tabBarControl
{
    if ([(NSView *)[tabBarControl addTabButton] isHidden])
        return NSZeroRect;

    NSRect bounds = [tabBarControl bounds];
    return NSMakeRect(NSMaxX(bounds) - WLCapsuleSideMargin - WLCapsuleTrackHeight,
                      NSMidY(bounds) - WLCapsuleTrackHeight / 2,
                      WLCapsuleTrackHeight,
                      WLCapsuleTrackHeight);
}

- (NSRect)overflowButtonRectForTabBarControl:(PSMTabBarControl *)tabBarControl
{
    if ([(NSView *)[tabBarControl overflowPopUpButton] isHidden])
        return NSZeroRect;

    NSSize size = [tabBarControl overflowButtonSize];
    NSRect trackRect = [self trackRectForTabBarControl:tabBarControl];
    return NSMakeRect(NSMaxX(trackRect) - WLCapsuleOverflowButtonInset - size.width,
                      NSMidY(trackRect) - size.height / 2,
                      size.width,
                      size.height);
}

- (NSRect)dragRectForTabCell:(PSMTabBarCell *)cell ofTabBarControl:(PSMTabBarControl *)tabBarControl
{
    return [cell frame];
}

- (NSRect)closeButtonRectForBounds:(NSRect)theRect ofTabCell:(PSMTabBarCell *)cell
{
    if (![cell shouldDrawCloseButton])
        return NSZeroRect;

    return NSMakeRect(NSMinX(theRect) + WLCapsuleCloseButtonInset,
                      NSMidY(theRect) - WLCapsuleCloseButtonSize / 2,
                      WLCapsuleCloseButtonSize,
                      WLCapsuleCloseButtonSize);
}

- (NSRect)titleRectForBounds:(NSRect)theRect ofTabCell:(PSMTabBarCell *)cell
{
    // 左側固定保留關閉按鈕的位置；若有圖示、處理中指示器或未讀數量，也一併避開
    CGFloat leftReserved = WLCapsuleCloseButtonInset + WLCapsuleCloseButtonSize;
    CGFloat rightReserved = 0;

    NSRect iconRect = [cell iconRectForBounds:theRect];
    if (!NSIsEmptyRect(iconRect))
        leftReserved = MAX(leftReserved, NSMaxX(iconRect) - NSMinX(theRect));

    NSRect indicatorRect = [cell indicatorRectForBounds:theRect];
    if (!NSIsEmptyRect(indicatorRect))
        rightReserved = MAX(rightReserved, NSMaxX(theRect) - NSMinX(indicatorRect));

    NSRect counterRect = [cell objectCounterRectForBounds:theRect];
    if (!NSIsEmptyRect(counterRect))
        rightReserved = MAX(rightReserved, NSMaxX(theRect) - NSMinX(counterRect));

    // 左右留出相同的寬度，標題才會落在分頁的正中央
    CGFloat inset = MAX(leftReserved, rightReserved) + 4.0;
    CGFloat width = NSWidth(theRect) - inset * 2;
    if (width <= 0)
        return NSZeroRect;

    CGFloat textHeight = [[cell attributedStringValue] size].height;
    return NSMakeRect(NSMinX(theRect) + inset, NSMidY(theRect) - textHeight / 2, width, textHeight);
}

#pragma mark 「＋」按鈕

- (NSImage *)addTabButtonImage
{
    return WLAddTabButtonImage(0.0);
}

- (NSImage *)addTabButtonRolloverImage
{
    return WLAddTabButtonImage(0.05);
}

- (NSImage *)addTabButtonPressedImage
{
    return WLAddTabButtonImage(0.12);
}

#pragma mark 標題

- (NSAttributedString *)attributedStringValueForTabCell:(PSMTabBarCell *)cell
{
    NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [paragraphStyle setAlignment:NSTextAlignmentCenter];
    [paragraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];

    BOOL selected = ([cell state] == NSControlStateValueOn);
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:WLCapsuleTitleFontSize],
        NSForegroundColorAttributeName: selected ? [NSColor labelColor] : [NSColor secondaryLabelColor],
        NSParagraphStyleAttributeName: paragraphStyle,
    };
    NSString *title = [cell title] ?: @"";
    return [[[NSAttributedString alloc] initWithString:title attributes:attributes] autorelease];
}

#pragma mark 繪製

- (void)drawBezelOfTabBarControl:(PSMTabBarControl *)tabBarControl inRect:(NSRect)rect
{
    // 主視窗被設為非不透明（setOpaque:NO），分頁列必須自己把底色填滿，否則會透出黑色
    [[NSColor windowBackgroundColor] set];
    NSRectFill([tabBarControl bounds]);

    NSRect trackRect = [self trackRectForTabBarControl:tabBarControl];
    CGFloat radius = NSHeight(trackRect) / 2;
    [[[NSColor labelColor] colorWithAlphaComponent:0.08] set];
    [[NSBezierPath bezierPathWithRoundedRect:trackRect xRadius:radius yRadius:radius] fill];
}

- (void)drawBezelOfTabCell:(PSMTabBarCell *)cell withFrame:(NSRect)frame inTabBarControl:(PSMTabBarControl *)tabBarControl
{
    BOOL selected = ([cell state] == NSControlStateValueOn);
    if (!selected && ![cell isHighlighted])
        return;

    NSRect capsuleRect = NSMakeRect(NSMinX(frame), NSMidY(frame) - WLCapsuleTrackHeight / 2, NSWidth(frame), WLCapsuleTrackHeight);
    capsuleRect = NSInsetRect(capsuleRect, WLCapsuleSelectionInset, WLCapsuleSelectionInset);
    CGFloat radius = NSHeight(capsuleRect) / 2;
    NSBezierPath *capsule = [NSBezierPath bezierPathWithRoundedRect:capsuleRect xRadius:radius yRadius:radius];

    if (!selected) {
        // 滑鼠移入非作用中的分頁
        [[[NSColor labelColor] colorWithAlphaComponent:0.05] set];
        [capsule fill];
        return;
    }

    BOOL dark = WLIsDarkAppearance([tabBarControl effectiveAppearance]);
    NSShadow *shadow = [[[NSShadow alloc] init] autorelease];
    [shadow setShadowColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.2]];
    [shadow setShadowBlurRadius:2.0];
    [shadow setShadowOffset:NSMakeSize(0.0, -0.5)];

    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    [(dark ? [NSColor colorWithCalibratedWhite:1.0 alpha:0.22] : [NSColor whiteColor]) set];
    [capsule fill];
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawTitleOfTabCell:(PSMTabBarCell *)cell withFrame:(NSRect)frame inTabBarControl:(PSMTabBarControl *)tabBarControl
{
    // 框架預設會替標題加上一層白色陰影（舊式浮雕效果），這裡改為直接繪製
    [[cell attributedStringValue] drawInRect:[cell titleRectForBounds:frame]];
}

- (void)drawCloseButtonOfTabCell:(PSMTabBarCell *)cell withFrame:(NSRect)frame inTabBarControl:(PSMTabBarControl *)tabBarControl
{
    // 比照 Finder：滑鼠移入分頁時才顯示關閉按鈕
    BOOL over = [cell closeButtonOver];
    BOOL pressed = [cell closeButtonPressed];
    if (![cell isHighlighted] && !over && !pressed)
        return;

    NSRect buttonRect = [cell closeButtonRectForBounds:frame];
    if (over || pressed) {
        [[[NSColor labelColor] colorWithAlphaComponent:(pressed ? 0.2 : 0.1)] set];
        [[NSBezierPath bezierPathWithOvalInRect:buttonRect] fill];
    }
    WLDrawSymbol(@"xmark", 8.0, NSFontWeightBold, [NSColor secondaryLabelColor], buttonRect);
}

@end

#pragma mark -

@implementation WLTabBarControl

- (void)awakeFromNib
{
    [super awakeFromNib];

    WLCapsuleTabStyle *capsuleStyle = [[WLCapsuleTabStyle alloc] init];
    [self setStyle:(id)capsuleStyle];
    [capsuleStyle release];

    // 不依標題長度決定寬度，並把期望寬度設得比分頁列還寬，框架就會把可用寬度平均分給所有分頁
    [self setSizeCellsToFit:NO];
    [self setCellMaxWidth:WLCapsuleUnlimitedCellWidth];
    [self setCellOptimumWidth:WLCapsuleUnlimitedCellWidth];

    // xib 內的分頁列高度是 22，這裡改為新的高度並維持貼齊上緣
    NSRect frame = [self frame];
    frame.origin.y = NSMaxY(frame) - WLTabBarHeight;
    frame.size.height = WLTabBarHeight;
    [self setFrame:frame];
}

- (void)closeTabClick:(id)sender
{
    NSTabViewItem *item = [sender representedObject];
    [sender retain];
    if(([_cells count] == 1) && (![self canCloseOnlyTab]))
        return;
    
    if ([[self delegate] respondsToSelector:@selector(tabView:shouldCloseTabViewItem:)]) {
        if (![[self delegate] tabView:tabView shouldCloseTabViewItem:item]) {
            // fix mouse downed close button
            [sender setCloseButtonPressed:NO];
            [sender release];
            return;
        }
    }
    
    [item retain];
    
    [tabView removeTabViewItem:item];
    [item release];
    [sender release];
}

- (void)mouseDown:(NSEvent *)theEvent {
    // double click
    if ([theEvent clickCount] > 1) {
        // PSMTabBarControl: detect if on cells
        NSPoint mousePt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
        NSRect cellFrame;
        id cell = [self cellForPoint:mousePt cellFrame:&cellFrame];
        // not on any cell: new tab
        if (!cell) {
            NSButton *button = (NSButton *)[self addTabButton];
            [button performClick:button];
        }
    }
    [super mouseDown:theEvent];
}

- (void)selectTabViewItemAtIndex:(NSInteger)index {
    if ([[self cells] count] > 0 && [[self cells] count] > index) {
        NSTabViewItem *tabViewItem = [[[self cells] objectAtIndex:index] representedObject];
        [[self tabView] selectTabViewItem:tabViewItem];
    }
}

- (void)selectFirstTabViewItem:(id)sender {
    if ([[self cells] count] > 0)
        [self selectTabViewItemAtIndex:0];
}

- (void)selectLastTabViewItem:(id)sender {
    uint count = [[self cells] count];
    if (count > 0)
        [self selectTabViewItemAtIndex:count-1];
}

- (NSInteger)indexOfTabViewItem:(NSTabViewItem *)tabViewItem {
    size_t count = [[self cells] count];
    for (size_t i = 0; i < count; ++i) {
        if ([[[[self cells] objectAtIndex:i] representedObject] isEqualTo:tabViewItem])
            return i;
    }
    return -1;
}

- (void)selectNextTabViewItem:(id)sender {
    NSTabViewItem *sel = [[self tabView] selectedTabViewItem];
    if (sel == nil)
        return;
    int index = [self indexOfTabViewItem:sel] + 1;
    if (index == [[self cells] count])
        index = 0;
    [self selectTabViewItemAtIndex:index];
}

- (void)selectPreviousTabViewItem:(id)sender {
    NSTabViewItem *sel = [[self tabView] selectedTabViewItem];
    if (sel == nil)
        return;
    int index = [self indexOfTabViewItem:sel];
    if (index == 0)
        [self selectLastTabViewItem:sender];
    else
        [self selectTabViewItemAtIndex:index-1];
}

#pragma mark -
- (void)removeTabViewItem:(NSTabViewItem *)tabViewItem {
    int index = [self indexOfTabViewItem:tabViewItem];
    [self closeTabClick:[[self cells] objectAtIndex:index]];
}

#pragma mark - Set main controller
- (void)setMainController:(WLMainFrameController *)controller {
	_currMainController = controller;
}

- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)aTabView
{
    NSArray *tabItems = [tabView tabViewItems];
    // go through cells, remove any whose representedObjects are not in [tabView tabViewItems]
    NSEnumerator *e = [[[_cells copy] autorelease] objectEnumerator];
    PSMTabBarCell *cell;
    while ( (cell = [e nextObject]) ) {
        //remove the observer binding
        if ([cell representedObject] && ![tabItems containsObject:[cell representedObject]]) {
            // see issue #2609
            // -removeTabForCell: comes first to stop the observing that would be triggered in the delegate's call tree
            // below and finally caused a crash.
            [self removeTabForCell:cell];
            
            if ([[self delegate] respondsToSelector:@selector(tabView:didCloseTabViewItem:)]) {
                [[self delegate] tabView:aTabView didCloseTabViewItem:[cell representedObject]];
            }
        }
    }
    
    // go through tab view items, add cell for any not present
    NSMutableArray *cellItems = [self representedTabViewItems];
    NSEnumerator *ex = [tabItems objectEnumerator];
    NSTabViewItem *item;
    while ( (item = [ex nextObject]) ) {
        if (![cellItems containsObject:item]) {
            [self addTabViewItem:item];
        }
    }
    
    // pass along for other delegate responses
    if ([[self delegate] respondsToSelector:@selector(tabViewDidChangeNumberOfTabViewItems:)]) {
        [[self delegate] performSelector:@selector(tabViewDidChangeNumberOfTabViewItems:) withObject:aTabView];
    }
    
    // reset cursor tracking for the add tab button if one exists
    if ([self addTabButton]) [[self addTabButton] resetCursorRects];
}

@end

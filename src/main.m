//
//  main.m
//  Welly
//
//  main.m
//  MacBlueTelnet
//
//  Created by Yung-Luen Lan on 2006/6/9.
//  Copyright yllan.org 2006. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// 註冊成 sleep 的防閒置圖示；整個執行期間都要保留
static NSImage *sAntiIdleImage = nil;

int main(int argc, char *argv[])
{
    // 工具列的防閒置按鈕在介面檔中引用名為 sleep 的圖片（黑色的 sleep.pdf），啟用時不會被系統反白。
    // macOS 27 的按鈕在載入當下就決定圖片的畫法，事後再改圖片的屬性無效，
    // 所以在載入介面檔之前先把系統圖示註冊成同一個名稱。
    @autoreleasepool {
        sAntiIdleImage = [[NSImage imageWithSystemSymbolName:@"zzz" accessibilityDescription:nil] retain];
        [sAntiIdleImage setName:@"sleep"];
    }
    return NSApplicationMain(argc,  (const char **)argv);
}

# Welly-Modify

繁體中文 | [English](#english)

Welly-Modify 是 macOS 上的 BBS 用戶端 Welly 的修改版，以 [clyang/welly](https://github.com/clyang/welly)（Welly - clyang edition）3.2.0 的原始碼為基礎，修正了防閒置、換上仿 Finder 的分頁列樣式，並加入 YouTube 影片連結的內建播放視窗。上游原有的功能見[主要功能](#主要功能)。

![Welly-Modify 的視窗](screenshots/welly-modify.png)

- [下載與安裝](#下載與安裝)
- [本版修改內容](#本版修改內容)
- [主要功能](#主要功能)
- [常見問題](#常見問題)
- [自行編譯](#自行編譯)
- [上游與致謝](#上游與致謝)

## 下載與安裝

最新版：[1.004](https://github.com/Goston/Welly-Modify/releases/latest)

1. 到 [Releases](https://github.com/Goston/Welly-Modify/releases/latest) 下載 `Welly-1.004.zip`。
2. 解壓縮後，把 `Welly.app` 拖到「應用程式」。

系統需求：macOS 12.0 以上，支援 Apple Silicon 與 Intel。

### 第一次打開被擋下怎麼辦？

本 App 沒有 Apple Developer ID 簽章，也未經 Apple 公證（notarization），第一次打開時 macOS 會顯示類似「Apple 無法驗證『Welly』是否為惡意軟體」的警告並拒絕打開。請依下列步驟放行，只需要做一次：

1. 先打開一次 `Welly.app`，在警告視窗按「完成」。
2. 打開「系統設定」>「隱私權與安全性」，向下捲動到「安全性」。
3. 按 Welly 那一項的「強制打開」。這個按鈕只會在嘗試打開 App 之後約一小時內出現。
4. 警告會再出現一次，按「打開」並輸入登入密碼確認，之後就可以正常打開了。

以上步驟依據 Apple 官方文件：[打開來自未知開發者的 Mac App](https://support.apple.com/zh-tw/guide/mac-help/mh40616/mac)。

也可以改在「終端機」執行下列指令，移除下載時被加上的隔離標記：

```
xattr -dr com.apple.quarantine /Applications/Welly.app
```

## 本版修改內容

以下是相對於上游 clyang/welly 3.2.0 的主要修改。

1. **修正防閒置**
    - 防閒置封包由 6 個 NUL 位元組改為 Telnet 的 `IAC DO TIMING-MARK`（`0xFF 0xFD 0x06`）。
    - 接收端會忽略伺服器對防閒置的回應 `IAC WILL TIMING-MARK`（`0xFF 0xFB 0x06`）與 `IAC WONT TIMING-MARK`（`0xFF 0xFC 0x06`），不會把它們當成一般字元畫到畫面上（1.001 起）。
2. **修改視窗樣式**
    - 分頁列改為仿 Finder 的膠囊式樣式：淺灰色膠囊軌道，作用中的分頁以白色膠囊標示，右側為圓形的「+」按鈕。
    - 所有分頁平均分配分頁列寬度，標題置中，滑鼠移入分頁時才顯示關閉按鈕。
    - 支援深色模式，分頁列高度由 22 調整為 34。
    - 修正在新版 macOS 上開啟分頁後，網址列等介面不會更新的問題。
3. **YouTube 影片連結以內建視窗播放**（1.004 起）
    - 點擊文章中的 YouTube 影片連結時，會在 Welly 自己的播放視窗以 YouTube 官方內嵌播放器開啟，不必切換到瀏覽器。影片不會自動播放，按下播放鍵才開始。
    - 支援 `youtube.com/watch?v=`、`youtu.be/`、`/shorts/`、`/live/`、`/embed/` 形式的連結，連結中的起始時間（`t=`、`start=`）也會沿用。
    - 需在偏好設定把「預設處理網址連結方式」設為「內建QuickLook開啟」。設為「外部瀏覽器」或按住 Shift 點擊時，仍會以瀏覽器開啟。
4. **自動更新改用自己的更新來源**
    - 更新來源由上游改為本 repo 的 [update.xml](update.xml)，驗證更新檔用的簽章公鑰（`src/dsa_pub.pem`）也換成 Welly-Modify 自己的，不會再被自動更新成 clyang 版。
5. **版本號重新起算**
    - 版本號不再延續上游，從 1.0 (1) 重新起算。

## 主要功能

以下功能承襲自上游的 clyang 版。

1. **以 WebSocket Secure（`wss://`）連線到 PTT**
    - 密碼不會以明文在網路上傳送。
    - 連接埠 22 與 23 被擋的網路環境也能連線。
2. **文章收藏與推文追蹤**
    - 文章追蹤管理視窗：![文章追蹤管理視窗](https://i.imgur.com/fqSuEwP.png)
    - 新推文通知：![新推文通知](https://i.imgur.com/jQq9LCb.png)
    - 必須以下列其中一種方式連線到 PTT 才能使用：
        - `wss://YOURID@ws.ptt.cc/bbs`
        - `ssh://bbs@ptt.cc/YOURID`
        - `telnet://YOURID@ptt.cc`
    - 在閱讀文章或看板列表時，按 <kbd>Command</kbd>+<kbd>Shift</kbd>+<kbd>A</kbd> 收藏文章。預設只收藏，不追蹤推文。
        - 底色淺綠表示該文章有新推文。
        - 底色紅色表示該文章已經被刪除。
    - 按 <kbd>Command</kbd>+<kbd>.</kbd> 打開收藏文章視窗，雙擊文章即可前往該文，也可以在這裡勾選要追蹤推文的文章。
    - 每 5 分鐘自動檢查被追蹤的文章，有新推文時螢幕右上方會出現提示，點選提示會打開收藏文章視窗。
3. **`wss://` 連線支援自動登入**
4. **內嵌 `telnet` 程式**
    - macOS High Sierra 預設移除了 `telnet`，新購買的 Mac 或重新安裝的系統上沒有這個程式。Welly 自帶一份，不受影響。
5. **一鍵開啟網頁版文章**（<kbd>Command</kbd>+<kbd>P</kbd>）
    - 在文章列表或閱讀文章時，用瀏覽器開啟該篇文章的網頁版，適合圖片很多的文章。
6. **自動分段推文**（<kbd>Command</kbd>+<kbd>M</kbd>）
    - 只需要輸入推文內容，超過長度限制的部分由 Welly 自動分段送出。
    - ![自動分段推文](https://i.imgur.com/0ojoCkv.gif)
7. **推文黑名單**
    - 以站台為單位設定。推文中有黑名單內的 ID 時，該則推文會被暗化顯示。
    - ![推文黑名單](https://i.imgur.com/d2HTnPn.png)
8. **文章長截圖**（<kbd>Command</kbd>+<kbd>/</kbd>）
    - 把多頁的文章完整備份成一張大圖，文章被作者或板主刪除後仍然留有紀錄。
    - 長文會自動分段截圖，每 20 頁產生一張，數百頁的文章也能完整備份。
    - 範例：[https://i.imgur.com/SnWxprv.jpg](https://i.imgur.com/SnWxprv.jpg)
9. **自動更新**
    - 本修改版的更新來源見[本版修改內容](#本版修改內容)。
10. **圖片的 Quick Look 預覽**
    - 在 macOS High Sierra 上也能使用。
11. **全螢幕瀏覽 BBS**

## 常見問題

**Q1：連上後都是亂碼怎麼辦？**

在選單列選「顯示方式」>「編碼」>「正體中文」。

**Q2：推文追蹤會不會偷偷記錄我的密碼，然後在背景幫我登入檢查？**

不會。程式檢查的是 PTT 網頁版的文章，不會記錄您的密碼。

**Q3：每 5 分鐘檢查一次太久了，可以更頻繁嗎？**

不行。為了避免對 PTT 造成阻斷服務（DoS），5 分鐘是寫死在程式中的；每次也只用單一執行緒抓取網頁，降低對 PTT 網頁版前端的影響。

**Q4：換電腦時，追蹤中的文章要怎麼備份？**

把 `~/Library/Application Support/Welly` 裡的 `PttArticle.db` 備份起來，在新電腦上放回同樣的位置即可。

## 自行編譯

專案的部署目標（deployment target）是 macOS 12.0，這是 Xcode 27.2 可接受的最低版本，不需要另外覆寫建置設定：

```
cd src
xcodebuild -project Welly.xcodeproj -scheme Welly -configuration Release build
```

- 這樣只會編出本機的架構。加上 `-destination 'generic/platform=macOS'` 會編出 Apple Silicon 與 Intel 的通用版本。
- 專案沒有設定簽章身分，編出來的 App 是 ad-hoc 簽章。
- Release 組態會把 `Welly.app` 輸出到 `/tmp/Welly.dst/Applications/`。
- 版本號定義在 `src/Welly.xcodeproj/project.pbxproj` 的 `MARKETING_VERSION` 與 `CURRENT_PROJECT_VERSION`。
- 自動更新是以 `CURRENT_PROJECT_VERSION` 和 [update.xml](update.xml) 的 `sparkle:version` 比較。發佈新版時，壓縮檔必須用與 `src/dsa_pub.pem` 對應的私鑰簽章，並把簽章與檔案長度寫進 `update.xml`，否則 App 會拒絕安裝該更新。

## 上游與致謝

Welly-Modify 的基底是 clyang 維護的 [clyang/welly](https://github.com/clyang/welly)（Welly - clyang edition）3.2.0，而 clyang 版又是以 @KOed 的版本為基礎。以下是上游 README 的簡介原文：

> Welly是一套運行在Mac上功能豐富的BBS軟體, 我所維護的版本是基於 @KOed 的版本之上, 做進一步的功能開發以及bug修復.
>
> 特別感謝: @ElvisChiang, @sunghau以及@terces

### 下載上游版本

- 上游的 clyang 版請到 [clyang/welly 的 Releases](https://github.com/clyang/welly/releases) 下載。
- Homebrew 的 `welly` cask 對應的是上游的 clyang 版 3.2.0，不是本修改版。上游提供的安裝指令是 `brew install --cask welly`，但這個 cask 已在 2026-09-01 被 Homebrew 停用（disabled），原因是未通過 macOS 的 Gatekeeper 檢查，詳見 [formulae.brew.sh/cask/welly](https://formulae.brew.sh/cask/welly)。
- 上游 README 對 Homebrew cask 貢獻者的致謝：「Thanks jackblack@ptt to make brew cask happened!」「Thanks ericj@ to update cask to lastest version!」

### 程式相依性

為了以 WebSocket Secure（`wss://`）連線，Welly 內含一支名為 `usock2wsock` 的小程式。原始碼在 [Go-UnixSocket2WebSocket](https://github.com/clyang/Go-UnixSocket2WebSocket)，可以自行編譯。

---

## English

Welly-Modify is a modified version of Welly, a BBS client for macOS. It is based on the source of [clyang/welly](https://github.com/clyang/welly) (Welly - clyang edition) 3.2.0. It fixes anti-idle, replaces the tab bar with a Finder-like style, and adds a built-in player window for YouTube links. Upstream's own features are listed under [Features](#features).

### Download and install

1. Download the latest `Welly-<version>.zip` from [Releases](https://github.com/Goston/Welly-Modify/releases/latest).
2. Unzip it and drag `Welly.app` to Applications.

Requirements: macOS 12.0 or later, Apple Silicon or Intel.

Welly-Modify is not signed with an Apple Developer ID and is not notarized, so macOS blocks it the first time you open it. To allow it (only needed once):

1. Open `Welly.app` once and click "Done" on the warning.
2. Go to System Settings > Privacy & Security and scroll down to Security.
3. Click "Open Anyway" next to Welly. The button is only available for about an hour after you try to open the app.
4. Click "Open" on the warning that appears again and enter your login password.

Or remove the quarantine attribute in Terminal:

```
xattr -dr com.apple.quarantine /Applications/Welly.app
```

### Modifications

Main changes relative to upstream clyang/welly 3.2.0:

1. **Anti-idle fix**
    - The anti-idle packet is now Telnet `IAC DO TIMING-MARK` (`0xFF 0xFD 0x06`) instead of six NUL bytes.
    - The server's replies to it, `IAC WILL TIMING-MARK` (`0xFF 0xFB 0x06`) and `IAC WONT TIMING-MARK` (`0xFF 0xFC 0x06`), are dropped on receipt instead of being drawn as text (since 1.001).
2. **New window style**
    - Finder-like capsule tab bar: a light gray capsule track, a white capsule for the active tab, and a round "+" button on the right.
    - Tabs share the bar width equally with centered titles; the close button only shows on hover.
    - Supports Dark Mode; the tab bar height is changed from 22 to 34.
    - Fixes the address bar (and other UI) not being updated after opening a tab on recent macOS.
3. **Built-in YouTube player window** (since 1.004)
    - Clicking a YouTube video link opens it in Welly's own player window using the official YouTube embedded player, instead of switching to the browser. Videos do not autoplay.
    - Supports `youtube.com/watch?v=`, `youtu.be/`, `/shorts/`, `/live/` and `/embed/` links; a start time in the link (`t=`, `start=`) is honored.
    - Requires "Default URL Open" in Preferences to be set to "Builtin Quicklook". With "External Browser", or when Shift-clicking, links still open in the browser.
4. **Own update feed**
    - The auto-update feed now points to [update.xml](update.xml) in this repo, and the public key used to verify updates (`src/dsa_pub.pem`) is replaced with Welly-Modify's own, so the app is no longer updated back to the clyang edition.
5. **New version numbering**
    - Versions no longer follow upstream and start over from 1.0 (1).

### Features

Inherited from the upstream clyang edition:

1. **Connect to PTT over WebSocket Secure (`wss://`)**
    - Your password is not sent in plain text.
    - Works on networks that block ports 22 and 23.
2. **Article archiving and comment tracking**
3. **Auto-login over `wss://`**
4. **Bundled `telnet`**
    - macOS High Sierra removed the `telnet` command by default; Welly ships its own.
5. **Open the web version of a post** (<kbd>Command</kbd>+<kbd>P</kbd>)
    - Opens the post's PTT web URL in the browser, which is handy for posts with many image links.
6. **Long comments** (<kbd>Command</kbd>+<kbd>M</kbd>)
    - Write a long comment without worrying about the length limit; Welly splits it automatically.
7. **Comment blacklist**
    - Dims comments from the user IDs you list.
8. **Long article screenshots** (<kbd>Command</kbd>+<kbd>/</kbd>)
    - Saves an entire multi-page article as a JPG with one key, paging automatically.
    - Example: [https://i.imgur.com/SnWxprv.jpg](https://i.imgur.com/SnWxprv.jpg)
9. **Auto update**
10. **Quick Look for images**, including on High Sierra
11. **Full screen mode**

### Build

The deployment target is macOS 12.0, the lowest that Xcode 27.2 accepts, so no build setting overrides are needed:

```
cd src
xcodebuild -project Welly.xcodeproj -scheme Welly -configuration Release build
```

This builds for the architecture of your Mac only. Add `-destination 'generic/platform=macOS'` for a universal (Apple Silicon and Intel) build. The Release configuration writes `Welly.app` to `/tmp/Welly.dst/Applications/`.

### Upstream and credits

Welly-Modify is based on [clyang/welly](https://github.com/clyang/welly) (Welly - clyang edition) 3.2.0, maintained by clyang, which is in turn based on @KOed's edition. The introduction from the upstream README:

> Welly is a terminal application on Mac OS X, which aims to bring best user experience for browsing term BBS. My edition is based on @KOed 's great work. This edition provides new features and bug fixes reported by users.
>
> Special Thanks to: @ElvisChiang, @sunghau and @terces

- Download the upstream clyang edition from [its Releases](https://github.com/clyang/welly/releases).
- The Homebrew `welly` cask is the upstream clyang edition 3.2.0, not Welly-Modify. Upstream's install command was `brew install --cask welly`, but Homebrew disabled the cask on 2026-09-01 because it does not pass the macOS Gatekeeper check; see [formulae.brew.sh/cask/welly](https://formulae.brew.sh/cask/welly).
- Upstream's thanks to the cask contributors: "Thanks jackblack@ptt to make brew cask happened!" and "Thanks ericj@ to update cask to lastest version!"
- To make the telnet protocol work over WebSocket Secure (`wss://`), Welly includes a small program called `usock2wsock`. You can get the source and build your own binary from [Go-UnixSocket2WebSocket](https://github.com/clyang/Go-UnixSocket2WebSocket).

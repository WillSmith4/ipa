# Application shortcuts

Long-press an application banner to open the existing Launch App / Hide App
action sheet. iOS now also offers Copy Launch URL, Save App Icon and Create App
Clip. Existing actions and streaming gesture recognition are unchanged.

Copy Launch URL copies `voidlink://launch?host=<host-uuid>&app=<app-id>`.
The URL works both when opening VoidLink and when returning to an open app.
It resolves the saved host, checks its pinned pairing certificate, refreshes
the host and application list, then uses the ordinary stream launch path.
Hidden applications can be launched without changing their hidden flag.
Missing/unpaired/offline hosts, removed apps and invalid URLs produce an error.
An active local stream is not interrupted. A different running app on the host
uses the existing Resume / Quit Running App and Start menu, without an automatic
quit. URLs contain no network addresses, credentials or arbitrary commands.

In Shortcuts on iOS 16+, add **Launch Application in VoidLink** and paste the
copied URL into **Launch URL**. The action opens VoidLink and routes the same
request. The system's **Open URLs** action also works, including on older iOS.

Save App Icon starts a GameDB search using the app name: the first two UTF-16
characters form Sunshine's lowercase alphanumeric bucket, or `@` if empty.
Normalized names use whitespace-to-dot, lowercase prefix matching. Selection
is automatic: exact names first, then matching prefixes in ascending numeric
game-ID order (the bucket's JavaScript Object.keys order). Results without a
cover are skipped. There is no manual cover picker or fuzzy matching. If no
cover is found, the system Files picker opens so you can choose your own image.
Cancel leaves the choice available without creating a placeholder. Imported
images are decoded, oriented and converted to PNG, downsampled to at most
512 pixels. Each candidate is loaded only as needed.
Its IGDB image slug is used with
`https://images.igdb.com/igdb/image/upload/t_thumb_2x/<slug>.png`.
The system Files exporter saves the PNG. Covers are not uploaded to Sunshine,
and its configured banners are not modified.

Create App Clip uses the same search and image. It creates a removable Home
Screen Web Clip profile, like the supplied LiveContainer example (not an
App Store App Clip). The preview offers Install Web Clip and Save Web Clip
Profile. Installation serves just that generated profile over a temporary,
tokenized loopback HTTP address and opens it in Safari. After allowing the
download, install it in **Settings > Profile Downloaded > Install**.
The profile contains only one `com.apple.webClip.managed` payload with the
selected icon and launch URL. Nothing is uploaded. Per-host/app profile IDs
avoid replacing another game's shortcut. The listener expires after five
minutes and closes when the flow is dismissed; downloaded profiles no longer
need it. Exported profiles may also be opened from Files and installed.

`BuildScripts/test-app-shortcuts.sh` tests the actual URL parser, GameDB search
and URL construction, profile serialization, and live loopback HTTP download
with fixture data. It runs in macOS CI before archiving the IPA. Device checks:
cold/warm URL launch, Shortcuts invocation, paired/offline/removed host and app,
running-app conflict, automatic/missing covers, Files export, profile installation,
Home Screen launch and removal. These require an iOS device and paired host.

References: [Apple Web Clip payload](https://developer.apple.com/documentation/devicemanagement/webclip),
[profile installation](https://support.apple.com/en-us/102400),
[App Intents](https://developer.apple.com/documentation/appintents/acceleratingappinteractionswithappintents/).

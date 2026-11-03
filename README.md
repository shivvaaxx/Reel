# Reel

**A clean, native Mac app for downloading videos and photos — from YouTube, Instagram, TikTok and over a thousand other sites.**

Reel is a SwiftUI app for macOS that puts a calm, Apple-style interface on top of the best open-source download tools: [yt-dlp](https://github.com/yt-dlp/yt-dlp) for video and [gallery-dl](https://github.com/mikf/gallery-dl) for photos. Paste a link, press Return, and you're done. It lives in your menu bar, your Share menu, Safari and Shortcuts too, so you can send a link to Reel from wherever you are and keep browsing.

Reel started as a replacement for [MacYTDL](https://github.com/section83/MacYTDL). It keeps what made that app useful and rethinks everything else: one window instead of chains of dialogs, live previews, a Safari-style downloads list, and download tools that keep themselves up to date so things don't quietly break.

---

## Features

### Download from almost anywhere
- **YouTube**: single videos, Shorts, entire playlists and channels.
- **Instagram**: Reels, videos, single photos and multi-photo carousels.
- **TikTok**: videos and photo slideshows.
- **1,000+ other sites**: anything [yt-dlp supports](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md).

### A main window that gets out of the way
- **One link bar.** Paste a link and press Return, or drag a link from Safari anywhere onto the window.
- **Preview before you download.** See the thumbnail, title, channel and duration first, then pick a quality: Best Available, 4K, 1440p, 1080p, 720p, 480p, or Audio Only.
- **Download just a clip.** Click **Trim** on the preview card and set a start and end time, so you only download the part you want.
- **Playlists, your way.** A playlist lists every video with a checkbox. Download all of it, or just the ones you want. Videos you already have start unticked.
- **Photo posts.** Instagram posts and TikTok slideshows show a card that saves every photo and video in the post, with progress like "Saving 3 of 8…".
- **Copied-link suggestions.** If you've just copied a link, Reel offers it as a one-click button. To avoid macOS paste warnings, Reel only checks *that* a link was copied, and reads it only when you click. ⇧⌘V downloads straight from the clipboard.

### Library and subscriptions
- **Library (⌘2):** everything you've downloaded, searchable and filterable by site. Play it, reveal it in Finder, open the original page or download it again.
- **Duplicate detection:** Reel recognises the same video behind different links (youtu.be, Shorts, links with share-tracking parameters) and asks before downloading it twice.
- **Subscriptions (⌘3):** follow a YouTube channel or playlist, and Reel downloads new uploads automatically at the quality you choose.

### Menu bar mode
- **Drop links on the icon.** Drag a link from any app onto Reel's menu bar icon and it downloads at your default quality, with no window and no switching apps. A checkmark confirms the drop landed.
- **Progress at a glance.** The icon fills with a progress ring while downloads run.
- **A panel for everything else.** Click the icon to paste a link, see each download's progress, pause, cancel, retry, or show the file in Finder. It works over full-screen apps too.
- **Run Reel entirely from the menu bar.** Turn off the Dock icon in Settings and Reel becomes a menu bar app. (Reel won't let you hide both the Dock and menu bar icons, so it can never become unreachable.)

### Send links from anywhere
- **Share menu:** choose **Reel** in the Share menu of Safari or any other app.
- **Safari extension:** a toolbar button that sends the page you're on to Reel.
- **Shortcuts:** a "Download with Reel" action for your own shortcuts and automations.
- **Services:** select a link in any app and choose **Services › Download with Reel**.
- **Bookmarklet and `reel://` links:** `reel://download?url=…` works from any browser. Settings › General has a bookmarklet you can drag to your bookmarks bar.

### Accelerated, multi-connection downloads
Like a download manager such as Folx, Reel splits each video into 8 MB segments and downloads them over several connections at once. This makes the biggest difference on YouTube, which limits each connection's speed. In testing, a 4K YouTube video downloaded at about **50 MB/s with 8 connections**, against about 13 MB/s over one.

- **How it works:** yt-dlp chooses the streams. Reel's own Swift downloader fetches their segments in parallel, writing each straight into place. yt-dlp then merges the streams and adds artwork as usual.
- **Resumable:** finished segments are recorded in a small ledger, so pausing or quitting never throws work away.
- **Streaming formats** (HLS/DASH) download their fragments in parallel too.
- **Safe fallback:** if a site doesn't allow segmented downloads, Reel quietly uses a normal single-connection download instead.
- Choose **Off, 4, 8 or 16 connections** in Settings › Downloads. 8 is the default.

### A downloads list like Safari's
- One progress bar per download. It stays accurate even when video and audio download as separate streams and get merged.
- Size, speed and time remaining as each download runs, then plain-English steps afterwards: "Merging video and audio…", "Converting to HEVC…", "Adding artwork…".
- **Pause and resume**, one at a time or with Pause All. Partial downloads pick up where they left off.
- **Downloads survive quitting.** The list is saved, and unfinished downloads continue the next time Reel opens.
- **Cancel** cleans up the half-downloaded files. **Try Again** retries failures with one click.
- **Geo-blocked videos** tell you which countries they *are* available in, so you know whether a proxy will help.
- Several downloads run at once (you choose how many) and the rest wait in a queue.
- Double-click a finished download to play it, or reveal it in Finder, **Add to Photos** or **Add to Music**.
- **Dock badge** with the number of active downloads, and a **notification** when one finishes while you're elsewhere. Clicking the notification shows the file.
- A per-download **log** (right-click › Show Log) for when something goes wrong.

### Downloads on your terms
- **Speed limit**, so a big download doesn't take over your connection.
- **Schedule:** let downloads run only at certain hours, such as overnight.
- **Hotspot-aware:** downloads wait automatically on Personal Hotspot or in Low Data Mode, and continue on a normal network. You can always start one anyway.
- **Proxy** support, for networks that need it.

### Files that just work on your Apple devices
- **QuickTime-compatible by default.** Reel asks for H.264 video and AAC audio, so files play in QuickTime, Photos and on iPhone and iPad.
- **Real 4K that still plays everywhere.** YouTube only serves 4K as VP9/AV1. In compatible mode Reel downloads it anyway and converts it to HEVC using your Mac's hardware video encoder, which is fast and keeps the quality high.
- **Never an unplayable TikTok.** TikTok also serves ByteDance's own video codec, which no Mac can play. Reel always avoids it.
- **Artwork, chapters and details embedded** into each file: thumbnail, title, channel and chapter markers.
- **Optional subtitles**, embedded in the language you choose.
- **Audio only** as AAC (.m4a) or MP3.

### Sign-in, only where you want it
Instagram, sometimes TikTok, and age-restricted YouTube videos only show to signed-in people. In **Settings › Accounts**, Reel can borrow your sign-in from Safari, Chrome, Firefox, Brave or Edge, **for the sites you tick and no others**. Your sign-in is read locally by the download tools and is never sent anywhere else.

> Safari keeps its sign-ins private, so using Safari means giving Reel **Full Disk Access** (System Settings › Privacy & Security). Chrome and other browsers instead show a one-time Keychain prompt; choose **Always Allow**.

### Always up to date
- **Reel updates itself.** It checks for new versions daily (using [Sparkle](https://sparkle-project.org)) and shows you what's new before installing. Every update is verified against Reel's signing key. You can turn this off, or check by hand with **Reel › Check for Updates…**.
- **So do its download tools.** Sites like YouTube and Instagram change all the time, and an out-of-date downloader is the most common reason downloads stop working. On first launch Reel downloads **private copies** of everything it needs. Nothing is installed system-wide, and Homebrew isn't required. yt-dlp and gallery-dl are checked for updates daily, and FFmpeg, Deno and uv monthly. **Settings › Engine** lists every tool's version and lets you update or reinstall them.

| Tool | What Reel uses it for | Source |
|---|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | Finding and downloading videos | Installed from PyPI into a private Python environment |
| [gallery-dl](https://github.com/mikf/gallery-dl) | Saving Instagram and TikTok photos | Same private Python environment |
| [FFmpeg / FFprobe](https://ffmpeg.martin-riedl.de) | Merging streams, clips, HEVC conversion, artwork | Martin Riedl's signed Apple silicon builds |
| [Deno](https://deno.com) | Solving YouTube's JavaScript playback checks | Official release |
| [uv](https://github.com/astral-sh/uv) | Managing that private Python (3.13) | Official release |

Everything lives in `~/Library/Application Support/Reel/`. Delete that folder and Reel simply sets itself up again.

### Settings
- **General:** menu bar icon, Dock icon, download folder, how many downloads run at once, notifications, copied-link suggestions, bookmarklet.
- **Downloads:** default quality, accelerated connections, speed limit, schedule, hotspot behaviour, audio format, QuickTime compatibility and 4K conversion, embedded artwork and details, subtitles.
- **Accounts:** which browser's sign-in to use, and for which sites; proxy.
- **Engine:** app updates, tool versions, automatic tool updates, Update Now, Reinstall All.
- **Support:** ways to support Reel's development.

---

## Install

**Requirements:** a Mac with Apple silicon running **macOS 26 Tahoe or later**.

1. Download the `.dmg` from the [latest release](../../releases/latest).
2. Open it and drag **Reel** into **Applications**.
3. Open Reel. The first time, macOS will say it can't verify the developer, because Reel isn't notarized by Apple yet. Go to **System Settings › Privacy & Security**, scroll down and click **Open Anyway**. You only need to do this once; after that, Reel updates itself.
4. Reel takes a few seconds to download its tools, and then it's ready.

**Optional extras:**
- **Safari extension:** turn on Reel in **Safari › Settings › Extensions**. Because Reel isn't notarized yet, you may first need to enable **Develop › Allow Unsigned Extensions**.
- **Share menu:** if Reel isn't listed, turn it on in **System Settings › General › Login Items & Extensions › Sharing**.

## Scripting

Queue downloads from Terminal, Shortcuts or a script:

```sh
open -a Reel --args --download "https://www.youtube.com/watch?v=…" "https://www.tiktok.com/@…/video/…"

# Pick a quality, or download only part of a video
open -a Reel --args --quality 1080p --download "https://youtu.be/…"
open -a Reel --args --clip 1:20-3:45 --download "https://youtu.be/…"

# Or use the URL scheme from anywhere
open "reel://download?url=https%3A%2F%2Fyoutu.be%2F…"
```

## Build from source

You need Xcode 26 or later (Swift 6.2+) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) for the extensions.

```sh
git clone https://github.com/shivvaaxx/Reel.git
cd Reel
./build.sh        # fetches Sparkle, builds build/Reel.app with its extensions
./make-dmg.sh     # optional: packages build/Reel-<version>.dmg
swift test        # runs the test suite
```

`build.sh` runs `tools/fetch-sparkle.sh`, which downloads a pinned, checksum-verified copy of Sparkle into `Vendor/`. The app itself is a plain Swift package. The Share, Safari and Shortcuts extensions live in `Extensions/` and are built from `Extensions/project.yml`. If you don't have an Apple Development certificate, the build is signed ad hoc, which works but means macOS asks for permissions again after each rebuild.

| File | Purpose |
|---|---|
| `ReelApp.swift` | App entry point, windows, menus, Dock/menu bar presence, launch options |
| `ContentView.swift` | Main window: link bar, lookups, downloads list |
| `Cards.swift` | Video (with trimming), playlist and photo-post preview cards |
| `DownloadRow.swift` | Download rows, controls, context menus, geo-block details |
| `LibraryView.swift` / `Store.swift` | Library window and the saved queue and history |
| `SubscriptionsView.swift` / `Subscriptions.swift` | Followed channels and playlists |
| `MenuBar.swift` | Menu bar icon, link drops, progress ring and panel |
| `DownloadQueue.swift` | Queue, running yt-dlp/gallery-dl, progress parsing |
| `Accelerator.swift` | Multi-connection segmented downloader |
| `Converter.swift` | Hardware HEVC conversion |
| `Scheduling.swift` | Speed limit, schedule, hotspot and Low Data Mode holds |
| `Integrations.swift` | Add to Photos and Music |
| `Handoff.swift` | `reel://` links, Services and launch arguments |
| `Updater.swift` | Sparkle auto-updates |
| `Engine.swift` | Installing, locating and updating the tools; link lookups |
| `Models.swift` | Settings, quality options, download arguments, site routing |
| `SetupAndSettings.swift` | First-run setup screen and the Settings window |
| `Clipboard.swift` | Copied-link detection and support links |
| `Shell.swift` | Process, line-buffer and download helpers |
| `Extensions/` | Share, Safari and Shortcuts extensions |
| `tools/MakeIcon.swift` | Renders the app icon |
| `release.sh` | Builds, signs and publishes a release and its update feed |

## Support Reel

Reel is free and open source. If it saves you time, you can support its development on [Ko-fi](https://ko-fi.com/shivvaaxx) or [GitHub Sponsors](https://github.com/sponsors/shivvaaxx). Bug reports and ideas are just as welcome in [Issues](../../issues).

## Please download responsibly

Reel is a tool for saving things you have the right to keep: your own uploads, Creative Commons and public-domain media, or content for personal offline viewing where that's allowed. Respect creators' rights and each site's terms of service.

## Credits

Reel would be nothing without the volunteers behind [yt-dlp](https://github.com/yt-dlp/yt-dlp), [gallery-dl](https://github.com/mikf/gallery-dl), [FFmpeg](https://ffmpeg.org), [Deno](https://deno.com), [uv](https://github.com/astral-sh/uv) and [Sparkle](https://sparkle-project.org). Thanks to [Martin Riedl](https://ffmpeg.martin-riedl.de) for the Apple silicon FFmpeg builds, and to [MacYTDL](https://github.com/section83/MacYTDL) for years of showing what a Mac front end for yt-dlp should do.

## License

[MIT](LICENSE). The tools Reel downloads keep their own licences.

# Reel

**A clean, native Mac app for downloading videos and photos — from YouTube, Instagram, TikTok and over a thousand other sites.**

Reel is a SwiftUI app for macOS that puts a calm, Apple-style interface on top of the best open-source download tools: [yt-dlp](https://github.com/yt-dlp/yt-dlp) for video and [gallery-dl](https://github.com/mikf/gallery-dl) for photos. Paste a link, press Return, and you're done. It lives in your menu bar too, so you can drop a link onto it from Safari and keep browsing.

Reel started as a replacement for [MacYTDL](https://github.com/section83/MacYTDL). It keeps what made that app useful and rethinks everything else: one window instead of chains of dialogs, live previews, a Safari-style downloads list, and download tools that keep themselves up to date so things don't quietly break.

---

## Features

### Download from almost anywhere
- **YouTube** — single videos, Shorts and entire playlists.
- **Instagram** — Reels, videos, single photos and multi-photo carousels.
- **TikTok** — videos and photo slideshows.
- **1,000+ other sites** — anything [yt-dlp supports](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md).

### A main window that gets out of the way
- **One link bar.** Paste a link and press Return, or drag a link from Safari anywhere onto the window.
- **Preview before you download.** See the thumbnail, title, channel and duration first, then pick a quality: Best Available, 4K, 1440p, 1080p, 720p, 480p, or Audio Only.
- **Playlists, your way.** A playlist lists every video with a checkbox. Download all of it, or just the ones you want.
- **Photo posts.** Instagram posts and TikTok slideshows show a card that saves every photo and video in the post.
- **Copied-link suggestions.** If you've just copied a link, Reel offers it as a one-click button. ⇧⌘V downloads straight from the clipboard.

### Menu bar mode
- **Drop links on the icon.** Drag a link from any app onto Reel's menu bar icon and it downloads at your default quality, with no window and no switching apps. A checkmark confirms the drop landed.
- **Progress at a glance.** The icon fills with a progress ring while downloads run.
- **A panel for everything else.** Click the icon to paste a link, see each download's progress, pause, cancel, retry, or show the file in Finder.
- **Run Reel entirely from the menu bar.** Turn off the Dock icon in Settings and Reel becomes a menu bar app. (Reel won't let you hide both the Dock and menu bar icons, so it can never become unreachable.)

### Accelerated, multi-connection downloads
Like a download manager such as Folx, Reel splits each video into 8 MB segments and downloads them over several connections at once. This makes the biggest difference on YouTube, which limits each connection's speed. In testing, a 4K YouTube video downloaded at about **50 MB/s with 8 connections**, against about 13 MB/s over one.

- **How it works:** yt-dlp chooses the streams. Reel's own Swift downloader fetches their segments in parallel, writing each straight into place. yt-dlp then merges the streams and adds artwork as usual.
- **Resumable:** finished segments are recorded in a small ledger, so pausing or quitting never throws work away.
- **Streaming formats** (HLS/DASH) download their fragments in parallel too.
- **Safe fallback:** if a site doesn't allow segmented downloads, Reel quietly uses a normal single-connection download instead.
- Choose **Off, 4, 8 or 16 connections** in Settings › Downloads. 8 is the default.

### A downloads list like Safari's
- One progress bar per download. It stays accurate even when video and audio download as separate streams and get merged.
- Size, speed and time remaining as each download runs, then plain-English steps afterwards: "Merging video and audio…", "Adding artwork…".
- **Pause and resume.** Partial downloads pick up where they left off.
- **Cancel** cleans up the half-downloaded files. **Try Again** retries failures with one click.
- Several downloads run at once (you choose how many) and the rest wait in a queue.
- Double-click a finished download to play it, or reveal it in Finder.
- **Dock badge** with the number of active downloads, and a **notification** when one finishes while you're elsewhere. Clicking the notification shows the file.
- A per-download **log** (right-click › Show Log) for when something goes wrong.

### Files that just work on your Apple devices
- **QuickTime-compatible by default.** Reel asks for H.264 video and AAC audio, so files play in QuickTime, Photos and on iPhone and iPad. On YouTube that usually means up to 1080p; turn the setting off to get 4K and VP9/AV1.
- **Never an unplayable TikTok.** TikTok also serves ByteDance's own video codec, which no Mac can play. Reel always avoids it.
- **Artwork, chapters and details embedded** into each file: thumbnail, title, channel and chapter markers.
- **Optional subtitles**, embedded in the language you choose.
- **Audio only** as AAC (.m4a) or MP3.

### Sign-in for Instagram and TikTok
Instagram, and sometimes TikTok, only show posts to signed-in people. In **Settings › Accounts**, Reel can borrow your sign-in from Safari, Chrome, Firefox, Brave or Edge, **for those two sites only**. Your sign-in is read locally by the download tools and is never sent anywhere else.

> Safari keeps its sign-ins private, so using Safari means giving Reel **Full Disk Access** (System Settings › Privacy & Security). Chrome and other browsers instead show a one-time Keychain prompt; choose **Always Allow**.

### A self-maintaining engine
Sites like YouTube and Instagram change all the time, and an out-of-date downloader is the most common reason downloads stop working. Reel deals with this itself:

- On first launch Reel downloads **private copies** of everything it needs and shows each one's progress. Nothing is installed system-wide, and Homebrew isn't required.
- **yt-dlp and gallery-dl are checked for updates daily**; FFmpeg, Deno and uv monthly. You can also update or reinstall everything from **Settings › Engine**, which also lists every tool's version.

| Tool | What Reel uses it for | Source |
|---|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | Finding and downloading videos | Official standalone macOS build |
| [FFmpeg / FFprobe](https://ffmpeg.martin-riedl.de) | Merging streams, converting audio, embedding artwork | Martin Riedl's signed Apple silicon builds |
| [Deno](https://deno.com) | Solving YouTube's JavaScript playback checks | Official release |
| [gallery-dl](https://github.com/mikf/gallery-dl) | Saving Instagram and TikTok photos | Installed from PyPI into a private Python environment |
| [uv](https://github.com/astral-sh/uv) | Managing that private Python (3.13) | Official release |

Everything lives in `~/Library/Application Support/Reel/`. Delete that folder and Reel simply sets itself up again.

### Settings
- **General:** menu bar icon, Dock icon, download folder, how many downloads run at once, notifications, copied-link suggestions.
- **Downloads:** default quality, accelerated connections, audio format, QuickTime compatibility, embedded artwork and details, subtitles and their language.
- **Accounts:** which browser's sign-in to use for Instagram and TikTok.
- **Engine:** tool versions, automatic updates, Update Now, Reinstall All.

---

## Install

**Requirements:** a Mac with Apple silicon running **macOS 26 Tahoe or later**.

1. Download `Reel.dmg` from the [latest release](../../releases/latest).
2. Open it and drag **Reel** into **Applications**.
3. Open Reel. The first time, macOS will say it can't verify the developer, because Reel isn't notarized by Apple. Go to **System Settings › Privacy & Security**, scroll down and click **Open Anyway**. You only need to do this once.
4. Reel takes a few seconds to download its tools, and then it's ready.

## Scripting

Queue downloads from Terminal, Shortcuts or a script:

```sh
open -a Reel --args --download "https://www.youtube.com/watch?v=…" "https://www.tiktok.com/@…/video/…"
```

## Build from source

You need Xcode 26 or later (Swift 6.2+).

```sh
git clone https://github.com/shivvaaxx/Reel.git
cd Reel
./build.sh        # builds build/Reel.app
./make-dmg.sh     # optional: packages build/Reel.dmg
```

The project is a plain Swift package, with no Xcode project to maintain.

| File | Purpose |
|---|---|
| `ReelApp.swift` | App entry point, window, Dock/menu bar presence, quit confirmation |
| `ContentView.swift` | Main window: link bar, lookups, downloads list |
| `Cards.swift` | Video, playlist and photo-post preview cards |
| `DownloadRow.swift` | Download rows, controls and context menus |
| `MenuBar.swift` | Menu bar icon, link drops, progress ring and panel |
| `DownloadQueue.swift` | Queue, running yt-dlp/gallery-dl, progress parsing |
| `Accelerator.swift` | Multi-connection segmented downloader and its download plan |
| `Engine.swift` | Installing, locating and updating the tools; link lookups |
| `Models.swift` | Settings, quality options, download arguments, site routing |
| `SetupAndSettings.swift` | First-run setup screen and the Settings window |
| `Shell.swift` | Process, line-buffer and download helpers |
| `tools/MakeIcon.swift` | Renders the app icon |

## Please download responsibly

Reel is a tool for saving things you have the right to keep: your own uploads, Creative Commons and public-domain media, or content for personal offline viewing where that's allowed. Respect creators' rights and each site's terms of service.

## Credits

Reel would be nothing without the volunteers behind [yt-dlp](https://github.com/yt-dlp/yt-dlp), [gallery-dl](https://github.com/mikf/gallery-dl), [FFmpeg](https://ffmpeg.org), [Deno](https://deno.com) and [uv](https://github.com/astral-sh/uv). Thanks to [Martin Riedl](https://ffmpeg.martin-riedl.de) for the Apple silicon FFmpeg builds, and to [MacYTDL](https://github.com/section83/MacYTDL) for years of showing what a Mac front end for yt-dlp should do.

## License

[MIT](LICENSE). The tools Reel downloads keep their own licences.

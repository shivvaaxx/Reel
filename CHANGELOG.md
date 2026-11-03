# Changelog

All notable changes to Reel. Versions follow [semantic versioning](https://semver.org): bug-fix releases bump the last number (1.1.1), new features the middle (1.2.0).

## [Unreleased]

### Added
- **Automatic updates.** Reel checks for new versions daily and shows what's new before installing; updates are verified with a signing key. (People on 1.0 need to download this version once by hand.)
- **Downloads survive quitting.** The list is saved; unfinished downloads continue next time Reel opens, from where they stopped.
- **Library** (⌘2): everything you've downloaded, searchable and filterable by site, with Open Original Page and Download Again.
- **Duplicate detection** across link variants (youtu.be, Shorts, share-tracking parameters); playlists untick videos you already have.
- **Subscriptions** (⌘3): follow a YouTube channel or playlist and new uploads download automatically.
- **4K that plays in QuickTime:** in compatible mode, Reel downloads YouTube's real 4K and converts it to HEVC with your Mac's video encoder.
- **Clip trimming:** download just part of a video (Trim on the preview card, or `--clip 1:20-3:45`).
- **Speed limit, download schedule**, and automatic waiting on Personal Hotspot or Low Data Mode.
- **Geo-blocked videos** now say where they *are* available, and a proxy setting is available.
- **Add to Photos / Add to Music** after downloading.
- Sign-in can be used for any site you choose, including age-restricted YouTube.
- Photo posts show "Saving 3 of 8…"; TikTok photos get readable names.
- Pause All / Resume All, View and Downloads menus, Support tab (Ko-fi and GitHub Sponsors).
- **Send links from anywhere:** a Share menu extension, a Safari toolbar button, a "Download with Reel" Shortcuts action, a Services menu item, a bookmarklet and `reel://download?url=` links.
- Launch options `--quality` (e.g. `1080p`, `4k`, `audio`) and `--clip`.

### Changed
- **New app icon**: a pink-to-indigo tile with a download arrow and play button, with a black arrow in dark mode and a tinted version for tinted icons.
- Reel only checks *whether* a link was copied (no macOS paste warnings) and reads it when you click.
- yt-dlp now runs from Reel's private Python environment: each step starts ~20× faster.
- Builds are signed with a stable identity, so macOS remembers Reel's permissions across updates.

### Fixed
- Release builds can be signed with Developer ID and notarized automatically, so the DMG opens without the "cannot verify" warning.
- Clip downloads and some streaming formats failed because FFmpeg couldn't verify HTTPS certificates.
- A rare crash at launch when the window and the menu bar panel checked the clipboard at the same time.
- Menu bar panel corners and its cut-off header; the panel now works over full-screen apps.

## [1.0.0] - 2026-11-03

First release: native SwiftUI downloader for YouTube, Instagram, TikTok and 1,000+ sites, with a menu bar drop target, multi-connection accelerator, previews, playlists, QuickTime-compatible files, and self-updating download tools.

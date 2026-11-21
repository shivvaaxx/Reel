# Security Policy

## Supported versions

Only the latest release gets security fixes. Reel updates itself, so the fix reaches everyone through the normal update.

| Version | Supported |
|---|---|
| Latest release (1.4.x) | Yes |
| Anything older | No: update to the latest |

## Reporting a vulnerability

**Please don't open a public issue for a security problem.**

Report it privately through GitHub: go to the [Security tab](https://github.com/shivvaaxx/Reel/security) and choose **Report a vulnerability**. Only the maintainer can see the report.

Please include:
- what an attacker could do, and what they would need (a malicious link, a file on disk, a network position…)
- the steps to reproduce it, and the Reel and macOS versions
- a proof of concept if you have one

You'll get a reply within 7 days. Once a fix ships, the advisory is published and you're credited, unless you'd rather not be.

## What's in scope

- **The app:** Reel itself, its Share, Safari and Shortcuts extensions, and its `reel://` link handler.
- **Updates:** Reel's update feed (`appcast.xml`) and the release DMGs. Releases are signed with Developer ID and notarized by Apple, and updates are verified with an EdDSA signature before they install.
- **The download tools:** on first launch Reel downloads FFmpeg, Deno and uv over HTTPS from their publishers, then installs yt-dlp and gallery-dl from PyPI with uv. A way to make Reel fetch or run something other than those tools is in scope.
- **Your data:** if you allow it, Reel reads your browser's sign-in for the sites you choose. It's passed only to the local download tools. Anything that would send it, or your download history, off your Mac is in scope.

## What's not in scope

- Bugs in yt-dlp, gallery-dl, FFmpeg, Deno or uv themselves: report those to their projects.
- Problems that need someone to already control your Mac or your user account.
- Whether a site allows downloading its content: that's between you and the site.

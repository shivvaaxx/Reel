# Contributing to Reel

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug or asking for a feature

Open an [issue](https://github.com/shivvaaxx/Reel/issues/new/choose) and pick a template. For a download that fails, include the link (if it's public), the message Reel shows and the log: right-click the download and choose **Show Log**.

Security problems go through the private process in [SECURITY.md](SECURITY.md), not a public issue.

## Building

You need a Mac with Apple silicon, macOS 26 or later, and Xcode 26.

```bash
./build.sh        # builds build/Reel.app with its extensions
swift test        # runs the tests
```

`build.sh` fetches a pinned, checksum-verified copy of Sparkle into `Vendor/`. Without an Apple Development certificate the build is signed ad hoc, which works, but macOS will ask for permissions again after each rebuild.

## Pull requests

- **Keep each PR to one change.** A fix and a redesign are two PRs.
- **Match the code around you.** SwiftUI, one view per responsibility, and the styles in `Sources/Reel/Look.swift` rather than new colours or spacing.
- **Add a test** in `Tests/ReelTests` for logic changes (argument building, parsing, naming). UI changes need a screenshot, light and dark, in the PR.
- **Note user-facing changes** under `## [Unreleased]` in `CHANGELOG.md`, in plain words. Those notes become the release notes and the in-app "What's New".
- **Run `swift test`** before opening the PR.

## What Reel won't take

Features meant to get around paywalls, DRM or access controls, and anything that sends people's data off their Mac.

By contributing, you agree your work is released under the project's [MIT License](LICENSE), and you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

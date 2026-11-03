import Foundation
import Testing
@testable import Reel

@Suite("Link identity")
struct LinkKeyTests {
    @Test("YouTube link variants map to the same video", arguments: [
        "https://www.youtube.com/watch?v=jNQXAC9IVRw",
        "https://youtube.com/watch?v=jNQXAC9IVRw&t=10s",
        "https://m.youtube.com/watch?v=jNQXAC9IVRw",
        "https://youtu.be/jNQXAC9IVRw?si=abc123",
        "https://www.youtube.com/shorts/jNQXAC9IVRw",
        "https://music.youtube.com/watch?v=jNQXAC9IVRw&list=RD",
    ])
    func youtube(_ link: String) {
        #expect(LinkKey.key(for: link) == "youtube:jNQXAC9IVRw")
    }

    @Test func instagramReelAndPostShareTheShortcode() {
        #expect(LinkKey.key(for: "https://www.instagram.com/reel/DWt8RKZDvwG/?igsh=x") == "instagram:DWt8RKZDvwG")
        #expect(LinkKey.key(for: "https://instagram.com/p/DWt8RKZDvwG") == "instagram:DWt8RKZDvwG")
    }

    @Test func tiktokVideoAndPhoto() {
        #expect(LinkKey.key(for: "https://www.tiktok.com/@nasa/video/7094190006482242821?lang=en") == "tiktok:7094190006482242821")
        #expect(LinkKey.key(for: "https://www.tiktok.com/@nasa/photo/7300000000000000000") == "tiktok:7300000000000000000")
    }

    @Test func differentVideosDiffer() {
        #expect(LinkKey.key(for: "https://youtu.be/aaaaaaaaaaa") != LinkKey.key(for: "https://youtu.be/bbbbbbbbbbb"))
    }
}

@Suite("Clip times")
struct TimeTextTests {
    @Test(arguments: [("0", 0.0), ("83", 83.0), ("1:23", 83.0), ("1:02:03", 3723.0), ("0:05.5", 5.5)])
    func parses(_ text: String, _ seconds: Double) {
        #expect(TimeText.seconds(text) == seconds)
    }

    @Test(arguments: ["", "abc", "1:2:3:4", "-5", "1::2"])
    func rejects(_ text: String) {
        #expect(TimeText.seconds(text) == nil)
    }

    @Test func clipFileNamesAvoidColons() {
        #expect(DownloadOptions.clock(95) == "1.35")
        #expect(DownloadOptions.clock(3725) == "1.02.05")
    }
}

@Suite("Routing")
struct RoutingTests {
    @Test func photoPostsGoToGalleryDL() {
        #expect(Prefs.kind(for: "https://www.instagram.com/p/ABC123/") == .gallery)
        #expect(Prefs.kind(for: "https://www.tiktok.com/@x/photo/123") == .gallery)
        #expect(Prefs.kind(for: "https://www.instagram.com/reel/ABC123/") == .video)
        #expect(Prefs.kind(for: "https://www.youtube.com/watch?v=x") == .video)
    }

    @Test func siteNames() {
        #expect(Prefs.siteName(for: "https://youtu.be/x") == "YouTube")
        #expect(Prefs.siteName(for: "https://www.vimeo.com/1") == "vimeo.com")
    }
}

@Suite("Download arguments")
struct ArgumentTests {
    private func options(_ quality: Quality, compatible: Bool = true) -> DownloadOptions {
        DownloadOptions(quality: quality, audioFormat: .m4a, folder: URL(fileURLWithPath: "/tmp"),
                        compatible: compatible, embedDetails: true, subtitles: false,
                        subtitleLanguage: "en", connections: 8)
    }

    private func format(_ args: [String]) -> String? {
        args.firstIndex(of: "-f").map { args[$0 + 1] }
    }

    @Test func compatibleModeAsksForH264First() throws {
        let f = try #require(format(options(.p1080).selectionArguments(for: "https://youtu.be/x")))
        #expect(f.hasPrefix("bv[height<=1080][vcodec^=avc]+ba"))
    }

    @Test func tiktokIsAlwaysCompatible() throws {
        let args = options(.best, compatible: false).selectionArguments(for: "https://www.tiktok.com/@a/video/1")
        let f = try #require(format(args))
        #expect(f.contains("vcodec^=avc"))
        #expect(args.contains("vcodec:h264,res,acodec:m4a"))
    }

    @Test func audioOnlyExtracts() {
        let args = options(.audio).selectionArguments(for: "https://youtu.be/x")
        #expect(args.contains("-x"))
        #expect(args.contains("m4a"))
    }

    @Test func clipsUseDownloadSections() {
        var o = options(.best)
        o.clipStart = 80
        o.clipEnd = 125
        let args = o.selectionArguments(for: "https://youtu.be/x")
        let i = args.firstIndex(of: "--download-sections")
        #expect(i.map { args[$0 + 1] } == "*80.00-125.00")
    }

    @Test func fourKInCompatibleModeTakesTheHEVCPath() throws {
        let o = options(.p2160)
        #expect(o.usesHEVCConversion(for: "https://youtu.be/x"))
        let f = try #require(format(o.selectionArguments(for: "https://youtu.be/x")))
        #expect(f.hasPrefix("bv[height<=2160]+ba"))
        #expect(!f.contains("avc"))
        // 1080p and TikTok never need conversion.
        #expect(!options(.p1080).usesHEVCConversion(for: "https://youtu.be/x"))
        #expect(!o.usesHEVCConversion(for: "https://www.tiktok.com/@a/video/1"))
        // Turning compatibility off means no conversion at all.
        #expect(!options(.p2160, compatible: false).usesHEVCConversion(for: "https://youtu.be/x"))
    }

    @Test func speedLimitDisablesTheAccelerator() {
        var o = options(.best)
        #expect(o.canAccelerate)
        o.rateLimit = 2.5
        #expect(!o.canAccelerate)
        let args = o.videoArguments(for: "https://youtu.be/x")
        let i = args.firstIndex(of: "--limit-rate")
        #expect(i.map { args[$0 + 1] } == "2560K")
        #expect(o.galleryArguments(for: "https://instagram.com/p/x").contains("2560K"))
    }

    @Test func linkComesAfterDoubleDash() {
        let args = options(.best).videoArguments(for: "-oops")
        #expect(args.suffix(2) == ["--", "-oops"])
    }
}

@Suite("Schedule")
struct ScheduleTests {
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    @Test func daytimeWindow() {
        #expect(Schedule.isWithinWindow(at(10), start: 9 * 60, end: 17 * 60))
        #expect(!Schedule.isWithinWindow(at(18), start: 9 * 60, end: 17 * 60))
        #expect(!Schedule.isWithinWindow(at(17), start: 9 * 60, end: 17 * 60))   // end is exclusive
    }

    @Test func overnightWindow() {
        #expect(Schedule.isWithinWindow(at(23, 30), start: 23 * 60, end: 7 * 60))
        #expect(Schedule.isWithinWindow(at(3), start: 23 * 60, end: 7 * 60))
        #expect(!Schedule.isWithinWindow(at(12), start: 23 * 60, end: 7 * 60))
    }

    @Test func minutesRoundTrip() {
        #expect(Schedule.minutes(from: Schedule.date(fromMinutes: 95)) == 95)
    }
}

@Suite("Error messages")
struct ErrorTests {
    @Test func stripsExtractorPrefix() {
        let msg = Engine.readableError("ERROR: [youtube] abc123: Video unavailable", fallback: "x")
        #expect(msg == "Video unavailable")
    }

    @Test func geoBlockListsCountries() {
        let output = """
        ERROR: [youtube] abc: The uploader has not made this video available in your country
        This video is available in Germany, Austria, Switzerland.
        You might want to use a VPN or a proxy server (with --proxy) to workaround.
        """
        #expect(Engine.geoRestriction(in: output) == ["Germany", "Austria", "Switzerland"])
        #expect(Engine.readableError(output, fallback: "x").contains("available in Germany, Austria, Switzerland"))
    }

    @Test func geoBlockWithoutCountries() {
        let output = "ERROR: [bbc] x: This video is not available from your location due to geo restriction"
        #expect(Engine.geoRestriction(in: output) == [])
        #expect(Engine.readableError(output, fallback: "x").contains("VPN or a proxy"))
    }

    @Test func longCountryListIsShortened() {
        let output = "not made this video available in your country\nThis video is available in A, B, C, D, E, F."
        #expect(Engine.readableError(output, fallback: "x").hasSuffix("A, B, C and 3 more."))
    }

    @Test func ordinaryErrorsAreNotGeo() {
        #expect(Engine.geoRestriction(in: "ERROR: [youtube] x: Private video") == nil)
    }

    @Test func friendlyKnownCases() {
        #expect(Engine.readableError("ERROR: Unsupported URL: https://x", fallback: "x") == "That site or link isn't supported.")
        #expect(Engine.readableError("nothing useful", fallback: "fallback") == "fallback")
    }
}

@Suite("Launch arguments")
struct QualityArgumentTests {
    @Test func parsesFriendlyNames() {
        #expect(Quality(argument: "1080p") == .p1080)
        #expect(Quality(argument: "4K") == .p2160)
        #expect(Quality(argument: "best") == .best)
        #expect(Quality(argument: "audio") == .audio)
        #expect(Quality(argument: "p720") == .p720)
        #expect(Quality(argument: "potato") == nil)
    }
}

@Suite("What's New")
struct WhatsNewTests {
    @Test func parsesChangelogSections() {
        let text = """

        ### Added
        - **Library** (⌘2): everything you've downloaded.
        - Subscriptions.

        ### Fixed
        - A rare crash
          at launch.
        """
        let sections = WhatsNew.parse(text)
        #expect(sections.map(\.title) == ["Added", "Fixed"])
        #expect(sections[0].items.count == 2)
        #expect(String(sections[0].items[0].characters).hasPrefix("Library (⌘2)"))
        #expect(String(sections[1].items[0].characters) == "A rare crash at launch.")
    }

    @Test func emptyNotesHaveNoSections() {
        #expect(WhatsNew.parse("").isEmpty)
    }
}

@Suite("Subscriptions")
@MainActor
struct SubscriptionWindowTests {
    @Test func channelsReadNewestPlaylistsReadEverything() {
        #expect(Subscriptions.lookupWindow(for: "https://www.youtube.com/@NASA/videos") == Subscriptions.window)
        #expect(Subscriptions.lookupWindow(for: "https://www.youtube.com/channel/UC123/videos") == Subscriptions.window)
        #expect(Subscriptions.lookupWindow(for: "https://youtube.com/playlist?list=PL123&si=abc") == nil)
    }
}

@Suite("Folder index")
struct FolderIndexTests {
    @Test func iCloudPlaceholdersKeepTheirNames() {
        #expect(FolderIndex.placeholderName(".Me at the zoo [jNQXAC9IVRw].mp4.icloud") == "Me at the zoo [jNQXAC9IVRw].mp4")
        #expect(FolderIndex.placeholderName("Episode.mp4") == nil)
    }

    @Test func youTubeIDsInFileNames() {
        #expect(FolderIndex.youTubeID(inName: "Me at the zoo [jNQXAC9IVRw]") == "jNQXAC9IVRw")
        #expect(FolderIndex.youTubeID(inName: "Me at the zoo") == nil)
        #expect(FolderIndex.youTubeID(inName: "Notes [draft]") == nil)
    }

    @Test func stampedFilesAreRecognisedAfterMoving() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("reel-index-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("MasterChef/Season 1")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let original = root.appendingPathComponent("Episode 1.mp4")
        try Data("x".utf8).write(to: original)
        SourceTag.stamp(original, link: "https://youtu.be/jNQXAC9IVRw?si=share")
        let moved = folder.appendingPathComponent("Renamed.mp4")
        try fm.moveItem(at: original, to: moved)
        #expect(SourceTag.read(moved) == "https://youtu.be/jNQXAC9IVRw?si=share")
        let keys = await FolderIndex.keys(in: root, ffprobe: nil, environment: nil)
        #expect(keys == ["youtube:jNQXAC9IVRw"])
    }
}

@Suite("Subscription folders")
@MainActor
struct SubscriptionFolderTests {
    @Test func ownFolderWinsOtherwiseTheDefault() {
        let key = Subscriptions.defaultFolderKey
        let saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.set("/Users/test/iCloud Shows", forKey: key)

        var plain = Subscription(link: "https://youtube.com/playlist?list=PL1", title: "A", quality: "best")
        var own = Subscription(link: "https://youtube.com/playlist?list=PL2", title: "B", quality: "best")
        own.folder = "/Users/test/Downloads/B"
        #expect(Subscriptions.folder(for: plain).path == "/Users/test/iCloud Shows")
        #expect(Subscriptions.folder(for: own).path == "/Users/test/Downloads/B")

        UserDefaults.standard.removeObject(forKey: key)
        #expect(Subscriptions.folder(for: plain) == Prefs.downloadFolder)
        plain.folder = nil
        #expect(Subscriptions.folder(for: own).path == "/Users/test/Downloads/B")
    }
}

@Suite("Matching files to videos by title")
struct TitleMatchTests {
    @Test("yt-dlp file names match their video titles", arguments: [
        ("Celebrity Master Chef (2026) - Tamil S01E04 | Mystery Ingredient Elimination Challenge",
         "Celebrity Master Chef (2026) - Tamil S01E04 ｜ Mystery Ingredient Elimination Challenge"),
        ("Celebrity Master Chef  (2026) - Tamil S01 EP10", "Celebrity Master Chef  (2026) - Tamil S01 EP10"),
        ("AC/DC: Live", "AC⧸DC： Live"),
    ])
    func matches(title: String, fileName: String) {
        #expect(FolderIndex.titleKey(title) == FolderIndex.titleKey(fileName))
    }

    @Test func differentEpisodesDoNotMatch() {
        #expect(FolderIndex.titleKey("Celebrity Master Chef (2026) Tamil S01 EP01")
                != FolderIndex.titleKey("Celebrity Master Chef (2026) Tamil S01 EP02"))
    }
}

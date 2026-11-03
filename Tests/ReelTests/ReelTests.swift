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

    @Test func linkComesAfterDoubleDash() {
        let args = options(.best).videoArguments(for: "-oops")
        #expect(args.suffix(2) == ["--", "-oops"])
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

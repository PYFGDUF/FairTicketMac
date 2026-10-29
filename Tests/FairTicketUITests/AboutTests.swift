import Foundation
import Testing
@testable import FairTicketUI

/// The About panel is the one screen nobody re-reads after it ships, which is exactly
/// how a stale project address survives for years — so the address and the version line
/// are asserted here instead of being trusted to review.
@Suite("关于界面")
struct AboutTests {

    // MARK: Project

    @Test("关于界面里的地址就是 GitHub 项目")
    func aboutPointsAtTheRepository() {
        #expect(FairTicketProject.repositoryAddress == "https://github.com/Tuan-Space/12306FairTicket")
        #expect(FairTicketProject.repositoryURL.absoluteString == FairTicketProject.repositoryAddress)
        #expect(FairTicketProject.repositoryURL.host() == "github.com")
    }

    @Test("地址与显示的仓库名指向同一个仓库")
    func displayNameMatchesTheAddress() {
        // A card that shows one repository and opens another is the failure this
        // guards: the two are edited in different places and only agree by convention.
        #expect(FairTicketProject.repositoryAddress.hasSuffix("/\(FairTicketProject.repositoryDisplayName)"))
    }

    // MARK: Version

    @Test("版本行同时给出短版本号和构建号")
    func versionLineShowsBothNumbers() {
        let version = FairTicketVersion(short: "1.0.0", build: "1")
        #expect(version.displayText == "版本 1.0.0（构建 1）")
    }

    @Test("缺哪一半就只写哪一半，不会打印空括号")
    func versionLineDegradesToWhatIsKnown() {
        #expect(FairTicketVersion(short: "1.0.0").displayText == "版本 1.0.0")
        #expect(FairTicketVersion(build: "7").displayText == "构建 7")
        #expect(FairTicketVersion().displayText == "开发版本")
    }

    @Test("空字符串按缺失处理")
    func blankNumbersCountAsMissing() {
        // `swift test` runs without the app's Info.plist, and an empty string is what a
        // hand-written plist with an unset variable leaves behind.
        #expect(FairTicketVersion(short: "", build: "").displayText == "开发版本")
        #expect(FairTicketVersion(short: "", build: "1").displayText == "构建 1")
    }
}

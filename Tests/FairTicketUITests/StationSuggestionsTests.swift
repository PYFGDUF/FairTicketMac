import Testing
@testable import FairTicketUI

@Suite("车站候选")
struct StationSuggestionsTests {
    private let stations = ["广州南", "上海虹桥", "广州东", "上海", "广州北", "广州"]

    @Test("城市同名车站优先于带方位的车站")
    func exactCityStation() {
        #expect(StationSuggestions.matches(stations, query: "广州") == ["广州", "广州东", "广州北", "广州南"])
        #expect(StationSuggestions.matches(stations, query: "上海") == ["上海", "上海虹桥"])
    }

    @Test("完整站名与首尾空白保留标准名称")
    func fullStation() {
        #expect(StationSuggestions.matches(stations, query: " \n广州南\t") == ["广州南"])
    }

    @Test("精确匹配在截取十二项前排序")
    func exactMatchSurvivesLimit() {
        let names = (1...20).map { "测试\($0)站" } + ["站"]
        let matches = StationSuggestions.matches(names, query: "站")
        #expect(matches.count == 21)
        #expect(matches.prefix(12).first == "站")
    }

    @Test("部分输入仍提供候选，空输入与无匹配清空候选")
    func partialAndEmpty() {
        #expect(StationSuggestions.matches(stations, query: "广") == ["广州", "广州东", "广州北", "广州南"])
        #expect(StationSuggestions.matches(stations, query: " \n").isEmpty)
        #expect(StationSuggestions.matches(stations, query: "不存在").isEmpty)
    }
}

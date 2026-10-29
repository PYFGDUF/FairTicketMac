import Foundation
import Testing
@testable import FairTicketUI

@Suite("日期选择日历")
struct TicketCalendarTests {
    private let calendar = TicketCalendarMonth.calendar

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    @Test("月视图从周一开始，日期连续覆盖六周")
    func monthGrid() throws {
        for monthNumber in 1...12 {
            let month = TicketCalendarMonth(containing: try date(2026, monthNumber, 15))
            #expect(month.days.count == 42)
            #expect(calendar.component(.weekday, from: try #require(month.days.first)) == 2)
            for pair in zip(month.days, month.days.dropFirst()) {
                #expect(calendar.dateComponents([.day], from: pair.0, to: pair.1).day == 1)
            }
            let daysInMonth = try #require(calendar.range(of: .day, in: .month, for: month.start))
            #expect(month.days.filter(month.contains).count == daysInMonth.count)
        }
    }

    @Test("闰年与非闰年的二月天数正确")
    func leapYears() throws {
        let leap = TicketCalendarMonth(containing: try date(2024, 2, 1))
        let century = TicketCalendarMonth(containing: try date(2100, 2, 1))
        #expect(leap.days.filter(leap.contains).count == 29)
        #expect(century.days.filter(century.contains).count == 28)
    }

    @Test("切月保留日期意图并处理跨年和月末")
    func navigation() throws {
        let january = TicketCalendarMonth.move(try date(2026, 12, 31), by: 1, component: .month)
        #expect(calendar.isDate(january, inSameDayAs: try date(2027, 1, 31)))
        let february = TicketCalendarMonth.move(january, by: 1, component: .month)
        #expect(calendar.isDate(february, inSameDayAs: try date(2027, 2, 28)))
        let previousWeek = TicketCalendarMonth.move(try date(2027, 1, 3), by: -7, component: .day)
        #expect(calendar.isDate(previousWeek, inSameDayAs: try date(2026, 12, 27)))
    }
}

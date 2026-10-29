import SwiftUI
import Testing
@testable import FairTicketUI

@Suite("界面字号")
struct TextPreferenceTests {
    @Test("默认字号与异常存储值回退到中号")
    func defaultSize() {
        #expect(TicketTextSize.stored("") == .medium)
        #expect(TicketTextSize.stored("obsolete-value") == .medium)
        #expect(EnvironmentValues().ticketTextSize == .medium)
    }

    @Test("三档字号保持标题、正文和提示的层级")
    func hierarchy() {
        for size in TicketTextSize.allCases {
            let card = Theme.cardTitle.scaledSize(for: size)
            let section = Theme.sectionTitle.scaledSize(for: size)
            let body = Theme.ui(14).scaledSize(for: size)
            #expect(card > section)
            #expect(section > body)
            #expect(body >= 12)
        }
        #expect(Theme.value.scaledSize(for: .small) < Theme.value.scaledSize(for: .medium))
        #expect(Theme.value.scaledSize(for: .medium) < Theme.value.scaledSize(for: .large))
    }
}

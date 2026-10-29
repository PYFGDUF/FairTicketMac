import SwiftUI

public struct AppSettingsView: View {
    @AppStorage(TicketTextSize.storageKey) private var storedSize = TicketTextSize.medium.rawValue

    public init() {}

    public var body: some View {
        TextSizeSettingsContent(selection: Binding(
            get: { TicketTextSize.stored(storedSize) },
            set: { storedSize = $0.rawValue }
        ))
    }
}

struct TextSizeSettingsContent: View {
    @Binding var selection: TicketTextSize
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("显示设置")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textStrong(scheme))

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("字号")
                    .font(Theme.sectionTitle)
                    .foregroundStyle(Theme.textStrong(scheme))
                Picker("字号", selection: $selection) {
                    ForEach(TicketTextSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .font(Theme.ui(15, .medium))
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("界面字号")
                Text("更改会立即应用到所有页面，并自动保存。")
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textSecondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("阅读效果预览")
                    .font(Theme.sectionTitle)
                    .foregroundStyle(Theme.textStrong(scheme))
                Text("查看行程、选择席别，让每一步都清晰。")
                    .font(Theme.value)
                    .foregroundStyle(Theme.text(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text("辅助提示与标题保持明确层级。")
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.textSecondary(scheme))
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.well(scheme), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .padding(Theme.Space.xl)
        .frame(width: 460, alignment: .leading)
        .background(Theme.card(scheme))
        .tint(Theme.brand)
    }
}

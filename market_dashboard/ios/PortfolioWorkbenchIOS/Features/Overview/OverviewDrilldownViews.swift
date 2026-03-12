import SwiftUI

struct OverviewDrilldownTag: Identifiable {
    let id = UUID()
    let text: String
    let tint: Color
}

struct OverviewDrilldownSection: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let bullets: [String]

    init(title: String, body: String, bullets: [String] = []) {
        self.title = title
        self.body = body
        self.bullets = bullets
    }
}

struct OverviewDrilldownItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let accent: Color
    let tags: [OverviewDrilldownTag]
    let sections: [OverviewDrilldownSection]
    let relatedSymbols: [String]
}

struct OverviewDrilldownScreen: View {
    let item: OverviewDrilldownItem

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AppBackdrop {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        heroCard

                        ForEach(item.sections) { section in
                            SectionPanel(title: section.title) {
                                VStack(alignment: .leading, spacing: 12) {
                                    if !section.body.isEmpty {
                                        Text(section.body)
                                            .font(.subheadline)
                                            .foregroundStyle(BrokerPalette.ink)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    if !section.bullets.isEmpty {
                                        VStack(alignment: .leading, spacing: 10) {
                                            ForEach(section.bullets, id: \.self) { bullet in
                                                HStack(alignment: .top, spacing: 10) {
                                                    Circle()
                                                        .fill(item.accent.opacity(0.9))
                                                        .frame(width: 6, height: 6)
                                                        .padding(.top, 7)
                                                    Text(bullet)
                                                        .font(.subheadline)
                                                        .foregroundStyle(BrokerPalette.muted)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if !item.relatedSymbols.isEmpty {
                            SectionPanel(title: "关联持仓") {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(item.relatedSymbols, id: \.self) { symbol in
                                        NavigationLink {
                                            HoldingDetailScreen(symbol: symbol)
                                        } label: {
                                            HStack {
                                                Text(symbol)
                                                    .font(.headline)
                                                    .foregroundStyle(BrokerPalette.ink)
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.footnote.weight(.bold))
                                                    .foregroundStyle(item.accent)
                                            }
                                            .padding(14)
                                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("完整信息")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .tint(item.accent)
                }
            }
        }
    }

    private var heroCard: some View {
        SectionPanel(title: item.title, subtitle: item.subtitle) {
            VStack(alignment: .leading, spacing: 14) {
                if !item.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(item.tags) { tag in
                                TagBadge(text: tag.text, tint: tag.tint)
                            }
                        }
                    }
                }

                Text("点击卡片后的完整说明都会在这里展开，便于直接查看未截断的背景、影响和建议。")
                    .font(.footnote)
                    .foregroundStyle(BrokerPalette.muted)
            }
        }
    }
}

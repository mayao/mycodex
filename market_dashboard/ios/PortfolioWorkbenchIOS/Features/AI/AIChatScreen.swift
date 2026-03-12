import SwiftUI
import PortfolioWorkbenchMobileCore

enum AIChatContext: Identifiable, Equatable {
    case dashboard
    case holding(symbol: String, title: String)

    var id: String {
        switch self {
        case .dashboard:
            return "dashboard"
        case let .holding(symbol, _):
            return "holding-\(symbol)"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard:
            return "基于当前组合总览上下文"
        case let .holding(_, title):
            return "基于 \(title) 的持仓详情上下文"
        }
    }

    var promptSuggestions: [String] {
        switch self {
        case .dashboard:
            return [
                "今天组合最该先处理什么？",
                "哪些持仓最受宏观影响？",
                "给我一个下周执行框架。",
            ]
        case .holding:
            return [
                "这只股票为什么现在还该持有？",
                "什么情况下加仓或减仓？",
                "最先盯的验证点是什么？",
            ]
        }
    }

    var apiContext: PortfolioWorkbenchAPIClient.AIChatContext {
        switch self {
        case .dashboard:
            return .dashboard
        case let .holding(symbol, _):
            return .holding(symbol: symbol)
        }
    }
}

private enum AIChatRole: String {
    case user
    case assistant
}

private struct AIChatBubbleMessage: Identifiable {
    let id = UUID()
    let role: AIChatRole
    let content: String
}

struct AIChatScreen: View {
    let context: AIChatContext

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettingsStore
    @FocusState private var isComposerFocused: Bool

    @State private var messages: [AIChatBubbleMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var engineLabel: String?
    @State private var statusMessage = "直接围绕当前组合或持仓继续追问，回复会走你已配置的大模型。"

    var body: some View {
        NavigationStack {
            AppBackdrop {
                VStack(spacing: 14) {
                    headerCard

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                if messages.isEmpty {
                                    introCard
                                    promptSuggestionStrip
                                } else {
                                    ForEach(messages) { message in
                                        messageBubble(message)
                                            .id(message.id)
                                    }
                                }

                                if isSending {
                                    typingBubble
                                        .id("typing-indicator")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 12)
                        }
                        .onChange(of: messages.count, initial: false) { _, _ in
                            scrollToBottom(proxy: proxy)
                        }
                        .onChange(of: isSending, initial: false) { _, _ in
                            scrollToBottom(proxy: proxy)
                        }
                    }

                    composerBar
                }
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .navigationTitle("AI 深聊")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .tint(BrokerPalette.cyan)
                }
            }
        }
    }

    private var headerCard: some View {
        SectionPanel(title: "自由互动入口", subtitle: context.subtitle) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TagBadge(text: "对话模式", tint: BrokerPalette.cyan)
                    if let engineLabel, !engineLabel.isEmpty {
                        TagBadge(text: engineLabel, tint: BrokerPalette.gold)
                    }
                }

                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(BrokerPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
    }

    private var introCard: some View {
        SectionPanel(title: "你可以直接追问") {
            Text("这里不会只停留在顶部那次 AI 洞察刷新，而是允许你继续围绕仓位、风险、催化、执行框架做更细的追问。")
                .font(.subheadline)
                .foregroundStyle(BrokerPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var promptSuggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(context.promptSuggestions, id: \.self) { suggestion in
                    Button {
                        Task { await submit(text: suggestion) }
                    } label: {
                        Text(suggestion)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BrokerPalette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(BrokerPalette.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("继续追问更细的判断或执行动作", text: $draft, axis: .vertical)
                .lineLimit(1 ... 5)
                .focused($isComposerFocused)
                .padding(14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .foregroundStyle(BrokerPalette.ink)

            Button {
                Task { await submit(text: draft) }
            } label: {
                Image(systemName: isSending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(canSend ? BrokerPalette.cyan : BrokerPalette.muted)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    @ViewBuilder
    private func messageBubble(_ message: AIChatBubbleMessage) -> some View {
        HStack {
            if message.role == .assistant {
                bubble(message.content, role: .assistant)
                Spacer(minLength: 36)
            } else {
                Spacer(minLength: 36)
                bubble(message.content, role: .user)
            }
        }
    }

    private var typingBubble: some View {
        HStack {
            bubble("AI 正在整理更细的判断…", role: .assistant)
            Spacer(minLength: 36)
        }
    }

    private func bubble(_ text: String, role: AIChatRole) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(role == .assistant ? BrokerPalette.ink : Color.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                role == .assistant
                    ? BrokerPalette.panelStrong.opacity(0.96)
                    : BrokerPalette.cyan,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(role == .assistant ? BrokerPalette.line : BrokerPalette.cyan.opacity(0.2), lineWidth: 1)
            )
            .fixedSize(horizontal: false, vertical: true)
    }

    private func submit(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else {
            return
        }

        if draft == text {
            draft = ""
        }

        let userMessage = AIChatBubbleMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        isSending = true
        statusMessage = "正在向已配置的大模型请求更细的上下文回复…"

        do {
            let client = try await settings.makeValidatedClient()
            let response = try await client.sendAIChat(
                context: context.apiContext,
                messages: messages.map {
                    PortfolioWorkbenchAPIClient.AIChatMessage(
                        role: $0.role.rawValue,
                        content: $0.content
                    )
                }
            )
            messages.append(AIChatBubbleMessage(role: .assistant, content: response.reply))
            engineLabel = response.engineLabel ?? engineLabel
            statusMessage = response.statusMessage
        } catch {
            messages.append(AIChatBubbleMessage(role: .assistant, content: "请求失败：\(error.localizedDescription)"))
            statusMessage = error.localizedDescription
        }

        isSending = false
        isComposerFocused = false
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if isSending {
            proxy.scrollTo("typing-indicator", anchor: .bottom)
            return
        }
        guard let lastID = messages.last?.id else {
            return
        }
        proxy.scrollTo(lastID, anchor: .bottom)
    }
}

import Foundation

public enum PortfolioWorkbenchLocalMock {
    public static let mockPhoneNumber = "13800138000"
    public static let mockVerificationCode = "123456"

    public static func isMockPhoneNumber(_ phoneNumber: String) -> Bool {
        normalizedPhone(phoneNumber) == mockPhoneNumber
    }

    public static func matchesMockCredentials(phoneNumber: String, code: String) -> Bool {
        isMockPhoneNumber(phoneNumber)
            && code.trimmingCharacters(in: .whitespacesAndNewlines) == mockVerificationCode
    }

    public static func makePhoneCodePayload(phoneNumber: String) -> PhoneCodeRequestPayload {
        let normalized = normalizedPhone(phoneNumber)
        let message: String
        if normalized == mockPhoneNumber {
            message = "当前为本地 mock 模式，固定验证码 \(mockVerificationCode) 已就绪，可直接继续登录。"
        } else {
            message = "当前为本地 mock 模式。请使用默认手机号 \(mockPhoneNumber) 和验证码 \(mockVerificationCode)。"
        }
        return PhoneCodeRequestPayload(
            message: message,
            expiresInSeconds: 300,
            debugCode: mockVerificationCode
        )
    }

    public static func makePhoneSession(phoneNumber: String = mockPhoneNumber) -> MobileSessionPayload {
        let normalized = normalizedPhone(phoneNumber)
        let suffix = String(normalized.suffix(4))
        let user = MobileUser(
            userId: "mock-user-phone-\(suffix)",
            displayName: "Mock 用户 \(suffix)",
            phoneNumberMasked: maskedPhone(normalized),
            authProvider: "phone",
            isOwner: true
        )
        return MobileSessionPayload(
            sessionToken: "local-mock-phone-\(suffix)",
            user: user,
            message: "已进入本地 mock 手机号登录，首页数据来自本地演示快照。"
        )
    }

    public static func makeWeChatSession(displayName: String? = nil) -> MobileSessionPayload {
        let nickname = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = nickname?.isEmpty == false ? nickname! : "微信 Mock 用户"
        let user = MobileUser(
            userId: "mock-user-wechat",
            displayName: resolvedName,
            phoneNumberMasked: nil,
            authProvider: "wechat",
            isOwner: true
        )
        return MobileSessionPayload(
            sessionToken: "local-mock-wechat",
            user: user,
            message: "已进入本地 mock 微信登录，后续可再切回真实服务联调。"
        )
    }

    public static func makeClient(
        currentUser: MobileUser?,
        sessionToken: String?
    ) -> PortfolioWorkbenchAPIClient {
        PortfolioWorkbenchAPIClient(
            configuration: AppServerConfiguration(
                baseURL: URL(string: "http://local-mock.invalid/")!,
                sessionToken: sessionToken ?? "local-mock"
            ),
            session: LocalMockURLSession(currentUser: currentUser, sessionToken: sessionToken)
        )
    }

    private static func normalizedPhone(_ phoneNumber: String) -> String {
        phoneNumber.filter(\.isNumber)
    }

    private static func maskedPhone(_ phoneNumber: String) -> String? {
        guard phoneNumber.count >= 7 else {
            return phoneNumber.isEmpty ? nil : phoneNumber
        }
        return "\(phoneNumber.prefix(3))****\(phoneNumber.suffix(4))"
    }
}

private final class LocalMockURLSession: URLSessioning {
    private let currentUser: MobileUser?
    private let sessionToken: String?
    private let encoder: JSONEncoder

    init(currentUser: MobileUser?, sessionToken: String?) {
        self.currentUser = currentUser
        self.sessionToken = sessionToken
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let method = (request.httpMethod ?? "GET").uppercased()
        let url = request.url ?? URL(string: "http://local-mock.invalid/")!
        let path = url.path

        switch (method, path) {
        case ("POST", "/api/mobile/auth/phone/request-code"):
            let body = request.jsonBody()
            let phoneNumber = String(describing: body["phone_number"] ?? body["phoneNumber"] ?? "")
            return try response(
                url: url,
                statusCode: 200,
                payload: PortfolioWorkbenchLocalMock.makePhoneCodePayload(phoneNumber: phoneNumber)
            )

        case ("POST", "/api/mobile/auth/phone/verify"):
            let body = request.jsonBody()
            let phoneNumber = String(describing: body["phone_number"] ?? body["phoneNumber"] ?? "")
            let code = String(describing: body["code"] ?? "")
            guard PortfolioWorkbenchLocalMock.matchesMockCredentials(
                phoneNumber: phoneNumber,
                code: code
            ) else {
                return errorResponse(
                    url: url,
                    statusCode: 400,
                    message: "本地 mock 模式只接受手机号 \(PortfolioWorkbenchLocalMock.mockPhoneNumber) 和验证码 \(PortfolioWorkbenchLocalMock.mockVerificationCode)。"
                )
            }
            return try response(
                url: url,
                statusCode: 200,
                payload: PortfolioWorkbenchLocalMock.makePhoneSession(phoneNumber: phoneNumber)
            )

        case ("POST", "/api/mobile/auth/wechat/login"):
            let body = request.jsonBody()
            let displayName = body["display_name"] as? String ?? body["displayName"] as? String
            return try response(
                url: url,
                statusCode: 200,
                payload: PortfolioWorkbenchLocalMock.makeWeChatSession(displayName: displayName)
            )

        case ("GET", "/api/mobile/auth/session"):
            guard let user = authenticatedUser else {
                return errorResponse(url: url, statusCode: 401, message: "请先登录本地 mock 账号。")
            }
            return try response(url: url, statusCode: 200, payload: MobileUserEnvelope(user: user))

        case ("GET", "/api/mobile/dashboard"):
            guard authenticatedUser != nil else {
                return errorResponse(url: url, statusCode: 401, message: "请先登录本地 mock 账号。")
            }
            return try response(url: url, statusCode: 200, payload: MockPortfolioFixtures.dashboard)

        case ("GET", "/api/mobile/dashboard-ai"):
            guard authenticatedUser != nil else {
                return errorResponse(url: url, statusCode: 401, message: "请先登录本地 mock 账号。")
            }
            return try response(url: url, statusCode: 200, payload: MockPortfolioFixtures.dashboardAI)

        case ("GET", "/api/mobile/stock-detail"):
            guard authenticatedUser != nil else {
                return errorResponse(url: url, statusCode: 401, message: "请先登录本地 mock 账号。")
            }
            guard let symbol = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "symbol" })?
                .value,
                let payload = MockPortfolioFixtures.holdingDetail(for: symbol) else {
                return errorResponse(url: url, statusCode: 404, message: "本地 mock 详情中没有这个标的。")
            }
            return try response(url: url, statusCode: 200, payload: payload)

        case ("GET", "/api/mobile/stock-detail-ai"):
            guard authenticatedUser != nil else {
                return errorResponse(url: url, statusCode: 401, message: "请先登录本地 mock 账号。")
            }
            guard let symbol = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "symbol" })?
                .value,
                let payload = MockPortfolioFixtures.holdingDetailAI(for: symbol) else {
                return errorResponse(url: url, statusCode: 404, message: "本地 mock AI 详情中没有这个标的。")
            }
            return try response(url: url, statusCode: 200, payload: payload)

        case ("GET", "/api/mobile/import-center"):
            guard let user = authenticatedUser else {
                return errorResponse(url: url, statusCode: 401, message: "请先登录本地 mock 账号。")
            }
            return try response(
                url: url,
                statusCode: 200,
                payload: MockPortfolioFixtures.importCenter(for: user)
            )

        case ("POST", "/api/mobile/ai-chat"):
            guard authenticatedUser != nil else {
                return errorResponse(url: url, statusCode: 401, message: "请先登录本地 mock 账号。")
            }
            let body = request.jsonBody()
            let contextType = String(describing: body["context_type"] ?? body["contextType"] ?? "dashboard")
            let symbol = body["symbol"] as? String
            return try response(
                url: url,
                statusCode: 200,
                payload: MockPortfolioFixtures.chatReply(
                    contextType: contextType,
                    symbol: symbol
                )
            )

        case ("POST", "/api/mobile/auth/logout"):
            return try response(
                url: url,
                statusCode: 200,
                payload: BasicMessagePayload(message: "已退出本地 mock 会话。")
            )

        case ("POST", "/api/mobile/upload-statement"):
            return errorResponse(
                url: url,
                statusCode: 501,
                message: "本地 mock 模式不支持 PDF 上传，请连接真实服务后再试。"
            )

        default:
            return errorResponse(url: url, statusCode: 404, message: "本地 mock 路由不存在。")
        }
    }

    private var authenticatedUser: MobileUser? {
        if let currentUser {
            return currentUser
        }
        if sessionToken?.contains("wechat") == true {
            return PortfolioWorkbenchLocalMock.makeWeChatSession().user
        }
        if sessionToken?.contains("phone") == true {
            return PortfolioWorkbenchLocalMock.makePhoneSession().user
        }
        return nil
    }

    private func response<T: Encodable>(
        url: URL,
        statusCode: Int,
        payload: T
    ) throws -> (Data, URLResponse) {
        let data = try encoder.encode(payload)
        return (
            data,
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }

    private func errorResponse(
        url: URL,
        statusCode: Int,
        message: String
    ) -> (Data, URLResponse) {
        let data = Data("{\"error\":\"\(message.replacingOccurrences(of: "\"", with: "\\\""))\"}".utf8)
        return (
            data,
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }
}

private extension URLRequest {
    func jsonBody() -> [String: Any] {
        guard let httpBody,
              let object = try? JSONSerialization.jsonObject(with: httpBody),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }
}

private enum MockPortfolioFixtures {
    static let generatedAt = "2026-03-11T09:30:00Z"
    static let analysisDateCn = "2026年3月11日"
    static let snapshotDate = "2026-03-10"

    static let positions: [MobilePosition] = [
        MobilePosition(
            symbol: "NVDA",
            name: "英伟达",
            nameEn: "NVIDIA",
            market: "US",
            currency: "USD",
            categoryName: "AI 算力",
            styleLabel: "进攻主线",
            fundamentalLabel: "强",
            weightPct: 26.8,
            statementValueHkd: 2_680_000,
            statementPnlPct: 18.6,
            statementPnlHkd: 420_000,
            currentPrice: 926.4,
            changePct: 2.1,
            changePct5d: 6.8,
            tradeDate: snapshotDate,
            signalScore: 79,
            signalZone: "偏强",
            trendState: "上行延续",
            positionLabel: "趋势主仓",
            macroSignal: "偏多",
            newsSignal: "偏多",
            accountCount: 2,
            stance: "继续持有但不追高",
            role: "组合进攻杠杆",
            summary: "AI 资本开支仍强，仓位承担组合弹性。",
            action: "若放量跌破 5 日线，先回收一成风险预算。",
            watchItems: "关注数据中心资本开支与监管口径变化。",
            sparklinePoints: [100, 103, 106, 108, 110, 113, 117, 121, 124, 128]
        ),
        MobilePosition(
            symbol: "00700.HK",
            name: "腾讯控股",
            nameEn: "Tencent",
            market: "HK",
            currency: "HKD",
            categoryName: "港股互联网",
            styleLabel: "核心底仓",
            fundamentalLabel: "强",
            weightPct: 22.4,
            statementValueHkd: 2_240_000,
            statementPnlPct: 9.3,
            statementPnlHkd: 190_000,
            currentPrice: 376.2,
            changePct: 1.4,
            changePct5d: 3.1,
            tradeDate: snapshotDate,
            signalScore: 71,
            signalZone: "中高位跟踪",
            trendState: "缓步修复",
            positionLabel: "防守中枢",
            macroSignal: "中性",
            newsSignal: "偏多",
            accountCount: 2,
            stance: "持有但控上限",
            role: "现金流稳定器",
            summary: "广告、游戏和回购一起托住估值中枢。",
            action: "若港股互联网情绪继续修复，可保持当前权重。",
            watchItems: "游戏版号、广告景气与回购节奏。",
            sparklinePoints: [100, 99, 101, 102, 104, 105, 104, 106, 107, 109]
        ),
        MobilePosition(
            symbol: "MSTR",
            name: "Strategy",
            nameEn: "MicroStrategy",
            market: "US",
            currency: "USD",
            categoryName: "比特币代理",
            styleLabel: "高波动卫星",
            fundamentalLabel: "中",
            weightPct: 17.6,
            statementValueHkd: 1_760_000,
            statementPnlPct: -6.2,
            statementPnlHkd: -118_000,
            currentPrice: 1_298,
            changePct: -1.9,
            changePct5d: 4.8,
            tradeDate: snapshotDate,
            signalScore: 57,
            signalZone: "波动放大",
            trendState: "高位震荡",
            positionLabel: "弹性仓位",
            macroSignal: "中性",
            newsSignal: "中性",
            accountCount: 2,
            stance: "保留弹性但降波动预期",
            role: "比特币 beta 放大器",
            summary: "方向仍取决于 BTC 走势，但波动远高于现货。",
            action: "若 BTC 回撤叠加 MSTR 失守关键位，优先减仓。",
            watchItems: "比特币 ETF 资金流与可转债相关消息。",
            sparklinePoints: [100, 98, 101, 104, 110, 112, 109, 115, 117, 114]
        ),
        MobilePosition(
            symbol: "AMD",
            name: "AMD",
            nameEn: "Advanced Micro Devices",
            market: "US",
            currency: "USD",
            categoryName: "半导体",
            styleLabel: "进攻副线",
            fundamentalLabel: "中强",
            weightPct: 12.8,
            statementValueHkd: 1_280_000,
            statementPnlPct: 5.4,
            statementPnlHkd: 66_000,
            currentPrice: 184.7,
            changePct: 1.1,
            changePct5d: 2.4,
            tradeDate: snapshotDate,
            signalScore: 63,
            signalZone: "中性偏强",
            trendState: "震荡上修",
            positionLabel: "跟随仓",
            macroSignal: "中性",
            newsSignal: "偏多",
            accountCount: 2,
            stance: "跟随但不抢跑",
            role: "AI 次核心仓位",
            summary: "受益于 AI 主题扩散，但节奏弱于龙头。",
            action: "更适合低吸而不是追涨，控制好与 NVDA 的总暴露。",
            watchItems: "MI 系列订单兑现与 PC 周期恢复。",
            sparklinePoints: [100, 101, 100, 102, 104, 105, 107, 106, 109, 111]
        ),
        MobilePosition(
            symbol: "GLD",
            name: "SPDR Gold Shares",
            nameEn: "GLD",
            market: "US",
            currency: "USD",
            categoryName: "避险资产",
            styleLabel: "对冲仓",
            fundamentalLabel: "中",
            weightPct: 8.4,
            statementValueHkd: 840_000,
            statementPnlPct: 3.2,
            statementPnlHkd: 26_000,
            currentPrice: 219.3,
            changePct: 0.4,
            changePct5d: 1.2,
            tradeDate: snapshotDate,
            signalScore: 61,
            signalZone: "中性跟踪",
            trendState: "稳步抬升",
            positionLabel: "尾部保护",
            macroSignal: "偏多",
            newsSignal: "中性",
            accountCount: 1,
            stance: "保留对冲底仓",
            role: "组合防守缓冲",
            summary: "用来对冲美元利率和风险偏好回落。",
            action: "不需要主动加码，保持现有保护作用即可。",
            watchItems: "实际利率、美元指数与避险需求。",
            sparklinePoints: [100, 100.5, 101, 101.2, 101.6, 102.1, 102.4, 102.8, 103.1, 103.5]
        )
    ]

    static let accounts: [MobileAccount] = [
        MobileAccount(
            accountId: "longbridge_main",
            broker: "Longbridge",
            statementDate: snapshotDate,
            baseCurrency: "HKD",
            navHkd: 4_520_000,
            holdingsValueHkd: 4_100_000,
            financingHkd: 620_000,
            holdingCount: 3,
            tradeCount: 6,
            derivativeCount: 1,
            riskNotes: ["融资余额较高，回撤放大时需要优先控制。"],
            topNames: "腾讯、NVDA、MSTR",
            sourceMode: "upload",
            uploadedAt: "2026-03-10T20:30:00Z",
            loadStatus: "parsed",
            issue: nil,
            fileName: "longbridge_daily_0310.pdf",
            fileExists: true,
            statementType: "longbridge_daily"
        ),
        MobileAccount(
            accountId: "ibkr_alpha",
            broker: "Interactive Brokers",
            statementDate: snapshotDate,
            baseCurrency: "USD",
            navHkd: 3_240_000,
            holdingsValueHkd: 3_020_000,
            financingHkd: 180_000,
            holdingCount: 2,
            tradeCount: 4,
            derivativeCount: 1,
            riskNotes: ["MSTR 与 AI 仓位相关性较高，波动会叠加。"],
            topNames: "NVDA、AMD",
            sourceMode: "cache",
            uploadedAt: nil,
            loadStatus: "cache",
            issue: "当前使用缓存结单，待真实服务重连后可刷新。",
            fileName: "ibkr_daily_0310.pdf",
            fileExists: false,
            statementType: "ibkr_daily"
        ),
        MobileAccount(
            accountId: "tiger_satellite",
            broker: "Tiger",
            statementDate: snapshotDate,
            baseCurrency: "USD",
            navHkd: 2_240_000,
            holdingsValueHkd: 2_050_000,
            financingHkd: 90_000,
            holdingCount: 2,
            tradeCount: 3,
            derivativeCount: 0,
            riskNotes: ["对冲仓位较小，主要依赖大仓位自行控风险。"],
            topNames: "GLD、腾讯",
            sourceMode: "cache",
            uploadedAt: nil,
            loadStatus: "cache",
            issue: "当前使用本地 mock 快照。",
            fileName: "tiger_monthly_0228.pdf",
            fileExists: false,
            statementType: "tiger_monthly"
        )
    ]

    static let recentTrades: [MobileTrade] = [
        MobileTrade(
            date: "2026-03-10",
            symbol: "NVDA",
            name: "英伟达",
            side: "买入",
            quantity: 20,
            price: 914,
            currency: "USD",
            broker: "Interactive Brokers",
            accountId: "ibkr_alpha"
        ),
        MobileTrade(
            date: "2026-03-10",
            symbol: "00700.HK",
            name: "腾讯控股",
            side: "买入",
            quantity: 300,
            price: 369,
            currency: "HKD",
            broker: "Longbridge",
            accountId: "longbridge_main"
        ),
        MobileTrade(
            date: "2026-03-09",
            symbol: "AMD",
            name: "AMD",
            side: "减仓",
            quantity: 40,
            price: 181.2,
            currency: "USD",
            broker: "Interactive Brokers",
            accountId: "ibkr_alpha"
        ),
        MobileTrade(
            date: "2026-03-08",
            symbol: "GLD",
            name: "SPDR Gold Shares",
            side: "买入",
            quantity: 50,
            price: 217.1,
            currency: "USD",
            broker: "Tiger",
            accountId: "tiger_satellite"
        )
    ]

    static let derivatives: [MobileDerivative] = [
        MobileDerivative(
            symbol: "MSTR",
            description: "MSTR 2026-06 1200P",
            currency: "USD",
            quantity: -1,
            marketValue: -14_200,
            unrealizedPnl: 2_400,
            estimatedNotional: 120_000,
            estimatedNotionalHkd: 936_000,
            underlyings: ["MSTR"],
            broker: "Longbridge",
            accountId: "longbridge_main"
        ),
        MobileDerivative(
            symbol: "NVDA",
            description: "NVDA 2026-06 850P",
            currency: "USD",
            quantity: -1,
            marketValue: -9_800,
            unrealizedPnl: 1_180,
            estimatedNotional: 85_000,
            estimatedNotionalHkd: 663_000,
            underlyings: ["NVDA"],
            broker: "Interactive Brokers",
            accountId: "ibkr_alpha"
        )
    ]

    static let dashboard = MobileDashboardPayload(
        generatedAt: generatedAt,
        analysisDateCn: analysisDateCn,
        snapshotDate: snapshotDate,
        hero: MobileDashboardHero(
            title: "MyInvAI",
            subtitle: "本地 mock 组合已就绪，先把登录、首页、持仓和设置流程跑通。",
            overview: "这是一份内置在 App 里的演示快照，目的是在真机联调和签名阶段先验证移动端流程，不依赖短信服务或局域网后端。",
            snapshotWindow: "2026-03-03 至 2026-03-10",
            liveNote: "本地 mock 快照 · 无需连接 Mac 服务",
            macroNote: "本地 mock 主题摘要 · 可用于演示导航与刷新动作",
            primaryTheme: "AI 算力 + 港股互联网",
            primaryBroker: "Longbridge"
        ),
        summaryCards: [
            MobileSummaryCard(label: "净资产", value: "HK$10.00M", detail: "演示快照窗口 2026-03-03 至 2026-03-10", tone: .up),
            MobileSummaryCard(label: "股票市值", value: "HK$8.80M", detail: "5 个核心持仓，AI 与港股互联网为主", tone: .neutral),
            MobileSummaryCard(label: "融资占用", value: "HK$0.89M", detail: "约占净资产 8.9%，仍在可控范围", tone: .warn),
            MobileSummaryCard(label: "衍生品名义敞口", value: "HK$1.60M", detail: "2 条保护性期权仓位", tone: .warn),
            MobileSummaryCard(label: "前五集中度", value: "88.00%", detail: "进攻仓位集中，适合先验证风控提醒", tone: .down),
            MobileSummaryCard(label: "账户覆盖", value: "3 个", detail: "Longbridge / IBKR / Tiger", tone: .neutral)
        ],
        marketPulse: MobileMarketPulse(
            headline: "今日个股固定看三类：头部持仓、近期交易、异常波动",
            summary: "本地 mock 模式下先用演示快照验证你的操作链路。个股固定展示 3 个视角：头部持仓关注 NVDA、近期交易关注 00700.HK、异常波动关注 MSTR。",
            selectionLogic: "市场脉冲里的个股不是“头部持仓”重复列表。它固定从 3 条线各取 1 只：头部持仓按权重取 1 只，近期交易按最近 8 笔唯一成交标的取 1 只，异常波动按日内/5日波动与信号异常取 1 只；如果重复就顺延。",
            catalysts: [
                MobileMarketPulseCatalyst(
                    rawId: "macro-ai",
                    category: "经济/宏观",
                    title: "AI 资本开支仍强",
                    headline: "云厂商与算力链条维持高景气",
                    summary: "这会直接影响 NVDA 与 AMD 的弹性表现。",
                    selectionReason: nil,
                    impactNote: "关联权重约 39.6% · 重点 NVDA、AMD",
                    advice: "如果龙头继续放量上行，优先守住已有利润，不要在加速段无纪律追价。",
                    relatedSymbols: ["NVDA", "AMD"],
                    source: "Local Mock",
                    publishedAt: "2026-03-11T08:00:00Z",
                    tone: .up
                ),
                MobileMarketPulseCatalyst(
                    rawId: "macro-hk-tech",
                    category: "行业/主题",
                    title: "港股互联网情绪回暖",
                    headline: "平台经济估值修复在继续",
                    summary: "腾讯承担组合防守中枢，适合作为波动较低的留仓部分。",
                    selectionReason: nil,
                    impactNote: "关联权重约 22.4% · 重点 00700.HK",
                    advice: "持有即可，真正需要调整的是进攻仓位的总暴露而不是防守底仓。",
                    relatedSymbols: ["00700.HK"],
                    source: "Local Mock",
                    publishedAt: "2026-03-11T08:15:00Z",
                    tone: .neutral
                ),
                MobileMarketPulseCatalyst(
                    rawId: "stock-nvda",
                    category: "个股",
                    title: "NVDA · 英伟达",
                    headline: "AI 主线仍是演示组合的最大进攻仓位",
                    summary: "NVDA 是当前 mock 组合里权重最高的单一持仓，决定了组合的弹性上限。",
                    selectionReason: "头部持仓关注 · 当前第 1 大仓位",
                    impactNote: "入选逻辑：头部持仓关注 · 当前第 1 大仓位 · 权重 26.8% · 最近交易 买入 2026-03-10",
                    advice: "如果龙头继续加速，不要因为强势就继续抬高仓位上限，先守纪律。",
                    relatedSymbols: ["NVDA"],
                    source: "Local Mock",
                    publishedAt: "2026-03-11T08:20:00Z",
                    tone: .up
                ),
                MobileMarketPulseCatalyst(
                    rawId: "stock-tencent",
                    category: "个股",
                    title: "00700.HK · 腾讯控股",
                    headline: "最近交易里最新的核心持仓之一",
                    summary: "腾讯既是防守底仓，也是最近一笔演示买入后的重点复核对象。",
                    selectionReason: "近期交易关注 · 第 2 个唯一成交标的 买入 2026-03-10",
                    impactNote: "入选逻辑：近期交易关注 · 第 2 个唯一成交标的 买入 2026-03-10 · 权重 22.4%",
                    advice: "这类底仓的重点不是追高，而是确认买入后逻辑是否仍成立。",
                    relatedSymbols: ["00700.HK"],
                    source: "Local Mock",
                    publishedAt: "2026-03-11T08:25:00Z",
                    tone: .neutral
                ),
                MobileMarketPulseCatalyst(
                    rawId: "stock-mstr",
                    category: "个股",
                    title: "MSTR · Strategy",
                    headline: "比特币代理仓位弹性仍大，但回撤也会更快",
                    summary: "MSTR 是当前演示组合里最容易放大回撤的仓位。",
                    selectionReason: "异常波动关注 · 日内 -1.90% / 5日 4.80%",
                    impactNote: "入选逻辑：异常波动关注 · 日内 -1.90% / 5日 4.80% · 权重 17.6%",
                    advice: "若 BTC 回落并且 MSTR 失守关键位，先从这里回收风险预算。",
                    relatedSymbols: ["MSTR"],
                    source: "Local Mock",
                    publishedAt: "2026-03-11T08:30:00Z",
                    tone: .warn
                )
            ],
            suggestions: [
                "先确认进攻仓位总暴露是否超出本周容忍度",
                "把 MSTR 当成弹性仓位管理，不当作核心底仓",
                "保留腾讯和 GLD 作为波动缓冲"
            ]
        ),
        sourceHealth: MobileSourceHealth(parsedCount: 1, cachedCount: 2, errorCount: 0),
        keyDrivers: [
            MobileInsightCard(title: "AI 算力主线继续贡献弹性", detail: "NVDA 与 AMD 合计接近四成权重，决定这份演示组合的攻击性。", tone: .up),
            MobileInsightCard(title: "港股平台仓位提供现金流稳定器", detail: "腾讯负责降低整体波动，让组合不至于完全受单一美股主题牵引。", tone: .neutral)
        ],
        riskFlags: [
            MobileInsightCard(title: "集中度偏高", detail: "前五仓位达到 88%，适合在后续真数据接入前先把风险提示和导航流程验证完整。", tone: .down),
            MobileInsightCard(title: "MSTR 与 NVDA 的波动同向放大", detail: "当风险偏好回落时，这两个仓位可能一起拖累净值。", tone: .warn)
        ],
        actionCenter: MobileActionCenter(
            headline: "先把流程跑通，再恢复真实联调",
            overview: "当前阶段的目标不是判断买卖，而是验证真机安装、登录、刷新、详情页跳转和设置页能力。",
            priorityActions: [
                MobilePriorityAction(title: "先用 mock 手机号完成首次登录", detail: "手机号 13800138000，验证码 123456。"),
                MobilePriorityAction(title: "确认首页、持仓、账户、设置 4 个 tab 都能进入", detail: "这一步不依赖局域网后端。"),
                MobilePriorityAction(title: "等签名和网络打通后再切回真实服务地址", detail: "那时再联调短信、上传和实时刷新。")
            ],
            disclaimer: "本地 mock 仅用于演示客户端流程，不代表真实账户或实时行情。"
        ),
        actionBlocks: [
            MobileActionBlock(label: "登录", title: "先跑通手机号 mock 登录", detail: "不用等短信能力，先让用户态和页面状态稳定下来。", badge: "现在可做", tone: .up),
            MobileActionBlock(label: "首页", title: "确认总览卡片和图表都能正常渲染", detail: "这一步主要验证布局、滚动和刷新动作。", badge: "UI 验证", tone: .neutral),
            MobileActionBlock(label: "风险", title: "把高集中度和高波动提示呈现出来", detail: "即使是演示模式，也要让关键风险位在首页可见。", badge: "提示", tone: .warn)
        ],
        aiUpdatedAt: generatedAt,
        aiEngineLabel: "Local Mock Engine",
        healthRadar: [
            MobileRadarMetric(label: "集中度", value: 72, summary: "主线明确但偏集中"),
            MobileRadarMetric(label: "弹性", value: 81, summary: "进攻性强，收益和回撤都会放大"),
            MobileRadarMetric(label: "防守", value: 54, summary: "腾讯和 GLD 提供一定缓冲"),
            MobileRadarMetric(label: "流动性", value: 86, summary: "大部分仓位流动性较好"),
            MobileRadarMetric(label: "执行纪律", value: 64, summary: "需要更清晰的减仓触发器")
        ],
        allocationGroups: MobileAllocationGroups(
            themes: [
                MobileAllocationBucket(label: "AI 算力", valueHkd: 3_960_000, weightPct: 39.6, count: 2, coreHoldings: ["英伟达", "AMD"], coreSymbols: ["NVDA", "AMD"]),
                MobileAllocationBucket(label: "港股互联网", valueHkd: 2_240_000, weightPct: 22.4, count: 1, coreHoldings: ["腾讯控股"], coreSymbols: ["00700.HK"]),
                MobileAllocationBucket(label: "比特币代理", valueHkd: 1_760_000, weightPct: 17.6, count: 1, coreHoldings: ["Strategy"], coreSymbols: ["MSTR"]),
                MobileAllocationBucket(label: "避险资产", valueHkd: 840_000, weightPct: 8.4, count: 1, coreHoldings: ["GLD"], coreSymbols: ["GLD"])
            ],
            markets: [
                MobileAllocationBucket(label: "美股", valueHkd: 6_560_000, weightPct: 65.6, count: 4, coreHoldings: ["NVDA", "MSTR", "AMD"], coreSymbols: ["NVDA", "MSTR", "AMD"]),
                MobileAllocationBucket(label: "港股", valueHkd: 2_240_000, weightPct: 22.4, count: 1, coreHoldings: ["腾讯控股"], coreSymbols: ["00700.HK"])
            ],
            brokers: [
                MobileAllocationBucket(label: "Longbridge", valueHkd: 4_520_000, weightPct: 45.2, count: 1, coreHoldings: ["腾讯", "MSTR"], coreSymbols: ["00700.HK", "MSTR"]),
                MobileAllocationBucket(label: "IBKR", valueHkd: 3_240_000, weightPct: 32.4, count: 1, coreHoldings: ["NVDA", "AMD"], coreSymbols: ["NVDA", "AMD"]),
                MobileAllocationBucket(label: "Tiger", valueHkd: 2_240_000, weightPct: 22.4, count: 1, coreHoldings: ["GLD"], coreSymbols: ["GLD"])
            ]
        ),
        macroTopics: [
            MobileMacroTopic(rawId: "topic-1", name: "AI 资本开支", severity: "高", summary: "云厂商开支预期支撑算力链主线。", headline: "AI 主线仍强", impactLabels: "NVDA / AMD", score: 3, source: "Local Mock", publishedAt: "2026-03-11T08:00:00Z", impactWeightPct: 39.6),
            MobileMacroTopic(rawId: "topic-2", name: "港股平台修复", severity: "中", summary: "回购和现金流改善带来估值修复。", headline: "腾讯承担防守中枢", impactLabels: "00700.HK", score: 1, source: "Local Mock", publishedAt: "2026-03-11T08:15:00Z", impactWeightPct: 22.4),
            MobileMacroTopic(rawId: "topic-3", name: "比特币高波动", severity: "高", summary: "MSTR 的波动会远高于现货本身。", headline: "弹性与风险同时放大", impactLabels: "MSTR", score: -1, source: "Local Mock", publishedAt: "2026-03-11T08:30:00Z", impactWeightPct: 17.6)
        ],
        strategyViews: [
            MobileStrategyCard(title: "进攻主线", tag: "权重 39.6%", tone: .up, summary: "AI 算力依旧是这份演示组合的主要收益来源。"),
            MobileStrategyCard(title: "防守中枢", tag: "权重 30.8%", tone: .neutral, summary: "腾讯与 GLD 负责缓冲情绪和利率扰动。"),
            MobileStrategyCard(title: "弹性卫星", tag: "权重 17.6%", tone: .warn, summary: "MSTR 可以放大利润，但也最容易放大回撤。")
        ],
        positions: positions,
        spotlightPositions: Array(positions.prefix(4)),
        accounts: accounts,
        recentTrades: recentTrades,
        derivatives: derivatives,
        statementSources: [
            MobileStatementSource(accountId: "longbridge_main", broker: "Longbridge", fileExists: true, fileName: "longbridge_daily_0310.pdf", issue: nil, loadStatus: "parsed", sourceMode: "upload", statementDate: snapshotDate, statementType: "longbridge_daily", uploadedAt: "2026-03-10T20:30:00Z"),
            MobileStatementSource(accountId: "ibkr_alpha", broker: "Interactive Brokers", fileExists: false, fileName: "ibkr_daily_0310.pdf", issue: "当前使用缓存快照。", loadStatus: "cache", sourceMode: "cache", statementDate: snapshotDate, statementType: "ibkr_daily", uploadedAt: nil),
            MobileStatementSource(accountId: "tiger_satellite", broker: "Tiger", fileExists: false, fileName: "tiger_monthly_0228.pdf", issue: "当前使用本地演示快照。", loadStatus: "cache", sourceMode: "cache", statementDate: "2026-02-28", statementType: "tiger_monthly", uploadedAt: nil)
        ],
        referenceSources: [
            MobileReferenceSource(label: "组合演示快照", type: "mock", fileName: "embedded-mock-dashboard"),
            MobileReferenceSource(label: "风险与宏观摘要", type: "mock", fileName: "embedded-mock-insights")
        ],
        updateGuide: [
            "如果你现在是在真机上首次打开 App，先用 mock 账号把 UI 和导航全走一遍。",
            "真要联调真实数据时，把服务地址改成这台 Mac 的局域网地址，不要填 127.0.0.1 或 localhost。",
            "短信、上传和实时刷新都依赖后端服务；签名和局域网没打通之前，先以本地 mock 模式验证客户端流程。"
        ]
    )

    static let dashboardAI = MobileDashboardAIRefreshPayload(
        generatedAt: generatedAt,
        analysisDateCn: analysisDateCn,
        actionBlocks: [
            MobileActionBlock(label: "AI", title: "高弹性仓位先看 MSTR", detail: "它最容易放大回撤，优先决定是否降低波动预算。", badge: "优先", tone: .warn),
            MobileActionBlock(label: "AI", title: "NVDA 继续强则守利润", detail: "真正需要的是纪律，不是继续追价。", badge: "跟踪", tone: .up),
            MobileActionBlock(label: "AI", title: "腾讯和 GLD 维持防守缓冲", detail: "在真实数据接通前，不必频繁调整防守仓位。", badge: "稳定", tone: .neutral)
        ],
        aiUpdatedAt: generatedAt,
        aiEngineLabel: "Local Mock Engine",
        aiStatusMessage: "本地 mock AI 已刷新，用于验证按钮、提示和卡片状态。"
    )

    static func importCenter(for user: MobileUser) -> ImportCenterPayload {
        ImportCenterPayload(
            user: user,
            brokers: [
                BrokerCapability(
                    id: "longbridge",
                    name: "Longbridge",
                    crossAppAuthorization: "oauth_supported",
                    officialApiAvailable: true,
                    supportsPositions: true,
                    supportsTrades: true,
                    connectableInApp: false,
                    status: "oauth_or_token",
                    authPath: "OAuth / App Key / Access Token",
                    summary: "后续最接近正式自动化接入的一条路径。",
                    nextStep: "等真机联调稳定后，再补回调、token 存储和刷新。",
                    docsUrl: "https://open.longbridge.com/docs/getting-started",
                    requirements: ["申请应用凭证", "配置回调", "后端安全存储 token"]
                ),
                BrokerCapability(
                    id: "ibkr",
                    name: "IBKR",
                    crossAppAuthorization: "approval_required",
                    officialApiAvailable: true,
                    supportsPositions: true,
                    supportsTrades: true,
                    connectableInApp: false,
                    status: "approval_or_gateway",
                    authPath: "Client Portal Web API / Gateway",
                    summary: "正式接入通常需要审批或额外网关。",
                    nextStep: "先把移动端流程走通，再考虑申请和服务端会话维护。",
                    docsUrl: "https://www.interactivebrokers.com/campus/ibkr-api-page/webapi-doc/",
                    requirements: ["开发者审批", "回调域名", "会话维护"]
                ),
                BrokerCapability(
                    id: "futu",
                    name: "Futu",
                    crossAppAuthorization: "not_direct",
                    officialApiAvailable: true,
                    supportsPositions: true,
                    supportsTrades: true,
                    connectableInApp: false,
                    status: "gateway_required",
                    authPath: "OpenD gateway",
                    summary: "更偏服务端集成，不是手机上的一键跨 App 授权。",
                    nextStep: "短期继续保留 PDF 结单导入。",
                    docsUrl: "https://openapi.futunn.com/futu-api-doc/intro/intro.html",
                    requirements: ["部署 OpenD", "维护登录态", "服务端可达性"]
                )
            ],
            statementTemplates: [
                StatementImportTemplate(id: "tmpl-longbridge-daily", brokerId: "longbridge", broker: "Longbridge", statementType: "daily", label: "长桥日结单", description: "适合先验证上传入口与账户替换流程。"),
                StatementImportTemplate(id: "tmpl-ibkr-daily", brokerId: "ibkr", broker: "Interactive Brokers", statementType: "daily", label: "IBKR 日结单", description: "后续可接入更多账户粒度字段。"),
                StatementImportTemplate(id: "tmpl-futu-monthly", brokerId: "futu", broker: "Futu", statementType: "monthly", label: "富途月结单", description: "先作为缓存/导入链路的演示模板。")
            ],
            notes: [
                "当前是本地 mock 模式，设置页的券商说明主要用于验证内容布局与滚动。",
                "等真机签名、局域网和后端都打通后，再接回真实 OAuth、短信和文件上传。",
                "本地 mock 会话不会动你的真实账户数据。"
            ]
        )
    }

    static func chatReply(
        contextType: String,
        symbol: String?
    ) -> MobileAIChatReplyPayload {
        let trimmedSymbol = symbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reply: String
        if contextType == "holding", let trimmedSymbol, !trimmedSymbol.isEmpty {
            reply = "\(trimmedSymbol) 当前是本地 mock 详情回复。这里主要验证聊天入口、消息列表和请求状态，真实联调时再切回后端 AI。"
        } else {
            reply = "当前是本地 mock 组合回复。你已经不依赖短信和后端就能把登录、首页、持仓、设置和聊天入口跑通。"
        }
        return MobileAIChatReplyPayload(
            reply: reply,
            engineLabel: "Local Mock Engine",
            statusMessage: "本地 mock 回复已返回。"
        )
    }

    static func holdingDetail(for symbol: String) -> HoldingDetailPayload? {
        guard let position = positions.first(where: { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }) else {
            return nil
        }
        let fixture = holdingFixture(for: position.symbol)

        return HoldingDetailPayload(
            generatedAt: generatedAt,
            analysisDateCn: analysisDateCn,
            shareMode: false,
            hero: HoldingDetailHero(
                symbol: position.symbol,
                name: position.name,
                categoryName: position.categoryName,
                styleLabel: position.styleLabel,
                fundamentalLabel: position.fundamentalLabel,
                signalScore: position.signalScore ?? 60,
                signalZone: position.signalZone ?? "中性跟踪",
                trendState: position.trendState ?? "震荡",
                positionLabel: position.positionLabel ?? "观察仓",
                macroSignal: position.macroSignal ?? "中性",
                newsSignal: position.newsSignal ?? "中性",
                currentPrice: position.currentPrice,
                changePct: position.changePct,
                changePct5d: position.changePct5d,
                tradeDate: position.tradeDate,
                priceSource: "local_mock",
                priceSourceLabel: "本地 mock 快照",
                newsHeadline: fixture.newsHeadline
            ),
            sourceMeta: HoldingDetailSourceMeta(
                priceSourceLabel: "本地 mock 快照",
                liveUpdatedAt: generatedAt,
                macroUpdatedAt: generatedAt,
                tradeDate: snapshotDate
            ),
            executiveSummary: fixture.executiveSummary,
            focusCards: [
                HoldingDetailFocusCard(label: "仓位权重", value: String(format: "%.1f%%", position.weightPct), detail: "用于验证详情页顶部摘要卡"),
                HoldingDetailFocusCard(label: "浮盈亏", value: signedPercent(position.statementPnlPct), detail: "本地 mock 里同样保留了收益/回撤表达"),
                HoldingDetailFocusCard(label: "当前角色", value: position.role, detail: position.summary ?? "用于验证说明文案")
            ],
            signalRows: [
                HoldingDetailSignalRow(label: "趋势", score: position.signalScore ?? 60, comment: position.trendState ?? "趋势中性"),
                HoldingDetailSignalRow(label: "宏观", score: fixture.macroScore, comment: position.macroSignal ?? "宏观中性"),
                HoldingDetailSignalRow(label: "消息", score: fixture.newsScore, comment: position.newsSignal ?? "消息中性")
            ],
            signalMatrix: HoldingDetailSignalMatrix(
                columns: [
                    HoldingDetailSignalMatrixColumn(key: "trend", label: "趋势"),
                    HoldingDetailSignalMatrixColumn(key: "macro", label: "宏观"),
                    HoldingDetailSignalMatrixColumn(key: "news", label: "消息")
                ],
                rows: fixture.matrixRows
            ),
            portfolioContext: [
                HoldingDetailLabelValue(label: "角色", value: position.role),
                HoldingDetailLabelValue(label: "策略", value: position.stance),
                HoldingDetailLabelValue(label: "关注点", value: position.watchItems ?? "暂无"),
                HoldingDetailLabelValue(label: "账户数", value: "\(position.accountCount ?? 1) 个")
            ],
            priceCards: [
                HoldingDetailPriceCard(label: "现价", value: decimalString(position.currentPrice), delta: signedPercent(position.changePct)),
                HoldingDetailPriceCard(label: "5日变化", value: signedPercent(position.changePct5d), delta: nil),
                HoldingDetailPriceCard(label: "市值(HKD)", value: groupedCurrency(position.statementValueHkd), delta: nil)
            ],
            accountRows: fixture.accountRows,
            relatedTrades: recentTrades
                .filter { $0.symbol.caseInsensitiveCompare(position.symbol) == .orderedSame }
                .map {
                    HoldingDetailTradeRow(
                        date: $0.date,
                        side: $0.side,
                        broker: $0.broker,
                        quantity: $0.quantity,
                        price: $0.price,
                        currency: $0.currency
                    )
                },
            derivativeRows: derivatives
                .filter { $0.symbol.caseInsensitiveCompare(position.symbol) == .orderedSame }
                .map {
                    HoldingDetailDerivativeRow(
                        symbol: $0.symbol,
                        description: $0.description,
                        estimatedNotionalHkd: $0.estimatedNotionalHkd
                    )
                },
            bullCase: fixture.bullCase,
            bearCase: fixture.bearCase,
            watchlist: fixture.watchlist,
            actionPlan: fixture.actionPlan,
            peers: fixture.peers,
            history: fixture.history,
            comparisonHistory: fixture.comparisonHistory,
            holdingNote: HoldingDetailNote(
                symbol: position.symbol,
                name: position.name,
                weightPct: position.weightPct,
                role: position.role,
                stance: position.stance,
                thesis: position.summary ?? fixture.executiveSummary.joined(separator: " "),
                watchItems: position.watchItems ?? fixture.watchlist.joined(separator: "；"),
                risk: fixture.bearCase.first ?? "关注波动放大。",
                action: position.action ?? fixture.actionPlan.first ?? "继续跟踪。",
                currentPrice: position.currentPrice,
                changePct: position.changePct,
                positionLabel: position.positionLabel,
                trendState: position.trendState,
                macroSignal: position.macroSignal,
                newsSignal: position.newsSignal,
                fundamentalLabel: position.fundamentalLabel,
                signalScore: position.signalScore,
                signalZone: position.signalZone,
                statementPnlPct: position.statementPnlPct,
                statementValueHkd: position.statementValueHkd,
                categoryName: position.categoryName
            )
        )
    }

    static func holdingDetailAI(for symbol: String) -> HoldingDetailAIPayload? {
        guard let position = positions.first(where: { $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }) else {
            return nil
        }
        let fixture = holdingFixture(for: position.symbol)
        return HoldingDetailAIPayload(
            generatedAt: generatedAt,
            analysisDateCn: analysisDateCn,
            executiveSummary: fixture.executiveSummary,
            bullCase: fixture.bullCase,
            bearCase: fixture.bearCase,
            watchlist: fixture.watchlist,
            actionPlan: fixture.actionPlan,
            aiStatusMessage: "本地 mock AI 详情已刷新，重点是验证按钮和详情页文案切换。"
        )
    }

    private static func holdingFixture(for symbol: String) -> MockHoldingFixture {
        switch symbol {
        case "NVDA":
            return MockHoldingFixture(
                executiveSummary: [
                    "NVDA 是演示组合的进攻主线，承担主要收益弹性。",
                    "真实联调前，这里先用本地 mock 数据验证详情页结构和交互。",
                    "策略重点不是追涨，而是明确回撤时如何减仓。"
                ],
                bullCase: ["云厂商资本开支继续上修。", "高端 GPU 供需仍偏紧。"],
                bearCase: ["估值已经高，需要更强的订单兑现。", "若监管口径收紧，波动会明显放大。"],
                watchlist: ["大型云厂商 capex 指引", "竞争对手新品节奏", "美国监管表态"],
                actionPlan: ["继续持有主仓。", "若跌破关键均线先回收一成风险预算。"],
                macroScore: 74,
                newsScore: 79,
                newsHeadline: "AI 开支继续支撑算力龙头强势。",
                accountRows: [
                    HoldingDetailAccountRow(label: "IBKR 主攻", accountId: "ibkr_alpha", quantity: 120, statementValue: 1_180_000, statementPnlPct: 16.2),
                    HoldingDetailAccountRow(label: "Longbridge 协同", accountId: "longbridge_main", quantity: 80, statementValue: 1_500_000, statementPnlPct: 20.4)
                ],
                peers: [
                    peer(symbol: "AMD", name: "AMD", signalScore: 63, trendState: "震荡上修", currentPrice: 184.7, changePct: 1.1, signalZone: "中性偏强"),
                    peer(symbol: "AVGO", name: "Broadcom", signalScore: 70, trendState: "强势整理", currentPrice: 1_442, changePct: 0.8, signalZone: "偏强"),
                    peer(symbol: "TSM", name: "台积电", signalScore: 66, trendState: "稳步抬升", currentPrice: 168.2, changePct: 0.7, signalZone: "中性偏强")
                ],
                matrixRows: [
                    matrixRow(symbol: "NVDA", name: "英伟达", isTarget: true, signalScore: 79, signalZone: "偏强", trendState: "上行延续", trend: 82, macro: 74, news: 79),
                    matrixRow(symbol: "AMD", name: "AMD", isTarget: false, signalScore: 63, signalZone: "中性偏强", trendState: "震荡上修", trend: 66, macro: 62, news: 61),
                    matrixRow(symbol: "TSM", name: "台积电", isTarget: false, signalScore: 66, signalZone: "中性偏强", trendState: "稳步抬升", trend: 68, macro: 64, news: 60)
                ],
                history: history([100, 102, 103, 105, 109, 112, 115, 118, 124, 128]),
                comparisonHistory: [
                    comparison(symbol: "NVDA", name: "英伟达", isTarget: true, values: [100, 102, 103, 105, 109, 112, 115, 118, 124, 128]),
                    comparison(symbol: "AMD", name: "AMD", isTarget: false, values: [100, 100.5, 101, 101.5, 102.5, 103, 104, 105, 107, 109]),
                    comparison(symbol: "TSM", name: "台积电", isTarget: false, values: [100, 100.8, 101.2, 101.9, 102.1, 102.8, 103.5, 104.3, 105.4, 106.1])
                ]
            )

        case "00700.HK":
            return MockHoldingFixture(
                executiveSummary: [
                    "腾讯在演示组合里承担防守中枢，作用是稳住波动。",
                    "它不是最高弹性的仓位，但能给组合现金流和回购支撑。",
                    "详情页的重点是验证“核心底仓”这种角色表达是否足够清楚。"
                ],
                bullCase: ["广告和游戏恢复带来估值修复。", "回购延续会提升下行保护。"],
                bearCase: ["行业监管再度升温。", "港股风险偏好重新走弱。"],
                watchlist: ["版号节奏", "广告景气", "回购进度"],
                actionPlan: ["维持底仓。", "只有情绪过热时才考虑主动降权。"],
                macroScore: 58,
                newsScore: 66,
                newsHeadline: "平台经济情绪修复继续，但弹性仍弱于美股 AI 主线。",
                accountRows: [
                    HoldingDetailAccountRow(label: "Longbridge 主仓", accountId: "longbridge_main", quantity: 3_800, statementValue: 1_430_000, statementPnlPct: 11.2),
                    HoldingDetailAccountRow(label: "Tiger 底仓", accountId: "tiger_satellite", quantity: 1_200, statementValue: 810_000, statementPnlPct: 6.8)
                ],
                peers: [
                    peer(symbol: "03690.HK", name: "美团-W", signalScore: 59, trendState: "震荡修复", currentPrice: 112.4, changePct: 0.9, signalZone: "中性"),
                    peer(symbol: "09988.HK", name: "阿里巴巴-W", signalScore: 57, trendState: "区间震荡", currentPrice: 86.8, changePct: 0.6, signalZone: "中性"),
                    peer(symbol: "META", name: "Meta", signalScore: 69, trendState: "强势整理", currentPrice: 522.1, changePct: 1.2, signalZone: "偏强")
                ],
                matrixRows: [
                    matrixRow(symbol: "00700.HK", name: "腾讯控股", isTarget: true, signalScore: 71, signalZone: "中高位跟踪", trendState: "缓步修复", trend: 70, macro: 58, news: 66),
                    matrixRow(symbol: "03690.HK", name: "美团-W", isTarget: false, signalScore: 59, signalZone: "中性", trendState: "震荡修复", trend: 57, macro: 55, news: 58),
                    matrixRow(symbol: "09988.HK", name: "阿里巴巴-W", isTarget: false, signalScore: 57, signalZone: "中性", trendState: "区间震荡", trend: 55, macro: 54, news: 56)
                ],
                history: history([100, 100.2, 100.8, 101.5, 102.1, 102.8, 103.6, 104.2, 106.4, 109]),
                comparisonHistory: [
                    comparison(symbol: "00700.HK", name: "腾讯控股", isTarget: true, values: [100, 100.2, 100.8, 101.5, 102.1, 102.8, 103.6, 104.2, 106.4, 109]),
                    comparison(symbol: "03690.HK", name: "美团-W", isTarget: false, values: [100, 99.5, 99.9, 100.7, 101.3, 101.8, 102.2, 102.9, 103.7, 104.4]),
                    comparison(symbol: "09988.HK", name: "阿里巴巴-W", isTarget: false, values: [100, 99.2, 99.4, 99.7, 100.1, 100.8, 101.2, 101.9, 102.5, 103.3])
                ]
            )

        case "MSTR":
            return MockHoldingFixture(
                executiveSummary: [
                    "MSTR 是演示组合里波动最大的仓位。",
                    "它提供高弹性，也最容易在风险偏好回落时成为回撤放大器。",
                    "这个详情页主要验证高风险提示、对冲仓位和行动建议是否表达清楚。"
                ],
                bullCase: ["比特币继续趋势上行。", "市场风险偏好回暖。"],
                bearCase: ["BTC 回撤会被放大传导。", "高波动下容易触发情绪化操作。"],
                watchlist: ["BTC ETF 资金流", "MSTR 可转债和增发消息", "仓位最大回撤阈值"],
                actionPlan: ["保留弹性但降预期。", "一旦 BTC 转弱优先减仓。"],
                macroScore: 52,
                newsScore: 55,
                newsHeadline: "MSTR 仍具高弹性，但波动管理优先级高于追求更高收益。",
                accountRows: [
                    HoldingDetailAccountRow(label: "Longbridge 弹性仓", accountId: "longbridge_main", quantity: 700, statementValue: 980_000, statementPnlPct: -4.5),
                    HoldingDetailAccountRow(label: "IBKR 协同仓", accountId: "ibkr_alpha", quantity: 220, statementValue: 780_000, statementPnlPct: -8.1)
                ],
                peers: [
                    peer(symbol: "COIN", name: "Coinbase", signalScore: 61, trendState: "高位震荡", currentPrice: 266.4, changePct: 1.5, signalZone: "波动放大"),
                    peer(symbol: "IBIT", name: "iShares Bitcoin Trust", signalScore: 58, trendState: "趋势跟随", currentPrice: 44.8, changePct: 0.9, signalZone: "中性"),
                    peer(symbol: "SQ", name: "Block", signalScore: 54, trendState: "震荡", currentPrice: 83.4, changePct: -0.3, signalZone: "中性")
                ],
                matrixRows: [
                    matrixRow(symbol: "MSTR", name: "Strategy", isTarget: true, signalScore: 57, signalZone: "波动放大", trendState: "高位震荡", trend: 56, macro: 52, news: 55),
                    matrixRow(symbol: "COIN", name: "Coinbase", isTarget: false, signalScore: 61, signalZone: "波动放大", trendState: "高位震荡", trend: 60, macro: 57, news: 58),
                    matrixRow(symbol: "IBIT", name: "IBIT", isTarget: false, signalScore: 58, signalZone: "中性", trendState: "趋势跟随", trend: 58, macro: 55, news: 54)
                ],
                history: history([100, 97, 99, 102, 106, 104, 110, 112, 118, 114]),
                comparisonHistory: [
                    comparison(symbol: "MSTR", name: "Strategy", isTarget: true, values: [100, 97, 99, 102, 106, 104, 110, 112, 118, 114]),
                    comparison(symbol: "COIN", name: "Coinbase", isTarget: false, values: [100, 98, 99, 101, 103, 104, 106, 108, 111, 112]),
                    comparison(symbol: "IBIT", name: "IBIT", isTarget: false, values: [100, 99, 100, 101, 102, 103, 104, 106, 108, 109])
                ]
            )

        case "AMD":
            return MockHoldingFixture(
                executiveSummary: [
                    "AMD 是演示组合中的 AI 跟随仓位。",
                    "它不如 NVDA 强，但能在主题扩散时贡献增量收益。",
                    "这里主要验证持仓说明、对比矩阵和 AI 刷新的页面状态。"
                ],
                bullCase: ["AI 订单继续兑现。", "PC 与服务器周期同步修复。"],
                bearCase: ["AI 叙事兑现不及预期。", "在龙头过强时容易被边缘化。"],
                watchlist: ["MI 系列订单", "服务器业务毛利率", "与 NVDA 的强弱关系"],
                actionPlan: ["跟随持有。", "若弱于龙头太多则继续降权。"],
                macroScore: 60,
                newsScore: 62,
                newsHeadline: "AMD 更适合作为跟随仓，而不是替代龙头的主仓。",
                accountRows: [
                    HoldingDetailAccountRow(label: "IBKR 跟随仓", accountId: "ibkr_alpha", quantity: 1_200, statementValue: 760_000, statementPnlPct: 7.2),
                    HoldingDetailAccountRow(label: "Tiger 机动仓", accountId: "tiger_satellite", quantity: 500, statementValue: 520_000, statementPnlPct: 3.1)
                ],
                peers: [
                    peer(symbol: "NVDA", name: "英伟达", signalScore: 79, trendState: "上行延续", currentPrice: 926.4, changePct: 2.1, signalZone: "偏强"),
                    peer(symbol: "ARM", name: "Arm", signalScore: 60, trendState: "震荡", currentPrice: 136.7, changePct: 0.5, signalZone: "中性"),
                    peer(symbol: "AVGO", name: "Broadcom", signalScore: 70, trendState: "强势整理", currentPrice: 1_442, changePct: 0.8, signalZone: "偏强")
                ],
                matrixRows: [
                    matrixRow(symbol: "AMD", name: "AMD", isTarget: true, signalScore: 63, signalZone: "中性偏强", trendState: "震荡上修", trend: 64, macro: 60, news: 62),
                    matrixRow(symbol: "NVDA", name: "英伟达", isTarget: false, signalScore: 79, signalZone: "偏强", trendState: "上行延续", trend: 82, macro: 74, news: 79),
                    matrixRow(symbol: "ARM", name: "Arm", isTarget: false, signalScore: 60, signalZone: "中性", trendState: "震荡", trend: 58, macro: 56, news: 55)
                ],
                history: history([100, 100.5, 101, 101.8, 103.2, 104.1, 105, 106.4, 109, 111]),
                comparisonHistory: [
                    comparison(symbol: "AMD", name: "AMD", isTarget: true, values: [100, 100.5, 101, 101.8, 103.2, 104.1, 105, 106.4, 109, 111]),
                    comparison(symbol: "NVDA", name: "英伟达", isTarget: false, values: [100, 102, 103, 105, 109, 112, 115, 118, 124, 128]),
                    comparison(symbol: "ARM", name: "Arm", isTarget: false, values: [100, 100.1, 100.6, 101.2, 101.7, 102.3, 103, 104, 105.1, 106])
                ]
            )

        default:
            return MockHoldingFixture(
                executiveSummary: ["当前是本地 mock 详情页，用于验证结构和跳转。"],
                bullCase: ["保留主要逻辑流。"],
                bearCase: ["暂无真实行情。"],
                watchlist: ["等待真实服务恢复。"],
                actionPlan: ["继续验证界面流程。"],
                macroScore: 60,
                newsScore: 60,
                newsHeadline: "本地 mock 标的详情。",
                accountRows: [
                    HoldingDetailAccountRow(label: "Demo", accountId: "demo", quantity: 100, statementValue: 100_000, statementPnlPct: 0.0)
                ],
                peers: [peer(symbol: "DEMO", name: "Demo Peer", signalScore: 60, trendState: "中性", currentPrice: 100, changePct: 0, signalZone: "中性")],
                matrixRows: [matrixRow(symbol: "DEMO", name: "Demo", isTarget: true, signalScore: 60, signalZone: "中性", trendState: "中性", trend: 60, macro: 60, news: 60)],
                history: history([100, 101, 102, 101, 100, 99, 100, 101, 102, 103]),
                comparisonHistory: [comparison(symbol: "DEMO", name: "Demo", isTarget: true, values: [100, 101, 102, 101, 100, 99, 100, 101, 102, 103])]
            )
        }
    }

    private static func peer(
        symbol: String,
        name: String,
        signalScore: Int,
        trendState: String,
        currentPrice: Double,
        changePct: Double,
        signalZone: String
    ) -> HoldingDetailPeer {
        HoldingDetailPeer(
            symbol: symbol,
            name: name,
            signalScore: signalScore,
            trendState: trendState,
            currentPrice: currentPrice,
            changePct: changePct,
            normalizedHistory: history([100, 101, 102, 103, 104, 105, 106, 107, 108, 109]),
            factorScores: ["trend": signalScore, "macro": max(signalScore - 5, 1), "news": max(signalScore - 3, 1)],
            signalZone: signalZone
        )
    }

    private static func matrixRow(
        symbol: String,
        name: String,
        isTarget: Bool,
        signalScore: Int,
        signalZone: String,
        trendState: String,
        trend: Int,
        macro: Int,
        news: Int
    ) -> HoldingDetailSignalMatrixRow {
        HoldingDetailSignalMatrixRow(
            symbol: symbol,
            name: name,
            isTarget: isTarget,
            signalScore: signalScore,
            signalZone: signalZone,
            trendState: trendState,
            cells: [
                HoldingDetailSignalMatrixCell(label: "趋势", score: trend),
                HoldingDetailSignalMatrixCell(label: "宏观", score: macro),
                HoldingDetailSignalMatrixCell(label: "消息", score: news)
            ]
        )
    }

    private static func comparison(
        symbol: String,
        name: String,
        isTarget: Bool,
        values: [Double]
    ) -> HoldingDetailComparisonRow {
        HoldingDetailComparisonRow(
            symbol: symbol,
            name: name,
            isTarget: isTarget,
            points: history(values)
        )
    }

    private static func history(_ values: [Double]) -> [HoldingDetailSeriesPoint] {
        values.enumerated().map { index, value in
            let day = 11 - (values.count - index - 1)
            let dayString = String(format: "2026-03-%02d", max(day, 1))
            return HoldingDetailSeriesPoint(date: dayString, price: value)
        }
    }

    private static func signedPercent(_ value: Double?) -> String {
        guard let value else {
            return "N/A"
        }
        return String(format: value >= 0 ? "+%.1f%%" : "%.1f%%", value)
    }

    private static func decimalString(_ value: Double?) -> String {
        guard let value else {
            return "N/A"
        }
        return value >= 100 ? String(format: "%.1f", value) : String(format: "%.2f", value)
    }

    private static func groupedCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "HK$"
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? "HK$\(Int(value))"
    }
}

private struct MockHoldingFixture {
    let executiveSummary: [String]
    let bullCase: [String]
    let bearCase: [String]
    let watchlist: [String]
    let actionPlan: [String]
    let macroScore: Int
    let newsScore: Int
    let newsHeadline: String
    let accountRows: [HoldingDetailAccountRow]
    let peers: [HoldingDetailPeer]
    let matrixRows: [HoldingDetailSignalMatrixRow]
    let history: [HoldingDetailSeriesPoint]
    let comparisonHistory: [HoldingDetailComparisonRow]
}

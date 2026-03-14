import Foundation

public enum MobileTone: String, Codable, Sendable {
    case up
    case warn
    case down
    case neutral
}

public enum AIProviderKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case anthropic
    case kimi
    case gemini

    public var id: String { rawValue }
}

public struct AIProviderRequestConfiguration: Codable, Sendable, Equatable {
    public let provider: AIProviderKind
    public let model: String?
    public let apiKey: String?
    public let baseURL: String?

    public init(
        provider: AIProviderKind,
        model: String? = nil,
        apiKey: String? = nil,
        baseURL: String? = nil
    ) {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case model
        case apiKey = "api_key"
        case baseURL = "base_url"
    }
}

public struct AIRequestConfiguration: Codable, Sendable, Equatable {
    public let primaryProvider: AIProviderKind
    public let enableFallbacks: Bool
    public let providers: [AIProviderRequestConfiguration]

    public init(
        primaryProvider: AIProviderKind,
        enableFallbacks: Bool,
        providers: [AIProviderRequestConfiguration]
    ) {
        self.primaryProvider = primaryProvider
        self.enableFallbacks = enableFallbacks
        self.providers = providers
    }

    private enum CodingKeys: String, CodingKey {
        case primaryProvider = "primary_provider"
        case enableFallbacks = "enable_fallbacks"
        case providers
    }
}

public struct AIServiceProviderStatus: Codable, Sendable, Equatable, Identifiable {
    public let provider: AIProviderKind
    public let label: String
    public let model: String?
    public let baseURL: String?
    public let preset: String?
    public let credentialSource: String
    public let accessState: String
    public let accessMessage: String
    public let checkedAt: String?
    public let latencyMs: Int?

    public var id: AIProviderKind { provider }

    private enum CodingKeys: String, CodingKey {
        case provider
        case label
        case model
        case baseURL = "baseUrl"
        case preset
        case credentialSource
        case accessState
        case accessMessage
        case checkedAt
        case latencyMs
    }
}

public struct AIServiceStatusPayload: Codable, Sendable, Equatable {
    public let primaryProvider: AIProviderKind?
    public let enableFallbacks: Bool
    public let providerOrder: [AIProviderKind]
    public let usesServiceConfig: Bool
    public let providers: [AIServiceProviderStatus]
    public let note: String

    private enum CodingKeys: String, CodingKey {
        case primaryProvider
        case enableFallbacks
        case providerOrder
        case usesServiceConfig
        case providers
        case note
    }
}

public struct MobileUser: Codable, Sendable, Equatable {
    public let userId: String
    public let displayName: String
    public let phoneNumberMasked: String?
    public let authProvider: String
    public let isOwner: Bool
}

public struct MobileUserEnvelope: Codable, Sendable {
    public let user: MobileUser
}

public struct DeviceAccountCredentials: Codable, Sendable, Equatable {
    public let assignedUserId: String?
    public let deviceName: String
    public let defaultPassword: String?
    public let isNewDevice: Bool

    public init(
        assignedUserId: String?,
        deviceName: String,
        defaultPassword: String?,
        isNewDevice: Bool
    ) {
        self.assignedUserId = assignedUserId
        self.deviceName = deviceName
        self.defaultPassword = defaultPassword
        self.isNewDevice = isNewDevice
    }
}

public struct MobileSessionPayload: Codable, Sendable {
    public let sessionToken: String?
    public let user: MobileUser
    public let message: String?
    public let deviceCredentials: DeviceAccountCredentials?

    public init(
        sessionToken: String?,
        user: MobileUser,
        message: String?,
        deviceCredentials: DeviceAccountCredentials? = nil
    ) {
        self.sessionToken = sessionToken
        self.user = user
        self.message = message
        self.deviceCredentials = deviceCredentials
    }
}

public struct PhoneCodeRequestPayload: Codable, Sendable {
    public let message: String
    public let expiresInSeconds: Int
    public let debugCode: String?
}

public struct BrokerCapability: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let crossAppAuthorization: String
    public let officialApiAvailable: Bool
    public let supportsPositions: Bool
    public let supportsTrades: Bool
    public let connectableInApp: Bool
    public let status: String
    public let authPath: String
    public let summary: String
    public let nextStep: String
    public let docsUrl: String
    public let requirements: [String]
}

public struct StatementImportTemplate: Codable, Sendable, Identifiable {
    public let id: String
    public let brokerId: String
    public let broker: String
    public let statementType: String
    public let label: String
    public let description: String
}

public struct ImportCenterPayload: Codable, Sendable {
    public let user: MobileUser?
    public let brokers: [BrokerCapability]
    public let statementTemplates: [StatementImportTemplate]
    public let notes: [String]
}

public struct BasicMessagePayload: Codable, Sendable {
    public let message: String
}

public struct MobileServerDiscoveryPayload: Codable, Sendable, Equatable {
    public let service: String
    public let appName: String
    public let bindHost: String
    public let port: Int
    public let suggestedBaseUrl: String?
    public let detectedLanIp: String?
    public let availablePaths: [String]
}

public struct MobileDashboardPayload: Codable, Sendable {
    public let generatedAt: String
    public let analysisDateCn: String
    public let snapshotDate: String
    public let hero: MobileDashboardHero
    public let summaryCards: [MobileSummaryCard]
    public let marketPulse: MobileMarketPulse
    public let sourceHealth: MobileSourceHealth
    public let keyDrivers: [MobileInsightCard]
    public let riskFlags: [MobileInsightCard]
    public let actionCenter: MobileActionCenter
    public let actionBlocks: [MobileActionBlock]
    public let aiUpdatedAt: String?
    public let aiEngineLabel: String?
    public let healthRadar: [MobileRadarMetric]
    public let allocationGroups: MobileAllocationGroups
    public let macroTopics: [MobileMacroTopic]
    public let strategyViews: [MobileStrategyCard]
    public let positions: [MobilePosition]
    public let spotlightPositions: [MobilePosition]
    public let accounts: [MobileAccount]
    public let recentTrades: [MobileTrade]
    public let derivatives: [MobileDerivative]
    public let statementSources: [MobileStatementSource]
    public let referenceSources: [MobileReferenceSource]
    public let updateGuide: [String]

    public init(
        generatedAt: String,
        analysisDateCn: String,
        snapshotDate: String,
        hero: MobileDashboardHero,
        summaryCards: [MobileSummaryCard],
        marketPulse: MobileMarketPulse,
        sourceHealth: MobileSourceHealth,
        keyDrivers: [MobileInsightCard],
        riskFlags: [MobileInsightCard],
        actionCenter: MobileActionCenter,
        actionBlocks: [MobileActionBlock],
        aiUpdatedAt: String?,
        aiEngineLabel: String?,
        healthRadar: [MobileRadarMetric],
        allocationGroups: MobileAllocationGroups,
        macroTopics: [MobileMacroTopic],
        strategyViews: [MobileStrategyCard],
        positions: [MobilePosition],
        spotlightPositions: [MobilePosition],
        accounts: [MobileAccount],
        recentTrades: [MobileTrade],
        derivatives: [MobileDerivative],
        statementSources: [MobileStatementSource],
        referenceSources: [MobileReferenceSource],
        updateGuide: [String]
    ) {
        self.generatedAt = generatedAt
        self.analysisDateCn = analysisDateCn
        self.snapshotDate = snapshotDate
        self.hero = hero
        self.summaryCards = summaryCards
        self.marketPulse = marketPulse
        self.sourceHealth = sourceHealth
        self.keyDrivers = keyDrivers
        self.riskFlags = riskFlags
        self.actionCenter = actionCenter
        self.actionBlocks = actionBlocks
        self.aiUpdatedAt = aiUpdatedAt
        self.aiEngineLabel = aiEngineLabel
        self.healthRadar = healthRadar
        self.allocationGroups = allocationGroups
        self.macroTopics = macroTopics
        self.strategyViews = strategyViews
        self.positions = positions
        self.spotlightPositions = spotlightPositions
        self.accounts = accounts
        self.recentTrades = recentTrades
        self.derivatives = derivatives
        self.statementSources = statementSources
        self.referenceSources = referenceSources
        self.updateGuide = updateGuide
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt
        case analysisDateCn
        case snapshotDate
        case hero
        case summaryCards
        case marketPulse
        case sourceHealth
        case keyDrivers
        case riskFlags
        case actionCenter
        case actionBlocks
        case aiUpdatedAt
        case aiEngineLabel
        case healthRadar
        case allocationGroups
        case macroTopics
        case strategyViews
        case positions
        case spotlightPositions
        case accounts
        case recentTrades
        case derivatives
        case statementSources
        case referenceSources
        case updateGuide
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(String.self, forKey: .generatedAt)
        analysisDateCn = try container.decode(String.self, forKey: .analysisDateCn)
        snapshotDate = try container.decode(String.self, forKey: .snapshotDate)
        hero = try container.decode(MobileDashboardHero.self, forKey: .hero)
        summaryCards = try container.decode([MobileSummaryCard].self, forKey: .summaryCards)
        marketPulse = try container.decodeIfPresent(MobileMarketPulse.self, forKey: .marketPulse) ?? .empty
        sourceHealth = try container.decode(MobileSourceHealth.self, forKey: .sourceHealth)
        keyDrivers = try container.decode([MobileInsightCard].self, forKey: .keyDrivers)
        riskFlags = try container.decode([MobileInsightCard].self, forKey: .riskFlags)
        actionCenter = try container.decode(MobileActionCenter.self, forKey: .actionCenter)
        actionBlocks = try container.decode([MobileActionBlock].self, forKey: .actionBlocks)
        aiUpdatedAt = try container.decodeIfPresent(String.self, forKey: .aiUpdatedAt)
        aiEngineLabel = try container.decodeIfPresent(String.self, forKey: .aiEngineLabel)
        healthRadar = try container.decode([MobileRadarMetric].self, forKey: .healthRadar)
        allocationGroups = try container.decode(MobileAllocationGroups.self, forKey: .allocationGroups)
        macroTopics = try container.decode([MobileMacroTopic].self, forKey: .macroTopics)
        strategyViews = try container.decode([MobileStrategyCard].self, forKey: .strategyViews)
        positions = try container.decode([MobilePosition].self, forKey: .positions)
        spotlightPositions = try container.decode([MobilePosition].self, forKey: .spotlightPositions)
        accounts = try container.decode([MobileAccount].self, forKey: .accounts)
        recentTrades = try container.decode([MobileTrade].self, forKey: .recentTrades)
        derivatives = try container.decode([MobileDerivative].self, forKey: .derivatives)
        statementSources = try container.decode([MobileStatementSource].self, forKey: .statementSources)
        referenceSources = try container.decode([MobileReferenceSource].self, forKey: .referenceSources)
        updateGuide = try container.decode([String].self, forKey: .updateGuide)
    }
}

public struct MobileMarketPulse: Codable, Sendable {
    public let headline: String
    public let summary: String
    public let selectionLogic: String?
    public let catalysts: [MobileMarketPulseCatalyst]
    public let suggestions: [String]
}

private extension MobileMarketPulse {
    static let empty = MobileMarketPulse(
        headline: "市场脉冲暂不可用",
        summary: "当前响应未包含市场脉冲摘要，先展示组合核心数据。",
        selectionLogic: nil,
        catalysts: [],
        suggestions: []
    )
}

public struct MobileMarketPulseCatalyst: Codable, Sendable, Identifiable {
    public let rawId: String?
    public let category: String
    public let title: String
    public let headline: String
    public let summary: String
    public let selectionReason: String?
    public let impactNote: String
    public let advice: String
    public let relatedSymbols: [String]
    public let source: String?
    public let publishedAt: String?
    public let tone: MobileTone?

    public var id: String { rawId ?? category + title }

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case category
        case title
        case headline
        case summary
        case selectionReason
        case impactNote
        case advice
        case relatedSymbols
        case source
        case publishedAt
        case tone
    }
}

public struct MobileActionBlock: Codable, Sendable, Identifiable {
    public let label: String
    public let title: String
    public let detail: String?
    public let badge: String?
    public let tone: MobileTone?

    public var id: String { label + title }
}

public struct MobileDashboardHero: Codable, Sendable {
    public let title: String
    public let subtitle: String
    public let overview: String
    public let snapshotWindow: String
    public let liveNote: String
    public let macroNote: String
    public let primaryTheme: String?
    public let primaryBroker: String?
}

public struct MobileSummaryCard: Codable, Sendable, Identifiable {
    public let label: String
    public let value: String
    public let detail: String
    public let tone: MobileTone

    public var id: String { label }
}

public struct MobileSourceHealth: Codable, Sendable {
    public let parsedCount: Int
    public let cachedCount: Int
    public let errorCount: Int
}

public struct MobileInsightCard: Codable, Sendable, Identifiable {
    public let title: String
    public let detail: String
    public let tone: MobileTone?

    public var id: String { title + String(detail.prefix(20)) }
}

public struct MobileActionCenter: Codable, Sendable {
    public let headline: String
    public let overview: String
    public let priorityActions: [MobilePriorityAction]
    public let disclaimer: String
}

public struct MobilePriorityAction: Codable, Sendable, Identifiable {
    public let title: String
    public let detail: String

    public var id: String { title + String(detail.prefix(20)) }
}

public struct MobileRadarMetric: Codable, Sendable, Identifiable {
    public let label: String
    public let value: Double
    public let summary: String

    public var id: String { label }
}

public struct MobileAllocationGroups: Codable, Sendable {
    public let themes: [MobileAllocationBucket]
    public let markets: [MobileAllocationBucket]
    public let brokers: [MobileAllocationBucket]
}

public struct MobileAllocationBucket: Codable, Sendable, Identifiable {
    public let label: String
    public let valueHkd: Double?
    public let weightPct: Double
    public let count: Int?
    public let coreHoldings: [String]?
    public let coreSymbols: [String]?

    public var id: String { label }
}

public struct MobileMacroTopic: Codable, Sendable, Identifiable {
    public let rawId: String?
    public let name: String
    public let severity: String
    public let summary: String
    public let headline: String
    public let impactLabels: String
    public let score: Int
    public let source: String?
    public let publishedAt: String?
    public let impactWeightPct: Double

    public var id: String { rawId ?? name }

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case name
        case severity
        case summary
        case headline
        case impactLabels
        case score
        case source
        case publishedAt
        case impactWeightPct
    }
}

public struct MobileStrategyCard: Codable, Sendable, Identifiable {
    public let title: String
    public let tag: String
    public let tone: MobileTone
    public let summary: String

    public var id: String { title }
}

public struct MobilePosition: Codable, Sendable, Identifiable {
    public let symbol: String
    public let name: String
    public let nameEn: String?
    public let market: String
    public let currency: String
    public let categoryName: String
    public let styleLabel: String
    public let fundamentalLabel: String
    public let weightPct: Double
    public let statementValueHkd: Double
    public let statementPnlPct: Double?
    public let statementPnlHkd: Double?
    public let currentPrice: Double?
    public let changePct: Double?
    public let changePct5d: Double?
    public let tradeDate: String?
    public let signalScore: Int?
    public let signalZone: String?
    public let trendState: String?
    public let positionLabel: String?
    public let macroSignal: String?
    public let newsSignal: String?
    public let accountCount: Int?
    public let stance: String
    public let role: String
    public let summary: String?
    public let action: String?
    public let watchItems: String?
    public let sparklinePoints: [Double]

    public var id: String { symbol }
}

public struct MobileAccount: Codable, Sendable, Identifiable {
    public let accountId: String
    public let broker: String
    public let statementDate: String
    public let baseCurrency: String
    public let navHkd: Double
    public let holdingsValueHkd: Double
    public let financingHkd: Double
    public let holdingCount: Int
    public let tradeCount: Int
    public let derivativeCount: Int
    public let riskNotes: [String]
    public let topNames: String?
    public let sourceMode: String?
    public let uploadedAt: String?
    public let loadStatus: String?
    public let issue: String?
    public let fileName: String?
    public let fileExists: Bool?
    public let statementType: String?

    public var id: String { accountId }
}

public struct MobileTrade: Codable, Sendable, Identifiable {
    public let date: String
    public let symbol: String
    public let name: String
    public let side: String
    public let quantity: Double
    public let price: Double
    public let currency: String
    public let broker: String
    public let accountId: String

    public var id: String { "\(date)-\(symbol)-\(broker)-\(quantity)" }
}

public struct MobileDerivative: Codable, Sendable, Identifiable {
    public let symbol: String
    public let description: String
    public let currency: String
    public let quantity: Double?
    public let marketValue: Double?
    public let unrealizedPnl: Double?
    public let estimatedNotional: Double?
    public let estimatedNotionalHkd: Double?
    public let underlyings: [String]
    public let broker: String
    public let accountId: String

    public var id: String { description + accountId }
}

public struct MobileStatementSource: Codable, Sendable, Identifiable {
    public let accountId: String
    public let broker: String
    public let fileExists: Bool
    public let fileName: String
    public let issue: String?
    public let loadStatus: String
    public let sourceMode: String
    public let statementDate: String?
    public let statementType: String
    public let uploadedAt: String?

    public var id: String { accountId }
}

public struct MobileReferenceSource: Codable, Sendable, Identifiable {
    public let label: String
    public let type: String
    public let fileName: String

    public var id: String { label + fileName }
}

public struct MobileDashboardAIRefreshPayload: Codable, Sendable {
    public let generatedAt: String
    public let analysisDateCn: String
    public let actionBlocks: [MobileActionBlock]
    public let aiUpdatedAt: String?
    public let aiEngineLabel: String?
    public let aiStatusMessage: String
}

public struct MobileAIChatReplyPayload: Codable, Sendable {
    public let reply: String
    public let engineLabel: String?
    public let statusMessage: String
}

public struct HoldingDetailPayload: Codable, Sendable {
    public let generatedAt: String
    public let analysisDateCn: String
    public let shareMode: Bool
    public let hero: HoldingDetailHero
    public let sourceMeta: HoldingDetailSourceMeta
    public let executiveSummary: [String]
    public let focusCards: [HoldingDetailFocusCard]
    public let signalRows: [HoldingDetailSignalRow]
    public let signalMatrix: HoldingDetailSignalMatrix
    public let portfolioContext: [HoldingDetailLabelValue]
    public let priceCards: [HoldingDetailPriceCard]
    public let accountRows: [HoldingDetailAccountRow]
    public let relatedTrades: [HoldingDetailTradeRow]
    public let derivativeRows: [HoldingDetailDerivativeRow]
    public let bullCase: [String]
    public let bearCase: [String]
    public let watchlist: [String]
    public let actionPlan: [String]
    public let peers: [HoldingDetailPeer]
    public let history: [HoldingDetailSeriesPoint]
    public let comparisonHistory: [HoldingDetailComparisonRow]
    public let holdingNote: HoldingDetailNote

    public init(
        generatedAt: String,
        analysisDateCn: String,
        shareMode: Bool,
        hero: HoldingDetailHero,
        sourceMeta: HoldingDetailSourceMeta,
        executiveSummary: [String],
        focusCards: [HoldingDetailFocusCard],
        signalRows: [HoldingDetailSignalRow],
        signalMatrix: HoldingDetailSignalMatrix,
        portfolioContext: [HoldingDetailLabelValue],
        priceCards: [HoldingDetailPriceCard],
        accountRows: [HoldingDetailAccountRow],
        relatedTrades: [HoldingDetailTradeRow],
        derivativeRows: [HoldingDetailDerivativeRow],
        bullCase: [String],
        bearCase: [String],
        watchlist: [String],
        actionPlan: [String],
        peers: [HoldingDetailPeer],
        history: [HoldingDetailSeriesPoint],
        comparisonHistory: [HoldingDetailComparisonRow],
        holdingNote: HoldingDetailNote
    ) {
        self.generatedAt = generatedAt
        self.analysisDateCn = analysisDateCn
        self.shareMode = shareMode
        self.hero = hero
        self.sourceMeta = sourceMeta
        self.executiveSummary = executiveSummary
        self.focusCards = focusCards
        self.signalRows = signalRows
        self.signalMatrix = signalMatrix
        self.portfolioContext = portfolioContext
        self.priceCards = priceCards
        self.accountRows = accountRows
        self.relatedTrades = relatedTrades
        self.derivativeRows = derivativeRows
        self.bullCase = bullCase
        self.bearCase = bearCase
        self.watchlist = watchlist
        self.actionPlan = actionPlan
        self.peers = peers
        self.history = history
        self.comparisonHistory = comparisonHistory
        self.holdingNote = holdingNote
    }
}

public struct HoldingDetailAIPayload: Codable, Sendable {
    public let generatedAt: String
    public let analysisDateCn: String
    public let executiveSummary: [String]
    public let bullCase: [String]
    public let bearCase: [String]
    public let watchlist: [String]
    public let actionPlan: [String]
    public let aiStatusMessage: String
}

public struct HoldingDetailHero: Codable, Sendable {
    public let symbol: String
    public let name: String
    public let categoryName: String
    public let styleLabel: String
    public let fundamentalLabel: String
    public let signalScore: Int
    public let signalZone: String
    public let trendState: String
    public let positionLabel: String
    public let macroSignal: String
    public let newsSignal: String
    public let currentPrice: Double?
    public let changePct: Double?
    public let changePct5d: Double?
    public let tradeDate: String?
    public let priceSource: String
    public let priceSourceLabel: String
    public let newsHeadline: String?
}

public struct HoldingDetailSourceMeta: Codable, Sendable {
    public let priceSourceLabel: String
    public let liveUpdatedAt: String?
    public let macroUpdatedAt: String?
    public let tradeDate: String
}

public struct HoldingDetailFocusCard: Codable, Sendable, Identifiable {
    public let label: String
    public let value: String
    public let detail: String

    public var id: String { label }
}

public struct HoldingDetailSignalRow: Codable, Sendable, Identifiable {
    public let label: String
    public let score: Int
    public let comment: String

    public var id: String { label }
}

public struct HoldingDetailSignalMatrix: Codable, Sendable {
    public let columns: [HoldingDetailSignalMatrixColumn]
    public let rows: [HoldingDetailSignalMatrixRow]
}

public struct HoldingDetailSignalMatrixColumn: Codable, Sendable, Identifiable {
    public let key: String
    public let label: String

    public var id: String { key }
}

public struct HoldingDetailSignalMatrixRow: Codable, Sendable, Identifiable {
    public let symbol: String
    public let name: String
    public let isTarget: Bool
    public let signalScore: Int
    public let signalZone: String
    public let trendState: String
    public let cells: [HoldingDetailSignalMatrixCell]

    public var id: String { symbol }
}

public struct HoldingDetailSignalMatrixCell: Codable, Sendable, Identifiable {
    public let label: String
    public let score: Int

    public var id: String { label }
}

public struct HoldingDetailLabelValue: Codable, Sendable, Identifiable {
    public let label: String
    public let value: String

    public var id: String { label + value }
}

public struct HoldingDetailPriceCard: Codable, Sendable, Identifiable {
    public let label: String
    public let value: String
    public let delta: String?

    public var id: String { label }
}

public struct HoldingDetailAccountRow: Codable, Sendable, Identifiable {
    public let label: String
    public let accountId: String
    public let quantity: Double
    public let statementValue: Double
    public let statementPnlPct: Double?

    public var id: String { accountId }
}

public struct HoldingDetailTradeRow: Codable, Sendable, Identifiable {
    public let date: String
    public let side: String
    public let broker: String
    public let quantity: Double?
    public let price: Double?
    public let currency: String

    public var id: String { "\(date)-\(broker)-\(quantity ?? 0)" }
}

public struct HoldingDetailDerivativeRow: Codable, Sendable, Identifiable {
    public let symbol: String
    public let description: String
    public let estimatedNotionalHkd: Double?

    public var id: String { description + symbol }
}

public struct HoldingDetailPeer: Codable, Sendable, Identifiable {
    public let symbol: String
    public let name: String
    public let signalScore: Int
    public let trendState: String
    public let currentPrice: Double?
    public let changePct: Double?
    public let normalizedHistory: [HoldingDetailSeriesPoint]
    public let factorScores: [String: Int]
    public let signalZone: String

    public var id: String { symbol }
}

public struct HoldingDetailSeriesPoint: Codable, Sendable, Identifiable {
    public let date: String
    public let price: Double?

    public var id: String { date }
}

public struct HoldingDetailComparisonRow: Codable, Sendable, Identifiable {
    public let symbol: String
    public let name: String
    public let isTarget: Bool
    public let points: [HoldingDetailSeriesPoint]

    public var id: String { symbol }
}

public struct HoldingDetailNote: Codable, Sendable {
    public let symbol: String
    public let name: String
    public let weightPct: Double
    public let role: String
    public let stance: String
    public let thesis: String
    public let watchItems: String
    public let risk: String
    public let action: String
    public let currentPrice: Double?
    public let changePct: Double?
    public let positionLabel: String?
    public let trendState: String?
    public let macroSignal: String?
    public let newsSignal: String?
    public let fundamentalLabel: String?
    public let signalScore: Int?
    public let signalZone: String?
    public let statementPnlPct: Double?
    public let statementValueHkd: Double
    public let categoryName: String
}

public struct StatementUploadEnvelope: Codable, Sendable {
    public let message: String
    public let payload: MobileDashboardPayload?
}

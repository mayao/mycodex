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

    public init(
        userId: String,
        displayName: String,
        phoneNumberMasked: String? = nil,
        authProvider: String,
        isOwner: Bool
    ) {
        self.userId = userId
        self.displayName = displayName
        self.phoneNumberMasked = phoneNumberMasked
        self.authProvider = authProvider
        self.isOwner = isOwner
    }
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
    public let quantity: Double?
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
    public let accountIds: [String]?
    public let brokers: [String]?
    public let stance: String
    public let role: String
    public let summary: String?
    public let action: String?
    public let watchItems: String?
    public let sparklinePoints: [Double]

    public var id: String { symbol }

    public init(
        symbol: String,
        name: String,
        nameEn: String? = nil,
        market: String,
        currency: String,
        quantity: Double? = nil,
        categoryName: String,
        styleLabel: String,
        fundamentalLabel: String,
        weightPct: Double,
        statementValueHkd: Double,
        statementPnlPct: Double? = nil,
        statementPnlHkd: Double? = nil,
        currentPrice: Double? = nil,
        changePct: Double? = nil,
        changePct5d: Double? = nil,
        tradeDate: String? = nil,
        signalScore: Int? = nil,
        signalZone: String? = nil,
        trendState: String? = nil,
        positionLabel: String? = nil,
        macroSignal: String? = nil,
        newsSignal: String? = nil,
        accountCount: Int? = nil,
        accountIds: [String]? = nil,
        brokers: [String]? = nil,
        stance: String,
        role: String,
        summary: String? = nil,
        action: String? = nil,
        watchItems: String? = nil,
        sparklinePoints: [Double]
    ) {
        self.symbol = symbol
        self.name = name
        self.nameEn = nameEn
        self.market = market
        self.currency = currency
        self.quantity = quantity
        self.categoryName = categoryName
        self.styleLabel = styleLabel
        self.fundamentalLabel = fundamentalLabel
        self.weightPct = weightPct
        self.statementValueHkd = statementValueHkd
        self.statementPnlPct = statementPnlPct
        self.statementPnlHkd = statementPnlHkd
        self.currentPrice = currentPrice
        self.changePct = changePct
        self.changePct5d = changePct5d
        self.tradeDate = tradeDate
        self.signalScore = signalScore
        self.signalZone = signalZone
        self.trendState = trendState
        self.positionLabel = positionLabel
        self.macroSignal = macroSignal
        self.newsSignal = newsSignal
        self.accountCount = accountCount
        self.accountIds = accountIds
        self.brokers = brokers
        self.stance = stance
        self.role = role
        self.summary = summary
        self.action = action
        self.watchItems = watchItems
        self.sparklinePoints = sparklinePoints
    }
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
    public let availabilityStatus: String?
    public let availabilityNote: String?
    public let parsedPayloadExists: Bool?
    public let sourceMode: String
    public let statementDate: String?
    public let statementType: String
    public let uploadedAt: String?

    public var id: String { "\(broker)|\(accountId)|\(statementType)|\(sourceMode)|\(fileName)" }

    public init(
        accountId: String,
        broker: String,
        fileExists: Bool,
        fileName: String,
        issue: String? = nil,
        loadStatus: String,
        availabilityStatus: String? = nil,
        availabilityNote: String? = nil,
        parsedPayloadExists: Bool? = nil,
        sourceMode: String,
        statementDate: String? = nil,
        statementType: String,
        uploadedAt: String? = nil
    ) {
        self.accountId = accountId
        self.broker = broker
        self.fileExists = fileExists
        self.fileName = fileName
        self.issue = issue
        self.loadStatus = loadStatus
        self.availabilityStatus = availabilityStatus
        self.availabilityNote = availabilityNote
        self.parsedPayloadExists = parsedPayloadExists
        self.sourceMode = sourceMode
        self.statementDate = statementDate
        self.statementType = statementType
        self.uploadedAt = uploadedAt
    }
}

public enum HoldingsExportFormat: String, Sendable, CaseIterable, Identifiable {
    case pdf
    case xlsx

    public var id: String { rawValue }
}

public struct ExportedDocument: Sendable, Equatable {
    public let fileURL: URL
    public let fileName: String
    public let contentType: String

    public init(fileURL: URL, fileName: String, contentType: String) {
        self.fileURL = fileURL
        self.fileName = fileName
        self.contentType = contentType
    }
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

    public var id: String { "\(date)-\(side)-\(broker)-\(currency)-\(quantity ?? 0)-\(price ?? 0)" }
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

    public var id: String { "\(date)-\(price.map(String.init(describing:)) ?? "nil")" }
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
    public let resolvedAccountId: String?
    public let resolvedBroker: String?
    public let resolvedStatementType: String?
    public let detectedBroker: String?
    public let detectedStatementType: String?
    public let detectedStatementDate: String?
    public let routingAction: String?
    public let rejectionReason: String?
}

public enum AIDataSource: String, Codable, Sendable {
    case longbridge
    case fallback
    case unavailable
}

public enum LBAssetClass: String, Codable, Sendable {
    case stock
    case fund
    case fcn
    case note
    case other
}

public struct LBCurrencyBalance: Codable, Sendable, Identifiable {
    public let currency: String
    public let netAssets: Double?
    public let availableCash: Double?
    public let withdrawCash: Double?
    public let buyPower: Double?
    public let source: AIDataSource

    public var id: String { currency }

    public init(
        currency: String,
        netAssets: Double?,
        availableCash: Double?,
        withdrawCash: Double?,
        buyPower: Double?,
        source: AIDataSource
    ) {
        self.currency = currency
        self.netAssets = netAssets
        self.availableCash = availableCash
        self.withdrawCash = withdrawCash
        self.buyPower = buyPower
        self.source = source
    }
}

public struct LBAccountSummary: Codable, Sendable {
    public let totalAssetsHKD: Double?
    public let availableCashHKD: Double?
    public let unrealizedPnlHKD: Double?
    public let currencies: [LBCurrencyBalance]
    public let fxRatesToHKD: [String: Double]
    public let notes: [String]
    public let source: AIDataSource

    public init(
        totalAssetsHKD: Double?,
        availableCashHKD: Double?,
        unrealizedPnlHKD: Double?,
        currencies: [LBCurrencyBalance],
        fxRatesToHKD: [String: Double],
        notes: [String],
        source: AIDataSource
    ) {
        self.totalAssetsHKD = totalAssetsHKD
        self.availableCashHKD = availableCashHKD
        self.unrealizedPnlHKD = unrealizedPnlHKD
        self.currencies = currencies
        self.fxRatesToHKD = fxRatesToHKD
        self.notes = notes
        self.source = source
    }
}

public struct LBPosition: Codable, Sendable, Identifiable {
    public let symbol: String
    public let name: String
    public let market: String
    public let currency: String
    public let assetClass: LBAssetClass
    public let quantity: Double
    public let costPrice: Double?
    public let currentPrice: Double?
    public let marketValue: Double?
    public let marketValueHKD: Double?
    public let unrealizedPnl: Double?
    public let unrealizedPnlHKD: Double?
    public let unrealizedPnlPct: Double?
    public let changePct: Double?
    public let changePct5d: Double?
    public let categoryName: String?
    public let styleLabel: String?
    public let signalScore: Int?
    public let signalZone: String?
    public let trendState: String?
    public let macroSignal: String?
    public let newsSignal: String?
    public let stanceHint: String?
    public let watchItems: String?
    public let priceSource: AIDataSource
    public let baseSource: AIDataSource
    public let notes: [String]

    public var id: String { symbol }

    public init(
        symbol: String,
        name: String,
        market: String,
        currency: String,
        assetClass: LBAssetClass = .stock,
        quantity: Double,
        costPrice: Double?,
        currentPrice: Double?,
        marketValue: Double?,
        marketValueHKD: Double?,
        unrealizedPnl: Double?,
        unrealizedPnlHKD: Double?,
        unrealizedPnlPct: Double?,
        changePct: Double? = nil,
        changePct5d: Double? = nil,
        categoryName: String? = nil,
        styleLabel: String? = nil,
        signalScore: Int? = nil,
        signalZone: String? = nil,
        trendState: String? = nil,
        macroSignal: String? = nil,
        newsSignal: String? = nil,
        stanceHint: String? = nil,
        watchItems: String? = nil,
        priceSource: AIDataSource,
        baseSource: AIDataSource,
        notes: [String]
    ) {
        self.symbol = symbol
        self.name = name
        self.market = market
        self.currency = currency
        self.assetClass = assetClass
        self.quantity = quantity
        self.costPrice = costPrice
        self.currentPrice = currentPrice
        self.marketValue = marketValue
        self.marketValueHKD = marketValueHKD
        self.unrealizedPnl = unrealizedPnl
        self.unrealizedPnlHKD = unrealizedPnlHKD
        self.unrealizedPnlPct = unrealizedPnlPct
        self.changePct = changePct
        self.changePct5d = changePct5d
        self.categoryName = categoryName
        self.styleLabel = styleLabel
        self.signalScore = signalScore
        self.signalZone = signalZone
        self.trendState = trendState
        self.macroSignal = macroSignal
        self.newsSignal = newsSignal
        self.stanceHint = stanceHint
        self.watchItems = watchItems
        self.priceSource = priceSource
        self.baseSource = baseSource
        self.notes = notes
    }
}

public struct LBConversationMessage: Sendable, Codable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct LBConversationResult: Codable, Sendable {
    public let reply: String
    public let engineLabel: String
    public let usedFallbackRules: Bool
    public let generatedAt: Date

    public init(reply: String, engineLabel: String, usedFallbackRules: Bool, generatedAt: Date) {
        self.reply = reply
        self.engineLabel = engineLabel
        self.usedFallbackRules = usedFallbackRules
        self.generatedAt = generatedAt
    }
}

public struct LBNewsItem: Codable, Sendable, Identifiable {
    public let id: String
    public let symbol: String?
    public let title: String
    public let summary: String?
    public let publishedAt: Date?
    public let url: String?
    public let source: AIDataSource
    public let bodyMarkdown: String?

    public init(
        id: String,
        symbol: String?,
        title: String,
        summary: String?,
        publishedAt: Date?,
        url: String?,
        source: AIDataSource,
        bodyMarkdown: String? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.summary = summary
        self.publishedAt = publishedAt
        self.url = url
        self.source = source
        self.bodyMarkdown = bodyMarkdown
    }
}

public struct LBMarketTemperature: Codable, Sendable, Identifiable {
    public let market: String
    public let temperature: Int
    public let description: String
    public let valuation: Int
    public let sentiment: Int
    public let updatedAt: Date?
    public let source: AIDataSource

    public var id: String { market }

    public init(
        market: String,
        temperature: Int,
        description: String,
        valuation: Int,
        sentiment: Int,
        updatedAt: Date?,
        source: AIDataSource
    ) {
        self.market = market
        self.temperature = temperature
        self.description = description
        self.valuation = valuation
        self.sentiment = sentiment
        self.updatedAt = updatedAt
        self.source = source
    }
}

public struct AIPortfolioSnapshot: Codable, Sendable {
    public let generatedAt: Date
    public let accountSummary: LBAccountSummary
    public let positions: [LBPosition]
    public let topNews: [LBNewsItem]
    public let marketTemperatures: [LBMarketTemperature]
    public let fallbackUsage: [String]
    public let recentTrades: [MobileTrade]
    public let derivatives: [MobileDerivative]
    public let macroTopics: [MobileMacroTopic]

    private enum CodingKeys: String, CodingKey {
        case generatedAt
        case accountSummary
        case positions
        case topNews
        case marketTemperatures
        case fallbackUsage
        case recentTrades
        case derivatives
        case macroTopics
    }

    public init(
        generatedAt: Date,
        accountSummary: LBAccountSummary,
        positions: [LBPosition],
        topNews: [LBNewsItem],
        marketTemperatures: [LBMarketTemperature],
        fallbackUsage: [String],
        recentTrades: [MobileTrade] = [],
        derivatives: [MobileDerivative] = [],
        macroTopics: [MobileMacroTopic] = []
    ) {
        self.generatedAt = generatedAt
        self.accountSummary = accountSummary
        self.positions = positions
        self.topNews = topNews
        self.marketTemperatures = marketTemperatures
        self.fallbackUsage = fallbackUsage
        self.recentTrades = recentTrades
        self.derivatives = derivatives
        self.macroTopics = macroTopics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        accountSummary = try container.decode(LBAccountSummary.self, forKey: .accountSummary)
        positions = try container.decode([LBPosition].self, forKey: .positions)
        topNews = try container.decode([LBNewsItem].self, forKey: .topNews)
        marketTemperatures = try container.decode([LBMarketTemperature].self, forKey: .marketTemperatures)
        fallbackUsage = try container.decode([String].self, forKey: .fallbackUsage)
        recentTrades = try container.decodeIfPresent([MobileTrade].self, forKey: .recentTrades) ?? []
        derivatives = try container.decodeIfPresent([MobileDerivative].self, forKey: .derivatives) ?? []
        macroTopics = try container.decodeIfPresent([MobileMacroTopic].self, forKey: .macroTopics) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(accountSummary, forKey: .accountSummary)
        try container.encode(positions, forKey: .positions)
        try container.encode(topNews, forKey: .topNews)
        try container.encode(marketTemperatures, forKey: .marketTemperatures)
        try container.encode(fallbackUsage, forKey: .fallbackUsage)
        try container.encode(recentTrades, forKey: .recentTrades)
        try container.encode(derivatives, forKey: .derivatives)
        try container.encode(macroTopics, forKey: .macroTopics)
    }
}

public extension AIPortfolioSnapshot {
    var isMeaningful: Bool {
        if !positions.isEmpty
            || !topNews.isEmpty
            || !marketTemperatures.isEmpty
            || !recentTrades.isEmpty
            || !derivatives.isEmpty
            || !macroTopics.isEmpty {
            return true
        }
        if accountSummary.totalAssetsHKD != nil || accountSummary.availableCashHKD != nil || accountSummary.unrealizedPnlHKD != nil {
            return true
        }
        if !accountSummary.currencies.isEmpty {
            return true
        }
        if accountSummary.notes.isEmpty == false {
            return true
        }

        // Fallback markers alone do not make the snapshot safe to render.
        // Treat a snapshot as meaningful only if it carries visible portfolio content.
        return false
    }
}

public extension MobileDashboardPayload {
    var isMeaningful: Bool {
        if !accounts.isEmpty
            || !positions.isEmpty
            || !summaryCards.isEmpty
            || !recentTrades.isEmpty
            || !derivatives.isEmpty
            || !statementSources.isEmpty
            || !referenceSources.isEmpty {
            return true
        }

        if !hero.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hero.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if !marketPulse.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !marketPulse.catalysts.isEmpty {
            return true
        }

        if !keyDrivers.isEmpty || !riskFlags.isEmpty || !actionBlocks.isEmpty || !updateGuide.isEmpty {
            return true
        }

        return false
    }
}

public struct LBInsightInput: Sendable {
    public let snapshot: AIPortfolioSnapshot
    public let focusSymbols: [String]

    public init(snapshot: AIPortfolioSnapshot, focusSymbols: [String]) {
        self.snapshot = snapshot
        self.focusSymbols = focusSymbols
    }
}

public struct LBInsightResult: Codable, Sendable {
    public let conclusion: String
    public let evidences: [String]
    public let riskPoints: [String]
    public let suggestedActions: [String]
    public let engineLabel: String
    public let usedFallbackRules: Bool
    public let generatedAt: Date

    public init(
        conclusion: String,
        evidences: [String],
        riskPoints: [String],
        suggestedActions: [String],
        engineLabel: String,
        usedFallbackRules: Bool,
        generatedAt: Date
    ) {
        self.conclusion = conclusion
        self.evidences = evidences
        self.riskPoints = riskPoints
        self.suggestedActions = suggestedActions
        self.engineLabel = engineLabel
        self.usedFallbackRules = usedFallbackRules
        self.generatedAt = generatedAt
    }
}

public struct LBDailyStrategyAction: Codable, Sendable, Identifiable {
    public let id: String
    public let symbol: String?
    public let name: String?
    public let market: String?
    public let action: String
    public let trigger: String
    public let risk: String
    public let hedge: String
    public let confidence: String
    public let weightPct: Double?
    public let score: Int?
    public let riskBudgetBps: Int?
    public let layer: String

    public init(
        id: String,
        symbol: String? = nil,
        name: String? = nil,
        market: String? = nil,
        action: String,
        trigger: String,
        risk: String,
        hedge: String,
        confidence: String,
        weightPct: Double? = nil,
        score: Int? = nil,
        riskBudgetBps: Int? = nil,
        layer: String
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.market = market
        self.action = action
        self.trigger = trigger
        self.risk = risk
        self.hedge = hedge
        self.confidence = confidence
        self.weightPct = weightPct
        self.score = score
        self.riskBudgetBps = riskBudgetBps
        self.layer = layer
    }
}

public struct LBDailyStrategyLayer: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let symbols: [String]

    public init(id: String, title: String, summary: String, symbols: [String]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.symbols = symbols
    }
}

public struct LBDailyStrategyReminder: Codable, Sendable, Identifiable {
    public let id: String
    public let market: String
    public let title: String
    public let message: String
    public let fireAt: Date

    public init(id: String, market: String, title: String, message: String, fireAt: Date) {
        self.id = id
        self.market = market
        self.title = title
        self.message = message
        self.fireAt = fireAt
    }
}

public struct LBDailyStrategy: Codable, Sendable, Identifiable {
    public var id: String { dateKey }

    public let dateKey: String
    public let generatedAt: Date
    public let engineLabel: String
    public let usedFallbackRules: Bool
    public let regimeSummary: String
    public let explanation: String
    public let macroDrivers: [String]
    public let topActions: [LBDailyStrategyAction]
    public let holdingLayers: [LBDailyStrategyLayer]
    public let hedgeNotes: [String]
    public var comparisonHighlights: [String]
    public var reminders: [LBDailyStrategyReminder]

    public init(
        dateKey: String,
        generatedAt: Date,
        engineLabel: String,
        usedFallbackRules: Bool,
        regimeSummary: String,
        explanation: String,
        macroDrivers: [String],
        topActions: [LBDailyStrategyAction],
        holdingLayers: [LBDailyStrategyLayer],
        hedgeNotes: [String],
        comparisonHighlights: [String],
        reminders: [LBDailyStrategyReminder]
    ) {
        self.dateKey = dateKey
        self.generatedAt = generatedAt
        self.engineLabel = engineLabel
        self.usedFallbackRules = usedFallbackRules
        self.regimeSummary = regimeSummary
        self.explanation = explanation
        self.macroDrivers = macroDrivers
        self.topActions = topActions
        self.holdingLayers = holdingLayers
        self.hedgeNotes = hedgeNotes
        self.comparisonHighlights = comparisonHighlights
        self.reminders = reminders
    }
}

public extension AIPortfolioSnapshot {
    func fillingMissingFields(from reference: AIPortfolioSnapshot?) -> AIPortfolioSnapshot {
        guard let reference else {
            return self
        }

        let referencePositions = Dictionary(
            uniqueKeysWithValues: reference.positions.map { (Self.normalizedSymbol($0.symbol), $0) }
        )
        let mergedPositions = positions.map { position in
            guard let referencePosition = referencePositions[Self.normalizedSymbol(position.symbol)] else {
                return position
            }
            return position.fillingMissingFields(from: referencePosition)
        }

        return AIPortfolioSnapshot(
            generatedAt: generatedAt,
            accountSummary: accountSummary.fillingMissingFields(from: reference.accountSummary),
            positions: mergedPositions,
            topNews: Self.mergeUniqueByID(topNews, fallback: reference.topNews, minimumCount: 3),
            marketTemperatures: Self.mergeUniqueByID(
                marketTemperatures,
                fallback: reference.marketTemperatures,
                minimumCount: max(marketTemperatures.count, reference.marketTemperatures.count)
            ),
            fallbackUsage: Self.mergeUniqueStrings(fallbackUsage, reference.fallbackUsage),
            recentTrades: Self.mergeUniqueByID(recentTrades, fallback: reference.recentTrades, minimumCount: 3),
            derivatives: Self.mergeUniqueByID(derivatives, fallback: reference.derivatives, minimumCount: 2),
            macroTopics: Self.mergeUniqueByID(macroTopics, fallback: reference.macroTopics, minimumCount: 2)
        )
    }

    func recoveringMissingCoreData(from reference: AIPortfolioSnapshot?) -> AIPortfolioSnapshot {
        guard let reference else {
            return self
        }

        let enriched = fillingMissingFields(from: reference)
        let currentPositions = Dictionary(
            uniqueKeysWithValues: enriched.positions.map { (Self.normalizedSymbol($0.symbol), $0) }
        )
        let referencePositions = Dictionary(
            uniqueKeysWithValues: reference.positions.map { (Self.normalizedSymbol($0.symbol), $0) }
        )
        let mergedKeys = Set(currentPositions.keys).union(referencePositions.keys)
        let mergedPositions = mergedKeys.compactMap { key -> LBPosition? in
            if let current = currentPositions[key], let referencePosition = referencePositions[key] {
                return current.fillingMissingFields(from: referencePosition)
            }
            return currentPositions[key] ?? referencePositions[key]
        }
        .sorted(by: Self.positionSort)

        return AIPortfolioSnapshot(
            generatedAt: generatedAt,
            accountSummary: enriched.accountSummary,
            positions: mergedPositions,
            topNews: Self.mergeUniqueByID(enriched.topNews, fallback: reference.topNews),
            marketTemperatures: Self.mergeUniqueByID(enriched.marketTemperatures, fallback: reference.marketTemperatures),
            fallbackUsage: Self.mergeUniqueStrings(enriched.fallbackUsage, reference.fallbackUsage),
            recentTrades: Self.mergeUniqueByID(enriched.recentTrades, fallback: reference.recentTrades),
            derivatives: Self.mergeUniqueByID(enriched.derivatives, fallback: reference.derivatives),
            macroTopics: Self.mergeUniqueByID(enriched.macroTopics, fallback: reference.macroTopics)
        )
    }

    fileprivate static func normalizedSymbol(_ symbol: String) -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let dotIndex = trimmed.firstIndex(of: ".") else {
            return trimmed
        }
        let code = String(trimmed[..<dotIndex])
        let suffix = String(trimmed[dotIndex...])
        if suffix == ".HK", let numeric = Int(code) {
            return "\(numeric)\(suffix)"
        }
        return trimmed
    }

    fileprivate static func positionSort(_ lhs: LBPosition, _ rhs: LBPosition) -> Bool {
        let left = lhs.marketValueHKD ?? lhs.marketValue ?? 0
        let right = rhs.marketValueHKD ?? rhs.marketValue ?? 0
        if left == right {
            return normalizedSymbol(lhs.symbol) < normalizedSymbol(rhs.symbol)
        }
        return left > right
    }

    fileprivate static func mergeUniqueStrings(_ primary: [String], _ fallback: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in primary + fallback where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    fileprivate static func mergeUniqueByID<T: Identifiable>(
        _ primary: [T],
        fallback: [T],
        minimumCount: Int? = nil
    ) -> [T] where T.ID: Hashable {
        var seen = Set<T.ID>()
        var result: [T] = []

        for item in primary where seen.insert(item.id).inserted {
            result.append(item)
        }

        if let minimumCount {
            guard result.count < minimumCount else {
                return result
            }
            for item in fallback where seen.insert(item.id).inserted {
                result.append(item)
                if result.count >= minimumCount {
                    break
                }
            }
            return result
        }

        for item in fallback where seen.insert(item.id).inserted {
            result.append(item)
        }
        return result
    }
}

private extension LBAccountSummary {
    func fillingMissingFields(from reference: LBAccountSummary) -> LBAccountSummary {
        let referenceCurrencies = Dictionary(
            uniqueKeysWithValues: reference.currencies.map { ($0.currency.uppercased(), $0) }
        )
        let mergedCurrencies = AIPortfolioSnapshot.mergeUniqueByID(
            currencies.map { currency in
                currency.fillingMissingFields(from: referenceCurrencies[currency.currency.uppercased()] ?? currency)
            },
            fallback: reference.currencies
        )

        return LBAccountSummary(
            totalAssetsHKD: totalAssetsHKD ?? reference.totalAssetsHKD,
            availableCashHKD: availableCashHKD ?? reference.availableCashHKD,
            unrealizedPnlHKD: unrealizedPnlHKD ?? reference.unrealizedPnlHKD,
            currencies: mergedCurrencies,
            fxRatesToHKD: reference.fxRatesToHKD.merging(fxRatesToHKD) { _, new in new },
            notes: AIPortfolioSnapshot.mergeUniqueStrings(notes, reference.notes),
            source: source == .fallback && reference.source == .longbridge ? .longbridge : source
        )
    }
}

private extension LBCurrencyBalance {
    func fillingMissingFields(from reference: LBCurrencyBalance) -> LBCurrencyBalance {
        LBCurrencyBalance(
            currency: currency,
            netAssets: netAssets ?? reference.netAssets,
            availableCash: availableCash ?? reference.availableCash,
            withdrawCash: withdrawCash ?? reference.withdrawCash,
            buyPower: buyPower ?? reference.buyPower,
            source: source == .unavailable ? reference.source : source
        )
    }
}

private extension LBPosition {
    func fillingMissingFields(from reference: LBPosition) -> LBPosition {
        let resolvedName = Self.preferredName(primary: name, fallback: reference.name, symbol: symbol)
        let resolvedCurrentPrice = currentPrice ?? reference.currentPrice
        let resolvedCostPrice = costPrice ?? reference.costPrice
        let resolvedMarketValue = marketValue ?? resolvedCurrentPrice.map { quantity * $0 } ?? reference.marketValue
        let resolvedMarketValueHKD: Double? = {
            if let marketValueHKD {
                return marketValueHKD
            }
            if currency.uppercased() == "HKD" {
                return resolvedMarketValue
            }
            return reference.marketValueHKD
        }()
        let computedUnrealizedPnl: Double? = {
            guard let resolvedCurrentPrice, let resolvedCostPrice else {
                return nil
            }
            return (resolvedCurrentPrice - resolvedCostPrice) * quantity
        }()
        let resolvedUnrealizedPnl = unrealizedPnl ?? computedUnrealizedPnl ?? reference.unrealizedPnl
        let resolvedUnrealizedPnlHKD: Double? = {
            if let unrealizedPnlHKD {
                return unrealizedPnlHKD
            }
            if currency.uppercased() == "HKD" {
                return resolvedUnrealizedPnl
            }
            return reference.unrealizedPnlHKD
        }()
        let resolvedUnrealizedPnlPct: Double? = {
            if let unrealizedPnlPct {
                return unrealizedPnlPct
            }
            guard let resolvedCurrentPrice, let resolvedCostPrice, resolvedCostPrice > 0 else {
                return reference.unrealizedPnlPct
            }
            return ((resolvedCurrentPrice - resolvedCostPrice) / resolvedCostPrice) * 100
        }()
        let resolvedPriceSource: AIDataSource = {
            if currentPrice != nil {
                return priceSource == .unavailable ? reference.priceSource : priceSource
            }
            if reference.currentPrice != nil {
                return reference.priceSource
            }
            return priceSource
        }()

        return LBPosition(
            symbol: symbol,
            name: resolvedName,
            market: market,
            currency: currency,
            assetClass: assetClass,
            quantity: quantity,
            costPrice: resolvedCostPrice,
            currentPrice: resolvedCurrentPrice,
            marketValue: resolvedMarketValue,
            marketValueHKD: resolvedMarketValueHKD,
            unrealizedPnl: resolvedUnrealizedPnl,
            unrealizedPnlHKD: resolvedUnrealizedPnlHKD,
            unrealizedPnlPct: resolvedUnrealizedPnlPct,
            changePct: changePct ?? reference.changePct,
            changePct5d: changePct5d ?? reference.changePct5d,
            categoryName: categoryName ?? reference.categoryName,
            styleLabel: styleLabel ?? reference.styleLabel,
            signalScore: signalScore ?? reference.signalScore,
            signalZone: signalZone ?? reference.signalZone,
            trendState: trendState ?? reference.trendState,
            macroSignal: macroSignal ?? reference.macroSignal,
            newsSignal: newsSignal ?? reference.newsSignal,
            stanceHint: stanceHint ?? reference.stanceHint,
            watchItems: watchItems ?? reference.watchItems,
            priceSource: resolvedPriceSource,
            baseSource: baseSource,
            notes: AIPortfolioSnapshot.mergeUniqueStrings(notes, reference.notes)
        )
    }

    private static func preferredName(primary: String, fallback: String, symbol: String) -> String {
        let trimmedPrimary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPrimary.isEmpty == false, trimmedPrimary.uppercased() != symbol.uppercased() {
            return trimmedPrimary
        }
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedFallback.isEmpty == false {
            return trimmedFallback
        }
        return trimmedPrimary.isEmpty ? symbol : trimmedPrimary
    }
}

import Foundation

public enum NarrativeProviderKind: String, Codable, Sendable {
    case mock
    case openAICompatible = "openai-compatible"
}

public enum SummaryPeriodKind: String, Codable, Sendable {
    case day
    case week
    case month
}

public enum ReportKind: String, Codable, Sendable {
    case weekly
    case monthly
}

public enum StructuredInsightSeverity: String, Codable, Sendable {
    case positive
    case low
    case medium
    case high
}

public enum StructuredInsightKind: String, Codable, Sendable {
    case trend
    case anomaly
    case correlation
}

public enum HealthTone: String, Codable, Sendable {
    case positive
    case attention
    case neutral
}

public enum HealthStatus: String, Codable, Sendable {
    case improving
    case watch
    case stable
}

public enum SourceDimensionStatus: String, Codable, Sendable {
    case ready
    case attention
    case background
}

public enum ImporterKey: String, Codable, CaseIterable, Sendable, Identifiable {
    case annualExam = "annual_exam"
    case bloodTest = "blood_test"
    case bodyScale = "body_scale"
    case activity

    public var id: String { rawValue }
}

public enum ImportTaskStatus: String, Codable, Sendable {
    case running
    case completed
    case completedWithErrors = "completed_with_errors"
    case failed
}

public enum ImportRowStatus: String, Codable, Sendable {
    case imported
    case failed
    case skipped
}

public struct HealthSummaryPromptBundle: Codable, Sendable {
    public let templateId: String
    public let version: String
    public let systemPrompt: String
    public let userPrompt: String
}

public struct HealthSummarySectionedOutput: Codable, Sendable {
    public let periodKind: SummaryPeriodKind
    public let headline: String
    public let mostImportantChanges: [String]
    public let possibleReasons: [String]
    public let priorityActions: [String]
    public let continueObserving: [String]
    public let disclaimer: String
}

public struct HealthSummaryGenerationResult: Codable, Sendable {
    public let provider: NarrativeProviderKind
    public let model: String
    public let prompt: HealthSummaryPromptBundle
    public let output: HealthSummarySectionedOutput
}

public struct HealthOverviewDigest: Codable, Sendable {
    public let headline: String
    public let summary: String
    public let goodSignals: [String]
    public let needsAttention: [String]
    public let longTermRisks: [String]
    public let actionPlan: [String]
}

public struct HealthOverviewSpotlight: Codable, Sendable, Identifiable {
    public let label: String
    public let value: String
    public let tone: HealthTone
    public let detail: String

    public var id: String { label + value }
}

public struct HealthSourceDimensionCard: Codable, Sendable, Identifiable {
    public let key: String
    public let label: String
    public let latestAt: String?
    public let status: SourceDimensionStatus
    public let summary: String
    public let highlight: String

    public var id: String { key }
}

public struct HealthAnalysisMetric: Codable, Sendable, Identifiable {
    public let label: String
    public let value: String
    public let detail: String
    public let tone: HealthTone

    public var id: String { label + value }
}

public struct HealthDimensionAnalysis: Codable, Sendable, Identifiable {
    public let key: String
    public let kicker: String
    public let title: String
    public let summary: String
    public let goodSignals: [String]
    public let needsAttention: [String]
    public let longTermRisks: [String]
    public let actionPlan: [String]
    public let metrics: [HealthAnalysisMetric]

    public var id: String { key }
}

public struct HealthImportOption: Codable, Sendable, Identifiable {
    public let key: ImporterKey
    public let title: String
    public let description: String
    public let formats: [String]
    public let hints: [String]

    public var id: ImporterKey { key }
}

public struct AnnualExamMetricView: Codable, Sendable, Identifiable {
    public let metricCode: String
    public let label: String
    public let shortLabel: String
    public let unit: String
    public let latestValue: Double
    public let previousValue: Double?
    public let delta: Double?
    public let abnormalFlag: String
    public let referenceRange: String?
    public let meaning: String?
    public let practicalAdvice: String?

    public var id: String { metricCode }
}

public struct AnnualExamView: Codable, Sendable {
    public let latestTitle: String
    public let latestRecordedAt: String
    public let previousTitle: String?
    public let metrics: [AnnualExamMetricView]
    public let abnormalMetricLabels: [String]
    public let improvedMetricLabels: [String]
    public let highlightSummary: String
    public let actionSummary: String
}

public struct GeneticFindingView: Codable, Sendable, Identifiable {
    public let id: String
    public let geneSymbol: String
    public let traitLabel: String
    public let dimension: String
    public let riskLevel: String
    public let evidenceLevel: String
    public let summary: String
    public let suggestion: String
    public let recordedAt: String
    public let linkedMetricLabel: String?
    public let linkedMetricValue: String?
    public let linkedMetricFlag: String?
    public let plainMeaning: String?
    public let practicalAdvice: String?
}

public struct HealthReminderItem: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let severity: StructuredInsightSeverity
    public let summary: String
    public let suggestedAction: String
    public let indicatorMeaning: String?
    public let practicalAdvice: String?
}

public struct HealthTrendLine: Codable, Sendable, Identifiable {
    public let key: String
    public let label: String
    public let color: String
    public let unit: String
    public let yAxisId: String?

    public var id: String { key }
}

public struct TrendPoint: Codable, Sendable, Identifiable {
    public let date: String
    public let values: [String: Double]

    public var id: String { date }

    public init(date: String, values: [String: Double]) {
        self.date = date
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var date = ""
        var values: [String: Double] = [:]

        for key in container.allKeys {
            if key.stringValue == "date" {
                date = try container.decode(String.self, forKey: key)
                continue
            }

            if let value = try? container.decode(Double.self, forKey: key) {
                values[key.stringValue] = value
                continue
            }

            if let intValue = try? container.decode(Int.self, forKey: key) {
                values[key.stringValue] = Double(intValue)
            }
        }

        self.date = date
        self.values = values
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(date, forKey: DynamicCodingKey("date"))

        for (key, value) in values {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }
}

public struct HealthTrendChartModel: Codable, Sendable {
    public let title: String
    public let description: String
    public let defaultRange: String
    public let data: [TrendPoint]
    public let lines: [HealthTrendLine]
}

public struct MetricSummary: Codable, Sendable, Identifiable {
    public let metricCode: String
    public let metricName: String
    public let category: String
    public let unit: String
    public let sampleCount: Int
    public let latestValue: Double
    public let latestSampleTime: String
    public let historicalMean: Double?
    public let latestVsMean: Double?
    public let latestVsMeanPct: Double?
    public let trendDirection: String?
    public let monthOverMonth: Double?
    public let yearOverYear: Double?
    public let abnormalFlag: String
    public let referenceRange: String?

    public var id: String { metricCode }
}

public struct StructuredInsightEvidenceMetric: Codable, Sendable, Identifiable {
    public let metricCode: String
    public let metricName: String
    public let unit: String
    public let latestValue: Double
    public let latestSampleTime: String
    public let sampleCount: Int
    public let historicalMean: Double?
    public let latestVsMean: Double?
    public let latestVsMeanPct: Double?
    public let trendDirection: String?
    public let monthOverMonth: Double?
    public let yearOverYear: Double?
    public let abnormalFlag: String?
    public let referenceRange: String?
    public let relatedRecordIds: [String]

    public var id: String { metricCode + latestSampleTime }
}

public struct StructuredInsightEvidence: Codable, Sendable {
    public let summary: String
    public let metrics: [StructuredInsightEvidenceMetric]
}

public struct StructuredInsight: Codable, Sendable, Identifiable {
    public let id: String
    public let kind: StructuredInsightKind
    public let title: String
    public let severity: StructuredInsightSeverity
    public let evidence: StructuredInsightEvidence
    public let possibleReason: String
    public let suggestedAction: String
    public let disclaimer: String
}

public struct StructuredInsightsResult: Codable, Sendable {
    public let generatedAt: String
    public let userId: String
    public let metricSummaries: [MetricSummary]
    public let insights: [StructuredInsight]
}

public struct PlanItemReview: Codable, Sendable, Identifiable {
    public var id: String { planItemId }
    public let planItemId: String
    public let title: String
    public let dimension: String
    public let frequency: String
    public let targetValue: Double?
    public let targetUnit: String?
    public let expectedChecks: Int
    public let actualCompleted: Int
    public let completionRate: Double
    public let status: String
}

public struct PlanReviewData: Codable, Sendable {
    public let periodStart: String
    public let periodEnd: String
    public let totalItems: Int
    public let overallCompletionRate: Double
    public let items: [PlanItemReview]
    public let aiComment: String
}

public struct HealthReportSnapshotRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let reportType: ReportKind
    public let periodStart: String
    public let periodEnd: String
    public let createdAt: String
    public let title: String
    public let summary: HealthSummaryGenerationResult
    public let structuredInsights: StructuredInsightsResult
    public let planReview: PlanReviewData?
}

public struct HealthOverviewCard: Codable, Sendable, Identifiable {
    public let metricCode: String
    public let label: String
    public let value: String
    public let trend: String
    public let status: HealthStatus
    public let abnormalFlag: String
    public let meaning: String?

    public var id: String { metricCode }
}

public struct HealthHomePageData: Codable, Sendable {
    public let generatedAt: String
    public let disclaimer: String
    public let overviewHeadline: String
    public let overviewNarrative: String
    public let overviewDigest: HealthOverviewDigest
    public let overviewFocusAreas: [String]
    public let overviewSpotlights: [HealthOverviewSpotlight]
    public let sourceDimensions: [HealthSourceDimensionCard]
    public let dimensionAnalyses: [HealthDimensionAnalysis]
    public let importOptions: [HealthImportOption]
    public let overviewCards: [HealthOverviewCard]
    public let annualExam: AnnualExamView?
    public let geneticFindings: [GeneticFindingView]
    public let keyReminders: [HealthReminderItem]
    public let watchItems: [HealthReminderItem]
    public let latestNarrative: HealthSummaryGenerationResult
    public let charts: HealthCharts
    public let latestReports: [HealthReportSnapshotRecord]
}

public struct HealthCharts: Codable, Sendable {
    public let lipid: HealthTrendChartModel
    public let bodyComposition: HealthTrendChartModel
    public let activity: HealthTrendChartModel
    public let recovery: HealthTrendChartModel
}

public struct ReportsIndexData: Codable, Sendable {
    public let generatedAt: String
    public let weeklyReports: [HealthReportSnapshotRecord]
    public let monthlyReports: [HealthReportSnapshotRecord]
}

public struct ImportWarning: Codable, Sendable, Identifiable {
    public let code: String
    public let message: String
    public let header: String?
    public let rowNumber: Int?

    public var id: String { code + message + String(rowNumber ?? 0) }
}

public struct ImportRowResult: Codable, Sendable, Identifiable {
    public let rowNumber: Int
    public let status: ImportRowStatus
    public let metricCode: String?
    public let sourceField: String?
    public let errorMessage: String?

    public var id: String { "\(rowNumber)-\(status.rawValue)" }
}

public struct ImportExecutionResult: Codable, Sendable {
    public let importTaskId: String
    public let importerKey: ImporterKey
    public let filePath: String
    public let taskStatus: ImportTaskStatus
    public let totalRecords: Int
    public let successRecords: Int
    public let failedRecords: Int
    public let logSummary: [ImportRowResult]
    public let warnings: [ImportWarning]
}

public struct ImportTaskSummary: Codable, Sendable, Identifiable {
    public let importTaskId: String
    public let title: String
    public let importerKey: ImporterKey?
    public let taskType: String
    public let taskStatus: ImportTaskStatus
    public let sourceType: String
    public let sourceFile: String?
    public let startedAt: String
    public let finishedAt: String?
    public let totalRecords: Int
    public let successRecords: Int
    public let failedRecords: Int
    public let parseMode: String?

    public var id: String { importTaskId }

    public var isFinished: Bool {
        switch taskStatus {
        case .running:
            false
        case .completed, .completedWithErrors, .failed:
            true
        }
    }
}

public struct ImportTaskListResponse: Codable, Sendable {
    public let tasks: [ImportTaskSummary]
}

public struct ImportTaskResponse: Codable, Sendable {
    public let task: ImportTaskSummary
}

public struct ImportAcceptedResponse: Codable, Sendable {
    public let accepted: Bool
    public let task: ImportTaskSummary
}

public enum HealthKitMetricKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case weight
    case bodyFat
    case bmi
    case steps
    case distanceWalkingRunning
    case activeEnergy
    case exerciseMinutes
    case sleepMinutes

    public var id: String { rawValue }
}

public struct HealthKitMetricSampleInput: Codable, Sendable, Identifiable {
    public let kind: HealthKitMetricKind
    public let value: Double
    public let unit: String
    public let sampleTime: String
    public let sourceLabel: String?

    public init(
        kind: HealthKitMetricKind,
        value: Double,
        unit: String,
        sampleTime: String,
        sourceLabel: String? = nil
    ) {
        self.kind = kind
        self.value = value
        self.unit = unit
        self.sampleTime = sampleTime
        self.sourceLabel = sourceLabel
    }

    public var id: String {
        "\(kind.rawValue)-\(sampleTime)"
    }
}

public struct HealthKitSyncRequest: Codable, Sendable {
    public let samples: [HealthKitMetricSampleInput]

    public init(samples: [HealthKitMetricSampleInput]) {
        self.samples = samples
    }
}

public struct HealthKitSyncResult: Codable, Sendable {
    public let importTaskId: String
    public let taskStatus: ImportTaskStatus
    public let totalRecords: Int
    public let successRecords: Int
    public let failedRecords: Int
    public let syncedKinds: [HealthKitMetricKind]
    public let latestSampleTime: String?
}

public struct HealthKitSyncEnvelope: Codable, Sendable {
    public let result: HealthKitSyncResult
}

public enum AIChatMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

public struct AIChatMessage: Codable, Sendable, Identifiable {
    public let id: String
    public let role: AIChatMessageRole
    public let content: String
    public let createdAt: String?

    public init(
        id: String = UUID().uuidString,
        role: AIChatMessageRole,
        content: String,
        createdAt: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct AIChatRequest: Codable, Sendable {
    public let messages: [AIChatMessage]

    public init(messages: [AIChatMessage]) {
        self.messages = messages
    }
}

public struct AIChatResponse: Codable, Sendable {
    public let reply: AIChatMessage
    public let provider: String
    public let model: String
}

public struct PrivacyExportRequest: Codable, Sendable {
    public let scope: String
    public let format: String
    public let includeAuditLogs: Bool

    public init(scope: String = "all", format: String = "json", includeAuditLogs: Bool = false) {
        self.scope = scope
        self.format = format
        self.includeAuditLogs = includeAuditLogs
    }
}

public struct PrivacyDeleteRequest: Codable, Sendable {
    public let scope: String
    public let importTaskId: String?
    public let confirm: Bool

    public init(scope: String = "all", importTaskId: String? = nil, confirm: Bool = false) {
        self.scope = scope
        self.importTaskId = importTaskId
        self.confirm = confirm
    }
}

public struct PrivacyPlaceholderResponse: Codable, Sendable {
    public let status: String
    public let action: String
    public let enabled: Bool
    public let request: PrivacyRequestEcho
    public let requiresExplicitConfirmation: Bool?
    public let availableData: [String: Int]
    public let nextStep: String
}

public struct PrivacyRequestEcho: Codable, Sendable {
    public let scope: String
    public let format: String?
    public let includeAuditLogs: Bool?
    public let importTaskId: String?
    public let confirm: Bool?
}

// MARK: - Device Authorization

public struct DeviceAuthorizeRequest: Codable, Sendable {
    public let provider: String
    public let callbackUrl: String?

    public init(provider: String, callbackUrl: String? = nil) {
        self.provider = provider
        self.callbackUrl = callbackUrl
    }
}

public struct DeviceAuthorizeResponse: Codable, Sendable {
    public let authUrl: String
    public let state: String
    public let provider: String
}

public struct DeviceStatusResponse: Codable, Sendable {
    public let devices: [DeviceConnectionInfo]
}

public struct DeviceConnectionInfo: Codable, Sendable, Identifiable {
    public var id: String { provider }
    public let provider: String
    public let label: String
    public let isConnected: Bool
    public let isConfigured: Bool
    public let connectedAt: String?
    public let lastSyncAt: String?
}

public struct DeviceDisconnectRequest: Codable, Sendable {
    public let provider: String

    public init(provider: String) {
        self.provider = provider
    }
}

public struct DynamicCodingKey: CodingKey {
    public let stringValue: String
    public let intValue: Int?

    public init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    public init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    public init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - Auth Models

public struct PhoneCodeRequest: Codable, Sendable {
    public let phoneNumber: String
    public init(phoneNumber: String) { self.phoneNumber = phoneNumber }
}

public struct PhoneCodeResponse: Codable, Sendable {
    public let message: String
    public let expiresInSeconds: Int
    public let code: String?  // only in development
}

public struct VerifyCodeRequest: Codable, Sendable {
    public let phoneNumber: String
    public let code: String
    public let deviceLabel: String?
    public init(phoneNumber: String, code: String, deviceLabel: String? = nil) {
        self.phoneNumber = phoneNumber
        self.code = code
        self.deviceLabel = deviceLabel
    }
}

public struct VerifyCodeResponse: Codable, Sendable {
    public let token: String
    public let user: UserInfo
}

public struct UserInfo: Codable, Sendable {
    public let id: String
    public let displayName: String
    public let phoneNumber: String?
}

public struct UserMeResponse: Codable, Sendable {
    public let user: UserInfo
}

// MARK: - Device-based auth

public struct DeviceLoginRequest: Codable, Sendable {
    public let deviceId: String
    public let deviceLabel: String?
    public init(deviceId: String, deviceLabel: String? = nil) {
        self.deviceId = deviceId
        self.deviceLabel = deviceLabel
    }
}

public struct DeviceLoginResponse: Codable, Sendable {
    public let token: String
    public let user: UserInfo
    public let isNewUser: Bool
}

// MARK: - Health Plan

public enum PlanDimension: String, Codable, Sendable, CaseIterable, Identifiable {
    case exercise
    case diet
    case sleep
    case checkup

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .exercise: return "运动"
        case .diet: return "饮食"
        case .sleep: return "睡眠"
        case .checkup: return "体检"
        }
    }

    public var icon: String {
        switch self {
        case .exercise: return "figure.run"
        case .diet: return "fork.knife"
        case .sleep: return "moon.zzz.fill"
        case .checkup: return "stethoscope"
        }
    }

    public var color: String {
        switch self {
        case .exercise: return "#10b981"
        case .diet: return "#f59e0b"
        case .sleep: return "#6366f1"
        case .checkup: return "#ef4444"
        }
    }
}

public enum PlanFrequency: String, Codable, Sendable {
    case daily
    case weekly
    case once

    public var label: String {
        switch self {
        case .daily: return "每天"
        case .weekly: return "每周"
        case .once: return "一次性"
        }
    }
}

public enum PlanItemStatus: String, Codable, Sendable {
    case active
    case paused
    case completed
    case archived
}

public struct HealthSuggestion: Codable, Sendable, Identifiable {
    public let id: String
    public let batchId: String
    public let dimension: PlanDimension
    public let title: String
    public let description: String
    public let targetMetricCode: String?
    public let targetValue: Double?
    public let targetUnit: String?
    public let frequency: PlanFrequency
    public let timeHint: String?
    public let priority: Int
    public let createdAt: String
}

public struct HealthPlanItem: Codable, Sendable, Identifiable {
    public let id: String
    public let userId: String
    public let suggestionId: String?
    public let dimension: PlanDimension
    public let title: String
    public let description: String
    public let targetMetricCode: String?
    public let targetValue: Double?
    public let targetUnit: String?
    public let frequency: PlanFrequency
    public let timeHint: String?
    public let status: PlanItemStatus
    public let createdAt: String
    public let updatedAt: String
}

public struct HealthPlanCheck: Codable, Sendable, Identifiable {
    public let id: String
    public let planItemId: String
    public let checkDate: String
    public let actualValue: Double?
    public let isCompleted: Int
    public let source: String
    public let createdAt: String

    public var completed: Bool { isCompleted != 0 }
}

public struct HealthPlanStats: Codable, Sendable {
    public let activeCount: Int
    public let todayCompleted: Int
    public let todayTotal: Int
    public let weekCompletionRate: Double
}

public struct HealthPlanDashboard: Codable, Sendable {
    public let planItems: [HealthPlanItem]
    public let pausedItems: [HealthPlanItem]
    public let suggestions: [HealthSuggestion]
    public let todayChecks: [HealthPlanCheck]
    public let stats: HealthPlanStats
}

public struct GenerateSuggestionsResponse: Codable, Sendable {
    public let batchId: String
    public let suggestions: [HealthSuggestion]
}

public struct AcceptSuggestionRequest: Codable, Sendable {
    public let action: String
    public let suggestionId: String
    public let targetValue: Double?
    public let targetUnit: String?
    public let frequency: PlanFrequency?
    public let timeHint: String?

    public init(
        suggestionId: String,
        targetValue: Double? = nil,
        targetUnit: String? = nil,
        frequency: PlanFrequency? = nil,
        timeHint: String? = nil
    ) {
        self.action = "accept"
        self.suggestionId = suggestionId
        self.targetValue = targetValue
        self.targetUnit = targetUnit
        self.frequency = frequency
        self.timeHint = timeHint
    }
}

public struct AcceptSuggestionResponse: Codable, Sendable {
    public let planItem: HealthPlanItem
}

public struct ManualCheckInRequest: Codable, Sendable {
    public let action: String
    public let planItemId: String
    public let date: String?

    public init(planItemId: String, date: String? = nil) {
        self.action = "check_in"
        self.planItemId = planItemId
        self.date = date
    }
}

public struct ManualCheckInResponse: Codable, Sendable {
    public let check: HealthPlanCheck
}

public struct UpdatePlanStatusRequest: Codable, Sendable {
    public let action: String
    public let planItemId: String
    public let status: PlanItemStatus

    public init(planItemId: String, status: PlanItemStatus) {
        self.action = "update_status"
        self.planItemId = planItemId
        self.status = status
    }
}

public struct UpdatePlanStatusResponse: Codable, Sendable {
    public let planItem: HealthPlanItem
}

public struct UpdatePlanItemRequest: Codable, Sendable {
    public let action: String
    public let planItemId: String
    public let targetValue: Double?
    public let targetUnit: String?
    public let frequency: PlanFrequency?
    public let timeHint: String?

    public init(
        planItemId: String,
        targetValue: Double? = nil,
        targetUnit: String? = nil,
        frequency: PlanFrequency? = nil,
        timeHint: String? = nil
    ) {
        self.action = "update_item"
        self.planItemId = planItemId
        self.targetValue = targetValue
        self.targetUnit = targetUnit
        self.frequency = frequency
        self.timeHint = timeHint
    }
}

public struct UpdatePlanItemResponse: Codable, Sendable {
    public let planItem: HealthPlanItem
}

public struct PlanCompletionCheckResponse: Codable, Sendable {
    public let checks: [HealthPlanCheck]
}

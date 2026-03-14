import Foundation
import PortfolioWorkbenchMobileCore
import Security

enum AppAIProvider: String, Codable, CaseIterable, Identifiable {
    case anthropic
    case kimi
    case gemini

    var id: String { rawValue }

    var kind: AIProviderKind {
        switch self {
        case .anthropic:
            return .anthropic
        case .kimi:
            return .kimi
        case .gemini:
            return .gemini
        }
    }

    var displayName: String {
        switch self {
        case .anthropic:
            return "Claude"
        case .kimi:
            return "Kimi"
        case .gemini:
            return "Gemini"
        }
    }

    var defaultModelIdentifier: String {
        switch self {
        case .anthropic:
            return "claude-sonnet-4-5-20250929"
        case .kimi:
            return "moonshot-v1-8k"
        case .gemini:
            return "gemini-2.5-flash"
        }
    }

    var shortHint: String {
        switch self {
        case .anthropic:
            return "服务端可托管 Claude Key，研究表达通常更稳。"
        case .kimi:
            return "服务端可切 Moonshot 或 Kimi Coding 兼容通道。"
        case .gemini:
            return "海外链路模型，适合作为第三顺位备用。"
        }
    }
}

struct AppAIProviderProfile: Codable, Equatable {
    var provider: AppAIProvider
    var modelIdentifier: String

    init(provider: AppAIProvider, modelIdentifier: String? = nil) {
        self.provider = provider
        self.modelIdentifier = modelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? modelIdentifier!.trimmingCharacters(in: .whitespacesAndNewlines)
            : provider.defaultModelIdentifier
    }
}

struct AppAISettingsProfile: Codable, Equatable {
    var primaryProvider: AppAIProvider
    var enableFallbacks: Bool
    var providers: [AppAIProviderProfile]

    static let `default` = AppAISettingsProfile(
        primaryProvider: .anthropic,
        enableFallbacks: true,
        providers: AppAIProvider.allCases.map { AppAIProviderProfile(provider: $0) }
    )

    func profile(for provider: AppAIProvider) -> AppAIProviderProfile {
        providers.first(where: { $0.provider == provider }) ?? AppAIProviderProfile(provider: provider)
    }

    func updatingModel(_ modelIdentifier: String, for provider: AppAIProvider) -> AppAISettingsProfile {
        var next = self
        let trimmed = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = next.providers.firstIndex(where: { $0.provider == provider }) {
            next.providers[index].modelIdentifier = trimmed.isEmpty ? provider.defaultModelIdentifier : trimmed
        } else {
            next.providers.append(AppAIProviderProfile(provider: provider, modelIdentifier: trimmed))
        }
        next.providers.sort { $0.provider.rawValue < $1.provider.rawValue }
        return next
    }
}

final class AIProviderCredentialStore {
    static let shared = AIProviderCredentialStore()

    private let service = "com.xmly.portfolioworkbenchios.ai-provider"

    func loadAPIKey(for provider: AppAIProvider) -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            baseQuery(for: provider).merging([
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]) { _, new in new } as CFDictionary,
            &item
        )

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func persistAPIKey(_ value: String?, for provider: AppAIProvider) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let query = baseQuery(for: provider)

        if trimmed.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(trimmed.utf8)
        let status = SecItemCopyMatching(
            query.merging([
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]) { _, new in new } as CFDictionary,
            nil
        )

        if status == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            return
        }

        guard status == errSecItemNotFound else {
            return
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func baseQuery(for provider: AppAIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }
}

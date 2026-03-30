import Foundation
import SwiftUI
import VitalCommandMobileCore

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var state: LoadState<HealthHomePageData> = .idle
    @Published private(set) var isUsingCache = false
    @Published private(set) var cacheDate: Date?
    private(set) var lastError: Error?
    private var currentCacheScope: String?
    private var activeRequestID = UUID()
    private let fileStore = MobileFileStore(namespace: "HealthAI")

    /// Returns true if the last load failure was a 401 auth error
    var isAuthError: Bool {
        guard let apiError = lastError as? HealthAPIClientError else { return false }
        if case let .server(statusCode, _) = apiError { return statusCode == 401 }
        return false
    }

    var loadedPayload: HealthHomePageData? {
        if case let .loaded(data) = state {
            return data
        }
        return nil
    }

    func setError(_ message: String) {
        state = .failed(message)
    }

    // MARK: - Cache

    private static let legacyCacheKey = "vital-command.dashboard-cache"
    private static let legacyCacheDateKey = "vital-command.dashboard-cache-date"

    private func normalizedScope(_ cacheScope: String) -> String {
        let trimmed = cacheScope.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "anonymous" : trimmed
    }

    private func cacheKey(for cacheScope: String) -> String {
        "vital-command.dashboard-cache.\(normalizedScope(cacheScope))"
    }

    private func cacheDateKey(for cacheScope: String) -> String {
        "vital-command.dashboard-cache-date.\(normalizedScope(cacheScope))"
    }

    private func cacheFileName(for cacheScope: String) -> String {
        "dashboard-\(sanitizeCacheScope(cacheScope)).json"
    }

    private func clearLegacyCache() {
        UserDefaults.standard.removeObject(forKey: Self.legacyCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyCacheDateKey)
    }

    private func saveToCache(_ data: HealthHomePageData, cacheScope: String) {
        _ = fileStore.save(
            CachedPayload(value: data),
            fileName: cacheFileName(for: cacheScope)
        )
    }

    private func loadFromCache(cacheScope: String) -> CachedPayload<HealthHomePageData>? {
        if let cached = fileStore.load(
            CachedPayload<HealthHomePageData>.self,
            fileName: cacheFileName(for: cacheScope)
        ) {
            return cached
        }

        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: cacheScope)) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(HealthHomePageData.self, from: data) else {
            return nil
        }

        let migrated = CachedPayload(
            value: payload,
            cachedAt: UserDefaults.standard.object(forKey: cacheDateKey(for: cacheScope)) as? Date ?? Date()
        )
        _ = fileStore.save(migrated, fileName: cacheFileName(for: cacheScope))
        return migrated
    }

    private func cachedDate(cacheScope: String) -> Date? {
        if let cached = fileStore.load(
            CachedPayload<HealthHomePageData>.self,
            fileName: cacheFileName(for: cacheScope)
        ) {
            return cached.cachedAt
        }

        return UserDefaults.standard.object(forKey: cacheDateKey(for: cacheScope)) as? Date
    }

    private func sanitizeCacheScope(_ cacheScope: String) -> String {
        cacheScope.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    }

    private func resetForScopeChange(_ cacheScope: String) {
        currentCacheScope = cacheScope
        state = .idle
        isUsingCache = false
        cacheDate = nil
        lastError = nil
    }

    // MARK: - Load

    func load(using client: HealthAPIClient, cacheScope: String) async {
        let cacheScope = normalizedScope(cacheScope)
        let requestID = UUID()

        if case .loading = state, currentCacheScope == cacheScope {
            return
        }

        activeRequestID = requestID
        clearLegacyCache()

        if currentCacheScope != cacheScope {
            resetForScopeChange(cacheScope)
        }

        // If we have no data yet, try cache first for instant display
        if case .idle = state {
            if let cached = loadFromCache(cacheScope: cacheScope) {
                state = .loaded(cached.value)
                isUsingCache = true
                cacheDate = cached.cachedAt
            }
        }

        // Don't show spinner if we already have cached data
        if loadedPayload == nil {
            state = .loading
        }

        do {
            let freshData = try await client.fetchDashboard()
            guard activeRequestID == requestID else { return }
            state = .loaded(freshData)
            isUsingCache = false
            cacheDate = nil
            lastError = nil
            saveToCache(freshData, cacheScope: cacheScope)
        } catch {
            guard activeRequestID == requestID else { return }
            lastError = error
            // If we already have data (cached or previous), keep showing it
            if loadedPayload != nil {
                isUsingCache = true
                cacheDate = cachedDate(cacheScope: cacheScope)
                // Don't overwrite with error
            } else {
                // No cache, no data — try cache one more time
                if let cached = loadFromCache(cacheScope: cacheScope) {
                    state = .loaded(cached.value)
                    isUsingCache = true
                    cacheDate = cached.cachedAt
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }
}

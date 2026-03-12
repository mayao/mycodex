import Foundation
import SwiftUI
import VitalCommandMobileCore

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var state: LoadState<HealthHomePageData> = .idle
    @Published private(set) var isUsingCache = false
    @Published private(set) var cacheDate: Date?

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

    private static let cacheKey = "vital-command.dashboard-cache"
    private static let cacheDateKey = "vital-command.dashboard-cache-date"

    private func saveToCache(_ data: HealthHomePageData) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        if let encoded = try? encoder.encode(data) {
            UserDefaults.standard.set(encoded, forKey: Self.cacheKey)
            UserDefaults.standard.set(Date(), forKey: Self.cacheDateKey)
        }
    }

    private func loadFromCache() -> HealthHomePageData? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(HealthHomePageData.self, from: data)
    }

    private func cachedDate() -> Date? {
        UserDefaults.standard.object(forKey: Self.cacheDateKey) as? Date
    }

    // MARK: - Load

    func load(using client: HealthAPIClient) async {
        if case .loading = state {
            return
        }

        // If we have no data yet, try cache first for instant display
        if case .idle = state {
            if let cached = loadFromCache() {
                state = .loaded(cached)
                isUsingCache = true
                cacheDate = cachedDate()
            }
        }

        // Don't show spinner if we already have cached data
        if loadedPayload == nil {
            state = .loading
        }

        do {
            let freshData = try await client.fetchDashboard()
            state = .loaded(freshData)
            isUsingCache = false
            cacheDate = nil
            saveToCache(freshData)
        } catch {
            // If we already have data (cached or previous), keep showing it
            if loadedPayload != nil {
                isUsingCache = true
                cacheDate = cachedDate()
                // Don't overwrite with error
            } else {
                // No cache, no data — try cache one more time
                if let cached = loadFromCache() {
                    state = .loaded(cached)
                    isUsingCache = true
                    cacheDate = cachedDate()
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }
}

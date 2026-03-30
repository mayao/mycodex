import Foundation

public struct CachedPayload<Value: Codable & Sendable>: Codable, Sendable {
    public let cachedAt: Date
    public let value: Value

    public init(value: Value, cachedAt: Date = Date()) {
        self.cachedAt = cachedAt
        self.value = value
    }
}

public final class MobileFileStore: @unchecked Sendable {
    public let baseDirectory: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(namespace: String = "HealthAI", fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let rootDirectory =
            (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ))
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        self.baseDirectory = rootDirectory.appendingPathComponent(namespace, isDirectory: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    public init(baseDirectory: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    public func load<T: Decodable>(_ type: T.Type, fileName: String) -> T? {
        let url = fileURL(for: fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(type, from: data)
    }

    @discardableResult
    public func save<T: Encodable>(_ value: T, fileName: String) -> Bool {
        let url = fileURL(for: fileName)
        guard let data = try? encoder.encode(value) else {
            return false
        }
        do {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func remove(fileName: String) -> Bool {
        let url = fileURL(for: fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            return true
        }
        do {
            try fileManager.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    public func fileURL(for fileName: String) -> URL {
        baseDirectory.appendingPathComponent(fileName)
    }
}

public struct HealthKitSyncState: Codable, Sendable {
    public var pendingSamples: [HealthKitMetricSampleInput]
    public var lastCollectedAt: Date?
    public var lastAttemptedSyncAt: Date?
    public var lastSuccessfulSyncAt: Date?
    public var lastSuccessfulServerURL: String?
    public var lastErrorMessage: String?
    public var lastResult: HealthKitSyncResult?

    public init(
        pendingSamples: [HealthKitMetricSampleInput] = [],
        lastCollectedAt: Date? = nil,
        lastAttemptedSyncAt: Date? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        lastSuccessfulServerURL: String? = nil,
        lastErrorMessage: String? = nil,
        lastResult: HealthKitSyncResult? = nil
    ) {
        self.pendingSamples = pendingSamples
        self.lastCollectedAt = lastCollectedAt
        self.lastAttemptedSyncAt = lastAttemptedSyncAt
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastSuccessfulServerURL = lastSuccessfulServerURL
        self.lastErrorMessage = lastErrorMessage
        self.lastResult = lastResult
    }

    public var pendingSampleCount: Int {
        pendingSamples.count
    }
}

public final class HealthKitSyncStateStore: @unchecked Sendable {
    private let fileStore: MobileFileStore
    private let fileName: String

    public init(
        fileStore: MobileFileStore = MobileFileStore(namespace: "HealthAI"),
        fileName: String = "healthkit-sync-state.json"
    ) {
        self.fileStore = fileStore
        self.fileName = fileName
    }

    public func loadState() -> HealthKitSyncState {
        fileStore.load(HealthKitSyncState.self, fileName: fileName) ?? HealthKitSyncState()
    }

    @discardableResult
    public func mergePendingSamples(
        _ samples: [HealthKitMetricSampleInput],
        collectedAt: Date = Date()
    ) -> HealthKitSyncState {
        var state = loadState()
        var deduped = Dictionary(uniqueKeysWithValues: state.pendingSamples.map { ($0.id, $0) })
        for sample in samples {
            deduped[sample.id] = sample
        }

        state.pendingSamples = deduped.values.sorted {
            if $0.sampleTime == $1.sampleTime {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.sampleTime < $1.sampleTime
        }
        if samples.isEmpty == false {
            state.lastCollectedAt = collectedAt
        }
        _ = fileStore.save(state, fileName: fileName)
        return state
    }

    @discardableResult
    public func markSyncSuccess(
        sentSampleIDs: [String],
        result: HealthKitSyncResult,
        serverURL: String,
        syncedAt: Date = Date()
    ) -> HealthKitSyncState {
        var state = loadState()
        let sentSet = Set(sentSampleIDs)
        state.pendingSamples.removeAll { sentSet.contains($0.id) }
        state.lastAttemptedSyncAt = syncedAt
        state.lastSuccessfulSyncAt = syncedAt
        state.lastSuccessfulServerURL = serverURL
        state.lastErrorMessage = nil
        state.lastResult = result
        _ = fileStore.save(state, fileName: fileName)
        return state
    }

    @discardableResult
    public func markSyncFailure(
        message: String,
        attemptedAt: Date = Date()
    ) -> HealthKitSyncState {
        var state = loadState()
        state.lastAttemptedSyncAt = attemptedAt
        state.lastErrorMessage = message
        _ = fileStore.save(state, fileName: fileName)
        return state
    }
}

public enum HealthKitUploadTargetResolver {
    public static func prioritizeTargets(
        discoveredServerURLs: [String],
        currentServerURL: String?,
        savedServerURLs: [String]
    ) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        func append(_ candidate: String?) {
            guard let candidate = canonicalize(candidate), seen.insert(candidate).inserted else {
                return
            }
            ordered.append(candidate)
        }

        for url in discoveredServerURLs {
            append(url)
        }
        append(currentServerURL)

        let lanSaved = savedServerURLs.filter { isLikelyLAN(urlString: $0) }
        let remoteSaved = savedServerURLs.filter { !isLikelyLAN(urlString: $0) }
        for url in lanSaved + remoteSaved {
            append(url)
        }

        return ordered
    }

    public static func isLikelyLAN(urlString: String) -> Bool {
        guard let host = URL(string: canonicalize(urlString) ?? "")?.host?.lowercased() else {
            return false
        }

        if host.hasSuffix(".local") {
            return true
        }

        if host.hasPrefix("10.") || host.hasPrefix("192.168.") {
            return true
        }

        let octets = host.split(separator: ".")
        if octets.count == 4,
           octets[0] == "172",
           let second = Int(octets[1]),
           (16 ... 31).contains(second) {
            return true
        }

        return false
    }

    public static func canonicalize(_ urlString: String?) -> String? {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return nil
        }

        if raw.count > 1 {
            return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        }

        return raw
    }
}

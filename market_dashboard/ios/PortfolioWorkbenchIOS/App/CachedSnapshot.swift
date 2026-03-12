import Foundation

struct CachedSnapshot<Value: Codable>: Codable {
    let cachedAt: Date
    let payload: Value
}

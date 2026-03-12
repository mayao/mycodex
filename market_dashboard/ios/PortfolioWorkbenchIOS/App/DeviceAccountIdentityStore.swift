import Foundation
import Security

struct DeviceAccountProfile: Codable, Equatable {
    var installationID: String
    var deviceLabel: String
    var assignedUserID: String?
    var defaultPassword: String?
    var lastProvisionedAt: Date?
}

final class DeviceAccountIdentityStore {
    static let shared = DeviceAccountIdentityStore()

    private let service = "com.xmly.portfolioworkbenchios.device-account"
    private let account = "primary"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func resolveProfile(defaultDeviceLabel: String) -> DeviceAccountProfile {
        if var profile = load() {
            if profile.deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profile.deviceLabel = defaultDeviceLabel
                persist(profile)
            }
            return profile
        }

        let profile = DeviceAccountProfile(
            installationID: "dev_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            deviceLabel: defaultDeviceLabel,
            assignedUserID: nil,
            defaultPassword: nil,
            lastProvisionedAt: nil
        )
        persist(profile)
        return profile
    }

    func persist(_ profile: DeviceAccountProfile) {
        guard let data = try? encoder.encode(profile) else {
            return
        }

        let query = baseQuery()
        let status = SecItemCopyMatching(query.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, new in new } as CFDictionary, nil)

        if status == errSecSuccess {
            SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            return
        }

        guard status == errSecItemNotFound else {
            return
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func load() -> DeviceAccountProfile? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            baseQuery().merging([
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]) { _, new in new } as CFDictionary,
            &item
        )

        guard status == errSecSuccess,
              let data = item as? Data,
              let profile = try? decoder.decode(DeviceAccountProfile.self, from: data) else {
            return nil
        }
        return profile
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

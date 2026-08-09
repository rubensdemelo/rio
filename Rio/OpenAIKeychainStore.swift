import Combine
import Foundation
import Security

enum OpenAIKeychainStoreError: Error, Sendable, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidStoredValue
}

protocol OpenAIAPIKeyStore: Sendable {
    func load() throws -> String?
    func save(_ key: String) throws
    func remove() throws
}

struct KeychainOpenAIAPIKeyStore: OpenAIAPIKeyStore, Sendable {
    private let service: String
    private let account: String

    init(service: String = "com.rio.app", account: String = "openai-api-key") {
        self.service = service
        self.account = account
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                throw OpenAIKeychainStoreError.invalidStoredValue
            }
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case errSecItemNotFound:
            return nil
        default:
            throw OpenAIKeychainStoreError.unexpectedStatus(status)
        }
    }

    func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try remove()
            return
        }

        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw OpenAIKeychainStoreError.unexpectedStatus(status)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw OpenAIKeychainStoreError.unexpectedStatus(addStatus)
        }
    }

    func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAIKeychainStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

@MainActor
final class OpenAIProviderSettings: ObservableObject {
    @Published var apiKey = ""
    @Published private(set) var isConfigured = false
    @Published private(set) var errorMessage: String?

    let providerName = "OpenAI"
    private let keyStore: any OpenAIAPIKeyStore

    init(keyStore: any OpenAIAPIKeyStore = KeychainOpenAIAPIKeyStore()) {
        self.keyStore = keyStore
        reload()
    }

    func save() -> Bool {
        do {
            try keyStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            apiKey = ""
            errorMessage = nil
            reload()
            return true
        } catch {
            errorMessage = "Rio could not save your API key to the Keychain."
            return false
        }
    }

    func remove() {
        do {
            try keyStore.remove()
            apiKey = ""
            errorMessage = nil
            isConfigured = false
        } catch {
            errorMessage = "Rio could not remove your API key from the Keychain."
        }
    }

    func reload() {
        do {
            isConfigured = try keyStore.load() != nil
            errorMessage = nil
        } catch {
            isConfigured = false
            errorMessage = "Rio could not access your API key in the Keychain."
        }
    }
}

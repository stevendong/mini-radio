#if os(macOS) || os(iOS)
import Foundation
import Combine
import Security
import LocalAuthentication
import RadioCore

@MainActor
final class LibrarySyncController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var isSyncing = false
    @Published private(set) var serverAddress = ""
    @Published private(set) var hasSavedKey = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var message = "尚未开启同步"
    @Published private(set) var hasError = false

    var snapshot: (() throws -> LibrarySyncDocument)?
    var receive: ((LibrarySyncDocument) throws -> Void)?

    private var key = ""
    private var client: LibrarySyncClient?
    private var task: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var pendingChanges = false
    private var generation = UUID()
    private let available: Bool
    private let preferences = UserDefaults.standard
    private let keychainService = "com.stevendong.miniradio.library-sync"

    init(available: Bool) {
        self.available = available
        guard available else { return }
        serverAddress = preferences.string(forKey: "librarySync.server") ?? ""
        if serverAddress.isEmpty,
           let address = ProcessInfo.processInfo.environment["MINIRADIO_SYNC_SERVER"],
           let url = LibrarySyncClient.serverURL(address) {
            serverAddress = url.absoluteString
            preferences.set(serverAddress, forKey: "librarySync.server")
        }
        lastSyncedAt = preferences.object(forKey: "librarySync.lastSyncedAt") as? Date
        if preferences.bool(forKey: "librarySync.configured") {
            do {
                key = try readKey()
                hasSavedKey = !key.isEmpty
            } catch {
                hasError = true
                message = "暂时无法读取已保存密钥，请重新输入密钥后启用同步。"
            }
        }
        if preferences.bool(forKey: "librarySync.enabled"), hasSavedKey,
           let url = LibrarySyncClient.serverURL(serverAddress) {
            enabled = true
            client = LibrarySyncClient(server: url, key: key)
            message = "等待同步"
        }
    }

    func configure(server: String, key enteredKey: String) throws {
        guard available else { return }
        guard let url = LibrarySyncClient.serverURL(server) else { throw SyncServiceError.invalidServer }
        let trimmed = enteredKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedKey = trimmed.isEmpty && url.absoluteString == serverAddress ? key : trimmed
        guard !savedKey.isEmpty, savedKey.utf8.count <= 4_096,
              savedKey.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
            throw SyncServiceError.invalidKey
        }
        try saveKey(savedKey, server: url.absoluteString)
        cancelRequests()
        if serverAddress != url.absoluteString || key != savedKey {
            lastSyncedAt = nil
            preferences.removeObject(forKey: "librarySync.lastSyncedAt")
        }
        key = savedKey
        serverAddress = url.absoluteString
        hasSavedKey = true
        enabled = true
        hasError = false
        message = "等待同步"
        preferences.set(serverAddress, forKey: "librarySync.server")
        preferences.set(true, forKey: "librarySync.configured")
        preferences.set(true, forKey: "librarySync.enabled")
        client = LibrarySyncClient(server: url, key: savedKey)
        synchronize()
    }

    func disable() {
        cancelRequests()
        enabled = false
        hasError = false
        message = "同步已停用，本机数据已保留"
        preferences.set(false, forKey: "librarySync.enabled")
    }

    func localDataChanged() {
        guard enabled else { return }
        pendingChanges = true
        scheduleSync()
    }

    func synchronize() {
        debounceTask?.cancel()
        debounceTask = nil
        guard enabled, let client, let snapshot, let receive else { return }
        guard !isSyncing else { return }
        let outgoing: LibrarySyncDocument
        do { outgoing = try snapshot() }
        catch {
            hasError = true
            message = SyncServiceError.localStorageUnavailable.localizedDescription
            return
        }
        let requestGeneration = generation
        pendingChanges = false
        isSyncing = true
        hasError = false
        message = "正在同步…"
        task = Task { [weak self] in
            do {
                let incoming = try await client.synchronize(outgoing)
                try Task.checkCancellation()
                guard let self, self.generation == requestGeneration else { return }
                do { try receive(incoming) }
                catch { throw SyncServiceError.localStorageUnavailable }
                self.lastSyncedAt = Date()
                self.preferences.set(self.lastSyncedAt, forKey: "librarySync.lastSyncedAt")
                self.message = "同步成功"
                self.hasError = false
            } catch {
                guard let self, self.generation == requestGeneration, !Task.isCancelled else { return }
                self.hasError = true
                self.pendingChanges = true
                self.message = (error as? SyncServiceError)?.localizedDescription
                    ?? (error as? LibrarySyncError)?.localizedDescription
                    ?? SyncServiceError.unavailable.localizedDescription
            }
            guard let self, self.generation == requestGeneration else { return }
            self.isSyncing = false
            self.task = nil
            if self.pendingChanges && !self.hasError { self.scheduleSync() }
        }
    }

    func setActive(_ active: Bool) {
        pollingTask?.cancel()
        pollingTask = nil
        guard active else { return }
        synchronize()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                catch { return }
                guard let self else { return }
                self.synchronize()
            }
        }
    }

    private func scheduleSync() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 1_000_000_000) }
            catch { return }
            self?.synchronize()
        }
    }

    private func cancelRequests() {
        generation = UUID()
        task?.cancel()
        task = nil
        debounceTask?.cancel()
        debounceTask = nil
        isSyncing = false
    }

    private func keychainQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "sync-key"]
    }

    private func readKey() throws -> String {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let credential = try? JSONDecoder().decode(SyncCredential.self, from: data),
              credential.server == serverAddress else { throw SyncKeyError.unavailable }
        return credential.key
    }

    private func saveKey(_ value: String, server: String) throws {
        let data = try JSONEncoder().encode(SyncCredential(server: server, key: value))
        let query = keychainQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw SyncKeyError.unavailable }
        var entry = query
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw SyncKeyError.unavailable }
    }
}

private struct SyncCredential: Codable {
    let server: String
    let key: String
}

private enum SyncKeyError: LocalizedError {
    case unavailable
    var errorDescription: String? { "无法将同步密钥保存到系统钥匙串，请解锁设备后重试。" }
}
#endif

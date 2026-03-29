// Vault/VaultManager.swift
// GhostStream - AES-256-GCM encrypted media vault with biometric auth

import Foundation
import CryptoKit
import LocalAuthentication
import SwiftUI

@Observable
final class VaultManager: @unchecked Sendable {
    var isUnlocked: Bool = false
    var items: [VaultItem] = []
    var isLoading: Bool = false
    var error: String?

    private var symmetricKey: SymmetricKey?

    private var vaultDirectory: URL {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent(".vault")
        }
        let dir = documentsDir.appendingPathComponent(".vault", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var metadataURL: URL {
        vaultDirectory.appendingPathComponent("metadata.json")
    }

    // MARK: - Authentication

    func unlock() async throws {
        let context = LAContext()
        context.localizedFallbackTitle = "패스코드 사용"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) ||
              context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            throw VaultError.biometricUnavailable
        }

        let reason = "GhostStream 보관함 잠금 해제"
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        let success = try await context.evaluatePolicy(policy, localizedReason: reason)
        guard success else { throw VaultError.authFailed }

        // Load or create encryption key
        symmetricKey = try loadOrCreateKey()
        isUnlocked = true
        await loadMetadata()
    }

    func lock() {
        symmetricKey = nil
        isUnlocked = false
        items.removeAll()
    }

    // MARK: - File Operations

    func store(fileURL: URL, originalName: String? = nil) async throws {
        guard let key = symmetricKey else { throw VaultError.locked }

        let data = try Data(contentsOf: fileURL)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw VaultError.encryptionFailed }

        let itemID = UUID().uuidString
        let encryptedPath = vaultDirectory.appendingPathComponent(itemID)
        try combined.write(to: encryptedPath)

        let name = originalName ?? fileURL.lastPathComponent
        let ext = fileURL.pathExtension.lowercased()
        let type: VaultItem.MediaType = switch ext {
        case "gif": .gif
        case "mp4", "m4v", "mov": .video
        case "webm": .video
        default: .other
        }

        let item = VaultItem(
            id: itemID,
            originalName: name,
            mediaType: type,
            fileSize: Int64(data.count),
            dateAdded: .now,
            thumbnailData: nil
        )

        items.insert(item, at: 0)
        await saveMetadata()
    }

    func decrypt(item: VaultItem) async throws -> URL {
        guard let key = symmetricKey else { throw VaultError.locked }

        let src = vaultDirectory.appendingPathComponent(item.id)
        let encData = try Data(contentsOf: src)
        let sealedBox = try AES.GCM.SealedBox(combined: encData)
        let plainData = try AES.GCM.open(sealedBox, using: key)

        let ext = (item.originalName as NSString).pathExtension
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpURL = tmpDir
            .appendingPathComponent("vault_\(item.id).\(ext.isEmpty ? "mp4" : ext)")
        try plainData.write(to: tmpURL)
        return tmpURL
    }

    func delete(item: VaultItem) async throws {
        let path = vaultDirectory.appendingPathComponent(item.id)
        try FileManager.default.removeItem(at: path)
        items.removeAll { $0.id == item.id }
        await saveMetadata()
    }

    func export(item: VaultItem) async throws -> URL {
        return try await decrypt(item: item)
    }

    var totalSize: String {
        let total = items.reduce(0) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    // MARK: - Key Management

    private func loadOrCreateKey() throws -> SymmetricKey {
        let tag = "com.ghoststream.vault.key"

        // Try loading from Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tag,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }

        // Create new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw VaultError.keyStoreFailed }

        return newKey
    }

    // MARK: - Metadata Persistence

    private func saveMetadata() async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            try? data.write(to: metadataURL)
        }
    }

    private func loadMetadata() async {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL) else {
            items = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([VaultItem].self, from: data)) ?? []
    }
}

// MARK: - Models

struct VaultItem: Identifiable, Codable, Hashable {
    let id: String
    let originalName: String
    let mediaType: MediaType
    let fileSize: Int64
    let dateAdded: Date
    var thumbnailData: Data?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDate: String {
        dateAdded.formatted(date: .abbreviated, time: .shortened)
    }

    var icon: String {
        switch mediaType {
        case .video: return "play.circle.fill"
        case .gif: return "photo.circle.fill"
        case .other: return "doc.circle.fill"
        }
    }

    enum MediaType: String, Codable {
        case video, gif, other
    }
}

enum VaultError: LocalizedError {
    case locked
    case authFailed
    case biometricUnavailable
    case encryptionFailed
    case decryptionFailed
    case keyStoreFailed

    var errorDescription: String? {
        switch self {
        case .locked: "보관함이 잠겨 있습니다."
        case .authFailed: "인증에 실패했습니다."
        case .biometricUnavailable: "생체 인증을 사용할 수 없습니다."
        case .encryptionFailed: "파일 암호화에 실패했습니다."
        case .decryptionFailed: "파일 복호화에 실패했습니다."
        case .keyStoreFailed: "암호화 키 저장에 실패했습니다."
        }
    }
}

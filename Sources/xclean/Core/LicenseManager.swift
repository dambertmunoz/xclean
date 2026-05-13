import Foundation
import IOKit
import Security
import CryptoKit

/// One-machine license enforcement.
///
/// Talks to the xclean landing's `/api/license/{activate,validate,deactivate}`
/// endpoints. The platform UUID is salted + SHA-256 hashed before leaving the
/// machine so the server never sees the raw identifier.
///
/// Key + machineId live in the macOS Keychain. The current activation status
/// is cached in UserDefaults along with the last successful validation epoch,
/// which feeds the offline-grace policy (7 days from `lastValidatedAt`).
final class LicenseManager {
    static let shared = LicenseManager()

    enum State: Equatable {
        case unactivated
        case active(expiresAt: Date)
        case grace(expiresAt: Date, deadline: Date)
        case invalid(reason: String)
    }

    enum LicenseError: Error, LocalizedError {
        case missingLicenseKey
        case invalidKeyFormat
        case network(String)
        case server(reason: String, status: Int)

        var errorDescription: String? {
            switch self {
            case .missingLicenseKey: return "No license key stored."
            case .invalidKeyFormat:  return "Formato de key inválido (XCL-XXXX-XXXX-XXXX-XXXX)."
            case .network(let msg):  return "Sin conexión: \(msg)"
            case .server(let r, _):  return "Servidor: \(r)"
            }
        }
    }

    private let baseURL = URL(string: "https://xclean-seven.vercel.app")!
    private let salt = "xclean-v1-machine-salt"
    private let graceDays = 7

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 6
        c.timeoutIntervalForResource = 12
        return URLSession(configuration: c)
    }()

    // MARK: - public API

    func currentState() -> State {
        guard storedKey() != nil else { return .unactivated }
        guard let cached = cachedStatus() else { return .unactivated }
        let now = Date()
        if cached.expiresAt <= now {
            return .invalid(reason: "license_expired")
        }
        let graceDeadline = cached.lastValidatedAt.addingTimeInterval(TimeInterval(graceDays * 86_400))
        if now <= graceDeadline {
            return .active(expiresAt: cached.expiresAt)
        }
        return .grace(expiresAt: cached.expiresAt, deadline: graceDeadline)
    }

    @discardableResult
    func activate(key: String, machineLabel: String? = nil) async throws -> State {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard isValidKeyFormat(trimmed) else { throw LicenseError.invalidKeyFormat }
        let machineId = self.machineId()
        let label = machineLabel ?? Host.current().localizedName ?? "Mac"

        let resp = try await postJSON(
            path: "/api/license/activate",
            body: ["key": trimmed, "machineId": machineId, "machineLabel": label]
        )
        guard resp.statusCode == 200 else {
            let reason = (try? JSONDecoder().decode(ServerError.self, from: resp.data))?.reason
                ?? "http_\(resp.statusCode)"
            throw LicenseError.server(reason: reason, status: resp.statusCode)
        }
        let parsed = try JSONDecoder.iso8601.decode(ActivateResponse.self, from: resp.data)
        try storeKey(trimmed)
        let expiresAt = parsed.lastSeenAt.addingTimeInterval(365 * 86_400) // optimistic; refined on first validate
        cacheStatus(expiresAt: expiresAt, lastValidatedAt: Date())
        // Refresh immediately to get the canonical expiresAt.
        _ = try? await validateInternal(key: trimmed, machineId: machineId)
        return currentState()
    }

    @discardableResult
    func validate() async throws -> State {
        guard let key = storedKey() else { throw LicenseError.missingLicenseKey }
        return try await validateInternal(key: key, machineId: machineId())
    }

    func deactivate() async throws {
        guard let key = storedKey() else { throw LicenseError.missingLicenseKey }
        let resp = try await postJSON(
            path: "/api/license/deactivate",
            body: ["key": key, "machineId": machineId()]
        )
        guard resp.statusCode == 200 else {
            throw LicenseError.server(reason: "deactivate_failed", status: resp.statusCode)
        }
        clearStoredKey()
        clearCachedStatus()
    }

    func storedLicenseKey() -> String? { storedKey() }

    // MARK: - validation core

    private func validateInternal(key: String, machineId: String) async throws -> State {
        let resp = try await postJSON(
            path: "/api/license/validate",
            body: ["key": key, "machineId": machineId]
        )
        if resp.statusCode == 200 {
            let parsed = try JSONDecoder.iso8601.decode(ValidateResponse.self, from: resp.data)
            cacheStatus(expiresAt: parsed.expiresAt, lastValidatedAt: Date())
            return .active(expiresAt: parsed.expiresAt)
        }
        let reason = (try? JSONDecoder().decode(ServerError.self, from: resp.data))?.reason
            ?? "http_\(resp.statusCode)"
        // If we get a clear server-side rejection, clear the cache.
        if [403, 404].contains(resp.statusCode) {
            clearCachedStatus()
        }
        throw LicenseError.server(reason: reason, status: resp.statusCode)
    }

    // MARK: - machine fingerprint

    /// SHA-256(salt || rawPlatformUUID), hex-encoded.
    func machineId() -> String {
        let raw = rawPlatformUUID() ?? fallbackUUID()
        let salted = salt + raw
        let digest = SHA256.hash(data: Data(salted.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func rawPlatformUUID() -> String? {
        let mainPort: mach_port_t
        if #available(macOS 12.0, *) {
            mainPort = kIOMainPortDefault
        } else {
            mainPort = kIOMasterPortDefault
        }
        guard let dict = IOServiceMatching("IOPlatformExpertDevice") else { return nil }
        let entry = IOServiceGetMatchingService(mainPort, dict)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard
            let cf = IORegistryEntryCreateCFProperty(entry, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
        else { return nil }
        return cf.takeRetainedValue() as? String
    }

    /// Stable fallback if IOKit fails — synthesized once and persisted.
    private func fallbackUUID() -> String {
        let key = "xclean.fallback.machineid"
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let v = UUID().uuidString
        UserDefaults.standard.set(v, forKey: key)
        return v
    }

    // MARK: - key format

    func isValidKeyFormat(_ key: String) -> Bool {
        return key.range(of: "^XCL(-[A-Z2-9]{4}){4}$", options: .regularExpression) != nil
    }

    // MARK: - Keychain storage

    private let service = "xclean.license"
    private let accountKey = "license_key"

    private func storeKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LicenseError.network("Keychain store failed (\(status))")
        }
    }

    private func storedKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func clearStoredKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - cached status (UserDefaults)

    private struct CachedStatus {
        let expiresAt: Date
        let lastValidatedAt: Date
    }

    private let cacheKeyExpires = "xclean.license.cache.expiresAt"
    private let cacheKeyLastValidated = "xclean.license.cache.lastValidatedAt"

    private func cachedStatus() -> CachedStatus? {
        let d = UserDefaults.standard
        guard
            let exp = d.object(forKey: cacheKeyExpires) as? Date,
            let last = d.object(forKey: cacheKeyLastValidated) as? Date
        else { return nil }
        return CachedStatus(expiresAt: exp, lastValidatedAt: last)
    }

    private func cacheStatus(expiresAt: Date, lastValidatedAt: Date) {
        let d = UserDefaults.standard
        d.set(expiresAt, forKey: cacheKeyExpires)
        d.set(lastValidatedAt, forKey: cacheKeyLastValidated)
    }

    private func clearCachedStatus() {
        let d = UserDefaults.standard
        d.removeObject(forKey: cacheKeyExpires)
        d.removeObject(forKey: cacheKeyLastValidated)
    }

    // MARK: - HTTP

    private struct HTTPResp { let statusCode: Int; let data: Data }

    private func postJSON(path: String, body: [String: Any]) async throws -> HTTPResp {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            return HTTPResp(statusCode: code, data: data)
        } catch {
            throw LicenseError.network(error.localizedDescription)
        }
    }
}

private struct ActivateResponse: Decodable {
    let ok: Bool
    let rebound: Bool
    let activatedAt: Date
    let lastSeenAt: Date
}

private struct ValidateResponse: Decodable {
    let valid: Bool
    let expiresAt: Date
    let lastSeenAt: Date
}

private struct ServerError: Decodable {
    let reason: String?
}

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

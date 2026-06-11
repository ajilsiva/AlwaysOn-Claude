import Foundation

struct OAuthCredentials {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }
}

enum CredentialsError: Error {
    case notFound
}

/// Reads Claude Code's OAuth credentials. Keychain first — via the Apple-signed
/// /usr/bin/security binary, NOT SecItemCopyMatching: our ad-hoc cdhash changes
/// every rebuild and would re-trigger the Keychain ACL prompt, while the grant
/// to `security` persists after one "Always Allow". Falls back to the
/// credentials file. Token values are never logged or printed.
enum CredentialsProvider {
    static let keychainService = "Claude Code-credentials"

    static func load() -> Result<OAuthCredentials, CredentialsError> {
        if let payload = keychainPayload(), let creds = parse(payload) {
            return .success(creds)
        }
        if let payload = filePayload(), let creds = parse(payload) {
            return .success(creds)
        }
        return .failure(.notFound)
    }

    private static func keychainPayload() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }

        var trimmed = data
        while let last = trimmed.last, last == 0x0a || last == 0x0d {
            trimmed.removeLast()
        }
        // `security -w` prints hex when the item data is non-ASCII.
        if trimmed.first != UInt8(ascii: "{"), let decoded = dataFromHex(trimmed) {
            return decoded
        }
        return trimmed
    }

    private static func filePayload() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        return try? Data(contentsOf: url)
    }

    private static func parse(_ payload: Data) -> OAuthCredentials? {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        let expiresAt = (oauth["expiresAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } // epoch ms
        return OAuthCredentials(accessToken: token,
                                expiresAt: expiresAt,
                                subscriptionType: oauth["subscriptionType"] as? String)
    }

    private static func dataFromHex(_ data: Data) -> Data? {
        guard let string = String(data: data, encoding: .utf8),
              string.count.isMultiple(of: 2),
              string.allSatisfy(\.isHexDigit)
        else { return nil }
        var bytes = Data(capacity: string.count / 2)
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}

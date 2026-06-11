import Foundation

enum UsageFetchError: Error {
    case unauthorized
    case rateLimited(until: Date?)
    case server(Int)
    case decode
    case network
}

/// GET https://api.anthropic.com/api/oauth/usage — the same data Claude Code's
/// /usage command shows. Requires the OAuth beta header.
final class UsageAPIClient {
    private let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetch(token: String, claudeVersion: String?) async throws -> UsageResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/\(claudeVersion ?? "2.1.0")", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageFetchError.network
        }
        guard let http = response as? HTTPURLResponse else { throw UsageFetchError.network }

        switch http.statusCode {
        case 200:
            guard let decoded = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
                throw UsageFetchError.decode
            }
            return decoded
        case 401, 403:
            throw UsageFetchError.unauthorized
        case 429:
            throw UsageFetchError.rateLimited(until: Self.retryAfter(http))
        default:
            throw UsageFetchError.server(http.statusCode)
        }
    }

    /// Retry-After: integer seconds or an HTTP-date.
    static func retryAfter(_ http: HTTPURLResponse) -> Date? {
        guard let value = http.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = Double(value.trimmingCharacters(in: .whitespaces)) {
            return Date().addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}

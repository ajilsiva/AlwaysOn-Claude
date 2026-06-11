import Foundation

/// One rate-limit window from the OAuth usage endpoint. All fields optional —
/// the endpoint returns null windows and unknown extra keys freely.
struct UsageWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetsAtDate: Date? {
        resetsAt.flatMap(APIDate.parse)
    }
}

struct UsageResponse: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

/// The endpoint emits dates like "2026-06-11T08:39:59.560767+00:00" —
/// 6 fractional digits, which ISO8601DateFormatter's .withFractionalSeconds
/// (exactly 3 digits) rejects. Strip the fraction as a last resort.
enum APIDate {
    static func parse(_ string: String) -> Date? {
        if let date = fractional.date(from: string) { return date }
        if let date = plain.date(from: string) { return date }
        let stripped = string.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression)
        return plain.date(from: stripped)
    }

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

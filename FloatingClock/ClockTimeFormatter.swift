import Foundation

/// Each clock caches its whole-second text; tenth-second ticks only append a digit.
@MainActor
final class ClockTimeFormatter {
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var cachedSecond: Int64 = .min
    private var cachedTime = ""

    func string(from date: Date) -> String {
        let timestamp = date.timeIntervalSince1970
        let second = Int64(floor(timestamp))
        if second != cachedSecond {
            cachedSecond = second
            cachedTime = formatter.string(from: date)
        }
        let tenth = Int(floor(timestamp * 10)) % 10
        return "\(cachedTime).\(tenth)"
    }
}

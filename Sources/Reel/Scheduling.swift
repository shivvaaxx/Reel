import Foundation
import Network
import Observation

/// Watches the network so downloads can wait while on Personal Hotspot or Low Data Mode.
@MainActor @Observable
final class NetworkWatch {
    static let shared = NetworkWatch()

    private(set) var isExpensive = false     // Personal Hotspot, tethering, cellular
    private(set) var isConstrained = false   // Low Data Mode
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored var onChange: (() -> Void)?

    private init() {
        monitor.pathUpdateHandler = { path in
            let expensive = path.isExpensive, constrained = path.isConstrained
            let online = path.status == .satisfied
            Task { @MainActor in
                let watch = NetworkWatch.shared
                guard watch.isExpensive != expensive || watch.isConstrained != constrained
                        || watch.isOnline != online else { return }
                watch.isExpensive = expensive
                watch.isConstrained = constrained
                watch.isOnline = online
                watch.onChange?()
            }
        }
        monitor.start(queue: DispatchQueue(label: "reel.network"))
    }
}

/// When downloads are allowed to run, from Settings › Downloads.
enum Schedule {
    private static var defaults: UserDefaults { .standard }

    static var isEnabled: Bool { defaults.bool(forKey: "scheduleEnabled") }
    /// Minutes after midnight.
    static var start: Int { defaults.object(forKey: "scheduleStart") as? Int ?? 60 }       // 1:00 AM
    static var end: Int { defaults.object(forKey: "scheduleEnd") as? Int ?? 7 * 60 }      // 7:00 AM
    static var pauseOnCostlyNetwork: Bool { defaults.object(forKey: "pauseOnCostlyNetwork") as? Bool ?? true }

    /// Whether `date` falls in the window (which may cross midnight).
    static func isWithinWindow(_ date: Date = Date(), start: Int = Schedule.start, end: Int = Schedule.end) -> Bool {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start == end { return true }
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }

    static func timeText(_ minutes: Int) -> String {
        var parts = DateComponents()
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        let date = Calendar.current.date(from: parts) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

import SwiftUI
import WatchConnectivity

@main
struct PulseLoopWatchApp: App {
    @State private var connectivity = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchTabView()
                .environment(connectivity)
        }
    }
}

/// Manages WatchConnectivity session to sync data from the iPhone app.
@MainActor @Observable
final class WatchSessionManager: NSObject, WCSessionDelegate {
    var steps: Int = 0
    var heartRate: Int = 0
    var nextTask: String = ""
    var protocolDue: [String] = []
    var briefText: String = ""

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            if let s = applicationContext["steps"] as? Int { steps = s }
            if let hr = applicationContext["heartRate"] as? Int { heartRate = hr }
            if let task = applicationContext["nextTask"] as? String { nextTask = task }
            if let protocol_ = applicationContext["protocolDue"] as? [String] { protocolDue = protocol_ }
            if let brief = applicationContext["briefText"] as? String { briefText = brief }
        }
    }
}

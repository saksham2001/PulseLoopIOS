import Foundation
import WatchConnectivity
import SwiftData

/// Sends ring data, tasks, and protocol info to the Apple Watch companion.
/// Runs on the iPhone and pushes application context updates.
@MainActor @Observable
final class WatchSyncService: NSObject, WCSessionDelegate {
    private var session: WCSession?
    var isWatchReachable = false

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    /// Sends current state to the watch via application context.
    func syncToWatch(steps: Int, heartRate: Int, nextTask: String, protocolDue: [String], briefText: String) {
        guard let session, session.activationState == .activated else { return }
        let context: [String: Any] = [
            "steps": steps,
            "heartRate": heartRate,
            "nextTask": nextTask,
            "protocolDue": protocolDue,
            "briefText": briefText
        ]
        try? session.updateApplicationContext(context)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            isWatchReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}

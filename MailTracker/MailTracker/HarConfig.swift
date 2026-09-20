import Foundation
import Combine

class HarConfig: ObservableObject {
    static let shared = HarConfig()

    @Published var sessionId: String = ""
    @Published var userAgent: String = ""

    private let defaults = UserDefaults.standard

    func load() {
        sessionId = defaults.string(forKey: "sessionId") ?? ""
        userAgent = defaults.string(forKey: "userAgent") ?? ""
    }

    func save(sessionId: String, userAgent: String) {
        self.sessionId = sessionId
        self.userAgent = userAgent
        defaults.set(sessionId, forKey: "sessionId")
        defaults.set(userAgent, forKey: "userAgent")
    }

    var isConfigured: Bool {
        !sessionId.isEmpty
    }

    var isIOS: Bool {
        userAgent.contains("iPhone")
    }
}

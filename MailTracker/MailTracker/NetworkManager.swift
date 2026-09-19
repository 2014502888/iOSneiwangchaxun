import Foundation

class NetworkManager: NSObject, URLSessionDelegate {

    static let shared = NetworkManager()

    private let baseURL = "http://211.156.201.20:8012"
    private let userId = "E00000097801"
    private let from = "xm"

    private var token: String?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = [
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": HarConfig.shared.isIOS ? "zh-CN,zh-Hans;q=0.9" : "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7",
            "Pragma": "no-cache",
            "Cache-Control": "no-cache"
        ]
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func query(mailNo: String) async throws -> [String: Any] {
        let token = try await fetchToken()

        let url = URL(string: "\(baseURL)/so-novel-biz/mail/getMailTraceByMailNo?userId=\(userId)&from=\(from)&mailNo=\(mailNo)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        applyHeaders(to: &request)
        request.setValue("sessionId=\(HarConfig.shared.sessionId); xmToken=\(token)", forHTTPHeaderField: "Cookie")
        request.httpBody = "{\"mailNo\":\"\(mailNo)\"}".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "HTTP错误"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Network", code: -2, userInfo: [NSLocalizedDescriptionKey: "解析失败"])
        }
        return json
    }

    private func fetchToken() async throws -> String {
        if let token = token, !token.isEmpty { return token }

        let url = URL(string: "\(baseURL)/so-novel-biz/common/xmGetToken?userId=\(userId)&from=\(from)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("sessionId=\(HarConfig.shared.sessionId)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "获取token失败"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]],
              let first = dataArr.first,
              let inner = first["data"] as? [String: Any],
              let newToken = inner["token"] as? String, !newToken.isEmpty else {
            throw NSError(domain: "Network", code: -2, userInfo: [NSLocalizedDescriptionKey: "session验证失败"])
        }
        token = newToken
        return newToken
    }

    private func applyHeaders(to request: inout URLRequest) {
        let cfg = HarConfig.shared
        if !cfg.userAgent.isEmpty {
            request.setValue(cfg.userAgent, forHTTPHeaderField: "User-Agent")
        }
        request.setValue("http://211.156.201.20:8012", forHTTPHeaderField: "Origin")
        if cfg.isIOS {
            request.setValue("http://211.156.201.20:8012/so-novel-xm/", forHTTPHeaderField: "Referer")
            request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        } else {
            request.setValue("http://211.156.201.20:8012/sowebx/", forHTTPHeaderField: "Referer")
            request.setValue("com.holly.android.holly.uc_test", forHTTPHeaderField: "X-Requested-With")
            request.setValue("zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        }
    }

    // Allow HTTP (not HTTPS) for intranet
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
    }
}

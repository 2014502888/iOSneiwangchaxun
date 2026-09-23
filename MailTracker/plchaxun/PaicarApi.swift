import Foundation

// MARK: - 寄递派车 API 客户端（对应 PaicarApi.kt，PhalApi sign 签名）
// 签名/参数顺序与安卓、Flutter 完全一致：keys 用「插入顺序」（s→业务参数→token→user_id→timestamp→sign→keys），
// 登录 platform 固定 android（服务端仅接受该值）。此前的 sorted() 导致 keys 顺序不同、接口被服务端拒绝。

enum PaicarApi {
    static let base = "http://119.91.30.146/a/car/phalapi/public/"
    private static let salt = "*#&FD)#f34"
    private static let authExpiredCode = 410

    // 登录态
    static var token = ""
    static var userId = ""

    // 登录失效回调（token 被其他端顶掉时触发，UI 层注册跳登录确认）
    static var onAuthExpired: (() -> Void)?

    // MARK: 签名

    static func makePwd(_ plain: String) -> String { paicarMD5(salt + plain) }

    /// 与安卓 signed() 完全一致：
    /// 1) 参数按「插入顺序」追加：s → 业务参数 → token → user_id → timestamp
    /// 2) sign = MD5(按 key 字母序拼接的 value)
    /// 3) keys = 「插入顺序」的全部 key 用 & 连接（含 sign、keys），末尾加 &
    private static func signed(service: String, params: [(String, String)]) -> [String: String] {
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        var ordered: [(String, String)] = [("s", service)]
        ordered.append(contentsOf: params)
        ordered.append(("token", token))
        ordered.append(("user_id", userId))
        ordered.append(("timestamp", ts))
        let sortedKeys = ordered.map { $0.0 }.sorted()
        let concat = sortedKeys.map { k in ordered.first(where: { $0.0 == k })?.1 ?? "" }.joined()
        ordered.append(("sign", paicarMD5(concat)))
        ordered.append(("keys", ordered.map { $0.0 }.joined(separator: "&") + "&"))
        var dict: [String: String] = [:]
        for (k, v) in ordered { dict[k] = v }
        return dict
    }

    private static func parseBody(_ body: String, service: String) throws -> PaicarResult {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PaicarError.api("响应解析失败")
        }
        let r = PaicarResult.fromJson(obj)
        if service != "App.User_user.login" && (r.ret == authExpiredCode || r.ret < 0) {
            onAuthExpired?()
            throw PaicarError.authExpired
        }
        return r
    }

    static func get(_ service: String, params: [(String, String)]) async throws -> PaicarResult {
        let signed = signed(service: service, params: params)
        var comps = URLComponents(string: base)!
        var items: [URLQueryItem] = []
        for (k, v) in signed.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: k, value: v))
        }
        comps.queryItems = items
        guard let url = comps.url else { throw PaicarError.api("URL 错误") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let body = String(data: data, encoding: .utf8) else { throw PaicarError.api("空响应") }
        return try parseBody(body, service: service)
    }

    static func post(_ service: String, params: [(String, String)]) async throws -> PaicarResult {
        let signed = signed(service: service, params: params)
        let bodyString = signed.map { k, v in
            "\(k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k)=\(v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v)"
        }.joined(separator: "&")
        var req = URLRequest(url: URL(string: base)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        req.httpBody = bodyString.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let body = String(data: data, encoding: .utf8) else { throw PaicarError.api("空响应") }
        return try parseBody(body, service: service)
    }

    /// multipart 上传图片（对应 PaicarApi.uploadImage，字段 file）
    static func uploadImage(fileData: Data, fileName: String, extra: [(String, String)]) async throws -> [String: Any] {
        let signed = signed(service: "App.Upload_uploadImage.go", params: extra)
        let boundary = "paicar-\(Int(Date().timeIntervalSince1970 * 1000))"
        var req = URLRequest(url: URL(string: base)!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        var body = Data()
        for (k, v) in signed {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n".data(using: .utf8)!)
            body.append(v.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        let ext = (fileName as NSString).pathExtension.lowercased()
        let mime = ext == "png" ? "image/png" : (ext == "gif" ? "image/gif" : "image/jpeg")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let raw = String(data: data, encoding: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PaicarError.api("上传失败")
        }
        return obj
    }

    // MARK: 登录 / 账号

    static func login(userNo: String, plainPassword: String) async throws -> PaicarLoginInfo {
        let r = try await get("App.User_user.login", params: [
            ("user_no", userNo),
            ("password", makePwd(plainPassword)),
            ("version", "1.1.4"),
            ("platform", "android"),
        ])
        if !r.ok { throw PaicarError.api(r.msg.isEmpty ? "登录失败" : r.msg) }
        let info = PaicarLoginInfo.fromJson(r.dataMap)
        if !info.success {
            let msg = (r.dataMap["message"] as? String) ?? "账号或密码错误"
            throw PaicarError.api(msg)
        }
        token = info.token
        userId = info.userId
        return info
    }

    static func profile() async throws -> [String: Any] {
        let r = try await get("App.User_user.profile", params: [])
        if !r.ok { throw PaicarError.api("获取资料失败") }
        return (r.dataMap["profile"] as? [String: Any]) ?? [:]
    }

    static func changePwd(orgPwd: String, newPwd: String) async throws -> [String: Any] {
        let r = try await get("App.User_user.changePwd", params: [
            ("orgPassword", makePwd(orgPwd)),
            ("newPassword", makePwd(newPwd)),
        ])
        if !r.ok { throw PaicarError.api(r.msg.isEmpty ? "修改失败" : r.msg) }
        return r.dataMap
    }

    // MARK: 申请单

    static func applyOrderList(organId: String, rolesId: String) async throws -> [[String: Any]] {
        let r = try await get("App.DispatchCar_applyOrder.getList", params: [("organ_id", organId), ("roles_id", rolesId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func applyOrderDetail(id: String) async throws -> [String: Any] {
        let r = try await get("App.DispatchCar_applyOrder.getDetail", params: [("id", id)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return (r.dataMap["order"] as? [String: Any]) ?? [:]
    }

    static func applyOrderSave(id: String?, organId: String, customerListJson: String,
                               arrivalTime: String, number: String, liaisonId: String,
                               routeId: String, carSpecs: String, remarks: String) async throws -> PaicarResult {
        var p: [(String, String)] = [
            ("organ_id", organId),
            ("customerList", customerListJson),
            ("arrivalTime", arrivalTime),
            ("number", number),
            ("liaison_id", liaisonId),
            ("route_id", routeId),
            ("carSpecs", carSpecs),
            ("remarks", remarks),
        ]
        if let id = id, !id.isEmpty { p.append(("id", id)) }
        let service = (id != nil && !id!.isEmpty) ? "App.DispatchCar_applyOrder.update" : "App.DispatchCar_applyOrder.insert"
        return try await post(service, params: p)
    }

    static func applyOrderAction(id: String, action: String) async throws -> PaicarResult {
        try await post("App.DispatchCar_applyOrder.\(action)", params: [("id", id)])
    }

    static func applyOrderCheckNotFinishBill(organId: String) async throws -> [String: Any] {
        let r = try await get("App.DispatchCar_applyOrder.checkNotFinishBill", params: [("organ_id", organId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataMap
    }

    // MARK: 派车单

    static func dispatchOrderList(organId: String, rolesId: String, page: Int, perpage: Int) async throws -> [[String: Any]] {
        let r = try await get("App.DispatchCar_dispatchOrder.getList", params: [
            ("organ_id", organId), ("roles_id", rolesId),
            ("page", "\(page)"), ("perpage", "\(perpage)"),
        ])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func dispatchOrderDetail(id: String) async throws -> [String: Any] {
        let r = try await get("App.DispatchCar_dispatchOrder.getDetail", params: [("id", id)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataMap
    }

    static func dispatch(organId: String, carOrganId: String, carSpecsId: String, orderIdList: String) async throws -> PaicarResult {
        try await post("App.DispatchCar_dispatchOrder.dispatch", params: [
            ("organ_id", organId), ("carOrgan_id", carOrganId),
            ("carSpecs_id", carSpecsId), ("order_id_list", orderIdList),
        ])
    }

    static func arrangeCar(id: String, carNo: String, driverId: String) async throws -> PaicarResult {
        try await post("App.DispatchCar_dispatchOrder.arrangeCar", params: [
            ("id", id), ("carNo", carNo), ("driver_id", driverId),
        ])
    }

    static func finish(id: String, leaveTime: String, finishDesc: String, loadingNum: String) async throws -> PaicarResult {
        try await post("App.DispatchCar_dispatchOrder.finish", params: [
            ("id", id), ("leaveTime", leaveTime), ("finishDesc", finishDesc), ("loadingNum", loadingNum),
        ])
    }

    static func dispatchAction(id: String, action: String) async throws -> PaicarResult {
        try await post("App.DispatchCar_dispatchOrder.\(action)", params: [("id", id)])
    }

    static func deleteImage(id: String, file: String) async throws -> PaicarResult {
        try await post("App.DispatchCar_dispatchOrder.deleteImage", params: [("id", id), ("file", file)])
    }

    // MARK: 基础数据

    static func getCarSpecs() async throws -> [[String: Any]] {
        let r = try await get("App.Base_data.getCarSpecs", params: [])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func getDriver(organId: String, name: String = "") async throws -> [[String: Any]] {
        var p: [(String, String)] = [("organ_id", organId)]
        if !name.isEmpty { p.append(("name", name)) }
        let r = try await get("App.Base_data.getDriver", params: p)
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func getLiaison(organId: String) async throws -> [[String: Any]] {
        let r = try await get("App.Base_data.getLiaison", params: [("organ_id", organId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func getFleetList(organId: String) async throws -> [[String: Any]] {
        let r = try await get("App.Base_organ.getFleetList", params: [("organ_id", organId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func getFleetCarList(organId: String, specsId: String, carNo: String = "") async throws -> [[String: Any]] {
        var p: [(String, String)] = [("organ_id", organId), ("specs_id", specsId)]
        if !carNo.isEmpty { p.append(("carNo", carNo)) }
        let r = try await get("App.Base_fleetCar.getList", params: p)
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func getRouteList(organId: String) async throws -> [[String: Any]] {
        let r = try await get("App.Base_drivieRoute.getList", params: [("organ_id", organId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    static func getCustomer(organId: String) async throws -> [[String: Any]] {
        let r = try await get("App.Base_customer.getCustomer", params: [("organ_id", organId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList
    }

    // MARK: 看板

    static func applyOrderGather(organId: String, rolesId: String) async throws -> [String: Any] {
        let r = try await get("App.DispatchCar_applyOrder.getGather", params: [("organ_id", organId), ("roles_id", rolesId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList.first ?? [:]
    }

    static func dispatchOrderGather(organId: String, rolesId: String) async throws -> [String: Any] {
        let r = try await get("App.DispatchCar_dispatchOrder.getGather", params: [("organ_id", organId), ("roles_id", rolesId)])
        if !r.ok { throw PaicarError.api(r.msg) }
        return r.dataList.first ?? [:]
    }

    static func imageUrl(_ file: String) -> String { base + "uploads/" + file }

    // MARK: 快捷申请配置（UserDefaults 对应 SharedPreferences）

    static func defaultQuickCars() -> [[String: String]] {
        [
            ["customerId": "44", "customerName": "柒牌及卡尔美(品牌客户-罗山)", "number": "1000", "liaisonId": "78", "routeId": "62", "carSpecs": "5.3 米", "hour": "20:00", "shipment": "1", "enabled": "1"],
            ["customerId": "216", "customerName": "福建省晋江市康健食品有限公司", "number": "1000", "liaisonId": "78", "routeId": "35", "carSpecs": "5.3 米", "hour": "16:00", "shipment": "1", "enabled": "1"],
            ["customerId": "230", "customerName": "陈琳莉（国内业务合同）", "number": "1000", "liaisonId": "78", "routeId": "33", "carSpecs": "5.3 米", "hour": "17:00", "shipment": "1", "enabled": "1"],
            ["customerId": "253", "customerName": "泉州初觅食刻品牌管理有限公司", "number": "3000", "liaisonId": "78", "routeId": "31", "carSpecs": "9.6 米", "hour": "19:00", "shipment": "1", "enabled": "1"],
            ["customerId": "45", "customerName": "福建安踏物流(品牌客户-基地)", "number": "1000", "liaisonId": "222", "routeId": "59", "carSpecs": "5.3 米", "hour": "10:00", "shipment": "1", "enabled": "1"],
            ["customerId": "45", "customerName": "福建安踏物流(品牌客户-基地)", "number": "1000", "liaisonId": "222", "routeId": "64", "carSpecs": "5.3 米", "hour": "18:00", "shipment": "1", "enabled": "1"],
            ["customerId": "45", "customerName": "福建安踏物流(品牌客户-基地)", "number": "1000", "liaisonId": "222", "routeId": "101", "carSpecs": "5.3 米", "hour": "23:00", "shipment": "1", "enabled": "1"],
        ]
    }

    private static let quickCarsKey = "paicar_quick_cars"
    static func loadQuickCars() -> [[String: String]] {
        guard let raw = UserDefaults.standard.string(forKey: quickCarsKey),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return defaultQuickCars()
        }
        return arr.map { row in
            var m: [String: String] = [:]
            for (k, v) in row { m[k] = (v as? String) ?? "\(v)" }
            return m
        }
    }

    static func saveQuickCars(_ cars: [[String: String]]) {
        let arr = cars.map { $0 }
        if let data = try? JSONSerialization.data(withJSONObject: arr) {
            UserDefaults.standard.set(String(data: data, encoding: .utf8) ?? "", forKey: quickCarsKey)
        }
    }

    private static func quickArrival(hour: String) -> String {
        let now = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: now) + " " + hour
    }

    /// 一键创建一条快捷申请单，返回新单 id
    static func quickApplyCar(_ spec: [String: String]) async throws -> String {
        let profile = try await PaicarProfileHolder.load()
        let cust: [[String: Any]] = [[
            "id": spec["customerId"] ?? "",
            "customerName": spec["customerName"] ?? "",
            "number": spec["number"] ?? "",
            "shipment": spec["shipment"] == "1" ? 1 : 0,
        ]]
        let jsonData = try JSONSerialization.data(withJSONObject: cust)
        let json = String(data: jsonData, encoding: .utf8) ?? ""
        let r = try await post("App.DispatchCar_applyOrder.insert", params: [
            ("organ_id", profile.organId),
            ("customerList", json),
            ("arrivalTime", quickArrival(hour: spec["hour"] ?? "20:00")),
            ("number", spec["number"] ?? "1000"),
            ("liaison_id", spec["liaisonId"] ?? ""),
            ("route_id", spec["routeId"] ?? ""),
            ("carSpecs", spec["carSpecs"] ?? ""),
            ("remarks", ""),
        ])
        if !r.ok { throw PaicarError.api(r.msg.isEmpty ? "申请失败" : r.msg) }
        let id = (r.dataMap["id"] as? String) ?? ""
        if id.isEmpty { throw PaicarError.api("申请失败：未返回单号") }
        return id
    }

    /// 一键撤回并删除：001 先撤回成 000 再删；000 直接删
    static func quickRecall(id: String) async throws {
        try? await post("App.DispatchCar_applyOrder.recall", params: [("id", id)])
        let r2 = try await post("App.DispatchCar_applyOrder.delete", params: [("id", id)])
        if !r2.ok { throw PaicarError.api(r2.msg.isEmpty ? "删除失败" : r2.msg) }
    }

    private static let quickIdsKey = "paicar_quick_ids"
    static func loadQuickIds() -> [String] {
        guard let raw = UserDefaults.standard.string(forKey: quickIdsKey),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return arr
    }

    static func saveQuickIds(_ ids: [String]) {
        if let data = try? JSONSerialization.data(withJSONObject: ids) {
            UserDefaults.standard.set(String(data: data, encoding: .utf8) ?? "", forKey: quickIdsKey)
        }
    }
}

// MARK: - 登录态存储（对应 PaicarSession）

enum PaicarSession {
    private static let kToken = "paicar_token"
    private static let kUser = "paicar_user_id"
    private static let kUserNo = "paicar_user_no"
    private static let kUserPwd = "paicar_user_pwd"

    static var loggedIn: Bool { PaicarApi.token.isEmpty == false }

    static var savedUserNo: String {
        UserDefaults.standard.string(forKey: kUserNo) ?? ""
    }
    static var savedUserPwd: String {
        UserDefaults.standard.string(forKey: kUserPwd) ?? ""
    }

    static func load() {
        PaicarApi.token = UserDefaults.standard.string(forKey: kToken) ?? ""
        PaicarApi.userId = UserDefaults.standard.string(forKey: kUser) ?? ""
    }

    static func save(token: String, userId: String, userNo: String, userPwd: String = "") {
        let d = UserDefaults.standard
        d.set(token, forKey: kToken)
        d.set(userId, forKey: kUser)
        d.set(userNo, forKey: kUserNo)
        if !userPwd.isEmpty { d.set(userPwd, forKey: kUserPwd) }
        PaicarApi.token = token
        PaicarApi.userId = userId
    }

    static func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: kToken)
        d.removeObject(forKey: kUser)
        PaicarApi.token = ""
        PaicarApi.userId = ""
    }
}

// MARK: - 全局 Profile 缓存（对应 PaicarProfileHolder）

enum PaicarProfileHolder {
    static var profile: PaicarProfile?
    static var loading = false

    static func load() async throws -> PaicarProfile {
        if let p = profile { return p }
        let j = try await PaicarApi.profile()
        let p = PaicarProfile.fromJson(j)
        profile = p
        return p
    }
}

// MARK: - 全局脏标记（对应 PaicarApp.finishedDirty / dispatchDirty）

enum PaicarFlags {
    static var finishedDirty = false
    static var dispatchDirty = false
}

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportDelegate: NSObject, UIDocumentPickerDelegate {
    static let shared = ImportDelegate()
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        HarImporter.importHar(from: url)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true)
    }
}

struct TraceNode: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let desc: String
    let province: String
    let city: String
    let orgName: String
    let orgCode: String
}

struct MailResult: Identifiable {
    let id = UUID()
    let mailNum: String
    var traces: [TraceNode]
    var weight: String
    var fee: String
    var destProvince: String
    var destCity: String
    var error: String?
    var isDuplicate: Bool = false
}

enum ResultTab: String, CaseIterable, Identifiable {
    case success, failed, duplicate
    var id: String { rawValue }
}

enum TrackParsing {
    static func isValidMailNum(_ digits: String) -> Bool {
        guard digits.count == 13 else { return false }
        guard let first = digits.first else { return false }
        return first == "1" || first == "8" || first == "9"
    }
    static func parseInput(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let tokens = normalized.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" || $0 == ";" || $0 == "；" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var valid: [String] = []
        for token in tokens {
            var digits = ""; var segments: [String] = []
            for ch in token {
                if let ascii = ch.asciiValue, (48...57).contains(ascii) { digits.append(ch) }
                else if !digits.isEmpty { segments.append(digits); digits = "" }
            }
            if !digits.isEmpty { segments.append(digits) }
            for seg in segments {
                if seg.count == 13, isValidMailNum(seg) { valid.append(seg) }
                else if seg.count > 14 {
                    for i in 0...(seg.count - 13) {
                        let s = seg.index(seg.startIndex, offsetBy: i)
                        let e = seg.index(s, offsetBy: 13)
                        let sub = String(seg[s..<e])
                        if let first = sub.first, first == "1" || first == "8" || first == "9" { valid.append(sub); break }
                    }
                }
            }
        }
        return valid
    }
}

final class AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()
    init(value: Int) { self.count = value }
    func wait() async {
        await withCheckedContinuation { cont in
            lock.lock()
            if count > 0 { count -= 1; lock.unlock(); cont.resume() }
            else { waiters.append(cont); lock.unlock() }
        }
    }
    func signal() {
        lock.lock()
        if !waiters.isEmpty { let w = waiters.removeFirst(); lock.unlock(); w.resume() }
        else { count += 1; lock.unlock() }
    }
}

private final class Ticker {
    private var task: Task<Void, Never>?
    func start(interval: TimeInterval = 0.1, _ block: @escaping () -> Void) {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                await MainActor.run { block() }
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
}

final class QueryEngine: ObservableObject {
    @Published var inputText = ""
    @Published var isQuerying = false
    @Published var total = 0
    @Published var completed = 0
    @Published var elapsedSeconds: Double = 0
    @Published var results: [MailResult] = []
    @Published var concurrency = 2
    private var currentTask: Task<Void, Never>?
    private let ticker = Ticker()

    var successResults: [MailResult] { results.filter { $0.error == nil && !$0.isDuplicate } }
    var failedResults: [MailResult] { results.filter { $0.error != nil } }
    var duplicateResults: [MailResult] { results.filter { $0.isDuplicate } }

    func start() {
        guard !isQuerying else { return }
        let nums = TrackParsing.parseInput(inputText)
        guard !nums.isEmpty else { return }
        let startDate = Date()
        total = nums.count; completed = 0; results = []; isQuerying = true
        currentTask = Task { [weak self] in await self?.run(nums: nums, start: startDate) }
        ticker.start { [weak self] in self?.elapsedSeconds = Date().timeIntervalSince(startDate) }
    }
    func cancel() {
        currentTask?.cancel(); currentTask = nil; ticker.stop(); isQuerying = false
    }

    @MainActor
    private func run(nums: [String], start: Date) async {
        defer {
            if !Task.isCancelled { isQuerying = false; ticker.stop(); elapsedSeconds = Date().timeIntervalSince(start) }
        }
        let semaphore = AsyncSemaphore(value: concurrency)
        var collected: [Int: MailResult] = [:]
        await withTaskGroup(of: (Int, MailResult).self) { group in
            for (index, num) in nums.enumerated() {
                if Task.isCancelled { break }
                group.addTask {
                    await semaphore.wait()
                    defer { await semaphore.signal() }
                    if Task.isCancelled {
                        return (index, MailResult(mailNum: num, traces: [], weight: "", fee: "", destProvince: "", destCity: "", error: "已取消"))
                    }
                    do {
                        let json = try await NetworkManager.shared.query(mailNo: num)
                        return (index, self.parseResult(num, json: json))
                    } catch {
                        do {
                            let json = try await NetworkManager.shared.query(mailNo: num)
                            return (index, self.parseResult(num, json: json))
                        } catch {
                            return (index, MailResult(mailNum: num, traces: [], weight: "", fee: "", destProvince: "", destCity: "", error: "查询失败"))
                        }
                    }
                }
            }
            for await (index, result) in group {
                collected[index] = result
                completed = collected.count
                var ordered = (0..<nums.count).compactMap { collected[$0] }
                var seen2 = Set<String>()
                for i in ordered.indices {
                    if seen2.contains(ordered[i].mailNum) { ordered[i].isDuplicate = true }
                    else { seen2.insert(ordered[i].mailNum) }
                }
                results = ordered
            }
        }
    }

    private func parseResult(_ mailNo: String, json: [String: Any]) -> MailResult {
        var list: [[String: Any]]?
        if let data = json["data"] as? [String: Any], let l = data["data"] as? [[String: Any]] { list = l }
        else if let l = json["data"] as? [[String: Any]] { list = l }
        guard let l = list, !l.isEmpty else {
            return MailResult(mailNum: mailNo, traces: [], weight: "", fee: "", destProvince: "", destCity: "", error: "无物流信息")
        }
        var items: [TraceNode] = []; var weight = ""; var fee = ""
        for item in l { flatten(item, into: &items, weight: &weight, fee: &fee) }
        items.sort { $0.time > $1.time }
        var destCity = ""
        for t in items {
            var s = t.desc
            if let range = s.range(of: "发往:") { s = String(s[range.upperBound...]) }
            else if let range = s.range(of: "发往：") { s = String(s[range.upperBound...]) }
            else { continue }
            while s.first == " " || s.first == "　" { s.removeFirst() }
            if let end = s.firstIndex(of: " ") { s = String(s[..<end]) }
            destCity = s; break
        }
        let destProvince = AreaUtil.shared.getProvinceByCity(destCity)
        return MailResult(mailNum: mailNo, traces: items, weight: weight, fee: fee, destProvince: destProvince, destCity: destCity, error: nil)
    }

    private func flatten(_ node: [String: Any], into items: inout [TraceNode], weight: inout String, fee: inout String) {
        let time = node["opTime"] as? String ?? ""
        let title = node["opName"] as? String ?? ""
        var desc = ""
        if let org = node["opOrgName"] as? String, !org.isEmpty { desc = org }
        if let opDesc = node["opDesc"] as? String, !opDesc.isEmpty { if !desc.isEmpty { desc += " - " }; desc += opDesc }
        if let operatorName = node["operatorName"] as? String, !operatorName.isEmpty { if !desc.isEmpty { desc += " - " }; desc += "操作员: \(operatorName)" }
        let province = node["opOrgProvName"] as? String ?? ""
        let city = node["opOrgCity"] as? String ?? ""
        let orgName = node["opOrgName"] as? String ?? ""
        let orgCode = node["opOrgCode"] as? String ?? ""
        if weight.isEmpty, let opDesc = node["opDesc"] as? String, let range = opDesc.range(of: "重量:") {
            let s = String(opDesc[range.upperBound...])
            if let match = s.range(of: #"\d+\.?\d*\s*[gGkKmM]+"#, options: .regularExpression) { weight = String(s[match]) }
        }
        if fee.isEmpty, let opDesc = node["opDesc"] as? String, let range = opDesc.range(of: "基本资费:") {
            let s = String(opDesc[range.upperBound...])
            if let match = s.range(of: #"\d+\.?\d*\s*元"#, options: .regularExpression) { fee = String(s[match]) }
        }
        if !time.isEmpty || !title.isEmpty {
            items.append(TraceNode(time: time, title: title, desc: desc, province: province, city: city, orgName: orgName, orgCode: orgCode))
        }
        if let children = node["children"] as? [[String: Any]] {
            for child in children { flatten(child, into: &items, weight: &weight, fee: &fee) }
        }
    }
}

struct ContentView: View {
    @StateObject private var engine = QueryEngine()
    @State private var selectedTab: ResultTab = .success
    @State private var selectedResult: MailResult?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                inputSection
                if engine.isQuerying { progressBar }
                if !engine.results.isEmpty || engine.isQuerying { statsAndTabs }
                resultContent
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { engine.inputText = ""; engine.results = [] } label: {
                        Image(systemName: "trash").foregroundColor(.blue)
                    }.disabled(engine.inputText.isEmpty)
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Button { if engine.concurrency > 1 { engine.concurrency -= 1 } } label: {
                            Image(systemName: "minus.circle.fill").foregroundColor(.blue)
                        }
                        Text("\(engine.concurrency)").frame(width: 24).multilineTextAlignment(.center)
                        Button { if engine.concurrency < 20 { engine.concurrency += 1 } } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(.blue)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
                        picker.delegate = ImportDelegate.shared
                        picker.allowsMultipleSelection = false
                        UIApplication.shared.windows.first?.rootViewController?.present(picker, animated: true)
                    } label: {
                        Image(systemName: "doc.badge.gearshape").foregroundColor(.blue)
                    }
                }
            }
            .sheet(item: $selectedResult) { r in DetailSheet(result: r) }
        }
        .navigationViewStyle(.stack)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if engine.total > 0 {
                    if engine.isQuerying { Text("\(engine.total) 个正在查询") }
                    else { Text("已查询 \(engine.total) 个") }
                    Text("用时 \(formattedElapsed)")
                } else if engine.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("单号（每行一个，自动过滤中文）")
                } else {
                    let nums = TrackParsing.parseInput(engine.inputText)
                    Text("\(nums.count) 个准备查询")
                }
            }
            .font(.subheadline).foregroundColor(.secondary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                TextEditor(text: $engine.inputText)
                    .font(.system(size: 20))
                    .padding(8)
                    .frame(minHeight: 140)
                    .disabled(engine.isQuerying)
            }

            HStack(spacing: 12) {
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    engine.start()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("查询")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(engine.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white).cornerRadius(10)
                }
                .disabled(engine.isQuerying || engine.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !HarConfig.shared.isConfigured)

                if engine.isQuerying {
                    Button { engine.cancel() } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 12, height: 12)
                            Text("停止")
                        }
                        .font(.headline)
                        .padding(.vertical, 10).padding(.horizontal, 16)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.red).cornerRadius(10)
                    }
                }
            }
        }
        .padding(.horizontal).padding(.top, 8).padding(.bottom, 12)
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: Double(engine.completed), total: Double(max(engine.total, 1))).tint(.blue)
            Text("\(engine.completed) / \(engine.total)").font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal).padding(.bottom, 6)
    }

    private var statsAndTabs: some View {
        VStack(spacing: 8) {
            HStack {
                Text("成功 \(engine.successResults.count)，失败 \(engine.failedResults.count)，重复 \(engine.duplicateResults.count)")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            }.padding(.horizontal)
            Picker("结果", selection: $selectedTab) {
                Text("成功 (\(engine.successResults.count))").tag(ResultTab.success)
                Text("失败 (\(engine.failedResults.count))").tag(ResultTab.failed)
                Text("重复 (\(engine.duplicateResults.count))").tag(ResultTab.duplicate)
            }
            .pickerStyle(.segmented).padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var resultContent: some View {
        let list: [MailResult]
        switch selectedTab {
        case .success: list = engine.successResults
        case .failed: list = engine.failedResults
        case .duplicate: list = engine.duplicateResults
        }
        if list.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "cube").font(.system(size: 50)).foregroundColor(.secondary)
                Text("输入单号后点击查询").foregroundColor(.secondary)
                Spacer()
            }
        } else {
            List {
                ForEach(list) { r in
                    Button { selectedResult = r } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.mailNum).font(.system(size: 16, weight: .medium))
                            if let err = r.error {
                                Text(err).font(.system(size: 14)).foregroundColor(.secondary)
                            } else if !r.traces.isEmpty {
                                Text(r.traces[0].time).font(.caption).foregroundColor(.secondary)
                                Text(r.traces[0].title).font(.subheadline).fontWeight(.medium)
                                if !r.traces[0].desc.isEmpty {
                                    Text(r.traces[0].desc).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(PlainListStyle())
        }
    }

    private var formattedElapsed: String { String(format: "%.1f秒", engine.elapsedSeconds) }
}

struct DetailSheet: View {
    let result: MailResult
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            List {
                Section {
                    Text(result.mailNum).font(.headline).frame(maxWidth: .infinity, alignment: .center)
                    if !result.destCity.isEmpty {
                        Text("寄达\(result.destProvince)\(result.destCity)").font(.subheadline).frame(maxWidth: .infinity, alignment: .center)
                    }
                    if !result.weight.isEmpty || !result.fee.isEmpty {
                        Text("重量\(result.weight)  资费\(result.fee)").font(.subheadline).frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                if !result.traces.isEmpty {
                    Section("全部轨迹（\(result.traces.count)条）") {
                        ForEach(result.traces) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.time).font(.caption).foregroundColor(.blue)
                                Text(item.title).font(.subheadline).fontWeight(.medium)
                                if !item.desc.isEmpty {
                                    Text(item.desc).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("物流详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("返回") { dismiss() }.foregroundColor(.blue)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }.foregroundColor(.blue)
                }
            }
        }
    }
}
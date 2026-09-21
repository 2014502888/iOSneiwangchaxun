import SwiftUI
import UIKit
import UniformTypeIdentifiers


class PickerDelegate: NSObject, UIDocumentPickerDelegate {
    static let shared = PickerDelegate()
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        HarImporter.importHar(from: url)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true)
    }
}

struct TraceItem: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let desc: String
    let province: String
    let city: String
    let orgName: String
    let orgCode: String
}

struct QueryResult: Identifiable {
    let id = UUID()
    let mailNo: String
    var traces: [TraceItem]
    var weight: String
    var fee: String
    var destProvince: String
    var destCity: String
    var error: String?
}

enum TrackParsing {
    static func isValidMailNum(_ digits: String) -> Bool {
        guard digits.count == 13 else { return false }
        guard let first = digits.first else { return false }
        return first == "1" || first == "8" || first == "9"
    }

    static func parseInputDetailed(_ text: String) -> (valid: [String], invalid: Int) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let tokens = normalized
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" || $0 == ";" || $0 == "；" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var valid: [String] = []
        var invalid = 0

        for token in tokens {
            var digits = ""
            var segments: [String] = []
            for ch in token {
                if let ascii = ch.asciiValue, (48...57).contains(ascii) {
                    digits.append(ch)
                } else if !digits.isEmpty {
                    segments.append(digits)
                    digits = ""
                }
            }
            if !digits.isEmpty { segments.append(digits) }

            for seg in segments {
                if seg.count == 13 {
                    if isValidMailNum(seg) {
                        valid.append(seg)
                    } else {
                        invalid += 1
                    }
                } else if seg.count == 14 {
                    invalid += 1
                } else if seg.count > 14 {
                    var found: String? = nil
                    for i in 0...(seg.count - 13) {
                        let start = seg.index(seg.startIndex, offsetBy: i)
                        let end = seg.index(start, offsetBy: 13)
                        let sub = String(seg[start..<end])
                        if let first = sub.first, first == "1" || first == "8" || first == "9" {
                            found = sub
                        }
                    }
                    if let f = found {
                        valid.append(f)
                    } else {
                        invalid += 1
                    }
                } else {
                    invalid += 1
                }
            }
        }
        return (valid, invalid)
    }
}

struct ContentView: View {
    @State private var mailNo = ""
    @State private var results: [QueryResult] = []
    @State private var isLoading = false
    @State private var errorMsg = ""
    @State private var selectedResult: QueryResult?
    @State private var queryStats = ""
    @State private var showSettings = false
    @State private var concurrency = 2
    @State private var isPaused = false

    private var inputInfo: (valid: [String], invalid: Int) {
        TrackParsing.parseInputDetailed(mailNo)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    if mailNo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("单号（每行一个，自动过滤中文）")
                            .foregroundColor(.secondary)
                    } else if results.isEmpty {
                        Text("\(inputInfo.valid.count) 个准备查询")
                            .foregroundColor(.secondary)
                    } else {
                        let success = results.filter { $0.error == nil }.count
                        Text("\(success) 个查询成功")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !queryStats.isEmpty {
                        Text(queryStats)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .font(.subheadline)
                .padding(.horizontal)

                ZStack(alignment: .topLeading) {
                    if mailNo.isEmpty {
                        Text("")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                    }
                    TextEditor(text: $mailNo)
                        .frame(height: 120)
                        .padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator)))
                }
                .padding(.horizontal)
                .padding(.top, 4)

                HStack(spacing: 12) {
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        Task { await doQuery() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "magnifyingglass")
                                Text("查询")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(inputInfo.valid.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(inputInfo.valid.isEmpty || isLoading || !HarConfig.shared.isConfigured)

                    if isLoading {
                        Button {
                            isPaused = true
                        } label: {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal)

                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .foregroundColor(.red)
                        .padding()
                }

                if results.isEmpty && !isLoading {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "cube.box")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("输入单号后点击查询")
                            .foregroundColor(.gray)
                    }
                    Spacer()
                } else if !results.isEmpty {
                    List {
                        ForEach(results) { r in
                            Button {
                                selectedResult = r
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(r.mailNo)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let err = r.error {
                                        Text(err)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    } else if !r.traces.isEmpty {
                                        Text(r.traces[0].time)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(r.traces[0].title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        if !r.traces[0].desc.isEmpty {
                                            Text(r.traces[0].desc)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
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
            .navigationBarTitle("快递查询", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        mailNo = ""
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.blue)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(.blue)
                    }
                }
            }
        }

        .sheet(isPresented: $showSettings) {
            NavigationView {
                List {
                    HStack {
                        Text("并发数")
                        Spacer()
                        Text("\(concurrency)")
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                        Spacer()
                        HStack(spacing: 4) {
                            Button {
                                if concurrency > 1 { concurrency -= 1 }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 18))
                            }
                            Button {
                                if concurrency < 20 { concurrency += 1 }
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 18))
                            }
                        }
                    }
                    HStack {
                        Button {
                            errorMsg = ""
                            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
                            picker.delegate = PickerDelegate.shared
                            picker.allowsMultipleSelection = false
                            UIApplication.shared.windows.first?.rootViewController?.presentedViewController?.present(picker, animated: true)
                        } label: {
                            VStack {
                                Image(systemName: "doc.badge.gearshape")
                                    .foregroundColor(.blue)
                                Text("导入文件")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        Button {
                            showSettings = false
                            exportXLSX()
                        } label: {
                            VStack {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.blue)
                                Text("导出文件")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .navigationTitle("设置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") { showSettings = false }
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .sheet(item: $selectedResult) { r in
            NavigationView {
                List {
                    Section {
                        Text(r.mailNo)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                        if !r.destCity.isEmpty {
                            Text("寄达\(r.destProvince)\(r.destCity)")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        if !r.weight.isEmpty || !r.fee.isEmpty {
                            Text("重量\(r.weight)  资费\(r.fee)")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    if !r.traces.isEmpty {
                        Section("全部轨迹（\(r.traces.count)条）") {
                            ForEach(r.traces) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.time)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Text(item.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    if !item.desc.isEmpty {
                                        Text(item.desc)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
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
                        Button("返回") { selectedResult = nil }
                            .foregroundColor(.blue)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") { selectedResult = nil }
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }

    private func presentDocumentPicker() {
        errorMsg = ""
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = PickerDelegate.shared
        picker.allowsMultipleSelection = false
        UIApplication.shared.windows.first?.rootViewController?.present(picker, animated: true)
    }

    private func exportXLSX() {
        let validResults = results.filter { !$0.traces.isEmpty }
        guard !validResults.isEmpty else {
            errorMsg = "没有可导出的数据"
            return
        }

        var rows: [[String]] = []
        for r in validResults {
            let last = r.traces[0]
            var acceptTrace: TraceItem? = nil
            for t in r.traces {
                if t.title.contains("收寄") { acceptTrace = t; break }
            }
            if acceptTrace == nil && r.traces.count > 1 {
                acceptTrace = r.traces[r.traces.count - 2]
            }
            let row: [String] = [
                r.mailNo,
                last.time,
                last.title,
                r.weight,
                r.fee,
                last.province,
                last.city,
                last.orgName,
                last.orgCode,
                r.destCity,
                r.destProvince,
                acceptTrace?.province ?? "",
                acceptTrace?.city ?? "",
                acceptTrace?.orgName ?? ""
            ]
            rows.append(row)
        }

        let data = XLSXExporter.export(rows: rows)
        let fileName = XLSXExporter.defaultFileName() + ".xlsx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            DispatchQueue.main.async {
                guard let rootVC = UIApplication.shared.windows.first?.rootViewController else { return }
                rootVC.dismiss(animated: false) {
                    let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    activityVC.completionWithItemsHandler = { _, _, _, _ in
                        activityVC.dismiss(animated: true)
                    }
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = rootVC.view
                        popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                    rootVC.present(activityVC, animated: true)
                }
            }
        } catch {
            errorMsg = "导出失败: \(error.localizedDescription)"
        }
    }

    private func doQuery() async {
        isLoading = true
        results = []
        errorMsg = ""
        queryStats = ""
        isPaused = false

        let info = TrackParsing.parseInputDetailed(mailNo)
        guard !info.valid.isEmpty else {
            errorMsg = "请输入有效单号"
            isLoading = false
            return
        }

        let unique = Array(Set(info.valid)).sorted()
        let start = Date()

        await withTaskGroup(of: QueryResult.self) { group in
            var active = 0
            var index = 0
            while index < unique.count || active > 0 {
                while active < concurrency && index < unique.count {
                    let no = unique[index]
                    group.addTask {
                        do {
                            let json = try await NetworkManager.shared.query(mailNo: no)
                            return parseTracesToResult(no, json: json)
                        } catch {
                            do {
                                let json = try await NetworkManager.shared.query(mailNo: no)
                                return parseTracesToResult(no, json: json)
                            } catch {
                                return QueryResult(mailNo: no, traces: [], weight: "", fee: "", destProvince: "", destCity: "", error: "查询失败")
                            }
                        }
                    }
                    active += 1
                    index += 1
                }
                if isPaused { break }
                if let r = await group.next() {
                    results.append(r)
                    active -= 1
                    let elapsed = Date().timeIntervalSince(start)
                    queryStats = "用时\(String(format: "%.1f", elapsed))s"
                }
            }
        }

        isLoading = false
    }

    private func parseTracesToResult(_ mailNo: String, json: [String: Any]) -> QueryResult {
        var list: [[String: Any]]?
        if let data = json["data"] as? [String: Any],
           let l = data["data"] as? [[String: Any]] {
            list = l
        } else if let l = json["data"] as? [[String: Any]] {
            list = l
        }
        guard let l = list, !l.isEmpty else {
            return QueryResult(mailNo: mailNo, traces: [], weight: "", fee: "", destProvince: "", destCity: "", error: "无物流信息")
        }

        var items: [TraceItem] = []
        var weight = ""
        var fee = ""
        for item in l {
            flatten(item, into: &items, weight: &weight, fee: &fee)
        }
        items.sort { $0.time > $1.time }

        var destCity = ""
        for t in items {
            var s = t.desc
            if let range = s.range(of: "发往:") {
                s = String(s[range.upperBound...])
            } else if let range = s.range(of: "发往：") {
                s = String(s[range.upperBound...])
            } else {
                continue
            }
            while s.first == " " || s.first == "　" { s.removeFirst() }
            if let end = s.firstIndex(of: " ") { s = String(s[..<end]) }
            destCity = s
            break
        }
        let destProvince = AreaUtil.shared.getProvinceByCity(destCity)

        return QueryResult(mailNo: mailNo, traces: items, weight: weight, fee: fee, destProvince: destProvince, destCity: destCity, error: nil)
    }

    private func flatten(_ node: [String: Any], into items: inout [TraceItem], weight: inout String, fee: inout String) {
        let time = node["opTime"] as? String ?? ""
        let title = node["opName"] as? String ?? ""
        var desc = ""
        if let org = node["opOrgName"] as? String, !org.isEmpty { desc = org }
        if let opDesc = node["opDesc"] as? String, !opDesc.isEmpty {
            if !desc.isEmpty { desc += " - " }
            desc += opDesc
        }
        if let operatorName = node["operatorName"] as? String, !operatorName.isEmpty {
            if !desc.isEmpty { desc += " - " }
            desc += "操作员: \(operatorName)"
        }
        let province = node["opOrgProvName"] as? String ?? ""
        let city = node["opOrgCity"] as? String ?? ""
        let orgName = node["opOrgName"] as? String ?? ""
        let orgCode = node["opOrgCode"] as? String ?? ""

        if weight.isEmpty, let opDesc = node["opDesc"] as? String,
           let range = opDesc.range(of: "重量:") {
            let s = String(opDesc[range.upperBound...])
            if let match = s.range(of: #"\d+\.?\d*\s*[gGkKmM]+"#, options: .regularExpression) {
                weight = String(s[match])
            }
        }
        if fee.isEmpty, let opDesc = node["opDesc"] as? String,
           let range = opDesc.range(of: "基本资费:") {
            let s = String(opDesc[range.upperBound...])
            if let match = s.range(of: #"\d+\.?\d*\s*元"#, options: .regularExpression) {
                fee = String(s[match])
            }
        }

        if !time.isEmpty || !title.isEmpty {
            items.append(TraceItem(time: time, title: title, desc: desc, province: province, city: city, orgName: orgName, orgCode: orgCode))
        }
        if let children = node["children"] as? [[String: Any]] {
            for child in children { flatten(child, into: &items, weight: &weight, fee: &fee) }
        }
    }
}

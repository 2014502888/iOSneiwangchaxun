import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    var onPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPicked: (URL) -> Void
        init(onPicked: @escaping (URL) -> Void) { self.onPicked = onPicked }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPicked(url)
        }
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
    let weight: String
    let fee: String
}

// MARK: - 输入解析（按 KDApp 逻辑）
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
    @State private var traces: [TraceItem] = []
    @State private var isLoading = false
    @State private var showPicker = false
    @State private var errorMsg = ""
    @State private var showDetail = false
    @State private var infoWeight = ""
    @State private var infoFee = ""
    @State private var infoProvince = ""
    @State private var infoCity = ""

    private var inputInfo: (valid: [String], invalid: Int) {
        TrackParsing.parseInputDetailed(mailNo)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    if mailNo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("单号（每行一个，自动过滤中文）")
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(inputInfo.valid.count) 个准备查询")
                            .foregroundColor(.secondary)
                        if inputInfo.invalid > 0 {
                            Text("（\(inputInfo.invalid) 个非正确单号）")
                                .foregroundColor(.red)
                        }
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

                Button {
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
                .padding(.horizontal)
                .disabled(inputInfo.valid.isEmpty || isLoading || !HarConfig.shared.isConfigured)

                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .foregroundColor(.red)
                        .padding()
                }

                if traces.isEmpty && !isLoading {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "cube.box")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("输入单号后点击查询")
                            .foregroundColor(.gray)
                    }
                    Spacer()
                } else if !traces.isEmpty {
                    ScrollView {
                        Button {
                            showDetail = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mailNo)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(traces[0].time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(traces[0].title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if !traces[0].desc.isEmpty {
                                    Text(traces[0].desc)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("快递查询")
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
                    HStack(spacing: 20) {
                        Button {
                            showPicker = true
                        } label: {
                            Image(systemName: "doc.badge.gearshape")
                                .foregroundColor(.blue)
                        }
                        Button {
                            exportXLSX()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { url in
                HarImporter.importHar(from: url)
            }
        }
        .sheet(isPresented: $showDetail) {
            NavigationView {
                List {
                    Section {
                        Text(mailNo)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text("寄达\(infoProvince)\(infoCity)")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text("重量\(infoWeight)  资费\(infoFee)")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Section("全部轨迹（\(traces.count)条）") {
                        ForEach(traces) { item in
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
                .navigationTitle("物流详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") { showDetail = false }
                    }
                }
            }
        }
    }

    private func exportXLSX() {
        guard !traces.isEmpty else { return }

        let last = traces[0]
        let second = traces.count > 1 ? traces[1] : nil

        // 寄达地：从所有 trace 的 desc 找"发往:"或"发往："
        var destCity = ""
        for t in traces {
            var s = t.desc
            if let range = s.range(of: "发往:") {
                s = String(s[range.upperBound...])
            } else if let range = s.range(of: "发往：") {
                s = String(s[range.upperBound...])
            } else {
                continue
            }
            while s.first == " " || s.first == "　" { s.removeFirst() }
            if let end = s.firstIndex(of: " ") {
                s = String(s[..<end])
            }
            destCity = s
            break
        }

        let row: [String] = [
            mailNo,                          // 1. 邮件单号
            last.time,                       // 2. 最后物流更新时间
            last.title,                      // 3. 物流状态
            infoWeight,                      // 4. 重量
            infoFee,                         // 5. 资费
            last.province,                   // 6. 所在省
            last.city,                       // 7. 所在市
            last.orgName,                    // 8. 所在机构
            last.orgCode,                    // 9. 机构代码
            destCity,                        // 10. 寄达地
            "",                              // 11. 寄达省（AreaUtil 匹配，先留空）
            second?.province ?? "",          // 12. 收寄省份
            second?.city ?? "",              // 13. 收寄城市
            second?.orgName ?? ""            // 14. 收寄机构
        ]

        let data = XLSXExporter.export(rows: [row])
        let fileName = XLSXExporter.defaultFileName() + ".xlsx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            DispatchQueue.main.async {
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = UIApplication.shared.windows.first
                    popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                UIApplication.shared.windows.first?.rootViewController?.present(activityVC, animated: true)
            }
        } catch {
            errorMsg = "导出失败: \(error.localizedDescription)"
        }
    }

    private func doQuery() async {
        isLoading = true
        traces = []
        errorMsg = ""
        infoWeight = ""
        infoFee = ""
        infoProvince = ""
        infoCity = ""

        let info = TrackParsing.parseInputDetailed(mailNo)
        guard !info.valid.isEmpty else {
            errorMsg = "请输入有效单号"
            isLoading = false
            return
        }
        let firstNo = info.valid[0]
        do {
            let json = try await NetworkManager.shared.query(mailNo: firstNo)
            parseTraces(json)
        } catch {
            errorMsg = "查询失败: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func parseTraces(_ json: [String: Any]) {
        var list: [[String: Any]]?

        if let data = json["data"] as? [String: Any],
           let l = data["data"] as? [[String: Any]] {
            list = l
        } else if let l = json["data"] as? [[String: Any]] {
            list = l
        }

        guard let l = list, !l.isEmpty else {
            if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let s = String(data: data, encoding: .utf8) {
                errorMsg = "无物流信息\n\(s)"
            } else {
                errorMsg = "无物流信息"
            }
            return
        }

        var items: [TraceItem] = []
        for item in l {
            flatten(item, depth: 0, into: &items)
            extractInfo(item)
        }
        items.sort { $0.time > $1.time }
        traces = items
    }

    private func extractInfo(_ node: [String: Any]) {
        if let opName = node["opName"] as? String, opName.contains("收寄计费") {
            if let opDesc = node["opDesc"] as? String {
                if infoWeight.isEmpty, let range = opDesc.range(of: "重量:") {
                    var s = String(opDesc[range.upperBound...])
                    if let match = s.range(of: #"\d+\.?\d*\s*[gGkKmM]+"#, options: .regularExpression) {
                        infoWeight = String(s[match])
                    }
                }
                if infoFee.isEmpty, let range = opDesc.range(of: "基本资费:") {
                    var s = String(opDesc[range.upperBound...])
                    if let match = s.range(of: #"\d+\.?\d*\s*元"#, options: .regularExpression) {
                        infoFee = String(s[match])
                    }
                }
            }
            infoWeight = infoWeight.isEmpty ? (node["mailWeight"] as? String ?? "") : infoWeight
            infoFee = infoFee.isEmpty ? (node["fee"] as? String ?? "") : infoFee
        }
        if infoProvince.isEmpty {
            infoProvince = node["opOrgProvName"] as? String ?? ""
        }
        if infoCity.isEmpty {
            infoCity = node["opOrgCity"] as? String ?? ""
        }
        if let children = node["children"] as? [[String: Any]] {
            for child in children { extractInfo(child) }
        }
    }

    private func flatten(_ node: [String: Any], depth: Int, into items: inout [TraceItem]) {
        let time = node["opTime"] as? String ?? ""
        let title = node["opName"] as? String ?? ""
        var desc = ""
        if let org = node["opOrgName"] as? String, !org.isEmpty {
            desc = org
        }
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
        var weight = node["mailWeight"] as? String ?? ""
        var fee = node["fee"] as? String ?? ""

        if let opDesc = node["opDesc"] as? String {
            if weight.isEmpty, let range = opDesc.range(of: "重量:") {
                var s = String(opDesc[range.upperBound...])
                if let end = s.firstIndex(of: " ") {
                    s = String(s[..<end])
                }
                weight = s
            }
            if fee.isEmpty, let range = opDesc.range(of: "基本资费:") {
                var s = String(opDesc[range.upperBound...])
                if let end = s.firstIndex(of: "元") {
                    s = String(s[..<end])
                }
                fee = s + "元"
            }
        }
        if !time.isEmpty || !title.isEmpty {
            items.append(TraceItem(time: time, title: title, desc: desc, province: province, city: city, orgName: orgName, orgCode: orgCode, weight: weight, fee: fee))
        }
        if let children = node["children"] as? [[String: Any]] {
            for child in children {
                flatten(child, depth: depth + 1, into: &items)
            }
        }
    }
}

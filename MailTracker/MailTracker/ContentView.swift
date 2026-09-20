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
}

struct ContentView: View {
    @State private var mailNo = ""
    @State private var traces: [TraceItem] = []
    @State private var isLoading = false
    @State private var showPicker = false
    @State private var errorMsg = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("输入单号", text: $mailNo)
                        .keyboardType(.numberPad)
                }
                Section {
                    Button {
                        Task { await doQuery() }
                    } label: {
                        if isLoading { ProgressView() }
                        else { Text("查询").frame(maxWidth: .infinity) }
                    }
                    .disabled(mailNo.isEmpty || isLoading || !HarConfig.shared.isConfigured)
                }
                Section {
                    Button("导入HAR文件") { showPicker = true }
                }
                if !errorMsg.isEmpty {
                    Section("错误") {
                        Text(errorMsg).foregroundColor(.red)
                    }
                }
                if !traces.isEmpty {
                    Section("物流详情") {
                        ForEach(traces) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
            .navigationTitle("内网邮件查询")
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { url in
                HarImporter.importHar(from: url)
            }
        }
    }

    private func doQuery() async {
        isLoading = true
        traces = []
        errorMsg = ""
        do {
            let json = try await NetworkManager.shared.query(mailNo: mailNo)
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
            let time = item["opTime"] as? String ?? ""
            let title = item["opName"] as? String ?? ""
            var desc = ""
            if let org = item["opOrgName"] as? String, !org.isEmpty {
                desc = org
            }
            if let opDesc = item["opDesc"] as? String, !opDesc.isEmpty {
                if !desc.isEmpty { desc += " - " }
                desc += opDesc
            }
            items.append(TraceItem(time: time, title: title, desc: desc))
        }
        traces = items
    }
}

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

        init(onPicked: @escaping (URL) -> Void) {
            self.onPicked = onPicked
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPicked(url)
        }
    }
}

struct ContentView: View {
    @State private var mailNo = ""
    @State private var result = ""
    @State private var isLoading = false
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("输入单号", text: $mailNo)
                        .keyboardType(.numberPad)
                }

                Section {
                    Button {
                        Task { await doQuery() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("查询")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(mailNo.isEmpty || isLoading || !HarConfig.shared.isConfigured)
                }

                Section {
                    Button("导入HAR文件") {
                        showPicker = true
                    }
                }

                if !result.isEmpty {
                    Section("查询结果") {
                        ForEach(parseResult(result), id: \.0) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.0)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(item.1)
                                    .font(.subheadline)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("内网邮件查询")
            .toolbar {
                if !HarConfig.shared.isConfigured {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("未配置")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { url in
                HarImporter.importHar(from: url)
            }
        }
    }

    private func doQuery() async {
        isLoading = true
        result = ""
        do {
            let json = try await NetworkManager.shared.query(mailNo: mailNo)
            result = pretty(json)
        } catch {
            result = "查询失败: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func pretty(_ obj: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\(obj)"
    }

    private func parseResult(_ jsonString: String) -> [(String, String)] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [("原始", jsonString)]
        }
        var items: [(String, String)] = []
        for (key, value) in json {
            if let arr = value as? [[String: Any]] {
                for (i, item) in arr.enumerated() {
                    for (k, v) in item {
                        items.append(("\(k)", "\(v)"))
                    }
                    if i < arr.count - 1 {
                        items.append(("——", ""))
                    }
                }
            } else if let dict = value as? [String: Any] {
                for (k, v) in dict {
                    items.append(("\(k)", "\(v)"))
                }
            } else {
                items.append((key, "\(value)"))
            }
        }
        return items.isEmpty ? [("结果", jsonString)] : items
    }
}

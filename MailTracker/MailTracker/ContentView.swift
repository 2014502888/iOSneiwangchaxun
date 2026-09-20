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
    @State private var resultDict: [String: Any] = [:]
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

                if !resultDict.isEmpty {
                    Section("查询结果") {
                        let items = flatten(resultDict, prefix: "")
                        ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.0)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(item.1)
                                    .font(.subheadline)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 2)
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
        resultDict = [:]
        do {
            let json = try await NetworkManager.shared.query(mailNo: mailNo)
            resultDict = json
        } catch {
            resultDict = ["错误": error.localizedDescription]
        }
        isLoading = false
    }

    private func flatten(_ obj: Any, prefix: String) -> [(String, String)] {
        var items: [(String, String)] = []
        if let dict = obj as? [String: Any] {
            for (key, value) in dict {
                let label = prefix.isEmpty ? key : "\(prefix).\(key)"
                if let arr = value as? [Any] {
                    for (i, item) in arr.enumerated() {
                        items.append(contentsOf: flatten(item, prefix: "\(label)[\(i)]"))
                    }
                } else if let sub = value as? [String: Any] {
                    items.append(contentsOf: flatten(sub, prefix: label))
                } else {
                    items.append((label, "\(value)"))
                }
            }
        } else {
            items.append((prefix, "\(obj)"))
        }
        return items
    }
}

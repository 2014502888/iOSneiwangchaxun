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
    @ObservedObject var config = HarConfig.shared
    @State private var mailNo = ""
    @State private var resultText = ""
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
                    .disabled(mailNo.isEmpty || isLoading || !config.isConfigured)
                }

                Section {
                    Button("导入HAR文件") {
                        showPicker = true
                    }
                }

                if !resultText.isEmpty {
                    Section("查询结果") {
                        ScrollView {
                            Text(resultText)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(height: 300)
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
        resultText = ""
        do {
            let json = try await NetworkManager.shared.query(mailNo: mailNo)
            if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let s = String(data: data, encoding: .utf8) {
                resultText = s
            } else {
                resultText = "\(json)"
            }
        } catch {
            resultText = "查询失败: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

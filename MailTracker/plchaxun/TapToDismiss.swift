import SwiftUI
import UIKit

// 点击背景收键盘，不影响 TextEditor
struct TapToDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(TapToDismissView())
    }
}

struct TapToDismissView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator: NSObject {
        @objc func tap() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

extension View {
    func tapToDismissKeyboard() -> some View {
        modifier(TapToDismissModifier())
    }
}

import SwiftUI
import UIKit

// MARK: - 边缘滑动返回（SwiftUI 手势版）
// 不往 UIWindow 添加手势识别器（会干扰全 App 按钮点击）。
// 用法：页面 body 上 .edgeSwipeBack { presentationMode.wrappedValue.dismiss() }
// 支持：屏幕左边缘右滑 / 屏幕右边缘左滑（横向为主、纵向位移小于 80pt 才触发）
enum EdgeSwipeBack {
    /// 禁用系统左缘 pop 手势：带导航栏页面（内网/外网）的系统返回手势会吞掉左边缘触摸
    /// 但又不触发（navigationBarBackButtonHidden 下），导致页面自己的手势也收不到。
    static func disableSystemPop() {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first?.windows.first else { return }
            findNav(window.rootViewController)?.interactivePopGestureRecognizer?.isEnabled = false
        }
    }

    private static func findNav(_ vc: UIViewController?) -> UINavigationController? {
        if let n = vc as? UINavigationController { return n }
        if let tab = vc as? UITabBarController {
            for c in tab.viewControllers ?? [] {
                if let n = findNav(c) { return n }
            }
        }
        for c in vc?.children ?? [] {
            if let n = findNav(c) { return n }
        }
        return nil
    }
}

extension View {
    func edgeSwipeBack(_ onSwipe: @escaping () -> Void) -> some View {
        self.highPriorityGesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    let w = UIScreen.main.bounds.width
                    let sx = value.startLocation.x
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dy) < 80 else { return }
                    if sx < 45 && dx > 70 {
                        onSwipe()
                    } else if sx > w - 45 && dx < -70 {
                        onSwipe()
                    }
                }
        )
    }
}

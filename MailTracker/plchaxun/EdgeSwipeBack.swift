import SwiftUI
import UIKit

// MARK: - 边缘滑动返回（SwiftUI 手势版，交互式：跟手拖动、可取消，类似 iOS 系统级返回）
// 用法：页面 body 上 .interactiveEdgeSwipeBack { presentationMode.wrappedValue.dismiss() }
// 支持：屏幕左边缘右滑（横向为主、纵向位移小于 80pt 才触发）
// 交互效果：拖动时当前页跟手右移、左边露出上一页快照；回滑或松手未过半则回弹取消；
//          过半或快速滑动则动画移出并真正返回（与 iOS 系统 pop 手势一致）
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

    /// 截取导航栈「上一页」的全屏快照（交互式返回时左边露出的内容）。
    /// 当前页是 NavigationLink push 的，栈倒数第二个 VC 就是返回目标页。
    static func snapshotOfPreviousPage() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first,
            let nav = findNav(window.rootViewController) else { return nil }
        let vcs = nav.viewControllers
        guard vcs.count >= 2, let prev = vcs[vcs.count - 2].view else { return nil }
        let size = prev.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            prev.drawHierarchy(in: prev.bounds, afterScreenUpdates: false)
        }
    }

    static func findNav(_ vc: UIViewController?) -> UINavigationController? {
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

// MARK: - 交互式边缘返回 modifier

struct InteractiveSwipeBackModifier: ViewModifier {
    let onSwipe: () -> Void
    // 全屏返回已由 FullScreenBack 统一驱动系统原生转场，这里不再自己模拟手势/快照，避免冲突
    func body(content: Content) -> some View { content }
}

// MARK: - 全屏边缘返回（驱动系统原生转场，效果与系统一致：跟手、露真上一页、过半才返回）

final class FullScreenPanGesture: UIPanGestureRecognizer {}

final class FullScreenBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = FullScreenBackDelegate()
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer,
              let nav = FullScreenBack.nav else { return false }
        // 只有导航栈多于一页才允许返回
        guard nav.viewControllers.count > 1 else { return false }
        let t = pan.translation(in: g.view)
        // 只响应向右（返回方向）的横向拖动；纵向滚动不抢
        guard t.x > 2, abs(t.x) > abs(t.y) else { return false }
        return true
    }
}

enum FullScreenBack {
    static weak var nav: UINavigationController?
    static func install() {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first?.windows.first,
                  let nav = EdgeSwipeBack.findNav(window.rootViewController) else { return }
            FullScreenBack.nav = nav
            if nav.view.gestureRecognizers?.contains(where: { $0 is FullScreenPanGesture }) == true { return }
            // KVC 拿到系统边缘返回手势的 target（_UINavigationInteractiveTransition），
            // 全屏手势直接驱动它的私有 handleNavigationTransition:，复用系统原生 pop 动画
            guard let sys = nav.interactivePopGestureRecognizer,
                  let targets = sys.value(forKey: "_targets") as? [NSObject],
                  let target = targets.first?.value(forKey: "_target") else { return }
            let sel = NSSelectorFromString("handleNavigationTransition:")
            let g = FullScreenPanGesture(target: target, action: sel)
            g.delegate = FullScreenBackDelegate.shared
            nav.view.addGestureRecognizer(g)
            sys.isEnabled = false   // 全屏手势接管，避免与系统边缘手势重复
        }
    }
}

extension View {
    func interactiveEdgeSwipeBack(_ onSwipe: @escaping () -> Void) -> some View {
        modifier(InteractiveSwipeBackModifier(onSwipe: onSwipe))
    }
}

// MARK: - 旧版：一次性判断触发（保留备用）

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

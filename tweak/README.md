# 全屏返回手势 dylib 插件（FullScreenBackTweak）

把 iOS 原生「左边缘右滑返回」扩展为**整屏右滑即可返回**，直接驱动系统原生 pop 转场：跟手、左边露出真上一页、过半才返回、不过半回弹，不闪。

## 原理
通过 KVC 拿到导航控制器私有的 `_UINavigationInteractiveTransition`，
给 nav.view 加一个全屏 `UIPanGestureRecognizer`，target 指向系统私有方法
`handleNavigationTransition:`，从而复用系统原生交互动画。

## 文件
- `FullScreenBackTweak.x` — Logos 源码（自包含，含手势类/delegate/安装逻辑）
- `Makefile` — Theos 编译配置
- `FullScreenBackTweak.plist` — 注入过滤（默认注入所有 Bundle）

## 编译（需要 Mac + Theos 环境）
```bash
cd tweak
make package
```
产物在 `packages/` 下的 `.deb`；其中 `FullScreenBackTweak.dylib` 可直接用
注入工具（如 TrollSpeed / ElleKit / Substitute / 巨魔+Sileo）加载到任意 App。

## 直接拿 dylib
`make` 后在 `._/FullScreenBackTweak.dylib` 即编译产物，无需打包 deb 也可直接注入。

## 调注入目标
编辑 `FullScreenBackTweak.plist`，把 `"Bundles": ["*"]` 改成指定 App 的
Bundle ID（如 `["com.tencent.xin"]`），只对该 App 生效。

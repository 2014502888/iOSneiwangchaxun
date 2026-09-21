# KDApp (iOS 版)

邮件/EMS 轨迹批量查询工具 —— iPhone/iPad 版本。

基于原 macOS 版反编译还原后移植为 iOS，保持原有功能不变，新增：**成功界面多选单号并统一复制（每行一个，换行分隔）**。

## 功能

- 批量输入单号（每行/逗号/空格分隔），一键查询
- 实时进度、耗时统计
- 结果分类：Success / Failed / Duplicate / All
- 单号轨迹详情页
- 导出 XLSX（iOS 分享面板保存/发送）
- **🆕 成功界面多选复制**：工具栏点勾选图标进入多选，选好后点 Copy 一键复制所选单号

## 系统要求

- iOS 16.0 或以上（iPhone / iPad）
- 因为用了 SwiftUI NavigationStack，最低 iOS 16

## 编译方式（GitHub Actions 云端编译，推荐）

工程已带 `.github/workflows/build.yml`，苹果官方云 Mac 自动编译出 IPA：

1. 把本目录所有内容上传到 GitHub 仓库（参考下方步骤）
2. 在仓库 Actions 页面创建 workflow，粘贴 `.github/workflows/build.yml` 的内容
3. 等 3-5 分钟编译完成
4. 从 Actions 页面下载 `KDApp-iOS` artifact，解压得到 `KDApp.ipa`

## 安装到 iPhone

编译出的 IPA 是未签名的，需要用侧载工具安装：

### 方式 A：Sideloadly（推荐，Windows/Mac 都支持，免费）

1. 电脑下载 Sideloadly：https://sideloadly.io
2. 手机用数据线连电脑，信任电脑
3. 打开 Sideloadly，把 `KDApp.ipa` 拖进去
4. 输入你的 Apple ID（免费账号即可，7 天有效期）
5. 点 Start，等安装完成
6. 手机上：设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID 证书
7. 打开 KDApp

### 方式 B：AltStore（免费，需要电脑同 Wi-Fi）

参考 https://altstore.io

### 方式 C：TrollStore（永久签名，仅支持特定 iOS 版本）

如果你的手机是 iOS 14.0-16.6.1 且支持 TrollStore，可以永久安装，不用每 7 天重签。

## 文件结构

```
KDApp-iOS/
├── KDApp.xcodeproj/        # Xcode 工程
├── .github/workflows/build.yml  # GitHub 自动编译
└── KDApp/
    ├── KDApp.swift          # App 入口
    ├── ContentView.swift    # 主界面（含多选复制）
    ├── Models.swift         # 数据模型
    ├── TrackParsing.swift   # 输入/日期/轨迹解析
    ├── TrackAPI.swift       # 接口层
    ├── QueryEngine.swift    # 查询引擎
    ├── TraceDetailView.swift# 轨迹详情
    ├── XLSXExporter.swift   # XLSX 导出
    └── Info.plist           # iOS 配置（已内置 ATS 例外）
```

## 接口说明

接口地址：`http://211.156.193.140:8000/cotrackapi/api/track/mail/`
参数：`{"mailNo":"单号","type":"ems_track_cn_3.0"}`（POST + JSON）

Info.plist 已内置 `NSAppTransportSecurity` → `NSAllowsArbitraryLoads=true`，http 接口可直连。

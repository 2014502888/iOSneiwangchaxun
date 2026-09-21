# 内网邮件查询 iOS 版

## 功能
- 导入 HAR 文件自动提取 sessionId、UA
- 自动识别 iOS / Android 抓包，切换对应请求头
- 查询邮件轨迹

## 使用
1. 用文件管理器打开 .har 文件，或在 App 内点"导入HAR文件"
2. 弹"导入成功"后自动刷新
3. 输入单号查询

## 推送 GitHub 编译
1. 新建 GitHub 仓库
2. 把 `ios/` 目录内容推上去
3. Actions 会自动编译，下载 `.xcarchive`
4. 用 Sideloadly / AltStore 安装到手机

## 注意
- 需要 iOS 15+
- 内网 HTTP 已允许（NSAllowsArbitraryLoads）
- 未签名 IPA 需要自签或用 AltStore 签名安装

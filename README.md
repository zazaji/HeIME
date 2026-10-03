# 和码输入法（macOS 端）

基于 Swift 的 macOS 拼音输入法：拼音组词引擎、候选窗口、用户词库、标点符号映射、输入统计与偏好设置。

## 目录结构

| 路径 | 说明 |
|---|---|
| `HeInput/` | 输入法主工程源码（Swift）：组词引擎、候选窗口、用户词库、统计、偏好设置等 |
| `HeInput/HeMa.db` | 内置词库（SQLite：汉字 / 词组 / 拼音 / 英文单词 / 特殊字符） |
| `HeInput.xcodeproj` | Xcode 工程文件 |

## 构建

用 Xcode 打开 `HeInput.xcodeproj`，选择 HeInput scheme 即可构建运行。

正式安装包（签名 + 公证）的打包脚本与凭据不随本仓库分发。

## 数据统计与隐私

输入法会采集**匿名使用统计**并上传到作者自建的 Cloudflare Worker 服务：

- 采集内容：随机设备 ID（UUID）、日期（上海时区）、当日上屏字数
- **不采集**：按键内容、候选词、词库内容、剪贴板等任何输入数据
- 用途：仅用于统计活跃度与使用量

上报端点不写入源码（避免泄漏），在本机通过 App Group UserDefaults 配置一次即可：

```bash
defaults write group.hezi.inputmethod HeInput_ReportEndpoint "https://your-server.example.com/api/report"
```

未配置该键时：本地计数照常累计，网络上报自动停用。

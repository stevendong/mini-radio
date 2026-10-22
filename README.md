# Mini Radio

原生 macOS / iOS 小收音机 · SwiftUI + AVFoundation · macOS 13+ / iOS 16+

菜单栏控制、随机换台、电台搜索、收藏与最近收听、手动直播地址、音量和睡眠定时。

```sh
swift test --jobs 2
bash scripts/build-macos.sh
bash scripts/build-ios.sh device
```

构建脚本需在 Mac 上运行，产出 `artifacts/MiniRadio-0.1.0-universal.zip`，包含 Apple Silicon / Intel 通用应用。当前使用 ad-hoc 签名，尚未公证。

电台目录：[Radio Browser](https://www.radio-browser.info/) · 体验灵感：[RoamDial](https://roamdial.com/about.html)

iOS 专用界面位于 `App/iOS`，Xcode 工程为 `iOS/MiniRadio.xcodeproj`，方案为 `MiniRadio-iOS`。首次构建可先运行上述 iOS 脚本生成图标和无签名 IPA。真机安装前需在 Xcode 选择自己的签名团队，或自行签名 IPA；仓库不包含证书和描述文件。iOS 版支持后台音频、系统媒体控制、系统音量和 AirPlay 输出。

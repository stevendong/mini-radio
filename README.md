# Mini Radio

原生 macOS 小收音机 · SwiftUI + AVFoundation · macOS 13+

菜单栏控制、随机换台、电台搜索、收藏与最近收听、手动直播地址、音量和睡眠定时。

```sh
swift test --jobs 2
bash scripts/build-macos.sh
```

构建脚本需在 Mac 上运行，产出 `artifacts/MiniRadio-0.1.0-universal.zip`，包含 Apple Silicon / Intel 通用应用。当前使用 ad-hoc 签名，尚未公证。

电台目录：[Radio Browser](https://www.radio-browser.info/) · 体验灵感：[RoamDial](https://roamdial.com/about.html)

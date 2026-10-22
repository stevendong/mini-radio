# Mini Radio

原生 macOS / iOS 小收音机 · SwiftUI + AVFoundation · macOS 13+ / iOS 16+

菜单栏控制、随机换台、电台搜索、收藏与最近收听、手动直播地址、音量和睡眠定时。

macOS 顶部菜单栏显示当前电台名称；点击后可查看电台信息、播放状态和音质，直接播放/暂停、停止、随机换台、收藏、调节音量或静音、设置睡眠定时，并从收藏和最近收听快速选台。播放器窗口关闭后仍可通过菜单栏控制收听。

```sh
swift test --jobs 2
bash scripts/build-macos.sh
bash scripts/build-ios.sh device
```

构建脚本需在 Mac 上运行，产出 `artifacts/MiniRadio-0.2.1-universal.zip`，包含 Apple Silicon / Intel 通用应用。当前使用 ad-hoc 签名，尚未公证。

电台目录：[Radio Browser](https://www.radio-browser.info/) · 体验灵感：[RoamDial](https://roamdial.com/about.html)

iOS 专用界面位于 `App/iOS`，Xcode 工程为 `iOS/MiniRadio.xcodeproj`，方案为 `MiniRadio-iOS`。首次构建可先运行上述 iOS 脚本生成图标和无签名 IPA。真机安装前需在 Xcode 选择自己的签名团队，或自行签名 IPA；仓库不包含证书和描述文件。iOS 版支持后台音频、系统媒体控制、系统音量和 AirPlay 输出。

## CarPlay

iOS 0.3.0 接入 CarPlay 音频界面，提供“收藏、最近收听、发现”三个分类。点击电台即可播放并进入系统正在播放页面，可使用播放/暂停、下一站、随机换台、收藏和停止按钮；发现页支持刷新目录。车机和手机共用播放器、收藏与历史，不会产生两份同时播放的音频。音量使用车机和方向盘的系统控制。

车机收藏与最近收听不受手机当前列表筛选影响；发现页沿用手机当前载入的目录，可使用本机目录缓存。手机收藏变更、成功收听记录和同步结果会更新车机列表。CarPlay 单独启动时也会初始化播放器和本地数据，手机界面无需先打开。断开车机后会释放车载界面；音频路由变化继续由现有播放器处理。

真实车机显示需要 Apple 批准的 `com.apple.developer.carplay-audio` 权限，以及包含该权限的开发者签名和描述文件。[Apple 权限申请说明](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements)。仓库提供 `iOS/MiniRadio-CarPlay.entitlements`；普通个人签名不具备此权限，普通真机安装包不会出现在 CarPlay 主屏幕上。当前真车显示、锁屏启动、方向盘控制及无线 CarPlay 尚未验收。

普通手机包继续使用原来的构建命令；CarPlay 无签名包和模拟器构建分别使用：

```sh
bash scripts/build-ios.sh carplay
bash scripts/build-ios.sh simulator
```

CarPlay 无签名包为 `artifacts/MiniRadio-iOS-0.3.0-CarPlay-unsigned.ipa`，必须使用获批权限的签名后才能安装使用；生成 IPA 不代表已获得 CarPlay 权限。使用已获批团队直接构建签名版时，在 Xcode 配置对应描述文件，并设置 `CARPLAY_ENTITLEMENTS=MiniRadio-CarPlay.entitlements`，或通过命令行：

```sh
xcodebuild -project iOS/MiniRadio.xcodeproj -scheme MiniRadio-iOS \
  -configuration Release -destination 'generic/platform=iOS' \
  CARPLAY_ENTITLEMENTS=MiniRadio-CarPlay.entitlements \
  DEVELOPMENT_TEAM=YOUR_AUTHORIZED_TEAM_ID -allowProvisioningUpdates build
```

模拟器构建自动带 CarPlay 音频 entitlement。在 Simulator 中选择 I/O → External Displays → CarPlay 后，从车载主屏幕打开 Mini Radio。模拟器验证使用 `--ui-testing` 合成电台和本地音频服务，不读取个人收藏或请求站源图片。模拟器不能替代实际车机验证，参见 [Apple 模拟器说明](https://developer.apple.com/documentation/carplay/using-the-carplay-simulator)。

本轮已验证模拟器主屏幕图标和电台列表显示，以及车载选台触发真实 AVPlayer 播放本地测试音频、手机共享电台状态、手机暂停和停止操作。普通真机版与 CarPlay 无签名版构建通过；真实车机专属播放按钮、锁屏冷启动、方向盘按键和无线连接待取得授权签名后验证。

## 收藏与收听同步

macOS 在播放器的更多菜单或菜单栏面板的更多菜单中打开“收藏与收听同步”；iOS 在首页右上角更多菜单中打开。可在 [radio.myaichatbox.com](https://radio.myaichatbox.com) 生成随机同步密钥，再在各台设备填写相同服务地址和密钥，点击“保存并启用同步”。默认服务地址已填入，也可以修改。密钥保存在系统钥匙串，不写入源码、普通偏好文件或请求地址；持有者可访问并删除空间，请私下保存，丢失后无法找回。

同步默认关闭。开启后，收藏变更会在约一秒后同步；应用前台使用期间每分钟同步，回到应用时也会同步，也可点击“立即同步”。macOS 应用仍在菜单栏运行时继续检查更新。网络失败先保留本机修改，后续自动重试；停用同步保留本机和服务端已有数据。

同步范围为收藏、取消收藏记录、最近 50 个收听电台及其时间、最后收听电台。合并不会切换正在播放的电台，也不共享音量、睡眠定时或窗口偏好。收听记录在成功开始播放后产生；旧版本本地数据自动迁移，历史时间未知的旧记录优先级低于新修改。取消收藏会保留删除记录，避免离线设备把旧收藏恢复回来。两端设备的系统时间应保持准确。

同步服务位于 `server/`，使用 Node.js 26+ 内置 HTTP/SQLite，无第三方运行时依赖。通过 HTTPS 传输，服务端 AES-GCM 加密存储数据、只保存同步密钥摘要；服务端持有存储密钥，具备解密能力。网页支持撤销密钥和删除云端数据；加密备份最多保留 7 天。错误时保留本机收藏与播放。

服务测试：`node --test server/sync.test.mjs`。启动前设置 `SYNC_DATABASE` 和 `SYNC_MASTER_KEY_FILE`（32 字节随机二进制存储密钥文件），然后运行 `node server/index.mjs`，默认监听回环地址。生产配置、主密钥、数据库与备份保持私有，不提交到仓库。备份入口为 `node server/backup.mjs`，另需设置 `SYNC_BACKUP_DIRECTORY`。更换或遗失主密钥会导致已有数据库无法解密。

## 同步服务接口约定

客户端向配置的服务地址追加 `/v1/library/sync`，发送 `POST`，请求头为 `Authorization: Bearer <同步密钥>`、`Content-Type: application/json`，超时 30 秒。请求和 HTTP 200 响应使用相同的 JSON 格式：

```json
{
  "format": "mini-radio-library",
  "version": 1,
  "state": {
    "favorites": {},
    "history": {}
  }
}
```

`favorites` 以电台 `stationuuid` 为键，每项为 `{ "station": <电台对象>, "modifiedAt": <时间数值>, "removed": false, "revision": "<变更标识>" }`；取消收藏时 `removed` 为 `true`，仍保留该项。`history` 同样以 `stationuuid` 为键，每项为 `{ "station": <电台对象>, "listenedAt": <时间数值>, "revision": "<变更标识>" }`。电台对象使用 `Station` 的 Codable 字段，包括 `stationuuid`、`name`、`url`、`url_resolved`、`countrycode`、`state`、`language`、`tags`、`codec`、`bitrate`。

时间数值使用 Swift Codable Date 的默认表示，即从 2001-01-01 00:00:00 UTC 起经过的秒数，允许小数和负数；换算 Unix 秒数时加 `978307200`。服务应保留双精度数值和客户端 `revision`，不要重新生成时间或变更标识。

服务端必须按密钥隔离数据，并在同一次原子操作中完成读取、合并、持久化后再返回合并结果。收藏按 `modifiedAt` 取较新变更；同一时间先保留删除，删除状态相同再取字典序较大的 `revision`。收听记录按 `listenedAt`、再按 `revision` 取较新项，按时间倒序、电台 ID 升序保留前 50 项。收藏删除记录不可随意清理。返回结果必须包含客户端提交的所有未被更新变更取代的收藏项，包括删除记录。客户端会拒绝未完整合并的成功响应。

请求和响应上限为 8 MB；鉴权失败返回 401/403，尚未部署返回 404，内容过大返回 413，限流返回 429，其他服务错误返回 5xx。响应内容和密钥不会显示在客户端错误信息中。接口应直接响应，不依赖重定向。

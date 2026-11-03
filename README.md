# Mini Radio

原生 macOS / iOS / Android 小收音机 · macOS 13+ / iOS 16+ / Android 8.0+

菜单栏控制、随机换台、电台搜索、收藏与最近收听、手动直播地址、音量和睡眠定时。

macOS 顶部菜单栏显示当前电台名称；点击后可查看电台信息、播放状态和音质，直接播放/暂停、停止、随机换台、收藏、调节音量或静音、设置睡眠定时，并从收藏和最近收听快速选台。播放器窗口关闭后仍可通过菜单栏控制收听。

设备接电（含充满仍接电）且连接 Wi-Fi 时，正在播放的电台会自动准备一个随机下一站，切台时优先复用已缓冲的播放器。断电、离开 Wi-Fi、暂停或停止后释放备用连接；蜂窝、热点和低数据模式下不预加载。预加载会额外使用一路音频流量，不计入最近收听。

```sh
swift test --jobs 2
bash scripts/build-macos.sh
bash scripts/build-ios.sh device
```

构建脚本需在 Mac 上运行，产出 `artifacts/MiniRadio-0.2.2-universal.zip`，包含 Apple Silicon / Intel 通用应用。当前使用 ad-hoc 签名，尚未公证。

电台目录：[Radio Browser](https://www.radio-browser.info/) · 体验灵感：[RoamDial](https://roamdial.com/about.html)

iOS 专用界面位于 `App/iOS`，Xcode 工程为 `iOS/MiniRadio.xcodeproj`，方案为 `MiniRadio-iOS`。首次构建可先运行上述 iOS 脚本生成图标和无签名 IPA。真机安装前需在 Xcode 选择自己的签名团队，或自行签名 IPA；仓库不包含证书和描述文件。iOS 版支持后台音频、系统媒体控制、系统音量和 AirPlay 输出。

## Android 车机

Android 0.4.0 位于 `android/`，使用 Java 和 Android 原生 SDK，无第三方运行时依赖。界面适配横屏、分屏窗口和低密度车机屏幕；支持发现、地区筛选、搜索、收藏、最近 50 个收听电台、手动直播地址、随机换台和睡眠定时。目录不可达时可使用本机缓存和预置电台；直播是否可播放取决于电台与当前网络。

播放器通过前台服务保持后台播放，使用 MediaSession 提供系统播放/暂停、停止、上一站、下一站和收藏操作，并通过 MediaBrowserService 提供收藏、最近、发现三个目录。音量使用车机或方向盘的系统控制。导航提示可降低播放音量，临时音频打断结束后恢复；其他音源永久接管、用户暂停或断开音频输出时不自动抢回播放。支持 Android 原生解码器可播放的 MP3、AAC 和 HLS 音源。

车机和方向盘的“上一曲 / 下一曲”可切换电台，应用前台和后台均通过同一播放器处理；前台页面也接收车机发送到窗口的媒体按键。每次按键只切换一站，松开和长按重复事件不会重复切换。换台跟随当前标签页和搜索结果：收藏、最近按各自可见列表循环切换；发现页的下一站执行“随心漫游”，从当前发现结果随机选台，上一站按发现列表顺序切换。当前电台不在顺序列表时，下一站从首站开始，上一站从末站开始；空列表不会切到其他标签页的电台。最近页保持本轮浏览顺序，重新进入时按最新收听时间更新。回到地图后沿用最后选择的标签页与列表筛选，重启应用也会恢复选择。系统播放卡片提供上一站、播放/暂停、下一站和停止。

构建需要 JDK 17+、Android SDK Platform 35 和 Build Tools 36.0.0。设置 `JAVA_HOME`、`ANDROID_SDK_ROOT`（也支持 `ANDROID_HOME`）后运行：

```sh
bash scripts/build-android.sh
ANDROID_SERIAL=YOUR_DEVICE_SERIAL bash scripts/build-android.sh install
ANDROID_SERIAL=YOUR_DEVICE_SERIAL bash scripts/test-android.sh
```

产物为 `artifacts/android/MiniRadio-Android-0.4.0.apk`。测试脚本在指定设备运行独立偏好文件中的电台校验、收藏与历史持久化、同步合并、Keystore 加密和媒体目录检查，不修改个人收藏。当前面向 Android 9 车机兼容使用 target SDK 28，最低 API 26；此配置用于车机侧载，不用于应用商店上架。SDK 路径默认使用 macOS 常见安装位置，可通过环境变量修改；平台和构建工具版本分别可通过 `ANDROID_PLATFORM`、`ANDROID_BUILD_TOOLS_VERSION` 覆盖。

脚本首次构建会在仓库外创建本机开发签名，后续覆盖安装保留数据；自有签名可使用 `MINI_RADIO_KEYSTORE`、`MINI_RADIO_KEY_ALIAS`、`MINI_RADIO_STORE_PASSWORD` 和 `MINI_RADIO_KEY_PASSWORD` 配置。签名文件、配置和 APK 均不提交到仓库。

在“更多 → 收藏与收听同步”填写 HTTPS 服务地址与同步密钥。密钥使用 Android Keystore 的 AES-GCM 加密后保存在应用私有偏好中。启用后启动同步、每分钟检查更新，收藏和成功收听变更在约一秒后同步；失败保留本机数据并重试。合并协议与 macOS/iOS 相同，下载的数据不会切换当前播放。停用同步保留已有数据。

普通构建不包含同步配置。为私有设备预置配置时，可将包含 `server` 和 `key` 字段的 JSON 文件保存在仓库外，通过 `MINI_RADIO_SYNC_CONFIG` 指定该文件再执行构建或安装；应用首次读取该配置后自动开启同步，相同配置不覆盖用户后续停用选择。此 APK 内含同步密钥，只用于私有安装，不应公开分发；公开源码和构建不包含该文件或密钥。

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

macOS 在播放器的更多菜单或菜单栏面板的更多菜单中打开“收藏与收听同步”；iOS 在首页右上角更多菜单中打开。可使用服务维护者发放的一次性邀请码，在 [radio.myaichatbox.com](https://radio.myaichatbox.com) 生成随机同步密钥，再在各台设备填写相同服务地址和密钥，点击“保存并启用同步”。已有同步密钥继续可用，无需重新生成。默认服务地址已填入，也可以修改。密钥保存在系统钥匙串，不写入源码、普通偏好文件或请求地址；持有者可访问并删除空间，请私下保存，丢失后无法找回。

同步默认关闭。开启后，收藏变更会在约一秒后同步；应用前台使用期间每分钟同步，回到应用时也会同步，也可点击“立即同步”。macOS 应用仍在菜单栏运行时继续检查更新。网络失败先保留本机修改，后续自动重试；停用同步保留本机和服务端已有数据。

同步范围为收藏、取消收藏记录、最近 50 个收听电台及其时间、最后收听电台。合并不会切换正在播放的电台，也不共享音量、睡眠定时或窗口偏好。收听记录在成功开始播放后产生；旧版本本地数据自动迁移，历史时间未知的旧记录优先级低于新修改。取消收藏会保留删除记录，避免离线设备把旧收藏恢复回来。两端设备的系统时间应保持准确。

同步服务位于 `server/`，使用 Node.js 26+ 内置 HTTP/SQLite，无第三方运行时依赖。通过 HTTPS 传输，服务端 AES-GCM 加密存储数据、只保存同步密钥摘要；服务端持有存储密钥，具备解密能力。网页支持撤销密钥和删除云端数据；加密备份最多保留 7 天。错误时保留本机收藏与播放。

服务测试：`node --test server/sync.test.mjs`。启动前设置 `SYNC_DATABASE` 和 `SYNC_MASTER_KEY_FILE`（32 字节随机二进制存储密钥文件），然后运行 `node server/index.mjs`，默认监听回环地址。生产配置、主密钥、数据库与备份保持私有，不提交到仓库。备份入口为 `node server/backup.mjs`，另需设置 `SYNC_BACKUP_DIRECTORY`。更换或遗失主密钥会导致已有数据库无法解密。

维护者可在本地加载同一私有配置后运行 `node server/admin.mjs invite --count 1 --days 7 --out invitations.json`，将一次性邀请码写入新建的私有文件，妥善发送给使用者；命令不会打印凭据。`node server/admin.mjs stats` 仅返回空间数量和匿名安全事件计数。反代时还必须显式配置 `SYNC_TRUSTED_PROXIES`，应用仅信任这些来源的转发地址。邀请码、管理输出及配置文件不得提交到仓库。

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

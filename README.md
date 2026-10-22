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

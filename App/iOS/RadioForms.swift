import SwiftUI

struct AddRadioView: View {
    @ObservedObject var model: RadioModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var invalid = false
    var body: some View {
        NavigationStack {
            Form {
                Section("电台信息") {
                    TextField("电台名称（选填）", text: $name).accessibilityIdentifier("manual-name")
                    TextField("https://… 直播地址", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("manual-url")
                }
                Section {
                    Text("请输入直接 MP3、AAC 或 HLS 直播地址，普通网页无法播放。HTTP 地址使用未加密连接。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if invalid { Text("请输入有效的 HTTP 或 HTTPS 直播地址。").foregroundStyle(.red).accessibilityIdentifier("manual-error") }
                }
            }.navigationTitle("添加电台").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("收藏并播放") {
                            if model.addManual(name: name, address: address) { dismiss() } else { invalid = true }
                        }.accessibilityIdentifier("manual-save")
                    }
                }
        }
    }
}

struct RadioFiltersView: View {
    @ObservedObject var model: RadioModel
    @Environment(\.dismiss) private var dismiss
    @State private var country = ""
    @State private var language = ""
    @State private var tag = ""
    var body: some View {
        NavigationStack {
            Form {
                Picker("国家", selection: $country) {
                    Text("所有国家").tag("")
                    Text("中国").tag("CN"); Text("美国").tag("US"); Text("英国").tag("GB")
                    Text("日本").tag("JP"); Text("法国").tag("FR"); Text("德国").tag("DE")
                    Text("意大利").tag("IT"); Text("西班牙").tag("ES"); Text("加拿大").tag("CA")
                    Text("澳大利亚").tag("AU"); Text("巴西").tag("BR")
                }
                Picker("语言", selection: $language) {
                    Text("所有语言").tag(""); Text("中文").tag("chinese"); Text("英语").tag("english")
                    Text("日语").tag("japanese"); Text("法语").tag("french"); Text("德语").tag("german")
                }
                Picker("流派", selection: $tag) {
                    Text("所有流派").tag(""); Text("爵士").tag("jazz"); Text("古典").tag("classical")
                    Text("流行").tag("pop"); Text("氛围").tag("ambient"); Text("摇滚").tag("rock"); Text("新闻").tag("news")
                }
                Button("重置筛选") { country = ""; language = ""; tag = "" }
            }.navigationTitle("筛选电台").navigationBarTitleDisplayMode(.inline)
                .onAppear { country = model.query.countrycode; language = model.query.language; tag = model.query.tag }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("应用") {
                            model.query.countrycode = country; model.query.language = language; model.query.tag = tag
                            model.search(); dismiss()
                        }
                    }
                }
        }
    }
}

struct IOSPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("只为收听") {
                    Text("收藏、最近收听和偏好默认保存在本机。可选用服务地址和同步密钥合并收藏与收听记录。不申请麦克风或定位权限，不接入广告或行为分析 SDK。")
                    Text("开启同步后，收藏、取消收藏记录、电台地址、最近 50 个收听电台及时间会发送到你设置的服务。密钥保存在系统钥匙串，停用同步保留本机和服务端已有数据。未开启同步时不会上传这些数据。")
                    Text("如果你开启了系统备份，本地应用数据也可能随设备备份迁移。")
                    Text("默认同步服务为 radio.myaichatbox.com，通过 HTTPS 传输、服务端加密存储，服务端持有解密密钥。网页可撤销同步密钥和删除云端数据，加密备份最多保留 7 天。")
                }
                Section("网络连接") {
                    Text("电台目录与搜索请求发送给 Radio Browser。主动选台按目录服务约定提交电台标识用于点击计数。")
                    Text("直播音频直接来自各电台服务器，连接的服务能看到你的 IP 地址。部分电台使用未加密 HTTP，音频中也可能含电台自身的广告。")
                    Text("目录健康标记不代表你当前网络一定可播。收藏与缓存可离线查看，直播音频仍需要网络。")
                }
                Section("项目与来源") {
                    Link("开源代码", destination: URL(string: "https://github.com/stevendong/mini-radio")!)
                    Link("Radio Browser", destination: URL(string: "https://www.radio-browser.info/")!)
                    Link("体验灵感：RoamDial", destination: URL(string: "https://roamdial.com/about.html")!)
                    Text("Mini Radio · iOS 0.3.0").foregroundStyle(.secondary)
                }
            }.navigationTitle("数据来源与隐私").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

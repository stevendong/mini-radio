#if os(macOS) || os(iOS)
import SwiftUI

struct LibrarySyncView: View {
    @ObservedObject var sync: LibrarySyncController
    @State private var server = ""
    @State private var key = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("HTTPS 服务地址", text: $server)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("sync-server")
                SecureField(sync.hasSavedKey ? "密钥（留空保留已保存密钥）" : "同步密钥", text: $key)
                    .accessibilityIdentifier("sync-key")
                Text("在其他设备填写相同的服务地址和密钥，即可合并收藏与最近收听。更换服务地址时需重新输入密钥。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("保存并启用同步") {
                    do {
                        try sync.configure(server: server, key: key)
                        key = ""
                        server = sync.serverAddress
                        errorMessage = nil
                    } catch { errorMessage = error.localizedDescription }
                }.accessibilityIdentifier("sync-save")
                if sync.enabled {
                    Button("停用同步") { sync.disable() }
                        .accessibilityIdentifier("sync-disable")
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            } header: { Text("同步服务") }

            Section {
                HStack {
                    if sync.isSyncing { ProgressView().controlSize(.small) }
                    Text(sync.message)
                        .foregroundStyle(sync.hasError ? Color.orange : Color.secondary)
                }.accessibilityIdentifier("sync-status")
                if let date = sync.lastSyncedAt {
                    LabeledContent("最近成功同步", value: date.formatted(date: .abbreviated, time: .standard))
                }
                Button("立即同步") { sync.synchronize() }
                    .disabled(!sync.enabled || sync.isSyncing)
                    .accessibilityIdentifier("sync-now")
            } header: { Text("同步状态") }

            Section {
                Text("开启后，收藏、取消收藏记录、电台地址、最近 50 个收听电台及其时间会发送到你配置的服务。密钥仅保存在系统钥匙串中。")
                Text("修改会自动同步；前台使用期间每分钟检查更新，回到应用时也会同步。离线时先保存在本机，服务恢复后自动重试。")
                Text("同步不会中断正在播放的电台，也不会远程控制另一台设备的播放、音量或睡眠定时。停用同步保留本机和服务端已有数据。")
            } header: { Text("同步范围与隐私") }
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { server = sync.serverAddress }
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #else
        .frame(width: 480, height: 580)
        #endif
    }
}
#endif

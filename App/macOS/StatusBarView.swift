#if os(macOS)
import SwiftUI
import AppKit
import RadioCore

struct StatusBarLabel: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: playback.isActive ? "antenna.radiowaves.left.and.right" : "radio")
            Text(title)
        }
        .help("\(playback.station?.name ?? "Mini Radio") · \(playback.status.label)")
        .accessibilityLabel("Mini Radio，\(playback.station?.name ?? "未选择电台")，\(playback.status.label)")
    }

    private var title: String {
        guard let name = playback.station?.name else { return "Mini Radio" }
        return name.count > 14 ? String(name.prefix(14)) + "…" : name
    }
}

struct StatusBarPanel: View {
    @ObservedObject var model: RadioModel
    @ObservedObject var playback: PlaybackController
    @Environment(\.openWindow) private var openWindow
    @State private var volumeBeforeMuting = 0.65

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("MINI RADIO", systemImage: "radio")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2).foregroundStyle(.secondary)
                Spacer()
                Button { model.pinned.toggle() } label: {
                    Image(systemName: model.pinned ? "pin.fill" : "pin")
                }
                .help(model.pinned ? "取消播放器置顶" : "播放器置顶")
                .accessibilityLabel(model.pinned ? "取消播放器置顶" : "播放器置顶")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(playback.station?.name ?? "听见，另一个地方。")
                    .font(.headline).lineLimit(2)
                Text(playback.station?.detail ?? "选择收藏电台，或随机漫游下一站")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    if playback.isActive && playback.status != .playing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Circle().fill(playback.status == .playing ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                    }
                    Text(playback.status.label).lineLimit(2)
                    Spacer(minLength: 0)
                    if let station = playback.station {
                        Text(quality(station)).monospaced()
                    }
                }.font(.caption2).foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                Button {
                    if let station = playback.station { model.toggleFavorite(station) }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.title3).foregroundStyle(isFavorite ? Color.pink : Color.secondary)
                        .frame(width: 44, height: 44)
                }
                .disabled(playback.station == nil)
                .help(isFavorite ? "取消收藏" : "收藏当前电台")
                .accessibilityLabel(isFavorite ? "取消收藏" : "收藏当前电台")
                Spacer()
                Button { playback.toggle() } label: {
                    Image(systemName: playback.isActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 52, height: 52)
                        .background(Color.accentColor, in: Circle())
                }
                .disabled(playback.station == nil && model.visibleStations.isEmpty)
                .help(playback.isActive ? "暂停" : "播放")
                .accessibilityLabel(playback.isActive ? "暂停" : "播放")
                Spacer()
                Button { model.randomNext() } label: {
                    Image(systemName: "shuffle").font(.title3).frame(width: 44, height: 44)
                }
                .disabled(model.visibleStations.isEmpty)
                .help("随机下一站").accessibilityLabel("随机下一站")
                Button { playback.stop() } label: {
                    Image(systemName: "stop.fill").font(.subheadline).frame(width: 36, height: 44)
                }
                .disabled(playback.status == .idle && playback.sleepDeadline == nil)
                .help("停止播放并取消定时").accessibilityLabel("停止播放")
            }

            HStack(spacing: 10) {
                Button(action: toggleMute) {
                    Image(systemName: playback.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 24, height: 24)
                }
                .help(playback.volume == 0 ? "取消静音" : "静音")
                .accessibilityLabel(playback.volume == 0 ? "取消静音" : "静音")
                Slider(value: $playback.volume, in: 0...1).accessibilityLabel("播放音量")
                Text("\(Int((playback.volume * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            HStack {
                Label("睡眠定时", systemImage: "moon.zzz")
                Spacer()
                if let deadline = playback.sleepDeadline {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(remaining(until: deadline, at: context.date)).monospacedDigit()
                    }
                } else {
                    Text("未开启")
                }
                Menu {
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Button("\(minutes) 分钟后停止") { playback.setSleep(minutes: minutes) }
                    }
                    Divider()
                    Button("取消定时") { playback.setSleep(minutes: nil) }
                        .disabled(playback.sleepDeadline == nil)
                } label: { Text("设置") }
                .menuStyle(.borderlessButton).fixedSize()
                .help("设置睡眠定时").accessibilityLabel("设置睡眠定时")
            }.font(.caption).foregroundStyle(.secondary)

            if let message = model.storageError {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            if model.visibleStations.isEmpty {
                Text(model.loading ? "正在寻找电台…" : "当前列表暂无电台，打开播放器探索或添加。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                stationMenu("收藏电台", icon: "heart", stations: model.library.favorites, tab: .favorites)
                Spacer()
                stationMenu("最近收听", icon: "clock", stations: model.library.recent, tab: .recent)
            }.font(.caption)
            HStack {
                Button { showWindow("player") } label: {
                    Label("打开播放器", systemImage: "macwindow")
                }
                Spacer()
                Menu {
                    Button("探索电台") {
                        model.tab = .discover
                        model.expanded = true
                        showWindow("player")
                    }
                    Button("刷新电台目录") { model.search() }
                    Button("数据来源与隐私") { showWindow("privacy") }
                    Divider()
                    Button("退出 Mini Radio") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
                .help("更多选项").accessibilityLabel("更多选项")
            }.font(.caption)
        }
        .buttonStyle(.plain)
        .padding(18).frame(width: 340)
    }

    private var isFavorite: Bool { playback.station.map(model.isFavorite) == true }

    private func stationMenu(_ title: String, icon: String, stations: [Station], tab: RadioModel.Tab) -> some View {
        Menu {
            if stations.isEmpty {
                Text(tab == .favorites ? "暂无收藏电台" : "暂无收听记录")
            }
            ForEach(stations.prefix(10)) { station in
                Button {
                    model.select(station)
                } label: {
                    if playback.station?.id == station.id {
                        Label(station.name, systemImage: "checkmark")
                    } else {
                        Text(station.name)
                    }
                }
            }
            Divider()
            Button("查看全部\(tab.rawValue)") {
                model.tab = tab
                model.expanded = true
                showWindow("player")
            }
        } label: {
            Label("\(title) · \(stations.count)", systemImage: icon)
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private func quality(_ station: Station) -> String {
        [station.codec, station.bitrate > 0 ? "\(station.bitrate) kbps" : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func remaining(until deadline: Date, at now: Date) -> String {
        let seconds = max(0, Int(ceil(deadline.timeIntervalSince(now))))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func toggleMute() {
        if playback.volume > 0 {
            volumeBeforeMuting = playback.volume
            playback.volume = 0
        } else {
            playback.volume = volumeBeforeMuting
        }
    }

    private func showWindow(_ id: String) {
        openWindow(id: id)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
#endif

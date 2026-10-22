#if os(macOS)
import SwiftUI
import AppKit
import RadioCore

struct PlayerView: View {
    @ObservedObject var model: RadioModel
    @ObservedObject var playback: PlaybackController
    @State private var adding = false
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("MINI RADIO", systemImage: "radio").font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(2).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.pinned.toggle() } label: {
                        Image(systemName: model.pinned ? "pin.fill" : "pin")
                    }.help(model.pinned ? "取消窗口置顶" : "窗口置顶")
                    .accessibilityLabel("窗口置顶").buttonStyle(.borderless)
                    Menu {
                        Button("添加直播地址…") { adding = true }
                        Menu("睡眠定时") {
                            ForEach([15, 30, 45, 60], id: \.self) { n in
                                Button("\(n) 分钟后停止") { playback.setSleep(minutes: n) }
                            }
                            Button("取消定时") { playback.setSleep(minutes: nil) }.disabled(playback.sleepDeadline == nil)
                        }
                        Button("停止播放") { playback.stop() }
                        Divider()
                        Button("数据来源与隐私") { openWindow(id: "privacy") }
                        Button("退出 Mini Radio") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).frame(width: 22).help("更多选项")
                }

                HStack(alignment: .center, spacing: 17) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20).fill(Color.accentColor.opacity(0.12))
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 30, weight: .light)).foregroundStyle(Color.accentColor)
                    }.frame(width: 76, height: 76).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(playback.station?.name ?? "听见，另一个地方。")
                            .font(.system(size: 22, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                        Text(playback.station?.detail ?? "从一座城市，漫游到下一座")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: 5) {
                            Circle().fill(playback.status == .playing ? Color.green : Color.secondary.opacity(0.5)).frame(width: 5, height: 5)
                            Text(playback.status.label).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        }.accessibilityElement(children: .combine)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 24) {
                    Button { if let station = playback.station { model.toggleFavorite(station) } } label: {
                        Image(systemName: playback.station.map(model.isFavorite) == true ? "heart.fill" : "heart")
                            .font(.system(size: 19)).foregroundStyle(playback.station.map(model.isFavorite) == true ? Color.pink : Color.secondary)
                    }.disabled(playback.station == nil).help("收藏当前电台").accessibilityLabel("收藏当前电台")
                    Spacer(minLength: 4)
                    Button { playback.toggle() } label: {
                        Image(systemName: playback.isActive ? "pause.fill" : "play.fill")
                            .font(.system(size: 22)).frame(width: 56, height: 56)
                            .background(Color.accentColor, in: Circle()).foregroundStyle(.white)
                    }.keyboardShortcut(.space, modifiers: [])
                        .help(playback.isActive ? "暂停 · 空格" : "播放 · 空格")
                        .accessibilityLabel(playback.isActive ? "暂停" : "播放")
                    Spacer(minLength: 4)
                    Button { model.randomNext() } label: {
                        Image(systemName: "shuffle").font(.system(size: 20))
                    }.keyboardShortcut(.rightArrow, modifiers: [.command]).help("随机下一站 · ⌘→").accessibilityLabel("随机下一站")
                }.buttonStyle(.plain).padding(.horizontal, 24)

                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").font(.system(size: 11)).foregroundStyle(.secondary).accessibilityHidden(true)
                    Slider(value: $playback.volume, in: 0...1).accessibilityLabel("播放音量")
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                HStack {
                    Button { model.expanded.toggle() } label: {
                        Label(model.expanded ? "收起电台" : "探索电台", systemImage: model.expanded ? "chevron.up" : "square.grid.2x2")
                            .font(.system(size: 12, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                    Spacer()
                    if let deadline = playback.sleepDeadline {
                        HStack(spacing: 4) {
                            Image(systemName: "moon.zzz")
                            Text(deadline, style: .time)
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                        .help("到时停止播放")
                    } else {
                        Text("LIVE · 随心漫游").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                }
            }.padding(24)

            if let error = model.storageError {
                Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 24).padding(.bottom, 10)
            }
            if !model.expanded, let notice = model.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 10)
            }
            if model.expanded {
                Divider()
                DirectoryView(model: model, playback: playback)
            }
        }
        .frame(width: 420)
        .background(.regularMaterial)
        .background(WindowConfiguration(pinned: model.pinned))
        .sheet(isPresented: $adding) { AddStationView(model: model) }
    }
}

struct DirectoryView: View {
    @ObservedObject var model: RadioModel
    @ObservedObject var playback: PlaybackController

    var body: some View {
        VStack(spacing: 12) {
            Picker("电台列表", selection: $model.tab) {
                ForEach(RadioModel.Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索电台名称", text: $model.query.name)
                    .textFieldStyle(.plain).onSubmit { model.search() }
                if !model.query.name.isEmpty {
                    Button { model.query.name = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("清除搜索")
                }
            }.padding(8).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 8) {
                Picker("国家", selection: $model.query.countrycode) {
                    Text("所有国家").tag("")
                    Text("中国").tag("CN"); Text("美国").tag("US"); Text("英国").tag("GB")
                    Text("日本").tag("JP"); Text("法国").tag("FR"); Text("德国").tag("DE")
                }.labelsHidden().frame(maxWidth: .infinity)
                Picker("流派", selection: $model.query.tag) {
                    Text("所有流派").tag("")
                    Text("爵士").tag("jazz"); Text("古典").tag("classical"); Text("流行").tag("pop")
                    Text("氛围").tag("ambient"); Text("摇滚").tag("rock"); Text("新闻").tag("news")
                }.labelsHidden().frame(maxWidth: .infinity)
                Picker("语言", selection: $model.query.language) {
                    Text("所有语言").tag(""); Text("中文").tag("chinese"); Text("英语").tag("english")
                    Text("日语").tag("japanese"); Text("法语").tag("french")
                }.labelsHidden().frame(maxWidth: .infinity)
            }.controlSize(.small)

            ScrollView {
                LazyVStack(spacing: 3) {
                    if model.visibleStations.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: model.tab == .favorites ? "heart" : "radio").font(.title2)
                            Text(model.loading && model.tab == .discover ? "正在寻找电台…" : "这里还没有电台")
                            Text(model.tab == .favorites ? "收藏喜欢的声音，下次一键收听" : "试试调整筛选，或添加直播地址")
                                .font(.caption)
                        }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    ForEach(model.visibleStations) { station in
                        HStack(spacing: 8) {
                            Button { model.select(station) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: playback.station?.id == station.id && playback.isActive ? "speaker.wave.2.fill" : "radio")
                                        .foregroundStyle(playback.station?.id == station.id ? Color.accentColor : Color.secondary).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(station.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                        Text(station.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    if station.bitrate > 0 { Text("\(station.bitrate)k").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary) }
                                }.padding(.vertical, 10).padding(.leading, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button { model.toggleFavorite(station) } label: {
                                Image(systemName: model.isFavorite(station) ? "heart.fill" : "heart")
                                    .foregroundStyle(model.isFavorite(station) ? Color.pink : Color.secondary)
                                    .frame(width: 28, height: 36)
                            }.buttonStyle(.plain).accessibilityLabel(model.isFavorite(station) ? "取消收藏 \(station.name)" : "收藏 \(station.name)")
                        }.background(playback.station?.id == station.id ? Color.accentColor.opacity(0.07) : Color.clear,
                                     in: RoundedRectangle(cornerRadius: 8))
                    }
                    if model.tab == .discover, model.canLoadMore, !model.stations.isEmpty {
                        Button("加载更多") { model.loadMore() }.disabled(model.loading).padding(.vertical, 10)
                    }
                }
            }.frame(height: 265)
            HStack(spacing: 6) {
                if model.loading { ProgressView().controlSize(.mini) }
                if let notice = model.notice { Text(notice).lineLimit(2) }
                else if let date = model.cachedDate { Text("缓存目录 · \(date.formatted(date: .abbreviated, time: .shortened))") }
                else { Text("目录来自 Radio Browser · 音频由电台提供") }
                Spacer(minLength: 0)
                Button { model.search() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("刷新电台目录").accessibilityLabel("刷新电台目录")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(16)
            .onChange(of: model.query) { _ in model.search(debounce: true) }
    }
}

struct AddStationView: View {
    @ObservedObject var model: RadioModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var invalid = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加你的电台").font(.title3.weight(.semibold))
            TextField("电台名称（选填）", text: $name)
            TextField("https://… 直播地址", text: $address)
            Text("请输入直接 MP3、AAC 或 HLS 直播地址，普通网站页面无法播放。HTTP 地址会使用未加密连接。")
                .font(.caption).foregroundStyle(.secondary)
            if invalid { Text("请输入有效的 HTTP 或 HTTPS 地址。").font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("收藏并播放") {
                    if model.addManual(name: name, address: address) { dismiss() } else { invalid = true }
                }.keyboardShortcut(.defaultAction)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 380)
    }
}

struct PrivacyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Mini Radio", systemImage: "radio").font(.title2.weight(.semibold))
            Text("收藏、最近收听与偏好保存在本机。应用不要求账号，不申请麦克风权限，不接入广告或行为分析 SDK。")
            Text("电台目录与搜索请求发送给 Radio Browser；主动选台会按目录服务约定上报电台标识用于点击计数。直播音频直接连接电台服务器，相关服务能看到你的 IP 地址。部分电台使用未加密 HTTP。")
            Text("目录健康状态不代表当前网络一定可播。离线时可以查看本地收藏和缓存，直播仍然需要网络。")
            Link("Radio Browser", destination: URL(string: "https://www.radio-browser.info/")!)
            Link("体验灵感：RoamDial", destination: URL(string: "https://roamdial.com/about.html")!)
            Text("0.1.1 · 原生 macOS 小收音机").font(.caption).foregroundStyle(.secondary)
        }.font(.system(size: 13)).padding(28).frame(width: 440)
    }
}

struct WindowConfiguration: NSViewRepresentable {
    var pinned: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = pinned ? .floating : .normal
            window.title = "Mini Radio"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .windowBackgroundColor
            window.isMovableByWindowBackground = true
        }
    }
}

#endif

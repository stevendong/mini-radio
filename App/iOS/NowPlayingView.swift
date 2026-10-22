import SwiftUI
import AVKit
import MediaPlayer

struct NowPlayingView: View {
    @ObservedObject var model: RadioModel
    @ObservedObject var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var artworkSize = 220

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text("MINI RADIO").font(.caption.monospaced().weight(.semibold)).tracking(3)
                        Text("声音，会带你去远方。").font(.caption).foregroundStyle(.secondary)
                    }.foregroundStyle(.secondary).padding(.top, 8)
                    ZStack {
                        RoundedRectangle(cornerRadius: 42, style: .continuous)
                            .fill(LinearGradient(colors: [Color.accentColor.opacity(0.20), Color.accentColor.opacity(0.06)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "radio").font(.system(size: 84, weight: .ultraLight)).foregroundStyle(Color.accentColor)
                    }.frame(width: min(artworkSize, 260), height: min(artworkSize, 260)).accessibilityHidden(true)
                    VStack(spacing: 10) {
                        Text(playback.station?.name ?? "听见，另一个地方。")
                            .font(.system(.title, design: .rounded, weight: .semibold)).multilineTextAlignment(.center)
                            .accessibilityIdentifier("player-station-name")
                        Text(playback.station?.detail ?? "选一座城市，或把目的地交给随机")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Label(playback.status.label, systemImage: playback.status == .playing ? "dot.radiowaves.left.and.right" : "circle")
                            .font(.caption).foregroundStyle(playback.status == .playing ? Color.green : Color.secondary)
                            .accessibilityIdentifier("player-status")
                        if let station = playback.station {
                            let quality = [station.codec, station.bitrate > 0 ? "\(station.bitrate) kbps" : ""].filter { !$0.isEmpty }
                            if !quality.isEmpty { Text(quality.joined(separator: " · ")).font(.caption2.monospaced()).foregroundStyle(.tertiary) }
                        }
                    }
                    HStack(spacing: 32) {
                        Button {
                            if let station = playback.station { model.toggleFavorite(station) }
                        } label: {
                            Image(systemName: playback.station.map(model.isFavorite) == true ? "heart.fill" : "heart")
                                .font(.title2).frame(width: 48, height: 56)
                                .foregroundStyle(playback.station.map(model.isFavorite) == true ? Color.pink : Color.secondary)
                        }.disabled(playback.station == nil).accessibilityLabel("收藏当前电台")
                        Button { playback.toggle() } label: {
                            Image(systemName: playback.isActive ? "pause.fill" : "play.fill")
                                .font(.system(size: 30)).foregroundStyle(.white).frame(width: 80, height: 80)
                                .background(Color.accentColor, in: Circle())
                        }.accessibilityLabel(playback.isActive ? "暂停" : "播放").accessibilityIdentifier("player-play")
                        Button { model.randomNext() } label: {
                            Image(systemName: "shuffle").font(.title2).frame(width: 48, height: 56)
                        }.accessibilityLabel("随机下一站").accessibilityIdentifier("player-next")
                    }.buttonStyle(.plain)
                    VStack(spacing: 16) {
                        SystemVolumeView().frame(height: 30).accessibilityLabel("系统播放音量")
                        HStack {
                            Menu {
                                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                                    Button("\(minutes) 分钟后停止") { playback.setSleep(minutes: minutes) }
                                }
                                Button("取消定时") { playback.setSleep(minutes: nil) }.disabled(playback.sleepDeadline == nil)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "moon.zzz")
                                    if let deadline = playback.sleepDeadline { Text(deadline, style: .time) }
                                    else { Text("睡眠定时") }
                                }.font(.subheadline)
                            }.accessibilityIdentifier("sleep-timer")
                            Spacer()
                            AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("选择 AirPlay 输出")
                            Button { playback.stop() } label: { Image(systemName: "stop.circle").font(.title3).frame(width: 44, height: 44) }
                                .accessibilityLabel("停止播放").accessibilityIdentifier("player-stop")
                        }
                    }
                }.padding(.horizontal, 30).padding(.bottom, 24).frame(maxWidth: 540).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("dismiss-player")
                }
            }
        }
    }
}

struct SystemVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        return view
    }
    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

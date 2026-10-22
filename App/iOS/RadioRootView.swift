import SwiftUI
import RadioCore

struct RadioRootView: View {
    @ObservedObject var model: RadioModel
    @ObservedObject var playback: PlaybackController
    @State private var showingPlayer = false
    @State private var adding = false
    @State private var privacy = false
    @State private var filters = false
    @State private var syncing = false

    var body: some View {
        TabView(selection: $model.tab) {
            ForEach(RadioModel.Tab.allCases, id: \.self) { tab in
                NavigationStack {
                    StationBrowser(model: model, playback: playback, tab: tab, filters: $filters)
                        .navigationTitle(tab == .discover ? "听见远方" : tab.rawValue)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button { adding = true } label: { Image(systemName: "plus.circle") }
                                    .accessibilityLabel("添加电台").accessibilityIdentifier("add-station")
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Menu {
                                    Button { filters = true } label: { Label("筛选电台", systemImage: "line.3.horizontal.decrease.circle") }
                                    Button { model.search() } label: { Label("刷新目录", systemImage: "arrow.clockwise") }
                                    Button { syncing = true } label: { Label("收藏与收听同步", systemImage: "arrow.triangle.2.circlepath") }
                                        .accessibilityIdentifier("library-sync")
                                    Button { privacy = true } label: { Label("数据来源与隐私", systemImage: "hand.raised") }
                                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("更多选项")
                            }
                        }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            CompactPlayer(model: model, playback: playback) { showingPlayer = true }
                        }
                }
                .tabItem { Label(tab.rawValue, systemImage: icon(tab)) }
                .tag(tab)
            }
        }
        .onChange(of: model.tab) { tab in if tab == .discover { model.search() } }
        .sheet(isPresented: $showingPlayer) {
            NowPlayingView(model: model, playback: playback)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $adding) { AddRadioView(model: model) }
        .sheet(isPresented: $privacy) { IOSPrivacyView() }
        .sheet(isPresented: $filters) { RadioFiltersView(model: model) }
        .sheet(isPresented: $syncing) {
            NavigationStack {
                LibrarySyncView(sync: model.sync)
                    .navigationTitle("收藏与收听同步")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { syncing = false } }
                    }
            }
        }
    }

    private func icon(_ tab: RadioModel.Tab) -> String {
        switch tab { case .discover: return "globe.europe.africa"; case .favorites: return "heart"; case .recent: return "clock" }
    }
}

struct StationBrowser: View {
    @ObservedObject var model: RadioModel
    @ObservedObject var playback: PlaybackController
    let tab: RadioModel.Tab
    @Binding var filters: Bool
    private var rows: [Station] { model.visibleStations }

    var body: some View {
        List {
            if tab == .discover {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("MINI RADIO", systemImage: "radio").font(.caption.monospaced().weight(.semibold)).tracking(2)
                            Spacer()
                            Text("LIVE").font(.caption2.monospaced().weight(.medium))
                        }.foregroundStyle(.secondary)
                        Text("把日常，调到另一座城市。")
                            .font(.system(.title2, design: .rounded, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        Text("一段旋律，一种语言，一扇通往远方的小窗。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button { model.randomNext() } label: {
                            Label {
                                Text("随心漫游").foregroundStyle(.white)
                            } icon: {
                                Image(systemName: "shuffle").foregroundStyle(.white)
                            }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 5)
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("discover-shuffle")
                    }.padding(.vertical, 12)
                }.listRowBackground(Color.accentColor.opacity(0.075))
                Section {
                    Button { filters = true } label: {
                        HStack {
                            Label("国家、语言与流派", systemImage: "line.3.horizontal.decrease.circle")
                            Spacer()
                            Text(hasFilters ? "已筛选" : "全部").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.font(.subheadline)
                    }.accessibilityIdentifier("station-filters")
                }
            }
            if let message = model.storageError {
                Section { Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            }
            Section {
                if rows.isEmpty {
                    VStack(spacing: 12) {
                        if model.loading && tab == .discover { ProgressView() }
                        else { Image(systemName: tab == .favorites ? "heart" : "antenna.radiowaves.left.and.right").font(.largeTitle) }
                        Text(emptyTitle).font(.headline)
                        Text(tab == .favorites ? "点亮电台旁的爱心，把喜欢的声音留在这里。" : "调整搜索条件，或使用左上角添加直播地址。")
                            .font(.subheadline).multilineTextAlignment(.center)
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 30)
                }
                ForEach(rows) { station in
                    StationRow(station: station, model: model, playback: playback)
                        .listRowSeparator(.hidden)
                }
                if tab == .discover, model.canLoadMore, !model.stations.isEmpty {
                    Button { model.loadMore() } label: {
                        HStack { Spacer(); if model.loading { ProgressView() } else { Text("加载更多电台") }; Spacer() }
                    }.disabled(model.loading)
                }
            } header: { Text(tab == .discover ? "正在世界各地播出" : tab.rawValue) }
            if tab == .discover {
                Section {
                    if let message = model.notice { Text(message) }
                    else if let date = model.cachedDate { Text("缓存目录 · \(date.formatted(date: .abbreviated, time: .shortened))") }
                    Text("目录由 Radio Browser 提供，直播音频来自各电台。")
                }.font(.caption).foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $model.query.name, prompt: "搜索电台名称")
        .onChange(of: model.query.name) { _ in
            if tab == .discover && model.tab == .discover { model.search(debounce: true) }
        }
        .refreshable { if tab == .discover { model.search() } }
    }

    private var hasFilters: Bool { !model.query.countrycode.isEmpty || !model.query.tag.isEmpty || !model.query.language.isEmpty }
    private var emptyTitle: String {
        if model.loading && tab == .discover { return "正在寻找电台…" }
        return tab == .favorites ? "收藏一段喜欢的声音" : "这里还没有电台"
    }
}

struct StationRow: View {
    let station: Station
    @ObservedObject var model: RadioModel
    @ObservedObject var playback: PlaybackController
    var body: some View {
        HStack(spacing: 12) {
            Button { model.select(station) } label: {
                HStack(spacing: 12) {
                    Image(systemName: playback.station?.id == station.id && playback.isActive ? "speaker.wave.2.fill" : "radio")
                        .font(.title3).frame(width: 44, height: 44)
                        .foregroundStyle(Color.accentColor).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(station.name).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                        Text(station.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 5).contentShape(Rectangle())
            }.buttonStyle(.borderless).accessibilityIdentifier("station-\(station.id)")
            Button { model.toggleFavorite(station) } label: {
                Image(systemName: model.isFavorite(station) ? "heart.fill" : "heart")
                    .foregroundStyle(model.isFavorite(station) ? Color.pink : Color.secondary).frame(width: 44, height: 44)
            }.buttonStyle(.borderless)
                .accessibilityLabel(model.isFavorite(station) ? "取消收藏 \(station.name)" : "收藏 \(station.name)")
                .accessibilityIdentifier("favorite-\(station.id)")
        }
    }
}

struct CompactPlayer: View {
    @ObservedObject var model: RadioModel
    @ObservedObject var playback: PlaybackController
    var expand: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Button(action: expand) {
                HStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.title3)
                        .frame(width: 42, height: 42).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playback.station?.name ?? "准备好，听见远方").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(playback.status.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("open-player")
            Button { playback.toggle() } label: {
                Image(systemName: playback.isActive ? "pause.fill" : "play.fill").font(.title3).frame(width: 44, height: 48)
            }.accessibilityLabel(playback.isActive ? "暂停" : "播放").accessibilityIdentifier("compact-play")
            Button { model.randomNext() } label: {
                Image(systemName: "shuffle").font(.title3).frame(width: 44, height: 48)
            }.accessibilityLabel("随机下一站").accessibilityIdentifier("compact-next")
        }.padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial).overlay(alignment: .top) { Divider() }
    }
}

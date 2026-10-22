import CarPlay
import Combine
import RadioCore
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPTabBarTemplateDelegate {
    private let session = IOSRadioSession.shared
    private var model: RadioModel { session.model }
    private var interfaceController: CPInterfaceController?
    private var subscriptions: Set<AnyCancellable> = []
    private var lists: [RadioModel.Tab: CPListTemplate] = [:]
    private var currentTab: RadioModel.Tab = .favorites
    private var pushingNowPlaying = false
    private var contentStyle: UIUserInterfaceStyle = .dark

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        contentStyle = templateApplicationScene.contentStyle
        session.connectCarPlay(templateApplicationScene.session.persistentIdentifier)
        let templates = [RadioModel.Tab.favorites, .recent, .discover].map { tab in
            let list = CPListTemplate(title: tab.rawValue, sections: [])
            list.tabTitle = tab.rawValue
            list.tabImage = UIImage(systemName: icon(for: tab))
            list.emptyViewTitleVariants = [emptyTitle(for: tab)]
            list.emptyViewSubtitleVariants = [tab == .discover ? "可使用缓存，或稍后刷新重试" : "在 iPhone 添加电台后，这里会自动更新"]
            lists[tab] = list
            return list
        }
        let tabs = CPTabBarTemplate(templates: templates)
        tabs.delegate = self
        refresh()
        interfaceController.setRootTemplate(tabs, animated: false) { [weak self] success, _ in
            if !success { self?.model.notice = "车载界面暂时无法打开，请重新连接 CarPlay。" }
        }
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        model.playback.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        session.disconnectCarPlay(templateApplicationScene.session.persistentIdentifier)
        subscriptions.removeAll()
        lists.removeAll()
        self.interfaceController = nil
        pushingNowPlaying = false
    }

    func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        if let tab = lists.first(where: { $0.value === selectedTemplate })?.key { currentTab = tab }
        refreshNowPlayingButtons()
    }

    func contentStyleDidChange(_ contentStyle: UIUserInterfaceStyle) {
        self.contentStyle = contentStyle
        refresh()
    }

    private func refresh() {
        for (tab, list) in lists {
            let limit = max(0, min(50, CPListTemplate.maximumItemCount))
            let stations = Array(model.stations(for: tab).prefix(limit))
            var sections: [CPListSection] = []
            var actions: [CPListItem] = []
            if !stations.isEmpty {
                let random = CPListItem(text: "随心漫游", detailText: "随机收听此分类的电台", image: listSymbol("shuffle"))
                random.handler = { [weak self] _, completion in
                    Task { @MainActor in
                        defer { completion() }
                        guard let self else { return }
                        self.model.randomNext(from: tab)
                        self.showNowPlaying()
                    }
                }
                actions.append(random)
            }
            if tab == .discover {
                let reload = CPListItem(text: model.loading ? "正在刷新…" : "刷新目录",
                                        detailText: model.notice ?? "获取最新电台列表", image: listSymbol("arrow.clockwise"))
                reload.isEnabled = !model.loading
                reload.handler = { [weak self] _, completion in
                    Task { @MainActor in
                        defer { completion() }
                        self?.model.search()
                    }
                }
                actions.append(reload)
            }
            if !actions.isEmpty { sections.append(CPListSection(items: actions)) }
            let items = stations.prefix(max(0, limit - actions.count)).map { station in
                stationItem(station, tab: tab)
            }
            if !items.isEmpty { sections.append(CPListSection(items: items)) }
            list.updateSections(sections)
            if tab == .discover {
                list.emptyViewTitleVariants = [model.loading ? "正在寻找电台…" : emptyTitle(for: tab)]
                list.emptyViewSubtitleVariants = [model.notice ?? "可使用缓存，或稍后刷新重试"]
                let refresh = CPBarButton(title: "刷新") { [weak self] _ in self?.model.search() }
                refresh.isEnabled = !model.loading
                list.leadingNavigationBarButtons = [refresh]
            }
            let nowPlaying = CPBarButton(title: "正在播放") { [weak self] _ in self?.showNowPlaying() }
            nowPlaying.isEnabled = model.playback.station != nil
            list.trailingNavigationBarButtons = [nowPlaying]
        }
        refreshNowPlayingButtons()
    }

    private func stationItem(_ station: Station, tab: RadioModel.Tab) -> CPListItem {
        let selected = model.playback.station?.id == station.id
        let detail = selected ? model.playback.status.label + " · " + station.detail : station.detail
        let item = CPListItem(text: station.name, detailText: detail, image: listSymbol("radio"))
        item.isPlaying = selected && model.playback.isActive
        item.playingIndicatorLocation = .trailing
        item.handler = { [weak self] _, completion in
            Task { @MainActor in
                defer { completion() }
                guard let self else { return }
                self.model.select(station, from: tab)
                self.showNowPlaying()
            }
        }
        return item
    }

    private func refreshNowPlayingButtons() {
        let playback = model.playback
        let favorite = playback.station.map(model.isFavorite) == true
        let heart = CPNowPlayingImageButton(image: symbol(favorite ? "heart.fill" : "heart")) { [weak self] _ in
            guard let self, let station = self.model.playback.station else { return }
            self.model.toggleFavorite(station)
        }
        heart.isEnabled = playback.station != nil
        heart.isSelected = favorite
        let shuffle = CPNowPlayingImageButton(image: symbol("shuffle")) { [weak self] _ in
            guard let self else { return }
            self.model.randomNext(from: self.currentTab)
        }
        shuffle.isEnabled = !model.stations(for: currentTab).isEmpty
        let stop = CPNowPlayingImageButton(image: symbol("stop.fill")) { [weak self] _ in self?.model.playback.stop() }
        stop.isEnabled = playback.isActive || playback.status == .paused || playback.sleepDeadline != nil
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([heart, shuffle, stop])
    }

    private func showNowPlaying() {
        guard let interfaceController, model.playback.station != nil,
              interfaceController.topTemplate !== CPNowPlayingTemplate.shared, !pushingNowPlaying else { return }
        pushingNowPlaying = true
        interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true) { [weak self] success, _ in
            self?.pushingNowPlaying = false
            if !success { self?.model.notice = "暂时无法打开车载播放页，请返回电台列表重试。" }
        }
    }

    private func symbol(_ name: String) -> UIImage {
        UIImage(systemName: name) ?? UIImage()
    }

    private func listSymbol(_ name: String) -> UIImage? {
        UIImage(systemName: name)?.withTintColor(contentStyle == .light ? .black : .white, renderingMode: .alwaysOriginal)
    }

    private func icon(for tab: RadioModel.Tab) -> String {
        switch tab {
        case .favorites: return "heart"
        case .recent: return "clock"
        case .discover: return "globe.europe.africa"
        }
    }

    private func emptyTitle(for tab: RadioModel.Tab) -> String {
        switch tab {
        case .favorites: return "暂无收藏电台"
        case .recent: return "暂无收听记录"
        case .discover: return "暂时没有可用电台"
        }
    }
}

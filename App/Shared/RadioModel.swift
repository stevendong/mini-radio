#if os(macOS) || os(iOS)
import Foundation
import Combine
import RadioCore

@MainActor
final class RadioModel: ObservableObject {
    enum Tab: String, CaseIterable { case discover = "发现", favorites = "收藏", recent = "最近" }
    @Published var library = Library()
    @Published var stations: [Station] = []
    @Published var tab: Tab = .discover
    @Published var query = StationQuery()
    @Published var loading = false
    @Published var canLoadMore = true
    @Published var notice: String?
    @Published var storageError: String?
    @Published var cachedDate: Date?
    @Published var expanded = false
    @Published var pinned = UserDefaults.standard.bool(forKey: "pinned") {
        didSet { UserDefaults.standard.set(pinned, forKey: "pinned") }
    }
    let playback = PlaybackController()
    let sync: LibrarySyncController
    private let directory = RadioDirectory()
    private let store: LibraryStore
    private var searchTask: Task<Void, Never>?
    private var queryGeneration = UUID()
    private var offset = 0
    private var recentRandom: [String] = []
    private var maySaveLibrary = true

    init(automaticallyLoad: Bool = true, storageDirectory: URL? = nil) {
        sync = LibrarySyncController(available: storageDirectory == nil)
        let base = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiniRadio", isDirectory: true)
        store = LibraryStore(directory: base)
        do { library = try store.load() }
        catch {
            maySaveLibrary = false
            storageError = "收藏文件读取失败，已保留原文件。本次收藏修改不会覆盖它。"
        }
        playback.restore(library.lastStation)
        playback.onSuccessfulPlayback = { [weak self] station in
            guard let self else { return }
            self.library.recordSuccessfulPlayback(station); self.save()
        }
        playback.onNext = { [weak self] in self?.randomNext() }
        sync.snapshot = { [weak self] in
            guard let self, self.maySaveLibrary, self.storageError == nil else {
                throw SyncServiceError.localStorageUnavailable
            }
            return LibrarySyncDocument(library: self.library)
        }
        sync.receive = { [weak self] document in
            guard let self, self.maySaveLibrary else { throw SyncServiceError.localStorageUnavailable }
            var merged = self.library
            merged.merge(document)
            try self.store.save(merged)
            self.library = merged
            self.storageError = nil
            if self.playback.station == nil { self.playback.restore(merged.lastStation) }
        }
        loadCache()
        if automaticallyLoad { search() }
    }

    func select(_ station: Station) {
        playback.play(station)
        Task { await directory.recordSelection(station) }
    }

    func toggleFavorite(_ station: Station) { library.toggleFavorite(station); save() }
    func isFavorite(_ station: Station) -> Bool { library.favorites.contains { $0.id == station.id } }

    func addManual(name: String, address: String) -> Bool {
        guard let station = Station.manual(name: name, address: address) else { return false }
        if let existing = library.favorites.first(where: { $0.url == station.url }) { select(existing); return true }
        library.setFavorite(station, enabled: true); save(); select(station); return true
    }

    func randomNext() {
        let source = visibleStations
        let candidates = source.filter { $0.id != playback.station?.id && !recentRandom.contains($0.id) }
        let fallback = source.filter { $0.id != playback.station?.id }
        guard let next = (candidates.isEmpty ? fallback : candidates).randomElement() ?? source.first else {
            expanded = true; notice = "当前列表还没有电台，请搜索或手动添加。"; return
        }
        recentRandom.append(next.id); recentRandom = Array(recentRandom.suffix(15)); select(next)
    }

    var visibleStations: [Station] {
        switch tab {
        case .discover: return stations
        case .favorites: return library.favorites.filter(matches)
        case .recent: return library.recent.filter(matches)
        }
    }

    private func matches(_ station: Station) -> Bool {
        (query.name.isEmpty || station.name.localizedCaseInsensitiveContains(query.name))
        && (query.countrycode.isEmpty || station.countrycode.caseInsensitiveCompare(query.countrycode) == .orderedSame)
        && (query.language.isEmpty || station.language.localizedCaseInsensitiveContains(query.language))
        && (query.tag.isEmpty || station.tags.localizedCaseInsensitiveContains(query.tag))
    }

    func search(debounce: Bool = false) {
        searchTask?.cancel()
        queryGeneration = UUID()
        let generation = queryGeneration, requested = query
        offset = 0; canLoadMore = true; notice = nil; loading = true
        if !restoreCache(for: requested) { stations = []; cachedDate = nil }
        searchTask = Task { [weak self] in
            if debounce {
                do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            }
            await self?.fetch(query: requested, generation: generation, more: false)
        }
    }

    func loadMore() {
        guard !loading, canLoadMore else { return }
        loading = true
        let requested = query, generation = queryGeneration
        searchTask = Task { [weak self] in await self?.fetch(query: requested, generation: generation, more: true) }
    }

    private func fetch(query: StationQuery, generation: UUID, more: Bool) async {
        do {
            let result = try await directory.search(query, offset: more ? offset : 0)
            guard !Task.isCancelled, queryGeneration == generation else { return }
            if more {
                let existing = Set(stations.map(\.id))
                stations += result.stations.filter { !existing.contains($0.id) }
            } else { stations = result.stations }
            offset = result.nextOffset
            canLoadMore = result.hasMore
            cachedDate = nil; notice = nil
            saveCache(query: query)
        } catch {
            guard !Task.isCancelled, queryGeneration == generation else { return }
            notice = error.localizedDescription
        }
        loading = false
    }

    private func save() {
        guard maySaveLibrary else { return }
        do { try store.save(library); storageError = nil; sync.localDataChanged() }
        catch { storageError = "收藏保存失败：\(error.localizedDescription)" }
    }

    private var cacheURL: URL { store.directory.appendingPathComponent("directory-cache.json") }
    private func loadCache() { _ = restoreCache(for: query) }
    @discardableResult private func restoreCache(for query: StationQuery) -> Bool {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(DirectorySnapshot.self, from: data), cache.query == query else { return false }
        stations = cache.stations; cachedDate = cache.date
        return true
    }
    private func saveCache(query: StationQuery) {
        do {
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(DirectorySnapshot(query: query, stations: stations))
            try data.write(to: cacheURL, options: .atomic)
        } catch { notice = "目录已载入，但缓存保存失败。" }
    }
}
#endif

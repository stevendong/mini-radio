#if os(macOS) || os(iOS)
import AVFoundation
import Combine
import MediaPlayer
import RadioCore

@MainActor
final class PlaybackController: ObservableObject {
    enum Status: Equatable {
        case idle, connecting, playing, paused, reconnecting(Int), failed(String)
        var label: String {
            switch self {
            case .idle: return "准备收听"
            case .connecting: return "正在连接…"
            case .playing: return "正在直播"
            case .paused: return "已暂停"
            case .reconnecting(let n): return "正在重连 · \(n)"
            case .failed(let message): return message
            }
        }
    }

    @Published private(set) var station: Station?
    @Published private(set) var status: Status = .idle
    @Published var volume: Double = 0.65 {
        didSet { player?.volume = Float(volume); UserDefaults.standard.set(volume, forKey: "volume") }
    }
    @Published private(set) var sleepDeadline: Date?
    var onSuccessfulPlayback: ((Station) -> Void)?
    var onNext: (() -> Void)?

    private var player: AVPlayer?
    private var observations: [NSKeyValueObservation] = []
    private var notifications: [NSObjectProtocol] = []
    private var policy = PlaybackSession()
    private var retryTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var reportedGeneration: UUID?
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    #if os(iOS)
    private var interruption = AudioInterruptionState()
    private var audioSessionObservers: [NSObjectProtocol] = []
    #endif

    var isActive: Bool {
        switch status { case .playing, .connecting, .reconnecting: return true; default: return false }
    }

    init() {
        #if os(iOS)
        volume = 1
        observeAudioSession()
        #else
        if UserDefaults.standard.object(forKey: "volume") != nil {
            volume = min(1, max(0, UserDefaults.standard.double(forKey: "volume")))
        }
        #endif
        let center = MPRemoteCommandCenter.shared()
        bind(center.playCommand) { $0.resume() }
        bind(center.pauseCommand) { $0.pause() }
        bind(center.togglePlayPauseCommand) { $0.toggle() }
        bind(center.stopCommand) { $0.stop() }
        bind(center.nextTrackCommand) { $0.onNext?() }
        center.previousTrackCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
    }

    private func bind(_ command: MPRemoteCommand, action: @escaping @MainActor (PlaybackController) -> Void) {
        command.isEnabled = true
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in if let self { action(self) } }
            return .success
        }
        remoteTargets.append((command, target))
    }

    func restore(_ station: Station?) { self.station = station; status = station == nil ? .idle : .paused }

    func play(_ station: Station) {
        #if os(iOS)
        interruption.userChangedPlayback()
        #endif
        invalidatePlayback()
        self.station = station
        reportedGeneration = nil
        #if os(iOS)
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default)
            try audio.setActive(true)
        } catch {
            status = .failed("暂时无法使用音频输出，请稍后重播")
            updateNowPlaying(); return
        }
        #endif
        guard let ticket = policy.start(urls: station.streamURLs) else {
            status = .failed("电台没有有效的直播地址")
            #if os(iOS)
            deactivateAudioSession()
            #endif
            updateNowPlaying(); return
        }
        begin(ticket)
    }

    func toggle() { isActive ? pause() : resume() }
    func resume() { if let station { play(station) } else { onNext?() } }

    func pause() {
        #if os(iOS)
        interruption.userChangedPlayback()
        #endif
        suspendPlayback()
        #if os(iOS)
        deactivateAudioSession()
        #endif
    }

    private func suspendPlayback() {
        invalidatePlayback()
        status = station == nil ? .idle : .paused
        updateNowPlaying()
    }

    func stop() {
        pause(); status = .idle
        setSleep(minutes: nil)
        updateNowPlaying()
    }

    func shutdown() {
        stop()
        remoteTargets.forEach { $0.0.removeTarget($0.1) }
        remoteTargets.removeAll()
        #if os(iOS)
        audioSessionObservers.forEach { NotificationCenter.default.removeObserver($0) }
        audioSessionObservers.removeAll()
        #endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func setSleep(minutes: Int?) {
        sleepTask?.cancel(); sleepTask = nil; sleepDeadline = nil
        guard let minutes, minutes > 0 else { return }
        let deadline = Date().addingTimeInterval(Double(minutes) * 60)
        sleepDeadline = deadline
        sleepTask = Task { [weak self] in
            // Wall-clock checks handle sleep/wake as well as ordinary elapsed time.
            while !Task.isCancelled, Date() < deadline {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func invalidatePlayback() {
        policy.cancel()
        retryTask?.cancel(); retryTask = nil
        teardownAttempt()
    }

    private func teardownAttempt() {
        watchdog?.cancel(); watchdog = nil
        observations.removeAll()
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications.removeAll()
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
    }

    private func begin(_ ticket: PlaybackSession.Ticket) {
        guard policy.accepts(ticket) else { return }
        teardownAttempt()
        status = ticket.attempt == 0 ? .connecting : .reconnecting(ticket.attempt)
        let item = AVPlayerItem(url: ticket.url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = Float(volume)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        player = newPlayer

        observations.append(item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let failed = item.status == .failed
            Task { @MainActor [weak self] in
                guard failed else { return }
                self?.failed(ticket)
            }
        })
        observations.append(newPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            let playing = p.timeControlStatus == .playing
            let waiting = p.timeControlStatus == .waitingToPlayAtSpecifiedRate
            Task { @MainActor [weak self] in
                guard let self, self.policy.accepts(ticket) else { return }
                if playing {
                    self.watchdog?.cancel(); self.watchdog = nil
                    self.status = .playing
                    if self.reportedGeneration != ticket.generation, let station = self.station {
                        self.reportedGeneration = ticket.generation
                        self.onSuccessfulPlayback?(station)
                    }
                    self.updateNowPlaying()
                } else if waiting {
                    self.status = ticket.attempt == 0 ? .connecting : .reconnecting(ticket.attempt)
                    self.armWatchdog(ticket)
                    self.updateNowPlaying()
                }
            }
        })
        for name in [AVPlayerItem.failedToPlayToEndTimeNotification, AVPlayerItem.didPlayToEndTimeNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.failed(ticket) }
            })
        }
        newPlayer.play()
        armWatchdog(ticket)
        updateNowPlaying()
    }

    private func armWatchdog(_ ticket: PlaybackSession.Ticket) {
        guard watchdog == nil else { return }
        watchdog = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 18_000_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            self?.failed(ticket)
        }
    }

    private func failed(_ ticket: PlaybackSession.Ticket) {
        guard policy.accepts(ticket) else { return }
        let next = policy.retry(after: ticket)
        teardownAttempt()
        guard let next else {
            status = .failed("连接失败，试试重播或下一站")
            #if os(iOS)
            deactivateAudioSession()
            #endif
            updateNowPlaying(); return
        }
        status = .reconnecting(next.attempt)
        updateNowPlaying()
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(next.attempt) * 1_000_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            self?.begin(next)
        }
    }

    #if os(iOS)
    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        audioSessionObservers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                                        object: nil, queue: .main) { [weak self] note in
            let kind = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor [weak self] in
                guard let self, let kind else { return }
                if kind == AVAudioSession.InterruptionType.began.rawValue {
                    self.interruption.begin(wasPlaying: self.isActive)
                    self.suspendPlayback()
                } else if kind == AVAudioSession.InterruptionType.ended.rawValue {
                    let allowed = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                    if self.interruption.end(systemAllowsResume: allowed) { self.resume() }
                }
            }
        })
        audioSessionObservers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                                        object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor [weak self] in self?.pause() }
        })
        audioSessionObservers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                                        object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.interruption.userChangedPlayback()
                self.suspendPlayback()
                self.status = .failed("音频服务已重置，请重新播放")
                self.updateNowPlaying()
            }
        })
    }
    #endif

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let station else {
            center.nowPlayingInfo = nil
            #if os(macOS)
            center.playbackState = .stopped
            #endif
            return
        }
        center.nowPlayingInfo = [MPMediaItemPropertyTitle: station.name,
                                MPMediaItemPropertyArtist: station.detail,
                                MPNowPlayingInfoPropertyIsLiveStream: true,
                                MPNowPlayingInfoPropertyPlaybackRate: status == .playing ? 1.0 : 0.0]
        #if os(macOS)
        switch status {
        case .playing: center.playbackState = .playing
        case .paused: center.playbackState = .paused
        case .idle, .failed: center.playbackState = .stopped
        default: center.playbackState = .interrupted
        }
        #endif
    }
}
#endif

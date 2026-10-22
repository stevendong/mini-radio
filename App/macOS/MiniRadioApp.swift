#if os(macOS)
import SwiftUI
import AppKit

@main
struct MiniRadioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = RadioModel()
    var body: some Scene {
        Window("Mini Radio", id: "player") {
            PlayerView(model: model, playback: model.playback)
                .onAppear { delegate.model = model; model.sync.setActive(true) }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("收听") {
                Button("播放 / 暂停") { model.playback.toggle() }.keyboardShortcut("p", modifiers: [.command])
                Button("随机下一站") { model.randomNext() }.keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("停止") { model.playback.stop() }
                Divider()
                Button("探索电台") { model.expanded.toggle() }.keyboardShortcut("f", modifiers: [.command])
            }
        }
        Window("数据来源与隐私", id: "privacy") { PrivacyView() }
            .windowResizability(.contentSize)
        Window("收藏与收听同步", id: "sync") { LibrarySyncView(sync: model.sync) }
            .windowResizability(.contentSize)
        MenuBarExtra {
            StatusBarPanel(model: model, playback: model.playback)
        } label: {
            StatusBarLabel(playback: model.playback)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: RadioModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        model?.sync.setActive(false)
        model?.playback.shutdown()
    }
    func applicationDidBecomeActive(_ notification: Notification) { model?.sync.synchronize() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.contains("--smoke-test") else { return }
        // A CI launch probe only. Audio playback is validated separately on a real Mac.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let window = NSApplication.shared.windows.first(where: { $0.title == "Mini Radio" && $0.isVisible }),
                  let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                let output = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("MiniRadio", isDirectory: true)
                try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try? data.write(to: output.appendingPathComponent("launch-smoke.png"))
            }
            self?.model?.playback.shutdown()
            NSApplication.shared.terminate(nil)
        }
    }
}
#else
import Foundation
@main enum UnsupportedPlatform {
    static func main() {
        FileHandle.standardError.write(Data("Mini Radio requires macOS 13 or later.\n".utf8))
        exit(1)
    }
}
#endif

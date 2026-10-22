import SwiftUI
import RadioCore

@main
struct MiniRadioIOSApp: App {
    @StateObject private var model: RadioModel
    @Environment(\.scenePhase) private var phase

    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing") {
            let identifier = ProcessInfo.processInfo.environment["MINIRADIO_UI_TEST_RUN"] ?? "preview"
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MiniRadioUITests")
                .appendingPathComponent(UUID(uuidString: identifier)?.uuidString ?? "preview")
            let testModel = RadioModel(automaticallyLoad: false, storageDirectory: folder)
            let stream = "http://127.0.0.1:18767/tone.wav"
            testModel.stations = [
                Station(id: "ui-jazz", name: "Jazz Window", url: stream, countrycode: "JP", tags: "jazz", codec: "WAV"),
                Station(id: "ui-classical", name: "Classical Morning", url: stream, countrycode: "FR", tags: "classical"),
                Station(id: "ui-ambient", name: "Ambient Nights", url: stream, countrycode: "US", tags: "ambient")
            ]
            _model = StateObject(wrappedValue: testModel)
            return
        }
        #endif
        _model = StateObject(wrappedValue: RadioModel())
    }

    var body: some Scene {
        WindowGroup {
            RadioRootView(model: model, playback: model.playback)
                .tint(Color(red: 0.76, green: 0.34, blue: 0.12))
                .onAppear { model.sync.setActive(phase == .active) }
                .onChange(of: phase) { value in
                    model.sync.setActive(value == .active)
                    if value == .active, let deadline = model.playback.sleepDeadline, deadline <= Date() {
                        model.playback.stop()
                    }
                }
        }
    }
}

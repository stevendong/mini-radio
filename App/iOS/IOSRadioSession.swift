import Foundation
import RadioCore

@MainActor
final class IOSRadioSession {
    static let shared = IOSRadioSession()
    let model: RadioModel
    private var phoneActive = false
    private var carPlaySessions: Set<String> = []

    private init() {
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
            model = testModel
            return
        }
        #endif
        model = RadioModel()
    }

    func setPhoneActive(_ active: Bool) {
        phoneActive = active
        updateActivity()
    }

    func connectCarPlay(_ identifier: String) {
        carPlaySessions.insert(identifier)
        updateActivity()
    }

    func disconnectCarPlay(_ identifier: String) {
        carPlaySessions.remove(identifier)
        updateActivity()
    }

    private func updateActivity() {
        model.sync.setActive(phoneActive || !carPlaySessions.isEmpty)
    }
}

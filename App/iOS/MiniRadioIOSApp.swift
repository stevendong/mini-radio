import SwiftUI

@main
struct MiniRadioIOSApp: App {
    @StateObject private var model: RadioModel
    @Environment(\.scenePhase) private var phase

    init() {
        _model = StateObject(wrappedValue: IOSRadioSession.shared.model)
    }

    var body: some Scene {
        WindowGroup {
            RadioRootView(model: model, playback: model.playback)
                .tint(Color(red: 0.76, green: 0.34, blue: 0.12))
                .onAppear { IOSRadioSession.shared.setPhoneActive(phase == .active) }
                .onChange(of: phase) { value in
                    IOSRadioSession.shared.setPhoneActive(value == .active)
                    if value == .active, let deadline = model.playback.sleepDeadline, deadline <= Date() {
                        model.playback.stop()
                    }
                }
        }
    }
}

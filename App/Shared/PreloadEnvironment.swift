#if os(macOS) || os(iOS)
import Foundation
import Network
import RadioCore
#if os(iOS)
import UIKit
#else
import IOKit.ps
#endif

@MainActor
final class PreloadEnvironment {
    private(set) var conditions = PreloadConditions()
    var onChange: (() -> Void)?
    private let monitor = NWPathMonitor()
    private let monitoring: Bool
    private var observers: [NSObjectProtocol] = []
    #if os(macOS)
    private var powerSource: CFRunLoopSource?
    #endif

    init(monitoring: Bool = true) {
        self.monitoring = monitoring
        guard monitoring else { return }
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        monitor.start(queue: DispatchQueue(label: "MiniRadio.PreloadNetwork"))
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        for name in [UIDevice.batteryStateDidChangeNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })
        }
        #else
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let environment = Unmanaged<PreloadEnvironment>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak environment] in environment?.refresh() }
        }
        powerSource = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        #endif
        refresh()
    }

    func refresh() {
        guard monitoring else { return }
        let path = monitor.currentPath
        // Unknown paths and cellular/hotspot fallback do not enable speculative audio.
        let wifi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            && !path.usesInterfaceType(.cellular) && !path.isExpensive && !path.isConstrained
        #if os(iOS)
        let battery = UIDevice.current.batteryState
        let externalPower = battery == .charging || battery == .full
        #else
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let source = snapshot.flatMap { IOPSGetProvidingPowerSourceType($0)?.takeUnretainedValue() as String? }
        let externalPower = source == kIOPSACPowerValue
        #endif
        update(PreloadConditions(externalPower: externalPower, wifi: wifi))
    }

    func update(_ value: PreloadConditions) {
        guard conditions != value else { return }
        conditions = value
        onChange?()
    }

    deinit {
        monitor.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        #if os(macOS)
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
        #endif
    }
}
#endif

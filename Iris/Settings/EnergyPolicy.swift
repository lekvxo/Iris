import Foundation
import Observation

@MainActor @Observable
final class EnergyPolicy {
    private(set) var thermalState: ProcessInfo.ThermalState
    @ObservationIgnored private var foregroundWindows: Set<UUID> = []
    @ObservationIgnored private let changed: (Bool) -> Void
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(changed: @escaping (Bool) -> Void) {
        // Reading thermalState enables Foundation's change notifications.
        thermalState = ProcessInfo.processInfo.thermalState
        self.changed = changed
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateThermalState(ProcessInfo.processInfo.thermalState) }
        }
        changed(false)
    }

    var isHot: Bool { thermalState == .serious || thermalState == .critical }
    var filterWorkAllowed: Bool { !foregroundWindows.isEmpty && !isHot }
    var probeInterval: Int { isHot ? 2000 : 250 }

    func setForeground(_ foreground: Bool, window: UUID) {
        if foreground { foregroundWindows.insert(window) }
        else { foregroundWindows.remove(window) }
        changed(filterWorkAllowed)
    }

    func updateThermalState(_ state: ProcessInfo.ThermalState) {
        thermalState = state
        changed(filterWorkAllowed)
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

import AppKit
import Observation

@MainActor
@Observable
final class MonitorViewModel {
    static let shared = MonitorViewModel()
    private static let intervalKey = "refreshIntervalMinutes"
    private static let soundKey = "soundEnabled"
    static let intervals = [5, 10, 20, 30, 60]

    private(set) var snapshot: HeadsetSnapshot?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    var refreshIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(refreshIntervalMinutes, forKey: Self.intervalKey)
            scheduleRefresh()
        }
    }
    var soundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: Self.soundKey)
            if !soundEnabled { soundPlayer.stopAll() }
        }
    }

    private var refreshTask: Task<Void, Never>?
    private var started = false
    private var executablePath: String?
    private let soundPlayer = SoundPlayer()

    private init() {
        let stored = UserDefaults.standard.integer(forKey: Self.intervalKey)
        refreshIntervalMinutes = Self.intervals.contains(stored) ? stored : 10
        soundEnabled = UserDefaults.standard.object(forKey: Self.soundKey) as? Bool ?? true
    }

    var isConnected: Bool { snapshot?.connectedDevice != nil }

    var iconAssetName: String {
        guard let device = snapshot?.connectedDevice else { return "Disconnected" }
        guard let level = device.batteryLevel else { return "Connected" }
        switch level {
        case ..<20: return "BatteryLow"
        case ..<50: return "BatteryMedium"
        case ...80: return "BatteryHigh"
        default: return "BatteryFull"
        }
    }

    var accessibilityText: String {
        guard let device = snapshot?.connectedDevice else {
            return String(localized: "No headset found")
        }
        guard let battery = device.batteryLevel else {
            return String(localized: "Battery: retrieving information")
        }
        return String(format: String(localized: "Battery: %d%%"), battery)
    }

    func start() {
        guard !started else { return }
        started = true
        executablePath = HeadsetControlService.executablePath()
        if executablePath == nil {
            showMissingExecutableAlert()
            return
        }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        guard let path = executablePath ?? HeadsetControlService.executablePath() else {
            errorMessage = String(localized: "HeadsetControl is unavailable.")
            showMissingExecutableAlert()
            return
        }
        executablePath = path
        isRefreshing = true
        defer {
            isRefreshing = false
            scheduleRefresh()
        }
        do {
            let wasConnected = isConnected
            let previousBatteryLevel = snapshot?.connectedDevice?.batteryLevel
            let newSnapshot = try await HeadsetControlService.fetch(at: path)
            snapshot = newSnapshot
            errorMessage = nil
            if soundEnabled, let device = newSnapshot.connectedDevice {
                if !wasConnected { soundPlayer.play("detection") }
                if let level = device.batteryLevel {
                    if !wasConnected || previousBatteryLevel != level {
                        soundPlayer.play("info")
                    }
                    if level <= 20 { soundPlayer.play("low") }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        guard started, executablePath != nil else { return }
        let needsBatteryRetry = snapshot?.connectedDevice?.batteryLevel == nil && isConnected
        let delaySeconds = needsBatteryRetry ? 60 : refreshIntervalMinutes * 60
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func showMissingExecutableAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "HeadsetControl is unavailable")
        alert.informativeText = String(localized: "Install headsetcontrol with Homebrew, then reopen Headphone monitor.")
        alert.addButton(withTitle: String(localized: "OK"))
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

@MainActor
private final class SoundPlayer {
    private var sounds: [String: NSSound] = [:]

    func play(_ name: String) {
        if sounds[name] == nil,
           let url = Bundle.main.url(forResource: name, withExtension: "wav") {
            sounds[name] = NSSound(contentsOf: url, byReference: false)
        }
        guard let sound = sounds[name] else { return }
        sound.stop()
        sound.play()
    }

    func stopAll() {
        sounds.values.forEach { $0.stop() }
    }
}

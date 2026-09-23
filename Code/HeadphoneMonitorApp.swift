import AppKit
import SwiftUI

@main
struct HeadphoneMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = MonitorViewModel.shared

    var body: some Scene {
        MenuBarExtra {
            MonitorMenuView(model: model)
        } label: {
            Image(model.iconAssetName)
                .accessibilityLabel(model.accessibilityText)
        }
        .menuBarExtraStyle(.menu)

        Window("Headset information", id: "headset-information") {
            HeadsetInformationView(model: model)
        }
        .defaultSize(width: 620, height: 580)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MonitorViewModel.shared.start()
    }
}

import AppKit
import SwiftUI

struct MonitorMenuView: View {
    @Bindable var model: MonitorViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Headset information") {
            openWindow(id: "headset-information")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Menu("Settings") {
            Picker("Refresh information every", selection: $model.refreshIntervalMinutes) {
                ForEach(MonitorViewModel.intervals, id: \.self) { minutes in
                    Text(intervalText(minutes)).tag(minutes)
                }
            }
            .pickerStyle(.menu)
            Toggle("Sound", isOn: $model.soundEnabled)
        }

        Button("Refresh information") {
            Task { await model.refresh() }
        }
        .disabled(model.isRefreshing)

        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private func intervalText(_ minutes: Int) -> String {
        String(format: String(localized: "%d minutes"), minutes)
    }
}

struct HeadsetInformationView: View {
    @Bindable var model: MonitorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Headset information")
                        .font(.title2.bold())
                    Spacer()
                    if model.isRefreshing { ProgressView() }
                    Button("Refresh information") {
                        Task { await model.refresh() }
                    }
                    .disabled(model.isRefreshing)
                }

                Text(model.accessibilityText)
                    .font(.headline)

                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                }

                if let snapshot = model.snapshot {
                    if let device = snapshot.connectedDevice {
                        LabeledContent("Device", value: device.name)
                        if let product = device.product {
                            LabeledContent("Product", value: product)
                        }
                        if let vendor = device.vendor {
                            LabeledContent("Vendor", value: vendor)
                        }
                    }
                    LabeledContent("Last updated", value: snapshot.updatedAt.formatted())
                    Text("Complete HeadsetControl output")
                        .font(.headline)
                    Text(snapshot.output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                } else if !model.isRefreshing {
                    Text("No headset information available")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

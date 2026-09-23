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

        Menu("Headset settings") {
            if let device = model.snapshot?.connectedDevice {
                if device.capabilities.contains(HeadsetOption.sidetone.rawValue) {
                    numericPicker("Microphone monitoring", option: .sidetone, values: [0, 32, 64, 96, 128])
                }
                if device.capabilities.contains(HeadsetOption.inactiveTime.rawValue) {
                    Picker("Inactivity time", selection: settingSelection(.inactiveTime)) {
                        Text("Never").tag(0 as Int?)
                        ForEach([5, 15, 30, 45, 60, 90], id: \.self) { minutes in
                            Text(intervalText(minutes)).tag(minutes as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if device.capabilities.contains(HeadsetOption.equalizerPreset.rawValue),
                   !device.equalizerPresets.isEmpty {
                    Picker("Preset", selection: settingSelection(.equalizerPreset)) {
                        ForEach(Array(device.equalizerPresets.enumerated()), id: \.offset) { index, name in
                            Text(presetText(name)).tag(index as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if device.capabilities.contains(HeadsetOption.microphoneMuteLEDBrightness.rawValue) {
                    Picker("Muted microphone LED", selection: settingSelection(.microphoneMuteLEDBrightness)) {
                        Text("Off").tag(0 as Int?)
                        Text("Low").tag(1 as Int?)
                        Text("Medium").tag(2 as Int?)
                        Text("High").tag(3 as Int?)
                    }
                    .pickerStyle(.menu)
                }
                if device.capabilities.contains(HeadsetOption.microphoneVolume.rawValue) {
                    numericPicker("Microphone gain", option: .microphoneVolume, values: [0, 32, 64, 96, 128])
                }
                if device.capabilities.contains(HeadsetOption.volumeLimiter.rawValue) {
                    Picker("Volume limiter", selection: settingSelection(.volumeLimiter)) {
                        Text("Enable").tag(1 as Int?)
                        Text("Disable").tag(0 as Int?)
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .disabled(!model.isConnected || model.isApplyingSetting)

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

    private func settingSelection(_ option: HeadsetOption) -> Binding<Int?> {
        Binding(
            get: { model.selectedValue(for: option) },
            set: { value in
                guard let value else { return }
                Task { await model.set(option, to: value) }
            }
        )
    }

    private func numericPicker(_ title: LocalizedStringKey, option: HeadsetOption, values: [Int]) -> some View {
        Picker(title, selection: settingSelection(option)) {
            ForEach(values, id: \.self) { value in
                Text("\(value)").tag(value as Int?)
            }
        }
        .pickerStyle(.menu)
    }

    private func presetText(_ name: String) -> String {
        switch name.lowercased() {
        case "flat": String(localized: "Flat")
        case "bass": String(localized: "Bass")
        case "focus": String(localized: "Focus")
        case "smiley": String(localized: "Smiley")
        default: name
        }
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

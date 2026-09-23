import Foundation

struct HeadsetDevice: Sendable, Identifiable {
    let id: String
    let name: String
    let product: String?
    let vendor: String?
    let batteryLevel: Int?
    let connected: Bool
    let capabilities: Set<String>
    let equalizerPresets: [String]
    let selectionID: String?
}

struct HeadsetSnapshot: Sendable {
    let devices: [HeadsetDevice]
    let output: String
    let updatedAt: Date

    var connectedDevice: HeadsetDevice? { devices.first(where: \.connected) }
}

enum HeadsetControlError: LocalizedError {
    case unavailable
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "HeadsetControl is unavailable.")
        case .timedOut: String(localized: "HeadsetControl timed out.")
        case .failed(let message): message
        }
    }
}

enum HeadsetControlService {
    static func executablePath() -> String? {
        let paths = [
            "/opt/homebrew/bin/headsetcontrol",
            "/usr/local/bin/headsetcontrol"
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { "\($0)/headsetcontrol" }
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    static func fetch(at path: String) async throws -> HeadsetSnapshot {
        let output = try await Task.detached(priority: .utility) {
            try run(path: path, arguments: ["-b", "-o", "json"])
        }.value
        if let snapshot = parseJSON(output) { return snapshot }

        // Older releases can provide only human-readable battery output.
        let fallback = try await Task.detached(priority: .utility) {
            try run(path: path, arguments: ["-b"])
        }.value
        return parseText(fallback)
    }

    static func set(_ option: HeadsetOption, to value: Int, for device: HeadsetDevice, at path: String) async throws {
        var arguments: [String] = []
        if let selectionID = device.selectionID {
            arguments += ["-d", selectionID]
        }
        arguments += [option.argument, String(value)]
        _ = try await Task.detached(priority: .utility) {
            try run(path: path, arguments: arguments, requireSuccess: true)
        }.value
    }

    private static func run(path: String, arguments: [String], requireSuccess: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do { try process.run() }
        catch { throw HeadsetControlError.failed(error.localizedDescription) }

        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let wasTimedOut = timeout.isCancelled == false && process.terminationStatus == 15
        timeout.cancel()
        if wasTimedOut { throw HeadsetControlError.timedOut }
        if requireSuccess && process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HeadsetControlError.failed(detail.flatMap { $0.isEmpty ? nil : $0 }
                ?? String(localized: "HeadsetControl could not change this setting."))
        }
        guard let text = String(data: data, encoding: .utf8), requireSuccess || !text.isEmpty else {
            throw HeadsetControlError.failed(String(localized: "HeadsetControl returned no information."))
        }
        return text
    }

    private static func parseJSON(_ output: String) -> HeadsetSnapshot? {
        guard let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceObjects = root["devices"] as? [[String: Any]] else { return nil }
        let devices = deviceObjects.enumerated().map { index, item -> HeadsetDevice in
            let battery = item["battery"] as? [String: Any] ?? [:]
            let level = (battery["level"] as? NSNumber)?.intValue
            let validLevel = level.flatMap { (0...100).contains($0) ? $0 : nil }
            let status = (item["status"] as? String ?? "").lowercased()
            let errors = item["errors"] as? [String: String] ?? [:]
            let inaccessible = errors.values.contains {
                $0.localizedCaseInsensitiveContains("could not open device")
            }
            let connected = !["disconnected", "unsupported", "error"].contains(status)
                && (!inaccessible || validLevel != nil)
            let vendorID = item["id_vendor"] as? String
            let productID = item["id_product"] as? String
            let selectionID = vendorID.flatMap { vendor in
                productID.map { product in
                    "\(vendor):\(product)"
                }
            }
            let capabilities = Set(item["capabilities"] as? [String] ?? [])
            let presetCount = item["equalizer_presets_count"] as? Int ?? 0
            let presetNames = orderedPresetNames(in: output, count: presetCount)
            return HeadsetDevice(
                id: "\(item["id_vendor"] ?? "")-\(item["id_product"] ?? "")-\(index)",
                name: item["device"] as? String ?? item["product"] as? String ?? String(localized: "Headset"),
                product: item["product"] as? String,
                vendor: item["vendor"] as? String,
                batteryLevel: validLevel,
                connected: connected,
                capabilities: capabilities,
                equalizerPresets: presetNames,
                selectionID: selectionID
            )
        }
        return HeadsetSnapshot(devices: devices, output: output, updatedAt: Date())
    }

    private static func parseText(_ output: String) -> HeadsetSnapshot {
        let range = output.range(of: #"\bBattery(?: level)?\s*:\s*\d{1,3}\s*%?"#, options: [.regularExpression, .caseInsensitive])
            ?? output.range(of: #"\b\d{1,3}\s*%"#, options: .regularExpression)
        let level = range.flatMap { match -> Int? in
            let digits = output[match].filter(\.isNumber)
            guard let number = Int(digits), (0...100).contains(number) else { return nil }
            return number
        }
        let detected = !output.localizedCaseInsensitiveContains("no supported device")
            && (output.range(of: #"found [1-9]\d* supported device"#, options: [.regularExpression, .caseInsensitive]) != nil || level != nil)
        let devices = detected ? [HeadsetDevice(
            id: "legacy", name: String(localized: "Headset"), product: nil, vendor: nil,
            batteryLevel: level, connected: true,
            capabilities: [], equalizerPresets: [], selectionID: nil
        )] : []
        return HeadsetSnapshot(devices: devices, output: output, updatedAt: Date())
    }

    private static func orderedPresetNames(in output: String, count: Int) -> [String] {
        guard count > 0,
              let start = output.range(of: #""equalizer_presets"\s*:\s*\{"#, options: .regularExpression),
              let expression = try? NSRegularExpression(pattern: #""([^"\\]+)"\s*:\s*\["#) else { return [] }
        let remainder = String(output[start.upperBound...])
        let range = NSRange(remainder.startIndex..<remainder.endIndex, in: remainder)
        return expression.matches(in: remainder, range: range).prefix(count).compactMap { match in
            Range(match.range(at: 1), in: remainder).map { String(remainder[$0]) }
        }
    }
}

enum HeadsetOption: String, Sendable {
    case sidetone = "CAP_SIDETONE"
    case inactiveTime = "CAP_INACTIVE_TIME"
    case equalizerPreset = "CAP_EQUALIZER_PRESET"
    case microphoneMuteLEDBrightness = "CAP_MICROPHONE_MUTE_LED_BRIGHTNESS"
    case microphoneVolume = "CAP_MICROPHONE_VOLUME"
    case volumeLimiter = "CAP_VOLUME_LIMITER"

    var argument: String {
        switch self {
        case .sidetone: "-s"
        case .inactiveTime: "-i"
        case .equalizerPreset: "-p"
        case .microphoneMuteLEDBrightness: "--microphone-mute-led-brightness"
        case .microphoneVolume: "--microphone-volume"
        case .volumeLimiter: "--volume-limiter"
        }
    }
}

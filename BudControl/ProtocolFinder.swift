import SwiftUI
import Foundation
import UIKit

enum FinderActionPreset: String, CaseIterable, Identifiable {
    case noiseControlCycle = "Noise control cycle"
    case playPause = "Play / Pause"
    case nextTrack = "Next track"
    case previousTrack = "Previous track"
    case voiceAssistant = "Voice assistant"
    case removeEarbud = "Remove an earbud"
    case insertEarbud = "Insert an earbud"
    case caseOpenClose = "Open / close case"
    case custom = "Custom action"

    var id: String { rawValue }

    var instruction: String {
        switch self {
        case .noiseControlCycle:
            return "Press and hold the RIGHT earbud touch area for about 3 seconds until the noise mode changes."
        case .playPause:
            return "Double-tap either earbud once."
        case .nextTrack:
            return "Triple-tap the RIGHT earbud once."
        case .previousTrack:
            return "Triple-tap the LEFT earbud once."
        case .voiceAssistant:
            return "Press and hold the LEFT earbud touch area for about 3 seconds."
        case .removeEarbud:
            return "Remove one earbud from your ear and leave it out for a few seconds."
        case .insertEarbud:
            return "Put one earbud back in your ear and leave it there for a few seconds."
        case .caseOpenClose:
            return "Put the earbuds in the case, then open or close the lid once."
        case .custom:
            return "Perform exactly one action, then return here and tap Analyze Changes."
        }
    }
}

enum FinderPhase: Equatable {
    case idle
    case preparing
    case baselineReady
    case capturing
    case analyzed

    var title: String {
        switch self {
        case .idle: return "Ready"
        case .preparing: return "Preparing baseline…"
        case .baselineReady: return "Baseline ready"
        case .capturing: return "Recording action"
        case .analyzed: return "Analysis complete"
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "circle"
        case .preparing: return "hourglass"
        case .baselineReady: return "checkmark.circle.fill"
        case .capturing: return "record.circle"
        case .analyzed: return "sparkles"
        }
    }
}

struct ProtocolCandidate: Identifiable, Hashable {
    let id: String
    let serviceUUID: String
    let characteristicUUID: String
    let properties: [String]
    let baselineHex: String?
    let latestHex: String
    let eventCount: Int
    let notificationCount: Int
    let uniqueValueCount: Int
    let changedByteIndexes: [Int]
    let score: Int
    let tags: [String]

    var changed: Bool {
        guard let baselineHex else { return false }
        return normalize(baselineHex) != normalize(latestHex)
    }

    var scoreLabel: String {
        switch score {
        case 25...: return "Very strong"
        case 16..<25: return "Strong"
        case 9..<16: return "Possible"
        default: return "Weak"
        }
    }

    var diffText: String {
        guard !changedByteIndexes.isEmpty else { return changed ? "Value changed" : "No byte delta" }
        return changedByteIndexes.map { "#\($0)" }.joined(separator: ", ")
    }

    private func normalize(_ input: String) -> String {
        input.replacingOccurrences(of: " ", with: "").uppercased()
    }
}

struct SavedProtocolObservation: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let actionLabel: String
    let serviceUUID: String
    let characteristicUUID: String
    let baselineHex: String?
    let latestHex: String
    let changedByteIndexes: [Int]
    let properties: [String]
    let note: String
}

final class ProtocolObservationStore: ObservableObject {
    @Published private(set) var observations: [SavedProtocolObservation] = []

    private let defaults: UserDefaults
    private let key = "BudControl.ProtocolObservations.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func save(actionLabel: String, candidate: ProtocolCandidate, note: String = "Guided Protocol Finder capture") {
        let item = SavedProtocolObservation(
            id: UUID(),
            createdAt: Date(),
            actionLabel: actionLabel,
            serviceUUID: candidate.serviceUUID,
            characteristicUUID: candidate.characteristicUUID,
            baselineHex: candidate.baselineHex,
            latestHex: candidate.latestHex,
            changedByteIndexes: candidate.changedByteIndexes,
            properties: candidate.properties,
            note: note
        )
        observations.insert(item, at: 0)
        if observations.count > 100 {
            observations.removeLast(observations.count - 100)
        }
        persist()
    }

    func remove(_ item: SavedProtocolObservation) {
        observations.removeAll { $0.id == item.id }
        persist()
    }

    func removeAll() {
        observations.removeAll()
        persist()
    }

    func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["BudControl Protocol Finder observations", ""]
        for item in observations {
            lines.append("Action: \(item.actionLabel)")
            lines.append("Time: \(formatter.string(from: item.createdAt))")
            lines.append("Service: \(item.serviceUUID)")
            lines.append("Characteristic: \(item.characteristicUUID)")
            lines.append("Properties: \(item.properties.joined(separator: ", "))")
            lines.append("Before: \(item.baselineHex ?? "unknown")")
            lines.append("After: \(item.latestHex)")
            lines.append("Changed bytes: \(item.changedByteIndexes.map(String.init).joined(separator: ", "))")
            lines.append("Note: \(item.note)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedProtocolObservation].self, from: data) else { return }
        observations = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(observations) else { return }
        defaults.set(data, forKey: key)
    }
}

enum ProtocolCaptureAnalyzer {
    static func snapshot(services: [GATTServiceInfo]) -> [String: String] {
        var result: [String: String] = [:]
        for service in services {
            for characteristic in service.characteristics {
                if let value = characteristic.lastValueHex, !value.isEmpty {
                    result[characteristic.id] = value
                }
            }
        }
        return result
    }

    static func analyze(
        events: [ProtocolEvent],
        since startedAt: Date,
        baseline: [String: String],
        services: [GATTServiceInfo]
    ) -> [ProtocolCandidate] {
        let relevant = events.filter { event in
            event.timestamp >= startedAt &&
            (event.category == "notification/value" || event.category == "read/value") &&
            event.serviceUUID != nil && event.characteristicUUID != nil &&
            !(event.valueHex ?? "").isEmpty
        }

        let grouped = Dictionary(grouping: relevant) { event -> String in
            let service = normalizeUUID(event.serviceUUID ?? "")
            let characteristic = normalizeUUID(event.characteristicUUID ?? "")
            return "\(service)|\(characteristic)"
        }

        var infoByID: [String: GATTCharacteristicInfo] = [:]
        for service in services {
            for characteristic in service.characteristics {
                infoByID[characteristic.id] = characteristic
            }
        }

        var candidates: [ProtocolCandidate] = []
        for (id, groupedEvents) in grouped {
            guard let lastEvent = groupedEvents.last,
                  let serviceUUID = lastEvent.serviceUUID,
                  let characteristicUUID = lastEvent.characteristicUUID,
                  let latestHex = lastEvent.valueHex else { continue }

            let info = infoByID[id]
            let properties = info?.properties ?? []
            let values = groupedEvents.compactMap(\.valueHex)
            let uniqueValues = Set(values.map(normalizeHex))
            let notificationCount = groupedEvents.filter { $0.category == "notification/value" }.count
            let baselineHex = baseline[id]
            let changedIndexes = byteDiff(before: baselineHex, after: latestHex)
            let didChange = baselineHex.map { normalizeHex($0) != normalizeHex(latestHex) } ?? false

            var score = 0
            score += min(notificationCount * 6, 24)
            if didChange { score += 12 }
            score += min(changedIndexes.count * 2, 10)
            if uniqueValues.count > 1 { score += min(uniqueValues.count * 2, 8) }
            if properties.contains("notify") || properties.contains("indicate") { score += 4 }
            if properties.contains("write") || properties.contains("writeWithoutResponse") { score += 3 }
            if isVendorSpecific(serviceUUID) { score += 3 }
            if groupedEvents.allSatisfy({ $0.category == "read/value" }) && !didChange { score -= 6 }
            score = max(0, score)

            var tags: [String] = []
            if notificationCount > 0 { tags.append("Notification") }
            if didChange { tags.append("Changed") }
            if uniqueValues.count > 1 { tags.append("Multiple values") }
            if properties.contains("write") || properties.contains("writeWithoutResponse") { tags.append("Writable") }
            if isVendorSpecific(serviceUUID) { tags.append("Vendor") }
            if looksBatteryLike(characteristicUUID: characteristicUUID, valueHex: latestHex) { tags.append("Battery-like") }
            if isObservedMotoBudsService(serviceUUID) { tags.append("Moto service seen") }

            candidates.append(
                ProtocolCandidate(
                    id: id,
                    serviceUUID: normalizeUUID(serviceUUID),
                    characteristicUUID: normalizeUUID(characteristicUUID),
                    properties: properties,
                    baselineHex: baselineHex,
                    latestHex: latestHex,
                    eventCount: groupedEvents.count,
                    notificationCount: notificationCount,
                    uniqueValueCount: uniqueValues.count,
                    changedByteIndexes: changedIndexes,
                    score: score,
                    tags: tags
                )
            )
        }

        return candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.notificationCount != $1.notificationCount { return $0.notificationCount > $1.notificationCount }
            return $0.characteristicUUID < $1.characteristicUUID
        }
    }

    static func report(actionLabel: String, candidates: [ProtocolCandidate]) -> String {
        var lines = [
            "BudControl Protocol Finder report",
            "Action: \(actionLabel)",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "Candidates: \(candidates.count)",
            ""
        ]
        for (index, candidate) in candidates.enumerated() {
            lines.append("#\(index + 1) \(candidate.scoreLabel) (score \(candidate.score))")
            lines.append("Service: \(candidate.serviceUUID)")
            lines.append("Characteristic: \(candidate.characteristicUUID)")
            lines.append("Properties: \(candidate.properties.joined(separator: ", "))")
            lines.append("Before: \(candidate.baselineHex ?? "unknown")")
            lines.append("After: \(candidate.latestHex)")
            lines.append("Changed byte indexes: \(candidate.changedByteIndexes.map(String.init).joined(separator: ", "))")
            lines.append("Events: \(candidate.eventCount), notifications: \(candidate.notificationCount), unique values: \(candidate.uniqueValueCount)")
            lines.append("Tags: \(candidate.tags.joined(separator: ", "))")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func byteDiff(before: String?, after: String) -> [Int] {
        guard let before,
              let beforeBytes = bytes(from: before),
              let afterBytes = bytes(from: after) else { return [] }
        let maxCount = max(beforeBytes.count, afterBytes.count)
        var result: [Int] = []
        for index in 0..<maxCount {
            let lhs: UInt8? = index < beforeBytes.count ? beforeBytes[index] : nil
            let rhs: UInt8? = index < afterBytes.count ? afterBytes[index] : nil
            if lhs != rhs { result.append(index) }
        }
        return result
    }

    private static func bytes(from hex: String) -> [UInt8]? {
        let cleaned = normalizeHex(hex)
        guard !cleaned.isEmpty, cleaned.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    private static func normalizeHex(_ input: String) -> String {
        input.uppercased().filter { $0.isHexDigit }
    }

    private static func normalizeUUID(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func isVendorSpecific(_ serviceUUID: String) -> Bool {
        let normalized = normalizeUUID(serviceUUID)
        let standardServices: Set<String> = ["1800", "1801", "180A", "180F", "1812", "1844", "1845", "1846", "184E"]
        return !standardServices.contains(normalized)
    }

    private static func isObservedMotoBudsService(_ serviceUUID: String) -> Bool {
        let normalized = normalizeUUID(serviceUUID)
        let observed: Set<String> = [
            "FE2C",
            "FC9D",
            "66666666-6666-6666-6666-666666666666",
            "FC9D9FE0-4899-11EE-BE56-0242AC120002"
        ]
        return observed.contains(normalized)
    }

    private static func looksBatteryLike(characteristicUUID: String, valueHex: String) -> Bool {
        let normalizedCharacteristic = normalizeUUID(characteristicUUID)
        guard normalizedCharacteristic == "FC9D0004-7DC1-4D3A-B13E-F9087FC8EDDB",
              let values = bytes(from: valueHex), values.count == 4 else { return false }
        return values[1...3].allSatisfy { $0 <= 100 }
    }
}

struct ProtocolFinderView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @StateObject private var observationStore = ProtocolObservationStore()

    @State private var selectedPreset: FinderActionPreset = .noiseControlCycle
    @State private var customAction = ""
    @State private var phase: FinderPhase = .idle
    @State private var baseline: [String: String] = [:]
    @State private var captureStartedAt: Date?
    @State private var candidates: [ProtocolCandidate] = []
    @State private var hideWeakCandidates = true
    @State private var showingSaved = false

    private var actionLabel: String {
        if selectedPreset == .custom {
            let trimmed = customAction.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Custom action" : trimmed
        }
        return selectedPreset.rawValue
    }

    private var visibleCandidates: [ProtocolCandidate] {
        hideWeakCandidates ? candidates.filter { $0.score >= 9 || $0.changed || $0.notificationCount > 0 } : candidates
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.accentColor.opacity(0.14))
                                .frame(width: 54, height: 54)
                            Image(systemName: "scope")
                                .font(.title2.bold())
                                .foregroundStyle(Color.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Protocol Finder")
                                .font(.title2.bold())
                            Text("Capture one action. See what changed.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Finder filters out service scans, RSSI, and subscription chatter, then ranks the GATT characteristics most related to the action you performed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
            }

            Section {
                Picker("Action", selection: $selectedPreset) {
                    ForEach(FinderActionPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                if selectedPreset == .custom {
                    TextField("Describe one action", text: $customAction)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label(phase.title, systemImage: phase.symbol)
                        .font(.headline)
                    Text(selectedPreset.instruction)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Choose one test")
            } footer: {
                Text("Change only one thing per capture. Repeating the same test two or three times makes a candidate much easier to trust.")
            }

            Section {
                Button {
                    prepareBaseline()
                } label: {
                    Label("1. Prepare Baseline", systemImage: "camera.metering.center.weighted")
                }
                .disabled(phase == .preparing || phase == .capturing)

                Button {
                    startCapture()
                } label: {
                    Label("2. Start Action Capture", systemImage: "record.circle")
                }
                .disabled(phase != .baselineReady && phase != .analyzed)

                Button {
                    analyzeCapture()
                } label: {
                    Label("3. Analyze Changes", systemImage: "wand.and.stars")
                }
                .disabled(phase != .capturing)
            } header: {
                Text("Guided capture")
            } footer: {
                if phase == .capturing {
                    Text("Perform the selected earbud action now. Wait about three seconds, then tap Analyze Changes.")
                } else {
                    Text("Baseline records the current characteristic values. The action capture then compares everything that arrives afterward.")
                }
            }

            if phase == .analyzed {
                Section {
                    Toggle("Hide weak / unchanged results", isOn: $hideWeakCandidates)
                    LabeledContent("Candidates found", value: "\(visibleCandidates.count)")
                    if candidates.isEmpty {
                        Text("No characteristic values were captured during this action. Try the test again and wait a little longer before analyzing.")
                            .foregroundStyle(.secondary)
                    } else if visibleCandidates.isEmpty {
                        Text("Only low-signal results were found. Turn off the filter above to inspect them.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleCandidates.prefix(12)) { candidate in
                            NavigationLink {
                                ProtocolCandidateDetailView(
                                    actionLabel: actionLabel,
                                    candidate: candidate,
                                    observationStore: observationStore
                                )
                            } label: {
                                ProtocolCandidateRow(candidate: candidate)
                            }
                        }
                    }
                    Button("Copy Finder Report") {
                        UIPasteboard.general.string = ProtocolCaptureAnalyzer.report(actionLabel: actionLabel, candidates: visibleCandidates)
                        bluetooth.message = "Protocol Finder report copied."
                    }
                    .disabled(visibleCandidates.isEmpty)

                    Button("Repeat This Test") {
                        prepareBaseline()
                    }
                } header: {
                    Text("Ranked results")
                } footer: {
                    Text("A high score means the characteristic changed or notified near your action. It does not automatically prove that it is the write-command channel.")
                }
            }

            Section {
                LabeledContent("Services", value: "\(bluetooth.discoveredServices.count)")
                LabeledContent("Characteristics", value: "\(bluetooth.characteristicCount)")
                LabeledContent("Raw events", value: "\(bluetooth.protocolEvents.count)")
                Button("Refresh GATT Values") { bluetooth.refreshStatus() }
                Button("Rediscover Services") { bluetooth.rediscoverAllServices() }
            } header: {
                Text("Connection")
            } footer: {
                Text("Moto-service hints are based only on service UUIDs already observed from this Moto Buds+ connection. Their exact meanings remain unverified until repeated captures support them.")
            }

            Section {
                if observationStore.observations.isEmpty {
                    Text("No observations saved yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(observationStore.observations.prefix(5)) { observation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(observation.actionLabel)
                                .font(.subheadline.bold())
                            Text(observation.characteristicUUID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text("After: \(observation.latestHex)")
                                .font(.caption.monospaced())
                                .lineLimit(1)
                        }
                    }
                }
                Button("View Saved Observations") { showingSaved = true }
                    .disabled(observationStore.observations.isEmpty)
                Button("Copy Saved Observations") {
                    UIPasteboard.general.string = observationStore.exportText()
                    bluetooth.message = "Saved observations copied."
                }
                .disabled(observationStore.observations.isEmpty)
            } header: {
                Text("Saved observations")
            } footer: {
                Text("Save repeatable before/after patterns here. Verified write commands remain separate from observed status events.")
            }

            Section {
                NavigationLink {
                    ProtocolLabView()
                } label: {
                    Label("Open Advanced GATT Lab", systemImage: "wave.3.right.circle")
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Use the raw lab only when you need individual characteristics, complete event logs, or a verified one-shot write.")
            }
        }
        .navigationTitle("Finder")
        .sheet(isPresented: $showingSaved) {
            NavigationStack {
                SavedObservationsView(store: observationStore)
            }
        }
    }

    private func prepareBaseline() {
        phase = .preparing
        candidates = []
        captureStartedAt = nil
        bluetooth.refreshStatus()
        bluetooth.addProtocolMarker("FINDER baseline requested: \(actionLabel)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            baseline = ProtocolCaptureAnalyzer.snapshot(services: bluetooth.discoveredServices)
            phase = .baselineReady
            bluetooth.addProtocolMarker("FINDER baseline ready: \(baseline.count) values")
        }
    }

    private func startCapture() {
        candidates = []
        captureStartedAt = Date()
        phase = .capturing
        bluetooth.addProtocolMarker("FINDER action start: \(actionLabel)")
    }

    private func analyzeCapture() {
        guard let captureStartedAt else { return }
        candidates = ProtocolCaptureAnalyzer.analyze(
            events: bluetooth.protocolEvents,
            since: captureStartedAt,
            baseline: baseline,
            services: bluetooth.discoveredServices
        )
        phase = .analyzed
        bluetooth.addProtocolMarker("FINDER analyzed \(actionLabel): \(candidates.count) candidates")
    }
}

private struct ProtocolCandidateRow: View {
    let candidate: ProtocolCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(candidate.scoreLabel)
                    .font(.subheadline.bold())
                Spacer()
                Text("\(candidate.score)")
                    .font(.caption.bold().monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            Text(candidate.characteristicUUID)
                .font(.caption.monospaced())
                .lineLimit(1)
            Text(candidate.serviceUUID)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                ForEach(candidate.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }
            if candidate.changed {
                Text("Changed bytes: \(candidate.diffText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if candidate.notificationCount > 0 {
                Text("\(candidate.notificationCount) notification event\(candidate.notificationCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ProtocolCandidateDetailView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    let actionLabel: String
    let candidate: ProtocolCandidate
    @ObservedObject var observationStore: ProtocolObservationStore

    @State private var note = "Repeated capture from my own earbuds"

    var body: some View {
        Form {
            Section("Candidate") {
                LabeledContent("Confidence", value: candidate.scoreLabel)
                LabeledContent("Score", value: "\(candidate.score)")
                LabeledContent("Events", value: "\(candidate.eventCount)")
                LabeledContent("Notifications", value: "\(candidate.notificationCount)")
                LabeledContent("Unique values", value: "\(candidate.uniqueValueCount)")
            }

            Section("Identity") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Service")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(candidate.serviceUUID)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Characteristic")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(candidate.characteristicUUID)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                Text(candidate.properties.joined(separator: ", "))
                    .font(.footnote.monospaced())
            }

            Section("Before / after") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Baseline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(candidate.baselineHex ?? "No baseline value")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("After action")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(candidate.latestHex)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Changed byte indexes", value: candidate.diffText)
            }

            if !candidate.tags.isEmpty {
                Section("Why it ranked") {
                    ForEach(candidate.tags, id: \.self) { tag in
                        Label(tag, systemImage: tagSymbol(tag))
                    }
                }
            }

            Section {
                TextField("Evidence note", text: $note, axis: .vertical)
                Button("Save as Observation") {
                    observationStore.save(actionLabel: actionLabel, candidate: candidate, note: note)
                    bluetooth.message = "Observation saved. Repeat the test to confirm the same pattern."
                }
                Button("Copy Candidate") {
                    UIPasteboard.general.string = ProtocolCaptureAnalyzer.report(actionLabel: actionLabel, candidates: [candidate])
                    bluetooth.message = "Candidate copied."
                }
                if candidate.properties.contains("read") {
                    Button("Read Characteristic Again") {
                        bluetooth.readCharacteristic(id: candidate.id)
                    }
                }
            } header: {
                Text("Actions")
            } footer: {
                Text("Observed notifications and status changes are evidence, not automatically a control command. Use Advanced GATT Lab only after you have a verified write payload.")
            }
        }
        .navigationTitle("Candidate")
    }

    private func tagSymbol(_ tag: String) -> String {
        switch tag {
        case "Notification": return "bell.badge"
        case "Changed": return "arrow.left.arrow.right"
        case "Multiple values": return "square.stack.3d.up"
        case "Writable": return "pencil.line"
        case "Battery-like": return "battery.100"
        case "Moto service seen": return "earbuds"
        default: return "shippingbox"
        }
    }
}

private struct SavedObservationsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ProtocolObservationStore

    var body: some View {
        List {
            if store.observations.isEmpty {
                Text("No saved observations.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.observations) { observation in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(observation.actionLabel)
                            .font(.headline)
                        Text(observation.characteristicUUID)
                            .font(.caption.monospaced())
                        Text("Before: \(observation.baselineHex ?? "unknown")")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("After: \(observation.latestHex)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.remove(observation) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Observations")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            if !store.observations.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy") {
                        UIPasteboard.general.string = store.exportText()
                    }
                }
            }
        }
    }
}

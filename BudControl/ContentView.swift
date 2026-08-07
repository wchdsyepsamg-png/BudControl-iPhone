import SwiftUI
import UIKit
import Foundation

struct ContentView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager

    var body: some View {
        Group {
            if bluetooth.isConnected {
                MainTabsView()
            } else {
                NavigationStack { DiscoveryView() }
            }
        }
        .alert("BudControl", isPresented: messageBinding) {
            Button("OK", role: .cancel) { bluetooth.message = nil }
        } message: {
            Text(bluetooth.message ?? "")
        }
    }

    private var messageBinding: Binding<Bool> {
        Binding(
            get: { bluetooth.message != nil },
            set: { if !$0 { bluetooth.message = nil } }
        )
    }
}

private struct MainTabsView: View {
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
            NavigationStack { SoundView() }
                .tabItem { Label("Sound", systemImage: "waveform") }
            NavigationStack { ControlsView() }
                .tabItem { Label("Controls", systemImage: "hand.tap.fill") }
            NavigationStack { DeviceView() }
                .tabItem { Label("Device", systemImage: "earbuds") }
            NavigationStack { ProtocolFinderView() }
                .tabItem { Label("Finder", systemImage: "scope") }
        }
    }
}

private struct DiscoveryView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var preferences: AppPreferences

    private var visibleDevices: [EarbudDevice] {
        bluetooth.visibleDevices(showAll: preferences.showAllDevices)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.24), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()

            List {
                Section {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .frame(width: 118, height: 118)
                            Image(systemName: "earbuds")
                                .font(.system(size: 58, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        Text("BudControl")
                            .font(.largeTitle.bold())
                        Text(bluetooth.bluetoothState)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text("Pair your earbuds in iPhone Settings first, then scan for their Bluetooth Low Energy companion service.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .listRowBackground(Color.clear)
                }

                Section {
                    if let remembered = bluetooth.rememberedDeviceName {
                        Button {
                            impact(preferences)
                            bluetooth.reconnectRememberedDevice()
                        } label: {
                            Label("Reconnect to \(remembered)", systemImage: "arrow.clockwise.circle.fill")
                                .frame(maxWidth: .infinity)
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        impact(preferences)
                        bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
                    } label: {
                        Label(
                            bluetooth.isScanning ? "Stop Scanning" : "Scan for Earbuds",
                            systemImage: bluetooth.isScanning ? "stop.circle.fill" : "dot.radiowaves.left.and.right"
                        )
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)

                    Toggle("Show all Bluetooth LE devices", isOn: $preferences.showAllDevices)
                } footer: {
                    Text("iOS may show the media-audio connection and the control connection as separate Bluetooth roles.")
                }

                if !visibleDevices.isEmpty {
                    Section("Nearby devices") {
                        ForEach(visibleDevices) { device in
                            Button {
                                impact(preferences)
                                bluetooth.connect(to: device)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: device.isLikelyMotoBuds ? "earbuds" : "dot.radiowaves.left.and.right")
                                        .frame(width: 34, height: 34)
                                        .background(Color.accentColor.opacity(0.12))
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(device.name)
                                            .foregroundStyle(.primary)
                                            .font(.headline)
                                        Text("\(device.signalText) · \(device.rssi) dBm")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if device.isLikelyMotoBuds {
                                        Text("LIKELY MOTO")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 4)
                                            .background(Color.accentColor.opacity(0.14))
                                            .clipShape(Capsule())
                                    }
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        impact(preferences)
                        bluetooth.connectDemo()
                    } label: {
                        Label("Open Interactive Demo", systemImage: "sparkles")
                    }
                } header: {
                    Text("Explore")
                } footer: {
                    Text("Demo mode unlocks every screen without sending commands to hardware.")
                }

                Section("Compatibility") {
                    Text("Built for clean-room compatibility work with Moto Buds+ 2, Moto Buds 2, Moto Buds+, Moto Buds, and moto buds loop. Standard battery and device information work when exposed through Bluetooth LE. Manufacturer-specific controls require verified command mappings for your exact model and firmware.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Connect")
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var commandStore: VerifiedCommandStore
    @StateObject private var audioRoute = AudioRouteManager()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                heroCard
                quickModes
                scenes
                routeCard
                readinessCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("My Buds")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink { SettingsView() } label: {
                    Image(systemName: "gearshape.fill")
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bluetooth.connectedName ?? "Earbuds")
                        .font(.title2.bold())
                    Label(bluetooth.isDemoMode ? "Interactive demo" : "Connected", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(bluetooth.lastCommandStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                BatteryRing(level: bluetooth.batteryLevel)
            }

            Divider().overlay(Color.white.opacity(0.2))

            HStack(spacing: 12) {
                statusPill("Signal", bluetooth.signalStrength.map { "\($0) dBm" } ?? "—", "antenna.radiowaves.left.and.right")
                statusPill("Mode", shortMode, preferences.listeningMode.symbol)
                statusPill("EQ", preferences.eqPreset.rawValue, "slider.horizontal.3")
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.accentColor.opacity(0.25), radius: 18, y: 10)
    }

    private var quickModes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Listening mode")
                .font(.headline)
            HStack(spacing: 10) {
                ForEach(ListeningMode.allCases) { mode in
                    Button {
                        preferences.listeningMode = mode
                        perform(.forListeningMode(mode), bluetooth: bluetooth, store: commandStore, preferences: preferences)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: mode.symbol)
                                .font(.title3)
                            Text(mode == .noiseCancellation ? "ANC" : mode.rawValue)
                                .font(.caption.bold())
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(preferences.listeningMode == mode ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                        .foregroundStyle(preferences.listeningMode == mode ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var scenes: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sound scenes")
                    .font(.headline)
                Spacer()
                Text("One tap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SoundScene.allCases) { scene in
                        Button {
                            applyScene(scene)
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: scene.symbol)
                                    .font(.title2)
                                Text(scene.rawValue)
                                    .font(.headline)
                                Text(scene.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 145, alignment: .leading)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay {
                                if preferences.lastScene == scene {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color.accentColor, lineWidth: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("iPhone audio route", systemImage: "airplayaudio")
                    .font(.headline)
                Spacer()
                SystemRoutePicker()
                    .frame(width: 42, height: 32)
            }
            LabeledContent("Output", value: audioRoute.outputName)
            LabeledContent("Bluetooth media", value: audioRoute.isBluetoothAudioActive ? "Active" : "Not active")
            LabeledContent("Format", value: audioRoute.sampleRate > 0 ? "\(Int(audioRoute.sampleRate)) Hz · \(audioRoute.outputChannels) ch" : "Unavailable")
            Button("Refresh Route") {
                impact(preferences)
                audioRoute.refresh()
                bluetooth.refreshStatus()
            }
            .buttonStyle(.bordered)
        }
        .cardStyle()
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Control readiness", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                Spacer()
                Text("\(commandStore.commands.count)/\(CommandAction.allCases.count)")
                    .font(.subheadline.bold())
            }
            ProgressView(value: Double(commandStore.commands.count), total: Double(CommandAction.allCases.count))
            Text(commandStore.commands.isEmpty
                 ? "The app can scan, connect, read standard data, and capture GATT traffic now. Map verified commands in Protocol Lab to activate Motorola-specific controls."
                 : "Mapped controls send the exact command profile stored on this iPhone. Unmapped controls remain local-only.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var shortMode: String {
        switch preferences.listeningMode {
        case .noiseCancellation: return "ANC"
        case .transparency: return "Aware"
        case .off: return "Off"
        }
    }

    private func statusPill(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
            Text(value)
                .font(.caption.bold())
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .opacity(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func applyScene(_ scene: SoundScene) {
        impact(preferences)
        preferences.apply(scene: scene)
        let actions: [CommandAction?] = [
            .forListeningMode(preferences.listeningMode),
            .forPreset(preferences.eqPreset),
            preferences.lowLatencyEnabled ? .lowLatencyOn : .lowLatencyOff
        ]
        var sent = 0
        for action in actions.compactMap({ $0 }) {
            if let command = commandStore.command(for: action) {
                bluetooth.executeVerifiedCommand(command, title: action.title)
                sent += 1
            }
        }
        bluetooth.message = sent == 0
            ? "\(scene.rawValue) scene saved locally. Map its commands in Protocol Lab to control the earbuds."
            : "\(scene.rawValue) scene applied with \(sent) verified command\(sent == 1 ? "" : "s")."
    }
}

private struct SoundView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var commandStore: VerifiedCommandStore

    private let frequencies = ["60", "250", "1K", "4K", "12K"]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Listening mode")
                        .font(.headline)
                    ForEach(ListeningMode.allCases) { mode in
                        Button {
                            preferences.listeningMode = mode
                            perform(.forListeningMode(mode), bluetooth: bluetooth, store: commandStore, preferences: preferences)
                        } label: {
                            HStack {
                                Image(systemName: mode.symbol)
                                    .font(.title3)
                                    .frame(width: 38)
                                Text(mode.rawValue)
                                    .font(.headline)
                                Spacer()
                                if preferences.listeningMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(14)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Equalizer")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(EQPreset.allCases) { preset in
                                Button {
                                    preferences.eqPreset = preset
                                    if let action = CommandAction.forPreset(preset) {
                                        perform(action, bluetooth: bluetooth, store: commandStore, preferences: preferences)
                                    } else {
                                        bluetooth.message = "Custom EQ is stored locally until a verified custom-EQ command format is mapped."
                                    }
                                } label: {
                                    Text(preset.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 8)
                                        .background(preferences.eqPreset == preset ? Color.accentColor : Color(.tertiarySystemFill))
                                        .foregroundStyle(preferences.eqPreset == preset ? Color.white : Color.primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()

                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(0..<5, id: \.self) { index in
                            VStack(spacing: 8) {
                                Text(String(format: "%+.0f", preferences.customEQ[index]))
                                    .font(.caption2.monospacedDigit())
                                Slider(
                                    value: Binding(
                                        get: { preferences.customEQ[index] },
                                        set: { preferences.setCustomEQBand(index, value: $0) }
                                    ),
                                    in: -6...6,
                                    step: 1
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 90, height: 34)
                                .padding(.vertical, 28)
                                Text(frequencies[index])
                                    .font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Text("Custom bands are a saved profile until the earbuds' custom-EQ packet format is verified.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio features")
                        .font(.headline)
                    mappedToggle(
                        "High-Resolution mode",
                        symbol: "waveform.badge.plus",
                        isOn: $preferences.highResolutionEnabled,
                        onAction: .highResolutionOn,
                        offAction: .highResolutionOff
                    )
                    Divider()
                    mappedToggle(
                        "Low-latency mode",
                        symbol: "bolt.fill",
                        isOn: $preferences.lowLatencyEnabled,
                        onAction: .lowLatencyOn,
                        offAction: .lowLatencyOff
                    )
                    Text("High-resolution audio also depends on the earbud codec, iPhone audio route, source format, and the model's firmware.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .cardStyle()
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sound")
    }

    private func mappedToggle(
        _ title: String,
        symbol: String,
        isOn: Binding<Bool>,
        onAction: CommandAction,
        offAction: CommandAction
    ) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: symbol)
        }
        .onChange(of: isOn.wrappedValue) { enabled in
            perform(enabled ? onAction : offAction, bluetooth: bluetooth, store: commandStore, preferences: preferences)
        }
    }
}

private struct ControlsView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var commandStore: VerifiedCommandStore

    var body: some View {
        Form {
            Section {
                mappedToggle("In-ear detection", isOn: $preferences.inEarDetectionEnabled, on: .inEarOn, off: .inEarOff)
                mappedToggle("Automatic play/pause", isOn: $preferences.autoPlayPauseEnabled, on: .autoPlayOn, off: .autoPlayOff)
                mappedToggle("Multipoint", isOn: $preferences.multipointEnabled, on: .multipointOn, off: .multipointOff)
            } header: {
                Text("Wear detection")
            } footer: {
                Text("These switches send a command only when the matching action is mapped. Your choices are still saved locally.")
            }

            Section {
                actionPicker("Double tap", selection: $preferences.leftDoubleTap)
                actionPicker("Press and hold", selection: $preferences.leftHold)
            } header: {
                Text("Left earbud")
            } footer: {
                Text("Touch assignments are stored as a profile. Their packet format differs by model and must be mapped before real control is enabled.")
            }

            Section("Right earbud") {
                actionPicker("Double tap", selection: $preferences.rightDoubleTap)
                actionPicker("Press and hold", selection: $preferences.rightHold)
            }

            Section("Assistant and calls") {
                Label("Use “Siri” or the iPhone side button", systemImage: "mic.fill")
                Label("Call audio follows the system Bluetooth route", systemImage: "phone.fill")
                Text("iOS does not let third-party apps silently trigger Siri or replace the system call controls.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Controls")
    }

    private func mappedToggle(_ title: String, isOn: Binding<Bool>, on: CommandAction, off: CommandAction) -> some View {
        Toggle(title, isOn: isOn)
            .onChange(of: isOn.wrappedValue) { enabled in
                perform(enabled ? on : off, bluetooth: bluetooth, store: commandStore, preferences: preferences)
            }
    }

    private func actionPicker(_ title: String, selection: Binding<TouchAction>) -> some View {
        Picker(title, selection: selection) {
            ForEach(TouchAction.allCases) { action in
                Text(action.rawValue).tag(action)
            }
        }
    }
}

private struct DeviceView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var commandStore: VerifiedCommandStore
    @State private var showingResetInfo = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "earbuds")
                        .font(.system(size: 38))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 66, height: 66)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bluetooth.connectedName ?? "Earbuds")
                            .font(.headline)
                        Text(bluetooth.modelNumber ?? "Model unavailable")
                            .foregroundStyle(.secondary)
                        Text(bluetooth.firmwareVersion.map { "Firmware \($0)" } ?? "Firmware unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Device information") {
                LabeledContent("Manufacturer", value: bluetooth.manufacturer ?? "Unavailable")
                LabeledContent("Model", value: bluetooth.modelNumber ?? "Unavailable")
                LabeledContent("Firmware", value: bluetooth.firmwareVersion ?? "Unavailable")
                LabeledContent("Battery", value: bluetooth.batteryLevel.map { "\($0)%" } ?? "Unavailable")
                LabeledContent("Signal", value: bluetooth.signalStrength.map { "\($0) dBm" } ?? "Unavailable")
                Button("Refresh Device Information") { bluetooth.refreshStatus() }
            }

            Section("Find My Buds") {
                proximityView
                Button {
                    perform(.findLeft, bluetooth: bluetooth, store: commandStore, preferences: preferences)
                } label: {
                    Label("Play Sound on Left Earbud", systemImage: "speaker.wave.2.fill")
                }
                Button {
                    perform(.findRight, bluetooth: bluetooth, store: commandStore, preferences: preferences)
                } label: {
                    Label("Play Sound on Right Earbud", systemImage: "speaker.wave.2.fill")
                }
                Text("Use sound only when the earbuds are outside your ears. RSSI is a rough proximity estimate, not precise location tracking.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Discovered services", value: "\(bluetooth.discoveredServices.count)")
                LabeledContent("Characteristics", value: "\(bluetooth.characteristicCount)")
                Button("Rediscover Bluetooth Services") { bluetooth.rediscoverAllServices() }
                Button("Copy Diagnostics") { bluetooth.copyProtocolLog() }
                Button("Factory Reset Information", role: .destructive) { showingResetInfo = true }
            } header: {
                Text("Firmware and service")
            } footer: {
                Text("Firmware installation and factory reset are not automated without official packages, signatures, and verified commands.")
            }

            Section {
                Button("Disconnect", role: .destructive) { bluetooth.disconnect() }
            }
        }
        .navigationTitle("Device")
        .confirmationDialog("Factory reset is not automated", isPresented: $showingResetInfo, titleVisibility: .visible) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Use the manufacturer's physical-button reset procedure for your exact model. Sending guessed reset or firmware commands can make the earbuds unusable.")
        }
    }

    private var proximityView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Nearby signal", systemImage: "location.fill")
                Spacer()
                Text(proximityText)
                    .font(.subheadline.bold())
            }
            ProgressView(value: proximityValue)
        }
    }

    private var proximityValue: Double {
        guard let rssi = bluetooth.signalStrength else { return 0 }
        return min(max(Double(rssi + 100) / 60.0, 0), 1)
    }

    private var proximityText: String {
        guard let rssi = bluetooth.signalStrength else { return "Unknown" }
        switch rssi {
        case -55...0: return "Very close"
        case -68 ..< -55: return "Close"
        case -80 ..< -68: return "Nearby"
        default: return "Far / weak"
        }
    }
}

struct ProtocolLabView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var commandStore: VerifiedCommandStore
    @State private var writesUnlocked = false
    @State private var markerText = ""
    @State private var importText = ""
    @State private var showingImport = false
    @State private var showingExport = false

    private var recentEvents: [ProtocolEvent] {
        Array(bluetooth.protocolEvents.suffix(120).reversed())
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Clean-room GATT lab", systemImage: "wave.3.right.circle.fill")
                        .font(.headline)
                    Text("Capture services, values, and notifications from earbuds you own. Save repeatable packets as named commands, then the rest of the app can use them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Session") {
                LabeledContent("Services", value: "\(bluetooth.discoveredServices.count)")
                LabeledContent("Characteristics", value: "\(bluetooth.characteristicCount)")
                LabeledContent("Events", value: "\(bluetooth.protocolEvents.count)")
                Button("Rediscover All Services") { bluetooth.rediscoverAllServices() }
                Button("Copy Protocol Log") { bluetooth.copyProtocolLog() }
                    .disabled(bluetooth.protocolEvents.isEmpty)
                Button("Clear Protocol Log", role: .destructive) { bluetooth.clearProtocolLog() }
                    .disabled(bluetooth.protocolEvents.isEmpty)
            }

            Section {
                TextField("Example: enabled transparency", text: $markerText)
                Button("Add Marker") {
                    bluetooth.addProtocolMarker(markerText)
                    markerText = ""
                }
                .disabled(markerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Experiment marker")
            } footer: {
                Text("Add a marker immediately before changing one physical setting, then compare the notifications that follow.")
            }

            Section("Verified command profile") {
                LabeledContent("Mapped actions", value: "\(commandStore.commands.count)/\(CommandAction.allCases.count)")
                ForEach(commandStore.commands) { command in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(CommandAction(rawValue: command.action)?.title ?? command.action)
                                .font(.subheadline.bold())
                            Text("\(command.serviceUUID) · \(command.characteristicUUID)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            commandStore.remove(command)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                Button("Copy Profile JSON") {
                    UIPasteboard.general.string = commandStore.exportJSON()
                    bluetooth.message = "Verified command profile copied."
                }
                Button("Import Profile JSON") { showingImport = true }
                Button("View Export JSON") { showingExport = true }
                if !commandStore.commands.isEmpty {
                    Button("Delete All Mappings", role: .destructive) { commandStore.removeAll() }
                }
            }

            Section("Research writes") {
                Toggle("Unlock one-shot writes", isOn: $writesUnlocked)
                Text(writesUnlocked
                     ? "Only send commands you captured and repeated successfully on your own hardware. Avoid firmware, reset, bootloader, and unknown characteristics."
                     : "Writes are locked. Discovery, reads, and notification capture remain available.")
                    .font(.footnote)
                    .foregroundStyle(writesUnlocked ? .orange : .secondary)
            }

            Section("GATT database") {
                if bluetooth.discoveredServices.isEmpty {
                    Text("No services discovered yet. Connect and tap Rediscover All Services.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bluetooth.discoveredServices) { service in
                        NavigationLink {
                            ServiceInspectorView(serviceID: service.id, writesUnlocked: $writesUnlocked)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(service.uuid)
                                    .font(.body.monospaced())
                                Text("\(service.characteristics.count) characteristics")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Recent GATT events") {
                if recentEvents.isEmpty {
                    Text("No protocol events recorded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentEvents) { event in ProtocolEventRow(event: event) }
                }
            }

            Section("App") {
                NavigationLink("BudControl Settings") { SettingsView() }
            }
        }
        .navigationTitle("Advanced Lab")
        .sheet(isPresented: $showingImport) {
            NavigationStack {
                Form {
                    Section("Paste profile JSON") {
                        TextEditor(text: $importText)
                            .font(.body.monospaced())
                            .frame(minHeight: 260)
                    }
                }
                .navigationTitle("Import Profile")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingImport = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") {
                            switch commandStore.importJSON(importText) {
                            case .success(let count):
                                bluetooth.message = "Imported \(count) command mapping\(count == 1 ? "" : "s")."
                                showingImport = false
                            case .failure(let error):
                                bluetooth.message = "Profile import failed: \(error.localizedDescription)"
                            }
                        }
                        .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showingExport) {
            NavigationStack {
                ScrollView {
                    Text(commandStore.exportJSON())
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Profile JSON")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingExport = false }
                    }
                }
            }
        }
    }
}

private struct ServiceInspectorView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    let serviceID: String
    @Binding var writesUnlocked: Bool

    private var service: GATTServiceInfo? {
        bluetooth.discoveredServices.first(where: { $0.id == serviceID })
    }

    var body: some View {
        List {
            if let service {
                Section("Service") {
                    LabeledContent("UUID", value: service.uuid)
                    LabeledContent("Characteristics", value: "\(service.characteristics.count)")
                }
                Section("Characteristics") {
                    ForEach(service.characteristics) { characteristic in
                        NavigationLink {
                            CharacteristicInspectorView(characteristicID: characteristic.id, writesUnlocked: $writesUnlocked)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(characteristic.uuid)
                                    .font(.body.monospaced())
                                Text(characteristic.properties.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let value = characteristic.lastValueHex, !value.isEmpty {
                                    Text(value)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("This service is no longer available. Rediscover services.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Service")
    }
}

private struct CharacteristicInspectorView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var commandStore: VerifiedCommandStore
    let characteristicID: String
    @Binding var writesUnlocked: Bool
    @State private var hexPayload = ""
    @State private var preferResponse = true
    @State private var selectedAction: CommandAction = .ancOn
    @State private var evidence = "Repeated capture from my own earbuds"

    private var characteristic: GATTCharacteristicInfo? {
        bluetooth.characteristicInfo(id: characteristicID)
    }

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { bluetooth.characteristicInfo(id: characteristicID)?.isNotifying ?? false },
            set: { bluetooth.setNotifications(id: characteristicID, enabled: $0) }
        )
    }

    var body: some View {
        Form {
            if let characteristic {
                Section("Identity") {
                    LabeledContent("Service", value: characteristic.serviceUUID)
                    LabeledContent("Characteristic", value: characteristic.uuid)
                    Text(characteristic.properties.joined(separator: ", "))
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }

                Section("Value") {
                    Text(characteristic.lastValueHex ?? "No value received")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    if characteristic.canRead {
                        Button("Read Value") { bluetooth.readCharacteristic(id: characteristicID) }
                    }
                    if characteristic.canNotify {
                        Toggle("Capture notifications", isOn: notificationBinding)
                    }
                }

                if characteristic.canWrite {
                    Section {
                        if writesUnlocked {
                            TextField("Hex bytes, for example 01 A0 FF", text: $hexPayload, axis: .vertical)
                                .font(.body.monospaced())
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            if characteristic.canWriteWithResponse && characteristic.canWriteWithoutResponse {
                                Toggle("Request write response", isOn: $preferResponse)
                            } else {
                                LabeledContent("Write type", value: characteristic.canWriteWithResponse ? "With response" : "Without response")
                            }
                            Button("Send Once") {
                                let useResponse = characteristic.canWriteWithResponse && (!characteristic.canWriteWithoutResponse || preferResponse)
                                bluetooth.writeHex(hexPayload, to: characteristicID, preferResponse: useResponse)
                            }
                            .disabled(hexPayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            Text("Return to Protocol Lab and unlock one-shot writes first.")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("One-shot write")
                    } footer: {
                        Text("Do not guess payloads. Firmware and reset commands are intentionally not automated.")
                    }

                    Section {
                        Picker("Action", selection: $selectedAction) {
                            ForEach(CommandAction.allCases) { action in
                                Text(action.title).tag(action)
                            }
                        }
                        TextField("Evidence note", text: $evidence, axis: .vertical)
                        Button("Save Mapping") {
                            let useResponse = characteristic.canWriteWithResponse && (!characteristic.canWriteWithoutResponse || preferResponse)
                            commandStore.register(
                                action: selectedAction,
                                serviceUUID: characteristic.serviceUUID,
                                characteristicUUID: characteristic.uuid,
                                payloadHex: hexPayload,
                                writeWithResponse: useResponse,
                                evidenceNote: evidence
                            )
                            bluetooth.message = "Mapped \(selectedAction.title). The normal app control can now use this packet."
                        }
                        .disabled(
                            !writesUnlocked ||
                            hexPayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    } header: {
                        Text("Save as verified action")
                    } footer: {
                        Text("Save only after the same packet has produced the same non-destructive result several times on your own device.")
                    }
                }
            } else {
                Text("This characteristic is no longer available. Rediscover services.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Characteristic")
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var commandStore: VerifiedCommandStore
    @State private var showingReset = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $preferences.theme) {
                    ForEach(AppTheme.allCases) { theme in Text(theme.rawValue).tag(theme) }
                }
                Toggle("Haptic feedback", isOn: $preferences.hapticsEnabled)
            }

            Section("Discovery") {
                Toggle("Show all Bluetooth LE devices", isOn: $preferences.showAllDevices)
                BluetoothRememberedDeviceRow()
            }

            Section("Compatibility profile") {
                LabeledContent("Verified commands", value: "\(commandStore.commands.count)")
                Text("Mappings are saved only on this iPhone unless you copy and export the JSON profile.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("App", value: "BudControl")
                LabeledContent("Version", value: "5.0 Ultimate Lab")
                LabeledContent("Minimum iOS", value: "16.0")
                Text("Independent clean-room companion-app prototype. Not affiliated with or endorsed by Motorola Mobility LLC.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset App Preferences", role: .destructive) { showingReset = true }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Reset all app preferences?", isPresented: $showingReset, titleVisibility: .visible) {
            Button("Reset Preferences", role: .destructive) { preferences.reset() }
            Button("Cancel", role: .cancel) { }
        }
    }
}

private struct BluetoothRememberedDeviceRow: View {
    @EnvironmentObject private var bluetooth: BluetoothManager

    var body: some View {
        if let name = bluetooth.rememberedDeviceName {
            HStack {
                VStack(alignment: .leading) {
                    Text("Remembered device")
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Forget", role: .destructive) { bluetooth.forgetRememberedDevice() }
            }
        } else {
            LabeledContent("Remembered device", value: "None")
        }
    }
}

private struct ProtocolEventRow: View {
    let event: ProtocolEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(event.direction)
                    .font(.caption.bold())
                Text(event.category)
                    .font(.caption)
                Spacer()
                Text(event.displayTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let characteristicUUID = event.characteristicUUID {
                Text(characteristicUUID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let valueHex = event.valueHex, !valueHex.isEmpty {
                Text(valueHex)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            if let note = event.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct BatteryRing: View {
    let level: Int?

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(level ?? 0) / 100)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Image(systemName: "battery.75")
                    .font(.caption)
                Text(level.map { "\($0)%" } ?? "—")
                    .font(.headline.monospacedDigit())
            }
        }
        .frame(width: 78, height: 78)
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private func perform(
    _ action: CommandAction,
    bluetooth: BluetoothManager,
    store: VerifiedCommandStore,
    preferences: AppPreferences
) {
    impact(preferences)
    if let command = store.command(for: action) {
        bluetooth.executeVerifiedCommand(command, title: action.title)
    } else {
        bluetooth.reportMissingMapping(action)
    }
}

private func impact(_ preferences: AppPreferences) {
    guard preferences.hapticsEnabled else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

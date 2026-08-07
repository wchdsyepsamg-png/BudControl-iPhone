import Foundation
import Combine

struct EarbudDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int
    let isLikelyMotoBuds: Bool

    var signalText: String {
        switch rssi {
        case -55...0: return "Excellent"
        case -67 ..< -55: return "Good"
        case -78 ..< -67: return "Fair"
        default: return "Weak"
        }
    }
}

enum ListeningMode: String, CaseIterable, Identifiable, Codable {
    case noiseCancellation = "Noise Cancellation"
    case transparency = "Transparency"
    case off = "Off"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .noiseCancellation: return "ear.and.waveform"
        case .transparency: return "waveform.path.ecg"
        case .off: return "speaker.slash"
        }
    }
}

enum EQPreset: String, CaseIterable, Identifiable, Codable {
    case balanced = "Balanced"
    case bassBoost = "Bass Boost"
    case vocal = "Vocal"
    case bright = "Bright"
    case warm = "Warm"
    case custom = "Custom"
    var id: String { rawValue }
}

enum SoundScene: String, CaseIterable, Identifiable, Codable {
    case commute = "Commute"
    case focus = "Focus"
    case workout = "Workout"
    case gaming = "Gaming"
    case outdoors = "Outdoors"
    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .commute: return "ANC, balanced sound"
        case .focus: return "ANC, warm tuning"
        case .workout: return "Transparency, bass boost"
        case .gaming: return "Low latency, bright tuning"
        case .outdoors: return "Transparency, balanced sound"
        }
    }

    var symbol: String {
        switch self {
        case .commute: return "tram.fill"
        case .focus: return "brain.head.profile"
        case .workout: return "figure.run"
        case .gaming: return "gamecontroller.fill"
        case .outdoors: return "leaf.fill"
        }
    }
}

enum TouchAction: String, CaseIterable, Identifiable, Codable {
    case playPause = "Play / Pause"
    case nextTrack = "Next Track"
    case previousTrack = "Previous Track"
    case listeningMode = "Change Listening Mode"
    case voiceAssistant = "Voice Assistant"
    case volumeUp = "Volume Up"
    case volumeDown = "Volume Down"
    case none = "No Action"
    var id: String { rawValue }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }
}

enum CommandAction: String, CaseIterable, Identifiable, Codable {
    case ancOn = "sound.anc.on"
    case transparencyOn = "sound.transparency.on"
    case listeningOff = "sound.listening.off"
    case eqBalanced = "eq.balanced"
    case eqBassBoost = "eq.bass"
    case eqVocal = "eq.vocal"
    case eqBright = "eq.bright"
    case eqWarm = "eq.warm"
    case highResolutionOn = "audio.hires.on"
    case highResolutionOff = "audio.hires.off"
    case lowLatencyOn = "audio.latency.on"
    case lowLatencyOff = "audio.latency.off"
    case inEarOn = "wear.in_ear.on"
    case inEarOff = "wear.in_ear.off"
    case autoPlayOn = "wear.autoplay.on"
    case autoPlayOff = "wear.autoplay.off"
    case multipointOn = "connection.multipoint.on"
    case multipointOff = "connection.multipoint.off"
    case findLeft = "find.left"
    case findRight = "find.right"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ancOn: return "Noise Cancellation"
        case .transparencyOn: return "Transparency"
        case .listeningOff: return "Listening Mode Off"
        case .eqBalanced: return "EQ: Balanced"
        case .eqBassBoost: return "EQ: Bass Boost"
        case .eqVocal: return "EQ: Vocal"
        case .eqBright: return "EQ: Bright"
        case .eqWarm: return "EQ: Warm"
        case .highResolutionOn: return "High-Resolution On"
        case .highResolutionOff: return "High-Resolution Off"
        case .lowLatencyOn: return "Low Latency On"
        case .lowLatencyOff: return "Low Latency Off"
        case .inEarOn: return "In-Ear Detection On"
        case .inEarOff: return "In-Ear Detection Off"
        case .autoPlayOn: return "Auto Play/Pause On"
        case .autoPlayOff: return "Auto Play/Pause Off"
        case .multipointOn: return "Multipoint On"
        case .multipointOff: return "Multipoint Off"
        case .findLeft: return "Find Left Earbud"
        case .findRight: return "Find Right Earbud"
        }
    }

    static func forListeningMode(_ mode: ListeningMode) -> CommandAction {
        switch mode {
        case .noiseCancellation: return .ancOn
        case .transparency: return .transparencyOn
        case .off: return .listeningOff
        }
    }

    static func forPreset(_ preset: EQPreset) -> CommandAction? {
        switch preset {
        case .balanced: return .eqBalanced
        case .bassBoost: return .eqBassBoost
        case .vocal: return .eqVocal
        case .bright: return .eqBright
        case .warm: return .eqWarm
        case .custom: return nil
        }
    }
}

struct GATTCharacteristicInfo: Identifiable, Hashable {
    let id: String
    let serviceUUID: String
    let uuid: String
    let properties: [String]
    var isNotifying: Bool
    var lastValueHex: String?

    var canRead: Bool { properties.contains("read") }
    var canNotify: Bool { properties.contains("notify") || properties.contains("indicate") }
    var canWriteWithResponse: Bool { properties.contains("write") }
    var canWriteWithoutResponse: Bool { properties.contains("writeWithoutResponse") }
    var canWrite: Bool { canWriteWithResponse || canWriteWithoutResponse }
}

struct GATTServiceInfo: Identifiable, Hashable {
    let id: String
    let uuid: String
    var characteristics: [GATTCharacteristicInfo]
}

struct ProtocolEvent: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let direction: String
    let category: String
    let serviceUUID: String?
    let characteristicUUID: String?
    let valueHex: String?
    let note: String?

    var displayTime: String { Self.timeFormatter.string(from: timestamp) }

    var singleLine: String {
        var pieces = ["[\(displayTime)]", direction, category]
        if let serviceUUID { pieces.append("S:\(serviceUUID)") }
        if let characteristicUUID { pieces.append("C:\(characteristicUUID)") }
        if let valueHex, !valueHex.isEmpty { pieces.append(valueHex) }
        if let note, !note.isEmpty { pieces.append(note) }
        return pieces.joined(separator: " ")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

final class AppPreferences: ObservableObject {
    private enum Key {
        static let listeningMode = "listeningMode"
        static let eqPreset = "eqPreset"
        static let customEQ = "customEQ"
        static let highResolution = "highResolution"
        static let lowLatency = "lowLatency"
        static let inEarDetection = "inEarDetection"
        static let autoPlayPause = "autoPlayPause"
        static let multipoint = "multipoint"
        static let leftDoubleTap = "leftDoubleTap"
        static let leftHold = "leftHold"
        static let rightDoubleTap = "rightDoubleTap"
        static let rightHold = "rightHold"
        static let showAllDevices = "showAllDevices"
        static let theme = "theme"
        static let haptics = "haptics"
        static let lastScene = "lastScene"
    }

    private let defaults: UserDefaults

    @Published var listeningMode: ListeningMode { didSet { defaults.set(listeningMode.rawValue, forKey: Key.listeningMode) } }
    @Published var eqPreset: EQPreset { didSet { defaults.set(eqPreset.rawValue, forKey: Key.eqPreset) } }
    @Published var customEQ: [Double] { didSet { defaults.set(customEQ, forKey: Key.customEQ) } }
    @Published var highResolutionEnabled: Bool { didSet { defaults.set(highResolutionEnabled, forKey: Key.highResolution) } }
    @Published var lowLatencyEnabled: Bool { didSet { defaults.set(lowLatencyEnabled, forKey: Key.lowLatency) } }
    @Published var inEarDetectionEnabled: Bool { didSet { defaults.set(inEarDetectionEnabled, forKey: Key.inEarDetection) } }
    @Published var autoPlayPauseEnabled: Bool { didSet { defaults.set(autoPlayPauseEnabled, forKey: Key.autoPlayPause) } }
    @Published var multipointEnabled: Bool { didSet { defaults.set(multipointEnabled, forKey: Key.multipoint) } }
    @Published var leftDoubleTap: TouchAction { didSet { defaults.set(leftDoubleTap.rawValue, forKey: Key.leftDoubleTap) } }
    @Published var leftHold: TouchAction { didSet { defaults.set(leftHold.rawValue, forKey: Key.leftHold) } }
    @Published var rightDoubleTap: TouchAction { didSet { defaults.set(rightDoubleTap.rawValue, forKey: Key.rightDoubleTap) } }
    @Published var rightHold: TouchAction { didSet { defaults.set(rightHold.rawValue, forKey: Key.rightHold) } }
    @Published var showAllDevices: Bool { didSet { defaults.set(showAllDevices, forKey: Key.showAllDevices) } }
    @Published var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) } }
    @Published var lastScene: SoundScene? { didSet { defaults.set(lastScene?.rawValue, forKey: Key.lastScene) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        listeningMode = ListeningMode(rawValue: defaults.string(forKey: Key.listeningMode) ?? "") ?? .noiseCancellation
        eqPreset = EQPreset(rawValue: defaults.string(forKey: Key.eqPreset) ?? "") ?? .balanced
        let savedCustomEQ = defaults.array(forKey: Key.customEQ) as? [Double] ?? [0, 0, 0, 0, 0]
        customEQ = savedCustomEQ.count == 5 ? savedCustomEQ : [0, 0, 0, 0, 0]
        highResolutionEnabled = defaults.object(forKey: Key.highResolution) as? Bool ?? false
        lowLatencyEnabled = defaults.object(forKey: Key.lowLatency) as? Bool ?? false
        inEarDetectionEnabled = defaults.object(forKey: Key.inEarDetection) as? Bool ?? true
        autoPlayPauseEnabled = defaults.object(forKey: Key.autoPlayPause) as? Bool ?? true
        multipointEnabled = defaults.object(forKey: Key.multipoint) as? Bool ?? false
        leftDoubleTap = TouchAction(rawValue: defaults.string(forKey: Key.leftDoubleTap) ?? "") ?? .playPause
        leftHold = TouchAction(rawValue: defaults.string(forKey: Key.leftHold) ?? "") ?? .listeningMode
        rightDoubleTap = TouchAction(rawValue: defaults.string(forKey: Key.rightDoubleTap) ?? "") ?? .playPause
        rightHold = TouchAction(rawValue: defaults.string(forKey: Key.rightHold) ?? "") ?? .voiceAssistant
        showAllDevices = defaults.object(forKey: Key.showAllDevices) as? Bool ?? true
        theme = AppTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        lastScene = SoundScene(rawValue: defaults.string(forKey: Key.lastScene) ?? "")
    }

    func setCustomEQBand(_ index: Int, value: Double) {
        guard customEQ.indices.contains(index) else { return }
        var copy = customEQ
        copy[index] = value
        customEQ = copy
        eqPreset = .custom
    }

    func apply(scene: SoundScene) {
        lastScene = scene
        switch scene {
        case .commute:
            listeningMode = .noiseCancellation
            eqPreset = .balanced
            lowLatencyEnabled = false
        case .focus:
            listeningMode = .noiseCancellation
            eqPreset = .warm
            lowLatencyEnabled = false
        case .workout:
            listeningMode = .transparency
            eqPreset = .bassBoost
            lowLatencyEnabled = false
        case .gaming:
            listeningMode = .off
            eqPreset = .bright
            lowLatencyEnabled = true
        case .outdoors:
            listeningMode = .transparency
            eqPreset = .balanced
            lowLatencyEnabled = false
        }
    }

    func reset() {
        listeningMode = .noiseCancellation
        eqPreset = .balanced
        customEQ = [0, 0, 0, 0, 0]
        highResolutionEnabled = false
        lowLatencyEnabled = false
        inEarDetectionEnabled = true
        autoPlayPauseEnabled = true
        multipointEnabled = false
        leftDoubleTap = .playPause
        leftHold = .listeningMode
        rightDoubleTap = .playPause
        rightHold = .voiceAssistant
        showAllDevices = true
        theme = .system
        hapticsEnabled = true
        lastScene = nil
    }
}

import Foundation
import AVFoundation
import AVKit
import Combine
import SwiftUI

final class AudioRouteManager: ObservableObject {
    @Published private(set) var outputName = "iPhone audio"
    @Published private(set) var outputType = "Built-in"
    @Published private(set) var isBluetoothAudioActive = false
    @Published private(set) var sampleRate = 0.0
    @Published private(set) var outputChannels = 0

    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        let session = AVAudioSession.sharedInstance()
        let output = session.currentRoute.outputs.first
        outputName = output?.portName ?? "iPhone audio"
        outputType = output?.portType.rawValue ?? "Built-in"
        isBluetoothAudioActive = session.currentRoute.outputs.contains { output in
            output.portType == .bluetoothA2DP || output.portType == .bluetoothHFP
        }
        sampleRate = session.sampleRate
        outputChannels = Int(session.outputNumberOfChannels)
    }
}

struct SystemRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.prioritizesVideoDevices = false
        picker.activeTintColor = UIColor.systemBlue
        picker.tintColor = UIColor.secondaryLabel
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}

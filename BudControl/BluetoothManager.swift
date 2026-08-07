import Foundation
import CoreBluetooth
import Combine
import UIKit

final class BluetoothManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothState = "Starting Bluetooth…"
    @Published private(set) var devices: [EarbudDevice] = []
    @Published private(set) var connectedName: String?
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var signalStrength: Int?
    @Published private(set) var manufacturer: String?
    @Published private(set) var modelNumber: String?
    @Published private(set) var firmwareVersion: String?
    @Published private(set) var isScanning = false
    @Published private(set) var isDemoMode = false
    @Published private(set) var discoveredServices: [GATTServiceInfo] = []
    @Published private(set) var protocolEvents: [ProtocolEvent] = []
    @Published private(set) var lastCommandStatus = "No verified command sent"
    @Published private(set) var rememberedDeviceName: String? = UserDefaults.standard.string(forKey: "BudControl.lastDeviceName")
    @Published var message: String?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var scanStopWorkItem: DispatchWorkItem?
    private var characteristicsByID: [String: CBCharacteristic] = [:]
    private var loggedAdvertisementIDs: Set<UUID> = []

    private let batteryService = CBUUID(string: "180F")
    private let batteryLevelCharacteristic = CBUUID(string: "2A19")
    private let deviceInfoService = CBUUID(string: "180A")
    private let manufacturerCharacteristic = CBUUID(string: "2A29")
    private let modelCharacteristic = CBUUID(string: "2A24")
    private let firmwareCharacteristic = CBUUID(string: "2A26")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }

    var isConnected: Bool { connectedName != nil }

    var characteristicCount: Int {
        discoveredServices.reduce(0) { $0 + $1.characteristics.count }
    }

    func visibleDevices(showAll: Bool) -> [EarbudDevice] {
        showAll ? devices : devices.filter { $0.isLikelyMotoBuds }
    }

    func startScan() {
        guard central.state == .poweredOn else {
            message = "Turn on Bluetooth and allow Bluetooth access in iPhone Settings."
            return
        }

        disconnectDemoIfNeeded()
        devices.removeAll()
        peripherals.removeAll()
        loggedAdvertisementIDs.removeAll()
        isScanning = true
        bluetoothState = "Scanning for nearby earbuds…"
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        scanStopWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.stopScan() }
        scanStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: workItem)
    }

    func stopScan() {
        scanStopWorkItem?.cancel()
        scanStopWorkItem = nil
        central.stopScan()
        isScanning = false
        if connectedName == nil {
            bluetoothState = devices.isEmpty ? "No devices found" : "Select a device"
        }
    }

    func reconnectRememberedDevice() {
        guard central.state == .poweredOn else {
            message = "Turn on Bluetooth first."
            return
        }
        guard let rawID = UserDefaults.standard.string(forKey: "BudControl.lastPeripheralID"),
              let identifier = UUID(uuidString: rawID) else {
            message = "No remembered earbud control connection is available yet."
            return
        }
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first else {
            message = "The remembered device is not currently available. Put the earbuds nearby and scan again."
            return
        }
        stopScan()
        resetProtocolSession()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        bluetoothState = "Reconnecting to \(rememberedDeviceName ?? peripheral.name ?? "earbuds")…"
        appendEvent(direction: "SYS", category: "reconnect", note: rememberedDeviceName)
        central.connect(peripheral, options: nil)
    }

    func forgetRememberedDevice() {
        UserDefaults.standard.removeObject(forKey: "BudControl.lastPeripheralID")
        UserDefaults.standard.removeObject(forKey: "BudControl.lastDeviceName")
        rememberedDeviceName = nil
        message = "Remembered device removed."
    }

    func connect(to device: EarbudDevice) {
        guard let peripheral = peripherals[device.id] else {
            message = "That device is no longer available. Scan again."
            return
        }
        stopScan()
        resetProtocolSession()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        bluetoothState = "Connecting to \(device.name)…"
        appendEvent(direction: "SYS", category: "connect", note: device.name)
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        if isDemoMode {
            clearConnection()
            bluetoothState = "Demo disconnected"
            return
        }
        if let peripheral = connectedPeripheral {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    func connectDemo() {
        stopScan()
        resetProtocolSession()
        isDemoMode = true
        connectedName = "BudControl Demo Buds"
        batteryLevel = 86
        signalStrength = -48
        manufacturer = "BudControl"
        modelNumber = "Interactive Demo"
        firmwareVersion = "1.0.0"
        bluetoothState = "Connected in demo mode"
        discoveredServices = [
            GATTServiceInfo(
                id: "180F",
                uuid: "180F",
                characteristics: [
                    GATTCharacteristicInfo(
                        id: "180F|2A19",
                        serviceUUID: "180F",
                        uuid: "2A19",
                        properties: ["read", "notify"],
                        isNotifying: true,
                        lastValueHex: "56"
                    )
                ]
            ),
            GATTServiceInfo(
                id: "FFF0",
                uuid: "FFF0",
                characteristics: [
                    GATTCharacteristicInfo(
                        id: "FFF0|FFF1",
                        serviceUUID: "FFF0",
                        uuid: "FFF1",
                        properties: ["write", "notify"],
                        isNotifying: true,
                        lastValueHex: "01 00"
                    )
                ]
            )
        ]
        appendEvent(direction: "SYS", category: "demo", note: "Loaded simulated GATT database")
    }

    func refreshStatus() {
        if isDemoMode {
            signalStrength = Int.random(in: -55 ... -42)
            appendEvent(direction: "RX", category: "demo-rssi", valueHex: String(signalStrength ?? -48))
            return
        }
        connectedPeripheral?.readRSSI()
        for service in connectedPeripheral?.services ?? [] {
            for characteristic in service.characteristics ?? [] where characteristic.properties.contains(.read) {
                connectedPeripheral?.readValue(for: characteristic)
            }
        }
    }

    func rediscoverAllServices() {
        guard !isDemoMode, let peripheral = connectedPeripheral else {
            message = isDemoMode ? "Demo services are already loaded." : "Connect to earbuds first."
            return
        }
        discoveredServices.removeAll()
        characteristicsByID.removeAll()
        appendEvent(direction: "SYS", category: "service-scan", note: "Rediscovering all GATT services")
        peripheral.discoverServices(nil)
    }

    func characteristicInfo(id: String) -> GATTCharacteristicInfo? {
        for service in discoveredServices {
            if let info = service.characteristics.first(where: { $0.id == id }) {
                return info
            }
        }
        return nil
    }

    func readCharacteristic(id: String) {
        if isDemoMode {
            appendEvent(direction: "TX", category: "demo-read", characteristicUUID: id)
            return
        }
        guard let peripheral = connectedPeripheral,
              let characteristic = characteristicsByID[id] else {
            message = "Characteristic is no longer available. Rediscover services."
            return
        }
        guard characteristic.properties.contains(.read) else {
            message = "This characteristic does not advertise read access."
            return
        }
        appendEvent(
            direction: "TX",
            category: "read-request",
            serviceUUID: characteristic.service?.uuid.uuidString,
            characteristicUUID: characteristic.uuid.uuidString
        )
        peripheral.readValue(for: characteristic)
    }

    func setNotifications(id: String, enabled: Bool) {
        if isDemoMode {
            updateCharacteristicSnapshot(id: id, isNotifying: enabled)
            appendEvent(direction: "TX", category: enabled ? "demo-subscribe" : "demo-unsubscribe", characteristicUUID: id)
            return
        }
        guard let peripheral = connectedPeripheral,
              let characteristic = characteristicsByID[id] else {
            message = "Characteristic is no longer available. Rediscover services."
            return
        }
        guard characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else {
            message = "This characteristic does not advertise notifications or indications."
            return
        }
        appendEvent(
            direction: "TX",
            category: enabled ? "subscribe" : "unsubscribe",
            serviceUUID: characteristic.service?.uuid.uuidString,
            characteristicUUID: characteristic.uuid.uuidString
        )
        peripheral.setNotifyValue(enabled, for: characteristic)
    }

    func writeHex(_ input: String, to id: String, preferResponse: Bool) {
        guard let data = Self.dataFromHex(input) else {
            message = "Enter valid hexadecimal bytes, such as 01 A0 FF."
            return
        }
        guard !data.isEmpty else {
            message = "Enter at least one byte."
            return
        }
        guard data.count <= 128 else {
            message = "One-shot research writes are limited to 128 bytes."
            return
        }

        if isDemoMode {
            appendEvent(direction: "TX", category: "demo-write", characteristicUUID: id, valueHex: data.hexString)
            message = "Demo write recorded. No real device command was sent."
            return
        }

        guard let peripheral = connectedPeripheral,
              let characteristic = characteristicsByID[id] else {
            message = "Characteristic is no longer available. Rediscover services."
            return
        }

        let supportsResponse = characteristic.properties.contains(.write)
        let supportsWithoutResponse = characteristic.properties.contains(.writeWithoutResponse)
        guard supportsResponse || supportsWithoutResponse else {
            message = "This characteristic does not advertise write access."
            return
        }

        let type: CBCharacteristicWriteType
        if preferResponse && supportsResponse {
            type = .withResponse
        } else if supportsWithoutResponse {
            type = .withoutResponse
        } else {
            type = .withResponse
        }

        let maximum = peripheral.maximumWriteValueLength(for: type)
        guard data.count <= maximum else {
            message = "Payload is \(data.count) bytes, but this connection allows \(maximum) bytes for that write type."
            return
        }

        appendEvent(
            direction: "TX",
            category: type == .withResponse ? "write" : "write-no-response",
            serviceUUID: characteristic.service?.uuid.uuidString,
            characteristicUUID: characteristic.uuid.uuidString,
            valueHex: data.hexString
        )
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    func executeVerifiedCommand(_ command: VerifiedGATTCommand, title: String) {
        let service = command.serviceUUID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let characteristic = command.characteristicUUID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let id = "\(service)|\(characteristic)"

        guard characteristicInfo(id: id) != nil || isDemoMode else {
            lastCommandStatus = "Mapping unavailable on this connection"
            message = "The mapped characteristic was not found. Rediscover services and confirm the profile matches this earbud model and firmware."
            return
        }

        writeHex(command.payloadHex, to: id, preferResponse: command.writeWithResponse)
        lastCommandStatus = isDemoMode ? "Demo: \(title)" : "Sent: \(title)"
        appendEvent(
            direction: "APP",
            category: "verified-action",
            serviceUUID: service,
            characteristicUUID: characteristic,
            valueHex: command.payloadHex,
            note: title
        )
    }

    func reportMissingMapping(_ action: CommandAction) {
        lastCommandStatus = "Needs mapping: \(action.title)"
        if isDemoMode {
            message = "Demo: \(action.title)"
        } else {
            message = "\(action.title) is saved locally, but no verified command is mapped yet. Open Protocol Lab, capture the command from earbuds you own, and save it to this action."
        }
    }

    func addProtocolMarker(_ note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendEvent(direction: "MARK", category: "experiment", note: trimmed)
    }

    func clearProtocolLog() {
        protocolEvents.removeAll()
        lastCommandStatus = "Protocol log cleared"
    }

    func copyProtocolLog() {
        UIPasteboard.general.string = protocolLogText()
        message = "Protocol log copied to the clipboard."
    }

    func protocolLogText() -> String {
        let header = [
            "BudControl clean-room GATT log",
            "Device: \(connectedName ?? "None")",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "Services: \(discoveredServices.count)",
            "Characteristics: \(characteristicCount)",
            ""
        ]
        return (header + protocolEvents.map(\.singleLine)).joined(separator: "\n")
    }

    func showUnsupportedControl(_ title: String) {
        if isDemoMode {
            message = "Demo: \(title)"
        } else {
            message = "\(title) was saved locally. Use Protocol Lab captures from your own earbuds to map a verified command before enabling real control."
        }
    }

    private func disconnectDemoIfNeeded() {
        if isDemoMode { clearConnection() }
    }

    private func clearConnection() {
        isDemoMode = false
        connectedName = nil
        connectedPeripheral = nil
        batteryLevel = nil
        signalStrength = nil
        manufacturer = nil
        modelNumber = nil
        firmwareVersion = nil
        discoveredServices.removeAll()
        characteristicsByID.removeAll()
    }

    private func resetProtocolSession() {
        discoveredServices.removeAll()
        characteristicsByID.removeAll()
        protocolEvents.removeAll()
    }

    private func updateDeviceInfo(_ characteristic: CBCharacteristic) {
        guard let data = characteristic.value,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) else { return }
        switch characteristic.uuid {
        case manufacturerCharacteristic: manufacturer = text
        case modelCharacteristic: modelNumber = text
        case firmwareCharacteristic: firmwareVersion = text
        default: break
        }
    }

    private func appendEvent(
        direction: String,
        category: String,
        serviceUUID: String? = nil,
        characteristicUUID: String? = nil,
        valueHex: String? = nil,
        note: String? = nil
    ) {
        let event = ProtocolEvent(
            timestamp: Date(),
            direction: direction,
            category: category,
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID,
            valueHex: valueHex,
            note: note
        )
        protocolEvents.append(event)
        if protocolEvents.count > 1000 {
            protocolEvents.removeFirst(protocolEvents.count - 1000)
        }
    }

    private func characteristicID(serviceUUID: CBUUID, characteristicUUID: CBUUID) -> String {
        "\(serviceUUID.uuidString.uppercased())|\(characteristicUUID.uuidString.uppercased())"
    }

    private func updateCharacteristicSnapshot(
        id: String,
        isNotifying: Bool? = nil,
        lastValueHex: String? = nil
    ) {
        guard let serviceIndex = discoveredServices.firstIndex(where: { service in
            service.characteristics.contains(where: { $0.id == id })
        }), let characteristicIndex = discoveredServices[serviceIndex].characteristics.firstIndex(where: { $0.id == id }) else {
            return
        }
        if let isNotifying {
            discoveredServices[serviceIndex].characteristics[characteristicIndex].isNotifying = isNotifying
        }
        if let lastValueHex {
            discoveredServices[serviceIndex].characteristics[characteristicIndex].lastValueHex = lastValueHex
        }
    }

    private static func dataFromHex(_ input: String) -> Data? {
        var cleaned = input.uppercased()
        for separator in ["0X", " ", "\n", "\t", "-", ":", ","] {
            cleaned = cleaned.replacingOccurrences(of: separator, with: "")
        }
        guard cleaned.count % 2 == 0 else { return nil }
        guard cleaned.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789ABCDEF").contains($0) }) else {
            return nil
        }
        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: bluetoothState = "Bluetooth is ready"
        case .poweredOff: bluetoothState = "Bluetooth is off"
        case .unauthorized: bluetoothState = "Bluetooth permission denied"
        case .unsupported: bluetoothState = "Bluetooth is unsupported"
        case .resetting: bluetoothState = "Bluetooth is resetting"
        case .unknown: bluetoothState = "Bluetooth status unknown"
        @unknown default: bluetoothState = "Bluetooth unavailable"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Unnamed Bluetooth Device"
        let lowercased = name.lowercased()
        let isMoto = lowercased.contains("moto buds") || lowercased.contains("motobuds") || lowercased.contains("buds loop")
        peripherals[peripheral.identifier] = peripheral
        let device = EarbudDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, isLikelyMotoBuds: isMoto)
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        devices.sort { first, second in
            if first.isLikelyMotoBuds != second.isLikelyMotoBuds {
                return first.isLikelyMotoBuds
            }
            return first.rssi > second.rssi
        }

        if !loggedAdvertisementIDs.contains(peripheral.identifier) {
            loggedAdvertisementIDs.insert(peripheral.identifier)
            let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
                .map(\.uuidString)
                .joined(separator: ", ")
            let manufacturerData = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.hexString
            appendEvent(
                direction: "RX",
                category: "advertisement",
                valueHex: manufacturerData,
                note: "\(name); RSSI \(RSSI); services \(serviceUUIDs ?? "none listed")"
            )
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        connectedName = peripheral.name ?? "Connected Earbuds"
        rememberedDeviceName = connectedName
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "BudControl.lastPeripheralID")
        UserDefaults.standard.set(connectedName, forKey: "BudControl.lastDeviceName")
        bluetoothState = "Connected"
        peripheral.delegate = self
        appendEvent(direction: "SYS", category: "connected", note: connectedName)
        peripheral.discoverServices(nil)
        peripheral.readRSSI()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        appendEvent(direction: "SYS", category: "connect-failed", note: error?.localizedDescription)
        clearConnection()
        bluetoothState = "Connection failed"
        message = error?.localizedDescription ?? "The earbuds could not be connected."
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        appendEvent(direction: "SYS", category: "disconnected", note: error?.localizedDescription)
        clearConnection()
        bluetoothState = "Disconnected"
        if let error { message = error.localizedDescription }
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            appendEvent(direction: "SYS", category: "service-error", note: error.localizedDescription)
            message = error.localizedDescription
            return
        }

        let services = peripheral.services ?? []
        discoveredServices = services.map { service in
            GATTServiceInfo(id: service.uuid.uuidString.uppercased(), uuid: service.uuid.uuidString.uppercased(), characteristics: [])
        }
        appendEvent(direction: "RX", category: "services", note: "Discovered \(services.count) services")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            appendEvent(
                direction: "SYS",
                category: "characteristic-error",
                serviceUUID: service.uuid.uuidString,
                note: error.localizedDescription
            )
            message = error.localizedDescription
            return
        }

        let serviceUUID = service.uuid.uuidString.uppercased()
        let characteristics = service.characteristics ?? []
        let snapshots = characteristics.map { characteristic -> GATTCharacteristicInfo in
            let id = characteristicID(serviceUUID: service.uuid, characteristicUUID: characteristic.uuid)
            characteristicsByID[id] = characteristic
            return GATTCharacteristicInfo(
                id: id,
                serviceUUID: serviceUUID,
                uuid: characteristic.uuid.uuidString.uppercased(),
                properties: characteristic.properties.protocolNames,
                isNotifying: characteristic.isNotifying,
                lastValueHex: characteristic.value?.hexString
            )
        }

        if let serviceIndex = discoveredServices.firstIndex(where: { $0.uuid == serviceUUID }) {
            discoveredServices[serviceIndex].characteristics = snapshots
        }

        appendEvent(
            direction: "RX",
            category: "characteristics",
            serviceUUID: serviceUUID,
            note: "Discovered \(characteristics.count) characteristics"
        )

        for characteristic in characteristics {
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let serviceUUID = characteristic.service?.uuid.uuidString.uppercased()
        let characteristicUUID = characteristic.uuid.uuidString.uppercased()
        let id = serviceUUID.map { "\($0)|\(characteristicUUID)" } ?? characteristicUUID

        if let error {
            appendEvent(
                direction: "SYS",
                category: "value-error",
                serviceUUID: serviceUUID,
                characteristicUUID: characteristicUUID,
                note: error.localizedDescription
            )
            message = error.localizedDescription
            return
        }

        let hex = characteristic.value?.hexString ?? ""
        updateCharacteristicSnapshot(id: id, lastValueHex: hex)
        appendEvent(
            direction: "RX",
            category: characteristic.isNotifying ? "notification/value" : "read/value",
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID,
            valueHex: hex
        )

        if characteristic.uuid == batteryLevelCharacteristic, let value = characteristic.value?.first {
            batteryLevel = min(100, Int(value))
        }
        if characteristic.service?.uuid == deviceInfoService {
            updateDeviceInfo(characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let serviceUUID = characteristic.service?.uuid.uuidString.uppercased()
        let characteristicUUID = characteristic.uuid.uuidString.uppercased()
        let id = serviceUUID.map { "\($0)|\(characteristicUUID)" } ?? characteristicUUID
        if let error {
            appendEvent(
                direction: "SYS",
                category: "notification-error",
                serviceUUID: serviceUUID,
                characteristicUUID: characteristicUUID,
                note: error.localizedDescription
            )
            return
        }
        updateCharacteristicSnapshot(id: id, isNotifying: characteristic.isNotifying)
        appendEvent(
            direction: "RX",
            category: characteristic.isNotifying ? "subscribed" : "unsubscribed",
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        appendEvent(
            direction: error == nil ? "RX" : "SYS",
            category: error == nil ? "write-ack" : "write-error",
            serviceUUID: characteristic.service?.uuid.uuidString.uppercased(),
            characteristicUUID: characteristic.uuid.uuidString.uppercased(),
            note: error?.localizedDescription
        )
        if let error { message = error.localizedDescription }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error {
            appendEvent(direction: "SYS", category: "rssi-error", note: error.localizedDescription)
            return
        }
        signalStrength = RSSI.intValue
        appendEvent(direction: "RX", category: "rssi", valueHex: "\(RSSI.intValue) dBm")
    }
}

private extension CBCharacteristicProperties {
    var protocolNames: [String] {
        var values: [String] = []
        if contains(.broadcast) { values.append("broadcast") }
        if contains(.read) { values.append("read") }
        if contains(.writeWithoutResponse) { values.append("writeWithoutResponse") }
        if contains(.write) { values.append("write") }
        if contains(.notify) { values.append("notify") }
        if contains(.indicate) { values.append("indicate") }
        if contains(.authenticatedSignedWrites) { values.append("authenticatedSignedWrites") }
        if contains(.extendedProperties) { values.append("extendedProperties") }
        if contains(.notifyEncryptionRequired) { values.append("notifyEncryptionRequired") }
        if contains(.indicateEncryptionRequired) { values.append("indicateEncryptionRequired") }
        return values
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

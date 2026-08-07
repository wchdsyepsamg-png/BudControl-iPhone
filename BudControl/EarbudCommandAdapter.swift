import Foundation
import Combine

struct VerifiedGATTCommand: Codable, Hashable, Identifiable {
    let action: String
    let serviceUUID: String
    let characteristicUUID: String
    let payloadHex: String
    let writeWithResponse: Bool
    let evidenceNote: String

    var id: String { action }
}

final class VerifiedCommandStore: ObservableObject {
    @Published private(set) var commands: [VerifiedGATTCommand] = []
    private let defaultsKey = "BudControlVerifiedCommands.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func command(for action: CommandAction) -> VerifiedGATTCommand? {
        commands.first { $0.action == action.rawValue }
    }

    func register(
        action: CommandAction,
        serviceUUID: String,
        characteristicUUID: String,
        payloadHex: String,
        writeWithResponse: Bool,
        evidenceNote: String
    ) {
        let command = VerifiedGATTCommand(
            action: action.rawValue,
            serviceUUID: normalize(serviceUUID),
            characteristicUUID: normalize(characteristicUUID),
            payloadHex: payloadHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            writeWithResponse: writeWithResponse,
            evidenceNote: evidenceNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        commands.removeAll { $0.action == action.rawValue }
        commands.append(command)
        commands.sort { $0.action < $1.action }
        save()
    }

    func remove(_ command: VerifiedGATTCommand) {
        commands.removeAll { $0.id == command.id }
        save()
    }

    func removeAll() {
        commands.removeAll()
        save()
    }

    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(commands) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    @discardableResult
    func importJSON(_ text: String) -> Result<Int, Error> {
        do {
            let decoded = try JSONDecoder().decode([VerifiedGATTCommand].self, from: Data(text.utf8))
            var merged = commands
            for item in decoded {
                merged.removeAll { $0.action == item.action }
                merged.append(item)
            }
            commands = merged.sorted { $0.action < $1.action }
            save()
            return .success(decoded.count)
        } catch {
            return .failure(error)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([VerifiedGATTCommand].self, from: data) else { return }
        commands = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func normalize(_ uuid: String) -> String {
        uuid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

import SwiftUI

@main
struct BudControlApp: App {
    @StateObject private var bluetooth = BluetoothManager()
    @StateObject private var preferences = AppPreferences()
    @StateObject private var commandStore = VerifiedCommandStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetooth)
                .environmentObject(preferences)
                .environmentObject(commandStore)
                .preferredColorScheme(preferredScheme)
        }
    }

    private var preferredScheme: ColorScheme? {
        switch preferences.theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

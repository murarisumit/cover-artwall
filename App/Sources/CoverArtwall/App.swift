import SwiftUI

@main
struct CoverArtwallApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.currentTrack == nil ? "photo" : "photo.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let wallpaper = appState.currentWallpaperImage {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 236, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.15))
                    )
            }

            if let track = appState.currentTrack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.headline).lineLimit(1)
                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text("Nothing playing").foregroundStyle(.secondary)
            }

            Divider()

            Toggle("Update wallpaper automatically", isOn: $appState.isAutoUpdateEnabled)

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { appState.launchAtLoginEnabled },
                    set: { appState.setLaunchAtLogin($0) }
                )
            )

            if let error = appState.lastError {
                Divider()
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Divider()

            Button("Quit Cover Artwall") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}

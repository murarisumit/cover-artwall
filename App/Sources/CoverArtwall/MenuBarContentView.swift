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
                    if let sourceName = appState.currentSourceName {
                        Text(sourceName).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("Nothing playing").foregroundStyle(.secondary)
            }

            Divider()

            if showsSourcePicker {
                Picker("Source", selection: $appState.sourceSelection) {
                    Text("Automatic").tag(SourceSelection.automatic)
                    ForEach(appState.availableSources) { source in
                        Text(source.displayName).tag(SourceSelection.pinned(sourceID: source.id))
                    }
                }
            }

            Toggle("Update wallpaper automatically", isOn: $appState.isAutoUpdateEnabled)

            if appState.availableDisplays.count > 1 {
                displayPicker
            }

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
        .onAppear {
            appState.refreshAvailableSources()
            appState.refreshAvailableDisplays()
        }
    }

    /// Only shown with more than one display connected — on a single
    /// screen there is nothing to choose.
    @ViewBuilder
    private var displayPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Displays")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("All displays", isOn: allDisplaysBinding)
                .toggleStyle(.checkbox)

            ForEach(appState.availableDisplays) { display in
                Toggle(display.name, isOn: binding(for: display))
                    .toggleStyle(.checkbox)
                    .lineLimit(1)
                    .padding(.leading, 18)
                    // Individually checked-and-locked under "All displays",
                    // which reads more clearly than hiding the list.
                    .disabled(appState.displaySelection == .allDisplays)
            }

            if appState.targetedDisplays.isEmpty {
                Text("No display selected — the wallpaper is left alone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
            }
        }
    }

    private var allDisplaysBinding: Binding<Bool> {
        Binding(
            get: { appState.displaySelection == .allDisplays },
            set: { isOn in
                // Unchecking "All displays" leaves every display selected;
                // the user then unchecks the ones they don't want.
                appState.displaySelection = isOn
                    ? .allDisplays
                    : .only(Set(appState.availableDisplays.map(\.id)))
            }
        )
    }

    private func binding(for display: DisplayInfo) -> Binding<Bool> {
        Binding(
            get: { appState.displaySelection.includes(display) },
            set: { isOn in
                appState.displaySelection = appState.displaySelection.setting(
                    display,
                    enabled: isOn,
                    among: appState.availableDisplays
                )
            }
        )
    }

    /// With a single music app installed there's nothing to choose, so the
    /// picker stays out of the way — unless the pinned source has since
    /// been uninstalled, in which case it's the only way back.
    private var showsSourcePicker: Bool {
        if appState.availableSources.count > 1 { return true }
        if case .pinned(let sourceID) = appState.sourceSelection {
            return !appState.availableSources.contains { $0.id == sourceID }
        }
        return false
    }
}

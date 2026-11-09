import SwiftUI
import AVFoundation

@main
struct LunkAlarmApp: App {
    @State private var store = AlarmStore()
    var body: some Scene {
        WindowGroup { AlarmRootView(store: store) }
    }
}

private struct AlarmRootView: View {
    let store: AlarmStore
    @Environment(\.scenePhase) private var scenePhase
    private var themedContent: some View {
        ContentView(store: store)
            .preferredColorScheme(store.theme.isLight ? .light : .dark)
            .tint(store.theme.accent)
    }
    var body: some View {
        themedContent
            .task { await store.observeAlarms() }
            .task { await store.observeAuthorization() }
            .onChange(of: scenePhase, initial: true) { _, phase in sceneChanged(phase) }
            .onChange(of: store.state.settings) { _, _ in store.saveSettings() }
            .onReceive(NotificationCenter.default.publisher(for: .lunkAlarmIntent)) { _ in store.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification), perform: handleInterruption)
    }
    private func sceneChanged(_ phase: ScenePhase) {
        store.setActive(phase == .active, backgrounded: phase == .background)
    }
    private func handleInterruption(_ note: Notification) {
        guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              type == AVAudioSession.InterruptionType.ended.rawValue else { return }
        guard let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
        let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
        if options.contains(.shouldResume) { store.resumeAudioAfterInterruption() }
    }
}

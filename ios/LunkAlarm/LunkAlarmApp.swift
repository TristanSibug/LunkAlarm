import SwiftUI
import AVFoundation

@main
struct LunkAlarmApp: App {
    @State private var store = AlarmStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .preferredColorScheme(store.theme.isLight ? .light : .dark)
                .tint(store.theme.accent)
                .task { await store.observeAlarms() }
                .task { await store.observeAuthorization() }
                .onChange(of: scenePhase) { _, phase in store.setActive(phase == .active) }
                .onChange(of: store.state.settings) { _, _ in store.saveSettings() }
                .onReceive(NotificationCenter.default.publisher(for: .lunkAlarmIntent)) { _ in store.refresh() }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
                    guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          type == AVAudioSession.InterruptionType.ended.rawValue,
                          let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                          AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume),
                          store.ringing != nil else { return }
                    store.sound.resumeAfterInterruption()
                }
        }
    }
}

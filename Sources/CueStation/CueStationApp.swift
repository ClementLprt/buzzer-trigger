import SwiftUI

@main
struct CueStationApp: App {
    @StateObject private var show = ShowController()
    @StateObject private var buzzer = BuzzerInput()

    var body: some Scene {
        WindowGroup("Cue Station") {
            ContentView()
                .environmentObject(show)
                .environmentObject(buzzer)
                .frame(minWidth: 1150, minHeight: 760)
                .onAppear { buzzer.show = show }
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            CuesView().tabItem { Text("Cues") }
            DiffusionView().tabItem { Text("Diffusion") }
            EditorView().tabItem { Text("Sons") }
            SettingsView().tabItem { Text("Réglages") }
            GuideView().tabItem { Text("Mode d'emploi") }
        }
        .padding(12)
    }
}

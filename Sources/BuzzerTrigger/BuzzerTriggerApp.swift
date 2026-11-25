import SwiftUI

@main
struct BuzzerTriggerApp: App {
    @StateObject private var engine = TriggerEngine()
    @StateObject private var show = ShowController()

    var body: some Scene {
        WindowGroup("Buzzer Trigger") {
            ContentView()
                .environmentObject(engine)
                .environmentObject(show)
                .frame(minWidth: 1100, minHeight: 760)
                .onAppear {
                    engine.show = show
                    show.logger = { [weak engine] text in engine?.addLog(text) }
                }
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            OperationView().tabItem { Text("Buzzer") }
            DiffusionView().tabItem { Text("Diffusion") }
            EditorView().tabItem { Text("Éditeur de sons") }
            WiringView().tabItem { Text("Tuto câblage") }
        }
        .padding(12)
    }
}

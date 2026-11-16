import SwiftUI

@main
struct BuzzerTriggerApp: App {
    @StateObject private var engine = TriggerEngine()

    var body: some Scene {
        WindowGroup("Buzzer Trigger") {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 900, minHeight: 720)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            OperationView().tabItem { Text("Exploitation") }
            WiringView().tabItem { Text("Tuto câblage") }
        }
        .padding(12)
    }
}

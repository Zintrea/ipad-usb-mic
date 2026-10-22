import SwiftUI

@main
struct IpadMicApp: App {
    // เก็บ server ไว้ที่ระดับแอป เพื่อให้มีอายุยาวกว่า view
    @StateObject private var server = MicServer()
    @StateObject private var tones = Tones()

    var body: some Scene {
        WindowGroup {
            ContentView(server: server, tones: tones)
        }
    }
}

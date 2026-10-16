import SwiftUI

struct ContentView: View {
    @ObservedObject var server: SineServer

    // ใช้สีของระบบทั้งหมด เพื่อให้โหมดมืด/สว่างทำงานเอง
    private var dotColor: Color {
        switch server.state {
        case .stopped: return .gray
        case .waiting: return .yellow
        case .streaming: return .green
        }
    }

    private var statusText: String {
        switch server.state {
        case .stopped: return "หยุดอยู่"
        case .waiting: return "รอคอมต่อ..."
        case .streaming: return "กำลังส่งเสียง"
        }
    }

    var body: some View {
        VStack(spacing: 32) {
            Text("iPad Mic")
                .font(.largeTitle.bold())

            HStack(spacing: 12) {
                Circle().fill(dotColor).frame(width: 20, height: 20)
                Text(statusText).font(.title2)
            }

            Button {
                if server.state == .stopped { server.start() } else { server.stop() }
            } label: {
                Text(server.state == .stopped ? "START" : "STOP")
                    .font(.system(size: 36, weight: .bold))
                    .frame(maxWidth: 360, minHeight: 100)
            }
            .buttonStyle(.borderedProminent)
            .tint(server.state == .stopped ? .blue : .red)

            Text("โหมดทดสอบ: 440 Hz")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

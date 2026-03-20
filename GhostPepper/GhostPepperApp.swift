import SwiftUI

@main
struct GhostPepperApp: App {
    @StateObject private var appState = AppState()
    @State private var hasInitialized = false
    @State private var pulseOn = true

    private let pulseTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Group {
                switch appState.status {
                case .recording:
                    Image("MenuBarIcon")
                        .renderingMode(.template)
                        .foregroundStyle(pulseOn ? .red : .red.opacity(0.3))
                        .onReceive(pulseTimer) { _ in
                            if appState.status == .recording {
                                pulseOn.toggle()
                            }
                        }
                case .loading:
                    Image(systemName: "ellipsis.circle")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.orange)
                case .error:
                    Image(systemName: "exclamationmark.triangle")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.yellow)
                default:
                    Image("MenuBarIcon")
                        .renderingMode(.template)
                }
            }
            .onAppear {
                guard !hasInitialized else { return }
                hasInitialized = true
                Task {
                    await appState.initialize()
                }
            }
        }
    }
}

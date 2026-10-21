import SwiftUI

@main struct OnDeviceApp: App {
    @StateObject private var conversation = ConversationController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ConversationView(controller: conversation)
                .preferredColorScheme(.dark)
                .task { conversation.prepare() }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { conversation.interrupt() }
                }
        }
    }
}

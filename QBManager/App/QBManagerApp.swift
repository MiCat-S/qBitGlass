import SwiftUI

@main
struct QBManagerApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                .fontDesign(.serif)
                .onOpenURL { model.handleOpen($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            model.setSceneActive(phase == .active)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            ServerListView()
                .navigationDestination(for: UUID.self) { id in
                    if let store = model.session(for: id) {
                        TorrentListView(store: store)
                    } else {
                        ContentUnavailableView("找不到伺服器", systemImage: "server.rack")
                    }
                }
        }
    }
}

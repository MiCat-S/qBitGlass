import SwiftUI

struct ServerListView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var sheetNS
    @State private var editing: ServerEditTarget?
    @State private var showSettings = false
    @State private var pendingDelete: ServerConfig?

    var body: some View {
        Group {
            if model.servers.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(model.servers) { server in
                        Button {
                            model.open(server.id)
                        } label: {
                            ServerRow(server: server)
                        }
                        .tint(.primary)
                        .listRowBackground(Theme.card)
                        .swipeActions(edge: .trailing) {
                            Button("刪除", systemImage: "trash") { pendingDelete = server }
                                .tint(.red)
                            Button("編輯", systemImage: "pencil") { editing = ServerEditTarget(server: server, isNew: false) }
                                .tint(Theme.accent)
                        }
                        .contextMenu {
                            Button("編輯", systemImage: "pencil") { editing = ServerEditTarget(server: server, isNew: false) }
                            Button("刪除", systemImage: "trash", role: .destructive) { pendingDelete = server }
                        }
                        // 確認框掛在這一列上，從被刪除的伺服器彈出
                        .confirmationDialog("刪除伺服器「\(server.displayName)」？",
                                            isPresented: deleteBinding(server), titleVisibility: .visible) {
                            Button("刪除", role: .destructive) { model.delete(server) }
                        }
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
                .themedList()
            }
        }
        .navigationTitle("qBittorrent")
        .toolbarItem(.topBarLeading, source: .settings, in: sheetNS) {
            Button("設定", systemImage: "gearshape") { showSettings = true }
        }
        .toolbarItem(.topBarTrailing, source: .addServer, in: sheetNS) {
            Button("新增伺服器", systemImage: "plus") {
                editing = ServerEditTarget(server: ServerConfig(), isNew: true, source: .addServer)
            }
        }
        // isNew 在開啟時就決定，避免儲存後關閉動畫中標題變成「編輯伺服器」
        .sheet(item: $editing) { target in
            ServerEditView(server: target.server, isNew: target.isNew).zoomTransition(from: target.source, in: sheetNS)
        }
        .sheet(isPresented: $showSettings) { SettingsView().zoomTransition(from: .settings, in: sheetNS) }
    }

    private func deleteBinding(_ server: ServerConfig) -> Binding<Bool> {
        Binding(get: { pendingDelete?.id == server.id }, set: { if !$0 { pendingDelete = nil } })
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("尚未新增伺服器", systemImage: "server.rack")
        } description: {
            Text("新增你的 qBittorrent WebUI 位址，例如\nhttp://192.168.1.10:8080")
        } actions: {
            Button {
                editing = ServerEditTarget(server: ServerConfig(), isNew: true, source: .emptyAddServer)
            } label: {
                Label("新增伺服器", systemImage: "plus")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .glassButton(prominent: true)
            .sheetSource(.emptyAddServer, in: sheetNS)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

private struct ServerRow: View {
    let server: ServerConfig

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .glass(Circle(), tint: Theme.accent.opacity(0.15))
            VStack(alignment: .leading, spacing: 3) {
                Text(server.displayName)
                    .font(.headline)
                Text(server.baseURL?.absoluteString ?? server.url)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Text(server.authMode.label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

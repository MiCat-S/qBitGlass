import SwiftUI

struct ServerListView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: ServerConfig?
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
                            Button("編輯", systemImage: "pencil") { editing = server }
                                .tint(Theme.accent)
                        }
                        .contextMenu {
                            Button("編輯", systemImage: "pencil") { editing = server }
                            Button("刪除", systemImage: "trash", role: .destructive) { pendingDelete = server }
                        }
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
                .themedList()
            }
        }
        .navigationTitle("qBittorrent")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("設定", systemImage: "gearshape") { showSettings = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("新增伺服器", systemImage: "plus") { editing = ServerConfig() }
            }
        }
        .sheet(item: $editing) { server in
            ServerEditView(server: server, isNew: model.server(server.id) == nil)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .confirmationDialog("刪除伺服器「\(pendingDelete?.displayName ?? "")」？",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("刪除", role: .destructive) {
                if let s = pendingDelete { model.delete(s) }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("尚未新增伺服器", systemImage: "server.rack")
        } description: {
            Text("新增你的 qBittorrent WebUI 位址，例如\nhttp://192.168.1.10:8080")
        } actions: {
            Button {
                editing = ServerConfig()
            } label: {
                Label("新增伺服器", systemImage: "plus")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .glassButton(prominent: true)
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

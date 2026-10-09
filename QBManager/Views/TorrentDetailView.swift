import SwiftUI

struct TorrentDetailView: View {
    let store: SessionStore
    let hash: String

    @Environment(\.dismiss) private var dismiss
    @Namespace private var sheetNS

    enum Tab: String, CaseIterable, Identifiable {
        case info = "概覽", files = "檔案", trackers = "Tracker"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .info
    @State private var files: [TorrentFile]?
    @State private var trackers: [TorrentTracker]?
    @State private var props: [String: JSONValue] = [:]
    @State private var loadError: String?
    @State private var pending: PendingAction?
    @State private var categoryTarget: HashList?
    @State private var tagTarget: HashList?
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showLocation = false
    @State private var locationText = ""

    var body: some View {
        Group {
            if let t = store.torrents[hash] {
                List {
                    // 放在 section header 中，避免 List cell 背景出現在玻璃卡片後方
                    Section {
                    } header: {
                        VStack(spacing: 18) {
                            header(t)
                            Picker("分頁", selection: $tab) {
                                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        .foregroundStyle(.primary)
                        .textCase(nil)
                        .padding(.top, 8)
                    }

                    if let loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    switch tab {
                    case .info: infoSections(t)
                    case .files: filesSection
                    case .trackers: trackersSection
                    }
                }
                .themedList()
                .navigationTitle(t.name)
                .toolbarItem(.topBarTrailing, source: .detailMore, in: sheetNS) { moreMenu(t) }
                .alert("重新命名", isPresented: $showRename) {
                    TextField("名稱", text: $renameText)
                    Button("確定") {
                        let name = renameText.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        Task { await store.run { try await $0.rename(hash, name) } }
                    }
                    Button("取消", role: .cancel) {}
                }
                .alert("變更儲存位置", isPresented: $showLocation) {
                    TextField("路徑", text: $locationText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("移動") {
                        let path = locationText.trimmingCharacters(in: .whitespaces)
                        guard !path.isEmpty else { return }
                        Task { await store.run { try await $0.setLocation([hash], path) } }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("檔案會被移動到伺服器上的新路徑")
                }
            } else {
                ContentUnavailableView("種子已不存在", systemImage: "questionmark.folder")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $categoryTarget) { target in
            CategoryPickerView(store: store, hashes: target.hashes).zoomTransition(from: target.source, in: sheetNS)
        }
        .sheet(item: $tagTarget) { target in
            TagEditorView(store: store, hashes: target.hashes).zoomTransition(from: target.source, in: sheetNS)
        }
        .actionErrorAlert(store, isActive: categoryTarget == nil && tagTarget == nil)
        .onAppear { store.acquire() }
        .onDisappear { store.release() }
        .task(id: tab) { await poll(tab) }
    }

    // MARK: - 頂部狀態卡片

    private func header(_ t: Torrent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(t.state.label, systemImage: t.state.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(t.state.color)
                Spacer()
                Text(Fmt.percent(t.progress))
                    .font(.system(.title, design: .serif).weight(.semibold).monospacedDigit())
            }
            ProgressView(value: min(max(t.progress, 0), 1))
                .tint(t.state.color)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)
            HStack {
                Label(Fmt.speed(t.dlspeed), systemImage: "arrow.down").foregroundStyle(.blue)
                Spacer()
                Label(Fmt.speed(t.upspeed), systemImage: "arrow.up").foregroundStyle(.green)
                Spacer()
                Label(Fmt.eta(t.eta), systemImage: "clock").foregroundStyle(Theme.secondaryText)
            }
            .labelStyle(TightLabelStyle())
            .font(.footnote.weight(.medium).monospacedDigit())

            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    if t.state.isStopped {
                        pill("啟動", "play.fill", prominent: true) { await store.start([hash]) }
                    } else {
                        pill("停止", "stop.fill") { await store.stop([hash]) }
                    }
                    // 強制啟動開啟時以品牌色實心玻璃顯示
                    pill("強制", "bolt.fill", prominent: t.forceStart) {
                        await store.forceStart([hash], !t.forceStart)
                    }
                    // 確認框從被點的膠囊按鈕彈出
                    pill("校驗", "checkmark.arrow.trianglehead.counterclockwise") { confirm(.recheck, at: .pillRecheck) }
                        .confirmTorrentAction($pending, anchor: .pillRecheck, store: store)
                    pill("刪除", "trash.fill", tint: .red) { confirm(.delete, at: .pillDelete) }
                        .confirmTorrentAction($pending, anchor: .pillDelete, store: store, onDone: closeIfDeleted)
                }
            }
        }
        .padding(18)
        // 卡片屬於內容層用實色；玻璃只用在上面的控制按鈕（Apple 建議避免玻璃疊玻璃）
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func pill(_ title: String, _ symbol: String, prominent: Bool = false, tint: Color? = nil,
                      action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(tint ?? .primary))
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .glassButton(prominent: prominent)
        .accessibilityLabel(title)
    }

    // MARK: - 概覽

    @ViewBuilder
    private func infoSections(_ t: Torrent) -> some View {
        Section("傳輸") {
            info("已下載", Fmt.bytes(t.downloaded))
            info("已上傳", Fmt.bytes(t.uploaded))
            info("分享率", Fmt.ratio(t.ratio))
            info("下載限速", Fmt.limit(t.dlLimit))
            info("上傳限速", Fmt.limit(t.upLimit))
            info("種子", "\(t.numSeeds)（共 \(t.numComplete)）")
            info("下載者", "\(t.numLeechs)（共 \(t.numIncomplete)）")
            if t.availability >= 0 { info("可用性", String(format: "%.3f", t.availability)) }
            if let c = props["nb_connections"]?.int { info("連線數", "\(c)") }
            if let w = props["total_wasted"]?.int, w > 0 { info("浪費", Fmt.bytes(w)) }
        }
        Section("資訊") {
            info("大小", Fmt.bytes(t.size))
            if t.totalSize != t.size { info("總大小", Fmt.bytes(t.totalSize)) }
            info("分類", t.category.isEmpty ? "—" : t.category)
            info("標籤", t.tags.isEmpty ? "—" : t.tags.joined(separator: ", "))
            info("加入時間", Fmt.date(t.addedOn))
            info("完成時間", Fmt.date(t.completionOn))
            info("活動時間", Fmt.duration(t.timeActive))
            info("做種時間", Fmt.duration(t.seedingTime))
            info("最後活動", Fmt.date(t.lastActivity))
            if let n = props["pieces_num"]?.int, let s = props["piece_size"]?.int {
                info("區塊", "\(props["pieces_have"]?.int ?? 0) / \(n) × \(Fmt.bytes(s))")
            }
            if let d = props["creation_date"]?.int, d > 0 { info("建立時間", Fmt.date(d)) }
            if let by = props["created_by"]?.string, !by.isEmpty { info("建立工具", by) }
            info("私有種子", t.isPrivate ? "是" : "否")
            info("依序下載", t.seqDl ? "是" : "否")
            info("首尾區塊優先", t.firstLastPiecePrio ? "是" : "否")
            info("自動管理", t.autoTmm ? "是" : "否")
        }
        Section("位置") {
            copyable("儲存路徑", t.savePath)
            if !t.contentPath.isEmpty { copyable("內容路徑", t.contentPath) }
            copyable("Hash", t.hash)
            if !t.tracker.isEmpty { copyable("目前 Tracker", t.tracker) }
            if let comment = props["comment"]?.string, !comment.isEmpty { copyable("註解", comment) }
        }
    }

    private func info(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .listRowBackground(Theme.card)
    }

    private func copyable(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
            Text(value).font(.footnote).textSelection(.enabled)
        }
        .listRowBackground(Theme.card)
        .contextMenu {
            Button("拷貝", systemImage: "doc.on.doc") { UIPasteboard.general.string = value }
        }
    }

    // MARK: - 檔案

    @ViewBuilder
    private var filesSection: some View {
        if let files {
            Section {
                ForEach(files) { f in
                    // 點一下檔案就從該列彈出優先順序選單，目前的優先順序會打勾
                    Menu {
                        Picker("下載優先順序", selection: Binding(get: { f.priority }, set: { p in
                            Task { await setPriority([f.index], p) }
                        })) {
                            ForEach(TorrentFile.priorities, id: \.value) { p in Text(p.label).tag(p.value) }
                        }
                    } label: {
                        FileRow(file: f)
                    }
                    .tint(.primary)
                    .listRowBackground(Theme.card)
                }
            } header: {
                HStack {
                    Text("\(files.count) 個檔案")
                    Spacer()
                    Menu("全部設為") {
                        ForEach(TorrentFile.priorities, id: \.value) { p in
                            Button(p.label) { Task { await setPriority(files.map(\.index), p.value) } }
                        }
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            } footer: {
                Text("點選檔案可調整下載優先順序")
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
        }
    }

    private func setPriority(_ ids: [Int], _ priority: Int) async {
        let ok = await store.run { try await $0.setFilePriority(hash, ids: ids, priority: priority) }
        if ok { await load(.files) }
    }

    // MARK: - Tracker

    @ViewBuilder
    private var trackersSection: some View {
        if let trackers {
            Section("\(trackers.count) 個 Tracker") {
                ForEach(trackers) { tr in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(tr.url)
                                .font(.footnote.weight(.medium))
                                .lineLimit(2)
                                .textSelection(.enabled)
                            Spacer()
                            Text(tr.statusLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(trackerColor(tr.status))
                        }
                        if tr.isRealTracker {
                            Text("做種 \(tr.seeds) · 下載 \(tr.leeches) · 用戶 \(tr.peers) · 已完成 \(tr.downloaded)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Theme.secondaryText)
                        }
                        if !tr.message.isEmpty {
                            Text(tr.message).font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
        }
    }

    private func trackerColor(_ status: Int) -> Color {
        switch status {
        case 2: return .green
        case 3: return .blue
        case 4: return .red
        default: return Theme.secondaryText
        }
    }

    // MARK: - 工具列

    private func moreMenu(_ t: Torrent) -> some View {
        Menu {
            Button("重新匯報", systemImage: "antenna.radiowaves.left.and.right") {
                Task { await store.reannounce([hash]) }
            }
            Button("設定分類…", systemImage: "folder") { categoryTarget = HashList(hashes: [hash], source: .detailMore) }
            Button("管理標籤…", systemImage: "tag") { tagTarget = HashList(hashes: [hash], source: .detailMore) }
            Button("重新命名…", systemImage: "pencil") {
                renameText = t.name
                showRename = true
            }
            Button("變更儲存位置…", systemImage: "folder.badge.gearshape") {
                locationText = t.savePath
                showLocation = true
            }
            Divider()
            Toggle(isOn: Binding(get: { t.seqDl }, set: { _ in Task { await store.toggleSequential([hash]) } })) {
                Label("依序下載", systemImage: "arrow.right.to.line")
            }
            Toggle(isOn: Binding(get: { t.firstLastPiecePrio }, set: { _ in Task { await store.toggleFirstLast([hash]) } })) {
                Label("首尾區塊優先", systemImage: "arrow.left.and.right")
            }
            Divider()
            Button("拷貝磁力連結", systemImage: "link") { UIPasteboard.general.string = t.magnetURI }
            Button("拷貝 Hash", systemImage: "number") { UIPasteboard.general.string = t.hash }
            Divider()
            Button("刪除…", systemImage: "trash", role: .destructive) { confirm(.delete, at: .detailMore) }
        } label: {
            Label("更多", systemImage: "ellipsis.circle")
        }
        // 從選單刪除時，確認框從右上的「更多」按鈕彈出
        .confirmTorrentAction($pending, anchor: .detailMore, store: store, onDone: closeIfDeleted)
    }

    private func confirm(_ kind: PendingAction.Kind, at anchor: PendingAction.Anchor) {
        pending = PendingAction(kind: kind, hashes: [hash], anchor: anchor)
    }

    private func closeIfDeleted(_ action: PendingAction, _ ok: Bool) {
        if ok, action.kind == .delete { dismiss() }
    }

    // MARK: - 載入

    private func poll(_ tab: Tab) async {
        while !Task.isCancelled {
            await load(tab)
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func load(_ tab: Tab) async {
        guard let client = store.client else { return }
        do {
            switch tab {
            case .info: props = try await client.properties(hash)
            case .files: files = try await client.files(hash)
            case .trackers: trackers = try await client.trackers(hash)
            }
            loadError = nil
        } catch {
            if !SessionStore.isCancellation(error) { loadError = SessionStore.describe(error) }
        }
    }

}

private struct FileRow: View {
    let file: TorrentFile

    var body: some View {
        let parts = file.name.split(separator: "/")
        VStack(alignment: .leading, spacing: 5) {
            Text(parts.last.map(String.init) ?? file.name)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
            if parts.count > 1 {
                Text(parts.dropLast().joined(separator: "/"))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            ProgressView(value: min(max(file.progress, 0), 1))
                .tint(file.priority == 0 ? .gray : Theme.accent)
            HStack {
                Text("\(Fmt.percent(file.progress)) · \(Fmt.bytes(file.size))")
                Spacer()
                Text(file.priorityLabel)
                    .foregroundStyle(file.priority == 0 ? .red : (file.priority >= 6 ? Theme.accent : Theme.secondaryText))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 2)
    }
}

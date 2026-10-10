import SwiftUI

struct TorrentRoute: Hashable {
    var hash: String
}

/// 一組要套用操作的種子（用於 sheet）；source 是 sheet 展開的來源按鈕
struct HashList: Identifiable {
    let id = UUID()
    var hashes: [String]
    var source: SheetSource?
}

struct TorrentListView: View {
    @Environment(AppModel.self) private var model
    @Bindable var store: SessionStore
    @Namespace private var sheetNS

    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var showFilter = false
    @State private var addItem: IncomingTorrent?
    @State private var addFromButton = false
    @State private var pending: PendingAction?
    @State private var categoryTarget: HashList?
    @State private var tagTarget: HashList?
    @State private var serverTarget: ServerEditTarget?

    private var isEditing: Bool { editMode.isEditing }

    /// 清單是否在最上層（沒有推入詳情頁、也沒有開著 sheet），只有這時才由清單顯示錯誤
    private var isFrontmost: Bool {
        model.path.count <= 1 && !showFilter && addItem == nil && categoryTarget == nil
            && tagTarget == nil && serverTarget == nil
    }

    var body: some View {
        let visible = store.visibleTorrents
        let selected = visible.filter { selection.contains($0.hash) }.map(\.hash)

        browseToolbar(
            content(visible)
                .navigationTitle(isEditing ? "已選 \(selected.count) 項" : store.server.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(isEditing)
                .toolbar { editingToolbar(visible: visible, selected: selected) }
        )
        .glassBar(edge: .top) {
            if store.hasLoaded { StatusChips(store: store) }
        }
        .glassBar(edge: .bottom) {
            if store.hasLoaded {
                if isEditing {
                    actionBar(selected)
                } else {
                    StatsBar(store: store)
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: isEditing)
        .navigationDestination(for: TorrentRoute.self) { route in
            TorrentDetailView(store: store, hash: route.hash)
        }
        .sheet(isPresented: $showFilter) {
            FilterView(store: store).zoomTransition(from: .filter, in: sheetNS)
        }
        .sheet(item: $addItem) { item in
            AddTorrentView(store: store, prefill: item)
                .zoomTransition(from: addFromButton ? .addTorrent : nil, in: sheetNS)
        }
        .sheet(item: $categoryTarget) { target in
            CategoryPickerView(store: store, hashes: target.hashes).zoomTransition(from: target.source, in: sheetNS)
        }
        .sheet(item: $tagTarget) { target in
            TagEditorView(store: store, hashes: target.hashes).zoomTransition(from: target.source, in: sheetNS)
        }
        .sheet(item: $serverTarget) { target in
            ServerEditView(server: target.server, isNew: false).zoomTransition(from: target.source, in: sheetNS)
        }
        .actionErrorAlert(store, isActive: isFrontmost)
        .onAppear {
            store.acquire()
            model.activeServerID = store.server.id
            consumeIncoming()
        }
        .onDisappear { store.release() }
        .onChange(of: model.incoming) { _, _ in consumeIncoming() }
        .onChange(of: isEditing) { _, editing in if !editing { selection.removeAll() } }
    }

    // MARK: - 內容

    @ViewBuilder
    private func content(_ visible: [Torrent]) -> some View {
        if !store.hasLoaded {
            switch store.state {
            case .failed(let message):
                ContentUnavailableView {
                    Label("無法連線", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(store.willRetry ? "\(message)\n稍後會自動重試" : message)
                } actions: {
                    Button("重試") { Task { await store.reconnect() } }
                        .glassButton(prominent: true)
                    // 連線失敗多半要改網址或帳密，直接在這裡編輯，不必退回伺服器清單
                    Button("編輯伺服器") { serverTarget = ServerEditTarget(server: store.server, isNew: false) }
                        .glassButton()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background.ignoresSafeArea())
            default:
                ProgressView("連線中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background.ignoresSafeArea())
            }
        } else {
            List(selection: $selection) {
                if let err = store.syncError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .listRowBackground(Color.clear)
                        .selectionDisabled()
                }
                ForEach(visible) { t in
                    row(t)
                }
            }
            .listStyle(.plain)
            .themedList()
            .environment(\.editMode, $editMode)
            .searchable(text: $store.filter.search, prompt: "搜尋名稱或 Hash")
            .refreshable { await store.manualRefresh() }
            .overlay {
                if visible.isEmpty {
                    ContentUnavailableView {
                        Label(store.torrents.isEmpty ? "沒有種子" : "沒有符合條件的種子",
                              systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        if store.filter.isFiltering || !store.filter.search.isEmpty {
                            Text("試試調整篩選條件")
                        }
                    } actions: {
                        if store.filter.isFiltering {
                            Button("清除篩選") {
                                store.filter = TorrentFilter(sort: store.filter.sort, ascending: store.filter.ascending)
                            }
                            .glassButton()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ t: Torrent) -> some View {
        Group {
            if isEditing {
                TorrentRow(torrent: t)
            } else {
                NavigationLink(value: TorrentRoute(hash: t.hash)) {
                    TorrentRow(torrent: t)
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.secondaryText.opacity(0.25))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("刪除", systemImage: "trash") { confirm(.delete, [t.hash], at: .row(t.hash)) }
                .tint(.red)
            if t.state.isStopped {
                Button("啟動", systemImage: "play.fill") { Task { await store.start([t.hash]) } }
                    .tint(.green)
            } else {
                Button("停止", systemImage: "stop.fill") { Task { await store.stop([t.hash]) } }
                    .tint(.gray)
            }
        }
        .swipeActions(edge: .leading) {
            Button(t.forceStart ? "取消強制" : "強制啟動", systemImage: "bolt.fill") {
                Task { await store.forceStart([t.hash], !t.forceStart) }
            }
            .tint(Theme.accent)
        }
        .contextMenu {
            // 只顯示目前可用的那一個，與左滑按鈕一致
            if t.state.isStopped {
                Button("啟動", systemImage: "play") { Task { await store.start([t.hash]) } }
            } else {
                Button("停止", systemImage: "stop") { Task { await store.stop([t.hash]) } }
            }
            Button(t.forceStart ? "取消強制啟動" : "強制啟動", systemImage: "bolt") {
                Task { await store.forceStart([t.hash], !t.forceStart) }
            }
            Divider()
            moreActions([t.hash], anchor: .row(t.hash))
            Divider()
            Button("刪除…", systemImage: "trash", role: .destructive) {
                confirm(.delete, [t.hash], at: .row(t.hash))
            }
        }
        // 確認框掛在這一列上，從被操作的那一列彈出
        .confirmTorrentAction($pending, anchor: .row(t.hash), store: store) { action, ok in
            if ok, action.kind == .delete { selection.subtract(action.hashes) }
        }
    }

    /// 單選與批次共用的「更多」操作；anchor 是確認框要掛的位置
    @ViewBuilder
    private func moreActions(_ hashes: [String], anchor: PendingAction.Anchor) -> some View {
        let source: SheetSource? = anchor == .barMore ? .barMore : nil
        Button("重新校驗…", systemImage: "checkmark.arrow.trianglehead.counterclockwise") {
            confirm(.recheck, hashes, at: anchor)
        }
        Button("重新匯報", systemImage: "antenna.radiowaves.left.and.right") {
            Task { await store.reannounce(hashes) }
        }
        Button("設定分類…", systemImage: "folder") { categoryTarget = HashList(hashes: hashes, source: source) }
        Button("管理標籤…", systemImage: "tag") { tagTarget = HashList(hashes: hashes, source: source) }
        Menu {
            Button("移到最前", systemImage: "arrow.up.to.line") { Task { await store.queue(.top, hashes) } }
            Button("上移", systemImage: "arrow.up") { Task { await store.queue(.up, hashes) } }
            Button("下移", systemImage: "arrow.down") { Task { await store.queue(.down, hashes) } }
            Button("移到最後", systemImage: "arrow.down.to.line") { Task { await store.queue(.bottom, hashes) } }
        } label: {
            Label("佇列", systemImage: "list.number")
        }
        Menu {
            Button("切換依序下載", systemImage: "arrow.right.to.line") { Task { await store.toggleSequential(hashes) } }
            Button("切換首尾區塊優先", systemImage: "arrow.left.and.right") { Task { await store.toggleFirstLast(hashes) } }
        } label: {
            Label("下載選項", systemImage: "slider.horizontal.3")
        }
        Button("複製磁力連結", systemImage: "link") {
            UIPasteboard.general.string = hashes.compactMap { store.torrents[$0]?.magnetURI }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
    }

    private func confirm(_ kind: PendingAction.Kind, _ hashes: [String], at anchor: PendingAction.Anchor) {
        pending = PendingAction(kind: kind, hashes: hashes, anchor: anchor)
    }

    // MARK: - 工具列

    /// 選取模式：左上全選／全不選，右上依條件選取，完成離開
    @ToolbarContentBuilder
    private func editingToolbar(visible: [Torrent], selected: [String]) -> some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .topBarLeading) {
                let allSelected = !visible.isEmpty && selected.count == visible.count
                Button(allSelected ? "全不選" : "全選") {
                    if allSelected {
                        selection.removeAll()
                    } else {
                        selection = Set(visible.map(\.hash))
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("反選", systemImage: "circle.lefthalf.filled") {
                        selection = Set(visible.map(\.hash)).subtracting(selection)
                    }
                    Divider()
                    Button("選取已停止", systemImage: "pause.circle") {
                        selection = Set(visible.filter { $0.state.isStopped }.map(\.hash))
                    }
                    Button("選取已完成", systemImage: "checkmark.seal") {
                        selection = Set(visible.filter { $0.state.isCompleted }.map(\.hash))
                    }
                    Button("選取錯誤", systemImage: "exclamationmark.triangle") {
                        selection = Set(visible.filter { $0.state.isErrored }.map(\.hash))
                    }
                } label: {
                    Label("選取", systemImage: "checklist")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { editMode = .inactive }
            }
        }
    }

    /// 一般模式的工具列；iOS 26+ 各按鈕同時是 sheet 的轉場來源，篩選、新增等畫面會從按鈕展開
    @ViewBuilder
    private func browseToolbar(_ base: some View) -> some View {
        let shown = !isEditing && store.hasLoaded
        if #available(iOS 26.0, *) {
            base.toolbar {
                if shown {
                    ToolbarItem(placement: .topBarTrailing) { filterButton }
                        .matchedTransitionSource(id: SheetSource.filter, in: sheetNS)
                    ToolbarItem(placement: .topBarTrailing) { addButton }
                        .matchedTransitionSource(id: SheetSource.addTorrent, in: sheetNS)
                    ToolbarItem(placement: .topBarTrailing) { moreMenu }
                        .matchedTransitionSource(id: SheetSource.listMore, in: sheetNS)
                }
            }
        } else {
            base.toolbar {
                if shown {
                    ToolbarItem(placement: .topBarTrailing) { filterButton }
                    ToolbarItem(placement: .topBarTrailing) { addButton }
                    ToolbarItem(placement: .topBarTrailing) { moreMenu }
                }
            }
        }
    }

    private var filterButton: some View {
        Button {
            showFilter = true
        } label: {
            Label("篩選", systemImage: store.filter.isFiltering
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    private var addButton: some View {
        Button("新增", systemImage: "plus") {
            addFromButton = true
            addItem = IncomingTorrent()
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("選取", systemImage: "checkmark.circle") { editMode = .active }
            Menu {
                Picker("排序", selection: $store.filter.sort) {
                    ForEach(SortField.allCases) { Text($0.label).tag($0) }
                }
                Picker("方向", selection: $store.filter.ascending) {
                    Text("遞減").tag(false)
                    Text("遞增").tag(true)
                }
            } label: {
                Label("排序：\(store.filter.sort.label)", systemImage: "arrow.up.arrow.down")
            }
            Divider()
            Button(store.serverState.altSpeedEnabled ? "關閉替代速度限制" : "開啟替代速度限制",
                   systemImage: "tortoise") {
                Task { await store.toggleAltSpeed() }
            }
            Button("全部啟動", systemImage: "play") { Task { await store.start(["all"]) } }
            Button("全部停止", systemImage: "stop") { Task { await store.stop(["all"]) } }
            Divider()
            Button("重新連線", systemImage: "arrow.clockwise") { Task { await store.reconnect() } }
            Button("編輯伺服器…", systemImage: "pencil") {
                serverTarget = ServerEditTarget(server: store.server, isNew: false, source: .listMore)
            }
        } label: {
            Label("更多", systemImage: "ellipsis.circle")
        }
    }

    // MARK: - 批次操作列（Liquid Glass 浮動列）

    private func actionBar(_ selected: [String]) -> some View {
        let disabled = selected.isEmpty
        let allForced = !selected.isEmpty && selected.allSatisfy { store.torrents[$0]?.forceStart == true }
        return GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                ActionButton(title: "啟動", symbol: "play.fill", disabled: disabled) {
                    Task { await store.start(selected) }
                }
                ActionButton(title: "停止", symbol: "stop.fill", disabled: disabled) {
                    Task { await store.stop(selected) }
                }
                ActionButton(title: allForced ? "取消強制" : "強制", symbol: "bolt.fill",
                             tint: Theme.accent, disabled: disabled) {
                    Task { await store.forceStart(selected, !allForced) }
                }
                ActionButton(title: "刪除", symbol: "trash.fill", tint: .red, disabled: disabled) {
                    confirm(.delete, selected, at: .barDelete)
                }
                // 從刪除鈕往上彈出；刪除成功後離開選取模式
                .confirmTorrentAction($pending, anchor: .barDelete, store: store) { _, ok in
                    if ok { editMode = .inactive }
                }
                Menu {
                    moreActions(selected, anchor: .barMore)
                } label: {
                    ActionLabel(title: "更多", symbol: "ellipsis")
                }
                .disabled(disabled)
                .opacity(disabled ? 0.4 : 1)
                .sheetSource(.barMore, in: sheetNS)
                .confirmTorrentAction($pending, anchor: .barMore, store: store)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassCapsule()
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - 其他

    private func consumeIncoming() {
        guard let item = model.incoming, model.activeServerID == store.server.id else { return }
        model.incoming = nil
        addFromButton = false
        addItem = item
    }
}

// MARK: - 子元件

private struct ActionLabel: View {
    let title: String
    let symbol: String
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(height: 22)
            Text(title)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .frame(minWidth: 54, minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct ActionButton: View {
    let title: String
    let symbol: String
    var tint: Color = .primary
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionLabel(title: title, symbol: symbol, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

/// 頂部狀態快速篩選（玻璃膠囊）
private struct StatusChips: View {
    @Bindable var store: SessionStore
    private let quick: [StatusFilter] = [.all, .downloading, .seeding, .completed, .stopped, .active, .stalled, .checking, .errored]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                GlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(quick) { status in
                            let count = store.count(status)
                            if status == .all || count > 0 || store.filter.status == status {
                                chip(status, count).id(status)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
            .scrollClipDisabled()
            // 選到半露在邊緣的膠囊，或從篩選面板改了狀態時，把它捲到看得見的位置
            .onChange(of: store.filter.status) { _, status in
                withAnimation(.smooth) { proxy.scrollTo(status, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(store.filter.status, anchor: .center) }
        }
    }

    private func chip(_ status: StatusFilter, _ count: Int) -> some View {
        let on = store.filter.status == status
        return Button {
            withAnimation(.smooth) { store.filter.status = status }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: status.symbol)
                    .font(.caption.weight(.semibold))
                Text(status.label)
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(on ? .white.opacity(0.85) : Theme.secondaryText)
            }
            .font(.subheadline.weight(on ? .semibold : .regular))
            .foregroundStyle(on ? .white : .primary)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassCapsule(tint: on ? Theme.accent : nil, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chip.\(status.rawValue)")
    }
}

/// 底部全域速度資訊（玻璃膠囊）
private struct StatsBar: View {
    let store: SessionStore

    var body: some View {
        let s = store.serverState
        HStack(spacing: 14) {
            Label(Fmt.speed(s.dlSpeed), systemImage: "arrow.down")
                .foregroundStyle(.blue)
            Label(Fmt.speed(s.upSpeed), systemImage: "arrow.up")
                .foregroundStyle(.green)
            if let free = s.freeSpace {
                Label(Fmt.bytes(free), systemImage: "internaldrive")
                    .foregroundStyle(Theme.secondaryText)
            }
            Button {
                Task { await store.toggleAltSpeed() }
            } label: {
                Image(systemName: "tortoise.fill")
                    .foregroundStyle(s.altSpeedEnabled ? Theme.accent : Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(s.altSpeedEnabled ? "關閉替代速度限制" : "開啟替代速度限制")
        }
        .font(.footnote.weight(.medium).monospacedDigit())
        .labelStyle(TightLabelStyle())
        .lineLimit(1)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .glassCapsule()
        .padding(.bottom, 6)
    }
}

struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

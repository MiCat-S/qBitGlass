import SwiftUI

// iOS 26 起確認框會以 popover 從「掛載它的元件」彈出，sheet 也能從觸發的按鈕展開。
// 所以確認框要掛在實際點擊的列或按鈕上，而不是整個畫面；sheet 則標記來源按鈕。

/// sheet 的轉場來源（iOS 26+ sheet 會從這些按鈕展開）
enum SheetSource: Hashable {
    case filter, addTorrent, listMore, barMore, detailMore
    case addServer, emptyAddServer, settings
}

/// 需要使用者確認的種子操作；anchor 決定確認框掛在哪個元件上
struct PendingAction {
    enum Kind { case delete, recheck }
    enum Anchor: Hashable {
        /// 清單中的某一列（左滑、長按選單）
        case row(String)
        /// 選取模式底部操作列
        case barDelete, barMore
        /// 詳情頁的膠囊按鈕與右上「更多」
        case pillDelete, pillRecheck, detailMore
    }

    var kind: Kind
    var hashes: [String]
    var anchor: Anchor
}

extension View {
    /// 在觸發元件上掛確認框；確認後執行操作，並回報是否成功
    func confirmTorrentAction(_ pending: Binding<PendingAction?>, anchor: PendingAction.Anchor, store: SessionStore,
                              onDone: @escaping (PendingAction, Bool) -> Void = { _, _ in }) -> some View {
        modifier(TorrentActionDialog(pending: pending, anchor: anchor, store: store, onDone: onDone))
    }

    /// 操作失敗提示。同一個 store 會同時被清單、詳情和 sheet 使用，只讓最上層的畫面啟用，避免重複彈出
    func actionErrorAlert(_ store: SessionStore, isActive: Bool = true) -> some View {
        let shown = isActive && store.actionError != nil
        return alert("操作失敗", isPresented: Binding(get: { shown }, set: { if !$0 { store.actionError = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(store.actionError ?? "")
        }
    }

    /// iOS 26+ 讓 sheet 從來源按鈕展開；沒有來源或舊系統時維持一般的 sheet 動畫
    @ViewBuilder
    func zoomTransition(from source: SheetSource?, in ns: Namespace.ID) -> some View {
        if let source {
            if #available(iOS 26.0, *) {
                navigationTransition(.zoom(sourceID: source, in: ns))
            } else {
                self
            }
        } else {
            self
        }
    }

    /// 把一般元件（非工具列）標記為 sheet 的轉場來源
    @ViewBuilder
    func sheetSource(_ source: SheetSource, in ns: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            matchedTransitionSource(id: source, in: ns)
        } else {
            self
        }
    }

    /// 單一工具列按鈕，iOS 26+ 同時作為 sheet 的轉場來源。
    /// ToolbarContentBuilder 在 iOS 17.5 前不支援 #available，所以在 View 層分支
    @ViewBuilder
    func toolbarItem<C: View>(_ placement: ToolbarItemPlacement, source: SheetSource, in ns: Namespace.ID,
                              @ViewBuilder content: () -> C) -> some View {
        if #available(iOS 26.0, *) {
            toolbar {
                ToolbarItem(placement: placement, content: content)
                    .matchedTransitionSource(id: source, in: ns)
            }
        } else {
            toolbar { ToolbarItem(placement: placement, content: content) }
        }
    }
}

private struct TorrentActionDialog: ViewModifier {
    @Binding var pending: PendingAction?
    let anchor: PendingAction.Anchor
    let store: SessionStore
    let onDone: (PendingAction, Bool) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible, presenting: pending) { action in
            switch action.kind {
            case .delete:
                Button("刪除種子（保留檔案）", role: .destructive) {
                    perform(action) { await store.delete(action.hashes, deleteFiles: false) }
                }
                Button("刪除種子及已下載檔案", role: .destructive) {
                    perform(action) { await store.delete(action.hashes, deleteFiles: true) }
                }
            case .recheck:
                Button("重新校驗") {
                    perform(action) { await store.recheck(action.hashes) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: { action in
            if action.kind == .recheck {
                Text("會重新檢查已下載的資料，校驗期間不會傳輸，大型種子可能需要一段時間。")
            }
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { pending?.anchor == anchor }, set: { if !$0 { pending = nil } })
    }

    private var title: String {
        guard let pending else { return "" }
        let verb = pending.kind == .delete ? "刪除" : "重新校驗"
        if pending.hashes.count == 1, let t = store.torrents[pending.hashes[0]] {
            return "\(verb)「\(t.name)」？"
        }
        return "\(verb) \(pending.hashes.count) 個種子？"
    }

    private func perform(_ action: PendingAction, _ op: @escaping () async -> Bool) {
        Task { onDone(action, await op()) }
    }
}

/// sheet 的取消按鈕：有未儲存的內容時先從按鈕彈出確認，避免誤觸丟失輸入
struct DiscardButton: View {
    let hasChanges: Bool
    let dismiss: () -> Void
    @State private var confirm = false

    var body: some View {
        Button("取消", role: .cancel) {
            if hasChanges { confirm = true } else { dismiss() }
        }
        .confirmationDialog("要捨棄尚未儲存的內容嗎？", isPresented: $confirm, titleVisibility: .visible) {
            Button("捨棄", role: .destructive) { dismiss() }
            Button("繼續編輯", role: .cancel) {}
        }
    }
}

import SwiftUI

struct CategoryPickerView: View {
    let store: SessionStore
    let hashes: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var working = false

    private var current: Set<String> {
        Set(hashes.compactMap { store.torrents[$0]?.category })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("未分類", value: "", symbol: "folder.badge.minus")
                    ForEach(store.sortedCategories, id: \.name) { c in
                        row(c.name, value: c.name, symbol: "folder.fill", detail: c.savePath)
                    }
                } footer: {
                    Text("將套用到 \(hashes.count) 個種子")
                }
                Section("新增分類") {
                    HStack {
                        TextField("分類名稱", text: $newName)
                        Button("新增並套用") { apply(newName.trimmingCharacters(in: .whitespaces)) }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("設定分類")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                }
            }
            .overlay { if working { ProgressView() } }
        }
        .presentationDetents([.medium, .large])
        .actionErrorAlert(store)
    }

    private func row(_ title: String, value: String, symbol: String, detail: String = "") -> some View {
        Button {
            apply(value)
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading) {
                        Text(title).foregroundStyle(.primary)
                        if !detail.isEmpty {
                            Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }
                } icon: {
                    Image(systemName: symbol)
                }
                Spacer()
                if current == [value] {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
        }
        .disabled(working)
    }

    private func apply(_ category: String) {
        working = true
        Task {
            // 失敗時留在畫面上顯示錯誤，成功才關閉
            if await store.setCategory(hashes, category) { dismiss() }
            working = false
        }
    }
}

struct TagEditorView: View {
    let store: SessionStore
    let hashes: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""
    @State private var working = false

    private var torrents: [Torrent] { hashes.compactMap { store.torrents[$0] } }

    private func coverage(_ tag: String) -> Int {
        torrents.filter { $0.tags.contains(tag) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.tags.isEmpty {
                        Text("尚無標籤").foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(store.tags, id: \.self) { tag in
                        let n = coverage(tag)
                        Button {
                            toggle(tag, hasAll: n == torrents.count && n > 0)
                        } label: {
                            HStack {
                                Image(systemName: n == 0 ? "circle" : (n == torrents.count ? "checkmark.circle.fill" : "minus.circle.fill"))
                                    .foregroundStyle(n == 0 ? Theme.secondaryText : Theme.accent)
                                Text(tag).foregroundStyle(.primary)
                                Spacer()
                                if n > 0 && n < torrents.count {
                                    Text("\(n)/\(torrents.count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                        .disabled(working)
                    }
                } footer: {
                    Text("點選切換：全部種子都有該標籤時會移除，否則會加到所有選取的種子（共 \(hashes.count) 個）。")
                }
                Section("新增標籤") {
                    HStack {
                        TextField("標籤名稱（可用逗號分隔多個）", text: $newTag)
                        Button("新增並套用") { addNew() }
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("管理標籤")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .overlay { if working { ProgressView() } }
        }
        .presentationDetents([.medium, .large])
        .actionErrorAlert(store)
    }

    private func toggle(_ tag: String, hasAll: Bool) {
        working = true
        Task {
            if hasAll {
                await store.removeTags(hashes, [tag])
            } else {
                await store.addTags(hashes, [tag])
            }
            working = false
        }
    }

    private func addNew() {
        let tags = newTag.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !tags.isEmpty else { return }
        working = true
        Task {
            if await store.addTags(hashes, tags) { newTag = "" }
            working = false
        }
    }
}

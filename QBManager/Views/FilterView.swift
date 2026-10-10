import SwiftUI

struct FilterView: View {
    @Bindable var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let counts = Counts(store)
        NavigationStack {
            Form {
                Section("分類") {
                    option("全部", symbol: "folder", count: counts.total, selected: store.filter.category == nil) {
                        store.filter.category = nil
                    }
                    option("未分類", symbol: "folder.badge.questionmark",
                           count: counts.categories[""] ?? 0,
                           selected: store.filter.category == "") {
                        store.filter.category = ""
                    }
                    ForEach(store.sortedCategories, id: \.name) { c in
                        option(c.name, symbol: "folder.fill",
                               count: counts.categories[c.name] ?? 0,
                               selected: store.filter.category == c.name) {
                            store.filter.category = c.name
                        }
                    }
                }

                Section("標籤") {
                    option("全部", symbol: "tag", count: counts.total, selected: store.filter.tag == nil) {
                        store.filter.tag = nil
                    }
                    option("無標籤", symbol: "tag.slash",
                           count: counts.untagged,
                           selected: store.filter.tag == "") {
                        store.filter.tag = ""
                    }
                    ForEach(store.tags, id: \.self) { tag in
                        option(tag, symbol: "tag.fill",
                               count: counts.tags[tag] ?? 0,
                               selected: store.filter.tag == tag) {
                            store.filter.tag = tag
                        }
                    }
                }

                Section("Tracker") {
                    option("全部", symbol: "antenna.radiowaves.left.and.right", count: counts.total,
                           selected: store.filter.trackerHost == nil) {
                        store.filter.trackerHost = nil
                    }
                    option("無 Tracker", symbol: "antenna.radiowaves.left.and.right.slash",
                           count: counts.trackers[""] ?? 0,
                           selected: store.filter.trackerHost == "") {
                        store.filter.trackerHost = ""
                    }
                    ForEach(counts.trackers.keys.filter { !$0.isEmpty }.sorted(), id: \.self) { host in
                        option(host, symbol: "server.rack", count: counts.trackers[host] ?? 0,
                               selected: store.filter.trackerHost == host) {
                            store.filter.trackerHost = host
                        }
                    }
                }

                Section("排序") {
                    Picker("排序依據", selection: $store.filter.sort) {
                        ForEach(SortField.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("方向", selection: $store.filter.ascending) {
                        Text("遞減").tag(false)
                        Text("遞增").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section("狀態") {
                    ForEach(StatusFilter.allCases) { s in
                        option(s.label, symbol: s.symbol, count: store.count(s),
                               selected: store.filter.status == s) {
                            store.filter.status = s
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("篩選與排序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重設") {
                        store.filter.status = .all
                        store.filter.category = nil
                        store.filter.tag = nil
                        store.filter.trackerHost = nil
                    }
                    .disabled(!store.filter.isFiltering)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func option(_ title: String, symbol: String, count: Int, selected: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbol)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                    .opacity(selected ? 1 : 0)
            }
        }
    }
}

/// 走訪一次算出分類、標籤、Tracker 的種子數，取代每個選項各掃一遍
private struct Counts {
    var total = 0
    /// 分類名稱 → 數量；空字串為未分類
    var categories: [String: Int] = [:]
    var tags: [String: Int] = [:]
    var untagged = 0
    /// Tracker 主機 → 數量；空字串為無 Tracker
    var trackers: [String: Int] = [:]

    @MainActor init(_ store: SessionStore) {
        for t in store.torrents.values {
            total += 1
            categories[t.category, default: 0] += 1
            if t.tags.isEmpty { untagged += 1 }
            for tag in t.tags { tags[tag, default: 0] += 1 }
            let hosts = store.hosts(of: t)
            if hosts.isEmpty { trackers["", default: 0] += 1 }
            for h in hosts { trackers[h, default: 0] += 1 }
        }
    }
}

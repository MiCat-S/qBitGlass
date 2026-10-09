import SwiftUI

struct FilterView: View {
    @Bindable var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let all = Array(store.torrents.values)
        NavigationStack {
            Form {
                Section("分類") {
                    option("全部", symbol: "folder", count: all.count, selected: store.filter.category == nil) {
                        store.filter.category = nil
                    }
                    option("未分類", symbol: "folder.badge.questionmark",
                           count: all.filter { $0.category.isEmpty }.count,
                           selected: store.filter.category == "") {
                        store.filter.category = ""
                    }
                    ForEach(store.sortedCategories, id: \.name) { c in
                        option(c.name, symbol: "folder.fill",
                               count: all.filter { $0.category == c.name }.count,
                               selected: store.filter.category == c.name) {
                            store.filter.category = c.name
                        }
                    }
                }

                Section("標籤") {
                    option("全部", symbol: "tag", count: all.count, selected: store.filter.tag == nil) {
                        store.filter.tag = nil
                    }
                    option("無標籤", symbol: "tag.slash",
                           count: all.filter { $0.tags.isEmpty }.count,
                           selected: store.filter.tag == "") {
                        store.filter.tag = ""
                    }
                    ForEach(store.tags, id: \.self) { tag in
                        option(tag, symbol: "tag.fill",
                               count: all.filter { $0.tags.contains(tag) }.count,
                               selected: store.filter.tag == tag) {
                            store.filter.tag = tag
                        }
                    }
                }

                Section("Tracker") {
                    let hostCounts = trackerCounts(all)
                    option("全部", symbol: "antenna.radiowaves.left.and.right", count: all.count,
                           selected: store.filter.trackerHost == nil) {
                        store.filter.trackerHost = nil
                    }
                    option("無 Tracker", symbol: "antenna.radiowaves.left.and.right.slash",
                           count: hostCounts[""] ?? 0,
                           selected: store.filter.trackerHost == "") {
                        store.filter.trackerHost = ""
                    }
                    ForEach(hostCounts.keys.filter { !$0.isEmpty }.sorted(), id: \.self) { host in
                        option(host, symbol: "server.rack", count: hostCounts[host] ?? 0,
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

    private func trackerCounts(_ all: [Torrent]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for t in all {
            let hosts = store.hosts(of: t)
            if hosts.isEmpty { counts["", default: 0] += 1 }
            for h in hosts { counts[h, default: 0] += 1 }
        }
        return counts
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

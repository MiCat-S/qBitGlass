import SwiftUI
import UniformTypeIdentifiers

struct AddTorrentView: View {
    let store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var links: String
    @State private var files: [TorrentUpload]
    @State private var options = AddTorrentOptions()
    @State private var tagsText = ""
    @State private var showImporter = false
    @State private var adding = false
    @State private var error: String?

    private static let torrentType = UTType(filenameExtension: "torrent") ?? .data

    init(store: SessionStore, prefill: IncomingTorrent) {
        self.store = store
        _links = State(initialValue: prefill.urls.joined(separator: "\n"))
        _files = State(initialValue: prefill.files)
    }

    private var urlList: [String] {
        links.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if links.isEmpty {
                            Text("貼上磁力連結或種子網址，一行一個")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $links)
                            .frame(minHeight: 96)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .scrollContentBackground(.hidden)
                    }
                    HStack {
                        Button("貼上", systemImage: "doc.on.clipboard") {
                            if let s = UIPasteboard.general.string {
                                links = links.isEmpty ? s : links + "\n" + s
                            }
                        }
                        .glassButton()
                        Spacer()
                        Button("選擇 .torrent", systemImage: "doc.badge.plus") { showImporter = true }
                            .glassButton()
                    }
                    .buttonStyle(.borderless)
                    ForEach(files, id: \.self) { f in
                        HStack {
                            Label(f.filename, systemImage: "doc.fill")
                                .lineLimit(1)
                            Spacer()
                            Text(Fmt.bytes(Int64(f.data.count)))
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .onDelete { files.remove(atOffsets: $0) }
                } header: {
                    Text("來源")
                }

                Section("選項") {
                    Picker("分類", selection: $options.category) {
                        Text("無").tag("")
                        ForEach(store.sortedCategories, id: \.name) { Text($0.name).tag($0.name) }
                    }
                    TextField("標籤（逗號分隔）", text: $tagsText)
                        .textInputAutocapitalization(.never)
                    TextField("儲存路徑（留空使用預設）", text: $options.savePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("加入後不要開始", isOn: $options.startStopped)
                    Toggle("跳過雜湊檢查", isOn: $options.skipChecking)
                    Toggle("依序下載", isOn: $options.sequential)
                    Toggle("先下載首尾區塊", isOn: $options.firstLastPiece)
                }

                if let error {
                    Section {
                        Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("新增種子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if adding {
                        ProgressView()
                    } else {
                        Button("新增") { Task { await add() } }
                            .disabled(urlList.isEmpty && files.isEmpty)
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [Self.torrentType],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        files.append(TorrentUpload(filename: url.lastPathComponent, data: data))
                    }
                }
            }
        }
    }

    private func add() async {
        adding = true
        error = nil
        defer { adding = false }
        var o = options
        o.urls = urlList
        o.files = files
        o.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let client = store.client else {
            error = "尚未連線到伺服器"
            return
        }
        do {
            try await client.add(o)
            await store.refresh()
            dismiss()
        } catch {
            self.error = SessionStore.describe(error)
        }
    }
}

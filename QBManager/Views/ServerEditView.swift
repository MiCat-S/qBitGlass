import SwiftUI

/// 要編輯的伺服器；source 是 sheet 展開的來源按鈕
struct ServerEditTarget: Identifiable {
    var server: ServerConfig
    var isNew: Bool
    var source: SheetSource?
    var id: UUID { server.id }
}

struct ServerEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var server: ServerConfig
    @State private var secret: String
    let isNew: Bool
    private let original: ServerConfig
    private let originalSecret: String

    @State private var testing = false
    @State private var testResult: Result<String, Error>?

    init(server: ServerConfig, isNew: Bool) {
        let secret = Keychain.get(server.secretAccount) ?? ""
        _server = State(initialValue: server)
        _secret = State(initialValue: secret)
        self.isNew = isNew
        original = server
        originalSecret = secret
    }

    private var hasChanges: Bool { server != original || secret != originalSecret }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名稱（選填）", text: $server.name)
                    TextField("http://192.168.1.10:8080", text: $server.url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("伺服器")
                } footer: {
                    Text("填入 WebUI 網址，可包含反向代理子路徑，例如 https://nas.example.com/qbittorrent")
                }

                Section {
                    Picker("驗證方式", selection: $server.authMode) {
                        ForEach(AuthMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: server.authMode) { _, _ in
                        secret = Keychain.get(server.secretAccount) ?? ""
                    }

                    switch server.authMode {
                    case .password:
                        TextField("使用者名稱", text: $server.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("密碼", text: $secret)
                    case .apiKey:
                        SecureField("qbt_ 開頭的 API Key", text: $secret)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    case .none:
                        EmptyView()
                    }
                } header: {
                    Text("驗證")
                } footer: {
                    switch server.authMode {
                    case .password: Text("使用 WebUI 的帳號密碼登入，Session 過期會自動重新登入。")
                    case .apiKey: Text("需要 qBittorrent 5.2 以上，在 WebUI 設定中產生 API Key。")
                    case .none: Text("適用於 qBittorrent 已設定「略過 localhost／白名單子網路驗證」的情況。")
                    }
                }

                proxySection

                Section {
                    Toggle("信任自簽憑證", isOn: $server.trustSelfSigned)
                } header: {
                    Text("進階")
                } footer: {
                    Text("僅在使用自簽 HTTPS 憑證時開啟。")
                }

                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Label("測試連線", systemImage: "bolt.horizontal")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(server.baseURL == nil || server.proxy.isIncomplete || testing)

                    if let testResult {
                        switch testResult {
                        case .success(let info):
                            Label(info, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let error):
                            failure(error)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(isNew ? "新增伺服器" : "編輯伺服器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DiscardButton(hasChanges: hasChanges) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        model.save(server, secret: secret)
                        dismiss()
                        // 新增的伺服器儲存後直接進入
                        if isNew { model.open(server.id) }
                    }
                    .disabled(server.baseURL == nil || server.proxy.isIncomplete)
                }
            }
        }
        // 有輸入內容時停用下滑關閉，改由「取消」確認是否捨棄
        .interactiveDismissDisabled(hasChanges)
    }

    private var proxySection: some View {
        Section {
            Toggle("經由代理連線", isOn: $server.proxy.enabled)
                .onChange(of: server.proxy.enabled) { _, on in
                    // 第一次開啟時帶入系統目前的代理
                    if on, server.proxy.port.isEmpty, let sys = ProxySettings.system { useSystemProxy(sys) }
                }
            if server.proxy.enabled {
                Picker("類型", selection: $server.proxy.kind) {
                    ForEach(ProxyKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("代理位址", text: $server.proxy.host)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("連接埠", text: $server.proxy.port)
                    .keyboardType(.numberPad)
                if let sys = ProxySettings.system,
                   sys.host != server.proxy.host || String(sys.port) != server.proxy.port || server.proxy.kind != .http {
                    Button("使用目前的系統代理（\(sys.host):\(sys.port)）", systemImage: "arrow.down.circle") {
                        useSystemProxy(sys)
                    }
                }
            }
        } header: {
            Text("代理")
        } footer: {
            Text("開啟後，連到這台伺服器的所有請求都會經過指定的代理，包括區網與 Tailscale 位址（系統代理預設會略過這些位址）。例如 Surge 的 HTTP 代理是 127.0.0.1:6152。")
        }
    }

    private func useSystemProxy(_ sys: (host: String, port: Int)) {
        server.proxy.kind = .http
        server.proxy.host = sys.host
        server.proxy.port = String(sys.port)
    }

    @ViewBuilder
    private func failure(_ error: Error) -> some View {
        Label(SessionStore.describe(error), systemImage: "xmark.octagon.fill")
            .foregroundStyle(.red)
        // 伺服器要求轉址時，提供一鍵改用轉址後的網址
        if let url = redirectTarget(error) {
            Button("改用 \(url)", systemImage: "arrow.uturn.right") {
                server.url = url
                testResult = nil
            }
        }
    }

    private func redirectTarget(_ error: Error) -> String? {
        guard case QBError.redirected(let url) = error, !url.isEmpty else { return nil }
        return url
    }

    private func test() async {
        testing = true
        testResult = nil
        defer { testing = false }
        do {
            let client = try QBClient(config: server, secret: secret)
            let info = try await client.connect()
            testResult = .success("連線成功：qBittorrent \(info.app)（WebAPI \(info.api)）")
            await client.logout()
        } catch {
            testResult = .failure(error)
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("refreshInterval") private var refreshInterval = 2.0
    @AppStorage("autoOpenLast") private var autoOpenLast = true

    var body: some View {
        NavigationStack {
            Form {
                Section("同步") {
                    Picker("刷新間隔", selection: $refreshInterval) {
                        ForEach([1.0, 2.0, 3.0, 5.0, 10.0], id: \.self) { Text("\(Int($0)) 秒").tag($0) }
                    }
                    Toggle("啟動時自動開啟上次的伺服器", isOn: $autoOpenLast)
                }
                Section("關於") {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                    LabeledContent("API", value: "qBittorrent WebUI API v2")
                    Link(destination: URL(string: "https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-5.0)")!) {
                        Label("WebUI API 文件", systemImage: "book")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

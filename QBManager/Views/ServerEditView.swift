import SwiftUI

struct ServerEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var server: ServerConfig
    @State private var secret: String
    let isNew: Bool

    @State private var testing = false
    @State private var testResult: Result<String, Error>?

    init(server: ServerConfig, isNew: Bool) {
        _server = State(initialValue: server)
        _secret = State(initialValue: Keychain.get(server.secretAccount) ?? "")
        self.isNew = isNew
    }

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
                    .disabled(server.baseURL == nil || testing)

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
                    Button("取消", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        model.save(server, secret: secret)
                        dismiss()
                    }
                    .disabled(server.baseURL == nil)
                }
            }
        }
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

import SwiftUI

struct PasswordRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: PasswordRecoveryStore
    @State private var method: AccountInput.Method
    @State private var phone: String
    @State private var email: String
    @State private var code = ""
    @State private var password = ""
    @State private var confirmation = ""
    @FocusState private var focused: Field?
    private enum Field { case phone, email, code, password, confirmation }

    init(client: APIClient, method: AccountInput.Method, phone: String, email: String) {
        _store = StateObject(wrappedValue: PasswordRecoveryStore(api: PasswordRecoveryAPI(client: client)))
        _method = State(initialValue: method); _phone = State(initialValue: phone); _email = State(initialValue: email)
    }
    var body: some View {
        Form {
            Section {
                Label(store.isComplete ? "密码已更新" : "找回你的账号", systemImage: store.isComplete ? "checkmark.shield" : "lock.rotation")
                    .font(.title3.weight(.semibold)).foregroundStyle(SleepPalette.teal)
                Text(store.isComplete ? "请返回登录，使用新密码进入原账号。原有睡眠和健康记录会保留。" : "手机号接收短信验证码，邮箱接收邮件验证码。验证后即可设置新密码。")
                    .font(.subheadline).foregroundStyle(SleepPalette.muted)
            }
            if !store.isComplete {
                if !store.api.enabled {
                    Section {
                        Label(PasswordRecoveryAPI.unavailableMessage, systemImage: "info.circle")
                            .font(.subheadline).accessibilityIdentifier("recoveryUnavailable")
                    }
                } else if store.challenge == nil {
                    Section("找回账号") {
                        Picker("账号类型", selection: $method) {
                            ForEach(AccountInput.Method.allCases, id: \.self) { Text($0.title + "账号").tag($0) }
                        }.pickerStyle(.segmented)
                        if method == .phone {
                            TextField("注册手机号", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                                .focused($focused, equals: .phone).accessibilityIdentifier("recoveryPhone")
                        }
                        if method == .email { TextField("注册邮箱", text: $email)
                            .keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focused, equals: .email).accessibilityIdentifier("recoveryEmail") }
                    }
                } else {
                    Section("验证码") {
                        LabeledContent(method.title, value: method == .phone ? AccountInput.phone(phone) : AccountInput.email(email))
                        TextField("6 位数字验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .focused($focused, equals: .code).accessibilityIdentifier("recoveryCode")
                        SecureField("新密码（至少 6 个字符）", text: $password).textContentType(.newPassword)
                            .focused($focused, equals: .password).accessibilityIdentifier("recoveryPassword")
                        SecureField("再次输入新密码", text: $confirmation).textContentType(.newPassword)
                            .focused($focused, equals: .confirmation).accessibilityIdentifier("recoveryConfirmation")
                    }
                }
                if let message = store.message {
                    Section { Text(message).font(.subheadline).accessibilityIdentifier("recoveryMessage") }
                }
                if store.api.enabled {
                    Section {
                        Button {
                            focused = nil
                            Task {
                                if store.challenge == nil { await store.request(method: method, phone: phone, email: email) }
                                else {
                                    await store.confirm(code: code, password: password, confirmation: confirmation)
                                    code = ""; password = ""; confirmation = ""
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                if store.isLoading { ProgressView() }
                                Label(store.challenge == nil ? "获取验证码" : "确认重置密码", systemImage: store.challenge == nil ? "paperplane" : "lock.rotation")
                                Spacer()
                            }.padding(.vertical, 8)
                        }.buttonStyle(GroveButtonStyle(.primary)).tint(SleepPalette.teal)
                            .accessibilityIdentifier("recoverySubmit")
                        if store.challenge != nil {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let remaining = max(0, Int(ceil((store.retryAt ?? .distantPast).timeIntervalSince(context.date))))
                                Button(remaining > 0 ? "\(remaining) 秒后可重新获取" : "重新获取验证码") {
                                    focused = nil; code = ""
                                    Task { await store.request(method: method, phone: phone, email: email) }
                                }.disabled(remaining > 0)
                            }
                        }
                    }
                }
                Section {
                    Text("请使用注册时的手机号或邮箱。若未收到，请检查短信拦截或垃圾邮件；无法使用原联系方式时，请联系平台管理员核实身份。")
                        .font(.footnote).foregroundStyle(SleepPalette.muted)
                }
            }
            Section { Button("返回登录") { dismiss() }.accessibilityIdentifier("recoveryBackToLogin") }
        }
        .disabled(store.isLoading).scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden).background(SleepPalette.background)
        .navigationTitle("忘记密码").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { focused = nil } }
        }
        .onDisappear { code = ""; password = ""; confirmation = "" }
    }
}

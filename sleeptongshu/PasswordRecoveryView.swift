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
                Label(store.isComplete ? "密码已更新" : "通过邮箱找回", systemImage: store.isComplete ? "checkmark.shield" : "envelope.badge.shield.half.filled")
                    .font(.title3.weight(.semibold)).foregroundStyle(SleepPalette.teal)
                Text(store.isComplete ? "请返回登录，使用新密码进入原账号。原有睡眠和健康记录会保留。" : "手机号账号使用已绑定并验证的邮箱找回；邮箱账号使用注册邮箱找回。")
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
                        TextField(method == .phone ? "已绑定的邮箱" : "注册邮箱", text: $email)
                            .keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focused, equals: .email).accessibilityIdentifier("recoveryEmail")
                    }
                } else {
                    Section("邮箱验证") {
                        LabeledContent("邮箱", value: AccountInput.email(email))
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
                                Label(store.challenge == nil ? "获取邮箱验证码" : "确认重置密码", systemImage: store.challenge == nil ? "envelope" : "lock.rotation")
                                Spacer()
                            }.padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).tint(SleepPalette.teal)
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
                    Text("还没有绑定邮箱？若仍记得密码，可先登录，在邮箱验证功能开通后完成绑定。已经忘记密码且没有绑定邮箱时，需要联系平台管理员核实身份后处理。")
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

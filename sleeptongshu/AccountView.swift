import SwiftUI

struct AppEntryView: View {
    @EnvironmentObject private var account: AccountStore
    @Environment(\.scenePhase) private var scenePhase
    private var bypassForTests: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing") && !ProcessInfo.processInfo.arguments.contains("-ui-testing-account")
        #else
        false
        #endif
    }
    var body: some View {
        Group {
            if bypassForTests || account.canEnter { RootTabView() }
            else if account.isRestoring {
                VStack(spacing: 16) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 36)).foregroundStyle(SleepPalette.teal)
                    ProgressView("正在检查登录状态")
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(SleepPalette.background)
            } else { NavigationStack { AccountLoginView().toolbar(.hidden, for: .navigationBar) } }
        }.task { if !bypassForTests { await account.restore() } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { account.checkExpiry() } }
    }
}

struct AccountLoginView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var register = false
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var displayName = ""
    @FocusState private var focused: Field?
    private enum Field { case username, password, confirmation, displayName }
    private var passwordContentType: UITextContentType {
        #if DEBUG
        // Prevent the simulator's password generator from replacing automated input.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return .oneTimeCode }
        #endif
        return register ? .newPassword : .password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Image(systemName: "moon.stars.fill").font(.system(size: 27)).foregroundStyle(SleepPalette.teal)
                        .frame(width: 58, height: 58).background(SleepPalette.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Text("睡眠同书").font(.system(size: 14, weight: .medium)).foregroundStyle(SleepPalette.muted)
                }.padding(.top, 26)
                VStack(alignment: .leading, spacing: 9) {
                    Text("sleeptongshu").font(.system(size: 32, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                    Text(register ? "创建账号，开启你的健康记录" : "欢迎回来，关注每一晚的自己")
                        .font(.system(size: 15)).foregroundStyle(SleepPalette.muted)
                }
                Picker("账号操作", selection: $register) {
                    Text("登录").tag(false)
                    Text("注册").tag(true)
                }.pickerStyle(.segmented).disabled(account.isLoading).accessibilityIdentifier("accountMode")
                if !account.isConfigured {
                    Label("账号服务正在准备。当前可以预览本机功能，暂不创建或上传账号。", systemImage: "clock.badge.checkmark")
                        .font(.system(size: 13)).foregroundStyle(SleepPalette.muted).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("accountNotConfigured")
                    previewButton
                }
                VStack(alignment: .leading, spacing: 20) {
                    field("账号", symbol: "person") {
                        TextField("3～32 位字母、数字或下划线", text: $username)
                            .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.asciiCapable).focused($focused, equals: .username).submitLabel(.done)
                            .accessibilityIdentifier("accountUsername")
                    }
                    field("密码", symbol: "lock") {
                        SecureField(register ? "至少 8 个字符" : "输入密码", text: $password)
                            .textContentType(passwordContentType).keyboardType(.asciiCapable).focused($focused, equals: .password)
                            .submitLabel(.done).accessibilityIdentifier("accountPassword")
                    }
                    if register {
                        field("确认密码", symbol: "lock.rotation") {
                            SecureField("再次输入密码", text: $confirmation).textContentType(passwordContentType).keyboardType(.asciiCapable)
                                .focused($focused, equals: .confirmation).submitLabel(.done)
                                .accessibilityIdentifier("accountConfirmPassword")
                        }
                        field("昵称（选填）", symbol: "person.text.rectangle") {
                            TextField("希望怎么称呼你", text: $displayName).textContentType(.nickname)
                                .focused($focused, equals: .displayName).submitLabel(.done)
                                .accessibilityIdentifier("accountDisplayName")
                        }
                    }
                }.disabled(account.isLoading)
                if let message = account.message {
                    Label(message, systemImage: "info.circle").font(.system(size: 13)).foregroundStyle(SleepPalette.rose)
                        .lineSpacing(4).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("accountMessage")
                }
                Button(action: submit) {
                    HStack(spacing: 10) {
                        if account.isLoading { ProgressView().tint(.white) }
                        Text(account.isLoading ? "请稍候" : register ? "创建账号" : "登录")
                        Image(systemName: "arrow.right")
                    }.font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(.white).background(SleepPalette.teal, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(account.isLoading || !account.isConfigured).opacity(account.isConfigured ? 1 : 0.5)
                    .accessibilityIdentifier("accountSubmit")
                VStack(alignment: .leading, spacing: 8) {
                    Label("账号资料与健康记录分开保存", systemImage: "lock.shield")
                        .font(.system(size: 12, weight: .medium))
                    Text("注册后，账号与昵称将保存到睡眠同书平台，用于登录与账号管理。健康记录目前仅保存在这台手机。")
                        .font(.system(size: 12)).foregroundStyle(SleepPalette.muted).lineSpacing(5)
                }
            }.padding(.horizontal, 26).padding(.bottom, 32).frame(maxWidth: 460).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(SleepPalette.background).foregroundStyle(SleepPalette.ink)
            .onSubmit { focused = nil }
            .onChange(of: register) { _, _ in password = ""; confirmation = ""; account.message = nil; focused = nil }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focused = nil }.accessibilityIdentifier("accountKeyboardDone")
                }
            }
    }

    private var previewButton: some View {
        Button { focused = nil; password = ""; confirmation = ""; account.preview() } label: {
            HStack {
                Image(systemName: "iphone")
                Text("预览本机功能")
                Spacer()
                Image(systemName: "arrow.right")
            }.font(.system(size: 15, weight: .medium)).frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(SleepPalette.teal).padding(.horizontal, 16)
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(SleepPalette.teal.opacity(0.25)) }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("accountPreview")
    }

    private func field<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 13, weight: .medium))
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(SleepPalette.muted)
                content().font(.system(size: 14)).textFieldStyle(.plain).frame(minHeight: 52)
            }.padding(.horizontal, 14).frame(minHeight: 52).background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(SleepPalette.line) }
        }
    }
    private func submit() {
        guard !account.isLoading else { return }
        focused = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let enteredPassword = password
        let enteredConfirmation = confirmation
        Task {
            await account.submit(register: register, username: username, password: enteredPassword,
                                 confirmation: enteredConfirmation, displayName: displayName)
            password = ""
            confirmation = ""
        }
    }
}

struct AccountCenterView: View {
    @EnvironmentObject private var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(account.session?.user.displayName.isEmpty == false ? account.session!.user.displayName : "睡眠同书账号", systemImage: "person.crop.circle")
                        .font(.system(size: 19, weight: .semibold))
                    if let user = account.session?.user {
                        LabeledContent("账号", value: user.username)
                        LabeledContent("注册日期", value: user.createdAt.formatted(date: .abbreviated, time: .omitted))
                    } else {
                        Text("本机预览 · 尚未登录或注册").foregroundStyle(SleepPalette.muted)
                    }
                }
                Section("记录与账号") {
                    Label("健康记录保存在这台手机", systemImage: "iphone")
                    Text("本版仅对接账号资料，不上传睡眠或体征记录。退出或切换账号不会清除这台手机上的记录。")
                        .font(.system(size: 13)).foregroundStyle(SleepPalette.muted)
                    if !account.isConfigured {
                        Text("账号服务尚未上线，当前预览不创建平台账号。")
                            .font(.system(size: 13)).foregroundStyle(SleepPalette.muted)
                    }
                }
                if let message = account.message { Section { Text(message).font(.system(size: 13)).foregroundStyle(SleepPalette.rose) } }
                Section {
                    Button(role: .destructive) { confirmSignOut = true } label: {
                        Label(account.session == nil ? "返回登录页" : "退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }.disabled(account.isLoading).accessibilityIdentifier("accountSignOut")
                }
            }.scrollContentBackground(.hidden).background(SleepPalette.background)
                .navigationTitle("我的账号").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .confirmationDialog(account.session == nil ? "返回登录页？" : "退出当前账号？", isPresented: $confirmSignOut, titleVisibility: .visible) {
                    Button("确定退出", role: .destructive) {
                        if account.session == nil { account.leavePreview() }
                        else { Task { await account.signOut() } }
                    }
                } message: { Text("本机睡眠与健康记录会保留。") }
        }
    }
}

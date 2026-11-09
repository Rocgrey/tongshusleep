import SwiftUI

/// Keep authentication ahead of all business screens; the pending route lives in AccountStore.
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
        }
        .task { if !bypassForTests { await account.restore() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { account.checkExpiry() } }
        .sheet(item: $account.presentedDestination) { destination in
            switch destination {
            case .profile: AccountCenterView()
            case .upload(let id): SleepUploadView(recordID: id)
            }
        }
    }
}

struct AccountLoginView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var register = false
    @State private var username = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var method = AccountInput.Method.phone
    @State private var password = ""
    @State private var confirmation = ""
    @State private var registrationNotice: String?
    @AppStorage("accountRememberLogin") private var remember = true
    @State private var showsError = false
    @FocusState private var focused: Field?
    private enum Field { case username, phone, email, password, confirmation }
    private var passwordContentType: UITextContentType {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return .oneTimeCode }
        #endif
        return register ? .newPassword : .password
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Image(systemName: "moon.stars.fill").font(.system(size: 28)).foregroundStyle(SleepPalette.teal)
                        .frame(width: 58, height: 58).background(SleepPalette.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Text("睡眠同书").font(.system(size: 14)).foregroundStyle(SleepPalette.muted)
                }.padding(.top, 24)
                VStack(alignment: .leading, spacing: 9) {
                    Text("sleeptongshu").font(.system(size: 32, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                    Text(register ? "创建账号，记录每一晚的自己" : "欢迎回来，今晚也好好休息")
                        .font(.system(size: 15)).foregroundStyle(SleepPalette.muted)
                }
                Picker("账号操作", selection: $register) {
                    Text("登录").tag(false)
                    Text("注册").tag(true)
                }.pickerStyle(.segmented).disabled(account.isLoading).accessibilityIdentifier("accountMode")
                VStack(alignment: .leading, spacing: 20) {
                    if !register {
                        Picker("登录方式", selection: $method) {
                            ForEach(AccountInput.Method.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("accountLoginMethod")
                    }
                    if register {
                        field("用户名", symbol: "person") {
                            TextField("3～32 位中文、字母、数字或下划线", text: $username)
                                .textContentType(.nickname).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focused, equals: .username).accessibilityIdentifier("accountUsername")
                        }
                    }
                    if register || method == .phone {
                        field("手机号", symbol: "iphone") {
                            TextField("11 位大陆手机号", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
                                .focused($focused, equals: .phone).accessibilityIdentifier("accountPhone")
                        }
                    }
                    if register || method == .email { field(register ? "邮箱（选填）" : "邮箱", symbol: "envelope") {
                        TextField("你的邮箱地址", text: $email).textContentType(.username).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .email)
                            .accessibilityIdentifier("accountEmail")
                    } }
                    field("密码", symbol: "lock") {
                        SecureField(register ? "至少 6 个字符" : "输入密码", text: $password)
                            .textContentType(passwordContentType).keyboardType(.asciiCapable).focused($focused, equals: .password)
                            .accessibilityIdentifier("accountPassword")
                    }
                    if register {
                        field("确认密码", symbol: "lock.rotation") {
                            SecureField("再次输入密码", text: $confirmation).textContentType(passwordContentType).keyboardType(.asciiCapable)
                                .focused($focused, equals: .confirmation).accessibilityIdentifier("accountConfirmPassword")
                        }
                    } else {
                        Toggle("记住登录", isOn: $remember).font(.system(size: 14)).tint(SleepPalette.teal)
                            .accessibilityIdentifier("accountRemember")
                    }
                }.disabled(account.isLoading)
                if let message = account.message ?? registrationNotice {
                    Label(message, systemImage: "info.circle").font(.system(size: 13)).foregroundStyle(SleepPalette.muted)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("accountMessage")
                }
                Button(action: submit) {
                    HStack(spacing: 10) {
                        if account.isLoading { ProgressView().tint(SleepPalette.muted) }
                        Text(account.isLoading ? "请稍候" : register ? "注册" : "登录")
                        Image(systemName: "arrow.right")
                    }.font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(account.isLoading ? SleepPalette.muted : .white)
                        .background(account.isLoading ? SleepPalette.line : SleepPalette.teal, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(account.isLoading).accessibilityIdentifier("accountSubmit")
                Button {
                    register.toggle()
                } label: {
                    HStack {
                        Text(register ? "已有账号，去登录" : "还没有账号？去注册")
                        Image(systemName: "arrow.right")
                    }.font(.system(size: 14)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(SleepPalette.teal).disabled(account.isLoading)
                Label("账号安全保存。睡眠记录由你选择后上传。", systemImage: "lock.shield")
                    .font(.system(size: 12)).foregroundStyle(SleepPalette.muted)
            }.padding(.horizontal, 26).padding(.bottom, 32).frame(maxWidth: 460).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(SleepPalette.background).foregroundStyle(SleepPalette.ink)
            .submitLabel(.done).onSubmit { focused = nil }
            .onChange(of: register) { _, _ in password = ""; confirmation = ""; account.message = nil; focused = nil }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focused = nil }.accessibilityIdentifier("accountKeyboardDone")
                }
            }
            .alert("请检查一下", isPresented: $showsError) { Button("知道了", role: .cancel) { } }
                message: { Text(account.message ?? "请稍后重试。") }
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
        registrationNotice = nil
        let inputPassword = password, inputConfirmation = confirmation, isRegistration = register
        Task {
            if isRegistration {
                let success = await account.register(username: username, phone: phone, email: email, password: inputPassword, confirmation: inputConfirmation)
                if success {
                    registrationNotice = account.message
                    register = false
                    method = AccountInput.phone(phone).isEmpty ? .email : .phone
                } else { showsError = true }
            } else {
                await account.login(identifier: method == .phone ? phone : email, method: method, password: inputPassword, remember: remember)
                if account.session == nil { showsError = true }
            }
            password = ""; confirmation = ""
        }
    }
}

struct AccountCenterView: View {
    @EnvironmentObject private var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsExit = false
    var body: some View {
        NavigationStack {
            Form {
                if let user = account.session?.user {
                    Section {
                        Label(user.username, systemImage: "person.crop.circle.fill").font(.system(size: 20, weight: .semibold))
                        if let phone = user.phone { LabeledContent("手机号", value: phone).accessibilityIdentifier("profilePhone") }
                        if let email = user.email { LabeledContent("邮箱", value: email).accessibilityIdentifier("profileEmail") }
                        LabeledContent("注册日期", value: user.createdAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    Section("记录与账号") {
                        Label("睡眠与步数由你选择同步", systemImage: "lock.shield")
                        Text("本机记录不会因切换账号而被清空。上传前请确认当前账号；已上传的记录在对应账号的平台中保存。")
                            .font(.system(size: 13)).foregroundStyle(SleepPalette.muted)
                    }
                    Section {
                        Button(role: .destructive) { confirmsExit = true } label: {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        }.disabled(account.isLoading).accessibilityIdentifier("accountSignOut")
                    }
                }
            }.scrollContentBackground(.hidden).background(SleepPalette.background)
                .navigationTitle("我的账号").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .confirmationDialog("退出当前账号？", isPresented: $confirmsExit, titleVisibility: .visible) {
                    Button("确定退出", role: .destructive) { Task { await account.signOut() } }
                } message: { Text("本机睡眠与健康记录会保留。") }
        }
    }
}

import SwiftUI
import WebKit
import Combine

enum SleepClassroomConfiguration {
    static let homeURL = URL(string: "https://palm-sleep-guide.app.workbuddy.host/")!
}

/// The website keeps its own cookies; no App credentials or health data are injected.
@MainActor final class SleepClassroomBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var errorMessage: String?
    private var observations: [NSKeyValueObservation] = []
    private var hasLoaded = false

    lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        view.scrollView.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "sleepClassroomWeb"
        observations = [
            view.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in self?.progress = view.estimatedProgress }
            },
            view.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in self?.canGoBack = view.canGoBack }
            },
            view.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in self?.canGoForward = view.canGoForward }
            }
        ]
        return view
    }()

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        home()
    }
    func home() { load(SleepClassroomConfiguration.homeURL) }
    private func load(_ url: URL) {
        errorMessage = nil
        webView.load(URLRequest(url: url, timeoutInterval: 30))
    }
    func reload() {
        errorMessage = nil
        if webView.url == nil { home() } else { webView.reload() }
    }
    func back() { webView.goBack() }
    func forward() { webView.goForward() }
    func openInBrowser() { UIApplication.shared.open(webView.url ?? SleepClassroomConfiguration.homeURL) }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil; isLoading = true
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { isLoading = false }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        isLoading = false
        errorMessage = "请检查网络连接后重试，也可以在浏览器中打开。"
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoading = false
        errorMessage = "页面已暂停，请重新加载。"
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        switch url.scheme?.lowercased() {
        case "http", "https", "about", "blob": decisionHandler(.allow)
        case "tel", "mailto":
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
        default: decisionHandler(.cancel)
        }
    }
    // target=_blank links stay in this browser and remain reachable via Back.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

private struct SleepClassroomWebView: UIViewRepresentable {
    let browser: SleepClassroomBrowser
    func makeUIView(context: Context) -> WKWebView {
        let view = browser.webView
        browser.loadIfNeeded()
        return view
    }
    // SwiftUI state updates must not reload the page or reset its scroll position.
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct SleepClassroomView: View {
    @StateObject private var browser = SleepClassroomBrowser()
    @State private var hasOpened = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if hasOpened {
                    ZStack(alignment: .top) {
                        SleepClassroomWebView(browser: browser)
                        if browser.isLoading {
                            ProgressView(value: max(0.05, browser.progress))
                                .progressViewStyle(.linear).tint(SleepPalette.teal)
                                .accessibilityLabel("正在加载睡眠课堂")
                        }
                        if let error = browser.errorMessage {
                            ContentUnavailableView {
                                Label("课堂暂时无法打开", systemImage: "wifi.exclamationmark")
                            } description: { Text(error) } actions: {
                                Button { browser.reload() } label: { Label("重新加载", systemImage: "arrow.clockwise") }
                                    .buttonStyle(.borderedProminent).accessibilityIdentifier("classroomRetry")
                                Button("在浏览器中打开") { browser.openInBrowser() }
                            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(SleepPalette.background)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SleepPalette.background)
            .navigationTitle("睡眠课堂")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { browser.back() } label: { Image(systemName: "chevron.left") }
                        .disabled(!browser.canGoBack).accessibilityLabel("返回上一页").help("返回上一页")
                    Button { browser.forward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!browser.canGoForward).accessibilityLabel("前进").help("前进")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("刷新课堂").accessibilityIdentifier("classroomReload").help("刷新课堂")
                    Menu {
                        Button { browser.home() } label: { Label("课堂首页", systemImage: "house") }
                        Button { browser.openInBrowser() } label: { Label("在浏览器中打开", systemImage: "safari") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("课堂选项").accessibilityIdentifier("classroomOptions").help("课堂选项")
                }
            }
            .onAppear { hasOpened = true }
        }
    }
}

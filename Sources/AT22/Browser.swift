import SwiftUI
import WebKit

// MARK: - 内蔵ブラウザ

/// エージェントが立てた開発サーバーや PR を、AT22 の中で開く板。会話の発言に出てきた URL の札から開く。
/// ponytail: タブは1枚だけ。履歴は WKWebView の戻る／進むに任せる
struct BrowserSheet: View {
    let start: URL
    let onClose: () -> Void

    @State private var address = ""
    @State private var model = BrowserModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("‹") { model.web.goBack() }.buttonStyle(.plain).font(.mono(16)).disabled(!model.canGoBack)
                Button("›") { model.web.goForward() }.buttonStyle(.plain).font(.mono(16)).disabled(!model.canGoForward)
                Button("↻") { model.web.reload() }.buttonStyle(.plain).font(.mono(13))
                TextField("URL", text: $address)
                    .textFieldStyle(.plain).font(.mono(12))
                    .padding(.horizontal, 10).frame(height: 28)
                    .overlay(Rectangle().strokeBorder(Palette.Light.line, lineWidth: 1))
                    .onSubmit { model.open(Self.url(address)) }
                if model.loading { InkLoader(status: "download", pitch: 1.2) }
                Button("Safari ↗") { if let url = model.web.url { NSWorkspace.shared.open(url) } }
                    .buttonStyle(SumiButtonStyle(primary: false, size: 11))
                Button("閉じる ×", action: onClose).buttonStyle(SumiButtonStyle(primary: true, size: 11))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)
            .background(Palette.Light.bg)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
            WebView(web: model.web)
        }
        .foregroundStyle(Palette.Light.fg)
        .background(Palette.Light.bg)
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 2))
        .padding(40)
        .onAppear {
            address = start.absoluteString
            model.open(start)
        }
        .onChange(of: model.current) { address = model.current }
    }

    /// 打った文字を URL に。スキームが無ければ http（開発サーバーは大抵 http）
    nonisolated static func url(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return URL(string: t.contains("://") ? t : "http://" + t)
    }

    /// 発言の中の URL（開発サーバーと PR を札にする）。重複は1つに
    nonisolated static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<String>(), out: [URL] = []
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, ["http", "https"].contains(url.scheme ?? ""), seen.insert(url.absoluteString).inserted else { continue }
            out.append(url)
        }
        return Array(out.prefix(4))
    }
}

@MainActor @Observable
final class BrowserModel: NSObject, WKNavigationDelegate {
    let web = WKWebView()
    var loading = false
    var current = ""
    var canGoBack = false
    var canGoForward = false

    override init() {
        super.init()
        web.navigationDelegate = self
    }

    func open(_ url: URL?) {
        guard let url else { return }
        web.load(URLRequest(url: url))
    }

    private func sync() {
        loading = web.isLoading
        current = web.url?.absoluteString ?? current
        canGoBack = web.canGoBack
        canGoForward = web.canGoForward
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        MainActor.assumeIsolated { sync() }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { sync() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { sync() }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { sync() }
    }
}

private struct WebView: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

import Combine
import SwiftUI
import WebKit

@MainActor
final class WebViewProxy: ObservableObject {
    weak var webView: WKWebView?

    func load(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        webView?.load(URLRequest(url: url))
    }

    func reload() { webView?.reload() }
    func goBack() { if webView?.canGoBack == true { webView?.goBack() } }

    func evaluate(_ script: String) async throws -> Any? {
        guard let webView else { throw AppError.importCapture(L10n.tr("WebView is not ready yet.")) }
        return try await webView.evaluateJavaScript(script)
    }
}

struct ImportWebView: UIViewRepresentable {
    @ObservedObject var proxy: WebViewProxy
    let initialURL: String
    let onNavigationChange: (String, String?, Bool) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        proxy.webView = webView
        if let url = URL(string: initialURL) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(proxy: proxy, onNavigationChange: onNavigationChange)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let proxy: WebViewProxy
        let onNavigationChange: (String, String?, Bool) -> Void

        init(proxy: WebViewProxy, onNavigationChange: @escaping (String, String?, Bool) -> Void) {
            self.proxy = proxy
            self.onNavigationChange = onNavigationChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigationChange(webView.url?.absoluteString ?? "", webView.title, webView.canGoBack)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onNavigationChange(webView.url?.absoluteString ?? "", webView.title, webView.canGoBack)
        }
    }
}

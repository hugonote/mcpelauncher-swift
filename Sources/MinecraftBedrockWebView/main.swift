import AppKit
import WebKit

final class LoginWindowController: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    private let startURL: URL
    private let endURLPrefix: String
    private var window: NSWindow?
    private var webView: WKWebView?
    private var didFinish = false

    init(startURL: URL, endURLPrefix: String) {
        self.startURL = startURL
        self.endURLPrefix = endURLPrefix
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(max(screenFrame.width * 0.82, 900), 1280)
        let height = min(max(screenFrame.height * 0.82, 680), 920)
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2,
            width: width,
            height: height
        )

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Xbox Sign In"
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        webView.load(URLRequest(url: startURL))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url, finishIfNeeded(url) {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }
        report(error)
    }

    private func finishIfNeeded(_ url: URL) -> Bool {
        let value = url.absoluteString
        guard value.hasPrefix(endURLPrefix) else {
            return false
        }
        didFinish = true
        FileHandle.standardOutput.write(Data((value + "\n").utf8))
        NSApp.terminate(nil)
        return true
    }

    private func report(_ error: Error) {
        guard !didFinish else {
            return
        }
        FileHandle.standardError.write(Data("mcpelauncher-webview: \(error.localizedDescription)\n".utf8))
    }
}

let args = CommandLine.arguments
guard args.count == 3, let startURL = URL(string: args[1]), !args[2].isEmpty else {
    FileHandle.standardError.write(Data("usage: mcpelauncher-webview <startUrl> <endUrlPrefix>\n".utf8))
    exit(2)
}

let delegate = LoginWindowController(startURL: startURL, endURLPrefix: args[2])
let app = NSApplication.shared
app.delegate = delegate
app.run()

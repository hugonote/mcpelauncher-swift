import SwiftUI
import WebKit

struct WebLoginView: NSViewRepresentable {
    static let defaultURL = URL(string: "https://accounts.google.com/embedded/setup/v2/android?source=com.android.settings&xoauth_display_name=Android%20Phone&canFrp=1&canSk=1&lang=en&langCountry=en_us&hl=en-US&cc=us")!

    var onToken: (String, String) -> Void
    var onAccountIdentifier: (String) -> Void = { _ in }
    var onConsentAccepted: () -> Void = {}
    var onSetupFinished: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onToken: onToken,
            onAccountIdentifier: onAccountIdentifier,
            onConsentAccepted: onConsentAccepted,
            onSetupFinished: onSetupFinished
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        configuration.userContentController.add(context.coordinator, name: "googleLogin")
        configuration.userContentController.addUserScript(Self.bridgeScript)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.cookieStore = configuration.websiteDataStore.httpCookieStore
        webView.load(URLRequest(url: Self.defaultURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "googleLogin")
    }

    static let bridgeScript = WKUserScript(
        source: """
        (function() {
          function post(message) {
            try {
              window.webkit.messageHandlers.googleLogin.postMessage(message);
            } catch (error) {}
          }
          window.mm = window.mm || {};
          window.mm.showView = function() {
            post({ type: "setupFinished" });
          };
          window.mm.setAccountIdentifier = function(identifier) {
            post({ type: "accountIdentifier", value: String(identifier || "") });
          };
          window.mm.log = function(value) {
            post({ type: "log", value: String(value || "") });
          };
          var autoConsentClicked = false;
          function textFor(element) {
            if (!element) {
              return "";
            }
            return [
              element.innerText,
              element.textContent,
              element.getAttribute && element.getAttribute("aria-label"),
              element.value
            ].filter(Boolean).join(" ").trim().toLowerCase();
          }
          function isAgreeElement(element) {
            var text = textFor(element).replace(/\\s+/g, " ").trim();
            return text === "i agree" || text === "agree" || text.indexOf(" i agree ") !== -1;
          }
          function findAgreeButton(root) {
            var selectors = [
              "button",
              "[role='button']",
              "input[type='button']",
              "input[type='submit']",
              "div[tabindex]",
              "span"
            ];
            var candidates = [];
            try {
              candidates = Array.prototype.slice.call(root.querySelectorAll(selectors.join(",")));
            } catch (error) {
              return null;
            }
            for (var index = 0; index < candidates.length; index += 1) {
              var candidate = candidates[index];
              if (isAgreeElement(candidate)) {
                return candidate.closest("button,[role='button'],input,div[tabindex]") || candidate;
              }
            }
            return null;
          }
          function clickAgreeIfVisible() {
            if (autoConsentClicked) {
              return;
            }
            var button = findAgreeButton(document);
            if (!button) {
              return;
            }
            var rect = button.getBoundingClientRect();
            if (rect.width <= 0 || rect.height <= 0) {
              return;
            }
            autoConsentClicked = true;
            post({ type: "consentAccepted" });
            button.click();
          }
          document.addEventListener("click", function(event) {
            var element = event.target;
            for (var depth = 0; element && depth < 5; depth += 1, element = element.parentElement) {
              if (isAgreeElement(element)) {
                post({ type: "consentAccepted" });
                return;
              }
            }
          }, true);
          setTimeout(clickAgreeIfVisible, 300);
          setTimeout(clickAgreeIfVisible, 1000);
          setTimeout(clickAgreeIfVisible, 2000);
          if (window.MutationObserver) {
            new MutationObserver(clickAgreeIfVisible).observe(document.documentElement || document, {
              childList: true,
              subtree: true
            });
          }
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver, WKScriptMessageHandler {
        private let onToken: (String, String) -> Void
        private let onAccountIdentifier: (String) -> Void
        private let onConsentAccepted: () -> Void
        private let onSetupFinished: () -> Void
        fileprivate weak var cookieStore: WKHTTPCookieStore?
        private var lastToken: String?
        private var lastAccountIdentifier: String?

        init(
            onToken: @escaping (String, String) -> Void,
            onAccountIdentifier: @escaping (String) -> Void,
            onConsentAccepted: @escaping () -> Void,
            onSetupFinished: @escaping () -> Void
        ) {
            self.onToken = onToken
            self.onAccountIdentifier = onAccountIdentifier
            self.onConsentAccepted = onConsentAccepted
            self.onSetupFinished = onSetupFinished
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            collectCookies(from: webView.configuration.websiteDataStore.httpCookieStore)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            collectCookies(from: webView.configuration.websiteDataStore.httpCookieStore)
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            collectCookies(from: webView.configuration.websiteDataStore.httpCookieStore)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            collectCookies(from: webView.configuration.websiteDataStore.httpCookieStore)
            return .allow
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let payload = message.body as? [String: Any],
               let type = payload["type"] as? String {
                if type == "accountIdentifier",
                   let value = payload["value"] as? String,
                   !value.isEmpty {
                    lastAccountIdentifier = value
                    DispatchQueue.main.async {
                        self.onAccountIdentifier(value)
                    }
                } else if type == "consentAccepted" {
                    DispatchQueue.main.async {
                        self.onConsentAccepted()
                    }
                } else if type == "setupFinished" {
                    DispatchQueue.main.async {
                        self.onSetupFinished()
                    }
                }
            }
            if let cookieStore {
                collectCookies(from: cookieStore)
            }
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            collectCookies(from: cookieStore)
        }

        private func collectCookies(from cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { cookies in
                let token = cookies.first(where: { $0.name == "oauth_token" })?.value
                let userID = cookies.first(where: { $0.name == "user_id" })?.value ?? ""
                let accountIdentifier = cookies.first(where: { $0.name == "Email" })?.value ??
                    cookies.first(where: { $0.name == "LSID" })?.value
                if let accountIdentifier, !accountIdentifier.isEmpty, accountIdentifier != self.lastAccountIdentifier {
                    self.lastAccountIdentifier = accountIdentifier
                    DispatchQueue.main.async {
                        self.onAccountIdentifier(accountIdentifier)
                    }
                }
                if let token, !token.isEmpty, token != self.lastToken {
                    self.lastToken = token
                    DispatchQueue.main.async {
                        self.onToken(token, userID)
                    }
                }
            }
        }
    }
}

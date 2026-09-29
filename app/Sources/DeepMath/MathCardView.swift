import SwiftUI
import WebKit

/// Everything `card.js` needs to draw one card.
struct CardPayload: Encodable, Equatable {
    enum Prompt: String, Encodable { case symbol, meaning }

    let card: Card
    let flipped: Bool
    let prompt: Prompt
    let known: Bool
    let review: Bool
    let kindLabel: String
    let context: String
    let level: String
    let hint: String
}

/// Shows a card rendered with KaTeX. Clicking the card calls `onFlip`.
struct MathCardView: View {
    let payload: CardPayload
    let onFlip: () -> Void

    var body: some View {
        CardWebView(payload: payload, onFlip: onFlip)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(payload.flipped ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }
}

/// A web view that never takes keyboard focus, so Space, arrows and letter shortcuts
/// keep reaching the SwiftUI buttons instead of scrolling the page.
final class PassiveWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }
}

/// Forwards script messages without the web view's user-content controller retaining the coordinator.
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

private struct CardWebView: NSViewRepresentable {
    let payload: CardPayload
    let onFlip: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakMessageHandler(context.coordinator), name: "card")
        let view = PassiveWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = true
        context.coordinator.webView = view
        if let dir = AppResources.webDirectory {
            view.loadFileURL(dir.appendingPathComponent("card.html"), allowingReadAccessTo: dir)
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onFlip = onFlip
        context.coordinator.show(payload)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onFlip: () -> Void = {}
        private var ready = false
        private var pending: CardPayload?
        private var shown: CardPayload?

        func show(_ payload: CardPayload) {
            guard payload != shown else { return }
            pending = payload
            flush()
        }

        private func flush() {
            guard ready, let payload = pending, let webView,
                  let data = try? JSONEncoder().encode(payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            pending = nil
            shown = payload
            webView.evaluateJavaScript("renderCard(\(json))")
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.body as? String {
            case "ready":
                ready = true
                flush()
            case "flip":
                onFlip()
            default:
                break
            }
        }
    }
}

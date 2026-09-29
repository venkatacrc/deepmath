import AppKit
import SwiftUI
import WebKit

@MainActor
final class PrintRequest: ObservableObject {
    @Published var isPresented = false
}

struct PrintOptions: Encodable {
    var read = true
    var meaning = true
    var details = true
    var ai = false
}

private struct SheetItem: Encodable {
    let card: Card
    let heading: String
    let meta: String
}

private struct SheetPayload: Encodable {
    let title: String
    let options: PrintOptions
    let items: [SheetItem]
}

/// Lays the cards out as a study sheet in an off-screen web view (so KaTeX typesets the
/// formulas), then hands it to the print system, which paginates it and either shows the
/// Print dialog or saves a PDF.
@MainActor
final class MathPrinter: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private static var active: Set<MathPrinter> = []

    private let payload: SheetPayload
    private let saveURL: URL?
    private let info: NSPrintInfo
    private let window: NSWindow
    private let webView: WKWebView

    static func run(cards: [(Card, heading: String, meta: String)], title: String,
                    options: PrintOptions, saveTo url: URL?) {
        let printer = MathPrinter(
            payload: SheetPayload(title: title, options: options,
                                  items: cards.map { SheetItem(card: $0.0, heading: $0.heading, meta: $0.meta) }),
            saveTo: url)
        active.insert(printer)
        printer.start()
    }

    private init(payload: SheetPayload, saveTo url: URL?) {
        self.payload = payload
        saveURL = url
        info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 40
        info.bottomMargin = 40
        info.leftMargin = 48
        info.rightMargin = 48
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.isHorizontallyCentered = false
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter.rawValue] = true
        if let url {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = url
        }
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let frame = NSRect(x: 0, y: 0, width: width, height: info.paperSize.height)
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: frame, configuration: config)
        window = NSWindow(contentRect: frame.offsetBy(dx: -20_000, dy: -20_000),
                          styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.contentView = webView
        config.userContentController.add(WeakMessageHandler(self), name: "card")
        webView.navigationDelegate = self
    }

    private func start() {
        guard let dir = AppResources.webDirectory else { return finish() }
        // Printing always uses the light palette.
        webView.appearance = NSAppearance(named: .aqua)
        window.orderBack(nil)
        webView.loadFileURL(dir.appendingPathComponent("card.html"), allowingReadAccessTo: dir)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.body as? String {
        case "ready": render()
        case "sheetReady": printSheet()
        default: break
        }
    }

    private func render() {
        guard let data = try? JSONEncoder().encode(payload), let json = String(data: data, encoding: .utf8) else {
            return finish()
        }
        webView.evaluateJavaScript("renderSheet(\(json))")
    }

    private func printSheet() {
        let op = webView.printOperation(with: info)
        op.jobTitle = payload.title
        op.showsPrintPanel = saveURL == nil
        op.showsProgressPanel = true
        op.view?.frame = webView.bounds
        let host = saveURL == nil ? (NSApp.keyWindow ?? NSApp.mainWindow ?? window) : window
        op.runModal(for: host, delegate: self, didRun: #selector(printDone(_:success:context:)), contextInfo: nil)
    }

    @objc private func printDone(_ op: NSPrintOperation, success: Bool, context: UnsafeMutableRawPointer?) {
        finish()
    }

    private func finish() {
        window.orderOut(nil)
        window.contentView = nil
        Self.active.remove(self)
    }
}

struct PrintSheetView: View {
    /// The cards in the current selection, in course order.
    let cards: [Card]
    let reviewIDs: Set<String>
    let heading: (Card) -> String
    let meta: (Card) -> String
    let title: String
    let onClose: () -> Void

    @AppStorage("printRead") private var read = true
    @AppStorage("printMeaning") private var meaning = true
    @AppStorage("printDetails") private var details = true
    @AppStorage("printAI") private var ai = false
    @AppStorage("printReviewOnly") private var reviewOnly = false

    private var picked: [Card] { reviewOnly ? cards.filter { reviewIDs.contains($0.id) } : cards }
    private var options: PrintOptions { PrintOptions(read: read, meaning: meaning, details: details, ai: ai) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Print study sheet").font(.title2.weight(.semibold))
            Text("Prints the cards in the levels and topics ticked in the sidebar, for the card type chosen in the toolbar.")
                .font(.callout).foregroundStyle(.secondary)

            GroupBox("Cards") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Only cards marked for review", isOn: $reviewOnly)
                    Text("\(picked.count) card\(picked.count == 1 ? "" : "s") will be printed")
                        .font(.callout.weight(.medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("Include with each formula") {
                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("How to read it aloud", isOn: $read)
                        Toggle("Meaning", isOn: $meaning)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Term-by-term notes and examples", isOn: $details)
                        Toggle("Use in modern AI and sources", isOn: $ai)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Save as PDF…") { savePDF() }
                Button("Print…") { print() }
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(picked.isEmpty)
        }
        .padding(24)
        .frame(width: 560)
    }

    private var job: [(Card, heading: String, meta: String)] {
        picked.map { ($0, heading: heading($0), meta: meta($0)) }
    }

    private func print() {
        let (job, options) = (job, options)
        onClose()
        DispatchQueue.main.async {
            MathPrinter.run(cards: job, title: title, options: options, saveTo: nil)
        }
    }

    private func savePDF() {
        let panel = NSSavePanel()
        panel.title = "Save study sheet as PDF"
        panel.nameFieldStringValue = "\(title).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let (job, options) = (job, options)
        onClose()
        DispatchQueue.main.async {
            MathPrinter.run(cards: job, title: title, options: options, saveTo: url)
        }
    }
}

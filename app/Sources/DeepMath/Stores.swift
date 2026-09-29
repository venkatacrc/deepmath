import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum AppResources {
    /// Prefers the copy inside the .app, then the SwiftPM resource bundle (used by `swift run`).
    static func url(_ name: String, _ ext: String?) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.module.url(forResource: name, withExtension: ext)
    }

    static var webDirectory: URL? { url("web", nil) }
}

@MainActor
final class DeckStore: ObservableObject {
    @Published private(set) var deck: Deck = .empty
    @Published private(set) var origin = ""
    @Published private(set) var revision = 0
    @Published var errorMessage: String?

    static var userDeckURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeepMath", isDirectory: true)
            .appendingPathComponent("deck.json")
    }

    init() { load() }

    /// Prefers an imported deck in Application Support, then the built-in deck.
    func load() {
        var candidates: [(URL, String)] = []
        if FileManager.default.fileExists(atPath: Self.userDeckURL.path) {
            candidates.append((Self.userDeckURL, "Imported deck"))
        }
        if let url = AppResources.url("deck", "json") {
            candidates.append((url, "Built-in deck"))
        }
        for (url, name) in candidates {
            do {
                let data = try Data(contentsOf: url)
                deck = try JSONDecoder().decode(Deck.self, from: data)
                origin = name
                revision += 1
                return
            } catch {
                errorMessage = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func importDeck() {
        let panel = NSOpenPanel()
        panel.title = "Import a deck.json"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            _ = try JSONDecoder().decode(Deck.self, from: data)
            let dest = Self.userDeckURL
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try data.write(to: dest)
            load()
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func revertToBuiltIn() {
        try? FileManager.default.removeItem(at: Self.userDeckURL)
        load()
    }
}

@MainActor
final class ProgressStore: ObservableObject {
    @Published private(set) var known: Set<String>
    @Published private(set) var review: Set<String>

    private let defaults = UserDefaults.standard

    init() {
        known = Set(defaults.stringArray(forKey: "knownCards") ?? [])
        review = Set(defaults.stringArray(forKey: "reviewCards") ?? [])
    }

    func toggleKnown(_ id: String) {
        if known.remove(id) == nil {
            known.insert(id)
            review.remove(id)
        }
        save()
    }

    func toggleReview(_ id: String) {
        if review.remove(id) == nil {
            review.insert(id)
            known.remove(id)
        }
        save()
    }

    func markKnown(_ id: String) {
        known.insert(id)
        review.remove(id)
        save()
    }

    func markReview(_ id: String) {
        review.insert(id)
        known.remove(id)
        save()
    }

    func reset() {
        let alert = NSAlert()
        alert.messageText = "Reset progress?"
        alert.informativeText = "This clears every Known and Review mark."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        known = []
        review = []
        save()
    }

    private func save() {
        defaults.set(Array(known), forKey: "knownCards")
        defaults.set(Array(review), forKey: "reviewCards")
    }
}

/// Speaks a card's “read aloud” line with the system voice.
@MainActor
final class Speaker: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

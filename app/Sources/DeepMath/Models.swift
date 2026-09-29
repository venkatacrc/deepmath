import Foundation

struct Deck: Codable {
    var title: String
    var levels: [Level]
    var sources: [Source]
    var cards: [Card]

    static let empty = Deck(title: "Deep Math", levels: [], sources: [], cards: [])
}

/// A stage of the course, from Grade 5–6 (1) to Masters (5).
struct Level: Codable, Identifiable, Hashable {
    let id: Int
    let label: String
}

/// A branch of mathematics, such as Linear Algebra, split into topics.
struct Source: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let ai: String
    let groups: [SourceGroup]
}

struct SourceGroup: Codable, Identifiable, Hashable {
    let id: String
    let label: String
}

struct Term: Codable, Hashable {
    let tex: String
    let text: String
}

/// A notation card (one symbol) or an equation card (a whole formula, explained term by term).
/// `tex` and `example` are KaTeX; prose fields may contain `$inline math$`.
struct Card: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let src: String
    let group: String
    let level: Int
    let name: String
    let tex: String
    let read: String
    let meaning: String
    let example: String
    let terms: [Term]
    let ai: String
    let cite: String

    var key: String { GroupKey.make(src, group) }
    var isEquation: Bool { kind == "equation" }
}

enum CardKind: String, CaseIterable, Identifiable {
    case notation, equations, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notation: "Notation"
        case .equations: "Equations"
        case .both: "Both"
        }
    }

    func includes(_ card: Card) -> Bool {
        switch self {
        case .notation: !card.isEquation
        case .equations: card.isEquation
        case .both: true
        }
    }
}

/// A `(source, group)` pair such as `linalg|matrices`, used for topic selection.
enum GroupKey {
    static func make(_ src: String, _ group: String) -> String { "\(src)|\(group)" }
}

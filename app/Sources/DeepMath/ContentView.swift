import SwiftUI

enum PracticeMode: String, CaseIterable, Identifiable {
    case all, notKnown, review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All cards"
        case .notKnown: "Not yet known"
        case .review: "Review only"
        }
    }
}

enum StudyMode: String, CaseIterable, Identifiable {
    case learn, test

    var id: String { rawValue }
    var title: String { self == .learn ? "Learn" : "Test" }
}

/// What the front of a Test card shows.
enum TestDirection: String, CaseIterable, Identifiable {
    case symbol, meaning

    var id: String { rawValue }
    var title: String { self == .symbol ? "Notation → meaning" : "Meaning → notation" }
}

struct ContentView: View {
    @EnvironmentObject private var store: DeckStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var speaker: Speaker
    @EnvironmentObject private var printRequest: PrintRequest

    /// Newline-separated `src|group` keys; `*` means every group in the deck.
    @AppStorage("selectedGroups") private var selectedRaw = "*"
    @AppStorage("excludedLevels") private var excludedRaw = ""
    @AppStorage("shuffle") private var shuffle = false
    @AppStorage("practiceMode") private var modeRaw = PracticeMode.all.rawValue
    @AppStorage("cardKind") private var kindRaw = CardKind.both.rawValue
    @AppStorage("studyMode") private var studyRaw = StudyMode.learn.rawValue
    @AppStorage("testDirection") private var directionRaw = TestDirection.symbol.rawValue

    @StateObject private var session = StudySession()

    private var cards: [Card] { store.deck.cards }
    private var kind: CardKind { CardKind(rawValue: kindRaw) ?? .both }
    private var mode: PracticeMode { PracticeMode(rawValue: modeRaw) ?? .all }
    private var order: [Int] { session.order }
    private var position: Int { session.position }
    private var study: StudyMode { StudyMode(rawValue: studyRaw) ?? .learn }
    private var direction: TestDirection { TestDirection(rawValue: directionRaw) ?? .symbol }
    /// In Learn mode every card is shown in full; in Test mode the answer is hidden until revealed.
    private var flipped: Bool { study == .learn || session.flipped }

    private var allGroupKeys: Set<String> {
        Set(store.deck.sources.flatMap { s in s.groups.map { GroupKey.make(s.id, $0.id) } })
    }

    private var selected: Binding<Set<String>> {
        Binding(
            get: {
                selectedRaw == "*" ? allGroupKeys : Set(selectedRaw.split(separator: "\n").map(String.init))
            },
            set: { selectedRaw = $0.sorted().joined(separator: "\n") })
    }

    private var excludedLevels: Binding<Set<Int>> {
        Binding(
            get: { Set(excludedRaw.split(separator: ",").compactMap { Int($0) }) },
            set: { excludedRaw = $0.sorted().map(String.init).joined(separator: ",") })
    }

    private var currentIndex: Int? {
        guard order.indices.contains(position), order.allSatisfy({ $0 < cards.count }) else { return nil }
        return order[position]
    }

    /// Cards matching the sidebar, the level filter and the Notation/Equations picker.
    private var selectedCards: [Card] {
        let groups = selected.wrappedValue
        let levels = excludedLevels.wrappedValue
        return cards.filter { kind.includes($0) && groups.contains($0.key) && !levels.contains($0.level) }
    }

    private var sourceProgress: [String: (known: Int, total: Int)] {
        let levels = excludedLevels.wrappedValue
        var result: [String: (known: Int, total: Int)] = [:]
        for card in cards where kind.includes(card) && !levels.contains(card.level) {
            var entry = result[card.src] ?? (0, 0)
            entry.total += 1
            if progress.known.contains(card.id) { entry.known += 1 }
            result[card.src] = entry
        }
        return result
    }

    private func source(_ card: Card) -> Source? { store.deck.sources.first { $0.id == card.src } }

    private func context(_ card: Card) -> String {
        guard let source = source(card) else { return card.src }
        let group = source.groups.first { $0.id == card.group }?.label ?? card.group
        return "\(source.title) · \(group)"
    }

    private func levelLabel(_ card: Card) -> String {
        store.deck.levels.first { $0.id == card.level }?.label ?? "Level \(card.level)"
    }

    private func payload(_ card: Card) -> CardPayload {
        CardPayload(
            card: card,
            flipped: flipped,
            prompt: direction == .meaning ? .meaning : .symbol,
            known: progress.known.contains(card.id),
            review: progress.review.contains(card.id),
            kindLabel: card.isEquation ? "Equation" : "Notation",
            context: context(card),
            level: levelLabel(card),
            hint: card.isEquation
                ? "Read the equation aloud and explain each term, then click the card or press Space to check."
                : "Say how this is read and what it means, then click the card or press Space to check.")
    }

    var body: some View {
        NavigationSplitView {
            FilterView(
                deck: store.deck,
                selected: selected,
                excludedLevels: excludedLevels,
                collapsed: $session.collapsedSources,
                progress: sourceProgress,
                cardCount: order.count,
                cardNoun: kind == .both ? "cards" : "\(kind.title.lowercased()) cards")
            .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            detail
                .padding(24)
                .toolbar { toolbar }
        }
        .onAppear(perform: rebuild)
        .onChange(of: selectedRaw) { rebuild() }
        .onChange(of: excludedRaw) { rebuild() }
        .onChange(of: shuffle) { rebuild() }
        .onChange(of: modeRaw) { rebuild() }
        .onChange(of: kindRaw) { rebuild() }
        .onChange(of: studyRaw) { rebuild() }
        .onChange(of: directionRaw) { session.flipped = false }
        .onChange(of: store.revision) { rebuild() }
        .onChange(of: session.position) { speaker.stop() }
        .sheet(isPresented: $printRequest.isPresented) {
            PrintSheetView(
                cards: selectedCards,
                reviewIDs: progress.review,
                heading: { source($0)?.title ?? $0.src },
                meta: { "\(levelLabel($0)) · \(context($0))" },
                title: printTitle,
                onClose: { printRequest.isPresented = false })
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var printTitle: String {
        let ids = Set(selectedCards.map(\.src))
        let titles = store.deck.sources.filter { ids.contains($0.id) }.map(\.title)
        return titles.isEmpty || titles.count == store.deck.sources.count
            ? store.deck.title
            : "\(store.deck.title) — \(titles.joined(separator: ", "))"
    }

    @ViewBuilder
    private var detail: some View {
        if study == .test && session.finished {
            testSummary
        } else if let index = currentIndex {
            let card = cards[index]
            VStack(spacing: 18) {
                header
                MathCardView(payload: payload(card)) {
                    if study == .test { session.flipped = true }
                }
                controls(card)
            }
        } else {
            ContentUnavailableView(
                "No cards to practice",
                systemImage: "rectangle.stack",
                description: Text(emptyHint))
        }
    }

    private var emptyHint: String {
        switch mode {
        case .review: "No cards are marked for review in the selected topics. Press R on a card to mark it."
        case .notKnown: "Every card in the selected topics is marked known."
        case .all: "Tick at least one level and one topic in the sidebar."
        }
    }

    private var header: some View {
        HStack {
            Text("Card \(position + 1) of \(order.count)")
                .font(.headline)
            Spacer()
            if study == .test {
                let answered = session.answers.count
                let correct = session.answers.values.filter { $0 }.count
                Text("Score \(correct) of \(answered) · \(order.count - answered) to go")
                    .font(.callout.weight(.medium))
            } else {
                let ids = Set(order.map { cards[$0].id })
                Text("Known \(ids.intersection(progress.known).count) · Review \(ids.intersection(progress.review).count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var testSummary: some View {
        let correct = session.answers.values.filter { $0 }.count
        let missed = order.filter { session.answers[cards[$0].id] == false }
        let percent = order.isEmpty ? 0 : Int((Double(correct) / Double(order.count) * 100).rounded())
        VStack(spacing: 16) {
            Image(systemName: missed.isEmpty ? "star.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(missed.isEmpty ? .yellow : .green)
            Text("Test complete").font(.largeTitle.weight(.semibold))
            Text("\(correct) of \(order.count) correct (\(percent)%)").font(.title2)
            Text(missed.isEmpty
                 ? "Every card is now marked known."
                 : "Cards you got are marked known; the \(missed.count) you missed are marked for review.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if !missed.isEmpty {
                    Button("Retest the \(missed.count) missed") { retest(missed) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                Button("Start a new test") { rebuild() }
                Button("Switch to Learn") { studyRaw = StudyMode.learn.rawValue }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func controls(_ card: Card) -> some View {
        HStack(spacing: 12) {
            Button { move(-1) } label: { Label("Previous", systemImage: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            if study == .test {
                if flipped {
                    Button { answer(card.id, correct: false) } label: { Label("Missed it (M)", systemImage: "xmark.circle") }
                        .keyboardShortcut("m", modifiers: [])
                        .tint(.orange)
                    Button { answer(card.id, correct: true) } label: { Label("Got it (G)", systemImage: "checkmark.circle") }
                        .keyboardShortcut("g", modifiers: [])
                        .tint(.green)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button { session.flipped = true } label: { Label("Show answer", systemImage: "eye") }
                        .keyboardShortcut(.space, modifiers: [])
                        .buttonStyle(.borderedProminent)
                }
            }
            Button { move(1) } label: {
                Label(study == .test ? "Skip" : "Next", systemImage: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            Spacer()
            Button { speaker.speak(card.read) } label: { Label("Read aloud (S)", systemImage: "speaker.wave.2") }
                .keyboardShortcut("s", modifiers: [])
                .disabled(!flipped)
                .help("Hear how the notation is read")
            if study == .learn {
                Button { progress.toggleKnown(card.id) } label: {
                    Label("Known (K)", systemImage: progress.known.contains(card.id) ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .keyboardShortcut("k", modifiers: [])
                Button { progress.toggleReview(card.id) } label: {
                    Label("Review (R)", systemImage: progress.review.contains(card.id) ? "flag.fill" : "flag")
                }
                .keyboardShortcut("r", modifiers: [])
            }
        }
        .controlSize(.large)
    }

    /// Records the answer, updates known/review, and moves to the next unanswered card.
    private func answer(_ id: String, correct: Bool) {
        session.answers[id] = correct
        if correct { progress.markKnown(id) } else { progress.markReview(id) }
        let next = (1...order.count).map { (position + $0) % order.count }
            .first { session.answers[cards[order[$0]].id] == nil }
        if let next {
            session.position = next
            session.flipped = false
        } else {
            session.finished = true
        }
    }

    private func retest(_ indices: [Int]) {
        session.order = shuffle ? indices.shuffled() : indices
        session.position = 0
        session.flipped = false
        session.answers = [:]
        session.finished = false
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Cards", selection: $kindRaw) {
                ForEach(CardKind.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .help("Practice single symbols, whole equations, or both")
        }
        ToolbarItem(placement: .navigation) {
            Picker("Mode", selection: $studyRaw) {
                ForEach(StudyMode.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .help("Learn: see each card in full. Test: recall it, then mark whether you got it.")
        }
        ToolbarItemGroup {
            Picker("Test direction", selection: $directionRaw) {
                ForEach(TestDirection.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.menu)
            .disabled(study == .learn)
            .help("In Test mode, show the notation and recall its meaning, or the other way round")
            Picker("Practice", selection: $modeRaw) {
                ForEach(PracticeMode.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Toggle(isOn: $shuffle) { Label("Shuffle", systemImage: "shuffle") }
                .help("Shuffle the cards. Off: course order, from Grade 5 up to Masters.")
            Button { rebuild() } label: { Label("Restart", systemImage: "arrow.counterclockwise") }
                .help("Start again from the first card")
            Button { printRequest.isPresented = true } label: { Label("Print", systemImage: "printer") }
                .help("Print the selected cards as a study sheet or save them as a PDF")
        }
    }

    private func move(_ delta: Int) {
        guard !order.isEmpty else { return }
        session.position = (position + delta + order.count) % order.count
        session.flipped = false
    }

    private func rebuild() {
        let ids = Dictionary(cards.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var picked = selectedCards.compactMap { ids[$0.id] }
        switch mode {
        case .all: break
        case .notKnown: picked.removeAll { progress.known.contains(cards[$0].id) }
        case .review: picked.removeAll { !progress.review.contains(cards[$0].id) }
        }
        session.order = shuffle ? picked.shuffled() : picked
        session.position = 0
        session.flipped = false
        session.answers = [:]
        session.finished = false
    }
}

@MainActor
final class StudySession: ObservableObject {
    @Published var order: [Int] = []
    @Published var position = 0
    @Published var flipped = false
    @Published var collapsedSources: Set<String> = []
    /// Test mode: card id → whether it was recalled correctly in this run.
    @Published var answers: [String: Bool] = [:]
    @Published var finished = false
}

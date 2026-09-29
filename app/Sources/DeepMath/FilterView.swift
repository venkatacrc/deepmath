import SwiftUI

struct FilterView: View {
    let deck: Deck
    @Binding var selected: Set<String>
    @Binding var excludedLevels: Set<Int>
    @Binding var collapsed: Set<String>
    /// Known and total card counts per source, for the current card kind and levels.
    let progress: [String: (known: Int, total: Int)]
    let cardCount: Int
    let cardNoun: String

    var body: some View {
        List {
            Section("Levels") {
                ForEach(deck.levels) { level in
                    Toggle(level.label, isOn: Binding(
                        get: { !excludedLevels.contains(level.id) },
                        set: { on in
                            if on { excludedLevels.remove(level.id) } else { excludedLevels.insert(level.id) }
                        }))
                    .toggleStyle(.checkbox)
                }
            }

            Section("Practice these") {
                ForEach(deck.sources) { source in
                    DisclosureGroup(isExpanded: Binding(
                        get: { !collapsed.contains(source.id) },
                        set: { open in
                            if open { collapsed.remove(source.id) } else { collapsed.insert(source.id) }
                        })
                    ) {
                        Text(source.ai)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Select all") { setAll(source, on: true) }
                            Button("Clear") { setAll(source, on: false) }
                        }
                        .buttonStyle(.link)
                        .font(.caption)

                        ForEach(source.groups) { group in
                            Toggle(group.label, isOn: binding(for: GroupKey.make(source.id, group.id)))
                                .toggleStyle(.checkbox)
                        }
                    } label: {
                        HStack {
                            Text(source.title).font(.headline)
                            Spacer()
                            if let p = progress[source.id], p.total > 0 {
                                Text("\(p.known)/\(p.total)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(p.known == p.total ? .green : .secondary)
                                    .help("\(p.known) of \(p.total) cards known")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                Text("∇")
                    .font(.system(size: 32, weight: .semibold, design: .serif))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(red: 0.42, green: 0.45, blue: 0.98), Color(red: 0.23, green: 0.16, blue: 0.72)],
                        startPoint: .top, endPoint: .bottom))
                Text(deck.title).font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom) {
            Text("\(cardCount) \(cardNoun) selected")
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.bar)
        }
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(key) },
            set: { on in
                if on { selected.insert(key) } else { selected.remove(key) }
            })
    }

    private func setAll(_ source: Source, on: Bool) {
        for group in source.groups {
            let key = GroupKey.make(source.id, group.id)
            if on { selected.insert(key) } else { selected.remove(key) }
        }
    }
}

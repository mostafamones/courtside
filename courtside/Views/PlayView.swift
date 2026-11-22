import SwiftUI

struct PlayView: View {
    @Environment(AppStore.self) private var store
    @Binding var showScoreboard: Bool
    @Binding var setupRequest: SetupRequest?
    @State private var editingRulePreset: RulePreset?

    var body: some View {
        NavigationStack {
            List {
                if let active = store.activeMatch {
                    Section("In progress") {
                        Button { showScoreboard = true } label: {
                            MatchSummaryRow(record: active)
                        }
                        .buttonStyle(.plain)
                        Button("Resume scoring", systemImage: "play.fill") { showScoreboard = true }
                    }
                }

                Section {
                    Button("New match", systemImage: "plus.circle.fill") {
                        setupRequest = .newMatch(nil, presetName: nil)
                    }
                    .font(.headline)
                }

                Section {
                    if store.favourites.isEmpty {
                        Text("Swipe right on a match in History to save its lineup as a favourite. Favourites can also be started from your Watch.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.sortedFavourites) { favourite in
                        Button {
                            setupRequest = .newMatch(favourite.setup, presetName: favourite.name)
                        } label: {
                            FavouriteRow(favourite: favourite)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) { store.deleteFavourite(favourite) }.tint(.red)
                            Button("Edit") { setupRequest = .editFavourite(favourite) }.tint(.blue)
                        }
                    }
                } header: {
                    Text("Favourites")
                }

                Section {
                    ForEach(store.sortedRulePresets) { preset in
                        Button { editingRulePreset = preset } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name).font(.headline)
                                Text(preset.rules.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) { store.deleteRulePreset(preset) }.tint(.red)
                        }
                    }
                    Button("New rule preset", systemImage: "plus") {
                        editingRulePreset = RulePreset(name: "", rules: .standard)
                    }
                } header: {
                    Text("Rule presets")
                } footer: {
                    Text("Your own scoring rules, e.g. a fast match. Pick one when starting any match.")
                }
            }
            .sheet(item: $editingRulePreset) { RulePresetEditor(preset: $0) }
            .navigationTitle("Courtside")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }
}

struct FavouriteRow: View {
    let favourite: Favourite

    var body: some View {
        HStack(spacing: 14) {
            Text(favourite.emoji)
                .font(.system(size: 26))
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(favourite.name).font(.headline)
                TeamLine(setup: favourite.setup, team: .a)
                TeamLine(setup: favourite.setup, team: .b)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

struct TeamLine: View {
    let setup: MatchSetup
    let team: TeamSide

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(setup.colors[team].color).frame(width: 10, height: 10)
            Text(setup.teamName(team)).font(.subheadline)
        }
    }
}

struct MatchSummaryRow: View {
    let record: MatchRecord

    var body: some View {
        let state = record.state
        VStack(alignment: .leading, spacing: 6) {
            ForEach(TeamSide.allCases, id: \.self) { team in
                HStack(spacing: 8) {
                    if record.leader == team {
                        Image(systemName: "medal.fill").foregroundStyle(.yellow).frame(width: 10)
                    } else {
                        Circle().fill(record.setup.colors[team].color).frame(width: 10, height: 10)
                    }
                    Text(record.setup.teamName(team))
                        .fontWeight(record.leader == team ? .bold : .regular)
                        .lineLimit(1)
                    Spacer()
                    SetScoresText(record: record, team: team)
                }
            }
            HStack {
                StatusBadge(status: record.status)
                Text(record.startedAt, format: .dateTime.day().month().year().hour().minute())
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

struct SetScoresText: View {
    let record: MatchRecord
    let team: TeamSide

    var body: some View {
        let state = record.state
        HStack(spacing: 10) {
            ForEach(Array(state.completedSets.enumerated()), id: \.offset) { _, set in
                Text(set.isMatchTiebreak ? "\(set.tiebreak?[team] ?? 0)" : "\(set.games[team])")
                    .fontWeight(set.winner == team ? .bold : .regular)
            }
            if record.status == .inProgress || (record.status == .endedEarly && state.games != .zero) {
                Text("\(state.games[team])")
                    .fontWeight(state.games[team] > state.games[team.opponent] ? .bold : .regular)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }
}

struct StatusBadge: View {
    let status: MatchStatus

    var body: some View {
        let (title, color): (String, Color) = switch status {
        case .inProgress: ("In progress", .orange)
        case .completed: ("Completed", .green)
        case .endedEarly: ("Ended early", .gray)
        }
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.25), in: Capsule())
            .foregroundStyle(color)
    }
}

struct RulePresetEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var preset: RulePreset

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Fast match", text: $preset.name)
                }
                Section("Rules") {
                    RulesFields(rules: $preset.rules)
                }
            }
            .navigationTitle(store.rulePresets.contains { $0.id == preset.id } ? "Edit rule preset" : "New rule preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        preset.name = preset.name.trimmingCharacters(in: .whitespaces)
                        store.saveRulePreset(preset)
                        dismiss()
                    }
                    .disabled(preset.name.nilIfBlank == nil)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

extension MatchRecord {
    /// The winner, or for unfinished matches whoever leads on sets, then games.
    var leader: TeamSide? {
        let state = state
        if let winner = state.winner { return winner }
        let sets = TeamPair(a: state.completedSets.filter { $0.winner == .a }.count,
                            b: state.completedSets.filter { $0.winner == .b }.count)
        if sets.a != sets.b { return sets.a > sets.b ? .a : .b }
        if state.games.a != state.games.b { return state.games.a > state.games.b ? .a : .b }
        return nil
    }
}

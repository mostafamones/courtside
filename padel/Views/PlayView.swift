import SwiftUI

struct PlayView: View {
    @Environment(AppStore.self) private var store
    @Binding var showScoreboard: Bool
    @Binding var setupRequest: SetupRequest?

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

                Section("Presets") {
                    if store.presets.isEmpty {
                        Text("Save a lineup and rules as a preset when you set up a match — handy for recurring groups like “Thursday padel”.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.presets.sorted { $0.name < $1.name }) { preset in
                        Button {
                            setupRequest = .newMatch(preset.setup, presetName: preset.name)
                        } label: {
                            PresetRow(preset: preset)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) { store.deletePreset(preset) }
                            Button("Edit") { setupRequest = .editPreset(preset) }
                        }
                    }
                }
            }
            .navigationTitle("Padel")
        }
    }
}

struct PresetRow: View {
    let preset: MatchPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(preset.name).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            TeamLine(setup: preset.setup, team: .a)
            TeamLine(setup: preset.setup, team: .b)
            Text(preset.setup.rules.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    Circle().fill(record.setup.colors[team].color).frame(width: 10, height: 10)
                    Text(record.setup.teamName(team))
                        .fontWeight(state.winner == team ? .bold : .regular)
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
                Text("\(state.games[team])").foregroundStyle(.secondary)
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

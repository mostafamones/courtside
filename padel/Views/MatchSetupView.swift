import SwiftUI

struct MatchSetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let request: SetupRequest
    let onStart: (MatchSetup, String?) -> Void

    @State private var slots: [PlayerSnapshot?] = [nil, nil, nil, nil]
    @State private var colors = TeamPair<TeamColor>(a: .gold, b: .turquoise)
    @State private var useStandardRules = true
    @State private var rules = MatchRules.standard
    @State private var firstServingTeam: TeamSide = .a
    @State private var firstServer = 0
    @State private var opposingFirstServer = 2
    @State private var saveAsPreset = false
    @State private var presetName = ""
    @State private var addingPlayerToSlot: Int?
    @State private var newPlayerName = ""
    @State private var didLoad = false

    private var isEditingPreset: Bool {
        if case .editPreset = request { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                if isEditingPreset || saveAsPreset {
                    Section("Preset") {
                        TextField("Name, e.g. Thursday padel", text: $presetName)
                    }
                }
                teamSection(.a)
                teamSection(.b)
                rulesSection
                servingSection
                if !isEditingPreset {
                    Section {
                        Toggle("Save as preset", isOn: $saveAsPreset)
                    } footer: {
                        Text("Presets keep the lineup, colors and rules. Editing a preset never changes past matches.")
                    }
                }
            }
            .navigationTitle(isEditingPreset ? "Edit preset" : "New match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditingPreset ? "Save" : "Start") { submit() }
                        .disabled(!canSubmit)
                        .fontWeight(.semibold)
                }
            }
            .alert("New player", isPresented: Binding(
                get: { addingPlayerToSlot != nil },
                set: { if !$0 { addingPlayerToSlot = nil } }
            )) {
                TextField("Name", text: $newPlayerName)
                Button("Add") {
                    if let slot = addingPlayerToSlot, let name = newPlayerName.nilIfBlank {
                        slots[slot] = PlayerSnapshot(store.addPlayer(name: name))
                    }
                    newPlayerName = ""
                }
                Button("Cancel", role: .cancel) { newPlayerName = "" }
            }
            .onAppear(perform: load)
            .onChange(of: firstServingTeam) { _, team in
                // Keep the first server on the chosen team and the other on the opponents.
                if MatchSetup.team(of: firstServer) != team {
                    swap(&firstServer, &opposingFirstServer)
                }
            }
        }
    }

    // MARK: Sections

    private func teamSection(_ team: TeamSide) -> some View {
        let base = team == .a ? 0 : 2
        return Section {
            ForEach(base..<(base + 2), id: \.self) { slot in
                playerPicker(slot: slot)
            }
            Picker("Color", selection: Binding(get: { colors[team] }, set: { colors[team] = $0 })) {
                ForEach(TeamColor.allCases) { color in
                    Label(color.title, systemImage: "circle.fill")
                        .tint(color.color)
                        .tag(color)
                        .disabled(colors[team.opponent] == color)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            HStack {
                Circle().fill(colors[team].color).frame(width: 10, height: 10)
                Text(team == .a ? "Team 1 · top / left" : "Team 2 · bottom / right")
                Spacer()
                if team == .b {
                    Button("Swap partners", systemImage: "arrow.up.arrow.down") { swapPartners() }
                        .font(.caption)
                        .textCase(nil)
                }
            }
        }
    }

    private func playerPicker(slot: Int) -> some View {
        let taken = Set(slots.enumerated().compactMap { $0.offset == slot ? nil : $0.element?.id })
        return Menu {
            ForEach(store.sortedPlayers.filter { !taken.contains($0.id) }) { player in
                Button(player.displayName) { slots[slot] = PlayerSnapshot(player) }
            }
            Divider()
            Button("New player…", systemImage: "person.badge.plus") { addingPlayerToSlot = slot }
            if slots[slot] != nil {
                Button("Clear", systemImage: "xmark", role: .destructive) { slots[slot] = nil }
            }
        } label: {
            HStack {
                Text("Player \(slot % 2 + 1)").foregroundStyle(.secondary)
                Spacer()
                Text(slots[slot]?.name ?? "Choose")
                    .foregroundStyle(slots[slot] == nil ? Color.accentColor : .primary)
            }
        }
    }

    private var rulesSection: some View {
        Section("Scoring") {
            Picker("Rules", selection: $useStandardRules) {
                Text("Standard").tag(true)
                Text("Custom").tag(false)
            }
            .pickerStyle(.segmented)
            .onChange(of: useStandardRules) { _, standard in
                if standard { rules = .standard }
            }

            if useStandardRules {
                Text(MatchRules.standard.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Match length", selection: $rules.setsToWin) {
                    Text("One set").tag(1)
                    Text("Best of three").tag(2)
                    Text("Best of five").tag(3)
                }
                Picker("Deuce", selection: $rules.deuceRule) {
                    ForEach(DeuceRule.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Games per set", selection: $rules.gamesPerSet) {
                    Text("4 (tiebreak at 4–4)").tag(4)
                    Text("6 (tiebreak at 6–6)").tag(6)
                }
                Picker("Tiebreak to", selection: $rules.tiebreakTarget) {
                    Text("7 points").tag(7)
                    Text("10 points").tag(10)
                }
                if rules.setsToWin > 1 {
                    Picker("Deciding set", selection: $rules.decidingSet) {
                        ForEach(DecidingSet.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
        }
    }

    private var servingSection: some View {
        Section {
            Picker("Serves first", selection: $firstServingTeam) {
                Text(teamLabel(.a)).tag(TeamSide.a)
                Text(teamLabel(.b)).tag(TeamSide.b)
            }
            Picker("First server", selection: $firstServer) {
                ForEach(indices(of: firstServingTeam), id: \.self) { Text(name(at: $0)).tag($0) }
            }
            Picker("Opponents' first server", selection: $opposingFirstServer) {
                ForEach(indices(of: firstServingTeam.opponent), id: \.self) { Text(name(at: $0)).tag($0) }
            }
        } header: {
            Text("Serving order")
        } footer: {
            Text("Rotation: " + setupDraft.serveOrder.map { name(at: $0) }.joined(separator: " → "))
        }
    }

    // MARK: Logic

    private func indices(of team: TeamSide) -> [Int] { team == .a ? [0, 1] : [2, 3] }

    private func name(at index: Int) -> String { slots[index]?.name ?? "Player \(index % 2 + 1)" }

    private func teamLabel(_ team: TeamSide) -> String {
        indices(of: team).map { name(at: $0) }.joined(separator: " & ")
    }

    private var setupDraft: MatchSetup {
        var setup = MatchSetup(players: slots.enumerated().map {
            $0.element ?? PlayerSnapshot(id: UUID(), name: "Player \($0.offset % 2 + 1)")
        })
        setup.colors = colors
        setup.rules = useStandardRules ? .standard : rules
        setup.firstServer = firstServer
        setup.opposingFirstServer = opposingFirstServer
        return setup
    }

    private var canSubmit: Bool {
        guard slots.allSatisfy({ $0 != nil }), setupDraft.isValid else { return false }
        if isEditingPreset || saveAsPreset { return presetName.nilIfBlank != nil }
        return true
    }

    private func swapPartners() {
        // Move team 1's second player to team 2 and vice versa to rearrange teams.
        slots.swapAt(1, 2)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let initial: MatchSetup?
        switch request {
        case .newMatch(let setup, let name):
            initial = setup
            presetName = name ?? ""
        case .editPreset(let preset):
            initial = preset.setup
            presetName = preset.name
        }
        guard let initial else { return }
        // Refresh names from current profiles where they still exist.
        slots = initial.players.map { snapshot in
            store.player(id: snapshot.id).map(PlayerSnapshot.init) ?? snapshot
        }
        colors = initial.colors
        rules = initial.rules
        useStandardRules = initial.rules == .standard
        firstServingTeam = MatchSetup.team(of: initial.firstServer)
        firstServer = initial.firstServer
        opposingFirstServer = initial.opposingFirstServer
    }

    private func submit() {
        let setup = setupDraft
        switch request {
        case .editPreset(var preset):
            preset.name = presetName.nilIfBlank ?? preset.name
            preset.setup = setup
            store.savePreset(preset)
            dismiss()
        case .newMatch:
            var name: String?
            if saveAsPreset, let presetName = presetName.nilIfBlank {
                store.savePreset(MatchPreset(name: presetName, setup: setup))
                name = presetName
            } else if let existing = presetName.nilIfBlank {
                name = existing
            }
            onStart(setup, name)
        }
    }
}

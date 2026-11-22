import SwiftUI

struct MatchSetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let request: SetupRequest
    let onStart: (MatchSetup, String?) -> Void

    @State private var slots: [PlayerSnapshot?] = [nil, nil, nil, nil]
    @State private var colors = TeamPair<TeamColor>(a: .gold, b: .turquoise)
    @State private var ruleChoice = RuleChoice.standard
    @State private var rules = MatchRules.standard
    @State private var savingRulePreset = false
    @State private var rulePresetName = ""
    @State private var firstServingTeam: TeamSide = .a
    @State private var firstServer = 0
    @State private var opposingFirstServer = 2
    @State private var favouriteName = ""
    @State private var favouriteEmoji = Favourite.defaultEmoji
    @State private var showSettings = false
    @State private var addingPlayerToSlot: Int?
    @State private var newPlayerName = ""
    @State private var didLoad = false

    /// Which rules the match uses. Picking a preset copies its rules; editing them makes it custom.
    enum RuleChoice: Hashable {
        case standard
        case preset(UUID)
        case custom
    }

    private var isEditingFavourite: Bool {
        if case .editFavourite = request { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                if isEditingFavourite {
                    Section("Favourite") {
                        TextField("Name, e.g. Thursday padel", text: $favouriteName)
                        EmojiPicker(selection: $favouriteEmoji)
                    }
                }
                teamSection(.a)
                teamSection(.b)
            }
            .navigationDestination(isPresented: $showSettings) {
                Form {
                    rulesSection
                    servingSection
                }
                .navigationTitle("Scoring & serving")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isEditingFavourite ? "Save" : "Start") { submit() }
                            .disabled(!canSubmit)
                            .fontWeight(.semibold)
                    }
                }
                .alert("Save rules as preset", isPresented: $savingRulePreset) {
                    TextField("Name, e.g. Fast match", text: $rulePresetName)
                    Button("Save") {
                        if let name = rulePresetName.nilIfBlank {
                            let preset = RulePreset(name: name, rules: rules)
                            store.saveRulePreset(preset)
                            ruleChoice = .preset(preset.id)
                        }
                        rulePresetName = ""
                    }
                    Button("Cancel", role: .cancel) { rulePresetName = "" }
                }
            }
            .navigationTitle(isEditingFavourite ? "Edit favourite" : "New match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { showSettings = true }
                        .disabled(!hasAllPlayers)
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
                    Label {
                        Text(color.title)
                    } icon: {
                        Circle().fill(color.color).frame(width: 14, height: 14)
                    }
                    .tag(color)
                        .disabled(colors[team.opponent] == color)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            HStack {
                Circle().fill(colors[team].color).frame(width: 10, height: 10)
                Text(team == .a ? "Team 1" : "Team 2")
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
        Section {
            Picker("Rules", selection: $ruleChoice) {
                Text("Standard").tag(RuleChoice.standard)
                ForEach(store.sortedRulePresets) { Text($0.name).tag(RuleChoice.preset($0.id)) }
                Text("Custom").tag(RuleChoice.custom)
            }
            .onChange(of: ruleChoice) { _, choice in
                switch choice {
                case .standard: rules = .standard
                case .preset(let id): rules = store.rulePresets.first { $0.id == id }?.rules ?? rules
                case .custom: break
                }
            }

            if ruleChoice == .custom {
                RulesFields(rules: $rules)
                Button("Save as rule preset…", systemImage: "square.and.arrow.down") { savingRulePreset = true }
            } else {
                Text(rules.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Scoring")
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
        setup.rules = rules
        setup.firstServer = firstServer
        setup.opposingFirstServer = opposingFirstServer
        return setup
    }

    private var hasAllPlayers: Bool { slots.allSatisfy { $0 != nil } }

    private var canSubmit: Bool {
        guard hasAllPlayers, setupDraft.isValid else { return false }
        if isEditingFavourite { return favouriteName.nilIfBlank != nil }
        return true
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let initial: MatchSetup?
        switch request {
        case .newMatch(let setup, let name):
            initial = setup
            favouriteName = name ?? ""
        case .editFavourite(let favourite):
            initial = favourite.setup
            favouriteName = favourite.name
            favouriteEmoji = favourite.emoji
        }
        guard let initial else { return }
        // Refresh names from current profiles where they still exist.
        slots = initial.players.map { snapshot in
            store.player(id: snapshot.id).map(PlayerSnapshot.init) ?? snapshot
        }
        colors = initial.colors
        rules = initial.rules
        if initial.rules == .standard {
            ruleChoice = .standard
        } else if let preset = store.rulePresets.first(where: { $0.rules == initial.rules }) {
            ruleChoice = .preset(preset.id)
        } else {
            ruleChoice = .custom
        }
        firstServingTeam = MatchSetup.team(of: initial.firstServer)
        firstServer = initial.firstServer
        opposingFirstServer = initial.opposingFirstServer
    }

    private func submit() {
        let setup = setupDraft
        switch request {
        case .editFavourite(var favourite):
            favourite.name = favouriteName.nilIfBlank ?? favourite.name
            favourite.emoji = favouriteEmoji
            favourite.setup = setup
            store.saveFavourite(favourite)
            dismiss()
        case .newMatch:
            onStart(setup, favouriteName.nilIfBlank)
        }
    }
}

/// The custom rule pickers, shared by match setup and the rule preset editor.
struct RulesFields: View {
    @Binding var rules: MatchRules

    var body: some View {
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

struct EmojiPicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
            ForEach(Favourite.emojiChoices, id: \.self) { emoji in
                Button { selection = emoji } label: {
                    Text(emoji)
                        .font(.title2)
                        .frame(width: 36, height: 36)
                        .background(selection == emoji ? Color.accentColor.opacity(0.3) : .clear, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == emoji ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

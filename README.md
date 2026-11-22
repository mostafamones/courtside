# Courtside

Courtside is a padel scorekeeper for iPhone and Apple Watch. Set up a doubles match, record points on either device, and review the result on your iPhone. The scoreboard shows the current game, set scores, and who serves next. The iPhone app works offline and requires no account.

## Start a match

1. On iPhone, open **Play → New match**. Select four distinct players, two per team, and choose a color for each team. You can create a player directly from the match setup.
2. Tap **Next** to open **Scoring & serving**. Choose standard rules, a saved rule preset, or custom rules. Select the first serving team and the first server on each team.
3. Tap **Start**. In portrait, the phone stacks the teams. In landscape, it places them side by side. The Apple Watch always stacks the teams.
4. If you minimize the iPhone scoreboard mid-match, choose **Resume scoring** in **Play** to come back to it.

### Score points

| Action | iPhone | Apple Watch |
| --- | --- | --- |
| Add a point | Tap the team’s panel. | Tap the team’s half. |
| Remove a point from the current game | Double-tap the team’s panel. | Double-tap the team’s half. |
| Undo the most recent action | Tap the undo button at the top of the scoreboard. | Long-press the scoreboard, then tap **Undo last action**. |
| Swap the displayed teams | Open the scoreboard menu and choose **Switch sides**. The same menu can also switch sides on the Watch. | Long-press the scoreboard, then tap **Switch sides**. |

The green service marker indicates the server and serving side. Courtside asks for confirmation before advancing past a winning game or tiebreak point, so you can correct the point before the next game starts. With golden-point scoring, choose the receiving side at deuce. You can also end a match early from the iPhone menu and keep the score reached so far.

### Scoring formats

| Setting | Available options | Standard |
| --- | --- | --- |
| Match length | One set, best of three, best of five | Best of three |
| Deuce | Advantage or golden point | Advantage |
| Games per set | Four or six, with a tiebreak at 4–4 or 6–6 | Six |
| Set tiebreak | First to seven or ten points, win by two | Seven points |
| Deciding set | Normal set or a 10-point match tiebreak, win by two | Normal set |

Save a custom format under **Play → Rule presets** to reuse it with any lineup.

## Match history, players, and favourites

- **History** lists completed and ended-early matches. Open one to see the result, individual set scores, match duration, points won by each team, and the rules used. **Play again** opens a new match setup with the same lineup and settings.
- **Players** holds your local roster, with optional nicknames and each player’s match and win counts. Swipe right on your own profile and tap **This is me** to place your team at the bottom of the Watch scoreboard when a new match starts.
- **Favourites** save a lineup together with its team colors, rules, and service order. Swipe right on a match in **History**, choose **Favourite**, and give it a name and emoji. Open it from **Play** or start it directly from Apple Watch after it syncs.

## Apple Watch and local data

Install the companion app on a paired Apple Watch. When you start a match on iPhone, the Watch shows the live scoreboard. Changes made on either device sync back to the other, including matches started from a synced favourite on the Watch.

WatchConnectivity sends the current match record. If both devices make a change before hearing from the other, the newer timestamped record wins. Each device can keep scoring locally while the counterpart is out of reach, and the latest match state is available for delivery when connectivity returns.

The iPhone stores players, favourites, rule presets, and matches as JSON in its app sandbox under `Application Support/PadelStore`. The Watch caches its current match and synced favourites in `UserDefaults`. Match records include snapshots of the players’ names, so edits to the roster preserve the names shown in past matches.

## Build and run

Use Xcode 26.4 or newer with iOS and watchOS platform support installed. The project sets iOS 26.4 and watchOS 26.4 as its minimum deployment versions. It uses Apple frameworks and has no external package dependencies.

1. Open `courtside.xcodeproj` in Xcode.
2. Select the `courtside` scheme and an iPhone simulator, then run the app.
3. Select the `courtsideWatch` scheme to run the companion app on an Apple Watch simulator. Use a paired iPhone and Apple Watch to check scoring and favourite sync between devices.
4. For a physical device build, select your development team under **Signing & Capabilities** for both app targets. If your team needs a different bundle identifier, update the Watch target’s companion bundle identifier to match the iPhone app.

The iPhone app uses `mones.courtside` and the Watch app uses `mones.courtside.watchkitapp`. An installation with the previous Padel bundle identifier keeps its own local data.

### Run the scoring tests

```sh
xcodebuild test -project courtside.xcodeproj -scheme courtside \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:courtsideTests
```

Replace **iPhone 17** with an installed simulator name if needed. Unit tests cover scoring, deuce, tiebreaks, service rotation, undo, and persistence. The separate `courtsideUITests` target contains launch checks.

## Project layout

| Path | Role |
| --- | --- |
| [`courtside/Views/`](courtside/Views) | SwiftUI match setup, scoreboard, history, and roster |
| [`courtside/Scoring/`](courtside/Scoring) | Shared scoring engine, rules, and service rotation |
| [`courtside/Models/`](courtside/Models) | Shared player, lineup, and match records |
| [`courtside/Store/`](courtside/Store) | iPhone match state and JSON persistence |
| [`courtside/Sync/`](courtside/Sync) | WatchConnectivity transport shared by both targets |
| [`courtsideWatch/`](courtsideWatch) | Watch scoreboard, match controls, and local cache |
| [`courtsideTests/`](courtsideTests) and [`courtsideUITests/`](courtsideUITests) | Scoring and persistence tests, plus UI launch checks |

The scoring engine derives the current score by replaying the match’s action log from the initial rules and service order. Both targets use that engine, so each device can compute the same state from the same record.

## App icon

Both app targets use [`Courtside.icon`](courtside/Courtside.icon), which contains the editable court and ball layers. Open the package in Icon Composer to update the shared icon, then rebuild the app. [Apple’s Icon Composer guide](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)

# Producer Tycoon (Swift)

Universal SwiftUI port (iOS + macOS) of **Producer Tycoon** — the satirical
music-label simulator from [Rafthouse/The-Producer-Game](https://github.com/Rafthouse/The-Producer-Game),
running the **co-evolved balanced world** from that repo's torchsim work
(`dc3f825`: theta knobs + adaptive dealer network at the 62% player-win
equilibrium).

## Architecture

```
producertycoon.swift/
├── project.yml                     # XcodeGen (universal app, iOS+macOS 26)
├── ProducerTycoon/                 # SwiftUI app: 3 tabs (Студія/Лейбл/Тренди)
├── producertycoonTests/            # app-hosted smoke tests (iOS)
└── Kits/Producer/ProducerKit/      # SwiftPM engine package (all game logic)
    ├── Sources/ProducerKit/
    │   ├── Resources/
    │   │   ├── game_constants.json    # single source of truth (exported from TS)
    │   │   ├── world_coevolved.json   # theta (18 knobs) + dealer (4024 params)
    │   │   └── text_bonus_dist.json   # lyrics-corpus fit histogram
    │   ├── ProducerEngine.swift       # scalar port of torchsim env_producer.py
    │   ├── ReleaseMath.swift          # pure release score/economics
    │   ├── TourMath.swift             # pure tour math
    │   ├── Dealer.swift               # attention dealer inference (13-dim memory)
    │   └── ...
    └── Tests/ProducerKitTests/     # 64 tests — run with `swift test`
```

No gameplay literal lives in engine code: everything is decoded from
`game_constants.json` (the torchsim anti-drift rule). The dealer is the
shipped adaptive world generator — it deals candidate artists conditioned on
session state and its own recent deals, holding difficulty at the calibrated
62% target. `tsRound` implements TS `Math.round` half-up semantics (the
parity target is the TypeScript game, not torch's half-even).

## Test provenance

- **Golden parity** (`MathParityTests`, `DealerTests`): expected values were
  computed with float64 numpy directly from the shipped artifacts using the
  `env_producer.py` formulas — the sim that holds 102/102 KS statistical
  parity vs the TS game. Dealer forward-pass goldens use the actual trained
  weights.
- **Gate parity** (`GateParityTests`): Swift mirrors of the scripted gate
  policies replay on the neutral world and must reproduce the real TS game's
  measured outcome rates (greedy-heuristic 0.686 win-fans / 0.312 bankrupt,
  sign-release-spam 0.775 bankrupt, random-legal ~1.0 bankrupt fast). Note:
  the once-per-artist-per-week release rule in those tests is the gate
  DRIVER's convention; the engine itself allows re-releases, and the
  coevolved `token_reward_mult` is what keeps that self-limiting.
- **Engine invariants** (`EngineTests`): weekly-transition ordering, clamps,
  win/lose precedence (victory beats game-over), theta bankruptcy floor,
  action cap + escape hatch, full-episode termination and determinism.

## Build & run

```bash
cd Kits/Producer/ProducerKit && swift test    # engine test suite
xcodegen generate                              # regenerate the Xcode project
xcodebuild -project producertycoon.swift.xcodeproj \
  -scheme producertycoon.swift -destination "platform=macOS" build
```

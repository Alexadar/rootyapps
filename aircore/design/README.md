# Airside — SwiftUI design handoff

Design-to-code scaffold for the Airside HVAC air-side calculator, in the **water-breeze**
palette. Physics lives in `AirsideKit` (pure Swift, oracle-testable); UI in `AirsideUI`
+ per-platform app targets.

```
AirsideSwift/
  Package.swift
  Sources/
    AirsideKit/            pure physics — no UI, no network, on-device
      Units.swift
      Altitude.swift
      Psychrometrics.swift
      AirSideHeat.swift
      DuctSizing.swift
      FanLaws.swift
      PipeSizing.swift
    AirsideUI/             shared design system + chart
      DesignSystem.swift
      PsychroChart.swift
      Components.swift
  Apps/
    iOS/     HomeView · PsychrometricsView · DuctView   (field tool, one-handed)
    iPadOS/  ChartWorkspaceView                          (chart as workspace)
    macOS/   MacContentView                              (desk work + export)
    watchOS/ WatchView                                   (one crown conversion)
```

## Scope guard (do not add)
Straight duct from friction only — **no** fitting losses, equivalent length, load calc,
or anything combustion/flue/vent/gas. No account, no network, no IAP. If a number shows on
screen, a Kit must be able to prove it.

## Using it
Open `Package.swift` in Xcode for the Kit + UI libraries. The files under `Apps/` are
SwiftUI views ready to drop into per-platform app targets (add them to a multiplatform
Xcode project; each declares its own `@main` App). Correlations: Hyland–Wexler saturation
pressure via a Magnus form; barometric pressure vs. elevation for altitude correction.

> Handoff scaffold — compiles as a starting point; wire persistence (state restoration on
> backgrounding), VoiceOver labels on every computed value and chart node, and Dynamic Type
> before shipping.

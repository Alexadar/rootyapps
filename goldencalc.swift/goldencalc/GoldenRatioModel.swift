// GoldenRatioModel.swift
// Golden ratio calculations separated from UI.
// Created by Cline assistant.

import Foundation
import Combine
import SwiftUI

final class GoldenRatioModel: ObservableObject {
    // Published so UI can observe changes if needed.
    @Published private(set) var lastUpdateSource: String? = nil

    // Constants as Float (per request: inputs/outputs are floats)
    let coefA: Float = 0.6180339887
    let coefB: Float = 0.3819660113
    let ratio: Float = 1.6180339887

    init() {}

    // High level helpers that are easy for UI to call:
    // When the user edits A, call this to get B and C.
    // In: a (Float)
    // Out: (b: Float, c: Float)
    func calcFromA(_ a: Float) -> (b: Float, c: Float) {
        let c = a * ratio
        let b = c * coefB
        lastUpdateSource = "a"
        return (b, c)
    }

    // When the user edits B, call this to get A and C.
    // In: b (Float)
    // Out: (a: Float, c: Float)
    func calcFromB(_ b: Float) -> (a: Float, c: Float) {
        // Follow the same math used in the app:
        // a = (b / coefB) * coefA
        let a = (b / coefB) * coefA
        let c = a * ratio
        lastUpdateSource = "b"
        return (a, c)
    }

    // When the user edits C, call this to get A and B.
    // In: c (Float)
    // Out: (a: Float, b: Float)
    func calcFromC(_ c: Float) -> (a: Float, b: Float) {
        let a = c * coefA
        let b = c * coefB
        lastUpdateSource = "c"
        return (a, b)
    }

    // Additionally provide the named functions requested by the task.
    // These compute a single value given the other two floats.
    // In: floats, Out: float
    func calculateA(b: Float, c: Float) -> Float {
        // a is derived from c
        lastUpdateSource = "calculateA(b,c)"
        return c * coefA
    }

    func calculateB(a: Float, c: Float) -> Float {
        // b is derived from c
        lastUpdateSource = "calculateB(a,c)"
        return c * coefB
    }

    func calculateC(a: Float, b: Float) -> Float {
        // c is derived from a (consistent with app)
        lastUpdateSource = "calculateC(a,b)"
        return a * ratio
    }
}

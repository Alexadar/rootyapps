import Foundation

public struct Complex: Sendable {
    public var re, im: Double
    public init(_ re: Double, _ im: Double) { self.re = re; self.im = im }
    public var magnitude: Double { (re * re + im * im).squareRoot() }
    static func + (a: Complex, b: Complex) -> Complex { Complex(a.re + b.re, a.im + b.im) }
    static func - (a: Complex, b: Complex) -> Complex { Complex(a.re - b.re, a.im - b.im) }
    static func * (a: Complex, b: Complex) -> Complex { Complex(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re) }
}

/// Iterative radix-2 Cooley-Tukey FFT (n must be a power of two). Pure, stateless.
public enum FFT {
    public static func transform(_ input: [Complex]) -> [Complex] {
        var a = input
        let n = a.count
        precondition(n & (n - 1) == 0, "length must be a power of two")
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { a.swapAt(i, j) }
        }
        var len = 2
        while len <= n {
            let ang = -2 * Double.pi / Double(len)
            let wlen = Complex(cos(ang), sin(ang))
            var i = 0
            while i < n {
                var w = Complex(1, 0)
                for k in 0..<(len / 2) {
                    let u = a[i + k]
                    let v = a[i + k + len / 2] * w
                    a[i + k] = u + v
                    a[i + k + len / 2] = u - v
                    w = w * wlen
                }
                i += len
            }
            len <<= 1
        }
        return a
    }
}

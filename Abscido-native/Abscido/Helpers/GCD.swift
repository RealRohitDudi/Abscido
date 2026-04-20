import Foundation

/// Computes the Greatest Common Divisor of two integers using the Euclidean algorithm.
/// Used for reducing CMTime rational fractions in FCPXML export.
func gcd(_ a: Int, _ b: Int) -> Int {
    let a = abs(a)
    let b = abs(b)
    if b == 0 { return a }
    return gcd(b, a % b)
}

/// Computes the Least Common Multiple of two integers.
func lcm(_ a: Int, _ b: Int) -> Int {
    guard a != 0 && b != 0 else { return 0 }
    return abs(a * b) / gcd(a, b)
}

/// Reduces a rational fraction (numerator/denominator) to its simplest form.
func reduceFraction(numerator: Int, denominator: Int) -> (numerator: Int, denominator: Int) {
    guard denominator != 0 else { return (0, 1) }
    let g = gcd(abs(numerator), abs(denominator))
    return (numerator / g, denominator / g)
}

/// Converts milliseconds + fps to a reduced rational string for FCPXML.
/// Example: 1001ms at 29.97fps → "30030/30000s"
func msToRationalString(_ ms: Double, fps: Double) -> String {
    let denominator = Int(round(fps * 1000))
    let numerator = Int(round(ms / 1000.0 * Double(denominator)))
    let reduced = reduceFraction(numerator: numerator, denominator: denominator)
    return "\(reduced.numerator)/\(reduced.denominator)s"
}

/// Returns the frame duration as a rational string for FCPXML format attributes.
/// Example: 29.97fps → "1001/30000s", 24fps → "100/2400s"
func frameDurationRational(fps: Double) -> String {
    let denominator = Int(round(fps * 1000))
    let numerator = Int(round(1000.0))
    let reduced = reduceFraction(numerator: numerator, denominator: denominator)
    return "\(reduced.numerator)/\(reduced.denominator)s"
}

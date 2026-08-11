import Foundation
import UnitsKit

/// What a number *is*, so the app can convert and label it in one place.
///
/// ## The unit switch has exactly one implementation
///
/// Every value the app holds is SI, because every Kit is SI. A quantity knows which ``Conversion``
/// and which symbol belong to it in each system, and how many decimals it deserves — so switching
/// IP ⇄ SI is a change of presentation and nothing else. The stored number never moves and never
/// re-rounds, which is what makes flipping the toggle free and reversible.
///
/// This is also the one place the two datum-carrying quantities are kept apart from their
/// differences: ``temperature`` converts a reading, ``temperatureDifference`` converts a ΔT, and
/// they are separate cases so a call site cannot pick the wrong one by accident.
public enum Quantity: String, CaseIterable, Sendable, Hashable {

    case temperature
    case temperatureDifference
    case relativeHumidity
    case humidityRatio
    case enthalpy
    case enthalpyDifference
    case specificVolume
    case density
    case elevation
    case barometricPressure
    case airFlow
    case waterFlow
    case airVelocity
    case waterVelocity
    case ductSize
    case ductFrictionRate
    case waterHeadGradient
    case heatLoad
    case fanPressure
    case fanSpeed
    case fanPower
    case dimensionless

    /// How to get from the display unit to SI.
    public func conversion(_ system: UnitSystem) -> Conversion {
        switch (self, system) {
        case (.temperature, .ip):            return Units.fahrenheit
        case (.temperature, .si):            return Units.celsius
        case (.temperatureDifference, .ip):  return Units.fahrenheit.asDifference
        case (.temperatureDifference, .si):  return Units.celsius

        case (.relativeHumidity, _):         return Conversion(factor: 0.01)   // % ⇄ fraction

        case (.humidityRatio, .ip):          return Units.grainsPerPoundDryAir
        case (.humidityRatio, .si):          return Units.gramsPerKilogramDryAir

        case (.enthalpy, .ip):               return Units.btuPerPoundDryAir
        case (.enthalpy, .si):               return Conversion(factor: 1)
        case (.enthalpyDifference, .ip):     return Units.btuPerPoundDryAir.asDifference
        case (.enthalpyDifference, .si):     return Conversion(factor: 1)

        case (.specificVolume, .ip):         return Units.cubicFeetPerPound
        case (.specificVolume, .si):         return Conversion(factor: 1)
        case (.density, .ip):                return Units.poundsPerCubicFoot
        case (.density, .si):                return Conversion(factor: 1)

        case (.elevation, .ip):              return Units.feet
        case (.elevation, .si):              return Conversion(factor: 1)
        case (.barometricPressure, .ip):     return Units.inchOfMercury
        case (.barometricPressure, .si):     return Conversion(factor: 1000)   // kPa

        case (.airFlow, .ip):                return Units.cubicFeetPerMinute
        case (.airFlow, .si):                return Units.litresPerSecond
        case (.waterFlow, .ip):              return Units.gallonsPerMinute
        case (.waterFlow, .si):              return Units.litresPerSecond

        case (.airVelocity, .ip):            return Units.feetPerMinute
        case (.airVelocity, .si):            return Conversion(factor: 1)
        case (.waterVelocity, .ip):          return Units.feetPerSecond
        case (.waterVelocity, .si):          return Conversion(factor: 1)

        case (.ductSize, .ip):               return Units.inches
        case (.ductSize, .si):               return Units.millimetres

        case (.ductFrictionRate, .ip):       return Units.inchesOfWaterPer100Feet
        case (.ductFrictionRate, .si):       return Conversion(factor: 1)      // Pa/m
        case (.waterHeadGradient, .ip):      return Units.footOfWaterPer100Feet
        case (.waterHeadGradient, .si):      return Units.kilopascalsPerMetre

        case (.heatLoad, .ip):               return Units.btuPerHour
        case (.heatLoad, .si):               return Conversion(factor: 1)      // W

        case (.fanPressure, .ip):            return Units.inchOfWaterGauge
        case (.fanPressure, .si):            return Conversion(factor: 1)      // Pa
        case (.fanSpeed, _):                 return Conversion(factor: 1)      // RPM
        case (.fanPower, .ip):               return Conversion(factor: 745.6998715822702) // hp → W
        case (.fanPower, .si):               return Conversion(factor: 1000)   // kW

        case (.dimensionless, _):            return Conversion(factor: 1)
        }
    }

    /// The symbol shown beside the number.
    public func symbol(_ system: UnitSystem) -> String {
        switch (self, system) {
        case (.temperature, .ip), (.temperatureDifference, .ip): return "°F"
        case (.temperature, .si):                                return "°C"
        case (.temperatureDifference, .si):                      return "K"
        case (.relativeHumidity, _):                             return "%"
        case (.humidityRatio, .ip):                              return "gr/lb"
        case (.humidityRatio, .si):                              return "g/kg"
        case (.enthalpy, .ip), (.enthalpyDifference, .ip):       return "Btu/lb"
        case (.enthalpy, .si), (.enthalpyDifference, .si):       return "kJ/kg"
        case (.specificVolume, .ip):                             return "ft³/lb"
        case (.specificVolume, .si):                             return "m³/kg"
        case (.density, .ip):                                    return "lb/ft³"
        case (.density, .si):                                    return "kg/m³"
        case (.elevation, .ip):                                  return "ft"
        case (.elevation, .si):                                  return "m"
        case (.barometricPressure, .ip):                         return "inHg"
        case (.barometricPressure, .si):                         return "kPa"
        case (.airFlow, .ip):                                    return "CFM"
        case (.airFlow, .si):                                    return "L/s"
        case (.waterFlow, .ip):                                  return "GPM"
        case (.waterFlow, .si):                                  return "L/s"
        case (.airVelocity, .ip):                                return "fpm"
        case (.airVelocity, .si):                                return "m/s"
        case (.waterVelocity, .ip):                              return "ft/s"
        case (.waterVelocity, .si):                              return "m/s"
        case (.ductSize, .ip):                                   return "in"
        case (.ductSize, .si):                                   return "mm"
        case (.ductFrictionRate, .ip):                           return "in wg/100 ft"
        case (.ductFrictionRate, .si):                           return "Pa/m"
        case (.waterHeadGradient, .ip):                          return "ft/100 ft"
        case (.waterHeadGradient, .si):                          return "kPa/m"
        case (.heatLoad, .ip):                                   return "Btu/h"
        case (.heatLoad, .si):                                   return "W"
        case (.fanPressure, .ip):                                return "in wg"
        case (.fanPressure, .si):                                return "Pa"
        case (.fanSpeed, _):                                     return "RPM"
        case (.fanPower, .ip):                                   return "hp"
        case (.fanPower, .si):                                   return "kW"
        case (.dimensionless, _):                                return ""
        }
    }

    /// Decimal places to show. Chosen so the last digit means something at the precision the
    /// physics supports, and so the same quantity does not gain or lose significance when the
    /// units change.
    public func decimals(_ system: UnitSystem) -> Int {
        switch (self, system) {
        case (.temperature, _), (.temperatureDifference, _):     return 1
        case (.relativeHumidity, _):                             return 1
        case (.humidityRatio, .ip):                              return 1
        case (.humidityRatio, .si):                              return 2
        case (.enthalpy, _), (.enthalpyDifference, _):           return 1
        case (.specificVolume, .ip):                             return 2
        case (.specificVolume, .si):                             return 3
        case (.density, .ip):                                    return 4
        case (.density, .si):                                    return 3
        case (.elevation, _):                                    return 0
        case (.barometricPressure, _):                           return 2
        case (.airFlow, .ip):                                    return 0
        case (.airFlow, .si):                                    return 1
        case (.waterFlow, _):                                    return 1
        case (.airVelocity, .ip):                                return 0
        case (.airVelocity, .si):                                return 2
        case (.waterVelocity, _):                                return 2
        case (.ductSize, .ip):                                   return 2
        case (.ductSize, .si):                                   return 0
        case (.ductFrictionRate, .ip):                           return 3
        case (.ductFrictionRate, .si):                           return 2
        case (.waterHeadGradient, .ip):                          return 2
        case (.waterHeadGradient, .si):                          return 3
        case (.heatLoad, _):                                     return 0
        case (.fanPressure, .ip):                                return 2
        case (.fanPressure, .si):                                return 0
        case (.fanSpeed, _):                                     return 0
        case (.fanPower, _):                                     return 2
        case (.dimensionless, _):                                return 2
        }
    }

    /// The value in display units.
    public func display(si value: Double, in system: UnitSystem) -> Double {
        conversion(system).fromSI(value)
    }

    /// The SI value behind something the user typed.
    public func si(display value: Double, in system: UnitSystem) -> Double {
        conversion(system).toSI(value)
    }
}

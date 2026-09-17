import AppKit

/// Canonical design names: <family>-<100...1000>-<light|dark>.
/// Swift spelling: gray1000Light = gray-1000-light.
/// Backgrounds retain Geist's separate 1/2 scale: background1Light.
enum GeistColorTokens {
    static let background1Light: GeistColorTokenValue = .gray(1.00)
    static let background2Light: GeistColorTokenValue = .gray(0.98)
    static let background1Dark: GeistColorTokenValue = .gray(0.04)
    static let background2Dark: GeistColorTokenValue = .gray(0.00)

    static let gray100Light: GeistColorTokenValue = .gray(0.95)
    static let gray200Light: GeistColorTokenValue = .gray(0.92)
    static let gray300Light: GeistColorTokenValue = .gray(0.90)
    static let gray400Light: GeistColorTokenValue = .gray(0.92)
    static let gray500Light: GeistColorTokenValue = .gray(0.79)
    static let gray600Light: GeistColorTokenValue = .gray(0.66)
    static let gray700Light: GeistColorTokenValue = .gray(0.56)
    static let gray800Light: GeistColorTokenValue = .gray(0.49)
    static let gray900Light: GeistColorTokenValue = .gray(0.30)
    static let gray1000Light: GeistColorTokenValue = .gray(0.09)
    static let gray100Dark: GeistColorTokenValue = .gray(0.10)
    static let gray200Dark: GeistColorTokenValue = .gray(0.12)
    static let gray300Dark: GeistColorTokenValue = .gray(0.16)
    static let gray400Dark: GeistColorTokenValue = .gray(0.18)
    static let gray500Dark: GeistColorTokenValue = .gray(0.27)
    static let gray600Dark: GeistColorTokenValue = .gray(0.53)
    static let gray700Dark: GeistColorTokenValue = .gray(0.56)
    static let gray800Dark: GeistColorTokenValue = .gray(0.49)
    static let gray900Dark: GeistColorTokenValue = .gray(0.63)
    static let gray1000Dark: GeistColorTokenValue = .gray(0.93)

    static let blue100Light: GeistColorTokenValue = .oklch(0.9732, 0.0141, 251.56)
    static let blue200Light: GeistColorTokenValue = .oklch(0.9629, 0.0195, 250.59)
    static let blue300Light: GeistColorTokenValue = .oklch(0.9458, 0.0293, 249.849)
    static let blue400Light: GeistColorTokenValue = .oklch(0.9158, 0.0473, 245.116)
    static let blue500Light: GeistColorTokenValue = .oklch(0.8275, 0.0979, 248.48)
    static let blue600Light: GeistColorTokenValue = .oklch(0.7308, 0.1583, 248.133)
    static let blue700Light: GeistColorTokenValue = .oklch(0.5761, 0.2508, 258.23)
    static let blue800Light: GeistColorTokenValue = .oklch(0.5151, 0.2399, 257.85)
    static let blue900Light: GeistColorTokenValue = .oklch(0.5318, 0.2399, 256.99)
    static let blue1000Light: GeistColorTokenValue = .oklch(0.2667, 0.1099, 254.34)
    static let blue100Dark: GeistColorTokenValue = .oklch(0.2217, 0.0690, 259.89)
    static let blue200Dark: GeistColorTokenValue = .oklch(0.2545, 0.0811, 255.80)
    static let blue300Dark: GeistColorTokenValue = .oklch(0.3086, 0.1022, 255.21)
    static let blue400Dark: GeistColorTokenValue = .oklch(0.3410, 0.1210, 254.74)
    static let blue500Dark: GeistColorTokenValue = .oklch(0.3850, 0.1403, 254.40)
    static let blue600Dark: GeistColorTokenValue = .oklch(0.6494, 0.1982, 251.813)
    static let blue700Dark: GeistColorTokenValue = .oklch(0.5761, 0.2321, 258.23)
    static let blue800Dark: GeistColorTokenValue = .oklch(0.5151, 0.2307, 257.85)
    static let blue900Dark: GeistColorTokenValue = .oklch(0.7170, 0.1648, 250.794)
    static let blue1000Dark: GeistColorTokenValue = .oklch(0.9675, 0.0179, 242.423)

    static let red100Light: GeistColorTokenValue = .oklch(0.9650, 0.0223, 13.09)
    static let red200Light: GeistColorTokenValue = .oklch(0.9541, 0.0299, 14.2526)
    static let red300Light: GeistColorTokenValue = .oklch(0.9433, 0.0369, 15.0115)
    static let red400Light: GeistColorTokenValue = .oklch(0.9151, 0.0471, 19.80)
    static let red500Light: GeistColorTokenValue = .oklch(0.8447, 0.1018, 17.71)
    static let red600Light: GeistColorTokenValue = .oklch(0.7112, 0.1881, 21.22)
    static let red700Light: GeistColorTokenValue = .oklch(0.6256, 0.2524, 23.03)
    static let red800Light: GeistColorTokenValue = .oklch(0.5819, 0.2482, 25.15)
    static let red900Light: GeistColorTokenValue = .oklch(0.5499, 0.2320, 25.29)
    static let red1000Light: GeistColorTokenValue = .oklch(0.2480, 0.1041, 18.86)
    static let red100Dark: GeistColorTokenValue = .oklch(0.2210, 0.0657, 15.11)
    static let red200Dark: GeistColorTokenValue = .oklch(0.2593, 0.0834, 19.02)
    static let red300Dark: GeistColorTokenValue = .oklch(0.3147, 0.1105, 20.96)
    static let red400Dark: GeistColorTokenValue = .oklch(0.3527, 0.1273, 21.23)
    static let red500Dark: GeistColorTokenValue = .oklch(0.4068, 0.1479, 23.16)
    static let red600Dark: GeistColorTokenValue = .oklch(0.6256, 0.2277, 23.03)
    static let red700Dark: GeistColorTokenValue = .oklch(0.6256, 0.2234, 23.03)
    static let red800Dark: GeistColorTokenValue = .oklch(0.5801, 0.2270, 25.12)
    static let red900Dark: GeistColorTokenValue = .oklch(0.6996, 0.2136, 22.03)
    static let red1000Dark: GeistColorTokenValue = .oklch(0.9560, 0.0293, 6.61)

    static let amber100Light: GeistColorTokenValue = .oklch(0.9748, 0.0331, 85.79)
    static let amber200Light: GeistColorTokenValue = .oklch(0.9681, 0.0495, 90.2423)
    static let amber300Light: GeistColorTokenValue = .oklch(0.9593, 0.0636, 90.52)
    static let amber400Light: GeistColorTokenValue = .oklch(0.9102, 0.1322, 88.25)
    static let amber500Light: GeistColorTokenValue = .oklch(0.8655, 0.1583, 79.63)
    static let amber600Light: GeistColorTokenValue = .oklch(0.8025, 0.1953, 73.59)
    static let amber700Light: GeistColorTokenValue = .oklch(0.8187, 0.1969, 76.46)
    static let amber800Light: GeistColorTokenValue = .oklch(0.7721, 0.1991, 64.28)
    static let amber900Light: GeistColorTokenValue = .oklch(0.5279, 0.1496, 54.65)
    static let amber1000Light: GeistColorTokenValue = .oklch(0.3083, 0.0990, 45.48)
    static let amber100Dark: GeistColorTokenValue = .oklch(0.2246, 0.0538, 76.04)
    static let amber200Dark: GeistColorTokenValue = .oklch(0.2495, 0.0642, 64.78)
    static let amber300Dark: GeistColorTokenValue = .oklch(0.3234, 0.0837, 63.83)
    static let amber400Dark: GeistColorTokenValue = .oklch(0.3553, 0.0903, 66.2971)
    static let amber500Dark: GeistColorTokenValue = .oklch(0.4155, 0.1044, 67.98)
    static let amber600Dark: GeistColorTokenValue = .oklch(0.7504, 0.1737, 74.49)
    static let amber700Dark: GeistColorTokenValue = .oklch(0.8187, 0.1969, 76.46)
    static let amber800Dark: GeistColorTokenValue = .oklch(0.7721, 0.1991, 64.28)
    static let amber900Dark: GeistColorTokenValue = .oklch(0.7721, 0.1991, 64.28)
    static let amber1000Dark: GeistColorTokenValue = .oklch(0.9670, 0.0418, 84.59)

    static let green100Light: GeistColorTokenValue = .oklch(0.9759, 0.0289, 145.42)
    static let green200Light: GeistColorTokenValue = .oklch(0.9692, 0.0370, 147.15)
    static let green300Light: GeistColorTokenValue = .oklch(0.9460, 0.0674, 144.23)
    static let green400Light: GeistColorTokenValue = .oklch(0.9149, 0.0976, 146.24)
    static let green500Light: GeistColorTokenValue = .oklch(0.8545, 0.1627, 146.30)
    static let green600Light: GeistColorTokenValue = .oklch(0.8025, 0.2140, 145.18)
    static let green700Light: GeistColorTokenValue = .oklch(0.6458, 0.1746, 147.27)
    static let green800Light: GeistColorTokenValue = .oklch(0.5781, 0.1507, 147.50)
    static let green900Light: GeistColorTokenValue = .oklch(0.5175, 0.1453, 147.65)
    static let green1000Light: GeistColorTokenValue = .oklch(0.2915, 0.1197, 147.38)
    static let green100Dark: GeistColorTokenValue = .oklch(0.2309, 0.0716, 149.68)
    static let green200Dark: GeistColorTokenValue = .oklch(0.2712, 0.0895, 150.09)
    static let green300Dark: GeistColorTokenValue = .oklch(0.2984, 0.0960, 149.25)
    static let green400Dark: GeistColorTokenValue = .oklch(0.3439, 0.1039, 147.78)
    static let green500Dark: GeistColorTokenValue = .oklch(0.4419, 0.1484, 147.20)
    static let green600Dark: GeistColorTokenValue = .oklch(0.5811, 0.1815, 146.55)
    static let green700Dark: GeistColorTokenValue = .oklch(0.6458, 0.1990, 147.27)
    static let green800Dark: GeistColorTokenValue = .oklch(0.5781, 0.1776, 147.50)
    static let green900Dark: GeistColorTokenValue = .oklch(0.7310, 0.2158, 148.29)
    static let green1000Dark: GeistColorTokenValue = .oklch(0.9676, 0.0560, 154.18)

    static let teal100Light: GeistColorTokenValue = .oklch(0.9772, 0.0359, 186.70)
    static let teal200Light: GeistColorTokenValue = .oklch(0.9706, 0.0347, 180.66)
    static let teal300Light: GeistColorTokenValue = .oklch(0.9492, 0.0478, 182.07)
    static let teal400Light: GeistColorTokenValue = .oklch(0.9276, 0.0718, 183.78)
    static let teal500Light: GeistColorTokenValue = .oklch(0.8688, 0.1344, 182.42)
    static let teal600Light: GeistColorTokenValue = .oklch(0.8150, 0.1610, 178.96)
    static let teal700Light: GeistColorTokenValue = .oklch(0.6492, 0.1572, 181.95)
    static let teal800Light: GeistColorTokenValue = .oklch(0.5753, 0.1392, 181.66)
    static let teal900Light: GeistColorTokenValue = .oklch(0.5208, 0.1251, 182.93)
    static let teal1000Light: GeistColorTokenValue = .oklch(0.3211, 0.0788, 179.82)
    static let teal100Dark: GeistColorTokenValue = .oklch(0.2210, 0.0544, 178.74)
    static let teal200Dark: GeistColorTokenValue = .oklch(0.2506, 0.0620, 178.76)
    static let teal300Dark: GeistColorTokenValue = .oklch(0.3150, 0.0767, 180.99)
    static let teal400Dark: GeistColorTokenValue = .oklch(0.3243, 0.0763, 180.13)
    static let teal500Dark: GeistColorTokenValue = .oklch(0.4335, 0.1055, 180.97)
    static let teal600Dark: GeistColorTokenValue = .oklch(0.6071, 0.1485, 180.24)
    static let teal700Dark: GeistColorTokenValue = .oklch(0.6492, 0.1403, 181.95)
    static let teal800Dark: GeistColorTokenValue = .oklch(0.5753, 0.1392, 181.66)
    static let teal900Dark: GeistColorTokenValue = .oklch(0.7456, 0.1765, 182.80)
    static let teal1000Dark: GeistColorTokenValue = .oklch(0.9646, 0.0560, 180.29)

    static let purple100Light: GeistColorTokenValue = .oklch(0.9665, 0.0244, 312.189)
    static let purple200Light: GeistColorTokenValue = .oklch(0.9673, 0.0228, 309.80)
    static let purple300Light: GeistColorTokenValue = .oklch(0.9485, 0.0364, 310.15)
    static let purple400Light: GeistColorTokenValue = .oklch(0.9177, 0.0614, 312.82)
    static let purple500Light: GeistColorTokenValue = .oklch(0.8126, 0.1409, 310.80)
    static let purple600Light: GeistColorTokenValue = .oklch(0.7207, 0.2083, 308.19)
    static let purple700Light: GeistColorTokenValue = .oklch(0.5550, 0.3008, 306.12)
    static let purple800Light: GeistColorTokenValue = .oklch(0.4858, 0.2638, 305.73)
    static let purple900Light: GeistColorTokenValue = .oklch(0.4718, 0.2579, 304.00)
    static let purple1000Light: GeistColorTokenValue = .oklch(0.2396, 0.1300, 305.66)
    static let purple100Dark: GeistColorTokenValue = .oklch(0.2234, 0.0779, 316.87)
    static let purple200Dark: GeistColorTokenValue = .oklch(0.2591, 0.0921, 314.41)
    static let purple300Dark: GeistColorTokenValue = .oklch(0.3198, 0.1219, 312.41)
    static let purple400Dark: GeistColorTokenValue = .oklch(0.3593, 0.1504, 309.78)
    static let purple500Dark: GeistColorTokenValue = .oklch(0.4099, 0.1721, 307.92)
    static let purple600Dark: GeistColorTokenValue = .oklch(0.5550, 0.2191, 306.12)
    static let purple700Dark: GeistColorTokenValue = .oklch(0.5550, 0.2186, 306.12)
    static let purple800Dark: GeistColorTokenValue = .oklch(0.4858, 0.2102, 305.73)
    static let purple900Dark: GeistColorTokenValue = .oklch(0.6987, 0.2037, 309.51)
    static let purple1000Dark: GeistColorTokenValue = .oklch(0.9610, 0.0304, 316.46)

    static let pink100Light: GeistColorTokenValue = .oklch(0.9569, 0.0359, 344.622)
    static let pink200Light: GeistColorTokenValue = .oklch(0.9571, 0.0321, 353.14)
    static let pink300Light: GeistColorTokenValue = .oklch(0.9383, 0.0451, 356.29)
    static let pink400Light: GeistColorTokenValue = .oklch(0.9112, 0.0573, 358.82)
    static let pink500Light: GeistColorTokenValue = .oklch(0.8428, 0.0915, 356.99)
    static let pink600Light: GeistColorTokenValue = .oklch(0.7433, 0.1547, 0.24)
    static let pink700Light: GeistColorTokenValue = .oklch(0.6352, 0.2380, 1.01)
    static let pink800Light: GeistColorTokenValue = .oklch(0.5951, 0.2339, 4.21)
    static let pink900Light: GeistColorTokenValue = .oklch(0.5350, 0.2058, 2.84)
    static let pink1000Light: GeistColorTokenValue = .oklch(0.2600, 0.0977, 359.00)
    static let pink100Dark: GeistColorTokenValue = .oklch(0.2267, 0.0628, 354.73)
    static let pink200Dark: GeistColorTokenValue = .oklch(0.2620, 0.0859, 356.68)
    static let pink300Dark: GeistColorTokenValue = .oklch(0.3115, 0.1067, 355.93)
    static let pink400Dark: GeistColorTokenValue = .oklch(0.3213, 0.1174, 356.71)
    static let pink500Dark: GeistColorTokenValue = .oklch(0.3701, 0.1453, 358.39)
    static let pink600Dark: GeistColorTokenValue = .oklch(0.5033, 0.2089, 4.33)
    static let pink700Dark: GeistColorTokenValue = .oklch(0.6352, 0.2346, 1.01)
    static let pink800Dark: GeistColorTokenValue = .oklch(0.5951, 0.2429, 4.21)
    static let pink900Dark: GeistColorTokenValue = .oklch(0.6936, 0.2223, 3.91)
    static let pink1000Dark: GeistColorTokenValue = .oklch(0.9574, 0.0326, 350.08)

    static func background(_ role: GeistBackgroundRole, theme: AppearanceTheme) -> GeistColorTokenValue {
        switch (role, theme) {
            case (.primary, .light): background1Light
            case (.secondary, .light): background2Light
            case (.primary, .dark): background1Dark
            case (.secondary, .dark): background2Dark
        }
    }

    static func color(
        _ family: WorkspaceSidebarProjectThemeFamily,
        _ step: GeistColorStep,
        theme: AppearanceTheme
    ) -> GeistColorTokenValue {
        scale(family, theme: theme)[step.index]
    }

    private static func scale(
        _ family: WorkspaceSidebarProjectThemeFamily,
        theme: AppearanceTheme
    ) -> [GeistColorTokenValue] {
        switch (family, theme) {
            case (.gray, .light): [gray100Light, gray200Light, gray300Light, gray400Light, gray500Light, gray600Light, gray700Light, gray800Light, gray900Light, gray1000Light]
            case (.gray, .dark): [gray100Dark, gray200Dark, gray300Dark, gray400Dark, gray500Dark, gray600Dark, gray700Dark, gray800Dark, gray900Dark, gray1000Dark]
            case (.blue, .light): [blue100Light, blue200Light, blue300Light, blue400Light, blue500Light, blue600Light, blue700Light, blue800Light, blue900Light, blue1000Light]
            case (.blue, .dark): [blue100Dark, blue200Dark, blue300Dark, blue400Dark, blue500Dark, blue600Dark, blue700Dark, blue800Dark, blue900Dark, blue1000Dark]
            case (.red, .light): [red100Light, red200Light, red300Light, red400Light, red500Light, red600Light, red700Light, red800Light, red900Light, red1000Light]
            case (.red, .dark): [red100Dark, red200Dark, red300Dark, red400Dark, red500Dark, red600Dark, red700Dark, red800Dark, red900Dark, red1000Dark]
            case (.amber, .light): [amber100Light, amber200Light, amber300Light, amber400Light, amber500Light, amber600Light, amber700Light, amber800Light, amber900Light, amber1000Light]
            case (.amber, .dark): [amber100Dark, amber200Dark, amber300Dark, amber400Dark, amber500Dark, amber600Dark, amber700Dark, amber800Dark, amber900Dark, amber1000Dark]
            case (.green, .light): [green100Light, green200Light, green300Light, green400Light, green500Light, green600Light, green700Light, green800Light, green900Light, green1000Light]
            case (.green, .dark): [green100Dark, green200Dark, green300Dark, green400Dark, green500Dark, green600Dark, green700Dark, green800Dark, green900Dark, green1000Dark]
            case (.teal, .light): [teal100Light, teal200Light, teal300Light, teal400Light, teal500Light, teal600Light, teal700Light, teal800Light, teal900Light, teal1000Light]
            case (.teal, .dark): [teal100Dark, teal200Dark, teal300Dark, teal400Dark, teal500Dark, teal600Dark, teal700Dark, teal800Dark, teal900Dark, teal1000Dark]
            case (.purple, .light): [purple100Light, purple200Light, purple300Light, purple400Light, purple500Light, purple600Light, purple700Light, purple800Light, purple900Light, purple1000Light]
            case (.purple, .dark): [purple100Dark, purple200Dark, purple300Dark, purple400Dark, purple500Dark, purple600Dark, purple700Dark, purple800Dark, purple900Dark, purple1000Dark]
            case (.pink, .light): [pink100Light, pink200Light, pink300Light, pink400Light, pink500Light, pink600Light, pink700Light, pink800Light, pink900Light, pink1000Light]
            case (.pink, .dark): [pink100Dark, pink200Dark, pink300Dark, pink400Dark, pink500Dark, pink600Dark, pink700Dark, pink800Dark, pink900Dark, pink1000Dark]
        }
    }
}

enum GeistColorTokenValue {
    case gray(CGFloat)
    case oklch(CGFloat, CGFloat, CGFloat)

    var nsColor: NSColor {
        switch self {
            case .gray(let white):
                NSColor(srgbRed: white, green: white, blue: white, alpha: 1)
            case .oklch(let lightness, let chroma, let hue):
                Self.oklchNSColor(lightness: lightness, chroma: chroma, hue: hue)
        }
    }

    private static func oklchNSColor(lightness: CGFloat, chroma: CGFloat, hue: CGFloat) -> NSColor {
        let hueRadians = hue * .pi / 180
        let a = chroma * cos(hueRadians)
        let b = chroma * sin(hueRadians)
        let lPrime = lightness + (0.3963377774 * a) + (0.2158037573 * b)
        let mPrime = lightness - (0.1055613458 * a) - (0.0638541728 * b)
        let sPrime = lightness - (0.0894841775 * a) - (1.2914855480 * b)
        let l = lPrime * lPrime * lPrime
        let m = mPrime * mPrime * mPrime
        let s = sPrime * sPrime * sPrime
        let x = (1.2268798734 * l) - (0.5578149966 * m) + (0.2813910502 * s)
        let y = (-0.0405757452 * l) + (1.1122868294 * m) - (0.0717110667 * s)
        let z = (-0.0763729497 * l) - (0.4214933239 * m) + (1.5869240244 * s)
        let red = (2.4934969119 * x) - (0.9313836179 * y) - (0.4027107845 * z)
        let green = (-0.8294889696 * x) + (1.7626640603 * y) + (0.0236246858 * z)
        let blue = (0.0358458302 * x) - (0.0761723893 * y) + (0.9568845240 * z)
        return NSColor(
            displayP3Red: gammaEncode(red),
            green: gammaEncode(green),
            blue: gammaEncode(blue),
            alpha: 1
        )
    }

    private static func gammaEncode(_ component: CGFloat) -> CGFloat {
        let encoded = component <= 0.0031308
            ? 12.92 * component
            : (1.055 * pow(component, 1 / 2.4)) - 0.055
        return min(max(encoded, 0), 1)
    }
}

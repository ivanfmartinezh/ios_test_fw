// Copyright (c) 2021 Proton AG
//
// This file is part of Proton Mail.
//
// Proton Mail is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Proton Mail is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Proton Mail. If not, see https://www.gnu.org/licenses/.

import Foundation
import SwiftSoup

private enum CSSKeys: String {
    case style, color, transparent, background, border
    case bgColor = "bgcolor"
    case backgroundColor = "background-color"

    case target, id, `class`
}

enum DarkStyleSupportLevel {
    /// Need to generate the supplement css to support dark mode
    case protonSupport
    case notSupport
    /// The message support dark mode by itself
    /// Don't need to generate the supplement css for dark mode
    case nativeSupport
}

struct HSLA {
    /// hue, [0, 360]
    let h: Int
    // saturation, [0%, 100%]
    let s: Int
    // lightness, [0%, 100%]
    let l: Int
    // alpha, [0%, 100%] or [0.0, 1.0]
    let a: CGFloat

    var isDark: Bool {
        l < 50
    }

    var isLight: Bool {
        !isDark
    }

    var color: UIColor {
        UIColor(
            hue: CGFloat(h) / 360.0,
            saturation: CGFloat(s) / 100.0,
            lightness: CGFloat(l) / 100.0,
            alpha: a
        )
    }
}

struct CSSMagic {
    typealias CSSAttribute = (key: String, value: String)

    /// https://developer.mozilla.org/en-US/docs/Web/CSS/color_value
    private static let definedColors = [
        "aliceblue": HSLA(h: 208, s: 100, l: 97, a: 1),
        "antiquewhite": HSLA(h: 34, s: 78, l: 91, a: 1),
        "aqua": HSLA(h: 180, s: 100, l: 50, a: 1),
        "aquamarine": HSLA(h: 160, s: 100, l: 75, a: 1),
        "azure": HSLA(h: 180, s: 100, l: 97, a: 1),
        "beige": HSLA(h: 60, s: 56, l: 91, a: 1),
        "bisque": HSLA(h: 33, s: 100, l: 88, a: 1),
        "black": HSLA(h: 0, s: 0, l: 0, a: 1),
        "blanchedalmond": HSLA(h: 36, s: 100, l: 90, a: 1),
        "blue": HSLA(h: 240, s: 100, l: 50, a: 1),
        "blueviolet": HSLA(h: 271, s: 76, l: 53, a: 1),
        "brown": HSLA(h: 0, s: 59, l: 41, a: 1),
        "burlywood": HSLA(h: 34, s: 57, l: 70, a: 1),
        "cadetblue": HSLA(h: 182, s: 25, l: 50, a: 1),
        "chartreuse": HSLA(h: 90, s: 100, l: 50, a: 1),
        "chocolate": HSLA(h: 25, s: 75, l: 47, a: 1),
        "coral": HSLA(h: 16, s: 100, l: 66, a: 1),
        "cornflowerblue": HSLA(h: 219, s: 79, l: 66, a: 1),
        "cornsilk": HSLA(h: 48, s: 100, l: 93, a: 1),
        "crimson": HSLA(h: 348, s: 83, l: 47, a: 1),
        "cyan": HSLA(h: 180, s: 100, l: 50, a: 1),
        "darkblue": HSLA(h: 240, s: 100, l: 27, a: 1),
        "darkcyan": HSLA(h: 180, s: 100, l: 27, a: 1),
        "darkgoldenrod": HSLA(h: 43, s: 89, l: 38, a: 1),
        "darkgray": HSLA(h: 0, s: 0, l: 66, a: 1),
        "darkgreen": HSLA(h: 120, s: 100, l: 20, a: 1),
        "darkgrey": HSLA(h: 0, s: 0, l: 66, a: 1),
        "darkkhaki": HSLA(h: 56, s: 38, l: 58, a: 1),
        "darkmagenta": HSLA(h: 300, s: 100, l: 27, a: 1),
        "darkolivegreen": HSLA(h: 82, s: 39, l: 30, a: 1),
        "darkorange": HSLA(h: 33, s: 100, l: 50, a: 1),
        "darkorchid": HSLA(h: 280, s: 61, l: 50, a: 1),
        "darkred": HSLA(h: 0, s: 100, l: 27, a: 1),
        "darksalmon": HSLA(h: 15, s: 72, l: 70, a: 1),
        "darkseagreen": HSLA(h: 120, s: 25, l: 65, a: 1),
        "darkslateblue": HSLA(h: 248, s: 39, l: 39, a: 1),
        "darkslategray": HSLA(h: 180, s: 25, l: 25, a: 1),
        "darkslategrey": HSLA(h: 180, s: 25, l: 25, a: 1),
        "darkturquoise": HSLA(h: 181, s: 100, l: 41, a: 1),
        "darkviolet": HSLA(h: 282, s: 100, l: 41, a: 1),
        "deeppink": HSLA(h: 328, s: 100, l: 54, a: 1),
        "deepskyblue": HSLA(h: 195, s: 100, l: 50, a: 1),
        "dimgray": HSLA(h: 0, s: 0, l: 41, a: 1),
        "dimgrey": HSLA(h: 0, s: 0, l: 41, a: 1),
        "dodgerblue": HSLA(h: 210, s: 100, l: 56, a: 1),
        "firebrick": HSLA(h: 0, s: 68, l: 42, a: 1),
        "floralwhite": HSLA(h: 40, s: 100, l: 97, a: 1),
        "forestgreen": HSLA(h: 120, s: 61, l: 34, a: 1),
        "fuchsia": HSLA(h: 300, s: 100, l: 50, a: 1),
        "gainsboro": HSLA(h: 0, s: 0, l: 86, a: 1),
        "ghostwhite": HSLA(h: 240, s: 100, l: 99, a: 1),
        "gold": HSLA(h: 51, s: 100, l: 50, a: 1),
        "goldenrod": HSLA(h: 43, s: 74, l: 49, a: 1),
        "gray": HSLA(h: 0, s: 0, l: 50, a: 1),
        "green": HSLA(h: 120, s: 100, l: 25, a: 1),
        "greenyellow": HSLA(h: 84, s: 100, l: 59, a: 1),
        "grey": HSLA(h: 0, s: 0, l: 50, a: 1),
        "honeydew": HSLA(h: 120, s: 100, l: 97, a: 1),
        "hotpink": HSLA(h: 330, s: 100, l: 71, a: 1),
        "indianred": HSLA(h: 0, s: 53, l: 58, a: 1),
        "indigo": HSLA(h: 275, s: 100, l: 25, a: 1),
        "ivory": HSLA(h: 60, s: 100, l: 97, a: 1),
        "khaki": HSLA(h: 54, s: 77, l: 75, a: 1),
        "lavender": HSLA(h: 240, s: 67, l: 94, a: 1),
        "lavenderblush": HSLA(h: 340, s: 100, l: 97, a: 1),
        "lawngreen": HSLA(h: 90, s: 100, l: 49, a: 1),
        "lemonchiffon": HSLA(h: 54, s: 100, l: 90, a: 1),
        "lightblue": HSLA(h: 195, s: 53, l: 79, a: 1),
        "lightcoral": HSLA(h: 0, s: 79, l: 72, a: 1),
        "lightcyan": HSLA(h: 180, s: 100, l: 94, a: 1),
        "lightgoldenrodyellow": HSLA(h: 60, s: 80, l: 90, a: 1),
        "lightgray": HSLA(h: 0, s: 0, l: 83, a: 1),
        "lightgreen": HSLA(h: 120, s: 73, l: 75, a: 1),
        "lightgrey": HSLA(h: 0, s: 0, l: 83, a: 1),
        "lightpink": HSLA(h: 351, s: 100, l: 86, a: 1),
        "lightsalmon": HSLA(h: 17, s: 100, l: 74, a: 1),
        "lightseagreen": HSLA(h: 177, s: 70, l: 41, a: 1),
        "lightskyblue": HSLA(h: 203, s: 92, l: 75, a: 1),
        "lightslategray": HSLA(h: 210, s: 14, l: 53, a: 1),
        "lightslategrey": HSLA(h: 210, s: 14, l: 53, a: 1),
        "lightsteelblue": HSLA(h: 214, s: 41, l: 78, a: 1),
        "lightyellow": HSLA(h: 60, s: 100, l: 94, a: 1),
        "lime": HSLA(h: 120, s: 100, l: 50, a: 1),
        "limegreen": HSLA(h: 120, s: 61, l: 50, a: 1),
        "linen": HSLA(h: 30, s: 67, l: 94, a: 1),
        "magenta": HSLA(h: 300, s: 100, l: 50, a: 1),
        "maroon": HSLA(h: 0, s: 100, l: 25, a: 1),
        "mediumaquamarine": HSLA(h: 160, s: 51, l: 60, a: 1),
        "mediumblue": HSLA(h: 240, s: 100, l: 40, a: 1),
        "mediumorchid": HSLA(h: 288, s: 59, l: 58, a: 1),
        "mediumpurple": HSLA(h: 260, s: 60, l: 65, a: 1),
        "mediumseagreen": HSLA(h: 147, s: 50, l: 47, a: 1),
        "mediumslateblue": HSLA(h: 249, s: 80, l: 67, a: 1),
        "mediumspringgreen": HSLA(h: 157, s: 100, l: 49, a: 1),
        "mediumturquoise": HSLA(h: 178, s: 60, l: 55, a: 1),
        "mediumvioletred": HSLA(h: 322, s: 81, l: 43, a: 1),
        "midnightblue": HSLA(h: 240, s: 64, l: 27, a: 1),
        "mintcream": HSLA(h: 150, s: 100, l: 98, a: 1),
        "mistyrose": HSLA(h: 6, s: 100, l: 94, a: 1),
        "moccasin": HSLA(h: 38, s: 100, l: 85, a: 1),
        "navajowhite": HSLA(h: 36, s: 100, l: 84, a: 1),
        "navy": HSLA(h: 240, s: 100, l: 25, a: 1),
        "oldlace": HSLA(h: 39, s: 85, l: 95, a: 1),
        "olive": HSLA(h: 60, s: 100, l: 25, a: 1),
        "olivedrab": HSLA(h: 80, s: 60, l: 35, a: 1),
        "orange": HSLA(h: 39, s: 100, l: 50, a: 1),
        "orangered": HSLA(h: 16, s: 100, l: 50, a: 1),
        "orchid": HSLA(h: 302, s: 59, l: 65, a: 1),
        "palegoldenrod": HSLA(h: 55, s: 67, l: 80, a: 1),
        "palegreen": HSLA(h: 120, s: 93, l: 79, a: 1),
        "paleturquoise": HSLA(h: 180, s: 65, l: 81, a: 1),
        "palevioletred": HSLA(h: 340, s: 60, l: 65, a: 1),
        "papayawhip": HSLA(h: 37, s: 100, l: 92, a: 1),
        "peachpuff": HSLA(h: 28, s: 100, l: 86, a: 1),
        "peru": HSLA(h: 30, s: 59, l: 53, a: 1),
        "pink": HSLA(h: 350, s: 100, l: 88, a: 1),
        "plum": HSLA(h: 300, s: 47, l: 75, a: 1),
        "powderblue": HSLA(h: 187, s: 52, l: 80, a: 1),
        "purple": HSLA(h: 300, s: 100, l: 25, a: 1),
        "rebeccapurple": HSLA(h: 270, s: 50, l: 40, a: 1),
        "red": HSLA(h: 0, s: 100, l: 50, a: 1),
        "rosybrown": HSLA(h: 0, s: 25, l: 65, a: 1),
        "royalblue": HSLA(h: 225, s: 73, l: 57, a: 1),
        "saddlebrown": HSLA(h: 25, s: 76, l: 31, a: 1),
        "salmon": HSLA(h: 6, s: 93, l: 71, a: 1),
        "sandybrown": HSLA(h: 28, s: 87, l: 67, a: 1),
        "seagreen": HSLA(h: 146, s: 50, l: 36, a: 1),
        "seashell": HSLA(h: 25, s: 100, l: 97, a: 1),
        "sienna": HSLA(h: 19, s: 56, l: 40, a: 1),
        "silver": HSLA(h: 0, s: 0, l: 75, a: 1),
        "skyblue": HSLA(h: 197, s: 71, l: 73, a: 1),
        "slateblue": HSLA(h: 248, s: 53, l: 58, a: 1),
        "slategray": HSLA(h: 210, s: 13, l: 50, a: 1),
        "slategrey": HSLA(h: 210, s: 13, l: 50, a: 1),
        "snow": HSLA(h: 0, s: 100, l: 99, a: 1),
        "springgreen": HSLA(h: 150, s: 100, l: 50, a: 1),
        "steelblue": HSLA(h: 207, s: 44, l: 49, a: 1),
        "tan": HSLA(h: 34, s: 44, l: 69, a: 1),
        "teal": HSLA(h: 180, s: 100, l: 25, a: 1),
        "thistle": HSLA(h: 300, s: 24, l: 80, a: 1),
        "tomato": HSLA(h: 9, s: 100, l: 64, a: 1),
        "turquoise": HSLA(h: 174, s: 72, l: 56, a: 1),
        "violet": HSLA(h: 300, s: 76, l: 72, a: 1),
        "wheat": HSLA(h: 39, s: 77, l: 83, a: 1),
        "white": HSLA(h: 0, s: 0, l: 100, a: 1),
        "whitesmoke": HSLA(h: 0, s: 0, l: 96, a: 1),
        "yellow": HSLA(h: 60, s: 100, l: 50, a: 1),
        "yellowgreen": HSLA(h: 80, s: 61, l: 50, a: 1)
    ]

    private static let colorRelated: (Element) -> Bool = { node in
        let keywords = [
            CSSKeys.style.rawValue,
            CSSKeys.bgColor.rawValue,
            CSSKeys.color.rawValue,
            CSSKeys.border.rawValue
        ]
        for keyword in keywords {
            guard node.hasAttr(keyword) else { continue }
            return true
        }
        return false
    }

    static func darkStyleSupportLevel(document: Document?,
                                      darkModeCache: DarkModeCacheProtocol = userCachedStatus) -> DarkStyleSupportLevel {
        if darkModeCache.darkModeStatus == .forceOff {
            return .notSupport
        }

        guard let document = document else {
            return .notSupport
        }
        // If the meta tag color-scheme is present, we assume that the email supports dark mode
        if let meta = try? document.select(#"meta[name="color-scheme"]"#),
           let content = try? meta.attr("content"),
           content.contains(check: "dark") {
            return .nativeSupport
        }
        // If the meta tag supported-color-schemes is present, we assume that the email supports dark mode
        if let meta = try? document.select(#"meta[name="supported-color-schemes"]"#),
           let content = try? meta.attr("content"),
           content.contains(check: "dark") {
            return .nativeSupport
        }
        // If the media query prefers-color-scheme is present, we assume that the email supports dark mode
        if let style = try? document.select("style"),
           let content = try? style.html(),
           content.preg_match(#"color-scheme:\s?\S{0,}\s?dark"#) {
            return .nativeSupport
        }
        // The last condition is contrast between foreground and background
        // But the calculation is not easy to do here
        // Move the check to `hasGoodContrast(attributes:)` during generate dark mode css
        return .protonSupport
    }

    /// Generate css for dark mode
    /// - Parameter document: Message html parsed document
    /// - Returns: CSS needs to be overridden
    static func generateCSSForDarkMode(document: Document?) -> String {
        guard let document = document else {
            return ""
        }
        let styleCSS = CSSMagic.getStyleCSS(from: document)
        guard let styleDict = CSSMagic.getDarkModeCSSDictFrom(styleCSS: styleCSS) else {
            return ""
        }
        let newStyleCSS = CSSMagic.assemble(cssDict: styleDict)

        let colorNodes = CSSMagic.getColorNodes(from: document)
        guard let cssDict = CSSMagic.getDarkModeCSSDict(for: colorNodes) else {
            return ""
        }
        let inlineCSS = CSSMagic.assemble(cssDict: cssDict)

        let css = newStyleCSS + inlineCSS
        return "@media (prefers-color-scheme: dark) { \(css) }"
    }
}

// MARK: Private functions
extension CSSMagic {
    static func parse(htmlString: String) -> Document? {
        do {
            let fullHTMLDocument = try SwiftSoup.parse(htmlString)
            return fullHTMLDocument
        } catch {
            return nil
        }
    }

    static func getStyleCSS(from document: Document) -> [String] {
        do {
            let nodes = try document.select("style").array()
            return nodes.compactMap({ element -> String? in
                guard let innerHTML = try? element.html() else {
                    return nil
                }
                let style = innerHTML.preg_replace(#"\/\*[^{}]+\*\/"#, replaceto: "")
                return style
            })
        } catch {
            return []
        }
    }

    /// Get nodes which has color settings (background color or text color)
    /// - Parameter document: Message html document
    /// - Returns: Nodes array
    static func getColorNodes(from document: Document) -> [Element] {
        guard let body = document.body() else {
            return []
        }
        let nodes = body
            .flatChildNodes()
            .filter(CSSMagic.colorRelated)
        return nodes
    }

    /// Get dark mode style css from <style> contents
    /// - Parameter styleCSS: <style> contents
    /// - Returns: dark mode style css or `nil` if it doesn't have good contrast
    static func getDarkModeCSSDictFrom(styleCSS: [String]) -> [String: [String]]? {
        var result: [String: [String]] = [:]
        let flattenCSS = styleCSS.flatMap({ $0.split(separator: "}") })
        for css in flattenCSS {
            let data = css.split(separator: "{")
                .map({ String($0) })
            guard data.count == 2,
                  let selectorKey = data.first,
                  let selectorValue = data.last else { continue }
            let attributes = CSSMagic.splitInline(attributes: selectorValue)
            guard hasGoodContrast(attributes: attributes) else {
                continue
            }
            let newAttributes = CSSMagic.switchToDarkModeStyle(attributes: attributes)
            result[selectorKey] = newAttributes
        }
        return result
    }

    /// Get dark mode style css for each html nodes
    /// - Parameter colorNodes: nodes that contains color related attributes
    /// - Returns: dark mode css style or `nil` if one of nodes doesn't have good contrast
    static func getDarkModeCSSDict(for colorNodes: [Element]) -> [String: [String]]? {
        var darkModeCSS: [String: [String]] = [:]
        for node in colorNodes {
            guard let styleCSS = CSSMagic.getDarkModeCSS(from: node),
                  !styleCSS.isEmpty else {
                continue
            }
            let anchor = CSSMagic.getCSSAnchor(of: node)
            guard anchor.isEmpty == false else { continue }
            darkModeCSS[anchor] = styleCSS
        }
        return darkModeCSS
    }
    
    /// Get dark mode css for the given html node
    /// - Parameter node: html node
    /// - Returns: dark mode css style or `nil` if it doesn't have good contrast
    static func getDarkModeCSS(from node: Element) -> [String]? {
        do {
            let bgStyle = try node.attr(CSSKeys.bgColor.rawValue)
            let colorStyle = try node.attr(CSSKeys.color.rawValue)
            let style = try node.attr(CSSKeys.style.rawValue)
            var attributes = CSSMagic.splitInline(attributes: style)
            if bgStyle.isEmpty == false {
                attributes.append((CSSKeys.bgColor.rawValue, bgStyle))
            }
            if colorStyle.isEmpty == false {
                attributes.append((CSSKeys.color.rawValue, colorStyle))
            }
            guard hasGoodContrast(attributes: attributes) else { return [] }
            return CSSMagic.switchToDarkModeStyle(attributes: attributes)
        } catch {
            return []
        }
    }

    /// Check if the background and foreground has good contrast
    /// Color contrast ratio greater than 1 is good contrast
    /// - Parameter attributes: attributes array
    /// - Returns: bool result
    static func hasGoodContrast(attributes: [CSSMagic.CSSAttribute]) -> Bool {
        let foregroundKey = CSSKeys.color.rawValue
        let backgroundKeys = [CSSKeys.backgroundColor.rawValue,
                              CSSKeys.bgColor.rawValue,
                              CSSKeys.background.rawValue]
        let foregroundStyle = attributes.first(where: {$0.key == foregroundKey})?.value ?? "#000"
        let backgroundStyle = attributes.first(where: {backgroundKeys.contains($0.key)})?.value ?? "#fff"

        let foregroundColor = parseAttribute(attribute: foregroundStyle)?.colorAttribute ?? "#000"
        let backgroundColor = parseAttribute(attribute: backgroundStyle)?.colorAttribute ?? "#fff"
        let color = getHSLA(attribute: foregroundColor) ?? HSLA(h: 0, s: 0, l: 100, a: 1)
        let background = getHSLA(attribute: backgroundColor) ?? HSLA(h: 0, s: 0, l: 0, a: 1)

        // https://www.w3.org/TR/WCAG20/#relativeluminancedef
        guard let colorRL = getRelativeLuminance(from: color),
              let backgroundRL = getRelativeLuminance(from: background) else {
            let result = (color.isDark && (background.isLight || background.a == 0)) ||
            (color.isLight && background.isDark)
            return result
        }
        let lighter = max(colorRL, backgroundRL)
        let darker = min(colorRL, backgroundRL)
        let colorContrastRatio = (lighter + 0.05) / (darker + 0.05)
        return colorContrastRatio >= 2
    }

    static func switchToDarkModeStyle(attributes: [CSSMagic.CSSAttribute]) -> [String] {
        var cssArray: [String] = []
        let keywords = [CSSKeys.color.rawValue,
                        CSSKeys.backgroundColor.rawValue,
                        CSSKeys.bgColor.rawValue,
                        CSSKeys.background.rawValue,
                        CSSKeys.border.rawValue]
        for attribute in attributes {
            guard keywords.contains(attribute.key) else { continue }
            let color = attribute.value
            guard color != CSSKeys.transparent.rawValue else { continue }
            let isForeground = attribute.key == CSSKeys.color.rawValue
            guard let hsla = CSSMagic.getDarkModeColor(from: color, isForeground: isForeground) else {
                continue
            }
            var key = attribute.key
            if key == CSSKeys.bgColor.rawValue {
                // bgcolor is decrypted, it will be overridden by background-color
                // So in theory, bgcolor and background-color won't use at the same time
                key = CSSKeys.backgroundColor.rawValue
            }
            cssArray.append("\(key): \(hsla) !important")
            if key == CSSKeys.border.rawValue {
                attributes
                    .filter { $0.key.hasPrefix("\(CSSKeys.border.rawValue)-")}
                    .forEach { attribute in
                        cssArray.append("\(attribute.key): \(attribute.value) !important")
                    }

            }
        }
        return cssArray
    }

    static func getHSLA(attribute: String) -> HSLA? {
        let color = attribute.trim()

        var hsla: HSLA?
        if let value = CSSMagic.definedColors[color] {
            hsla = value
        } else if color.hasPrefix("rgb") || color.hasPrefix("rgba") {
            guard let (r, g, b, a) = CSSMagic.getRGBA(by: color) else {
                return nil
            }
            hsla = CSSMagic.getHSLA(from: r, g: g, b: b, a: a)
        } else if color.hasPrefix("hsl") || color.hasPrefix("hsla") {
            hsla = CSSMagic.getHSLA(from: color)
        } else {
            guard let (r, g, b, a) = CSSMagic.getRGBA(from: color) else {
                return nil
            }
            hsla = CSSMagic.getHSLA(from: r, g: g, b: b, a: a)
        }
        return hsla
    }

    /// - Parameter color: CSS color representation, could be rgba, hex...etc
    /// - Returns: HSLA representation, e.g. hsla(100, 50%, 62%, 0.5). Depends on the given value, return value is not always has alpha
    static func getDarkModeColor(from color: String, isForeground: Bool) -> String? {
        guard var (colorAttribute, index, others) = parseAttribute(attribute: color) else { return nil }
        guard let hsla = getHSLA(attribute: colorAttribute) else { return nil }
        let darkModeHSLA = CSSMagic.hslaForDarkMode(hsla: hsla, isForeground: isForeground)
        others.insert(darkModeHSLA, at: index)
        return others.joined(separator: " ")
    }
}

// MARK: Color parser
extension CSSMagic {

    /// - Parameter hex: #FFF, #FFFF, #FFFFFF, #FFFFFFFF
    /// - Returns: (r, g, b, a)
    static func getRGBA(from hex: String) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        var hexColor = hex
        if hexColor.hasPrefix("#") {
            let start = hex.index(hexColor.startIndex, offsetBy: 1)
            hexColor = String(hexColor[start...])
        }
        switch hexColor.count {
        case 8:
            // RRGGBBAA
            break
        case 6:
            // RRGGBB
            hexColor = "\(hexColor)FF"
        case 4:
            // RGBA
            var result = ""
            hexColor.forEach { char in
                result = "\(result)\(char)\(char)"
            }
            hexColor = result
        case 3:
            // RGB
            var result = ""
            hexColor.forEach { char in
                result = "\(result)\(char)\(char)"
            }
            hexColor = "\(result)FF"
        default:
            return nil
        }

        let scanner = Scanner(string: hexColor)
        var hexNumber: UInt64 = 0
        guard scanner.scanHexInt64(&hexNumber) else { return nil }
        let r = CGFloat((hexNumber & 0xff000000) >> 24) / 255
        let g = CGFloat((hexNumber & 0x00ff0000) >> 16) / 255
        let b = CGFloat((hexNumber & 0x0000ff00) >> 8) / 255
        let a = CGFloat(hexNumber & 0x000000ff) / 255
        return (r, g, b, a)
    }

    /**
     Get CGFloat value of rgba from rgb() or rgba()
     
     The possible input are
     
     r: [0, 255] or [0%, 100%]
    
     g: [0, 255] or [0%, 100%]
    
     b: [0, 255] or [0%, 100%]
    
     a: [0.0, 1.0] or [0%, 100%]
     
     For r/ g/ b, they need to follow the same format, all int or all percentage
     
     For a, can be float or percentage
     - Parameter rgb: rgb(128, 128, 128), rgb(50%, 50%, 50%), rgba(50%, 50%, 50%, 0.5)
     - Returns: (r, g, b, a), range: [0.0, 1.0]
     */
    static func getRGBA(by rgb: String) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        guard let splitValues = CSSMagic.split(from: rgb),
              let rValue = splitValues[safe: 0],
              let gValue = splitValues[safe: 1],
              let bValue = splitValues[safe: 2],
              let r = CSSMagic.normalize(value: rValue, maximum: 255),
              let g = CSSMagic.normalize(value: gValue, maximum: 255),
              let b = CSSMagic.normalize(value: bValue, maximum: 255) else {
                  return nil
              }
        if let aValue = splitValues[safe: 3] {
            if aValue.contains("%"),
               let a = CSSMagic.normalize(value: aValue, maximum: 100) {
                return (r, g, b, a)
            } else if let a = Double(aValue) {
                return (r, g, b, CGFloat(a))
            }
        }
        return (r, g, b, 1)
    }

    /// - Parameters:
    ///   - r: Red, [0.0, 1.0]
    ///   - g: Green, [0.0, 1.0]
    ///   - b: Blue, [0.0, 1.0]
    ///   - a: Alpha, [0.0, 1.0]
    /// - Returns: HSLA representation, e.g. hsla(100, 50%, 50%, 0.4)
    static func getHSLA(from r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) -> HSLA {
        let max: CGFloat = max(r, g, b)
        let min: CGFloat = min(r, g, b)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var l = (max + min) / 2

        if max == min {
            // achromatic
            h = 0
            s = 0
        } else {
            let d = max - min
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
            switch max {
            case r:
                h = (g - b) / d + (g < b ? 6 : 0)
            case g:
                h = (b - r) / d + 2
            case b:
                h = (r - g) / d + 4
            default:
                break
            }
            h /= 6
        }
        s = s * 100
        s = round(s)
        l = l * 100
        l = round(l)
        h = round(360 * h)
        return HSLA(h: Int(h), s: Int(s), l: Int(l), a: a)
    }

    /**
     Parse HSLA from hsl() or hsla()
     
     The possible input are
     
     h: [0, 360]
    
     s: [0%, 100%]
    
     l: [0%, 100%]
    
     a: [0.0, 1.0] or [0%, 100%]
     
     - Parameter hsl: hsl(128, 100%, 100%), hsla(128, 100%, 100%, 0.5)
     - Returns: HSLA
     */
    static func getHSLA(from hslString: String) -> HSLA? {
        guard let values = CSSMagic.split(from: hslString) else { return nil }

        guard let h = Int(values[safe: 0] ?? ""),
              let sValue = CSSMagic.getNormalizeFloat(from: values[safe: 1] ?? ""),
              let lValue = CSSMagic.getNormalizeFloat(from: values[safe: 2] ?? "")
        else { return nil }

        let s = Int(sValue * 100)
        let l = Int(lValue * 100)
        if let a = values[safe: 3] {
            if a.contains("%"),
               let aValue = CSSMagic.getNormalizeFloat(from: a) {
                return HSLA(h: h, s: s, l: l, a: aValue)
            } else if let aValue = Double(a) {
                return HSLA(h: h, s: s, l: l, a: CGFloat(aValue))
            } else {
                return nil
            }
        }
        return HSLA(h: h, s: s, l: l, a: 1)
    }

    static func hslaForDarkMode(hsla: HSLA, isForeground: Bool) -> String {
        var l = hsla.l
        let isAchromatic = hsla.s <= 5
        switch (isForeground, isAchromatic) {
        case (true, true):
            return "hsla(0, 0%, 100%, \(hsla.a))"
        case (false, true):
            return "hsla(230, 12%, 10%, \(hsla.a))"
        case (true, false), (false, false):
            if isForeground {
                l = max(l, 100)
            } else {
                l = min(30, l)
            }
        }
        return "hsla(\(hsla.h), \(hsla.s)%, \(l)%, \(hsla.a))"
    }

    static func getRelativeLuminance(from hsla: HSLA) -> CGFloat? {
        let color = hsla.color
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        let rValue = transformToRLSpace(from: red)
        let gValue = transformToRLSpace(from: green)
        let bValue = transformToRLSpace(from: blue)
        return 0.2126 * rValue + 0.7152 * gValue + 0.0722 * bValue
    }

    private static func transformToRLSpace(from value: CGFloat) -> CGFloat {
        if value <= 0.03928 {
            return value / 12.92
        } else {
            return pow(((value + 0.055) / 1.055), 2.4)
        }
    }
}

// MARK: Helper function
extension CSSMagic {
    /// Split values from css representation
    /// - Parameter css: possible input rgb(1, 1, 1), hsla(100, 50%, 50%, 0.3)
    /// - Returns: The values between brackets
    static func split(from css: String) -> [String]? {
        guard let start = css.firstIndex(of: "("),
              let end = css.firstIndex(of: ")") else {
                  return nil
              }
        let index = css.index(after: start)
        let values = css[index..<end]
            .split(separator: ",")
            .compactMap({
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            })
        return values
    }

    /// Normalize input value to range [0.0, 1.0]
    /// - Parameters:
    ///   - value: possible value, string int "128" or percentage string "50%"
    ///   - maximum: maximum value
    /// - Returns: Normalize float value or nil
    static func normalize(value: String, maximum: CGFloat) -> CGFloat? {
        if let doubleValue = Double(value) {
            return min(doubleValue, maximum) / maximum
        }
        return CSSMagic.getNormalizeFloat(from: value)
    }

    static func getNormalizeFloat(from percentage: String) -> CGFloat? {
        guard percentage.contains(check: "%"),
              let end = percentage.firstIndex(of: "%") else { return nil }
        let start = percentage.startIndex
        let subString = percentage[start..<end]
        guard let value = Double(subString) else { return nil }
        let result = value / 100.0
        return result
    }

    static func splitInline(attributes: String) -> [CSSAttribute] {
        // "font-family: arial; font-size: 14px;"
        return attributes
            .split(separator: ";")
            .compactMap({ attribute -> CSSAttribute? in
                let splits = attribute.split(separator: ":")
                guard let key = splits[safe: 0],
                      let value = splits[safe: 1] else {
                          return nil
                      }
                return (String(key).trim(), String(value).trim())
            })
    }

    static func getCSSAnchor(of node: Element) -> String {
        if !node.id().isEmpty {
            return "#\(node.id())"
        }
        var anchor = node.tagNameNormal()
        if let classSet = try? node.classNames() {
            let className = Array(classSet).joined(separator: ".")
            if className.isEmpty == false {
                anchor = "\(anchor).\(className)"
            }
        }
        let ignoreKeys = [CSSKeys.target.rawValue,
                          CSSKeys.id.rawValue,
                          CSSKeys.class.rawValue]
        if let attributes = node.getAttributes()?.asList() {
            let selector = attributes
                .filter({ attribute in
                    let key = attribute.getKey()
                    let value = attribute.getValue()
                    let containQuotes = value.contains("\"") || value.contains("&quot;")
                    return !ignoreKeys.contains(key) && !containQuotes
                })
                .map(anchorMapper(attribute:))
                .joined(separator: "")
            anchor = "\(anchor)\(selector)"
        }
        // e.g. div.classA.classB[att="value1"][data="value2"]
        if anchor == node.tagNameNormal() {
            return (try? node.cssSelector()) ?? .empty
        } else {
            return anchor
        }
    }

    static func anchorMapper(attribute: Attribute) -> String {
        let key = attribute.getKey()
        let value = attribute.getValue()
            .trim()
            .preg_replace("\\n", replaceto: "")
            .preg_replace("font-family:([\\s\\S]*?);", replaceto: "")
        if key == "style" {
            let colorKeys = [
                CSSKeys.color.rawValue,
                CSSKeys.border.rawValue,
                CSSKeys.backgroundColor.rawValue
            ]
            let values = value
                .components(separatedBy: ";")
                .filter { !$0.isEmpty }
                .filter { styleValue in
                    colorKeys.reduce(false) { partialResult, colorKey in
                        styleValue.contains(check: colorKey) || partialResult
                    }
                }
            let assemble = values
                .map { "[\(key)*=\"\($0.trim())\"]" }
                .joined()
            return assemble
        } else {
            return "[\(key)=\"\(value)\"]"
        }
    }

    static func assemble(cssDict: [String: [String]]) -> String {
        var css = ""
        for (anchor, values) in cssDict {
            guard !values.isEmpty else { continue }
            let value = values.joined(separator: ";")
            css += "\(anchor) { \(value) }"
        }
        return css
    }

    static func isColor(attribute: String) -> Bool {
        let count = [4, 5, 7, 9]
        if attribute.hasPrefix("rgb") || attribute.hasPrefix("rgba") {
            return attribute.preg_match("rgba?(.*,.*,.*)")
        } else if attribute.hasPrefix("hsl") || attribute.hasPrefix("hsla") {
            return attribute.preg_match("hsla?(.*,.*,.*)")
        } else if definedColors.keys.contains(attribute) {
            return true
        } else if attribute.hasPrefix("#") && count.firstIndex(of: attribute.count) != nil {
            return true
        }
        return false
    }

    static func splitAttributeIfNeeded(attribute: String) -> [String] {
        if isColor(attribute: attribute) {
            return [attribute]
        } else {
            return attribute.components(separatedBy: .whitespacesAndNewlines)
        }
    }

    static func parseAttribute(attribute: String) -> (colorAttribute: String, index: Int, others: [String])? {
        var splits = splitAttributeIfNeeded(attribute: attribute)
        guard let index = splits.firstIndex(where: { isColor(attribute: $0)} ) else { return nil }
        let colorAttribute = splits.remove(at: index)
        return (colorAttribute, index, splits)
    }
}

extension SwiftSoup.Node {
    func flatChildNodes() -> [SwiftSoup.Element] {
        var result: [SwiftSoup.Node] = []
        result.append(self)
        var childNodes = self.getChildNodes()
        while let node = childNodes.first {
            result.append(childNodes.removeFirst())
            let subNodes = node.getChildNodes()
            if subNodes.isEmpty { continue }
            childNodes.append(contentsOf: subNodes)
        }
        return result.compactMap({ $0 as? Element })
    }
}

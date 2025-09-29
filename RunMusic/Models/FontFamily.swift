import Foundation
import SwiftUI

// MARK: - Font Family Model

struct FontFamily: Identifiable, Codable, Equatable {
    let id = UUID()
    let name: String
    let displayName: String
    let systemName: String // For system fonts
    let isPremium: Bool
    let category: FontCategory
    
    enum FontCategory: String, CaseIterable, Codable {
        case athletic = "Athletic"
        case impact = "Impact"
        case script = "Script"
        case geometric = "Geometric"
        case retro = "Retro"
        case minimal = "Minimal"
    }
    
    // MARK: - Font Application
    
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // Always use the specific font name for proper preview
        return .custom(systemName, size: size)
    }
    
    func customFont(size: CGFloat) -> Font {
        // Always use the specific font name for consistency
        return .custom(systemName, size: size)
    }
    
    // MARK: - Preset Fonts
    
    static let `default` = FontFamily(
        name: "Helvetica Neue",
        displayName: "Helvetica Neue",
        systemName: "Helvetica Neue",
        isPremium: false,
        category: .minimal
    )
    
    static let presets: [FontFamily] = [
        // Free fonts
        FontFamily(
            name: "SF Pro Display",
            displayName: "SF Pro Display", 
            systemName: "SF Pro Display",
            isPremium: false,
            category: .minimal
        ),
        FontFamily(
            name: "Avenir Next",
            displayName: "Avenir Next",
            systemName: "AvenirNext-Regular",
            isPremium: false,
            category: .geometric
        ),
        FontFamily(
            name: "Impact",
            displayName: "Impact",
            systemName: "Impact",
            isPremium: false,
            category: .impact
        ),
        
        // Premium fonts - Athletic & Sport
        FontFamily(
            name: "Futura Condensed",
            displayName: "Futura Condensed",
            systemName: "FuturaCondensedMedium",
            isPremium: true,
            category: .athletic
        ),
        FontFamily(
            name: "DIN Alternate",
            displayName: "DIN Alternate",
            systemName: "DINAlternate-Bold",
            isPremium: true,
            category: .athletic
        ),
        FontFamily(
            name: "DIN Condensed",
            displayName: "DIN Condensed",
            systemName: "DINCondensed-Bold",
            isPremium: true,
            category: .athletic
        ),
        
        // Premium fonts - Bold Impact
        FontFamily(
            name: "Arial Black",
            displayName: "Arial Black",
            systemName: "ArialMT",
            isPremium: true,
            category: .impact
        ),
        FontFamily(
            name: "Helvetica Neue Bold",
            displayName: "Helvetica Neue Bold",
            systemName: "HelveticaNeue-CondensedBold",
            isPremium: true,
            category: .impact
        ),
        FontFamily(
            name: "Copperplate Bold",
            displayName: "Copperplate Bold",
            systemName: "Copperplate-Bold",
            isPremium: true,
            category: .impact
        ),
        
        // Premium fonts - Script & Handwritten
        FontFamily(
            name: "Bradley Hand",
            displayName: "Bradley Hand",
            systemName: "BradleyHandITCTT-Bold",
            isPremium: true,
            category: .script
        ),
        FontFamily(
            name: "Marker Felt",
            displayName: "Marker Felt",
            systemName: "MarkerFelt-Wide",
            isPremium: true,
            category: .script
        ),
        FontFamily(
            name: "Noteworthy",
            displayName: "Noteworthy",
            systemName: "Noteworthy-Bold",
            isPremium: true,
            category: .script
        ),
        
        // Premium fonts - Geometric & Modern
        FontFamily(
            name: "Avenir Black",
            displayName: "Avenir Black",
            systemName: "AvenirNext-DemiBold",
            isPremium: true,
            category: .geometric
        ),
        FontFamily(
            name: "Gill Sans",
            displayName: "Gill Sans",
            systemName: "GillSans-Bold",
            isPremium: true,
            category: .geometric
        ),
        FontFamily(
            name: "Optima Bold",
            displayName: "Optima Bold",
            systemName: "Optima-ExtraBlack",
            isPremium: true,
            category: .geometric
        ),
        
        // Premium fonts - Retro & Vintage
        FontFamily(
            name: "American Typewriter",
            displayName: "American Typewriter",
            systemName: "AmericanTypewriter-CondensedBold",
            isPremium: true,
            category: .retro
        ),
        FontFamily(
            name: "Rockwell",
            displayName: "Rockwell",
            systemName: "Rockwell-Bold",
            isPremium: true,
            category: .retro
        ),
        FontFamily(
            name: "Courier Bold",
            displayName: "Courier Bold",
            systemName: "Courier-Bold",
            isPremium: true,
            category: .retro
        ),
        
        // Premium fonts - Clean Minimal
        FontFamily(
            name: "Helvetica Light",
            displayName: "Helvetica Light",
            systemName: "HelveticaNeue-UltraLight",
            isPremium: true,
            category: .minimal
        ),
        FontFamily(
            name: "Helvetica Thin",
            displayName: "Helvetica Thin",
            systemName: "HelveticaNeue-Thin",
            isPremium: true,
            category: .minimal
        )
    ]
    
    // MARK: - Filtering
    
    static var freePresets: [FontFamily] {
        presets.filter { !$0.isPremium }
    }
    
    static var premiumPresets: [FontFamily] {
        presets.filter { $0.isPremium }
    }
    
    static func presets(for category: FontCategory) -> [FontFamily] {
        presets.filter { $0.category == category }
    }
}

// MARK: - Hashable conformance for proper SwiftUI updates
extension FontFamily: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(systemName)
        hasher.combine(isPremium)
    }
}
import SwiftUI

struct RunColorScheme: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let primaryColor: CodableColor
    let secondaryColor: CodableColor
    let isCustom: Bool
    
    init(name: String, primaryColor: Color, secondaryColor: Color, isCustom: Bool = false) {
        self.id = UUID()
        self.name = name
        self.primaryColor = CodableColor(primaryColor)
        self.secondaryColor = CodableColor(secondaryColor)
        self.isCustom = isCustom
    }
    
    var gradient: LinearGradient {
        LinearGradient(
            colors: [primaryColor.color, secondaryColor.color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    var routeGradient: LinearGradient {
        LinearGradient(
            colors: [
                primaryColor.color.opacity(0.7),
                primaryColor.color.opacity(0.9),
                secondaryColor.color.opacity(0.5)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // Preset color schemes
    static let presets: [RunColorScheme] = [
        RunColorScheme(name: "sunset", primaryColor: .orange, secondaryColor: .pink),
        RunColorScheme(name: "ocean", primaryColor: .blue, secondaryColor: .cyan),
        RunColorScheme(name: "forest", primaryColor: .green, secondaryColor: .mint),
        RunColorScheme(name: "berry", primaryColor: .purple, secondaryColor: .pink),
        RunColorScheme(name: "fire", primaryColor: .red, secondaryColor: .orange),
        RunColorScheme(name: "lavender", primaryColor: .purple, secondaryColor: .blue),
        RunColorScheme(name: "golden", primaryColor: .yellow, secondaryColor: .orange),
        RunColorScheme(name: "emerald", primaryColor: .teal, secondaryColor: .green)
    ]
    
    static let `default` = presets[0] // sunset
}

// Helper to make Color codable
struct CodableColor: Codable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    
    init(_ color: Color) {
        // Extract RGBA components from SwiftUI Color
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.alpha = Double(a)
    }
    
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
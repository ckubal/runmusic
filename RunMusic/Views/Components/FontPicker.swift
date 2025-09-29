import SwiftUI

struct FontPicker: View {
    @Binding var selectedFont: FontFamily
    @StateObject private var subscriptionService = SubscriptionService.shared
    let title: String
    
    init(selectedFont: Binding<FontFamily>, title: String = "font family") {
        self._selectedFont = selectedFont
        self.title = title
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.custom("Helvetica Neue", size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Current font indicator (similar to Aa icon mentioned by user)
                Button(action: {
                    // Scroll to current selection or show a tooltip
                }) {
                    Text("Aa")
                        .font(selectedFont.customFont(size: 16))
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            // Free fonts section
            fontSection(
                title: "Free",
                fonts: FontFamily.freePresets,
                headerColor: .blue
            )
            
            // Premium fonts section
            fontSection(
                title: "Premium",
                fonts: FontFamily.premiumPresets,
                headerColor: .orange,
                requiresPremium: true
            )
        }
    }
    
    @ViewBuilder
    private func fontSection(title: String, fonts: [FontFamily], headerColor: Color, requiresPremium: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.custom("Helvetica Neue", size: 14))
                    .fontWeight(.semibold)
                    .foregroundColor(headerColor)
                
                if requiresPremium {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(fonts) { font in
                    FontCard(
                        font: font,
                        isSelected: selectedFont.id == font.id,
                        isLocked: requiresPremium && !subscriptionService.canAccessPremiumFonts(),
                        onTap: {
                            if requiresPremium && !subscriptionService.canAccessPremiumFonts() {
                                // For now, don't block anything for testing
                                // In production, this would show premium prompt
                                print("🔒 Premium font tapped, but allowing for testing")
                            }
                            selectedFont = font
                        }
                    )
                }
            }
        }
    }
}

struct FontCard: View {
    let font: FontFamily
    let isSelected: Bool
    let isLocked: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Preview text with font
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(height: 80)
                    .overlay(
                        VStack(spacing: 6) {
                            // Main preview text
                            Text("run the tunes")
                                .font(font.customFont(size: 16))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                            
                            // Sample subtitle
                            Text("San Francisco")
                                .font(font.customFont(size: 12))
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                        .opacity(isLocked ? 0.6 : 1.0)
                    )
                    .overlay(
                        // Premium lock overlay
                        Group {
                            if isLocked {
                                ZStack {
                                    Color.black.opacity(0.3)
                                    
                                    VStack(spacing: 4) {
                                        Image(systemName: "crown.fill")
                                            .font(.title3)
                                            .foregroundColor(.orange)
                                        
                                        Text("Premium")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.orange)
                                    }
                                }
                                .cornerRadius(12)
                            }
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? (font.isPremium ? .orange : .blue) : Color.clear,
                                lineWidth: 3
                            )
                    )
                
                // Font name with premium indicator
                HStack(spacing: 4) {
                    Text(font.displayName)
                        .font(.custom("Helvetica Neue", size: 12))
                        .fontWeight(.medium)
                        .foregroundColor(isSelected ? (font.isPremium ? .orange : .blue) : .primary)
                        .multilineTextAlignment(.center)
                    
                    if font.isPremium {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct FontCategoryFilter: View {
    @Binding var selectedCategory: FontFamily.FontCategory?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                FilterChip(
                    title: "All",
                    isSelected: selectedCategory == nil,
                    onTap: { selectedCategory = nil }
                )
                
                ForEach(FontFamily.FontCategory.allCases, id: \.self) { category in
                    FilterChip(
                        title: category.rawValue,
                        isSelected: selectedCategory == category,
                        onTap: { selectedCategory = category }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.custom("Helvetica Neue", size: 12))
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.systemGray6))
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack {
        FontPicker(selectedFont: .constant(FontFamily.default))
            .padding()
        
        Divider()
        
        FontCategoryFilter(selectedCategory: .constant(nil))
    }
}
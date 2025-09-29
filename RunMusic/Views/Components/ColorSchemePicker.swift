import SwiftUI

struct ColorSchemePicker: View {
    @Binding var selectedColorScheme: RunColorScheme
    let title: String
    let showCustomOption: Bool
    
    @State private var showingCustomPicker = false
    
    init(selectedColorScheme: Binding<RunColorScheme>, title: String = "color scheme", showCustomOption: Bool = true) {
        self._selectedColorScheme = selectedColorScheme
        self.title = title
        self.showCustomOption = showCustomOption
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.custom("Helvetica Neue", size: 18))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Preset color schemes
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(RunColorScheme.presets) { colorScheme in
                    ColorSchemeCard(
                        colorScheme: colorScheme,
                        isSelected: selectedColorScheme.id == colorScheme.id,
                        onTap: {
                            selectedColorScheme = colorScheme
                        }
                    )
                }
                
                // Custom color option
                if showCustomOption {
                    Button(action: {
                        showingCustomPicker = true
                    }) {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 80)
                                
                                VStack(spacing: 4) {
                                    Image(systemName: "plus.circle")
                                        .font(.title2)
                                        .foregroundColor(.primary)
                                    
                                    Text("custom")
                                        .font(.custom("Helvetica Neue", size: 12))
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showingCustomPicker) {
            CustomColorSchemePicker(selectedColorScheme: $selectedColorScheme)
        }
    }
}

struct ColorSchemeCard: View {
    let colorScheme: RunColorScheme
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Preview gradient
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme.gradient)
                    .frame(height: 80)
                    .overlay(
                        // Sample elements to show how colors look
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.white.opacity(0.85))
                                    .frame(width: 10, height: 10)
                                    .overlay(
                                        Text("i")
                                            .font(.system(size: 5, weight: .semibold))
                                            .foregroundColor(colorScheme.primaryColor.color)
                                    )
                                
                                Circle()
                                    .fill(Color.white.opacity(0.85))
                                    .frame(width: 10, height: 10)
                                    .overlay(
                                        Text("ii")
                                            .font(.system(size: 5, weight: .semibold))
                                            .foregroundColor(colorScheme.primaryColor.color)
                                    )
                                
                                Spacer()
                            }
                            
                            Spacer()
                            
                            HStack {
                                Text("san francisco")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(colorScheme.primaryColor.color)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(colorScheme.primaryColor.color.opacity(0.1))
                                    .cornerRadius(6)
                                
                                Spacer()
                            }
                        }
                        .padding(8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? colorScheme.primaryColor.color : Color.clear,
                                lineWidth: 3
                            )
                    )
                
                Text(colorScheme.name)
                    .font(.custom("Helvetica Neue", size: 12))
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? colorScheme.primaryColor.color : .primary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct CustomColorSchemePicker: View {
    @Binding var selectedColorScheme: RunColorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var primaryColor: Color = .orange
    @State private var secondaryColor: Color = .pink
    @State private var schemeName: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Name input
                VStack(alignment: .leading, spacing: 8) {
                    Text("scheme name")
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.medium)
                    
                    TextField("enter name", text: $schemeName)
                        .textFieldStyle(.roundedBorder)
                        .font(.custom("Helvetica Neue", size: 16))
                }
                
                // Color pickers
                VStack(spacing: 16) {
                    ColorPicker("primary color", selection: $primaryColor, supportsOpacity: false)
                        .font(.custom("Helvetica Neue", size: 16))
                    
                    ColorPicker("secondary color", selection: $secondaryColor, supportsOpacity: false)
                        .font(.custom("Helvetica Neue", size: 16))
                }
                
                // Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("preview")
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.medium)
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [primaryColor, secondaryColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(height: 100)
                        .overlay(
                            VStack(spacing: 8) {
                                Text("light work")
                                    .font(.custom("Helvetica Neue", size: 16))
                                    .fontWeight(.bold)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [primaryColor, secondaryColor],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                
                                HStack(spacing: 4) {
                                    Text("san francisco")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(primaryColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(primaryColor.opacity(0.1))
                                        .cornerRadius(8)
                                    
                                    Spacer()
                                }
                            }
                            .padding()
                        )
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("custom colors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("cancel") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("save") {
                        let customScheme = RunColorScheme(
                            name: schemeName.isEmpty ? "custom" : schemeName.lowercased(),
                            primaryColor: primaryColor,
                            secondaryColor: secondaryColor,
                            isCustom: true
                        )
                        selectedColorScheme = customScheme
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                }
            }
        }
    }
}

#Preview {
    ColorSchemePicker(selectedColorScheme: .constant(RunColorScheme.default))
        .padding()
}
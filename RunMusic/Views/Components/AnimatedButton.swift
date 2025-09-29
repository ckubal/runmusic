import SwiftUI

// Enhanced animated button with bouncy feedback
struct BouncyIconButton: View {
    let iconName: String
    let isActive: Bool
    let activeColor: Color
    let size: CGFloat
    let showStrikethrough: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var scale: CGFloat = 1.0
    
    init(iconName: String, isActive: Bool, activeColor: Color, size: CGFloat, showStrikethrough: Bool = true, action: @escaping () -> Void) {
        self.iconName = iconName
        self.isActive = isActive
        self.activeColor = activeColor
        self.size = size
        self.showStrikethrough = showStrikethrough
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            HapticFeedbackService.shared.mediumTap()
            
            // Trigger bounce animation
            withAnimation(.interpolatingSpring(stiffness: 600, damping: 15)) {
                scale = 0.8
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.interpolatingSpring(stiffness: 600, damping: 15)) {
                    scale = 1.0
                }
            }
            
            // Execute the action
            action()
        }) {
            ZStack {
                // Background circle for active state (only for non-gray colors)
                Circle()
                    .fill(isActive && activeColor != .gray ? activeColor.opacity(0.2) : Color.clear)
                    .frame(width: size * 1.8, height: size * 1.8)
                    .scaleEffect(isActive ? 1.0 : 0.8)
                    .animation(.easeInOut(duration: 0.2), value: isActive)
                
                // Icon with strikethrough overlay
                ZStack {
                    Image(systemName: iconName)
                        .font(.system(size: size, weight: .medium))
                        .foregroundColor(isActive ? activeColor : .gray.opacity(0.4))
                        .scaleEffect(scale)
                        .animation(.easeInOut(duration: 0.15), value: isActive)
                    
                    // Strikethrough line for inactive state
                    if !isActive && showStrikethrough {
                        Rectangle()
                            .fill(.gray.opacity(0.8))
                            .frame(width: size * 1.4, height: 2.5)
                            .rotationEffect(.degrees(-45))
                            .animation(.easeInOut(duration: 0.2), value: isActive)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 50) { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        } perform: {
            // Long press completed - could add additional functionality here
        }
    }
}

// MARK: - Animated Dropdown Component

struct AnimatedDropdown<Content: View>: View {
    let title: String
    let isExpanded: Binding<Bool>
    let content: () -> Content
    
    @State private var contentHeight: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.wrappedValue.toggle()
                }
                
                // Haptic feedback
                HapticFeedbackService.shared.lightTap()
            }) {
                HStack {
                    Text(title)
                        .font(.custom("Helvetica Neue", size: 14))
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                        .animation(.easeInOut(duration: 0.3), value: isExpanded.wrappedValue)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expandable content
            if isExpanded.wrappedValue {
                content()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                    .animation(.easeInOut(duration: 0.3), value: isExpanded.wrappedValue)
            }
        }
    }
}

// MARK: - Animated Toggle Button

struct AnimatedToggleButton: View {
    let title: String
    let systemImage: String
    let isOn: Binding<Bool>
    let tintColor: Color
    
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            HapticFeedbackService.shared.lightTap()
            
            // Bounce animation
            withAnimation(.interpolatingSpring(stiffness: 500, damping: 15)) {
                scale = 0.95
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.interpolatingSpring(stiffness: 500, damping: 15)) {
                    scale = 1.0
                }
            }
            
            // Toggle the state
            isOn.wrappedValue.toggle()
        }) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(isOn.wrappedValue ? tintColor : .gray)
                    .font(.title2)
                    .scaleEffect(isOn.wrappedValue ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isOn.wrappedValue)
                
                Text(title)
                    .font(.custom("Helvetica Neue", size: 16))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Animated toggle switch
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isOn.wrappedValue ? tintColor : Color(.systemGray4))
                        .frame(width: 50, height: 30)
                        .animation(.easeInOut(duration: 0.2), value: isOn.wrappedValue)
                    
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .offset(x: isOn.wrappedValue ? 10 : -10)
                        .animation(.easeInOut(duration: 0.2), value: isOn.wrappedValue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .scaleEffect(scale)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Animated Action Button

struct AnimatedActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            HapticFeedbackService.shared.mediumTap()
            
            // Bounce animation
            withAnimation(.interpolatingSpring(stiffness: 400, damping: 15)) {
                scale = 0.95
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.interpolatingSpring(stiffness: 400, damping: 15)) {
                    scale = 1.0
                }
            }
            
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.custom("Helvetica Neue", size: 16))
                    .fontWeight(.medium)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(color.opacity(0.3), lineWidth: 1)
                    )
            )
            .scaleEffect(scale)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 50) { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        } perform: {
            // Long press handled in main button action
        }
    }
}

// MARK: - Toast Notification

struct ToastView: View {
    let message: String
    let systemImage: String?
    let color: Color
    @Binding var isShowing: Bool
    
    var body: some View {
        if isShowing {
            HStack(spacing: 8) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                }
                Text(message)
                    .font(.custom("Helvetica Neue", size: 14))
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color)
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .move(edge: .top))
            ))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isShowing = false
                    }
                }
            }
        }
    }
}

// MARK: - Toast Manager

class ToastManager: ObservableObject {
    @Published var showToast = false
    @Published var toastMessage = ""
    @Published var toastIcon: String?
    @Published var toastColor: Color = .green
    
    func show(message: String, icon: String? = nil, color: Color = .green) {
        toastMessage = message
        toastIcon = icon
        toastColor = color
        
        withAnimation(.easeInOut(duration: 0.3)) {
            showToast = true
        }
    }
}
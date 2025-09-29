import SwiftUI

struct UsernameSelectionView: View {
    @EnvironmentObject private var firebaseAuth: FirebaseAuthService
    @State private var username = ""
    @State private var isAvailable: Bool? = nil
    @State private var validationError: String? = nil
    @State private var isCheckingAvailability = false
    @State private var isReserving = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    let onComplete: (String) -> Void
    let onSkip: () -> Void
    
    private let checkDelay: Double = 0.5
    @State private var checkTimer: Timer? = nil
    
    var body: some View {
        ZStack {
            // Gradient background matching app aesthetic
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.15),
                    Color.pink.opacity(0.08),
                    Color.purple.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Header
                VStack(spacing: 20) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.pink.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.orange.opacity(0.3), radius: 20, x: 0, y: 10)
                        
                        Text("@")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 8) {
                        Text("choose your username")
                            .font(.custom("Helvetica Neue", size: 28))
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.orange, Color.pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("this will appear on your shared run cards")
                            .font(.custom("Helvetica Neue", size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                // Username input
                VStack(spacing: 16) {
                    HStack {
                        Text("@")
                            .font(.custom("Helvetica Neue", size: 20))
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                        
                        TextField("username", text: $username)
                            .font(.custom("Helvetica Neue", size: 20))
                            .textCase(.lowercase)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .onChange(of: username) { _, newValue in
                                handleUsernameChange(newValue)
                            }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(borderColor, lineWidth: 2)
                    )
                    
                    // Status indicator
                    HStack {
                        statusIcon
                        statusText
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .animation(.easeInOut(duration: 0.2), value: isAvailable)
                    .animation(.easeInOut(duration: 0.2), value: validationError)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    // Continue button
                    Button {
                        Task {
                            await reserveUsername()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if isReserving {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            
                            Text(isReserving ? "reserving..." : "continue")
                                .font(.custom("Helvetica Neue", size: 18))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: isUsernameValid ? [Color.orange, Color.pink.opacity(0.8)] : [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: isUsernameValid ? Color.orange.opacity(0.3) : Color.clear, radius: 10, x: 0, y: 5)
                    }
                    .disabled(!isUsernameValid || isReserving)
                    
                    // Skip button
                    Button("skip for now") {
                        onSkip()
                    }
                    .font(.custom("Helvetica Neue", size: 16))
                    .foregroundColor(.secondary)
                    .disabled(isReserving)
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .padding()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Computed Properties
    
    private var borderColor: Color {
        if validationError != nil {
            return .red.opacity(0.6)
        } else if isAvailable == true {
            return .green.opacity(0.6)
        } else if isAvailable == false {
            return .orange.opacity(0.6)
        } else {
            return .gray.opacity(0.3)
        }
    }
    
    private var statusIcon: some View {
        Group {
            if isCheckingAvailability {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.secondary)
            } else if validationError != nil {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            } else if isAvailable == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if isAvailable == false {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.clear)
            }
        }
        .font(.system(size: 14))
    }
    
    private var statusText: some View {
        Text(statusMessage)
            .font(.custom("Helvetica Neue", size: 12))
            .foregroundColor(statusColor)
    }
    
    private var statusMessage: String {
        if isCheckingAvailability {
            return "checking availability..."
        } else if let error = validationError {
            return error
        } else if isAvailable == true {
            return "username available!"
        } else if isAvailable == false {
            return "username not available"
        } else if username.isEmpty {
            return "enter a username"
        } else {
            return ""
        }
    }
    
    private var statusColor: Color {
        if validationError != nil {
            return .red
        } else if isAvailable == true {
            return .green
        } else if isAvailable == false {
            return .orange
        } else {
            return .secondary
        }
    }
    
    private var isUsernameValid: Bool {
        validationError == nil && isAvailable == true && !username.isEmpty
    }
    
    // MARK: - Methods
    
    private func handleUsernameChange(_ newValue: String) {
        // Reset states
        isAvailable = nil
        validationError = nil
        
        // Cancel existing timer
        checkTimer?.invalidate()
        
        // Validate format first
        let validation = FirestoreService.shared.validateUsername(newValue)
        if !validation.isValid {
            validationError = validation.error
            return
        }
        
        // If validation passes and username is not empty, check availability after delay
        if !newValue.isEmpty {
            isCheckingAvailability = true
            checkTimer = Timer.scheduledTimer(withTimeInterval: checkDelay, repeats: false) { _ in
                Task {
                    await checkUsernameAvailability(newValue)
                }
            }
        }
    }
    
    @MainActor
    private func checkUsernameAvailability(_ username: String) async {
        do {
            let available = try await FirestoreService.shared.isUsernameAvailable(username)
            isAvailable = available
        } catch {
            validationError = "Unable to check availability"
        }
        isCheckingAvailability = false
    }
    
    @MainActor
    private func reserveUsername() async {
        guard let userId = firebaseAuth.currentUser?.uid else {
            errorMessage = "Authentication required"
            showError = true
            return
        }
        
        isReserving = true
        
        do {
            let reserved = try await FirestoreService.shared.reserveUsername(username, for: userId)
            if reserved {
                try await FirestoreService.shared.confirmUsernameReservation(username, for: userId)
                
                // Update the user profile with the username
                try await firebaseAuth.updateUsername(username)
                
                // Add a small delay to ensure the profile update is complete
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Force reload the user profile to ensure the UI detects the change
                await firebaseAuth.loadUserProfile(userId: userId)
                
                print("✅ Username reservation complete, profile reloaded")
                onComplete(username)
            } else {
                // Username was taken between our check and reservation attempt
                isAvailable = false
                await checkUsernameAvailability(username)
            }
        } catch {
            errorMessage = "Failed to reserve username. Please try again."
            showError = true
        }
        
        isReserving = false
    }
}

#Preview {
    UsernameSelectionView(
        onComplete: { username in
            print("Username selected: \(username)")
        },
        onSkip: {
            print("Username selection skipped")
        }
    )
    .environmentObject(FirebaseAuthService.shared)
}
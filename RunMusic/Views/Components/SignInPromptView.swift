import SwiftUI

struct SignInPromptView: View {
    let context: SignInContext
    let onSignIn: () -> Void
    let onDismiss: () -> Void
    let onContinueWithoutSignIn: (() -> Void)?
    
    @EnvironmentObject private var firebaseAuth: FirebaseAuthService
    @StateObject private var authViewModel = AuthViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: context.icon)
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text(context.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(context.message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 12) {
                // Google Sign-In Button
                Button {
                    Task {
                        await firebaseAuth.signInWithGoogle()
                        if firebaseAuth.isAuthenticated {
                            onSignIn()
                        }
                    }
                } label: {
                    HStack {
                        if firebaseAuth.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(colorScheme == .dark ? .white : .black)
                        } else {
                            Image("google_logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .padding(.leading, 15)
                        }
                        
                        Spacer()
                        
                        Text(firebaseAuth.isLoading ? "signing in..." : "Sign in with Google")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Spacer()
                    }
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                }
                .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                .disabled(firebaseAuth.isLoading)
                
                // Apple Sign-In Button
                Button {
                    Task {
                        authViewModel.startAppleSignIn()
                        // Wait for Apple sign-in completion
                        while authViewModel.authSheetState == .authenticating {
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        }
                        if authViewModel.authSheetState == .successful {
                            onSignIn()
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 20))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.leading, 15)
                        
                        Spacer()
                        
                        Text("Sign in with Apple")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Spacer()
                    }
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                }
                .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                .disabled(authViewModel.authSheetState == .authenticating || authViewModel.authSheetState == .linkingAndLoading)
                
                if let continueAction = onContinueWithoutSignIn {
                    Button {
                        continueAction()
                    } label: {
                        Text(context.skipText)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let errorMessage = firebaseAuth.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 8)
        .padding()
    }
}

enum SignInContext {
    case savingRun
    case exportingCard
    case multipleRuns
    case firstCustomization
    case spotifyImport
    
    var icon: String {
        switch self {
        case .savingRun:
            return "cloud.fill"
        case .exportingCard:
            return "square.and.arrow.up"
        case .multipleRuns:
            return "icloud.and.arrow.up"
        case .firstCustomization:
            return "paintbrush.fill"
        case .spotifyImport:
            return "music.note.house.fill"
        }
    }
    
    var title: String {
        switch self {
        case .savingRun:
            return "Save your work to the cloud?"
        case .exportingCard:
            return "Keep your creations safe"
        case .multipleRuns:
            return "Sync across all your devices"
        case .firstCustomization:
            return "Never lose your customizations"
        case .spotifyImport:
            return "Secure cloud storage required"
        }
    }
    
    var message: String {
        switch self {
        case .savingRun:
            return "Sign in to automatically save your run customizations. They'll be available on all your devices, even if you delete the app."
        case .exportingCard:
            return "Sign in to save this card design to the cloud before sharing. You'll be able to edit it later or recreate it on other devices."
        case .multipleRuns:
            return "You have several customized runs! Sign in to sync them across all your devices and keep them safe in the cloud."
        case .firstCustomization:
            return "You're customizing your first run! Sign in to save these changes to the cloud so they'll never be lost."
        case .spotifyImport:
            return "Your Spotify listening history will be securely stored in your personal cloud account, accessible across all your devices. This ensures your data won't be lost if you reinstall the app.\n\nFree accounts can store up to 1,000 tracks. Premium accounts get unlimited track storage."
        }
    }
    
    var skipText: String {
        switch self {
        case .savingRun:
            return "save locally only"
        case .exportingCard:
            return "export without saving"
        case .multipleRuns:
            return "keep local only"
        case .firstCustomization:
            return "continue without saving"
        case .spotifyImport:
            return "cancel import"
        }
    }
}

struct SignInPromptModifier: ViewModifier {
    @Binding var showSignInPrompt: Bool
    let context: SignInContext
    let onSignIn: () -> Void
    let onContinueWithoutSignIn: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if showSignInPrompt {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showSignInPrompt = false
                        }
                    
                    SignInPromptView(
                        context: context,
                        onSignIn: {
                            showSignInPrompt = false
                            onSignIn()
                        },
                        onDismiss: {
                            showSignInPrompt = false
                        },
                        onContinueWithoutSignIn: onContinueWithoutSignIn.map { action in
                            {
                                showSignInPrompt = false
                                action()
                            }
                        }
                    )
                }
            }
    }
}

extension View {
    func signInPrompt(
        isPresented: Binding<Bool>,
        context: SignInContext,
        onSignIn: @escaping () -> Void,
        onContinueWithoutSignIn: (() -> Void)? = nil
    ) -> some View {
        modifier(SignInPromptModifier(
            showSignInPrompt: isPresented,
            context: context,
            onSignIn: onSignIn,
            onContinueWithoutSignIn: onContinueWithoutSignIn
        ))
    }
}
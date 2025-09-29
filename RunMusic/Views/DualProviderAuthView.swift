import SwiftUI
import AuthenticationServices

struct DualProviderAuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
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
            
            switch authViewModel.authSheetState {
            case .idle:
                authContent
            case .authenticating, .linkingAndLoading:
                loadingView
            case .successful:
                loadingView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authViewModel.authSheetState)
        .onChange(of: authViewModel.authSheetState) { _, newState in
            if newState == .successful {
                dismiss()
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                .scaleEffect(1.5)
            
            Text("setting up your account...")
                .font(.custom("Helvetica Neue", size: 18))
                .foregroundColor(.primary)
        }
        .transition(.opacity)
    }
    
    private var authContent: some View {
        VStack(spacing: 0) {
            VStack {
                Spacer()
                
                // App branding
                VStack(spacing: 20) {
                    // Logo
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.pink.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: Color.orange.opacity(0.3), radius: 20, x: 0, y: 10)
                        
                        Image(systemName: "figure.run")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 8) {
                        Text("run the tunes")
                            .font(.custom("Helvetica Neue", size: 42))
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.orange, Color.pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    
                    Text("create an account to save & share!")
                        .font(.custom("Helvetica Neue", size: 18))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: 15) {
                if let errorMessage = authViewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 5)
                }

                // Google Sign-In Button
                Button {
                    Task {
                        await authViewModel.signInWithGoogle()
                    }
                } label: {
                    HStack {
                        Image("google_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .padding(.leading, 15)
                        
                        Spacer()
                        
                        Text("Sign in with Google")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Spacer()
                    }
                    .frame(height: 50)
                    .frame(maxWidth: 320)
                }
                .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                .disabled(authViewModel.authSheetState != .idle)
                
                // Apple Sign-In Button
                Button {
                    authViewModel.startAppleSignIn()
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
                    .frame(maxWidth: 320)
                }
                .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                .disabled(authViewModel.authSheetState != .idle)
                
                // Terms and privacy
                VStack(spacing: 5) {
                    Text("by signing in, you agree to our")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                    
                    HStack(spacing: 5) {
                        Link("terms", destination: URL(string: "https://runmusic.app/terms")!)
                            .font(.caption2)
                            .foregroundColor(.orange)
                        
                        Text("and")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                        
                        Link("privacy policy", destination: URL(string: "https://runmusic.app/privacy")!)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 20)
                .multilineTextAlignment(.center)
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal)
    }
}

// MARK: - Apple Sign-In Button Wrapper (Unused - keeping for reference)
//
// struct SignInWithAppleButtonViewRepresentable: UIViewRepresentable {
//     func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
//         let button = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
//         button.cornerRadius = 8
//         return button
//     }
//     
//     func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
//         // No updates needed
//     }
// }

// MARK: - Preview

#Preview {
    DualProviderAuthView()
        .environmentObject(AuthViewModel())
}
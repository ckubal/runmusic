import Foundation
import FirebaseAuth
import GoogleSignIn
import Combine
import FirebaseCore
import FirebaseFirestore
import AuthenticationServices
import CryptoKit
import os.log
import  FirebaseFunctions

// MARK: - Authentication State & Models

enum AuthenticationState: Equatable {
    case initial
    case unauthenticated
    case authenticated
}

enum AuthSheetState: Equatable {
    case idle
    case authenticating
    case linkingAndLoading
    case successful
}

// MARK: - AuthViewModel

@MainActor
class AuthViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var authState: AuthenticationState = .initial
    @Published var errorMessage: String? = nil
    @Published var showingAuthSheet = false
    @Published var authSheetState: AuthSheetState = .idle
    
    @Published private(set) var isUserPermanentlyAuthenticated: Bool = false
    @Published private(set) var userProfile: UserProfile? = nil
    
    // MARK: - Private Properties
    private var authStateHandler: AuthStateDidChangeListenerHandle?
    private var db = Firestore.firestore()
    private let functions = Functions.functions()
    private var userDocumentListener: ListenerRegistration?
    
    // Apple Sign-In nonce
    fileprivate var currentNonce: String?
    
    var isCurrentUserAnonymous: Bool {
        Auth.auth().currentUser?.isAnonymous ?? true
    }
    
    override init() {
        super.init()
        os_log(.debug, "AuthViewModel: Initializing.")
        registerAuthStateHandler()
    }
    
    deinit {
        if let handler = authStateHandler { Auth.auth().removeStateDidChangeListener(handler) }
        userDocumentListener?.remove()
        os_log(.debug, "AuthViewModel: Deinitialized and cleaned up listeners.")
    }
    
    func promptForLogin() {
        errorMessage = nil
        authSheetState = .idle
        showingAuthSheet = true
    }
    
    func getCurrentUserID() -> String? {
        return Auth.auth().currentUser?.uid
    }
    
    // MARK: - Auth State Management
    
    private func registerAuthStateHandler() {
        if authStateHandler != nil { Auth.auth().removeStateDidChangeListener(authStateHandler!) }
        
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] (auth, user) in
            guard let self = self else { return }
            
            if let currentUser = user {
                self.authState = .authenticated
                self.isUserPermanentlyAuthenticated = !currentUser.isAnonymous
                self.setupUserDocumentListener(userId: currentUser.uid)
                
                // Sync service tokens after successful authentication
                if !currentUser.isAnonymous {
                    Task {
                        await self.syncServiceTokens()
                    }
                }
            } else {
                self.authState = .unauthenticated
                self.isUserPermanentlyAuthenticated = false
                self.clearUserSession()
                // Commented out to prevent error when showing Strava login first
                // self.signInAnonymously()
            }
        }
    }
    
    private func signInAnonymously() {
        Auth.auth().signInAnonymously { [weak self] (authResult, error) in
            if let error = error {
                os_log(.error, "Anonymous sign-in error: %{public}s", error.localizedDescription)
                self?.errorMessage = "Could not start a browse session. Please check your connection."
            }
        }
    }
    
    private func clearUserSession() {
        errorMessage = nil
        userDocumentListener?.remove()
        userDocumentListener = nil
        userProfile = nil
        authSheetState = .idle
    }
    
    func logOut() {
        os_log(.info, "AuthViewModel: Attempting log out.")
        GIDSignIn.sharedInstance.signOut()
        do { 
            try Auth.auth().signOut() 
        } catch { 
            self.errorMessage = "Error signing out." 
        }
    }
    
    // MARK: - Enhanced Sign-In Logic (from Captune Creator)
    
    /// Signs in a user directly with a credential. This is for EXISTING users.
    /// The Firebase SDK will handle replacing the anonymous session automatically.
    func signIn(with credential: AuthCredential) async -> Bool {
        self.authSheetState = .linkingAndLoading
        self.errorMessage = nil
        
        do {
            let authResult = try await Auth.auth().signIn(with: credential)
            let user = authResult.user
            os_log(.info, "Direct sign-in successful.")
            
            self.isUserPermanentlyAuthenticated = true
            
            // CRITICAL FIX: Ensure user profile exists after sign-in
            await ensureUserProfileExists(user: user, appleFullName: nil)
            
            self.authSheetState = .successful
            return true
        } catch {
            os_log(.error, "Direct sign-in failed: %{public}s", error.localizedDescription)
            self.errorMessage = "Could not sign in to your account. Please try again."
            self.authSheetState = .idle
            return false
        }
    }
    
    /// Links an existing anonymous user to a new permanent credential. This is for NEW users.
    func linkAnonymousUser(with credential: AuthCredential, fullName: PersonNameComponents?) async -> Bool {
        self.authSheetState = .linkingAndLoading
        self.errorMessage = nil
        
        // Check if we have an anonymous user to link to
        var currentUser = Auth.auth().currentUser
        
        // If no user or user is not anonymous, create anonymous session first
        if currentUser == nil || !currentUser!.isAnonymous {
            os_log(.info, "No anonymous user found. Creating anonymous session for linking...")
            do {
                let authResult = try await Auth.auth().signInAnonymously()
                currentUser = authResult.user
                os_log(.info, "Anonymous session created successfully")
            } catch {
                os_log(.error, "Failed to create anonymous session: %{public}s", error.localizedDescription)
                self.errorMessage = "Failed to initialize session. Please try again."
                self.authSheetState = .idle
                return false
            }
        }
        
        guard let anonymousUser = currentUser, anonymousUser.isAnonymous else {
            os_log(.error, "Link failed: Could not establish anonymous session.")
            self.errorMessage = "Your session has expired. Please try again."
            self.authSheetState = .idle
            return false
        }
        
        do {
            let authResult = try await anonymousUser.link(with: credential)
            let user = authResult.user
            os_log(.info, "Link successful. New permanent user: %{public}s", user.uid)
            
            self.isUserPermanentlyAuthenticated = true
            
            await ensureUserProfileExists(user: user, appleFullName: fullName)
            
            os_log(.info, "New user link flow complete. Setting state to successful.")
            self.authSheetState = .successful
            return true
        } catch {
            os_log(.error, "Linking failed: %{public}s", error.localizedDescription)
            self.isUserPermanentlyAuthenticated = false
            self.errorMessage = "Failed to create your account: \(error.localizedDescription)"
            self.authSheetState = .idle
            return false
        }
    }
    
    // MARK: - Google Sign-In (Enhanced with Cross-Provider Check)
    
    func signInWithGoogle() async {
        authSheetState = .authenticating
        errorMessage = nil
        
        do {
            guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = await windowScene.windows.first,
                  let rootViewController = await window.rootViewController else {
                throw AuthError.noRootViewController
            }
            
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                throw AuthError.noClientID
            }
            
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
            
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.noIDToken
            }
            
            let accessToken = result.user.accessToken.tokenString
            let userEmail = result.user.profile?.email ?? ""
            
            // Step 1: Check if user exists on backend
            let checkResult = try await functions.httpsCallable("checkIfGoogleUserExists").call(["googleEmail": userEmail])
            let resultData = checkResult.data as? [String: Any]
            let userExists = resultData?["exists"] as? Bool ?? false
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            
            if !userExists {
                // No account exists - safe to create new one
                os_log(.default, "Google user does not exist. Initiating link flow.")
                _ = await linkAnonymousUser(with: credential, fullName: nil)
                return
            }
            
            // Account exists - check if it's a Google account or cross-provider conflict
            let hasGoogleProvider = resultData?["hasGoogleProvider"] as? Bool ?? false
            let existingProviders = resultData?["existingProviders"] as? [String] ?? []
            
            if hasGoogleProvider {
                // Same provider - safe to sign in
                os_log(.default, "Google user exists. Initiating direct sign-in.")
                _ = await signIn(with: credential)
            } else {
                // Cross-provider conflict - show helpful error
                let otherProvider = existingProviders.first == "apple.com" ? "Apple" : "another service"
                errorMessage = "This email is already registered with \(otherProvider). Please log in with \(otherProvider) to access your existing account."
                authSheetState = .idle
                os_log(.default, "Google sign-in blocked: cross-provider conflict with %{public}s", existingProviders.joined(separator: ","))
            }
        } catch {
            errorMessage = error.localizedDescription
            authSheetState = .idle
        }
    }
    
    // MARK: - User Profile Management
    
    private func setupUserDocumentListener(userId: String) {
        if userDocumentListener != nil { userDocumentListener?.remove() }
        let docRef = db.collection("users").document(userId)
        userDocumentListener = docRef.addSnapshotListener { [weak self] documentSnapshot, error in
            guard let self = self else { return }
            if let document = documentSnapshot, document.exists {
                // Convert Firestore document to UserProfile
                do {
                    self.userProfile = try document.data(as: UserProfile.self)
                } catch {
                    os_log(.error, "Failed to decode user profile: %{public}s", error.localizedDescription)
                }
            } else {
                self.userProfile = nil
            }
        }
    }
    
    private func ensureUserProfileExists(user: User, appleFullName: PersonNameComponents?) async {
        do {
            let profileExists = try await FirestoreService.shared.userProfileExists(userId: user.uid)
            
            if !profileExists {
                var userProfile = UserProfile(
                    id: user.uid,
                    email: user.email ?? "",
                    displayName: getDisplayName(from: user, appleFullName: appleFullName),
                    photoURL: user.photoURL?.absoluteString,
                    createdAt: Date(),
                    lastActiveAt: Date(),
                    preferences: UserPreferences.shared.exportToFirebase(),
                    stravaUserId: nil,
                    username: nil
                )
                
                // Add Strava user ID if available
                if StravaService.shared.isAuthenticated, let stravaId = StravaService.shared.athlete?.id {
                    userProfile.stravaUserId = String(stravaId)
                }
                
                try await FirestoreService.shared.createUserProfile(userProfile)
            } else {
                try await FirestoreService.shared.updateLastActive(userId: user.uid)
            }
            
            // Set display name in Firebase Auth if needed for Apple Sign-In
            if let fullName = appleFullName, user.displayName == nil {
                Task {
                    let changeRequest = user.createProfileChangeRequest()
                    changeRequest.displayName = PersonNameComponentsFormatter().string(from: fullName)
                    try? await changeRequest.commitChanges()
                }
            }
        } catch {
            os_log(.error, "Error creating/updating user profile: %{public}s", error.localizedDescription)
        }
    }
    
    private func getDisplayName(from user: User, appleFullName: PersonNameComponents?) -> String {
        if let fullName = appleFullName {
            return PersonNameComponentsFormatter().string(from: fullName)
        } else if let firebaseDisplayName = user.displayName, !firebaseDisplayName.isEmpty {
            return firebaseDisplayName
        }
        return ""
    }
    
    // MARK: - Service Token Sync
    
    private func syncServiceTokens() async {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            os_log(.debug, "No permanent user for token sync")
            return
        }
        
        os_log(.info, "Starting service token sync for user %{public}s", user.uid)
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await SpotifyService.shared.syncWithFirebase()
            }
            
            group.addTask {
                await StravaService.shared.syncWithFirebase()
            }
        }
        
        os_log(.info, "Service token sync completed")
        
        // Log final authentication status
        let spotifyAuth = await SpotifyService.shared.isAuthenticated
        let stravaAuth = await StravaService.shared.isAuthenticated
        os_log(.info, "Auth Status - Spotify: %{public}@, Strava: %{public}@", String(spotifyAuth), String(stravaAuth))
    }
    
    // MARK: - Username Management
    
    func updateUsername(_ username: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.noUser
        }
        
        // Update user profile with username
        try await FirestoreService.shared.updateUserProfile(UserProfile(
            id: user.uid,
            email: user.email ?? "",
            displayName: user.displayName ?? "",
            photoURL: user.photoURL?.absoluteString,
            createdAt: Date(), // This will be ignored in merge update
            lastActiveAt: Date(),
            preferences: UserPreferences.shared.exportToFirebase(),
            stravaUserId: StravaService.shared.athlete?.id != nil ? String(StravaService.shared.athlete!.id) : nil,
            username: username
        ))
        
        os_log(.info, "Username updated successfully: @%{public}s", username)
    }
    
    // MARK: - Apple Sign-In Nonce Generation
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            for random in randoms {
                if remainingLength == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
    }
}

// MARK: - Apple Sign-In Delegate

extension AuthViewModel: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
    }
    
    func startAppleSignIn() {
        let nonce = randomNonceString()
        currentNonce = nonce
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        authSheetState = .authenticating
        
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            errorMessage = "Apple sign-in error: invalid credentials received."
            authSheetState = .idle
            return
        }
        
        let appleUserID = appleIDCredential.user
        let appleEmail = appleIDCredential.email
        
        Task {
            do {
                // Step 1: Check if the user exists on our backend
                var callData: [String: Any] = ["appleUserId": appleUserID]
                if let email = appleEmail {
                    callData["appleEmail"] = email
                }
                
                let result = try await functions.httpsCallable("checkIfAppleUserExists").call(callData)
                let resultData = result.data as? [String: Any]
                let userExists = resultData?["exists"] as? Bool ?? false
                
                // Create credential for sign-in/link operation
                guard let nonce = currentNonce,
                      let appleIDToken = appleIDCredential.identityToken,
                      let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                    errorMessage = "Could not verify Apple credential. Please try again."
                    authSheetState = .idle
                    return
                }
                
                let credential = OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: nonce, fullName: appleIDCredential.fullName)
                
                if !userExists {
                    // No account exists - safe to create new one
                    os_log(.default, "Apple user does not exist. Initiating link flow.")
                    _ = await linkAnonymousUser(with: credential, fullName: appleIDCredential.fullName)
                    return
                }
                
                // Account exists - check if it's an Apple account or cross-provider conflict
                let hasAppleProvider = resultData?["hasAppleProvider"] as? Bool ?? false
                let existingProviders = resultData?["existingProviders"] as? [String] ?? []
                
                if hasAppleProvider {
                    // Same provider - safe to sign in
                    os_log(.default, "Apple user exists. Initiating direct sign-in.")
                    _ = await signIn(with: credential)
                } else {
                    // Cross-provider conflict - show helpful error
                    let otherProvider = existingProviders.first == "google.com" ? "Google" : "another service"
                    errorMessage = "This email is already registered with \(otherProvider). Please log in with \(otherProvider) to access your existing account."
                    authSheetState = .idle
                    os_log(.default, "Apple sign-in blocked: cross-provider conflict with %{public}s", existingProviders.joined(separator: ","))
                }
            } catch {
                os_log(.error, "Error calling checkIfAppleUserExists or during sign-in: %{public}s", error.localizedDescription)
                errorMessage = "An error occurred: \(error.localizedDescription)"
                authSheetState = .idle
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
            errorMessage = nil
        } else {
            errorMessage = "Sign-in failed. Please try again."
        }
        authSheetState = .idle
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case noRootViewController
    case noClientID
    case noIDToken
    case noUser
    
    var errorDescription: String? {
        switch self {
        case .noRootViewController:
            return "Unable to find root view controller"
        case .noClientID:
            return "No client ID found in Firebase configuration"
        case .noIDToken:
            return "Failed to get ID token from Google Sign-In"
        case .noUser:
            return "No authenticated user found"
        }
    }
}

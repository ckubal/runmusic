# Apple Sign-In Setup for RunMusic

This document outlines the steps needed to enable Apple Sign-In in the RunMusic Firebase project.

## Firebase Console Configuration

### 1. Enable Apple as a Sign-In Provider

1. Go to Firebase Console → Authentication → Sign-in method
2. Click on "Apple" in the Sign-in providers list
3. Toggle "Enable" to ON
4. Configure the following settings:

**OAuth redirect URI:**
```
https://runmusic-[PROJECT-ID].firebaseapp.com/__/auth/handler
```
(Replace [PROJECT-ID] with your actual Firebase project ID)

### 2. Apple Developer Console Setup

You'll need to configure Apple Sign-In in your Apple Developer account:

#### A. Create an App ID (if not already done)
1. Go to Apple Developer Console → Certificates, Identifiers & Profiles → Identifiers
2. Create or edit your App ID for RunMusic
3. Enable "Sign In with Apple" capability
4. Configure domains and email sources (use Firebase callback URL above)

#### B. Create a Service ID for Web Authentication
1. Create a new Service ID for web authentication
2. Enable "Sign In with Apple" for this Service ID  
3. Configure Web Authentication:
   - Primary App ID: Your RunMusic App ID
   - Domains: `runmusic-[PROJECT-ID].firebaseapp.com`
   - Return URLs: The OAuth redirect URI from step 1

#### C. Create a Private Key for Apple Sign-In
1. Go to Keys section in Apple Developer Console
2. Create a new key with "Sign In with Apple" enabled
3. Download the .p8 key file (keep it secure!)
4. Note the Key ID

### 3. Configure Firebase with Apple Credentials

Back in Firebase Console → Authentication → Sign-in method → Apple:

1. **Service ID:** Enter the Service ID you created in Apple Developer Console
2. **OAuth code flow configuration:**
   - Team ID: Your Apple Developer Team ID
   - Key ID: The Key ID from the private key you created
   - Private Key: Upload or paste the content of the .p8 file

### 4. iOS App Configuration

Ensure your iOS app is properly configured:

#### A. Xcode Project Settings
1. Add "Sign In with Apple" capability to your app target
2. Ensure your Bundle ID matches the App ID configured in Apple Developer Console

#### B. Info.plist URL Schemes
The app already includes the Firebase auth URL scheme. Ensure this is present:
```xml
<key>CFBundleURLTypes</key>
<array>
    <key>CFBundleURLName</key>
    <string>runmusic-firebase-auth</string>
    <key>CFBundleURLSchemes</key>
    <array>
        <string>runmusic-[PROJECT-ID]</string>
    </array>
</array>
```

## Implementation Status

✅ **Code Implementation Complete:**
- AuthViewModel with Apple Sign-In support
- Cross-provider conflict detection
- Firebase Cloud Functions for user verification
- UI with both Google and Apple sign-in buttons

⚠️ **Manual Configuration Required:**
- Firebase Console Apple provider setup
- Apple Developer Console configuration
- Service ID and Private Key setup

## Testing

Once configured, test the following scenarios:

1. **New Apple User:** Sign in with Apple (new account) → Should create account
2. **Existing Apple User:** Sign in with Apple (existing) → Should sign in
3. **Cross-Provider Conflict:** 
   - Create account with Google email
   - Try to sign in with Apple using same email
   - Should show conflict message: "Account exists, use Google instead"
4. **Vice Versa:** Same test but Google → Apple conflict

## Security Considerations

- The private key (.p8 file) should never be committed to version control
- Store Apple credentials securely in Firebase Console
- Test the auth flow thoroughly before production release
- Consider implementing account linking for users who want to connect both providers

## Support

If you encounter issues:
1. Check Firebase Console logs under Functions
2. Review Apple Developer Console configuration
3. Ensure all domains and callbacks match exactly
4. Test with Firebase Auth emulator for development
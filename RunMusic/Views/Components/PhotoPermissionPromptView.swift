import SwiftUI
import Photos

struct PhotoPermissionPromptView: View {
    @StateObject private var photoService = PhotoService.shared
    @State private var showingSettings = false
    let onPermissionGranted: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)
                
                VStack(spacing: 8) {
                    Text("customize with photos")
                        .font(.custom("Helvetica Neue", size: 18))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("add photos from your library to create personalized run card backgrounds.")
                        .font(.custom("Helvetica Neue", size: 15))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            
            VStack(spacing: 12) {
                if photoService.authorizationStatus == .notDetermined {
                    Button(action: requestPermission) {
                        HStack {
                            Image(systemName: "photo.badge.plus")
                            Text("enable photos")
                        }
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                } else if photoService.authorizationStatus == .denied {
                    Button(action: { showingSettings = true }) {
                        HStack {
                            Image(systemName: "gear")
                            Text("Open Settings")
                        }
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    
                    Text("photo access was declined. you can enable it anytime in settings.")
                        .font(.custom("Helvetica Neue", size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                } else if photoService.authorizationStatus == .restricted {
                    VStack(spacing: 8) {
                        Text("Photo Access Restricted")
                            .font(.custom("Helvetica Neue", size: 16))
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        
                        Text("Photo access is restricted on this device. Contact your device administrator for assistance.")
                            .font(.custom("Helvetica Neue", size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                } else if photoService.authorizationStatus == .limited {
                    VStack(spacing: 12) {
                        Text("Limited Photo Access")
                            .font(.custom("Helvetica Neue", size: 16))
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        
                        Text("you can customize with your selected photos, or grant full access for more options.")
                            .font(.custom("Helvetica Neue", size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        Button(action: requestFullAccess) {
                            HStack {
                                Image(systemName: "photo.on.rectangle")
                                Text("Allow Full Access")
                            }
                            .font(.custom("Helvetica Neue", size: 16))
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .padding(.vertical, 20)
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding(.horizontal, 20)
        .sheet(isPresented: $showingSettings) {
            SettingsRedirectView()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Check permission status when app becomes active (user might have changed it in Settings)
            photoService.checkAuthorizationStatus()
            if photoService.authorizationStatus == .authorized || photoService.authorizationStatus == .limited {
                onPermissionGranted()
            }
        }
    }
    
    private func requestPermission() {
        Task {
            let granted = await photoService.requestPhotoLibraryAccess()
            await MainActor.run {
                if granted {
                    onPermissionGranted()
                }
            }
        }
    }
    
    private func requestFullAccess() {
        Task {
            let granted = await photoService.requestPhotoLibraryAccess()
            await MainActor.run {
                if granted {
                    onPermissionGranted()
                }
            }
        }
    }
}

struct SettingsRedirectView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 16) {
                    Image(systemName: "gear.badge")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    VStack(spacing: 8) {
                        Text("enable photo access")
                            .font(.custom("Helvetica Neue", size: 18))
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("customize your run cards with photo backgrounds from your library.")
                            .font(.custom("Helvetica Neue", size: 15))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Steps:")
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            Text("1.")
                                .font(.custom("Helvetica Neue", size: 14))
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                            Text("Tap \"Open Settings\" below")
                                .font(.custom("Helvetica Neue", size: 14))
                                .foregroundColor(.primary)
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Text("2.")
                                .font(.custom("Helvetica Neue", size: 14))
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                            Text("Find and tap \"Run The Tunes\" in the apps list")
                                .font(.custom("Helvetica Neue", size: 14))
                                .foregroundColor(.primary)
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Text("3.")
                                .font(.custom("Helvetica Neue", size: 14))
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                            Text("Tap \"Photos\" and select \"All Photos\"")
                                .font(.custom("Helvetica Neue", size: 14))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(16)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Button(action: openSettings) {
                    HStack {
                        Image(systemName: "gear")
                        Text("Open Settings")
                    }
                    .font(.custom("Helvetica Neue", size: 16))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.orange)
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding(20)
            .navigationTitle("Photo Access")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

#Preview {
    PhotoPermissionPromptView {
        print("Permission granted!")
    }
}
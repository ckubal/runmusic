import SwiftUI

struct SpotifyConnectionPrompt: View {
    let context: SpotifyPromptContext
    let onConnect: () -> Void
    let onDismiss: (() -> Void)?
    @StateObject private var spotifyService = SpotifyService.shared
    
    enum SpotifyPromptContext {
        case albumArt
        case powerSong
        case musicData
        case trackSelection
        case generalMusic
        
        var title: String {
            switch self {
            case .albumArt:
                return "connect for album art"
            case .powerSong:
                return "connect to find power songs"
            case .musicData:
                return "connect for music data"
            case .trackSelection:
                return "connect to select tracks"
            case .generalMusic:
                return "connect spotify for music"
            }
        }
        
        var description: String {
            switch self {
            case .albumArt:
                return "see album covers on your run cards"
            case .powerSong:
                return "discover which songs boost your pace"
            case .musicData:
                return "see what songs powered your runs"
            case .trackSelection:
                return "choose which songs appear on cards"
            case .generalMusic:
                return "unlock all music-powered features"
            }
        }
        
        var icon: String {
            switch self {
            case .albumArt:
                return "photo.on.rectangle"
            case .powerSong:
                return "bolt.fill"
            case .musicData:
                return "music.note"
            case .trackSelection:
                return "music.note.list"
            case .generalMusic:
                return "music.note"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: context.icon)
                    .font(.title2)
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.title)
                        .font(.custom("Helvetica Neue", size: 16))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(context.description)
                        .font(.custom("Helvetica Neue", size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let onDismiss = onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            }
            
            Button {
                onConnect()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                    Text("connect spotify")
                }
                .font(.custom("Helvetica Neue", size: 14))
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [.green, .blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Convenience View Modifiers

struct SpotifyConnectionBanner: View {
    let context: SpotifyConnectionPrompt.SpotifyPromptContext
    @StateObject private var spotifyService = SpotifyService.shared
    @State private var isVisible = true
    
    var body: some View {
        if !spotifyService.isAuthenticated && isVisible {
            SpotifyConnectionPrompt(
                context: context,
                onConnect: {
                    if let authURL = spotifyService.authURL {
                        UIApplication.shared.open(authURL)
                    }
                },
                onDismiss: {
                    withAnimation {
                        isVisible = false
                    }
                }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Usage Examples & Preview

#Preview("Album Art Context") {
    SpotifyConnectionPrompt(
        context: .albumArt,
        onConnect: {
            print("Connect tapped")
        },
        onDismiss: {
            print("Dismiss tapped")
        }
    )
    .padding()
}

#Preview("Power Song Context") {
    SpotifyConnectionPrompt(
        context: .powerSong,
        onConnect: {
            print("Connect tapped")
        },
        onDismiss: nil
    )
    .padding()
}
import SwiftUI

struct InstagramStyleTrackRow: View {
    let track: SpotifyTrack
    let index: Int
    let fontFamily: FontFamily
    let isPowerSong: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            // Show fire emoji for power song, otherwise roman numeral
            if isPowerSong {
                Text("🔥")
                    .font(.system(size: 12))
            } else {
                Text(romanNumeral(for: index).lowercased())
                    .font(fontFamily.customFont(size: 10))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            
            Text("\(track.name.lowercased()) - \(track.artist.lowercased())")
                .font(fontFamily.customFont(size: 10))
                .fontWeight(.medium)
                .foregroundColor(isPowerSong ? Color.orange : .white)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(isPowerSong ? 0.4 : 0.7))
        .cornerRadius(0) // Hard corners for Instagram style
    }
    
    private func romanNumeral(for number: Int) -> String {
        let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        let numerals = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
        
        var num = number
        var result = ""
        
        for (index, value) in values.enumerated() {
            let count = num / value
            if count > 0 {
                result += String(repeating: numerals[index], count: count)
                num %= value
            }
        }
        
        return result
    }
}

#Preview {
    let sampleTrack = SpotifyTrack(
        id: "1",
        name: "Blinding Lights",
        artist: "The Weeknd",
        album: "After Hours",
        playedAt: Date(),
        durationMs: 200000,
        albumImageURL: nil
    )
    
    return VStack(spacing: 8) {
        InstagramStyleTrackRow(track: sampleTrack, index: 1, fontFamily: FontFamily.default, isPowerSong: true)
        InstagramStyleTrackRow(track: sampleTrack, index: 2, fontFamily: FontFamily.default, isPowerSong: false)
        InstagramStyleTrackRow(track: sampleTrack, index: 3, fontFamily: FontFamily.default, isPowerSong: false)
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
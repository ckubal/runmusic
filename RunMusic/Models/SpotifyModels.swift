import Foundation

// MARK: - Recently Played Response

struct SpotifyRecentlyPlayedResponse: Codable {
    let items: [SpotifyPlayHistoryItem]
    let next: String?
    let cursors: SpotifyCursors?
    let limit: Int
    let href: String
}

struct SpotifyPlayHistoryItem: Codable {
    let track: SpotifyTrackInfo
    let playedAt: String
    
    private enum CodingKeys: String, CodingKey {
        case track
        case playedAt = "played_at"
    }
}

struct SpotifyTrackInfo: Codable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum
    let durationMs: Int
    let explicit: Bool
    let externalUrls: SpotifyExternalUrls
    
    private enum CodingKeys: String, CodingKey {
        case id, name, artists, album, explicit
        case durationMs = "duration_ms"
        case externalUrls = "external_urls"
    }
}

struct SpotifyArtist: Codable {
    let id: String
    let name: String
    let type: String
    let uri: String
    let externalUrls: SpotifyExternalUrls
    
    private enum CodingKeys: String, CodingKey {
        case id, name, type, uri
        case externalUrls = "external_urls"
    }
}

struct SpotifyAlbum: Codable {
    let id: String
    let name: String
    let albumType: String
    let artists: [SpotifyArtist]
    let images: [SpotifyImage]
    let releaseDate: String
    let totalTracks: Int
    
    private enum CodingKeys: String, CodingKey {
        case id, name, artists, images
        case albumType = "album_type"
        case releaseDate = "release_date"
        case totalTracks = "total_tracks"
    }
}

struct SpotifyImage: Codable {
    let height: Int?
    let width: Int?
    let url: String
}

struct SpotifyExternalUrls: Codable {
    let spotify: String
}

struct SpotifyCursors: Codable {
    let after: String?
    let before: String?
}

struct SpotifyAuthResponse: Codable {
    let accessToken: String
    let tokenType: String
    let scope: String
    let expiresIn: Int
    let refreshToken: String?
    
    private enum CodingKeys: String, CodingKey {
        case scope
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

struct SpotifyUserProfile: Codable {
    let id: String
    let displayName: String?
    let email: String?
    let images: [SpotifyImage]
    let followers: SpotifyFollowers
    
    private enum CodingKeys: String, CodingKey {
        case id, email, images, followers
        case displayName = "display_name"
    }
}

struct SpotifyFollowers: Codable {
    let total: Int
}

// MARK: - Extended Streaming History Models (for JSON import)

struct SpotifyExtendedStreamingHistoryItem: Codable {
    let ts: Date?
    let username: String?
    let platform: String?
    let msPlayed: Int?
    let connCountry: String?
    let ipAddr: String?  // Changed from ipAddrDecrypted
    let ipAddrDecrypted: String?
    let userAgentDecrypted: String?
    let masterMetadataTrackName: String?
    let masterMetadataAlbumArtistName: String?
    let masterMetadataAlbumAlbumName: String?
    let spotifyTrackUri: String?
    let episodeName: String?
    let episodeShowName: String?
    let spotifyEpisodeUri: String?
    let audiobookTitle: String?
    let audiobookUri: String?
    let audiobookChapterUri: String?
    let audiobookChapterTitle: String?
    let reasonStart: String?
    let reasonEnd: String?
    let shuffle: Bool?
    let skipped: Bool?
    let offline: Bool?
    let offlineTimestamp: Int?  // Changed to Int
    let incognitoMode: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case ts, username, platform, shuffle, skipped, offline
        case msPlayed = "ms_played"
        case connCountry = "conn_country"
        case ipAddr = "ip_addr"
        case ipAddrDecrypted = "ip_addr_decrypted"
        case userAgentDecrypted = "user_agent_decrypted"
        case masterMetadataTrackName = "master_metadata_track_name"
        case masterMetadataAlbumArtistName = "master_metadata_album_artist_name"
        case masterMetadataAlbumAlbumName = "master_metadata_album_album_name"
        case spotifyTrackUri = "spotify_track_uri"
        case episodeName = "episode_name"
        case episodeShowName = "episode_show_name"
        case spotifyEpisodeUri = "spotify_episode_uri"
        case audiobookTitle = "audiobook_title"
        case audiobookUri = "audiobook_uri"
        case audiobookChapterUri = "audiobook_chapter_uri"
        case audiobookChapterTitle = "audiobook_chapter_title"
        case reasonStart = "reason_start"
        case reasonEnd = "reason_end"
        case offlineTimestamp = "offline_timestamp"
        case incognitoMode = "incognito_mode"
    }
}

// MARK: - Top Tracks Response

struct SpotifyTopTracksResponse: Codable {
    let items: [SpotifyTopTrackItem]
    let total: Int
    let limit: Int
    let offset: Int
    let href: String
    let previous: String?
    let next: String?
}

struct SpotifyTopTrackItem: Codable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum?
    let durationMs: Int
    let explicit: Bool
    let popularity: Int
    let previewUrl: String?
    let externalUrls: SpotifyExternalUrls
    
    private enum CodingKeys: String, CodingKey {
        case id, name, artists, album, explicit, popularity
        case durationMs = "duration_ms"
        case previewUrl = "preview_url"
        case externalUrls = "external_urls"
    }
}

// MARK: - Currently Playing Response

struct SpotifyCurrentlyPlayingResponse: Codable {
    let device: SpotifyDevice?
    let shuffleState: Bool
    let repeatState: String
    let timestamp: Int64
    let context: SpotifyContext?
    let progressMs: Int?
    let item: SpotifyCurrentTrack?
    let currentlyPlayingType: String
    let actions: SpotifyActions?
    let isPlaying: Bool
    
    private enum CodingKeys: String, CodingKey {
        case device, context, item, actions
        case shuffleState = "shuffle_state"
        case repeatState = "repeat_state"
        case timestamp
        case progressMs = "progress_ms"
        case currentlyPlayingType = "currently_playing_type"
        case isPlaying = "is_playing"
    }
}

struct SpotifyDevice: Codable {
    let id: String?
    let isActive: Bool
    let isPrivateSession: Bool
    let isRestricted: Bool
    let name: String
    let type: String
    let volumePercent: Int?
    
    private enum CodingKeys: String, CodingKey {
        case id, name, type
        case isActive = "is_active"
        case isPrivateSession = "is_private_session"
        case isRestricted = "is_restricted"
        case volumePercent = "volume_percent"
    }
}

struct SpotifyContext: Codable {
    let type: String
    let href: String?
    let externalUrls: SpotifyExternalUrls?
    let uri: String
    
    private enum CodingKeys: String, CodingKey {
        case type, href, uri
        case externalUrls = "external_urls"
    }
}

struct SpotifyCurrentTrack: Codable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum?
    let durationMs: Int
    let explicit: Bool
    let popularity: Int?
    let previewUrl: String?
    let externalUrls: SpotifyExternalUrls
    
    private enum CodingKeys: String, CodingKey {
        case id, name, artists, album, explicit, popularity
        case durationMs = "duration_ms"
        case previewUrl = "preview_url"
        case externalUrls = "external_urls"
    }
}

struct SpotifyActions: Codable {
    let interrupting_playback: Bool?
    let pausing: Bool?
    let resuming: Bool?
    let seeking: Bool?
    let skipping_next: Bool?
    let skipping_prev: Bool?
    let toggling_repeat_context: Bool?
    let toggling_shuffle: Bool?
    let toggling_repeat_track: Bool?
    let transferring_playback: Bool?
}
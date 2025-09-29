# RunMusic

RunMusic connects your Strava running activities with your Spotify music listening history to create beautiful, shareable cards that show what music you listened to during your runs.

## Features

- **Strava Integration**: Authenticate with Strava to fetch your running activities
- **Route Visualization**: Display artistic GPS route sketches without revealing exact locations
- **Run History**: Browse all your runs with thumbnail route previews
- **Shareable Cards**: Generate Instagram Story-formatted cards showing:
  - Artistic route sketch
  - Run statistics (distance, time, pace)
  - City/neighborhood (editable for privacy)
  - Song list with Roman numeral indicators on the route
- **Spotify Integration** (Optional): Match songs played during runs
- **Privacy Controls**: Hide/show different elements, edit location names

## Setup

### Prerequisites

1. Xcode 15.0 or later
2. iOS 16.0 or later
3. Strava Developer Account
4. Firebase Project (for backend)
5. Spotify Developer Account (optional)

### Strava API Setup

1. Go to [Strava Developers](https://developers.strava.com/)
2. Create a new app
3. Set Authorization Callback Domain to: `runmusic://strava-auth`
4. Update `StravaService.swift` with your:
   - `clientID`
   - `clientSecret`

### Firebase Setup

1. Create a new Firebase project
2. Download `GoogleService-Info.plist`
3. Add to your Xcode project
4. Enable Authentication and Firestore

### Installation

1. Clone the repository
2. Open `RunMusic.xcodeproj` in Xcode
3. Add Firebase dependencies via Swift Package Manager:
   - `https://github.com/firebase/firebase-ios-sdk`
4. Configure your API keys
5. Build and run

## Architecture

- **Models**: Data structures for runs, Strava/Spotify responses
- **Services**: API clients for Strava and Spotify
- **Views**: SwiftUI components for UI
- **Utils**: Helper functions for data conversion and GPS processing

## API Endpoints Used

### Strava
- `/oauth/authorize` - Authentication
- `/oauth/token` - Token exchange
- `/athlete/activities` - Fetch activities
- `/activities/{id}` - Detailed activity
- `/activities/{id}/streams` - GPS coordinates

### Spotify (Optional)
- `/authorize` - Authentication  
- `/api/token` - Token exchange
- `/me/player/recently-played` - Recent tracks

## Privacy & Security

- Location data is never stored with full precision
- Route sketches are artistic interpretations without map backgrounds
- Users can edit or hide city/neighborhood names
- All data stays local until explicitly shared

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see LICENSE file for details
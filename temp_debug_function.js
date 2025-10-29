const functions = require('firebase-functions');
const admin = require('firebase-admin');

// This would be added to the existing Cloud Functions to debug the Spotify issue
const debugSpotifyData = functions.https.onRequest(async (req, res) => {
  try {
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'GET');
    
    const userId = '98ziMzBOZqRQYIcJS9nlQaJqu9m1';
    const db = admin.firestore();
    
    console.log('Querying Spotify listening history for user:', userId);
    
    // Get total count first (no limit)
    const totalSnapshot = await db.collection('spotifyListeningHistory')
      .where('userId', '==', userId)
      .get();
    
    console.log('Total documents found:', totalSnapshot.size);
    
    if (totalSnapshot.size > 0) {
      const docs = totalSnapshot.docs;
      
      // Sort by playedAt to get date range
      const sortedDocs = docs.sort((a, b) => {
        const aTime = a.data().playedAt;
        const bTime = b.data().playedAt;
        return aTime - bTime;
      });
      
      const firstDoc = sortedDocs[0].data();
      const lastDoc = sortedDocs[sortedDocs.length - 1].data();
      
      // Get recent tracks (within last 7 days)
      const sevenDaysAgo = Date.now() - (7 * 24 * 60 * 60 * 1000);
      const recentTracks = docs.filter(doc => doc.data().playedAt > sevenDaysAgo);
      
      // Get recent tracks (within last 24 hours)
      const oneDayAgo = Date.now() - (24 * 60 * 60 * 1000);
      const todayTracks = docs.filter(doc => doc.data().playedAt > oneDayAgo);
      
      const result = {
        success: true,
        totalTracks: totalSnapshot.size,
        dateRange: {
          earliest: new Date(firstDoc.playedAt).toISOString(),
          latest: new Date(lastDoc.playedAt).toISOString()
        },
        recentActivity: {
          last7Days: recentTracks.length,
          last24Hours: todayTracks.length
        },
        firstTrack: {
          name: firstDoc.trackName,
          artist: firstDoc.artistName,
          playedAt: new Date(firstDoc.playedAt).toISOString()
        },
        lastTrack: {
          name: lastDoc.trackName,
          artist: lastDoc.artistName,
          playedAt: new Date(lastDoc.playedAt).toISOString()
        },
        sampleTracks: sortedDocs.slice(-5).map(doc => {
          const data = doc.data();
          return {
            name: data.trackName,
            artist: data.artistName,
            playedAt: new Date(data.playedAt).toISOString()
          };
        })
      };
      
      res.status(200).json(result);
    } else {
      res.status(200).json({
        success: false,
        message: 'No documents found for this user',
        totalTracks: 0
      });
    }
    
  } catch (error) {
    console.error('Error querying data:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

module.exports = { debugSpotifyData };
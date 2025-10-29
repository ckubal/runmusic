const admin = require('./functions/node_modules/firebase-admin');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'runmusic-be'
});

const db = admin.firestore();

async function querySpotifyData() {
  const userId = '98ziMzBOZqRQYIcJS9nlQaJqu9m1';
  
  try {
    console.log('Querying Spotify listening history for user:', userId);
    
    // Query the spotifyListeningHistory collection for this user
    const snapshot = await db.collection('spotifyListeningHistory')
      .where('userId', '==', userId)
      .orderBy('playedAt', 'asc')
      .get();
    
    console.log('Total documents found:', snapshot.size);
    
    if (snapshot.size > 0) {
      const docs = snapshot.docs;
      
      // Get date range
      const firstDoc = docs[0].data();
      const lastDoc = docs[docs.length - 1].data();
      
      console.log('Date range:');
      console.log('Earliest track:', new Date(firstDoc.playedAt).toISOString());
      console.log('Latest track:', new Date(lastDoc.playedAt).toISOString());
      
      // Show first few documents
      console.log('\nFirst 3 tracks:');
      docs.slice(0, 3).forEach((doc, index) => {
        const data = doc.data();
        console.log(`${index + 1}. "${data.trackName}" by ${data.artistName} - ${new Date(data.playedAt).toISOString()}`);
      });
      
      // Show last few documents
      console.log('\nLast 3 tracks:');
      docs.slice(-3).forEach((doc, index) => {
        const data = doc.data();
        console.log(`${docs.length - 2 + index}. "${data.trackName}" by ${data.artistName} - ${new Date(data.playedAt).toISOString()}`);
      });
      
      // Check for recent tracks (within last 24 hours)
      const oneDayAgo = Date.now() - (24 * 60 * 60 * 1000);
      const recentTracks = docs.filter(doc => doc.data().playedAt > oneDayAgo);
      console.log('\nTracks from last 24 hours:', recentTracks.length);
      
      // Check for tracks from last week
      const oneWeekAgo = Date.now() - (7 * 24 * 60 * 60 * 1000);
      const weeklyTracks = docs.filter(doc => doc.data().playedAt > oneWeekAgo);
      console.log('Tracks from last 7 days:', weeklyTracks.length);
      
    } else {
      console.log('No documents found for this user');
    }
    
  } catch (error) {
    console.error('Error querying data:', error);
  }
  
  process.exit(0);
}

querySpotifyData();
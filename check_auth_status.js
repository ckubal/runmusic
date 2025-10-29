const admin = require('./functions/node_modules/firebase-admin');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'runmusic-be'
});

const db = admin.firestore();

async function checkAuthenticationStatus() {
  const userId = '98ziMzBOZqRQYIcJS9nlQaJqu9m1';
  
  console.log('🔍 CHECKING POST-AUTHENTICATION STATUS');
  console.log('=' * 50);
  console.log(`User ID: ${userId}`);
  console.log(`Check Time: ${new Date().toISOString()}`);
  console.log();
  
  try {
    // 1. Check if Spotify tokens exist
    console.log('📊 CHECKING SPOTIFY TOKENS...');
    const spotifyTokenDoc = await db.collection('users')
      .doc(userId)
      .collection('tokens')
      .doc('spotify')
      .get();
    
    if (spotifyTokenDoc.exists) {
      const tokenData = spotifyTokenDoc.data();
      console.log('✅ Spotify tokens found!');
      console.log('Token components:', {
        hasEncryptedData: !!tokenData.encryptedData,
        hasIV: !!tokenData.iv,
        hasTag: !!tokenData.tag,
        updatedAt: tokenData.updatedAt ? new Date(tokenData.updatedAt).toISOString() : 'Not set'
      });
    } else {
      console.log('❌ No Spotify tokens found');
    }
    
    // 2. Check recent Spotify tracks count
    console.log('\n📊 CHECKING RECENT SPOTIFY DATA...');
    const recentTracksSnapshot = await db.collection('spotifyListeningHistory')
      .where('userId', '==', userId)
      .orderBy('syncedAt', 'desc')
      .limit(5)
      .get();
    
    console.log(`Recent tracks: ${recentTracksSnapshot.size}`);
    
    if (recentTracksSnapshot.size > 0) {
      console.log('Most recent tracks:');
      recentTracksSnapshot.docs.forEach((doc, index) => {
        const track = doc.data();
        const syncTime = track.syncedAt ? new Date(track.syncedAt).toISOString() : 'Unknown';
        console.log(`  ${index + 1}. "${track.trackName}" by ${track.artistName} (synced: ${syncTime})`);
      });
    }
    
    // 3. Check Firebase user info
    console.log('\n👤 CHECKING FIREBASE USER...');
    const userDoc = await db.collection('users').doc(userId).get();
    
    if (userDoc.exists) {
      const userData = userDoc.data();
      console.log('✅ User document exists');
      console.log('User info:', {
        displayName: userData.displayName,
        email: userData.email,
        hasStravaUserId: !!userData.stravaUserId
      });
    } else {
      console.log('❌ No user document found');
    }
    
    // 4. Summary
    console.log('\n📋 AUTHENTICATION SUMMARY:');
    const hasSpotifyTokens = spotifyTokenDoc.exists;
    const hasRecentTracks = recentTracksSnapshot.size > 0;
    const hasUserDoc = userDoc.exists;
    
    console.log(`Spotify Tokens: ${hasSpotifyTokens ? '✅' : '❌'}`);
    console.log(`Recent Tracks: ${hasRecentTracks ? '✅' : '❌'}`);
    console.log(`User Profile: ${hasUserDoc ? '✅' : '❌'}`);
    
    if (hasSpotifyTokens) {
      console.log('\n🎉 READY FOR SYNC: Your Spotify re-authentication looks successful!');
      console.log('The continuous sync will pick up your tokens in the next run.');
    } else {
      console.log('\n⚠️  TOKENS MISSING: Spotify re-authentication may not have completed properly.');
    }
    
  } catch (error) {
    console.error('❌ Error during authentication check:', error);
  }
  
  process.exit(0);
}

checkAuthenticationStatus();
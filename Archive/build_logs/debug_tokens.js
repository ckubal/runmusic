const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./functions/service-account-key.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function debugUserTokens() {
  console.log('🔍 DEBUG: Checking Spotify tokens for ckubal@gmail.com...');
  
  try {
    // Step 1: Find user ID for ckubal@gmail.com
    const usersQuery = await db.collection('users')
      .where('email', '==', 'ckubal@gmail.com')
      .get();
    
    if (usersQuery.empty) {
      console.log('❌ No user found with email ckubal@gmail.com');
      return;
    }
    
    const userDoc = usersQuery.docs[0];
    const userId = userDoc.id;
    const userData = userDoc.data();
    
    console.log(`✅ Found user: ${userId}`);
    console.log(`   - Display Name: ${userData.displayName || 'N/A'}`);
    console.log(`   - Created At: ${userData.createdAt?.toDate() || 'N/A'}`);
    console.log(`   - Strava User ID: ${userData.stravaUserId || 'N/A'}`);
    
    // Step 2: Check Spotify tokens
    const spotifyTokenDoc = await db.collection('users')
      .doc(userId)
      .collection('tokens')
      .doc('spotify')
      .get();
    
    if (!spotifyTokenDoc.exists) {
      console.log('❌ NO SPOTIFY TOKENS FOUND');
      console.log('   - Path checked: users/' + userId + '/tokens/spotify');
      console.log('   - This explains why continuous sync finds 0 users!');
    } else {
      const tokenData = spotifyTokenDoc.data();
      console.log('✅ Spotify tokens found:');
      console.log(`   - Created At: ${tokenData.createdAt?.toDate()}`);
      console.log(`   - Expires At: ${tokenData.expiresAt?.toDate()}`);
      console.log(`   - Is Expired: ${tokenData.expiresAt ? tokenData.expiresAt.toDate() < new Date() : 'Unknown'}`);
      console.log(`   - Has Encrypted Data: ${!!tokenData.encryptedData}`);
    }
    
    // Step 3: Check sync settings
    const syncSettingsDoc = await db.collection('userSyncSettings')
      .doc(userId)
      .get();
    
    if (syncSettingsDoc.exists) {
      const syncData = syncSettingsDoc.data();
      console.log('✅ Sync settings found:');
      console.log(`   - Background Sync Enabled: ${syncData.isBackgroundSyncEnabled}`);
      console.log(`   - Last Sync: ${syncData.lastSyncTime?.toDate() || 'Never'}`);
    } else {
      console.log('❌ No sync settings found');
    }
    
    // Step 4: Check global collection for this user
    const globalTracksQuery = await db.collection('spotifyListeningHistory')
      .where('userId', '==', userId)
      .orderBy('playedAt', 'desc')
      .limit(10)
      .get();
    
    console.log(`📊 Global collection has ${globalTracksQuery.size} tracks for this user`);
    
    if (!globalTracksQuery.empty) {
      const latestTrack = globalTracksQuery.docs[0].data();
      console.log(`   - Latest track: "${latestTrack.trackName}" by ${latestTrack.artistName}`);
      console.log(`   - Played at: ${latestTrack.playedAt?.toDate()}`);
      console.log(`   - Source: ${latestTrack.source || 'Unknown'}`);
    }
    
    // Step 5: Check total global collection size
    const totalTracksSnapshot = await db.collection('spotifyListeningHistory').limit(1).get();
    console.log(`📊 Total documents in global collection: Limited query returned ${totalTracksSnapshot.size}`);
    
  } catch (error) {
    console.error('❌ ERROR:', error);
  }
  
  process.exit(0);
}

debugUserTokens();
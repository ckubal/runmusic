const admin = require('./functions/node_modules/firebase-admin');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'runmusic-be'
});

const db = admin.firestore();

async function debugSpotifyContinuity() {
  const userId = '98ziMzBOZqRQYIcJS9nlQaJqu9m1';
  
  console.log('🔍 SPOTIFY DATA CONTINUITY INVESTIGATION');
  console.log('=' * 50);
  console.log(`User ID: ${userId}`);
  console.log(`Investigation Date: ${new Date().toISOString()}`);
  console.log();
  
  try {
    // 1. Query all Spotify listening history for this user
    console.log('📊 QUERYING SPOTIFY LISTENING HISTORY...');
    const snapshot = await db.collection('spotifyListeningHistory')
      .where('userId', '==', userId)
      .orderBy('playedAt', 'asc')
      .get();
    
    console.log(`Total tracks found: ${snapshot.size}`);
    
    if (snapshot.size === 0) {
      console.log('❌ NO TRACKS FOUND - This indicates a major sync failure');
      return;
    }
    
    // 2. Analyze the date range and gaps
    const docs = snapshot.docs;
    const tracks = docs.map(doc => {
      const data = doc.data();
      return {
        id: doc.id,
        trackName: data.trackName,
        artistName: data.artistName,
        playedAt: new Date(data.playedAt),
        playedAtMs: data.playedAt
      };
    });
    
    // Sort by played at time
    tracks.sort((a, b) => a.playedAt - b.playedAt);
    
    const earliestTrack = tracks[0];
    const latestTrack = tracks[tracks.length - 1];
    
    console.log();
    console.log('📅 DATE RANGE ANALYSIS:');
    console.log(`Earliest track: ${earliestTrack.playedAt.toISOString()}`);
    console.log(`Latest track: ${latestTrack.playedAt.toISOString()}`);
    console.log();
    
    // 3. Check for gaps in the last 60 days
    const sixtyDaysAgo = new Date();
    sixtyDaysAgo.setDate(sixtyDaysAgo.getDate() - 60);
    
    const recentTracks = tracks.filter(track => track.playedAt >= sixtyDaysAgo);
    console.log(`📊 Tracks in last 60 days: ${recentTracks.length}`);
    
    // 4. Analyze daily distribution
    const tracksByDate = {};
    recentTracks.forEach(track => {
      const dateKey = track.playedAt.toISOString().split('T')[0]; // YYYY-MM-DD
      if (!tracksByDate[dateKey]) {
        tracksByDate[dateKey] = [];
      }
      tracksByDate[dateKey].push(track);
    });
    
    console.log();
    console.log('📊 DAILY TRACK DISTRIBUTION (Last 60 days):');
    
    // Find gaps (days with 0 tracks)
    const gaps = [];
    for (let i = 0; i < 60; i++) {
      const checkDate = new Date();
      checkDate.setDate(checkDate.getDate() - i);
      const dateKey = checkDate.toISOString().split('T')[0];
      
      const trackCount = tracksByDate[dateKey]?.length || 0;
      
      if (i < 14) { // Show last 14 days in detail
        console.log(`${dateKey}: ${trackCount} tracks`);
      }
      
      if (trackCount === 0) {
        gaps.push({
          date: dateKey,
          dayOfWeek: checkDate.toLocaleDateString('en-US', { weekday: 'short' })
        });
      }
    }
    
    console.log();
    console.log('❌ GAPS DETECTED (Days with 0 tracks in last 60 days):');
    if (gaps.length === 0) {
      console.log('✅ No gaps found! Sync appears to be working consistently.');
    } else {
      console.log(`Found ${gaps.length} days with no tracks:`);
      gaps.forEach(gap => {
        console.log(`   ${gap.date} (${gap.dayOfWeek})`);
      });
    }
    
    // 5. Check specific dates mentioned in the issue
    console.log();
    console.log('🎯 SPECIFIC DATE CHECKS:');
    
    const checkDates = [
      '2025-10-04', // User mentioned listening on this date
      '2025-10-11', // Last track in API response
      '2025-10-12',
      '2025-10-13', // Today
      '2025-09-28', // When sync was supposedly fixed
    ];
    
    checkDates.forEach(dateKey => {
      const trackCount = tracksByDate[dateKey]?.length || 0;
      console.log(`${dateKey}: ${trackCount} tracks`);
      
      if (trackCount > 0 && tracksByDate[dateKey]) {
        // Show first few tracks for that date
        const dayTracks = tracksByDate[dateKey].slice(0, 3);
        dayTracks.forEach(track => {
          console.log(`   - "${track.trackName}" by ${track.artistName} at ${track.playedAt.toLocaleTimeString()}`);
        });
      }
    });
    
    // 6. Check for recent sync activity
    console.log();
    console.log('🔄 RECENT SYNC ACTIVITY:');
    
    const last24Hours = new Date();
    last24Hours.setHours(last24Hours.getHours() - 24);
    
    const veryRecentTracks = tracks.filter(track => track.playedAt >= last24Hours);
    console.log(`Tracks added in last 24 hours: ${veryRecentTracks.length}`);
    
    const last7Days = new Date();
    last7Days.setDate(last7Days.getDate() - 7);
    
    const weeklyTracks = tracks.filter(track => track.playedAt >= last7Days);
    console.log(`Tracks added in last 7 days: ${weeklyTracks.length}`);
    
    // 7. Show most recent tracks to understand current sync state
    console.log();
    console.log('🎵 MOST RECENT TRACKS (Last 10):');
    const lastTenTracks = tracks.slice(-10);
    lastTenTracks.forEach((track, index) => {
      console.log(`${lastTenTracks.length - index}. "${track.trackName}" by ${track.artistName}`);
      console.log(`    Played: ${track.playedAt.toISOString()}`);
    });
    
    // 8. Summary and conclusions
    console.log();
    console.log('📝 SUMMARY & ANALYSIS:');
    console.log(`Total tracks: ${tracks.length}`);
    console.log(`Date range: ${(latestTrack.playedAt - earliestTrack.playedAt) / (1000 * 60 * 60 * 24)} days`);
    console.log(`Gaps in last 60 days: ${gaps.length}`);
    console.log(`Average tracks per day (non-zero days): ${Math.round(recentTracks.length / (60 - gaps.length))}`);
    
    if (gaps.length > 10) {
      console.log('⚠️  ISSUE DETECTED: Too many gaps suggest sync failures');
    }
    
    if (veryRecentTracks.length === 0) {
      console.log('🚨 CRITICAL: No tracks in last 24 hours - sync may be broken');
    }
    
    if (latestTrack.playedAt < last7Days) {
      console.log('🚨 CRITICAL: No tracks in last 7 days - sync definitely broken');
    }
    
  } catch (error) {
    console.error('❌ Error during investigation:', error);
  }
  
  process.exit(0);
}

debugSpotifyContinuity();
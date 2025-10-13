/**
 * RunMusic Firebase Cloud Functions
 * 
 * Handles authentication cross-provider conflict detection and user management
 * for the RunMusic iOS application.
 */

import { initializeApp } from 'firebase-admin/app';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onCall } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';
import * as crypto from 'crypto';

// Initialize Firebase Admin
initializeApp();
const db = getFirestore();

// Export authentication functions for Apple Sign-In implementation
export {
  checkIfGoogleUserExists,
  checkIfAppleUserExists,
  deleteUserAccount
} from './authFunctions';

/**
 * Debug endpoint to check user's current token status
 */
export const debugUserTokens = onCall(async (request) => {
  try {
    const userId = '98ziMzBOZqRQYIcJS9nlQaJqu9m1'; // Your user ID
    
    logger.info(`Checking token status for user: ${userId}`);
    
    // Check if Spotify tokens exist
    const spotifyTokenDoc = await db.collection('users')
      .doc(userId)
      .collection('tokens')
      .doc('spotify')
      .get();
    
    const hasSpotifyTokens = spotifyTokenDoc.exists;
    let tokenInfo = { exists: false };
    
    if (hasSpotifyTokens) {
      const tokenData = spotifyTokenDoc.data()!;
      tokenInfo = {
        exists: true,
        hasEncryptedData: !!tokenData.encryptedData,
        hasIV: !!tokenData.iv,
        hasTag: !!tokenData.tag,
        updatedAt: tokenData.updatedAt || null
      };
    }
    
    // Check recent tracks
    const recentTracksSnapshot = await db.collection('spotifyListeningHistory')
      .where('userId', '==', userId)
      .orderBy('syncedAt', 'desc')
      .limit(3)
      .get();
    
    const recentTracks = recentTracksSnapshot.docs.map(doc => {
      const track = doc.data();
      return {
        name: track.trackName,
        artist: track.artistName,
        syncedAt: track.syncedAt ? new Date(track.syncedAt).toISOString() : null
      };
    });
    
    return {
      success: true,
      timestamp: new Date().toISOString(),
      spotify: tokenInfo,
      recentTracksCount: recentTracksSnapshot.size,
      recentTracks: recentTracks,
      message: hasSpotifyTokens ? 'Spotify tokens found - ready for sync!' : 'No Spotify tokens - need re-authentication'
    };
    
  } catch (error) {
    logger.error('Debug token check failed:', error);
    return {
      success: false,
      error: error.message,
      timestamp: new Date().toISOString()
    };
  }
});

// Spotify API configuration from Firebase config
import { defineSecret } from 'firebase-functions/params';

// Use Firebase functions config (will migrate to environment variables later)
// For now, using the legacy functions.config() which works with existing deployment
const getSpotifyCredentials = () => {
  // This will be populated at runtime from Firebase config
  return {
    clientId: process.env.SPOTIFY_CLIENT_ID || 'c38b1724640d4af6b13aec892cf01a2c',
    clientSecret: process.env.SPOTIFY_CLIENT_SECRET || '2e15a2c6cff24158baf48a68ba769fa4'
  };
};

/**
 * Continuous Spotify Sync - Runs every 45 minutes
 * Syncs Spotify listening history for all authenticated users
 */
export const continuousSpotifySync = onSchedule('every 45 minutes', async (event) => {
  logger.info('Starting continuous Spotify sync (every 45 minutes)...');
  
  try {
    // Find all users with Spotify tokens
    const usersSnapshot = await db.collection('users').get();
    const usersWithSpotifyTokens: string[] = [];
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      
      // Check if user has Spotify tokens
      const spotifyTokenDoc = await db.collection('users')
        .doc(userId)
        .collection('tokens')
        .doc('spotify')
        .get();
      
      if (spotifyTokenDoc.exists) {
        usersWithSpotifyTokens.push(userId);
      }
    }
    
    logger.info(`Found ${usersWithSpotifyTokens.length} users with Spotify tokens for continuous sync`);
    
    let successfulSyncs = 0;
    let failedSyncs = 0;
    let totalTracks = 0;
    
    // Process each user
    for (const userId of usersWithSpotifyTokens) {
      try {
        logger.info(`Starting backup sync for user: ${userId}`);
        const trackCount = await syncUserSpotifyHistory(userId);
        totalTracks += trackCount;
        successfulSyncs++;
        logger.info(`Synced ${trackCount} tracks for user ${userId}`);
      } catch (error) {
        logger.error(`Failed to sync user ${userId}:`, error);
        failedSyncs++;
      }
    }
    
    logger.info(`Continuous sync completed. Users: ${successfulSyncs} successful, ${failedSyncs} failed. Total tracks: ${totalTracks}`);
    
  } catch (error) {
    logger.error('Continuous sync error:', error);
    throw error;
  }
});

/**
 * Manual trigger for continuous sync - for testing and manual recovery
 */
export const triggerContinuousSync = onCall(async (request) => {
  logger.info('Manual continuous sync triggered');
  
  try {
    // Call the same logic as the scheduled function
    await continuousSpotifySync.schedule('manual-trigger');
    return { success: true, message: 'Sync triggered successfully' };
  } catch (error) {
    logger.error('Manual sync trigger failed:', error);
    return { success: false, error: error.message };
  }
});

/**
 * Sync Spotify history for a single user
 * Enhanced with robust token refresh and comprehensive error handling
 */
async function syncUserSpotifyHistory(userId: string): Promise<number> {
  let trackCount = 0;
  
  try {
    // Get user's Spotify tokens
    const tokenDoc = await db.collection('users')
      .doc(userId)
      .collection('tokens')
      .doc('spotify')
      .get();
    
    if (!tokenDoc.exists) {
      logger.warn(`No Spotify tokens found for user ${userId}`);
      return 0;
    }
    
    const tokenData = tokenDoc.data()!;
    
    // Decrypt tokens (this function should match the iOS app implementation)
    const decryptedTokens = await decryptSpotifyTokens(tokenData, userId);
    
    if (!decryptedTokens) {
      logger.warn(`Failed to decrypt Spotify tokens for user ${userId}`);
      return 0;
    }
    
    logger.info(`Successfully decrypted tokens - hasRefreshToken: ${!!decryptedTokens.refreshToken}`);
    
    // Check if access token is expired and refresh if needed
    let accessToken = decryptedTokens.accessToken;
    
    if (isTokenExpired(decryptedTokens.expiresAt)) {
      logger.info(`Decrypted access token expired for user ${userId}, refreshing...`);
      
      if (!decryptedTokens.refreshToken) {
        logger.warn(`No refresh token available for user ${userId} - user needs to re-authenticate with Spotify`);
        
        // Clear invalid tokens to prevent future attempts
        await clearInvalidSpotifyTokens(userId);
        logger.info(`Token was stored without refresh token. User must re-connect Spotify in the app.`);
        return 0;
      }
      
      // Refresh the access token
      const refreshedTokens = await refreshSpotifyAccessToken(decryptedTokens.refreshToken, userId);
      
      if (!refreshedTokens) {
        logger.warn(`Failed to refresh Spotify token for user ${userId} - clearing tokens`);
        await clearInvalidSpotifyTokens(userId);
        return 0;
      }
      
      accessToken = refreshedTokens.accessToken;
      
      // Store the new tokens
      await storeRefreshedTokens(userId, refreshedTokens);
    }
    
    // Get the last sync time
    const lastSyncTime = await getLastSyncTime(userId);
    logger.info(`Last sync time for user ${userId}: ${lastSyncTime.toISOString()}`);
    
    // Fetch recent tracks from Spotify
    const tracks = await fetchSpotifyRecentTracks(accessToken, lastSyncTime);
    
    if (tracks.length > 0) {
      // Store tracks in the unified collection
      await storeSpotifyTracks(userId, tracks);
      trackCount = tracks.length;
      
      // Update last sync time
      await updateLastSyncTime(userId);
      
      logger.info(`Successfully synced ${trackCount} new tracks for user ${userId}`);
    } else {
      logger.info(`No new tracks found for user ${userId} since ${lastSyncTime.toISOString()}`);
    }
    
  } catch (error) {
    logger.error(`Error syncing Spotify history for user ${userId}:`, error);
    throw error;
  }
  
  return trackCount;
}

/**
 * Fetch recent tracks from Spotify API
 * Fixed to only use 'after' parameter to avoid 400 errors
 */
async function fetchSpotifyRecentTracks(accessToken: string, lastSyncTime: Date): Promise<any[]> {
  try {
    // CRITICAL FIX: Only use 'after' parameter, NOT 'before' 
    // This was the root cause of the sync failures from August 23, 2025
    const params = new URLSearchParams({
      limit: '50',
      after: lastSyncTime.getTime().toString()
      // REMOVED: before parameter (this was causing 400 errors)
    });
    
    const response = await fetch(`https://api.spotify.com/v1/me/player/recently-played?${params}`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      }
    });
    
    logger.info(`Spotify API response status: ${response.status}`);
    
    if (!response.ok) {
      if (response.status === 401) {
        throw new Error('SPOTIFY_TOKEN_EXPIRED');
      } else if (response.status === 400) {
        const errorText = await response.text();
        logger.error(`Spotify API 400 error: ${errorText}`);
        throw new Error(`SPOTIFY_API_ERROR: ${errorText}`);
      }
      throw new Error(`Spotify API error: ${response.status}`);
    }
    
    const data = await response.json();
    const tracks = data.items || [];
    
    logger.info(`Fetched ${tracks.length} tracks from Spotify API`);
    
    return tracks;
    
  } catch (error) {
    logger.error('Error fetching Spotify tracks:', error);
    throw error;
  }
}

/**
 * Refresh Spotify access token using refresh token
 */
async function refreshSpotifyAccessToken(refreshToken: string, userId: string): Promise<any | null> {
  try {
    const credentials = getSpotifyCredentials();
    const authHeader = Buffer.from(`${credentials.clientId}:${credentials.clientSecret}`).toString('base64');
    
    const response = await fetch('https://accounts.spotify.com/api/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': `Basic ${authHeader}`
      },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: refreshToken
      })
    });
    
    if (!response.ok) {
      const errorText = await response.text();
      logger.error(`Failed to refresh Spotify token for user ${userId}: ${response.status} - ${errorText}`);
      return null;
    }
    
    const tokenData = await response.json();
    
    logger.info(`Successfully refreshed Spotify token for user ${userId}`);
    
    return {
      accessToken: tokenData.access_token,
      refreshToken: tokenData.refresh_token || refreshToken, // Keep old refresh token if new one not provided
      expiresAt: Date.now() + (tokenData.expires_in * 1000)
    };
    
  } catch (error) {
    logger.error(`Error refreshing Spotify token for user ${userId}:`, error);
    return null;
  }
}

/**
 * Helper functions - these would need to be implemented based on the iOS app's encryption logic
 */

async function decryptSpotifyTokens(tokenData: any, userId: string): Promise<any | null> {
  try {
    logger.info(`Decrypting Spotify tokens for user ${userId}`);
    
    // Extract encrypted token data from Firestore format
    const encryptedData = tokenData.encryptedData;
    const iv = tokenData.iv;
    const tag = tokenData.tag;
    
    if (!encryptedData || !iv || !tag) {
      logger.error('Missing encryption components:', { encryptedData: !!encryptedData, iv: !!iv, tag: !!tag });
      return null;
    }
    
    // Generate key from userId using SHA256 (matching iOS app)
    const keyHash = crypto.createHash('sha256').update(userId).digest();
    
    // Decode Base64 components
    const ciphertext = Buffer.from(encryptedData, 'base64');
    const nonce = Buffer.from(iv, 'base64'); 
    const authTag = Buffer.from(tag, 'base64');
    
    // Create AES-256-GCM decipher using the proper Node.js API
    const algorithm = 'aes-256-gcm';
    
    // Use createDecipheriv with explicit key and IV (nonce) for GCM
    const decipher = crypto.createDecipheriv(algorithm, keyHash, nonce);
    
    let decrypted: string;
    try {
      // Set the authentication tag (required for GCM mode verification)
      (decipher as any).setAuthTag(authTag);
      
      // Decrypt the ciphertext
      let decryptedBuffer = decipher.update(ciphertext);
      const finalBuffer = decipher.final();
      
      // Combine the buffers and convert to string
      const fullDecrypted = Buffer.concat([decryptedBuffer, finalBuffer]);
      decrypted = fullDecrypted.toString('utf8');
      
      logger.info('Successfully decrypted token data using AES-256-GCM');
      
    } catch (decryptError) {
      logger.error('GCM decryption failed:', decryptError);
      
      // For debugging, let's log what we're working with
      logger.info('Debug token decryption details:', {
        userIdLength: userId.length,
        keyHashLength: keyHash.length,
        encryptedDataLength: encryptedData.length,
        ivLength: iv.length, 
        tagLength: tag.length,
        ciphertextLength: ciphertext.length,
        nonceLength: nonce.length,
        authTagLength: authTag.length
      });
      
      throw new Error(`Token decryption failed: ${decryptError.message}`);
    }
    
    // Parse the decrypted JSON
    const tokensData = JSON.parse(decrypted);
    
    // Validate token structure
    if (!tokensData.accessToken) {
      logger.error('Decrypted data missing accessToken');
      return null;
    }
    
    logger.info(`Successfully decrypted tokens - hasRefreshToken: ${!!tokensData.refreshToken}`);
    
    return {
      accessToken: tokensData.accessToken,
      refreshToken: tokensData.refreshToken || null,
      expiresAt: tokensData.expiresAt ? new Date(tokensData.expiresAt).getTime() : Date.now() + (3600 * 1000) // Default 1 hour if missing
    };
    
  } catch (error) {
    logger.error(`Failed to decrypt Spotify tokens for user ${userId}:`, error);
    return null;
  }
}

async function clearInvalidSpotifyTokens(userId: string): Promise<void> {
  await db.collection('users')
    .doc(userId)
    .collection('tokens')
    .doc('spotify')
    .delete();
  
  logger.info(`Cleared invalid Spotify tokens for user ${userId}`);
}

async function getLastSyncTime(userId: string): Promise<Date> {
  // Get the most recent track timestamp for this user
  const recentTrackSnapshot = await db.collection('spotifyListeningHistory')
    .where('userId', '==', userId)
    .orderBy('playedAt', 'desc')
    .limit(1)
    .get();
  
  if (!recentTrackSnapshot.empty) {
    const lastTrack = recentTrackSnapshot.docs[0].data();
    const lastPlayedAt = lastTrack.playedAt;
    
    // Ensure we have a valid timestamp
    if (lastPlayedAt && !isNaN(lastPlayedAt)) {
      const lastSyncDate = new Date(lastPlayedAt);
      if (!isNaN(lastSyncDate.getTime())) {
        return lastSyncDate;
      }
    }
    
    logger.warn(`Invalid playedAt timestamp for last track: ${lastPlayedAt}`);
  }
  
  // Default to 24 hours ago if no previous sync or invalid timestamp
  const oneDayAgo = new Date();
  oneDayAgo.setHours(oneDayAgo.getHours() - 24);
  logger.info(`Using default last sync time: ${oneDayAgo.toISOString()}`);
  return oneDayAgo;
}

async function storeSpotifyTracks(userId: string, tracks: any[]): Promise<void> {
  const batch = db.batch();
  
  for (const item of tracks) {
    const track = item.track;
    const playedAt = new Date(item.played_at);
    
    // Create a document ID based on user + track + timestamp for uniqueness
    const docId = `${userId}_${track.id}_${playedAt.getTime()}`;
    
    const trackDoc = db.collection('spotifyListeningHistory').doc(docId);
    
    batch.set(trackDoc, {
      userId,
      trackId: track.id,
      trackName: track.name,
      artistName: track.artists[0]?.name || 'Unknown Artist',
      albumName: track.album?.name || 'Unknown Album',
      playedAt: playedAt.getTime(),
      durationMs: track.duration_ms,
      explicit: track.explicit || false,
      popularity: track.popularity || 0,
      previewUrl: track.preview_url || null,
      externalUrls: track.external_urls || {},
      syncedAt: Date.now()
    });
  }
  
  await batch.commit();
}

async function storeRefreshedTokens(userId: string, tokens: any): Promise<void> {
  try {
    logger.info(`Storing refreshed tokens for user ${userId}`);
    
    // Create tokens object matching iOS format
    const tokensToStore = {
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: new Date(tokens.expiresAt).toISOString()
    };
    
    // Encrypt the tokens using the same logic as iOS app
    const encryptedToken = await encryptSpotifyTokens(tokensToStore, userId);
    
    if (!encryptedToken) {
      throw new Error('Failed to encrypt refreshed tokens');
    }
    
    // Store to Firebase
    await db.collection('users')
      .doc(userId)
      .collection('tokens')
      .doc('spotify')
      .set({
        encryptedData: encryptedToken.encryptedData,
        iv: encryptedToken.iv,
        tag: encryptedToken.tag,
        updatedAt: Date.now()
      });
      
    logger.info(`Successfully stored refreshed tokens for user ${userId}`);
    
  } catch (error) {
    logger.error(`Failed to store refreshed tokens for user ${userId}:`, error);
    throw error;
  }
}

/**
 * Encrypt Spotify tokens using AES-256-GCM (matching iOS app)
 */
async function encryptSpotifyTokens(tokens: any, userId: string): Promise<any | null> {
  try {
    // Generate key from userId using SHA256 (matching iOS app)
    const keyHash = crypto.createHash('sha256').update(userId).digest();
    
    // Convert tokens to JSON string
    const tokensString = JSON.stringify(tokens);
    const plaintext = Buffer.from(tokensString, 'utf8');
    
    // Generate random nonce/IV for GCM (12 bytes is standard for GCM)
    const nonce = crypto.randomBytes(12);
    
    // Create AES-256-GCM cipher
    const algorithm = 'aes-256-gcm';
    const cipher = crypto.createCipheriv(algorithm, keyHash, nonce);
    
    // Encrypt the data
    let ciphertext = cipher.update(plaintext);
    cipher.final();
    
    // Get the authentication tag
    const authTag = cipher.getAuthTag();
    
    // Return encrypted components (all base64 encoded)
    return {
      encryptedData: ciphertext.toString('base64'),
      iv: nonce.toString('base64'),
      tag: authTag.toString('base64')
    };
    
  } catch (error) {
    logger.error(`Failed to encrypt tokens for user ${userId}:`, error);
    return null;
  }
}

async function updateLastSyncTime(userId: string): Promise<void> {
  // Store sync metadata
  await db.collection('users')
    .doc(userId)
    .collection('syncMetadata')
    .doc('spotify')
    .set({
      lastSyncAt: Date.now(),
      lastSuccessfulSync: Date.now()
    }, { merge: true });
}

function isTokenExpired(expiresAt: number): boolean {
  // Add 5 minute buffer
  return Date.now() >= (expiresAt - 5 * 60 * 1000);
}
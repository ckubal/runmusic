import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import * as logger from "firebase-functions/logger";

// Use existing admin instance
const db = getFirestore();
const auth = getAuth();

/**
 * Check if a user with the given Google email exists and what providers they have
 */
export const checkIfGoogleUserExists = onCall(
  { cors: true },
  async (request) => {
    const { data } = request;
    const googleEmail = data?.googleEmail;

    if (!googleEmail || typeof googleEmail !== 'string') {
      throw new HttpsError('invalid-argument', 'googleEmail is required and must be a string');
    }

    try {
      // First, try to find the user by email in Firebase Auth
      let userRecord;
      try {
        userRecord = await auth.getUserByEmail(googleEmail);
      } catch (error: any) {
        // User doesn't exist in Firebase Auth
        if (error.code === 'auth/user-not-found') {
          return {
            exists: false,
            hasGoogleProvider: false,
            existingProviders: []
          };
        }
        throw error;
      }

      // If we get here, the user exists in Firebase Auth
      // Check what providers they have
      const providerIds = userRecord.providerData.map(provider => provider.providerId);
      const hasGoogleProvider = providerIds.includes('google.com');
      const hasAppleProvider = providerIds.includes('apple.com');

      // Also check if user exists in our Firestore users collection
      const userDoc = await db.collection('users').doc(userRecord.uid).get();
      const userExists = userDoc.exists;

      logger.info(`Google user check for ${googleEmail}: exists=${userExists}, providers=[${providerIds.join(',')}]`);

      return {
        exists: userExists,
        hasGoogleProvider,
        hasAppleProvider,
        existingProviders: providerIds,
        uid: userRecord.uid
      };

    } catch (error) {
      logger.error('Error checking Google user existence:', error);
      throw new HttpsError('internal', 'Failed to check user existence');
    }
  }
);

/**
 * Check if a user with the given Apple credentials exists and what providers they have
 */
export const checkIfAppleUserExists = onCall(
  { cors: true },
  async (request) => {
    const { data } = request;
    const appleUserId = data?.appleUserId;
    const appleEmail = data?.appleEmail;

    if (!appleUserId || typeof appleUserId !== 'string') {
      throw new HttpsError('invalid-argument', 'appleUserId is required and must be a string');
    }

    try {
      let userRecord;

      // First, try to find by Apple provider ID
      try {
        // Try to find user by Apple provider ID
        const users = await auth.getUsers([{ providerId: 'apple.com', providerUid: appleUserId }]);
        userRecord = users.users[0];
      } catch (error: any) {
        // If not found by provider ID, try by email if provided
        if (appleEmail) {
          try {
            userRecord = await auth.getUserByEmail(appleEmail);
          } catch (emailError: any) {
            if (emailError.code === 'auth/user-not-found') {
              return {
                exists: false,
                hasAppleProvider: false,
                existingProviders: []
              };
            }
            throw emailError;
          }
        } else {
          return {
            exists: false,
            hasAppleProvider: false,
            existingProviders: []
          };
        }
      }

      if (!userRecord) {
        return {
          exists: false,
          hasAppleProvider: false,
          existingProviders: []
        };
      }

      // Check what providers they have
      const providerIds = userRecord.providerData.map(provider => provider.providerId);
      const hasAppleProvider = providerIds.includes('apple.com');
      const hasGoogleProvider = providerIds.includes('google.com');

      // Check if user exists in our Firestore users collection
      const userDoc = await db.collection('users').doc(userRecord.uid).get();
      const userExists = userDoc.exists;

      logger.info(`Apple user check for ${appleUserId}: exists=${userExists}, providers=[${providerIds.join(',')}]`);

      return {
        exists: userExists,
        hasAppleProvider,
        hasGoogleProvider,
        existingProviders: providerIds,
        uid: userRecord.uid
      };

    } catch (error) {
      logger.error('Error checking Apple user existence:', error);
      throw new HttpsError('internal', 'Failed to check user existence');
    }
  }
);

/**
 * Delete a user account and all associated data
 */
export const deleteUserAccount = onCall(
  { cors: true },
  async (request) => {
    const { auth: authContext } = request;

    if (!authContext) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    const uid = authContext.uid;

    try {
      logger.info(`Deleting user account: ${uid}`);

      // Delete user data from Firestore
      await db.collection('users').doc(uid).delete();
      
      // Delete the user from Firebase Auth
      await auth.deleteUser(uid);

      logger.info(`Successfully deleted user account: ${uid}`);
      return { success: true };
    } catch (error) {
      logger.error('Error deleting user account:', error);
      throw new HttpsError('internal', 'Failed to delete user account');
    }
  }
);
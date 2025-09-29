/**
 * RunMusic Firebase Cloud Functions
 * 
 * Handles authentication cross-provider conflict detection and user management
 * for the RunMusic iOS application.
 */

import { initializeApp } from 'firebase-admin/app';

// Initialize Firebase Admin
initializeApp();

// Export authentication functions for Apple Sign-In implementation
export {
  checkIfGoogleUserExists,
  checkIfAppleUserExists,
  deleteUserAccount
} from './authFunctions';
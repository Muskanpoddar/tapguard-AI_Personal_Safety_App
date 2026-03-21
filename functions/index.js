// functions/index.js
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

// Initialize with service account
const serviceAccount = require('./service-account.json');

initializeApp({
  credential: cert(serviceAccount),
});

const db  = getFirestore();
const fcm = getMessaging();

// ── Trigger 1: Timer ended — alert contact ────────────────────────────────
// Fires when session doc updates and timerEnded becomes true
exports.onTimerEnded = onDocumentUpdated(
  'sessions/{sessionId}',
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();

    // Only trigger when timerEnded changes from false → true
    if (before.timerEnded === after.timerEnded) return null;
    if (!after.timerEnded) return null;
    if (!after.isActive)   return null;

    const ownerUid   = after.ownerUid;
    const ownerName  = after.ownerName || 'Your contact';
    const sessionId  = event.params.sessionId;

    console.log(`Timer ended for session ${sessionId}, owner: ${ownerUid}`);

    // Get all contacts of the owner — notify them
    try {
      const contactsSnap = await db
          .collection('users')
          .doc(ownerUid)
          .collection('contacts')
          .where('isActive', '==', true)
          .get();

      if (contactsSnap.empty) {
        console.log('No active contacts to notify');
        return null;
      }

      // Collect all FCM tokens of contacts
      const tokens = [];
      for (const doc of contactsSnap.docs) {
        const contactUid = doc.id;
        const userDoc = await db.collection('users').doc(contactUid).get();
        if (userDoc.exists) {
          const token = userDoc.data().fcmToken;
          if (token) tokens.push(token);
        }
      }

      if (tokens.length === 0) {
        console.log('No FCM tokens found');
        return null;
      }

      // Send notification to all contacts
      const message = {
        notification: {
          title:  `⚠️ Check on ${ownerName}`,
          body:   `${ownerName}'s safety timer has ended. Please check if they are safe!`,
        },
        data: {
          type:      'timer_ended',
          sessionId: sessionId,
          ownerUid:  ownerUid,
          ownerName: ownerName,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'tapguard_alerts',
            priority:  'max',
            sound:     'default',
            vibrateTimingsMillis: [0, 500, 200, 500, 200, 500],
          },
        },
        tokens: tokens,
      };

      const response = await fcm.sendEachForMulticast(message);
      console.log(`Sent to ${response.successCount} devices`);

      // Clean up invalid tokens
      response.responses.forEach((resp, i) => {
        if (!resp.success) {
          console.log(`Failed for token ${i}: ${resp.error?.message}`);
        }
      });

    } catch (err) {
      console.error('Error sending notification:', err);
    }

    return null;
  }
);

// ── Trigger 2: I am Safe — notify contacts ────────────────────────────────
// Fires when isSafe becomes true
exports.onUserSafe = onDocumentUpdated(
  'sessions/{sessionId}',
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();

    // Only trigger when isSafe changes false → true
    if (before.isSafe === after.isSafe) return null;
    if (!after.isSafe)   return null;
    if (!after.isActive) return null;

    const ownerUid  = after.ownerUid;
    const ownerName = after.ownerName || 'Your contact';
    const sessionId = event.params.sessionId;

    console.log(`User safe for session ${sessionId}`);

    try {
      const contactsSnap = await db
          .collection('users')
          .doc(ownerUid)
          .collection('contacts')
          .where('isActive', '==', true)
          .get();

      if (contactsSnap.empty) return null;

      const tokens = [];
      for (const doc of contactsSnap.docs) {
        const userDoc = await db
            .collection('users').doc(doc.id).get();
        if (userDoc.exists) {
          const token = userDoc.data().fcmToken;
          if (token) tokens.push(token);
        }
      }

      if (tokens.length === 0) return null;

      const message = {
        notification: {
          title: `✅ ${ownerName} is Safe`,
          body:  `${ownerName} has confirmed they are safe.`,
        },
        data: {
          type:      'user_safe',
          sessionId: sessionId,
          ownerName: ownerName,
        },
        android: {
          priority: 'normal',
          notification: {
            channelId: 'tapguard_alerts',
            sound:     'default',
          },
        },
        tokens: tokens,
      };

      await fcm.sendEachForMulticast(message);
      console.log('Safety notification sent');

    } catch (err) {
      console.error('Error sending safety notification:', err);
    }

    return null;
  }
);

// ── Trigger 3: Session ended — notify contacts ────────────────────────────
exports.onSessionEnded = onDocumentUpdated(
  'sessions/{sessionId}',
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();

    // Only trigger when isActive changes true → false
    if (before.isActive === after.isActive) return null;
    if (after.isActive) return null;

    const ownerName = after.ownerName || 'Your contact';
    const ownerUid  = after.ownerUid;

    try {
      const contactsSnap = await db
          .collection('users')
          .doc(ownerUid)
          .collection('contacts')
          .where('isPaired', '==', true)
          .get();

      if (contactsSnap.empty) return null;

      const tokens = [];
      for (const doc of contactsSnap.docs) {
        const userDoc = await db
            .collection('users').doc(doc.id).get();
        if (userDoc.exists) {
          const token = userDoc.data().fcmToken;
          if (token) tokens.push(token);
        }
      }

      if (tokens.length === 0) return null;

      await fcm.sendEachForMulticast({
        notification: {
          title: `🔒 Session Ended`,
          body:  `${ownerName} has ended their safety session.`,
        },
        data: {
          type: 'session_ended',
          ownerName: ownerName,
        },
        android: {
          priority: 'normal',
          notification: {
            channelId: 'tapguard_alerts',
          },
        },
        tokens: tokens,
      });

    } catch (err) {
      console.error('Error:', err);
    }

    return null;
  }
);
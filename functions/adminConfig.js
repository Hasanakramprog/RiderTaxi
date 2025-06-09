/* eslint-disable linebreak-style */
const admin = require("firebase-admin");
// eslint-disable-next-line linebreak-style

// Initialize admin only once
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const fcm = admin.messaging();

module.exports = {
  admin,
  db,
  // eslint-disable-next-line comma-dangle
  fcm
};

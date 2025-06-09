/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

// const {onRequest} = require("firebase-functions/v2/https");
// const logger = require("firebase-functions/logger");
const findNearbyDriversModule = require("./findNearbyDrivers");
const updateDriverRatingModule = require("./updateDriverRating");
const hotspotsModule = require("./hotspots");
// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });

// Export all functions from the findNearbyDrivers module
exports.findNearbyDrivers = findNearbyDriversModule.findNearbyDrivers;
// eslint-disable-next-line max-len
exports.refreshNearbyDriversSearch = findNearbyDriversModule.refreshNearbyDriversSearch;
// Export the driver rating update function
exports.updateDriverRating = updateDriverRatingModule.updateDriverRating;
// Export hotspots functions
exports.calculateHotspots = hotspotsModule.calculateHotspots;
exports.getHotspots = hotspotsModule.getHotspots;

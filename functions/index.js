/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const findNearbyDriversModule = require("./findNearbyDrivers");
const updateDriverRatingModule = require("./updateDriverRating");
const hotspotsModule = require("./hotspots");
const tripNotificationsModule = require("./tripNotifications");

// Export Cloud Tasks dispatch functions from the findNearbyDrivers module
exports.findNearbyDrivers = findNearbyDriversModule.findNearbyDrivers;
exports.dispatchNextRound = findNearbyDriversModule.dispatchNextRound;
exports.restartDispatch = findNearbyDriversModule.restartDispatch;

// Export the driver rating update function
exports.updateDriverRating = updateDriverRatingModule.updateDriverRating;

// Export hotspots functions
exports.calculateHotspots = hotspotsModule.calculateHotspots;
exports.getHotspots = hotspotsModule.getHotspots;

// Export trip status push notifications trigger for riders
exports.onTripStatusChanged = tripNotificationsModule.onTripStatusChanged;

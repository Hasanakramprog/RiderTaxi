/* eslint-disable linebreak-style */
const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {admin, db} = require("./adminConfig"); // Use shared config

// // Initialize admin if not already initialized
// if (!admin.apps.length) {
//   admin.initializeApp();
// }

// const db = admin.firestore();

/**
 * Logs debug information with a formatted label.
 *
 * @param {string} label - The label for the debug output.
 * @param {*} data - The data to be stringified and logged.
 */
function logDebug(label, data) {
  console.log(`===== ${label} =====`);
  console.log(JSON.stringify(data, null, 2));
}

/**
 * Calculate new driver rating based on existing rating and new user rating
 * @param {number} currentRating - Current driver rating
 * @param {number} currentRatingCount - Number of ratings the driver has
 * @param {number} newUserRating - New rating from the user (1-5)
 * @return {object} Object containing new rating and new rating count
 */
function calculateNewRating(currentRating, currentRatingCount, newUserRating) {
  // Calculate the total points from all previous ratings
  const totalPoints = currentRating * currentRatingCount;
  // Add the new rating points
  const newTotalPoints = totalPoints + newUserRating;
  // Calculate new count
  const newRatingCount = currentRatingCount + 1;
  // Calculate new average rating
  const newRating = newTotalPoints / newRatingCount;
  return {
    newRating: Math.round(newRating * 10) / 10, // Round to 1 decimal place
    newRatingCount: newRatingCount,
  };
}

// Main function to update driver rating when trip is rated
// eslint-disable-next-line max-len
exports.updateDriverRating = onDocumentUpdated("trips/{tripId}", async (event) => {
  try {
    const tripId = event.params.tripId;
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    // eslint-disable-next-line max-len
    logDebug("Trip update detected", {tripId, beforeStatus: beforeData.status, afterStatus: afterData.status});
    // Only process if userRating was added and trip is completed
    if (afterData.status !== "completed") {
      console.log("Trip not completed, skipping rating update");
      return null;
    }
    // Check if userRating was just added (didn't exist before, exists now)
    if (beforeData.userRating || !afterData.userRating) {
      console.log("No new user rating detected, skipping");
      return null;
    }
    const userRating = afterData.userRating;
    const driverId = afterData.driverId;
    // Validate rating is between 1 and 5
    if (userRating < 1 || userRating > 5) {
      console.error("Invalid user rating:", userRating);
      return null;
    }
    if (!driverId) {
      console.error("No driver ID found in trip data");
      return null;
    }
    logDebug("Processing rating update", {
      tripId,
      driverId,
      userRating,
    });
    // Update driver rating using a transaction to prevent race conditions
    await db.runTransaction(async (transaction) => {
      const driverRef = db.collection("drivers").doc(driverId);
      const driverDoc = await transaction.get(driverRef);
      if (!driverDoc.exists) {
        throw new Error(`Driver ${driverId} not found`);
      }
      const driverData = driverDoc.data();
      // eslint-disable-next-line max-len
      const currentRating = driverData.rating || 5.0; // Default to 5.0 if no rating
      const currentRatingCount = driverData.ratingCount || 0;
      // Calculate new rating
      const {newRating, newRatingCount} = calculateNewRating(
          currentRating,
          currentRatingCount,
          userRating,
      );
      logDebug("Rating calculation", {
        currentRating,
        currentRatingCount,
        userRating,
        newRating,
        newRatingCount,
      });
      // Update driver document
      transaction.update(driverRef, {
        rating: newRating,
        ratingCount: newRatingCount,
        lastRatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      // Also update the trip to mark that rating has been processed
      const tripRef = db.collection("trips").doc(tripId);
      transaction.update(tripRef, {
        ratingProcessed: true,
        ratingProcessedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      // eslint-disable-next-line max-len
      console.log(`Updated driver ${driverId} rating from ${currentRating} to ${newRating} (${newRatingCount} total ratings)`);
    });
    return null;
  } catch (error) {
    console.error("Error updating driver rating:", error);
    return null;
  }
});

// Export the function
module.exports = {
  updateDriverRating: exports.updateDriverRating,
};

// eslint-disable-next-line max-len
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

// Initialize admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const fcm = admin.messaging();

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
 * Calculates the distance in kilometers between two geographic coordinates
 * using the Haversine formula.
 *
 * @param {number} lat1 - Latitude of the first point.
 * @param {number} lon1 - Longitude of the first point.
 * @param {number} lat2 - Latitude of the second point.
 * @param {number} lon2 - Longitude of the second point.
 * @return {number} The distance in kilometers.
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Radius of earth in km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) *
      Math.cos(lat2 * Math.PI / 180) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c; // Distance in km
}

// Helper function to find nearby drivers
// eslint-disable-next-line require-jsdoc
async function findDriversForTrip(tripId, tripData) {
  try {
    logDebug("Processing trip", {tripId, tripStatus: tripData.status});

    // Only process trips with 'searching' status
    if (tripData.status !== "searching") {
      logDebug("Trip not in searching status", {status: tripData.status});
      return null;
    }

    console.log(`Finding drivers for trip ${tripId}`);

    // Get pickup coordinates
    const pickupLat = tripData.pickup.latitude;
    const pickupLng = tripData.pickup.longitude;

    // Define search radius (in km)
    const searchRadius = 5;

    // Query for available drivers
    const driversSnapshot = await db.collection("drivers")
        .where("isOnline", "==", true)
        .where("isAvailable", "==", true)
        .get();

    if (driversSnapshot.empty) {
      console.log("No available drivers found");
      // You might want to update the trip status here
      await db.collection("trips").doc(tripId).update({
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        noDriversAvailable: true,
      });
      return null;
    }

    // Calculate distance for each driver and sort by proximity
    const nearbyDrivers = [];

    driversSnapshot.forEach((doc) => {
      const driverData = doc.data();
      const driverId = doc.id;

      // Check if driver has valid location
      if (driverData.location &&
        driverData.location.latitude &&
        driverData.location.longitude) {
        const distance = calculateDistance(
            pickupLat,
            pickupLng,
            driverData.location.latitude,
            driverData.location.longitude,
        );

        // Only include drivers within the search radius
        if (distance <= searchRadius) {
          nearbyDrivers.push({
            driverId,
            distance,
            fcmToken: driverData.fcmToken,
            driverName: driverData.displayName || "Driver",
          });
        }
      }
    });

    // Sort drivers by distance (closest first)
    nearbyDrivers.sort((a, b) => a.distance - b.distance);

    console.log(`Found ${nearbyDrivers.length} nearby drivers`);

    if (nearbyDrivers.length === 0) {
      console.log("No drivers within search radius");
      await db.collection("trips").doc(tripId).update({
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        noDriversAvailable: true,
      });
      return null;
    }

    // For now, just send notification to the closest driver
    // In a production app, you'd implement a queue system
    const closestDriver = nearbyDrivers[0];

    // Store a record of which driver was notified
    await db.collection("trips").doc(tripId).update({
      nearbyDrivers: nearbyDrivers,
      notifiedDriverId: closestDriver.driverId,
      notificationTime: admin.firestore.FieldValue.serverTimestamp(),
      status: "driver_notified",
    });

    // Send push notification to driver
    if (closestDriver.fcmToken) {
      const message = {
        token: closestDriver.fcmToken,
        notification: {
          title: "New Trip Request",
          body:
          `New pickup request (${closestDriver.distance.toFixed(1)}km away)`,
        },
        data: {
          tripId: tripId,
          pickupAddress: tripData.pickup.address || "Unknown location",
          pickupLatitude: pickupLat.toString(),
          pickupLongitude: pickupLng.toString(),
          dropoffAddress: tripData.dropoff.address || "Unknown destination",
          fare: tripData.fare ? tripData.fare.toString() : "0",
          distance: tripData.distance ? tripData.distance.toString() : "0",
          estimatedDuration:
          tripData.duration ? tripData.duration.toString() : "0",
          expiresIn: "20", // Driver has 20 seconds to respond
          notificationType: "tripRequest",
        },
      };

      try {
        await fcm.send(message);
        console.log(`Notification sent to driver ${closestDriver.driverId}`);
      } catch (error) {
        console.error("Error sending notification:", error);
      }
    }

    return null;
  } catch (error) {
    console.error("Error in findDriversForTrip function:", error);
    return null;
  }
}

// Handle trip creation
// eslint-disable-next-line max-len
exports.findNearbyDrivers = onDocumentCreated("trips/{tripId}", async (event) => {
  try {
    const tripId = event.params.tripId;
    const tripData = event.data.data();

    logDebug("New trip created", {tripId, tripData});

    return findDriversForTrip(tripId, tripData);
  } catch (error) {
    console.error("Error in findNearbyDrivers onCreate function:", error);
    return null;
  }
});

// Handle trip updates (for periodic searches)
// eslint-disable-next-line max-len
exports.refreshNearbyDriversSearch = onDocumentUpdated("trips/{tripId}", async (event) => {
  try {
    const tripId = event.params.tripId;
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    // Only trigger on searchRefreshedAt updates for searching trips
    if (afterData.status !== "searching") {
      return null;
    }
    // Check if searchRefreshedAt was updated
    if (!afterData.searchRefreshedAt) {
      return null;
    }
    // If searchRefreshedAt existed before, make sure it changed
    // eslint-disable-next-line max-len
    if (beforeData.searchRefreshedAt && afterData.searchRefreshedAt.seconds === beforeData.searchRefreshedAt.seconds) {
      return null;
    }
    // eslint-disable-next-line max-len
    logDebug("Refreshing driver search", {tripId, searchAttempts: afterData.searchAttempts || 0});
    return findDriversForTrip(tripId, afterData);
  } catch (error) {
    console.error("Error in refreshNearbyDriversSearch function:", error);
    return null;
  }
});

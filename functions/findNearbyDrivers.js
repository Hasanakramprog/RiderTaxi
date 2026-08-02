// eslint-disable-next-line max-len
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {admin, db, fcm} = require("./adminConfig"); // Use shared config

// Initialize admin if not already initialized
// if (!admin.apps.length) {
//   admin.initializeApp();
// }

// const db = admin.firestore();
// const fcm = admin.messaging();

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

/**
 * Calculates driver priority score based on multiple factors.
 * Higher score = higher priority for trip assignment.
 *
 * Scoring breakdown (0-100 points total):
 * - Distance: 0-50 points (closer = more points)
 * - Tier Bonus: 0-15 points (Platinum=15, Gold=10, Silver=5, Bronze=0)
 * - Acceptance Rate: 0-20 points (100% = 20 points)
 * - User Rating: 0-15 points (5 stars = 15 points)
 *
 * @param {object} driver - Driver data including metrics and location.
 * @param {number} pickupLat - Pickup latitude.
 * @param {number} pickupLng - Pickup longitude.
 * @param {number} distance - Pre-calculated distance in km.
 * @return {object} Driver priority data with score breakdown.
 */
function calculateDriverPriority(driver, pickupLat, pickupLng, distance) {
  // 1. Distance Score (0-50 points)
  // Closer drivers get more points. 10km+ = 0 points
  const distanceScore = Math.max(0, 50 - (distance * 5));

  // 2. Tier Bonus (0-15 points)
  const tierBonuses = {
    "platinum": 15,
    "gold": 10,
    "silver": 5,
    "bronze": 0,
  };
  const tier = driver.metrics?.tier || "silver";
  const tierScore = tierBonuses[tier] || 5;

  // 3. Acceptance Rate Score (0-20 points)
  // 100% acceptance = 20 points
  const acceptanceRate = driver.metrics?.acceptanceRate || 0;
  const acceptanceScore = (acceptanceRate / 100) * 20;

  // 4. User Rating Score (0-15 points)
  // 5 stars = 15 points
  const userRating = driver.rating || 0;
  const ratingScore = (userRating / 5) * 15;

  // Total Priority Score (0-100 points)
  const totalScore = distanceScore + tierScore + acceptanceScore + ratingScore;

  return {
    driverId: driver.driverId,
    distance: distance,
    tier: tier,
    acceptanceRate: acceptanceRate,
    rating: userRating,
    reliabilityScore: driver.metrics?.reliabilityScore || 0,
    priorityScore: totalScore,
    // Score breakdown for debugging
    scoreBreakdown: {
      distance: distanceScore.toFixed(1),
      tier: tierScore,
      acceptance: acceptanceScore.toFixed(1),
      rating: ratingScore.toFixed(1),
      total: totalScore.toFixed(1),
    },
    fcmToken: driver.fcmToken,
    driverName: driver.displayName || "Driver",
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Builds the FCM message payload for a single driver.
// Extracted so it can be reused in Promise.all() broadcast.
// eslint-disable-next-line require-jsdoc
function buildMessage(driver, tripId, tripData, pickupLat, pickupLng) {
  const messageData = {
    tripId: tripId,
    pickupAddress: tripData.pickup.address || "Unknown location",
    pickupLatitude: pickupLat.toString(),
    pickupLongitude: pickupLng.toString(),
    dropoffAddress: tripData.dropoff.address || "Unknown destination",
    fare: tripData.fare ? tripData.fare.toString() : "0",
    distance: tripData.distance ? tripData.distance.toString() : "0",
    estimatedDuration: tripData.duration ? tripData.duration.toString() : "0",
    expiresIn: "20", // Driver has 20 seconds to respond
    notificationType: "tripRequest",
    notificationTime: tripData.notificationTime ?
      tripData.notificationTime.toMillis().toString() :
      Date.now().toString(),
  };

  // Add stops information (up to 5 — FCM has message size limits)
  if (tripData.stops && Array.isArray(tripData.stops) && tripData.stops.length > 0) {
    const stopsCount = tripData.stops.length;
    messageData.hasStops = "true";
    messageData.stopsCount = stopsCount.toString();
    let totalWaitingTime = 0;
    const maxStops = Math.min(stopsCount, 5);
    for (let i = 0; i < maxStops; i++) {
      const stop = tripData.stops[i];
      if (stop) {
        messageData[`stop${i + 1}Address`] = stop.address || "Unknown stop location";
        if (stop.latitude && stop.longitude) {
          messageData[`stop${i + 1}Latitude`] = stop.latitude.toString();
          messageData[`stop${i + 1}Longitude`] = stop.longitude.toString();
        }
        if (stop.waitingTime !== undefined) {
          messageData[`stop${i + 1}WaitingTime`] = stop.waitingTime.toString();
          totalWaitingTime += parseInt(stop.waitingTime) || 0;
        } else {
          messageData[`stop${i + 1}WaitingTime`] = "0";
        }
      }
    }
    messageData.totalWaitingTime = totalWaitingTime.toString();
    if (stopsCount > maxStops) {
      messageData.additionalStops = (stopsCount - maxStops).toString();
    }
  } else {
    messageData.hasStops = "false";
    messageData.totalWaitingTime = "0";
  }

  // Build notification body
  let notificationBody = `New pickup request (${driver.distance.toFixed(1)}km away)`;
  if (tripData.stops && tripData.stops.length > 0) {
    // eslint-disable-next-line max-len
    notificationBody += ` with ${tripData.stops.length} stop${tripData.stops.length > 1 ? "s" : ""}`;
    const totalWaitingMinutes = parseInt(messageData.totalWaitingTime) || 0;
    if (totalWaitingMinutes > 0) {
      notificationBody += ` (${totalWaitingMinutes} min waiting)`;
    }
  }

  return {
    token: driver.fcmToken,
    notification: {
      title: "New Trip Request",
      body: notificationBody,
    },
    data: messageData,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
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

    // Calculate distance and priority for each driver
    const driversWithPriority = [];

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
          // Calculate priority score for this driver
          const driverWithPriority = calculateDriverPriority(
              {
                driverId: driverId,
                ...driverData,
              },
              pickupLat,
              pickupLng,
              distance,
          );

          driversWithPriority.push(driverWithPriority);
        }
      }
    });

    // Sort drivers by PRIORITY SCORE (highest first) instead of distance
    driversWithPriority.sort((a, b) => b.priorityScore - a.priorityScore);

    console.log(`Found ${driversWithPriority.length} nearby drivers`);

    if (driversWithPriority.length === 0) {
      console.log("No drivers within search radius");
      await db.collection("trips").doc(tripId).update({
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        noDriversAvailable: true,
      });
      return null;
    }

    // ── Task 1: Broadcast to top 3 drivers simultaneously ────────────────────
    const TOP_N = 3;
    const topDrivers = driversWithPriority.slice(0, TOP_N);

    // Log the drivers being notified
    console.log(`Broadcasting to ${topDrivers.length} driver(s) simultaneously:`);
    topDrivers.forEach((driver, index) => {
      console.log(`  ${index + 1}. ${driver.driverName} (${driver.tier})`);
      console.log(`     Priority: ${driver.priorityScore.toFixed(1)} pts | Distance: ${driver.distance.toFixed(2)}km`);
      console.log(`     Breakdown: ${JSON.stringify(driver.scoreBreakdown)}`);
    });

    // ── Write trip document: store all notified drivers + initialize the race lock
    //
    // claimedByDriverId starts as null ("door is unlocked").
    // The driver app must run a Firestore Transaction that:
    //   1. Reads claimedByDriverId
    //   2. If null  → sets it to the driver's own ID (claims the trip)
    //   3. If not null → throws "already claimed" (another driver won the race)
    // This guarantees exactly one driver gets the trip, even if all 3 tap
    // Accept at the exact same millisecond.
    await db.collection("trips").doc(tripId).update({
      nearbyDrivers: driversWithPriority.map((d) => ({
        driverId: d.driverId,
        distance: d.distance,
        tier: d.tier,
        priorityScore: d.priorityScore,
        acceptanceRate: d.acceptanceRate,
      })),
      notifiedDriverIds: topDrivers.map((d) => d.driverId), // array — all 3 notified
      claimedByDriverId: null,                              // race lock — null = unclaimed
      notifiedDriverTier: topDrivers[0].tier,
      notifiedDriverPriority: topDrivers[0].priorityScore,
      notificationTime: admin.firestore.FieldValue.serverTimestamp(),
      status: "driver_notified",
    });

    // ── Send FCM notifications to all top drivers in parallel ─────────────────
    const notifyResults = await Promise.allSettled(
        topDrivers
            .filter((driver) => driver.fcmToken) // skip drivers with no token
            .map(async (driver) => {
              const message = buildMessage(driver, tripId, tripData, pickupLat, pickupLng);
              await fcm.send(message);
              console.log(
                  `✓ Notified driver ${driver.driverId} (${driver.tier}, ` +
                  `${driver.priorityScore.toFixed(1)}pts, ${driver.distance.toFixed(2)}km)`,
              );
            }),
    );

    // Log any send failures without crashing the function
    notifyResults.forEach((result, i) => {
      if (result.status === "rejected") {
        console.error(`✗ Failed to notify driver at index ${i}:`, result.reason);
      }
    });

    const successCount = notifyResults.filter((r) => r.status === "fulfilled").length;
    console.log(`Broadcast complete: ${successCount}/${topDrivers.length} drivers notified successfully.`);

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

    // IMPORTANT: Don't run on initial trip creation
    // Only run when searchRefreshedAt is explicitly updated
    if (!beforeData.searchRefreshedAt && afterData.searchRefreshedAt) {
      console.log("Skipping refresh - this is initial trip creation");
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

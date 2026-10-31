const {getFunctions} = require("firebase-admin/functions");
const {onTaskDispatched} = require("firebase-functions/v2/tasks");
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const crypto = require("crypto");
const {admin, db, fcm} = require("./adminConfig");
const {getEffectiveSettings} = require("./walletCore");

/**
 * Supported vehicle classes in the dispatch system.
 */
const VEHICLE_TYPES = Object.freeze({
  BIKE: "bike",
  STANDARD: "standard",
  FEMALE: "female",
  XL: "xl",
  VIP: "vip",
});

/**
 * Supported gender values for matching.
 */
const GENDER = Object.freeze({
  ANY: "any",
  FEMALE: "female",
  MALE: "male",
});

/**
 * Configuration for Cloud Tasks chained dispatch rounds.
 */
const DISPATCH_CONFIG = Object.freeze({
  MAX_SEARCH_DURATION_MS: 120 * 1000,
  ROUND_DELAY_SECONDS: 15,
  DEFAULT_RADIUS_KM: 5,
  EXPANDED_RADIUS_KM: 8,
  EXPAND_AFTER_MS: 45 * 1000,
  TOP_DRIVERS_PER_ROUND: 3,
});

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

  return R * c;
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
  const distanceScore = Math.max(0, 50 - (distance * 5));

  // 2. Tier Bonus (0-15 points)
  const tierBonuses = {
    "platinum": 15,
    "gold": 10,
    "silver": 5,
    "bronze": 0,
  };
  const tier = driver.metrics?.tier || "silver";
  const tierScore = tierBonuses[tier] !== undefined ? tierBonuses[tier] : 5;

  // 3. Acceptance Rate Score (0-20 points)
  const acceptanceRate = driver.metrics?.acceptanceRate || 0;
  const acceptanceScore = (acceptanceRate / 100) * 20;

  // 4. User Rating Score (0-15 points)
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

/**
 * Builds the FCM message payload for a single driver.
 *
 * @param {object} driver - Candidate driver with priority and distance info.
 * @param {string} tripId - Firestore trip ID.
 * @param {object} tripData - Trip document data.
 * @param {number} pickupLat - Pickup latitude.
 * @param {number} pickupLng - Pickup longitude.
 * @return {object} FCM message payload.
 */
function buildMessage(driver, tripId, tripData, pickupLat, pickupLng) {
  const requestedType =
    tripData.requestedCarType || tripData.carType || VEHICLE_TYPES.STANDARD;
  const isFemaleTrip =
    tripData.driverGenderPreference === GENDER.FEMALE ||
    requestedType === VEHICLE_TYPES.FEMALE;
  const isBikeTrip =
    requestedType === VEHICLE_TYPES.BIKE ||
    tripData.carType === VEHICLE_TYPES.BIKE;

  const messageData = {
    tripId: tripId,
    pickupAddress: tripData.pickup?.address || "Unknown location",
    pickupLatitude: pickupLat.toString(),
    pickupLongitude: pickupLng.toString(),
    dropoffAddress: tripData.dropoff?.address || "Unknown destination",
    fare: tripData.fare ? tripData.fare.toString() : "0",
    distance: tripData.distance ? tripData.distance.toString() : "0",
    estimatedDuration: tripData.duration ? tripData.duration.toString() : "0",
    expiresIn: "20",
    notificationType: "tripRequest",
    carType: tripData.carType || VEHICLE_TYPES.STANDARD,
    requestedCarType: requestedType,
    driverGenderPreference: tripData.driverGenderPreference || GENDER.ANY,
    notificationTime: tripData.notificationTime &&
      typeof tripData.notificationTime.toMillis === "function" ?
      tripData.notificationTime.toMillis().toString() :
      Date.now().toString(),
  };

  // Add stops information (up to 5 — FCM has message size limits)
  if (
    tripData.stops &&
    Array.isArray(tripData.stops) &&
    tripData.stops.length > 0
  ) {
    const stopsCount = tripData.stops.length;
    messageData.hasStops = "true";
    messageData.stopsCount = stopsCount.toString();
    let totalWaitingTime = 0;
    const maxStops = Math.min(stopsCount, 5);
    for (let i = 0; i < maxStops; i++) {
      const stop = tripData.stops[i];
      if (stop) {
        const stopAddr = stop.address || "Unknown stop location";
        messageData[`stop${i + 1}Address`] = stopAddr;
        if (stop.latitude && stop.longitude) {
          messageData[`stop${i + 1}Latitude`] = stop.latitude.toString();
          messageData[`stop${i + 1}Longitude`] = stop.longitude.toString();
        }
        if (stop.waitingTime !== undefined) {
          messageData[`stop${i + 1}WaitingTime`] = stop.waitingTime.toString();
          totalWaitingTime += parseInt(stop.waitingTime, 10) || 0;
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

  let notificationTitle = "New Trip Request";
  if (isBikeTrip) {
    notificationTitle = "🛵 New Bike Trip Request";
  } else if (isFemaleTrip) {
    notificationTitle = "🧕 New Women Trip Request";
  }

  let notificationBody = `New pickup (${driver.distance.toFixed(1)}km away)`;
  if (isBikeTrip) {
    notificationBody = `Bike pickup (${driver.distance.toFixed(1)}km away)`;
  } else if (isFemaleTrip) {
    notificationBody = `Women ride (${driver.distance.toFixed(1)}km away)`;
  }

  if (tripData.stops && tripData.stops.length > 0) {
    const stopCount = tripData.stops.length;
    const plural = stopCount > 1 ? "s" : "";
    notificationBody += ` with ${stopCount} stop${plural}`;
    const totalWaitingMinutes = parseInt(messageData.totalWaitingTime, 10) || 0;
    if (totalWaitingMinutes > 0) {
      notificationBody += ` (${totalWaitingMinutes} min waiting)`;
    }
  }

  return {
    token: driver.fcmToken,
    notification: {
      title: notificationTitle,
      body: notificationBody,
    },
    data: messageData,
  };
}

/**
 * Finds eligible drivers for a trip within a given radius, excluding any
 * drivers already notified or who explicitly declined.
 *
 * Preserves wallet balance + overdraft checks, vehicle/gender filters,
 * and priority scoring.
 *
 * @param {string} tripId - Trip document ID.
 * @param {object} tripData - Current trip document data.
 * @param {number} searchRadiusKm - Search radius in kilometers.
 * @param {Set<string>} excludedDriverIds - Set of driver IDs to exclude.
 * @return {Promise<Array<object>>} Sorted list of eligible priority drivers.
 */
async function findEligibleDriversForTrip(
    tripId,
    tripData,
    searchRadiusKm,
    excludedDriverIds = new Set(),
) {
  if (
    !tripData.pickup ||
    typeof tripData.pickup.latitude !== "number" ||
    typeof tripData.pickup.longitude !== "number"
  ) {
    console.warn(`[Dispatch] Trip ${tripId} missing valid pickup coordinates.`);
    return [];
  }

  const pickupLat = tripData.pickup.latitude;
  const pickupLng = tripData.pickup.longitude;

  // 1. Read app_settings/wallet once per invocation
  const settingsDoc = await db.collection("app_settings").doc("wallet").get();
  const walletSettings = getEffectiveSettings(
      settingsDoc.exists ? settingsDoc.data() : null,
  );

  // 2. Query for available drivers with walletCanWork == true
  let driversQuery = db.collection("drivers")
      .where("isOnline", "==", true)
      .where("isAvailable", "==", true)
      .where("walletCanWork", "==", true);

  const isFemaleRequested =
    tripData.requestedCarType === VEHICLE_TYPES.FEMALE ||
    tripData.driverGenderPreference === GENDER.FEMALE ||
    tripData.carType === VEHICLE_TYPES.FEMALE;

  const isBikeRequested =
    tripData.requestedCarType === VEHICLE_TYPES.BIKE ||
    tripData.carType === VEHICLE_TYPES.BIKE;

  if (isFemaleRequested) {
    driversQuery = driversQuery.where("gender", "==", GENDER.FEMALE);
  } else if (isBikeRequested) {
    driversQuery = driversQuery.where("carType", "==", VEHICLE_TYPES.BIKE);
  } else if (tripData.carType) {
    driversQuery = driversQuery.where("carType", "==", tripData.carType);
  }

  const driversSnapshot = await driversQuery.get();
  if (driversSnapshot.empty) {
    console.log(
        `[Dispatch] Trip ${tripId}: No online drivers with walletCanWork.`,
    );
    return [];
  }

  // 3. Filter by exclusion set, safety guards, and search radius
  const candidatesInRadius = [];

  driversSnapshot.forEach((doc) => {
    const driverData = doc.data();
    const driverId = doc.id;

    // Exclude already-notified or declined drivers
    if (excludedDriverIds && excludedDriverIds.has(driverId)) {
      return;
    }

    // Safety Guard: Ensure female trip receives ONLY female drivers
    if (isFemaleRequested && driverData.gender !== GENDER.FEMALE) {
      console.warn(
          `[Dispatch] Driver ${driverId} rejected: Non-female for female trip.`,
      );
      return;
    }

    // Safety Guard: Ensure bike trip receives ONLY bike drivers
    if (isBikeRequested && driverData.carType !== VEHICLE_TYPES.BIKE) {
      console.warn(
          `[Dispatch] Driver ${driverId} rejected: Non-bike for bike trip.`,
      );
      return;
    }

    // Safety Guard: Female tier vehicle class compatibility
    if (isFemaleRequested) {
      const allowedCarTypes = [VEHICLE_TYPES.STANDARD, VEHICLE_TYPES.FEMALE];
      if (
        driverData.carType &&
        !allowedCarTypes.includes(driverData.carType)
      ) {
        return;
      }
    }

    if (
      driverData.location &&
      typeof driverData.location.latitude === "number" &&
      typeof driverData.location.longitude === "number"
    ) {
      const distance = calculateDistance(
          pickupLat,
          pickupLng,
          driverData.location.latitude,
          driverData.location.longitude,
      );

      if (distance <= searchRadiusKm) {
        candidatesInRadius.push({
          driverId,
          driverData,
          distance,
        });
      }
    }
  });

  if (candidatesInRadius.length === 0) {
    console.log(
        `[Dispatch] Trip ${tripId}: No new candidates within ` +
        `${searchRadiusKm}km radius.`,
    );
    return [];
  }

  // 4. Batch-load driver_wallets and enforce balance + overdraft eligibility
  const rawFare = Number(tripData.fare || tripData.estimatedFare || 0);
  const estimateFareCents = Math.round(rawFare * 100);
  const requiredAllowanceCents = Math.round(
      estimateFareCents * walletSettings.dispatchBufferMultiplier,
  );

  const walletRefs = candidatesInRadius.map((c) =>
    db.collection("driver_wallets").doc(c.driverId),
  );
  const walletDocs = await db.getAll(...walletRefs);
  const walletMap = new Map();
  walletDocs.forEach((doc) => {
    if (doc.exists) walletMap.set(doc.id, doc.data());
  });

  const eligibleCandidates = [];
  for (const candidate of candidatesInRadius) {
    const wallet = walletMap.get(candidate.driverId);
    if (!wallet) {
      console.warn(
          `[Dispatch] Candidate ${candidate.driverId} has no wallet doc.`,
      );
      continue;
    }

    const balanceCents = wallet.balanceCents || 0;
    const overdraftLimit = walletSettings.overdraftLimitCents;
    const totalAvailable = balanceCents + overdraftLimit;

    if (totalAvailable >= requiredAllowanceCents) {
      eligibleCandidates.push(candidate);
    } else {
      console.log(
          `[Dispatch] Candidate ${candidate.driverId} insufficient wallet: ` +
          `available=${totalAvailable}c, required=${requiredAllowanceCents}c`,
      );
    }
  }

  if (eligibleCandidates.length === 0) {
    console.log(
        `[Dispatch] Trip ${tripId}: No candidates met wallet requirement.`,
    );
    return [];
  }

  // 5. Calculate priority scores and sort highest first
  const driversWithPriority = eligibleCandidates.map((c) =>
    calculateDriverPriority(
        {
          driverId: c.driverId,
          ...c.driverData,
        },
        pickupLat,
        pickupLng,
        c.distance,
    ),
  );

  driversWithPriority.sort((a, b) => b.priorityScore - a.priorityScore);
  return driversWithPriority;
}

/**
 * Broadcasts FCM trip request notifications to a batch of candidate drivers.
 *
 * @param {Array<object>} driversBatch - Drivers to notify in this round.
 * @param {string} tripId - Trip document ID.
 * @param {object} tripData - Current trip document data.
 * @return {Promise<number>} Number of drivers successfully notified.
 */
async function sendNotificationsToDrivers(driversBatch, tripId, tripData) {
  const pickupLat = tripData.pickup.latitude;
  const pickupLng = tripData.pickup.longitude;

  console.log(
      `[Dispatch] Broadcasting trip ${tripId} to ` +
      `${driversBatch.length} driver(s):`,
  );
  driversBatch.forEach((driver, index) => {
    console.log(
        `  ${index + 1}. ${driver.driverName} (${driver.tier}) | ` +
        `Score: ${driver.priorityScore.toFixed(1)} | ` +
        `Dist: ${driver.distance.toFixed(2)}km`,
    );
  });

  const notifyResults = await Promise.allSettled(
      driversBatch
          .filter((driver) => driver.fcmToken)
          .map(async (driver) => {
            const message = buildMessage(
                driver,
                tripId,
                tripData,
                pickupLat,
                pickupLng,
            );
            await fcm.send(message);
            console.log(
                `✓ Notified driver ${driver.driverId} (${driver.tier}, ` +
                `${driver.priorityScore.toFixed(1)}pts, ` +
                `${driver.distance.toFixed(2)}km)`,
            );
          }),
  );

  notifyResults.forEach((result, i) => {
    if (result.status === "rejected") {
      console.error(
          `✗ Failed to notify driver at index ${i}:`,
          result.reason,
      );
    }
  });

  const successCount = notifyResults.filter(
      (r) => r.status === "fulfilled",
  ).length;
  console.log(
      `[Dispatch] Broadcast complete: ${successCount}/${driversBatch.length} ` +
      `notified.`,
  );
  return successCount;
}

/**
 * Claims a single dispatch round inside a Firestore transaction to guarantee
 * idempotency across at-least-once event/task deliveries.
 *
 * @param {string} tripId - Trip document ID.
 * @param {string} sessionId - Active dispatch session UUID.
 * @param {number} round - Round number (1..N).
 * @return {Promise<boolean>} True if round was claimed; false if duplicate.
 */
async function claimRound(tripId, sessionId, round) {
  const ref = db.collection("trips").doc(tripId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;

    const d = snap.data().dispatch || {};

    // A newer search session (TRY AGAIN) replaced this one -> stale, stop
    if (d.sessionId && d.sessionId !== sessionId) return false;

    // This round (or a later one) was already claimed -> duplicate, stop
    if ((d.lastRound || 0) >= round) return false;

    tx.update(ref, {dispatch: {sessionId, lastRound: round}});
    return true;
  });
}

/**
 * Enqueues the next dispatch round in Cloud Tasks with task-name deduplication.
 *
 * @param {string} tripId - Trip document ID.
 * @param {string} sessionId - Active dispatch session UUID.
 * @param {number} startedAt - Epoch ms when this dispatch session started.
 * @param {number} nextRound - Next round number.
 * @return {Promise<void>}
 */
async function enqueueNextRound(tripId, sessionId, startedAt, nextRound) {
  const queue = getFunctions().taskQueue("dispatchNextRound");
  await queue.enqueue(
      {tripId, sessionId, startedAt, round: nextRound},
      {
        scheduleDelaySeconds: DISPATCH_CONFIG.ROUND_DELAY_SECONDS,
        // Deterministic task ID prevents Cloud Tasks from accepting duplicates
        id: `${tripId}-${sessionId}-r${nextRound}`,
      },
  );
}

/**
 * Executes a single dispatch round (~1s) and schedules the next round.
 *
 * @param {string} tripId - Trip document ID.
 * @param {string} sessionId - Active dispatch session UUID.
 * @param {number} startedAt - Epoch ms when this dispatch session started.
 * @param {number} round - Current round number (1..N).
 * @return {Promise<void>}
 */
async function runDispatchRound(tripId, sessionId, startedAt, round) {
  try {
    // 1. Claim this round (per-round lock). Duplicate or stale -> exit.
    const claimed = await claimRound(tripId, sessionId, round);
    if (!claimed) {
      console.log(
          `[Dispatch] ${tripId} round ${round} already handled or stale, ` +
          `skipping.`,
      );
      return;
    }

    const ref = db.collection("trips").doc(tripId);
    const snap = await ref.get();
    if (!snap.exists) return;
    const trip = snap.data();

    // 2. Stop conditions
    if (trip.status === "cancelled") {
      console.log(`[Dispatch] Trip ${tripId} cancelled, stopping chain.`);
      return;
    }
    if (
      trip.status === "driver_accepted" ||
      trip.status === "driver_arrived" ||
      trip.status === "in_progress" ||
      trip.status === "completed" ||
      trip.claimedByDriverId
    ) {
      console.log(
          `[Dispatch] Trip ${tripId} already accepted/active, stopping chain.`,
      );
      return;
    }

    // 3. Deadline check (120 seconds)
    const elapsed = Date.now() - startedAt;
    if (elapsed > DISPATCH_CONFIG.MAX_SEARCH_DURATION_MS) {
      console.log(
          `[Dispatch] Trip ${tripId} reached 120s deadline. ` +
          `Setting no_drivers_available.`,
      );
      await ref.update({
        status: "no_drivers_available",
        noDriversAvailable: true,
        searchEndedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    // 4. Do ONE round of work
    const radius =
      elapsed > DISPATCH_CONFIG.EXPAND_AFTER_MS ?
        DISPATCH_CONFIG.EXPANDED_RADIUS_KM :
        DISPATCH_CONFIG.DEFAULT_RADIUS_KM;

    // Exclude all previously notified drivers AND drivers who declined
    const excludedDriverIds = new Set([
      ...(trip.notifiedDriverIds || []),
      ...(trip.declinedDriverIds || []),
    ]);

    const candidates = await findEligibleDriversForTrip(
        tripId,
        trip,
        radius,
        excludedDriverIds,
    );
    const batch = candidates.slice(0, DISPATCH_CONFIG.TOP_DRIVERS_PER_ROUND);

    if (batch.length > 0) {
      await ref.update({
        nearbyDrivers: candidates.map((d) => ({
          driverId: d.driverId,
          distance: d.distance,
          tier: d.tier,
          priorityScore: d.priorityScore,
          acceptanceRate: d.acceptanceRate,
        })),
        status: "driver_notified",
        notifiedDriverIds: admin.firestore.FieldValue.arrayUnion(
            ...batch.map((d) => d.driverId),
        ),
        claimedByDriverId: trip.claimedByDriverId || null,
        notifiedDriverTier: batch[0].tier,
        notifiedDriverPriority: batch[0].priorityScore,
        notificationTime: admin.firestore.FieldValue.serverTimestamp(),
        searchAttempts: round,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      });

      await sendNotificationsToDrivers(batch, tripId, trip);
    } else {
      await ref.update({
        status: "searching",
        searchAttempts: round,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // 5. Schedule the next round, then EXIT
    await enqueueNextRound(tripId, sessionId, startedAt, round + 1);
  } catch (error) {
    console.error(
        `[Dispatch] Error in runDispatchRound (${tripId}, round ${round}):`,
        error,
    );
    throw error;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cloud Function Entry Points
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Entry Point 1: Triggered when a new trip document is created -> Round 1.
 */
exports.findNearbyDrivers = onDocumentCreated(
    "trips/{tripId}",
    async (event) => {
      try {
        const tripId = event.params.tripId;
        const tripData = event.data ? event.data.data() : null;
        if (!tripData) return null;

        logDebug("New trip created", {tripId, status: tripData.status});

        const sessionId = crypto.randomUUID();
        await runDispatchRound(tripId, sessionId, Date.now(), 1);
        return null;
      } catch (error) {
        console.error("Error in findNearbyDrivers onCreate:", error);
        return null;
      }
    },
);

/**
 * Entry Point 2: Cloud Tasks handler for Rounds 2..N.
 */
exports.dispatchNextRound = onTaskDispatched(
    {
      retryConfig: {maxAttempts: 3, minBackoffSeconds: 5},
      rateLimits: {maxConcurrentDispatches: 50},
    },
    async (req) => {
      const {tripId, sessionId, startedAt, round} = req.data;
      await runDispatchRound(tripId, sessionId, startedAt, round);
    },
);

/**
 * Entry Point 3: Triggered when rider taps TRY AGAIN
 * (status transitions from "no_drivers_available" -> "searching").
 */
exports.restartDispatch = onDocumentUpdated(
    "trips/{tripId}",
    async (event) => {
      try {
        const before = event.data.before.data();
        const after = event.data.after.data();
        if (
          before.status === "no_drivers_available" &&
          after.status === "searching"
        ) {
          const tripId = event.params.tripId;
          const sessionId = crypto.randomUUID();
          console.log(
              `[Dispatch] Restarting dispatch for trip ${tripId} ` +
              `with new session ${sessionId}`,
          );
          // Reset session and notifiedDriverIds, but preserve declinedDriverIds
          await event.data.after.ref.update({
            notifiedDriverIds: [],
            dispatch: {sessionId, lastRound: 0},
          });
          await runDispatchRound(tripId, sessionId, Date.now(), 1);
        }
        return null;
      } catch (error) {
        console.error("Error in restartDispatch onUpdate:", error);
        return null;
      }
    },
);

// Export internals for unit/simulation testing
exports._internal = {
  DISPATCH_CONFIG,
  VEHICLE_TYPES,
  GENDER,
  calculateDistance,
  calculateDriverPriority,
  buildMessage,
  findEligibleDriversForTrip,
  sendNotificationsToDrivers,
  claimRound,
  enqueueNextRound,
  runDispatchRound,
};

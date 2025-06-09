/* eslint-disable linebreak-style */
// eslint-disable-next-line linebreak-style
/* eslint-disable indent */
/* eslint-disable linebreak-style */
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall} = require("firebase-functions/v2/https");
const {admin, db} = require("./adminConfig"); // Use shared config

// Function to calculate hotspots - runs every hour
exports.calculateHotspots = onSchedule("every 1 hours", async (event) => {
  try {
    console.log("Starting hotspot calculation...");
    // Get completed trips from last 30 days
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    // Convert to Firestore Timestamp for proper comparison
    // eslint-disable-next-line max-len
    const thirtyDaysAgoTimestamp = admin.firestore.Timestamp.fromDate(thirtyDaysAgo);
    const tripsSnapshot = await db.collection("trips")
      .where("status", "==", "completed")
      // eslint-disable-next-line max-len
      .where("createdAt", ">=", thirtyDaysAgoTimestamp) // Changed from "timestamp" to "createdAt"
      .get();
    console.log(`Found ${tripsSnapshot.size} completed trips`);
    if (tripsSnapshot.empty) {
      console.log("No trips found for hotspot calculation");
      return {success: true, message: "No trips found"};
    }
    // Extract pickup locations
    const pickupLocations = [];
    tripsSnapshot.forEach((doc) => {
      const trip = doc.data();
      if (trip.pickup && trip.pickup.latitude && trip.pickup.longitude) {
        pickupLocations.push({
          lat: trip.pickup.latitude,
          lng: trip.pickup.longitude,
          // eslint-disable-next-line max-len
          timestamp: trip.createdAt, // Changed from trip.timestamp to trip.createdAt
          tripId: doc.id,
        });
      }
    });
    console.log(`Extracted ${pickupLocations.length} valid pickup locations`);
    if (pickupLocations.length === 0) {
      console.log("No valid pickup locations found");
      return {success: true, message: "No valid pickup locations"};
    }
    // Calculate hotspots using clustering algorithm
    const hotspots = calculateHotspotsFromLocations(pickupLocations);
    // Clear existing hotspots
    const hotspotsRef = db.collection("hotspots");
    const existingHotspots = await hotspotsRef.get();
    const batch = db.batch();
    existingHotspots.forEach((doc) => {
      batch.delete(doc.ref);
    });
    // Add new hotspots
    hotspots.forEach((hotspot, index) => {
      const hotspotRef = hotspotsRef.doc(`hotspot_${index}`);
      batch.set(hotspotRef, {
        ...hotspot,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    await batch.commit();
    console.log(`Updated ${hotspots.length} hotspots`);
    return {success: true, hotspotsCount: hotspots.length};
  } catch (error) {
    console.error("Error calculating hotspots:", error);
    // For scheduled functions, don't throw - return error info instead
    return {success: false, error: error.message};
  }
});

// Helper function to calculate hotspots
// eslint-disable-next-line require-jsdoc
function calculateHotspotsFromLocations(locations) {
  const hotspots = [];
  const gridSize = 0.01; // ~1km grid
  const minTripsForHotspot = 1; // Reduced for testing - change back to 10 later
  // Create grid-based clustering
  const grid = {};

  locations.forEach((location) => {
    const gridX = Math.floor(location.lat / gridSize);
    const gridY = Math.floor(location.lng / gridSize);
    const key = `${gridX}_${gridY}`;

    if (!grid[key]) {
      grid[key] = {
        locations: [],
        centerLat: (gridX + 0.5) * gridSize,
        centerLng: (gridY + 0.5) * gridSize,
        count: 0,
      };
    }

    grid[key].locations.push(location);
    grid[key].count++;
  });

  // Convert grid cells to hotspots
  Object.values(grid).forEach((cell) => {
    if (cell.count >= minTripsForHotspot) {
      // Calculate actual center of locations
      // eslint-disable-next-line max-len
      const avgLat = cell.locations.reduce((sum, loc) => sum + loc.lat, 0) / cell.count;
      // eslint-disable-next-line max-len
      const avgLng = cell.locations.reduce((sum, loc) => sum + loc.lng, 0) / cell.count;

      let intensity = "low";
      // eslint-disable-next-line max-len
      if (cell.count >= 20) intensity = "high"; // Reduced thresholds for testing
      else if (cell.count >= 10) intensity = "medium";

      hotspots.push({
        center: {
          latitude: avgLat,
          longitude: avgLng,
        },
        radius: 2000, // 2km radius
        tripCount: cell.count,
        intensity: intensity,
      });
    }
  });

  return hotspots;
}

// HTTP function to get hotspots (for real-time requests)
exports.getHotspots = onCall(async (request) => {
  try {
    // Check if user is authenticated (optional for testing)
    if (!request.auth) {
      console.log("Warning: Unauthenticated request for hotspots");
      // Uncomment to require authentication:
      // throw new Error("User must be authenticated");
    }

    const hotspotsSnapshot = await db.collection("hotspots").get();
    const hotspots = [];

    hotspotsSnapshot.forEach((doc) => {
      hotspots.push({
        id: doc.id,
        ...doc.data(),
      });
    });

    console.log(`Returning ${hotspots.length} hotspots`);
    return {hotspots, count: hotspots.length};
  } catch (error) {
    console.error("Error getting hotspots:", error);
    throw new Error("Error retrieving hotspots");
  }
});

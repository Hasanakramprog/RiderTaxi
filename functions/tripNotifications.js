const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {admin, db, fcm} = require("./adminConfig");

/**
 * Sends a push notification to the rider when their trip status changes.
 */
exports.onTripStatusChanged = onDocumentUpdated(
    "trips/{tripId}",
    async (event) => {
      const beforeData = event.data.before ? event.data.before.data() : null;
      const afterData = event.data.after ? event.data.after.data() : null;
      const tripId = event.params.tripId;

      if (!beforeData || !afterData) {
        return null;
      }

      // Only trigger if status actually changed
      if (beforeData.status === afterData.status) {
        return null;
      }

      const riderId = afterData.userId || afterData.riderId;
      if (!riderId) {
        console.log(`Trip ${tripId} has no rider ID attached.`);
        return null;
      }

      const newStatus = afterData.status;
      let title = "";
      let body = "";

      switch (newStatus) {
        case "driver_accepted": {
          const driverName = afterData.driverName || "A driver";
          const vehicleInfo = afterData.carModel ?
            ` in a ${afterData.carModel}` :
            "";
          title = "Driver Found! 🚗";
          body = `${driverName}${vehicleInfo} has accepted your ride and is on the way.`;
          break;
        }
        case "driver_arrived": {
          const driverName = afterData.driverName || "Your driver";
          title = "Driver Arrived! 📍";
          body = `${driverName} has arrived at your pickup location.`;
          break;
        }
        case "in_progress": {
          title = "Trip Started 🛣️";
          body = "Your ride is underway. Have a safe journey!";
          break;
        }
        case "completed": {
          const fare = afterData.fare ? `$${Number(afterData.fare).toFixed(2)}` : "";
          title = "Trip Completed 🎉";
          body = fare ?
            `You have arrived at your destination. Total fare: ${fare}.` :
            "You have arrived at your destination. Thank you for riding!";
          break;
        }
        case "cancelled": {
          const reason = afterData.cancelledReason || afterData.cancelReason;
          title = "Trip Cancelled ❌";
          body = reason ?
            `Your trip was cancelled: ${reason}` :
            "Your trip has been cancelled.";
          break;
        }
        case "no_drivers_available": {
          title = "No Drivers Available ⚠️";
          body = "We could not find a nearby driver. Please try again shortly.";
          break;
        }
        default:
          // Unmonitored status change
          return null;
      }

      try {
        // Fetch rider's user profile to obtain FCM registration token
        const riderDoc = await db.collection("users").doc(riderId).get();
        if (!riderDoc.exists) {
          console.log(`Rider document users/${riderId} not found.`);
          return null;
        }

        const fcmToken = riderDoc.data().fcmToken;
        if (!fcmToken) {
          console.log(`No FCM token registered for rider ${riderId}.`);
          return null;
        }

        const message = {
          token: fcmToken,
          notification: {
            title: title,
            body: body,
          },
          data: {
            tripId: tripId,
            status: String(newStatus),
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
          android: {
            priority: "high",
            notification: {
              channelId: "high_importance_channel",
              sound: "default",
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
          apns: {
            payload: {
              aps: {
                alert: {
                  title: title,
                  body: body,
                },
                sound: "default",
                badge: 1,
              },
            },
          },
        };

        console.log(`Sending FCM notification to rider ${riderId} for trip ${tripId} (${newStatus})`);
        const response = await fcm.send(message);
        console.log(`Successfully sent message to rider: ${response}`);
        return response;
      } catch (error) {
        console.error(`Error sending push notification for trip ${tripId}:`, error);

        // Remove stale/unregistered token if device unregistered
        if (
          error.code === "messaging/registration-token-not-registered" ||
          error.code === "messaging/invalid-registration-token"
        ) {
          console.log(`Cleaning up invalid FCM token for rider ${riderId}`);
          await db.collection("users").doc(riderId).update({
            fcmToken: admin.firestore.FieldValue.delete(),
          });
        }
        return null;
      }
    },
);

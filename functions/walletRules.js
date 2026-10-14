/**
 * walletRules.js
 * Pure business logic and extension points for driver wallet charging.
 * Section 9 of specification.
 */

// Terminal statuses that trigger completion/cancellation evaluation
const TERMINAL_TRIP_STATUSES = Object.freeze([
  "completed",
  "cancelled",
]);

// Ledger reason codes
const LEDGER_REASONS = Object.freeze({
  COMPLETED: "completed",
  NO_FARE: "no_fare",
  CANCELLED_NO_CHARGE: "cancelled_no_charge",
  TOPUP: "topup",
  ADJUSTMENT: "adjustment",
  INITIAL_CREDIT: "initial_credit",
  SUSPENDED: "suspended",
  UNSUSPENDED: "unsuspended",
});

/**
 * Computes chargeable allowance cents for a trip.
 * Currently only completed trips are charged their full final fare (excluding tips if separated).
 *
 * @param {object} trip - The trip document data.
 * @returns {{ cents: number, reason: string }}
 */
function computeChargeableCents(trip) {
  if (!trip) {
    return { cents: 0, reason: LEDGER_REASONS.NO_FARE };
  }

  const status = trip.status;

  if (status === "completed") {
    // Fare field: trip.fare or trip.finalFare or trip.actualFare
    // If tips are ever separated in trip.tip / trip.tipAmount, we exclude them.
    const rawFare = Number(trip.fare != null ? trip.fare : trip.finalFare);

    if (isNaN(rawFare) || rawFare <= 0) {
      return { cents: 0, reason: LEDGER_REASONS.NO_FARE };
    }

    // Convert fare to integer cents
    const cents = Math.round(rawFare * 100);
    return { cents, reason: LEDGER_REASONS.COMPLETED };
  }

  if (status === "cancelled") {
    // Phase 1: Cancelled trips are not charged
    return { cents: 0, reason: LEDGER_REASONS.CANCELLED_NO_CHARGE };
  }

  return { cents: 0, reason: "unhandled_status" };
}

module.exports = {
  TERMINAL_TRIP_STATUSES,
  LEDGER_REASONS,
  computeChargeableCents,
};

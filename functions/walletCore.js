/**
 * walletCore.js
 * Centralized settings defaults, validation, and driver mirror field computation.
 */

const DEFAULT_WALLET_SETTINGS = Object.freeze({
  commissionRate: 0.20,
  overdraftLimitCents: 1000, // $10.00
  dispatchBufferMultiplier: 1.25,
  lowBalanceWarnCents: [2000, 1000], // $20.00, $10.00
  currency: "USD",
  supportPhone: "",
  supportWhatsapp: "",
});

/**
 * Returns merged settings falling back to sensible defaults.
 * @param {object|null} data
 * @returns {object}
 */
function getEffectiveSettings(data) {
  if (!data) return { ...DEFAULT_WALLET_SETTINGS };

  const commissionRate =
    typeof data.commissionRate === "number" &&
    data.commissionRate >= 0.01 &&
    data.commissionRate <= 0.90
      ? data.commissionRate
      : DEFAULT_WALLET_SETTINGS.commissionRate;

  const overdraftLimitCents =
    Number.isInteger(data.overdraftLimitCents) &&
    data.overdraftLimitCents >= 0 &&
    data.overdraftLimitCents <= 10000
      ? data.overdraftLimitCents
      : DEFAULT_WALLET_SETTINGS.overdraftLimitCents;

  const dispatchBufferMultiplier =
    typeof data.dispatchBufferMultiplier === "number" &&
    data.dispatchBufferMultiplier >= 1.0 &&
    data.dispatchBufferMultiplier <= 3.0
      ? data.dispatchBufferMultiplier
      : DEFAULT_WALLET_SETTINGS.dispatchBufferMultiplier;

  let lowBalanceWarnCents = DEFAULT_WALLET_SETTINGS.lowBalanceWarnCents;
  if (Array.isArray(data.lowBalanceWarnCents) && data.lowBalanceWarnCents.length > 0) {
    const valid = data.lowBalanceWarnCents
      .map((x) => Number(x))
      .filter((x) => Number.isInteger(x) && x > 0);
    if (valid.length > 0) {
      lowBalanceWarnCents = valid.sort((a, b) => b - a);
    }
  }

  return {
    commissionRate,
    overdraftLimitCents,
    dispatchBufferMultiplier,
    lowBalanceWarnCents,
    currency: typeof data.currency === "string" ? data.currency : "USD",
    supportPhone: typeof data.supportPhone === "string" ? data.supportPhone : "",
    supportWhatsapp: typeof data.supportWhatsapp === "string" ? data.supportWhatsapp : "",
  };
}

/**
 * Validates payload for updating wallet settings.
 * Throws an Error with a descriptive message if invalid.
 */
function validateSettingsPayload(payload) {
  if (!payload || typeof payload !== "object") {
    throw new Error("Invalid settings payload.");
  }

  const {
    commissionRate,
    overdraftLimitCents,
    dispatchBufferMultiplier,
    lowBalanceWarnCents,
  } = payload;

  if (
    typeof commissionRate !== "number" ||
    commissionRate < 0.01 ||
    commissionRate > 0.90
  ) {
    throw new Error("Commission rate must be between 1% (0.01) and 90% (0.90).");
  }

  if (
    !Number.isInteger(overdraftLimitCents) ||
    overdraftLimitCents < 0 ||
    overdraftLimitCents > 10000
  ) {
    throw new Error("Overdraft limit must be an integer between 0 and 10,000 cents ($100).");
  }

  if (
    typeof dispatchBufferMultiplier !== "number" ||
    dispatchBufferMultiplier < 1.0 ||
    dispatchBufferMultiplier > 3.0
  ) {
    throw new Error("Dispatch buffer multiplier must be between 1.00 and 3.00.");
  }

  if (
    !Array.isArray(lowBalanceWarnCents) ||
    lowBalanceWarnCents.length === 0 ||
    !lowBalanceWarnCents.every((x) => Number.isInteger(x) && x > 0)
  ) {
    throw new Error("Low balance warnings must be a non-empty array of positive integer cents.");
  }
}

/**
 * Recomputes walletCanWork and walletStatus mirror fields.
 * Used everywhere: topup, adjust, charge, settings change, and migration.
 *
 * @param {object} params
 * @param {number} params.balanceCents - Current driver wallet balance
 * @param {number} params.overdraftLimitCents - Current effective overdraft limit
 * @param {boolean} params.suspended - True if driver wallet is suspended
 * @param {number[]} [params.lowBalanceWarnCents] - Array of warning thresholds
 * @returns {{ walletCanWork: boolean, walletStatus: "active"|"low"|"locked"|"suspended" }}
 */
function computeWalletMirror({
  balanceCents = 0,
  overdraftLimitCents = 1000,
  suspended = false,
  lowBalanceWarnCents = [2000, 1000],
}) {
  if (suspended) {
    return {
      walletCanWork: false,
      walletStatus: "suspended",
    };
  }

  const effectiveAvailable = balanceCents + overdraftLimitCents;
  const walletCanWork = effectiveAvailable > 0;

  if (!walletCanWork) {
    return {
      walletCanWork: false,
      walletStatus: "locked",
    };
  }

  // Check if balance is low (below the highest warning threshold)
  const warnThreshold = Math.max(...(lowBalanceWarnCents || [2000]));
  if (balanceCents <= warnThreshold) {
    return {
      walletCanWork: true,
      walletStatus: "low",
    };
  }

  return {
    walletCanWork: true,
    walletStatus: "active",
  };
}

module.exports = {
  DEFAULT_WALLET_SETTINGS,
  getEffectiveSettings,
  validateSettingsPayload,
  computeWalletMirror,
};

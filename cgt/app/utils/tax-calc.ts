// ─── Belgian CGT Calculator – Pure Tax Logic ─────────────────────
// Based on the law approved 3 April 2026 by the Belgian Chamber.

export const CGT_RATE = 0.10;
export const CGT_EXEMPTION = 10_000;
export const CARRY_FORWARD_PER_YEAR = 1_000; // 1/10th of base exemption
export const MAX_CARRY_FORWARD = 5_000; // max 5 years of carry-forward

export const TOB = {
  shares: { rate: 0.0012, cap: 1300 },
  bonds: { rate: 0.0012, cap: 1300 },
  etfAccHigh: { rate: 0.0132, cap: 4000 },
  etfAccLow: { rate: 0.0012, cap: 1300 },
  etfDist: { rate: 0.0012, cap: 1300 },
} as const;

export type TobCategory = keyof typeof TOB;

export interface YearResult {
  year: number;
  portfolioValue: number;
  unrealizedGain: number;
  realizedGain: number;
  cgtDue: number;
  tobPaid: number;
  netPortfolioAfterTax: number;
  exemptionUsed: number;
  carryForward: number;
  refundReceived: number;
}

export function calcTob(amount: number, category: TobCategory): number {
  const { rate, cap } = TOB[category];
  return Math.min(amount * rate, cap);
}

/**
 * Compute the effective exemption for a given year, accounting for carry-forward.
 * Returns { effectiveExemption, newCarryForward }.
 *
 * Rules:
 * - Base exemption = €10,000/year
 * - If not fully used: carry over €1,000 to next year (up to €5,000 max)
 * - When used: oldest carry-forward is consumed first (FIFO)
 */
export function computeExemption(
  gain: number,
  carryForward: number,
): { effectiveExemption: number; newCarryForward: number } {
  const totalExemption = CGT_EXEMPTION + carryForward;

  if (gain >= totalExemption) {
    // Fully used all exemption + carry-forward
    return { effectiveExemption: totalExemption, newCarryForward: 0 };
  }

  // Didn't fully use exemption → carry over €1,000
  const newCF = Math.min(carryForward + CARRY_FORWARD_PER_YEAR, MAX_CARRY_FORWARD);
  return { effectiveExemption: totalExemption, newCarryForward: newCF };
}

// ─── Scenario: Hold ──────────────────────────────────────────────
// Buy and hold until final sale at end of period.
// No CGT or TOB paid until the very end.
// Exemption accumulates each unused year.
export function holdScenario(
  portfolioValue: number,
  costBasis: number,
  expectedReturn: number,
  years: number,
  tobCategory: TobCategory,
  _brokerMode: 'opt-in' | 'opt-out',
  yearlyContribution = 0,
): YearResult[] {
  const results: YearResult[] = [];
  let value = portfolioValue;
  let basis = costBasis;
  let carryForward = 0;

  for (let y = 1; y <= years; y++) {
    // Add yearly contribution at start of year (new money = new cost basis)
    if (yearlyContribution > 0) {
      value += yearlyContribution;
      basis += yearlyContribution;
    }
    value *= 1 + expectedReturn;
    const ug = Math.max(0, value - basis);

    // Each year we don't sell → exemption carry-forward accumulates
    carryForward = Math.min(carryForward + CARRY_FORWARD_PER_YEAR, MAX_CARRY_FORWARD);

    // At final year, compute the CGT + TOB for the exit sale
    if (y === years) {
      const { effectiveExemption } = computeExemption(ug, carryForward);
      const cgt = Math.max(0, ug - effectiveExemption) * CGT_RATE;
      const tob = calcTob(value, tobCategory);
      results.push({
        year: y, portfolioValue: value, unrealizedGain: 0,
        realizedGain: ug, cgtDue: cgt, tobPaid: tob,
        netPortfolioAfterTax: value - cgt - tob,
        exemptionUsed: Math.min(ug, effectiveExemption),
        carryForward: 0, refundReceived: 0,
      });
    } else {
      results.push({
        year: y, portfolioValue: value, unrealizedGain: ug,
        realizedGain: 0, cgtDue: 0, tobPaid: 0,
        netPortfolioAfterTax: value,
        exemptionUsed: 0, carryForward,
        refundReceived: 0,
      });
    }
  }
  return results;
}

// ─── Scenario: Full Harvest ──────────────────────────────────────
// Sell everything each year and rebuy. Realizes all gains annually.
export function harvestScenario(
  portfolioValue: number,
  costBasis: number,
  expectedReturn: number,
  years: number,
  tobCategory: TobCategory,
  brokerMode: 'opt-in' | 'opt-out',
  yearlyContribution = 0,
): YearResult[] {
  const results: YearResult[] = [];
  let value = portfolioValue;
  let basis = costBasis;
  let carryForward = 0;
  // Pending refunds for broker mode (arrive ~2 years later)
  const pendingRefunds: number[] = [];

  for (let y = 1; y <= years; y++) {
    // Add yearly contribution at start of year
    if (yearlyContribution > 0) {
      value += yearlyContribution;
      basis += yearlyContribution;
    }
    value *= 1 + expectedReturn;

    // Receive pending refund from 2 years ago (broker mode)
    let refundReceived = 0;
    if (pendingRefunds.length > 0) {
      refundReceived = pendingRefunds.shift()!;
      value += refundReceived;
      basis += refundReceived; // refund is not a gain — it's returned overpaid tax
    }

    // Losses cannot be carried forward to future years (Belgian law)
    const gain = Math.max(0, value - basis);

    const { effectiveExemption, newCarryForward } = computeExemption(
      gain, carryForward,
    );
    carryForward = newCarryForward;

    let cgt: number;
    if (brokerMode === 'opt-in') {
      // Broker withholds 10% of full gain (no exemption, no loss offset)
      cgt = gain * CGT_RATE;
      // Schedule refund for overpaid amount (will arrive ~2 years later)
      const correctTax = Math.max(0, gain - effectiveExemption) * CGT_RATE;
      const overpaid = cgt - correctTax;
      if (overpaid > 0) {
        pendingRefunds.push(overpaid);
      }
    } else {
      // Self-report: apply exemption immediately
      const taxable = Math.max(0, gain - effectiveExemption);
      cgt = taxable * CGT_RATE;
    }

    const ts = calcTob(value, tobCategory);
    const tb = calcTob(value - cgt - ts, tobCategory);
    const tt = ts + tb;
    const total = cgt + tt;

    value -= total;
    basis = value;

    results.push({
      year: y, portfolioValue: value, unrealizedGain: 0,
      realizedGain: gain, cgtDue: cgt, tobPaid: tt,
      netPortfolioAfterTax: value,
      exemptionUsed: brokerMode === 'opt-out' ? Math.min(gain, effectiveExemption) : 0,
      carryForward, refundReceived,
    });
  }

  // Flush remaining pending refunds into final result
  const totalPending = pendingRefunds.reduce((s, r) => s + r, 0);
  if (totalPending > 0 && results.length > 0) {
    const last = results[results.length - 1]!;
    last.netPortfolioAfterTax += totalPending;
    last.refundReceived += totalPending;
  }

  return results;
}

// ─── Scenario: Smart Harvest ─────────────────────────────────────
// Sell only enough each year to use the tax-free exemption.
export function smartScenario(
  portfolioValue: number,
  costBasis: number,
  expectedReturn: number,
  years: number,
  tobCategory: TobCategory,
  brokerMode: 'opt-in' | 'opt-out',
  yearlyContribution = 0,
): YearResult[] {
  const results: YearResult[] = [];
  let value = portfolioValue;
  let basis = costBasis;
  let carryForward = 0;
  const pendingRefunds: number[] = [];

  for (let y = 1; y <= years; y++) {
    // Add yearly contribution at start of year
    if (yearlyContribution > 0) {
      value += yearlyContribution;
      basis += yearlyContribution;
    }
    value *= 1 + expectedReturn;

    // Receive pending refund from 2 years ago (broker mode)
    let refundReceived = 0;
    if (pendingRefunds.length > 0) {
      refundReceived = pendingRefunds.shift()!;
      value += refundReceived;
      basis += refundReceived; // refund is not a gain — it's returned overpaid tax
    }

    const totalGain = Math.max(0, value - basis);
    if (totalGain <= 0) {
      carryForward = Math.min(carryForward + CARRY_FORWARD_PER_YEAR, MAX_CARRY_FORWARD);
      results.push({
        year: y, portfolioValue: value, unrealizedGain: 0,
        realizedGain: 0, cgtDue: 0, tobPaid: 0,
        netPortfolioAfterTax: value,
        exemptionUsed: 0, carryForward, refundReceived,
      });
      continue;
    }

    const effectiveExemption = CGT_EXEMPTION + carryForward;
    // Final year: sell everything (exit). Otherwise: sell just enough to use exemption.
    const isFinalYear = y === years;
    const frac = isFinalYear ? 1 : Math.min(1, effectiveExemption / totalGain);
    const sell = value * frac;
    const rg = totalGain * frac;
    const taxable = Math.max(0, rg - effectiveExemption);

    let cgt: number;
    if (brokerMode === 'opt-in') {
      // Broker withholds 10% of realized gain (ignores exemption)
      cgt = rg * CGT_RATE;
      const correctTax = taxable * CGT_RATE;
      const overpaid = cgt - correctTax;
      if (overpaid > 0) {
        pendingRefunds.push(overpaid);
      }
    } else {
      cgt = taxable * CGT_RATE;
    }

    const ts = calcTob(sell, tobCategory);
    const tb = calcTob(sell - cgt - ts, tobCategory);
    const tt = ts + tb;
    const tax = cgt + tt;

    const unsold = value - sell;
    const uBasis = basis * (1 - frac);
    const rebuy = sell - tax;
    basis = uBasis + rebuy;
    value = unsold + rebuy;

    // Smart harvest tries to use exactly the exemption → no carry-forward builds
    if (taxable === 0 && rg < effectiveExemption) {
      carryForward = Math.min(carryForward + CARRY_FORWARD_PER_YEAR, MAX_CARRY_FORWARD);
    } else {
      carryForward = 0;
    }

    results.push({
      year: y, portfolioValue: value, unrealizedGain: Math.max(0, value - basis),
      realizedGain: rg, cgtDue: cgt, tobPaid: tt,
      netPortfolioAfterTax: value,
      exemptionUsed: brokerMode === 'opt-out' ? Math.min(rg, effectiveExemption) : 0,
      carryForward, refundReceived,
    });
  }

  // Flush remaining pending refunds into final result
  const totalPending = pendingRefunds.reduce((s, r) => s + r, 0);
  if (totalPending > 0 && results.length > 0) {
    const last = results[results.length - 1]!;
    last.netPortfolioAfterTax += totalPending;
    last.refundReceived += totalPending;
  }

  return results;
}

// ─── Final net values (after exit sale) ──────────────────────────

export function holdFinalNet(results: YearResult[]): number {
  return results.at(-1)?.netPortfolioAfterTax ?? 0;
}

export function harvestFinalNet(results: YearResult[]): number {
  return results.at(-1)?.netPortfolioAfterTax ?? 0;
}

export function smartFinalNet(results: YearResult[]): number {
  return results.at(-1)?.netPortfolioAfterTax ?? 0;
}

export function holdTotalTax(results: YearResult[]): number {
  return results.reduce((s, r) => s + r.cgtDue + r.tobPaid, 0);
}

export function harvestTotalTax(results: YearResult[]): number {
  return results.reduce((s, r) => s + r.cgtDue + r.tobPaid - r.refundReceived, 0);
}

export function smartTotalTax(results: YearResult[]): number {
  return results.reduce((s, r) => s + r.cgtDue + r.tobPaid - r.refundReceived, 0);
}

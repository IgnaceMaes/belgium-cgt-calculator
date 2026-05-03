// ─── Belgian CGT Calculator – Pure Tax Logic ─────────────────────
// Based on the law approved 3 April 2026 by the Belgian Chamber.

export const CGT_RATE = 0.1;
export const CGT_EXEMPTION = 10_000;
export const CARRY_FORWARD_PER_YEAR = 1_000; // 1/10th of base exemption
export const MAX_CARRY_FORWARD = 5_000; // max 5 years of carry-forward

// Taks op effectenrekeningen (portfolio tax)
export const PORTFOLIO_TAX_RATE = 0.0015; // 0.15%
export const PORTFOLIO_TAX_THRESHOLD = 1_000_000; // €1M

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
  portfolioTax: number;
  netPortfolioAfterTax: number;
  exemptionUsed: number;
  carryForward: number;
  refundReceived: number;
}

export function calcPortfolioTax(
  value: number,
  includePortfolioTax: boolean,
): number {
  if (!includePortfolioTax) return 0;
  return value >= PORTFOLIO_TAX_THRESHOLD ? value * PORTFOLIO_TAX_RATE : 0;
}

export function calcTob(amount: number, category: TobCategory): number {
  const { rate, cap } = TOB[category];
  return Math.min(Math.max(0, amount) * rate, cap);
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
  const newCF = Math.min(
    carryForward + CARRY_FORWARD_PER_YEAR,
    MAX_CARRY_FORWARD,
  );
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
  brokerMode: 'opt-in' | 'opt-out',
  yearlyContribution = 0,
  includePortfolioTax = false,
  cgtRate = CGT_RATE,
): YearResult[] {
  const results: YearResult[] = [];
  let value = portfolioValue;
  let basis = costBasis;
  let carryForward = 0;
  const pendingRefunds: number[] = [];

  for (let y = 1; y <= years; y++) {
    let withdrawalGain = 0;
    let withdrawalTob = 0;

    if (yearlyContribution > 0) {
      value += yearlyContribution;
      basis += yearlyContribution;
    } else if (yearlyContribution < 0 && value > 0) {
      // Withdrawal = partial sale. Taxes come from sale proceeds, not remaining shares.
      const actual = Math.min(-yearlyContribution, value);
      const frac = actual / value;
      const soldBasis = basis * frac;
      withdrawalGain = Math.max(0, actual - soldBasis);
      withdrawalTob = calcTob(actual, tobCategory);
      // Remaining portfolio: only remove the sold shares (taxes paid from proceeds)
      value -= actual;
      basis -= soldBasis;
    }

    // Receive pending refund from broker (arrives ~2 years later)
    let refundReceived = 0;
    if (pendingRefunds.length > 0) {
      refundReceived = pendingRefunds.shift()!;
      value += refundReceived;
      basis += refundReceived;
    }

    // Apply return on remaining portfolio
    value *= 1 + expectedReturn;
    const ug = Math.max(0, value - basis);

    // Portfolio tax
    const ptax = calcPortfolioTax(value, includePortfolioTax);
    value -= ptax;

    const isFinalYear = y === years;

    if (isFinalYear) {
      // Exit: sell everything. Combine withdrawal + exit gains for ONE annual exemption.
      const totalRealized = withdrawalGain + ug;
      const { effectiveExemption } = computeExemption(totalRealized, carryForward);

      let cgt: number;
      if (brokerMode === 'opt-in') {
        cgt = totalRealized * cgtRate;
        const correctTax = Math.max(0, totalRealized - effectiveExemption) * cgtRate;
        const overpaid = cgt - correctTax;
        if (overpaid > 0) pendingRefunds.push(overpaid);
      } else {
        cgt = Math.max(0, totalRealized - effectiveExemption) * cgtRate;
      }

      const exitTob = calcTob(value, tobCategory);

      results.push({
        year: y,
        portfolioValue: value,
        unrealizedGain: 0,
        realizedGain: totalRealized,
        cgtDue: cgt,
        tobPaid: exitTob + withdrawalTob,
        portfolioTax: ptax,
        netPortfolioAfterTax: value - cgt - exitTob,
        exemptionUsed: Math.min(totalRealized, effectiveExemption),
        carryForward: 0,
        refundReceived,
      });
    } else {
      // Non-final year: only the withdrawal is a realization event
      const { effectiveExemption, newCarryForward } = computeExemption(withdrawalGain, carryForward);

      let cgt = 0;
      if (withdrawalGain > 0) {
        if (brokerMode === 'opt-in') {
          cgt = withdrawalGain * cgtRate;
          const correctTax = Math.max(0, withdrawalGain - effectiveExemption) * cgtRate;
          const overpaid = cgt - correctTax;
          if (overpaid > 0) pendingRefunds.push(overpaid);
        } else {
          cgt = Math.max(0, withdrawalGain - effectiveExemption) * cgtRate;
        }
      }

      carryForward = newCarryForward;

      results.push({
        year: y,
        portfolioValue: value,
        unrealizedGain: ug,
        realizedGain: withdrawalGain,
        cgtDue: cgt,
        tobPaid: withdrawalTob,
        portfolioTax: ptax,
        netPortfolioAfterTax: value,
        exemptionUsed: withdrawalGain > 0 ? Math.min(withdrawalGain, effectiveExemption) : 0,
        carryForward,
        refundReceived,
      });
    }
  }

  // Flush remaining pending refunds
  const totalPending = pendingRefunds.reduce((s, r) => s + r, 0);
  if (totalPending > 0 && results.length > 0) {
    const last = results[results.length - 1]!;
    last.netPortfolioAfterTax += totalPending;
    last.refundReceived += totalPending;
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
  includePortfolioTax = false,
  cgtRate = CGT_RATE,
): YearResult[] {
  const results: YearResult[] = [];
  let value = portfolioValue;
  let basis = costBasis;
  let carryForward = 0;
  // Pending refunds for broker mode (arrive ~2 years later)
  const pendingRefunds: number[] = [];

  for (let y = 1; y <= years; y++) {
    // Contribution: add new capital + cost basis
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
      gain,
      carryForward,
    );
    carryForward = newCarryForward;

    let cgt: number;
    if (brokerMode === 'opt-in') {
      // Broker withholds 10% of full gain (no exemption, no loss offset)
      cgt = gain * cgtRate;
      // Schedule refund for overpaid amount (will arrive ~2 years later)
      const correctTax = Math.max(0, gain - effectiveExemption) * cgtRate;
      const overpaid = cgt - correctTax;
      if (overpaid > 0) {
        pendingRefunds.push(overpaid);
      }
    } else {
      // Self-report: apply exemption immediately
      const taxable = Math.max(0, gain - effectiveExemption);
      cgt = taxable * cgtRate;
    }

    const ts = calcTob(value, tobCategory);
    const tb = calcTob(value - cgt - ts, tobCategory);
    const tt = ts + tb;
    const ptax = calcPortfolioTax(value, includePortfolioTax);
    const total = cgt + tt + ptax;

    value -= total;
    // Withdrawal: taken from proceeds after selling (reduces rebuy amount)
    if (yearlyContribution < 0) {
      const withdrawal = Math.min(-yearlyContribution, value);
      value -= withdrawal;
    }
    basis = value;

    results.push({
      year: y,
      portfolioValue: value,
      unrealizedGain: 0,
      realizedGain: gain,
      cgtDue: cgt,
      tobPaid: tt,
      portfolioTax: ptax,
      netPortfolioAfterTax: value,
      exemptionUsed:
        brokerMode === 'opt-out' ? Math.min(gain, effectiveExemption) : 0,
      carryForward,
      refundReceived,
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
  includePortfolioTax = false,
  cgtRate = CGT_RATE,
): YearResult[] {
  const results: YearResult[] = [];
  let value = portfolioValue;
  let basis = costBasis;
  let carryForward = 0;
  const pendingRefunds: number[] = [];

  for (let y = 1; y <= years; y++) {
    // Contribution: add new capital + cost basis
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
    // Withdrawal amount needed (0 if contributing or no withdrawal)
    const withdrawalNeeded = yearlyContribution < 0
      ? Math.min(-yearlyContribution, value)
      : 0;

    if (totalGain <= 0 && withdrawalNeeded === 0) {
      const ptax = calcPortfolioTax(value, includePortfolioTax);
      value -= ptax;
      carryForward = Math.min(
        carryForward + CARRY_FORWARD_PER_YEAR,
        MAX_CARRY_FORWARD,
      );
      results.push({
        year: y,
        portfolioValue: value,
        unrealizedGain: 0,
        realizedGain: 0,
        cgtDue: 0,
        tobPaid: 0,
        portfolioTax: ptax,
        netPortfolioAfterTax: value,
        exemptionUsed: 0,
        carryForward,
        refundReceived,
      });
      continue;
    }

    // If no gains but withdrawal needed: sell at cost (no CGT), pay TOB
    if (totalGain <= 0 && withdrawalNeeded > 0) {
      const tob = calcTob(withdrawalNeeded, tobCategory);
      const ptax = calcPortfolioTax(value, includePortfolioTax);
      const frac = withdrawalNeeded / value;
      value -= withdrawalNeeded + tob + ptax;
      basis -= basis * frac;
      if (basis < 0) basis = 0;
      if (value < 0) value = 0;
      carryForward = Math.min(
        carryForward + CARRY_FORWARD_PER_YEAR,
        MAX_CARRY_FORWARD,
      );
      results.push({
        year: y,
        portfolioValue: value,
        unrealizedGain: Math.max(0, value - basis),
        realizedGain: 0,
        cgtDue: 0,
        tobPaid: tob,
        portfolioTax: ptax,
        netPortfolioAfterTax: value,
        exemptionUsed: 0,
        carryForward,
        refundReceived,
      });
      continue;
    }

    const effectiveExemption = CGT_EXEMPTION + carryForward;
    // Final year: sell everything (exit). Otherwise: sell enough for exemption + withdrawal.
    const isFinalYear = y === years;
    // Minimum fraction needed to cover the withdrawal
    const withdrawalFrac = withdrawalNeeded > 0 ? withdrawalNeeded / value : 0;
    // Smart fraction: sell just enough to realize gains up to exemption
    const smartFrac = Math.min(1, effectiveExemption / totalGain);
    // Use whichever is larger: the smart harvest or the withdrawal requirement
    const frac = isFinalYear ? 1 : Math.min(1, Math.max(smartFrac, withdrawalFrac));
    const sell = value * frac;
    const rg = totalGain * frac;
    const taxable = Math.max(0, rg - effectiveExemption);

    let cgt: number;
    if (brokerMode === 'opt-in') {
      // Broker withholds 10% of realized gain (ignores exemption)
      cgt = rg * cgtRate;
      const correctTax = taxable * cgtRate;
      const overpaid = cgt - correctTax;
      if (overpaid > 0) {
        pendingRefunds.push(overpaid);
      }
    } else {
      cgt = taxable * cgtRate;
    }

    const ts = calcTob(sell, tobCategory);
    const tb = calcTob(sell - cgt - ts, tobCategory);
    const tt = ts + tb;
    const ptax = calcPortfolioTax(value, includePortfolioTax);

    const unsold = value - sell;
    const uBasis = basis * (1 - frac);
    // Rebuy: subtract withdrawal from proceeds (withdrawal cash is taken out)
    const rebuy = sell - (cgt + tt) - withdrawalNeeded;
    basis = uBasis + Math.max(0, rebuy);
    value = unsold + Math.max(0, rebuy) - ptax;
    if (value < 0) value = 0;
    if (basis < 0) basis = 0;

    // Smart harvest tries to use exactly the exemption → no carry-forward builds
    if (taxable === 0 && rg < effectiveExemption) {
      carryForward = Math.min(
        carryForward + CARRY_FORWARD_PER_YEAR,
        MAX_CARRY_FORWARD,
      );
    } else {
      carryForward = 0;
    }

    results.push({
      year: y,
      portfolioValue: value,
      unrealizedGain: Math.max(0, value - basis),
      realizedGain: rg,
      cgtDue: cgt,
      tobPaid: tt,
      portfolioTax: ptax,
      netPortfolioAfterTax: value,
      exemptionUsed:
        brokerMode === 'opt-out' ? Math.min(rg, effectiveExemption) : 0,
      carryForward,
      refundReceived,
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
  return results.reduce((s, r) => s + r.cgtDue + r.tobPaid + r.portfolioTax, 0);
}

export function harvestTotalTax(results: YearResult[]): number {
  return results.reduce(
    (s, r) => s + r.cgtDue + r.tobPaid + r.portfolioTax - r.refundReceived,
    0,
  );
}

export function smartTotalTax(results: YearResult[]): number {
  return results.reduce(
    (s, r) => s + r.cgtDue + r.tobPaid + r.portfolioTax - r.refundReceived,
    0,
  );
}

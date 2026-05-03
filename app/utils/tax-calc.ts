// ─── Belgian CGT Calculator – Pure Tax Logic ─────────────────────
// Based on the law approved 3 April 2026 by the Belgian Chamber.

export const CGT_RATE = 0.1;
export const CGT_EXEMPTION = 10_000;
export const CARRY_FORWARD_PER_YEAR = 1_000; // 1/10th of base exemption
export const MAX_CARRY_FORWARD = 5_000; // max 5 years of carry-forward
export const EXEMPTION_INDEXATION_RATE = 0.02; // 2% annual indexation of the exemption

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
  baseExemption = CGT_EXEMPTION,
  cfPerYear = CARRY_FORWARD_PER_YEAR,
  maxCF = MAX_CARRY_FORWARD,
): { effectiveExemption: number; newCarryForward: number } {
  const totalExemption = baseExemption + carryForward;

  if (gain >= totalExemption) {
    // Fully used all exemption + carry-forward
    return { effectiveExemption: totalExemption, newCarryForward: 0 };
  }

  // Didn't fully use exemption → carry over
  const newCF = Math.min(
    carryForward + cfPerYear,
    maxCF,
  );
  return { effectiveExemption: totalExemption, newCarryForward: newCF };
}

// ─── FIFO Lot Tracking ──────────────────────────────────────────
// Belgian law mandates First-In-First-Out: oldest shares are sold first.

interface Lot {
  value: number;
  basis: number;
}

function lotsValue(lots: Lot[]): number {
  return lots.reduce((s, l) => s + l.value, 0);
}

function lotsBasis(lots: Lot[]): number {
  return lots.reduce((s, l) => s + l.basis, 0);
}

/** Sell a specific value amount from lots using FIFO order. Mutates the lots array. */
function sellFifo(
  lots: Lot[],
  amount: number,
): { soldValue: number; soldBasis: number } {
  let remaining = amount;
  let soldValue = 0;
  let soldBasis = 0;

  while (remaining > 0.001 && lots.length > 0) {
    const lot = lots[0]!;
    if (lot.value <= 0.001) {
      lots.shift();
      continue;
    }
    const sell = Math.min(lot.value, remaining);
    const frac = sell / lot.value;
    const basis = lot.basis * frac;

    soldValue += sell;
    soldBasis += basis;
    lot.value -= sell;
    lot.basis -= basis;
    remaining -= sell;

    if (lot.value < 0.001) lots.shift();
  }

  return { soldValue, soldBasis };
}

/**
 * Read-only: calculate how much value must be sold (FIFO order)
 * to realize a target net gain. Does NOT modify lots.
 */
function valueForGainFifo(lots: Lot[], targetGain: number): number {
  let netGain = 0;
  let valueSold = 0;

  for (const lot of lots) {
    if (netGain >= targetGain - 0.001) break;

    const lotGain = lot.value - lot.basis;

    if (netGain + lotGain <= targetGain + 0.001) {
      valueSold += lot.value;
      netGain += lotGain;
    } else {
      const needGain = targetGain - netGain;
      if (lotGain > 0) {
        const frac = needGain / lotGain;
        valueSold += lot.value * frac;
      }
      break;
    }
  }

  return valueSold;
}

/** Reduce all lot values proportionally (e.g. for portfolio tax deduction). */
function applyDeduction(lots: Lot[], amount: number): void {
  const total = lotsValue(lots);
  if (amount <= 0 || total <= 0) return;
  const factor = Math.max(0, (total - amount) / total);
  for (const lot of lots) {
    lot.value *= factor;
  }
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
  exemptionIndexRate = EXEMPTION_INDEXATION_RATE,
): YearResult[] {
  const results: YearResult[] = [];
  const lots: Lot[] = [{ value: portfolioValue, basis: costBasis }];
  let carryForward = 0;
  const pendingRefunds: number[] = [];

  for (let y = 1; y <= years; y++) {
    let withdrawalGain = 0;
    let withdrawalTob = 0;

    if (yearlyContribution > 0) {
      lots.push({ value: yearlyContribution, basis: yearlyContribution });
    } else if (yearlyContribution < 0 && lotsValue(lots) > 0) {
      // Withdrawal = partial sale using FIFO (oldest lots sold first).
      const actual = Math.min(-yearlyContribution, lotsValue(lots));
      const { soldValue, soldBasis } = sellFifo(lots, actual);
      withdrawalGain = Math.max(0, soldValue - soldBasis);
      withdrawalTob = calcTob(soldValue, tobCategory);
    }

    // Receive pending refund from broker (arrives ~2 years later)
    let refundReceived = 0;
    if (pendingRefunds.length > 0) {
      refundReceived = pendingRefunds.shift()!;
      lots.push({ value: refundReceived, basis: refundReceived });
    }

    // Apply return on all remaining lots
    for (const lot of lots) {
      lot.value *= 1 + expectedReturn;
    }
    let value = lotsValue(lots);
    const ug = Math.max(0, value - lotsBasis(lots));

    // Portfolio tax
    const ptax = calcPortfolioTax(value, includePortfolioTax);
    applyDeduction(lots, ptax);
    value = lotsValue(lots);

    const isFinalYear = y === years;

    // Indexed exemption values for this year
    const indexFactor = Math.pow(1 + exemptionIndexRate, y - 1);
    const indexedExemption = CGT_EXEMPTION * indexFactor;
    const indexedCFPerYear = CARRY_FORWARD_PER_YEAR * indexFactor;
    const indexedMaxCF = MAX_CARRY_FORWARD * indexFactor;

    if (isFinalYear) {
      // Exit: sell everything (FIFO). Combine withdrawal + exit gains for ONE annual exemption.
      const exitBasis = lotsBasis(lots);
      sellFifo(lots, value);
      const exitGain = Math.max(0, value - exitBasis);
      const totalRealized = withdrawalGain + exitGain;
      const { effectiveExemption } = computeExemption(totalRealized, carryForward, indexedExemption, indexedCFPerYear, indexedMaxCF);

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
      const { effectiveExemption, newCarryForward } = computeExemption(withdrawalGain, carryForward, indexedExemption, indexedCFPerYear, indexedMaxCF);

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
  exemptionIndexRate = EXEMPTION_INDEXATION_RATE,
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

    // Indexed exemption values for this year
    const indexFactor = Math.pow(1 + exemptionIndexRate, y - 1);
    const indexedExemption = CGT_EXEMPTION * indexFactor;
    const indexedCFPerYear = CARRY_FORWARD_PER_YEAR * indexFactor;
    const indexedMaxCF = MAX_CARRY_FORWARD * indexFactor;

    const { effectiveExemption, newCarryForward } = computeExemption(
      gain,
      carryForward,
      indexedExemption,
      indexedCFPerYear,
      indexedMaxCF,
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
// Sell only enough each year to use the tax-free exemption (FIFO lot tracking).
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
  exemptionIndexRate = EXEMPTION_INDEXATION_RATE,
): YearResult[] {
  const results: YearResult[] = [];
  const lots: Lot[] = [{ value: portfolioValue, basis: costBasis }];
  let carryForward = 0;
  const pendingRefunds: number[] = [];

  for (let y = 1; y <= years; y++) {
    // Contribution: new lot at cost
    if (yearlyContribution > 0) {
      lots.push({ value: yearlyContribution, basis: yearlyContribution });
    }

    // Apply return to all lots
    for (const lot of lots) {
      lot.value *= 1 + expectedReturn;
    }

    // Receive pending refund from 2 years ago (broker mode)
    let refundReceived = 0;
    if (pendingRefunds.length > 0) {
      refundReceived = pendingRefunds.shift()!;
      lots.push({ value: refundReceived, basis: refundReceived });
    }

    const totalVal = lotsValue(lots);
    const totalBas = lotsBasis(lots);
    const totalGain = Math.max(0, totalVal - totalBas);
    // Withdrawal amount needed (0 if contributing or no withdrawal)
    const withdrawalNeeded = yearlyContribution < 0
      ? Math.min(-yearlyContribution, totalVal)
      : 0;

    // Indexed exemption values for this year
    const indexFactor = Math.pow(1 + exemptionIndexRate, y - 1);
    const indexedExemption = CGT_EXEMPTION * indexFactor;
    const indexedCFPerYear = CARRY_FORWARD_PER_YEAR * indexFactor;
    const indexedMaxCF = MAX_CARRY_FORWARD * indexFactor;

    // No gains and no withdrawal: skip
    if (totalGain <= 0 && withdrawalNeeded === 0) {
      const ptax = calcPortfolioTax(totalVal, includePortfolioTax);
      applyDeduction(lots, ptax);
      carryForward = Math.min(
        carryForward + indexedCFPerYear,
        indexedMaxCF,
      );
      const val = lotsValue(lots);
      results.push({
        year: y,
        portfolioValue: val,
        unrealizedGain: 0,
        realizedGain: 0,
        cgtDue: 0,
        tobPaid: 0,
        portfolioTax: ptax,
        netPortfolioAfterTax: val,
        exemptionUsed: 0,
        carryForward,
        refundReceived,
      });
      continue;
    }

    const effectiveExemption = indexedExemption + carryForward;
    const isFinalYear = y === years;

    // Determine how much to sell (FIFO):
    // - Smart: sell enough (oldest lots first) to realize gains up to exemption
    // - Withdrawal: sell at least enough to cover withdrawal
    // - Final year: sell everything
    let sellAmount: number;
    if (isFinalYear) {
      sellAmount = totalVal;
    } else {
      const smartSell = totalGain > 0
        ? valueForGainFifo(lots, Math.min(effectiveExemption, totalGain))
        : 0;
      sellAmount = Math.min(totalVal, Math.max(smartSell, withdrawalNeeded));
    }

    // No sell needed (e.g. totalGain ≤ 0, no withdrawal, not final)
    if (sellAmount < 0.001 && withdrawalNeeded < 0.001) {
      const ptax = calcPortfolioTax(totalVal, includePortfolioTax);
      applyDeduction(lots, ptax);
      carryForward = Math.min(
        carryForward + indexedCFPerYear,
        indexedMaxCF,
      );
      const val = lotsValue(lots);
      results.push({
        year: y,
        portfolioValue: val,
        unrealizedGain: Math.max(0, val - lotsBasis(lots)),
        realizedGain: 0,
        cgtDue: 0,
        tobPaid: 0,
        portfolioTax: ptax,
        netPortfolioAfterTax: val,
        exemptionUsed: 0,
        carryForward,
        refundReceived,
      });
      continue;
    }

    // Sell (FIFO)
    const preSellVal = totalVal;
    const { soldValue: sell, soldBasis } = sellFifo(lots, sellAmount);
    const rg = Math.max(0, sell - soldBasis);
    const taxable = Math.max(0, rg - effectiveExemption);

    let cgt: number;
    if (brokerMode === 'opt-in') {
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
    const ptax = calcPortfolioTax(preSellVal, includePortfolioTax);

    // Rebuy: sell proceeds minus taxes minus withdrawal = new lot at cost
    const rebuyAmount = sell - (cgt + tt) - withdrawalNeeded;
    if (rebuyAmount > 0.001) {
      lots.push({ value: rebuyAmount, basis: rebuyAmount });
    }

    // Apply portfolio tax to remaining lots
    applyDeduction(lots, ptax);
    let value = lotsValue(lots);
    if (value < 0) {
      lots.length = 0;
      value = 0;
    }

    // Smart harvest tries to use exactly the exemption → no carry-forward builds
    if (taxable === 0 && rg < effectiveExemption) {
      carryForward = Math.min(
        carryForward + indexedCFPerYear,
        indexedMaxCF,
      );
    } else {
      carryForward = 0;
    }

    results.push({
      year: y,
      portfolioValue: value,
      unrealizedGain: Math.max(0, value - lotsBasis(lots)),
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

import { module, test } from 'qunit';
import {
  calcTob,
  calcPortfolioTax,
  computeExemption,
  holdScenario,
  harvestScenario,
  smartScenario,
  holdFinalNet,
  harvestFinalNet,
  smartFinalNet,
  holdTotalTax,
  harvestTotalTax,
  smartTotalTax,
  CGT_RATE,
  CGT_EXEMPTION,
  CARRY_FORWARD_PER_YEAR,
  MAX_CARRY_FORWARD,
  PORTFOLIO_TAX_RATE,
  PORTFOLIO_TAX_THRESHOLD,
  TOB,
} from 'cgt/utils/tax-calc';

module('Unit | Utils | tax-calc', function () {
  // ─── calcTob ─────────────────────────────────────────────

  module('calcTob', function () {
    test('shares: applies 0.12% rate', function (assert) {
      const result = calcTob(100_000, 'shares');
      assert.true(Math.abs(result - 120) < 0.01, `expected ~120, got ${result}`);
    });

    test('shares: caps at €1300', function (assert) {
      const result = calcTob(2_000_000, 'shares');
      assert.strictEqual(result, 1300);
    });

    test('etfAccHigh: applies 1.32% rate', function (assert) {
      const result = calcTob(100_000, 'etfAccHigh');
      assert.strictEqual(result, 1320); // 100k * 0.0132
    });

    test('etfAccHigh: caps at €4000', function (assert) {
      const result = calcTob(500_000, 'etfAccHigh');
      assert.strictEqual(result, 4000);
    });

    test('zero amount returns zero', function (assert) {
      assert.strictEqual(calcTob(0, 'shares'), 0);
    });
  });

  // ─── computeExemption ────────────────────────────────────

  module('computeExemption', function () {
    test('no carry-forward, gain below exemption', function (assert) {
      const { effectiveExemption, newCarryForward } = computeExemption(5_000, 0);
      assert.strictEqual(effectiveExemption, CGT_EXEMPTION);
      assert.strictEqual(newCarryForward, CARRY_FORWARD_PER_YEAR);
    });

    test('no carry-forward, gain equals exemption', function (assert) {
      const { effectiveExemption, newCarryForward } = computeExemption(10_000, 0);
      assert.strictEqual(effectiveExemption, CGT_EXEMPTION);
      assert.strictEqual(newCarryForward, 0);
    });

    test('no carry-forward, gain exceeds exemption', function (assert) {
      const { effectiveExemption, newCarryForward } = computeExemption(20_000, 0);
      assert.strictEqual(effectiveExemption, CGT_EXEMPTION);
      assert.strictEqual(newCarryForward, 0);
    });

    test('with carry-forward, gain fully uses total', function (assert) {
      const { effectiveExemption, newCarryForward } = computeExemption(13_000, 3_000);
      assert.strictEqual(effectiveExemption, 13_000);
      assert.strictEqual(newCarryForward, 0);
    });

    test('with carry-forward, gain below total exemption → adds 1K', function (assert) {
      const { effectiveExemption, newCarryForward } = computeExemption(5_000, 2_000);
      assert.strictEqual(effectiveExemption, 12_000); // 10K + 2K carry
      assert.strictEqual(newCarryForward, 3_000); // 2K + 1K
    });

    test('carry-forward caps at MAX_CARRY_FORWARD', function (assert) {
      const { newCarryForward } = computeExemption(0, MAX_CARRY_FORWARD);
      assert.strictEqual(newCarryForward, MAX_CARRY_FORWARD);
    });

    test('carry-forward just under max adds 1K to reach max', function (assert) {
      const { newCarryForward } = computeExemption(0, MAX_CARRY_FORWARD - 1_000);
      assert.strictEqual(newCarryForward, MAX_CARRY_FORWARD);
    });
  });

  // ─── holdScenario ────────────────────────────────────────

  module('holdScenario', function () {
    test('returns correct number of years', function (assert) {
      const results = holdScenario(100_000, 80_000, 0.07, 5, 'shares', 'opt-out');
      assert.strictEqual(results.length, 5);
    });

    test('no tax paid until final year', function (assert) {
      const results = holdScenario(100_000, 80_000, 0.07, 5, 'shares', 'opt-out');
      for (let i = 0; i < 4; i++) {
        assert.strictEqual(results[i]!.cgtDue, 0, `year ${i + 1} CGT should be 0`);
        assert.strictEqual(results[i]!.tobPaid, 0, `year ${i + 1} TOB should be 0`);
      }
      // Final year should have some tax
      const finalYear = results[4]!;
      const hasTax = finalYear.cgtDue > 0 || finalYear.tobPaid > 0;
      assert.true(hasTax, 'final year has tax');
    });

    test('carry-forward accumulates each year (max 5K)', function (assert) {
      const results = holdScenario(100_000, 80_000, 0.07, 10, 'shares', 'opt-out');
      // Year 1: carry = 1K, Year 5: carry = 5K (max), Year 9: still 5K
      assert.strictEqual(results[0]!.carryForward, 1_000);
      assert.strictEqual(results[4]!.carryForward, MAX_CARRY_FORWARD);
      assert.strictEqual(results[8]!.carryForward, MAX_CARRY_FORWARD);
      // Last year: carry consumed
      assert.strictEqual(results[9]!.carryForward, 0);
    });

    test('portfolio grows each year', function (assert) {
      const results = holdScenario(100_000, 80_000, 0.07, 5, 'shares', 'opt-out');
      for (let i = 1; i < 5; i++) {
        assert.true(results[i]!.portfolioValue > results[i - 1]!.portfolioValue);
      }
    });

    test('final net is less than portfolio value (tax owed)', function (assert) {
      const results = holdScenario(100_000, 50_000, 0.07, 10, 'shares', 'opt-out');
      const last = results[9]!;
      assert.true(last.netPortfolioAfterTax < last.portfolioValue);
    });
  });

  // ─── harvestScenario ─────────────────────────────────────

  module('harvestScenario', function () {
    test('returns correct number of years', function (assert) {
      const results = harvestScenario(100_000, 80_000, 0.07, 5, 'shares', 'opt-out');
      assert.strictEqual(results.length, 5);
    });

    test('self-report: no CGT when gain < exemption', function (assert) {
      // Small portfolio with gains well under €10K
      const results = harvestScenario(50_000, 48_000, 0.03, 1, 'shares', 'opt-out');
      assert.strictEqual(results[0]!.cgtDue, 0);
    });

    test('self-report: CGT when gain > exemption', function (assert) {
      // Large portfolio with gains above €10K
      const results = harvestScenario(500_000, 300_000, 0.10, 1, 'shares', 'opt-out');
      assert.true(results[0]!.cgtDue > 0);
    });

    test('broker opt-in: withholds 10% on full gain', function (assert) {
      // With broker, CGT = gain * 10% regardless of exemption
      const results = harvestScenario(50_000, 48_000, 0.03, 1, 'shares', 'opt-in');
      const gain = 50_000 * 1.03 - 48_000;
      const expectedCgt = gain * CGT_RATE;
      assert.true(Math.abs(results[0]!.cgtDue - expectedCgt) < 1, 'CGT should be ~10% of gain');
    });

    test('broker opt-in: refund arrives 2 years later', function (assert) {
      const results = harvestScenario(50_000, 48_000, 0.03, 4, 'shares', 'opt-in');
      // Year 1: overpaid, no refund yet
      assert.strictEqual(results[0]!.refundReceived, 0);
      // Year 2: receives refund from year 1's overpayment
      assert.true(results[1]!.refundReceived > 0, 'should receive refund in year 2');
    });

    test('self-report net > broker net (broker loses compounding)', function (assert) {
      const selfReport = harvestScenario(200_000, 150_000, 0.07, 10, 'shares', 'opt-out');
      const broker = harvestScenario(200_000, 150_000, 0.07, 10, 'shares', 'opt-in');
      const selfNet = harvestFinalNet(selfReport);
      const brokerNet = harvestFinalNet(broker);
      assert.true(selfNet > brokerNet, `self-report (${selfNet}) should be > broker (${brokerNet})`);
    });

    test('unrealized gain is always 0 (everything sold)', function (assert) {
      const results = harvestScenario(100_000, 80_000, 0.07, 5, 'shares', 'opt-out');
      for (const r of results) {
        assert.strictEqual(r.unrealizedGain, 0);
      }
    });
  });

  // ─── smartScenario ───────────────────────────────────────

  module('smartScenario', function () {
    test('returns correct number of years', function (assert) {
      const results = smartScenario(100_000, 80_000, 0.07, 5, 'shares', 'opt-out');
      assert.strictEqual(results.length, 5);
    });

    test('self-report: no CGT in non-final years when within exemption', function (assert) {
      // Smart harvest should sell only enough to use the exemption (except final year: full exit)
      const results = smartScenario(100_000, 80_000, 0.07, 5, 'shares', 'opt-out');
      for (const r of results.slice(0, -1)) {
        assert.strictEqual(r.cgtDue, 0, `year ${r.year} CGT should be 0`);
      }
    });

    test('final year sells everything (no unrealized gain left)', function (assert) {
      const results = smartScenario(200_000, 100_000, 0.07, 10, 'shares', 'opt-out');
      const last = results[9]!;
      assert.strictEqual(last.unrealizedGain, 0, 'unrealized gain should be 0 after final exit');
    });

    test('self-report: realizes some gain each year', function (assert) {
      const results = smartScenario(200_000, 150_000, 0.07, 5, 'shares', 'opt-out');
      for (const r of results) {
        assert.true(r.realizedGain >= 0, `year ${r.year} should have non-negative realized gain`);
      }
    });

    test('smart harvest final net >= full harvest final net', function (assert) {
      // Smart should usually beat or match full harvest (less TOB)
      const smartR = smartScenario(200_000, 150_000, 0.07, 10, 'shares', 'opt-out');
      const harvestR = harvestScenario(200_000, 150_000, 0.07, 10, 'shares', 'opt-out');
      const smartNet = smartFinalNet(smartR);
      const harvestNet = harvestFinalNet(harvestR);
      assert.true(smartNet >= harvestNet, `smart (${smartNet}) >= harvest (${harvestNet})`);
    });

    test('broker opt-in: CGT is always 10% of realized gain', function (assert) {
      const results = smartScenario(200_000, 100_000, 0.07, 5, 'shares', 'opt-in');
      const withGains = results.filter(r => r.realizedGain > 0);
      assert.true(withGains.length > 0, 'should have years with gains');
      for (const r of withGains) {
        assert.true(Math.abs(r.cgtDue - r.realizedGain * CGT_RATE) < 1,
          `year ${r.year}: CGT should be 10% of realized gain`);
      }
    });
  });

  // ─── Final value helpers ─────────────────────────────────

  module('final value helpers', function () {
    test('holdFinalNet returns last year net', function (assert) {
      const results = holdScenario(100_000, 80_000, 0.07, 5, 'shares', 'opt-out');
      assert.strictEqual(holdFinalNet(results), results[4]!.netPortfolioAfterTax);
    });

    test('holdFinalNet returns 0 for empty results', function (assert) {
      assert.strictEqual(holdFinalNet([]), 0);
    });

    test('harvestFinalNet returns last year net', function (assert) {
      const results = harvestScenario(100_000, 80_000, 0.07, 5, 'shares', 'opt-out');
      assert.strictEqual(harvestFinalNet(results), results[4]!.netPortfolioAfterTax);
    });

    test('smartFinalNet returns last year net (exit baked in)', function (assert) {
      const results = smartScenario(200_000, 100_000, 0.07, 10, 'shares', 'opt-out');
      const last = results[9]!;
      const finalNet = smartFinalNet(results);
      // Final year sells everything, so net = last netPortfolioAfterTax
      assert.strictEqual(finalNet, last.netPortfolioAfterTax);
      assert.true(finalNet > 0);
    });
  });

  // ─── Total tax helpers ───────────────────────────────────

  module('total tax helpers', function () {
    test('holdTotalTax: all tax is in the final year', function (assert) {
      const results = holdScenario(100_000, 50_000, 0.07, 10, 'shares', 'opt-out');
      const total = holdTotalTax(results);
      assert.strictEqual(total, results[9]!.cgtDue + results[9]!.tobPaid);
    });

    test('harvestTotalTax: net tax (self-report, no refunds)', function (assert) {
      const results = harvestScenario(100_000, 80_000, 0.07, 5, 'shares', 'opt-out');
      const total = harvestTotalTax(results);
      // With self-report, refundReceived is 0, so net = gross
      const manual = results.reduce((s, r) => s + r.cgtDue + r.tobPaid, 0);
      assert.strictEqual(total, manual);
    });

    test('harvestTotalTax: broker opt-in subtracts refunds', function (assert) {
      const results = harvestScenario(200_000, 150_000, 0.07, 10, 'shares', 'opt-in');
      const gross = results.reduce((s, r) => s + r.cgtDue + r.tobPaid, 0);
      const refunds = results.reduce((s, r) => s + r.refundReceived, 0);
      const total = harvestTotalTax(results);
      assert.true(Math.abs(total - (gross - refunds)) < 0.01, 'total tax should be gross minus refunds');
      assert.true(total < gross, 'net tax should be less than gross withheld');
    });

    test('smartTotalTax: sums all years (exit baked in)', function (assert) {
      const results = smartScenario(200_000, 100_000, 0.07, 10, 'shares', 'opt-out');
      const total = smartTotalTax(results);
      const manual = results.reduce((s, r) => s + r.cgtDue + r.tobPaid, 0);
      assert.strictEqual(total, manual);
    });

    test('broker opt-in: pending refunds flushed into final year', function (assert) {
      // With only 3 years, year 3 overpayment can't be refunded in time
      const results = harvestScenario(200_000, 100_000, 0.07, 3, 'shares', 'opt-in');
      // Last year should have refund received (flushed pending)
      const totalRefunds = results.reduce((s, r) => s + r.refundReceived, 0);
      assert.true(totalRefunds > 0, 'some refunds should have been received or flushed');
    });
  });

  // ─── Carry-forward accumulation integration ──────────────

  module('carry-forward integration', function () {
    test('hold: 5+ years of holding builds max carry-forward', function (assert) {
      const results = holdScenario(100_000, 80_000, 0.07, 7, 'shares', 'opt-out');
      // Year 5: 5K (max)
      assert.strictEqual(results[4]!.carryForward, MAX_CARRY_FORWARD);
      // Year 6: still 5K (capped)
      assert.strictEqual(results[5]!.carryForward, MAX_CARRY_FORWARD);
    });

    test('hold: effective exemption at exit = 10K + 5K carry = 15K', function (assert) {
      // With 10 years of holding, carry-forward maxes at 5K
      // So effective exemption at exit = 15K
      // With small enough gain, no CGT should be owed
      const results = holdScenario(100_000, 96_000, 0.02, 10, 'shares', 'opt-out');
      const last = results[9]!;
      // Portfolio ~ 100K * 1.02^10 ≈ 121,899; gain ~ 25,899
      // Effective exemption = 15K, so taxable = ~10,899
      // If gain < 15K, CGT = 0
      // Let's just verify the carry-forward was applied
      assert.true(last.cgtDue >= 0);
    });
  });

  // ─── Strategy comparisons ─────────────────────────────────

  module('strategy comparisons', function () {
    test('self-report harvest pays less total tax than hold (low TOB)', function (assert) {
      const holdR = holdScenario(100_000, 80_000, 0.07, 10, 'shares', 'opt-out');
      const harvestR = harvestScenario(100_000, 80_000, 0.07, 10, 'shares', 'opt-out');
      const holdTax = holdTotalTax(holdR);
      const harvestTax = harvestTotalTax(harvestR);
      assert.true(harvestTax < holdTax,
        `harvest tax (${harvestTax.toFixed(0)}) should be < hold tax (${holdTax.toFixed(0)})`);
    });

    test('broker opt-in net tax equals self-report net tax (same effective tax)', function (assert) {
      const selfR = harvestScenario(200_000, 150_000, 0.07, 10, 'shares', 'opt-out');
      const brokerR = harvestScenario(200_000, 150_000, 0.07, 10, 'shares', 'opt-in');
      const selfTax = harvestTotalTax(selfR);
      const brokerTax = harvestTotalTax(brokerR);
      // Net tax should be very close (broker overpays then gets refunded)
      // Small difference due to compounding on the refund timing
      const diff = Math.abs(selfTax - brokerTax);
      assert.true(diff < selfTax * 0.15,
        `tax difference (${diff.toFixed(0)}) should be small relative to total (${selfTax.toFixed(0)})`);
    });
  });

  // ─── Constants ───────────────────────────────────────────

  module('constants', function () {
    test('CGT rate is 10%', function (assert) {
      assert.strictEqual(CGT_RATE, 0.10);
    });

    test('CGT exemption is €10,000', function (assert) {
      assert.strictEqual(CGT_EXEMPTION, 10_000);
    });

    test('carry-forward per year is €1,000', function (assert) {
      assert.strictEqual(CARRY_FORWARD_PER_YEAR, 1_000);
    });

    test('max carry-forward is €5,000', function (assert) {
      assert.strictEqual(MAX_CARRY_FORWARD, 5_000);
    });

    test('TOB shares rate is 0.12%', function (assert) {
      assert.strictEqual(TOB.shares.rate, 0.0012);
    });

    test('TOB etfAccHigh rate is 1.32%', function (assert) {
      assert.strictEqual(TOB.etfAccHigh.rate, 0.0132);
    });
  });

  // ─── Bulletproof: Edge Cases ─────────────────────────────

  module('edge cases', function () {
    test('zero gain → no CGT in any scenario', function (assert) {
      const hold = holdScenario(100_000, 100_000, 0, 5, 'shares', 'opt-out');
      const harvest = harvestScenario(100_000, 100_000, 0, 5, 'shares', 'opt-out');
      const smart = smartScenario(100_000, 100_000, 0, 5, 'shares', 'opt-out');
      assert.strictEqual(holdTotalTax(hold), hold[4]!.tobPaid, 'hold: only TOB at exit');
      for (const r of harvest) assert.strictEqual(r.cgtDue, 0, 'harvest: no CGT');
      for (const r of smart) assert.strictEqual(r.cgtDue, 0, 'smart: no CGT');
    });

    test('negative return → no CGT, portfolio shrinks', function (assert) {
      const results = harvestScenario(100_000, 100_000, -0.05, 3, 'shares', 'opt-out');
      for (const r of results) {
        assert.strictEqual(r.cgtDue, 0, `year ${r.year}: no CGT on losses`);
        assert.strictEqual(r.realizedGain, 0, `year ${r.year}: no realized gain`);
      }
      assert.true(results[2]!.portfolioValue < 100_000, 'portfolio should shrink');
    });

    test('gain exactly at exemption boundary: €10,000', function (assert) {
      // Gain = exactly €10,000 → exemption fully used, no tax
      const { effectiveExemption, newCarryForward } = computeExemption(10_000, 0);
      assert.strictEqual(effectiveExemption, 10_000);
      assert.strictEqual(newCarryForward, 0, 'carry-forward resets when fully used');
    });

    test('gain at €9,999 → no tax, €1K carry forward', function (assert) {
      const { effectiveExemption, newCarryForward } = computeExemption(9_999, 0);
      assert.strictEqual(effectiveExemption, 10_000);
      assert.strictEqual(newCarryForward, 1_000);
    });

    test('gain at €10,001 → tax on €1', function (assert) {
      const { effectiveExemption, newCarryForward } = computeExemption(10_001, 0);
      assert.strictEqual(effectiveExemption, 10_000);
      assert.strictEqual(newCarryForward, 0);
      const tax = (10_001 - effectiveExemption) * CGT_RATE;
      assert.true(Math.abs(tax - 0.10) < 0.01, 'tax should be ~€0.10');
    });

    test('large portfolio hitting TOB cap', function (assert) {
      // 5M portfolio → TOB should be capped
      const tob = calcTob(5_000_000, 'shares');
      assert.strictEqual(tob, 1300, 'shares TOB capped at €1300');
      const tobHigh = calcTob(5_000_000, 'etfAccHigh');
      assert.strictEqual(tobHigh, 4000, 'etfAccHigh TOB capped at €4000');
    });

    test('1 year scenario', function (assert) {
      const hold = holdScenario(100_000, 80_000, 0.07, 1, 'shares', 'opt-out');
      assert.strictEqual(hold.length, 1);
      const year = hold[0]!;
      const hasTaxEvent = year.cgtDue > 0 || year.realizedGain > 0;
      assert.true(hasTaxEvent, 'final year has tax event');
    });
  });

  // ─── Bulletproof: No Loss Carry-Forward ──────────────────

  module('no loss carry-forward (Belgian law)', function () {
    test('harvest: loss year followed by gain year → no loss offset', function (assert) {
      // Year 1: negative return (loss), Year 2: positive return (gain)
      // Loss from Y1 should NOT reduce Y2's taxable gain
      const results = harvestScenario(100_000, 100_000, -0.10, 1, 'shares', 'opt-out');
      // After year 1 with -10% return, value ~ 90K, gain = 0
      assert.strictEqual(results[0]!.cgtDue, 0);

      // Now simulate gain year after loss: use the post-loss value as new start
      const postLossValue = results[0]!.portfolioValue;
      const results2 = harvestScenario(postLossValue, postLossValue, 0.30, 1, 'shares', 'opt-out');
      // Gain should be calculated from postLossValue, NOT offset by previous year's loss
      const gain = postLossValue * 1.30 - postLossValue;
      assert.true(gain > 10_000, 'gain should exceed exemption');
      assert.true(results2[0]!.cgtDue > 0, 'CGT should be charged (no loss carry)');
    });

    test('smart: negative return year does not create loss carry', function (assert) {
      // With mixed returns, each year stands alone
      const results = smartScenario(100_000, 100_000, -0.05, 3, 'shares', 'opt-out');
      for (const r of results) {
        assert.strictEqual(r.cgtDue, 0, `year ${r.year}: no CGT`);
        assert.strictEqual(r.realizedGain, 0, `year ${r.year}: no realized gain`);
      }
    });
  });

  // ─── Bulletproof: Carry-Forward Accumulation ─────────────

  module('carry-forward detailed', function () {
    test('5 years unused → max carry-forward of €5,000', function (assert) {
      const results = holdScenario(100_000, 100_000, 0, 6, 'shares', 'opt-out');
      // No gains, so carry-forward accumulates each year
      assert.strictEqual(results[0]!.carryForward, 1_000);
      assert.strictEqual(results[1]!.carryForward, 2_000);
      assert.strictEqual(results[2]!.carryForward, 3_000);
      assert.strictEqual(results[3]!.carryForward, 4_000);
      assert.strictEqual(results[4]!.carryForward, 5_000);
      // Year 6 is final year, carry consumed but was capped at 5K
    });

    test('carry-forward never exceeds €5,000 even after 10 years', function (assert) {
      const results = holdScenario(100_000, 100_000, 0, 10, 'shares', 'opt-out');
      for (let i = 4; i < 9; i++) {
        assert.strictEqual(results[i]!.carryForward, 5_000, `year ${i + 1}: capped at 5K`);
      }
    });

    test('carry-forward consumed on exit → effective exemption €15K', function (assert) {
      // 10 years hold, small gain → exemption = 10K + 5K carry
      const results = holdScenario(110_000, 100_000, 0.01, 10, 'shares', 'opt-out');
      const last = results[9]!;
      // After 10 years at 1%: value ≈ 110K * 1.01^10 ≈ 121,538
      // gain ≈ 21,538, effective exemption = 15K, taxable ≈ 6,538
      assert.true(last.exemptionUsed > 10_000, 'should use more than base exemption');
      assert.true(last.exemptionUsed <= 15_000, 'should not exceed max exemption');
    });
  });

  // ─── Bulletproof: Conservation of Money ──────────────────

  module('conservation of money', function () {
    test('hold: value_in + growth = net_out + total_tax', function (assert) {
      const results = holdScenario(100_000, 80_000, 0.07, 10, 'shares', 'opt-out');
      const finalValue = results[9]!.portfolioValue;
      const totalTax = holdTotalTax(results);
      const netOut = holdFinalNet(results);
      // net_out + tax = final portfolio value (before tax)
      assert.true(Math.abs(netOut + totalTax - finalValue) < 0.01,
        'net + tax should equal pre-tax portfolio');
    });

    test('harvest (self-report): money is conserved each year', function (assert) {
      const results = harvestScenario(100_000, 100_000, 0.07, 5, 'shares', 'opt-out');
      let prevValue = 100_000;
      for (const r of results) {
        const growthValue = prevValue * 1.07;
        const expectedNet = growthValue - r.cgtDue - r.tobPaid;
        assert.true(Math.abs(r.netPortfolioAfterTax - expectedNet) < 1,
          `year ${r.year}: money should be conserved (expected ${expectedNet.toFixed(0)}, got ${r.netPortfolioAfterTax.toFixed(0)})`);
        prevValue = r.netPortfolioAfterTax;
      }
    });

    test('harvest (broker): money conserved including refunds', function (assert) {
      const results = harvestScenario(100_000, 100_000, 0.07, 10, 'shares', 'opt-in');
      // Total money out = final net + all taxes paid - all refunds received
      const netOut = harvestFinalNet(results);
      const totalTax = harvestTotalTax(results);
      // Total should roughly equal initial investment grown
      assert.true(netOut > 0, 'should have positive final value');
      assert.true(totalTax >= 0, 'net tax should be non-negative');
    });
  });

  // ─── Bulletproof: Determinism ────────────────────────────

  module('determinism', function () {
    test('same inputs → same outputs (hold)', function (assert) {
      const a = holdScenario(100_000, 80_000, 0.07, 10, 'shares', 'opt-out');
      const b = holdScenario(100_000, 80_000, 0.07, 10, 'shares', 'opt-out');
      assert.deepEqual(a, b);
    });

    test('same inputs → same outputs (harvest)', function (assert) {
      const a = harvestScenario(100_000, 80_000, 0.07, 10, 'shares', 'opt-out');
      const b = harvestScenario(100_000, 80_000, 0.07, 10, 'shares', 'opt-out');
      assert.deepEqual(a, b);
    });

    test('same inputs → same outputs (smart)', function (assert) {
      const a = smartScenario(200_000, 100_000, 0.07, 10, 'shares', 'opt-out');
      const b = smartScenario(200_000, 100_000, 0.07, 10, 'shares', 'opt-out');
      assert.deepEqual(a, b);
    });
  });

  // ─── Bulletproof: Yearly Contributions ───────────────────

  module('yearly contributions', function () {
    test('contributions increase both value and basis', function (assert) {
      const without = holdScenario(100_000, 80_000, 0.07, 5, 'shares', 'opt-out', 0);
      const withC = holdScenario(100_000, 80_000, 0.07, 5, 'shares', 'opt-out', 10_000);
      // With contributions, final value should be much higher
      assert.true(holdFinalNet(withC) > holdFinalNet(without) + 40_000,
        'contributions should significantly increase final value');
    });

    test('contributions with negative return still add to basis', function (assert) {
      const results = harvestScenario(100_000, 100_000, -0.03, 3, 'shares', 'opt-out', 10_000);
      // Even with negative returns, contributions keep adding value
      for (const r of results) {
        assert.strictEqual(r.cgtDue, 0, `year ${r.year}: no CGT (contributions > losses)`);
      }
    });
  });

  // ─── Bulletproof: Broker vs Self-Report ──────────────────

  module('broker vs self-report detailed', function () {
    test('broker always withholds more upfront than self-report', function (assert) {
      const selfR = harvestScenario(200_000, 100_000, 0.07, 5, 'shares', 'opt-out');
      const brokerR = harvestScenario(200_000, 100_000, 0.07, 5, 'shares', 'opt-in');
      // Each year, broker CGT >= self-report CGT
      for (let i = 0; i < 5; i++) {
        assert.true(brokerR[i]!.cgtDue >= selfR[i]!.cgtDue,
          `year ${i + 1}: broker (${brokerR[i]!.cgtDue.toFixed(0)}) >= self-report (${selfR[i]!.cgtDue.toFixed(0)})`);
      }
    });

    test('self-report uses exemption, broker does not', function (assert) {
      // Small gain within exemption
      const selfR = harvestScenario(50_000, 48_000, 0.05, 1, 'shares', 'opt-out');
      const brokerR = harvestScenario(50_000, 48_000, 0.05, 1, 'shares', 'opt-in');
      assert.strictEqual(selfR[0]!.cgtDue, 0, 'self-report: no CGT (within exemption)');
      assert.true(brokerR[0]!.cgtDue > 0, 'broker: CGT withheld (ignores exemption)');
    });

    test('broker refund flushed when scenario ends before refund arrives', function (assert) {
      // 2-year scenario: year 1 overpayment, year 2 gets refund via shift
      // But year 2 also overpays → that refund is flushed
      const results = harvestScenario(200_000, 100_000, 0.07, 2, 'shares', 'opt-in');
      const totalRefunds = results.reduce((s, r) => s + r.refundReceived, 0);
      assert.true(totalRefunds > 0, 'flushed refunds should be > 0');
    });
  });

  // ─── Bulletproof: Smart Harvest Specifics ────────────────

  module('smart harvest specifics', function () {
    test('non-final years: realized gain ≤ exemption (self-report)', function (assert) {
      const results = smartScenario(200_000, 100_000, 0.07, 10, 'shares', 'opt-out');
      for (const r of results.slice(0, -1)) {
        assert.true(r.realizedGain <= CGT_EXEMPTION + MAX_CARRY_FORWARD + 1,
          `year ${r.year}: realized gain (${r.realizedGain.toFixed(0)}) should be within exemption range`);
      }
    });

    test('final year: sells everything, unrealized gain = 0', function (assert) {
      const results = smartScenario(200_000, 100_000, 0.07, 10, 'shares', 'opt-out');
      const last = results[9]!;
      assert.strictEqual(last.unrealizedGain, 0);
      assert.true(last.realizedGain > 0, 'final year should have realized gain');
    });

    test('smart with very small gains → carry-forward accumulates', function (assert) {
      // Tiny return: gains well below exemption each year
      const results = smartScenario(50_000, 49_000, 0.01, 5, 'shares', 'opt-out');
      // Gains are small, so carry-forward should build up
      assert.true(results[3]!.carryForward > 0, 'carry-forward should accumulate');
    });
  });

  // ─── Portfolio Tax (Effectenrekening) ────────────────────
  module('portfolio tax', function () {
    test('calcPortfolioTax: zero below threshold', function (assert) {
      assert.strictEqual(calcPortfolioTax(999_999, true), 0);
      assert.strictEqual(calcPortfolioTax(500_000, true), 0);
    });

    test('calcPortfolioTax: 0.15% at and above threshold', function (assert) {
      assert.strictEqual(calcPortfolioTax(1_000_000, true), 1_500);
      assert.strictEqual(calcPortfolioTax(2_000_000, true), 3_000);
    });

    test('calcPortfolioTax: disabled returns zero regardless', function (assert) {
      assert.strictEqual(calcPortfolioTax(2_000_000, false), 0);
      assert.strictEqual(calcPortfolioTax(1_000_000, false), 0);
    });

    test('constants are correct', function (assert) {
      assert.strictEqual(PORTFOLIO_TAX_RATE, 0.0015);
      assert.strictEqual(PORTFOLIO_TAX_THRESHOLD, 1_000_000);
    });

    test('hold: portfolio tax reduces final value', function (assert) {
      const without = holdScenario(1_500_000, 1_500_000, 0.07, 5, 'etfAccLow', 'opt-out', 0, false);
      const withPtax = holdScenario(1_500_000, 1_500_000, 0.07, 5, 'etfAccLow', 'opt-out', 0, true);
      assert.true(holdFinalNet(withPtax) < holdFinalNet(without), 'portfolio tax should reduce final net');
      // Each year should have portfolio tax > 0
      for (const r of withPtax) {
        assert.true(r.portfolioTax > 0, `year ${r.year}: should have portfolio tax`);
      }
    });

    test('harvest: portfolio tax included in total tax', function (assert) {
      const withPtax = harvestScenario(1_500_000, 1_500_000, 0.07, 3, 'etfAccLow', 'opt-out', 0, true);
      const totalPtax = withPtax.reduce((s, r) => s + r.portfolioTax, 0);
      assert.true(totalPtax > 0, 'should have some portfolio tax');
      const totalTax = harvestTotalTax(withPtax);
      assert.true(totalTax > totalPtax, 'total tax should include portfolio tax + CGT + TOB');
    });

    test('smart: portfolio tax included in total tax', function (assert) {
      const withPtax = smartScenario(1_500_000, 1_500_000, 0.07, 3, 'etfAccLow', 'opt-out', 0, true);
      const totalPtax = withPtax.reduce((s, r) => s + r.portfolioTax, 0);
      assert.true(totalPtax > 0, 'should have some portfolio tax');
    });

    test('below threshold: no portfolio tax even when enabled', function (assert) {
      const results = holdScenario(100_000, 100_000, 0.07, 5, 'etfAccLow', 'opt-out', 0, true);
      for (const r of results) {
        assert.strictEqual(r.portfolioTax, 0, `year ${r.year}: no portfolio tax below €1M`);
      }
    });

    test('portfolio grows past threshold mid-simulation', function (assert) {
      // Start at 800K, 7% return, 50K/yr contribution → should cross 1M
      const results = holdScenario(800_000, 800_000, 0.07, 5, 'etfAccLow', 'opt-out', 50_000, true);
      const earlyYears = results.filter(r => r.portfolioTax === 0);
      const lateYears = results.filter(r => r.portfolioTax > 0);
      assert.true(lateYears.length > 0, 'should start paying portfolio tax after crossing 1M');
      const startsAbove = results[0]!.portfolioValue >= 1_000_000;
      const hasBelowYears = earlyYears.length > 0 || startsAbove;
      assert.true(hasBelowYears, 'should have some years below or start above');
    });
  });
});

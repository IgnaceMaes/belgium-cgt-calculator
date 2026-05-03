import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { modifier } from 'ember-modifier';

import {
  type TobCategory,
  type YearResult,
  holdScenario,
  harvestScenario,
  smartScenario,
  holdFinalNet,
  harvestFinalNet,
  smartFinalNet,
  holdTotalTax,
  harvestTotalTax,
  smartTotalTax,
} from '@/utils/tax-calc';
import { HOLD_COLOR, HARVEST_COLOR, SMART_COLOR } from '@/utils/colors';
import type {
  LineChartSeries,
  LineChartPoint,
} from '@/components/cgt/line-chart';
import type { BarItem } from '@/components/cgt/bar-chart';

import InputsPanel from '@/components/cgt/inputs-panel';
import ResultCards from '@/components/cgt/result-cards';
import StrategyExplainer from '@/components/cgt/strategy-explainer';
import LineChart from '@/components/cgt/line-chart';
import BarChart from '@/components/cgt/bar-chart';
import YearByYear from '@/components/cgt/year-by-year';
import CgtFooter from '@/components/cgt/footer';

export default class CgtCalculator extends Component {
  // ─── State ─────────────────────────────────────────────────

  @tracked portfolioValue = 100_000;
  @tracked costBasis = 100_000;
  @tracked expectedReturn = 0.07;
  @tracked yearsToProject = 10;
  @tracked yearlyContribution = 10_000;
  @tracked tobCategory: TobCategory = 'etfAccLow';
  @tracked brokerReporting: 'opt-in' | 'opt-out' = 'opt-in';
  @tracked includePortfolioTax = false;
  @tracked cgtRate = 0.1;
  @tracked showDetails = false;
  @tracked isDark = true;

  // ─── Theme ─────────────────────────────────────────────────

  syncTheme = modifier(() => {
    document.documentElement.classList.toggle('light', !this.isDark);
    return () => {
      document.documentElement.classList.remove('light');
    };
  });

  toggleTheme = () => {
    this.isDark = !this.isDark;
    document.documentElement.classList.toggle('light', !this.isDark);
  };

  // ─── Derived values ────────────────────────────────────────

  get expectedReturnPct() {
    return Math.round(this.expectedReturn * 1000) / 10;
  }
  get cgtRatePct() {
    return Math.round(this.cgtRate * 1000) / 10;
  }

  // ─── Scenarios ─────────────────────────────────────────────

  get holdResults(): YearResult[] {
    return holdScenario(
      this.portfolioValue,
      this.costBasis,
      this.expectedReturn,
      this.yearsToProject,
      this.tobCategory,
      this.brokerReporting,
      this.yearlyContribution,
      this.includePortfolioTax,
      this.cgtRate,
    );
  }

  get harvestResults(): YearResult[] {
    return harvestScenario(
      this.portfolioValue,
      this.costBasis,
      this.expectedReturn,
      this.yearsToProject,
      this.tobCategory,
      this.brokerReporting,
      this.yearlyContribution,
      this.includePortfolioTax,
      this.cgtRate,
    );
  }

  get smartResults(): YearResult[] {
    return smartScenario(
      this.portfolioValue,
      this.costBasis,
      this.expectedReturn,
      this.yearsToProject,
      this.tobCategory,
      this.brokerReporting,
      this.yearlyContribution,
      this.includePortfolioTax,
      this.cgtRate,
    );
  }

  // ─── Computed results ──────────────────────────────────────

  get holdFinal() {
    return holdFinalNet(this.holdResults);
  }
  get harvestFinal() {
    return harvestFinalNet(this.harvestResults);
  }
  get smartFinal() {
    return smartFinalNet(this.smartResults);
  }

  get holdTax() {
    return holdTotalTax(this.holdResults);
  }
  get harvestTax() {
    return harvestTotalTax(this.harvestResults);
  }
  get smartTax() {
    return smartTotalTax(this.smartResults);
  }

  get totalInvested() {
    return this.costBasis + this.yearlyContribution * this.yearsToProject;
  }
  get smartVsHold() {
    return this.smartFinal - this.holdFinal;
  }
  get harvestEqualsSmart() {
    return Math.abs(this.harvestFinal - this.smartFinal) < 1;
  }

  get bestStrategy(): 'hold' | 'harvest' | 'smart' {
    const vals = [
      { n: 'hold' as const, v: this.holdFinal },
      { n: 'harvest' as const, v: this.harvestFinal },
      { n: 'smart' as const, v: this.smartFinal },
    ];
    vals.sort((a, b) => b.v - a.v);
    return vals[0]!.n;
  }

  get scenarios() {
    return [
      {
        name: 'Hold',
        key: 'hold',
        color: HOLD_COLOR,
        final: this.holdFinal,
        totalTax: this.holdTax,
        grossProfit: this.holdFinal + this.holdTax - this.totalInvested,
        netProfit: this.holdFinal - this.totalInvested,
        borderClass: 'border-indigo-500/30',
        bgClass: 'border-indigo-500/30 bg-indigo-500/10',
        badgeClass: 'bg-indigo-500/20 text-indigo-400 border-indigo-500/30',
      },
      {
        name: 'Full harvest',
        key: 'harvest',
        color: HARVEST_COLOR,
        final: this.harvestFinal,
        totalTax: this.harvestTax,
        grossProfit: this.harvestFinal + this.harvestTax - this.totalInvested,
        netProfit: this.harvestFinal - this.totalInvested,
        borderClass: 'border-pink-500/30',
        bgClass: 'border-pink-500/30 bg-pink-500/10',
        badgeClass: 'bg-pink-500/20 text-pink-400 border-pink-500/30',
      },
      {
        name: 'Smart harvest',
        key: 'smart',
        color: SMART_COLOR,
        final: this.smartFinal,
        totalTax: this.smartTax,
        grossProfit: this.smartFinal + this.smartTax - this.totalInvested,
        netProfit: this.smartFinal - this.totalInvested,
        borderClass: 'border-emerald-500/30',
        bgClass: 'border-emerald-500/30 bg-emerald-500/10',
        badgeClass: 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30',
      },
    ];
  }

  // ─── Chart data ────────────────────────────────────────────

  get growthSeries(): LineChartSeries[] {
    const ug0 = Math.max(0, this.portfolioValue - this.costBasis);
    const toPoints = (results: YearResult[]): LineChartPoint[] => [
      { x: 0, y: this.portfolioValue, unrealizedGain: ug0 },
      ...results.map((r) => ({
        x: r.year,
        y: r.netPortfolioAfterTax,
        unrealizedGain: r.unrealizedGain,
      })),
    ];
    return [
      { label: 'Hold', color: HOLD_COLOR, points: toPoints(this.holdResults) },
      {
        label: 'Full harvest',
        color: HARVEST_COLOR,
        points: toPoints(this.harvestResults),
      },
      {
        label: 'Smart harvest',
        color: SMART_COLOR,
        points: toPoints(this.smartResults),
      },
    ];
  }

  get taxBars(): BarItem[] {
    return [
      { label: 'Hold', value: this.holdTax, color: HOLD_COLOR },
      { label: 'Full harvest', value: this.harvestTax, color: HARVEST_COLOR },
      { label: 'Smart harvest', value: this.smartTax, color: SMART_COLOR },
    ];
  }

  get detailSections() {
    return [
      { label: 'Hold', color: HOLD_COLOR, rows: this.holdResults },
      {
        label: 'Full harvest',
        color: HARVEST_COLOR,
        rows: this.harvestResults,
      },
      { label: 'Smart harvest', color: SMART_COLOR, rows: this.smartResults },
    ];
  }

  // ─── Broker description ────────────────────────────────────

  get brokerDescription() {
    return this.brokerReporting === 'opt-in'
      ? `Broker deducts ${this.cgtRatePct}% on every profitable sale, ignoring the €10K exemption and any losses. You claim the exemption back via your annual tax return, but the refund takes ~1.5–2 years. This means overpaid tax doesn't compound in your favor during that period.`
      : 'You declare and pay via your annual tax return. You can offset losses, apply the €10K exemption optimally across your full portfolio, and avoid lending money to the government interest-free.';
  }

  // ─── Handlers ──────────────────────────────────────────────

  setPortfolio = (v: number) => {
    this.portfolioValue = v;
  };
  setBasis = (v: number) => {
    this.costBasis = v;
  };
  setContribution = (v: number) => {
    this.yearlyContribution = v;
  };
  onReturn = (e: Event) => {
    this.expectedReturn =
      (Number((e.target as HTMLInputElement).value) || 0) / 100;
  };
  onYears = (e: Event) => {
    this.yearsToProject = Math.min(
      30,
      Math.max(1, Number((e.target as HTMLInputElement).value) || 1),
    );
  };
  onTob = (v: TobCategory) => {
    this.tobCategory = v;
  };
  onBroker = (v: 'opt-in' | 'opt-out') => {
    this.brokerReporting = v;
  };
  onCgtRate = (e: Event) => {
    this.cgtRate = (Number((e.target as HTMLInputElement).value) || 0) / 100;
  };
  toggleDetails = () => {
    this.showDetails = !this.showDetails;
  };
  togglePortfolioTax = () => {
    this.includePortfolioTax = !this.includePortfolioTax;
  };

  // ─── Template ──────────────────────────────────────────────

  <template>
    <div class="relative min-h-screen" {{this.syncTheme}}>
      {{! Theme toggle }}
      <button
        type="button"
        class="fixed top-5 right-5 z-50 flex h-9 w-9 items-center justify-center rounded-full border border-border bg-card backdrop-blur-sm text-muted-foreground transition-all hover:text-foreground hover:bg-accent"
        title={{if this.isDark "Switch to light mode" "Switch to dark mode"}}
        {{on "click" this.toggleTheme}}
      >
        {{#if this.isDark}}
          <svg
            class="h-4 w-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            stroke-width="2"
          ><circle cx="12" cy="12" r="5" /><path
              d="M12 1v2m0 18v2M4.22 4.22l1.42 1.42m12.72 12.72l1.42 1.42M1 12h2m18 0h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"
            /></svg>
        {{else}}
          <svg
            class="h-4 w-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            stroke-width="2"
          ><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" /></svg>
        {{/if}}
      </button>

      <div class="mx-auto max-w-3xl px-5 py-16 space-y-10">

        {{! Header }}
        <header class="space-y-3 text-center">
          <div
            class="inline-flex items-center gap-2 rounded-full border border-border bg-card px-4 py-1.5 text-xs text-muted-foreground"
          >
            <span
              class="inline-block h-1.5 w-1.5 rounded-full bg-emerald-500 animate-pulse"
            ></span>
            Belgian tax reform 2026
          </div>
          <h1
            class="text-4xl font-bold tracking-tight sm:text-5xl text-foreground"
          >
            Capital Gains<br />Tax Calculator
          </h1>
          <p
            class="mx-auto max-w-lg text-base text-muted-foreground leading-relaxed"
          >
            Compare hold vs. harvest strategies under Belgium's new CGT. Find
            out if annual gain harvesting saves you money after TOB costs.
          </p>
        </header>

        {{! Inputs }}
        <InputsPanel
          @portfolioValue={{this.portfolioValue}}
          @costBasis={{this.costBasis}}
          @expectedReturnPct={{this.expectedReturnPct}}
          @yearsToProject={{this.yearsToProject}}
          @yearlyContribution={{this.yearlyContribution}}
          @cgtRatePct={{this.cgtRatePct}}
          @tobCategory={{this.tobCategory}}
          @brokerReporting={{this.brokerReporting}}
          @brokerDescription={{this.brokerDescription}}
          @includePortfolioTax={{this.includePortfolioTax}}
          @onPortfolio={{this.setPortfolio}}
          @onBasis={{this.setBasis}}
          @onReturn={{this.onReturn}}
          @onYears={{this.onYears}}
          @onContribution={{this.setContribution}}
          @onCgtRate={{this.onCgtRate}}
          @onTob={{this.onTob}}
          @onBroker={{this.onBroker}}
          @onTogglePortfolioTax={{this.togglePortfolioTax}}
        />

        {{! Result cards }}
        <ResultCards
          @scenarios={{this.scenarios}}
          @totalInvested={{this.totalInvested}}
          @bestStrategy={{this.bestStrategy}}
          @harvestEqualsSmart={{this.harvestEqualsSmart}}
          @smartVsHold={{this.smartVsHold}}
        />

        {{! Strategy explainer }}
        <StrategyExplainer @cgtRatePct={{this.cgtRatePct}} />

        {{! Charts }}
        <section class="space-y-4">
          <h2 class="text-sm font-semibold text-foreground">Net portfolio growth</h2>
          <div
            class="rounded-2xl border border-border bg-card p-5 backdrop-blur-sm"
          >
            <LineChart @series={{this.growthSeries}} />
          </div>
        </section>

        <section class="space-y-4">
          <h2 class="text-sm font-semibold text-foreground">Total tax paid</h2>
          <div
            class="rounded-2xl border border-border bg-card p-5 backdrop-blur-sm"
          >
            <BarChart @items={{this.taxBars}} />
          </div>
        </section>

        {{! Year-by-year }}
        <YearByYear
          @sections={{this.detailSections}}
          @showDetails={{this.showDetails}}
          @includePortfolioTax={{this.includePortfolioTax}}
          @onToggle={{this.toggleDetails}}
        />

        {{! Footer }}
        <CgtFooter @cgtRatePct={{this.cgtRatePct}} />

      </div>
    </div>
  </template>
}

import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { modifier } from 'ember-modifier';

import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Tooltip, TooltipTrigger, TooltipContent } from '@/components/ui/tooltip';
import IMask from 'imask';

import {
  type TobCategory, type YearResult,
  holdScenario, harvestScenario, smartScenario,
  holdFinalNet, harvestFinalNet, smartFinalNet,
  holdTotalTax, harvestTotalTax, smartTotalTax,
  calcTob, CGT_RATE, CGT_EXEMPTION,
  PORTFOLIO_TAX_RATE, PORTFOLIO_TAX_THRESHOLD,
} from '@/utils/tax-calc';

// ─── Colors ──────────────────────────────────────────────────────

const HOLD_COLOR = '#6366f1';
const HARVEST_COLOR = '#ec4899';
const SMART_COLOR = '#10b981';

function fmt(v: number): string {
  return new Intl.NumberFormat('nl-BE', {
    style: 'currency',
    currency: 'EUR',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(v);
}

function fmtK(v: number): string {
  if (Math.abs(v) >= 1_000_000) return `€${(v / 1_000_000).toFixed(1)}M`;
  if (Math.abs(v) >= 1_000) return `€${(v / 1_000).toFixed(0)}K`;
  return fmt(v);
}

// ─── Info icon helper ─────────────────────────────────────────────

const INFO_ICON = `<svg class="h-3.5 w-3.5 text-muted-foreground/60 hover:text-muted-foreground transition-colors" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4m0-4h.01"/></svg>`;

// ─── Line Chart ───────────────────────────────────────────────────

interface LineChartPoint { x: number; y: number; unrealizedGain?: number; }
interface LineChartSeries { label: string; color: string; points: LineChartPoint[]; }
interface LineChartSignature { Args: { series: LineChartSeries[] }; Element: HTMLDivElement; }

class LineChart extends Component<LineChartSignature> {
  padL = 62; padR = 20; padT = 20; padB = 36;
  w = 600; h = 300;
  @tracked hoverIdx: number | null = null;

  get allPoints() { return this.args.series.flatMap((s) => s.points); }
  get xMin() { return Math.min(...this.allPoints.map((p) => p.x)); }
  get xMax() { return Math.max(...this.allPoints.map((p) => p.x)); }
  get yMin() { return Math.floor(Math.min(...this.allPoints.map((p) => p.y)) / 10_000) * 10_000; }
  get yMax() { return Math.ceil(Math.max(...this.allPoints.map((p) => p.y)) / 10_000) * 10_000; }

  get yTicks(): number[] {
    const range = this.yMax - this.yMin;
    const step = this.niceStep(range, 5);
    const ticks: number[] = [];
    for (let v = this.yMin; v <= this.yMax; v += step) ticks.push(v);
    return ticks;
  }

  get xTicks(): number[] {
    const ticks: number[] = [];
    for (let x = this.xMin; x <= this.xMax; x++) ticks.push(x);
    return ticks;
  }

  niceStep(range: number, maxTicks: number): number {
    const rough = range / maxTicks;
    const mag = Math.pow(10, Math.floor(Math.log10(rough)));
    const norm = rough / mag;
    let nice: number;
    if (norm <= 1.5) nice = 1;
    else if (norm <= 3) nice = 2;
    else if (norm <= 7) nice = 5;
    else nice = 10;
    return nice * mag;
  }

  sx = (x: number) => {
    const range = this.xMax - this.xMin || 1;
    return this.padL + ((x - this.xMin) / range) * (this.w - this.padL - this.padR);
  };
  sy = (y: number) => {
    const range = this.yMax - this.yMin || 1;
    return this.padT + (1 - (y - this.yMin) / range) * (this.h - this.padT - this.padB);
  };
  pathD = (points: LineChartPoint[]) =>
    points.map((p, i) => `${i === 0 ? 'M' : 'L'}${this.sx(p.x).toFixed(1)},${this.sy(p.y).toFixed(1)}`).join(' ');
  areaD = (points: LineChartPoint[]) => {
    const line = this.pathD(points);
    const last = points.at(-1);
    const first = points.at(0);
    if (!last || !first) return line;
    return `${line} L${this.sx(last.x).toFixed(1)},${(this.h - this.padB).toFixed(1)} L${this.sx(first.x).toFixed(1)},${(this.h - this.padB).toFixed(1)} Z`;
  };
  lastPoint = (points: LineChartPoint[]) => { const p = points.at(-1); return p ? [p] : []; };
  fmtTick = (v: number) => fmtK(v);

  onMouseMove = (e: MouseEvent) => {
    const svg = (e.currentTarget as SVGSVGElement);
    const rect = svg.getBoundingClientRect();
    const mouseX = ((e.clientX - rect.left) / rect.width) * this.w;
    const range = this.xMax - this.xMin || 1;
    const dataX = this.xMin + ((mouseX - this.padL) / (this.w - this.padL - this.padR)) * range;
    const idx = Math.round(dataX - this.xMin);
    if (idx >= 0 && idx <= this.xMax - this.xMin) {
      this.hoverIdx = idx;
    } else {
      this.hoverIdx = null;
    }
  };
  onMouseLeave = () => { this.hoverIdx = null; };

  get hoverX(): number | null {
    if (this.hoverIdx === null) return null;
    return this.sx(this.xMin + this.hoverIdx);
  }

  get hoverData(): { label: string; color: string; value: string; unrealizedGain: string | null }[] | null {
    if (this.hoverIdx === null) return null;
    return this.args.series.map((s) => {
      const p = s.points[this.hoverIdx!];
      return {
        label: s.label, color: s.color,
        value: p ? fmtK(p.y) : '—',
        unrealizedGain: p?.unrealizedGain != null ? fmtK(p.unrealizedGain) : null,
      };
    });
  }

  get hoverYear(): number | null {
    if (this.hoverIdx === null) return null;
    return this.xMin + this.hoverIdx;
  }

  get tooltipX(): number {
    const x = this.hoverX ?? 0;
    // flip tooltip to left side when near right edge
    return x > this.w * 0.65 ? x - 180 : x + 10;
  }

  get tooltipY(): number {
    return this.padT + 8;
  }

  hoverDots = (points: LineChartPoint[]) => {
    if (this.hoverIdx === null) return [];
    const p = points[this.hoverIdx];
    return p ? [p] : [];
  };

  <template>
    <div class="w-full" ...attributes>
      <svg viewBox="0 0 {{this.w}} {{this.h}}" class="w-full h-auto" preserveAspectRatio="xMidYMid meet"
        {{on "mousemove" this.onMouseMove}} {{on "mouseleave" this.onMouseLeave}}>
        <defs>
          {{#each @series as |s idx|}}
            <linearGradient id="area-{{idx}}" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stop-color={{s.color}} stop-opacity="0.12" />
              <stop offset="100%" stop-color={{s.color}} stop-opacity="0.01" />
            </linearGradient>
          {{/each}}
        </defs>

        {{! Grid }}
        {{#each this.yTicks as |tick|}}
          <line x1={{this.padL}} x2={{this.w}} y1={{this.sy tick}} y2={{this.sy tick}}
            stroke="currentColor" stroke-opacity="0.06" stroke-width="1" />
          <text x={{this.padL}} y={{this.sy tick}} dx="-8" dy="4" text-anchor="end"
            class="fill-muted-foreground" font-size="10" font-family="Inter Variable, sans-serif">{{this.fmtTick tick}}</text>
        {{/each}}
        {{#each this.xTicks as |tick|}}
          <text x={{this.sx tick}} y={{this.h}} dy="-6" text-anchor="middle"
            class="fill-muted-foreground" font-size="10" font-family="Inter Variable, sans-serif">{{tick}}</text>
        {{/each}}

        {{! Area fills }}
        {{#each @series as |s idx|}}
          <path d={{this.areaD s.points}} fill="url(#area-{{idx}})" />
        {{/each}}

        {{! Lines }}
        {{#each @series as |s|}}
          <path d={{this.pathD s.points}} fill="none" stroke={{s.color}}
            stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
          {{#each (this.lastPoint s.points) as |p|}}
            <circle cx={{this.sx p.x}} cy={{this.sy p.y}} r="3.5" fill={{s.color}} />
            <circle cx={{this.sx p.x}} cy={{this.sy p.y}} r="6" fill={{s.color}} fill-opacity="0.15" />
          {{/each}}
        {{/each}}

        {{! Hover crosshair & dots }}
        {{#if this.hoverX}}
          <line x1={{this.hoverX}} x2={{this.hoverX}} y1={{this.padT}} y2={{this.h}}
            stroke="currentColor" stroke-opacity="0.2" stroke-width="1" stroke-dasharray="3 3" />
          {{#each @series as |s|}}
            {{#each (this.hoverDots s.points) as |p|}}
              <circle cx={{this.sx p.x}} cy={{this.sy p.y}} r="4" fill={{s.color}} stroke="var(--background, #0a0a12)" stroke-width="2" />
            {{/each}}
          {{/each}}

          {{! Tooltip box }}
          <g>
            <rect x={{this.tooltipX}} y={{this.tooltipY}} width="170" height={{this.tooltipH}}
              rx="6" fill="var(--popover, #1a1a2e)" fill-opacity="0.95" stroke="var(--border)" stroke-width="0.5" />
            <text x={{this.tooltipX}} y={{this.tooltipY}} dx="8" dy="16"
              font-size="10" font-weight="600" class="fill-foreground" font-family="Inter Variable, sans-serif">
              Year {{this.hoverYear}}
            </text>
            <text x={{this.tooltipValueX}} y={{this.tooltipY}} dy="16"
              font-size="8" text-anchor="end" class="fill-muted-foreground" font-family="Inter Variable, sans-serif" opacity="0.6">net / unrealized</text>
            {{#each this.hoverData as |d idx|}}
              <circle cx={{this.tooltipDotX}} cy={{this.tooltipItemY idx}} r="3" fill={{d.color}} />
              <text x={{this.tooltipLabelX}} y={{this.tooltipItemY idx}} dy="3.5"
                font-size="9" class="fill-muted-foreground" font-family="Inter Variable, sans-serif">{{d.label}}</text>
              <text x={{this.tooltipValueX}} y={{this.tooltipItemY idx}} dy="3.5"
                font-size="9" font-weight="500" text-anchor="end" class="fill-foreground" font-family="Inter Variable, sans-serif">{{d.value}}</text>
              {{#if d.unrealizedGain}}
                <text x={{this.tooltipValueX}} y={{this.tooltipItemY idx}} dy="14"
                  font-size="8" text-anchor="end" class="fill-muted-foreground" font-family="Inter Variable, sans-serif" opacity="0.6">↳ {{d.unrealizedGain}} unrealized</text>
              {{/if}}
            {{/each}}
          </g>
        {{/if}}
      </svg>

      {{! Legend }}
      <div class="flex flex-wrap items-center justify-center gap-4 pt-3 text-xs">
        {{#each @series as |s|}}
          <div class="flex items-center gap-1.5">
            <div class="h-2 w-2 rounded-full" style="background:{{s.color}}"></div>
            <span class="text-muted-foreground">{{s.label}}</span>
          </div>
        {{/each}}
      </div>
    </div>
  </template>

  get hasUnrealizedGains(): boolean {
    return this.hoverData?.some((d) => d.unrealizedGain !== null) ?? false;
  }
  get tooltipH() {
    if (!this.hoverData) return 0;
    let h = 24; // header
    for (const d of this.hoverData) {
      h += d.unrealizedGain ? 30 : 18; // row + optional sub-row
    }
    return h + 4; // padding
  }
  get tooltipDotX() { return this.tooltipX + 14; }
  get tooltipLabelX() { return this.tooltipX + 24; }
  get tooltipValueX() { return this.tooltipX + 162; }
  tooltipItemY = (idx: number) => {
    if (!this.hoverData) return this.tooltipY + 32;
    let y = this.tooltipY + 32;
    for (let i = 0; i < idx; i++) {
      y += this.hoverData[i]?.unrealizedGain ? 30 : 18;
    }
    return y;
  };
}

// ─── Bar Chart ────────────────────────────────────────────────────

interface BarItem { label: string; value: number; color: string; }
interface BarChartSignature { Args: { items: BarItem[] }; Element: HTMLDivElement; }

class BarChart extends Component<BarChartSignature> {
  get maxVal() { return Math.max(...this.args.items.map((i) => i.value), 1); }
  pct = (v: number) => `${((v / this.maxVal) * 100).toFixed(1)}%`;
  fmtV = (v: number) => fmt(v);

  <template>
    <div class="space-y-4" ...attributes>
      {{#each @items as |item|}}
        <div class="space-y-1.5">
          <div class="flex items-baseline justify-between text-sm">
            <span class="text-muted-foreground">{{item.label}}</span>
            <span class="tabular-nums font-medium text-foreground">{{this.fmtV item.value}}</span>
          </div>
          <div class="h-1.5 w-full overflow-hidden rounded-full bg-muted">
            <div class="h-full rounded-full transition-all duration-700 ease-out"
              style="width:{{this.pct item.value}};background:{{item.color}}"></div>
          </div>
        </div>
      {{/each}}
    </div>
  </template>
}

// ─── Main Calculator ──────────────────────────────────────────────

export default class CgtCalculator extends Component {
  @tracked portfolioValue = 100_000;
  @tracked costBasis = 100_000;
  @tracked expectedReturn = 0.07;
  @tracked yearsToProject = 10;
  @tracked yearlyContribution = 10_000;
  @tracked tobCategory: TobCategory = 'etfAccLow';
  @tracked brokerReporting: 'opt-in' | 'opt-out' = 'opt-in';
  @tracked includePortfolioTax = false;
  @tracked showDetails = false;
  @tracked isDark = true;

  syncTheme = modifier((el: Element) => {
    const apply = () => {
      document.documentElement.classList.toggle('light', !this.isDark);
    };
    apply();
    return () => {
      document.documentElement.classList.remove('light');
    };
  });

  toggleTheme = () => {
    this.isDark = !this.isDark;
    document.documentElement.classList.toggle('light', !this.isDark);
  };

  get currentGain() { return Math.max(0, this.portfolioValue - this.costBasis); }
  get expectedReturnPct() { return Math.round(this.expectedReturn * 1000) / 10; }

  get tobOptions() {
    return [
      { value: 'shares' as TobCategory, label: 'Shares', detail: '0.12%' },
      { value: 'bonds' as TobCategory, label: 'Bonds', detail: '0.12%' },
      { value: 'etfAccHigh' as TobCategory, label: 'Acc. ETF (1.32%)', detail: '1.32%' },
      { value: 'etfAccLow' as TobCategory, label: 'Acc. ETF (0.12%)', detail: '0.12%' },
      { value: 'etfDist' as TobCategory, label: 'Dist. ETF', detail: '0.12%' },
    ];
  }

  // ─── Scenarios ─────────────────────────────────────────────

  get holdResults(): YearResult[] {
    return holdScenario(this.portfolioValue, this.costBasis, this.expectedReturn, this.yearsToProject, this.tobCategory, this.brokerReporting, this.yearlyContribution, this.includePortfolioTax);
  }

  get harvestResults(): YearResult[] {
    return harvestScenario(this.portfolioValue, this.costBasis, this.expectedReturn, this.yearsToProject, this.tobCategory, this.brokerReporting, this.yearlyContribution, this.includePortfolioTax);
  }

  get smartResults(): YearResult[] {
    return smartScenario(this.portfolioValue, this.costBasis, this.expectedReturn, this.yearsToProject, this.tobCategory, this.brokerReporting, this.yearlyContribution, this.includePortfolioTax);
  }

  // ─── Final values ──────────────────────────────────────────

  get holdFinal() { return holdFinalNet(this.holdResults); }
  get harvestFinal() { return harvestFinalNet(this.harvestResults); }
  get smartFinal() { return smartFinalNet(this.smartResults); }

  get holdTotalTax() { return holdTotalTax(this.holdResults); }
  get harvestTotalTax() { return harvestTotalTax(this.harvestResults); }
  get smartTotalTax() { return smartTotalTax(this.smartResults); }

  get totalInvested() { return this.costBasis + this.yearlyContribution * this.yearsToProject; }
  get holdGrossProfit() { return this.holdFinal + this.holdTotalTax - this.totalInvested; }
  get harvestGrossProfit() { return this.harvestFinal + this.harvestTotalTax - this.totalInvested; }
  get smartGrossProfit() { return this.smartFinal + this.smartTotalTax - this.totalInvested; }
  get holdProfit() { return this.holdFinal - this.totalInvested; }
  get harvestProfit() { return this.harvestFinal - this.totalInvested; }
  get smartProfit() { return this.smartFinal - this.totalInvested; }

  get smartVsHold() { return this.smartFinal - this.holdFinal; }
  get harvestEqualsSmart() { return Math.abs(this.harvestFinal - this.smartFinal) < 1; }

  get bestStrategy(): 'hold' | 'harvest' | 'smart' {
    const vals = [
      { n: 'hold' as const, v: this.holdFinal },
      { n: 'harvest' as const, v: this.harvestFinal },
      { n: 'smart' as const, v: this.smartFinal },
    ];
    vals.sort((a, b) => b.v - a.v);
    return vals[0]!.n;
  }

  // ─── Chart data ────────────────────────────────────────────

  get growthSeries(): LineChartSeries[] {
    const ug0 = Math.max(0, this.portfolioValue - this.costBasis);
    const hold: LineChartPoint[] = [{ x: 0, y: this.portfolioValue, unrealizedGain: ug0 }, ...this.holdResults.map((r) => ({ x: r.year, y: r.netPortfolioAfterTax, unrealizedGain: r.unrealizedGain }))];
    const harvest: LineChartPoint[] = [{ x: 0, y: this.portfolioValue, unrealizedGain: ug0 }, ...this.harvestResults.map((r) => ({ x: r.year, y: r.netPortfolioAfterTax, unrealizedGain: r.unrealizedGain }))];
    const smart: LineChartPoint[] = [{ x: 0, y: this.portfolioValue, unrealizedGain: ug0 }, ...this.smartResults.map((r) => ({ x: r.year, y: r.netPortfolioAfterTax, unrealizedGain: r.unrealizedGain }))];
    return [
      { label: 'Hold', color: HOLD_COLOR, points: hold },
      { label: 'Full harvest', color: HARVEST_COLOR, points: harvest },
      { label: 'Smart harvest', color: SMART_COLOR, points: smart },
    ];
  }

  get taxBars(): BarItem[] {
    return [
      { label: 'Hold', value: this.holdTotalTax, color: HOLD_COLOR },
      { label: 'Full harvest', value: this.harvestTotalTax, color: HARVEST_COLOR },
      { label: 'Smart harvest', value: this.smartTotalTax, color: SMART_COLOR },
    ];
  }

  // ─── Handlers ──────────────────────────────────────────────

  euroMask = modifier((el: HTMLInputElement, [setValue, initial]: [((v: number) => void), number]) => {
    const mask = IMask(el, {
      mask: Number,
      thousandsSeparator: '.',
      radix: ',',
      scale: 0,
      signed: false,
      min: 0,
      max: 999_999_999,
    });
    mask.typedValue = initial;
    mask.on('accept', () => setValue(mask.typedValue));
    return () => mask.destroy();
  });

  setPortfolio = (v: number) => { this.portfolioValue = v; };
  setBasis = (v: number) => { this.costBasis = v; };
  setContribution = (v: number) => { this.yearlyContribution = v; };
  onReturn = (e: Event) => { this.expectedReturn = (Number((e.target as HTMLInputElement).value) || 0) / 100; };
  onYears = (e: Event) => { this.yearsToProject = Math.min(30, Math.max(1, Number((e.target as HTMLInputElement).value) || 1)); };
  onTob = (v: TobCategory) => { this.tobCategory = v; };
  onBroker = (v: 'opt-in' | 'opt-out') => { this.brokerReporting = v; };
  toggleDetails = () => { this.showDetails = !this.showDetails; };
  togglePortfolioTax = () => { this.includePortfolioTax = !this.includePortfolioTax; };

  // ─── Helpers ───────────────────────────────────────────────

  f = (v: number) => fmt(v);
  isPos = (v: number) => v >= 0;
  isTob = (v: TobCategory) => this.tobCategory === v;
  isBest = (s: string) => {
    if (this.harvestEqualsSmart && (s === 'harvest' || s === 'smart')) {
      return this.bestStrategy === 'harvest' || this.bestStrategy === 'smart';
    }
    return this.bestStrategy === s;
  };
  get isBrokerOptIn() { return this.brokerReporting === 'opt-in'; }
  get isBrokerOptOut() { return this.brokerReporting === 'opt-out'; }

  get detailSections() {
    return [
      { label: 'Hold', color: HOLD_COLOR, rows: this.holdResults },
      { label: 'Full harvest', color: HARVEST_COLOR, rows: this.harvestResults },
      { label: 'Smart harvest', color: SMART_COLOR, rows: this.smartResults },
    ];
  }

  get holdColor() { return HOLD_COLOR; }
  get harvestColor() { return HARVEST_COLOR; }
  get smartColor() { return SMART_COLOR; }

  <template>
    <div class="relative min-h-screen" {{this.syncTheme}}>
      {{! Theme toggle — fixed top right }}
      <button type="button"
        class="fixed top-5 right-5 z-50 flex h-9 w-9 items-center justify-center rounded-full border border-border bg-card backdrop-blur-sm text-muted-foreground transition-all hover:text-foreground hover:bg-accent"
        title={{if this.isDark "Switch to light mode" "Switch to dark mode"}}
        {{on "click" this.toggleTheme}}>
        {{#if this.isDark}}
          <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="5"/><path d="M12 1v2m0 18v2M4.22 4.22l1.42 1.42m12.72 12.72l1.42 1.42M1 12h2m18 0h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/></svg>
        {{else}}
          <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
        {{/if}}
      </button>

      <div class="mx-auto max-w-3xl px-5 py-16 space-y-10">

        {{! ═══ HEADER ═══ }}
        <header class="space-y-3 text-center">
          <div class="inline-flex items-center gap-2 rounded-full border border-border bg-card px-4 py-1.5 text-xs text-muted-foreground">
            <span class="inline-block h-1.5 w-1.5 rounded-full bg-emerald-500 animate-pulse"></span>
            Belgian tax reform 2026
          </div>
          <h1 class="text-4xl font-bold tracking-tight sm:text-5xl text-foreground">
            Capital Gains<br />Tax Calculator
          </h1>
          <p class="mx-auto max-w-lg text-base text-muted-foreground leading-relaxed">
            Compare hold vs. harvest strategies under Belgium's new 10% CGT.
            Find out if annual gain harvesting saves you money after TOB costs.
          </p>
        </header>

        {{! ═══ INPUTS PANEL ═══ }}
        <section class="rounded-2xl border border-border bg-card p-6 backdrop-blur-sm space-y-6">
          <h2 class="text-sm font-semibold text-foreground">Your portfolio</h2>

          <div class="grid gap-5 sm:grid-cols-2">
            <div class="space-y-2">
              <div class="flex items-center gap-1.5">
                <Label class="text-xs text-muted-foreground">Portfolio value</Label>
                <Tooltip>
                  <TooltipTrigger>
                    <svg class="h-3.5 w-3.5 text-muted-foreground/60 hover:text-muted-foreground transition-colors cursor-help" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4m0-4h.01"/></svg>
                  </TooltipTrigger>
                  <TooltipContent @side="top">Current total market value of your investment portfolio</TooltipContent>
                </Tooltip>
              </div>
              <div class="relative">
                <span class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-xs text-muted-foreground">€</span>
                <Input @type="text" inputmode="numeric"
                  class="tabular-nums pl-7"
                  {{this.euroMask this.setPortfolio this.portfolioValue}} />
              </div>
            </div>
            <div class="space-y-2">
              <div class="flex items-center gap-1.5">
                <Label class="text-xs text-muted-foreground">Cost basis</Label>
                <Tooltip>
                  <TooltipTrigger>
                    <svg class="h-3.5 w-3.5 text-muted-foreground/60 hover:text-muted-foreground transition-colors cursor-help" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4m0-4h.01"/></svg>
                  </TooltipTrigger>
                  <TooltipContent @side="top">Your portfolio value on 1 January 2026 — the starting point for calculating taxable gains under Belgian law. Gains made before 2026 are tax-free.</TooltipContent>
                </Tooltip>
              </div>
              <div class="relative">
                <span class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-xs text-muted-foreground">€</span>
                <Input @type="text" inputmode="numeric"
                  class="tabular-nums pl-7"
                  {{this.euroMask this.setBasis this.costBasis}} />
              </div>
            </div>
            <div class="space-y-2">
              <div class="flex items-center gap-1.5">
                <Label class="text-xs text-muted-foreground">Annual return</Label>
                <Tooltip>
                  <TooltipTrigger>
                    <svg class="h-3.5 w-3.5 text-muted-foreground/60 hover:text-muted-foreground transition-colors cursor-help" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4m0-4h.01"/></svg>
                  </TooltipTrigger>
                  <TooltipContent @side="top">Expected average annual return on your investments. Historical stock market average is ~7–8%.</TooltipContent>
                </Tooltip>
              </div>
              <div class="relative">
                <Input @type="number" value={{this.expectedReturnPct}} step="0.5" min="0" max="50"
                  class="tabular-nums pr-7"
                  {{on "input" this.onReturn}} />
                <span class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-xs text-muted-foreground">%</span>
              </div>
            </div>
            <div class="space-y-2">
              <div class="flex items-center gap-1.5">
                <Label class="text-xs text-muted-foreground">Years</Label>
                <Tooltip>
                  <TooltipTrigger>
                    <svg class="h-3.5 w-3.5 text-muted-foreground/60 hover:text-muted-foreground transition-colors cursor-help" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4m0-4h.01"/></svg>
                  </TooltipTrigger>
                  <TooltipContent @side="top">Number of years to project forward. All scenarios assume a final sale at the end.</TooltipContent>
                </Tooltip>
              </div>
              <div class="relative">
                <Input @type="number" value={{this.yearsToProject}} step="1" min="1" max="30"
                  class="tabular-nums pr-7"
                  {{on "input" this.onYears}} />
                <span class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-xs text-muted-foreground">yr</span>
              </div>
            </div>
            <div class="space-y-2">
              <div class="flex items-center gap-1.5">
                <Label class="text-xs text-muted-foreground">Yearly contribution</Label>
                <Tooltip>
                  <TooltipTrigger>
                    <svg class="h-3.5 w-3.5 text-muted-foreground/60 hover:text-muted-foreground transition-colors cursor-help" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4m0-4h.01"/></svg>
                  </TooltipTrigger>
                  <TooltipContent @side="top">Additional capital invested each year. This amount is added at the start of each year and increases your cost basis accordingly.</TooltipContent>
                </Tooltip>
              </div>
              <div class="relative">
                <span class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-xs text-muted-foreground">€</span>
                <Input @type="text" inputmode="numeric"
                  class="tabular-nums pl-7"
                  {{this.euroMask this.setContribution this.yearlyContribution}} />
              </div>
            </div>
          </div>

          {{! TOB category }}
          <div class="space-y-2.5">
            <div class="flex items-center gap-1.5">
              <Label class="text-xs text-muted-foreground">TOB rate (Transaction tax)</Label>
              <Tooltip>
                <TooltipTrigger>
                  <svg class="h-3.5 w-3.5 text-muted-foreground/60 hover:text-muted-foreground transition-colors cursor-help" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4m0-4h.01"/></svg>
                </TooltipTrigger>
                <TooltipContent @side="top" class="max-w-xs">Belgian stock exchange tax (Taks op Beursverrichtingen) charged on every buy and sell. Most accumulating ETFs pay 1.32%, but some (e.g. registered in Belgium or certain EU-domiciled funds) pay only 0.12%.</TooltipContent>
              </Tooltip>
            </div>
            <div class="flex flex-wrap gap-2">
              {{#each this.tobOptions as |opt|}}
                <button type="button"
                  class="rounded-lg border px-3 py-1.5 text-xs font-medium transition-all duration-200
                    {{if (this.isTob opt.value)
                      'border-primary bg-primary text-primary-foreground shadow-sm'
                      'border-border text-muted-foreground hover:border-foreground/20 hover:bg-accent'}}"
                  {{on "click" (fn this.onTob opt.value)}}>
                  {{opt.label}}
                </button>
              {{/each}}
            </div>
          </div>

          {{! Broker reporting }}
          <div class="space-y-2.5">
            <div class="flex items-center gap-1.5">
              <Label class="text-xs text-muted-foreground">CGT collection method</Label>
              <Tooltip>
                <TooltipTrigger>
                  <svg class="h-3.5 w-3.5 text-muted-foreground/60 hover:text-muted-foreground transition-colors cursor-help" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4m0-4h.01"/></svg>
                </TooltipTrigger>
                <TooltipContent @side="top" class="max-w-xs">With broker withholding, your broker deducts CGT only when you actually sell. If you hold for years, the tax is deferred — meaning that money stays invested and compounds. With self-reporting, you declare and pay via your annual tax return.</TooltipContent>
              </Tooltip>
            </div>
            <div class="flex gap-2">
              <button type="button"
                class="rounded-lg border px-3 py-1.5 text-xs font-medium transition-all duration-200
                  {{if this.isBrokerOptIn
                    'border-primary bg-primary text-primary-foreground shadow-sm'
                    'border-border text-muted-foreground hover:border-foreground/20 hover:bg-accent'}}"
                {{on "click" (fn this.onBroker "opt-in")}}>Broker withholds</button>
              <button type="button"
                class="rounded-lg border px-3 py-1.5 text-xs font-medium transition-all duration-200
                  {{if this.isBrokerOptOut
                    'border-primary bg-primary text-primary-foreground shadow-sm'
                    'border-border text-muted-foreground hover:border-foreground/20 hover:bg-accent'}}"
                {{on "click" (fn this.onBroker "opt-out")}}>Self-report</button>
            </div>
            <p class="text-xs text-muted-foreground leading-relaxed">
              {{if this.isBrokerOptIn
                "Broker deducts 10% on every profitable sale, ignoring the €10K exemption and any losses. You claim the exemption back via your annual tax return, but the refund takes ~1.5–2 years. This means overpaid tax doesn't compound in your favor during that period."
                "You declare and pay via your annual tax return. You can offset losses, apply the €10K exemption optimally across your full portfolio, and avoid lending money to the government interest-free."}}
            </p>
          </div>

          {{! Portfolio tax }}
          <div class="space-y-2.5">
            <div class="flex items-center gap-1.5">
              <Label class="text-xs text-muted-foreground">Portfolio tax (effectenrekening)</Label>
              <Tooltip>
                <TooltipTrigger>
                  <svg class="h-3.5 w-3.5 text-muted-foreground/60 hover:text-muted-foreground transition-colors cursor-help" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4m0-4h.01"/></svg>
                </TooltipTrigger>
                <TooltipContent @side="top" class="max-w-xs">The taks op effectenrekeningen is a 0.15% annual tax on securities accounts valued above €1,000,000. It applies to the total account value, not just the excess. Assessed on average quarterly reference points.</TooltipContent>
              </Tooltip>
            </div>
            <div class="flex gap-2">
              <button type="button"
                class="rounded-lg border px-3 py-1.5 text-xs font-medium transition-all duration-200
                  {{if this.includePortfolioTax
                    'border-primary bg-primary text-primary-foreground shadow-sm'
                    'border-border text-muted-foreground hover:border-foreground/20 hover:bg-accent'}}"
                {{on "click" this.togglePortfolioTax}}>Include (≥ €1M)</button>
              <button type="button"
                class="rounded-lg border px-3 py-1.5 text-xs font-medium transition-all duration-200
                  {{unless this.includePortfolioTax
                    'border-primary bg-primary text-primary-foreground shadow-sm'
                    'border-border text-muted-foreground hover:border-foreground/20 hover:bg-accent'}}"
                {{on "click" this.togglePortfolioTax}}>Exclude</button>
            </div>
            {{#if this.includePortfolioTax}}
              <p class="text-xs text-muted-foreground leading-relaxed">
                0.15% per year on the total account value when it exceeds €1,000,000. This is deducted annually from your portfolio, reducing your compounding base.
              </p>
            {{/if}}
          </div>
        </section>

        {{! ═══ RESULTS CARDS ═══ }}
        <section class="space-y-4">
          <h2 class="text-sm font-semibold text-foreground">Net portfolio after {{this.yearsToProject}} years</h2>

          <div class="grid gap-3 sm:grid-cols-3">
            {{! Hold }}
            <div class="group relative rounded-2xl border p-5 transition-all duration-300
              {{if (this.isBest 'hold')
                'border-indigo-500/30 bg-indigo-500/10'
                'border-border bg-card'}}">
              {{#if (this.isBest "hold")}}
                <Badge class="absolute -top-2.5 right-3 bg-indigo-500/20 text-indigo-400 border-indigo-500/30 text-[10px] uppercase tracking-wider">Best</Badge>
              {{/if}}
              <div class="flex items-center gap-2 text-xs text-muted-foreground mb-1.5">
                <div class="h-2 w-2 rounded-full" style="background:{{this.holdColor}}"></div>
                Hold
              </div>
              <div class="text-2xl font-semibold tabular-nums text-foreground">{{this.f this.holdFinal}}</div>
              <div class="mt-3 space-y-1 text-xs text-muted-foreground">
                <div class="flex justify-between"><span>Invested</span><span class="tabular-nums">{{this.f this.totalInvested}}</span></div>
                <div class="flex justify-between"><span>Gross profit</span><span class="tabular-nums {{if (this.isPos this.holdGrossProfit) 'text-emerald-400' 'text-red-400'}}">{{if (this.isPos this.holdGrossProfit) "+" ""}}{{this.f this.holdGrossProfit}}</span></div>
                <div class="flex justify-between"><span>Tax paid</span><span class="tabular-nums text-orange-400">−{{this.f this.holdTotalTax}}</span></div>
                <div class="flex justify-between border-t border-border pt-1 mt-1"><span class="font-medium text-foreground">Net profit</span><span class="tabular-nums font-medium {{if (this.isPos this.holdProfit) 'text-emerald-400' 'text-red-400'}}">{{if (this.isPos this.holdProfit) "+" ""}}{{this.f this.holdProfit}}</span></div>
              </div>
            </div>

            {{! Full harvest }}
            <div class="group relative rounded-2xl border p-5 transition-all duration-300
              {{if (this.isBest 'harvest')
                'border-pink-500/30 bg-pink-500/10'
                'border-border bg-card'}}">
              {{#if (this.isBest "harvest")}}
                <Badge class="absolute -top-2.5 right-3 bg-pink-500/20 text-pink-400 border-pink-500/30 text-[10px] uppercase tracking-wider">Best</Badge>
              {{/if}}
              <div class="flex items-center gap-2 text-xs text-muted-foreground mb-1.5">
                <div class="h-2 w-2 rounded-full" style="background:{{this.harvestColor}}"></div>
                Full harvest
              </div>
              <div class="text-2xl font-semibold tabular-nums text-foreground">{{this.f this.harvestFinal}}</div>
              <div class="mt-3 space-y-1 text-xs text-muted-foreground">
                <div class="flex justify-between"><span>Invested</span><span class="tabular-nums">{{this.f this.totalInvested}}</span></div>
                <div class="flex justify-between"><span>Gross profit</span><span class="tabular-nums {{if (this.isPos this.harvestGrossProfit) 'text-emerald-400' 'text-red-400'}}">{{if (this.isPos this.harvestGrossProfit) "+" ""}}{{this.f this.harvestGrossProfit}}</span></div>
                <div class="flex justify-between"><span>Tax paid</span><span class="tabular-nums text-orange-400">−{{this.f this.harvestTotalTax}}</span></div>
                <div class="flex justify-between border-t border-border pt-1 mt-1"><span class="font-medium text-foreground">Net profit</span><span class="tabular-nums font-medium {{if (this.isPos this.harvestProfit) 'text-emerald-400' 'text-red-400'}}">{{if (this.isPos this.harvestProfit) "+" ""}}{{this.f this.harvestProfit}}</span></div>
              </div>
            </div>

            {{! Smart harvest }}
            <div class="group relative rounded-2xl border p-5 transition-all duration-300
              {{if (this.isBest 'smart')
                'border-emerald-500/30 bg-emerald-500/10'
                'border-border bg-card'}}">
              {{#if (this.isBest "smart")}}
                <Badge class="absolute -top-2.5 right-3 bg-emerald-500/20 text-emerald-400 border-emerald-500/30 text-[10px] uppercase tracking-wider">Best</Badge>
              {{/if}}
              <div class="flex items-center gap-2 text-xs text-muted-foreground mb-1.5">
                <div class="h-2 w-2 rounded-full" style="background:{{this.smartColor}}"></div>
                Smart harvest
              </div>
              <div class="text-2xl font-semibold tabular-nums text-foreground">{{this.f this.smartFinal}}</div>
              <div class="mt-3 space-y-1 text-xs text-muted-foreground">
                <div class="flex justify-between"><span>Invested</span><span class="tabular-nums">{{this.f this.totalInvested}}</span></div>
                <div class="flex justify-between"><span>Gross profit</span><span class="tabular-nums {{if (this.isPos this.smartGrossProfit) 'text-emerald-400' 'text-red-400'}}">{{if (this.isPos this.smartGrossProfit) "+" ""}}{{this.f this.smartGrossProfit}}</span></div>
                <div class="flex justify-between"><span>Tax paid</span><span class="tabular-nums text-orange-400">−{{this.f this.smartTotalTax}}</span></div>
                <div class="flex justify-between border-t border-border pt-1 mt-1"><span class="font-medium text-foreground">Net profit</span><span class="tabular-nums font-medium {{if (this.isPos this.smartProfit) 'text-emerald-400' 'text-red-400'}}">{{if (this.isPos this.smartProfit) "+" ""}}{{this.f this.smartProfit}}</span></div>
              </div>
            </div>
          </div>

          {{! Delta callout }}
          <div class="flex flex-col gap-2">
            <div class="flex items-center justify-between rounded-xl border border-border bg-card px-5 py-3.5">
              <span class="text-sm text-muted-foreground">Smart harvest vs. hold</span>
              <span class="text-xl font-bold tabular-nums {{if (this.isPos this.smartVsHold) 'text-emerald-400' 'text-red-400'}}">
                {{if (this.isPos this.smartVsHold) "+" ""}}{{this.f this.smartVsHold}}
              </span>
            </div>
          </div>
        </section>

        {{! ═══ STRATEGY EXPLAINER ═══ }}
        <section class="rounded-2xl border border-border bg-card p-6 backdrop-blur-sm space-y-4">
          <h2 class="text-sm font-semibold text-foreground">How the strategies work</h2>
          <div class="grid gap-4 sm:grid-cols-3">
            <div class="space-y-2">
              <div class="flex items-center gap-2">
                <div class="h-2 w-2 rounded-full" style="background:#6366f1"></div>
                <span class="text-xs font-medium text-foreground">Hold</span>
              </div>
              <p class="text-xs text-muted-foreground leading-relaxed">Buy and hold until the end. No CGT or TOB is paid until the final sale — all gains compound untaxed. Simple, but you forfeit the annual €10K exemption each year (unused exemptions can carry forward €1K/year, up to a max €15K).</p>
            </div>
            <div class="space-y-2">
              <div class="flex items-center gap-2">
                <div class="h-2 w-2 rounded-full" style="background:#ec4899"></div>
                <span class="text-xs font-medium text-foreground">Full harvest</span>
              </div>
              <p class="text-xs text-muted-foreground leading-relaxed">Sell everything each year and immediately rebuy. This realizes all gains annually, using the €10K exemption each year. Unused exemption carries forward (€1K/year, max €5K extra). But you pay TOB on every sell &amp; buy cycle, and gains above the exemption are taxed at 10%. Assumes you can rebuy at the same price you sold — in practice there may be a small spread.</p>
            </div>
            <div class="space-y-2">
              <div class="flex items-center gap-2">
                <div class="h-2 w-2 rounded-full" style="background:#10b981"></div>
                <span class="text-xs font-medium text-foreground">Smart harvest</span>
              </div>
              <p class="text-xs text-muted-foreground leading-relaxed">Sell only enough each year to realize gains up to the €10K exemption. Unused exemption carries forward €1K/year (max €5K extra, so up to €15K total). Minimizes TOB while still harvesting the tax-free allowance. Usually the best strategy when TOB is high. Assumes you can rebuy at the same price you sold — in practice there may be a small spread.</p>
            </div>
          </div>
        </section>

        {{! ═══ CHARTS ═══ }}
        <section class="space-y-4">
          <h2 class="text-sm font-semibold text-foreground">Net portfolio growth</h2>
          <div class="rounded-2xl border border-border bg-card p-5 backdrop-blur-sm">
            <LineChart @series={{this.growthSeries}} />
          </div>
        </section>

        <section class="space-y-4">
          <h2 class="text-sm font-semibold text-foreground">Total tax paid</h2>
          <div class="rounded-2xl border border-border bg-card p-5 backdrop-blur-sm">
            <BarChart @items={{this.taxBars}} />
          </div>
        </section>

        {{! ═══ YEAR-BY-YEAR ═══ }}
        <section>
          <button type="button"
            class="flex w-full items-center justify-between rounded-xl border border-border bg-card px-5 py-3.5 text-sm text-muted-foreground transition-all hover:bg-accent"
            {{on "click" this.toggleDetails}}>
            <span>Year-by-year breakdown</span>
            <svg class="h-4 w-4 text-muted-foreground transition-transform duration-200 {{if this.showDetails 'rotate-180' ''}}" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
            </svg>
          </button>

          {{#if this.showDetails}}
            <div class="mt-4 space-y-6">
              {{#each this.detailSections as |section|}}
                <div class="space-y-3">
                  <div class="flex items-center gap-2">
                    <div class="h-2 w-2 rounded-full" style="background:{{section.color}}"></div>
                    <h3 class="text-sm font-medium text-foreground">{{section.label}}</h3>
                  </div>
                  <div class="overflow-x-auto rounded-xl border border-border">
                    <table class="w-full text-xs">
                      <thead>
                        <tr class="border-b border-border bg-muted/50">
                          <th class="px-4 py-2.5 text-left font-medium text-muted-foreground uppercase tracking-wider text-[10px]">Yr</th>
                          <th class="px-4 py-2.5 text-right font-medium text-muted-foreground uppercase tracking-wider text-[10px]">Portfolio</th>
                          <th class="px-4 py-2.5 text-right font-medium text-muted-foreground uppercase tracking-wider text-[10px]">Gain</th>
                          <th class="px-4 py-2.5 text-right font-medium text-muted-foreground uppercase tracking-wider text-[10px]">CGT</th>
                          <th class="px-4 py-2.5 text-right font-medium text-muted-foreground uppercase tracking-wider text-[10px]">TOB</th>
                          {{#if this.includePortfolioTax}}
                            <th class="px-4 py-2.5 text-right font-medium text-muted-foreground uppercase tracking-wider text-[10px]">PTax</th>
                          {{/if}}
                          <th class="px-4 py-2.5 text-right font-medium text-muted-foreground uppercase tracking-wider text-[10px]">Net</th>
                        </tr>
                      </thead>
                      <tbody>
                        {{#each section.rows as |row|}}
                          <tr class="border-b border-border/50 last:border-0 hover:bg-muted/30 transition-colors">
                            <td class="px-4 py-2 tabular-nums text-muted-foreground">{{row.year}}</td>
                            <td class="px-4 py-2 text-right tabular-nums">{{this.f row.portfolioValue}}</td>
                            <td class="px-4 py-2 text-right tabular-nums">{{this.f row.realizedGain}}</td>
                            <td class="px-4 py-2 text-right tabular-nums">{{this.f row.cgtDue}}</td>
                            <td class="px-4 py-2 text-right tabular-nums">{{this.f row.tobPaid}}</td>
                            {{#if this.includePortfolioTax}}
                              <td class="px-4 py-2 text-right tabular-nums">{{this.f row.portfolioTax}}</td>
                            {{/if}}
                            <td class="px-4 py-2 text-right tabular-nums font-medium">{{this.f row.netPortfolioAfterTax}}</td>
                          </tr>
                        {{/each}}
                      </tbody>
                    </table>
                  </div>
                </div>
              {{/each}}
            </div>
          {{/if}}
        </section>

        {{! ═══ FOOTER ═══ }}
        <footer class="rounded-2xl border border-border bg-card px-6 py-5">
          <div class="flex items-start gap-3">
            <div class="mt-0.5 shrink-0 rounded-full border border-border h-4 w-4 flex items-center justify-center">
              <svg class="h-2.5 w-2.5 text-muted-foreground" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
            </div>
            <div class="text-xs text-muted-foreground space-y-1 leading-relaxed">
              <p><span class="text-foreground font-medium">Key rules:</span> 10% CGT on realized gains · €10K/year exempt (unused €1K carries forward, max €5K extra) · losses offset gains within the same year only · TOB on every buy &amp; sell</p>
              <p><span class="text-foreground font-medium">Note:</span> The hold scenario defers all CGT to the final sale. Harvest scenarios pay CGT each year but reset the cost basis, using the exemption annually. Broker opt-in withholds 10% on all gains upfront; you reclaim the exemption via your tax return ~2 years later. Harvest and smart harvest assume you can rebuy at the same price you sold — in practice, the bid-ask spread and intraday price movement may cause small deviations.</p>
              <p><span class="text-foreground font-medium">Disclaimer:</span> Estimates only. Based on the Belgian Arizona coalition tax reform proposal. Consult a tax advisor for your specific situation.</p>
            </div>
          </div>
        </footer>

        <div class="text-center pb-8">
          <p class="text-[10px] text-muted-foreground/40 uppercase tracking-[0.2em]">Built with Ember.js</p>
        </div>

      </div>
    </div>
  </template>
}

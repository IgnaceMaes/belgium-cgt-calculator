import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { modifier } from 'ember-modifier';
import IMask from 'imask';

import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tooltip, TooltipTrigger, TooltipContent } from '@/components/ui/tooltip';
import type { TobCategory } from '@/utils/tax-calc';

interface TobOption { value: TobCategory; label: string; detail: string; }

interface InputsPanelSignature {
  Args: {
    portfolioValue: number;
    costBasis: number;
    expectedReturnPct: number;
    yearsToProject: number;
    yearlyContribution: number;
    cgtRatePct: number;
    tobCategory: TobCategory;
    brokerReporting: 'opt-in' | 'opt-out';
    brokerDescription: string;
    includePortfolioTax: boolean;
    onPortfolio: (v: number) => void;
    onBasis: (v: number) => void;
    onReturn: (e: Event) => void;
    onYears: (e: Event) => void;
    onContribution: (v: number) => void;
    onCgtRate: (e: Event) => void;
    onTob: (v: TobCategory) => void;
    onBroker: (v: 'opt-in' | 'opt-out') => void;
    onTogglePortfolioTax: () => void;
  };
}

export default class InputsPanel extends Component<InputsPanelSignature> {
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

  get tobOptions(): TobOption[] {
    return [
      { value: 'shares', label: 'Shares', detail: '0.12%' },
      { value: 'bonds', label: 'Bonds', detail: '0.12%' },
      { value: 'etfAccHigh', label: 'Acc. ETF (1.32%)', detail: '1.32%' },
      { value: 'etfAccLow', label: 'Acc. ETF (0.12%)', detail: '0.12%' },
      { value: 'etfDist', label: 'Dist. ETF', detail: '0.12%' },
    ];
  }

  isTob = (v: TobCategory) => this.args.tobCategory === v;
  get isBrokerOptIn() { return this.args.brokerReporting === 'opt-in'; }
  get isBrokerOptOut() { return this.args.brokerReporting === 'opt-out'; }

  <template>
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
            <Input @type="text" inputmode="numeric" class="tabular-nums pl-7"
              {{this.euroMask @onPortfolio @portfolioValue}} />
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
            <Input @type="text" inputmode="numeric" class="tabular-nums pl-7"
              {{this.euroMask @onBasis @costBasis}} />
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
            <Input @type="number" value={{@expectedReturnPct}} step="0.5" min="0" max="50"
              class="tabular-nums pr-7" {{on "input" @onReturn}} />
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
            <Input @type="number" value={{@yearsToProject}} step="1" min="1" max="30"
              class="tabular-nums pr-7" {{on "input" @onYears}} />
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
            <Input @type="text" inputmode="numeric" class="tabular-nums pl-7"
              {{this.euroMask @onContribution @yearlyContribution}} />
          </div>
        </div>

        <div class="space-y-2">
          <div class="flex items-center gap-1.5">
            <Label class="text-xs text-muted-foreground">CGT rate</Label>
            <Tooltip>
              <TooltipTrigger>
                <svg class="h-3.5 w-3.5 text-muted-foreground/60 hover:text-muted-foreground transition-colors cursor-help" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4m0-4h.01"/></svg>
              </TooltipTrigger>
              <TooltipContent @side="top">Capital gains tax rate applied to realized gains above the exemption. Belgian law sets this at 10%.</TooltipContent>
            </Tooltip>
          </div>
          <div class="relative">
            <Input @type="number" value={{@cgtRatePct}} step="0.5" min="0" max="100"
              class="tabular-nums pr-7" {{on "input" @onCgtRate}} />
            <span class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-xs text-muted-foreground">%</span>
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
              {{on "click" (fn @onTob opt.value)}}>
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
            {{on "click" (fn @onBroker "opt-in")}}>Broker withholds</button>
          <button type="button"
            class="rounded-lg border px-3 py-1.5 text-xs font-medium transition-all duration-200
              {{if this.isBrokerOptOut
                'border-primary bg-primary text-primary-foreground shadow-sm'
                'border-border text-muted-foreground hover:border-foreground/20 hover:bg-accent'}}"
            {{on "click" (fn @onBroker "opt-out")}}>Self-report</button>
        </div>
        <p class="text-xs text-muted-foreground leading-relaxed">
          {{@brokerDescription}}
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
              {{if @includePortfolioTax
                'border-primary bg-primary text-primary-foreground shadow-sm'
                'border-border text-muted-foreground hover:border-foreground/20 hover:bg-accent'}}"
            {{on "click" @onTogglePortfolioTax}}>Include (≥ €1M)</button>
          <button type="button"
            class="rounded-lg border px-3 py-1.5 text-xs font-medium transition-all duration-200
              {{unless @includePortfolioTax
                'border-primary bg-primary text-primary-foreground shadow-sm'
                'border-border text-muted-foreground hover:border-foreground/20 hover:bg-accent'}}"
            {{on "click" @onTogglePortfolioTax}}>Exclude</button>
        </div>
        {{#if @includePortfolioTax}}
          <p class="text-xs text-muted-foreground leading-relaxed">
            0.15% per year on the total account value when it exceeds €1,000,000. This is deducted annually from your portfolio, reducing your compounding base.
          </p>
        {{/if}}
      </div>
    </section>
  </template>
}

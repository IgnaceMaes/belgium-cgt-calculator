import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import type { YearResult } from '@/utils/tax-calc';
import { fmt } from '@/utils/format';

interface DetailSection {
  label: string;
  color: string;
  rows: YearResult[];
}

interface YearByYearSignature {
  Args: {
    sections: DetailSection[];
    showDetails: boolean;
    includePortfolioTax: boolean;
    onToggle: () => void;
  };
}

export default class YearByYear extends Component<YearByYearSignature> {
  f = (v: number) => fmt(v);

  <template>
    <section>
      <button type="button"
        class="flex w-full items-center justify-between rounded-xl border border-border bg-card px-5 py-3.5 text-sm text-muted-foreground transition-all hover:bg-accent"
        {{on "click" @onToggle}}>
        <span>Year-by-year breakdown</span>
        <svg class="h-4 w-4 text-muted-foreground transition-transform duration-200 {{if @showDetails 'rotate-180' ''}}" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {{#if @showDetails}}
        <div class="mt-4 space-y-6">
          {{#each @sections as |section|}}
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
                      {{#if @includePortfolioTax}}
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
                        {{#if @includePortfolioTax}}
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
  </template>
}

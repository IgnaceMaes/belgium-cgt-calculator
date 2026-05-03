import Component from '@glimmer/component';
import { HOLD_COLOR, HARVEST_COLOR, SMART_COLOR } from '@/utils/colors';

interface StrategyExplainerSignature {
  Args: { cgtRatePct: number };
}

export default class StrategyExplainer extends Component<StrategyExplainerSignature> {
  holdColor = HOLD_COLOR;
  harvestColor = HARVEST_COLOR;
  smartColor = SMART_COLOR;

  <template>
    <section class="rounded-2xl border border-border bg-card p-6 backdrop-blur-sm space-y-4">
      <h2 class="text-sm font-semibold text-foreground">How the strategies work</h2>
      <div class="grid gap-4 sm:grid-cols-3">
        <div class="space-y-2">
          <div class="flex items-center gap-2">
            <div class="h-2 w-2 rounded-full" style="background:{{this.holdColor}}"></div>
            <span class="text-xs font-medium text-foreground">Hold</span>
          </div>
          <p class="text-xs text-muted-foreground leading-relaxed">Buy and hold until the end. No CGT or TOB is paid until the final sale — all gains compound untaxed. Simple, but you forfeit the annual €10K exemption each year (unused exemptions can carry forward €1K/year, up to a max €15K).</p>
        </div>
        <div class="space-y-2">
          <div class="flex items-center gap-2">
            <div class="h-2 w-2 rounded-full" style="background:{{this.harvestColor}}"></div>
            <span class="text-xs font-medium text-foreground">Full harvest</span>
          </div>
          <p class="text-xs text-muted-foreground leading-relaxed">Sell everything each year and immediately rebuy. This realizes all gains annually, using the €10K exemption each year. Unused exemption carries forward (€1K/year, max €5K extra). But you pay TOB on every sell &amp; buy cycle, and gains above the exemption are taxed at {{@cgtRatePct}}%. Assumes you can rebuy at the same price you sold — in practice there may be a small spread.</p>
        </div>
        <div class="space-y-2">
          <div class="flex items-center gap-2">
            <div class="h-2 w-2 rounded-full" style="background:{{this.smartColor}}"></div>
            <span class="text-xs font-medium text-foreground">Smart harvest</span>
          </div>
          <p class="text-xs text-muted-foreground leading-relaxed">Sell only enough each year to realize gains up to the €10K exemption. Unused exemption carries forward €1K/year (max €5K extra, so up to €15K total). Minimizes TOB while still harvesting the tax-free allowance. Usually the best strategy when TOB is high. Assumes you can rebuy at the same price you sold — in practice there may be a small spread.</p>
        </div>
      </div>
    </section>
  </template>
}

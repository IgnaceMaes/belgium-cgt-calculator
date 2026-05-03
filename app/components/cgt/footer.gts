import type { TemplateOnlyComponent } from '@ember/component/template-only';

interface FooterSignature {
  Args: { cgtRatePct: number };
}

const CgtFooter: TemplateOnlyComponent<FooterSignature> = <template>
  <footer class="rounded-2xl border border-border bg-card px-6 py-5">
    <div class="flex items-start gap-3">
      <div
        class="mt-0.5 shrink-0 rounded-full border border-border h-4 w-4 flex items-center justify-center"
      >
        <svg
          class="h-2.5 w-2.5 text-muted-foreground"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          stroke-width="2"
        ><path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
          /></svg>
      </div>
      <div class="text-xs text-muted-foreground space-y-1 leading-relaxed">
        <p><span class="text-foreground font-medium">Key rules:</span>
          {{@cgtRatePct}}% CGT on realized gains · €10K/year exempt (unused €1K
          carries forward, max €5K extra) · losses offset gains within the same
          year only · TOB on every buy &amp; sell</p>
        <p><span class="text-foreground font-medium">Note:</span>
          The hold scenario defers all CGT to the final sale. Harvest scenarios
          pay CGT each year but reset the cost basis, using the exemption
          annually. Broker opt-in withholds
          {{@cgtRatePct}}% on all gains upfront; you reclaim the exemption via
          your tax return ~2 years later. Harvest and smart harvest assume you
          can rebuy at the same price you sold — in practice, the bid-ask spread
          and intraday price movement may cause small deviations.</p>
        <p><span class="text-foreground font-medium">Disclaimer:</span>
          Estimates only. Based on the Belgian Arizona coalition tax reform
          proposal. Consult a tax advisor for your specific situation.</p>
      </div>
    </div>
  </footer>

  <div class="text-center pb-8">
    <p
      class="text-[10px] text-muted-foreground/40 uppercase tracking-[0.2em]"
    >Built with Ember.js</p>
  </div>
</template>;

export default CgtFooter;

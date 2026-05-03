import Component from '@glimmer/component';
import { htmlSafe } from '@ember/template';
import { Badge } from '@/components/ui/badge';
import { fmt } from '@/utils/format';

interface ScenarioData {
  name: string;
  key: string;
  color: string;
  final: number;
  totalTax: number;
  grossProfit: number;
  netProfit: number;
  borderClass: string;
  bgClass: string;
  badgeClass: string;
}

interface ResultCardSignature {
  Args: {
    scenarios: ScenarioData[];
    totalInvested: number;
    bestStrategy: string;
    harvestEqualsSmart: boolean;
    smartVsHold: number;
  };
}

export default class ResultCards extends Component<ResultCardSignature> {
  f = (v: number) => fmt(v);
  isPos = (v: number) => v >= 0;
  bgStyle = (color: string) => htmlSafe(`background:${color}`);

  isBest = (key: string) => {
    const { bestStrategy, harvestEqualsSmart } = this.args;
    if (harvestEqualsSmart && (key === 'harvest' || key === 'smart')) {
      return bestStrategy === 'harvest' || bestStrategy === 'smart';
    }
    return bestStrategy === key;
  };

  <template>
    <section class="space-y-4">
      <h2 class="text-sm font-semibold text-foreground">Net portfolio after exit</h2>

      <div class="grid gap-3 sm:grid-cols-3">
        {{#each @scenarios as |s|}}
          <div
            class="group relative rounded-2xl border p-5 transition-all duration-300
              {{if (this.isBest s.key) s.bgClass 'border-border bg-card'}}"
          >
            {{#if (this.isBest s.key)}}
              <Badge
                class="absolute -top-2.5 right-3
                  {{s.badgeClass}}
                  text-[10px] uppercase tracking-wider"
              >Best</Badge>
            {{/if}}
            <div
              class="flex items-center gap-2 text-xs text-muted-foreground mb-1.5"
            >
              <div
                class="h-2 w-2 rounded-full"
                style={{this.bgStyle s.color}}
              ></div>
              {{s.name}}
            </div>
            <div
              class="text-2xl font-semibold tabular-nums text-foreground"
            >{{this.f s.final}}</div>
            <div class="mt-3 space-y-1 text-xs text-muted-foreground">
              <div class="flex justify-between"><span>Invested</span><span
                  class="tabular-nums"
                >{{this.f @totalInvested}}</span></div>
              <div class="flex justify-between"><span>Gross profit</span><span
                  class="tabular-nums
                    {{if
                      (this.isPos s.grossProfit)
                      'text-emerald-400'
                      'text-red-400'
                    }}"
                >{{if (this.isPos s.grossProfit) "+" ""}}{{this.f
                    s.grossProfit
                  }}</span></div>
              <div class="flex justify-between"><span>Tax paid</span><span
                  class="tabular-nums text-orange-400"
                >−{{this.f s.totalTax}}</span></div>
              <div
                class="flex justify-between border-t border-border pt-1 mt-1"
              ><span class="font-medium text-foreground">Net profit</span><span
                  class="tabular-nums font-medium
                    {{if
                      (this.isPos s.netProfit)
                      'text-emerald-400'
                      'text-red-400'
                    }}"
                >{{if (this.isPos s.netProfit) "+" ""}}{{this.f
                    s.netProfit
                  }}</span></div>
            </div>
          </div>
        {{/each}}
      </div>

      <div class="flex flex-col gap-2">
        <div
          class="flex items-center justify-between rounded-xl border border-border bg-card px-5 py-3.5"
        >
          <span class="text-sm text-muted-foreground">Smart harvest vs. hold</span>
          <span
            class="text-xl font-bold tabular-nums
              {{if
                (this.isPos @smartVsHold)
                'text-emerald-400'
                'text-red-400'
              }}"
          >
            {{if (this.isPos @smartVsHold) "+" ""}}{{this.f @smartVsHold}}
          </span>
        </div>
      </div>
    </section>
  </template>
}

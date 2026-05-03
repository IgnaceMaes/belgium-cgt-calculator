import Component from '@glimmer/component';
import { htmlSafe } from '@ember/template';
import { fmt } from '@/utils/format';

export interface BarItem {
  label: string;
  value: number;
  color: string;
}

interface BarChartSignature {
  Args: { items: BarItem[] };
  Element: HTMLDivElement;
}

export default class BarChart extends Component<BarChartSignature> {
  get maxVal() {
    return Math.max(...this.args.items.map((i) => i.value), 1);
  }
  pct = (v: number) => `${((v / this.maxVal) * 100).toFixed(1)}%`;
  fmtV = (v: number) => fmt(v);
  barStyle = (value: number, color: string) => htmlSafe(`width:${this.pct(value)};background:${color}`);

  <template>
    <div class="space-y-4" ...attributes>
      {{#each @items as |item|}}
        <div class="space-y-1.5">
          <div class="flex items-baseline justify-between text-sm">
            <span class="text-muted-foreground">{{item.label}}</span>
            <span class="tabular-nums font-medium text-foreground">{{this.fmtV
                item.value
              }}</span>
          </div>
          <div class="h-1.5 w-full overflow-hidden rounded-full bg-muted">
            <div
              class="h-full rounded-full transition-all duration-700 ease-out"
              style={{this.barStyle item.value item.color}}
            ></div>
          </div>
        </div>
      {{/each}}
    </div>
  </template>
}

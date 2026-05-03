import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { htmlSafe } from '@ember/template';
import { on } from '@ember/modifier';
import { fmtK } from '@/utils/format';

export interface LineChartPoint {
  x: number;
  y: number;
  unrealizedGain?: number;
}
export interface LineChartSeries {
  label: string;
  color: string;
  points: LineChartPoint[];
}

interface LineChartSignature {
  Args: { series: LineChartSeries[] };
  Element: HTMLDivElement;
}

export default class LineChart extends Component<LineChartSignature> {
  padL = 62;
  padR = 20;
  padT = 20;
  padB = 36;
  w = 600;
  h = 300;
  @tracked hoverIdx: number | null = null;

  get allPoints() {
    return this.args.series.flatMap((s) => s.points);
  }
  get xMin() {
    return Math.min(...this.allPoints.map((p) => p.x));
  }
  get xMax() {
    return Math.max(...this.allPoints.map((p) => p.x));
  }
  get yMin() {
    return (
      Math.floor(Math.min(...this.allPoints.map((p) => p.y)) / 10_000) * 10_000
    );
  }
  get yMax() {
    return (
      Math.ceil(Math.max(...this.allPoints.map((p) => p.y)) / 10_000) * 10_000
    );
  }

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
    return (
      this.padL + ((x - this.xMin) / range) * (this.w - this.padL - this.padR)
    );
  };

  sy = (y: number) => {
    const range = this.yMax - this.yMin || 1;
    return (
      this.padT +
      (1 - (y - this.yMin) / range) * (this.h - this.padT - this.padB)
    );
  };

  pathD = (points: LineChartPoint[]) =>
    points
      .map(
        (p, i) =>
          `${i === 0 ? 'M' : 'L'}${this.sx(p.x).toFixed(1)},${this.sy(p.y).toFixed(1)}`,
      )
      .join(' ');

  areaD = (points: LineChartPoint[]) => {
    const line = this.pathD(points);
    const last = points.at(-1);
    const first = points.at(0);
    if (!last || !first) return line;
    return `${line} L${this.sx(last.x).toFixed(1)},${(this.h - this.padB).toFixed(1)} L${this.sx(first.x).toFixed(1)},${(this.h - this.padB).toFixed(1)} Z`;
  };

  lastPoint = (points: LineChartPoint[]) => {
    const p = points.at(-1);
    return p ? [p] : [];
  };
  fmtTick = (v: number) => fmtK(v);
  bgStyle = (color: string) => htmlSafe(`background:${color}`);

  onMouseMove = (e: MouseEvent) => {
    const svg = e.currentTarget as SVGSVGElement;
    const rect = svg.getBoundingClientRect();
    const mouseX = ((e.clientX - rect.left) / rect.width) * this.w;
    const range = this.xMax - this.xMin || 1;
    const dataX =
      this.xMin +
      ((mouseX - this.padL) / (this.w - this.padL - this.padR)) * range;
    const idx = Math.round(dataX - this.xMin);
    if (idx >= 0 && idx <= this.xMax - this.xMin) {
      this.hoverIdx = idx;
    } else {
      this.hoverIdx = null;
    }
  };

  onMouseLeave = () => {
    this.hoverIdx = null;
  };

  get hoverX(): number | null {
    if (this.hoverIdx === null) return null;
    return this.sx(this.xMin + this.hoverIdx);
  }

  get hoverData():
    | {
        label: string;
        color: string;
        value: string;
        unrealizedGain: string | null;
      }[]
    | null {
    if (this.hoverIdx === null) return null;
    return this.args.series.map((s) => {
      const p = s.points[this.hoverIdx!];
      return {
        label: s.label,
        color: s.color,
        value: p ? fmtK(p.y) : '—',
        unrealizedGain:
          p?.unrealizedGain != null ? fmtK(p.unrealizedGain) : null,
      };
    });
  }

  get hoverYear(): number | null {
    if (this.hoverIdx === null) return null;
    return this.xMin + this.hoverIdx;
  }

  get tooltipX(): number {
    const x = this.hoverX ?? 0;
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

  get tooltipH() {
    if (!this.hoverData) return 0;
    let h = 24;
    for (const d of this.hoverData) {
      h += d.unrealizedGain ? 30 : 18;
    }
    return h + 4;
  }

  get tooltipDotX() {
    return this.tooltipX + 14;
  }
  get tooltipLabelX() {
    return this.tooltipX + 24;
  }
  get tooltipValueX() {
    return this.tooltipX + 162;
  }

  tooltipItemY = (idx: number) => {
    if (!this.hoverData) return this.tooltipY + 32;
    let y = this.tooltipY + 32;
    for (let i = 0; i < idx; i++) {
      y += this.hoverData[i]?.unrealizedGain ? 30 : 18;
    }
    return y;
  };

  <template>
    <div class="w-full" ...attributes>
      {{! template-lint-disable no-invalid-interactive }}
      <svg
        viewBox="0 0 {{this.w}} {{this.h}}"
        class="w-full h-auto"
        preserveAspectRatio="xMidYMid meet"
        role="img"
        {{on "mousemove" this.onMouseMove}}
        {{on "mouseleave" this.onMouseLeave}}
      >
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
          <line
            x1={{this.padL}}
            x2={{this.w}}
            y1={{this.sy tick}}
            y2={{this.sy tick}}
            stroke="currentColor"
            stroke-opacity="0.06"
            stroke-width="1"
          />
          <text
            x={{this.padL}}
            y={{this.sy tick}}
            dx="-8"
            dy="4"
            text-anchor="end"
            class="fill-muted-foreground"
            font-size="10"
            font-family="Inter Variable, sans-serif"
          >{{this.fmtTick tick}}</text>
        {{/each}}
        {{#each this.xTicks as |tick|}}
          <text
            x={{this.sx tick}}
            y={{this.h}}
            dy="-6"
            text-anchor="middle"
            class="fill-muted-foreground"
            font-size="10"
            font-family="Inter Variable, sans-serif"
          >{{tick}}</text>
        {{/each}}

        {{! Area fills }}
        {{#each @series as |s idx|}}
          <path d={{this.areaD s.points}} fill="url(#area-{{idx}})" />
        {{/each}}

        {{! Lines }}
        {{#each @series as |s|}}
          <path
            d={{this.pathD s.points}}
            fill="none"
            stroke={{s.color}}
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
          {{#each (this.lastPoint s.points) as |p|}}
            <circle
              cx={{this.sx p.x}}
              cy={{this.sy p.y}}
              r="3.5"
              fill={{s.color}}
            />
            <circle
              cx={{this.sx p.x}}
              cy={{this.sy p.y}}
              r="6"
              fill={{s.color}}
              fill-opacity="0.15"
            />
          {{/each}}
        {{/each}}

        {{! Hover crosshair & dots }}
        {{#if this.hoverX}}
          <line
            x1={{this.hoverX}}
            x2={{this.hoverX}}
            y1={{this.padT}}
            y2={{this.h}}
            stroke="currentColor"
            stroke-opacity="0.2"
            stroke-width="1"
            stroke-dasharray="3 3"
          />
          {{#each @series as |s|}}
            {{#each (this.hoverDots s.points) as |p|}}
              <circle
                cx={{this.sx p.x}}
                cy={{this.sy p.y}}
                r="4"
                fill={{s.color}}
                stroke="var(--background, #0a0a12)"
                stroke-width="2"
              />
            {{/each}}
          {{/each}}

          {{! Tooltip box }}
          <g>
            <rect
              x={{this.tooltipX}}
              y={{this.tooltipY}}
              width="170"
              height={{this.tooltipH}}
              rx="6"
              fill="var(--popover, #1a1a2e)"
              fill-opacity="0.95"
              stroke="var(--border)"
              stroke-width="0.5"
            />
            <text
              x={{this.tooltipX}}
              y={{this.tooltipY}}
              dx="8"
              dy="16"
              font-size="10"
              font-weight="600"
              class="fill-foreground"
              font-family="Inter Variable, sans-serif"
            >
              Year
              {{this.hoverYear}}
            </text>
            <text
              x={{this.tooltipValueX}}
              y={{this.tooltipY}}
              dy="16"
              font-size="8"
              text-anchor="end"
              class="fill-muted-foreground"
              font-family="Inter Variable, sans-serif"
              opacity="0.6"
            >net / unrealized</text>
            {{#each this.hoverData as |d idx|}}
              <circle
                cx={{this.tooltipDotX}}
                cy={{this.tooltipItemY idx}}
                r="3"
                fill={{d.color}}
              />
              <text
                x={{this.tooltipLabelX}}
                y={{this.tooltipItemY idx}}
                dy="3.5"
                font-size="9"
                class="fill-muted-foreground"
                font-family="Inter Variable, sans-serif"
              >{{d.label}}</text>
              <text
                x={{this.tooltipValueX}}
                y={{this.tooltipItemY idx}}
                dy="3.5"
                font-size="9"
                font-weight="500"
                text-anchor="end"
                class="fill-foreground"
                font-family="Inter Variable, sans-serif"
              >{{d.value}}</text>
              {{#if d.unrealizedGain}}
                <text
                  x={{this.tooltipValueX}}
                  y={{this.tooltipItemY idx}}
                  dy="14"
                  font-size="8"
                  text-anchor="end"
                  class="fill-muted-foreground"
                  font-family="Inter Variable, sans-serif"
                  opacity="0.6"
                >↳ {{d.unrealizedGain}} unrealized</text>
              {{/if}}
            {{/each}}
          </g>
        {{/if}}
      </svg>

      {{! Legend }}
      <div
        class="flex flex-wrap items-center justify-center gap-4 pt-3 text-xs"
      >
        {{#each @series as |s|}}
          <div class="flex items-center gap-1.5">
            <div
              class="h-2 w-2 rounded-full"
              style={{this.bgStyle s.color}}
            ></div>
            <span class="text-muted-foreground">{{s.label}}</span>
          </div>
        {{/each}}
      </div>
    </div>
  </template>
}

# 🇧🇪 Belgium Capital Gains Tax Calculator

> Compare hold vs. harvest strategies under Belgium's new capital gains tax.

A client-side simulator that projects how different sell/rebuy strategies affect your portfolio over time — factoring in CGT, TOB, exemptions, carry-forward, broker withholding refunds, and portfolio tax.

**[→ Try it live](https://ignacemaes.github.io/belgium-cgt-calculator/)**

## Strategies

| Strategy | Description |
|---|---|
| **Hold** | Buy and hold until exit. All gains compound untaxed, but you forfeit the annual exemption. |
| **Full Harvest** | Sell everything yearly and rebuy. Uses the €10K exemption each year, but pays TOB on every cycle. |
| **Smart Harvest** | Sell only enough to realize gains up to the exemption. Minimizes TOB while harvesting the tax-free allowance. |

## Tax Rules Modeled

- **CGT** — configurable rate (default 10%) on realized gains above the exemption
- **Exemption** — €10K/year, with €1K/year carry-forward (max €5K)
- **TOB** — transaction tax on every buy & sell (0.12% or 1.32% depending on instrument)
- **Broker withholding** — opt-in mode withholds CGT on full gain, refund ~2 years later
- **Portfolio tax** — 0.15% annually on accounts ≥ €1M

## Tech

Built with [Ember.js](https://emberjs.com/) · [TypeScript](https://www.typescriptlang.org/) · [Tailwind CSS](https://tailwindcss.com/) · [Vite](https://vite.dev/) · WebGPU shader background

## Development

```bash
pnpm install
pnpm start        # http://localhost:4200
pnpm test         # run test suite
pnpm lint         # lint everything
pnpm build        # production build
```

## License

MIT

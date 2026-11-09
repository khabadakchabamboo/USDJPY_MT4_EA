# USDJPY Minimum Shuffle EA

## Configuration

- MetaTrader 4 / MQL4, USDJPY Forex chart, JPY account only.
- Uses the broker's minimum volume, normally 0.01 lot / 1,000 USD at Rakuten MT4.
- At most one open position on this symbol; no pyramiding or hedging.
- Default movement trigger: strictly greater than JPY 100 in either direction.
- Default take-profit: JPY 100 gross price profit, rounded away from entry to a tradable tick.
- No initial loss SL, daily loss limit or equity cutoff. Version 1.05 also
  hosts the [common account-wide profit protector](../JP225_MT4_EA/Common/ProfitProtector_MT4.mqh):
  activation 100 JPY gross **per lot**, minimum lock 50 JPY gross **per lot**,
  then a continuous 50 JPY gross-per-lot trailing SL using broker tick conversion.
- The protector covers all filled positions on all account symbols/magics, not
  only this strategy's position. It changes SL only and never loosens a tighter
  stop. Pending orders are untouched. A one-second timer keeps monitoring even
  when the USDJPY chart has no ticks or this strategy is waiting.
- Live trading is supported but requires `AllowLiveTrading=true`.

No profitability or loss limit is implied. Margin closeout, price gaps, variable
spreads, swap, disconnections, and repeated realized losses remain possible.
Do not run this EA on Japan 225 or a non-JPY account.

## Execution rules

The reference is the last confirmed **actual execution price for this EA's
symbol and MagicNumber**, not the last account-wide trade.

`movementJPY = (midpoint - referencePrice) * contractSize * minimumLots`

| State | Upward movement > trigger | Downward movement > trigger |
| --- | --- | --- |
| Flat | Open minimum-size buy | Open minimum-size sell |
| Long | Hold; do not add | Close buy at market, become flat |
| Short | Close sell at market, become flat | Hold; do not add |

Every successful open or close resets the reference to its actual fill. Closing
does not also reverse on the same tick. A subsequent fresh movement is needed
to open again. Exact equality to the trigger does not trade.

Automatic TP exits and external closures of a tracked strategy position also
reset the reference to the actual closing fill. Detection occurs on a subsequent
tick; that tick is used only for reconciliation, not another trade.

When no position, saved reference, or loaded strategy history exists, the first
valid midpoint seeds the reference without placing an order. Set Account History
to **All History** before first use or recovery.

At 1,000 USD, JPY 100 corresponds to a 0.100 USDJPY price change (10 pips).
For a buy filled at 150.000, TP is 150.100; for a sell it is 149.900.
Signal comparison uses midpoint versus execution price, deliberately matching
the requested design. It is spread-asymmetric: this is not a midpoint-to-midpoint
signal. A monetary trigger is not a guaranteed realized profit/loss.

## Installation

1. In the intended Rakuten MT4 terminal, choose **File > Open Data Folder**.
2. Copy [USDJPY_MinimumShuffle.ex4](./USDJPY_MinimumShuffle.ex4) into `MQL4\Experts`.
   Refresh Navigator's Expert Advisors list or restart the terminal.
3. For source changes, also copy [USDJPY_MinimumShuffle.mq4](./USDJPY_MinimumShuffle.mq4)
   into `MQL4\Experts\USDJPY_MT4_EA`, keep the `JP225_MT4_EA` library repository
   as its sibling, open it in MetaEditor, and compile with **F7**.
4. Set Account History to **All History**.
5. Attach the compiled EA to the actual USDJPY chart (broker suffixes are supported).
   Chart timeframe does not affect signals; the EA evaluates incoming ticks.
6. Enable EA trading permissions and terminal AutoTrading.
7. Test on demo first. For live operation, explicitly set `AllowLiveTrading=true`
   in the EA inputs. This input gates strategy orders only; shared protection
   operates whenever chart and terminal trading permissions allow it, even
   with `AllowLiveTrading=false`. Multiple EA hosts coordinate protection
   requests. Broker constraints, delays, costs, gaps and slippage mean the
   profit lock is not a guaranteed net realized profit.

Use one EA instance for this symbol/account and do not manually trade the symbol
or run other EAs on it. Other-symbol positions are outside this EA's cap.
Separate terminal installations do not share its terminal-local coordination.

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `TriggerJPY` | 100 | Movement value at minimum volume, in account JPY |
| `TakeProfitJPY` | 100 | Gross entry-to-exit price-profit target |
| `AllowLiveTrading` | false | Explicit live-account permission |
| `MagicNumber` | 9251100 | Stable strategy identity; do not change with an open position |
| `SlippagePoints` | 10 | Market-order slippage allowance in MT4 points, not pips |

On a three-decimal USDJPY symbol, 10 points is 1 pip. Execution policies can
make the slippage allowance ineffective; fills are not guaranteed.

## TP handling and error behavior

Opening orders include a server-side TP and no SL. If the broker rejects that
order, the EA logs the error and does not retry without TP. It does not silently
widen the target to satisfy the broker's stop distance.

After an actual entry fill, it adjusts TP if required to align the target with
that fill. If adjustment fails, the original TP remains, an error is logged, and
it retries on later ticks. Therefore the target can temporarily differ from
JPY 100. If the executable quote has already crossed the corrected target, it
requests a market close; actual profit can differ because of execution.

TP rounding may produce slightly more than the requested gross amount. Spread
is already reflected in actual entry/exit prices; swap and any commissions are
not included in the JPY target. The EA does not promise JPY 100 net profit.

Opposite signals may close at a loss. No transaction is counted as hypothetical
"loss reduction"; use realized P/L and total equity when assessing results.

Trade timeout error 128 has an uncertain execution outcome. The EA persists an
execution halt and does not retry the order. Disable AutoTrading and verify
broker orders/history first. Only after reconciling the outcome, delete the
specific `.halt` terminal global variable named in the Experts log using F3,
reattach the EA, and restore trading permissions. Do not clear all state variables.

Foreign/pending orders on the same symbol, multiple strategy positions, or a
position that is no longer minimum size pause all EA actions with an Experts-log
message. The EA does not automatically liquidate or alter conflicting orders.
Existing server-side TPs continue operating.

## Persistence

Reference and tracked ticket use MT4 terminal global variables, namespaced by
account, server, demo/live/test mode, symbol, and MagicNumber. They are flushed
after executions. A tracked position's actual closing price is recovered from
history after restart, including TP exits during downtime.

If tracked history is unavailable, trading pauses rather than guessing a new
reference. MT4 global variables expire after four weeks without access; after
expiration recovery uses currently loaded strategy history. Without that history,
the initial-midpoint behavior applies and is explicitly logged.

Backtests reset their own TEST state. Do not run simultaneous backtests for the
same identity. Live/demo state is not erased by tester startup.

## Verification status and pre-live checklist

Compiled with the locally installed Rakuten MetaEditor: **0 errors, 0 warnings**.
The accompanying EX4 is the resulting executable. Source-extracted movement and
TP arithmetic, a documented transition model, and source contracts passed 29
checks. These checks are not a broker-runtime execution test.

No broker trade was placed and no terminal EA was activated. Broker execution,
restart recovery, and server-side TP behavior still require Rakuten demo testing.

Verify on demo:

- No entry until movement is strictly greater than the threshold.
- Flat -> long -> flat, and flat -> short -> flat.
- A same-direction signal never creates a second position.
- TP closure resets the reference to the closing fill.
- Restart with an open position preserves its volume, TP, and reference.
- Restart after an offline TP exit recovers the closing fill.
- Rejected orders do not advance the reference.
- Live orders are blocked while `AllowLiveTrading=false`.
- Broker minimum volume, stop level, tick size, and required margin are as expected.

Use tick-quality testing with realistic variable spreads. A one-position cap is
not a cumulative loss cap. Keep AutoTrading off on live until these checks pass.

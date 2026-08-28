import math
import random
import csv
import json
import ctypes
import argparse
import logging
import sys
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Optional

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
log = logging.getLogger("K2-BACKTEST")

@dataclass
class BacktestConfig:
    starting_balance:      float = 200_000.0
    daily_loss_limit_usd:  float = 10_000.0
    internal_gate_usd:     float =  6_000.0
    fill_latency_ms:       float = 35.0
    commission_per_lot:    float = 3.00
    point_value_per_lot:   float = 100.0
    lot_step:              float = 0.1
    min_lots:              float = 0.5
    atr_baseline:          float = 25.0
    atr_period_bars:       int   = 14
    stop_mult:             float = 1.5
    tp_mult:               float = 2.0
    action_long_thresh:    float =  0.15
    action_short_thresh:   float = -0.15
    min_hold_seconds:      float = 95.0
    mc_scenarios:          int   = 1_000
    mc_seed:               int   = 42
    news_windows: list = field(default_factory=lambda: [
        (13, 25, 20),
        (18, 55, 30),
        (12, 25, 15),
        ( 8, 25, 15),
    ])

@dataclass
class Tick:
    timestamp: float
    bid:       float
    ask:       float
    volume:    float = 0.0

    @property
    def mid(self) -> float: return (self.bid + self.ask) / 2.0
    @property
    def spread(self) -> float: return self.ask - self.bid

@dataclass
class Bar5Min:
    timestamp: float
    open:  float
    high:  float
    low:   float
    close: float
    volume: float

@dataclass
class TradeRecord:
    timestamp:      float
    direction:      int
    lots:           float
    entry_price:    float
    exit_price:     float
    stop_price:     float
    tp_price:       float
    pnl_gross:      float
    commission:     float
    slippage_cost:  float
    pnl_net:        float
    exit_reason:    str
    hold_seconds:   float
    atr_at_entry:   float
    regime:         str
    equity_after:   float

class TickDataLoader:
    @staticmethod
    def load(path: str, max_ticks: int = None) -> list[Tick]:
        path = Path(path)
        ticks = []
        with open(path, newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    ticks.append(Tick(
                        timestamp = float(row['timestamp']),
                        bid       = float(row['bid']),
                        ask       = float(row['ask']),
                        volume    = float(row.get('volume', 0.0)),
                    ))
                except (ValueError, KeyError):
                    continue
                if max_ticks and len(ticks) >= max_ticks:
                    break
        log.info(f"[DATA] Loaded {len(ticks):,} ticks from {path.name}")
        return ticks

class ATRTracker:
    BAR_SECONDS = 300
    def __init__(self, period: int = 14):
        self.period  = period
        self._trs: deque = deque(maxlen=period)
        self._bar_start: Optional[float] = None
        self._bar_h = self._bar_l = self._bar_c = 0.0
        self._prev_close: Optional[float] = None
        self.current_atr: Optional[float] = None
        self.bars: list[Bar5Min] = []

    def push_tick(self, tick: Tick) -> Optional[float]:
        mid = tick.mid
        if self._bar_start is None:
            self._bar_start = tick.timestamp
            self._bar_h = self._bar_l = mid

        self._bar_h = max(self._bar_h, mid)
        self._bar_l = min(self._bar_l, mid)
        self._bar_c = mid

        if tick.timestamp - self._bar_start >= self.BAR_SECONDS:
            bar = Bar5Min(self._bar_start, mid, self._bar_h, self._bar_l, self._bar_c, tick.volume)
            self.bars.append(bar)
            self._close_bar(bar)
            self._bar_start = tick.timestamp
            self._bar_h = self._bar_l = mid
            return self.current_atr
        return None

    def _close_bar(self, bar: Bar5Min) -> None:
        if self._prev_close is not None:
            tr = max(bar.high - bar.low, abs(bar.high - self._prev_close), abs(bar.low  - self._prev_close))
        else:
            tr = bar.high - bar.low
        self._trs.append(tr)
        self._prev_close = bar.close
        if len(self._trs) >= self.period:
            self.current_atr = sum(self._trs) / len(self._trs)

class SlippageModel:
    def __init__(self, seed: int = 42):
        random.seed(seed)
        self._rng = random.Random(seed)

    def sample_slippage(self, lots: float, is_news: bool = False, is_spike: bool = False) -> float:
        u = self._rng.gauss(0, 1)
        base_slip = math.exp(-0.85 + 0.6 * u)
        lot_factor = math.sqrt(max(lots, 0.5) / 0.5)
        if is_spike:
            multiplier = 5.0 / (self._rng.random() ** (1.0/1.5))
        elif is_news:
            multiplier = self._rng.uniform(2.5, 6.0)
        else:
            multiplier = 1.0
        return round(base_slip * lot_factor * multiplier, 3)

class DeathLoopStress:
    def __init__(self, cfg: BacktestConfig):
        self.cfg = cfg

    def max_safe_lots(self, atr: float) -> float:
        denominator = atr * self.cfg.stop_mult * self.cfg.point_value_per_lot
        if denominator <= 0: return self.cfg.min_lots
        raw = self.cfg.internal_gate_usd / denominator
        stepped = math.floor(raw / self.cfg.lot_step) * self.cfg.lot_step
        return max(round(stepped, 2), self.cfg.min_lots)

class KesslerInference:
    def __init__(self, lib_path: Optional[str] = None):
        self._use_real = False
        self._lib = None
        self._ring: deque = deque(maxlen=20)
        if lib_path and Path(lib_path).exists():
            try:
                self._lib = ctypes.CDLL(lib_path)
                self._lib.kessler_init.restype  = ctypes.c_int
                self._lib.kessler_infer.restype = ctypes.c_float
                if self._lib.kessler_init():
                    self._use_real = True
                    log.info(f"[INFERENCE] Using real Zig library: {lib_path}")
                    weights_file = "kessler_v2_weights.bin"
                    if Path(weights_file).exists():
                        load_fn = self._lib.kessler_load_weights
                        load_fn.restype  = ctypes.c_int
                        load_fn.argtypes = [ctypes.c_char_p]
                        ok = load_fn(weights_file.encode('utf-8'))
                        log.info(f"[WEIGHTS] Load result: {'OK' if ok else 'FAILED'}")
                    else:
                        log.warning(f"[WEIGHTS] Missing {weights_file}")
            except Exception as e:
                log.warning(f"[INFERENCE] Library load failed ({e}) — replay mode")
        if not self._use_real:
            log.info("[INFERENCE] Replay mode: synthetic signals")

    def infer(self, tick: Tick, atr: float) -> float:
        if self._use_real:
            dt = datetime.fromtimestamp(tick.timestamp, tz=timezone.utc)
            time_val = (dt.hour + dt.minute / 60.0) / 24.0
            return float(self._lib.kessler_infer(ctypes.c_float(tick.mid), ctypes.c_float(time_val), ctypes.c_float(tick.spread), ctypes.c_float(tick.volume)))
        else:
            self._ring.append(tick.mid)
            if len(self._ring) < 20: return 0.0
            fast = sum(list(self._ring)[-5:]) / 5.0
            slow = sum(self._ring) / 20.0
            vol = math.sqrt(sum((p - slow)**2 for p in self._ring) / 20.0)
            if vol < 1e-6: return 0.0
            return math.tanh(((fast - slow) / vol) * 0.5)

    def push_bar(self, b: Bar5Min):
        if self._use_real and hasattr(self._lib, 'kessler_push_bar'):
            self._lib.kessler_push_bar(ctypes.c_float(b.open), ctypes.c_float(b.high), ctypes.c_float(b.low), ctypes.c_float(b.close), ctypes.c_float(b.volume))

class SpreadModel:
    def __init__(self, cfg: BacktestConfig):
        self.cfg = cfg
    def _in_news(self, ts: float) -> bool:
        dt = datetime.fromtimestamp(ts, tz=timezone.utc)
        mins = dt.hour * 60 + dt.minute
        for h, m, dur in self.cfg.news_windows:
            w = h * 60 + m
            if w <= mins < w + dur: return True
        return False
    def effective_spread(self, tick: Tick) -> float:
        if tick.spread > 0.1:
            return tick.spread * 3.5 if self._in_news(tick.timestamp) else tick.spread
        return 2.0
    def is_news(self, ts: float) -> bool:
        return self._in_news(ts)

class BacktestEnvironment:
    def __init__(self, cfg, inference, slip_model, spread_model):
        self.cfg = cfg
        self.inference = inference
        self.slip = slip_model
        self.spread_model = spread_model
        self.atr_tracker = ATRTracker(cfg.atr_period_bars)
        self.death_stress = DeathLoopStress(cfg)
        self.equity = cfg.starting_balance
        self.day_open_equity = cfg.starting_balance
        self._last_trade_time = 0.0
        self._position = 0
        self._entry_price = 0.0
        self._entry_lots = 0.0
        self._entry_sl = 0.0
        self._entry_tp = 0.0
        self._entry_time = 0.0
        self._entry_atr = 0.0
        self._last_day = None
        self.trades = []
        self.daily_pnl = {}
        self.guardian_trips = 0
        self._daily_loss = 0.0

    def _day_str(self, ts: float) -> str:
        return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d")

    def _check_day_rollover(self, ts: float):
        day = self._day_str(ts)
        if day != self._last_day:
            if self._last_day:
                self.daily_pnl[self._last_day] = self.equity - self.day_open_equity
            self.day_open_equity = self.equity
            self._daily_loss = 0.0
            self._last_day = day

    def _compute_lots(self, atr: float, action: float) -> float:
        atr_max = self.death_stress.max_safe_lots(atr)
        remaining = max(self.cfg.internal_gate_usd + self._daily_loss, 0)
        if remaining <= 0: return 0.0
        usd_per_lot = atr * self.cfg.stop_mult * self.cfg.point_value_per_lot
        if usd_per_lot <= 0: return self.cfg.min_lots
        raw_lots = (remaining * 0.15 * min(abs(action), 1.0)) / usd_per_lot
        lots = min(raw_lots, atr_max)
        lots = min(lots, (0.5 * self.cfg.atr_baseline) / (atr + 1e-8))
        return max(round(math.floor(lots / self.cfg.lot_step) * self.cfg.lot_step, 2), self.cfg.min_lots)

    def run(self, ticks: list[Tick]):
        atr = self.cfg.atr_baseline
        for i, tick in enumerate(ticks):
            if i % 100_000 == 0 and i > 0:
                log.info(f"Processed {i:,} ticks | Equity ${self.equity:,.0f} | Trades {len(self.trades)}")
            self._check_day_rollover(tick.timestamp)
            new_atr = self.atr_tracker.push_tick(tick)
            if new_atr: 
                atr = new_atr
                if self.atr_tracker.bars:
                    self.inference.push_bar(self.atr_tracker.bars[-1])

            dd = (self.day_open_equity - self.equity) / self.cfg.starting_balance
            if dd >= (self.cfg.internal_gate_usd / self.cfg.starting_balance):
                if self._position != 0: self._close_position(tick, "GUARDIAN")
                self.guardian_trips += 1
                self._daily_loss = 0.0
                self.day_open_equity = self.equity
                continue

            if self._position != 0:
                mid = tick.mid
                if self._position == 1:
                    if mid <= self._entry_sl: self._close_position(tick, "SL"); continue
                    elif mid >= self._entry_tp: self._close_position(tick, "TP")
                else:
                    if mid >= self._entry_sl: self._close_position(tick, "SL"); continue
                    elif mid <= self._entry_tp: self._close_position(tick, "TP")

            if tick.timestamp - self._last_trade_time < self.cfg.min_hold_seconds: continue

            action = self.inference.infer(tick, atr)
            new_dir = 1 if action > self.cfg.action_long_thresh else -1 if action < self.cfg.action_short_thresh else 0
            if self._position != 0 and self._position != new_dir:
                self._close_position(tick, "SIGNAL_FLIP")
            if new_dir != 0 and self._position == 0:
                self._open_position(new_dir, tick, atr, action)

    def _open_position(self, direction, tick, atr, action):
        lots = self._compute_lots(atr, action)
        if lots <= 0: return
        slip = self.slip.sample_slippage(lots, self.spread_model.is_news(tick.timestamp))
        fill = (tick.ask + slip) if direction == 1 else (tick.bid - slip)
        self._position, self._entry_price, self._entry_lots, self._entry_sl, self._entry_tp, self._entry_time, self._entry_atr = \
            direction, fill, lots, fill - atr * self.cfg.stop_mult * direction, fill + atr * self.cfg.tp_mult * direction, tick.timestamp, atr

    def _close_position(self, tick, reason):
        slip = self.slip.sample_slippage(self._entry_lots, self.spread_model.is_news(tick.timestamp))
        fill = (tick.bid - slip) if self._position == 1 else (tick.ask + slip)
        gross = (fill - self._entry_price) * self._position * self._entry_lots * self.cfg.point_value_per_lot
        comm = self.cfg.commission_per_lot * self._entry_lots
        net = gross - comm
        self.equity += net
        self._daily_loss = min(self._daily_loss + net, 0.0)
        self.trades.append(TradeRecord(tick.timestamp, self._position, self._entry_lots, self._entry_price, fill, self._entry_sl, self._entry_tp, gross, comm, slip * self._entry_lots * 100, net, reason, tick.timestamp - self._entry_time, self._entry_atr, "REGIME", self.equity))
        self._position = 0
        self._last_trade_time = tick.timestamp

class BacktestReport:
    def __init__(self, env): self.env = env
    def print_full(self):
        trades = self.env.trades
        print("\n" + "=" * 60)
        print("  KESSLER K2 — BACKTEST REPORT")
        print("=" * 60)
        print(f"  Trades       : {len(trades)}")
        print(f"  Net PnL      : ${self.env.equity - 200000:,.2f}")
        print(f"  Guardian trips: {self.env.guardian_trips}")
        if trades:
            wins = [t for t in trades if t.pnl_net > 0]
            print(f"  Win rate     : {len(wins)/len(trades):.1%}")
        print("=" * 60 + "\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["deathloop", "montecarlo", "backtest", "all"], default="all")
    parser.add_argument("--ticks", default=None)
    parser.add_argument("--lib", default=None)
    args = parser.parse_args()
    
    cfg = BacktestConfig()
    if args.mode == "backtest":
        if not args.ticks:
            print("ERROR: --ticks required")
            sys.exit(1)
        ticks = TickDataLoader.load(args.ticks)
        env = BacktestEnvironment(cfg, KesslerInference(args.lib), SlippageModel(), SpreadModel(cfg))
        env.run(ticks)
        BacktestReport(env).print_full()

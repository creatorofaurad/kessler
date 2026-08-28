import math
from enum import Enum
from dataclasses import dataclass, field
from collections import deque
from typing import Optional

class VolatilityRegime(Enum):
    EXTREME  = "EXTREME"    # ATR > 3× baseline: news spikes, open chaos
    ELEVATED = "ELEVATED"   # ATR 1.5–3× baseline: active session
    NORMAL   = "NORMAL"     # ATR 0.7–1.5× baseline: steady trend
    LOW      = "LOW"        # ATR < 0.7× baseline: consolidation/accumulation

@dataclass
class SizerConfig:
    balance:              float = 50_000.0
    daily_loss_limit_usd: float = 2_500.0   # 5% of $50k
    max_trades_per_day:   int   = 20        
    atr_baseline:         float = 25.0      
    point_value_per_lot:  float = 100.0     
    min_lots:             float = 0.5
    internal_gate_usd:    float = 1_500.0   # Internal guardian threshold
    lot_step:             float = 0.1       
    atr_stop_multiplier:  float = 0.5       

    risk_frac: dict = field(default_factory=lambda: {
        VolatilityRegime.EXTREME:  0.03,   
        VolatilityRegime.ELEVATED: 0.07,   
        VolatilityRegime.NORMAL:   0.12,   
        VolatilityRegime.LOW:      0.18,   
    })

def classify_regime(current_atr: float, cfg: SizerConfig) -> VolatilityRegime:
    ratio = current_atr / (cfg.atr_baseline + 1e-8)
    if   ratio > 3.0: return VolatilityRegime.EXTREME
    elif ratio > 1.5: return VolatilityRegime.ELEVATED
    elif ratio > 0.7: return VolatilityRegime.NORMAL
    else:             return VolatilityRegime.LOW

def _round_to_step(lots: float, step: float) -> float:
    return round(math.floor(lots / step) * step, 10)

def calculate_dynamic_lots(
    current_atr:        float,
    max_risk_usd:       float,          
    signal_confidence:  float = 0.5,    
    daily_pnl_so_far:   float = 0.0,    
    cfg:                SizerConfig = None,
) -> tuple[float, VolatilityRegime, dict]:
    
    if cfg is None:
        cfg = SizerConfig()

    regime = classify_regime(current_atr, cfg)
    remaining_budget = max(cfg.daily_loss_limit_usd + min(daily_pnl_so_far, 0.0), 0.0)
    effective_budget = min(remaining_budget, max_risk_usd)
    
    base_risk = effective_budget * cfg.risk_frac[regime]
    conf_scale = 0.5 + 0.5 * min(max(signal_confidence, 0.15), 1.0)
    risk_usd = base_risk * conf_scale

    stop_points = current_atr * cfg.atr_stop_multiplier
    dollar_risk_per_lot = stop_points * cfg.point_value_per_lot

    if dollar_risk_per_lot < 1.0:   
        raw_lots = cfg.min_lots
    else:
        raw_lots = risk_usd / dollar_risk_per_lot

    target_lots_at_baseline = 0.5  
    K = target_lots_at_baseline * cfg.atr_baseline
    hyperbolic_cap = K / (current_atr + 1e-8)

    denominator = current_atr * cfg.atr_stop_multiplier * cfg.point_value_per_lot
    atr_max_lots = cfg.min_lots
    if denominator > 0:
        raw_max = cfg.internal_gate_usd / denominator
        atr_max_lots = max(_round_to_step(math.floor(raw_max / cfg.lot_step) * cfg.lot_step, cfg.lot_step), cfg.min_lots)

    lots_unclamped = min(raw_lots, hyperbolic_cap)
    lots_clamped = max(cfg.min_lots, min(lots_unclamped, atr_max_lots))
    lots_final   = max(_round_to_step(lots_clamped, cfg.lot_step), cfg.min_lots)

    diagnostics = {
        "regime":              regime.value,
        "atr":                 round(current_atr, 2),
        "atr_ratio":           round(current_atr / cfg.atr_baseline, 2),
        "stop_points":         round(stop_points, 2),
        "lots_final":          lots_final,
        "dollar_exposure":     round(lots_final * current_atr * cfg.point_value_per_lot, 2),
    }

    return lots_final, regime, diagnostics

class ATRTracker:
    def __init__(self, period: int = 14):
        self.period  = period
        self.highs:  deque = deque(maxlen=period + 1)
        self.lows:   deque = deque(maxlen=period + 1)
        self.closes: deque = deque(maxlen=period + 1)
        self._trs:   deque = deque(maxlen=period)

    def push_bar(self, high: float, low: float, close: float) -> Optional[float]:
        self.highs.append(high)
        self.lows.append(low)
        self.closes.append(close)

        if len(self.closes) < 2: return None

        prev_close = self.closes[-2]
        tr = max(
            high - low,
            abs(high - prev_close),
            abs(low  - prev_close),
        )
        self._trs.append(tr)

        if len(self._trs) < self.period: return None
        return sum(self._trs) / len(self._trs)
# kelly sizer

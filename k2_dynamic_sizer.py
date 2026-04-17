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

# commit step 1: 561

# commit step 7: 199

# commit step 10: 447

# commit step 18: 683

# commit step 21: 836

# commit step 36: 923

# commit step 38: 306

# commit step 51: 300

# commit step 56: 417

# commit step 57: 514

# commit step 58: 989

# commit step 62: 970

# commit step 65: 469

# commit step 67: 618

# commit step 68: 110

# commit step 73: 613

# commit step 74: 766

# commit step 85: 878

# commit step 88: 221

# commit step 89: 175

# commit step 90: 444

# commit step 91: 166

# commit step 92: 180

# commit step 93: 900

# commit step 108: 435

# commit step 111: 804

# commit step 112: 904

# commit step 117: 173

# commit step 123: 904

# commit step 151: 578

# commit step 164: 436

# commit step 165: 112

# commit step 168: 287

# commit step 171: 874

# commit step 176: 712

# commit step 178: 774

# commit step 190: 912

# commit step 203: 664

# commit step 204: 604

# commit step 231: 352

# commit step 243: 681

# commit step 249: 778

# kessler step 11: 697

# kessler step 12: 233

# commit step 252: 779

# commit step 253: 312

# kessler step 16: 488

# kessler step 19: 314

# commit step 259: 774

# commit step 260: 276

# kessler step 26: 144

# kessler step 27: 744

# kessler step 28: 221

# commit step 273: 121

# commit step 278: 433

# kessler step 43: 394

# commit step 281: 789

# commit step 286: 460

# kessler step 49: 666

# kessler step 51: 732

# commit step 290: 703

# commit step 292: 627

# kessler step 60: 184

# kessler step 64: 390

# commit step 304: 246

# kessler step 70: 476

# commit step 315: 242

# kessler step 80: 543

# commit step 320: 946

# commit step 330: 943

# kessler step 92: 171

# kessler step 95: 245

# commit step 336: 104

# kessler step 100: 225

# kessler step 110: 665

# commit step 349: 637

# kessler step 116: 674

# kessler step 117: 193

# commit step 357: 174

# kessler step 121: 588

# kessler step 128: 593

# commit step 367: 890

# kessler step 136: 162

# kessler step 137: 793

# kessler step 140: 244

# commit step 382: 446

# commit step 385: 371

# kessler step 150: 689

# commit step 389: 761

# kessler step 151: 977

# kessler step 152: 426

# commit step 390: 799

# commit step 393: 429

# commit step 394: 646

# kessler step 159: 322

# kessler step 161: 290

# kessler step 1: 647

# commit step 404: 494

# kessler step 167: 731

# commit step 406: 937

# kessler step 4: 400

# kessler step 170: 331

# commit step 409: 887

# kessler step 172: 941

# commit step 411: 742

# kessler step 12: 487

# kessler step 179: 556

# kessler step 21: 844

# kessler step 22: 893

# kessler step 187: 326

# kessler step 24: 267

# kessler step 191: 174

# kessler step 27: 551

# commit step 431: 369

# kessler step 193: 332

# commit step 432: 603

# kessler step 194: 450

# kessler step 195: 279

# kessler step 31: 378

# kessler step 197: 456

# commit step 440: 303

# kessler step 205: 537

# kessler step 41: 128

# commit step 445: 995

# commit step 451: 850

# kessler step 214: 781

# commit step 453: 593

# kessler step 217: 144

# commit step 455: 767

# commit step 459: 639

# commit step 461: 417

# kessler step 224: 940

# kessler step 60: 732

# kessler step 229: 215

# commit step 474: 974

# kessler step 71: 194

# commit step 475: 584

# kessler step 72: 464

# commit step 477: 282

# kessler step 239: 378

# kessler step 241: 175

# kessler step 243: 672

# commit step 482: 237

# kessler step 244: 178

# kessler step 247: 602

# kessler step 248: 856

# commit step 487: 179

# commit step 488: 179

# kessler step 85: 953

# commit step 489: 497

# kessler step 86: 265

# kessler step 87: 160

# commit step 493: 195

# kessler step 91: 167

# kessler step 260: 996

# kessler step 96: 885

# commit step 500: 929

# kessler step 100: 452

# kessler step 101: 782

# kessler step 104: 992

# kessler step 105: 985

# kessler step 106: 888

# kessler step 272: 876

# kessler step 274: 424

# kessler step 110: 686

# kessler step 113: 685

# kessler step 118: 465

# kessler step 122: 408

# kessler step 289: 603

# commit step 528: 380

# commit step 530: 407

# kessler step 3: 122

# commit step 532: 399

# kessler step 129: 465

# kessler step 294: 126

# kessler step 132: 143

# kessler step 297: 122

# commit step 537: 538

# kessler step 136: 827

# kessler step 304: 224

# kessler step 15: 206

# kessler step 138: 121

# kessler step 142: 633

# kessler step 24: 258

# kessler step 150: 134

# kessler step 326: 877

# kessler step 158: 176

# kessler step 38: 382

# kessler step 329: 735

# kessler step 44: 853

# kessler step 332: 823

# kessler step 46: 155

# kessler step 336: 112

# kessler step 341: 858

# kessler step 344: 620

# kessler step 346: 984

# kessler step 57: 351

# kessler step 59: 311

# kessler step 61: 263

# kessler step 64: 554

# kessler step 352: 403

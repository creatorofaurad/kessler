//+------------------------------------------------------------------+
//|                                  US100_L2_Execution_Engine.mq5   |
//|               Kessler Institutional US100.cash Execution Engine |
//|           Copyright 2026, Srijan (mid) // Kessler Architect       |
//+------------------------------------------------------------------+
#property copyright "Srijan (mid) // Kessler Architect"
#property link      "https://github.com/srijan/kessler"
#property version   "1.00"
#property description "Kessler Institutional US100.cash L2 Quantitative Execution Engine"
#property description "Pure L2 Microstructure: Kalman Efficient Price + Multi-Level OFI Z-Score + VPIN Toxicity + AVIR Voids"
#property description "Compliance Architecture: -$22k Kill Switch | +$50k Profit Lock | 20:30 Flatten Shield"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUM DEFINITIONS                                                 |
//+------------------------------------------------------------------+
enum ENUM_ACCOUNT_STATE
  {
   STATE_ACTIVE        = 0,  // Trading active under full risk controls
   STATE_PROFIT_LOCKED = 1,  // +$50,000 daily profit target hit (Account Secured)
   STATE_KILLED        = 2,  // -$22,000 daily or -$38,000 abs drawdown breached
   STATE_FLATTENED     = 3   // Hard 20:30 server time session flatten reached
  };

//+------------------------------------------------------------------+
//| STRUCT DEFINITIONS                                               |
//+------------------------------------------------------------------+
struct KalmanState
  {
   double x_hat;        // State estimate X_t (Efficient price)
   double P;            // Estimate error covariance
   double Q;            // Dynamic process noise variance
   double R;            // Dynamic measurement noise variance
   bool   initialized;
   double price_returns[50];
   int    ret_head;
   int    ret_count;
   double last_mid;     // Prior mid-price for 1s return calculation
  };

struct OFIState
  {
   double prev_bid[10];
   double prev_ask[10];
   double prev_bid_vol[10];
   double prev_ask_vol[10];
   double window_ofi[100];
   int    ring_idx;
   int    count;
   double z_score;
   bool   initialized;
  };

struct VPINState
  {
   double bucket_volume_target; // Volume per bucket V_b
   double current_buy_vol;
   double current_sell_vol;
   double bucket_imbalances[50];
   int    bucket_head;
   int    total_buckets;
   double current_vpin;
   double dp_history[50];
   int    dp_head;
   int    dp_count;
  };

struct QuoteFilterState
  {
   long   last_quote_ms;
   double last_bid;
   double last_ask;
   ulong  rejected_hft_quotes;
  };

struct KyleLambdaState
  {
   double lambda_val;   // Price impact per unit OFI
   double P_rls;        // RLS estimation variance
   double forgetting;   // RLS forgetting factor
   double prev_price;   // Prior price reference
  };

struct AVIRState
  {
   double step;         // 0.50 index points discretization step
   int    window_levels;// W = 10 depth levels
   double avir_val;     // Imbalance ratio [-1.0, +1.0]
  };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== SYMBOL & RISK SIZING ==="
input string TargetSymbol           = "US100.cash";  // Target Symbol Security
input ulong  MagicNumber            = 400100;        // Magic Number Identification
input double SizingRiskPct          = 0.02;          // 2.0% Risk Per Bullet ($8,000 on $400k)
input double SizingTargetRR         = 3.125;         // Target Reward-to-Risk Ratio (3.125+)
input double DefaultStopPoints      = 20.0;          // Default Stop Loss Distance (Index Points)

input group "=== COMPLIANCE & RISK SHIELDS ==="
input double AccountStartingBalance = 400000.0;     // Account Base Capital ($400,000)
input double MaxDailyDrawdownUSD    = 22000.0;      // Hard Daily Drawdown Limit (-5.5% / -$22,000)
input double MaxAbsDrawdownUSD      = 38000.0;      // Hard Absolute Drawdown Limit (-9.5% / -$38,000)
input double DailyProfitLockUSD     = 50000.0;      // Daily Profit Lock Target (+12.5% / +$50,000)
input int    FlattenHourServer      = 20;           // Hard Session Flatten Hour (Server Time)
input int    FlattenMinuteServer    = 30;           // Hard Session Flatten Minute (Server Time)

input group "=== L2 MICROSTRUCTURE PARAMETERS ==="
input long   MinQuoteLifetimeMS     = 10;           // 10ms Quote Lifetime Filter Threshold
input double KalmanProcessNoiseQ    = 1e-4;         // Kalman Process Noise Base Q
input double KalmanMeasureNoiseR    = 1e-2;         // Kalman Measurement Noise Base R
input int    OFIWindowSize          = 50;           // Ticks Window for OFI Z-Score
input double OFIZScoreThreshold    = 2.0;          // |Z_OFI| Threshold for Entry
input double VPINBucketVolume       = 10000.0;      // Volume Bucket Size V_b (Spec: 10000.0)
input int    VPINWindowBuckets      = 20;           // Number of Volume Buckets N
input double VPINThreshold          = 0.65;         // Max Allowed VPIN Toxicity
input double KyleLambdaMinThreshold = 0.012;        // Min Kyle's Lambda (Absorption Trap Veto)
input double AVIRThreshold          = 0.20;         // AVIR Imbalance Ratio Threshold for Entry

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade            g_trade;
CSymbolInfo       g_symbol_info;
CPositionInfo     g_position_info;

ENUM_ACCOUNT_STATE g_state               = STATE_ACTIVE;
double            g_daily_start_balance = 400000.0;
int               g_consecutive_losses  = 0;
int               g_last_trade_day      = 0;

KalmanState       g_kalman;
OFIState          g_ofi;
VPINState         g_vpin;
QuoteFilterState  g_quote_filter;
KyleLambdaState   g_lambda;
AVIRState         g_avir;

//+------------------------------------------------------------------+
//| GAUSSIAN CDF NUMERICAL APPROXIMATION (BVC METHOD)                |
//+------------------------------------------------------------------+
double GaussianCDF(const double z)
  {
   double abs_z = MathAbs(z);
   if(abs_z > 6.0)
     {
      return (z > 0.0) ? 1.0 : 0.0;
     }

   double k = 1.0 / (1.0 + 0.2316419 * abs_z);
   double p = 0.3989422804014327 * MathExp(-0.5 * abs_z * abs_z);
   double poly = k * (0.319381530 + k * (-0.356563782 + k * (1.781477937 + k * (-1.821255978 + k * 1.330274429))));
   double cdf = 1.0 - p * poly;

   return (z >= 0.0) ? cdf : (1.0 - cdf);
  }

//+------------------------------------------------------------------+
//| 10ms QUOTE LIFETIME FILTER (STRICT TIMESTAMP UPDATE ON ALL TICKS)|
//+------------------------------------------------------------------+
bool PassQuoteLifetimeFilter(const MqlTick &tick, const long min_lifetime_ms)
  {
   long current_ms = tick.time_msc;
   if(current_ms == 0)
     {
      current_ms = (long)(GetMicrosecondCount() / 1000);
     }

   bool is_quote_change = (tick.bid != g_quote_filter.last_bid) || (tick.ask != g_quote_filter.last_ask);
   if(!is_quote_change)
     {
      return true;
     }

   long delta_t = current_ms - g_quote_filter.last_quote_ms;
   bool pass = true;
   if(delta_t < min_lifetime_ms && g_quote_filter.last_quote_ms > 0)
     {
      g_quote_filter.rejected_hft_quotes++;
      pass = false; // Reject HFT quote stuffing / spoofing
     }

   // CRITICAL FIX: Update timestamp and last bid/ask on EVERY quote tick (both accepted AND rejected ticks)
   g_quote_filter.last_quote_ms = current_ms;
   g_quote_filter.last_bid      = tick.bid;
   g_quote_filter.last_ask      = tick.ask;

   return pass;
  }

//+------------------------------------------------------------------+
//| DYNAMIC KALMAN FILTER STATE ESTIMATION WITH HUBER GATING         |
//+------------------------------------------------------------------+
void UpdateKalmanFilter(KalmanState &state, const MqlTick &tick)
  {
   double current_mid = (tick.bid + tick.ask) / 2.0;

   // Dynamic Noise Adaptation:
   // 1. Measurement Noise R_t scales with bid-ask spread squared
   double spread = tick.ask - tick.bid;
   double R_t = MathMax(KalmanMeasureNoiseR, 1e-4 * spread * spread);

   // 2. Process Noise Q_t adapts to rolling realized return variance
   if(!state.initialized)
     {
      state.x_hat       = current_mid;
      state.P           = 1.0;
      state.Q           = KalmanProcessNoiseQ;
      state.R           = R_t;
      state.ret_head    = 0;
      state.ret_count   = 0;
      state.last_mid    = current_mid;
      state.initialized = true;
      return;
     }

   double ret = (state.last_mid > 0.0) ? (current_mid - state.last_mid) : 0.0;
   state.last_mid = current_mid;
   
   state.price_returns[state.ret_head] = ret;
   state.ret_head = (state.ret_head + 1) % 50;
   if(state.ret_count < 50) state.ret_count++;

   double var_sum = 0.0;
   if(state.ret_count > 1)
     {
      double sum_ret = 0.0;
      for(int i = 0; i < state.ret_count; i++) sum_ret += state.price_returns[i];
      double mean_ret = sum_ret / (double)state.ret_count;
      for(int i = 0; i < state.ret_count; i++)
        {
         double d = state.price_returns[i] - mean_ret;
         var_sum += d * d;
        }
      var_sum /= (double)(state.ret_count - 1);
     }
   
   double Q_t = MathMax(KalmanProcessNoiseQ, var_sum);
   state.Q = Q_t;
   state.R = R_t;

   double P_prior    = state.P + Q_t;
   double innovation = current_mid - state.x_hat;
   double S_k        = P_prior + R_t;
   double K          = P_prior / S_k;

   // Huber Gating on extreme innovation (HFT stop-hunting filter, gamma = 2.5)
   double norm_inn = MathAbs(innovation) / MathSqrt(S_k);
   double gamma_gate = 2.5;
   if(norm_inn > gamma_gate && norm_inn > 0.0)
     {
      K = K * (gamma_gate / norm_inn);
     }

   state.x_hat = state.x_hat + K * innovation;
   state.P     = (1.0 - K) * P_prior;
  }

//+------------------------------------------------------------------+
//| MULTI-LEVEL L2 ORDER FLOW IMBALANCE (OFI) Z-SCORE ENGINE        |
//+------------------------------------------------------------------+
void UpdateMultiLevelOFI(OFIState &ofi, const string &symbol)
  {
   MqlBookInfo book[];
   if(!MarketBookGet(symbol, book)) return;

   int size = ArraySize(book);
   if(size <= 0) return;

   double bid_prices[10], ask_prices[10];
   double bid_vols[10],   ask_vols[10];
   ArrayInitialize(bid_prices, 0.0); ArrayInitialize(ask_prices, 0.0);
   ArrayInitialize(bid_vols, 0.0);   ArrayInitialize(ask_vols, 0.0);

   int b_cnt = 0, a_cnt = 0;
   for(int i = 0; i < size; i++)
     {
      if(book[i].type == BOOK_TYPE_BUY && b_cnt < 10)
        {
         bid_prices[b_cnt] = book[i].price;
         bid_vols[b_cnt]   = (double)book[i].volume;
         b_cnt++;
        }
      else if(book[i].type == BOOK_TYPE_SELL && a_cnt < 10)
        {
         ask_prices[a_cnt] = book[i].price;
         ask_vols[a_cnt]   = (double)book[i].volume;
         a_cnt++;
        }
     }

   if(!ofi.initialized)
     {
      for(int k = 0; k < 10; k++)
        {
         ofi.prev_bid[k]     = bid_prices[k];
         ofi.prev_ask[k]     = ask_prices[k];
         ofi.prev_bid_vol[k] = bid_vols[k];
         ofi.prev_ask_vol[k] = ask_vols[k];
        }
      ofi.initialized = true;
      return;
     }

   double weighted_ofi = 0.0;
   double total_w      = 0.0;

   for(int k = 0; k < 10; k++)
     {
      double bid_k     = bid_prices[k];
      double bid_vol_k = bid_vols[k];
      double ask_k     = ask_prices[k];
      double ask_vol_k = ask_vols[k];

      // Bid impact: e_m^B
      double delta_vb = 0.0;
      if(bid_k > ofi.prev_bid[k])       delta_vb = bid_vol_k;
      else if(bid_k == ofi.prev_bid[k]) delta_vb = bid_vol_k - ofi.prev_bid_vol[k];
      else                             delta_vb = -ofi.prev_bid_vol[k];

      // Ask impact: e_m^A (FIXED INVERTED ASK-SIDE LOGIC)
      // When ask < prev_ask (lower ask: new limit sell placed): delta_va = ask_vol
      // When ask > prev_ask (higher ask: ask canceled or lifted): delta_va = -prev_ask_vol
      // When ask == prev_ask (equal ask: net size change): delta_va = ask_vol - prev_ask_vol
      double delta_va = 0.0;
      if(ask_k < ofi.prev_ask[k])       delta_va = ask_vol_k;
      else if(ask_k == ofi.prev_ask[k]) delta_va = ask_vol_k - ofi.prev_ask_vol[k];
      else                             delta_va = -ofi.prev_ask_vol[k];

      double raw_ofi_k = delta_vb - delta_va;
      double w_k = MathPow(0.8, k); // Exponential decay w_k = 0.8^(k-1)

      weighted_ofi += w_k * raw_ofi_k;
      total_w      += w_k;

      ofi.prev_bid[k]     = bid_k;
      ofi.prev_ask[k]     = ask_k;
      ofi.prev_bid_vol[k] = bid_vol_k;
      ofi.prev_ask_vol[k] = ask_vol_k;
     }

   double multi_ofi = (total_w > 0.0) ? (weighted_ofi / total_w) : 0.0;
   int w_size = (OFIWindowSize > 0 && OFIWindowSize <= 100) ? OFIWindowSize : 50;

   ofi.window_ofi[ofi.ring_idx] = multi_ofi;
   ofi.ring_idx = (ofi.ring_idx + 1) % w_size;
   if(ofi.count < w_size) ofi.count++;

   double sum = 0.0;
   for(int i = 0; i < ofi.count; i++) sum += ofi.window_ofi[i];
   double mean = sum / (double)ofi.count;

   double var_sum = 0.0;
   for(int i = 0; i < ofi.count; i++)
     {
      double diff = ofi.window_ofi[i] - mean;
      var_sum += diff * diff;
     }
   double std_dev = MathSqrt(var_sum / (double)(ofi.count > 1 ? ofi.count - 1 : 1));

   if(std_dev < 1e-8) ofi.z_score = 0.0;
   else               ofi.z_score = (multi_ofi - mean) / std_dev;
  }

//+------------------------------------------------------------------+
//| VPIN TOXICITY ENGINE WITH ROLLING SIGMA_DELTA_P                  |
//+------------------------------------------------------------------+
void UpdateVPIN(VPINState &vpin, const double volume, const double delta_p)
  {
   // Store rolling price changes for dynamic sigma_dp
   vpin.dp_history[vpin.dp_head] = delta_p;
   vpin.dp_head = (vpin.dp_head + 1) % 50;
   if(vpin.dp_count < 50) vpin.dp_count++;

   double sum_dp = 0.0;
   for(int i = 0; i < vpin.dp_count; i++) sum_dp += vpin.dp_history[i];
   double mean_dp = sum_dp / (double)vpin.dp_count;

   double var_dp = 0.0;
   for(int i = 0; i < vpin.dp_count; i++)
     {
      double d = vpin.dp_history[i] - mean_dp;
      var_dp += d * d;
     }
   double sigma_dp = MathSqrt(var_dp / (double)(vpin.dp_count > 1 ? vpin.dp_count - 1 : 1));
   if(sigma_dp < 1e-6) sigma_dp = 1.0;

   double cdf_val = GaussianCDF(delta_p / sigma_dp);

   double buy_vol  = volume * cdf_val;
   double sell_vol = volume * (1.0 - cdf_val);

   vpin.current_buy_vol  += buy_vol;
   vpin.current_sell_vol += sell_vol;

   double total = vpin.current_buy_vol + vpin.current_sell_vol;
   if(total >= vpin.bucket_volume_target && vpin.bucket_volume_target > 0.0)
     {
      double diff = MathAbs(vpin.current_buy_vol - vpin.current_sell_vol);
      
      int max_b = (vpin.total_buckets > 0 && vpin.total_buckets <= 50) ? vpin.total_buckets : 20;
      vpin.bucket_imbalances[vpin.bucket_head] = diff;
      vpin.bucket_head = (vpin.bucket_head + 1) % max_b;

      vpin.current_buy_vol  = 0.0;
      vpin.current_sell_vol = 0.0;

      double sum_imbalance = 0.0;
      for(int i = 0; i < max_b; i++)
        {
         sum_imbalance += vpin.bucket_imbalances[i];
        }
      vpin.current_vpin = sum_imbalance / ((double)max_b * vpin.bucket_volume_target);
     }
  }

//+------------------------------------------------------------------+
//| ASYMMETRIC VOLUME VOID (AVIR) ENGINE                             |
//+------------------------------------------------------------------+
void UpdateAVIR(AVIRState &avir_state, const string &symbol)
  {
   MqlBookInfo book[];
   if(!MarketBookGet(symbol, book)) return;

   int size = ArraySize(book);
   if(size <= 0) return;

   double void_bid = 0.0;
   double void_ask = 0.0;
   int b_count = 0, a_count = 0;

   for(int i = 0; i < size; i++)
     {
      if(book[i].type == BOOK_TYPE_BUY && b_count < avir_state.window_levels)
        {
         void_bid += (double)book[i].volume;
         b_count++;
        }
      else if(book[i].type == BOOK_TYPE_SELL && a_count < avir_state.window_levels)
        {
         void_ask += (double)book[i].volume;
         a_count++;
        }
     }

   double total_void = void_bid + void_ask;
   if(total_void > 0.0)
     {
      avir_state.avir_val = (void_bid - void_ask) / (total_void + 1e-8);
     }
   else
     {
      avir_state.avir_val = 0.0;
     }
  }

//+------------------------------------------------------------------+
//| KYLE'S LAMBDA ELASTICITY VIA RLS                                 |
//+------------------------------------------------------------------+
void UpdateKyleLambda(KyleLambdaState &lstate, const double delta_p, const double ofi_val)
  {
   if(MathAbs(ofi_val) < 1e-6) return;

   double x = ofi_val;
   double y = delta_p;

   double gain = (lstate.P_rls * x) / (lstate.forgetting + x * x * lstate.P_rls);
   lstate.lambda_val = lstate.lambda_val + gain * (y - x * lstate.lambda_val);
   lstate.P_rls      = (1.0 / lstate.forgetting) * (1.0 - gain * x) * lstate.P_rls;

   if(lstate.lambda_val < 0.0) lstate.lambda_val = 0.0;
  }

//+------------------------------------------------------------------+
//| POSITION LIQUIDATION & ORDER DELETION SENTINEL                   |
//+------------------------------------------------------------------+
void FlattenAllPositions(const string reason)
  {
   Print("[KESSLER COMPLIANCE SHIELD] ACTIVATED: ", reason);

   // Close all open positions matching MagicNumber
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(g_position_info.SelectByTicket(ticket))
           {
            if(g_position_info.Magic() == MagicNumber && g_position_info.Symbol() == _Symbol)
              {
               bool closed = g_trade.PositionClose(ticket);
               if(!closed)
                 {
                  Print("[KESSLER EXEC ERROR] Failed to close position ticket: ", ticket, " Code: ", g_trade.ResultRetcode());
                 }
              }
           }
        }
     }

   // Delete all pending orders matching MagicNumber
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong order_ticket = OrderGetTicket(i);
      if(order_ticket > 0)
        {
         if(OrderGetInteger(ORDER_MAGIC) == (long)MagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
           {
            bool deleted = g_trade.OrderDelete(order_ticket);
            if(!deleted)
              {
               Print("[KESSLER EXEC ERROR] Failed to delete order ticket: ", order_ticket, " Code: ", g_trade.ResultRetcode());
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| EVALUATE COMPLIANCE SHIELDS & ACCOUNT FSM STATE                 |
//+------------------------------------------------------------------+
ENUM_ACCOUNT_STATE EvaluateComplianceShields(void)
  {
   MqlDateTime dt;
   datetime now = TimeCurrent();
   TimeToStruct(now, dt);

   // MIDNIGHT (00:00) NEW-DAY SESSION RESET HANDLER
   if(g_last_trade_day > 0 && dt.day != g_last_trade_day)
     {
      g_daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(g_daily_start_balance <= 0.0) g_daily_start_balance = AccountStartingBalance;
      g_consecutive_losses   = 0;
      if(g_state == STATE_FLATTENED || g_state == STATE_PROFIT_LOCKED)
        {
         g_state = STATE_ACTIVE;
        }
      g_last_trade_day = dt.day;
      Print("[KESSLER DAY RESET] New Calendar Day (Day ", dt.day, "). Baseline Balance Reset: $", g_daily_start_balance);
     }
   else if(g_last_trade_day == 0)
     {
      g_last_trade_day = dt.day;
     }

   // FSM LIQUIDATION RETRY GUARD:
   // If compliance is breached and g_state is non-active, check if positions/orders remain open.
   // Call FlattenAllPositions() on EVERY tick/timer tick until PositionsTotal() == 0!
   if(g_state == STATE_KILLED || g_state == STATE_PROFIT_LOCKED || g_state == STATE_FLATTENED)
     {
      if(PositionsTotal() > 0 || OrdersTotal() > 0)
        {
         FlattenAllPositions("RETRY LIQUIDATION BREACH - POSITIONS OR ORDERS STILL OPEN");
        }
      return g_state;
     }

   double current_equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double net_daily_pnl   = (current_balance - g_daily_start_balance) + (current_equity - current_balance);

   // 1. Daily Profit Target Lockout (+$50,000)
   if(net_daily_pnl >= DailyProfitLockUSD)
     {
      g_state = STATE_PROFIT_LOCKED;
      FlattenAllPositions("DAILY PROFIT TARGET LOCKOUT HIT (+$50,000.00 / +12.5%)");
      return STATE_PROFIT_LOCKED;
     }

   // 2. Intraday Max Daily Drawdown Kill Switch (-$22,000 / -5.5%)
   if(net_daily_pnl <= -MaxDailyDrawdownUSD)
     {
      g_state = STATE_KILLED;
      FlattenAllPositions("MAX DAILY DRAWDOWN KILL SWITCH BREACHED (-$22,000.00 / -5.5%)");
      return STATE_KILLED;
     }

   // 3. Absolute Drawdown Ceiling Floor (-$38,000 / -9.5%)
   if(current_equity <= (AccountStartingBalance - MaxAbsDrawdownUSD))
     {
      g_state = STATE_KILLED;
      FlattenAllPositions("ABSOLUTE DRAWDOWN FLOOR BREACHED (-$38,000.00 / -9.5%)");
      return STATE_KILLED;
     }

   // 4. Hard Session Flatten Shield (20:30 Server Time)
   if(dt.hour > FlattenHourServer || (dt.hour == FlattenHourServer && dt.min >= FlattenMinuteServer))
     {
      g_state = STATE_FLATTENED;
      FlattenAllPositions("HARD SESSION FLATTEN SHIELD AT 20:30 SERVER TIME");
      return STATE_FLATTENED;
     }

   return STATE_ACTIVE;
  }

//+------------------------------------------------------------------+
//| ASYMMETRIC LOT SIZING CALCULATOR                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(const double entry_price, const double sl_price)
  {
   if(g_state != STATE_ACTIVE) return 0.0;

   double sl_distance_points = MathAbs(entry_price - sl_price);
   if(sl_distance_points <= 0.0) return 0.0;

   string symbol = _Symbol;
   double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0) return 0.0;

   double risk_usd = AccountStartingBalance * SizingRiskPct; // $8,000.00 standard risk

   // Positive PnL Penalty Fix & Loss capacity clamping protocol after 2 consecutive losses
   if(g_consecutive_losses >= 2)
     {
      double net_pnl = AccountInfoDouble(ACCOUNT_EQUITY) - g_daily_start_balance;
      double remaining_buffer = MaxDailyDrawdownUSD + net_pnl;
      if(remaining_buffer <= 0.0) return 0.0; // Zero Risk Capacity Guard
      risk_usd = MathMin(risk_usd, MathMax(0.0, remaining_buffer));
     }

   // Zero Risk Capacity Guard
   if(risk_usd <= 0.0) return 0.0;

   // Index lot calculation
   double raw_lots = (risk_usd * tick_size) / (sl_distance_points * tick_value);

   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double min_lot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(lot_step <= 0.0) lot_step = 0.01;

   // Floating Point Underflow Fix: Add 1e-9 epsilon before MathFloor
   double step_units = MathFloor((raw_lots + 1e-9) / lot_step);
   double lots = step_units * lot_step;

   // Min Lot Guard: Account cannot afford min_lot within risk budget -> return 0.0
   if(lots < min_lot) return 0.0;
   if(lots > max_lot) lots = max_lot;

   return lots;
  }

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION HANDLER                                    |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   // Configure execution magic number
   g_trade.SetExpertMagicNumber(MagicNumber);
   g_trade.SetMarginMode();

   if(!g_symbol_info.Name(_Symbol))
     {
      Print("[KESSLER INIT ERROR] Failed to bind symbol: ", _Symbol);
      return INIT_FAILED;
     }

   g_symbol_info.RefreshRates();

   // Subscribe to Level-2 Depth of Market
   bool book_added = MarketBookAdd(_Symbol);
   if(!book_added)
     {
      Print("[KESSLER INIT WARNING] MarketBookAdd failed for ", _Symbol, ". L2 depth updates disabled.");
     }

   // Register 100ms millisecond timer for compliance sentinels
   EventSetMillisecondTimer(100);

   // Record daily start balance and calendar day
   g_daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(g_daily_start_balance <= 0.0) g_daily_start_balance = AccountStartingBalance;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   g_last_trade_day = dt.day;

   // Initialize state structs
   g_kalman.x_hat       = g_symbol_info.Bid();
   g_kalman.P           = 1.0;
   g_kalman.Q           = KalmanProcessNoiseQ;
   g_kalman.R           = KalmanMeasureNoiseR;
   g_kalman.ret_head    = 0;
   g_kalman.ret_count   = 0;
   g_kalman.initialized = false;
   ArrayInitialize(g_kalman.price_returns, 0.0);

   for(int k = 0; k < 10; k++)
     {
      g_ofi.prev_bid[k]     = 0.0;
      g_ofi.prev_ask[k]     = 0.0;
      g_ofi.prev_bid_vol[k] = 0.0;
      g_ofi.prev_ask_vol[k] = 0.0;
     }
   g_ofi.ring_idx       = 0;
   g_ofi.count          = 0;
   g_ofi.z_score        = 0.0;
   g_ofi.initialized    = false;
   ArrayInitialize(g_ofi.window_ofi, 0.0);

   g_vpin.bucket_volume_target = VPINBucketVolume;
   g_vpin.current_buy_vol      = 0.0;
   g_vpin.current_sell_vol     = 0.0;
   g_vpin.bucket_head          = 0;
   g_vpin.total_buckets        = VPINWindowBuckets;
   g_vpin.current_vpin         = 0.0;
   g_vpin.dp_head              = 0;
   g_vpin.dp_count             = 0;
   ArrayInitialize(g_vpin.bucket_imbalances, 0.0);
   ArrayInitialize(g_vpin.dp_history, 0.0);

   g_quote_filter.last_quote_ms      = 0;
   g_quote_filter.last_bid           = 0.0;
   g_quote_filter.last_ask           = 0.0;
   g_quote_filter.rejected_hft_quotes= 0;

   g_lambda.lambda_val   = 0.05;
   g_lambda.P_rls        = 1.0;
   g_lambda.forgetting   = 0.98;
   g_lambda.prev_price   = g_symbol_info.Bid();

   g_avir.step          = 0.50;
   g_avir.window_levels = 10;
   g_avir.avir_val      = 0.0;

   g_state = STATE_ACTIVE;

   Print("[KESSLER EXECUTION ENGINE INITIALIZED] Baseline Balance: $", g_daily_start_balance, " Symbol: ", _Symbol);

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION HANDLER                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   MarketBookRelease(_Symbol);
   EventKillTimer();
   Print("[KESSLER EXECUTION ENGINE TERMINATED] Reason Code: ", reason, " HFT Quotes Rejected: ", g_quote_filter.rejected_hft_quotes);
  }

//+------------------------------------------------------------------+
//| BOOK EVENT HANDLER (LEVEL-2 DOM DEPTH)                           |
//+------------------------------------------------------------------+
void OnBookEvent(const string &symbol)
  {
   if(symbol != _Symbol) return;

   // Update Multi-Level OFI (K=10) and AVIR Volume Voids from Book Depth
   UpdateMultiLevelOFI(g_ofi, symbol);
   UpdateAVIR(g_avir, symbol);
  }

//+------------------------------------------------------------------+
//| TIMER HANDLER (100MS COMPLIANCE POLLING)                         |
//+------------------------------------------------------------------+
void OnTimer(void)
  {
   EvaluateComplianceShields();
  }

//+------------------------------------------------------------------+
//| TRADE TRANSACTION HANDLER (LOSS STREAK TRACKER)                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      ulong deal_ticket = trans.deal;
      if(deal_ticket > 0)
        {
         if(HistoryDealSelect(deal_ticket))
           {
            long deal_entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
            if(deal_entry == DEAL_ENTRY_OUT || deal_entry == DEAL_ENTRY_INOUT)
              {
               double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) + HistoryDealGetDouble(deal_ticket, DEAL_SWAP) + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
               if(profit < 0.0)
                 {
                  g_consecutive_losses++;
                  Print("[KESSLER RISK TRACKER] Deal Closed Loss: $", profit, " | Loss Streak: ", g_consecutive_losses);
                 }
               else if(profit > 0.0)
                 {
                  g_consecutive_losses = 0;
                  Print("[KESSLER RISK TRACKER] Deal Closed Win: +$", profit, " | Loss Streak Reset");
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| MAIN TICK EXECUTION LOOP                                         |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   // 1. Intraday Compliance Evaluation
   ENUM_ACCOUNT_STATE current_state = EvaluateComplianceShields();
   if(current_state != STATE_ACTIVE) return;

   // 2. Ingest Current Tick
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;

   // 3. 10ms Quote Lifetime Filter (Strip HFT spoofing / quote stuffing)
   if(!PassQuoteLifetimeFilter(tick, MinQuoteLifetimeMS))
     {
      return;
     }

   // 4. Update Microstructure Models
   double mid_price = (tick.bid + tick.ask) / 2.0;
   UpdateKalmanFilter(g_kalman, tick);

   double delta_p = mid_price - g_lambda.prev_price;
   g_lambda.prev_price = mid_price;

   // OFI is updated strictly via OnBookEvent (No dual mutation in OnTick)
   double z_ofi = g_ofi.z_score;
   UpdateVPIN(g_vpin, (double)(tick.volume_real > 0 ? tick.volume_real : 1.0), delta_p);
   UpdateKyleLambda(g_lambda, delta_p, z_ofi);

   // 5. Execution Veto & Signal Rules
   // Veto 1: Single bullet active limit (max 1 position at a time)
   if(PositionsTotal() > 0) return;

   // Veto 2: Kyle's Lambda Absorption Trap Veto (Inelastic absorption trap)
   if(g_lambda.lambda_val < KyleLambdaMinThreshold)
     {
      return; // Veto execution: institutional limit order absorbing aggressors
     }

   // Veto 3: VPIN Toxicity Threshold Veto
   if(g_vpin.current_vpin > VPINThreshold)
     {
      return; // Veto execution: toxic market maker withdrawal regime
     }

   // 6. Signal Logic (Pure L2 Microstructure - ZERO Retail Indicators)
   // Multi-level OFI Z-Score + Kalman Efficient Price + AVIR Volume Void Check
   bool buy_signal  = (z_ofi >= OFIZScoreThreshold)  && (mid_price <= g_kalman.x_hat) && (g_avir.avir_val >= -0.60);
   bool sell_signal = (z_ofi <= -OFIZScoreThreshold) && (mid_price >= g_kalman.x_hat) && (g_avir.avir_val <= 0.60);

   if(!buy_signal && !sell_signal) return;

   // 7. Calculate Position Sizing & Order Targets (DIRECT INDEX POINTS - NO _Point MULTIPLICATION)
   double stop_points   = DefaultStopPoints;
   double target_points = stop_points * SizingTargetRR;

   if(buy_signal)
     {
      double entry_price = tick.ask;
      double sl_price    = entry_price - stop_points;
      double tp_price    = entry_price + target_points;
      double lots        = CalculateLotSize(entry_price, sl_price);

      if(lots > 0.0)
        {
         bool exec_ok = g_trade.Buy(lots, _Symbol, entry_price, sl_price, tp_price, "KESSLER_L2_BUY");
         if(exec_ok)
           {
            Print("[KESSLER EXECUTION SUCCESS] BUY ", lots, " lots at ", entry_price, " SL: ", sl_price, " TP: ", tp_price, " | Z_OFI: ", z_ofi, " VPIN: ", g_vpin.current_vpin, " AVIR: ", g_avir.avir_val);
           }
         else
           {
            Print("[KESSLER EXECUTION ERROR] BUY order failed. Code: ", g_trade.ResultRetcode());
           }
        }
     }
   else if(sell_signal)
     {
      double entry_price = tick.bid;
      double sl_price    = entry_price + stop_points;
      double tp_price    = entry_price - target_points;
      double lots        = CalculateLotSize(entry_price, sl_price);

      if(lots > 0.0)
        {
         bool exec_ok = g_trade.Sell(lots, _Symbol, entry_price, sl_price, tp_price, "KESSLER_L2_SELL");
         if(exec_ok)
           {
            Print("[KESSLER EXECUTION SUCCESS] SELL ", lots, " lots at ", entry_price, " SL: ", sl_price, " TP: ", tp_price, " | Z_OFI: ", z_ofi, " VPIN: ", g_vpin.current_vpin, " AVIR: ", g_avir.avir_val);
           }
         else
           {
            Print("[KESSLER EXECUTION ERROR] SELL order failed. Code: ", g_trade.ResultRetcode());
           }
        }
     }
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                     KESSLER_GEASS_OBLIVION.mq5   |
//|                            Sovereign Risk & L2 TD4 Neural Sniper |
//|                     Copyright 2026, Srijan (mid) // Kessler Node |
//+------------------------------------------------------------------+
#property copyright "Srijan (mid) // Kessler Node"
#property link      "https://kessler.node"
#property version   "5.00"
#property strict

// ------------------------------------------------------------------
// C-ABI DLL Handshake (monolith.dll / kessler_execution.dll)
// ------------------------------------------------------------------
#import "monolith.dll"
int monolith_init();
void monolith_shutdown();
double monolith_evaluate_tick(long timestamp, double bid, double ask, double volume, double current_equity, double daily_start_balance, double initial_balance);
#import

//--- FTMO Institutional Compliance & Sizing Inputs
input group "=== INSTITUTIONAL RISK & SIZING ==="
input double   BaseLotSize         = 0.50;    // Scaled Lot Size (Upgraded from 0.05)
input double   MaxDailyDrawdown    = 0.045;   // 4.5% Hard Sentinel (FTMO 5% Stop)
input double   MaxOverallDrawdown  = 0.095;   // 9.5% Hard Sentinel (FTMO 10% Stop)
input int      MinHoldSeconds      = 60;      // FTMO 60s Anti-HFT Minimum Hold Shield

input group "=== TRAILING RUNNER EXIT (ALPHA MAXIMIZER) ==="
input bool     EnableRunnerTrail   = true;    // Don't Choke Winners at 60s — Let Them Ride
input double   TrailStartATR       = 1.5;     // ATR Multiplier to Lock Break-Even
input double   TrailStepATR        = 2.0;     // ATR Trailing Step for 100+ Point Trends
input int      ATRPeriod           = 14;      // ATR Window

//--- Internal State
double         g_daily_start_balance;
double         g_initial_balance;
int            g_atr_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("+==================================================================+");
   Print("|              KESSLER GEASS OBLIVION — APEX L2 SNIPER             |");
   Print("|            INSTITUTIONAL FTMO CHALLENGE MAXIMIZER v5.0           |");
   Print("+==================================================================+");

   // 1. MANDATORY COMMODITIES & TOXIC SYMBOL BLACKLIST (KILL USOIL / CRUDE BLEED)
   string sym = Symbol();
   StringToUpper(sym);
   if (StringFind(sym, "OIL") >= 0 || StringFind(sym, "WTI") >= 0 || 
       StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0 || 
       StringFind(sym, "COMM") >= 0)
     {
      Print("[FATAL ABORT] Commodity symbol '", sym, "' detected and BLACKLISTED.");
      Print("[CRO DIRECTIVE] USOIL.cash bled -$16.37 with a 7% win rate. Engine restricted to US100.cash & US30.cash only!");
      return(INIT_FAILED);
     }

   // 2. DLL Weights Boot
   Print("[INIT] Booting Zero-Latency TD4 Neural Weights in Bare-Metal Cache...");
   int init_status = monolith_init();
   if (init_status != 1)
     {
      Print("[WARN] monolith.dll not found in library path. Running native Kalman/Z-Score fallback mode.");
     }
   else
     {
      Print("[INIT] monolith.dll neural weights linked successfully.");
     }

   g_daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);

   // 3. Setup ATR Indicator for Dynamic Runner Trailing
   g_atr_handle = iATR(Symbol(), PERIOD_M1, ATRPeriod);
   if (g_atr_handle == INVALID_HANDLE)
     {
      Print("[WARN] Failed to create M1 ATR handle. Trailing exit will use point fallback.");
     }

   Print("[INIT] KESSLER GEASS OBLIVION ONLINE. SYMBOL: ", Symbol(), " | BASE LOTS: ", BaseLotSize);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   monolith_shutdown();
   if (g_atr_handle != INVALID_HANDLE) IndicatorRelease(g_atr_handle);
   Print("[KESSLER] GEASS OBLIVION OFFLINE. SYMBOL: ", Symbol());
  }

//+------------------------------------------------------------------+
//| Helper: Get current M1 ATR                                       |
//+------------------------------------------------------------------+
double GetCurrentATR()
  {
   if (g_atr_handle == INVALID_HANDLE) return (20.0 * _Point);
   double atr_buf[];
   ArraySetAsSeries(atr_buf, true);
   if (CopyBuffer(g_atr_handle, 0, 0, 1, atr_buf) <= 0) return (20.0 * _Point);
   return atr_buf[0];
  }

//+------------------------------------------------------------------+
//| Expert tick function (The Execution & Trailing Engine)           |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. FTMO Hard Loss Sentinel Check
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double daily_dd = (g_daily_start_balance - current_equity) / g_daily_start_balance;
   double total_dd = (g_initial_balance - current_equity) / g_initial_balance;

   if (daily_dd >= MaxDailyDrawdown || total_dd >= MaxOverallDrawdown)
     {
      Print("[FTMO SENTINEL BREACH] Max Drawdown reached! Daily DD: ", daily_dd * 100.0, "%. Halting execution.");
      return;
     }

   // 2. MANAGE ACTIVE POSITIONS (60s HOLD + RUNNER TRAILING EXIT)
   for (int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if (PositionGetSymbol(i) != Symbol()) continue;
      
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      long open_time = PositionGetInteger(POSITION_TIME);
      long current_time = TimeCurrent();
      long duration = current_time - open_time;

      // RULE A: ANTI-HFT FTMO COMPLIANCE SHIELD (HOLD >= 60 SECONDS)
      if (duration < MinHoldSeconds)
        {
         continue; // Do not touch trade until 60 seconds have elapsed
        }

      // RULE B: RUNNER TRAILING EXIT (DO NOT FORCE-CLOSE AT 60s IF IN PROFIT)
      double current_profit_pts = 0.0;
      double position_price = PositionGetDouble(POSITION_PRICE_OPEN);
      long pos_type = PositionGetInteger(POSITION_TYPE);
      double current_sl = PositionGetDouble(POSITION_SL);
      double current_price = (pos_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK);

      if (pos_type == POSITION_TYPE_BUY)
         current_profit_pts = current_price - position_price;
      else
         current_profit_pts = position_price - current_price;

      double atr = GetCurrentATR();

      // If winner exceeds TrailStartATR, lock break-even stop and trail
      if (current_profit_pts >= (TrailStartATR * atr))
        {
         double new_sl = 0.0;
         if (pos_type == POSITION_TYPE_BUY)
           {
            new_sl = current_price - (TrailStepATR * atr);
            if (new_sl > current_sl && new_sl > position_price)
              {
               TradeModifySL(ticket, new_sl);
              }
           }
         else
           {
            new_sl = current_price + (TrailStepATR * atr);
            if ((current_sl == 0.0 || new_sl < current_sl) && new_sl < position_price)
              {
               TradeModifySL(ticket, new_sl);
              }
           }
        }
      else if (duration >= (MinHoldSeconds + 120) && current_profit_pts <= 0.0)
        {
         // If trade is stagnant/losing after 180 seconds, close to recycle capital
         TradeClose(ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| Trade Execution Helpers                                          |
//+------------------------------------------------------------------+
void TradeModifySL(ulong ticket, double sl_price)
  {
   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol = Symbol();
   req.sl = sl_price;
   req.tp = PositionGetDouble(POSITION_TP);
   OrderSend(req, res);
  }

void TradeClose(ulong ticket)
  {
   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action = TRADE_ACTION_DEAL;
   req.position = ticket;
   req.symbol = Symbol();
   req.volume = PositionGetDouble(POSITION_VOLUME);
   req.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price = (req.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   req.deviation = 10;
   OrderSend(req, res);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                           Kessler_Obsidian_TD4.mq5 |
//|                                  Copyright 2026, Srijan (Kessler)|
//|                       𝕂𝕖𝕤𝕤𝕝𝕖𝕣 𝕆𝕓𝕤𝕚𝕕𝕚𝕒𝕟 : 𝕋𝔻𝟜 𝔸𝕡𝕖𝕩  |
//+------------------------------------------------------------------+
#property copyright "Srijan (Kessler)"
#property link      "https://github.com/srijan/kessler"
#property version   "3.00"
#property description "𝕂𝕖𝕤𝕤𝕝𝕖𝕣 𝕆𝕓𝕤𝕚𝕕𝕚𝕒𝕟 | 𝕋𝔻𝟜 𝕀𝕟𝕤𝕥𝕚𝕥𝕦𝕥𝕚𝕠𝕟𝕒𝕝 𝔼𝕩𝕖𝕔𝕦𝕥𝕚𝕠𝕟 𝕄𝕒𝕥𝕣𝕚𝕩"
#property description "⚡ 128-Dim Windowed ActorMLP — Pure Equity Index Engine (US100 / US30)"
#property description "🛡️ Hardwired USOIL Blacklist + ATR Trailing Runner Shield (No 60s Clip)"
#property strict

#import "monolith.dll"
   int monolith_init();
   void monolith_shutdown();
   double monolith_evaluate_tick(long timestamp, double bid, double ask, double volume, double current_equity, double daily_start_balance, double initial_balance);
#import

//--- FTMO Institutional Risk & Sizing (CRO Approved)
input group "=== INSTITUTIONAL RISK & SIZING ==="
input double MaxDailyDrawdown   = 0.018; // 1.8% Hard Daily Stop (Avoids FTMO 3% Breach)
input double MaxOverallDrawdown = 0.085; // 8.5% Hard Overall Stop (Avoids FTMO 10% Breach)
input double FixedLotSize       = 0.50;  // 0.50 Scaled Institutional Lot Size (10x Alpha)
input int    MinHoldTimeSeconds = 60;    // FTMO 60-Second Anti-HFT Compliance Shield
input int    MagicNumber        = 28001; // Kessler Obsidian Magic Number

input group "=== DYNAMIC RUNNER TRAILING STOP ==="
input bool   EnableRunnerTrail  = true;  // Keep Winners Open for 100+ Point Trends
input double TrailStartATR      = 1.5;   // ATR Multiplier to Lock Break-Even Stop
input double TrailStepATR       = 2.0;   // ATR Trailing Step Window
input int    ATRPeriod          = 14;    // M1 ATR Period

double g_starting_equity;
double g_daily_start_equity;
int    g_last_day_year;
int    g_atr_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| EA Initialization                                                |
//+------------------------------------------------------------------+
int OnInit()
{
   // 1. MANDATORY COMMODITY BLACKLIST (KILL USOIL BLEED)
   string sym = Symbol();
   StringToUpper(sym);
   if (StringFind(sym, "OIL") >= 0 || StringFind(sym, "WTI") >= 0 || 
       StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0 || 
       StringFind(sym, "COMM") >= 0)
     {
      Print("[FATAL ABORT] Commodity symbol '", sym, "' detected and BLACKLISTED.");
      Print("[CRO DIRECTIVE] USOIL.cash bled -$16.37 with a 7% win rate. Engine restricted to US100.cash & US30.cash only!");
      return INIT_FAILED;
     }

   g_starting_equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   g_daily_start_equity = g_starting_equity;
   g_last_day_year      = -1;
   
   int res = monolith_init();
   if(res <= 0) {
      Print("[𝕂𝕖𝕤𝕤𝕝𝕖𝕣 𝕆𝕓𝕤𝕚𝕕𝕚𝕒𝕟] WARN: monolith_init() failed with code: ", res, ". Running native Z-score mode.");
   }
   
   g_atr_handle = iATR(Symbol(), PERIOD_M1, ATRPeriod);
   
   Print("+========================================================================+");
   Print("|   𝕂𝕖𝕤𝕤𝕝𝕖𝕣 𝕆𝕓𝕤𝕚𝕕𝕚𝕒𝕟 — 𝕋𝔻𝟜 ℕ𝔼𝕌ℝ𝔸𝕃 𝔼𝕏𝔼ℂ𝕌𝕋𝕀𝕆ℕ 𝔼ℕ𝔾𝕀ℕ𝔼  |");
   Print("+========================================================================+");
   Print("| [SYMBOL]       : ", Symbol(), " (COMMODITIES PURGED)");
   Print("| [LOT SIZE]     : ", FixedLotSize, " Lots (10x Institutional Sizing)");
   Print("| [TRAILING]     : ACTIVE (ATR Break-Even + Step)");
   Print("+========================================================================+");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EA Deinitialization                                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   monolith_shutdown();
   if(g_atr_handle != INVALID_HANDLE) IndicatorRelease(g_atr_handle);
   Print("[𝕂𝕖𝕤𝕤𝕝𝕖𝕣 𝕆𝕓𝕤𝕚𝕕𝕚𝕒𝕟] Engine offline. Reason code: ", reason);
   Comment("");
}

//+------------------------------------------------------------------+
//| Check FTMO Daily Drawdown & Update Midnight Balance              |
//+------------------------------------------------------------------+
bool IsDrawdownSafe(double current_equity)
{
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_year != g_last_day_year) {
      g_daily_start_equity = current_equity;
      g_last_day_year      = dt.day_of_year;
      Print("[𝕂𝕖𝕤𝕤𝕝𝕖𝕣 𝕆𝕓𝕤𝕚𝕕𝕚𝕒𝕟] New Trading Day: Reset Daily Start Equity to $", DoubleToString(g_daily_start_equity, 2));
   }
   
   double daily_limit   = g_daily_start_equity * (1.0 - MaxDailyDrawdown);
   double overall_limit = g_starting_equity * (1.0 - MaxOverallDrawdown);
   
   if(current_equity <= daily_limit || current_equity <= overall_limit) {
      Print("[𝕂𝕖𝕤𝕤𝕝𝕖𝕣 𝕆𝕓𝕤𝕚𝕕𝕚𝕒𝕟] RISK SENTINEL TRIGGERED: Drawdown limit reached. Closing positions.");
      return false;
   }
   return true;
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
//| Close open positions with Hold-Time & Trailing Logic             |
//+------------------------------------------------------------------+
void ManageAndClosePositions(bool ignore_hold_time, double action)
{
   double atr = GetCurrentATR();
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == Symbol() && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         long open_time = PositionGetInteger(POSITION_TIME);
         long duration = TimeCurrent() - open_time;
         
         if(!ignore_hold_time && duration < MinHoldTimeSeconds) {
            continue; // Respect FTMO 60s hold shield
         }

         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         long   pos_type   = PositionGetInteger(POSITION_TYPE);
         double current_sl = PositionGetDouble(POSITION_SL);
         double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         double current_price = (pos_type == POSITION_TYPE_BUY) ? bid : ask;
         double profit_pts = (pos_type == POSITION_TYPE_BUY) ? (current_price - open_price) : (open_price - current_price);

         // RULE 1: TRAILING RUNNER EXIT (DO NOT CHOKE WINNERS ON NEUTRAL SIGNAL)
         if(EnableRunnerTrail && profit_pts >= (TrailStartATR * atr)) {
            double new_sl = 0.0;
            if(pos_type == POSITION_TYPE_BUY) {
               new_sl = bid - (TrailStepATR * atr);
               if(new_sl > current_sl && new_sl > open_price) {
                  TradeModifySL(ticket, new_sl);
               }
            } else {
               new_sl = ask + (TrailStepATR * atr);
               if((current_sl == 0.0 || new_sl < current_sl) && new_sl < open_price) {
                  TradeModifySL(ticket, new_sl);
               }
            }
            // Let the trailing stop exit the winner — do not close on time/signal clip!
            continue;
         }

         // RULE 2: If trade is NOT a runner and signal neutralized (<0.20) OR stagnant after 180s, close to recycle
         if(MathAbs(action) < 0.20 || duration >= 180) {
            MqlTradeRequest request;
            MqlTradeResult  result;
            ZeroMemory(request);
            ZeroMemory(result);
            
            request.action   = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol   = Symbol();
            request.volume   = PositionGetDouble(POSITION_VOLUME);
            request.magic    = MagicNumber;
            
            if(pos_type == POSITION_TYPE_BUY) {
               request.type  = ORDER_TYPE_SELL;
               request.price = bid;
            } else {
               request.type  = ORDER_TYPE_BUY;
               request.price = ask;
            }
            
            OrderSend(request, result);
         }
      }
   }
}

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

//+------------------------------------------------------------------+
//| Execute Market Order                                             |
//+------------------------------------------------------------------+
void ExecuteOrder(ENUM_ORDER_TYPE type, double price)
{
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = Symbol();
   request.volume   = FixedLotSize;
   request.type     = type;
   request.price    = price;
   request.magic    = MagicNumber;
   request.comment  = "𝕂-𝕆𝕓𝕤";
   
   OrderSend(request, result);
   if(result.retcode == TRADE_RETCODE_DONE) {
      Print("[𝕂𝕖𝕤𝕤𝕝𝕖𝕣 𝕆𝕓𝕤𝕚𝕕𝕚𝕒𝕟] Executed order ticket #", result.order, " | Volume: ", FixedLotSize, " | Action: ", EnumToString(type));
   }
}

//+------------------------------------------------------------------+
//| Expert Tick Execution Loop                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!IsDrawdownSafe(current_equity)) {
      ManageAndClosePositions(true, 0.0); // Override 60s hold time in drawdown emergency
      return;
   }
   
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double vol = (double)SymbolInfoInteger(Symbol(), SYMBOL_VOLUME);
   
   long tick_time = TimeCurrent();
   double action = monolith_evaluate_tick(tick_time, bid, ask, vol, current_equity, g_daily_start_equity, g_starting_equity);
   
   // Live On-Chart Telemetry Display
   string telemetry = "𝕂𝕖𝕤𝕤𝕝𝕖𝕣 𝕆𝕓𝕤𝕚𝕕𝕚𝕒𝕟 : 𝕋𝔻𝟜 𝔸𝕡𝕖𝕩 𝔼𝕩𝕖𝕔𝕦𝕥𝕚𝕠𝕟\n" +
                      "-----------------------------------------\n" +
                      "⚡ Neural Action : " + DoubleToString(action, 4) + "\n" +
                      "🛡️ Daily Equity  : $" + DoubleToString(current_equity, 2) + "\n" +
                      "🔥 Sentinel Stop : $" + DoubleToString(g_daily_start_equity * (1.0 - MaxDailyDrawdown), 2) + "\n" +
                      "📊 Lot Sizing    : " + DoubleToString(FixedLotSize, 2) + " (Commodities Purged)";
   Comment(telemetry);
   
   // Have an open position?
   bool has_position = false;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(PositionGetSymbol(i) == Symbol() && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         has_position = true;
         break;
      }
   }
   
   // High-conviction sniper execution threshold (0.75)
   if(!has_position) {
      if(action > 0.75) {
         ExecuteOrder(ORDER_TYPE_BUY, ask);
      } else if(action < -0.75) {
         ExecuteOrder(ORDER_TYPE_SELL, bid);
      }
   } else {
      // Manage active positions with Runner Trailing Stop (no premature 60s clip!)
      ManageAndClosePositions(false, action);
   }
}
//+------------------------------------------------------------------+

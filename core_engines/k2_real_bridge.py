import ctypes
import os
import time
import datetime
import k2_dynamic_sizer as sizer

CSV_PATH = os.path.join(os.path.dirname(__file__), 'dashboard', 'live_trades.csv')

if not os.path.exists(CSV_PATH):
    os.makedirs(os.path.dirname(CSV_PATH), exist_ok=True)
    with open(CSV_PATH, 'w') as f:
        f.write("Timestamp,Direction,Lots,Fill_Price,Spread_pts,Slippage_pts,Commission,PnL,Equity\n")

# --- Setup C ABI Bridge ---
if os.name == 'nt':
    lib_filename = "ml_native.dll"
    lib_path = os.path.join(os.path.dirname(__file__), "zig-out", "bin", lib_filename)
else:
    lib_filename = "libml_native.so"
    lib_path = os.path.join(os.path.dirname(__file__), "zig-out", "lib", lib_filename)
try:
    k2 = ctypes.CDLL(lib_path)
except OSError as e:
    print(f"Error loading libml_native.so: {e}")
    print("Ensure you ran: zig build -Doptimize=ReleaseFast")
    exit(1)

# kessler_init() -> i32
k2.kessler_init.restype = ctypes.c_int32

# kessler_load_weights(path: *const u8) -> i32
k2.kessler_load_weights.argtypes = [ctypes.c_char_p]
k2.kessler_load_weights.restype = ctypes.c_int32

# kessler_infer(price: f32, time_val: f32, spread: f32, volume: f32) -> f32
k2.kessler_infer.argtypes = [ctypes.c_float, ctypes.c_float, ctypes.c_float, ctypes.c_float]
k2.kessler_infer.restype = ctypes.c_float

# kessler_get_equity() -> f32
k2.kessler_get_equity.restype = ctypes.c_float

# kessler_reset() -> void
k2.kessler_reset.restype = None

# kessler_push_bar(open, high, low, close, volume) -> void
k2.kessler_push_bar.argtypes = [ctypes.c_float, ctypes.c_float, ctypes.c_float, ctypes.c_float, ctypes.c_float]
k2.kessler_push_bar.restype = None

def init_k2(weights_path="kessler_v2_weights.bin"):
    print("[*] Initializing Kessler engine...")
    if k2.kessler_init() != 1:
        print("[-] Failed to initialize Kessler engine")
        return False
        
    print(f"[*] Loading weights from {weights_path}...")
    abs_weights = os.path.abspath(weights_path).encode("utf-8")
    if k2.kessler_load_weights(abs_weights) != 1:
        print(f"[-] Failed to load weights from {weights_path}")
        return False
        
    print("[+] Engine initialized and weights loaded successfully")
    return True

def run_forward_test():
    """
    Connect to MT5, fetch live NAS100 ticks, and pass to kessler_infer.
    This replaces the fake synthetic python loops with real Zig evaluation.
    """
    try:
        import MetaTrader5 as mt5
    except ImportError:
        print("MetaTrader5 python package not installed.")
        return

    login = int(os.environ.get("MT5_LOGIN", 0))
    password = os.environ.get("MT5_PASSWORD", "YOUR_PASSWORD")
    server = os.environ.get("MT5_SERVER", "YOUR_SERVER")

    if login != 0:
        authorized = mt5.initialize(login=login, password=password, server=server)
    else:
        authorized = mt5.initialize()

    if not authorized:
        print("initialize() failed, error code =", mt5.last_error())
        quit()
        
    symbol = os.environ.get("MT5_SYMBOL", "USTEC")
    if not mt5.symbol_select(symbol, True):
        print(f"Failed to select {symbol}")
        mt5.shutdown()
        return
        
    print(f"[*] Starting live forward test on {symbol}. Press Ctrl+C to stop.")
    
    if not mt5.symbol_select(symbol, True):
        print(f"Failed to select symbol {symbol}")
    
    # ─── CRITICAL: Backfill M5 bars into the Zig neural engine ───
    rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M5, 0, 200)
    if rates is not None and len(rates) > 0:
        for r in rates:
            k2.kessler_push_bar(
                float(r['open']),
                float(r['high']),
                float(r['low']),
                float(r['close']),
                float(r['tick_volume'])
            )
        print(f"[+] Backfilled {len(rates)} M5 bars into neural engine. Brain is ONLINE.")
    else:
        print("[-] WARNING: Could not fetch historical bars. Neural engine will output 0.0 until 150 bars accumulate.")
    
    last_bar_time = rates[-1]['time'] if rates is not None and len(rates) > 0 else 0
    last_logged_equity = -1.0
    
    try:
        while True:
            tick = mt5.symbol_info_tick(symbol)
            if tick is None:
                time.sleep(0.1)
                continue
            
            # ─── Push new M5 bars as they close ───
            latest_rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M5, 0, 1)
            if latest_rates is not None and len(latest_rates) > 0:
                bar_time = latest_rates[0]['time']
                if bar_time > last_bar_time:
                    k2.kessler_push_bar(
                        float(latest_rates[0]['open']),
                        float(latest_rates[0]['high']),
                        float(latest_rates[0]['low']),
                        float(latest_rates[0]['close']),
                        float(latest_rates[0]['tick_volume'])
                    )
                    last_bar_time = bar_time
                    print(f"[BAR] New M5 candle pushed: O={latest_rates[0]['open']:.2f} H={latest_rates[0]['high']:.2f} L={latest_rates[0]['low']:.2f} C={latest_rates[0]['close']:.2f}")
                
            # Use bid price
            price = tick.bid
            spread = (tick.ask - tick.bid) if tick.ask else 0.5
            volume = float(tick.volume)
            
            # Pass to Zig engine (now with real bar data feeding the observation space)
            action = k2.kessler_infer(price, 0.0, spread, volume)
            
            equity = k2.kessler_get_equity()
            
            print(f"Price: {price:.2f} | Action: {action:+.3f} | Equity: ${equity:.2f}")
            
            # --- PHYSICAL MT5 EXECUTION WITH HARD SERVER-SIDE SL ---
            positions = mt5.positions_get(symbol=symbol)
            if positions is not None and len(positions) == 0:
                sym_info = mt5.symbol_info(symbol)
                point = sym_info.point if sym_info else 0.01
                
                # --- DYNAMIC SIZER ---
                rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M5, 0, 15)
                current_atr = 25.0
                if rates is not None and len(rates) >= 15:
                    tracker = sizer.ATRTracker(period=100)
                    for r in rates:
                        atr = tracker.push_bar(r['high'], r['low'], r['close'])
                    if atr is not None:
                        current_atr = atr
                        
                lots, regime, diag = sizer.calculate_dynamic_lots(
                    current_atr=current_atr,
                    max_risk_usd=250.0,  # FTMO Strict Limit
                    signal_confidence=abs(action)
                )
                lots = min(lots, 5.0) # BAZOOKA HARD CAP
                print(f"[SIZER] {diag} | BAZOOKA LOTS: {lots}")
                
                sl_distance = diag["stop_points"]
                tp_distance = sl_distance * 1.5  # 1:1.5 R:R (Strict consistency profile)
                
                magic_num = 777777
                
                # Determine filling mode
                filling_mode = mt5.ORDER_FILLING_RETURN
                if sym_info.filling_mode & 1:
                    filling_mode = mt5.ORDER_FILLING_FOK
                elif sym_info.filling_mode & 2:
                    filling_mode = mt5.ORDER_FILLING_IOC
                
                if action > 0.90:
                    print(f"[!] KESSLER WYCKOFF TRIGGER: FIRING LONG at {tick.ask}")
                    request = {
                        "action": mt5.TRADE_ACTION_DEAL,
                        "symbol": symbol,
                        "volume": lots,
                        "type": mt5.ORDER_TYPE_BUY,
                        "price": tick.ask,
                        "sl": tick.ask - sl_distance,
                        "tp": tick.ask + tp_distance,
                        "deviation": 20,
                        "magic": magic_num,
                        "comment": "K2_Sniper_Long",
                        "type_time": mt5.ORDER_TIME_GTC,
                        "type_filling": filling_mode,
                    }
                    res = mt5.order_send(request)
                    if res.retcode != mt5.TRADE_RETCODE_DONE:
                        print(f"[-] Physical MT5 Order Failed: {res.comment}")
                    else:
                        print(f"[+] Physical Order FILLED! Price: {res.price}, SL: {request['sl']}")
                        
                elif action < -0.90:
                    print(f"[!] KESSLER WYCKOFF TRIGGER: FIRING SHORT at {tick.bid}")
                    request = {
                        "action": mt5.TRADE_ACTION_DEAL,
                        "symbol": symbol,
                        "volume": lots,
                        "type": mt5.ORDER_TYPE_SELL,
                        "price": tick.bid,
                        "sl": tick.bid + sl_distance,
                        "tp": tick.bid - tp_distance,
                        "deviation": 20,
                        "magic": magic_num,
                        "comment": "K2_Sniper_Short",
                        "type_time": mt5.ORDER_TIME_GTC,
                        "type_filling": filling_mode,
                    }
                    res = mt5.order_send(request)
                    if res.retcode != mt5.TRADE_RETCODE_DONE:
                        print(f"[-] Physical MT5 Order Failed: {res.comment}")
                    else:
                        print(f"[+] Physical Order FILLED! Price: {res.price}, SL: {request['sl']}")
            
            # Log to dashboard CSV if equity changes (meaning a trade closed) or if it's the first tick
            if abs(equity - last_logged_equity) > 0.01:
                pnl = equity - last_logged_equity if last_logged_equity > 0 else 0
                direction = "LONG" if action > 0 else "SHORT" if action < 0 else "HOLD"
                lots = 1.0 if pnl != 0 else 0.0
                ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                
                with open(CSV_PATH, 'a') as f:
                    f.write(f"{ts},{direction},{lots},{price:.2f},{spread:.2f},0.0,0.0,{pnl:.2f},{equity:.2f}\n")
                
                last_logged_equity = equity
                
            time.sleep(1.0) # Poll every 1s for the test
            
    except KeyboardInterrupt:
        print("\n[*] Forward test stopped.")
    finally:
        mt5.shutdown()

if __name__ == "__main__":
    if init_k2():
        print("[*] Bridge test successful.")
        run_forward_test()

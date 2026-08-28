import zmq
import time
import json
import numpy as np

class KesslerXAUUSDEngine:
    """
    Kessler TD3 - ZeroMQ Bridge for MT5
    Target: XAUUSD (Gold)
    Strategy: Statistical Z-Score Mean Reversion
    """
    def __init__(self, port=5555):
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.REP)
        self.socket.bind(f"tcp://*:{port}")
        self.price_history = []
        print(f"\n=============================================")
        print(f" INITIALIZING TD3 ZEROMQ ENGINE FOR MT5")
        print(f" TARGET: XAUUSD Z-SCORE MEAN REVERSION")
        print(f"=============================================\n")
        print(f"[TD3] Python Engine bound to tcp://*:{port}. Awaiting MT5 heartbeat...")

    def process_tick(self, close_price):
        self.price_history.append(close_price)
        
        # We need at least 100 periods to calculate a valid statistical deviation
        if len(self.price_history) < 100:
            return {"signal": 0, "z_score": 0.0, "status": "buffering"}
            
        # Maintain window size for capital efficiency
        if len(self.price_history) > 100:
            self.price_history.pop(0)

        # Cold Math: Z-Score Calculation
        prices = np.array(self.price_history)
        mean = np.mean(prices)
        std = np.std(prices)
        
        if std == 0:
            return {"signal": 0, "z_score": 0.0}
            
        current_z = (close_price - mean) / std
        
        # Execution Logic
        # Z-Score > +3.0 = Statistical anomaly (Overbought) -> SHORT (-1)
        # Z-Score < -3.0 = Statistical anomaly (Oversold) -> LONG (1)
        signal = 0
        if current_z >= 3.0:
            signal = -1
            print(f"[EXECUTE] XAUUSD SHORT FLAG TRIGGERED | Z-Score: {current_z:.2f}")
        elif current_z <= -3.0:
            signal = 1
            print(f"[EXECUTE] XAUUSD LONG FLAG TRIGGERED | Z-Score: {current_z:.2f}")
            
        return {"signal": signal, "z_score": float(current_z), "status": "active"}

    def run(self):
        while True:
            # Await tick data payload from the MQL5 EA
            message = self.socket.recv_string()
            
            try:
                data = json.loads(message)
                if "close" in data:
                    result = self.process_tick(data["close"])
                    self.socket.send_string(json.dumps(result))
                else:
                    self.socket.send_string(json.dumps({"error": "Invalid payload"}))
            except Exception as e:
                print(f"[ERR] Socket parsing failure: {e}")
                self.socket.send_string(json.dumps({"error": str(e)}))

if __name__ == "__main__":
    try:
        engine = KesslerXAUUSDEngine()
        engine.run()
    except KeyboardInterrupt:
        print("\n[TD3] Engine offline. Socket closed.")

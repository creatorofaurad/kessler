import time
import random
import os

OUTPUT_FILE = r"C:\Users\srija\Projects\kessler\macro_sentiment.csv"

def get_macro_sentiment():
    # In a full deployment, this would hit ForexFactory API or Finnhub.
    # For now, we simulate the NLP Volatility/Sentiment index.
    # 0 = Neutral (Safe to Trade), 1 = High Volatility (Killswitch)
    
    # Simulating a random macro spike 5% of the time
    if random.random() < 0.05:
        return {"event": "CPI_PRINT", "volatility_score": 0.95, "action": "KILLSWITCH"}
    return {"event": "NONE", "volatility_score": 0.10, "action": "CLEAR"}

print("[*] INITIALIZING MACRO-EVENT NEWS SNIPER...")
print("[*] Target: XAUUSD (Gold) Macro Feed")
print(f"[*] Dumping State Tensor to: {OUTPUT_FILE}")

for _ in range(5):
    state = get_macro_sentiment()
    print(f"[>] Macro Scan | Event: {state['event']} | Volatility: {state['volatility_score']} | Status: {state['action']}")
    
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(f"event,volatility_score,action\n")
        f.write(f"{state['event']},{state['volatility_score']},{state['action']}\n")
    
    time.sleep(1)

print("[+] MACRO SNIPER DAEMON ONLINE. FEEDING MT5 TENSORS.")

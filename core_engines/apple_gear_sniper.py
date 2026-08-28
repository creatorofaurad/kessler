import time
import random

print("\n[*] INITIALIZING TACTICAL INVENTORY SNIPER...")
print("[*] Target Payload: MacBook Pro M5 Max + iPhone")
print("[*] Value Target: \u20b912,800,000")

def scan_inventory():
    print("[>] Scanning Apple India Retail API...")
    time.sleep(1)
    print("[>] Scanning Authorized Resellers (Croma, Reliance Digital)...")
    time.sleep(1)
    
    # Simulate inventory status
    stock_status = "OUT_OF_STOCK"
    if random.random() < 0.1:
        stock_status = "IN_STOCK"
        
    print(f"[*] STATUS: M5 Max Config is currently {stock_status}")
    if stock_status == "IN_STOCK":
        print("[!] ALERT: SECURE THE PAYLOAD IMMEDIATELY.")
    else:
        print("[-] Still holding. Capital velocity continues.")

scan_inventory()

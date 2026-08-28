import asyncio
import json
import websockets
import os

print("[SYSTEM] Kessler Crypto Bridge Initializing...")
print("[SYSTEM] Target: Hyperliquid Testnet L1")

# Use Testnet for Sandbox
HL_WS_URL = "wss://api.hyperliquid-testnet.xyz/ws"

async def hyperliquid_feed():
    print(f"[*] Connecting to Hyperliquid L1 WebSocket: {HL_WS_URL}")
    
    async with websockets.connect(HL_WS_URL) as ws:
        print("[+] Connection Established. Subscribing to L2 Order Book & Trades...")
        
        # Subscribe to SOL trades (This gives us price action & liquidations)
        subscribe_msg = {
            "method": "subscribe",
            "subscription": {
                "type": "trades",
                "coin": "SOL"
            }
        }
        await ws.send(json.dumps(subscribe_msg))
        
        # Subscribe to L2 Book
        subscribe_l2 = {
            "method": "subscribe",
            "subscription": {
                "type": "l2Book",
                "coin": "SOL"
            }
        }
        await ws.send(json.dumps(subscribe_l2))

        print("[*] Awaiting Order Book Data...")
        
        # Listen to the stream
        while True:
            response = await ws.recv()
            data = json.loads(response)
            
            # Filter and display the data for our God Model
            if "channel" in data:
                if data["channel"] == "trades":
                    for trade in data["data"]:
                        side_val = trade.get("dir", trade.get("side", "Unknown"))
                        side = "🟢 BUY " if side_val in ["Buy", "B"] else "🔴 SELL"
                        price = float(trade.get("px", 0))
                        size = float(trade.get("sz", 0))
                        # Check for liquidations (Hyperliquid flags force-liquidations in the hash)
                        is_liq = trade.get("liquidated", trade.get("isLiquidation", False)) 
                        
                        if is_liq:
                            print(f"[LIQUIDATION CASCADE] {side} {size} SOL @ ${price:.2f} ⚠️ THE JUDAS SWAP IS PRIMED")
                        elif size > 50.0: # Only print whale orders to avoid spam
                            print(f"[WHALE ORDER] {side} {size} SOL @ ${price:.2f}")

                elif data["channel"] == "l2Book":
                    # We just grabbed the top of the book (Bid/Ask spread)
                    bids = data["data"]["levels"][0]
                    asks = data["data"]["levels"][1]
                    if bids and asks:
                        top_bid = bids[0]["px"]
                        top_ask = asks[0]["px"]
                        # print(f"[L2 SPREAD] Bid: {top_bid} | Ask: {top_ask}") # Uncomment to see raw spread

if __name__ == "__main__":
    try:
        asyncio.run(hyperliquid_feed())
    except KeyboardInterrupt:
        print("\n[SYSTEM] Disconnected from Hyperliquid L1.")
    except Exception as e:
        print(f"[-] Connection Error: {e}")
        print("    -> Make sure you have the 'websockets' library installed (pip install websockets)")

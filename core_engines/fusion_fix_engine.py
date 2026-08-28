import sys
import time
import quickfix as fix
import quickfix44 as fix44

class FusionFIXEngine(fix.Application):
    def __init__(self):
        super().__init__()
        self.sessionID = None

    def onCreate(self, sessionID):
        self.sessionID = sessionID
        print(f"[+] FIX API Session Created: {sessionID}")

    def onLogon(self, sessionID):
        print(f"[+] SUCCESS: Logged into Fusion Markets ECN Matching Engine -> {sessionID}")

    def onLogout(self, sessionID):
        print(f"[-] Disconnected from Fusion Markets ECN: {sessionID}")

    def toAdmin(self, message, sessionID):
        # Inject SenderSubID or credentials if Fusion Markets requires it
        pass

    def fromAdmin(self, message, sessionID):
        pass

    def toApp(self, message, sessionID):
        print(f"[>] Sending Order Message -> {message}")

    def fromApp(self, message, sessionID):
        print(f"[<] Incoming FIX Message: {message}")

    def execute_market_order(self, symbol, side, qty):
        if not self.sessionID:
            print("[-] CRITICAL ERROR: FIX Session not established.")
            return
            
        trade = fix.Message()
        trade.getHeader().setField(fix.BeginString(fix.BeginString_FIX44))
        trade.getHeader().setField(fix.MsgType(fix.MsgType_NewOrderSingle))

        trade.setField(fix.ClOrdID(str(int(time.time() * 1000)))) 
        trade.setField(fix.HandlInst(fix.HandlInst_MANUAL_ORDER_BEST_EXECUTION))
        trade.setField(fix.Symbol(symbol))
        
        # 1 = Buy, 2 = Sell
        fix_side = fix.Side_BUY if side == "BUY" else fix.Side_SELL
        trade.setField(fix.Side(fix_side))
        
        trade.setField(fix.OrderQty(qty))
        trade.setField(fix.OrdType(fix.OrdType_MARKET))
        
        print(f"[*] INITIATING SUB-MILLISECOND FIX EXECUTION: {side} {qty} lots of {symbol}")
        fix.Session.sendToTarget(trade, self.sessionID)

def main():
    print("===================================================")
    print(" [*] KESSLER ARK NODE: FUSION MARKETS FIX API ENGINE")
    print("===================================================")
    print("[*] Bypassing Retail Platforms. Establishing direct ECN socket...")
    
    # In a live deployment, this points to fusion_fix.cfg containing IP/Port/Credentials
    print("[*] Awaiting Fusion Markets FIX credentials to establish heartbeat...")
    time.sleep(1)
    print("[!] Engine scaffolded. Ready to bind to SAC-GRU Matrix.")

if __name__ == "__main__":
    main()

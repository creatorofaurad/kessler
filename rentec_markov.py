import sys

def main():
    print("[INIT] Booting RenTec Markov State Miner...")
    print("[MINING] Parsing 22 years of market microstructure...")

    transition_matrix = [[0, 0, 0, 0] for _ in range(4)]
    prev_close = 0.0
    prev_state = None
    lines_parsed = 0

    with open(r"C:\Users\srija\OneDrive\Desktop\XAUUSDM5.csv", 'r', encoding='utf-16le') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) < 6:
                continue

            try:
                h = float(parts[2])
                l = float(parts[3])
                c = float(parts[4])
            except ValueError:
                continue

            if prev_close == 0.0:
                prev_close = c
                continue

            ret = c - prev_close
            vol = h - l
            
            is_high_vol = vol > 1.5
            is_bull = ret > 0
            
            current_state = 0
            if not is_high_vol and not is_bull: current_state = 0
            if not is_high_vol and is_bull: current_state = 1
            if is_high_vol and not is_bull: current_state = 2 # Cascade
            if is_high_vol and is_bull: current_state = 3     # Squeeze
            
            if prev_state is not None:
                transition_matrix[prev_state][current_state] += 1
            
            prev_state = current_state
            prev_close = c
            lines_parsed += 1

    print(f"[DONE] Processed {lines_parsed} ticks. Transition Matrix:")
    
    for i in range(4):
        total_transitions = sum(transition_matrix[i])
        if total_transitions > 0:
            print(f"From State {i} ({get_state_name(i)}):")
            for j in range(4):
                prob = transition_matrix[i][j] / total_transitions
                print(f"  -> State {j} ({get_state_name(j)}): {prob:.4f} ({transition_matrix[i][j]} instances)")

def get_state_name(state):
    if state == 0: return "Low Vol, Bear"
    if state == 1: return "Low Vol, Bull"
    if state == 2: return "High Vol Cascade"
    if state == 3: return "High Vol Squeeze"
    return "Unknown"

if __name__ == "__main__":
    main()

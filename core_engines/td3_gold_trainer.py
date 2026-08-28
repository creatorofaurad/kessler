import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.nn.functional as F
import os
import copy
import time

# Hyperparameters
STATE_DIM = 7
ACTION_DIM = 1
MAX_ACTION = 1.0
BUFFER_SIZE = int(1e5)
BATCH_SIZE = 256
GAMMA = 0.99
TAU = 0.005
POLICY_NOISE = 0.2
NOISE_CLIP = 0.5
POLICY_FREQ = 2

class ReplayBuffer:
    def __init__(self, max_size=BUFFER_SIZE):
        self.state = np.zeros((max_size, STATE_DIM))
        self.action = np.zeros((max_size, ACTION_DIM))
        self.next_state = np.zeros((max_size, STATE_DIM))
        self.reward = np.zeros((max_size, 1))
        self.not_done = np.zeros((max_size, 1))
        self.max_size = max_size
        self.ptr = 0
        self.size = 0

    def add(self, state, action, next_state, reward, done):
        self.state[self.ptr] = state
        self.action[self.ptr] = action
        self.next_state[self.ptr] = next_state
        self.reward[self.ptr] = reward
        self.not_done[self.ptr] = 1. - done

        self.ptr = (self.ptr + 1) % self.max_size
        self.size = min(self.size + 1, self.max_size)

    def sample(self, batch_size):
        ind = np.random.randint(0, self.size, size=batch_size)
        return (
            torch.FloatTensor(self.state[ind]),
            torch.FloatTensor(self.action[ind]),
            torch.FloatTensor(self.next_state[ind]),
            torch.FloatTensor(self.reward[ind]),
            torch.FloatTensor(self.not_done[ind])
        )

class Actor(nn.Module):
    def __init__(self, state_dim, action_dim, max_action):
        super(Actor, self).__init__()
        self.l1 = nn.Linear(state_dim, 256)
        self.l2 = nn.Linear(256, 256)
        self.l3 = nn.Linear(256, action_dim)
        self.max_action = max_action

    def forward(self, state):
        a = F.relu(self.l1(state))
        a = F.relu(self.l2(a))
        return self.max_action * torch.tanh(self.l3(a))

class Critic(nn.Module):
    def __init__(self, state_dim, action_dim):
        super(Critic, self).__init__()
        # Q1 architecture
        self.l1 = nn.Linear(state_dim + action_dim, 256)
        self.l2 = nn.Linear(256, 256)
        self.l3 = nn.Linear(256, 1)
        # Q2 architecture
        self.l4 = nn.Linear(state_dim + action_dim, 256)
        self.l5 = nn.Linear(256, 256)
        self.l6 = nn.Linear(256, 1)

    def forward(self, state, action):
        sa = torch.cat([state, action], 1)
        q1 = F.relu(self.l1(sa))
        q1 = F.relu(self.l2(q1))
        q1 = self.l3(q1)
        q2 = F.relu(self.l4(sa))
        q2 = F.relu(self.l5(q2))
        q2 = self.l6(q2)
        return q1, q2

    def Q1(self, state, action):
        sa = torch.cat([state, action], 1)
        q1 = F.relu(self.l1(sa))
        q1 = F.relu(self.l2(q1))
        q1 = self.l3(q1)
        return q1

class TD3:
    def __init__(self):
        self.actor = Actor(STATE_DIM, ACTION_DIM, MAX_ACTION)
        self.actor_target = copy.deepcopy(self.actor)
        self.actor_optimizer = torch.optim.Adam(self.actor.parameters(), lr=3e-4)

        self.critic = Critic(STATE_DIM, ACTION_DIM)
        self.critic_target = copy.deepcopy(self.critic)
        self.critic_optimizer = torch.optim.Adam(self.critic.parameters(), lr=3e-4)

        self.total_it = 0

    def train(self, replay_buffer, batch_size=256):
        self.total_it += 1

        # Sample replay buffer 
        state, action, next_state, reward, not_done = replay_buffer.sample(batch_size)

        with torch.no_grad():
            # Select action according to policy and add clipped noise
            noise = (torch.randn_like(action) * POLICY_NOISE).clamp(-NOISE_CLIP, NOISE_CLIP)
            next_action = (self.actor_target(next_state) + noise).clamp(-MAX_ACTION, MAX_ACTION)

            # Compute the target Q value
            target_Q1, target_Q2 = self.critic_target(next_state, next_action)
            target_Q = torch.min(target_Q1, target_Q2)
            target_Q = reward + not_done * GAMMA * target_Q

        # Get current Q estimates
        current_Q1, current_Q2 = self.critic(state, action)

        # Compute critic loss
        critic_loss = F.mse_loss(current_Q1, target_Q) + F.mse_loss(current_Q2, target_Q)

        # Optimize the critic
        self.critic_optimizer.zero_grad()
        critic_loss.backward()
        self.critic_optimizer.step()

        # Delayed policy updates
        if self.total_it % POLICY_FREQ == 0:
            # Compute actor loss
            actor_loss = -self.critic.Q1(state, self.actor(state)).mean()
            
            # Optimize the actor 
            self.actor_optimizer.zero_grad()
            actor_loss.backward()
            self.actor_optimizer.step()

            # Update the frozen target models
            for param, target_param in zip(self.critic.parameters(), self.critic_target.parameters()):
                target_param.data.copy_(TAU * param.data + (1 - TAU) * target_param.data)

            for param, target_param in zip(self.actor.parameters(), self.actor_target.parameters()):
                target_param.data.copy_(TAU * param.data + (1 - TAU) * target_param.data)

class GoldEnvironment:
    def __init__(self, csv_path):
        self.df = pd.read_csv(csv_path)
        self.current_step = 0
        self.max_steps = len(self.df) - 1
        
        self.data = self.df[['Open', 'High', 'Low', 'Close', 'TickVolume', 'Spread', 'ATR_14']].values
        self.data = (self.data - np.mean(self.data, axis=0)) / (np.std(self.data, axis=0) + 1e-8)
        
    def reset(self):
        self.current_step = 0
        self.position = 0 
        self.entry_price = 0
        return self.data[self.current_step]

    def step(self, action):
        state = self.data[self.current_step]
        current_close = self.df.iloc[self.current_step]['Close']
        reward = 0
        done = False
        
        act = action[0]
        
        if self.position == 0:
            if act > 0.5:
                self.position = 1
                self.entry_price = current_close
            elif act < -0.5:
                self.position = -1
                self.entry_price = current_close
        else:
            profit_points = (current_close - self.entry_price) if self.position == 1 else (self.entry_price - current_close)
            
            if act > -0.5 and act < 0.5: 
                if profit_points > 0:
                    reward = 1.35 
                else:
                    reward = -3.0 
                self.position = 0
            else:
                reward = -2.0 
                
        self.current_step += 1
        if self.current_step >= self.max_steps:
            done = True
            
        next_state = self.data[self.current_step] if not done else np.zeros(STATE_DIM)
        return next_state, reward, done

def train_td3():
    csv_path = r"C:\Users\srija\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Files\Kessler_TD3_StateData_XAUUSD.csv"
    if not os.path.exists(csv_path):
        print(f"[ERROR] CSV not found at {csv_path}")
        return
        
    env = GoldEnvironment(csv_path)
    agent = TD3()
    replay_buffer = ReplayBuffer()
    
    print("[SYSTEM] Starting REAL TD3 Training Loop (This will take 30-45 mins)...")
    
    MAX_EPOCHS = 13
    total_timesteps = 0
    
    for epoch in range(MAX_EPOCHS):
        state = env.reset()
        done = False
        epoch_reward = 0
        
        start_time = time.time()
        
        while not done:
            if total_timesteps < 5000:
                action = np.random.uniform(-MAX_ACTION, MAX_ACTION, ACTION_DIM)
            else:
                state_tensor = torch.FloatTensor(state.reshape(1, -1))
                action = agent.actor(state_tensor).detach().numpy()[0]
                action = (action + np.random.normal(0, 0.1, size=ACTION_DIM)).clip(-MAX_ACTION, MAX_ACTION)
            
            next_state, reward, done = env.step(action)
            replay_buffer.add(state, action, next_state, reward, done)
            
            state = next_state
            epoch_reward += reward
            total_timesteps += 1
            
            if total_timesteps > 5000:
                agent.train(replay_buffer, BATCH_SIZE)
                
            if total_timesteps % 10000 == 0:
                print(f"Epoch: {epoch+1}/{MAX_EPOCHS} | Step: {total_timesteps} | Last Reward: {epoch_reward:.2f}")

        elapsed = time.time() - start_time
        print(f"[EPOCH {epoch+1} COMPLETE] Reward: {epoch_reward:.2f} | Time: {elapsed:.1f}s")
    
    with open("kessler_weights.bin", "wb") as f:
        for param in agent.actor.parameters():
            f.write(param.detach().numpy().tobytes())
            
    print("[SUCCESS] Exported REAL kessler_weights.bin")

if __name__ == "__main__":
    train_td3()

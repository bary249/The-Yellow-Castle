# Land of Clans & Wanderers – Core Rules

## 1. Objective
- Defend your crystal while attacking the enemy crystal.
- You **win** when the enemy crystal’s HP reaches 0.
- You **lose** when your crystal’s HP reaches 0.
- If time / turn limit is reached without a destroyed crystal, the winner is decided by **crystal HP / damage dealt** (or it’s a draw, depending on mode).

---

## 2. Match Setup
- Each player brings a **25-card deck**.
- At the start of the match:
  - Draw **6 cards** into your hand.
  - Your **crystal HP** is set (e.g. 100).
  - The board has **3 lanes**: Left, Center, Right.
- Each lane has 3 zones:
  - **Your Base** → **Middle** → **Enemy Base**.
- Your frontline and crystal can each have an **element attunement** (e.g. Fire, Water, Nature).

---

## 3. Cards & Hand
- Cards have:
  - **Damage** (how hard they hit).
  - **Health** (how much damage they can take).
  - **Tick** (1–5) = when/how often they act during combat.
  - Optional **Element** (Fire, Water, Nature, etc.).
  - Optional **Abilities** (keywords like Fury, Shield, Stack buffs/debuffs, etc.).
- Hand rules:
  - You start with **6 cards**.
  - At the start of each new round you draw **2 cards**.
  - There is a **hand size limit** (around 8–9 cards; exact cap can be tuned).
  - When the deck is empty, you **stop drawing** (no reshuffle).

Design intent: if you play too many cards early, you can run out of gas later.

---

## 4. Lanes & Stacks
- The battlefield has **3 lanes**, each with:
  - Your **Card Stack** (frontline) and the opponent’s **Card Stack**.
  - Each stack holds up to **2 cards**:
    - **Top** card = **active** card.
    - **Bottom** card = **backup**.
- Active card rules:
  - The **top card** fights first.
  - If the top card dies, the bottom card becomes active **at the start of the next tick**, not in the middle of a tick.
- Placement rules:
  - You can play up to **2 cards per lane**.
  - When a stack has 1 card and you add a second:
    - Place as **Top** → your new card becomes top; the old top moves to bottom.
    - Place as **Bottom** → your new card goes under the existing top.

---

## 5. Turn Structure (8-Second Turn Phase)
Each round has the following phases:

### 5.1 Turn Phase (Planning)
- Both players act **simultaneously** within an **8-second timer**:
  - Choose **0–2 cards per lane** from your hand.
  - Choose top/bottom placement for each lane’s stack.
  - Confirm your moves before the timer ends.
- When you place a card in a lane and confirm:
  - It **leaves your hand**.
  - You **cannot pull it back** to your hand later that round.

### 5.2 Combat Phase (Resolution)
- After **both players** submit their moves (or the timer expires), all lanes go into combat.
- Combat is resolved using a **5-tick system** (see next section).

### 5.3 Lane Advancement & Crystal Damage
- After combat in all lanes:
  - Winning sides **push their lane’s zone** forward toward the enemy base.
  - If a side reaches the **enemy base**, surviving cards **hit the enemy crystal**.

### 5.4 Draw Phase
- After advancement:
  - Both players draw **2 new cards** (if their deck still has cards).
  - The next **Turn Phase** begins.

---

## 6. Tick System (How Combat Works)
Combat in each lane is broken into **5 ticks**.

### 6.1 When Cards Act
- Cards have a **Tick** value from 1–5. This controls **when** they attack:
  - **Tick 1**: acts on **ticks 1, 2, 3, 4, 5** (every tick).
  - **Tick 2**: acts on **ticks 2 and 4**.
  - **Tick 3–5**: act **once**, on their matching tick number.

### 6.2 Simultaneous Combat
For each **tick** in each lane:
- Determine which cards are **active** (top or surviving bottom) on each side.
- If a card is scheduled to act this tick, it attacks.
- If **both** sides have active cards that act on this tick:
  - They **both deal damage** to each other, even if one dies from the other’s hit.
  - This avoids “I died before my turn” frustration.
- If only one side acts on this tick, it attacks alone.

### 6.3 Overflow Damage
- If an attack **kills** the top card and deals **more damage than needed**:
  - The extra (overflow) damage is applied to the **bottom card** in that stack (if it exists).
- The bottom card **still does not act mid-tick**; it only becomes active at the **start of the next tick** if still alive.

---

## 7. Damage, Elements & Abilities

### 7.1 Base Damage
- Each attack starts from the attacker’s **Damage stat**.

### 7.2 Element System (Simplified Player View)
- Cards and bases may have **elements** (e.g. Fire, Water, Nature).
- Basic relationships (example):
  - Fire **beats** Nature.
  - Nature **beats** Water.
  - Water **beats** Fire.
- If your element has advantage over the target’s element, you deal **extra damage**.
- If your element is at a disadvantage, you deal **less damage**.
- Fighting in your **own base zone** with a card that matches your base’s element gives a **small bonus** to your damage.

### 7.3 Example Abilities
(Exact numbers may vary; this is the intent.)
- **Fury**: flat bonus damage on each attack.
- **Shield**: reduces incoming damage.
- **Stack Buff**: your card gains extra damage while stacked with a specific ally.
- **Stack Debuff**: enemy attacks into this stack are slightly weaker.

The UI will show these abilities as **keywords** on the card.

---

## 8. Lane Advancement & Zones
Each lane tracks how far you’ve pushed toward the enemy crystal.

- **Zones** per lane:
  - Your Base → Middle → Enemy Base.
- After combat in a lane:
  - If you clearly **win** that lane this round:
    - The lane’s zone moves **one step toward the enemy base**.
  - If your opponent wins, the zone moves **toward your base**.
  - If it’s a **draw** (no clear winner), the zone **doesn’t move**.
- Reaching the **enemy base**:
  - Surviving cards in that lane directly deal their **Damage** to the **enemy crystal**.

Zones also interact with the **element system** (e.g. stronger in your own base).

---

## 9. End of Match
A match can end in a few ways:

- **Crystal Destroyed**
  - If your **crystal HP reaches 0**, you **lose**.
  - If the enemy crystal reaches 0, you **win**.

- **Turn / Time Limit Reached** (if configured)
  - Compare **remaining crystal HP**.
  - Possible outcomes:
    - You win on higher HP.
    - You lose on lower HP.
    - Or the game declares a **draw**.

---

## 10. Future / Optional Systems (High-Level)
These systems are part of the wider design and may be enabled later:

- **Hero System**
  - Each deck has **one Hero** with special abilities.
  - Hero abilities are used a **limited number of times** per match.
  - Effects include buffs, heals, extra draws, etc.

- **Gold & Post-Match Shop**
  - Earn gold by destroying cards, capturing zones, and win streaks.
  - A portion (e.g. 25%) carries over to a **post-match shop** for card and upgrade purchases.

- **Character Families & Ultimates**
  - Some cards belong to **families** (e.g. Monkey, Ant) with **3 variations**.
  - Playing all 3 variations can trigger a powerful **Ultimate** effect.

These details are for long-term progression and content, and don’t change the **core turn-by-turn rules** described above.

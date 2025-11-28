# Land of Clans & Wanderers – Core Rules

> **Terminology note (for developers):**
> In code, stack positions are currently named `topCard`/`bottomCard`.
> In these rules and the UI we use **Front**/**Back**.

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
- Each **base** (yours and your opponent's) can have a **terrain attunement** (e.g. Marsh, Woods, Lake, Desert).
- Each player selects a **Hero** before the match begins.

---

## 2.1 Fog of War

- **Enemy base terrains are hidden** at the start of the match.
- You see "???" on enemy base tiles until revealed.
- A lane's enemy base terrain is **revealed when you capture that lane's middle tile**.
- Once revealed, the terrain **stays visible for the rest of the match**.
- This adds strategic uncertainty about terrain bonuses the enemy might have.

---

## 2.2 Heroes

- Heroes are **historical figures** with unique abilities.
- Each hero has:
  - **Terrain Affinities** (1–2 terrains they're associated with, e.g., Napoleon → Woods, Lake).
  - **One special ability** that can be used **once per match**.
- The hero's terrain affinity determines your **base terrain** for the match.

### Available Heroes

| Hero | Terrain | Ability |
|------|---------|---------|
| **Napoleon Bonaparte** | Woods, Lake | Draw 2 extra cards this turn |
| **Saladin** | Desert | Give all your units +1 damage this turn |
| **Admiral Nelson** | Lake | Heal all surviving units by 3 HP |

### Using Your Hero Ability

- Click the **ABILITY** button next to your player info.
- Ability can only be used **during the staging phase** (before you submit your moves).
- Once used, the ability cannot be used again for the rest of the match.
- The button turns grey after use.

---

## 3. Cards & Hand
- Cards have:
  - **Damage** (how hard they hit).
  - **Health** (how much damage they can take).
  - **Tick** (1–5) = when/how often they act during combat.
  - Optional **Terrain tag** (Marsh, Woods, Lake, Desert, etc.).
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
    - **Front** card = **active** card (closest to the enemy).
    - **Back** card = **backup** (behind the front card).
- Active card rules:
  - The **front card** fights first.
  - If the front card dies, the back card becomes active **at the start of the next tick**, not in the middle of a tick.
- Placement rules:
  - You can play up to **2 cards per lane**.
  - When a stack has 1 card and you add a second:
    - Place as **Front** → your new card becomes front; the old front moves to back.
    - Place as **Back** → your new card goes behind the existing front card.

---

## 5. Turn Structure (8-Second Turn Phase)
Each round has the following phases:

### 5.1 Turn Phase (Planning)
- Both players act **simultaneously** within an **8-second timer**:
  - Choose **0–2 cards per lane** from your hand.
  - Choose front/back placement for each lane’s stack.
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
- Determine which cards are **active** (front or surviving back card) on each side.
- If a card is scheduled to act this tick, it attacks.
- If **both** sides have active cards that act on this tick:
  - They **both deal damage** to each other, even if one dies from the other’s hit.
  - This avoids “I died before my turn” frustration.
- If only one side acts on this tick, it attacks alone.

### 6.3 Overflow Damage
- If an attack **kills** the front card and deals **more damage than needed**:
  - The extra (overflow) damage is applied to the **back card** in that stack (if it exists).
- The back card **still does not act mid-tick**; it only becomes active at the **start of the next tick** if still alive.

---

## 7. Damage, Terrain & Abilities

### 7.1 Base Damage
- Each attack starts from the attacker’s **Damage stat**.

### 7.2 Terrain & Zone Attunement (Simplified Player View)
- Cards and bases may have **terrain tags** (e.g. Marsh, Woods, Lake, Desert).
- There is **no card-vs-card rock-paper-scissors** in the current implementation.
- Terrain only matters via **zone attunement**:
  - When combat happens in a **base zone** (either your base or the enemy base), if your card’s terrain matches that base’s terrain, that attack gets a **small bonus** to its damage.

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

Zones also interact with the **terrain attunement** system (e.g. slightly stronger in your own attuned base terrain; no direct terrain-vs-terrain matchup).

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
  - Each deck has **one Hero** with a unique ability.
  - The hero ability is intended as a **single powerful use per match** (design: 1 ability, 1 use).
  - Effects include buffs, heals, extra draws, etc.

- **Gold & Post-Match Shop**
  - Earn gold by destroying cards, capturing zones, and win streaks.
  - A portion (e.g. 25%) carries over to a **post-match shop** for card and upgrade purchases.

- **Character Families & Ultimates**
  - Some cards belong to **families** (e.g. Monkey, Ant) with **3 variations**.
  - Playing all 3 variations can trigger a powerful **Ultimate** effect.

- **3 Ages System**
  - The match is divided into **three Ages** (early, mid, late game).
  - Each Age is tied to a different **deck** for the same player.
  - As turns progress, the game automatically **switches to the next Age deck** at set turn thresholds.
  - The UI will clearly show the **current Age/deck** so players know which stage of the battle they are in.

These details are for long-term progression and content, and don’t change the **core turn-by-turn rules** described above.

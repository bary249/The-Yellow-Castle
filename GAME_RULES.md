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
- Terrain assignments:
  - **Base tiles** (yours and opponent's) have terrain matching their Hero's attunement.
  - **Middle tiles** have **random terrain** (Woods, Lake, Desert, or Marsh).
- Each player selects a **Hero** before the match begins.

---

## 2.1 Fog of War

- **Enemy base terrains AND cards are hidden** at the start of the match.
- You see "???" on enemy base tiles until revealed.
- A lane's enemy base is **revealed when you capture that lane's middle tile**.
- Once revealed, both terrain AND cards **stay visible for the rest of the match**.
- This adds strategic uncertainty:
  - You don't know enemy terrain bonuses
  - You don't know what cards they've deployed to their base

### Scout Visibility
- **Scout** units have a special ability to see through fog of war.
- When a Scout is in the **middle row**, it reveals enemy base tiles:
  - **West lane**: Reveals West and Center enemy bases
  - **Center lane**: Reveals ALL 3 enemy bases (West, Center, East)
  - **East lane**: Reveals East and Center enemy bases
- Scouts are valuable for reconnaissance but deal **0 damage**.

---

## 2.2 Relics

- A **hidden relic** is placed on a **random middle tile** (West, Center, or East) at the start of each match.
- Players don't know which tile contains the relic until they reach it.
- The **first player to reach the relic tile** claims it.
- **Relic Reward**: Currently grants a random Rare or Epic card added to your hand.
- Future relic types may include:
  - Gold bonuses
  - Crystal healing
  - Extra card draws
  - Temporary buffs

**Campaign note:**
- Campaign mode can also grant **persistent relics** as progression rewards (e.g. act completion).
- These campaign relics can modify battle rewards (gold) or apply a flat stat bonus (e.g. +1 damage) at match start.
- These are separate from the in-match relic tile described above.

- Story Mode can also apply **persistent deck changes**: cards destroyed during battle are removed from your campaign deck for the rest of the run.

- Home Town buildings can have a **supply time** measured in **encounters** (cooldown between collects).
- Story Mode starts with a basic **Training Grounds** building in the Home Town.
- Advanced Home Town buildings can deliver **higher rarity** cards with a **longer** supply time.
- Supply time can also be increased based on **distance from Home Town**.
- Hero progression unlocks can also grant **Home Town perks**.
- When a Home Town building delivers a reward, the game shows what arrived.
- Some encounters grant an additional **pre-determined offer** (consumable/relic/building) on completion.
- Encounter selection can show you this offer before you commit to traveling there.

- Boss pacing (Campaign/Story Mode):
  - The boss becomes **available after 7 encounters** in the current act.
  - The boss encounter is **not forced**; when available, it appears as one of the selectable encounter options alongside regular encounters.

- Boss battles (Campaign/Story Mode):
  - Boss encounters include a **unique boss unit card** in the enemy deck (named after the boss).
  - Boss cards have **very strong stats** and **multiple abilities**.

- Act transitions (Campaign/Story Mode):
  - When you defeat the boss and enter the next act:
    - Your cards, relics, consumables/items, and buildings **carry over**.
    - Your army is restored: **all fallen cards return** and your base HP is set to **full**.

- Shop encounters can allow you to **repair** previously destroyed cards for a gold cost.
- After encounters, you can optionally visit your Home Town before choosing the next destination.

- Home Town shows your distance from town and supply status for buildings.

- In Story Mode, the encounter location can affect the middle and enemy base terrain.

- Some Story Mode battles are **conquerable cities**.
- After conquering a city, a **Defense** encounter can appear as a selectable encounter.
- Defense encounters give **+1 damage and +1 HP** to all player cards for that battle.

- The campaign map can show the route you have traveled so far.

- After encounters in Story Mode, a short story/dispatch dialog can appear.

- Home Town building deliveries can arrive automatically when ready (no manual collect required), and will show a delivery dialog.

- Home Town can offer a paid action to hurry logistics:
  - **Hurry Supply** costs **100 gold**.
  - It reduces all in-flight supply deliveries to arrive in **1 encounter**.
  - It also reduces any building cooldowns (without an in-flight delivery) to be ready in **1 encounter**.

- Campaign mode also has **consumables** (e.g. healing, remove-card) that are stored in the campaign inventory and can be equipped/used between encounters.

---

## 2.3 Heroes

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
  - **Move Speed** (0, 1, or 2) = how many zones the card moves per turn.
    - **0**: Stationary (stays in place, defensive)
    - **1**: Normal (moves 1 zone per turn)
    - **2**: Fast (moves 2 zones per turn, reaches enemy quickly)
  - **Rarity** (Common, Rare, Epic, Legendary) - determines deck limits.
  - Optional **Terrain tag** (Marsh, Woods, Lake, Desert, etc.).
  - Optional **Abilities** (keywords like Fury, Shield, Regen, etc.).

### 3.1 Card Rarity System

| Rarity | Color | Max Copies in Deck | Description |
|--------|-------|-------------------|-------------|
| **Common** | Grey | Unlimited | Basic troops - Quick Strikes, Warriors, Tanks |
| **Rare** | Blue | 3 copies | Elite versions with +25% stats |
| **Epic** | Purple | 2 copies | Specialists with powerful abilities |
| **Legendary** | Gold | 1 copy | Champions with unique powers |

### 3.2 Card Types

**Common Cards:**
- Quick Strike (tick 1, fast attacker)
- Warrior (tick 3, balanced)
- Tank (tick 5, high damage/health)

**Rare Cards:**
- Elite Striker (better Quick Strike)
- Veteran (better Warrior)

**Epic Cards:**
- Shield Totem (defensive support)
- War Banner (offensive support)
- Healing Tree (heal/regen support)
- Berserker (glass cannon)
- Guardian (super tank)
- Sentinel (regen tank)

**Legendary Cards:**
- Sunfire Warlord (Desert champion - fury + cleave)
- Tidal Leviathan (Lake champion - massive tank)
- Ancient Treant (Woods champion - regen + thorns)

- Hand rules:
  - You start with **6 cards**.
  - At the start of each new round you draw **2 cards**.
  - There is a **hand size limit** (around 8–9 cards; exact cap can be tuned).
- When the deck is empty, you **stop drawing** (no reshuffle).

Design intent: if you play too many cards early, you can run out of gas later.

---

## 3.3 Charges & Consumable Abilities (TYC3)

Some abilities are **consumable** and have a limited number of **charges** per unit.

- A charged ability is shown with a number, e.g. `Ignite 2 (1)`.
- When the charge reaches `0`, that ability can no longer be used for the rest of the match unless refreshed.

**Examples (implemented):**
- **Ignite X**: spend 1 charge to ignite an adjacent tile for `X` turns. Units on ignited tiles take **1 damage per turn**.
- **Poisoner**: spends 1 charge on an attack to poison the target for 2 turns (**1 damage per turn**).
- **Resetter**: refreshes consumable charges on a friendly unit on the same tile and then self-destructs.

**DOT Stacking**: Poison and ignite damage **stack**. A poisoned unit standing on an ignited tile takes **2 damage** at the start of their owner's turn.

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
  - Choose **0–1 card per lane** from your hand (max 1 card per lane per turn).
  - Cards can only be staged at **your base** (row 2).
    - Exception: Cards with **paratrooper** ability can be staged at middle if you own it.
  - You can remove staged cards before submitting (X button on card).
  - Confirm your moves before the timer ends.
- When you place a card in a lane and confirm:
  - It **leaves your hand**.
  - You **cannot pull it back** to your hand later that round.

### 5.2 Movement Phase
- **Before combat**, all cards move forward based on their **Move Speed**:
  - Cards move 0, 1, or 2 zones toward the enemy base.
  - Movement **stops** when encountering enemy cards.
  - Combat happens wherever cards meet.

### 5.3 Combat Phase (Resolution)
- After **both players** submit their moves (or the timer expires), all lanes go into combat.
- Combat is resolved using a **5-tick system** (see next section).

### 5.4 Crystal Damage
- Crystal damage occurs when:
  - **Uncontested**: Your cards at enemy base with no defenders → deal damage each turn.
  - **Combat victory at enemy base**: Surviving attackers deal their damage.
- Attackers **stay at enemy base** after dealing damage (they hold position).
- Defender must send cards to push attackers back.

### 5.5 Draw Phase
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

### 7.2 Terrain Attunement
- Each tile on the board has a **terrain type** (Woods, Lake, Desert, or Marsh).
- Cards may have an **element** that matches a terrain type.
- **Terrain Buff**: When a card's element matches the tile's terrain where combat is happening, that card gets **+1 damage**.
- This applies to **ANY tile** - base tiles AND middle tiles.
- Example: A "Woods" element card fighting on a "Woods" terrain tile gets +1 damage bonus.

### 7.2.1 Burning Terrain (Woods/Forest)
-- Burning is **not automatic** on Woods/Forest.
-- A Woods/Forest tile only burns if it is **ignited** by an **Ignite** ability.
-- When a unit **moves onto** an **ignited Woods/Forest** tile, it immediately takes **1 damage**.
-- After taking damage, the unit is **knocked back** to the tile it came from if that tile is valid and has space.
-- Ignition lasts **2 turns** (active on turn T and T+1 if ignited on turn T).
-- This happens **mid-turn** (as part of movement), not only during combat.

### 7.3 Abilities Reference

| Ability | Effect |
|---------|--------|
| **fury_X** | +X damage when attacking |
| **shield_X** | Reduces incoming damage by X |
| **regen_X** | Heals X HP each tick |
| **thorns_X** | Reflects X damage back to attackers |
| **cleave** | Attacks hit all enemy cards in the lane |
| **regenerate** | Slowly regenerates health over time |
| **heal_ally_X** | Heals friendly cards by X HP per tick |
| **stack_buff_damage_X** | +X damage to all friendly cards in stack |
| **stack_debuff_enemy_damage_X** | -X damage to all enemy cards in lane |
| **conceal_back** | When front card with a back card, hides back card identity from enemy |
| **scout** | Reveals enemy base tiles in adjacent lanes (see Fog of War section) |
| **trap_X** | Place a hidden trap on matching terrain; when an enemy enters that tile it takes X damage (trap is consumed) |
| **ignite_X** | Ignite an adjacent tile for X turns (burning triggers only on ignited Woods/Forest) |
| **spy** | Invisible infiltrator: undetectable by enemies (except watcher); cannot attack or be targeted by direct attacks; can share tiles with enemy units; on entering enemy base auto-kills 1 enemy there (if 1–2 exist) otherwise deals 1 base damage; then self-destructs |
| **watcher** | Reveals spies and hidden cards within 1 tile (same tile, left, right, forward) |
| **push_back** | When attacking normally, pushes enemy cards on the attacked tile 1 tile backward |
| **glue** | Enemy cards in front of this unit cannot intentionally move while this unit remains behind them |
| **silence** | Enemy cards in front of this unit cannot attack while this unit remains behind them |
| **paralyze** | Enemy cards in front of this unit cannot move or attack while this unit remains behind them |
| **barrier** | Negates the next incoming damage to this unit (once per match) |
| **fear** | The first time an enemy unit enters the tile directly in front of this unit, that enemy unit’s AP is set to 0 (once per enemy unit per fear-card) |
| **terrain_affinity** | While standing on terrain: Lake gives +1 AP on arrival (once per tile per turn), Marsh gives +5 HP, Desert becomes ranged, Woods gives +3 damage |
| **mega_taunt** | Intercepts enemy base attacks for adjacent bases (highest HP interceptor, deterministic tie-break) |
| **tall** | Provides fog-of-war visibility within Manhattan distance 1 |
| **shaco** | On play, spawns a decoy copy in each other lane (same row); decoys deal 0 damage and die when attacking |
| **one_side_attacker** | From side lanes, also hits center + far side (same row); only primary target retaliates |
| **two_side_attacker** | From center hits both sides; from side hits center; only primary target retaliates |
| **enhancer** | Target a friendly unit on the same tile to double its damage, then self-destruct |
| **switcher** | Target 2 friendly units on the same tile to swap their abilities, then self-destruct |

### 7.4 Medic Special Rule (Play-to-Heal)
- If you play a **Medic** card from hand directly onto **your base tile** (row closest to your hand) and that tile contains an **injured friendly unit**:
  - The Medic **does not pay the placement AP cost**.
  - The Medic immediately **heals one injured friendly unit on that same tile**, spending **only the heal AP cost** (same as attack AP cost).
- Medics **never heal cards in hand**.

The UI will show these abilities as **keywords** on the card with full descriptions in the deck editor.

---

## 8. Lane Advancement & Zones
Each lane tracks how far you've pushed toward the enemy crystal.

### 8.1 Zone Positions
- **Zones** per lane: Your Base → Middle → Enemy Base.
- The **zone represents where combat happens** (the front line).
- Players can **only stage cards at their own base** (captured tiles).
- You **cannot stage cards at enemy base** - capturing enemy base = win condition.

### 8.2 Combat Location
- Combat happens **at the zone position**:
  - Zone at Middle → combat at middle tile
  - Zone at Enemy Base → combat at enemy base tile
  - Zone at Your Base → combat at your base tile
- Cards from both sides **advance toward the zone** to fight.
- **Terrain buffs apply based on the tile's terrain**, not the zone type.

### 8.3 Zone Movement
- After combat in a lane:
  - If you clearly **win** that lane this round:
    - The lane's zone moves **one step toward the enemy base**.
  - If your opponent wins, the zone moves **toward your base**.
  - If it's a **draw** (no clear winner), the zone **doesn't move**.

### 8.4 Crystal Damage
- Crystal damage occurs when your cards are at **enemy base**:
  - **Uncontested attack**: If no defenders, your cards deal damage each turn they stay there.
  - **Combat victory**: If you win combat at enemy base, survivors deal their damage.
- Attackers **stay at enemy base** after dealing damage (no retreat).
- To stop crystal damage, the defender must send cards to that lane.
- This creates pressure: once attackers reach enemy base, they keep dealing damage until pushed back.

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




I want to write a game where the player is a historical leader and the game is a turn-based match against an AI opponent.
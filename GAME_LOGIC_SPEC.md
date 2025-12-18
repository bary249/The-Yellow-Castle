# Land of Clans & Wanderers – Game Logic Spec

This document captures the **implemented and intended logic** of the game, mapped to current code where possible.

- High-level rules & player-facing view → see `GAME_RULES.md`.
- This file → dev-facing reference for match flow, combat math, and lane logic.

---

## 1. Core Concepts & Data Structures

### 1.1 Cards (`GameCard`)

**Key fields (conceptual):**
- `name`, `id` (identification).
- `damage` (base damage per attack).
- `maxHealth` / `currentHealth`.
- `tick` (1–5): timing profile.
- `element` (nullable string, treated as a **terrain tag** such as `Marsh`, `Woods`, `Lake`, `Desert`, etc.).
- `rarity` (int 1-4): determines deck copy limits.
  - 1 = Common (unlimited)
  - 2 = Rare (max 3 copies)
  - 3 = Epic (max 2 copies)
  - 4 = Legendary (max 1 copy)
- `abilities` (list of string tags):
  - Offensive: `fury_X`, `cleave`, `thorns_X`, `first_strike`
  - Defensive: `shield_X`, `regen_X`, `regenerate`, `guard`
  - Support: `heal_ally_X`, `inspire_X`, `fortify_X`, `rally_X`, `command_X`
  - Attack Style: `ranged` (no retaliation), `far_attack` (attacks from distance)
  - Tactical: `conceal_back`, `scout`, `paratrooper`, `stealth_pass`
- `isAlive` (derived from `currentHealth > 0`).

**Important behavior:**
- `takeDamage(int amount)` reduces `currentHealth` and returns whether the card died.

---

### 1.2 Deck (`Deck`)

- Holds a fixed list of `GameCard` instances (design target: **25 cards**, min **15 cards**).
- **Rarity scarcity limits enforced:**
  - Common: unlimited copies
  - Rare: max 3 copies of each card
  - Epic: max 2 copies of each card
  - Legendary: max 1 copy of each card
- Factory constructors:
  - `Deck.starter(playerId)` - creates default 25-card deck
  - `Deck.fromCards(playerId, cards)` - creates deck from saved cards (pads to 25 if needed)
- Provides:
  - `shuffle()` at match start.
  - `drawCards(count)` to draw a batch of cards.
  - `remainingCards` for UI.
- No **mid-match reshuffle**: once deck is empty, no more draws.
- **Firebase persistence:** decks saved to `users/{userId}/user_decks/{deckId}`.

---

### 1.3 Player (`Player`)

**Fields (conceptual):**
- `id`, `name`, `isHuman`.
- `deck` (Deck).
- `hand` (`List<GameCard>`).
- `crystalHP` (int, default e.g. 100).
- `gold` (int; match currency, partially used / TBD).
- `attunedElement` (optional element for base/crystal attunement).
- `hero` (optional `GameHero`).

**Important flags/methods:**
- `isDefeated` → `crystalHP <= 0`.
- `isHandFull` → hand >= `maxHandSize` (design ~8).
- `drawInitialHand()` → draw 6.
- `drawCards({count = 2})` per new turn.
- `playCard(GameCard)` → removes card from hand if present.
- `takeCrystalDamage(int)` → reduces `crystalHP` (floor at 0).

---

### 1.4 Hero (`GameHero`)

**Fields:**
- `id`, `name`, `description`.
- `terrainAffinities` (list of 1–2 terrain types, e.g., `['Woods', 'Lake']`).
- `abilityType` (enum: `drawCards`, `damageBoost`, `healUnits`).
- `abilityDescription` (player-facing text).
- `abilityUsed` (bool, tracks if ability has been used this match).

**Ability Types:**
- `drawCards`: Draw 2 extra cards this turn.
- `damageBoost`: Give all your units +1 damage this turn (applied during combat).
- `healUnits`: Heal all surviving units by 3 HP.

**Usage rules:**
- Hero ability can only be used **once per match**.
- Must be activated **during staging phase** (before submission).
- After submission, ability cannot be used that turn.
- After ability is used, `abilityUsed` is set to `true` and button is disabled.

**Hero ↔ Base Terrain:**
- The hero's `terrainAffinities` can determine the player's base terrain(s).
- Currently, the first affinity is used as the player's `attunedElement`.

---

### 1.4.1 Campaign Modifiers (Campaign Mode)

- Campaign mode can apply **persistent bonuses** (e.g. from relics) into a battle.
- These bonuses are passed into the battle screen (`TestMatchScreen`) as parameters and applied at match initialization.

- Campaign mode can also apply **persistent deck changes**.
  - In Story Mode, player cards destroyed during a battle are removed from `CampaignState.deck` for the rest of the run.

- Home Town buildings can have a **supply time** measured in **encounters** (cooldown between collects).
- Story Mode starts with a basic **Training Grounds** building in the Home Town.
- Advanced Home Town buildings can deliver **higher rarity** cards with a **longer** supply time.
- Supply time can also be increased based on **distance from Home Town**.
- Hero progression unlocks can also grant **Home Town perks** (e.g. building cost discounts, improved logistics).
- When a Home Town building delivers a reward, the UI can show a dialog to confirm what arrived.
- Encounters can include a **pre-determined offer** (e.g. consumable/relic/building) that is generated with the encounter and awarded on completion.
- Encounter selection UI can display the offer before the player chooses a node.
- Campaign boss pacing:
  - The boss becomes **available after 7 encounters** in the current act.
  - The boss encounter is **not forced**; when available, it appears as one of the selectable encounter options alongside regular encounters.

- Boss battle decks (Campaign/Story Mode):
  - Boss encounters use an **explicit enemy deck** for the match.
  - The enemy deck always includes the **act boss card** (a very strong unit named after the boss encounter title).
  - Current act boss cards:
    - Act 1: `General Beaulieu`
    - Act 2: `Murad Bey`
    - Act 3: `Coalition Forces`

- Act transitions (Campaign/Story Mode):
  - When completing an act and advancing to the next one:
    - The campaign **carries over** the player's cards, relics, consumables/items, and Home Town buildings.
    - All fallen cards are **revived** (moved back into the deck and healed).
    - Player base HP is restored to **full**.
    - The act's Home Town location + end node are updated to match the new theater (affects distance-based supply and terrain seeding).

- Shop encounters can offer **repairs** for previously destroyed campaign deck cards (for a gold cost).
- After an encounter completes, the player can optionally visit the Home Town before selecting the next destination.
- Home Town UI can display distance from town and a per-building supply-time breakdown.
- In Story Mode, the encounter location can be used to generate deterministic board terrains for the enemy base and middle row.
- Some Story Mode battles can be **conquerable cities**. Winning a conquerable city can create a temporary **Defense** encounter option.
- Defense encounters grant a temporary **+1 damage and +1 HP** to all player cards for that match.
- Campaign tracks the player's travel history and can render the traveled route on the real map.
- After encounters, Story Mode can show a short blocking story/dispatch dialog generated from encounter type/title and current travel location.
- Home Town building deliveries can be auto-collected when they become ready (based on encounter count + distance penalty), while still showing delivery dialogs.
- Home Town can offer a paid action to hurry logistics:
  - **Hurry Supply** costs **100 gold**.
  - It reduces all in-flight supply deliveries to arrive in **1 encounter**.
  - It also reduces any building cooldowns (without an in-flight delivery) to be ready in **1 encounter**.

**Implemented campaign bonuses:**
- **Gold per battle bonus**: `CampaignState.goldPerBattleBonus` (e.g. `relic_gold_purse` => +10 gold per battle reward).
- **Global damage bonus**: `CampaignState.globalDamageBonus` (e.g. `relic_morale` => +1 damage).
  - This is passed into `TestMatchScreen` as `playerDamageBonus`.
  - `playerDamageBonus` is applied by increasing `GameCard.damage` for every card in the player's deck for that match.
  - This does **not** change the core combat rules; it is a pre-match deck stat modifier used by campaign mode.

---

### 1.5 Medic Action (TYC3)

- Medics are units with a `medic_X` ability.
- Healing is an **action** that spends AP (uses the same AP cost as attack).
- **Play-to-Heal special case:**
  - If a Medic is played from hand directly onto the player's **base tile** and that tile contains an **injured friendly unit**, the Medic:
    - does **not** pay the placement AP cost
    - immediately heals **one** injured friendly unit on that same tile
    - spends **only** the heal AP cost
  - Medics do **not** heal cards in hand.

**Campaign inventory & activation:**
- Campaign tracks owned relics and an `activeRelics` subset. Only **active** relics apply their bonuses.
- Campaign also tracks consumables as counts (inventory vs equipped/active).
- Consumables are applied when used from the campaign inventory UI (not automatically on purchase).

---

### 1.5 Lanes & Tiles (`Lane`, `Tile`, `GameBoard`)

**GameBoard**
- 3×3 grid of tiles.
- Rows: 0 = opponent base, 1 = middle, 2 = player base.
- Columns: 0 = west, 1 = center, 2 = east.

**Tile**
- Each tile has:
  - `row`, `col` (position).
  - `terrain` (woods, lake, desert, marsh).
  - `owner` (player or opponent - only middle tiles can change ownership).
  - `cards` (list of visible cards on this tile).
  - `hiddenSpies` (list of Spy cards on this tile; hidden from opponent UI).
  - `trap` (optional hidden `TileTrap` state; does not occupy card slots).
  - `ignitedUntilTurn` (optional int; if set and >= current turn, the tile is ignited).

**Lane**
- `LanePosition` enum: `west`, `center`, `east`.
- `Zone` enum: `playerBase`, `middle`, `enemyBase`.
- Fields:
  - `position` (lane id).
  - `currentZone` (the front line - **where combat happens** for this lane).
  - `playerCards`, `opponentCards` (PositionalCards each - holds base and middle cards).

**Zone & Combat Location:**
- The **zone represents where combat happens** (the front line).
- Players can **only stage cards at their own base** (not at enemy base).
- Combat happens **at the zone position**:
  - Zone at `middle` → combat at middle tile.
  - Zone at `enemyBase` → combat at enemy base tile.
  - Zone at `playerBase` → combat at player base tile.
- Cards from both sides **advance toward the zone** to fight.

**Terrain Attunement Buff:**
- Each tile has a terrain type (woods, lake, desert, marsh).
- When a card's `element` matches the tile's `terrain`, the card gets **+1 damage**.
- This applies to **ANY tile** (base or middle), not just bases.
- Example: A "woods" element card fighting on a "woods" terrain tile gets +1 damage.

**Tile Card Limits:**
- Max 2 cards per tile per side.
- Cards are placed on tiles, not in stacks.

**Tile Hazards (Implemented):**
- **Traps/Mines**: A trap can exist on a tile as hidden state (`Tile.trap`). When an enemy unit enters the tile, the trap triggers, deals damage, and is consumed.
- **Burning Terrain (Woods/Forest)**: Burning only triggers on `Woods`/`Forest` tiles that are currently **ignited** (`ignitedUntilTurn >= current turn`). On entry, the unit takes 1 damage and is knocked back to the tile it came from if possible.
- **Marsh AP Drain (Implemented)**: After a unit enters a `marsh` tile (including forced movement such as knockback/push), its `currentAP` is set to `0`.

**Spy (Implemented):**
- Spy units are stored on tiles as `Tile.hiddenSpies` (not in `Tile.cards`).
- **Undetectable**: Spy is always invisible to the opponent in the UI (except its gravestone/RIP when it dies). Enemies cannot see the spy unless they have a "watcher" ability.
- **Cannot attack**: Spy cannot perform normal attacks. It can only move and assassinate.
- **Cannot be attacked directly**: Spy is excluded from direct attack targeting.
  - It can still die to non-targeted effects such as traps, burning, cleave, etc.
- **Co-existence**: Spy may move onto tiles that already contain enemy units (the opponent still sees their own units normally).
- **Enemy base entry trigger (automatic)**: When a Spy enters the enemy base tile:
  - If the enemy base tile has 1–2 enemy units, Spy kills one (first).
  - Otherwise, Spy deals 1 damage to the enemy base.
  - Then Spy always self-destructs.
- **Assassination dialog**: When spy assassinates, a dialog is shown to both players indicating the spy's action.

**Watcher (Implemented - core + UI):**
- A unit with `watcher` reveals hidden information on tiles within **watch distance 1** relative to the Watcher's owner direction.
- Tiles revealed (relative to viewer):
  - same tile
  - left
  - right
  - forward
- When a tile is revealed by watcher:
  - enemy `Tile.hiddenSpies` on that tile become targetable by any friendly unit.
  - the UI renders those spies as full enemy cards on that tile.
  - `conceal_back` is treated as not applying for that tile.

**Push Back (Implemented - core):**
- Trigger: on a normal attack action (card attacks card) by a unit with `push_back`.
- Effect: pushes enemy units on the attacked tile 1 tile backward (relative to the attacker’s owner direction).
- Forced-movement entry effects apply (trap, spy base entry, burning knockback, fear, marsh AP drain), and visibility/relic pickup update after landing.

**Glue (Implemented - core):**
- While a unit with `glue` is present, enemy units in the tile directly in front of it (same column, one tile forward relative to the glue owner) cannot intentionally move.
- Forced movement (trap/burning knockback/push) overrides glue.
- Effect ends immediately if the glue unit moves away or dies.

**Silence (Implemented - core):**
- While a unit with `silence` is present, enemy units in the tile directly in front of it cannot attack.
- Effect ends immediately if the silencing unit moves away or dies.

**Paralyze (Implemented - core):**
- While a unit with `paralyze` is present, enemy units in the tile directly in front of it cannot move or attack.
- Effect ends immediately if the paralyzing unit moves away or dies.

**Barrier (Implemented - core):**
- A unit with `barrier` negates the next incoming damage completely (no HP reduction).
- It is consumed once per match per unit.
- Requires persistent state for online sync:
  - `GameCard.barrierUsed` (bool)

**Fear (Implemented - core):**
- Passive ability.
- Trigger: when an enemy unit enters the tile directly in front of a `fear` unit (relative to the fear unit’s owner direction).
- Effect: that enemy unit’s `currentAP` is set to `0`.
- Triggers once per enemy unit per fear-card (deterministic for online sync):
  - `GameCard.fearSeenEnemyIds` (set of enemy card IDs that already triggered)

**Terrain Affinity (Implemented - core):**
- Active while the unit is standing on a tile.
- Lake: on arrival, grants +1 AP once per tile per turn (can temporarily exceed max AP).
- Marsh: while on the tile, grants +5 HP (added on entry, removed on exit).
- Desert: while on the tile, the unit becomes `ranged` (no retaliation).
- Woods/Forest: while on the tile, the unit gains +3 damage.

**Mega Taunt (Implemented - core):**
- Trigger: when an enemy performs a base attack.
- Effect: if the defending side has an adjacent base-tile unit with `mega_taunt`, it intercepts the base damage.
- Selection: highest current HP interceptor; ties are deterministic.

**Tall (Implemented - core):**
- Passive visibility.
- Units with `tall` grant fog-of-war visibility within Manhattan distance 1.

**Lane winner:**
- Determined by which side has surviving cards after combat.

**Zone advancement:**
- `advanceZone(bool playerWon)`:
  - If `playerWon == true`:
    - `playerBase` → `middle`.
    - `middle` → `enemyBase`.
    - `enemyBase` → returns `true` (already at enemy base, crystal damage applied).
  - If `playerWon == false` (opponent wins): mirrored logic toward `playerBase`.
  - Return value = **did victor win while already at enemy base?**

**Retreat after crystal damage:**
- `retreatZone(bool playerAttacking)`:
  - After dealing crystal damage, survivors **retreat to middle**.
  - This creates a push-pull dynamic - you cannot hold enemy base permanently.

Note: Lane `reset()` clears cards but **does not reset `currentZone`**.

---

### 1.5 MatchState (`MatchState`)

- Fields:
  - `player`, `opponent` (Player).
  - `lanes` = 3 `Lane`s.
  - `currentPhase` (enum `MatchPhase`):
    - `setup`, `turnPhase`, `combatPhase`, `drawPhase`, `gameOver`.
  - `turnNumber` (int starting at 1).
  - `winnerId` (nullable), plus `winner` getter.
  - `playerSubmitted`, `opponentSubmitted` (bool).

- Methods:
  - `getLane(LanePosition)` → lane lookup.
  - `isGameOver` → `currentPhase == MatchPhase.gameOver`.
  - `bothPlayersSubmitted` → both flags true.
  - `resetSubmissions()` after each full round.
  - `endMatch(String winnerPlayerId)`.
  - `checkGameOver()` → sets winner if any `isDefeated`.

---

## 2. Match Flow Logic (`MatchManager`)

### 2.1 Match Start

`startMatch(...)` performs:
1. Instantiate `Player` objects for both sides (including `attunedElement` if used).
2. `deck.shuffle()` for each.
3. Create `MatchState` with:
   - Phase = `setup`.
   - 3 `Lane`s with `currentZone = Zone.middle` by default.
4. Draw initial hands:
   - `player.drawInitialHand()`.
   - `opponent.drawInitialHand()`.
5. Set:
   - `turnNumber = 1`.
   - `currentPhase = MatchPhase.turnPhase`.

---

### 2.2 Turn Phase – Player & Opponent Submission

**Player submission** `submitPlayerMoves(Map<LanePosition, List<GameCard>> placements)`:
- Guard: do nothing if no active match or already submitted.
- For each `lanePosition → cards[]`:
  - Get `Lane` via `getLane()`.
  - For each `card`:
    - If `player.playCard(card)` succeeds (card was in hand):
      - Place card on the appropriate tile in the lane.
- Set `playerSubmitted = true`.
- If `bothPlayersSubmitted` → call `_resolveCombat()`.

**AI / opponent submission** `submitOpponentMoves(...)` and `submitOnlineOpponentMoves(...)`:
- Similar logic for opponent cards.
- Set `opponentSubmitted = true` and resolve combat when both have submitted.

---

### 2.3 Combat Resolution Entry Point

`_resolveCombat()`:
1. Set phase to `combatPhase`.
2. Reset `skipAllTicks` and clear previous combat logs.
3. Log a header (`TURN X - COMBAT RESOLUTION`).
4. For each lane in `match.lanes`:
   - If `lane.hasActiveCards` → call `_resolveLaneAnimated(lane)`.
5. After all lanes:
   - Print combat log (for debug / simulations).
   - Call `_checkCrystalDamage()` to handle lane advancement & crystal HP.
   - Delay briefly (unless `fastMode`) and then check `checkGameOver()`.
6. If still not game over → call `_startNextTurn()`.

---

## 3. Tick-by-Tick Combat (`CombatResolver`)

### 3.1 Context Setup

Before resolving a lane, `_resolveLaneAnimated` calls:

```dart
_combatResolver.setLaneContext(
  zone: lane.currentZone,
  tileTerrain: tile.terrain,  // Terrain of the current combat tile
  playerDamageBoost: playerDamageBoost,
);
```

This allows the damage calculator to know:
- **Which zone** we’re in (player base, middle, enemy base)
- **Tile terrain** for terrain attunement buffs
- **Hero damage boost** if active

---

### 3.2 Tick Loop

`resolveLane(Lane lane, {String? customLaneName})` (non-animated) and `processTickInLane` share the same core tick logic:

For `tick` from 1 to 5:
1. Determine active cards:
   - `playerCard = lane.playerStack.activeCard`.
   - `opponentCard = lane.opponentStack.activeCard`.
2. Log tick status.
3. Determine whether each acts this tick:
   - `playerActs = playerCard != null && _shouldActOnTick(playerCard.tick, tick)`.
   - `opponentActs = opponentCard != null && _shouldActOnTick(opponentCard.tick, tick)`.
4. If neither acts → log “No Actions”, continue.
5. Snapshot alive states **before** any attacks:
   - `playerAliveBeforeTick`, `opponentAliveBeforeTick`.
6. **Simultaneous attack rule:**
   - If `playerActs` and both were alive before tick → call `_performAttack(player → opponent, checkAliveBeforeAttack: false)`.
   - If `opponentActs` and both were alive before tick → call `_performAttack(opponent → player, checkAliveBeforeAttack: false)`.
   - Alive checks are intentionally skipped during these simultaneous calls so both attacks are guaranteed to fire if scheduled.
7. In animated path, after each tick:
   - Wait for user input or auto-progress.
   - Call `cleanup()` on both stacks.
   - Break if one stack becomes empty.

`_shouldActOnTick(cardTick, currentTick)` implements the timing:
- If `cardTick == 1` → true for all ticks.
- If `cardTick == 2` → true on even ticks (2, 4).
- Else → true only when `cardTick == currentTick`.

---

### 3.3 Damage Calculation

`_calculateElementalDamage(GameCard attacker, GameCard target)`:
- Starts from `attacker.damage`.
- **No card-vs-card terrain matchup is applied** (no rock-paper-scissors).
- Round/clamp logic is effectively a no-op at present; damage is the raw stat before other modifiers.

`_performAttack(...)` then layers additional modifiers:

1. **Zone-Attunement Buff (terrain + base zone)**
   - Each lane knows the **current zone** (`Zone.playerBase`, `Zone.middle`, `Zone.enemyBase`) and the attuned terrain for each base (`playerBaseElement`, `opponentBaseElement`).
   - Whenever combat happens in a **base zone** (either `Zone.playerBase` or `Zone.enemyBase`):
     - If the **attacker’s terrain tag** matches that base’s attuned terrain:
       - `damage += 1` (+1 terrain-attuned base buff in that base).

2. **Fury**
   - If `attacker.abilities` contains `fury_X` → `damage += X` (+X fury).

3. **Lane-wide Buffs**
   - `inspire_X`: +X damage to ALL allies in this lane.
   - `fortify_X`: +X shield to ALL allies in this lane.

4. **Tile-local Buffs**
   - `command_X`: +2X damage to other friendly units on the SAME TILE (not lane-wide).

4. **Shield** `shield_X`
   - If `target.abilities` contains `shield_X` → reduce damage by X (min 1).

5. **Apply damage**
   - Store `hpBefore`.
   - `targetDied = target.takeDamage(damage)`.
   - Store `hpAfter`.
   - Log attack result; mark as important in log if target died.

---

### 3.4 Lane Battle End

When either side has no surviving cards or ticks 1–5 finish:
- `lane.playerWon` is evaluated.
- `_logBattleEnd` writes a final message:
  - Victory / Defeat / Draw for that lane.

The animated path then waits briefly before moving to next lane.

---

## 4. Tile Ownership & Zone Advancement

### 4.1 Board Layout (3×3 Grid)

```
Row 0: [W Enemy Base] [C Enemy Base] [E Enemy Base]  ← Opponent's base (ALWAYS opponent-owned)
Row 1: [W Middle]     [C Middle]     [E Middle]      ← Contested (can be captured)
Row 2: [W Your Base]  [C Your Base]  [E Your Base]   ← Player's base (ALWAYS player-owned)
```

**Ownership Rules:**
- **Base tiles (row 0 & row 2)**: NEVER change ownership. Each player always controls their 3 base tiles.
- **Middle tiles (row 1)**: Can be captured by winning combat there.

### 4.2 Card Placement Rules

- Max **2 cards per tile** you control
- **Staging Phase**: Place cards only on tiles you own
  - Turn 1: Only base tiles available (row 2 for player)
  - Later turns: Base tiles + any captured middle tiles

### 4.3 Advancement Logic (Per Lane)

**During Battle Phase:**
1. Cards attempt to advance **1 tile toward enemy** each turn
   - Player cards: Row 2 → Row 1 → Row 0
   - Opponent cards: Row 0 → Row 1 → Row 2
2. Cards **STOP when they meet enemies** on a tile
3. Combat resolves at that tile
4. Must **destroy ALL enemy cards** on a tile to "clear the way"

**After Combat:**
| Combat Result | What Happens |
|---------------|--------------|
| Did NOT clear enemies | Stay at current tile |
| Cleared enemies at middle | Advance to enemy base (row 0/2) |
| Cleared enemies at enemy base | **Hit crystal**, then return to middle |
| At middle, enemy base is EMPTY | **Hit crystal** (uncontested), stay at middle |

### 4.4 Crystal Damage

Crystal damage occurs when:
- Your cards are at the **middle tile** AND
- Enemy has **no defenders** at their base tile in that lane

This represents your cards "hitting" the enemy base. After dealing damage, cards remain at middle (they don't occupy enemy base).

**Why cards return to middle after crystal hit:**
- Enemy base tiles are NEVER captured
- Enemy must always have their base tiles available for staging
- Your cards "raid" the base, deal damage, and fall back

### 4.5 Implementation (`_checkCrystalDamage()`)

For each lane:
1. Read `playerWon = lane.playerWon`.
2. If `playerWon == true` (player wins):
   - `reachedBase = lane.advanceZone(true)`.
   - Update middle tile ownership if applicable.
   - If `reachedBase`:
     - Compute `totalDamage` = sum of `damage` on surviving cards.
     - Call `opponent.takeCrystalDamage(totalDamage)`.
     - `lane.retreatZone(true)` → survivors return to middle.
   - Award gold (400).
3. If `playerWon == false` (opponent wins):
   - Mirror logic toward player base.
4. If `playerWon == null`: no advancement (draw).

This function is called **after** combat logs and per-lane tick resolution.

---

## 5. Turn Advancement

`_startNextTurn()`:
1. Guard: if no active match, return.
2. Set `currentPhase = MatchPhase.drawPhase`.
3. Draw cards:
   - `player.drawCards()` (default 2).
   - `opponent.drawCards()`.
4. **Do not reset lanes**:
   - Comments emphasize: "surviving cards persist across turns"; zones and surviving cards remain.
5. `resetSubmissions()` on MatchState.
6. Increment `turnNumber` and set `currentPhase = MatchPhase.turnPhase`.

Result: match progresses turn by turn with **persistent board state** and moving zones.

---

## 6. AI & Simulation

### 6.1 Simple AI (`SimpleAI`)

`generateMoves(Player aiPlayer)`:
- If hand empty → return empty placements.
- Start with a list of lanes: `[west, center, east]`, shuffle.
- For each lane:
  - Randomly pick `cardsToPlay` in `0..2`.
  - For each card to play:
    - Pick a random card from hand.
    - Add it to that lane’s card list.
- Return `Map<LanePosition, List<GameCard>>`.

This is intentionally dumb; it exists to stress test decks and logic.

---

### 6.2 Match Simulation (`match_simulator.dart`)

- `simulateSingleMatch`:
  - Creates a new `MatchManager`.
  - Sets `autoProgress = true`, `fastMode = true` (no UI delays).
  - Uses cloned decks for both sides.
  - Starts match with different `attunedElement` values (e.g. player Water, opponent Fire).
  - Instantiates two `SimpleAI` instances.
  - Loops until `match.isGameOver` or `turnNumber > maxTurns` (e.g. 40):
    - Fetch AI moves for both players.
    - Call `submitPlayerMoves` and `submitOpponentMoves`.
  - At the end, derive `winner` label (`deck1`, `deck2`, or `draw`) and record stats + `fullLog`.

- `simulateManyGames`:
  - Repeats `simulateSingleMatch` `count` times.
  - Aggregates results (wins, draws, average turns).

This is used for **balance testing and regression checks**.

---

## 7. Designed but Not Fully Implemented (Hooks / TODOs)

This section is meant as a **bridge** between `GAME_TODO.md` and the current code.

- **Gold system (fine-grained):**
  - Current code already awards **400 gold** on lane capture.
  - Still missing:
    - Per-card destruction rewards (50–200 gold).
    - Win streak bonuses.
    - 25% carryover to post-match shop.

- **Abilities not yet fully implemented in combat:**
  - `cleave` - hits all enemies (not implemented)
  - `thorns_X` - reflect damage (not implemented)
  - `regen_X` - heal per tick (not implemented)
  - `heal_ally_X` - heal allies (not implemented)
  - `regenerate` - continuous heal (not implemented)

- **Character families & ultimates:**
  - Planned: tracking variations per family, triggering “Ultimate” when 3 variations are played.
  - Implementation hooks would sit:
    - In card-play logic (when playing from hand).
    - In match state or a dedicated `UltimateTracker`.

- **3 Ages System (multi-deck progression):**
  - Planned: each player has **3 separate decks** representing **Age 1 (early)**, **Age 2 (mid)**, **Age 3 (late)**.
  - The active deck is determined by the **current turn number**:
    - Age 1 for early turns, then automatic switch to Age 2, then Age 3.
  - Likely implementation points:
    - A small "Age controller" that, on `_startNextTurn`, checks `turnNumber` and swaps which deck supplies draws.
    - UI/state hooks to expose the **current age/deck** for visualization and logging.
  - This has **no code yet**; it’s purely a design hook to be implemented later.

- **Online multiplayer:**
  - `online_match_screen.dart` and Firebase sync services coordinate this.
  - Match logic must be **deterministic** (given same inputs, same outputs).
  - Likely server/Cloud Functions to verify combats.

---

## 8. Usage Notes for Future Development

- When adding new abilities:
  - Prefer string tags in `GameCard.abilities` with **clear, composable semantics**.
  - Centralize their effects in `CombatResolver._performAttack` (damage) or related helpers.

- When changing lane/win rules:
  - Update `Lane.playerWon`, `Lane.advanceZone`, and `_checkCrystalDamage()` together.

- When expanding the **terrain/attunement system**:
  - Consider whether to introduce card-vs-card terrain relationships again or keep it purely zone-based.
  - Keep any matrices small and legible to simplify reasoning and balancing.

- When wiring Heroes or Ultimates:
  - Keep **core combat deterministic**; abilities should modify inputs but not add non-deterministic randomness mid-resolution.

This spec should evolve with the code. Whenever major gameplay logic changes, update this file together with relevant models/services.

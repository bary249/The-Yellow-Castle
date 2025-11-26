# Land of Clans & Wanderers – Game Logic Spec

This document captures the **implemented and intended logic** of the game, mapped to current code where possible.

> **Terminology note:**
> The gameplay and UI refer to stack positions as **Front**/**Back**.
> The underlying code still uses `topCard`/`bottomCard` for those positions.

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
- `abilities` (list of string tags):
  - Examples: `fury_2`, `shield_2`, `stack_buff_damage_2`, `stack_debuff_enemy_damage_2`.
- `isAlive` (derived from `currentHealth > 0`).

**Important behavior:**
- `takeDamage(int amount)` reduces `currentHealth` and returns whether the card died.

---

### 1.2 Deck (`Deck`)

- Holds a fixed list of `GameCard` instances (design target: **25 cards**).
- Provides:
  - `shuffle()` at match start.
  - `drawCards(count)` to draw a batch of cards.
  - `remainingCards` for UI.
- No **mid-match reshuffle**: once deck is empty, no more draws.

---

### 1.3 Player (`Player`)

**Fields (conceptual):**
- `id`, `name`, `isHuman`.
- `deck` (Deck).
- `hand` (`List<GameCard>`).
- `crystalHP` (int, default e.g. 100).
- `gold` (int; match currency, partially used / TBD).
- `attunedElement` (optional element for base/crystal attunement).

**Important flags/methods:**
- `isDefeated` → `crystalHP <= 0`.
- `isHandFull` → hand >= `maxHandSize` (design ~8).
- `drawInitialHand()` → draw 6.
- `drawCards({count = 2})` per new turn.
- `playCard(GameCard)` → removes card from hand if present.
- `takeCrystalDamage(int)` → reduces `crystalHP` (floor at 0).
- `earnGold(int)` → adds to `gold` (economy hooks).

---

### 1.4 Lanes & CardStacks (`Lane`, `CardStack`)

**Lane**
- `LanePosition` enum: `left`, `center`, `right`.
- `Zone` enum: `playerBase`, `middle`, `enemyBase`.
- Fields:
  - `position` (lane id).
  - `currentZone` (where the battle is happening for this lane this round).
  - `playerStack`, `opponentStack` (CardStack each).

**CardStack**
- Conceptually holds up to **2 cards** per side:
  - **Front card** (closest to the enemy, active first).
  - **Back card** (behind the front card, comes in when front dies).
- In code these are currently named:
  - `topCard` (used as the **front** card).
  - `bottomCard` (used as the **back** card).
  - `isPlayerOwned` (bool).

**Key methods:**
- `isEmpty` → both front/back slots null.
- `isFull` → both front/back slots non-null.
- `activeCard`:
  - Returns `topCard` (front card) if it exists and `isAlive`.
  - Else `bottomCard` (back card) if exists and `isAlive`.
  - Else `null`.
- `addCard(GameCard card, {bool asTopCard = true})`:
  - If stack empty → new card becomes `topCard` (front).
  - If only `topCard` (front) present:
    - `asTopCard == true` → move existing `topCard` to `bottomCard` (back), new card becomes `topCard` (front).
    - `asTopCard == false` → new card becomes `bottomCard` (back).
  - If both occupied → returns `false`.
- `cleanup()` after tick/combat:
  - Clears dead `bottomCard` (back card).
  - If `topCard` (front) is dead → promotes `bottomCard` (back) to `topCard` (front), nulls `bottomCard`.
  - If new `topCard` (front) still dead → clears it.

**Lane winner:**
- Getter `playerWon`:
  - `true` if `playerStack.activeCard != null` and `opponentStack.activeCard == null`.
  - `false` if reverse.
  - `null` otherwise (tie / both alive / both dead).

**Zone advancement:**
- `advanceZone(bool playerWon)`:
  - If `playerWon == true`:
    - `playerBase` → `middle`.
    - `middle` → `enemyBase`.
    - `enemyBase` → returns `true` (reached enemy base, crystal damage should be applied).
  - If `playerWon == false` (opponent wins): mirrored logic toward `playerBase`.
  - Return value = **did victor reach enemy base this advancement step?**

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
      - Check `hasSurvivors = lane.playerStack.topCard != null`.
      - **Rule:** if there are survivors already in this lane stack, **fresh cards go to bottom**.
      - Call `lane.playerStack.addCard(card, asTopCard: !hasSurvivors)`.
- Set `playerSubmitted = true`.
- If `bothPlayersSubmitted` → call `_resolveCombat()`.

**AI / opponent submission** `submitOpponentMoves(...)` and `submitOnlineOpponentMoves(...)`:
- Similar logic but:
  - AI version checks `opponent.playCard(card)`.
  - Online version trusts cards (assumes already validated via network) and calls `lane.opponentStack.addCard(card)` directly.
- Set `opponentSubmitted = true` and resolve combat when both have submitted.

**Important rule enforced here:**
- **Surviving cards stay on top; new cards naturally stack underneath** when there are survivors.

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
  playerBaseElement: currentMatch.player.attunedElement,
  opponentBaseElement: currentMatch.opponent.attunedElement,
);
```

This allows the damage calculator to know **which zone** we’re in and **which base elements** to compare.

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
   - If `attacker.abilities` contains `fury_2` → `damage += 2` (+2 fury).

3. **Stack Buff** `stack_buff_damage_2`
   - Look at `topCard` (front) and `bottomCard` (back) of **attackerStack** (excluding attacker itself).
   - If any has `stack_buff_damage_2` → `damage += 2` (+2 stack buff).

4. **Stack Debuff** `stack_debuff_enemy_damage_2`
   - Look at `topCard` (front) / `bottomCard` (back) of **targetStack**.
   - If any has this ability → reduce damage by 2 (min 1) (−2 stack debuff).

5. **Shield** `shield_2`
   - If `target.abilities` contains `shield_2` → reduce damage by 2 (min 1) (−2 shield).

6. **Apply damage & overflow**
   - Store `hpBefore`.
   - `targetDied = target.takeDamage(damage)`.
   - Store `hpAfter`.
   - Log attack result; mark as important in log if target died.

7. **Overflow damage**
   - If `targetDied`:
     - Compute `overflowDamage = -target.currentHealth` (excess into negative).
     - If `overflowDamage > 0` and `targetStack.bottomCard` (back card) exists and is alive:
       - Call `_applyOverflowDamage(overflowDamage, targetStack, tick, laneName)`.

`_applyOverflowDamage` then:
- Applies full `damage` to `stack.bottomCard` (back card).
- Logs overflow event.

---

### 3.4 Lane Battle End

When either stack becomes empty or ticks 1–5 finish:
- `lane.playerWon` is evaluated.
- `_logBattleEnd` writes a final message:
  - Victory / Defeat / Draw for that lane.

The animated path then waits briefly before moving to next lane.

---

### 3.5 Post-Combat Fatigue

After all lanes have resolved, crystal damage has been applied, and zones advanced, a **fatigue pass** is applied:

- For every lane, for both `playerStack` and `opponentStack`:
  - For each card in `aliveCards`:
    - Reduce `currentHealth` by 2, but never below 1.
- Fatigue **cannot kill** a card; it only softens surviving units for future turns.

This makes long-lived units gradually wear down over multiple rounds, even if they are winning consistently.

---

## 4. Zone Advancement & Crystal Damage

`_checkCrystalDamage()` in `MatchManager`:

For each lane:
1. Read `playerWon = lane.playerWon`.
2. If `playerWon == true` (player side wins lane):
   - Log.
   - `reachedBase = lane.advanceZone(true)`.
   - Log new `zoneDisplay`.
   - If `reachedBase`:
     - Compute `totalDamage` = sum of `damage` on `lane.playerStack.aliveCards`.
     - Call `opponent.takeCrystalDamage(totalDamage)`.
     - Log crystal damage.
   - Award gold → `player.earnGold(400)` (tier capture reward).
3. If `playerWon == false` (opponent wins lane):
   - Mirror logic, using `lane.advanceZone(false)` and `player.takeCrystalDamage(totalDamage)`.
   - Award gold to opponent.
4. If `playerWon == null`: no advancement, log draw.

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
- Start with a list of lanes: `[left, center, right]`, shuffle.
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

- **Hero system:**
  - Heroes per deck, with single-use or limited-use abilities.
  - Not yet integrated into `MatchManager` or `CombatResolver`.
  - Likely entry points:
    - Additional modifiers in damage calculation.
    - Temporary buffs/debuffs on lanes or cards.

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

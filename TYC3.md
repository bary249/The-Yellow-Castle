# Land of Clans & Wanderers – Turn-Based AP System Redesign (TYC 3)

> **Status**: PLANNING
> **Created**: December 3, 2025
> **Impact**: MAJOR - Core gameplay loop overhaul

---

## 1. Overview

This document outlines a fundamental redesign of the game from **simultaneous tick-based combat** to a **turn-based Action Point (AP) system** with player-controlled targeting.

### Current System (Being Replaced)
- Both players submit moves simultaneously
- 8-second timer for submissions
- Combat resolves via 5-tick system (cards auto-attack based on tick value)
- No player control over which enemy to attack

### New System (Turn-Based AP)
- Players take **alternating turns** (30 seconds each)
- Random first player selection
- Cards have **Action Points (AP)** for movement and attacks
- Players **manually choose** which enemy card/base to attack
- **Retaliation** system for combat

---

## 2. Turn Structure

### 2.1 Turn Flow
1. **Random first player** at game start
2. Active player has **30 seconds** to:
   - Place cards (up to 2 per turn, 1 on first turn for first player)
   - Move cards (costs 1 AP per move)
   - Attack with cards (costs card's attack AP cost)
3. Player can **end turn early** by pressing "End Turn" button
4. Turn passes to opponent

### 2.2 First Turn Restriction
- **First player** can only place **1 card** on their first turn
- After that, both players can place **up to 2 cards per turn**

---

## 3. Action Point (AP) System

### 3.1 AP Basics
- Each card has **current AP** and **max AP** (displayed top-right of card)
- Most cards: **1 max AP**, gain **1 AP per turn**
- Fast units (e.g., Horseman): **2 max AP**, gain **2 AP per turn**
- Future: Some cards may have **3+ max AP**

### 3.2 AP Costs
| Action | AP Cost |
|--------|---------|
| **Move** (1 tile) | 1 AP |
| **Attack** | Card's attack cost (varies, shown top-left) |

### 3.3 AP Regeneration
- Cards gain AP at the **start of their owner's turn**
- AP cannot exceed max AP

---

## 4. Card Display (New Layout)

```
┌─────────────────┐
│ [2]         1/2 │  ← Top-left: Attack AP cost | Top-right: Current/Max AP
│                 │
│   [Card Art]    │
│                 │
│ [5]         [8] │  ← Bottom-left: Damage | Bottom-right: HP
│   [Abilities]   │
└─────────────────┘
```

### 4.1 Card Parameters
- **Top-left**: Attack AP cost (how much AP to attack)
- **Top-right**: Current AP / Max AP
- **Bottom-left**: Damage value
- **Bottom-right**: HP (current/max)
- **Abilities**: Special keywords (Guard, Ranged, etc.)

---

## 5. Board & Tiles

### 5.1 Board Layout (3×3 Grid)
```
Row 0: [Enemy Base] [Enemy Base] [Enemy Base]  ← Opponent's base (3 tiles)
Row 1: [Middle]     [Middle]     [Middle]      ← Contested zone
Row 2: [Your Base]  [Your Base]  [Your Base]   ← Player's base (3 tiles)
```

### 5.2 Tile Capacity
- **Maximum 4 cards per tile** (2 rows × 2 columns)
- Layout per tile:
  ```
  [Card1] [Card2]  ← Front row
  [Card3] [Card4]  ← Back row
  ```

### 5.3 Tile Ownership
- **Base tiles**: Always owned by respective player (never captured)
- **Middle tiles**: Can be contested by both players' cards

---

## 6. Base System

### 6.1 Base Properties
- Each player has a **Base** (the 3 tiles in their back row)
- Base has **HP** (e.g., 100 HP)
- Base has **no damage** (cannot attack)
- Base **can be attacked** like a card

### 6.2 Win Condition
- **Deplete enemy base HP to 0** = Victory

---

## 7. Combat & Retaliation

### 7.1 Attack Flow
1. Player selects attacking card
2. Player selects target (enemy card OR enemy base)
3. Attacking card spends AP equal to its attack cost
4. Attacking card deals its **damage** to target
5. **Retaliation** occurs (if applicable)

### 7.2 Retaliation Rules
- When a card is attacked, it **retaliates** by dealing its damage back to the attacker
- Retaliation is **automatic** and **free** (no AP cost)
- Retaliation happens **even if the defender dies** from the attack

### 7.3 Retaliation Exceptions
- **Ranged** ability: Attacker does NOT receive retaliation damage
- **Guard** ability: Must be attacked before base (see below)
- Other abilities may modify retaliation (future)

### 7.4 Destroying Cards & Position
- When you destroy an enemy card in the **middle zone**, your attacking card **takes its place**
- This only applies to middle tiles (not base tiles)
- No enemy cards can be in player base, no player cards in enemy base (permanently)

---

## 8. Special Abilities

### 8.1 Core Abilities (Turn-Based)
| Ability | Effect |
|---------|--------|
| **Guard** | Enemy cards must attack this card before attacking the base |
| **Ranged** | This card does not receive retaliation damage |
| **Long_Range** | Can attack targets 2 tiles away (e.g., base-to-base). Cannons, Artillery. |
| **Fury_X** | +X damage when attacking |
| **Shield_X** | Reduces incoming damage by X |
| **Regen_X** | Heals X HP at start of owner's turn |

### 8.2 Range & Attack Distance
- **Normal attack range**: 1 tile (can only attack adjacent tiles)
- **Long_Range**: 2 tiles (can attack from base to enemy base, skipping middle)
- Cards with **Long_Range** (e.g., Cannon, Artillery, Siege Weapons):
  - Can attack enemies 2 tiles away
  - Typically combined with **Ranged** (no retaliation) since target can't reach back
  - Usually **Stationary** (0 movement) to balance the power

### 8.3 Existing Abilities (To Review)
These abilities from the current system need review for turn-based compatibility:
- `cleave` - Attacks hit all enemy cards in lane
- `thorns_X` - Reflects X damage to attackers
- `first_strike` - May need redesign
- `far_attack` - Becomes **Long_Range** ability
- `heal_ally_X` - Heals friendly cards

---

## 9. Card Draw & Hand

### 9.1 Starting Hand
- Each player draws **6 cards** at game start

### 9.2 Card Draw
- Draw **1 card per turn** (at start of turn)
- Hand size limit: TBD (suggest 8-10)

---

## 10. Implementation Phases (Detailed)

### Phase 1: Model Updates (Foundation) ✅ COMPLETE
**Files modified:**
- `lib/models/card.dart` - Added AP fields
- `lib/models/player.dart` - Added base HP
- `lib/models/match_state.dart` - Added turn tracking
- `lib/models/tile.dart` - Updated capacity to 4 cards

**Tasks:**
- [x] Add to `GameCard`: `maxAP`, `currentAP`, `attackAPCost`, `apPerTurn`
- [x] Add to `GameCard`: `attackRange` (1 = normal, 2 = long range)
- [x] Add to `Player`: `baseHP`, `maxBaseHP` (renamed from crystalHP)
- [x] Add to `MatchState`: `activePlayerId`, `turnStartTime`, `isFirstTurn`, `cardsPlayedThisTurn`
- [x] Update `Tile`: change max cards from 2 to 4 (2×2 grid)
- [x] Update `GameCard.copy()`, `toJson()`, `fromJson()` for new fields
- [x] Add `GameCard.regenerateAP()` method
- [x] Add `GameCard.canAttack()`, `GameCard.canMove()` helpers

### Phase 2: Card Library Updates ✅ COMPLETE
**Files modified:**
- `lib/data/card_library.dart` - Added AP values to all cards

**Tasks:**
- [x] Define AP values for each card based on current tick/moveSpeed:
  - Tick 1-2 cards → 2 AP (fast attackers)
  - Tick 3-5 cards → 1 AP (slower, harder hitters)
  - MoveSpeed 2 cards → 2 AP (cavalry/horsemen)
  - MoveSpeed 0 cards → 1 AP but stationary
- [x] Define `attackAPCost` for each card (most = 1, heavy hitters = 2)
- [x] Add `attackRange: 2` to cannons/artillery for long range
- [x] Update ability strings: `ranged` (no retaliation), `guard`, `long_range`

### Phase 3: Turn System Overhaul ✅ COMPLETE
**Files modified:**
- `lib/services/match_manager.dart` - Added TYC3 turn-based methods
- `lib/models/match_state.dart` - Phase enum already updated in Phase 1

**Tasks:**
- [x] Update `MatchPhase` enum: added `playerTurn`, `opponentTurn` (Phase 1)
- [x] Add `startMatchTYC3()` method with random first player
- [x] Implement random first player selection
- [x] Add 30-second turn timer tracking (`turnSecondsRemaining`)
- [x] Implement `endTurnTYC3()` method (switch active player)
- [x] Keep legacy submission logic (deprecated, for backward compat)
- [x] Implement first-turn restriction (1 card only via `maxCardsThisTurn`)
- [x] Add AP regeneration at turn start (`_regenerateAPForActivePlayer`)
- [x] Add `placeCardTYC3()` for card placement
- [x] Add `canMoveCard()` and `moveCardTYC3()` for movement

### Phase 4: Action System (Move & Attack) ✅ COMPLETE
**Files modified:**
- `lib/services/match_manager.dart` - Added TYC3 action methods
- `lib/services/combat_resolver.dart` - Added single-attack resolution

**Tasks:**
- [x] Movement in MatchManager (Phase 3):
  - `moveCardTYC3(card, fromRow, fromCol, toRow, toCol)` - costs 1 AP
  - `canMoveCard()` - validates movement
- [x] Attack in MatchManager:
  - `attackCardTYC3(attacker, target, positions)` - costs attackAPCost
  - `attackBaseTYC3(attacker, position)` - attack enemy base
  - `getValidTargetsTYC3()` - find valid targets
- [x] Card placement (Phase 3):
  - `placeCardTYC3(card, row, col)` - from hand to base tile
- [x] Movement validation:
  - Adjacent tiles only (same lane, row +/- 1)
  - Cannot move to full tiles (4 cards max)
  - Cannot move to enemy base tiles
- [x] Attack validation in CombatResolver:
  - `validateAttackTYC3()` - checks AP, range, guards
  - Range check (1 tile normal, 2 for Long_Range)
  - Guard rule (must attack guards first)
- [x] Single-attack resolution in CombatResolver:
  - `resolveAttackTYC3()` - damage + retaliation
  - `AttackResult` class for results
  - Fury, shield, thorns ability processing

### Phase 5: Retaliation System ✅ COMPLETE (merged into Phase 4)
**Implemented in Phase 4:**

**Tasks:**
- [x] Retaliation in `resolveAttackTYC3()`:
  - Defender deals damage back after being attacked
  - Skip retaliation if defender dies
  - Skip retaliation if attacker has `ranged` ability
  - Thorns damage applied separately
- [x] Base attack in `attackBaseTYC3()`:
  - No retaliation from base
  - Must clear all guards/cards first
  - Game over check after base damage

### Phase 6: UI Overhaul
**Files to modify:**
- `lib/screens/test_match_screen.dart` - Main battle UI

**Tasks:**
- [ ] Add "End Turn" button (prominent, always visible)
- [ ] Add turn indicator (whose turn + 30s countdown)
- [ ] Update card display:
  - Top-left: Attack AP cost
  - Top-right: Current AP / Max AP
  - Bottom-left: Damage
  - Bottom-right: HP
- [ ] Implement card selection UI (tap to select)
- [ ] Implement target selection UI (tap enemy card/base)
- [ ] Implement move destination UI (tap adjacent tile)
- [ ] Add action buttons: "Move", "Attack", "Cancel"
- [ ] Show valid targets/destinations highlighted
- [ ] Remove tick-based combat log, add action log
- [ ] Update tile display for 4-card capacity (2×2 grid)

### Phase 7: AI Updates
**Files to modify:**
- `lib/services/simple_ai.dart` - Rewrite for turn-based

**Tasks:**
- [ ] Rewrite AI to take actions during its turn:
  - Evaluate board state
  - Decide which cards to place (up to 2)
  - Decide which cards to move
  - Decide which cards to attack with
  - Execute actions sequentially
- [ ] Add AI decision logic:
  - Prioritize attacking low-HP enemies
  - Prioritize attacking base when no guards
  - Move cards forward when safe
  - Place cards to defend when threatened

### Phase 8: Simulation Mode Updates
**Files to modify:**
- `lib/simulation/match_simulator.dart` - Update for turn-based
- `bin/simulate_games.dart` - Update CLI

**Tasks:**
- [ ] Update simulator to alternate turns
- [ ] AI plays both sides taking actions
- [ ] Track new metrics (AP usage, attacks per turn, etc.)
- [ ] Ensure deterministic results for testing

### Phase 9: Online Mode Updates
**Files to modify:**
- `lib/services/matchmaking_service.dart`
- `lib/screens/matchmaking_screen.dart`
- Firebase rules if needed

**Tasks:**
- [ ] Update Firebase match document structure:
  - `activePlayerId` - whose turn
  - `turnStartTime` - for timer sync
  - `actions` - list of actions taken this turn
- [ ] Implement real-time action sync
- [ ] Handle turn timeout (auto-end turn)
- [ ] Validate actions server-side (or client-side with verification)

### Phase 10: Testing & Balance
**Tasks:**
- [ ] Run simulation mode with new system
- [ ] Balance AP costs and regeneration rates
- [ ] Balance attack costs vs damage output
- [ ] Test all abilities in new system
- [ ] Test Guard + Ranged + Long_Range interactions
- [ ] Full playtest of all 3 modes

---

## 11. Model Changes Required

### 11.1 GameCard Updates
```dart
class GameCard {
  // Existing fields...
  
  // NEW AP fields
  int maxAP;           // Maximum AP (1-3+)
  int currentAP;       // Current AP available
  int attackAPCost;    // AP cost to attack (1-3)
  int apPerTurn;       // AP gained per turn (usually = maxAP)
  
  // Existing fields to keep
  int damage;          // Damage dealt per attack
  int maxHealth;
  int currentHealth;
  List<String> abilities;
}
```

### 11.2 Player Updates
```dart
class Player {
  // Existing fields...
  
  // NEW Base HP
  int baseHP;          // Base health (e.g., 100)
  int maxBaseHP;
}
```

### 11.3 MatchState Updates
```dart
class MatchState {
  // Existing fields...
  
  // NEW Turn tracking
  String activePlayerId;    // Whose turn it is
  DateTime turnStartTime;   // For 30-second timer
  bool isFirstTurn;         // Track first turn restriction
}
```

### 11.4 Tile Updates
```dart
class Tile {
  // Existing fields...
  
  // UPDATE: Max 4 cards per tile
  List<GameCard> cards;  // Max 4 (2×2 grid)
}
```

---

## 12. UI Changes Required

### 12.1 New UI Elements
- [ ] "End Turn" button (prominent, always visible during your turn)
- [ ] Turn indicator (whose turn + timer countdown)
- [ ] AP display on cards
- [ ] Attack cost display on cards
- [ ] Target selection highlight
- [ ] Retaliation damage preview

### 12.2 Removed UI Elements
- [ ] 8-second simultaneous timer
- [ ] "Submit Moves" button
- [ ] Tick-based combat log (replace with action log)

---

## 13. Questions to Resolve

1. **AP on placement**: Do newly placed cards have 0 AP or start with some AP?
   - Suggestion: Start with 0 AP (can't act until next turn)

2. **Movement direction**: Can cards move sideways (between lanes)?
   - Suggestion: Only forward/backward initially

3. **Multiple attacks**: Can a card with 2+ AP attack multiple times per turn?
   - Suggestion: Yes, if they have enough AP

4. **Base Guard**: Can there be multiple Guard cards? Attack order?
   - Suggestion: Must kill ALL guards before attacking base

5. **Tile capacity**: What happens if a tile is full and a card wants to move there?
   - Suggestion: Cannot move to full tiles

6. **Card placement**: Can you place cards on middle tiles you control?
   - Suggestion: Only on base tiles (keep current rule)

---

## 14. Balance Considerations

### 14.1 AP Economy
- 1 AP cards: Slow but reliable (attack every other turn)
- 2 AP cards: Can attack every turn OR move + attack
- 3 AP cards: Highly mobile, multiple actions per turn

### 14.2 Attack Cost Balance
- 1 AP attack: Standard, can attack every turn with 1 AP card
- 2 AP attack: Powerful but slow, needs 2 AP card to attack every turn
- 3 AP attack: Very powerful, requires high AP card or multi-turn buildup

### 14.3 Retaliation Impact
- Makes attacking risky (you take damage back)
- Ranged becomes very valuable
- Guard becomes essential for base protection
- Encourages strategic target selection

---

## 15. Migration Notes

### From Current System
- **Tick value** → May influence AP or attack cost
- **Move speed** → Influences max AP
- **Damage/HP** → Keep as-is
- **Abilities** → Review each for turn-based compatibility

### Card Library Updates
All cards in `card_library.dart` need:
- `maxAP` assignment
- `attackAPCost` assignment
- `apPerTurn` assignment
- Ability review

---

*This document should be updated as design decisions are finalized.*

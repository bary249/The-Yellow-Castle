# Ability Testing Plan

This doc is focused on **Ability Testing Mode**.

Source of truth for card→ability mapping: `card_game/lib/data/card_library.dart`.

---

## Ability Testing Mode — Full Checklist

### A) “Must work” Ability-Testing Set (charges + targeting + statuses)

#### `shaco` — Shaco
- [ ] **Spawn**: On play, spawns decoys in the other lanes (same row) if space exists.
- [ ] **Charge**: Shaco consumes its `shaco` charge on spawn and can’t spawn again at `0`.
- [ ] **No tipping**: Decoys show **`Shaco (0)`** (no “1” leak).
- [ ] **Decoy rules**: Decoys behave as designed (0 damage / die from any damage / etc.).

#### `ignite_2` — Firestarter
- [ ] **Targeting**: Only valid adjacent tiles are selectable.
- [ ] **Charge**: Consumes 1 ignite charge; cannot ignite again at `0`.
- [ ] **Tile state**: Tile becomes ignited for `2` turns (visual + state persistence).
- [ ] **Damage on entry** (if intended): unit entering ignited tile takes `1`.
- [ ] **Turn-start tick**: unit standing on ignited tile takes `1` at start of its owner’s turn.
- [ ] **Expire**: Ignite ends after duration.

#### `poisoner` — Poisoner
- [ ] **Apply**: On hit, consumes 1 charge and applies poison.
- [ ] **UI**: Target shows poison badge (`☠ X`) and details show poison.
- [ ] **Tick timing**: Poison deals `1` damage at start of poisoned unit owner’s turn.
- [ ] **Duration**: Decrements and clears at `0`.

#### `resetter` — Resetter
- [ ] **Targeting**: Can only target **friendly** unit on **same tile**.
- [ ] **Effect**: Adds `+1` charge to each consumable ability on the target (`fear`, `paralyze`, `glue`, `silence`, `shaco`, `poisoner`, `ignite_*`, etc. as applicable).
- [ ] **Self-destruct**: Resetter removes itself after use.
- [ ] **UI refresh**: Target shows updated charges immediately.

#### `switcher` — Switcher
- [ ] **Two targets**: Must select 2 friendly units on same tile.
- [ ] **Swap**: Abilities swap between targets (UI updates).
- [ ] **Persist**: Swapped abilities still work after end turn.
- [ ] **Self-destruct**: Switcher removes itself after swap.

#### DOT stacking (Poison + Ignite)
- [ ] **Stacking**: Poisoned unit standing on ignited tile takes **2 total damage** at turn start (1 poison + 1 ignite).

---

### B) Fog / Reveal / Hidden Info

#### `spy` — Spy
- [ ] **Movement rule**: Can enter enemy base as designed.
- [ ] **Trigger**: On base entry, eliminates 1 enemy on that tile then spy is destroyed.
- [ ] **Visibility**: Confirm it behaves with watcher/scout vision rules.

#### `watcher` — Watcher
- [ ] **Reveal zone**: Reveals hidden info on:
  - [ ] Same tile
  - [ ] Left/right adjacent tiles
  - [ ] The “forward” tile (from owner perspective)
- [ ] **Effect**: Enemy spies/concealed info becomes visible where watcher applies.

#### `scout` — Scout, Desert Shadow Scout
- [ ] **Reveal**: Reveals adjacent lanes per design (center vs side behavior).

#### `tall` — Tall
- [ ] **Reveal radius**: Manhattan distance 1 visibility works as expected.

---

### C) Control / Defensive

#### `barrier` — Barrier
- [ ] **Absorb**: First incoming damage is negated.
- [ ] **Charge**: Goes to `0` after absorbing.
- [ ] **After**: Next hit damages normally.

#### `fear` — Fear
- [ ] **Trigger**: First time enemy enters tile in front → enemy AP becomes `0`.
- [ ] **Once**: Doesn’t re-trigger when charge is `0` / already consumed.

#### `paralyze` — Paralyzer
- [ ] **Effect**: Enemy directly in front cannot move/attack while paralyzer behind.

#### `glue` — Glue
- [ ] **Effect**: Enemy directly in front cannot intentionally move while glued.

#### `silence` — Silencer
- [ ] **Effect**: Enemy directly in front cannot attack while silenced.

#### `guard` — (multiple cards)
- [ ] **Rule**: Guard priority / interception behaves per current implementation.

#### `mega_taunt` — Mega Taunt
- [ ] **Intercept**: Intercepts base attacks for adjacent bases.

#### `tile_shield_6` — Lake Shield Totem
- [ ] **Effect**: Damage mitigation applies to all units on tile (verify amount).

---

### D) Attack Patterns / Special Targeting

#### `push_back` — Pusher
- [ ] **Push**: On normal attack, pushes enemy unit(s) back 1 tile.

#### `diagonal_attack` — Diagonal Attacker
- [ ] **Diagonal**: Can attack diagonally adjacent (distance 1 only).

#### `one_side_attacker` — One-Side Attacker
- [ ] **Splash**: Hits center + far side (from side) with only primary retaliation.

#### `two_side_attacker` — Two-Side Attacker
- [ ] **Splash**: Center hits both sides; side hits center; only primary retaliation.

#### `lane_sweep` — Lane Sweeper
- [ ] **Lane hit**: Attacks all enemies in lane (verify definition + damage).

#### `long_range` — Siege Cannon
- [ ] **Range**: Can attack enemies 2 tiles away.

#### `ranged` — (many cards)
- [ ] **No retaliation**: Ranged attacker does not receive retaliation damage.

---

### E) Buff / Heal / Auras

#### `enhancer` — Enhancer
- [ ] **Target ally**: Same tile only.
- [ ] **Double damage**: Target damage doubles.
- [ ] **Self-destruct**: Enhancer removes itself.

#### `ap_booster` — AP Booster
- [ ] **+1 AP**: Target friendly on same tile gains AP (check clamp to max).

#### `medic_5` / `medic_10` / `medic_15`
- [ ] **Heal amount**: Matches number.
- [ ] **No overheal**: Doesn’t exceed max HP.

#### `heal_ally_2` — Woods Healing Tree
- [ ] **Tick**: Heals as expected at correct timing.

---

### F) Parameterized Combat Mods (test one representative each)

#### `shield_1`, `shield_2`, `shield_3`
- [ ] **Mitigation**: Reduces incoming damage by the value.

#### `fury_1`, `fury_2`, `fury_3`
- [ ] **Bonus damage**: Adds value to damage on attack.

#### `regen_1`, `regen_2`
- [ ] **Healing per turn**: Heals by value at correct timing.

#### `thorns_3`
- [ ] **Reflect**: Attacker takes 3 damage when hitting the unit.

#### `fortify_1`
- [ ] **Lane-wide shield buff** applies properly.

#### `inspire_1`, `inspire_2`
- [ ] **Lane-wide damage buff** applies properly.

#### `rally_1`
- [ ] **Adjacent ally buff** applies properly.

#### `command_1`
- [ ] **Lane-wide damage + shield** apply properly.

#### `motivate_1`
- [ ] **Same-type aura** applies only to correct family units and correct tiles.

---

### G) Terrain / Traps / Conversion

#### `trap_3` — Woods Mine
- [ ] **Hidden trigger**: Enemy entering tile takes 3 damage.
- [ ] **Fog behavior**: Should not be obvious unless revealed.

#### `terrain_affinity` — Terrain Adept
- [ ] **Lake**: +1 AP on arrival once per tile per turn
- [ ] **Marsh**: +5 HP
- [ ] **Desert**: becomes ranged
- [ ] **Woods**: +3 damage

#### `converter` — Converter
- [ ] **Convert**: Changes target tile terrain correctly and persists.

---

## Ability → Card(s) quick reference (parsed)

- `ap_booster`: AP Booster
- `archer`: Archer
- `barrier`: Barrier
- `cannon`: Desert Cannon, Lake Cannon, Woods Cannon
- `cavalry`: Cavalry, Desert Elite Striker, Lake Elite Striker, Murad Bey, Woods Elite Striker
- `cleave`: Coalition Forces, Grand Battery, Licorne Cannon, Sunfire Warlord
- `command_1`: Marshal Ney
- `converter`: Converter
- `diagonal_attack`: Diagonal Attacker
- `enhancer`: Enhancer
- `fear`: Fear
- `first_strike`: Bedouin Raider, Cossack, Murad Bey
- `flanking`: Desert Shadow Scout
- `fortify_1`: Sapper
- `fury_1`: Desert Berserker, Grenadier, Mamluk Bey, Marshal Ney, Pavlovsky Guard, Polish Lancer
- `fury_2`: Desert War Banner, Old Guard, Sunfire Warlord
- `fury_3`: General Beaulieu, Murad Bey
- `glue`: Glue
- `guard`: Ancient Treant, Austrian Grenadier, General Beaulieu, Janissary, Lake Guardian, Old Guard, Shield Guard, Tidal Leviathan
- `heal_ally_2`: Woods Healing Tree
- `ignite_2`: Firestarter
- `inspire_1`: Austrian Officer, Drummer Boy
- `inspire_2`: Imperial Eagle
- `lane_sweep`: Lane Sweeper
- `long_range`: Siege Cannon
- `medic_10`: Advanced Medic
- `medic_15`: Expert Medic
- `medic_5`: Field Medic
- `mega_taunt`: Mega Taunt
- `motivate_1`: Artillery Commander, Melee Commander, Ranged Commander
- `one_side_attacker`: One-Side Attacker
- `paralyze`: Paralyzer
- `pikeman`: Desert Berserker, Desert Veteran, Lake Veteran, Pikeman, Woods Sentinel, Woods Veteran
- `poisoner`: Poisoner
- `push_back`: Pusher
- `rally_1`: Imperial Eagle, Young Guard
- `ranged`: Archer, Artillery Commander, Austrian Cannon, Austrian Hussar, Camel Gun, Chasseur à Cheval, Coalition Forces, Desert Cannon, Field Cannon, Grand Battery, Horse Artillery, Hussar, Lake Cannon, Licorne Cannon, Polish Lancer, Ranged Commander, Shadow Assassin, Siege Cannon, Woods Cannon
- `regen_1`: Lake Mist Weaver, Woods Healing Tree, Woods Sentinel, Woods Shroud Walker
- `regen_2`: Ancient Treant, Tidal Leviathan
- `resetter`: Resetter
- `scout`: Desert Shadow Scout, Scout
- `shaco`: Shaco
- `shield_1`: Austrian Cuirassier, Austrian Grenadier, Cuirassier, Lake Guardian, Lake Mist Weaver, Old Guard, Pavlovsky Guard
- `shield_2`: Coalition Forces
- `shield_3`: General Beaulieu, Tidal Leviathan
- `shield_guard`: Lake Guardian, Shield Guard
- `silence`: Silencer
- `spy`: Spy
- `switcher`: Switcher
- `tall`: Tall
- `terrain_affinity`: Terrain Adept
- `thorns_3`: Ancient Treant
- `tile_shield_6`: Lake Shield Totem
- `trap_3`: Woods Mine
- `two_side_attacker`: Two-Side Attacker
- `watcher`: Watcher


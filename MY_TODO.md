
**Design Notes – Card Mechanics (Technical Translation)**

**Traps / Mines**

* Place a hidden card on a specific terrain tile (e.g., lake, Forest).
* The opponent cannot see the card.
* When an enemy unit enters that tile, the trap is triggered and the unit takes **damage**.

**Burning (Fire Effect)**

* Any unit currently occupying a **Forest** tile takes **damage**.
* Affected units are **pushed back by one tile** (knockback), **if the target tile is unoccupied / valid**.

**Spy**

* Can infiltrate the enemy base **without being revealed** to the opponent.
* Upon activation, the Spy **eliminates one enemy unit**.
* After the action resolves, the Spy **is destroyed (self-sacrifice)**.


To Be Done - 

one Side attacking card - low dmg but can attack 2 side lanes in one attack ( so if placed on east middle tile, can attack all enemy cards on the central and west tile in 1 shot, and vice versa. it cannot attack east and west if placed in middle).

two side attacking card - low dmg but can attack 2 side lanes in one attack ( can attack east and west if placed in middle . but can not attack all enemy cards on the central and west tile in 1 shot, if placed in east tile etc).

Marsh tile charastarstic - cosnumes 2 ap on enter.(costs 1 ap to move to, but deplates all ap for cards that moved into it , so if a hussar for examples move into a marsh , evfen if they have 1 ap left, it will be condsumed to 0)

New ability - Glue - makes enemy cards in adjcent front units unable to move from thier current tile for as long as the glueing card is present in front of them.

New Ability  - Mega Taunt - absorb damage to adcjenet ally base regardless of lane. ( so if placed in the middle base tile, it will absorb all damage from cards attacking base in east or west, if placed on est , absorb west and center etc.) it also has the "tall" ability - which means that it's visible to units 1 manhatten distance away. (so cards on middle west or east can see it if placed on central. of )

New ability - shaco - split to all side lane with 2 decoys on each side.

New ability - %Terrain% affinity  - gives special buffs based on matching terrain - lake (+1 ap on arrival), marsh (+5 hp), deset ( gain ranged ability), woods ( +3 dmg) 


New Ability - Watcher - Can see spies and hidden cards from 1 tile away (only left /right/forward/ same tile).


new ability - push back - push back all enemy cards in front of it 1 tile back.








New ability - Silence - makes enemy cards in adjcent front units unable to attack from thier current tile for as long as the silencing card is present in front of them.(It's like glue but on attack instead of movement).

New ability - Paralyze  - makes enemy cards in adjcent front units unable to move or attack from thier current tile for as long as the paralyzing card is present in front of them.(It's like glue but on attack and movement instead of movement).

New ability - barrier - negates one incoming attack dmg completely(no hp reduction for the card)(it's consumed 1 per match same as a hero ability).

New Ability - Fear - A passive card ability , that makes enemy cards that see this card for the first time , reduce thier ap to 0.(it's like makeing the tile in front of this unit act like a "marsh")












































Marsh terrain: AP drain-on-entry (fast, safe)
Spec: normal move cost (1), then if destination is Marsh => set AP to 0. Applies to all movement into marsh, including knockback/push.

Implementation steps:

Core (MatchManager):
After movement resolves, if destTile.terrain == marsh: card.currentAP = 0
Ensure this runs for:
normal move
burning knockback
push-back knockback (later)
UI: no special UI needed initially (optional: show “Marsh drained AP” log later)
AI: avoid stepping into marsh unless beneficial (later optimization)
Docs: update GAME_RULES.md + GAME_LOGIC_SPEC.md
2) Watcher (ties into Spy + hidden mechanics)
Spec: reveals full spy + all hidden cards within 1 tile away: same / left / right / forward. Also enables attacking spies (your answer: yes).

Implementation steps:

Visibility (UI):
When rendering opponent view, allow spies to be shown only if there is an enemy Watcher in range.
Same for other “hidden cards” (we’ll locate how concealment is implemented).
Targeting (core):
Current rule: spies excluded from direct targeting.
New rule: if spy is “revealed by watcher”, allow getValidTargetsTYC3 / targeting to include spy.
Online sync: no new state required if computed from board each frame.
Docs: update Spy + Watcher section.
Open decision (you confirm):

Once watcher reveals spy, can any unit target it, or only watcher?
3) Side attacks (two abilities)
Shared requirements:

Damage = 3
Player chooses a primary target.
Only primary target retaliates.
UI should preview “also hits these units”, and result dialog should list collateral hits.
3a) One-Side Attacker
Spec:

If placed in east middle tile: can attack center + west in one attack (and vice versa).
If placed in center: does not attack both sides.
Implementation:

CombatResolver: resolve attack as:
Primary target tile: chosen target
Secondary tiles: based on attacker lane
Apply 3 dmg to all enemy cards on affected tiles
Retaliation: only from the chosen primary target card
UI:
While targeting, highlight affected tiles
Battle result dialog: show list of collateral hits/destroys
AI: if it has this unit, choose targets maximizing multi-hit value.
3b) Two-Side Attacker
Spec:

If placed in middle: hits east + west.
If placed in east: cannot do the “central+west in one shot”; so it behaves like normal (or hits only center—your text implies “cannot attack all enemy cards on central and west tile”, so I’ll treat as only central? we’ll implement exactly: side position does not gain extra beyond normal lane).
(We’ll encode precise lane patterns once I inspect current lane/row model.)

4) Glue (movement lock in front tile)
Spec:

A glue unit locks enemy cards in the tile directly in front (same lane, one step forward).
Prevents movement and forced movement / knockback.
Effect ends immediately when glue unit moves away or dies.
Implementation:

Core:
In move validation / forced movement:
If victim is glued, movement fails (no displacement).
Need to update burning knockback logic to respect glue.
UI: show “Glued: cannot move” snackbar.
AI: stop trying to move glued units; prefer attacking glue source.
5) Mega Taunt + Tall
Mega Taunt spec:

Intercepts only base-damage attacks (attacks whose target is the base).
Cross-lane adjacency:
Middle base tile protects east/west base attacks, etc.
Interceptor selection:
Pick eligible Mega Taunt with highest HP, tie => random.
Tall spec:

Purely fog-of-war visibility within manhattan distance 1.
Implementation:

Core:
In attackBaseTYC3 (and any other base-damage entry point), before applying damage:
find eligible MegaTaunt defenders
redirect damage to defender card instead of base
UI: base attack dialog should say “Intercepted by Mega Taunt”.
Visibility: tall units reveal themselves within 1 manhattan to enemy.
6) Shaco (decoy spawn)
Spec:

On play
Spawns 1 decoy each into side lanes (one west, one east)
Decoys use same visible stats as Shaco (so they’re not obvious)
“Use the same decoy mechanism already implemented”
Implementation:

Find existing decoy system; reuse it (very important).
Ensure tile capacity is respected.
7) Terrain Affinity
Spec: buff while standing on terrain.

Lake: +1 AP on arrival, only once per tile per turn
Marsh: +5 HP
Desert: “gains ranged” (not attackRange=2; use existing “ranged” mechanic)
Woods: +3 dmg
Implementation concerns:

Needs per-turn gating for lake. Likely needs small per-card state (serialized) like lastLakeBonusTurn + lastLakeBonusTileKey.
“While standing” means buffs are dynamic; we’ll compute effective stats during attack/move checks.
8) Push Back (new)
Spec: push back all enemy cards in front tile 1 tile back. Open decision needed: when does it trigger? (attack vs activation vs passive)

Implementation:

Needs forced movement engine that respects:
tile bounds
tile capacity
glue prevention
marsh AP drain if pushed into marsh
traps/burning triggers on landing
9) Add a new card for each ability + ability testing availability
For each mechanic:

Add a card factory in card_library.dart.
Ensure the card shows up in ability testing mode pool:
Ability testing currently builds a combined pool; we’ll ensure our new cards are included (or explicitly append them).
---
trigger: model_decision
description: This is the main gameplay loop. consider this when building the game mechanics and screens and logics
---

Land Of Clans & Wanderers

 🌟 Game Vision

- A strategic card-based base defense game.
- Players raid or defend clan bases using 25-card decks.
- Matches are short (3–5 minutes), with tactical depth, bluffing, and progression systems.
- Future MOBA-style modes exist in the broader vision, but are not the current focus.

---
🔹 Core Gameplay Loop

Setup
- Both players load a pre-built 25-card deck.
- Each draws 6 cards initially.
- Hand limit: 8 cards (possibly 9, TBD).
- Map features 3 lanes (columns), each with 2 tiers leading to enemy crystal.
- Each player’s frontline and crystal are element-attuned.

Turn Phase (8 Seconds, Simultaneous Submission)
- Both players simultaneously:
  - Choose 0–2 cards per lane.
  - Stack up to 2 cards per lane (choose top/bottom order).
  - Submit their moves before the timer expires.

Combat Phase
- Combat resolves lane-by-lane.
- Cards act according to a 5-tick system:
  - Tick 1 cards act on ticks 1,2,3,4,5 (5 actions)
  - Tick 2 cards act on ticks 2,4 (2 actions)
  - Tick 3–5 cards act once at their tick.
- Within each tick:
  - All eligible cards act simultaneously.
  - Damage is applied.
- Overflow Damage:
  - If a top card dies, excess damage flows to the next card in the stack.
  - A bottom card only becomes active at the start of a tick — not mid-tick.

Lane and Advancement System
- If a player wins a tier, surviving cards advance to the next tier.
- If a player wins Tier 2, surviving cards advance to attack the enemy crystal.
- New cards can be played between phases (after each full combat round).

Match End
- Game ends if a crystal’s HP is depleted.
- Tiebreakers based on crystal damage if needed.

---

📈 Card Management
- Deck = 25 cards max.
- Initial hand: 6 cards.
- Draw 2 cards per round.
- No mid-match deck reshuffle.
- Scarcity is intentional: playing too many cards early creates mid-game vulnerability.

Card Types
- **General Cards**:
  - No character or element.
  - Damage, Health, Tick stats only.
  - More common.
- **Character Cards**:
  - Linked to specific unit families (e.g., Monkey, Ant).
  - Three variations per character.
  - Playing all 3 variations triggers an "Ultimate".
  - Have skills and elemental alignment.

---
🧹 Hero System
- Each player can assign 1 Hero to a deck.
- Heroes have 2 activatable abilities per combat.
- Heroes cannot be killed.
- Abilities affect broader battle conditions:
  - Buff elemental cards.
  - Heal crystals.
  - Provide extra draws, etc.
- Heroes are *not* tied to a specific element.

---

🌱 Elemental System
- Each base’s frontline and crystal are element-attuned.
- Middle zone of map is neutral.
- Element system includes:
  - Buffs to matching element cards.
  - Weaknesses against opposing elements (Fire > Grass, Water > Fire, etc.).
- Players can change their base and frontline element **outside of combat**, for a gold cost.

---

💰 Resource Systems
- **Gold** earned during battle:
  - Destroying cards (50–200 Gold).
  - Capturing tiers (400 Gold).
  - Win streak bonuses (100 Gold).
- 25% of gold is carried over to the post-match shop.
- No mid-match gold use planned (outside of potential abilities).

---

🌈 Anti-Snowball Systems
- Comeback mechanics available.
- Special cards become accessible when behind.
- Strategic falling behind is possible.

---

🔍 Outstanding Considerations

- Future refinements for hero abilities.
- Final balance for hand size (8 or 9).Split screen into 3 vertical columns


Card hand visible (bottom bar or collapsible)

 Design Goal
Create a mobile-first game screen (portrait) for a card-based lane battler. Each lane shows only one active zone at a time, and each lane may show a different zone (e.g., player base, middle, opponent base).
Players must be able to:
Understand the battle context in each lane


Select and play cards from hand


Track lane progression clearly



📐 Layout Structure
Divide screen into 3 vertical lanes (left, center, right)


Each lane has its own current zone view


Bottom section: player’s hand (collapsible if needed)



🧱 Lane Content Per Zone
Each zone block should support:
Item
Notes
Zone label
At top or corner of lane
Background
Element-based or terrain-based visual
Crystal hint
Partial icon/glow at back edge if relevant
2 player cards
Stacked; top is active, bottom is backup
2 opponent cards
Same structure mirrored
Visual spacing
Enough for drag-to-place or tap-to-select


🕹️ Interaction Flows
Tap card in hand → highlight valid drop slots in all 3 lanes


Drag card into lane → show preview


Tap “Start Combat” → lanes lock and resolve tick-by-tick


Combat log/summary scrolls into view after combat ends (optional)



🧠 Tutorial / First-Time User Cues
Use bright banners for “This is the MIDDLE zone” etc.


Arrows to explain:


Crystal behind you = defend it


Winning pushes you forward


Consider a mini-map or per-lane progression tracker in top bar



🧪 Edge Case & Testing Notes
Make sure card readability works on small phones


Avoid accidental overlap/touch errors between lanes


Lane progression should feel spatial even without zoom



Crystal HP shown near relevant lanes (top and bottom)


"End Turn" or "Start Combat" button clearly accessible


Zone label/map per lane (top of each lane or fixed banner)

- Further design of elemental interactions and weaknesses.

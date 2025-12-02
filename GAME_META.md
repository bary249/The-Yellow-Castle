# Land of Clans & Wanderers – Meta Progression & Campaign System

> **Game Style**: Roguelite Deckbuilder (similar to Dawncaster)  
> **Theme**: Historical Leaders & Civilizations  
> **Core Loop**: Campaign → Acts → Battles → Boss → Rewards → Meta Upgrades

---

## 1. Overview

Players embark on **Campaigns** as historical leaders, each with a unique 3-act story based on their greatest historical achievement. Each campaign is a **roguelite run** – you build your deck during the run, but lose it when the campaign ends (win or lose). 

**Meta progression** persists between runs via **Legacy Points**, which unlock permanent upgrades, new starter cards, items, and leader abilities.

---

## 2. Leaders (Playable Characters)

Each leader represents a different civilization and playstyle. **13 leaders available at launch**, organized by historical era.

### 2.1 Leader Roster

#### **Ancient Era (4 Leaders)**
| Leader | Civilization | Terrain Affinity | Playstyle | Campaign Theme |
|--------|--------------|------------------|-----------|----------------|
| **Ramesses II** | Egypt | Desert | Defensive/Economic | Building the Empire |
| **Julius Caesar** | Rome | Woods | Aggressive/Military | Conquest of Gaul |
| **Alexander the Great** | Macedon | Lake | Aggressive/Fast | Conquest of Persia |
| **Cleopatra** | Ptolemaic Egypt | Lake, Desert | Economic/Political | Queen of the Nile |

#### **Classical/Eastern Era (3 Leaders)**
| Leader | Civilization | Terrain Affinity | Playstyle | Campaign Theme |
|--------|--------------|------------------|-----------|----------------|
| **Sun Tzu** | Ancient China | Woods | Defensive/Utility | The Art of War |
| **Genghis Khan** | Mongol Empire | Desert, Marsh | Aggressive/Swarm | Uniting the Steppes |
| **Napoleon Bonaparte** | France | Woods, Lake | Balanced/Tactical | Conquest of Europe |

#### **Middle Ages Era (3 Leaders)**
| Leader | Civilization | Terrain Affinity | Playstyle | Campaign Theme |
|--------|--------------|------------------|-----------|----------------|
| **Saladin** | Ayyubid Sultanate | Desert | Defensive/Counter | Reclaiming Jerusalem |
| **Richard the Lionheart** | England | Woods, Lake | Aggressive/Chivalry | The Third Crusade |
| **Joan of Arc** | France | Woods | Defensive/Faith | Liberation of France |

#### **Modern Era (3 Leaders)**
| Leader | Civilization | Terrain Affinity | Playstyle | Campaign Theme |
|--------|--------------|------------------|-----------|----------------|
| **George Washington** | United States | Woods, Marsh | Balanced/Guerrilla | American Revolution |
| **Simón Bolívar** | Gran Colombia | Marsh, Woods | Aggressive/Liberation | South American Independence |
| **Queen Victoria** | British Empire | Lake | Economic/Colonial | The Sun Never Sets |

### 2.2 Leader Attributes

Each leader has:
- **Terrain Affinity**: Determines base terrain in battles (affects card bonuses)
- **Starter Deck**: 15 unique cards themed to their civilization and playstyle
- **Leader Ability**: A powerful once-per-battle ability (unlockable variants via meta progression)
- **Special Card Pool**: 6 special cards (player picks 2 at campaign start)
- **Item Pool**: 4 starting items (player picks 1 at campaign start)

---

## 3. Campaign Structure

Each campaign is a **3-act roguelite run** based on the leader's historical achievement.

### 3.1 Campaign Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     CAMPAIGN START                          │
│  • Pick Leader                                              │
│  • Choose 2 Special Cards (from leader's pool of 6)         │
│  • Choose 1 Starting Item (from leader's pool of 4)         │
│  • Receive Starter Deck (15 cards)                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        ACT 1                                │
│  • 4-7 battles (randomized)                                 │
│  • 5-way path choice between battles                        │
│  • Ends with ACT 1 BOSS                                     │
│  • Victory grants: Campaign Achievement + Permanent Buff    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        ACT 2                                │
│  • 5-8 battles (randomized)                                 │
│  • Harder enemies, better rewards                           │
│  • Ends with ACT 2 BOSS                                     │
│  • Victory grants: Campaign Achievement + Permanent Buff    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        ACT 3                                │
│  • 6-9 battles (randomized)                                 │
│  • Hardest enemies, best rewards                            │
│  • Ends with FINAL BOSS                                     │
│  • Victory: Campaign Complete! Major Legacy Points reward   │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Campaign Narratives by Leader

#### **Ramesses II – Building the Empire**
- **Act 1**: Defense of the Delta (Boss: Hittite Vanguard)
  - *Achievement*: **The Pyramids** – All defensive cards gain +1 Shield
- **Act 2**: Battle of Kadesh (Boss: Hittite King Muwatalli II)
  - *Achievement*: **Abu Simbel** – Start each battle with +10 Crystal HP
- **Act 3**: Eternal Legacy (Boss: Sea Peoples Invasion)
  - *Achievement*: **Living God** – Leader ability can be used twice per battle

#### **Julius Caesar – Conquest of Gaul**
- **Act 1**: Gallic Wars Begin (Boss: Helvetii Chieftain)
  - *Achievement*: **Legion Standards** – All units gain +1 damage on first attack
- **Act 2**: Siege of Alesia (Boss: Vercingetorix)
  - *Achievement*: **Roman Roads** – Cards with Move Speed 1+ gain +1 Move Speed
- **Act 3**: Crossing the Rubicon (Boss: Pompey Magnus)
  - *Achievement*: **Dictator Perpetuo** – Draw 1 extra card each turn

#### **Alexander the Great – Conquest of Persia**
- **Act 1**: Battle of Granicus (Boss: Persian Satraps)
  - *Achievement*: **Companion Cavalry** – Fast units (Move 2) deal +2 damage
- **Act 2**: Siege of Tyre (Boss: Tyrian Defenders)
  - *Achievement*: **Gordian Knot** – Once per battle, destroy any enemy card instantly
- **Act 3**: Battle of Gaugamela (Boss: Darius III)
  - *Achievement*: **King of Kings** – All cards cost 0 on the first turn

#### **Napoleon Bonaparte – Conquest of Europe**
- **Act 1**: Italian Campaign (Boss: Austrian General)
  - *Achievement*: **Artillery Master** – Tick 1-2 cards deal +1 damage
- **Act 2**: Egyptian Campaign (Boss: Mamluk Cavalry)
  - *Achievement*: **Rosetta Stone** – Reveal enemy cards at start of battle
- **Act 3**: Battle of Austerlitz (Boss: Coalition Forces)
  - *Achievement*: **Emperor of the French** – Choose 3 cards to add to hand at battle start

#### **Genghis Khan – Uniting the Steppes**
- **Act 1**: Tribal Wars (Boss: Rival Khan)
  - *Achievement*: **Horse Archers** – All units can attack before moving
- **Act 2**: Fall of the Jin Dynasty (Boss: Jin Emperor)
  - *Achievement*: **Yam Network** – Draw 2 extra cards after winning a lane
- **Act 3**: Khwarezmian Empire (Boss: Shah Muhammad II)
  - *Achievement*: **World Conqueror** – Defeated enemies drop bonus Legacy Points

#### **Sun Tzu – The Art of War**
- **Act 1**: Wu-Chu War (Boss: Chu General)
  - *Achievement*: **Know Your Enemy** – See enemy card placements before committing
- **Act 2**: Battle of Boju (Boss: Chu King's Guard)
  - *Achievement*: **Supreme Excellence** – Win battles without fighting: uncontested lanes deal double crystal damage
- **Act 3**: The Art of War (Boss: Rival Strategist)
  - *Achievement*: **Master Strategist** – Rearrange your card positions after seeing enemy moves

#### **Cleopatra – Queen of the Nile**
- **Act 1**: Securing the Throne (Boss: Ptolemy XIII)
  - *Achievement*: **Royal Treasury** – Gain +50% gold from all sources
- **Act 2**: Alliance with Rome (Boss: Roman Assassins)
  - *Achievement*: **Diplomatic Immunity** – One card per battle cannot be targeted
- **Act 3**: Battle of Actium (Boss: Octavian's Fleet)
  - *Achievement*: **Last Pharaoh** – If you would lose, survive with 1 HP once per battle

---

### 3.3 Middle Ages Campaign Narratives

#### **Saladin – Reclaiming Jerusalem**
- **Act 1**: Uniting the Sultanate (Boss: Fatimid Rebels)
  - *Achievement*: **Desert Fortress** – All units gain +1 Shield when defending
- **Act 2**: Battle of Hattin (Boss: King Guy of Jerusalem)
  - *Achievement*: **Chivalrous Honor** – Defeated enemy units have 20% chance to join your deck
- **Act 3**: Siege of Jerusalem (Boss: Crusader Garrison)
  - *Achievement*: **Mercy of the Sultan** – Heal 5 HP after each battle victory

#### **Richard the Lionheart – The Third Crusade**
- **Act 1**: Siege of Acre (Boss: Saracen Defenders)
  - *Achievement*: **Crusader Zeal** – All units deal +1 damage when attacking
- **Act 2**: March to Jaffa (Boss: Saladin's Vanguard)
  - *Achievement*: **Lion's Courage** – Units below 50% HP gain Fury +2
- **Act 3**: Battle of Arsuf (Boss: Saladin's Elite Guard)
  - *Achievement*: **Heart of a Lion** – Leader ability cooldown reduced by 1 turn

#### **Joan of Arc – Liberation of France**
- **Act 1**: The Siege of Orléans (Boss: English Garrison)
  - *Achievement*: **Divine Vision** – See 2 extra path options on the campaign map
- **Act 2**: Coronation at Reims (Boss: Burgundian Ambush)
  - *Achievement*: **Blessed Banner** – All allies gain +1/+1 at battle start
- **Act 3**: The Maid's Trial (Boss: Inquisition Forces)
  - *Achievement*: **Martyrdom** – If your crystal would be destroyed, survive with 1 HP and gain +3 damage to all units (once per campaign)

---

### 3.4 Modern Era Campaign Narratives

#### **George Washington – American Revolution**
- **Act 1**: Crossing the Delaware (Boss: Hessian Mercenaries)
  - *Achievement*: **Winter Soldiers** – Units gain +1 damage in the first 2 turns
- **Act 2**: Valley Forge (Boss: British Regulars)
  - *Achievement*: **Forged in Hardship** – Gain 1 extra card choice after each battle
- **Act 3**: Siege of Yorktown (Boss: General Cornwallis)
  - *Achievement*: **Father of the Nation** – Start each battle with 1 random buff active

#### **Simón Bolívar – South American Independence**
- **Act 1**: Admirable Campaign (Boss: Spanish Royalists)
  - *Achievement*: **Liberator's Call** – Summon a free "Patriot" card at battle start
- **Act 2**: Crossing the Andes (Boss: Mountain Garrison)
  - *Achievement*: **Mountain Warfare** – Units with Move Speed 2 gain +2 HP
- **Act 3**: Battle of Boyacá (Boss: Viceroy's Army)
  - *Achievement*: **Gran Colombia** – All units gain +1/+1 for each act completed

#### **Queen Victoria – The Sun Never Sets**
- **Act 1**: Securing the Crown (Boss: Chartist Uprising)
  - *Achievement*: **Industrial Revolution** – Gain +30% gold from all sources
- **Act 2**: The Crimean War (Boss: Russian Imperial Guard)
  - *Achievement*: **Naval Supremacy** – Lake terrain units gain +2 damage
- **Act 3**: Diamond Jubilee (Boss: Colonial Rebellion)
  - *Achievement*: **Empress of India** – Item limit increased by 1 (6 max)

---

## 4. Battle Path System (Between Battles)

After each battle, the player chooses from **5 possible paths**. Each path has a **revealed icon** indicating what awaits.

### 4.1 Path Types

| Icon | Path Type | Description |
|------|-----------|-------------|
| ⚔️ | **Normal Battle** | Standard enemy encounter. Rewards: Gold + 1 card choice |
| 💀 | **Elite Battle** | Harder enemy, better rewards. Rewards: Gold + 2 card choices + 1 item |
| 🎰 | **Mystery Battle** | Unknown difficulty. Could be easy or brutal. High risk/reward |
| 🏪 | **Card Shop** | Spend gold to buy cards. No battle |
| 🎁 | **Item Shop** | Spend gold to buy items. No battle |
| ⛺ | **Rest Site** | Heal crystal HP, remove a card from deck, or upgrade a card |
| 📜 | **Event** | Story event with choices. Could grant cards, items, buffs, or debuffs |
| 💎 | **Treasure** | Free reward! Random card or item. Rare occurrence |

### 4.2 Path Generation Rules

- **Always** at least 1 battle option (Normal or Elite)
- **Non-battle options** (Shop, Rest, Event) appear every 2-3 encounters, not every turn
- **Elite battles** become more common in later acts
- **Mystery battles** have higher variance (could be treasure or trap)
- **Boss path** appears after minimum battles completed (forced, no choice)

### 4.3 Difficulty Indicators

Normal battles show a **skull count** (1-3) indicating difficulty:
- 💀 = Easy (weaker deck, lower HP)
- 💀💀 = Medium (balanced)
- 💀💀💀 = Hard (strong deck, higher HP, possible elite cards)

---

## 5. Cards & Deck Building (During Campaign)

### 5.1 Starter Deck (15 Cards)

Each leader begins with a **themed 15-card starter deck**:

| Leader | Deck Theme | Example Cards |
|--------|------------|---------------|
| Ramesses II | Defensive/Structures | Stone Wall, Obelisk Guard, Desert Sentinel |
| Julius Caesar | Aggressive/Legion | Legionnaire, Centurion, Pilum Thrower |
| Alexander | Fast/Cavalry | Companion, Phalanx, Hetairoi |
| Napoleon | Balanced/Artillery | Grenadier, Cannon, Old Guard |
| Genghis Khan | Swarm/Mobility | Horse Archer, Mongol Rider, Keshik |
| Sun Tzu | Utility/Control | Spy, Saboteur, Strategist |
| Cleopatra | Economic/Political | Royal Guard, Merchant, Diplomat |

### 5.2 Special Cards (Pick 2 at Campaign Start)

Each leader has **6 special cards** in their pool. Player picks **2** before starting.

**Example – Napoleon's Special Card Pool:**
1. **Imperial Guard** – Elite unit with Fury +2 and Shield +1
2. **Artillery Barrage** – Deal 5 damage to all enemies in one lane
3. **Forced March** – All your units gain +1 Move Speed this battle
4. **Conscription** – Draw 3 cards immediately
5. **Marshal's Baton** – One unit gains +3/+3 permanently
6. **Continental System** – Enemy cards cost +1 to play this battle

### 5.3 Card Acquisition During Campaign

Cards can be acquired through:
- **Battle Rewards**: Choose 1 of 3 cards after winning
- **Elite Rewards**: Choose 2 of 4 cards after winning elite battles
- **Card Shops**: Buy cards with gold (3-5 cards available)
- **Events**: Some events grant free cards
- **Boss Rewards**: Guaranteed rare/epic card

### 5.4 Card Rarity in Campaign

| Rarity | Availability | Power Level |
|--------|--------------|-------------|
| Common | Battles, Shops | Basic stats |
| Rare | Elite battles, Shops | +25% stats, minor ability |
| Epic | Bosses, Events | Strong ability |
| Legendary | Act 3 only, very rare | Game-changing ability |

---

## 6. Items (Permanent Campaign Buffs)

Items are **passive buffs** that last the entire campaign run.

### 6.1 Starting Item (Pick 1 at Campaign Start)

Each leader has **4 starting items** in their pool. Player picks **1**.

**Example – Napoleon's Starting Item Pool:**
1. **Bicorne Hat** – +1 damage to all Tick 1-2 cards
2. **Campaign Map** – See one extra path option
3. **Imperial Eagle** – +5 Crystal HP at battle start
4. **Artillery Manual** – Cards with Cleave deal +2 damage

### 6.2 Item Acquisition During Campaign

Items can be acquired through:
- **Elite Battle Rewards**: Guaranteed item drop
- **Item Shops**: Buy items with gold (2-3 items available)
- **Events**: Some events grant items
- **Boss Rewards**: Guaranteed item

### 6.3 Item Categories

| Category | Effect Type | Examples |
|----------|-------------|----------|
| **Offensive** | Damage boosts | +1 damage to fast units, Cleave bonus |
| **Defensive** | Survivability | +Crystal HP, Shield bonuses, Regen |
| **Utility** | Card/Resource | Extra draws, gold bonus, card upgrades |
| **Unique** | Special effects | See enemy hands, extra turn time, etc. |

### 6.4 Item Limit

Players can hold **maximum 5 items** at once. If at limit, must discard one to pick up new.

---

## 7. Meta Progression (Legacy System)

**Legacy Points** are the persistent currency earned across all campaign runs.

### 7.1 Earning Legacy Points

| Source | Legacy Points |
|--------|---------------|
| Win Normal Battle | 5 LP |
| Win Elite Battle | 10 LP |
| Defeat Boss | 25 LP |
| Complete Act 1 | 50 LP |
| Complete Act 2 | 100 LP |
| Complete Act 3 (Win Campaign) | 200 LP |
| First time completing a campaign | 100 LP bonus |
| Lose a campaign | 10-30 LP (based on progress) |

### 7.2 Leader Upgrade Trees

Each leader has **3 intertwining upgrade branches**. Upgrades cost Legacy Points.

```
                    ┌─────────────────┐
                    │   LEADER ROOT   │
                    │   (Unlocked)    │
                    └────────┬────────┘
           ┌─────────────────┼─────────────────┐
           ▼                 ▼                 ▼
    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
    │   MILITARY   │  │   ECONOMIC   │  │   POLITICAL  │
    │   (Offense)  │  │   (Utility)  │  │   (Defense)  │
    └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
           │                 │                 │
    ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐
    │  Tier 1 (50) │  │  Tier 1 (50) │  │  Tier 1 (50) │
    └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
           │                 │                 │
    ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐
    │ Tier 2 (100) │  │ Tier 2 (100) │  │ Tier 2 (100) │
    └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
           │                 │                 │
    ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐
    │ Tier 3 (150) │  │ Tier 3 (150) │  │ Tier 3 (150) │
    └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
           │                 │                 │
    ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐
    │ Tier 4 (200) │  │ Tier 4 (200) │  │ Tier 4 (200) │
    └──────────────┘  └──────────────┘  └──────────────┘
```

### 7.3 Upgrade Types by Branch

#### **Military Branch (Offense)**
| Tier | Upgrade | Effect |
|------|---------|--------|
| 1 | Veteran Training | Starter deck cards gain +1 damage |
| 2 | Elite Recruits | Unlock 2 new aggressive special cards |
| 3 | War Machine | Unlock "Siege Engine" starting item |
| 4 | Conqueror's Wrath | Leader ability deals +3 damage |

#### **Economic Branch (Utility)**
| Tier | Upgrade | Effect |
|------|---------|--------|
| 1 | Trade Routes | +20% gold from battles |
| 2 | Merchant Guild | Unlock 2 new utility special cards |
| 3 | Royal Treasury | Unlock "Golden Crown" starting item |
| 4 | Economic Dominance | Start campaigns with 100 bonus gold |

#### **Political Branch (Defense)**
| Tier | Upgrade | Effect |
|------|---------|--------|
| 1 | Fortifications | Starter deck cards gain +1 HP |
| 2 | Diplomatic Corps | Unlock 2 new defensive special cards |
| 3 | Alliance Network | Unlock "Treaty Scroll" starting item |
| 4 | Divine Right | Start battles with a random buff active |

### 7.4 Cross-Branch Synergies

Some upgrades require nodes from **multiple branches**:

| Synergy Upgrade | Requirements | Effect |
|-----------------|--------------|--------|
| **Imperial Ambition** | Military T2 + Political T2 | Unlock alternate leader ability |
| **Golden Age** | Economic T2 + Political T2 | +1 item slot (6 max) |
| **Total War** | Military T2 + Economic T2 | Elite battles give double rewards |
| **World Wonder** | All T3 nodes | Unlock leader's ultimate ability |

### 7.5 Leader Abilities (Unlockable Variants)

Each leader starts with **1 base ability**. Meta progression unlocks **2 alternate abilities**.

**Example – Napoleon:**
| Ability | Unlock | Effect |
|---------|--------|--------|
| **Tactical Genius** (Base) | Default | Draw 2 extra cards this turn |
| **Artillery Barrage** | Military T4 | Deal 5 damage to all enemies in one lane |
| **Grande Armée** | Imperial Ambition synergy | All units gain +2/+2 this turn |

---

## 8. Shops

### 8.1 Card Shop

- **Appears**: As a path option between battles
- **Inventory**: 4-6 cards (randomized, rarity based on act)
- **Prices**: 
  - Common: 50-75 gold
  - Rare: 100-150 gold
  - Epic: 200-300 gold
- **Refresh**: Pay 25 gold to refresh inventory (once per visit)
- **Card Removal**: Pay 75 gold to remove a card from your deck

### 8.2 Item Shop

- **Appears**: As a path option between battles (less common than card shop)
- **Inventory**: 2-4 items (randomized)
- **Prices**: 100-250 gold depending on power
- **Refresh**: Pay 50 gold to refresh inventory (once per visit)

---

## 9. Rest Sites

Rest sites offer **one of three choices**:

| Choice | Effect |
|--------|--------|
| **Rest** | Heal 30% of max Crystal HP |
| **Smith** | Upgrade one card (permanent +1/+1 or ability enhancement) |
| **Meditate** | Remove one card from your deck |

---

## 10. Events

Random story events with **meaningful choices**.

### 10.1 Example Events

**The Merchant Caravan**
> A traveling merchant offers you rare goods, but bandits are nearby.
- **Protect the Merchant**: Fight elite battle → Gain 2 items + 100 gold
- **Rob the Merchant**: Gain 150 gold, lose 1 random item
- **Ignore**: Nothing happens

**Ancient Ruins**
> You discover ruins of a forgotten civilization.
- **Explore Carefully**: Gain 1 random rare card
- **Loot Everything**: Gain 2 random cards, but take 10 crystal damage
- **Study the Inscriptions**: Upgrade 2 random cards in your deck

**The Deserter**
> A soldier from the enemy army offers to join you.
- **Accept**: Add "Deserter" card to deck (mediocre stats, but free)
- **Interrogate**: See the next 3 battle difficulties
- **Execute**: Gain 25 gold, +1 damage next battle

---

## 11. Difficulty Scaling

### 11.1 Act Difficulty

| Act | Enemy HP | Enemy Cards | Elite Chance | Rewards |
|-----|----------|-------------|--------------|---------|
| 1 | 80-100 | Common/Rare | 20% | Low |
| 2 | 100-120 | Rare/Epic | 35% | Medium |
| 3 | 120-150 | Epic/Legendary | 50% | High |

### 11.2 Boss Scaling

| Boss | HP | Special Mechanics |
|------|-----|-------------------|
| Act 1 Boss | 120 | 1 unique ability |
| Act 2 Boss | 150 | 2 unique abilities |
| Act 3 Boss | 200 | 3 unique abilities + enrage at 50% HP |

---

## 12. Campaign Rewards Summary

### 12.1 Per-Battle Rewards

| Battle Type | Gold | Cards | Items | Legacy Points |
|-------------|------|-------|-------|---------------|
| Normal | 30-50 | 1 choice | - | - |
| Elite | 50-80 | 2 choices | 1 | 10 |
| Boss | 100 | 1 guaranteed rare+ | 1 | 25 |

### 12.2 Campaign Completion Rewards

| Outcome | Legacy Points | Bonus |
|---------|---------------|-------|
| Die in Act 1 | 10-20 | - |
| Die in Act 2 | 30-50 | - |
| Die in Act 3 | 60-80 | - |
| Complete Campaign | 200 | +100 if first time |

---

## 13. UI/UX Considerations

### 13.1 Campaign Map Screen
- **Visual**: Branching path map (like Slay the Spire)
- **Shows**: Current position, upcoming nodes, act progress
- **Icons**: Clear indicators for each path type

### 13.2 Pre-Campaign Screen
- **Leader Selection**: Portrait + stats + terrain + playstyle
- **Special Card Selection**: 6 cards shown, pick 2
- **Item Selection**: 4 items shown, pick 1
- **Deck Preview**: See starter deck before confirming

### 13.3 Meta Progression Screen
- **Leader Grid**: All 7 leaders with unlock/upgrade status
- **Upgrade Tree**: Visual tree with branches and synergies
- **Legacy Points**: Current balance and earning history

---

## 14. Future Expansion Ideas

### 14.1 Additional Leaders
- **Joan of Arc** (France) – Divine/Faith theme
- **Hannibal Barca** (Carthage) – Elephants/Siege theme
- **Shaka Zulu** (Zulu) – Warrior/Rush theme
- **Queen Victoria** (Britain) – Colonial/Naval theme
- **Tokugawa Ieyasu** (Japan) – Samurai/Honor theme

### 14.2 New Game Modes
- **Endless Mode**: Infinite acts with scaling difficulty
- **Daily Challenge**: Fixed seed, leaderboard competition
- **Boss Rush**: Fight all bosses in sequence
- **Multiplayer Campaign**: Co-op or competitive campaigns

### 14.3 Seasonal Content
- **New Acts**: Additional story content per leader
- **New Cards**: Seasonal card pools
- **Limited Events**: Time-limited campaigns with unique rewards

---

## 15. Technical Implementation Notes

### 15.1 Data Models Needed
- `Leader` – id, name, terrain, playstyle, starterDeck, specialCards, items, upgradeTree
- `Campaign` – leaderId, currentAct, currentNode, deck, items, gold, achievements
- `CampaignNode` – type, difficulty, rewards, completed
- `CampaignAct` – actNumber, nodes, bossNode, achievement
- `LegacyProgress` – totalPoints, spentPoints, unlockedUpgrades per leader
- `Item` – id, name, description, effect, rarity

### 15.2 Save System
- **Campaign Save**: Auto-save after each battle (one active campaign per leader)
- **Meta Save**: Legacy points and upgrades (synced to cloud)

### 15.3 Mode Compatibility
This system is **primarily for single-player** (Player vs AI). 
- **Simulation Mode**: Can simulate campaign runs for balance testing
- **Online Mode**: Separate from campaigns (uses standard deck building)

---

## Appendix A: Leader Quick Reference

### Ancient Era
| Leader | Terrain | Playstyle | Base Ability |
|--------|---------|-----------|--------------|
| Ramesses II | Desert | Defensive | Shield Wall – All units gain +2 Shield this turn |
| Julius Caesar | Woods | Aggressive | Legion Advance – All units attack twice this turn |
| Alexander | Lake | Fast | Cavalry Charge – All units gain +2 Move Speed |
| Cleopatra | Lake/Desert | Economic | Royal Decree – Gain 50 gold, heal 10 HP |

### Classical/Eastern Era
| Leader | Terrain | Playstyle | Base Ability |
|--------|---------|-----------|--------------|
| Sun Tzu | Woods | Control | Art of War – Rearrange all cards after seeing enemy |
| Genghis Khan | Desert/Marsh | Swarm | Horde – Summon 2 Horse Archer cards |
| Napoleon | Woods/Lake | Balanced | Tactical Genius – Draw 2 extra cards |

### Middle Ages Era
| Leader | Terrain | Playstyle | Base Ability |
|--------|---------|-----------|--------------|
| Saladin | Desert | Counter | Desert Wind – Counter-attack deals double damage this turn |
| Richard the Lionheart | Woods/Lake | Chivalry | Crusader's Charge – All units gain +2 damage and -1 tick this turn|
| Joan of Arc | Woods | Faith | Divine Inspiration – Heal all units to full HP |

### Modern Era
| Leader | Terrain | Playstyle | Base Ability |
|--------|---------|-----------|--------------|
| George Washington | Woods/Marsh | Guerrilla | Ambush – Hidden units deal +3 damage on first attack |
| Simón Bolívar | Marsh/Woods | Liberation | Rally the People – Summon 2 Patriot cards to empty lanes |
| Queen Victoria | Lake | Colonial | Imperial Mandate – Gain 100 gold and draw 2 cards |

---

## Appendix B: Glossary

- **Campaign**: A full roguelite run with one leader (3 acts)
- **Act**: A section of the campaign ending with a boss
- **Node**: A point on the campaign map (battle, shop, event, etc.)
- **Legacy Points (LP)**: Persistent currency for meta upgrades
- **Special Card**: Powerful cards chosen at campaign start
- **Item**: Passive buff lasting the entire campaign
- **Achievement**: Permanent buff earned by defeating act bosses
- **Starter Deck**: The 15 cards you begin each campaign with

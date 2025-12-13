Make sure all title and back buttons have good contrast (some are black on brown now and hard to see).

[X] Add a continuity mechanism to the campaign mode.
[X] A signed in player (not guest) should be able to continue the campaign from where they stopped (not mid battle, but yes in terms of their deck and inventory, act, and encounter selection).
[X] Save campaign progress locally so players can resume after app restart.
[X] Implement cloud sync for campaign progress across devices (if Firebase auth is available).
[X] Track completed encounters and unlocked content between sessions.
[X] Persist campaign state including deck, inventory, act progress, and encounter selections.
[X] Ensure campaign data is properly loaded when resuming from saved state.


The campaign mode should have a menu with 3 options: Start Camagin, Continue Camapgin(if applicable), and Hero Progress.
Start is a new campaign, continue is if there is a saved campagin that is not done yet for this user and hero progress is teh skill tree for the hero (see @GAME_META for details).



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

- [x] Implement act 2 and 3 for Napoleon in campaign mode.
- [x] Add the meta progression screen for Napoleon and link it from the campaign menu.
- [x] Add campaign mode entry points to the main menu (start/continue).
- [x] Grant a relic reward when successfully completing each act.
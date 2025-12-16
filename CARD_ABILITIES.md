# Card Abilities

This document lists all available card abilities and their effects in the game.

## Unit Class Interactions (Buffs/Debuffs)
These interactions trigger automatically when specific unit classes battle each other.

| Class | Interaction | Effect |
|-------|-------------|--------|
| **Pikeman** | vs **Cavalry** | **+4 Damage** when attacking Cavalry.<br>**+4 Retaliation** when defending against Cavalry. |
| **Cavalry** | vs **Archer** | **+4 Damage** when attacking Archers. |
| **Ranged Unit** | vs **Melee** | **-4 Retaliation** (Weakness) when attacked by melee units. |
| **Shield Guard** | vs **Ranged** | **-2 Damage Taken** from ranged attacks. |

## Standard Abilities

### Combat Abilities
*   **Ranged**: Can attack from a distance without triggering retaliation from melee targets.
*   **Long Range**: Increases attack range to 2 tiles (standard range is 1).
*   **Guard**: Protects other units in the same tile. Enemies must defeat all Guards in a tile before they can target other units or the Base.
*   **Fury X**: Adds **+X** to Damage dealt (both on attack and retaliation).
*   **Shield X**: Reduces all incoming damage by **X** (minimum 0).
*   **Thorns X**: Deals **X** damage to any attacker after combat resolves.
*   **Command X**: Grants **+2X Damage** to all other friendly units on the same tile. (e.g., Command 1 = +2 damage to adjacent allies)

### Utility Abilities
*   **Scout**: Provides vision of adjacent lanes, revealing units hidden by Fog of War.
*   **Flanking**: Allows the unit to move sideways (change lanes) to adjacent columns. Standard units can only move forward.
*   **Regen / Regenerate**: Restores HP/AP at the start of the turn (mechanic details may vary by implementation).

## Retaliation Mechanics
Retaliation occurs when a unit is attacked.

*   **Melee vs Melee**: When a melee unit is attacked by another melee unit, the defender strikes back (Retaliates) with their current Damage. This happens **simultaneously** with the attack (even if the defender dies).
*   **Ranged Attacks**: Units with **Ranged** or **Long Range** abilities do **not** trigger retaliation when attacking (unless the target also has a special ability to counter-fire, which is not standard).
*   **Retaliation Modifiers**:
    *   **Ranged Weakness**: Ranged units (Archers, Cannons) suffer **-4 Retaliation Damage** when attacked by any melee unit.
    *   **Pikeman Defense**: Pikemen deal **+4 Retaliation Damage** when attacked by Cavalry.
    *   **Terrain Bonus**: Units on matching terrain deal **+1 Retaliation Damage**.
    *   **Fury**: The **Fury** bonus applies to Retaliation damage as well.

## Status Effects
*   **Terrain Bonus**: Units receive **+1 Damage** and **+1 Retaliation** when occupying a tile that matches their element (e.g., Desert unit on Desert tile).
*   **Hero Boost**: Temporary buffs granted by Hero abilities (e.g., Saladin's +1 Damage for one turn).

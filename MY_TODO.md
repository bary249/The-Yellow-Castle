Major changes! ✅ ALL COMPLETED

1. ✅ Card Move Speed:
   - Added `moveSpeed` attribute to GameCard (0, 1, or 2)
   - Updated all cards in card_library.dart with appropriate speeds
   - Tanks/Support = 0 (stationary), Warriors = 1 (normal), Quick Strikes = 2 (fast)

2. ✅ 1 Card per lane per turn:
   - UI enforces 1 card per lane per turn in staging
   - AI follows same rule

3. ✅ Cards only staged at player base:
   - UI blocks middle tile staging unless card has 'paratrooper' ability
   - AI follows same rule

4. ✅ X button to remove staged cards:
   - Added X button overlay on staged cards during staging phase
   - Calls `_removeCardFromTile()` to unstage

5. ✅ Random terrain on middle tiles:
   - GameBoard.create() now assigns random terrain (woods/lake/desert/marsh) to middle row

6. ✅ Crystal damage rework:
   - Cards can reach enemy base and STAY there (no retreat)
   - Crystal damage: uncontested attackers OR combat victory at enemy base
   - Attackers keep dealing damage each turn until pushed back

7. ✅ All applies to both players:
   - Player and opponent use same movement/crystal damage logic
   - Zone mapping correctly handles both perspectives

✅ ALL 3 MODES UPDATED:
- Simulation mode: Uses MatchManager with new logic
- Player vs AI: Uses same MatchManager + updated SimpleAI
- Online mode: Uses same logic + moveSpeed serialized in Firebase




Add Icon for each terrain in tile and on card.

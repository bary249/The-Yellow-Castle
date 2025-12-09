import '../models/hero.dart';

/// Library of all available heroes in the game.
class HeroLibrary {
  /// All heroes available for selection.
  static List<GameHero> get allHeroes => [
    napoleon(),
    saladin(),
    admiralNelson(),
    archdukeCharles(),
  ];

  /// Get a hero by ID.
  static GameHero? getHeroById(String id) {
    try {
      return allHeroes.firstWhere((h) => h.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Napoleon Bonaparte - French military commander.
  /// Affinity: Woods, Lake (European terrain)
  /// Ability: Draw 2 extra cards this turn.
  static GameHero napoleon() => GameHero(
    id: 'napoleon',
    name: 'Napoleon Bonaparte',
    description:
        'The French Emperor who conquered much of Europe through brilliant military tactics.',
    terrainAffinities: ['Woods', 'Lake'],
    abilityType: HeroAbilityType.drawCards,
    abilityDescription: 'Draw 2 extra cards this turn.',
  );

  /// Saladin - Kurdish Sultan who defended the Holy Land.
  /// Affinity: Desert
  /// Ability: Give all your units +1 damage this turn.
  static GameHero saladin() => GameHero(
    id: 'saladin',
    name: 'Saladin',
    description:
        'The Sultan of Egypt and Syria who united the Muslim world against the Crusaders.',
    terrainAffinities: ['Desert'],
    abilityType: HeroAbilityType.damageBoost,
    abilityDescription: 'Give all your units +1 damage this turn.',
  );

  /// Admiral Horatio Nelson - British naval commander.
  /// Affinity: Lake (water/naval terrain)
  /// Ability: Heal all surviving units by 3 HP.
  static GameHero admiralNelson() => GameHero(
    id: 'admiral_nelson',
    name: 'Admiral Nelson',
    description:
        'The British naval hero who defeated Napoleon\'s fleet at Trafalgar.',
    terrainAffinities: ['Lake'],
    abilityType: HeroAbilityType.healUnits,
    abilityDescription: 'Heal all surviving units by 3 HP.',
  );

  /// Archduke Charles - Austrian Field Marshal.
  /// Affinity: Woods (Alpine/Forest terrain)
  /// Ability: Deal 2 direct damage to the enemy base.
  static GameHero archdukeCharles() => GameHero(
    id: 'archduke_charles',
    name: 'Archduke Charles',
    description:
        'A capable Austrian commander and one of Napoleon\'s most formidable opponents.',
    terrainAffinities: ['Woods'],
    abilityType: HeroAbilityType.directBaseDamage,
    abilityDescription: 'Deal 2 direct damage to the enemy base.',
  );
}

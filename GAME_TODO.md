# Land of Clans & Wanderers - Development TODO

**Framework**: Flutter + Flame  
**Target**: Mobile (Portrait mode)  
**Match Duration**: 3-5 minutes  

---

## 🏗️ 1. Project Setup & Architecture

### 1.1 Project Initialization
- [ ] Create new Flutter project with Flame dependency
- [ ] Set up proper folder structure (lib/components, lib/models, lib/systems, lib/screens, lib/ui, lib/data)
- [ ] Configure pubspec.yaml with all required dependencies
  - [ ] flame (game engine)
  - [ ] flame_riverpod (state management)
  - [ ] flutter_riverpod (state management)
  - [ ] flame_audio (sound effects)
  - [ ] hive/shared_preferences (local storage)
  - [ ] json_serializable (data serialization)
  - [ ] firebase_core (Firebase SDK)
  - [ ] firebase_auth (Authentication)
  - [ ] cloud_firestore (Database)
  - [ ] firebase_analytics (Analytics)
  - [ ] firebase_crashlytics (Crash reporting)
- [ ] Set up proper asset directories (assets/images, assets/audio, assets/data)
- [ ] Create .gitignore for Flutter/Flame projects
- [ ] Initialize git repository
- [ ] Set up linting rules and analysis options

### 1.2 Architecture Design
- [ ] Design state management architecture (Riverpod providers structure)
- [ ] Create base game class extending FlameGame
- [ ] Set up game router/screen management system
- [ ] Design data layer architecture (repositories, services)
- [ ] Plan dependency injection structure
- [ ] Design event/messaging system for game events
- [ ] Create base component classes for reusable game objects
- [ ] Design **Match Mode** abstraction (Local AI vs Online PvP)
  - [ ] Shared game logic interface
  - [ ] AI opponent implementation
  - [ ] Online opponent implementation
  - [ ] Mode selection at match start

### 1.3 Firebase Configuration
- [ ] Create Firebase project in Firebase Console
- [ ] Add Android app to Firebase project
  - [ ] Download google-services.json
  - [ ] Configure android/app/build.gradle
  - [ ] Add to android/app/ directory
- [ ] Add iOS app to Firebase project (if applicable)
  - [ ] Download GoogleService-Info.plist
  - [ ] Configure iOS project in Xcode
  - [ ] Add to ios/Runner/ directory
- [ ] Initialize Firebase in main.dart
  - [ ] Call Firebase.initializeApp() before runApp
  - [ ] Handle initialization errors
- [ ] Set up Firebase Authentication
  - [ ] Enable email/password provider
  - [ ] Enable Google Sign-In provider
  - [ ] Enable Apple Sign-In (iOS requirement)
  - [ ] Set up anonymous authentication (for guest play)
- [ ] Configure Firestore Database
  - [ ] Choose region
  - [ ] Set up initial security rules (start in test mode, lock down later)
- [ ] Enable Firebase Analytics
- [ ] Enable Firebase Crashlytics
- [ ] Set up environment variables for dev/prod Firebase projects

---

## 📊 2. Data Models & Structures

### 2.1 Core Game Models
- [ ] Create **Card** model
  - [ ] id, name, type (general/character)
  - [ ] damage, health, tick (1-5)
  - [ ] element (nullable)
  - [ ] character family (nullable)
  - [ ] variation (1-3 for character cards)
  - [ ] skills/abilities list
  - [ ] rarity, cost metadata
  - [ ] JSON serialization/deserialization
- [ ] Create **Deck** model
  - [ ] 25-card list
  - [ ] deck name, id
  - [ ] assigned hero
  - [ ] element configuration
  - [ ] validation logic (max 25 cards)
- [ ] Create **Hero** model
  - [ ] id, name, description
  - [ ] 2 ability definitions
  - [ ] ability cooldowns/charges
  - [ ] visual/animation data
- [ ] Create **Element** enum (Fire, Water, Grass, etc.)
  - [ ] Element strength/weakness matrix
  - [ ] Buff/debuff calculations
- [ ] Create **Lane** model
  - [ ] Lane position (left/center/right)
  - [ ] Current zone (player base, middle, enemy base)
  - [ ] Tier (1 or 2)
- [ ] Create **Crystal** model
  - [ ] HP (current/max)
  - [ ] Element affinity
  - [ ] Visual state
- [ ] Create **PlayerState** model
  - [ ] Hand (List<Card>, max 8-9)
  - [ ] Deck (remaining cards)
  - [ ] Gold (current match)
  - [ ] Win streak counter
  - [ ] Submitted moves per lane

### 2.2 Combat Models
- [ ] Create **CardPlacement** model
  - [ ] Lane (left/center/right)
  - [ ] Position (top/bottom stack)
  - [ ] Card reference
- [ ] Create **CombatStack** model
  - [ ] Top card (active)
  - [ ] Bottom card (backup)
  - [ ] Owner (player/opponent)
- [ ] Create **TickAction** model
  - [ ] Card reference
  - [ ] Action type (attack, skill, etc.)
  - [ ] Target
  - [ ] Damage value
- [ ] Create **CombatLog** model
  - [ ] Tick-by-tick action records
  - [ ] Damage dealt/taken
  - [ ] Card deaths
  - [ ] Overflow damage tracking

### 2.3 Character System
- [ ] Create **CharacterFamily** enum (Monkey, Ant, etc.)
- [ ] Create **CharacterVariation** model
  - [ ] Variation number (1-3)
  - [ ] Skills unique to variation
- [ ] Create **Ultimate** ability model
  - [ ] Trigger condition (3 variations played)
  - [ ] Effect definition
  - [ ] Visual/animation data

### 2.4 Online Multiplayer Models (Firebase)
- [ ] Create **Player** model (Firestore document)
  - [ ] userId (Firebase Auth UID)
  - [ ] displayName
  - [ ] photoURL
  - [ ] elo/rank/rating
  - [ ] winCount, lossCount
  - [ ] cardCollection (owned cards)
  - [ ] deckSlots (multiple saved decks)
  - [ ] gold/currency
  - [ ] lastActive timestamp
  - [ ] JSON serialization for Firestore
- [ ] Create **OnlineMatch** model (Firestore document)
  - [ ] matchId (unique)
  - [ ] player1Id, player2Id
  - [ ] player1Deck, player2Deck
  - [ ] currentTurn (turn counter)
  - [ ] currentPhase (setup/turn/combat/advancement)
  - [ ] turnStartTime (for 8-second timer)
  - [ ] player1Moves, player2Moves (submitted each turn)
  - [ ] matchStatus (waiting/in_progress/completed)
  - [ ] winnerId
  - [ ] createdAt, updatedAt timestamps
  - [ ] matchLog (complete action history for replay)
- [ ] Create **TurnSubmission** model
  - [ ] playerId
  - [ ] turnNumber
  - [ ] placements (List<CardPlacement>)
  - [ ] heroAbilities used
  - [ ] submittedAt timestamp
- [ ] Create **MatchmakingQueue** model
  - [ ] playerId
  - [ ] deckId
  - [ ] eloRange
  - [ ] joinedAt timestamp
  - [ ] status (searching/matched)

---

## 🎮 3. Core Game Systems

### 3.1 Match Flow System
- [ ] Create **MatchManager** service
  - [ ] Initialize match with 2 decks
  - [ ] Handle match start sequence
  - [ ] Manage turn phases
  - [ ] Handle match end conditions
  - [ ] Calculate victory/defeat
- [ ] Implement **Turn Timer** (8 seconds)
  - [ ] Countdown display
  - [ ] Auto-submit on timeout
  - [ ] Visual/audio warnings
- [ ] Create **Phase Manager**
  - [ ] Setup Phase (draw initial 6 cards)
  - [ ] Turn Phase (player input, 8s timer)
  - [ ] Combat Phase (resolve all lanes)
  - [ ] Advancement Phase (move winning cards)
  - [ ] Draw Phase (draw 2 cards)

### 3.2 Combat Resolution System
- [ ] Create **CombatResolver** service
  - [ ] Process all 3 lanes sequentially
  - [ ] Implement tick system (1-5)
  - [ ] Handle simultaneous card actions within ticks
  - [ ] Calculate damage with element modifiers
  - [ ] Apply overflow damage rules
  - [ ] Track card deaths
  - [ ] Award gold for destroyed cards (50-200)
- [ ] Implement **Tick Scheduler**
  - [ ] Tick 1 cards act on ticks 1,2,3,4,5
  - [ ] Tick 2 cards act on ticks 2,4
  - [ ] Tick 3-5 cards act once at their tick
  - [ ] Handle simultaneous actions per tick
- [ ] Create **Damage Calculator**
  - [ ] Base damage from card stats
  - [ ] Element advantage/disadvantage modifiers
  - [ ] Zone-based buffs (frontline element)
  - [ ] Hero ability modifiers
  - [ ] Overflow damage to next card in stack
- [ ] Implement **Card Activation Rules**
  - [ ] Top card is always active
  - [ ] Bottom card activates only at tick start (not mid-tick)
  - [ ] Handle card death and stack updates

### 3.3 Lane Advancement System
- [ ] Create **LaneController** for each lane
  - [ ] Track current zone per lane
  - [ ] Handle zone transitions
  - [ ] Award gold for tier capture (400)
  - [ ] Manage card advancement rules
- [ ] Implement **Zone Progression**
  - [ ] Player Base → Tier 1 → Tier 2 → Enemy Crystal
  - [ ] Mirror logic for opponent
  - [ ] Visual representation per lane
  - [ ] Independent progression per lane

### 3.4 Card Draw System
- [ ] Create **DeckManager** service
  - [ ] Shuffle deck at match start
  - [ ] Draw initial 6 cards
  - [ ] Draw 2 cards per round
  - [ ] Handle empty deck scenario
  - [ ] NO mid-match reshuffle
  - [ ] Enforce hand limit (8 cards, possibly 9)
  - [ ] Discard excess cards if needed

### 3.5 Gold & Economy System
- [ ] Create **GoldManager** service
  - [ ] Track gold earned during battle
  - [ ] Card destruction: 50-200 gold
  - [ ] Tier capture: 400 gold
  - [ ] Win streak bonuses: 100 gold
  - [ ] Calculate 25% carryover for post-match shop
  - [ ] Display gold counter in UI

### 3.6 Element System
- [ ] Create **ElementManager** service
  - [ ] Define element types (Fire, Water, Grass, etc.)
  - [ ] Implement strength/weakness matrix
  - [ ] Calculate buffs for matching elements
  - [ ] Calculate debuffs for opposing elements
  - [ ] Handle neutral zone (middle)
  - [ ] Allow element switching outside combat (gold cost)
- [ ] Create element visual effects
  - [ ] Zone background tinting
  - [ ] Card glow when buffed
  - [ ] Damage number colors

### 3.7 Hero Ability System
- [ ] Create **HeroManager** service
  - [ ] Track hero assigned to deck
  - [ ] Manage 2 ability charges per combat
  - [ ] Handle ability activation
  - [ ] Apply ability effects (buffs, heals, draws, etc.)
  - [ ] Cooldown/charge tracking
  - [ ] Heroes cannot be killed
- [ ] Implement hero abilities
  - [ ] Buff elemental cards
  - [ ] Heal crystal
  - [ ] Extra card draws
  - [ ] Damage boosts
  - [ ] Defensive shields
  - [ ] AOE effects

### 3.8 Character Ultimate System
- [ ] Create **UltimateTracker** service
  - [ ] Track variations played per character family
  - [ ] Detect when all 3 variations are played
  - [ ] Trigger ultimate ability
  - [ ] Apply ultimate effects
  - [ ] Visual/audio feedback

### 3.9 Anti-Snowball System
- [ ] Design comeback mechanics
  - [ ] Special cards available when behind
  - [ ] Bonus effects when losing
  - [ ] Defensive buffs when crystal low
- [ ] Implement strategic losing mechanics
  - [ ] Allow intentional tier losses
  - [ ] Reward delayed strategies

---

## 🎨 4. Visual Assets & UI Components

### 4.1 Card Visuals
- [ ] **Design card frame template** (mark if copyrighted, replace later)
  - [ ] General card frame
  - [ ] Character card frame (with element indicator)
  - [ ] Rare/epic/legendary variants
- [ ] **Create card art placeholders** (FREE to use or marked)
  - [ ] Use placeholder illustrations initially
  - [ ] Mark all copyrighted images for replacement
  - [ ] Source free assets from OpenGameArt, Kenney.nl, itch.io
- [ ] **Create card stat UI**
  - [ ] Damage indicator
  - [ ] Health indicator
  - [ ] Tick number badge
  - [ ] Element icon
  - [ ] Character family icon
- [ ] Implement card glow/highlight states
  - [ ] Selected state
  - [ ] Playable state
  - [ ] Buffed state
  - [ ] Weakened state

### 4.2 Lane & Zone Visuals
- [ ] **Create zone backgrounds** (3 zones × 2 players)
  - [ ] Player Base (element-based)
  - [ ] Middle (neutral)
  - [ ] Enemy Base (element-based)
  - [ ] Use FREE tiled backgrounds or procedural generation
- [ ] **Create lane dividers/borders**
  - [ ] Visual separation between 3 lanes
  - [ ] Highlight active lane
- [ ] **Create crystal visuals**
  - [ ] HP bar
  - [ ] Element-based glow/color
  - [ ] Damage effects
  - [ ] Low HP warning state
- [ ] **Create progression indicators**
  - [ ] Mini-map or lane tracker
  - [ ] Zone labels (Player Base, Middle, Enemy Base)
  - [ ] Tier indicators

### 4.3 Hero Visuals
- [ ] **Design hero portraits** (mark if copyrighted)
  - [ ] Use free character generators or placeholder silhouettes
  - [ ] Mark for custom art replacement
- [ ] **Create hero ability icons** (2 per hero)
  - [ ] Use free icon sets (Font Awesome, Material Icons)
  - [ ] Ability cooldown overlay
  - [ ] Activated state

### 4.4 UI Elements
- [ ] **Create main menu screen**
  - [ ] Play button
  - [ ] Deck builder button
  - [ ] Collection button
  - [ ] Settings button
  - [ ] Background (FREE or procedural)
- [ ] **Create battle UI overlay**
  - [ ] Turn timer (circular or bar)
  - [ ] Gold counter
  - [ ] Crystal HP (player & opponent)
  - [ ] Win streak indicator
  - [ ] "Start Combat" button
  - [ ] Hero ability buttons
- [ ] **Create hand UI**
  - [ ] Horizontal scrollable card list
  - [ ] Collapsible option
  - [ ] Card count indicator
  - [ ] Deck remaining count
- [ ] **Create combat log UI**
  - [ ] Scrollable action feed
  - [ ] Tick-by-tick breakdown
  - [ ] Damage numbers
  - [ ] Card death notifications
- [ ] **Create end-match screen**
  - [ ] Victory/defeat banner
  - [ ] Match summary
  - [ ] Gold earned
  - [ ] Rematch/return to menu buttons
- [ ] **Create deck builder UI**
  - [ ] Card collection grid
  - [ ] Current deck list (25 max)
  - [ ] Filter by element, type, rarity
  - [ ] Hero selection
  - [ ] Save/load deck
- [ ] **Create post-match shop UI**
  - [ ] Available cards/items
  - [ ] Gold from match (25% carryover)
  - [ ] Purchase flow

### 4.5 Visual Effects (VFX)
- [ ] **Card play animations**
  - [ ] Card slide from hand to lane
  - [ ] Card flip animation
  - [ ] Card glow on placement
- [ ] **Combat animations**
  - [ ] Attack swipe/slash effects
  - [ ] Damage numbers (floating text)
  - [ ] Card death/destruction effect
  - [ ] Overflow damage indicator
- [ ] **Element effect particles**
  - [ ] Fire: flames, embers
  - [ ] Water: droplets, waves
  - [ ] Grass: leaves, vines
  - [ ] Use Flame particle system or FREE sprite sheets
- [ ] **Hero ability effects**
  - [ ] Buff glow/aura
  - [ ] Heal sparkles
  - [ ] AOE blast radius
- [ ] **Lane advancement effects**
  - [ ] Card march-forward animation
  - [ ] Zone transition fade
  - [ ] Tier capture fanfare
- [ ] **UI transitions**
  - [ ] Screen fade in/out
  - [ ] Button press animations
  - [ ] Modal pop-ups

---

## 🔊 5. Audio & Sound Design

### 5.1 Sound Effects (FREE or marked)
- [ ] **Card sounds**
  - [ ] Card draw sound
  - [ ] Card play/placement sound
  - [ ] Card flip sound
  - [ ] Card destruction sound
- [ ] **Combat sounds**
  - [ ] Attack/hit sounds (varied by damage)
  - [ ] Critical hit sound
  - [ ] Card death sound
  - [ ] Overflow damage sound
- [ ] **UI sounds**
  - [ ] Button click
  - [ ] Timer tick/warning
  - [ ] Menu navigation
  - [ ] Confirm/cancel sounds
- [ ] **Hero ability sounds**
  - [ ] Ability activation (unique per hero)
  - [ ] Buff applied sound
  - [ ] Ultimate trigger sound
- [ ] **Ambient sounds**
  - [ ] Background battle ambience
  - [ ] Crystal hum
  - [ ] Win/lose stingers
- [ ] **Source FREE sounds**
  - [ ] Freesound.org
  - [ ] OpenGameArt.org
  - [ ] Kenney.nl
  - [ ] Mark copyrighted sounds for replacement

### 5.2 Music (FREE or marked)
- [ ] **Menu music** (looping)
  - [ ] Use FREE music from incompetech.com, freemusicarchive.org
- [ ] **Battle music** (looping, 3-5 min)
  - [ ] Tension/action theme
  - [ ] Adaptive layers based on match state
- [ ] **Victory/defeat themes**
  - [ ] Short victory fanfare
  - [ ] Defeat theme
- [ ] **Mark all music sources** and licensing requirements

---

## 🧪 6. Game Components (Flame)

### 6.1 Base Components
- [ ] Create **GameWorld** (FlameGame)
  - [ ] Camera setup (portrait orientation)
  - [ ] Background rendering
  - [ ] Component management
- [ ] Create **CardComponent** (PositionComponent)
  - [ ] Visual rendering (sprite/custom paint)
  - [ ] Drag detection
  - [ ] Tap detection
  - [ ] Animation controller
  - [ ] Health bar overlay
- [ ] Create **LaneComponent** (PositionComponent)
  - [ ] Zone background
  - [ ] Card slots (top/bottom)
  - [ ] Drop zone detection
  - [ ] Progression indicator
- [ ] Create **CrystalComponent** (SpriteComponent)
  - [ ] HP bar
  - [ ] Damage flash animation
  - [ ] Element glow effect
- [ ] Create **HeroAbilityButton** (ButtonComponent)
  - [ ] Icon sprite
  - [ ] Cooldown overlay
  - [ ] Tap handler

### 6.2 UI Components (Flame)
- [ ] Create **HandWidget** (Flutter widget overlay)
  - [ ] Horizontal card list
  - [ ] Drag-to-play gesture
  - [ ] Collapsible animation
- [ ] Create **TimerWidget** (Flutter widget)
  - [ ] Circular countdown
  - [ ] Warning colors (last 3 seconds)
  - [ ] Sound trigger
- [ ] Create **GoldDisplay** (Flutter widget)
  - [ ] Animated counter
  - [ ] Gold gain popup
- [ ] Create **CombatLogOverlay** (Flutter widget)
  - [ ] Scrollable list view
  - [ ] Formatted action text
  - [ ] Auto-scroll to latest

### 6.3 Animation Controllers
- [ ] Create **CardAnimator**
  - [ ] Play animation (hand → lane)
  - [ ] Attack animation
  - [ ] Death animation
  - [ ] Idle animation
- [ ] Create **CombatAnimator**
  - [ ] Tick-by-tick sequencing
  - [ ] Damage number spawner
  - [ ] Simultaneous action handler
- [ ] Create **TransitionAnimator**
  - [ ] Zone advancement
  - [ ] Lane progression
  - [ ] Phase transitions

---

## 🧠 7. AI & Opponent Logic

### 7.1 Basic AI
- [ ] Create **AIController** service
  - [ ] Card selection logic
  - [ ] Lane targeting strategy
  - [ ] Hero ability usage
  - [ ] Difficulty levels (easy, medium, hard)
- [ ] Implement AI strategies
  - [ ] Aggressive (rush enemy crystal)
  - [ ] Defensive (protect own crystal)
  - [ ] Balanced (adaptive)
  - [ ] Counter-play (respond to player moves)
- [ ] AI card evaluation
  - [ ] Calculate card value (damage, health, tick)
  - [ ] Evaluate lane states
  - [ ] Prioritize targets
  - [ ] Element advantage consideration

### 7.2 Online Multiplayer System (Firebase)

#### 7.2.1 Authentication & User Management
- [ ] Create **AuthService**
  - [ ] Sign up with email/password
  - [ ] Sign in with email/password
  - [ ] Sign in with Google
  - [ ] Sign in with Apple
  - [ ] Anonymous sign-in (guest mode)
  - [ ] Sign out
  - [ ] Handle auth state changes
  - [ ] Password reset
- [ ] Create **UserService** (Firestore)
  - [ ] Create user profile on first login
  - [ ] Update user profile (displayName, photoURL)
  - [ ] Fetch user profile
  - [ ] Listen to user profile changes
  - [ ] Update last active timestamp
  
#### 7.2.2 Matchmaking System
- [ ] Create **MatchmakingService**
  - [ ] Join matchmaking queue (write to Firestore)
  - [ ] Match players with similar ELO (±100-200 range)
  - [ ] Create OnlineMatch document when 2 players found
  - [ ] Remove players from queue when matched
  - [ ] Handle queue timeout (30-60 seconds)
  - [ ] Cancel matchmaking
  - [ ] Listen for match found event
- [ ] Implement **ELO rating system**
  - [ ] Calculate rating changes post-match
  - [ ] Update player ratings in Firestore
  - [ ] Display player rank/tier
- [ ] Create matchmaking UI
  - [ ] "Find Match" button
  - [ ] "Searching for opponent..." spinner
  - [ ] Estimated wait time
  - [ ] Cancel button
  
#### 7.2.3 Real-time Match Synchronization
- [ ] Create **OnlineMatchService**
  - [ ] Listen to OnlineMatch document changes
  - [ ] Submit turn moves to Firestore
  - [ ] Detect when both players submitted
  - [ ] Trigger combat resolution
  - [ ] Update match state after combat
  - [ ] Handle player disconnection
  - [ ] Handle match completion
  - [ ] Update player stats (wins/losses)
- [ ] Implement **Turn Synchronization**
  - [ ] Start 8-second timer when turn phase begins
  - [ ] Auto-submit empty moves on timeout
  - [ ] Lock UI when waiting for opponent
  - [ ] Show opponent "submitted" indicator
  - [ ] Ensure both players see same game state
- [ ] Implement **Combat Resolution** (server-side logic)
  - [ ] Use Cloud Functions or client-side with validation
  - [ ] Ensure deterministic combat (same inputs = same outputs)
  - [ ] Write combat log to Firestore
  - [ ] Update match state atomically
  
#### 7.2.4 Anti-Cheat & Validation
- [ ] **Firestore Security Rules**
  - [ ] Players can only read their own profile
  - [ ] Players can only update their own allowed fields
  - [ ] Players cannot modify ELO directly
  - [ ] Players can only write to matchmaking queue as themselves
  - [ ] Players can only submit moves for their own matches
  - [ ] Match results can only be written by server/cloud function
- [ ] **Server-side validation** (Cloud Functions - optional but recommended)
  - [ ] Validate deck composition (25 cards, 1 hero)
  - [ ] Validate card placements (2 per lane max)
  - [ ] Validate hero ability usage (2 per match)
  - [ ] Recalculate combat on server to prevent manipulation
  - [ ] Detect impossible game states
- [ ] **Client-side checks**
  - [ ] Validate all inputs before sending to Firestore
  - [ ] Checksum/hash game state
  - [ ] Detect network tampering
  
#### 7.2.5 Reconnection & Error Handling
- [ ] Handle **player disconnection**
  - [ ] Detect disconnect via Firestore presence system
  - [ ] Give opponent 30-60 second grace period
  - [ ] Award win to connected player if opponent doesn't return
  - [ ] Allow reconnection if match still active
  - [ ] Restore game state on reconnect
- [ ] Handle **network errors**
  - [ ] Retry failed Firestore writes
  - [ ] Show connection status indicator
  - [ ] Queue moves locally if offline
  - [ ] Sync when connection restored
- [ ] Handle **match abandonment**
  - [ ] Penalize players who quit early (ELO/ranking)
  - [ ] Track quit rate
  - [ ] Temporary bans for repeat quitters

---

## 💾 8. Data Management & Persistence

### 8.1 Local Storage
- [ ] Set up Hive/SharedPreferences
- [ ] Save player decks
- [ ] Save collection (owned cards)
- [ ] Save gold/currency
- [ ] Save settings (sound, music, language)
- [ ] Save match history
- [ ] Save tutorial completion flags

### 8.2 Card Database
- [ ] Create JSON card definitions
  - [ ] General cards (20-30)
  - [ ] Character cards (5-10 families × 3 variations)
  - [ ] Ultimate abilities
- [ ] Create JSON hero definitions
  - [ ] 5-10 heroes with 2 abilities each
- [ ] Create repository pattern for data access
- [ ] Implement card unlocking system
- [ ] Implement rarity system

### 8.3 Deck Management
- [ ] Create DeckRepository
  - [ ] Save/load decks locally (Hive)
  - [ ] Save/load decks from Firebase (cloud sync)
  - [ ] Validate deck (25 cards, 1 hero)
  - [ ] Multiple deck slots (3-5 slots)
  - [ ] Deck naming
  - [ ] Deck export/import (future)
  - [ ] Sync local and cloud decks

### 8.4 Firebase Cloud Storage
- [ ] Create **FirebasePlayerRepository**
  - [ ] Sync player profile to Firestore
  - [ ] Sync card collection to Firestore
  - [ ] Sync decks to Firestore
  - [ ] Sync gold/currency to Firestore
  - [ ] Handle offline mode (cache locally, sync when online)
  - [ ] Resolve conflicts (local vs cloud data)
- [ ] Implement **Cloud Save System**
  - [ ] Auto-save to cloud every X minutes
  - [ ] Manual "Sync Now" button
  - [ ] Show sync status indicator
  - [ ] Download cloud save on new device login
  - [ ] Merge local + cloud data intelligently
- [ ] Create **Firestore Collections Structure**
  - [ ] `/players/{userId}` - player profile
  - [ ] `/players/{userId}/decks/{deckId}` - subcollection for decks
  - [ ] `/players/{userId}/collection` - owned cards
  - [ ] `/matches/{matchId}` - online match documents
  - [ ] `/matchmaking/{playerId}` - matchmaking queue
  - [ ] `/leaderboard/{season}` - ranked ladder

---

## 🎓 9. Tutorial & Onboarding

### 9.1 First-Time Experience
- [ ] Create welcome screen
- [ ] Create interactive tutorial
  - [ ] Explain 3 lanes
  - [ ] Explain zones (base, middle, enemy)
  - [ ] Explain card placement (2 per lane, top/bottom)
  - [ ] Explain turn timer
  - [ ] Explain combat ticks
  - [ ] Explain overflow damage
  - [ ] Explain advancement
  - [ ] Explain hero abilities
- [ ] Create practice match against AI
- [ ] Create tooltips for UI elements
- [ ] Create help menu with rules

### 9.2 Progressive Disclosure
- [ ] Unlock features gradually
  - [ ] Basic cards → Character cards → Heroes
  - [ ] Basic deck → Multiple decks
  - [ ] Element system explanation
  - [ ] Ultimate abilities

---

## 🧪 10. Testing & Quality Assurance

### 10.1 Unit Tests
- [ ] Test card models
- [ ] Test combat resolver logic
- [ ] Test damage calculator
- [ ] Test overflow damage
- [ ] Test tick scheduler
- [ ] Test deck validation
- [ ] Test gold calculations
- [ ] Test element system
- [ ] Test hero abilities
- [ ] Test ultimate triggers

### 10.2 Integration Tests
- [ ] Test full match flow
- [ ] Test turn phases
- [ ] Test lane advancement
- [ ] Test AI behavior
- [ ] Test deck builder
- [ ] Test data persistence

### 10.3 Widget Tests
- [ ] Test UI components
- [ ] Test card drag-and-drop
- [ ] Test button interactions
- [ ] Test timer countdown
- [ ] Test hand management

### 10.4 Performance Testing
- [ ] Profile game loop performance
- [ ] Optimize rendering (60 FPS target)
- [ ] Test on low-end devices
- [ ] Memory leak detection
- [ ] Battery consumption testing

### 10.5 Playtest & Balance
- [ ] Internal playtesting
- [ ] Card balance tuning
- [ ] Match duration validation (3-5 min)
- [ ] Difficulty curve testing
- [ ] Snowball/comeback balance
- [ ] Hero ability balance

---

## ✨ 11. Polish & Juice

### 11.1 Visual Polish
- [ ] Screen shake on heavy hits
- [ ] Card bounce on play
- [ ] Smooth lane scrolling
- [ ] Particle effects on special moves
- [ ] Victory/defeat screen animations
- [ ] Loading screen with tips
- [ ] Consistent art style

### 11.2 Audio Polish
- [ ] Dynamic music layers
- [ ] Context-aware sound effects
- [ ] Audio mixing (balance levels)
- [ ] Victory/defeat voice lines (optional)

### 11.3 UX Enhancements
- [ ] Haptic feedback on card play
- [ ] Visual feedback for all actions
- [ ] Clear error messages
- [ ] Undo button (during turn phase)
- [ ] Confirm dialog for important actions
- [ ] Accessibility features (colorblind mode, text size)

---

## 🚀 12. Build & Release Preparation

### 12.1 Platform Configuration
- [ ] Configure Android build
  - [ ] App icons
  - [ ] Splash screen
  - [ ] Permissions
  - [ ] Signing keys
- [ ] Configure iOS build (if applicable)
  - [ ] App icons
  - [ ] Splash screen
  - [ ] Certificates
  - [ ] Provisioning profiles

### 12.2 Optimization
- [ ] Reduce app size (asset compression)
- [ ] Optimize images (WebP format)
- [ ] Code obfuscation
- [ ] Remove debug code
- [ ] Minimize dependencies

### 12.3 Marketing Assets
- [ ] Create app store screenshots
- [ ] Write app description
- [ ] Create promotional video
- [ ] Design app icon
- [ ] Create privacy policy
- [ ] Create terms of service

### 12.4 Release
- [ ] Beta testing (TestFlight, Google Play Beta)
- [ ] Bug fixes from beta feedback
- [ ] Final QA pass
- [ ] Submit to Google Play Store
- [ ] Submit to Apple App Store (if applicable)

---

## 📝 13. Documentation

### 13.1 Code Documentation
- [ ] Document all public APIs
- [ ] Create architecture diagram
- [ ] Document state management flow
- [ ] Create component hierarchy diagram
- [ ] Document data models

### 13.2 Game Design Documentation
- [ ] Finalize game rules document
- [ ] Create card database spreadsheet
- [ ] Document hero abilities
- [ ] Document element system
- [ ] Create balance notes

### 13.3 Asset Documentation
- [ ] List all asset sources
- [ ] Document licenses for FREE assets
- [ ] Mark copyrighted assets for replacement
- [ ] Create asset replacement checklist

---

## 🔄 14. Post-Launch

### 14.1 Live Operations
- [ ] Monitor crash reports
- [ ] Track player analytics
- [ ] Gather user feedback
- [ ] Plan content updates

### 14.2 Future Features
- [ ] MOBA-style modes (per vision)
- [ ] Clan system
- [ ] Ranked ladder
- [ ] Seasonal events
- [ ] New card sets
- [ ] New heroes
- [ ] Cosmetic skins

---

## 📋 Priority Phases (With Online Multiplayer)

### **Phase 1: Core Prototype + Firebase Setup** (Weeks 1-4)
- ✅ Project setup with Flutter + Flame
- ⏸️ Firebase project creation and configuration (deferred)
- ⏸️ Basic authentication (email/password, anonymous) (deferred)
- ⏸️ Firestore setup with initial security rules (deferred)
- ✅ Basic data models (Card, Deck, Lane, Player, MatchState)
- ✅ Simple combat resolver (tick system, overflow damage)
- ✅ 3-lane UI with card placement (click-to-place)
- ✅ Win/lose conditions
- ✅ **Local AI opponent** (for testing core mechanics)
- ✅ **Battle log system** (on-screen + terminal output)

### **Phase 2: Combat Depth + Cloud Sync** (Weeks 5-8)
- ✅ Full tick system implementation
- ✅ Overflow damage
- 🔄 **Lane advancement & zones (base → middle → enemy base)** (IN PROGRESS)
- [ ] **Simple per-tick visualization of card battles and lane victory**
- [ ] Gold system
- [ ] Element system basics
- ⏸️ **Player profile system (Firestore)** (deferred)
- ⏸️ **Cloud save/sync for decks and collection** (deferred)
- ⏸️ **Offline mode support** (deferred)

### **Phase 3: Content & Online Foundation** (Weeks 9-12)
- Hero abilities
- Character ultimates
- Full card database (25+ cards)
- Deck builder UI with cloud sync
- **Matchmaking system (ELO-based)**
- **Real-time match synchronization**
- **Basic online PvP (MVP)**
- **Anti-cheat validation (security rules)**

### **Phase 4: Online Features & Polish** (Weeks 13-16)
- **Reconnection handling**
- **Leaderboard system**
- **Match history and replays**
- Visual effects
- Audio implementation
- Tutorial system
- Playtesting & balance (both AI and PvP)
- Performance optimization
- **Server-side combat validation (Cloud Functions - optional)**

### **Phase 5: Beta & Release** (Weeks 17-20)
- **Closed beta with real players**
- Bug fixes from beta feedback
- **Anti-cheat refinements**
- **ELO system balancing**
- Asset replacement (copyrighted → original/free)
- Final QA pass
- Store submission (Android, iOS)
- Launch!

### **Phase 6: Post-Launch (Ongoing)**
- Monitor server costs and optimize Firestore usage
- Track player analytics (Firebase Analytics)
- Balance patches based on data
- New card sets (seasons)
- Ranked seasons/ladders
- Social features (friend lists, clans)
- Tournaments/events
- Potential MOBA mode (future vision)

---

### **Firebase Cost Considerations**
- **Free Tier Limits**:
  - 50K document reads/day
  - 20K document writes/day
  - 20K document deletes/day
  - 1 GiB stored data
  - 10 GiB/month network egress
- **Estimated Usage Per Match** (3-5 min):
  - ~10-15 writes (turn submissions, match updates)
  - ~20-30 reads (listening to match state)
- **For 1000 daily active users**:
  - ~5-10 matches per user = 5K-10K matches/day
  - ~50K-150K writes/day (may exceed free tier)
  - **Plan to upgrade to Blaze (pay-as-you-go) early**
  - Estimated cost: $5-$20/month for 1K DAU

### **Development Notes**
- **Build local AI first** to test game mechanics without Firebase costs
- **Test online with friends** before open beta to validate matchmaking
- **Implement Firestore security rules early** to prevent exploits
- **Monitor Firebase usage dashboard** regularly to avoid surprise bills
- **Consider Cloud Functions** for combat validation if cheating becomes an issue

---

**Total Estimated Timeline**: 4-5 months for initial release with online multiplayer  
**Key Dependencies**: Firebase setup, matchmaking logic, asset creation, anti-cheat validation, playtesting feedback

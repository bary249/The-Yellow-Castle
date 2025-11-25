# 🎮 Multiplayer Implementation Plan

## Overview
Implement real-time online multiplayer using Firebase (Firestore + Authentication).

---

## 📋 Phase 1: Firebase Foundation (Week 1)

### Step 1.1: Firebase Project Setup
- [ ] Create Firebase project in console
- [ ] Add Flutter app (Android + iOS)
- [ ] Download `google-services.json` (Android)
- [ ] Download `GoogleService-Info.plist` (iOS)
- [ ] Add Firebase dependencies to `pubspec.yaml`

**Dependencies needed:**
```yaml
firebase_core: ^2.24.0
firebase_auth: ^4.15.0
cloud_firestore: ^4.13.0
firebase_analytics: ^10.7.0 (optional)
```

### Step 1.2: Authentication Setup
- [ ] Initialize Firebase in `main.dart`
- [ ] Create `AuthService` class
- [ ] Implement anonymous authentication (fast onboarding)
- [ ] Add optional email/password upgrade
- [ ] Store user profile in Firestore

**User Profile Structure:**
```dart
{
  userId: string,
  displayName: string?,
  email: string?,
  elo: number (default: 1000),
  gamesPlayed: number,
  wins: number,
  losses: number,
  createdAt: timestamp
}
```

---

## 📋 Phase 2: Firestore Data Models (Week 1-2)

### Step 2.1: Match Document Structure
```dart
{
  matchId: string,
  status: 'waiting' | 'active' | 'completed',
  createdAt: timestamp,
  updatedAt: timestamp,
  
  player1: {
    userId: string,
    displayName: string,
    elo: number,
    ready: boolean,
    submitted: boolean,
    crystalHP: number,
    gold: number
  },
  
  player2: {
    userId: string,
    displayName: string,
    elo: number,
    ready: boolean,
    submitted: boolean,
    crystalHP: number,
    gold: number
  },
  
  turnNumber: number,
  currentPhase: 'placement' | 'combat' | 'ended',
  
  lanes: {
    left: { zone: string, ... },
    center: { zone: string, ... },
    right: { zone: string, ... }
  },
  
  winner: string?,
  disconnected: string[]
}
```

### Step 2.2: Turn Submission Structure
```dart
// Subcollection: matches/{matchId}/turns/{turnNumber}
{
  turnNumber: number,
  player1Moves: {
    left: [cardData],
    center: [cardData],
    right: [cardData]
  },
  player2Moves: {
    left: [cardData],
    center: [cardData],
    right: [cardData]
  },
  combatLog: [...],
  timestamp: timestamp
}
```

---

## 📋 Phase 3: Match Services (Week 2-3)

### Step 3.1: OnlineMatchManager
- [ ] Extend current `MatchManager` or create `OnlineMatchManager`
- [ ] Create match in Firestore
- [ ] Join existing match
- [ ] Listen to match updates (real-time)
- [ ] Submit turn to Firestore
- [ ] Wait for opponent submission
- [ ] Trigger combat when both submitted

### Step 3.2: Matchmaking Service
- [ ] Create "matchmaking queue" collection
- [ ] Add player to queue
- [ ] Match players by ELO (±100 range)
- [ ] Create match document when pair found
- [ ] Remove from queue when matched

**Queue Document:**
```dart
{
  userId: string,
  elo: number,
  timestamp: timestamp,
  searching: boolean
}
```

---

## 📋 Phase 4: Security & Anti-Cheat (Week 3)

### Step 4.1: Firestore Security Rules
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // User profiles
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }
    
    // Matches
    match /matches/{matchId} {
      allow read: if request.auth.uid in resource.data.playerIds;
      allow create: if request.auth != null;
      allow update: if request.auth.uid in resource.data.playerIds
                    && validateTurnSubmission(request.resource.data);
    }
    
    // Turn submissions
    match /matches/{matchId}/turns/{turnId} {
      allow read: if request.auth.uid in get(/databases/$(database)/documents/matches/$(matchId)).data.playerIds;
      allow create: if request.auth.uid in get(/databases/$(database)/documents/matches/$(matchId)).data.playerIds;
    }
  }
  
  function validateTurnSubmission(data) {
    // Validate card placements don't exceed limits
    // Validate cards are in player's deck
    // Validate turn timing
    return true; // Implement validation logic
  }
}
```

### Step 4.2: Client-Side Validation
- [ ] Validate all moves before submission
- [ ] Check card ownership
- [ ] Verify lane placement rules
- [ ] Ensure turn order

### Step 4.3: Server-Side Validation (Optional - Cloud Functions)
- [ ] Validate combat resolution
- [ ] Prevent tampering with HP/damage
- [ ] Detect disconnects vs intentional quits

---

## 📋 Phase 5: UI Updates (Week 3-4)

### Step 5.1: Main Menu
- [ ] Add "Play Online" button
- [ ] Add "Play vs AI" button
- [ ] Show user profile (username, ELO)
- [ ] Add settings (logout, account)

### Step 5.2: Matchmaking Screen
- [ ] Show "Searching for opponent..." animation
- [ ] Display estimated wait time
- [ ] Show ELO range
- [ ] Cancel search button

### Step 5.3: Online Match Screen
- [ ] Show opponent info (name, ELO)
- [ ] Display "Waiting for opponent..." during their turn
- [ ] Show connection status indicator
- [ ] Add surrender button
- [ ] Show match timer

### Step 5.4: Post-Match Screen
- [ ] Show winner/loser
- [ ] Display ELO changes (+/- X)
- [ ] Show match statistics
- [ ] Rematch button (if opponent agrees)

---

## 📋 Phase 6: Testing & Polish (Week 4)

### Step 6.1: Local Testing
- [ ] Test with two devices/emulators
- [ ] Verify turn synchronization
- [ ] Test disconnect scenarios
- [ ] Check security rules

### Step 6.2: Beta Testing
- [ ] Deploy to TestFlight/Internal Testing
- [ ] Invite 5-10 testers
- [ ] Collect feedback on latency
- [ ] Monitor Firestore usage/costs

---

## 🎯 Key Technical Decisions

### 1. **Turn-Based vs Real-Time**
✅ **Turn-based**: Perfect for this game
- Lower bandwidth
- Simpler synchronization
- Better for mobile (works with poor connection)

### 2. **Combat Resolution: Client or Server?**
**Phase 1 (MVP)**: Client-side with validation
- Both clients resolve independently
- Security rules prevent tampering
- Faster, no Cloud Functions needed

**Phase 2 (Production)**: Server-side Cloud Function
- Single source of truth
- Prevents cheating completely
- Slightly higher latency

### 3. **Reconnection Strategy**
- Store match state in Firestore
- On reconnect, fetch latest state
- Resume from current turn
- Timeout after 3 minutes of inactivity

### 4. **ELO System**
- Start: 1000 ELO
- Win: +20 to +40 (based on opponent ELO)
- Loss: -20 to -40
- Update after match completion

---

## 📊 Estimated Costs (Firebase)

**Free Tier Limits:**
- 50K reads/day
- 20K writes/day
- 1GB storage

**Estimated Usage (100 active players/day):**
- ~10K reads (checking matches, profiles)
- ~5K writes (turn submissions, updates)
- ~10MB storage (match history)

**Verdict**: Free tier sufficient for beta! 🎉

---

## 🚀 Next Steps

1. **You**: Create Firebase project and download config files
2. **Me**: Add dependencies and initialize Firebase
3. **Together**: Test authentication flow
4. **Me**: Build Firestore data models
5. **Test**: First online match!

Ready to start? Let me know when you've created the Firebase project! 🔥

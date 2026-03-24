# RPG Board Game Plan

## Working Concept

A 2D top-down, turn-based multiplayer board RPG for 2-8 players. Matches should last about 45-60 minutes, with each player's turn taking roughly 45-60 seconds. The game blends board movement, character progression, property control, raiding, light economy, quick combat, and optional high-risk encounters.

The target feel is "Monopoly on steroids with RPG systems," but with better pacing, stronger comeback potential, and much less downtime.

## Core Product Decisions

- Engine: Godot 4
- Scripting language: GDScript
- Camera/view: 2D top-down
- Match length target: 45-60 minutes
- Player count target: 2-8 players
- Multiplayer v1: host shares address and players direct-connect
- Match recovery: restore after crashes
- Board structure: semi-randomized
- Combat: fast resolution on the main board, no separate battle screen
- Defeat handling: respawn with penalties, no early elimination

## Design Pillars

1. Short turns, long strategy
Each turn should feel quick and decisive, while the full match builds toward a larger power struggle.

2. Multiple paths to victory
Players should be able to win through combat, territory, economy, boss hunting, disruption, or smart hybrid play.

3. Constant board tension
The board should feel dangerous and alive, with reasons to move, contest space, and react to shifting threats.

4. Low downtime
Even with 8 players, off-turn waiting should stay manageable. Combat, NPC behavior, and UI flow must be fast.

5. Strong comeback potential
Players who fall behind should have ways to recover, while leaders should become more exposed and contestable.

## High-Level Game Loop

### Match Flow

1. Host creates lobby and starts authoritative local server
2. Players join via direct connection
3. Board is generated from a semi-randomized template
4. Players take turns in round-robin order
5. After all players act, a short world phase resolves
6. Play continues until a victory threshold is reached
7. Final round is triggered
8. Highest final score wins

### Turn Flow

Each turn should follow a simple structure:

1. Start turn and begin timer
2. Roll movement die or use a movement-modifying effect
3. Move across connected cells
4. Resolve landing cell
5. Perform one major action if available
6. Use any allowed instant/free effects
7. End turn or auto-end when timer expires

### Turn Time Budget

Recommended default timer: 50 seconds

Suggested pacing budget:

- 5 seconds: orient and inspect
- 10 seconds: roll and move
- 10-20 seconds: resolve cell or combat
- 10-15 seconds: major action
- 5 seconds: optional item/skill use and end turn

This keeps the game readable without turning each turn into a mini-RPG session.

## Board Structure

### Recommended Board Model

Use a node-based board made of connected cells rather than a free-walk tile grid.

Why:

- Faster turns
- Cleaner visuals
- Easier path readability
- Better balance control
- Simpler networking and synchronization

### Semi-Randomized Board Approach

Do not fully procedural-generate the whole board. Instead, build the board from handcrafted region modules attached to a controlled backbone.

Recommended structure:

- 1 central hub region
- 3-5 outer regions
- 48-64 total cells
- 2-4 loops
- Several branches and shortcuts
- A few high-risk dead-end routes with strong rewards

This gives replayability without sacrificing fairness or clarity.

### Region Examples

- Town district: shops, casino, safer economy cells
- Frontier: neutral properties, roaming mobs, event cells
- Ruins: magic-oriented cells, curses, high-risk loot
- Stronghold rim: defended properties and raid-heavy routes
- Dungeon belt: boss entrances and dangerous reward nodes

### Cell Types for v1

- Start/shrine cell
- Neutral path cell
- Property cell
- Shop cell
- Event cell
- Casino cell
- Mob den cell
- Dungeon entrance cell
- Shrine/respawn cell
- Portal or shortcut cell

## Victory System

The fantasy goal is to become "the mightiest," but the actual match needs a clear scoring system.

Recommended win currency: Renown

Players gain Renown from:

- Defeating other players
- Winning boss encounters
- Holding upgraded properties
- Successful raids
- Completing special events
- Maybe clearing region objectives

Recommended end condition:

- A player reaches a Renown threshold based on player count
- The game enters a final round
- After the final round, the player with the most Renown wins

Benefits:

- Multiple viable strategies
- Clear match pacing
- Strong endgame tension
- Prevents endless stalemates

## Player Systems

### Core Stats

Keep the stat set fairly compact for readability.

Recommended v1 stat package:

- Might: physical damage and raid pressure
- Guard: defense and survivability
- Arcana: magic power and spell scaling
- Fortune: crits, loot quality, and event odds
- Mobility: movement modifiers, evasion, route flexibility

Optional sixth layer:

- Influence: economy, property efficiency, and shop interactions

This should only be added if testing shows that economy and combat need clearer separation. Otherwise, five stats is cleaner.

### Resources

- Health
- Gold
- Renown
- Cooldowns
- Inventory slots

### Progression

Players should be able to improve through:

- Level-ups or stat upgrades
- Equipment
- Consumable items
- Passive bonuses
- Active skills
- Property ownership
- Temporary event buffs

### Skill Design

Keep skills impactful but fast to understand.

Recommended skill categories:

- Direct damage
- Movement control
- Self-buffs
- Debuffs
- Economy manipulation
- Property interaction
- Escape or reposition tools

Important constraint:

Skills that affect players across the board should be strong enough to matter, but not so common that they make movement and positioning irrelevant.

## Combat Design

### Core Principle

Combat must resolve quickly and remain readable to all players.

Target duration:

- Normal fight: 2-4 seconds
- Boss resolution: 5-10 seconds

### Player vs Player

When combat starts, the active player chooses a quick action:

- Basic attack
- Skill
- Item
- Raid action
- Retreat if allowed

The defender should not need a long live-response window in v1. To keep pacing fast, defense should mostly come from:

- Stats
- Equipped gear
- Passive abilities
- A preselected stance
- Property defenses if on owned territory

Recommended stance examples:

- Aggressive
- Balanced
- Defensive
- Trickster

This lets off-turn players still influence outcomes without stopping the game.

### Player vs Mob

Resolve with the same fast combat system as player fights.

### Boss Encounters

Bosses should be optional and risky, but still fast.

Recommended v1 model:

- Boss is tied to a dungeon cell
- Entering the dungeon commits the active player to a challenge
- Boss fight resolves on the board using 1-3 strong exchanges
- Rewards are large enough to justify the risk

Avoid making bosses feel like a separate game mode inside the match.

## Defeat and Respawn

Players should not be permanently eliminated during the main match.

Recommended defeat consequences:

- Lose a chunk of gold
- Lose some temporary buffs
- Potentially drop a small portion of carried loot
- Respawn at a shrine or base node
- Suffer a short tempo penalty

Recommended tempo penalty:

- Miss one immediate world-phase opportunity
- Or begin next turn with reduced movement
- Or respawn shielded but weaker for one cycle

The defeated player should still feel involved and able to recover.

## Economy and Property Systems

### Property Ownership

Players can claim certain cells as properties.

Properties should:

- Generate gold
- Possibly generate small Renown
- Be upgradeable
- Support defensive improvements
- Create conflict hotspots

### Property Upgrades

Recommended upgrade types:

- Income upgrade
- Defense upgrade
- Utility upgrade

Utility examples:

- trap effect
- heal on land
- sight/reveal bonus
- toll or tax effect

### Raiding

If a player lands on a property owned by someone else, they may initiate a raid.

Possible raid outcomes:

- Steal gold
- Damage or disable the property
- Temporarily occupy it
- Transfer ownership after a strong success

### Anti-Snowball Measures

This system needs guardrails so one early lead does not become unbeatable.

Recommended balancing tools:

- Diminishing returns on large property empires
- Higher upkeep or vulnerability for overextended owners
- Bounties or bonus rewards for attacking leaders
- Event systems that slightly favor weaker players

## Mobs and World Phase

### Mobs

Mobs should create pressure, not turn the game into an NPC simulator.

Recommended mob behavior:

- Spawn from dens or events
- Occupy cells or roam short distances
- Fight players who land on or enter their cell
- Occasionally interfere with property income or travel routes

### World Phase

Instead of giving every mob a long full turn, resolve a brief world phase after each round of player turns.

The world phase can handle:

- Property income
- Cooldown ticks
- Mob movement or spawning
- Region events
- Boss reset timers

Target duration:

- 3-8 seconds

## Events and Casino

### Event Cells

These should add unpredictability and story energy, but not create huge rules overhead.

Good event outcomes:

- Gain or lose gold
- Gain a temporary buff or curse
- Spawn a mob
- Teleport
- Change ownership pressure
- Trigger a small local challenge

### Casino Cells

These should be risky and tempting, not mandatory.

Examples:

- Double-or-nothing gold bets
- Luck-weighted wheel
- One-time stat gamble
- Rare item lottery

The casino should be a spice system, not a dominant strategy.

## Recommended UX and Visual Direction

### Visual Goals

- Pretty, readable, and symmetric
- Smooth movement and transitions
- Strong highlights and hover feedback
- No cluttered token overlaps
- Clear ownership markers
- Clean board readability at a glance

### Board Presentation

- Tokens should animate along paths rather than jump between cells
- Reachable cells should highlight clearly
- Cell ownership should be color-coded
- Overlapping players should use arranged orbit slots around the cell center
- Damage, healing, gold, and status changes should use fast floating popups

### UI Panels

Recommended v1 layout:

- Top bar: round, turn, timer, current player
- Left or right panel: selected player details
- Bottom action bar: roll, skill, item, inspect, end turn
- Collapsible event/combat log
- Hover tooltips for all cells and icons

### Menus

Recommended screens:

- Main menu
- Host game
- Join game
- Lobby
- Restore crashed match
- Settings
- Endgame summary

## Technical Architecture

### Engine Choice

Godot 4 is the recommended fit because it offers:

- Strong 2D support
- Clean scene system
- Good UI tooling
- Accessible scripting
- Easy asset iteration
- A smaller overall complexity footprint than a large AAA-oriented engine

### Networking Model

Use an authoritative host-server model for v1.

Recommended structure:

- Host launches the match and also runs a local server process
- The server owns the true game state
- Clients send requested actions
- Server validates movement, combat, economy, and victory logic
- Clients mainly render results and local UI state

This is more robust than letting the host client itself be the sole source of truth.

### Joining

For v1, direct connect is acceptable.

Important note:

A real short join code usually requires relay or matchmaking infrastructure. In v1, the "code" can be presented as a connection address or LAN address. Later versions can add a friendlier relay-backed room code.

### Crash Recovery

The game should autosave frequently on the host side.

Recommended approach:

- Save a state snapshot after every completed turn
- Save another snapshot after major state changes
- Append a lightweight event log between snapshots
- Keep several rotating recent backups
- On launch, offer to restore the most recent interrupted match

Recommended restore behavior:

- Rebuild board state from latest snapshot
- Replay any remaining events if needed
- Allow players to reconnect using their session identity

### Data and Content Organization

Gameplay systems should be easy to rebalance without code surgery.

Recommended data split:

- Board/cell definitions: external data files
- Item definitions: external data files
- Skill definitions: external data files
- Mob and boss definitions: external data files
- Visual scenes and effects: Godot scenes/resources

This keeps art iteration and gameplay tuning relatively independent.

## Suggested Project Structure

One reasonable starting structure:

```text
project/
  scenes/
    board/
    cells/
    actors/
    ui/
    fx/
  scripts/
    core/
    board/
    combat/
    economy/
    ai/
    networking/
    persistence/
    ui/
  data/
    boards/
    cells/
    items/
    skills/
    mobs/
    bosses/
    balance/
  assets/
    sprites/
    icons/
    audio/
    fonts/
```

## Balance Rules for v1

To keep the game within 45-60 minutes, the first version should avoid excess complexity.

Recommended limits:

- One major action per turn
- Compact stat set
- Fast, mostly deterministic combat resolution
- Limited inventory size
- Limited active skill slots
- Short world phase
- No player elimination
- No overly long dungeon side-modes

## v1 Scope

### Must-Haves

- Multiplayer lobby and direct connect
- Turn timer
- Semi-randomized board generation from modules
- Movement and path resolution
- Core stats and player progression
- Quick on-board combat
- Properties and property upgrades
- Shops and inventory
- Basic mobs
- At least one boss encounter type
- Event cells
- Casino cells
- Respawn system
- Host crash recovery
- Clean top-down UI

### Nice-to-Haves if Time Allows

- Character classes
- Regional objectives
- Weather or map modifiers
- Spectator reconnect view
- Replay log
- Cosmetic skins

### Save for Later Versions

- Internet relay/matchmaking
- Real short room codes
- Voice/chat features
- Advanced modding support
- Separate ranked/casual modes

## Recommended Milestones

### Milestone 1: Paper Design Lock

Finalize:

- Stat model
- Renown thresholds
- Turn timer rules
- Property rules
- Combat resolution formula
- Defeat penalties
- Board module structure

### Milestone 2: Offline Vertical Slice

Build:

- One playable board
- 2-4 local players
- Movement
- A few cell types
- Basic combat
- Shop
- Property claim/raid
- Respawn

### Milestone 3: Full Match Skeleton

Add:

- Semi-randomized board assembly
- World phase
- Mobs
- Boss cell
- Renown and final round logic
- Endgame screen

### Milestone 4: Multiplayer Foundation

Add:

- Authoritative host server
- Lobby flow
- Join and reconnect
- State synchronization

### Milestone 5: Crash Recovery

Add:

- Snapshot saves
- Rolling backups
- Restore screen
- Rejoin handling

### Milestone 6: Presentation and Polish

Add:

- Better camera movement
- Smoother token animation
- Impact effects
- Cleaner overlays
- Better readability and pacing polish

### Milestone 7: Balance Pass

Tune:

- Match duration
- Snowball control
- Boss rewards
- Property economy
- Skill power
- 2-8 player pacing

## Design Risks to Watch

1. Turn bloat
Too many optional actions will break the 45-60 second turn goal.

2. Snowballing
Property economies can dominate unless leaders become vulnerable and catch-up tools exist.

3. Downtime at 8 players
Combat, world phases, and UI waits must stay very short.

4. Excess randomness
Semi-randomized boards should vary without creating unfair spawn advantage or dead strategies.

5. Rules overload
Too many stats, effects, and exceptions will make the game harder to read than it is fun to play.

## Recommended First Build Strategy

The smartest implementation path is:

1. Prove the game is fun offline with placeholder art
2. Lock the core loop and pacing
3. Add networking only after the turn model feels good
4. Add crash recovery before content explosion
5. Polish UI and visuals once interaction flow is solid

## Immediate Next Step

If implementation starts, the next best deliverable is a formal v1 design breakdown covering:

- exact turn rules
- board generation rules
- combat formula
- property and raid math
- Renown scoring table
- list of cell types
- first-pass UI screens
- first-pass class/item/skill content

That document can then drive actual project scaffolding in Godot.

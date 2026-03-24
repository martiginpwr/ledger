# V1 Rules Spec

This document turns the high-level project plan into a buildable v1 ruleset. It is intentionally concrete. The numbers here are not "final balance," but they are meant to be good enough to prototype, playtest, and iterate.

This file complements:

- `RPG_BOARD_GAME_PLAN.md` for vision and product direction

## v1 Goals

The first playable version should:

- Support 2-8 players
- Finish most matches in 45-60 minutes for 4-8 players
- Keep each turn fast and readable
- Resolve combat on the main board in a few seconds
- Allow multiple viable routes to victory
- Survive host crashes through autosave and restore

## Design Constraints

These constraints should drive all implementation choices:

- One turn should rarely exceed one minute
- A player should usually make one major decision per turn
- No separate combat scene
- No permanent elimination during the main match
- No subsystem should require long off-turn interaction

## Match Structure

### Recommended Timer by Player Count

| Players | Turn Timer | Target Rounds |
| --- | --- | --- |
| 2-3 | 55 seconds | 8-10 |
| 4-6 | 50 seconds | 7-9 |
| 7-8 | 40 seconds | 7-8 |

### Hard Match Cap

- The match ends automatically after round 10 if no one has triggered the final round.
- If round 10 ends without a final round, highest Renown wins.

### Final Round Trigger

The first player to reach the Renown threshold triggers the final round.

Recommended thresholds:

| Players | Renown Threshold |
| --- | --- |
| 2-3 | 12 |
| 4-6 | 14 |
| 7-8 | 16 |

The current round finishes, then one final full round is played. After that, the player with the highest Renown wins.

### Tiebreakers

Use these in order:

1. Most gold
2. Most boss trophies
3. Most owned property levels
4. Lowest seat number wins ties only as a temporary prototype fallback

The final fallback should be replaced later with a cleaner sudden-death rule if needed.

## Board Model

## Core Shape

Use a node graph, not a free-walk tile field.

Each node is a cell. Each cell connects to one or more neighboring cells. Movement spends one point per edge traversed.

## Board Assembly by Player Count

### 2-3 Players

- 1 central hub
- 3 outer regions
- 1 cross-link between outer regions
- Target size: 38-42 cells

### 4-6 Players

- 1 central hub
- 4 outer regions
- 2 cross-links between outer regions
- Target size: 48-52 cells

### 7-8 Players

- 1 central hub
- 5 outer regions
- 3 cross-links between outer regions
- Target size: 58-62 cells

## Board Generation Rules

The board should be semi-randomized from handcrafted region modules.

### Assembly Steps

1. Choose a board size template by player count.
2. Place the fixed central hub.
3. Randomly select the required number of outer region modules from the content pool.
4. Attach each region to a hub anchor.
5. Add the required number of cross-links from the approved link pool.
6. Validate the result.

### Validation Rules

Every generated board must pass all of these:

- Every region is reachable from the hub.
- At least one shop is within 4 steps of the hub.
- At least one shrine is within 5 steps of every cell.
- No boss entrance is within 3 steps of the hub.
- No region entrance is blocked behind a one-way dead-end.
- No cell has more than 4 connections in v1.
- Each outer region contains at least 2 properties and 1 event cell.
- The casino appears exactly once per board.
- Boss entrances appear at least once and at most 3 times.

## Cell Distribution Targets

These are total board targets, not per-region hard requirements.

### 2-3 Players

- 6-7 properties
- 2 shops
- 4-5 events
- 1 casino
- 2 mob dens
- 1 boss entrance
- 1 central shrine and 1 secondary shrine

### 4-6 Players

- 9-10 properties
- 3 shops
- 6-7 events
- 1 casino
- 3 mob dens
- 2 boss entrances
- 1 central shrine and 1 secondary shrine

### 7-8 Players

- 11-13 properties
- 3-4 shops
- 8-9 events
- 1 casino
- 4 mob dens
- 2-3 boss entrances
- 1 central shrine and 2 secondary shrines

## Movement

### Movement Die

Use a custom travel die with faces:

- 1
- 2
- 2
- 3
- 3
- 4

This keeps movement tighter and more controllable than a classic d6.

### Movement Rules

- The active player rolls the travel die at the start of their turn.
- They may move at least 1 step and up to the rolled value.
- They may stop early on any legal cell.
- They choose routes at branches during movement.
- Portal and shortcut effects only trigger if the player stops on the relevant cell.

### Occupancy

- Any number of players can occupy the same cell.
- Any number of mobs can be present on the same cell in the data model.
- The renderer should visually spread tokens around the cell center so they never overlap badly.

## Turn Structure

Each turn follows this order:

1. Start-turn effects resolve.
2. Reduce cooldowns on the active player's skills by 1.
3. Start the turn timer.
4. Roll the travel die.
5. Move.
6. Resolve forced encounters on the destination cell.
7. Resolve the destination cell's passive effect.
8. Perform up to one Major Action.
9. Perform up to one Quick Action if desired.
10. End turn.

### If the Timer Expires

Use the safest deterministic fallback:

- If movement has not been rolled yet, auto-roll.
- If movement was rolled but no path was chosen, auto-move along the default route for the current cell.
- If a valid destination was already selected, commit it.
- Skip any unresolved optional action.
- End the turn.

This fallback behavior should be clearly communicated in the UI.

## Forced Encounters

Forced encounters happen before the active player takes a Major Action.

### Forced by Mobs

- If the destination cell contains a hostile mob, combat starts immediately.
- If the player wins, they may still take their Major Action if time remains.
- If the player loses, the turn ends.

### Forced by Bosses

- Bosses do not auto-trigger.
- A boss entrance only matters if the player uses their Major Action to enter it.

### Forced by Other Players

- Landing on another player does not force combat in v1.
- The active player must spend their Major Action to attack.

## Action Budget

## Major Action

A player may take one Major Action each turn.

Major Actions include:

- Attack another player on the same cell
- Use an active combat or utility skill
- Claim a neutral property
- Upgrade an owned property
- Raid an enemy property
- Shop
- Train at a shrine
- Enter a boss dungeon
- Gamble at the casino
- Resolve an event choice that requires commitment

## Quick Action

A player may take one Quick Action each turn.

Quick Actions include:

- Use one consumable
- Change stance
- Use a skill marked Quick

Inspection, tooltips, and map review do not count as actions.

## Player Sheet

### Core Stats

Use five core stats in v1:

- Might
- Guard
- Arcana
- Fortune
- Mobility

### What Each Stat Does

#### Might

- Increases physical attack power
- Improves raids
- Boosts some aggressive skills

#### Guard

- Increases max HP
- Increases physical defense
- Improves survival during boss and mob fights

#### Arcana

- Increases spell power
- Improves magic utility skills
- Helps bypass some armor effects

#### Fortune

- Improves loot and event outcomes
- Improves crit-related effects
- Enables reroll and gamble synergies

#### Mobility

- Improves movement-related skill effects
- Improves retreat checks
- Improves reposition tools and escape reliability

### Derived Values

Use these default formulas:

- Max HP = `10 + Guard * 2`
- Basic attack power = `Might + weapon bonus`
- Spell power = `Arcana + focus bonus`
- Base defense = `Guard + armor bonus`

## Starting State

All players start with:

- 10 gold
- Full HP
- 1 weapon slot
- 1 armor slot
- 1 trinket slot
- 3 consumable inventory slots
- 2 active skill slots
- Balanced stance

Every player begins at the central shrine or sanctuary region.

## Origins

v1 should include lightweight origins instead of full classes. Each player chooses one during match setup.

All stats begin at 1, then the chosen origin applies bonuses.

### Raider

- +2 Might
- +1 Mobility
- Passive: First successful raid each round grants +1 extra gold.
- Starter skill: Power Strike

### Warden

- +2 Guard
- +1 Might
- Passive: Owned properties gain +1 defense while you are alive.
- Starter skill: Hold Fast

### Arcanist

- +2 Arcana
- +1 Fortune
- Passive: Your first spell each round gains +1 power.
- Starter skill: Arc Bolt

### Trickster

- +2 Fortune
- +1 Mobility
- Passive: Once per round, reroll one event, gamble, or loot roll.
- Starter skill: Shadowstep

### Stat Caps

- Hard cap: 5 in any core stat
- Soft expectation for v1 matches: most players finish at 3-4 in their key stats

## Stances

The current stance remains active until changed.

### Balanced

- No modifier

### Aggressive

- +1 attack value in initiated combat
- -1 defense value in all combat

### Guarded

- +1 defense value in all combat
- -1 attack value in initiated combat

### Cunning

- +1 Fortune for crit and loot effects
- +1 retreat checks

## Progression

v1 uses gold-driven progression instead of XP levels.

This keeps systems compact and ties economy, risk, and build growth together.

### Training at Shrines

A shrine Major Action may be used to:

- Heal 6 HP for 3 gold
- Heal to full for 5 gold
- Remove one curse or wound effect for 4 gold
- Raise one stat by 1

### Stat Training Cost

Raising a stat costs:

- From 1 to 2: 5 gold
- From 2 to 3: 7 gold
- From 3 to 4: 9 gold
- From 4 to 5: 11 gold

### Learning Skills

Shops and shrines may offer skills.

Rules:

- A player can equip up to 2 active skills total in v1.
- Starter skills count toward the limit.
- Learning a new skill while full requires replacing one equipped skill.

## Combat

## Combat Design Goals

- Resolve in 2-4 seconds for standard fights
- Require only one attacker decision in v1
- Remain readable to spectators
- Avoid long defender response windows

## Combat Modes

There are three v1 combat types:

- Player versus player
- Player versus mob
- Player versus boss

All three use the same underlying exchange model.

## Exchange Model

A combat instance resolves as up to 3 exchanges:

1. Attacker exchange
2. Defender counterexchange if still alive and able
3. Attacker final exchange if still alive and the initiating action allows it

Standard attack actions allow 2 exchanges.
Boss and some skill-based fights allow 3 exchanges.

## Combat Formula

Use a d6 for each exchange.

### Physical Attack

- Attack total = `d6 + Might + weapon bonus + stance attack modifier + skill modifier`
- Defense total = `d6 + Guard + armor bonus + stance defense modifier + terrain/property modifier`
- Damage = `max(1, attack total - defense total + 2)`

### Magic Attack

- Attack total = `d6 + Arcana + focus bonus + skill modifier`
- Defense total = `d6 + Guard + armor bonus + resist modifier`
- Damage = `max(1, attack total - defense total + 2)`

### Crit Rule

- A natural 6 on the attack die deals +2 extra damage.
- If the attacker has Fortune 4 or 5, a natural 5 also crits.

### Retreat Rule

Only some actions and skills allow retreat.

Default retreat check:

- `d6 + Mobility`
- Target number 6

On success, move to an adjacent legal cell and end the combat.

## PvP Combat Rules

### Basic Attack

- Major Action
- Requires same-cell target
- Uses the standard 2-exchange model

### If the Defender Survives

- The defender remains on the cell
- The attacker remains on the cell
- No one is locked into future combat automatically

This keeps movement open and avoids combat mode traps.

## Mob Combat Rules

### Standard Mob Fight

- Triggered immediately when entering a hostile mob cell
- Uses the 2-exchange model
- If the player survives and wins, the mob is removed
- The player may still take their Major Action

### Elite Mob Fight

- Uses the 3-exchange model
- Usually grants Renown and better loot

## Boss Combat Rules

### Boss Entry

- Entering a boss dungeon costs the Major Action
- The challenge resolves immediately

### Boss Resolution

- Use the 3-exchange model
- Bosses have scripted passive rules, not long ability trees, in v1
- A failed boss attempt ejects the player to the entrance cell

### Boss Reward Package

Recommended reward baseline:

- +4 Renown
- 6-8 gold
- 1 trophy or rare item

## Defeat and Respawn

### On Defeat

When a player's HP reaches 0:

- They lose `max(3 gold, 25% of current gold rounded down)`
- They lose all temporary buffs
- They gain the `Wounded` status
- They immediately respawn at the nearest shrine at 50% HP rounded up
- Their current turn ends immediately

### Wounded Status

The `Wounded` status lasts until the end of the player's next turn.

Effects:

- -1 attack value
- Cannot enter boss dungeons
- Cannot benefit from casino doubles

This keeps defeat meaningful without removing the player from the match.

### On Mob Defeat

If a mob is defeated:

- Grant its reward
- Remove it from the board
- Mark its den or spawn source for future respawn logic if relevant

## Economy

## Gold Sources

The main gold sources in v1 should be:

- Starting gold
- Property income
- Mob rewards
- Player defeat rewards
- Boss rewards
- Events
- Casino wins

### Default Gold Rewards

- Defeat a normal mob: 2 gold
- Defeat an elite mob: 4 gold and 1 Renown
- Defeat another player: 3 gold
- Win a boss: 6-8 gold

## Properties

Properties are the board-control backbone of the economy.

### Property Levels

#### Level 1: Outpost

- Claim cost: 6 gold
- Income: 2 gold each world phase
- Defense bonus: 0
- Property defense rating: 6

#### Level 2: Estate

- Upgrade cost: 6 gold
- Income: 3 gold each world phase
- Property defense rating: 8
- One utility modifier may be attached later

#### Level 3: Stronghold

- Upgrade cost: 8 gold
- Income: 4 gold each world phase
- Property defense rating: 11
- Grants +1 Renown when upgraded

### Property Income Rules

- A property that was successfully raided since the last world phase produces no income.
- A property occupied by a hostile mob produces no income.
- Income is paid during the world phase.

### Property Utility Modifiers

v1 should support exactly 3 utility modifier types:

- Toll: visiting enemies lose 1 gold
- Ward: +1 property defense rating
- Cache: +1 gold income

These should be data-driven and optional.

## Raids

Raids are a Major Action and require the active player to be on an enemy property.

### If the Owner Is Absent

Resolve the raid against the property's defense rating.

Raid total:

- `d6 + Might + weapon bonus + raid modifiers`

Defense total:

- `d6 + property defense rating + ward modifiers`

Raid outcomes:

- Success by 1-2: steal 3 gold from the owner if possible, property loses income this world phase
- Success by 3-4: steal 4 gold and downgrade one utility modifier
- Success by 5 or more: steal 4 gold and reduce the property by 1 level

### If the Owner Is Present

- The owner may be attacked instead of the structure
- If the attacker wins the fight, apply the weakest successful raid result automatically
- The defending owner gains the property's defense modifier during combat

### Renown from Raids

- First successful raid each round: +1 Renown
- Destroying or reducing a Stronghold: +1 additional Renown

## Shops

A shop Major Action allows one of these:

- Buy one item
- Buy one equipment piece
- Sell one item for half value rounded down
- Browse the current skill offer and learn one skill

### Shop Refresh

- Each shop has a shared rotating stock
- Shared stock refreshes every 2 world phases
- Rare items may be region-specific later, but not required in v1

## Inventory and Equipment

### Equipment Slots

- 1 weapon
- 1 armor
- 1 trinket

### Inventory Slots

- 3 consumable slots

### Suggested Equipment Power Budget

- Basic shop weapon: +1 physical attack
- Rare boss weapon: +2 physical attack plus one rider effect
- Basic armor: +1 defense
- Rare armor: +2 defense or +1 defense plus immunity rider
- Trinkets should mostly modify Fortune, Mobility, or economy interactions

## Renown Sources

These are the main intended routes to victory in v1:

- Defeat another player: +2 Renown
- Defeat an elite mob: +1 Renown
- Defeat a boss: +4 Renown
- First successful raid each round: +1 Renown
- Upgrade a property to Stronghold: +1 Renown
- Major event rewards: +1 Renown

This gives combat, territory, risk-taking, and disruption all a place in the win race.

## Leader Pressure

To reduce snowballing, the current Renown leader becomes `Marked` during each world phase.

### Marked Effects

- Players tied for highest Renown are all Marked
- Defeating a Marked player grants +1 bonus Renown
- Successfully raiding a Marked player's property grants +1 bonus gold

This keeps leaders powerful but exposed.

## World Phase

The world phase happens after every player has taken one turn.

Target duration:

- 3-8 seconds

## World Phase Order

1. Pay property income
2. Clear raid locks on properties
3. Update Marked leader status
4. Spawn or move mobs
5. Tick event timers and region effects
6. Refresh shops if needed
7. Increment round counter if all players acted

## Mobs

Mobs should create pressure without causing long delays.

### v1 Mob Roles

- Ambusher: punishes greedy routes
- Bruiser: blocks high-value paths
- Leech: steals gold or buffs
- Elite: mini-objective with better rewards

### Spawn Rules

- Each mob den checks a spawn chance during world phase if empty
- Spawn chance should be modest in v1, around 35%
- No more than 1 newly spawned mob per den per world phase
- Elite mobs should only come from scripted events or rare den rolls

### Movement Rules

- Normal mobs move at most 1 cell during world phase
- If a player is already on the mob's cell, no movement occurs
- Mobs should prefer nearby players, not random wandering, to keep them readable

## Events

Event cells should be short, flavorful, and impactful.

### Event Design Rules

- Resolve in under 5 seconds
- Offer at most 2 choices in v1
- Usually affect gold, HP, mobility, item gain, curses, or small Renown rewards
- Avoid long scripted scenes in v1

### Event Categories

- Fortune event
- Ambush event
- Merchant event
- Relic event
- Local crisis event

## Casino

The casino is optional risk, not a core economy engine.

### Casino Actions

Use the Major Action to choose one:

- Coin Flip: bet up to 4 gold, double on win
- High Roll: pay 2 gold, roll for a small item or gold prize
- Lucky Draw: pay 5 gold for a low chance at a rare trinket

### Casino Rules

- The casino can only be used once per player per round
- Wounded players cannot benefit from doubled rewards
- Fortune may influence some outcomes

## First-Pass Skill List

These are good seed skills for v1 content.

### Origin Skills

#### Power Strike

- Type: Major
- Cooldown: 2
- Effect: next physical attack this turn gains +2 attack value and +1 damage

#### Hold Fast

- Type: Quick
- Cooldown: 3
- Effect: gain +2 defense value until the start of your next turn

#### Arc Bolt

- Type: Major
- Cooldown: 2
- Range: 3 cells
- Effect: deal one magic exchange to a target in range

#### Shadowstep

- Type: Quick
- Cooldown: 3
- Effect: move up to 2 cells after finishing your Major Action

### Learnable Skills

#### Fire Sigil

- Type: Major
- Cooldown: 3
- Effect: target player on your cell or an adjacent cell takes a magic attack and suffers Burn

#### Ward Burst

- Type: Quick
- Cooldown: 3
- Effect: remove one debuff and gain +1 defense this turn

#### Hook Chain

- Type: Major
- Cooldown: 3
- Effect: pull a target from an adjacent cell onto your cell, then deal a weak physical exchange

#### Lucky Break

- Type: Quick
- Cooldown: 4
- Effect: reroll one attack die, defense die, or event roll

#### Sabotage

- Type: Major
- Cooldown: 3
- Effect: gain +3 on your next raid this turn

#### Blink Rune

- Type: Quick
- Cooldown: 4
- Effect: teleport to a visible cell within 2 steps

## First-Pass Status Effects

Keep the list short in v1.

### Burn

- Take 1 damage at the start of your next turn

### Guarded

- Gain +1 defense value during combat

### Wounded

- Temporary defeat penalty status

### Silenced

- Cannot use skills until the end of your next turn

### Rooted

- Cannot use Mobility-based movement skills until the end of your next turn

## First-Pass Item List

### Minor Potion

- Cost: 3 gold
- Quick Action
- Restore 4 HP

### Greater Potion

- Cost: 5 gold
- Quick Action
- Restore 7 HP

### Smoke Bomb

- Cost: 4 gold
- Quick Action
- Automatically succeed at a retreat check

### Raider's Kit

- Cost: 4 gold
- Quick Action
- Gain +2 on a raid this turn

### Throwing Knife

- Cost: 3 gold
- Quick Action
- Deal 2 damage to a target on your cell or an adjacent cell

### Ward Scroll

- Cost: 4 gold
- Quick Action
- Gain Guarded until your next turn

### Fortune Card

- Cost: 4 gold
- Quick Action
- Reroll any one d6 you just rolled

### Trap Kit

- Cost: 5 gold
- Major Action on owned property
- Add a temporary trap; first enemy raiding before next world phase suffers -1 on the raid

## First-Pass Mob List

### Bandit

- HP: 6
- Attack bias: physical
- Reward: 2 gold
- Trait: steals 1 extra gold if it wins

### Wisp

- HP: 5
- Attack bias: magic
- Reward: 2 gold
- Trait: 25% chance to apply Silenced

### Brute

- HP: 8
- Attack bias: physical
- Reward: 3 gold
- Trait: blocks a high-value path

### Elite Hunter

- HP: 10
- Reward: 4 gold and 1 Renown
- Trait: uses the 3-exchange model

## First-Pass Boss List

### Bone Tyrant

- HP: 14
- Trait: gains +1 defense on its counterexchange
- Reward: +4 Renown, 7 gold, one rare weapon or armor drop

### Storm Idol

- HP: 12
- Trait: first exchange deals magic splash for 1 damage even on a defended hit
- Reward: +4 Renown, 6 gold, one rare trinket or skill offer

## UI Requirements for the Ruleset

These rules only work well if the UI supports them clearly.

v1 must show:

- Current turn and round
- Remaining turn timer
- Current Renown standings
- Active stance
- HP, gold, and cooldowns
- Cell ownership and property level
- Reachable cells after rolling
- A short combat/event log

## Networking and Save Requirements

The ruleset depends on an authoritative host server.

The server must own:

- Turn order
- Board generation result
- Dice rolls
- Combat results
- Property state
- Inventory and skills
- Renown state
- World phase outcomes

## Autosave Requirements

The host server should save:

- After board generation
- After each completed player turn
- After each boss result
- After each property ownership change
- At the end of every world phase

Recommended save model:

- Full snapshot plus rolling backup slots
- Small event log for debugging and restore validation

## Prototype Success Criteria

The first playable prototype is "good enough" if:

- A full 4-player local match can be completed
- Players understand what to do without a rules explainer after a few turns
- Most turns finish inside the timer
- Combat feels fast and satisfying
- Properties and raids matter
- No single strategy dominates immediately

## Next Implementation Step

The next best production task after this spec is:

1. Scaffold the Godot project
2. Implement the board graph data model
3. Implement turn state, movement, and timer
4. Implement fast combat resolution
5. Add 3-4 cell types before expanding content

This order should produce a playable prototype fastest.

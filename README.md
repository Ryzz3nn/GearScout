# GearScout

Two addons for World of Warcraft Burning Crusade Anniversary (client 2.5.6, interface 20506).

- **GearScout** is what everyone installs. It audits your own gear and rotation and tells you, in plain words, what to fix. It answers gear questions from your raid lead. It never shows you anyone else's gear.
- **GearScout_Lead** is what one officer installs. It asks the group or guild for gear and shows the answers in a sortable table.

No Ace3, no LibStub, no shared libraries, no other addon required. Details is used if it happens to be there, and ignored if it is not.

## Install

Both folders live in `Interface/AddOns`. On this machine they are already junctioned in, so editing the source here updates the game directly and a `/reload` is enough:

```
D:\World of Warcraft\_anniversary_\Interface\AddOns\GearScout       -> gearscout\GearScout
D:\World of Warcraft\_anniversary_\Interface\AddOns\GearScout_Lead  -> gearscout\GearScout_Lead
```

To hand it to guild members, zip the `GearScout` folder only. Give `GearScout_Lead` to officers only.

## Commands

| Command | What it does |
| --- | --- |
| `/gearscout` or `/gscout` | Open the coach window |
| `/gearscout scan` | Re-read your gear and print the score |
| `/gearscout rot` | Print which rotation spells were detected for your spec |
| `/gearlead` or `/gsl` | Open the officer console |
| `/gsl group` | Open it and immediately scan your party or raid |
| `/gsl guild` | Open it and immediately scan online guild members |

## The privacy split

This is a design decision, not a side effect.

A member's copy registers a handler for exactly one opcode, `q`, which means "someone is asking for your gear". It sends a reply and nothing else. There is no code in the base addon that stores or renders another player's equipment, so a member cannot see the raid's gear even if they want to.

The officer addon is what registers handlers for `d` (gear data) and `x` (declined). Installing that folder is what grants the ability.

Members control who may ask, in Settings:

- group leader and assistants (default)
- anyone in my guild
- anyone who asks
- nobody, decline every request

A decline sends an explicit refusal, so the lead sees "declined" rather than mistaking it for a missing addon.

Worth being honest about: addon Lua ships as readable text. A determined person can edit their own copy. The split is a privacy design for normal use, not copy protection.

## What the gear audit checks

All of it from data the client already has. No item database ships with this addon.

- Empty slots, with an empty off hand next to a two hander correctly ignored
- Missing enchants, with the enchantable slot list resolved per character (rings only count if you are an enchanter, the ranged slot only if it is a bow, gun or crossbow, the off hand only if it is a weapon or shield)
- Empty gem sockets, counted from the base item so inserted gems do not hide the socket count
- Wearing lighter armor than your class allows from level 40
- Green or white items at level 68 and above
- Any piece far behind the median of everything else you own
- Items simply too low for your level
- Stats your class cannot use, only from level 60 and only above a threshold
- Broken gear

Score starts at 100 and loses points per problem. It measures wasted potential, not item rarity.

## What the rotation tracker checks

The recorder listens to `UNIT_SPELLCAST_SUCCEEDED` filtered to the player through `RegisterUnitEvent`, so the client discards every other unit's casts before Lua runs. It deliberately does not touch `COMBAT_LOG_EVENT_UNFILTERED`, which is the usual cause of frame drops in trackers like this. Recording one cast writes two numbers into two preallocated arrays.

Analysis runs once, when combat ends:

- Uptime on maintenance spells, reconstructed from your own cast times and the known debuff duration
- Cooldowns used against how many uses the fight length allowed
- Buttons your spec cares about that you never pressed
- Gaps longer than three seconds with nothing cast

Spec detection uses the talent tab with the most points. Spell ids in `Profiles.lua` exist only to resolve the localized spell name, so every rank counts as the same button and the addon works in any client language. An id that fails to resolve is dropped quietly.

## Details integration, optional

If Details is loaded, the report is enriched after each fight using only functions marked exported in Details' own `API.lua`: `GetCurrentCombat`, `GetCombat`, `GetCombatTime`, `GetCombatName`, `GetActor`, `GetSpellList`, `Tempo`. That adds damage per second, damage share per spell, and a more accurate idle time than the gap estimate.

Every call is wrapped. If Details changes shape, the bridge disables itself for that fight and the native report still stands. The segment length is sanity checked against the recorded fight length so the wrong segment is never attached.

## Network behaviour

Blizzard gives each addon message prefix an allowance of 10 messages that refills at 1 per second. Going over it drops messages silently.

- Every send passes through a token bucket capped at 8, two under the real limit
- The drain timer only exists while something is queued
- Replies are jittered up to 2.5 seconds so a full raid does not answer in the same frame
- A gear payload is roughly 500 characters, sent as three chunks of 200
- Replies go by whisper to the requester, not to the raid channel

## UI notes

- Lists are virtualized. A 40 man roster builds the same row frames as an empty one
- No permanent `OnUpdate` anywhere. The only one is a self cancelling tween on the score bar, plus one that exists solely while the minimap button is being dragged
- Panels are flat textures with hairline borders rather than the Backdrop API, which has changed shape between clients
- Open animations run as AnimationGroups so interpolation happens on the C side
- Frames sit in the DIALOG strata and every panel enables mouse, so clicks near the chat frame do not fall through

## Adding a spec

Edit `Profiles.lua`. Entries are keyed by class file name then talent tab index (1, 2, 3 in the order the game shows them).

```lua
{ id = 772, kind = "dot", dur = 21 },   -- Rend
```

`kind` is one of `dot` (maintain on target), `buff` (maintain on self), `cd` (use on cooldown, needs `cd`), `core` (main button, counted only), `proc` (never judged).

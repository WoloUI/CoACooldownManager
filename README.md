# CoA Cooldown Manager

**A retail-style Cooldown Manager for Project Ascension (WoW 3.3.5a).**
Built by **WoloUI** for the classless CoA realms.

Retail WoW got a built-in Cooldown Manager. 3.3.5 never did — you got WeakAuras, and
a weekend of writing custom Lua for every aura you wanted. CoA Cooldown Manager gives
you the same result with **dropdown menus only: never a line of code**, and it is built
from the ground up for Ascension's classless, re-ID'd, high-mutation spell system.

---

## Why it exists

Ascension breaks most 3.3.5 addons in three specific ways, and CoACDM is designed around
all three:

- **Spell IDs change between patches.** CoACDM stores spell **names**, not IDs, everywhere.
  A name also follows the learned rank automatically, so nothing silently stops tracking.
- **There are no classes.** Nothing in the addon assumes a class, a spec, or a fixed
  resource. Bars auto-detect what you actually have.
- **The API is a custom backport.** CoACDM uses Ascension's own APIs where they exist
  (`GetSpellCharges`, `UnitGetTotalAbsorbs`, `C_CharacterAdvancement`) and degrades
  gracefully where they don't.

---

## Features

### Viewers — build any bar you want

Everything you see is a *viewer* anchored in a hierarchy off the root Power bar. Ships with
Essential / Defensives / Utility / Buffs / Target DoTs / Reminders / Alerts, plus
**unlimited custom bars** of your own.

Eight display styles per bar:

| Style | What it shows |
|---|---|
| **Icons** | Cooldown sweep, charge counts, keybind text, desaturate-when-unusable |
| **Bars** | Duration status bars that drain smoothly |
| **Power** | 1–2 auto-detected resources, energy ticks, combo points |
| **Stacks** | CoA pseudo-resources (Reaper Souls, Occultist Sanity) as segments or a continuous bar |
| **Shield** | A vertical curved segment column that drains with your absorb shields |
| **Swing** | Swing timer |
| **Cast** | Cast bar |
| **Reminders** | Text alert rows |

Each bar tracks four kinds of element: **spells**, **items** (consumables),
**trinkets** (with internal-cooldown gray-out after a proc), and **summons**
(pet/guardian duration timers). Element order in the config *is* display order, with
`^` / `v` buttons to reorder.

### Triggers — conditional logic, no scripting

A base trigger plus chained conditions, all from dropdowns. Conditions can be
**cross-spell**: "show this only while *another* aura is up", "only when its stacks are
above N", "only when that other spell is off cooldown", "only while my pet is out".
Actions include **glow** and **play sound**, edge-triggered so a sound fires once on
false→true and re-arms cleanly. Pet buffs are trackable as first-class units.

### HoT / buff tracking on your existing unit frames

Draws your **own** heal-over-time and buff indicators directly onto your ElvUI or Blizzard
party/raid frames — 9 anchor points with offsets, icon or colour square, and per-spell
time / sweep / stacks / blink options.

This is the part that took the most engineering. Frames are discovered by *walking* the
real frame children and mapping by `IsVisible()` (ElvUI leaves hidden raid headers
reporting `IsShown() == true`, which silently splits your map across two headers in a
34-man raid). Indicators require `aura.mine`, matching ElvUI's own oUF_AuraWatch
ownership rule, so you never light up on another healer's HoTs — with an opt-in
`anyCaster` checkbox per indicator when you *do* want that.

### Screen overlays

Standalone, account-wide, draggable in edit mode, each with an optional edge-triggered sound:

- **Missing Raid Buffs** — a row of icons for every raid buff category you're missing.
  16 categories / 137 buff names, generated from the community "CoA Buff Reminders"
  WeakAura. Hidden in combat by default: it's a pre-pull checklist, not a nag.
- **Aggro Alert** — "AGGRO ON YOU" with arrows when you take threat in combat.
- **Range Alert** — "OUT OF RANGE" when your target is outside melee reach. 3.3.5 has no
  `UnitInMeleeRange`, so this probes `IsSpellInRange` against your configured spell, then
  Auto Attack, then any short-range spell in your book — and stays silent rather than
  lying when the client can't tell.

### Reminders

Aura-by-ID and weapon-enchant reminders with custom text, recomputed on a 0.3s tick.

### Edit mode & appearance

Drag every bar with 12px magnet snapping to other bars and to screen centre. A movable
**ExtraActionBar** (bar and individual buttons). LibSharedMedia fonts and textures
(consumed if another addon provides it, never embedded), font scaling, frame strata
selector, and five glow styles — proc flipbook, pixel, pulse, shine, solid — with a
colour picker.

### Class HUD hider

An on-screen picker that hides CoA's built-in class HUDs (resource orbs and friends):
hover, left-click to hide, right-click to cancel. Per-profile, and re-hides on show.

### Profiles

Config is **per character**, which is what you actually want on a classless server —
layouts live per character so anchors never bleed between alts. Named profiles are
account-wide **templates**, loaded *by copy* on assignment: deleting a template never
touches the character copies that came from it. Import/export via `!CDM1!` base64
strings, parsed by a hand-written token parser (never `loadstring`).

### Spell scanner

Run it when you want (`/cdm scan` or the panel button). Parses tooltip cooldowns, uses a
spell-hint table and keyword heuristics, and hands you a suggestions window.

---

## Installation

1. Extract the `CoACooldownManager` folder into
   `Interface/AddOns/`.
2. **Fully restart the game client.** Not `/reload` — the addon loads new files, and
   3.3.5 only reads the `.toc` at startup.
3. Type `/cdm`.

Optional but recommended: ElvUI (unit-frame tracking + skinning) and LibSharedMedia.

## Commands

| Command | Does |
|---|---|
| `/cdm` | Open the config panel |
| `/cdm edit` | Toggle edit mode (drag bars) |
| `/cdm test` | Test mode — fills bars with fake data so you can position them solo |
| `/cdm scan` | Run the spell scanner |
| `/cdm debug` | Dump unit-frame mapping and cached auras (tracking triage) |
| `/cdm range` | Print melee-range probe candidates and raw results |
| `/cdm trinket` | Trinket diagnostic |
| `/cdm minimap` | Toggle the minimap button |
| `/cdm reset` | Reset positions |
| `/cdm resetextra` | Reset the ExtraActionBar position |

Minimap button: **left-click** config, **right-click** edit mode, **drag** around the rim.

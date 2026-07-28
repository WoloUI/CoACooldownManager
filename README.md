# CoA Cooldown Manager

**A retail-style Cooldown Manager for Project Ascension (WoW 3.3.5a).**
Built by **WoloUI** for the classless CoA realms.

Retail WoW got a built-in Cooldown Manager. 3.3.5 never did — you got WeakAuras, and
a weekend of writing custom Lua for every aura you wanted. CoA Cooldown Manager gives
you the same result with **dropdown menus only: never a line of code**, and it is built
from the ground up for Ascension's classless, re-ID'd, high-mutation spell system.

![Bars and the configuration panel](.github/screenshots/config-panel.png)

---

## Screenshots

**Edit mode** — every bar labelled and draggable, with the Missing Raid Buffs checklist,
the AGGRO ON YOU arrows and the OUT OF RANGE warning all live on screen:

![Edit mode with the screen overlays](.github/screenshots/edit-mode.png)

**HoT tracking** — pick a spell, then place its indicator on the party/raid frame with the
preview grid. Test mode shows fake indicators so you can position them without a group:

![The Tracking tab and HoT indicator placement](.github/screenshots/hot-tracking.png)

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

Each bar tracks five kinds of element: **spells**, **items** (consumables),
**trinkets** (with internal-cooldown gray-out after a proc), **summons**
(pet/guardian duration timers), and **totems** (a totem slot, gray while empty). Element order in the config *is* display order, with
`^` / `v` buttons to reorder.

- Add spells four ways: drag from the spellbook onto the config panel, drop them on a
  bar in edit mode, shift+click them in the spellbook with a bar selected, or accept a
  scan suggestion. All four build the element the same way, and the bar's style decides
  what it becomes — the same spell is a cooldown on an icon row and a draining debuff on
  a duration bar.
- Power bars: per-bar text mode — current/max, current only, percent, or hidden.
- Per-bar `Timer` toggle, so target debuffs can show just their stack count.

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

**GCD sweep** (per icon bar, off by default) runs the global cooldown sweep on that bar's
icons, but only while the GCD outlasts the spell's own cooldown — the same rule WeakAuras
uses, so icons stay readable instead of flickering on every cast. **GCD time** adds the
countdown on top of it.

### Totem tracker

Totems are read from the *slots* rather than a spell list, so whatever this server plants
there — a shaman's four totems, a Witch Doctor's idols, wards and effigies — shows up with
its own icon, name and timer. `/cdm totems` prints what the client reports per slot.

Add a **Totem** element to any icon bar: sweep and time left while the totem stands, and a
**gray icon while it does not**, so an empty slot still tells you what to re-plant. Pick a
slot — the icon and the totem's real name are learned the first time you plant one, and
until then the placeholder borrows whatever your totem bar has on that slot — or match by
the totem's name instead.

Totems with their own cooldown sweep it on the gray icon, so you can see when the re-plant
is coming up rather than just that it's gone — which is the whole story for something like
Stasis Ward, up for 2 seconds and cooling for 45. The planting spell is resolved
automatically (your totem bar's spell for that slot, then the totem's own name); there's an
optional field for it when the two names differ.

Being ordinary elements, they take the whole trigger builder, so a **glow or a sound** is
two dropdowns away:

- *This spell ready* = **can be planted now** (down *and* off cooldown) — the actionable
  alert. Not "while it's down", which on a 2s/45s totem would fire almost permanently.
- *Time left* is the **totem's** own remaining time, 0 while it's down, never the
  cooldown's.

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

Run it when you want (`/cdm scan` or the panel button). Reads the tooltip of every active
spell and hands you a scrollable, searchable suggestions window: pick which of *your* bars
each spell should go to, or dismiss it.

**One suggestion per spell, not per rank.** The spellbook lists every learned rank as its
own slot; the scan keeps one row per name and follows the highest rank. On a real Pyro
spellbook that is 100 of 159 slots collapsed away.

**Filtering is per spellbook tab**, because that is what actually separates junk from
abilities on this server: racials, PvP toggles, mounts and hearthstones live in the general
tab and Ascension's toys in its own *Ascension Vanity Items* tab, while real spells live in
the specialization tabs. Both junk tabs are unticked by default and every tab gets a
checkbox, read live from the client so the names always match your spec.

> A note for anyone tempted by `C_CharacterAdvancement`: it is **not** a usable
> "is this a class ability" signal here. It answers for only a fraction of spells — on a
> live Pyro, Eruption and Spellburn read as non-CA while sitting on the player's own bars.
> The optional `Only class/spec spells` toggle uses it, off by default, and asks every rank
> because the CA entry is registered against the base rank only.

**Cooldowns are not the only thing worth a bar.** Plenty of spec spells have no cooldown
line at all, so the scan also reads aura durations (`for 19 sec`) and suggests those as
target DoTs or self buffs on a duration bar. A spell with neither a cooldown nor a duration
has nothing a bar could show, and is left alone.

Spells you dismiss with `X` stay dismissed, even across a manual scan, and the General page
lists them so you can put one back. Two diagnostics, because tooltip wording and the
client's own spell data cannot be inspected outside the game: `/cdm scan debug` prints a
per-tab summary and why each spell was kept or dropped, and `/cdm scan tip <spell>` dumps a
raw tooltip line by line next to the cooldown it parsed.

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
| `/cdm gcd` | Show which global-cooldown probe answers on this server |
| `/cdm totems` | Dump every totem slot's raw contents |
| `/cdm trinket` | Trinket diagnostic |
| `/cdm minimap` | Toggle the minimap button |
| `/cdm reset` | Reset positions |
| `/cdm resetextra` | Reset the ExtraActionBar position |

Minimap button: **left-click** config, **right-click** edit mode, **drag** around the rim.

---

## Support

This addon is free, and it stays free. It was built raid night by raid night, on feedback
from people who kept telling me what was still annoying — and it's better for it.

If it saved you a weekend of writing WeakAuras, or just made your healing feel good, you can
buy me a coffee at **[ko-fi.com/woloui](https://ko-fi.com/woloui)**. Completely optional and
genuinely appreciated. ☕

Either way, thanks for playing with it. Bug reports and ideas are worth just as much.

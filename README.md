# SKTools-ESO

SKTools for **The Elder Scrolls Online**: the look and feel of
[SKTools for WoW Forever](https://github.com/chri5w00ds/sktools), rebuilt for ESO.

| Part | What it does |
| --- | --- |
| Resources | Health, Magicka and Stamina bars in one framed block, with a cast bar for channelled abilities and damage shields on the health bar |
| Skills | Front and back skill bars side by side, with cooldown sweeps, skill timers and a resource frame that fills as you build up to a skill's cost |
| Stamina tick | A spark sweeping across the stamina bar to the next regeneration tick, with the moment before it marked |
| Buffs | The effects on you: Major and Minor buffs growing left, Major and Minor debuffs growing right, and every other effect in Other buffs and Other debuffs panels |
| Instance | Its own element: the effects an instance and its enemies put on you in dungeons, trials and arenas |
| Group | Which group member has which of the effects you watch, in a grid |
| Synergy | For tanks: which group member can take which synergy, with each one's 20-second cooldown |
| CC alert | A resizable banner naming the CC on you and whether to Break Free or Roll Dodge, with a sound |
| Minimap | A round map of where you are, following you, with your location above it and your own time in it |
| Keybinds | One account-wide set of keybinds: save it from one character, switch it on for the others |

## Look

The bars and icons copy the WoW Forever version: SKTools pastels shaded light at the top and dark
at the bottom, fine dark seams between bars, and a thin frame with rounded corners (silver round
the resource bars, white round the skill icons). Everything is drawn with vertex colours, so the
addon's only image files are the minimap's view cone, a circle (the mount pill's ends) and
the bee. The settings window is dark navy with ESO trim: the bee and a gold title, a bronze divider with a
diamond, and each tab laid out in sections under gold headings.

## Use

- **`/sktools`**, or the bee on the left of the minimap's location strip, opens the settings window, with one tab per part. The bee faces right, and left while the window is open.
- **`/sktools unlock`** / **`/sktools lock`**, or **Lock all elements** in the General tab, unlock and lock every element for moving.
- **`/rl`** (or **`/reload`**) reloads the UI.
- Settings are account-wide by default; the General tab can give a character its own profile.

### Resources

Top to bottom: Health, Magicka, Stamina, and the cast bar along the bottom while you channel
(nothing above it moves). Percent on the left of each bar, the value on the right. While you ride, your mount's stamina shows as a
narrower green pill under the bars. A damage
shield shows as a pale band over the top of the health bar, as long as the shield, with the
amount in blue beside your health. ESO's own resource bars are hidden while
the block shows.

Options: width and bar heights, track opacity, gradient (darker on the left), cylinder shading,
a colour for each bar, hide when full and out of combat.

### Skills

```
 Front            Back
[2] [4] [ULT]    [2] [4] [ULT]
[1] [3] [ 5 ]    [1] [3] [ 5 ]
```

- **Cooldown sweep**: the global cooldown and real cooldowns, each with its own opacity.
- **Skill timers**: the time left on each skill's buff, damage or heal over time, on both bars,
  in the middle of the icon (whole seconds, tenths in the last second). Delayed skills such as
  Budding Seeds count down to the bloom, and Subterranean Assault counts both detonations (6 s).
- **Resource frame**: short of a skill's cost, the icon greys and a thin frame in the resource's
  colour fills clockwise from 12 o'clock as you build up to it. The ultimate fills as your
  ultimate charges.
- **Ultimates**: each ultimate shows how close you are to its cost, in percent, until it's ready;
  a thin meter in the gap between the halves fills with your ultimate out of 500.
- **Moving skills**: drag a skill to another slot on the bar you're on (or drop one from the skills
  window), out of combat. Hover over an icon for the skill's tooltip.
- The bar you are not on is dimmed. ESO's own action bar is hidden (keybinds keep working).


### Stamina tick

Stamina comes back in ticks, every 2 seconds in combat; blocking or sprinting as a tick lands
gives nothing back. A spark sweeps across the stamina bar and reaches the right end as the tick
lands. An optional sound plays a set time before each tick. The timer locks onto your real ticks.
Switch it on or off in the General tab.

### Buffs

The effects on you in four panels: **Buffs**, growing left from their right edge, and
**Debuffs**, growing right from their left edge, each with a Major and a Minor row; and **Other
buffs** (growing left) and **Other debuffs** (growing right), with everything else (skill
buffs, set procs, food). A row is as long as it has effects. Icons in the Essentials style with
the time left in the middle, stacks in the corner and a blink in the last 3 seconds. Effects that
never run out are left out of the Other panels unless you want them. With the cursor shown, each
icon has the game's tooltip for its effect. The panels hide over the map and menus.

### Instance

Its own element and tab: inside dungeons, trials and arenas, the buffs and debuffs that the
instance itself and its enemies put on you, kept apart from your own (top row buffs, bottom row
debuffs, growing out from its centre). Switched off, those effects go in the Other rows.

### Group

One row per group member (you included; tanks first, then healers, then damage dealers, each
with their role's icon), one column per watched effect, the effect's icon on top
(its name in a tooltip). A member who has the effect gets a cell filled green that sweeps away like the
skill bars' global cooldown, leaving black, with the time left; one who hasn't gets an empty cell with a dash. Dead or offline members are dimmed. The watched effects
are a list you edit and reorder in the Group tab (starting with Major Courage, Major and Minor Berserk, Major
Slayer, Powerful Assault, Major Force, Minor Toughness and Major Resolve); an effect's icon is
learnt the first time anyone in the group has it.

### Synergy

For tanks, in the group buffs' style: one row per group member, one column per synergy family
(every morph of a skill shares one cooldown, and so do Spear Shards and Necrotic Orb). Green
means ready; just taken, the cell darkens with the skill bars' cooldown sweep and the seconds left
of its 20-second cooldown. Shown while you're queued as a tank (or always). The families are a
list you edit and reorder in the Synergy tab: a name, then the synergies in it, separated by
commas.

### CC alert

When an enemy crowd controls you, a banner names the CC and the ability that caused it and tells you
what gets you out: **» BREAK FREE «** for stuns, knockdowns, fears, charms and disorients,
**« ROLL DODGE »** for roots and immobilizes (snares and silences can be switched on too). A bar
drains over the CC's duration, and each action has its own sound. Unlock to place it on the grid
and set its width, height and background.

### Minimap

A round map of where you are (the game's own map of your zone, city or delve), north up,
following you, with your arrow in the middle turning with you and a soft cone showing where the camera looks,
in a thin silver ring. Your
location sits above it in its own frame, and your own time inside the circle at the bottom. Pins
show quests (the one you're following bigger), wayshrines and other places, your waypoint and
your group (round dots, the leader bigger and gold). Zoom
with the mouse wheel over it or the Zoom slider.

### Keybinds

On the character whose keybinds you want everywhere, press **Save as the account set**. On each
other character, tick **Use the account keybinds**: they are applied straight away and at every
login. The first time, that character's own keybinds are kept as a backup, and **Restore own
keybinds** puts them back. Keybinds are matched by action name, so they land on the right actions
even when addons add or remove keybinds. **Keep the account set up to date** copies changes made
on a character that uses the set back into it.

### Moving elements

While unlocked, a faint grid covers the screen (bright lines crossing at the middle) and each
element shows its name above a thin gold outline. Elements
are dragged box by box, so where they show while dragging is where they stay, and their sizes
are taken in whole grid boxes, so every frame line lands on a grid line. Snap to grid and the
grid size are in the General tab.

## Install

Copy the `SKTools-ESO` folder into
`Documents/Elder Scrolls Online/live/AddOns/` and enable it in the in-game AddOns list.

## Credits

Created by **Scotskoogen-Chris**. Licensed under the GNU GPL v3 (see `LICENSE.txt`).

# SKTools-ESO

SKTools for **The Elder Scrolls Online**: the look and feel of
[SKTools for WoW Forever](https://github.com/chri5w00ds/sktools), rebuilt for ESO.

| Part | What it does |
| --- | --- |
| Resources | Health, Magicka and Stamina bars in one framed block, with a cast bar for channelled abilities and damage shields on the health bar |
| Skills | Front and back skill bars side by side, with cooldown sweeps, skill timers and a resource frame that fills as you build up to a skill's cost |

## Look

The bars and icons copy the WoW Forever version: SKTools pastels shaded light at the top and dark
at the bottom, fine dark seams between bars, and a thin frame with rounded corners (silver round
the resource bars, white round the skill icons). Everything is drawn with vertex colours, so the
addon has no image files. The settings window is a dark navy with a classic silver border.

## Use

- **`/sktools`** opens the settings window, with one tab per part.
- **`/sktools unlock`** / **`/sktools lock`** unlock and lock every element for moving.
- Settings are account-wide by default; the General tab can give a character its own profile.

### Resources

Top to bottom: Health, Magicka, Stamina, and the cast bar along the bottom while you channel
(nothing above it moves). Percent on the left of each bar, the value on the right. A damage
shield shows as a lighter segment after the health fill. ESO's own resource bars are hidden while
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
  Budding Seeds count down to the bloom.
- **Resource frame**: short of a skill's cost, the icon greys and a thin frame in the resource's
  colour fills clockwise from 12 o'clock as you build up to it. The ultimate fills as your
  ultimate charges.
- The bar you are not on is dimmed. ESO's own action bar is hidden (keybinds keep working).

By default the pane sits on top of the resource bars, the two frames sharing a line.

### Moving elements

While unlocked, a faint grid covers the screen (bright lines crossing at the middle). Elements
are dragged box by box, so where they show while dragging is where they stay, and their sizes
are taken in whole grid boxes, so every frame line lands on a grid line. Dragged near the top of
the resource bars, the skill pane snaps onto them. Snap to grid and the grid size are in the
General tab.

## Install

Copy the `SKTools-ESO` folder into
`Documents/Elder Scrolls Online/live/AddOns/` and enable it in the in-game AddOns list.

## Credits

Created by **Scotskoogen-Chris**. Licensed under the GNU GPL v3 (see `LICENSE.txt`).

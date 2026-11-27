# Changelog

## 1.1.3

- New option "Countdown to regeneration" on the Liquid tab (off by default): after each spell a small ring next to your mana tube fills up over the five seconds until mana regeneration resumes, optionally with the seconds shown.
- New slider "Heal preview strength" on the Liquid tab: higher values make the incoming heal preview brighter, with a soft shimmer at its edge; 100 % keeps the current look.
- The preview's "Heal" button now also shows the heal preview, and a new "Countdown" button plays the ring.
- With PvP enabled, Blizzard's large faction flag no longer covers the portrait ring and tubes; a small faction crest now sits neatly on the ring instead.

## 1.1.2

- Hidden Blizzard buff and debuff buttons under the target frame no longer catch the mouse, so tooltips match the icons you see.
- With Blizzard's "Both" status text the percent and the number now sit cleanly at the left and right of the tube, clear of the portrait ring.
- The settings preview now shows exactly the numbers and positions of your real frames, including Blizzard's rounding and short numbers.
- New option "Show regeneration clearly" on the Liquid tab (off by default): a bright pulse marks the moment mana regeneration resumes after the five-second rule, with a test button in the preview.

## 1.1.1

- Leftovers of Blizzard's power bar (full-resource pulse, gain/loss flash, cost preview, spark) no longer show on top of the power tube.
- Your own number formats show nothing instead of "0 / 0" or "0%" for a unit without that resource.
- The target-of-target tube now changes colour when its resource type changes.

## 1.1.0

- Redesigned settings window with six tabs (General, Liquid, Portrait, Text & numbers, Font, Profiles) and its own values per frame.
- A live preview sits beside every tab, with sliders for health, power and experience, a target type picker, test buttons and a dark, light or game-world background.
- Every slider marks its default value, and a right-click resets it; dropdowns and checkboxes name their default too.
- Choose the font for every text element: three new bundled fonts, the Blizzard fonts and the fonts of other addons via LibSharedMedia.
- Health, power and experience can show a permanent value text, with several formats, a number that floats on the liquid level or one etched into the glass.
- Blizzard-style numbers can stay in Blizzard's spot or sit centred in the tube.
- The player and target portraits get four animated styles: living painting, submerged in the vial, a reacting model and a plain animated model.
- The new Profiles tab lets every character use its own profile, with create, copy, rename and reset.
- Out of the box everything looks exactly as before; all of this is optional.

## 1.0.2

- The boss ornament on the target portrait now sits cleanly on the ring, and the quest symbol no longer covers a horn.

## 1.0.1

- In combat the liquid now takes the colour of the debuff's border: blue for magic, purple for curse, orange for disease, green for poison, red for everything else.
- The grey veil in combat is gone.
- In WoW Forever the frames show the full name with surname.

## 1.0.0

- First release: the player, target and target-of-target frames become bronze glass vials with liquid health and resource.
- The liquid sloshes with your movement, glides to new values and leaves a glowing damage trail.
- Hits, heals, mana regeneration, shields and debuffs show as effects inside the glass.
- The experience bar becomes a liquid tube with a rested section and a level-up effect.
- The target portrait gets dragons for elite and rare, a crest for bosses, a raid marker, the quest symbol and a level gem.
- Two looks: piston chamber (default) or plain liquid edge, switchable with `/vials style`.
- Settings window via `/vials config` and in the game's AddOns options; `/vials` lists all commands.
- Works on WoW Forever and Retail, alone or together with Lucid.

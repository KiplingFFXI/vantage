# Changelog

## 1.1.1

This update fixes bugs found since 1.1.0 and brings the effect data up to date with Phoenix. A mob's Stoneskin now goes away once damage gets through.

- A mob's Stoneskin, or a pet's, such as from Metallic Body, comes off its timers at the first hit or spikes that get damage through. The game sends no one the wear-off for a mob's own buff, so before, a mob's icon stayed for minutes after it was gone.
- The effect data now follows Phoenix's source at `ed41f351f6`, from October 30. Party members' timers count down for many more job abilities, such as Boost from 3 minutes and Focus from 2. More spells, blood pacts and mob moves have a length too, and a few lengths changed to match Phoenix, such as Leaf Dagger's Poison.
- With **Icons show** on **The effect it gives**, many more job abilities show their status picture from the start, such as Berserk and Divine Seal, on recasts, Party cooldowns and the Pet display. Before, most showed it only once you'd used them that session. Jump, Chakra, Charm, Chi Blast, Double-Up and Cure I to V keep their own picture, as they give that status only sometimes.
- The first time you use a job ability after you log in, zone or change jobs, its recast shows its full length and its **Recast started** alert goes off. That goes for a use Paralysis stops too, as Phoenix still starts the recast unless it's a two-hour. Your first Blood Pact after you zone also gets its full length, even when your avatar runs a while before it goes off.
- Typing "nan" into **Blink seconds left** no longer stops every save after it, and the slider is now wide enough for its text.
- If a hand edit or `/vg set` turns a display or an overhead icon type in your settings into a number or true/false, Vantage drops it at load. Before, it broke the settings window.
- Picking from an effect or recast list with a find box, such as an alert's **Effect** or **Never pulse for**, closes the list. Before, it stayed open.
- A settings or profiles file with nothing but blank space counts as empty, like an empty file. Before, Vantage reported it as broken and wouldn't save over it.
- `/vg get` and the `/vg set` confirmation show text in quotes, so text of only spaces shows. Before, a separator of one space looked empty, and setting it back as shown emptied it.
- **Down** in **Parts of a row** and in **Member order** no longer shows the moved entry twice for a frame and leaves out the one it changed places with. **Remove** beside someone no longer in your party had the same kind of bug.
- In edit mode, the bar sits at the bottom of the screen while the settings window is open at the top, so the window's title and top row stay clear.
- At a big **Settings text size**, the settings window's bottom corners no longer take clicks meant for the rows under them.
- **Saved profiles** is greyed out and says "No saved profiles yet" when you have none. Before, it opened an empty list.
- A report made after Vantage finds the game's party windows says it found them. Before, it still said it was waiting for the party list.
- Vantage does less work while the settings window is open, most of all on **Timer durations**, **Profiles**, the **Size and place** tab of Party list buffs and a display's own page.

## 1.1.0

This update adds a way to show only the effects job abilities put on your party. It also fixes some bugs, and Vantage does less work every frame.

- **Only effects from job abilities**, on the **Filters** tab of Party members' timers and Party list buffs, shows only what job abilities put on your party, such as Berserk, Focus and Warcry. Rolls, maneuvers and blood pacts count too. Both start off, and the starter profiles turn them off.
- The main page says more about what Party members' timers and Party cooldowns show.
- Vantage does less work every frame, most of all in an alliance and while the settings window is open.
- An export made with 1.1.0 that holds the new tick, such as a whole profile, can't be read by 1.0.0. It asks you to update Vantage.
- Party cooldowns forget a member's old job abilities when they change jobs, even with Party list buffs off. The two-hour stays.
- A display whose **Moves with** puts it past the edge of the screen moves at the first arrow key press or drag. Before, it didn't move until you had undone the part past the edge.
- An **Effect removed / wore off** alert now goes off for your pet's Regen from Reward or Repair and for the boost from Deep Breathing. The game's wear-off for these can come just after Vantage takes them off on time.
- Exporting a whole profile leaves out a duration override that's only on one of your characters. Before, it went out with no name, which put it on everyone.
- **Import and add** no longer mixes your spot for a display with the imported one. A display you've moved keeps its whole spot and its **Moves with**, and one you never moved takes the imported spot.
- `/vg set` won't make displays move with each other in a circle, and a display that only moves with one of them keeps its **Moves with**.
- A search result for a tab or a row that doesn't name a display opens a display that has it. Before, it could open one that doesn't.
- Escape with the edit mode bar's **Display** list open only closes the list. Before, it ended edit mode too.
- `/vg watch` and `/vg unwatch` with something other than a number after them say so and do nothing. Before, they used your target.
- Settings saved by a newer Vantage stay in your file when you load them here, so going back a version and forward again keeps them.
- An overhead icons setting Vantage doesn't know, from a newer Vantage or a hand edit, gives no icons and breaks nothing.
- The **Always show** tooltips and the guide now say what an unticked effect on **Show only** does. The guide also says when Blank Gaze lights buffs again after a reload.

## 1.0.0

This is the first public release. Vantage is an Ashita v4 addon for FFXI on Phoenix. It shows buff, debuff and recast timers that you can move, size and style, and it can put buffs beside the game's party list. The game's own windows stay as they are.

- Timer panels for your own buffs and debuffs, your target, party members and the enemies you watch. Each one can show bars, expanded bars, icons or text.
- Recasts for spells, abilities and equipped enchanted items, in separate panels or one combined panel.
- Buffs beside the game's party list, for your party and each alliance party.
- Overhead icons, Party cooldowns, and the Phantom Roll and pet displays. These start off.
- Hidden everywhere, a Filters tab on each display, and When to show rules.
- Alerts for gains, remaining time, removals and missing effects. They can show as notices, row emphasis or a line in your chat log, or play your own sounds.
- Skins, Original FFXI and XI View client artwork, and fonts of your own.
- Starter profiles for melee, tanks, healers, support, crowd control and pet jobs.
- Named profiles that every character can load and link to jobs. You also get Undo, Redo, import and export, and resets for one part of your setup at a time.
- Edit mode, Grid mode and Moves with.
- `/vg report` and **Export report** say what Vantage found, to help when something looks wrong.

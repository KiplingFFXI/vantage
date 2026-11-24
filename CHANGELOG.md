# Changelog

## 1.4.0

This update adds a lot to the Pet display and Party list, reworks the settings window, shows debuffs the game doesn't announce, and makes each frame much lighter. Some things have new names: Hidden everywhere is the **Hide list**, the buffs beside the game's party list are **Party list**, edit mode is **Arrange on screen**, **Grid mode** is **Snap while moving**, Starter profiles are **Quick setup for a role**, **Reset this display** is **Reset all of this display**, **Mark recasts I can't use right now** is **Tint recasts I can't use right now**, an alert's **Repeat reminder** is **Repeat every**, and **Tallest** on Phantom Roll, Pet, the party cooldown list and Alerts is **Height**.

### Pet

- New ticks on Pet's **Show** tab, all off at first, show what your pet is fighting and doing, its last move, how far off it is and how long it has been out.
- For an automaton they add timers for the attachments that fire on their own, such as Strobe and Flashbulb, its own spell and ability cooldowns, its build, and its MP as a number like 168/420.
- They also show what an avatar costs you in MP, when Healing Breath would fire, a mark where Sic is ready and what Reward would heal.
- Alerts can tell you when your pet's HP is low, when it has 1000 TP, and when a charm or a jug pet is about to end. They're under **Your pet** on Alerts' **Show** tab, and they start off. They need the Pet display on, and Alerts says so while it's off.
- **Replace the game's pet bar**, under **While playing**, hides the pet's name, HP bar and TP that the game draws above the party list, so the Pet display is the only one. It starts off. Like **Replace the game's buff icons**, it changes one spot in the game's memory, checks that spot first, and puts it back when you turn it off or unload Vantage. While Pet's **When to show** hides the display, the game draws its own bar.

### Party

- **Party list** can show how far each member is from you, with a warning color past spell range or past a distance you pick.
- **Icon size beside the game's list** gives those icons a size of their own. Smaller ones sit in the middle of each member's row, and bigger ones go in a stack with each member's name.
- Party list's **Sort** has **My order** now, as the timer panels do, so its effects go in an order you pick. **Add to My order** on its **Filters** tab adds one.
- Party members' timers can show your own effects too (**Include me**), and one cast on several members, like a Protectra, as one row (**One row for a cast on several members**).
- Party cooldowns watch Sneak Attack, Trick Attack and Utsusemi too. Utsusemi's time is the recast the game sent.

### Timers and alerts

- Debuffs the game doesn't announce on a mob now show, with the usual time as an estimate. That covers weapon skills like Shield Break and Full Break, pet moves, Shield Bash, Tomahawk, Feint, Ice Spikes' Paralysis and more. A resist looks the same to Vantage, so now and then one shows that never landed.
- A monster move whose time Phoenix rolls shows the range, like `2m - 8m`, with both ends counting down.
- Pointing at an effect says what it does, in the game's own words, right under its name.
- Timer panels can be up to 2400 pixels wide, and their rows can go into columns.
- Recast rows that share one timer read one name: **Maneuvers**, **Phantom Roll**, **Quick Draw**, **Blood Pact: Rage**, **Blood Pact: Ward** and **Sic**. Effect names like **Paralysis** have their capitals.
- Alert notices can have their own **Notice text size** and **Notice text color**, and each alert can give its notice a color of its own.
- On Alerts' **Show** tab, **Haste reminder**, **Sleep reminder** and **Silence notice** are now **Haste ending**, **Sleep ending** and **Silenced**, and **Shadows gone** and **Recast ready** are new. **New alert** and **Recast ready** stay off until you choose what they watch, and so does an alert that's on when you change its **Alert type**.
- `/vg watch` with a player targeted says **Target an enemy first.** instead of watching them. To watch a player, type `/vg watch ID`.
- `/vg mute` and `/vg preview` take on or off, as `/vg minimal` does, so `/vg mute off` never mutes.
- You can use your own buff icons. Put a picture per effect, named by its number like `33.png` for Haste, in a folder under `config/addons/vantage/icons/` and pick that set under **Icons**. **Open icons folder**, beside **Reload icons**, opens that folder for you. Vantage reads folders, not zip files, and a line under **Icons** says when a zip there needs extracting, pictures need a folder of their own, or one folder holds several sets. A set extracted one folder too deep, as in `icons/Bright/Bright/`, works as it is.
- A new install's timer panels give a row its ending-soon color at 15 seconds left, up from 10, and the ready pulse starts green instead of gold. Settings you saved keep theirs, and **Import and add** counts the old ones as never changed.
- **Icons** and **Party buff icons** no longer have **Client**. **Original FFXI** shows the same pictures, sharp at any size on Party list, so a saved Client is now Original FFXI.

### The settings window

- The main page puts **What to show** in groups: **On you**, **Target and enemies**, **Party** and **Alerts**, with **While playing** under them.
- A display's name at the top opens a list of every display, and the button beside it goes back to where you came from.
- **Copy this tab to** gives other panels the same settings as this tab, and **Reset this tab** puts back just the tab you're on.
- A timer or recast panel's own **Show samples** shows samples on that panel only. The main page's **Show samples** and `/vg preview on` still show them on every display that is on.
- **Copy shown timers** and **Copy timer details** moved from **Help** to each timer and recast panel's **Show** tab.
- The main page has **Lit icons** and **Glow around them**, for the icons that light up on every display. Party list has its own glow and light color, where it used Overhead icons' before.
- Overhead icons' **Look** tab says its icons are the main page's **Icons**, with **Open Icons** to go there.
- **Mute alerts** sits at the top of the window, and **Unmute alerts** there or **Unmute** on the main page brings them back.
- **Snap while moving** has its tick in Arrange on screen's bar too. The rest of what **Grid mode** opened on the main page is now only in the bar's **Snapping** fold: **This display snaps** for the display you picked, **Show the grid**, **Grid**, what it lines up with and **Snap distance**. Ticking **Snap while moving** while no display snaps ticks them all.
- The ready pulse has an editor of its own. Its settings, its spot and its **When to show** were on the Recasts editor's tabs before. **Edit** on its main page row opens it, and so does **Edit the ready pulse** on Recasts' **Show** tab.
- **Follow the cursor while I am choosing a target** moved from Target timers' **Show** tab to **While playing** on the main page, since it was always one tick for every display.
- A timer or recast panel's countdown rows read **Countdown size**, **Countdown position** and **Countdown gap**, as on Party list.
- **Clear these conditions** is gone from **When to show**. **Reset this tab** there clears them in one Undo step.
- Timer durations says how many overrides you have, and **Override to edit** shows each one, instead of a list of them all above it.
- `/vg reset navigation` and `/vg reset preview` are gone. `/vg reset window` turns **Hold Shift to see through this window** back on, along with the window's place and size, and `/vg preview off` ends the samples. The command list names each command once, and older words like `/vg party live` and `/vg alliance` still work.
- **Chat line colors**, under **While playing**, sets the colors of Vantage's own lines in the chat log, with **Print a sample line** to see them.
- A line at the top of a display's editor says why it's hidden right now, with a button to bring it back when there is one.
- A setting a display keeps apart from the main page says `Has its own:`, with a button to use the main page's look again.
- On Profiles and sharing, one **What to export** list holds every kind of export and **A saved profile**, with **Copy** and **Save to a file** under it, so the current settings can go to a file too. A saved profile's row keeps **Load**, **Overwrite**, **Rename** and **Delete**.
- Most **Help** sections can copy a link to their part of the guide.
- At big text sizes and on small screens, a row that doesn't fit goes on the next line instead of running out of the window. Arrange on screen's bar stays on the screen and in front of the settings window.

### Fixes and speed

- In the offline benchmark, a frame makes far less garbage: about 0.5 KB in a party of six, down from 7.9, and 1.4 KB in a full alliance, down from 36.4.
- An alliance member KO'd out of your range loses the buffs Vantage was tracking on them once the game shows their HP at 0.
- A slept mob on Watched enemy timers keeps its Sleep while you target many others.
- Each Phantom Roll bust keeps its own time.
- A **Timer durations** override for a job ability now works for Shadowbind, Shield Bash, Weapon Bash, Angon, Tomahawk, Blade Bash and Feint.
- A timer or recast panel that fills down, with **Width** on **Fits the rows**, widens for the columns its rows need, up to **Widest**, instead of leaving rows out.
- Row text's **Up** and **Down** on a recast panel move a part on the first press.
- In Arrange on screen, a Shift drag or a change on the bar right after an arrow press is an Undo step of its own, and Undo and Redo are greyed when there's nothing to undo or redo.
- Undo takes a change, and names it, as soon as you make it. Before, it stayed greyed or named the step before for a moment.
- An export keeps a built-in font like Georgia Bold when your character's name is one of the font's words.
- **Import and add** judges each of Party list's groups on its own, so a group you never moved takes the imported spot.
- With **Replace the game's buff icons** on, the game draws its own icons while **When to show** hides both Self buffs and Self debuffs, so you're never left with none.
- With **Replace the game's buff icons** on, the game's + menu cursor follows the right buff when two have the same icon, like two Marches.
- A profile whose name ends in `#` can be picked.
- An import that changes nothing says so, and Undo stays on your last change.
- A recast that was counting when you zoned keeps its length and its ready pulse, even when the game sends the zone's ability list a few seconds late. One that was already running when you logged in or loaded Vantage keeps its ready pulse through a zone change too.
- A support job change in your Mog House takes off every ability recast but the job special's at once, as Phoenix clears them. Before, they stayed for 10 seconds.
- **On its row** plays a ready pulse only where a recast panel shows that recast. Before, a recast that **When to show** had hidden could still pulse where its row used to be.
- A Shift drag, or a change in the settings window, right after a change of another kind is an Undo step of its own, with its own name. Before, it could join the step before it.
- A Shift resize of the settings window that you let go while the pointer moves is one Undo step.
- Opening the settings window on a screen smaller than its saved size makes no Undo step, and Undo past it keeps Redo.
- `/vg hide party`, `/vg lock party`, `/vg undo 3`, `/vg reset party ui` and other commands given a word they don't take change nothing and show their usage line, instead of acting on everything or dropping the word.
- `/vg mute off`, `/vg set`, an Undo or Redo, a reset, a profile load or an import no longer tells you again about an effect that's still missing.
- **Import and add** of **Where everything is** judges each display's spot, size, fill and **Moves with** on its own, as it does for a whole profile. Before, a display whose width you changed kept the imported spot out.
- **Import from a file** shows a file's whole name when it has `##` in it.
- **Show only names containing** finds an effect by the name **Rename it** gave it, and still by the game's name. On a recast panel it looks only at the recast's names, so part of your own name no longer keeps every recast, and a number no longer keeps recasts that don't have it in their name.
- A party member's running ability estimates stay when the game hides their support job for a while.
- Another Corsair's Double-Up countdown ends when their Double-Up Chance goes, as after a Fold.
- Absorb-STR to Absorb-CHR that land show their Down on the mob for 90 seconds.
- A party member's Reraise counts down its hour, and your own counts as yours.
- Killer Instinct and Mantra show on every member they reach, and Mantra counts 3 minutes.
- A mob's or an alliance member's Blink shows its shadows, 2 from Blink or 4 from a blue mage's Zephyr Mantle, and goes with the last one.
- A monster's Depuration, Rapid Molt or Voidsong takes the debuffs that can be erased off it at once, and Benediction does the same for each mob it reaches. A Nightmare Bunny's Wild Carrot clears its debuff rows too.
- An alliance Corsair's roll past the two Phoenix keeps on a member, or past the one it keeps from a /COR, takes off the one that ends first.
- Another player's buff songs and bar-element spells count a range up to what a level 75 caster gives them, instead of the shortest time. So do their Requiem, Elegy, Threnody and Lullaby on a mob, doubled under Troubadour.
- Your own songs under Troubadour or Soul Voice drop the part of a second before doubling, as Phoenix does, so a Requiem Flute Requiem counts 402 seconds, not 403.
- A party member's Flee shows, counting 30 to 45 seconds.
- A party blue mage's Reactor Cool, Saline Coat, Plasma Charge, Warm-Up and Amplification count down.
- Enervation's Magic Def. Down is guessed on every mob it reaches, and Feral Howl's Terror is guessed too.
- A Diaga II no longer takes the place of a stronger Dia or Bio on the timers, and a repeated one no longer starts its countdown again.
- Physical Shield, Arrow Shield, Magic Shield, Damage Spikes, Shining Ruby and Rampart count as buffs. A mob's Physical Shield and Damage Spikes light up for removal, and its Arrow Shield and Magic Shield don't, since neither can come off. While a mob has a Magic Shield, none of its buffs light, since Phoenix turns every removal away. A Soulflayer's Immortal Shield blocks nothing, so it lights, and so do the mob's other buffs.
- A change Vantage couldn't save before you switched characters no longer goes over a newer save of that character from another game. A line says it wasn't saved.
- Vantage reads spell timers only for the spells Phoenix has, and any other you know, so reading your recasts takes about half the work.
- With many profiles saved, the Profiles buttons answer faster, because Vantage reads `profiles.json` again only when it changed.
- The effect data follows Phoenix at revision `9785020970`.
- An export made with 1.4.0 that holds one of the new settings can't be read by 1.3.0 or older. It asks you to update Vantage.

## 1.3.0

This update adds a way to keep Target timers away while you target yourself. The settings window's text also keeps the soft edges of the game's own letters now.

- **Hide while I target myself**, on the **Show** tab of Target timers, keeps the panel away while your target is you. Your own effects already show on Self buffs and Self debuffs, so they don't show twice. It starts off. **Show samples** and edit mode still show the panel, and a line under the tick says when it's hiding it.
- The settings window's text with the **Original FFXI** and **XI View** fonts keeps the soft grey pixels at the edges of the game's letters. Before, those pixels came out full white, which made the text look heavy and blocky next to the game's own. The letters' dark shadow is still left out, because the window draws its text in one color. Vantage makes these fonts again the first time this version loads.
- When something else in the game, such as another addon or plugin, has changed the game's menu mover, the line under **Replace the game's buff icons** says so. Before, it said the menu mover was missing. Vantage still leaves the game's buff icons alone then.
- An export made with 1.3.0 that holds the new Target timers tick, such as that display or a whole profile, can't be read by 1.2.1 or older. It asks you to update Vantage.

## 1.2.1

This update fixes how the settings window looks in the game. Its text is sharp on the Original FFXI and XI View fonts, and the game no longer shows through its bottom right corner.

- The settings window's text is sharp with the **Original FFXI** and **XI View** fonts. Before, each one pixel stroke came out as two grey columns side by side, which looked smeared. Vantage now asks Ashita to draw those fonts pixel for pixel.
- That text stays at a whole multiple of 16 pixels on screen when Ashita's own style has a font scale. Before, a scale put it between two sizes, which blurred it.
- On the Original FFXI skin, the game no longer shows through the settings window's bottom right corner. With Shift held, the frame now runs all the way around that corner.
- The settings window's pages have the window's own background behind them, and its buttons, sliders and lists have no outline, as in the README's pictures. Before, Ashita's own style put a grey sheet over the pages and an outline on every box. Tick boxes and radio buttons keep their thin outline. The edit mode bar's buttons have no outline either.
- `/vg report` now says whether each menu font is drawn sharp.

## 1.2.0

This update adds a way to replace the game's own buff icons with Vantage's, and it can show an automaton's HP as a number.

- **Replace the game's buff icons**, on the main page, hides the game's own buff and debuff icons, so Self buffs and Self debuffs are the only ones on screen. It starts off, and it needs both of those panels on.
- You still cancel a buff with the game's + menu. With the game's icons replaced, its cursor shows on Vantage's icon for the buff it's on, and Confirm cancels that buff. The game does the cancel, and Vantage still sends nothing. Clicking an icon does nothing.
- When the + menu is on an effect no self panel shows, because a filter hides it or the panel has no room for it, a small line by Self buffs shows its name, like `+ menu: Protect`.
- While the game's icons are replaced, Vantage changes how the game draws them, in the game's memory, and keeps the game's + menu off screen. It puts both back when you turn the setting off or unload Vantage. If a game update changes that part of the game, the game draws its own icons, and a line under the tick says why.
- **Replace the game's buff icons** is each character's own setting. Profiles, exports and shared layouts don't carry it, and an import can't turn it on.
- **Show automaton HP as a number**, on Pet's **Show** tab, shows your automaton's HP and max HP on its bar, like 812/1040, instead of a percent. It starts off. Only automatons get this, because the game sends every other pet's HP as a percent, and the number shows only while it agrees with the percent the game shows.
- `/vg report` now says whether the game's buff icons are replaced, and why not when they should be.
- An export made with 1.2.0 that holds the new Pet tick, such as the Pet display or a whole profile, can't be read by 1.1.1 or older. It asks you to update Vantage.

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

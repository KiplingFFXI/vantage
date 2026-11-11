# Install Vantage

Vantage is an Ashita v4 addon for FFXI on Phoenix. It shows buff, debuff and recast timers that you can move, size and style, and it can put buffs beside the game's party list. It doesn't hide or replace any of the game's windows unless you turn on **Replace the game's buff icons**, which hides the game's own buff icons. You need Ashita v4, version 4.3.2.1 or later. That's the build the Phoenix launcher installs.

## Install

The game can stay open while you do this.

1. Download `vantage-<version>-addon.zip` from the [release page](https://github.com/KiplingFFXI/vantage/releases).
2. Open the zip and copy its `addons/vantage` folder into the `addons` folder of the game folder Ashita runs from. You should end up with `addons/vantage/vantage.lua` there. If you're updating, move the old `addons/vantage` folder out of the game folder first so no old files get mixed in. The zip's other files are documents, and they don't go in the game folder.
3. Start the game if it isn't running, then load Vantage in game:

```text
/addon load vantage
```

   If Vantage is already loaded, run `/addon reload vantage` instead. Until you do, it keeps running the code it already loaded.

4. Run `/vg` to open the main page.

## Load it at startup

Enable vantage under **Manually installed** on the Phoenix launcher's Addons page. Or add `/addon load vantage` to the startup script you load addons from. With the Phoenix launcher, that script is `scripts/default.txt`. Put the line in the user block at the end of the file, and never inside a block marked as managed by the launcher. Use one method. Vantage never changes the launcher or a startup script.

## Settings

Each character gets its own `settings.json`, in its own folder under `config/addons/vantage`. Profiles, shared layouts, custom fonts, sounds and reports are kept there too. Copying in a new addon folder doesn't touch any of them.

## Check it

Run `/vg report` after loading. It writes `reports/latest.json` in the settings folder. The report says whether Vantage found the game clock for your own countdowns, the item data for item recasts, the game's party list rows and the chat window. It also says where the client art and fonts came from, or why one isn't drawn the way you picked. If Vantage can't find a part, that part turns off on its own and everything else keeps working. If your own buffs show no countdown, the report says why. A report can hold the names of characters and targets Vantage saw.

## Remove it

Run `/addon unload vantage`, then move `addons/vantage` out of the game folder. The settings folder stays where it is, so if you load Vantage again later, everything comes back.

The [guide](GUIDE.md) explains the panels, filters, skins, profiles, alerts and commands. The [changelog](../CHANGELOG.md) lists what each version brought. Vantage is by Kipling and uses the GNU GPL v3. See [LICENSE](../LICENSE).

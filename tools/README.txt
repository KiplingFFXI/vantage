Vantage release tools

  python tools/check_repository.py
  python tools/package.py
  python tools/export_catalog.py --duration-source <checkout> --duration-path <path> --check
  python tools/client_check.py <FFXiMain.dll or decoded client image>
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\install_addon.ps1 -Zip <archive> -Sha256 <hash> -Game <game folder>

package.py builds the release, dist/vantage-VERSION-addon.zip. The zip holds
addons/vantage/ (the addon) with LICENSE, README.md, CHANGELOG.md,
docs/GUIDE.md and docs/INSTALL.md, in a stable member order with fixed
timestamps. Use --out to choose another output folder. It refuses unexpected or
missing runtime files, modules vantage.lua loads that it would leave out,
linked files, and document links that leave the archive. It also refuses
private markers in plain bytes or UTF-16LE, in any letter case. Private markers
are the lines of private_markers.txt, temporary and scratch paths, and absolute
user paths. private_markers.txt lists your own Windows user name, email and
character names, one per line. .gitignore keeps it out of the repository, so a
build without it checks only the paths. package.py leaves out caches, tests,
tools, fonts made at run time and game data.

release_files.py holds the runtime file list package.py and check_repository.py
use. The archive bundles no game assets, settings or sound files. Local sounds
stay in each player's settings folder.

install_addon.ps1 installs an archive into a game folder (Windows PowerShell
5.1), with the game open or closed. If the game is open, run
/addon reload vantage in game afterwards. It refuses an archive whose SHA-256
isn't the one passed in. It notes the hash of every file under
config/addons/vantage (settings, profiles, shared layout and the rest). It
moves addons/vantage to a dated vantage-addon-backup-<UTC time> folder. That
folder goes in Documents, or in the folder -BackupParent names, outside the
game folder on the same drive. Then it copies the new addon and checks every
copied file's hash and that no settings file changed. On any failure, it puts
the backup back. Each folder moves whole or not at all, so an old addon with a
file held open stays where it is. It writes a JSON receipt beside the backup.
It never touches the launcher or a startup script.
tests/test_install_addon.py runs it against temporary folders only.

client_check.py checks that a game client has every pattern the addon looks
for, each exactly once. Those are the patterns for the chat windows and menu
scale (core/chat.lua), the event, interface and map focus flags
(core/client.lua), the game's party list and the Treasure Pool window
(core/native_party_ui.lua), the game clock (core/clock.lua), the game's name
point and cameras (core/name_anchor.lua), and the game's own buff icons and +
menu for Replace the game's buff icons (core/game_buffs.lua). For those it
checks where each routine starts and each routine whole. While the addon
loads ffxi.itemdata, they also include that library's patterns and those of
the ffxi libraries it loads. It reads the patterns from those files, prints
each one with where it was found, and exits 0 only when every one is found
once. It only reads the client. It decodes a DLL in memory with the research
decoder in tests/out/native-solo-research. That folder isn't in the
repository. Without it, pass a decoded client image. The libraries default to
the addons/libs folder of the Ashita install the client is in, or ASHITA_LIBS.
--libs picks another.

The catalog exporter reads pinned Git objects from the source repositories,
never dirty checkout files. --phoenix picks the Phoenix checkout. If you leave
it out, the exporter uses a sibling folder. --duration-source and
--duration-path name the checkout that holds the duration tables and their path
there. Those tables are the author's own committed work, with the same Phoenix
revision, and generation copies them into the addon. docs/SOURCE_MANIFEST.json
records the revisions and hashes. --check verifies that the output can be
reproduced, without editing it.
The exporter leaves out the effects an audit found can't exist on Phoenix. The
list is in the tool, and the audit is in docs/VALIDATION.md. It also lists the
spells and job abilities players can have there, for the Timer durations page.

"""The addon's runtime files and the checks package.py and check_repository.py run on them."""
import os
import posixpath
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / 'vantage'
CORE = 'alerts catalog chat client customization effect_filters effect_order identity observer profiles sound store tracker roster native_party_ui recasts memory patterns clock json performance camera name_anchor warmup overhead dispel durations recast_tints ready_pulse party_cooldowns rolls pet anchors conditions share starters game_buffs'.split()
UI = 'alert_panel appearance main_page shared_look client_assets client_fonts client_menu_fonts client_skin countdown_text defaults fields fonts hud icons item_icons action_icons recast_icons layout resize text_wrap render_cache text_metrics effect_blink effect_settings filter_settings settings_window settings_stub search_index controls theme party_defaults party_theme party_layout party_labels party_hud party_settings party_size_widget native_party_hud frame_policy setup_defaults client_bitmap numbers imgui_scopes overhead_defaults overhead_icons overhead_preview overhead_settings duration_settings cooldown_list cooldown_settings ready_pulse element_box roll_display roll_settings pet_display pet_settings elements snap edit_mode condition_settings panel_frame panel_rows status_panel recast_panel profiles_page'.split()
REQUIRED = {'vantage.lua', 'data/ability_effects.lua', 'data/actions.lua', 'data/catalog.lua', 'data/cleansable.lua', 'data/dispelable.lua', 'data/effects.lua', 'data/gear.lua', 'data/party_cooldowns.lua', 'data/rolls.lua', 'data/pets.lua', 'data/zones.lua'}
REQUIRED |= {'core/%s.lua' % name for name in CORE} | {'ui/%s.lua' % name for name in UI}
OPTIONAL = set()
DIRECTORIES = {'core', 'ui', 'data'}
# require('name'), require 'name' and pcall(require,'name').
REQUIRE = re.compile(r'''\brequire\s*(?:\(\s*|,\s*)?['"]([\w.]+)['"]''')
PRIVATE = re.compile(r'(?i)(?:[a-z]:[\\/]+Users[\\/]+|/(?:home|Users)/)[^\s\x00\'"<>]+|'
                     r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|'
                     r'\b(?:ghp_[a-zA-Z0-9]{30,}|github_pat_[a-zA-Z0-9_]{40,})\b')


def linked(path):
    return os.path.islink(path) or (hasattr(os.path, 'isjunction') and os.path.isjunction(path))


def addon_version(addon=ADDON):
    text = (Path(addon) / 'vantage.lua').read_text(encoding='ascii')
    match = re.search(r"^addon\.version\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)'", text, re.M)
    if not match:
        raise RuntimeError('vantage.lua must declare a version with three numeric parts.')
    return match.group(1)


def checked_bytes(path, name):
    if linked(path):
        raise RuntimeError('Linked release file: ' + name)
    data = Path(path).read_bytes().replace(b'\r\n', b'\n')
    text = data.decode('ascii')
    if PRIVATE.search(text):
        raise RuntimeError('Private path or credential marker in ' + name)
    return data


def required_modules(addon=ADDON):
    """Every addon file that vantage.lua's require graph reaches."""
    addon = Path(addon)
    reached, pending = set(), ['vantage.lua']
    while pending:
        name = pending.pop()
        if name in reached:
            continue
        reached.add(name)
        for module in REQUIRE.findall((addon / name).read_text(encoding='ascii')):
            path = module.replace('.', '/') + '.lua'
            # A name with no file here is an Ashita library.
            if (addon / path).is_file():
                pending.append(path)
    return reached


def addon_files(addon=ADDON):
    addon = Path(addon)
    if linked(addon):
        raise RuntimeError('The addon folder must not be linked.')
    left_out = required_modules(addon) - REQUIRED
    if left_out:
        raise RuntimeError('vantage.lua loads modules the release leaves out: ' + ', '.join(sorted(left_out)))
    found = set()
    for folder, subfolders, filenames in os.walk(addon):
        for name in subfolders:
            path = Path(folder) / name
            relative = path.relative_to(addon).as_posix()
            if linked(path) or relative not in DIRECTORIES:
                raise RuntimeError('Unexpected or linked runtime folder: ' + relative)
        for name in filenames:
            path = Path(folder) / name
            relative = path.relative_to(addon).as_posix()
            if linked(path) or relative not in REQUIRED | OPTIONAL:
                raise RuntimeError('Unexpected or linked runtime file: ' + relative)
            found.add(relative)
    missing = REQUIRED - found
    if missing:
        raise RuntimeError('Missing runtime files: ' + ', '.join(sorted(missing)))
    return [(addon / name, 'vantage/' + name) for name in sorted(found)]


def check_archive_links(contents):
    names = {name for name, _ in contents}
    for name, data in contents:
        if not name.endswith('.md'):
            continue
        for target in re.findall(r'\[[^\]\n]*\]\(([^)\n]+)\)', data.decode('ascii')):
            target = target.strip('<>')
            split = urlsplit(target)
            if split.scheme or split.netloc:
                continue
            destination = posixpath.normpath(posixpath.join(posixpath.dirname(name), unquote(split.path))) if split.path else name
            if destination not in names:
                raise RuntimeError('Broken archive document link in %s: %s' % (name, target))

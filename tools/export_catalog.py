"""Rebuild pinned status metadata and the previously audited duration tables.

Reads Git objects, never the mutable source checkouts. The duration tables are
the author's own committed work and record the same Phoenix revision. Updating either
pin requires a new source review; this tool will not follow a moving branch.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

PHOENIX = '071c401048bdb97bcbe12ad93651574fcf867407'
DURATION_REV = 'a0d1df0c6984a436291ef973fb29f434a8a4d67a'
ROOT = Path(__file__).resolve().parents[1]
# The effects that can't exist on Phoenix, by why, from an audit of all 668 judged at phoenix/live ed41f351f6 with its
# era settings (docs/VALIDATION.md). The pin above doesn't move this list: recheck it when Phoenix opens WotG content
# or changes those settings.
AUDITED_OUT = {
    # DNC, SCH, GEO or RUN only.
    'job_off': '23, 178-188, 228, 358-370, 375-402, 407, 410-416, 442-443, 448-452, 468-470, 472, 507-508, 513, '
               '517-519, 522-571, 580, 582, 584, 588, 612, 796, 798',
    # Nothing in the code applies them.
    'no_apply_site': '0, 17-18, 53, 158-161, 193, 204, 208, 211-213, 232-234, 244-248, 257, 264, 267, 284, 291-292, '
                     '458-459, 473, 475-476, 481, 486-489, 506, 509-511, 515-516, 572-573, 578, 585, 587, 589-597, '
                     '602, 604-610, 613-618, 620, 622, 624, 627-635',
    # They need a level past 75.
    'level_cap': '222-223, 227, 229-231, 286, 288-290, 298, 330-338, 433, 435-441, 453-457, 460-467, 471, 477, '
                 '479-480, 482-483, 485, 490-494, 496-505, 576, 586, 598, 601',
    # The Abyssea, Campaign, Monstrosity and Trust systems.
    'system_off': '268, 285, 287, 474, 575, 626, 768-788, 790, 807-813',
    # Content Phoenix has switched off.
    'content_tag_off': '275, 328-329, 339, 371, 403, 405-406, 408-409, 417-431, 495, 577, 583, 599-600, 611, 619, '
                       '621, 625',
    # Only in zones with no way in.
    'closed_zone_only': '19-21, 177, 189, 293-297, 432, 434, 447, 512',
    # Items nothing gives, the empty slot marker and a GM-only effect.
    'item_no_source': '270-272',
    'sentinel': '255',
    'gm_only': '603',
    # Only reachable through a shop.
    'shop_only': '277-282, 404, 581',
    # The client has no name or icon for them, so nothing can show them: applied with icon 0, only ever on a mob, or
    # part of a quest from after this era.
    'never_shown': '791-795, 797, 799-806',
}
# What players can have: spells and abilities of these content tags (NULL is the base game), on a job up to 18 at level
# 75 or under. Phoenix's era SQL moves nothing across 75 (Reraise I to III, Banishga and Sekkanoki only), and the two
# SQL files give the same lists at the pin and at phoenix/live ed41f351f6. Group 8 is the Trust spells, which every job
# has at level 1 and nobody can cast on Phoenix.
OPEN_CONTENT = {'NULL', 'ROTZ', 'COP', 'TOAU'}
TRUST_GROUP = '8'


def blob(repo, ref, path):
    return subprocess.check_output(['git', '-C', str(repo), 'show', ref + ':' + path])


def lua(value):
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return "'" + value.replace('\\', '\\\\').replace("'", "\\'") + "'"
    if isinstance(value, list):
        return '{ ' + ', '.join(lua(v) for v in value) + ' }'
    return '{ ' + ', '.join(f'[{lua(k)}] = {lua(v)}' for k, v in value.items()) + ' }'


def id_list(text):
    ids = set()
    for part in text.split(', '):
        first, _, last = part.partition('-')
        ids.update(range(int(first), int(last or first) + 1))
    return ids


def phoenix_statuses(rows):
    out = set().union(*(id_list(text) for text in AUDITED_OUT.values()))
    result = {ident: row for ident, row in rows.items() if ident not in out}
    if len(result) != 271:
        raise RuntimeError('Audited status catalog changed unexpectedly.')
    return result


def player_actions(spell_text, ability_text):
    spells, abilities = [], []
    # jobs is hex bytes, byte N the level of job N and 0 for none.
    for row in re.findall(r'^INSERT INTO `spell_list` VALUES \((.*)\);', spell_text, re.M):
        fields = row.split(',')
        if (fields[3] != TRUST_GROUP and fields[24].strip("'") in OPEN_CONTENT
                and any(0 < level <= 75 for level in bytes.fromhex(fields[2][2:])[:18])):
            spells.append(int(fields[0]))
    for row in re.findall(r'^INSERT INTO `abilities` VALUES \((.*)\);', ability_text, re.M):
        fields = row.split(',')
        if fields[20].strip("'") in OPEN_CONTENT and 1 <= int(fields[2]) <= 18 and int(fields[3]) <= 75:
            abilities.append(int(fields[0]))
    if (len(spells), len(abilities)) != (436, 355):
        raise RuntimeError('Pinned spell and ability lists changed unexpectedly.')
    return sorted(spells), sorted(abilities)


def statuses(text):
    result = {}
    for match in re.finditer(r'^  ([a-z][a-z0-9_]*):\n(.*?)(?=^  [a-z][a-z0-9_]*:|\Z)', text, re.M | re.S):
        key, body = match.groups()
        ident = re.search(r'^    id:\s*(\d+)', body, re.M)
        if not ident:
            continue
        ident = int(ident[1])
        flags = re.findall(r'^      - (\w+)', body, re.M)
        harmful = (1 <= ident <= 31 or 128 <= ident <= 135 or 146 <= ident <= 156
                   or ident in {143, 157, 159, 167, 168, 174, 175, 186, 192, 193, 194, 217, 223, 264, 299, 309, 404, 463, 464, 465, 466, 473, 540, 565, 566, 567, 597, 630, 631, 793})
        harmful = harmful or 'erasable' in flags or 'waltzable' in flags
        harmful = harmful or any(s in key for s in ('_down', '_daze', 'encumbrance', 'obliviscence', 'impairment', 'omerta', 'debilitation'))
        helpful = ('dispelable' in flags or 'song' in flags or 'roll' in flags
                   or 32 <= ident <= 126 or 161 <= ident <= 166 or 169 <= ident <= 172
                   or 178 <= ident <= 185 or 227 <= ident <= 243 or 300 <= ident <= 308
                   or 340 <= ident <= 377 or 379 <= ident <= 385 or 401 <= ident <= 403
                   or 405 <= ident <= 417 or 419 <= ident <= 423 or 461 <= ident <= 473
                   or 424 <= ident <= 447 or 453 <= ident <= 460
                   or ident in {176, 187, 188, 249, 251, 253, 254, 256, 268, 270, 271, 272, 273, 275, 283, 287, 289, 290, 469})
        kind = 'debuff' if harmful else 'buff' if helpful else 'other'
        group = ('Songs' if 'song' in flags or 192 <= ident <= 222 else
                 'Rolls' if 'roll' in flags or ident in {308, 309} else
                 'Food' if ident == 251 else 'Travel' if ident in {69, 70, 71, 253, 254, 256} else
                 'Protection' if ident in {36, 37, 39, 40, 41, 66, 116} else
                 'Recovery' if ident in {42, 43, 249} else 'Debuffs' if harmful else
                 'Buffs' if helpful else 'Other')
        result[ident] = dict(id=ident, name=key.replace('_', ' ').title(), kind=kind, group=group,
                             priority=100 if ident == 15 else 80 if ident in {2, 6, 7, 10, 14, 16, 19, 28, 193} else 0)
    if len(result) != 668:
        raise RuntimeError('Pinned status catalog changed unexpectedly.')
    return result


def cut(text, pattern, expected, replacement=''):
    text, count = re.subn(pattern, replacement, text, flags=re.M)
    if count != expected:
        raise RuntimeError('Duration artifact changed: ' + pattern)
    return text


def what_is_read(effects):
    # The addon reads an effect's row only for what it drops, so a row with nothing to drop is the same as no row.
    effects = cut(effects, r'^    -- What an effect removes, and its usual duration\.$', 1, '    -- What an effect removes.')
    effects = cut(effects, r', usual = \d+(?= \},)', 161)
    effects = cut(effects, r'^ +usual = \d+,\n', 7)
    effects = cut(effects, r'^ +\[\d+\] = \{ drops = \{  \} \},  -- \w+\n', 542)
    # The client names no effect at 640 or over and core/tracker.lua gives one no row, so a move that gives one shows nothing.
    effects = cut(effects, r'^ +\[\d+\] = \{ effect = (?:6[4-9]\d|[7-9]\d\d),.*\n', 4)
    effects = cut(effects, r"^    (?:built  |content) = '.*',\n", 2)
    effects = cut(effects, r'^    -- The most common item duration.*\n    proc_usual = \{[^}]*\},\n', 1)
    return cut(effects, r'^    -- Unique icon IDs\..*\n    pictured = \{[^}]*\},\n', 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phoenix', type=Path, default=ROOT.parent / 'Phoenix')
    parser.add_argument('--duration-source', type=Path, required=True)
    parser.add_argument('--duration-path', required=True)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    manifest = {'phoenix_revision': PHOENIX, 'duration_revision': DURATION_REV,
                'assumptions': 'RESTRICT_CONTENT enabled; ROTZ/COP/TOAU enabled; later expansions disabled', 'sources': {}}

    def read(repo, revision, path, listed=None):
        raw = blob(repo, revision, path)
        manifest['sources'][listed or path] = {'revision': revision, 'sha256': hashlib.sha256(raw).hexdigest()}
        return raw.decode('utf-8-sig').replace('\r\n', '\n')

    status_text = read(args.phoenix, PHOENIX, 'data/status_effects.yaml')
    duration = read(args.duration_source, DURATION_REV, args.duration_path, 'duration tables')
    if 'phoenix/live ' + PHOENIX[:10] not in duration:
        raise RuntimeError('Duration artifact does not match the reviewed Phoenix revision.')
    # The source's header names the tool that built it; here it names this one.
    header = '-- Built by tools\\export_data.py from phoenix/live ' + PHOENIX[:10] + '.\n'
    if duration.count(header) != 1:
        raise RuntimeError('Duration artifact header changed.')
    effects = what_is_read(duration.replace(header, '-- Built from phoenix/live ' + PHOENIX[:10] + ' by tools/export_catalog.py.\n'))
    for path in ['modules/init.txt', 'src/map/packets/s2c/0x063_miscdata_status_icons.cpp',
                 'src/map/packets/s2c/0x076_group_effects.cpp', 'src/map/status_effect_container.cpp',
                 'src/map/packets/s2c/0x028_battle2.cpp', 'src/map/packets/s2c/0x029_battle_message.cpp',
                 'src/map/packets/s2c/0x08c_merit.h', 'src/map/enums/msg_basic.h', 'src/map/enums/msg_std.h',
                 'scripts/globals/spells/enhancing_spell.lua', 'scripts/globals/spells/enhancing_song.lua',
                 'scripts/globals/spells/enfeebling_spell.lua', 'scripts/globals/spells/enfeebling_song.lua',
                 'scripts/globals/job_utils/corsair.lua', 'modules/era/lua/globals/job_utils/corsair.lua',
                 'modules/phoenix/lua/globals/spells/enhancing_spell.lua',
                 'modules/phoenix/lua/globals/spells/enfeebling_spell.lua',
                 'modules/phoenix/lua/globals/spells/enhancing_ninjutsu.lua']:
        read(args.phoenix, PHOENIX, path)
    ability_text = read(args.phoenix, PHOENIX, 'scripts/enum/job_ability.lua')
    abilities = {k: int(v) for k, v in re.findall(r'^\s*(\w+)\s*=\s*(\d+)', ability_text, re.M)}
    effect_ids = {m[1]: int(re.search(r'^    id:\s*(\d+)', m[2], re.M)[1])
                  for m in re.finditer(r'^  (\w+):\n(.*?)(?=^  \w+:|\Z)', status_text, re.M | re.S)
                  if re.search(r'^    id:\s*(\d+)', m[2], re.M)}
    corsair = blob(args.phoenix, PHOENIX, 'scripts/globals/job_utils/corsair.lua').decode()
    result = phoenix_statuses(statuses(status_text))
    rolls = {abilities[name]: effect_ids[effect.lower()]
             for name, effect in re.findall(r'\[xi.jobAbility.(\w+_ROLL)\]\s*=\s*\{\s*effect\s*=\s*xi.effect.(\w+)', corsair)
             if name in abilities and effect.lower() in effect_ids and effect_ids[effect.lower()] in result}
    # Only the era rolls exist on Phoenix.
    if len(rolls) != 18:
        raise RuntimeError('Pinned roll list changed unexpectedly.')
    supplemental = {'rolls': rolls}
    supplemental['spells'], supplemental['abilities'] = player_actions(read(args.phoenix, PHOENIX, 'sql/spell_list.sql'),
                                                                       read(args.phoenix, PHOENIX, 'sql/abilities.sql'))
    magic = read(args.phoenix, PHOENIX, 'scripts/enum/magic.lua').split('xi.magic.spell =', 1)[1]
    spell_ids = {k: int(v) for k, v in re.findall(r'^\s*(\w+)\s*=\s*(\d+)', magic, re.M)}
    enhancing = blob(args.phoenix, PHOENIX, 'scripts/globals/spells/enhancing_spell.lua').decode()
    supplemental['enhancing'] = {}
    for name, level, composure in re.findall(r'^\s*\[xi.magic.spell.(\w+)\s*\]\s*=\s*\{\s*\d+,\s*xi.effect.\w+,\s*(\d+),\s*\d+,\s*\d+,\s*(true|false)', enhancing, re.M):
        supplemental['enhancing'][spell_ids[name]] = {'level': int(level), 'composure': composure == 'true'}
    songs = blob(args.phoenix, PHOENIX, 'scripts/globals/spells/enhancing_song.lua').decode()
    supplemental['songs'] = {}
    for name, body in re.findall(r'^\s*\[xi.magic.spell.(\w+)\s*\]\s*=\s*\{(.*?)\}', songs, re.M):
        values = [v.strip() for v in body.split(',')]
        supplemental['songs'][spell_ids[name]] = {'modifier': values[3].removeprefix('xi.mod.').lower(), 'soul_voice_duration': values[11] == 'false'}
    merits = read(args.phoenix, PHOENIX, 'data/merits.yaml')
    era_merits = read(args.phoenix, PHOENIX, 'modules/era/data/merits.yaml')
    group2_cap = len(re.search(r'job_group_2:\s*\[([^\]]+)\]', era_merits)[1].split(','))
    supplemental['merits'] = {}
    for name in ('winning_streak', 'bust_duration'):
        match = re.search(r'\b' + name + r':\s*\n\s*id:\s*(0x[\da-fA-F]+)\s*\n\s*value:\s*(\d+)', merits)
        if not match:
            raise RuntimeError('Missing merit rule: ' + name)
        supplemental['merits'][name] = {'id': int(match[1], 16), 'value': int(match[2]), 'most': group2_cap if name == 'winning_streak' else 5}
    mod_text = read(args.phoenix, PHOENIX, 'data/enums/mod.yaml')
    mod_ids = {name: int(value) for name, value in re.findall(r'^  (\w+):\s*(\d+)', mod_text, re.M)}
    wanted = {name for name in mod_ids if name in {'enh_magic_duration', 'enf_mag_duration', 'song_duration_bonus',
              'phantom_duration', 'regen_duration', 'invisible_duration', 'sneak_duration', 'all_songs_effect'}
              or name in {s + '_effect' for s in ('ballad', 'carol', 'etude', 'madrigal', 'mambo', 'march', 'minne', 'minuet', 'paeon', 'prelude')}}
    wanted.update(row['modifier'] for row in supplemental['songs'].values() if row['modifier'] in mod_ids)
    names = {mod_ids[name]: name for name in wanted}
    item_mods = read(args.phoenix, PHOENIX, 'sql/item_mods.sql')
    gear = {}
    for item, mod, value in re.findall(r'INSERT INTO `item_mods` VALUES \((\d+),(\d+),(-?\d+)\)', item_mods):
        if int(mod) in names:
            gear.setdefault(int(item), {})[names[int(mod)]] = int(value)
    outputs = {
        ROOT / 'vantage/data/catalog.lua': '-- Generated by tools/export_catalog.py.\nreturn {\n' +
            ''.join(f'    [{k}] = {lua(v)},\n' for k, v in sorted(result.items())) + '}\n',
        ROOT / 'vantage/data/effects.lua': effects,
        ROOT / 'vantage/data/actions.lua': '-- Generated by tools/export_catalog.py.\nreturn ' + lua(supplemental) + '\n',
        ROOT / 'vantage/data/gear.lua': '-- Base item duration modifiers. Augments and script-only bonuses remain unknown.\nreturn ' + lua(gear) + '\n',
        ROOT / 'docs/SOURCE_MANIFEST.json': json.dumps(manifest, indent=2, sort_keys=True) + '\n',
    }
    for path, text in outputs.items():
        if args.check:
            if not path.exists() or path.read_text(encoding='utf-8') != text:
                raise RuntimeError('Generated file differs: ' + str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8', newline='\n')
    print(f'{len(result)} status definitions; {len(rolls)} roll mappings; pinned source manifest verified.')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""
Writes the website's command list (celmod-website/includes/commands.php) from the plugins' own
RegConsoleCmd/RegAdminCmd lines, so the commands page always matches the server.

    python3 tools/export_commands.py ../celmod-website/includes/commands.php

Commands registered to the same function with the same description are shown together as aliases
(!colors / !colorlist). Each command goes in the category from CATEGORY below; anything new and
unlisted lands in "Other" until it's added here. USAGE adds the arguments shown after a command.
"""
import glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTING = os.path.join(HERE, '..', 'addons', 'sourcemod', 'scripting')

CATEGORIES = [
    ('building', 'Building'),
    ('cels', 'Cels and Bits'),
    ('land', 'Land'),
    ('money', 'Money and Shop'),
    ('collecting', 'Emblems, Hats and Collecting'),
    ('player', 'Player and Chat'),
    ('help', 'Help and Info'),
    ('other', 'Other'),
    ('admin', 'Admin'),
]

CATEGORY = {}
for cat, names in {
    'building': 'spawn p s save load saves builds clear copy paste +copy +move freeze freezeit freezeall unfreeze unfreezeit unfreezeall del delete remove delall deleteall removeall undo '
                'r rotate flip roll turn stand straight straighten smove pmove drop moveto weld release stack stackinfo axis mark marker '
                'replace model skin color paint palette fadecolor alpha amt renderfx solid god lock unlock perm unperm owner',
    'cels': 'text door light ladder internet seturl turret fire effect emitter message music celmusic sound teleport spawnpoint button link setpass pass wep ammo ammocrate charger',
    'land': 'land coop landcoop dm deathmatch landdeathmatch gravity landgravity shop landshop landskin landcolor addteam delteam team '
            'fee landban landunban landkick kick landslay weps nofly landnoclip extinguish buildmessage block unblock hide show zones',
    'money': 'bank balance cl buy sell give trade catalog shopitems seasons arsenal buymodel playermodels playermodel',
    'collecting': 'emblems hats inventory weapons emblem hat weapon thirdperson firstperson speed presents wrap gift guess bid spawnpad spawnpads npckills tacticlvl tacticxp',
    'player': 'fly noclip nokill stuck switch hudcolor feed pmute punmute timeleft',
    'help': 'news reportbug dispute motd rules cmds commands commandlist colors colorlist props proplist effects effectlist updates updatelist',
}.items():
    for n in names.split():
        CATEGORY[n] = cat

USAGE = {
    'spawn': '<prop name>', 'land': '(again to finish, #clear to remove)', 'save': '<build name>', 'load': '<build name>', 'clear': '<build name>',
    'r': '<degrees>', 'flip': '<degrees>', 'roll': '<degrees>', 'turn': '<degrees>', 'rotate': '<flip> <r> <roll>',
    'stack': '<x> <y> <z> [copies]', 'smove': '<x> <y> <z>', 'replace': '<prop name>', 'skin': '<number>',
    'color': '<color> (#all for everything you own)', 'fadecolor': '<color 1> <color 2>', 'palette': '<red> <green> <blue>',
    'alpha': '<0-255>', 'renderfx': '<effect>', 'door': '<door skin>', 'light': '[distance]', 'ladder': '<1 or 2>',
    'seturl': '<url>', 'text': '<words> (^ in front for small text)', 'effect': '<effect name>', 'message': '<text>', 'music': '<song>', 'sound': '<sound name>',
    'setpass': '<passcode or off>', 'pass': '<passcode>', 'wep': '<weapon>', 'ammo': '<ammo type>', 'ammocrate': '<smg, ar2, rpg, grenade or cball>',
    'charger': '<health or suit>', 'gravity': '<amount>', 'landskin': '<1-26 or off>', 'landcolor': '<color>',
    'addteam': '<player>', 'delteam': '<player>', 'fee': '<amount> | pay', 'npckills': '[type] [player]', 'hudcolor': '<colour or r g b | random>', 'turret': '', 'landban': '<player>', 'landunban': '<player>', 'landkick': '<player>', 'kick': '<player>',
    'landslay': '<player or #all>', 'buildmessage': '<message or off>', 'block': '<player>', 'unblock': '<player>', 'hide': '<player>', 'show': '<player>',
    'cl': '[amount]', 'buy': '[item]', 'bank': '[number or add]', 'sell': '<price>', 'give': '<player>', 'trade': '<player> <price>', 'buymodel': '<model>', 'playermodel': '<model or off>',
    'emblem': '<emblem or off>', 'hat': '<hat or off>', 'weapon': '<celwep or off>', 'wrap': '<item> <player>', 'guess': '<1, 2 or 3>', 'bid': '<amount>',
    'spawnpad': '[enemy]', 'pungag': '<player> [minutes] [reason]', 'punungag': '<player>', 'punkick': '<player> [reason]', 'punban': '<player> <minutes, 0 = forever> [reason]', 'shell': '[big]', 'pmute': '<player>', 'punmute': '<player>', 'reportbug': '<what happened>',
    'setbalance': '<player> <amount>', 'givemoney': '<player> <amount>', 'takemoney': '<player> <amount>', 'giveitem': '<player> <kind> <item>',
    'givemodel': '<player> <model>', 'takemodel': '<player> <model>', 'auction': '<kind> <item> <starting bid> <minutes>',
    'emblemdrop': '[boxes]', 'dungeonspawner': '<enemy> [max alive] [seconds]', 'deldungeonspawner': '[number or all]',
    'forceseason': '<season> <on, off or auto>', 'blacklist': '<prop name>', 'setowner': '<player>', 'autobuild': '<x> <y> <z>',
}

def main(out_path):
    found = {}  # (function, description, admin) -> [names]
    order = []
    for path in sorted(glob.glob(os.path.join(SCRIPTING, 'celmod*.sp'))):
        if 'template' in path:
            continue
        text = open(path, encoding='utf-8', errors='replace').read()
        for m in re.finditer(r'Reg(Console|Admin)Cmd\("([v+][^"]*)",\s*(\w+),\s*(?:ADMFLAG_\w+(?:\s*\|\s*ADMFLAG_\w+)*\s*,\s*)?"((?:[^"\\]|\\.)*)"', text):
            kind, name, func, desc = m.groups()
            name = name[2:] if name.startswith('v_') else name
            desc = re.sub(r'^\|CelMod\|\s*', '', desc)
            key = (func, desc, kind == 'Admin')
            if key not in found:
                found[key] = []
                order.append(key)
            found[key].append(name)

    groups = {cat: [] for cat, _ in CATEGORIES}
    for key in order:
        func, desc, admin = key
        names = found[key]
        # A name with usage text leads (!spawn before !p/!s), then the shortest (!del before !delete/!remove).
        names.sort(key=lambda n: (n not in USAGE, CATEGORY.get(n) is None, len(n), n))
        lead = names[0]
        cat = 'admin' if admin else CATEGORY.get(lead, 'other')
        groups[cat].append((names, USAGE.get(lead, ''), desc))

    def php(s):
        return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"

    lines = ['<?php', '/*', ' * The commands page (cmds.php). Generated by tools/export_commands.py in the celmod repo from the',
             ' * plugins themselves; run it again after adding or changing commands instead of editing this by hand.', ' */',
             'return [']
    total = 0
    for cat, title in CATEGORIES:
        items = groups[cat]
        if not items:
            continue
        items.sort(key=lambda i: i[0][0].lstrip('+'))
        lines.append(f"\t{php(title)} => [")
        for names, usage, desc in items:
            total += 1
            lines.append(f"\t\t[[{', '.join(php(n) for n in names)}], {php(usage)}, {php(desc)}],")
        lines.append('\t],')
    lines.append('];')
    open(out_path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
    print(f'{total} commands written to {out_path}')
    if groups['other']:
        print('Not in a category yet:', ', '.join(i[0][0] for i in groups['other']))

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', '..', 'celmod-website', 'includes', 'commands.php'))

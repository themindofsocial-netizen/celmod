#!/usr/bin/env python3
"""Writes the website's Colors and Effects lists from the server's own files, so they never go out of date.

    python3 tools/export_reference.py ../celmod-website

colors.php   from addons/sourcemod/data/celmod/colors.txt (what !color knows), plus rainbow and error.
effects.php  from the effect names celmod-effects.sp accepts (Native_GetEffectTypeFromName), with a line about each.
"""
import html
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, 'addons', 'sourcemod', 'data', 'celmod')
SCRIPTS = os.path.join(ROOT, 'addons', 'sourcemod', 'scripting')

# What each effect is (the entity celmod-effects makes for it).
EFFECT_INFO = {
    'core': ('Citadel energy core', 'A crackling ball of Combine energy.'),
    'explosion': ('Explosion', 'Blows up when used.'),
    'fire': ('Fire', 'A fire that burns until you put it out.'),
    'shake': ('Earthquake', 'Shakes the screen of everyone nearby.'),
    'smokestack': ('Smoke stack', 'A column of rising smoke.'),
    'spotlight': ('Spotlight', 'A beam of light pointing the way the cel faces.'),
    'steam': ('Steam', 'A jet of steam.'),
}


def page(title, body, script=''):
    return ("<?php require __DIR__ . '/includes/bootstrap.php'; cm_page_start('|CelMod| - %s'); ?>\n"
            "<!-- Written by tools/export_reference.py (celmod repo) from the server's files: edit those, not this. -->\n"
            '<h2><span class="celColor">|CelMod| %s</span><br>\n</h2>\n%s\n<?php cm_page_end(%s); ?>\n') % (title, title, body, script or '')


def colors(site):
    text = re.sub(r'//[^\n]*', '', open(os.path.join(DATA, 'colors.txt'), encoding='utf-8', errors='replace').read())
    pairs = re.findall(r'"([^"]+)"\s+"(\d+)\|(\d+)\|(\d+)"', text)

    # The same color under two names (gray/grey) is shown once, with both names.
    seen = {}
    for name, r, g, b in pairs:
        seen.setdefault((int(r), int(g), int(b)), []).append(name)

    cards = []
    for (r, g, b), names in seen.items():
        main = names[0]
        also = (' <span class="muted">or %s</span>' % ', '.join(html.escape(n) for n in names[1:])) if len(names) > 1 else ''
        cards.append('<button type="button" class="swatch-card" data-copy="!color %s" title="Copy !color %s">'
                     '<span class="chip" style="background:rgb(%d,%d,%d)"></span><span class="txt"><b>%s</b>%s<small>%d %d %d</small></span></button>'
                     % (html.escape(main), html.escape(main), r, g, b, html.escape(main), also, r, g, b))
    cards.append('<button type="button" class="swatch-card" data-copy="!color rainbow" title="Copy !color rainbow">'
                  '<span class="chip chip-rainbow"></span><span class="txt"><b>rainbow</b><small>cycles through every color</small></span></button>')
    cards.append('<button type="button" class="swatch-card" data-copy="!color error" title="Copy !color error">'
                  '<span class="chip chip-error"></span><span class="txt"><b>error</b><small>fades red-orange and black</small></span></button>')

    body = ('<p>Look at your prop and type <span class="h">!color &lt;color&gt;</span>. Click a color to copy its command.<br>\n'
            '<span class="h">!color &lt;color&gt; #all</span> colors everything you own, and <span class="h">!color &lt;color&gt; #hud</span> '
            'colors your HUD text. For any color at all, <span class="h">!palette &lt;red&gt; &lt;green&gt; &lt;blue&gt;</span>; to fade '
            'between two, <span class="h">!fadecolor &lt;color 1&gt; &lt;color 2&gt;</span>.</p>\n'
            '<div class="swatch-grid">\n%s\n</div>\n'
            '<div class="btngrid"><a href="renderfx">Render Effects</a> <a href="effects">Effects</a> <a href="lists">All Lists</a></div>'
            ) % '\n'.join(cards)
    open(os.path.join(site, 'colors.php'), 'w').write(page('Colors', body))
    return len(cards)


def effects(site):
    source = open(os.path.join(SCRIPTS, 'celmod-effects.sp'), encoding='utf-8').read()
    native = source[source.index('public int Native_GetEffectTypeFromName'):]
    native = native[:native.index('\n}\n')]
    native = re.sub(r'/\*.*?\*/', '', native, flags=re.S)  # effects that are switched off in the plugin
    names = re.findall(r'StrContains\("([a-z]+)"', native)

    rows = []
    for name in names:
        title, what = EFFECT_INFO.get(name, (name.capitalize(), ''))
        rows.append('<tr><td><b data-copy="!effect %s" title="Copy !effect %s">%s</b></td><td>%s</td><td>%s</td></tr>'
                    % (name, name, name, html.escape(title), html.escape(what)))

    body = ('<p>Aim where it should go and type <span class="h">!effect &lt;effect&gt;</span>: it spawns an effect cel. Press '
            '<b>E</b> on it (or <span class="h">!link</span> a button to it) to turn it on and off, and '
            '<span class="h">!color</span> it to change its color. Click an effect to copy its command.</p>\n'
            '<div class="table-scroll"><table class="cmtable">\n<tr><th>Type</th><th>Effect</th><th>What it does</th></tr>\n%s\n</table></div>\n'
            '<div class="btngrid"><a href="renderfx">Render Effects</a> <a href="colors">Colors</a> <a href="lists">All Lists</a></div>'
            ) % '\n'.join(rows)
    open(os.path.join(site, 'effects.php'), 'w').write(page('Effects', body))
    return len(names)


def main():
    site = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, '..', 'celmod-website')
    print('%d colors and %d effects written to %s' % (colors(site), effects(site), site))


if __name__ == '__main__':
    main()

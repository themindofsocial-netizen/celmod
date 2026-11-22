#!/usr/bin/env python3
"""Writes the website's prop list from the server's own data files, so it never goes out of date.

    python3 tools/export_props.py ../celmod-website/props

Reads addons/sourcemod/data/celmod/spawns.txt (what !spawn knows), blacklist.txt (aliases that can't be
spawned) and shop.txt (the "Props" section: props you buy, one copy per purchase). Writes props/a.php ..
props/z.php, props/other.php (aliases that start with a digit), props/index.php, props/shop.php and
props/props.json (every name, for the search box on the index; props/search.js reads it).
props/dis.php (the discontinued props history) is left alone.
"""
import html
import os
import re
import string
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, 'addons', 'sourcemod', 'data', 'celmod')


def keyvalues(path):
    """A small KeyValues reader: nested dicts of strings (later duplicate keys win)."""
    text = open(path, encoding='utf-8', errors='replace').read()
    text = re.sub(r'//[^\n]*', '', text)
    tokens = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', text)
    stack = [{}]
    key = None
    for quoted, brace in tokens:
        if brace == '{':
            child = {}
            stack[-1][key.lower() if key else ''] = child
            stack.append(child)
            key = None
        elif brace == '}':
            stack.pop()
            key = None
        elif key is None:
            key = quoted
        else:
            stack[-1][key.lower()] = quoted
            key = None
    return stack[0]


def first_section(kv):
    return next(iter(kv.values())) if kv else {}


def bucket(alias):
    first = alias[0].lower()
    return first if first in string.ascii_lowercase else 'other'


def letter_grid(present, current=None, prefix=''):
    out = ['<div class="btngrid letters">']
    for b in list(string.ascii_lowercase) + ['other']:
        label = '0-9' if b == 'other' else b.upper()
        if b not in present:
            out.append('<b title="No props yet">%s</b>' % label)
        elif b == current:
            out.append('<a href="%s%s" class="active" style="color:#71E100">%s</a>' % (prefix, b, label))
        else:
            out.append('<a href="%s%s">%s</a>' % (prefix, b, label))
    out.append('</div>')
    return '\n'.join(out)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, '..', 'celmod-website', 'props')

    spawns = first_section(keyvalues(os.path.join(DATA, 'spawns.txt')))
    # spawns.txt holds one section of "alias" "classname|model" (some files group them; flatten either way).
    flat = {}
    for k, v in spawns.items():
        if isinstance(v, dict):
            flat.update({a: s for a, s in v.items() if isinstance(s, str)})
        else:
            flat[k] = v

    blacklist = first_section(keyvalues(os.path.join(DATA, 'blacklist.txt'))).get('blacklist', {})
    shop = first_section(keyvalues(os.path.join(DATA, 'shop.txt')))
    shop_props = shop.get('props', {})

    hidden = set(a.lower() for a in blacklist) | set(a.lower() for a in shop_props)
    props = sorted(a for a in flat if a.lower() not in hidden and '|' in flat[a])

    by_bucket = {}
    for a in props:
        by_bucket.setdefault(bucket(a), []).append(a)

    for b, aliases in by_bucket.items():
        title = '0-9' if b == 'other' else b.upper()
        lines = []
        for a in aliases:
            cls = flat[a].split('|', 1)[0]
            note = ' <span class="muted">(NPC: shoot it to change its pose, E to pause)</span>' if cls == 'cycler' else ''
            lines.append('  <span data-copy="!%s" title="Click to copy !%s">%s</span>%s<br>' % (html.escape(a), html.escape(a), html.escape(a), note))
        page = ("<?php require __DIR__ . '/../includes/bootstrap.php'; cm_page_start('|CelMod| - Prop List - %s'); ?>\n"
                '<!-- Written by tools/export_props.py from the server\'s spawns.txt: edit that file, not this one. -->\n'
                '<h2><span class="celColor">|CelMod| Props - %s</span><br>\n</h2>\n%s\n'
                '<p class="muted">Click a prop to copy it, ready to paste into the game\'s chat.</p>\n<p class="proplist">\n%s\n  <br>\n  </p><div class="btngrid"><a href="./">Back to Props List</a></div><p>\n  </p>\n'
                '<?php cm_page_end(); ?>\n') % (title, title, letter_grid(by_bucket, b), '\n'.join(lines))
        open(os.path.join(out_dir, b + '.php'), 'w').write(page)

    # Letters that no longer have props: their old pages are removed.
    for b in list(string.ascii_lowercase) + ['other']:
        path = os.path.join(out_dir, b + '.php')
        if b not in by_bucket and os.path.exists(path):
            os.remove(path)

    index = ("<?php require __DIR__ . '/../includes/bootstrap.php'; cm_page_start('|CelMod| - Prop List'); ?>\n"
             '<!-- Written by tools/export_props.py from the server\'s spawns.txt. -->\n'
             '<h2><span class="celColor">|CelMod| Props</span><br>\n</h2>\n'
             '<p>%d spawnable props for use with !spawn<br>\n'
             '  Usage: !spawn &lt;name of prop&gt; &lt;options&gt;<br>\n'
             '  Ex. <span class="highlight">!spawn woodcrate1 drop</span><br>\n  <b>OR</b><br>\n'
             '  Ex. <span class="highlight">!woodcrate1 drop</span><br>\n  <br>\n  Options include:<br>\n'
             '  <b>unfrozen</b> - Spawns the prop unfrozen<br>\n'
             '  <b>nogod</b> - Spawns the prop and makes it breakable<br>\n'
             '  <b>drop</b> - Spawns the prop at the floor<br>\n</p>\n'
             '<div class="searchbar"><input type="search" id="propfind" placeholder="Search all %d props... (press /)" aria-label="Search props" autocomplete="off">'
             ' <span class="count" id="propcount" aria-live="polite"></span></div>\n'
             '<div class="search-results" id="propresults" hidden></div>\n%s\n'
             '<div class="btngrid"><a href="shop">Shop Props</a> <a href="dis">Discontinued Props</a></div>\n'
             '<p>\n</p>\n<?php cm_page_end(\'<script src="search.js?v=\' . (int)@filemtime(__DIR__ . \'/search.js\') . \'" defer></script>\'); ?>\n') % (len(props), len(props), letter_grid(by_bucket))
    open(os.path.join(out_dir, 'index.php'), 'w').write(index)

    # Every prop name for the search box on the index (shop props are on their own page).
    import json
    open(os.path.join(out_dir, 'props.json'), 'w').write(json.dumps(props, separators=(',', ':')))

    rows = []
    for alias in sorted(shop_props):
        item = shop_props[alias]
        if not isinstance(item, dict):
            continue
        name = item.get('name', alias)
        price = item.get('price', '0')
        season = item.get('season', '')
        category = item.get('category', 'Rare Props')
        rows.append('<tr><td><b>%s</b></td><td>!spawn %s</td><td>%s</td><td><?= h(cm_cl(%d)) ?></td><td>%s</td></tr>' % (
            html.escape(name), html.escape(alias), html.escape(category), int(price or 0),
            html.escape(season.capitalize()) if season else 'All year'))

    shop_page = ("<?php require __DIR__ . '/../includes/bootstrap.php'; cm_page_start('|CelMod| - Shop Props'); ?>\n"
                 '<!-- Written by tools/export_props.py from the server\'s shop.txt. -->\n'
                 '<h2><span class="celColor">|CelMod| Shop Props</span><br>\n</h2>\n'
                 '<p>These props are CelItems: each one you buy is one copy, kept in your <b>!bank</b>. You can only have as many out\n'
                 'as you own, and !give, !trade or selling one makes it the other player\'s for good. Buy them in the\n'
                 '<a href="../shop">shop</a> or in game with <span class="highlight">!buy prop_&lt;name&gt;</span>.\n'
                 'Seasonal props are only sold in their season.</p>\n'
                 '<div class="table-scroll"><table class="cmtable">\n<tr><th>Prop</th><th>Spawn with</th><th>Category</th><th>Price</th><th>Sold</th></tr>\n%s\n</table></div>\n'
                 '<div class="btngrid"><a href="./">Back to Props List</a></div>\n<?php cm_page_end(); ?>\n') % '\n'.join(rows)
    open(os.path.join(out_dir, 'shop.php'), 'w').write(shop_page)

    print('%d props in %d pages, %d shop props written to %s' % (len(props), len(by_bucket), len(rows), out_dir))


if __name__ == '__main__':
    main()

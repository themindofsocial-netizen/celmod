#!/usr/bin/env python3
"""Writes the website's sound and music lists from the server's own sounds.txt, so they never go out of date.

    python3 tools/export_sounds.py ../celmod-website

Reads addons/sourcemod/data/celmod/sounds.txt ("Sounds": what !sound plays, "Music": what !music plays, with each
song's length) and writes sounds.php and music.php in the website folder.
"""
import html
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOUNDS = os.path.join(ROOT, 'addons', 'sourcemod', 'data', 'celmod', 'sounds.txt')


def section(text, name):
    """The "key" "value" pairs of one section, in file order."""
    m = re.search(r'"%s"\s*\{(.*?)\}' % re.escape(name), text, re.S)
    if not m:
        return []
    body = re.sub(r'//[^\n]*', '', m.group(1))
    return re.findall(r'"([^"]+)"\s+"([^"]*)"', body)


def natural(name):
    """Sort key: button2 before button10."""
    return [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', name.lower())]


def group_of(path):
    """A sound's folder: the top one (vo and npc one level further, they have so many)."""
    parts = path.replace('\\', '/').lower().split('/')
    if len(parts) >= 3 and parts[0] in ('vo', 'npc'):
        return parts[0] + '/' + parts[1]
    return parts[0] if len(parts) > 1 else 'other'


def page(title, intro, body, script):
    return ("<?php require __DIR__ . '/includes/bootstrap.php'; cm_page_start('|CelMod| - %s'); ?>\n"
            "<!-- Written by tools/export_sounds.py (celmod repo) from the server's sounds.txt: edit that file, not this one. -->\n"
            '<h2><span class="celColor">|CelMod| %s</span><br>\n</h2>\n%s\n%s\n'
            "<?php cm_page_end(%s); ?>\n") % (title, title, intro, body, script)


SEARCH_JS = r"""<<<'JS'
<script>
(function () {
	var box = document.getElementById('soundfind'), count = document.getElementById('soundcount');
	var items = document.querySelectorAll('.soundlist [data-name]'), groups = document.querySelectorAll('.soundgroup');
	if (!box) { return; }
	box.addEventListener('input', function () {
		var q = box.value.trim().toLowerCase().replace(/^!(sound|music)\s+/, '').replace(/^!/, ''), shown = 0;
		items.forEach(function (el) {
			var ok = q === '' || el.getAttribute('data-name').indexOf(q) !== -1;
			el.style.display = ok ? '' : 'none';
			if (ok) { shown++; }
		});
		groups.forEach(function (g) {
			var any = g.querySelector('[data-name]:not([style*="none"])');
			g.style.display = any ? '' : 'none';
			if (g.tagName === 'DETAILS') { g.open = q !== '' && !!any; }
		});
		count.textContent = q === '' ? '' : (shown === 0 ? 'Nothing matches' : shown + ' match' + (shown === 1 ? '' : 'es'));
	});
})();
</script>
JS"""


def main():
    site = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, '..', 'celmod-website')
    text = open(SOUNDS, encoding='utf-8', errors='replace').read()

    sounds = section(text, 'Sounds')
    groups = {}
    paths = dict(sounds)
    for name, path in sounds:
        groups.setdefault(group_of(path), []).append(name)

    blocks = []
    for g in sorted(groups, key=natural):
        names = groups[g]
        chips = '\n'.join('  <button type="button" data-name="%s %s" data-copy="!sound %s" title="%s">%s</button>'
                          % (html.escape(n.lower()), html.escape(paths[n].lower()), html.escape(n), html.escape(paths[n]), html.escape(n)) for n in sorted(names, key=natural))
        blocks.append('<details class="soundgroup"><summary><b>%s</b> <span class="muted">(%d)</span></summary>\n'
                      '<div class="search-results soundlist">\n%s\n</div></details>' % (html.escape(g), len(names), chips))

    intro = ('<p>%d sounds for the sound cel: every Half-Life 2 sound, by folder. Spawn one with '
             '<span class="h">!sound &lt;name&gt;</span>, then press <b>E</b> on the can (or link a button to it) to play it. '
             'In game, <span class="h">!soundlist</span> shows the folders and <span class="h">!soundlist &lt;word&gt;</span> searches.<br>\n'
             'Click a sound to copy its command, ready to paste into the chat.</p>\n'
             '<div class="searchbar"><input type="search" id="soundfind" placeholder="Find a sound... (press /)" '
             'aria-label="Find a sound" autocomplete="off"> <span class="count" id="soundcount" aria-live="polite"></span></div>\n'
             '<div class="btngrid"><a href="music">Music List</a> <a href="cmds">Commands</a></div>') % len(sounds)
    open(os.path.join(site, 'sounds.php'), 'w').write(page('Sounds', intro, '\n'.join(blocks), SEARCH_JS))

    music = section(text, 'Music')
    rows = []
    for name, value in music:
        parts = value.split('|')
        length = ''
        if len(parts) > 1:
            try:
                secs = int(float(parts[1]))
                length = '%d:%02d' % (secs // 60, secs % 60)
            except ValueError:
                pass
        rows.append('<tr data-name="%s"><td><b data-copy="!music %s" title="Copy !music %s">%s</b></td><td class="num">%s</td></tr>'
                    % (html.escape(name.lower()), html.escape(name), html.escape(name), html.escape(name), length))
    intro = ('<p>%d songs for the music cel. Spawn a radio with <span class="h">!music &lt;song&gt; [speed 50-200]</span>, '
             'then press <b>E</b> on it to play the song, and again to stop it. In game, <span class="h">!celmusic</span> '
             'lists them.<br>\nClick a song to copy its command.</p>\n'
             '<div class="searchbar"><input type="search" id="soundfind" placeholder="Find a song... (press /)" '
             'aria-label="Find a song" autocomplete="off"> <span class="count" id="soundcount" aria-live="polite"></span></div>\n'
             '<div class="btngrid"><a href="sounds">Sound List</a> <a href="cmds">Commands</a></div>') % len(music)
    body = ('<div class="table-scroll soundlist"><table class="cmtable">\n<tr><th>Song</th><th class="num">Length</th></tr>\n%s\n</table></div>'
            % '\n'.join(rows))
    open(os.path.join(site, 'music.php'), 'w').write(page('Music', intro, body, SEARCH_JS))

    print('%d sounds and %d songs written to %s' % (len(sounds), len(music), site))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Writes the website's render effect list (renderfx.php) from the list in celmod-entity.sp.

    python3 tools/export_renderfx.py ../celmod-website
"""
import html
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'addons', 'sourcemod', 'scripting', 'celmod-entity.sp')


def main():
    site = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, '..', 'celmod-website')
    text = open(SOURCE, encoding='utf-8').read()
    block = re.search(r'g_sRenderFXList\[\]\[\]\[\] = \{(.*?)\};', text, re.S).group(1)
    effects = re.findall(r'\{\s*"([^"]+)",\s*"([^"]+)"\s*\}', block)

    rows = '\n'.join('<tr><td><b data-copy="!renderfx %s" title="Copy !renderfx %s">%s</b></td><td>%s</td></tr>'
                     % (html.escape(n), html.escape(n), html.escape(n), html.escape(d)) for n, d in effects)
    page = ("<?php require __DIR__ . '/includes/bootstrap.php'; cm_page_start('|CelMod| - Render Effects'); ?>\n"
            "<!-- Written by tools/export_renderfx.py (celmod repo) from celmod-entity.sp: edit the list there. -->\n"
            '<h2><span class="celColor">|CelMod| Render Effects</span><br>\n</h2>\n'
            '<p>Look at one of your props and type <span class="h">!renderfx &lt;effect&gt;</span>. In game, '
            '<span class="h">!renderfx</span> on its own lists them. <span class="h">!renderfx default</span> takes the '
            'effect off again.<br>\nRender effects can be part of <span class="h">!animate</span> frames too. '
            'Click an effect to copy its command.</p>\n'
            '<div class="table-scroll"><table class="cmtable">\n<tr><th>Effect</th><th>What it looks like</th></tr>\n%s\n</table></div>\n'
            '<div class="btngrid"><a href="colors">Colors List</a> <a href="effects">Effects List</a> <a href="cmds">Commands</a></div>\n'
            '<?php cm_page_end(); ?>\n') % rows
    open(os.path.join(site, 'renderfx.php'), 'w').write(page)
    print('%d render effects written to %s' % (len(effects), os.path.join(site, 'renderfx.php')))


if __name__ == '__main__':
    main()

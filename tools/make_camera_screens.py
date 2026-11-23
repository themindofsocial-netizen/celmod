#!/usr/bin/env python3
"""Makes the "camera screen" copies of the TV models, so a TV linked to a camera cel shows the camera on its own screen.

    python tools/make_camera_screens.py --game "C:/path/to/server/hl2mp" --out "C:/path/to/server/hl2mp"
    python tools/make_camera_screens.py --game "C:/path/to/server/hl2mp" --out "C:/path/to/website/fastdl" --bz2

A server can't change one prop's material, and players' downloaded files can't replace Half-Life 2's own. So each
TV gets a copy of its model where only the screen's material is renamed to a new one (the same length, so nothing
else in the file moves), and that new material shows the camera picture (the _rt_Camera render target, as Half-Life
2's security monitors do). celmod-camera swaps a TV to its copy while it's linked to a camera, and back when it's
unlinked. The copies are made from the game's own files, read straight out of its VPKs, so they're never kept in
this repo.

Writes, for each TV below:
    models/celmod/camscreens/<model>.mdl (.vvd, .dx90.vtx, .dx80.vtx, .sw.vtx, .phy)
    materials/<the model's material folder>/<new screen name>.vmt
and prints the line for data/celmod/camerascreens.txt.

--bz2 writes them compressed for FastDL instead. --list <model> prints a model's materials (to find a screen's).
"""
import argparse
import bz2
import os
import struct
import sys

# The TVs: (stock model, its screen's material). Add more here (or with --add model=material).
SCREENS = [
    ('models/props_c17/tv_monitor01.mdl', 'tv_monitor01_screen'),
]

OUT_FOLDER = 'models/celmod/camscreens'
EXTENSIONS = ['.mdl', '.vvd', '.dx90.vtx', '.dx80.vtx', '.sw.vtx', '.phy']

SCREEN_VMT = '''// |CelMod| camera screen: a TV linked to a camera cel shows the camera here (made by tools/make_camera_screens.py).
"UnlitGeneric"
{
	"$basetexture" "_rt_Camera"
	"$model" "1"
}
'''


class Vpk:
    """Reads files out of a VPK (versions 1 and 2): the *_dir.vpk and its numbered archives."""

    def __init__(self, dir_path):
        self.dir_path = dir_path
        self.files = {}
        with open(dir_path, 'rb') as f:
            data = f.read()
        sig, version, tree_size = struct.unpack_from('<III', data, 0)
        if sig != 0x55AA1234:
            raise ValueError('%s is not a VPK' % dir_path)
        header = 12 if version == 1 else 28
        self.data_start = header + tree_size
        self.data = data
        pos = header

        def read_string():
            nonlocal pos
            end = data.index(b'\0', pos)
            s = data[pos:end].decode('latin-1')
            pos = end + 1
            return s

        while True:
            ext = read_string()
            if not ext:
                break
            while True:
                path = read_string()
                if not path:
                    break
                while True:
                    name = read_string()
                    if not name:
                        break
                    crc, preload, archive, offset, length, term = struct.unpack_from('<IHHIIH', data, pos)
                    pos += 18
                    preload_data = data[pos:pos + preload]
                    pos += preload
                    full = ('' if path == ' ' else path + '/') + name + ('' if ext == ' ' else '.' + ext)
                    self.files[full.lower()] = (preload_data, archive, offset, length)

    def read(self, path):
        entry = self.files.get(path.lower().replace('\\', '/'))
        if entry is None:
            return None
        preload, archive, offset, length = entry
        if length == 0:
            return preload
        if archive == 0x7FFF:
            return preload + self.data[self.data_start + offset:self.data_start + offset + length]
        base = self.dir_path[:-len('_dir.vpk')]
        with open('%s_%03d.vpk' % (base, archive), 'rb') as f:
            f.seek(offset)
            return preload + f.read(length)


class Game:
    """A file from the game: loose in hl2mp or hl2 first, then the VPKs of both."""

    def __init__(self, hl2mp):
        self.roots = [hl2mp, os.path.join(os.path.dirname(os.path.abspath(hl2mp)), 'hl2')]
        self.vpks = []
        for root in self.roots:
            if not os.path.isdir(root):
                continue
            for name in sorted(os.listdir(root)):
                if name.endswith('_dir.vpk'):
                    try:
                        self.vpks.append(Vpk(os.path.join(root, name)))
                    except (ValueError, OSError, struct.error) as e:
                        print('  skipping %s: %s' % (name, e), file=sys.stderr)

    def read(self, path):
        for root in self.roots:
            loose = os.path.join(root, path)
            if os.path.isfile(loose):
                with open(loose, 'rb') as f:
                    return f.read()
        for vpk in self.vpks:
            data = vpk.read(path)
            if data is not None:
                return data
        return None


def textures(mdl):
    """The model's material names, with where each name is in the file, and its material folders."""
    count, index, cd_count, cd_index = struct.unpack_from('<iiii', mdl, 204)
    names = []
    for i in range(count):
        at = index + i * 64
        name_at = at + struct.unpack_from('<i', mdl, at)[0]
        names.append((mdl[name_at:mdl.index(b'\0', name_at)].decode('latin-1'), name_at))
    folders = []
    for i in range(cd_count):
        at = struct.unpack_from('<i', mdl, cd_index + i * 4)[0]
        folders.append(mdl[at:mdl.index(b'\0', at)].decode('latin-1').replace('\\', '/'))
    return names, folders


def camera_name(name, taken):
    """A new material name the same length as the screen's, so the model file keeps its layout."""
    for tag in ('_cm', 'cm', 'c'):
        for i in range(10):
            mark = (tag + (str(i) if i else ''))
            if len(mark) >= len(name):
                continue
            new = name[:len(name) - len(mark)] + mark
            if new.lower() not in taken and new.lower() != name.lower():
                return new
    raise ValueError('no free name for %s' % name)


def make(game, model, screen, out, compress):
    mdl = game.read(model)
    if mdl is None or mdl[:4] != b'IDST':
        print('  %s: not found in the game' % model)
        return None

    names, folders = textures(mdl)
    match = [n for n in names if n[0].lower() == screen.lower()]
    if not match:
        print('  %s: has no material called %s (it has: %s)' % (model, screen, ', '.join(n for n, _ in names)))
        return None

    taken = set(n.lower() for n, _ in names)
    new = camera_name(match[0][0], taken)

    mdl = bytearray(mdl)
    mdl[match[0][1]:match[0][1] + len(new)] = new.encode('latin-1')

    stem = os.path.splitext(os.path.basename(model))[0]
    internal = '%s/%s.mdl' % (OUT_FOLDER[len('models/'):], stem)
    mdl[12:76] = internal.encode('latin-1').ljust(64, b'\0')[:64]

    def write(rel, data):
        rel = rel + ('.bz2' if compress else '')
        path = os.path.join(out, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            f.write(bz2.compress(data) if compress else data)
        print('    ' + rel)

    base = os.path.splitext(model)[0]
    for ext in EXTENSIONS:
        data = bytes(mdl) if ext == '.mdl' else game.read(base + ext)
        if data is not None:
            write('%s/%s%s' % (OUT_FOLDER, stem, ext), data)

    # The screen's new material, in the folder the model finds its materials in.
    folder = (folders[0] if folders else '').strip('/')
    vmt = 'materials/%s/%s.vmt' % (folder, new) if folder else 'materials/%s.vmt' % new
    write(vmt, SCREEN_VMT.encode())

    return '"%s"\n\t\t{\n\t\t\t"model"\t\t"%s/%s.mdl"\n\t\t\t"material"\t"%s"\n\t\t}' % (model, OUT_FOLDER, stem, vmt)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--game', required=True, help="the server's hl2mp folder (hl2 next to it is read too)")
    parser.add_argument('--out', help='where to write (the hl2mp folder, or the FastDL folder with --bz2)')
    parser.add_argument('--bz2', action='store_true', help='write .bz2 files for FastDL')
    parser.add_argument('--add', action='append', default=[], metavar='MODEL=MATERIAL', help='another TV: its model and its screen material')
    parser.add_argument('--list', metavar='MODEL', help="print a model's materials and stop")
    args = parser.parse_args()

    game = Game(args.game)

    if args.list:
        mdl = game.read(args.list)
        if mdl is None:
            sys.exit('%s: not found' % args.list)
        names, folders = textures(mdl)
        print('materials: ' + ', '.join(n for n, _ in names))
        print('folders:   ' + ', '.join(folders))
        return

    if not args.out:
        parser.error('--out is needed')

    screens = SCREENS + [tuple(a.split('=', 1)) for a in args.add]
    lines = []
    for model, screen in screens:
        print(model)
        line = make(game, model, screen, args.out, args.bz2)
        if line:
            lines.append(line)

    if lines:
        print('\nIn data/celmod/camerascreens.txt\'s "Screens" section (the TV is there already: check its "material"')
        print('matches, and add any new ones):')
        for line in lines:
            print('\t\t' + line)


if __name__ == '__main__':
    main()

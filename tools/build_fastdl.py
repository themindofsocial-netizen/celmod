#!/usr/bin/env python3
"""Builds the FastDL folder: every file players may need to download, compressed with bzip2 the way Source expects.

On the game server (the best way: it sees every file the server has):

    python tools/build_fastdl.py --game "C:/hl2dm/hl2mp" --out "C:/www/fastdl"

  For every map in cfg/mapcycle.txt it reads the map file and adds the map itself plus every texture, model and
  sound the map uses that the server has as a loose file (in hl2mp/ or hl2mp/custom/*/). Stock Half-Life 2
  content lives inside the game's .vpk files, so it is never copied. Textures a material uses and the files and
  textures of each model are followed too. It also adds everything in data/celmod/downloads.txt.

In this repo (no game server at hand):

    python3 tools/build_fastdl.py --maps DIR [--merge OLD_FASTDL_DIR]

  Adds this repo's materials/, models/ and sound/, the .bsp files in DIR, and (with --merge) the .bz2 files of
  another FastDL tree. Files from this repo replace merged ones with the same path.

Every path is written in lower case: the maps and the game ask for lower-case names, and web servers (and Linux)
treat "Rock.vtf" and "rock.vtf" as different files. Unchanged files are not compressed again.

Afterwards <out>/MISSING.txt lists what the maps or downloads.txt need but nobody has (with --game: files the
server doesn't have loose; they're stock if the game shows them fine, otherwise the server is missing them too).
"""
import argparse
import bz2
import io
import os
import re
import shutil
import struct
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTENT = ('materials', 'models', 'sound')
SKIP = ('.txt', '.md', '.bat', '.psd', '.tga', '.qc', '.smd')
MODEL_PARTS = ('.mdl', '.vvd', '.dx90.vtx', '.dx80.vtx', '.sw.vtx', '.phy', '.ani')
TEXTURE_KEYS = re.compile(
    r'^[ \t]*"?\$(basetexture2?|bumpmap2?|normalmap|detail|envmapmask|blendmodulatetexture|phongexponenttexture|'
    r'selfillummask|lightwarptexture|texture2|iris|ambientoccltexture|envmap|bottommaterial|underwateroverlay|'
    r'fallbackmaterial|refracttexture|reflecttexture|dudvmap|corneatexture)"?[ \t]+"?([^"\s}]+)"?', re.I | re.M)


def norm(path):
    return path.replace('\\', '/').strip().strip('/').lower()


def stock_files():
    """Stock Half-Life 2 files (inside the game's VPKs): never missing."""
    path = os.path.join(ROOT, 'tools', 'hl2_stock_files.txt')
    if not os.path.exists(path):
        return set()
    return {l.strip() for l in open(path, encoding='utf-8') if l.strip() and not l.startswith('#')}


def compress(src, dst, force=False):
    """Writes src as dst (.bz2) unless dst is already newer."""
    if not force and os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
        return False
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(src, 'rb') as fin, bz2.open(dst + '.tmp', 'wb', compresslevel=9) as fout:
        shutil.copyfileobj(fin, fout, 1 << 20)
    os.replace(dst + '.tmp', dst)
    return True


class GameFiles:
    """Finds loose files in the game folder and its custom/ folders, ignoring the case of names."""

    def __init__(self, game):
        self.index = {}
        roots = [game]
        custom = os.path.join(game, 'custom')
        if os.path.isdir(custom):
            roots += [os.path.join(custom, d) for d in sorted(os.listdir(custom)) if os.path.isdir(os.path.join(custom, d))]
        for base in roots:
            for top in CONTENT + ('maps',):
                for root, _, files in os.walk(os.path.join(base, top)):
                    for f in files:
                        rel = norm(os.path.relpath(os.path.join(root, f), base))
                        self.index.setdefault(rel, os.path.join(root, f))

    def find(self, rel):
        return self.index.get(norm(rel))


def map_dependencies(bsp_path):
    """The materials, models and sounds a map uses, and the files packed inside it."""
    data = open(bsp_path, 'rb').read()
    if data[:4] != b'VBSP':
        raise ValueError('not a Source map')
    lumps = [struct.unpack_from('<iiii', data, 8 + 16 * i) for i in range(64)]

    def lump(i):
        return data[lumps[i][0]:lumps[i][0] + lumps[i][1]]

    need = set()
    strings, table = lump(43), lump(44)
    for offset in struct.unpack('<%di' % (len(table) // 4), table):
        end = strings.index(b'\0', offset)
        need.add('materials/' + norm(strings[offset:end].decode('latin1')) + '.vmt')

    for key, value in re.findall(r'"([^"]*)"\s+"([^"]*)"', lump(0).decode('latin1', 'replace')):
        k, v = key.lower(), norm(value)
        if not v:
            continue
        if k == 'skyname':
            need.update('materials/skybox/%s%s.vmt' % (v, side) for side in ('bk', 'dn', 'ft', 'lf', 'rt', 'up'))
        elif v.endswith('.mdl'):
            need.add(v)
        elif v.endswith(('.vmt', '.spr')):
            need.add(('' if v.startswith('materials/') else 'materials/') + v[:-4] + '.vmt')
        elif k in ('texture', 'material', 'overlaymaterial', 'ropematerial'):
            need.add('materials/' + v + '.vmt')
        elif v.endswith(('.wav', '.mp3')) and k in ('message', 'sound', 'noise', 'startsound', 'stopsound', 'movesound'):
            need.add('sound/' + v.lstrip('*#@)(^><!?'))

    game = lump(35)
    for i in range(struct.unpack_from('<i', game, 0)[0]):
        gid, _, _, offset, _ = struct.unpack_from('<4sHHii', game, 4 + 16 * i)
        if gid in (b'prps', b'sprp'):
            count = struct.unpack_from('<i', data, offset)[0]
            for j in range(count):
                name = data[offset + 4 + 128 * j:offset + 132 + 128 * j].split(b'\0')[0]
                need.add(norm(name.decode('latin1')))

    packed = set()
    try:
        pak = zipfile.ZipFile(io.BytesIO(lump(40)))
        packed = {norm(n) for n in pak.namelist()}
        # Materials packed into the map (cubemap "patch" copies, mostly) point back to the real material.
        for n in pak.namelist():
            if n.lower().endswith('.vmt'):
                need.update(material_textures(pak.read(n).decode('latin1', 'replace')))
    except zipfile.BadZipFile:
        pass
    return need, packed


def material_textures(text):
    """Textures (.vtf) and other materials a .vmt uses."""
    out = set()
    for key, value in TEXTURE_KEYS.findall(text):
        v = norm(value)
        if v.startswith(('env_cubemap', '_rt_', '$')) or not v:
            continue
        if key.lower() in ('bottommaterial', 'underwateroverlay', 'fallbackmaterial'):
            out.add('materials/' + v + ('' if v.endswith('.vmt') else '.vmt'))
        else:
            out.add('materials/' + v + ('' if v.endswith('.vtf') else '.vtf'))
    for value in re.findall(r'"?include"?\s+"?([^"\s]+)"?', text, re.I):
        out.add(norm(value))
    return out


def model_materials(mdl_bytes):
    """The materials a model uses: every texture name in every material folder it lists."""
    try:
        num_tex, tex_index, num_cd, cd_index = struct.unpack_from('<iiii', mdl_bytes, 204)

        def cstr(at):
            return mdl_bytes[at:mdl_bytes.index(b'\0', at)].decode('latin1')

        names = [cstr(tex_index + 64 * i + struct.unpack_from('<i', mdl_bytes, tex_index + 64 * i)[0]) for i in range(num_tex)]
        folders = [cstr(struct.unpack_from('<i', mdl_bytes, cd_index + 4 * i)[0]) for i in range(num_cd)]
    except (struct.error, ValueError):
        return set()
    return {'materials/' + norm(folder + '/' + name) + '.vmt' for folder in folders for name in names}


def build_from_game(args, out):
    files = GameFiles(args.game)
    stock = stock_files()
    wanted, missing = set(), set()

    maps = []
    cycle = os.path.join(args.game, 'cfg', 'mapcycle.txt')
    if args.mapcycle:
        cycle = args.mapcycle
    if os.path.exists(cycle):
        maps = [line.split('//')[0].strip() for line in open(cycle, encoding='utf-8', errors='replace')]
        maps = [m for m in maps if m]

    queue = []
    for name in maps:
        bsp = files.find('maps/%s.bsp' % name)
        if not bsp:
            missing.add('maps/%s.bsp' % name)
            continue
        wanted.add('maps/%s.bsp' % name.lower())
        need, packed = map_dependencies(bsp)
        queue += [p for p in need if p not in packed]

    listing = os.path.join(args.game, 'addons', 'sourcemod', 'data', 'celmod', 'downloads.txt')
    if os.path.exists(listing):
        queue += [norm(l.split('//')[0]) for l in open(listing, encoding='utf-8', errors='replace') if l.split('//')[0].strip()]

    seen = set()
    while queue:
        rel = queue.pop()
        if rel in seen:
            continue
        seen.add(rel)
        path = files.find(rel)
        if rel.endswith('.mdl'):
            if not path:
                if rel not in stock:
                    missing.add(rel)
                continue
            base = rel[:-4]
            for part in MODEL_PARTS:
                if files.find(base + part):
                    wanted.add(base + part)
            # A model names its textures and the folders to look in: each texture is in one of them.
            by_name = {}
            for mat in model_materials(open(path, 'rb').read()):
                by_name.setdefault(mat.rsplit('/', 1)[1], []).append(mat)
            for options in by_name.values():
                found = [m for m in options if files.find(m)]
                queue += found
                if not found and not any(m in stock for m in options):
                    missing.add(' or '.join(options))
            continue
        if not path:
            # materials/maps/<map>/ files can only come from inside the map (cubemap copies): not FastDL's job.
            if rel not in stock and not rel.startswith('materials/maps/'):
                missing.add(rel)
            continue
        wanted.add(rel)
        if rel.endswith('.vmt'):
            queue += list(material_textures(open(path, encoding='latin1').read()))

    made = sum(compress(files.find(rel), os.path.join(out, rel + '.bz2')) for rel in sorted(wanted))
    return wanted, made, sorted(missing)


def build_from_repo(args, out):
    have, merged, made = set(), set(), 0

    # Older FastDL trees first, so this repo's newer files replace them.
    for tree in args.merge:
        for root, _, names in os.walk(tree):
            for f in names:
                rel = norm(os.path.relpath(os.path.join(root, f), tree))
                if not rel.endswith('.bz2') or rel.split('/')[0] not in CONTENT:
                    continue
                dst = os.path.join(out, rel)
                if not os.path.exists(dst):
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    shutil.copyfile(os.path.join(root, f), dst)
                    made += 1
                    merged.add(rel)
                have.add(rel[:-4])

    for top in CONTENT:
        for root, _, names in os.walk(os.path.join(ROOT, top)):
            for f in names:
                if f.lower().endswith(SKIP):
                    continue
                rel = norm(os.path.relpath(os.path.join(root, f), ROOT))
                made += compress(os.path.join(root, f), os.path.join(out, rel + '.bz2'), force=(rel + '.bz2') in merged)
                have.add(rel)

    if args.maps:
        for f in sorted(os.listdir(args.maps)):
            if f.lower().endswith('.bsp'):
                made += compress(os.path.join(args.maps, f), os.path.join(out, 'maps', f.lower() + '.bz2'))
    for root, _, names in os.walk(os.path.join(out, 'maps')):
        have.update('maps/' + f.lower()[:-4] for f in names if f.lower().endswith('.bz2'))

    missing = []
    listing = os.path.join(ROOT, 'addons', 'sourcemod', 'data', 'celmod', 'downloads.txt')
    if os.path.exists(listing):
        for line in open(listing, encoding='utf-8', errors='replace'):
            path = norm(line.split('//')[0])
            if path and path not in have:
                missing.append(path)
    return have, made, missing


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--game', help="the game server's hl2mp folder (reads its maps, content and mapcycle)")
    ap.add_argument('--mapcycle', help='a different mapcycle file (default: <game>/cfg/mapcycle.txt)')
    ap.add_argument('--maps', help='repo mode: folder with .bsp files to include')
    ap.add_argument('--merge', action='append', default=[], help='repo mode: an existing FastDL tree to keep files from')
    ap.add_argument('--out', default=os.path.join(ROOT, 'fastdl'))
    args = ap.parse_args()

    out = os.path.abspath(args.out)
    if args.game:
        have, made, missing = build_from_game(args, out)
        note = ('Needed by the maps or downloads.txt, but neither a file on the server nor stock Half-Life 2. Players\n'
                'see these as purple-and-black checkers or ERROR: add them to the server (hl2mp/ or hl2mp/custom/<pack>/)\n'
                'and run this again. (A few may be HL2DM\'s own stock files, which are fine.)\n\n')
    else:
        have, made, missing = build_from_repo(args, out)
        note = 'Files in downloads.txt that this FastDL does not have (players will not get them):\n\n'

    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, 'MISSING.txt'), 'w') as fm:
        fm.write(note + ('\n'.join(missing) + '\n' if missing else '(none)\n'))

    print('%d files in the FastDL (%d written), %d needed but not found -> %s'
          % (len(have), made, len(missing), os.path.join(out, 'MISSING.txt')))


if __name__ == '__main__':
    sys.exit(main())

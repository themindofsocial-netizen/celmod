#!/usr/bin/env python3
"""Builds models/celmod/phys8_inv.* (the Invisible emblem) from models/celmod/phys8.*.

The copy is the same model, but it reads its materials from models/celmod/emblemi/ instead of
models/celmod/emblem3/. Those materials have $no_draw, so the emblem is never drawn but stays an opaque
model, and Source still draws opaque models into shadows (render to texture and the flashlight).
Only the material folder name changes (same length), so the model's checksum and its .vvd/.vtx/.phy files
stay valid; they are copied under the new name.

Usage: python3 tools/make_invisible_emblem.py <folder holding phys8.mdl, .vvd, .dx90.vtx, ...>
"""
import os
import shutil
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "models/celmod"
DST = "models/celmod"
OLD = b"models\\celmod\\emblem3\\"
NEW = b"models\\celmod\\emblemi\\"

data = open(os.path.join(SRC, "phys8.mdl"), "rb").read()
count = data.count(OLD) + data.count(OLD.replace(b"\\", b"/"))
if count == 0:
    sys.exit("phys8.mdl does not use models/celmod/emblem3/ materials")

data = data.replace(OLD, NEW).replace(OLD.replace(b"\\", b"/"), NEW.replace(b"\\", b"/"))
os.makedirs(DST, exist_ok=True)
open(os.path.join(DST, "phys8_inv.mdl"), "wb").write(data)

for ext in (".vvd", ".phy", ".dx80.vtx", ".dx90.vtx", ".sw.vtx"):
    path = os.path.join(SRC, "phys8" + ext)
    if os.path.exists(path):
        shutil.copyfile(path, os.path.join(DST, "phys8_inv" + ext))
        print("copied", "phys8_inv" + ext)

print("wrote phys8_inv.mdl (%d material path(s) changed)" % count)

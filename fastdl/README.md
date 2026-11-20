# |CelMod| FastDL

FastDL lets players download the maps and custom content from a web server at full speed, instead of
slowly from the game server or not at all. Without it, players who don't already have a file see
purple-and-black checkers, ERROR models, or can't join a map they don't have.

This folder is a complete FastDL. It holds every file the server can send players, compressed with
bzip2 (`.bz2`) the way Source expects:

| Folder | What it has |
|---|---|
| `maps/` | The 8 maps in `cfg/mapcycle.txt` |
| `materials/`, `models/`, `sound/` | CelMod's content (emblems, hats, celweps, land skins, player models) and the maps' custom textures |
| `MISSING.txt` | Files the server needs but that aren't here. Check it after every rebuild. |

## Why it wasn't working

- The old FastDL (`rockzehh/celmod-archive`, `fastdl/`) only had the old `_cm2_r` / `_cm_r` maps. None of
  the current `_cm12` maps were there, so players couldn't download them.
- The current maps use custom textures and models (the `celmod/`, `cncr04s/` and `gm_forest/` folders
  and so on) that aren't packed inside the map files. Those weren't on the FastDL either.
- Newer CelMod files, such as the land skin decals, were missing too.
- Some texture files had capital letters in their names. Web servers treat `Rock.vtf` and `rock.vtf` as
  different files, so the game's request for the lower-case name failed. Every name here is now lower
  case.

## Setting it up

The game server and the website are on the same network, so the simplest setup is to serve this
folder from the website's own web server.

### 1. Put the files on the web server

Copy this whole `fastdl/` folder into the website's folder, so these addresses work:

```
https://celmod.net/fastdl/maps/gm_bloodyconstruct_cm12.bsp.bz2
https://celmod.net/fastdl/materials/cncr04s/rock/caveset1_1bs.vtf.bz2
```

Any web server works (Apache, nginx, IIS, Caddy). It only has to send the files as they are.

### 2. Make sure the web server will send these files

- **IIS (Windows)** won't send file types it doesn't know; it answers 404. Put a `web.config` in the
  `fastdl/` folder:

  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <configuration>
    <system.webServer>
      <staticContent>
        <remove fileExtension=".bz2" />
        <mimeMap fileExtension=".bz2" mimeType="application/octet-stream" />
      </staticContent>
    </system.webServer>
  </configuration>
  ```

- **nginx and Apache** send `.bz2` files out of the box. If the website routes every address through
  `index.php` (rewrite rules), make sure real files in `fastdl/` are served directly. The usual rules
  ("if the file exists, serve it") already do this.
- Don't turn on directory listing; FastDL doesn't need it.

### 3. Point the game server at it

These lines are in `cfg/server.cfg`:

```
sv_allowdownload 1
sv_downloadurl "https://celmod.net/fastdl/"
```

The address must end with `/`, and it must be the folder that holds `maps/` and `materials/`, not the
`maps/` folder itself. Change the server's map (or restart it) after editing.

### 4. Test it

1. Open one of the addresses from step 1 in a browser. It should download a file, not show a 404 or
   the website's page.
2. On a computer that hasn't played on the server, delete
   `Half-Life 2 Deathmatch/hl2mp/download/maps/gm_bloodyconstruct_cm12.bsp` if it's there. Join, and
   the map should download quickly.
3. In game, `developer 1` in the console shows each file as it downloads. A line saying a file failed
   means that file isn't on the FastDL.

## Rebuilding it

Rebuild after adding a map, changing a texture, or adding new CelMod content.

**On the game server (best):** the tool reads every map in the mapcycle and picks out exactly what each
one uses. Stock Half-Life 2 files are never copied, since everyone already has them. It needs
[Python 3](https://www.python.org/downloads/); on Windows, tick "Add python.exe to PATH" in the
installer. Run it from this repo:

```
python tools/build_fastdl.py --game "C:\path\to\server\hl2mp" --out "C:\path\to\website\fastdl"
```

- It reads `hl2mp/cfg/mapcycle.txt`, `hl2mp/maps/`, `hl2mp/materials`, `models` and `sound`, every
  `hl2mp/custom/<pack>/` folder, and CelMod's `downloads.txt`.
- It only compresses files that changed since the last run, so later runs are quick.
- Afterwards, read `MISSING.txt` in the output folder. Anything listed there isn't on the server, so
  players will see it as checkers or ERROR. Add those files to the server (keep the folder paths) and
  run the tool again. A few entries may be HL2DM's own stock files; those are fine.

**From this repo, without the server:**

```
python3 tools/build_fastdl.py --maps <folder with the .bsp files> --merge <an older fastdl folder>
```

This uses the repo's `materials/`, `models/` and `sound/`, plus the maps you point it at.

## Adding content to the server

Custom textures and models go into `hl2mp/custom/<any name>/materials/...` (or straight into
`hl2mp/materials/...`), with the same folder paths the map uses. Keep the names lower case. After
adding files, rebuild the FastDL so players get them too.

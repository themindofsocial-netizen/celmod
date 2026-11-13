# Celweps (Custom Guns weapon scripts)

These make CelMod's celweps real, separate weapons. They need the
[Custom Guns](https://github.com/Alienmario/customguns-hl2dm) plugin (and DHooks).

1. Install Custom Guns as its readme says (configs, gamedata and plugins into `addons/sourcemod`).
2. Copy these `weapon_cm_*.txt` files into `hl2mp/scripts/` (or `hl2mp/custom/<folder>/scripts/`).
3. Put the models on the server: this repository's `models/celweps/` folder (axe, swords, pickaxe, sunflower,
   saw gun, melon launcher, blade bow), plus `models/weapons/hl2meleepack/v_shovel.mdl` for the shovel.
   Their textures go in `materials/celweps/a1/`, `a2/`, `a5/`, `a6/`, `a8/`, `a9/`, `a10/` and `a11/`
   (for example `materials/celweps/a2/axe.vmt`); without them the weapons show a purple and black checkerboard.

Players get a celwep by pressing E on a weapon cel they own (`!weapon <name>` spawns one). One celwep is held at a
time: pressing E on another celwep swaps it in, and pressing E on the one held puts it back. CelMod turns off
Custom Guns' own weapon wheel (`customguns_global_switcher 0`, Reload is held back while a celwep is out) and its
default weapon (`customguns_default ""`).

Without Custom Guns, celweps still work: the player gets the stock weapon named by `base` in collectibles.txt.

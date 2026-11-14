Files for the FastDL host (sv_downloadurl), compressed the way Source expects (.bz2), laid out like the
host's own fastdl/ folder. Copy everything in here into the host's fastdl/ folder (for this server:
rockzehh/celmod-archive, fastdl/). Players download these instead of getting an error model or a missing texture.

  models/celmod/phys8_inv.*              the Invisible emblem's model
  materials/models/celmod/emblemi/       the Invisible emblem's (never drawn) materials
  materials/celmod/landskins/decal/      the land skin decals

Not included (not in this repo): the Gordon Freeman and Skeleton player models (models/humans/freeman,
models/humans/skeleton) and their materials. Compress those with bzip2 and add them the same way.

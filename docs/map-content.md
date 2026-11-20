# Map content the maps need

> **Update:** the cncr04s and Counter-Strike: Source textures for gm_bloodyconstruct_cm12 are now in this repo
> (materials/cncr04s, materials/de_nuke, materials/de_train). `tools/build_fastdl.py --game` run on the server
> rebuilds the FastDL from what the server has and lists anything still missing in MISSING.txt.

Worked out from the map files themselves (tools: the BSP texture table, entities, static props and each map's
packed files), then compared with every file stock Half-Life 2 ships (its VPK file lists) and with what this repo
already has. Anything left over has to be on the server and on the FastDL host, or players see purple-and-black
checkers and ERROR models.

**For each material listed, bring the .vmt and every .vtf it uses** (usually the same name, plus a `_normal` /
`_n` bump map or a `_detail` texture if the .vmt names one). Keep the folder paths exactly as written.

HL2DM has a few files of its own that aren't in Half-Life 2's lists, so a name here is very likely, not certainly,
missing. If you're unsure about one, check whether it shows up in game without the pack.

## gm_bloodyconstruct_cm12: only this map uses these

### Other materials (not in stock Half-Life 2)

- `materials/2.vmt`
- `materials/decals/decalmetalmanhole003a.vmt`
- `materials/decals/handyparking_n.vmt`
- `materials/decals/miloutlet001.vmt`
- `materials/decals/milstains002.vmt`
- `materials/decals/offsignb.vmt`
- `materials/metal/metalhull009b.vmt`
- `materials/metal/metalpipe003a_cheap.vmt`
- `materials/metal/metalwall058a.vmt`
- `materials/plaster/plasterwall028d.vmt`
- `materials/wood/woodshelf005a.vmt`

### CelMod's own materials

- `materials/celmod/condemned.vmt`
- `materials/celmod/gm_bloodyconstruct/blocked.vmt`
- `materials/celmod/gm_bloodyconstruct/carea.vmt`
- `materials/celmod/gm_bloodyconstruct/deladecal.vmt`
- `materials/celmod/gm_bloodyconstruct/noservice.vmt`
- `materials/celmod/gm_bloodyconstruct/poster1.vmt`
- `materials/celmod/gm_bloodyconstruct/poster2.vmt`
- `materials/celmod/gm_bloodyconstruct/poster3.vmt`
- `materials/celmod/gm_bloodyconstruct/poster4.vmt`
- `materials/celmod/gm_bloodyconstruct/poster5.vmt`
- `materials/celmod/gm_bloodyconstruct/poster6.vmt`
- `materials/celmod/gm_bloodyconstruct/stove.vmt`

### cncr04s texture pack

- `materials/cncr04s/dirt/cityrbblbs.vmt`
- `materials/cncr04s/dirt/d_rubble_flat.vmt`
- `materials/cncr04s/dirt/it_t_2-1dirtgrass512-01.vmt`
- `materials/cncr04s/metalpanel/miscpanel1.vmt`
- `materials/cncr04s/metalpanel/whs_heatingunit_frnt.vmt`
- `materials/cncr04s/metalpanel/whs_heatingunit_side.vmt`
- `materials/cncr04s/rock/caveset1_1bs.vmt`
- `materials/cncr04s/rock/it_t_3-2rockfacegrassbase01.vmt`

### Counter-Strike: Source content

- `materials/de_nuke/nukdoorsb.vmt`
- `materials/de_nuke/nuke_metalvent.vmt`
- `materials/de_train/train_metalceiling_01.vmt`
- `materials/de_train/train_metalceiling_02.vmt`

### Models (bring the .mdl with its .vvd, .dx90.vtx, .dx80.vtx, .sw.vtx, .phy and its materials)

- `models/celmod/cop1.mdl`
- `models/celmod/cop2.mdl`
- `models/celmod/cop3.mdl`
- `models/celmod/cop4.mdl`
- `models/celmod/cop5.mdl`
- `models/celmod/cop6.mdl`
- `models/celmod/cop7.mdl`
- `models/celmod/cop8.mdl`
- `models/celmod/cop9.mdl`
- `models/celmod/dead_head.mdl`
- `models/celmod/wide_eyes.mdl`
- `models/odessa_fix.mdl`
- `models/props/cs_office/computer_mouse.mdl`

## gm_bloodyconstruct_cm12: also used by other maps

These are probably already on the server (the other maps work), but they are not in this repo either.

- `materials/celmod/grass2.vmt`
- `materials/celmod/jimmy.vmt`
- `materials/celmod/lava.vmt`
- `materials/celmod/normbrick/normbrick02.vmt`
- `materials/celmod/poster_white.vmt`
- `materials/cncr04s/metal/secfence1.vmt`
- `materials/cncr04s/rock/drkgryflag1.vmt`
- `materials/cncr04s/rock/it_t_2-1rockface512-02.vmt`
- `materials/cncr04s/rock/it_t_rockface01.vmt`
- `materials/wood/woodwall004c.vmt`
- `models/gm_forest/tree_alder.mdl`
- `models/gm_forest/tree_birch1.mdl`

## The other maps

Custom content these maps use that is neither packed into the map, in stock Half-Life 2, nor in this repo.
If these maps already show fine on the server, the server has them; to make this repo complete, add them too.

<details><summary><b>gm_build_map_cm12</b> (52 files)</summary>

- `materials/blueblazing/celmod/cmbanner.vmt`
- `materials/celmod/normbrick/normbrick02.vmt`
- `materials/cncr04s/concretetypes/it_e_3-2wallconctrim-dark.vmt`
- `materials/cncr04s/concretetypes/stairs.vmt`
- `materials/cncr04s/grass/bocage_fencetop.vmt`
- `materials/cncr04s/grass/bocage_fencetop_dt.vmt`
- `materials/cncr04s/metal/bunker_hatch.vmt`
- `materials/cncr04s/metal/bunker_roof_int.vmt`
- `materials/cncr04s/metal/castiron.vmt`
- `materials/cncr04s/metal/ironwall1.vmt`
- `materials/cncr04s/metal/ironwall2.vmt`
- `materials/cncr04s/metal/secfence1.vmt`
- `materials/cncr04s/metalpanel/blackbarrel.vmt`
- `materials/cncr04s/rock/fencerow_stone1.vmt`
- `materials/cncr04s/sand/e3road.vmt`
- `materials/cncr04s/sand/ka_t_1-1sandroad01.vmt`
- `materials/cncr04s/sand/omaha_set1_dt.vmt`
- `materials/cncr04s/sand/sand1b.vmt`
- `materials/cnsc/blueglass.vmt`
- `materials/cs_havana/floor02_dt.vmt`
- `materials/decals/decalgraffiti043a_cs.vmt`
- `materials/decals/decalgraffiti056a_cs.vmt`
- `materials/gm_construct/grass.vmt`
- `materials/maps/qw_testmap/concrete/concretefloor019a_0_8256_-1759.vmt`
- `materials/maps/qw_testmap/concrete/concretefloor028a_-284_8256_-1769.vmt`
- `materials/maps/qw_testmap/concrete/concretefloor028a_-5_-27_-1578.vmt`
- `materials/maps/qw_testmap/concrete/concretefloor028a_0_8256_-1759.vmt`
- `materials/maps/qw_testmap/concrete/concretefloor028a_1664_0_64.vmt`
- `materials/maps/qw_testmap/concrete/concretefloor033a_-6664_-1280_-1792.vmt`
- `materials/maps/qw_testmap/glass/combineglass001a_-911_32_302.vmt`
- `materials/maps/qw_testmap/glass/combineglass001a_1664_0_64.vmt`
- `materials/maps/qw_testmap/glass/combineglass001a_36_32_192.vmt`
- `materials/maps/qw_testmap/metal/citadel_metalwall072c_-5_-27_-1578.vmt`
- `materials/maps/qw_testmap/metal/citadel_metalwall072c_-6664_-1280_-1792.vmt`
- `materials/maps/qw_testmap/metal/citadel_metalwall072c_-7764_-1280_-1802.vmt`
- `materials/maps/qw_testmap/metal/citadel_metalwall072c_-911_32_302.vmt`
- `materials/maps/qw_testmap/metal/citadel_metalwall072c_0_8256_-1759.vmt`
- `materials/maps/qw_testmap/metal/citadel_metalwall072c_1664_0_64.vmt`
- `materials/maps/qw_testmap/metal/citadel_metalwall072c_6174_-1216_-1972.vmt`
- `materials/maps/qw_testmap/metal/citadel_tilefloor016a_-5_-27_-1578.vmt`
- `materials/maps/qw_testmap/metal/citadel_tilefloor016a_-6664_-1280_-1792.vmt`
- `materials/maps/qw_testmap/metal/citadel_tilefloor016a_-911_32_302.vmt`
- `materials/maps/qw_testmap/metal/citadel_tilefloor016a_-960_8220_-1832.vmt`
- `materials/maps/qw_testmap/metal/citadel_tilefloor016a_0_8256_-1759.vmt`
- `materials/maps/qw_testmap/metal/citadel_tilefloor016a_1664_0_64.vmt`
- `materials/maps/qw_testmap/metal/citadel_tilefloor016a_6174_-1216_-1972.vmt`
- `materials/maps/qw_testmap/nature/water_canals_water2_-6664_-1280_-1792.vmt`
- `materials/maps/qw_testmap/tile/tilefloor016a_-911_32_302.vmt`
- `materials/maps/qw_testmap/tile/tilefloor016a_1664_0_64.vmt`
- `materials/maps/qw_testmap/tile/tilefloor016a_36_32_192.vmt`
- `materials/stone/stonewall014a.vmt`
- `materials/stone/tidstairsatp.vmt`

</details>

<details><summary><b>gm_cubeland_cm12</b> (4 files)</summary>

- `materials/celmod/gm_cubeland/d.vmt`
- `materials/celmod/gm_cubeland/sky_day01_09bk.vmt`
- `materials/celmod/gm_cubeland/sky_day01_09up.vmt`
- `materials/celmod/normbrick/normbrick02.vmt`

</details>

<details><summary><b>gm_cubicle_winter_cm12</b> (25 files)</summary>

- `materials/4.vmt`
- `materials/celmod/gm_cubicle/1_2.vmt`
- `materials/celmod/gm_cubicle/1_3.vmt`
- `materials/celmod/gm_cubicle/1_4.vmt`
- `materials/celmod/gm_cubicle/1_5.vmt`
- `materials/celmod/gm_cubicle/1_6.vmt`
- `materials/celmod/gm_cubicle/1_7.vmt`
- `materials/celmod/gm_cubicle/1_8.vmt`
- `materials/celmod/gm_cubicle/1_9.vmt`
- `materials/celmod/gm_cubicle/burntwood.vmt`
- `materials/celmod/gm_cubicle/water_frozen.vmt`
- `materials/celmod/normbrick/normbrick02.vmt`
- `materials/celmod/park_snow.vmt`
- `materials/cncr04s/brick/brick1trim.vmt`
- `materials/cncr04s/brick/brickfc2smbr.vmt`
- `materials/cncr04s/brick/church_interior_wall2flt.vmt`
- `materials/cncr04s/brick/greymarble_brick.vmt`
- `materials/cncr04s/brick/jh_patterntile1.vmt`
- `materials/cncr04s/ice/frozenriver.vmt`
- `materials/cncr04s/tile/glasstabletop_1.vmt`
- `materials/cncr04s/tile/marblegallery_floor.vmt`
- `models/celmod/phys8.mdl`
- `models/props_foliage/tree_pine_01.mdl`
- `models/props_foliage/tree_pine_02.mdl`
- `models/props_foliage/tree_pine_03.mdl`

</details>

<details><summary><b>gm_fourplay_cm12</b> (29 files)</summary>

- `materials/celmod/gm_fourplay/dela_spray.vmt`
- `materials/celmod/normbrick/normbrick02.vmt`
- `materials/celmod/park_grass.vmt`
- `materials/cncr04s/concretetypes/af-e-door03wallbase02.vmt`
- `materials/cncr04s/concretetypes/algierwall1drk_1flat.vmt`
- `materials/cncr04s/concretetypes/argenmid1.vmt`
- `materials/cncr04s/concretetypes/garagefloor.vmt`
- `materials/cncr04s/concretetypes/interiorwall_afrika1flat.vmt`
- `materials/cncr04s/dirt/d_rubble_flat_dt.vmt`
- `materials/cncr04s/metal/iron_floor2a.vmt`
- `materials/cncr04s/metal/iron_floor3b.vmt`
- `materials/cncr04s/metal/ironwall1.vmt`
- `materials/cncr04s/metal/ironwall2.vmt`
- `materials/cncr04s/metal/jh_corrugate4a.vmt`
- `materials/cncr04s/metal/wheel_side.vmt`
- `materials/cncr04s/plaster/plaster_wall2a.vmt`
- `materials/cncr04s/sand/ka_t_1-1sand03a_dt.vmt`
- `materials/cnsc/blueglass.vmt`
- `materials/color/white_poster.vmt`
- `materials/customtext/gc textures/earth/dirt_cracked01_dt.vmt`
- `materials/decals/decalgraffiti001b_cs.vmt`
- `materials/decals/decalgraffiti002a.vmt`
- `materials/decals/decalgraffiti027a_cs.vmt`
- `materials/metal/milgrate001.vmt`
- `materials/metal/milroof002.vmt`
- `materials/metal/proddoora.vmt`
- `materials/stone/stonefloor008a.vmt`
- `materials/wood/milflr002.vmt`
- `models/gm_forest/tree_birch1.mdl`

</details>

<details><summary><b>gm_grassyplains_cm12</b> (31 files)</summary>

- `materials/celmod/clouds3.vtf`
- `materials/celmod/grass2.vmt`
- `materials/celmod/grass4.vmt`
- `materials/celmod/grass4dirtblend.vmt`
- `materials/celmod/grass_b.vtf`
- `materials/celmod/jimmy.vmt`
- `materials/celmod/normbrick/normbrick02.vmt`
- `materials/cncr04s/grass/bocage_fencetop_dt.vmt`
- `materials/cncr04s/rock/it_t_2-1rockface512-02.vmt`
- `materials/nature/water_riverbed01_beneath.vmt`
- `materials/nature/water_riverbed04.vmt`
- `materials/stone/stonewall031j.vmt`
- `materials/wood/woodwall004c.vmt`
- `models/dav0r/buttons/switch.mdl`
- `models/gm_forest/grass.mdl`
- `models/grass/grass_long.mdl`
- `models/props_foliage/bush2.mdl`
- `models/props_foliage/ferns01.mdl`
- `models/props_foliage/ferns02.mdl`
- `models/props_foliage/grass3.mdl`
- `models/props_foliage/grass_cluster02.mdl`
- `models/props_foliage/rock_forest02.mdl`
- `models/props_foliage/shrub_small.mdl`
- `models/props_foliage/small_cattails.mdl`
- `models/props_foliage/tree_dry01.mdl`
- `models/props_foliage/tree_dry02.mdl`
- `models/props_foliage/tree_pine04.mdl`
- `models/props_foliage/tree_pine05.mdl`
- `models/props_foliage/tree_pine06.mdl`
- `models/props_foliage/tree_slice01.mdl`
- `models/props_foliage/tree_stump01.mdl`

</details>

<details><summary><b>gm_multi_area_cm12</b> (15 files)</summary>

- `materials//metal2.vmt`
- `materials/celmod/grass4.vmt`
- `materials/celmod/normbrick/normbrick02.vmt`
- `materials/celmod/water_autumn.vmt`
- `materials/concrete/concretefloor009a_construct.vmt`
- `materials/gm_construct/grass_13.vmt`
- `materials/phoenix_storms/celmod/citadel_metalwall078a.vmt`
- `materials/phoenix_storms/celmod/metalwall050a.vmt`
- `materials/phoenix_storms/celmod/plasterceiling002b.vmt`
- `materials/phoenix_storms/celmod/plasterwall008a.vmt`
- `materials/phoenix_storms/ps_grass.vmt`
- `models/gm_forest/tree_alder.mdl`
- `models/gm_forest/tree_birch1.mdl`
- `models/gm_forest/tree_oak1.mdl`
- `models/gm_forest/tree_oak2.mdl`

</details>

<details><summary><b>gm_park_cm12_snowy</b> (49 files)</summary>

- `materials/8.vmt`
- `materials/celmod/calapsy_1.vmt`
- `materials/celmod/calapsy_2.vmt`
- `materials/celmod/calapsy_load_hidef.vmt`
- `materials/celmod/calapsy_park.vmt`
- `materials/celmod/gm_cubicle/water_frozen.vmt`
- `materials/celmod/lava.vmt`
- `materials/celmod/maps_cm8/calmap_1.vmt`
- `materials/celmod/maps_cm8/calmap_2.vmt`
- `materials/celmod/maps_cm8/calmap_3.vmt`
- `materials/celmod/maps_cm8/calmap_4.vmt`
- `materials/celmod/maps_cm8/calmap_5.vmt`
- `materials/celmod/maps_cm8/calmap_6.vmt`
- `materials/celmod/maps_cm8/calmap_7.vmt`
- `materials/celmod/maps_cm8/calmap_8.vmt`
- `materials/celmod/maps_cm8/calmap_next.vmt`
- `materials/celmod/normbrick/normbrick02.vmt`
- `materials/celmod/park_hq_plaster1.vmt`
- `materials/celmod/park_snow.vmt`
- `materials/celmod/poster_white.vmt`
- `materials/cncr04s/concretetypes/af-e-concrete2t.vmt`
- `materials/cncr04s/concretetypes/af-e-concrete2t_dt.vmt`
- `materials/cncr04s/concretetypes/garagefloor.vmt`
- `materials/cncr04s/ice/ice1.vmt`
- `materials/cncr04s/metal-vent/industrialgrate1-trans.vmt`
- `materials/cncr04s/metal/bunk_ceiling.vmt`
- `materials/cncr04s/metal/bunker_hatch.vmt`
- `materials/cncr04s/metal/castiron.vmt`
- `materials/cncr04s/plaster/af_e_wall_mosquebase_01a.vmt`
- `materials/cncr04s/plaster/af_e_wall_mosquestripe_01.vmt`
- `materials/cncr04s/rock/cistone1smdrk.vmt`
- `materials/cncr04s/rock/drkgryflag1.vmt`
- `materials/cncr04s/rock/it_t_rockface01.vmt`
- `materials/cncr04s/sand/omaha_pjspick4.vmt`
- `materials/cncr04s/sand/omaha_pjspick4_dt.vmt`
- `materials/cncr04s/slime/canal_sludge.vmt`
- `materials/cncr04s/wood/frenchfloor_wood1.vmt`
- `materials/cncr04s/wood/gnrlcratesml_top.vmt`
- `materials/cs_havana/dirtfloor009c.vmt`
- `materials/de_nuke/nuke_metaldoor_01.vmt`
- `materials/decals/decalmetalmanhole004a.vmt`
- `materials/maps/gm_grassyplains_cm/nature/water_canals_city_murky_dx70_depth_88.vmt`
- `materials/props/plasticexitsign001a.vmt`
- `models/celmod/delaware.mdl`
- `models/celmod/phys3.mdl`
- `models/celmod/present02.mdl`
- `models/gm_forest/tree_alder.mdl`
- `models/props_foliage/jn_falltree_02.mdl`
- `models/stromy/plum_2.mdl`

</details>


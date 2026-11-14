#pragma semicolon 1

#include <celmod>
#include <sdktools>

#pragma newdecls required

#define SPAWNPAD_MODEL "models/celmod/spawnpad2.mdl"
#define SPAWNPAD_SOUND "ambient/levels/labs/electric_explosion1.wav"
#define MAX_PADTYPES 32

/*
 * Enemy spawn pads.
 *
 * Killing an enemy (in a map's dungeon, for example) counts toward its spawn pad. Every cm_spawnpad_kills kills
 * earns one pad of that kind, and each pad earned lets the player have one more of them placed at a time, so a
 * deleted pad is never lost. A placed pad keeps a few of its enemies alive on top of it. Enemies that come out of a
 * spawn pad never count toward kills, so pads can't be farmed. The kinds are listed in data/celmod/spawnpads.txt.
 */

bool g_bLate;
bool g_bLoaded[MAXPLAYERS + 1];
bool g_bPadOn[MAXENTITIES + 1];
bool g_bTypeOnFire[MAX_PADTYPES];

char g_sTypeAlias[MAX_PADTYPES][32];
char g_sTypeName[MAX_PADTYPES][64];
char g_sTypeClass[MAX_PADTYPES][64];
char g_sTypeKeyValues[MAX_PADTYPES][256];

ConVar g_cvKills;
ConVar g_cvInterval;

int g_iKills[MAXPLAYERS + 1][MAX_PADTYPES];
int g_iPadType[MAXENTITIES + 1];
int g_iSpawnedBy[MAXENTITIES + 1];
int g_iTypeCount;
int g_iTypeMax[MAX_PADTYPES];
int g_iTypeHealth[MAX_PADTYPES];
int g_iTypeSkin[MAX_PADTYPES];

#define MAX_DUNGEON 64

int g_iDungeonCount;
int g_iDungeonType[MAX_DUNGEON];
int g_iDungeonMax[MAX_DUNGEON];
float g_fDungeonInterval[MAX_DUNGEON];
float g_fDungeonOrigin[MAX_DUNGEON][3];
float g_fDungeonYaw[MAX_DUNGEON];
float g_fDungeonNext[MAX_DUNGEON];
int g_iDungeonOf[MAXENTITIES + 1] = { -1, ... };
int g_iBeamSprite;
ConVar g_cvDungeonInterval;
ConVar g_cvDungeonRange;
ConVar g_cvHuntRange;
ConVar g_cvXPEnemy;

ArrayList g_alPads;
StringMap g_smHookedClasses;

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	g_bLate = bLate;

	MarkNativeAsOptional("Cel_AddPlayerStat");
	MarkNativeAsOptional("Cel_AddTacticsXP");
	MarkNativeAsOptional("Cel_SetPlayerStat");

	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "|CelMod| Spawn Pads",
	author = CEL_AUTHOR,
	description = "Enemy spawn pads, earned by killing enemies.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	g_alPads = new ArrayList();
	g_smHookedClasses = new StringMap();

	for (int i = 0; i <= MAXENTITIES; i++)
	{
		g_iPadType[i] = -1;
		g_iSpawnedBy[i] = INVALID_ENT_REFERENCE;
	}

	g_cvKills = CreateConVar("cm_spawnpad_kills", "500", "Kills of an enemy needed for each of its spawn pads.", _, true, 1.0);
	g_cvInterval = CreateConVar("cm_spawnpad_interval", "8.0", "Seconds between a spawn pad's spawns.", _, true, 1.0);

	RegConsoleCmd("v_spawnpad", Command_SpawnPad, "|CelMod| Places an enemy spawn pad you have earned, or lists your kills and pads.");
	RegConsoleCmd("v_spawnpads", Command_SpawnPad, "|CelMod| Lists your enemy kills and the spawn pads you have earned.");

	LoadPadTypes();

	g_cvDungeonInterval = CreateConVar("cm_dungeon_interval", "15.0", "Default seconds between a dungeon spawner's spawns.", _, true, 2.0);
	g_cvXPEnemy = CreateConVar("cm_tactics_xp_enemy", "1.0", "Tactics experience for killing an enemy, for every 50 of its health (0 = none). Spawn pad enemies give none.", _, true, 0.0);
	g_cvHuntRange = CreateConVar("cm_dungeon_hunt_range", "1500.0", "How far away dungeon and spawn pad enemies notice a player they can see.", _, true, 0.0);
	g_cvDungeonRange = CreateConVar("cm_dungeon_range", "2000.0", "Dungeon spawners only spawn while a player is this close (0 = always).", _, true, 0.0);

	RegAdminCmd("v_dungeonspawner", Command_DungeonSpawner, ADMFLAG_SLAY, "|CelMod| Places a dungeon enemy spawner where you aim: <enemy> [max alive] [seconds between spawns]. Saved for this map.");
	RegAdminCmd("v_dungeonspawners", Command_DungeonSpawners, ADMFLAG_SLAY, "|CelMod| Lists this map's dungeon spawners and shows where they are.");
	RegAdminCmd("v_deldungeonspawner", Command_DelDungeonSpawner, ADMFLAG_SLAY, "|CelMod| Removes the dungeon spawner nearest to where you aim, or one by number (all = every one on this map).");
	RegAdminCmd("v_dungeonclear", Command_DungeonClear, ADMFLAG_SLAY, "|CelMod| Removes every enemy the dungeon spawners have spawned (the spawners stay).");

	if (g_bLate)
	{
		int iEntity = -1;

		while ((iEntity = FindEntityByClassname(iEntity, "*")) != -1)
		{
			if (iEntity > MaxClients)
			{
				RequestFrame(Frame_CheckPad, EntIndexToEntRef(iEntity));
			}
		}
	}
}

public void OnMapStart()
{
	PrecacheModel(SPAWNPAD_MODEL, true);
	PrecacheSound(SPAWNPAD_SOUND, true);

	g_alPads.Clear();

	g_iBeamSprite = PrecacheModel("sprites/laserbeam.vmt", true);
	LoadDungeon();

	CreateTimer(1.0, Timer_SpawnPads, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

//HL2DM never loads Half-Life 2's skill settings, so every enemy's health and damage ConVar is 0: enemies spawn
//with almost no health and their attacks do nothing. Any of them still at 0 gets Half-Life 2's normal value.
public void OnConfigsExecuted()
{
	static const char sSkill[][][] =
	{
		{ "sk_zombie_health", "50" }, { "sk_zombie_dmg_one_slash", "10" }, { "sk_zombie_dmg_both_slash", "25" },
		{ "sk_zombie_poison_health", "175" }, { "sk_zombie_poison_dmg_spit", "20" },
		{ "sk_fastzombie_health", "50" }, { "sk_fastzombie_dmg_one_slash", "6" }, { "sk_fastzombie_dmg_both_slash", "10" },
		{ "sk_zombine_health", "100" },
		{ "sk_headcrab_health", "10" }, { "sk_headcrab_melee_dmg", "5" },
		{ "sk_headcrab_fast_health", "10" },
		{ "sk_headcrab_poison_health", "35" },
		{ "sk_antlion_health", "30" }, { "sk_antlion_swipe_damage", "5" }, { "sk_antlion_jump_damage", "5" },
		{ "sk_antlionguard_health", "500" }, { "sk_antlionguard_dmg_charge", "20" }, { "sk_antlionguard_dmg_shove", "10" },
		{ "sk_manhack_health", "25" }, { "sk_manhack_melee_dmg", "20" },
		{ "sk_stalker_health", "50" }, { "sk_stalker_melee_dmg", "5" },
		{ "sk_strider_health", "350" }, { "sk_strider_num_missiles1", "5" }, { "sk_strider_num_missiles2", "7" }, { "sk_strider_num_missiles3", "7" },
		{ "sk_vortigaunt_health", "100" }, { "sk_vortigaunt_dmg_claw", "10" }, { "sk_vortigaunt_dmg_rake", "25" }, { "sk_vortigaunt_dmg_zap", "25" },
		{ "sk_ichthyosaur_health", "200" }, { "sk_ichthyosaur_melee_dmg", "8" },
		{ "sk_rollermine_shock", "10" }, { "sk_rollermine_stun_delay", "3" }, { "sk_rollermine_vehicle_intercept", "1" }
	};

	for (int i = 0; i < sizeof(sSkill); i++)
	{
		ConVar cvSkill = FindConVar(sSkill[i][0]);

		if (cvSkill != null && cvSkill.FloatValue == 0.0)
		{
			cvSkill.SetString(sSkill[i][1]);
		}
	}
}

public void OnClientDisconnect(int iClient)
{
	g_bLoaded[iClient] = false;
}

void LoadPadTypes()
{
	char sPath[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod/spawnpads.txt");

	KeyValues kvPads = new KeyValues("SpawnPads");

	g_iTypeCount = 0;

	if (!kvPads.ImportFromFile(sPath) || !kvPads.GotoFirstSubKey())
	{
		LogError("Could not read %s.", sPath);
		delete kvPads;
		return;
	}

	do
	{
		int i = g_iTypeCount;

		kvPads.GetSectionName(g_sTypeAlias[i], sizeof(g_sTypeAlias[]));
		kvPads.GetString("name", g_sTypeName[i], sizeof(g_sTypeName[]), g_sTypeAlias[i]);
		kvPads.GetString("classname", g_sTypeClass[i], sizeof(g_sTypeClass[]), "");
		kvPads.GetString("keyvalues", g_sTypeKeyValues[i], sizeof(g_sTypeKeyValues[]), "");

		g_iTypeSkin[i] = kvPads.GetNum("skin", 0);
		g_iTypeMax[i] = kvPads.GetNum("max", 2);
		g_iTypeHealth[i] = kvPads.GetNum("health", 0);
		g_bTypeOnFire[i] = kvPads.GetNum("onfire", 0) != 0;

		//Every kill of this enemy is heard through its OnDeath output.
		if (g_sTypeClass[i][0] != '\0' && !g_smHookedClasses.ContainsKey(g_sTypeClass[i]))
		{
			g_smHookedClasses.SetValue(g_sTypeClass[i], true);
			HookEntityOutput(g_sTypeClass[i], "OnDeath", Output_EnemyDeath);
		}

		g_iTypeCount++;
	}
	while (g_iTypeCount < MAX_PADTYPES && kvPads.GotoNextKey());

	delete kvPads;
}

//Kills are kept in the player's settings file as "padkills_<alias>".
void LoadKills(int iClient)
{
	if (g_bLoaded[iClient])
	{
		return;
	}

	char sSetting[64];

	for (int i = 0; i < g_iTypeCount; i++)
	{
		FormatEx(sSetting, sizeof(sSetting), "padkills_%s", g_sTypeAlias[i]);

		int iKills = Cel_GetClientSettingInt(iClient, sSetting);

		g_iKills[iClient][i] = iKills < 0 ? 0 : iKills;
	}

	g_bLoaded[iClient] = true;
}

int GetPadsEarned(int iClient, int iType)
{
	LoadKills(iClient);

	return g_iKills[iClient][iType] / g_cvKills.IntValue;
}

int FindPadType(const char[] sSearch)
{
	for (int i = 0; i < g_iTypeCount; i++)
	{
		if (StrEqual(g_sTypeAlias[i], sSearch, false) || StrEqual(g_sTypeName[i], sSearch, false))
		{
			return i;
		}
	}

	return -1;
}

int FindPadTypeBySkin(int iSkin)
{
	for (int i = 0; i < g_iTypeCount; i++)
	{
		if (g_iTypeSkin[i] == iSkin)
		{
			return i;
		}
	}

	return -1;
}

public void Output_EnemyDeath(const char[] sOutput, int iCaller, int iActivator, float fDelay)
{
	if (iCaller <= MaxClients || iCaller > MAXENTITIES || iActivator < 1 || iActivator > MaxClients || !IsClientInGame(iActivator))
	{
		return;
	}

	//Enemies from a spawn pad never count.
	if (g_iSpawnedBy[iCaller] != INVALID_ENT_REFERENCE)
	{
		return;
	}

	char sClass[64];

	GetEntityClassname(iCaller, sClass, sizeof(sClass));

	bool bOnFire = (GetEntityFlags(iCaller) & FL_ONFIRE) != 0;
	int iMatch = -1, iFallback = -1;

	//A burning enemy counts toward its fire pad if it has one (the Fire Zombie), otherwise toward its plain pad.
	for (int i = 0; i < g_iTypeCount; i++)
	{
		if (!StrEqual(g_sTypeClass[i], sClass, false))
		{
			continue;
		}

		if (g_bTypeOnFire[i] == bOnFire)
		{
			iMatch = i;
			break;
		}

		if (!g_bTypeOnFire[i])
		{
			iFallback = i;
		}
	}

	if (iMatch == -1)
	{
		iMatch = iFallback;
	}

	if (iMatch == -1)
	{
		return;
	}

	AddKill(iActivator, iMatch);

	//Tactics experience: tougher enemies are worth more (one point for every 50 health, at least one).
	int iMaxHealth = HasEntProp(iCaller, Prop_Data, "m_iMaxHealth") ? GetEntProp(iCaller, Prop_Data, "m_iMaxHealth") : 0;

	Cel_AddXP(iActivator, RoundToCeil(float(iMaxHealth < 50 ? 50 : iMaxHealth) / 50.0 * g_cvXPEnemy.FloatValue));
}

void AddKill(int iClient, int iType)
{
	char sSetting[64];

	LoadKills(iClient);

	g_iKills[iClient][iType]++;

	Cel_AddStat(iClient, "enemy_kills");

	FormatEx(sSetting, sizeof(sSetting), "padkills_%s", g_sTypeAlias[iType]);
	Cel_SetClientSettingInt(iClient, sSetting, g_iKills[iClient][iType]);

	if (g_iKills[iClient][iType] % g_cvKills.IntValue == 0)
	{
		Cel_PrintToChatAll("{green}%N{default} has killed {green}%d %s{default}s and earned a {green}%s spawn pad{default}!", iClient, g_iKills[iClient][iType], g_sTypeName[iType], g_sTypeName[iType]);
		Cel_PrintToChat(iClient, "Type {green}[tag]spawnpad %s{default} to place it.", g_sTypeAlias[iType]);
	}
}

public Action Command_SpawnPad(int iClient, int iArgs)
{
	char sArg[64];

	if (iClient < 1)
	{
		return Plugin_Handled;
	}

	LoadKills(iClient);

	if (iArgs < 1)
	{
		ListPads(iClient);
		return Plugin_Handled;
	}

	GetCmdArgString(sArg, sizeof(sArg));
	TrimString(sArg);
	StripQuotes(sArg);

	if (StrEqual(sArg, "on", false) || StrEqual(sArg, "off", false))
	{
		TogglePad(iClient, StrEqual(sArg, "on", false));
		return Plugin_Handled;
	}

	int iType = FindPadType(sArg);

	if (iType == -1)
	{
		Cel_ReplyToCommand(iClient, "There is no {green}%s{default} spawn pad. Type {green}[tag]spawnpads{default} to see them all.", sArg);
		return Plugin_Handled;
	}

	if (g_sTypeClass[iType][0] == '\0')
	{
		Cel_ReplyToCommand(iClient, "The {green}%s{default} spawn pad isn't available yet.", g_sTypeName[iType]);
		return Plugin_Handled;
	}

	int iEarned = GetPadsEarned(iClient, iType), iPlaced = CountPlacedPads(iClient, iType);

	if (iEarned < 1)
	{
		Cel_ReplyToCommand(iClient, "Kill {green}%d{default} more %ss to earn a {green}%s spawn pad{default}.", g_cvKills.IntValue - g_iKills[iClient][iType], g_sTypeName[iType], g_sTypeName[iType]);
		return Plugin_Handled;
	}

	if (iPlaced >= iEarned)
	{
		Cel_ReplyToCommand(iClient, "All {green}%d{default} of your %s spawn pads are already placed.", iEarned, g_sTypeName[iType]);
		return Plugin_Handled;
	}

	if (!Cel_CheckPropCount(iClient))
	{
		Cel_ReplyToCommand(iClient, "You have reached your prop limit.");
		return Plugin_Handled;
	}

	float fAngles[3], fOrigin[3];

	Cel_GetCrosshairHitOrigin(iClient, fOrigin);

	GetClientAbsAngles(iClient, fAngles);
	fAngles[0] = 0.0;

	int iPad = Cel_SpawnProp(iClient, "spawnpad", "prop_physics_override", SPAWNPAD_MODEL, fAngles, fOrigin, 255, 255, 255, 255);

	if (iPad == -1)
	{
		return Plugin_Handled;
	}

	SetEntProp(iPad, Prop_Send, "m_nSkin", g_iTypeSkin[iType]);

	Cel_FixSpawnPosition(iPad, fOrigin);

	//Pads sit still so their enemies spawn where they were placed.
	AcceptEntityInput(iPad, "DisableMotion");

	RegisterPad(iPad, iType);

	Cel_ReplyToCommand(iClient, "Placed a {green}%s spawn pad{default}. Look at it and type {green}[tag]spawnpad off{default} to pause it.", g_sTypeName[iType]);

	return Plugin_Handled;
}

void ListPads(int iClient)
{
	int iNeed = g_cvKills.IntValue;

	Cel_ReplyToCommand(iClient, "Your spawn pads (one for every {green}%d{default} kills of an enemy):", iNeed);

	for (int i = 0; i < g_iTypeCount; i++)
	{
		if (g_sTypeClass[i][0] == '\0')
		{
			continue;
		}

		int iEarned = g_iKills[iClient][i] / iNeed;

		if (iEarned > 0)
		{
			Cel_ReplyToCommand(iClient, "{green}%s{default}: %d kills, %d pad%s (%d placed). Place one with {green}[tag]spawnpad %s{default}.", g_sTypeName[i], g_iKills[iClient][i], iEarned, iEarned == 1 ? "" : "s", CountPlacedPads(iClient, i), g_sTypeAlias[i]);
		}
		else if (g_iKills[iClient][i] > 0)
		{
			Cel_ReplyToCommand(iClient, "{green}%s{default}: %d/%d kills.", g_sTypeName[i], g_iKills[iClient][i], iNeed);
		}
	}
}

void TogglePad(int iClient, bool bOn)
{
	int iPad = Cel_GetClientAimTarget(iClient);

	if (iPad <= MaxClients || iPad > MAXENTITIES || g_iPadType[iPad] == -1)
	{
		Cel_ReplyToCommand(iClient, "Look at a spawn pad first.");
		return;
	}

	if (!Cel_CanEdit(iClient, iPad))
	{
		Cel_ReplyToCommand(iClient, "That spawn pad isn't yours.");
		return;
	}

	g_bPadOn[iPad] = bOn;

	Cel_ReplyToCommand(iClient, "The {green}%s spawn pad{default} is now {green}%s{default}.", g_sTypeName[g_iPadType[iPad]], bOn ? "on" : "off");
}

int CountPlacedPads(int iClient, int iType)
{
	int iCount = 0;

	for (int i = 0; i < g_alPads.Length; i++)
	{
		int iPad = EntRefToEntIndex(g_alPads.Get(i));

		if (iPad != INVALID_ENT_REFERENCE && g_iPadType[iPad] == iType && Cel_GetOwner(iPad) == iClient)
		{
			iCount++;
		}
	}

	return iCount;
}

void RegisterPad(int iPad, int iType)
{
	int iRef = EntIndexToEntRef(iPad);

	if (g_alPads.FindValue(iRef) != -1)
	{
		return;
	}

	g_iPadType[iPad] = iType;
	g_bPadOn[iPad] = true;

	g_alPads.Push(iRef);
}

public void OnEntityCreated(int iEntity, const char[] sClassname)
{
	if (iEntity > MaxClients && iEntity <= MAXENTITIES)
	{
		g_iPadType[iEntity] = -1;
		g_iSpawnedBy[iEntity] = INVALID_ENT_REFERENCE;
		g_iDungeonOf[iEntity] = -1;

		RequestFrame(Frame_CheckPad, EntIndexToEntRef(iEntity));
	}
}

//Pads loaded from a build (or spawned before a plugin reload) are found by their model; the skin says the kind.
public void Frame_CheckPad(any iRef)
{
	int iEntity = EntRefToEntIndex(iRef);

	if (iEntity == INVALID_ENT_REFERENCE || iEntity <= MaxClients || iEntity > MAXENTITIES || g_iPadType[iEntity] != -1 || !Cel_IsEntity(iEntity))
	{
		return;
	}

	char sModel[PLATFORM_MAX_PATH];

	GetEntPropString(iEntity, Prop_Data, "m_ModelName", sModel, sizeof(sModel));

	if (!StrEqual(sModel, SPAWNPAD_MODEL, false))
	{
		return;
	}

	int iType = FindPadTypeBySkin(GetEntProp(iEntity, Prop_Send, "m_nSkin"));

	if (iType != -1)
	{
		RegisterPad(iEntity, iType);
	}
}

public void OnEntityDestroyed(int iEntity)
{
	if (iEntity <= MaxClients || iEntity > MAXENTITIES)
	{
		return;
	}

	if (g_iPadType[iEntity] != -1)
	{
		int iRef = EntIndexToEntRef(iEntity), iIndex = g_alPads.FindValue(iRef);

		if (iIndex != -1)
		{
			g_alPads.Erase(iIndex);
		}

		//Its enemies go with it.
		for (int i = MaxClients + 1; i <= MAXENTITIES; i++)
		{
			if (g_iSpawnedBy[i] == iRef && IsValidEntity(i))
			{
				AcceptEntityInput(i, "Kill");
			}
		}
	}

	g_iPadType[iEntity] = -1;
	g_iSpawnedBy[iEntity] = INVALID_ENT_REFERENCE;
	g_iDungeonOf[iEntity] = -1;
}

public Action Timer_SpawnPads(Handle hTimer)
{
	float fNow = GetGameTime();
	static float fNextSpawn[MAXENTITIES + 1];

	ThinkDungeon(fNow);

	//Every couple of seconds, idle enemies from dungeons and pads go looking for a player.
	static int iTick;

	if (++iTick % 2 == 0)
	{
		for (int i = MaxClients + 1; i <= MAXENTITIES; i++)
		{
			if ((g_iDungeonOf[i] != -1 || g_iSpawnedBy[i] != INVALID_ENT_REFERENCE) && IsValidEntity(i))
			{
				HuntPlayers(i);
			}
		}
	}

	for (int i = 0; i < g_alPads.Length; i++)
	{
		int iPad = EntRefToEntIndex(g_alPads.Get(i));

		if (iPad == INVALID_ENT_REFERENCE)
		{
			continue;
		}

		int iType = g_iPadType[iPad], iOwner = Cel_GetOwner(iPad);

		if (!g_bPadOn[iPad] || iType == -1 || g_sTypeClass[iType][0] == '\0' || iOwner < 1 || iOwner > MaxClients || !IsClientInGame(iOwner) || fNow < fNextSpawn[iPad])
		{
			continue;
		}

		//Pads beyond what the owner has earned (from an old build, say) stay idle.
		if (PadRank(iPad, iOwner, iType) >= GetPadsEarned(iOwner, iType))
		{
			continue;
		}

		fNextSpawn[iPad] = fNow + g_cvInterval.FloatValue;

		if (CountEnemies(iPad) < g_iTypeMax[iType])
		{
			SpawnEnemy(iPad, iType);
		}
	}

	return Plugin_Continue;
}

//Which of its owner's pads of this kind this one is, oldest first.
int PadRank(int iPad, int iOwner, int iType)
{
	int iRank = 0;

	for (int i = 0; i < g_alPads.Length; i++)
	{
		int iOther = EntRefToEntIndex(g_alPads.Get(i));

		if (iOther == iPad)
		{
			break;
		}

		if (iOther != INVALID_ENT_REFERENCE && g_iPadType[iOther] == iType && Cel_GetOwner(iOther) == iOwner)
		{
			iRank++;
		}
	}

	return iRank;
}

int CountEnemies(int iPad)
{
	int iRef = EntIndexToEntRef(iPad), iCount = 0;

	for (int i = MaxClients + 1; i <= MAXENTITIES; i++)
	{
		if (g_iSpawnedBy[i] == iRef && IsValidEntity(i))
		{
			iCount++;
		}
	}

	return iCount;
}

void SpawnEnemy(int iPad, int iType)
{
	float fOrigin[3], fAngles[3];

	GetEntPropVector(iPad, Prop_Data, "m_vecAbsOrigin", fOrigin);
	GetEntPropVector(iPad, Prop_Data, "m_angAbsRotation", fAngles);

	fOrigin[2] += 16.0;

	float fSpot[3];

	if (!FindSpawnSpot(fOrigin, fSpot))
	{
		return;
	}

	int iEnemy = SpawnEnemyAt(iType, fSpot, fAngles[1]);

	if (iEnemy == -1)
	{
		return;
	}

	//Enemies from a player's pad never count toward kills.
	g_iSpawnedBy[iEnemy] = EntIndexToEntRef(iPad);

	EmitAmbientSound(SPAWNPAD_SOUND, fOrigin, iPad, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
}

//Creates one enemy of a kind (spawnpads.txt) standing at a spot.
int SpawnEnemyAt(int iType, float fOrigin[3], float fYaw)
{
	float fAngles[3];

	int iEnemy = CreateEntityByName(g_sTypeClass[iType]);

	if (iEnemy == -1)
	{
		return -1;
	}

	if (iEnemy > MAXENTITIES)
	{
		AcceptEntityInput(iEnemy, "Kill");
		return -1;
	}

	//"key value;key value" from spawnpads.txt.
	if (g_sTypeKeyValues[iType][0] != '\0')
	{
		char sPairs[16][128], sPair[2][64];
		int iPairs = ExplodeString(g_sTypeKeyValues[iType], ";", sPairs, sizeof(sPairs), sizeof(sPairs[]));

		for (int i = 0; i < iPairs; i++)
		{
			TrimString(sPairs[i]);

			if (ExplodeString(sPairs[i], " ", sPair, sizeof(sPair), sizeof(sPair[]), true) == 2)
			{
				DispatchKeyValue(iEnemy, sPair[0], sPair[1]);
			}
		}
	}

	fAngles[1] = fYaw;

	//Corpses fade away instead of piling up.
	DispatchKeyValue(iEnemy, "spawnflags", "512");

	TeleportEntity(iEnemy, fOrigin, fAngles, NULL_VECTOR);
	DispatchSpawn(iEnemy);
	ActivateEntity(iEnemy);

	//A health set for this enemy in spawnpads.txt ("health") wins over the game's default.
	if (g_iTypeHealth[iType] > 0)
	{
		SetEntProp(iEnemy, Prop_Data, "m_iHealth", g_iTypeHealth[iType]);
		SetEntProp(iEnemy, Prop_Data, "m_iMaxHealth", g_iTypeHealth[iType]);
	}

	//HL2DM's game rules don't give enemies Half-Life 2's relationships, so they treat players as neutral and never
	//attack. Each one is told to hate players.
	SetVariantString("player D_HT 99");
	AcceptEntityInput(iEnemy, "SetRelationship");

	AcceptEntityInput(iEnemy, "Wake");

	if (g_bTypeOnFire[iType])
	{
		AcceptEntityInput(iEnemy, "Ignite");
	}

	return iEnemy;
}

//A clear spot for a new enemy near a point: the point itself if nothing stands there, otherwise a few tries in a ring
//around it, so enemies never spawn inside each other (stuck in a stack) or inside a player. False if all are taken.
bool FindSpawnSpot(const float fCenter[3], float fSpot[3])
{
	float fMins[3] = { -18.0, -18.0, 0.0 }, fMaxs[3] = { 18.0, 18.0, 72.0 };

	for (int i = 0; i < 12; i++)
	{
		fSpot = fCenter;

		if (i > 0)
		{
			float fAngle = GetRandomFloat(0.0, 6.2832), fDist = GetRandomFloat(40.0, 110.0);

			fSpot[0] += Cosine(fAngle) * fDist;
			fSpot[1] += Sine(fAngle) * fDist;
		}

		fSpot[2] += 4.0;

		TR_TraceHullFilter(fSpot, fSpot, fMins, fMaxs, MASK_NPCSOLID, Filter_SpawnSpot);

		if (TR_DidHit())
		{
			continue;
		}

		//There must be a way there from the spawner (not through a wall).
		TR_TraceRayFilter(fCenter, fSpot, MASK_NPCSOLID_BRUSHONLY, RayType_EndPoint, Filter_SpawnSpot);

		if (!TR_DidHit())
		{
			return true;
		}
	}

	return false;
}

public bool Filter_SpawnSpot(int iEntity, int iMask)
{
	return true;
}

//Enemies that haven't noticed anyone are told about the nearest player they can see, so they come for them
//instead of standing where they spawned.
void HuntPlayers(int iEnemy)
{
	if (!HasEntProp(iEnemy, Prop_Data, "m_hEnemy"))
	{
		return;
	}

	int iCurrent = GetEntPropEnt(iEnemy, Prop_Data, "m_hEnemy");

	if (iCurrent > 0 && iCurrent <= MaxClients && IsClientInGame(iCurrent) && IsPlayerAlive(iCurrent))
	{
		return;
	}

	float fEyes[3], fPos[3], fBest = g_cvHuntRange.FloatValue;
	int iTarget = -1;

	GetEntPropVector(iEnemy, Prop_Data, "m_vecAbsOrigin", fEyes);
	fEyes[2] += 40.0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetEntityMoveType(i) == MOVETYPE_NOCLIP)
		{
			continue;
		}

		GetClientEyePosition(i, fPos);

		float fDist = GetVectorDistance(fEyes, fPos);

		if (fDist >= fBest)
		{
			continue;
		}

		TR_TraceRayFilter(fEyes, fPos, MASK_VISIBLE, RayType_EndPoint, Filter_NotEnemy, iEnemy);

		if (TR_DidHit() && TR_GetEntityIndex() != i)
		{
			continue;
		}

		fBest = fDist;
		iTarget = i;
	}

	if (iTarget == -1)
	{
		return;
	}

	//UpdateEnemyMemory takes a targetname: the player gets a short-lived one for it, then their own back.
	char sOld[64];

	GetEntPropString(iTarget, Prop_Data, "m_iName", sOld, sizeof(sOld));
	SetEntPropString(iTarget, Prop_Data, "m_iName", "cm_hunt_target");

	SetVariantString("cm_hunt_target");
	AcceptEntityInput(iEnemy, "UpdateEnemyMemory");

	SetEntPropString(iTarget, Prop_Data, "m_iName", sOld);
}

public bool Filter_NotEnemy(int iEntity, int iMask, any iEnemy)
{
	return iEntity != iEnemy;
}

/*
 * Dungeon spawners: admins place them in a map's dungeon (!dungeonspawner), and they keep enemies coming for
 * players to fight. Unlike a player's spawn pad, kills of these enemies count toward spawn pads. They are
 * invisible, saved per map in data/celmod/dungeons/<map>.txt, and only spawn while a player is nearby.
 */

void DungeonPath(char[] sPath, int iMaxLength)
{
	char sMap[PLATFORM_MAX_PATH];

	GetCurrentMap(sMap, sizeof(sMap));
	GetMapDisplayName(sMap, sMap, sizeof(sMap));

	BuildPath(Path_SM, sPath, iMaxLength, "data/celmod/dungeons");

	if (!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}

	BuildPath(Path_SM, sPath, iMaxLength, "data/celmod/dungeons/%s.txt", sMap);
}

void LoadDungeon()
{
	char sPath[PLATFORM_MAX_PATH], sEnemy[64];

	g_iDungeonCount = 0;

	for (int i = 0; i <= MAXENTITIES; i++)
	{
		g_iDungeonOf[i] = -1;
	}

	DungeonPath(sPath, sizeof(sPath));

	KeyValues kvDungeon = new KeyValues("Dungeon");

	if (!kvDungeon.ImportFromFile(sPath) || !kvDungeon.GotoFirstSubKey())
	{
		delete kvDungeon;
		return;
	}

	do
	{
		kvDungeon.GetString("enemy", sEnemy, sizeof(sEnemy), "");

		int iType = FindPadType(sEnemy);

		if (iType == -1 || g_sTypeClass[iType][0] == '\0' || g_iDungeonCount >= MAX_DUNGEON)
		{
			continue;
		}

		int i = g_iDungeonCount++;

		g_iDungeonType[i] = iType;
		kvDungeon.GetVector("origin", g_fDungeonOrigin[i]);
		g_fDungeonYaw[i] = kvDungeon.GetFloat("yaw", 0.0);
		g_iDungeonMax[i] = kvDungeon.GetNum("max", g_iTypeMax[iType]);
		g_fDungeonInterval[i] = kvDungeon.GetFloat("interval", 0.0);
		g_fDungeonNext[i] = 0.0;
	}
	while (kvDungeon.GotoNextKey());

	delete kvDungeon;
}

void SaveDungeon()
{
	char sPath[PLATFORM_MAX_PATH], sKey[8];

	DungeonPath(sPath, sizeof(sPath));

	KeyValues kvDungeon = new KeyValues("Dungeon");

	for (int i = 0; i < g_iDungeonCount; i++)
	{
		IntToString(i + 1, sKey, sizeof(sKey));

		kvDungeon.JumpToKey(sKey, true);
		kvDungeon.SetString("enemy", g_sTypeAlias[g_iDungeonType[i]]);
		kvDungeon.SetVector("origin", g_fDungeonOrigin[i]);
		kvDungeon.SetFloat("yaw", g_fDungeonYaw[i]);
		kvDungeon.SetNum("max", g_iDungeonMax[i]);
		kvDungeon.SetFloat("interval", g_fDungeonInterval[i]);
		kvDungeon.GoBack();
	}

	if (!kvDungeon.ExportToFile(sPath))
	{
		LogError("|CelMod| Could not write '%s'.", sPath);
	}

	delete kvDungeon;
}

public Action Command_DungeonSpawner(int iClient, int iArgs)
{
	char sArg[64];

	if (iClient < 1)
	{
		return Plugin_Handled;
	}

	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]dungeonspawner{default} <enemy> [max alive] [seconds between spawns]");
		ListEnemyKinds(iClient);
		return Plugin_Handled;
	}

	GetCmdArg(1, sArg, sizeof(sArg));

	int iType = FindPadType(sArg);

	if (iType == -1 || g_sTypeClass[iType][0] == '\0')
	{
		Cel_ReplyToCommand(iClient, "There is no enemy called {green}%s{default}.", sArg);
		ListEnemyKinds(iClient);
		return Plugin_Handled;
	}

	if (g_iDungeonCount >= MAX_DUNGEON)
	{
		Cel_ReplyToCommand(iClient, "This map already has {green}%d{default} dungeon spawners, the most it can have.", MAX_DUNGEON);
		return Plugin_Handled;
	}

	int i = g_iDungeonCount++;

	g_iDungeonType[i] = iType;
	g_iDungeonMax[i] = g_iTypeMax[iType];
	g_fDungeonInterval[i] = 0.0;
	g_fDungeonNext[i] = 0.0;

	if (iArgs >= 2)
	{
		GetCmdArg(2, sArg, sizeof(sArg));
		g_iDungeonMax[i] = ClampInt(StringToInt(sArg), 1, 16);
	}

	if (iArgs >= 3)
	{
		GetCmdArg(3, sArg, sizeof(sArg));
		g_fDungeonInterval[i] = StringToFloat(sArg) < 2.0 ? 2.0 : StringToFloat(sArg);
	}

	float fAngles[3];

	Cel_GetCrosshairHitOrigin(iClient, g_fDungeonOrigin[i]);
	g_fDungeonOrigin[i][2] += 8.0;

	//The enemies face the player who placed it.
	GetClientEyeAngles(iClient, fAngles);
	g_fDungeonYaw[i] = fAngles[1] + 180.0;

	SaveDungeon();
	ShowDungeonSpawner(iClient, i);

	Cel_ReplyToCommand(iClient, "Dungeon spawner {green}#%d{default} placed: up to {green}%d %s{default}%s, every {green}%.0f{default} seconds.", i + 1, g_iDungeonMax[i], g_sTypeName[iType], g_iDungeonMax[i] == 1 ? "" : "s", DungeonInterval(i));

	return Plugin_Handled;
}

public Action Command_DungeonSpawners(int iClient, int iArgs)
{
	float fEyes[3];

	if (g_iDungeonCount == 0)
	{
		Cel_ReplyToCommand(iClient, "This map has no dungeon spawners. Place one with {green}[tag]dungeonspawner{default} <enemy>.");
		return Plugin_Handled;
	}

	if (iClient > 0)
	{
		GetClientEyePosition(iClient, fEyes);
	}

	Cel_ReplyToCommand(iClient, "Dungeon spawners on this map (shown for 10 seconds):");

	for (int i = 0; i < g_iDungeonCount; i++)
	{
		Cel_ReplyToCommand(iClient, "{green}#%d{default} %s: %d/%d alive, every %.0fs", i + 1, g_sTypeName[g_iDungeonType[i]], CountDungeonEnemies(i), g_iDungeonMax[i], DungeonInterval(i));

		if (iClient > 0)
		{
			ShowDungeonSpawner(iClient, i);
		}
	}

	return Plugin_Handled;
}

public Action Command_DelDungeonSpawner(int iClient, int iArgs)
{
	char sArg[16];
	int iRemove = -1;

	if (iArgs >= 1)
	{
		GetCmdArg(1, sArg, sizeof(sArg));

		if (StrEqual(sArg, "all", false))
		{
			for (int i = g_iDungeonCount - 1; i >= 0; i--)
			{
				RemoveDungeonSpawner(i);
			}

			SaveDungeon();
			Cel_ReplyToCommand(iClient, "Every dungeon spawner on this map has been removed.");
			return Plugin_Handled;
		}

		iRemove = StringToInt(sArg) - 1;
	}
	else if (iClient > 0)
	{
		//The one nearest to where the admin is aiming, within a short distance.
		float fAim[3], fBest = 256.0;

		Cel_GetCrosshairHitOrigin(iClient, fAim);

		for (int i = 0; i < g_iDungeonCount; i++)
		{
			float fDist = GetVectorDistance(fAim, g_fDungeonOrigin[i]);

			if (fDist < fBest)
			{
				fBest = fDist;
				iRemove = i;
			}
		}
	}

	if (iRemove < 0 || iRemove >= g_iDungeonCount)
	{
		Cel_ReplyToCommand(iClient, "Aim at a dungeon spawner (see them with {green}[tag]dungeonspawners{default}), or give its number.");
		return Plugin_Handled;
	}

	Cel_ReplyToCommand(iClient, "Dungeon spawner {green}#%d{default} (%s) removed.", iRemove + 1, g_sTypeName[g_iDungeonType[iRemove]]);

	RemoveDungeonSpawner(iRemove);
	SaveDungeon();

	return Plugin_Handled;
}

public Action Command_DungeonClear(int iClient, int iArgs)
{
	int iCount = 0;

	for (int i = MaxClients + 1; i <= MAXENTITIES; i++)
	{
		if (g_iDungeonOf[i] != -1 && IsValidEntity(i))
		{
			AcceptEntityInput(i, "Kill");
			iCount++;
		}
	}

	Cel_ReplyToCommand(iClient, "Removed {green}%d{default} dungeon enemies.", iCount);

	return Plugin_Handled;
}

//Removes a spawner and its enemies; the ones after it move down a number.
void RemoveDungeonSpawner(int iIndex)
{
	for (int i = MaxClients + 1; i <= MAXENTITIES; i++)
	{
		if (g_iDungeonOf[i] == iIndex && IsValidEntity(i))
		{
			AcceptEntityInput(i, "Kill");
		}
		else if (g_iDungeonOf[i] > iIndex)
		{
			g_iDungeonOf[i]--;
		}
	}

	for (int i = iIndex; i < g_iDungeonCount - 1; i++)
	{
		g_iDungeonType[i] = g_iDungeonType[i + 1];
		g_iDungeonMax[i] = g_iDungeonMax[i + 1];
		g_fDungeonInterval[i] = g_fDungeonInterval[i + 1];
		g_fDungeonOrigin[i] = g_fDungeonOrigin[i + 1];
		g_fDungeonYaw[i] = g_fDungeonYaw[i + 1];
		g_fDungeonNext[i] = g_fDungeonNext[i + 1];
	}

	g_iDungeonCount--;
}

void ListEnemyKinds(int iClient)
{
	char sList[512];

	for (int i = 0; i < g_iTypeCount; i++)
	{
		if (g_sTypeClass[i][0] != '\0')
		{
			Format(sList, sizeof(sList), "%s%s%s", sList, sList[0] == '\0' ? "" : ", ", g_sTypeAlias[i]);
		}
	}

	Cel_ReplyToCommand(iClient, "Enemies: {green}%s{default}", sList);
}

int ClampInt(int iValue, int iMin, int iMax)
{
	return iValue < iMin ? iMin : (iValue > iMax ? iMax : iValue);
}

float DungeonInterval(int i)
{
	return g_fDungeonInterval[i] > 0.0 ? g_fDungeonInterval[i] : g_cvDungeonInterval.FloatValue;
}

int CountDungeonEnemies(int iIndex)
{
	int iCount = 0;

	for (int i = MaxClients + 1; i <= MAXENTITIES; i++)
	{
		if (g_iDungeonOf[i] == iIndex && IsValidEntity(i))
		{
			iCount++;
		}
	}

	return iCount;
}

//A ring and a pillar of light at a spawner, for the admin only, for 10 seconds.
void ShowDungeonSpawner(int iClient, int iIndex)
{
	int iColor[4] = { 255, 60, 60, 255 };
	float fTop[3];

	fTop = g_fDungeonOrigin[iIndex];
	fTop[2] += 96.0;

	TE_SetupBeamRingPoint(g_fDungeonOrigin[iIndex], 47.0, 48.0, g_iBeamSprite, 0, 0, 10, 10.0, 3.0, 0.0, iColor, 0, 0);
	TE_SendToClient(iClient);

	TE_SetupBeamPoints(g_fDungeonOrigin[iIndex], fTop, g_iBeamSprite, 0, 0, 10, 10.0, 3.0, 3.0, 0, 0.0, iColor, 0);
	TE_SendToClient(iClient);
}

//Called every second from Timer_SpawnPads.
void ThinkDungeon(float fNow)
{
	float fRange = g_cvDungeonRange.FloatValue;

	for (int i = 0; i < g_iDungeonCount; i++)
	{
		if (fNow < g_fDungeonNext[i])
		{
			continue;
		}

		g_fDungeonNext[i] = fNow + DungeonInterval(i);

		if (CountDungeonEnemies(i) >= g_iDungeonMax[i])
		{
			continue;
		}

		//Only while someone is near, and never right on top of a player.
		bool bNear = fRange <= 0.0, bBlocked = false;
		float fPos[3];

		for (int c = 1; c <= MaxClients; c++)
		{
			if (!IsClientInGame(c) || !IsPlayerAlive(c))
			{
				continue;
			}

			GetClientAbsOrigin(c, fPos);

			float fDist = GetVectorDistance(fPos, g_fDungeonOrigin[i]);

			if (fDist < 48.0)
			{
				bBlocked = true;
			}

			if (fDist <= fRange)
			{
				bNear = true;
			}
		}

		if (!bNear || bBlocked)
		{
			continue;
		}

		float fSpot[3];

		if (!FindSpawnSpot(g_fDungeonOrigin[i], fSpot))
		{
			continue;
		}

		int iEnemy = SpawnEnemyAt(g_iDungeonType[i], fSpot, g_fDungeonYaw[i]);

		if (iEnemy != -1)
		{
			g_iDungeonOf[iEnemy] = i;
		}
	}
}

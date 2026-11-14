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
int g_iTypeSkin[MAX_PADTYPES];

ArrayList g_alPads;
StringMap g_smHookedClasses;

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	g_bLate = bLate;

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

	CreateTimer(1.0, Timer_SpawnPads, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

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

	CreateTimer(1.0, Timer_SpawnPads, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
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
}

void AddKill(int iClient, int iType)
{
	char sSetting[64];

	LoadKills(iClient);

	g_iKills[iClient][iType]++;

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
}

public Action Timer_SpawnPads(Handle hTimer)
{
	float fNow = GetGameTime();
	static float fNextSpawn[MAXENTITIES + 1];

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

	int iEnemy = CreateEntityByName(g_sTypeClass[iType]);

	if (iEnemy == -1)
	{
		return;
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

	GetEntPropVector(iPad, Prop_Data, "m_vecAbsOrigin", fOrigin);
	GetEntPropVector(iPad, Prop_Data, "m_angAbsRotation", fAngles);

	fOrigin[2] += 16.0;
	fAngles[0] = 0.0;
	fAngles[2] = 0.0;

	g_iSpawnedBy[iEnemy] = EntIndexToEntRef(iPad);

	TeleportEntity(iEnemy, fOrigin, fAngles, NULL_VECTOR);
	DispatchSpawn(iEnemy);
	ActivateEntity(iEnemy);

	if (g_bTypeOnFire[iType])
	{
		AcceptEntityInput(iEnemy, "Ignite");
	}

	EmitAmbientSound(SPAWNPAD_SOUND, fOrigin, iPad, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
}

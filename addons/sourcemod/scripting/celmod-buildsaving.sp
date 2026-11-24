#pragma semicolon 1

#include <celmod>

#pragma newdecls required

bool g_bLate;

float g_fCrosshairOrigin[MAXPLAYERS + 1][3];
bool g_bLoading[MAXPLAYERS + 1]; //a build is being spawned in batches for this player
ConVar g_cvLoadBatch;
ConVar g_cvLoadBudget;

Handle g_hOnBuildLoaded;
Handle g_hOnLoadEntity;
Handle g_hOnSaveEntity;

int g_iSaveOverride[MAXPLAYERS + 1];

//The build market: players sell copies of their saved builds. A listing is a copy of the save, taken when it is
//listed, kept in data/celmod/buildmarket/<id>.txt; the listings themselves, and what each seller has earned while
//offline, are in data/celmod/buildmarket/market.txt. Selling never takes the build away from its seller.
char g_sMarketDir[PLATFORM_MAX_PATH];
char g_sMarketFile[PLATFORM_MAX_PATH];
ConVar g_cvMarketMax;
ConVar g_cvMarketMaxPrice;
ConVar g_cvMarketFee;
int g_iLockedSkipped[MAXPLAYERS + 1]; //shop props left out of the build that is loading, because the player doesn't own them

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	CreateNative("Cel_LoadBuild", Native_LoadBuild);
	CreateNative("Cel_SaveBuild", Native_SaveBuild);
	
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "|CelMod| Build Saving System",
	author = CEL_AUTHOR,
	description = "Handles saving/loading of client buildings.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	LoadTranslations("celmod.phrases");
	
	g_hOnBuildLoaded = CreateGlobalForward("Cel_OnBuildLoaded", ET_Ignore, Param_Cell, Param_String);
	g_hOnLoadEntity = CreateGlobalForward("Cel_OnLoadEntity", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	g_hOnSaveEntity = CreateGlobalForward("Cel_OnSaveEntity", ET_Ignore, Param_Cell, Param_Cell);
	
	if (g_bLate)
	{
		for (int i = 1; i < MaxClients; i++)
		{
			if (IsClientAuthorized(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
	
	g_cvLoadBatch = CreateConVar("cm_load_per_frame", "6", "Most entities spawned per server frame when a build loads. Lower = smoother for everyone, but slower to load.", _, true, 1.0);
	g_cvLoadBudget = CreateConVar("cm_load_frame_ms", "2.0", "Milliseconds a loading build may spend spawning in one server frame (the rest waits for the next frame).", _, true, 0.2);
	RegConsoleCmd("v_load", Command_LoadBuild, "|CelMod| Loads entities from a save file.");
	RegConsoleCmd("v_save", Command_SaveBuild, "|CelMod| Saves all server entities that are in your land.");
	RegConsoleCmd("v_saves", Command_ListSaves, "|CelMod| Lists your saved builds.");
	RegConsoleCmd("v_builds", Command_ListSaves, "|CelMod| Lists your saved builds.");
	
	RegConsoleCmd("v_sellbuild", Command_SellBuild, "|CelMod| Puts a copy of one of your saved builds on the build market: !sellbuild <save> <price>.");
	RegConsoleCmd("v_unsellbuild", Command_UnsellBuild, "|CelMod| Takes one of your builds off the build market: !unsellbuild <save or listing number>.");
	RegConsoleCmd("v_buildmarket", Command_BuildMarket, "|CelMod| Shows the builds other players are selling.");
	RegConsoleCmd("v_market", Command_BuildMarket, "|CelMod| Shows the builds other players are selling.");
	RegConsoleCmd("v_buybuild", Command_BuyBuild, "|CelMod| Buys a copy of a build from the build market: !buybuild <listing number>.");
	RegAdminCmd("v_delbuildlisting", Command_DelListing, ADMFLAG_SLAY, "|CelMod| Removes any listing from the build market: v_delbuildlisting <listing number>.");
	
	g_cvMarketMax = CreateConVar("cm_buildmarket_max", "5", "Most builds one player can have on the build market at once.", _, true, 1.0);
	g_cvMarketMaxPrice = CreateConVar("cm_buildmarket_maxprice", "1000000", "Highest price a build can be sold for on the build market.", _, true, 1.0);
	g_cvMarketFee = CreateConVar("cm_buildmarket_fee", "10", "Percent of each build market sale kept by the server (taken out of what the seller gets).", _, true, 0.0, true, 100.0);
	
	BuildPath(Path_SM, g_sMarketDir, sizeof(g_sMarketDir), "data/celmod/buildmarket");
	
	if (!DirExists(g_sMarketDir))
	{
		CreateDirectory(g_sMarketDir, 511);
	}
	
	BuildPath(Path_SM, g_sMarketFile, sizeof(g_sMarketFile), "data/celmod/buildmarket/market.txt");
}

public void OnClientPutInServer(int iClient)
{
	char sAuthID[64], sPath[PLATFORM_MAX_PATH];
	
	Cel_ChooseHudColor(iClient);
	
	Cel_GetAuthID(iClient, sAuthID, sizeof(sAuthID));
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod/users/%s/saves", sAuthID);
	if (!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}
}

//Finds the client's Steam id and makes sure their save folder exists. Returns false if the id is not known yet.
bool Cel_PrepareSaveFolder(int iClient, char[] sAuthID, int iMaxLength)
{
	char sPath[PLATFORM_MAX_PATH];
	
	Cel_GetAuthID(iClient, sAuthID, iMaxLength);
	
	//The stored id is empty when Steam had not confirmed the player when they joined.
	if (sAuthID[0] == '\0' && !GetClientAuthId(iClient, AuthId_SteamID64, sAuthID, iMaxLength, false))
	{
		sAuthID[0] = '\0';
	}
	
	if (sAuthID[0] == '\0')
	{
		return false;
	}
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod/users");
	if (!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod/users/%s", sAuthID);
	if (!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod/users/%s/saves", sAuthID);
	if (!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}
	
	return DirExists(sPath);
}

//Works out the client's land: the middle of its floor (what saved positions are measured from), half its width
//and depth, and its height. Returns false if the client has no land.
bool Cel_GetLandLayout(int iClient, float fMiddle[3], float fHalfSize[2], float &fHeight)
{
	float fBottom[3], fCorner[2][3], fTop[3];
	
	if (!Cel_IsLandCreated(iClient))
	{
		return false;
	}
	
	Cel_GetLandPositions(iClient, 1, fCorner[0]);
	Cel_GetLandPositions(iClient, 4, fCorner[1]);
	
	Cel_GetMiddleOfABox(fCorner[0], fCorner[1], fMiddle);
	
	fMiddle[2] = fCorner[0][2];
	
	Cel_GetLandPositions(iClient, 2, fBottom);
	Cel_GetLandPositions(iClient, 3, fTop);
	
	fHalfSize[0] = FloatAbs(fTop[0] - fBottom[0]) / 2.0;
	fHalfSize[1] = FloatAbs(fTop[1] - fBottom[1]) / 2.0;
	fHeight = FloatAbs(fTop[2] - fBottom[2]);
	
	return true;
}

//An entity belongs to a build when its origin is inside its owner's own land.
bool Cel_IsEntityInOwnLand(int iClient, int iEntity)
{
	float fHalfSize[2], fHeight, fMiddle[3], fOrigin[3];
	
	if (!Cel_GetLandLayout(iClient, fMiddle, fHalfSize, fHeight))
	{
		return false;
	}
	
	Cel_GetEntityOrigin(iEntity, fOrigin);
	
	return (FloatAbs(fOrigin[0] - fMiddle[0]) <= fHalfSize[0] && FloatAbs(fOrigin[1] - fMiddle[1]) <= fHalfSize[1]
		&& fOrigin[2] >= fMiddle[2] - 64.0 && fOrigin[2] <= fMiddle[2] + fHeight);
}

public Action Command_LoadBuild(int iClient, int iArgs)
{
	char sSaveName[64];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CMD_LoadBuild");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sSaveName, sizeof(sSaveName));
	
	Cel_LoadBuild(iClient, sSaveName);
	
	return Plugin_Handled;
}

public Action Command_SaveBuild(int iClient, int iArgs)
{
	char sSaveName[64];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CMD_SaveBuild");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sSaveName, sizeof(sSaveName));
	
	Cel_SaveBuild(iClient, sSaveName);
	
	return Plugin_Handled;
}

public int Native_LoadBuild(Handle hPlugin, int iNumParams)
{
	char sAuthID[64], sBuffer[3][PLATFORM_MAX_PATH], sFile[PLATFORM_MAX_PATH], sPropName[64], sRelPath[PLATFORM_MAX_PATH], sSaveName[96];
	float fEnt[2][3], fOrigin[3];
	
	int iClient = GetNativeCell(1), iProp = -1;
	
	GetNativeString(2, sSaveName, sizeof(sSaveName));
	
	if (g_bLoading[iClient])
	{
		Cel_ReplyToCommand(iClient, "Your last build is still loading. Wait a moment.");
		return false;
	}
	
	if (!Cel_PrepareSaveFolder(iClient, sAuthID, sizeof(sAuthID)))
	{
		Cel_ReplyToCommand(iClient, "Your builds cannot be reached right now: your Steam ID is not known to the server yet. Try again in a moment.");
		
		return false;
	}
	
	//Builds are placed around the middle of the player's own land, exactly as they were saved.
	float fHalfSize[2], fHeight, fNeeded[3];
	
	if (!Cel_GetLandLayout(iClient, g_fCrosshairOrigin[iClient], fHalfSize, fHeight))
	{
		Cel_ReplyToCommand(iClient, "You need a land to load a build into. Type {green}[tag]land{default} to create one.");
		
		return false;
	}
	
	Format(sRelPath, sizeof(sRelPath), "data/celmod/users/%s/saves/%s.txt", sAuthID, sSaveName);
	
	BuildPath(Path_SM, sFile, sizeof(sFile), sRelPath);
	
	KeyValues kvLoadBuild = new KeyValues("Vault");
	
	if(kvLoadBuild.ImportFromFile(sFile))
	{
		//First pass: how much room the build needs. Nothing is spawned unless all of it fits in the land.
		int iEntries = 0;
		
		if (kvLoadBuild.GotoFirstSubKey())
		{
			do
			{
				iEntries++;
				
				if (FloatAbs(kvLoadBuild.GetFloat("o1")) > fNeeded[0]) fNeeded[0] = FloatAbs(kvLoadBuild.GetFloat("o1"));
				if (FloatAbs(kvLoadBuild.GetFloat("o2")) > fNeeded[1]) fNeeded[1] = FloatAbs(kvLoadBuild.GetFloat("o2"));
				if (kvLoadBuild.GetFloat("o3") > fNeeded[2]) fNeeded[2] = kvLoadBuild.GetFloat("o3");
			}
			while (kvLoadBuild.GotoNextKey());
			
			kvLoadBuild.Rewind();
		}
		
		if (fNeeded[0] > fHalfSize[0] + 1.0 || fNeeded[1] > fHalfSize[1] + 1.0 || fNeeded[2] > fHeight + 1.0)
		{
			kvLoadBuild.Close();
			
			Cel_ReplyToCommand(iClient, "The build {green}%s{default} does not fit in your land. It needs {green}%d x %d{default} units and {green}%d{default} high; your land is {green}%d x %d{default} and {green}%d{default} high.", sSaveName, RoundToCeil(fNeeded[0] * 2.0), RoundToCeil(fNeeded[1] * 2.0), RoundToCeil(fNeeded[2]), RoundToFloor(fHalfSize[0] * 2.0), RoundToFloor(fHalfSize[1] * 2.0), RoundToFloor(fHeight));
			
			return false;
		}
		
		//A build is spawned all at once, so it has to fit in the player's limits, and in what is left of the
		//server's entity slots: running out of those crashes the whole server.
		Cel_RecountClientEntities(iClient);
		
		ConVar cvItems = FindConVar("cm_max_items");
		int iRoom = (Cel_GetPropLimit() - Cel_GetPropCount(iClient)) + (Cel_GetCelLimit() - Cel_GetCelCount(iClient))
			+ (cvItems != null ? cvItems.IntValue - Cel_GetItemCount(iClient) : 0);
		
		if (iEntries > iRoom)
		{
			kvLoadBuild.Close();
			
			Cel_ReplyToCommand(iClient, "The build {green}%s{default} has {green}%d{default} entities, but you only have room for {green}%d{default} more. Delete some first.", sSaveName, iEntries, iRoom < 0 ? 0 : iRoom);
			
			return false;
		}
		
		if (GetEntityCount() + iEntries * 2 > GetMaxEntities() - Cel_EdictReserve())
		{
			kvLoadBuild.Close();
			
			Cel_ReplyToCommand(iClient, "The server is too full of entities to load {green}%s{default} ({green}%d{default} entities) right now.", sSaveName, iEntries);
			
			return false;
		}
		
		//Spawned a few at a time, every server frame (at most cm_load_per_frame, and only for cm_load_frame_ms), so
		//a big build doesn't freeze the server for everyone. The build's own message and links come once it's all in.
		if (!kvLoadBuild.GotoFirstSubKey())
		{
			kvLoadBuild.Close();
			
			Cel_ReplyToCommand(iClient, "%t", "LoadedBuild", sSaveName);
			return true;
		}
		
		g_bLoading[iClient] = true;
		g_iLockedSkipped[iClient] = 0;
		
		DataPack dpLoad = new DataPack();
		
		dpLoad.WriteCell(GetClientUserId(iClient));
		dpLoad.WriteCell(kvLoadBuild);
		dpLoad.WriteString(sSaveName);
		
		RequestFrame(Frame_LoadBatch, dpLoad);
		
		Cel_ReplyToCommand(iClient, "Loading {green}%s{default} ({green}%d{default} entities)...", sSaveName, iEntries);
		
		return true;
	}else{
		kvLoadBuild.Close();
		
		Cel_ReplyToCommand(iClient, "%t", "SaveDoesntExist", sSaveName);
		
		return false;
	}
}

//One saved entity of a build: spawned and set up as it was saved.
void LoadBuildEntry(int iClient, KeyValues kvLoadBuild)
{
	char sBuffer[3][PLATFORM_MAX_PATH], sPropName[64];
	float fEnt[2][3], fOrigin[3];
	int iProp = -1;
	
	fEnt[0][0] = kvLoadBuild.GetFloat("a1");
	fEnt[0][1] = kvLoadBuild.GetFloat("a2");
	fEnt[0][2] = kvLoadBuild.GetFloat("a3");
	
	fEnt[1][0] = kvLoadBuild.GetFloat("o1");
	fEnt[1][1] = kvLoadBuild.GetFloat("o2");
	fEnt[1][2] = kvLoadBuild.GetFloat("o3");
	
	fOrigin[0] = fEnt[1][0] + g_fCrosshairOrigin[iClient][0];
	fOrigin[1] = fEnt[1][1] + g_fCrosshairOrigin[iClient][1];
	fOrigin[2] = fEnt[1][2] + g_fCrosshairOrigin[iClient][2];
	
	kvLoadBuild.GetString("classname", sBuffer[0], sizeof(sBuffer[]));
	kvLoadBuild.GetString("targetname", sBuffer[1], sizeof(sBuffer[]));
	kvLoadBuild.GetString("model", sBuffer[2], sizeof(sBuffer[]));
	
	EntityType etType = view_as<EntityType>(kvLoadBuild.GetNum("entitytype"));
	
	//A shop prop the player hasn't bought is left out (a build bought on the build market can hold some).
	kvLoadBuild.GetString("propname", sPropName, sizeof(sPropName));
	
	if (sPropName[0] != '\0')
	{
		char sSpawn[PLATFORM_MAX_PATH];
		
		if (Cel_CheckShopProp(iClient, sPropName, sSpawn, sizeof(sSpawn)) == -1)
		{
			g_iLockedSkipped[iClient]++;
			return;
		}
	}
	
	//Entity types that cannot be loaded are skipped instead of re-using the previous entity.
	iProp = -1;
	
	switch(etType)
	{
		case ENTTYPE_CYCLER:
		{
			kvLoadBuild.GetString("propname", sPropName, sizeof(sPropName));
			
			iProp = Cel_SpawnProp(iClient, sPropName, "cycler", sBuffer[2], fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
			
			if (iProp != -1)
			{
				Cel_SetCyclerAnim(iProp, kvLoadBuild.GetNum("animsequence"), kvLoadBuild.GetFloat("animcycle"), kvLoadBuild.GetNum("animpaused") == 1);
			}
		}
		case ENTTYPE_DOOR:
		{
			iProp = Cel_SpawnDoor(iClient, 1, fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
		}
		case ENTTYPE_DYNAMIC:
		{
			kvLoadBuild.GetString("propname", sPropName, sizeof(sPropName));
			
			iProp = Cel_SpawnProp(iClient, sPropName, "prop_physics_override", sBuffer[2], fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
		}
		case ENTTYPE_EFFECT:
		{
			iProp = Cel_SpawnEffect(iClient, fOrigin, view_as<EffectType>(kvLoadBuild.GetNum("effecttype")), view_as<bool>(kvLoadBuild.GetNum("effectenabled")), kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
		}
		case ENTTYPE_INTERNET:
		{
			char sURL[PLATFORM_MAX_PATH];
			
			kvLoadBuild.GetString("interneturl", sURL, sizeof(sURL));
			
			iProp = Cel_SpawnInternet(iClient, sURL, fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
		}
		case ENTTYPE_LADDER:
		{
			iProp = Cel_SpawnLadder(iClient, sBuffer[2], fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
		}
		case ENTTYPE_LIGHT:
		{
			iProp = Cel_SpawnLight(iClient, fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
		}
		case ENTTYPE_PHYSICS:
		{
			kvLoadBuild.GetString("propname", sPropName, sizeof(sPropName));
			
			iProp = Cel_SpawnProp(iClient, sPropName, "prop_physics_override", sBuffer[2], fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
			
			Cel_SetBreakable(iProp, view_as<bool>(kvLoadBuild.GetNum("breakable")));
		}
		case ENTTYPE_AMMO:
		{
			iProp = Cel_SpawnAmmoBit(iClient, view_as<AmmoBitType>(kvLoadBuild.GetNum("ammobittype")), fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
		}
		case ENTTYPE_AMMOCRATE:
		{
			iProp = Cel_SpawnAmmoCrate(iClient, view_as<AmmoCrateType>(kvLoadBuild.GetNum("ammocratetype")), fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
		}
		case ENTTYPE_CHARGER:
		{
			iProp = Cel_SpawnCharger(iClient, view_as<ChargerType>(kvLoadBuild.GetNum("chargertype")), fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
		}
		case ENTTYPE_WEAPONSPWNER:
		{
			iProp = Cel_SpawnWeaponBit(iClient, view_as<WeaponBitType>(kvLoadBuild.GetNum("weaponbittype")), fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
		}
		case ENTTYPE_TRIGGER:
		{
			iProp = Cel_SpawnButton(iClient, fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"), sBuffer[2]);
		}
		case ENTTYPE_EMBLEM, ENTTYPE_HAT, ENTTYPE_CELWEP:
		{
			char sItemId[64];
			
			kvLoadBuild.GetString("itemid", sItemId, sizeof(sItemId));
			
			//Returns -1 when the player no longer owns the item, or it is already spawned.
			iProp = Cel_SpawnCollectible(iClient, etType == ENTTYPE_EMBLEM ? "emblem" : (etType == ENTTYPE_HAT ? "hat" : "weapon"), sItemId, fEnt[0], fOrigin);
		}
		case ENTTYPE_UNKNOWN:
		{
			kvLoadBuild.GetString("propname", sPropName, sizeof(sPropName));
			
			iProp = Cel_SpawnProp(iClient, sPropName, "prop_physics_override", sBuffer[2], fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
		}
	}
	
	if (iProp == -1 || !IsValidEntity(iProp))
	{
		return;
	}
	
	Entity_SetName(iProp, sBuffer[1]);
	Cel_SetEntity(iProp, true);
	Entity_SetSpawnFlags(iProp, kvLoadBuild.GetNum("spawnflags"));
	Entity_SetSkin(iProp, kvLoadBuild.GetNum("skin"));
	Cel_FixDefaultSkin(iProp);
	Cel_SetMotion(iProp, view_as<bool>(kvLoadBuild.GetNum("motion")));
	Cel_SetSolid(iProp, view_as<bool>(kvLoadBuild.GetNum("solid")));
	
	if (kvLoadBuild.GetNum("perm", 0) == 1)
	{
		Cel_SetPerm(iProp, true);
	}
	Cel_SetRenderFX(iProp, view_as<RenderFx>(kvLoadBuild.GetNum("renderfx")));
	Cel_SetOwner(iClient, iProp);
	
	Cel_SetColorFade(iProp, view_as<bool>(kvLoadBuild.GetNum("colorfading")), kvLoadBuild.GetNum("fc1-1"), kvLoadBuild.GetNum("fc1-2"), kvLoadBuild.GetNum("fc1-3"), kvLoadBuild.GetNum("fc2-1"), kvLoadBuild.GetNum("fc2-2"), kvLoadBuild.GetNum("fc2-3"));
	Cel_SetRainbow(iProp, view_as<bool>(kvLoadBuild.GetNum("colorrainbow")));
	
	//Other plugins restore what they stored with this entity (teleports, messages, sounds, links, welds).
	Call_StartForward(g_hOnLoadEntity);
	
	Call_PushCell(iClient);
	Call_PushCell(iProp);
	Call_PushCell(kvLoadBuild);
	
	Call_Finish();
}

public void Frame_LoadBatch(DataPack dpLoad)
{
	char sSaveName[96];
	
	dpLoad.Reset();
	
	int iClient = GetClientOfUserId(dpLoad.ReadCell());
	KeyValues kvLoadBuild = view_as<KeyValues>(dpLoad.ReadCell());
	dpLoad.ReadString(sSaveName, sizeof(sSaveName));
	
	//The player left: the rest isn't loaded.
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		delete kvLoadBuild;
		delete dpLoad;
		return;
	}
	
	float fStart = GetEngineTime(), fBudget = g_cvLoadBudget.FloatValue / 1000.0;
	
	for (int n = 0; n < g_cvLoadBatch.IntValue; n++)
	{
		LoadBuildEntry(iClient, kvLoadBuild);
		
		if (!kvLoadBuild.GotoNextKey())
		{
			delete kvLoadBuild;
			delete dpLoad;
			
			g_bLoading[iClient] = false;
			
			Cel_ReplyToCommand(iClient, "%t", "LoadedBuild", sSaveName);
			
			if (g_iLockedSkipped[iClient] > 0)
			{
				Cel_PrintToChat(iClient, "{green}%d{default} shop prop%s in this build %s left out: you don't own %s. Buy %s in the shop to load %s.", g_iLockedSkipped[iClient], g_iLockedSkipped[iClient] == 1 ? "" : "s", g_iLockedSkipped[iClient] == 1 ? "was" : "were", g_iLockedSkipped[iClient] == 1 ? "it" : "them", g_iLockedSkipped[iClient] == 1 ? "it" : "them", g_iLockedSkipped[iClient] == 1 ? "it" : "them");
			}
			
			Call_StartForward(g_hOnBuildLoaded);
			Call_PushCell(iClient);
			Call_PushString(sSaveName);
			Call_Finish();
			
			return;
		}
		
		if (GetEngineTime() - fStart >= fBudget)
		{
			break;
		}
	}
	
	RequestFrame(Frame_LoadBatch, dpLoad);
}

//Natives:
public int Native_SaveBuild(Handle hPlugin, int iNumParams)
{
	bool bPropOutside = false;
	char sAuthID[64], sBuffer[3][PLATFORM_MAX_PATH], sFile[2][PLATFORM_MAX_PATH], sPropName[64], sRelPath[PLATFORM_MAX_PATH], sSaveName[96], sCount[32];
	float fEnt[2][3], fLandPos[2][3], fMiddle[3], fOrigin[3];
	int iClient = GetNativeCell(1), iColor[4], iCount = 0, iFadeColor[2][3], iLand;
	
	GetNativeString(2, sSaveName, sizeof(sSaveName));
	
	Cel_GetLandPositions(iClient, 1, fLandPos[0]);
	Cel_GetLandPositions(iClient, 4, fLandPos[1]);
	
	if(fLandPos[0][0] == 0.0 && fLandPos[0][1] == 0.0 && fLandPos[0][2] == 0.0 && fLandPos[1][0] == 0.0 && fLandPos[1][1] == 0.0 && fLandPos[1][2] == 0.0)
	{
		Cel_ReplyToCommand(iClient, "%t", "PropsWontSave");
		Cel_ReplyToCommand(iClient, "%t", "SetUpLandArea");
		
		return false;
	}
	
	if (!Cel_PrepareSaveFolder(iClient, sAuthID, sizeof(sAuthID)))
	{
		Cel_ReplyToCommand(iClient, "Your build cannot be saved right now: your Steam ID is not known to the server yet. Try again in a moment.");
		
		return false;
	}
	
	Format(sRelPath, sizeof(sRelPath), "data/celmod/users/%s/saves/%s.txt", sAuthID, sSaveName);
	
	BuildPath(Path_SM, sFile[0], sizeof(sFile[]), sRelPath);
	
	if (FileExists(sFile[0]))
	{
		switch(g_iSaveOverride[iClient])
		{
			case 0:
			{
				Cel_ReplyToCommand(iClient, "%t", "SaveOverriteWarning", sSaveName);
				Cel_ReplyToCommand(iClient, "%t", "SaveOverriteConfirm", sSaveName);
				
				g_iSaveOverride[iClient] = 1;
				
				return false;
			}
			
			case 1:
			{
				DeleteFile(sFile[0]);
				
				BuildPath(Path_SM, sFile[0], sizeof(sFile[]), sRelPath);
				
				g_iSaveOverride[iClient] = 0;
			}
		}
	}
	
	Cel_GetMiddleOfABox(fLandPos[0], fLandPos[1], fMiddle);
	
	fMiddle[2] = (fLandPos[0][2]);
	
	KeyValues kvSaveBuild = new KeyValues("Vault");
	
	kvSaveBuild.ImportFromFile(sFile[0]);
	
	for (int i = 0; i < GetMaxEntities(); i++)
	{
		//The land owner's own entities and their build team's, as long as they are in the owner's land.
		if (i > MaxClients && IsValidEntity(i) && Cel_IsEntity(i) && (Cel_GetOwner(i) == iClient || Cel_IsOnBuildTeam(iClient, Cel_GetOwner(i))))
		{
			if(Cel_IsEntityInOwnLand(iClient, i))
			{
				iLand = iClient;
				
				if(iLand == iClient)
				{
					iCount++;
					
					IntToString(iCount, sCount, sizeof(sCount));
					
					Entity_GetRenderColor(i, iColor);
					Cel_GetFadeColor(i, iFadeColor[0], iFadeColor[1]);
					
					Entity_GetClassName(i, sBuffer[0], sizeof(sBuffer[]));
					Entity_GetName(i, sBuffer[1], sizeof(sBuffer[]));
					Entity_GetModel(i, sBuffer[2], sizeof(sBuffer[]));
					
					Cel_GetEntityAngles(i, fEnt[0]);
					
					Cel_GetEntityOrigin(i, fEnt[1]);
					
					fOrigin[0] = fEnt[1][0] - fMiddle[0];
					fOrigin[1] = fEnt[1][1] - fMiddle[1];
					fOrigin[2] = fEnt[1][2] - fMiddle[2];
					
					kvSaveBuild.JumpToKey(sCount, true);
					
					kvSaveBuild.SetNum("entitytype", view_as<int>(Cel_GetEntityType(i)));
					
					kvSaveBuild.SetString("classname", sBuffer[0]);
					kvSaveBuild.SetString("targetname", sBuffer[1]);
					kvSaveBuild.SetString("model", sBuffer[2]);
					
					kvSaveBuild.SetNum("spawnflags", Entity_GetSpawnFlags(i));
					kvSaveBuild.SetNum("skin", Entity_GetSkin(i));
					kvSaveBuild.SetNum("motion", view_as<int>(Cel_GetMotion(i)));
					kvSaveBuild.SetNum("renderfx", view_as<int>(Cel_GetRenderFX(i)));
					kvSaveBuild.SetNum("solid", view_as<int>(Cel_IsSolid(i)));
					kvSaveBuild.SetNum("perm", view_as<int>(Cel_IsPerm(i)));
					
					kvSaveBuild.SetNum("c1", iColor[0]);
					kvSaveBuild.SetNum("c2", iColor[1]);
					kvSaveBuild.SetNum("c3", iColor[2]);
					kvSaveBuild.SetNum("c4", iColor[3]);
					
					kvSaveBuild.SetFloat("a1", fEnt[0][0]);
					kvSaveBuild.SetFloat("a2", fEnt[0][1]);
					kvSaveBuild.SetFloat("a3", fEnt[0][2]);
					
					kvSaveBuild.SetFloat("o1", fOrigin[0]);
					kvSaveBuild.SetFloat("o2", fOrigin[1]);
					kvSaveBuild.SetFloat("o3", fOrigin[2]);
					
					kvSaveBuild.SetNum("fc1-1", iFadeColor[0][0]);
					kvSaveBuild.SetNum("fc1-2", iFadeColor[0][1]);
					kvSaveBuild.SetNum("fc1-3", iFadeColor[0][2]);
					kvSaveBuild.SetNum("fc2-1", iFadeColor[1][0]);
					kvSaveBuild.SetNum("fc2-2", iFadeColor[1][1]);
					kvSaveBuild.SetNum("fc2-3", iFadeColor[1][2]);
					
					kvSaveBuild.SetNum("colorfading", view_as<int>(Cel_IsFading(i)));
					kvSaveBuild.SetNum("colorrainbow", view_as<int>(Cel_IsRainbow(i)));
					
					switch(Cel_GetEntityType(i))
					{
						case ENTTYPE_CYCLER:
						{
							Cel_GetPropName(i, sPropName, sizeof(sPropName));
							
							kvSaveBuild.SetString("propname", sPropName);
							
							int iSequence;
							float fCycle;
							bool bPaused;
							
							Cel_GetCyclerAnim(i, iSequence, fCycle, bPaused);
							
							kvSaveBuild.SetNum("animsequence", iSequence);
							kvSaveBuild.SetFloat("animcycle", fCycle);
							kvSaveBuild.SetNum("animpaused", view_as<int>(bPaused));
						}
						case ENTTYPE_DOOR:
						{
							fOrigin[2] -= 54;
							
							kvSaveBuild.SetFloat("o3", fOrigin[2]);
						}
						case ENTTYPE_DYNAMIC:
						{
							Cel_GetPropName(i, sPropName, sizeof(sPropName));
							
							kvSaveBuild.SetString("propname", sPropName);
						}
						case ENTTYPE_EFFECT:
						{
							kvSaveBuild.SetNum("effecttype", view_as<int>(Cel_GetEffectType(i)));
							kvSaveBuild.SetNum("effectenabled", view_as<int>(Cel_IsEffectActive(i)));
						}
						case ENTTYPE_INTERNET:
						{
							char sURL[PLATFORM_MAX_PATH];
							
							Cel_GetInternetURL(i, sURL, sizeof(sURL));
							
							kvSaveBuild.SetString("interneturl", sURL);
						}
						case ENTTYPE_PHYSICS:
						{
							Cel_GetPropName(i, sPropName, sizeof(sPropName));
							
							kvSaveBuild.SetString("propname", sPropName);
							kvSaveBuild.SetNum("breakable", view_as<int>(Cel_IsBreakable(i)));
						}
						case ENTTYPE_AMMO:
						{
							fEnt[0][1] -= 90;
							
							kvSaveBuild.SetFloat("a2", fEnt[0][1]);
							
							kvSaveBuild.SetNum("ammobittype", Cel_GetAmmoType(i));
						}
						case ENTTYPE_AMMOCRATE:
						{
							fEnt[0][1] -= 180;
							
							kvSaveBuild.SetFloat("a2", fEnt[0][1]);
							
							kvSaveBuild.SetNum("ammocratetype", Cel_GetAmmoCrateType(i));
						}
						case ENTTYPE_CHARGER:
						{
							fEnt[0][1] -= 180;
							
							kvSaveBuild.SetFloat("a2", fEnt[0][1]);
							
							kvSaveBuild.SetNum("chargertype", Cel_GetChargerType(i));
						}
						case ENTTYPE_WEAPONSPWNER:
						{
							fEnt[0][1] -= 90;
							
							kvSaveBuild.SetFloat("a2", fEnt[0][1]);
							
							kvSaveBuild.SetNum("weaponbittype", Cel_GetWeaponType(i));
						}
						case ENTTYPE_EMBLEM, ENTTYPE_HAT, ENTTYPE_CELWEP:
						{
							char sItemId[64];
							
							Cel_GetCollectibleId(i, sItemId, sizeof(sItemId));
							
							kvSaveBuild.SetString("itemid", sItemId);
						}
					}
					
					//Other plugins add what they need to rebuild this entity.
					Call_StartForward(g_hOnSaveEntity);
					
					Call_PushCell(i);
					Call_PushCell(kvSaveBuild);
					
					Call_Finish();
					
					kvSaveBuild.Rewind();
				}
			}else{
				bPropOutside = true;
			}
		}
	}
	
	kvSaveBuild.Rewind();
	
	bool bWritten = kvSaveBuild.ExportToFile(sFile[0]);
	
	kvSaveBuild.Close();
	
	g_iSaveOverride[iClient] = 0;
	
	if (!bWritten)
	{
		LogError("|CelMod| Could not write the build file '%s'.", sFile[0]);
		
		Cel_ReplyToCommand(iClient, "Your build {green}%s{default} could not be written to disk. The server log has the details.", sSaveName);
		
		return false;
	}
	
	if (iCount == 0)
	{
		Cel_ReplyToCommand(iClient, "Nothing was saved: none of your entities are inside your land.");
	}
	
	if (bPropOutside)
	Cel_ReplyToCommand(iClient, "%t", "PropOutsideLand");
	
	Cel_ReplyToCommand(iClient, "%t", "SavedBuild", sSaveName);
	
	return true;
}

//!saves: your saved builds, newest first, with how many entities each holds and when it was saved. The first ten go to
//chat; all of them to the console when there are more.
public Action Command_ListSaves(int iClient, int iArgs)
{
	char sAuthID[64], sDir[PLATFORM_MAX_PATH], sEntry[PLATFORM_MAX_PATH], sFile[PLATFORM_MAX_PATH], sName[PLATFORM_MAX_PATH], sWhen[32];
	FileType ftType;

	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}

	if (!Cel_PrepareSaveFolder(iClient, sAuthID, sizeof(sAuthID)))
	{
		Cel_ReplyToCommand(iClient, "Your saves can't be found until Steam has confirmed who you are. Try again in a moment.");
		return Plugin_Handled;
	}

	BuildPath(Path_SM, sDir, sizeof(sDir), "data/celmod/users/%s/saves", sAuthID);

	DirectoryListing dlSaves = OpenDirectory(sDir);

	if (dlSaves == null)
	{
		Cel_ReplyToCommand(iClient, "You don't have any saved builds yet. Save your land with {green}[tag]save <name>{default}.");
		return Plugin_Handled;
	}

	// [time saved, entities] for each save, sorted newest first with the names alongside.
	ArrayList alSaves = new ArrayList(2);
	ArrayList alNames = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

	while (dlSaves.GetNext(sEntry, sizeof(sEntry), ftType))
	{
		int iLength = strlen(sEntry);

		if (ftType != FileType_File || iLength < 5 || !StrEqual(sEntry[iLength - 4], ".txt", false))
		{
			continue;
		}

		FormatEx(sFile, sizeof(sFile), "%s/%s", sDir, sEntry);

		// Each entity in a save is its own numbered section.
		int iEntities = 0;
		KeyValues kvSave = new KeyValues("Vault");

		if (kvSave.ImportFromFile(sFile) && kvSave.GotoFirstSubKey())
		{
			do
			{
				iEntities++;
			}
			while (kvSave.GotoNextKey());
		}

		delete kvSave;

		int iTime = GetFileTime(sFile, FileTime_LastChange);
		int iAt = 0;

		while (iAt < alSaves.Length && alSaves.Get(iAt, 0) >= iTime)
		{
			iAt++;
		}

		strcopy(sName, sizeof(sName), sEntry);
		sName[iLength - 4] = '\0';

		if (iAt >= alSaves.Length)
		{
			int iRow = alSaves.Push(iTime);

			alSaves.Set(iRow, iEntities, 1);
			alNames.PushString(sName);
		} else {
			alSaves.ShiftUp(iAt);
			alSaves.Set(iAt, iTime, 0);
			alSaves.Set(iAt, iEntities, 1);
			alNames.ShiftUp(iAt);
			alNames.SetString(iAt, sName);
		}
	}

	delete dlSaves;

	int iCount = alSaves.Length;

	if (iCount == 0)
	{
		Cel_ReplyToCommand(iClient, "You don't have any saved builds yet. Save your land with {green}[tag]save <name>{default}.");
	} else {
		Cel_ReplyToCommand(iClient, "Your saved builds ({green}%d{default}), newest first. Load one with {green}[tag]load <name>{default}:", iCount);

		for (int i = 0; i < iCount; i++)
		{
			alNames.GetString(i, sName, sizeof(sName));
			FormatTime(sWhen, sizeof(sWhen), "%m/%d/%Y", alSaves.Get(i, 0));

			int iEntities = alSaves.Get(i, 1);

			if (i < 10)
			{
				Cel_PrintToChat(iClient, "{green}%s{default} - %d entit%s, saved %s", sName, iEntities, iEntities == 1 ? "y" : "ies", sWhen);
			}

			PrintToConsole(iClient, "%-32s %5d entities   saved %s", sName, iEntities, sWhen);
		}

		if (iCount > 10)
		{
			Cel_PrintToChat(iClient, "...and {green}%d{default} more: the full list is in your console.", iCount - 10);
		}
	}

	delete alSaves;
	delete alNames;

	return Plugin_Handled;
}

public void OnClientDisconnect(int iClient)
{
	g_bLoading[iClient] = false;
}

//Build market:

//Only letters, digits, - and _ : a save name goes into a file path.
bool IsSafeSaveName(const char[] sName)
{
	int iLength = strlen(sName);
	
	if (iLength < 1 || iLength > 48)
	{
		return false;
	}
	
	for (int i = 0; i < iLength; i++)
	{
		if (!IsCharAlpha(sName[i]) && !IsCharNumeric(sName[i]) && sName[i] != '-' && sName[i] != '_')
		{
			return false;
		}
	}
	
	return true;
}

KeyValues OpenMarket()
{
	KeyValues kvMarket = new KeyValues("BuildMarket");
	
	kvMarket.ImportFromFile(g_sMarketFile);
	
	return kvMarket;
}

void SaveMarket(KeyValues kvMarket)
{
	kvMarket.Rewind();
	
	if (!kvMarket.ExportToFile(g_sMarketFile))
	{
		LogError("|CelMod| Could not save the build market to %s.", g_sMarketFile);
	}
}

//Counts the entities in a save file, and copies it to sTo (when given) without any emblems, hats or celweps:
//those belong to their owner and never come with a build.
int CopyBuild(const char[] sFrom, const char[] sTo, const char[] sBoughtFrom = "")
{
	KeyValues kvBuild = new KeyValues("Vault");
	
	if (!kvBuild.ImportFromFile(sFrom))
	{
		delete kvBuild;
		return -1;
	}
	
	int iEntities = 0;
	
	if (kvBuild.GotoFirstSubKey())
	{
		bool bMore = true;
		
		while (bMore)
		{
			EntityType etType = view_as<EntityType>(kvBuild.GetNum("entitytype"));
			
			if (etType == ENTTYPE_EMBLEM || etType == ENTTYPE_HAT || etType == ENTTYPE_CELWEP)
			{
				bMore = (kvBuild.DeleteThis() == 1);
			} else {
				iEntities++;
				bMore = kvBuild.GotoNextKey();
			}
		}
		
		kvBuild.Rewind();
	}
	
	if (sTo[0] != '\0')
	{
		//Marks a bought copy, so it can't be put straight back on the market by its buyer.
		if (sBoughtFrom[0] != '\0')
		{
			kvBuild.SetString("boughtfrom", sBoughtFrom);
		}
		
		if (!kvBuild.ExportToFile(sTo))
		{
			iEntities = -1;
		}
	}
	
	delete kvBuild;
	
	return iEntities;
}

public Action Command_SellBuild(int iClient, int iArgs)
{
	char sAuthID[64], sSave[64], sPrice[16], sFile[PLATFORM_MAX_PATH], sCopy[PLATFORM_MAX_PATH], sId[16], sSeller[64];
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 2)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]sellbuild{default} <save> <price>. Buyers get a copy; you keep your build and get paid every time someone buys it.");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sSave, sizeof(sSave));
	GetCmdArg(2, sPrice, sizeof(sPrice));
	
	int iPrice = StringToInt(sPrice);
	
	if (!IsSafeSaveName(sSave))
	{
		Cel_ReplyToCommand(iClient, "There is no save called {green}%s{default}. See your saves with {green}[tag]saves{default}.", sSave);
		return Plugin_Handled;
	}
	
	if (iPrice < 1 || iPrice > g_cvMarketMaxPrice.IntValue)
	{
		Cel_ReplyToCommand(iClient, "The price has to be between {green}1{default} and {green}%d CL{default}.", g_cvMarketMaxPrice.IntValue);
		return Plugin_Handled;
	}
	
	if (!Cel_PrepareSaveFolder(iClient, sAuthID, sizeof(sAuthID)))
	{
		Cel_ReplyToCommand(iClient, "Your saves can't be found until Steam has confirmed who you are. Try again in a moment.");
		return Plugin_Handled;
	}
	
	BuildPath(Path_SM, sFile, sizeof(sFile), "data/celmod/users/%s/saves/%s.txt", sAuthID, sSave);
	
	if (!FileExists(sFile))
	{
		Cel_ReplyToCommand(iClient, "There is no save called {green}%s{default}. See your saves with {green}[tag]saves{default}.", sSave);
		return Plugin_Handled;
	}
	
	KeyValues kvCheck = new KeyValues("Vault");
	
	kvCheck.ImportFromFile(sFile);
	kvCheck.GetString("boughtfrom", sSeller, sizeof(sSeller), "");
	
	delete kvCheck;
	
	if (sSeller[0] != '\0')
	{
		Cel_ReplyToCommand(iClient, "{green}%s{default} is a build you bought from {green}%s{default}: only builds you made can be sold.", sSave, sSeller);
		return Plugin_Handled;
	}
	
	KeyValues kvMarket = OpenMarket();
	
	//Already listed: the price is changed, and the listing gets a fresh copy of the save.
	int iMine = 0, iExisting = 0, iNext = kvMarket.GetNum("nextid", 1);
	
	if (kvMarket.JumpToKey("Listings") && kvMarket.GotoFirstSubKey())
	{
		do
		{
			kvMarket.GetString("seller", sSeller, sizeof(sSeller));
			
			if (StrEqual(sSeller, sAuthID))
			{
				iMine++;
				
				kvMarket.GetString("save", sCopy, sizeof(sCopy));
				
				if (StrEqual(sCopy, sSave, false))
				{
					kvMarket.GetSectionName(sId, sizeof(sId));
					iExisting = StringToInt(sId);
				}
			}
		}
		while (kvMarket.GotoNextKey());
	}
	
	kvMarket.Rewind();
	
	if (iExisting == 0 && iMine >= g_cvMarketMax.IntValue)
	{
		delete kvMarket;
		Cel_ReplyToCommand(iClient, "You already have {green}%d{default} builds on the market, the most you can. Take one off with {green}[tag]unsellbuild <save>{default}.", iMine);
		return Plugin_Handled;
	}
	
	int iId = iExisting != 0 ? iExisting : iNext;
	
	BuildPath(Path_SM, sCopy, sizeof(sCopy), "data/celmod/buildmarket/%d.txt", iId);
	
	int iEntities = CopyBuild(sFile, sCopy);
	
	if (iEntities < 1)
	{
		delete kvMarket;
		Cel_ReplyToCommand(iClient, iEntities == 0 ? "{green}%s{default} has nothing in it that can be sold (emblems, hats and celweps never come with a build)." : "{green}%s{default} could not be copied to the market. Try again later.", sSave);
		return Plugin_Handled;
	}
	
	if (iExisting == 0)
	{
		kvMarket.SetNum("nextid", iNext + 1);
	}
	
	IntToString(iId, sId, sizeof(sId));
	
	kvMarket.JumpToKey("Listings", true);
	kvMarket.JumpToKey(sId, true);
	
	GetClientName(iClient, sSeller, sizeof(sSeller));
	
	kvMarket.SetString("seller", sAuthID);
	kvMarket.SetString("sellername", sSeller);
	kvMarket.SetString("save", sSave);
	kvMarket.SetNum("price", iPrice);
	kvMarket.SetNum("entities", iEntities);
	
	if (iExisting == 0)
	{
		kvMarket.SetNum("listed", GetTime());
		kvMarket.SetNum("sold", 0);
	}
	
	SaveMarket(kvMarket);
	delete kvMarket;
	
	if (iExisting != 0)
	{
		Cel_ReplyToCommand(iClient, "Your build {green}%s{default} (listing {green}#%d{default}) is now {green}%d CL{default}, with its latest save.", sSave, iId, iPrice);
	} else {
		Cel_PrintToChatAll("{green}%N{default} put the build {green}%s{default} ({green}%d{default} entities) on the market for {green}%d CL{default}. Type {green}[tag]market{default} to see it.", iClient, sSave, iEntities, iPrice);
	}
	
	return Plugin_Handled;
}

//Finds a listing by its number, or by one of the client's own save names. Leaves kvMarket on it.
bool FindListing(KeyValues kvMarket, const char[] sWhat, const char[] sAuthID, char[] sId, int iIdLength)
{
	char sSave[64], sSeller[64];
	
	kvMarket.Rewind();
	
	if (!kvMarket.JumpToKey("Listings"))
	{
		return false;
	}
	
	char sNumber[16];
	strcopy(sNumber, sizeof(sNumber), sWhat);
	
	if (sNumber[0] == '#')
	{
		strcopy(sNumber, sizeof(sNumber), sWhat[1]);
	}
	
	if (StringToInt(sNumber) > 0 && kvMarket.JumpToKey(sNumber))
	{
		strcopy(sId, iIdLength, sNumber);
		return true;
	}
	
	if (sAuthID[0] != '\0' && kvMarket.GotoFirstSubKey())
	{
		do
		{
			kvMarket.GetString("seller", sSeller, sizeof(sSeller));
			kvMarket.GetString("save", sSave, sizeof(sSave));
			
			if (StrEqual(sSeller, sAuthID) && StrEqual(sSave, sWhat, false))
			{
				kvMarket.GetSectionName(sId, iIdLength);
				return true;
			}
		}
		while (kvMarket.GotoNextKey());
	}
	
	return false;
}

void RemoveListing(KeyValues kvMarket, const char[] sId)
{
	char sCopy[PLATFORM_MAX_PATH];
	
	kvMarket.Rewind();
	
	if (kvMarket.JumpToKey("Listings") && kvMarket.JumpToKey(sId))
	{
		kvMarket.DeleteThis();
	}
	
	BuildPath(Path_SM, sCopy, sizeof(sCopy), "data/celmod/buildmarket/%s.txt", sId);
	
	if (FileExists(sCopy))
	{
		DeleteFile(sCopy);
	}
	
	SaveMarket(kvMarket);
}

public Action Command_UnsellBuild(int iClient, int iArgs)
{
	char sAuthID[64], sWhat[64], sId[16], sSeller[64], sSave[64];
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]unsellbuild{default} <save or listing number>.");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sWhat, sizeof(sWhat));
	
	if (!Cel_PrepareSaveFolder(iClient, sAuthID, sizeof(sAuthID)))
	{
		Cel_ReplyToCommand(iClient, "Steam hasn't confirmed who you are yet. Try again in a moment.");
		return Plugin_Handled;
	}
	
	KeyValues kvMarket = OpenMarket();
	
	if (!FindListing(kvMarket, sWhat, sAuthID, sId, sizeof(sId)))
	{
		delete kvMarket;
		Cel_ReplyToCommand(iClient, "You don't have a build called {green}%s{default} on the market.", sWhat);
		return Plugin_Handled;
	}
	
	kvMarket.GetString("seller", sSeller, sizeof(sSeller));
	kvMarket.GetString("save", sSave, sizeof(sSave));
	
	if (!StrEqual(sSeller, sAuthID))
	{
		delete kvMarket;
		Cel_ReplyToCommand(iClient, "Listing {green}#%s{default} isn't yours.", sId);
		return Plugin_Handled;
	}
	
	RemoveListing(kvMarket, sId);
	delete kvMarket;
	
	Cel_ReplyToCommand(iClient, "{green}%s{default} is off the market. Everyone who bought it keeps their copy.", sSave);
	
	return Plugin_Handled;
}

public Action Command_DelListing(int iClient, int iArgs)
{
	char sWhat[16], sId[16], sSave[64], sSeller[64];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]delbuildlisting{default} <listing number>.");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sWhat, sizeof(sWhat));
	
	KeyValues kvMarket = OpenMarket();
	
	if (!FindListing(kvMarket, sWhat, "", sId, sizeof(sId)))
	{
		delete kvMarket;
		Cel_ReplyToCommand(iClient, "There is no listing {green}#%s{default}.", sWhat);
		return Plugin_Handled;
	}
	
	kvMarket.GetString("save", sSave, sizeof(sSave));
	kvMarket.GetString("sellername", sSeller, sizeof(sSeller));
	
	RemoveListing(kvMarket, sId);
	delete kvMarket;
	
	Cel_ReplyToCommand(iClient, "Removed listing {green}#%s{default} ({green}%s{default} by {green}%s{default}).", sId, sSave, sSeller);
	
	return Plugin_Handled;
}

public Action Command_BuildMarket(int iClient, int iArgs)
{
	char sId[16], sSave[64], sSeller[64], sLine[128];
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	KeyValues kvMarket = OpenMarket();
	
	Menu mMarket = new Menu(Menu_Market);
	
	mMarket.SetTitle("Build Market\nBuy a copy of another player's build.\nIt goes into your saves: !load it in your land.\n ");
	
	if (kvMarket.JumpToKey("Listings") && kvMarket.GotoFirstSubKey())
	{
		do
		{
			kvMarket.GetSectionName(sId, sizeof(sId));
			kvMarket.GetString("save", sSave, sizeof(sSave));
			kvMarket.GetString("sellername", sSeller, sizeof(sSeller));
			
			Format(sLine, sizeof(sLine), "#%s %s by %s - %d CL (%d entities, %d sold)", sId, sSave, sSeller, kvMarket.GetNum("price"), kvMarket.GetNum("entities"), kvMarket.GetNum("sold"));
			
			mMarket.AddItem(sId, sLine);
			PrintToConsole(iClient, "%s", sLine);
		}
		while (kvMarket.GotoNextKey());
	}
	
	delete kvMarket;
	
	if (mMarket.ItemCount == 0)
	{
		delete mMarket;
		Cel_ReplyToCommand(iClient, "Nobody is selling a build right now. Sell one of yours with {green}[tag]sellbuild <save> <price>{default}.");
		return Plugin_Handled;
	}
	
	mMarket.Display(iClient, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int Menu_Market(Menu mMenu, MenuAction maAction, int iClient, int iItem)
{
	if (maAction == MenuAction_Select)
	{
		char sId[16], sSave[64], sSeller[64], sLine[128];
		
		mMenu.GetItem(iItem, sId, sizeof(sId));
		
		KeyValues kvMarket = OpenMarket();
		
		if (!FindListing(kvMarket, sId, "", sId, sizeof(sId)))
		{
			delete kvMarket;
			Cel_PrintToChat(iClient, "That build is no longer on the market.");
			return 0;
		}
		
		kvMarket.GetString("save", sSave, sizeof(sSave));
		kvMarket.GetString("sellername", sSeller, sizeof(sSeller));
		
		Menu mConfirm = new Menu(Menu_MarketConfirm);
		
		mConfirm.SetTitle("%s by %s\n%d entities, sold %d time%s\nPrice: %d CL (you have %d CL)\n ", sSave, sSeller, kvMarket.GetNum("entities"), kvMarket.GetNum("sold"), kvMarket.GetNum("sold") == 1 ? "" : "s", kvMarket.GetNum("price"), Cel_GetClientBalance(iClient));
		
		Format(sLine, sizeof(sLine), "Buy it for %d CL", kvMarket.GetNum("price"));
		
		mConfirm.AddItem(sId, sLine);
		mConfirm.AddItem("", "Back to the market");
		
		delete kvMarket;
		
		mConfirm.Display(iClient, MENU_TIME_FOREVER);
	} else if (maAction == MenuAction_End) {
		delete mMenu;
	}
	
	return 0;
}

public int Menu_MarketConfirm(Menu mMenu, MenuAction maAction, int iClient, int iItem)
{
	if (maAction == MenuAction_Select)
	{
		char sId[16];
		
		mMenu.GetItem(iItem, sId, sizeof(sId));
		
		if (sId[0] == '\0')
		{
			FakeClientCommand(iClient, "v_buildmarket");
		} else {
			BuyBuild(iClient, sId);
		}
	} else if (maAction == MenuAction_End) {
		delete mMenu;
	}
	
	return 0;
}

public Action Command_BuyBuild(int iClient, int iArgs)
{
	char sId[16];
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]buybuild{default} <listing number>. See what's for sale with {green}[tag]market{default}.");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sId, sizeof(sId));
	
	BuyBuild(iClient, sId);
	
	return Plugin_Handled;
}

void BuyBuild(int iClient, const char[] sWhat)
{
	char sAuthID[64], sId[16], sSave[64], sSeller[64], sSellerName[64], sCopy[PLATFORM_MAX_PATH], sTo[PLATFORM_MAX_PATH], sName[64];
	
	if (!Cel_PrepareSaveFolder(iClient, sAuthID, sizeof(sAuthID)))
	{
		Cel_ReplyToCommand(iClient, "Steam hasn't confirmed who you are yet. Try again in a moment.");
		return;
	}
	
	KeyValues kvMarket = OpenMarket();
	
	if (!FindListing(kvMarket, sWhat, "", sId, sizeof(sId)))
	{
		delete kvMarket;
		Cel_ReplyToCommand(iClient, "There is no listing {green}#%s{default} on the market. See what's for sale with {green}[tag]market{default}.", sWhat);
		return;
	}
	
	kvMarket.GetString("seller", sSeller, sizeof(sSeller));
	kvMarket.GetString("sellername", sSellerName, sizeof(sSellerName));
	kvMarket.GetString("save", sSave, sizeof(sSave));
	
	int iPrice = kvMarket.GetNum("price");
	
	if (StrEqual(sSeller, sAuthID))
	{
		delete kvMarket;
		Cel_ReplyToCommand(iClient, "That's your own build.");
		return;
	}
	
	if (kvMarket.JumpToKey("buyers") && kvMarket.GetNum(sAuthID, 0) == 1)
	{
		delete kvMarket;
		Cel_ReplyToCommand(iClient, "You already bought {green}%s{default}. It's in your saves.", sSave);
		return;
	}
	
	kvMarket.Rewind();
	FindListing(kvMarket, sId, "", sId, sizeof(sId));
	
	if (Cel_GetClientBalance(iClient) < iPrice)
	{
		delete kvMarket;
		Cel_ReplyToCommand(iClient, "{green}%s{default} costs {green}%d CL{default}; you have {green}%d CL{default}.", sSave, iPrice, Cel_GetClientBalance(iClient));
		return;
	}
	
	//Into the buyer's saves under the build's name, or name_2, name_3... if they already have a save called that.
	strcopy(sName, sizeof(sName), sSave);
	BuildPath(Path_SM, sTo, sizeof(sTo), "data/celmod/users/%s/saves/%s.txt", sAuthID, sName);
	
	for (int n = 2; FileExists(sTo) && n < 100; n++)
	{
		Format(sName, sizeof(sName), "%s_%d", sSave, n);
		BuildPath(Path_SM, sTo, sizeof(sTo), "data/celmod/users/%s/saves/%s.txt", sAuthID, sName);
	}
	
	BuildPath(Path_SM, sCopy, sizeof(sCopy), "data/celmod/buildmarket/%s.txt", sId);
	
	if (FileExists(sTo) || CopyBuild(sCopy, sTo, sSellerName) < 0)
	{
		delete kvMarket;
		Cel_ReplyToCommand(iClient, "The build couldn't be copied to your saves. Nothing was paid.");
		return;
	}
	
	Cel_SubFromClientBalance(iClient, iPrice);
	
	kvMarket.SetNum("sold", kvMarket.GetNum("sold") + 1);
	kvMarket.JumpToKey("buyers", true);
	kvMarket.SetNum(sAuthID, 1);
	
	//The seller's share, less the market's fee: paid now if they're here, or the next time they join.
	int iEarned = iPrice - (iPrice * g_cvMarketFee.IntValue) / 100;
	int iSeller = FindClientByAuth(sSeller);
	
	if (iSeller > 0)
	{
		Cel_AddToClientBalance(iSeller, iEarned);
		Cel_PrintToChat(iSeller, "{green}%N{default} bought your build {green}%s{default}. You got {green}%d CL{default}.", iClient, sSave, iEarned);
	} else if (iEarned > 0) {
		kvMarket.Rewind();
		kvMarket.JumpToKey("Earnings", true);
		kvMarket.SetNum(sSeller, kvMarket.GetNum(sSeller, 0) + iEarned);
	}
	
	SaveMarket(kvMarket);
	delete kvMarket;
	
	Cel_ReplyToCommand(iClient, "You bought {green}%s{default} by {green}%s{default} for {green}%d CL{default}. It's saved as {green}%s{default}: type {green}[tag]load %s{default} in your land.", sSave, sSellerName, iPrice, sName, sName);
}

int FindClientByAuth(const char[] sAuthID)
{
	char sOther[64];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			Cel_GetAuthID(i, sOther, sizeof(sOther));
			
			if (StrEqual(sOther, sAuthID))
			{
				return i;
			}
		}
	}
	
	return 0;
}

//Builds sold while the seller was away are paid once their balance has loaded.
public void OnClientPostAdminCheck(int iClient)
{
	if (!IsFakeClient(iClient))
	{
		CreateTimer(5.0, Timer_PayEarnings, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_PayEarnings(Handle hTimer, int iUserId)
{
	char sAuthID[64];
	int iClient = GetClientOfUserId(iUserId);
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Stop;
	}
	
	Cel_GetAuthID(iClient, sAuthID, sizeof(sAuthID));
	
	if (sAuthID[0] == '\0')
	{
		return Plugin_Stop;
	}
	
	KeyValues kvMarket = OpenMarket();
	
	if (kvMarket.JumpToKey("Earnings"))
	{
		int iEarned = kvMarket.GetNum(sAuthID, 0);
		
		if (iEarned > 0)
		{
			kvMarket.DeleteKey(sAuthID);
			SaveMarket(kvMarket);
			
			Cel_AddToClientBalance(iClient, iEarned);
			Cel_PrintToChat(iClient, "Your builds sold on the market while you were away: you got {green}%d CL{default}.", iEarned);
		}
	}
	
	delete kvMarket;
	
	return Plugin_Stop;
}

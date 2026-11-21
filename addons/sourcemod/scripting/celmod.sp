//|CelMod| by rockzehh.

#pragma semicolon 1

#include <celmod>
#include <geoip>
#undef REQUIRE_PLUGIN

#pragma newdecls required

bool g_bLate;
bool g_bIsFlying[MAXPLAYERS + 1];
bool g_bNoKill[MAXPLAYERS + 1];
bool g_bPlayer[MAXPLAYERS + 1];

char g_sAuthID[MAXPLAYERS + 1][64];
char g_sBlacklistDB[PLATFORM_MAX_PATH];
char g_sDownloadPath[PLATFORM_MAX_PATH];
char g_sOverlayPath[PLATFORM_MAX_PATH];
char g_sSpawnDB[PLATFORM_MAX_PATH];
char g_sShopDB[PLATFORM_MAX_PATH];

StringMap g_smShopProps;

ConVar g_cvCelLimit;
ConVar g_cvDownloadPath;
ConVar g_cvOverlayPath;
ConVar g_cvPropLimit;

Handle g_hOnPropSpawn;

int g_iBeam;
int g_iCelCount[MAXPLAYERS + 1];
int g_iCelLimit;
int g_iHalo;
int g_iPhys;
int g_iPropCount[MAXPLAYERS + 1];
int g_iPropLimit;
float g_fNextSpawnRefusal[MAXPLAYERS + 1];
int g_iItemCount[MAXPLAYERS + 1]; //bank items out in the world (their own limit, cm_max_items)
bool g_bBankItem[MAXENTITIES + 1];
ConVar g_cvItemLimit;

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	MarkNativeAsOptional("Cel_CheckShopDB");
	MarkNativeAsOptional("Cel_CheckClientPurchase");
	MarkNativeAsOptional("Cel_GetZoneType");
	MarkNativeAsOptional("Cel_IsZoneExempt");
	
	CreateNative("Cel_AddToBlacklist", Native_AddToBlacklist);
	CreateNative("Cel_AddToCelCount", Native_AddToCelCount);
	CreateNative("Cel_AddToPropCount", Native_AddToPropCount);
	CreateNative("Cel_ChangeBeam", Native_ChangeBeam);
	CreateNative("Cel_CheckBlacklistDB", Native_CheckBlacklistDB);
	CreateNative("Cel_CheckCelCount", Native_CheckCelCount);
	CreateNative("Cel_CheckPropCount", Native_CheckPropCount);
	CreateNative("Cel_CheckSpawnDB", Native_CheckSpawnDB);
	CreateNative("Cel_CheckShopProp", Native_CheckShopProp);
	CreateNative("Cel_RecountClientEntities", Native_RecountClientEntities);
	CreateNative("Cel_MarkBankItem", Native_MarkBankItem);
	CreateNative("Cel_IsBankItem", Native_IsBankItem);
	CreateNative("Cel_CheckItemCount", Native_CheckItemCount);
	CreateNative("Cel_GetItemCount", Native_GetItemCount);
	CreateNative("Cel_SubFromItemCount", Native_SubFromItemCount);
	CreateNative("Cel_AddToItemCount", Native_AddToItemCount);
	CreateNative("Cel_DownloadClientFiles", Native_DownloadClientFiles);
	CreateNative("Cel_GetAuthID", Native_GetAuthID);
	CreateNative("Cel_GetBeamMaterial", Native_GetBeamMaterial);
	CreateNative("Cel_GetCelCount", Native_GetCelCount);
	CreateNative("Cel_GetCelLimit", Native_GetCelLimit);
	CreateNative("Cel_GetClientAimTarget", Native_GetClientAimTarget);
	CreateNative("Cel_GetCombinedCount", Native_GetCombinedCount);
	CreateNative("Cel_GetCrosshairHitOrigin", Native_GetCrosshairHitOrigin);
	CreateNative("Cel_GetHaloMaterial", Native_GetHaloMaterial);
	CreateNative("Cel_GetNoKill", Native_GetNoKill);
	CreateNative("Cel_GetPhysicsMaterial", Native_GetPhysicsMaterial);
	CreateNative("Cel_GetPropCount", Native_GetPropCount);
	CreateNative("Cel_GetPropLimit", Native_GetPropLimit);
	CreateNative("Cel_IsPlayer", Native_IsPlayer);
	CreateNative("Cel_RemovalBeam", Native_RemovalBeam);
	CreateNative("Cel_RemoveFromBlacklist", Native_RemoveFromBlacklist);
	CreateNative("Cel_SetAuthID", Native_SetAuthID);
	CreateNative("Cel_SetCelCount", Native_SetCelCount);
	CreateNative("Cel_SetCelLimit", Native_SetCelLimit);
	CreateNative("Cel_SetNoKill", Native_SetNoKill);
	CreateNative("Cel_SetPlayer", Native_SetPlayer);
	CreateNative("Cel_SetPropCount", Native_SetPropCount);
	CreateNative("Cel_SetPropLimit", Native_SetPropLimit);
	CreateNative("Cel_SpawnProp", Native_SpawnProp);
	CreateNative("Cel_SubFromCelCount", Native_SubFromCelCount);
	CreateNative("Cel_SubFromPropCount", Native_SubFromPropCount);
	
	g_bLate = bLate;
	
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "|CelMod|",
	author = CEL_AUTHOR,
	description = "A fully customized building experience with extra features to enhance the standard gameplay.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	LoadTranslations("celmod.phrases");
	LoadTranslations("common.phrases");
	
	char sPath[PLATFORM_MAX_PATH];
	
	if (g_bLate)
	{
		for (int i = 1; i < MaxClients; i++)
		{
			if (IsClientAuthorized(i))
			{
				Cel_SetAuthID(i);
				
				OnClientPutInServer(i);
			}
		}
		
		OnMapStart();
	}
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod");
	if (!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod/users");
	if (!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}
	BuildPath(Path_SM, g_sSpawnDB, sizeof(g_sSpawnDB), "data/celmod/spawns.txt");
	if (!FileExists(g_sSpawnDB))
	{
		ThrowError("|CelMod| %t", "FileNotFound", g_sSpawnDB);
	}
	BuildPath(Path_SM, g_sBlacklistDB, sizeof(g_sBlacklistDB), "data/celmod/blacklist.txt");
	if (!FileExists(g_sBlacklistDB))
	{
		Cel_AddToBlacklist("traintrack01");
	}
	
	BuildPath(Path_SM, g_sShopDB, sizeof(g_sShopDB), "data/celmod/shop.txt");
	g_smShopProps = new StringMap();
	LoadShopProps();
	
	AddCommandListener(Handle_Spawn, "say");
	AddCommandListener(Handle_Spawn, "say_team");
	
	g_hOnPropSpawn = CreateGlobalForward("Cel_OnPropSpawn", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	
	HookEvent("player_connect", Event_Connect, EventHookMode_Pre);
	HookEvent("player_death", Event_Death, EventHookMode_Post);
	HookEvent("player_disconnect", Event_Disconnect, EventHookMode_Pre);
	HookEvent("player_spawn", Event_Spawn, EventHookMode_Post);
	
	RegConsoleCmd("dev_getpos", Dev_GetPos, "");
	
	RegAdminCmd("v_blacklist", Command_Blacklist, ADMFLAG_SLAY, "|CelMod| Adds/removes a prop from the spawn blacklist.");
	RegAdminCmd("v_setowner", Command_SetOwner, ADMFLAG_SLAY, "|CelMod| Sets the owner of the prop you are looking at.");
	
	RegConsoleCmd("v_axis", Command_Axis, "|CelMod| Creates a marker to the player showing every axis.");
	RegConsoleCmd("v_fly", Command_Fly, "|CelMod| Enables/disables noclip on the player.");
	RegConsoleCmd("v_mark", Command_Axis, "|CelMod| Creates a marker to the player showing every axis.");
	RegConsoleCmd("v_marker", Command_Axis, "|CelMod| Creates a marker to the player showing every axis.");
	RegConsoleCmd("v_nokill", Command_NoKill, "|CelMod| Enables/disables godmode on the player.");
	RegConsoleCmd("v_owner", Command_Owner, "|CelMod| Gets the owner of the entity you are looking at.");
	RegConsoleCmd("v_p", Command_Spawn, "|CelMod| Spawns a prop by name.");
	RegConsoleCmd("v_s", Command_Spawn, "|CelMod| Spawns a prop by name.");
	RegConsoleCmd("v_spawn", Command_Spawn, "|CelMod| Spawns a prop by name.");
	
	CreateConVar("celmod", "1", "Notifies the server that the plugin is running.");
	g_cvCelLimit = CreateConVar("cm_max_player_cels", "20", "Maxiumum number of cel entities a client is allowed.");
	g_cvDownloadPath = CreateConVar("cm_download_list_path", "data/celmod/downloads.txt", "Path for the download list for clients.");
	g_cvItemLimit = CreateConVar("cm_max_items", "50", "Maximum number of bank items (emblems, hats, celweps, shop props, hobos) a player can have out at once. They don't count toward the prop or cel limit.", _, true, 0.0);
	CreateConVar("cm_admin_shop_props", "0", "1: root admins can spawn any shop prop, any number of times (for displays). 0: admins need to own copies like everyone.", _, true, 0.0, true, 1.0);
	CreateConVar("cm_edict_reserve", "256", "Entity slots kept free for the game: players can't spawn or load anything once the server is this close to its 2048 entity limit (running out crashes the server).", _, true, 32.0, true, 1024.0);
	g_cvPropLimit = CreateConVar("cm_max_props", "200", "Maximum number of props a player is allowed to spawn (the server still keeps cm_edict_reserve entity slots free).");
	g_cvOverlayPath = CreateConVar("cm_overlay_material_path", "celmod/cm_overlay2.vmt", "Default CelMod overlay path.");
	CreateConVar("cm_version", CEL_VERSION, "The version of the plugin the server is running.");

	
	g_cvCelLimit.AddChangeHook(CM_OnConVarChanged);
	g_cvDownloadPath.AddChangeHook(CM_OnConVarChanged);
	g_cvOverlayPath.AddChangeHook(CM_OnConVarChanged);
	g_cvPropLimit.AddChangeHook(CM_OnConVarChanged);
	
	Cel_SetCelLimit(g_cvCelLimit.IntValue);
	g_cvDownloadPath.GetString(g_sDownloadPath, sizeof(g_sDownloadPath));
	g_cvOverlayPath.GetString(g_sOverlayPath, sizeof(g_sOverlayPath));
	Cel_SetPropLimit(g_cvPropLimit.IntValue);
	
	AutoExecConfig(true, "celmod.main");
	
	ConCommand_RemoveFlags("r_screenoverlay", FCVAR_CHEAT);
}

public void OnClientAuthorized(int iClient, const char[] sAuthID)
{
	char sClient[128], sCountry[45], sIP[64];
	
	GetClientIP(iClient, sIP, sizeof(sIP), true);
	GetClientName(iClient, sClient, sizeof(sClient));
	GeoipCountry(sIP, sCountry, sizeof(sCountry));
	
	Cel_SetAuthID(iClient);
	
	CPrintToChatAll("{green}[+]{default} %t", "Connecting", sClient, sCountry);
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			PrecacheSound("npc/metropolice/vo/on1.wav");
			
			EmitSoundToClient(i, "npc/metropolice/vo/on1.wav", i, 2, 100, 0, 1.0, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		}
	}
}

public void OnClientPutInServer(int iClient)
{
	char sAuthID[64], sPath[PLATFORM_MAX_PATH];
	
	Cel_ChooseHudColor(iClient);
	
	Cel_GetAuthID(iClient, sAuthID, sizeof(sAuthID));
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod/users/%s", sAuthID);
	if (!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}
	
	Cel_SetCelCount(iClient, 0);
	Cel_SetNoKill(iClient, false);
	Cel_SetPlayer(iClient, true);
	Cel_SetPropCount(iClient, 0);
	g_iItemCount[iClient] = 0;
	
	g_bIsFlying[iClient] = false;
	
	ClientCommand(iClient, "r_screenoverlay %s", g_sOverlayPath);
}

public void OnClientDisconnect(int iClient)
{
	char sClient[128];
	
	GetClientName(iClient, sClient, sizeof(sClient));
	
	//The next player in this slot gets their own id.
	g_sAuthID[iClient][0] = '\0';
	
	Cel_SetCelCount(iClient, 0);
	Cel_SetNoKill(iClient, false);
	Cel_SetPlayer(iClient, false);
	Cel_SetPropCount(iClient, 0);
	g_iItemCount[iClient] = 0;
	
	g_bIsFlying[iClient] = false;
	
	if (IsClientInGame(iClient) && !IsFakeClient(iClient))
	{
		ClientCommand(iClient, "r_screenoverlay 0");
	}
	
	CPrintToChatAll("{red}[-]{default} %t", "Disconnecting", sClient);
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			PrecacheSound("npc/metropolice/vo/off1.wav");
			
			EmitSoundToClient(i, "npc/metropolice/vo/off1.wav", i, 2, 100, 0, 1.0, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		}
	}
}

public void OnMapStart()
{
	g_iBeam = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt", true);
	g_iPhys = PrecacheModel("materials/sprites/physbeam.vmt", true);
	
	Cel_DownloadClientFiles();
	
	LoadShopProps();
}

/**
 * Rare and discontinued props from the "Props" section of shop.txt. Only players who bought one
 * (purchase "prop_<alias>") can spawn it; everyone else is told to get it from the shop.
 * Each entry may give its own "spawn" string ("classname|model") so retired props need no
 * entry in spawns.txt.
 */
void LoadShopProps()
{
	char sAlias[64], sSpawn[256];
	
	g_smShopProps.Clear();
	
	KeyValues kvShop = new KeyValues("Shop");
	
	if (kvShop.ImportFromFile(g_sShopDB) && kvShop.JumpToKey("Props") && kvShop.GotoFirstSubKey())
	{
		do
		{
			kvShop.GetSectionName(sAlias, sizeof(sAlias));
			kvShop.GetString("spawn", sSpawn, sizeof(sSpawn), "");
			StringToLower(sAlias);
			g_smShopProps.SetString(sAlias, sSpawn);
			
			//Custom models: players are sent the model and its materials, worked out from the model itself.
			char sParts[2][PLATFORM_MAX_PATH];
			
			if (ExplodeString(sSpawn, "|", sParts, 2, sizeof(sParts[])) == 2 && sParts[1][0] != '\0')
			{
				Cel_AddModelDownloads(sParts[1]);
			}
		} while (kvShop.GotoNextKey());
	}
	
	delete kvShop;
}

void StringToLower(char[] sText)
{
	for (int i = 0; sText[i] != '\0'; i++)
	{
		sText[i] = CharToLower(sText[i]);
	}
}

bool LookupSpawnDB(const char[] sAlias, char[] sSpawnString, int iMaxLength)
{
	KeyValues kvProps = new KeyValues("Props");
	
	kvProps.ImportFromFile(g_sSpawnDB);
	kvProps.JumpToKey("Models", false);
	kvProps.GetString(sAlias, sSpawnString, iMaxLength, "null");
	
	delete kvProps;
	
	return !StrEqual(sSpawnString, "null");
}

public void OnMapEnd()
{
	g_iBeam = -1;
	g_iHalo = -1;
	g_iPhys = -1;
}

public void CM_OnConVarChanged(ConVar cvConVar, const char[] sOldValue, const char[] sNewValue)
{
	if (cvConVar == g_cvCelLimit)
	{
		Cel_SetCelLimit(StringToInt(sNewValue));
		PrintToServer("|CelMod| Cel limit updated to %i.", StringToInt(sNewValue));
	} else if (cvConVar == g_cvDownloadPath)
	{
		g_cvDownloadPath.GetString(g_sDownloadPath, sizeof(g_sDownloadPath));
		PrintToServer("|CelMod| Download list path updated to %s.", sNewValue);
	} else if (cvConVar == g_cvOverlayPath)
	{
		g_cvOverlayPath.GetString(g_sOverlayPath, sizeof(g_sOverlayPath));
		PrintToServer("|CelMod| Default overlay material path updated to %s.", sNewValue);
	} else if (cvConVar == g_cvPropLimit) {
		Cel_SetPropLimit(StringToInt(sNewValue));
		PrintToServer("|CelMod| Prop limit updated to %i.", StringToInt(sNewValue));
	}
}

//Commands:
public Action Dev_GetPos(int iClient, int iArgs)
{
	float fAng[3], fPos[3];
	
	GetClientAbsAngles(iClient, fAng);
	GetClientAbsOrigin(iClient, fPos);
	
	PrintToChat(iClient, "ANG: %f.f %f.f %f.f POS: %f.f %f.f %f.f", fAng[0], fAng[1], fAng[2], fPos[0], fPos[1], fPos[2]);
	
	return Plugin_Handled;
}

public Action Command_Axis(int iClient, int iArgs)
{
	float fClientOrigin[4][3];
	
	GetClientAbsOrigin(iClient, fClientOrigin[0]);
	GetClientAbsOrigin(iClient, fClientOrigin[1]);
	GetClientAbsOrigin(iClient, fClientOrigin[2]);
	GetClientAbsOrigin(iClient, fClientOrigin[3]);
	
	fClientOrigin[1][0] += 50;
	fClientOrigin[2][1] += 50;
	fClientOrigin[3][2] += 50;
	
	TE_SetupBeamPoints(fClientOrigin[0], fClientOrigin[1], Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 60.0, 3.0, 3.0, 1, 0.0, g_iRed, 10); TE_SendToClient(iClient);
	TE_SetupBeamPoints(fClientOrigin[0], fClientOrigin[2], Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 60.0, 3.0, 3.0, 1, 0.0, g_iGreen, 10); TE_SendToClient(iClient);
	TE_SetupBeamPoints(fClientOrigin[0], fClientOrigin[3], Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 60.0, 3.0, 3.0, 1, 0.0, g_iBlue, 10); TE_SendToClient(iClient);
	
	Cel_ReplyToCommand(iClient, "%t", "CreateAxis");
	
	return Plugin_Handled;
}

public Action Command_Blacklist(int iClient, int iArgs)
{
	char sOption[64], sProp[64];
	
	if(iArgs < 2)
	{
		Cel_ReplyToCommand(iClient, "%t", "CMD_Blacklist");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sOption, sizeof(sOption));
	GetCmdArg(2, sProp, sizeof(sProp));
	
	if(StrEqual(sOption, "#add", false))
	{
		if(Cel_CheckBlacklistDB(sProp))
		{
			Cel_ReplyToCommand(iClient, "%t", "PropInBlacklist", sProp);
			return Plugin_Handled;
		}
		
		Cel_AddToBlacklist(sProp);
		
		Cel_ReplyToCommand(iClient, "%t", "AddToBlacklist", sProp);
		
		return Plugin_Handled;
	}else if(StrEqual(sOption, "#remove", false))
	{
		if(!Cel_CheckBlacklistDB(sProp))
		{
			Cel_ReplyToCommand(iClient, "%t", "PropNotInBlacklist", sProp);
			return Plugin_Handled;
		}
		
		Cel_RemoveFromBlacklist(sProp);
		
		Cel_ReplyToCommand(iClient, "%t", "RemoveFromBlacklist", sProp);
		
		return Plugin_Handled;
	}else{
		Cel_ReplyToCommand(iClient, "%t", "CMD_Blacklist");
		return Plugin_Handled;
	}
}

public Action Command_Fly(int iClient, int iArgs)
{
	if (iClient < 1 || !IsClientInGame(iClient) || !IsPlayerAlive(iClient))
	{
		return Plugin_Handled;
	}
	
	//Toggled from what the player is really doing: dying, an event area or a no-fly land can take them out of
	//noclip, and a remembered "flying" flag then needed !fly twice.
	g_bIsFlying[iClient] = (GetEntityMoveType(iClient) != MOVETYPE_NOCLIP);
	
	SetEntityMoveType(iClient, g_bIsFlying[iClient] ? MOVETYPE_NOCLIP : MOVETYPE_WALK);
	
	Cel_ReplyToCommand(iClient, "%t", "Flying", g_bIsFlying[iClient] ? "enabled" : "disabled");
	
	return Plugin_Handled;
}

public Action Command_NoKill(int iClient, int iArgs)
{
	Cel_SetNoKill(iClient, !Cel_GetNoKill(iClient));
	
	Cel_ReplyToCommand(iClient, "%t", "NoKill", Cel_GetNoKill(iClient) ? "on" : "off");
	
	return Plugin_Handled;
}

public Action Command_Owner(int iClient, int iArgs)
{
	if (Cel_GetClientAimTarget(iClient) == -1)
	{
		Cel_NotLooking(iClient);
		return Plugin_Handled;
	}
	
	int iProp = Cel_GetClientAimTarget(iClient);
	
	if(Cel_IsEntity(iProp))
	{
		if(Cel_CheckOwner(iClient, iProp))
		{
			Cel_ReplyToCommandEntity(iClient, iProp, "%t", "IsOwner");
		}else{
			Cel_ReplyToCommandEntity(iClient, iProp, "%t", "EntityOwner");
		}
	}
	
	return Plugin_Handled;
}

public Action Command_SetOwner(int iClient, int iArgs)
{
	char sNames[2][PLATFORM_MAX_PATH], sTarget[PLATFORM_MAX_PATH];
	
	if (Cel_GetClientAimTarget(iClient) == -1)
	{
		Cel_NotLooking(iClient);
		return Plugin_Handled;
	}
	
	int iProp = Cel_GetClientAimTarget(iClient);
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	GetClientName(iClient, sNames[0], sizeof(sNames[]));
	
	if (StrEqual(sTarget, ""))
	{
		Cel_SetOwner(iClient, iProp);
		
		Cel_ChangeBeam(iClient, iProp);
		
		Cel_ReplyToCommandEntity(iClient, iProp, "%t", "SetOwnerClient", sNames[0]);
		
		return Plugin_Handled;
	}
	
	int iTarget = FindTarget(iClient, sTarget, true, false);
	
	if (iTarget == -1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CantFindTarget");
		return Plugin_Handled;
	}
	
	GetClientName(iTarget, sNames[1], sizeof(sNames[]));
	
	Cel_SetOwner(iTarget, iProp);
	
	Cel_ChangeBeam(iClient, iProp);
	
	Cel_ReplyToCommandEntity(iClient, iProp, "%t", "SetOwnerClient", sNames[1]);
	Cel_ReplyToCommandEntity(iClient, iProp,  "%t", "SetOwnerTarget", sNames[0], sNames[1]);
	
	return Plugin_Handled;
}

public Action Command_Spawn(int iClient, int iArgs)
{
	char sAlias[64], sOption[64], sSpawnBuffer[2][128], sSpawnString[256];
	float fAngles[3], fOrigin[3];
	int iOption = 0;
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CMD_Spawn");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sAlias, sizeof(sAlias));
	GetCmdArg(2, sOption, sizeof(sOption));
	
	int iShopProp = Cel_CheckShopProp(iClient, sAlias, sSpawnString, sizeof(sSpawnString));
	
	//Shop props are bank items, with their own limit (checked when it spawns), not the prop limit.
	if (iShopProp != 1 && !StrEqual(sAlias, "hobo", false) && !Cel_CheckPropCount(iClient))
	{
		Cel_ReplyToCommand(iClient, "%t", "MaxPropLimit", Cel_GetPropCount(iClient));
		return Plugin_Handled;
	}
	
	if (iShopProp == -1)
	{
		Cel_ReplyToCommand(iClient, "{green}%s{default} is a shop prop. Buy it with {green}[tag]buy prop_%s{default} or in the web shop. Seasonal props are only sold in their season ({green}[tag]seasons{default}).", sAlias, sAlias);
		return Plugin_Handled;
	}
	
	if(iShopProp == 0 && Cel_CheckBlacklistDB(sAlias))
	{
		Cel_ReplyToCommand(iClient, "%t", "PropNotFound", sAlias);
		return Plugin_Handled;
	}
	
	if(StrEqual(sOption, "drop", false))
	{
		iOption = 1;
	}else if(StrEqual(sOption, "unfrozen", false))
	{
		iOption = 2;
	}else if(StrEqual(sOption, "nogod", false))
	{
		iOption = 3;
	}else if(StrEqual(sOption, "", false))
	{
		iOption = 0;
	}else{
		Cel_ReplyToCommand(iClient, "%t", "CMD_Spawn");
		return Plugin_Handled;
	}
	
	if (iShopProp == 1 || Cel_CheckSpawnDB(sAlias, sSpawnString, sizeof(sSpawnString)))
	{
		ExplodeString(sSpawnString, "|", sSpawnBuffer, 2, sizeof(sSpawnBuffer[]));
		
		GetClientAbsAngles(iClient, fAngles);
		Cel_GetCrosshairHitOrigin(iClient, fOrigin);
		
		int iProp = Cel_SpawnProp(iClient, sAlias, sSpawnBuffer[0], sSpawnBuffer[1], fAngles, fOrigin, 255, 255, 255, 255);
		
		//Refused (a limit, a full server, or a shop prop that is all out): the reason was already given.
		if (iProp == -1)
		{
			return Plugin_Handled;
		}
		
		Cel_FixSpawnPosition(iProp, fOrigin);
		
		switch(iOption)
		{
			case 1:
			{
				Cel_DropEntityToFloor(iProp);
			}
			case 2:
			{
				Cel_SetMotion(iProp, true);
			}
			case 3:
			{
				Cel_SetBreakable(iProp, true);
			}
		}
		
		Call_StartForward(g_hOnPropSpawn);
		
		Call_PushCell(iProp);
		Call_PushCell(iClient);
		Call_PushCell(Cel_GetEntityType(iProp));
		
		Call_Finish();
		
		Cel_ReplyToCommand(iClient, "%t", "SpawnProp", sAlias);
	} else {
		Cel_ReplyToCommand(iClient, "%t", "PropNotFound", sAlias);
		return Plugin_Handled;
	}
	
	return Plugin_Handled;
}

public Action Handle_Spawn(int iClient, char[] sCommand, int iArgs)
{
	char sOption[64], sPropAlias[64], sSpawnBuffer[2][128], sSpawnString[256];
	float fAngles[3], fOrigin[3];
	int iOption = 0;
	
	GetCmdArg(1, sPropAlias, sizeof(sPropAlias));
	
	bool bTyped = (sPropAlias[0] == '!' || sPropAlias[0] == '/');
	
	ReplaceString(sPropAlias, sizeof(sPropAlias), "!", "");
	ReplaceString(sPropAlias, sizeof(sPropAlias), "/", "");
	
	int iShopProp = Cel_CheckShopProp(iClient, sPropAlias, sSpawnString, sizeof(sSpawnString));
	
	if (iShopProp == -1)
	{
		// Only answer "!rareprop" or "/rareprop"; a plain word in chat is just chat.
		if (!bTyped)
		{
			return Plugin_Continue;
		}
		
		Cel_ReplyToCommand(iClient, "{green}%s{default} is a shop prop. Buy it with {green}[tag]buy prop_%s{default} or in the web shop. Seasonal props are only sold in their season ({green}[tag]seasons{default}).", sPropAlias, sPropAlias);
		return Plugin_Handled;
	}
	
	if (iShopProp == 1 || Cel_CheckSpawnDB(sPropAlias, sSpawnString, sizeof(sSpawnString)))
	{
		GetCmdArg(2, sOption, sizeof(sOption));
		
		if(StrEqual(sOption, "drop", false))
		{
			iOption = 1;
		}else if(StrEqual(sOption, "unfrozen", false))
		{
			iOption = 2;
		}else if(StrEqual(sOption, "nogod", false))
		{
			iOption = 3;
		}else if(StrEqual(sOption, "", false))
		{
			iOption = 0;
		}else{
			iOption = 0;
		}
		
		if (iShopProp != 1 && !Cel_CheckPropCount(iClient))
		{
			Cel_ReplyToCommand(iClient, "%t", "MaxPropLimit", Cel_GetPropCount(iClient));
			return Plugin_Handled;
		}
		
		if(iShopProp == 0 && Cel_CheckBlacklistDB(sPropAlias))
		{
			return Plugin_Continue;
		}
		
		ExplodeString(sSpawnString, "|", sSpawnBuffer, 2, sizeof(sSpawnBuffer[]));
		
		GetClientAbsAngles(iClient, fAngles);
		Cel_GetCrosshairHitOrigin(iClient, fOrigin);
		
		int iProp = Cel_SpawnProp(iClient, sPropAlias, sSpawnBuffer[0], sSpawnBuffer[1], fAngles, fOrigin, 255, 255, 255, 255);
		
		//Refused (a limit, a full server, or a shop prop that is all out): the reason was already given.
		if (iProp == -1)
		{
			return Plugin_Handled;
		}
		
		Cel_FixSpawnPosition(iProp, fOrigin);
		
		switch(iOption)
		{
			case 1:
			{
				Cel_DropEntityToFloor(iProp);
			}
			case 2:
			{
				Cel_SetMotion(iProp, true);
			}
			case 3:
			{
				Cel_SetBreakable(iProp, true);
			}
		}
		
		Call_StartForward(g_hOnPropSpawn);
		
		Call_PushCell(iProp);
		Call_PushCell(iClient);
		Call_PushCell(Cel_GetEntityType(iProp));
		
		Call_Finish();
		
		Cel_ReplyToCommand(iClient, "%t", "SpawnProp", sPropAlias);
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

//Events:
public Action Event_Connect(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	if (!bDontBroadcast)
	{
		char sClientName[33], sNetworkID[22], sAddress[32];
		
		eEvent.GetString("name", sClientName, sizeof(sClientName));
		eEvent.GetString("networkid", sNetworkID, sizeof(sNetworkID));
		eEvent.GetString("address", sAddress, sizeof(sAddress));
		
		Event eNewEvent = CreateEvent("player_connect", true);
		eNewEvent.SetString("name", sClientName);
		
		eNewEvent.SetInt("index", GetEventInt(eEvent, "index"));
		eNewEvent.SetInt("userid", GetEventInt(eEvent, "userid"));
		
		eNewEvent.SetString("networkid", sNetworkID);
		eNewEvent.SetString("address", sAddress);
		
		eNewEvent.Fire(true);
		
		return Plugin_Handled;
	}
	
	return Plugin_Handled;
}

public Action Event_Death(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(eEvent.GetInt("userid"));
	
	if(Cel_IsPlayer(iClient))
	{
		int iRagdoll = GetEntPropEnt(iClient, Prop_Send, "m_hRagdoll");
		
		if (iRagdoll > MaxClients && IsValidEntity(iRagdoll))
		{
			IgniteEntity(iRagdoll, 3.0);
			
			CreateTimer(2.0, Timer_DisRemove, EntIndexToEntRef(iRagdoll));
		}
	}
	
	return Plugin_Handled;
}

public Action Event_Disconnect(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	if (!bDontBroadcast)
	{
		char sClientName[33], sNetworkID[22], sReason[65];
		
		eEvent.GetString("name", sClientName, sizeof(sClientName));
		eEvent.GetString("networkid", sNetworkID, sizeof(sNetworkID));
		eEvent.GetString("reason", sReason, sizeof(sReason));
		
		Event eNewEvent = CreateEvent("player_disconnect", true);
		eNewEvent.SetInt("userid", GetEventInt(eEvent, "userid"));
		eNewEvent.SetString("reason", sReason);
		eNewEvent.SetString("name", sClientName);
		eNewEvent.SetString("networkid", sNetworkID);
		
		eNewEvent.Fire(true);
		
		return Plugin_Handled;
	}
	
	int iClient = GetClientOfUserId(eEvent.GetInt("userid"));
	
	for (int i = 0; i < GetMaxEntities(); i++)
	{
		if (Cel_CheckOwner(iClient, i) && IsValidEntity(i))
		{
			if (Cel_CheckEntityType(i, "effect"))
			{
				if (Cel_GetEffectAttachment(i) > MaxClients) Cel_SetRainbow(Cel_GetEffectAttachment(i), false);
				if (Cel_GetEffectAttachment(i) > MaxClients) Cel_SetColorFade(Cel_GetEffectAttachment(i), false, 0, 0, 0, 0, 0, 0);
				
				if (Cel_GetEffectAttachment(i) > MaxClients) AcceptEntityInput(Cel_GetEffectAttachment(i), "TurnOff");
				if (Cel_GetEffectAttachment(i) > MaxClients) AcceptEntityInput(Cel_GetEffectAttachment(i), "kill");
			}
			
			AcceptEntityInput(i, "kill");
		}
	}
	
	return Plugin_Handled;
}

public Action Event_Spawn(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(eEvent.GetInt("userid"));
	
	Cel_SetNoKill(iClient, view_as<bool>(Cel_GetNoKill(iClient)));
	
	return Plugin_Continue;
}

//Natives:
public int Native_AddToBlacklist(Handle hPlugin, int iNumParams)
{
	char sProp[64];
	
	GetNativeString(1, sProp, sizeof(sProp));
	
	KeyValues kvBlacklist = new KeyValues("Vault");
	
	kvBlacklist.ImportFromFile(g_sBlacklistDB);
	
	kvBlacklist.JumpToKey("Blacklist", true);
	
	kvBlacklist.SetString(sProp, "blacklist");
	
	kvBlacklist.Rewind();
	
	kvBlacklist.ExportToFile(g_sBlacklistDB);
	
	kvBlacklist.Close();
	
	return true;
}

public int Native_AddToCelCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	int iFinalCount = (g_iCelCount[iClient] += 1);
	
	Cel_SetCelCount(iClient, iFinalCount);
	
	return true;
}

public int Native_AddToPropCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	int iFinalCount = (g_iPropCount[iClient] += 1);
	
	Cel_SetPropCount(iClient, iFinalCount);
	
	return true;
}

public int Native_ChangeBeam(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	int iEntity = GetNativeCell(2);
	
	char sSound[96];
	
	float fClientOrigin[3], fHitOrigin[3];
	
	GetClientAbsOrigin(iClient, fClientOrigin);
	
	Cel_GetCrosshairHitOrigin(iClient, fHitOrigin);
	
	TE_SetupBeamPoints(fClientOrigin, fHitOrigin, Cel_GetPhysicsMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.25, 5.0, 5.0, 1, 0.0, g_iWhite, 10); TE_SendToAll();
	TE_SetupSparks(fHitOrigin, NULL_VECTOR, 2, 5); TE_SendToAll();
	
	Format(sSound, sizeof(sSound), "weapons/airboat/airboat_gun_lastshot%i.wav", GetRandomInt(1, 2));
	
	PrecacheSound(sSound);
	
	EmitSoundToAll(sSound, iEntity, 2, 100, 0, 1.0, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
	
	return true;
}

public int Native_CheckBlacklistDB(Handle hPlugin, int iNumParams)
{
	char sAlias[64], sSpawnString[128];
	
	GetNativeString(1, sAlias, sizeof(sAlias));
	
	KeyValues kvBlacklist = new KeyValues("Vault");
	
	kvBlacklist.ImportFromFile(g_sBlacklistDB);
	
	kvBlacklist.JumpToKey("Blacklist", false);
	
	kvBlacklist.GetString(sAlias, sSpawnString, sizeof(sSpawnString), "null");
	
	kvBlacklist.Rewind();
	
	delete kvBlacklist;
	
	return (StrEqual(sSpawnString, "null")) ? false : true;
}

//Counts the props and cels a player really has out and puts the counters right.
void RecountClientEntities(int iClient)
{
	if (iClient < 1 || iClient > MaxClients)
	{
		return;
	}
	
	int iProps = 0, iCels = 0, iItems = 0;
	
	for (int i = MaxClients + 1; i < GetMaxEntities(); i++)
	{
		if (!IsValidEntity(i) || !Cel_IsEntity(i) || Cel_GetOwner(i) != iClient)
		{
			continue;
		}
		
		if (g_bBankItem[i])
		{
			iItems++;
		} else if (Cel_CheckEntityCatagory(i, ENTCATAGORY_PROP))
		{
			iProps++;
		} else {
			iCels++;
		}
	}
	
	if (iProps != g_iPropCount[iClient] || iCels != g_iCelCount[iClient])
	{
		LogMessage("|CelMod| Entity count for %L corrected: props %d -> %d, cels %d -> %d.", iClient, g_iPropCount[iClient], iProps, g_iCelCount[iClient], iCels);
	}
	
	g_iPropCount[iClient] = iProps;
	g_iCelCount[iClient] = iCels;
	g_iItemCount[iClient] = iItems;
}

public int Native_RecountClientEntities(Handle hPlugin, int iNumParams)
{
	RecountClientEntities(GetNativeCell(1));
	
	return 0;
}

public int Native_CheckCelCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	if (Cel_EdictsLow(8))
	{
		NotifySpawnRefused(iClient, "The server is nearly out of entity slots, so nothing more can be spawned right now. Delete some props first.");
		return false;
	}
	
	//The count is kept by adding and subtracting, which can drift: it is checked against the real entities
	//before anyone is told they're at the limit.
	if (Cel_GetCelCount(iClient) >= Cel_GetCelLimit())
	{
		RecountClientEntities(iClient);
	}
	
	return (Cel_GetCelCount(iClient) >= Cel_GetCelLimit()) ? false : true;
}

public int Native_CheckPropCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	if (Cel_EdictsLow(8))
	{
		NotifySpawnRefused(iClient, "The server is nearly out of entity slots, so nothing more can be spawned right now. Delete some props first.");
		return false;
	}
	
	if (Cel_GetPropCount(iClient) >= Cel_GetPropLimit())
	{
		RecountClientEntities(iClient);
	}
	
	return (Cel_GetPropCount(iClient) >= Cel_GetPropLimit()) ? false : true;
}

public int Native_CheckSpawnDB(Handle hPlugin, int iNumParams)
{
	int iMaxLength = GetNativeCell(3);
	
	char sAlias[64], sSpawnString[128];
	
	GetNativeString(1, sAlias, sizeof(sAlias));
	
	KeyValues kvProps = new KeyValues("Props");
	
	kvProps.ImportFromFile(g_sSpawnDB);
	
	kvProps.JumpToKey("Models", false);
	
	kvProps.GetString(sAlias, sSpawnString, iMaxLength, "null");
	
	kvProps.Rewind();
	
	delete kvProps;
	
	SetNativeString(2, sSpawnString, iMaxLength);
	
	return (StrEqual(sSpawnString, "null")) ? false : true;
}

public int Native_CheckShopProp(Handle hPlugin, int iNumParams)
{
	char sAlias[64], sKey[80], sSpawn[256];
	int iClient = GetNativeCell(1), iMaxLength = GetNativeCell(4);
	
	GetNativeString(2, sAlias, sizeof(sAlias));
	ReplaceString(sAlias, sizeof(sAlias), "!", "");
	ReplaceString(sAlias, sizeof(sAlias), "/", "");
	StringToLower(sAlias);
	
	if (!g_smShopProps.GetString(sAlias, sSpawn, sizeof(sSpawn)))
	{
		return 0;
	}
	
	FormatEx(sKey, sizeof(sKey), "prop_%s", sAlias);
	
	// Root admins can always spawn them, e.g. to set up displays.
	if (!Cel_CheckClientPurchase(iClient, sKey) && !AdminShopPropsUnlimited(iClient))
	{
		return -1;
	}
	
	if (sSpawn[0] == '\0' && !LookupSpawnDB(sAlias, sSpawn, sizeof(sSpawn)))
	{
		return 0;
	}
	
	SetNativeString(3, sSpawn, iMaxLength);
	
	return 1;
}

public int Native_DownloadClientFiles(Handle hPlugin, int iNumParams)
{
	char sPath[PLATFORM_MAX_PATH];
	
	BuildPath(Path_SM, sPath, sizeof(sPath), g_sDownloadPath);
	
	if(!FileExists(sPath))
	{
		PrintToServer("|CelMod| Cannot download client files. (No download txt file exists at data/celmod/downloads.txt)");
	}else{
		File fDownloadFiles = OpenFile(sPath, "r");
		
		char sBuffer[256];
		int iAdded = 0, iMissing = 0;
		
		while (!fDownloadFiles.EndOfFile() && fDownloadFiles.ReadLine(sBuffer, sizeof(sBuffer)))
		{
			//Works whatever the file was saved with: Windows line endings (\r\n), spaces, and \ for folders, which
			//Linux doesn't understand (a file on a Linux server is never found with them, so it's never sent).
			TrimString(sBuffer);
			ReplaceString(sBuffer, sizeof(sBuffer), "\\", "/");
			
			if (sBuffer[0] == '\0' || (sBuffer[0] == '/' && sBuffer[1] == '/'))
			{
				continue;
			}
			
			if (FileExists(sBuffer))
			{
				AddFileToDownloadsTable(sBuffer);
				iAdded++;
				
				if(StrContains(sBuffer, ".mdl", false) != -1)
				{
					PrecacheModel(sBuffer, true);
				}
			} else {
				//Linux is case sensitive: a file named differently in upper/lower case counts as missing too.
				if (iMissing < 20)
				{
					LogMessage("|CelMod| Download list: '%s' isn't on the server, so players can't download it.", sBuffer);
				}
				
				iMissing++;
			}
		}
		
		fDownloadFiles.Close();
		
		PrintToServer("|CelMod| Download list: %d files sent to players%s", iAdded, iMissing > 0 ? " (some are missing on the server, see the SourceMod log)." : ".");
		
		if (iMissing > 20)
		{
			LogMessage("|CelMod| Download list: %d more files are missing.", iMissing - 20);
		}
	}
	
	return true;
}

public int Native_GetAuthID(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1), iMaxLength = GetNativeCell(3);
	
	//Not known at join yet (Steam answered late): asked again now.
	if (g_sAuthID[iClient][0] == '\0' && IsClientConnected(iClient) && IsClientAuthorized(iClient))
	{
		GetClientAuthId(iClient, AuthId_SteamID64, g_sAuthID[iClient], sizeof(g_sAuthID[]));
	}
	
	SetNativeString(2, g_sAuthID[iClient], iMaxLength);
	
	return true;
}

public int Native_GetBeamMaterial(Handle hPlugin, int iNumParams)
{
	return g_iBeam;
}

public int Native_GetCelCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_iCelCount[iClient];
}

public int Native_GetCelLimit(Handle hPlugin, int iNumParams)
{
	return g_iCelLimit;
}

public int Native_GetClientAimTarget(Handle hPlugin, int iNumParams)
{
	float fEyeAngles[3], fEyeOrigin[3], fHitPoint[3];
	int iClient = GetNativeCell(1), iTarget = -1;
	
	GetClientEyeAngles(iClient, fEyeAngles);
	GetClientEyePosition(iClient, fEyeOrigin);
	
	Handle hTraceRay = TR_TraceRayFilterEx(fEyeOrigin, fEyeAngles, (MASK_SHOT_HULL|MASK_SHOT), RayType_Infinite, Cel_FilterPlayer, iClient);
	
	if (TR_DidHit(hTraceRay))
	{
		iTarget = TR_GetEntityIndex(hTraceRay);
		
		if(iTarget == 0) iTarget = -1;
		
		if(iTarget == -1)
		{
			TR_GetEndPosition(fHitPoint, hTraceRay);
			
			TR_GetPointContents(fHitPoint, iTarget);
			
			TR_GetPlaneNormal(hTraceRay, fHitPoint);
			TR_GetPointContents(fHitPoint, iTarget);
		}
		
		CloseHandle(hTraceRay);
	}
	
	return (Cel_IsEntity(iTarget)) ? iTarget : -1;
}

public int Native_GetCombinedCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return (g_iPropCount[iClient] + g_iCelCount[iClient]);
}

public int Native_GetCrosshairHitOrigin(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	float fCrosshairOrigin[3], fEyeAngles[3], fEyeOrigin[3];
	
	GetClientEyeAngles(iClient, fEyeAngles);
	GetClientEyePosition(iClient, fEyeOrigin);
	
	Handle hTraceRay = TR_TraceRayFilterEx(fEyeOrigin, fEyeAngles, (MASK_SHOT_HULL|MASK_SHOT), RayType_Infinite, Cel_FilterPlayer, iClient);
	
	if (TR_DidHit(hTraceRay))
	{
		TR_GetEndPosition(fCrosshairOrigin, hTraceRay);
		
		CloseHandle(hTraceRay);
	}
	
	SetNativeArray(2, fCrosshairOrigin, 3);
	
	return true;
}

public int Native_GetHaloMaterial(Handle hPlugin, int iNumParams)
{
	return g_iHalo;
}

public int Native_GetNoKill(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_bNoKill[iClient];
}

public int Native_GetPhysicsMaterial(Handle hPlugin, int iNumParams)
{
	return g_iPhys;
}

public int Native_GetPropCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_iPropCount[iClient];
}

public int Native_GetPropLimit(Handle hPlugin, int iNumParams)
{
	return g_iPropLimit;
}

public int Native_IsPlayer(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_bPlayer[iClient];
}

public int Native_RemovalBeam(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	int iEntity = GetNativeCell(2);
	
	char sSound[96];
	
	float fClientOrigin[3], fEntityOrigin[3];
	
	GetClientAbsOrigin(iClient, fClientOrigin);
	
	Cel_GetEntityOrigin(iEntity, fEntityOrigin);
	
	TE_SetupBeamPoints(fClientOrigin, fEntityOrigin, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.25, 5.0, 5.0, 1, 0.0, g_iGray, 10); TE_SendToAll();
	
	TE_SetupBeamRingPoint(fEntityOrigin, 0.0, 15.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.5, 5.0, 0.0, g_iGray, 10, 0); TE_SendToAll();
	
	Format(sSound, sizeof(sSound), "ambient/levels/citadel/weapon_disintegrate%i.wav", GetRandomInt(1, 4));
	
	PrecacheSound(sSound);
	
	EmitAmbientSound(sSound, fEntityOrigin, iEntity, 100, 0, 1.0, 100, 0.0);
	
	return true;
}

public int Native_RemoveFromBlacklist(Handle hPlugin, int iNumParams)
{
	char sProp[64];
	
	GetNativeString(1, sProp, sizeof(sProp));
	
	KeyValues kvBlacklist = new KeyValues("Vault");
	
	kvBlacklist.ImportFromFile(g_sBlacklistDB);
	
	kvBlacklist.JumpToKey("Blacklist", true);
	
	kvBlacklist.DeleteKey(sProp);
	
	kvBlacklist.Rewind();
	
	kvBlacklist.ExportToFile(g_sBlacklistDB);
	
	kvBlacklist.Close();
	
	return true;
}

public int Native_SetAuthID(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	GetClientAuthId(iClient, AuthId_SteamID64, g_sAuthID[iClient], sizeof(g_sAuthID));
	
	return true;
}

public int Native_SetCelCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	int iCount = GetNativeCell(2);
	
	g_iCelCount[iClient] = iCount;
	
	return true;
}

public int Native_SetCelLimit(Handle hPlugin, int iNumParams)
{
	int iLimit = GetNativeCell(1);
	
	g_iCelLimit = iLimit;
	
	return true;
}

public int Native_SetNoKill(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	bool bNoKill = view_as<bool>(GetNativeCell(2));
	
	//A player who is leaving (or never fully joined) may have no entity any more: only the setting is kept then.
	if (iClient > 0 && iClient <= MaxClients && IsClientInGame(iClient) && IsValidEntity(iClient))
	{
		SetEntProp(iClient, Prop_Data, "m_takedamage", bNoKill ? 0 : 2, 1);
	}
	
	g_bNoKill[iClient] = bNoKill;
	
	return true;
}

public int Native_SetPlayer(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	g_bPlayer[iClient] = view_as<bool>(GetNativeCell(2));
	
	return true;
}

public int Native_SetPropCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	int iCount = GetNativeCell(2);
	
	g_iPropCount[iClient] = iCount;
	
	return true;
}

public int Native_SetPropLimit(Handle hPlugin, int iNumParams)
{
	int iLimit = GetNativeCell(1);
	
	g_iPropLimit = iLimit;
	
	return true;
}

//A shop prop given, traded or sold to another player is theirs for good: one copy moves from the old owner's
//purchases to the new owner's, so it is saved with them (and the old owner can't spawn it again).
public void Cel_OnEntityOwnerChanged(int iEntity, int iOldOwner, int iNewOwner)
{
	char sName[64], sSpawn[256], sKey[80];
	
	if (!Cel_IsEntity(iEntity) || iOldOwner < 1 || iOldOwner > MaxClients || iNewOwner < 1 || iNewOwner > MaxClients
		|| !IsClientInGame(iOldOwner) || !IsClientInGame(iNewOwner) || IsFakeClient(iOldOwner) || IsFakeClient(iNewOwner))
	{
		return;
	}
	
	Cel_GetPropName(iEntity, sName, sizeof(sName));
	StringToLower(sName);
	
	if (!g_smShopProps.GetString(sName, sSpawn, sizeof(sSpawn)))
	{
		return;
	}
	
	FormatEx(sKey, sizeof(sKey), "prop_%s", sName);
	
	Cel_AddClientPurchase(iOldOwner, sKey, -1);
	Cel_AddClientPurchase(iNewOwner, sKey, 1);
	
	LogMessage("|CelMod| %L gave a %s to %L.", iOldOwner, sName, iNewOwner);
}

//Bank items that go through Cel_SpawnProp: shop props and hobos.
bool IsBankItemAlias(const char[] sAlias)
{
	char sLower[64], sSpawn[256];
	
	strcopy(sLower, sizeof(sLower), sAlias);
	StringToLower(sLower);
	
	return (StrEqual(sLower, "hobo") || g_smShopProps.GetString(sLower, sSpawn, sizeof(sSpawn)));
}

public void OnEntityCreated(int iEntity, const char[] sClassname)
{
	if (iEntity > 0 && iEntity <= MAXENTITIES)
	{
		g_bBankItem[iEntity] = false;
	}
}

//Moves an entity that was just counted as a prop or cel over to its owner's bank item count.
public int Native_MarkBankItem(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1);
	
	if (iEntity <= MaxClients || iEntity > MAXENTITIES || g_bBankItem[iEntity] || !Cel_IsEntity(iEntity))
	{
		return 0;
	}
	
	int iOwner = Cel_GetOwner(iEntity);
	
	g_bBankItem[iEntity] = true;
	
	if (iOwner > 0 && iOwner <= MaxClients)
	{
		if (Cel_CheckEntityCatagory(iEntity, ENTCATAGORY_PROP))
		{
			g_iPropCount[iOwner]--;
		} else {
			g_iCelCount[iOwner]--;
		}
		
		g_iItemCount[iOwner]++;
	}
	
	return 0;
}

public int Native_IsBankItem(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1);
	
	return (iEntity > 0 && iEntity <= MAXENTITIES && g_bBankItem[iEntity]);
}

public int Native_CheckItemCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	if (iClient < 1 || iClient > MaxClients)
	{
		return true;
	}
	
	if (g_iItemCount[iClient] >= g_cvItemLimit.IntValue)
	{
		RecountClientEntities(iClient);
	}
	
	return g_iItemCount[iClient] < g_cvItemLimit.IntValue;
}

public int Native_GetItemCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return (iClient > 0 && iClient <= MaxClients) ? g_iItemCount[iClient] : 0;
}

public int Native_SubFromItemCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	if (iClient > 0 && iClient <= MaxClients && g_iItemCount[iClient] > 0)
	{
		g_iItemCount[iClient]--;
	}
	
	return 0;
}

public int Native_AddToItemCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	if (iClient > 0 && iClient <= MaxClients)
	{
		g_iItemCount[iClient]++;
	}
	
	return 0;
}

//Shop props are finite for everyone, admins included. cm_admin_shop_props 1 lets root admins spawn any number
//of any shop prop, e.g. to set up displays.
bool AdminShopPropsUnlimited(int iClient)
{
	ConVar cvAdmin = FindConVar("cm_admin_shop_props");
	
	return (cvAdmin != null && cvAdmin.BoolValue && CheckCommandAccess(iClient, "celmod_shop_props", ADMFLAG_ROOT));
}

bool ShopPropCopyAllowed(int iClient, const char[] sAlias)
{
	char sLower[64], sSpawn[256], sKey[80], sName[64];
	
	if (iClient < 1 || iClient > MaxClients || !IsClientInGame(iClient) || AdminShopPropsUnlimited(iClient))
	{
		return true;
	}
	
	strcopy(sLower, sizeof(sLower), sAlias);
	StringToLower(sLower);
	
	if (!g_smShopProps.GetString(sLower, sSpawn, sizeof(sSpawn)))
	{
		return true;
	}
	
	FormatEx(sKey, sizeof(sKey), "prop_%s", sLower);
	
	int iOwned = Cel_GetClientPurchaseCount(iClient, sKey), iOut = 0;
	
	for (int i = MaxClients + 1; i < GetMaxEntities(); i++)
	{
		if (IsValidEntity(i) && Cel_IsEntity(i) && Cel_GetOwner(i) == iClient)
		{
			Cel_GetPropName(i, sName, sizeof(sName));
			
			if (StrEqual(sName, sLower, false))
			{
				iOut++;
			}
		}
	}
	
	if (iOut >= iOwned)
	{
		char sMessage[192];
		
		FormatEx(sMessage, sizeof(sMessage), "You own {green}%d{default} %s and %s out. Delete one or put it back with {green}!bank add{default}, or buy another.", iOwned, sLower, iOwned == 1 ? "it is" : "they are all");
		NotifySpawnRefused(iClient, sMessage);
		
		return false;
	}
	
	return true;
}

void NotifySpawnRefused(int iClient, const char[] sMessage)
{
	if (iClient > 0 && iClient <= MaxClients && IsClientInGame(iClient) && GetGameTime() >= g_fNextSpawnRefusal[iClient])
	{
		g_fNextSpawnRefusal[iClient] = GetGameTime() + 2.0;
		
		Cel_PrintToChat(iClient, sMessage);
	}
}

public int Native_SpawnProp(Handle hPlugin, int iNumParams)
{
	char sAlias[64], sModel[PLATFORM_MAX_PATH], sEntityType[64];
	float fAngles[3], fOrigin[3];
	int iClient = GetNativeCell(1), iColor[4];
	
	GetNativeString(2, sAlias, sizeof(sAlias));
	GetNativeString(3, sEntityType, sizeof(sEntityType));
	GetNativeString(4, sModel, sizeof(sModel));
	
	GetNativeArray(5, fAngles, 3);
	GetNativeArray(6, fOrigin, 3);
	
	iColor[0] = GetNativeCell(7);
	iColor[1] = GetNativeCell(8);
	iColor[2] = GetNativeCell(9);
	iColor[3] = GetNativeCell(10);
	
	//Nothing is built inside an event area (a maze or parkour course), even by aiming into it from outside or
	//loading a build over it. Admins with !adminmode on are the exception.
	if (iClient > 0 && iClient <= MaxClients && GetFeatureStatus(FeatureType_Native, "Cel_GetZoneType") == FeatureStatus_Available
		&& Cel_GetZoneType(fOrigin) == CEL_ZONE_EVENT && !Cel_ZoneExempt(iClient))
	{
		Cel_PrintToChat(iClient, "You cannot spawn things inside an event area.");
		return -1;
	}
	
	//Nobody builds in another player's land unless they're on its build team. Admins with !adminmode can.
	if (iClient > 0 && iClient <= MaxClients && IsClientInGame(iClient))
	{
		int iLandOwner = Cel_OtherLandAt(iClient, fOrigin);
		
		if (iLandOwner != 0)
		{
			char sMessage[160];
			
			FormatEx(sMessage, sizeof(sMessage), "That's {green}%N{default}'s land: you can only build there if they add you with {green}!addteam{default}.", iLandOwner);
			NotifySpawnRefused(iClient, sMessage);
			return -1;
		}
	}
	
	//A physics prop needs the model's .phy file. Without one it would not spawn at all, so it becomes a solid
	//prop that does not move instead.
	bool bNoPhysics = false;
	
	if (StrContains(sEntityType, "prop_physics", false) == 0 && !Cel_IsPhysicsModelComplete(sModel) && FileExists(sModel, true))
	{
		bNoPhysics = true;
		strcopy(sEntityType, sizeof(sEntityType), "prop_dynamic_override");
	}
	
	//Crash guards: never use up the server's last entity slots, and never overflow the model precache table.
	if (Cel_EdictsLow())
	{
		NotifySpawnRefused(iClient, "The server is nearly out of entity slots, so nothing more can be spawned right now. Delete some props first.");
		return -1;
	}
	
	if (Cel_ModelTableFull(sModel))
	{
		NotifySpawnRefused(iClient, "This map can't load any more new models. Try a prop that is already in use, or wait for the next map.");
		LogMessage("|CelMod| Model precache table is full: refused '%s'.", sModel);
		return -1;
	}
	
	//Shop props are finite CelItems: only as many copies can be out as the player has bought.
	if (!ShopPropCopyAllowed(iClient, sAlias))
	{
		return -1;
	}
	
	//Combine props (models/props_combine/) are unlocked by buying "combine props" in the shop, when it sells them.
	if (iClient > 0 && iClient <= MaxClients && IsClientInGame(iClient) && StrContains(sModel, "props_combine/", false) != -1)
	{
		int iPrice;
		char sDisplay[64];
		
		if (GetFeatureStatus(FeatureType_Native, "Cel_CheckShopDB") == FeatureStatus_Available
			&& Cel_CheckShopDB("combineprops", iPrice, sDisplay, sizeof(sDisplay)) && !Cel_CheckClientPurchase(iClient, "combineprops"))
		{
			char sMessage[160];
			
			FormatEx(sMessage, sizeof(sMessage), "Combine props are sold in the shop: buy them with {green}!buy combineprops{default} for {green}%d CL{default}.", iPrice);
			NotifySpawnRefused(iClient, sMessage);
			return -1;
		}
	}
	
	//Shop props and hobos are bank items: they have their own limit instead of the prop limit.
	bool bBankItem = IsBankItemAlias(sAlias);
	
	if (bBankItem && iClient > 0 && iClient <= MaxClients && !Cel_CheckItemCount(iClient))
	{
		char sMessage[192];
		
		FormatEx(sMessage, sizeof(sMessage), "You have {green}%d{default} bank items out, the most you can. Put some away with {green}!bank add{default} first.", g_iItemCount[iClient]);
		NotifySpawnRefused(iClient, sMessage);
		return -1;
	}
	
	int iProp = CreateEntityByName(sEntityType);
	
	if (iProp == -1)
	return -1;
	
	PrecacheModel(sModel);
	
	DispatchKeyValue(iProp, "model", sModel);
	
	//A prop_dynamic_override keeps its own classname until it has spawned (renamed earlier it would be deleted for
	//a physics-only model); it is renamed just after spawning below.
	if (!bNoPhysics)
	{
		DispatchKeyValue(iProp, "classname", "cel_physics");
	}
	
	if (bNoPhysics)
	{
		DispatchKeyValue(iProp, "solid", "2");
	}
	
	Entity_SetSolidType(iProp, bNoPhysics ? SOLID_BBOX : SOLID_VPHYSICS);
	Entity_SetCollisionGroup(iProp, COLLISION_GROUP_NONE);
	
	if (StrEqual(sEntityType, "cycler"))
	{
		DispatchKeyValue(iProp, "classname", "cel_doll");
		DispatchKeyValue(iProp, "DefaultAnim", "ragdoll");
	}
	
	TeleportEntity(iProp, fOrigin, fAngles, NULL_VECTOR);
	
	DispatchSpawn(iProp);
	
	if (bNoPhysics)
	{
		DispatchKeyValue(iProp, "classname", "cel_dynamic");
	}
	
	Cel_AddToPropCount(iClient);
	
	Cel_SetColor(iProp, iColor[0], iColor[1], iColor[2], iColor[3]);
	
	Cel_SetRainbow(iProp, false);
	
	Cel_SetEntity(iProp, true);
	
	Cel_SetMotion(iProp, false);
	
	Cel_SetOwner(iClient, iProp);
	
	Cel_SetPropName(iProp, sAlias);
	
	Cel_SetRenderFX(iProp, RENDERFX_NONE);
	
	Cel_SetSolid(iProp, true);
	
	Cel_SetBreakable(iProp, false);
	
	if (bBankItem)
	{
		Cel_MarkBankItem(iProp);
	}
	
	return iProp;
}

public int Native_SubFromCelCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	int iFinalCount = (g_iCelCount[iClient] -= 1);
	
	Cel_SetCelCount(iClient, iFinalCount);
	
	return true;
}

public int Native_SubFromPropCount(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	int iFinalCount = (g_iPropCount[iClient] -= 1);
	
	Cel_SetPropCount(iClient, iFinalCount);
	
	return true;
}

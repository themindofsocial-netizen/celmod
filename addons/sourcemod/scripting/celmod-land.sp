#pragma semicolon 1

#include <celmod>

#pragma newdecls required

#define LAND_MODEL "models/error.mdl"

bool g_bLandColor[MAXPLAYERS + 1];

ArrayList g_alSkinTiles[MAXPLAYERS + 1];
ConVar g_cvSkinTexture;
ConVar g_cvSkinTile;
int g_iLandSkin[MAXPLAYERS + 1];
bool g_bLate;

#define LANDSKIN_COUNT 26

ConVar g_cvMaxLandSize;

float g_fMaxLandSize;

Handle g_hGettingTop[MAXPLAYERS+1];
Handle g_hLandTimer[MAXPLAYERS+1];

int g_iBeam = -1;
int g_iCurrentLandEntity[MAXPLAYERS + 1];
int g_iCurrentLandOwner[MAXPLAYERS + 1];
int g_iHalo = -1;
int g_iLand = -1;
int g_iLandColor[MAXPLAYERS + 1][3];
int g_iLandEntOwner[MAXENTITIES + 1];
int g_iLaser = -1;
int g_iPhys = -1;

enum struct Land {
	bool bGodMode;
	bool bInCoopMode;
	bool bInDeathmatchMode;
	bool bInShopMode;
	bool bInsideLand;
	bool bLandCreated;
	bool bLandDrawing;
	bool bLandGettingTopPos;
	bool bModeCoop;
	bool bModeDeathmatch;
	bool bModeShop;
	
	float fLandGravity;
	float fLandPosBottom[3];
	float fLandPosBottomMiddle[3];
	float fLandPosBottomTop[3];
	float fLandPosStarting[3];
	float fLandPosTop[3];
	
	int iLandEntity;
	int iLandOwner;
	int iLandStage;
}

Land g_liLand[MAXPLAYERS+1];

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	CreateNative("Cel_ClearLand", Native_ClearLand);
	CreateNative("Cel_CreateLand", Native_CreateLand);
	CreateNative("Cel_DrawLandBorders", Native_DrawLandBorders);
	CreateNative("Cel_GetCurrentLandEntity", Native_GetCurrentLandEntity);
	CreateNative("Cel_GetCurrentLandOwner", Native_GetCurrentLandOwner);
	CreateNative("Cel_GetLandEntity", Native_GetLandEntity);
	CreateNative("Cel_GetLandGravity", Native_GetLandGravity);
	CreateNative("Cel_GetLandOwner", Native_GetLandOwner);
	CreateNative("Cel_GetLandOwnerFromEntity", Native_GetLandOwnerFromEntity);
	CreateNative("Cel_IsOnBuildTeam", Native_IsOnBuildTeam);
	CreateNative("Cel_CanEdit", Native_CanEdit);
	CreateNative("Cel_GetLandOwnerFromPosition", Native_GetLandOwnerFromPosition);
	CreateNative("Cel_GetLandPositions", Native_GetLandPositions);
	CreateNative("Cel_GetMiddleOfABox", Native_GetMiddleOfBox);
	CreateNative("Cel_IsClientCrosshairInLand", Native_IsClientCrosshairInLand);
	CreateNative("Cel_IsClientInLand", Native_IsClientInLand);
	CreateNative("Cel_IsEntityInLand", Native_IsEntityInLand);
	CreateNative("Cel_IsLandCreated", Native_IsLandCreated);
	CreateNative("Cel_IsPositionInBox", Native_IsPositionInBox);
	CreateNative("Cel_SetLandGravity", Native_SetLandGravity);
	CreateNative("Cel_SetCurrentLandEntity", Native_SetCurrentLandEntity);
	CreateNative("Cel_SetCurrentLandOwner", Native_SetCurrentLandOwner);
	
	g_bLate = bLate;
	
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "|CelMod| Land",
	author = CEL_AUTHOR,
	description = "Creates a personal building area.",
	version = CEL_VERSION,
	url = CEL_URL
};

//Skulls over the heads of players in a co-op or deathmatch land, seen by everyone.
#define SKULL_COOP "celmod/faces/skull_coop.vmt"
#define SKULL_DM "celmod/faces/skull2.vmt"

int g_iSkullRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };

//Build teams: g_bTeam[owner][member]. Each owner's team is remembered as SteamID64s in their "buildteam" setting.
bool g_bTeam[MAXPLAYERS + 1][MAXPLAYERS + 1];
char g_sTeamIds[MAXPLAYERS + 1][1024];
int g_iSkullMode[MAXPLAYERS + 1];
ConVar g_cvSkullSize;
int g_iSkullPixels[3];
ConVar g_cvSkullHeight;

public void OnPluginStart()
{
	LoadTranslations("celmod.phrases");
	
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
	
	g_cvMaxLandSize = CreateConVar("cm_max_land_size", "1495.5", "Maximum land size allowed.");
	
	g_cvMaxLandSize.AddChangeHook(CMLand_OnConVarChanged);
	
	g_fMaxLandSize = g_cvMaxLandSize.FloatValue;
	
	AutoExecConfig(true, "celmod.land");
	
	g_cvSkullSize = CreateConVar("cm_land_skull_size", "16", "How big (in units) the co-op and deathmatch skulls over players' heads are. A player is about 72 units tall.", _, true, 2.0, true, 128.0);
	g_cvSkullSize.AddChangeHook(CMLand_OnSkullSizeChanged);
	g_cvSkullHeight = CreateConVar("cm_land_skull_height", "80", "How high above a player's feet the middle of the land skull floats (a player is about 72 units tall).", _, true, 40.0, true, 200.0);
	g_cvSkullHeight.AddChangeHook(CMLand_OnSkullHeightChanged);
	
	CreateTimer(0.25, Timer_Skulls, _, TIMER_REPEAT);
	
	RegConsoleCmd("v_addteam", Command_AddTeam, "|CelMod| Lets a player build in your land and edit the props in it.");
	RegConsoleCmd("v_delteam", Command_DelTeam, "|CelMod| Removes a player from your build team, or lists your team.");
	RegConsoleCmd("v_team", Command_DelTeam, "|CelMod| Lists your build team.");
	
	RegConsoleCmd("v_coop", Command_LandCoop, "|CelMod| Changes the mode to co-op within the land.");
	RegConsoleCmd("v_deathmatch", Command_LandDeathmatch, "|CelMod| Changes the mode to deathmatch within the land.");
	RegConsoleCmd("v_dm", Command_LandDeathmatch, "|CelMod| Changes the mode to deathmatch within the land.");
	RegConsoleCmd("v_gravity", Command_LandGravity, "|CelMod| Changes the gravity within the land.");
	g_cvSkinTile = CreateConVar("cm_landskin_tile", "512", "Size in units of each land skin tile laid over a land's floor.", _, true, 64.0, true, 2048.0);
	g_cvSkinTexture = CreateConVar("cm_landskin_texture", "512", "Size in pixels of the land skin textures; sets how big each tile is drawn.", _, true, 16.0);
	
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_alSkinTiles[i] = new ArrayList();
	}
	
	RegConsoleCmd("v_landskin", Command_LandSkin, "|CelMod| Covers the floor of your land with a land skin (1 to 26), or removes it (off).");
	RegConsoleCmd("v_landcolor", Command_LandColor, "|CelMod| Changes the color of your land's border.");
	RegConsoleCmd("v_land", Command_Land, "|CelMod| Creates a building zone.");
	RegConsoleCmd("v_landcoop", Command_LandCoop, "|CelMod| Changes the mode to co-op within the land.");
	RegConsoleCmd("v_landdeathmatch", Command_LandDeathmatch, "|CelMod| Changes the mode to deathmatch within the land.");
	RegConsoleCmd("v_landgravity", Command_LandGravity, "|CelMod| Changes the gravity within the land.");
	RegConsoleCmd("v_landshop", Command_LandShop, "|CelMod| Changes the mode to shop (merchant) within the land.");
	RegConsoleCmd("v_shop", Command_LandShop, "|CelMod| Changes the mode to shop (merchant) within the land.");
}

//Saved teams are matched up once players' settings and Steam IDs are known.
public void OnClientPostAdminCheck(int iClient)
{
	char sId[32];
	
	Cel_GetClientSettingString(iClient, "buildteam", g_sTeamIds[iClient], sizeof(g_sTeamIds[]));
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == iClient || !IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}
		
		//This player's team members who are already here.
		if (GetClientAuthId(i, AuthId_SteamID64, sId, sizeof(sId)) && TeamListHas(g_sTeamIds[iClient], sId))
		{
			g_bTeam[iClient][i] = true;
		}
		
		//Teams this player is on.
		if (GetClientAuthId(iClient, AuthId_SteamID64, sId, sizeof(sId)) && TeamListHas(g_sTeamIds[i], sId))
		{
			g_bTeam[i][iClient] = true;
		}
	}
}

bool TeamListHas(const char[] sList, const char[] sId)
{
	char sFind[40];
	
	Format(sFind, sizeof(sFind), ",%s,", sId);
	
	char sWrapped[1100];
	
	Format(sWrapped, sizeof(sWrapped), ",%s,", sList);
	
	return (StrContains(sWrapped, sFind) != -1);
}

void SaveTeam(int iOwner)
{
	char sId[32];
	
	g_sTeamIds[iOwner][0] = '\0';
	
	//Members who are here now, plus saved members who are not.
	char sOld[1024], sParts[32][32];
	
	Cel_GetClientSettingString(iOwner, "buildteam", sOld, sizeof(sOld));
	
	int iParts = ExplodeString(sOld, ",", sParts, sizeof(sParts), sizeof(sParts[]));
	
	for (int k = 0; k < iParts; k++)
	{
		if (sParts[k][0] == '\0' || IsIdInGame(sParts[k]))
		{
			continue;
		}
		
		Format(g_sTeamIds[iOwner], sizeof(g_sTeamIds[]), "%s%s%s", g_sTeamIds[iOwner], g_sTeamIds[iOwner][0] == '\0' ? "" : ",", sParts[k]);
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bTeam[iOwner][i] && IsClientInGame(i) && GetClientAuthId(i, AuthId_SteamID64, sId, sizeof(sId)))
		{
			Format(g_sTeamIds[iOwner], sizeof(g_sTeamIds[]), "%s%s%s", g_sTeamIds[iOwner], g_sTeamIds[iOwner][0] == '\0' ? "" : ",", sId);
		}
	}
	
	Cel_SetClientSettingString(iOwner, "buildteam", g_sTeamIds[iOwner]);
}

bool IsIdInGame(const char[] sId)
{
	char sOther[32];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientAuthId(i, AuthId_SteamID64, sOther, sizeof(sOther)) && StrEqual(sOther, sId))
		{
			return true;
		}
	}
	
	return false;
}

public Action Command_AddTeam(int iClient, int iArgs)
{
	char sTarget[MAX_NAME_LENGTH];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]addteam{default} <player>. They can then build in your land and edit the props in it.");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	int iTarget = FindTarget(iClient, sTarget, true, false);
	
	if (iTarget == -1)
	{
		return Plugin_Handled;
	}
	
	if (iTarget == iClient)
	{
		Cel_ReplyToCommand(iClient, "You are always on your own build team.");
		return Plugin_Handled;
	}
	
	g_bTeam[iClient][iTarget] = true;
	
	SaveTeam(iClient);
	
	Cel_ReplyToCommand(iClient, "{green}%N{default} is now on your build team: they can build in your land and edit the props in it. Only you can save and load the build.", iTarget);
	Cel_PrintToChat(iTarget, "{green}%N{default} added you to their build team: you can build in their land and edit the props in it.", iClient);
	
	return Plugin_Handled;
}

public Action Command_DelTeam(int iClient, int iArgs)
{
	char sTarget[MAX_NAME_LENGTH], sList[512];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	//No name: list the team.
	if (iArgs < 1)
	{
		sList[0] = '\0';
		
		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_bTeam[iClient][i] && IsClientInGame(i))
			{
				Format(sList, sizeof(sList), "%s%s{green}%N{default}", sList, sList[0] == '\0' ? "" : ", ", i);
			}
		}
		
		if (sList[0] == '\0')
		{
			Cel_ReplyToCommand(iClient, "Nobody on your build team is here. Add someone with {green}[tag]addteam{default} <player>.");
		} else {
			Cel_ReplyToCommand(iClient, "Your build team here: %s. Remove someone with {green}[tag]delteam{default} <player>.", sList);
		}
		
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	int iTarget = FindTarget(iClient, sTarget, true, false);
	
	if (iTarget == -1 || iTarget == iClient)
	{
		return Plugin_Handled;
	}
	
	if (!g_bTeam[iClient][iTarget])
	{
		Cel_ReplyToCommand(iClient, "{green}%N{default} is not on your build team.", iTarget);
		return Plugin_Handled;
	}
	
	g_bTeam[iClient][iTarget] = false;
	
	SaveTeam(iClient);
	
	Cel_ReplyToCommand(iClient, "{green}%N{default} is no longer on your build team.", iTarget);
	Cel_PrintToChat(iTarget, "{green}%N{default} removed you from their build team.", iClient);
	
	return Plugin_Handled;
}

public int Native_IsOnBuildTeam(Handle hPlugin, int iNumParams)
{
	int iOwner = GetNativeCell(1), iClient = GetNativeCell(2);
	
	if (iOwner < 1 || iOwner > MaxClients || iClient < 1 || iClient > MaxClients)
	{
		return false;
	}
	
	return (iOwner == iClient || g_bTeam[iOwner][iClient]);
}

public int Native_CanEdit(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1), iEntity = GetNativeCell(2);
	
	if (iEntity <= MaxClients || !Cel_IsEntity(iEntity))
	{
		return false;
	}
	
	int iOwner = Cel_GetOwner(iEntity);
	
	if (iOwner == iClient)
	{
		return true;
	}
	
	if (iClient < 1 || iClient > MaxClients || iOwner < 1 || iOwner > MaxClients)
	{
		return false;
	}
	
	//In the land of someone whose team the player is on, and owned by that land's owner or another teammate.
	int iLandOwner = Cel_GetLandOwnerFromEntity(iEntity);
	
	if (iLandOwner < 1 || iLandOwner > MaxClients)
	{
		return false;
	}
	
	bool bClientAllowed = (iLandOwner == iClient || g_bTeam[iLandOwner][iClient]);
	bool bOwnerAllowed = (iLandOwner == iOwner || g_bTeam[iLandOwner][iOwner]);
	
	return (bClientAllowed && bOwnerAllowed);
}

public void OnClientPutInServer(int iClient)
{
	Cel_ClearLand(iClient);
	
	g_bLandColor[iClient] = false;
	
	SDKHook(iClient, SDKHook_OnTakeDamage, Hook_CoopDamage);
	
	g_iLandSkin[iClient] = Cel_GetClientSettingInt(iClient, "landskin");
	
	if (g_iLandSkin[iClient] < 1 || g_iLandSkin[iClient] > LANDSKIN_COUNT)
	{
		g_iLandSkin[iClient] = 0;
	}
	
	g_hGettingTop[iClient] = CreateTimer(0.1, Timer_GettingTop, GetClientUserId(iClient), TIMER_REPEAT);
	g_hLandTimer[iClient] = CreateTimer(0.1, Timer_Land, GetClientUserId(iClient), TIMER_REPEAT);
}

public void OnClientDisconnect(int iClient)
{
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_bTeam[iClient][i] = false;
		g_bTeam[i][iClient] = false;
	}
	
	g_sTeamIds[iClient][0] = '\0';

	RemoveSkull(iClient);
	
	Cel_ClearLand(iClient);
	
	if(g_hGettingTop[iClient] != INVALID_HANDLE)
	{
		CloseHandle(g_hGettingTop[iClient]);
	}
	
	if(g_hLandTimer[iClient] != INVALID_HANDLE)
	{
		CloseHandle(g_hLandTimer[iClient]);
	}
}

public void OnMapStart()
{
	g_iBeam = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iHalo = PrecacheModel("materials/sprites/halo01.vmt");
	g_iLand = PrecacheModel("materials/sprites/spotlight.vmt");
	g_iLaser = PrecacheModel("materials/sprites/laser.vmt");
	g_iPhys = PrecacheModel("materials/sprites/physbeam.vmt");
	
	g_iSkullPixels[1] = PrecacheSkull(SKULL_COOP);
	g_iSkullPixels[2] = PrecacheSkull(SKULL_DM);
	
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_iSkullRef[i] = INVALID_ENT_REFERENCE;
		g_iSkullMode[i] = 0;
	}
}

//Sent to players along with its texture, when the server has the files.
//Precaches the skull, sends its files to players, and returns the texture's width in pixels (a sprite is drawn
//one unit per pixel at scale 1, so this is what the scale is worked out from).
int PrecacheSkull(const char[] sMaterial)
{
	char sFile[PLATFORM_MAX_PATH];
	int iWidth = 0;
	
	PrecacheModel(sMaterial, true);
	
	Format(sFile, sizeof(sFile), "materials/%s", sMaterial);
	
	if (FileExists(sFile, false))
	{
		AddFileToDownloadsTable(sFile);
	}
	
	ReplaceString(sFile, sizeof(sFile), ".vmt", ".vtf");
	
	if (FileExists(sFile, false))
	{
		AddFileToDownloadsTable(sFile);
	}
	
	//The VTF header holds the width as a 16-bit number 16 bytes in.
	File fTexture = OpenFile(sFile, "rb", true);
	
	if (fTexture != null)
	{
		int iValue;
		
		if (fTexture.Seek(16, SEEK_SET) && fTexture.ReadInt16(iValue))
		{
			iWidth = iValue & 0xFFFF;
		}
		
		delete fTexture;
	}
	
	return (iWidth > 0) ? iWidth : 128;
}

float SkullScale(int iMode)
{
	return g_cvSkullSize.FloatValue / float(g_iSkullPixels[iMode] > 0 ? g_iSkullPixels[iMode] : 128);
}

//A new height: every skull is put back on at the new height (the timer puts them back within a quarter second).
public void CMLand_OnSkullHeightChanged(ConVar cvConVar, const char[] sOldValue, const char[] sNewValue)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		RemoveSkull(i);
	}
}

//A new size applies to every skull already showing, straight away.
public void CMLand_OnSkullSizeChanged(ConVar cvConVar, const char[] sOldValue, const char[] sNewValue)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		int iSkull = EntRefToEntIndex(g_iSkullRef[i]);
		
		if (g_iSkullRef[i] != INVALID_ENT_REFERENCE && iSkull != INVALID_ENT_REFERENCE && g_iSkullMode[i] > 0)
		{
			SetEntPropFloat(iSkull, Prop_Send, "m_flSpriteScale", SkullScale(g_iSkullMode[i]));
		}
	}
}

//Co-op land: skull_coop over the head. Deathmatch land: skull2. Shown to everyone, wherever they are.
public Action Timer_Skulls(Handle hTimer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}
		
		int iMode = 0;
		
		if (IsPlayerAlive(i) && g_liLand[i].bInsideLand)
		{
			if (g_liLand[i].bInDeathmatchMode)
			{
				iMode = 2;
			} else if (g_liLand[i].bInCoopMode)
			{
				iMode = 1;
			}
		}
		
		if (iMode == g_iSkullMode[i] && (iMode == 0 || EntRefToEntIndex(g_iSkullRef[i]) != INVALID_ENT_REFERENCE))
		{
			continue;
		}
		
		RemoveSkull(i);
		
		if (iMode != 0)
		{
			CreateSkull(i, iMode);
		}
	}
	
	return Plugin_Continue;
}

void CreateSkull(int iClient, int iMode)
{
	float fOrigin[3];
	
	int iSkull = CreateEntityByName("env_sprite");
	
	if (iSkull == -1)
	{
		return;
	}
	
	DispatchKeyValue(iSkull, "model", iMode == 2 ? SKULL_DM : SKULL_COOP);
	DispatchKeyValue(iSkull, "rendermode", "1");
	DispatchKeyValue(iSkull, "renderamt", "255");
	DispatchKeyValue(iSkull, "rendercolor", "255 255 255");
	DispatchKeyValue(iSkull, "spawnflags", "1");
	DispatchKeyValue(iSkull, "classname", "cel_landskull");
	DispatchKeyValueFloat(iSkull, "scale", SkullScale(iMode));
	
	DispatchSpawn(iSkull);
	
	GetClientAbsOrigin(iClient, fOrigin);
	
	fOrigin[2] += g_cvSkullHeight.FloatValue;
	
	TeleportEntity(iSkull, fOrigin, NULL_VECTOR, NULL_VECTOR);
	
	//Parented to the player, so it moves with them smoothly on everyone's screen.
	SetVariantString("!activator");
	AcceptEntityInput(iSkull, "SetParent", iClient, iSkull);
	
	AcceptEntityInput(iSkull, "ShowSprite");
	
	g_iSkullRef[iClient] = EntIndexToEntRef(iSkull);
	g_iSkullMode[iClient] = iMode;
	
	SDKHook(iSkull, SDKHook_SetTransmit, Hook_SkullTransmit);
}

void RemoveSkull(int iClient)
{
	int iSkull = EntRefToEntIndex(g_iSkullRef[iClient]);
	
	if (g_iSkullRef[iClient] != INVALID_ENT_REFERENCE && iSkull != INVALID_ENT_REFERENCE && iSkull > MaxClients)
	{
		AcceptEntityInput(iSkull, "kill");
	}
	
	g_iSkullRef[iClient] = INVALID_ENT_REFERENCE;
	g_iSkullMode[iClient] = 0;
}

//Everyone sees the skull, except its own player in first person (it would float in their view when looking up).
public Action Hook_SkullTransmit(int iEntity, int iClient)
{
	if (iClient > 0 && iClient <= MaxClients && EntRefToEntIndex(g_iSkullRef[iClient]) == iEntity && GetEntProp(iClient, Prop_Send, "m_iObserverMode") == 0)
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public void OnMapEnd()
{
	g_iBeam = -1;
	g_iHalo = -1;
	g_iLand = -1;
	g_iLaser = -1;
	g_iPhys = -1;
}

public void CMLand_OnConVarChanged(ConVar cvConVar, const char[] sOldValue, const char[] sNewValue)
{
	if (cvConVar == g_cvMaxLandSize)
	{
		g_fMaxLandSize = g_cvMaxLandSize.FloatValue;
		PrintToServer("|CelMod| Max land size updated to %s.", sNewValue);
	}
}

//Commands:
public Action Command_Land(int iClient, int iArgs)
{
	char sOption[64];
	
	GetCmdArg(1, sOption, sizeof(sOption));
	
	if(StrContains(sOption, "#clear", false) != -1)
	{
		if(Cel_IsLandCreated(iClient))
		{
			Cel_ClearLand(iClient);
			
			Cel_ReplyToCommand(iClient, "%t", "LandCleared");
		}else{
			Cel_ReplyToCommand(iClient, "%t", "LandNotStarted");
		}
		
		return Plugin_Handled;
	}else if(StrEqual(sOption, "")){
		switch(g_liLand[iClient].iLandStage)
		{
			case 0:
			{
				if(Cel_IsClientCrosshairInLand(iClient))
				{
					Cel_ReplyToCommand(iClient, "%t", "CantStartLandInLand");
					return Plugin_Handled;
				}
				
				Cel_GetCrosshairHitOrigin(iClient, g_liLand[iClient].fLandPosBottom);
				Cel_GetCrosshairHitOrigin(iClient, g_liLand[iClient].fLandPosStarting);
				
				g_liLand[iClient].bLandDrawing = true;
				g_liLand[iClient].bLandGettingTopPos = true;
				
				Cel_ReplyToCommand(iClient, "%t", "LandStarted");
				
				g_liLand[iClient].iLandStage = 1;
			}
			
			case 1:
			{
				if(Cel_IsClientCrosshairInLand(iClient))
				{
					Cel_ReplyToCommand(iClient, "%t", "CantEndLandInLand");
					return Plugin_Handled;
				}
				
				g_liLand[iClient].bLandGettingTopPos = false;
				g_liLand[iClient].bLandCreated = true;
				
				Cel_GetMiddleOfABox(g_liLand[iClient].fLandPosBottom, g_liLand[iClient].fLandPosTop, g_liLand[iClient].fLandPosBottomMiddle);
				
				g_liLand[iClient].fLandPosBottomMiddle[2] = g_liLand[iClient].fLandPosBottom[2];
				
				Cel_CreateLand(iClient, g_liLand[iClient].fLandPosBottom, g_liLand[iClient].fLandPosTop);
				
				//A land skin the player chose before is laid on the new land.
				ApplyLandSkin(iClient);
				
				g_liLand[iClient].iLandStage = 2;
				
				Cel_ReplyToCommand(iClient, "%t", "LandFinished");
			}
			
			case 2:
			{
				Cel_ClearLand(iClient);
				
				Cel_ReplyToCommand(iClient, "%t", "LandCleared");
			}
		}
	}else{
		Cel_ReplyToCommand(iClient, "%t", "CMD_Land");
		return Plugin_Handled;
	}
	
	return Plugin_Handled;
}

public Action Command_LandCoop(int iClient, int iArgs)
{
	g_liLand[iClient].bModeCoop = !g_liLand[iClient].bModeCoop;
	g_liLand[iClient].bModeDeathmatch = false;
	g_liLand[iClient].bModeShop = false;
	
	Cel_ReplyToCommand(iClient, "%t", g_liLand[iClient].bModeCoop ? "CoopOn" : "CoopOff");
	
	return Plugin_Handled;
}

public Action Command_LandDeathmatch(int iClient, int iArgs)
{
	g_liLand[iClient].bModeCoop = false;
	g_liLand[iClient].bModeDeathmatch = !g_liLand[iClient].bModeDeathmatch;
	g_liLand[iClient].bModeShop = false;
	
	Cel_ReplyToCommand(iClient, "%t", g_liLand[iClient].bModeDeathmatch ? "DeathmatchOn" : "DeathmatchOff");
	
	return Plugin_Handled;
}

public Action Command_LandGravity(int iClient, int iArgs)
{
	char sGravity[64];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CMD_LandGravity");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sGravity, sizeof(sGravity));
	
	float fGravity = StringToFloat(sGravity);
	
	//Either a multiplier (0.5 = half) or the game's own gravity units (600 is normal, 300 is half).
	if (fGravity > 10.0)
	{
		fGravity /= 600.0;
	}
	
	if (fGravity < 0.05 || fGravity > 4.0)
	{
		Cel_ReplyToCommand(iClient, "Gravity goes from {green}0.05{default} (almost none) to {green}4{default} (four times normal); {green}1{default} is normal. Game units such as {green}300{default} work too.");
		return Plugin_Handled;
	}
	
	Cel_SetLandGravity(iClient, fGravity);
	
	//Everyone already standing in the land feels it straight away.
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && g_liLand[i].bInsideLand && Cel_GetCurrentLandOwner(i) == iClient)
		{
			SetEntityGravity(i, fGravity);
		}
	}
	
	Cel_ReplyToCommand(iClient, "Your land's gravity is now {green}%.2f{default} times normal.", fGravity);
	
	return Plugin_Handled;
}

public Action Command_LandShop(int iClient, int iArgs)
{
	g_liLand[iClient].bModeCoop = false;
	g_liLand[iClient].bModeDeathmatch = false;
	g_liLand[iClient].bModeShop = !g_liLand[iClient].bModeShop;
	
	Cel_ReplyToCommand(iClient, "%t", g_liLand[iClient].bModeShop ? "ShopOn" : "ShopOff");
	
	return Plugin_Handled;
}

//Natives:
public int Native_CreateLand(Handle hPlugin, int iNumParams)
{
	float fMax[3], fLandPosMiddle[3], fMin[3];
	int iClient, iEnt;
	
	iClient = GetNativeCell(1);
	
	GetNativeArray(2, fMin, 3);
	GetNativeArray(3, fMax, 3);
	
	iEnt = CreateEntityByName("trigger_multiple");
	
	DispatchKeyValue(iEnt, "spawnflags", "1103");
	DispatchKeyValue(iEnt, "wait", "0");
	
	DispatchSpawn(iEnt);
	ActivateEntity(iEnt);
	
	Cel_GetMiddleOfABox(fMin, fMax, fLandPosMiddle);
	
	TeleportEntity(iEnt, fLandPosMiddle, NULL_VECTOR, NULL_VECTOR);
	
	PrecacheModel(LAND_MODEL);
	SetEntityModel(iEnt, LAND_MODEL);
	
	fMin[0] = fMin[0] - fLandPosMiddle[0];
	if (fMin[0] > 0.0)
	fMin[0] *= -1.0;
	
	fMin[1] = fMin[1] - fLandPosMiddle[1];
	if (fMin[1] > 0.0)
	fMin[1] *= -1.0;
	
	fMin[2] = fMin[2] - fLandPosMiddle[2];
	if (fMin[2] > 0.0)
	fMin[2] *= -1.0;
	
	fMax[0] = fMax[0] - fLandPosMiddle[0];
	if (fMax[0] < 0.0)
	fMax[0] *= -1.0;
	
	fMax[1] = fMax[1] - fLandPosMiddle[1];
	if (fMax[1] < 0.0)
	fMax[1] *= -1.0;
	
	fMax[2] = fMax[2] - fLandPosMiddle[2];
	if (fMax[2] < 0.0)
	fMax[2] *= -1.0;
	
	SetEntPropVector(iEnt, Prop_Send, "m_vecMins", fMin);
	SetEntPropVector(iEnt, Prop_Send, "m_vecMaxs", fMax);
	
	SetEntProp(iEnt, Prop_Send, "m_nSolidType", 2);
	
	int iEffects = GetEntProp(iEnt, Prop_Send, "m_fEffects");
	iEffects |= 32;
	SetEntProp(iEnt, Prop_Send, "m_fEffects", iEffects);
	
	HookSingleEntityOutput(iEnt, "OnStartTouch", EntOut_LandOnStartTouch);
	HookSingleEntityOutput(iEnt, "OnTrigger", EntOut_LandOnTrigger);
	HookSingleEntityOutput(iEnt, "OnEndTouch", EntOut_LandOnEndTouch);
	
	g_iLandEntOwner[iEnt] = iClient;
	g_liLand[iClient].iLandEntity = iEnt;
	g_liLand[iClient].iLandOwner = iClient;
	
	g_liLand[iClient].bModeCoop = false;
	g_liLand[iClient].bModeDeathmatch = false;
	g_liLand[iClient].bModeShop = false;
	
	return g_liLand[iClient].iLandEntity;
}

public int Native_ClearLand(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	RemoveLandSkin(iClient);
	
	g_liLand[iClient].bInCoopMode = false;
	g_liLand[iClient].bInDeathmatchMode = false;
	g_liLand[iClient].bInShopMode = false;
	g_liLand[iClient].bInsideLand = false;
	g_liLand[iClient].bLandDrawing = false;
	g_liLand[iClient].bLandGettingTopPos = false;
	g_liLand[iClient].bModeCoop = false;
	g_liLand[iClient].bModeDeathmatch = false;
	g_liLand[iClient].bModeShop = false;
	
	if(Cel_IsLandCreated(iClient))
	{
		AcceptEntityInput(g_liLand[iClient].iLandEntity, "kill");
	}
	
	g_liLand[iClient].bLandCreated = false;
	
	g_liLand[iClient].fLandPosBottom = g_fZero;
	g_liLand[iClient].fLandPosBottomTop = g_fZero;
	g_liLand[iClient].fLandGravity = 1.0;
	g_liLand[iClient].fLandPosBottomMiddle = g_fZero;
	g_liLand[iClient].fLandPosStarting = g_fZero;
	g_liLand[iClient].fLandPosTop = g_fZero;
	
	g_liLand[iClient].iLandEntity = -1;
	g_liLand[iClient].iLandOwner = -1;
	g_liLand[iClient].iLandStage = 0;
	
	return true;
}

public int Native_DrawLandBorders(Handle hPlugin, int iNumParams)
{
	bool bFlat = view_as<bool>(GetNativeCell(5));
	float fFrom[3], fLife, fTo[3];
	int iColor[4];
	
	GetNativeArray(1, fFrom, 3);
	GetNativeArray(2, fTo, 3);
	fLife = view_as<float>(GetNativeCell(3));
	
	GetNativeArray(4, iColor, 4);
	
	float fLeftBottomFront[3];
	
	fLeftBottomFront[0] = fFrom[0];
	fLeftBottomFront[1] = fFrom[1];
	
	if (bFlat)
	{
		fLeftBottomFront[2] = fTo[2] - 2;
	} else {
		fLeftBottomFront[2] = fTo[2];
	}
	
	float fRightBottomFront[3];
	
	fRightBottomFront[0] = fTo[0];
	fRightBottomFront[1] = fFrom[1];
	
	if (bFlat)
	{
		fRightBottomFront[2] = fTo[2] - 2;
	} else {
		fRightBottomFront[2] = fTo[2];
	}
	
	float fLeftBottomBack[3];
	
	fLeftBottomBack[0] = fFrom[0];
	fLeftBottomBack[1] = fTo[1];
	
	if (bFlat)
	{
		fLeftBottomBack[2] = fTo[2] - 2;
	} else {
		fLeftBottomBack[2] = fTo[2];
	}
	
	float fRightBottomBack[3];
	
	fRightBottomBack[0] = fTo[0];
	fRightBottomBack[1] = fTo[1];
	
	if (bFlat)
	{
		fRightBottomBack[2] = fTo[2] - 2;
	} else {
		fRightBottomBack[2] = fTo[2];
	}
	
	float fLeftTopFront[3];
	
	fLeftTopFront[0] = fFrom[0];
	fLeftTopFront[1] = fFrom[1];
	
	if (bFlat)
	{
		fLeftTopFront[2] = fFrom[2] + 3;
	} else {
		fLeftTopFront[2] = fFrom[2] + 100;
	}
	
	float fRightTopFront[3];
	
	fRightTopFront[0] = fTo[0];
	fRightTopFront[1] = fFrom[1];
	
	if (bFlat)
	{
		fRightTopFront[2] = fFrom[2] + 3;
	} else {
		fRightTopFront[2] = fFrom[2] + 100;
	}
	
	float fLeftTopBack[3];
	
	fLeftTopBack[0] = fFrom[0];
	fLeftTopBack[1] = fTo[1];
	
	if (bFlat)
	{
		fLeftTopBack[2] = fFrom[2] + 3;
	} else {
		fLeftTopBack[2] = fFrom[2] + 100;
	}
	
	float fRightTopBack[3];
	
	fRightTopBack[0] = fTo[0];
	fRightTopBack[1] = fTo[1];
	
	if (bFlat)
	{
		fRightTopBack[2] = fFrom[2] + 3;
	} else {
		fRightTopBack[2] = fFrom[2] + 100;
	}
	
	TE_SetupBeamPoints(fLeftTopFront, fRightTopFront, g_iLand, 0, 0, 0, fLife, 3.0, 3.0, 10, 0.0, iColor, 0); TE_SendToAll(0.0);
	TE_SetupBeamPoints(fLeftTopFront, fLeftTopBack, g_iLand, 0, 0, 0, fLife, 3.0, 3.0, 10, 0.0, iColor, 0); TE_SendToAll(0.0);
	TE_SetupBeamPoints(fRightTopBack, fLeftTopBack, g_iLand, 0, 0, 0, fLife, 3.0, 3.0, 10, 0.0, iColor, 0); TE_SendToAll(0.0);
	TE_SetupBeamPoints(fRightTopBack, fRightTopFront, g_iLand, 0, 0, 0, fLife, 3.0, 3.0, 10, 0.0, iColor, 0); TE_SendToAll(0.0);
	
	return true;
}

public int Native_GetLandEntity(Handle hPlugin, int iNumParams)
{
	float fLandPosBottom[3], fLandPosTop[3];
	
	GetNativeArray(1, fLandPosBottom, 3);
	GetNativeArray(2, fLandPosTop, 3);
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientAuthorized(i))
		{
			if(g_liLand[i].fLandPosBottom[0] == fLandPosBottom[0] && g_liLand[i].fLandPosBottom[1] == fLandPosBottom[1] && g_liLand[i].fLandPosBottom[2] == fLandPosBottom[2] && g_liLand[i].fLandPosTop[0] == fLandPosTop[0] && g_liLand[i].fLandPosTop[1] == fLandPosTop[1] && g_liLand[i].fLandPosTop[2] == fLandPosTop[2])
			{
				return g_liLand[i].iLandEntity;
			}
		}
	}
	
	return -1;
}

public int Native_GetLandOwner(Handle hPlugin, int iNumParams)
{
	float fLandPosBottom[3], fLandPosTop[3];
	
	GetNativeArray(1, fLandPosBottom, 3);
	GetNativeArray(2, fLandPosTop, 3);
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientAuthorized(i))
		{
			if(g_liLand[i].fLandPosBottom[0] == fLandPosBottom[0] && g_liLand[i].fLandPosBottom[1] == fLandPosBottom[1] && g_liLand[i].fLandPosBottom[2] == fLandPosBottom[2] && g_liLand[i].fLandPosTop[0] == fLandPosTop[0] && g_liLand[i].fLandPosTop[1] == fLandPosTop[1] && g_liLand[i].fLandPosTop[2] == fLandPosTop[2])
			{
				return g_liLand[i].iLandOwner;
			}
		}
	}
	
	return -1;
}

public int Native_GetLandOwnerFromEntity(Handle hPlugin, int iNumParams)
{
	float fOrigin[3], fMax[3], fMin[3];
	int iEntity = GetNativeCell(1);
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientAuthorized(i))
		{
			Entity_GetAbsOrigin(iEntity, fOrigin);
			GetEntPropVector(iEntity, Prop_Send, "m_vecMins", fMin);
			GetEntPropVector(iEntity, Prop_Send, "m_vecMaxs", fMax);
			
			fMin[0] = fOrigin[0] + fMin[0];
			fMin[1] = fOrigin[1] + fMin[1];
			fMin[2] = fOrigin[2] + fMin[2];
			
			fMax[0] = fOrigin[0] + fMax[0];
			fMax[1] = fOrigin[1] + fMax[1];
			fMax[2] = fOrigin[2] + fMax[2];
			
			if(Cel_IsPositionInBox(fMax, g_liLand[i].fLandPosBottom, g_liLand[i].fLandPosTop) || Cel_IsPositionInBox(fOrigin, g_liLand[i].fLandPosBottom, g_liLand[i].fLandPosTop) || Cel_IsPositionInBox(fMin, g_liLand[i].fLandPosBottom, g_liLand[i].fLandPosTop))
			{
				return g_liLand[i].iLandOwner;
			}
		}
	}
	
	return -1;
}

public int Native_GetLandOwnerFromPosition(Handle hPlugin, int iNumParams)
{
	float fOrigin[3];
	
	GetNativeArray(1, fOrigin, 3);
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientAuthorized(i))
		{
			if(Cel_IsPositionInBox(fOrigin, g_liLand[i].fLandPosBottom, g_liLand[i].fLandPosTop))
			{
				return g_liLand[i].iLandOwner;
			}
		}
	}
	
	return -1;
}

public void Native_GetLandPositions(Handle hPlugin, int iNumParams)
{
	float fPosition[3];
	int iClient = GetNativeCell(1), iPosition = GetNativeCell(2);
	
	switch(iPosition)
	{
		case 1:
		{
			fPosition = g_liLand[iClient].fLandPosStarting;
		}
		case 2:
		{
			fPosition = g_liLand[iClient].fLandPosBottom;
		}
		case 3:
		{
			fPosition = g_liLand[iClient].fLandPosTop;
		}
		case 4:
		{
			fPosition = g_liLand[iClient].fLandPosBottomTop;
		}
		case 5:
		{
			fPosition = g_liLand[iClient].fLandPosBottomMiddle;
		}
	}
	
	SetNativeArray(3, fPosition, 3);
}

public int Native_GetMiddleOfBox(Handle hPlugin, int iNumParams)
{
	float fBuffer[3], fMax[3], fMin[3];
	
	GetNativeArray(1, fMin, 3);
	GetNativeArray(2, fMax, 3);
	
	float fMid[3];
	
	MakeVectorFromPoints(fMin, fMax, fMid);
	
	fMid[0] = fMid[0] / 2.0;
	fMid[1] = fMid[1] / 2.0;
	fMid[2] = fMid[2] / 2.0;
	
	AddVectors(fMin, fMid, fBuffer);
	
	SetNativeArray(3, fBuffer, 3);
	
	return true;
}

public int Native_IsClientInLand(Handle hPlugin, int iNumParams)
{
	float fOrigin[3];
	int iClient = GetNativeCell(1);
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientAuthorized(i))
		{
			GetClientAbsOrigin(iClient, fOrigin);
			
			if(Cel_IsPositionInBox(fOrigin, g_liLand[i].fLandPosBottom, g_liLand[i].fLandPosTop))
			{
				return true;
			}
		}
	}
	
	return false;
}

public int Native_IsClientCrosshairInLand(Handle hPlugin, int iNumParams)
{
	float fOrigin[3];
	int iClient = GetNativeCell(1);
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientAuthorized(i))
		{
			Cel_GetCrosshairHitOrigin(iClient, fOrigin);
			
			fOrigin[2] += 1.0;
			
			if(Cel_IsPositionInBox(fOrigin, g_liLand[i].fLandPosBottom, g_liLand[i].fLandPosTop) && g_liLand[i].bLandCreated)
			{
				return true;
			}
		}else{
			return false;
		}
	}
	
	return false;
}

public int Native_IsEntityInLand(Handle hPlugin, int iNumParams)
{
	float fMax[3], fMin[3], fOrigin[3];
	int iEntity = GetNativeCell(1);
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsClientAuthorized(i))
		{
			Entity_GetAbsOrigin(iEntity, fOrigin);
			GetEntPropVector(iEntity, Prop_Send, "m_vecMins", fMin);
			GetEntPropVector(iEntity, Prop_Send, "m_vecMaxs", fMax);
			
			fMin[0] = fOrigin[0] + fMin[0];
			fMin[1] = fOrigin[1] + fMin[1];
			fMin[2] = fOrigin[2] + fMin[2];
			
			fMax[0] = fOrigin[0] + fMax[0];
			fMax[1] = fOrigin[1] + fMax[1];
			fMax[2] = fOrigin[2] + fMax[2];
			
			if(Cel_IsPositionInBox(fMax, g_liLand[i].fLandPosBottom, g_liLand[i].fLandPosTop) || Cel_IsPositionInBox(fOrigin, g_liLand[i].fLandPosBottom, g_liLand[i].fLandPosTop) || Cel_IsPositionInBox(fMin, g_liLand[i].fLandPosBottom, g_liLand[i].fLandPosTop))
			{
				return true;
			}
		}else{
			return false;
		}
	}
	
	return false;
}

public int Native_IsLandCreated(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_liLand[iClient].bLandCreated;
}

public int Native_IsPositionInBox(Handle hPlugin, int iNumParams)
{
	float fCorner1[3], fCorner2[3], fPos[3];
	
	GetNativeArray(1, fPos, 3);
	GetNativeArray(2, fCorner1, 3);
	GetNativeArray(3, fCorner2, 3);
	
	float fEntity[3];
	float fField1[2];
	float fField2[2];
	float fField3[2];
	
	fEntity = fPos;
	
	//fEntity[2] += 25.0;
	
	if (FloatCompare(fCorner1[0], fCorner2[0]) == -1)
	{
		fField1[0] = fCorner1[0];
		fField1[1] = fCorner2[0];
	}
	else
	{
		fField1[0] = fCorner2[0];
		fField1[1] = fCorner1[0];
	}
	if (FloatCompare(fCorner1[1], fCorner2[1]) == -1)
	{
		fField2[0] = fCorner1[1];
		fField2[1] = fCorner2[1];
	}
	else
	{
		fField2[0] = fCorner2[1];
		fField2[1] = fCorner1[1];
	}
	if (FloatCompare(fCorner1[2], fCorner2[2]) == -1)
	{
		fField3[0] = fCorner1[2];
		fField3[1] = fCorner2[2];
	}
	else
	{
		fField3[0] = fCorner2[2];
		fField3[1] = fCorner1[2];
	}
	
	// Check the Vectors ...
	
	if (fEntity[0] < fField1[0] || fEntity[0] > fField1[1])
	{
		return false;
	}
	if (fEntity[1] < fField2[0] || fEntity[1] > fField2[1])
	{
		return false;
	}
	if (fEntity[2] < fField3[0] || fEntity[2] > fField3[1])
	{
		return false;
	}
	
	return true;
}

public void Native_SetLandGravity(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	g_liLand[iClient].fLandGravity = GetNativeCell(2);
}

public any Native_GetLandGravity(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_liLand[iClient].fLandGravity;
}

public int Native_GetCurrentLandEntity(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_iCurrentLandEntity[iClient];
}

public int Native_GetCurrentLandOwner(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_iCurrentLandOwner[iClient];
}

public void Native_SetCurrentLandEntity(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	g_iCurrentLandEntity[iClient] = GetNativeCell(2);
}

public void Native_SetCurrentLandOwner(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	g_iCurrentLandOwner[iClient] = GetNativeCell(2);
}

//Outputs:
public void EntOut_LandOnStartTouch(const char[] sOutput, int iCaller, int iActivator, float fDelay)
{
	if (iActivator < 1 || iActivator > MaxClients || !IsClientInGame(iActivator) || !IsPlayerAlive(iActivator))
	return;
	
	char sName[64];
	
	int iOwner = g_iLandEntOwner[iCaller];
	
	if(Cel_IsPlayer(iActivator))
	{
		GetClientName(iOwner, sName, sizeof(sName));
		
		if(!g_liLand[iActivator].bInsideLand)
		{
			Cel_PrintToChat(iActivator, "%t", "EnteredLand", sName);
		}
		
		g_liLand[iActivator].bInsideLand = true;
		
		Cel_SetCurrentLandEntity(iActivator, g_liLand[iOwner].iLandEntity);
		Cel_SetCurrentLandOwner(iActivator, g_liLand[iOwner].iLandOwner);
	}
}

public void EntOut_LandOnTrigger(const char[] sOutput, int iCaller, int iActivator, float fDelay)
{
	if (iActivator < 1 || iActivator > MaxClients || !IsClientInGame(iActivator) || !IsPlayerAlive(iActivator))
	return;
	
	int iOwner = g_iLandEntOwner[iCaller];
	
	if(Cel_IsPlayer(iActivator))
	{
		if(g_liLand[iActivator].bInsideLand)
		{
			SetEntityGravity(iActivator, Cel_GetLandGravity(iOwner));
			
			if(g_liLand[iOwner].bModeDeathmatch && !g_liLand[iActivator].bInDeathmatchMode)
			{
				SetEntProp(iActivator, Prop_Data, "m_takedamage", 2, 1);
				
				g_liLand[iActivator].bInDeathmatchMode = true;
				
				Cel_PrintToChat(iActivator, "%t", "LandMode_Deathmatch");
			}
			
			//Co-op: players can be hurt (by the world, NPCs and falls) but not by other players.
			if(g_liLand[iOwner].bModeCoop && !g_liLand[iActivator].bInCoopMode)
			{
				SetEntProp(iActivator, Prop_Data, "m_takedamage", 2, 1);
				
				g_liLand[iActivator].bInCoopMode = true;
				
				Cel_PrintToChat(iActivator, "%t", "LandMode_Coop");
			}
			
			//Update land modes; a mode that was switched off gives the player their own god mode back.
			if(!g_liLand[iOwner].bModeCoop && g_liLand[iActivator].bInCoopMode)
			{
				g_liLand[iActivator].bInCoopMode = false;
				
				Cel_SetNoKill(iActivator, Cel_GetNoKill(iActivator));
			}
			
			if(!g_liLand[iOwner].bModeDeathmatch && g_liLand[iActivator].bInDeathmatchMode)
			{
				g_liLand[iActivator].bInDeathmatchMode = false;
				
				Cel_SetNoKill(iActivator, Cel_GetNoKill(iActivator));
			}
			
			if(!g_liLand[iOwner].bModeShop && g_liLand[iActivator].bInShopMode)
			{
				g_liLand[iActivator].bInShopMode = false;
			}
		}
	}
}

public void EntOut_LandOnEndTouch(const char[] sOutput, int iCaller, int iActivator, float fDelay)
{
	if (iActivator < 1 || iActivator > MaxClients || !IsClientInGame(iActivator) || !IsPlayerAlive(iActivator))
	return;
	
	if(Cel_IsPlayer(iActivator))
	{
		g_liLand[iActivator].bInsideLand = false;
		
		Cel_SetCurrentLandEntity(iActivator, -1);
		Cel_SetCurrentLandOwner(iActivator, -1);
		
		SetEntityGravity(iActivator, 1.0);
		
		if(g_liLand[iActivator].bInDeathmatchMode || g_liLand[iActivator].bInCoopMode)
		{
			Cel_SetNoKill(iActivator, Cel_GetNoKill(iActivator));
			
			g_liLand[iActivator].bInDeathmatchMode = false;
			g_liLand[iActivator].bInCoopMode = false;
		}
	}
}

//Timers:
public Action Timer_GettingTop(Handle hTimer, any iPlayer)
{
	int iClient = GetClientOfUserId(iPlayer);
	
	if(g_liLand[iClient].bLandGettingTopPos)
	{
		Cel_GetCrosshairHitOrigin(iClient, g_liLand[iClient].fLandPosBottomTop);
		
		Handle hTraceRay = TR_TraceRayEx(g_liLand[iClient].fLandPosBottomTop, g_fUp, MASK_ALL, RayType_Infinite);
		
		if (TR_DidHit(hTraceRay))
		{
			TR_GetEndPosition(g_liLand[iClient].fLandPosTop, hTraceRay);
			
			CloseHandle(hTraceRay);
		}
		
		//Thank you Instakill.
		for(int x = 0; x < 2; x++)
		{
			if(g_liLand[iClient].fLandPosBottomTop[x] > g_liLand[iClient].fLandPosBottom[x] + g_fMaxLandSize) {
				g_liLand[iClient].fLandPosBottomTop[x] = g_liLand[iClient].fLandPosBottom[x] + g_fMaxLandSize;
			}
			if(g_liLand[iClient].fLandPosTop[x] > g_liLand[iClient].fLandPosBottom[x] + g_fMaxLandSize) {
				g_liLand[iClient].fLandPosTop[x] = g_liLand[iClient].fLandPosBottom[x] + g_fMaxLandSize;
			}
			
			if(g_liLand[iClient].fLandPosBottomTop[x] < g_liLand[iClient].fLandPosBottom[x] - g_fMaxLandSize) {
				g_liLand[iClient].fLandPosBottomTop[x] = g_liLand[iClient].fLandPosBottom[x] - g_fMaxLandSize;
			}
			if(g_liLand[iClient].fLandPosTop[x] < g_liLand[iClient].fLandPosBottom[x] - g_fMaxLandSize) {
				g_liLand[iClient].fLandPosTop[x] = g_liLand[iClient].fLandPosBottom[x] - g_fMaxLandSize;
			}
		}
	}
	
	return Plugin_Continue;
}

//In a co-op land, damage from another player does nothing.
public Action Hook_CoopDamage(int iVictim, int &iAttacker, int &iInflictor, float &fDamage, int &iDamageType)
{
	if (iVictim < 1 || iVictim > MaxClients || !g_liLand[iVictim].bInCoopMode)
	{
		return Plugin_Continue;
	}
	
	int iFrom = iAttacker;
	
	//Thrown props and grenades count as the player who threw them.
	if (iFrom > MaxClients && iInflictor > 0 && iInflictor <= MaxClients)
	{
		iFrom = iInflictor;
	}
	
	if (iFrom > 0 && iFrom <= MaxClients && iFrom != iVictim)
	{
		fDamage = 0.0;
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

//Land skins: materials/celmod/landskins/s1 to s26, drawn as flat tiles lying just above the land's floor.
void RemoveLandSkin(int iClient)
{
	for (int i = 0; i < g_alSkinTiles[iClient].Length; i++)
	{
		int iTile = EntRefToEntIndex(g_alSkinTiles[iClient].Get(i));

		if (iTile != INVALID_ENT_REFERENCE && iTile > MaxClients)
		{
			AcceptEntityInput(iTile, "kill");
		}
	}

	g_alSkinTiles[iClient].Clear();
}

void ApplyLandSkin(int iClient)
{
	char sMaterial[PLATFORM_MAX_PATH];
	float fAngles[3] = { -90.0, 0.0, 0.0 }, fMax[3], fMin[3], fPos[3];

	RemoveLandSkin(iClient);

	if (g_iLandSkin[iClient] < 1 || !g_liLand[iClient].bLandCreated)
	{
		return;
	}

	for (int k = 0; k < 3; k++)
	{
		fMin[k] = (g_liLand[iClient].fLandPosBottom[k] < g_liLand[iClient].fLandPosTop[k]) ? g_liLand[iClient].fLandPosBottom[k] : g_liLand[iClient].fLandPosTop[k];
		fMax[k] = (g_liLand[iClient].fLandPosBottom[k] < g_liLand[iClient].fLandPosTop[k]) ? g_liLand[iClient].fLandPosTop[k] : g_liLand[iClient].fLandPosBottom[k];
	}

	Format(sMaterial, sizeof(sMaterial), "celmod/landskins/s%d.vmt", g_iLandSkin[iClient]);

	float fTile = g_cvSkinTile.FloatValue;
	float fWidth = fMax[0] - fMin[0], fLength = fMax[1] - fMin[1];

	//Square tiles, overlapping a little where the land is not a whole number of tiles, so they cover it exactly.
	int iAcross = RoundToCeil(fWidth / fTile), iAlong = RoundToCeil(fLength / fTile);

	if (iAcross < 1) iAcross = 1;
	if (iAlong < 1) iAlong = 1;

	float fTileX = (fWidth < fTile) ? fWidth : fTile;
	float fTileY = (fLength < fTile) ? fLength : fTile;
	float fSize = (fTileX > fTileY) ? fTileX : fTileY;

	for (int x = 0; x < iAcross; x++)
	{
		for (int y = 0; y < iAlong; y++)
		{
			int iTile = CreateEntityByName("env_sprite_oriented");

			if (iTile == -1)
			{
				return;
			}

			fPos[0] = fMin[0] + fTileX * 0.5 + ((iAcross > 1) ? x * (fWidth - fTileX) / (iAcross - 1) : (fWidth - fTileX) * 0.5);
			fPos[1] = fMin[1] + fTileY * 0.5 + ((iAlong > 1) ? y * (fLength - fTileY) / (iAlong - 1) : (fLength - fTileY) * 0.5);

			//Just above the floor, each tile a hair apart in height so overlapping edges do not flicker.
			fPos[2] = fMin[2] + 1.0 + ((x + y) % 4) * 0.1;

			DispatchKeyValue(iTile, "model", sMaterial);
			DispatchKeyValue(iTile, "rendermode", "0");
			DispatchKeyValue(iTile, "renderamt", "255");
			DispatchKeyValue(iTile, "spawnflags", "1");
			DispatchKeyValue(iTile, "classname", "cel_landskin");
			DispatchKeyValueFloat(iTile, "scale", fSize / g_cvSkinTexture.FloatValue);

			DispatchSpawn(iTile);

			TeleportEntity(iTile, fPos, fAngles, NULL_VECTOR);

			AcceptEntityInput(iTile, "ShowSprite");

			g_alSkinTiles[iClient].Push(EntIndexToEntRef(iTile));
		}
	}
}

public Action Command_LandSkin(int iClient, int iArgs)
{
	char sArg[16], sDisplay[64];
	int iPrice;

	if (iClient < 1)
	{
		return Plugin_Handled;
	}

	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]landskin{default} <1-%d/off>", LANDSKIN_COUNT);
		return Plugin_Handled;
	}

	GetCmdArg(1, sArg, sizeof(sArg));

	if (StrEqual(sArg, "off", false) || StrEqual(sArg, "0"))
	{
		g_iLandSkin[iClient] = 0;

		Cel_SetClientSettingInt(iClient, "landskin", 0);

		RemoveLandSkin(iClient);

		Cel_ReplyToCommand(iClient, "Your land skin has been removed.");

		return Plugin_Handled;
	}

	int iSkin = StringToInt(sArg);

	if (iSkin < 1 || iSkin > LANDSKIN_COUNT)
	{
		Cel_ReplyToCommand(iClient, "Land skins go from {green}1{default} to {green}%d{default}.", LANDSKIN_COUNT);
		return Plugin_Handled;
	}

	//Land skins are bought once in the shop, when the shop sells them.
	if (Cel_CheckShopDB("landskin", iPrice, sDisplay, sizeof(sDisplay)) && !Cel_CheckClientPurchase(iClient, "landskin"))
	{
		Cel_ReplyToCommand(iClient, "Land skins cost {green}%d CL{default}. Buy them with {green}[tag]buy landskin{default}.", iPrice);
		return Plugin_Handled;
	}

	g_iLandSkin[iClient] = iSkin;

	Cel_SetClientSettingInt(iClient, "landskin", iSkin);

	if (!g_liLand[iClient].bLandCreated)
	{
		Cel_ReplyToCommand(iClient, "Land skin {green}%d{default} chosen. It will cover your land once you make one with {green}[tag]land{default}.", iSkin);
		return Plugin_Handled;
	}

	ApplyLandSkin(iClient);

	Cel_ReplyToCommand(iClient, "Your land now has land skin {green}%d{default}.", iSkin);

	return Plugin_Handled;
}

public Action Command_LandColor(int iClient, int iArgs)
{
	char sColor[64], sColorBuffer[3][8], sColorString[32];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]landcolor{default} <color/off>");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sColor, sizeof(sColor));
	
	if (StrEqual(sColor, "off", false) || StrEqual(sColor, "none", false))
	{
		g_bLandColor[iClient] = false;
		
		Cel_ReplyToCommand(iClient, "Your land's border uses your HUD color again.");
		
		return Plugin_Handled;
	}
	
	if (!Cel_CheckColorDB(sColor, sColorString, sizeof(sColorString)))
	{
		Cel_ReplyToCommand(iClient, "There is no color called {green}%s{default}. Type {green}[tag]colorlist{default} to see them.", sColor);
		return Plugin_Handled;
	}
	
	ExplodeString(sColorString, "|", sColorBuffer, 3, sizeof(sColorBuffer[]));
	
	g_bLandColor[iClient] = true;
	g_iLandColor[iClient][0] = StringToInt(sColorBuffer[0]);
	g_iLandColor[iClient][1] = StringToInt(sColorBuffer[1]);
	g_iLandColor[iClient][2] = StringToInt(sColorBuffer[2]);
	
	Cel_ReplyToCommand(iClient, "Your land's border is now {green}%s{default}.", sColor);
	
	return Plugin_Handled;
}

public Action Timer_Land(Handle hTimer, any iPlayer)
{
	int iClient = GetClientOfUserId(iPlayer), iColor[4];
	
	Cel_GetHudColor(iClient, iColor);
	
	//A color chosen with !landcolor replaces the HUD color for the land's border.
	if (iClient > 0 && g_bLandColor[iClient])
	{
		iColor[0] = g_iLandColor[iClient][0];
		iColor[1] = g_iLandColor[iClient][1];
		iColor[2] = g_iLandColor[iClient][2];
	}
	
	if(g_liLand[iClient].bLandDrawing)
	{
		Cel_DrawLandBorders(g_liLand[iClient].fLandPosStarting, g_liLand[iClient].fLandPosTop, 0.1, iColor, true);
	}
	
	return Plugin_Continue;
}

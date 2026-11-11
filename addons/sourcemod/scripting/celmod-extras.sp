#pragma semicolon 1

#include <celmod>

#pragma newdecls required

/*
 * |CelMod| Extras
 *
 * Smaller commands from the original server's command list that do not belong to another plugin.
 */

ArrayList g_alUndo[MAXPLAYERS + 1];

bool g_bHide[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool g_bHideHooked[MAXENTITIES + 1];
bool g_bLandBan[MAXPLAYERS + 1][MAXPLAYERS + 1];

char g_sMessage[MAXENTITIES + 1][192];
char g_sSound[MAXENTITIES + 1][PLATFORM_MAX_PATH];
char g_sSoundDB[PLATFORM_MAX_PATH];

float g_fLandKickUntil[MAXPLAYERS + 1][MAXPLAYERS + 1];
float g_fNextBanNotice[MAXPLAYERS + 1];
float g_fNextSoundUse[MAXENTITIES + 1];

int g_iMoveToRef[MAXPLAYERS + 1];
int g_iTrackOwner[MAXENTITIES + 1];
int g_iWeldRef[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "|CelMod| Extras",
	author = CEL_AUTHOR,
	description = "Extra player and land commands from the original command list.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	LoadTranslations("celmod.phrases");
	LoadTranslations("common.phrases");
	
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_iMoveToRef[i] = INVALID_ENT_REFERENCE;
		g_iWeldRef[i] = INVALID_ENT_REFERENCE;
		g_alUndo[i] = new ArrayList();
	}
	
	BuildPath(Path_SM, g_sSoundDB, sizeof(g_sSoundDB), "data/celmod/sounds.txt");
	
	CreateTimer(0.5, Timer_LandBans, _, TIMER_REPEAT);
	
	RegConsoleCmd("v_hide", Command_Hide, "|CelMod| Hides another player's entities from your view.");
	RegConsoleCmd("v_landban", Command_LandBan, "|CelMod| Bans a player from your land.");
	RegConsoleCmd("v_landunban", Command_LandUnban, "|CelMod| Lets a banned player back into your land.");
	RegConsoleCmd("v_message", Command_Message, "|CelMod| Spawns a message cel that shows your text to whoever uses it.");
	RegConsoleCmd("v_release", Command_Release, "|CelMod| Releases the entity you are looking at from a weld.");
	RegConsoleCmd("v_show", Command_Show, "|CelMod| Shows a hidden player's entities again.");
	RegConsoleCmd("v_sound", Command_Sound, "|CelMod| Spawns a sound cel that plays a sound when used.");
	RegConsoleCmd("v_undo", Command_Undo, "|CelMod| Removes the last entity you spawned.");
	RegConsoleCmd("v_weld", Command_Weld, "|CelMod| Welds one of your entities to another so they move together.");
	RegConsoleCmd("v_clear", Command_Clear, "|CelMod| Deletes one of your saved builds.");
	RegConsoleCmd("v_fire", Command_Fire, "|CelMod| Spawns a fire effect cel.");
	RegConsoleCmd("v_landkick", Command_LandKick, "|CelMod| Kicks a player out of your land for 10 seconds.");
	RegConsoleCmd("v_landslay", Command_LandSlay, "|CelMod| Slays a player, or everyone, inside your land.");
	RegConsoleCmd("v_moveto", Command_MoveTo, "|CelMod| Moves one of your entities onto another entity.");
	RegConsoleCmd("v_noclip", Command_NoClip, "|CelMod| Enables/disables noclip on the player.");
	RegConsoleCmd("v_stuck", Command_Stuck, "|CelMod| Respawns you.");
	RegConsoleCmd("v_turn", Command_Turn, "|CelMod| Rotates the prop you are looking at.");
	RegConsoleCmd("v_weps", Command_Weps, "|CelMod| Gives you every weapon.");
}

public void OnClientPutInServer(int iClient)
{
	g_iMoveToRef[iClient] = INVALID_ENT_REFERENCE;
	g_iWeldRef[iClient] = INVALID_ENT_REFERENCE;
	g_fNextBanNotice[iClient] = 0.0;
	
	g_alUndo[iClient].Clear();
	
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_bHide[iClient][i] = false;
		g_bHide[i][iClient] = false;
		g_bLandBan[iClient][i] = false;
		g_bLandBan[i][iClient] = false;
		g_fLandKickUntil[iClient][i] = 0.0;
		g_fLandKickUntil[i][iClient] = 0.0;
	}
}

public void OnMapStart()
{
	for (int i = 0; i <= MAXENTITIES; i++)
	{
		g_bHideHooked[i] = false;
		g_iTrackOwner[i] = 0;
		g_sMessage[i][0] = '\0';
		g_sSound[i][0] = '\0';
	}
	
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_alUndo[i].Clear();
	}
}

//Every CelMod entity is noted a frame after it is created, once its owner has been set.
public void OnEntityCreated(int iEntity, const char[] sClassname)
{
	if (iEntity > MaxClients && iEntity <= MAXENTITIES)
	{
		g_bHideHooked[iEntity] = false;
		g_iTrackOwner[iEntity] = 0;
		g_sMessage[iEntity][0] = '\0';
		g_sSound[iEntity][0] = '\0';
		
		RequestFrame(Frame_TrackEntity, EntIndexToEntRef(iEntity));
	}
}

public void Frame_TrackEntity(any iRef)
{
	int iEntity = EntRefToEntIndex(iRef);
	
	if (iEntity == INVALID_ENT_REFERENCE || iEntity <= MaxClients || iEntity > MAXENTITIES || !Cel_IsEntity(iEntity))
	{
		return;
	}
	
	int iOwner = Cel_GetOwner(iEntity);
	
	if (iOwner < 1 || iOwner > MaxClients)
	{
		return;
	}
	
	g_iTrackOwner[iEntity] = iOwner;
	
	g_alUndo[iOwner].Push(iRef);
	
	//Keeps the list from growing without end on a long session.
	if (g_alUndo[iOwner].Length > 512)
	{
		g_alUndo[iOwner].Erase(0);
	}
	
	UpdateHideHook(iEntity);
}

public void Cel_OnEntityOwnerChanged(int iEntity, int iOldOwner, int iNewOwner)
{
	if (iEntity > MaxClients && iEntity <= MAXENTITIES)
	{
		g_iTrackOwner[iEntity] = iNewOwner;
		
		UpdateHideHook(iEntity);
	}
}

//An entity is only hooked while somebody is hiding its owner, the hook runs for every player every tick.
void UpdateHideHook(int iEntity)
{
	bool bNeeded = false;
	int iOwner = g_iTrackOwner[iEntity];
	
	if (iOwner > 0)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_bHide[i][iOwner])
			{
				bNeeded = true;
				break;
			}
		}
	}
	
	if (bNeeded && !g_bHideHooked[iEntity])
	{
		g_bHideHooked[iEntity] = true;
		
		SDKHook(iEntity, SDKHook_SetTransmit, Hook_HideTransmit);
	} else if (!bNeeded && g_bHideHooked[iEntity])
	{
		g_bHideHooked[iEntity] = false;
		
		SDKUnhook(iEntity, SDKHook_SetTransmit, Hook_HideTransmit);
	}
}

void UpdateHideHooksFor(int iOwner)
{
	for (int i = MaxClients + 1; i <= MAXENTITIES; i++)
	{
		if (g_iTrackOwner[i] == iOwner && IsValidEntity(i))
		{
			UpdateHideHook(i);
		}
	}
}

public Action Hook_HideTransmit(int iEntity, int iClient)
{
	if (iClient > 0 && iClient <= MaxClients && iEntity > 0 && iEntity <= MAXENTITIES && g_bHide[iClient][g_iTrackOwner[iEntity]])
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

//Banned and recently kicked players are sent back to a spawn point when they step into the land.
public Action Timer_LandBans(Handle hTimer)
{
	float fOrigin[3];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}
		
		GetClientAbsOrigin(i, fOrigin);
		
		fOrigin[2] += 16.0;
		
		int iOwner = Cel_GetLandOwnerFromPosition(fOrigin);
		
		if (iOwner < 1 || iOwner > MaxClients || iOwner == i || !Cel_IsPlayer(iOwner) || !Cel_IsLandCreated(iOwner))
		{
			continue;
		}
		
		if (g_bLandBan[iOwner][i] || GetGameTime() < g_fLandKickUntil[iOwner][i])
		{
			DispatchSpawn(i);
			
			if (GetGameTime() >= g_fNextBanNotice[i])
			{
				g_fNextBanNotice[i] = GetGameTime() + 5.0;
				
				Cel_PrintToChat(i, "You are not allowed inside {green}%N{default}'s land.", iOwner);
			}
		}
	}
	
	return Plugin_Continue;
}

public void Hook_MessageUse(int iEntity, int iActivator, int iCaller, UseType utType, float fValue)
{
	if (iActivator > 0 && iActivator <= MaxClients && IsClientInGame(iActivator) && g_sMessage[iEntity][0] != '\0')
	{
		Cel_PrintToChat(iActivator, "Message from {green}%N{default}: %s", Cel_GetOwner(iEntity), g_sMessage[iEntity]);
	}
}

public void Hook_SoundUse(int iEntity, int iActivator, int iCaller, UseType utType, float fValue)
{
	if (g_sSound[iEntity][0] == '\0' || GetGameTime() < g_fNextSoundUse[iEntity] || Cel_IsLocked(iEntity))
	{
		return;
	}
	
	g_fNextSoundUse[iEntity] = GetGameTime() + 1.0;
	
	EmitSoundToAll(g_sSound[iEntity], iEntity);
}

//Spawns a usable prop at the client's crosshair for the message and sound cels.
int SpawnUsableProp(int iClient, const char[] sAlias, const char[] sModel)
{
	float fAngles[3], fOrigin[3];
	
	if (!Cel_CheckPropCount(iClient))
	{
		Cel_ReplyToCommand(iClient, "You have reached your prop limit.");
		return -1;
	}
	
	Cel_GetCrosshairHitOrigin(iClient, fOrigin);
	
	GetClientAbsAngles(iClient, fAngles);
	
	fAngles[0] = 0.0;
	fAngles[1] += 180.0;
	
	int iProp = Cel_SpawnProp(iClient, sAlias, "prop_physics_override", sModel, fAngles, fOrigin, 255, 255, 255, 255);
	
	if (iProp == -1)
	{
		return -1;
	}
	
	Cel_FixSpawnPosition(iProp, fOrigin);
	
	//Lets players press E on it.
	SetEntProp(iProp, Prop_Data, "m_spawnflags", GetEntProp(iProp, Prop_Data, "m_spawnflags") | 256);
	
	return iProp;
}

//Runs another CelMod command for the client, replying the same way this command was used.
void RunCelCommand(int iClient, const char[] sCommand)
{
	ReplySource rsOldReplySrc = GetCmdReplySource();
	
	SetCmdReplySource(SM_REPLY_TO_CHAT);
	
	FakeClientCommand(iClient, "%s", sCommand);
	
	SetCmdReplySource(rsOldReplySrc);
}

bool IsInLandOf(int iPlayer, int iLandOwner)
{
	float fOrigin[3];
	
	if (!IsClientInGame(iPlayer) || !IsPlayerAlive(iPlayer))
	{
		return false;
	}
	
	GetClientAbsOrigin(iPlayer, fOrigin);
	
	fOrigin[2] += 16.0;
	
	return (Cel_GetLandOwnerFromPosition(fOrigin) == iLandOwner);
}

//Commands:
public Action Command_Clear(int iClient, int iArgs)
{
	char sAuthID[64], sFile[PLATFORM_MAX_PATH], sSaveName[64];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]clear{default} <build>");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sSaveName, sizeof(sSaveName));
	
	//A build name is a file name, so nothing that could leave the saves folder is accepted.
	for (int i = 0; sSaveName[i] != '\0'; i++)
	{
		if (!IsCharAlpha(sSaveName[i]) && !IsCharNumeric(sSaveName[i]) && sSaveName[i] != '_' && sSaveName[i] != '-')
		{
			Cel_ReplyToCommand(iClient, "Build names can only contain letters, numbers, {green}_{default} and {green}-{default}.");
			return Plugin_Handled;
		}
	}
	
	Cel_GetAuthID(iClient, sAuthID, sizeof(sAuthID));
	
	BuildPath(Path_SM, sFile, sizeof(sFile), "data/celmod/users/%s/saves/%s.txt", sAuthID, sSaveName);
	
	if (!FileExists(sFile))
	{
		Cel_ReplyToCommand(iClient, "You do not have a build called {green}%s{default}.", sSaveName);
		return Plugin_Handled;
	}
	
	if (DeleteFile(sFile))
	{
		Cel_ReplyToCommand(iClient, "Deleted your build {green}%s{default}.", sSaveName);
	} else {
		Cel_ReplyToCommand(iClient, "The build {green}%s{default} could not be deleted.", sSaveName);
	}
	
	return Plugin_Handled;
}

public Action Command_Fire(int iClient, int iArgs)
{
	if (iClient > 0)
	{
		RunCelCommand(iClient, "v_effect fire");
	}
	
	return Plugin_Handled;
}

public Action Command_NoClip(int iClient, int iArgs)
{
	if (iClient > 0)
	{
		RunCelCommand(iClient, "v_fly");
	}
	
	return Plugin_Handled;
}

public Action Command_Turn(int iClient, int iArgs)
{
	char sCommand[64], sDegree[32];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]turn{default} <degrees>");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sDegree, sizeof(sDegree));
	
	Format(sCommand, sizeof(sCommand), "v_r %d", StringToInt(sDegree));
	
	RunCelCommand(iClient, sCommand);
	
	return Plugin_Handled;
}

//Used twice: first on the entity to move, then on the entity to move it to.
public Action Command_MoveTo(int iClient, int iArgs)
{
	float fOrigin[3];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	int iProp = Cel_GetClientAimTarget(iClient);
	
	if (iProp == -1)
	{
		Cel_NotLooking(iClient);
		return Plugin_Handled;
	}
	
	int iMoving = EntRefToEntIndex(g_iMoveToRef[iClient]);
	
	if (g_iMoveToRef[iClient] == INVALID_ENT_REFERENCE || iMoving == INVALID_ENT_REFERENCE || !Cel_CheckOwner(iClient, iMoving))
	{
		if (!Cel_CheckOwner(iClient, iProp))
		{
			Cel_NotYours(iClient, iProp);
			return Plugin_Handled;
		}
		
		g_iMoveToRef[iClient] = EntIndexToEntRef(iProp);
		
		Cel_ChangeBeam(iClient, iProp);
		
		Cel_ReplyToCommandEntity(iClient, iProp, "Selected this [type]. Now look at the entity to move it to and type {green}[tag]moveto{default} again.");
		
		return Plugin_Handled;
	}
	
	g_iMoveToRef[iClient] = INVALID_ENT_REFERENCE;
	
	if (iMoving == iProp)
	{
		Cel_ReplyToCommand(iClient, "Move cancelled.");
		return Plugin_Handled;
	}
	
	Cel_GetEntityOrigin(iProp, fOrigin);
	
	TeleportEntity(iMoving, fOrigin, NULL_VECTOR, NULL_VECTOR);
	
	Cel_ChangeBeam(iClient, iMoving);
	
	Cel_ReplyToCommandEntity(iClient, iMoving, "Moved your [type] to the other entity.");
	
	return Plugin_Handled;
}

public Action Command_Stuck(int iClient, int iArgs)
{
	if (iClient > 0 && IsClientInGame(iClient))
	{
		DispatchSpawn(iClient);
		
		Cel_ReplyToCommand(iClient, "You have been respawned.");
	}
	
	return Plugin_Handled;
}

public Action Command_Weps(int iClient, int iArgs)
{
	static const char sWeapons[][] = 
	{
		"weapon_crowbar", "weapon_stunstick", "weapon_physcannon", "weapon_pistol", "weapon_357", "weapon_smg1", 
		"weapon_ar2", "weapon_shotgun", "weapon_crossbow", "weapon_frag", "weapon_rpg", "weapon_slam"
	};
	float fOrigin[3];
	
	if (iClient < 1 || !IsClientInGame(iClient) || !IsPlayerAlive(iClient))
	{
		return Plugin_Handled;
	}
	
	GetClientAbsOrigin(iClient, fOrigin);
	
	fOrigin[2] += 16.0;
	
	int iLandOwner = Cel_GetLandOwnerFromPosition(fOrigin);
	
	//Weapons are for outside of lands, a land owner decides what happens inside theirs.
	if (iLandOwner > 0 && iLandOwner != iClient && Cel_IsPlayer(iLandOwner) && Cel_IsLandCreated(iLandOwner))
	{
		Cel_ReplyToCommand(iClient, "You cannot use {green}[tag]weps{default} inside another player's land.");
		return Plugin_Handled;
	}
	
	for (int i = 0; i < sizeof(sWeapons); i++)
	{
		GivePlayerItem(iClient, sWeapons[i]);
	}
	
	Cel_ReplyToCommand(iClient, "You have been given every weapon.");
	
	return Plugin_Handled;
}

public Action Command_LandSlay(int iClient, int iArgs)
{
	char sTarget[MAX_NAME_LENGTH];
	int iCount = 0;
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]landslay{default} <player/#all>");
		return Plugin_Handled;
	}
	
	if (!Cel_IsLandCreated(iClient))
	{
		Cel_ReplyToCommand(iClient, "%t", "LandNotStarted");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	if (StrEqual(sTarget, "#all", false))
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (i != iClient && IsInLandOf(i, iClient))
			{
				ForcePlayerSuicide(i);
				
				iCount++;
			}
		}
		
		Cel_ReplyToCommand(iClient, "Slayed {green}%d{default} player%s inside your land.", iCount, iCount == 1 ? "" : "s");
		
		return Plugin_Handled;
	}
	
	int iTarget = FindTarget(iClient, sTarget, true, false);
	
	if (iTarget == -1)
	{
		return Plugin_Handled;
	}
	
	if (!IsInLandOf(iTarget, iClient))
	{
		Cel_ReplyToCommand(iClient, "{green}%N{default} is not inside your land.", iTarget);
		return Plugin_Handled;
	}
	
	ForcePlayerSuicide(iTarget);
	
	Cel_ReplyToCommand(iClient, "Slayed {green}%N{default} inside your land.", iTarget);
	
	return Plugin_Handled;
}

public Action Command_LandKick(int iClient, int iArgs)
{
	char sTarget[MAX_NAME_LENGTH];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]landkick{default} <player>");
		return Plugin_Handled;
	}
	
	if (!Cel_IsLandCreated(iClient))
	{
		Cel_ReplyToCommand(iClient, "%t", "LandNotStarted");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	int iTarget = FindTarget(iClient, sTarget, true, false);
	
	if (iTarget == -1 || iTarget == iClient)
	{
		return Plugin_Handled;
	}
	
	if (!IsInLandOf(iTarget, iClient))
	{
		Cel_ReplyToCommand(iClient, "{green}%N{default} is not inside your land.", iTarget);
		return Plugin_Handled;
	}
	
	//Sends the player back to a spawn point and keeps them out for 10 seconds.
	g_fLandKickUntil[iClient][iTarget] = GetGameTime() + 10.0;
	
	DispatchSpawn(iTarget);
	
	Cel_PrintToChat(iTarget, "You were kicked out of {green}%N{default}'s land for 10 seconds.", iClient);
	Cel_ReplyToCommand(iClient, "Kicked {green}%N{default} out of your land for 10 seconds.", iTarget);
	
	return Plugin_Handled;
}

public Action Command_Undo(int iClient, int iArgs)
{
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	while (g_alUndo[iClient].Length > 0)
	{
		int iLast = g_alUndo[iClient].Length - 1;
		int iEntity = EntRefToEntIndex(g_alUndo[iClient].Get(iLast));
		
		g_alUndo[iClient].Erase(iLast);
		
		if (iEntity != INVALID_ENT_REFERENCE && iEntity > MaxClients && Cel_CheckOwner(iClient, iEntity))
		{
			Cel_RemovalBeam(iClient, iEntity);
			
			Cel_ReplyToCommandEntity(iClient, iEntity, "Removed the last [type] you spawned.");
			
			Cel_DissolveEntity(iEntity);
			
			return Plugin_Handled;
		}
	}
	
	Cel_ReplyToCommand(iClient, "There is nothing left to undo.");
	
	return Plugin_Handled;
}

public Action Command_Hide(int iClient, int iArgs)
{
	return SetHidden(iClient, iArgs, true);
}

public Action Command_Show(int iClient, int iArgs)
{
	return SetHidden(iClient, iArgs, false);
}

Action SetHidden(int iClient, int iArgs, bool bHide)
{
	char sTarget[MAX_NAME_LENGTH];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]%s{default} <player>", bHide ? "hide" : "show");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	int iTarget = FindTarget(iClient, sTarget, true, false);
	
	if (iTarget == -1 || iTarget == iClient)
	{
		return Plugin_Handled;
	}
	
	g_bHide[iClient][iTarget] = bHide;
	
	UpdateHideHooksFor(iTarget);
	
	Cel_ReplyToCommand(iClient, bHide ? "You no longer see {green}%N{default}'s entities. They are still solid." : "You can see {green}%N{default}'s entities again.", iTarget);
	
	return Plugin_Handled;
}

//Used twice: first on the entity to attach, then on the entity it should follow.
public Action Command_Weld(int iClient, int iArgs)
{
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	int iProp = Cel_GetClientAimTarget(iClient);
	
	if (iProp == -1)
	{
		Cel_NotLooking(iClient);
		return Plugin_Handled;
	}
	
	if (!Cel_CheckOwner(iClient, iProp))
	{
		Cel_NotYours(iClient, iProp);
		return Plugin_Handled;
	}
	
	int iFirst = EntRefToEntIndex(g_iWeldRef[iClient]);
	
	if (g_iWeldRef[iClient] == INVALID_ENT_REFERENCE || iFirst == INVALID_ENT_REFERENCE || !Cel_CheckOwner(iClient, iFirst))
	{
		g_iWeldRef[iClient] = EntIndexToEntRef(iProp);
		
		Cel_ChangeBeam(iClient, iProp);
		
		Cel_ReplyToCommandEntity(iClient, iProp, "Selected this [type]. Now look at the entity it should be welded to and type {green}[tag]weld{default} again.");
		
		return Plugin_Handled;
	}
	
	g_iWeldRef[iClient] = INVALID_ENT_REFERENCE;
	
	if (iFirst == iProp || GetEntPropEnt(iProp, Prop_Data, "m_hMoveParent") == iFirst)
	{
		Cel_ReplyToCommand(iClient, "Weld cancelled.");
		return Plugin_Handled;
	}
	
	SetVariantString("!activator");
	AcceptEntityInput(iFirst, "SetParent", iProp, iFirst);
	
	Cel_ChangeBeam(iClient, iFirst);
	
	Cel_ReplyToCommandEntity(iClient, iFirst, "Welded your [type]. It now moves with the other entity. Welds are not saved with builds.");
	
	return Plugin_Handled;
}

public Action Command_Release(int iClient, int iArgs)
{
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	int iProp = Cel_GetClientAimTarget(iClient);
	
	if (iProp == -1)
	{
		Cel_NotLooking(iClient);
		return Plugin_Handled;
	}
	
	if (!Cel_CheckOwner(iClient, iProp))
	{
		Cel_NotYours(iClient, iProp);
		return Plugin_Handled;
	}
	
	if (GetEntPropEnt(iProp, Prop_Data, "m_hMoveParent") == -1)
	{
		Cel_ReplyToCommandEntity(iClient, iProp, "This [type] is not welded to anything.");
		return Plugin_Handled;
	}
	
	AcceptEntityInput(iProp, "ClearParent");
	
	Cel_ChangeBeam(iClient, iProp);
	
	Cel_ReplyToCommandEntity(iClient, iProp, "Released your [type] from its weld.");
	
	return Plugin_Handled;
}

public Action Command_LandBan(int iClient, int iArgs)
{
	return SetLandBan(iClient, iArgs, true);
}

public Action Command_LandUnban(int iClient, int iArgs)
{
	return SetLandBan(iClient, iArgs, false);
}

Action SetLandBan(int iClient, int iArgs, bool bBan)
{
	char sTarget[MAX_NAME_LENGTH];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]%s{default} <player>", bBan ? "landban" : "landunban");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	int iTarget = FindTarget(iClient, sTarget, true, false);
	
	if (iTarget == -1 || iTarget == iClient)
	{
		return Plugin_Handled;
	}
	
	g_bLandBan[iClient][iTarget] = bBan;
	g_fLandKickUntil[iClient][iTarget] = 0.0;
	
	if (bBan)
	{
		Cel_PrintToChat(iTarget, "{green}%N{default} has banned you from their land.", iClient);
		Cel_ReplyToCommand(iClient, "{green}%N{default} is banned from your land until they or you leave the server.", iTarget);
	} else {
		Cel_PrintToChat(iTarget, "{green}%N{default} has let you back into their land.", iClient);
		Cel_ReplyToCommand(iClient, "{green}%N{default} can enter your land again.", iTarget);
	}
	
	return Plugin_Handled;
}

public Action Command_Message(int iClient, int iArgs)
{
	char sText[192];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);
	TrimString(sText);
	
	if (sText[0] == '\0')
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]message{default} <message>");
		return Plugin_Handled;
	}
	
	int iProp = SpawnUsableProp(iClient, "message", "models/props_lab/clipboard.mdl");
	
	if (iProp == -1)
	{
		return Plugin_Handled;
	}
	
	strcopy(g_sMessage[iProp], sizeof(g_sMessage[]), sText);
	
	SDKHook(iProp, SDKHook_UsePost, Hook_MessageUse);
	
	Cel_ReplyToCommand(iClient, "Spawned a message cel. Players read it by pressing {green}E{default} on it. It is not saved with builds.");
	
	return Plugin_Handled;
}

public Action Command_Sound(int iClient, int iArgs)
{
	char sName[64], sPath[PLATFORM_MAX_PATH];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]sound{default} <sound name>");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sName, sizeof(sName));
	
	KeyValues kvSounds = new KeyValues("Sounds");
	
	kvSounds.ImportFromFile(g_sSoundDB);
	kvSounds.JumpToKey("Sounds", false);
	kvSounds.GetString(sName, sPath, sizeof(sPath), "");
	
	delete kvSounds;
	
	if (sPath[0] == '\0')
	{
		Cel_ReplyToCommand(iClient, "There is no sound called {green}%s{default}.", sName);
		return Plugin_Handled;
	}
	
	int iProp = SpawnUsableProp(iClient, "sound", "models/props_lab/citizenradio.mdl");
	
	if (iProp == -1)
	{
		return Plugin_Handled;
	}
	
	PrecacheSound(sPath);
	
	strcopy(g_sSound[iProp], sizeof(g_sSound[]), sPath);
	
	g_fNextSoundUse[iProp] = 0.0;
	
	SDKHook(iProp, SDKHook_UsePost, Hook_SoundUse);
	
	Cel_ReplyToCommand(iClient, "Spawned a {green}%s{default} sound cel. Press {green}E{default} on it to play it. It is not saved with builds.", sName);
	
	return Plugin_Handled;
}

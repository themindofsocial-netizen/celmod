#pragma semicolon 1

#include <celmod>

#pragma newdecls required

/*
 * |CelMod| Extras
 *
 * Smaller commands from the original server's command list that do not belong to another plugin.
 */

int g_iMoveToRef[MAXPLAYERS + 1];

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
	}
	
	RegConsoleCmd("v_clear", Command_Clear, "|CelMod| Deletes one of your saved builds.");
	RegConsoleCmd("v_fire", Command_Fire, "|CelMod| Spawns a fire effect cel.");
	RegConsoleCmd("v_landkick", Command_LandKick, "|CelMod| Respawns a player who is inside your land.");
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
	
	//Sends the player back to a spawn point.
	DispatchSpawn(iTarget);
	
	Cel_PrintToChat(iTarget, "You were kicked out of {green}%N{default}'s land.", iClient);
	Cel_ReplyToCommand(iClient, "Kicked {green}%N{default} out of your land.", iTarget);
	
	return Plugin_Handled;
}

#pragma semicolon 1

#include <celmod>
#include <SteamWorks>

#pragma newdecls required

/*
 * |CelMod| Game Name
 *
 * Shows |CM| in the server browser's Game column instead of "Half-Life 2 Deathmatch", like the original server.
 * Steam's server list takes the name from the SteamWorks extension, so this plugin requires it: loading this plugin
 * makes SourceMod load SteamWorks, and if SteamWorks can't load, only this plugin fails (the reason is in
 * SourceMod's error log and in "sm exts list"). SourceMod's own SDKHooks also answers direct server queries with it.
 */

ConVar g_cvGameName;

public Plugin myinfo =
{
	name = "|CelMod| Game Name",
	author = CEL_AUTHOR,
	description = "Shows |CM| as the game in the server browser.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	g_cvGameName = CreateConVar("cm_game_description", "|CM|", "Game name shown in the server browser. Empty leaves the game's own.");
	g_cvGameName.AddChangeHook(OnGameNameChanged);

	RegAdminCmd("cm_gamename_status", Command_Status, ADMFLAG_ROOT, "|CelMod| Shows whether the server browser game name is being set.");

	// Steam can reset it on a map change, so it is set again now and then.
	CreateTimer(60.0, Timer_ApplyGameName, _, TIMER_REPEAT);
}

public void OnConfigsExecuted()
{
	ApplyGameName();
}

public void SteamWorks_SteamServersConnected()
{
	ApplyGameName();
}

public void OnGameNameChanged(ConVar cvConVar, const char[] sOldValue, const char[] sNewValue)
{
	ApplyGameName();
}

public Action Timer_ApplyGameName(Handle hTimer)
{
	ApplyGameName();

	return Plugin_Continue;
}

void ApplyGameName()
{
	char sName[64];

	g_cvGameName.GetString(sName, sizeof(sName));

	if (sName[0] != '\0')
	{
		SteamWorks_SetGameDescription(sName);
	}
}

public Action OnGetGameDescription(char sGameDesc[64])
{
	char sName[64];

	g_cvGameName.GetString(sName, sizeof(sName));

	if (sName[0] == '\0')
	{
		return Plugin_Continue;
	}

	strcopy(sGameDesc, sizeof(sGameDesc), sName);

	return Plugin_Changed;
}

public Action Command_Status(int iClient, int iArgs)
{
	char sName[64];

	g_cvGameName.GetString(sName, sizeof(sName));

	ReplyToCommand(iClient, "|CelMod| Game name: \"%s\". SteamWorks connected to Steam: %s.", sName, SteamWorks_IsConnected() ? "yes" : "no (the name is sent once it connects)");

	ApplyGameName();

	return Plugin_Handled;
}

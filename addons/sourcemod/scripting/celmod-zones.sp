#pragma semicolon 1

#include <celmod>

#pragma newdecls required

/*
 * |CelMod| Zones
 *
 * Admin made areas of a map, saved per map in data/celmod/zones/<map>.txt.
 *
 * Restricted area - flying (noclip) inside it kills you, and !fly, !noclip and !land are refused inside it.
 *				   Getting in on foot or through a map teleporter is fine.
 * Event area	  - the same, and no building command works inside it at all. Emblems give no help moving inside it
 *				   (speed, sprint, gravity, jump, feather), and nobody can phase, blink, open portals or take a
 *				   teleport pad into either kind of area. Put event emblems (!eventemblem) at the end of the course.
 *
 * Admins (slay flag) are never affected.
 */

#define MAX_ZONES 64

#define ZONE_RESTRICTED 0
#define ZONE_EVENT 1

bool g_bCornerSet[MAXPLAYERS + 1];

char g_sMap[64];
char g_sZoneDB[PLATFORM_MAX_PATH];
char g_sZoneName[MAX_ZONES][48];

float g_fCorner[MAXPLAYERS + 1][3];
float g_fNextNotice[MAXPLAYERS + 1];
float g_fZoneMax[MAX_ZONES][3];
float g_fZoneMin[MAX_ZONES][3];

int g_iBeam = -1;
int g_iPendingType[MAXPLAYERS + 1];
int g_iZoneCount;
int g_iZoneType[MAX_ZONES];

//Commands that still work inside an event area. Everything else that starts with v_ is a building command.
char g_sEventAllowed[][] = 
{
	"v_balance", "v_buy", "v_cl", "v_emblems", "v_hats", "v_weapons", "v_inventory", "v_thirdperson", "v_firstperson", "v_stuck", 
	"v_owner", "v_commandlist", "v_cmds", "v_commands", "v_updates", "v_updatelist", "v_switch", "v_guess", "v_bid", 
	"v_playermodel", "v_playermodels", "v_buymodel", "v_emblem", "v_hat", "v_weapon", "v_zones", "v_celmusic", "v_block"
};

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	CreateNative("Cel_GetZoneType", Native_GetZoneType);
	
	RegPluginLibrary("celmod_zones");
	
	return APLRes_Success;
}

//Which kind of area a point is in: CEL_ZONE_NONE, CEL_ZONE_RESTRICTED or CEL_ZONE_EVENT.
public int Native_GetZoneType(Handle hPlugin, int iNumParams)
{
	float fPos[3];
	
	GetNativeArray(1, fPos, 3);
	
	int iZone = FindZone(fPos);
	
	return (iZone == -1) ? CEL_ZONE_NONE : g_iZoneType[iZone];
}

public Plugin myinfo =
{
	name = "|CelMod| Zones",
	author = CEL_AUTHOR,
	description = "Event areas and restricted areas.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	
	RegAdminCmd("v_zone", Command_Zone, ADMFLAG_SLAY, "|CelMod| Creates an event or restricted area. Use it at one corner, then at the opposite corner.");
	RegAdminCmd("v_delzone", Command_DelZone, ADMFLAG_SLAY, "|CelMod| Deletes the area you are standing in.");
	RegConsoleCmd("v_zones", Command_Zones, "|CelMod| Lists the event and restricted areas on this map.");
	
	//Every command passes through here, so building commands can be refused inside an area.
	AddCommandListener(Listener_AnyCommand, "");
	
	CreateTimer(0.25, Timer_Enforce, _, TIMER_REPEAT);
	CreateTimer(1.0, Timer_Draw, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	char sDir[PLATFORM_MAX_PATH];
	
	GetCurrentMap(g_sMap, sizeof(g_sMap));
	
	g_iBeam = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	
	BuildPath(Path_SM, sDir, sizeof(sDir), "data/celmod/zones");
	
	if (!DirExists(sDir))
	{
		CreateDirectory(sDir, 511);
	}
	
	BuildPath(Path_SM, g_sZoneDB, sizeof(g_sZoneDB), "data/celmod/zones/%s.txt", g_sMap);
	
	LoadZones();
}

public void OnClientPutInServer(int iClient)
{
	g_bCornerSet[iClient] = false;
	g_fNextNotice[iClient] = 0.0;
}

void LoadZones()
{
	char sType[32];
	
	g_iZoneCount = 0;
	
	KeyValues kvZones = new KeyValues("Zones");
	
	if (kvZones.ImportFromFile(g_sZoneDB) && kvZones.GotoFirstSubKey())
	{
		do
		{
			if (g_iZoneCount >= MAX_ZONES)
			{
				break;
			}
			
			kvZones.GetString("name", g_sZoneName[g_iZoneCount], sizeof(g_sZoneName[]), "Area");
			kvZones.GetString("type", sType, sizeof(sType), "restricted");
			kvZones.GetVector("min", g_fZoneMin[g_iZoneCount]);
			kvZones.GetVector("max", g_fZoneMax[g_iZoneCount]);
			
			g_iZoneType[g_iZoneCount] = StrEqual(sType, "event", false) ? ZONE_EVENT : ZONE_RESTRICTED;
			
			g_iZoneCount++;
		}
		while (kvZones.GotoNextKey());
	}
	
	delete kvZones;
}

void SaveZones()
{
	char sKey[16];
	
	KeyValues kvZones = new KeyValues("Zones");
	
	for (int i = 0; i < g_iZoneCount; i++)
	{
		IntToString(i + 1, sKey, sizeof(sKey));
		
		kvZones.JumpToKey(sKey, true);
		kvZones.SetString("name", g_sZoneName[i]);
		kvZones.SetString("type", g_iZoneType[i] == ZONE_EVENT ? "event" : "restricted");
		kvZones.SetVector("min", g_fZoneMin[i]);
		kvZones.SetVector("max", g_fZoneMax[i]);
		kvZones.Rewind();
	}
	
	if (!kvZones.ExportToFile(g_sZoneDB))
	{
		LogError("|CelMod| Could not write the zone file '%s'.", g_sZoneDB);
	}
	
	delete kvZones;
}

//Returns the area the position is in, or -1. Event areas win where two overlap.
int FindZone(float fPos[3])
{
	int iFound = -1;
	
	for (int i = 0; i < g_iZoneCount; i++)
	{
		if (fPos[0] >= g_fZoneMin[i][0] && fPos[0] <= g_fZoneMax[i][0] && fPos[1] >= g_fZoneMin[i][1] && fPos[1] <= g_fZoneMax[i][1] && fPos[2] >= g_fZoneMin[i][2] && fPos[2] <= g_fZoneMax[i][2])
		{
			if (iFound == -1 || g_iZoneType[i] == ZONE_EVENT)
			{
				iFound = i;
			}
		}
	}
	
	return iFound;
}

int ZoneOfClient(int iClient)
{
	float fOrigin[3];
	
	GetClientAbsOrigin(iClient, fOrigin);
	
	fOrigin[2] += 32.0;
	
	return FindZone(fOrigin);
}

bool IsExempt(int iClient)
{
	return CheckCommandAccess(iClient, "celmod_zone_exempt", ADMFLAG_SLAY, true);
}

void Notice(int iClient, const char[] sMessage)
{
	if (GetGameTime() >= g_fNextNotice[iClient])
	{
		g_fNextNotice[iClient] = GetGameTime() + 2.0;
		
		Cel_PrintToChat(iClient, "%s", sMessage);
	}
}

public Action Listener_AnyCommand(int iClient, const char[] sCommand, int iArgs)
{
	char sLower[64], sMessage[192];
	
	if (iClient < 1 || iClient > MaxClients || g_iZoneCount == 0 || !IsClientInGame(iClient) || !IsPlayerAlive(iClient))
	{
		return Plugin_Continue;
	}
	
	strcopy(sLower, sizeof(sLower), sCommand);
	
	for (int i = 0; sLower[i] != '\0'; i++)
	{
		sLower[i] = CharToLower(sLower[i]);
	}
	
	bool bFly = (StrEqual(sLower, "noclip") || StrEqual(sLower, "v_fly") || StrEqual(sLower, "v_noclip"));
	bool bBuild = (strncmp(sLower, "v_", 2) == 0 || StrEqual(sLower, "+move") || StrEqual(sLower, "+copy") || StrEqual(sLower, "+grab"));
	
	if (!bFly && !bBuild)
	{
		return Plugin_Continue;
	}
	
	int iZone = ZoneOfClient(iClient);
	
	if (iZone == -1 || IsExempt(iClient))
	{
		return Plugin_Continue;
	}
	
	if (bFly || StrEqual(sLower, "v_land"))
	{
		Format(sMessage, sizeof(sMessage), "You cannot use that inside {green}%s{default}.", g_sZoneName[iZone]);
		Notice(iClient, sMessage);
		
		return Plugin_Stop;
	}
	
	if (g_iZoneType[iZone] != ZONE_EVENT)
	{
		return Plugin_Continue;
	}
	
	for (int i = 0; i < sizeof(g_sEventAllowed); i++)
	{
		if (StrEqual(sLower, g_sEventAllowed[i]))
		{
			return Plugin_Continue;
		}
	}
	
	Format(sMessage, sizeof(sMessage), "Building commands do not work inside {green}%s{default}.", g_sZoneName[iZone]);
	Notice(iClient, sMessage);
	
	return Plugin_Stop;
}

//Anyone flying inside an area is killed. Walking in, or arriving by a map teleporter, is allowed.
public Action Timer_Enforce(Handle hTimer)
{
	char sMessage[192];
	
	if (g_iZoneCount == 0)
	{
		return Plugin_Continue;
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetEntityMoveType(i) != MOVETYPE_NOCLIP || IsExempt(i))
		{
			continue;
		}
		
		int iZone = ZoneOfClient(i);
		
		if (iZone == -1)
		{
			continue;
		}
		
		SetEntityMoveType(i, MOVETYPE_WALK);
		ForcePlayerSuicide(i);
		
		Format(sMessage, sizeof(sMessage), "You cannot fly into {green}%s{default}.", g_sZoneName[iZone]);
		
		g_fNextNotice[i] = 0.0;
		
		Notice(i, sMessage);
	}
	
	return Plugin_Continue;
}

//Admins see the areas as boxes: red for restricted, yellow for event.
public Action Timer_Draw(Handle hTimer)
{
	int iAdmins[MAXPLAYERS + 1], iCount = 0;
	
	if (g_iZoneCount == 0 || g_iBeam < 1)
	{
		return Plugin_Continue;
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && IsExempt(i))
		{
			iAdmins[iCount++] = i;
		}
	}
	
	if (iCount == 0)
	{
		return Plugin_Continue;
	}
	
	for (int i = 0; i < g_iZoneCount; i++)
	{
		int iColor[4] = { 255, 40, 40, 255 };
		float fA[3], fB[3];
		
		if (g_iZoneType[i] == ZONE_EVENT)
		{
			iColor[1] = 220;
		}
		
		//The four edges of the floor.
		for (int iEdge = 0; iEdge < 4; iEdge++)
		{
			fA[0] = (iEdge == 1 || iEdge == 2) ? g_fZoneMax[i][0] : g_fZoneMin[i][0];
			fA[1] = (iEdge >= 2) ? g_fZoneMax[i][1] : g_fZoneMin[i][1];
			fA[2] = g_fZoneMin[i][2] + 8.0;
			
			int iNext = (iEdge + 1) % 4;
			
			fB[0] = (iNext == 1 || iNext == 2) ? g_fZoneMax[i][0] : g_fZoneMin[i][0];
			fB[1] = (iNext >= 2) ? g_fZoneMax[i][1] : g_fZoneMin[i][1];
			fB[2] = fA[2];
			
			TE_SetupBeamPoints(fA, fB, g_iBeam, 0, 0, 0, 1.05, 3.0, 3.0, 0, 0.0, iColor, 0);
			TE_Send(iAdmins, iCount);
		}
	}
	
	return Plugin_Continue;
}

public Action Command_Zone(int iClient, int iArgs)
{
	char sName[48], sType[32];
	float fOrigin[3];
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	GetClientAbsOrigin(iClient, fOrigin);
	
	if (!g_bCornerSet[iClient])
	{
		if (iArgs < 1)
		{
			Cel_ReplyToCommand(iClient, "Usage: {green}[tag]zone{default} <event/restricted> [name], standing at one corner. Then {green}[tag]zone{default} again at the opposite corner.");
			return Plugin_Handled;
		}
		
		GetCmdArg(1, sType, sizeof(sType));
		
		if (!StrEqual(sType, "event", false) && !StrEqual(sType, "restricted", false))
		{
			Cel_ReplyToCommand(iClient, "The area type must be {green}event{default} or {green}restricted{default}.");
			return Plugin_Handled;
		}
		
		g_bCornerSet[iClient] = true;
		g_iPendingType[iClient] = StrEqual(sType, "event", false) ? ZONE_EVENT : ZONE_RESTRICTED;
		g_fCorner[iClient] = fOrigin;
		
		Cel_ReplyToCommand(iClient, "First corner set. Go to the opposite corner (fly up for the height you want) and type {green}[tag]zone{default} again, with a name if you like.");
		
		return Plugin_Handled;
	}
	
	g_bCornerSet[iClient] = false;
	
	if (g_iZoneCount >= MAX_ZONES)
	{
		Cel_ReplyToCommand(iClient, "This map already has the most areas it can hold.");
		return Plugin_Handled;
	}
	
	int iZone = g_iZoneCount++;
	
	for (int i = 0; i < 3; i++)
	{
		g_fZoneMin[iZone][i] = (g_fCorner[iClient][i] < fOrigin[i]) ? g_fCorner[iClient][i] : fOrigin[i];
		g_fZoneMax[iZone][i] = (g_fCorner[iClient][i] < fOrigin[i]) ? fOrigin[i] : g_fCorner[iClient][i];
	}
	
	//Both corners at about the same height means the admin only marked out the floor: the area goes far up.
	g_fZoneMin[iZone][2] -= 16.0;
	
	if (g_fZoneMax[iZone][2] - g_fZoneMin[iZone][2] < 128.0)
	{
		g_fZoneMax[iZone][2] = g_fZoneMin[iZone][2] + 2048.0;
	}
	
	g_iZoneType[iZone] = g_iPendingType[iClient];
	
	if (iArgs > 0)
	{
		GetCmdArgString(sName, sizeof(sName));
		StripQuotes(sName);
		
		//When typed as "event My Area" on the second use, the type word is dropped from the name.
		ReplaceStringEx(sName, sizeof(sName), "event ", "", -1, -1, false);
		ReplaceStringEx(sName, sizeof(sName), "restricted ", "", -1, -1, false);
		TrimString(sName);
	}
	
	if (sName[0] == '\0' || StrEqual(sName, "event", false) || StrEqual(sName, "restricted", false))
	{
		Format(sName, sizeof(sName), "%s area %d", g_iZoneType[iZone] == ZONE_EVENT ? "Event" : "Restricted", iZone + 1);
	}
	
	strcopy(g_sZoneName[iZone], sizeof(g_sZoneName[]), sName);
	
	SaveZones();
	
	Cel_ReplyToCommand(iClient, "Created the %s area {green}%s{default}. Admins see its outline on the floor.", g_iZoneType[iZone] == ZONE_EVENT ? "event" : "restricted", sName);
	
	return Plugin_Handled;
}

public Action Command_DelZone(int iClient, int iArgs)
{
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	int iZone = ZoneOfClient(iClient);
	
	if (iZone == -1)
	{
		Cel_ReplyToCommand(iClient, "You are not standing in an area.");
		return Plugin_Handled;
	}
	
	Cel_ReplyToCommand(iClient, "Deleted the area {green}%s{default}.", g_sZoneName[iZone]);
	
	for (int i = iZone; i < g_iZoneCount - 1; i++)
	{
		g_sZoneName[i] = g_sZoneName[i + 1];
		g_fZoneMin[i] = g_fZoneMin[i + 1];
		g_fZoneMax[i] = g_fZoneMax[i + 1];
		g_iZoneType[i] = g_iZoneType[i + 1];
	}
	
	g_iZoneCount--;
	
	SaveZones();
	
	return Plugin_Handled;
}

public Action Command_Zones(int iClient, int iArgs)
{
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (g_iZoneCount == 0)
	{
		Cel_ReplyToCommand(iClient, "This map has no event or restricted areas.");
		return Plugin_Handled;
	}
	
	for (int i = 0; i < g_iZoneCount; i++)
	{
		Cel_ReplyToCommand(iClient, "{green}%s{default} (%s)", g_sZoneName[i], g_iZoneType[i] == ZONE_EVENT ? "event: no flying, no land, no building commands" : "restricted: no flying, no land");
	}
	
	return Plugin_Handled;
}

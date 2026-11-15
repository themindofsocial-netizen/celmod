#pragma semicolon 1

#include <celmod>

#pragma newdecls required

/*
 * |CelMod| Map Timer
 *
 * Announces how long is left on the map at 60, 30, 15, 5 and 1 minutes, like the original server:
 *   -=-=-=15 MINUTES REMAINING=-=-=-
 *   -=-=-=5 MINUTES REMAINING - SAVE YOUR BUILDS=-=-=-   (5 minutes and below)
 * with a warning bell, then a Metro Cop saying the number of minutes, "stay alert" at 5 minutes and "final warning"
 * at 1 minute.
 *
 * Each sound is a list of paths separated by ";": the first one the server really has is used (missing ones are
 * noted in the error log once), so the sounds can be changed without editing the plugin.
 */

static const int g_iMarks[] = { 60, 30, 15, 5, 1 };
static const char g_sNumberWords[][] = { "sixty", "thirty", "fifteen", "five", "one" };

bool g_bAnnounced[sizeof(g_iMarks)];

ConVar g_cvEnabled;
ConVar g_cvGong;
ConVar g_cvNumber;
ConVar g_cvStayAlert;
ConVar g_cvFinalWarning;

char g_sGong[PLATFORM_MAX_PATH];
char g_sStayAlert[PLATFORM_MAX_PATH];
char g_sFinalWarning[PLATFORM_MAX_PATH];
char g_sNumber[sizeof(g_iMarks)][PLATFORM_MAX_PATH];

public Plugin myinfo =
{
	name = "|CelMod| Map Timer",
	author = CEL_AUTHOR,
	description = "Announces the time left on the map.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	g_cvEnabled = CreateConVar("cm_maptimer", "1", "Announce the time left on the map at 60, 30, 15, 5 and 1 minutes.", _, true, 0.0, true, 1.0);
	g_cvGong = CreateConVar("cm_maptimer_gong", "ambient/alarms/warningbell1.wav", "The gong played with each announcement (paths under sound/, the first one the server has is used).");
	g_cvNumber = CreateConVar("cm_maptimer_number", "npc/metropolice/vo/%s.wav", "The Metro Cop saying the number of minutes (%s becomes sixty, thirty, fifteen, five or one).");
	g_cvStayAlert = CreateConVar("cm_maptimer_stayalert", "npc/metropolice/vo/stayalert.wav;npc/metropolice/vo/stayalertreportsightlines.wav;npc/combine_soldier/vo/stayalert.wav", "The \"stay alert\" line played at 5 minutes.");

	g_cvFinalWarning = CreateConVar("cm_maptimer_finalwarning", "npc/metropolice/vo/finalwarning.wav", "The \"final warning\" line played at 1 minute.");

	AutoExecConfig(true, "celmod.maptimer");

	RegAdminCmd("cm_maptimer_test", Command_Test, ADMFLAG_ROOT, "|CelMod| Plays a map timer announcement now: cm_maptimer_test <60/30/15/5/1>.");

	CreateTimer(1.0, Timer_Check, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	for (int i = 0; i < sizeof(g_iMarks); i++)
	{
		g_bAnnounced[i] = false;
	}
}

public void OnConfigsExecuted()
{
	char sList[PLATFORM_MAX_PATH * 3], sPattern[PLATFORM_MAX_PATH], sPath[PLATFORM_MAX_PATH];

	g_cvGong.GetString(sList, sizeof(sList));
	PickSound(sList, g_sGong, sizeof(g_sGong), "gong");

	g_cvStayAlert.GetString(sList, sizeof(sList));
	PickSound(sList, g_sStayAlert, sizeof(g_sStayAlert), "stay alert");

	g_cvFinalWarning.GetString(sList, sizeof(sList));
	PickSound(sList, g_sFinalWarning, sizeof(g_sFinalWarning), "final warning");

	g_cvNumber.GetString(sPattern, sizeof(sPattern));

	for (int i = 0; i < sizeof(g_iMarks); i++)
	{
		Format(sPath, sizeof(sPath), sPattern, g_sNumberWords[i]);
		PickSound(sPath, g_sNumber[i], sizeof(g_sNumber[]), g_sNumberWords[i]);
	}
}

//The first sound in the list the server has (it looks inside the game's own files too). Empty if none.
void PickSound(const char[] sList, char[] sChosen, int iMaxLength, const char[] sWhat)
{
	char sPaths[6][PLATFORM_MAX_PATH], sFile[PLATFORM_MAX_PATH];

	sChosen[0] = '\0';

	int iCount = ExplodeString(sList, ";", sPaths, sizeof(sPaths), sizeof(sPaths[]));

	for (int i = 0; i < iCount; i++)
	{
		TrimString(sPaths[i]);

		Format(sFile, sizeof(sFile), "sound/%s", sPaths[i]);

		if (sPaths[i][0] != '\0' && FileExists(sFile, true))
		{
			strcopy(sChosen, iMaxLength, sPaths[i]);
			PrecacheSound(sChosen, true);
			return;
		}
	}

	LogError("|CelMod| Map timer: none of the %s sounds (%s) are on the server; that part of the announcement is skipped.", sWhat, sList);
}

public Action Timer_Check(Handle hTimer)
{
	int iLeft;

	if (!g_cvEnabled.BoolValue || !GetMapTimeLeft(iLeft) || iLeft < 0)
	{
		return Plugin_Continue;
	}

	for (int i = 0; i < sizeof(g_iMarks); i++)
	{
		int iMark = g_iMarks[i] * 60;

		// Announced once, as the time left passes the mark (not when a map starts with less time than it).
		if (!g_bAnnounced[i] && iLeft <= iMark && iLeft > iMark - 5)
		{
			g_bAnnounced[i] = true;
			Announce(i);
		}
		else if (iLeft > iMark + 5)
		{
			// The time limit went back up (mp_timelimit changed): the mark can be announced again.
			g_bAnnounced[i] = false;
		}
	}

	return Plugin_Continue;
}

void Announce(int iMark)
{
	int iMinutes = g_iMarks[iMark];

	if (iMinutes <= 5)
	{
		CPrintToChatAll("{green}-=-=-=%d %s REMAINING - SAVE YOUR BUILDS=-=-=-", iMinutes, iMinutes == 1 ? "MINUTE" : "MINUTES");
	} else {
		CPrintToChatAll("{green}-=-=-=%d MINUTES REMAINING=-=-=-", iMinutes);
	}

	if (g_sGong[0] != '\0')
	{
		EmitSoundToAll(g_sGong);
	}

	// Then the Metro Cop: the number, and "stay alert" at 5 minutes.
	DataPack dpSay = new DataPack();

	dpSay.WriteCell(iMark);

	CreateTimer(1.6, Timer_SayNumber, dpSay, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
}

public Action Timer_SayNumber(Handle hTimer, DataPack dpSay)
{
	dpSay.Reset();

	int iMark = dpSay.ReadCell();

	if (g_sNumber[iMark][0] != '\0')
	{
		EmitSoundToAll(g_sNumber[iMark]);
	}

	if (g_iMarks[iMark] == 5 && g_sStayAlert[0] != '\0')
	{
		CreateTimer(1.2, Timer_StayAlert, _, TIMER_FLAG_NO_MAPCHANGE);
	}

	if (g_iMarks[iMark] == 1 && g_sFinalWarning[0] != '\0')
	{
		CreateTimer(1.2, Timer_FinalWarning, _, TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Stop;
}

public Action Timer_FinalWarning(Handle hTimer)
{
	EmitSoundToAll(g_sFinalWarning);

	return Plugin_Stop;
}

public Action Timer_StayAlert(Handle hTimer)
{
	EmitSoundToAll(g_sStayAlert);

	return Plugin_Stop;
}

public Action Command_Test(int iClient, int iArgs)
{
	char sArg[8];

	GetCmdArg(1, sArg, sizeof(sArg));

	int iMinutes = iArgs > 0 ? StringToInt(sArg) : 5;

	for (int i = 0; i < sizeof(g_iMarks); i++)
	{
		if (g_iMarks[i] == iMinutes)
		{
			Announce(i);
			ReplyToCommand(iClient, "|CelMod| Gong: %s | Number: %s | Stay alert: %s", g_sGong[0] ? g_sGong : "(none found)", g_sNumber[i][0] ? g_sNumber[i] : "(none found)", g_sStayAlert[0] ? g_sStayAlert : "(none found)");
			return Plugin_Handled;
		}
	}

	ReplyToCommand(iClient, "|CelMod| Use 60, 30, 15, 5 or 1.");

	return Plugin_Handled;
}

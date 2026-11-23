#pragma semicolon 1

#include <sdkhooks>
#include <celmod>

#pragma newdecls required

/*
 * |CelMod| Missing Person
 *
 * The 'Missing: Jimmy' quest on gm_bloodyconstruct_cm12 (works on any map with the same entity names).
 *
 *   jimmy_evidence  func_button by Jimmy's wrench next to the antlion hole in the laser room.
 *   talk_pd_sarge   func_button on Sgt. Malone at the police scene.
 *   pd_sarge        the sergeant's prop_dynamic (the reward line is spoken from it).
 *
 * Pressing the wrench marks the player as carrying the evidence. Talking to the sergeant with it gives the
 * "police" player model for good (Cel_GivePlayerModel, the same as !givemodel), after which the player can wear it
 * with !playermodel police. The model's entry lives in data/celmod/collectibles.txt under PlayerModels.
 *
 * It can be done once: whoever owns the police model can't pick the wrench up again. Solving it also gives tactics
 * experience (cm_tactics_xp_jimmy).
 *
 * The evidence only lasts until the player leaves or the map changes.
 */

#define MODEL_ID "police"
#define SND_REWARD "vo/npc/male01/fantastic01.wav"
#define SND_AGAIN "vo/npc/male01/nice.wav"

ConVar g_cvXP;

bool g_bEvidence[MAXPLAYERS + 1];
float g_fNextTalk[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "|CelMod| Missing Person",
	author = "CelMod",
	description = "Unlocks the police player model on gm_bloodyconstruct by finding Jimmy's wrench.",
	version = "1.0.0",
	url = ""
};

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	MarkNativeAsOptional("Cel_GivePlayerModel");
	MarkNativeAsOptional("Cel_OwnsPlayerModel");
	MarkNativeAsOptional("Cel_PrintToChat");
	MarkNativeAsOptional("Cel_AddTacticsXP");

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvXP = CreateConVar("cm_tactics_xp_jimmy", "50", "Tactics experience for handing Jimmy's wrench to Sgt. Malone (once, with the police model).", _, true, 0.0);

	HookEntityOutput("func_button", "OnPressed", Output_ButtonPressed);

	// Late load: hook the sergeant's button if the map is already running.
	int iEnt = -1;

	while ((iEnt = FindEntityByClassname(iEnt, "func_button")) != -1)
	{
		HookIfSarge(iEnt);
	}
}

public void OnMapStart()
{
	PrecacheSound(SND_REWARD, true);
	PrecacheSound(SND_AGAIN, true);

	// The police model's animations come from this file (it is $includemodel'd), so players on other maps need it too.
	if (FileExists("models/m_anm.mdl", false))
	{
		AddFileToDownloadsTable("models/m_anm.mdl");
		PrecacheModel("models/m_anm.mdl", true);
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		g_bEvidence[i] = false;
		g_fNextTalk[i] = 0.0;
	}
}

public void OnClientDisconnect(int iClient)
{
	g_bEvidence[iClient] = false;
	g_fNextTalk[iClient] = 0.0;
}

public void OnEntityCreated(int iEntity, const char[] sClassname)
{
	if (StrEqual(sClassname, "func_button"))
	{
		SDKHook(iEntity, SDKHook_SpawnPost, Hook_ButtonSpawnPost);
	}
}

public void Hook_ButtonSpawnPost(int iEntity)
{
	HookIfSarge(iEntity);
}

void HookIfSarge(int iEntity)
{
	char sName[64];

	GetEntPropString(iEntity, Prop_Data, "m_iName", sName, sizeof(sName));

	if (StrEqual(sName, "talk_pd_sarge"))
	{
		SDKUnhook(iEntity, SDKHook_Use, Hook_SargeUse);
		SDKHook(iEntity, SDKHook_Use, Hook_SargeUse);
	}
}

public void Output_ButtonPressed(const char[] sOutput, int iCaller, int iActivator, float fDelay)
{
	char sName[64];

	if (!IsValidClient(iActivator) || !IsValidEntity(iCaller))
	{
		return;
	}

	GetEntPropString(iCaller, Prop_Data, "m_iName", sName, sizeof(sName));

	if (!StrEqual(sName, "jimmy_evidence"))
	{
		return;
	}

	if (OwnsPoliceModel(iActivator) == 1)
	{
		Chat(iActivator, "You already wear the badge, officer. The {green}police{default} player model is yours ({green}[tag]playermodel police{default}).");

		return;
	}

	if (!g_bEvidence[iActivator])
	{
		g_bEvidence[iActivator] = true;

		Chat(iActivator, "You picked up {green}Jimmy's pipe wrench{default}. Take it to {green}Sgt. Malone{default} at the police scene.");
	}
}

// Talking to the sergeant while carrying the wrench hands it in instead of a random line.
public Action Hook_SargeUse(int iEntity, int iActivator, int iCaller, UseType utType, float fValue)
{
	if (!IsValidClient(iActivator) || !g_bEvidence[iActivator])
	{
		return Plugin_Continue;
	}

	float fNow = GetGameTime();

	if (fNow < g_fNextTalk[iActivator])
	{
		return Plugin_Handled;
	}

	g_fNextTalk[iActivator] = fNow + 3.0;

	int iOwned = OwnsPoliceModel(iActivator);

	if (iOwned == -1)
	{
		LogError("|CelMod| The '%s' player model is missing from data/celmod/collectibles.txt, so it can't be given.", MODEL_ID);

		return Plugin_Continue;
	}

	g_bEvidence[iActivator] = false;

	int iSarge = FindByName("prop_dynamic", "pd_sarge");
	int iSpeaker = (iSarge != -1) ? iSarge : iEntity;

	// The case is solved once: someone who already has the badge gets nothing more for it.
	if (iOwned == 1)
	{
		EmitSoundToAll(SND_AGAIN, iSpeaker, SNDCHAN_VOICE);
		Subtitle(iActivator, "Sgt. Malone: You already cracked this one, officer. I'll file it with the rest.");

		return Plugin_Handled;
	}

	if (GetFeatureStatus(FeatureType_Native, "Cel_GivePlayerModel") != FeatureStatus_Available || !Cel_GivePlayerModel(iActivator, MODEL_ID))
	{
		g_bEvidence[iActivator] = true;
		LogError("|CelMod| Could not give the '%s' player model to %L.", MODEL_ID, iActivator);

		return Plugin_Continue;
	}

	EmitSoundToAll(SND_REWARD, iSpeaker, SNDCHAN_VOICE);
	Subtitle(iActivator, "Sgt. Malone: Fantastic! Jimmy's wrench... the bugs took him down that tunnel. You did better police work than my whole squad. Welcome to the force.");
	Chat(iActivator, "{green}Police Officer{default} player model unlocked! Wear it with {green}[tag]playermodel police{default}.");

	// Experience for solving it: only here, and this only happens once (the model is theirs from now on).
	if (g_cvXP.IntValue > 0)
	{
		Cel_AddXP(iActivator, g_cvXP.IntValue);
	}
	LogAction(iActivator, -1, "%L unlocked the %s player model on gm_bloodyconstruct.", iActivator, MODEL_ID);

	return Plugin_Handled;
}

int OwnsPoliceModel(int iClient)
{
	if (GetFeatureStatus(FeatureType_Native, "Cel_OwnsPlayerModel") != FeatureStatus_Available)
	{
		return -1;
	}

	return Cel_OwnsPlayerModel(iClient, MODEL_ID);
}

int FindByName(const char[] sClassname, const char[] sTarget)
{
	char sName[64];
	int iEnt = -1;

	while ((iEnt = FindEntityByClassname(iEnt, sClassname)) != -1)
	{
		GetEntPropString(iEnt, Prop_Data, "m_iName", sName, sizeof(sName));

		if (StrEqual(sName, sTarget))
		{
			return iEnt;
		}
	}

	return -1;
}

void Subtitle(int iClient, const char[] sText)
{
	SetHudTextParams(-1.0, 0.76, 7.0, 255, 255, 255, 255, 0, 0.25, 0.05, 0.6);
	ShowHudText(iClient, 2, sText);
}

void Chat(int iClient, const char[] sMessage)
{
	if (GetFeatureStatus(FeatureType_Native, "Cel_PrintToChat") == FeatureStatus_Available)
	{
		Cel_PrintToChat(iClient, sMessage);

		return;
	}

	char sPlain[256];

	strcopy(sPlain, sizeof(sPlain), sMessage);
	ReplaceString(sPlain, sizeof(sPlain), "{green}", "");
	ReplaceString(sPlain, sizeof(sPlain), "{default}", "");
	ReplaceString(sPlain, sizeof(sPlain), "[tag]", "!");
	PrintToChat(iClient, "%s", sPlain);
}

bool IsValidClient(int iClient)
{
	return iClient > 0 && iClient <= MaxClients && IsClientInGame(iClient) && !IsFakeClient(iClient);
}

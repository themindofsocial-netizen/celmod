#pragma semicolon 1

#include <celmod>

#define TELEPORT_MODEL "models/props_lab/teleplatform.mdl"
#define HOOPIE_MODEL "models/celmod/hoopie.mdl"
#define HOOPIE_SOUND "weapons/physcannon/energy_bounce1.wav"

#pragma newdecls required

/*
 * |CelMod| Extras
 *
 * Smaller commands from the original server's command list that do not belong to another plugin.
 */

ArrayList g_alUndo[MAXPLAYERS + 1];

//While a build loads: the entity each saved id became, and the links still to be made.
ArrayList g_alLoadLinks[MAXPLAYERS + 1];
StringMap g_smLoadIds[MAXPLAYERS + 1];

bool g_bHide[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool g_bHideHooked[MAXENTITIES + 1];
bool g_bLandBan[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool g_bNoFly[MAXPLAYERS + 1]; //!nofly: other players can't noclip inside this player's land
bool g_bNoWeps[MAXPLAYERS + 1]; //!weps: other players' weapons don't work in this player's land
int g_iNoWepsOwner[MAXPLAYERS + 1]; //the owner of the no-weapons land a player is standing in (0 = none)
float g_fNextNoWepsNotice[MAXPLAYERS + 1];
bool g_bBlockLand[MAXPLAYERS + 1][MAXPLAYERS + 1];
char g_sBlockIds[MAXPLAYERS + 1][1024];
char g_sBuildMessage[MAXPLAYERS + 1][128];
int g_iLastLandIn[MAXPLAYERS + 1];
bool g_bOutsideKnown[MAXPLAYERS + 1];
float g_fLastOutside[MAXPLAYERS + 1][3];
float g_fNextBlockNotice[MAXPLAYERS + 1];
int g_iLandFee[MAXPLAYERS + 1]; //!fee: what it costs other players to walk into this player's land (0 = free)
bool g_bFeePaid[MAXPLAYERS + 1][MAXPLAYERS + 1]; //[owner][visitor]: paid until either leaves or the fee changes
int g_iFeeAsked[MAXPLAYERS + 1]; //the owner whose fee this player was last stopped by, for !fee pay
ConVar g_cvLandFeeMax;

char g_sMessage[MAXENTITIES + 1][192];
char g_sSound[MAXENTITIES + 1][PLATFORM_MAX_PATH];
char g_sSoundDB[PLATFORM_MAX_PATH];
char g_sMusic[MAXENTITIES + 1][PLATFORM_MAX_PATH];
float g_fMusicLength[MAXENTITIES + 1];
float g_fMusicEnds[MAXENTITIES + 1];
int g_iMusicPitch[MAXENTITIES + 1];

float g_fLandKickUntil[MAXPLAYERS + 1][MAXPLAYERS + 1];
float g_fNextBanNotice[MAXPLAYERS + 1];
float g_fNextSoundUse[MAXENTITIES + 1];

int g_iMoveToRef[MAXPLAYERS + 1];
int g_iTrackOwner[MAXENTITIES + 1];
int g_iTeleportDest[MAXENTITIES + 1];
int g_iTeleportRef[MAXPLAYERS + 1];
int g_iWeldRef[MAXPLAYERS + 1];

float g_fNextTeleport[MAXPLAYERS + 1];
float g_fNextBounce[MAXPLAYERS + 1];
int g_iSpawnPointRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
int g_iDiedInLand[MAXPLAYERS + 1];
ConVar g_cvSpawnPointModel;
ConVar g_cvSpawnHealth;
ConVar g_cvLoadout;
ConVar g_cvNoBlock;
ConVar g_cvDoubleJump;
ConVar g_cvDoubleJumpHeight;
ConVar g_cvUnlimitedAux;
bool g_bDoubleJumped[MAXPLAYERS + 1];
int g_iLastButtons[MAXPLAYERS + 1];
ConVar g_cvHoopieBounce;

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	MarkNativeAsOptional("SetEntityCollisionGroup");
	
	MarkNativeAsOptional("Cel_GetZoneType");
	MarkNativeAsOptional("Cel_IsZoneExempt");
	MarkNativeAsOptional("Cel_AddPlayerStat");
	MarkNativeAsOptional("Cel_SetPlayerStat");
	
	return APLRes_Success;
}

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
	
	g_cvSpawnPointModel = CreateConVar("cm_spawnpoint_model", "models/props_junk/sawblade001a.mdl", "Model of the !spawnpoint cel.");
	
	HookEvent("player_death", Event_SpawnPointDeath);
	HookEvent("player_spawn", Event_SpawnPointSpawn);
	HookEvent("player_spawn", Event_SpawnHealth);
	HookEvent("player_spawn", Event_SpawnLoadout);
	CreateTimer(0.5, Timer_RefillChargers, _, TIMER_REPEAT);
	g_cvLoadout = CreateConVar("cm_spawn_loadout", "weapon_physcannon weapon_crowbar", "The only weapons players spawn with (empty = the game's own). Celweps and bought weapons are given back as usual.");
	
	g_cvNoBlock = CreateConVar("cm_noblock", "1", "1: players walk through each other (they still collide with the world and props, and can still be shot).", _, true, 0.0, true, 1.0);
	g_cvNoBlock.AddChangeHook(CMExtras_OnNoBlockChanged);
	g_cvSpawnHealth = CreateConVar("cm_spawn_health", "225", "Health (and full health) players spawn with.", _, true, 1.0);
	g_cvUnlimitedAux = CreateConVar("cm_unlimited_aux", "1", "1: the suit's aux power (sprint, flashlight, breath underwater) never runs out.", _, true, 0.0, true, 1.0);
	g_cvDoubleJump = CreateConVar("cm_double_jump", "1", "Double jumping (jump again in the air): 0 turns it off. Never in event areas.", _, true, 0.0);
	g_cvDoubleJumpHeight = CreateConVar("cm_double_jump_height", "24.0", "How high a double jump goes, in units (a normal jump is about 21).", _, true, 1.0, true, 512.0);
	
	g_cvLandFeeMax = CreateConVar("cm_land_fee_max", "100000", "Highest entry fee a player can set on their land with !fee.", _, true, 0.0);
	g_cvHoopieBounce = CreateConVar("cm_hoopie_bounce", "650", "How hard a hoopie bounces players off it.", _, true, 0.0, true, 3000.0);
	
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_iMoveToRef[i] = INVALID_ENT_REFERENCE;
		g_iWeldRef[i] = INVALID_ENT_REFERENCE;
		g_iTeleportRef[i] = INVALID_ENT_REFERENCE;
		g_alUndo[i] = new ArrayList();
		g_alLoadLinks[i] = new ArrayList(3);
		g_smLoadIds[i] = new StringMap();
	}
	
	BuildPath(Path_SM, g_sSoundDB, sizeof(g_sSoundDB), "data/celmod/sounds.txt");
	
	CreateTimer(0.5, Timer_LandBans, _, TIMER_REPEAT);
	CreateTimer(0.1, Timer_NoBlock, _, TIMER_REPEAT);
	
	RegConsoleCmd("v_model", Command_Model, "|CelMod| Replaces the model on the entity you are looking at.");
	RegConsoleCmd("v_palette", Command_Palette, "|CelMod| Colors the prop you are looking at with your own red, green and blue values.");
	RegConsoleCmd("v_spawnpoint", Command_SpawnPoint, "|CelMod| Spawns a spawn point in your land: anyone who dies in your land respawns on it.");
	RegConsoleCmd("v_teleport", Command_Teleport, "|CelMod| Spawns a teleport pad. Use it twice: the first pad sends players to the second.");
	RegConsoleCmd("v_hide", Command_Hide, "|CelMod| Hides another player's entities from your view.");
	RegConsoleCmd("v_block", Command_Block, "|CelMod| Stops you from entering a player's land (use again to allow it). With no name, lists who you have blocked.");
	RegConsoleCmd("v_unblock", Command_Unblock, "|CelMod| Lets you enter a player's land again.");
	CreateTimer(0.1, Timer_BlockLands, _, TIMER_REPEAT);
	RegConsoleCmd("v_fee", Command_Fee, "|CelMod| Charges other players a fee to enter your land: !fee <amount> (0 = free). Visitors type !fee pay.");
	RegConsoleCmd("v_landban", Command_LandBan, "|CelMod| Bans a player from your land.");
	RegConsoleCmd("v_landunban", Command_LandUnban, "|CelMod| Lets a banned player back into your land.");
	RegConsoleCmd("v_buildmessage", Command_BuildMessage, "|CelMod| Sets the message players see when they walk into your build (off to remove it).");
	CreateTimer(0.5, Timer_BuildMessages, _, TIMER_REPEAT);
	RegConsoleCmd("v_message", Command_Message, "|CelMod| Spawns a message cel that shows your text to whoever uses it.");
	RegConsoleCmd("v_release", Command_Release, "|CelMod| Releases the entity you are looking at from a weld.");
	RegConsoleCmd("v_show", Command_Show, "|CelMod| Shows a hidden player's entities again.");
	RegConsoleCmd("v_music", Command_Music, "|CelMod| Spawns a music cel that plays a song when used (and stops it when used again).");
	RegConsoleCmd("v_celmusic", Command_CelMusic, "|CelMod| Lists the songs the music cel can play.");
	RegConsoleCmd("v_sound", Command_Sound, "|CelMod| Spawns a sound cel that plays a sound when used.");
	RegConsoleCmd("v_undo", Command_Undo, "|CelMod| Removes the last entity you spawned.");
	RegConsoleCmd("v_weld", Command_Weld, "|CelMod| Welds one of your entities to another so they move together.");
	RegConsoleCmd("v_clear", Command_Clear, "|CelMod| Deletes one of your saved builds.");
	RegConsoleCmd("v_fire", Command_Fire, "|CelMod| Spawns a fire effect cel.");
	RegConsoleCmd("v_landkick", Command_LandKick, "|CelMod| Kicks a player out of your land for 10 seconds.");
	RegConsoleCmd("v_kick", Command_LandKick, "|CelMod| Kicks a player out of your land for 10 seconds (same as !landkick).");
	RegConsoleCmd("v_landslay", Command_LandSlay, "|CelMod| Slays a player, or everyone, inside your land.");
	RegConsoleCmd("v_moveto", Command_MoveTo, "|CelMod| Moves one of your entities onto another entity.");
	RegConsoleCmd("v_noclip", Command_NoClip, "|CelMod| Enables/disables noclip on the player.");
	RegConsoleCmd("v_stuck", Command_Stuck, "|CelMod| Respawns you.");
	RegConsoleCmd("v_turn", Command_Turn, "|CelMod| Rotates the prop you are looking at.");
	RegConsoleCmd("v_nofly", Command_LandNoFly, "|CelMod| Turns noclip off (or back on) for other players inside your land.");
	RegConsoleCmd("v_landnoclip", Command_LandNoFly, "|CelMod| Turns noclip off (or back on) for other players inside your land (same as !nofly).");
	AddCommandListener(Listener_NoFly, "v_fly");
	RegConsoleCmd("v_weps", Command_LandWeps, "|CelMod| Turns other players' weapons off (or back on) inside your land.");
	RegConsoleCmd("v_text", Command_Text, "|CelMod| Writes words in the world out of text screens where you aim: !text <words> (^ in front for small text).");
	RegConsoleCmd("v_arsenal", Command_Arsenal, "|CelMod| Gives you every weapon (bought in the shop: !buy arsenal).");
}

//Health and suit chargers never run out: the map's own and charger bits are topped up twice a second, before
//anyone can empty them.
public Action Timer_RefillChargers(Handle hTimer)
{
	static const char sClasses[][] = { "item_healthcharger", "item_suitcharger", "bit_charger_health", "bit_charger_suit" };
	
	ConVar cvHealth = FindConVar("sk_healthcharger"), cvSuit = FindConVar("sk_suitcharger");
	int iHealth = (cvHealth != null && cvHealth.IntValue > 0) ? cvHealth.IntValue : 50;
	int iSuit = (cvSuit != null && cvSuit.IntValue > 0) ? cvSuit.IntValue : 75;
	
	for (int c = 0; c < sizeof(sClasses); c++)
	{
		int iCharger = -1;
		bool bSuit = (StrContains(sClasses[c], "suit") != -1);
		
		while ((iCharger = FindEntityByClassname(iCharger, sClasses[c])) != -1)
		{
			if (HasEntProp(iCharger, Prop_Data, "m_iJuice") && GetEntProp(iCharger, Prop_Data, "m_iJuice") < (bSuit ? iSuit : iHealth))
			{
				SetEntProp(iCharger, Prop_Data, "m_iJuice", bSuit ? iSuit : iHealth);
				
				if (HasEntProp(iCharger, Prop_Send, "m_flJuice"))
				{
					SetEntPropFloat(iCharger, Prop_Send, "m_flJuice", 1.0);
				}
			}
		}
	}
	
	return Plugin_Continue;
}

//Spawn loadout: the game hands out its default weapons; just after, everything not in cm_spawn_loadout is taken
//away and anything missing from it is given. (Celweps and Custom Guns come a second later, as before.)
public void Event_SpawnLoadout(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	char sLoadout[256];
	
	g_cvLoadout.GetString(sLoadout, sizeof(sLoadout));
	TrimString(sLoadout);
	
	if (sLoadout[0] != '\0')
	{
		CreateTimer(0.1, Timer_SpawnLoadout, eEvent.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_SpawnLoadout(Handle hTimer, any iUserId)
{
	char sLoadout[256], sClass[64], sKeep[8][64];
	int iClient = GetClientOfUserId(iUserId);
	
	if (iClient < 1 || !IsClientInGame(iClient) || !IsPlayerAlive(iClient))
	{
		return Plugin_Stop;
	}
	
	g_cvLoadout.GetString(sLoadout, sizeof(sLoadout));
	TrimString(sLoadout);
	
	int iKeep = ExplodeString(sLoadout, " ", sKeep, sizeof(sKeep), sizeof(sKeep[]));
	bool bHave[8];
	
	int iSize = GetEntPropArraySize(iClient, Prop_Send, "m_hMyWeapons");
	
	for (int w = 0; w < iSize; w++)
	{
		int iWeapon = GetEntPropEnt(iClient, Prop_Send, "m_hMyWeapons", w);
		
		if (iWeapon <= MaxClients || !IsValidEntity(iWeapon) || !GetEntityClassname(iWeapon, sClass, sizeof(sClass)))
		{
			continue;
		}
		
		bool bKeep = false;
		
		for (int k = 0; k < iKeep; k++)
		{
			if (StrEqual(sClass, sKeep[k], false))
			{
				bKeep = true;
				bHave[k] = true;
			}
		}
		
		if (!bKeep)
		{
			RemovePlayerItem(iClient, iWeapon);
			AcceptEntityInput(iWeapon, "Kill");
		}
	}
	
	for (int k = 0; k < iKeep; k++)
	{
		if (!bHave[k] && sKeep[k][0] != '\0')
		{
			GivePlayerItem(iClient, sKeep[k]);
		}
	}
	
	FakeClientCommand(iClient, "use weapon_physcannon");
	
	return Plugin_Stop;
}

//Combine players spawn with the game's stunstick in the crowbar's slot, so they couldn't pick a crowbar up: touching
//one swaps the stunstick for it.
public Action Hook_WeaponCanUse(int iClient, int iWeapon)
{
	char sClass[32];
	
	if (iWeapon <= MaxClients || !IsValidEntity(iWeapon) || !GetEntityClassname(iWeapon, sClass, sizeof(sClass)) || !StrEqual(sClass, "weapon_crowbar"))
	{
		return Plugin_Continue;
	}
	
	int iSize = GetEntPropArraySize(iClient, Prop_Send, "m_hMyWeapons");
	
	for (int w = 0; w < iSize; w++)
	{
		int iHeld = GetEntPropEnt(iClient, Prop_Send, "m_hMyWeapons", w);
		
		if (iHeld > MaxClients && IsValidEntity(iHeld) && GetEntityClassname(iHeld, sClass, sizeof(sClass)) && StrEqual(sClass, "weapon_stunstick"))
		{
			RemovePlayerItem(iClient, iHeld);
			AcceptEntityInput(iHeld, "Kill");
		}
	}
	
	return Plugin_Continue;
}

public void OnClientPutInServer(int iClient)
{
	SDKHook(iClient, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
	
	g_sBuildMessage[iClient][0] = '\0';
	g_iLastLandIn[iClient] = 0;
	g_iNoWepsOwner[iClient] = 0;
	g_bNoWeps[iClient] = false;
	g_bNoFly[iClient] = false;
	g_iMoveToRef[iClient] = INVALID_ENT_REFERENCE;
	g_iWeldRef[iClient] = INVALID_ENT_REFERENCE;
	g_iTeleportRef[iClient] = INVALID_ENT_REFERENCE;
	g_iSpawnPointRef[iClient] = INVALID_ENT_REFERENCE;
	g_iDiedInLand[iClient] = 0;
	g_fNextBanNotice[iClient] = 0.0;
	g_fNextTeleport[iClient] = 0.0;
	g_bOutsideKnown[iClient] = false;
	g_sBlockIds[iClient][0] = '\0';
	
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_bBlockLand[iClient][i] = false;
		g_bBlockLand[i][iClient] = false;
	}
	g_fNextBlockNotice[iClient] = 0.0;
	g_iLandFee[iClient] = 0;
	g_iFeeAsked[iClient] = 0;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_iFeeAsked[i] == iClient)
		{
			g_iFeeAsked[i] = 0;
		}
	}
	
	g_alUndo[iClient].Clear();
	
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_bHide[iClient][i] = false;
		g_bHide[i][iClient] = false;
		g_bLandBan[iClient][i] = false;
		g_bLandBan[i][iClient] = false;
		g_bFeePaid[iClient][i] = false;
		g_bFeePaid[i][iClient] = false;
		g_fLandKickUntil[iClient][i] = 0.0;
		g_fLandKickUntil[i][iClient] = 0.0;
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_iNoWepsOwner[i] == iClient)
		{
			g_iNoWepsOwner[i] = 0;
		}
	}
}

public void OnMapStart()
{
	PrecacheSound("ambient/machines/teleport1.wav", true);
	PrecacheSound(HOOPIE_SOUND, true);
	PrecacheModel(TELEPORT_MODEL, true);
	
	for (int i = 0; i <= MAXENTITIES; i++)
	{
		g_iTeleportDest[i] = INVALID_ENT_REFERENCE;
		g_bHideHooked[i] = false;
		g_iTrackOwner[i] = 0;
		g_sMessage[i][0] = '\0';
		g_sSound[i][0] = '\0';
		g_sMusic[i][0] = '\0';
		g_fMusicEnds[i] = 0.0;
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
		g_iTeleportDest[iEntity] = INVALID_ENT_REFERENCE;
		g_sMessage[iEntity][0] = '\0';
		g_sSound[iEntity][0] = '\0';
		g_sMusic[iEntity][0] = '\0';
		g_fMusicEnds[iEntity] = 0.0;
		
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
	
	//Hoopies bounce players off their face.
	char sModel[PLATFORM_MAX_PATH];
	
	GetEntPropString(iEntity, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
	
	if (StrEqual(sModel, HOOPIE_MODEL, false))
	{
		SDKHook(iEntity, SDKHook_StartTouchPost, Hook_HoopieTouch);
	}
	
	int iOwner = Cel_GetOwner(iEntity);
	
	if (iOwner < 1 || iOwner > MaxClients)
	{
		return;
	}
	
	g_iTrackOwner[iEntity] = iOwner;
	
	//A spawn point loaded from a build becomes its owner's spawn point (only one is kept).
	char sPropName[64];
	
	Cel_GetPropName(iEntity, sPropName, sizeof(sPropName));
	
	if (StrEqual(sPropName, "spawnpoint"))
	{
		SetSpawnPoint(iOwner, iEntity);
	}
	
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
//!block <player>: keeps yourself out of that player's land. Remembered (by Steam ID) between visits.
public void OnClientPostAdminCheck(int iClient)
{
	char sId[32];
	
	g_bNoWeps[iClient] = (Cel_GetClientSettingInt(iClient, "land-noweps") == 1);
	g_bNoFly[iClient] = (Cel_GetClientSettingInt(iClient, "land-nofly") == 1);
	
	Cel_GetClientSettingString(iClient, "blockedlands", g_sBlockIds[iClient], sizeof(g_sBlockIds[]));
	
	//The message players see when they walk into this player's build.
	Cel_GetClientSettingString(iClient, "buildmessage", g_sBuildMessage[iClient], sizeof(g_sBuildMessage[]));
	
	if (StrEqual(g_sBuildMessage[iClient], "none"))
	{
		g_sBuildMessage[iClient][0] = '\0';
	}
	
	g_iLastLandIn[iClient] = 0;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == iClient || !IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}
		
		if (GetClientAuthId(i, AuthId_SteamID64, sId, sizeof(sId)) && IdListHas(g_sBlockIds[iClient], sId))
		{
			g_bBlockLand[iClient][i] = true;
		}
		
		if (GetClientAuthId(iClient, AuthId_SteamID64, sId, sizeof(sId)) && IdListHas(g_sBlockIds[i], sId))
		{
			g_bBlockLand[i][iClient] = true;
		}
	}
}

bool IdListHas(const char[] sList, const char[] sId)
{
	char sFind[40], sWrapped[1100];
	
	Format(sFind, sizeof(sFind), ",%s,", sId);
	Format(sWrapped, sizeof(sWrapped), ",%s,", sList);
	
	return (StrContains(sWrapped, sFind) != -1);
}

//Saves the Steam IDs: blocked players who are here now, plus saved ones who are not.
void SaveBlocks(int iClient)
{
	char sOld[1024], sParts[32][32], sId[32], sOther[32];
	
	Cel_GetClientSettingString(iClient, "blockedlands", sOld, sizeof(sOld));
	
	g_sBlockIds[iClient][0] = '\0';
	
	int iParts = ExplodeString(sOld, ",", sParts, sizeof(sParts), sizeof(sParts[]));
	
	for (int k = 0; k < iParts; k++)
	{
		if (sParts[k][0] == '\0')
		{
			continue;
		}
		
		bool bHere = false;
		
		for (int i = 1; i <= MaxClients && !bHere; i++)
		{
			bHere = (IsClientInGame(i) && !IsFakeClient(i) && GetClientAuthId(i, AuthId_SteamID64, sOther, sizeof(sOther)) && StrEqual(sOther, sParts[k]));
		}
		
		if (!bHere)
		{
			Format(g_sBlockIds[iClient], sizeof(g_sBlockIds[]), "%s%s%s", g_sBlockIds[iClient], g_sBlockIds[iClient][0] == '\0' ? "" : ",", sParts[k]);
		}
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bBlockLand[iClient][i] && IsClientInGame(i) && GetClientAuthId(i, AuthId_SteamID64, sId, sizeof(sId)))
		{
			Format(g_sBlockIds[iClient], sizeof(g_sBlockIds[]), "%s%s%s", g_sBlockIds[iClient], g_sBlockIds[iClient][0] == '\0' ? "" : ",", sId);
		}
	}
	
	Cel_SetClientSettingString(iClient, "blockedlands", g_sBlockIds[iClient]);
}

public Action Command_Block(int iClient, int iArgs)
{
	return SetBlock(iClient, iArgs, true);
}

public Action Command_Unblock(int iClient, int iArgs)
{
	return SetBlock(iClient, iArgs, false);
}

Action SetBlock(int iClient, int iArgs, bool bBlockCommand)
{
	char sTarget[MAX_NAME_LENGTH], sList[512];
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	//No name: who is blocked.
	if (iArgs < 1)
	{
		sList[0] = '\0';
		
		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_bBlockLand[iClient][i] && IsClientInGame(i))
			{
				Format(sList, sizeof(sList), "%s%s{green}%N{default}", sList, sList[0] == '\0' ? "" : ", ", i);
			}
		}
		
		if (sList[0] == '\0')
		{
			Cel_ReplyToCommand(iClient, "Usage: {green}[tag]block{default} <player> keeps you out of their land. You have not blocked anyone who is here.");
		} else {
			Cel_ReplyToCommand(iClient, "You are keeping yourself out of the lands of: %s.", sList);
		}
		
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
		Cel_ReplyToCommand(iClient, "You can't block yourself from your own land.");
		return Plugin_Handled;
	}
	
	//!block on someone already blocked lets you back in, like a toggle; !unblock always lets you back in.
	bool bBlock = bBlockCommand ? !g_bBlockLand[iClient][iTarget] : false;
	
	g_bBlockLand[iClient][iTarget] = bBlock;
	
	SaveBlocks(iClient);
	
	if (bBlock)
	{
		Cel_ReplyToCommand(iClient, "You can no longer enter {green}%N{default}'s land. Type {green}[tag]block %N{default} again to undo it.", iTarget, iTarget);
		
		//Already inside it: put outside straight away.
		float fOrigin[3];
		
		GetClientAbsOrigin(iClient, fOrigin);
		
		fOrigin[2] += 16.0;
		
		if (IsPlayerAlive(iClient) && Cel_GetLandOwnerFromPosition(fOrigin) == iTarget)
		{
			g_bOutsideKnown[iClient] = false;
			
			DispatchSpawn(iClient);
		}
	} else {
		Cel_ReplyToCommand(iClient, "You can enter {green}%N{default}'s land again.", iTarget);
	}
	
	return Plugin_Handled;
}

//Players are stopped at the edge of lands they blocked themselves from: put back where they last stood outside.
public Action Timer_BlockLands(Handle hTimer)
{
	float fOrigin[3], fZero[3];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			g_bOutsideKnown[i] = false;
			continue;
		}
		
		GetClientAbsOrigin(i, fOrigin);
		
		float fCheck[3];
		
		fCheck = fOrigin;
		fCheck[2] += 16.0;
		
		int iOwner = Cel_GetLandOwnerFromPosition(fCheck);
		
		bool bFee = (iOwner >= 1 && iOwner <= MaxClients && iOwner != i && g_iLandFee[iOwner] > 0 && !g_bFeePaid[iOwner][i] && IsClientInGame(iOwner) && !Cel_IsOnBuildTeam(iOwner, i));
		
		//!nofly: a visitor flying in, from any side (from below too), is stopped at the edge like a blocked land.
		bool bNoFly = (iOwner >= 1 && iOwner <= MaxClients && iOwner != i && g_bNoFly[iOwner] && GetEntityMoveType(i) == MOVETYPE_NOCLIP && NoFlyOwnerAt(i) == iOwner);
		
		if (iOwner < 1 || iOwner > MaxClients || iOwner == i || (!g_bBlockLand[i][iOwner] && !bFee && !bNoFly) || !Cel_IsPlayer(iOwner) || !Cel_IsLandCreated(iOwner))
		{
			g_fLastOutside[i] = fOrigin;
			g_bOutsideKnown[i] = true;
			continue;
		}
		
		if (g_bOutsideKnown[i])
		{
			TeleportEntity(i, g_fLastOutside[i], NULL_VECTOR, fZero);
		} else {
			DispatchSpawn(i);
		}
		
		if (GetGameTime() >= g_fNextBlockNotice[i])
		{
			g_fNextBlockNotice[i] = GetGameTime() + 3.0;
			
			if (bNoFly && !g_bBlockLand[i][iOwner])
			{
				Cel_PrintToChat(i, "{green}%N{default} has turned noclip off in their land. Walk in instead.", iOwner);
				continue;
			}
			
			if (!g_bBlockLand[i][iOwner])
			{
				g_iFeeAsked[i] = iOwner;
				
				Cel_PrintToChat(i, "{green}%N{default}'s land has an entry fee of {green}%d CL{default}. Type {green}[tag]fee pay{default} to pay it and go in.", iOwner, g_iLandFee[iOwner]);
				continue;
			}
			
			Cel_PrintToChat(i, "You blocked yourself from {green}%N{default}'s land. Type {green}[tag]block %N{default} to undo it.", iOwner, iOwner);
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_LandBans(Handle hTimer)
{
	float fOrigin[3];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iNoWepsOwner[i] = 0;
		
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
		
		//!nofly: flying into the land puts the player back on their feet.
		if (g_bNoFly[iOwner] && GetEntityMoveType(i) == MOVETYPE_NOCLIP && NoFlyOwnerAt(i) == iOwner)
		{
			SetEntityMoveType(i, MOVETYPE_WALK);
			
			Cel_PrintToChat(i, "{green}%N{default} has turned noclip off in their land.", iOwner);
		}
		
		//Remembered here (twice a second) so the weapon block below doesn't look up lands every frame.
		if (g_bNoWeps[iOwner])
		{
			g_iNoWepsOwner[i] = iOwner;
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
	
	if (g_iMoveToRef[iClient] == INVALID_ENT_REFERENCE || iMoving == INVALID_ENT_REFERENCE || !Cel_CanEdit(iClient, iMoving))
	{
		if (!Cel_CanEdit(iClient, iProp))
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
	
	if (Cel_RefusePerm(iClient, iMoving))
	{
		return Plugin_Handled;
	}
	
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

//!nofly: other players can't noclip inside your land: turning it on there is refused, and anyone flying in is put
//back on their feet. You, your build team and admins with !zonebypass can still fly. Remembered.
public Action Command_LandNoFly(int iClient, int iArgs)
{
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	g_bNoFly[iClient] = !g_bNoFly[iClient];
	
	Cel_SetClientSettingInt(iClient, "land-nofly", g_bNoFly[iClient] ? 1 : 0);
	
	if (g_bNoFly[iClient])
	{
		Cel_ReplyToCommand(iClient, "Noclip is now {green}off{default} for other players in your land. Type {green}[tag]nofly{default} to allow it again.");
	} else {
		Cel_ReplyToCommand(iClient, "Other players can noclip in your land again.");
	}
	
	return Plugin_Handled;
}

//The land owner whose !nofly stops this player flying where they stand (0 = none).
int NoFlyOwnerAt(int iClient)
{
	float fOrigin[3];
	
	GetClientAbsOrigin(iClient, fOrigin);
	fOrigin[2] += 16.0;
	
	int iOwner = Cel_GetLandOwnerFromPosition(fOrigin);
	
	if (iOwner < 1 || iOwner > MaxClients || iOwner == iClient || !g_bNoFly[iOwner] || !IsClientInGame(iOwner) || !Cel_IsLandCreated(iOwner)
		|| Cel_IsOnBuildTeam(iOwner, iClient) || Cel_ZoneExempt(iClient))
	{
		return 0;
	}
	
	return iOwner;
}

public Action Listener_NoFly(int iClient, const char[] sCommand, int iArgc)
{
	if (iClient < 1 || iClient > MaxClients || !IsClientInGame(iClient) || !IsPlayerAlive(iClient) || GetEntityMoveType(iClient) == MOVETYPE_NOCLIP)
	{
		return Plugin_Continue;
	}
	
	int iOwner = NoFlyOwnerAt(iClient);
	
	if (iOwner != 0)
	{
		Cel_PrintToChat(iClient, "{green}%N{default} has turned noclip off in their land.", iOwner);
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

//!weps: other players' weapons stop working inside your land (they can still use the gravity gun). Remembered.
public Action Command_LandWeps(int iClient, int iArgs)
{
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	g_bNoWeps[iClient] = !g_bNoWeps[iClient];
	
	Cel_SetClientSettingInt(iClient, "land-noweps", g_bNoWeps[iClient] ? 1 : 0);
	
	if (g_bNoWeps[iClient])
	{
		Cel_ReplyToCommand(iClient, "Outside weapons are now {green}off{default} in your land: other players can't fire their weapons inside it. Type {green}[tag]weps{default} to turn them back on.");
	} else {
		Cel_ReplyToCommand(iClient, "Outside weapons are now {green}on{default} in your land again.");
	}
	
	return Plugin_Handled;
}

//!text <words>: the words, built out of text screens (models/celmod/txtscreen1-4), one per character, centred on the
//crosshair and facing you. ^ in front of the words makes small text, like the original server. Each screen is an
//ordinary prop of yours (frozen), so it can be moved, colored, saved and deleted like any other.
//  txtscreen1 / txtscreen3 (big / small): skins 0-29 = a-z, 0-3
//  txtscreen2 / txtscreen4 (big / small): skins 0-11 = 4-9 ! ? : - ( )
public Action Command_Text(int iClient, int iArgs)
{
	static const char sSet1[] = "abcdefghijklmnopqrstuvwxyz0123";
	static const char sSet2[] = "456789!?:-()";
	char sText[64], sDisplay[64], sSkipped[32];
	float fHit[3], fEyes[3], fAngles[3], fPos[3];
	int iPrice;
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	if (Cel_CheckShopDB("text", iPrice, sDisplay, sizeof(sDisplay)) && !Cel_CheckClientPurchase(iClient, "text"))
	{
		Cel_ReplyToCommand(iClient, "{green}[tag]text{default} writes words in the world. Buy it for {green}%d CL{default} with {green}[tag]buy text{default}.", iPrice);
		return Plugin_Handled;
	}
	
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);
	TrimString(sText);
	
	bool bSmall = (sText[0] == '^');
	
	if (bSmall)
	{
		strcopy(sText, sizeof(sText), sText[1]);
		TrimString(sText);
	}
	
	if (sText[0] == '\0')
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]text <words>{default} (letters, numbers and {green}! ? : - ( ){default}). Put {green}^{default} in front for small text.");
		return Plugin_Handled;
	}
	
	int iLength = strlen(sText);
	
	if (iLength > 32)
	{
		Cel_ReplyToCommand(iClient, "That's too long: up to {green}32{default} characters at once.");
		return Plugin_Handled;
	}
	
	// The screens lie flat on the surface under the crosshair (wall, floor, ceiling or slope), facing out of it, the row
	// centred on the crosshair. Text "up" is the world's up on walls and slopes; on a floor it points the way the player
	// faces, and on a ceiling back towards them, so it always reads upright and left to right from where they stand.
	float fWidth = bSmall ? 10.0 : 22.0;
	float fNormal[3], fUp[3], fForward[3], fRow[3], fFlat[3], fPropAngles[3];
	
	GetClientEyePosition(iClient, fEyes);
	GetClientEyeAngles(iClient, fAngles);
	
	Handle hTrace = TR_TraceRayFilterEx(fEyes, fAngles, MASK_SOLID, RayType_Infinite, Cel_FilterPlayer, iClient);
	
	if (!TR_DidHit(hTrace))
	{
		delete hTrace;
		Cel_ReplyToCommand(iClient, "Aim at a wall, floor or ceiling to write on it.");
		return Plugin_Handled;
	}
	
	TR_GetEndPosition(fHit, hTrace);
	TR_GetPlaneNormal(hTrace, fNormal);
	delete hTrace;
	
	NormalizeVector(fNormal, fNormal);
	
	// The player's facing, flat.
	fFlat[0] = 0.0;
	fFlat[1] = fAngles[1];
	fFlat[2] = 0.0;
	GetAngleVectors(fFlat, fForward, NULL_VECTOR, NULL_VECTOR);
	
	if (FloatAbs(fNormal[2]) < 0.7)
	{
		fUp[0] = 0.0; fUp[1] = 0.0; fUp[2] = 1.0;
	} else if (fNormal[2] > 0.0) {
		fUp = fForward;
	} else {
		fUp[0] = -fForward[0]; fUp[1] = -fForward[1]; fUp[2] = 0.0;
	}
	
	// Up, kept flat against the surface.
	float fAlong = GetVectorDotProduct(fUp, fNormal);
	
	for (int k = 0; k < 3; k++)
	{
		fUp[k] -= fNormal[k] * fAlong;
	}
	
	NormalizeVector(fUp, fUp);
	
	// The row runs along the text's right: up x normal.
	GetVectorCrossProduct(fUp, fNormal, fRow);
	NormalizeVector(fRow, fRow);
	
	// The screen's front is its local +X (measured in game: pointed into the surface, players saw the backs), so +X
	// points out of the surface, and its up (local +Z) is fUp, with the roll worked out from the up vector the pitch
	// and yaw alone would give.
	float fRight0[3], fUp0[3];
	
	GetVectorAngles(fNormal, fPropAngles);
	fPropAngles[2] = 0.0;
	GetAngleVectors(fPropAngles, NULL_VECTOR, fRight0, fUp0);
	fPropAngles[2] = RadToDeg(ArcTangent2(GetVectorDotProduct(fUp, fRight0), GetVectorDotProduct(fUp, fUp0)));
	
	// Sitting on the surface (half the screen's thickness out of it), with the middle of the characters on the crosshair.
	for (int k = 0; k < 3; k++)
	{
		fHit[k] += fNormal[k] * 0.6 - fUp[k] * 5.0;
	}
	
	int iSpawned = 0, iSkippedCount = 0;
	
	for (int i = 0; i < iLength; i++)
	{
		int c = CharToLower(sText[i]);
		
		if (c == ' ')
		{
			continue;
		}
		
		int iSkin = FindCharInString(sSet1, c), iModelSet = 1;
		
		if (iSkin == -1)
		{
			iSkin = FindCharInString(sSet2, c);
			iModelSet = 2;
		}
		
		if (iSkin == -1)
		{
			if (iSkippedCount < sizeof(sSkipped) - 1 && FindCharInString(sSkipped, c) == -1)
			{
				sSkipped[iSkippedCount++] = c;
				sSkipped[iSkippedCount] = '\0';
			}
			
			continue;
		}
		
		if (!Cel_CheckPropCount(iClient))
		{
			Cel_ReplyToCommand(iClient, "%t", "MaxPropLimit", Cel_GetPropCount(iClient));
			break;
		}
		
		// Character i sits (i - middle) widths along the row from the crosshair.
		float fShift = (float(i) - float(iLength - 1) / 2.0) * fWidth;
		
		for (int k = 0; k < 3; k++)
		{
			fPos[k] = fHit[k] + fRow[k] * fShift;
		}
		
		char sModel[64], sAlias[16];
		int iModel = (bSmall ? 2 : 0) + iModelSet;
		
		FormatEx(sModel, sizeof(sModel), "models/celmod/txtscreen%d.mdl", iModel);
		FormatEx(sAlias, sizeof(sAlias), "text%d", iModel);
		
		int iProp = Cel_SpawnProp(iClient, sAlias, "prop_physics_override", sModel, fPropAngles, fPos, 255, 255, 255, 255);
		
		if (iProp == -1)
		{
			break;
		}
		
		SetEntProp(iProp, Prop_Send, "m_nSkin", iSkin);
		
		iSpawned++;
	}
	
	if (iSpawned > 0)
	{
		Cel_ReplyToCommand(iClient, "Wrote {green}%s{default} (%d screens).", sText, iSpawned);
	}
	
	if (iSkippedCount > 0)
	{
		Cel_ReplyToCommand(iClient, "These characters aren't available and were left out: {green}%s{default}", sSkipped);
	}
	
	return Plugin_Handled;
}

//!arsenal (the old !weps): every weapon, bought once in the shop when the shop sells it.
public Action Command_Arsenal(int iClient, int iArgs)
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
	
	char sDisplay[64];
	int iPrice;
	
	if (Cel_CheckShopDB("arsenal", iPrice, sDisplay, sizeof(sDisplay)) && !Cel_CheckClientPurchase(iClient, "arsenal"))
	{
		Cel_ReplyToCommand(iClient, "{green}[tag]arsenal{default} gives you every weapon. Buy it for {green}%d CL{default} with {green}[tag]buy arsenal{default}.", iPrice);
		return Plugin_Handled;
	}
	
	GetClientAbsOrigin(iClient, fOrigin);
	
	fOrigin[2] += 16.0;
	
	int iLandOwner = Cel_GetLandOwnerFromPosition(fOrigin);
	
	//Weapons are for outside of lands, a land owner decides what happens inside theirs.
	if (iLandOwner > 0 && iLandOwner != iClient && Cel_IsPlayer(iLandOwner) && Cel_IsLandCreated(iLandOwner))
	{
		Cel_ReplyToCommand(iClient, "You cannot use {green}[tag]arsenal{default} inside another player's land.");
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
		char sCommand[16];
		
		GetCmdArg(0, sCommand, sizeof(sCommand));
		ReplaceString(sCommand, sizeof(sCommand), "v_", "", false);
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]%s{default} <player> (kicks them out of your land for 10 seconds)", sCommand);
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
	
	if (!Cel_CanEdit(iClient, iProp))
	{
		Cel_NotYours(iClient, iProp);
		return Plugin_Handled;
	}
	
	int iFirst = EntRefToEntIndex(g_iWeldRef[iClient]);
	
	if (g_iWeldRef[iClient] == INVALID_ENT_REFERENCE || iFirst == INVALID_ENT_REFERENCE || !Cel_CanEdit(iClient, iFirst))
	{
		g_iWeldRef[iClient] = EntIndexToEntRef(iProp);
		
		Cel_ChangeBeam(iClient, iProp);
		
		Cel_ReplyToCommandEntity(iClient, iProp, "Selected this [type]. Now look at the entity it should be welded to and type {green}[tag]weld{default} again.");
		
		return Plugin_Handled;
	}
	
	g_iWeldRef[iClient] = INVALID_ENT_REFERENCE;
	
	//The welded prop is the one that gets carried: a perm prop stays put. (Welding onto a perm prop is fine.)
	if (Cel_RefusePerm(iClient, iFirst))
	{
		return Plugin_Handled;
	}
	
	if (iFirst == iProp || ParentLoops(iFirst, iProp))
	{
		Cel_ReplyToCommand(iClient, "Weld cancelled.");
		return Plugin_Handled;
	}
	
	//A welded prop is carried by the other one: its own physics is frozen first, as a moving physics object that is
	//also parented fights the hierarchy inside the physics engine.
	Cel_SetMotion(iFirst, false);
	
	SetVariantString("!activator");
	AcceptEntityInput(iFirst, "SetParent", iProp, iFirst);
	
	Cel_ChangeBeam(iClient, iFirst);
	
	Cel_ReplyToCommandEntity(iClient, iFirst, "Welded your [type]. It now moves with the other entity. ");
	
	return Plugin_Handled;
}

//True when parenting iChild to iParent would make a loop (iChild is already above iParent): the engine
//crashes on a parent loop. Also refuses parenting to players.
bool ParentLoops(int iChild, int iParent)
{
	int iWalk = iParent;
	
	for (int iDepth = 0; iDepth < 64 && iWalk > 0; iDepth++)
	{
		if (iWalk == iChild || iWalk <= MaxClients)
		{
			return true;
		}
		
		iWalk = GetEntPropEnt(iWalk, Prop_Data, "m_hMoveParent");
	}
	
	return (iWalk > 0);
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
	
	if (!Cel_CanEdit(iClient, iProp))
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

public Action Command_Fee(int iClient, int iArgs)
{
	char sArg[32];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sArg, sizeof(sArg));
	
	if (iArgs < 1)
	{
		if (g_iLandFee[iClient] > 0)
		{
			Cel_ReplyToCommand(iClient, "Your land's entry fee is {green}%d CL{default}. {green}[tag]fee 0{default} makes it free.", g_iLandFee[iClient]);
		} else {
			Cel_ReplyToCommand(iClient, "Your land is free to enter. Usage: {green}[tag]fee{default} <amount>, or {green}[tag]fee pay{default} to pay another land's fee.");
		}
		
		return Plugin_Handled;
	}
	
	if (StrEqual(sArg, "pay", false))
	{
		int iOwner = g_iFeeAsked[iClient];
		
		if (iOwner < 1 || iOwner > MaxClients || !IsClientInGame(iOwner) || g_iLandFee[iOwner] <= 0)
		{
			Cel_ReplyToCommand(iClient, "There is no land fee to pay. Walk up to a land with a fee first.");
			return Plugin_Handled;
		}
		
		if (g_bFeePaid[iOwner][iClient])
		{
			Cel_ReplyToCommand(iClient, "You already paid to enter {green}%N{default}'s land.", iOwner);
			return Plugin_Handled;
		}
		
		int iFee = g_iLandFee[iOwner];
		
		if (!Cel_CheckClientBalance(iClient, iFee))
		{
			Cel_ReplyToCommand(iClient, "You need {green}%d CL{default} to enter {green}%N{default}'s land.", iFee, iOwner);
			return Plugin_Handled;
		}
		
		Cel_SubFromClientBalance(iClient, iFee);
		Cel_AddToClientBalance(iOwner, iFee);
		
		g_bFeePaid[iOwner][iClient] = true;
		
		Cel_ReplyToCommand(iClient, "You paid {green}%d CL{default}: you can enter {green}%N{default}'s land until one of you leaves.", iFee, iOwner);
		Cel_PrintToChat(iOwner, "{green}%N{default} paid your {green}%d CL{default} land fee.", iClient, iFee);
		
		return Plugin_Handled;
	}
	
	if (StrEqual(sArg, "off", false))
	{
		strcopy(sArg, sizeof(sArg), "0");
	}
	
	int iFee = StringToInt(sArg);
	
	if ((iFee == 0 && !StrEqual(sArg, "0")) || iFee < 0)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]fee{default} <amount> (0 = free), or {green}[tag]fee pay{default}.");
		return Plugin_Handled;
	}
	
	if (iFee > g_cvLandFeeMax.IntValue)
	{
		Cel_ReplyToCommand(iClient, "The highest land fee is {green}%d CL{default}.", g_cvLandFeeMax.IntValue);
		return Plugin_Handled;
	}
	
	g_iLandFee[iClient] = iFee;
	
	//A new fee: everyone pays again (people already inside are moved out by the land check).
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_bFeePaid[iClient][i] = false;
	}
	
	if (iFee > 0)
	{
		Cel_ReplyToCommand(iClient, "Players now pay {green}%d CL{default} to enter your land (your build team gets in free).", iFee);
	} else {
		Cel_ReplyToCommand(iClient, "Your land is free to enter again.");
	}
	
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
	
	//Being banned from someone's land counts toward the website's "Most Hated" leaderboard.
	if (bBan && !g_bLandBan[iClient][iTarget])
	{
		Cel_AddStat(iTarget, "land_bans");
	}
	
	g_bLandBan[iClient][iTarget] = bBan;
	g_fLandKickUntil[iClient][iTarget] = 0.0;
	
	if (bBan)
	{
		Cel_PrintToChat(iTarget, "Player {green}%N{default} has banned you from their land.", iClient);
		Cel_ReplyToCommand(iClient, "{green}%N{default} is banned from your land until they or you leave the server.", iTarget);
	} else {
		Cel_PrintToChat(iTarget, "Player {green}%N{default} has unbanned you from their land.", iClient);
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
	
	Cel_ReplyToCommand(iClient, "Spawned a message cel. Players read it by pressing {green}E{default} on it.");
	
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
	
	//A soda can: press E on it to play its sound.
	int iProp = SpawnUsableProp(iClient, "sound", "models/props_junk/popcan01a.mdl");
	
	if (iProp == -1)
	{
		return Plugin_Handled;
	}
	
	PrecacheSound(sPath);
	
	strcopy(g_sSound[iProp], sizeof(g_sSound[]), sPath);
	
	g_fNextSoundUse[iProp] = 0.0;
	
	SDKHook(iProp, SDKHook_UsePost, Hook_SoundUse);
	
	Cel_ReplyToCommand(iClient, "Spawned a {green}%s{default} sound cel. Press {green}E{default} on it to play it.", sName);
	
	return Plugin_Handled;
}

//A music cel that is deleted while playing stops its song for everyone.
public void OnEntityDestroyed(int iEntity)
{
	if (iEntity > MaxClients && iEntity <= MAXENTITIES && g_sMusic[iEntity][0] != '\0' && GetGameTime() < g_fMusicEnds[iEntity])
	{
		StopSound(iEntity, SNDCHAN_STATIC, g_sMusic[iEntity]);
	}
	
	if (iEntity > 0 && iEntity <= MAXENTITIES)
	{
		g_sMusic[iEntity][0] = '\0';
		g_fMusicEnds[iEntity] = 0.0;
	}
}

//Music cel: plays a song from the "Music" list in data/celmod/sounds.txt. E starts it, E again stops it.
bool FindSong(const char[] sName, char[] sPath, int iMaxLength, float &fLength)
{
	char sValue[PLATFORM_MAX_PATH], sParts[2][PLATFORM_MAX_PATH];
	
	KeyValues kvSounds = new KeyValues("Sounds");
	
	kvSounds.ImportFromFile(g_sSoundDB);
	
	bool bFound = (kvSounds.JumpToKey("Music", false));
	
	if (bFound)
	{
		kvSounds.GetString(sName, sValue, sizeof(sValue), "");
		
		bFound = (sValue[0] != '\0');
	}
	
	delete kvSounds;
	
	if (!bFound)
	{
		return false;
	}
	
	//"path|length in seconds"
	int iParts = ExplodeString(sValue, "|", sParts, 2, sizeof(sParts[]));
	
	strcopy(sPath, iMaxLength, sParts[0]);
	
	fLength = (iParts > 1) ? StringToFloat(sParts[1]) : 0.0;
	
	return true;
}

public Action Command_Music(int iClient, int iArgs)
{
	char sName[64], sPath[PLATFORM_MAX_PATH], sPitch[8];
	float fLength;
	int iPitch = 100;
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]music{default} <song> [speed 50-200]. Type {green}[tag]celmusic{default} for the list of songs.");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sName, sizeof(sName));
	
	if (!FindSong(sName, sPath, sizeof(sPath), fLength))
	{
		Cel_ReplyToCommand(iClient, "There is no song called {green}%s{default}. Type {green}[tag]celmusic{default} for the list.", sName);
		return Plugin_Handled;
	}
	
	if (iArgs > 1)
	{
		GetCmdArg(2, sPitch, sizeof(sPitch));
		
		iPitch = StringToInt(sPitch);
		
		if (iPitch < 50) iPitch = 50;
		if (iPitch > 200) iPitch = 200;
	}
	
	//A radio: press E on it to play its song, and again to stop it.
	int iProp = SpawnUsableProp(iClient, "music", "models/props_lab/citizenradio.mdl");
	
	if (iProp == -1)
	{
		return Plugin_Handled;
	}
	
	SetupMusicCel(iProp, sPath, fLength, iPitch);
	
	Cel_ReplyToCommand(iClient, "Spawned a {green}%s{default} music cel. Press {green}E{default} on it to play it, and again to stop it.", sName);
	
	return Plugin_Handled;
}

void SetupMusicCel(int iProp, const char[] sPath, float fLength, int iPitch)
{
	PrecacheSound(sPath);
	
	strcopy(g_sMusic[iProp], sizeof(g_sMusic[]), sPath);
	
	g_fMusicLength[iProp] = fLength;
	g_iMusicPitch[iProp] = iPitch;
	g_fMusicEnds[iProp] = 0.0;
	
	SetEntProp(iProp, Prop_Data, "m_spawnflags", GetEntProp(iProp, Prop_Data, "m_spawnflags") | 256);
	
	SDKHook(iProp, SDKHook_UsePost, Hook_MusicUse);
}

public void Hook_MusicUse(int iEntity, int iActivator, int iCaller, UseType utType, float fValue)
{
	if (g_sMusic[iEntity][0] == '\0' || GetGameTime() < g_fNextSoundUse[iEntity] || Cel_IsLocked(iEntity))
	{
		return;
	}
	
	g_fNextSoundUse[iEntity] = GetGameTime() + 0.5;
	
	//Playing: stop it.
	if (GetGameTime() < g_fMusicEnds[iEntity])
	{
		StopSound(iEntity, SNDCHAN_STATIC, g_sMusic[iEntity]);
		
		g_fMusicEnds[iEntity] = 0.0;
		
		return;
	}
	
	EmitSoundToAll(g_sMusic[iEntity], iEntity, SNDCHAN_STATIC, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, g_iMusicPitch[iEntity]);
	
	//A faster song ends sooner.
	float fLength = (g_fMusicLength[iEntity] > 0.0) ? g_fMusicLength[iEntity] : 600.0;
	
	g_fMusicEnds[iEntity] = GetGameTime() + fLength * 100.0 / g_iMusicPitch[iEntity];
}

//The songs a music cel can play, with how long each one is.
public Action Command_CelMusic(int iClient, int iArgs)
{
	char sName[64], sValue[PLATFORM_MAX_PATH], sParts[2][PLATFORM_MAX_PATH], sLine[256];
	int iCount = 0, iOnLine = 0;
	
	KeyValues kvSounds = new KeyValues("Sounds");
	
	if (!kvSounds.ImportFromFile(g_sSoundDB) || !kvSounds.JumpToKey("Music", false) || !kvSounds.GotoFirstSubKey(false))
	{
		delete kvSounds;
		
		Cel_ReplyToCommand(iClient, "There are no songs for the music cel on this server.");
		return Plugin_Handled;
	}
	
	Cel_ReplyToCommand(iClient, "Music cel songs ({green}[tag]music{default} <song> [speed 50-200]):");
	
	sLine[0] = '\0';
	
	do
	{
		kvSounds.GetSectionName(sName, sizeof(sName));
		kvSounds.GetString(NULL_STRING, sValue, sizeof(sValue), "");
		
		int iLength = (ExplodeString(sValue, "|", sParts, 2, sizeof(sParts[])) > 1) ? RoundToFloor(StringToFloat(sParts[1])) : 0;
		
		if (iLength > 0)
		{
			Format(sLine, sizeof(sLine), "%s%s{green}%s{default} (%d:%02d)", sLine, iOnLine > 0 ? ", " : "", sName, iLength / 60, iLength % 60);
		} else {
			Format(sLine, sizeof(sLine), "%s%s{green}%s{default}", sLine, iOnLine > 0 ? ", " : "", sName);
		}
		
		iCount++;
		iOnLine++;
		
		//A few to a line, so chat does not cut them off.
		if (iOnLine == 5)
		{
			Cel_ReplyToCommand(iClient, "%s", sLine);
			
			sLine[0] = '\0';
			iOnLine = 0;
		}
	}
	while (kvSounds.GotoNextKey(false));
	
	delete kvSounds;
	
	if (iOnLine > 0)
	{
		Cel_ReplyToCommand(iClient, "%s", sLine);
	}
	
	if (iCount == 0)
	{
		Cel_ReplyToCommand(iClient, "There are no songs for the music cel on this server.");
	}
	
	return Plugin_Handled;
}

public Action Command_Model(int iClient, int iArgs)
{
	char sAlias[64], sCommand[96];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]model{default} <prop name>");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sAlias, sizeof(sAlias));
	
	//Quotes and semicolons would let the argument run a second command.
	ReplaceString(sAlias, sizeof(sAlias), "\"", "");
	ReplaceString(sAlias, sizeof(sAlias), ";", "");
	
	Format(sCommand, sizeof(sCommand), "v_replace \"%s\"", sAlias);
	
	RunCelCommand(iClient, sCommand);
	
	return Plugin_Handled;
}

public Action Command_Palette(int iClient, int iArgs)
{
	char sValue[3][16];
	int iColor[3];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 3)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]palette{default} <red> <green> <blue> (each 0 to 255)");
		return Plugin_Handled;
	}
	
	int iProp = Cel_GetClientAimTarget(iClient);
	
	if (iProp == -1)
	{
		Cel_NotLooking(iClient);
		return Plugin_Handled;
	}
	
	if (Cel_RefuseSpecial(iClient, iProp))
	{
		return Plugin_Handled;
	}
	
	if (!Cel_CanEdit(iClient, iProp))
	{
		Cel_NotYours(iClient, iProp);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < 3; i++)
	{
		GetCmdArg(i + 1, sValue[i], sizeof(sValue[]));
		
		iColor[i] = StringToInt(sValue[i]);
		
		if (iColor[i] < 0) iColor[i] = 0;
		if (iColor[i] > 255) iColor[i] = 255;
	}
	
	Cel_SetRainbow(iProp, false);
	Cel_SetColorFade(iProp, false, 0, 0, 0, 0, 0, 0);
	Cel_SetColor(iProp, iColor[0], iColor[1], iColor[2], -1);
	
	Cel_ChangeBeam(iClient, iProp);
	
	Cel_ReplyToCommandEntity(iClient, iProp, "Colored your [type] {green}%d %d %d{default}.", iColor[0], iColor[1], iColor[2]);
	
	return Plugin_Handled;
}

//The first pad a player spawns is the entrance, the second is where it leads. Then the pair is complete.
//The spawn point cel: anyone who dies inside its owner's land respawns on it. It only works inside that land.
public Action Command_SpawnPoint(int iClient, int iArgs)
{
	float fAngles[3], fOrigin[3];
	char sModel[PLATFORM_MAX_PATH];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	Cel_GetCrosshairHitOrigin(iClient, fOrigin);
	
	if (Cel_GetLandOwnerFromPosition(fOrigin) != iClient)
	{
		Cel_ReplyToCommand(iClient, "A spawn point only works inside your own land.");
		return Plugin_Handled;
	}
	
	if (!Cel_CheckPropCount(iClient))
	{
		Cel_ReplyToCommand(iClient, "You have reached your prop limit.");
		return Plugin_Handled;
	}
	
	g_cvSpawnPointModel.GetString(sModel, sizeof(sModel));
	
	GetClientAbsAngles(iClient, fAngles);
	fAngles[0] = 0.0;
	
	int iPoint = Cel_SpawnProp(iClient, "spawnpoint", "prop_physics_override", sModel, fAngles, fOrigin, 0, 220, 170, 255);
	
	if (iPoint == -1)
	{
		return Plugin_Handled;
	}
	
	Cel_FixSpawnPosition(iPoint, fOrigin);
	AcceptEntityInput(iPoint, "DisableMotion");
	
	bool bMoved = SetSpawnPoint(iClient, iPoint);
	
	Cel_ReplyToCommand(iClient, bMoved ? "Moved your spawn point. Anyone who dies in your land respawns here." : "Placed a spawn point. Anyone who dies in your land respawns here.");
	
	return Plugin_Handled;
}

//Keeps one spawn point per player; an older one is removed. Returns true when one was replaced.
bool SetSpawnPoint(int iClient, int iPoint)
{
	int iOld = EntRefToEntIndex(g_iSpawnPointRef[iClient]);
	bool bReplaced = false;
	
	if (g_iSpawnPointRef[iClient] != INVALID_ENT_REFERENCE && iOld != INVALID_ENT_REFERENCE && iOld != iPoint)
	{
		AcceptEntityInput(iOld, "Kill");
		bReplaced = true;
	}
	
	g_iSpawnPointRef[iClient] = EntIndexToEntRef(iPoint);
	
	return bReplaced;
}

public void Event_SpawnPointDeath(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(eEvent.GetInt("userid"));
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return;
	}
	
	float fOrigin[3];
	
	GetClientAbsOrigin(iClient, fOrigin);
	
	g_iDiedInLand[iClient] = Cel_GetLandOwnerFromPosition(fOrigin);
}

public void Event_SpawnPointSpawn(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(eEvent.GetInt("userid"));
	
	if (iClient > 0 && g_iDiedInLand[iClient] > 0)
	{
		//A frame later, so the game has finished placing the player.
		RequestFrame(Frame_SpawnPointRespawn, GetClientUserId(iClient));
	}
}

public void Frame_SpawnPointRespawn(any iUserId)
{
	int iClient = GetClientOfUserId(iUserId);
	
	if (iClient < 1 || !IsClientInGame(iClient) || !IsPlayerAlive(iClient))
	{
		return;
	}
	
	int iOwner = g_iDiedInLand[iClient];
	
	g_iDiedInLand[iClient] = 0;
	
	if (iOwner < 1 || iOwner > MaxClients || !IsClientInGame(iOwner) || g_bBlockLand[iOwner][iClient] || g_bBlockLand[iClient][iOwner])
	{
		return;
	}
	
	int iPoint = EntRefToEntIndex(g_iSpawnPointRef[iOwner]);
	
	//The spawn point must still be inside its owner's land.
	if (g_iSpawnPointRef[iOwner] == INVALID_ENT_REFERENCE || iPoint == INVALID_ENT_REFERENCE || Cel_GetLandOwnerFromEntity(iPoint) != iOwner)
	{
		return;
	}
	
	float fOrigin[3];
	
	Cel_GetEntityOrigin(iPoint, fOrigin);
	fOrigin[2] += 16.0;
	
	TeleportEntity(iClient, fOrigin, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
}

public Action Command_Teleport(int iClient, int iArgs)
{
	float fAngles[3], fOrigin[3];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (!Cel_CheckPropCount(iClient))
	{
		Cel_ReplyToCommand(iClient, "You have reached your prop limit.");
		return Plugin_Handled;
	}
	
	Cel_GetCrosshairHitOrigin(iClient, fOrigin);
	
	//The teleporter platform from Dr. Kleiner's lab (the old saw blade if a server is missing it).
	bool bLabPad = FileExists(TELEPORT_MODEL, true);
	
	GetClientAbsAngles(iClient, fAngles);
	fAngles[0] = 0.0;
	
	int iPad = Cel_SpawnProp(iClient, "teleport", "prop_physics_override", bLabPad ? TELEPORT_MODEL : "models/props_junk/sawblade001a.mdl", fAngles, fOrigin, bLabPad ? 255 : 0, bLabPad ? 255 : 200, 255, 255);
	
	if (iPad == -1)
	{
		return Plugin_Handled;
	}
	
	Cel_FixSpawnPosition(iPad, fOrigin);
	
	int iEntrance = EntRefToEntIndex(g_iTeleportRef[iClient]);
	
	if (g_iTeleportRef[iClient] == INVALID_ENT_REFERENCE || iEntrance == INVALID_ENT_REFERENCE || !Cel_CanEdit(iClient, iEntrance))
	{
		g_iTeleportRef[iClient] = EntIndexToEntRef(iPad);
		
		SDKHook(iPad, SDKHook_StartTouchPost, Hook_TeleportTouch);
		
		Cel_ReplyToCommand(iClient, "Spawned the teleport entrance. Type {green}[tag]teleport{default} again where it should lead.");
		
		return Plugin_Handled;
	}
	
	g_iTeleportDest[iEntrance] = EntIndexToEntRef(iPad);
	g_iTeleportRef[iClient] = INVALID_ENT_REFERENCE;
	
	Cel_SetColor(iPad, 255, 140, 0, 255);
	
	Cel_ReplyToCommand(iClient, "Spawned the teleport exit. Walking onto the blue pad now takes players to the orange one.");
	
	return Plugin_Handled;
}

//Launches a player off a hoopie, along the side of its face they touched, so tilted hoopies throw them sideways.
//Standing on (or landing on) a hoopie bounces the player. Checked every frame from what each player is standing on,
//because physics props don't always report players touching them.
public void OnGameFrame()
{
	char sModel[PLATFORM_MAX_PATH];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		// Unlimited aux power: kept full, so sprinting, the flashlight and swimming never drain it.
		if (g_cvUnlimitedAux.BoolValue && GetEntPropFloat(i, Prop_Send, "m_flSuitPower") < 100.0)
		{
			SetEntPropFloat(i, Prop_Send, "m_flSuitPower", 100.0);
		}
		
		int iGround = GetEntPropEnt(i, Prop_Send, "m_hGroundEntity");
		
		if (iGround <= MaxClients || !IsValidEntity(iGround))
		{
			continue;
		}
		
		GetEntPropString(iGround, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
		
		if (StrEqual(sModel, HOOPIE_MODEL, false))
		{
			Hook_HoopieTouch(iGround, i);
		}
	}
}

public void Hook_HoopieTouch(int iEntity, int iOther)
{
	if (iOther < 1 || iOther > MaxClients || !IsPlayerAlive(iOther) || GetGameTime() < g_fNextBounce[iOther])
	{
		return;
	}
	
	g_fNextBounce[iOther] = GetGameTime() + 0.25;
	
	float fAngles[3], fUp[3], fPropOrigin[3], fPlayerOrigin[3], fToPlayer[3], fVelocity[3];
	
	Cel_GetEntityAngles(iEntity, fAngles);
	GetAngleVectors(fAngles, NULL_VECTOR, NULL_VECTOR, fUp);
	
	Cel_GetEntityOrigin(iEntity, fPropOrigin);
	GetClientAbsOrigin(iOther, fPlayerOrigin);
	fPlayerOrigin[2] += 36.0;
	
	MakeVectorFromPoints(fPropOrigin, fPlayerOrigin, fToPlayer);
	
	if (GetVectorDotProduct(fToPlayer, fUp) < 0.0)
	{
		NegateVector(fUp);
	}
	
	GetEntPropVector(iOther, Prop_Data, "m_vecVelocity", fVelocity);
	
	float fStrength = g_cvHoopieBounce.FloatValue;
	
	//Keep the run-up's sideways speed, replace the speed into the hoopie with the bounce.
	float fInto = GetVectorDotProduct(fVelocity, fUp);
	
	for (int i = 0; i < 3; i++)
	{
		fVelocity[i] += fUp[i] * (fStrength - fInto);
	}
	
	TeleportEntity(iOther, NULL_VECTOR, NULL_VECTOR, fVelocity);
	
	EmitSoundToAll(HOOPIE_SOUND, iEntity, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.8, GetRandomInt(95, 120));
}

public void Hook_TeleportTouch(int iEntity, int iOther)
{
	float fOrigin[3];
	
	if (iOther < 1 || iOther > MaxClients || !IsPlayerAlive(iOther) || GetGameTime() < g_fNextTeleport[iOther] || Cel_IsLocked(iEntity))
	{
		return;
	}
	
	int iExit = EntRefToEntIndex(g_iTeleportDest[iEntity]);
	
	if (g_iTeleportDest[iEntity] == INVALID_ENT_REFERENCE || iExit == INVALID_ENT_REFERENCE)
	{
		return;
	}
	
	g_fNextTeleport[iOther] = GetGameTime() + 1.0;
	
	Cel_GetEntityOrigin(iExit, fOrigin);
	
	fOrigin[2] += 12.0;
	
	//Teleport pads can't carry players into an event or restricted area (a maze or parkour course).
	float fCheck[3];
	
	fCheck = fOrigin;
	fCheck[2] += 32.0;
	
	if (GetFeatureStatus(FeatureType_Native, "Cel_GetZoneType") == FeatureStatus_Available && !Cel_ZoneExempt(iOther))
	{
		int iDestZone = Cel_GetZoneType(fCheck);
		
		//A pad from inside a build area to somewhere else in one is fine (both ends were built in there).
		float fFrom[3];
		
		GetClientAbsOrigin(iOther, fFrom);
		fFrom[2] += 32.0;
		
		bool bInsideBuild = (iDestZone == CEL_ZONE_BUILD && Cel_GetZoneType(fFrom) == CEL_ZONE_BUILD);
		
		if (iDestZone != CEL_ZONE_NONE && !bInsideBuild)
		{
			Cel_PrintToChat(iOther, "This teleport pad leads into an event, restricted or build area, so it does not work.");
			return;
		}
	}
	
	TeleportEntity(iOther, fOrigin, NULL_VECTOR, NULL_VECTOR);
	
	EmitSoundToAll("ambient/machines/teleport1.wav", iExit);
}

//Build saving: every entity is given an id, and anything that points at another entity stores that entity's id.
public void Cel_OnSaveEntity(int iEntity, KeyValues kvSave)
{
	kvSave.SetNum("x_id", iEntity);
	
	if (g_sMessage[iEntity][0] != '\0')
	{
		kvSave.SetString("x_message", g_sMessage[iEntity]);
	}
	
	if (g_sSound[iEntity][0] != '\0')
	{
		kvSave.SetString("x_sound", g_sSound[iEntity]);
	}
	
	if (g_sMusic[iEntity][0] != '\0')
	{
		kvSave.SetString("x_music", g_sMusic[iEntity]);
		kvSave.SetFloat("x_musiclength", g_fMusicLength[iEntity]);
		kvSave.SetNum("x_musicpitch", g_iMusicPitch[iEntity]);
	}
	
	int iExit = EntRefToEntIndex(g_iTeleportDest[iEntity]);
	
	if (g_iTeleportDest[iEntity] != INVALID_ENT_REFERENCE && iExit != INVALID_ENT_REFERENCE)
	{
		kvSave.SetNum("x_teleport", iExit);
	}
	
	int iParent = GetEntPropEnt(iEntity, Prop_Data, "m_hMoveParent");
	
	if (iParent > MaxClients && Cel_IsEntity(iParent))
	{
		kvSave.SetNum("x_weld", iParent);
	}
	
	if (Cel_GetEntityType(iEntity) == ENTTYPE_TRIGGER && Cel_GetTriggerLink(iEntity) > 0)
	{
		kvSave.SetNum("x_link", Cel_GetTriggerLink(iEntity));
	}
}

public void Cel_OnLoadEntity(int iClient, int iEntity, KeyValues kvSave)
{
	char sId[16];
	int iLink[3];
	
	IntToString(kvSave.GetNum("x_id", -1), sId, sizeof(sId));
	
	g_smLoadIds[iClient].SetValue(sId, EntIndexToEntRef(iEntity));
	
	kvSave.GetString("x_message", g_sMessage[iEntity], sizeof(g_sMessage[]), "");
	
	if (g_sMessage[iEntity][0] != '\0')
	{
		SetEntProp(iEntity, Prop_Data, "m_spawnflags", GetEntProp(iEntity, Prop_Data, "m_spawnflags") | 256);
		
		SDKHook(iEntity, SDKHook_UsePost, Hook_MessageUse);
	}
	
	char sMusic[PLATFORM_MAX_PATH];
	
	kvSave.GetString("x_music", sMusic, sizeof(sMusic), "");
	
	if (sMusic[0] != '\0')
	{
		SetupMusicCel(iEntity, sMusic, kvSave.GetFloat("x_musiclength", 0.0), kvSave.GetNum("x_musicpitch", 100));
	}
	
	kvSave.GetString("x_sound", g_sSound[iEntity], sizeof(g_sSound[]), "");
	
	if (g_sSound[iEntity][0] != '\0')
	{
		PrecacheSound(g_sSound[iEntity]);
		
		g_fNextSoundUse[iEntity] = 0.0;
		
		SetEntProp(iEntity, Prop_Data, "m_spawnflags", GetEntProp(iEntity, Prop_Data, "m_spawnflags") | 256);
		
		SDKHook(iEntity, SDKHook_UsePost, Hook_SoundUse);
	}
	
	//Links are made once the whole build is in, the other entity may not exist yet. 0 = teleport, 1 = weld, 2 = button link.
	static const char sKeys[][] = { "x_teleport", "x_weld", "x_link" };
	
	for (int i = 0; i < sizeof(sKeys); i++)
	{
		if (kvSave.GetNum(sKeys[i], -1) != -1)
		{
			iLink[0] = i;
			iLink[1] = EntIndexToEntRef(iEntity);
			iLink[2] = kvSave.GetNum(sKeys[i]);
			
			g_alLoadLinks[iClient].PushArray(iLink);
		}
	}
}

public void Cel_OnBuildLoaded(int iClient, const char[] sSaveName)
{
	char sId[16];
	int iLink[3], iRef;
	
	for (int i = 0; i < g_alLoadLinks[iClient].Length; i++)
	{
		g_alLoadLinks[iClient].GetArray(i, iLink);
		
		IntToString(iLink[2], sId, sizeof(sId));
		
		int iEntity = EntRefToEntIndex(iLink[1]);
		
		if (iEntity == INVALID_ENT_REFERENCE || !g_smLoadIds[iClient].GetValue(sId, iRef))
		{
			continue;
		}
		
		int iOther = EntRefToEntIndex(iRef);
		
		if (iOther == INVALID_ENT_REFERENCE)
		{
			continue;
		}
		
		switch (iLink[0])
		{
			case 0:
			{
				g_iTeleportDest[iEntity] = iRef;
				
				SDKHook(iEntity, SDKHook_StartTouchPost, Hook_TeleportTouch);
			}
			case 1:
			{
				if (iOther == iEntity || ParentLoops(iEntity, iOther))
				{
					continue;
				}
				
				Cel_SetMotion(iEntity, false);
				
				SetVariantString("!activator");
				AcceptEntityInput(iEntity, "SetParent", iOther, iEntity);
			}
			case 2:
			{
				Cel_SetTriggerLink(iEntity, iOther);
			}
		}
	}
	
	g_alLoadLinks[iClient].Clear();
	g_smLoadIds[iClient].Clear();
}

//Build messages: !buildmessage <text> sets what players see in chat when they walk into your build (your land).
public Action Command_BuildMessage(int iClient, int iArgs)
{
	char sMessage[128];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		if (g_sBuildMessage[iClient][0] != '\0')
		{
			Cel_ReplyToCommand(iClient, "Your build message: {green}%s{default}. Change it with {green}[tag]buildmessage{default} <text>, or remove it with {green}[tag]buildmessage off{default}.", g_sBuildMessage[iClient]);
		} else {
			Cel_ReplyToCommand(iClient, "Usage: {green}[tag]buildmessage{default} <text>. Players see it when they walk into your build.");
		}
		
		return Plugin_Handled;
	}
	
	GetCmdArgString(sMessage, sizeof(sMessage));
	StripQuotes(sMessage);
	TrimString(sMessage);
	
	if (StrEqual(sMessage, "off", false) || StrEqual(sMessage, "none", false))
	{
		g_sBuildMessage[iClient][0] = '\0';
		Cel_SetClientSettingString(iClient, "buildmessage", "none");
		
		Cel_ReplyToCommand(iClient, "Your build message has been removed.");
		return Plugin_Handled;
	}
	
	strcopy(g_sBuildMessage[iClient], sizeof(g_sBuildMessage[]), sMessage);
	Cel_SetClientSettingString(iClient, "buildmessage", sMessage);
	
	Cel_ReplyToCommand(iClient, "Players walking into your build will now see: {green}From %N:{default} %s", iClient, sMessage);
	
	return Plugin_Handled;
}

//Shows a build's message to each player as they walk into it (once each time they come in).
public Action Timer_BuildMessages(Handle hTimer)
{
	float fOrigin[3];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i))
		{
			g_iLastLandIn[i] = 0;
			continue;
		}
		
		GetClientAbsOrigin(i, fOrigin);
		fOrigin[2] += 16.0;
		
		int iOwner = Cel_GetLandOwnerFromPosition(fOrigin);
		
		if (iOwner < 1 || iOwner > MaxClients)
		{
			iOwner = 0;
		}
		
		if (iOwner != g_iLastLandIn[i] && iOwner != 0 && iOwner != i && IsClientInGame(iOwner) && g_sBuildMessage[iOwner][0] != '\0')
		{
			Cel_PrintToChat(i, "{green}From %N:{default} %s", iOwner, g_sBuildMessage[iOwner]);
		}
		
		g_iLastLandIn[i] = iOwner;
	}
	
	return Plugin_Continue;
}

//Spawn health: every player starts with cm_spawn_health (225), which is also their full health for healing.
//No player-to-player collision. The "debris trigger" collision group lets players pass through each other, but the
//engine's rules make NPCs pass through it too (leaping enemies couldn't reach anyone, so dungeon monsters stopped
//hurting players). So a player is only in it while another player is close by, and back in the normal player group,
//where NPCs collide with them and hurt them as usual, once nobody is. The group is networked, so movement prediction
//on players' screens agrees with the server.
#define COLLISION_GROUP_PLAYER_DEFAULT 5
#define COLLISION_GROUP_PLAYER_NOBLOCK 2

void SetNoBlock(int iClient)
{
	int iGroup = (g_cvNoBlock.BoolValue && PlayerNearby(iClient)) ? COLLISION_GROUP_PLAYER_NOBLOCK : COLLISION_GROUP_PLAYER_DEFAULT;
	
	if (GetEntProp(iClient, Prop_Send, "m_CollisionGroup") != iGroup)
	{
		SetCollisionGroupSafe(iClient, iGroup);
	}
}

//The physics engine has to be told when an entity's collision group changes (CBaseEntity::SetCollisionGroup calls
//CollisionRulesChanged): changing the value behind its back leaves its collision data stale, which can crash the
//server inside the physics step. SourceMod's SetEntityCollisionGroup does it properly; the old way is only used if
//this SourceMod lacks it, or if it once failed on this game (the line after the call is then never reached).
bool g_bCollisionNativeTried = false;
bool g_bCollisionNativeWorks = false;

void SetCollisionGroupSafe(int iEntity, int iGroup)
{
	if (GetFeatureStatus(FeatureType_Native, "SetEntityCollisionGroup") == FeatureStatus_Available && (!g_bCollisionNativeTried || g_bCollisionNativeWorks))
	{
		g_bCollisionNativeTried = true;
		g_bCollisionNativeWorks = false;
		
		SetEntityCollisionGroup(iEntity, iGroup);
		
		g_bCollisionNativeWorks = true;
		return;
	}
	
	SetEntProp(iEntity, Prop_Send, "m_CollisionGroup", iGroup);
}

//Another living player close enough to touch soon (a little more than two player widths, and overlapping in height).
bool PlayerNearby(int iClient)
{
	float fMine[3], fOther[3];
	
	GetClientAbsOrigin(iClient, fMine);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == iClient || !IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}
		
		GetClientAbsOrigin(i, fOther);
		
		if (FloatAbs(fMine[0] - fOther[0]) < 80.0 && FloatAbs(fMine[1] - fOther[1]) < 80.0 && FloatAbs(fMine[2] - fOther[2]) < 100.0)
		{
			return true;
		}
	}
	
	return false;
}

public Action Timer_NoBlock(Handle hTimer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			SetNoBlock(i);
		}
	}
	
	return Plugin_Continue;
}

public void CMExtras_OnNoBlockChanged(ConVar cvConVar, const char[] sOldValue, const char[] sNewValue)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			SetNoBlock(i);
		}
	}
}

public void Event_SpawnHealth(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(eEvent.GetInt("userid"));
	
	if (iClient > 0)
	{
		g_bDoubleJumped[iClient] = false;
		
		//A frame later, after the game has set its own spawn health.
		RequestFrame(Frame_SpawnHealth, GetClientUserId(iClient));
	}
}

public void Frame_SpawnHealth(any iUserId)
{
	int iClient = GetClientOfUserId(iUserId);
	
	if (iClient < 1 || !IsClientInGame(iClient) || !IsPlayerAlive(iClient))
	{
		return;
	}
	
	SetNoBlock(iClient);
	
	int iHealth = g_cvSpawnHealth.IntValue;
	
	SetEntProp(iClient, Prop_Data, "m_iMaxHealth", iHealth);
	SetEntityHealth(iClient, iHealth);
}

//Double jump: pressing jump again in the air gives one more jump, until the player lands. Not inside event areas
//(mazes and parkour), unless the player is an admin with !zonebypass on.
public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAngles[3], int &iWeapon)
{
	int iLast = g_iLastButtons[iClient];
	
	g_iLastButtons[iClient] = iButtons;
	
	//!weps: in a land with weapons off, a visitor's weapons don't fire. The gravity gun still works, for building.
	if (g_iNoWepsOwner[iClient] > 0 && (iButtons & (IN_ATTACK | IN_ATTACK2)) && IsPlayerAlive(iClient))
	{
		char sWeapon[32];
		int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
		
		if (iActive > MaxClients && IsValidEntity(iActive) && GetEntityClassname(iActive, sWeapon, sizeof(sWeapon)) && !StrEqual(sWeapon, "weapon_physcannon"))
		{
			iButtons &= ~(IN_ATTACK | IN_ATTACK2);
			
			if (GetGameTime() >= g_fNextNoWepsNotice[iClient] && IsClientInGame(g_iNoWepsOwner[iClient]))
			{
				g_fNextNoWepsNotice[iClient] = GetGameTime() + 4.0;
				
				Cel_PrintToChat(iClient, "Weapons are turned off in {green}%N{default}'s land.", g_iNoWepsOwner[iClient]);
			}
		}
	}
	
	if (g_cvDoubleJump.FloatValue <= 0.0 || !IsPlayerAlive(iClient) || IsFakeClient(iClient))
	{
		return Plugin_Continue;
	}
	
	if (GetEntityFlags(iClient) & FL_ONGROUND)
	{
		g_bDoubleJumped[iClient] = false;
		return Plugin_Continue;
	}
	
	if (!(iButtons & IN_JUMP) || (iLast & IN_JUMP) || g_bDoubleJumped[iClient] || GetEntityMoveType(iClient) != MOVETYPE_WALK || GetEntProp(iClient, Prop_Data, "m_nWaterLevel") > 1)
	{
		return Plugin_Continue;
	}
	
	if (GetFeatureStatus(FeatureType_Native, "Cel_GetZoneType") == FeatureStatus_Available && !Cel_ZoneExempt(iClient))
	{
		float fFeet[3];
		
		GetClientAbsOrigin(iClient, fFeet);
		fFeet[2] += 16.0;
		
		if (Cel_GetZoneType(fFeet) == CEL_ZONE_EVENT)
		{
			return Plugin_Continue;
		}
	}
	
	g_bDoubleJumped[iClient] = true;
	
	float fVelocity[3];
	
	// The upward speed that rises cm_double_jump_height with the player's gravity (sv_gravity, scaled by a gravity
	// emblem), so it feels like a second normal jump and not a launch.
	ConVar cvGravity = FindConVar("sv_gravity");
	float fScale = GetEntityGravity(iClient);
	float fGravity = (cvGravity != null ? cvGravity.FloatValue : 600.0) * (fScale > 0.0 ? fScale : 1.0);

	GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", fVelocity);
	fVelocity[2] = SquareRoot(2.0 * fGravity * g_cvDoubleJumpHeight.FloatValue);
	
	TeleportEntity(iClient, NULL_VECTOR, NULL_VECTOR, fVelocity);
	
	return Plugin_Continue;
}

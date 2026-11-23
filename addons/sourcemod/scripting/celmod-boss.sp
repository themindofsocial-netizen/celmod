#pragma semicolon 1

#include <sdkhooks>
#include <sdktools>
#include <celmod>

#pragma newdecls required

/*
 * |CelMod| Boss
 *
 * The boss fight under gm_bloodyconstruct_cm12 (works on any map with the same entity names):
 *
 *   removeweps        trigger_push in the vent: takes away every weapon of a player that goes through it.
 *   startboss         trigger past the final door: drops the player into the arena at startboss_spawn.
 *   finaldoor_block   the door behind it: slams shut and locks a few seconds after the first player drops in.
 *   removeme          the cycler with models/celmod/wide_eyes.mdl at the far end: replaced by the boss.
 *   manhackpoint      where manhacks fly in from.
 *   ceilingpoints     where ceiling lasers fire from once the boss is hurt.
 *
 * The fight: in the arena only the gravity gun works. The boss fires telegraphed lasers at players (a thin beam
 * warns where the shot goes, then a burst fires down that line: step out of it). Manhacks fly in; catch one with
 * the gravity gun and launch it into the boss. Enough hits and it's beaten: everyone still standing gets CL and their
 * weapons back, the blood emblem and CL, and the door opens. It stays dead until the next map. If everyone in the
 * arena dies or leaves, the fight resets.
 */

#define BOSS_MODEL "models/celmod/wide_eyes.mdl"
#define BOSS_NAME "Wide Eyes"
#define LASER_SPRITE "sprites/laserbeam.vmt"

#define SND_CHARGE "npc/strider/charging.wav"
#define SND_FIRE "npc/strider/fire.wav"
#define SND_HIT "npc/manhack/grind5.wav"
#define SND_PAIN "npc/combine_gunship/gunship_pain.wav"
#define SND_DEATH "npc/combine_gunship/gunship_explode2.wav"
#define SND_LOCK "doors/heavy_metal_stop1.wav"
#define SND_ROAR "npc/combine_gunship/gunship_moan.wav"

#define MAX_SHOTS 8
#define MAX_POINTS 16

ConVar g_cvEnable, g_cvHits, g_cvHitsPerPlayer, g_cvReward, g_cvXP, g_cvEmblem, g_cvLaserDamage, g_cvManhacks, g_cvLockDelay;

bool g_bMapReady;
bool g_bFight;
bool g_bDoorLocked;
bool g_bBeaten; // once beaten, it stays dead until the next map
bool g_bInFight[MAXPLAYERS + 1];

int g_iBossRef = INVALID_ENT_REFERENCE;
int g_iHits;
int g_iMaxHits;
int g_iLaserSprite;
int g_iCeilingCount;

float g_fBossPos[3];
float g_fBossAngles[3];
float g_fSpawnPos[3];
float g_fManhackPos[3];
float g_fCeiling[MAX_POINTS][3];
float g_fFightStart;
float g_fNextAttack;
float g_fNextManhack;
float g_fNextHud;
float g_fNextNotice[MAXPLAYERS + 1];
float g_fNextStrip[MAXPLAYERS + 1];

bool g_bHasManhackPoint;

// Telegraphed shots: a warning line, then the burst at g_fShotTime.
bool g_bShot[MAX_SHOTS];
float g_fShotStart[MAX_SHOTS][3];
float g_fShotEnd[MAX_SHOTS][3];
float g_fShotTime[MAX_SHOTS];

// Manhacks of the fight, and until when one counts as thrown (it was in a gravity gun a moment ago).
ArrayList g_alManhacks;
float g_fThrownUntil[MAXENTITIES + 1];

Handle g_hThink;
bool g_bLate;
int g_iExplosionSprite;

public Plugin myinfo =
{
	name = "|CelMod| Boss",
	author = "CelMod",
	description = "The Wide Eyes boss fight under gm_bloodyconstruct_cm12.",
	version = "1.0.0",
	url = ""
};

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	g_bLate = bLate;

	MarkNativeAsOptional("Cel_AddToClientBalance");
	MarkNativeAsOptional("Cel_GiveCollectible");
	MarkNativeAsOptional("Cel_AddTacticsXP");
	MarkNativeAsOptional("Cel_PrintToChat");
	MarkNativeAsOptional("Cel_PrintToChatAll");

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("cm_boss_enable", "1", "Whether the boss fight on maps that have one (gm_bloodyconstruct_cm12) is on.");
	g_cvHits = CreateConVar("cm_boss_hits", "8", "Manhack hits it takes to beat the boss with one player.", _, true, 1.0);
	g_cvHitsPerPlayer = CreateConVar("cm_boss_hits_per_player", "2", "Extra hits it takes for each more player in the fight.", _, true, 0.0);
	g_cvReward = CreateConVar("cm_boss_reward", "10000", "CL each player still standing gets for beating the boss.", _, true, 0.0);
	g_cvLaserDamage = CreateConVar("cm_boss_laser_damage", "30", "Damage of one of the boss's lasers.", _, true, 0.0);
	g_cvManhacks = CreateConVar("cm_boss_manhacks", "3", "Manhacks in the arena at once (one more for each extra player).", _, true, 1.0, true, 12.0);
	g_cvXP = CreateConVar("cm_tactics_xp_boss", "200", "Tactics experience everyone still in the arena gets for beating the boss.", _, true, 0.0);
	g_cvEmblem = CreateConVar("cm_boss_emblem", "blood", "Emblem everyone still in the arena gets for beating the boss (empty = none).");
	g_cvLockDelay = CreateConVar("cm_boss_lock_delay", "4", "Seconds after the first player drops in before the door locks behind them (so friends can follow).", _, true, 0.0);

	HookEntityOutput("trigger_multiple", "OnStartTouch", Output_StartTouch);
	HookEntityOutput("trigger_push", "OnStartTouch", Output_StartTouch);

	HookEvent("player_death", Event_PlayerDeath);

	g_alManhacks = new ArrayList();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}

	// Loaded while a map is running: set it up now.
	if (g_bLate)
	{
		OnMapStart();
	}
}

public void OnMapStart()
{
	PrecacheModel(BOSS_MODEL, true);
	PrecacheModel("models/manhack.mdl", true);
	g_iLaserSprite = PrecacheModel(LASER_SPRITE, true);
	g_iExplosionSprite = PrecacheModel("sprites/zerogxplode.spr", true);

	PrecacheSound(SND_CHARGE, true);
	PrecacheSound(SND_FIRE, true);
	PrecacheSound(SND_HIT, true);
	PrecacheSound(SND_PAIN, true);
	PrecacheSound(SND_DEATH, true);
	PrecacheSound(SND_LOCK, true);
	PrecacheSound(SND_ROAR, true);

	g_bMapReady = false;
	g_bFight = false;
	g_bDoorLocked = false;
	g_iBossRef = INVALID_ENT_REFERENCE;
	g_bBeaten = false;
	g_alManhacks.Clear();

	for (int i = 1; i <= MaxClients; i++)
	{
		g_bInFight[i] = false;
	}

	CreateTimer(1.0, Timer_SetupArena, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
	g_hThink = null;
	g_bMapReady = false;
}

public void OnClientPutInServer(int iClient)
{
	SDKHook(iClient, SDKHook_WeaponCanUse, Hook_WeaponCanUse);

	g_bInFight[iClient] = false;
	g_fNextNotice[iClient] = 0.0;
	g_fNextStrip[iClient] = 0.0;
}

public void OnClientDisconnect(int iClient)
{
	if (g_bInFight[iClient])
	{
		g_bInFight[iClient] = false;

		CheckFightOver();
	}
}

public void OnEntityDestroyed(int iEntity)
{
	if (iEntity > 0 && iEntity <= MAXENTITIES)
	{
		g_fThrownUntil[iEntity] = 0.0;
	}
}

// ---- Setting the arena up --------------------------------------------------------------------------------------

public Action Timer_SetupArena(Handle hTimer)
{
	if (g_bMapReady)
	{
		return Plugin_Stop;
	}

	// No boss on this map.
	if (FindByName("trigger_multiple", "startboss") == -1 || !FindPoint("info_teleport_destination", "startboss_spawn", g_fSpawnPos))
	{
		return Plugin_Stop;
	}

	g_bHasManhackPoint = FindPoint("info_target", "manhackpoint", g_fManhackPos);

	// The ceiling points (fired from once the boss is hurt).
	g_iCeilingCount = 0;

	int iEnt = -1;
	char sName[64];

	while ((iEnt = FindEntityByClassname(iEnt, "info_target")) != -1 && g_iCeilingCount < MAX_POINTS)
	{
		GetEntPropString(iEnt, Prop_Data, "m_iName", sName, sizeof(sName));

		if (StrEqual(sName, "ceilingpoints"))
		{
			GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", g_fCeiling[g_iCeilingCount++]);
		}
	}

	// The map's stand-in for the boss: its spot is where the boss lives.
	bool bFound;

	while ((iEnt = FindEntityByClassname(iEnt, "cycler")) != -1)
	{
		GetEntPropString(iEnt, Prop_Data, "m_iName", sName, sizeof(sName));

		if (StrEqual(sName, "removeme"))
		{
			GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", g_fBossPos);
			GetEntPropVector(iEnt, Prop_Data, "m_angAbsRotation", g_fBossAngles);

			AcceptEntityInput(iEnt, "Kill");

			bFound = true;
		}
	}

	if (!bFound)
	{
		LogError("|CelMod| The boss arena has no 'removeme' cycler to put the boss in place of, so there's no boss fight.");

		return Plugin_Stop;
	}

	SpawnBoss();

	g_bMapReady = true;
	g_hThink = CreateTimer(0.1, Timer_Think, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Stop;
}

void SpawnBoss()
{
	int iBoss = EntRefToEntIndex(g_iBossRef);

	if (iBoss == INVALID_ENT_REFERENCE)
	{
		iBoss = CreateEntityByName("prop_dynamic_override");

		if (iBoss == -1)
		{
			return;
		}

		DispatchKeyValue(iBoss, "model", BOSS_MODEL);
		DispatchKeyValue(iBoss, "solid", "0");
		DispatchKeyValue(iBoss, "targetname", "cm_boss");
		DispatchKeyValue(iBoss, "disableshadows", "1");

		TeleportEntity(iBoss, g_fBossPos, g_fBossAngles, NULL_VECTOR);
		DispatchSpawn(iBoss);

		g_iBossRef = EntIndexToEntRef(iBoss);
	}

	SetEntityRenderMode(iBoss, RENDER_NORMAL);
	SetEntityRenderColor(iBoss, 255, 255, 255, 255);
	AcceptEntityInput(iBoss, "EnableDraw");
}

// ---- Triggers -----------------------------------------------------------------------------------------------------

public void Output_StartTouch(const char[] sOutput, int iCaller, int iActivator, float fDelay)
{
	if (!g_cvEnable.BoolValue || iActivator < 1 || iActivator > MaxClients || !IsClientInGame(iActivator) || !IsPlayerAlive(iActivator) || !IsValidEntity(iCaller))
	{
		return;
	}

	char sName[64];

	GetEntPropString(iCaller, Prop_Data, "m_iName", sName, sizeof(sName));

	if (StrEqual(sName, "removeweps"))
	{
		StripWeapons(iActivator);

		if (GetGameTime() >= g_fNextStrip[iActivator])
		{
			g_fNextStrip[iActivator] = GetGameTime() + 10.0;

			Chat(iActivator, "Something in the vent pulled your weapons away.");
		}
	} else if (StrEqual(sName, "startboss") && g_bMapReady) {
		EnterArena(iActivator);
	}
}

void EnterArena(int iClient)
{
	if (g_bInFight[iClient])
	{
		return;
	}

	float fNow = GetGameTime();

	if (g_bBeaten)
	{
		if (fNow >= g_fNextNotice[iClient])
		{
			g_fNextNotice[iClient] = fNow + 5.0;

			Chat(iClient, "{green}%s{default} has already been beaten on this map.", BOSS_NAME);
		}

		return;
	}

	// The door is shut: the fight is already on without them.
	if (g_bDoorLocked)
	{
		return;
	}

	// Into the arena, looking at the boss.
	float fAngles[3], fDir[3];

	SubtractVectors(g_fBossPos, g_fSpawnPos, fDir);
	GetVectorAngles(fDir, fAngles);
	fAngles[0] = 0.0;
	fAngles[2] = 0.0;

	float fZero[3];

	TeleportEntity(iClient, g_fSpawnPos, fAngles, fZero);

	// Gravity gun only.
	StripWeapons(iClient);
	GivePlayerItem(iClient, "weapon_physcannon");
	FakeClientCommand(iClient, "use weapon_physcannon");

	g_bInFight[iClient] = true;

	if (!g_bFight)
	{
		StartFight();
	}

	g_iMaxHits = g_cvHits.IntValue + g_cvHitsPerPlayer.IntValue * (CountFighters() - 1);

	Chat(iClient, "Only the {green}gravity gun{default} works down here. Dodge {green}%s{default}'s lasers, catch the manhacks and throw them into it!", BOSS_NAME);
}

void StartFight()
{
	g_bFight = true;
	g_bDoorLocked = false;
	g_iHits = 0;

	float fNow = GetGameTime();

	g_fFightStart = fNow;
	g_fNextManhack = fNow + 3.0;
	g_fNextAttack = fNow + g_cvLockDelay.FloatValue + 2.0;

	for (int i = 0; i < MAX_SHOTS; i++)
	{
		g_bShot[i] = false;
	}

	SpawnBoss();

	int iBoss = EntRefToEntIndex(g_iBossRef);

	if (iBoss != INVALID_ENT_REFERENCE)
	{
		EmitSoundToAll(SND_ROAR, iBoss, SNDCHAN_VOICE, SNDLEVEL_SCREAMING);
	}

	CreateTimer(g_cvLockDelay.FloatValue, Timer_LockDoor, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_LockDoor(Handle hTimer)
{
	if (!g_bFight)
	{
		return Plugin_Stop;
	}

	int iDoor = FindByName("func_door", "finaldoor_block");

	if (iDoor != -1)
	{
		AcceptEntityInput(iDoor, "Close");
		AcceptEntityInput(iDoor, "Lock");
	}

	g_bDoorLocked = true;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bInFight[i] && IsClientInGame(i))
		{
			EmitSoundToClient(i, SND_LOCK);
			Chat(i, "The door slams shut and locks behind you.");
		}
	}

	return Plugin_Stop;
}

void OpenDoor()
{
	int iDoor = FindByName("func_door", "finaldoor_block");

	if (iDoor != -1)
	{
		AcceptEntityInput(iDoor, "Unlock");
		AcceptEntityInput(iDoor, "Open");
	}

	g_bDoorLocked = false;
}

// ---- The fight ----------------------------------------------------------------------------------------------------

public Action Timer_Think(Handle hTimer)
{
	if (!g_bFight)
	{
		return Plugin_Continue;
	}

	int iBoss = EntRefToEntIndex(g_iBossRef);

	if (iBoss == INVALID_ENT_REFERENCE)
	{
		return Plugin_Continue;
	}

	float fNow = GetGameTime(), fEye[3];

	// Fighters who got out of the arena some other way (a teleport, noclip) are out of the fight.
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bInFight[i] && (!IsClientInGame(i) || !IsPlayerAlive(i) || DistanceToArena(i) > 3000.0))
		{
			g_bInFight[i] = false;

			if (IsClientInGame(i) && IsPlayerAlive(i))
			{
				GiveLoadout(i);
			}
		}
	}

	if (CheckFightOver())
	{
		return Plugin_Continue;
	}

	BossCenter(iBoss, fEye);

	FaceTarget(iBoss, fEye, fNow);
	CheckManhackHits(iBoss, fEye, fNow);
	RunShots(iBoss, fNow);

	bool bHurt = g_iHits * 2 >= g_iMaxHits;

	// A new laser every few seconds, faster once it's hurt; then the ceiling joins in.
	if (fNow >= g_fNextAttack)
	{
		int iTarget = RandomFighter();

		if (iTarget != -1)
		{
			AimShot(fEye, iTarget, bHurt ? 0.9 : 1.2);

			if (bHurt && g_iCeilingCount > 0)
			{
				int iSecond = RandomFighter();

				if (iSecond != -1)
				{
					AimShot(g_fCeiling[GetRandomInt(0, g_iCeilingCount - 1)], iSecond, 1.1);
				}
			}

			EmitSoundToAll(SND_CHARGE, iBoss, SNDCHAN_WEAPON, SNDLEVEL_SCREAMING);
		}

		g_fNextAttack = fNow + (bHurt ? 2.0 : 3.0);
	}

	if (fNow >= g_fNextManhack)
	{
		g_fNextManhack = fNow + 4.0;

		SpawnManhacks();
	}

	if (fNow >= g_fNextHud)
	{
		g_fNextHud = fNow + 0.5;

		ShowBossHud();
	}

	return Plugin_Continue;
}

void FaceTarget(int iBoss, const float fEye[3], float fNow)
{
	int iTarget = NearestFighter(fEye);

	if (iTarget == -1)
	{
		return;
	}

	float fTarget[3], fDir[3], fAngles[3], fPos[3];

	GetClientEyePosition(iTarget, fTarget);
	SubtractVectors(fTarget, fEye, fDir);
	GetVectorAngles(fDir, fAngles);

	fAngles[0] = 0.0;
	fAngles[2] = 0.0;

	// A slow hover.
	fPos = g_fBossPos;
	fPos[2] += Sine((fNow - g_fFightStart) * 1.5) * 12.0;

	TeleportEntity(iBoss, fPos, fAngles, NULL_VECTOR);
}

void AimShot(const float fFrom[3], int iTarget, float fWarning)
{
	int iShot = -1;

	for (int i = 0; i < MAX_SHOTS; i++)
	{
		if (!g_bShot[i])
		{
			iShot = i;
			break;
		}
	}

	if (iShot == -1)
	{
		return;
	}

	float fAt[3], fDir[3], fEnd[3];

	// Locked on where they are now: moving out of the line is how it's dodged.
	GetClientAbsOrigin(iTarget, fAt);
	fAt[2] += 40.0;

	SubtractVectors(fAt, fFrom, fDir);
	NormalizeVector(fDir, fDir);
	ScaleVector(fDir, 6000.0);
	AddVectors(fFrom, fDir, fEnd);

	// Stops at the first wall.
	TR_TraceRayFilter(fFrom, fEnd, MASK_SOLID_BRUSHONLY, RayType_EndPoint, Filter_WorldOnly);

	if (TR_DidHit())
	{
		TR_GetEndPosition(fEnd);
	}

	g_fShotStart[iShot] = fFrom;
	g_fShotEnd[iShot] = fEnd;
	g_fShotTime[iShot] = GetGameTime() + fWarning;
	g_bShot[iShot] = true;
}

void RunShots(int iBoss, float fNow)
{
	for (int i = 0; i < MAX_SHOTS; i++)
	{
		if (!g_bShot[i])
		{
			continue;
		}

		if (fNow < g_fShotTime[i])
		{
			// The warning: a thin flickering line along where it'll fire.
			TE_SetupBeamPoints(g_fShotStart[i], g_fShotEnd[i], g_iLaserSprite, 0, 0, 0, 0.12, 1.5, 1.5, 0, 1.0, { 255, 60, 0, 160 }, 0);
			TE_SendToAll();

			continue;
		}

		g_bShot[i] = false;

		TE_SetupBeamPoints(g_fShotStart[i], g_fShotEnd[i], g_iLaserSprite, 0, 0, 0, 0.35, 14.0, 10.0, 0, 2.0, { 255, 20, 20, 255 }, 0);
		TE_SendToAll();

		TE_SetupSparks(g_fShotEnd[i], NULL_VECTOR, 8, 4);
		TE_SendToAll();

		EmitSoundToAll(SND_FIRE, iBoss, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);

		for (int c = 1; c <= MaxClients; c++)
		{
			if (!g_bInFight[c] || !IsClientInGame(c) || !IsPlayerAlive(c))
			{
				continue;
			}

			float fFeet[3], fHead[3];

			GetClientAbsOrigin(c, fFeet);
			GetClientEyePosition(c, fHead);
			fFeet[2] += 12.0;

			if (DistanceToSegment(fFeet, g_fShotStart[i], g_fShotEnd[i]) < 24.0 || DistanceToSegment(fHead, g_fShotStart[i], g_fShotEnd[i]) < 24.0)
			{
				SDKHooks_TakeDamage(c, iBoss, iBoss, g_cvLaserDamage.FloatValue, DMG_ENERGYBEAM);
			}
		}
	}
}

void SpawnManhacks()
{
	// Gone ones out of the list.
	for (int i = g_alManhacks.Length - 1; i >= 0; i--)
	{
		if (EntRefToEntIndex(g_alManhacks.Get(i)) == INVALID_ENT_REFERENCE)
		{
			g_alManhacks.Erase(i);
		}
	}

	int iWant = g_cvManhacks.IntValue + CountFighters() - 1;

	if (g_alManhacks.Length >= iWant || !g_bHasManhackPoint)
	{
		return;
	}

	int iHack = CreateEntityByName("npc_manhack");

	if (iHack == -1 || iHack > MAXENTITIES)
	{
		if (iHack != -1)
		{
			AcceptEntityInput(iHack, "Kill");
		}

		return;
	}

	float fPos[3], fAngles[3];

	fPos = g_fManhackPos;
	fPos[0] += GetRandomFloat(-40.0, 40.0);
	fPos[1] += GetRandomFloat(-40.0, 40.0);
	fPos[2] += 40.0;

	fAngles[1] = GetRandomFloat(0.0, 360.0);

	DispatchKeyValue(iHack, "targetname", "cm_boss_manhack");
	DispatchKeyValue(iHack, "spawnflags", "512");

	TeleportEntity(iHack, fPos, fAngles, NULL_VECTOR);
	DispatchSpawn(iHack);
	ActivateEntity(iHack);

	// HL2DM doesn't give NPCs Half-Life 2's relationships: told to go after players, like the spawn pads' ones.
	SetVariantString("player D_HT 99");
	AcceptEntityInput(iHack, "SetRelationship");
	AcceptEntityInput(iHack, "Wake");

	g_alManhacks.Push(EntIndexToEntRef(iHack));
}

// A manhack that was in someone's gravity gun a moment ago and reaches the boss is a hit.
void CheckManhackHits(int iBoss, const float fEye[3], float fNow)
{
	// What each fighter's gravity gun is holding right now.
	for (int c = 1; c <= MaxClients; c++)
	{
		if (!g_bInFight[c] || !IsClientInGame(c) || !IsPlayerAlive(c))
		{
			continue;
		}

		int iGun = GetEntPropEnt(c, Prop_Send, "m_hActiveWeapon");

		if (iGun <= MaxClients || !IsValidEntity(iGun) || !HasEntProp(iGun, Prop_Send, "m_hAttachedObject"))
		{
			continue;
		}

		int iHeld = GetEntPropEnt(iGun, Prop_Send, "m_hAttachedObject");

		if (iHeld > MaxClients && iHeld <= MAXENTITIES && g_alManhacks.FindValue(EntIndexToEntRef(iHeld)) != -1)
		{
			g_fThrownUntil[iHeld] = fNow + 3.0;
		}
	}

	float fRadius = BossRadius(iBoss);

	for (int i = g_alManhacks.Length - 1; i >= 0; i--)
	{
		int iHack = EntRefToEntIndex(g_alManhacks.Get(i));

		if (iHack == INVALID_ENT_REFERENCE)
		{
			g_alManhacks.Erase(i);
			continue;
		}

		float fPos[3], fVel[3];

		GetEntPropVector(iHack, Prop_Data, "m_vecAbsOrigin", fPos);
		GetEntPropVector(iHack, Prop_Data, "m_vecAbsVelocity", fVel);

		if (GetVectorDistance(fPos, fEye) > fRadius)
		{
			continue;
		}

		// Thrown: it left a gravity gun a moment ago, or it's flying far faster than a manhack flies by itself.
		if (fNow > g_fThrownUntil[iHack] && GetVectorLength(fVel) < 700.0)
		{
			continue;
		}

		g_alManhacks.Erase(i);

		TE_SetupExplosion(fPos, g_iExplosionSprite, 1.0, 1, 0, 80, 0);
		TE_SendToAll();

		EmitSoundToAll(SND_HIT, iBoss, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);

		SDKHooks_TakeDamage(iHack, iBoss, iBoss, 500.0, DMG_BLAST);
		AcceptEntityInput(iHack, "Kill");

		BossHit(iBoss);

		if (!g_bFight)
		{
			return;
		}
	}
}

void BossHit(int iBoss)
{
	g_iHits++;

	EmitSoundToAll(SND_PAIN, iBoss, SNDCHAN_VOICE, SNDLEVEL_SCREAMING);

	// A red flash.
	SetEntityRenderColor(iBoss, 255, 80, 80, 255);
	CreateTimer(0.3, Timer_UnFlash, _, TIMER_FLAG_NO_MAPCHANGE);

	if (g_iHits * 2 >= g_iMaxHits && (g_iHits - 1) * 2 < g_iMaxHits)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_bInFight[i] && IsClientInGame(i))
			{
				Chat(i, "{green}%s{default} is furious: the ceiling is firing too!", BOSS_NAME);
			}
		}
	}

	ShowBossHud();

	if (g_iHits >= g_iMaxHits)
	{
		BossDefeated(iBoss);
	}
}

public Action Timer_UnFlash(Handle hTimer)
{
	int iBoss = EntRefToEntIndex(g_iBossRef);

	if (iBoss != INVALID_ENT_REFERENCE)
	{
		SetEntityRenderColor(iBoss, 255, 255, 255, 255);
	}

	return Plugin_Stop;
}

void BossDefeated(int iBoss)
{
	float fEye[3];

	BossCenter(iBoss, fEye);

	for (int i = 0; i < 4; i++)
	{
		float fPos[3];

		fPos = fEye;
		fPos[0] += GetRandomFloat(-60.0, 60.0);
		fPos[1] += GetRandomFloat(-60.0, 60.0);
		fPos[2] += GetRandomFloat(-40.0, 40.0);

		TE_SetupExplosion(fPos, g_iExplosionSprite, 4.0, 1, 0, 200, 0);
		TE_SendToAll(i * 0.25);
	}

	EmitSoundToAll(SND_DEATH, iBoss, SNDCHAN_VOICE, SNDLEVEL_SCREAMING);

	AcceptEntityInput(iBoss, "DisableDraw");

	char sNames[192], sEmblem[32], sReward[96];
	int iReward = g_cvReward.IntValue;

	g_cvEmblem.GetString(sEmblem, sizeof(sEmblem));
	TrimString(sEmblem);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bInFight[i] || !IsClientInGame(i))
		{
			continue;
		}

		g_bInFight[i] = false;

		if (IsPlayerAlive(i))
		{
			GiveLoadout(i);

			sReward[0] = '\0';

			if (sEmblem[0] != '\0' && GetFeatureStatus(FeatureType_Native, "Cel_GiveCollectible") == FeatureStatus_Available && Cel_GiveCollectible(i, "emblem", sEmblem))
			{
				Format(sReward, sizeof(sReward), "the {green}%s{default} emblem, ", sEmblem);
			}

			if (iReward > 0 && GetFeatureStatus(FeatureType_Native, "Cel_AddToClientBalance") == FeatureStatus_Available)
			{
				Cel_AddToClientBalance(i, iReward);
				Format(sReward, sizeof(sReward), "%s{green}%d CL{default}, ", sReward, iReward);
			}

			if (g_cvXP.IntValue > 0 && GetFeatureStatus(FeatureType_Native, "Cel_AddTacticsXP") == FeatureStatus_Available)
			{
				Cel_AddXP(i, g_cvXP.IntValue);
				Format(sReward, sizeof(sReward), "%s{green}%d XP{default}, ", sReward, g_cvXP.IntValue);
			}

			Chat(i, "You beat {green}%s{default}! You get %syour weapons back.", BOSS_NAME, sReward);
		}

		Format(sNames, sizeof(sNames), "%s%s%N", sNames, sNames[0] == '\0' ? "" : ", ", i);
	}

	ChatAll("{green}%s{default} beat {green}%s{default} in the depths of the construction site!", sNames, BOSS_NAME);
	LogAction(-1, -1, "%s beat the boss (%d hits).", sNames, g_iMaxHits);

	// Dead for the rest of the map.
	g_bBeaten = true;

	EndFight();
}

// Ends the fight once nobody is left in it. True if it ended.
bool CheckFightOver()
{
	if (!g_bFight || CountFighters() > 0)
	{
		return false;
	}

	ChatAll("{green}%s{default} wins this time. The way down is open again.", BOSS_NAME);

	EndFight();

	return true;
}

void EndFight()
{
	g_bFight = false;

	for (int i = 0; i < MAX_SHOTS; i++)
	{
		g_bShot[i] = false;
	}

	for (int i = 0; i < g_alManhacks.Length; i++)
	{
		int iHack = EntRefToEntIndex(g_alManhacks.Get(i));

		if (iHack != INVALID_ENT_REFERENCE)
		{
			AcceptEntityInput(iHack, "Kill");
		}
	}

	g_alManhacks.Clear();

	OpenDoor();

	int iBoss = EntRefToEntIndex(g_iBossRef);

	if (iBoss != INVALID_ENT_REFERENCE)
	{
		TeleportEntity(iBoss, g_fBossPos, g_fBossAngles, NULL_VECTOR);
	}
}

public void Event_PlayerDeath(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(eEvent.GetInt("userid"));

	if (iClient > 0 && g_bInFight[iClient])
	{
		g_bInFight[iClient] = false;

		Chat(iClient, "{green}%s{default} got you.", BOSS_NAME);

		CheckFightOver();
	}
}

// Only the gravity gun in the arena.
public Action Hook_WeaponCanUse(int iClient, int iWeapon)
{
	if (!g_bInFight[iClient] || !IsValidEntity(iWeapon))
	{
		return Plugin_Continue;
	}

	char sClass[32];

	GetEntityClassname(iWeapon, sClass, sizeof(sClass));

	return StrEqual(sClass, "weapon_physcannon") ? Plugin_Continue : Plugin_Handled;
}

// ---- Helpers ------------------------------------------------------------------------------------------------------

void ShowBossHud()
{
	char sBar[64];
	int iLeft = g_iMaxHits - g_iHits, iCells = 20;
	int iFull = (g_iMaxHits > 0) ? RoundToCeil(float(iLeft) / float(g_iMaxHits) * float(iCells)) : 0;

	for (int i = 0; i < iCells; i++)
	{
		StrCat(sBar, sizeof(sBar), i < iFull ? "|" : ".");
	}

	SetHudTextParams(-1.0, 0.06, 0.7, 255, 60, 40, 255, 0, 0.0, 0.0, 0.0);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bInFight[i] && IsClientInGame(i))
		{
			ShowHudText(i, 3, "%s\n[%s] %d/%d", BOSS_NAME, sBar, iLeft, g_iMaxHits);
		}
	}
}

void StripWeapons(int iClient)
{
	int iSize = GetEntPropArraySize(iClient, Prop_Send, "m_hMyWeapons");

	for (int i = 0; i < iSize; i++)
	{
		int iWeapon = GetEntPropEnt(iClient, Prop_Send, "m_hMyWeapons", i);

		if (iWeapon > MaxClients && IsValidEntity(iWeapon))
		{
			RemovePlayerItem(iClient, iWeapon);
			AcceptEntityInput(iWeapon, "Kill");
		}
	}
}

// The weapons players spawn with (celmod-extras' cm_spawn_loadout), or the gravity gun and crowbar.
void GiveLoadout(int iClient)
{
	char sLoadout[256], sWeapons[12][32];

	ConVar cvLoadout = FindConVar("cm_spawn_loadout");

	if (cvLoadout != null)
	{
		cvLoadout.GetString(sLoadout, sizeof(sLoadout));
	}

	if (sLoadout[0] == '\0')
	{
		strcopy(sLoadout, sizeof(sLoadout), "weapon_physcannon weapon_crowbar");
	}

	int iCount = ExplodeString(sLoadout, " ", sWeapons, sizeof(sWeapons), sizeof(sWeapons[]));

	for (int i = 0; i < iCount; i++)
	{
		TrimString(sWeapons[i]);

		if (StrContains(sWeapons[i], "weapon_") == 0 && GetPlayerWeaponByClass(iClient, sWeapons[i]) == -1)
		{
			GivePlayerItem(iClient, sWeapons[i]);
		}
	}
}

int GetPlayerWeaponByClass(int iClient, const char[] sClass)
{
	char sWeapon[32];
	int iSize = GetEntPropArraySize(iClient, Prop_Send, "m_hMyWeapons");

	for (int i = 0; i < iSize; i++)
	{
		int iWeapon = GetEntPropEnt(iClient, Prop_Send, "m_hMyWeapons", i);

		if (iWeapon > MaxClients && IsValidEntity(iWeapon) && GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon)) && StrEqual(sWeapon, sClass))
		{
			return iWeapon;
		}
	}

	return -1;
}

int CountFighters()
{
	int iCount;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bInFight[i] && IsClientInGame(i) && IsPlayerAlive(i))
		{
			iCount++;
		}
	}

	return iCount;
}

int RandomFighter()
{
	int iFighters[MAXPLAYERS + 1], iCount;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bInFight[i] && IsClientInGame(i) && IsPlayerAlive(i))
		{
			iFighters[iCount++] = i;
		}
	}

	return iCount > 0 ? iFighters[GetRandomInt(0, iCount - 1)] : -1;
}

int NearestFighter(const float fFrom[3])
{
	int iBest = -1;
	float fBest = 999999.0, fPos[3];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bInFight[i] && IsClientInGame(i) && IsPlayerAlive(i))
		{
			GetClientAbsOrigin(i, fPos);

			float fDistance = GetVectorDistance(fPos, fFrom);

			if (fDistance < fBest)
			{
				fBest = fDistance;
				iBest = i;
			}
		}
	}

	return iBest;
}

float DistanceToArena(int iClient)
{
	float fPos[3], fMiddle[3];

	GetClientAbsOrigin(iClient, fPos);

	for (int i = 0; i < 3; i++)
	{
		fMiddle[i] = (g_fBossPos[i] + g_fSpawnPos[i]) * 0.5;
	}

	return GetVectorDistance(fPos, fMiddle);
}

// The middle of the boss's model (where its lasers come from and where manhacks must reach).
void BossCenter(int iBoss, float fCenter[3])
{
	float fMins[3], fMaxs[3];

	GetEntPropVector(iBoss, Prop_Data, "m_vecAbsOrigin", fCenter);
	GetEntPropVector(iBoss, Prop_Send, "m_vecMins", fMins);
	GetEntPropVector(iBoss, Prop_Send, "m_vecMaxs", fMaxs);

	if (fMaxs[2] - fMins[2] < 1.0)
	{
		fCenter[2] += 48.0;
		return;
	}

	for (int i = 0; i < 3; i++)
	{
		fCenter[i] += (fMins[i] + fMaxs[i]) * 0.5;
	}
}

float BossRadius(int iBoss)
{
	float fMins[3], fMaxs[3];

	GetEntPropVector(iBoss, Prop_Send, "m_vecMins", fMins);
	GetEntPropVector(iBoss, Prop_Send, "m_vecMaxs", fMaxs);

	float fSize = GetVectorDistance(fMins, fMaxs) * 0.5;

	return fSize < 90.0 ? 90.0 : fSize + 30.0;
}

float DistanceToSegment(const float fPoint[3], const float fA[3], const float fB[3])
{
	float fAB[3], fAP[3], fClosest[3];

	SubtractVectors(fB, fA, fAB);
	SubtractVectors(fPoint, fA, fAP);

	float fLength = GetVectorDotProduct(fAB, fAB);
	float fT = (fLength > 0.0) ? GetVectorDotProduct(fAP, fAB) / fLength : 0.0;

	if (fT < 0.0)
	{
		fT = 0.0;
	} else if (fT > 1.0) {
		fT = 1.0;
	}

	for (int i = 0; i < 3; i++)
	{
		fClosest[i] = fA[i] + fAB[i] * fT;
	}

	return GetVectorDistance(fPoint, fClosest);
}

public bool Filter_WorldOnly(int iEntity, int iContentsMask)
{
	return iEntity == 0;
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

bool FindPoint(const char[] sClassname, const char[] sTarget, float fPos[3])
{
	int iEnt = FindByName(sClassname, sTarget);

	if (iEnt == -1)
	{
		return false;
	}

	GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", fPos);

	return true;
}

void Chat(int iClient, const char[] sFormat, any ...)
{
	char sMessage[256];

	VFormat(sMessage, sizeof(sMessage), sFormat, 3);

	if (GetFeatureStatus(FeatureType_Native, "Cel_PrintToChat") == FeatureStatus_Available)
	{
		Cel_PrintToChat(iClient, "%s", sMessage);
		return;
	}

	ReplaceString(sMessage, sizeof(sMessage), "{green}", "");
	ReplaceString(sMessage, sizeof(sMessage), "{default}", "");
	PrintToChat(iClient, "%s", sMessage);
}

void ChatAll(const char[] sFormat, any ...)
{
	char sMessage[256];

	VFormat(sMessage, sizeof(sMessage), sFormat, 2);

	if (GetFeatureStatus(FeatureType_Native, "Cel_PrintToChatAll") == FeatureStatus_Available)
	{
		Cel_PrintToChatAll("%s", sMessage);
		return;
	}

	ReplaceString(sMessage, sizeof(sMessage), "{green}", "");
	ReplaceString(sMessage, sizeof(sMessage), "{default}", "");
	PrintToChatAll("%s", sMessage);
}

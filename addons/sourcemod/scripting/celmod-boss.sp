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
// One-shot sounds only: the stalker's laser sounds loop forever once started.
#define SND_FIRE "npc/strider/fire.wav"
#define SND_HIT "physics/flesh/flesh_bloody_impact_hard1.wav"
#define SND_BURN "player/pl_burnpain1.wav"
#define SND_SPLAT "physics/flesh/flesh_squishy_impact_hard1.wav"
#define SND_GORE "physics/flesh/flesh_bloody_break.wav"
#define SND_LEECH "npc/barnacle/barnacle_tongue_pull1.wav"
#define SND_PAIN "npc/combine_gunship/gunship_pain.wav"
#define SND_DEATH "npc/combine_gunship/gunship_explode2.wav"
#define SND_LOCK "doors/heavy_metal_stop1.wav"
#define SND_ROAR "npc/combine_gunship/gunship_moan.wav"
#define SND_SLAM "ambient/explosions/explode_4.wav"
#define SND_ROCK "physics/flesh/flesh_squishy_impact_hard1.wav"
#define SND_SHIELD "ambient/energy/zap1.wav"

#define MAX_SHOTS 24
#define MAX_POINTS 16

ConVar g_cvEnable, g_cvHits, g_cvHitsPerPlayer, g_cvReward, g_cvXP, g_cvEmblem, g_cvLaserDamage, g_cvManhacks, g_cvLockDelay, g_cvSlamDamage, g_cvRockDamage;

bool g_bMapReady;
bool g_bFight;
bool g_bDoorLocked;
bool g_bDoorClosing; // startboss was touched: finaldoor_block closes for good a few seconds later
int g_iStage; // 1, 2 or 3, like a Dark Souls boss's phases
float g_fShieldUntil; // between stages it can't be hurt

// The floor shockwave (stage 2+): an expanding ring you jump over.
bool g_bWave;
float g_fWaveStart;
float g_fWaveCenter[3];
bool g_bWaveHit[MAXPLAYERS + 1];

// Falling rocks (stage 3): a ring marks where each lands.
#define MAX_ROCKS 8
bool g_bRock[MAX_ROCKS];
float g_fRockPos[MAX_ROCKS][3];
float g_fRockTime[MAX_ROCKS];

// Laser bursts (stage 2+): more shots at the same player, each aimed where they are now.
int g_iBurstLeft;
int g_iBurstTarget;
float g_fNextBurst;

int g_iAttack; // which attack is next, so they take turns
bool g_bBeaten; // once beaten, it stays dead until the next map
bool g_bInFight[MAXPLAYERS + 1];

int g_iBossRef = INVALID_ENT_REFERENCE;
int g_iHits;
int g_iMaxHits;
int g_iLaserSprite;
int g_iCeilingCount;

float g_fBossPos[3]; // where it waits (the map's stand-in)
float g_fBossCur[3]; // where it is now, in the fight
float g_fBossGoal[3]; // where it's drifting to
float g_fArenaMins[2] = { -999999.0, -999999.0 };
float g_fArenaMaxs[2] = { 999999.0, 999999.0 };
bool g_bArenaKnown;
float g_fNextAura;

// The floor laser (stage 3): a beam sweeping round the boss along the floor. Jump over it.
bool g_bSweep;
float g_fSweepStart;
float g_fSweepYaw;
float g_fNextSweepHit[MAXPLAYERS + 1];
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
bool g_bShotFired[MAX_SHOTS]; // fired, and still deadly while its beam shows
float g_fShotLiveUntil[MAX_SHOTS];
bool g_bShotHit[MAX_SHOTS][MAXPLAYERS + 1]; // who it already hurt (once each)

// Manhacks of the fight, and until when one counts as thrown (it was in a gravity gun a moment ago).
ArrayList g_alManhacks;
float g_fThrownUntil[MAXENTITIES + 1];
float g_fHackLast[MAXENTITIES + 1][3]; // where each manhack was at the last check
bool g_bHackSeen[MAXENTITIES + 1];

Handle g_hThink;
bool g_bLate;
int g_iBloodSpray;
int g_iBloodDrop;
int g_iBloodDecal[4];

// Bloodletting (stage 2+): blood-laser tethers that drain everyone it can see. Break its sight or get away.
#define LEECH_RANGE 1100.0
#define LEECH_TIME 2.5
bool g_bLeech;
float g_fLeechStart;
float g_fNextLeechTick;
bool g_bLeeched[MAXPLAYERS + 1]; // still held since the tether caught them
bool g_bDrawTick; // warnings are redrawn every other think (0.2 s), to keep players' network traffic down
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
	MarkNativeAsOptional("Cel_SendHudMessage");

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("cm_boss_enable", "1", "Whether the boss fight on maps that have one (gm_bloodyconstruct_cm12) is on.");
	g_cvHits = CreateConVar("cm_boss_hits", "30", "Manhack hits it takes to beat the boss with one player (split over its three stages).", _, true, 3.0);
	g_cvHitsPerPlayer = CreateConVar("cm_boss_hits_per_player", "10", "Extra hits it takes for each more player in the fight.", _, true, 0.0);
	g_cvSlamDamage = CreateConVar("cm_boss_slam_damage", "60", "Damage of the floor shockwave (stage 2 on), unless you jump over it.", _, true, 0.0);
	g_cvRockDamage = CreateConVar("cm_boss_rock_damage", "80", "Damage of a falling rock (stage 3).", _, true, 0.0);
	g_cvReward = CreateConVar("cm_boss_reward", "10000", "CL each player still standing gets for beating the boss.", _, true, 0.0);
	g_cvLaserDamage = CreateConVar("cm_boss_laser_damage", "55", "Damage of one of the boss's lasers.", _, true, 0.0);
	g_cvManhacks = CreateConVar("cm_boss_manhacks", "3", "Manhacks in the arena at once (one more for each extra player).", _, true, 1.0, true, 12.0);
	g_cvXP = CreateConVar("cm_tactics_xp_boss", "200", "Tactics experience everyone still in the arena gets for beating the boss.", _, true, 0.0);
	g_cvEmblem = CreateConVar("cm_boss_emblem", "blood", "Emblem everyone still in the arena gets for beating the boss (empty = none).");
	g_cvLockDelay = CreateConVar("cm_boss_lock_delay", "5", "Seconds the door behind stays open after the first player drops in (so friends can follow); then it closes for the rest of the map.", _, true, 0.0);

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

	StopOldLoops();
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
	PrecacheSound(SND_BURN, true);
	PrecacheSound(SND_SPLAT, true);
	PrecacheSound(SND_GORE, true);
	PrecacheSound(SND_LEECH, true);

	g_iBloodSpray = PrecacheModel("sprites/bloodspray.vmt", true);
	g_iBloodDrop = PrecacheModel("sprites/blood.vmt", true);

	for (int i = 0; i < 4; i++)
	{
		char sDecal[32];

		FormatEx(sDecal, sizeof(sDecal), "decals/blood%d", i + 1);
		g_iBloodDecal[i] = PrecacheDecal(sDecal, true);
	}
	PrecacheSound(SND_PAIN, true);
	PrecacheSound(SND_DEATH, true);
	PrecacheSound(SND_LOCK, true);
	PrecacheSound(SND_ROAR, true);
	PrecacheSound(SND_SLAM, true);
	PrecacheSound(SND_ROCK, true);
	PrecacheSound(SND_SHIELD, true);

	g_bMapReady = false;
	g_bFight = false;
	g_bDoorLocked = false;
	g_bDoorClosing = false;
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
		g_bHackSeen[iEntity] = false;
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

	// The arena's corners (its rockpoints): the boss drifts around inside them.
	{
		int iPoint = -1, iFound = 0;
		char sPoint[32];
		float fPoint[3];

		g_fArenaMins = { 999999.0, 999999.0 };
		g_fArenaMaxs = { -999999.0, -999999.0 };

		while ((iPoint = FindEntityByClassname(iPoint, "info_target")) != -1)
		{
			GetEntPropString(iPoint, Prop_Data, "m_iName", sPoint, sizeof(sPoint));

			if (!StrEqual(sPoint, "rockpoints") && !StrEqual(sPoint, "ceilingpoints"))
			{
				continue;
			}

			GetEntPropVector(iPoint, Prop_Data, "m_vecAbsOrigin", fPoint);

			for (int a = 0; a < 2; a++)
			{
				if (fPoint[a] < g_fArenaMins[a]) g_fArenaMins[a] = fPoint[a];
				if (fPoint[a] > g_fArenaMaxs[a]) g_fArenaMaxs[a] = fPoint[a];
			}

			iFound++;
		}

		g_bArenaKnown = (iFound >= 2);
	}

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

	// The final door opens for anyone who walks up to it (its trigger starts switched off in the map), and the door
	// behind it stays open until the fight starts.
	int iTrigger = FindByName("trigger_multiple", "finaldoor_trig");

	if (iTrigger != -1)
	{
		AcceptEntityInput(iTrigger, "Enable");
	}

	int iBlock = FindByName("func_door", "finaldoor_block");

	if (iBlock != -1)
	{
		AcceptEntityInput(iBlock, "Unlock");
		AcceptEntityInput(iBlock, "Open");
	}

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
	} else if (StrEqual(sName, "finaldoor_trig")) {
		int iDoor = FindByName("func_door", "finaldoor");

		if (iDoor != -1)
		{
			AcceptEntityInput(iDoor, "Open", iActivator, iActivator);
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

			Chat(iClient, "{green}%s{default} is gone from this map.", BOSS_NAME);
		}

		return;
	}

	// The door is shut: the fight is already on without them.
	if (g_bDoorLocked)
	{
		return;
	}

	// Walked in past the trigger: in the fight from here (no teleport; whoever isn't in before the door shuts is
	// locked out).
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

	Chat(iClient, "Only the {green}gravity gun{default} works in here. Dodge {green}%s{default}'s lasers, jump its shockwaves, keep your distance, and throw the manhacks into it!", BOSS_NAME);
}

void StartFight()
{
	g_bFight = true;
	g_bDoorLocked = false;
	g_iHits = 0;
	g_iStage = 1;
	g_fShieldUntil = 0.0;
	g_bSweep = false;
	g_fBossCur = g_fBossPos;
	g_fBossGoal = g_fBossPos;
	g_iAttack = 0;
	g_iBurstLeft = 0;
	g_bWave = false;

	for (int i = 0; i < MAX_ROCKS; i++)
	{
		g_bRock[i] = false;
	}

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

	// The door behind stays open a moment, then shuts for good.
	if (!g_bDoorClosing)
	{
		g_bDoorClosing = true;

		CreateTimer(g_cvLockDelay.FloatValue, Timer_LockDoor, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_LockDoor(Handle hTimer)
{
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
			Chat(i, "The door slams shut behind you. There's no way back.");
		}
	}

	return Plugin_Stop;
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

	g_bDrawTick = !g_bDrawTick;

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

	RunWave(iBoss, fNow);
	RunRocks(iBoss, fNow);
	RunBurst(fEye, fNow);
	RunSweep(iBoss, fEye, fNow);
	RunLeech(iBoss, fEye, fNow);
	RunAura(iBoss, fEye, fNow);

	// Its attacks, by stage; none while it's staggered between stages.
	if (fNow >= g_fNextAttack && fNow >= g_fShieldUntil)
	{
		Attack(iBoss, fEye, fNow);
	}

	if (fNow >= g_fNextManhack)
	{
		g_fNextManhack = fNow + (g_iStage == 3 ? 2.5 : 4.0);

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

	// It drifts from spot to spot around the arena, faster each stage (not while staggered).
	if (fNow >= g_fShieldUntil)
	{
		float fToGoal[3];

		SubtractVectors(g_fBossGoal, g_fBossCur, fToGoal);
		fToGoal[2] = 0.0;

		float fLeft = GetVectorLength(fToGoal), fStep = (g_iStage == 1 ? 90.0 : (g_iStage == 2 ? 150.0 : 230.0)) * 0.1;

		if (fLeft <= fStep)
		{
			PickGoal();
		} else {
			ScaleVector(fToGoal, fStep / fLeft);
			AddVectors(g_fBossCur, fToGoal, g_fBossCur);
		}
	}

	// A slow hover.
	fPos = g_fBossCur;
	fPos[2] += Sine((fNow - g_fFightStart) * 1.5) * 12.0;

	TeleportEntity(iBoss, fPos, fAngles, NULL_VECTOR);
}

// A new spot to drift to: somewhere in the arena (kept off its walls), a fair way from where it is.
void PickGoal()
{
	float fMins[2], fMaxs[2];

	if (g_bArenaKnown)
	{
		for (int a = 0; a < 2; a++)
		{
			float fInset = (g_fArenaMaxs[a] - g_fArenaMins[a]) * 0.2;

			fMins[a] = g_fArenaMins[a] + fInset;
			fMaxs[a] = g_fArenaMaxs[a] - fInset;
		}
	} else {
		for (int a = 0; a < 2; a++)
		{
			fMins[a] = g_fBossPos[a] - 400.0;
			fMaxs[a] = g_fBossPos[a] + 400.0;
		}
	}

	for (int iTry = 0; iTry < 8; iTry++)
	{
		g_fBossGoal[0] = GetRandomFloat(fMins[0], fMaxs[0]);
		g_fBossGoal[1] = GetRandomFloat(fMins[1], fMaxs[1]);
		g_fBossGoal[2] = g_fBossPos[2];

		if (SquareRoot(Pow(g_fBossGoal[0] - g_fBossCur[0], 2.0) + Pow(g_fBossGoal[1] - g_fBossCur[1], 2.0)) > 300.0)
		{
			break;
		}
	}
}

// Getting close hurts: anyone inside its field is burned and thrown back out.
#define AURA_RADIUS 300.0

void RunAura(int iBoss, const float fEye[3], float fNow)
{
	if (fNow < g_fNextAura)
	{
		return;
	}

	g_fNextAura = fNow + 0.3;

	float fFloor[3];

	fFloor = g_fBossCur;
	fFloor[2] = g_fSpawnPos[2] + 4.0;

	// Its edge, faintly on the floor (ring sizes are across).
	TE_SetupBeamRingPoint(fFloor, AURA_RADIUS * 2.0, AURA_RADIUS * 2.0 + 1.0, g_iLaserSprite, 0, 0, 0, 0.32, 3.0, 1.5, { 120, 0, 0, 140 }, 0, 0);
	TE_SendToAll();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bInFight[i] || !IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		float fPos[3], fPush[3];

		GetClientAbsOrigin(i, fPos);

		float fDistance = SquareRoot(Pow(fPos[0] - fEye[0], 2.0) + Pow(fPos[1] - fEye[1], 2.0));

		if (fDistance > AURA_RADIUS)
		{
			continue;
		}

		SDKHooks_TakeDamage(i, iBoss, iBoss, 12.0, DMG_SHOCK);
		Bleed(i);

		fPush[0] = fPos[0] - fEye[0];
		fPush[1] = fPos[1] - fEye[1];
		fPush[2] = 0.0;
		NormalizeVector(fPush, fPush);
		ScaleVector(fPush, 650.0);
		fPush[2] = 220.0;

		TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, fPush);

		TE_SetupBeamPoints(fEye, fPos, g_iLaserSprite, 0, 0, 0, 0.2, 4.0, 1.0, 0, 6.0, { 200, 0, 0, 255 }, 0);
		TE_SendToAll();
	}
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
	g_bShotFired[iShot] = false;
}

void RunShots(int iBoss, float fNow)
{
	for (int i = 0; i < MAX_SHOTS; i++)
	{
		if (!g_bShot[i])
		{
			continue;
		}

		if (!g_bShotFired[i] && fNow < g_fShotTime[i])
		{
			// The warning: a thin flickering line along where it'll fire.
			if (g_bDrawTick)
			{
				TE_SetupBeamPoints(g_fShotStart[i], g_fShotEnd[i], g_iLaserSprite, 0, 0, 0, 0.22, 1.5, 1.5, 0, 1.0, { 140, 0, 0, 170 }, 0);
				TE_SendToAll();
			}

			continue;
		}

		if (!g_bShotFired[i])
		{
			g_bShotFired[i] = true;
			g_fShotLiveUntil[i] = fNow + 0.35;

			for (int c = 0; c <= MaxClients; c++)
			{
				g_bShotHit[i][c] = false;
			}

			// A blood-red beam with a hot core.
			TE_SetupBeamPoints(g_fShotStart[i], g_fShotEnd[i], g_iLaserSprite, 0, 0, 0, 0.35, 16.0, 12.0, 0, 1.5, { 170, 0, 0, 255 }, 0);
			TE_SendToAll();
			TE_SetupBeamPoints(g_fShotStart[i], g_fShotEnd[i], g_iLaserSprite, 0, 0, 0, 0.25, 4.0, 3.0, 0, 0.0, { 255, 120, 110, 255 }, 0);
			TE_SendToAll();

			// It leaves blood where it lands.
			BloodDecal(g_fShotEnd[i]);

			EmitSoundToAll(SND_FIRE, iBoss, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);
		}

		// Deadly for as long as the beam shows: anyone whose body it touches (once each).
		for (int c = 1; c <= MaxClients; c++)
		{
			if (g_bShotHit[i][c] || !g_bInFight[c] || !IsClientInGame(c) || !IsPlayerAlive(c))
			{
				continue;
			}

			if (SegmentHitsPlayer(c, g_fShotStart[i], g_fShotEnd[i], 6.0))
			{
				g_bShotHit[i][c] = true;

				SDKHooks_TakeDamage(c, iBoss, iBoss, g_cvLaserDamage.FloatValue, DMG_ENERGYBEAM);
				Bleed(c);
			}
		}

		if (fNow >= g_fShotLiveUntil[i])
		{
			g_bShot[i] = false;
		}
	}
}

// Whether a line passes through a player's body (their real box, taller standing than crouched), give or take a
// little padding.
bool SegmentHitsPlayer(int iClient, const float fA[3], const float fB[3], float fPad)
{
	float fOrigin[3], fMins[3], fMaxs[3];

	GetClientAbsOrigin(iClient, fOrigin);
	GetClientMins(iClient, fMins);
	GetClientMaxs(iClient, fMaxs);

	float fLow = 0.0, fHigh = 1.0;

	for (int a = 0; a < 3; a++)
	{
		float fBoxMin = fOrigin[a] + fMins[a] - fPad, fBoxMax = fOrigin[a] + fMaxs[a] + fPad;
		float fDelta = fB[a] - fA[a];

		if (FloatAbs(fDelta) < 0.0001)
		{
			if (fA[a] < fBoxMin || fA[a] > fBoxMax)
			{
				return false;
			}

			continue;
		}

		float fT1 = (fBoxMin - fA[a]) / fDelta, fT2 = (fBoxMax - fA[a]) / fDelta;

		if (fT1 > fT2)
		{
			float fSwap = fT1;
			fT1 = fT2;
			fT2 = fSwap;
		}

		if (fT1 > fLow) fLow = fT1;
		if (fT2 < fHigh) fHigh = fT2;

		if (fLow > fHigh)
		{
			return false;
		}
	}

	return true;
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

	int iWant = g_cvManhacks.IntValue + CountFighters() - 1 + (g_iStage == 3 ? 2 : 0);

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

	float fRadius = BossRadius(iBoss) + 20.0;

	for (int i = g_alManhacks.Length - 1; i >= 0; i--)
	{
		int iHack = EntRefToEntIndex(g_alManhacks.Get(i));

		if (iHack == INVALID_ENT_REFERENCE)
		{
			g_alManhacks.Erase(i);
			continue;
		}

		float fPos[3], fLast[3];

		GetEntPropVector(iHack, Prop_Data, "m_vecAbsOrigin", fPos);

		fLast = g_bHackSeen[iHack] ? g_fHackLast[iHack] : fPos;
		g_fHackLast[iHack] = fPos;
		g_bHackSeen[iHack] = true;

		// Held in a gravity gun right now (the manhack's own flag, where the game has it).
		if (HasEntProp(iHack, Prop_Data, "m_bHeld") && GetEntProp(iHack, Prop_Data, "m_bHeld"))
		{
			g_fThrownUntil[iHack] = fNow + 3.0;
		}

		// Its speed, measured from how far it moved since the last check (a tenth of a second ago): a thrown
		// manhack covers far more ground than one flying by itself.
		float fSpeed = GetVectorDistance(fPos, fLast) / 0.1;

		if (fSpeed > 600.0)
		{
			g_fThrownUntil[iHack] = fNow + 1.0;
		}

		// Its whole path since the last check, not just where it is now: a fast throw can cross the boss between
		// two checks.
		if (DistanceToSegment(fEye, fLast, fPos) > fRadius)
		{
			continue;
		}

		// Thrown: it was in a gravity gun a moment ago, or it's flying far faster than a manhack flies by itself.
		if (fNow > g_fThrownUntil[iHack])
		{
			continue;
		}

		g_alManhacks.Erase(i);

		// Staggered between stages: the throw sparks off its shield.
		if (fNow < g_fShieldUntil)
		{
			TE_SetupSparks(fPos, NULL_VECTOR, 8, 6);
			TE_SendToAll();

			EmitSoundToAll(SND_SHIELD, iBoss, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);

			SDKHooks_TakeDamage(iHack, iBoss, iBoss, 500.0, DMG_BLAST);
			AcceptEntityInput(iHack, "Kill");

			continue;
		}

		BloodBurst(fPos, 5, 70.0);

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

	if (g_iHits >= g_iMaxHits)
	{
		ShowBossHud();
		BossDefeated(iBoss);
		return;
	}

	// A third of its health gone: the next stage.
	int iStage = 1 + (g_iHits * 3) / g_iMaxHits;

	if (iStage > g_iStage)
	{
		NextStage(iBoss, iStage);
	}

	ShowBossHud();
}

// ---- Stages -------------------------------------------------------------------------------------------------------

char g_sStageName[][] = { "", "Bloodshot", "Hemorrhage", "Exsanguination" };

// Between stages: it roars, staggers behind a shield for a few seconds, and throws everyone back.
void NextStage(int iBoss, int iStage)
{
	g_iStage = iStage;

	float fNow = GetGameTime(), fEye[3];

	g_fShieldUntil = fNow + 4.0;
	g_fNextAttack = g_fShieldUntil + 0.5;
	g_iBurstLeft = 0;

	BossCenter(iBoss, fEye);

	EmitSoundToAll(SND_ROAR, iBoss, SNDCHAN_VOICE, SNDLEVEL_SCREAMING);

	int iColor[4] = { 170, 0, 0, 255 };

	if (iStage == 3)
	{
		iColor = { 255, 0, 0, 255 };
	}

	BloodBurst(fEye, 8, 120.0);
	EmitSoundToAll(SND_GORE, iBoss, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);

	TE_SetupBeamRingPoint(fEye, 20.0, 900.0, g_iLaserSprite, 0, 0, 0, 0.8, 24.0, 0.0, iColor, 0, 0);
	TE_SendToAll();

	// Thrown back from it, and the room shakes.
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bInFight[i] || !IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		float fPos[3], fPush[3];

		GetClientAbsOrigin(i, fPos);
		SubtractVectors(fPos, fEye, fPush);
		fPush[2] = 0.0;
		NormalizeVector(fPush, fPush);
		ScaleVector(fPush, 550.0);
		fPush[2] = 280.0;

		TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, fPush);

		Shake(i, 12.0, 3.0);

		Chat(i, "{green}%s{default}: {green}%s{default}. It's shielded for a moment!", BOSS_NAME, g_sStageName[iStage]);
	}

	// The last stage: it glows red from now on.
	if (iStage == 3)
	{
		SetEntityRenderColor(iBoss, 255, 120, 120, 255);
	}
}

// Takes turns between its attacks; later stages have more of them, and use them faster. Built to be very hard for a
// room full of players with 225 health: most attacks go for everyone at once.
void Attack(int iBoss, const float fEye[3], float fNow)
{
	if (RandomFighter() == -1)
	{
		return;
	}

	int iKinds = (g_iStage == 1) ? 3 : (g_iStage == 2 ? 6 : 7);
	int iKind = g_iAttack++ % iKinds;
	float fWarn = (g_iStage == 1) ? 0.8 : (g_iStage == 2 ? 0.65 : 0.5);

	switch (iKind)
	{
		// A laser at every player (two each in the last stage).
		case 0:
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (g_bInFight[i] && IsClientInGame(i) && IsPlayerAlive(i))
				{
					AimShot(fEye, i, fWarn);

					if (g_iStage == 3)
					{
						AimShot(fEye, i, fWarn + 0.35);
					}
				}
			}

			EmitSoundToAll(SND_CHARGE, iBoss, SNDCHAN_WEAPON, SNDLEVEL_SCREAMING);
		}

		// A burst: quick shots at one player, each aimed where they've moved to.
		case 1:
		{
			g_iBurstLeft = (g_iStage == 3) ? 6 : 4;
			g_iBurstTarget = GetClientUserId(RandomFighter());
			g_fNextBurst = fNow;

			EmitSoundToAll(SND_CHARGE, iBoss, SNDCHAN_WEAPON, SNDLEVEL_SCREAMING);
		}

		// It slams the floor: a ring runs out across the arena. Jump over it.
		case 2:
		{
			StartWave(iBoss, fNow);
		}

		// The ceiling opens fire: lasers at every player from above.
		case 3:
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (!g_bInFight[i] || !IsClientInGame(i) || !IsPlayerAlive(i))
				{
					continue;
				}

				for (int n = 0; n < (g_iStage == 3 ? 2 : 1); n++)
				{
					AimShot(g_iCeilingCount > 0 ? g_fCeiling[GetRandomInt(0, g_iCeilingCount - 1)] : fEye, i, fWarn + 0.2 + n * 0.4);
				}
			}

			EmitSoundToAll(SND_CHARGE, iBoss, SNDCHAN_WEAPON, SNDLEVEL_SCREAMING);
		}

		// Rocks fall where everyone stands (and where they're running to).
		case 4:
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (g_bInFight[i] && IsClientInGame(i) && IsPlayerAlive(i))
				{
					float fPos[3], fVel[3];

					GetClientAbsOrigin(i, fPos);
					DropRock(fPos, fNow + 1.1);

					GetEntPropVector(i, Prop_Data, "m_vecAbsVelocity", fVel);
					fPos[0] += fVel[0] * 0.9;
					fPos[1] += fVel[1] * 0.9;
					DropRock(fPos, fNow + 1.4);
				}
			}
		}

		// The floor laser: a beam sweeps all the way round it along the floor. Jump over it.
		// Bloodletting: blood-laser tethers latch onto everyone it can see and drain them.
		case 5:
		{
			StartLeech(iBoss, fNow);
		}

		case 6:
		{
			g_bSweep = true;
			g_fSweepStart = fNow + 1.0;
			g_fSweepYaw = GetRandomFloat(0.0, 360.0);

			for (int i = 1; i <= MaxClients; i++)
			{
				g_fNextSweepHit[i] = 0.0;
			}

			EmitSoundToAll(SND_CHARGE, iBoss, SNDCHAN_WEAPON, SNDLEVEL_SCREAMING);
		}
	}

	float fGap = (g_iStage == 1) ? 1.8 : (g_iStage == 2 ? 1.4 : 1.0);

	g_fNextAttack = fNow + fGap + ((iKind == 2 || iKind == 5 || iKind == 6) ? 1.2 : 0.0);
}

#define SWEEP_TIME 3.0
#define SWEEP_LENGTH 1400.0

void RunSweep(int iBoss, const float fEye[3], float fNow)
{
	if (!g_bSweep)
	{
		return;
	}

	float fFloorZ = g_fSpawnPos[2] + 14.0;
	float fStart[3], fEnd[3];

	fStart = g_fBossCur;
	fStart[2] = fFloorZ;

	// Its warning: a thin line where it starts.
	if (fNow < g_fSweepStart)
	{
		fEnd = fStart;
		fEnd[0] += Cosine(DegToRad(g_fSweepYaw)) * SWEEP_LENGTH;
		fEnd[1] += Sine(DegToRad(g_fSweepYaw)) * SWEEP_LENGTH;

		if (g_bDrawTick)
		{
			TE_SetupBeamPoints(fStart, fEnd, g_iLaserSprite, 0, 0, 0, 0.22, 2.0, 2.0, 0, 1.0, { 140, 0, 0, 180 }, 0);
			TE_SendToAll();
		}
		return;
	}

	float fDone = (fNow - g_fSweepStart) / SWEEP_TIME;

	if (fDone > 1.0)
	{
		g_bSweep = false;
		return;
	}

	float fYaw = g_fSweepYaw + fDone * 360.0;

	fEnd = fStart;
	fEnd[0] += Cosine(DegToRad(fYaw)) * SWEEP_LENGTH;
	fEnd[1] += Sine(DegToRad(fYaw)) * SWEEP_LENGTH;

	TE_SetupBeamPoints(fEye, fStart, g_iLaserSprite, 0, 0, 0, 0.12, 6.0, 6.0, 0, 1.0, { 200, 0, 0, 255 }, 0);
	TE_SendToAll();
	TE_SetupBeamPoints(fStart, fEnd, g_iLaserSprite, 0, 0, 0, 0.12, 10.0, 10.0, 0, 1.5, { 200, 0, 0, 255 }, 0);
	TE_SendToAll();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bInFight[i] || !IsClientInGame(i) || !IsPlayerAlive(i) || fNow < g_fNextSweepHit[i])
		{
			continue;
		}

		// Along the floor: a jump lifts you over it.
		if (SegmentHitsPlayer(i, fStart, fEnd, 4.0))
		{
			SDKHooks_TakeDamage(i, iBoss, iBoss, g_cvLaserDamage.FloatValue, DMG_ENERGYBEAM);
			Bleed(i);

			g_fNextSweepHit[i] = fNow + 0.5;
		}
	}
}

void RunBurst(const float fEye[3], float fNow)
{
	if (g_iBurstLeft < 1 || fNow < g_fNextBurst)
	{
		return;
	}

	int iTarget = GetClientOfUserId(g_iBurstTarget);

	if (iTarget < 1 || !g_bInFight[iTarget] || !IsPlayerAlive(iTarget))
	{
		g_iBurstLeft = 0;
		return;
	}

	AimShot(fEye, iTarget, 0.7);

	g_iBurstLeft--;
	g_fNextBurst = fNow + 0.4;
}

void StartWave(int iBoss, float fNow)
{
	g_bWave = true;
	g_fWaveStart = fNow + 1.0;

	g_fWaveCenter = g_fBossCur;
	g_fWaveCenter[2] = g_fSpawnPos[2] + 6.0;

	for (int i = 1; i <= MaxClients; i++)
	{
		g_bWaveHit[i] = false;
	}

	// Its warning: it roars and the floor under it glows.
	EmitSoundToAll(SND_ROAR, iBoss, SNDCHAN_VOICE, SNDLEVEL_SCREAMING);

	TE_SetupBeamRingPoint(g_fWaveCenter, 140.0, 20.0, g_iLaserSprite, 0, 0, 0, 1.0, 12.0, 0.0, { 150, 0, 0, 255 }, 0, 0);
	TE_SendToAll();
}

#define WAVE_SPEED 650.0
#define WAVE_REACH 2400.0

void RunWave(int iBoss, float fNow)
{
	if (!g_bWave || fNow < g_fWaveStart)
	{
		return;
	}

	float fRadius = (fNow - g_fWaveStart) * WAVE_SPEED;

	// Sent once: the game grows the ring itself, at the same speed.
	if (fRadius < WAVE_SPEED * 0.11)
	{
		TE_SetupBeamRingPoint(g_fWaveCenter, 10.0, WAVE_REACH * 2.0, g_iLaserSprite, 0, 0, 0, WAVE_REACH / WAVE_SPEED, 18.0, 2.0, { 160, 0, 0, 255 }, 0, 0);
		TE_SendToAll();

		EmitAmbientSound(SND_SLAM, g_fWaveCenter, SOUND_FROM_WORLD, SNDLEVEL_SCREAMING);
		EmitAmbientSound(SND_GORE, g_fWaveCenter, SOUND_FROM_WORLD, SNDLEVEL_SCREAMING);

		BloodBurst(g_fWaveCenter, 10, 160.0);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_bInFight[i] && IsClientInGame(i))
			{
				Shake(i, 6.0, 1.0);
			}
		}
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bInFight[i] || g_bWaveHit[i] || !IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		float fPos[3];

		GetClientAbsOrigin(i, fPos);

		float fDistance = SquareRoot(Pow(fPos[0] - g_fWaveCenter[0], 2.0) + Pow(fPos[1] - g_fWaveCenter[1], 2.0));

		// The ring passes under them: on the ground it hits; in the air (a jump) it passes.
		if (fDistance > fRadius - 70.0 && fDistance < fRadius + 20.0)
		{
			g_bWaveHit[i] = true;

			if (GetEntityFlags(i) & FL_ONGROUND)
			{
				SDKHooks_TakeDamage(i, iBoss, iBoss, g_cvSlamDamage.FloatValue, DMG_SONIC);
				Bleed(i);

				float fPush[3];

				fPush[2] = 320.0;
				TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, fPush);
			}
		}
	}

	if (fRadius > WAVE_REACH)
	{
		g_bWave = false;
	}
}

void DropRock(const float fPos[3], float fWhen)
{
	for (int i = 0; i < MAX_ROCKS; i++)
	{
		if (!g_bRock[i])
		{
			g_bRock[i] = true;
			g_fRockPos[i] = fPos;
			g_fRockPos[i][2] += 4.0;
			g_fRockTime[i] = fWhen;
			return;
		}
	}
}

void RunRocks(int iBoss, float fNow)
{
	for (int r = 0; r < MAX_ROCKS; r++)
	{
		if (!g_bRock[r])
		{
			continue;
		}

		if (fNow < g_fRockTime[r])
		{
			// The mark where it lands, tightening as it falls.
			float fLeft = g_fRockTime[r] - fNow;

			// (Ring sizes are across, not from the middle: 180 marks the 90 it hits.)
			if (g_bDrawTick)
			{
				TE_SetupBeamRingPoint(g_fRockPos[r], 180.0 + fLeft * 120.0, 180.0, g_iLaserSprite, 0, 0, 0, 0.22, 4.0, 0.0, { 150, 0, 0, 230 }, 0, 0);
				TE_SendToAll();
			}
			continue;
		}

		g_bRock[r] = false;

		// A glob of blood bursts where it lands.
		BloodBurst(g_fRockPos[r], 6, 90.0);
		BloodDecal(g_fRockPos[r]);

		EmitAmbientSound(SND_ROCK, g_fRockPos[r], SOUND_FROM_WORLD, SNDLEVEL_SCREAMING);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (!g_bInFight[i] || !IsClientInGame(i) || !IsPlayerAlive(i))
			{
				continue;
			}

			float fPos[3];

			GetClientAbsOrigin(i, fPos);

			if (SquareRoot(Pow(fPos[0] - g_fRockPos[r][0], 2.0) + Pow(fPos[1] - g_fRockPos[r][1], 2.0)) < 90.0 && FloatAbs(fPos[2] - g_fRockPos[r][2]) < 96.0)
			{
				SDKHooks_TakeDamage(i, iBoss, iBoss, g_cvRockDamage.FloatValue, DMG_CRUSH);
				Bleed(i);
			}
		}
	}
}

// ---- Blood ------------------------------------------------------------------------------------------------------

// A spray of blood from a point, in all directions.
void BloodBurst(const float fPos[3], int iCount, float fSpread)
{
	for (int i = 0; i < iCount; i++)
	{
		float fDir[3], fAt[3];

		fDir[0] = GetRandomFloat(-1.0, 1.0);
		fDir[1] = GetRandomFloat(-1.0, 1.0);
		fDir[2] = GetRandomFloat(0.2, 1.0);

		fAt = fPos;
		fAt[0] += GetRandomFloat(-fSpread, fSpread) * 0.3;
		fAt[1] += GetRandomFloat(-fSpread, fSpread) * 0.3;

		TE_SetupBloodSprite(fAt, fDir, { 160, 0, 0, 255 }, RoundToFloor(fSpread / 10.0) + 6, g_iBloodSpray, g_iBloodDrop);
		TE_SendToAll(i * 0.03);
	}
}

// A blood stain on the floor under a point.
void BloodDecal(const float fPos[3])
{
	float fDown[3], fHit[3];

	fDown = fPos;
	fDown[2] -= 256.0;

	TR_TraceRayFilter(fPos, fDown, MASK_SOLID_BRUSHONLY, RayType_EndPoint, Filter_WorldOnly);

	if (!TR_DidHit())
	{
		return;
	}

	TR_GetEndPosition(fHit);

	TE_Start("World Decal");
	TE_WriteVector("m_vecOrigin", fHit);
	TE_WriteNum("m_nIndex", g_iBloodDecal[GetRandomInt(0, 3)]);
	TE_SendToAll();
}

// A player hit: they bleed, and it burns.
void Bleed(int iClient)
{
	float fPos[3];

	GetClientAbsOrigin(iClient, fPos);
	fPos[2] += 40.0;

	BloodBurst(fPos, 3, 40.0);
	BloodDecal(fPos);

	EmitSoundToAll(SND_BURN, iClient, SNDCHAN_AUTO, SNDLEVEL_NORMAL);
}

void StartLeech(int iBoss, float fNow)
{
	g_bLeech = true;
	g_fLeechStart = fNow + 0.8;
	g_fNextLeechTick = g_fLeechStart;

	for (int i = 1; i <= MaxClients; i++)
	{
		g_bLeeched[i] = true;
	}

	EmitSoundToAll(SND_LEECH, iBoss, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);
}

// Can the boss's eye see this player, close enough to drain them?
bool LeechReaches(const float fEye[3], int iClient)
{
	float fChest[3];

	GetClientAbsOrigin(iClient, fChest);
	fChest[2] += 40.0;

	if (GetVectorDistance(fEye, fChest) > LEECH_RANGE)
	{
		return false;
	}

	TR_TraceRayFilter(fEye, fChest, MASK_SOLID, RayType_EndPoint, Filter_NotPlayersOrBoss);

	return !TR_DidHit();
}

public bool Filter_NotPlayersOrBoss(int iEntity, int iContentsMask)
{
	return iEntity > MaxClients && iEntity != EntRefToEntIndex(g_iBossRef) && g_alManhacks.FindValue(EntIndexToEntRef(iEntity)) == -1;
}

void RunLeech(int iBoss, const float fEye[3], float fNow)
{
	if (!g_bLeech)
	{
		return;
	}

	bool bWarning = fNow < g_fLeechStart, bTick = !bWarning && fNow >= g_fNextLeechTick;

	if (bTick)
	{
		g_fNextLeechTick = fNow + 0.3;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bLeeched[i] || !g_bInFight[i] || !IsClientInGame(i) || !IsPlayerAlive(i))
		{
			g_bLeeched[i] = false;
			continue;
		}

		// Out of its sight or reach: the tether snaps, and stays snapped for this attack.
		if (!LeechReaches(fEye, i))
		{
			g_bLeeched[i] = false;
			continue;
		}

		float fChest[3];

		GetClientAbsOrigin(i, fChest);
		fChest[2] += 40.0;

		if (g_bDrawTick || bTick)
		{
			TE_SetupBeamPoints(fEye, fChest, g_iLaserSprite, 0, 0, 0, 0.22, bWarning ? 1.0 : 6.0, bWarning ? 1.0 : 3.0, 0, bWarning ? 0.0 : 4.0, bWarning ? { 120, 0, 0, 150 } : { 200, 0, 0, 255 }, 0);
			TE_SendToAll();
		}

		if (bTick)
		{
			SDKHooks_TakeDamage(i, iBoss, iBoss, 8.0, DMG_ENERGYBEAM);

			BloodBurst(fChest, 1, 30.0);
		}
	}

	if (fNow < g_fLeechStart + LEECH_TIME)
	{
		return;
	}

	g_bLeech = false;

	// Anyone it held the whole time feeds it: it heals a hit's worth (never back past the start of its stage).
	bool bFed = false;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bLeeched[i] && g_bInFight[i] && IsClientInGame(i) && IsPlayerAlive(i))
		{
			bFed = true;
		}
	}

	int iStageStart = ((g_iStage - 1) * g_iMaxHits + 2) / 3;

	if (bFed && g_iHits > iStageStart)
	{
		g_iHits--;

		EmitSoundToAll(SND_GORE, iBoss, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_bInFight[i] && IsClientInGame(i))
			{
				Chat(i, "{green}%s{default} feeds on your blood and heals. Break its sight to escape the tethers!", BOSS_NAME);
			}
		}

		ShowBossHud();
	}
}

// An earlier version played the stalker's looping laser sounds, which never stop on their own: stopped wherever
// they could still be playing.
void StopOldLoops()
{
	static const char sLoops[][] = { "npc/stalker/laser_burn.wav", "npc/stalker/laser_flesh.wav" };

	for (int e = 1; e <= MaxClients; e++)
	{
		if (!IsClientInGame(e))
		{
			continue;
		}

		for (int l = 0; l < sizeof(sLoops); l++)
		{
			for (int c = 0; c <= 7; c++)
			{
				StopSound(e, c, sLoops[l]);
			}
		}
	}

	int iBoss = EntRefToEntIndex(g_iBossRef);

	if (iBoss != INVALID_ENT_REFERENCE)
	{
		for (int l = 0; l < sizeof(sLoops); l++)
		{
			for (int c = 0; c <= 7; c++)
			{
				StopSound(iBoss, c, sLoops[l]);
			}
		}
	}
}

// Shakes one player's screen.
void Shake(int iClient, float fAmplitude, float fDuration)
{
	Handle hMessage = StartMessageOne("Shake", iClient);

	if (hMessage == null)
	{
		return;
	}

	BfWrite bfShake = UserMessageToBfWrite(hMessage);

	bfShake.WriteByte(0);
	bfShake.WriteFloat(fAmplitude);
	bfShake.WriteFloat(150.0);
	bfShake.WriteFloat(fDuration);

	EndMessage();
}

public Action Timer_UnFlash(Handle hTimer)
{
	int iBoss = EntRefToEntIndex(g_iBossRef);

	if (iBoss != INVALID_ENT_REFERENCE)
	{
		if (g_iStage == 3)
		{
			SetEntityRenderColor(iBoss, 255, 120, 120, 255);
		} else {
			SetEntityRenderColor(iBoss, 255, 255, 255, 255);
		}
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

	// It bursts: blood everywhere.
	BloodBurst(fEye, 16, 220.0);
	EmitSoundToAll(SND_GORE, iBoss, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);

	for (int i = 0; i < 12; i++)
	{
		float fSplat[3];

		fSplat = fEye;
		fSplat[0] += GetRandomFloat(-260.0, 260.0);
		fSplat[1] += GetRandomFloat(-260.0, 260.0);
		fSplat[2] = g_fSpawnPos[2] + 8.0;

		BloodDecal(fSplat);
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

	ChatAll("{green}%s{default} wins. It sinks back into the dark until the next map.", BOSS_NAME);

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

	g_bWave = false;
	g_bSweep = false;
	g_bLeech = false;

	StopOldLoops();
	g_iBurstLeft = 0;

	for (int i = 0; i < MAX_ROCKS; i++)
	{
		g_bRock[i] = false;
	}

	// The fight is over for this map (the door behind is shut for good): Wide Eyes goes.
	int iBoss = EntRefToEntIndex(g_iBossRef);

	if (iBoss != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(iBoss, "Kill");
	}

	g_iBossRef = INVALID_ENT_REFERENCE;
	g_bBeaten = true;
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

	char sText[192];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bInFight[i] && IsClientInGame(i))
		{
			// Sent straight to channel 5 (CelMod's own HUD message): SourceMod's ShowHudText folds channel numbers into
			// its own count, which landed the bar on a channel the CelMod HUD redraws constantly.
			FormatEx(sText, sizeof(sText), "%s  -  %s%s\n[%s] %d/%d", BOSS_NAME, g_sStageName[g_iStage > 0 && g_iStage < 4 ? g_iStage : 1], GetGameTime() < g_fShieldUntil ? " (shielded)" : "", sBar, iLeft, g_iMaxHits);

			if (GetFeatureStatus(FeatureType_Native, "Cel_SendHudMessage") == FeatureStatus_Available)
			{
				Cel_SendHudMessage(i, 5, -1.0, 0.06, 255, 60, 40, 255, 0, 0.0, 0.0, 1.2, 0.0, sText);
			} else {
				ShowHudText(i, 0, "%s", sText);
			}
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

		if (g_bArenaKnown && i < 2)
		{
			fMiddle[i] = (g_fArenaMins[i] + g_fArenaMaxs[i]) * 0.5;
		}
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

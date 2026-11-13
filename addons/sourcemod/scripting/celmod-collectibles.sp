#pragma semicolon 1

#include <celmod>

#pragma newdecls required

/*
 * |CelMod| Collectibles
 *
 * Emblems  - Owned cels. Press E on one you own to enable it; while it is enabled and you are
 *			holding the gravity gun you get its power. Other players see the emblem model in
 *			your hands, your own first person view stays the default gravity gun.
 * Hats	 - Owned cels. Press E on one you own to wear it.
 * Drops	- Crates rain from the sky. Any crate that ends up inside a land becomes an item
 *			owned by that land's owner.
 * Rewards  - Admin placed pickups (end of a maze, parkour, ...). Press E to claim once.
 *
 * Every item a player owns is recorded in their client settings ("emblem_<id>" / "hat_<id>").
 * That ledger is what stops items being duplicated through !save/!load, and what lets a
 * player get an item back with !emblem / !hat after the entity is removed or the map changes.
 */

#define MAX_ITEMS 320
#define MAX_PLAYERMODELS 48

#define KIND_EMBLEM 0
#define KIND_HAT 1
#define KIND_WEAPON 2

#define BOOTH_MODEL "models/props_lab/hev_case.mdl"
#define BOOTH_MODEL_FALLBACK "models/props_combine/suit_charger001.mdl"
#define CANISTER_MODEL "models/props_combine/headcrabcannister01a.mdl"
#define BIG_EMBLEM_MODEL "models/celmod/bhys8.mdl"

#define GRAVGUN_CLASS "weapon_physcannon"
#define GRAVGUN_WORLDMODEL "models/weapons/w_physics.mdl"
#define DROPBOX_MODEL "models/celmod/physbox8.mdl"
#define DROPBOX_FALLBACK "models/items/item_item_crate.mdl"

#define SOUND_EQUIP "buttons/button9.wav"
#define SOUND_UNEQUIP "buttons/button10.wav"
#define SOUND_DENY "buttons/button8.wav"
#define SOUND_FIRE "ambient/fire/mtov_flame2.wav"
#define SOUND_WATER "ambient/water/water_splash1.wav"
#define SOUND_STEAM "player/sprayer.wav"
#define SOUND_FLAME "ambient/fire/mtov_flame2.wav"
#define SOUND_FIREBALL "ambient/fire/gascan_ignite1.wav"
#define SOUND_QUAKE "ambient/explosions/exp2.wav"
#define SOUND_FLASH "npc/scanner/scanner_photo1.wav"
#define SOUND_CANISTER "weapons/mortar/mortar_shell_incomming1.wav"
#define SOUND_DIG "physics/surfaces/sand_impact_bullet1.wav"
#define SOUND_TRASH "physics/metal/metal_solid_impact_soft1.wav"
#define SOUND_HEAL "items/medshot4.wav"
#define SOUND_SHOCK "ambient/energy/zap1.wav"
#define SOUND_BLINK "ambient/machines/teleport1.wav"
#define SOUND_ICE "physics/glass/glass_impact_bullet4.wav"
#define SOUND_DROP "ambient/levels/labs/electric_explosion1.wav"
#define SOUND_REWARD "items/suitchargeok1.wav"

enum struct Item
{
	int iKind;
	char sId[32];
	char sName[48];
	char sModel[PLATFORM_MAX_PATH];
	int iColor[4];
	char sPower[24];
	float fValue;
	float fCooldown;
	float fDuration;
	float fRange;
	int iWeight;
	float fOffset[3];
	float fAngles[3];
	float fScale;
	int iBeamColor[4];
	int iDamageType;
	char sFx[16];
	char sAura[16];
	char sSecondary[16];
	float fSecondaryValue;
	float fSecondaryCooldown;
	char sSprite[PLATFORM_MAX_PATH];
	int iSpriteIndex;
	float fSlow;
	float fKnockback;
	float fIgnite;
	float fSpeed;
	int iSkin;
	float fHandOffset[3];
	float fHandAngles[3];
	float fHandScale;
	int iModelIndex;
	int iBig;
	bool bIsBig;
	char sUpgradeTo[32];
	int iUpgradeTo;
	int iUpgradeCost;
	float fJump;
	float fFallDamage;
	int iPlayerColor[4];
	bool bPlayerColor;
	bool bGlow;
	char sCustomGun[32];
	float fHitDamage;
	float fHitRange;
	float fRefire;
	char sDigs[64];
	char sHandModel[PLATFORM_MAX_PATH];
	char sAttack[16];
	char sBase[32];
	float fDamage;
}

enum struct PlayerModel
{
	char sId[32];
	char sName[48];
	char sModel[PLATFORM_MAX_PATH];
	int iPrice;
	int iAdminFlags;
}

char g_sKindClass[][] = { "cel_emblem", "cel_hat", "cel_weapon" };
char g_sKindName[][] = { "emblem", "hat", "weapon" };
char g_sKindPlural[][] = { "emblems", "hats", "weapons" };
char g_sKindTitle[][] = { "Emblems", "Hats", "Weapons" };

ConVar g_cvUpgradeCost;

int g_iBoothRef = INVALID_ENT_REFERENCE;
float g_fBoothSpot[3];
bool g_bBoothPlaced = false;
bool g_bBoothSpent = false;
char g_sLastBoothMap[PLATFORM_MAX_PATH];
float g_fLastBoothSpot[3];

char g_sBoothModel[PLATFORM_MAX_PATH];
char g_sDropModel[PLATFORM_MAX_PATH];

int g_iHeldBox[MAXPLAYERS + 1];
float g_fHeldBoxTime[MAXPLAYERS + 1];
char g_sCanisterModel[PLATFORM_MAX_PATH];
int g_iCelWepItem[MAXPLAYERS + 1];
int g_iShownGunRef[MAXPLAYERS + 1];
int g_iFireballItem[MAXENTITIES + 1];
int g_iFireballOwner[MAXENTITIES + 1];
int g_iMoneyBox[MAXENTITIES + 1];
bool g_bDugUp[MAXENTITIES + 1];
int g_iDugBy[MAXENTITIES + 1];
int g_iDigger;
int g_iTrashCans[64];
int g_iTrashCanCount;

ConVar g_cvTrashMax;
ConVar g_cvTrashMin;
float g_fNextCough[MAXPLAYERS + 1];
float g_fNextDig[MAXPLAYERS + 1];
int g_iSmogItem[MAXPLAYERS + 1][3];
int g_iSmogRef[MAXPLAYERS + 1][3];

ConVar g_cvNukeMaxProps;
ConVar g_cvNukeWrecks;
ConVar g_cvDigChance;
ConVar g_cvDigEmblemChance;
ConVar g_cvDigMoneyChance;
ConVar g_cvDigMoneyMax;
ConVar g_cvDigMoneyMin;

// What usually comes up when digging.
char g_sJunkModels[][] =
{
	"models/props_junk/garbage_milkcarton001a.mdl", "models/props_junk/garbage_glassbottle003a.mdl", "models/props_junk/garbage_metalcan001a.mdl",
	"models/props_junk/garbage_takeoutcarton001a.mdl", "models/props_junk/garbage_newspaper001a.mdl", "models/props_junk/shoe001a.mdl",
	"models/props_junk/popcan01a.mdl", "models/props_junk/garbage_plasticbottle003a.mdl", "models/props_junk/garbage_coffeemug001a.mdl",
	"models/props_junk/garbage_bag001a.mdl", "models/props_c17/doll01.mdl", "models/props_junk/meathook001a.mdl"
};
int g_iCelWepRef[MAXPLAYERS + 1];
int g_iPlayerModel[MAXPLAYERS + 1];
int g_iPlayerModelCount;

PlayerModel g_PlayerModels[MAX_PLAYERMODELS];

bool g_bLate;
bool g_bDropBox[MAXENTITIES + 1];
bool g_bFrozenTint[MAXPLAYERS + 1];
bool g_bHeldShown[MAXPLAYERS + 1];
bool g_bHoldingGravGun[MAXPLAYERS + 1];
bool g_bInvFromDisk[MAXPLAYERS + 1];
bool g_bCloaked[MAXPLAYERS + 1];
bool g_bTinted[MAXPLAYERS + 1];
bool g_bPhasing[MAXPLAYERS + 1];
bool g_bCelWepTaken[MAXPLAYERS + 1][MAX_ITEMS];
bool g_bCustomGuns;
bool g_bGravityManaged[MAXPLAYERS + 1];
bool g_bPortal[MAXPLAYERS + 1][2];
bool g_bSpeedManaged[MAXPLAYERS + 1];

// Walking speed, changed by tapping the walk key (left Alt): super slow, very slow, slow, normal, fast.
#define WALK_NORMAL 3
char g_sWalkTier[][] = { "super slow", "very slow", "slow", "normal", "fast" };
float g_fWalkTier[] = { 0.25, 0.4, 0.6, 1.0, 1.5 };
int g_iWalkTier[MAXPLAYERS + 1] = { WALK_NORMAL, ... };
bool g_bWalkKeyOff[MAXPLAYERS + 1];
bool g_bThirdPerson[MAXPLAYERS + 1];
int g_iCameraRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };

char g_sInvPath[MAXPLAYERS + 1][PLATFORM_MAX_PATH];
char g_sItemDB[PLATFORM_MAX_PATH];
char g_sMap[64];
char g_sRewardDB[PLATFORM_MAX_PATH];

ConVar g_cvDropCount;
ConVar g_cvDropDelay;
ConVar g_cvThirdPersonAimFix;
ConVar g_cvBoothAlpha;
ConVar g_cvDropInterval;
ConVar g_cvDropMinPlayers;
ConVar g_cvDropRadius;
ConVar g_cvGiftChance;
ConVar g_cvGiftDays;
ConVar g_cvShowSelf;

float g_fFrozenUntil[MAXPLAYERS + 1];
float g_fSkyward[3] = { 0.0, 0.0, 1.0 };
float g_fNextPower[MAXPLAYERS + 1];
float g_fNextSecondary[MAXPLAYERS + 1];
float g_fNextQuake[MAXPLAYERS + 1];

int g_iDemonColor[4] = { 120, 0, 160, 255 };
float g_fNextShotSound[MAXPLAYERS + 1];
float g_fPortal[MAXPLAYERS + 1][2][3];
float g_fPortalWait[MAXPLAYERS + 1];

int g_iActiveEmblem[MAXPLAYERS + 1];
int g_iActiveHat[MAXPLAYERS + 1];
int g_iEntItem[MAXENTITIES + 1];
int g_iHandEntRef[MAXPLAYERS + 1];
int g_iHandItem[MAXPLAYERS + 1];
int g_iHatEntRef[MAXPLAYERS + 1];
int g_iItemCount;
int g_iLastButtons[MAXPLAYERS + 1];
int g_iMinutesSinceDrop;
int g_iModdedWeaponRef[MAXPLAYERS + 1];
int g_iRewardId[MAXENTITIES + 1];
bool g_bRewardEvent[MAXENTITIES + 1];
bool g_bRewardLinked[MAXENTITIES + 1];
bool g_bInEvent[MAXPLAYERS + 1];
float g_fPhaseStart[MAXPLAYERS + 1][3];
int g_iTick;

Item g_Items[MAX_ITEMS];

KeyValues g_kvInv[MAXPLAYERS + 1];

// Custom Guns (github.com/Alienmario/customguns-hl2dm) gives celweps their own inventory slot, view model and
// world model. It is optional: without it celweps fall back to a stock weapon.
native bool CG_GiveGun(int iClient, const char[] sClassname, bool bIgnoreAdminLevel = false);
native void CG_ClearInventory(int iClient);
native float CG_PlayActivity(int iWeapon, int iActivity);
native void CG_SetPlayerAnimation(int iClient, int iPlayerAnim);
native void CG_GetShootPosition(int iClient, float fPos[3], float fForwardOffset = 0.0, float fRightOffset = 0.0, float fUpOffset = 0.0);

#define CG_ACT_VM_PRIMARYATTACK 180
#define CG_ACT_VM_HITCENTER 190
#define CG_ACT_VM_MISSCENTER 196
#define CG_PLAYER_ATTACK1 5

#include <celmod_emblemfx>

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	MarkNativeAsOptional("CG_GiveGun");
	MarkNativeAsOptional("Cel_GetZoneType");
	CreateNative("Cel_GetRewardLabel", Native_GetRewardLabel);
	MarkNativeAsOptional("CG_ClearInventory");
	MarkNativeAsOptional("CG_PlayActivity");
	MarkNativeAsOptional("CG_SetPlayerAnimation");
	MarkNativeAsOptional("CG_GetShootPosition");

	CreateNative("Cel_GetCollectibleId", Native_GetCollectibleId);
	CreateNative("Cel_GetCollectibleName", Native_GetCollectibleName);
	CreateNative("Cel_GetCollectibleLook", Native_GetCollectibleLook);
	CreateNative("Cel_GiveCollectible", Native_GiveCollectible);
	CreateNative("Cel_IsCollectible", Native_IsCollectible);
	CreateNative("Cel_GetDropBoxEmblem", Native_GetDropBoxEmblem);
	CreateNative("Cel_SpawnCollectible", Native_SpawnCollectible);
	CreateNative("Cel_GetCollectibleCount", Native_GetCollectibleCount);
	CreateNative("Cel_GetPlayerModelCount", Native_GetPlayerModelCount);
	CreateNative("Cel_GetPlayerModelInfo", Native_GetPlayerModelInfo);
	CreateNative("Cel_OwnsPlayerModel", Native_OwnsPlayerModel);
	CreateNative("Cel_GivePlayerModel", Native_GivePlayerModel);

	g_bLate = bLate;

	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "|CelMod| Collectibles",
	author = CEL_AUTHOR,
	description = "Emblems, hats, emblem drops and reward pickups.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	LoadTranslations("celmod.phrases");
	LoadTranslations("common.phrases");

	char sInvDir[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, g_sItemDB, sizeof(g_sItemDB), "data/celmod/collectibles.txt");

	BuildPath(Path_SM, sInvDir, sizeof(sInvDir), "data/celmod/inventory");

	if (!DirExists(sInvDir))
	{
		CreateDirectory(sInvDir, 511);
	}

	for (int i = 0; i <= MAXENTITIES; i++)
	{
		g_iEntItem[i] = -1;
		g_iRewardId[i] = -1;
	}

	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		ResetClient(i);
	}

	g_cvThirdPersonAimFix = CreateConVar("cm_thirdperson_aimfix", "1", "1 = keep the !thirdperson view following the player's aim. Set 0 if the view acts strangely.", _, true, 0.0, true, 1.0);
	g_cvBoothAlpha = CreateConVar("cm_powerbooth_alpha", "90", "How see-through the Power Booth is (0 invisible, 255 solid). Lower is harder to spot.", _, true, 0.0, true, 255.0);
	g_cvAura = CreateConVar("cm_emblem_aura", "1", "1 = an emblem held out shows its own aura around the player.", _, true, 0.0, true, 1.0);
	g_cvDropDelay = CreateConVar("cm_drop_delay", "3.0", "Seconds between one emblem box and the next in a drop.", _, true, 0.0, true, 60.0);
	g_cvDropCount = CreateConVar("cm_drop_count", "5", "Number of crates in one emblem drop.", _, true, 1.0, true, 30.0);
	g_cvNukeWrecks = CreateConVar("cm_nuke_wrecks_builds", "1", "1: the Nuke emblem unfreezes and scatters props where it lands, as on the original server. 0: builds are safe.", _, true, 0.0, true, 1.0);
	g_cvNukeMaxProps = CreateConVar("cm_nuke_max_props", "80", "Most props one Nuke can send flying, to limit lag.", _, true, 0.0);
	g_cvDigChance = CreateConVar("cm_dig_chance", "0.35", "Chance a shovel hit on the ground digs something up.", _, true, 0.0, true, 1.0);
	g_cvDigEmblemChance = CreateConVar("cm_dig_emblem_chance", "0.04", "Share of finds that are a Black or White emblem.", _, true, 0.0, true, 1.0);
	g_cvDigMoneyChance = CreateConVar("cm_dig_money_chance", "0.12", "Share of finds that are a money box. The rest is junk.", _, true, 0.0, true, 1.0);
	g_cvTrashMin = CreateConVar("cm_trash_reward_min", "10", "Least cleers for putting dug up junk in a trash can.", _, true, 0.0);
	g_cvTrashMax = CreateConVar("cm_trash_reward_max", "60", "Most cleers for putting dug up junk in a trash can.", _, true, 0.0);
	g_cvDigMoneyMin = CreateConVar("cm_dig_money_min", "100", "Least cleers in a dug up money box.", _, true, 0.0);
	g_cvDigMoneyMax = CreateConVar("cm_dig_money_max", "1500", "Most cleers in a dug up money box.", _, true, 0.0);
	g_cvUpgradeCost = CreateConVar("cm_upgrade_cost", "5", "How many of the same emblem the Power Booth takes to make one big emblem.", _, true, 2.0);
	g_cvDropInterval = CreateConVar("cm_drop_interval", "0", "Minutes between automatic emblem drops. 0 disables automatic drops.", _, true, 0.0);
	g_cvDropMinPlayers = CreateConVar("cm_drop_min_players", "2", "Players needed on the server for an automatic emblem drop.", _, true, 1.0);
	g_cvDropRadius = CreateConVar("cm_drop_radius", "1200.0", "How far from a player or land a crate can fall.", _, true, 64.0);
	g_cvGiftChance = CreateConVar("cm_emblem_gift_chance", "0.25", "Chance per build load that the one time free emblem appears, once the player is old enough.", _, true, 0.0, true, 1.0);
	g_cvGiftDays = CreateConVar("cm_emblem_gift_days", "3", "Days after a player's first build load before the free emblem can appear. -1 disables the free emblem.");

	g_cvShowSelf = CreateConVar("cm_emblem_show_self", "0", "Testing only: 1 also shows a player their own held emblem (it will float in their first person view).", _, true, 0.0, true, 1.0);

	AutoExecConfig(true, "celmod.collectibles");

	RegAdminCmd("v_delreward", Command_DelReward, ADMFLAG_SLAY, "|CelMod| Removes the reward pickup you are looking at.");
	RegAdminCmd("v_emblemdrop", Command_EmblemDrop, ADMFLAG_SLAY, "|CelMod| Starts an emblem drop.");
	RegAdminCmd("v_giveitem", Command_GiveItem, ADMFLAG_SLAY, "|CelMod| Gives an emblem or hat to a player.");
	RegAdminCmd("v_tune", Command_Tune, ADMFLAG_SLAY, "|CelMod| Sets where held emblems, celweps or your hat sit, and saves it.");
	RegAdminCmd("v_nudge", Command_Nudge, ADMFLAG_SLAY, "|CelMod| Moves where held emblems, celweps or your hat sit a little, and saves it.");
	RegConsoleCmd("v_speed", Command_Speed, "|CelMod| Turns changing your walking speed with the walk key (left Alt) on or off.");
	RegAdminCmd("v_eventemblem", Command_EventEmblem, ADMFLAG_SLAY, "|CelMod| Places an event emblem where you aim (end of a maze or parkour). Each player can only ever get it once.");
	RegAdminCmd("v_eventitem", Command_EventItem, ADMFLAG_SLAY, "|CelMod| Places an event emblem, hat or celwep where you aim. Each player can only ever get it once.");
	RegAdminCmd("v_reward", Command_Reward, ADMFLAG_SLAY, "|CelMod| Creates a reward pickup that gives an emblem or hat once per player.");
	RegConsoleCmd("v_firstperson", Command_FirstPerson, "|CelMod| Switches back to the first person view.");
	RegConsoleCmd("v_thirdperson", Command_ThirdPerson, "|CelMod| Switches to a third person view so you can see your emblem and hat.");
	RegAdminCmd("v_powerbooth", Command_PowerBooth, ADMFLAG_SLAY, "|CelMod| Moves the Power Booth to where you are looking.");
	RegAdminCmd("v_givemodel", Command_GiveModel, ADMFLAG_SLAY, "|CelMod| Gives a player model to a player.");
	RegAdminCmd("v_takemodel", Command_TakeModel, ADMFLAG_SLAY, "|CelMod| Takes a player model away from a player.");
	RegConsoleCmd("v_buymodel", Command_BuyModel, "|CelMod| Buys a player model.");
	RegConsoleCmd("v_playermodel", Command_PlayerModel, "|CelMod| Wears a player model you own, or goes back to your own (off).");
	RegConsoleCmd("v_playermodels", Command_PlayerModels, "|CelMod| Lists the player models and their prices.");
	RegConsoleCmd("v_weapon", Command_Weapon, "|CelMod| Spawns a weapon cel you own, or puts your celwep away (off).");
	RegConsoleCmd("v_weapons", Command_Inventory, "|CelMod| Lists the emblems, hats and weapons you own.");
	RegConsoleCmd("v_emblem", Command_Emblem, "|CelMod| Spawns an emblem you own, or disables your active emblem.");
	RegConsoleCmd("v_emblems", Command_Inventory, "|CelMod| Lists the emblems and hats you own.");
	RegConsoleCmd("v_hat", Command_Hat, "|CelMod| Spawns a hat you own, or takes off your hat.");
	RegConsoleCmd("v_hats", Command_Inventory, "|CelMod| Lists the emblems and hats you own.");
	RegConsoleCmd("v_inventory", Command_Inventory, "|CelMod| Lists the emblems and hats you own.");

	HookEvent("player_death", Event_Death, EventHookMode_Post);
	HookEvent("player_spawn", Event_Spawn, EventHookMode_Post);

	CreateTimer(0.2, Timer_Think, _, TIMER_REPEAT);
	CreateTimer(60.0, Timer_Minute, _, TIMER_REPEAT);

	if (g_bLate)
	{
		OnMapStart();

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnAllPluginsLoaded()
{
	g_bCustomGuns = LibraryExists("customguns");
}

public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, "customguns"))
	{
		g_bCustomGuns = true;
	}
}

// Celweps are taken by pressing E on their cels, one at a time, so Custom Guns' own weapon wheel and its default
// weapon are switched off. Its settings are set again after every config load, so they stay off.
public void OnConfigsExecuted()
{
	ConVar cvSetting = FindConVar("customguns_global_switcher");

	if (cvSetting != null)
	{
		cvSetting.SetBool(false);
	}

	cvSetting = FindConVar("customguns_default");

	if (cvSetting != null)
	{
		cvSetting.SetString("");
	}
}

public void OnLibraryRemoved(const char[] sName)
{
	if (StrEqual(sName, "customguns"))
	{
		g_bCustomGuns = false;
	}
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			RemoveHatEntity(i);
			RestoreWeapon(i);

			if (g_bSpeedManaged[i])
			{
				SetEntPropFloat(i, Prop_Data, "m_flLaggedMovementValue", 1.0);
			}
		}
	}
}

public void OnMapStart()
{
	Fx_Precache();

	GetCurrentMap(g_sMap, sizeof(g_sMap));

	PrecacheModel(GRAVGUN_WORLDMODEL, true);
	// The emblem box, with the emblem's own skin; a plain crate if the server does not have it.
	strcopy(g_sDropModel, sizeof(g_sDropModel), Cel_IsPhysicsModelComplete(DROPBOX_MODEL) ? DROPBOX_MODEL : DROPBOX_FALLBACK);

	PrecacheModel(g_sDropModel, true);

	PrecacheSound(SOUND_EQUIP, true);
	PrecacheSound(SOUND_UNEQUIP, true);
	PrecacheSound(SOUND_DENY, true);
	PrecacheSound(SOUND_FIRE, true);
	PrecacheSound(SOUND_ICE, true);
	PrecacheSound(SOUND_SHOCK, true);
	PrecacheSound(SOUND_HEAL, true);
	PrecacheSound(SOUND_QUAKE, true);
	PrecacheSound(SOUND_FLASH, true);
	PrecacheSound(SOUND_CANISTER, true);
	PrecacheModel("models/props_wasteland/antlionhill.mdl", true);
	PrecacheModel("models/error.mdl", true);

	for (int i = 1; i <= 4; i++)
	{
		char sCough[64];

		Format(sCough, sizeof(sCough), "ambient/voices/cough%d.wav", i);

		PrecacheSound(sCough, true);
	}
	PrecacheSound(SOUND_FLAME, true);
	PrecacheSound(SOUND_FIREBALL, true);
	PrecacheSound(SOUND_WATER, true);
	PrecacheSound(SOUND_STEAM, true);
	PrecacheSound(SOUND_BLINK, true);
	PrecacheSound(SOUND_DROP, true);
	PrecacheSound(SOUND_REWARD, true);

	for (int i = 0; i <= MAXENTITIES; i++)
	{
		g_bDropBox[i] = false;
		g_iEntItem[i] = -1;
		g_iRewardId[i] = -1;
		g_bRewardEvent[i] = false;
		g_bRewardLinked[i] = false;
	}

	g_iMinutesSinceDrop = 0;
	g_iBoothRef = INVALID_ENT_REFERENCE;

	// The HEV suit case is used when the game has it, the suit charger otherwise.
	strcopy(g_sBoothModel, sizeof(g_sBoothModel), FileExists(BOOTH_MODEL, true) ? BOOTH_MODEL : BOOTH_MODEL_FALLBACK);
	strcopy(g_sCanisterModel, sizeof(g_sCanisterModel), FileExists(CANISTER_MODEL, true) ? CANISTER_MODEL : "models/props_c17/oildrum001_explosive.mdl");

	PrecacheModel(g_sBoothModel, true);
	PrecacheModel(g_sCanisterModel, true);

	for (int i = 0; i < sizeof(g_sJunkModels); i++)
	{
		PrecacheModel(g_sJunkModels[i], true);
	}

	char sMoneyBox[PLATFORM_MAX_PATH];

	Cel_GetMoneyBoxModel(sMoneyBox, sizeof(sMoneyBox));

	PrecacheModel(sMoneyBox, true);
	PrecacheSound(SOUND_TRASH, true);
	PrecacheSound(SOUND_DIG, true);

	// After the Guess Booth (placed at 3 seconds), so it can be kept far away from it.
	g_bBoothPlaced = false;
	g_bBoothSpent = false;

	CreateTimer(8.0, Timer_SpawnBooth, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(5.0, Timer_BoothGuard, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	LoadItems();
	LoadRewards();

	CreateTimer(2.0, Timer_LinkRewards, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPutInServer(int iClient)
{
	ResetClient(iClient);

	g_bThirdPerson[iClient] = false;
	g_iWalkTier[iClient] = WALK_NORMAL;
	g_bWalkKeyOff[iClient] = false;

	SDKHook(iClient, SDKHook_OnTakeDamage, Hook_PlayerTakeDamage);

	Inv_Close(iClient);
	Inv_Open(iClient);

	if (!IsFakeClient(iClient))
	{
		CreateTimer(2.0, Timer_RestoreClient, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void OnClientDisconnect(int iClient)
{
	RemoveThirdPersonCamera(iClient);

	// The items stay in the player's ledger, so they can spawn them again next time.
	for (int i = MaxClients + 1; i <= MAXENTITIES; i++)
	{
		if (IsItemEntity(i) && Cel_CheckOwner(iClient, i))
		{
			AcceptEntityInput(i, "kill");
		}
	}

	RemoveHatEntity(iClient);
	RestoreWeapon(iClient);
	ResetClient(iClient);

	Inv_Close(iClient);
}

public void OnEntityDestroyed(int iEntity)
{
	if (iEntity > 0 && iEntity <= MAXENTITIES && g_iFireballOwner[iEntity] != 0)
	{
		FireballExploded(iEntity);
	}

	if (iEntity > 0 && iEntity <= MAXENTITIES)
	{
		g_iFireballOwner[iEntity] = 0;
		g_bDugUp[iEntity] = false;
		g_iMoneyBox[iEntity] = 0;
		g_bDropBox[iEntity] = false;
		g_iEntItem[iEntity] = -1;
		g_iRewardId[iEntity] = -1;
		g_bRewardEvent[iEntity] = false;
		g_bRewardLinked[iEntity] = false;
	}
}

//Forwards from other CelMod plugins:
public void Cel_OnEntityOwnerChanged(int iEntity, int iOldOwner, int iNewOwner)
{
	if (iEntity < 1 || iEntity > MAXENTITIES || g_iEntItem[iEntity] == -1 || g_bDropBox[iEntity] || g_iRewardId[iEntity] != -1)
	{
		return;
	}

	int iItem = g_iEntItem[iEntity];

	if (IsRealClient(iOldOwner))
	{
		SetOwned(iOldOwner, iItem, GetOwned(iOldOwner, iItem) - 1);

		if (GetOwned(iOldOwner, iItem) < 1)
		{
			if (g_iActiveEmblem[iOldOwner] == iItem)
			{
				SetActiveEmblem(iOldOwner, -1);
			}

			if (g_iActiveHat[iOldOwner] == iItem)
			{
				SetActiveHat(iOldOwner, -1);
			}

			if (g_iCelWepItem[iOldOwner] == iItem)
			{
				SetActiveCelWep(iOldOwner, -1);
			}

			if (g_bCelWepTaken[iOldOwner][iItem])
			{
				SetCelWepTaken(iOldOwner, iItem, false);
			}
		}
	}

	if (IsRealClient(iNewOwner))
	{
		SetOwned(iNewOwner, iItem, GetOwned(iNewOwner, iItem) + 1);
	}
}

public void Cel_OnBuildLoaded(int iClient, const char[] sSaveName)
{
	float fBottom[3], fOrigin[3], fTop[3];

	if (!IsRealClient(iClient) || g_cvGiftDays.IntValue < 0)
	{
		return;
	}

	if (Inv_GetInt(iClient, "emblem_gift") == 1)
	{
		return;
	}

	int iFirst = Inv_GetInt(iClient, "emblem_gift_first");

	if (iFirst < 1)
	{
		Inv_SetInt(iClient, "emblem_gift_first", GetTime());
		return;
	}

	if (GetTime() - iFirst < g_cvGiftDays.IntValue * 86400)
	{
		return;
	}

	if (GetRandomFloat(0.0, 1.0) > g_cvGiftChance.FloatValue)
	{
		return;
	}

	int iItem = PickRandomItem(KIND_EMBLEM);

	if (iItem == -1)
	{
		return;
	}

	Cel_GetLandPositions(iClient, 2, fBottom);
	Cel_GetLandPositions(iClient, 3, fTop);

	if (Cel_IsLandCreated(iClient))
	{
		fOrigin[0] = GetRandomFloat(fBottom[0] < fTop[0] ? fBottom[0] : fTop[0], fBottom[0] < fTop[0] ? fTop[0] : fBottom[0]);
		fOrigin[1] = GetRandomFloat(fBottom[1] < fTop[1] ? fBottom[1] : fTop[1], fBottom[1] < fTop[1] ? fTop[1] : fBottom[1]);
		fOrigin[2] = (fBottom[2] < fTop[2] ? fBottom[2] : fTop[2]) + 48.0;
	} else {
		Cel_GetCrosshairHitOrigin(iClient, fOrigin);

		fOrigin[2] += 48.0;
	}

	int iEntity = SpawnItemEntity(iClient, iItem, fOrigin, g_fZero);

	if (iEntity == -1)
	{
		return;
	}

	Cel_DropEntityToFloor(iEntity);

	SetOwned(iClient, iItem, GetOwned(iClient, iItem) + 1);

	Inv_SetInt(iClient, "emblem_gift", 1);

	Cel_PrintToChat(iClient, "Something new has appeared in your build... a {green}%s{default} emblem! Press {green}E{default} on it to enable it.", g_Items[iItem].sName);
}

//Commands:
public Action Command_Emblem(int iClient, int iArgs)
{
	return HandleItemCommand(iClient, iArgs, KIND_EMBLEM);
}

public Action Command_Hat(int iClient, int iArgs)
{
	return HandleItemCommand(iClient, iArgs, KIND_HAT);
}

public Action Command_Weapon(int iClient, int iArgs)
{
	return HandleItemCommand(iClient, iArgs, KIND_WEAPON);
}

int KindFromName(const char[] sKind)
{
	if (StrEqual(sKind, "hat", false)) return KIND_HAT;
	if (StrEqual(sKind, "weapon", false) || StrEqual(sKind, "celwep", false)) return KIND_WEAPON;

	return KIND_EMBLEM;
}

Action HandleItemCommand(int iClient, int iArgs, int iKind)
{
	char sArg[64];
	float fAngles[3], fOrigin[3];

	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]%s{default} <name/off>", g_sKindName[iKind]);

		PrintInventory(iClient, iKind);

		return Plugin_Handled;
	}

	GetCmdArg(1, sArg, sizeof(sArg));

	if (StrEqual(sArg, "off", false) || StrEqual(sArg, "none", false))
	{
		if (iKind == KIND_EMBLEM)
		{
			SetActiveEmblem(iClient, -1);

			Cel_ReplyToCommand(iClient, "Your emblem has been disabled.");
		} else if (iKind == KIND_WEAPON)
		{
			SetActiveCelWep(iClient, -1);

			Cel_ReplyToCommand(iClient, "Your celwep has been put away.");
		} else {
			SetActiveHat(iClient, -1);

			Cel_ReplyToCommand(iClient, "You took your hat off.");
		}

		return Plugin_Handled;
	}

	int iItem = FindItem(iKind, sArg);

	if (iItem == -1)
	{
		Cel_ReplyToCommand(iClient, "There is no %s called {green}%s{default}.", g_sKindName[iKind], sArg);
		return Plugin_Handled;
	}

	int iOwned = GetOwned(iClient, iItem);

	if (iOwned < 1)
	{
		Cel_ReplyToCommand(iClient, "You do not own a {green}%s{default} %s.", g_Items[iItem].sName, g_sKindName[iKind]);
		return Plugin_Handled;
	}

	if (CountSpawned(iClient, iItem) >= iOwned)
	{
		Cel_ReplyToCommand(iClient, "Every {green}%s{default} %s you own is already spawned.", g_Items[iItem].sName, g_sKindName[iKind]);
		return Plugin_Handled;
	}

	Cel_GetCrosshairHitOrigin(iClient, fOrigin);

	GetClientAbsAngles(iClient, fAngles);

	fAngles[0] = 0.0;
	fAngles[2] = 0.0;

	int iEntity = SpawnItemEntity(iClient, iItem, fOrigin, fAngles);

	if (iEntity == -1)
	{
		Cel_ReplyToCommand(iClient, "The %s could not be spawned.", g_sKindName[iKind]);
		return Plugin_Handled;
	}

	Cel_FixSpawnPosition(iEntity, fOrigin);

	Cel_ReplyToCommand(iClient, "Spawned your {green}%s{default} %s. Press {green}E{default} on it to %s.", g_Items[iItem].sName, g_sKindName[iKind], iKind == KIND_EMBLEM ? "enable it" : (iKind == KIND_HAT ? "wear it" : "take it"));

	return Plugin_Handled;
}

public Action Command_ThirdPerson(int iClient, int iArgs)
{
	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	// Typing it again switches back.
	SetThirdPerson(iClient, !g_bThirdPerson[iClient]);

	Cel_ReplyToCommand(iClient, g_bThirdPerson[iClient] ? "Third person view enabled. Type {green}[tag]firstperson{default} to go back." : "First person view enabled.");

	return Plugin_Handled;
}

public Action Command_FirstPerson(int iClient, int iArgs)
{
	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	SetThirdPerson(iClient, false);

	Cel_ReplyToCommand(iClient, "First person view enabled.");

	return Plugin_Handled;
}

// The camera is moved behind the player by putting them in an observer mode with no target.
void SetThirdPerson(int iClient, bool bEnable)
{
	g_bThirdPerson[iClient] = bEnable;

	if (!IsClientInGame(iClient) || !IsPlayerAlive(iClient))
	{
		RemoveThirdPersonCamera(iClient);
		return;
	}

	if (bEnable)
	{
		// The death camera observer mode: the game itself draws the view behind the player, smoothly, and draws the
		// player's own model (and so their hat and held emblem).
		SetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget", 0);
		SetEntProp(iClient, Prop_Send, "m_iObserverMode", 1);
		SetEntProp(iClient, Prop_Send, "m_bDrawViewmodel", 0);
		SetEntProp(iClient, Prop_Send, "m_iFOV", 110);
	} else {
		RemoveThirdPersonCamera(iClient);

		SetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget", -1);
		SetEntProp(iClient, Prop_Send, "m_iObserverMode", 0);
		SetEntProp(iClient, Prop_Send, "m_bDrawViewmodel", 1);
		SetEntProp(iClient, Prop_Send, "m_iFOV", 0);
	}
}

void RemoveThirdPersonCamera(int iClient)
{
	int iCamera = EntRefToEntIndex(g_iCameraRef[iClient]);

	g_iCameraRef[iClient] = INVALID_ENT_REFERENCE;

	if (iCamera != INVALID_ENT_REFERENCE && iCamera > MaxClients)
	{
		if (IsClientInGame(iClient))
		{
			SetClientViewEntity(iClient, iClient);
		}

		AcceptEntityInput(iCamera, "kill");
	}
}

// The death camera turns the view towards the "killer" a while after the death time, and for a living player that is
// the player themself, so the view stops following the aim. Keeping the death time at "just now" every frame keeps
// the camera on the player's own aim. (cm_thirdperson_aimfix 0 turns this off.)
void UpdateThirdPersonCameras()
{
	if (!g_cvThirdPersonAimFix.BoolValue)
	{
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bThirdPerson[i] && IsClientInGame(i) && IsPlayerAlive(i) && HasEntProp(i, Prop_Send, "m_flDeathTime"))
		{
			SetEntPropFloat(i, Prop_Send, "m_flDeathTime", GetGameTime());
		}
	}
}

public Action Command_Inventory(int iClient, int iArgs)
{
	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	PrintInventory(iClient, KIND_EMBLEM);
	PrintInventory(iClient, KIND_HAT);
	PrintInventory(iClient, KIND_WEAPON);

	return Plugin_Handled;
}

// Where held models and hats sit is tuned in game and saved to data/celmod/tuning.txt, which overrides
// collectibles.txt. Held models are tuned per model (every emblem with the same model is held the same way),
// hats per hat.
void TuningPath(char[] sPath, int iMaxLength)
{
	BuildPath(Path_SM, sPath, iMaxLength, "data/celmod/tuning.txt");
}

void ApplyTuning()
{
	char sKey[PLATFORM_MAX_PATH], sPath[PLATFORM_MAX_PATH];

	TuningPath(sPath, sizeof(sPath));

	KeyValues kvTuning = new KeyValues("Tuning");

	if (!kvTuning.ImportFromFile(sPath))
	{
		delete kvTuning;

		return;
	}

	for (int i = 0; i < g_iItemCount; i++)
	{
		if (g_Items[i].iKind == KIND_HAT)
		{
			Format(sKey, sizeof(sKey), "hat %s", g_Items[i].sId);

			if (kvTuning.JumpToKey(sKey, false))
			{
				kvTuning.GetVector("offset", g_Items[i].fOffset, g_Items[i].fOffset);
				kvTuning.GetVector("angles", g_Items[i].fAngles, g_Items[i].fAngles);
				kvTuning.Rewind();
			}

			continue;
		}

		HeldModel(i, sKey, sizeof(sKey));

		if (kvTuning.JumpToKey(sKey, false))
		{
			kvTuning.GetVector("offset", g_Items[i].fHandOffset, g_Items[i].fHandOffset);
			kvTuning.GetVector("angles", g_Items[i].fHandAngles, g_Items[i].fHandAngles);
			kvTuning.Rewind();
		}
	}

	delete kvTuning;
}

// The model an item is shown with in the hand.
void HeldModel(int iItem, char[] sModel, int iMaxLength)
{
	strcopy(sModel, iMaxLength, g_Items[iItem].sHandModel[0] != '\0' ? g_Items[iItem].sHandModel : g_Items[iItem].sModel);
}

// Sets the position and angles of what the player holds (bHat false) or wears, saves them, and shows the change.
void SetTuning(int iClient, bool bHat, float fOffset[3], float fAngles[3])
{
	char sKey[PLATFORM_MAX_PATH], sModel[PLATFORM_MAX_PATH], sPath[PLATFORM_MAX_PATH];

	int iItem = bHat ? g_iActiveHat[iClient] : g_iHandItem[iClient];

	if (bHat)
	{
		g_Items[iItem].fOffset = fOffset;
		g_Items[iItem].fAngles = fAngles;

		Format(sKey, sizeof(sKey), "hat %s", g_Items[iItem].sId);
	} else {
		HeldModel(iItem, sModel, sizeof(sModel));

		for (int i = 0; i < g_iItemCount; i++)
		{
			char sOther[PLATFORM_MAX_PATH];

			if (g_Items[i].iKind == KIND_HAT)
			{
				continue;
			}

			HeldModel(i, sOther, sizeof(sOther));

			if (StrEqual(sOther, sModel, false))
			{
				g_Items[i].fHandOffset = fOffset;
				g_Items[i].fHandAngles = fAngles;
			}
		}

		strcopy(sKey, sizeof(sKey), sModel);
	}

	TuningPath(sPath, sizeof(sPath));

	KeyValues kvTuning = new KeyValues("Tuning");

	kvTuning.ImportFromFile(sPath);
	kvTuning.JumpToKey(sKey, true);
	kvTuning.SetVector("offset", fOffset);
	kvTuning.SetVector("angles", fAngles);
	kvTuning.Rewind();

	if (!kvTuning.ExportToFile(sPath))
	{
		LogError("|CelMod| Could not write '%s'.", sPath);
	}

	delete kvTuning;

	// Everyone holding or wearing it sees the change straight away.
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}

		if (bHat && g_iActiveHat[i] == iItem)
		{
			CreateHatEntity(i);
		} else if (!bHat && g_bHeldShown[i])
		{
			RestoreWeapon(i);
		}
	}

	Cel_ReplyToCommand(iClient, "Saved: offset {green}%.1f %.1f %.1f{default}  angles {green}%.0f %.0f %.0f{default}", fOffset[0], fOffset[1], fOffset[2], fAngles[0], fAngles[1], fAngles[2]);
}

// Checks there is something to tune and fills in its current values. Returns false with a message otherwise.
bool GetTuning(int iClient, bool bHat, float fOffset[3], float fAngles[3])
{
	if (bHat)
	{
		if (g_iActiveHat[iClient] == -1)
		{
			Cel_ReplyToCommand(iClient, "Put a hat on first.");
			return false;
		}

		fOffset = g_Items[g_iActiveHat[iClient]].fOffset;
		fAngles = g_Items[g_iActiveHat[iClient]].fAngles;

		return true;
	}

	if (!g_bHeldShown[iClient] || g_iHandItem[iClient] == -1)
	{
		Cel_ReplyToCommand(iClient, "Hold your gravity gun with an emblem enabled, or a celwep, first.");
		return false;
	}

	fOffset = g_Items[g_iHandItem[iClient]].fHandOffset;
	fAngles = g_Items[g_iHandItem[iClient]].fHandAngles;

	return true;
}

// !tune <hand/hat> <forward> <left> <up> <pitch> <yaw> <roll>: sets every value at once.
public Action Command_Tune(int iClient, int iArgs)
{
	char sArg[16];
	float fAngles[3], fOffset[3];

	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	if (iArgs < 7)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]tune{default} <hand/hat> <forward> <left> <up> <pitch> <yaw> <roll>. To move a little at a time: {green}[tag]nudge{default} <hand/hat> <forward/left/up/pitch/yaw/roll> <amount>");
		return Plugin_Handled;
	}

	GetCmdArg(1, sArg, sizeof(sArg));

	bool bHat = StrEqual(sArg, "hat", false);

	if (!GetTuning(iClient, bHat, fOffset, fAngles))
	{
		return Plugin_Handled;
	}

	for (int i = 0; i < 6; i++)
	{
		GetCmdArg(i + 2, sArg, sizeof(sArg));

		if (i < 3)
		{
			fOffset[i] = StringToFloat(sArg);
		} else {
			fAngles[i - 3] = StringToFloat(sArg);
		}
	}

	SetTuning(iClient, bHat, fOffset, fAngles);

	return Plugin_Handled;
}

// !nudge <hand/hat> <forward/left/up/pitch/yaw/roll> <amount>: moves one value by an amount.
public Action Command_Nudge(int iClient, int iArgs)
{
	static const char sAxes[][] = { "forward", "left", "up", "pitch", "yaw", "roll" };
	char sAmount[16], sAxis[16], sWhat[16];
	float fAngles[3], fOffset[3];

	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	if (iArgs < 3)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]nudge{default} <hand/hat> <forward/left/up/pitch/yaw/roll> <amount>, e.g. {green}[tag]nudge hand up 2{default} or {green}[tag]nudge hand yaw -10{default}. Use {green}[tag]thirdperson{default} to watch.");
		return Plugin_Handled;
	}

	GetCmdArg(1, sWhat, sizeof(sWhat));
	GetCmdArg(2, sAxis, sizeof(sAxis));
	GetCmdArg(3, sAmount, sizeof(sAmount));

	bool bHat = StrEqual(sWhat, "hat", false);

	if (!GetTuning(iClient, bHat, fOffset, fAngles))
	{
		return Plugin_Handled;
	}

	for (int i = 0; i < sizeof(sAxes); i++)
	{
		if (!StrEqual(sAxis, sAxes[i], false))
		{
			continue;
		}

		if (i < 3)
		{
			fOffset[i] += StringToFloat(sAmount);
		} else {
			fAngles[i - 3] += StringToFloat(sAmount);
		}

		SetTuning(iClient, bHat, fOffset, fAngles);

		return Plugin_Handled;
	}

	Cel_ReplyToCommand(iClient, "Choose one of: forward, left, up, pitch, yaw, roll.");

	return Plugin_Handled;
}

public Action Command_GiveItem(int iClient, int iArgs)
{
	char sId[64], sKind[32], sTarget[MAX_NAME_LENGTH];

	if (iArgs < 3)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]giveitem{default} <player> <emblem/hat> <name>");
		return Plugin_Handled;
	}

	GetCmdArg(1, sTarget, sizeof(sTarget));
	GetCmdArg(2, sKind, sizeof(sKind));
	GetCmdArg(3, sId, sizeof(sId));

	int iTarget = FindTarget(iClient, sTarget, true, false);

	if (iTarget == -1)
	{
		return Plugin_Handled;
	}

	int iItem = FindItem(KindFromName(sKind), sId);

	if (iItem == -1)
	{
		Cel_ReplyToCommand(iClient, "There is no %s called {green}%s{default}.", sKind, sId);
		return Plugin_Handled;
	}

	GiveItem(iTarget, iItem);

	Cel_ReplyToCommand(iClient, "Gave a {green}%s{default} %s to {green}%N{default}.", g_Items[iItem].sName, g_sKindName[g_Items[iItem].iKind], iTarget);

	return Plugin_Handled;
}

public Action Command_EmblemDrop(int iClient, int iArgs)
{
	char sCount[16];
	int iCount = g_cvDropCount.IntValue;

	if (iArgs > 0)
	{
		GetCmdArg(1, sCount, sizeof(sCount));

		iCount = StringToInt(sCount);

		if (iCount < 1) iCount = 1;
		if (iCount > 30) iCount = 30;
	}

	int iSpawned = StartDrop(iCount);

	if (iSpawned < 1)
	{
		Cel_ReplyToCommand(iClient, "No crates could be dropped. There must be a player alive with open sky above them.");
	}

	return Plugin_Handled;
}

// An event item (emblem, hat or celwep): a fixed object at the end of a maze or parkour course (inside an event
// area made with !zone). Every player can press E on it to claim the item, once and only once ever per item.
public Action Command_EventEmblem(int iClient, int iArgs)
{
	char sId[64];

	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]eventemblem{default} <emblem>, or {green}[tag]eventitem{default} <emblem/hat/weapon> <name>");
		return Plugin_Handled;
	}

	GetCmdArg(1, sId, sizeof(sId));

	PlaceEventItem(iClient, KIND_EMBLEM, sId);

	return Plugin_Handled;
}

public Action Command_EventItem(int iClient, int iArgs)
{
	char sId[64], sKind[32];

	if (iArgs < 2)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]eventitem{default} <emblem/hat/weapon> <name> (placed where you aim), or {green}[tag]eventitem link{default} <emblem/hat/weapon> <name> (makes the map object you look at claimable). {green}[tag]delreward{default} removes either.");
		return Plugin_Handled;
	}

	GetCmdArg(1, sKind, sizeof(sKind));
	GetCmdArg(2, sId, sizeof(sId));

	// Link: a map's own entity (a prop, button, door or other brush entity) becomes the claimable object.
	if (StrEqual(sKind, "link", false))
	{
		if (iArgs < 3)
		{
			Cel_ReplyToCommand(iClient, "Usage: {green}[tag]eventitem link{default} <emblem/hat/weapon> <name>, while looking at a map object.");
			return Plugin_Handled;
		}

		strcopy(sKind, sizeof(sKind), sId);

		GetCmdArg(3, sId, sizeof(sId));

		if (!StrEqual(sKind, "emblem", false) && !StrEqual(sKind, "hat", false) && !StrEqual(sKind, "weapon", false) && !StrEqual(sKind, "celwep", false))
		{
			Cel_ReplyToCommand(iClient, "The kind must be {green}emblem{default}, {green}hat{default} or {green}weapon{default}.");
			return Plugin_Handled;
		}

		LinkEventItem(iClient, KindFromName(sKind), sId);

		return Plugin_Handled;
	}

	if (!StrEqual(sKind, "emblem", false) && !StrEqual(sKind, "hat", false) && !StrEqual(sKind, "weapon", false) && !StrEqual(sKind, "celwep", false))
	{
		Cel_ReplyToCommand(iClient, "The kind must be {green}emblem{default}, {green}hat{default} or {green}weapon{default}.");
		return Plugin_Handled;
	}

	PlaceEventItem(iClient, KindFromName(sKind), sId);

	return Plugin_Handled;
}

void PlaceEventItem(int iClient, int iKind, const char[] sName)
{
	float fOrigin[3];

	if (!IsRealClient(iClient))
	{
		return;
	}

	int iItem = FindItem(iKind, sName);

	if (iItem == -1 || g_Items[iItem].bIsBig)
	{
		Cel_ReplyToCommand(iClient, "There is no %s called {green}%s{default}.", g_sKindName[iKind], sName);
		return;
	}

	Cel_GetCrosshairHitOrigin(iClient, fOrigin);

	fOrigin[2] += 24.0;

	int iId = SaveReward(-1, iKind, g_Items[iItem].sId, fOrigin, true);

	int iEntity = SpawnRewardEntity(iId, iKind, g_Items[iItem].sId, fOrigin);

	if (iEntity == -1)
	{
		Cel_ReplyToCommand(iClient, "The event %s could not be spawned.", g_sKindName[iKind]);
		return;
	}

	g_bRewardEvent[iEntity] = true;

	Cel_ReplyToCommand(iClient, "Placed event %s {green}#%d{default} ({green}%s{default}). Every player can press E on it to get it, once and only once.", g_sKindName[iKind], iId, g_Items[iItem].sName);

	if (ZoneTypeAt(fOrigin) != CEL_ZONE_EVENT)
	{
		Cel_ReplyToCommand(iClient, "Tip: put the course inside an event area ({green}[tag]zone{default}) so nobody can fly, phase or blink to it.");
	}

	if (g_Items[iItem].iWeight > 0)
	{
		Cel_ReplyToCommand(iClient, "Tip: the {green}%s{default} can also come from drops and random rewards. Give it {green}\"dropweight\" \"0\"{default} in collectibles.txt to make it event only.", g_Items[iItem].sName);
	}
}

void LinkEventItem(int iClient, int iKind, const char[] sName)
{
	char sClassname[64];

	if (!IsRealClient(iClient))
	{
		return;
	}

	int iItem = FindItem(iKind, sName);

	if (iItem == -1 || g_Items[iItem].bIsBig)
	{
		Cel_ReplyToCommand(iClient, "There is no %s called {green}%s{default}.", g_sKindName[iKind], sName);
		return;
	}

	int iTarget = GetClientAimTarget(iClient, false);

	// Only the map's own entities: they carry the Hammer ID the map was built with, which is the same every time
	// the map loads. Static props and world brushes are part of the world and can't be used.
	if (iTarget <= MaxClients || iTarget > MAXENTITIES || !IsValidEntity(iTarget) || !HasEntProp(iTarget, Prop_Data, "m_iHammerID") || GetEntProp(iTarget, Prop_Data, "m_iHammerID") < 1)
	{
		Cel_ReplyToCommand(iClient, "Look at one of the map's own entities (a prop_dynamic or prop_physics prop, a button, a door or another brush entity). Static props and plain walls are part of the world and can't be used.");
		return;
	}

	if (Cel_IsEntity(iTarget) || g_iRewardId[iTarget] != -1)
	{
		Cel_ReplyToCommand(iClient, "That is already a CelMod entity or a claimable item.");
		return;
	}

	int iHammer = GetEntProp(iTarget, Prop_Data, "m_iHammerID");
	float fOrigin[3];

	GetEntPropVector(iTarget, Prop_Data, "m_vecAbsOrigin", fOrigin);

	int iId = SaveReward(-1, iKind, g_Items[iItem].sId, fOrigin, true, iHammer);

	MarkLinked(iTarget, iId, iItem);

	GetEntityClassname(iTarget, sClassname, sizeof(sClassname));

	Cel_ReplyToCommand(iClient, "This {green}%s{default} (Hammer ID %d) now gives the event %s {green}%s{default} (#%d). Every player can press E on it once and only once.", sClassname, iHammer, g_sKindName[iKind], g_Items[iItem].sName, iId);

	if (ZoneTypeAt(fOrigin) != CEL_ZONE_EVENT)
	{
		Cel_ReplyToCommand(iClient, "Tip: put the course inside an event area ({green}[tag]zone{default}) so nobody can fly, phase or blink to it.");
	}
}

void MarkLinked(int iEntity, int iId, int iItem)
{
	g_bDropBox[iEntity] = false;
	g_iEntItem[iEntity] = iItem;
	g_iRewardId[iEntity] = iId;
	g_bRewardEvent[iEntity] = true;
	g_bRewardLinked[iEntity] = true;
}

// Attaches linked event items to the map's entities, by Hammer ID, once they have all spawned.
public Action Timer_LinkRewards(Handle hTimer)
{
	char sId[64], sKind[32], sSection[16];

	if (!FileExists(g_sRewardDB))
	{
		return Plugin_Stop;
	}

	KeyValues kvRewards = new KeyValues("Rewards");

	if (kvRewards.ImportFromFile(g_sRewardDB) && kvRewards.GotoFirstSubKey())
	{
		do
		{
			int iHammer = kvRewards.GetNum("hammerid", 0);

			if (iHammer < 1)
			{
				continue;
			}

			kvRewards.GetSectionName(sSection, sizeof(sSection));
			kvRewards.GetString("kind", sKind, sizeof(sKind), "emblem");
			kvRewards.GetString("item", sId, sizeof(sId), "");

			int iItem = FindItem(KindFromName(sKind), sId);
			int iEntity = FindByHammerId(iHammer);

			if (iItem == -1 || iEntity == -1)
			{
				LogError("|CelMod| Linked event item #%s on %s: %s.", sSection, g_sMap, iItem == -1 ? "unknown item" : "no map entity with that Hammer ID");
				continue;
			}

			MarkLinked(iEntity, StringToInt(sSection), iItem);
		}
		while (kvRewards.GotoNextKey());
	}

	delete kvRewards;

	return Plugin_Stop;
}

int FindByHammerId(int iHammer)
{
	for (int i = MaxClients + 1; i <= MAXENTITIES && i < GetMaxEntities(); i++)
	{
		if (IsValidEntity(i) && HasEntProp(i, Prop_Data, "m_iHammerID") && GetEntProp(i, Prop_Data, "m_iHammerID") == iHammer)
		{
			return i;
		}
	}

	return -1;
}

public int Native_GetRewardLabel(Handle hPlugin, int iNumParams)
{
	char sLabel[128];
	int iEntity = GetNativeCell(1);

	if (iEntity <= MaxClients || iEntity > MAXENTITIES || g_iRewardId[iEntity] == -1 || !IsValidEntity(iEntity))
	{
		return false;
	}

	int iItem = g_iEntItem[iEntity];

	if (g_bRewardEvent[iEntity] && iItem >= 0)
	{
		Format(sLabel, sizeof(sLabel), "Reward: %s", g_Items[iItem].sName);
	} else if (iItem >= 0)
	{
		Format(sLabel, sizeof(sLabel), "Reward: %s", g_Items[iItem].sName);
	} else {
		Format(sLabel, sizeof(sLabel), "Reward: a random %s", g_sKindName[-(iItem + 2)]);
	}

	SetNativeString(2, sLabel, GetNativeCell(3));

	return true;
}

// Event emblems glow and send up rings, so the prize at the end of a course stands out.
void ThinkEventEmblems()
{
	float fOrigin[3], fMins[3], fMaxs[3];
	int iColor[4];

	for (int iEntity = MaxClients + 1; iEntity <= MAXENTITIES && iEntity < GetMaxEntities(); iEntity++)
	{
		if (g_iRewardId[iEntity] == -1 || !g_bRewardEvent[iEntity] || g_iEntItem[iEntity] < 0 || !IsValidEntity(iEntity))
		{
			continue;
		}

		int iItem = g_iEntItem[iEntity];

		// The middle of the object: brush entities often have their origin somewhere else entirely.
		GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", fOrigin);

		if (HasEntProp(iEntity, Prop_Send, "m_vecMins"))
		{
			GetEntPropVector(iEntity, Prop_Send, "m_vecMins", fMins);
			GetEntPropVector(iEntity, Prop_Send, "m_vecMaxs", fMaxs);

			for (int k = 0; k < 3; k++)
			{
				fOrigin[k] += (fMins[k] + fMaxs[k]) * 0.5;
			}
		}

		iColor[0] = g_Items[iItem].iBeamColor[0];
		iColor[1] = g_Items[iItem].iBeamColor[1];
		iColor[2] = g_Items[iItem].iBeamColor[2];
		iColor[3] = 255;

		fOrigin[2] -= 16.0;

		Fx_Ring(fOrigin, 20.0, 60.0, g_iBmPhys, 4.0, 1.0, 0.0, iColor);

		fOrigin[2] += 16.0;

		Fx_Glow(fOrigin, g_iFxSoftGlow, 0.6, 1.0, 140);
	}
}

// Which kind of admin made area a point is in, when the zones plugin is loaded.
int ZoneTypeAt(float fPos[3])
{
	if (GetFeatureStatus(FeatureType_Native, "Cel_GetZoneType") != FeatureStatus_Available)
	{
		return CEL_ZONE_NONE;
	}

	return Cel_GetZoneType(fPos);
}

bool IsZoneExempt(int iClient)
{
	return CheckCommandAccess(iClient, "celmod_zone_exempt", ADMFLAG_SLAY, true);
}

// True when a point is inside an event or restricted area that the player is not allowed to get into by power.
bool ZoneBlocks(int iClient, float fPos[3])
{
	return (!IsZoneExempt(iClient) && ZoneTypeAt(fPos) != CEL_ZONE_NONE);
}

public Action Command_Reward(int iClient, int iArgs)
{
	char sId[64], sKind[32];
	float fOrigin[3];
	int iItem = -1, iKind;

	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	if (iArgs < 2)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]reward{default} <emblem/hat> <name/random>");
		return Plugin_Handled;
	}

	GetCmdArg(1, sKind, sizeof(sKind));
	GetCmdArg(2, sId, sizeof(sId));

	iKind = KindFromName(sKind);

	if (!StrEqual(sId, "random", false))
	{
		iItem = FindItem(iKind, sId);

		if (iItem == -1)
		{
			Cel_ReplyToCommand(iClient, "There is no %s called {green}%s{default}.", sKind, sId);
			return Plugin_Handled;
		}

		strcopy(sId, sizeof(sId), g_Items[iItem].sId);
	}

	Cel_GetCrosshairHitOrigin(iClient, fOrigin);

	fOrigin[2] += 24.0;

	int iId = SaveReward(-1, iKind, sId, fOrigin);

	if (SpawnRewardEntity(iId, iKind, sId, fOrigin) == -1)
	{
		Cel_ReplyToCommand(iClient, "The reward pickup could not be spawned.");
		return Plugin_Handled;
	}

	Cel_ReplyToCommand(iClient, "Created reward pickup {green}#%d{default} (%s: %s) on this map.", iId, g_sKindName[iKind], sId);

	return Plugin_Handled;
}

public Action Command_DelReward(int iClient, int iArgs)
{
	char sKey[16];

	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	int iEntity = GetClientAimTarget(iClient, false);

	if (iEntity < 1 || iEntity > MAXENTITIES || g_iRewardId[iEntity] == -1)
	{
		Cel_ReplyToCommand(iClient, "You are not looking at a reward pickup.");
		return Plugin_Handled;
	}

	int iId = g_iRewardId[iEntity];

	KeyValues kvRewards = new KeyValues("Rewards");

	kvRewards.ImportFromFile(g_sRewardDB);

	IntToString(iId, sKey, sizeof(sKey));

	if (kvRewards.JumpToKey(sKey, false))
	{
		kvRewards.DeleteThis();
		kvRewards.Rewind();
		kvRewards.ExportToFile(g_sRewardDB);
	}

	delete kvRewards;

	// A map entity that was linked stays in the map; it just stops being claimable.
	if (g_bRewardLinked[iEntity])
	{
		g_iRewardId[iEntity] = -1;
		g_iEntItem[iEntity] = -1;
		g_bRewardEvent[iEntity] = false;
		g_bRewardLinked[iEntity] = false;

		Cel_ReplyToCommand(iClient, "Unlinked event item {green}#%d{default} from this map entity.", iId);

		return Plugin_Handled;
	}

	AcceptEntityInput(iEntity, "kill");

	Cel_ReplyToCommand(iClient, "Removed reward pickup {green}#%d{default}.", iId);

	return Plugin_Handled;
}

//Events:
public Action Event_Death(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(eEvent.GetInt("userid"));

	if (iClient > 0)
	{
		RemoveHatEntity(iClient);
		RestoreWeapon(iClient);
		RemoveThirdPersonCamera(iClient);

		g_bHoldingGravGun[iClient] = false;
		g_bPhasing[iClient] = false;
		g_fFrozenUntil[iClient] = 0.0;

		if (g_bCloaked[iClient] || g_bFrozenTint[iClient])
		{
			g_bCloaked[iClient] = false;
			g_bFrozenTint[iClient] = false;

			SetEntityRenderMode(iClient, RENDER_NORMAL);
			SetEntityRenderColor(iClient, 255, 255, 255, 255);
		}
	}

	return Plugin_Continue;
}

public Action Event_Spawn(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	int iUserId = eEvent.GetInt("userid");

	if (GetClientOfUserId(iUserId) > 0)
	{
		CreateTimer(0.3, Timer_ApplyHat, iUserId, TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Continue;
}

//Hooks:
public void Hook_ItemUse(int iEntity, int iActivator, int iCaller, UseType utType, float fValue)
{
	if (iActivator < 1 || iActivator > MaxClients || !IsClientInGame(iActivator) || g_iEntItem[iEntity] == -1)
	{
		return;
	}

	int iItem = g_iEntItem[iEntity];

	if (!Cel_CheckOwner(iActivator, iEntity))
	{
		EmitSoundToClient(iActivator, SOUND_DENY);

		if (Cel_IsEntityForSale(iEntity))
		{
			Cel_PrintToChat(iActivator, "This {green}%s{default} %s is for sale for {green}%d CL{default}. Type {green}!buy{default} while looking at it.", g_Items[iItem].sName, g_sKindName[g_Items[iItem].iKind], Cel_GetEntityPrice(iEntity));
		} else {
			Cel_PrintToChat(iActivator, "This %s does not belong to you.", g_sKindName[g_Items[iItem].iKind]);
		}

		return;
	}

	if (Cel_IsLocked(iEntity))
	{
		return;
	}

	// One celwep at a time: taking another puts the current one back, and pressing E on the one held puts it back.
	if (g_Items[iItem].iKind == KIND_WEAPON && UsesCustomGun(iItem))
	{
		if (g_bCelWepTaken[iActivator][iItem])
		{
			SetCelWepTaken(iActivator, iItem, false);

			EmitSoundToAll(SOUND_UNEQUIP, iEntity);

			Cel_PrintToChat(iActivator, "You put your {green}%s{default} back.", g_Items[iItem].sName);

			return;
		}

		for (int i = 0; i < g_iItemCount; i++)
		{
			if (i != iItem && g_bCelWepTaken[iActivator][i])
			{
				char sKey[64];

				g_bCelWepTaken[iActivator][i] = false;

				Format(sKey, sizeof(sKey), "taken_%s", g_Items[i].sId);

				Inv_SetInt(iActivator, sKey, 0);
			}
		}

		// The old celwep leaves the inventory before the new one goes in.
		if (IsPlayerAlive(iActivator))
		{
			CG_ClearInventory(iActivator);
		}

		SetCelWepTaken(iActivator, iItem, true);

		EmitSoundToAll(SOUND_EQUIP, iEntity);

		Cel_PrintToChat(iActivator, "You took your {green}%s{default}. Press {green}E{default} on it again to put it back.", g_Items[iItem].sName);

		return;
	}

	if (g_Items[iItem].iKind == KIND_WEAPON)
	{
		if (g_iCelWepItem[iActivator] == iItem)
		{
			SetActiveCelWep(iActivator, -1);

			EmitSoundToAll(SOUND_UNEQUIP, iEntity);

			Cel_PrintToChat(iActivator, "You put your {green}%s{default} away.", g_Items[iItem].sName);
		} else {
			SetActiveCelWep(iActivator, iItem);

			EmitSoundToAll(SOUND_EQUIP, iEntity);

			Cel_PrintToChat(iActivator, "You took your {green}%s{default}. It is in your weapons now.", g_Items[iItem].sName);
		}

		return;
	}

	if (g_Items[iItem].iKind == KIND_EMBLEM)
	{
		if (g_iActiveEmblem[iActivator] == iItem)
		{
			SetActiveEmblem(iActivator, -1);

			EmitSoundToAll(SOUND_UNEQUIP, iEntity);

			Cel_PrintToChat(iActivator, "Your {green}%s{default} emblem has been disabled.", g_Items[iItem].sName);
		} else {
			SetActiveEmblem(iActivator, iItem);

			EmitSoundToAll(SOUND_EQUIP, iEntity);

			Cel_PrintToChat(iActivator, "Your {green}%s{default} emblem is now enabled. Hold your gravity gun to use it.", g_Items[iItem].sName);
		}
	} else {
		if (g_iActiveHat[iActivator] == iItem)
		{
			SetActiveHat(iActivator, -1);

			EmitSoundToAll(SOUND_UNEQUIP, iEntity);

			Cel_PrintToChat(iActivator, "You took off your {green}%s{default} hat.", g_Items[iItem].sName);
		} else {
			SetActiveHat(iActivator, iItem);

			EmitSoundToAll(SOUND_EQUIP, iEntity);

			Cel_PrintToChat(iActivator, "You are now wearing your {green}%s{default} hat.", g_Items[iItem].sName);
		}
	}
}

public void Hook_RewardUse(int iEntity, int iActivator, int iCaller, UseType utType, float fValue)
{
	char sKey[64];

	if (iActivator < 1 || iActivator > MaxClients || !IsRealClient(iActivator) || g_iRewardId[iEntity] == -1)
	{
		return;
	}

	Format(sKey, sizeof(sKey), "reward_%d_%s", g_iRewardId[iEntity], g_sMap);

	// An event emblem can only ever be earned once, from any pickup on any map, even one placed again later.
	char sEventKey[64];

	if (g_bRewardEvent[iEntity] && g_iEntItem[iEntity] >= 0)
	{
		int iEventItem = g_iEntItem[iEntity];

		// Emblems keep their original key; hats and celweps include their kind.
		if (g_Items[iEventItem].iKind == KIND_EMBLEM)
		{
			Format(sEventKey, sizeof(sEventKey), "event_%s", g_Items[iEventItem].sId);
		} else {
			Format(sEventKey, sizeof(sEventKey), "event_%s_%s", g_sKindName[g_Items[iEventItem].iKind], g_Items[iEventItem].sId);
		}

		if (Inv_GetInt(iActivator, sEventKey) == 1)
		{
			EmitSoundToClient(iActivator, SOUND_DENY);

			Cel_PrintToChat(iActivator, "You have already earned the {green}%s{default} event %s. Each event item can only be earned once.", g_Items[iEventItem].sName, g_sKindName[g_Items[iEventItem].iKind]);

			return;
		}
	}

	if (Inv_GetInt(iActivator, sKey) == 1)
	{
		EmitSoundToClient(iActivator, SOUND_DENY);

		Cel_PrintToChat(iActivator, "You have already claimed this reward.");

		return;
	}

	// g_iEntItem holds the item, or -(kind + 2) when the reward is a random item of that kind.
	int iItem = g_iEntItem[iEntity];

	if (iItem < -1)
	{
		iItem = PickRandomItem(-(iItem + 2));
	}

	if (iItem < 0)
	{
		return;
	}

	Inv_SetInt(iActivator, sKey, 1);

	if (g_bRewardEvent[iEntity])
	{
		Inv_SetInt(iActivator, sEventKey, 1);
	}

	GiveItem(iActivator, iItem);

	EmitSoundToAll(SOUND_REWARD, iEntity);

	Cel_PrintToChatAll("{green}%N{default} has earned a {green}%s{default} %s!", iActivator, g_Items[iItem].sName, g_sKindName[g_Items[iItem].iKind]);
}

public Action Hook_HatTransmit(int iEntity, int iClient)
{
	// The wearer never sees their own hat, it would block their first person view.
	if (!g_cvShowSelf.BoolValue && iClient > 0 && iClient <= MaxClients && !g_bThirdPerson[iClient] && EntRefToEntIndex(g_iHatEntRef[iClient]) == iEntity)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int iClient, int &iButtons)
{
	// Custom Guns opens its weapon wheel on Reload or +attack3 while a custom gun is in hand. Celweps never need
	// reloading, so those buttons are held back from it while one is out. (This runs before Custom Guns does, as
	// plugins are called in load order.)
	if (g_bCustomGuns && IsPlayerAlive(iClient) && (iButtons & (IN_RELOAD | IN_ATTACK3)))
	{
		char sWeapon[64];

		GetClientWeapon(iClient, sWeapon, sizeof(sWeapon));

		if (FindCustomGunItem(sWeapon) != -1)
		{
			iButtons &= ~(IN_RELOAD | IN_ATTACK3);
		}
	}

	int iLast = g_iLastButtons[iClient];

	g_iLastButtons[iClient] = iButtons;

	// Tapping the walk key steps the walking speed down a tier: normal, slow, very slow, super slow, then fast.
	if ((iButtons & IN_WALK) && !(iLast & IN_WALK) && IsPlayerAlive(iClient) && !g_bWalkKeyOff[iClient])
	{
		g_iWalkTier[iClient] = (g_iWalkTier[iClient] == 0) ? sizeof(g_fWalkTier) - 1 : g_iWalkTier[iClient] - 1;

		// Felt straight away; the emblem speed check puts both together a moment later.
		SetEntPropFloat(iClient, Prop_Data, "m_flLaggedMovementValue", WalkFactor(iClient));

		g_bSpeedManaged[iClient] = true;

		Cel_PrintToChat(iClient, "Your walking speed is now {green}%s{default}.", g_sWalkTier[g_iWalkTier[iClient]]);
	}

	// Pressing E while looking at the Power Booth up close.
	if ((iButtons & IN_USE) && !(iLast & IN_USE) && IsPlayerAlive(iClient) && IsLookingAtBooth(iClient))
	{
		Hook_BoothUse(EntRefToEntIndex(g_iBoothRef), iClient, iClient, Use_Toggle, 0.0);
	} else if ((iButtons & IN_USE) && !(iLast & IN_USE) && IsPlayerAlive(iClient))
	{
		// Pressing E on a reward pickup or event item up close.
		int iAim = GetClientAimTarget(iClient, false);

		if (iAim > MaxClients && iAim <= MAXENTITIES && g_iRewardId[iAim] != -1)
		{
			// Measured to the point being looked at, so large map objects work from any side.
			float fEyes[3], fAngles[3], fHit[3];

			GetClientEyePosition(iClient, fEyes);
			GetClientEyeAngles(iClient, fAngles);

			Handle hAim = TR_TraceRayFilterEx(fEyes, fAngles, MASK_SHOT, RayType_Infinite, Filter_NotSelf, iClient);

			bool bClose = false;

			if (TR_DidHit(hAim) && TR_GetEntityIndex(hAim) == iAim)
			{
				TR_GetEndPosition(fHit, hAim);

				// The game's own +use reach for doors and buttons (PLAYER_USE_RADIUS): 80 units from the eyes.
				bClose = (GetVectorDistance(fEyes, fHit) <= 80.0);
			}

			CloseHandle(hAim);

			if (bClose)
			{
				Hook_RewardUse(iAim, iClient, iClient, Use_Toggle, 0.0);
			}
		}
	}

	// The fallback shovel (no Custom Guns) digs too, whenever it swings at the ground.
	if ((iButtons & IN_ATTACK) && !(iLast & IN_ATTACK) && IsPlayerAlive(iClient) && g_iCelWepItem[iClient] != -1 && g_Items[g_iCelWepItem[iClient]].sDigs[0] != '\0'
		&& EntRefToEntIndex(g_iCelWepRef[iClient]) == GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon"))
	{
		float fAim[3], fDirection[3], fEnd[3], fNormal[3];

		GetClientEyePosition(iClient, fAim);

		float fAngles[3];

		GetClientEyeAngles(iClient, fAngles);
		GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);

		fEnd[0] = fAim[0] + fDirection[0] * 90.0;
		fEnd[1] = fAim[1] + fDirection[1] * 90.0;
		fEnd[2] = fAim[2] + fDirection[2] * 90.0;

		Handle hDig = TR_TraceRayFilterEx(fAim, fEnd, MASK_SHOT, RayType_EndPoint, Filter_NotSelf, iClient);

		if (TR_DidHit(hDig) && TR_GetEntityIndex(hDig) == 0)
		{
			TR_GetPlaneNormal(hDig, fNormal);
			TR_GetEndPosition(fEnd, hDig);

			if (fNormal[2] > 0.7)
			{
				DigForEmblem(iClient, g_iCelWepItem[iClient], fEnd);
			}
		}

		CloseHandle(hDig);
	}

	// Phasing into an event or restricted area puts the player back where they started phasing.
	if (g_bPhasing[iClient] && IsPlayerAlive(iClient))
	{
		float fOrigin[3];

		GetClientAbsOrigin(iClient, fOrigin);

		fOrigin[2] += 32.0;

		if (ZoneBlocks(iClient, fOrigin))
		{
			g_bPhasing[iClient] = false;

			SetEntityMoveType(iClient, MOVETYPE_WALK);

			TeleportEntity(iClient, g_fPhaseStart[iClient], NULL_VECTOR, g_fZero);

			Cel_PrintToChat(iClient, "You cannot phase into that area.");
		}
	}

	int iItem = g_iActiveEmblem[iClient];

	if (iItem == -1 || !g_bHoldingGravGun[iClient] || !IsPlayerAlive(iClient))
	{
		return Plugin_Changed;
	}

	// Phantom: holding right click phases through walls (but not inside event and restricted areas).
	if (StrEqual(g_Items[iItem].sPower, "phase") && (iButtons & IN_ATTACK2) && !g_bPhasing[iClient] && !g_bInEvent[iClient])
	{
		float fOrigin[3];

		GetClientAbsOrigin(iClient, fOrigin);

		fOrigin[2] += 32.0;

		if (!ZoneBlocks(iClient, fOrigin))
		{
			GetClientAbsOrigin(iClient, g_fPhaseStart[iClient]);

			g_bPhasing[iClient] = true;

			SetEntityMoveType(iClient, MOVETYPE_NOCLIP);
		}
	}

	// Jump emblems, and any emblem with a "jumpboost", jump higher.
	if ((StrEqual(g_Items[iItem].sPower, "jump") || g_Items[iItem].fJump > 0.0) && !g_bInEvent[iClient] && (iButtons & IN_JUMP) && !(iLast & IN_JUMP) && (GetEntityFlags(iClient) & FL_ONGROUND))
	{
		RequestFrame(Frame_Jump, GetClientUserId(iClient));
	}

	if (StrEqual(g_Items[iItem].sPower, "feather") && !g_bInEvent[iClient])
	{
		float fVelocity[3];

		GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", fVelocity);

		// Caps the falling speed, so the player floats down.
		if (!(GetEntityFlags(iClient) & FL_ONGROUND) && fVelocity[2] < -g_Items[iItem].fValue)
		{
			fVelocity[2] = -g_Items[iItem].fValue;

			TeleportEntity(iClient, NULL_VECTOR, NULL_VECTOR, fVelocity);
		}
	} else if (IsShotPower(g_Items[iItem].sPower))
	{
		// Primary fire can be held down, the emblem's cooldown sets how fast it shoots.
		if ((iButtons & IN_ATTACK) && GetGameTime() >= g_fNextPower[iClient])
		{
			g_fNextPower[iClient] = GetGameTime() + g_Items[iItem].fCooldown;

			FireEmblemShot(iClient, iItem);
		}
	}

	if ((iButtons & IN_ATTACK2) && !(iLast & IN_ATTACK2) && GetGameTime() >= g_fNextSecondary[iClient])
	{
		g_fNextSecondary[iClient] = GetGameTime() + 0.5;

		SecondaryEmblemPower(iClient, iItem);
	}

	return Plugin_Changed;
}

public void Frame_Jump(any iUserId)
{
	float fVelocity[3];
	int iClient = GetClientOfUserId(iUserId);

	if (iClient < 1 || !IsPlayerAlive(iClient))
	{
		return;
	}

	int iItem = g_iActiveEmblem[iClient];

	if (iItem == -1)
	{
		return;
	}

	float fJump = StrEqual(g_Items[iItem].sPower, "jump") ? g_Items[iItem].fValue : g_Items[iItem].fJump;

	if (fJump <= 0.0)
	{
		return;
	}

	GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", fVelocity);

	fVelocity[2] = fJump;

	TeleportEntity(iClient, NULL_VECTOR, NULL_VECTOR, fVelocity);
}

//Timers:
public Action Timer_RestoreClient(Handle hTimer, any iUserId)
{
	char sId[64];
	int iClient = GetClientOfUserId(iUserId);

	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Stop;
	}

	// Emblems start switched off on every join: the player presses E on one again to use it.
	Inv_SetString(iClient, "active_emblem", "none");

	// Celweps are not carried over a rejoin: the player takes them from their weapon cels again.
	for (int i = 0; i < g_iItemCount; i++)
	{
		char sKey[64];

		if (g_Items[i].iKind != KIND_WEAPON)
		{
			continue;
		}

		g_bCelWepTaken[iClient][i] = false;

		Format(sKey, sizeof(sKey), "taken_%s", g_Items[i].sId);

		if (Inv_GetInt(iClient, sKey) == 1)
		{
			Inv_SetInt(iClient, sKey, 0);
		}
	}

	Inv_SetString(iClient, "active_weapon", "none");

	int iItem;

	Inv_GetString(iClient, "active_playermodel", sId, sizeof(sId));

	for (int i = 0; i < g_iPlayerModelCount; i++)
	{
		if (StrEqual(g_PlayerModels[i].sId, sId, false) && OwnsPlayerModel(iClient, i))
		{
			g_iPlayerModel[iClient] = i;

			ApplyPlayerModel(iClient);
		}
	}

	Inv_GetString(iClient, "active_hat", sId, sizeof(sId));

	iItem = FindItem(KIND_HAT, sId);

	if (iItem != -1 && GetOwned(iClient, iItem) > 0)
	{
		g_iActiveHat[iClient] = iItem;

		CreateHatEntity(iClient);
	}

	return Plugin_Stop;
}

public Action Timer_ApplyHat(Handle hTimer, any iUserId)
{
	int iClient = GetClientOfUserId(iUserId);

	if (iClient > 0 && IsClientInGame(iClient))
	{
		// The player model goes on first: the hat is fixed to the model's head.
		ApplyPlayerModel(iClient);

		CreateHatEntity(iClient);

		// Custom Guns empties the inventory on death and refills it a second after spawning; ours go in after that.
		CreateTimer(1.5, Timer_GiveCelWeps, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);

		// Weapons are lost on death, so the celwep is handed back.
		if (g_iCelWepItem[iClient] != -1 && IsPlayerAlive(iClient))
		{
			SetActiveCelWep(iClient, g_iCelWepItem[iClient]);
		}

		ApplyPlayerModel(iClient);

		// The view resets on respawn, so a player who chose third person gets it back.
		if (g_bThirdPerson[iClient])
		{
			SetThirdPerson(iClient, true);
		}
	}

	return Plugin_Stop;
}

public Action Timer_Think(Handle hTimer)
{
	char sClassname[64];
	float fNow = GetGameTime(), fSpeed;
	int iItem, iWeapon;

	g_iTick++;

	bool bModelCheck = (g_iTick % 5 == 0);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}

		if (!IsPlayerAlive(i))
		{
			g_bHoldingGravGun[i] = false;
			continue;
		}

		iItem = g_iActiveEmblem[i];

		// The game puts players back on their own model now and then, a bought model is put back on.
		if (bModelCheck && g_iPlayerModel[i] != -1)
		{
			ApplyPlayerModel(i);
		}

		iWeapon = GetEntPropEnt(i, Prop_Send, "m_hActiveWeapon");

		// Emblem boxes: the one held with the gravity gun is remembered for the map change.
		if (iWeapon > MaxClients && IsValidEntity(iWeapon) && HasEntProp(iWeapon, Prop_Send, "m_hAttachedObject"))
		{
			int iHeld = GetEntPropEnt(iWeapon, Prop_Send, "m_hAttachedObject");

			if (iHeld > MaxClients && iHeld <= MAXENTITIES && g_bDropBox[iHeld])
			{
				g_iHeldBox[i] = EntIndexToEntRef(iHeld);
				g_fHeldBoxTime[i] = GetGameTime();
			}
		}

		g_bHoldingGravGun[i] = false;

		// Inside an event area (a maze or parkour course) emblems give no help moving around.
		float fFeet[3];

		GetClientAbsOrigin(i, fFeet);

		fFeet[2] += 32.0;

		bool bWasInEvent = g_bInEvent[i];

		g_bInEvent[i] = (!IsZoneExempt(i) && ZoneTypeAt(fFeet) == CEL_ZONE_EVENT);

		if (g_bInEvent[i] && !bWasInEvent && iItem != -1 && IsMovementPower(iItem))
		{
			Cel_PrintToChat(i, "Your {green}%s{default} emblem's power does not work in event areas.", g_Items[iItem].sName);
		}

		if (iWeapon > MaxClients && IsValidEntity(iWeapon))
		{
			GetEntityClassname(iWeapon, sClassname, sizeof(sClassname));

			g_bHoldingGravGun[i] = StrEqual(sClassname, GRAVGUN_CLASS);
		}

		// Third person model: other players see the emblem in this player's hand in place of the
		// gravity gun. The player's own first person view model is never touched.
		int iShow = (g_bHoldingGravGun[i] && iItem != -1) ? iItem : -1;

		// A celwep is shown the same way while its weapon is the one in hand.
		if (iShow == -1 && g_iCelWepItem[i] != -1 && iWeapon > MaxClients && EntRefToEntIndex(g_iCelWepRef[i]) == iWeapon)
		{
			iShow = g_iCelWepItem[i];
		}

		// Custom Guns celweps: their own world models are not made to sit in a hand, so the celwep model is put
		// there instead. Its name is shown when it is switched to, as the weapon menu only says "cubemap".
		int iGun = -1;

		if (iWeapon > MaxClients)
		{
			GetEntityClassname(iWeapon, sClassname, sizeof(sClassname));

			iGun = FindCustomGunItem(sClassname);
		}

		if (iGun != -1)
		{
			if (iShow == -1)
			{
				iShow = iGun;
			}

			if (g_iShownGunRef[i] != EntIndexToEntRef(iWeapon))
			{
				g_iShownGunRef[i] = EntIndexToEntRef(iWeapon);
			}
		} else {
			g_iShownGunRef[i] = INVALID_ENT_REFERENCE;
		}

		if (iShow != -1)
		{
			if (!g_bHeldShown[i] || g_iHandItem[i] != iShow || g_iModdedWeaponRef[i] != EntIndexToEntRef(iWeapon))
			{
				RestoreWeapon(i);
				ShowHeldEmblem(i, iShow, iWeapon);
			}
		} else if (g_bHeldShown[i])
		{
			RestoreWeapon(i);
		}

		// Movement speed: slowed by a blizzard emblem, or boosted by the player's own speed emblem.
		fSpeed = 1.0;

		if (fNow < g_fFrozenUntil[i])
		{
			fSpeed = 0.35;
		} else {
			if (g_bFrozenTint[i])
			{
				g_bFrozenTint[i] = false;
				g_bCloaked[i] = false;

				SetEntityRenderColor(i, 255, 255, 255, 255);
			}

			if (g_bHoldingGravGun[i] && iItem != -1 && !g_bInEvent[i])
			{
				// The speed emblem uses its value, any other emblem can carry a "speed" key.
				fSpeed = StrEqual(g_Items[iItem].sPower, "speed") ? g_Items[iItem].fValue : g_Items[iItem].fSpeed;
			}
		}

		// The walking speed tier the player picked with the walk key.
		fSpeed *= WalkFactor(i);

		if (fSpeed != 1.0 || g_bSpeedManaged[i])
		{
			SetEntPropFloat(i, Prop_Data, "m_flLaggedMovementValue", fSpeed);

			g_bSpeedManaged[i] = (fSpeed != 1.0);
		}

		// Some emblems tint their holder (Demon turns them deep purple).
		if (g_bHoldingGravGun[i] && iItem != -1 && g_Items[iItem].bPlayerColor && fNow >= g_fFrozenUntil[i])
		{
			g_bTinted[i] = true;

			// A see-through tint (Phantom) needs the see-through render mode.
			if (g_Items[iItem].iPlayerColor[3] < 255)
			{
				SetEntityRenderMode(i, RENDER_TRANSCOLOR);
			}

			SetEntityRenderColor(i, g_Items[iItem].iPlayerColor[0], g_Items[iItem].iPlayerColor[1], g_Items[iItem].iPlayerColor[2], g_Items[iItem].iPlayerColor[3]);
		} else if (g_bTinted[i])
		{
			g_bTinted[i] = false;

			if (fNow >= g_fFrozenUntil[i] && !g_bCloaked[i])
			{
				SetEntityRenderMode(i, RENDER_NORMAL);
				SetEntityRenderColor(i, 255, 255, 255, 255);
			}
		}

		// Phantom: a player who stops phasing (lets go of right click, puts the emblem away) is put back to walking
		// as soon as they are not inside anything.
		if (g_bPhasing[i] && !(g_bHoldingGravGun[i] && iItem != -1 && StrEqual(g_Items[iItem].sPower, "phase") && (GetClientButtons(i) & IN_ATTACK2)))
		{
			StopPhasing(i);
		}

		// Cloak: the player is nearly invisible while the emblem is in hand.
		if (g_bHoldingGravGun[i] && iItem != -1 && StrEqual(g_Items[iItem].sPower, "cloak"))
		{
			if (!g_bCloaked[i])
			{
				g_bCloaked[i] = true;

				SetEntityRenderMode(i, RENDER_TRANSCOLOR);
				SetEntityRenderColor(i, 255, 255, 255, RoundToFloor(g_Items[iItem].fValue));
			}
		} else if (g_bCloaked[i])
		{
			g_bCloaked[i] = false;

			SetEntityRenderMode(i, RENDER_NORMAL);
			SetEntityRenderColor(i, 255, 255, 255, 255);
		}

		// Gravity: the holder is lighter (or heavier) while the emblem is in hand.
		if (g_bHoldingGravGun[i] && iItem != -1 && StrEqual(g_Items[iItem].sPower, "gravity") && !g_bInEvent[i])
		{
			g_bGravityManaged[i] = true;

			SetEntityGravity(i, g_Items[iItem].fValue);
		} else if (g_bGravityManaged[i])
		{
			g_bGravityManaged[i] = false;

			SetEntityGravity(i, 1.0);
		}

		// Sprint: the suit's sprint power never runs out.
		if (g_bHoldingGravGun[i] && iItem != -1 && StrEqual(g_Items[iItem].sPower, "sprint") && !g_bInEvent[i])
		{
			SetEntPropFloat(i, Prop_Send, "m_flSuitPower", 100.0);
		}

		// Drain: the emblem slowly hurts its own holder, once a second.
		if (g_iTick % 5 == 0 && g_bHoldingGravGun[i] && iItem != -1 && StrEqual(g_Items[iItem].sPower, "drain") && !Cel_GetNoKill(i))
		{
			SDKHooks_TakeDamage(i, i, i, g_Items[iItem].fValue, DMG_RADIATION);
		}

		// Suit power regeneration, once a second.
		if (g_iTick % 5 == 0 && g_bHoldingGravGun[i] && iItem != -1 && StrEqual(g_Items[iItem].sPower, "armor"))
		{
			int iArmor = GetEntProp(i, Prop_Send, "m_ArmorValue") + RoundToFloor(g_Items[iItem].fValue);

			SetEntProp(i, Prop_Send, "m_ArmorValue", iArmor > 100 ? 100 : iArmor);
		}

		// Health regeneration, once a second.
		if (g_iTick % 5 == 0 && g_bHoldingGravGun[i] && iItem != -1 && StrEqual(g_Items[iItem].sPower, "heal"))
		{
			int iHealth = GetClientHealth(i);

			if (iHealth < 100)
			{
				iHealth += RoundToFloor(g_Items[iItem].fValue);

				SetEntityHealth(i, iHealth > 100 ? 100 : iHealth);
			}
		}
	}

	ThinkPortals();

	Fx_ThinkAuras();

	if (g_iTick % 5 == 0)
	{
		ThinkEventEmblems();
	}

	if (g_iTick % 3 == 0)
	{
		ThinkTrash();
	}

	if (g_iTick % 5 == 0)
	{
		ThinkSmog();
	}

	return Plugin_Continue;
}

public Action Timer_Minute(Handle hTimer)
{
	int iItem, iPlayers = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsRealClient(i))
		{
			continue;
		}

		iPlayers++;

		iItem = g_iActiveEmblem[i];

		// Gold emblem: pays its owner every minute it is enabled.
		if (iItem != -1 && StrEqual(g_Items[iItem].sPower, "gold") && IsPlayerAlive(i))
		{
			Cel_AddToClientBalance(i, RoundToFloor(g_Items[iItem].fValue));
		}
	}

	g_iMinutesSinceDrop++;

	if (g_cvDropInterval.IntValue > 0 && g_iMinutesSinceDrop >= g_cvDropInterval.IntValue && iPlayers >= g_cvDropMinPlayers.IntValue)
	{
		StartDrop(g_cvDropCount.IntValue);
	}

	return Plugin_Continue;
}

//Natives:
public int Native_GetCollectibleId(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1), iMaxLength = GetNativeCell(3);

	if (!IsItemEntity(iEntity))
	{
		SetNativeString(2, "", iMaxLength);

		return false;
	}

	SetNativeString(2, g_Items[g_iEntItem[iEntity]].sId, iMaxLength);

	return true;
}

public int Native_GetCollectibleName(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1), iMaxLength = GetNativeCell(3);

	if (!IsItemEntity(iEntity))
	{
		SetNativeString(2, "", iMaxLength);

		return false;
	}

	SetNativeString(2, g_Items[g_iEntItem[iEntity]].sName, iMaxLength);

	return true;
}

public int Native_GiveCollectible(Handle hPlugin, int iNumParams)
{
	char sId[64], sKind[32];
	int iClient = GetNativeCell(1);

	GetNativeString(2, sKind, sizeof(sKind));
	GetNativeString(3, sId, sizeof(sId));

	int iItem = FindItem(KindFromName(sKind), sId);

	if (iItem == -1 || !IsRealClient(iClient))
	{
		return false;
	}

	GiveItem(iClient, iItem);

	return true;
}

// For the shop (celmod-shop): how many of an item a client owns, -1 if there is no such item.
public int Native_GetCollectibleCount(Handle hPlugin, int iNumParams)
{
	char sId[64], sKind[32];
	int iClient = GetNativeCell(1);

	GetNativeString(2, sKind, sizeof(sKind));
	GetNativeString(3, sId, sizeof(sId));

	int iItem = FindItem(KindFromName(sKind), sId);

	if (iItem == -1 || !IsRealClient(iClient))
	{
		return -1;
	}

	return GetOwned(iClient, iItem);
}

public int Native_GetPlayerModelCount(Handle hPlugin, int iNumParams)
{
	return g_iPlayerModelCount;
}

public int Native_GetPlayerModelInfo(Handle hPlugin, int iNumParams)
{
	int iModel = GetNativeCell(1);

	if (iModel < 0 || iModel >= g_iPlayerModelCount)
	{
		return false;
	}

	SetNativeString(2, g_PlayerModels[iModel].sId, GetNativeCell(3));
	SetNativeString(4, g_PlayerModels[iModel].sName, GetNativeCell(5));
	SetNativeCellRef(6, g_PlayerModels[iModel].iPrice);
	SetNativeCellRef(7, g_PlayerModels[iModel].iAdminFlags);

	return true;
}

// -1 = no such model, 0 = not owned, 1 = owned (bought, given, free or admin).
public int Native_OwnsPlayerModel(Handle hPlugin, int iNumParams)
{
	char sId[64];
	int iClient = GetNativeCell(1);

	GetNativeString(2, sId, sizeof(sId));

	int iModel = FindPlayerModel(sId);

	if (iModel == -1 || !IsRealClient(iClient))
	{
		return -1;
	}

	return OwnsPlayerModel(iClient, iModel) ? 1 : 0;
}

// Same as !givemodel: the model is the player's for good.
public int Native_GivePlayerModel(Handle hPlugin, int iNumParams)
{
	char sId[64], sKey[64];
	int iClient = GetNativeCell(1);

	GetNativeString(2, sId, sizeof(sId));

	int iModel = FindPlayerModel(sId);

	if (iModel == -1 || !IsRealClient(iClient))
	{
		return false;
	}

	Format(sKey, sizeof(sKey), "playermodel_%s", g_PlayerModels[iModel].sId);
	Inv_SetInt(iClient, sKey, 1);

	return true;
}

public int Native_IsCollectible(Handle hPlugin, int iNumParams)
{
	return IsItemEntity(GetNativeCell(1));
}

public int Native_SpawnCollectible(Handle hPlugin, int iNumParams)
{
	char sId[64], sKind[32];
	float fAngles[3], fOrigin[3];
	int iClient = GetNativeCell(1);

	GetNativeString(2, sKind, sizeof(sKind));
	GetNativeString(3, sId, sizeof(sId));
	GetNativeArray(4, fAngles, 3);
	GetNativeArray(5, fOrigin, 3);

	int iItem = FindItem(KindFromName(sKind), sId);

	if (iItem == -1 || !IsRealClient(iClient))
	{
		return -1;
	}

	// Only as many copies as the player really owns can exist, so loading a build never duplicates an item.
	if (CountSpawned(iClient, iItem) >= GetOwned(iClient, iItem))
	{
		return -1;
	}

	return SpawnItemEntity(iClient, iItem, fOrigin, fAngles);
}

//Item database:
void LoadItems()
{
	g_iItemCount = 0;

	KeyValues kvItems = new KeyValues("Collectibles");

	if (!kvItems.ImportFromFile(g_sItemDB))
	{
		LogError("|CelMod| Could not read the collectibles file at '%s'. No emblems or hats are available.", g_sItemDB);

		delete kvItems;

		return;
	}

	if (kvItems.JumpToKey("Emblems", false) && kvItems.GotoFirstSubKey())
	{
		do
		{
			ReadItem(kvItems, KIND_EMBLEM);
		}
		while (kvItems.GotoNextKey());
	}

	// Emblems that turn into another emblem at the Power Booth (two Errors make a Blue Error, and so on).
	for (int i = 0; i < g_iItemCount; i++)
	{
		if (g_Items[i].sUpgradeTo[0] != '\0')
		{
			g_Items[i].iUpgradeTo = FindItem(KIND_EMBLEM, g_Items[i].sUpgradeTo);

			if (g_Items[i].iUpgradeTo == -1)
			{
				LogError("|CelMod| Emblem '%s' upgrades to the unknown emblem '%s'.", g_Items[i].sId, g_Items[i].sUpgradeTo);
			}
		}
	}

	// Every emblem gets a big version, made at the Power Booth. It is stronger and uses the large model.
	int iEmblems = g_iItemCount;

	for (int i = 0; i < iEmblems && g_iItemCount < MAX_ITEMS; i++)
	{
		int iBig = g_iItemCount++;

		g_Items[iBig] = g_Items[i];

		Format(g_Items[iBig].sId, sizeof(Item::sId), "%s_big", g_Items[i].sId);
		Format(g_Items[iBig].sName, sizeof(Item::sName), "Big %s", g_Items[i].sName);

		if (StrEqual(g_Items[i].sModel, "models/celmod/phys8.mdl", false))
		{
			strcopy(g_Items[iBig].sModel, sizeof(Item::sModel), BIG_EMBLEM_MODEL);

			// The large model is far too big for a hand, and scaled models do not show; it is held as the normal one.
			strcopy(g_Items[iBig].sHandModel, sizeof(Item::sHandModel), g_Items[i].sModel);

			g_Items[iBig].fHandScale = g_Items[i].fHandScale;
		} else {
			g_Items[iBig].fScale = g_Items[i].fScale * 2.0;
		}

		g_Items[iBig].iModelIndex = PrecacheModel(g_Items[iBig].sModel, true);
		g_Items[iBig].fCooldown = g_Items[i].fCooldown * 0.75;
		g_Items[iBig].fSecondaryValue = g_Items[i].fSecondaryValue * 1.5;
		g_Items[iBig].fSecondaryCooldown = g_Items[i].fSecondaryCooldown * 0.75;
		g_Items[iBig].iWeight = 0;
		g_Items[iBig].bIsBig = true;
		g_Items[iBig].iBig = -1;
		g_Items[iBig].iUpgradeTo = -1;
		g_Items[iBig].sUpgradeTo[0] = '\0';

		// Stronger numbers, except where a bigger value would make the power weaker.
		if (StrEqual(g_Items[i].sPower, "resist") || StrEqual(g_Items[i].sPower, "gravity") || StrEqual(g_Items[i].sPower, "cloak") || StrEqual(g_Items[i].sPower, "feather"))
		{
			g_Items[iBig].fValue = g_Items[i].fValue * 0.75;
		} else if (StrEqual(g_Items[i].sPower, "speed"))
		{
			g_Items[iBig].fValue = g_Items[i].fValue + 0.3;
		} else {
			g_Items[iBig].fValue = g_Items[i].fValue * 1.5;
		}

		g_Items[i].iBig = iBig;
	}

	kvItems.Rewind();

	if (kvItems.JumpToKey("Weapons", false) && kvItems.GotoFirstSubKey())
	{
		do
		{
			ReadItem(kvItems, KIND_WEAPON);
		}
		while (kvItems.GotoNextKey());
	}

	kvItems.Rewind();

	g_iPlayerModelCount = 0;

	if (kvItems.JumpToKey("PlayerModels", false) && kvItems.GotoFirstSubKey())
	{
		do
		{
			if (g_iPlayerModelCount >= MAX_PLAYERMODELS)
			{
				break;
			}

			int iModel = g_iPlayerModelCount++;

			kvItems.GetSectionName(g_PlayerModels[iModel].sId, sizeof(PlayerModel::sId));
			kvItems.GetString("name", g_PlayerModels[iModel].sName, sizeof(PlayerModel::sName), g_PlayerModels[iModel].sId);
			kvItems.GetString("model", g_PlayerModels[iModel].sModel, sizeof(PlayerModel::sModel), "");

			g_PlayerModels[iModel].iPrice = kvItems.GetNum("price", 0);

			char sFlags[32], sMaterials[PLATFORM_MAX_PATH];

			// Admin flags, e.g. "b". Admins with them can wear the model without buying it; nobody else can buy it.
			kvItems.GetString("admin", sFlags, sizeof(sFlags), "");

			g_PlayerModels[iModel].iAdminFlags = (sFlags[0] == '\0') ? 0 : ReadFlagString(sFlags);

			// Custom models: the model's own files are sent to players, plus every file in "materials" if given.
			AddModelToDownloads(g_PlayerModels[iModel].sModel);

			kvItems.GetString("materials", sMaterials, sizeof(sMaterials), "");

			if (sMaterials[0] != '\0')
			{
				AddFolderToDownloads(sMaterials);
			}

			PrecacheModel(g_PlayerModels[iModel].sModel, true);
		}
		while (kvItems.GotoNextKey());
	}

	kvItems.Rewind();

	if (kvItems.JumpToKey("Hats", false) && kvItems.GotoFirstSubKey())
	{
		do
		{
			ReadItem(kvItems, KIND_HAT);
		}
		while (kvItems.GotoNextKey());
	}

	delete kvItems;

	// Hand and hat positions saved in game with !tune and !nudge.
	ApplyTuning();

	// Players keep their active items across map changes, but item indexes can move if the file was edited.
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_iCelWepItem[i] >= g_iItemCount) g_iCelWepItem[i] = -1;
		if (g_iPlayerModel[i] >= g_iPlayerModelCount) g_iPlayerModel[i] = -1;
		if (g_iActiveEmblem[i] >= g_iItemCount) g_iActiveEmblem[i] = -1;
		if (g_iActiveHat[i] >= g_iItemCount) g_iActiveHat[i] = -1;
	}
}

void ReadItem(KeyValues kvItems, int iKind)
{
	if (g_iItemCount >= MAX_ITEMS)
	{
		return;
	}

	int iItem = g_iItemCount;

	g_Items[iItem].iKind = iKind;
	g_Items[iItem].sHandModel[0] = '\0';
	g_Items[iItem].iBig = -1;
	g_Items[iItem].bIsBig = false;

	kvItems.GetString("base", g_Items[iItem].sBase, sizeof(Item::sBase), "weapon_crowbar");
	kvItems.GetString("upgradesto", g_Items[iItem].sUpgradeTo, sizeof(Item::sUpgradeTo), "");
	kvItems.GetString("customgun", g_Items[iItem].sCustomGun, sizeof(Item::sCustomGun), "");
	kvItems.GetString("digs", g_Items[iItem].sDigs, sizeof(Item::sDigs), "");
	kvItems.GetString("attack", g_Items[iItem].sAttack, sizeof(Item::sAttack), "melee");

	g_Items[iItem].iUpgradeTo = -1;
	g_Items[iItem].iUpgradeCost = kvItems.GetNum("upgradecost", 2);
	g_Items[iItem].fJump = kvItems.GetFloat("jumpboost", 0.0);
	g_Items[iItem].fFallDamage = kvItems.GetFloat("falldamage", 1.0);
	g_Items[iItem].bGlow = view_as<bool>(kvItems.GetNum("glow", 0));
	g_Items[iItem].fHitDamage = kvItems.GetFloat("hitdamage", 25.0);
	g_Items[iItem].fHitRange = kvItems.GetFloat("hitrange", 80.0);
	g_Items[iItem].fRefire = kvItems.GetFloat("refire", 0.5);

	kvItems.GetColor4("playercolor", g_Items[iItem].iPlayerColor);

	g_Items[iItem].bPlayerColor = (g_Items[iItem].iPlayerColor[3] > 0);

	g_Items[iItem].fDamage = kvItems.GetFloat("damage", 1.0);

	kvItems.GetSectionName(g_Items[iItem].sId, sizeof(Item::sId));

	// The engine's KeyValues are case insensitive and can hand back another casing of the section name.
	for (int i = 0; g_Items[iItem].sId[i] != '\0'; i++)
	{
		g_Items[iItem].sId[i] = CharToLower(g_Items[iItem].sId[i]);
	}
	kvItems.GetString("name", g_Items[iItem].sName, sizeof(Item::sName), g_Items[iItem].sId);
	kvItems.GetString("model", g_Items[iItem].sModel, sizeof(Item::sModel), iKind == KIND_EMBLEM ? GRAVGUN_WORLDMODEL : "models/props_junk/trafficcone001a.mdl");
	kvItems.GetString("power", g_Items[iItem].sPower, sizeof(Item::sPower), "none");

	kvItems.GetColor4("color", g_Items[iItem].iColor);

	if (g_Items[iItem].iColor[0] == 0 && g_Items[iItem].iColor[1] == 0 && g_Items[iItem].iColor[2] == 0 && g_Items[iItem].iColor[3] == 0)
	{
		g_Items[iItem].iColor[0] = 255;
		g_Items[iItem].iColor[1] = 255;
		g_Items[iItem].iColor[2] = 255;
	}

	g_Items[iItem].iColor[3] = 255;

	g_Items[iItem].fValue = kvItems.GetFloat("value", 1.0);
	g_Items[iItem].fCooldown = kvItems.GetFloat("cooldown", 2.0);
	g_Items[iItem].fDuration = kvItems.GetFloat("duration", 4.0);
	g_Items[iItem].fRange = kvItems.GetFloat("range", 900.0);
	g_Items[iItem].fScale = kvItems.GetFloat("scale", 1.0);
	g_Items[iItem].iWeight = kvItems.GetNum("dropweight", 0);
	g_Items[iItem].iSkin = kvItems.GetNum("skin", 0);
	g_Items[iItem].fIgnite = kvItems.GetFloat("ignite", 0.0);
	g_Items[iItem].fSlow = kvItems.GetFloat("slow", 0.0);
	g_Items[iItem].fKnockback = kvItems.GetFloat("knockback", 0.0);

	kvItems.GetString("fx", g_Items[iItem].sFx, sizeof(Item::sFx), "beam");
	kvItems.GetString("aura", g_Items[iItem].sAura, sizeof(Item::sAura), "");
	kvItems.GetString("secondary", g_Items[iItem].sSecondary, sizeof(Item::sSecondary), "none");

	g_Items[iItem].fSecondaryValue = kvItems.GetFloat("secondaryvalue", 50.0);
	g_Items[iItem].fSecondaryCooldown = kvItems.GetFloat("secondarycooldown", 3.0);
	kvItems.GetString("sprite", g_Items[iItem].sSprite, sizeof(Item::sSprite), "sprites/glow04_noz.vmt");

	g_Items[iItem].iSpriteIndex = PrecacheModel(g_Items[iItem].sSprite, true);

	// A big shot model needs no sprite index of its own; sprite sprays use a glow instead.
	if (StrContains(g_Items[iItem].sSprite, ".mdl", false) != -1)
	{
		g_Items[iItem].iSpriteIndex = PrecacheModel("sprites/glow04_noz.vmt", true);
	}
	g_Items[iItem].fSpeed = kvItems.GetFloat("speed", 1.0);

	char sDamageType[24];

	kvItems.GetString("dmgtype", sDamageType, sizeof(sDamageType), "generic");

	if (StrEqual(sDamageType, "burn", false)) g_Items[iItem].iDamageType = DMG_BURN;
	else if (StrEqual(sDamageType, "drown", false)) g_Items[iItem].iDamageType = DMG_DROWN;
	else if (StrEqual(sDamageType, "poison", false)) g_Items[iItem].iDamageType = DMG_POISON;
	else if (StrEqual(sDamageType, "shock", false)) g_Items[iItem].iDamageType = DMG_SHOCK;
	else if (StrEqual(sDamageType, "dissolve", false)) g_Items[iItem].iDamageType = DMG_DISSOLVE;
	else if (StrEqual(sDamageType, "energy", false)) g_Items[iItem].iDamageType = DMG_ENERGYBEAM;
	else g_Items[iItem].iDamageType = DMG_GENERIC;

	kvItems.GetColor4("beamcolor", g_Items[iItem].iBeamColor);

	if (g_Items[iItem].iBeamColor[0] == 0 && g_Items[iItem].iBeamColor[1] == 0 && g_Items[iItem].iBeamColor[2] == 0)
	{
		g_Items[iItem].iBeamColor[0] = g_Items[iItem].iColor[0];
		g_Items[iItem].iBeamColor[1] = g_Items[iItem].iColor[1];
		g_Items[iItem].iBeamColor[2] = g_Items[iItem].iColor[2];
	}
	g_Items[iItem].fHandScale = kvItems.GetFloat("handscale", 1.0);

	kvItems.GetVector("handoffset", g_Items[iItem].fHandOffset);
	kvItems.GetVector("handangles", g_Items[iItem].fHandAngles);

	kvItems.GetVector("offset", g_Items[iItem].fOffset);
	kvItems.GetVector("angles", g_Items[iItem].fAngles);

	g_Items[iItem].iModelIndex = PrecacheModel(g_Items[iItem].sModel, true);

	g_iItemCount++;
}

int FindItem(int iKind, const char[] sSearch)
{
	for (int i = 0; i < g_iItemCount; i++)
	{
		if (g_Items[i].iKind == iKind && (StrEqual(g_Items[i].sId, sSearch, false) || StrEqual(g_Items[i].sName, sSearch, false)))
		{
			return i;
		}
	}

	return -1;
}

// Weighted pick using each item's "dropweight". Falls back to an even pick if no item of the kind has a weight.
int PickRandomItem(int iKind)
{
	int iCount = 0, iTotal = 0;

	for (int i = 0; i < g_iItemCount; i++)
	{
		if (iKind == -1 || g_Items[i].iKind == iKind)
		{
			iCount++;

			iTotal += g_Items[i].iWeight;
		}
	}

	if (iCount == 0)
	{
		return -1;
	}

	int iRoll = GetRandomInt(1, iTotal > 0 ? iTotal : iCount);

	for (int i = 0; i < g_iItemCount; i++)
	{
		if (iKind == -1 || g_Items[i].iKind == iKind)
		{
			iRoll -= (iTotal > 0) ? g_Items[i].iWeight : 1;

			if (iRoll <= 0)
			{
				return i;
			}
		}
	}

	return -1;
}

//Inventory storage:
// One file per player in data/celmod/inventory, kept in memory while they are connected. It holds
// how many of each item they own, their active emblem and hat, and which rewards they have claimed.
void Inv_Open(int iClient)
{
	char sAuthID[64];

	if (g_kvInv[iClient] == null)
	{
		g_kvInv[iClient] = new KeyValues("Inventory");
	}

	if (g_bInvFromDisk[iClient] || IsFakeClient(iClient))
	{
		return;
	}

	if (!GetClientAuthId(iClient, AuthId_SteamID64, sAuthID, sizeof(sAuthID), false) || sAuthID[0] == '\0')
	{
		// No Steam id yet. Tried again the next time the inventory is used.
		return;
	}

	BuildPath(Path_SM, g_sInvPath[iClient], sizeof(g_sInvPath[]), "data/celmod/inventory/%s.txt", sAuthID);

	if (FileExists(g_sInvPath[iClient]))
	{
		// Anything changed before the Steam id was known is replaced by what is on disk.
		delete g_kvInv[iClient];

		g_kvInv[iClient] = new KeyValues("Inventory");

		if (!g_kvInv[iClient].ImportFromFile(g_sInvPath[iClient]))
		{
			LogError("|CelMod| Could not read the inventory file '%s'.", g_sInvPath[iClient]);
		}
	}

	g_bInvFromDisk[iClient] = true;
}

void Inv_Save(int iClient)
{
	if (g_kvInv[iClient] == null || !g_bInvFromDisk[iClient])
	{
		return;
	}

	g_kvInv[iClient].Rewind();

	if (!g_kvInv[iClient].ExportToFile(g_sInvPath[iClient]))
	{
		LogError("|CelMod| Could not write the inventory file '%s'. Items will be lost when the player leaves.", g_sInvPath[iClient]);
	}
}

void Inv_Close(int iClient)
{
	if (g_kvInv[iClient] != null)
	{
		Inv_Save(iClient);

		delete g_kvInv[iClient];
	}

	g_bInvFromDisk[iClient] = false;
	g_sInvPath[iClient][0] = '\0';
}

int Inv_GetInt(int iClient, const char[] sKey)
{
	Inv_Open(iClient);

	g_kvInv[iClient].Rewind();

	return g_kvInv[iClient].GetNum(sKey, -1);
}

void Inv_SetInt(int iClient, const char[] sKey, int iValue)
{
	Inv_Open(iClient);

	g_kvInv[iClient].Rewind();
	g_kvInv[iClient].SetNum(sKey, iValue);

	Inv_Save(iClient);
}

void Inv_GetString(int iClient, const char[] sKey, char[] sValue, int iMaxLength)
{
	Inv_Open(iClient);

	g_kvInv[iClient].Rewind();
	g_kvInv[iClient].GetString(sKey, sValue, iMaxLength, "none");
}

void Inv_SetString(int iClient, const char[] sKey, const char[] sValue)
{
	Inv_Open(iClient);

	g_kvInv[iClient].Rewind();
	g_kvInv[iClient].SetString(sKey, sValue);

	Inv_Save(iClient);
}

//Ownership ledger:
void GetLedgerKey(int iItem, char[] sKey, int iMaxLength)
{
	Format(sKey, iMaxLength, "%s_%s", g_sKindName[g_Items[iItem].iKind], g_Items[iItem].sId);
}

int GetOwned(int iClient, int iItem)
{
	char sKey[64];

	GetLedgerKey(iItem, sKey, sizeof(sKey));

	int iOwned = Inv_GetInt(iClient, sKey);

	return iOwned < 0 ? 0 : iOwned;
}

void SetOwned(int iClient, int iItem, int iOwned)
{
	char sKey[64];

	GetLedgerKey(iItem, sKey, sizeof(sKey));

	Inv_SetInt(iClient, sKey, iOwned < 0 ? 0 : iOwned);
}

int CountSpawned(int iClient, int iItem)
{
	int iCount = 0;

	for (int i = MaxClients + 1; i <= MAXENTITIES; i++)
	{
		if (g_iEntItem[i] == iItem && IsItemEntity(i) && Cel_CheckOwner(iClient, i))
		{
			iCount++;
		}
	}

	return iCount;
}

void GiveItem(int iClient, int iItem)
{
	SetOwned(iClient, iItem, GetOwned(iClient, iItem) + 1);

	Cel_PrintToChat(iClient, "You received a {green}%s{default} %s! Type {green}!%s %s{default} to spawn it.", g_Items[iItem].sName, g_sKindName[g_Items[iItem].iKind], g_sKindName[g_Items[iItem].iKind], g_Items[iItem].sId);
}

void PrintInventory(int iClient, int iKind)
{
	char sEntry[96], sList[192];
	int iCount = 0, iOwned;

	// Everything goes into one list. It is only split when it would not fit in a single chat message.
	for (int i = 0; i < g_iItemCount; i++)
	{
		if (g_Items[i].iKind != iKind)
		{
			continue;
		}

		iOwned = GetOwned(iClient, i);

		if (iOwned < 1)
		{
			continue;
		}

		iCount++;

		Format(sEntry, sizeof(sEntry), "%s%s", g_Items[i].sName, (g_iActiveEmblem[iClient] == i || g_iActiveHat[iClient] == i || g_iCelWepItem[iClient] == i) ? " {green}[on]{default}" : "");

		if (iOwned > 1)
		{
			Format(sEntry, sizeof(sEntry), "%s x%d", sEntry, iOwned);
		}

		if (strlen(sList) + strlen(sEntry) + 2 >= sizeof(sList) - 1)
		{
			Cel_ReplyToCommand(iClient, "%s,", sList);

			sList[0] = '\0';
		}

		if (sList[0] == '\0')
		{
			Format(sList, sizeof(sList), "{green}%s:{default} %s", g_sKindTitle[iKind], sEntry);
		} else {
			Format(sList, sizeof(sList), "%s, %s", sList, sEntry);
		}
	}

	if (iCount == 0)
	{
		Cel_ReplyToCommand(iClient, "You do not own any %s.", g_sKindPlural[iKind]);
	} else {
		Cel_ReplyToCommand(iClient, "%s", sList);
	}
}

//Item entities:
bool IsItemEntity(int iEntity)
{
	return (iEntity > MaxClients && iEntity <= MAXENTITIES && g_iEntItem[iEntity] >= 0 && g_iEntItem[iEntity] < g_iItemCount && !g_bDropBox[iEntity] && g_iRewardId[iEntity] == -1 && IsValidEntity(iEntity));
}

int SpawnItemEntity(int iClient, int iItem, float fOrigin[3], float fAngles[3])
{
	int iEntity = CreateEntityByName("prop_physics_override");

	if (iEntity == -1 || iEntity > MAXENTITIES)
	{
		return -1;
	}

	PrecacheModel(g_Items[iItem].sModel);

	DispatchKeyValue(iEntity, "model", g_Items[iItem].sModel);
	DispatchKeyValue(iEntity, "classname", g_sKindClass[g_Items[iItem].iKind]);
	DispatchKeyValue(iEntity, "spawnflags", "256");

	if (g_Items[iItem].iKind == KIND_EMBLEM && g_Items[iItem].fScale != 1.0)
	{
		DispatchKeyValueFloat(iEntity, "modelscale", g_Items[iItem].fScale);
	}

	DispatchSpawn(iEntity);

	SetEntProp(iEntity, Prop_Send, "m_nSkin", g_Items[iItem].iSkin);

	TeleportEntity(iEntity, fOrigin, fAngles, NULL_VECTOR);

	g_bDropBox[iEntity] = false;
	g_iEntItem[iEntity] = iItem;
	g_iRewardId[iEntity] = -1;

	Cel_AddToCelCount(iClient);
	Cel_SetColor(iEntity, g_Items[iItem].iColor[0], g_Items[iItem].iColor[1], g_Items[iItem].iColor[2], g_Items[iItem].iColor[3]);
	Cel_SetRainbow(iEntity, false);
	Cel_SetEntity(iEntity, true);
	Cel_SetMotion(iEntity, false);
	Cel_SetOwner(iClient, iEntity);
	Cel_SetSolid(iEntity, true);
	Cel_LockEntity(iEntity, false);
	Cel_SetRenderFX(iEntity, RENDERFX_NONE);
	Cel_SetBreakable(iEntity, false);
	Cel_SetPropName(iEntity, g_Items[iItem].sName);

	SDKHook(iEntity, SDKHook_UsePost, Hook_ItemUse);

	if (g_Items[iItem].bGlow)
	{
		SetEntityRenderFx(iEntity, RENDERFX_GLOWSHELL);
	}

	return iEntity;
}

//Emblems:
void SetActiveEmblem(int iClient, int iItem)
{
	g_iActiveEmblem[iClient] = iItem;

	g_bPortal[iClient][0] = false;
	g_bPortal[iClient][1] = false;

	if (iItem == -1)
	{
		RestoreWeapon(iClient);

		Inv_SetString(iClient, "active_emblem", "none");
	} else {
		Inv_SetString(iClient, "active_emblem", g_Items[iItem].sId);
	}
}

// Attaches a copy of the emblem to the player's right hand and hides the gravity gun's world model.
void ShowHeldEmblem(int iClient, int iItem, int iWeapon)
{
	char sSkin[16];

	g_bHeldShown[iClient] = true;
	g_iHandItem[iClient] = iItem;
	g_iModdedWeaponRef[iClient] = EntIndexToEntRef(iWeapon);

	// Player models without the hand attachment keep the gravity gun, tinted in the emblem's color.
	if (LookupEntityAttachment(iClient, "anim_attachment_RH") < 1)
	{
		SetEntityRenderColor(iWeapon, g_Items[iItem].iColor[0], g_Items[iItem].iColor[1], g_Items[iItem].iColor[2], 255);

		return;
	}

	int iHand = CreateEntityByName("prop_dynamic_override");

	if (iHand == -1)
	{
		return;
	}

	IntToString(g_Items[iItem].iSkin, sSkin, sizeof(sSkin));

	DispatchKeyValue(iHand, "model", g_Items[iItem].sHandModel[0] != '\0' ? g_Items[iItem].sHandModel : g_Items[iItem].sModel);
	DispatchKeyValue(iHand, "solid", "0");
	DispatchKeyValue(iHand, "skin", sSkin);
	DispatchKeyValue(iHand, "classname", "cel_emblem_held");
	if (g_Items[iItem].fHandScale != 1.0)
	{
		DispatchKeyValueFloat(iHand, "modelscale", g_Items[iItem].fHandScale);
	}

	DispatchSpawn(iHand);

	SetEntityRenderColor(iHand, g_Items[iItem].iColor[0], g_Items[iItem].iColor[1], g_Items[iItem].iColor[2], 255);

	if (g_Items[iItem].bGlow)
	{
		SetEntityRenderFx(iHand, RENDERFX_GLOWSHELL);
	}

	SetVariantString("!activator");
	AcceptEntityInput(iHand, "SetParent", iClient, iHand);

	SetVariantString("anim_attachment_RH");
	AcceptEntityInput(iHand, "SetParentAttachment", iHand, iHand);

	// Once parented to the attachment these are relative to the player's right hand.
	SetLocalOffset(iHand, g_Items[iItem].fHandOffset, g_Items[iItem].fHandAngles);

	g_iHandEntRef[iClient] = EntIndexToEntRef(iHand);

	SDKHook(iHand, SDKHook_SetTransmit, Hook_HandTransmit);

	SetEntityRenderMode(iWeapon, RENDER_TRANSCOLOR);
	SetEntityRenderColor(iWeapon, 255, 255, 255, 0);
}

public Action Hook_HandTransmit(int iEntity, int iClient)
{
	// The holder does not see the attached emblem, it would float in their first person view.
	if (!g_cvShowSelf.BoolValue && iClient > 0 && iClient <= MaxClients && !g_bThirdPerson[iClient]
		&& iClient > 0 && iClient <= MaxClients && EntRefToEntIndex(g_iHandEntRef[iClient]) == iEntity)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

// Removes the held emblem and makes the gravity gun's world model visible again.
void RestoreWeapon(int iClient)
{
	int iHand = EntRefToEntIndex(g_iHandEntRef[iClient]);
	int iWeapon = EntRefToEntIndex(g_iModdedWeaponRef[iClient]);

	if (g_iHandEntRef[iClient] != INVALID_ENT_REFERENCE && iHand != INVALID_ENT_REFERENCE && iHand > MaxClients)
	{
		AcceptEntityInput(iHand, "ClearParent");
		AcceptEntityInput(iHand, "kill");
	}

	if (g_iModdedWeaponRef[iClient] != INVALID_ENT_REFERENCE && iWeapon != INVALID_ENT_REFERENCE && iWeapon > MaxClients)
	{
		SetEntityRenderMode(iWeapon, RENDER_NORMAL);
		SetEntityRenderColor(iWeapon, 255, 255, 255, 255);
	}

	g_bHeldShown[iClient] = false;
	g_iHandEntRef[iClient] = INVALID_ENT_REFERENCE;
	g_iHandItem[iClient] = -1;
	g_iModdedWeaponRef[iClient] = INVALID_ENT_REFERENCE;
}

//The setting is remembered between visits.
public void OnClientPostAdminCheck(int iClient)
{
	g_bWalkKeyOff[iClient] = (Cel_GetClientSettingInt(iClient, "walkkeyoff") == 1);
}

public Action Command_Speed(int iClient, int iArgs)
{
	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	g_bWalkKeyOff[iClient] = !g_bWalkKeyOff[iClient];

	Cel_SetClientSettingInt(iClient, "walkkeyoff", g_bWalkKeyOff[iClient] ? 1 : 0);

	if (g_bWalkKeyOff[iClient])
	{
		// Back to normal speed, so nobody is left stuck at a slow speed with the key turned off.
		g_iWalkTier[iClient] = WALK_NORMAL;
		g_bSpeedManaged[iClient] = true;

		Cel_ReplyToCommand(iClient, "The walk key no longer changes your walking speed. Your walking speed is now {green}normal{default}. Type {green}[tag]speed{default} to turn it back on.");
	} else {
		Cel_ReplyToCommand(iClient, "Tapping the walk key (left Alt) changes your walking speed again. Type {green}[tag]speed{default} to turn it off.");
	}

	return Plugin_Handled;
}

float WalkFactor(int iClient)
{
	float fFactor = g_fWalkTier[g_iWalkTier[iClient]];

	// No running faster than normal through a maze or parkour course.
	if (g_bInEvent[iClient] && fFactor > 1.0)
	{
		fFactor = 1.0;
	}

	return fFactor;
}

bool IsMovementPower(int iItem)
{
	return (StrEqual(g_Items[iItem].sPower, "speed") || StrEqual(g_Items[iItem].sPower, "sprint") || StrEqual(g_Items[iItem].sPower, "gravity") || StrEqual(g_Items[iItem].sPower, "jump")
		|| StrEqual(g_Items[iItem].sPower, "feather") || StrEqual(g_Items[iItem].sPower, "phase") || StrEqual(g_Items[iItem].sPower, "blink") || StrEqual(g_Items[iItem].sPower, "portal")
		|| g_Items[iItem].fJump > 0.0 || g_Items[iItem].fSpeed != 1.0);
}

bool IsShotPower(const char[] sPower)
{
	return (StrEqual(sPower, "fire") || StrEqual(sPower, "blizzard") || StrEqual(sPower, "shock") || StrEqual(sPower, "push") || StrEqual(sPower, "blast") || StrEqual(sPower, "blink")
		|| StrEqual(sPower, "flamethrower") || StrEqual(sPower, "shot") || StrEqual(sPower, "spray") || StrEqual(sPower, "medic") || StrEqual(sPower, "magnitude") || StrEqual(sPower, "chaos") || StrEqual(sPower, "portal") || StrEqual(sPower, "demon")
		|| StrEqual(sPower, "flash") || StrEqual(sPower, "smog") || StrEqual(sPower, "nuke"));
}

// Primary fire with a shot emblem: a beam from the player to whatever they are aiming at.
void FireEmblemShot(int iClient, int iItem)
{
	char sPower[24];
	float fAngles[3], fDirection[3], fEnd[3], fStart[3];
	int iColor[4], iTarget = -1;

	strcopy(sPower, sizeof(sPower), g_Items[iItem].sPower);

	GetClientEyePosition(iClient, fStart);
	GetClientEyeAngles(iClient, fAngles);

	GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);

	fEnd[0] = fStart[0] + fDirection[0] * g_Items[iItem].fRange;
	fEnd[1] = fStart[1] + fDirection[1] * g_Items[iItem].fRange;
	fEnd[2] = fStart[2] + fDirection[2] * g_Items[iItem].fRange;

	Handle hTrace = TR_TraceRayFilterEx(fStart, fEnd, MASK_SHOT, RayType_EndPoint, Filter_NotSelf, iClient);

	if (TR_DidHit(hTrace))
	{
		TR_GetEndPosition(fEnd, hTrace);

		iTarget = TR_GetEntityIndex(hTrace);
	}

	CloseHandle(hTrace);

	iColor[0] = g_Items[iItem].iBeamColor[0];
	iColor[1] = g_Items[iItem].iBeamColor[1];
	iColor[2] = g_Items[iItem].iBeamColor[2];
	iColor[3] = 255;

	if (StrEqual(sPower, "flamethrower"))
	{
		Flamethrower(iClient, iItem, fStart, fDirection);

		return;
	}

	if (StrEqual(sPower, "blink"))
	{
		BlinkPlayer(iClient, fStart, fDirection, fEnd, iColor);

		return;
	}

	if (StrEqual(sPower, "portal"))
	{
		SetPortal(iClient, 0, fEnd, fDirection, iColor);

		return;
	}

	// Demon: a tower of dark power bursts out of the ground where the player aims.
	if (StrEqual(sPower, "demon"))
	{
		DemonTower(iClient, iItem, fEnd, iColor);

		return;
	}

	// Solar: a flash of light that blinds everyone facing the holder.
	if (StrEqual(sPower, "flash"))
	{
		SolarFlash(iClient, iItem);

		return;
	}

	// Smog: a cloud of grey smoke that makes players inside it cough.
	if (StrEqual(sPower, "smog"))
	{
		SmogCloud(iClient, iItem, fEnd);

		return;
	}

	// Nuke: calls down a headcrab canister.
	if (StrEqual(sPower, "nuke"))
	{
		NukeStrike(iClient, iItem, fEnd);

		return;
	}

	fStart[2] -= 12.0;

	DrawShotEffect(iClient, iItem, fStart, fEnd, fDirection, iColor);

	if (StrEqual(sPower, "blast"))
	{
		int iExplosion = CreateEntityByName("env_explosion");

		if (iExplosion != -1)
		{
			DispatchKeyValueFloat(iExplosion, "iMagnitude", g_Items[iItem].fValue);
			DispatchKeyValue(iExplosion, "spawnflags", "0");

			SetEntPropEnt(iExplosion, Prop_Data, "m_hOwnerEntity", iClient);

			DispatchSpawn(iExplosion);

			TeleportEntity(iExplosion, fEnd, NULL_VECTOR, NULL_VECTOR);

			AcceptEntityInput(iExplosion, "Explode");
			AcceptEntityInput(iExplosion, "kill");
		}

		return;
	}

	// Pink: heals the player being aimed at.
	if (StrEqual(sPower, "medic"))
	{
		if (iTarget > 0 && iTarget <= MaxClients && IsClientInGame(iTarget) && IsPlayerAlive(iTarget) && GetClientHealth(iTarget) < 100)
		{
			int iHealth = GetClientHealth(iTarget) + RoundToFloor(g_Items[iItem].fValue);

			SetEntityHealth(iTarget, iHealth > 100 ? 100 : iHealth);

			EmitSoundToAll(SOUND_HEAL, iTarget);
		}

		return;
	}

	// Magnitude: throws what the player aims at. Only loose physics objects and players who can be hurt.
	if (StrEqual(sPower, "magnitude"))
	{
		ThrowTarget(iClient, iTarget, fDirection, g_Items[iItem].fValue);

		return;
	}

	// Chaos: an eruption that sets fire to everyone standing near where the player aims.
	if (StrEqual(sPower, "chaos"))
	{
		float fVictim[3];

		ChaosHill(iClient, iItem, fEnd);

		TE_SetupBeamRingPoint(fEnd, 10.0, g_Items[iItem].fValue * 2.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 1.0, 12.0, 0.0, iColor, 10, 0);
		TE_SendToAll();

		SpriteSpray(fEnd, g_fSkyward, g_Items[iItem].iSpriteIndex, 500, 0.6, 30);

		EmitSoundToAll(SOUND_FIRE, iClient);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (i == iClient || !IsClientInGame(i) || !IsPlayerAlive(i) || Cel_GetNoKill(i))
			{
				continue;
			}

			GetClientAbsOrigin(i, fVictim);

			if (GetVectorDistance(fVictim, fEnd) <= g_Items[iItem].fValue)
			{
				IgniteEntity(i, g_Items[iItem].fDuration);
			}
		}

		return;
	}

	if (StrEqual(sPower, "spray"))
	{
		return;
	}

	// Only players who can be hurt are affected, so players with !nokill enabled are left alone.
	if (iTarget < 1 || iTarget > MaxClients || !IsClientInGame(iTarget) || !IsPlayerAlive(iTarget) || Cel_GetNoKill(iTarget))
	{
		return;
	}

	if (StrEqual(sPower, "shot"))
	{
		if (g_Items[iItem].fValue > 0.0)
		{
			SDKHooks_TakeDamage(iTarget, iClient, iClient, g_Items[iItem].fValue, g_Items[iItem].iDamageType);
		}

		if (g_Items[iItem].fIgnite > 0.0)
		{
			IgniteEntity(iTarget, g_Items[iItem].fIgnite);
		}

		// Ice chills its target for a moment.
		if (g_Items[iItem].fSlow > 0.0)
		{
			g_fFrozenUntil[iTarget] = GetGameTime() + g_Items[iItem].fSlow;
			g_bFrozenTint[iTarget] = true;

			SetEntityRenderColor(iTarget, 90, 160, 255, 255);
		}

		// Water shoves its target back.
		if (g_Items[iItem].fKnockback > 0.0)
		{
			float fShove[3];

			fShove[0] = fDirection[0] * g_Items[iItem].fKnockback;
			fShove[1] = fDirection[1] * g_Items[iItem].fKnockback;
			fShove[2] = 120.0;

			TeleportEntity(iTarget, NULL_VECTOR, NULL_VECTOR, fShove);
		}
	} else if (StrEqual(sPower, "fire"))
	{
		IgniteEntity(iTarget, g_Items[iItem].fDuration);
	} else if (StrEqual(sPower, "blizzard"))
	{
		g_fFrozenUntil[iTarget] = GetGameTime() + g_Items[iItem].fDuration;
		g_bFrozenTint[iTarget] = true;

		SetEntityRenderColor(iTarget, 90, 160, 255, 255);
	} else if (StrEqual(sPower, "shock"))
	{
		SDKHooks_TakeDamage(iTarget, iClient, iClient, g_Items[iItem].fValue, DMG_SHOCK);
	} else if (StrEqual(sPower, "push"))
	{
		float fPush[3];

		fPush[0] = fDirection[0] * g_Items[iItem].fValue;
		fPush[1] = fDirection[1] * g_Items[iItem].fValue;
		fPush[2] = fDirection[2] * g_Items[iItem].fValue + 250.0;

		TeleportEntity(iTarget, NULL_VECTOR, NULL_VECTOR, fPush);
	}
}

// What a shot looks and sounds like. Each emblem picks a style with its "fx" key:
//   flame, ice, water, energy, smoke, orb  - sprites that fly from the player to the target
//   spray                                  - a burst of sprites thrown forward
//   laser, plasma, rainbow, beam           - beams
void DrawShotEffect(int iClient, int iItem, float fStart[3], float fEnd[3], float fDirection[3], int iColor[4])
{
	char sFx[16];
	float fUp[3] = { 0.0, 0.0, 1.0 };
	int iSprite = g_Items[iItem].iSpriteIndex;

	strcopy(sFx, sizeof(sFx), g_Items[iItem].sFx);

	if (StrEqual(sFx, "none"))
	{
		return;
	}

	// Each emblem's own style (see celmod_emblemfx.inc); the simpler styles below are kept for custom emblems.
	if (DrawStyledShot(iClient, iItem, sFx, fStart, fEnd, fDirection, iColor))
	{
		return;
	}

	if (StrEqual(sFx, "model"))
	{
		LaunchModel(iItem, fStart, fEnd, iColor, 1500.0);

		TE_SetupSparks(fEnd, fUp, 4, 2);
		TE_SendToAll();

		PlayShotSound(iClient, SOUND_SHOCK);
	} else if (StrEqual(sFx, "flame"))
	{
		LaunchSprite(iItem, fStart, fEnd, iColor, 1100.0, 0.6, false);
		SpriteSpray(fEnd, fUp, iSprite, 70, 0.6, 3);

		PlayShotSound(iClient, SOUND_FIRE);
	} else if (StrEqual(sFx, "ice"))
	{
		LaunchSprite(iItem, fStart, fEnd, iColor, 1300.0, 0.35, false);

		TE_SetupBeamRingPoint(fEnd, 2.0, 40.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.3, 3.0, 0.0, iColor, 10, 0);
		TE_SendToAll();

		PlayShotSound(iClient, SOUND_ICE);
	} else if (StrEqual(sFx, "water"))
	{
		LaunchSprite(iItem, fStart, fEnd, iColor, 900.0, 0.4, true);
		SpriteSpray(fEnd, fUp, iSprite, 140, 0.8, 4);

		PlayShotSound(iClient, SOUND_WATER);
	} else if (StrEqual(sFx, "energy"))
	{
		LaunchSprite(iItem, fStart, fEnd, iColor, 1600.0, 0.5, false);

		TE_SetupEnergySplash(fEnd, fUp, false);
		TE_SendToAll();

		PlayShotSound(iClient, SOUND_SHOCK);
	} else if (StrEqual(sFx, "smoke"))
	{
		LaunchSprite(iItem, fStart, fEnd, iColor, 500.0, 1.2, false);

		TE_SetupSmoke(fEnd, iSprite, 25.0, 8);
		TE_SendToAll();

		PlayShotSound(iClient, SOUND_STEAM);
	} else if (StrEqual(sFx, "orb"))
	{
		LaunchSprite(iItem, fStart, fEnd, iColor, 1400.0, 1.4, false);

		TE_SetupSparks(fEnd, fUp, 6, 4);
		TE_SendToAll();

		PlayShotSound(iClient, SOUND_SHOCK);
	} else if (StrEqual(sFx, "spray"))
	{
		SpriteSpray(fStart, fDirection, iSprite, 650, 0.25, 5);

		PlayShotSound(iClient, SOUND_STEAM);
	} else if (StrEqual(sFx, "laser"))
	{
		TE_SetupBeamPoints(fStart, fEnd, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.15, 2.0, 2.0, 1, 0.0, iColor, 20);
		TE_SendToAll();

		PlayShotSound(iClient, SOUND_SHOCK);
	} else if (StrEqual(sFx, "plasma"))
	{
		int iCore[4] = { 255, 255, 255, 255 };

		TE_SetupBeamPoints(fStart, fEnd, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.15, 10.0, 10.0, 1, 4.0, iColor, 30);
		TE_SendToAll();

		TE_SetupBeamPoints(fStart, fEnd, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.15, 3.0, 3.0, 1, 0.0, iCore, 30);
		TE_SendToAll();

		PlayShotSound(iClient, SOUND_SHOCK);
	} else if (StrEqual(sFx, "rainbow"))
	{
		int iRainbow[4], iRGB[3];

		HSVtoRGB(GetGameTime() * 240.0, 1.0, 1.0, iRGB);

		iRainbow[0] = iRGB[0];
		iRainbow[1] = iRGB[1];
		iRainbow[2] = iRGB[2];
		iRainbow[3] = 255;

		TE_SetupBeamPoints(fStart, fEnd, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.2, 6.0, 6.0, 1, 1.0, iRainbow, 20);
		TE_SendToAll();

		PlayShotSound(iClient, SOUND_SHOCK);
	} else {
		TE_SetupBeamPoints(fStart, fEnd, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.3, 6.0, 2.0, 1, 2.0, iColor, 20);
		TE_SendToAll();

		TE_SetupBeamRingPoint(fEnd, 4.0, 60.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.4, 5.0, 0.0, iColor, 10, 0);
		TE_SendToAll();

		PlayShotSound(iClient, SOUND_SHOCK);
	}
}

// Fast firing emblems would otherwise stack the same sound many times a second.
void PlayShotSound(int iClient, const char[] sSound)
{
	if (GetGameTime() >= g_fNextShotSound[iClient])
	{
		g_fNextShotSound[iClient] = GetGameTime() + 0.6;

		EmitSoundToAll(sSound, iClient);
	}
}

// A sprite that flies from one point to another and removes itself on arrival.
int LaunchSprite(int iItem, float fStart[3], float fEnd[3], int iColor[4], float fSpeed, float fScale, bool bGravity)
{
	char sBuffer[64];

	float fDistance = GetVectorDistance(fStart, fEnd);

	// Nothing to show at point blank range, and never spawn sprites when the map is nearly out of entities.
	if (fDistance < 24.0 || GetEntityCount() > GetMaxEntities() - 200)
	{
		return -1;
	}

	int iSprite = CreateEntityByName("env_sprite");

	if (iSprite == -1)
	{
		return -1;
	}

	float fLife = fDistance / fSpeed;

	DispatchKeyValue(iSprite, "model", g_Items[iItem].sSprite);
	DispatchKeyValue(iSprite, "rendermode", "5");
	DispatchKeyValue(iSprite, "renderamt", "255");
	DispatchKeyValue(iSprite, "framerate", "15");
	DispatchKeyValue(iSprite, "spawnflags", "1");
	DispatchKeyValue(iSprite, "classname", "cel_emblem_shot");

	Format(sBuffer, sizeof(sBuffer), "%d %d %d", iColor[0], iColor[1], iColor[2]);
	DispatchKeyValue(iSprite, "rendercolor", sBuffer);

	DispatchKeyValueFloat(iSprite, "scale", fScale);

	DispatchSpawn(iSprite);

	// Moved along its path every frame: a sprite does not move by itself.
	TeleportEntity(iSprite, fStart, NULL_VECTOR, NULL_VECTOR);

	StartMover(iSprite, fStart, fEnd, fLife, bGravity, true);

	return iSprite;
}

// A burst of sprites thrown in a direction, they fall and fade on their own.
void SpriteSpray(float fOrigin[3], float fDirection[3], int iModelIndex, int iSpeed, float fNoise, int iCount)
{
	float fPos[3];

	if (iModelIndex < 1)
	{
		return;
	}

	if (iCount > 14)
	{
		iCount = 14;
	}

	float fReach = iSpeed * 0.25;

	for (int i = 0; i < iCount; i++)
	{
		float fAlong = GetRandomFloat(0.0, fReach);
		float fSpread = fReach * (0.15 + fNoise);

		fPos[0] = fOrigin[0] + fDirection[0] * fAlong + GetRandomFloat(-fSpread, fSpread) * 0.5;
		fPos[1] = fOrigin[1] + fDirection[1] * fAlong + GetRandomFloat(-fSpread, fSpread) * 0.5;
		fPos[2] = fOrigin[2] + fDirection[2] * fAlong + GetRandomFloat(-fSpread, fSpread) * 0.5;

		TE_SetupGlowSprite(fPos, iModelIndex, GetRandomFloat(0.25, 0.6), GetRandomFloat(0.4, 1.2), 220);
		TE_SendToAll();
	}
}

// Where the player is aiming, up to a range. Returns what was hit, or -1.
int TraceEmblemAim(int iClient, float fRange, float fStart[3], float fDirection[3], float fEnd[3])
{
	float fAngles[3];
	int iTarget = -1;

	GetClientEyePosition(iClient, fStart);
	GetClientEyeAngles(iClient, fAngles);

	GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);

	fEnd[0] = fStart[0] + fDirection[0] * fRange;
	fEnd[1] = fStart[1] + fDirection[1] * fRange;
	fEnd[2] = fStart[2] + fDirection[2] * fRange;

	Handle hTrace = TR_TraceRayFilterEx(fStart, fEnd, MASK_SHOT, RayType_EndPoint, Filter_NotSelf, iClient);

	if (TR_DidHit(hTrace))
	{
		TR_GetEndPosition(fEnd, hTrace);

		iTarget = TR_GetEntityIndex(hTrace);
	}

	CloseHandle(hTrace);

	return iTarget;
}

bool CanBeHurt(int iAttacker, int iVictim)
{
	return (iVictim > 0 && iVictim <= MaxClients && iVictim != iAttacker && IsClientInGame(iVictim) && IsPlayerAlive(iVictim) && !Cel_GetNoKill(iVictim));
}

void CreateExplosion(int iClient, float fOrigin[3], float fMagnitude)
{
	int iExplosion = CreateEntityByName("env_explosion");

	if (iExplosion == -1)
	{
		return;
	}

	DispatchKeyValueFloat(iExplosion, "iMagnitude", fMagnitude);
	DispatchKeyValue(iExplosion, "spawnflags", "0");

	SetEntPropEnt(iExplosion, Prop_Data, "m_hOwnerEntity", iClient);

	DispatchSpawn(iExplosion);

	TeleportEntity(iExplosion, fOrigin, NULL_VECTOR, NULL_VECTOR);

	AcceptEntityInput(iExplosion, "Explode");
	AcceptEntityInput(iExplosion, "kill");
}

// Fire: a short stream of flames from the emblem that burns everyone caught in it.
void Flamethrower(int iClient, int iItem, float fStart[3], float fDirection[3])
{
	float fMuzzle[3], fToVictim[3], fVictim[3];

	fMuzzle[0] = fStart[0] + fDirection[0] * 30.0;
	fMuzzle[1] = fStart[1] + fDirection[1] * 30.0;
	fMuzzle[2] = fStart[2] + fDirection[2] * 30.0 - 12.0;

	// A stream of flames that grows wider further from the emblem.
	for (int i = 0; i < 6; i++)
	{
		float fFlame[3];
		float fAlong = g_Items[iItem].fRange * (i + GetRandomFloat(0.0, 1.0)) / 6.0;
		float fSpread = 4.0 + fAlong * 0.12;

		fFlame[0] = fMuzzle[0] + fDirection[0] * fAlong + GetRandomFloat(-fSpread, fSpread);
		fFlame[1] = fMuzzle[1] + fDirection[1] * fAlong + GetRandomFloat(-fSpread, fSpread);
		fFlame[2] = fMuzzle[2] + fDirection[2] * fAlong + GetRandomFloat(-fSpread, fSpread);

		TE_SetupGlowSprite(fFlame, g_Items[iItem].iSpriteIndex, GetRandomFloat(0.1, 0.2), 0.25 + fAlong / g_Items[iItem].fRange * 1.1, 230);
		TE_SendToAll();
	}

	// A rippling heat haze through the flames and the glow they throw on the walls around them.
	float fFar[3], fMid[3];
	int iHeat[4];

	for (int k = 0; k < 3; k++)
	{
		fFar[k] = fMuzzle[k] + fDirection[k] * g_Items[iItem].fRange;
		fMid[k] = fMuzzle[k] + fDirection[k] * g_Items[iItem].fRange * 0.5;
	}

	iHeat[0] = g_Items[iItem].iBeamColor[0];
	iHeat[1] = g_Items[iItem].iBeamColor[1];
	iHeat[2] = g_Items[iItem].iBeamColor[2];
	iHeat[3] = 160;

	Fx_Beam(fMuzzle, fFar, g_iBmPhys, 6.0, 40.0, 0.15, 4.0, iHeat, 0, 30);

	if (GetRandomInt(0, 2) == 0)
	{
		Fx_Light(fMid, iHeat, 200.0, 0.4, 5);
	}

	PlayShotSound(iClient, SOUND_FLAME);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!CanBeHurt(iClient, i))
		{
			continue;
		}

		GetClientAbsOrigin(i, fVictim);

		fVictim[2] += 40.0;

		MakeVectorFromPoints(fStart, fVictim, fToVictim);

		float fDistance = NormalizeVector(fToVictim, fToVictim);

		// Inside the range and inside a cone of about 25 degrees around the aim.
		if (fDistance > g_Items[iItem].fRange || GetVectorDotProduct(fToVictim, fDirection) < 0.9)
		{
			continue;
		}

		// Walls block the flames.
		Handle hTrace = TR_TraceRayFilterEx(fStart, fVictim, MASK_SOLID, RayType_EndPoint, Filter_WorldOnly, 0);

		bool bBlocked = TR_DidHit(hTrace);

		CloseHandle(hTrace);

		if (bBlocked)
		{
			continue;
		}

		SDKHooks_TakeDamage(i, iClient, iClient, g_Items[iItem].fValue, DMG_BURN);

		if (g_Items[iItem].fIgnite > 0.0)
		{
			IgniteEntity(i, g_Items[iItem].fIgnite);
		}
	}
}

// A model that flies from one point to another and removes itself on arrival (the Errors fire error models).
void LaunchModel(int iItem, float fStart[3], float fEnd[3], int iColor[4], float fSpeed)
{
	char sBuffer[64];
	float fAngles[3], fVelocity[3];

	float fDistance = GetVectorDistance(fStart, fEnd);

	if (fDistance < 24.0 || GetEntityCount() > GetMaxEntities() - 200)
	{
		return;
	}

	int iModel = CreateEntityByName("prop_dynamic_override");

	if (iModel == -1)
	{
		return;
	}

	float fLife = fDistance / fSpeed;

	DispatchKeyValue(iModel, "model", g_Items[iItem].sSprite);
	DispatchKeyValue(iModel, "solid", "0");
	DispatchKeyValue(iModel, "classname", "cel_emblem_shot");

	DispatchSpawn(iModel);

	SetEntityRenderColor(iModel, iColor[0], iColor[1], iColor[2], 255);

	MakeVectorFromPoints(fStart, fEnd, fVelocity);
	GetVectorAngles(fVelocity, fAngles);

	TeleportEntity(iModel, fStart, fAngles, NULL_VECTOR);

	StartMover(iModel, fStart, fEnd, fLife, false, true);
}

// Things that fly along a path (shots, the Nuke's canister) are moved here every server frame, because the
// entities used for them do not move by themselves.
#define MAX_MOVERS 128

int g_iMoverRef[MAX_MOVERS] = { INVALID_ENT_REFERENCE, ... };
bool g_bMoverArc[MAX_MOVERS];
bool g_bMoverKill[MAX_MOVERS];
float g_fMoverBegin[MAX_MOVERS];
float g_fMoverEnd[MAX_MOVERS][3];
float g_fMoverLife[MAX_MOVERS];
float g_fMoverStart[MAX_MOVERS][3];

void StartMover(int iEntity, float fStart[3], float fEnd[3], float fLife, bool bArc, bool bKillAtEnd)
{
	for (int i = 0; i < MAX_MOVERS; i++)
	{
		if (EntRefToEntIndex(g_iMoverRef[i]) != INVALID_ENT_REFERENCE)
		{
			continue;
		}

		g_iMoverRef[i] = EntIndexToEntRef(iEntity);
		g_fMoverStart[i] = fStart;
		g_fMoverEnd[i] = fEnd;
		g_fMoverBegin[i] = GetGameTime();
		g_fMoverLife[i] = fLife > 0.05 ? fLife : 0.05;
		g_bMoverArc[i] = bArc;
		g_bMoverKill[i] = bKillAtEnd;

		return;
	}

	// Too many things in the air at once: this one is simply removed.
	AcceptEntityInput(iEntity, "kill");
}

public void OnGameFrame()
{
	float fPos[3];
	float fNow = GetGameTime();

	UpdateThirdPersonCameras();

	for (int i = 0; i < MAX_MOVERS; i++)
	{
		if (g_iMoverRef[i] == INVALID_ENT_REFERENCE)
		{
			continue;
		}

		int iEntity = EntRefToEntIndex(g_iMoverRef[i]);

		if (iEntity == INVALID_ENT_REFERENCE)
		{
			g_iMoverRef[i] = INVALID_ENT_REFERENCE;
			continue;
		}

		float fT = (fNow - g_fMoverBegin[i]) / g_fMoverLife[i];

		if (fT >= 1.0)
		{
			g_iMoverRef[i] = INVALID_ENT_REFERENCE;

			if (g_bMoverKill[i])
			{
				AcceptEntityInput(iEntity, "kill");
			} else {
				TeleportEntity(iEntity, g_fMoverEnd[i], NULL_VECTOR, NULL_VECTOR);
			}

			continue;
		}

		for (int k = 0; k < 3; k++)
		{
			fPos[k] = g_fMoverStart[i][k] + (g_fMoverEnd[i][k] - g_fMoverStart[i][k]) * fT;
		}

		// Arcing shots (water) rise and fall on the way.
		if (g_bMoverArc[i])
		{
			fPos[2] += 4.0 * GetVectorDistance(g_fMoverStart[i], g_fMoverEnd[i]) * 0.12 * fT * (1.0 - fT);
		}

		TeleportEntity(iEntity, fPos, NULL_VECTOR, NULL_VECTOR);
	}
}

// Ends phasing once the player is clear of walls and props; while still inside something they stay phased.
void StopPhasing(int iClient)
{
	float fMaxs[3], fMins[3], fOrigin[3];

	if (!IsClientInGame(iClient) || !IsPlayerAlive(iClient))
	{
		g_bPhasing[iClient] = false;

		return;
	}

	GetClientAbsOrigin(iClient, fOrigin);
	GetClientMins(iClient, fMins);
	GetClientMaxs(iClient, fMaxs);

	Handle hTrace = TR_TraceHullFilterEx(fOrigin, fOrigin, fMins, fMaxs, MASK_PLAYERSOLID, Filter_NotSelf, iClient);

	bool bStuck = TR_DidHit(hTrace);

	CloseHandle(hTrace);

	if (bStuck)
	{
		return;
	}

	g_bPhasing[iClient] = false;

	if (GetEntityMoveType(iClient) == MOVETYPE_NOCLIP)
	{
		SetEntityMoveType(iClient, MOVETYPE_WALK);
	}
}

// Removes an entity after a delay, without a timer of our own.
void KillAfter(int iEntity, float fDelay)
{
	char sBuffer[64];

	Format(sBuffer, sizeof(sBuffer), "OnUser2 !self:Kill::%.2f:1", fDelay);

	SetVariantString(sBuffer);
	AcceptEntityInput(iEntity, "AddOutput");
	AcceptEntityInput(iEntity, "FireUser2");
}

// Demon: a column of dark power rises out of the ground and throws everyone standing on it.
void DemonTower(int iClient, int iItem, float fEnd[3], int iColor[4])
{
	float fBase[3], fDown[3], fTop[3], fVictim[3];

	// The tower always starts on the ground below where the player aims.
	fDown = fEnd;
	fDown[2] -= 2000.0;

	Handle hTrace = TR_TraceRayFilterEx(fEnd, fDown, MASK_SOLID, RayType_EndPoint, Filter_WorldOnly, 0);

	fBase = fEnd;

	if (TR_DidHit(hTrace))
	{
		TR_GetEndPosition(fBase, hTrace);
	}

	CloseHandle(hTrace);

	fTop = fBase;
	fTop[2] += 360.0;

	for (int i = 0; i < 3; i++)
	{
		float fA[3], fB[3];

		fA = fBase;
		fB = fTop;

		fA[0] += Cosine(i * 2.094) * 20.0;
		fA[1] += Sine(i * 2.094) * 20.0;
		fB[0] = fA[0];
		fB[1] = fA[1];

		TE_SetupBeamPoints(fA, fB, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.6, 18.0, 4.0, 1, 6.0, iColor, 20);
		TE_SendToAll();
	}

	TE_SetupBeamRingPoint(fBase, 8.0, 160.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.6, 10.0, 0.0, iColor, 10, 0);
	TE_SendToAll();

	SpriteSpray(fBase, g_fSkyward, g_Items[iItem].iSpriteIndex, 500, 0.15, 16);

	EmitSoundToAll(SOUND_FIRE, iClient);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!CanBeHurt(iClient, i))
		{
			continue;
		}

		GetClientAbsOrigin(i, fVictim);

		if (GetVectorDistance(fVictim, fBase) > 80.0)
		{
			continue;
		}

		float fThrow[3] = { 0.0, 0.0, 500.0 };

		TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, fThrow);

		SDKHooks_TakeDamage(i, iClient, iClient, g_Items[iItem].fValue, DMG_ENERGYBEAM);
	}
}

// Solar: blinds everyone who can see the holder and is facing them, like a combine scanner's flash.
void SolarFlash(int iClient, int iItem)
{
	float fEyes[3], fFacing[3], fOtherEyes[3], fToHolder[3];

	GetClientEyePosition(iClient, fEyes);

	TE_SetupGlowSprite(fEyes, g_Items[iItem].iSpriteIndex, 0.4, 4.0, 255);
	TE_SendToAll();

	EmitSoundToAll(SOUND_FLASH, iClient);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == iClient || !IsClientInGame(i) || !IsPlayerAlive(i) || IsFakeClient(i))
		{
			continue;
		}

		GetClientEyePosition(i, fOtherEyes);

		if (GetVectorDistance(fEyes, fOtherEyes) > g_Items[iItem].fRange)
		{
			continue;
		}

		// Only players looking towards the holder are blinded.
		float fAngles[3];

		GetClientEyeAngles(i, fAngles);
		GetAngleVectors(fAngles, fFacing, NULL_VECTOR, NULL_VECTOR);

		MakeVectorFromPoints(fOtherEyes, fEyes, fToHolder);
		NormalizeVector(fToHolder, fToHolder);

		if (GetVectorDotProduct(fFacing, fToHolder) < 0.5)
		{
			continue;
		}

		Handle hTrace = TR_TraceRayFilterEx(fOtherEyes, fEyes, MASK_SOLID, RayType_EndPoint, Filter_WorldOnly, 0);

		bool bBlocked = TR_DidHit(hTrace);

		CloseHandle(hTrace);

		if (bBlocked)
		{
			continue;
		}

		int iHold = RoundToFloor(g_Items[iItem].fDuration * 1000.0);

		Client_ScreenFade(i, 1500, FFADE_IN | FFADE_PURGE, iHold, 255, 255, 255, 255);
	}
}

// Smog: a cloud of grey smoke that lasts a while. Everyone inside coughs and takes damage every second.
void SmogCloud(int iClient, int iItem, float fEnd[3])
{
	char sColor[32];

	// One cloud per player at a time.
	int iOldest = -1;
	int iCount = 0;

	for (int i = 0; i < 3; i++)
	{
		if (EntRefToEntIndex(g_iSmogRef[iClient][i]) != INVALID_ENT_REFERENCE)
		{
			iCount++;
		} else if (iOldest == -1)
		{
			iOldest = i;
		}
	}

	if (iCount >= 1)
	{
		EmitSoundToClient(iClient, SOUND_DENY);

		return;
	}

	int iSmoke = CreateEntityByName("env_smokestack");

	if (iSmoke == -1)
	{
		return;
	}

	Format(sColor, sizeof(sColor), "%d %d %d", g_Items[iItem].iColor[0] + 30, g_Items[iItem].iColor[1] + 30, g_Items[iItem].iColor[2] + 30);

	DispatchKeyValue(iSmoke, "BaseSpread", "60");
	DispatchKeyValue(iSmoke, "SpreadSpeed", "12");
	DispatchKeyValue(iSmoke, "Speed", "18");
	DispatchKeyValue(iSmoke, "StartSize", "40");
	DispatchKeyValue(iSmoke, "EndSize", "90");
	DispatchKeyValue(iSmoke, "Rate", "18");
	DispatchKeyValue(iSmoke, "JetLength", "90");
	DispatchKeyValue(iSmoke, "Twist", "8");
	DispatchKeyValue(iSmoke, "SmokeMaterial", "particle/SmokeStack.vmt");
	DispatchKeyValue(iSmoke, "rendercolor", sColor);
	DispatchKeyValue(iSmoke, "renderamt", "220");
	DispatchKeyValue(iSmoke, "classname", "cel_smog");

	DispatchSpawn(iSmoke);

	TeleportEntity(iSmoke, fEnd, NULL_VECTOR, NULL_VECTOR);

	AcceptEntityInput(iSmoke, "TurnOn");

	KillAfter(iSmoke, g_Items[iItem].fDuration);

	g_iSmogRef[iClient][iOldest] = EntIndexToEntRef(iSmoke);
	g_iSmogItem[iClient][iOldest] = iItem;

	EmitSoundToAll(SOUND_STEAM, iClient, SNDCHAN_AUTO, SNDLEVEL_CONVO, SND_NOFLAGS, 0.5);
}

// Once a second: everyone standing in someone's smog coughs and is hurt.
void ThinkSmog()
{
	char sCough[64];
	float fCloud[3], fVictim[3];

	for (int iOwner = 1; iOwner <= MaxClients; iOwner++)
	{
		for (int c = 0; c < 3; c++)
		{
			int iSmoke = EntRefToEntIndex(g_iSmogRef[iOwner][c]);

			if (iSmoke == INVALID_ENT_REFERENCE)
			{
				continue;
			}

			int iItem = g_iSmogItem[iOwner][c];

			GetEntPropVector(iSmoke, Prop_Data, "m_vecAbsOrigin", fCloud);

			for (int i = 1; i <= MaxClients; i++)
			{
				if (!IsClientInGame(i) || !IsPlayerAlive(i) || Cel_GetNoKill(i) || (i == iOwner))
				{
					continue;
				}

				GetClientEyePosition(i, fVictim);

				if (GetVectorDistance(fVictim, fCloud) > 160.0)
				{
					continue;
				}

				// A cough now and then, not one every second from everyone in the cloud.
				if (GetGameTime() >= g_fNextCough[i])
				{
					g_fNextCough[i] = GetGameTime() + GetRandomFloat(2.5, 4.5);

					Format(sCough, sizeof(sCough), "ambient/voices/cough%d.wav", GetRandomInt(1, 4));

					EmitSoundToAll(sCough, i, SNDCHAN_VOICE, SNDLEVEL_CONVO, SND_NOFLAGS, 0.6);
				}

				if (IsClientInGame(iOwner))
				{
					SDKHooks_TakeDamage(i, iOwner, iOwner, (iItem >= 0 && iItem < g_iItemCount) ? g_Items[iItem].fValue : 1.0, DMG_POISON);
				}
			}
		}
	}
}

// Chaos: an antlion hill bursts out of the ground with fire pouring from its top, then sinks back down.
void ChaosHill(int iClient, int iItem, float fEnd[3])
{
	float fDown[3], fGround[3];

	fDown = fEnd;
	fDown[2] -= 2000.0;

	Handle hTrace = TR_TraceRayFilterEx(fEnd, fDown, MASK_SOLID, RayType_EndPoint, Filter_WorldOnly, 0);

	fGround = fEnd;

	if (TR_DidHit(hTrace))
	{
		TR_GetEndPosition(fGround, hTrace);
	}

	CloseHandle(hTrace);

	int iHill = CreateEntityByName("prop_dynamic_override");

	if (iHill == -1)
	{
		return;
	}

	DispatchKeyValue(iHill, "model", "models/props_wasteland/antlionhill.mdl");
	DispatchKeyValue(iHill, "solid", "0");
	DispatchKeyValue(iHill, "classname", "cel_chaoshill");

	DispatchSpawn(iHill);

	float fStart[3];

	fStart = fGround;
	fStart[2] -= 220.0;

	TeleportEntity(iHill, fStart, NULL_VECTOR, NULL_VECTOR);

	int iFire = CreateEntityByName("env_fire");

	if (iFire != -1)
	{
		float fTop[3];

		fTop = fGround;
		fTop[2] += 40.0;

		DispatchKeyValue(iFire, "firesize", "96");
		DispatchKeyValue(iFire, "fireattack", "1");
		DispatchKeyValue(iFire, "damagescale", "0");
		DispatchKeyValue(iFire, "health", "6");
		DispatchKeyValue(iFire, "spawnflags", "133");

		DispatchSpawn(iFire);

		TeleportEntity(iFire, fTop, NULL_VECTOR, NULL_VECTOR);

		AcceptEntityInput(iFire, "StartFire");

		KillAfter(iFire, g_Items[iItem].fDuration);
	}

	KillAfter(iHill, g_Items[iItem].fDuration + 1.0);

	DataPack dpHill;

	CreateDataTimer(0.05, Timer_ChaosHill, dpHill, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	dpHill.WriteCell(EntIndexToEntRef(iHill));
	dpHill.WriteFloat(fGround[2]);
	dpHill.WriteFloat(GetGameTime());
	dpHill.WriteFloat(g_Items[iItem].fDuration);
}

// Raises the hill over a second, holds it, then lowers it again.
public Action Timer_ChaosHill(Handle hTimer, DataPack dpHill)
{
	float fOrigin[3];

	dpHill.Reset();

	int iHill = EntRefToEntIndex(dpHill.ReadCell());
	float fGround = dpHill.ReadFloat();
	float fStarted = dpHill.ReadFloat();
	float fDuration = dpHill.ReadFloat();

	if (iHill == INVALID_ENT_REFERENCE)
	{
		return Plugin_Stop;
	}

	float fAge = GetGameTime() - fStarted;
	float fRise = 1.0;

	if (fAge < 1.0)
	{
		fRise = fAge;
	} else if (fAge > fDuration)
	{
		fRise = 1.0 - (fAge - fDuration);
	}

	if (fRise < 0.0)
	{
		fRise = 0.0;
	}

	GetEntPropVector(iHill, Prop_Data, "m_vecAbsOrigin", fOrigin);

	fOrigin[2] = fGround - 220.0 + 160.0 * fRise;

	TeleportEntity(iHill, fOrigin, NULL_VECTOR, NULL_VECTOR);

	return (fAge > fDuration + 1.0) ? Plugin_Stop : Plugin_Continue;
}

// Nuke: a headcrab canister falls from the sky where the player aims. On impact it unfreezes and scatters
// every prop around it, as it did on the original server. cm_nuke_wrecks_builds 0 keeps builds safe.
void NukeStrike(int iClient, int iItem, float fEnd[3])
{
	float fAngles[3], fDirection[3], fStart[3], fVelocity[3];

	// It comes in steeply from a random side, starting as high as the open space above allows.
	fAngles[0] = 65.0;
	fAngles[1] = GetRandomFloat(0.0, 360.0);

	GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);

	fStart[0] = fEnd[0] - fDirection[0] * 2000.0;
	fStart[1] = fEnd[1] - fDirection[1] * 2000.0;
	fStart[2] = fEnd[2] - fDirection[2] * 2000.0;

	Handle hTrace = TR_TraceRayFilterEx(fEnd, fStart, MASK_SOLID, RayType_EndPoint, Filter_WorldOnly, 0);

	if (TR_DidHit(hTrace))
	{
		TR_GetEndPosition(fStart, hTrace);
	}

	CloseHandle(hTrace);

	float fDistance = GetVectorDistance(fStart, fEnd);

	if (fDistance < 200.0)
	{
		// No room above: it simply drops in from a short way up.
		fDistance = 200.0;
	}

	float fFlight = fDistance / 1800.0;

	int iCanister = CreateEntityByName("prop_dynamic_override");

	if (iCanister == -1)
	{
		return;
	}

	DispatchKeyValue(iCanister, "model", g_sCanisterModel);
	DispatchKeyValue(iCanister, "solid", "0");
	DispatchKeyValue(iCanister, "classname", "cel_nuke");

	DispatchSpawn(iCanister);

	float fFacing[3];

	fFacing[0] = fAngles[0];
	fFacing[1] = fAngles[1];

	fVelocity[0] = fDirection[0] * 1800.0;
	fVelocity[1] = fDirection[1] * 1800.0;
	fVelocity[2] = fDirection[2] * 1800.0;

	TeleportEntity(iCanister, fStart, fFacing, NULL_VECTOR);

	StartMover(iCanister, fStart, fEnd, fFlight, false, true);

	// A smoke trail behind it.
	int iTrail = CreateEntityByName("env_smoketrail");

	if (iTrail != -1)
	{
		DispatchKeyValue(iTrail, "opacity", "0.6");
		DispatchKeyValue(iTrail, "spawnrate", "40");
		DispatchKeyValue(iTrail, "lifetime", "2");
		DispatchKeyValue(iTrail, "startcolor", "180 180 180");
		DispatchKeyValue(iTrail, "endcolor", "60 60 60");
		DispatchKeyValue(iTrail, "startsize", "24");
		DispatchKeyValue(iTrail, "endsize", "80");
		DispatchKeyValue(iTrail, "spawnradius", "8");

		DispatchSpawn(iTrail);

		TeleportEntity(iTrail, fStart, NULL_VECTOR, NULL_VECTOR);

		SetVariantString("!activator");
		AcceptEntityInput(iTrail, "SetParent", iCanister, iTrail);
	}

	EmitSoundToAll(SOUND_CANISTER, iCanister);

	DataPack dpNuke;

	CreateDataTimer(fFlight, Timer_NukeImpact, dpNuke, TIMER_FLAG_NO_MAPCHANGE);

	dpNuke.WriteCell(GetClientUserId(iClient));
	dpNuke.WriteCell(iItem);
	dpNuke.WriteFloat(fEnd[0]);
	dpNuke.WriteFloat(fEnd[1]);
	dpNuke.WriteFloat(fEnd[2]);
	dpNuke.WriteFloat(fAngles[1]);
}

public Action Timer_NukeImpact(Handle hTimer, DataPack dpNuke)
{
	float fImpact[3], fOrigin[3], fPush[3];
	int iCount = 0;

	dpNuke.Reset();

	int iClient = GetClientOfUserId(dpNuke.ReadCell());
	int iItem = dpNuke.ReadCell();

	fImpact[0] = dpNuke.ReadFloat();
	fImpact[1] = dpNuke.ReadFloat();
	fImpact[2] = dpNuke.ReadFloat();

	float fYaw = dpNuke.ReadFloat();

	// The blast. Damage counts as the caller's, so kills are theirs.
	CreateExplosion(iClient > 0 ? iClient : 0, fImpact, (iItem >= 0 && iItem < g_iItemCount) ? g_Items[iItem].fValue : 150.0);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		GetClientAbsOrigin(i, fOrigin);

		if (GetVectorDistance(fOrigin, fImpact) <= 1200.0)
		{
			Client_Shake(i, SHAKE_START, 25.0, 150.0, 2.0);
		}
	}

	// The spent canister stays stuck in the ground for a while, smoking.
	int iWreck = CreateEntityByName("prop_dynamic_override");

	if (iWreck != -1)
	{
		float fWreckAngles[3];

		fWreckAngles[0] = 65.0;
		fWreckAngles[1] = fYaw;

		DispatchKeyValue(iWreck, "model", g_sCanisterModel);
		DispatchKeyValue(iWreck, "solid", "0");
		DispatchKeyValue(iWreck, "classname", "cel_nuke_wreck");

		DispatchSpawn(iWreck);

		TeleportEntity(iWreck, fImpact, fWreckAngles, NULL_VECTOR);

		KillAfter(iWreck, 20.0);
	}

	int iSmoke = CreateEntityByName("env_smokestack");

	if (iSmoke != -1)
	{
		DispatchKeyValue(iSmoke, "BaseSpread", "30");
		DispatchKeyValue(iSmoke, "SpreadSpeed", "10");
		DispatchKeyValue(iSmoke, "Speed", "60");
		DispatchKeyValue(iSmoke, "StartSize", "30");
		DispatchKeyValue(iSmoke, "EndSize", "90");
		DispatchKeyValue(iSmoke, "Rate", "12");
		DispatchKeyValue(iSmoke, "JetLength", "220");
		DispatchKeyValue(iSmoke, "SmokeMaterial", "particle/SmokeStack.vmt");
		DispatchKeyValue(iSmoke, "rendercolor", "90 90 90");
		DispatchKeyValue(iSmoke, "renderamt", "200");

		DispatchSpawn(iSmoke);

		TeleportEntity(iSmoke, fImpact, NULL_VECTOR, NULL_VECTOR);

		AcceptEntityInput(iSmoke, "TurnOn");

		KillAfter(iSmoke, 15.0);
	}

	if (!g_cvNukeWrecks.BoolValue)
	{
		return Plugin_Stop;
	}

	// Everything loose or frozen nearby is unfrozen and thrown, as on the original server.
	for (int i = MaxClients + 1; i <= MAXENTITIES && iCount < g_cvNukeMaxProps.IntValue; i++)
	{
		if (!IsValidEntity(i) || !Cel_IsEntity(i) || GetEntityMoveType(i) != MOVETYPE_VPHYSICS)
		{
			continue;
		}

		Cel_GetEntityOrigin(i, fOrigin);

		float fDistance = GetVectorDistance(fOrigin, fImpact);

		if (fDistance > 400.0)
		{
			continue;
		}

		Cel_SetMotion(i, true);

		MakeVectorFromPoints(fImpact, fOrigin, fPush);
		NormalizeVector(fPush, fPush);

		float fForce = 1400.0 * (1.0 - fDistance / 500.0);

		fPush[0] *= fForce;
		fPush[1] *= fForce;
		fPush[2] = fPush[2] * fForce + 500.0;

		TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, fPush);

		iCount++;
	}

	return Plugin_Stop;
}

// Right click attacks chosen with the "secondary" key.
void SecondaryAttack(int iClient, int iItem)
{
	float fDirection[3], fEnd[3], fStart[3], fVictim[3];
	int iColor[4];

	iColor[0] = g_Items[iItem].iBeamColor[0];
	iColor[1] = g_Items[iItem].iBeamColor[1];
	iColor[2] = g_Items[iItem].iBeamColor[2];
	iColor[3] = 255;

	// Fireball: a ball of fire that flies until it hits something, then explodes and sets people alight.
	if (StrEqual(g_Items[iItem].sSecondary, "fireball"))
	{
		LaunchFireball(iClient, iItem, iColor);

		return;
	}

	// Ice storm: a burst of ice where the player aims that hurts and slows everyone near it.
	if (StrEqual(g_Items[iItem].sSecondary, "icestorm"))
	{
		TraceEmblemAim(iClient, 800.0, fStart, fDirection, fEnd);

		TE_SetupBeamRingPoint(fEnd, 10.0, 320.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.8, 10.0, 0.0, iColor, 10, 0);
		TE_SendToAll();

		SpriteSpray(fEnd, g_fSkyward, g_Items[iItem].iSpriteIndex, 350, 0.9, 30);

		EmitSoundToAll(SOUND_ICE, iClient);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (!CanBeHurt(iClient, i))
			{
				continue;
			}

			GetClientAbsOrigin(i, fVictim);

			if (GetVectorDistance(fVictim, fEnd) > 160.0)
			{
				continue;
			}

			SDKHooks_TakeDamage(i, iClient, iClient, g_Items[iItem].fSecondaryValue, DMG_DROWN);

			g_fFrozenUntil[i] = GetGameTime() + 3.0;
			g_bFrozenTint[i] = true;

			SetEntityRenderColor(i, 90, 160, 255, 255);
		}

		return;
	}

	// Big shot: one heavy bolt that kicks the holder backwards.
	if (StrEqual(g_Items[iItem].sSecondary, "bigshot"))
	{
		float fRecoil[3];

		int iTarget = TraceEmblemAim(iClient, 3000.0, fStart, fDirection, fEnd);

		fStart[2] -= 12.0;

		LaunchSprite(iItem, fStart, fEnd, iColor, 2200.0, 2.0, false);

		TE_SetupEnergySplash(fEnd, g_fSkyward, true);
		TE_SendToAll();

		EmitSoundToAll(SOUND_SHOCK, iClient);

		if (CanBeHurt(iClient, iTarget))
		{
			SDKHooks_TakeDamage(iTarget, iClient, iClient, g_Items[iItem].fSecondaryValue, g_Items[iItem].iDamageType);
		}

		GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", fRecoil);

		fRecoil[0] -= fDirection[0] * 450.0;
		fRecoil[1] -= fDirection[1] * 450.0;
		fRecoil[2] -= fDirection[2] * 450.0;

		TeleportEntity(iClient, NULL_VECTOR, NULL_VECTOR, fRecoil);
	}
}

void LaunchFireball(int iClient, int iItem, int iColor[4])
{
	char sColor[32];
	float fAngles[3], fDirection[3], fStart[3], fVelocity[3];

	GetClientEyePosition(iClient, fStart);
	GetClientEyeAngles(iClient, fAngles);
	GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);

	fStart[0] += fDirection[0] * 32.0;
	fStart[1] += fDirection[1] * 32.0;
	fStart[2] += fDirection[2] * 32.0 - 8.0;

	// The game's own grenade does the flying, the touching and the blast; it is dressed up as a fireball.
	int iBall = CreateEntityByName("grenade_ar2");

	if (iBall == -1 || iBall > MAXENTITIES)
	{
		return;
	}

	DispatchSpawn(iBall);

	SetEntPropEnt(iBall, Prop_Send, "m_hOwnerEntity", iClient);

	if (HasEntProp(iBall, Prop_Data, "m_hThrower"))
	{
		SetEntPropEnt(iBall, Prop_Data, "m_hThrower", iClient);
	}

	if (HasEntProp(iBall, Prop_Data, "m_flDamage"))
	{
		SetEntPropFloat(iBall, Prop_Data, "m_flDamage", g_Items[iItem].fSecondaryValue);
	}

	if (HasEntProp(iBall, Prop_Data, "m_DmgRadius"))
	{
		SetEntPropFloat(iBall, Prop_Data, "m_DmgRadius", 180.0);
	}

	SetEntityGravity(iBall, 0.15);
	SetEntityRenderMode(iBall, RENDER_NONE);

	fVelocity[0] = fDirection[0] * 1100.0;
	fVelocity[1] = fDirection[1] * 1100.0;
	fVelocity[2] = fDirection[2] * 1100.0;

	TeleportEntity(iBall, fStart, fAngles, fVelocity);

	// The flame itself, riding on the grenade.
	int iFlame = CreateEntityByName("env_sprite");

	if (iFlame != -1)
	{
		Format(sColor, sizeof(sColor), "%d %d %d", iColor[0], iColor[1], iColor[2]);

		DispatchKeyValue(iFlame, "model", g_Items[iItem].sSprite);
		DispatchKeyValue(iFlame, "rendermode", "5");
		DispatchKeyValue(iFlame, "renderamt", "255");
		DispatchKeyValue(iFlame, "rendercolor", sColor);
		DispatchKeyValue(iFlame, "framerate", "15");
		DispatchKeyValue(iFlame, "scale", "1.6");
		DispatchKeyValue(iFlame, "spawnflags", "1");

		DispatchSpawn(iFlame);

		TeleportEntity(iFlame, fStart, NULL_VECTOR, NULL_VECTOR);

		SetVariantString("!activator");
		AcceptEntityInput(iFlame, "SetParent", iBall, iFlame);

		AcceptEntityInput(iFlame, "ShowSprite");
	}

	g_iFireballOwner[iBall] = GetClientUserId(iClient);
	g_iFireballItem[iBall] = iItem;

	EmitSoundToAll(SOUND_FIREBALL, iClient);
}

// Called when a fireball's grenade blows up: everyone near it is left burning.
void FireballExploded(int iBall)
{
	float fOrigin[3], fVictim[3];

	int iClient = GetClientOfUserId(g_iFireballOwner[iBall]);
	int iItem = g_iFireballItem[iBall];

	g_iFireballOwner[iBall] = 0;

	GetEntPropVector(iBall, Prop_Data, "m_vecAbsOrigin", fOrigin);

	if (iItem >= 0 && iItem < g_iItemCount)
	{
		SpriteSpray(fOrigin, g_fSkyward, g_Items[iItem].iSpriteIndex, 300, 0.8, 12);
	}

	if (iClient < 1)
	{
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!CanBeHurt(iClient, i))
		{
			continue;
		}

		GetClientAbsOrigin(i, fVictim);

		if (GetVectorDistance(fVictim, fOrigin) <= 170.0)
		{
			IgniteEntity(i, 4.0);
		}
	}
}

// Right click with the emblem in hand.
void SecondaryEmblemPower(int iClient, int iItem)
{
	char sPower[24];
	float fAngles[3], fDirection[3], fEnd[3], fStart[3], fVelocity[3];
	int iColor[4], iTarget = -1;

	strcopy(sPower, sizeof(sPower), g_Items[iItem].sPower);

	// An emblem's own right click attack, set with its "secondary" key.
	if (!StrEqual(g_Items[iItem].sSecondary, "none"))
	{
		g_fNextSecondary[iClient] = GetGameTime() + g_Items[iItem].fSecondaryCooldown;

		SecondaryAttack(iClient, iItem);

		return;
	}

	// Pink: heals the holder.
	if (StrEqual(sPower, "medic"))
	{
		if (GetClientHealth(iClient) < 100)
		{
			int iHealth = GetClientHealth(iClient) + RoundToFloor(g_Items[iItem].fValue * 2.0);

			SetEntityHealth(iClient, iHealth > 100 ? 100 : iHealth);

			EmitSoundToAll(SOUND_HEAL, iClient);
		}

		return;
	}

	// Demon: shakes the screens of everyone nearby.
	if (StrEqual(sPower, "demon"))
	{
		if (GetGameTime() < g_fNextQuake[iClient])
		{
			EmitSoundToClient(iClient, SOUND_DENY);

			return;
		}

		g_fNextQuake[iClient] = GetGameTime() + 10.0;

		float fHolder[3], fOther[3];

		GetClientAbsOrigin(iClient, fHolder);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (i == iClient || !IsClientInGame(i) || !IsPlayerAlive(i))
			{
				continue;
			}

			GetClientAbsOrigin(i, fOther);

			if (GetVectorDistance(fHolder, fOther) <= 700.0)
			{
				Client_Shake(i, SHAKE_START, 18.0, 150.0, 2.5);
			}
		}

		EmitSoundToAll(SOUND_QUAKE, iClient);

		TE_SetupBeamRingPoint(fHolder, 10.0, 700.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.8, 16.0, 0.0, g_iDemonColor, 10, 0);
		TE_SendToAll();

		return;
	}

	if (!StrEqual(sPower, "magnitude") && !StrEqual(sPower, "portal"))
	{
		return;
	}

	GetClientEyePosition(iClient, fStart);
	GetClientEyeAngles(iClient, fAngles);

	GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);

	fEnd[0] = fStart[0] + fDirection[0] * g_Items[iItem].fRange;
	fEnd[1] = fStart[1] + fDirection[1] * g_Items[iItem].fRange;
	fEnd[2] = fStart[2] + fDirection[2] * g_Items[iItem].fRange;

	Handle hTrace = TR_TraceRayFilterEx(fStart, fEnd, MASK_SHOT, RayType_EndPoint, Filter_NotSelf, iClient);

	if (TR_DidHit(hTrace))
	{
		TR_GetEndPosition(fEnd, hTrace);

		iTarget = TR_GetEntityIndex(hTrace);
	}

	CloseHandle(hTrace);

	if (StrEqual(sPower, "portal"))
	{
		// The second portal is drawn in the opposite color of the first.
		iColor[0] = 255 - g_Items[iItem].iBeamColor[0];
		iColor[1] = 255 - g_Items[iItem].iBeamColor[1];
		iColor[2] = 255 - g_Items[iItem].iBeamColor[2];
		iColor[3] = 255;

		SetPortal(iClient, 1, fEnd, fDirection, iColor);

		return;
	}

	// Magnitude: pulls the target towards the holder.
	ThrowTarget(iClient, iTarget, fDirection, -200.0);
}

void ThrowTarget(int iClient, int iTarget, float fDirection[3], float fForce)
{
	float fVelocity[3];

	if (iTarget < 1 || !IsValidEntity(iTarget))
	{
		return;
	}

	if (iTarget <= MaxClients)
	{
		if (!IsPlayerAlive(iTarget) || Cel_GetNoKill(iTarget))
		{
			return;
		}

		fVelocity[2] = 150.0;
	} else {
		// Another player's build is never touched, and frozen props do not move anyway.
		if (GetEntityMoveType(iTarget) != MOVETYPE_VPHYSICS || (Cel_IsEntity(iTarget) && !Cel_CheckOwner(iClient, iTarget)))
		{
			return;
		}
	}

	fVelocity[0] += fDirection[0] * fForce;
	fVelocity[1] += fDirection[1] * fForce;
	fVelocity[2] += fDirection[2] * fForce;

	TeleportEntity(iTarget, NULL_VECTOR, NULL_VECTOR, fVelocity);
}

// Abyss: places one of the holder's two portals. Walking into one comes out of the other.
void SetPortal(int iClient, int iPortal, float fEnd[3], float fDirection[3], int iColor[4])
{
	// Portals can't be opened in event and restricted areas, nor while standing in one.
	float fFeet[3];

	GetClientAbsOrigin(iClient, fFeet);

	fFeet[2] += 32.0;

	if (ZoneBlocks(iClient, fEnd) || ZoneBlocks(iClient, fFeet))
	{
		EmitSoundToClient(iClient, SOUND_DENY);

		Cel_PrintToChat(iClient, "You cannot open a portal in that area.");

		return;
	}

	g_fPortal[iClient][iPortal][0] = fEnd[0] - fDirection[0] * 40.0;
	g_fPortal[iClient][iPortal][1] = fEnd[1] - fDirection[1] * 40.0;
	g_fPortal[iClient][iPortal][2] = fEnd[2] - fDirection[2] * 40.0;

	g_bPortal[iClient][iPortal] = true;

	TE_SetupBeamRingPoint(g_fPortal[iClient][iPortal], 4.0, 90.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.6, 8.0, 0.0, iColor, 10, 0);
	TE_SendToAll();

	EmitSoundToAll(SOUND_BLINK, iClient);
}

// Moves anyone standing in a portal to its other end, and keeps both ends visible.
void ThinkPortals()
{
	float fOrigin[3], fDest[3];
	int iBlue[4] = { 60, 160, 255, 255 }, iPurple[4] = { 170, 60, 255, 255 };

	for (int iOwner = 1; iOwner <= MaxClients; iOwner++)
	{
		if (!g_bPortal[iOwner][0] || !g_bPortal[iOwner][1])
		{
			continue;
		}

		if (g_iTick % 5 == 0)
		{
			TE_SetupBeamRingPoint(g_fPortal[iOwner][0], 70.0, 72.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 1.05, 6.0, 0.0, iBlue, 10, 0);
			TE_SendToAll();

			TE_SetupBeamRingPoint(g_fPortal[iOwner][1], 70.0, 72.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 1.05, 6.0, 0.0, iPurple, 10, 0);
			TE_SendToAll();
		}

		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetGameTime() < g_fPortalWait[i])
			{
				continue;
			}

			GetClientAbsOrigin(i, fOrigin);

			fOrigin[2] += 36.0;

			for (int iPortal = 0; iPortal < 2; iPortal++)
			{
				if (GetVectorDistance(fOrigin, g_fPortal[iOwner][iPortal]) > 48.0)
				{
					continue;
				}

				fDest[0] = g_fPortal[iOwner][1 - iPortal][0];
				fDest[1] = g_fPortal[iOwner][1 - iPortal][1];
				fDest[2] = g_fPortal[iOwner][1 - iPortal][2] - 30.0;

				// A short wait stops the player bouncing straight back through.
				g_fPortalWait[i] = GetGameTime() + 2.0;

				TeleportEntity(i, fDest, NULL_VECTOR, NULL_VECTOR);

				EmitSoundToAll(SOUND_BLINK, i);

				break;
			}
		}
	}
}

// Teleports the player to where they are aiming, if they fit there.
void BlinkPlayer(int iClient, float fStart[3], float fDirection[3], float fEnd[3], int iColor[4])
{
	float fDest[3], fMaxs[3], fMins[3], fOrigin[3];

	GetClientAbsOrigin(iClient, fOrigin);
	GetClientMins(iClient, fMins);
	GetClientMaxs(iClient, fMaxs);

	// Step back from the surface that was hit and stand on the eye line.
	fDest[0] = fEnd[0] - fDirection[0] * 40.0;
	fDest[1] = fEnd[1] - fDirection[1] * 40.0;
	fDest[2] = fEnd[2] - fDirection[2] * 40.0 - (fStart[2] - fOrigin[2]) + 8.0;

	// No blinking into, out of or around inside event and restricted areas.
	float fCheck[3];

	fCheck = fDest;
	fCheck[2] += 32.0;

	if (ZoneBlocks(iClient, fCheck) || ZoneBlocks(iClient, fStart))
	{
		EmitSoundToClient(iClient, SOUND_DENY);

		Cel_PrintToChat(iClient, "You cannot blink into or inside that area.");

		return;
	}

	Handle hTrace = TR_TraceHullFilterEx(fDest, fDest, fMins, fMaxs, MASK_PLAYERSOLID, Filter_NotSelf, iClient);

	bool bBlocked = TR_DidHit(hTrace);

	CloseHandle(hTrace);

	if (bBlocked || TR_PointOutsideWorld(fDest))
	{
		EmitSoundToClient(iClient, SOUND_DENY);

		// The cooldown is given back when the blink fails.
		g_fNextPower[iClient] = 0.0;

		return;
	}

	TE_SetupBeamRingPoint(fOrigin, 60.0, 4.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.4, 5.0, 0.0, iColor, 10, 0);
	TE_SendToAll();

	TeleportEntity(iClient, fDest, NULL_VECTOR, NULL_VECTOR);

	TE_SetupBeamRingPoint(fDest, 4.0, 60.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.4, 5.0, 0.0, iColor, 10, 0);
	TE_SendToAll();

	EmitSoundToAll(SOUND_BLINK, iClient);
}

// Resist emblem: the holder takes less damage.
public Action Hook_PlayerTakeDamage(int iVictim, int &iAttacker, int &iInflictor, float &fDamage, int &iDamageType)
{
	Action aResult = Plugin_Continue;

	// Celweps: hits made with the celwep in hand use its damage multiplier.
	if (iAttacker > 0 && iAttacker <= MaxClients && iAttacker != iVictim && iInflictor == iAttacker && g_iCelWepItem[iAttacker] != -1
		&& EntRefToEntIndex(g_iCelWepRef[iAttacker]) == GetEntPropEnt(iAttacker, Prop_Send, "m_hActiveWeapon"))
	{
		fDamage *= g_Items[g_iCelWepItem[iAttacker]].fDamage;

		aResult = Plugin_Changed;
	}

	if (iVictim < 1 || iVictim > MaxClients || !g_bHoldingGravGun[iVictim])
	{
		return aResult;
	}

	int iItem = g_iActiveEmblem[iVictim];

	if (iItem == -1)
	{
		return aResult;
	}

	// Demon and similar emblems soften falls.
	if ((iDamageType & DMG_FALL) && g_Items[iItem].fFallDamage != 1.0)
	{
		fDamage *= g_Items[iItem].fFallDamage;

		return Plugin_Changed;
	}

	if (!StrEqual(g_Items[iItem].sPower, "resist"))
	{
		return aResult;
	}

	fDamage *= g_Items[iItem].fValue;

	return Plugin_Changed;
}

public bool Filter_NotSelf(int iEntity, int iContentsMask, any aData)
{
	return iEntity != aData;
}

public bool Filter_WorldOnly(int iEntity, int iContentsMask, any aData)
{
	return iEntity == 0;
}

//Hats:
void SetActiveHat(int iClient, int iItem)
{
	g_iActiveHat[iClient] = iItem;

	RemoveHatEntity(iClient);

	if (iItem == -1)
	{
		Inv_SetString(iClient, "active_hat", "none");
	} else {
		Inv_SetString(iClient, "active_hat", g_Items[iItem].sId);

		CreateHatEntity(iClient);
	}
}

void RemoveHatEntity(int iClient)
{
	int iHat = EntRefToEntIndex(g_iHatEntRef[iClient]);

	if (g_iHatEntRef[iClient] != INVALID_ENT_REFERENCE && iHat != INVALID_ENT_REFERENCE && iHat > MaxClients)
	{
		AcceptEntityInput(iHat, "ClearParent");
		AcceptEntityInput(iHat, "kill");
	}

	g_iHatEntRef[iClient] = INVALID_ENT_REFERENCE;
}

// Places a parented entity relative to its parent (or the attachment it is on).
void SetLocalOffset(int iEntity, const float fOffset[3], const float fAngles[3])
{
	SetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOffset);
	SetEntPropVector(iEntity, Prop_Send, "m_angRotation", fAngles);
}

void CreateHatEntity(int iClient)
{
	int iItem = g_iActiveHat[iClient];

	RemoveHatEntity(iClient);

	if (iItem == -1 || !IsClientInGame(iClient) || !IsPlayerAlive(iClient))
	{
		return;
	}

	// A hat whose model the server does not have would be invisible: say so instead of failing quietly.
	if (!FileExists(g_Items[iItem].sModel, true))
	{
		LogError("|CelMod| The hat '%s' uses the model '%s', which is not on the server.", g_Items[iItem].sId, g_Items[iItem].sModel);

		Cel_PrintToChat(iClient, "The {green}%s{default} hat cannot be shown: its model is missing on the server.", g_Items[iItem].sName);

		return;
	}

	int iHat = CreateEntityByName("prop_dynamic_override");

	if (iHat == -1)
	{
		return;
	}

	DispatchKeyValue(iHat, "model", g_Items[iItem].sModel);
	DispatchKeyValue(iHat, "solid", "0");
	char sSkin[16];

	IntToString(g_Items[iItem].iSkin, sSkin, sizeof(sSkin));

	DispatchKeyValue(iHat, "skin", sSkin);
	DispatchKeyValue(iHat, "classname", "cel_hat_worn");
	// Scaled models do not show in this game, so a scale is only applied when one is set.
	if (g_Items[iItem].fScale != 1.0)
	{
		DispatchKeyValueFloat(iHat, "modelscale", g_Items[iItem].fScale);
	}

	DispatchSpawn(iHat);

	SetEntityRenderColor(iHat, g_Items[iItem].iColor[0], g_Items[iItem].iColor[1], g_Items[iItem].iColor[2], 255);

	SetVariantString("!activator");
	AcceptEntityInput(iHat, "SetParent", iClient, iHat);

	// Not every player model has the same attachments, so the first one that exists is used.
	static const char sAttachments[][] = { "eyes", "head", "anim_attachment_head", "forward" };

	bool bAttached = false;

	for (int i = 0; i < sizeof(sAttachments); i++)
	{
		if (LookupEntityAttachment(iClient, sAttachments[i]) > 0)
		{
			SetVariantString(sAttachments[i]);
			AcceptEntityInput(iHat, "SetParentAttachment", iHat, iHat);

			bAttached = true;

			break;
		}
	}

	if (bAttached)
	{
		// Relative to the player's head. (TeleportEntity would take these as a position in the world and put the
		// hat near the middle of the map, where nobody sees it.)
		SetLocalOffset(iHat, g_Items[iItem].fOffset, g_Items[iItem].fAngles);
	} else {
		// No head attachment at all: the hat sits at standing head height above the player's feet.
		float fFallback[3];

		fFallback[0] = g_Items[iItem].fOffset[0];
		fFallback[1] = g_Items[iItem].fOffset[1];
		fFallback[2] = g_Items[iItem].fOffset[2] + 64.0;

		SetLocalOffset(iHat, fFallback, g_Items[iItem].fAngles);
	}

	g_iHatEntRef[iClient] = EntIndexToEntRef(iHat);

	SDKHook(iHat, SDKHook_SetTransmit, Hook_HatTransmit);
}

//Emblem drops: the boxes fall one after another, a few seconds apart.
int StartDrop(int iCount)
{
	int iAlive = 0;

	g_iMinutesSinceDrop = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			iAlive++;
		}
	}

	if (iAlive == 0 || iCount < 1)
	{
		return 0;
	}

	for (int i = 0; i < iCount; i++)
	{
		CreateTimer(0.1 + i * g_cvDropDelay.FloatValue, Timer_DropOne, _, TIMER_FLAG_NO_MAPCHANGE);
	}

	Cel_PrintToChatAll("{green}Emblem drop!{default} %d emblem box%s about to fall from the sky. Hold one with your gravity gun when the map changes, or get it into your land, to keep the emblem inside.", iCount, iCount == 1 ? " is" : "es are");

	return iCount;
}

public Action Timer_DropOne(Handle hTimer)
{
	SpawnDropBox();

	return Plugin_Stop;
}

int SpawnDropBox()
{
	float fOrigin[3];

	int iItem = PickRandomItem(KIND_EMBLEM);

	if (iItem == -1 || !FindDropPosition(fOrigin))
	{
		return -1;
	}

	int iBox = CreateEntityByName("prop_physics_override");

	if (iBox == -1)
	{
		return -1;
	}

	if (iBox > MAXENTITIES)
	{
		AcceptEntityInput(iBox, "kill");
		return -1;
	}

	DispatchKeyValue(iBox, "model", g_sDropModel);
	DispatchKeyValue(iBox, "classname", "cel_dropbox");

	DispatchSpawn(iBox);

	TeleportEntity(iBox, fOrigin, NULL_VECTOR, NULL_VECTOR);

	// The box shows which emblem is inside: the emblem's skin, in the emblem's color.
	if (StrEqual(g_sDropModel, DROPBOX_MODEL))
	{
		SetEntProp(iBox, Prop_Send, "m_nSkin", g_Items[iItem].iSkin);
	}

	SetEntityRenderColor(iBox, g_Items[iItem].iColor[0], g_Items[iItem].iColor[1], g_Items[iItem].iColor[2], 255);

	// It must survive the fall and being thrown around with the gravity gun until the map changes.
	SetEntProp(iBox, Prop_Data, "m_takedamage", 0, 1);

	g_bDropBox[iBox] = true;
	g_iEntItem[iBox] = iItem;
	g_iRewardId[iBox] = -1;

	SDKHook(iBox, SDKHook_UsePost, Hook_DropBoxUse);

	EmitAmbientSound(SOUND_DROP, fOrigin, iBox, SNDLEVEL_SCREAMING);

	return iBox;
}

// Pressing E on an emblem box that is inside your own land opens it.
public void Hook_DropBoxUse(int iEntity, int iActivator, int iCaller, UseType utType, float fValue)
{
	float fOrigin[3];

	if (!IsRealClient(iActivator) || iEntity > MAXENTITIES || !g_bDropBox[iEntity])
	{
		return;
	}

	GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", fOrigin);

	if (Cel_GetLandOwnerFromPosition(fOrigin) != iActivator)
	{
		Cel_PrintToChat(iActivator, "Get this emblem box into {green}your land{default} and press {green}E{default} on it to open it, or hold it with your gravity gun when the map changes.");
		return;
	}

	ClaimDropBox(iActivator, iEntity, "You opened the emblem box");

	Cel_DissolveEntity(iEntity);
}

void ClaimDropBox(int iClient, int iBox, const char[] sHow)
{
	int iItem = g_iEntItem[iBox];

	// One box can only be won once.
	g_bDropBox[iBox] = false;

	if (iItem < 0 || iItem >= g_iItemCount)
	{
		return;
	}

	SetOwned(iClient, iItem, GetOwned(iClient, iItem) + 1);

	EmitSoundToClient(iClient, SOUND_REWARD);

	Cel_PrintToChat(iClient, "%s: a {green}%s{default} emblem is yours! Type {green}!emblem %s{default} to spawn it.", sHow, g_Items[iItem].sName, g_Items[iItem].sId);
}

public int Native_GetDropBoxEmblem(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1);

	if (iEntity <= MaxClients || iEntity > MAXENTITIES || !g_bDropBox[iEntity] || g_iEntItem[iEntity] < 0 || g_iEntItem[iEntity] >= g_iItemCount || !IsValidEntity(iEntity))
	{
		return false;
	}

	SetNativeString(2, g_Items[g_iEntItem[iEntity]].sName, GetNativeCell(3));

	return true;
}

// Picks a point in open air high above a random spot near a random living player.
bool FindDropPosition(float fOrigin[3])
{
	float fBase[3], fCeiling[3], fRadius = g_cvDropRadius.FloatValue;
	int iClients[MAXPLAYERS + 1], iCount = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			iClients[iCount++] = i;
		}
	}

	if (iCount == 0)
	{
		return false;
	}

	for (int iTry = 0; iTry < 12; iTry++)
	{
		GetClientAbsOrigin(iClients[GetRandomInt(0, iCount - 1)], fBase);

		fBase[0] += GetRandomFloat(-fRadius, fRadius);
		fBase[1] += GetRandomFloat(-fRadius, fRadius);
		fBase[2] += 48.0;

		if (TR_PointOutsideWorld(fBase))
		{
			continue;
		}

		Handle hTrace = TR_TraceRayFilterEx(fBase, g_fUp, MASK_SOLID, RayType_Infinite, Filter_WorldOnly, 0);

		if (!TR_DidHit(hTrace))
		{
			CloseHandle(hTrace);
			continue;
		}

		TR_GetEndPosition(fCeiling, hTrace);

		CloseHandle(hTrace);

		if (fCeiling[2] - fBase[2] < 200.0)
		{
			continue;
		}

		fOrigin[0] = fBase[0];
		fOrigin[1] = fBase[1];
		fOrigin[2] = fCeiling[2] - 48.0;

		return true;
	}

	return false;
}

//Reward pickups:
void LoadRewards()
{
	char sDir[PLATFORM_MAX_PATH], sId[64], sKind[32], sSection[16];
	float fOrigin[3];

	BuildPath(Path_SM, sDir, sizeof(sDir), "data/celmod/rewards");

	if (!DirExists(sDir))
	{
		CreateDirectory(sDir, 511);
	}

	BuildPath(Path_SM, g_sRewardDB, sizeof(g_sRewardDB), "data/celmod/rewards/%s.txt", g_sMap);

	if (!FileExists(g_sRewardDB))
	{
		return;
	}

	KeyValues kvRewards = new KeyValues("Rewards");

	if (kvRewards.ImportFromFile(g_sRewardDB) && kvRewards.GotoFirstSubKey())
	{
		do
		{
			kvRewards.GetSectionName(sSection, sizeof(sSection));
			kvRewards.GetString("kind", sKind, sizeof(sKind), "emblem");
			kvRewards.GetString("item", sId, sizeof(sId), "random");
			kvRewards.GetVector("origin", fOrigin);

			// Linked to one of the map's own entities: attached once the map's entities are all there.
			if (kvRewards.GetNum("hammerid", 0) > 0)
			{
				continue;
			}

			int iReward = SpawnRewardEntity(StringToInt(sSection), KindFromName(sKind), sId, fOrigin);

			if (iReward != -1)
			{
				g_bRewardEvent[iReward] = (kvRewards.GetNum("event", 0) == 1);
			}
		}
		while (kvRewards.GotoNextKey());
	}

	delete kvRewards;
}

// Writes a reward to this map's file. Pass -1 as the id to use the next free one. Returns the id.
int SaveReward(int iId, int iKind, const char[] sId, float fOrigin[3], bool bEvent = false, int iHammer = 0)
{
	char sKey[16], sSection[16];

	KeyValues kvRewards = new KeyValues("Rewards");

	kvRewards.ImportFromFile(g_sRewardDB);

	if (iId == -1)
	{
		iId = 1;

		if (kvRewards.GotoFirstSubKey())
		{
			do
			{
				kvRewards.GetSectionName(sSection, sizeof(sSection));

				if (StringToInt(sSection) >= iId)
				{
					iId = StringToInt(sSection) + 1;
				}
			}
			while (kvRewards.GotoNextKey());

			kvRewards.Rewind();
		}
	}

	IntToString(iId, sKey, sizeof(sKey));

	kvRewards.JumpToKey(sKey, true);
	kvRewards.SetString("kind", g_sKindName[iKind]);
	kvRewards.SetString("item", sId);
	kvRewards.SetVector("origin", fOrigin);
	kvRewards.SetNum("event", bEvent ? 1 : 0);

	if (iHammer > 0)
	{
		kvRewards.SetNum("hammerid", iHammer);
	}
	kvRewards.Rewind();

	kvRewards.ExportToFile(g_sRewardDB);

	delete kvRewards;

	return iId;
}

int SpawnRewardEntity(int iId, int iKind, const char[] sId, float fOrigin[3])
{
	char sModel[PLATFORM_MAX_PATH];
	int iColor[4] = { 255, 255, 255, 255 }, iItem = -1;

	if (!StrEqual(sId, "random", false))
	{
		iItem = FindItem(iKind, sId);

		if (iItem == -1)
		{
			LogError("|CelMod| Reward #%d on %s uses the unknown item '%s'.", iId, g_sMap, sId);

			return -1;
		}

		strcopy(sModel, sizeof(sModel), g_Items[iItem].sModel);

		iColor[0] = g_Items[iItem].iColor[0];
		iColor[1] = g_Items[iItem].iColor[1];
		iColor[2] = g_Items[iItem].iColor[2];
	} else {
		strcopy(sModel, sizeof(sModel), iKind == KIND_EMBLEM ? GRAVGUN_WORLDMODEL : g_sDropModel);
	}

	// A fixed object: nothing can move it, pick it up or break it. Players claim it by pressing E while looking at it.
	int iEntity = CreateEntityByName("prop_dynamic_override");

	if (iEntity == -1)
	{
		return -1;
	}

	if (iEntity > MAXENTITIES)
	{
		AcceptEntityInput(iEntity, "kill");
		return -1;
	}

	PrecacheModel(sModel);

	DispatchKeyValue(iEntity, "model", sModel);
	DispatchKeyValue(iEntity, "classname", "cel_reward");
	DispatchKeyValue(iEntity, "solid", "2");

	DispatchSpawn(iEntity);

	TeleportEntity(iEntity, fOrigin, NULL_VECTOR, NULL_VECTOR);

	SetEntProp(iEntity, Prop_Data, "m_takedamage", 0, 1);
	SetEntityRenderColor(iEntity, iColor[0], iColor[1], iColor[2], 255);
	SetEntityRenderFx(iEntity, RENDERFX_PULSE_FAST);

	if (iItem != -1)
	{
		SetEntProp(iEntity, Prop_Send, "m_nSkin", g_Items[iItem].iSkin);
	}

	g_bDropBox[iEntity] = false;
	g_iEntItem[iEntity] = (iItem == -1) ? -(iKind + 2) : iItem;
	g_iRewardId[iEntity] = iId;
	g_bRewardEvent[iEntity] = false;
	g_bRewardLinked[iEntity] = false;

	return iEntity;
}

//Helpers:
bool IsRealClient(int iClient)
{
	return (iClient > 0 && iClient <= MaxClients && IsClientInGame(iClient) && !IsFakeClient(iClient));
}

void ResetClient(int iClient)
{
	g_bCloaked[iClient] = false;
	g_bTinted[iClient] = false;
	g_bPhasing[iClient] = false;
	g_bGravityManaged[iClient] = false;

	for (int i = 0; i < MAX_ITEMS; i++)
	{
		g_bCelWepTaken[iClient][i] = false;
	}
	g_bPortal[iClient][0] = false;
	g_bPortal[iClient][1] = false;
	g_fNextSecondary[iClient] = 0.0;
	g_fNextQuake[iClient] = 0.0;
	g_fPortalWait[iClient] = 0.0;
	g_bFrozenTint[iClient] = false;
	g_bHoldingGravGun[iClient] = false;
	g_bSpeedManaged[iClient] = false;

	g_fFrozenUntil[iClient] = 0.0;
	g_fNextPower[iClient] = 0.0;

	g_iActiveEmblem[iClient] = -1;
	g_iActiveHat[iClient] = -1;
	g_iHatEntRef[iClient] = INVALID_ENT_REFERENCE;
	g_iLastButtons[iClient] = 0;
	g_iHeldBox[iClient] = INVALID_ENT_REFERENCE;
	g_fHeldBoxTime[iClient] = 0.0;
	g_iShownGunRef[iClient] = INVALID_ENT_REFERENCE;

	for (int i = 0; i < 3; i++)
	{
		g_iSmogRef[iClient][i] = INVALID_ENT_REFERENCE;
	}
	g_iCelWepItem[iClient] = -1;
	g_iCelWepRef[iClient] = INVALID_ENT_REFERENCE;
	g_iPlayerModel[iClient] = -1;
	g_bHeldShown[iClient] = false;
	g_iHandEntRef[iClient] = INVALID_ENT_REFERENCE;
	g_iHandItem[iClient] = -1;
	g_iModdedWeaponRef[iClient] = INVALID_ENT_REFERENCE;
}

//Celweps:
// A celwep is a stock weapon the player is handed, shown as its own model and hitting with its own damage.
void SetActiveCelWep(int iClient, int iItem)
{
	g_iCelWepItem[iClient] = iItem;
	g_iCelWepRef[iClient] = INVALID_ENT_REFERENCE;

	RestoreWeapon(iClient);

	if (iItem == -1)
	{
		Inv_SetString(iClient, "active_weapon", "none");

		return;
	}

	Inv_SetString(iClient, "active_weapon", g_Items[iItem].sId);

	if (!IsPlayerAlive(iClient))
	{
		return;
	}

	char sClassname[64];
	int iWeapon = -1;

	// The player may already carry the stock weapon this celwep is built on.
	for (int i = 0; i < 48; i++)
	{
		int iHeld = GetEntPropEnt(iClient, Prop_Send, "m_hMyWeapons", i);

		if (iHeld > MaxClients && IsValidEntity(iHeld))
		{
			GetEntityClassname(iHeld, sClassname, sizeof(sClassname));

			if (StrEqual(sClassname, g_Items[iItem].sBase, false))
			{
				iWeapon = iHeld;
				break;
			}
		}
	}

	if (iWeapon == -1)
	{
		iWeapon = GivePlayerItem(iClient, g_Items[iItem].sBase);
	}

	if (iWeapon > MaxClients && IsValidEntity(iWeapon))
	{
		g_iCelWepRef[iClient] = EntIndexToEntRef(iWeapon);
	}
}

//Player models:
bool OwnsPlayerModel(int iClient, int iModel)
{
	char sKey[64];

	Format(sKey, sizeof(sKey), "playermodel_%s", g_PlayerModels[iModel].sId);

	// Given or bought.
	if (Inv_GetInt(iClient, sKey) == 1)
	{
		return true;
	}

	// Admin models belong to every admin with the flags.
	if (g_PlayerModels[iModel].iAdminFlags != 0)
	{
		return CheckCommandAccess(iClient, "celmod_playermodel_admin", g_PlayerModels[iModel].iAdminFlags, true);
	}

	return (g_PlayerModels[iModel].iPrice < 1);
}

void ApplyPlayerModel(int iClient)
{
	char sModel[PLATFORM_MAX_PATH];
	int iModel = g_iPlayerModel[iClient];

	if (iModel < 0 || iModel >= g_iPlayerModelCount || !IsClientInGame(iClient) || !IsPlayerAlive(iClient))
	{
		return;
	}

	GetClientModel(iClient, sModel, sizeof(sModel));

	if (!StrEqual(sModel, g_PlayerModels[iModel].sModel, false))
	{
		SetEntityModel(iClient, g_PlayerModels[iModel].sModel);

		// A hat is fixed to an attachment of the old model, so it goes on again on the new one.
		if (g_iActiveHat[iClient] != -1)
		{
			CreateHatEntity(iClient);
		}
	}
}

int FindPlayerModel(const char[] sSearch)
{
	for (int i = 0; i < g_iPlayerModelCount; i++)
	{
		if (StrEqual(g_PlayerModels[i].sId, sSearch, false) || StrEqual(g_PlayerModels[i].sName, sSearch, false))
		{
			return i;
		}
	}

	return -1;
}

public Action Command_PlayerModels(int iClient, int iArgs)
{
	char sEntry[96], sList[192];

	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	for (int i = 0; i < g_iPlayerModelCount; i++)
	{
		// Admin models that are not for sale are only listed for those who have them.
		if (g_PlayerModels[i].iAdminFlags != 0 && g_PlayerModels[i].iPrice < 1 && !OwnsPlayerModel(iClient, i))
		{
			continue;
		}

		if (OwnsPlayerModel(iClient, i))
		{
			Format(sEntry, sizeof(sEntry), "%s {green}(owned)%s{default}", g_PlayerModels[i].sId, g_iPlayerModel[iClient] == i ? " [on]" : "");
		} else {
			Format(sEntry, sizeof(sEntry), "%s (%d CL)", g_PlayerModels[i].sId, g_PlayerModels[i].iPrice);
		}

		if (strlen(sList) + strlen(sEntry) + 2 >= sizeof(sList) - 1)
		{
			Cel_ReplyToCommand(iClient, "%s,", sList);

			sList[0] = '\0';
		}

		if (sList[0] == '\0')
		{
			Format(sList, sizeof(sList), "{green}Player models:{default} %s", sEntry);
		} else {
			Format(sList, sizeof(sList), "%s, %s", sList, sEntry);
		}
	}

	if (g_iPlayerModelCount == 0)
	{
		Cel_ReplyToCommand(iClient, "There are no player models for sale.");
	} else {
		Cel_ReplyToCommand(iClient, "%s", sList);
		Cel_ReplyToCommand(iClient, "Buy one with {green}[tag]buymodel{default} <name>, wear it with {green}[tag]playermodel{default} <name>.");
	}

	return Plugin_Handled;
}

public Action Command_BuyModel(int iClient, int iArgs)
{
	char sArg[64], sKey[64];

	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]buymodel{default} <name>");
		return Plugin_Handled;
	}

	GetCmdArg(1, sArg, sizeof(sArg));

	int iModel = FindPlayerModel(sArg);

	if (iModel == -1)
	{
		Cel_ReplyToCommand(iClient, "There is no player model called {green}%s{default}. Type {green}[tag]playermodels{default} to see them.", sArg);
		return Plugin_Handled;
	}

	if (OwnsPlayerModel(iClient, iModel))
	{
		Cel_ReplyToCommand(iClient, "You already own the {green}%s{default} player model.", g_PlayerModels[iModel].sName);
		return Plugin_Handled;
	}

	if (g_PlayerModels[iModel].iAdminFlags != 0 && g_PlayerModels[iModel].iPrice < 1)
	{
		Cel_ReplyToCommand(iClient, "The {green}%s{default} player model is not for sale.", g_PlayerModels[iModel].sName);
		return Plugin_Handled;
	}

	if (!Cel_CheckClientBalance(iClient, g_PlayerModels[iModel].iPrice))
	{
		Cel_ReplyToCommand(iClient, "The {green}%s{default} player model costs {green}%d CL{default}. You do not have enough.", g_PlayerModels[iModel].sName, g_PlayerModels[iModel].iPrice);
		return Plugin_Handled;
	}

	Cel_SubFromClientBalance(iClient, g_PlayerModels[iModel].iPrice);

	Format(sKey, sizeof(sKey), "playermodel_%s", g_PlayerModels[iModel].sId);

	Inv_SetInt(iClient, sKey, 1);

	Cel_ReplyToCommand(iClient, "You bought the {green}%s{default} player model for {green}%d CL{default}. Wear it with {green}[tag]playermodel %s{default}.", g_PlayerModels[iModel].sName, g_PlayerModels[iModel].iPrice, g_PlayerModels[iModel].sId);

	return Plugin_Handled;
}

public Action Command_PlayerModel(int iClient, int iArgs)
{
	char sArg[64];

	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]playermodel{default} <name/off>");
		return Plugin_Handled;
	}

	GetCmdArg(1, sArg, sizeof(sArg));

	if (StrEqual(sArg, "off", false) || StrEqual(sArg, "none", false))
	{
		g_iPlayerModel[iClient] = -1;

		Inv_SetString(iClient, "active_playermodel", "none");

		Cel_ReplyToCommand(iClient, "You will be back on your own player model when you next respawn.");

		return Plugin_Handled;
	}

	int iModel = FindPlayerModel(sArg);

	if (iModel == -1)
	{
		Cel_ReplyToCommand(iClient, "There is no player model called {green}%s{default}.", sArg);
		return Plugin_Handled;
	}

	if (!OwnsPlayerModel(iClient, iModel))
	{
		Cel_ReplyToCommand(iClient, "You do not own the {green}%s{default} player model. It costs {green}%d CL{default}.", g_PlayerModels[iModel].sName, g_PlayerModels[iModel].iPrice);
		return Plugin_Handled;
	}

	g_iPlayerModel[iClient] = iModel;

	Inv_SetString(iClient, "active_playermodel", g_PlayerModels[iModel].sId);

	ApplyPlayerModel(iClient);

	Cel_ReplyToCommand(iClient, "You are now wearing the {green}%s{default} player model.", g_PlayerModels[iModel].sName);

	return Plugin_Handled;
}

//Power Booth:
// A green, flickering suit charger that appears somewhere on every map. Pressing E on it turns several
// copies of one emblem into a single big emblem.
public Action Timer_SpawnBooth(Handle hTimer)
{
	float fSpot[3];

	// Hidden away: of many open spots in the air, the one furthest from both the Guess Booth and the spawn points.
	if (FindHiddenBoothSpot(fSpot))
	{
		SpawnPowerBooth(fSpot);

		return Plugin_Stop;
	}

	LogError("|CelMod| No open spot was found for the Power Booth on this map. It is placed near a spawn point instead.");

	static const char sSpawns[][] = { "info_player_deathmatch", "info_player_combine", "info_player_rebel", "info_player_start" };
	float fOrigin[3];
	int iPoints[128], iCount = 0, iEntity;

	for (int i = 0; i < sizeof(sSpawns); i++)
	{
		iEntity = -1;

		while ((iEntity = FindEntityByClassname(iEntity, sSpawns[i])) != -1 && iCount < sizeof(iPoints))
		{
			iPoints[iCount++] = iEntity;
		}
	}

	if (iCount == 0)
	{
		return Plugin_Stop;
	}

	GetEntPropVector(iPoints[GetRandomInt(0, iCount - 1)], Prop_Data, "m_vecAbsOrigin", fOrigin);

	float fYaw = GetRandomFloat(0.0, 6.28);

	fOrigin[0] += Cosine(fYaw) * 96.0;
	fOrigin[1] += Sine(fYaw) * 96.0;
	fOrigin[2] += 1.0;

	SpawnPowerBooth(fOrigin);

	return Plugin_Stop;
}

// How open a spot is: the average distance a look in 26 directions travels before hitting something (up to 2000).
float SpotOpenness(float fSpot[3])
{
	float fAngles[3], fDirection[3], fEnd[3], fHit[3], fTotal = 0.0;
	int iRays = 0;

	for (int iPitch = -60; iPitch <= 60; iPitch += 60)
	{
		for (int iYaw = 0; iYaw < 360; iYaw += 45)
		{
			fAngles[0] = float(iPitch);
			fAngles[1] = float(iYaw);

			GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);

			fEnd[0] = fSpot[0] + fDirection[0] * 2000.0;
			fEnd[1] = fSpot[1] + fDirection[1] * 2000.0;
			fEnd[2] = fSpot[2] + fDirection[2] * 2000.0;

			Handle hTrace = TR_TraceRayFilterEx(fSpot, fEnd, MASK_SOLID, RayType_EndPoint, Filter_WorldOnly, 0);

			fHit = fEnd;

			if (TR_DidHit(hTrace))
			{
				TR_GetEndPosition(fHit, hTrace);
			}

			CloseHandle(hTrace);

			fTotal += GetVectorDistance(fSpot, fHit);

			iRays++;
		}
	}

	return fTotal / iRays;
}

// True when a player standing at the point could see the spot.
bool CanSeeSpot(float fFrom[3], float fSpot[3])
{
	float fEyes[3];

	fEyes = fFrom;
	fEyes[2] += 64.0;

	Handle hTrace = TR_TraceRayFilterEx(fEyes, fSpot, MASK_SOLID, RayType_EndPoint, Filter_WorldOnly, 0);

	bool bSeen = !TR_DidHit(hTrace);

	CloseHandle(hTrace);

	return bSeen;
}

// A spot as high up as the map goes, tucked into a corner. Random points all over the map are each pushed straight
// up until just under the ceiling or sky, then scored: how high above the ground it hangs counts most, then how
// much it is boxed into a corner (two walls close by at right angles), then being out of sight of the spawn points
// and the Guess Booth. One of the best few is picked at random, never near where it was last time on this map.
#define BOOTH_HALF_WIDTH 28.0
#define BOOTH_HEIGHT 72.0

bool FindHiddenBoothSpot(float fBest[3])
{
	static const char sSpawns[][] = { "info_player_deathmatch", "info_player_combine", "info_player_rebel", "info_player_start" };
	char sMap[PLATFORM_MAX_PATH];
	float fCandidate[3], fGuess[3], fSpawn[64][3], fSpots[120][3], fScores[120];
	float fMins[3] = { -BOOTH_HALF_WIDTH, -BOOTH_HALF_WIDTH, 0.0 }, fMaxs[3] = { BOOTH_HALF_WIDTH, BOOTH_HALF_WIDTH, BOOTH_HEIGHT };
	bool bGuess = false;
	int iSpawns = 0, iSpots = 0, iEntity;

	GetCurrentMap(sMap, sizeof(sMap));

	bool bSameMap = StrEqual(sMap, g_sLastBoothMap);

	for (int i = 0; i < sizeof(sSpawns); i++)
	{
		iEntity = -1;

		while ((iEntity = FindEntityByClassname(iEntity, sSpawns[i])) != -1 && iSpawns < sizeof(fSpawn))
		{
			GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", fSpawn[iSpawns]);

			iSpawns++;
		}
	}

	iEntity = FindEntityByClassname(-1, "cel_booth_kleiner");

	if (iEntity != -1)
	{
		GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", fGuess);

		bGuess = true;
	}

	// CelMod maps are huge: spots come from anywhere inside the whole map, not just around the spawn points.
	float fWorldMin[3], fWorldMax[3];

	GetEntPropVector(0, Prop_Data, "m_WorldMins", fWorldMin);
	GetEntPropVector(0, Prop_Data, "m_WorldMaxs", fWorldMax);

	// Never back near last time's spot: a quarter of the map's width away at least.
	float fAvoidLast = (fWorldMax[0] - fWorldMin[0] + fWorldMax[1] - fWorldMin[1]) * 0.125;

	if (fAvoidLast < 1500.0) fAvoidLast = 1500.0;

	for (int iTry = 0; iTry < 400 && iSpots < sizeof(fSpots); iTry++)
	{
		if (!Cel_FindRandomMapSpot(GetRandomInt(0, 1) == 0, BOOTH_HALF_WIDTH, BOOTH_HEIGHT, fCandidate, NULL_VECTOR, 0.0, 3000.0, 1000000.0))
		{
			continue;
		}

		// Straight up, as far as the booth fits: just under the ceiling or the sky.
		float fTop[3], fSpot[3];

		fCandidate[2] += 4.0;

		fTop = fCandidate;
		fTop[2] += 8192.0;

		Handle hUp = TR_TraceHullFilterEx(fCandidate, fTop, fMins, fMaxs, MASK_PLAYERSOLID, Filter_WorldOnly, 0);

		TR_GetEndPosition(fSpot, hUp);

		bool bStartSolid = TR_StartSolid(hUp);

		CloseHandle(hUp);

		if (bStartSolid || TR_PointOutsideWorld(fSpot))
		{
			continue;
		}

		// A little gap under the ceiling, so it does not look stuck into it.
		fSpot[2] -= 24.0;

		if (fSpot[2] < fCandidate[2])
		{
			fSpot[2] = fCandidate[2];
		}

		if (bSameMap && GetVectorDistance(fSpot, g_fLastBoothSpot) < fAvoidLast)
		{
			continue;
		}

		// How high it hangs above whatever is under it.
		float fDown[3], fGround[3];

		fDown = fSpot;
		fDown[2] -= 16384.0;

		Handle hDown = TR_TraceRayFilterEx(fSpot, fDown, MASK_PLAYERSOLID, RayType_EndPoint, Filter_WorldOnly, 0);

		TR_GetEndPosition(fGround, hDown);

		CloseHandle(hDown);

		float fHeight = fSpot[2] - fGround[2];

		// How boxed into a corner it is: the closest pair of walls at right angles to each other, at booth height.
		float fWall[8], fMiddle[3], fAngles[3], fDirection[3], fEnd[3], fHit[3];

		fMiddle = fSpot;
		fMiddle[2] += BOOTH_HEIGHT * 0.5;

		for (int k = 0; k < 8; k++)
		{
			fAngles[0] = 0.0;
			fAngles[1] = 45.0 * k;
			fAngles[2] = 0.0;

			GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);

			for (int n = 0; n < 3; n++)
			{
				fEnd[n] = fMiddle[n] + fDirection[n] * 800.0;
			}

			Handle hWall = TR_TraceRayFilterEx(fMiddle, fEnd, MASK_PLAYERSOLID, RayType_EndPoint, Filter_WorldOnly, 0);

			fHit = fEnd;

			if (TR_DidHit(hWall))
			{
				TR_GetEndPosition(fHit, hWall);
			}

			CloseHandle(hWall);

			fWall[k] = GetVectorDistance(fMiddle, fHit);
		}

		float fCorner = 0.0;

		for (int k = 0; k < 8; k++)
		{
			float fPair = (fWall[k] > fWall[(k + 2) % 8]) ? fWall[k] : fWall[(k + 2) % 8];
			float fTight = 1.0 - fPair / 800.0;

			if (fTight > fCorner)
			{
				fCorner = fTight;
			}
		}

		// Out of sight of the spawn points and the Guess Booth, and away from them.
		float fNearest = 999999.0;
		int iSeen = 0;

		for (int i = 0; i < iSpawns; i++)
		{
			float fPoint[3];

			fPoint = fSpawn[i];

			float fDistance = GetVectorDistance(fSpot, fPoint);

			if (fDistance < fNearest) fNearest = fDistance;

			if (CanSeeSpot(fPoint, fMiddle)) iSeen++;
		}

		if (bGuess)
		{
			if (GetVectorDistance(fSpot, fGuess) < fNearest) fNearest = GetVectorDistance(fSpot, fGuess);

			if (CanSeeSpot(fGuess, fMiddle)) iSeen += 2;
		}

		if (fNearest > 3000.0) fNearest = 3000.0;

		// High up counts, but only up to a point: every spot well up in the air scores the same for height, so the
		// tallest part of the map does not win every time. Then the corner, then being hidden and far away.
		if (fHeight > 1200.0) fHeight = 1200.0;

		fScores[iSpots] = fHeight / 100.0 + fCorner * 6.0 - iSeen * 1.5 + fNearest / 1000.0;
		fSpots[iSpots] = fSpot;

		iSpots++;
	}

	if (iSpots == 0)
	{
		return false;
	}

	// Any of the better third of all the spots found, at random, so it turns up all over the map.
	int iTop[120], iTopCount = 0;
	int iWant = iSpots / 3;

	if (iWant < 1) iWant = 1;

	for (int k = 0; k < iWant; k++)
	{
		int iBest = -1;

		for (int i = 0; i < iSpots; i++)
		{
			if (fScores[i] > -999999.0 && (iBest == -1 || fScores[i] > fScores[iBest]))
			{
				iBest = i;
			}
		}

		if (iBest == -1)
		{
			break;
		}

		iTop[iTopCount++] = iBest;
		fScores[iBest] = -9999999.0;
	}

	fBest = fSpots[iTop[GetRandomInt(0, iTopCount - 1)]];

	strcopy(g_sLastBoothMap, sizeof(g_sLastBoothMap), sMap);
	g_fLastBoothSpot = fBest;

	return true;
}

// The booth can't be broken, and if anything removes it before it has been used, it comes back where it was.
// Once used it is gone for the rest of the map.
public Action Timer_BoothGuard(Handle hTimer)
{
	if (g_bBoothPlaced && EntRefToEntIndex(g_iBoothRef) == INVALID_ENT_REFERENCE)
	{
		float fSpot[3];

		fSpot = g_fBoothSpot;

		SpawnPowerBooth(fSpot);
	}

	return Plugin_Continue;
}

void SpawnPowerBooth(float fOrigin[3])
{
	int iOld = EntRefToEntIndex(g_iBoothRef);

	if (g_iBoothRef != INVALID_ENT_REFERENCE && iOld != INVALID_ENT_REFERENCE && iOld > MaxClients)
	{
		AcceptEntityInput(iOld, "kill");
	}

	g_iBoothRef = INVALID_ENT_REFERENCE;

	// A plain model that never moves: it works for any model, with or without a physics model of its own.
	int iBooth = CreateEntityByName("prop_dynamic_override");

	if (iBooth == -1)
	{
		return;
	}

	DispatchKeyValue(iBooth, "model", g_sBoothModel);
	DispatchKeyValue(iBooth, "classname", "cel_powerbooth");
	DispatchKeyValue(iBooth, "solid", "2");

	DispatchSpawn(iBooth);

	// Its base rests on the spot, facing a random way.
	float fMins[3], fPlace[3], fAngles[3];

	GetEntPropVector(iBooth, Prop_Send, "m_vecMins", fMins);

	fPlace = fOrigin;

	if (fMins[2] < 0.0)
	{
		fPlace[2] -= fMins[2];
	}

	fAngles[1] = GetRandomFloat(0.0, 360.0);

	TeleportEntity(iBooth, fPlace, fAngles, NULL_VECTOR);

	// Nothing can break it: no damage, no physics.
	SetEntProp(iBooth, Prop_Data, "m_takedamage", 0, 1);

	g_fBoothSpot = fOrigin;
	g_bBoothPlaced = true;
	g_bBoothSpent = false;

	// Green, see-through and flickering, as it was on the original server.
	SetEntityRenderMode(iBooth, RENDER_TRANSCOLOR);
	SetEntityRenderColor(iBooth, 0, 255, 0, g_cvBoothAlpha.IntValue);
	SetEntityRenderFx(iBooth, RENDERFX_DISTORT);

	g_iBoothRef = EntIndexToEntRef(iBooth);
}

public Action Command_PowerBooth(int iClient, int iArgs)
{
	float fOrigin[3];

	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	Cel_GetCrosshairHitOrigin(iClient, fOrigin);

	fOrigin[2] += 1.0;

	SpawnPowerBooth(fOrigin);

	Cel_ReplyToCommand(iClient, "The Power Booth has been moved here for this map.");

	return Plugin_Handled;
}

// True when the player is close to the Power Booth and aiming at it.
bool IsLookingAtBooth(int iClient)
{
	float fAngles[3], fBooth[3], fEyes[3], fForward[3], fToBooth[3];

	int iBooth = EntRefToEntIndex(g_iBoothRef);

	if (g_iBoothRef == INVALID_ENT_REFERENCE || iBooth == INVALID_ENT_REFERENCE)
	{
		return false;
	}

	GetClientEyePosition(iClient, fEyes);
	GetClientEyeAngles(iClient, fAngles);
	GetAngleVectors(fAngles, fForward, NULL_VECTOR, NULL_VECTOR);

	// The middle of the booth model, not its origin, which can be at its base.
	float fMaxs[3], fMins[3];

	GetEntPropVector(iBooth, Prop_Data, "m_vecAbsOrigin", fBooth);
	GetEntPropVector(iBooth, Prop_Send, "m_vecMins", fMins);
	GetEntPropVector(iBooth, Prop_Send, "m_vecMaxs", fMaxs);

	for (int i = 0; i < 3; i++)
	{
		fBooth[i] += (fMins[i] + fMaxs[i]) * 0.5;
	}

	MakeVectorFromPoints(fEyes, fBooth, fToBooth);

	float fDistance = NormalizeVector(fToBooth, fToBooth);

	if (fDistance > 160.0)
	{
		return false;
	}

	// Roughly aimed at it: within about 25 degrees, wider when right next to it.
	return (GetVectorDotProduct(fForward, fToBooth) >= (fDistance < 80.0 ? 0.7 : 0.9));
}

// How close spawned emblems must be to the Power Booth to be used.
#define BOOTH_REACH 200.0

// How many of the player's spawned copies of an emblem are at the booth.
int CountAtBooth(int iClient, int iItem, float fBooth[3])
{
	float fOrigin[3];
	int iCount = 0;

	for (int i = MaxClients + 1; i <= MAXENTITIES; i++)
	{
		if (g_iEntItem[i] != iItem || !IsItemEntity(i) || !Cel_CheckOwner(iClient, i))
		{
			continue;
		}

		Cel_GetEntityOrigin(i, fOrigin);

		if (GetVectorDistance(fOrigin, fBooth) <= BOOTH_REACH)
		{
			iCount++;
		}
	}

	return iCount;
}

// The player brings spawned emblems to the booth, then presses E on it. Only emblems sitting at the booth count.
public void Hook_BoothUse(int iEntity, int iActivator, int iCaller, UseType utType, float fValue)
{
	float fBooth[3];
	int iCost = g_cvUpgradeCost.IntValue, iFrom = -1, iTo = -1;

	if (!IsRealClient(iActivator) || g_bBoothSpent)
	{
		return;
	}

	GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", fBooth);

	// No menu (in HL2DM menus only show as a small notice that has to be opened with Esc): what is made depends on
	// how many were brought. Enough for a big emblem makes the big one; otherwise the next emblem up, if it has one.
	for (int i = 0; i < g_iItemCount && iTo == -1; i++)
	{
		if (g_Items[i].iKind != KIND_EMBLEM || g_Items[i].bIsBig)
		{
			continue;
		}

		int iHere = CountAtBooth(iActivator, i, fBooth);

		if (iHere < 1)
		{
			continue;
		}

		if (g_Items[i].iBig != -1 && iHere >= iCost)
		{
			iFrom = i;
			iTo = g_Items[i].iBig;
		} else if (g_Items[i].iUpgradeTo != -1 && iHere >= g_Items[i].iUpgradeCost)
		{
			iFrom = i;
			iTo = g_Items[i].iUpgradeTo;
		}
	}

	if (iTo != -1)
	{
		UpgradeAtBooth(iActivator, iEntity, iFrom, iTo);

		return;
	}

	EmitSoundToClient(iActivator, SOUND_DENY);

	// Say what was brought and how many more are needed.
	bool bTold = false;

	for (int i = 0; i < g_iItemCount; i++)
	{
		if (g_Items[i].iKind != KIND_EMBLEM || g_Items[i].bIsBig)
		{
			continue;
		}

		int iHere = CountAtBooth(iActivator, i, fBooth);

		if (iHere < 1)
		{
			continue;
		}

		bTold = true;

		if (g_Items[i].iUpgradeTo != -1)
		{
			Cel_PrintToChat(iActivator, "{green}Power Booth:{default} you brought {green}%d %s{default}. A {green}%s{default} needs {green}%d{default}, a {green}%s{default} needs {green}%d{default}.", iHere, g_Items[i].sName, g_Items[g_Items[i].iUpgradeTo].sName, g_Items[i].iUpgradeCost, g_Items[g_Items[i].iBig].sName, iCost);
		} else if (g_Items[i].iBig != -1)
		{
			Cel_PrintToChat(iActivator, "{green}Power Booth:{default} you brought {green}%d %s{default}. A {green}%s{default} needs {green}%d{default}.", iHere, g_Items[i].sName, g_Items[g_Items[i].iBig].sName, iCost);
		}
	}

	if (!bTold)
	{
		Cel_PrintToChat(iActivator, "{green}Power Booth:{default} bring your emblems here and press {green}E{default} to upgrade them.");
	}
}

// Takes the emblems from the booth and puts the new one in their place.
void UpgradeAtBooth(int iClient, int iBooth, int iFrom, int iTo)
{
	float fBooth[3], fOrigin[3], fSpot[3];

	if (iFrom < 0 || iFrom >= g_iItemCount || iTo < 0 || iTo >= g_iItemCount)
	{
		return;
	}

	if (iTo != g_Items[iFrom].iBig && iTo != g_Items[iFrom].iUpgradeTo)
	{
		return;
	}

	int iCost = (iTo == g_Items[iFrom].iBig) ? g_cvUpgradeCost.IntValue : g_Items[iFrom].iUpgradeCost;

	GetEntPropVector(iBooth, Prop_Data, "m_vecAbsOrigin", fBooth);

	// Checked again: emblems may have been carried away while the menu was open.
	if (CountAtBooth(iClient, iFrom, fBooth) < iCost || GetOwned(iClient, iFrom) < iCost)
	{
		EmitSoundToClient(iClient, SOUND_DENY);

		Cel_PrintToChat(iClient, "There are no longer {green}%d %s{default} emblems at the Power Booth.", iCost, g_Items[iFrom].sName);

		return;
	}

	int iTaken = 0;

	for (int i = MaxClients + 1; i <= MAXENTITIES && iTaken < iCost; i++)
	{
		if (g_iEntItem[i] != iFrom || !IsItemEntity(i) || !Cel_CheckOwner(iClient, i))
		{
			continue;
		}

		Cel_GetEntityOrigin(i, fOrigin);

		if (GetVectorDistance(fOrigin, fBooth) > BOOTH_REACH)
		{
			continue;
		}

		TE_SetupBeamPoints(fOrigin, fBooth, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.5, 4.0, 4.0, 1, 2.0, g_iGreen, 10);
		TE_SendToAll();

		// Drawn into the booth: a green spark where it was, then it is gone. (The CelMod dissolver's energy-core
		// burst looked like the booth blowing up.)
		float fUp[3] = { 0.0, 0.0, 1.0 };

		TE_SetupEnergySplash(fOrigin, fUp, false);
		TE_SendToAll();

		AcceptEntityInput(i, "kill");

		// Marked so it is not counted twice while it dissolves.
		g_iEntItem[i] = -1;

		iTaken++;
	}

	int iLeft = GetOwned(iClient, iFrom) - iCost;

	SetOwned(iClient, iFrom, iLeft);

	if (iLeft < 1 && g_iActiveEmblem[iClient] == iFrom)
	{
		SetActiveEmblem(iClient, -1);
	}

	// The new emblem appears beside the booth, already the player's.
	SetOwned(iClient, iTo, GetOwned(iClient, iTo) + 1);

	// The new emblem lands on the ground under the booth, where it can be reached.
	float fDown[3];

	fSpot = fBooth;
	fDown = fBooth;
	fDown[2] -= 4096.0;

	Handle hGround = TR_TraceRayFilterEx(fBooth, fDown, MASK_PLAYERSOLID, RayType_EndPoint, Filter_WorldOnly, 0);

	if (TR_DidHit(hGround))
	{
		TR_GetEndPosition(fSpot, hGround);
	}

	CloseHandle(hGround);

	fSpot[2] += 8.0;

	int iNew = SpawnItemEntity(iClient, iTo, fSpot, g_fZero);

	if (iNew != -1)
	{
		Cel_FixSpawnPosition(iNew, fSpot);
	}

	TE_SetupBeamRingPoint(fBooth, 10.0, 220.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.8, 10.0, 0.0, g_iGreen, 10, 0);
	TE_SendToAll();

	EmitSoundToAll(SOUND_REWARD, iBooth);

	Cel_PrintToChatAll("{green}%N{default} used the Power Booth to make a {green}%s{default} emblem! The booth is overloading...", iClient, g_Items[iTo].sName);

	// One use per map: the booth overloads and blows itself apart a moment later.
	g_bBoothSpent = true;
	g_bBoothPlaced = false;

	CreateTimer(1.5, Timer_BoothExplode, EntIndexToEntRef(iBooth), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_BoothExplode(Handle hTimer, any iRef)
{
	float fBooth[3], fUp[3] = { 0.0, 0.0, 1.0 };
	int iGreen[4] = { 60, 255, 60, 255 }, iWhite[4] = { 220, 255, 220, 255 };

	int iBooth = EntRefToEntIndex(iRef);

	if (iBooth == INVALID_ENT_REFERENCE)
	{
		return Plugin_Stop;
	}

	GetEntPropVector(iBooth, Prop_Data, "m_vecAbsOrigin", fBooth);

	fBooth[2] += 32.0;

	// A real explosion for the look and sound, but it hurts nobody and breaks nothing (spawnflag 1: no damage).
	int iExplosion = CreateEntityByName("env_explosion");

	if (iExplosion != -1)
	{
		DispatchKeyValue(iExplosion, "iMagnitude", "120");
		DispatchKeyValue(iExplosion, "spawnflags", "1");

		DispatchSpawn(iExplosion);

		TeleportEntity(iExplosion, fBooth, NULL_VECTOR, NULL_VECTOR);

		AcceptEntityInput(iExplosion, "Explode");
		AcceptEntityInput(iExplosion, "kill");
	}

	Fx_Starburst(fBooth, 8, 140.0, g_iBmLightning, 6.0, 0.6, iGreen);
	Fx_Ring(fBooth, 10.0, 300.0, g_iBmPhys, 14.0, 0.6, 0.0, iGreen);
	Fx_Ring(fBooth, 10.0, 200.0, g_iBmLaser, 8.0, 0.4, 0.0, iWhite);
	Fx_Sparks(fBooth, fUp, 8, 6);
	Fx_Light(fBooth, iGreen, 450.0, 1.0, 7);

	EmitAmbientSound(g_sFxBoom, fBooth, SOUND_FROM_WORLD, SNDLEVEL_SCREAMING);

	AcceptEntityInput(iBooth, "kill");

	g_iBoothRef = INVALID_ENT_REFERENCE;

	Cel_PrintToChatAll("{green}The Power Booth{default} blew up. It will be back somewhere else next map.");

	return Plugin_Stop;
}

// What an item looks like, for plugins that put one on display (the auction above the Guess Booth).
public int Native_GetCollectibleLook(Handle hPlugin, int iNumParams)
{
	char sId[64], sKind[32];

	GetNativeString(1, sKind, sizeof(sKind));
	GetNativeString(2, sId, sizeof(sId));

	int iItem = FindItem(KindFromName(sKind), sId);

	if (iItem == -1)
	{
		return false;
	}

	SetNativeString(3, g_Items[iItem].sModel, GetNativeCell(4));
	SetNativeString(5, g_Items[iItem].sName, GetNativeCell(6));
	SetNativeCellRef(7, g_Items[iItem].iSkin);
	SetNativeArray(8, g_Items[iItem].iColor, 4);

	return true;
}

//Custom Guns celweps:
bool UsesCustomGun(int iItem)
{
	return (g_bCustomGuns && g_Items[iItem].sCustomGun[0] != '\0' && GetFeatureStatus(FeatureType_Native, "CG_GiveGun") == FeatureStatus_Available);
}

int FindCustomGunItem(const char[] sClassname)
{
	for (int i = 0; i < g_iItemCount; i++)
	{
		if (g_Items[i].iKind == KIND_WEAPON && StrEqual(g_Items[i].sCustomGun, sClassname, false))
		{
			return i;
		}
	}

	return -1;
}

// Several celweps can be carried at once. Custom Guns can only empty a whole inventory, so to put one back the
// inventory is emptied and the rest are handed out again.
void SetCelWepTaken(int iClient, int iItem, bool bTaken)
{
	char sKey[64];

	g_bCelWepTaken[iClient][iItem] = bTaken;

	Format(sKey, sizeof(sKey), "taken_%s", g_Items[iItem].sId);

	Inv_SetInt(iClient, sKey, bTaken ? 1 : 0);

	if (!IsPlayerAlive(iClient) || !UsesCustomGun(iItem))
	{
		return;
	}

	if (bTaken)
	{
		CG_GiveGun(iClient, g_Items[iItem].sCustomGun, true);

		return;
	}

	CG_ClearInventory(iClient);

	GiveTakenCelWeps(iClient);
}

void GiveTakenCelWeps(int iClient)
{
	for (int i = 0; i < g_iItemCount; i++)
	{
		if (g_bCelWepTaken[iClient][i] && UsesCustomGun(i) && GetOwned(iClient, i) > 0)
		{
			CG_GiveGun(iClient, g_Items[i].sCustomGun, true);
		}
	}
}

public Action Timer_GiveCelWeps(Handle hTimer, any iUserId)
{
	int iClient = GetClientOfUserId(iUserId);

	if (iClient > 0 && IsClientInGame(iClient) && IsPlayerAlive(iClient))
	{
		GiveTakenCelWeps(iClient);
	}

	return Plugin_Stop;
}

// Called by Custom Guns when a player swings one of its weapons. Celweps are melee weapons: the hit, damage and
// effects come from the celwep's entry in collectibles.txt.
public void CG_OnPrimaryAttack(int iClient, int iWeapon)
{
	char sClassname[64];
	float fAngles[3], fEnd[3], fForward[3], fStart[3];

	GetEntityClassname(iWeapon, sClassname, sizeof(sClassname));

	int iItem = FindCustomGunItem(sClassname);

	if (iItem == -1)
	{
		return;
	}

	float fNext = GetGameTime() + g_Items[iItem].fRefire;

	SetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack", fNext);
	SetEntPropFloat(iWeapon, Prop_Send, "m_flNextSecondaryAttack", fNext);

	CG_SetPlayerAnimation(iClient, CG_PLAYER_ATTACK1);

	// Guns and launchers instead of a swing.
	if (StrEqual(g_Items[iItem].sAttack, "ranged") || StrEqual(g_Items[iItem].sAttack, "melon"))
	{
		CG_PlayActivity(iWeapon, CG_ACT_VM_PRIMARYATTACK);

		CelWepShoot(iClient, iItem);

		return;
	}

	CG_GetShootPosition(iClient, fStart);
	GetClientEyeAngles(iClient, fAngles);
	GetAngleVectors(fAngles, fForward, NULL_VECTOR, NULL_VECTOR);

	fEnd[0] = fStart[0] + fForward[0] * g_Items[iItem].fHitRange;
	fEnd[1] = fStart[1] + fForward[1] * g_Items[iItem].fHitRange;
	fEnd[2] = fStart[2] + fForward[2] * g_Items[iItem].fHitRange;

	float fMins[3] = { -10.0, -10.0, -10.0 }, fMaxs[3] = { 10.0, 10.0, 10.0 };

	Handle hTrace = TR_TraceHullFilterEx(fStart, fEnd, fMins, fMaxs, MASK_SHOT_HULL, Filter_NotSelf, iClient);

	if (!TR_DidHit(hTrace))
	{
		CloseHandle(hTrace);

		CG_PlayActivity(iWeapon, CG_ACT_VM_MISSCENTER);

		EmitGameSoundToAll("Weapon_Crowbar.Single", iWeapon);

		return;
	}

	float fHit[3], fNormal[3];

	int iHit = TR_GetEntityIndex(hTrace);

	TR_GetEndPosition(fHit, hTrace);
	TR_GetPlaneNormal(hTrace, fNormal);

	CloseHandle(hTrace);

	CG_PlayActivity(iWeapon, CG_ACT_VM_HITCENTER);

	EmitGameSoundToAll("Weapon_Crowbar.Melee_Hit", iWeapon);

	if (iHit > 0 && iHit <= MaxClients)
	{
		if (CanBeHurt(iClient, iHit))
		{
			SDKHooks_TakeDamage(iHit, iClient, iClient, g_Items[iItem].fHitDamage, DMG_CLUB);

			if (g_Items[iItem].fIgnite > 0.0)
			{
				IgniteEntity(iHit, g_Items[iItem].fIgnite);
			}

			if (g_Items[iItem].fSlow > 0.0)
			{
				g_fFrozenUntil[iHit] = GetGameTime() + g_Items[iItem].fSlow;
				g_bFrozenTint[iHit] = true;

				SetEntityRenderColor(iHit, 90, 160, 255, 255);
			}
		}

		return;
	}

	// Loose physics props get knocked about; nobody else's frozen build is touched.
	if (iHit > MaxClients && GetEntityMoveType(iHit) == MOVETYPE_VPHYSICS && (!Cel_IsEntity(iHit) || Cel_CheckOwner(iClient, iHit)))
	{
		float fPush[3];

		fPush[0] = fForward[0] * 250.0;
		fPush[1] = fForward[1] * 250.0;
		fPush[2] = fForward[2] * 250.0;

		TeleportEntity(iHit, NULL_VECTOR, NULL_VECTOR, fPush);
	}

	// Digging: a shovel hitting the ground can turn up an emblem.
	if (iHit == 0 && fNormal[2] > 0.7 && g_Items[iItem].sDigs[0] != '\0')
	{
		DigForEmblem(iClient, iItem, fHit);
	}
}

// A shovel hit on the ground. Most finds are junk; now and then a money box or an emblem comes up.
void DigForEmblem(int iClient, int iItem, float fHit[3])
{
	char sChoices[8][32];
	float fUp[3] = { 0.0, 0.0, 1.0 };

	TE_SetupDust(fHit, fUp, 12.0, 1.0);
	TE_SendToAll();

	EmitSoundToAll(SOUND_DIG, iClient, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.7);

	// Digging too fast in one place finds nothing new.
	if (GetGameTime() < g_fNextDig[iClient] || GetRandomFloat(0.0, 1.0) > g_cvDigChance.FloatValue)
	{
		return;
	}

	g_fNextDig[iClient] = GetGameTime() + 1.5;

	g_iDigger = GetClientUserId(iClient);

	float fSpot[3];

	fSpot = fHit;
	fSpot[2] += 12.0;

	float fRoll = GetRandomFloat(0.0, 1.0);

	if (fRoll < g_cvDigEmblemChance.FloatValue)
	{
		int iCount = ExplodeString(g_Items[iItem].sDigs, " ", sChoices, sizeof(sChoices), sizeof(sChoices[]));

		int iFound = FindItem(KIND_EMBLEM, sChoices[GetRandomInt(0, iCount - 1)]);

		if (iFound != -1)
		{
			// The emblem comes out of the ground already belonging to the digger.
			int iEntity = SpawnItemEntity(iClient, iFound, fSpot, g_fZero);

			SetOwned(iClient, iFound, GetOwned(iClient, iFound) + 1);

			if (iEntity != -1)
			{
				ThrowOutOfGround(iEntity);
			}

			EmitSoundToAll(SOUND_REWARD, iClient);

			Cel_PrintToChat(iClient, "You dug up a {green}%s{default} emblem!", g_Items[iFound].sName);

			return;
		}
	}

	if (fRoll < g_cvDigEmblemChance.FloatValue + g_cvDigMoneyChance.FloatValue)
	{
		int iMoney = GetRandomInt(g_cvDigMoneyMin.IntValue, g_cvDigMoneyMax.IntValue);

		//A cleers box that already belongs to the digger: E opens it, !give hands it over.
		int iBox = Cel_CreateCleerBox(iClient, iMoney, fSpot);

		if (iBox != -1)
		{
			ThrowOutOfGround(iBox);

			EmitSoundToAll(SOUND_REWARD, iClient);

			Cel_PrintToChat(iClient, "You dug up a {green}cleers box{default} with {green}%d CL{default}! Press {green}E{default} on it.", iMoney);
		}

		return;
	}

	SpawnDugUp(g_sJunkModels[GetRandomInt(0, sizeof(g_sJunkModels) - 1)], fSpot, 0);
}

// Something dug up: it pops out of the ground and is gone again after a while. Money boxes hold cleers.
void SpawnDugUp(const char[] sModel, float fSpot[3], int iMoney)
{
	int iProp = CreateEntityByName("prop_physics_override");

	if (iProp == -1 || iProp > MAXENTITIES)
	{
		return;
	}

	DispatchKeyValue(iProp, "model", sModel);
	DispatchKeyValue(iProp, "classname", iMoney > 0 ? "cel_dug_money" : "cel_dug_junk");
	DispatchKeyValue(iProp, "spawnflags", "256");

	DispatchSpawn(iProp);

	TeleportEntity(iProp, fSpot, NULL_VECTOR, NULL_VECTOR);

	g_bDugUp[iProp] = true;
	g_iMoneyBox[iProp] = iMoney;
	g_iDugBy[iProp] = g_iDigger;

	// Nothing that is dug up can be broken: junk is meant to be carried to a trash can.
	SetEntProp(iProp, Prop_Data, "m_takedamage", 0, 1);

	if (iMoney > 0)
	{
		SetEntProp(iProp, Prop_Data, "m_takedamage", 0, 1);
		SetEntProp(iProp, Prop_Send, "m_nSkin", Cel_GetMoneyBoxSkin(iMoney));

		SDKHook(iProp, SDKHook_UsePost, Hook_MoneyBoxUse);

		KillAfter(iProp, 90.0);
	} else {
		KillAfter(iProp, 180.0);
	}

	ThrowOutOfGround(iProp);
}

void ThrowOutOfGround(int iEntity)
{
	float fVelocity[3];

	fVelocity[0] = GetRandomFloat(-60.0, 60.0);
	fVelocity[1] = GetRandomFloat(-60.0, 60.0);
	fVelocity[2] = 260.0;

	if (GetEntityMoveType(iEntity) == MOVETYPE_VPHYSICS)
	{
		TeleportEntity(iEntity, NULL_VECTOR, NULL_VECTOR, fVelocity);
	}
}

public void Hook_MoneyBoxUse(int iEntity, int iActivator, int iCaller, UseType utType, float fValue)
{
	if (!IsRealClient(iActivator) || g_iMoneyBox[iEntity] < 1)
	{
		return;
	}

	int iMoney = g_iMoneyBox[iEntity];

	g_iMoneyBox[iEntity] = 0;

	Cel_AddToClientBalance(iActivator, iMoney);

	EmitSoundToAll(SOUND_REWARD, iEntity);

	AcceptEntityInput(iEntity, "kill");

	Cel_PrintToChat(iActivator, "The money box had {green}%d CL{default} in it.", iMoney);
}

//Downloads for custom player models:
void AddModelToDownloads(const char[] sModel)
{
	static const char sExtensions[][] = { ".mdl", ".vvd", ".phy", ".dx80.vtx", ".dx90.vtx", ".sw.vtx", ".vtx" };
	char sBase[PLATFORM_MAX_PATH], sFile[PLATFORM_MAX_PATH];

	strcopy(sBase, sizeof(sBase), sModel);

	int iDot = FindCharInString(sBase, '.', true);

	if (iDot == -1)
	{
		return;
	}

	sBase[iDot] = '\0';

	for (int i = 0; i < sizeof(sExtensions); i++)
	{
		Format(sFile, sizeof(sFile), "%s%s", sBase, sExtensions[i]);

		// Only files the server really has, so stock models add nothing.
		if (FileExists(sFile, false))
		{
			AddFileToDownloadsTable(sFile);
		}
	}
}

void AddFolderToDownloads(const char[] sFolder)
{
	char sEntry[PLATFORM_MAX_PATH], sPath[PLATFORM_MAX_PATH];
	FileType ftType;

	DirectoryListing dlFolder = OpenDirectory(sFolder, false);

	if (dlFolder == null)
	{
		LogError("|CelMod| The player model materials folder '%s' does not exist.", sFolder);

		return;
	}

	while (dlFolder.GetNext(sEntry, sizeof(sEntry), ftType))
	{
		if (StrEqual(sEntry, ".") || StrEqual(sEntry, ".."))
		{
			continue;
		}

		Format(sPath, sizeof(sPath), "%s/%s", sFolder, sEntry);

		if (ftType == FileType_Directory)
		{
			AddFolderToDownloads(sPath);
		} else if (ftType == FileType_File)
		{
			AddFileToDownloadsTable(sPath);
		}
	}

	delete dlFolder;
}

Action SetModelGiven(int iClient, int iArgs, bool bGive)
{
	char sKey[64], sModel[64], sTarget[MAX_NAME_LENGTH];

	if (iArgs < 2)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]%s{default} <player> <model>", bGive ? "givemodel" : "takemodel");
		return Plugin_Handled;
	}

	GetCmdArg(1, sTarget, sizeof(sTarget));
	GetCmdArg(2, sModel, sizeof(sModel));

	int iTarget = FindTarget(iClient, sTarget, true, false);

	if (iTarget == -1)
	{
		return Plugin_Handled;
	}

	int iModel = FindPlayerModel(sModel);

	if (iModel == -1)
	{
		Cel_ReplyToCommand(iClient, "There is no player model called {green}%s{default}.", sModel);
		return Plugin_Handled;
	}

	Format(sKey, sizeof(sKey), "playermodel_%s", g_PlayerModels[iModel].sId);

	Inv_SetInt(iTarget, sKey, bGive ? 1 : 0);

	if (!bGive && g_iPlayerModel[iTarget] == iModel && !OwnsPlayerModel(iTarget, iModel))
	{
		g_iPlayerModel[iTarget] = -1;

		Inv_SetString(iTarget, "active_playermodel", "none");
	}

	if (bGive)
	{
		Cel_PrintToChat(iTarget, "You were given the {green}%s{default} player model. Wear it with {green}!playermodel %s{default}.", g_PlayerModels[iModel].sName, g_PlayerModels[iModel].sId);
		Cel_ReplyToCommand(iClient, "Gave the {green}%s{default} player model to {green}%N{default}.", g_PlayerModels[iModel].sName, iTarget);
	} else {
		Cel_ReplyToCommand(iClient, "Took the {green}%s{default} player model from {green}%N{default}.", g_PlayerModels[iModel].sName, iTarget);
	}

	return Plugin_Handled;
}

public Action Command_GiveModel(int iClient, int iArgs)
{
	return SetModelGiven(iClient, iArgs, true);
}

public Action Command_TakeModel(int iClient, int iArgs)
{
	return SetModelGiven(iClient, iArgs, false);
}

// A celwep shot: "ranged" hits whatever is aimed at, using the item's fx for the look; "melon" throws a watermelon.
void CelWepShoot(int iClient, int iItem)
{
	float fAngles[3], fDirection[3], fEnd[3], fStart[3];
	int iColor[4];

	CG_GetShootPosition(iClient, fStart);
	GetClientEyeAngles(iClient, fAngles);
	GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);

	if (StrEqual(g_Items[iItem].sAttack, "melon"))
	{
		if (GetEntityCount() > GetMaxEntities() - 200)
		{
			return;
		}

		int iMelon = CreateEntityByName("prop_physics_override");

		if (iMelon == -1)
		{
			return;
		}

		float fOrigin[3], fVelocity[3];

		fOrigin[0] = fStart[0] + fDirection[0] * 40.0;
		fOrigin[1] = fStart[1] + fDirection[1] * 40.0;
		fOrigin[2] = fStart[2] + fDirection[2] * 40.0;

		DispatchKeyValue(iMelon, "model", "models/props_junk/watermelon01.mdl");
		DispatchKeyValue(iMelon, "classname", "cel_melon");

		DispatchSpawn(iMelon);

		// Kills by the melon count as the shooter's.
		if (HasEntProp(iMelon, Prop_Data, "m_hPhysicsAttacker"))
		{
			SetEntPropEnt(iMelon, Prop_Data, "m_hPhysicsAttacker", iClient);
			SetEntPropFloat(iMelon, Prop_Data, "m_flLastPhysicsAttackerTime", GetGameTime() + 10.0);
		}

		fVelocity[0] = fDirection[0] * g_Items[iItem].fRange;
		fVelocity[1] = fDirection[1] * g_Items[iItem].fRange;
		fVelocity[2] = fDirection[2] * g_Items[iItem].fRange;

		TeleportEntity(iMelon, fOrigin, fAngles, fVelocity);

		KillAfter(iMelon, 8.0);

		EmitGameSoundToAll("Weapon_RPG.Single", iClient);

		return;
	}

	fEnd[0] = fStart[0] + fDirection[0] * g_Items[iItem].fRange;
	fEnd[1] = fStart[1] + fDirection[1] * g_Items[iItem].fRange;
	fEnd[2] = fStart[2] + fDirection[2] * g_Items[iItem].fRange;

	Handle hTrace = TR_TraceRayFilterEx(fStart, fEnd, MASK_SHOT, RayType_EndPoint, Filter_NotSelf, iClient);

	int iHit = -1;

	if (TR_DidHit(hTrace))
	{
		TR_GetEndPosition(fEnd, hTrace);

		iHit = TR_GetEntityIndex(hTrace);
	}

	CloseHandle(hTrace);

	iColor[0] = g_Items[iItem].iBeamColor[0];
	iColor[1] = g_Items[iItem].iBeamColor[1];
	iColor[2] = g_Items[iItem].iBeamColor[2];
	iColor[3] = 255;

	fStart[2] -= 6.0;

	DrawShotEffect(iClient, iItem, fStart, fEnd, fDirection, iColor);

	if (CanBeHurt(iClient, iHit))
	{
		SDKHooks_TakeDamage(iHit, iClient, iClient, g_Items[iItem].fHitDamage, DMG_BULLET);

		if (g_Items[iItem].fIgnite > 0.0)
		{
			IgniteEntity(iHit, g_Items[iItem].fIgnite);
		}

		if (g_Items[iItem].fSlow > 0.0)
		{
			g_fFrozenUntil[iHit] = GetGameTime() + g_Items[iItem].fSlow;
			g_bFrozenTint[iHit] = true;

			SetEntityRenderColor(iHit, 90, 160, 255, 255);
		}
	}
}

//Trash cans: dug up junk dropped into one is cleared away and pays a little.
static const char g_sTrashModels[][] =
{
	"models/props_junk/trashbin01a.mdl", "models/props_junk/trashdumpster01a.mdl", "models/props_junk/trashdumpster02.mdl",
	"models/props_lab/scrapyarddumpster.mdl", "models/props_trainstation/trashcan_indoor001a.mdl", "models/props_trainstation/trashcan_indoor001b.mdl"
};

// Every trash can in the map: any the map has as props, and any a player spawned.
void FindTrashCans()
{
	char sModel[PLATFORM_MAX_PATH];

	g_iTrashCanCount = 0;

	for (int i = MaxClients + 1; i <= MAXENTITIES && g_iTrashCanCount < sizeof(g_iTrashCans); i++)
	{
		if (!IsValidEntity(i) || !HasEntProp(i, Prop_Data, "m_ModelName"))
		{
			continue;
		}

		GetEntPropString(i, Prop_Data, "m_ModelName", sModel, sizeof(sModel));

		for (int m = 0; m < sizeof(g_sTrashModels); m++)
		{
			if (StrEqual(sModel, g_sTrashModels[m], false))
			{
				g_iTrashCans[g_iTrashCanCount++] = EntIndexToEntRef(i);

				break;
			}
		}
	}
}

void ThinkTrash()
{
	float fJunk[3], fCan[3], fMaxs[3], fMins[3];

	// The list of cans is refreshed every few seconds, as players spawn and remove them.
	if (g_iTick % 15 == 0)
	{
		FindTrashCans();
	}

	for (int iJunk = MaxClients + 1; iJunk <= MAXENTITIES; iJunk++)
	{
		if (!g_bDugUp[iJunk] || g_iMoneyBox[iJunk] > 0 || !IsValidEntity(iJunk))
		{
			continue;
		}

		GetEntPropVector(iJunk, Prop_Data, "m_vecAbsOrigin", fJunk);

		for (int c = 0; c < g_iTrashCanCount; c++)
		{
			int iCan = EntRefToEntIndex(g_iTrashCans[c]);

			if (iCan == INVALID_ENT_REFERENCE)
			{
				continue;
			}

			GetEntPropVector(iCan, Prop_Data, "m_vecAbsOrigin", fCan);
			GetEntPropVector(iCan, Prop_Send, "m_vecMins", fMins);
			GetEntPropVector(iCan, Prop_Send, "m_vecMaxs", fMaxs);

			// Inside the can: within its sides, and below its rim (a little above, while falling in).
			if (fJunk[0] < fCan[0] + fMins[0] || fJunk[0] > fCan[0] + fMaxs[0] || fJunk[1] < fCan[1] + fMins[1] || fJunk[1] > fCan[1] + fMaxs[1]
				|| fJunk[2] < fCan[2] + fMins[2] || fJunk[2] > fCan[2] + fMaxs[2] + 8.0)
			{
				continue;
			}

			// Whoever threw it in with the gravity gun gets the money, otherwise whoever dug it up.
			int iClient = -1;

			if (HasEntProp(iJunk, Prop_Data, "m_hPhysicsAttacker"))
			{
				iClient = GetEntPropEnt(iJunk, Prop_Data, "m_hPhysicsAttacker");
			}

			if (!IsRealClient(iClient))
			{
				iClient = GetClientOfUserId(g_iDugBy[iJunk]);
			}

			g_bDugUp[iJunk] = false;

			AcceptEntityInput(iJunk, "kill");

			EmitSoundToAll(SOUND_TRASH, iCan);

			if (IsRealClient(iClient))
			{
				int iReward = GetRandomInt(g_cvTrashMin.IntValue, g_cvTrashMax.IntValue);

				Cel_AddToClientBalance(iClient, iReward);

				Cel_PrintToChat(iClient, "Thanks for keeping the place clean! {green}+%d CL{default}", iReward);
			}

			break;
		}
	}
}

// The map is changing: every player holding an emblem box (now, or until a moment ago, as the gravity gun lets go
// when the map ends) keeps the emblem inside.
public void OnMapEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		int iBox = EntRefToEntIndex(g_iHeldBox[i]);

		g_iHeldBox[i] = INVALID_ENT_REFERENCE;

		if (!IsRealClient(i) || iBox == INVALID_ENT_REFERENCE || !g_bDropBox[iBox] || GetGameTime() - g_fHeldBoxTime[i] > 1.5)
		{
			continue;
		}

		ClaimDropBox(i, iBox, "You kept your emblem box");
	}

	// Boxes left lying in someone's land belong to that land's owner.
	float fOrigin[3];

	for (int iBox = MaxClients + 1; iBox <= MAXENTITIES && iBox < GetMaxEntities(); iBox++)
	{
		if (!g_bDropBox[iBox] || !IsValidEntity(iBox))
		{
			continue;
		}

		GetEntPropVector(iBox, Prop_Data, "m_vecAbsOrigin", fOrigin);

		int iOwner = Cel_GetLandOwnerFromPosition(fOrigin);

		if (iOwner > 0 && IsRealClient(iOwner))
		{
			ClaimDropBox(iOwner, iBox, "An emblem box was left in your land");
		}
	}
}

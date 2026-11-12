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

#define MAX_ITEMS 192
#define MAX_PLAYERMODELS 48

#define KIND_EMBLEM 0
#define KIND_HAT 1
#define KIND_WEAPON 2

#define BOOTH_MODEL "models/props_combine/suit_charger001.mdl"
#define BIG_EMBLEM_MODEL "models/celmod/bhys8.mdl"

#define GRAVGUN_CLASS "weapon_physcannon"
#define GRAVGUN_WORLDMODEL "models/weapons/w_physics.mdl"
#define DROPBOX_MODEL "models/items/item_item_crate.mdl"

#define SOUND_EQUIP "buttons/button9.wav"
#define SOUND_UNEQUIP "buttons/button10.wav"
#define SOUND_DENY "buttons/button8.wav"
#define SOUND_FIRE "ambient/fire/mtov_flame2.wav"
#define SOUND_WATER "ambient/water/water_splash1.wav"
#define SOUND_STEAM "ambient/gas/steam2.wav"
#define SOUND_FLAME "ambient/fire/fire_med_loop1.wav"
#define SOUND_FIREBALL "ambient/fire/gascan_ignite1.wav"
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
	char sBase[32];
	float fDamage;
}

enum struct PlayerModel
{
	char sId[32];
	char sName[48];
	char sModel[PLATFORM_MAX_PATH];
	int iPrice;
}

char g_sKindClass[][] = { "cel_emblem", "cel_hat", "cel_weapon" };
char g_sKindName[][] = { "emblem", "hat", "weapon" };
char g_sKindPlural[][] = { "emblems", "hats", "weapons" };
char g_sKindTitle[][] = { "Emblems", "Hats", "Weapons" };

ConVar g_cvUpgradeCost;

int g_iBoothRef = INVALID_ENT_REFERENCE;
int g_iCelWepItem[MAXPLAYERS + 1];
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
bool g_bGravityManaged[MAXPLAYERS + 1];
bool g_bPortal[MAXPLAYERS + 1][2];
bool g_bSpeedManaged[MAXPLAYERS + 1];
bool g_bThirdPerson[MAXPLAYERS + 1];

char g_sInvPath[MAXPLAYERS + 1][PLATFORM_MAX_PATH];
char g_sItemDB[PLATFORM_MAX_PATH];
char g_sMap[64];
char g_sRewardDB[PLATFORM_MAX_PATH];

ConVar g_cvDropClaimTime;
ConVar g_cvDropCount;
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
int g_iTick;

Item g_Items[MAX_ITEMS];

KeyValues g_kvInv[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	CreateNative("Cel_GetCollectibleId", Native_GetCollectibleId);
	CreateNative("Cel_GetCollectibleName", Native_GetCollectibleName);
	CreateNative("Cel_GetCollectibleLook", Native_GetCollectibleLook);
	CreateNative("Cel_GiveCollectible", Native_GiveCollectible);
	CreateNative("Cel_IsCollectible", Native_IsCollectible);
	CreateNative("Cel_SpawnCollectible", Native_SpawnCollectible);

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

	g_cvDropClaimTime = CreateConVar("cm_drop_claim_time", "30.0", "Seconds after an emblem drop starts before the crates are checked against player lands.", _, true, 5.0);
	g_cvDropCount = CreateConVar("cm_drop_count", "5", "Number of crates in one emblem drop.", _, true, 1.0, true, 30.0);
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
	RegAdminCmd("v_tune", Command_Tune, ADMFLAG_SLAY, "|CelMod| Adjusts where your held emblem or worn hat sits, live, and prints the values for collectibles.txt.");
	RegAdminCmd("v_reward", Command_Reward, ADMFLAG_SLAY, "|CelMod| Creates a reward pickup that gives an emblem or hat once per player.");
	RegConsoleCmd("v_firstperson", Command_FirstPerson, "|CelMod| Switches back to the first person view.");
	RegConsoleCmd("v_thirdperson", Command_ThirdPerson, "|CelMod| Switches to a third person view so you can see your emblem and hat.");
	RegAdminCmd("v_powerbooth", Command_PowerBooth, ADMFLAG_SLAY, "|CelMod| Moves the Power Booth to where you are looking.");
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
	GetCurrentMap(g_sMap, sizeof(g_sMap));

	PrecacheModel(GRAVGUN_WORLDMODEL, true);
	PrecacheModel(DROPBOX_MODEL, true);

	PrecacheSound(SOUND_EQUIP, true);
	PrecacheSound(SOUND_UNEQUIP, true);
	PrecacheSound(SOUND_DENY, true);
	PrecacheSound(SOUND_FIRE, true);
	PrecacheSound(SOUND_ICE, true);
	PrecacheSound(SOUND_SHOCK, true);
	PrecacheSound(SOUND_HEAL, true);
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
	}

	g_iMinutesSinceDrop = 0;
	g_iBoothRef = INVALID_ENT_REFERENCE;

	PrecacheModel(BOOTH_MODEL, true);

	CreateTimer(5.0, Timer_SpawnBooth, _, TIMER_FLAG_NO_MAPCHANGE);

	LoadItems();
	LoadRewards();
}

public void OnClientPutInServer(int iClient)
{
	ResetClient(iClient);

	g_bThirdPerson[iClient] = false;

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
	if (iEntity > 0 && iEntity <= MAXENTITIES)
	{
		g_bDropBox[iEntity] = false;
		g_iEntItem[iEntity] = -1;
		g_iRewardId[iEntity] = -1;
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
		return;
	}

	if (bEnable)
	{
		SetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget", 0);
		SetEntProp(iClient, Prop_Send, "m_iObserverMode", 1);
		SetEntProp(iClient, Prop_Send, "m_bDrawViewmodel", 0);
		SetEntProp(iClient, Prop_Send, "m_iFOV", 110);
	} else {
		SetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget", -1);
		SetEntProp(iClient, Prop_Send, "m_iObserverMode", 0);
		SetEntProp(iClient, Prop_Send, "m_bDrawViewmodel", 1);
		SetEntProp(iClient, Prop_Send, "m_iFOV", 0);
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

// Moves the held emblem or the worn hat while you watch, so the right values can be found without editing
// the file and changing map each time. Nothing is saved: the printed lines go into collectibles.txt.
public Action Command_Tune(int iClient, int iArgs)
{
	char sArg[8][24];
	float fValues[7];

	if (!IsRealClient(iClient))
	{
		return Plugin_Handled;
	}

	if (iArgs < 7)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]tune{default} <hand/hat> <forward> <left> <up> <pitch> <yaw> <roll> [scale]");
		return Plugin_Handled;
	}

	for (int i = 0; i < 8 && i < iArgs; i++)
	{
		GetCmdArg(i + 1, sArg[i], sizeof(sArg[]));

		if (i > 0)
		{
			fValues[i - 1] = StringToFloat(sArg[i]);
		}
	}

	if (StrEqual(sArg[0], "hand", false))
	{
		int iItem = g_iActiveEmblem[iClient];

		if (iItem == -1)
		{
			Cel_ReplyToCommand(iClient, "Enable an emblem first.");
			return Plugin_Handled;
		}

		// Every emblem that uses the same model is held the same way.
		for (int i = 0; i < g_iItemCount; i++)
		{
			if (g_Items[i].iKind != KIND_EMBLEM || !StrEqual(g_Items[i].sModel, g_Items[iItem].sModel))
			{
				continue;
			}

			g_Items[i].fHandOffset[0] = fValues[0];
			g_Items[i].fHandOffset[1] = fValues[1];
			g_Items[i].fHandOffset[2] = fValues[2];
			g_Items[i].fHandAngles[0] = fValues[3];
			g_Items[i].fHandAngles[1] = fValues[4];
			g_Items[i].fHandAngles[2] = fValues[5];

			if (iArgs >= 8)
			{
				g_Items[i].fHandScale = fValues[6];
			}
		}

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				RestoreWeapon(i);
			}
		}

		Cel_ReplyToCommand(iClient, "\"handoffset\" \"%.1f %.1f %.1f\"  \"handangles\" \"%.1f %.1f %.1f\"  \"handscale\" \"%.2f\"", fValues[0], fValues[1], fValues[2], fValues[3], fValues[4], fValues[5], g_Items[iItem].fHandScale);
	} else {
		int iItem = g_iActiveHat[iClient];

		if (iItem == -1)
		{
			Cel_ReplyToCommand(iClient, "Put a hat on first.");
			return Plugin_Handled;
		}

		g_Items[iItem].fOffset[0] = fValues[0];
		g_Items[iItem].fOffset[1] = fValues[1];
		g_Items[iItem].fOffset[2] = fValues[2];
		g_Items[iItem].fAngles[0] = fValues[3];
		g_Items[iItem].fAngles[1] = fValues[4];
		g_Items[iItem].fAngles[2] = fValues[5];

		if (iArgs >= 8)
		{
			g_Items[iItem].fScale = fValues[6];
		}

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && g_iActiveHat[i] == iItem)
			{
				CreateHatEntity(i);
			}
		}

		Cel_ReplyToCommand(iClient, "\"offset\" \"%.1f %.1f %.1f\"  \"angles\" \"%.1f %.1f %.1f\"  \"scale\" \"%.2f\"", fValues[0], fValues[1], fValues[2], fValues[3], fValues[4], fValues[5], g_Items[iItem].fScale);
	}

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

		g_bHoldingGravGun[iClient] = false;
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
	int iLast = g_iLastButtons[iClient];

	g_iLastButtons[iClient] = iButtons;

	int iItem = g_iActiveEmblem[iClient];

	if (iItem == -1 || !g_bHoldingGravGun[iClient] || !IsPlayerAlive(iClient))
	{
		return Plugin_Continue;
	}

	if (StrEqual(g_Items[iItem].sPower, "jump"))
	{
		if ((iButtons & IN_JUMP) && !(iLast & IN_JUMP) && (GetEntityFlags(iClient) & FL_ONGROUND))
		{
			RequestFrame(Frame_Jump, GetClientUserId(iClient));
		}
	} else if (StrEqual(g_Items[iItem].sPower, "feather"))
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

	return Plugin_Continue;
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

	if (iItem == -1 || !StrEqual(g_Items[iItem].sPower, "jump"))
	{
		return;
	}

	GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", fVelocity);

	fVelocity[2] = g_Items[iItem].fValue;

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

	Inv_GetString(iClient, "active_emblem", sId, sizeof(sId));

	int iItem = FindItem(KIND_EMBLEM, sId);

	if (iItem != -1 && GetOwned(iClient, iItem) > 0)
	{
		g_iActiveEmblem[iClient] = iItem;
	}

	Inv_GetString(iClient, "active_weapon", sId, sizeof(sId));

	iItem = FindItem(KIND_WEAPON, sId);

	if (iItem != -1 && GetOwned(iClient, iItem) > 0 && IsPlayerAlive(iClient))
	{
		SetActiveCelWep(iClient, iItem);
	}

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
		CreateHatEntity(iClient);

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

		g_bHoldingGravGun[i] = false;

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

			if (g_bHoldingGravGun[i] && iItem != -1)
			{
				// The speed emblem uses its value, any other emblem can carry a "speed" key.
				fSpeed = StrEqual(g_Items[iItem].sPower, "speed") ? g_Items[iItem].fValue : g_Items[iItem].fSpeed;
			}
		}

		if (fSpeed != 1.0 || g_bSpeedManaged[i])
		{
			SetEntPropFloat(i, Prop_Data, "m_flLaggedMovementValue", fSpeed);

			g_bSpeedManaged[i] = (fSpeed != 1.0);
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
		if (g_bHoldingGravGun[i] && iItem != -1 && StrEqual(g_Items[iItem].sPower, "gravity"))
		{
			g_bGravityManaged[i] = true;

			SetEntityGravity(i, g_Items[iItem].fValue);
		} else if (g_bGravityManaged[i])
		{
			g_bGravityManaged[i] = false;

			SetEntityGravity(i, 1.0);
		}

		// Sprint: the suit's sprint power never runs out.
		if (g_bHoldingGravGun[i] && iItem != -1 && StrEqual(g_Items[iItem].sPower, "sprint"))
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

public Action Timer_DropSettle(Handle hTimer, any iRef)
{
	float fOrigin[3];
	int iBox = EntRefToEntIndex(iRef);

	if (iBox == INVALID_ENT_REFERENCE || iBox < 1 || !g_bDropBox[iBox])
	{
		return Plugin_Stop;
	}

	int iItem = g_iEntItem[iBox];

	GetEntPropVector(iBox, Prop_Data, "m_vecAbsOrigin", fOrigin);

	g_bDropBox[iBox] = false;
	g_iEntItem[iBox] = -1;

	AcceptEntityInput(iBox, "kill");

	TE_SetupBeamRingPoint(fOrigin, 10.0, 120.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.6, 6.0, 0.0, g_iOrange, 10, 0);
	TE_SendToAll();

	if (iItem < 0 || iItem >= g_iItemCount)
	{
		return Plugin_Stop;
	}

	int iOwner = Cel_GetLandOwnerFromPosition(fOrigin);

	if (!IsRealClient(iOwner) || !Cel_IsLandCreated(iOwner))
	{
		return Plugin_Stop;
	}

	fOrigin[2] += 8.0;

	int iEntity = SpawnItemEntity(iOwner, iItem, fOrigin, g_fZero);

	if (iEntity != -1)
	{
		Cel_DropEntityToFloor(iEntity);
	}

	SetOwned(iOwner, iItem, GetOwned(iOwner, iItem) + 1);

	Cel_PrintToChatAll("A crate landed in {green}%N{default}'s land and contained a {green}%s{default} %s!", iOwner, g_Items[iItem].sName, g_sKindName[g_Items[iItem].iKind]);

	return Plugin_Stop;
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

			// The large model is about eight times the size, in the hand it is shown a little bigger than normal.
			g_Items[iBig].fHandScale = g_Items[i].fHandScale * 0.18;
		} else {
			g_Items[iBig].fScale = g_Items[i].fScale * 2.0;
			g_Items[iBig].fHandScale = g_Items[i].fHandScale * 1.4;
		}

		g_Items[iBig].iModelIndex = PrecacheModel(g_Items[iBig].sModel, true);
		g_Items[iBig].fCooldown = g_Items[i].fCooldown * 0.75;
		g_Items[iBig].fSecondaryValue = g_Items[i].fSecondaryValue * 1.5;
		g_Items[iBig].fSecondaryCooldown = g_Items[i].fSecondaryCooldown * 0.75;
		g_Items[iBig].iWeight = 0;
		g_Items[iBig].bIsBig = true;
		g_Items[iBig].iBig = -1;

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
	g_Items[iItem].iBig = -1;
	g_Items[iItem].bIsBig = false;

	kvItems.GetString("base", g_Items[iItem].sBase, sizeof(Item::sBase), "weapon_crowbar");

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
	kvItems.GetString("secondary", g_Items[iItem].sSecondary, sizeof(Item::sSecondary), "none");

	g_Items[iItem].fSecondaryValue = kvItems.GetFloat("secondaryvalue", 50.0);
	g_Items[iItem].fSecondaryCooldown = kvItems.GetFloat("secondarycooldown", 3.0);
	kvItems.GetString("sprite", g_Items[iItem].sSprite, sizeof(Item::sSprite), "sprites/glow04_noz.vmt");

	g_Items[iItem].iSpriteIndex = PrecacheModel(g_Items[iItem].sSprite, true);
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

	DispatchKeyValue(iHand, "model", g_Items[iItem].sModel);
	DispatchKeyValue(iHand, "solid", "0");
	DispatchKeyValue(iHand, "skin", sSkin);
	DispatchKeyValue(iHand, "classname", "cel_emblem_held");
	DispatchKeyValueFloat(iHand, "modelscale", g_Items[iItem].fHandScale);

	DispatchSpawn(iHand);

	SetEntityRenderColor(iHand, g_Items[iItem].iColor[0], g_Items[iItem].iColor[1], g_Items[iItem].iColor[2], 255);

	SetVariantString("!activator");
	AcceptEntityInput(iHand, "SetParent", iClient, iHand);

	SetVariantString("anim_attachment_RH");
	AcceptEntityInput(iHand, "SetParentAttachment", iHand, iHand);

	// Once parented to the attachment these are relative to the player's right hand.
	TeleportEntity(iHand, g_Items[iItem].fHandOffset, g_Items[iItem].fHandAngles, NULL_VECTOR);

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

bool IsShotPower(const char[] sPower)
{
	return (StrEqual(sPower, "fire") || StrEqual(sPower, "blizzard") || StrEqual(sPower, "shock") || StrEqual(sPower, "push") || StrEqual(sPower, "blast") || StrEqual(sPower, "blink")
		|| StrEqual(sPower, "flamethrower") || StrEqual(sPower, "shot") || StrEqual(sPower, "spray") || StrEqual(sPower, "medic") || StrEqual(sPower, "magnitude") || StrEqual(sPower, "chaos") || StrEqual(sPower, "portal") || StrEqual(sPower, "demon"));
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

	// Demon: a purple burst where the player aims, nothing more.
	if (StrEqual(sPower, "demon"))
	{
		TE_SetupBeamRingPoint(fEnd, 4.0, 120.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.5, 8.0, 0.0, iColor, 10, 0);
		TE_SendToAll();

		SpriteSpray(fEnd, g_fSkyward, g_Items[iItem].iSpriteIndex, 180, 0.3, 14);

		EmitSoundToAll(SOUND_FIRE, iClient);

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

	if (StrEqual(sFx, "flame"))
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
void LaunchSprite(int iItem, float fStart[3], float fEnd[3], int iColor[4], float fSpeed, float fScale, bool bGravity)
{
	char sBuffer[64];
	float fVelocity[3];

	float fDistance = GetVectorDistance(fStart, fEnd);

	// Nothing to show at point blank range, and never spawn sprites when the map is nearly out of entities.
	if (fDistance < 24.0 || GetEntityCount() > GetMaxEntities() - 200)
	{
		return;
	}

	int iSprite = CreateEntityByName("env_sprite");

	if (iSprite == -1)
	{
		return;
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

	fVelocity[0] = (fEnd[0] - fStart[0]) / fLife;
	fVelocity[1] = (fEnd[1] - fStart[1]) / fLife;
	fVelocity[2] = (fEnd[2] - fStart[2]) / fLife;

	if (bGravity)
	{
		// Thrown upwards just enough to land on the target after falling.
		fVelocity[2] += 0.5 * FindConVar("sv_gravity").FloatValue * fLife;

		SetEntityMoveType(iSprite, MOVETYPE_FLYGRAVITY);
	} else {
		SetEntityMoveType(iSprite, MOVETYPE_NOCLIP);
	}

	TeleportEntity(iSprite, fStart, NULL_VECTOR, fVelocity);

	Format(sBuffer, sizeof(sBuffer), "OnUser1 !self:Kill::%.2f:1", fLife);

	SetVariantString(sBuffer);
	AcceptEntityInput(iSprite, "AddOutput");
	AcceptEntityInput(iSprite, "FireUser1");
}

// A burst of sprites thrown in a direction, they fall and fade on their own.
void SpriteSpray(float fOrigin[3], float fDirection[3], int iModelIndex, int iSpeed, float fNoise, int iCount)
{
	if (iModelIndex < 1)
	{
		return;
	}

	TE_Start("Sprite Spray");
	TE_WriteVector("m_vecOrigin", fOrigin);
	TE_WriteVector("m_vecDirection", fDirection);
	TE_WriteNum("m_nModelIndex", iModelIndex);
	TE_WriteNum("m_nSpeed", iSpeed);
	TE_WriteFloat("m_fNoise", fNoise);
	TE_WriteNum("m_nCount", iCount);
	TE_SendToAll();
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

	SpriteSpray(fMuzzle, fDirection, g_Items[iItem].iSpriteIndex, RoundToFloor(g_Items[iItem].fRange * 1.6), 0.12, 4);

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

// Right click attacks chosen with the "secondary" key.
void SecondaryAttack(int iClient, int iItem)
{
	float fDirection[3], fEnd[3], fStart[3], fVictim[3];
	int iColor[4];

	iColor[0] = g_Items[iItem].iBeamColor[0];
	iColor[1] = g_Items[iItem].iBeamColor[1];
	iColor[2] = g_Items[iItem].iBeamColor[2];
	iColor[3] = 255;

	// Fireball: a big ball of fire that explodes where it lands.
	if (StrEqual(g_Items[iItem].sSecondary, "fireball"))
	{
		TraceEmblemAim(iClient, 3000.0, fStart, fDirection, fEnd);

		fStart[2] -= 12.0;

		float fLife = GetVectorDistance(fStart, fEnd) / 900.0;

		LaunchSprite(iItem, fStart, fEnd, iColor, 900.0, 2.5, false);

		EmitSoundToAll(SOUND_FIREBALL, iClient);

		DataPack dpFireball;

		CreateDataTimer(fLife < 0.1 ? 0.1 : fLife, Timer_Fireball, dpFireball, TIMER_FLAG_NO_MAPCHANGE);

		dpFireball.WriteCell(GetClientUserId(iClient));
		dpFireball.WriteCell(iItem);
		dpFireball.WriteFloat(fEnd[0] - fDirection[0] * 8.0);
		dpFireball.WriteFloat(fEnd[1] - fDirection[1] * 8.0);
		dpFireball.WriteFloat(fEnd[2] - fDirection[2] * 8.0);

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

public Action Timer_Fireball(Handle hTimer, DataPack dpFireball)
{
	float fOrigin[3], fVictim[3];

	dpFireball.Reset();

	int iClient = GetClientOfUserId(dpFireball.ReadCell());
	int iItem = dpFireball.ReadCell();

	fOrigin[0] = dpFireball.ReadFloat();
	fOrigin[1] = dpFireball.ReadFloat();
	fOrigin[2] = dpFireball.ReadFloat();

	if (iClient < 1 || !IsClientInGame(iClient) || iItem < 0 || iItem >= g_iItemCount)
	{
		return Plugin_Stop;
	}

	CreateExplosion(iClient, fOrigin, g_Items[iItem].fSecondaryValue);

	SpriteSpray(fOrigin, g_fSkyward, g_Items[iItem].iSpriteIndex, 300, 0.9, 20);

	// Whoever is caught in the blast is left burning.
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!CanBeHurt(iClient, i))
		{
			continue;
		}

		GetClientAbsOrigin(i, fVictim);

		if (GetVectorDistance(fVictim, fOrigin) <= 150.0)
		{
			IgniteEntity(i, 4.0);
		}
	}

	return Plugin_Stop;
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

	// Demon: slams the holder straight down.
	if (StrEqual(sPower, "demon"))
	{
		if (!(GetEntityFlags(iClient) & FL_ONGROUND))
		{
			GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", fVelocity);

			fVelocity[2] = -1000.0;

			TeleportEntity(iClient, NULL_VECTOR, NULL_VECTOR, fVelocity);
		}

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

	if (iItem == -1 || !StrEqual(g_Items[iItem].sPower, "resist"))
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

void CreateHatEntity(int iClient)
{
	int iItem = g_iActiveHat[iClient];

	RemoveHatEntity(iClient);

	if (iItem == -1 || !IsClientInGame(iClient) || !IsPlayerAlive(iClient))
	{
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
	DispatchKeyValueFloat(iHat, "modelscale", g_Items[iItem].fScale);

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
		// Once parented to the attachment these are relative to the player's head.
		TeleportEntity(iHat, g_Items[iItem].fOffset, g_Items[iItem].fAngles, NULL_VECTOR);
	} else {
		// No head attachment at all: the hat sits at standing head height above the player's feet.
		float fFallback[3];

		fFallback[0] = g_Items[iItem].fOffset[0];
		fFallback[1] = g_Items[iItem].fOffset[1];
		fFallback[2] = g_Items[iItem].fOffset[2] + 64.0;

		TeleportEntity(iHat, fFallback, g_Items[iItem].fAngles, NULL_VECTOR);
	}

	g_iHatEntRef[iClient] = EntIndexToEntRef(iHat);

	SDKHook(iHat, SDKHook_SetTransmit, Hook_HatTransmit);
}

//Emblem drops:
int StartDrop(int iCount)
{
	float fOrigin[3];
	int iBox, iItem, iSpawned = 0;

	g_iMinutesSinceDrop = 0;

	for (int i = 0; i < iCount; i++)
	{
		iItem = PickRandomItem(-1);

		if (iItem == -1 || !FindDropPosition(fOrigin))
		{
			continue;
		}

		iBox = CreateEntityByName("prop_physics_override");

		if (iBox == -1 || iBox > MAXENTITIES)
		{
			continue;
		}

		DispatchKeyValue(iBox, "model", DROPBOX_MODEL);
		DispatchKeyValue(iBox, "classname", "cel_dropbox");

		DispatchSpawn(iBox);

		TeleportEntity(iBox, fOrigin, NULL_VECTOR, NULL_VECTOR);

		// The crate must survive the fall and being thrown around with the gravity gun.
		SetEntProp(iBox, Prop_Data, "m_takedamage", 0, 1);
		SetEntityRenderColor(iBox, g_Items[iItem].iColor[0], g_Items[iItem].iColor[1], g_Items[iItem].iColor[2], 255);

		g_bDropBox[iBox] = true;
		g_iEntItem[iBox] = iItem;
		g_iRewardId[iBox] = -1;

		CreateTimer(g_cvDropClaimTime.FloatValue, Timer_DropSettle, EntIndexToEntRef(iBox), TIMER_FLAG_NO_MAPCHANGE);

		iSpawned++;
	}

	if (iSpawned > 0)
	{
		EmitSoundToAll(SOUND_DROP);

		Cel_PrintToChatAll("{green}Emblem drop!{default} %d crate%s falling from the sky. Any crate inside your land in {green}%d{default} seconds is yours.", iSpawned, iSpawned == 1 ? " is" : "s are", RoundToFloor(g_cvDropClaimTime.FloatValue));
	}

	return iSpawned;
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

			SpawnRewardEntity(StringToInt(sSection), KindFromName(sKind), sId, fOrigin);
		}
		while (kvRewards.GotoNextKey());
	}

	delete kvRewards;
}

// Writes a reward to this map's file. Pass -1 as the id to use the next free one. Returns the id.
int SaveReward(int iId, int iKind, const char[] sId, float fOrigin[3])
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
		strcopy(sModel, sizeof(sModel), iKind == KIND_EMBLEM ? GRAVGUN_WORLDMODEL : DROPBOX_MODEL);
	}

	int iEntity = CreateEntityByName("prop_physics_override");

	if (iEntity == -1 || iEntity > MAXENTITIES)
	{
		return -1;
	}

	PrecacheModel(sModel);

	DispatchKeyValue(iEntity, "model", sModel);
	DispatchKeyValue(iEntity, "classname", "cel_reward");
	DispatchKeyValue(iEntity, "spawnflags", "264");

	DispatchSpawn(iEntity);

	TeleportEntity(iEntity, fOrigin, NULL_VECTOR, NULL_VECTOR);

	AcceptEntityInput(iEntity, "disablemotion");

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

	SDKHook(iEntity, SDKHook_UsePost, Hook_RewardUse);

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
	g_bGravityManaged[iClient] = false;
	g_bPortal[iClient][0] = false;
	g_bPortal[iClient][1] = false;
	g_fNextSecondary[iClient] = 0.0;
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

	return (g_PlayerModels[iModel].iPrice < 1 || Inv_GetInt(iClient, sKey) == 1);
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
	fOrigin[2] += 48.0;

	SpawnPowerBooth(fOrigin);

	return Plugin_Stop;
}

void SpawnPowerBooth(float fOrigin[3])
{
	int iOld = EntRefToEntIndex(g_iBoothRef);

	if (g_iBoothRef != INVALID_ENT_REFERENCE && iOld != INVALID_ENT_REFERENCE && iOld > MaxClients)
	{
		AcceptEntityInput(iOld, "kill");
	}

	g_iBoothRef = INVALID_ENT_REFERENCE;

	int iBooth = CreateEntityByName("prop_physics_override");

	if (iBooth == -1)
	{
		return;
	}

	DispatchKeyValue(iBooth, "model", BOOTH_MODEL);
	DispatchKeyValue(iBooth, "classname", "cel_powerbooth");
	DispatchKeyValue(iBooth, "spawnflags", "264");

	DispatchSpawn(iBooth);

	TeleportEntity(iBooth, fOrigin, NULL_VECTOR, NULL_VECTOR);

	AcceptEntityInput(iBooth, "disablemotion");

	SetEntProp(iBooth, Prop_Data, "m_takedamage", 0, 1);

	// Green, see-through and flickering, as it was on the original server.
	SetEntityRenderMode(iBooth, RENDER_TRANSCOLOR);
	SetEntityRenderColor(iBooth, 0, 255, 0, 150);
	SetEntityRenderFx(iBooth, RENDERFX_DISTORT);

	SDKHook(iBooth, SDKHook_UsePost, Hook_BoothUse);

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

	fOrigin[2] += 48.0;

	SpawnPowerBooth(fOrigin);

	Cel_ReplyToCommand(iClient, "The Power Booth has been moved here for this map.");

	return Plugin_Handled;
}

public void Hook_BoothUse(int iEntity, int iActivator, int iCaller, UseType utType, float fValue)
{
	float fOrigin[3];
	int iCost = g_cvUpgradeCost.IntValue, iChosen = -1;

	if (!IsRealClient(iActivator))
	{
		return;
	}

	// The enabled emblem is upgraded first, otherwise the first emblem the player has enough of.
	if (g_iActiveEmblem[iActivator] != -1 && g_Items[g_iActiveEmblem[iActivator]].iBig != -1 && GetOwned(iActivator, g_iActiveEmblem[iActivator]) >= iCost)
	{
		iChosen = g_iActiveEmblem[iActivator];
	}

	for (int i = 0; i < g_iItemCount && iChosen == -1; i++)
	{
		if (g_Items[i].iKind == KIND_EMBLEM && g_Items[i].iBig != -1 && GetOwned(iActivator, i) >= iCost)
		{
			iChosen = i;
		}
	}

	if (iChosen == -1)
	{
		EmitSoundToClient(iActivator, SOUND_DENY);

		Cel_PrintToChat(iActivator, "{green}Power Booth:{default} bring {green}%d{default} of the same emblem and I will turn them into one big emblem.", iCost);

		return;
	}

	int iLeft = GetOwned(iActivator, iChosen) - iCost;

	SetOwned(iActivator, iChosen, iLeft);

	// Spawned copies the player no longer owns are removed.
	int iSpawned = CountSpawned(iActivator, iChosen);

	for (int i = MaxClients + 1; i <= MAXENTITIES && iSpawned > iLeft; i++)
	{
		if (g_iEntItem[i] == iChosen && IsItemEntity(i) && Cel_CheckOwner(iActivator, i))
		{
			AcceptEntityInput(i, "kill");

			iSpawned--;
		}
	}

	if (iLeft < 1 && g_iActiveEmblem[iActivator] == iChosen)
	{
		SetActiveEmblem(iActivator, -1);
	}

	GiveItem(iActivator, g_Items[iChosen].iBig);

	GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", fOrigin);

	TE_SetupBeamRingPoint(fOrigin, 10.0, 220.0, Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.8, 10.0, 0.0, g_iGreen, 10, 0);
	TE_SendToAll();

	EmitSoundToAll(SOUND_REWARD, iEntity);

	Cel_PrintToChatAll("{green}%N{default} used the Power Booth to make a {green}%s{default} emblem!", iActivator, g_Items[g_Items[iChosen].iBig].sName);
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

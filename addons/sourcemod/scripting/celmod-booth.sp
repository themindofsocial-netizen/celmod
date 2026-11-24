#pragma semicolon 1

#include <celmod>

#pragma newdecls required

/*
 * |CelMod| Guess Booth
 *
 * A small Combine-blue square at a spot an admin chose for the map (!setguessbooth, saved as data/celmod/guessbooth/<map>.txt),
 * with three props floating in it. Maps without a saved spot have no Guess Booth.
 * One of the three is the winner. A player standing in the booth gets one guess per map; a right guess pays out.
 *
 * Players auction their own emblems, hats and celweps above the booth (!auction): others bid with !bid, and when
 * it ends the item goes to the highest bidder and their bid to the seller. Nothing changes hands until the end, so
 * nobody loses an item or money if someone leaves. Admins can also auction items the server gives away.
 */

#define BOOTH_HALF 136.0
#define DISPLAY_SIZE 38.0
#define HOST_MODEL "models/breen.mdl"
#define HOST_HELLO "vo/breencast/br_welcome01.wav"
#define HOLO_HEIGHT 60.0
#define HOLO_SPACING 80.0

bool g_bAuction;

float g_fSpinCenter[MAXENTITIES + 1][3];
float g_fSpinOffset[MAXENTITIES + 1][3];
float g_fSpinYaw;
bool g_bBooth;

char g_sAuctionId[64];
char g_sAuctionKind[32];
char g_sAuctionName[64];
char g_sPropAlias[3][64];
char g_sSpawnDB[PLATFORM_MAX_PATH];
char g_sBoothDB[PLATFORM_MAX_PATH];

ConVar g_cvReward;
ConVar g_cvXPGuess;

float g_fAuctionEnd;
float g_fCenter[3];
//Which way the booth faces: the way the admin who placed it was looking. Dr. Breen stands at the far side facing
//back, and the three props run left to right in front of him. 90 (north) is the old fixed layout.
float g_fBoothYaw = 90.0;

int g_iAuctionRef = INVALID_ENT_REFERENCE;
int g_iBeam = -1;
int g_iHostRef = INVALID_ENT_REFERENCE;
ArrayList g_alStructure; //the Combine props the booth is built from
float g_fPostTop[4][3]; //the top of each corner post (back left, back right, front left, front right)
float g_fHostForward; //how far back Dr. Breen stands (in front of his monitor wall)
int g_iGlowSprite = -1;
int g_iBoothTick;

//The stock Half-Life 2 props the booth is built from.
char g_sStructureModels[][] =
{
	"models/props_combine/breenconsole.mdl",
	"models/props_combine/combine_monitorbay.mdl",
	"models/props_combine/breenglobe.mdl",
	"models/props_combine/combine_fence01a.mdl",
	"models/props_combine/combine_fence01b.mdl",
	"models/props_combine/railing_256.mdl",
	"models/props_combine/combine_emitter01.mdl"
};

//Players Dr. Breen has already greeted on this map.
bool g_bGreeted[MAXPLAYERS + 1];
int g_iPropRef[3] = { INVALID_ENT_REFERENCE, INVALID_ENT_REFERENCE, INVALID_ENT_REFERENCE };
int g_iTopBid;
int g_iTopBidder;

//The player selling (userid), or 0 for an item the server gives (an admin's auction).
int g_iAuctionSeller;
char g_sSellerName[MAX_NAME_LENGTH];

//Every bid of this auction (bidder userid and amount), so if the top bidder can't pay at the end the next one wins.
#define MAX_BIDS 64
int g_iBidUser[MAX_BIDS];
int g_iBidAmount[MAX_BIDS];
int g_iBidCount;
ConVar g_cvAuctionMinutes;

//Steam ids of everyone who has used their guess on this map.
StringMap g_smGuessed;
StringMap g_smAnswer; //each player's own winning prop (0-2) for this map, by Steam ID

public Plugin myinfo =
{
	name = "|CelMod| Guess Booth",
	author = CEL_AUTHOR,
	description = "The Guess Booth and the auctions held above it.",
	version = CEL_VERSION,
	url = CEL_URL
};

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	MarkNativeAsOptional("Cel_AddTacticsXP");
	
	CreateNative("Cel_GetGuessBoothArea", Native_GetGuessBoothArea);
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	
	BuildPath(Path_SM, g_sSpawnDB, sizeof(g_sSpawnDB), "data/celmod/spawns.txt");
	BuildPath(Path_SM, g_sBoothDB, sizeof(g_sBoothDB), "data/celmod/guessbooth.txt");
	
	g_smGuessed = new StringMap();
	g_smAnswer = new StringMap();
	
	g_cvXPGuess = CreateConVar("cm_tactics_xp_guess", "15", "Tactics experience for a correct guess at the Guess Booth.", _, true, 0.0);
	g_cvReward = CreateConVar("cm_guess_reward", "5000", "Cleers paid for a correct guess at the Guess Booth.", _, true, 0.0);
	
	AutoExecConfig(true, "celmod.booth");
	
	RegConsoleCmd("v_auction", Command_Auction, "|CelMod| Auctions one of your emblems, hats or celweps above the Guess Booth: !auction <emblem/hat/weapon> <name> <minutes> [starting bid], or !auction cancel.");
	g_cvAuctionMinutes = CreateConVar("cm_auction_max_minutes", "10", "Longest auction a player can start, in minutes (admins can run longer ones).", _, true, 1.0);
	RegAdminCmd("v_guessbooth", Command_GuessBooth, ADMFLAG_SLAY, "|CelMod| Moves the Guess Booth to where you are standing for this map only, with new props.");
	RegAdminCmd("v_setguessbooth", Command_SetGuessBooth, ADMFLAG_SLAY, "|CelMod| Saves where you are standing as this map's Guess Booth spot and puts the booth there.");
	RegAdminCmd("v_delguessbooth", Command_DelGuessBooth, ADMFLAG_SLAY, "|CelMod| Removes this map's saved Guess Booth spot and the booth with it.");
	RegConsoleCmd("v_bid", Command_Bid, "|CelMod| Bids on the item being auctioned above the Guess Booth.");
	RegConsoleCmd("v_guess", Command_Guess, "|CelMod| Guesses the winning prop at the Guess Booth. One guess per map.");
	
	CreateTimer(1.0, Timer_Booth, _, TIMER_REPEAT);
	CreateTimer(0.05, Timer_Spin, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	g_iBeam = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	
	PrecacheModel(HOST_MODEL, true);
	PrecacheSound(HOST_HELLO, true);
	
	for (int i = 0; i < sizeof(g_sStructureModels); i++)
	{
		PrecacheModel(g_sStructureModels[i], true);
	}
	
	g_iGlowSprite = PrecacheModel("sprites/glow01.vmt", true);
	PrecacheModel("sprites/light_glow02_add.vmt", true);
	PrecacheSound("ambient/energy/zap5.wav", true);
	PrecacheSound("ambient/energy/zap6.wav", true);
	
	g_iHostRef = INVALID_ENT_REFERENCE;
	
	if (g_alStructure == null)
	{
		g_alStructure = new ArrayList();
	}
	
	g_alStructure.Clear();
	
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_bGreeted[i] = false;
	}
	
	PrecacheSound("buttons/button9.wav", true);
	PrecacheSound("buttons/button8.wav", true);
	
	g_bBooth = false;
	g_bAuction = false;
	g_iAuctionRef = INVALID_ENT_REFERENCE;
	
	for (int i = 0; i < 3; i++)
	{
		g_iPropRef[i] = INVALID_ENT_REFERENCE;
	}
	
	g_smGuessed.Clear();
	g_smAnswer.Clear();
	
	//Placed before the Power Booth, which then keeps out of its sight.
	CreateTimer(3.0, Timer_PlaceBooth, _, TIMER_FLAG_NO_MAPCHANGE);
}

//The Guess Booth goes where an admin saved it for this map. Without a saved spot the map has no Guess Booth.
public Action Timer_PlaceBooth(Handle hTimer)
{
	float fSpot[3];
	
	if (GetSavedSpot(fSpot))
	{
		PlaceBooth(fSpot);
	} else {
		LogMessage("|CelMod| This map has no Guess Booth spot. An admin can stand where it should go and type !setguessbooth.");
	}
	
	return Plugin_Stop;
}

//Each map's spot is its own file in data/celmod/guessbooth/, which the release never ships, so updating CelMod
//never wipes the spots. The older single file (data/celmod/guessbooth.txt) is still read as a fallback.
void SpotFile(char[] sPath, int iMaxLength)
{
	char sMap[PLATFORM_MAX_PATH], sDir[PLATFORM_MAX_PATH];
	
	GetCurrentMap(sMap, sizeof(sMap));
	
	//Workshop maps have slashes in their names.
	ReplaceString(sMap, sizeof(sMap), "/", "_");
	ReplaceString(sMap, sizeof(sMap), "\\", "_");
	
	BuildPath(Path_SM, sDir, sizeof(sDir), "data/celmod/guessbooth");
	
	if (!DirExists(sDir))
	{
		CreateDirectory(sDir, 511);
	}
	
	BuildPath(Path_SM, sPath, iMaxLength, "data/celmod/guessbooth/%s.txt", sMap);
}

bool GetSavedSpot(float fSpot[3])
{
	char sMap[PLATFORM_MAX_PATH], sPath[PLATFORM_MAX_PATH];
	bool bFound = false;
	
	SpotFile(sPath, sizeof(sPath));
	
	//Spots saved before the booth could face a way face north, like they always did.
	g_fBoothYaw = 90.0;
	
	KeyValues kvSpot = new KeyValues("GuessBooth");
	
	if (FileExists(sPath) && kvSpot.ImportFromFile(sPath))
	{
		kvSpot.GetVector("origin", fSpot);
		g_fBoothYaw = kvSpot.GetFloat("yaw", 90.0);
		
		bFound = true;
	}
	
	delete kvSpot;
	
	if (bFound)
	{
		return true;
	}
	
	//The older single file, if the server still has one.
	GetCurrentMap(sMap, sizeof(sMap));
	
	KeyValues kvSpots = new KeyValues("GuessBooth");
	
	if (FileExists(g_sBoothDB) && kvSpots.ImportFromFile(g_sBoothDB) && kvSpots.JumpToKey(sMap, false))
	{
		kvSpots.GetVector("origin", fSpot);
		
		bFound = true;
	}
	
	delete kvSpots;
	
	return bFound;
}

//Returns false (and says why in the server log) when the spot could not be written.
bool SetSavedSpot(const float fSpot[3], bool bRemove)
{
	char sMap[PLATFORM_MAX_PATH], sPath[PLATFORM_MAX_PATH];
	
	SpotFile(sPath, sizeof(sPath));
	
	if (bRemove)
	{
		if (FileExists(sPath))
		{
			DeleteFile(sPath);
		}
		
		//Also out of the older single file, so it does not come back from there.
		GetCurrentMap(sMap, sizeof(sMap));
		
		KeyValues kvSpots = new KeyValues("GuessBooth");
		
		if (FileExists(g_sBoothDB) && kvSpots.ImportFromFile(g_sBoothDB) && kvSpots.JumpToKey(sMap, false))
		{
			kvSpots.DeleteThis();
			kvSpots.Rewind();
			kvSpots.ExportToFile(g_sBoothDB);
		}
		
		delete kvSpots;
		
		return true;
	}
	
	KeyValues kvSpot = new KeyValues("GuessBooth");
	
	kvSpot.SetVector("origin", fSpot);
	kvSpot.SetFloat("yaw", g_fBoothYaw);
	
	bool bSaved = kvSpot.ExportToFile(sPath);
	
	delete kvSpot;
	
	//Read back, to be sure it really is on disk.
	float fCheck[3];
	
	if (!bSaved || !GetSavedSpot(fCheck) || GetVectorDistance(fCheck, fSpot) > 1.0)
	{
		LogError("|CelMod| Could not save the Guess Booth spot to %s. Check that the server can write to that folder.", sPath);
		return false;
	}
	
	return true;
}

void RemoveBooth()
{
	for (int i = 0; i < 3; i++)
	{
		RemoveRef(g_iPropRef[i]);
	}
	
	RemoveRef(g_iHostRef);
	RemoveStructure();
	
	g_bBooth = false;
}

public Action Command_SetGuessBooth(int iClient, int iArgs)
{
	char sMap[PLATFORM_MAX_PATH];
	float fOrigin[3];
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	GetClientAbsOrigin(iClient, fOrigin);
	GetCurrentMap(sMap, sizeof(sMap));
	
	//The booth faces the way the admin is facing.
	float fEyes[3];
	
	GetClientEyeAngles(iClient, fEyes);
	
	//No player's land may overlap the booth.
	float fOldYaw = g_fBoothYaw;
	
	g_fBoothYaw = fEyes[1];
	
	int iBlocker = LandInBoothArea(fOrigin);
	
	if (iBlocker > 0)
	{
		g_fBoothYaw = fOldYaw;
		
		Cel_ReplyToCommand(iClient, "The Guess Booth can't go here: it would overlap {green}%N{default}'s land.", iBlocker);
		return Plugin_Handled;
	}
	
	MoveBooth(fOrigin);
	
	if (!SetSavedSpot(fOrigin, false))
	{
		Cel_ReplyToCommand(iClient, "The Guess Booth was moved here, but the spot {green}could not be saved{default}: the server could not write to {green}data/celmod/guessbooth/{default}. See the error log.");
		return Plugin_Handled;
	}
	
	Cel_ReplyToCommand(iClient, "The Guess Booth on {green}%s{default} will now always be here.", sMap);
	
	return Plugin_Handled;
}

public Action Command_DelGuessBooth(int iClient, int iArgs)
{
	char sMap[PLATFORM_MAX_PATH];
	float fNone[3];
	
	GetCurrentMap(sMap, sizeof(sMap));
	
	SetSavedSpot(fNone, true);
	
	if (g_bAuction)
	{
		//The auction hangs above the booth, so it is called off (nobody has paid anything yet).
		Cel_PrintToChatAll("The auction for the {green}%s{default} is off: the Guess Booth was removed.", g_sAuctionName);
		ClearAuction();
	}
	
	RemoveBooth();
	
	Cel_ReplyToCommand(iClient, "{green}%s{default} no longer has a Guess Booth.", sMap);
	
	return Plugin_Handled;
}

int SpawnDisplay(const char[] sModel, float fCenter[3], bool bCheckSize = false, bool bHologram = false)
{
	float fMaxs[3], fMins[3], fOrigin[3];
	
	PrecacheModel(sModel);
	
	//A display only turns in place, so it has no physics at all: it is made not solid before it spawns, instead of
	//changing a physics prop's solidity and collision group afterwards behind the physics engine's back (a crash risk).
	int iEntity = CreateEntityByName("prop_dynamic_override");
	
	if (iEntity == -1)
	{
		return -1;
	}
	
	DispatchKeyValue(iEntity, "model", sModel);
	DispatchKeyValue(iEntity, "solid", "0");
	
	if (!DispatchSpawn(iEntity) || !IsValidEntity(iEntity))
	{
		return -1;
	}
	
	// Named after spawning: renamed before, a prop_physics_override loses its override.
	DispatchKeyValue(iEntity, "classname", "cel_boothdisplay");
	
	//The Guess Booth's props are holograms: see-through, tinted cyan, flickering like a projection.
	if (bHologram)
	{
		SetEntityRenderMode(iEntity, RENDER_TRANSCOLOR);
		SetEntityRenderColor(iEntity, 90, 210, 255, 150);
		SetEntityRenderFx(iEntity, RENDERFX_HOLOGRAM);
	}
	
	SetEntProp(iEntity, Prop_Data, "m_takedamage", 0, 1);
	
	GetEntPropVector(iEntity, Prop_Send, "m_vecMins", fMins);
	GetEntPropVector(iEntity, Prop_Send, "m_vecMaxs", fMaxs);
	
	if (bCheckSize)
	{
		float fLongest = 0.0;
		
		for (int i = 0; i < 3; i++)
		{
			if (fMaxs[i] - fMins[i] > fLongest)
			{
				fLongest = fMaxs[i] - fMins[i];
			}
		}
		
		//Only too big is refused: a size of 0 means the size is unknown, and the prop is shown anyway.
		if (fLongest > 96.0)
		{
			AcceptEntityInput(iEntity, "kill");
			
			return -1;
		}
	}
	
	//Holograms all show at about the same size: small props grow, big ones shrink.
	if (bHologram)
	{
		float fLongest = 0.0;
		
		for (int i = 0; i < 3; i++)
		{
			if (fMaxs[i] - fMins[i] > fLongest)
			{
				fLongest = fMaxs[i] - fMins[i];
			}
		}
		
		if (fLongest > 1.0)
		{
			float fScale = DISPLAY_SIZE / fLongest;
			
			if (fScale < 0.4) fScale = 0.4;
			if (fScale > 2.5) fScale = 2.5;
			
			SetEntPropFloat(iEntity, Prop_Send, "m_flModelScale", fScale);
			
			ScaleVector(fMins, fScale);
			ScaleVector(fMaxs, fScale);
		}
	}
	
	for (int i = 0; i < 3; i++)
	{
		fOrigin[i] = fCenter[i] - (fMins[i] + fMaxs[i]) * 0.5;
	}
	
	TeleportEntity(iEntity, fOrigin, NULL_VECTOR, NULL_VECTOR);
	
	//Kept so the prop can turn around its own middle.
	if (iEntity <= MAXENTITIES)
	{
		g_fSpinCenter[iEntity] = fCenter;
		
		for (int i = 0; i < 3; i++)
		{
			g_fSpinOffset[iEntity][i] = (fMins[i] + fMaxs[i]) * 0.5;
		}
	}
	
	return iEntity;
}

void RemoveRef(int &iRef)
{
	int iEntity = EntRefToEntIndex(iRef);
	
	if (iRef != INVALID_ENT_REFERENCE && iEntity != INVALID_ENT_REFERENCE && iEntity > MaxClients)
	{
		AcceptEntityInput(iEntity, "kill");
	}
	
	iRef = INVALID_ENT_REFERENCE;
}

//A point in the booth: forward (toward Dr. Breen), right and up from the centre, turned to the booth's facing.
void BoothPoint(const float fCenter[3], float fForward, float fRight, float fUp, float fOut[3])
{
	float fYaw = DegToRad(g_fBoothYaw);
	
	fOut[0] = fCenter[0] + Cosine(fYaw) * fForward + Sine(fYaw) * fRight;
	fOut[1] = fCenter[1] + Sine(fYaw) * fForward - Cosine(fYaw) * fRight;
	fOut[2] = fCenter[2] + fUp;
}

void PlaceBooth(float fOrigin[3])
{
	char sAlias[64], sBuffer[2][PLATFORM_MAX_PATH], sValue[PLATFORM_MAX_PATH];
	float fPos[3];
	
	ArrayList alAliases = new ArrayList(ByteCountToCells(64));
	ArrayList alModels = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	
	//Only ordinary props are used, no dolls.
	KeyValues kvProps = new KeyValues("Props");
	
	if (kvProps.ImportFromFile(g_sSpawnDB) && kvProps.JumpToKey("Models", false) && kvProps.GotoFirstSubKey(false))
	{
		do
		{
			kvProps.GetSectionName(sAlias, sizeof(sAlias));
			kvProps.GetString(NULL_STRING, sValue, sizeof(sValue), "");
			
			if (ExplodeString(sValue, "|", sBuffer, 2, sizeof(sBuffer[])) == 2 && StrEqual(sBuffer[0], "prop_physics_override"))
			{
				alAliases.PushString(sAlias);
				alModels.PushString(sBuffer[1]);
			}
		}
		while (kvProps.GotoNextKey(false));
	}
	
	delete kvProps;
	
	for (int i = 0; i < 3; i++)
	{
		RemoveRef(g_iPropRef[i]);
	}
	
	g_fCenter = fOrigin;
	g_bBooth = (alAliases.Length >= 3);
	
	BuildStructure(fOrigin);
	PlaceHost(fOrigin);
	
	if (g_bBooth)
	{
		int iShown = 0;
		
		//Random props until three can be shown: a prop the server does not have, or one too big or too small to
		//float in the booth, is skipped.
		while (iShown < 3 && alAliases.Length > 0)
		{
			int iPick = GetRandomInt(0, alAliases.Length - 1);
			
			alAliases.GetString(iPick, g_sPropAlias[iShown], sizeof(g_sPropAlias[]));
			alModels.GetString(iPick, sValue, sizeof(sValue));
			
			//Taken out of the list so the same prop is not tried twice.
			alAliases.Erase(iPick);
			alModels.Erase(iPick);
			
			//Left to right as seen from the front of the booth, each over its emitter.
			BoothPoint(fOrigin, 0.0, (iShown - 1) * HOLO_SPACING, HOLO_HEIGHT, fPos);
			
			int iEntity = SpawnDisplay(sValue, fPos, true, true);
			
			if (iEntity == -1)
			{
				continue;
			}
			
			g_iPropRef[iShown] = EntIndexToEntRef(iEntity);
			
			iShown++;
		}
		
		g_bBooth = (iShown == 3);
		
		if (g_bBooth)
		{
			PrintToServer("|CelMod| Guess Booth props: %s, %s, %s.", g_sPropAlias[0], g_sPropAlias[1], g_sPropAlias[2]);
		} else {
			LogError("|CelMod| The Guess Booth could only show %d of its three props. Check that the models in '%s' are on the server.", iShown, g_sSpawnDB);
		}
		
		//New props: everyone gets a new winning prop of their own the next time they guess.
		g_smAnswer.Clear();
	} else {
		LogError("|CelMod| The Guess Booth needs at least three props in '%s'.", g_sSpawnDB);
	}
	
	delete alAliases;
	delete alModels;
}

//Dr. Breen stands at the back of the booth behind his console, facing whoever walks up.
void PlaceHost(float fCenter[3])
{
	float fAngles[3], fPos[3];
	
	RemoveRef(g_iHostRef);
	
	int iHost = CreateEntityByName("prop_dynamic_override");
	
	if (iHost == -1)
	{
		return;
	}
	
	BoothPoint(fCenter, g_fHostForward, 0.0, 0.0, fPos);
	
	//Facing into the booth, back toward whoever walks up.
	fAngles[1] = g_fBoothYaw + 180.0;
	
	DispatchKeyValue(iHost, "model", HOST_MODEL);
	DispatchKeyValue(iHost, "solid", "2");
	
	DispatchSpawn(iHost);
	// Named after spawning: a prop_dynamic_override renamed before it spawns loses its override.
	DispatchKeyValue(iHost, "classname", "cel_booth_host");
	
	TeleportEntity(iHost, fPos, fAngles, NULL_VECTOR);
	
	//Standing idle (the model's own idle animation, found in its files).
	char sIdle[64];
	
	if (FindIdleSequence(HOST_MODEL, sIdle, sizeof(sIdle)))
	{
		PrintToServer("|CelMod| Guess Booth: Dr. Breen stands with the '%s' animation.", sIdle);
		
		SetVariantString(sIdle);
		AcceptEntityInput(iHost, "SetDefaultAnimation");
		
		SetVariantString(sIdle);
		AcceptEntityInput(iHost, "SetAnimation");
	}
	
	g_iHostRef = EntIndexToEntRef(iHost);
}

//The booth's Combine frame: each piece is sat on the floor and turned by its own size (its long side along the edge
//it stands on), so nothing depends on how a model happens to be built.
void BuildStructure(float fCenter[3])
{
	RemoveStructure();
	
	float fPos[3];
	
	//Dr. Breen's monitor wall across the back, inside the booth (its back against the far edge).
	float fFront = AddPieceFlush("models/props_combine/combine_monitorbay.mdl", fCenter, BOOTH_HALF, 0.0, g_fBoothYaw + 180.0, true, true);
	
	//Breen stands just in front of it, with his console in front of him, facing the players.
	g_fHostForward = fFront - 26.0;
	
	float fConsole = AddPieceFlush("models/props_combine/breenconsole.mdl", fCenter, g_fHostForward - 22.0, 0.0, g_fBoothYaw + 180.0, false, true);
	
	//His globe beside the console.
	BoothPoint(fCenter, (g_fHostForward + fConsole) * 0.5, BOOTH_HALF - 52.0, 0.0, fPos);
	AddPiece("models/props_combine/breenglobe.mdl", fPos, g_fBoothYaw + 200.0, false, true);
	
	//A post at each corner, with a Combine-blue light on top.
	for (int iCorner = 0; iCorner < 4; iCorner++)
	{
		float fForward = (iCorner < 2) ? BOOTH_HALF : -BOOTH_HALF;
		float fRight = (iCorner % 2 == 0) ? -BOOTH_HALF : BOOTH_HALF;
		
		BoothPoint(fCenter, fForward, fRight, 0.0, fPos);
		
		int iPost = AddPiece((iCorner % 2 == 0) ? "models/props_combine/combine_fence01a.mdl" : "models/props_combine/combine_fence01b.mdl", fPos, g_fBoothYaw + 90.0, false, true);
		
		float fTop = 128.0;
		
		if (iPost != -1)
		{
			float fMaxs[3], fMins[3];
			
			GetEntPropVector(iPost, Prop_Send, "m_vecMaxs", fMaxs);
			GetEntPropVector(iPost, Prop_Send, "m_vecMins", fMins);
			
			if (fMaxs[2] - fMins[2] > 8.0)
			{
				fTop = fMaxs[2] - fMins[2];
			}
		}
		
		g_fPostTop[iCorner] = fPos;
		g_fPostTop[iCorner][2] += fTop + 4.0;
		
		AddGlow(g_fPostTop[iCorner], 0.55);
	}
	
	//Railings along the two sides; the front stays open.
	for (int iSide = -1; iSide <= 1; iSide += 2)
	{
		BoothPoint(fCenter, 0.0, iSide * (BOOTH_HALF + 4.0), 0.0, fPos);
		AddPiece("models/props_combine/railing_256.mdl", fPos, g_fBoothYaw, true, true);
	}
	
	//An emitter on the floor under each hologram, projecting it.
	for (int i = 0; i < 3; i++)
	{
		BoothPoint(fCenter, 0.0, (i - 1) * HOLO_SPACING, 0.0, fPos);
		AddPiece("models/props_combine/combine_emitter01.mdl", fPos, g_fBoothYaw + 180.0, false, false);
	}
	
	//Spotlights from the back posts onto the holograms.
	float fTarget[3];
	
	BoothPoint(fCenter, 0.0, 0.0, HOLO_HEIGHT, fTarget);
	
	for (int iCorner = 0; iCorner < 2; iCorner++)
	{
		AddSpotlight(g_fPostTop[iCorner], fTarget);
	}
	
	//A slow-pulsing blue light over the booth.
	BoothPoint(fCenter, 0.0, 0.0, 150.0, fPos);
	AddLight(fPos);
}

//A piece with its back against a line across the booth (fBack, measured forward from the middle), centred at fRight.
//Returns how far forward its front reaches, to line the next piece up in front of it.
float AddPieceFlush(const char[] sModel, float fCenter[3], float fBack, float fRight, float fYaw, bool bAlong, bool bSolid)
{
	float fPos[3];
	
	BoothPoint(fCenter, fBack, fRight, 0.0, fPos);
	
	int iPiece = AddPiece(sModel, fPos, fYaw, bAlong, bSolid);
	
	if (iPiece == -1)
	{
		return fBack - 16.0;
	}
	
	//Its depth along the booth: measured from its size and the way it's turned.
	float fMins[3], fMaxs[3], fAngles[3];
	
	GetEntPropVector(iPiece, Prop_Send, "m_vecMins", fMins);
	GetEntPropVector(iPiece, Prop_Send, "m_vecMaxs", fMaxs);
	GetEntPropVector(iPiece, Prop_Data, "m_angAbsRotation", fAngles);
	
	float fTurn = DegToRad(fAngles[1] - g_fBoothYaw);
	float fHalfDepth = (FloatAbs(Cosine(fTurn)) * (fMaxs[0] - fMins[0]) + FloatAbs(Sine(fTurn)) * (fMaxs[1] - fMins[1])) * 0.5;
	
	//Pulled in so its back sits on the line instead of its middle.
	float fOrigin[3], fShift[3];
	
	GetEntPropVector(iPiece, Prop_Data, "m_vecAbsOrigin", fOrigin);
	BoothPoint(view_as<float>({ 0.0, 0.0, 0.0 }), -fHalfDepth, 0.0, 0.0, fShift);
	AddVectors(fOrigin, fShift, fOrigin);
	
	TeleportEntity(iPiece, fOrigin, NULL_VECTOR, NULL_VECTOR);
	
	return fBack - fHalfDepth * 2.0;
}

//A Combine-blue glow (a light seen from anywhere around it).
void AddGlow(const float fPos[3], float fScale)
{
	int iGlow = CreateEntityByName("env_sprite");
	
	if (iGlow == -1)
	{
		return;
	}
	
	DispatchKeyValue(iGlow, "model", "sprites/light_glow02_add.vmt");
	DispatchKeyValue(iGlow, "rendermode", "9");
	DispatchKeyValue(iGlow, "rendercolor", "40 150 255");
	DispatchKeyValue(iGlow, "renderamt", "230");
	DispatchKeyValueFloat(iGlow, "scale", fScale);
	DispatchKeyValue(iGlow, "spawnflags", "1");
	DispatchKeyValue(iGlow, "GlowProxySize", "4");
	
	TeleportEntity(iGlow, fPos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(iGlow);
	AcceptEntityInput(iGlow, "ShowSprite");
	
	g_alStructure.Push(EntIndexToEntRef(iGlow));
}

//A visible beam of light from fFrom onto fTo.
void AddSpotlight(const float fFrom[3], const float fTo[3])
{
	int iSpot = CreateEntityByName("point_spotlight");
	
	if (iSpot == -1)
	{
		return;
	}
	
	float fDir[3], fAngles[3];
	
	SubtractVectors(fTo, fFrom, fDir);
	GetVectorAngles(fDir, fAngles);
	
	char sLength[16];
	
	FormatEx(sLength, sizeof(sLength), "%.0f", GetVectorLength(fDir) + 24.0);
	
	DispatchKeyValue(iSpot, "spotlightlength", sLength);
	DispatchKeyValue(iSpot, "spotlightwidth", "28");
	DispatchKeyValue(iSpot, "rendercolor", "40 150 255");
	DispatchKeyValue(iSpot, "renderamt", "160");
	DispatchKeyValue(iSpot, "spawnflags", "3"); // on from the start, no dynamic light
	
	TeleportEntity(iSpot, fFrom, fAngles, NULL_VECTOR);
	DispatchSpawn(iSpot);
	AcceptEntityInput(iSpot, "LightOn");
	
	g_alStructure.Push(EntIndexToEntRef(iSpot));
}

//A blue light over the booth that slowly pulses (light style 11), lighting the booth and whoever stands in it.
void AddLight(const float fPos[3])
{
	int iLight = CreateEntityByName("light_dynamic");
	
	if (iLight == -1)
	{
		return;
	}
	
	DispatchKeyValue(iLight, "_light", "40 140 255 255");
	DispatchKeyValue(iLight, "brightness", "4");
	DispatchKeyValue(iLight, "distance", "380");
	DispatchKeyValue(iLight, "style", "11");
	
	TeleportEntity(iLight, fPos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(iLight);
	AcceptEntityInput(iLight, "TurnOn");
	
	g_alStructure.Push(EntIndexToEntRef(iLight));
}

//One piece of the frame, its bottom on the floor at fPos. bAlong: its long side runs along fYaw.
int AddPiece(const char[] sModel, const float fPos[3], float fYaw, bool bAlong, bool bSolid)
{
	if (g_alStructure == null)
	{
		g_alStructure = new ArrayList();
	}
	
	int iPiece = CreateEntityByName("prop_dynamic_override");
	
	if (iPiece == -1)
	{
		return -1;
	}
	
	DispatchKeyValue(iPiece, "model", sModel);
	DispatchKeyValue(iPiece, "solid", bSolid ? "6" : "0");
	DispatchKeyValue(iPiece, "disableshadows", "1");
	
	if (!DispatchSpawn(iPiece))
	{
		return -1;
	}
	
	DispatchKeyValue(iPiece, "classname", "cel_booth_frame");
	
	SetEntProp(iPiece, Prop_Data, "m_takedamage", 0, 1);
	
	float fMins[3], fMaxs[3], fAngles[3], fOrigin[3];
	
	GetEntPropVector(iPiece, Prop_Send, "m_vecMins", fMins);
	GetEntPropVector(iPiece, Prop_Send, "m_vecMaxs", fMaxs);
	
	fAngles[1] = fYaw;
	
	//A model that is longer along its own Y than its X is turned a quarter, so its long side follows fYaw.
	if (bAlong && (fMaxs[1] - fMins[1]) > (fMaxs[0] - fMins[0]))
	{
		fAngles[1] += 90.0;
	}
	
	//Centred over fPos and standing on the floor, wherever the model's own origin is.
	float fMidX = (fMins[0] + fMaxs[0]) * 0.5, fMidY = (fMins[1] + fMaxs[1]) * 0.5;
	float fCos = Cosine(DegToRad(fAngles[1])), fSin = Sine(DegToRad(fAngles[1]));
	
	fOrigin[0] = fPos[0] - (fMidX * fCos - fMidY * fSin);
	fOrigin[1] = fPos[1] - (fMidX * fSin + fMidY * fCos);
	fOrigin[2] = fPos[2] - fMins[2];
	
	TeleportEntity(iPiece, fOrigin, fAngles, NULL_VECTOR);
	
	g_alStructure.Push(EntIndexToEntRef(iPiece));
	
	return iPiece;
}

void RemoveStructure()
{
	if (g_alStructure == null)
	{
		return;
	}
	
	for (int i = 0; i < g_alStructure.Length; i++)
	{
		int iRef = g_alStructure.Get(i);
		
		RemoveRef(iRef);
	}
	
	g_alStructure.Clear();
}

//Looks through a model's animations (its own, and the ones in the models it includes) for an idle one, so the
//name never has to be guessed. Prefers a plain "idle".
bool FindIdleSequence(const char[] sModel, char[] sIdle, int iMaxLength)
{
	static const char sPreferred[][] = { "idle", "idle01", "idle_subtle", "lineidle01", "idle_angry" };
	char sBest[64];
	int iBestRank = 999;
	
	ScanSequences(sModel, sPreferred, sizeof(sPreferred), sBest, sizeof(sBest), iBestRank, 0);
	
	if (sBest[0] == '\0')
	{
		return false;
	}
	
	strcopy(sIdle, iMaxLength, sBest);
	return true;
}

void ScanSequences(const char[] sModel, const char[][] sPreferred, int iPreferred, char[] sBest, int iBestLength, int &iBestRank, int iDepth)
{
	File fModel = OpenFile(sModel, "rb", true);
	
	if (fModel == null)
	{
		return;
	}
	
	int iSeqCount = ReadIntAt(fModel, 188), iSeqIndex = ReadIntAt(fModel, 192);
	int iIncludeCount = ReadIntAt(fModel, 336), iIncludeIndex = ReadIntAt(fModel, 340);
	char sLabel[64];
	
	//Each sequence description is 212 bytes: its name and its activity's name at offsets (stored 4 and 8 bytes in)
	//from its own start, then its flags (12 bytes in).
	char sActivity[64];
	
	for (int i = 0; i < iSeqCount && i < 2048; i++)
	{
		int iDesc = iSeqIndex + i * 212;
		int iLabel = ReadIntAt(fModel, iDesc + 4);
		int iActivity = ReadIntAt(fModel, iDesc + 8);
		int iFlags = ReadIntAt(fModel, iDesc + 12);
		
		if (!ReadStringAt(fModel, iDesc + iLabel, sLabel, sizeof(sLabel)))
		{
			continue;
		}
		
		//Gestures and postures (delta animations) are only layered on top of another animation: played on their
		//own they leave the model in its arms-out reference pose.
		if (iFlags & 0x0004)
		{
			continue;
		}
		
		if (iActivity <= 0 || !ReadStringAt(fModel, iDesc + iActivity, sActivity, sizeof(sActivity)))
		{
			sActivity[0] = '\0';
		}
		
		int iRank = 999;
		
		//What the game itself plays for standing around: ACT_IDLE, looping best.
		if (StrEqual(sActivity, "ACT_IDLE", false))
		{
			iRank = (iFlags & 0x0001) ? -2 : -1;
		}
		
		for (int k = 0; k < iPreferred && iRank == 999; k++)
		{
			if (StrEqual(sLabel, sPreferred[k], false))
			{
				iRank = k;
				break;
			}
		}
		
		//Any other idle that isn't a transition into or out of something.
		if (iRank == 999 && StrContains(sLabel, "idle", false) != -1 && StrContains(sLabel, "_to_", false) == -1 && StrContains(sLabel, "to_idle", false) == -1)
		{
			iRank = 100;
		}
		
		if (iRank < iBestRank)
		{
			iBestRank = iRank;
			strcopy(sBest, iBestLength, sLabel);
		}
	}
	
	//Models that include others: each include is two offsets (label, file name) from its own start.
	char sInclude[PLATFORM_MAX_PATH];
	
	for (int i = 0; i < iIncludeCount && i < 16 && iDepth < 2; i++)
	{
		int iGroup = iIncludeIndex + i * 8;
		int iName = ReadIntAt(fModel, iGroup + 4);
		
		if (ReadStringAt(fModel, iGroup + iName, sInclude, sizeof(sInclude)) && sInclude[0] != '\0')
		{
			if (StrContains(sInclude, "models/", false) != 0 && StrContains(sInclude, "models\\", false) != 0)
			{
				Format(sInclude, sizeof(sInclude), "models/%s", sInclude);
			}
			
			ScanSequences(sInclude, sPreferred, iPreferred, sBest, iBestLength, iBestRank, iDepth + 1);
		}
	}
	
	delete fModel;
}

int ReadIntAt(File fFile, int iOffset)
{
	int iValue;
	
	if (iOffset < 0 || !fFile.Seek(iOffset, SEEK_SET) || !fFile.ReadInt32(iValue))
	{
		return 0;
	}
	
	return iValue;
}

bool ReadStringAt(File fFile, int iOffset, char[] sBuffer, int iMaxLength)
{
	sBuffer[0] = '\0';
	
	if (iOffset <= 0 || !fFile.Seek(iOffset, SEEK_SET))
	{
		return false;
	}
	
	return fFile.ReadString(sBuffer, iMaxLength) > 0;
}

public void OnClientPutInServer(int iClient)
{
	g_bGreeted[iClient] = false;
}

public int Native_GetGuessBoothArea(Handle hPlugin, int iNumParams)
{
	if (!g_bBooth)
	{
		return false;
	}
	
	SetNativeArray(1, g_fCenter, 3);
	SetNativeCellRef(2, g_fBoothYaw);
	SetNativeCellRef(3, BOOTH_HALF);
	
	return true;
}

//The first player whose land would overlap the booth if it stood at fOrigin (facing g_fBoothYaw), or 0.
int LandInBoothArea(const float fOrigin[3])
{
	float fA[3], fB[3];
	bool bWas = g_bBooth;
	float fWas[3];
	
	fWas = g_fCenter;
	g_fCenter = fOrigin;
	g_bBooth = true;
	
	int iFound = 0;
	
	for (int i = 1; i <= MaxClients && iFound == 0; i++)
	{
		if (IsClientInGame(i) && Cel_IsLandCreated(i))
		{
			Cel_GetLandPositions(i, 2, fA);
			Cel_GetLandPositions(i, 3, fB);
			
			if (Cel_LandHitsGuessBooth(fA, fB))
			{
				iFound = i;
			}
		}
	}
	
	g_fCenter = fWas;
	g_bBooth = bWas;
	
	return iFound;
}

bool IsInBooth(int iClient)
{
	float fOrigin[3];
	
	GetClientAbsOrigin(iClient, fOrigin);
	
	//Measured along the booth's own sides, as it can face any way.
	float fYaw = DegToRad(g_fBoothYaw), fDX = fOrigin[0] - g_fCenter[0], fDY = fOrigin[1] - g_fCenter[1];
	float fForward = fDX * Cosine(fYaw) + fDY * Sine(fYaw), fRight = fDX * Sine(fYaw) - fDY * Cosine(fYaw);
	
	return (g_bBooth && FloatAbs(fForward) <= BOOTH_HALF && FloatAbs(fRight) <= BOOTH_HALF && FloatAbs(fOrigin[2] - g_fCenter[2]) <= 160.0);
}

//Turns the booth's props and the auction item slowly around their middles, a full turn about every 15 seconds.
public Action Timer_Spin(Handle hTimer)
{
	float fAngles[3], fOrigin[3];
	
	g_fSpinYaw += 1.2;
	
	if (g_fSpinYaw >= 360.0)
	{
		g_fSpinYaw -= 360.0;
	}
	
	float fCos = Cosine(DegToRad(g_fSpinYaw)), fSin = Sine(DegToRad(g_fSpinYaw));
	
	fAngles[1] = g_fSpinYaw;
	
	for (int i = 0; i < 4; i++)
	{
		int iEntity = EntRefToEntIndex(i < 3 ? g_iPropRef[i] : g_iAuctionRef);
		
		if (iEntity == INVALID_ENT_REFERENCE || iEntity <= MaxClients || iEntity > MAXENTITIES)
		{
			continue;
		}
		
		//The origin swings around the middle as the prop turns, so the middle stays put.
		float fX = g_fSpinOffset[iEntity][0], fY = g_fSpinOffset[iEntity][1];
		
		fOrigin[0] = g_fSpinCenter[iEntity][0] - (fX * fCos - fY * fSin);
		fOrigin[1] = g_fSpinCenter[iEntity][1] - (fX * fSin + fY * fCos);
		fOrigin[2] = g_fSpinCenter[iEntity][2] - g_fSpinOffset[iEntity][2];
		
		//The holograms bob gently as they turn, each a little out of step.
		if (i < 3)
		{
			fOrigin[2] += Sine(GetGameTime() * 1.8 + float(i) * 2.1) * 4.0;
		}
		
		TeleportEntity(iEntity, fOrigin, fAngles, NULL_VECTOR);
	}
	
	return Plugin_Continue;
}

//Draws the booth's Combine-blue square, tells players near the booth what it is, and ends the auction on time.
public Action Timer_Booth(Handle hTimer)
{
	char sText[192];
	float fA[3], fB[3], fOrigin[3];
	int iBlue[4] = { 40, 150, 255, 255 };
	
	if (!g_bBooth || g_iBeam < 1)
	{
		return Plugin_Continue;
	}
	
	for (int iEdge = 0; iEdge < 4; iEdge++)
	{
		int iNext = (iEdge + 1) % 4;
		
		BoothPoint(g_fCenter, (iEdge >= 2) ? BOOTH_HALF : -BOOTH_HALF, (iEdge == 1 || iEdge == 2) ? BOOTH_HALF : -BOOTH_HALF, 4.0, fA);
		BoothPoint(g_fCenter, (iNext >= 2) ? BOOTH_HALF : -BOOTH_HALF, (iNext == 1 || iNext == 2) ? BOOTH_HALF : -BOOTH_HALF, 4.0, fB);
		
		TE_SetupBeamPoints(fA, fB, g_iBeam, 0, 0, 0, 1.05, 3.0, 3.0, 0, 0.0, iBlue, 0);
		TE_SendToAll();
	}
	
	//Each hologram is projected from the floor: a faint cyan beam widening up to the prop.
	int iHolo[4] = { 90, 210, 255, 70 };
	
	for (int i = 0; i < 3; i++)
	{
		int iProp = EntRefToEntIndex(g_iPropRef[i]);
		
		if (iProp == INVALID_ENT_REFERENCE)
		{
			continue;
		}
		
		float fBase[3], fTop[3];
		
		BoothPoint(g_fCenter, 0.0, (i - 1) * HOLO_SPACING, 10.0, fBase);
		GetEntPropVector(iProp, Prop_Data, "m_vecAbsOrigin", fTop);
		
		TE_SetupBeamPoints(fBase, fTop, g_iBeam, 0, 0, 0, 1.05, 2.0, 24.0, 0, 0.0, iHolo, 0);
		TE_SendToAll();
		
		//A glowing ring under each hologram, over its emitter.
		TE_SetupBeamRingPoint(fBase, 44.0, 52.0, g_iBeam, 0, 0, 0, 1.05, 3.0, 0.0, { 60, 170, 255, 170 }, 0, 0);
		TE_SendToAll();
	}
	
	g_iBoothTick++;
	
	//A pulse rippling out across the floor.
	if (g_iBoothTick % 2 == 0)
	{
		float fFloor[3];
		
		BoothPoint(g_fCenter, 0.0, 0.0, 3.0, fFloor);
		
		TE_SetupBeamRingPoint(fFloor, 30.0, BOOTH_HALF * 2.0, g_iBeam, 0, 0, 0, 1.6, 5.0, 0.0, { 40, 150, 255, 130 }, 0, 0);
		TE_SendToAll();
	}
	
	//Blue lightning arcing between the front posts.
	if (g_iBoothTick % 3 == 0)
	{
		TE_SetupBeamPoints(g_fPostTop[2], g_fPostTop[3], g_iBeam, 0, 0, 0, 0.45, 3.0, 3.0, 0, 12.0, { 120, 200, 255, 255 }, 0);
		TE_SendToAll();
		
		TE_SetupBeamPoints(g_fPostTop[2], g_fPostTop[3], g_iBeam, 0, 0, 0, 0.3, 1.5, 1.5, 0, 6.0, { 220, 240, 255, 255 }, 0);
		TE_SendToAll(0.1);
		
		float fMid[3];
		
		for (int k = 0; k < 3; k++)
		{
			fMid[k] = (g_fPostTop[2][k] + g_fPostTop[3][k]) * 0.5;
		}
		
		EmitAmbientSound(GetRandomInt(0, 1) ? "ambient/energy/zap5.wav" : "ambient/energy/zap6.wav", fMid, SOUND_FROM_WORLD, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.35);
	}
	
	int iLeft = RoundToFloor(g_fAuctionEnd - GetGameTime());
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsPlayerAlive(i))
		{
			continue;
		}
		
		GetClientAbsOrigin(i, fOrigin);
		
		if (GetVectorDistance(fOrigin, g_fCenter) > 320.0)
		{
			continue;
		}
		
		//Dr. Breen greets everyone once a map, the first time they step into the booth.
		int iHost = EntRefToEntIndex(g_iHostRef);
		
		if (!g_bGreeted[i] && IsInBooth(i) && iHost != INVALID_ENT_REFERENCE)
		{
			g_bGreeted[i] = true;
			
			EmitSoundToClient(i, HOST_HELLO, iHost);
			
			Cel_PrintToChat(i, "{green}Dr. Breen:{default} Welcome. Welcome to the Guess Booth. One of these three props is your winner, and it's not the same for everyone. Pick it with {green}!guess 1{default}, {green}2{default} or {green}3{default}.");
		}
		
		if (g_bAuction)
		{
			if (g_iTopBidder > 0 && GetClientOfUserId(g_iTopBidder) > 0)
			{
				Format(sText, sizeof(sText), "Auction: %s (sold by %s)\nTop bid: %d CL by %N\n%d:%02d left  -  !bid <amount>", g_sAuctionName, g_sSellerName, g_iTopBid, GetClientOfUserId(g_iTopBidder), iLeft / 60, iLeft % 60);
			} else {
				Format(sText, sizeof(sText), "Auction: %s (sold by %s)\nStarting bid: %d CL\n%d:%02d left  -  !bid <amount>", g_sAuctionName, g_sSellerName, g_iTopBid, iLeft / 60, iLeft % 60);
			}
		} else {
			Format(sText, sizeof(sText), "Guess Booth\nOne of the three props is your winner.\nStand in the square and type !guess 1, 2 or 3");
		}
		
		//A quiet message at the top of the screen; hint text beeps every time it is shown.
		Cel_SendHudMessage(i, 4, -1.0, 0.12, 40, 150, 255, 255, 0, 0.0, 0.2, 1.1, 0.0, sText);
	}
	
	if (g_bAuction && iLeft <= 0)
	{
		EndAuction();
	}
	
	return Plugin_Continue;
}

public Action Command_GuessBooth(int iClient, int iArgs)
{
	float fOrigin[3];
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	GetClientAbsOrigin(iClient, fOrigin);
	
	float fEyes[3];
	
	GetClientEyeAngles(iClient, fEyes);
	g_fBoothYaw = fEyes[1];
	
	MoveBooth(fOrigin);
	
	Cel_ReplyToCommand(iClient, "The Guess Booth has been moved here for this map, with new props. Use {green}[tag]setguessbooth{default} to keep it here every time.");
	
	return Plugin_Handled;
}

void MoveBooth(float fOrigin[3])
{
	float fDisplay[3];
	
	PlaceBooth(fOrigin);
	
	//An auction display moves with the booth.
	int iDisplay = EntRefToEntIndex(g_iAuctionRef);
	
	if (g_bAuction && iDisplay != INVALID_ENT_REFERENCE && iDisplay <= MAXENTITIES)
	{
		fDisplay = fOrigin;
		fDisplay[2] += 130.0;
		
		//The spin keeps it turning around its new spot.
		g_fSpinCenter[iDisplay] = fDisplay;
	}
}

public Action Command_Guess(int iClient, int iArgs)
{
	char sAuthID[64], sGuess[64];
	int iGuess = -1, iUsed;
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	if (!g_bBooth)
	{
		Cel_ReplyToCommand(iClient, "There is no Guess Booth on this map right now.");
		return Plugin_Handled;
	}
	
	if (!IsInBooth(iClient))
	{
		Cel_ReplyToCommand(iClient, "Stand inside the blue square of the Guess Booth to guess.");
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]guess{default} <1/2/3 or the prop's name>. You get one guess per map.");
		return Plugin_Handled;
	}
	
	if (!GetClientAuthId(iClient, AuthId_SteamID64, sAuthID, sizeof(sAuthID), false))
	{
		Format(sAuthID, sizeof(sAuthID), "userid_%d", GetClientUserId(iClient));
	}
	
	if (g_smGuessed.GetValue(sAuthID, iUsed))
	{
		Cel_ReplyToCommand(iClient, "You have already used your guess on this map.");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sGuess, sizeof(sGuess));
	
	for (int i = 0; i < 3; i++)
	{
		if (StrEqual(sGuess, g_sPropAlias[i], false) || (strlen(sGuess) == 1 && sGuess[0] == '1' + i))
		{
			iGuess = i;
		}
	}
	
	if (iGuess == -1)
	{
		Cel_ReplyToCommand(iClient, "That is not one of the three props. Type {green}1{default}, {green}2{default} or {green}3{default} (left to right), or the prop's spawn name. This did not use your guess.");
		return Plugin_Handled;
	}
	
	g_smGuessed.SetValue(sAuthID, 1);
	
	//Every player has their own winning prop, so one player's answer is no help to anyone else.
	int iAnswer;
	
	if (!g_smAnswer.GetValue(sAuthID, iAnswer))
	{
		iAnswer = GetRandomInt(0, 2);
		g_smAnswer.SetValue(sAuthID, iAnswer);
	}
	
	if (iGuess == iAnswer)
	{
		Cel_AddToClientBalance(iClient, g_cvReward.IntValue);
		Cel_AddXP(iClient, g_cvXPGuess.IntValue);
		
		EmitSoundToClient(iClient, "buttons/button9.wav");
		
		//Which prop it was isn't said.
		Cel_PrintToChatAll("{green}%N{default} guessed right at the Guess Booth and won {green}%d CL{default}!", iClient, g_cvReward.IntValue);
	} else {
		EmitSoundToClient(iClient, "buttons/button8.wav");
		
		Cel_ReplyToCommand(iClient, "Wrong, that wasn't your winning prop. Better luck on the next map.");
	}
	
	return Plugin_Handled;
}

//Auctions:
bool IsAuctionAdmin(int iClient)
{
	return iClient > 0 && CheckCommandAccess(iClient, "celmod_auction_admin", ADMFLAG_SLAY, true);
}

//"weapon", "celwep" and the like all mean a celwep.
void NormaliseKind(char[] sKind, int iMaxLength)
{
	if (StrEqual(sKind, "celwep", false) || StrEqual(sKind, "celweps", false) || StrEqual(sKind, "weapons", false))
	{
		strcopy(sKind, iMaxLength, "weapon");
	} else if (StrEqual(sKind, "emblems", false))
	{
		strcopy(sKind, iMaxLength, "emblem");
	} else if (StrEqual(sKind, "hats", false))
	{
		strcopy(sKind, iMaxLength, "hat");
	}
}

void ClearAuction()
{
	g_bAuction = false;
	g_iTopBidder = 0;
	g_iBidCount = 0;
	g_iAuctionSeller = 0;
	
	RemoveRef(g_iAuctionRef);
}

public Action Command_Auction(int iClient, int iArgs)
{
	char sArg[4][64], sModel[PLATFORM_MAX_PATH];
	float fOrigin[3];
	int iColor[4], iSkin;
	
	if (iArgs >= 1)
	{
		GetCmdArg(1, sArg[0], sizeof(sArg[]));
	}
	
	if (StrEqual(sArg[0], "cancel", false))
	{
		if (!g_bAuction)
		{
			Cel_ReplyToCommand(iClient, "There is no auction running.");
			return Plugin_Handled;
		}
		
		//The seller can call their own auction off; admins can call off any.
		if (!IsAuctionAdmin(iClient) && (g_iAuctionSeller == 0 || GetClientOfUserId(g_iAuctionSeller) != iClient))
		{
			Cel_ReplyToCommand(iClient, "Only the seller (or an admin) can cancel this auction.");
			return Plugin_Handled;
		}
		
		Cel_PrintToChatAll("The auction for the {green}%s{default} has been cancelled. Nothing changed hands.", g_sAuctionName);
		ClearAuction();
		
		return Plugin_Handled;
	}
	
	if (iArgs < 3)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]auction{default} <emblem/hat/weapon> <name> <minutes> [starting bid], or {green}[tag]auction cancel{default}. You sell one of your own.");
		return Plugin_Handled;
	}
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	if (g_bAuction)
	{
		Cel_ReplyToCommand(iClient, "An auction is already running (the {green}%s{default}, sold by {green}%s{default}). Wait for it to end.", g_sAuctionName, g_sSellerName);
		return Plugin_Handled;
	}
	
	if (!g_bBooth)
	{
		Cel_ReplyToCommand(iClient, "Auctions are held above the Guess Booth, and this map doesn't have one.");
		return Plugin_Handled;
	}
	
	for (int i = 1; i < 4 && i < iArgs; i++)
	{
		GetCmdArg(i + 1, sArg[i], sizeof(sArg[]));
	}
	
	NormaliseKind(sArg[0], sizeof(sArg[]));
	
	if (!Cel_GetCollectibleLook(sArg[0], sArg[1], sModel, sizeof(sModel), g_sAuctionName, sizeof(g_sAuctionName), iSkin, iColor))
	{
		Cel_ReplyToCommand(iClient, "There is no %s called {green}%s{default}.", sArg[0], sArg[1]);
		return Plugin_Handled;
	}
	
	//A player sells their own copy. An admin who doesn't own one auctions one the server gives away.
	bool bOwn = Cel_GetCollectibleCount(iClient, sArg[0], sArg[1]) > 0;
	
	if (!bOwn && !IsAuctionAdmin(iClient))
	{
		Cel_ReplyToCommand(iClient, "You don't have a {green}%s{default} to sell. Check {green}[tag]bank{default}.", g_sAuctionName);
		return Plugin_Handled;
	}
	
	float fMinutes = StringToFloat(sArg[2]), fMax = IsAuctionAdmin(iClient) ? 60.0 : g_cvAuctionMinutes.FloatValue;
	
	if (fMinutes < 1.0)
	{
		fMinutes = 1.0;
	} else if (fMinutes > fMax)
	{
		fMinutes = fMax;
	}
	
	strcopy(g_sAuctionKind, sizeof(g_sAuctionKind), sArg[0]);
	strcopy(g_sAuctionId, sizeof(g_sAuctionId), sArg[1]);
	
	g_bAuction = true;
	g_fAuctionEnd = GetGameTime() + fMinutes * 60.0;
	g_iTopBid = StringToInt(sArg[3]);
	g_iTopBidder = 0;
	g_iBidCount = 0;
	g_iAuctionSeller = bOwn ? GetClientUserId(iClient) : 0;
	
	if (bOwn)
	{
		GetClientName(iClient, g_sSellerName, sizeof(g_sSellerName));
	} else {
		strcopy(g_sSellerName, sizeof(g_sSellerName), "the server");
	}
	
	if (g_iTopBid < 1)
	{
		g_iTopBid = 1;
	}
	
	fOrigin = g_fCenter;
	fOrigin[2] += 130.0;
	
	int iDisplay = SpawnDisplay(sModel, fOrigin);
	
	if (iDisplay != -1)
	{
		SetEntProp(iDisplay, Prop_Send, "m_nSkin", iSkin);
		SetEntityRenderColor(iDisplay, iColor[0], iColor[1], iColor[2], 255);
		
		g_iAuctionRef = EntIndexToEntRef(iDisplay);
	}
	
	Cel_PrintToChatAll("{green}Auction!{default} {green}%s{default} is selling a {green}%s{default} above the Guess Booth. Bidding starts at {green}%d CL{default} and ends in {green}%d{default} minute%s. Bid with {green}!bid <amount>{default}.", g_sSellerName, g_sAuctionName, g_iTopBid, RoundToCeil(fMinutes), RoundToCeil(fMinutes) == 1 ? "" : "s");
	
	if (bOwn)
	{
		Cel_ReplyToCommand(iClient, "Keep a spare {green}%s{default} in your bank until it ends: it goes to the winner then, and their bid to you. {green}[tag]auction cancel{default} calls it off.", g_sAuctionName);
	}
	
	return Plugin_Handled;
}

//A bid is a promise: nothing is paid until the auction ends.
public Action Command_Bid(int iClient, int iArgs)
{
	char sAmount[32];
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	if (!g_bAuction)
	{
		Cel_ReplyToCommand(iClient, "There is no auction running.");
		return Plugin_Handled;
	}
	
	if (g_iAuctionSeller != 0 && GetClientOfUserId(g_iAuctionSeller) == iClient)
	{
		Cel_ReplyToCommand(iClient, "You can't bid on your own auction.");
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]bid{default} <amount>. The bid to beat is {green}%d CL{default}.", g_iTopBid);
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sAmount, sizeof(sAmount));
	
	int iAmount = StringToInt(sAmount);
	
	//The first bid may match the starting price, later bids must be higher than the last.
	if (iAmount < g_iTopBid || (g_iTopBidder > 0 && iAmount <= g_iTopBid))
	{
		Cel_ReplyToCommand(iClient, "Your bid must be %s {green}%d CL{default}.", g_iTopBidder > 0 ? "higher than" : "at least", g_iTopBid);
		return Plugin_Handled;
	}
	
	if (Cel_GetClientBalance(iClient) < iAmount)
	{
		Cel_ReplyToCommand(iClient, "You don't have {green}%d CL{default}.", iAmount);
		return Plugin_Handled;
	}
	
	int iUser = GetClientUserId(iClient), iSlot = -1;
	
	for (int b = 0; b < g_iBidCount; b++)
	{
		if (g_iBidUser[b] == iUser)
		{
			iSlot = b;
		}
	}
	
	if (iSlot == -1)
	{
		if (g_iBidCount >= MAX_BIDS)
		{
			Cel_ReplyToCommand(iClient, "This auction has too many bidders already.");
			return Plugin_Handled;
		}
		
		iSlot = g_iBidCount++;
		g_iBidUser[iSlot] = iUser;
	}
	
	g_iBidAmount[iSlot] = iAmount;
	g_iTopBid = iAmount;
	g_iTopBidder = iUser;
	
	//A late bid always leaves others 20 seconds to answer.
	if (g_fAuctionEnd - GetGameTime() < 20.0)
	{
		g_fAuctionEnd = GetGameTime() + 20.0;
	}
	
	Cel_PrintToChatAll("{green}%N{default} bid {green}%d CL{default} on the {green}%s{default}. You pay only if you win, when it ends.", iClient, iAmount, g_sAuctionName);
	
	return Plugin_Handled;
}

//The highest bid that can still go through wins: its bidder is here and can pay, and the seller still has the item.
void EndAuction()
{
	int iSeller = (g_iAuctionSeller != 0) ? GetClientOfUserId(g_iAuctionSeller) : 0;
	
	if (g_iBidCount == 0)
	{
		Cel_PrintToChatAll("The auction for the {green}%s{default} ended with no bids%s.", g_sAuctionName, g_iAuctionSeller != 0 ? "; it stays with its seller" : "");
		ClearAuction();
		return;
	}
	
	if (g_iAuctionSeller != 0 && (iSeller < 1 || !IsClientInGame(iSeller)))
	{
		Cel_PrintToChatAll("The auction for the {green}%s{default} is off: the seller has left. Nobody paid anything.", g_sAuctionName);
		ClearAuction();
		return;
	}
	
	//Highest bid first.
	for (int a = 0; a < g_iBidCount; a++)
	{
		for (int b = a + 1; b < g_iBidCount; b++)
		{
			if (g_iBidAmount[b] > g_iBidAmount[a])
			{
				int iU = g_iBidUser[a], iA = g_iBidAmount[a];
				
				g_iBidUser[a] = g_iBidUser[b]; g_iBidAmount[a] = g_iBidAmount[b];
				g_iBidUser[b] = iU; g_iBidAmount[b] = iA;
			}
		}
	}
	
	for (int b = 0; b < g_iBidCount; b++)
	{
		int iWinner = GetClientOfUserId(g_iBidUser[b]), iPrice = g_iBidAmount[b];
		
		if (iWinner < 1 || !IsClientInGame(iWinner) || Cel_GetClientBalance(iWinner) < iPrice)
		{
			continue;
		}
		
		//The seller's spare copy moves to the winner; if they no longer have one, the sale is off.
		if (iSeller > 0 && !Cel_TakeCollectible(iSeller, g_sAuctionKind, g_sAuctionId))
		{
			Cel_PrintToChatAll("The auction for the {green}%s{default} is off: the seller no longer has a spare one. Nobody paid anything.", g_sAuctionName);
			ClearAuction();
			return;
		}
		
		Cel_SubFromClientBalance(iWinner, iPrice);
		Cel_GiveCollectible(iWinner, g_sAuctionKind, g_sAuctionId);
		
		if (iSeller > 0)
		{
			Cel_AddToClientBalance(iSeller, iPrice);
			Cel_PrintToChat(iSeller, "You sold your {green}%s{default} to {green}%N{default} for {green}%d CL{default}.", g_sAuctionName, iWinner, iPrice);
		}
		
		Cel_PrintToChatAll("{green}%N{default} won the {green}%s{default} for {green}%d CL{default}!", iWinner, g_sAuctionName, iPrice);
		
		ClearAuction();
		return;
	}
	
	Cel_PrintToChatAll("The auction for the {green}%s{default} ended, but none of its bidders are here with enough money any more. Nothing changed hands.", g_sAuctionName);
	ClearAuction();
}

//The seller leaving calls their auction off (nothing has changed hands yet).
public void OnClientDisconnect(int iClient)
{
	if (g_bAuction && g_iAuctionSeller != 0 && GetClientOfUserId(g_iAuctionSeller) == iClient)
	{
		Cel_PrintToChatAll("The auction for the {green}%s{default} is off: the seller has left.", g_sAuctionName);
		ClearAuction();
	}
}

//An auction still running when the map changes is called off; nobody has paid anything.
public void OnMapEnd()
{
	if (g_bAuction)
	{
		ClearAuction();
	}
}

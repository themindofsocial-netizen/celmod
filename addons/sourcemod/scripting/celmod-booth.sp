#pragma semicolon 1

#include <celmod>

#pragma newdecls required

/*
 * |CelMod| Guess Booth
 *
 * A small yellow square at a spot an admin chose for the map (!setguessbooth, saved as data/celmod/guessbooth/<map>.txt),
 * with three props floating in it. Maps without a saved spot have no Guess Booth.
 * One of the three is the winner. A player standing in the booth gets one guess per map; a right guess pays out.
 *
 * Admins can hang an item above the booth and auction it: players bid with !bid, the highest bidder gets it.
 */

#define BOOTH_HALF 136.0
#define DISPLAY_SIZE 40.0
#define KLEINER_MODEL "models/kleiner.mdl"
#define CONE_MODEL "models/props_junk/trafficcone001a.mdl"
#define KLEINER_HELLO "vo/k_lab/kl_ahhhh.wav"

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

float g_fAuctionEnd;
float g_fCenter[3];

int g_iAnswer;
int g_iAuctionRef = INVALID_ENT_REFERENCE;
int g_iBeam = -1;
int g_iKleinerRef = INVALID_ENT_REFERENCE;
int g_iConeRef = INVALID_ENT_REFERENCE;

//Players Dr. Kleiner has already greeted on this map.
bool g_bGreeted[MAXPLAYERS + 1];
int g_iPropRef[3] = { INVALID_ENT_REFERENCE, INVALID_ENT_REFERENCE, INVALID_ENT_REFERENCE };
int g_iTopBid;
int g_iTopBidder;

//Steam ids of everyone who has used their guess on this map.
StringMap g_smGuessed;

public Plugin myinfo =
{
	name = "|CelMod| Guess Booth",
	author = CEL_AUTHOR,
	description = "The Guess Booth and the auctions held above it.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	
	BuildPath(Path_SM, g_sSpawnDB, sizeof(g_sSpawnDB), "data/celmod/spawns.txt");
	BuildPath(Path_SM, g_sBoothDB, sizeof(g_sBoothDB), "data/celmod/guessbooth.txt");
	
	g_smGuessed = new StringMap();
	
	g_cvReward = CreateConVar("cm_guess_reward", "5000", "Cleers paid for a correct guess at the Guess Booth.", _, true, 0.0);
	
	AutoExecConfig(true, "celmod.booth");
	
	RegAdminCmd("v_auction", Command_Auction, ADMFLAG_SLAY, "|CelMod| Auctions an emblem, hat or weapon above the Guess Booth, or cancels the auction.");
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
	
	PrecacheModel(KLEINER_MODEL, true);
	PrecacheModel(CONE_MODEL, true);
	PrecacheSound(KLEINER_HELLO, true);
	
	g_iKleinerRef = INVALID_ENT_REFERENCE;
	g_iConeRef = INVALID_ENT_REFERENCE;
	
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
	
	KeyValues kvSpot = new KeyValues("GuessBooth");
	
	if (FileExists(sPath) && kvSpot.ImportFromFile(sPath))
	{
		kvSpot.GetVector("origin", fSpot);
		
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
	
	RemoveRef(g_iKleinerRef);
	RemoveRef(g_iConeRef);
	
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
		//The auction hangs above the booth, so it is called off and the top bid returned.
		RefundTopBidder();
		
		g_bAuction = false;
		
		RemoveRef(g_iAuctionRef);
	}
	
	RemoveBooth();
	
	Cel_ReplyToCommand(iClient, "{green}%s{default} no longer has a Guess Booth.", sMap);
	
	return Plugin_Handled;
}

int SpawnDisplay(const char[] sModel, float fCenter[3], bool bCheckSize = false)
{
	float fMaxs[3], fMins[3], fOrigin[3];
	
	PrecacheModel(sModel);
	
	int iEntity = CreateEntityByName("prop_physics_override");
	
	if (iEntity == -1)
	{
		return -1;
	}
	
	DispatchKeyValue(iEntity, "model", sModel);
	DispatchKeyValue(iEntity, "classname", "cel_boothdisplay");
	
	//A physics prop whose model is missing or has no physics removes itself while spawning.
	if (!DispatchSpawn(iEntity) || !IsValidEntity(iEntity))
	{
		return -1;
	}
	
	AcceptEntityInput(iEntity, "DisableMotion");
	
	SetEntProp(iEntity, Prop_Data, "m_takedamage", 0, 1);
	
	//Players and shots pass straight through it.
	SetEntProp(iEntity, Prop_Send, "m_CollisionGroup", 1);
	SetEntProp(iEntity, Prop_Send, "m_nSolidType", 0);
	
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
	
	PlaceKleiner(fOrigin);
	
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
			
			fPos[0] = fOrigin[0] + (iShown - 1) * 72.0;
			fPos[1] = fOrigin[1];
			fPos[2] = fOrigin[2] + 72.0;
			
			int iEntity = SpawnDisplay(sValue, fPos, true);
			
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
		
		g_iAnswer = GetRandomInt(0, 2);
	} else {
		LogError("|CelMod| The Guess Booth needs at least three props in '%s'.", g_sSpawnDB);
	}
	
	delete alAliases;
	delete alModels;
}

//Dr. Kleiner stands at the back of the booth, frozen in his A-pose, facing whoever walks up.
void PlaceKleiner(float fCenter[3])
{
	float fAngles[3], fPos[3];
	
	RemoveRef(g_iKleinerRef);
	RemoveRef(g_iConeRef);
	
	int iKleiner = CreateEntityByName("prop_dynamic_override");
	
	if (iKleiner == -1)
	{
		return;
	}
	
	fPos[0] = fCenter[0];
	fPos[1] = fCenter[1] + BOOTH_HALF - 24.0;
	fPos[2] = fCenter[2];
	
	//Facing into the booth.
	fAngles[1] = 270.0;
	
	DispatchKeyValue(iKleiner, "model", KLEINER_MODEL);
	DispatchKeyValue(iKleiner, "solid", "2");
	DispatchKeyValue(iKleiner, "DefaultAnim", "ragdoll");
	
	DispatchSpawn(iKleiner);
	// Named after spawning: a prop_dynamic_override renamed before it spawns loses its override and is deleted
	// when its model is a physics-only prop (hats, the traffic cone...).
	DispatchKeyValue(iKleiner, "classname", "cel_booth_kleiner");
	
	TeleportEntity(iKleiner, fPos, fAngles, NULL_VECTOR);
	
	//The model's reference pose: arms out, standing still.
	SetVariantString("ragdoll");
	AcceptEntityInput(iKleiner, "SetAnimation");
	
	SetEntPropFloat(iKleiner, Prop_Send, "m_flPlaybackRate", 0.0);
	
	g_iKleinerRef = EntIndexToEntRef(iKleiner);
	
	//A traffic cone on his head, fixed to his eyes so it sits on his head whatever his pose.
	int iCone = CreateEntityByName("prop_dynamic_override");
	
	if (iCone != -1)
	{
		DispatchKeyValue(iCone, "model", CONE_MODEL);
		DispatchKeyValue(iCone, "solid", "2");
		
		DispatchSpawn(iCone);
		// Named after spawning: a prop_dynamic_override renamed before it spawns loses its override and is deleted
		// when its model is a physics-only prop (hats, the traffic cone...).
		DispatchKeyValue(iCone, "classname", "cel_booth_cone");
		
		//A bounding box (so its size is known) that players walk straight through.
		SetEntProp(iCone, Prop_Send, "m_CollisionGroup", 1);
		
		float fConeMins[3];
		
		GetEntPropVector(iCone, Prop_Send, "m_vecMins", fConeMins);
		
		float fConePos[3], fConeAngles[3];
		
		fConePos = fPos;
		fConePos[2] += 70.0;
		
		TeleportEntity(iCone, fConePos, fAngles, NULL_VECTOR);
		
		if (LookupEntityAttachment(iKleiner, "eyes") > 0)
		{
			SetVariantString("!activator");
			AcceptEntityInput(iCone, "SetParent", iKleiner, iCone);
			
			SetVariantString("eyes");
			AcceptEntityInput(iCone, "SetParentAttachment", iCone, iCone);
			
			//Relative to his eyes: a little back and up, standing upright on top of his head.
			//The cone's base goes about 7 units above his eyes, the top of his head.
			float fOffset[3];
			
			fOffset[0] = -3.0;
			fOffset[2] = 7.0 - fConeMins[2];
			
			SetEntPropVector(iCone, Prop_Send, "m_vecOrigin", fOffset);
			SetEntPropVector(iCone, Prop_Send, "m_angRotation", fConeAngles);
		}
		
		g_iConeRef = EntIndexToEntRef(iCone);
	}
}

public void OnClientPutInServer(int iClient)
{
	g_bGreeted[iClient] = false;
}

bool IsInBooth(int iClient)
{
	float fOrigin[3];
	
	GetClientAbsOrigin(iClient, fOrigin);
	
	return (g_bBooth && FloatAbs(fOrigin[0] - g_fCenter[0]) <= BOOTH_HALF && FloatAbs(fOrigin[1] - g_fCenter[1]) <= BOOTH_HALF && FloatAbs(fOrigin[2] - g_fCenter[2]) <= 160.0);
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
		
		TeleportEntity(iEntity, fOrigin, fAngles, NULL_VECTOR);
	}
	
	return Plugin_Continue;
}

//Draws the yellow square, tells players near the booth what it is, and ends the auction on time.
public Action Timer_Booth(Handle hTimer)
{
	char sText[192];
	float fA[3], fB[3], fOrigin[3];
	int iYellow[4] = { 255, 220, 0, 255 };
	
	if (!g_bBooth || g_iBeam < 1)
	{
		return Plugin_Continue;
	}
	
	for (int iEdge = 0; iEdge < 4; iEdge++)
	{
		int iNext = (iEdge + 1) % 4;
		
		fA[0] = g_fCenter[0] + ((iEdge == 1 || iEdge == 2) ? BOOTH_HALF : -BOOTH_HALF);
		fA[1] = g_fCenter[1] + ((iEdge >= 2) ? BOOTH_HALF : -BOOTH_HALF);
		fA[2] = g_fCenter[2] + 4.0;
		
		fB[0] = g_fCenter[0] + ((iNext == 1 || iNext == 2) ? BOOTH_HALF : -BOOTH_HALF);
		fB[1] = g_fCenter[1] + ((iNext >= 2) ? BOOTH_HALF : -BOOTH_HALF);
		fB[2] = fA[2];
		
		TE_SetupBeamPoints(fA, fB, g_iBeam, 0, 0, 0, 1.05, 3.0, 3.0, 0, 0.0, iYellow, 0);
		TE_SendToAll();
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
		
		//Dr. Kleiner greets everyone once a map, the first time they step into the booth.
		int iKleiner = EntRefToEntIndex(g_iKleinerRef);
		
		if (!g_bGreeted[i] && IsInBooth(i) && iKleiner != INVALID_ENT_REFERENCE)
		{
			g_bGreeted[i] = true;
			
			EmitSoundToClient(i, KLEINER_HELLO, iKleiner);
			
			Cel_PrintToChat(i, "{green}Dr. Kleiner:{default} Ah, hello! Welcome to the Guess Booth. One of these three props is the winner. Pick it with {green}!guess 1{default}, {green}2{default} or {green}3{default}.");
		}
		
		if (g_bAuction)
		{
			if (g_iTopBidder > 0 && GetClientOfUserId(g_iTopBidder) > 0)
			{
				Format(sText, sizeof(sText), "Auction: %s\nTop bid: %d CL by %N\n%d:%02d left  -  !bid <amount>", g_sAuctionName, g_iTopBid, GetClientOfUserId(g_iTopBidder), iLeft / 60, iLeft % 60);
			} else {
				Format(sText, sizeof(sText), "Auction: %s\nStarting bid: %d CL\n%d:%02d left  -  !bid <amount>", g_sAuctionName, g_iTopBid, iLeft / 60, iLeft % 60);
			}
		} else {
			Format(sText, sizeof(sText), "Guess Booth\nOne of the three props is the winner.\nStand in the square and type !guess 1, 2 or 3");
		}
		
		//A quiet message at the top of the screen; hint text beeps every time it is shown.
		Cel_SendHudMessage(i, 4, -1.0, 0.12, 255, 220, 0, 255, 0, 0.0, 0.2, 1.1, 0.0, sText);
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
		Cel_ReplyToCommand(iClient, "Stand inside the yellow square of the Guess Booth to guess.");
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
	
	if (iGuess == g_iAnswer)
	{
		Cel_AddToClientBalance(iClient, g_cvReward.IntValue);
		
		EmitSoundToClient(iClient, "buttons/button9.wav");
		
		Cel_PrintToChatAll("{green}%N{default} guessed the right prop at the Guess Booth ({green}%s{default}) and won {green}%d CL{default}!", iClient, g_sPropAlias[g_iAnswer], g_cvReward.IntValue);
	} else {
		EmitSoundToClient(iClient, "buttons/button8.wav");
		
		Cel_ReplyToCommand(iClient, "Wrong, it was not {green}%s{default}. Better luck on the next map.", g_sPropAlias[iGuess]);
	}
	
	return Plugin_Handled;
}

//Auctions:
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
		
		RefundTopBidder();
		
		g_bAuction = false;
		
		RemoveRef(g_iAuctionRef);
		
		Cel_PrintToChatAll("The auction for the {green}%s{default} has been cancelled.", g_sAuctionName);
		
		return Plugin_Handled;
	}
	
	if (iArgs < 3)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]auction{default} <emblem/hat/weapon> <name> <minutes> [starting bid], or {green}[tag]auction cancel{default}");
		return Plugin_Handled;
	}
	
	if (g_bAuction)
	{
		Cel_ReplyToCommand(iClient, "An auction is already running. Cancel it first with {green}[tag]auction cancel{default}.");
		return Plugin_Handled;
	}
	
	if (!g_bBooth)
	{
		Cel_ReplyToCommand(iClient, "There is no Guess Booth on this map. Place one with {green}[tag]guessbooth{default}.");
		return Plugin_Handled;
	}
	
	for (int i = 1; i < 4 && i < iArgs; i++)
	{
		GetCmdArg(i + 1, sArg[i], sizeof(sArg[]));
	}
	
	if (!Cel_GetCollectibleLook(sArg[0], sArg[1], sModel, sizeof(sModel), g_sAuctionName, sizeof(g_sAuctionName), iSkin, iColor))
	{
		Cel_ReplyToCommand(iClient, "There is no %s called {green}%s{default}.", sArg[0], sArg[1]);
		return Plugin_Handled;
	}
	
	strcopy(g_sAuctionKind, sizeof(g_sAuctionKind), sArg[0]);
	strcopy(g_sAuctionId, sizeof(g_sAuctionId), sArg[1]);
	
	float fMinutes = StringToFloat(sArg[2]);
	
	if (fMinutes < 0.5)
	{
		fMinutes = 0.5;
	}
	
	g_bAuction = true;
	g_fAuctionEnd = GetGameTime() + fMinutes * 60.0;
	g_iTopBid = StringToInt(sArg[3]);
	g_iTopBidder = 0;
	
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
	
	Cel_PrintToChatAll("{green}Auction!{default} A {green}%s{default} is hanging above the Guess Booth. Bidding starts at {green}%d CL{default} and ends in {green}%d{default} minute%s. Bid with {green}!bid <amount>{default}.", g_sAuctionName, g_iTopBid, RoundToCeil(fMinutes), RoundToCeil(fMinutes) == 1 ? "" : "s");
	
	return Plugin_Handled;
}

//A bid is paid when it is made, and given back in full when someone bids higher.
void RefundTopBidder()
{
	int iBidder = GetClientOfUserId(g_iTopBidder);
	
	if (g_iTopBidder > 0 && iBidder > 0 && IsClientInGame(iBidder))
	{
		Cel_AddToClientBalance(iBidder, g_iTopBid);
		
		Cel_PrintToChat(iBidder, "Your bid of {green}%d CL{default} on the {green}%s{default} has been returned.", g_iTopBid, g_sAuctionName);
	}
	
	g_iTopBidder = 0;
}

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
	
	int iOwnBid = (GetClientOfUserId(g_iTopBidder) == iClient) ? g_iTopBid : 0;
	
	if (Cel_GetClientBalance(iClient) + iOwnBid < iAmount)
	{
		Cel_ReplyToCommand(iClient, "You do not have {green}%d CL{default}.", iAmount);
		return Plugin_Handled;
	}
	
	RefundTopBidder();
	
	Cel_SubFromClientBalance(iClient, iAmount);
	
	g_iTopBid = iAmount;
	g_iTopBidder = GetClientUserId(iClient);
	
	//A late bid always leaves others 20 seconds to answer.
	if (g_fAuctionEnd - GetGameTime() < 20.0)
	{
		g_fAuctionEnd = GetGameTime() + 20.0;
	}
	
	Cel_PrintToChatAll("{green}%N{default} bid {green}%d CL{default} on the {green}%s{default}.", iClient, iAmount, g_sAuctionName);
	
	return Plugin_Handled;
}

void EndAuction()
{
	int iWinner = GetClientOfUserId(g_iTopBidder);
	
	g_bAuction = false;
	
	RemoveRef(g_iAuctionRef);
	
	if (g_iTopBidder == 0)
	{
		Cel_PrintToChatAll("The auction for the {green}%s{default} ended with no bids.", g_sAuctionName);
	} else if (iWinner < 1 || !IsClientInGame(iWinner))
	{
		Cel_PrintToChatAll("The auction for the {green}%s{default} ended, but the highest bidder has left the server. Nobody receives it.", g_sAuctionName);
	} else {
		Cel_GiveCollectible(iWinner, g_sAuctionKind, g_sAuctionId);
		
		Cel_PrintToChatAll("{green}%N{default} won the {green}%s{default} for {green}%d CL{default}!", iWinner, g_sAuctionName, g_iTopBid);
	}
	
	g_iTopBidder = 0;
}

//Bids are handed back if the map changes before the auction ends.
public void OnMapEnd()
{
	if (g_bAuction)
	{
		RefundTopBidder();
		
		g_bAuction = false;
	}
}

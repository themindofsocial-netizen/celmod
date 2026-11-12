#pragma semicolon 1

#include <celmod>
#include <studio_hdr>

#pragma newdecls required

/*
 * |CelMod| Guess Booth
 *
 * A small yellow square that appears near a spawn point on every map, with three props floating in it.
 * One of the three is the winner. A player standing in the booth gets one guess per map; a right guess pays out.
 *
 * Admins can hang an item above the booth and auction it: players bid with !bid, the highest bidder gets it.
 */

#define BOOTH_HALF 160.0
#define DISPLAY_SIZE 40.0
#define KLEINER_MODEL "models/kleiner.mdl"
#define CONE_MODEL "models/props_junk/trafficcone001a.mdl"
#define KLEINER_HELLO "vo/k_lab/kl_ahhhh.wav"

bool g_bAuction;
bool g_bBooth;

char g_sAuctionId[64];
char g_sAuctionKind[32];
char g_sAuctionName[64];
char g_sPropAlias[3][64];
char g_sSpawnDB[PLATFORM_MAX_PATH];

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
	
	g_smGuessed = new StringMap();
	
	g_cvReward = CreateConVar("cm_guess_reward", "5000", "Cleers paid for a correct guess at the Guess Booth.", _, true, 0.0);
	
	AutoExecConfig(true, "celmod.booth");
	
	RegAdminCmd("v_auction", Command_Auction, ADMFLAG_SLAY, "|CelMod| Auctions an emblem, hat or weapon above the Guess Booth, or cancels the auction.");
	RegAdminCmd("v_guessbooth", Command_GuessBooth, ADMFLAG_SLAY, "|CelMod| Moves the Guess Booth to where you are standing and picks new props.");
	RegConsoleCmd("v_bid", Command_Bid, "|CelMod| Bids on the item being auctioned above the Guess Booth.");
	RegConsoleCmd("v_guess", Command_Guess, "|CelMod| Guesses the winning prop at the Guess Booth. One guess per map.");
	
	CreateTimer(1.0, Timer_Booth, _, TIMER_REPEAT);
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
	
	//Placed before the Power Booth, which then keeps far away from it.
	CreateTimer(3.0, Timer_PlaceBooth, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_PlaceBooth(Handle hTimer)
{
	float fSpot[3];
	
	//Somewhere random in the map, on clear flat ground big enough for the square, well away from the Power Booth.
	float fPowerBooth[3];
	float fAvoid = 0.0;
	
	int iPowerBooth = FindEntityByClassname(-1, "cel_powerbooth");
	
	if (iPowerBooth != -1)
	{
		GetEntPropVector(iPowerBooth, Prop_Data, "m_vecAbsOrigin", fPowerBooth);
		
		fAvoid = 2000.0;
	}
	
	if (Cel_FindRandomMapSpot(true, BOOTH_HALF, 96.0, fSpot, fPowerBooth, fAvoid) || (fAvoid > 0.0 && Cel_FindRandomMapSpot(true, BOOTH_HALF, 96.0, fSpot, fPowerBooth, 800.0)))
	{
		PlaceBooth(fSpot);
		
		return Plugin_Stop;
	}
	
	LogError("|CelMod| No flat open spot was found for the Guess Booth on this map. It is placed near a spawn point instead.");
	
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
	
	if (iCount > 0)
	{
		GetEntPropVector(iPoints[GetRandomInt(0, iCount - 1)], Prop_Data, "m_vecAbsOrigin", fOrigin);
		
		float fYaw = GetRandomFloat(0.0, 6.28);
		
		fOrigin[0] += Cosine(fYaw) * 180.0;
		fOrigin[1] += Sine(fYaw) * 180.0;
		
		PlaceBooth(fOrigin);
	}
	
	return Plugin_Stop;
}

//Scales a display model so its longest side is the display size, whatever the prop is, and moves it so the
//middle of the model sits on the display point (some props have their origin at a corner or far below).
void FitDisplay(int iEntity, float fCenter[3])
{
	float fMaxs[3], fMins[3];
	
	//The model's own size, from the model file; the entity's collision box is empty when it is not solid.
	StudioHdr hdr = StudioHdr.FromEntity(iEntity);
	
	hdr.get_hull_min(fMins);
	hdr.get_hull_max(fMaxs);
	
	if (fMaxs[0] - fMins[0] < 1.0 && fMaxs[1] - fMins[1] < 1.0 && fMaxs[2] - fMins[2] < 1.0)
	{
		hdr.get_view_bbmin(fMins);
		hdr.get_view_bbmax(fMaxs);
	}
	
	float fLongest = 1.0;
	
	for (int i = 0; i < 3; i++)
	{
		if (fMaxs[i] - fMins[i] > fLongest)
		{
			fLongest = fMaxs[i] - fMins[i];
		}
	}
	
	float fScale = DISPLAY_SIZE / fLongest;
	
	//A model with no size information would otherwise be blown up to an enormous size.
	if (fLongest <= 1.0 || fScale > 4.0)
	{
		fScale = 1.0;
		fMins[0] = 0.0; fMins[1] = 0.0; fMins[2] = 0.0;
		fMaxs[0] = 0.0; fMaxs[1] = 0.0; fMaxs[2] = 0.0;
	} else if (fScale < 0.05)
	{
		fScale = 0.05;
	}
	
	SetEntPropFloat(iEntity, Prop_Send, "m_flModelScale", fScale);
	
	float fOrigin[3];
	
	for (int i = 0; i < 3; i++)
	{
		fOrigin[i] = fCenter[i] - (fMins[i] + fMaxs[i]) * 0.5 * fScale;
	}
	
	TeleportEntity(iEntity, fOrigin, NULL_VECTOR, NULL_VECTOR);
}

int SpawnDisplay(const char[] sModel, float fOrigin[3])
{
	int iEntity = CreateEntityByName("prop_dynamic_override");
	
	if (iEntity == -1)
	{
		return -1;
	}
	
	PrecacheModel(sModel);
	
	DispatchKeyValue(iEntity, "model", sModel);
	DispatchKeyValue(iEntity, "solid", "0");
	DispatchKeyValue(iEntity, "classname", "cel_boothdisplay");
	
	DispatchSpawn(iEntity);
	
	FitDisplay(iEntity, fOrigin);
	
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
			
			//Only props the server really has: custom CelMod models that are not installed would show nothing.
			if (ExplodeString(sValue, "|", sBuffer, 2, sizeof(sBuffer[])) == 2 && StrEqual(sBuffer[0], "prop_physics_override") && FileExists(sBuffer[1], true))
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
		for (int i = 0; i < 3; i++)
		{
			int iPick = GetRandomInt(0, alAliases.Length - 1);
			
			alAliases.GetString(iPick, g_sPropAlias[i], sizeof(g_sPropAlias[]));
			alModels.GetString(iPick, sValue, sizeof(sValue));
			
			//Taken out of the list so the same prop is not shown twice.
			alAliases.Erase(iPick);
			alModels.Erase(iPick);
			
			fPos[0] = fOrigin[0] + (i - 1) * 80.0;
			fPos[1] = fOrigin[1];
			fPos[2] = fOrigin[2] + 72.0;
			
			int iEntity = SpawnDisplay(sValue, fPos);
			
			g_iPropRef[i] = (iEntity == -1) ? INVALID_ENT_REFERENCE : EntIndexToEntRef(iEntity);
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
	DispatchKeyValue(iKleiner, "classname", "cel_booth_kleiner");
	
	DispatchSpawn(iKleiner);
	
	TeleportEntity(iKleiner, fPos, fAngles, NULL_VECTOR);
	
	//The model's reference pose: arms out, standing still.
	SetVariantString("ragdoll");
	AcceptEntityInput(iKleiner, "SetAnimation");
	
	SetEntPropFloat(iKleiner, Prop_Send, "m_flPlaybackRate", 0.0);
	
	g_iKleinerRef = EntIndexToEntRef(iKleiner);
	
	//A traffic cone on his head.
	int iCone = CreateEntityByName("prop_dynamic_override");
	
	if (iCone != -1)
	{
		//He never moves, so the cone simply sits at the top of his head: the top of his model, less a little.
		float fConePos[3], fKleinerMaxs[3];
		
		GetEntPropVector(iKleiner, Prop_Send, "m_vecMaxs", fKleinerMaxs);
		
		fConePos = fPos;
		fConePos[2] += (fKleinerMaxs[2] > 40.0 ? fKleinerMaxs[2] : 72.0) - 2.0;
		
		DispatchKeyValue(iCone, "model", CONE_MODEL);
		DispatchKeyValue(iCone, "solid", "0");
		DispatchKeyValue(iCone, "classname", "cel_booth_cone");
		DispatchKeyValueFloat(iCone, "modelscale", 0.6);
		
		DispatchSpawn(iCone);
		
		TeleportEntity(iCone, fConePos, fAngles, NULL_VECTOR);
		
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
	
	PlaceBooth(fOrigin);
	
	//An auction display moves with the booth.
	int iDisplay = EntRefToEntIndex(g_iAuctionRef);
	
	if (g_bAuction && iDisplay != INVALID_ENT_REFERENCE)
	{
		fOrigin[2] += 130.0;
		
		TeleportEntity(iDisplay, fOrigin, NULL_VECTOR, NULL_VECTOR);
	}
	
	Cel_ReplyToCommand(iClient, "The Guess Booth has been moved here for this map, with new props.");
	
	return Plugin_Handled;
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

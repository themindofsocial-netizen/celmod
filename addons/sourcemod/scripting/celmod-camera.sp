#pragma semicolon 1

#include <sdkhooks>
#include <sdktools>
#include <celmod>

#pragma newdecls required

/*
 * |CelMod| Camera cel
 *
 *   !camera              spawns a security camera cel. Press E on it to look through it.
 *   button  -> camera    (!link) the button shows whoever presses it the camera's view.
 *   internet cel -> camera  pressing E on the internet cel shows the camera's view instead of its page.
 *   TV      -> camera    the TV's screen shows what the camera sees, live.
 *
 * Looking through a camera: you stand still where you are, and E, jump or attack takes you back.
 *
 * A TV's own screen shows the camera when data/celmod/camerascreens.txt has a copy of its model for it (made on the
 * server with tools/make_camera_screens.py: the same model with only the screen's material swapped). Linked, the TV
 * wears that copy; unlinked, its own model again. A TV without one gets the picture laid over its front instead.
 *
 * TV screens use the game's camera render target (_rt_Camera, what Half-Life 2's security monitors use). The game
 * draws only one camera into it at a time, so every TV shows the same live camera: the one most recently linked to a
 * TV or looked through. That's a limit of the engine, not of CelMod.
 */

#define CAMERA_MODEL "models/props_combine/combinecamera001.mdl"
#define VIEW_MODEL "models/props_junk/popcan01a.mdl"
#define SCREEN_MATERIAL "materials/celmod/camerascreen.vmt"
#define SCREEN_SPRITE "celmod/camerascreen.vmt"
#define SND_VIEW "buttons/combine_button1.wav"
#define SND_LEAVE "buttons/combine_button2.wav"

int g_iViewing[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... }; // the camera a player is looking through
int g_iViewHelper[MAXENTITIES + 1] = { INVALID_ENT_REFERENCE, ... }; // per camera: the invisible point players see from
int g_iPointCamera[MAXENTITIES + 1] = { INVALID_ENT_REFERENCE, ... }; // per camera: its point_camera, for TVs
int g_iScreen[MAXENTITIES + 1] = { INVALID_ENT_REFERENCE, ... }; // per TV: the sprite showing the camera
int g_iScreenFor[MAXENTITIES + 1] = { INVALID_ENT_REFERENCE, ... }; // per TV: the camera its screen was made for
int g_iLiveCamera = INVALID_ENT_REFERENCE;
int g_iLastButtons[MAXPLAYERS + 1];
bool g_bIsCamera[MAXENTITIES + 1];
StringMap g_smToCamera; // TV model -> its copy whose screen shows the camera
StringMap g_smToNormal; // and back

public Plugin myinfo =
{
	name = "|CelMod| Camera",
	author = CEL_AUTHOR,
	description = "Camera cels: look through them with buttons and internet cels, and show them on TVs.",
	version = CEL_VERSION,
	url = CEL_URL
};

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	CreateNative("Cel_IsCamera", Native_IsCamera);
	CreateNative("Cel_ViewCamera", Native_ViewCamera);

	RegPluginLibrary("celmod-camera");

	return APLRes_Success;
}

public void OnPluginStart()
{
	RegConsoleCmd("v_camera", Command_Camera, "|CelMod| Spawns a camera cel: look through it with E, a button or an internet cel, or show it on a TV.");

	g_smToCamera = new StringMap();
	g_smToNormal = new StringMap();

	CreateTimer(0.5, Timer_Screens, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	PrecacheModel(CAMERA_MODEL, true);
	PrecacheModel(VIEW_MODEL, true);
	PrecacheModel(SCREEN_SPRITE, true);
	PrecacheSound(SND_VIEW, true);
	PrecacheSound(SND_LEAVE, true);

	AddFileToDownloadsTable(SCREEN_MATERIAL);

	g_iLiveCamera = INVALID_ENT_REFERENCE;

	LoadScreenModels();
}

public void OnClientDisconnect(int iClient)
{
	g_iViewing[iClient] = INVALID_ENT_REFERENCE;
}

public void OnEntityDestroyed(int iEntity)
{
	if (iEntity <= MaxClients || iEntity > MAXENTITIES)
	{
		return;
	}

	// A camera that goes: anyone looking through it comes back, and its helpers go with it.
	if (g_bIsCamera[iEntity])
	{
		g_bIsCamera[iEntity] = false;

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && EntRefToEntIndex(g_iViewing[i]) == iEntity)
			{
				StopViewing(i, false);
			}
		}

		KillRef(g_iViewHelper[iEntity]);
		KillRef(g_iPointCamera[iEntity]);
	}

	KillRef(g_iScreen[iEntity]);
	g_iScreenFor[iEntity] = INVALID_ENT_REFERENCE;
}

// ---- Spawning ------------------------------------------------------------------------------------------------------

public Action Command_Camera(int iClient, int iArgs)
{
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}

	if (!Cel_CheckCelCount(iClient))
	{
		Cel_ReplyToCommand(iClient, "You have reached your cel limit.");
		return Plugin_Handled;
	}

	float fAngles[3], fOrigin[3];

	Cel_GetCrosshairHitOrigin(iClient, fOrigin);
	GetClientAbsAngles(iClient, fAngles);

	// Facing the way you look, so it sees what you see.
	fAngles[0] = 0.0;

	int iCamera = Cel_SpawnProp(iClient, "camera", "prop_physics_override", CAMERA_MODEL, fAngles, fOrigin, 255, 255, 255, 255);

	if (iCamera == -1)
	{
		return Plugin_Handled;
	}

	Cel_FixSpawnPosition(iCamera, fOrigin);

	SetupCamera(iCamera);

	// Spawned as a prop, it counts as a cel.
	Cel_RecountClientEntities(iClient);

	Cel_ReplyToCommand(iClient, "Spawned a {green}camera{default}. Press {green}E{default} on it to look through it, or {green}[tag]link{default} a button, an internet cel or a TV to it.");

	return Plugin_Handled;
}

void SetupCamera(int iCamera)
{
	if (iCamera <= MaxClients || iCamera > MAXENTITIES)
	{
		return;
	}

	g_bIsCamera[iCamera] = true;

	// Lets players press E on it.
	SetEntProp(iCamera, Prop_Data, "m_spawnflags", GetEntProp(iCamera, Prop_Data, "m_spawnflags") | 256);

	SDKUnhook(iCamera, SDKHook_UsePost, Hook_CameraUse);
	SDKHook(iCamera, SDKHook_UsePost, Hook_CameraUse);
}

// A loaded build's cameras are cameras again.
public void Cel_OnLoadEntity(int iClient, int iEntity, KeyValues kvSave)
{
	char sName[16];

	Cel_GetPropName(iEntity, sName, sizeof(sName));

	if (StrEqual(sName, "camera", false))
	{
		SetupCamera(iEntity);

		Cel_RecountClientEntities(iClient);
	}
}

public void Hook_CameraUse(int iCamera, int iActivator, int iCaller, UseType utType, float fValue)
{
	if (iActivator > 0 && iActivator <= MaxClients && IsClientInGame(iActivator) && !Cel_IsLocked(iCamera))
	{
		ViewCamera(iActivator, iCamera);
	}
}

// ---- Looking through a camera --------------------------------------------------------------------------------------

public int Native_IsCamera(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1);

	return iEntity > MaxClients && iEntity <= MAXENTITIES && g_bIsCamera[iEntity] && IsValidEntity(iEntity);
}

public int Native_ViewCamera(Handle hPlugin, int iNumParams)
{
	return ViewCamera(GetNativeCell(1), GetNativeCell(2));
}

bool ViewCamera(int iClient, int iCamera)
{
	if (iClient < 1 || iClient > MaxClients || !IsClientInGame(iClient) || !IsPlayerAlive(iClient)
		|| iCamera <= MaxClients || iCamera > MAXENTITIES || !g_bIsCamera[iCamera] || !IsValidEntity(iCamera))
	{
		return false;
	}

	// Already looking through this one: pressing again takes you back.
	if (EntRefToEntIndex(g_iViewing[iClient]) == iCamera)
	{
		StopViewing(iClient, true);
		return true;
	}

	int iHelper = GetViewHelper(iCamera);

	if (iHelper == -1)
	{
		return false;
	}

	SetClientViewEntity(iClient, iHelper);

	g_iViewing[iClient] = EntIndexToEntRef(iCamera);
	g_iLastButtons[iClient] = GetClientButtons(iClient);

	EmitSoundToClient(iClient, SND_VIEW);
	PrintHintText(iClient, "Looking through a camera\nPress E, jump or attack to stop");

	// Looked through, with a TV showing it: it's the one TVs show.
	if (CameraHasScreen(iCamera))
	{
		MakeLive(iCamera);
	}

	return true;
}

void StopViewing(int iClient, bool bSound)
{
	g_iViewing[iClient] = INVALID_ENT_REFERENCE;

	if (IsClientInGame(iClient))
	{
		SetClientViewEntity(iClient, iClient);

		if (bSound)
		{
			EmitSoundToClient(iClient, SND_LEAVE);
		}
	}
}

// The invisible point a camera is seen from: in front of its lens, turned with it.
int GetViewHelper(int iCamera)
{
	int iHelper = EntRefToEntIndex(g_iViewHelper[iCamera]);

	if (iHelper != INVALID_ENT_REFERENCE)
	{
		return iHelper;
	}

	iHelper = CreateEntityByName("prop_dynamic_override");

	if (iHelper == -1)
	{
		return -1;
	}

	DispatchKeyValue(iHelper, "model", VIEW_MODEL);
	DispatchKeyValue(iHelper, "solid", "0");
	DispatchKeyValue(iHelper, "disableshadows", "1");

	float fPos[3], fAngles[3];

	LensPosition(iCamera, fPos, fAngles);

	TeleportEntity(iHelper, fPos, fAngles, NULL_VECTOR);
	DispatchSpawn(iHelper);

	// Not drawn, but still sent to players (they see from it).
	SetEntityRenderMode(iHelper, RENDER_NONE);

	SetVariantString("!activator");
	AcceptEntityInput(iHelper, "SetParent", iCamera, iHelper);

	g_iViewHelper[iCamera] = EntIndexToEntRef(iHelper);

	return iHelper;
}

// Just in front of the model, along the way it faces.
void LensPosition(int iCamera, float fPos[3], float fAngles[3])
{
	float fMaxs[3], fForward[3];

	GetEntPropVector(iCamera, Prop_Data, "m_vecAbsOrigin", fPos);
	GetEntPropVector(iCamera, Prop_Data, "m_angAbsRotation", fAngles);
	GetEntPropVector(iCamera, Prop_Send, "m_vecMaxs", fMaxs);

	GetAngleVectors(fAngles, fForward, NULL_VECTOR, NULL_VECTOR);

	float fOut = fMaxs[0] + 4.0;

	for (int i = 0; i < 3; i++)
	{
		fPos[i] += fForward[i] * fOut;
	}
}

// While looking through a camera you stay put; E, jump or attack takes you back.
public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAngles[3], int &iWeapon)
{
	if (g_iViewing[iClient] == INVALID_ENT_REFERENCE)
	{
		return Plugin_Continue;
	}

	int iCamera = EntRefToEntIndex(g_iViewing[iClient]);

	if (iCamera == INVALID_ENT_REFERENCE || !IsPlayerAlive(iClient))
	{
		StopViewing(iClient, false);
		return Plugin_Continue;
	}

	int iPressed = iButtons & ~g_iLastButtons[iClient];

	g_iLastButtons[iClient] = iButtons;

	if (iPressed & (IN_USE | IN_JUMP | IN_ATTACK | IN_ATTACK2))
	{
		StopViewing(iClient, true);
	}

	// Nothing else happens while watching (the press that ended it included).
	iButtons = 0;
	fVel[0] = 0.0;
	fVel[1] = 0.0;
	fVel[2] = 0.0;

	return Plugin_Changed;
}

// ---- TVs -----------------------------------------------------------------------------------------------------------

// Props that are TVs: a TV linked to a camera shows it on its screen.
bool IsTV(int iEntity)
{
	if (iEntity <= MaxClients || iEntity > MAXENTITIES || !IsValidEntity(iEntity) || !Cel_IsEntity(iEntity))
	{
		return false;
	}

	char sName[32];

	Cel_GetPropName(iEntity, sName, sizeof(sName));

	return StrEqual(sName, "tv", false) || StrEqual(sName, "monitor1", false) || StrEqual(sName, "monitor2", false) || StrEqual(sName, "monitor3", false);
}

// data/celmod/camerascreens.txt: TV models that have a copy whose own screen shows the camera (made by
// tools/make_camera_screens.py). A linked TV wears the copy, so only its screen changes; unlinked, it gets its own
// model back. TVs without one get a picture laid over the front instead.
void LoadScreenModels()
{
	g_smToCamera.Clear();
	g_smToNormal.Clear();

	char sPath[PLATFORM_MAX_PATH], sNormal[PLATFORM_MAX_PATH], sCopy[PLATFORM_MAX_PATH], sMaterial[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod/camerascreens.txt");

	KeyValues kvScreens = new KeyValues("CameraScreens");

	if (!kvScreens.ImportFromFile(sPath) || !kvScreens.JumpToKey("Screens") || !kvScreens.GotoFirstSubKey())
	{
		delete kvScreens;
		return;
	}

	do
	{
		kvScreens.GetSectionName(sNormal, sizeof(sNormal));
		kvScreens.GetString("model", sCopy, sizeof(sCopy), "");
		kvScreens.GetString("material", sMaterial, sizeof(sMaterial), "");

		// Only once the copy is really on the server (made with the tool).
		if (sCopy[0] == '\0' || !FileExists(sCopy, true))
		{
			continue;
		}

		StringToLower(sNormal);
		StringToLower(sCopy);

		g_smToCamera.SetString(sNormal, sCopy);
		g_smToNormal.SetString(sCopy, sNormal);

		PrecacheModel(sCopy, true);

		AddModelFiles(sCopy);

		if (sMaterial[0] != '\0' && FileExists(sMaterial, false))
		{
			AddFileToDownloadsTable(sMaterial);
		}
	}
	while (kvScreens.GotoNextKey());

	delete kvScreens;
}

void AddModelFiles(const char[] sModel)
{
	static const char sExtensions[][] = { ".mdl", ".vvd", ".phy", ".dx80.vtx", ".dx90.vtx", ".sw.vtx" };
	char sBase[PLATFORM_MAX_PATH], sFile[PLATFORM_MAX_PATH];

	strcopy(sBase, sizeof(sBase), sModel);
	sBase[strlen(sBase) - 4] = '\0';

	for (int i = 0; i < sizeof(sExtensions); i++)
	{
		FormatEx(sFile, sizeof(sFile), "%s%s", sBase, sExtensions[i]);

		if (FileExists(sFile, false))
		{
			AddFileToDownloadsTable(sFile);
		}
	}
}

void StringToLower(char[] sText)
{
	for (int i = 0; sText[i] != '\0'; i++)
	{
		sText[i] = CharToLower(sText[i]);
	}
}

// The TV's model now, and the one it should wear for its link (its camera copy when linked, its own otherwise).
bool ScreenModelFor(int iTV, bool bLinked, char[] sWant, int iMaxLength)
{
	char sModel[PLATFORM_MAX_PATH];

	GetEntPropString(iTV, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
	StringToLower(sModel);

	if (bLinked)
	{
		if (g_smToCamera.GetString(sModel, sWant, iMaxLength))
		{
			return true;
		}

		// Already wearing the copy.
		char sNormal[PLATFORM_MAX_PATH];

		if (g_smToNormal.GetString(sModel, sNormal, sizeof(sNormal)))
		{
			strcopy(sWant, iMaxLength, sModel);
			return true;
		}

		return false;
	}

	return g_smToNormal.GetString(sModel, sWant, iMaxLength);
}

void WearModel(int iTV, const char[] sModel)
{
	char sNow[PLATFORM_MAX_PATH];

	GetEntPropString(iTV, Prop_Data, "m_ModelName", sNow, sizeof(sNow));

	if (!StrEqual(sNow, sModel, false))
	{
		SetEntityModel(iTV, sModel);
	}
}

// Keeps every TV's screen matching its link: the camera on it while it's linked, its own screen once it isn't.
public Action Timer_Screens(Handle hTimer)
{
	if (GetFeatureStatus(FeatureType_Native, "Cel_GetTriggerLink") != FeatureStatus_Available)
	{
		return Plugin_Continue;
	}

	bool bLiveShown;
	int iLive = EntRefToEntIndex(g_iLiveCamera);
	char sModel[PLATFORM_MAX_PATH];

	for (int iTV = MaxClients + 1; iTV <= MAXENTITIES; iTV++)
	{
		if (!IsValidEntity(iTV) || !Cel_IsEntity(iTV))
		{
			if (g_iScreen[iTV] != INVALID_ENT_REFERENCE)
			{
				KillRef(g_iScreen[iTV]);
			}

			g_iScreenFor[iTV] = INVALID_ENT_REFERENCE;
			continue;
		}

		if (!IsTV(iTV))
		{
			continue;
		}

		int iCamera = Cel_GetTriggerLink(iTV, 0);
		bool bLinked = (iCamera != -1 && g_bIsCamera[iCamera]);

		if (!bLinked)
		{
			// Back to its own screen.
			if (ScreenModelFor(iTV, false, sModel, sizeof(sModel)))
			{
				WearModel(iTV, sModel);
			}

			KillRef(g_iScreen[iTV]);
			g_iScreenFor[iTV] = INVALID_ENT_REFERENCE;
			continue;
		}

		if (iCamera == iLive)
		{
			bLiveShown = true;
		}

		bool bNew = (EntRefToEntIndex(g_iScreenFor[iTV]) != iCamera);

		// Its own screen shows the camera (the copy of its model), or a picture over its front.
		if (ScreenModelFor(iTV, true, sModel, sizeof(sModel)))
		{
			WearModel(iTV, sModel);
			KillRef(g_iScreen[iTV]);
		} else if (bNew || EntRefToEntIndex(g_iScreen[iTV]) == INVALID_ENT_REFERENCE) {
			KillRef(g_iScreen[iTV]);
			MakeScreen(iTV);
		}

		if (!bNew)
		{
			continue;
		}

		// Newly linked (or to another camera): that camera goes live.
		g_iScreenFor[iTV] = EntIndexToEntRef(iCamera);

		MakeLive(iCamera);

		bLiveShown = true;
		iLive = iCamera;
	}

	// No TV shows the live camera any more: it stops drawing (a live camera costs every player some frame rate).
	if (!bLiveShown && iLive != INVALID_ENT_REFERENCE)
	{
		int iPoint = EntRefToEntIndex(g_iPointCamera[iLive]);

		if (iPoint != INVALID_ENT_REFERENCE)
		{
			AcceptEntityInput(iPoint, "SetOff");
		}

		g_iLiveCamera = INVALID_ENT_REFERENCE;
	}

	return Plugin_Continue;
}

bool CameraHasScreen(int iCamera)
{
	for (int iTV = MaxClients + 1; iTV <= MAXENTITIES; iTV++)
	{
		if (g_iScreenFor[iTV] != INVALID_ENT_REFERENCE && EntRefToEntIndex(g_iScreenFor[iTV]) == iCamera)
		{
			return true;
		}
	}

	return false;
}

// The screen: a flat sprite of the camera picture over the front of the TV, turned with it.
void MakeScreen(int iTV)
{
	int iSprite = CreateEntityByName("env_sprite_oriented");

	if (iSprite == -1)
	{
		return;
	}

	float fOrigin[3], fAngles[3], fMins[3], fMaxs[3], fForward[3], fCenter[3];

	GetEntPropVector(iTV, Prop_Data, "m_vecAbsOrigin", fOrigin);
	GetEntPropVector(iTV, Prop_Data, "m_angAbsRotation", fAngles);
	GetEntPropVector(iTV, Prop_Send, "m_vecMins", fMins);
	GetEntPropVector(iTV, Prop_Send, "m_vecMaxs", fMaxs);

	GetAngleVectors(fAngles, fForward, NULL_VECTOR, NULL_VECTOR);

	// The middle of the TV's front face.
	float fRight[3], fUp[3];

	GetAngleVectors(fAngles, NULL_VECTOR, fRight, fUp);

	float fMidY = (fMins[1] + fMaxs[1]) * 0.5, fMidZ = (fMins[2] + fMaxs[2]) * 0.5;

	for (int i = 0; i < 3; i++)
	{
		fCenter[i] = fOrigin[i] + fForward[i] * (fMaxs[0] + 0.6) - fRight[i] * fMidY + fUp[i] * fMidZ;
	}

	// The camera picture is 256 pixels square: sized to most of the TV's front.
	float fSide = fMaxs[1] - fMins[1];
	float fHeight = fMaxs[2] - fMins[2];

	if (fHeight < fSide)
	{
		fSide = fHeight;
	}

	char sScale[16];

	FormatEx(sScale, sizeof(sScale), "%.4f", (fSide * 0.7) / 256.0);

	DispatchKeyValue(iSprite, "model", SCREEN_SPRITE);
	DispatchKeyValue(iSprite, "scale", sScale);
	DispatchKeyValue(iSprite, "rendermode", "0");
	DispatchKeyValue(iSprite, "spawnflags", "1");

	TeleportEntity(iSprite, fCenter, fAngles, NULL_VECTOR);
	DispatchSpawn(iSprite);
	AcceptEntityInput(iSprite, "ShowSprite");

	SetVariantString("!activator");
	AcceptEntityInput(iSprite, "SetParent", iTV, iSprite);

	g_iScreen[iTV] = EntIndexToEntRef(iSprite);
}

// Makes this camera the one every TV shows (the game draws one at a time).
void MakeLive(int iCamera)
{
	if (EntRefToEntIndex(g_iLiveCamera) == iCamera)
	{
		return;
	}

	int iPoint = EntRefToEntIndex(g_iPointCamera[iCamera]);

	if (iPoint == INVALID_ENT_REFERENCE)
	{
		iPoint = CreateEntityByName("point_camera");

		if (iPoint == -1)
		{
			return;
		}

		float fPos[3], fAngles[3];

		LensPosition(iCamera, fPos, fAngles);

		DispatchKeyValue(iPoint, "FOV", "75");
		DispatchKeyValue(iPoint, "UseScreenAspectRatio", "0");
		DispatchKeyValue(iPoint, "spawnflags", "0");

		TeleportEntity(iPoint, fPos, fAngles, NULL_VECTOR);
		DispatchSpawn(iPoint);

		SetVariantString("!activator");
		AcceptEntityInput(iPoint, "SetParent", iCamera, iPoint);

		g_iPointCamera[iCamera] = EntIndexToEntRef(iPoint);
	}

	AcceptEntityInput(iPoint, "SetOnAndTurnOthersOff");

	g_iLiveCamera = EntIndexToEntRef(iCamera);
}

void KillRef(int &iRef)
{
	int iEntity = EntRefToEntIndex(iRef);

	if (iEntity != INVALID_ENT_REFERENCE && iEntity > MaxClients)
	{
		AcceptEntityInput(iEntity, "Kill");
	}

	iRef = INVALID_ENT_REFERENCE;
}

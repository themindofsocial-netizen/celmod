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
 *   TV      -> camera    pressing E on the TV shows the camera's view.
 *
 * Looking through a camera: you stand still where you are, and E, jump or attack takes you back. Any number of
 * players can look through cameras at once.
 */

#define CAMERA_MODEL "models/props_combine/combinecamera001.mdl"
#define VIEW_MODEL "models/props_junk/popcan01a.mdl"
#define SND_VIEW "buttons/combine_button1.wav"
#define SND_LEAVE "buttons/combine_button2.wav"

int g_iViewing[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... }; // the camera a player is looking through
int g_iViewHelper[MAXENTITIES + 1] = { INVALID_ENT_REFERENCE, ... }; // per camera: the invisible point players see from
int g_iLastButtons[MAXPLAYERS + 1];
int g_iDrewViewmodel[MAXPLAYERS + 1] = { 1, ... }; // whether their weapon was shown before they looked through a camera
bool g_bIsCamera[MAXENTITIES + 1];
bool g_bTVHooked[MAXENTITIES + 1];

public Plugin myinfo =
{
	name = "|CelMod| Camera",
	author = CEL_AUTHOR,
	description = "Camera cels: look through them with E, buttons, internet cels and TVs.",
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
	RegConsoleCmd("v_camera", Command_Camera, "|CelMod| Spawns a camera cel: look through it with E, or from a linked button, internet cel or TV.");

	CreateTimer(0.5, Timer_TVs, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	PrecacheModel(CAMERA_MODEL, true);
	PrecacheModel(VIEW_MODEL, true);
	PrecacheSound(SND_VIEW, true);
	PrecacheSound(SND_LEAVE, true);
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
	}

	g_bTVHooked[iEntity] = false;
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

	// Your own weapon isn't in the camera's picture (put back as it was afterwards: third person hides it too).
	// Remembered only when starting to watch, not when switching from one camera to another.
	if (EntRefToEntIndex(g_iViewing[iClient]) == INVALID_ENT_REFERENCE)
	{
		g_iDrewViewmodel[iClient] = GetEntProp(iClient, Prop_Send, "m_bDrawViewmodel");
	}

	SetEntProp(iClient, Prop_Send, "m_bDrawViewmodel", 0);

	SetClientViewEntity(iClient, iHelper);

	g_iViewing[iClient] = EntIndexToEntRef(iCamera);
	g_iLastButtons[iClient] = GetClientButtons(iClient);

	EmitSoundToClient(iClient, SND_VIEW);
	// One line: HL2DM's hint box draws a second line on top of the first.
	PrintHintText(iClient, "Looking through a camera: press E, jump or attack to stop");


	return true;
}

void StopViewing(int iClient, bool bSound)
{
	g_iViewing[iClient] = INVALID_ENT_REFERENCE;

	if (IsClientInGame(iClient))
	{
		SetClientViewEntity(iClient, iClient);
		SetEntProp(iClient, Prop_Send, "m_bDrawViewmodel", g_iDrewViewmodel[iClient]);

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

// Props that are TVs: pressing E on one linked to a camera shows the camera's view.
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

// TVs linked to a camera (with !link, or in a loaded build) can be pressed with E.
public Action Timer_TVs(Handle hTimer)
{
	if (GetFeatureStatus(FeatureType_Native, "Cel_GetTriggerLink") != FeatureStatus_Available)
	{
		return Plugin_Continue;
	}

	for (int iTV = MaxClients + 1; iTV <= MAXENTITIES; iTV++)
	{
		if (g_bTVHooked[iTV] || !IsTV(iTV))
		{
			continue;
		}

		int iCamera = Cel_GetTriggerLink(iTV, 0);

		if (iCamera == -1 || !g_bIsCamera[iCamera])
		{
			continue;
		}

		SetEntProp(iTV, Prop_Data, "m_spawnflags", GetEntProp(iTV, Prop_Data, "m_spawnflags") | 256);

		SDKHook(iTV, SDKHook_UsePost, Hook_TVUse);

		g_bTVHooked[iTV] = true;
	}

	return Plugin_Continue;
}

public void Hook_TVUse(int iTV, int iActivator, int iCaller, UseType utType, float fValue)
{
	if (iActivator < 1 || iActivator > MaxClients || !IsClientInGame(iActivator) || Cel_IsLocked(iTV))
	{
		return;
	}

	int iCamera = Cel_GetTriggerLink(iTV, 0);

	if (iCamera != -1 && g_bIsCamera[iCamera])
	{
		ViewCamera(iActivator, iCamera);
	}
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

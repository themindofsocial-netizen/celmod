#pragma semicolon 1

#include <celmod>

#define BUTTON_MODEL "models/dav0r/buttons/switch.mdl"

//!button <style>: the button models to pick from (any spawnable prop's name works too).
static const char g_sButtonStyles[][][] = {
	{ "switch", "models/dav0r/buttons/switch.mdl" },
	{ "combine", "models/props_combine/combinebutton.mdl" },
	{ "elevator", "models/props_lab/freightelevatorbutton.mdl" },
	{ "keypad", "models/props_lab/keypad.mdl" },
	{ "firetrap", "models/props_citizen_tech/firetrap_button01a.mdl" },
	{ "switchbox", "models/props_wasteland/prison_switchbox001a.mdl" },
	{ "lever", "models/props_lab/tpswitch.mdl" }
};

#pragma newdecls required

bool g_bLate;
bool g_bTouched[MAXPLAYERS + 1];

AmmoBitType g_abtAmmoType[MAXENTITIES + 1];
AmmoCrateType g_actAmmoCrateType[MAXENTITIES + 1];
ChargerType g_ctChargerType[MAXENTITIES + 1];
WeaponBitType g_wbtWeaponType[MAXENTITIES + 1];

ControlTriggerType g_cttTriggerType[MAXENTITIES + 1];

bool g_bCreatingLink[MAXPLAYERS + 1];
bool g_bHasLink[MAXENTITIES + 1];

int g_iLinkedEntity[MAXENTITIES + 1];
int g_iLinkingEntity[MAXPLAYERS + 1];
int g_iLinkStage[MAXPLAYERS + 1];

//!animate: up to 10 frames (a position and angles) per prop. A button linked to the prop plays them in order, and
//the next press plays them back. Frames are world positions; saved builds keep them as offsets from the prop, so a
//build loaded somewhere else animates in its new place.
#define ANIM_FRAMES 10
float g_fAnimPos[MAXENTITIES + 1][ANIM_FRAMES][3];
float g_fAnimAng[MAXENTITIES + 1][ANIM_FRAMES][3];
int g_iAnimColor[MAXENTITIES + 1][ANIM_FRAMES][4]; // color and opacity, blended smoothly between frames
int g_iAnimSkin[MAXENTITIES + 1][ANIM_FRAMES];     // skin and render effect switch halfway between frames
int g_iAnimFx[MAXENTITIES + 1][ANIM_FRAMES];
int g_iAnimMask[MAXENTITIES + 1];        // which frames are set (bit 0 = frame 1)
float g_fAnimStep[MAXENTITIES + 1];      // seconds per frame
bool g_bAnimBackward[MAXENTITIES + 1];   // the next press plays the frames in reverse
float g_fAnimStart[MAXENTITIES + 1];     // when the playing animation began (0 = not playing)
bool g_bAnimPlayingBack[MAXENTITIES + 1];

char g_sPasscode[MAXENTITIES + 1][32];
int g_iPassButton[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	CreateNative("Cel_GetAmmoType", Native_GetAmmoType);
	CreateNative("Cel_GetAmmoTypeFromName", Native_GetAmmoTypeFromName);
	CreateNative("Cel_GetAmmoTypeName", Native_GetAmmoTypeName);
	CreateNative("Cel_GetAmmoCrateType", Native_GetAmmoCrateType);
	CreateNative("Cel_GetAmmoCrateTypeFromName", Native_GetAmmoCrateTypeFromName);
	CreateNative("Cel_GetAmmoCrateTypeName", Native_GetAmmoCrateTypeName);
	CreateNative("Cel_GetChargerType", Native_GetChargerType);
	CreateNative("Cel_GetChargerTypeFromName", Native_GetChargerTypeFromName);
	CreateNative("Cel_GetChargerTypeName", Native_GetChargerTypeName);
	CreateNative("Cel_GetTriggerLink", Native_GetTriggerLink);
	CreateNative("Cel_GetTriggerType", Native_GetTriggerType);
	CreateNative("Cel_SetTriggerLink", Native_SetTriggerLink);
	CreateNative("Cel_GetWeaponType", Native_GetWeaponType);
	CreateNative("Cel_GetWeaponTypeFromName", Native_GetWeaponTypeFromName);
	CreateNative("Cel_GetWeaponTypeName", Native_GetWeaponTypeName);
	CreateNative("Cel_IsTrigger", Native_IsTrigger);
	CreateNative("Cel_SpawnAmmoBit", Native_SpawnAmmoBit);
	CreateNative("Cel_SpawnAmmoCrate", Native_SpawnAmmoCrate);
	CreateNative("Cel_SpawnButton", Native_SpawnButton);
	MarkNativeAsOptional("Cel_CheckShopProp");
	CreateNative("Cel_SpawnCharger", Native_SpawnCharger);
	//CreateNative("Cel_SpawnTrigger", Native_SpawnTrigger);
	CreateNative("Cel_SpawnWeaponBit", Native_SpawnWeaponBit);
	CreateNative("Cel_TriggerEntity", Native_TriggerEntity);
	
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "|CelMod| Bits",
	author = CEL_AUTHOR,
	description = "Handles all the bit cels. (Triggers, Teleporters, Guns, Ammo crates, Buttons, etc.)",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	LoadTranslations("celmod.phrases");
	
	if (g_bLate)
	{
		for (int i = 1; i < MaxClients; i++)
		{
			if (IsClientAuthorized(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
	
	RegConsoleCmd("v_ammo", Command_SpawnAmmoBit, "|CelMod| Creates an ammo bit that will give ammo when the player touches it.");
	RegConsoleCmd("v_ammocrate", Command_SpawnAmmoCrateBit, "|CelMod| Creates an ammo crate bit that will give ammo to the player.");
	RegConsoleCmd("v_button", Command_SpawnButton, "|CelMod| Spawns a button trigger bit: !button [model], where the model is switch, combine, elevator, keypad, firetrap, switchbox, lever or any prop's name (!button list).");
	RegConsoleCmd("v_charger", Command_SpawnChargerBit, "|CelMod| Creates a health/suit charger bit that will give health/suit to the player.");
	RegConsoleCmd("v_link", Command_Link, "|CelMod| Creates a link between a trigger bit and an entity.");
	RegConsoleCmd("v_animate", Command_Animate, "|CelMod| Animates a prop: !animate <1-10> saves where it is now as that frame; !link a button to it to play the frames. !animate speed <seconds>, play, clear.");
	RegConsoleCmd("v_anim", Command_Animate, "|CelMod| Animates a prop (same as !animate).");
	RegConsoleCmd("v_setpass", Command_SetPass, "|CelMod| Gives the button you are looking at a passcode (off to remove it).");
	RegConsoleCmd("v_pass", Command_Pass, "|CelMod| Uses a passcode button with its passcode: !pass <passcode>.");
	RegConsoleCmd("v_wep", Command_SpawnWeaponBit, "|CelMod| Creates a weapon bit that will give a weapon when the player touches it.");
}

public void OnClientPutInServer(int iClient)
{
	g_bTouched[iClient] = false;
}

public void OnClientDisconnect(int iClient)
{
	g_bTouched[iClient] = false;
}

public Action Command_Link(int iClient, int iArgs)
{
	char sOption[64];
	float fLinkOrigin[2][3];
	
	GetCmdArg(1, sOption, sizeof(sOption));
	
	if (Cel_GetClientAimTarget(iClient) == -1)
	{
		Cel_NotLooking(iClient);
		return Plugin_Handled;
	}
	
	int iEntity = Cel_GetClientAimTarget(iClient);
	
	switch(g_iLinkStage[iClient])
	{
		case 0:
		{
			if(!(Cel_GetEntityType(iEntity) == ENTTYPE_TRIGGER))
			{
				//You cannot make a link on a non-trigger bit.
				Cel_ReplyToCommand(iClient, "%t", "NotTriggerBit");
				return Plugin_Handled;
			}
			
			g_bCreatingLink[iClient] = true;
			g_iLinkingEntity[iClient] = iEntity;
			
			g_iLinkStage[iClient] = 1;
			
			//Started creating link. Type !link on another entity to complete the link.
			Cel_ReplyToCommand(iClient, "%t", "CreatingLink");
			return Plugin_Handled;
		}
		case 1:
		{
			if(Cel_CheckEntityType(iEntity, "door") || Cel_CheckEntityType(iEntity, "effect") || Cel_CheckEntityType(iEntity, "light") || (iEntity <= MAXENTITIES && g_iAnimMask[iEntity] != 0))
			{
				g_iLinkedEntity[g_iLinkingEntity[iClient]] = iEntity;
				g_bHasLink[g_iLinkingEntity[iClient]] = true;
				
				g_bCreatingLink[iClient] = false;
				g_iLinkStage[iClient] = 0;
				
				Cel_GetEntityOrigin(g_iLinkingEntity[iClient], fLinkOrigin[0]);
				Cel_GetEntityOrigin(iEntity, fLinkOrigin[1]);
				
				TE_SetupBeamPoints(fLinkOrigin[0], fLinkOrigin[1], Cel_GetBeamMaterial(), Cel_GetHaloMaterial(), 0, 15, 0.60, 1.0, 1.0, 1, 0.0, g_iOrange, 10); TE_SendToAll();
				
				PrecacheSound("buttons/button19.wav");
				EmitSoundToAll("buttons/button19.wav", g_iLinkingEntity[iClient], 2, 100, 0, 1.0, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
				EmitSoundToAll("buttons/button19.wav", iEntity, 2, 100, 0, 1.0, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
				
				//Created trigger link.
				Cel_ReplyToCommand(iClient, "%t", "CreatedLink");
				return Plugin_Handled;
			}else{
				//You cannot make a link on a physics prop.
				Cel_ReplyToCommandEntity(iClient, iEntity, "%t", "CantLinkEntity");
				return Plugin_Handled;
			}
		}
	}
	
	return Plugin_Handled;
}

public Action Command_SpawnAmmoBit(int iClient, int iArgs)
{
	char sOption[64];
	float fAngles[3], fOrigin[3];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CMD_BitAmmo");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sOption, sizeof(sOption));
	
	AmmoBitType abtType = Cel_GetAmmoTypeFromName(sOption);
	
	if (abtType == AMMOBIT_UNKNOWN)
	{
		Cel_ReplyToCommand(iClient, "%t", "InvalidBitAmmo");
		return Plugin_Handled;
	}
	
	if (!Cel_CheckCelCount(iClient))
	{
		Cel_ReplyToCommand(iClient, "%t", "MaxCelLimit", Cel_GetCelCount(iClient));
		return Plugin_Handled;
	}
	
	GetClientAbsAngles(iClient, fAngles);
	Cel_GetCrosshairHitOrigin(iClient, fOrigin);
	
	int iBit = Cel_SpawnAmmoBit(iClient, abtType, fAngles, fOrigin, 255, 255, 255, 255);
	
	Cel_TeleportInfrontOfClient(iClient, iBit, 20.0);
	
	Cel_ReplyToCommandEntity(iClient, iBit, "%t", "SpawnBitAmmo");
	
	return Plugin_Handled;
}

public Action Command_SpawnAmmoCrateBit(int iClient, int iArgs)
{
	char sOption[64];
	float fAngles[3], fOrigin[3];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CMD_BitAmmoCrate");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sOption, sizeof(sOption));
	
	AmmoCrateType actType = Cel_GetAmmoCrateTypeFromName(sOption);
	
	if (actType == AMMOCRATEBIT_UNKNOWN)
	{
		Cel_ReplyToCommand(iClient, "%t", "InvalidBitAmmoCrate");
		return Plugin_Handled;
	}
	
	if (!Cel_CheckCelCount(iClient))
	{
		Cel_ReplyToCommand(iClient, "%t", "MaxCelLimit", Cel_GetCelCount(iClient));
		return Plugin_Handled;
	}
	
	GetClientAbsAngles(iClient, fAngles);
	Cel_GetCrosshairHitOrigin(iClient, fOrigin);
	
	int iBit = Cel_SpawnAmmoCrate(iClient, actType, fAngles, fOrigin, 255, 255, 255, 255);
	
	Cel_TeleportInfrontOfClient(iClient, iBit, 12.5);
	
	Cel_ReplyToCommandEntity(iClient, iBit, "%t", "SpawnBitAmmoCrate");
	
	return Plugin_Handled;
}

public Action Command_SpawnButton(int iClient, int iArgs)
{
	char sOption[64], sModel[PLATFORM_MAX_PATH] = "", sSpawn[PLATFORM_MAX_PATH], sStyles[192] = "";
	float fAngles[3], fOrigin[3];
	
	GetCmdArg(1, sOption, sizeof(sOption));
	
	for (int i = 0; i < sizeof(g_sButtonStyles); i++)
	{
		Format(sStyles, sizeof(sStyles), "%s%s%s", sStyles, i > 0 ? ", " : "", g_sButtonStyles[i][0]);
	}
	
	if (StrEqual(sOption, "list", false))
	{
		Cel_ReplyToCommand(iClient, "Button models: {green}%s{default}. Any prop's name works too: {green}!button oildrum001{default}", sStyles);
		return Plugin_Handled;
	}
	
	//A style, or the name of any prop players can spawn.
	if (sOption[0] != '\0')
	{
		for (int i = 0; i < sizeof(g_sButtonStyles); i++)
		{
			if (StrEqual(sOption, g_sButtonStyles[i][0], false))
			{
				strcopy(sModel, sizeof(sModel), g_sButtonStyles[i][1]);
			}
		}
		
		//Shop props are bought one copy at a time, so they can't become free buttons.
		if (sModel[0] == '\0' && GetFeatureStatus(FeatureType_Native, "Cel_CheckShopProp") == FeatureStatus_Available
			&& Cel_CheckShopProp(iClient, sOption, sSpawn, sizeof(sSpawn)) != 0)
		{
			Cel_ReplyToCommand(iClient, "Shop props can't be used as buttons.");
			return Plugin_Handled;
		}
		
		if (sModel[0] == '\0' && !Cel_CheckBlacklistDB(sOption) && Cel_CheckSpawnDB(sOption, sSpawn, sizeof(sSpawn)))
		{
			int iBar = FindCharInString(sSpawn, '|');
			
			strcopy(sModel, sizeof(sModel), sSpawn[iBar + 1]);
		}
		
		if (sModel[0] == '\0')
		{
			Cel_ReplyToCommand(iClient, "There's no button model or prop called {green}%s{default}. Button models: {green}%s{default}, or any prop's name.", sOption, sStyles);
			return Plugin_Handled;
		}
		
		if (!Cel_IsPhysicsModelComplete(sModel))
		{
			Cel_ReplyToCommand(iClient, "{green}%s{default} can't be a button: the server doesn't have that model's collision.", sOption);
			return Plugin_Handled;
		}
	}
	
	GetClientAbsAngles(iClient, fAngles);
	Cel_GetCrosshairHitOrigin(iClient, fOrigin);
	
	if (!Cel_CheckCelCount(iClient))
	{
		Cel_ReplyToCommand(iClient, "%t", "MaxCelLimit", Cel_GetCelCount(iClient));
		return Plugin_Handled;
	}
	
	int iBit = Cel_SpawnButton(iClient, fAngles, fOrigin, 255, 255, 255, 255, sModel);
	
	if (iBit == -1)
	{
		return Plugin_Handled;
	}
	
	Cel_TeleportInfrontOfClient(iClient, iBit, 35.0);
	
	Cel_ReplyToCommand(iClient, "%t", "SpawnButton");
	
	if (sOption[0] == '\0')
	{
		Cel_ReplyToCommand(iClient, "Pick another look with {green}!button <model>{default}: {green}%s{default}, or any prop's name.", sStyles);
	}
	
	return Plugin_Handled;
}

public Action Command_SpawnChargerBit(int iClient, int iArgs)
{
	char sOption[64];
	float fAngles[3], fOrigin[3];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CMD_BitCharger");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sOption, sizeof(sOption));
	
	ChargerType ctType = Cel_GetChargerTypeFromName(sOption);
	
	if (ctType == CHARGERBIT_UNKNOWN)
	{
		Cel_ReplyToCommand(iClient, "%t", "InvalidBitCharger");
		return Plugin_Handled;
	}
	
	if (!Cel_CheckCelCount(iClient))
	{
		Cel_ReplyToCommand(iClient, "%t", "MaxCelLimit", Cel_GetCelCount(iClient));
		return Plugin_Handled;
	}
	
	GetClientAbsAngles(iClient, fAngles);
	Cel_GetCrosshairHitOrigin(iClient, fOrigin);
	
	int iBit = Cel_SpawnCharger(iClient, ctType, fAngles, fOrigin, 255, 255, 255, 255);
	
	Cel_TeleportInfrontOfClient(iClient, iBit, 45.0);
	
	Cel_ReplyToCommandEntity(iClient, iBit, "%t", "SpawnBitCharger");
	
	return Plugin_Handled;
}

public Action Command_SpawnWeaponBit(int iClient, int iArgs)
{
	char sOption[64];
	float fAngles[3], fOrigin[3];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CMD_BitWeapon");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sOption, sizeof(sOption));
	
	WeaponBitType wbtType = Cel_GetWeaponTypeFromName(sOption);
	
	if (wbtType == WEPBIT_UNKNOWN)
	{
		Cel_ReplyToCommand(iClient, "%t", "InvalidBitWeapon");
		return Plugin_Handled;
	}
	
	if (!Cel_CheckCelCount(iClient))
	{
		Cel_ReplyToCommand(iClient, "%t", "MaxCelLimit", Cel_GetCelCount(iClient));
		return Plugin_Handled;
	}
	
	GetClientAbsAngles(iClient, fAngles);
	Cel_GetCrosshairHitOrigin(iClient, fOrigin);
	
	int iBit = Cel_SpawnWeaponBit(iClient, wbtType, fAngles, fOrigin, 255, 255, 255, 255);
	
	Cel_TeleportInfrontOfClient(iClient, iBit, 20.0);
	
	Cel_ReplyToCommandEntity(iClient, iBit, "%t", "SpawnBitWeapon");
	
	return Plugin_Handled;
}

//Natives:
public int Native_GetAmmoType(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1);
	
	return view_as<AmmoBitType>(g_abtAmmoType[iEntity]);
}

public int Native_GetAmmoTypeFromName(Handle hPlugin, int iNumParams)
{
	char sAmmo[64];
	
	GetNativeString(1, sAmmo, sizeof(sAmmo));
	
	if(StrContains(sAmmo, "pistol", false) != -1)
	{
		return view_as<int>(AMMOBIT_PISTOL);
	}else if(StrContains(sAmmo, "magnum", false) != -1)
	{
		return view_as<int>(AMMOBIT_MAGNUM);
	}else if(StrContains(sAmmo, "smg", false) != -1)
	{
		return view_as<int>(AMMOBIT_SMG);
	}else if(StrContains(sAmmo, "ar2", false) != -1)
	{
		return view_as<int>(AMMOBIT_AR2);
	}else if(StrContains(sAmmo, "shotgun", false) != -1)
	{
		return view_as<int>(AMMOBIT_SHOTGUN);
	}else if(StrContains(sAmmo, "crossbow", false) != -1)
	{
		return view_as<int>(AMMOBIT_CROSSBOW);
	}else if(StrContains(sAmmo, "rpg", false) != -1)
	{
		return view_as<int>(AMMOBIT_RPG);
	}else{
		return view_as<int>(AMMOBIT_UNKNOWN);
	}
}

public int Native_GetAmmoTypeName(Handle hPlugin, int iNumParams)
{
	AmmoBitType abtType = view_as<AmmoBitType>(GetNativeCell(1));
	char sName[64];
	int iMaxLength = GetNativeCell(3);
	
	switch(abtType)
	{
		case AMMOBIT_PISTOL:
		{
			Format(sName, sizeof(sName), "pistol");
		}
		case AMMOBIT_MAGNUM:
		{
			Format(sName, sizeof(sName), "magnum");
		}
		case AMMOBIT_SMG:
		{
			Format(sName, sizeof(sName), "smg");
		}
		case AMMOBIT_AR2:
		{
			Format(sName, sizeof(sName), "ar2");
		}
		case AMMOBIT_SHOTGUN:
		{
			Format(sName, sizeof(sName), "shotgun");
		}
		case AMMOBIT_CROSSBOW:
		{
			Format(sName, sizeof(sName), "crossbow");
		}
		case AMMOBIT_RPG:
		{
			Format(sName, sizeof(sName), "rpg");
		}
		case AMMOBIT_UNKNOWN:
		{
			Format(sName, sizeof(sName), "unknown");
		}
	}
	
	SetNativeString(2, sName, iMaxLength);
	
	return true;
}

public int Native_GetAmmoCrateType(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1);
	
	return view_as<AmmoCrateType>(g_actAmmoCrateType[iEntity]);
}

public int Native_GetAmmoCrateTypeFromName(Handle hPlugin, int iNumParams)
{
	char sAmmoCrate[64];
	
	GetNativeString(1, sAmmoCrate, sizeof(sAmmoCrate));
	
	if(StrContains(sAmmoCrate, "smg", false) != -1)
	{
		return view_as<int>(AMMOCRATEBIT_SMG);
	}else if(StrContains(sAmmoCrate, "ar2", false) != -1)
	{
		return view_as<int>(AMMOCRATEBIT_AR2);
	}else if(StrContains(sAmmoCrate, "rpg", false) != -1)
	{
		return view_as<int>(AMMOCRATEBIT_RPG);
	}else if(StrContains(sAmmoCrate, "cball", false) != -1)
	{
		return view_as<int>(AMMOCRATEBIT_CBALL);
	}else if(StrContains(sAmmoCrate, "grenade", false) != -1)
	{
		return view_as<int>(AMMOCRATEBIT_GRENADE);
	}else{
		return view_as<int>(AMMOCRATEBIT_UNKNOWN);
	}
}

public int Native_GetAmmoCrateTypeName(Handle hPlugin, int iNumParams)
{
	AmmoCrateType actType = view_as<AmmoCrateType>(GetNativeCell(1));
	char sName[64];
	int iMaxLength = GetNativeCell(3);
	
	switch(actType)
	{
		case AMMOCRATEBIT_SMG:
		{
			Format(sName, sizeof(sName), "smg");
		}
		case AMMOCRATEBIT_AR2:
		{
			Format(sName, sizeof(sName), "ar2");
		}
		case AMMOCRATEBIT_RPG:
		{
			Format(sName, sizeof(sName), "rpg");
		}
		case AMMOCRATEBIT_CBALL:
		{
			Format(sName, sizeof(sName), "combine");
		}
		case AMMOCRATEBIT_GRENADE:
		{
			Format(sName, sizeof(sName), "grenade");
		}
		case AMMOCRATEBIT_UNKNOWN:
		{
			Format(sName, sizeof(sName), "unknown");
		}
	}
	
	SetNativeString(2, sName, iMaxLength);
	
	return true;
}

public int Native_GetChargerType(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1);
	
	return view_as<ChargerType>(g_ctChargerType[iEntity]);
}

public int Native_GetChargerTypeFromName(Handle hPlugin, int iNumParams)
{
	char sCharger[64];
	
	GetNativeString(1, sCharger, sizeof(sCharger));
	
	if(StrContains(sCharger, "health", false) != -1)
	{
		return view_as<int>(CHARGERBIT_HEALTH);
	}else if(StrContains(sCharger, "suit", false) != -1)
	{
		return view_as<int>(CHARGERBIT_SUIT);
	}else{
		return view_as<int>(CHARGERBIT_UNKNOWN);
	}
}

public int Native_GetChargerTypeName(Handle hPlugin, int iNumParams)
{
	ChargerType ctType = view_as<ChargerType>(GetNativeCell(1));
	char sName[64];
	int iMaxLength = GetNativeCell(3);
	
	switch(ctType)
	{
		case CHARGERBIT_HEALTH:
		{
			Format(sName, sizeof(sName), "health");
		}
		case CHARGERBIT_SUIT:
		{
			Format(sName, sizeof(sName), "suit");
		}
		case CHARGERBIT_UNKNOWN:
		{
			Format(sName, sizeof(sName), "unknown");
		}
	}
	
	SetNativeString(2, sName, iMaxLength);
	
	return true;
}

public int Native_GetTriggerType(Handle hPlugin, int iNumParams)
{
	char sClassname[64];
	
	ControlTriggerType cttType;
	
	int iEntity = GetNativeCell(1);
	
	GetEntityClassname(iEntity, sClassname, sizeof(sClassname));
	
	if(StrEqual(sClassname, "bit_trigger_button"))
	{
		cttType = TRIGGERTYPE_BUTTON;
	}else if(StrEqual(sClassname, "bit_trigger_step"))
	{
		cttType = TRIGGERTYPE_STEP;
	}
	
	return view_as<int>(cttType);
}

public int Native_GetWeaponType(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1);
	
	return view_as<WeaponBitType>(g_wbtWeaponType[iEntity]);
}

public int Native_GetWeaponTypeFromName(Handle hPlugin, int iNumParams)
{
	char sWeapon[64];
	
	GetNativeString(1, sWeapon, sizeof(sWeapon));
	
	if(StrContains(sWeapon, "gravgun", false) != -1)
	{
		return view_as<int>(WEPBIT_GRAVGUN);
	}else if(StrContains(sWeapon, "stunstick", false) != -1)
	{
		return view_as<int>(WEPBIT_STUNSTICK);
	}else if(StrContains(sWeapon, "crowbar", false) != -1)
	{
		return view_as<int>(WEPBIT_CROWBAR);
	}else if(StrContains(sWeapon, "pistol", false) != -1)
	{
		return view_as<int>(WEPBIT_PISTOL);
	}else if(StrContains(sWeapon, "magnum", false) != -1)
	{
		return view_as<int>(WEPBIT_MAGNUM);
	}else if(StrContains(sWeapon, "smg", false) != -1)
	{
		return view_as<int>(WEPBIT_SMG);
	}else if(StrContains(sWeapon, "ar2", false) != -1)
	{
		return view_as<int>(WEPBIT_AR2);
	}else if(StrContains(sWeapon, "shotgun", false) != -1)
	{
		return view_as<int>(WEPBIT_SHOTGUN);
	}else if(StrContains(sWeapon, "crossbow", false) != -1)
	{
		return view_as<int>(WEPBIT_CROSSBOW);
	}else if(StrContains(sWeapon, "grenade", false) != -1)
	{
		return view_as<int>(WEPBIT_GRENADE);
	}else if(StrContains(sWeapon, "rpg", false) != -1)
	{
		return view_as<int>(WEPBIT_RPG);
	}else if(StrContains(sWeapon, "slam", false) != -1)
	{
		return view_as<int>(WEPBIT_SLAM);
	}else {
		return view_as<int>(WEPBIT_UNKNOWN);
	}
}

public int Native_GetWeaponTypeName(Handle hPlugin, int iNumParams)
{
	WeaponBitType wbtType = view_as<WeaponBitType>(GetNativeCell(1));
	char sName[64];
	int iMaxLength = GetNativeCell(3);
	
	switch(wbtType)
	{
		case WEPBIT_GRAVGUN:
		{
			Format(sName, sizeof(sName), "gravity gun");
		}
		case WEPBIT_STUNSTICK:
		{
			Format(sName, sizeof(sName), "stunstick");
		}
		case WEPBIT_CROWBAR:
		{
			Format(sName, sizeof(sName), "crowbar");
		}
		case WEPBIT_PISTOL:
		{
			Format(sName, sizeof(sName), "pistol");
		}
		case WEPBIT_MAGNUM:
		{
			Format(sName, sizeof(sName), "magnum");
		}
		case WEPBIT_SMG:
		{
			Format(sName, sizeof(sName), "smg");
		}
		case WEPBIT_AR2:
		{
			Format(sName, sizeof(sName), "ar2");
		}
		case WEPBIT_SHOTGUN:
		{
			Format(sName, sizeof(sName), "shotgun");
		}
		case WEPBIT_CROSSBOW:
		{
			Format(sName, sizeof(sName), "crossbow");
		}
		case WEPBIT_GRENADE:
		{
			Format(sName, sizeof(sName), "grenade");
		}
		case WEPBIT_RPG:
		{
			Format(sName, sizeof(sName), "rpg");
		}
		case WEPBIT_SLAM:
		{
			Format(sName, sizeof(sName), "slam");
		}
		case WEPBIT_UNKNOWN:
		{
			Format(sName, sizeof(sName), "unknown");
		}
	}
	
	SetNativeString(2, sName, iMaxLength);
	
	return true;
}

public int Native_IsTrigger(Handle hPlugin, int iNumParams)
{
	char sClassname[64];
	
	int iEntity = GetNativeCell(1);
	
	GetEntityClassname(iEntity, sClassname, sizeof(sClassname));
	
	if(StrContains(sClassname, "bit_trigger_") != -1)
	{
		return true;
	}else{
		return false;
	}
}

public int Native_SpawnAmmoBit(Handle hPlugin, int iNumParams)
{
	AmmoBitType abtType = view_as<AmmoBitType>(GetNativeCell(2));
	char sModel[64];
	float fAngles[3], fOrigin[3];
	int iBase = CreateEntityByName("prop_physics_override"), iClient = GetNativeCell(1), iColor[4];
	
	GetNativeArray(3, fAngles, 3);
	GetNativeArray(4, fOrigin, 3);
	iColor[0] = GetNativeCell(5);
	iColor[1] = GetNativeCell(6);
	iColor[2] = GetNativeCell(7);
	iColor[3] = GetNativeCell(8);
	
	switch(abtType)
	{
		case AMMOBIT_PISTOL:
		{
			Format(sModel, sizeof(sModel), "models/items/boxmrounds.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_ammo_pistol");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case AMMOBIT_MAGNUM:
		{
			Format(sModel, sizeof(sModel), "models/items/357ammo.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_ammo_magnum");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case AMMOBIT_SMG:
		{
			Format(sModel, sizeof(sModel), "models/items/boxsrounds.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_ammo_smg");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case AMMOBIT_AR2:
		{
			Format(sModel, sizeof(sModel), "models/items/combine_rifle_cartridge01.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_ammo_ar2");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case AMMOBIT_SHOTGUN:
		{
			Format(sModel, sizeof(sModel), "models/items/boxbuckshot.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_ammo_shotgun");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case AMMOBIT_CROSSBOW:
		{
			Format(sModel, sizeof(sModel), "models/items/crossbowrounds.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_ammo_crossbow");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case AMMOBIT_RPG:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_missile_closed.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_ammo_rpg");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case AMMOBIT_UNKNOWN:
		{
			Format(sModel, sizeof(sModel), "models/items/boxmrounds.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_ammo_pistol");
			DispatchKeyValue(iBase, "model", sModel);
			
			abtType = AMMOBIT_UNKNOWN;
		}
	}
	
	DispatchSpawn(iBase);
	
	TeleportEntity(iBase, fOrigin, fAngles, NULL_VECTOR);
	
	Cel_AddToCelCount(iClient);
	Cel_SetColor(iBase, iColor[0], iColor[1], iColor[2], iColor[3]);
	Cel_SetRainbow(iBase, false);
	Cel_SetEntity(iBase, true);
	Cel_SetMotion(iBase, false);
	Cel_SetOwner(iClient, iBase);
	Cel_SetSolid(iBase, true);
	Cel_LockEntity(iBase, false);
	Cel_SetRenderFX(iBase, RENDERFX_NONE);
	
	g_abtAmmoType[iBase] = abtType;
	
	SDKHook(iBase, SDKHook_StartTouchPost, Hook_AmmoBitTouch);
	SDKHook(iBase, SDKHook_EndTouchPost, Hook_StopTouch);
	
	return iBase;
}

public int Native_SpawnAmmoCrate(Handle hPlugin, int iNumParams)
{
	AmmoCrateType actType = view_as<AmmoCrateType>(GetNativeCell(2));
	char sAmmoCrateType[16];
	float fAngles[3], fOrigin[3];
	int iBase = CreateEntityByName("item_ammo_crate"), iClient = GetNativeCell(1), iColor[4];
	
	GetNativeArray(3, fAngles, 3);
	GetNativeArray(4, fOrigin, 3);
	iColor[0] = GetNativeCell(5);
	iColor[1] = GetNativeCell(6);
	iColor[2] = GetNativeCell(7);
	iColor[3] = GetNativeCell(8);
	
	switch(actType)
	{
		case AMMOCRATEBIT_UNKNOWN:
		{
			actType = AMMOCRATEBIT_SMG;
		}
	}
	
	IntToString(view_as<int>(actType), sAmmoCrateType, sizeof(sAmmoCrateType));
	
	DispatchKeyValue(iBase, "AmmoType", sAmmoCrateType);
	DispatchKeyValue(iBase, "classname", "bit_ammocrate");
	
	DispatchSpawn(iBase);
	
	fAngles[1] += 180;
	
	TeleportEntity(iBase, fOrigin, fAngles, NULL_VECTOR);
	
	Cel_AddToCelCount(iClient);
	Cel_SetColor(iBase, iColor[0], iColor[1], iColor[2], iColor[3]);
	Cel_SetRainbow(iBase, false);
	Cel_SetEntity(iBase, true);
	Cel_SetMotion(iBase, false);
	Cel_SetOwner(iClient, iBase);
	Cel_SetSolid(iBase, true);
	Cel_LockEntity(iBase, false);
	Cel_SetRenderFX(iBase, RENDERFX_NONE);
	
	g_actAmmoCrateType[iBase] = actType;
	
	return iBase;
}

//The switch model (and its materials) are sent to players when the server has them.
public void OnMapStart()
{
	Cel_AddModelDownloads(BUTTON_MODEL);
}

public int Native_SpawnButton(Handle hPlugin, int iNumParams)
{
	float fAngles[3], fOrigin[3];
	int iBase, iClient = GetNativeCell(1), iColor[4];
	
	GetNativeArray(2, fAngles, 3);
	GetNativeArray(3, fOrigin, 3);
	iColor[0] = GetNativeCell(4);
	iColor[1] = GetNativeCell(5);
	iColor[2] = GetNativeCell(6);
	iColor[3] = GetNativeCell(7);
	
	iBase = CreateEntityByName("prop_physics_override");
	
	//The model asked for (a style or prop: !button <model>, or the one a saved build had), else the CelMod switch
	//when the server has it, else the Combine button.
	char sButtonModel[PLATFORM_MAX_PATH] = "";
	
	if (iNumParams >= 8)
	{
		GetNativeString(8, sButtonModel, sizeof(sButtonModel));
	}
	
	if (sButtonModel[0] == '\0' || !Cel_IsPhysicsModelComplete(sButtonModel))
	{
		strcopy(sButtonModel, sizeof(sButtonModel), Cel_IsPhysicsModelComplete(BUTTON_MODEL) ? BUTTON_MODEL : "models/props_combine/combinebutton.mdl");
	}
	
	PrecacheModel(sButtonModel);
	
	DispatchKeyValue(iBase, "model", sButtonModel);
	DispatchKeyValue(iBase, "classname", "bit_trigger_button");
	DispatchKeyValue(iBase, "spawnflags", "256");
	
	DispatchSpawn(iBase);
	
	TeleportEntity(iBase, fOrigin, fAngles, NULL_VECTOR);
	
	g_bHasLink[iBase] = false;
	g_iLinkedEntity[iBase] = -1;
	
	Cel_AddToCelCount(iClient);
	Cel_SetColor(iBase, iColor[0], iColor[1], iColor[2], iColor[3]);
	Cel_SetRainbow(iBase, false);
	Cel_SetEntity(iBase, true);
	Cel_SetMotion(iBase, false);
	Cel_SetOwner(iClient, iBase);
	Cel_SetSolid(iBase, true);
	Cel_LockEntity(iBase, false);
	Cel_SetRenderFX(iBase, RENDERFX_NONE);
	
	SDKHook(iBase, SDKHook_UsePost, Hook_ButtonUse);
	
	return iBase;
}

public int Native_SpawnCharger(Handle hPlugin, int iNumParams)
{
	ChargerType ctType = view_as<ChargerType>(GetNativeCell(2));
	float fAngles[3], fOrigin[3];
	int iBase, iClient = GetNativeCell(1), iColor[4];
	
	GetNativeArray(3, fAngles, 3);
	GetNativeArray(4, fOrigin, 3);
	iColor[0] = GetNativeCell(5);
	iColor[1] = GetNativeCell(6);
	iColor[2] = GetNativeCell(7);
	iColor[3] = GetNativeCell(8);
	
	switch(ctType)
	{
		case CHARGERBIT_HEALTH:
		{
			iBase = CreateEntityByName("item_healthcharger");
			
			DispatchKeyValue(iBase, "classname", "bit_charger_health");
		}
		case CHARGERBIT_SUIT:
		{
			iBase = CreateEntityByName("item_suitcharger");
			
			DispatchKeyValue(iBase, "classname", "bit_charger_suit");
		}
		case CHARGERBIT_UNKNOWN:
		{
			iBase = CreateEntityByName("item_healthcharger");
			
			DispatchKeyValue(iBase, "classname", "bit_charger_health");
		}
	}
	
	DispatchSpawn(iBase);
	
	fAngles[1] += 180;
	
	TeleportEntity(iBase, fOrigin, fAngles, NULL_VECTOR);
	
	Cel_AddToCelCount(iClient);
	Cel_SetColor(iBase, iColor[0], iColor[1], iColor[2], iColor[3]);
	Cel_SetRainbow(iBase, false);
	Cel_SetEntity(iBase, true);
	Cel_SetMotion(iBase, false);
	Cel_SetOwner(iClient, iBase);
	Cel_SetSolid(iBase, true);
	Cel_LockEntity(iBase, false);
	Cel_SetRenderFX(iBase, RENDERFX_NONE);
	
	g_ctChargerType[iBase] = ctType;
	
	return iBase;
}

public int Native_SpawnWeaponBit(Handle hPlugin, int iNumParams)
{
	WeaponBitType wbtType = view_as<WeaponBitType>(GetNativeCell(2));
	char sModel[64];
	float fAngles[3], fOrigin[3];
	int iBase = CreateEntityByName("prop_physics_override"), iClient = GetNativeCell(1), iColor[4];
	
	GetNativeArray(3, fAngles, 3);
	GetNativeArray(4, fOrigin, 3);
	iColor[0] = GetNativeCell(5);
	iColor[1] = GetNativeCell(6);
	iColor[2] = GetNativeCell(7);
	iColor[3] = GetNativeCell(8);
	
	switch(wbtType)
	{
		case WEPBIT_GRAVGUN:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_physics.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_wep_gravgun");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case WEPBIT_STUNSTICK:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_stunbaton.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_wep_stunstick");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case WEPBIT_CROWBAR:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_crowbar.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_wep_crowbar");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case WEPBIT_PISTOL:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_pistol.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_wep_pistol");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case WEPBIT_MAGNUM:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_357.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_wep_magnum");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case WEPBIT_SMG:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_smg1.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_wep_smg");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case WEPBIT_AR2:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_irifle.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_wep_ar2");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case WEPBIT_SHOTGUN:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_shotgun.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_wep_shotgun");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case WEPBIT_CROSSBOW:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_crossbow.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_wep_crossbow");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case WEPBIT_GRENADE:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_grenade.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_wep_grenade");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case WEPBIT_RPG:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_rocket_launcher.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_wep_rpg");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case WEPBIT_SLAM:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_slam.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_wep_slam");
			DispatchKeyValue(iBase, "model", sModel);
		}
		case WEPBIT_UNKNOWN:
		{
			Format(sModel, sizeof(sModel), "models/weapons/w_smg1.mdl");
			
			PrecacheModel(sModel);
			
			DispatchKeyValue(iBase, "classname", "bit_wep_smg");
			DispatchKeyValue(iBase, "model", sModel);
			
			wbtType = WEPBIT_SMG;
		}
	}
	
	DispatchSpawn(iBase);
	
	fAngles[1] += 90;
	
	TeleportEntity(iBase, fOrigin, fAngles, NULL_VECTOR);
	
	Cel_AddToCelCount(iClient);
	Cel_SetColor(iBase, iColor[0], iColor[1], iColor[2], iColor[3]);
	Cel_SetRainbow(iBase, false);
	Cel_SetEntity(iBase, true);
	Cel_SetMotion(iBase, false);
	Cel_SetOwner(iClient, iBase);
	Cel_SetSolid(iBase, true);
	Cel_LockEntity(iBase, false);
	Cel_SetRenderFX(iBase, RENDERFX_NONE);
	
	g_wbtWeaponType[iBase] = wbtType;
	
	SDKHook(iBase, SDKHook_StartTouchPost, Hook_WeaponBitTouch);
	SDKHook(iBase, SDKHook_EndTouchPost, Hook_StopTouch);
	
	return iBase;
}

public int Native_TriggerEntity(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1), iEntity = GetNativeCell(2);
	
	if(Cel_IsEntity(g_iLinkedEntity[iEntity]))
	{
		switch(Cel_GetEntityType(g_iLinkedEntity[iEntity]))
		{
			case ENTTYPE_DOOR:
			{
				AcceptEntityInput(g_iLinkedEntity[iEntity], "Toggle", iClient);
			}
			
			case ENTTYPE_LIGHT:
			{
				AcceptEntityInput(Entity_GetEntityAttachment(g_iLinkedEntity[iEntity]), "Toggle", iClient);
				
			}
			
			case ENTTYPE_EFFECT:
			{
				Cel_ActivateEffect(g_iLinkedEntity[iEntity]);
			}
			
			default:
			{
				PlayAnimation(g_iLinkedEntity[iEntity]);
			}
		}
	}
	
	return true;
}

//Hooks:
public void Hook_AmmoBitTouch(int iEntity, int iClient)
{
	//Anything can touch the box (props too): only living players get ammo.
	if (iClient < 1 || iClient > MaxClients || !IsClientInGame(iClient) || !IsPlayerAlive(iClient) || Cel_IsLocked(iEntity) || g_bTouched[iClient])
	{
		return;
	}
	
	//Each box gives what Half-Life 2's own pickup of that ammo gives, on top of what you have (up to the maximum),
	//for a weapon you're carrying.
	char sWeapon[32];
	int iAmount;
	
	switch (Cel_GetAmmoType(iEntity))
	{
		case AMMOBIT_MAGNUM: { sWeapon = "weapon_357"; iAmount = 6; }
		case AMMOBIT_SMG: { sWeapon = "weapon_smg1"; iAmount = 45; }
		case AMMOBIT_AR2: { sWeapon = "weapon_ar2"; iAmount = 20; }
		case AMMOBIT_SHOTGUN: { sWeapon = "weapon_shotgun"; iAmount = 20; }
		case AMMOBIT_CROSSBOW: { sWeapon = "weapon_crossbow"; iAmount = 6; }
		case AMMOBIT_RPG: { sWeapon = "weapon_rpg"; iAmount = 1; }
		default: { sWeapon = "weapon_pistol"; iAmount = 20; }
	}
	
	g_bTouched[iClient] = true;
	
	int iWeapon = Client_GetWeapon(iClient, sWeapon);
	
	if (iWeapon == INVALID_ENT_REFERENCE || iWeapon == -1)
	{
		return;
	}
	
	int iAmmoType = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType");
	
	if (iAmmoType >= 0)
	{
		GivePlayerAmmo(iClient, iAmount, iAmmoType, false);
	}
}

public void Hook_ButtonUse(int iEntity, int iActivator, int iCaller, UseType utType, float fValue)
{
	//A button with a passcode: only its owner presses it straight away; everyone else needs !pass.
	if (!Cel_IsLocked(iEntity) && g_sPasscode[iEntity][0] != '\0' && iActivator > 0 && iActivator <= MaxClients && !Cel_CheckOwner(iActivator, iEntity))
	{
		g_iPassButton[iActivator] = EntIndexToEntRef(iEntity);
		
		PrecacheSound("buttons/combine_button_locked.wav");
		EmitSoundToClient(iActivator, "buttons/combine_button_locked.wav", iEntity);
		
		Cel_PrintToChat(iActivator, "This button requires a passcode.");
		Cel_PrintToChat(iActivator, "If you know the passcode, type {green}!pass{default} and the passcode to use it.");
		
		return;
	}
	
	PressButton(iEntity, iActivator);
}

void PressButton(int iEntity, int iActivator)
{
	if(!Cel_IsLocked(iEntity))
	{
		if(g_bHasLink[iEntity])
		{
			Cel_TriggerEntity(iActivator, iEntity);
			
			PrecacheSound("buttons/combine_button1.wav");
			
			EmitSoundToAll("buttons/combine_button1.wav", iEntity, 2, 100, 0, 1.0, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		}else{
			PrecacheSound("buttons/combine_button_locked.wav");
			
			EmitSoundToAll("buttons/combine_button_locked.wav", iEntity, 2, 100, 0, 1.0, 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		}
	}
}

public void Hook_StopTouch(int iEntity, int iClient)
{
	if (iClient >= 1 && iClient <= MaxClients)
	{
		g_bTouched[iClient] = false;
	}
}

public void Hook_WeaponBitTouch(int iEntity, int iClient)
{
	if (iClient < 1 || iClient > MaxClients || !IsClientInGame(iClient) || !IsPlayerAlive(iClient))
	{
		return;
	}
	
	if(!Cel_IsLocked(iEntity))
	{
		if(!g_bTouched[iClient])
		{
			switch(Cel_GetWeaponType(iEntity))
			{
				case WEPBIT_GRAVGUN:
				{
					Client_GiveWeapon(iClient, "weapon_physcannon", false);
				}
				case WEPBIT_STUNSTICK:
				{
					Client_GiveWeapon(iClient, "weapon_stunstick", false);
				}
				case WEPBIT_CROWBAR:
				{
					Client_GiveWeapon(iClient, "weapon_crowbar", false);
				}
				case WEPBIT_PISTOL:
				{
					Client_GiveWeapon(iClient, "weapon_pistol", false);
				}
				case WEPBIT_MAGNUM:
				{
					Client_GiveWeapon(iClient, "weapon_357", false);
				}
				case WEPBIT_SMG:
				{
					Client_GiveWeapon(iClient, "weapon_smg1", false);
				}
				case WEPBIT_AR2:
				{
					Client_GiveWeapon(iClient, "weapon_ar2", false);
				}
				case WEPBIT_SHOTGUN:
				{
					Client_GiveWeapon(iClient, "weapon_shotgun", false);
				}
				case WEPBIT_CROSSBOW:
				{
					Client_GiveWeapon(iClient, "weapon_crossbow", false);
				}
				case WEPBIT_GRENADE:
				{
					Client_GiveWeapon(iClient, "weapon_frag", false);
				}
				case WEPBIT_RPG:
				{
					Client_GiveWeapon(iClient, "weapon_rpg", false);
				}
				case WEPBIT_SLAM:
				{
					Client_GiveWeapon(iClient, "weapon_slam", false);
				}
				case WEPBIT_UNKNOWN:
				{
					Client_GiveWeapon(iClient, "weapon_smg1", false);
				}
			}
			
			g_bTouched[iClient] = true;
		}
	}
}

public int Native_GetTriggerLink(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1);
	
	return (iEntity > 0 && iEntity <= MAXENTITIES && g_bHasLink[iEntity]) ? g_iLinkedEntity[iEntity] : -1;
}

public int Native_SetTriggerLink(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1), iTarget = GetNativeCell(2);
	
	g_iLinkedEntity[iEntity] = iTarget;
	g_bHasLink[iEntity] = (iTarget != -1);
	
	return true;
}

//Passcode buttons: the owner sets one with !setpass while looking at the button; anyone else pressing it is asked for
//it, and types !pass <passcode> to use it. The passcode is saved with the build.

public void OnEntityDestroyed(int iEntity)
{
	if (iEntity > 0 && iEntity <= MAXENTITIES)
	{
		g_sPasscode[iEntity][0] = '\0';
		g_iAnimMask[iEntity] = 0;
		g_fAnimStart[iEntity] = 0.0;
		g_bAnimBackward[iEntity] = false;
	}
}

//Animation:
public Action Command_Animate(int iClient, int iArgs)
{
	char sArg[16], sValue[16];
	
	int iProp = Cel_GetClientAimTarget(iClient);
	
	if (iProp == -1 || iProp > MAXENTITIES)
	{
		Cel_NotLooking(iClient);
		return Plugin_Handled;
	}
	
	if (!Cel_CheckOwner(iClient, iProp))
	{
		Cel_NotYours(iClient, iProp);
		return Plugin_Handled;
	}
	
	EntityType etType = Cel_GetEntityType(iProp);
	
	if (etType != ENTTYPE_PHYSICS && etType != ENTTYPE_DYNAMIC && etType != ENTTYPE_UNKNOWN && etType != ENTTYPE_CYCLER)
	{
		Cel_ReplyToCommand(iClient, "Only props can be animated.");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sArg, sizeof(sArg));
	GetCmdArg(2, sValue, sizeof(sValue));
	
	if (iArgs < 1)
	{
		ReplyAnimFrames(iClient, iProp);
		Cel_ReplyToCommand(iClient, "Move, turn, color, fade ({green}!alpha{default}) or reskin the prop, then {green}!animate <1-10>{default} to save it as that frame. {green}!link{default} a button to it to play them. Also: {green}!animate speed <seconds>{default}, {green}play{default}, {green}clear{default}.");
		return Plugin_Handled;
	}
	
	if (StrEqual(sArg, "clear", false))
	{
		g_iAnimMask[iProp] = 0;
		g_fAnimStart[iProp] = 0.0;
		Cel_ReplyToCommand(iClient, "The prop's animation frames are cleared.");
		return Plugin_Handled;
	}
	
	if (StrEqual(sArg, "speed", false))
	{
		float fStep = StringToFloat(sValue);
		
		if (fStep < 0.1 || fStep > 10.0)
		{
			Cel_ReplyToCommand(iClient, "Give the seconds each frame takes, from {green}0.1{default} to {green}10{default}: {green}!animate speed 0.5{default}");
			return Plugin_Handled;
		}
		
		g_fAnimStep[iProp] = fStep;
		Cel_ReplyToCommand(iClient, "Each frame now takes {green}%.1f{default} seconds.", fStep);
		return Plugin_Handled;
	}
	
	if (StrEqual(sArg, "play", false))
	{
		if (!PlayAnimation(iProp))
		{
			Cel_ReplyToCommand(iClient, "Save at least two frames first with {green}!animate <1-10>{default}.");
		}
		
		return Plugin_Handled;
	}
	
	int iFrame = StringToInt(sArg);
	
	if (iFrame < 1 || iFrame > ANIM_FRAMES)
	{
		Cel_ReplyToCommand(iClient, "Frames are numbered {green}1{default} to {green}%d{default}: {green}!animate 1{default}", ANIM_FRAMES);
		return Plugin_Handled;
	}
	
	if (g_fAnimStart[iProp] > 0.0)
	{
		Cel_ReplyToCommand(iClient, "Wait for the animation to finish first.");
		return Plugin_Handled;
	}
	
	GetEntPropVector(iProp, Prop_Data, "m_vecAbsOrigin", g_fAnimPos[iProp][iFrame - 1]);
	GetEntPropVector(iProp, Prop_Data, "m_angAbsRotation", g_fAnimAng[iProp][iFrame - 1]);
	
	//The look is part of the frame too: color, opacity (!alpha), skin and render effect.
	Cel_GetColor(iProp, g_iAnimColor[iProp][iFrame - 1]);
	g_iAnimSkin[iProp][iFrame - 1] = GetEntProp(iProp, Prop_Send, "m_nSkin");
	g_iAnimFx[iProp][iFrame - 1] = view_as<int>(Cel_GetRenderFX(iProp));
	
	if (g_iAnimMask[iProp] == 0)
	{
		g_fAnimStep[iProp] = 0.5;
		g_bAnimBackward[iProp] = false;
	}
	
	g_iAnimMask[iProp] |= (1 << (iFrame - 1));
	
	Cel_ReplyToCommand(iClient, "Saved frame {green}%d{default}.", iFrame);
	ReplyAnimFrames(iClient, iProp);
	
	return Plugin_Handled;
}

void ReplyAnimFrames(int iClient, int iProp)
{
	char sList[64] = "";
	
	for (int f = 0; f < ANIM_FRAMES; f++)
	{
		if (g_iAnimMask[iProp] & (1 << f))
		{
			Format(sList, sizeof(sList), "%s%s%d", sList, sList[0] != '\0' ? ", " : "", f + 1);
		}
	}
	
	if (sList[0] == '\0')
	{
		Cel_ReplyToCommand(iClient, "This prop has no animation frames yet.");
	} else {
		Cel_ReplyToCommand(iClient, "Frames: {green}%s{default} (%.1f seconds each).", sList, g_fAnimStep[iProp]);
	}
}

int AnimFrameCount(int iProp)
{
	int iCount = 0;
	
	for (int f = 0; f < ANIM_FRAMES; f++)
	{
		if (g_iAnimMask[iProp] & (1 << f))
		{
			iCount++;
		}
	}
	
	return iCount;
}

//Plays the frames in order (or back, every other time). False when there's nothing to play.
bool PlayAnimation(int iProp)
{
	if (iProp <= MaxClients || iProp > MAXENTITIES || !IsValidEntity(iProp) || AnimFrameCount(iProp) < 2 || g_fAnimStart[iProp] > 0.0)
	{
		return false;
	}
	
	g_bAnimPlayingBack[iProp] = g_bAnimBackward[iProp];
	g_bAnimBackward[iProp] = !g_bAnimBackward[iProp];
	g_fAnimStart[iProp] = GetGameTime();
	
	return true;
}

//The n-th set frame, counting in play order.
int NthFrame(int iProp, int n, bool bBack)
{
	int iSeen = 0;
	
	for (int k = 0; k < ANIM_FRAMES; k++)
	{
		int f = bBack ? (ANIM_FRAMES - 1 - k) : k;
		
		if (g_iAnimMask[iProp] & (1 << f))
		{
			if (iSeen == n)
			{
				return f;
			}
			
			iSeen++;
		}
	}
	
	return -1;
}

float AngleLerp(float a, float b, float t)
{
	float d = b - a;
	
	while (d > 180.0) d -= 360.0;
	while (d < -180.0) d += 360.0;
	
	return a + d * t;
}

public void OnGameFrame()
{
	float fNow = GetGameTime(), fPos[3], fAng[3];
	
	for (int i = MaxClients + 1; i <= MAXENTITIES; i++)
	{
		if (g_fAnimStart[i] <= 0.0)
		{
			continue;
		}
		
		if (!IsValidEntity(i))
		{
			g_fAnimStart[i] = 0.0;
			continue;
		}
		
		int iSegments = AnimFrameCount(i) - 1;
		float fT = (fNow - g_fAnimStart[i]) / g_fAnimStep[i];
		
		if (fT >= float(iSegments))
		{
			int iLast = NthFrame(i, iSegments, g_bAnimPlayingBack[i]);
			
			TeleportEntity(i, g_fAnimPos[i][iLast], g_fAnimAng[i][iLast], NULL_VECTOR);
			
			//The last frame's look is kept (saved with the prop, like a !color would be).
			if (!Cel_IsRainbow(i))
			{
				Cel_SetColor(i, g_iAnimColor[i][iLast][0], g_iAnimColor[i][iLast][1], g_iAnimColor[i][iLast][2], g_iAnimColor[i][iLast][3]);
			}
			
			SetEntProp(i, Prop_Send, "m_nSkin", g_iAnimSkin[i][iLast]);
			Cel_SetRenderFX(i, view_as<RenderFx>(g_iAnimFx[i][iLast]));
			
			g_fAnimStart[i] = 0.0;
			continue;
		}
		
		int iSeg = RoundToFloor(fT);
		float fF = fT - float(iSeg);
		
		// Eased, so each frame starts and stops smoothly.
		fF = fF * fF * (3.0 - 2.0 * fF);
		
		int a = NthFrame(i, iSeg, g_bAnimPlayingBack[i]), b = NthFrame(i, iSeg + 1, g_bAnimPlayingBack[i]);
		
		for (int k = 0; k < 3; k++)
		{
			fPos[k] = g_fAnimPos[i][a][k] + (g_fAnimPos[i][b][k] - g_fAnimPos[i][a][k]) * fF;
			fAng[k] = AngleLerp(g_fAnimAng[i][a][k], g_fAnimAng[i][b][k], fF);
		}
		
		TeleportEntity(i, fPos, fAng, NULL_VECTOR);
		
		//Color and opacity blend; skin and render effect change halfway. A rainbow prop keeps cycling its own colors.
		if (!Cel_IsRainbow(i))
		{
			int iColor[4];
			
			for (int k = 0; k < 4; k++)
			{
				iColor[k] = RoundToNearest(float(g_iAnimColor[i][a][k]) + float(g_iAnimColor[i][b][k] - g_iAnimColor[i][a][k]) * fF);
			}
			
			SetEntityRenderMode(i, (iColor[3] < 255 || g_iAnimColor[i][a][3] < 255 || g_iAnimColor[i][b][3] < 255) ? RENDER_TRANSCOLOR : RENDER_NORMAL);
			SetEntityRenderColor(i, iColor[0], iColor[1], iColor[2], iColor[3]);
		}
		
		int iHalf = (fF < 0.5) ? a : b;
		
		if (GetEntProp(i, Prop_Send, "m_nSkin") != g_iAnimSkin[i][iHalf])
		{
			SetEntProp(i, Prop_Send, "m_nSkin", g_iAnimSkin[i][iHalf]);
		}
		
		if (view_as<int>(GetEntityRenderFx(i)) != g_iAnimFx[i][iHalf])
		{
			SetEntityRenderFx(i, view_as<RenderFx>(g_iAnimFx[i][iHalf]));
		}
	}
}

bool IsButton(int iEntity)
{
	return iEntity > MaxClients && iEntity <= MAXENTITIES && IsValidEntity(iEntity) && Cel_IsEntity(iEntity) && Cel_GetEntityType(iEntity) == ENTTYPE_TRIGGER;
}

public Action Command_SetPass(int iClient, int iArgs)
{
	char sCode[32];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	int iButton = Cel_GetClientAimTarget(iClient);
	
	if (!IsButton(iButton))
	{
		Cel_ReplyToCommand(iClient, "Look at one of your buttons (from {green}[tag]button{default}) first.");
		return Plugin_Handled;
	}
	
	if (!Cel_CheckOwner(iClient, iButton))
	{
		Cel_ReplyToCommand(iClient, "That button isn't yours.");
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]setpass{default} <passcode>, or {green}[tag]setpass off{default} to remove it.");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sCode, sizeof(sCode));
	
	if (StrEqual(sCode, "off", false) || StrEqual(sCode, "none", false))
	{
		g_sPasscode[iButton][0] = '\0';
		Cel_ReplyToCommand(iClient, "That button no longer needs a passcode.");
		return Plugin_Handled;
	}
	
	strcopy(g_sPasscode[iButton], sizeof(g_sPasscode[]), sCode);
	
	Cel_ReplyToCommand(iClient, "That button now needs the passcode {green}%s{default}. You can still press it yourself.", sCode);
	
	return Plugin_Handled;
}

public Action Command_Pass(int iClient, int iArgs)
{
	char sCode[32];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]pass{default} <passcode>, for the passcode button you pressed (or are looking at).");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sCode, sizeof(sCode));
	
	// The button they're looking at, or else the last passcode button they pressed.
	int iButton = Cel_GetClientAimTarget(iClient);
	
	if (!IsButton(iButton) || g_sPasscode[iButton][0] == '\0')
	{
		iButton = EntRefToEntIndex(g_iPassButton[iClient]);
	}
	
	if (iButton == INVALID_ENT_REFERENCE || !IsButton(iButton) || g_sPasscode[iButton][0] == '\0')
	{
		Cel_ReplyToCommand(iClient, "Press the passcode button first (or look at it), then type {green}[tag]pass{default} and the passcode.");
		return Plugin_Handled;
	}
	
	if (!StrEqual(sCode, g_sPasscode[iButton]))
	{
		PrecacheSound("buttons/combine_button_locked.wav");
		EmitSoundToClient(iClient, "buttons/combine_button_locked.wav", iButton);
		
		Cel_ReplyToCommand(iClient, "Wrong passcode.");
		return Plugin_Handled;
	}
	
	Cel_ReplyToCommand(iClient, "Passcode accepted.");
	
	PressButton(iButton, iClient);
	
	return Plugin_Handled;
}

public void Cel_OnSaveEntity(int iEntity, KeyValues kvSave)
{
	if (iEntity > 0 && iEntity <= MAXENTITIES && g_sPasscode[iEntity][0] != '\0')
	{
		kvSave.SetString("x_passcode", g_sPasscode[iEntity]);
	}
	
	//Animation frames, as offsets from the prop, so they follow the build wherever it's loaded.
	if (iEntity > MaxClients && iEntity <= MAXENTITIES && g_iAnimMask[iEntity] != 0)
	{
		char sKey[16], sValue[128];
		float fOrigin[3];
		
		GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", fOrigin);
		
		kvSave.SetNum("x_animmask", g_iAnimMask[iEntity]);
		kvSave.SetFloat("x_animstep", g_fAnimStep[iEntity]);
		
		for (int f = 0; f < ANIM_FRAMES; f++)
		{
			if (g_iAnimMask[iEntity] & (1 << f))
			{
				FormatEx(sKey, sizeof(sKey), "x_anim%d", f + 1);
				FormatEx(sValue, sizeof(sValue), "%.2f %.2f %.2f %.2f %.2f %.2f %d %d %d %d %d %d", g_fAnimPos[iEntity][f][0] - fOrigin[0], g_fAnimPos[iEntity][f][1] - fOrigin[1], g_fAnimPos[iEntity][f][2] - fOrigin[2], g_fAnimAng[iEntity][f][0], g_fAnimAng[iEntity][f][1], g_fAnimAng[iEntity][f][2],
					g_iAnimColor[iEntity][f][0], g_iAnimColor[iEntity][f][1], g_iAnimColor[iEntity][f][2], g_iAnimColor[iEntity][f][3], g_iAnimSkin[iEntity][f], g_iAnimFx[iEntity][f]);
				kvSave.SetString(sKey, sValue);
			}
		}
	}
}

public void Cel_OnLoadEntity(int iClient, int iEntity, KeyValues kvSave)
{
	if (iEntity > 0 && iEntity <= MAXENTITIES)
	{
		kvSave.GetString("x_passcode", g_sPasscode[iEntity], sizeof(g_sPasscode[]), "");
		
		g_iAnimMask[iEntity] = kvSave.GetNum("x_animmask", 0);
		g_fAnimStep[iEntity] = kvSave.GetFloat("x_animstep", 0.5);
		g_bAnimBackward[iEntity] = false;
		g_fAnimStart[iEntity] = 0.0;
		
		if (g_iAnimMask[iEntity] != 0)
		{
			char sKey[16], sValue[160], sParts[12][16];
			int iSaved[4];
			
			//Frames saved before the look was part of them use the prop's look as it loaded.
			Cel_GetColor(iEntity, iSaved);
			float fOrigin[3];
			
			GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", fOrigin);
			
			for (int f = 0; f < ANIM_FRAMES; f++)
			{
				if (!(g_iAnimMask[iEntity] & (1 << f)))
				{
					continue;
				}
				
				FormatEx(sKey, sizeof(sKey), "x_anim%d", f + 1);
				kvSave.GetString(sKey, sValue, sizeof(sValue), "");
				
				int iParts = ExplodeString(sValue, " ", sParts, sizeof(sParts), sizeof(sParts[]));
				
				if (iParts < 6)
				{
					g_iAnimMask[iEntity] &= ~(1 << f);
					continue;
				}
				
				for (int k = 0; k < 3; k++)
				{
					g_fAnimPos[iEntity][f][k] = fOrigin[k] + StringToFloat(sParts[k]);
					g_fAnimAng[iEntity][f][k] = StringToFloat(sParts[k + 3]);
				}
				
				if (iParts >= 12)
				{
					for (int k = 0; k < 4; k++)
					{
						g_iAnimColor[iEntity][f][k] = StringToInt(sParts[6 + k]);
					}
					
					g_iAnimSkin[iEntity][f] = StringToInt(sParts[10]);
					g_iAnimFx[iEntity][f] = StringToInt(sParts[11]);
				} else {
					g_iAnimColor[iEntity][f] = iSaved;
					g_iAnimSkin[iEntity][f] = GetEntProp(iEntity, Prop_Send, "m_nSkin");
					g_iAnimFx[iEntity][f] = view_as<int>(Cel_GetRenderFX(iEntity));
				}
			}
		}
	}
}

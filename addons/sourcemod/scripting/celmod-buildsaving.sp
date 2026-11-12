#pragma semicolon 1

#include <celmod>

#pragma newdecls required

bool g_bLate;

float g_fCrosshairOrigin[MAXPLAYERS + 1][3];

Handle g_hOnBuildLoaded;
Handle g_hOnLoadEntity;
Handle g_hOnSaveEntity;

int g_iSaveOverride[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	CreateNative("Cel_LoadBuild", Native_LoadBuild);
	CreateNative("Cel_SaveBuild", Native_SaveBuild);
	
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "|CelMod| Build Saving System",
	author = CEL_AUTHOR,
	description = "Handles saving/loading of client buildings.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	LoadTranslations("celmod.phrases");
	
	g_hOnBuildLoaded = CreateGlobalForward("Cel_OnBuildLoaded", ET_Ignore, Param_Cell, Param_String);
	g_hOnLoadEntity = CreateGlobalForward("Cel_OnLoadEntity", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	g_hOnSaveEntity = CreateGlobalForward("Cel_OnSaveEntity", ET_Ignore, Param_Cell, Param_Cell);
	
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
	
	RegConsoleCmd("v_load", Command_LoadBuild, "|CelMod| Loads entities from a save file.");
	RegConsoleCmd("v_save", Command_SaveBuild, "|CelMod| Saves all server entities that are in your land.");
}

public void OnClientPutInServer(int iClient)
{
	char sAuthID[64], sPath[PLATFORM_MAX_PATH];
	
	Cel_ChooseHudColor(iClient);
	
	Cel_GetAuthID(iClient, sAuthID, sizeof(sAuthID));
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod/users/%s/saves", sAuthID);
	if (!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}
}

//Finds the client's Steam id and makes sure their save folder exists. Returns false if the id is not known yet.
bool Cel_PrepareSaveFolder(int iClient, char[] sAuthID, int iMaxLength)
{
	char sPath[PLATFORM_MAX_PATH];
	
	Cel_GetAuthID(iClient, sAuthID, iMaxLength);
	
	//The stored id is empty when Steam had not confirmed the player when they joined.
	if (sAuthID[0] == '\0' && !GetClientAuthId(iClient, AuthId_SteamID64, sAuthID, iMaxLength, false))
	{
		sAuthID[0] = '\0';
	}
	
	if (sAuthID[0] == '\0')
	{
		return false;
	}
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod/users");
	if (!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod/users/%s", sAuthID);
	if (!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/celmod/users/%s/saves", sAuthID);
	if (!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}
	
	return DirExists(sPath);
}

//Works out the client's land: the middle of its floor (what saved positions are measured from), half its width
//and depth, and its height. Returns false if the client has no land.
bool Cel_GetLandLayout(int iClient, float fMiddle[3], float fHalfSize[2], float &fHeight)
{
	float fBottom[3], fCorner[2][3], fTop[3];
	
	if (!Cel_IsLandCreated(iClient))
	{
		return false;
	}
	
	Cel_GetLandPositions(iClient, 1, fCorner[0]);
	Cel_GetLandPositions(iClient, 4, fCorner[1]);
	
	Cel_GetMiddleOfABox(fCorner[0], fCorner[1], fMiddle);
	
	fMiddle[2] = fCorner[0][2];
	
	Cel_GetLandPositions(iClient, 2, fBottom);
	Cel_GetLandPositions(iClient, 3, fTop);
	
	fHalfSize[0] = FloatAbs(fTop[0] - fBottom[0]) / 2.0;
	fHalfSize[1] = FloatAbs(fTop[1] - fBottom[1]) / 2.0;
	fHeight = FloatAbs(fTop[2] - fBottom[2]);
	
	return true;
}

//An entity belongs to a build when its origin is inside its owner's own land.
bool Cel_IsEntityInOwnLand(int iClient, int iEntity)
{
	float fHalfSize[2], fHeight, fMiddle[3], fOrigin[3];
	
	if (!Cel_GetLandLayout(iClient, fMiddle, fHalfSize, fHeight))
	{
		return false;
	}
	
	Cel_GetEntityOrigin(iEntity, fOrigin);
	
	return (FloatAbs(fOrigin[0] - fMiddle[0]) <= fHalfSize[0] && FloatAbs(fOrigin[1] - fMiddle[1]) <= fHalfSize[1]
		&& fOrigin[2] >= fMiddle[2] - 64.0 && fOrigin[2] <= fMiddle[2] + fHeight);
}

public Action Command_LoadBuild(int iClient, int iArgs)
{
	char sSaveName[64];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CMD_LoadBuild");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sSaveName, sizeof(sSaveName));
	
	Cel_LoadBuild(iClient, sSaveName);
	
	return Plugin_Handled;
}

public Action Command_SaveBuild(int iClient, int iArgs)
{
	char sSaveName[64];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CMD_SaveBuild");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sSaveName, sizeof(sSaveName));
	
	Cel_SaveBuild(iClient, sSaveName);
	
	return Plugin_Handled;
}

public int Native_LoadBuild(Handle hPlugin, int iNumParams)
{
	char sAuthID[64], sBuffer[3][PLATFORM_MAX_PATH], sFile[PLATFORM_MAX_PATH], sPropName[64], sRelPath[PLATFORM_MAX_PATH], sSaveName[96];
	float fEnt[2][3], fOrigin[3];
	
	int iClient = GetNativeCell(1), iProp = -1;
	
	GetNativeString(2, sSaveName, sizeof(sSaveName));
	
	if (!Cel_PrepareSaveFolder(iClient, sAuthID, sizeof(sAuthID)))
	{
		Cel_ReplyToCommand(iClient, "Your builds cannot be reached right now: your Steam ID is not known to the server yet. Try again in a moment.");
		
		return false;
	}
	
	//Builds are placed around the middle of the player's own land, exactly as they were saved.
	float fHalfSize[2], fHeight, fNeeded[3];
	
	if (!Cel_GetLandLayout(iClient, g_fCrosshairOrigin[iClient], fHalfSize, fHeight))
	{
		Cel_ReplyToCommand(iClient, "You need a land to load a build into. Type {green}[tag]land{default} to create one.");
		
		return false;
	}
	
	Format(sRelPath, sizeof(sRelPath), "data/celmod/users/%s/saves/%s.txt", sAuthID, sSaveName);
	
	BuildPath(Path_SM, sFile, sizeof(sFile), sRelPath);
	
	KeyValues kvLoadBuild = new KeyValues("Vault");
	
	if(kvLoadBuild.ImportFromFile(sFile))
	{
		//First pass: how much room the build needs. Nothing is spawned unless all of it fits in the land.
		if (kvLoadBuild.GotoFirstSubKey())
		{
			do
			{
				if (FloatAbs(kvLoadBuild.GetFloat("o1")) > fNeeded[0]) fNeeded[0] = FloatAbs(kvLoadBuild.GetFloat("o1"));
				if (FloatAbs(kvLoadBuild.GetFloat("o2")) > fNeeded[1]) fNeeded[1] = FloatAbs(kvLoadBuild.GetFloat("o2"));
				if (kvLoadBuild.GetFloat("o3") > fNeeded[2]) fNeeded[2] = kvLoadBuild.GetFloat("o3");
			}
			while (kvLoadBuild.GotoNextKey());
			
			kvLoadBuild.Rewind();
		}
		
		if (fNeeded[0] > fHalfSize[0] + 1.0 || fNeeded[1] > fHalfSize[1] + 1.0 || fNeeded[2] > fHeight + 1.0)
		{
			kvLoadBuild.Close();
			
			Cel_ReplyToCommand(iClient, "The build {green}%s{default} does not fit in your land. It needs {green}%d x %d{default} units and {green}%d{default} high; your land is {green}%d x %d{default} and {green}%d{default} high.", sSaveName, RoundToCeil(fNeeded[0] * 2.0), RoundToCeil(fNeeded[1] * 2.0), RoundToCeil(fNeeded[2]), RoundToFloor(fHalfSize[0] * 2.0), RoundToFloor(fHalfSize[1] * 2.0), RoundToFloor(fHeight));
			
			return false;
		}
		
		if (kvLoadBuild.GotoFirstSubKey())
		{
			do
			{
				fEnt[0][0] = kvLoadBuild.GetFloat("a1");
				fEnt[0][1] = kvLoadBuild.GetFloat("a2");
				fEnt[0][2] = kvLoadBuild.GetFloat("a3");
				
				fEnt[1][0] = kvLoadBuild.GetFloat("o1");
				fEnt[1][1] = kvLoadBuild.GetFloat("o2");
				fEnt[1][2] = kvLoadBuild.GetFloat("o3");
				
				fOrigin[0] = fEnt[1][0] + g_fCrosshairOrigin[iClient][0];
				fOrigin[1] = fEnt[1][1] + g_fCrosshairOrigin[iClient][1];
				fOrigin[2] = fEnt[1][2] + g_fCrosshairOrigin[iClient][2];
				
				kvLoadBuild.GetString("classname", sBuffer[0], sizeof(sBuffer[]));
				kvLoadBuild.GetString("targetname", sBuffer[1], sizeof(sBuffer[]));
				kvLoadBuild.GetString("model", sBuffer[2], sizeof(sBuffer[]));
				
				EntityType etType = view_as<EntityType>(kvLoadBuild.GetNum("entitytype"));
				
				//Entity types that cannot be loaded are skipped instead of re-using the previous entity.
				iProp = -1;
				
				switch(etType)
				{
					case ENTTYPE_CYCLER:
					{
						kvLoadBuild.GetString("propname", sPropName, sizeof(sPropName));
						
						iProp = Cel_SpawnProp(iClient, sPropName, "cycler", sBuffer[2], fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
						
						Entity_SetAnimSequence(iProp, kvLoadBuild.GetNum("animsequence"));
					}
					case ENTTYPE_DOOR:
					{
						iProp = Cel_SpawnDoor(iClient, 1, fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
					}
					case ENTTYPE_DYNAMIC:
					{
						kvLoadBuild.GetString("propname", sPropName, sizeof(sPropName));
						
						iProp = Cel_SpawnProp(iClient, sPropName, "prop_physics_override", sBuffer[2], fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
					}
					case ENTTYPE_EFFECT:
					{
						iProp = Cel_SpawnEffect(iClient, fOrigin, view_as<EffectType>(kvLoadBuild.GetNum("effecttype")), view_as<bool>(kvLoadBuild.GetNum("effectenabled")), kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
					}
					case ENTTYPE_INTERNET:
					{
						char sURL[PLATFORM_MAX_PATH];
						
						kvLoadBuild.GetString("interneturl", sURL, sizeof(sURL));
						
						iProp = Cel_SpawnInternet(iClient, sURL, fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
					}
					case ENTTYPE_LADDER:
					{
						iProp = Cel_SpawnLadder(iClient, sBuffer[2], fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
					}
					case ENTTYPE_LIGHT:
					{
						iProp = Cel_SpawnLight(iClient, fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
					}
					case ENTTYPE_PHYSICS:
					{
						kvLoadBuild.GetString("propname", sPropName, sizeof(sPropName));
						
						iProp = Cel_SpawnProp(iClient, sPropName, "prop_physics_override", sBuffer[2], fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
						
						Cel_SetBreakable(iProp, view_as<bool>(kvLoadBuild.GetNum("breakable")));
					}
					case ENTTYPE_AMMO:
					{
						iProp = Cel_SpawnAmmoBit(iClient, view_as<AmmoBitType>(kvLoadBuild.GetNum("ammobittype")), fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
					}
					case ENTTYPE_AMMOCRATE:
					{
						iProp = Cel_SpawnAmmoCrate(iClient, view_as<AmmoCrateType>(kvLoadBuild.GetNum("ammocratetype")), fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
					}
					case ENTTYPE_CHARGER:
					{
						iProp = Cel_SpawnCharger(iClient, view_as<ChargerType>(kvLoadBuild.GetNum("chargertype")), fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
					}
					case ENTTYPE_WEAPONSPWNER:
					{
						iProp = Cel_SpawnWeaponBit(iClient, view_as<WeaponBitType>(kvLoadBuild.GetNum("weaponbittype")), fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
					}
					case ENTTYPE_TRIGGER:
					{
						iProp = Cel_SpawnButton(iClient, fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
					}
					case ENTTYPE_EMBLEM, ENTTYPE_HAT, ENTTYPE_CELWEP:
					{
						char sItemId[64];
						
						kvLoadBuild.GetString("itemid", sItemId, sizeof(sItemId));
						
						//Returns -1 when the player no longer owns the item, or it is already spawned.
						iProp = Cel_SpawnCollectible(iClient, etType == ENTTYPE_EMBLEM ? "emblem" : (etType == ENTTYPE_HAT ? "hat" : "weapon"), sItemId, fEnt[0], fOrigin);
					}
					case ENTTYPE_UNKNOWN:
					{
						kvLoadBuild.GetString("propname", sPropName, sizeof(sPropName));
						
						iProp = Cel_SpawnProp(iClient, sPropName, "prop_physics_override", sBuffer[2], fEnt[0], fOrigin, kvLoadBuild.GetNum("c1"), kvLoadBuild.GetNum("c2"), kvLoadBuild.GetNum("c3"), kvLoadBuild.GetNum("c4"));
					}
				}
				
				if (iProp == -1 || !IsValidEntity(iProp))
				{
					continue;
				}
				
				Entity_SetName(iProp, sBuffer[1]);
				Cel_SetEntity(iProp, true);
				Entity_SetSpawnFlags(iProp, kvLoadBuild.GetNum("spawnflags"));
				Entity_SetSkin(iProp, kvLoadBuild.GetNum("skin"));
				Cel_SetMotion(iProp, view_as<bool>(kvLoadBuild.GetNum("motion")));
				Cel_SetSolid(iProp, view_as<bool>(kvLoadBuild.GetNum("solid")));
				Cel_SetRenderFX(iProp, view_as<RenderFx>(kvLoadBuild.GetNum("renderfx")));
				Cel_SetOwner(iClient, iProp);
				
				Cel_SetColorFade(iProp, view_as<bool>(kvLoadBuild.GetNum("colorfading")), kvLoadBuild.GetNum("fc1-1"), kvLoadBuild.GetNum("fc1-2"), kvLoadBuild.GetNum("fc1-3"), kvLoadBuild.GetNum("fc2-1"), kvLoadBuild.GetNum("fc2-2"), kvLoadBuild.GetNum("fc2-3"));
				Cel_SetRainbow(iProp, view_as<bool>(kvLoadBuild.GetNum("colorrainbow")));
				
				//Other plugins restore what they stored with this entity (teleports, messages, sounds, links, welds).
				Call_StartForward(g_hOnLoadEntity);
				
				Call_PushCell(iClient);
				Call_PushCell(iProp);
				Call_PushCell(kvLoadBuild);
				
				Call_Finish();
			}
			
			while (kvLoadBuild.GotoNextKey());
		}
		
		if(!kvLoadBuild.GotoNextKey())
		{
			kvLoadBuild.Close();	
		}
		
		iProp = -1;
		
		Cel_ReplyToCommand(iClient, "%t", "LoadedBuild", sSaveName);
		
		Call_StartForward(g_hOnBuildLoaded);
		
		Call_PushCell(iClient);
		Call_PushString(sSaveName);
		
		Call_Finish();
		
		return true;
	}else{
		kvLoadBuild.Close();
		
		Cel_ReplyToCommand(iClient, "%t", "SaveDoesntExist", sSaveName);
		
		return false;
	}
}

//Natives:
public int Native_SaveBuild(Handle hPlugin, int iNumParams)
{
	bool bPropOutside = false;
	char sAuthID[64], sBuffer[3][PLATFORM_MAX_PATH], sFile[2][PLATFORM_MAX_PATH], sPropName[64], sRelPath[PLATFORM_MAX_PATH], sSaveName[96], sCount[32];
	float fEnt[2][3], fLandPos[2][3], fMiddle[3], fOrigin[3];
	int iClient = GetNativeCell(1), iColor[4], iCount = 0, iFadeColor[2][3], iLand;
	
	GetNativeString(2, sSaveName, sizeof(sSaveName));
	
	Cel_GetLandPositions(iClient, 1, fLandPos[0]);
	Cel_GetLandPositions(iClient, 4, fLandPos[1]);
	
	if(fLandPos[0][0] == 0.0 && fLandPos[0][1] == 0.0 && fLandPos[0][2] == 0.0 && fLandPos[1][0] == 0.0 && fLandPos[1][1] == 0.0 && fLandPos[1][2] == 0.0)
	{
		Cel_ReplyToCommand(iClient, "%t", "PropsWontSave");
		Cel_ReplyToCommand(iClient, "%t", "SetUpLandArea");
		
		return false;
	}
	
	if (!Cel_PrepareSaveFolder(iClient, sAuthID, sizeof(sAuthID)))
	{
		Cel_ReplyToCommand(iClient, "Your build cannot be saved right now: your Steam ID is not known to the server yet. Try again in a moment.");
		
		return false;
	}
	
	Format(sRelPath, sizeof(sRelPath), "data/celmod/users/%s/saves/%s.txt", sAuthID, sSaveName);
	
	BuildPath(Path_SM, sFile[0], sizeof(sFile[]), sRelPath);
	
	if (FileExists(sFile[0]))
	{
		switch(g_iSaveOverride[iClient])
		{
			case 0:
			{
				Cel_ReplyToCommand(iClient, "%t", "SaveOverriteWarning", sSaveName);
				Cel_ReplyToCommand(iClient, "%t", "SaveOverriteConfirm", sSaveName);
				
				g_iSaveOverride[iClient] = 1;
				
				return false;
			}
			
			case 1:
			{
				DeleteFile(sFile[0]);
				
				BuildPath(Path_SM, sFile[0], sizeof(sFile[]), sRelPath);
				
				g_iSaveOverride[iClient] = 0;
			}
		}
	}
	
	Cel_GetMiddleOfABox(fLandPos[0], fLandPos[1], fMiddle);
	
	fMiddle[2] = (fLandPos[0][2]);
	
	KeyValues kvSaveBuild = new KeyValues("Vault");
	
	kvSaveBuild.ImportFromFile(sFile[0]);
	
	for (int i = 0; i < GetMaxEntities(); i++)
	{
		if (Cel_CheckOwner(iClient, i))
		{
			if(Cel_IsEntityInOwnLand(iClient, i))
			{
				iLand = iClient;
				
				if(iLand == iClient)
				{
					iCount++;
					
					IntToString(iCount, sCount, sizeof(sCount));
					
					Entity_GetRenderColor(i, iColor);
					Cel_GetFadeColor(i, iFadeColor[0], iFadeColor[1]);
					
					Entity_GetClassName(i, sBuffer[0], sizeof(sBuffer[]));
					Entity_GetName(i, sBuffer[1], sizeof(sBuffer[]));
					Entity_GetModel(i, sBuffer[2], sizeof(sBuffer[]));
					
					Cel_GetEntityAngles(i, fEnt[0]);
					
					Cel_GetEntityOrigin(i, fEnt[1]);
					
					fOrigin[0] = fEnt[1][0] - fMiddle[0];
					fOrigin[1] = fEnt[1][1] - fMiddle[1];
					fOrigin[2] = fEnt[1][2] - fMiddle[2];
					
					kvSaveBuild.JumpToKey(sCount, true);
					
					kvSaveBuild.SetNum("entitytype", view_as<int>(Cel_GetEntityType(i)));
					
					kvSaveBuild.SetString("classname", sBuffer[0]);
					kvSaveBuild.SetString("targetname", sBuffer[1]);
					kvSaveBuild.SetString("model", sBuffer[2]);
					
					kvSaveBuild.SetNum("spawnflags", Entity_GetSpawnFlags(i));
					kvSaveBuild.SetNum("skin", Entity_GetSkin(i));
					kvSaveBuild.SetNum("motion", view_as<int>(Cel_GetMotion(i)));
					kvSaveBuild.SetNum("renderfx", view_as<int>(Cel_GetRenderFX(i)));
					kvSaveBuild.SetNum("solid", view_as<int>(Cel_IsSolid(i)));
					
					kvSaveBuild.SetNum("c1", iColor[0]);
					kvSaveBuild.SetNum("c2", iColor[1]);
					kvSaveBuild.SetNum("c3", iColor[2]);
					kvSaveBuild.SetNum("c4", iColor[3]);
					
					kvSaveBuild.SetFloat("a1", fEnt[0][0]);
					kvSaveBuild.SetFloat("a2", fEnt[0][1]);
					kvSaveBuild.SetFloat("a3", fEnt[0][2]);
					
					kvSaveBuild.SetFloat("o1", fOrigin[0]);
					kvSaveBuild.SetFloat("o2", fOrigin[1]);
					kvSaveBuild.SetFloat("o3", fOrigin[2]);
					
					kvSaveBuild.SetNum("fc1-1", iFadeColor[0][0]);
					kvSaveBuild.SetNum("fc1-2", iFadeColor[0][1]);
					kvSaveBuild.SetNum("fc1-3", iFadeColor[0][2]);
					kvSaveBuild.SetNum("fc2-1", iFadeColor[1][0]);
					kvSaveBuild.SetNum("fc2-2", iFadeColor[1][1]);
					kvSaveBuild.SetNum("fc2-3", iFadeColor[1][2]);
					
					kvSaveBuild.SetNum("colorfading", view_as<int>(Cel_IsFading(i)));
					kvSaveBuild.SetNum("colorrainbow", view_as<int>(Cel_IsRainbow(i)));
					
					switch(Cel_GetEntityType(i))
					{
						case ENTTYPE_CYCLER:
						{
							Cel_GetPropName(i, sPropName, sizeof(sPropName));
							
							kvSaveBuild.SetString("propname", sPropName);
							
							kvSaveBuild.SetNum("animsequence", Entity_GetAnimSequence(i));
						}
						case ENTTYPE_DOOR:
						{
							fOrigin[2] -= 54;
							
							kvSaveBuild.SetFloat("o3", fOrigin[2]);
						}
						case ENTTYPE_DYNAMIC:
						{
							Cel_GetPropName(i, sPropName, sizeof(sPropName));
							
							kvSaveBuild.SetString("propname", sPropName);
						}
						case ENTTYPE_EFFECT:
						{
							kvSaveBuild.SetNum("effecttype", view_as<int>(Cel_GetEffectType(i)));
							kvSaveBuild.SetNum("effectenabled", view_as<int>(Cel_IsEffectActive(i)));
						}
						case ENTTYPE_INTERNET:
						{
							char sURL[PLATFORM_MAX_PATH];
							
							Cel_GetInternetURL(i, sURL, sizeof(sURL));
							
							kvSaveBuild.SetString("interneturl", sURL);
						}
						case ENTTYPE_PHYSICS:
						{
							Cel_GetPropName(i, sPropName, sizeof(sPropName));
							
							kvSaveBuild.SetString("propname", sPropName);
							kvSaveBuild.SetNum("breakable", view_as<int>(Cel_IsBreakable(i)));
						}
						case ENTTYPE_AMMO:
						{
							fEnt[0][1] -= 90;
							
							kvSaveBuild.SetFloat("a2", fEnt[0][1]);
							
							kvSaveBuild.SetNum("ammobittype", Cel_GetAmmoType(i));
						}
						case ENTTYPE_AMMOCRATE:
						{
							fEnt[0][1] -= 180;
							
							kvSaveBuild.SetFloat("a2", fEnt[0][1]);
							
							kvSaveBuild.SetNum("ammocratetype", Cel_GetAmmoCrateType(i));
						}
						case ENTTYPE_CHARGER:
						{
							fEnt[0][1] -= 180;
							
							kvSaveBuild.SetFloat("a2", fEnt[0][1]);
							
							kvSaveBuild.SetNum("chargertype", Cel_GetChargerType(i));
						}
						case ENTTYPE_WEAPONSPWNER:
						{
							fEnt[0][1] -= 90;
							
							kvSaveBuild.SetFloat("a2", fEnt[0][1]);
							
							kvSaveBuild.SetNum("weaponbittype", Cel_GetWeaponType(i));
						}
						case ENTTYPE_EMBLEM, ENTTYPE_HAT, ENTTYPE_CELWEP:
						{
							char sItemId[64];
							
							Cel_GetCollectibleId(i, sItemId, sizeof(sItemId));
							
							kvSaveBuild.SetString("itemid", sItemId);
						}
					}
					
					//Other plugins add what they need to rebuild this entity.
					Call_StartForward(g_hOnSaveEntity);
					
					Call_PushCell(i);
					Call_PushCell(kvSaveBuild);
					
					Call_Finish();
					
					kvSaveBuild.Rewind();
				}
			}else{
				bPropOutside = true;
			}
		}
	}
	
	kvSaveBuild.Rewind();
	
	bool bWritten = kvSaveBuild.ExportToFile(sFile[0]);
	
	kvSaveBuild.Close();
	
	g_iSaveOverride[iClient] = 0;
	
	if (!bWritten)
	{
		LogError("|CelMod| Could not write the build file '%s'.", sFile[0]);
		
		Cel_ReplyToCommand(iClient, "Your build {green}%s{default} could not be written to disk. The server log has the details.", sSaveName);
		
		return false;
	}
	
	if (iCount == 0)
	{
		Cel_ReplyToCommand(iClient, "Nothing was saved: none of your entities are inside your land.");
	}
	
	if (bPropOutside)
	Cel_ReplyToCommand(iClient, "%t", "PropOutsideLand");
	
	Cel_ReplyToCommand(iClient, "%t", "SavedBuild", sSaveName);
	
	return true;
}

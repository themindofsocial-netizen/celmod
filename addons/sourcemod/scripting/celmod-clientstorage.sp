#pragma semicolon 1

#include <celmod>

#pragma newdecls required

bool g_bLate;

char g_sClientPurchases[MAXPLAYERS + 1][PLATFORM_MAX_PATH];
char g_sClientSettings[MAXPLAYERS + 1][PLATFORM_MAX_PATH];

KeyValues g_kvClientPurchases[MAXPLAYERS + 1];
KeyValues g_kvClientSettings[MAXPLAYERS + 1];

//The Steam id the two paths above belong to. A player's files are only used once Steam has confirmed who they are,
//so data is never read from, or written to, the wrong player's files (or a shared one) while they're joining.
char g_sFilesFor[MAXPLAYERS + 1][32];

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	CreateNative("Cel_CheckClientPurchase", Native_CheckClientPurchase);
	CreateNative("Cel_CreateClientPurchases", Native_CreateClientPurchases);
	CreateNative("Cel_CreateClientSettings", Native_CreateClientSettings);
	CreateNative("Cel_GetClientSettingFloat", Native_GetClientSettingFloat);
	CreateNative("Cel_GetClientSettingInt", Native_GetClientSettingInt);
	CreateNative("Cel_GetClientSettingString", Native_GetClientSettingString);
	CreateNative("Cel_RemoveClientPurchase", Native_RemoveClientPurchase);
	CreateNative("Cel_SaveClientPurchase", Native_SaveClientPurchase);
	CreateNative("Cel_GetClientPurchaseCount", Native_GetClientPurchaseCount);
	CreateNative("Cel_AddClientPurchase", Native_AddClientPurchase);
	CreateNative("Cel_SetClientSettingFloat", Native_SetClientSettingFloat);
	CreateNative("Cel_SetClientSettingInt", Native_SetClientSettingInt);
	CreateNative("Cel_SetClientSettingString", Native_SetClientSettingString);
	
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "|CelMod| Client Storage",
	author = CEL_AUTHOR,
	description = "Handles all client storage, excluding save/loading.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	if (g_bLate)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i))
			{
				EnsureClientFiles(i);
			}
		}
	}
}

public void OnClientAuthorized(int iClient, const char[] sAuth)
{
	EnsureClientFiles(iClient);
}

public void OnClientDisconnect_Post(int iClient)
{
	g_sFilesFor[iClient][0] = '\0';
	g_sClientPurchases[iClient][0] = '\0';
	g_sClientSettings[iClient][0] = '\0';
}

//Points the player's slot at their own files (data/celmod/users/<SteamID64>/), making them if they're new.
//False while Steam hasn't confirmed the player yet (or for bots): nothing is read or saved then.
bool EnsureClientFiles(int iClient)
{
	char sAuth[32], sDir[PLATFORM_MAX_PATH];
	
	if (iClient < 1 || iClient > MaxClients || !IsClientConnected(iClient) || IsFakeClient(iClient) || !IsClientAuthorized(iClient)
		|| !GetClientAuthId(iClient, AuthId_SteamID64, sAuth, sizeof(sAuth)) || sAuth[0] == '\0')
	{
		return false;
	}
	
	if (g_sClientSettings[iClient][0] != '\0' && StrEqual(sAuth, g_sFilesFor[iClient]))
	{
		return true;
	}
	
	BuildPath(Path_SM, sDir, sizeof(sDir), "data/celmod/users/%s", sAuth);
	
	if (!DirExists(sDir))
	{
		CreateDirectory(sDir, 511);
	}
	
	strcopy(g_sFilesFor[iClient], sizeof(g_sFilesFor[]), sAuth);
	
	BuildPath(Path_SM, g_sClientPurchases[iClient], sizeof(g_sClientPurchases[]), "data/celmod/users/%s/purchases.txt", sAuth);
	BuildPath(Path_SM, g_sClientSettings[iClient], sizeof(g_sClientSettings[]), "data/celmod/users/%s/settings.txt", sAuth);
	
	if (!FileExists(g_sClientPurchases[iClient]))
	{
		CreateFile(g_sClientPurchases[iClient], "Purchases");
	}
	
	if (!FileExists(g_sClientSettings[iClient]))
	{
		CreateFile(g_sClientSettings[iClient], "Settings");
	}
	
	return true;
}

void CreateFile(const char[] sPath, const char[] sSection)
{
	KeyValues kvFile = new KeyValues("Vault");
	
	kvFile.ImportFromFile(sPath);
	kvFile.JumpToKey(sSection, true);
	kvFile.Rewind();
	kvFile.ExportToFile(sPath);
	
	delete kvFile;
}

//Natives:
public any Native_CheckClientPurchase(Handle hPlugin, int iNumParams)
{
	char sPurchase[64];
	int iClient = GetNativeCell(1);
	
	if (!EnsureClientFiles(iClient))
	{
		return false;
	}
	
	GetNativeString(2, sPurchase, sizeof(sPurchase));
	
	g_kvClientPurchases[iClient] = new KeyValues("Vault");
	
	g_kvClientPurchases[iClient].ImportFromFile(g_sClientPurchases[iClient]);
	
	g_kvClientPurchases[iClient].JumpToKey("Purchases");
	
	bool bHasPurchase = (g_kvClientPurchases[iClient].GetNum(sPurchase, 0) >= 1);
	
	g_kvClientPurchases[iClient].Rewind();
	
	g_kvClientPurchases[iClient].Close();
	
	return bHasPurchase;
}

public any Native_CheckClientSetting(Handle hPlugin, int iNumParams)
{
	char sSetting[64];
	int iClient = GetNativeCell(1);
	
	if (!EnsureClientFiles(iClient))
	{
		return false;
	}
	
	GetNativeString(2, sSetting, sizeof(sSetting));
	
	g_kvClientSettings[iClient] = new KeyValues("Vault");
	
	g_kvClientSettings[iClient].ImportFromFile(g_sClientSettings[iClient]);
	
	g_kvClientSettings[iClient].JumpToKey("Settings");
	
	bool bHasSetting = view_as<bool>(g_kvClientSettings[iClient].GetNum(sSetting, -1));
	
	g_kvClientSettings[iClient].Rewind();
	
	g_kvClientSettings[iClient].Close();
	
	return bHasSetting;
}

public void Native_CreateClientPurchases(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	if (!EnsureClientFiles(iClient))
	{
		return;
	}
	
	g_kvClientPurchases[iClient] = new KeyValues("Vault");
	
	g_kvClientPurchases[iClient].ImportFromFile(g_sClientPurchases[iClient]);
	
	g_kvClientPurchases[iClient].JumpToKey("Purchases", true);
	
	g_kvClientPurchases[iClient].Rewind();
	
	g_kvClientPurchases[iClient].ExportToFile(g_sClientPurchases[iClient]);
	
	g_kvClientPurchases[iClient].Close();
}

public void Native_CreateClientSettings(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	if (!EnsureClientFiles(iClient))
	{
		return;
	}
	
	g_kvClientSettings[iClient] = new KeyValues("Vault");
	
	g_kvClientSettings[iClient].ImportFromFile(g_sClientSettings[iClient]);
	
	g_kvClientSettings[iClient].JumpToKey("Settings", true);
	
	g_kvClientSettings[iClient].Rewind();
	
	g_kvClientSettings[iClient].ExportToFile(g_sClientSettings[iClient]);
	
	g_kvClientSettings[iClient].Close();
}

public any Native_GetClientSettingFloat(Handle hPlugin, int iNumParams)
{
	char sSetting[64];
	int iClient = GetNativeCell(1);
	
	if (!EnsureClientFiles(iClient))
	{
		return 0.0;
	}
	
	GetNativeString(2, sSetting, sizeof(sSetting));
	
	g_kvClientSettings[iClient] = new KeyValues("Vault");
	
	g_kvClientSettings[iClient].ImportFromFile(g_sClientSettings[iClient]);
	
	g_kvClientSettings[iClient].JumpToKey("Settings", true);
	
	float fValue = g_kvClientSettings[iClient].GetFloat(sSetting, 0.0);
	
	g_kvClientSettings[iClient].Rewind();
	
	g_kvClientSettings[iClient].Close();
	
	return fValue;
}

public int Native_GetClientSettingInt(Handle hPlugin, int iNumParams)
{
	char sSetting[64];
	int iClient = GetNativeCell(1);
	
	if (!EnsureClientFiles(iClient))
	{
		return -1;
	}
	
	GetNativeString(2, sSetting, sizeof(sSetting));
	
	g_kvClientSettings[iClient] = new KeyValues("Vault");
	
	g_kvClientSettings[iClient].ImportFromFile(g_sClientSettings[iClient]);
	
	g_kvClientSettings[iClient].JumpToKey("Settings", true);
	
	int iValue = g_kvClientSettings[iClient].GetNum(sSetting, -1);
	
	g_kvClientSettings[iClient].Rewind();
	
	g_kvClientSettings[iClient].Close();
	
	return iValue;
}

public void Native_GetClientSettingString(Handle hPlugin, int iNumParams)
{
	char sSetting[64], sValue[128];
	int iClient = GetNativeCell(1), iMaxLength = GetNativeCell(4);
	
	if (!EnsureClientFiles(iClient))
	{
		SetNativeString(3, "none", GetNativeCell(4));
		return;
	}
	
	GetNativeString(2, sSetting, sizeof(sSetting));
	
	g_kvClientSettings[iClient] = new KeyValues("Vault");
	
	g_kvClientSettings[iClient].ImportFromFile(g_sClientSettings[iClient]);
	
	g_kvClientSettings[iClient].JumpToKey("Settings", true);
	
	g_kvClientSettings[iClient].GetString(sSetting, sValue, iMaxLength, "none");
	
	g_kvClientSettings[iClient].Rewind();
	
	g_kvClientSettings[iClient].Close();
	
	SetNativeString(3, sValue, iMaxLength);
}

public void Native_RemoveClientPurchase(Handle hPlugin, int iNumParams)
{
	char sPurchase[64];
	int iClient = GetNativeCell(1);
	
	if (!EnsureClientFiles(iClient))
	{
		return;
	}
	
	GetNativeString(2, sPurchase, sizeof(sPurchase));
	
	g_kvClientPurchases[iClient] = new KeyValues("Vault");
	
	g_kvClientPurchases[iClient].ImportFromFile(g_sClientPurchases[iClient]);
	
	g_kvClientPurchases[iClient].JumpToKey("Purchases");
	
	g_kvClientPurchases[iClient].SetNum(sPurchase, 0);
	
	g_kvClientPurchases[iClient].Rewind();
	
	g_kvClientPurchases[iClient].ExportToFile(g_sClientPurchases[iClient]);
	
	g_kvClientPurchases[iClient].Close();
}

public void Native_SaveClientPurchase(Handle hPlugin, int iNumParams)
{
	char sPurchase[64];
	int iClient = GetNativeCell(1);
	
	if (!EnsureClientFiles(iClient))
	{
		return;
	}
	
	GetNativeString(2, sPurchase, sizeof(sPurchase));
	
	g_kvClientPurchases[iClient] = new KeyValues("Vault");
	
	g_kvClientPurchases[iClient].ImportFromFile(g_sClientPurchases[iClient]);
	
	g_kvClientPurchases[iClient].JumpToKey("Purchases", true);
	
	g_kvClientPurchases[iClient].SetNum(sPurchase, view_as<int>(GetNativeCell(3)));
	
	g_kvClientPurchases[iClient].Rewind();
	
	g_kvClientPurchases[iClient].ExportToFile(g_sClientPurchases[iClient]);
	
	g_kvClientPurchases[iClient].Close();
}

public void Native_SetClientSettingFloat(Handle hPlugin, int iNumParams)
{
	char sSetting[64];
	int iClient = GetNativeCell(1);
	
	if (!EnsureClientFiles(iClient))
	{
		return;
	}
	
	GetNativeString(2, sSetting, sizeof(sSetting));
	
	g_kvClientSettings[iClient] = new KeyValues("Vault");
	
	g_kvClientSettings[iClient].ImportFromFile(g_sClientSettings[iClient]);
	
	g_kvClientSettings[iClient].JumpToKey("Settings", true);
	
	g_kvClientSettings[iClient].SetFloat(sSetting, GetNativeCell(3));
	
	g_kvClientSettings[iClient].Rewind();
	
	g_kvClientSettings[iClient].ExportToFile(g_sClientSettings[iClient]);
	
	g_kvClientSettings[iClient].Close();
}

public void Native_SetClientSettingInt(Handle hPlugin, int iNumParams)
{
	char sSetting[64];
	int iClient = GetNativeCell(1);
	
	if (!EnsureClientFiles(iClient))
	{
		return;
	}
	
	GetNativeString(2, sSetting, sizeof(sSetting));
	
	g_kvClientSettings[iClient] = new KeyValues("Vault");
	
	g_kvClientSettings[iClient].ImportFromFile(g_sClientSettings[iClient]);
	
	g_kvClientSettings[iClient].JumpToKey("Settings", true);
	
	g_kvClientSettings[iClient].SetNum(sSetting, GetNativeCell(3));
	
	g_kvClientSettings[iClient].Rewind();
	
	g_kvClientSettings[iClient].ExportToFile(g_sClientSettings[iClient]);
	
	g_kvClientSettings[iClient].Close();
}

public void Native_SetClientSettingString(Handle hPlugin, int iNumParams)
{
	char sSetting[64], sValue[128];
	int iClient = GetNativeCell(1);
	
	if (!EnsureClientFiles(iClient))
	{
		return;
	}
	
	GetNativeString(2, sSetting, sizeof(sSetting));
	GetNativeString(3, sValue, sizeof(sValue));
	
	g_kvClientSettings[iClient] = new KeyValues("Vault");
	
	g_kvClientSettings[iClient].ImportFromFile(g_sClientSettings[iClient]);
	
	g_kvClientSettings[iClient].JumpToKey("Settings", true);
	
	g_kvClientSettings[iClient].SetString(sSetting, sValue);
	
	g_kvClientSettings[iClient].Rewind();
	
	g_kvClientSettings[iClient].ExportToFile(g_sClientSettings[iClient]);
	
	g_kvClientSettings[iClient].Close();
}

//A purchase's value is how many the player owns (shop props are finite CelItems: one per purchase).
public int Native_GetClientPurchaseCount(Handle hPlugin, int iNumParams)
{
	char sPurchase[64];
	int iClient = GetNativeCell(1);
	
	if (!EnsureClientFiles(iClient))
	{
		return 0;
	}
	
	GetNativeString(2, sPurchase, sizeof(sPurchase));
	
	KeyValues kvPurchases = new KeyValues("Vault");
	
	kvPurchases.ImportFromFile(g_sClientPurchases[iClient]);
	
	int iCount = kvPurchases.JumpToKey("Purchases") ? kvPurchases.GetNum(sPurchase, 0) : 0;
	
	delete kvPurchases;
	
	return iCount < 0 ? 0 : iCount;
}

public int Native_AddClientPurchase(Handle hPlugin, int iNumParams)
{
	char sPurchase[64];
	int iClient = GetNativeCell(1), iAdd = GetNativeCell(3);
	
	if (!EnsureClientFiles(iClient))
	{
		return 0;
	}
	
	GetNativeString(2, sPurchase, sizeof(sPurchase));
	
	KeyValues kvPurchases = new KeyValues("Vault");
	
	kvPurchases.ImportFromFile(g_sClientPurchases[iClient]);
	kvPurchases.JumpToKey("Purchases", true);
	
	int iCount = kvPurchases.GetNum(sPurchase, 0) + iAdd;
	
	if (iCount < 0)
	{
		iCount = 0;
	}
	
	kvPurchases.SetNum(sPurchase, iCount);
	kvPurchases.Rewind();
	kvPurchases.ExportToFile(g_sClientPurchases[iClient]);
	
	delete kvPurchases;
	
	return iCount;
}

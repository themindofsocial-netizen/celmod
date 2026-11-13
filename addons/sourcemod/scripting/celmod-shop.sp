#pragma semicolon 1

#include <celmod>

#pragma newdecls required

/*
 * |CelMod| Shop
 *
 * One catalog for everything that can be bought, in game (!buy <key>) or on the website:
 *
 *   Commands        "Commands" in shop.txt, as before ("key" "price|display").
 *   Rare props      "Props" in shop.txt: props only their buyers can spawn (rare cels, discontinued props).
 *   Emblems, hats   "Collectibles" in shop.txt, given like !giveitem.
 *   Player models   Every model in collectibles.txt with a price, given like !givemodel.
 *
 * Items can have a limited stock. What has been sold is kept in data/celmod/shopstock.txt, so a
 * stock of 6 means 6 can ever be sold, across restarts. Delivery always happens here, on the game
 * server, so the website can never sell more than there is or charge a player who can't pay.
 */

#define TYPE_COMMAND 0
#define TYPE_PROP 1
#define TYPE_COLLECTIBLE 2
#define TYPE_MODEL 3

enum struct ShopItem
{
	char sKey[64];         // what players type: "fire", "prop_dog", "model_gman", "hat_yearhat2009"
	char sName[64];
	char sCategory[32];
	char sDescription[128];
	char sTarget[64];      // prop alias / collectible id / player model id
	char sKind[16];        // collectibles: emblem, hat or weapon
	int iType;
	int iPrice;
	int iStock;            // 0 = no limit
	bool bRepeatable;
}

ArrayList g_alItems;
StringMap g_smSeasonOpen;
char g_sOpenShops[256];
KeyValues g_kvStock;

char g_sShopDB[PLATFORM_MAX_PATH];
char g_sStockDB[PLATFORM_MAX_PATH];
char g_sTypeName[4][16] = { "command", "prop", "collectible", "model" };

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	CreateNative("Cel_ShopGetItemCount", Native_ShopGetItemCount);
	CreateNative("Cel_ShopGetItem", Native_ShopGetItem);
	CreateNative("Cel_ShopGetItemType", Native_ShopGetItemType);
	CreateNative("Cel_ShopFindItem", Native_ShopFindItem);
	CreateNative("Cel_ShopOwnsItem", Native_ShopOwnsItem);
	CreateNative("Cel_ShopDeliver", Native_ShopDeliver);

	RegPluginLibrary("celmod-shop");

	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "|CelMod| Shop",
	author = CEL_AUTHOR,
	description = "The catalog of commands, rare props, player models, emblems and hats for sale.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	g_alItems = new ArrayList(sizeof(ShopItem));
	g_smSeasonOpen = new StringMap();

	BuildPath(Path_SM, g_sShopDB, sizeof(g_sShopDB), "data/celmod/shop.txt");
	BuildPath(Path_SM, g_sStockDB, sizeof(g_sStockDB), "data/celmod/shopstock.txt");

	g_kvStock = new KeyValues("Stock");
	g_kvStock.ImportFromFile(g_sStockDB);

	RegConsoleCmd("v_catalog", Command_Catalog, "|CelMod| Lists everything in the shop: commands, rare props, player models, emblems and hats.");
	RegConsoleCmd("v_shopitems", Command_Catalog, "|CelMod| Lists everything in the shop: commands, rare props, player models, emblems and hats.");
	RegConsoleCmd("v_seasons", Command_Seasons, "|CelMod| Lists the seasonal shops and when they open.");
	RegAdminCmd("cm_shop_reload", Command_Reload, ADMFLAG_ROOT, "|CelMod| Reloads the shop catalog from shop.txt and collectibles.txt.");
}

public void OnAllPluginsLoaded()
{
	LoadCatalog();
}

public void OnMapStart()
{
	// collectibles.txt is read by celmod-collectibles at map start, so build after it.
	CreateTimer(1.0, Timer_LoadCatalog, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_LoadCatalog(Handle hTimer)
{
	LoadCatalog();
	return Plugin_Stop;
}

public Action Command_Reload(int iClient, int iArgs)
{
	LoadCatalog();
	ReplyToCommand(iClient, "|CelMod| Shop reloaded: %d items.", g_alItems.Length);
	return Plugin_Handled;
}

//Catalog:
void LoadCatalog()
{
	char sKey[64], sValue[160], sParts[2][64];
	ShopItem eItem;

	g_alItems.Clear();

	KeyValues kvShop = new KeyValues("Shop");

	if (!kvShop.ImportFromFile(g_sShopDB))
	{
		LogError("|CelMod| Could not read %s, the shop is empty.", g_sShopDB);
		delete kvShop;
		return;
	}

	LoadSeasons(kvShop);
	kvShop.Rewind();

	// Commands: "key" "price|display"
	if (kvShop.JumpToKey("Commands") && kvShop.GotoFirstSubKey(false))
	{
		do
		{
			kvShop.GetSectionName(sKey, sizeof(sKey));
			kvShop.GetString(NULL_STRING, sValue, sizeof(sValue));

			sParts[0][0] = '\0';
			sParts[1][0] = '\0';
			ExplodeString(sValue, "|", sParts, 2, sizeof(sParts[]));

			ResetItem(eItem, TYPE_COMMAND, sKey, "Commands");
			strcopy(eItem.sName, sizeof(eItem.sName), sParts[1][0] != '\0' ? sParts[1] : sKey);
			strcopy(eItem.sTarget, sizeof(eItem.sTarget), sKey);
			eItem.iPrice = StringToInt(sParts[0]);
			AddItem(eItem);
		} while (kvShop.GotoNextKey(false));
	}
	kvShop.Rewind();

	// Rare props: "alias" { "name" "price" "stock" "category" "description" "spawn" }
	if (kvShop.JumpToKey("Props") && kvShop.GotoFirstSubKey())
	{
		do
		{
			kvShop.GetSectionName(sValue, sizeof(sValue));
			StringToLowerCase(sValue);
			FormatEx(sKey, sizeof(sKey), "prop_%s", sValue);

			// Seasonal props are only for sale while their season is on.
			char sSeason[32];
			bool bOpen;

			kvShop.GetString("season", sSeason, sizeof(sSeason), "");

			if (sSeason[0] != '\0' && (!g_smSeasonOpen.GetValue(sSeason, bOpen) || !bOpen))
			{
				continue;
			}

			ResetItem(eItem, TYPE_PROP, sKey, "Rare Props");
			strcopy(eItem.sTarget, sizeof(eItem.sTarget), sValue);
			ReadCommonKeys(kvShop, eItem);
			AddItem(eItem);
		} while (kvShop.GotoNextKey());
	}
	kvShop.Rewind();

	// Emblems and hats: "key" { "kind" "id" "name" "price" "stock" "category" "description" "repeatable" }
	if (kvShop.JumpToKey("Collectibles") && kvShop.GotoFirstSubKey())
	{
		do
		{
			kvShop.GetSectionName(sKey, sizeof(sKey));
			StringToLowerCase(sKey);

			ResetItem(eItem, TYPE_COLLECTIBLE, sKey, "");
			kvShop.GetString("kind", eItem.sKind, sizeof(eItem.sKind), "emblem");
			kvShop.GetString("id", eItem.sTarget, sizeof(eItem.sTarget), sKey);
			strcopy(eItem.sCategory, sizeof(eItem.sCategory), StrEqual(eItem.sKind, "hat", false) ? "Hats" : (StrEqual(eItem.sKind, "weapon", false) ? "Weapons" : "Emblems"));
			eItem.bRepeatable = view_as<bool>(kvShop.GetNum("repeatable", StrEqual(eItem.sKind, "emblem", false) ? 1 : 0));
			eItem.sName[0] = '\0'; // filled from collectibles.txt unless shop.txt names it
			ReadCommonKeys(kvShop, eItem);

			if (!CollectibleExists(eItem.sKind, eItem.sTarget, eItem.sName, sizeof(eItem.sName)))
			{
				LogError("|CelMod| Shop item \"%s\": there is no %s called \"%s\" in collectibles.txt.", sKey, eItem.sKind, eItem.sTarget);
				continue;
			}

			AddItem(eItem);
		} while (kvShop.GotoNextKey());
	}
	kvShop.Rewind();

	// Player models with a price, from collectibles.txt. shop.txt "PlayerModels" can hide one or limit its stock.
	char sId[32], sName[48];
	int iPrice, iFlags;

	for (int i = 0; i < Cel_GetPlayerModelCount(); i++)
	{
		if (!Cel_GetPlayerModelInfo(i, sId, sizeof(sId), sName, sizeof(sName), iPrice, iFlags) || iPrice < 1 || iFlags != 0)
		{
			continue;
		}

		FormatEx(sKey, sizeof(sKey), "model_%s", sId);
		StringToLowerCase(sKey);

		ResetItem(eItem, TYPE_MODEL, sKey, "Player Models");
		strcopy(eItem.sName, sizeof(eItem.sName), sName);
		strcopy(eItem.sTarget, sizeof(eItem.sTarget), sId);
		eItem.iPrice = iPrice;

		if (kvShop.JumpToKey("PlayerModels") && kvShop.JumpToKey(sId))
		{
			if (kvShop.GetNum("hide", 0) == 1)
			{
				kvShop.Rewind();
				continue;
			}
			ReadCommonKeys(kvShop, eItem);
			eItem.iPrice = iPrice; // the price always comes from collectibles.txt, like !buymodel
		}
		kvShop.Rewind();

		AddItem(eItem);
	}

	delete kvShop;
}

//Seasons: "key" { "name" "start" "MM/DD" "end" "MM/DD" }. Works out which are open today.
void LoadSeasons(KeyValues kvShop)
{
	char sKey[32], sName[64], sStart[8], sEnd[8], sToday[8];

	g_smSeasonOpen.Clear();
	g_sOpenShops[0] = '\0';

	FormatTime(sToday, sizeof(sToday), "%m%d", GetTime());

	int iToday = StringToInt(sToday);

	if (!kvShop.JumpToKey("Seasons") || !kvShop.GotoFirstSubKey())
	{
		return;
	}

	do
	{
		kvShop.GetSectionName(sKey, sizeof(sKey));
		kvShop.GetString("name", sName, sizeof(sName), sKey);
		kvShop.GetString("start", sStart, sizeof(sStart), "");
		kvShop.GetString("end", sEnd, sizeof(sEnd), "");

		int iStart = MonthDay(sStart), iEnd = MonthDay(sEnd);
		bool bOpen = false;

		if (iStart > 0 && iEnd > 0)
		{
			//A season like New Year runs over the end of the year.
			bOpen = (iStart <= iEnd) ? (iToday >= iStart && iToday <= iEnd) : (iToday >= iStart || iToday <= iEnd);
		}

		g_smSeasonOpen.SetValue(sKey, bOpen);

		if (bOpen)
		{
			Format(g_sOpenShops, sizeof(g_sOpenShops), "%s%s{green}%s{default}", g_sOpenShops, g_sOpenShops[0] == '\0' ? "" : " and the ", sName);
		}
	}
	while (kvShop.GotoNextKey());
}

// "12/25" -> 1225, or 0 if it is not a date.
int MonthDay(const char[] sDate)
{
	char sParts[2][4];

	if (ExplodeString(sDate, "/", sParts, 2, sizeof(sParts[])) != 2)
	{
		return 0;
	}

	int iMonth = StringToInt(sParts[0]), iDay = StringToInt(sParts[1]);

	if (iMonth < 1 || iMonth > 12 || iDay < 1 || iDay > 31)
	{
		return 0;
	}

	return iMonth * 100 + iDay;
}

//Players hear about an open seasonal shop when they join.
public void OnClientPostAdminCheck(int iClient)
{
	if (g_sOpenShops[0] != '\0' && !IsFakeClient(iClient))
	{
		CreateTimer(20.0, Timer_SeasonNotice, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_SeasonNotice(Handle hTimer, any iUserId)
{
	int iClient = GetClientOfUserId(iUserId);

	if (iClient > 0 && IsClientInGame(iClient) && g_sOpenShops[0] != '\0')
	{
		Cel_PrintToChat(iClient, "The %s is open! See what's for sale with {green}[tag]catalog{default} or in the web shop.", g_sOpenShops);
	}

	return Plugin_Stop;
}

public Action Command_Seasons(int iClient, int iArgs)
{
	char sKey[32], sName[64], sStart[8], sEnd[8];
	bool bOpen;

	KeyValues kvShop = new KeyValues("Shop");

	if (!kvShop.ImportFromFile(g_sShopDB) || !kvShop.JumpToKey("Seasons") || !kvShop.GotoFirstSubKey())
	{
		delete kvShop;
		Cel_ReplyToCommand(iClient, "There are no seasonal shops on this server.");
		return Plugin_Handled;
	}

	Cel_ReplyToCommand(iClient, "Seasonal shops:");

	do
	{
		kvShop.GetSectionName(sKey, sizeof(sKey));
		kvShop.GetString("name", sName, sizeof(sName), sKey);
		kvShop.GetString("start", sStart, sizeof(sStart), "?");
		kvShop.GetString("end", sEnd, sizeof(sEnd), "?");

		g_smSeasonOpen.GetValue(sKey, bOpen);

		Cel_ReplyToCommand(iClient, "{green}%s{default}: %s to %s%s", sName, sStart, sEnd, bOpen ? " ({green}open now{default})" : "");
	}
	while (kvShop.GotoNextKey());

	delete kvShop;

	return Plugin_Handled;
}

void ResetItem(ShopItem eItem, int iType, const char[] sKey, const char[] sCategory)
{
	strcopy(eItem.sKey, sizeof(eItem.sKey), sKey);
	strcopy(eItem.sName, sizeof(eItem.sName), sKey);
	strcopy(eItem.sCategory, sizeof(eItem.sCategory), sCategory);
	eItem.sDescription[0] = '\0';
	eItem.sTarget[0] = '\0';
	eItem.sKind[0] = '\0';
	eItem.iType = iType;
	eItem.iPrice = 0;
	eItem.iStock = 0;
	eItem.bRepeatable = false;
}

void ReadCommonKeys(KeyValues kvShop, ShopItem eItem)
{
	char sBuffer[128];

	kvShop.GetString("name", sBuffer, sizeof(sBuffer), "");
	if (sBuffer[0] != '\0')
	{
		strcopy(eItem.sName, sizeof(eItem.sName), sBuffer);
	}

	kvShop.GetString("category", sBuffer, sizeof(sBuffer), "");
	if (sBuffer[0] != '\0')
	{
		strcopy(eItem.sCategory, sizeof(eItem.sCategory), sBuffer);
	}

	kvShop.GetString("description", eItem.sDescription, sizeof(eItem.sDescription), "");
	eItem.iPrice = kvShop.GetNum("price", eItem.iPrice);
	eItem.iStock = kvShop.GetNum("stock", 0);
}

void AddItem(ShopItem eItem)
{
	if (!IsSafeKey(eItem.sKey))
	{
		LogError("|CelMod| Shop item \"%s\" skipped: keys may only use letters, numbers, _ and -.", eItem.sKey);
		return;
	}

	if (FindItem(eItem.sKey) != -1)
	{
		LogError("|CelMod| Shop item \"%s\" is listed twice; the first one is used.", eItem.sKey);
		return;
	}

	if (eItem.iPrice < 0)
	{
		eItem.iPrice = 0;
	}

	g_alItems.PushArray(eItem);
}

bool CollectibleExists(const char[] sKind, const char[] sId, char[] sName, int iMaxLength)
{
	char sModel[PLATFORM_MAX_PATH], sRealName[64];
	int iSkin, iColor[4];

	if (!Cel_GetCollectibleLook(sKind, sId, sModel, sizeof(sModel), sRealName, sizeof(sRealName), iSkin, iColor))
	{
		return false;
	}

	// Keep a name given in shop.txt, otherwise use the collectible's own.
	if (sName[0] == '\0')
	{
		strcopy(sName, iMaxLength, sRealName);
	}

	return true;
}

int FindItem(const char[] sKey)
{
	ShopItem eItem;

	for (int i = 0; i < g_alItems.Length; i++)
	{
		g_alItems.GetArray(i, eItem);

		if (StrEqual(eItem.sKey, sKey, false))
		{
			return i;
		}
	}

	return -1;
}

//Stock:
int GetSold(const char[] sKey)
{
	g_kvStock.Rewind();
	return g_kvStock.GetNum(sKey, 0);
}

void AddSold(const char[] sKey)
{
	g_kvStock.Rewind();
	g_kvStock.SetNum(sKey, g_kvStock.GetNum(sKey, 0) + 1);
	g_kvStock.Rewind();

	if (!g_kvStock.ExportToFile(g_sStockDB))
	{
		LogError("|CelMod| Could not write %s; sold counts will reset on restart.", g_sStockDB);
	}
}

/** How many can still be sold, or -1 for no limit. */
int GetLeft(ShopItem eItem)
{
	if (eItem.iStock < 1)
	{
		return -1;
	}

	int iLeft = eItem.iStock - GetSold(eItem.sKey);

	return iLeft < 0 ? 0 : iLeft;
}

bool OwnsItem(int iClient, ShopItem eItem)
{
	char sPurchase[64];

	switch (eItem.iType)
	{
		case TYPE_COMMAND, TYPE_PROP:
		{
			strcopy(sPurchase, sizeof(sPurchase), eItem.sKey);
			return Cel_CheckClientPurchase(iClient, sPurchase);
		}
		case TYPE_MODEL:
		{
			return Cel_OwnsPlayerModel(iClient, eItem.sTarget) == 1;
		}
		case TYPE_COLLECTIBLE:
		{
			return Cel_GetCollectibleCount(iClient, eItem.sKind, eItem.sTarget) > 0;
		}
	}

	return false;
}

/** Sells an item. Returns the price charged, or -1 with the reason in sError. */
int Deliver(int iClient, const char[] sKey, int iMaxPrice, char[] sError, int iErrorLength)
{
	char sPurchase[64];
	ShopItem eItem;

	int iIndex = FindItem(sKey);

	if (iIndex == -1)
	{
		strcopy(sError, iErrorLength, "That item is not in the shop.");
		return -1;
	}

	g_alItems.GetArray(iIndex, eItem);

	if (iMaxPrice >= 0 && eItem.iPrice > iMaxPrice)
	{
		FormatEx(sError, iErrorLength, "The price went up to %d CL.", eItem.iPrice);
		return -1;
	}

	if (GetLeft(eItem) == 0)
	{
		strcopy(sError, iErrorLength, "Sold out.");
		return -1;
	}

	if (!eItem.bRepeatable && OwnsItem(iClient, eItem))
	{
		strcopy(sError, iErrorLength, "You already own this.");
		return -1;
	}

	if (Cel_GetClientBalance(iClient) < eItem.iPrice)
	{
		FormatEx(sError, iErrorLength, "Not enough money: it costs %d CL.", eItem.iPrice);
		return -1;
	}

	if (eItem.iPrice > 0)
	{
		Cel_SubFromClientBalance(iClient, eItem.iPrice);
	}

	bool bGiven = true;

	switch (eItem.iType)
	{
		case TYPE_COMMAND, TYPE_PROP:
		{
			strcopy(sPurchase, sizeof(sPurchase), eItem.sKey);
			Cel_SaveClientPurchase(iClient, sPurchase, true);
		}
		case TYPE_MODEL:
		{
			bGiven = Cel_GivePlayerModel(iClient, eItem.sTarget);
		}
		case TYPE_COLLECTIBLE:
		{
			bGiven = Cel_GiveCollectible(iClient, eItem.sKind, eItem.sTarget);
		}
	}

	if (!bGiven)
	{
		if (eItem.iPrice > 0)
		{
			Cel_AddToClientBalance(iClient, eItem.iPrice);
		}
		strcopy(sError, iErrorLength, "The item could not be given, so you were not charged.");
		return -1;
	}

	if (eItem.iStock > 0)
	{
		AddSold(eItem.sKey);
	}

	switch (eItem.iType)
	{
		case TYPE_COMMAND: Cel_PrintToChat(iClient, "You bought {green}%s{default} for {green}%d CL{default}.", eItem.sName, eItem.iPrice);
		case TYPE_PROP: Cel_PrintToChat(iClient, "You bought {green}%s{default} for {green}%d CL{default}. Spawn it with {green}!%s{default}.", eItem.sName, eItem.iPrice, eItem.sTarget);
		case TYPE_MODEL: Cel_PrintToChat(iClient, "You bought the {green}%s{default} player model for {green}%d CL{default}. Wear it with {green}!playermodel %s{default}.", eItem.sName, eItem.iPrice, eItem.sTarget);
		case TYPE_COLLECTIBLE: Cel_PrintToChat(iClient, "You bought {green}%s{default} for {green}%d CL{default}.", eItem.sName, eItem.iPrice);
	}

	return eItem.iPrice;
}

//Commands:
public Action Command_Catalog(int iClient, int iArgs)
{
	char sCategory[32], sLeft[24];
	ShopItem eItem;

	if (iClient > 0)
	{
		Cel_ReplyToCommand(iClient, "The full shop is in your console. Buy with {green}[tag]buy <name>{default}.");
	}

	sCategory[0] = '\0';

	for (int i = 0; i < g_alItems.Length; i++)
	{
		g_alItems.GetArray(i, eItem);

		if (!StrEqual(eItem.sCategory, sCategory))
		{
			strcopy(sCategory, sizeof(sCategory), eItem.sCategory);
			PrintToConsole(iClient, "\n-- %s --", sCategory);
		}

		int iLeft = GetLeft(eItem);

		if (iLeft == -1)
		{
			sLeft[0] = '\0';
		} else if (iLeft == 0) {
			strcopy(sLeft, sizeof(sLeft), " (sold out)");
		} else {
			FormatEx(sLeft, sizeof(sLeft), " (%d left)", iLeft);
		}

		PrintToConsole(iClient, "%-24s %-28s %9d CL%s%s", eItem.sKey, eItem.sName, eItem.iPrice, sLeft, (iClient > 0 && !eItem.bRepeatable && OwnsItem(iClient, eItem)) ? " [owned]" : "");
	}

	return Plugin_Handled;
}

//Natives:
public int Native_ShopGetItemCount(Handle hPlugin, int iNumParams)
{
	return g_alItems.Length;
}

public int Native_ShopGetItem(Handle hPlugin, int iNumParams)
{
	ShopItem eItem;
	int iIndex = GetNativeCell(1);

	if (iIndex < 0 || iIndex >= g_alItems.Length)
	{
		return false;
	}

	g_alItems.GetArray(iIndex, eItem);

	SetNativeString(2, eItem.sKey, GetNativeCell(3));
	SetNativeString(4, eItem.sName, GetNativeCell(5));
	SetNativeString(6, eItem.sCategory, GetNativeCell(7));
	SetNativeString(8, eItem.sDescription, GetNativeCell(9));
	SetNativeCellRef(10, eItem.iPrice);
	SetNativeCellRef(11, GetLeft(eItem));
	SetNativeCellRef(12, eItem.bRepeatable);

	return true;
}

/** "command", "prop", "model", or the collectible kind ("emblem", "hat", "weapon"), plus what it unlocks. */
public int Native_ShopGetItemType(Handle hPlugin, int iNumParams)
{
	ShopItem eItem;
	int iIndex = GetNativeCell(1);

	if (iIndex < 0 || iIndex >= g_alItems.Length)
	{
		return false;
	}

	g_alItems.GetArray(iIndex, eItem);

	SetNativeString(2, eItem.iType == TYPE_COLLECTIBLE ? eItem.sKind : g_sTypeName[eItem.iType], GetNativeCell(3));
	SetNativeString(4, eItem.sTarget, GetNativeCell(5));

	return true;
}

public int Native_ShopFindItem(Handle hPlugin, int iNumParams)
{
	char sKey[64];

	GetNativeString(1, sKey, sizeof(sKey));

	return FindItem(sKey);
}

public int Native_ShopOwnsItem(Handle hPlugin, int iNumParams)
{
	char sKey[64];
	ShopItem eItem;
	int iClient = GetNativeCell(1);

	GetNativeString(2, sKey, sizeof(sKey));

	int iIndex = FindItem(sKey);

	if (iIndex == -1 || iClient < 1 || iClient > MaxClients || !IsClientInGame(iClient))
	{
		return false;
	}

	g_alItems.GetArray(iIndex, eItem);

	return OwnsItem(iClient, eItem);
}

public int Native_ShopDeliver(Handle hPlugin, int iNumParams)
{
	char sError[128], sKey[64];
	int iClient = GetNativeCell(1);

	GetNativeString(2, sKey, sizeof(sKey));

	if (iClient < 1 || iClient > MaxClients || !IsClientInGame(iClient))
	{
		SetNativeString(4, "The player is not on the server.", GetNativeCell(5));
		return -1;
	}

	int iPrice = Deliver(iClient, sKey, GetNativeCell(3), sError, sizeof(sError));

	SetNativeString(4, sError, GetNativeCell(5));

	return iPrice;
}

//Helpers:
bool IsSafeKey(const char[] sKey)
{
	int iLen = strlen(sKey);

	if (iLen == 0)
	{
		return false;
	}

	for (int i = 0; i < iLen; i++)
	{
		if (!IsCharAlpha(sKey[i]) && !IsCharNumeric(sKey[i]) && sKey[i] != '_' && sKey[i] != '-')
		{
			return false;
		}
	}

	return true;
}

void StringToLowerCase(char[] sText)
{
	for (int i = 0; sText[i] != '\0'; i++)
	{
		sText[i] = CharToLower(sText[i]);
	}
}

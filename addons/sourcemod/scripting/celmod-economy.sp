#pragma semicolon 1

#include <celmod>

#pragma newdecls required

bool g_bLate;

char g_sCleerModel[64];
char g_sShopDB[PLATFORM_MAX_PATH];

ConVar g_cvCleerModel;

Economy g_eEconomy[MAXPLAYERS + 1];

enum struct Economy
{
	bool bInTrade;
	int iBalance;
}

int g_iCleerAmount[MAXENTITIES + 1];
int g_iEntityPrice[MAXENTITIES + 1];
int g_iTradeEntityRef[MAXPLAYERS + 1];
int g_iTradeTarget[MAXPLAYERS + 1];

float g_fTradeExpire[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	CreateNative("Cel_AddToClientBalance", Native_AddToClientBalance);
	CreateNative("Cel_BuyCommand", Native_BuyCommand);
	CreateNative("Cel_BuyEntity", Native_BuyEntity);
	CreateNative("Cel_CancelSale", Native_CancelSale);
	CreateNative("Cel_CheckClientBalance", Native_CheckClientBalance);
	CreateNative("Cel_CheckShopDB", Native_CheckShopDB);
	//CreateNative("Cel_CreateCleerBox", Native_CreateCleerBox);
	//CreateNative("Cel_GetCleerBoxAmount", Native_GetCleerBoxAmount);
	CreateNative("Cel_GetClientBalance", Native_GetClientBalance);
	CreateNative("Cel_GetClientBalanceTranslated", Native_GetClientBalanceTranslated);
	CreateNative("Cel_GetClientPurchaseStatus", Native_GetClientPurchaseStatus);
	CreateNative("Cel_GetEntityPrice", Native_GetEntityPrice);
	CreateNative("Cel_GiveEntity", Native_GiveEntity);
	CreateNative("Cel_IsEntityForSale", Native_IsEntityForSale);
	CreateNative("Cel_SetClientBalance", Native_SetClientBalance);
	CreateNative("Cel_StartSale", Native_StartSale);
	CreateNative("Cel_SubFromClientBalance", Native_SubFromClientBalance);
	
	g_bLate = bLate;
	
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "|CelMod| Economy",
	author = CEL_AUTHOR,
	description = "Controls the econonmy aspects of CelMod.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	LoadTranslations("celmod.phrases");
	LoadTranslations("common.phrases");
	
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
	
	BuildPath(Path_SM, g_sShopDB, sizeof(g_sShopDB), "data/celmod/shop.txt");
	if (!FileExists(g_sShopDB))
	{
		ThrowError("|CelMod| %t", "FileNotFound", g_sShopDB);
	}
	
	g_cvCleerModel = CreateConVar("cm_cleer_box_model", "", "Model path for the cleers box.");
	
	g_cvCleerModel.AddChangeHook(CMEconomy_OnConVarChanged);
	
	g_cvCleerModel.GetString(g_sCleerModel, sizeof(g_sCleerModel));
	
	AutoExecConfig(true, "celmod.economy");
	
	RegAdminCmd("v_setbalance", Command_SetBalance, ADMFLAG_SLAY, "|CelMod| Sets the balance of the client you are specifing.");
	RegConsoleCmd("v_balance", Command_Balance, "|CelMod| Gets the players current balance.");
	RegConsoleCmd("v_buy", Command_Buy, "|CelMod| Purchases the current entity you are looking at or command you specified.");
	RegConsoleCmd("v_give", Command_Give, "|CelMod| Gives the entity you are looking at to another player.");
	RegConsoleCmd("v_sell", Command_Sell, "|CelMod| Sells the entity you are looking at.");
	RegConsoleCmd("v_trade", Command_Trade, "|CelMod| Offers the entity you are looking at in a trade with another player.");
	RegConsoleCmd("v_cl", Command_Cleer, "|CelMod| Shows your balance, or drops an amount of cleers for another player to pick up.");
}

public void OnClientPutInServer(int iClient)
{
	if(Cel_GetClientSettingInt(iClient, "balance") != -1)
	{
		Cel_SetClientBalance(iClient, Cel_GetClientSettingInt(iClient, "balance"));
	}else{
		Cel_SetClientBalance(iClient, 8500);
	}
}

public void OnClientDisconnect(int iClient)
{
	Cel_SetClientSettingInt(iClient, "balance", Cel_GetClientBalance(iClient));
	
	g_iTradeTarget[iClient] = 0;
	
	//Nothing a leaving player owned can stay on the market.
	for (int i = MaxClients + 1; i <= MAXENTITIES; i++)
	{
		if (g_iEntityPrice[i] > 0 && Cel_CheckOwner(iClient, i))
		{
			g_iEntityPrice[i] = 0;
		}
	}
}

public void OnEntityDestroyed(int iEntity)
{
	if (iEntity > 0 && iEntity <= MAXENTITIES)
	{
		g_iCleerAmount[iEntity] = 0;
		g_iEntityPrice[iEntity] = 0;
	}
}

public void CMEconomy_OnConVarChanged(ConVar cvConVar, const char[] sOldValue, const char[] sNewValue)
{
	if (cvConVar == g_cvCleerModel)
	{
		g_cvCleerModel.GetString(g_sCleerModel, sizeof(g_sCleerModel));
		PrintToServer("|CelMod| Cleer model updated to %s.", sNewValue);
	}
}

public Action Command_SetBalance(int iClient, int iArgs)
{
	char sBalance[32], sNames[2][PLATFORM_MAX_PATH], sTarget[PLATFORM_MAX_PATH];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CMD_SetBalance");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	GetCmdArg(2, sBalance, sizeof(sBalance));
	
	GetClientName(iClient, sNames[0], sizeof(sNames[]));
	
	if (StrEqual(sTarget, ""))
	{
		Cel_SetClientBalance(iClient, StringToInt(sBalance));
		
		Cel_ReplyToCommand(iClient, "%t", "SetBalanceClient", sNames[0], Cel_GetClientBalance(iClient));
		
		return Plugin_Handled;
	}
	
	int iTarget = FindTarget(iClient, sTarget, true, false);
	
	if (iTarget == -1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CantFindTarget");
		return Plugin_Handled;
	}
	
	GetClientName(iTarget, sNames[1], sizeof(sNames[]));
	
	Cel_SetClientBalance(iTarget, StringToInt(sBalance));
	
	Cel_ReplyToCommand(iClient, "%t", "SetBalanceClient", sNames[1], Cel_GetClientBalance(iTarget));
	
	return Plugin_Handled;
}

public Action Command_Balance(int iClient, int iArgs)
{
	Cel_ReplyToCommand(iClient, "%t", "GetBalance", Cel_GetClientBalance(iClient));
	
	return Plugin_Handled;
}

public Action Command_Buy(int iClient, int iArgs)
{
	char sDisplay[64], sOption[64];
	
	int iPrice;
	
	GetCmdArg(1, sOption, sizeof(sOption));
	
	if(StrEqual(sOption, ""))
	{
		if (Cel_GetClientAimTarget(iClient) == -1)
		{
			Cel_NotLooking(iClient);
			return Plugin_Handled;
		}
		
		int iProp = Cel_GetClientAimTarget(iClient);
		int iSeller = Cel_GetOwner(iProp);
		
		if (!Cel_IsEntityForSale(iProp) || iSeller < 1 || !Cel_IsPlayer(iSeller))
		{
			Cel_ReplyToCommandEntity(iClient, iProp, "This [type] is not for sale.");
			return Plugin_Handled;
		}
		
		if (iSeller == iClient)
		{
			Cel_ReplyToCommandEntity(iClient, iProp, "You already own this [type]. Type {green}[tag]sell 0{default} to take it off the market.");
			return Plugin_Handled;
		}
		
		if(Cel_CheckClientBalance(iClient, Cel_GetEntityPrice(iProp)))
		{
			Cel_BuyEntity(iClient, iSeller, iProp, Cel_GetEntityPrice(iProp));
			
			return Plugin_Handled;
		}else{
			Cel_ReplyToCommand(iClient, "%t", "InsufficantFunds");
			return Plugin_Handled;
		}
	}
	
	// Everything in the shop catalog (commands, rare props, player models, emblems, hats) is sold by
	// celmod-shop, which checks stock and ownership. "!buy gman" also finds "model_gman", etc.
	char sKey[80], sError[128];
	strcopy(sKey, sizeof(sKey), sOption);
	
	if (Cel_ShopFindItem(sKey) == -1)
	{
		FormatEx(sKey, sizeof(sKey), "prop_%s", sOption);
		
		if (Cel_ShopFindItem(sKey) == -1)
		{
			FormatEx(sKey, sizeof(sKey), "model_%s", sOption);
		}
	}
	
	if (Cel_ShopFindItem(sKey) != -1)
	{
		if (Cel_ShopDeliver(iClient, sKey, -1, sError, sizeof(sError)) == -1)
		{
			Cel_ReplyToCommand(iClient, "%s", sError);
		}
		return Plugin_Handled;
	}
	
	if(Cel_CheckShopDB(sOption, iPrice, sDisplay, sizeof(sDisplay)))
	{
		if(Cel_CheckClientBalance(iClient, iPrice))
		{
			Cel_BuyCommand(iClient, sOption, sDisplay, iPrice);
			return Plugin_Handled;
		}else{
			Cel_ReplyToCommand(iClient, "%t", "InsufficantFunds");
			return Plugin_Handled;
		}
	}else{
		Cel_ReplyToCommand(iClient, "%t", "NotInShop", sOption);
		return Plugin_Handled;
	}
}

public Action Command_Sell(int iClient, int iArgs)
{
	char sPrice[32];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "%t", "CMD_Sell");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sPrice, sizeof(sPrice));
	
	if (Cel_GetClientAimTarget(iClient) == -1)
	{
		Cel_NotLooking(iClient);
		return Plugin_Handled;
	}
	
	int iProp = Cel_GetClientAimTarget(iClient);
	
	if (Cel_CheckOwner(iClient, iProp))
	{
		if (StringToInt(sPrice) < 1)
		{
			if(Cel_IsEntityForSale(iProp))
			{
				Cel_CancelSale(iClient, iProp);
				return Plugin_Handled;
			}else{
				Cel_ReplyToCommand(iClient, "%t", "CannotSellForFree");
				return Plugin_Handled;
			}
		}else{
			Cel_StartSale(iClient, iProp, StringToInt(sPrice));
			return Plugin_Handled;
		}
	} else {
		Cel_NotYours(iClient, iProp);
		return Plugin_Handled;
	}
}

//Drops money as a box. Whoever presses E on it first gets the cleers.
public Action Command_Cleer(int iClient, int iArgs)
{
	char sAmount[32], sModel[PLATFORM_MAX_PATH];
	float fAngles[3], fDirection[3], fOrigin[3];
	
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "%t", "GetBalance", Cel_GetClientBalance(iClient));
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sAmount, sizeof(sAmount));
	
	int iAmount = StringToInt(sAmount);
	
	if (iAmount < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]cl{default} <amount>");
		return Plugin_Handled;
	}
	
	if (!IsPlayerAlive(iClient) || !Cel_CheckClientBalance(iClient, iAmount))
	{
		Cel_ReplyToCommand(iClient, "%t", "InsufficantFunds");
		return Plugin_Handled;
	}
	
	strcopy(sModel, sizeof(sModel), g_sCleerModel);
	
	if (sModel[0] == '\0')
	{
		strcopy(sModel, sizeof(sModel), "models/props_lab/box01a.mdl");
	}
	
	int iBox = CreateEntityByName("prop_physics_override");
	
	if (iBox == -1 || iBox > MAXENTITIES)
	{
		return Plugin_Handled;
	}
	
	PrecacheModel(sModel);
	
	DispatchKeyValue(iBox, "model", sModel);
	DispatchKeyValue(iBox, "classname", "cel_cleerdrop");
	DispatchKeyValue(iBox, "spawnflags", "256");
	
	DispatchSpawn(iBox);
	
	GetClientEyePosition(iClient, fOrigin);
	GetClientEyeAngles(iClient, fAngles);
	
	fAngles[0] = 0.0;
	
	GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);
	
	fOrigin[0] += fDirection[0] * 48.0;
	fOrigin[1] += fDirection[1] * 48.0;
	fOrigin[2] -= 16.0;
	
	TeleportEntity(iBox, fOrigin, fAngles, NULL_VECTOR);
	
	SetEntProp(iBox, Prop_Data, "m_takedamage", 0, 1);
	SetEntityRenderColor(iBox, 0, 255, 0, 255);
	
	g_iCleerAmount[iBox] = iAmount;
	
	Cel_SubFromClientBalance(iClient, iAmount);
	
	SDKHook(iBox, SDKHook_UsePost, Hook_CleerUse);
	
	Cel_ReplyToCommand(iClient, "You dropped {green}%d CL{default}. Anyone can pick it up by pressing {green}E{default} on it.", iAmount);
	
	return Plugin_Handled;
}

public void Hook_CleerUse(int iEntity, int iActivator, int iCaller, UseType utType, float fValue)
{
	if (iActivator < 1 || iActivator > MaxClients || !IsClientInGame(iActivator) || g_iCleerAmount[iEntity] < 1)
	{
		return;
	}
	
	int iAmount = g_iCleerAmount[iEntity];
	
	g_iCleerAmount[iEntity] = 0;
	
	Cel_AddToClientBalance(iActivator, iAmount);
	
	AcceptEntityInput(iEntity, "kill");
	
	Cel_PrintToChat(iActivator, "You picked up {green}%d CL{default}.", iAmount);
}

public Action Command_Give(int iClient, int iArgs)
{
	char sTarget[MAX_NAME_LENGTH];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]give{default} <player>");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	if (Cel_GetClientAimTarget(iClient) == -1)
	{
		Cel_NotLooking(iClient);
		return Plugin_Handled;
	}
	
	int iProp = Cel_GetClientAimTarget(iClient);
	
	if (!Cel_CheckOwner(iClient, iProp))
	{
		Cel_NotYours(iClient, iProp);
		return Plugin_Handled;
	}
	
	int iTarget = FindTarget(iClient, sTarget, true, false);
	
	if (iTarget == -1 || iTarget == iClient)
	{
		return Plugin_Handled;
	}
	
	Cel_GiveEntity(iClient, iTarget, iProp);
	
	return Plugin_Handled;
}

//Both players look at the entity they are offering and type !trade <other player>. The second one completes the swap.
public Action Command_Trade(int iClient, int iArgs)
{
	char sTarget[MAX_NAME_LENGTH];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]trade{default} <player> (while looking at the entity you are offering)");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	if (Cel_GetClientAimTarget(iClient) == -1)
	{
		Cel_NotLooking(iClient);
		return Plugin_Handled;
	}
	
	int iProp = Cel_GetClientAimTarget(iClient);
	
	if (!Cel_CheckOwner(iClient, iProp))
	{
		Cel_NotYours(iClient, iProp);
		return Plugin_Handled;
	}
	
	int iTarget = FindTarget(iClient, sTarget, true, false);
	
	if (iTarget == -1 || iTarget == iClient)
	{
		return Plugin_Handled;
	}
	
	int iTheirProp = EntRefToEntIndex(g_iTradeEntityRef[iTarget]);
	
	//The other player already offered something to this player: swap the two entities.
	if (g_iTradeTarget[iTarget] == GetClientUserId(iClient) && GetGameTime() < g_fTradeExpire[iTarget] && iTheirProp != INVALID_ENT_REFERENCE && iTheirProp > MaxClients && Cel_CheckOwner(iTarget, iTheirProp))
	{
		g_iTradeTarget[iTarget] = 0;
		g_iTradeTarget[iClient] = 0;
		
		g_iEntityPrice[iProp] = 0;
		g_iEntityPrice[iTheirProp] = 0;
		
		Cel_SetOwner(iTarget, iProp);
		Cel_SetOwner(iClient, iTheirProp);
		
		Cel_ChangeBeam(iClient, iTheirProp);
		Cel_ChangeBeam(iTarget, iProp);
		
		Cel_ReplyToCommandEntity(iClient, iTheirProp, "Trade complete. You received a [type] from {green}%N{default}.", iTarget);
		Cel_ReplyToCommandEntity(iTarget, iProp, "Trade complete. You received a [type] from {green}%N{default}.", iClient);
		
		return Plugin_Handled;
	}
	
	g_iTradeTarget[iClient] = GetClientUserId(iTarget);
	g_iTradeEntityRef[iClient] = EntIndexToEntRef(iProp);
	g_fTradeExpire[iClient] = GetGameTime() + 60.0;
	
	Cel_ReplyToCommandEntity(iClient, iProp, "You offered this [type] to {green}%N{default}. The offer lasts 60 seconds.", iTarget);
	Cel_ReplyToCommandEntity(iTarget, iProp, "{green}%N{default} is offering you a [type] in a trade. Look at what you want to give in return and type {green}!trade %N{default}.", iClient, iClient);
	
	return Plugin_Handled;
}

//Natives:
public int Native_AddToClientBalance(Handle hPlugin, int iNumParams)
{
	int iBalance = GetNativeCell(2), iClient = GetNativeCell(1), iNewBalance;
	
	iNewBalance = (g_eEconomy[iClient].iBalance += iBalance);
	
	Cel_SetClientBalance(iClient, iNewBalance);
	
	return true;
}

public int Native_BuyCommand(Handle hPlugin, int iNumParams)
{
	char sCommand[64], sDisplay[64];
	int iClient = GetNativeCell(1), iPrice = GetNativeCell(4);
	
	GetNativeString(2, sCommand, sizeof(sCommand));
	GetNativeString(3, sDisplay, sizeof(sDisplay));
	
	Cel_SaveClientPurchase(iClient, sCommand, true);
	
	Cel_SubFromClientBalance(iClient, iPrice);
	
	Cel_ReplyToCommand(iClient, "%t", "PurchaseCommand", sDisplay, iPrice);
	
	return true;
}

public int Native_BuyEntity(Handle hPlugin, int iNumParams)
{
	char sBuyer[64], sEntityType[32], sOwner[64];
	
	int iBuyer = GetNativeCell(1), iOwner = GetNativeCell(2), iPrice = GetNativeCell(4), iProp = GetNativeCell(3);
	
	Cel_GetEntityTypeName(Cel_GetEntityType(iProp), sEntityType, sizeof(sEntityType));
	
	GetClientName(iBuyer, sBuyer, sizeof(sBuyer));
	GetClientName(iOwner, sOwner, sizeof(sOwner));
	
	g_iEntityPrice[iProp] = 0;
	
	Cel_SetOwner(iBuyer, iProp);
	
	Cel_AddToClientBalance(iOwner, iPrice);
	
	Cel_SubFromClientBalance(iBuyer, iPrice);
	
	Cel_ChangeBeam(iBuyer, iProp);
	
	Cel_ReplyToCommandEntity(iBuyer, iProp, "You bought this [type] from {green}%s{default} for {green}%d CL{default}. It is now yours.", sOwner, iPrice);
	
	Cel_PrintToChat(iOwner, "{green}%s{default} bought your %s for {green}%d CL{default}.", sBuyer, sEntityType, iPrice);
	
	return true;
}

public int Native_CancelSale(Handle hPlugin, int iNumParams)
{
	char sEntityType[32];
	int iClient = GetNativeCell(1), iProp = GetNativeCell(2);
	
	g_iEntityPrice[iProp] = 0;
	
	Cel_GetEntityTypeName(Cel_GetEntityType(iProp), sEntityType, sizeof(sEntityType));
	
	Cel_ReplyToCommandEntity(iClient, iProp, "%t", "SaleCanceled");
	
	return true;
}

public int Native_CheckClientBalance(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1), iPrice = GetNativeCell(2);
	
	return (Cel_GetClientBalance(iClient) >= iPrice);
}

public int Native_CheckShopDB(Handle hPlugin, int iNumParams)
{
	int iMaxLength = GetNativeCell(4), iPrice;
	
	char sBuffer[2][32], sDisplayString[64], sOption[64];
	
	GetNativeString(1, sOption, sizeof(sOption));
	
	KeyValues kvShop = new KeyValues("Shop");
	
	kvShop.ImportFromFile(g_sShopDB);
	
	kvShop.JumpToKey("Commands", false);
	
	kvShop.GetString(sOption, sDisplayString, iMaxLength, "null");
	
	kvShop.Rewind();
	
	delete kvShop;
	
	if(StrEqual(sDisplayString, "null"))
	{
		Format(sBuffer[1], sizeof(sBuffer[]), "null");
		iPrice = 0;
	}else{
		ExplodeString(sDisplayString, "|", sBuffer, 2, sizeof(sBuffer[]));
		iPrice = StringToInt(sBuffer[0]);
	}
	
	SetNativeCellRef(2, iPrice);
	SetNativeString(3, sBuffer[1], iMaxLength);
	
	return (StrEqual(sDisplayString, "null")) ? false : true;
}

public int Native_GetClientBalance(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_eEconomy[iClient].iBalance;
}

public int Native_GetClientBalanceTranslated(Handle hPlugin, int iNumParams)
{
	char sBalance[64];
	int iClient = GetNativeCell(1), iMaxLength = GetNativeCell(3);
	
	if (g_eEconomy[iClient].iBalance < 100000)
	Format(sBalance, sizeof(sBalance), "%d CL", g_eEconomy[iClient].iBalance);
	else if (g_eEconomy[iClient].iBalance < 1000000)
	Format(sBalance, sizeof(sBalance), "%.1fK CL", g_eEconomy[iClient].iBalance / 1000.0);
	else if (g_eEconomy[iClient].iBalance < 1000000000)
	Format(sBalance, sizeof(sBalance), "%.1fM CL", g_eEconomy[iClient].iBalance / 1000000.0);
	else if (g_eEconomy[iClient].iBalance < 1000000000000)
	Format(sBalance, sizeof(sBalance), "%.1fB CL", g_eEconomy[iClient].iBalance / 1000000000.0);
	else if (g_eEconomy[iClient].iBalance < 1000000000000000)
	Format(sBalance, sizeof(sBalance), "%.1fT CL", g_eEconomy[iClient].iBalance / 1000000000000.0);
	else
	Format(sBalance, sizeof(sBalance), "%.1fQ CL", g_eEconomy[iClient].iBalance / 1000000000000000.0);
	
	
	SetNativeString(2, sBalance, iMaxLength);
	
	return true;
}

public int Native_GetClientPurchaseStatus(Handle hPlugin, int iNumParams)
{
	char sCommand[64];
	int iClient = GetNativeCell(1);
	
	GetNativeString(2, sCommand, sizeof(sCommand));
	
	if(Cel_CheckClientPurchase(iClient, sCommand))
	{
		return true;
	}
	
	return false;
}

public int Native_GetEntityPrice(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1);
	
	return g_iEntityPrice[iEntity];
}

public int Native_GiveEntity(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1), iTarget = GetNativeCell(2), iProp = GetNativeCell(3);
	
	g_iEntityPrice[iProp] = 0;
	
	Cel_SetOwner(iTarget, iProp);
	
	Cel_ChangeBeam(iClient, iProp);
	
	Cel_ReplyToCommandEntity(iClient, iProp, "You gave this [type] to {green}%N{default}.", iTarget);
	Cel_ReplyToCommandEntity(iTarget, iProp, "{green}%N{default} gave you a [type].", iClient);
	
	return true;
}

public int Native_IsEntityForSale(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1);
	
	return (iEntity > 0 && iEntity <= MAXENTITIES && g_iEntityPrice[iEntity] > 0);
}

public int Native_SetClientBalance(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1), iBalance = GetNativeCell(2);
	
	g_eEconomy[iClient].iBalance = iBalance;
	
	Cel_SetClientSettingInt(iClient, "balance", iBalance);
	
	return true;
}

public int Native_StartSale(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1), iEntity = GetNativeCell(2), iPrice = GetNativeCell(3);
	
	g_iEntityPrice[iEntity] = iPrice;
	
	Cel_ReplyToCommandEntity(iClient, iEntity, "%t", "StartSale", iPrice);
	
	return true;
}

public int Native_SubFromClientBalance(Handle hPlugin, int iNumParams)
{
	int iBalance = GetNativeCell(2), iClient = GetNativeCell(1), iNewBalance;
	
	iNewBalance = (g_eEconomy[iClient].iBalance -= iBalance);
	
	Cel_SetClientBalance(iClient, iNewBalance);
	
	return true;
}

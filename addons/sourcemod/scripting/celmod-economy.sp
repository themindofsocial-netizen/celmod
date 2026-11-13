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
int g_iCleerOwner[MAXENTITIES + 1];
int g_iTacticsLevel[MAXPLAYERS + 1];
int g_iTacticsXP[MAXPLAYERS + 1];

float g_fNextBuildXP[MAXPLAYERS + 1];

ConVar g_cvXPBuild;
ConVar g_cvXPKill;
ConVar g_cvXPMinute;
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
	CreateNative("Cel_CreateCleerBox", Native_CreateCleerBox);
	CreateNative("Cel_GetCleerBoxAmount", Native_GetCleerBoxAmount);
	CreateNative("Cel_IsEntityForSale", Native_IsEntityForSale);
	CreateNative("Cel_SetClientBalance", Native_SetClientBalance);
	CreateNative("Cel_StartSale", Native_StartSale);
	CreateNative("Cel_SubFromClientBalance", Native_SubFromClientBalance);
	CreateNative("Cel_AddTacticsXP", Native_AddTacticsXP);
	CreateNative("Cel_GetTacticsLevel", Native_GetTacticsLevel);
	CreateNative("Cel_GetTacticsXP", Native_GetTacticsXP);
	CreateNative("Cel_GetTacticsXPNeeded", Native_GetTacticsXPNeeded);
	
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
	
	g_cvXPMinute = CreateConVar("cm_tactics_xp_minute", "3", "Tactics experience for each minute played.", _, true, 0.0);
	g_cvXPKill = CreateConVar("cm_tactics_xp_kill", "5", "Tactics experience for killing another player.", _, true, 0.0);
	g_cvXPBuild = CreateConVar("cm_tactics_xp_build", "1", "Tactics experience for spawning a prop or cel (at most once every 3 seconds).", _, true, 0.0);
	
	AutoExecConfig(true, "celmod.economy");
	
	HookEvent("player_death", Event_TacticsDeath, EventHookMode_Post);
	
	CreateTimer(60.0, Timer_TacticsMinute, _, TIMER_REPEAT);
	
	RegConsoleCmd("v_tacticlvl", Command_TacticsLevel, "|CelMod| Shows your tactics level.");
	RegConsoleCmd("v_tacticxp", Command_TacticsLevel, "|CelMod| Shows your tactics experience towards the next level.");
	
	RegAdminCmd("v_setbalance", Command_SetBalance, ADMFLAG_SLAY, "|CelMod| Sets the balance of the client you are specifing.");
	RegAdminCmd("v_givemoney", Command_GiveMoney, ADMFLAG_SLAY, "|CelMod| Adds cleers to a player's balance: v_givemoney <player> <amount>.");
	RegAdminCmd("v_takemoney", Command_TakeMoney, ADMFLAG_SLAY, "|CelMod| Takes cleers from a player's balance: v_takemoney <player> <amount>.");
	RegConsoleCmd("v_balance", Command_Balance, "|CelMod| Gets the players current balance.");
	RegConsoleCmd("v_buy", Command_Buy, "|CelMod| Purchases the current entity you are looking at or command you specified.");
	RegConsoleCmd("v_give", Command_Give, "|CelMod| Gives the entity you are looking at to another player.");
	RegConsoleCmd("v_sell", Command_Sell, "|CelMod| Sells the entity you are looking at.");
	RegConsoleCmd("v_trade", Command_Trade, "|CelMod| Offers the entity you are looking at in a trade with another player.");
	RegConsoleCmd("v_cl", Command_Cleer, "|CelMod| Shows your balance, or drops an amount of cleers for another player to pick up.");
}

public void OnClientPutInServer(int iClient)
{
	g_iTacticsLevel[iClient] = Cel_GetClientSettingInt(iClient, "tactics_level");
	g_iTacticsXP[iClient] = Cel_GetClientSettingInt(iClient, "tactics_xp");
	g_fNextBuildXP[iClient] = 0.0;
	
	if (g_iTacticsLevel[iClient] < 1)
	{
		g_iTacticsLevel[iClient] = 1;
	}
	
	if (g_iTacticsXP[iClient] < 0)
	{
		g_iTacticsXP[iClient] = 0;
	}
	
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
	
	SaveTactics(iClient);
	
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
		//A cleers box that is deleted or cleaned up gives its money back to whoever owns it.
		if (g_iCleerAmount[iEntity] > 0)
		{
			int iOwner = GetClientOfUserId(g_iCleerOwner[iEntity]);
			
			if (iOwner > 0 && IsClientInGame(iOwner))
			{
				Cel_AddToClientBalance(iOwner, g_iCleerAmount[iEntity]);
			}
		}
		
		g_iCleerAmount[iEntity] = 0;
		g_iCleerOwner[iEntity] = 0;
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

public Action Command_GiveMoney(int iClient, int iArgs)
{
	return ChangeMoney(iClient, iArgs, true);
}

public Action Command_TakeMoney(int iClient, int iArgs)
{
	return ChangeMoney(iClient, iArgs, false);
}

//Admins add to or take from one or more players' balances (@all, @me, names...). Balances never go below 0.
Action ChangeMoney(int iClient, int iArgs, bool bGive)
{
	char sAmount[32], sTarget[MAX_NAME_LENGTH], sTargetName[MAX_TARGET_LENGTH];
	int iTargets[MAXPLAYERS + 1];
	bool bTnIsMl;
	
	if (iArgs < 2)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]%s{default} <player> <amount>", bGive ? "givemoney" : "takemoney");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	GetCmdArg(2, sAmount, sizeof(sAmount));
	
	int iAmount = StringToInt(sAmount);
	
	if (iAmount < 1)
	{
		Cel_ReplyToCommand(iClient, "The amount must be a whole number above 0.");
		return Plugin_Handled;
	}
	
	int iCount = ProcessTargetString(sTarget, iClient, iTargets, sizeof(iTargets), COMMAND_FILTER_NO_BOTS, sTargetName, sizeof(sTargetName), bTnIsMl);
	
	if (iCount <= 0)
	{
		ReplyToTargetError(iClient, iCount);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < iCount; i++)
	{
		int iTarget = iTargets[i];
		
		if (bGive)
		{
			Cel_AddToClientBalance(iTarget, iAmount);
			
			Cel_PrintToChat(iTarget, "An admin gave you {green}%d CL{default}. You now have {green}%d CL{default}.", iAmount, Cel_GetClientBalance(iTarget));
		} else {
			int iTaken = (Cel_GetClientBalance(iTarget) < iAmount) ? Cel_GetClientBalance(iTarget) : iAmount;
			
			Cel_SetClientBalance(iTarget, Cel_GetClientBalance(iTarget) - iTaken);
			
			Cel_PrintToChat(iTarget, "An admin took {green}%d CL{default} from you. You now have {green}%d CL{default}.", iTaken, Cel_GetClientBalance(iTarget));
		}
	}
	
	if (bTnIsMl)
	{
		Cel_ReplyToCommand(iClient, "%s {green}%d CL{default} %s %t.", bGive ? "Gave" : "Took", iAmount, bGive ? "to" : "from", sTargetName);
	} else {
		Cel_ReplyToCommand(iClient, "%s {green}%d CL{default} %s %s.", bGive ? "Gave" : "Took", iAmount, bGive ? "to" : "from", sTargetName);
	}
	
	LogAction(iClient, -1, "\"%L\" %s %d cleers %s %s.", iClient, bGive ? "gave" : "took", iAmount, bGive ? "to" : "from", sTargetName);
	
	return Plugin_Handled;
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

//Drops money as an owned cleers box. The owner opens it with E, or gives it to someone with !give.
public Action Command_Cleer(int iClient, int iArgs)
{
	char sAmount[32];
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
	
	if (!Cel_CheckPropCount(iClient))
	{
		Cel_PrintToChat(iClient, "%t", "MaxPropLimit", Cel_GetPropCount(iClient));
		return Plugin_Handled;
	}
	
	GetClientEyePosition(iClient, fOrigin);
	GetClientEyeAngles(iClient, fAngles);
	
	fAngles[0] = 0.0;
	
	GetAngleVectors(fAngles, fDirection, NULL_VECTOR, NULL_VECTOR);
	
	fOrigin[0] += fDirection[0] * 48.0;
	fOrigin[1] += fDirection[1] * 48.0;
	fOrigin[2] -= 16.0;
	
	if (CreateCleerBox(iClient, iAmount, fOrigin, true) == -1)
	{
		return Plugin_Handled;
	}
	
	Cel_ReplyToCommand(iClient, "You dropped a box with {green}%s CL{default}. Only you can open it ({green}E{default}); look at it and type {green}[tag]give <player>{default} to hand it to someone.", FormatCleers(iAmount));
	
	return Plugin_Handled;
}

char[] FormatCleers(int iAmount)
{
	char sAmount[32];
	
	IntToString(iAmount, sAmount, sizeof(sAmount));
	
	//1234567 -> 1,234,567
	int iLength = strlen(sAmount), iStart = (sAmount[0] == '-') ? 1 : 0;
	
	for (int i = iLength - 3; i > iStart; i -= 3)
	{
		int iEnd = strlen(sAmount);
		
		for (int k = iEnd; k >= i; k--)
		{
			sAmount[k + 1] = sAmount[k];
		}
		
		sAmount[i] = ',';
	}
	
	return sAmount;
}

int CreateCleerBox(int iOwner, int iAmount, const float fOrigin[3], bool bTakeMoney)
{
	char sModel[PLATFORM_MAX_PATH];
	float fAngles[3];
	
	if (iAmount < 1 || iOwner < 1 || iOwner > MaxClients || !IsClientInGame(iOwner))
	{
		return -1;
	}
	
	if (bTakeMoney && !Cel_CheckClientBalance(iOwner, iAmount))
	{
		return -1;
	}
	
	strcopy(sModel, sizeof(sModel), g_sCleerModel);
	
	//The cleers money box, unless the server sets another model.
	if (sModel[0] == '\0')
	{
		Cel_GetMoneyBoxModel(sModel, sizeof(sModel));
	}
	
	int iBox = CreateEntityByName("prop_physics_override");
	
	if (iBox == -1)
	{
		return -1;
	}
	
	if (iBox > MAXENTITIES)
	{
		AcceptEntityInput(iBox, "kill");
		return -1;
	}
	
	PrecacheModel(sModel);
	
	DispatchKeyValue(iBox, "model", sModel);
	DispatchKeyValue(iBox, "classname", "cel_cleerbox");
	DispatchKeyValue(iBox, "spawnflags", "256");
	DispatchKeyValueInt(iBox, "skin", Cel_GetMoneyBoxSkin(iAmount));
	
	DispatchSpawn(iBox);
	
	GetClientEyeAngles(iOwner, fAngles);
	
	fAngles[0] = 0.0;
	fAngles[2] = 0.0;
	
	TeleportEntity(iBox, fOrigin, fAngles, NULL_VECTOR);
	
	SetEntProp(iBox, Prop_Data, "m_takedamage", 0, 1);
	SetEntProp(iBox, Prop_Send, "m_nSkin", Cel_GetMoneyBoxSkin(iAmount));
	
	//A normal owned CelMod prop: it counts towards the owner's props and can be given, traded or deleted.
	Cel_AddToPropCount(iOwner);
	Cel_SetEntity(iBox, true);
	Cel_SetOwner(iOwner, iBox);
	Cel_SetPropName(iBox, "cleers");
	
	if (bTakeMoney)
	{
		Cel_SubFromClientBalance(iOwner, iAmount);
	}
	
	g_iCleerAmount[iBox] = iAmount;
	g_iCleerOwner[iBox] = GetClientUserId(iOwner);
	
	SDKHook(iBox, SDKHook_UsePost, Hook_CleerUse);
	
	return iBox;
}

public int Native_CreateCleerBox(Handle hPlugin, int iNumParams)
{
	float fOrigin[3];
	
	GetNativeArray(3, fOrigin, 3);
	
	return CreateCleerBox(GetNativeCell(1), GetNativeCell(2), fOrigin, view_as<bool>(GetNativeCell(4)));
}

public int Native_GetCleerBoxAmount(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1);
	
	return (iEntity > 0 && iEntity <= MAXENTITIES) ? g_iCleerAmount[iEntity] : 0;
}

public void Cel_OnEntityOwnerChanged(int iEntity, int iOldOwner, int iNewOwner)
{
	if (iEntity > 0 && iEntity <= MAXENTITIES && g_iCleerAmount[iEntity] > 0 && iNewOwner > 0 && iNewOwner <= MaxClients && IsClientInGame(iNewOwner))
	{
		g_iCleerOwner[iEntity] = GetClientUserId(iNewOwner);
	}
}

public void Hook_CleerUse(int iEntity, int iActivator, int iCaller, UseType utType, float fValue)
{
	if (iActivator < 1 || iActivator > MaxClients || !IsClientInGame(iActivator) || g_iCleerAmount[iEntity] < 1)
	{
		return;
	}
	
	//Only the owner can open it; it can be handed to someone else with !give.
	if (!Cel_CheckOwner(iActivator, iEntity))
	{
		if (Cel_IsPlayer(Cel_GetOwner(iEntity)))
		{
			Cel_PrintToChat(iActivator, "This cleers box belongs to {green}%N{default}. They can give it to you with {green}[tag]give{default}.", Cel_GetOwner(iEntity));
		}
		
		return;
	}
	
	int iAmount = g_iCleerAmount[iEntity];
	
	g_iCleerAmount[iEntity] = 0;
	g_iCleerOwner[iEntity] = 0;
	
	Cel_AddToClientBalance(iActivator, iAmount);
	
	AcceptEntityInput(iEntity, "kill");
	
	Cel_PrintToChat(iActivator, "You opened the box: {green}+%s CL{default}.", FormatCleers(iAmount));
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

//Tactics level:
//Experience comes from playing, building and fighting. Each level needs a little more than the last.
int TacticsXPNeeded(int iLevel)
{
	return 50 + iLevel * 10;
}

void SaveTactics(int iClient)
{
	if (g_iTacticsLevel[iClient] < 1)
	{
		return;
	}
	
	Cel_SetClientSettingInt(iClient, "tactics_level", g_iTacticsLevel[iClient]);
	Cel_SetClientSettingInt(iClient, "tactics_xp", g_iTacticsXP[iClient]);
}

void AddTacticsXP(int iClient, int iAmount)
{
	if (iClient < 1 || iClient > MaxClients || !IsClientInGame(iClient) || IsFakeClient(iClient) || iAmount < 1 || g_iTacticsLevel[iClient] < 1)
	{
		return;
	}
	
	g_iTacticsXP[iClient] += iAmount;
	
	bool bLevelled = false;
	
	while (g_iTacticsXP[iClient] >= TacticsXPNeeded(g_iTacticsLevel[iClient]))
	{
		g_iTacticsXP[iClient] -= TacticsXPNeeded(g_iTacticsLevel[iClient]);
		g_iTacticsLevel[iClient]++;
		
		bLevelled = true;
	}
	
	if (bLevelled)
	{
		SaveTactics(iClient);
		
		EmitSoundToClient(iClient, "buttons/bell1.wav");
		
		Cel_PrintToChat(iClient, "Tactics level up! You are now {green}level %d{default}.", g_iTacticsLevel[iClient]);
	}
}

public Action Timer_TacticsMinute(Handle hTimer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) > 1)
		{
			AddTacticsXP(i, g_cvXPMinute.IntValue);
			
			//Saved now and then, so a crash loses little.
			SaveTactics(i);
		}
	}
	
	return Plugin_Continue;
}

public void OnMapStart()
{
	PrecacheSound("buttons/bell1.wav", true);
}

public Action Event_TacticsDeath(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	int iVictim = GetClientOfUserId(eEvent.GetInt("userid"));
	int iAttacker = GetClientOfUserId(eEvent.GetInt("attacker"));
	
	if (iAttacker > 0 && iAttacker != iVictim)
	{
		AddTacticsXP(iAttacker, g_cvXPKill.IntValue);
	}
	
	return Plugin_Continue;
}

void BuildXP(int iOwner)
{
	if (iOwner > 0 && iOwner <= MaxClients && GetGameTime() >= g_fNextBuildXP[iOwner])
	{
		g_fNextBuildXP[iOwner] = GetGameTime() + 3.0;
		
		AddTacticsXP(iOwner, g_cvXPBuild.IntValue);
	}
}

public void Cel_OnPropSpawn(int iProp, int iOwner, EntityType etEntityType)
{
	BuildXP(iOwner);
}

public void Cel_OnCelSpawn(int iCel, int iOwner, EntityType etEntityType)
{
	BuildXP(iOwner);
}

public Action Command_TacticsLevel(int iClient, int iArgs)
{
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	Cel_ReplyToCommand(iClient, "Tactics level {green}%d{default}, {green}%d{default} of {green}%d{default} experience to the next level.", g_iTacticsLevel[iClient], g_iTacticsXP[iClient], TacticsXPNeeded(g_iTacticsLevel[iClient]));
	
	return Plugin_Handled;
}

public int Native_AddTacticsXP(Handle hPlugin, int iNumParams)
{
	AddTacticsXP(GetNativeCell(1), GetNativeCell(2));
	
	return true;
}

public int Native_GetTacticsLevel(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_iTacticsLevel[iClient] < 1 ? 1 : g_iTacticsLevel[iClient];
}

public int Native_GetTacticsXP(Handle hPlugin, int iNumParams)
{
	return g_iTacticsXP[GetNativeCell(1)];
}

public int Native_GetTacticsXPNeeded(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return TacticsXPNeeded(g_iTacticsLevel[iClient] < 1 ? 1 : g_iTacticsLevel[iClient]);
}

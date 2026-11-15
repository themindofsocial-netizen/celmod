#pragma semicolon 1

#include <celmod>

#pragma newdecls required

bool g_bLate;

StringMap g_smCelCommands;

//!pmute: g_bMuted[listener][talker], only for that listener: no voice and no chat from the talker.
bool g_bMuted[MAXPLAYERS + 1][MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	CreateNative("Cel_IsCelCommand", Native_IsCelCommand);
	CreateNative("Cel_NotLooking", Native_NotLooking);
	CreateNative("Cel_NotYours", Native_NotYours);
	CreateNative("Cel_PlayChatMessageSound", Native_PlayChatMessageSound);
	CreateNative("Cel_PrintToChat", Native_PrintToChat);
	CreateNative("Cel_PrintToChatAll", Native_PrintToChatAll);
	CreateNative("Cel_ReplyToCommand", Native_ReplyToCommand);
	CreateNative("Cel_ReplyToCommandEntity", Native_ReplyToCommandEntity);
	
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "|CelMod| Chat Handler",
	author = CEL_AUTHOR,
	description = "",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	LoadTranslations("celmod.phrases");
	
	if (g_bLate)
	{
		OnMapStart();
	}
	
	RegConsoleCmd("v_pmute", Command_PMute, "|CelMod| Mutes (or unmutes) a player just for you, voice and chat: !pmute <name>.");
	RegConsoleCmd("v_punmute", Command_PMute, "|CelMod| Unmutes a player you muted with !pmute: !punmute <name>.");

	// Chat from a muted player is held back from the players who muted them.
	UserMsg umSayText2 = GetUserMessageId("SayText2");

	if (umSayText2 != INVALID_MESSAGE_ID && GetUserMessageType() == UM_BitBuf)
	{
		HookUserMessage(umSayText2, Hook_SayText2, true);
	}

	LoadTranslations("common.phrases");

	AddCommandListener(Handle_Noclip, "noclip");
	AddCommandListener(Handle_Chat, "say");
	AddCommandListener(Handle_Chat, "say_team");
	
	ConCommand_RemoveFlags("noclip", FCVAR_CHEAT);
}

public void OnClientDisconnect(int iClient)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bMuted[iClient][i] = false;
		g_bMuted[i][iClient] = false;
	}
}

public Action Command_PMute(int iClient, int iArgs)
{
	char sCommand[16], sTarget[MAX_NAME_LENGTH];

	if (iClient < 1)
	{
		return Plugin_Handled;
	}

	GetCmdArg(0, sCommand, sizeof(sCommand));
	bool bUnmuteOnly = StrEqual(sCommand, "v_punmute", false);

	if (iArgs < 1)
	{
		char sList[512];
		int iCount = 0;

		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_bMuted[iClient][i] && IsClientInGame(i))
			{
				Format(sList, sizeof(sList), "%s%s{green}%N{default}", sList, iCount++ > 0 ? ", " : "", i);
			}
		}

		if (iCount > 0)
		{
			Cel_ReplyToCommand(iClient, "You have muted: %s. Type {green}!pmute <name>{default} again to unmute.", sList);
		} else {
			Cel_ReplyToCommand(iClient, "Type {green}!pmute{default} and then a player's name to mute them, just for you.");
		}

		return Plugin_Handled;
	}

	GetCmdArgString(sTarget, sizeof(sTarget));
	StripQuotes(sTarget);
	TrimString(sTarget);

	int iTarget = FindTarget(iClient, sTarget, true, false);

	if (iTarget == -1)
	{
		return Plugin_Handled;
	}

	if (iTarget == iClient)
	{
		Cel_ReplyToCommand(iClient, "You can't mute yourself.");
		return Plugin_Handled;
	}

	bool bMute = bUnmuteOnly ? false : !g_bMuted[iClient][iTarget];

	g_bMuted[iClient][iTarget] = bMute;

	SetListenOverride(iClient, iTarget, bMute ? Listen_No : Listen_Default);

	if (bMute)
	{
		Cel_ReplyToCommand(iClient, "You muted {green}%N{default}: you won't hear their voice or see their chat. Type {green}!pmute %N{default} again to unmute.", iTarget, iTarget);
	} else {
		Cel_ReplyToCommand(iClient, "You unmuted {green}%N{default}.", iTarget);
	}

	return Plugin_Handled;
}

//A chat message (SayText2) from a player someone muted is sent again a frame later to everyone else who should
//get it, unchanged. The original is blocked.
public Action Hook_SayText2(UserMsg umMsg, BfRead bfMsg, const int[] iPlayers, int iPlayersNum, bool bReliable, bool bInit)
{
	int iAuthor = bfMsg.ReadByte();

	if (iAuthor < 1 || iAuthor > MaxClients)
	{
		return Plugin_Continue;
	}

	bool bAnyMuted = false;

	for (int i = 0; i < iPlayersNum; i++)
	{
		if (g_bMuted[iPlayers[i]][iAuthor])
		{
			bAnyMuted = true;
			break;
		}
	}

	if (!bAnyMuted)
	{
		return Plugin_Continue;
	}

	// The rest of the message (the chat format name and its text), kept as it is.
	char sStrings[5][256];
	int iChat = bfMsg.ReadByte(), iStrings = 0;

	while (iStrings < 5 && bfMsg.BytesLeft > 0)
	{
		bfMsg.ReadString(sStrings[iStrings], sizeof(sStrings[]));
		iStrings++;
	}

	DataPack dpMsg = new DataPack();

	dpMsg.WriteCell(iAuthor);
	dpMsg.WriteCell(iChat);
	dpMsg.WriteCell(iStrings);

	for (int i = 0; i < iStrings; i++)
	{
		dpMsg.WriteString(sStrings[i]);
	}

	int iKeep = 0;

	for (int i = 0; i < iPlayersNum; i++)
	{
		if (!g_bMuted[iPlayers[i]][iAuthor])
		{
			iKeep++;
		}
	}

	dpMsg.WriteCell(iKeep);

	for (int i = 0; i < iPlayersNum; i++)
	{
		if (!g_bMuted[iPlayers[i]][iAuthor])
		{
			dpMsg.WriteCell(GetClientUserId(iPlayers[i]));
		}
	}

	RequestFrame(Frame_ResendSayText2, dpMsg);

	return Plugin_Handled;
}

public void Frame_ResendSayText2(DataPack dpMsg)
{
	char sStrings[5][256];
	int iClients[MAXPLAYERS], iCount = 0;

	dpMsg.Reset();

	int iAuthor = dpMsg.ReadCell(), iChat = dpMsg.ReadCell(), iStrings = dpMsg.ReadCell();

	for (int i = 0; i < iStrings; i++)
	{
		dpMsg.ReadString(sStrings[i], sizeof(sStrings[]));
	}

	int iKeep = dpMsg.ReadCell();

	for (int i = 0; i < iKeep; i++)
	{
		int iClient = GetClientOfUserId(dpMsg.ReadCell());

		if (iClient > 0 && IsClientInGame(iClient))
		{
			iClients[iCount++] = iClient;
		}
	}

	delete dpMsg;

	if (iCount < 1)
	{
		return;
	}

	BfWrite bfMsg = UserMessageToBfWrite(StartMessage("SayText2", iClients, iCount, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS));

	bfMsg.WriteByte(iAuthor);
	bfMsg.WriteByte(iChat);

	for (int i = 0; i < iStrings; i++)
	{
		bfMsg.WriteString(sStrings[i]);
	}

	EndMessage();
}

public void OnMapStart()
{
	Cel_PopulateCelCommands();
}

public void OnMapEnd()
{
	delete g_smCelCommands;
}

//Commands:
public Action Handle_Chat(int iClient, char[] sCommand, int iArgs)
{
	char sCommandString[MAX_MESSAGE_LENGTH];
	
	GetCmdArgString(sCommandString, sizeof(sCommandString));
	
	StripQuotes(sCommandString);
	
	if (sCommandString[0] == '!' || sCommandString[0] == '/') {
		ReplaceString(sCommandString, sizeof(sCommandString), (sCommandString[0] == '!') ? "!" : "/", "v_");
		
		if(Cel_IsCelCommand(sCommandString))
		{
			ReplySource rsOldReplySrc = GetCmdReplySource();
			
			SetCmdReplySource(SM_REPLY_TO_CHAT);
			
			FakeClientCommand(iClient, sCommandString);
			
			SetCmdReplySource(rsOldReplySrc);
		}
		else
		{
			//Not a CelMod command. SourceMod's own chat commands (!rtv, !admin, ...) are sm_ commands that it runs
			//itself, so only a command that is neither is called invalid.
			char sWord[64], sSourceMod[72];
			
			strcopy(sWord, sizeof(sWord), sCommandString[2]);
			
			int iSpace = FindCharInString(sWord, ' ');
			
			if (iSpace != -1)
			{
				sWord[iSpace] = '\0';
			}
			
			FormatEx(sSourceMod, sizeof(sSourceMod), "sm_%s", sWord);
			
			//"!blastdoor3" spawns a prop (celmod.sp's own chat listener, which sees the message too), so prop names and
			//shop props aren't invalid either.
			char sSpawn[256];
			
			if (sWord[0] != '\0' && !CommandExists(sSourceMod) && !Cel_CheckSpawnDB(sWord, sSpawn, sizeof(sSpawn))
				&& Cel_CheckShopProp(iClient, sWord, sSpawn, sizeof(sSpawn)) == 0)
			{
				Cel_PrintToChat(iClient, "Invalid command. Type {green}!cmds{default} for a command list.");
			}
		}
		
		return Plugin_Handled;
	}else if (IsChatTrigger()) {
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Handle_Noclip(int iClient, char[] sCommand, int iArgs)
{
	FakeClientCommand(iClient, "v_fly");
	
	return Plugin_Handled;
}

//Natives:
public int Native_IsCelCommand(Handle hPlugin, int iNumParams)
{
	char sCommand[MAX_MESSAGE_LENGTH], sCommandSplit[2][MAX_MESSAGE_LENGTH];
	int iValue;
	
	GetNativeString(1, sCommand, sizeof(sCommand));
	
	ExplodeString(sCommand, " ", sCommandSplit, 2, sizeof(sCommandSplit[]), false);
	
	CStrToLower(sCommandSplit[0]);
	
	return g_smCelCommands.GetValue(sCommandSplit[0], iValue);
}

public int Native_NotLooking(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	Cel_ReplyToCommand(iClient, "%t", "NotLooking");
	
	return true;
}

public int Native_NotYours(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	int iEntity = GetNativeCell(2);
	
	Cel_ReplyToCommandEntity(iClient, iEntity, "%t", "NotYours");
	
	return true;
}

public int Native_PlayChatMessageSound(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	ClientCommand(iClient, "play npc/stalker/stalker_footstep_%s1", GetRandomInt(0, 1) ? "left" : "right");
	
	return true;
}

public int Native_PrintToChat(Handle hPlugin, int iNumParams)
{
	char sBuffer[MAX_MESSAGE_LENGTH];
	
	int iPlayer = GetNativeCell(1), iWritten;
	
	FormatNativeString(0, 2, 3, sizeof(sBuffer), iWritten, sBuffer);
	
	CPrintToChat(iPlayer, "{blue}|CelMod|{default} %s", sBuffer);
	
	Cel_PlayChatMessageSound(iPlayer);
	
	return true;
}

public int Native_PrintToChatAll(Handle hPlugin, int iNumParams)
{
	char sBuffer[MAX_MESSAGE_LENGTH];
	
	int iWritten;
	
	FormatNativeString(0, 1, 2, sizeof(sBuffer), iWritten, sBuffer);
	
	CPrintToChatAll("{blue}|CM|{default} %s", sBuffer);
	
	return true;
}

public int Native_ReplyToCommand(Handle hPlugin, int iNumParams)
{
	char sBuffer[MAX_MESSAGE_LENGTH];
	
	int iPlayer = GetNativeCell(1), iWritten;
	
	FormatNativeString(0, 2, 3, sizeof(sBuffer), iWritten, sBuffer);
	
	ReplaceString(sBuffer, sizeof(sBuffer), "[tag]", GetCmdReplySource() == SM_REPLY_TO_CONSOLE ? "v_" : "!", true);
	
	if (GetCmdReplySource() == SM_REPLY_TO_CONSOLE)
	{
		CRemoveTags(sBuffer, sizeof(sBuffer));
		
		PrintToConsole(iPlayer, "|CelMod| %s", sBuffer);
	} else {
		CPrintToChat(iPlayer, "{blue}|CelMod|{default} %s", sBuffer);
		
		Cel_PlayChatMessageSound(iPlayer);
	}
	
	return true;
}

public int Native_ReplyToCommandEntity(Handle hPlugin, int iNumParams)
{
	char sBuffer[MAX_MESSAGE_LENGTH];
	
	int iEntity = GetNativeCell(2), iPlayer = GetNativeCell(1), iWritten;
	
	FormatNativeString(0, 3, 4, sizeof(sBuffer), iWritten, sBuffer);
	
	ReplaceString(sBuffer, sizeof(sBuffer), "[tag]", GetCmdReplySource() == SM_REPLY_TO_CONSOLE ? "v_" : "!", true);
	
	Cel_UpdateEntityMessageTags(iEntity, sBuffer, sizeof(sBuffer));
	
	if (GetCmdReplySource() == SM_REPLY_TO_CONSOLE)
	{
		CRemoveTags(sBuffer, sizeof(sBuffer));
		
		PrintToConsole(iPlayer, "|CelMod| %s", sBuffer);
	} else {
		CPrintToChat(iPlayer, "{blue}|CelMod|{default} %s", sBuffer);
		
		Cel_PlayChatMessageSound(iPlayer);
	}
	
	return true;
}

//Stocks:
stock void Cel_PopulateCelCommands()
{
	char sCMD[2][MAX_MESSAGE_LENGTH];
	Handle hCommandIter = GetCommandIterator();
	int iFlags;
	
	g_smCelCommands = new StringMap();
	
	while (ReadCommandIterator(hCommandIter, sCMD[0], sizeof(sCMD[]), iFlags, sCMD[1], sizeof(sCMD[])))
	{
		if (StrContains(sCMD[1], "|CelMod|", true) != -1)
		{
			g_smCelCommands.SetValue(sCMD[0], 1);
		}
	}
	
	CloseHandle(hCommandIter);
}

stock void Cel_UpdateEntityMessageTags(int iEntity, char[] sBuffer, int iMaxLength)
{
	char sName[128];
	
	if(Cel_CheckEntityType(iEntity, "ammo"))
	{
		Cel_GetAmmoTypeName(Cel_GetAmmoType(iEntity), sName, sizeof(sName));
		ReplaceString(sBuffer, iMaxLength, "[ammo]", sName, false);
	}
	if(Cel_CheckEntityType(iEntity, "ammocrate"))
	{
		Cel_GetAmmoCrateTypeName(Cel_GetAmmoCrateType(iEntity), sName, sizeof(sName));
		ReplaceString(sBuffer, iMaxLength, "[ammocrate]", sName, false);
	}
	if(Cel_CheckEntityType(iEntity, "charger"))
	{
		Cel_GetChargerTypeName(Cel_GetChargerType(iEntity), sName, sizeof(sName));
		ReplaceString(sBuffer, iMaxLength, "[charger]", sName, false);
	}
	if(Cel_CheckEntityType(iEntity, "weaponspwner"))
	{
		Cel_GetWeaponTypeName(Cel_GetWeaponType(iEntity), sName, sizeof(sName));
		ReplaceString(sBuffer, iMaxLength, "[weapon]", sName, false);
	}
	if(Cel_CheckEntityType(iEntity, "physics") || Cel_CheckEntityType(iEntity, "dynamic") || Cel_CheckEntityType(iEntity, "doll"))
	{
		Cel_GetPropName(iEntity, sName, sizeof(sName));
		ReplaceString(sBuffer, iMaxLength, "[propname]", sName, false);
	}
	if(Cel_CheckEntityType(iEntity, "internet"))
	{
		Cel_GetWeaponTypeName(Cel_GetWeaponType(iEntity), sName, sizeof(sName));
		ReplaceString(sBuffer, iMaxLength, "[url]", sName, false);
	}
	
	Cel_GetEntityCatagoryName(iEntity, sName, sizeof(sName));
	ReplaceString(sBuffer, iMaxLength, "[catagory]", sName, false);
	
	Cel_GetEntityTypeName(Cel_GetEntityType(iEntity), sName, sizeof(sName));
	ReplaceString(sBuffer, iMaxLength, "[type]", sName, false);
	
	GetClientName(Cel_GetOwner(iEntity), sName, sizeof(sName));
	ReplaceString(sBuffer, iMaxLength, "[owner]", sName, false);
}

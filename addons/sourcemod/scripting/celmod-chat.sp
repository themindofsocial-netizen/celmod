#pragma semicolon 1

#include <celmod>

#pragma newdecls required

bool g_bLate;

StringMap g_smCelCommands;

//!pmute: g_bMuted[listener][talker], only for that listener: no voice and no chat from the talker.
bool g_bMuted[MAXPLAYERS + 1][MAXPLAYERS + 1];

//!pungag: SteamID -> when the gag ends (unix time, 0 = never). Kept in data/celmod/gags.txt so it lasts across maps
//and reconnects.
StringMap g_smGags;

//!punfreeze: players frozen in place by an admin (until unfrozen or they leave; dying doesn't free them).
bool g_bPunFrozen[MAXPLAYERS + 1];
#define FREEZE_SOUND "physics/glass/glass_impact_bullet4.wav"
char g_sGagFile[PLATFORM_MAX_PATH];

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
	
	//Admin punishments.
	RegAdminCmd("v_pungag", Command_PunGag, ADMFLAG_CHAT, "|CelMod| Stops a player chatting: !pungag <name> [minutes, 0 = until lifted] [reason].");
	RegAdminCmd("v_punungag", Command_PunUngag, ADMFLAG_CHAT, "|CelMod| Lifts a gag: !punungag <name>.");
	RegAdminCmd("v_punkick", Command_PunKick, ADMFLAG_KICK, "|CelMod| Kicks a player: !punkick <name> [reason].");
	RegAdminCmd("v_punfreeze", Command_PunFreeze, ADMFLAG_SLAY, "|CelMod| Freezes a player in place (they can't move or shoot), or unfreezes them: !punfreeze <name>.");
	RegAdminCmd("v_goto", Command_Goto, ADMFLAG_SLAY, "|CelMod| Teleports you to a player: !goto <name>.");
	RegAdminCmd("v_bring", Command_Bring, ADMFLAG_SLAY, "|CelMod| Teleports a player to you: !bring <name>.");
	RegAdminCmd("v_bringall", Command_BringAll, ADMFLAG_SLAY, "|CelMod| Teleports every player to you.");
	RegAdminCmd("v_punban", Command_PunBan, ADMFLAG_BAN, "|CelMod| Bans a player: !punban <name> <minutes, 0 = forever> [reason].");
	
	HookEvent("player_spawn", Event_FrozenSpawn);
	AddCommandListener(Listener_FrozenFly, "v_fly");
	AddCommandListener(Listener_FrozenFly, "noclip");
	AddCommandListener(Listener_FrozenFly, "kill");
	AddCommandListener(Listener_FrozenFly, "explode");
	
	g_smGags = new StringMap();
	BuildPath(Path_SM, g_sGagFile, sizeof(g_sGagFile), "data/celmod/gags.txt");
	LoadGags();

	// Chat from a muted player is held back from the players who muted them.
	UserMsg umSayText2 = GetUserMessageId("SayText2");

	if (umSayText2 != INVALID_MESSAGE_ID && GetUserMessageType() == UM_BitBuf)
	{
		HookUserMessage(umSayText2, Hook_SayText2, true);
	}

	LoadTranslations("common.phrases");

	AddCommandListener(Handle_Noclip, "noclip");
	
	//SourceMod's nextmap plugin answers "[SM] Next Map: ...": CelMod answers instead, in its own style.
	AddCommandListener(Listener_NextMap, "sm_nextmap");
	AddCommandListener(Listener_NextMap, "nextmap");
	AddCommandListener(Handle_Chat, "say");
	AddCommandListener(Handle_Chat, "say_team");
	
	ConCommand_RemoveFlags("noclip", FCVAR_CHEAT);
}

public void OnClientDisconnect(int iClient)
{
	g_bPunFrozen[iClient] = false;
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
		//Only the leading ! or / becomes v_: the rest is left alone, so "!text hi!" keeps its last "!".
		Format(sCommandString, sizeof(sCommandString), "v_%s", sCommandString[1]);
		
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
	
	//A gagged player can still use commands, but nobody sees their chat.
	int iLeft;
	
	if (iClient > 0 && GagMinutesLeft(iClient, iLeft))
	{
		if (iLeft > 0)
		{
			Cel_PrintToChat(iClient, "You are gagged for {green}%d{default} more minute%s.", iLeft, iLeft == 1 ? "" : "s");
		} else {
			Cel_PrintToChat(iClient, "You are gagged until an admin lifts it.");
		}
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

//Punishments:
void LoadGags()
{
	g_smGags.Clear();
	
	KeyValues kvGags = new KeyValues("Gags");
	
	if (kvGags.ImportFromFile(g_sGagFile) && kvGags.GotoFirstSubKey(false))
	{
		char sAuth[64];
		int iNow = GetTime();
		
		do
		{
			kvGags.GetSectionName(sAuth, sizeof(sAuth));
			
			int iUntil = kvGags.GetNum(NULL_STRING, 0);
			
			if (iUntil == 0 || iUntil > iNow)
			{
				g_smGags.SetValue(sAuth, iUntil);
			}
		} while (kvGags.GotoNextKey(false));
	}
	
	delete kvGags;
}

void SaveGags()
{
	KeyValues kvGags = new KeyValues("Gags");
	StringMapSnapshot smsGags = g_smGags.Snapshot();
	char sAuth[64];
	int iUntil;
	
	for (int i = 0; i < smsGags.Length; i++)
	{
		smsGags.GetKey(i, sAuth, sizeof(sAuth));
		
		if (g_smGags.GetValue(sAuth, iUntil))
		{
			kvGags.SetNum(sAuth, iUntil);
		}
	}
	
	delete smsGags;
	
	kvGags.ExportToFile(g_sGagFile);
	delete kvGags;
}

//True when the player is gagged; iLeft is the minutes left (0 = until it is lifted).
bool GagMinutesLeft(int iClient, int &iLeft)
{
	char sAuth[64];
	int iUntil;
	
	if (!GetClientAuthId(iClient, AuthId_Steam2, sAuth, sizeof(sAuth)) || !g_smGags.GetValue(sAuth, iUntil))
	{
		return false;
	}
	
	if (iUntil == 0)
	{
		iLeft = 0;
		return true;
	}
	
	int iNow = GetTime();
	
	if (iUntil <= iNow)
	{
		g_smGags.Remove(sAuth);
		SaveGags();
		return false;
	}
	
	iLeft = (iUntil - iNow + 59) / 60;
	return true;
}

//The text after the first iSkip arguments, used as the reason.
void GetReason(int iSkip, char[] sReason, int iMaxLength, const char[] sDefault)
{
	char sArgs[256];
	int iPos = 0;
	
	GetCmdArgString(sArgs, sizeof(sArgs));
	
	for (int i = 0; i < iSkip && iPos != -1; i++)
	{
		char sSkip[128];
		int iNext = BreakString(sArgs[iPos], sSkip, sizeof(sSkip));
		
		iPos = (iNext == -1) ? -1 : iPos + iNext;
	}
	
	if (iPos == -1 || sArgs[iPos] == '\0')
	{
		strcopy(sReason, iMaxLength, sDefault);
	} else {
		strcopy(sReason, iMaxLength, sArgs[iPos]);
		StripQuotes(sReason);
		TrimString(sReason);
	}
}

void FormatLength(int iMinutes, char[] sLength, int iMaxLength)
{
	if (iMinutes <= 0)
	{
		strcopy(sLength, iMaxLength, "for good");
	} else if (iMinutes % 1440 == 0)
	{
		FormatEx(sLength, iMaxLength, "for %d day%s", iMinutes / 1440, iMinutes == 1440 ? "" : "s");
	} else if (iMinutes % 60 == 0)
	{
		FormatEx(sLength, iMaxLength, "for %d hour%s", iMinutes / 60, iMinutes == 60 ? "" : "s");
	} else {
		FormatEx(sLength, iMaxLength, "for %d minute%s", iMinutes, iMinutes == 1 ? "" : "s");
	}
}

public Action Command_PunGag(int iClient, int iArgs)
{
	char sTarget[64], sMinutes[16], sReason[128], sAuth[64], sLength[32];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}!pungag <name> [minutes, 0 = until lifted] [reason]{default}");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	int iTarget = FindTarget(iClient, sTarget, true, true);
	
	if (iTarget == -1)
	{
		return Plugin_Handled;
	}
	
	int iMinutes = 0, iSkip = 1;
	
	if (iArgs >= 2)
	{
		GetCmdArg(2, sMinutes, sizeof(sMinutes));
		
		if (StringToIntEx(sMinutes, iMinutes) == strlen(sMinutes) && sMinutes[0] != '\0')
		{
			iSkip = 2;
		} else {
			iMinutes = 0;
		}
	}
	
	if (iMinutes < 0)
	{
		iMinutes = 0;
	}
	
	GetReason(iSkip, sReason, sizeof(sReason), "No reason given");
	
	if (!GetClientAuthId(iTarget, AuthId_Steam2, sAuth, sizeof(sAuth)))
	{
		Cel_ReplyToCommand(iClient, "{green}%N{default} isn't signed in to Steam yet; try again in a moment.", iTarget);
		return Plugin_Handled;
	}
	
	g_smGags.SetValue(sAuth, iMinutes > 0 ? GetTime() + iMinutes * 60 : 0);
	SaveGags();
	
	FormatLength(iMinutes, sLength, sizeof(sLength));
	
	Cel_PrintToChatAll("{green}%N{default} was gagged %s by an admin. Reason: {green}%s{default}", iTarget, iMinutes > 0 ? sLength : "until it's lifted", sReason);
	LogAction(iClient, iTarget, "\"%L\" gagged \"%L\" (minutes \"%d\") (reason \"%s\")", iClient, iTarget, iMinutes, sReason);
	
	return Plugin_Handled;
}

public Action Command_PunUngag(int iClient, int iArgs)
{
	char sTarget[64], sAuth[64];
	int iUntil;
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}!punungag <name>{default}");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	int iTarget = FindTarget(iClient, sTarget, true, false);
	
	if (iTarget == -1)
	{
		return Plugin_Handled;
	}
	
	if (!GetClientAuthId(iTarget, AuthId_Steam2, sAuth, sizeof(sAuth)) || !g_smGags.GetValue(sAuth, iUntil))
	{
		Cel_ReplyToCommand(iClient, "{green}%N{default} isn't gagged.", iTarget);
		return Plugin_Handled;
	}
	
	g_smGags.Remove(sAuth);
	SaveGags();
	
	Cel_PrintToChatAll("{green}%N{default} can chat again.", iTarget);
	LogAction(iClient, iTarget, "\"%L\" ungagged \"%L\"", iClient, iTarget);
	
	return Plugin_Handled;
}

public Action Command_PunKick(int iClient, int iArgs)
{
	char sTarget[64], sReason[128];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}!punkick <name> [reason]{default}");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	int iTarget = FindTarget(iClient, sTarget, false, true);
	
	if (iTarget == -1)
	{
		return Plugin_Handled;
	}
	
	GetReason(1, sReason, sizeof(sReason), "Kicked by an admin");
	
	Cel_PrintToChatAll("{green}%N{default} was kicked. Reason: {green}%s{default}", iTarget, sReason);
	LogAction(iClient, iTarget, "\"%L\" kicked \"%L\" (reason \"%s\")", iClient, iTarget, sReason);
	
	KickClient(iTarget, "|CelMod| %s", sReason);
	
	return Plugin_Handled;
}

void ApplyPunFreeze(int iTarget, bool bFrozen)
{
	g_bPunFrozen[iTarget] = bFrozen;
	
	if (!IsClientInGame(iTarget) || !IsPlayerAlive(iTarget))
	{
		return;
	}
	
	SetEntityMoveType(iTarget, bFrozen ? MOVETYPE_NONE : MOVETYPE_WALK);
	SetEntityRenderMode(iTarget, bFrozen ? RENDER_TRANSCOLOR : RENDER_NORMAL);
	SetEntityRenderColor(iTarget, bFrozen ? 0 : 255, bFrozen ? 128 : 255, 255, bFrozen ? 192 : 255);
	
	if (bFrozen)
	{
		float fStop[3];
		
		TeleportEntity(iTarget, NULL_VECTOR, NULL_VECTOR, fStop);
	}
	
	PrecacheSound(FREEZE_SOUND);
	EmitSoundToAll(FREEZE_SOUND, iTarget);
}

public Action Command_PunFreeze(int iClient, int iArgs)
{
	char sTarget[64];
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}!punfreeze <name>{default} (again to unfreeze them)");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	
	int iTarget = FindTarget(iClient, sTarget, false, true);
	
	if (iTarget == -1)
	{
		return Plugin_Handled;
	}
	
	bool bFreeze = !g_bPunFrozen[iTarget];
	
	ApplyPunFreeze(iTarget, bFreeze);
	
	if (bFreeze)
	{
		Cel_PrintToChatAll("{green}%N{default} was frozen by an admin.", iTarget);
		Cel_PrintToChat(iTarget, "You're frozen: you can't move or shoot until an admin unfreezes you.");
	} else {
		Cel_PrintToChatAll("{green}%N{default} was unfrozen.", iTarget);
	}
	
	LogAction(iClient, iTarget, "\"%L\" %s \"%L\"", iClient, bFreeze ? "froze" : "unfroze", iTarget);
	
	return Plugin_Handled;
}

//!goto, !bring and !bringall: players land beside each other on a free spot (never inside a wall, a prop or another
//player), facing the one they were sent to.
public Action Command_Goto(int iClient, int iArgs)
{
	if (!IsTeleportAdmin(iClient))
	{
		return Plugin_Handled;
	}

	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}!goto <name>{default}");
		return Plugin_Handled;
	}

	char sTarget[64];

	GetCmdArg(1, sTarget, sizeof(sTarget));

	int iTarget = FindTarget(iClient, sTarget, false, false);

	if (iTarget == -1)
	{
		return Plugin_Handled;
	}

	if (iTarget == iClient || !IsPlayerAlive(iTarget))
	{
		Cel_ReplyToCommand(iClient, "You can't go to {green}%N{default} right now.", iTarget);
		return Plugin_Handled;
	}

	if (!SendPlayerTo(iClient, iTarget, 0))
	{
		Cel_ReplyToCommand(iClient, "There's no room next to {green}%N{default}.", iTarget);
		return Plugin_Handled;
	}

	Cel_ReplyToCommand(iClient, "You went to {green}%N{default}.", iTarget);
	LogAction(iClient, iTarget, "\"%L\" teleported to \"%L\"", iClient, iTarget);

	return Plugin_Handled;
}

public Action Command_Bring(int iClient, int iArgs)
{
	if (!IsTeleportAdmin(iClient))
	{
		return Plugin_Handled;
	}

	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}!bring <name>{default}");
		return Plugin_Handled;
	}

	char sTarget[64];

	GetCmdArg(1, sTarget, sizeof(sTarget));

	int iTarget = FindTarget(iClient, sTarget, false, true);

	if (iTarget == -1)
	{
		return Plugin_Handled;
	}

	if (iTarget == iClient || !IsPlayerAlive(iTarget))
	{
		Cel_ReplyToCommand(iClient, "You can't bring {green}%N{default} right now.", iTarget);
		return Plugin_Handled;
	}

	if (!SendPlayerTo(iTarget, iClient, 0))
	{
		Cel_ReplyToCommand(iClient, "There's no room next to you for {green}%N{default}.", iTarget);
		return Plugin_Handled;
	}

	Cel_ReplyToCommand(iClient, "You brought {green}%N{default} to you.", iTarget);
	Cel_PrintToChat(iTarget, "An admin, {green}%N{default}, brought you to them.", iClient);
	LogAction(iClient, iTarget, "\"%L\" brought \"%L\"", iClient, iTarget);

	return Plugin_Handled;
}

public Action Command_BringAll(int iClient, int iArgs)
{
	if (!IsTeleportAdmin(iClient))
	{
		return Plugin_Handled;
	}

	int iBrought, iNoRoom, iSlot = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == iClient || !IsClientInGame(i) || !IsPlayerAlive(i) || !CanUserTarget(iClient, i))
		{
			continue;
		}

		// Each one a step further round the circle, so they don't all try the same spot.
		if (SendPlayerTo(i, iClient, iSlot))
		{
			iBrought++;

			Cel_PrintToChat(i, "An admin, {green}%N{default}, brought everyone to them.", iClient);
		} else {
			iNoRoom++;
		}

		iSlot++;
	}

	if (iNoRoom > 0)
	{
		Cel_ReplyToCommand(iClient, "You brought {green}%d{default} player%s to you ({green}%d{default} didn't fit: try somewhere roomier).", iBrought, iBrought == 1 ? "" : "s", iNoRoom);
	} else {
		Cel_ReplyToCommand(iClient, "You brought {green}%d{default} player%s to you.", iBrought, iBrought == 1 ? "" : "s");
	}

	LogAction(iClient, -1, "\"%L\" brought everyone (%d players)", iClient, iBrought);

	return Plugin_Handled;
}

bool IsTeleportAdmin(int iClient)
{
	if (iClient < 1 || !IsClientInGame(iClient) || !IsPlayerAlive(iClient))
	{
		Cel_ReplyToCommand(iClient, "You need to be alive in the game to do that.");
		return false;
	}

	return true;
}

//Moves iPlayer to a free spot beside iTo, facing them. iSlot picks the spot: round iTo in rings, the first ring right
//in front of where iTo looks. False if there's nowhere to stand.
bool SendPlayerTo(int iPlayer, int iTo, int iSlot)
{
	float fCenter[3], fLook[3], fMins[3] = { -16.0, -16.0, 0.0 }, fMaxs[3] = { 16.0, 16.0, 72.0 };

	GetClientAbsOrigin(iTo, fCenter);
	GetClientEyeAngles(iTo, fLook);

	// Ducking players are shorter, but they stand up once they're moved: room for a standing player.
	for (int iTry = iSlot; iTry < iSlot + 48; iTry++)
	{
		int iRing = iTry / 8;
		float fYaw = fLook[1] + float(iTry % 8) * 45.0 + float(iRing) * 22.5;
		float fDistance = 56.0 + float(iRing) * 44.0;
		float fSpot[3], fAbove[3];

		fSpot[0] = fCenter[0] + Cosine(DegToRad(fYaw)) * fDistance;
		fSpot[1] = fCenter[1] + Sine(DegToRad(fYaw)) * fDistance;
		fSpot[2] = fCenter[2] + 8.0;

		// Not through a wall: the way from iTo to the spot is clear.
		fAbove = fCenter;
		fAbove[2] += 8.0;

		TR_TraceHullFilter(fAbove, fSpot, fMins, fMaxs, MASK_PLAYERSOLID, Filter_NotPlayers, iPlayer);

		if (TR_DidHit())
		{
			continue;
		}

		// And it's free to stand in.
		TR_TraceHullFilter(fSpot, fSpot, fMins, fMaxs, MASK_PLAYERSOLID, Filter_NotSelf, iPlayer);

		if (TR_DidHit())
		{
			continue;
		}

		float fFace[3], fDir[3], fZero[3];

		SubtractVectors(fCenter, fSpot, fDir);
		GetVectorAngles(fDir, fFace);
		fFace[0] = 0.0;
		fFace[2] = 0.0;

		TeleportEntity(iPlayer, fSpot, fFace, fZero);

		return true;
	}

	return false;
}

public bool Filter_NotPlayers(int iEntity, int iContentsMask, any aData)
{
	return iEntity > MaxClients;
}

public bool Filter_NotSelf(int iEntity, int iContentsMask, any aData)
{
	return iEntity != aData;
}

//Frozen players can't fly or kill themselves out of it.
public Action Listener_FrozenFly(int iClient, const char[] sCommand, int iArgs)
{
	if (iClient > 0 && iClient <= MaxClients && g_bPunFrozen[iClient])
	{
		Cel_PrintToChat(iClient, "You're frozen: you can't do that until an admin unfreezes you.");
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

//A frozen player who dies stays frozen when they come back.
public void Event_FrozenSpawn(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(eEvent.GetInt("userid"));
	
	if (iClient > 0 && g_bPunFrozen[iClient])
	{
		CreateTimer(0.2, Timer_RefreezeSpawn, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_RefreezeSpawn(Handle hTimer, any iUserId)
{
	int iClient = GetClientOfUserId(iUserId);
	
	if (iClient > 0 && g_bPunFrozen[iClient])
	{
		ApplyPunFreeze(iClient, true);
	}
	
	return Plugin_Stop;
}

//Frozen: no shooting, using or jumping either.
public Action OnPlayerRunCmd(int iClient, int &iButtons)
{
	if (g_bPunFrozen[iClient] && (iButtons & (IN_ATTACK | IN_ATTACK2 | IN_USE | IN_JUMP | IN_RELOAD)))
	{
		iButtons &= ~(IN_ATTACK | IN_ATTACK2 | IN_USE | IN_JUMP | IN_RELOAD);
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

public Action Command_PunBan(int iClient, int iArgs)
{
	char sTarget[64], sMinutes[16], sReason[128], sLength[32];
	
	if (iArgs < 2)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}!punban <name> <minutes, 0 = forever> [reason]{default}");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, sTarget, sizeof(sTarget));
	GetCmdArg(2, sMinutes, sizeof(sMinutes));
	
	int iMinutes;
	
	if (StringToIntEx(sMinutes, iMinutes) != strlen(sMinutes) || iMinutes < 0)
	{
		Cel_ReplyToCommand(iClient, "The ban length is in minutes: {green}0{default} bans for good. Usage: {green}!punban <name> <minutes> [reason]{default}");
		return Plugin_Handled;
	}
	
	int iTarget = FindTarget(iClient, sTarget, true, true);
	
	if (iTarget == -1)
	{
		return Plugin_Handled;
	}
	
	GetReason(2, sReason, sizeof(sReason), "Banned by an admin");
	FormatLength(iMinutes, sLength, sizeof(sLength));
	
	Cel_PrintToChatAll("{green}%N{default} was banned %s. Reason: {green}%s{default}", iTarget, sLength, sReason);
	LogAction(iClient, iTarget, "\"%L\" banned \"%L\" (minutes \"%d\") (reason \"%s\")", iClient, iTarget, iMinutes, sReason);
	
	char sKick[192];
	
	FormatEx(sKick, sizeof(sKick), "|CelMod| Banned %s: %s", sLength, sReason);
	
	BanClient(iTarget, iMinutes, BANFLAG_AUTO, sReason, sKick, "sm_ban", iClient);
	
	return Plugin_Handled;
}

public Action Listener_NextMap(int iClient, const char[] sCommand, int iArgs)
{
	ReplyNextMap(iClient, false);
	return Plugin_Handled;
}

//The word "nextmap" typed in chat (SourceMod answers it to everyone).
public Action OnClientSayCommand(int iClient, const char[] sCommand, const char[] sArgs)
{
	if (StrEqual(sArgs, "nextmap", false))
	{
		ReplyNextMap(iClient, true);
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

void ReplyNextMap(int iClient, bool bEveryone)
{
	char sMap[PLATFORM_MAX_PATH];
	
	if (!GetNextMap(sMap, sizeof(sMap)) || sMap[0] == '\0')
	{
		strcopy(sMap, sizeof(sMap), "not chosen yet");
	}
	
	if (bEveryone)
	{
		Cel_PrintToChatAll("Next map is {green}%s{default}.", sMap);
	} else if (iClient > 0 && IsClientInGame(iClient))
	{
		Cel_PrintToChat(iClient, "Next map is {green}%s{default}.", sMap);
	} else {
		PrintToServer("|CelMod| Next map is %s.", sMap);
	}
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
	
	//Chat messages show commands with "!".
	ReplaceString(sBuffer, sizeof(sBuffer), "[tag]", "!", true);
	
	CPrintToChat(iPlayer, "{blue}|CelMod|{default} %s", sBuffer);
	
	Cel_PlayChatMessageSound(iPlayer);
	
	return true;
}

public int Native_PrintToChatAll(Handle hPlugin, int iNumParams)
{
	char sBuffer[MAX_MESSAGE_LENGTH];
	
	int iWritten;
	
	FormatNativeString(0, 1, 2, sizeof(sBuffer), iWritten, sBuffer);
	
	ReplaceString(sBuffer, sizeof(sBuffer), "[tag]", "!", true);
	
	CPrintToChatAll("{blue}|CelMod|{default} %s", sBuffer);
	
	return true;
}

//A reply always reaches chat: commands run from a key bind (+copy, +move) count as console commands, and their
//replies used to go to the console only. A command typed in the console also gets the console copy, with v_.
void SendReply(int iPlayer, char[] sBuffer, int iMaxLength)
{
	if (iPlayer < 1 || iPlayer > MaxClients || !IsClientInGame(iPlayer))
	{
		ReplaceString(sBuffer, iMaxLength, "[tag]", "v_", true);
		CRemoveTags(sBuffer, iMaxLength);
		PrintToServer("|CelMod| %s", sBuffer);
		return;
	}
	
	char sChat[MAX_MESSAGE_LENGTH];
	
	strcopy(sChat, sizeof(sChat), sBuffer);
	ReplaceString(sChat, sizeof(sChat), "[tag]", "!", true);
	
	CPrintToChat(iPlayer, "{blue}|CelMod|{default} %s", sChat);
	Cel_PlayChatMessageSound(iPlayer);
	
	if (GetCmdReplySource() == SM_REPLY_TO_CONSOLE)
	{
		ReplaceString(sBuffer, iMaxLength, "[tag]", "v_", true);
		CRemoveTags(sBuffer, iMaxLength);
		PrintToConsole(iPlayer, "|CelMod| %s", sBuffer);
	}
}

public int Native_ReplyToCommand(Handle hPlugin, int iNumParams)
{
	char sBuffer[MAX_MESSAGE_LENGTH];
	
	int iPlayer = GetNativeCell(1), iWritten;
	
	FormatNativeString(0, 2, 3, sizeof(sBuffer), iWritten, sBuffer);
	
	SendReply(iPlayer, sBuffer, sizeof(sBuffer));
	
	return true;
}

public int Native_ReplyToCommandEntity(Handle hPlugin, int iNumParams)
{
	char sBuffer[MAX_MESSAGE_LENGTH];
	
	int iEntity = GetNativeCell(2), iPlayer = GetNativeCell(1), iWritten;
	
	FormatNativeString(0, 3, 4, sizeof(sBuffer), iWritten, sBuffer);
	
	Cel_UpdateEntityMessageTags(iEntity, sBuffer, sizeof(sBuffer));
	
	SendReply(iPlayer, sBuffer, sizeof(sBuffer));
	
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

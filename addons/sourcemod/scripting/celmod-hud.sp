#pragma semicolon 1

#include <celmod>

#pragma newdecls required

ArrayList g_alCommands;

bool g_bHudEnable;
bool g_bHudLeft[MAXPLAYERS + 1];
bool g_bFeedOff[MAXPLAYERS + 1]; //!feed: the command feed (history at the top of the screen) hidden for this player

ConVar g_cvHudEnable;

Handle g_hCommandTimer;
Handle g_hHudTimer;

int g_iClientColor[MAXPLAYERS + 1][4];
bool g_bHudColorChosen[MAXPLAYERS + 1]; //!hudcolor: a colour the player picked (kept, never re-randomized)

char g_sLabel[MAXENTITIES + 1][48]; //!label: a name given to a button or cel, shown when it's looked at

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	CreateNative("Cel_ChooseHudColor", Native_ChooseHudColor);
	CreateNative("Cel_GetHudColor", Native_GetHudColor);
	CreateNative("Cel_SendHudMessage", Native_SendHudMessage);
	CreateNative("Cel_SetHudColor", Native_SetHudColor);
	
	MarkNativeAsOptional("Cel_GetTriggerLink");
	
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "|CelMod| Player HUD",
	author = CEL_AUTHOR,
	description = "Creates and controls the custom player hud.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{
	LoadTranslations("celmod.phrases");
	
	g_cvHudEnable = CreateConVar("cm_show_hud", "1", "Shows/hides the hud for all players.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	g_cvHudEnable.AddChangeHook(CMHud_OnConVarChanged);
	
	g_bHudEnable = view_as<bool>(g_cvHudEnable.IntValue);
	
	AutoExecConfig(true, "celmod.hud");
	
	AddCommandListener(Handle_Chat, "say");
	AddCommandListener(Handle_Chat, "say_team");
	
	RegConsoleCmd("v_hudcolor", Command_HudColor, "|CelMod| Changes the colour of your HUD text: !hudcolor <colour or r g b>, or random.");
	RegConsoleCmd("v_switch", Command_Switch, "|CelMod| Switches the side the hud is on the screen.");
	RegConsoleCmd("v_label", Command_Label, "|CelMod| Names the button or cel you are looking at, shown when anyone looks at it: !label <name>, or !label off.");
	RegConsoleCmd("v_feed", Command_Feed, "|CelMod| Turns the command feed (the list of recent commands) on or off.");
}

public void OnMapStart()
{
	g_hCommandTimer = CreateTimer(0.1, Timer_CommandHUD, _, TIMER_REPEAT);
	g_hHudTimer = CreateTimer(0.1, Timer_HUD, _, TIMER_REPEAT);
	
	g_alCommands = new ArrayList(6);
}

public void OnMapEnd()
{
	CloseHandle(g_hCommandTimer);
	CloseHandle(g_hHudTimer);
	
	g_alCommands.Clear();
	
	g_alCommands.Close();
}

//Read from the player's files once Steam has confirmed them.
public void OnClientPostAdminCheck(int iClient)
{
	if(Cel_GetClientSettingInt(iClient, "hud-pos-left") != -1)
	{
		g_bHudLeft[iClient] = view_as<bool>(Cel_GetClientSettingInt(iClient, "hud-pos-left"));
	}else{
		Cel_SetClientSettingInt(iClient, "hud-pos-left", 0);
	}
	
	g_bFeedOff[iClient] = (Cel_GetClientSettingInt(iClient, "hud-feed-off") == 1);
	
	//The colour picked with !hudcolor, saved as (r << 16 | g << 8 | b) + 1 (0 or less = random).
	int iSaved = Cel_GetClientSettingInt(iClient, "hud-color");
	
	g_bHudColorChosen[iClient] = (iSaved > 0);
	
	if (g_bHudColorChosen[iClient])
	{
		iSaved--;
		
		g_iClientColor[iClient][0] = (iSaved >> 16) & 255;
		g_iClientColor[iClient][1] = (iSaved >> 8) & 255;
		g_iClientColor[iClient][2] = iSaved & 255;
		g_iClientColor[iClient][3] = 255;
	}
}

public Action Command_HudColor(int iClient, int iArgs)
{
	char sArg[64], sColor[64], sParts[3][16];
	int iRGB[3];
	
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	GetCmdArgString(sArg, sizeof(sArg));
	StripQuotes(sArg);
	TrimString(sArg);
	
	if (sArg[0] == '\0')
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]hudcolor{default} <colour name or r g b>, or {green}random{default}. Colour names are the same as {green}[tag]color{default}.");
		return Plugin_Handled;
	}
	
	if (StrEqual(sArg, "random", false) || StrEqual(sArg, "off", false))
	{
		g_bHudColorChosen[iClient] = false;
		Cel_SetClientSettingInt(iClient, "hud-color", 0);
		Cel_ChooseHudColor(iClient);
		
		Cel_ReplyToCommand(iClient, "Your HUD colour is random again.");
		return Plugin_Handled;
	}
	
	if (ExplodeString(sArg, " ", sParts, 3, sizeof(sParts[])) == 3 && String_IsNumeric(sParts[0]) && String_IsNumeric(sParts[1]) && String_IsNumeric(sParts[2]))
	{
		for (int i = 0; i < 3; i++)
		{
			iRGB[i] = StringToInt(sParts[i]);
			iRGB[i] = iRGB[i] < 0 ? 0 : (iRGB[i] > 255 ? 255 : iRGB[i]);
		}
	} else if (Cel_CheckColorDB(sArg, sColor, sizeof(sColor))) {
		ExplodeString(sColor, "|", sParts, 3, sizeof(sParts[]));
		
		for (int i = 0; i < 3; i++)
		{
			iRGB[i] = StringToInt(sParts[i]);
		}
	} else {
		Cel_ReplyToCommand(iClient, "{green}%s{default} isn't a colour. Use a name from {green}[tag]colors{default}, or three numbers (r g b).", sArg);
		return Plugin_Handled;
	}
	
	g_bHudColorChosen[iClient] = true;
	g_iClientColor[iClient][0] = iRGB[0];
	g_iClientColor[iClient][1] = iRGB[1];
	g_iClientColor[iClient][2] = iRGB[2];
	g_iClientColor[iClient][3] = 255;
	
	Cel_SetClientSettingInt(iClient, "hud-color", ((iRGB[0] << 16) | (iRGB[1] << 8) | iRGB[2]) + 1);
	
	Cel_ReplyToCommand(iClient, "Your HUD colour is now {green}%s{default}.", sArg);
	
	return Plugin_Handled;
}

public Action Command_Feed(int iClient, int iArgs)
{
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	g_bFeedOff[iClient] = !g_bFeedOff[iClient];
	
	Cel_SetClientSettingInt(iClient, "hud-feed-off", g_bFeedOff[iClient] ? 1 : 0);
	
	Cel_ReplyToCommand(iClient, "The command feed is now {green}%s{default}. Type {green}!feed{default} to turn it %s.", g_bFeedOff[iClient] ? "off" : "on", g_bFeedOff[iClient] ? "back on" : "off");
	
	return Plugin_Handled;
}

public void OnClientDisconnect(int iClient)
{
	Cel_SetClientSettingInt(iClient, "hud-pos-left", view_as<int>(g_bHudLeft[iClient]));
}

public void CMHud_OnConVarChanged(ConVar cvConVar, const char[] sOldValue, const char[] sNewValue)
{
	if (cvConVar == g_cvHudEnable)
	{
		g_bHudEnable = view_as<bool>(g_cvHudEnable.IntValue);
	}
}

public Action Handle_Chat(int iClient, char[] sCommand, int iArgs)
{
	char sRealCommand[MAX_MESSAGE_LENGTH];
	
	GetCmdArgString(sRealCommand, sizeof(sRealCommand));
	
	StripQuotes(sRealCommand);
	
	if (sRealCommand[0] == '!')
	{
		//Private commands (a button's passcode) are never shown to everyone in the command feed.
		if (IsPrivateCommand(sRealCommand))
		{
			return Plugin_Handled;
		}
		
		g_alCommands.PushString(sRealCommand);
		
		if(g_alCommands.Length >= 6)
		{
			g_alCommands.Erase(0);
		}
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

//An entity CelMod has no type for (a turret, for one) shows its own name when it has one.
char[] UnknownCelName(int iEntity)
{
	char sName[64];
	
	Cel_GetPropName(iEntity, sName, sizeof(sName));
	
	if (sName[0] == '\0')
	{
		strcopy(sName, sizeof(sName), "???");
	} else {
		sName[0] = CharToUpper(sName[0]);
	}
	
	return sName;
}

//The title shown above a high-level player's name when someone looks at them.
char[] LevelTitle(int iClient)
{
	char sTitle[32];
	int iLevel = Cel_GetTacticsLevel(iClient);
	
	if (iLevel >= 100)
	{
		strcopy(sTitle, sizeof(sTitle), "-= Legend =-\n");
	} else if (iLevel >= 75)
	{
		strcopy(sTitle, sizeof(sTitle), "- Veteran -\n");
	}
	
	return sTitle;
}

bool IsPrivateCommand(const char[] sText)
{
	static const char sPrivate[][] = { "setpass", "pass" };
	char sName[32];
	
	strcopy(sName, sizeof(sName), sText[1]);
	
	int iSpace = FindCharInString(sName, ' ');
	
	if (iSpace != -1)
	{
		sName[iSpace] = '\0';
	}
	
	for (int i = 0; i < sizeof(sPrivate); i++)
	{
		if (StrEqual(sName, sPrivate[i], false))
		{
			return true;
		}
	}
	
	return false;
}

public Action Command_Switch(int iClient, int iArgs)
{
	g_bHudLeft[iClient] = !g_bHudLeft[iClient];
	
	Cel_SetClientSettingInt(iClient, "hud-pos-left", view_as<int>(g_bHudLeft[iClient]));
	
	Cel_ReplyToCommand(iClient, "%t", "SwitchedHUD", g_bHudLeft[iClient] ? "left" : "right");
	
	return Plugin_Handled;
}

//Natives:
public int Native_ChooseHudColor(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	//A colour picked with !hudcolor is kept.
	if (iClient > 0 && iClient <= MaxClients && g_bHudColorChosen[iClient])
	{
		return true;
	}
	
	switch (GetRandomInt(0, 6))
	{
		case 0:
		{
			Cel_SetHudColor(iClient, 255, 0, 0, 255);
		}
		case 1:
		{
			Cel_SetHudColor(iClient, 255, 128, 0, 255);
		}
		case 2:
		{
			Cel_SetHudColor(iClient, 255, 255, 0, 255);
		}
		case 3:
		{
			Cel_SetHudColor(iClient, 0, 255, 0, 255);
		}
		case 4:
		{
			Cel_SetHudColor(iClient, 0, 0, 255, 255);
		}
		case 5:
		{
			Cel_SetHudColor(iClient, 255, 0, 255, 255);
		}
		case 6:
		{
			Cel_SetHudColor(iClient, 128, 0, 255, 255);
		}
	}
	
	return true;
}

public int Native_GetHudColor(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	SetNativeArray(2, g_iClientColor[iClient], 4);
	
	return true;
}

public int Native_SendHudMessage(Handle hPlugin, int iNumParams)
{
	char sMessage[MAX_MESSAGE_LENGTH];
	float fFadeIn = view_as<float>(GetNativeCell(10)), fFadeOut = view_as<float>(GetNativeCell(11)), fFxTime = view_as<float>(GetNativeCell(13)),
	fHoldTime = view_as<float>(GetNativeCell(12)), fX = view_as<float>(GetNativeCell(3)), fY = view_as<float>(GetNativeCell(4));
	int iA = GetNativeCell(8), iB = GetNativeCell(7), iChannel = GetNativeCell(2), iClient = GetNativeCell(1),
	iEffect = GetNativeCell(9), iG = GetNativeCell(6), iR = GetNativeCell(5);
	
	GetNativeString(14, sMessage, sizeof(sMessage));
	
	//Reliable: an unreliable message is dropped when a player's packet is already full (busy effects, like the boss
	//fight's), and the text then blinks out.
	Handle hHudMessage = (iClient != -1) ? StartMessageOne("HudMsg", iClient, USERMSG_RELIABLE) : StartMessageAll("HudMsg", USERMSG_RELIABLE);
	
	if (hHudMessage != INVALID_HANDLE)
	{
		BfWriteByte(hHudMessage, iChannel);
		
		BfWriteFloat(hHudMessage, fX);
		BfWriteFloat(hHudMessage, fY);
		
		BfWriteByte(hHudMessage, iR);
		BfWriteByte(hHudMessage, iG);
		BfWriteByte(hHudMessage, iB);
		BfWriteByte(hHudMessage, iA);
		BfWriteByte(hHudMessage, iR);
		BfWriteByte(hHudMessage, iG);
		BfWriteByte(hHudMessage, iB);
		BfWriteByte(hHudMessage, iA);
		BfWriteByte(hHudMessage, iEffect);
		
		BfWriteFloat(hHudMessage, fFadeIn);
		BfWriteFloat(hHudMessage, fFadeOut);
		BfWriteFloat(hHudMessage, fHoldTime);
		BfWriteFloat(hHudMessage, fFxTime);
		
		BfWriteString(hHudMessage, sMessage);
		
		EndMessage();
	}
	
	return true;
}

public int Native_SetHudColor(Handle hPlugin, int iNumParams)
{
	int iA = GetNativeCell(5), iB = GetNativeCell(4), iClient = GetNativeCell(1), iG = GetNativeCell(3), iR = GetNativeCell(2);
	
	g_iClientColor[iClient][0] = iR;
	g_iClientColor[iClient][1] = iG;
	g_iClientColor[iClient][2] = iB;
	g_iClientColor[iClient][3] = iA;
	
	return true;
}

//Timers:
public Action Timer_CommandHUD(Handle hTimer)
{
	char sCommands[5][MAX_MESSAGE_LENGTH], sMessage[MAX_MESSAGE_LENGTH];
	
	if (g_bHudEnable)
	{
		for (int i = 1; i < MaxClients; i++)
		{
			if (Cel_IsPlayer(i) && !g_bFeedOff[i])
			{
				if(g_alCommands.Length >= 1) g_alCommands.GetString(0, sCommands[0], sizeof(sCommands[]));
				if(g_alCommands.Length >= 2) g_alCommands.GetString(1, sCommands[1], sizeof(sCommands[]));
				if(g_alCommands.Length >= 3) g_alCommands.GetString(2, sCommands[2], sizeof(sCommands[]));
				if(g_alCommands.Length >= 4) g_alCommands.GetString(3, sCommands[3], sizeof(sCommands[]));
				if(g_alCommands.Length >= 5) g_alCommands.GetString(4, sCommands[4], sizeof(sCommands[]));
				
				Format(sMessage, sizeof(sMessage), "%s\n%s\n%s\n%s\n%s", sCommands[0], sCommands[1], sCommands[2], sCommands[3], sCommands[4]);
				
				//The command history sits at the top, on the same side as the HUD (!switch moves both).
				Cel_SendHudMessage(i, 3, g_bHudLeft[i] ? -3.010 : 3.010, 0.0, 255, 128, 0, 255, 0, 0.6, 0.01, 0.2, 0.01, sMessage);
			}
		}
	}
	
	return Plugin_Continue;
}

/*public Action Timer_HUD(Handle hTimer)
{
	char sBalance[64], sBuffer[128], sBufferArray[2][128], sMessage[MAX_MESSAGE_LENGTH], sPropname[128];
	float fOrigin[3];
	int iColor[4], iLand;

	if (g_bHudEnable)
	{
		for (int i = 1; i < MaxClients; i++)
		{
			if (Cel_IsPlayer(i))
			{
				int iEntity = Cel_GetClientAimTarget(i);

				if (iEntity != -1)
				{
					if(Cel_IsEntityForSale(iEntity))
					{
						if (Cel_CheckEntityCatagory(iEntity, ENTCATAGORY_PROP))
						{
							Cel_GetPropName(iEntity, sPropname, sizeof(sPropname));

							if (Cel_CheckOwner(i, iEntity))
							{
								Format(sMessage, sizeof(sMessage), "Prop: %s\nPrice: %i", sPropname, Cel_GetEntityPrice(iEntity));

								Cel_GetHudColor(i, iColor);
							} else {
								Format(sMessage, sizeof(sMessage), "Owner: %N\nProp: %s\nPrice: %i", Cel_GetOwner(iEntity), sPropname, Cel_GetEntityPrice(iEntity));

								Cel_GetHudColor(Cel_GetOwner(iEntity), iColor);
							}
						} else if (Cel_CheckEntityCatagory(iEntity, ENTCATAGORY_CEL)) {
							if (Cel_GetEntityType(iEntity) == ENTTYPE_EFFECT)
							{
								Cel_GetEffectTypeName(Cel_GetEffectType(iEntity), sPropname, sizeof(sPropname));

								if (Cel_CheckOwner(i, iEntity))
								{
									Format(sMessage, sizeof(sMessage), "Effect: %s\nPrice: %i", sPropname, Cel_GetEntityPrice(iEntity));

									Cel_GetHudColor(i, iColor);
								} else {
									Format(sMessage, sizeof(sMessage), "Owner: %N\nEffect: %s\nPrice: %i", Cel_GetOwner(iEntity), sPropname, Cel_GetEntityPrice(iEntity));

									Cel_GetHudColor(Cel_GetOwner(iEntity), iColor);
								}
							} else {
								Cel_GetEntityTypeName(Cel_GetEntityType(iEntity), sBuffer, sizeof(sBuffer));

								ExplodeString(sBuffer, " ", sBufferArray, 2, 128, true);

								strcopy(sPropname, sizeof(sPropname), sBufferArray[0]);

								//A cel that is a prop underneath (the music radio) is named after what it is.
								if (Cel_GetEntityType(iEntity) == ENTTYPE_PHYSICS || Cel_GetEntityType(iEntity) == ENTTYPE_DYNAMIC)
								{
									strcopy(sPropname, sizeof(sPropname), UnknownCelName(iEntity));
								}

								if (Cel_CheckOwner(i, iEntity))
								{
									Format(sMessage, sizeof(sMessage), "Cel: %s\nPrice: %i", sPropname, Cel_GetEntityPrice(iEntity));

									Cel_GetHudColor(i, iColor);
								} else {
									Format(sMessage, sizeof(sMessage), "Owner: %N\nCel: %s\nPrice: %i", Cel_GetOwner(iEntity), sPropname, Cel_GetEntityPrice(iEntity));

									Cel_GetHudColor(Cel_GetOwner(iEntity), iColor);
								}
							}

						} else if (Cel_CheckEntityCatagory(iEntity, ENTCATAGORY_UNKNOWN)) {
							if (Cel_CheckOwner(i, iEntity))
							{
								Format(sMessage, sizeof(sMessage), "Cel: %s\nPrice: %i", UnknownCelName(iEntity), Cel_GetEntityPrice(iEntity));

								Cel_GetHudColor(i, iColor);
							} else {
								Format(sMessage, sizeof(sMessage), "Owner: %N\nCel: %s\nPrice: %i", Cel_GetOwner(iEntity), UnknownCelName(iEntity), Cel_GetEntityPrice(iEntity));

								Cel_GetHudColor(Cel_GetOwner(iEntity), iColor);
							}
						}
					}else{
						if (Cel_CheckEntityCatagory(iEntity, ENTCATAGORY_PROP))
						{
							Cel_GetPropName(iEntity, sPropname, sizeof(sPropname));

							if (Cel_CheckOwner(i, iEntity))
							{
								Format(sMessage, sizeof(sMessage), "Prop: %s", sPropname);

								Cel_GetHudColor(i, iColor);
							} else {
								Format(sMessage, sizeof(sMessage), "Owner: %N\nProp: %s", Cel_GetOwner(iEntity), sPropname);

								Cel_GetHudColor(Cel_GetOwner(iEntity), iColor);
							}
						} else if (Cel_CheckEntityCatagory(iEntity, ENTCATAGORY_CEL)) {
							if (Cel_GetEntityType(iEntity) == ENTTYPE_EFFECT)
							{
								Cel_GetEffectTypeName(Cel_GetEffectType(iEntity), sPropname, sizeof(sPropname));

								if (Cel_CheckOwner(i, iEntity))
								{
									Format(sMessage, sizeof(sMessage), "Effect: %s", sPropname);

									Cel_GetHudColor(i, iColor);
								} else {
									Format(sMessage, sizeof(sMessage), "Owner: %N\nEffect: %s", Cel_GetOwner(iEntity), sPropname);

									Cel_GetHudColor(Cel_GetOwner(iEntity), iColor);
								}
							} else {
								Cel_GetEntityTypeName(Cel_GetEntityType(iEntity), sBuffer, sizeof(sBuffer));

								ExplodeString(sBuffer, " ", sBufferArray, 2, 128, true);

								strcopy(sPropname, sizeof(sPropname), sBufferArray[0]);

								//A cel that is a prop underneath (the music radio) is named after what it is.
								if (Cel_GetEntityType(iEntity) == ENTTYPE_PHYSICS || Cel_GetEntityType(iEntity) == ENTTYPE_DYNAMIC)
								{
									strcopy(sPropname, sizeof(sPropname), UnknownCelName(iEntity));
								}

								if (Cel_CheckOwner(i, iEntity))
								{
									Format(sMessage, sizeof(sMessage), "Cel: %s", sPropname);

									Cel_GetHudColor(i, iColor);
								} else {
									Format(sMessage, sizeof(sMessage), "Owner: %N\nCel: %s", Cel_GetOwner(iEntity), sPropname);

									Cel_GetHudColor(Cel_GetOwner(iEntity), iColor);
								}
							}

						} else if (Cel_CheckEntityCatagory(iEntity, ENTCATAGORY_UNKNOWN)) {
							if (Cel_CheckOwner(i, iEntity))
							{
								Format(sMessage, sizeof(sMessage), "Entity: Unknown");

								Cel_GetHudColor(i, iColor);
							} else {
								Format(sMessage, sizeof(sMessage), "Owner: %N\nCel: ???", Cel_GetOwner(iEntity));

								Cel_GetHudColor(Cel_GetOwner(iEntity), iColor);
							}
						}
					}
					if (Cel_IsPlayer(iEntity)) {
						Cel_GetClientBalanceTranslated(iEntity, sBalance, sizeof(sBalance));

						Format(sMessage, sizeof(sMessage), "%s%N Money: %s\nTactics Lvl: %d", LevelTitle(iEntity), iEntity, sBalance, Cel_GetTacticsLevel(iEntity));

						Cel_GetHudColor(iEntity, iColor);
					} else {
						Cel_GetClientBalanceTranslated(i, sBalance, sizeof(sBalance));

						Format(sMessage, sizeof(sMessage), "Balance: %s\nSpawned: %d", sBalance, Cel_GetCombinedCount(i));

						Cel_GetHudColor(i, iColor);
					}
				} else if(Cel_IsClientCrosshairInLand(i)){
				}else {
					Cel_GetCrosshairHitOrigin(i, fOrigin);

					iLand = Cel_GetLandOwnerFromPosition(fOrigin);

					if(iLand != -1)
					{
						Format(sMessage, sizeof(sMessage), "Land: %N", iLand);

						Cel_GetHudColor(iLand, iColor);
					}else{
						Cel_GetClientBalanceTranslated(i, sBalance, sizeof(sBalance));

						Format(sMessage, sizeof(sMessage), "Balance: %s\nSpawned: %d", sBalance, Cel_GetCombinedCount(i));

						Cel_GetHudColor(i, iColor);
					}
				}

				Cel_SendHudMessage(i, 1, g_bHudLeft[i] ? -2.010 : 2.010, -0.110, iColor[0], iColor[1], iColor[2], iColor[3], 0, 0.6, 0.01, 0.2, 0.01, sMessage);
			}
		}
	}

	return Plugin_Continue;
}*/

public Action Timer_HUD(Handle hTimer)
{
	char sBalance[32], sCelBuffer[64], sCelBufferArray[2][64], sHUDMessage[MAX_MESSAGE_LENGTH], sPropName[64];
	float fCrosshairOrigin[3];
	int iEntity, iHUDColor[4], iLandOwner;
	
	if (g_bHudEnable)
	{
		for (int i = 1; i < MaxClients; i++)
		{
			if (Cel_IsPlayer(i))
			{
				//Another player under the crosshair: their name, money and tactics level. (Cel_GetClientAimTarget only
				//finds props: its trace goes through players.)
				int iPlayer = GetClientAimTarget(i, true);
				
				iEntity = (iPlayer > 0 && iPlayer != i && IsClientInGame(iPlayer) && IsPlayerAlive(iPlayer) && Cel_IsPlayer(iPlayer)) ? -1 : Cel_GetClientAimTarget(i);
				
				if (iEntity == -1 && iPlayer > 0 && iPlayer != i && IsClientInGame(iPlayer) && IsPlayerAlive(iPlayer) && Cel_IsPlayer(iPlayer))
				{
					Cel_GetClientBalanceTranslated(iPlayer, sBalance, sizeof(sBalance));
					
					Format(sHUDMessage, sizeof(sHUDMessage), "%s%N Money: %s\nTactics Lvl: %d", LevelTitle(iPlayer), iPlayer, sBalance, Cel_GetTacticsLevel(iPlayer));
					
					Cel_GetHudColor(iPlayer, iHUDColor);
				} else if (iEntity != -1)
				{
					if (Cel_GetEntityType(iEntity) == ENTTYPE_CLEER && Cel_GetCleerBoxAmount(iEntity) > 0)
					{
						//Cleers box: who it belongs to and how much is inside.
						if (Cel_CheckOwner(i, iEntity))
						{
							char sShort[16];
							Cel_ShortCleers(Cel_GetCleerBoxAmount(iEntity), sShort, sizeof(sShort));
							Format(sHUDMessage, sizeof(sHUDMessage), "Owner: %N\nContains: %s CL", Cel_GetOwner(iEntity), sShort);
							
							Cel_GetHudColor(i, iHUDColor);
						} else {
							char sShort[16];
							Cel_ShortCleers(Cel_GetCleerBoxAmount(iEntity), sShort, sizeof(sShort));
							Format(sHUDMessage, sizeof(sHUDMessage), "Owner: %N\nContains: %s CL", Cel_GetOwner(iEntity), sShort);
							
							Cel_GetHudColor(Cel_GetOwner(iEntity), iHUDColor);
						}
					} else if (Cel_GetEntityType(iEntity) == ENTTYPE_EMBLEM || Cel_GetEntityType(iEntity) == ENTTYPE_HAT || Cel_GetEntityType(iEntity) == ENTTYPE_CELWEP)
					{
						Cel_GetCollectibleName(iEntity, sPropName, sizeof(sPropName));
						
						if (Cel_CheckOwner(i, iEntity))
						{
							Format(sHUDMessage, sizeof(sHUDMessage), "%s: %s", Cel_GetEntityType(iEntity) == ENTTYPE_EMBLEM ? "Emblem" : (Cel_GetEntityType(iEntity) == ENTTYPE_HAT ? "Hat" : "Weapon"), sPropName);
							
							Cel_GetHudColor(i, iHUDColor);
						} else {
							Format(sHUDMessage, sizeof(sHUDMessage), "Owner: %N\n%s: %s", Cel_GetOwner(iEntity), Cel_GetEntityType(iEntity) == ENTTYPE_EMBLEM ? "Emblem" : (Cel_GetEntityType(iEntity) == ENTTYPE_HAT ? "Hat" : "Weapon"), sPropName);
							
							Cel_GetHudColor(Cel_GetOwner(iEntity), iHUDColor);
						}
					} else if (Cel_CheckEntityCatagory(iEntity, ENTCATAGORY_BIT)) {
						if(Cel_GetEntityType(iEntity) == ENTTYPE_AMMO)
						{
							Cel_GetAmmoTypeName(Cel_GetAmmoType(iEntity), sCelBuffer, sizeof(sCelBuffer));
							
							if (Cel_CheckOwner(i, iEntity))
							{
								Format(sHUDMessage, sizeof(sHUDMessage), "Ammo: %s", sCelBuffer);
								
								Cel_GetHudColor(i, iHUDColor);
							} else {
								Format(sHUDMessage, sizeof(sHUDMessage), "Owner: %N\nAmmo: %s", Cel_GetOwner(iEntity), sCelBuffer);
								
								Cel_GetHudColor(Cel_GetOwner(iEntity), iHUDColor);
							}
						}else if(Cel_GetEntityType(iEntity) == ENTTYPE_AMMOCRATE)
						{
							Cel_GetAmmoCrateTypeName(Cel_GetAmmoCrateType(iEntity), sCelBuffer, sizeof(sCelBuffer));
							
							if (Cel_CheckOwner(i, iEntity))
							{
								Format(sHUDMessage, sizeof(sHUDMessage), "Ammocrate: %s", sCelBuffer);
								
								Cel_GetHudColor(i, iHUDColor);
							} else {
								Format(sHUDMessage, sizeof(sHUDMessage), "Owner: %N\nAmmocrate: %s", Cel_GetOwner(iEntity), sCelBuffer);
								
								Cel_GetHudColor(Cel_GetOwner(iEntity), iHUDColor);
							}
						}else if(Cel_GetEntityType(iEntity) == ENTTYPE_CHARGER)
						{
							Cel_GetChargerTypeName(Cel_GetChargerType(iEntity), sCelBuffer, sizeof(sCelBuffer));
							
							if (Cel_CheckOwner(i, iEntity))
							{
								Format(sHUDMessage, sizeof(sHUDMessage), "Charger: %s", sCelBuffer);
								
								Cel_GetHudColor(i, iHUDColor);
							} else {
								Format(sHUDMessage, sizeof(sHUDMessage), "Owner: %N\nCharger: %s", Cel_GetOwner(iEntity), sCelBuffer);
								
								Cel_GetHudColor(Cel_GetOwner(iEntity), iHUDColor);
							}
						}else if(Cel_GetEntityType(iEntity) == ENTTYPE_TRIGGER)
						{
							if (Cel_CheckOwner(i, iEntity))
							{
								Format(sHUDMessage, sizeof(sHUDMessage), "Cel: %s", "trigger");
								
								Cel_GetHudColor(i, iHUDColor);
							} else {
								Format(sHUDMessage, sizeof(sHUDMessage), "Owner: %N\nCel: %s", Cel_GetOwner(iEntity), "trigger");
								
								Cel_GetHudColor(Cel_GetOwner(iEntity), iHUDColor);
							}
						}else if(Cel_GetEntityType(iEntity) == ENTTYPE_WEAPONSPWNER)
						{
							Cel_GetWeaponTypeName(Cel_GetWeaponType(iEntity), sCelBuffer, sizeof(sCelBuffer));
							
							if (Cel_CheckOwner(i, iEntity))
							{
								Format(sHUDMessage, sizeof(sHUDMessage), "Weapon: %s", sCelBuffer);
								
								Cel_GetHudColor(i, iHUDColor);
							} else {
								Format(sHUDMessage, sizeof(sHUDMessage), "Owner: %N\nWeapon: %s", Cel_GetOwner(iEntity), sCelBuffer);
								
								Cel_GetHudColor(Cel_GetOwner(iEntity), iHUDColor);
							}
						}else{
							if (Cel_CheckOwner(i, iEntity))
							{
								Format(sHUDMessage, sizeof(sHUDMessage), "Cel: %s", "bit");
								
								Cel_GetHudColor(i, iHUDColor);
							} else {
								Format(sHUDMessage, sizeof(sHUDMessage), "Owner: %N\nCel: %s", Cel_GetOwner(iEntity), "bit");
								
								Cel_GetHudColor(Cel_GetOwner(iEntity), iHUDColor);
							}
						}
					}else if (Cel_CheckEntityCatagory(iEntity, ENTCATAGORY_PROP))
					{
						Cel_GetPropName(iEntity, sPropName, sizeof(sPropName));
						
						if (Cel_CheckOwner(i, iEntity))
						{
							Format(sHUDMessage, sizeof(sHUDMessage), "Prop: %s", sPropName);
							
							Cel_GetHudColor(i, iHUDColor);
						} else {
							Format(sHUDMessage, sizeof(sHUDMessage), "Owner: %N\nProp: %s", Cel_GetOwner(iEntity), sPropName);
							
							Cel_GetHudColor(Cel_GetOwner(iEntity), iHUDColor);
						}
					} else if (Cel_CheckEntityCatagory(iEntity, ENTCATAGORY_CEL)) {
						if (Cel_GetEntityType(iEntity) == ENTTYPE_EFFECT)
						{
							Cel_GetEffectTypeName(Cel_GetEffectType(iEntity), sPropName, sizeof(sPropName));
							
							if (Cel_CheckOwner(i, iEntity))
							{
								Format(sHUDMessage, sizeof(sHUDMessage), "Effect: %s", sPropName);
								
								Cel_GetHudColor(i, iHUDColor);
							} else {
								Format(sHUDMessage, sizeof(sHUDMessage), "Owner: %N\nEffect: %s", Cel_GetOwner(iEntity), sPropName);
								
								Cel_GetHudColor(Cel_GetOwner(iEntity), iHUDColor);
							}
						} else {
							Cel_GetEntityTypeName(Cel_GetEntityType(iEntity), sCelBuffer, sizeof(sCelBuffer));
							
							ExplodeString(sCelBuffer, " ", sCelBufferArray, 2, 128, true);
							
							strcopy(sPropName, sizeof(sPropName), sCelBufferArray[0]);
							
							//A cel that is a prop underneath (the music radio) is named after what it is.
							if (Cel_GetEntityType(iEntity) == ENTTYPE_PHYSICS || Cel_GetEntityType(iEntity) == ENTTYPE_DYNAMIC)
							{
								strcopy(sPropName, sizeof(sPropName), UnknownCelName(iEntity));
							}
							
							if (Cel_CheckOwner(i, iEntity))
							{
								Format(sHUDMessage, sizeof(sHUDMessage), "Cel: %s", sPropName);
								
								Cel_GetHudColor(i, iHUDColor);
							} else {
								Format(sHUDMessage, sizeof(sHUDMessage), "Owner: %N\nCel: %s", Cel_GetOwner(iEntity), sPropName);
								
								Cel_GetHudColor(Cel_GetOwner(iEntity), iHUDColor);
							}
						}
						
					} else if (Cel_CheckEntityCatagory(iEntity, ENTCATAGORY_UNKNOWN)) {
						if (Cel_CheckOwner(i, iEntity))
						{
							Format(sHUDMessage, sizeof(sHUDMessage), "Cel: %s", UnknownCelName(iEntity));
							
							Cel_GetHudColor(i, iHUDColor);
						} else {
							Format(sHUDMessage, sizeof(sHUDMessage), "Owner: %N\nCel: %s", Cel_GetOwner(iEntity), UnknownCelName(iEntity));
							
							Cel_GetHudColor(Cel_GetOwner(iEntity), iHUDColor);
						}
					}else if (Cel_IsPlayer(iEntity)) {
						Cel_GetClientBalanceTranslated(iEntity, sBalance, sizeof(sBalance));
						
						Format(sHUDMessage, sizeof(sHUDMessage), "%s%N Money: %s\nTactics Lvl: %d", LevelTitle(iEntity), iEntity, sBalance, Cel_GetTacticsLevel(iEntity));
						
						Cel_GetHudColor(iEntity, iHUDColor);
					}
					
					//A label (!label) goes on top, so a button says what it's for.
					if (iEntity <= MAXENTITIES && g_sLabel[iEntity][0] != '\0' && sHUDMessage[0] != '\0')
					{
						Format(sHUDMessage, sizeof(sHUDMessage), "\"%s\"\n%s", g_sLabel[iEntity], sHUDMessage);
					}
					
					//Anything that is for sale shows its price to everyone looking at it.
					if (Cel_IsEntityForSale(iEntity))
					{
						Format(sHUDMessage, sizeof(sHUDMessage), "%s\nPrice: %d CL%s", sHUDMessage, Cel_GetEntityPrice(iEntity), Cel_CheckOwner(i, iEntity) ? "" : " (!buy)");
					}
				} else if (GetClientAimTarget(i, false) > MaxClients && Cel_GetRewardLabel(GetClientAimTarget(i, false), sHUDMessage, sizeof(sHUDMessage))) {
					//Event emblems and reward pickups say what they give.
					Cel_GetHudColor(i, iHUDColor);
				} else if (GetClientAimTarget(i, false) > MaxClients && Cel_GetDropBoxEmblem(GetClientAimTarget(i, false), sPropName, sizeof(sPropName))) {
					//Emblem drop boxes are nobody's until the map changes, but everyone can see what is inside.
					Format(sHUDMessage, sizeof(sHUDMessage), "Emblem: %s", sPropName);
					
					Cel_GetHudColor(i, iHUDColor);
				} else if(Cel_IsClientCrosshairInLand(i)){
					Cel_GetCrosshairHitOrigin(i, fCrosshairOrigin);
					
					iLandOwner = Cel_GetLandOwnerFromPosition(fCrosshairOrigin);
					
					if(iLandOwner != -1 && iLandOwner != i)
					{
						Format(sHUDMessage, sizeof(sHUDMessage), "Land: %N", iLandOwner);
						
						Cel_GetHudColor(iLandOwner, iHUDColor);
					}else{
						Cel_GetClientBalanceTranslated(i, sBalance, sizeof(sBalance));
						
						FormatPlayerHUD(i, sBalance, sHUDMessage, sizeof(sHUDMessage));
						
						Cel_GetHudColor(i, iHUDColor);
					}
				}else{
					Cel_GetClientBalanceTranslated(i, sBalance, sizeof(sBalance));
					
					FormatPlayerHUD(i, sBalance, sHUDMessage, sizeof(sHUDMessage));
					
					Cel_GetHudColor(i, iHUDColor);
				}
				
				Cel_SendHudMessage(i, 1, g_bHudLeft[i] ? -2.010 : 2.010, -0.110, iHUDColor[0], iHUDColor[1], iHUDColor[2], iHUDColor[3], 0, 0.6, 0.01, 0.2, 0.01, sHUDMessage);
			}
		}
	}
	
	return Plugin_Continue;
}

//The player's own HUD: money, tactics level, and a bar of ten marks showing experience towards the next level.
void FormatPlayerHUD(int iClient, const char[] sBalance, char[] sMessage, int iMaxLength)
{
	char sBar[16];
	
	int iNeeded = Cel_GetTacticsXPNeeded(iClient);
	int iFilled = (iNeeded > 0) ? (Cel_GetTacticsXP(iClient) * 10) / iNeeded : 0;
	
	for (int i = 0; i < 10; i++)
	{
		sBar[i] = (i < iFilled) ? '+' : '-';
	}
	
	sBar[10] = '\0';
	
	Format(sMessage, iMaxLength, "Money: %s\nTactics Lvl: %d\nEXP: %s", sBalance, Cel_GetTacticsLevel(iClient), sBar);
}

//!label <name>: names a button or cel so you remember what it's for. It shows on top of the HUD for anyone looking at
//it, and saves keep it. Buttons and the other bits, cels (doors, lights, internet cels...), and the props that work
//like cels (sound, music, message and camera cels, TVs linked to a camera); not emblems, hats, celweps or weapons.
public Action Command_Label(int iClient, int iArgs)
{
	if (iClient < 1)
	{
		return Plugin_Handled;
	}
	
	if (iArgs < 1)
	{
		Cel_ReplyToCommand(iClient, "Usage: {green}[tag]label <name>{default} names the button or cel you're looking at (shown when anyone looks at it). {green}[tag]label off{default} removes it.");
		return Plugin_Handled;
	}
	
	int iEntity = Cel_GetClientAimTarget(iClient);
	
	if (iEntity == -1)
	{
		Cel_NotLooking(iClient);
		return Plugin_Handled;
	}
	
	if (!Cel_CanEdit(iClient, iEntity))
	{
		Cel_NotYours(iClient, iEntity);
		return Plugin_Handled;
	}
	
	if (!CanLabel(iEntity))
	{
		Cel_ReplyToCommand(iClient, "Only buttons and cels can be labelled (not props, emblems, hats or weapons).");
		return Plugin_Handled;
	}
	
	char sLabel[48];
	
	GetCmdArgString(sLabel, sizeof(sLabel));
	StripQuotes(sLabel);
	TrimString(sLabel);
	
	//One line of plain text.
	ReplaceString(sLabel, sizeof(sLabel), "\n", " ");
	ReplaceString(sLabel, sizeof(sLabel), "\r", " ");
	ReplaceString(sLabel, sizeof(sLabel), "\"", "'");
	
	if (StrEqual(sLabel, "off", false) || StrEqual(sLabel, "none", false) || StrEqual(sLabel, "clear", false) || sLabel[0] == '\0')
	{
		if (g_sLabel[iEntity][0] == '\0')
		{
			Cel_ReplyToCommand(iClient, "That has no label.");
		} else {
			g_sLabel[iEntity][0] = '\0';
			Cel_ReplyToCommand(iClient, "Label removed.");
		}
		
		return Plugin_Handled;
	}
	
	strcopy(g_sLabel[iEntity], sizeof(g_sLabel[]), sLabel);
	
	Cel_ReplyToCommand(iClient, "Labelled {green}%s{default}.", sLabel);
	
	return Plugin_Handled;
}

bool CanLabel(int iEntity)
{
	if (iEntity <= MaxClients || iEntity > MAXENTITIES || !Cel_IsEntity(iEntity))
	{
		return false;
	}
	
	switch (Cel_GetEntityType(iEntity))
	{
		case ENTTYPE_EMBLEM, ENTTYPE_HAT, ENTTYPE_CELWEP, ENTTYPE_WEAPONSPWNER, ENTTYPE_CLEER:
		{
			return false;
		}
	}
	
	if (Cel_CheckEntityCatagory(iEntity, ENTCATAGORY_BIT) || Cel_CheckEntityCatagory(iEntity, ENTCATAGORY_CEL))
	{
		return true;
	}
	
	//Props that work like cels.
	char sName[32];
	
	Cel_GetPropName(iEntity, sName, sizeof(sName));
	
	static const char sCelProps[][] = { "sound", "music", "message", "camera", "tv", "monitor1", "monitor2", "monitor3" };
	
	for (int i = 0; i < sizeof(sCelProps); i++)
	{
		if (StrEqual(sName, sCelProps[i], false))
		{
			return true;
		}
	}
	
	//Anything linked to something (a TV linked to a camera).
	return GetFeatureStatus(FeatureType_Native, "Cel_GetTriggerLink") == FeatureStatus_Available && Cel_GetTriggerLink(iEntity, 0) > 0;
}

public void OnEntityDestroyed(int iEntity)
{
	if (iEntity > 0 && iEntity <= MAXENTITIES)
	{
		g_sLabel[iEntity][0] = '\0';
	}
}

//Saves keep labels.
public void Cel_OnSaveEntity(int iEntity, KeyValues kvSave)
{
	if (iEntity > 0 && iEntity <= MAXENTITIES && g_sLabel[iEntity][0] != '\0')
	{
		kvSave.SetString("x_label", g_sLabel[iEntity]);
	}
}

public void Cel_OnLoadEntity(int iClient, int iEntity, KeyValues kvSave)
{
	if (iEntity > 0 && iEntity <= MAXENTITIES)
	{
		kvSave.GetString("x_label", g_sLabel[iEntity], sizeof(g_sLabel[]), "");
	}
}

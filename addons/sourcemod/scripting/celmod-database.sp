#pragma semicolon 1

#include <celmod>

#pragma newdecls required

/*
 * |CelMod| Database
 *
 * Mirrors live server data into a shared MySQL database so the |CelMod|
 * website can show realtime analytics, player profiles and leaderboards,
 * and delivers orders placed in the website shop.
 *
 * The game server stays authoritative: balances and purchases still live in
 * data/celmod/users/<steamid>/ and this plugin only copies them out. Web shop
 * orders are re-checked (price, balance, already owned) in-game before the
 * player is charged.
 *
 * Setup: add a "celmod" entry to addons/sourcemod/configs/databases.cfg that
 * points at the same database as the website's config.php. Tables are
 * created automatically.
 */

#define SCHEMA_QUERIES 13
#define MIGRATION_QUERIES 6

Database g_dbCelMod;

bool g_bConnecting;
bool g_bMapLogged;
bool g_bTracked[MAXPLAYERS + 1];
bool g_bPurchasesSynced[MAXPLAYERS + 1];

char g_sMap[64];
char g_sSteamID[MAXPLAYERS + 1][32];

ArrayList g_alShopItems;

ConVar g_cvAddress;
ConVar g_cvConfig;
ConVar g_cvHeartbeat;
ConVar g_cvOrderPoll;
ConVar g_cvSample;
ConVar g_cvServerID;

Handle g_hHeartbeatTimer;
Handle g_hOrderTimer;
Handle g_hSampleTimer;

int g_iJoinTime[MAXPLAYERS + 1];
int g_iPlayMark[MAXPLAYERS + 1];
int g_iMapStart;
int g_iPendingCels[MAXPLAYERS + 1];
int g_iPendingEffects[MAXPLAYERS + 1];
int g_iPendingProps[MAXPLAYERS + 1];
int g_iPendingRemoved[MAXPLAYERS + 1];
int g_iDayCels;
int g_iDayEffects;
int g_iDayProps;
int g_iSessionID[MAXPLAYERS + 1];
int g_iTick;

StringMap g_smRecentlyLeft;

//Announcements from the website's admin panel (cm_announcements), checked every cm_db_announce_poll seconds.
#define MAX_ANNOUNCEMENTS 32
int g_iAnnounceCount;
int g_iAnnounceID[MAX_ANNOUNCEMENTS];
int g_iAnnounceRepeat[MAX_ANNOUNCEMENTS];
bool g_bAnnounceOnJoin[MAX_ANNOUNCEMENTS];
char g_sAnnounce[MAX_ANNOUNCEMENTS][256];
StringMap g_smAnnounceShown;
ConVar g_cvAnnouncePoll;
Handle g_hAnnounceTimer;

char g_sSchema[SCHEMA_QUERIES][] = {
	"CREATE TABLE IF NOT EXISTS cm_players (steamid64 VARCHAR(20) NOT NULL, name VARCHAR(128) NOT NULL DEFAULT '', avatar_url VARCHAR(255) NOT NULL DEFAULT '', balance BIGINT NOT NULL DEFAULT 0, playtime_seconds INT UNSIGNED NOT NULL DEFAULT 0, connections INT UNSIGNED NOT NULL DEFAULT 0, props_spawned INT UNSIGNED NOT NULL DEFAULT 0, cels_spawned INT UNSIGNED NOT NULL DEFAULT 0, effects_spawned INT UNSIGNED NOT NULL DEFAULT 0, entities_removed INT UNSIGNED NOT NULL DEFAULT 0, is_online TINYINT(1) NOT NULL DEFAULT 0, first_seen DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, last_seen DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (steamid64), KEY idx_balance (balance), KEY idx_playtime (playtime_seconds), KEY idx_props (props_spawned)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
	"CREATE TABLE IF NOT EXISTS cm_purchases (steamid64 VARCHAR(20) NOT NULL, item VARCHAR(64) NOT NULL, source VARCHAR(8) NOT NULL DEFAULT 'game', purchased_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (steamid64, item)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
	"CREATE TABLE IF NOT EXISTS cm_shop_items (item VARCHAR(64) NOT NULL, display_name VARCHAR(64) NOT NULL DEFAULT '', price INT UNSIGNED NOT NULL DEFAULT 0, category VARCHAR(32) NOT NULL DEFAULT 'Commands', kind VARCHAR(16) NOT NULL DEFAULT 'command', target VARCHAR(64) NOT NULL DEFAULT '', description VARCHAR(255) NOT NULL DEFAULT '', stock_left INT NULL, repeatable TINYINT(1) NOT NULL DEFAULT 0, sort_order INT NOT NULL DEFAULT 0, enabled TINYINT(1) NOT NULL DEFAULT 1, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (item)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
	"CREATE TABLE IF NOT EXISTS cm_web_orders (id INT UNSIGNED NOT NULL AUTO_INCREMENT, steamid64 VARCHAR(20) NOT NULL, item VARCHAR(64) NOT NULL, price INT UNSIGNED NOT NULL, status VARCHAR(12) NOT NULL DEFAULT 'pending', message VARCHAR(255) NOT NULL DEFAULT '', server_id INT NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, processed_at DATETIME NULL, PRIMARY KEY (id), KEY idx_status_player (status, steamid64)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
	"CREATE TABLE IF NOT EXISTS cm_servers (server_id INT NOT NULL, hostname VARCHAR(128) NOT NULL DEFAULT '', address VARCHAR(64) NOT NULL DEFAULT '', map VARCHAR(64) NOT NULL DEFAULT '', players INT NOT NULL DEFAULT 0, max_players INT NOT NULL DEFAULT 0, total_props INT NOT NULL DEFAULT 0, total_cels INT NOT NULL DEFAULT 0, version VARCHAR(16) NOT NULL DEFAULT '', map_started DATETIME NULL, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (server_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
	"CREATE TABLE IF NOT EXISTS cm_online_players (server_id INT NOT NULL, steamid64 VARCHAR(20) NOT NULL, name VARCHAR(128) NOT NULL DEFAULT '', props INT NOT NULL DEFAULT 0, cels INT NOT NULL DEFAULT 0, balance BIGINT NOT NULL DEFAULT 0, joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (server_id, steamid64)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
	"CREATE TABLE IF NOT EXISTS cm_sessions (id INT UNSIGNED NOT NULL AUTO_INCREMENT, steamid64 VARCHAR(20) NOT NULL, server_id INT NOT NULL, map VARCHAR(64) NOT NULL DEFAULT '', started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, ended_at DATETIME NULL, PRIMARY KEY (id), KEY idx_player (steamid64), KEY idx_started (started_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
	"CREATE TABLE IF NOT EXISTS cm_events (id INT UNSIGNED NOT NULL AUTO_INCREMENT, server_id INT NOT NULL, steamid64 VARCHAR(20) NULL, name VARCHAR(128) NOT NULL DEFAULT '', type VARCHAR(16) NOT NULL, detail VARCHAR(255) NOT NULL DEFAULT '', created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (id), KEY idx_created (created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
	"CREATE TABLE IF NOT EXISTS cm_stats_daily (day DATE NOT NULL, server_id INT NOT NULL, connections INT UNSIGNED NOT NULL DEFAULT 0, peak_players INT UNSIGNED NOT NULL DEFAULT 0, props_spawned INT UNSIGNED NOT NULL DEFAULT 0, cels_spawned INT UNSIGNED NOT NULL DEFAULT 0, effects_spawned INT UNSIGNED NOT NULL DEFAULT 0, PRIMARY KEY (day, server_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
	"CREATE TABLE IF NOT EXISTS cm_player_samples (server_id INT NOT NULL, recorded_at DATETIME NOT NULL, players INT NOT NULL, PRIMARY KEY (server_id, recorded_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
	"CREATE TABLE IF NOT EXISTS cm_emblem_suggestions (id INT UNSIGNED NOT NULL AUTO_INCREMENT, steamid64 VARCHAR(20) NOT NULL, player_name VARCHAR(128) NOT NULL DEFAULT '', emblem_id VARCHAR(64) NOT NULL, title VARCHAR(64) NOT NULL DEFAULT '', kv TEXT NOT NULL, note VARCHAR(500) NOT NULL DEFAULT '', status VARCHAR(12) NOT NULL DEFAULT 'pending', admin_note VARCHAR(255) NOT NULL DEFAULT '', reviewed_by VARCHAR(20) NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, reviewed_at DATETIME NULL, PRIMARY KEY (id), KEY idx_status (status), KEY idx_player (steamid64)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
	"CREATE TABLE IF NOT EXISTS cm_maps (map VARCHAR(64) NOT NULL, times_played INT UNSIGNED NOT NULL DEFAULT 0, last_played DATETIME NULL, PRIMARY KEY (map)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
	"CREATE TABLE IF NOT EXISTS cm_announcements (id INT UNSIGNED NOT NULL AUTO_INCREMENT, message VARCHAR(255) NOT NULL, server_id INT NULL, repeat_minutes INT UNSIGNED NOT NULL DEFAULT 0, show_on_join TINYINT(1) NOT NULL DEFAULT 0, active TINYINT(1) NOT NULL DEFAULT 1, starts_at DATETIME NULL, ends_at DATETIME NULL, created_by VARCHAR(20) NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (id), KEY idx_active (active)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
};

// Columns added after the first release. Run one by one; "duplicate column" (1060) means already done.
char g_sMigrations[MIGRATION_QUERIES][] = {
	"ALTER TABLE cm_shop_items ADD COLUMN kind VARCHAR(16) NOT NULL DEFAULT 'command' AFTER category",
	"ALTER TABLE cm_shop_items ADD COLUMN target VARCHAR(64) NOT NULL DEFAULT '' AFTER kind",
	"ALTER TABLE cm_shop_items ADD COLUMN description VARCHAR(255) NOT NULL DEFAULT '' AFTER target",
	"ALTER TABLE cm_shop_items ADD COLUMN stock_left INT NULL AFTER description",
	"ALTER TABLE cm_shop_items ADD COLUMN repeatable TINYINT(1) NOT NULL DEFAULT 0 AFTER stock_left",
	"ALTER TABLE cm_shop_items ADD COLUMN sort_order INT NOT NULL DEFAULT 0 AFTER repeatable"
};

public Plugin myinfo =
{
	name = "|CelMod| Database",
	author = CEL_AUTHOR,
	description = "Shares live server data with the |CelMod| website and delivers web shop orders.",
	version = CEL_VERSION,
	url = CEL_URL
};

public void OnPluginStart()
{

	g_alShopItems = new ArrayList(ByteCountToCells(64));
	g_smRecentlyLeft = new StringMap();
	g_smAnnounceShown = new StringMap();

	g_cvConfig = CreateConVar("cm_db_config", "celmod", "Name of the databases.cfg entry shared with the website.");
	g_cvServerID = CreateConVar("cm_db_server_id", "1", "Unique ID for this server in the shared database (match the website config).", _, true, 1.0);
	g_cvAddress = CreateConVar("cm_db_address", "", "Public ip:port shown on the website. Leave empty to detect it.");
	g_cvHeartbeat = CreateConVar("cm_db_heartbeat", "15.0", "Seconds between live status updates.", _, true, 5.0);
	g_cvOrderPoll = CreateConVar("cm_db_order_poll", "5.0", "Seconds between checks for new web shop orders.", _, true, 2.0);
	g_cvAnnouncePoll = CreateConVar("cm_db_announce_poll", "30.0", "Seconds between checks for announcements made on the website.", _, true, 10.0);
	g_cvSample = CreateConVar("cm_db_sample", "300.0", "Seconds between player count samples for the activity chart.", _, true, 60.0);

	AutoExecConfig(true, "celmod.database");

	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

	RegAdminCmd("cm_db_status", Command_DBStatus, ADMFLAG_ROOT, "|CelMod| Shows the shared database connection status.");
}

public void OnConfigsExecuted()
{
	if (g_dbCelMod == null && !g_bConnecting)
	{
		ConnectDatabase();
	}

	RestartTimers();
}

public void OnMapStart()
{
	GetCurrentMap(g_sMap, sizeof(g_sMap));
	g_iMapStart = GetTime();
	g_bMapLogged = false;

	if (g_dbCelMod != null)
	{
		LogMapStart();
		SyncShopItems();
	}
}

public void OnMapEnd()
{
	FlushDailyStats(0);
}

void RestartTimers()
{
	delete g_hHeartbeatTimer;
	delete g_hOrderTimer;
	delete g_hSampleTimer;
	delete g_hAnnounceTimer;

	g_hHeartbeatTimer = CreateTimer(g_cvHeartbeat.FloatValue, Timer_Heartbeat, _, TIMER_REPEAT);
	g_hOrderTimer = CreateTimer(g_cvOrderPoll.FloatValue, Timer_PollOrders, _, TIMER_REPEAT);
	g_hSampleTimer = CreateTimer(g_cvSample.FloatValue, Timer_Sample, _, TIMER_REPEAT);
	g_hAnnounceTimer = CreateTimer(g_cvAnnouncePoll.FloatValue, Timer_PollAnnouncements, _, TIMER_REPEAT);
}

//Announcements:
public Action Timer_PollAnnouncements(Handle hTimer)
{
	char sQuery[512];

	if (g_dbCelMod == null)
	{
		return Plugin_Continue;
	}

	FormatEx(sQuery, sizeof(sQuery), "SELECT id, message, repeat_minutes, show_on_join, UNIX_TIMESTAMP() - UNIX_TIMESTAMP(created_at) FROM cm_announcements WHERE active = 1 AND (starts_at IS NULL OR starts_at <= NOW()) AND (ends_at IS NULL OR ends_at > NOW()) AND (server_id IS NULL OR server_id = %d) ORDER BY id LIMIT %d", g_cvServerID.IntValue, MAX_ANNOUNCEMENTS);

	g_dbCelMod.Query(SQL_OnAnnouncements, sQuery);

	return Plugin_Continue;
}

public void SQL_OnAnnouncements(Database dbDatabase, DBResultSet rsResults, const char[] sError, any aData)
{
	char sKey[16];
	float fLast;

	if (rsResults == null)
	{
		LogError("|CelMod| Could not read announcements: %s", sError);
		return;
	}

	g_iAnnounceCount = 0;

	while (rsResults.FetchRow() && g_iAnnounceCount < MAX_ANNOUNCEMENTS)
	{
		int i = g_iAnnounceCount++;

		g_iAnnounceID[i] = rsResults.FetchInt(0);
		rsResults.FetchString(1, g_sAnnounce[i], sizeof(g_sAnnounce[]));
		g_iAnnounceRepeat[i] = rsResults.FetchInt(2);
		g_bAnnounceOnJoin[i] = (rsResults.FetchInt(3) == 1);

		int iAge = rsResults.FetchInt(4);

		Format(sKey, sizeof(sKey), "a%d", g_iAnnounceID[i]);

		bool bSeen = g_smAnnounceShown.GetValue(sKey, fLast);

		//New on the website (or just started): everyone sees it now. Ones this server has not seen yet but
		//that are old (e.g. after a restart) only show again when their repeat comes round.
		if (!bSeen)
		{
			if (iAge < 600 || g_iAnnounceRepeat[i] > 0)
			{
				Announce(i);
			}

			g_smAnnounceShown.SetValue(sKey, GetEngineTime());
			continue;
		}

		if (g_iAnnounceRepeat[i] > 0 && GetEngineTime() - fLast >= g_iAnnounceRepeat[i] * 60.0)
		{
			Announce(i);

			g_smAnnounceShown.SetValue(sKey, GetEngineTime());
		}
	}
}

void Announce(int iIndex)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			Cel_PrintToChat(i, "{green}Announcement:{default} %s", g_sAnnounce[iIndex]);
		}
	}
}

//Players joining see the announcements marked "show on join".
public Action Timer_JoinAnnouncements(Handle hTimer, any iUserID)
{
	char sKey[16];
	int iClient = GetClientOfUserId(iUserID);

	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Stop;
	}

	//Once per visit, not again at every map change (a player keeps their user id across map changes).
	IntToString(iUserID, sKey, sizeof(sKey));

	if (!g_smAnnounceShown.SetValue(sKey, 0.0, false))
	{
		return Plugin_Stop;
	}

	for (int i = 0; i < g_iAnnounceCount; i++)
	{
		if (g_bAnnounceOnJoin[i])
		{
			Cel_PrintToChat(iClient, "{green}Announcement:{default} %s", g_sAnnounce[i]);
		}
	}

	return Plugin_Stop;
}

//Connection:
void ConnectDatabase()
{
	char sConfig[64];

	g_cvConfig.GetString(sConfig, sizeof(sConfig));

	if (!SQL_CheckConfig(sConfig))
	{
		LogError("|CelMod| No \"%s\" entry in databases.cfg, website sync is disabled.", sConfig);
		return;
	}

	g_bConnecting = true;

	Database.Connect(SQL_OnConnect, sConfig);
}

public void SQL_OnConnect(Database dbDatabase, const char[] sError, any aData)
{
	g_bConnecting = false;

	if (dbDatabase == null)
	{
		LogError("|CelMod| Could not connect to the shared database: %s (retrying in 30s)", sError);
		CreateTimer(30.0, Timer_Reconnect);
		return;
	}

	char sDriver[16];
	dbDatabase.Driver.GetIdentifier(sDriver, sizeof(sDriver));

	if (!StrEqual(sDriver, "mysql"))
	{
		LogError("|CelMod| The shared database must be MySQL/MariaDB (got \"%s\"), website sync is disabled.", sDriver);
		delete dbDatabase;
		return;
	}

	g_dbCelMod = dbDatabase;
	g_dbCelMod.SetCharset("utf8mb4");

	Transaction txSchema = new Transaction();

	for (int i = 0; i < SCHEMA_QUERIES; i++)
	{
		txSchema.AddQuery(g_sSchema[i]);
	}

	g_dbCelMod.Execute(txSchema, SQL_OnSchemaReady, SQL_OnTxnError);
}

public void SQL_OnSchemaReady(Database dbDatabase, any aData, int iNumQueries, DBResultSet[] rsResults, any[] aQueryData)
{
	char sQuery[256];

	PrintToServer("|CelMod| Connected to the shared website database.");

	for (int i = 0; i < MIGRATION_QUERIES; i++)
	{
		g_dbCelMod.Query(SQL_OnMigration, g_sMigrations[i], _, DBPrio_High);
	}

	// Orders that were mid-delivery when this server last stopped go back in the queue.
	// Re-delivering is safe: an item the player already owns is never charged twice.
	FormatEx(sQuery, sizeof(sQuery), "UPDATE cm_web_orders SET status = 'pending' WHERE status = 'processing' AND server_id = %d", g_cvServerID.IntValue);
	g_dbCelMod.Query(SQL_Generic, sQuery);

	SyncShopItems();
	LogMapStart();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && !g_bTracked[i])
		{
			TrackClient(i, true);
		}
	}

	Timer_Heartbeat(null);
}

public Action Timer_Reconnect(Handle hTimer)
{
	if (g_dbCelMod == null && !g_bConnecting)
	{
		ConnectDatabase();
	}

	return Plugin_Stop;
}

public Action Command_DBStatus(int iClient, int iArgs)
{
	ReplyToCommand(iClient, "|CelMod| Shared database: %s (server id %d, %d shop items synced)", g_dbCelMod != null ? "connected" : "not connected", g_cvServerID.IntValue, g_alShopItems.Length);

	return Plugin_Handled;
}

//Shop:
/**
 * Copies the shop catalog (celmod-shop: commands, rare props, player models, emblems, hats) to
 * cm_shop_items, including how many are left. Runs on connect, each map and about once a minute.
 */
void SyncShopItems()
{
	char sCategory[32], sDescription[128], sEscCategory[65], sEscDescription[257], sEscName[129], sEscTarget[129];
	char sKey[64], sName[64], sQuery[1536], sStock[16], sTarget[64], sType[16];
	int iLeft, iPrice;
	bool bRepeatable;

	if (g_dbCelMod == null)
	{
		return;
	}

	g_alShopItems.Clear();

	Transaction txShop = new Transaction();
	txShop.AddQuery("UPDATE cm_shop_items SET enabled = 0");

	for (int i = 0; i < Cel_ShopGetItemCount(); i++)
	{
		if (!Cel_ShopGetItem(i, sKey, sizeof(sKey), sName, sizeof(sName), sCategory, sizeof(sCategory), sDescription, sizeof(sDescription), iPrice, iLeft, bRepeatable)
			|| !Cel_ShopGetItemType(i, sType, sizeof(sType), sTarget, sizeof(sTarget))
			|| !IsSafeKey(sKey) || !IsSafeKey(sType))
		{
			continue;
		}

		if (!bRepeatable)
		{
			g_alShopItems.PushString(sKey);
		}

		g_dbCelMod.Escape(sName, sEscName, sizeof(sEscName));
		g_dbCelMod.Escape(sCategory, sEscCategory, sizeof(sEscCategory));
		g_dbCelMod.Escape(sDescription, sEscDescription, sizeof(sEscDescription));
		g_dbCelMod.Escape(sTarget, sEscTarget, sizeof(sEscTarget));

		if (iLeft < 0)
		{
			strcopy(sStock, sizeof(sStock), "NULL");
		} else {
			IntToString(iLeft, sStock, sizeof(sStock));
		}

		FormatEx(sQuery, sizeof(sQuery), "INSERT INTO cm_shop_items (item, display_name, price, category, kind, target, description, stock_left, repeatable, sort_order, enabled, updated_at) VALUES ('%s', '%s', %d, '%s', '%s', '%s', '%s', %s, %d, %d, 1, NOW()) ON DUPLICATE KEY UPDATE display_name = VALUES(display_name), price = VALUES(price), category = VALUES(category), kind = VALUES(kind), target = VALUES(target), description = VALUES(description), stock_left = VALUES(stock_left), repeatable = VALUES(repeatable), sort_order = VALUES(sort_order), enabled = 1, updated_at = NOW()",
			sKey, sEscName, iPrice, sEscCategory, sType, sEscTarget, sEscDescription, sStock, bRepeatable ? 1 : 0, i);
		txShop.AddQuery(sQuery);
	}

	g_dbCelMod.Execute(txShop, SQL_OnTxnOk, SQL_OnTxnError);
}

/** Shop keys and categories go into SQL unescaped, so only allow [A-Za-z0-9_-]. */
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

//Clients:
public void OnClientPostAdminCheck(int iClient)
{
	if (IsFakeClient(iClient))
	{
		return;
	}

	// Give the economy plugin a moment to load the player's balance.
	CreateTimer(3.0, Timer_TrackClient, GetClientUserId(iClient));
	CreateTimer(15.0, Timer_JoinAnnouncements, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_TrackClient(Handle hTimer, int iUserID)
{
	int iClient = GetClientOfUserId(iUserID);

	if (iClient != 0 && IsClientInGame(iClient) && !g_bTracked[iClient])
	{
		TrackClient(iClient, false);
	}

	return Plugin_Stop;
}

void TrackClient(int iClient, bool bLate)
{
	char sEscName[257], sName[128], sQuery[768];

	if (g_dbCelMod == null || !GetClientAuthId(iClient, AuthId_SteamID64, g_sSteamID[iClient], sizeof(g_sSteamID[])))
	{
		return;
	}

	g_bTracked[iClient] = true;
	g_bPurchasesSynced[iClient] = false;
	g_iJoinTime[iClient] = GetTime();
	g_iPlayMark[iClient] = g_iJoinTime[iClient];
	g_iPendingProps[iClient] = 0;
	g_iPendingCels[iClient] = 0;
	g_iPendingEffects[iClient] = 0;
	g_iPendingRemoved[iClient] = 0;

	GetClientName(iClient, sName, sizeof(sName));
	g_dbCelMod.Escape(sName, sEscName, sizeof(sEscName));

	// A rejoin right after a map change is the same visit, not a new connection.
	int iLeftAt;
	bool bReturning = bLate || (g_smRecentlyLeft.GetValue(g_sSteamID[iClient], iLeftAt) && GetTime() - iLeftAt < 300);
	g_smRecentlyLeft.Remove(g_sSteamID[iClient]);

	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO cm_players (steamid64, name, balance, connections, is_online, first_seen, last_seen) VALUES ('%s', '%s', %d, 1, 1, NOW(), NOW()) ON DUPLICATE KEY UPDATE name = VALUES(name), balance = VALUES(balance), connections = connections + %d, is_online = 1, last_seen = NOW()", g_sSteamID[iClient], sEscName, Cel_GetClientBalance(iClient), bReturning ? 0 : 1);
	g_dbCelMod.Query(SQL_Generic, sQuery);

	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO cm_sessions (steamid64, server_id, map) VALUES ('%s', %d, '%s')", g_sSteamID[iClient], g_cvServerID.IntValue, g_sMap);
	g_dbCelMod.Query(SQL_OnSessionCreated, sQuery, GetClientUserId(iClient));

	if (!bReturning)
	{
		LogEvent(iClient, "connect", "");

		FormatEx(sQuery, sizeof(sQuery), "INSERT INTO cm_stats_daily (day, server_id, connections) VALUES (CURDATE(), %d, 1) ON DUPLICATE KEY UPDATE connections = connections + 1", g_cvServerID.IntValue);
		g_dbCelMod.Query(SQL_Generic, sQuery);
	}

	SyncClientPurchases(iClient);
}

public void SQL_OnSessionCreated(Database dbDatabase, DBResultSet rsResults, const char[] sError, int iUserID)
{
	if (rsResults == null)
	{
		LogError("|CelMod| Database error: %s", sError);
		return;
	}

	int iClient = GetClientOfUserId(iUserID);

	if (iClient != 0)
	{
		g_iSessionID[iClient] = rsResults.InsertId;
	}
}

/** Runs on every disconnect, including map changes. */
public void OnClientDisconnect(int iClient)
{
	char sQuery[512];

	if (!g_bTracked[iClient])
	{
		return;
	}

	g_bTracked[iClient] = false;

	if (g_dbCelMod == null)
	{
		return;
	}

	FormatEx(sQuery, sizeof(sQuery), "UPDATE cm_players SET balance = %d, last_seen = NOW(), playtime_seconds = playtime_seconds + %d, props_spawned = props_spawned + %d, cels_spawned = cels_spawned + %d, effects_spawned = effects_spawned + %d, entities_removed = entities_removed + %d WHERE steamid64 = '%s'", Cel_GetClientBalance(iClient), GetTime() - g_iPlayMark[iClient], g_iPendingProps[iClient], g_iPendingCels[iClient], g_iPendingEffects[iClient], g_iPendingRemoved[iClient], g_sSteamID[iClient]);
	g_dbCelMod.Query(SQL_Generic, sQuery);

	if (g_iSessionID[iClient] > 0)
	{
		FormatEx(sQuery, sizeof(sQuery), "UPDATE cm_sessions SET ended_at = NOW() WHERE id = %d", g_iSessionID[iClient]);
		g_dbCelMod.Query(SQL_Generic, sQuery);
		g_iSessionID[iClient] = 0;
	}

	g_smRecentlyLeft.SetValue(g_sSteamID[iClient], GetTime());
}

/** Only fires when a player really leaves (not on map change). */
public Action Event_PlayerDisconnect(Event eEvent, const char[] sName, bool bDontBroadcast)
{
	char sQuery[256], sSteamID[32];
	int iClient = GetClientOfUserId(eEvent.GetInt("userid"));

	if (iClient == 0 || IsFakeClient(iClient) || g_dbCelMod == null || !GetClientAuthId(iClient, AuthId_SteamID64, sSteamID, sizeof(sSteamID), false))
	{
		return Plugin_Continue;
	}

	LogEvent(iClient, "disconnect", "");

	FormatEx(sQuery, sizeof(sQuery), "UPDATE cm_players SET is_online = 0 WHERE steamid64 = '%s'", sSteamID);
	g_dbCelMod.Query(SQL_Generic, sQuery);

	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM cm_online_players WHERE server_id = %d AND steamid64 = '%s'", g_cvServerID.IntValue, sSteamID);
	g_dbCelMod.Query(SQL_Generic, sQuery);

	g_smRecentlyLeft.Remove(sSteamID);

	return Plugin_Continue;
}

void SyncClientPurchases(int iClient)
{
	char sItem[64], sQuery[256];

	for (int i = 0; i < g_alShopItems.Length; i++)
	{
		g_alShopItems.GetString(i, sItem, sizeof(sItem));

		if (Cel_ShopOwnsItem(iClient, sItem))
		{
			FormatEx(sQuery, sizeof(sQuery), "INSERT IGNORE INTO cm_purchases (steamid64, item, source) VALUES ('%s', '%s', 'game')", g_sSteamID[iClient], sItem);

			DataPack dpPurchase = new DataPack();
			dpPurchase.WriteCell(GetClientUserId(iClient));
			dpPurchase.WriteCell(g_bPurchasesSynced[iClient]);
			dpPurchase.WriteString(sItem);

			g_dbCelMod.Query(SQL_OnPurchaseSynced, sQuery, dpPurchase);
		}
	}

	g_bPurchasesSynced[iClient] = true;
}

public void SQL_OnPurchaseSynced(Database dbDatabase, DBResultSet rsResults, const char[] sError, DataPack dpPurchase)
{
	char sItem[64];

	dpPurchase.Reset();
	int iClient = GetClientOfUserId(dpPurchase.ReadCell());
	bool bAnnounce = view_as<bool>(dpPurchase.ReadCell());
	dpPurchase.ReadString(sItem, sizeof(sItem));
	delete dpPurchase;

	if (rsResults == null)
	{
		LogError("|CelMod| Database error: %s", sError);
		return;
	}

	// A brand new row after the first sync means they just bought it in-game.
	if (bAnnounce && iClient != 0 && rsResults.AffectedRows == 1)
	{
		LogEvent(iClient, "purchase", sItem);
	}
}

//Live data:
public Action Timer_Heartbeat(Handle hTimer)
{
	char sAddress[64], sEscHost[257], sEscName[257], sHostname[128], sName[128], sQuery[1536];
	int iPlayers, iTotalCels, iTotalProps;

	if (g_dbCelMod == null)
	{
		return Plugin_Continue;
	}

	int iServerID = g_cvServerID.IntValue;

	Transaction txBeat = new Transaction();

	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM cm_online_players WHERE server_id = %d", iServerID);
	txBeat.AddQuery(sQuery);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		iPlayers++;
		iTotalProps += Cel_GetPropCount(i);
		iTotalCels += Cel_GetCelCount(i);

		if (!g_bTracked[i])
		{
			continue;
		}

		GetClientName(i, sName, sizeof(sName));
		g_dbCelMod.Escape(sName, sEscName, sizeof(sEscName));

		FormatEx(sQuery, sizeof(sQuery), "INSERT INTO cm_online_players (server_id, steamid64, name, props, cels, balance, joined_at) VALUES (%d, '%s', '%s', %d, %d, %d, FROM_UNIXTIME(%d))", iServerID, g_sSteamID[i], sEscName, Cel_GetPropCount(i), Cel_GetCelCount(i), Cel_GetClientBalance(i), g_iJoinTime[i]);
		txBeat.AddQuery(sQuery);

		FormatEx(sQuery, sizeof(sQuery), "UPDATE cm_players SET name = '%s', balance = %d, is_online = 1, last_seen = NOW(), playtime_seconds = playtime_seconds + %d, props_spawned = props_spawned + %d, cels_spawned = cels_spawned + %d, effects_spawned = effects_spawned + %d, entities_removed = entities_removed + %d WHERE steamid64 = '%s'", sEscName, Cel_GetClientBalance(i), GetTime() - g_iPlayMark[i], g_iPendingProps[i], g_iPendingCels[i], g_iPendingEffects[i], g_iPendingRemoved[i], g_sSteamID[i]);
		txBeat.AddQuery(sQuery);

		g_iPlayMark[i] = GetTime();
		g_iPendingProps[i] = 0;
		g_iPendingCels[i] = 0;
		g_iPendingEffects[i] = 0;
		g_iPendingRemoved[i] = 0;
	}

	FindConVar("hostname").GetString(sHostname, sizeof(sHostname));
	g_dbCelMod.Escape(sHostname, sEscHost, sizeof(sEscHost));
	GetServerAddress(sAddress, sizeof(sAddress));

	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO cm_servers (server_id, hostname, address, map, players, max_players, total_props, total_cels, version, map_started, updated_at) VALUES (%d, '%s', '%s', '%s', %d, %d, %d, %d, '%s', FROM_UNIXTIME(%d), NOW()) ON DUPLICATE KEY UPDATE hostname = VALUES(hostname), address = VALUES(address), map = VALUES(map), players = VALUES(players), max_players = VALUES(max_players), total_props = VALUES(total_props), total_cels = VALUES(total_cels), version = VALUES(version), map_started = VALUES(map_started), updated_at = NOW()", iServerID, sEscHost, sAddress, g_sMap, iPlayers, MaxClients, iTotalProps, iTotalCels, CEL_VERSION, g_iMapStart);
	txBeat.AddQuery(sQuery);

	// Anyone not on a live server (e.g. after a crash) is no longer online.
	txBeat.AddQuery("DELETE o FROM cm_online_players o JOIN cm_servers s ON s.server_id = o.server_id WHERE s.updated_at < NOW() - INTERVAL 5 MINUTE");
	txBeat.AddQuery("UPDATE cm_players p LEFT JOIN cm_online_players o ON o.steamid64 = p.steamid64 SET p.is_online = 0 WHERE p.is_online = 1 AND o.steamid64 IS NULL");

	g_dbCelMod.Execute(txBeat, SQL_OnTxnOk, SQL_OnTxnError);

	FlushDailyStats(iPlayers);

	// Pick up in-game purchases and stock changes about once a minute.
	if (++g_iTick % 4 == 0)
	{
		SyncShopItems();

		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_bTracked[i])
			{
				SyncClientPurchases(i);
			}
		}
	}

	return Plugin_Continue;
}

void FlushDailyStats(int iPlayers)
{
	char sQuery[512];

	if (g_dbCelMod == null)
	{
		return;
	}

	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO cm_stats_daily (day, server_id, peak_players, props_spawned, cels_spawned, effects_spawned) VALUES (CURDATE(), %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE peak_players = GREATEST(peak_players, VALUES(peak_players)), props_spawned = props_spawned + VALUES(props_spawned), cels_spawned = cels_spawned + VALUES(cels_spawned), effects_spawned = effects_spawned + VALUES(effects_spawned)", g_cvServerID.IntValue, iPlayers, g_iDayProps, g_iDayCels, g_iDayEffects);
	g_dbCelMod.Query(SQL_Generic, sQuery);

	g_iDayProps = 0;
	g_iDayCels = 0;
	g_iDayEffects = 0;
}

public Action Timer_Sample(Handle hTimer)
{
	char sQuery[256];
	int iPlayers;

	if (g_dbCelMod == null)
	{
		return Plugin_Continue;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			iPlayers++;
		}
	}

	FormatEx(sQuery, sizeof(sQuery), "INSERT IGNORE INTO cm_player_samples (server_id, recorded_at, players) VALUES (%d, NOW(), %d)", g_cvServerID.IntValue, iPlayers);
	g_dbCelMod.Query(SQL_Generic, sQuery);

	return Plugin_Continue;
}

void LogMapStart()
{
	char sQuery[256];

	if (g_bMapLogged || g_sMap[0] == '\0')
	{
		return;
	}

	g_bMapLogged = true;

	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO cm_maps (map, times_played, last_played) VALUES ('%s', 1, NOW()) ON DUPLICATE KEY UPDATE times_played = times_played + 1, last_played = NOW()", g_sMap);
	g_dbCelMod.Query(SQL_Generic, sQuery);

	LogEvent(0, "map_change", g_sMap);
}

void LogEvent(int iClient, const char[] sType, const char[] sDetail)
{
	char sEscDetail[257], sEscName[257], sName[128], sQuery[768], sSteam[40];

	if (g_dbCelMod == null)
	{
		return;
	}

	if (iClient > 0)
	{
		GetClientName(iClient, sName, sizeof(sName));
		FormatEx(sSteam, sizeof(sSteam), "'%s'", g_sSteamID[iClient]);
	} else {
		strcopy(sName, sizeof(sName), "Server");
		strcopy(sSteam, sizeof(sSteam), "NULL");
	}

	g_dbCelMod.Escape(sName, sEscName, sizeof(sEscName));
	g_dbCelMod.Escape(sDetail, sEscDetail, sizeof(sEscDetail));

	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO cm_events (server_id, steamid64, name, type, detail) VALUES (%d, %s, '%s', '%s', '%s')", g_cvServerID.IntValue, sSteam, sEscName, sType, sEscDetail);
	g_dbCelMod.Query(SQL_Generic, sQuery);
}

void GetServerAddress(char[] sAddress, int iMaxLength)
{
	g_cvAddress.GetString(sAddress, iMaxLength);

	if (sAddress[0] != '\0')
	{
		return;
	}

	int iIP = FindConVar("hostip").IntValue;

	FormatEx(sAddress, iMaxLength, "%d.%d.%d.%d:%d", (iIP >>> 24) & 0xFF, (iIP >>> 16) & 0xFF, (iIP >>> 8) & 0xFF, iIP & 0xFF, FindConVar("hostport").IntValue);
}

//Spawn counters:
public void Cel_OnPropSpawn(int iProp, int iOwner, EntityType etEntityType)
{
	if (iOwner > 0 && iOwner <= MaxClients)
	{
		g_iPendingProps[iOwner]++;
	}
	g_iDayProps++;
}

public void Cel_OnCelSpawn(int iCel, int iOwner, EntityType etEntityType)
{
	if (iOwner > 0 && iOwner <= MaxClients)
	{
		g_iPendingCels[iOwner]++;
	}
	g_iDayCels++;
}

public void Cel_OnEffectSpawn(int iEffect, int iOwner, EffectType etEffectType)
{
	if (iOwner > 0 && iOwner <= MaxClients)
	{
		g_iPendingEffects[iOwner]++;
	}
	g_iDayEffects++;
}

public void Cel_OnEntityRemove(int iEntity, int iOwner, bool bCel)
{
	if (iOwner > 0 && iOwner <= MaxClients)
	{
		g_iPendingRemoved[iOwner]++;
	}
}

//Web shop orders:
public Action Timer_PollOrders(Handle hTimer)
{
	char sIDs[2048], sQuery[2304];

	if (g_dbCelMod == null)
	{
		return Plugin_Continue;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bTracked[i])
		{
			if (sIDs[0] != '\0')
			{
				StrCat(sIDs, sizeof(sIDs), ",");
			}
			Format(sIDs, sizeof(sIDs), "%s'%s'", sIDs, g_sSteamID[i]);
		}
	}

	if (sIDs[0] == '\0')
	{
		return Plugin_Continue;
	}

	FormatEx(sQuery, sizeof(sQuery), "SELECT id, steamid64, item, price FROM cm_web_orders WHERE status = 'pending' AND steamid64 IN (%s) ORDER BY id LIMIT 10", sIDs);
	g_dbCelMod.Query(SQL_OnPendingOrders, sQuery);

	return Plugin_Continue;
}

public void SQL_OnPendingOrders(Database dbDatabase, DBResultSet rsResults, const char[] sError, any aData)
{
	char sItem[64], sQuery[256], sSteamID[32];

	if (rsResults == null)
	{
		LogError("|CelMod| Database error: %s", sError);
		return;
	}

	while (rsResults.FetchRow())
	{
		int iOrder = rsResults.FetchInt(0);
		rsResults.FetchString(1, sSteamID, sizeof(sSteamID));
		rsResults.FetchString(2, sItem, sizeof(sItem));
		int iOrderPrice = rsResults.FetchInt(3);

		// Claim the order first so two servers can never deliver it twice.
		FormatEx(sQuery, sizeof(sQuery), "UPDATE cm_web_orders SET status = 'processing', server_id = %d WHERE id = %d AND status = 'pending'", g_cvServerID.IntValue, iOrder);

		DataPack dpOrder = new DataPack();
		dpOrder.WriteCell(iOrder);
		dpOrder.WriteString(sSteamID);
		dpOrder.WriteString(sItem);
		dpOrder.WriteCell(iOrderPrice);

		g_dbCelMod.Query(SQL_OnOrderClaimed, sQuery, dpOrder);
	}
}

public void SQL_OnOrderClaimed(Database dbDatabase, DBResultSet rsResults, const char[] sError, DataPack dpOrder)
{
	char sDeliverError[128], sItem[64], sQuery[512], sSteamID[32];
	int iClient;

	dpOrder.Reset();
	int iOrder = dpOrder.ReadCell();
	dpOrder.ReadString(sSteamID, sizeof(sSteamID));
	dpOrder.ReadString(sItem, sizeof(sItem));
	int iOrderPrice = dpOrder.ReadCell();
	delete dpOrder;

	if (rsResults == null)
	{
		LogError("|CelMod| Database error: %s", sError);
		return;
	}

	if (rsResults.AffectedRows != 1)
	{
		return; // another server took it
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bTracked[i] && StrEqual(g_sSteamID[i], sSteamID))
		{
			iClient = i;
			break;
		}
	}

	if (iClient == 0)
	{
		FormatEx(sQuery, sizeof(sQuery), "UPDATE cm_web_orders SET status = 'pending', server_id = NULL WHERE id = %d", iOrder);
		g_dbCelMod.Query(SQL_Generic, sQuery);
		return;
	}

	// celmod-shop checks the item, stock, ownership and balance, charges and gives it.
	// It never charges more than the price the player saw on the website.
	int iPrice = Cel_ShopDeliver(iClient, sItem, iOrderPrice, sDeliverError, sizeof(sDeliverError));

	if (iPrice == -1)
	{
		FinishOrder(iOrder, "failed", sDeliverError);
		Cel_PrintToChat(iClient, "Your web shop order for {green}%s{default} failed: %s", sItem, sDeliverError);
		return;
	}

	Cel_PrintToChat(iClient, "Your web shop order for {green}%s{default} has arrived!", sItem);

	FormatEx(sQuery, sizeof(sQuery), "UPDATE cm_web_orders SET price = %d WHERE id = %d", iPrice, iOrder);
	g_dbCelMod.Query(SQL_Generic, sQuery);
	FinishOrder(iOrder, "completed", "Delivered in-game.");

	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO cm_purchases (steamid64, item, source) VALUES ('%s', '%s', 'web') ON DUPLICATE KEY UPDATE source = 'web'", sSteamID, sItem);
	g_dbCelMod.Query(SQL_Generic, sQuery);

	FormatEx(sQuery, sizeof(sQuery), "UPDATE cm_players SET balance = %d WHERE steamid64 = '%s'", Cel_GetClientBalance(iClient), sSteamID);
	g_dbCelMod.Query(SQL_Generic, sQuery);

	LogEvent(iClient, "web_purchase", sItem);

	SyncShopItems(); // stock went down
}

void FinishOrder(int iOrder, const char[] sStatus, const char[] sMessage)
{
	char sEscMessage[512], sQuery[768];

	g_dbCelMod.Escape(sMessage, sEscMessage, sizeof(sEscMessage));

	FormatEx(sQuery, sizeof(sQuery), "UPDATE cm_web_orders SET status = '%s', message = '%s', processed_at = NOW() WHERE id = %d", sStatus, sEscMessage, iOrder);
	g_dbCelMod.Query(SQL_Generic, sQuery);
}

//Callbacks:
public void SQL_OnMigration(Database dbDatabase, DBResultSet rsResults, const char[] sError, any aData)
{
	if (rsResults == null && StrContains(sError, "Duplicate column", false) == -1)
	{
		LogError("|CelMod| Database upgrade failed: %s", sError);
	}
}

public void SQL_Generic(Database dbDatabase, DBResultSet rsResults, const char[] sError, any aData)
{
	if (rsResults == null)
	{
		LogError("|CelMod| Database error: %s", sError);
	}
}

public void SQL_OnTxnOk(Database dbDatabase, any aData, int iNumQueries, DBResultSet[] rsResults, any[] aQueryData)
{
}

public void SQL_OnTxnError(Database dbDatabase, any aData, int iNumQueries, const char[] sError, int iFailIndex, any[] aQueryData)
{
	LogError("|CelMod| Database transaction failed at query %d: %s", iFailIndex, sError);
}

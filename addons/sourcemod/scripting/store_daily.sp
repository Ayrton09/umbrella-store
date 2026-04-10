#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dbi>
#include <umbrella_store>

#define US_CHAT_TAG " \x03[Umbrella Store]\x01"

#define DAILY_LOG_PREFIX     "[Umbrella Daily]"

Database g_DB = null;
bool g_bIsMySQL = false;
bool g_bReady = false;
bool g_bBusy[MAXPLAYERS + 1];

ConVar gCvarEnabled;
ConVar gCvarBaseCredits;
ConVar gCvarStreakBonus;
ConVar gCvarMaxStreakDays;
ConVar gCvarCooldownHours;
ConVar gCvarGraceHours;
ConVar gCvarAnnounceOnJoin;

public Plugin myinfo =
{
    name = "[Umbrella Store] Daily Reward",
    author = "Ayrton09",
    description = "Daily reward module for Umbrella Store",
    version = "1.0.0"
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store_daily.phrases");
    RegConsoleCmd("sm_daily", Cmd_Daily);
    RegConsoleCmd("sm_diario", Cmd_Daily);

    gCvarEnabled        = CreateConVar("store_daily_enabled", "1", "Enable !daily module.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarBaseCredits    = CreateConVar("store_daily_base_credits", "50", "Base credits for daily reward.", FCVAR_NONE, true, 1.0);
    gCvarStreakBonus    = CreateConVar("store_daily_streak_bonus", "25", "Extra bonus for each streak day.", FCVAR_NONE, true, 0.0);
    gCvarMaxStreakDays  = CreateConVar("store_daily_max_streak_days", "7", "Maximum streak days that scale the reward.", FCVAR_NONE, true, 1.0);
    gCvarCooldownHours  = CreateConVar("store_daily_cooldown_hours", "24", "Required hours between claims.", FCVAR_NONE, true, 1.0);
    gCvarGraceHours     = CreateConVar("store_daily_grace_hours", "48", "If more than this many hours pass, streak resets.", FCVAR_NONE, true, 1.0);
    gCvarAnnounceOnJoin = CreateConVar("store_daily_announce_on_join", "1", "Announce on join that !daily exists.", FCVAR_NONE, true, 0.0, true, 1.0);

    AutoExecConfig(true, "umbrella_store_daily");
}

public void OnConfigsExecuted()
{
    if (g_DB == null)
    {
        ConnectDatabase();
    }
}

public void OnClientPutInServer(int client)
{
    if (!IsValidHuman(client))
    {
        return;
    }

    g_bBusy[client] = false;

    if (gCvarAnnounceOnJoin.BoolValue)
    {
        CreateTimer(12.0, Timer_AnnounceDaily, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnClientDisconnect(int client)
{
    if (client >= 1 && client <= MaxClients)
    {
        g_bBusy[client] = false;
    }
}

public Action Timer_AnnounceDaily(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidHuman(client))
    {
        return Plugin_Stop;
    }

    DailyChat(client, "%t", "Daily Announce");
    return Plugin_Stop;
}
void DailyChat(int client, const char[] format, any ...)
{
    if (!IsValidHuman(client))
    {
        return;
    }

    char buffer[256], highlighted[320];
    SetGlobalTransTarget(client);
    VFormat(buffer, sizeof(buffer), format, 3);
    HighlightChatCommands(buffer, highlighted, sizeof(highlighted));
    PrintToChat(client, "%s %s", US_CHAT_TAG, highlighted);
}

bool IsCommandContinuationChar(int c)
{
    return (c >= 'a' && c <= 'z')
        || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9')
        || c == '_'
        || c == '-'
        || c == '/';
}

void HighlightChatCommands(const char[] input, char[] output, int maxlen)
{
    int inLen = strlen(input);
    int outPos = 0;
    bool inCommand = false;

    for (int i = 0; i < inLen && outPos < maxlen - 1; i++)
    {
        int ch = input[i];

        if (!inCommand && ch == '!' && (i + 1) < inLen && IsCommandContinuationChar(input[i + 1]))
        {
            if (outPos < maxlen - 1)
            {
                output[outPos++] = '\x04';
            }
            output[outPos++] = ch;
            inCommand = true;
            continue;
        }

        if (inCommand && !IsCommandContinuationChar(ch))
        {
            if (outPos < maxlen - 1)
            {
                output[outPos++] = '\x01';
            }
            inCommand = false;
        }

        if (outPos < maxlen - 1)
        {
            output[outPos++] = ch;
        }
    }

    if (inCommand && outPos < maxlen - 1)
    {
        output[outPos++] = '\x01';
    }

    output[outPos] = '\0';
}

bool IsValidHuman(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

void LogDailyError(const char[] where, const char[] error)
{
    if (error[0] != '\0')
    {
        LogError("%s %s: %s", DAILY_LOG_PREFIX, where, error);
    }
}

bool GetClientSteamIdSafe(int client, char[] steamid, int maxlen)
{
    if (!GetClientAuthId(client, AuthId_Steam2, steamid, maxlen))
    {
        steamid[0] = '\0';
        return false;
    }
    return true;
}

void EscapeStringSafe(const char[] input, char[] output, int maxlen)
{
    if (g_DB == null)
    {
        strcopy(output, maxlen, input);
        return;
    }

    g_DB.Escape(input, output, maxlen);
}

void ConnectDatabase()
{
    char dbConfig[64];

    ConVar storeDatabase = FindConVar("store_database");
    if (storeDatabase == null)
    {
        char failMsg[256];
        Format(failMsg, sizeof(failMsg), "%s Required core cvar 'store_database' was not found. Load Umbrella Store core before Umbrella Daily.", DAILY_LOG_PREFIX);
        LogError("%s", failMsg);
        SetFailState("%s", failMsg);
        return;
    }

    storeDatabase.GetString(dbConfig, sizeof(dbConfig));
    TrimString(dbConfig);
    if (dbConfig[0] == '\0')
    {
        char failMsg[256];
        Format(failMsg, sizeof(failMsg), "%s Core cvar 'store_database' is empty. Set it in umbrella_store_core.cfg to a valid databases.cfg entry.", DAILY_LOG_PREFIX);
        LogError("%s", failMsg);
        SetFailState("%s", failMsg);
        return;
    }

    if (SQL_CheckConfig(dbConfig))
    {
        Database.Connect(OnDBConnect, dbConfig);
        return;
    }

    char failMsg[256];
    Format(failMsg, sizeof(failMsg), "%s Database config '%s' not found in databases.cfg. Set store_database in Umbrella Store core to a valid entry.", DAILY_LOG_PREFIX, dbConfig);
    LogError("%s", failMsg);
    SetFailState("%s", failMsg);
}

public void OnDBConnect(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogDailyError("OnDBConnect", error);

        char failMsg[256];
        char dbConfig[64];
        ConVar storeDatabase = FindConVar("store_database");
        if (storeDatabase == null)
        {
            Format(failMsg, sizeof(failMsg), "%s Required core cvar 'store_database' was not found during database connection. Load Umbrella Store core before Umbrella Daily.", DAILY_LOG_PREFIX);
            SetFailState("%s", failMsg);
            return;
        }
        storeDatabase.GetString(dbConfig, sizeof(dbConfig));
        TrimString(dbConfig);

        Format(failMsg, sizeof(failMsg), "%s Failed to connect to database config '%s'. Check databases.cfg and connection settings.", DAILY_LOG_PREFIX, dbConfig);
        SetFailState("%s", failMsg);
        return;
    }

    g_DB = db;
    SetupDatabaseMode();
    CreateDailyTable();
}

void SetupDatabaseMode()
{
    if (g_DB == null)
    {
        return;
    }

    char driver[16];
    g_DB.Driver.GetIdentifier(driver, sizeof(driver));
    g_bIsMySQL = StrEqual(driver, "mysql", false);
}

void CreateDailyTable()
{
    char query[256];

    if (g_bIsMySQL)
    {
        Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS store_daily_rewards (steamid VARCHAR(32) PRIMARY KEY, last_claim INT NOT NULL DEFAULT 0, streak INT NOT NULL DEFAULT 0)");
    }
    else
    {
        Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS store_daily_rewards (steamid TEXT PRIMARY KEY, last_claim INTEGER NOT NULL DEFAULT 0, streak INTEGER NOT NULL DEFAULT 0)");
    }

    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogDailyError("CreateDailyTable", error);
        SetFailState("%s Failed to create or validate store_daily_rewards table.", DAILY_LOG_PREFIX);
        return;
    }

    g_bReady = true;
}

public void SQL_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || error[0] == '\0')
    {
        return;
    }

    LogDailyError("SQL_Callback", error);
}

public Action Cmd_Daily(int client, int args)
{
    if (!IsValidHuman(client) || !US_IsLoaded(client))
    {
        return Plugin_Handled;
    }

    if (!gCvarEnabled.BoolValue)
    {
        DailyChat(client, "%t", "Daily Disabled");
        return Plugin_Handled;
    }

    if (!g_bReady || g_DB == null)
    {
        DailyChat(client, "%t", "Daily Not Ready");
        return Plugin_Handled;
    }

    if (g_bBusy[client])
    {
        DailyChat(client, "%t", "Daily Busy");
        return Plugin_Handled;
    }

    char steam[32], safeSteam[64], query[256];
    if (!GetClientSteamIdSafe(client, steam, sizeof(steam)))
    {
        DailyChat(client, "%t", "Daily SteamId Error");
        return Plugin_Handled;
    }

    EscapeStringSafe(steam, safeSteam, sizeof(safeSteam));
    Format(query, sizeof(query), "SELECT last_claim, streak FROM store_daily_rewards WHERE steamid='%s'", safeSteam);

    g_bBusy[client] = true;
    g_DB.Query(OnDailyLoaded, query, GetClientUserId(client));
    return Plugin_Handled;
}

public void OnDailyLoaded(Database db, DBResultSet results, const char[] error, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidHuman(client))
    {
        return;
    }

    if (db == null || results == null || error[0] != '\0')
    {
        LogDailyError("OnDailyLoaded", error);
        DailyChat(client, "%t", "Daily Load Error");
        g_bBusy[client] = false;
        return;
    }

    int last = 0;
    int streak = 0;

    if (results.FetchRow())
    {
        last = results.FetchInt(0);
        streak = results.FetchInt(1);
    }

    int now = GetTime();
    int cooldown = gCvarCooldownHours.IntValue * 3600;
    int grace = gCvarGraceHours.IntValue * 3600;

    if (last > 0)
    {
        int elapsed = now - last;

        if (elapsed < cooldown)
        {
            int remain = cooldown - elapsed;
            int h = remain / 3600;
            int m = (remain % 3600) / 60;
            DailyChat(client, "%t", "Daily Cooldown", h, m);
            g_bBusy[client] = false;
            return;
        }

        if (elapsed <= grace)
        {
            streak++;
        }
        else
        {
            streak = 1;
        }
    }
    else
    {
        streak = 1;
    }

    int base = gCvarBaseCredits.IntValue;
    int bonus = gCvarStreakBonus.IntValue;
    int maxDays = gCvarMaxStreakDays.IntValue;

    int level = streak;
    if (level > maxDays)
    {
        level = maxDays;
    }

    int reward = base + ((level - 1) * bonus);

    if (!US_AddCredits(client, reward, false))
    {
        DailyChat(client, "%t", "Daily Add Credits Error");
        g_bBusy[client] = false;
        return;
    }

    if (!SaveClaim(client, now, streak))
    {
        if (!US_TakeCredits(client, reward))
        {
            LogError("%s Failed to rollback %d credits for client %N after claim persistence error.", DAILY_LOG_PREFIX, reward, client);
        }

        DailyChat(client, "%t", "Daily Load Error");
        g_bBusy[client] = false;
        return;
    }

    DailyChat(client, "%t", "Daily Claimed", reward, streak);
    g_bBusy[client] = false;
}

bool SaveClaim(int client, int time, int streak)
{
    char steam[32], safeSteam[64], query[256];
    if (!GetClientSteamIdSafe(client, steam, sizeof(steam)))
    {
        return false;
    }

    EscapeStringSafe(steam, safeSteam, sizeof(safeSteam));

    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "INSERT INTO store_daily_rewards (steamid,last_claim,streak) VALUES ('%s',%d,%d) ON DUPLICATE KEY UPDATE last_claim=%d, streak=%d",
            safeSteam, time, streak, time, streak);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT OR REPLACE INTO store_daily_rewards (steamid,last_claim,streak) VALUES ('%s',%d,%d)",
            safeSteam, time, streak);
    }

    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogDailyError("SaveClaim", error);
        return false;
    }

    return true;
}


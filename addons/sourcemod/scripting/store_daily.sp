#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dbi>
#include <umbrella_store>
#include <multicolors>

#define US_CHAT_TAG " {purple}[Umbrella Store]{default}"
#define DAILY_LOG_PREFIX "[Umbrella Daily]"
#define DAILY_TABLE_ID "umbrella_store_daily_rewards"

Database g_DB = null;
bool g_bReady = false;
bool g_bBusy[MAXPLAYERS + 1];

ConVar gCvarEnabled;
ConVar gCvarBaseCredits;
ConVar gCvarStreakBonus;
ConVar gCvarMaxStreakDays;
ConVar gCvarCooldownHours;
ConVar gCvarGraceHours;
ConVar gCvarAnnounceOnJoin;
ConVar gLegacyCvarEnabled;
ConVar gLegacyCvarBaseCredits;
ConVar gLegacyCvarStreakBonus;
ConVar gLegacyCvarMaxStreakDays;
ConVar gLegacyCvarCooldownHours;
ConVar gLegacyCvarGraceHours;
ConVar gLegacyCvarAnnounceOnJoin;
bool g_bSyncingCvarAliases = false;

public Plugin myinfo =
{
    name = "[Umbrella Store] Daily Reward",
    author = "Ayrton09",
    description = "Daily reward module for Umbrella Store",
    version = "1.1.0"
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store_daily.phrases");

    RegConsoleCmd("sm_daily", Cmd_Daily);
    RegConsoleCmd("sm_diario", Cmd_Daily);

    gCvarEnabled        = CreateConVar("umbrella_store_daily_enabled", "1", "Enable !daily module.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarBaseCredits    = CreateConVar("umbrella_store_daily_base_credits", "50", "Base credits for daily reward.", FCVAR_NONE, true, 1.0);
    gCvarStreakBonus    = CreateConVar("umbrella_store_daily_streak_bonus", "25", "Extra bonus for each streak day.", FCVAR_NONE, true, 0.0);
    gCvarMaxStreakDays  = CreateConVar("umbrella_store_daily_max_streak_days", "7", "Maximum streak days that scale the reward.", FCVAR_NONE, true, 1.0);
    gCvarCooldownHours  = CreateConVar("umbrella_store_daily_cooldown_hours", "24", "Required hours between claims.", FCVAR_NONE, true, 1.0);
    gCvarGraceHours     = CreateConVar("umbrella_store_daily_grace_hours", "48", "If more than this many hours pass, streak resets.", FCVAR_NONE, true, 1.0);
    gCvarAnnounceOnJoin = CreateConVar("umbrella_store_daily_announce_on_join", "1", "Announce on join that !daily exists.", FCVAR_NONE, true, 0.0, true, 1.0);

    gLegacyCvarEnabled        = CreateConVar("store_daily_enabled", "1", "Legacy alias for umbrella_store_daily_enabled.", FCVAR_DONTRECORD, true, 0.0, true, 1.0);
    gLegacyCvarBaseCredits    = CreateConVar("store_daily_base_credits", "50", "Legacy alias for umbrella_store_daily_base_credits.", FCVAR_DONTRECORD, true, 1.0);
    gLegacyCvarStreakBonus    = CreateConVar("store_daily_streak_bonus", "25", "Legacy alias for umbrella_store_daily_streak_bonus.", FCVAR_DONTRECORD, true, 0.0);
    gLegacyCvarMaxStreakDays  = CreateConVar("store_daily_max_streak_days", "7", "Legacy alias for umbrella_store_daily_max_streak_days.", FCVAR_DONTRECORD, true, 1.0);
    gLegacyCvarCooldownHours  = CreateConVar("store_daily_cooldown_hours", "24", "Legacy alias for umbrella_store_daily_cooldown_hours.", FCVAR_DONTRECORD, true, 1.0);
    gLegacyCvarGraceHours     = CreateConVar("store_daily_grace_hours", "48", "Legacy alias for umbrella_store_daily_grace_hours.", FCVAR_DONTRECORD, true, 1.0);
    gLegacyCvarAnnounceOnJoin = CreateConVar("store_daily_announce_on_join", "1", "Legacy alias for umbrella_store_daily_announce_on_join.", FCVAR_DONTRECORD, true, 0.0, true, 1.0);

    HookConVarChange(gCvarEnabled, OnDailyAliasCvarChanged);
    HookConVarChange(gCvarBaseCredits, OnDailyAliasCvarChanged);
    HookConVarChange(gCvarStreakBonus, OnDailyAliasCvarChanged);
    HookConVarChange(gCvarMaxStreakDays, OnDailyAliasCvarChanged);
    HookConVarChange(gCvarCooldownHours, OnDailyAliasCvarChanged);
    HookConVarChange(gCvarGraceHours, OnDailyAliasCvarChanged);
    HookConVarChange(gCvarAnnounceOnJoin, OnDailyAliasCvarChanged);
    HookConVarChange(gLegacyCvarEnabled, OnDailyAliasCvarChanged);
    HookConVarChange(gLegacyCvarBaseCredits, OnDailyAliasCvarChanged);
    HookConVarChange(gLegacyCvarStreakBonus, OnDailyAliasCvarChanged);
    HookConVarChange(gLegacyCvarMaxStreakDays, OnDailyAliasCvarChanged);
    HookConVarChange(gLegacyCvarCooldownHours, OnDailyAliasCvarChanged);
    HookConVarChange(gLegacyCvarGraceHours, OnDailyAliasCvarChanged);
    HookConVarChange(gLegacyCvarAnnounceOnJoin, OnDailyAliasCvarChanged);

    AutoExecConfig(true, "umbrella_store_daily");
    SyncDailyLegacyCvarsFromCanonical();
    RegisterDailyQuests();
}

public void OnConfigsExecuted()
{
    TryBootstrapDailyStorage(false);
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "umbrella_store", false))
    {
        RegisterDailyQuests();
        TryBootstrapDailyStorage(false);
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (!StrEqual(name, "umbrella_store", false))
    {
        return;
    }

    g_bReady = false;

    if (g_DB != null)
    {
        delete g_DB;
        g_DB = null;
    }
}

public void OnPluginEnd()
{
    if (g_DB != null)
    {
        delete g_DB;
        g_DB = null;
    }
}

void RegisterDailyQuests()
{
    US_RegisterQuestEx("daily_claims_3", "Quest Title Daily Claims I", 3, 150, "", false, "Quest Category Daily", "Quest Desc Daily Claims I");
    US_RegisterQuestEx("daily_streak_7", "Quest Title Daily Streak I", 7, 300, "", false, "Quest Category Daily", "Quest Desc Daily Streak I");
}

void SyncDailyCvarPair(ConVar source, ConVar target)
{
    if (source == null || target == null)
    {
        return;
    }

    char value[64];
    source.GetString(value, sizeof(value));
    target.SetString(value);
}

void SyncDailyLegacyCvarsFromCanonical()
{
    g_bSyncingCvarAliases = true;
    SyncDailyCvarPair(gCvarEnabled, gLegacyCvarEnabled);
    SyncDailyCvarPair(gCvarBaseCredits, gLegacyCvarBaseCredits);
    SyncDailyCvarPair(gCvarStreakBonus, gLegacyCvarStreakBonus);
    SyncDailyCvarPair(gCvarMaxStreakDays, gLegacyCvarMaxStreakDays);
    SyncDailyCvarPair(gCvarCooldownHours, gLegacyCvarCooldownHours);
    SyncDailyCvarPair(gCvarGraceHours, gLegacyCvarGraceHours);
    SyncDailyCvarPair(gCvarAnnounceOnJoin, gLegacyCvarAnnounceOnJoin);
    g_bSyncingCvarAliases = false;
}

public void OnDailyAliasCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (g_bSyncingCvarAliases)
    {
        return;
    }

    g_bSyncingCvarAliases = true;

    if (convar == gCvarEnabled)
    {
        gLegacyCvarEnabled.SetString(newValue);
    }
    else if (convar == gLegacyCvarEnabled)
    {
        gCvarEnabled.SetString(newValue);
    }
    else if (convar == gCvarBaseCredits)
    {
        gLegacyCvarBaseCredits.SetString(newValue);
    }
    else if (convar == gLegacyCvarBaseCredits)
    {
        gCvarBaseCredits.SetString(newValue);
    }
    else if (convar == gCvarStreakBonus)
    {
        gLegacyCvarStreakBonus.SetString(newValue);
    }
    else if (convar == gLegacyCvarStreakBonus)
    {
        gCvarStreakBonus.SetString(newValue);
    }
    else if (convar == gCvarMaxStreakDays)
    {
        gLegacyCvarMaxStreakDays.SetString(newValue);
    }
    else if (convar == gLegacyCvarMaxStreakDays)
    {
        gCvarMaxStreakDays.SetString(newValue);
    }
    else if (convar == gCvarCooldownHours)
    {
        gLegacyCvarCooldownHours.SetString(newValue);
    }
    else if (convar == gLegacyCvarCooldownHours)
    {
        gCvarCooldownHours.SetString(newValue);
    }
    else if (convar == gCvarGraceHours)
    {
        gLegacyCvarGraceHours.SetString(newValue);
    }
    else if (convar == gLegacyCvarGraceHours)
    {
        gCvarGraceHours.SetString(newValue);
    }
    else if (convar == gCvarAnnounceOnJoin)
    {
        gLegacyCvarAnnounceOnJoin.SetString(newValue);
    }
    else if (convar == gLegacyCvarAnnounceOnJoin)
    {
        gCvarAnnounceOnJoin.SetString(newValue);
    }

    g_bSyncingCvarAliases = false;
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
    CPrintToChat(client, "%s %s", US_CHAT_TAG, highlighted);
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

void AppendLiteral(char[] output, int maxlen, int &outPos, const char[] literal)
{
    int literalLen = strlen(literal);
    for (int i = 0; i < literalLen && outPos < maxlen - 1; i++)
    {
        output[outPos++] = literal[i];
    }
}

void HighlightChatCommands(const char[] input, char[] output, int maxlen)
{
    int inLen = strlen(input);
    int outPos = 0;
    bool inCommand = false;
    static const char commandStart[] = "{green}";
    static const char commandEnd[] = "{default}";

    for (int i = 0; i < inLen && outPos < maxlen - 1; i++)
    {
        int ch = input[i];

        if (!inCommand && ch == '!' && (i + 1) < inLen && IsCommandContinuationChar(input[i + 1]))
        {
            AppendLiteral(output, maxlen, outPos, commandStart);
            output[outPos++] = ch;
            inCommand = true;
            continue;
        }

        if (inCommand && !IsCommandContinuationChar(ch))
        {
            AppendLiteral(output, maxlen, outPos, commandEnd);
            inCommand = false;
        }

        output[outPos++] = ch;
    }

    if (inCommand && outPos < maxlen - 1)
    {
        AppendLiteral(output, maxlen, outPos, commandEnd);
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
    if (!US_DB_Escape(input, output, maxlen))
    {
        strcopy(output, maxlen, input);
    }
}

bool TryBootstrapDailyStorage(bool failHard)
{
    if (g_bReady && g_DB != null)
    {
        return true;
    }

    if (!US_IsDatabaseReady())
    {
        if (failHard)
        {
            LogError("%s Core database is not ready yet.", DAILY_LOG_PREFIX);
        }
        return false;
    }

    if (g_DB == null)
    {
        Handle dbHandle = US_GetDatabaseHandle();
        if (dbHandle == INVALID_HANDLE)
        {
            if (failHard)
            {
                LogError("%s Failed to clone Umbrella Store database handle.", DAILY_LOG_PREFIX);
            }
            return false;
        }

        g_DB = view_as<Database>(dbHandle);
    }

    static const char mysqlQuery[] =
        "CREATE TABLE IF NOT EXISTS store_daily_rewards (steamid VARCHAR(32) PRIMARY KEY, last_claim INT NOT NULL DEFAULT 0, streak INT NOT NULL DEFAULT 0)";
    static const char sqliteQuery[] =
        "CREATE TABLE IF NOT EXISTS store_daily_rewards (steamid TEXT PRIMARY KEY, last_claim INTEGER NOT NULL DEFAULT 0, streak INTEGER NOT NULL DEFAULT 0)";

    if (!US_DB_EnsureTable(DAILY_TABLE_ID, mysqlQuery, sqliteQuery))
    {
        if (failHard)
        {
            LogError("%s Failed to ensure table store_daily_rewards using core storage layer.", DAILY_LOG_PREFIX);
        }
        return false;
    }

    g_bReady = true;
    return true;
}

bool PersistDailyClaimRecord(const char[] steamid, int lastClaim, int streak)
{
    if (g_DB == null || steamid[0] == '\0')
    {
        return false;
    }

    char safeSteam[64], query[256];
    EscapeStringSafe(steamid, safeSteam, sizeof(safeSteam));

    if (US_IsMySQL())
    {
        Format(query, sizeof(query),
            "INSERT INTO store_daily_rewards (steamid,last_claim,streak) VALUES ('%s',%d,%d) ON DUPLICATE KEY UPDATE last_claim=VALUES(last_claim), streak=VALUES(streak)",
            safeSteam, lastClaim, streak);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO store_daily_rewards (steamid,last_claim,streak) VALUES ('%s',%d,%d) ON CONFLICT(steamid) DO UPDATE SET last_claim=excluded.last_claim, streak=excluded.streak",
            safeSteam, lastClaim, streak);
    }

    SQL_LockDatabase(g_DB);
    bool ok = SQL_FastQuery(g_DB, query);
    if (!ok)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogDailyError("PersistDailyClaimRecord", error);
    }
    SQL_UnlockDatabase(g_DB);
    return ok;
}

bool RestoreDailyClaimRecord(const char[] steamid, bool hadPrevious, int previousLast, int previousStreak)
{
    if (g_DB == null || steamid[0] == '\0')
    {
        return false;
    }

    char safeSteam[64], query[256];
    EscapeStringSafe(steamid, safeSteam, sizeof(safeSteam));

    if (hadPrevious)
    {
        if (US_IsMySQL())
        {
            Format(query, sizeof(query),
                "INSERT INTO store_daily_rewards (steamid,last_claim,streak) VALUES ('%s',%d,%d) ON DUPLICATE KEY UPDATE last_claim=VALUES(last_claim), streak=VALUES(streak)",
                safeSteam, previousLast, previousStreak);
        }
        else
        {
            Format(query, sizeof(query),
                "INSERT INTO store_daily_rewards (steamid,last_claim,streak) VALUES ('%s',%d,%d) ON CONFLICT(steamid) DO UPDATE SET last_claim=excluded.last_claim, streak=excluded.streak",
                safeSteam, previousLast, previousStreak);
        }
    }
    else
    {
        Format(query, sizeof(query), "DELETE FROM store_daily_rewards WHERE steamid='%s'", safeSteam);
    }

    SQL_LockDatabase(g_DB);
    bool ok = SQL_FastQuery(g_DB, query);
    if (!ok)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogDailyError("RestoreDailyClaimRecord", error);
    }
    SQL_UnlockDatabase(g_DB);
    return ok;
}

bool CompleteDailyClaim(int client, const char[] steamid, bool hadPrevious, int previousLast, int previousStreak, int lastClaim, int streak, int reward)
{
    if (!PersistDailyClaimRecord(steamid, lastClaim, streak))
    {
        return false;
    }

    if (!US_AddCredits(client, reward, false))
    {
        if (!RestoreDailyClaimRecord(steamid, hadPrevious, previousLast, previousStreak))
        {
            LogError("%s Failed to rollback daily claim record for %N after reward credit failure.", DAILY_LOG_PREFIX, client);
        }
        return false;
    }

    US_AddStat(client, "daily_claims", 1);
    US_SetStatMax(client, "daily_best_streak", streak);
    return true;
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

    if (!TryBootstrapDailyStorage(false) || g_DB == null)
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

    int previousLast = 0;
    int previousStreak = 0;
    bool hadPrevious = false;

    if (results.FetchRow())
    {
        hadPrevious = true;
        previousLast = results.FetchInt(0);
        previousStreak = results.FetchInt(1);
    }

    int streak = 0;
    int now = GetTime();
    int cooldown = gCvarCooldownHours.IntValue * 3600;
    int grace = gCvarGraceHours.IntValue * 3600;

    if (previousLast > 0)
    {
        int elapsed = now - previousLast;

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
            streak = previousStreak + 1;
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
    int rewardLevel = (streak > maxDays) ? maxDays : streak;
    int reward = base + ((rewardLevel - 1) * bonus);

    char steamid[32];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        DailyChat(client, "%t", "Daily SteamId Error");
        g_bBusy[client] = false;
        return;
    }

    if (!CompleteDailyClaim(client, steamid, hadPrevious, previousLast, previousStreak, now, streak, reward))
    {
        DailyChat(client, "%t", "Daily Load Error");
        g_bBusy[client] = false;
        return;
    }

    US_AdvanceQuestProgress(client, "daily_claims_3", 1);
    US_SetQuestProgressMax(client, "daily_streak_7", streak);

    DailyChat(client, "%t", "Daily Claimed", reward, streak);
    g_bBusy[client] = false;
}

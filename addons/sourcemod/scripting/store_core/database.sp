// Umbrella Store core: Database connection, schema, player load/save, and locked transactions.
// Included by store_core.sp.

bool EscapeStringSafe(const char[] input, char[] output, int maxlen)
{
    // Always leave the destination in a defined state: Escape() writes nothing
    // when the buffer is too small (it needs 2 * strlen + 1), and callers that
    // ignored the result would otherwise format uninitialised stack memory
    // straight into a query.
    output[0] = '\0';

    if (g_DB == null)
    {
        LogError("%s EscapeStringSafe called before database was ready.", STORE_LOG_PREFIX);
        return false;
    }

    if (!g_DB.Escape(input, output, maxlen))
    {
        output[0] = '\0';
        LogError("%s EscapeStringSafe could not escape a %d character value into a %d byte buffer.", STORE_LOG_PREFIX, strlen(input), maxlen);
        return false;
    }

    return true;
}

bool GetDatabaseConfigName(char[] buffer, int maxlen)
{
    if (gCvarDatabase != null)
    {
        gCvarDatabase.GetString(buffer, maxlen);
        TrimString(buffer);
    }
    else
    {
        strcopy(buffer, maxlen, STORE_DB_CONFIG);
    }

    if (buffer[0] == '\0')
    {
        strcopy(buffer, maxlen, STORE_DB_CONFIG);
    }

    return (buffer[0] != '\0');
}

void SaveDirtyPlayers()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_bCreditsDirty[i] && g_bIsLoaded[i] && IsValidClientConnected(i))
        {
            SavePlayer(i);
        }
    }
}

void ConnectDatabase()
{
    char dbConfig[64];
    if (gCvarDatabase != null)
    {
        gCvarDatabase.GetString(dbConfig, sizeof(dbConfig));
    }
    else
    {
        strcopy(dbConfig, sizeof(dbConfig), STORE_DB_CONFIG);
    }

    if (dbConfig[0] == '\0')
    {
        strcopy(dbConfig, sizeof(dbConfig), STORE_DB_CONFIG);
    }

    if (SQL_CheckConfig(dbConfig))
    {
        Database.Connect(OnDatabaseConnected, dbConfig);
        return;
    }

    char failMsg[256];
    Format(failMsg, sizeof(failMsg), "%s Database config '%s' not found in databases.cfg. Set store_database to a valid entry.", STORE_LOG_PREFIX, dbConfig);
    LogError("%s", failMsg);
    SetFailState("%s", failMsg);
}

public void OnDatabaseConnected(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogStoreError("OnDatabaseConnected", error);
        char failMsg[256];
        char dbConfig[64];
        if (gCvarDatabase != null)
        {
            gCvarDatabase.GetString(dbConfig, sizeof(dbConfig));
        }
        else
        {
            strcopy(dbConfig, sizeof(dbConfig), STORE_DB_CONFIG);
        }
        if (dbConfig[0] == '\0')
        {
            strcopy(dbConfig, sizeof(dbConfig), STORE_DB_CONFIG);
        }

        if (error[0] == '\0')
        {
            Format(failMsg, sizeof(failMsg), "%s Unable to connect database '%s'.", STORE_LOG_PREFIX, dbConfig);
        }
        else
        {
            Format(failMsg, sizeof(failMsg), "%s Database '%s' connection failed: %s", STORE_LOG_PREFIX, dbConfig, error);
        }
        SetFailState("%s", failMsg);
        return;
    }

    g_DB = db;
    SetupDatabaseMode();
    CreateTables();
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

void CreateTables()
{
    if (g_DB == null)
    {
        return;
    }

    char query1[512];
    char query2[512];
    char query3[512];
    char query4[512];
    char query5[512];
    char query6[512];
    char query7[512];
    char query8[512];
    char query9[512];
    char query10[512];
    char query11[512];
    char query12[768];
    char query13[512];
    char query14[512];
    char query15[512];
    char query16[1024];
    char query17[512];
    char query18[768];
    char query19[512];
    char query20[768];
    char query21[512];
    char query22[512];
    char query23[512];
    query3[0] = '\0';
    query5[0] = '\0';
    query7[0] = '\0';
    query9[0] = '\0';
    query11[0] = '\0';
    query13[0] = '\0';
    query15[0] = '\0';
    query17[0] = '\0';
    query19[0] = '\0';
    query21[0] = '\0';
    query22[0] = '\0';
    query23[0] = '\0';

    if (g_bIsMySQL)
    {
        Format(query1, sizeof(query1),
            "CREATE TABLE IF NOT EXISTS store_players (steamid VARCHAR(32) NOT NULL PRIMARY KEY, name VARCHAR(64) NOT NULL, credits INT NOT NULL DEFAULT 0)");
        Format(query2, sizeof(query2),
            "CREATE TABLE IF NOT EXISTS store_inventory (steamid VARCHAR(32) NOT NULL, item_id VARCHAR(32) NOT NULL, is_equipped INT NOT NULL DEFAULT 0, expires_at INT NOT NULL DEFAULT 0, PRIMARY KEY (steamid, item_id))");
        Format(query4, sizeof(query4),
            "CREATE TABLE IF NOT EXISTS store_credits_ledger (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, steamid VARCHAR(32) NOT NULL, amount INT NOT NULL, reason VARCHAR(64) NOT NULL, balance_after INT NOT NULL, created_at INT NOT NULL, INDEX idx_store_credits_ledger_steamid (steamid), INDEX idx_store_credits_ledger_created (created_at))");
        Format(query6, sizeof(query6),
            "CREATE TABLE IF NOT EXISTS store_player_stats (steamid VARCHAR(32) NOT NULL, stat_key VARCHAR(64) NOT NULL, stat_value INT NOT NULL DEFAULT 0, updated_at INT NOT NULL DEFAULT 0, PRIMARY KEY (steamid, stat_key), INDEX idx_store_player_stats_key (stat_key))");
        Format(query8, sizeof(query8),
            "CREATE TABLE IF NOT EXISTS store_player_quests (steamid VARCHAR(32) NOT NULL, quest_id VARCHAR(64) NOT NULL, progress INT NOT NULL DEFAULT 0, completed_at INT NOT NULL DEFAULT 0, rewarded_at INT NOT NULL DEFAULT 0, PRIMARY KEY (steamid, quest_id), INDEX idx_store_player_quests_quest (quest_id))");
        Format(query10, sizeof(query10),
            "CREATE TABLE IF NOT EXISTS store_player_quest_counts (steamid VARCHAR(32) NOT NULL, quest_id VARCHAR(64) NOT NULL, completion_count INT NOT NULL DEFAULT 0, updated_at INT NOT NULL DEFAULT 0, PRIMARY KEY (steamid, quest_id), INDEX idx_store_player_quest_counts_quest (quest_id))");
        Format(query12, sizeof(query12),
            "CREATE TABLE IF NOT EXISTS store_market_listings (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, seller_steamid VARCHAR(32) NOT NULL, item_id VARCHAR(32) NOT NULL, price INT NOT NULL, fee_percent INT NOT NULL DEFAULT 0, created_at INT NOT NULL, expires_at INT NOT NULL, sold_to VARCHAR(32) NOT NULL DEFAULT '', sold_at INT NOT NULL DEFAULT 0, cancelled_at INT NOT NULL DEFAULT 0, INDEX idx_store_market_seller (seller_steamid), INDEX idx_store_market_active (sold_at, cancelled_at, expires_at))");
        Format(query14, sizeof(query14),
            "CREATE TABLE IF NOT EXISTS store_market_sales (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, listing_id INT NOT NULL, seller_steamid VARCHAR(32) NOT NULL, buyer_steamid VARCHAR(32) NOT NULL, item_id VARCHAR(32) NOT NULL, price INT NOT NULL, fee_amount INT NOT NULL DEFAULT 0, created_at INT NOT NULL, INDEX idx_store_market_sales_seller (seller_steamid), INDEX idx_store_market_sales_buyer (buyer_steamid))");
        Format(query16, sizeof(query16),
            "CREATE TABLE IF NOT EXISTS store_audit_log (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, actor_steamid VARCHAR(32) NOT NULL DEFAULT '', actor_name VARCHAR(64) NOT NULL DEFAULT '', target_steamid VARCHAR(32) NOT NULL DEFAULT '', target_name VARCHAR(64) NOT NULL DEFAULT '', action VARCHAR(64) NOT NULL, item_id VARCHAR(32) NOT NULL DEFAULT '', amount INT NOT NULL DEFAULT 0, details VARCHAR(192) NOT NULL DEFAULT '', created_at INT NOT NULL, INDEX idx_store_audit_created (created_at), INDEX idx_store_audit_target (target_steamid), INDEX idx_store_audit_action (action))");
        Format(query18, sizeof(query18),
            "CREATE TABLE IF NOT EXISTS store_vouchers (code VARCHAR(64) NOT NULL PRIMARY KEY, reward_credits INT NOT NULL DEFAULT 0, reward_item VARCHAR(32) NOT NULL DEFAULT '', max_uses INT NOT NULL DEFAULT 1, uses INT NOT NULL DEFAULT 0, expires_at INT NOT NULL DEFAULT 0, created_by_steamid VARCHAR(32) NOT NULL DEFAULT '', created_by_name VARCHAR(64) NOT NULL DEFAULT '', created_at INT NOT NULL, disabled INT NOT NULL DEFAULT 0, INDEX idx_store_vouchers_disabled (disabled), INDEX idx_store_vouchers_expires (expires_at))");
        Format(query20, sizeof(query20),
            "CREATE TABLE IF NOT EXISTS store_voucher_redemptions (code VARCHAR(64) NOT NULL, steamid VARCHAR(32) NOT NULL, player_name VARCHAR(64) NOT NULL DEFAULT '', redeemed_at INT NOT NULL, PRIMARY KEY (code, steamid), INDEX idx_store_voucher_redemptions_steamid (steamid))");
        Format(query23, sizeof(query23),
            "CREATE TABLE IF NOT EXISTS store_market_locks (seller_steamid VARCHAR(32) NOT NULL, item_id VARCHAR(32) NOT NULL, created_at INT NOT NULL, PRIMARY KEY (seller_steamid, item_id))");
    }
    else
    {
        Format(query1, sizeof(query1),
            "CREATE TABLE IF NOT EXISTS store_players (steamid TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, credits INTEGER NOT NULL DEFAULT 0)");
        Format(query2, sizeof(query2),
            "CREATE TABLE IF NOT EXISTS store_inventory (steamid TEXT NOT NULL, item_id TEXT NOT NULL, is_equipped INTEGER NOT NULL DEFAULT 0, expires_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, item_id))");
        Format(query3, sizeof(query3),
            "CREATE INDEX IF NOT EXISTS idx_store_inventory_steamid ON store_inventory (steamid)");
        Format(query4, sizeof(query4),
            "CREATE TABLE IF NOT EXISTS store_credits_ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, steamid TEXT NOT NULL, amount INTEGER NOT NULL, reason TEXT NOT NULL, balance_after INTEGER NOT NULL, created_at INTEGER NOT NULL)");
        Format(query5, sizeof(query5),
            "CREATE INDEX IF NOT EXISTS idx_store_credits_ledger_steamid ON store_credits_ledger (steamid)");
        Format(query6, sizeof(query6),
            "CREATE TABLE IF NOT EXISTS store_player_stats (steamid TEXT NOT NULL, stat_key TEXT NOT NULL, stat_value INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, stat_key))");
        Format(query7, sizeof(query7),
            "CREATE INDEX IF NOT EXISTS idx_store_player_stats_key ON store_player_stats (stat_key)");
        Format(query8, sizeof(query8),
            "CREATE TABLE IF NOT EXISTS store_player_quests (steamid TEXT NOT NULL, quest_id TEXT NOT NULL, progress INTEGER NOT NULL DEFAULT 0, completed_at INTEGER NOT NULL DEFAULT 0, rewarded_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, quest_id))");
        Format(query9, sizeof(query9),
            "CREATE INDEX IF NOT EXISTS idx_store_player_quests_quest ON store_player_quests (quest_id)");
        Format(query10, sizeof(query10),
            "CREATE TABLE IF NOT EXISTS store_player_quest_counts (steamid TEXT NOT NULL, quest_id TEXT NOT NULL, completion_count INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, quest_id))");
        Format(query11, sizeof(query11),
            "CREATE INDEX IF NOT EXISTS idx_store_player_quest_counts_quest ON store_player_quest_counts (quest_id)");
        Format(query12, sizeof(query12),
            "CREATE TABLE IF NOT EXISTS store_market_listings (id INTEGER PRIMARY KEY AUTOINCREMENT, seller_steamid TEXT NOT NULL, item_id TEXT NOT NULL, price INTEGER NOT NULL, fee_percent INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, sold_to TEXT NOT NULL DEFAULT '', sold_at INTEGER NOT NULL DEFAULT 0, cancelled_at INTEGER NOT NULL DEFAULT 0)");
        Format(query13, sizeof(query13),
            "CREATE INDEX IF NOT EXISTS idx_store_market_active ON store_market_listings (sold_at, cancelled_at, expires_at)");
        Format(query14, sizeof(query14),
            "CREATE TABLE IF NOT EXISTS store_market_sales (id INTEGER PRIMARY KEY AUTOINCREMENT, listing_id INTEGER NOT NULL, seller_steamid TEXT NOT NULL, buyer_steamid TEXT NOT NULL, item_id TEXT NOT NULL, price INTEGER NOT NULL, fee_amount INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)");
        Format(query15, sizeof(query15),
            "CREATE INDEX IF NOT EXISTS idx_store_market_sales_seller ON store_market_sales (seller_steamid)");
        Format(query16, sizeof(query16),
            "CREATE TABLE IF NOT EXISTS store_audit_log (id INTEGER PRIMARY KEY AUTOINCREMENT, actor_steamid TEXT NOT NULL DEFAULT '', actor_name TEXT NOT NULL DEFAULT '', target_steamid TEXT NOT NULL DEFAULT '', target_name TEXT NOT NULL DEFAULT '', action TEXT NOT NULL, item_id TEXT NOT NULL DEFAULT '', amount INTEGER NOT NULL DEFAULT 0, details TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL)");
        Format(query17, sizeof(query17),
            "CREATE INDEX IF NOT EXISTS idx_store_audit_created ON store_audit_log (created_at)");
        Format(query18, sizeof(query18),
            "CREATE TABLE IF NOT EXISTS store_vouchers (code TEXT NOT NULL PRIMARY KEY, reward_credits INTEGER NOT NULL DEFAULT 0, reward_item TEXT NOT NULL DEFAULT '', max_uses INTEGER NOT NULL DEFAULT 1, uses INTEGER NOT NULL DEFAULT 0, expires_at INTEGER NOT NULL DEFAULT 0, created_by_steamid TEXT NOT NULL DEFAULT '', created_by_name TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, disabled INTEGER NOT NULL DEFAULT 0)");
        Format(query19, sizeof(query19),
            "CREATE INDEX IF NOT EXISTS idx_store_vouchers_disabled ON store_vouchers (disabled)");
        Format(query20, sizeof(query20),
            "CREATE TABLE IF NOT EXISTS store_voucher_redemptions (code TEXT NOT NULL, steamid TEXT NOT NULL, player_name TEXT NOT NULL DEFAULT '', redeemed_at INTEGER NOT NULL, PRIMARY KEY (code, steamid))");
        Format(query21, sizeof(query21),
            "CREATE INDEX IF NOT EXISTS idx_store_voucher_redemptions_steamid ON store_voucher_redemptions (steamid)");
        Format(query22, sizeof(query22),
            "CREATE INDEX IF NOT EXISTS idx_store_audit_target ON store_audit_log (target_steamid)");
        Format(query23, sizeof(query23),
            "CREATE TABLE IF NOT EXISTS store_market_locks (seller_steamid TEXT NOT NULL, item_id TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (seller_steamid, item_id))");
    }

    g_iPendingTableQueries = 0;
    if (query1[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query2[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query3[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query4[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query5[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query6[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query7[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query8[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query9[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query10[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query11[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query12[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query13[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query14[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query15[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query16[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query17[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query18[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query19[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query20[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query21[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query22[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query23[0] != '\0')
    {
        g_iPendingTableQueries++;
    }

    g_DB.Query(OnTableCreated, query1);
    g_DB.Query(OnTableCreated, query2);
    g_DB.Query(OnTableCreated, query4);
    g_DB.Query(OnTableCreated, query6);
    g_DB.Query(OnTableCreated, query8);
    g_DB.Query(OnTableCreated, query10);
    g_DB.Query(OnTableCreated, query12);
    g_DB.Query(OnTableCreated, query14);
    g_DB.Query(OnTableCreated, query16);
    g_DB.Query(OnTableCreated, query18);
    g_DB.Query(OnTableCreated, query20);

    if (query3[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query3);
    }

    if (query5[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query5);
    }

    if (query7[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query7);
    }

    if (query9[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query9);
    }

    if (query11[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query11);
    }

    if (query13[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query13);
    }

    if (query15[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query15);
    }

    if (query17[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query17);
    }

    if (query19[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query19);
    }

    if (query21[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query21);
    }

    if (query22[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query22);
    }

    if (query23[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query23);
    }

    // Best-effort migration for installs created before rental support existed.
    // On a fresh DB the column already exists (CREATE above) so this no-ops with
    // a harmless "duplicate column" error that OnRentalQueryDone ignores.
    g_DB.Query(OnRentalQueryDone, "ALTER TABLE store_inventory ADD COLUMN expires_at INT NOT NULL DEFAULT 0");
}

// Generic no-op callback for fire-and-forget rental maintenance queries
// (schema migration, expired-row cleanup). Duplicate-column errors are expected.
public void OnRentalQueryDone(Database db, DBResultSet results, const char[] error, any data)
{
    // Intentionally silent: these queries are best-effort and idempotent.
}

public void OnTableCreated(Database db, DBResultSet results, const char[] error, any data)
{
    if (g_iPendingTableQueries > 0)
    {
        g_iPendingTableQueries--;
    }

    if (db == null)
    {
        LogStoreError("OnTableCreated", error);
        g_bTableSetupFailed = true;
    }
    else if (error[0] != '\0')
    {
        LogStoreError("CreateTables", error);
        g_bTableSetupFailed = true;
    }

    if (g_iPendingTableQueries == 0 && g_bTableSetupFailed && !g_bLateDatabaseReady)
    {
        // Loading players against a schema that failed to build would make every
        // later read and write fail one by one and silently, instead of failing
        // once, loudly, where an operator can see it.
        SetFailState("%s Store tables could not be created; see the SourceMod error log.", STORE_LOG_PREFIX);
        return;
    }

    if (!g_bLateDatabaseReady && g_iPendingTableQueries == 0)
    {
        g_bLateDatabaseReady = true;
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidClientConnected(i) && !g_bIsLoaded[i] && !g_bIsLoading[i])
            {
                LoadPlayer(i);
            }
        }
    }
}

public void DummyCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || error[0] == '\0')
    {
        return;
    }

    LogStoreError("DummyCallback", error);
}

void LoadPlayer(int client)
{
    if (!IsValidClientConnected(client) || g_bIsLoading[client])
    {
        return;
    }

    g_bIsLoading[client] = true;
    g_iCredits[client] = 0;
    g_bIsLoaded[client] = false;

    if (g_hInventory[client] != null)
    {
        delete g_hInventory[client];
    }
    g_hInventory[client] = new ArrayList(sizeof(InventoryItem));

    if (g_mInventoryOwned[client] == null)
    {
        g_mInventoryOwned[client] = new StringMap();
    }
    else
    {
        g_mInventoryOwned[client].Clear();
    }

    if (g_DB == null)
    {
        g_bIsLoading[client] = false;
        return;
    }

    char steamid[32], safeSteamId[64];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        g_bIsLoading[client] = false;
        return;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));

    char query[256];
    Format(query, sizeof(query), "SELECT credits FROM store_players WHERE steamid = '%s'", safeSteamId);
    g_DB.Query(OnPlayerLoaded, query, GetClientUserId(client));
}

public void OnPlayerLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (!IsValidClientConnected(client))
    {
        return;
    }

    if (db == null || results == null)
    {
        g_bIsLoading[client] = false;
        LogStoreError("OnPlayerLoaded", error);
        return;
    }

    if (results.FetchRow())
    {
        g_iCredits[client] = results.FetchInt(0);
    }
    else
    {
        CreatePlayerRow(client);
    }

    char steamid[32], safeSteamId[64], queryInv[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        g_bIsLoading[client] = false;
        return;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    Format(queryInv, sizeof(queryInv), "SELECT item_id, is_equipped, expires_at FROM store_inventory WHERE steamid = '%s'", safeSteamId);
    g_DB.Query(OnInventoryLoaded, queryInv, GetClientUserId(client));
}

void CreatePlayerRow(int client)
{
    if (g_DB == null || !IsValidClientConnected(client))
    {
        return;
    }

    char steamid[32], name[64], safeSteamId[64], safeName[128], query[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return;
    }

    GetClientName(client, name, sizeof(name));
    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(name, safeName, sizeof(safeName));

    int initialCredits = (gCvarInitialCredits != null) ? gCvarInitialCredits.IntValue : 0;
    g_iCredits[client] = initialCredits;
    g_bCreditsDirty[client] = false;

    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "INSERT IGNORE INTO store_players (steamid, name, credits) VALUES ('%s', '%s', %d)",
            safeSteamId, safeName, initialCredits);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT OR IGNORE INTO store_players (steamid, name, credits) VALUES ('%s', '%s', %d)",
            safeSteamId, safeName, initialCredits);
    }

    SQL_LockDatabase(g_DB);
    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("CreatePlayerRow", error);
    }
    SQL_UnlockDatabase(g_DB);
}

bool BuildPlayerUpsertQueryForCredits(int client, int creditsValue, char[] query, int maxlen)
{
    if (g_DB == null || !IsValidClientConnected(client))
    {
        return false;
    }

    char steamid[32], name[64], safeSteamId[64], safeName[128];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    GetClientName(client, name, sizeof(name));
    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(name, safeName, sizeof(safeName));

    if (g_bIsMySQL)
    {
        Format(query, maxlen,
            "INSERT INTO store_players (steamid, name, credits) VALUES ('%s', '%s', %d) ON DUPLICATE KEY UPDATE name = VALUES(name), credits = VALUES(credits)",
            safeSteamId, safeName, creditsValue);
    }
    else
    {
        Format(query, maxlen,
            "INSERT OR REPLACE INTO store_players (steamid, name, credits) VALUES ('%s', '%s', %d)",
            safeSteamId, safeName, creditsValue);
    }

    return true;
}

bool BeginLockedStoreTransaction(const char[] where)
{
    if (g_DB == null)
    {
        return false;
    }

    SQL_LockDatabase(g_DB);
    if (SQL_FastQuery(g_DB, "BEGIN"))
    {
        return true;
    }

    char error[256];
    SQL_GetError(g_DB, error, sizeof(error));
    LogStoreError(where, error);
    SQL_UnlockDatabase(g_DB);
    return false;
}

// allowNoChange covers UPDATEs that legitimately rewrite a row with the value
// it already holds: MySQL reports *changed* rows (CLIENT_FOUND_ROWS is off), so
// such a statement reports zero even though the row matched and the transaction
// is perfectly valid.
bool ExecuteLockedStoreQuery(const char[] where, const char[] query, int expectedAffected = -1, bool allowNoChange = false)
{
    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError(where, error);
        LogError("%s %s query failed.", STORE_LOG_PREFIX, where);
        return false;
    }

    if (expectedAffected >= 0)
    {
        int affected = SQL_GetAffectedRows(g_DB);
        if (affected != expectedAffected && !(allowNoChange && affected == 0))
        {
            LogError("%s %s unexpected affected rows (%d != %d).", STORE_LOG_PREFIX, where, affected, expectedAffected);
            return false;
        }
    }

    return true;
}

void RollbackLockedStoreTransaction(const char[] where)
{
    if (g_DB != null && !SQL_FastQuery(g_DB, "ROLLBACK"))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError(where, error);
    }

    if (g_DB != null)
    {
        SQL_UnlockDatabase(g_DB);
    }
}

bool CommitLockedStoreTransaction(const char[] where)
{
    if (!SQL_FastQuery(g_DB, "COMMIT"))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError(where, error);
        RollbackLockedStoreTransaction(where);
        return false;
    }

    SQL_UnlockDatabase(g_DB);
    return true;
}

bool EnsureSharedTableInternal(const char[] tableId, const char[] mysqlQuery, const char[] sqliteQuery)
{
    if (g_DB == null || tableId[0] == '\0')
    {
        return false;
    }

    if (g_mEnsuredTables == null)
    {
        g_mEnsuredTables = new StringMap();
    }

    int cached;
    if (g_mEnsuredTables.GetValue(tableId, cached) && cached == 1)
    {
        return true;
    }

    char query[1024];
    if (g_bIsMySQL)
    {
        strcopy(query, sizeof(query), mysqlQuery);
    }
    else
    {
        strcopy(query, sizeof(query), sqliteQuery);
    }

    if (query[0] == '\0')
    {
        return false;
    }

    SQL_LockDatabase(g_DB);
    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("EnsureSharedTableInternal", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }
    SQL_UnlockDatabase(g_DB);

    g_mEnsuredTables.SetValue(tableId, 1);
    return true;
}

public void OnInventoryLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (!IsValidClientConnected(client))
    {
        return;
    }

    if (db == null || results == null)
    {
        g_bIsLoading[client] = false;
        LogStoreError("OnInventoryLoaded", error);
        return;
    }

    InventoryItem inv;
    int now = GetTime();
    bool hadExpired = false;
    while (results.FetchRow())
    {
        results.FetchString(0, inv.item_id, sizeof(inv.item_id));
        inv.is_equipped = results.FetchInt(1);
        inv.expires_at = results.FetchInt(2);

        if (inv.expires_at > 0 && inv.expires_at <= now)
        {
            // Rental expired while the player was offline: skip loading it and
            // flag a one-shot cleanup of all expired rows for this account.
            hadExpired = true;
            continue;
        }

        g_hInventory[client].PushArray(inv, sizeof(InventoryItem));
        InventoryOwnedSet(client, inv.item_id, true);
    }

    if (hadExpired)
    {
        DeleteExpiredInventoryRows(client, now);
    }

    g_bIsLoaded[client] = true;
    g_bIsLoading[client] = false;
    MarkInventoryChanged(client);
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];
    NormalizeEquippedItemConflicts(client);

    if (ArePlayerSkinsEnabled() && IsValidHumanClient(client) && IsPlayerAlive(client))
    {
        CreateTimer(0.1, Timer_ApplySkin, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }

    ForwardClientLoaded(client);
}

bool SavePlayer(int client)
{
    if (!IsValidClientConnected(client) || g_DB == null)
    {
        return false;
    }

    char query[512];
    int creditsSnapshot = g_iCredits[client];
    if (!BuildPlayerUpsertQueryForCredits(client, creditsSnapshot, query, sizeof(query)))
    {
        return false;
    }

    SQL_LockDatabase(g_DB);
    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("SavePlayerSync", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }
    SQL_UnlockDatabase(g_DB);

    if (g_iCredits[client] == creditsSnapshot)
    {
        g_bCreditsDirty[client] = false;
    }

    return true;
}

void SaveInventoryEquipState(int client, const char[] itemId, int equipped)
{
    if (g_DB == null)
    {
        return;
    }

    char steamid[32], safeSteamId[64], safeItemId[64], query[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));

    Format(query, sizeof(query),
        "UPDATE store_inventory SET is_equipped = %d WHERE steamid = '%s' AND item_id = '%s'",
        equipped, safeSteamId, safeItemId);

    SQL_LockDatabase(g_DB);
    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("SaveInventoryEquipState", error);
    }
    SQL_UnlockDatabase(g_DB);
}

// Umbrella Store core: Quest registry, progress, rewards, and quest menus.
// Included by store_core.sp.

bool RegisterQuestInternal(const char[] questId, const char[] title, int goal, int rewardCredits)
{
    if (questId[0] == '\0' || goal <= 0)
    {
        return false;
    }

    if (g_aQuestDefinitions == null)
    {
        g_aQuestDefinitions = new ArrayList(sizeof(StoreQuestDefinition));
    }

    if (g_mQuestIndex == null)
    {
        g_mQuestIndex = new StringMap();
    }

    StoreQuestDefinition definition;
    strcopy(definition.id, sizeof(definition.id), questId);
    strcopy(definition.title, sizeof(definition.title), title);
    strcopy(definition.category, sizeof(definition.category), "Quest Category General");
    definition.description[0] = '\0';
    definition.reward_item[0] = '\0';
    definition.reward_item_equip = 0;
    definition.goal = goal;
    definition.reward_credits = rewardCredits;

    int index;
    if (g_mQuestIndex.GetValue(questId, index) && index >= 0 && index < g_aQuestDefinitions.Length)
    {
        g_aQuestDefinitions.SetArray(index, definition, sizeof(StoreQuestDefinition));
        return true;
    }

    index = g_aQuestDefinitions.PushArray(definition, sizeof(StoreQuestDefinition));
    if (index < 0)
    {
        return false;
    }

    g_mQuestIndex.SetValue(questId, index);
    return true;
}

bool RegisterQuestDefinitionInternal(StoreQuestDefinition definition)
{
    if (definition.id[0] == '\0' || definition.goal <= 0)
    {
        return false;
    }

    if (definition.category[0] == '\0')
    {
        strcopy(definition.category, sizeof(definition.category), "Quest Category General");
    }

    if (!definition.repeatable)
    {
        definition.max_completions = 1;
    }
    else if (definition.max_completions == 0)
    {
        definition.max_completions = -1;
    }

    if (g_aQuestDefinitions == null)
    {
        g_aQuestDefinitions = new ArrayList(sizeof(StoreQuestDefinition));
    }

    if (g_mQuestIndex == null)
    {
        g_mQuestIndex = new StringMap();
    }

    int index;
    if (g_mQuestIndex.GetValue(definition.id, index) && index >= 0 && index < g_aQuestDefinitions.Length)
    {
        g_aQuestDefinitions.SetArray(index, definition, sizeof(StoreQuestDefinition));
        return true;
    }

    index = g_aQuestDefinitions.PushArray(definition, sizeof(StoreQuestDefinition));
    if (index < 0)
    {
        return false;
    }

    g_mQuestIndex.SetValue(definition.id, index);
    return true;
}

void ClearLoadedQuestConfigEntries()
{
    if (g_aQuestConfigIds == null || g_aQuestConfigBaseDefinitions == null || g_aQuestConfigBaseValid == null)
    {
        return;
    }

    char questId[64];
    StoreQuestDefinition baseDefinition;
    for (int i = g_aQuestConfigIds.Length - 1; i >= 0; i--)
    {
        g_aQuestConfigIds.GetString(i, questId, sizeof(questId));
        bool hadBase = view_as<bool>(g_aQuestConfigBaseValid.Get(i));
        if (hadBase)
        {
            g_aQuestConfigBaseDefinitions.GetArray(i, baseDefinition, sizeof(StoreQuestDefinition));
            RegisterQuestDefinitionInternal(baseDefinition);
        }
        else
        {
            UnregisterQuestInternal(questId);
        }
    }

    g_aQuestConfigIds.Clear();
    g_aQuestConfigBaseDefinitions.Clear();
    g_aQuestConfigBaseValid.Clear();
}

void LoadQuestConfig()
{
    ClearLoadedQuestConfigEntries();

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), STORE_QUESTS_CONFIG);
    if (!FileExists(path))
    {
        return;
    }

    KeyValues kv = new KeyValues("Quests");
    if (!kv.ImportFromFile(path))
    {
        LogError("%s Failed to load quest config: %s", STORE_LOG_PREFIX, path);
        delete kv;
        return;
    }

    if (!kv.GotoFirstSubKey())
    {
        delete kv;
        return;
    }

    do
    {
        StoreQuestDefinition definition;
        kv.GetSectionName(definition.id, sizeof(definition.id));
        kv.GetString("title", definition.title, sizeof(definition.title), definition.id);
        kv.GetString("category", definition.category, sizeof(definition.category), "Quest Category General");
        kv.GetString("description", definition.description, sizeof(definition.description), "");
        kv.GetString("reward_item", definition.reward_item, sizeof(definition.reward_item), "");
        definition.reward_item_equip = kv.GetNum("reward_item_equip", 0);
        definition.repeatable = kv.GetNum("repeatable", 0);
        definition.max_completions = kv.GetNum("max_completions", definition.repeatable ? -1 : 1);
        kv.GetString("requires_quest", definition.requires_quest, sizeof(definition.requires_quest), "");
        definition.starts_at = kv.GetNum("starts_at", 0);
        definition.ends_at = kv.GetNum("ends_at", 0);

        int enabled = kv.GetNum("enabled", 1);
        definition.goal = kv.GetNum("goal", 0);
        definition.reward_credits = kv.GetNum("reward_credits", 0);

        if (!enabled)
        {
            continue;
        }

        if (definition.id[0] == '\0' || definition.goal <= 0)
        {
            LogError("%s Invalid quest in %s. id='%s' goal=%d", STORE_LOG_PREFIX, path, definition.id, definition.goal);
            continue;
        }

        StoreQuestDefinition previousDefinition;
        previousDefinition.id[0] = '\0';
        previousDefinition.title[0] = '\0';
        previousDefinition.category[0] = '\0';
        previousDefinition.description[0] = '\0';
        previousDefinition.reward_item[0] = '\0';
        previousDefinition.reward_item_equip = 0;
        previousDefinition.goal = 0;
        previousDefinition.reward_credits = 0;
        previousDefinition.repeatable = 0;
        previousDefinition.max_completions = 1;
        previousDefinition.requires_quest[0] = '\0';
        previousDefinition.starts_at = 0;
        previousDefinition.ends_at = 0;
        bool hadPrevious = FindQuestDefinition(definition.id, previousDefinition);

        if (!RegisterQuestDefinitionInternal(definition))
        {
            LogError("%s Failed to register quest '%s' from %s", STORE_LOG_PREFIX, definition.id, path);
            continue;
        }

        g_aQuestConfigIds.PushString(definition.id);
        g_aQuestConfigBaseValid.Push(hadPrevious ? 1 : 0);
        g_aQuestConfigBaseDefinitions.PushArray(previousDefinition, sizeof(StoreQuestDefinition));
    }
    while (kv.GotoNextKey());

    delete kv;
}

bool UnregisterQuestInternal(const char[] questId)
{
    if (questId[0] == '\0' || g_aQuestDefinitions == null || g_mQuestIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mQuestIndex.GetValue(questId, index) || index < 0 || index >= g_aQuestDefinitions.Length)
    {
        return false;
    }

    g_aQuestDefinitions.Erase(index);
    g_mQuestIndex.Remove(questId);

    StoreQuestDefinition definition;
    for (int i = index; i < g_aQuestDefinitions.Length; i++)
    {
        g_aQuestDefinitions.GetArray(i, definition, sizeof(StoreQuestDefinition));
        g_mQuestIndex.SetValue(definition.id, i);
    }

    return true;
}

bool FindQuestDefinition(const char[] questId, StoreQuestDefinition definition)
{
    if (questId[0] == '\0' || g_aQuestDefinitions == null || g_mQuestIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mQuestIndex.GetValue(questId, index) || index < 0 || index >= g_aQuestDefinitions.Length)
    {
        return false;
    }

    g_aQuestDefinitions.GetArray(index, definition, sizeof(StoreQuestDefinition));
    return true;
}

bool LoadQuestProgressSnapshot(int client, ArrayList rows, StringMap indexMap, int &completedCount)
{
    completedCount = 0;

    if (rows == null || indexMap == null || g_DB == null || !IsValidClientConnected(client))
    {
        return false;
    }

    char steamid[32], safeSteamId[64], query[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    Format(query, sizeof(query),
        "SELECT q.quest_id, q.progress, q.completed_at, q.rewarded_at, COALESCE(c.completion_count, 0) "
        ... "FROM store_player_quests q "
        ... "LEFT JOIN store_player_quest_counts c ON q.steamid = c.steamid AND q.quest_id = c.quest_id "
        ... "WHERE q.steamid = '%s'",
        safeSteamId);

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("LoadQuestProgressSnapshot", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }

    StoreQuestProgressSnapshot state;
    while (results.FetchRow())
    {
        results.FetchString(0, state.quest_id, sizeof(state.quest_id));
        state.progress = results.FetchInt(1);
        state.completed_at = results.FetchInt(2);
        state.rewarded_at = results.FetchInt(3);
        state.completion_count = results.FetchInt(4);

        int rowIndex = rows.PushArray(state, sizeof(StoreQuestProgressSnapshot));
        if (rowIndex >= 0)
        {
            indexMap.SetValue(state.quest_id, rowIndex);
        }

        if (state.completion_count > 0)
        {
            completedCount += state.completion_count;
        }
        else if (state.rewarded_at > 0)
        {
            completedCount++;
        }
    }

    delete results;
    SQL_UnlockDatabase(g_DB);
    return true;
}

void GetQuestSnapshotState(ArrayList rows, StringMap indexMap, const char[] questId, int &progress, int &completedAt, int &rewardedAt, int &completionCount)
{
    progress = 0;
    completedAt = 0;
    rewardedAt = 0;
    completionCount = 0;

    if (rows == null || indexMap == null || questId[0] == '\0')
    {
        return;
    }

    int rowIndex = -1;
    if (!indexMap.GetValue(questId, rowIndex) || rowIndex < 0 || rowIndex >= rows.Length)
    {
        return;
    }

    StoreQuestProgressSnapshot state;
    rows.GetArray(rowIndex, state, sizeof(StoreQuestProgressSnapshot));
    progress = state.progress;
    completedAt = state.completed_at;
    rewardedAt = state.rewarded_at;
    completionCount = state.completion_count;
}

bool HasQuestRewardedInSnapshot(ArrayList rows, StringMap indexMap, const char[] questId)
{
    int progress = 0;
    int completedAt = 0;
    int rewardedAt = 0;
    int completionCount = 0;
    GetQuestSnapshotState(rows, indexMap, questId, progress, completedAt, rewardedAt, completionCount);
    return (rewardedAt > 0 || completionCount > 0);
}

void FormatQuestTitle(int client, const StoreQuestDefinition definition, char[] buffer, int maxlen)
{
    if (definition.title[0] == '\0')
    {
        buffer[0] = '\0';
        return;
    }

    if (TranslationPhraseExists(definition.title))
    {
        Format(buffer, maxlen, "%T", definition.title, client);
        return;
    }

    strcopy(buffer, maxlen, definition.title);
}

void FormatQuestText(int client, const char[] value, char[] buffer, int maxlen)
{
    if (value[0] == '\0')
    {
        buffer[0] = '\0';
        return;
    }

    if (TranslationPhraseExists(value))
    {
        Format(buffer, maxlen, "%T", value, client);
        return;
    }

    strcopy(buffer, maxlen, value);
}

void FormatQuestRewardText(int client, const StoreQuestDefinition definition, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    char creditsText[64];
    char itemText[96];
    creditsText[0] = '\0';
    itemText[0] = '\0';

    if (definition.reward_credits > 0)
    {
        FormatCreditsAmount(client, definition.reward_credits, creditsText, sizeof(creditsText));
    }

    if (definition.reward_item[0] != '\0')
    {
        StoreItem rewardItem;
        if (FindStoreItemById(definition.reward_item, rewardItem))
        {
            strcopy(itemText, sizeof(itemText), rewardItem.name);
        }
        else
        {
            strcopy(itemText, sizeof(itemText), definition.reward_item);
        }
    }

    if (creditsText[0] != '\0' && itemText[0] != '\0')
    {
        Format(buffer, maxlen, "%s + %s", creditsText, itemText);
    }
    else if (creditsText[0] != '\0')
    {
        strcopy(buffer, maxlen, creditsText);
    }
    else if (itemText[0] != '\0')
    {
        strcopy(buffer, maxlen, itemText);
    }
}

bool GetQuestProgressState(int client, const char[] questId, int &progress, int &completedAt, int &rewardedAt)
{
    progress = 0;
    completedAt = 0;
    rewardedAt = 0;

    if (g_DB == null || !IsValidClientConnected(client) || questId[0] == '\0')
    {
        return false;
    }

    char steamid[32], safeSteamId[64], safeQuestId[128], query[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(questId, safeQuestId, sizeof(safeQuestId));
    Format(query, sizeof(query),
        "SELECT progress, completed_at, rewarded_at FROM store_player_quests WHERE steamid = '%s' AND quest_id = '%s'",
        safeSteamId, safeQuestId);

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("GetQuestProgressState", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }

    if (results.FetchRow())
    {
        progress = results.FetchInt(0);
        completedAt = results.FetchInt(1);
        rewardedAt = results.FetchInt(2);
    }

    delete results;
    SQL_UnlockDatabase(g_DB);
    return true;
}

bool GetQuestCompletionCount(int client, const char[] questId, int &count)
{
    count = 0;

    if (g_DB == null || !IsValidClientConnected(client) || questId[0] == '\0')
    {
        return false;
    }

    char steamid[32], safeSteamId[64], safeQuestId[128], query[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(questId, safeQuestId, sizeof(safeQuestId));
    Format(query, sizeof(query),
        "SELECT completion_count FROM store_player_quest_counts WHERE steamid = '%s' AND quest_id = '%s'",
        safeSteamId, safeQuestId);

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("GetQuestCompletionCount", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }

    if (results.FetchRow())
    {
        count = results.FetchInt(0);
    }

    delete results;
    SQL_UnlockDatabase(g_DB);
    return true;
}

bool BuildQuestCompletionCountQuery(int client, const char[] questId, int count, char[] query, int maxlen)
{
    if (g_DB == null || !IsValidClientConnected(client) || questId[0] == '\0')
    {
        return false;
    }

    char steamid[32], safeSteamId[64], safeQuestId[128];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    if (!EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId)) || !EscapeStringSafe(questId, safeQuestId, sizeof(safeQuestId)))
    {
        return false;
    }

    if (g_bIsMySQL)
    {
        Format(query, maxlen,
            "INSERT INTO store_player_quest_counts (steamid, quest_id, completion_count, updated_at) VALUES ('%s', '%s', %d, %d) "
            ... "ON DUPLICATE KEY UPDATE completion_count = VALUES(completion_count), updated_at = VALUES(updated_at)",
            safeSteamId, safeQuestId, count, GetTime());
    }
    else
    {
        Format(query, maxlen,
            "INSERT INTO store_player_quest_counts (steamid, quest_id, completion_count, updated_at) VALUES ('%s', '%s', %d, %d) "
            ... "ON CONFLICT(steamid, quest_id) DO UPDATE SET completion_count = excluded.completion_count, updated_at = excluded.updated_at",
            safeSteamId, safeQuestId, count, GetTime());
    }

    return true;
}

bool IsQuestWithinWindow(const StoreQuestDefinition definition, int now)
{
    if (definition.starts_at > 0 && now < definition.starts_at)
    {
        return false;
    }

    if (definition.ends_at > 0 && now > definition.ends_at)
    {
        return false;
    }

    return true;
}

bool HasQuestRewardedAtLeastOnce(int client, const char[] questId)
{
    int progress = 0;
    int completedAt = 0;
    int rewardedAt = 0;
    if (!GetQuestProgressState(client, questId, progress, completedAt, rewardedAt))
    {
        return false;
    }

    if (rewardedAt > 0)
    {
        return true;
    }

    int completionCount = 0;
    GetQuestCompletionCount(client, questId, completionCount);
    return (completionCount > 0);
}

void GetQuestAvailabilityState(int client, const StoreQuestDefinition definition, int rewardedAt, int completionCount, bool &lockedByWindow, bool &lockedByRequirement, bool &maxedOut)
{
    lockedByWindow = false;
    lockedByRequirement = false;
    maxedOut = false;

    int now = GetTime();
    if (!IsQuestWithinWindow(definition, now))
    {
        lockedByWindow = true;
    }

    if (definition.requires_quest[0] != '\0' && !HasQuestRewardedAtLeastOnce(client, definition.requires_quest))
    {
        lockedByRequirement = true;
    }

    if (definition.repeatable)
    {
        if (definition.max_completions > 0 && completionCount >= definition.max_completions)
        {
            maxedOut = true;
        }
    }
    else if (rewardedAt > 0 || completionCount > 0)
    {
        maxedOut = true;
    }
}

void GetQuestAvailabilityStateFromSnapshot(const StoreQuestDefinition definition, int rewardedAt, int completionCount, ArrayList questRows, StringMap questIndex, bool &lockedByWindow, bool &lockedByRequirement, bool &maxedOut)
{
    lockedByWindow = false;
    lockedByRequirement = false;
    maxedOut = false;

    int now = GetTime();
    if (!IsQuestWithinWindow(definition, now))
    {
        lockedByWindow = true;
    }

    if (definition.requires_quest[0] != '\0' && !HasQuestRewardedInSnapshot(questRows, questIndex, definition.requires_quest))
    {
        lockedByRequirement = true;
    }

    if (definition.repeatable)
    {
        if (definition.max_completions > 0 && completionCount >= definition.max_completions)
        {
            maxedOut = true;
        }
    }
    else if (rewardedAt > 0 || completionCount > 0)
    {
        maxedOut = true;
    }
}

bool BuildQuestProgressStateQuery(int client, const char[] questId, int progress, int completedAt, int rewardedAt, char[] query, int maxlen)
{
    if (g_DB == null || !IsValidClientConnected(client) || questId[0] == '\0')
    {
        return false;
    }

    char steamid[32], safeSteamId[64], safeQuestId[128];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    if (!EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId)) || !EscapeStringSafe(questId, safeQuestId, sizeof(safeQuestId)))
    {
        return false;
    }

    if (g_bIsMySQL)
    {
        Format(query, maxlen,
            "INSERT INTO store_player_quests (steamid, quest_id, progress, completed_at, rewarded_at) VALUES ('%s', '%s', %d, %d, %d) "
            ... "ON DUPLICATE KEY UPDATE progress = VALUES(progress), completed_at = VALUES(completed_at), rewarded_at = VALUES(rewarded_at)",
            safeSteamId, safeQuestId, progress, completedAt, rewardedAt);
    }
    else
    {
        Format(query, maxlen,
            "INSERT INTO store_player_quests (steamid, quest_id, progress, completed_at, rewarded_at) VALUES ('%s', '%s', %d, %d, %d) "
            ... "ON CONFLICT(steamid, quest_id) DO UPDATE SET progress = excluded.progress, completed_at = excluded.completed_at, rewarded_at = excluded.rewarded_at",
            safeSteamId, safeQuestId, progress, completedAt, rewardedAt);
    }

    return true;
}

bool UpdateQuestProgressInternal(int client, const char[] questId, int value, bool setMax = false)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || value <= 0)
    {
        return false;
    }

    StoreQuestDefinition definition;
    if (!FindQuestDefinition(questId, definition))
    {
        return false;
    }

    int currentProgress = 0;
    int completedAt = 0;
    int rewardedAt = 0;
    int completionCount = 0;
    if (!GetQuestProgressState(client, questId, currentProgress, completedAt, rewardedAt))
    {
        return false;
    }
    if (!GetQuestCompletionCount(client, questId, completionCount))
    {
        completionCount = 0;
    }

    bool lockedByWindow = false;
    bool lockedByRequirement = false;
    bool maxedOut = false;
    GetQuestAvailabilityState(client, definition, rewardedAt, completionCount, lockedByWindow, lockedByRequirement, maxedOut);
    if (lockedByWindow || lockedByRequirement || maxedOut)
    {
        return false;
    }

    int newProgress = setMax ? ((value > currentProgress) ? value : currentProgress) : (currentProgress + value);
    int now = GetTime();
    bool shouldComplete = (newProgress >= definition.goal);

    if (shouldComplete && completedAt <= 0)
    {
        completedAt = now;
    }

    bool shouldReward = (shouldComplete && rewardedAt <= 0);

    // A player sitting at the credit ceiling must not lose the progress tick.
    // Resolve the reward balance up front and, if it cannot be applied, defer
    // the completion (progress is still persisted and the reward is retried on
    // the next progress event) instead of discarding the whole update.
    int rewardNewCredits = 0;
    if (shouldReward && definition.reward_credits > 0
        && !TryComputeCreditBalance(g_iCredits[client], definition.reward_credits, rewardNewCredits))
    {
        LogMessage("%s Quest '%s' reward for client %N deferred: credit balance would exceed the store maximum.", STORE_LOG_PREFIX, questId, client);
        shouldReward = false;
    }

    if (shouldReward)
    {
        rewardedAt = now;
    }

    if (shouldReward)
    {
        completionCount++;
    }

    int persistedProgress = newProgress;
    int persistedCompletedAt = completedAt;
    int persistedRewardedAt = rewardedAt;

    if (shouldReward && definition.repeatable)
    {
        bool reachedCap = (definition.max_completions > 0 && completionCount >= definition.max_completions);
        if (!reachedCap)
        {
            persistedProgress = 0;
            persistedCompletedAt = 0;
            persistedRewardedAt = 0;
        }
        else
        {
            persistedProgress = definition.goal;
            persistedCompletedAt = now;
            persistedRewardedAt = now;
        }
    }

    char questCountQuery[512];
    questCountQuery[0] = '\0';
    char questProgressQuery[512];
    if (shouldReward && !BuildQuestCompletionCountQuery(client, questId, completionCount, questCountQuery, sizeof(questCountQuery)))
    {
        return false;
    }

    if (!BuildQuestProgressStateQuery(client, questId, persistedProgress, persistedCompletedAt, persistedRewardedAt, questProgressQuery, sizeof(questProgressQuery)))
    {
        return false;
    }

    // The completion count, the progress state and any credit reward must land
    // as one transaction. Committing the count without the progress state (the
    // old non-transactional path for item-only quests) permanently marks a
    // non-repeatable quest as maxed out while never delivering its reward.
    char playerQuery[512];
    playerQuery[0] = '\0';
    if (shouldReward && definition.reward_credits > 0
        && !BuildPlayerUpsertQueryForCredits(client, rewardNewCredits, playerQuery, sizeof(playerQuery)))
    {
        return false;
    }

    if (!BeginLockedStoreTransaction("AdvanceQuestProgress"))
    {
        return false;
    }

    if (questCountQuery[0] != '\0' && !ExecuteLockedStoreQuery("AdvanceQuestProgress", questCountQuery))
    {
        RollbackLockedStoreTransaction("AdvanceQuestProgress");
        return false;
    }

    if (!ExecuteLockedStoreQuery("AdvanceQuestProgress", questProgressQuery))
    {
        RollbackLockedStoreTransaction("AdvanceQuestProgress");
        return false;
    }

    if (playerQuery[0] != '\0' && !ExecuteLockedStoreQuery("AdvanceQuestProgress", playerQuery))
    {
        RollbackLockedStoreTransaction("AdvanceQuestProgress");
        return false;
    }

    if (!CommitLockedStoreTransaction("AdvanceQuestProgress"))
    {
        return false;
    }

    if (shouldReward)
    {
        if (definition.reward_credits > 0)
        {
            char reason[96];
            Format(reason, sizeof(reason), "quest:%s", questId);
            g_iCredits[client] += definition.reward_credits;
            ReportCreditsChanged(client, definition.reward_credits, reason, false, true);
        }

        if (definition.reward_item[0] != '\0')
        {
            if (!GiveItemToClient(client, definition.reward_item, view_as<bool>(definition.reward_item_equip), true))
            {
                LogError("%s Quest '%s' could not reward item '%s' to client %N.", STORE_LOG_PREFIX, questId, definition.reward_item, client);
            }
        }

        char rewardText[128];
        FormatQuestRewardText(client, definition, rewardText, sizeof(rewardText));
        if (rewardText[0] != '\0')
        {
            PrintStorePhrase(client, "%T", "Quest Rewarded", client, rewardText);
        }

        ForwardQuestCompleted(client, questId, definition.reward_credits);
    }

    return true;
}

public Action Cmd_Quests(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    ShowQuestMenu(client);
    return Plugin_Handled;
}

void ShowQuestMenu(int client)
{
    Menu menu = new Menu(MenuHandler_QuestCategories);
    char title[192];
    int questCount = (g_aQuestDefinitions != null) ? g_aQuestDefinitions.Length : 0;

    Format(title, sizeof(title), "%T", "Quests Menu Title", client, questCount);
    menu.SetTitle(title);

    if (questCount <= 0)
    {
        AddMenuItemPhrase(menu, "empty", client, "Quests Empty", ITEMDRAW_DISABLED);
    }
    else
    {
        StoreQuestDefinition definition;
        StringMap seen = new StringMap();
        char category[64];
        char info[72];
        for (int i = 0; i < g_aQuestDefinitions.Length; i++)
        {
            g_aQuestDefinitions.GetArray(i, definition, sizeof(StoreQuestDefinition));
            FormatQuestText(client, definition.category, category, sizeof(category));

            // Deduplicate on the raw category, which is what ShowQuestListMenu
            // filters by. Keying on the translated label instead made two raw
            // categories that share a translation collapse into one entry, and
            // the quests behind the second one became unreachable.
            int existing = 0;
            if (seen.GetValue(definition.category, existing))
            {
                continue;
            }

            seen.SetValue(definition.category, 1);
            strcopy(info, sizeof(info), definition.category);
            menu.AddItem(info, category);
        }

        delete seen;

        AddMenuItemPhrase(menu, "all", client, "Quests Category All");
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_QuestCategories(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowStoreMainMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[72];
        menu.GetItem(param2, info, sizeof(info));
        ShowQuestListMenu(param1, info);
    }

    return 0;
}

void ShowQuestListMenu(int client, const char[] categoryFilter)
{
    Menu menu = new Menu(MenuHandler_QuestList);
    char title[192];
    char categoryLabel[64];
    ArrayList questRows = new ArrayList(sizeof(StoreQuestProgressSnapshot));
    StringMap questIndex = new StringMap();
    int ignoredCompletedCount = 0;
    LoadQuestProgressSnapshot(client, questRows, questIndex, ignoredCompletedCount);

    if (StrEqual(categoryFilter, "all"))
    {
        Format(categoryLabel, sizeof(categoryLabel), "%T", "Quests Category All", client);
    }
    else
    {
        FormatQuestText(client, categoryFilter, categoryLabel, sizeof(categoryLabel));
    }

    Format(title, sizeof(title), "%T", "Quests Category Menu Title", client, categoryLabel);
    menu.SetTitle(title);

    bool added = false;
    StoreQuestDefinition definition;
    char questTitle[128];
    char rewardText[128];
    char display[256];
    char info[72];

    for (int i = 0; i < g_aQuestDefinitions.Length; i++)
    {
        g_aQuestDefinitions.GetArray(i, definition, sizeof(StoreQuestDefinition));
        if (!StrEqual(categoryFilter, "all") && !StrEqual(definition.category, categoryFilter))
        {
            continue;
        }

        int progress = 0;
        int completedAt = 0;
        int rewardedAt = 0;
        int completionCount = 0;
        GetQuestSnapshotState(questRows, questIndex, definition.id, progress, completedAt, rewardedAt, completionCount);

        if (progress > definition.goal)
        {
            progress = definition.goal;
        }

        FormatQuestTitle(client, definition, questTitle, sizeof(questTitle));
        FormatQuestRewardText(client, definition, rewardText, sizeof(rewardText));

        bool lockedByWindow = false;
        bool lockedByRequirement = false;
        bool maxedOut = false;
        GetQuestAvailabilityStateFromSnapshot(definition, rewardedAt, completionCount, questRows, questIndex, lockedByWindow, lockedByRequirement, maxedOut);

        if (rewardedAt > 0)
        {
            Format(display, sizeof(display), "%T", "Quest Entry Completed", client, questTitle, definition.goal, definition.goal, rewardText);
        }
        else if (lockedByWindow || lockedByRequirement || maxedOut)
        {
            Format(display, sizeof(display), "%T", "Quest Entry Locked", client, questTitle, progress, definition.goal, rewardText);
        }
        else
        {
            Format(display, sizeof(display), "%T", "Quest Entry In Progress", client, questTitle, progress, definition.goal, rewardText);
        }

        Format(info, sizeof(info), "quest:%s", definition.id);
        menu.AddItem(info, display);
        added = true;
    }

    if (!added)
    {
        AddMenuItemPhrase(menu, "empty", client, "Quests Empty", ITEMDRAW_DISABLED);
    }

    delete questRows;
    delete questIndex;
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_QuestList(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowQuestMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[72];
        menu.GetItem(param2, info, sizeof(info));
        if (StrContains(info, "quest:") == 0)
        {
            char questId[64];
            strcopy(questId, sizeof(questId), info[6]);
            ShowQuestDetailsMenu(param1, questId);
        }
    }

    return 0;
}

void ShowQuestDetailsMenu(int client, const char[] questId)
{
    StoreQuestDefinition definition;
    if (!FindQuestDefinition(questId, definition))
    {
        ShowQuestMenu(client);
        return;
    }

    Menu menu = new Menu(MenuHandler_QuestDetails);
    char title[192];
    char questTitle[128];
    char description[192];
    char rewardText[128];
    char display[256];

    FormatQuestTitle(client, definition, questTitle, sizeof(questTitle));
    Format(title, sizeof(title), "%T", "Quest Details Menu Title", client, questTitle);
    menu.SetTitle(title);

    ArrayList questRows = new ArrayList(sizeof(StoreQuestProgressSnapshot));
    StringMap questIndex = new StringMap();
    int ignoredCompletedCount = 0;
    LoadQuestProgressSnapshot(client, questRows, questIndex, ignoredCompletedCount);

    int progress = 0;
    int completedAt = 0;
    int rewardedAt = 0;
    int completionCount = 0;
    GetQuestSnapshotState(questRows, questIndex, definition.id, progress, completedAt, rewardedAt, completionCount);
    if (progress > definition.goal)
    {
        progress = definition.goal;
    }

    Format(display, sizeof(display), "%T", "Quest Details Progress", client, progress, definition.goal);
    AddMenuItemText(menu, "progress", display, ITEMDRAW_DISABLED);

    FormatQuestRewardText(client, definition, rewardText, sizeof(rewardText));
    Format(display, sizeof(display), "%T", "Quest Details Reward", client, rewardText);
    AddMenuItemText(menu, "reward", display, ITEMDRAW_DISABLED);

    if (definition.repeatable)
    {
        int maxCompletions = definition.max_completions;
        if (maxCompletions <= 0)
        {
            Format(display, sizeof(display), "%T", "Quest Details Repeatable Unlimited", client, completionCount);
        }
        else
        {
            Format(display, sizeof(display), "%T", "Quest Details Repeatable Limited", client, completionCount, maxCompletions);
        }
        AddMenuItemText(menu, "repeatable", display, ITEMDRAW_DISABLED);
    }

    FormatQuestText(client, definition.category, description, sizeof(description));
    Format(display, sizeof(display), "%T", "Quest Details Category", client, description);
    AddMenuItemText(menu, "category", display, ITEMDRAW_DISABLED);

    FormatQuestText(client, definition.description, description, sizeof(description));
    if (description[0] != '\0')
    {
        Format(display, sizeof(display), "%T", "Quest Details Description", client, description);
        AddMenuItemText(menu, "description", display, ITEMDRAW_DISABLED);
    }

    if (definition.requires_quest[0] != '\0')
    {
        char requiresText[128];
        StoreQuestDefinition requiredDefinition;
        if (FindQuestDefinition(definition.requires_quest, requiredDefinition))
        {
            FormatQuestTitle(client, requiredDefinition, requiresText, sizeof(requiresText));
        }
        else
        {
            FormatQuestText(client, definition.requires_quest, requiresText, sizeof(requiresText));
        }
        Format(display, sizeof(display), "%T", "Quest Details Requires", client, requiresText);
        AddMenuItemText(menu, "requires", display, ITEMDRAW_DISABLED);
    }

    if (definition.starts_at > 0 || definition.ends_at > 0)
    {
        char startText[64];
        char endText[64];
        if (definition.starts_at > 0)
        {
            FormatTime(startText, sizeof(startText), "%Y-%m-%d %H:%M", definition.starts_at);
        }
        else
        {
            strcopy(startText, sizeof(startText), "-");
        }

        if (definition.ends_at > 0)
        {
            FormatTime(endText, sizeof(endText), "%Y-%m-%d %H:%M", definition.ends_at);
        }
        else
        {
            strcopy(endText, sizeof(endText), "-");
        }

        Format(display, sizeof(display), "%T", "Quest Details Window", client, startText, endText);
        AddMenuItemText(menu, "window", display, ITEMDRAW_DISABLED);
    }

    bool lockedByWindow = false;
    bool lockedByRequirement = false;
    bool maxedOut = false;
    GetQuestAvailabilityStateFromSnapshot(definition, rewardedAt, completionCount, questRows, questIndex, lockedByWindow, lockedByRequirement, maxedOut);

    if (rewardedAt > 0 && !definition.repeatable)
    {
        AddMenuItemPhrase(menu, "state", client, "Quest Details State Completed", ITEMDRAW_DISABLED);
    }
    else if (maxedOut)
    {
        AddMenuItemPhrase(menu, "state", client, "Quest Details State Maxed", ITEMDRAW_DISABLED);
    }
    else if (lockedByRequirement)
    {
        AddMenuItemPhrase(menu, "state", client, "Quest Details State Locked", ITEMDRAW_DISABLED);
    }
    else if (lockedByWindow)
    {
        AddMenuItemPhrase(menu, "state", client, "Quest Details State Scheduled", ITEMDRAW_DISABLED);
    }
    else if (completedAt > 0)
    {
        AddMenuItemPhrase(menu, "state", client, "Quest Details State Ready", ITEMDRAW_DISABLED);
    }
    else
    {
        AddMenuItemPhrase(menu, "state", client, "Quest Details StateActive", ITEMDRAW_DISABLED);
    }

    delete questRows;
    delete questIndex;
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_QuestDetails(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowQuestMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

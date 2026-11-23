// Umbrella Store core: Leaderboard registry and leaderboard menus.
// Included by store_core.sp.

void RebuildLeaderboardIndex()
{
    if (g_mLeaderboardIndex == null)
    {
        g_mLeaderboardIndex = new StringMap();
    }
    else
    {
        g_mLeaderboardIndex.Clear();
    }

    if (g_aLeaderboards == null)
    {
        return;
    }

    StoreLeaderboardDefinition definition;
    for (int i = 0; i < g_aLeaderboards.Length; i++)
    {
        g_aLeaderboards.GetArray(i, definition, sizeof(StoreLeaderboardDefinition));
        g_mLeaderboardIndex.SetValue(definition.id, i);
    }
}

bool RegisterLeaderboardInternal(const char[] id, const char[] title, const char[] statKey, const char[] entryPhrase = "Top Profit Entry", int sortOrder = 0)
{
    if (id[0] == '\0' || title[0] == '\0' || statKey[0] == '\0' || !IsSafeStatKey(statKey))
    {
        return false;
    }

    if (g_aLeaderboards == null)
    {
        g_aLeaderboards = new ArrayList(sizeof(StoreLeaderboardDefinition));
    }

    if (g_mLeaderboardIndex == null)
    {
        g_mLeaderboardIndex = new StringMap();
    }

    StoreLeaderboardDefinition definition;
    strcopy(definition.id, sizeof(definition.id), id);
    strcopy(definition.title, sizeof(definition.title), title);
    strcopy(definition.stat_key, sizeof(definition.stat_key), statKey);
    if (entryPhrase[0] != '\0' && TranslationPhraseExists(entryPhrase))
    {
        strcopy(definition.entry_phrase, sizeof(definition.entry_phrase), entryPhrase);
    }
    else
    {
        strcopy(definition.entry_phrase, sizeof(definition.entry_phrase), "Top Profit Entry");
    }
    definition.sort_order = sortOrder;

    int index;
    if (g_mLeaderboardIndex.GetValue(id, index) && index >= 0 && index < g_aLeaderboards.Length)
    {
        g_aLeaderboards.SetArray(index, definition, sizeof(StoreLeaderboardDefinition));
        return true;
    }

    index = g_aLeaderboards.PushArray(definition, sizeof(StoreLeaderboardDefinition));
    if (index < 0)
    {
        return false;
    }

    g_mLeaderboardIndex.SetValue(id, index);
    if (g_mAllowedStats != null)
    {
        g_mAllowedStats.SetValue(statKey, 1);
    }
    return true;
}

bool UnregisterLeaderboardInternal(const char[] id)
{
    if (id[0] == '\0' || g_aLeaderboards == null || g_mLeaderboardIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mLeaderboardIndex.GetValue(id, index) || index < 0 || index >= g_aLeaderboards.Length)
    {
        return false;
    }

    g_aLeaderboards.Erase(index);
    RebuildLeaderboardIndex();
    return true;
}

public Action Cmd_Leaderboards(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    ShowLeaderboardsMenu(client);
    return Plugin_Handled;
}

void ShowLeaderboardsMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Leaderboards);
    SetMenuTitlePhrase(menu, client, "Leaderboards Menu Title");

    AddMenuItemPhrase(menu, "credits", client, "Leaderboards Credits");
    AddMenuItemPhrase(menu, "profit", client, "Leaderboards Profit");
    AddMenuItemPhrase(menu, "daily", client, "Leaderboards Daily");
    AddMenuItemPhrase(menu, "blackjack", client, "Leaderboards Blackjack");
    AddMenuItemPhrase(menu, "coinflip", client, "Leaderboards Coinflip");
    AddMenuItemPhrase(menu, "crash", client, "Leaderboards Crash");
    AddMenuItemPhrase(menu, "roulette", client, "Leaderboards Roulette");
    AddRegisteredLeaderboards(menu, client);

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

void AddRegisteredLeaderboards(Menu menu, int client)
{
    if (g_aLeaderboards == null || g_aLeaderboards.Length <= 0)
    {
        return;
    }

    ArrayList ordered = new ArrayList();
    for (int i = 0; i < g_aLeaderboards.Length; i++)
    {
        ordered.Push(i);
    }

    StoreLeaderboardDefinition current;
    StoreLeaderboardDefinition compare;
    for (int i = 1; i < ordered.Length; i++)
    {
        int currentIndex = ordered.Get(i);
        g_aLeaderboards.GetArray(currentIndex, current, sizeof(StoreLeaderboardDefinition));

        int insertAt = i - 1;
        while (insertAt >= 0)
        {
            int compareIndex = ordered.Get(insertAt);
            g_aLeaderboards.GetArray(compareIndex, compare, sizeof(StoreLeaderboardDefinition));
            if (compare.sort_order <= current.sort_order)
            {
                break;
            }
            ordered.Set(insertAt + 1, compareIndex);
            insertAt--;
        }

        ordered.Set(insertAt + 1, currentIndex);
    }

    char title[128];
    for (int i = 0; i < ordered.Length; i++)
    {
        int index = ordered.Get(i);
        g_aLeaderboards.GetArray(index, current, sizeof(StoreLeaderboardDefinition));
        FormatQuestText(client, current.title, title, sizeof(title));
        menu.AddItem(current.id, title);
    }

    delete ordered;
}

public int MenuHandler_Leaderboards(Menu menu, MenuAction action, int param1, int param2)
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
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "credits"))
        {
            OpenTopCreditsLeaderboard(param1, true);
        }
        else if (StrEqual(info, "profit"))
        {
            OpenTopProfitLeaderboard(param1, true);
        }
        else if (StrEqual(info, "daily"))
        {
            OpenTopDailyLeaderboard(param1, true);
        }
        else if (StrEqual(info, "blackjack"))
        {
            OpenTopBlackjackLeaderboard(param1, true);
        }
        else if (StrEqual(info, "coinflip"))
        {
            OpenTopCoinflipLeaderboard(param1, true);
        }
        else if (StrEqual(info, "crash"))
        {
            OpenTopCrashLeaderboard(param1, true);
        }
        else if (StrEqual(info, "roulette"))
        {
            OpenTopRouletteLeaderboard(param1, true);
        }
        else
        {
            OpenRegisteredLeaderboard(param1, info, true);
        }
    }

    return 0;
}

bool OpenRegisteredLeaderboard(int client, const char[] leaderboardId, bool backToHub = false)
{
    if (leaderboardId[0] == '\0' || g_aLeaderboards == null || g_mLeaderboardIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mLeaderboardIndex.GetValue(leaderboardId, index) || index < 0 || index >= g_aLeaderboards.Length)
    {
        return false;
    }

    StoreLeaderboardDefinition definition;
    g_aLeaderboards.GetArray(index, definition, sizeof(StoreLeaderboardDefinition));

    // stat_key is allowlisted by IsSafeStatKey at registration time, but it is
    // still interpolated into SQL: escape it so a future change to that
    // allowlist cannot turn this into an injection point.
    char safeLeaderboardKey[128];
    if (!EscapeStringSafe(definition.stat_key, safeLeaderboardKey, sizeof(safeLeaderboardKey)))
    {
        return false;
    }

    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = '%s' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name ASC LIMIT 10",
            safeLeaderboardKey);
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = '%s' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name COLLATE NOCASE ASC LIMIT 10",
            safeLeaderboardKey);
    }

    RequestLeaderboardMenu(client, query, definition.title, definition.entry_phrase, backToHub);
    return true;
}

void RequestLeaderboardMenu(int client, const char[] query, const char[] titlePhrase, const char[] entryPhrase, bool backToHub = false)
{
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(backToHub ? 1 : 0);
    pack.WriteString(titlePhrase);
    if (entryPhrase[0] != '\0' && TranslationPhraseExists(entryPhrase))
    {
        pack.WriteString(entryPhrase);
    }
    else
    {
        pack.WriteString("Top Profit Entry");
    }
    g_DB.Query(OnLeaderboardLoaded, query, pack);
}

public void OnLeaderboardLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userid = pack.ReadCell();
    bool backToHub = view_as<bool>(pack.ReadCell());
    char titlePhrase[64], entryPhrase[64];
    pack.ReadString(titlePhrase, sizeof(titlePhrase));
    pack.ReadString(entryPhrase, sizeof(entryPhrase));
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0] != '\0' || results == null)
    {
        LogStoreError("OnLeaderboardLoaded", error);
        PrintStorePhrase(client, "%T", "Leaderboard Load Failed", client);
        return;
    }

    Menu menu = new Menu(backToHub ? MenuHandler_LeaderboardHubView : MenuHandler_TopCredits);
    char title[192];
    FormatQuestText(client, titlePhrase, title, sizeof(title));
    menu.SetTitle(title);

    char playerName[64];
    int metric;
    char display[160];
    char info[8];
    int pos = 1;

    while (results.FetchRow())
    {
        results.FetchString(0, playerName, sizeof(playerName));
        metric = results.FetchInt(1);

        char metricText[32];
        FormatNumberDots(metric, metricText, sizeof(metricText));
        Format(display, sizeof(display), "%T", entryPhrase, client, pos, playerName, metricText);
        IntToString(pos, info, sizeof(info));
        menu.AddItem(info, display, ITEMDRAW_DISABLED);
        pos++;
    }

    if (pos == 1)
    {
        char emptyLabel[96];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "Top Credits Empty", client);
        menu.AddItem("empty", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, 20);
}

void OpenTopCreditsLeaderboard(int client, bool backToHub = false)
{
    char query[256];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT name, credits FROM store_players ORDER BY credits DESC, name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT name, credits FROM store_players ORDER BY credits DESC, name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Credits Menu Title", "Top Credits Entry", backToHub);
}

void OpenTopProfitLeaderboard(int client, bool backToHub = false)
{
    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, COALESCE(SUM(CASE WHEN s.stat_key = 'credits_earned' THEN s.stat_value WHEN s.stat_key = 'credits_spent' THEN -s.stat_value ELSE 0 END), 0) AS metric "
            ... "FROM store_players p LEFT JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key IN ('credits_earned', 'credits_spent') "
            ... "GROUP BY p.steamid, p.name ORDER BY metric DESC, p.name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, COALESCE(SUM(CASE WHEN s.stat_key = 'credits_earned' THEN s.stat_value WHEN s.stat_key = 'credits_spent' THEN -s.stat_value ELSE 0 END), 0) AS metric "
            ... "FROM store_players p LEFT JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key IN ('credits_earned', 'credits_spent') "
            ... "GROUP BY p.steamid, p.name ORDER BY metric DESC, p.name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Profit Menu Title", "Top Profit Entry", backToHub);
}

void OpenTopDailyLeaderboard(int client, bool backToHub = false)
{
    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'daily_best_streak' "
            ... "WHERE s.stat_value > 0 ORDER BY s.stat_value DESC, p.name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'daily_best_streak' "
            ... "WHERE s.stat_value > 0 ORDER BY s.stat_value DESC, p.name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Daily Menu Title", "Top Daily Entry", backToHub);
}

void OpenTopBlackjackLeaderboard(int client, bool backToHub = false)
{
    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'blackjack_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'blackjack_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Blackjack Profit Menu Title", "Top Profit Entry", backToHub);
}

void OpenTopCoinflipLeaderboard(int client, bool backToHub = false)
{
    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'coinflip_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'coinflip_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Coinflip Profit Menu Title", "Top Profit Entry", backToHub);
}

void OpenTopCrashLeaderboard(int client, bool backToHub = false)
{
    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'crash_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'crash_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Crash Profit Menu Title", "Top Profit Entry", backToHub);
}

void OpenTopRouletteLeaderboard(int client, bool backToHub = false)
{
    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'roulette_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'roulette_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Roulette Profit Menu Title", "Top Profit Entry", backToHub);
}

public Action Cmd_TopProfit(int client, int args)
{
    if (client > 0 && !EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (g_DB == null)
    {
        char msg[192];
        Format(msg, sizeof(msg), "%T", "Store DB Not Ready", client);
        ReplaceColorTags(msg, sizeof(msg));
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopProfitLeaderboard(client, false);
    return Plugin_Handled;
}

public Action Cmd_TopDaily(int client, int args)
{
    if (client > 0 && !EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (g_DB == null)
    {
        char msg[192];
        Format(msg, sizeof(msg), "%T", "Store DB Not Ready", client);
        ReplaceColorTags(msg, sizeof(msg));
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopDailyLeaderboard(client, false);
    return Plugin_Handled;
}

public Action Cmd_TopBlackjack(int client, int args)
{
    if (client > 0 && !EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (g_DB == null)
    {
        char msg[192];
        Format(msg, sizeof(msg), "%T", "Store DB Not Ready", client);
        ReplaceColorTags(msg, sizeof(msg));
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopBlackjackLeaderboard(client, false);
    return Plugin_Handled;
}

public Action Cmd_TopCoinflip(int client, int args)
{
    if (client > 0 && !EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (g_DB == null)
    {
        char msg[192];
        Format(msg, sizeof(msg), "%T", "Store DB Not Ready", client);
        ReplaceColorTags(msg, sizeof(msg));
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopCoinflipLeaderboard(client, false);
    return Plugin_Handled;
}

public Action Cmd_TopCrash(int client, int args)
{
    if (client > 0 && !EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (g_DB == null)
    {
        char msg[192];
        Format(msg, sizeof(msg), "%T", "Store DB Not Ready", client);
        ReplaceColorTags(msg, sizeof(msg));
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopCrashLeaderboard(client, false);
    return Plugin_Handled;
}

public Action Cmd_TopRoulette(int client, int args)
{
    if (client > 0 && !EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (g_DB == null)
    {
        char msg[192];
        Format(msg, sizeof(msg), "%T", "Store DB Not Ready", client);
        ReplaceColorTags(msg, sizeof(msg));
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopRouletteLeaderboard(client, false);
    return Plugin_Handled;
}

public Action Cmd_TopCredits(int client, int args)
{
    if (client > 0 && !EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (g_DB == null)
    {
        char msg[192];
        Format(msg, sizeof(msg), "%T", "Store DB Not Ready", client);
        ReplaceColorTags(msg, sizeof(msg));
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopCreditsLeaderboard(client, false);
    return Plugin_Handled;
}

public int MenuHandler_TopCredits(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        Cmd_Store(param1, 0);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

public int MenuHandler_LeaderboardHubView(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowLeaderboardsMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

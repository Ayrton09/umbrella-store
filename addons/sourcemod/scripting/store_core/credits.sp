// Umbrella Store core: Credit balances, time and event rewards, and credit notifications.
// Included by store_core.sp.

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (client > 0 && client <= MaxClients && !IsFakeClient(client) && IsClientInGame(client))
    {
        if (buttons != 0 || FloatAbs(vel[0]) > 0.1 || FloatAbs(vel[1]) > 0.1 || FloatAbs(vel[2]) > 0.1)
        {
            g_fLastActivity[client] = GetGameTime();
        }
    }

    return Plugin_Continue;
}

void FormatNumberDots(int value, char[] buffer, int maxlen)
{
    char raw[32];
    IntToString(value, raw, sizeof(raw));

    int len = strlen(raw);
    int start = 0;
    bool negative = false;

    if (raw[0] == '-')
    {
        negative = true;
        start = 1;
    }

    char temp[32];
    int out = 0;

    if (negative)
    {
        temp[out++] = '-';
    }

    for (int i = start; i < len; i++)
    {
        temp[out++] = raw[i];
        int remaining = len - i - 1;
        if (remaining > 0 && (remaining % 3) == 0)
        {
            temp[out++] = '.';
        }
    }

    temp[out] = '\0';
    strcopy(buffer, maxlen, temp);
}

void FormatCreditsAmount(int client, int value, char[] buffer, int maxlen)
{
    char number[32];
    FormatNumberDots(value, number, sizeof(number));
    Format(buffer, maxlen, "%T", "Credits Amount", client, number);
}

void SetupCreditCvars()
{
    gCvarStoreEnabled = CreateConVar("store_enabled", "1", "Enable or disable Umbrella Store globally.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gCvarCreditsTimeEnabled = CreateConVar("store_credits_time_enabled", "1", "Enable credits for time played.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarCreditsTimeAmount = CreateConVar("store_credits_time_amount", "10", "Credits earned per time interval.", FCVAR_NONE, true, 0.0);
    gCvarCreditsTimeInterval = CreateConVar("store_credits_time_interval", "60", "Interval in seconds for time-based credits.", FCVAR_NONE, true, 10.0);
    gCvarCreditsKillEnabled = CreateConVar("store_credits_kill_enabled", "1", "Enable credits for kills.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarCreditsKillAmount = CreateConVar("store_credits_kill_amount", "2", "Credits earned per kill.", FCVAR_NONE, true, 0.0);
    gCvarCreditsHeadshotBonus = CreateConVar("store_credits_headshot_bonus", "1", "Extra credits for headshots.", FCVAR_NONE, true, 0.0);
    gCvarCreditsRoundWinEnabled = CreateConVar("store_credits_roundwin_enabled", "1", "Enable credits for round wins.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarCreditsRoundWinAmount = CreateConVar("store_credits_roundwin_amount", "3", "Credits earned per round win.", FCVAR_NONE, true, 0.0);
    gCvarCreditsPlantEnabled = CreateConVar("store_credits_plant_enabled", "1", "Enable credits for bomb plant.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarCreditsPlantAmount = CreateConVar("store_credits_plant_amount", "2", "Credits earned for bomb plant.", FCVAR_NONE, true, 0.0);
    gCvarCreditsDefuseEnabled = CreateConVar("store_credits_defuse_enabled", "1", "Enable credits for bomb defuse.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarCreditsDefuseAmount = CreateConVar("store_credits_defuse_amount", "3", "Credits earned for bomb defuse.", FCVAR_NONE, true, 0.0);
    gCvarCreditsAfkMax = CreateConVar("store_credits_afk_max", "90", "Maximum idle seconds allowed to receive time-based credits.", FCVAR_NONE, true, 15.0);
    gCvarCreditsNotifyDelay = CreateConVar("store_credits_notify_delay", "2.0", "Delay in seconds to group credit messages and reduce spam.", FCVAR_NONE, true, 0.1);
    gCvarCreditsAutosaveInterval = CreateConVar("store_credits_autosave_interval", "120.0", "Auto-save interval for credits in seconds.", FCVAR_NONE, true, 30.0);
    gCvarStoreAdminFlag = CreateConVar("store_admin_flag", "z", "SourceMod admin flag required for the Umbrella Store admin menu. Default z = root.", FCVAR_NOTIFY);
    gCvarInitialCredits = CreateConVar("store_initial_credits", "1000", "Initial credits for new players.", FCVAR_NONE, true, 0.0);
    gCvarSellPercent = CreateConVar("store_sell_percent", "50", "Refund percentage when selling items.", FCVAR_NONE, true, 0.0, true, 100.0);
    gCvarPreviewLifetime = CreateConVar("store_preview_lifetime", "15.0", "Preview lifetime in seconds.", FCVAR_NONE, true, 1.0);
    gCvarPreviewDistance = CreateConVar("store_preview_distance", "100.0", "Distance at which preview appears.", FCVAR_NONE, true, 1.0);
    gCvarPreviewZOffset = CreateConVar("store_preview_zoffset", "60.0", "Vertical offset for preview.", FCVAR_NONE, true, -500.0, true, 500.0);
    gCvarEnablePlayerSkins = CreateConVar("store_enable_player_skins", "1", "Enable or disable store player skins.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gCvarPreviewCooldown = CreateConVar("store_preview_cooldown", "3.0", "Cooldown between skin previews in seconds.", FCVAR_NONE, true, 0.0);
    gCvarEquipCooldown = CreateConVar("store_equip_cooldown", "0.35", "Cooldown between equip and unequip actions in seconds.", FCVAR_NONE, true, 0.0);
    gCvarMarketEnabled = CreateConVar("umbrella_store_market_enabled", "1", "Enable or disable the Umbrella Store marketplace.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gCvarMarketMinPrice = CreateConVar("umbrella_store_market_min_price", "50", "Minimum price for marketplace listings.", FCVAR_NONE, true, 1.0);
    gCvarMarketMaxPrice = CreateConVar("umbrella_store_market_max_price", "1000000", "Maximum price for marketplace listings. 0 disables the cap.", FCVAR_NONE, true, 0.0);
    gCvarMarketListingHours = CreateConVar("umbrella_store_market_listing_hours", "72", "Hours before a marketplace listing expires.", FCVAR_NONE, true, 1.0, true, 720.0);
    gCvarMarketFeePercent = CreateConVar("umbrella_store_market_fee_percent", "5", "Marketplace fee percentage applied to completed sales.", FCVAR_NONE, true, 0.0, true, 100.0);
    HookConVarChange(gCvarStoreEnabled, OnStoreEnabledChanged);
    HookConVarChange(gCvarStoreAdminFlag, OnStoreAdminFlagChanged);
    HookConVarChange(gCvarCreditsTimeInterval, OnCreditTimerSettingsChanged);
    HookConVarChange(gCvarCreditsAutosaveInterval, OnCreditTimerSettingsChanged);

    AutoExecConfig(true, "umbrella_store_core");
}

public void OnCreditTimerSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    StartCreditTimers();
}

void StartCreditTimers()
{
    if (g_hCreditsTimeTimer != null)
    {
        KillTimer(g_hCreditsTimeTimer);
        g_hCreditsTimeTimer = null;
    }

    if (g_hCreditsAutosaveTimer != null)
    {
        KillTimer(g_hCreditsAutosaveTimer);
        g_hCreditsAutosaveTimer = null;
    }

    g_hCreditsTimeTimer = CreateTimer(float(gCvarCreditsTimeInterval.IntValue), Timer_GiveTimeCredits, _, TIMER_REPEAT);
    g_hCreditsAutosaveTimer = CreateTimer(gCvarCreditsAutosaveInterval.FloatValue, Timer_AutoSaveCredits, _, TIMER_REPEAT);

    if (g_hRentalExpireTimer != null)
    {
        KillTimer(g_hRentalExpireTimer);
        g_hRentalExpireTimer = null;
    }
    g_hRentalExpireTimer = CreateTimer(60.0, Timer_ExpireRentals, _, TIMER_REPEAT);
}

void MarkClientActive(int client)
{
    if (client > 0 && client <= MaxClients)
    {
        g_fLastActivity[client] = GetGameTime();
    }
}

bool IsClientEligibleForTimeCredits(int client)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return false;
    }

    int team = GetClientTeam(client);
    if (team < 2)
    {
        return false;
    }

    float afkSeconds = GetGameTime() - g_fLastActivity[client];
    return (afkSeconds <= gCvarCreditsAfkMax.FloatValue);
}

void QueueCreditNotification(int client, int amount, const char[] reason)
{
    if (!IsValidHumanClient(client) || amount <= 0)
    {
        return;
    }

    if (StrEqual(reason, "time"))
    {
        g_iCreditReasonTime[client] += amount;
    }
    else if (StrEqual(reason, "kill"))
    {
        g_iCreditReasonKill[client] += amount;
    }
    else if (StrEqual(reason, "headshot"))
    {
        g_iCreditReasonHeadshot[client] += amount;
    }
    else if (StrEqual(reason, "roundwin"))
    {
        g_iCreditReasonRoundWin[client] += amount;
    }
    else if (StrEqual(reason, "plant"))
    {
        g_iCreditReasonPlant[client] += amount;
    }
    else if (StrEqual(reason, "defuse"))
    {
        g_iCreditReasonDefuse[client] += amount;
    }

    if (g_hCreditNotifyTimer[client] == null)
    {
        g_hCreditNotifyTimer[client] = CreateTimer(gCvarCreditsNotifyDelay.FloatValue, Timer_FlushCreditNotify, GetClientUserId(client));
    }
}

void ReportCreditsChanged(int client, int delta, const char[] reason, bool notify = false, bool persisted = false)
{
    if (!IsValidClientConnected(client))
    {
        return;
    }

    g_bCreditsDirty[client] = !persisted;

    if (delta == 0)
    {
        return;
    }

    LogCreditLedger(client, delta, reason);
    TrackEconomyStats(client, delta);

    if (notify && delta > 0)
    {
        QueueCreditNotification(client, delta, reason);
    }

    if (delta > 0)
    {
        ForwardCreditsGiven(client, delta, reason);
    }

    ForwardCreditsChanged(client, delta, reason);
}

void AddCreditsEx(int client, int amount, const char[] reason, bool notify = true)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || amount <= 0)
    {
        return;
    }

    int newBalance;
    if (!TryComputeCreditBalance(g_iCredits[client], amount, newBalance))
    {
        return;
    }

    g_iCredits[client] = newBalance;
    ReportCreditsChanged(client, amount, reason, notify, false);
}

public Action Timer_GiveTimeCredits(Handle timer, any data)
{
    if (!IsStoreEnabled() || !gCvarCreditsTimeEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int amount = gCvarCreditsTimeAmount.IntValue;
    if (amount <= 0)
    {
        return Plugin_Continue;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientEligibleForTimeCredits(i))
        {
            AddCreditsEx(i, amount, "time", true);
        }
    }

    return Plugin_Continue;
}

public Action Timer_AutoSaveCredits(Handle timer, any data)
{
    SaveDirtyPlayers();
    return Plugin_Continue;
}

public Action Timer_FlushCreditNotify(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);

    // Clear the slot before any early return: this is a one-shot timer, so
    // leaving the (now dead) handle stored would both block future
    // notifications from re-arming and make the KillTimer in ResetClientData
    // throw, aborting the rest of the client cleanup.
    if (client >= 1 && client <= MaxClients && g_hCreditNotifyTimer[client] == timer)
    {
        g_hCreditNotifyTimer[client] = null;
    }

    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Stop;
    }

    int total = g_iCreditReasonTime[client] + g_iCreditReasonKill[client] + g_iCreditReasonHeadshot[client] + g_iCreditReasonRoundWin[client] + g_iCreditReasonPlant[client] + g_iCreditReasonDefuse[client];
    if (total <= 0)
    {
        return Plugin_Stop;
    }

    char amountText[32];
    FormatNumberDots(total, amountText, sizeof(amountText));

    if (g_iCreditReasonTime[client] > 0 && total == g_iCreditReasonTime[client])
    {
        PrintStorePhrase(client, "%T", "Credits Time", client, amountText);
    }
    else if (g_iCreditReasonRoundWin[client] > 0 && total == g_iCreditReasonRoundWin[client])
    {
        PrintStorePhrase(client, "%T", "Credits Round Win", client, amountText);
    }
    else if (g_iCreditReasonPlant[client] > 0 && total == g_iCreditReasonPlant[client])
    {
        PrintStorePhrase(client, "%T", "Credits Plant", client, amountText);
    }
    else if (g_iCreditReasonDefuse[client] > 0 && total == g_iCreditReasonDefuse[client])
    {
        PrintStorePhrase(client, "%T", "Credits Defuse", client, amountText);
    }
    else if (g_iCreditReasonKill[client] > 0 && total == (g_iCreditReasonKill[client] + g_iCreditReasonHeadshot[client]))
    {
        if (g_iCreditReasonHeadshot[client] > 0 && g_iCreditReasonKill[client] > 0)
        {
            PrintStorePhrase(client, "%T", "Credits Kill Combo", client, amountText);
        }
        else if (g_iCreditReasonHeadshot[client] > 0)
        {
            PrintStorePhrase(client, "%T", "Credits Kill Headshot", client, amountText);
        }
        else
        {
            PrintStorePhrase(client, "%T", "Credits Kill", client, amountText);
        }
    }
    else
    {
        char details[192];
        details[0] = '\0';
        bool first = true;
        char part[64];
        char partAmount[32];

        if (g_iCreditReasonTime[client] > 0)
        {
            FormatNumberDots(g_iCreditReasonTime[client], partAmount, sizeof(partAmount));
            Format(part, sizeof(part), "%T", "Credits Detail Time", client, partAmount);
            StrCat(details, sizeof(details), part);
            first = false;
        }

        if (g_iCreditReasonKill[client] > 0)
        {
            if (!first)
            {
                StrCat(details, sizeof(details), ", ");
            }
            FormatNumberDots(g_iCreditReasonKill[client], partAmount, sizeof(partAmount));
            Format(part, sizeof(part), "%T", "Credits Detail Kill", client, partAmount);
            StrCat(details, sizeof(details), part);
            first = false;
        }

        if (g_iCreditReasonHeadshot[client] > 0)
        {
            if (!first)
            {
                StrCat(details, sizeof(details), ", ");
            }
            FormatNumberDots(g_iCreditReasonHeadshot[client], partAmount, sizeof(partAmount));
            Format(part, sizeof(part), "%T", "Credits Detail Headshot", client, partAmount);
            StrCat(details, sizeof(details), part);
            first = false;
        }

        if (g_iCreditReasonRoundWin[client] > 0)
        {
            if (!first)
            {
                StrCat(details, sizeof(details), ", ");
            }
            FormatNumberDots(g_iCreditReasonRoundWin[client], partAmount, sizeof(partAmount));
            Format(part, sizeof(part), "%T", "Credits Detail Round Win", client, partAmount);
            StrCat(details, sizeof(details), part);
            first = false;
        }

        if (g_iCreditReasonPlant[client] > 0)
        {
            if (!first)
            {
                StrCat(details, sizeof(details), ", ");
            }
            FormatNumberDots(g_iCreditReasonPlant[client], partAmount, sizeof(partAmount));
            Format(part, sizeof(part), "%T", "Credits Detail Plant", client, partAmount);
            StrCat(details, sizeof(details), part);
            first = false;
        }

        if (g_iCreditReasonDefuse[client] > 0)
        {
            if (!first)
            {
                StrCat(details, sizeof(details), ", ");
            }
            FormatNumberDots(g_iCreditReasonDefuse[client], partAmount, sizeof(partAmount));
            Format(part, sizeof(part), "%T", "Credits Detail Defuse", client, partAmount);
            StrCat(details, sizeof(details), part);
        }

        PrintStorePhrase(client, "%T", "Credits Mixed Breakdown", client, amountText, details);
    }

    g_iCreditReasonTime[client] = 0;
    g_iCreditReasonKill[client] = 0;
    g_iCreditReasonHeadshot[client] = 0;
    g_iCreditReasonRoundWin[client] = 0;
    g_iCreditReasonPlant[client] = 0;
    g_iCreditReasonDefuse[client] = 0;

    return Plugin_Stop;
}

bool TryComputeCreditBalance(int current, int delta, int &next)
{
    if (current < 0 || current > STORE_MAX_CREDITS)
    {
        return false;
    }

    if (delta > 0 && current > STORE_MAX_CREDITS - delta)
    {
        return false;
    }

    next = current + delta;
    return next >= 0 && next <= STORE_MAX_CREDITS;
}

bool ApplyCreditDeltasAtomic(int clientA, int deltaA, const char[] reasonA, int clientB, int deltaB, const char[] reasonB, bool notify, const char[] extraQuery)
{
    if (g_DB == null || !g_bLateDatabaseReady)
    {
        return false;
    }

    if (clientA < 1 || clientA > MaxClients || !g_bIsLoaded[clientA])
    {
        return false;
    }

    if (clientB == clientA)
    {
        // Merging must not wrap: two large positive deltas summing past INT_MAX
        // would turn into a debit that TryComputeCreditBalance happily accepts.
        if ((deltaB > 0 && deltaA > STORE_MAX_CREDITS - deltaB)
            || (deltaB < 0 && deltaA < -STORE_MAX_CREDITS - deltaB))
        {
            return false;
        }

        deltaA += deltaB;
        deltaB = 0;
        clientB = 0;
    }

    if ((clientB == 0 && deltaB != 0) || (clientB != 0 && (clientB < 1 || clientB > MaxClients || !g_bIsLoaded[clientB])))
    {
        return false;
    }

    int nextA = g_iCredits[clientA];
    int nextB = (clientB > 0) ? g_iCredits[clientB] : 0;

    if (deltaA != 0 && !TryComputeCreditBalance(g_iCredits[clientA], deltaA, nextA))
    {
        return false;
    }

    if (clientB > 0 && deltaB != 0 && !TryComputeCreditBalance(g_iCredits[clientB], deltaB, nextB))
    {
        return false;
    }

    char queryA[512], queryB[512];
    if (deltaA != 0 && !BuildPlayerUpsertQueryForCredits(clientA, nextA, queryA, sizeof(queryA)))
    {
        return false;
    }

    if (clientB > 0 && deltaB != 0 && !BuildPlayerUpsertQueryForCredits(clientB, nextB, queryB, sizeof(queryB)))
    {
        return false;
    }

    if (!BeginLockedStoreTransaction("ApplyCreditDeltasAtomic"))
    {
        return false;
    }

    if (extraQuery[0] != '\0' && !ExecuteLockedStoreQuery("ApplyCreditDeltasAtomic", extraQuery))
    {
        RollbackLockedStoreTransaction("ApplyCreditDeltasAtomic");
        return false;
    }

    if (deltaA != 0 && !ExecuteLockedStoreQuery("ApplyCreditDeltasAtomic", queryA))
    {
        RollbackLockedStoreTransaction("ApplyCreditDeltasAtomic");
        return false;
    }

    if (clientB > 0 && deltaB != 0 && !ExecuteLockedStoreQuery("ApplyCreditDeltasAtomic", queryB))
    {
        RollbackLockedStoreTransaction("ApplyCreditDeltasAtomic");
        return false;
    }

    if (!CommitLockedStoreTransaction("ApplyCreditDeltasAtomic"))
    {
        return false;
    }

    if (deltaA != 0)
    {
        g_iCredits[clientA] = nextA;
        ReportCreditsChanged(clientA, deltaA, reasonA, notify, true);
    }

    if (clientB > 0 && deltaB != 0)
    {
        g_iCredits[clientB] = nextB;
        ReportCreditsChanged(clientB, deltaB, reasonB, notify, true);
    }

    return true;
}

bool SetCreditsAtomic(int client, int amount, const char[] reason, bool notify)
{
    if (amount < 0 || amount > STORE_MAX_CREDITS)
    {
        return false;
    }

    int delta = amount - g_iCredits[client];
    if (delta == 0)
    {
        return true;
    }

    return ApplyCreditDeltasAtomic(client, delta, reason, 0, 0, "", notify, "");
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (victim > 0)
    {
        RemovePreview(victim);
    }

    if (!IsStoreEnabled() || !gCvarCreditsKillEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (!IsValidHumanClient(attacker) || !IsValidHumanClient(victim) || attacker == victim || GetClientTeam(attacker) < 2 || GetClientTeam(victim) < 2 || GetClientTeam(attacker) == GetClientTeam(victim))
    {
        return Plugin_Continue;
    }

    MarkClientActive(attacker);
    AddCreditsEx(attacker, gCvarCreditsKillAmount.IntValue, "kill", true);

    if (event.GetBool("headshot"))
    {
        AddCreditsEx(attacker, gCvarCreditsHeadshotBonus.IntValue, "headshot", true);
    }

    return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsStoreEnabled() || !gCvarCreditsRoundWinEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int winner = event.GetInt("winner");
    if (winner < 2)
    {
        return Plugin_Continue;
    }

    int amount = gCvarCreditsRoundWinAmount.IntValue;
    if (amount <= 0)
    {
        return Plugin_Continue;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidHumanClient(i) && g_bIsLoaded[i] && GetClientTeam(i) == winner)
        {
            AddCreditsEx(i, amount, "roundwin", true);
        }
    }

    return Plugin_Continue;
}

public Action Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsStoreEnabled() || !gCvarCreditsPlantEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidHumanClient(client))
    {
        MarkClientActive(client);
        AddCreditsEx(client, gCvarCreditsPlantAmount.IntValue, "plant", true);
    }

    return Plugin_Continue;
}

public Action Event_BombDefused(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsStoreEnabled() || !gCvarCreditsDefuseEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidHumanClient(client))
    {
        MarkClientActive(client);
        AddCreditsEx(client, gCvarCreditsDefuseAmount.IntValue, "defuse", true);
    }

    return Plugin_Continue;
}

public Action Event_TeamplayRoundWin(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsStoreEnabled() || !gCvarCreditsRoundWinEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int winner = event.GetInt("team");
    if (winner < 2)
    {
        return Plugin_Continue;
    }

    int amount = gCvarCreditsRoundWinAmount.IntValue;
    if (amount <= 0)
    {
        return Plugin_Continue;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidHumanClient(i) && g_bIsLoaded[i] && GetClientTeam(i) == winner)
        {
            AddCreditsEx(i, amount, "roundwin", true);
        }
    }

    return Plugin_Continue;
}

bool IsStringNumeric(const char[] value)
{
    int len = strlen(value);
    if (len <= 0)
    {
        return false;
    }

    for (int i = 0; i < len; i++)
    {
        if (!IsCharNumeric(value[i]))
        {
            return false;
        }
    }

    return true;
}

bool TryParseBoundedInt(const char[] value, bool allowZero, int maxValue, int &result)
{
    char buffer[32];
    strcopy(buffer, sizeof(buffer), value);
    TrimString(buffer);

    int len = strlen(buffer);
    if (len <= 0)
    {
        return false;
    }

    int parsed = 0;
    for (int i = 0; i < len; i++)
    {
        int digit = buffer[i] - '0';
        if (digit < 0 || digit > 9)
        {
            return false;
        }

        if (parsed > (maxValue - digit) / 10)
        {
            return false;
        }

        parsed = parsed * 10 + digit;
    }

    if (!allowZero && parsed <= 0)
    {
        return false;
    }

    result = parsed;
    return true;
}

bool TryParseCreditAmount(const char[] value, int &amount)
{
    return TryParseBoundedInt(value, false, STORE_MAX_CREDITS, amount);
}

bool TryParseSignedCreditAmount(const char[] value, int &amount)
{
    char buffer[32];
    strcopy(buffer, sizeof(buffer), value);
    TrimString(buffer);

    bool negative = false;
    if (buffer[0] == '-')
    {
        negative = true;
        strcopy(buffer, sizeof(buffer), buffer[1]);
    }
    else if (buffer[0] == '+')
    {
        strcopy(buffer, sizeof(buffer), buffer[1]);
    }

    int parsed = 0;
    if (!TryParseCreditAmount(buffer, parsed))
    {
        return false;
    }

    amount = negative ? -parsed : parsed;
    return true;
}

bool TryParseNonNegativeAmount(const char[] value, int &amount)
{
    return TryParseBoundedInt(value, true, STORE_MAX_CREDITS, amount);
}

public Action Cmd_Credits(int client, int args)
{
    if (client > 0 && !EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (client > 0 && g_bIsLoaded[client])
    {
        char creditsText[32], broadcastName[MAX_NAME_LENGTH];
        FormatNumberDots(g_iCredits[client], creditsText, sizeof(creditsText));
        GetSafeClientName(client, broadcastName, sizeof(broadcastName));

        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsValidHumanClient(i))
            {
                continue;
            }

            PrintStorePhrase(i, "%T", "Credits Broadcast", i, broadcastName, creditsText);
        }
    }
    return Plugin_Handled;
}

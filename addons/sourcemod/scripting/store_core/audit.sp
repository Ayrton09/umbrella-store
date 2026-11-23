// Umbrella Store core: Audit log and credit ledger.
// Included by store_core.sp.

void LogCreditLedgerBySteamId(const char[] steamid, int balanceAfter, int amount, const char[] reason)
{
    if (amount == 0 || g_DB == null || steamid[0] == '\0' || reason[0] == '\0')
    {
        return;
    }

    char safeSteamId[80], safeReason[256], query[768];
    if (!EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId))
        || !EscapeStringSafe(reason, safeReason, sizeof(safeReason)))
    {
        LogError("%s Credit ledger entry was dropped because a value could not be escaped.", STORE_LOG_PREFIX);
        return;
    }

    Format(query, sizeof(query),
        "INSERT INTO store_credits_ledger (steamid, amount, reason, balance_after, created_at) VALUES ('%s', %d, '%s', %d, %d)",
        safeSteamId, amount, safeReason, balanceAfter, GetTime());

    g_DB.Query(DummyCallback, query);
}

void LogCreditLedger(int client, int amount, const char[] reason)
{
    if (amount == 0 || g_DB == null || !IsValidClientConnected(client) || reason[0] == '\0')
    {
        return;
    }

    char steamid[32];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return;
    }

    LogCreditLedgerBySteamId(steamid, g_iCredits[client], amount, reason);
}

void GetAuditIdentity(int client, char[] steamid, int steamidMax, char[] name, int nameMax)
{
    steamid[0] = '\0';
    name[0] = '\0';

    if (client == 0)
    {
        strcopy(name, nameMax, "Console");
        return;
    }

    if (!IsValidClientConnected(client))
    {
        return;
    }

    GetClientSteamIdSafe(client, steamid, steamidMax);
    GetClientName(client, name, nameMax);
}

bool InsertAuditEvent(const char[] actorSteam, const char[] actorName, const char[] targetSteam, const char[] targetName, const char[] action, const char[] itemId, int amount, const char[] details)
{
    if (g_DB == null || action[0] == '\0')
    {
        return false;
    }

    // Escaping needs 2 * strlen + 1 bytes: action is char[64] at the native
    // boundary and details is char[192], so the old 96/256 byte destinations
    // could not hold a worst-case value and Escape() would refuse to write.
    char safeActorSteam[80], safeActorName[160], safeTargetSteam[80], safeTargetName[160], safeAction[160], safeItemId[80], safeDetails[512], query[2048];
    if (!EscapeStringSafe(actorSteam, safeActorSteam, sizeof(safeActorSteam))
        || !EscapeStringSafe(actorName, safeActorName, sizeof(safeActorName))
        || !EscapeStringSafe(targetSteam, safeTargetSteam, sizeof(safeTargetSteam))
        || !EscapeStringSafe(targetName, safeTargetName, sizeof(safeTargetName))
        || !EscapeStringSafe(action, safeAction, sizeof(safeAction))
        || !EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId))
        || !EscapeStringSafe(details, safeDetails, sizeof(safeDetails)))
    {
        LogError("%s Audit event '%s' was dropped because a value could not be escaped.", STORE_LOG_PREFIX, action);
        return false;
    }

    Format(query, sizeof(query),
        "INSERT INTO store_audit_log (actor_steamid, actor_name, target_steamid, target_name, action, item_id, amount, details, created_at) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', %d, '%s', %d)",
        safeActorSteam, safeActorName, safeTargetSteam, safeTargetName, safeAction, safeItemId, amount, safeDetails, GetTime());

    g_DB.Query(DummyCallback, query);
    return true;
}

bool LogAuditEvent(int actor, int target, const char[] action, const char[] itemId = "", int amount = 0, const char[] details = "")
{
    char actorSteam[32], actorName[64], targetSteam[32], targetName[64];
    GetAuditIdentity(actor, actorSteam, sizeof(actorSteam), actorName, sizeof(actorName));
    GetAuditIdentity(target, targetSteam, sizeof(targetSteam), targetName, sizeof(targetName));

    return InsertAuditEvent(actorSteam, actorName, targetSteam, targetName, action, itemId, amount, details);
}

bool LogAuditEventBySteamId(int actor, const char[] targetSteam, const char[] targetName, const char[] action, const char[] itemId = "", int amount = 0, const char[] details = "")
{
    char actorSteam[32], actorName[64];
    GetAuditIdentity(actor, actorSteam, sizeof(actorSteam), actorName, sizeof(actorName));

    return InsertAuditEvent(actorSteam, actorName, targetSteam, targetName, action, itemId, amount, details);
}

void ReplyAuditOutput(int client, const char[] format, any ...)
{
    char buffer[256];
    VFormat(buffer, sizeof(buffer), format, 3);

    if (client > 0)
    {
        if (StrContains(buffer, "[Umbrella Store]") == 0)
        {
            ReplaceString(buffer, sizeof(buffer), "[Umbrella Store]", " {green}[Umbrella Store]{default}");
        }
        CReplyToCommand(client, "%s", buffer);
    }
    else
    {
        PrintToServer("%s", buffer);
    }
}

bool RequestStoreAudit(int client, int target, int limit, bool filterByTarget)
{
    if (g_DB == null || !g_bLateDatabaseReady)
    {
        ReplyAuditOutput(client, "[Umbrella Store] Database no lista.");
        return false;
    }

    if (limit < 1)
    {
        limit = 1;
    }
    else if (limit > 100)
    {
        limit = 100;
    }

    char safeTargetSteamId[64];
    safeTargetSteamId[0] = '\0';
    char targetLabel[64];
    strcopy(targetLabel, sizeof(targetLabel), "global");

    if (filterByTarget)
    {
        if (!IsValidStoreAdminTarget(client, target))
        {
            return false;
        }

        char targetSteamId[32];
        if (!GetClientSteamIdSafe(target, targetSteamId, sizeof(targetSteamId)))
        {
            ReplyAuditOutput(client, "[Umbrella Store] No se pudo obtener SteamID del objetivo.");
            return false;
        }

        EscapeStringSafe(targetSteamId, safeTargetSteamId, sizeof(safeTargetSteamId));
        GetClientName(target, targetLabel, sizeof(targetLabel));
    }

    char query[512];
    if (filterByTarget)
    {
        Format(query, sizeof(query),
            "SELECT actor_name, target_name, action, item_id, amount, details, created_at FROM store_audit_log WHERE target_steamid = '%s' OR actor_steamid = '%s' ORDER BY id DESC LIMIT %d",
            safeTargetSteamId,
            safeTargetSteamId, limit);
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT actor_name, target_name, action, item_id, amount, details, created_at FROM store_audit_log ORDER BY id DESC LIMIT %d",
            limit);
    }

    DataPack pack = new DataPack();
    pack.WriteCell((client > 0) ? GetClientUserId(client) : 0);
    pack.WriteCell(limit);
    pack.WriteCell(filterByTarget ? 1 : 0);
    pack.WriteCell(GetCmdReplySource());
    pack.WriteString(targetLabel);

    g_DB.Query(OnStoreAuditLoaded, query, pack);
    ReplyAuditOutput(client, "[Umbrella Store] Cargando auditoria general...");
    return true;
}

public Action Cmd_StoreAudit(int client, int args)
{
    if (g_DB == null || !g_bLateDatabaseReady)
    {
        ReplyAuditOutput(client, "[Umbrella Store] Database no lista.");
        return Plugin_Handled;
    }

    int limit = 20;
    if (args == 1)
    {
        char argLimit[16];
        GetCmdArg(1, argLimit, sizeof(argLimit));
        if (TryParseBoundedInt(argLimit, false, 100, limit))
        {
            limit = (limit < 1) ? 1 : limit;
        }
    }
    else if (args >= 2)
    {
        char argLimit[16];
        GetCmdArg(2, argLimit, sizeof(argLimit));
        if (!TryParseBoundedInt(argLimit, false, 100, limit))
        {
            ReplyAuditOutput(client, "[Umbrella Store] Uso: sm_storeaudit [target] [limit]");
            return Plugin_Handled;
        }
    }

    bool filterByTarget = false;
    int target = 0;

    bool firstArgIsLimit = false;
    if (args == 1)
    {
        char firstArg[64];
        GetCmdArg(1, firstArg, sizeof(firstArg));
        firstArgIsLimit = IsStringNumeric(firstArg);
    }

    if (args >= 1 && !firstArgIsLimit)
    {
        char argTarget[64];
        GetCmdArg(1, argTarget, sizeof(argTarget));

        if (StrEqual(argTarget, "@all", false) || StrEqual(argTarget, "all", false) || StrEqual(argTarget, "global", false))
        {
            filterByTarget = false;
        }
        else
        {
            int targets[MAXPLAYERS];
            int count = 0;
            if (!TryResolveCreditTargets(client, argTarget, targets, count) || count != 1)
            {
                ReplyAdminTargetNotFound(client, argTarget);
                return Plugin_Handled;
            }

            target = targets[0];
            filterByTarget = true;
        }
    }
    else if (client > 0)
    {
        target = client;
        filterByTarget = true;
    }

    RequestStoreAudit(client, target, limit, filterByTarget);
    return Plugin_Handled;
}

public void OnStoreAuditLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int requesterUserId = pack.ReadCell();
    int limit = pack.ReadCell();
    bool filtered = view_as<bool>(pack.ReadCell());
    ReplySource replySource = view_as<ReplySource>(pack.ReadCell());
    char targetLabel[64];
    pack.ReadString(targetLabel, sizeof(targetLabel));
    delete pack;

    int client = GetClientOfUserId(requesterUserId);
    bool toConsole = (requesterUserId == 0);
    if (!toConsole && (client <= 0 || !IsClientInGame(client)))
    {
        return;
    }

    ReplySource previousSource = SetCmdReplySource(replySource);

    if (db == null || results == null || error[0] != '\0')
    {
        ReplyAuditOutput(client, "[Umbrella Store] Error cargando auditoria: %s", error);
        SetCmdReplySource(previousSource);
        return;
    }

    if (filtered)
    {
        ReplyAuditOutput(client, "========== Store Audit (%s, ultimo %d) ==========", targetLabel, limit);
    }
    else
    {
        ReplyAuditOutput(client, "========== Store Audit (global, ultimo %d) ==========", limit);
    }

    bool hasRows = false;
    while (results.FetchRow())
    {
        hasRows = true;

        char actorName[64], targetName[64], actionName[64], itemId[32], details[192], when[32], amountText[32];
        int amount = 0;
        int createdAt = 0;

        results.FetchString(0, actorName, sizeof(actorName));
        results.FetchString(1, targetName, sizeof(targetName));
        results.FetchString(2, actionName, sizeof(actionName));
        results.FetchString(3, itemId, sizeof(itemId));
        amount = results.FetchInt(4);
        results.FetchString(5, details, sizeof(details));
        createdAt = results.FetchInt(6);

        FormatTime(when, sizeof(when), "%Y-%m-%d %H:%M:%S", createdAt);
        FormatNumberDots(amount, amountText, sizeof(amountText));

        ReplyAuditOutput(client, "[%s] actor=%s target=%s action=%s item=%s amount=%s details=%s",
            when,
            actorName[0] != '\0' ? actorName : "-",
            targetName[0] != '\0' ? targetName : "-",
            actionName,
            itemId[0] != '\0' ? itemId : "-",
            amountText,
            details[0] != '\0' ? details : "-");
    }

    if (!hasRows)
    {
        ReplyAuditOutput(client, "[Umbrella Store] No hay registros de auditoria para ese criterio.");
    }

    SetCmdReplySource(previousSource);
}

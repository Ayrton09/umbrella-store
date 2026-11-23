// Umbrella Store core: Voucher creation and redemption.
// Included by store_core.sp.

void NormalizeVoucherCode(char[] code, int maxlen)
{
    TrimString(code);

    int len = strlen(code);
    for (int i = 0; i < len && i < maxlen; i++)
    {
        if (code[i] >= 'a' && code[i] <= 'z')
        {
            code[i] -= 32;
        }
    }
}

bool IsValidVoucherCode(const char[] code)
{
    int len = strlen(code);
    if (len < 4 || len >= 64)
    {
        return false;
    }

    for (int i = 0; i < len; i++)
    {
        int c = code[i];
        if ((c >= 'A' && c <= 'Z')
            || (c >= 'a' && c <= 'z')
            || (c >= '0' && c <= '9')
            || c == '_'
            || c == '-')
        {
            continue;
        }

        return false;
    }

    return true;
}

bool InsertVoucher(int admin, const char[] rawCode, int credits, const char[] rewardItem, int maxUses, int expiresHours)
{
    if (g_DB == null || !g_bLateDatabaseReady)
    {
        ReplyStorePhrase(admin, "%T", "Store DB Not Ready", admin);
        return false;
    }

    char code[64];
    strcopy(code, sizeof(code), rawCode);
    NormalizeVoucherCode(code, sizeof(code));

    if (!IsValidVoucherCode(code))
    {
        ReplyStorePhrase(admin, "%T", "Voucher Invalid Code", admin);
        return false;
    }

    if (credits < 0 || maxUses < 0 || expiresHours < 0)
    {
        ReplyStorePhrase(admin, "%T", "Voucher Invalid Args", admin);
        return false;
    }

    if (credits == 0 && rewardItem[0] == '\0')
    {
        ReplyStorePhrase(admin, "%T", "Voucher Invalid Args", admin);
        return false;
    }

    if (rewardItem[0] != '\0')
    {
        StoreItem item;
        if (!FindStoreItemById(rewardItem, item))
        {
            ReplyStorePhrase(admin, "%T", "Item Not Found", admin);
            return false;
        }
    }

    char adminSteam[32], adminName[64], safeCode[96], safeItem[64], safeAdminSteam[64], safeAdminName[128], query[1024];
    GetAuditIdentity(admin, adminSteam, sizeof(adminSteam), adminName, sizeof(adminName));
    EscapeStringSafe(code, safeCode, sizeof(safeCode));
    EscapeStringSafe(rewardItem, safeItem, sizeof(safeItem));
    EscapeStringSafe(adminSteam, safeAdminSteam, sizeof(safeAdminSteam));
    EscapeStringSafe(adminName, safeAdminName, sizeof(safeAdminName));

    int expiresAt = 0;
    if (expiresHours > 0)
    {
        int now = GetTime();
        if (expiresHours > (STORE_MAX_CREDITS - now) / 3600)
        {
            ReplyStorePhrase(admin, "%T", "Voucher Invalid Args", admin);
            return false;
        }
        expiresAt = now + expiresHours * 3600;
    }
    Format(query, sizeof(query),
        "INSERT INTO store_vouchers (code, reward_credits, reward_item, max_uses, uses, expires_at, created_by_steamid, created_by_name, created_at, disabled) VALUES ('%s', %d, '%s', %d, 0, %d, '%s', '%s', %d, 0)",
        safeCode, credits, safeItem, maxUses, expiresAt, safeAdminSteam, safeAdminName, GetTime());

    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("InsertVoucher", error);
        ReplyStorePhrase(admin, "%T", "Voucher Create Failed", admin);
        return false;
    }

    LogAuditEvent(admin, 0, (rewardItem[0] != '\0') ? "voucher_create_item" : "voucher_create_credits", rewardItem, credits, code);
    ReplyStorePhrase(admin, "%T", "Voucher Created", admin, code);
    return true;
}

bool DisableVoucherCode(int admin, const char[] rawCode)
{
    if (g_DB == null || !g_bLateDatabaseReady)
    {
        ReplyStorePhrase(admin, "%T", "Store DB Not Ready", admin);
        return false;
    }

    char code[64], safeCode[96], query[256];
    strcopy(code, sizeof(code), rawCode);
    NormalizeVoucherCode(code, sizeof(code));
    if (!IsValidVoucherCode(code))
    {
        ReplyStorePhrase(admin, "%T", "Voucher Invalid Code", admin);
        return false;
    }

    EscapeStringSafe(code, safeCode, sizeof(safeCode));
    Format(query, sizeof(query), "UPDATE store_vouchers SET disabled = 1 WHERE code = '%s'", safeCode);
    if (!SQL_FastQuery(g_DB, query) || SQL_GetAffectedRows(g_DB) != 1)
    {
        ReplyStorePhrase(admin, "%T", "Voucher Not Found", admin);
        return false;
    }

    LogAuditEvent(admin, 0, "voucher_disable", "", 0, code);
    ReplyStorePhrase(admin, "%T", "Voucher Disabled", admin, code);
    return true;
}

bool RedeemVoucherCode(int client, const char[] rawCode)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null || g_DB == null || !g_bLateDatabaseReady)
    {
        return false;
    }

    char code[64], safeCode[96];
    strcopy(code, sizeof(code), rawCode);
    NormalizeVoucherCode(code, sizeof(code));
    if (!IsValidVoucherCode(code))
    {
        PrintStorePhrase(client, "%T", "Voucher Invalid Code", client);
        return false;
    }

    char steamid[32], name[64], safeSteamId[64], safeName[128];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    GetClientName(client, name, sizeof(name));
    EscapeStringSafe(code, safeCode, sizeof(safeCode));
    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(name, safeName, sizeof(safeName));

    if (!BeginLockedStoreTransaction("RedeemVoucher"))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    char query[1024];
    Format(query, sizeof(query),
        "SELECT reward_credits, reward_item, max_uses, uses, expires_at, disabled FROM store_vouchers WHERE code = '%s' LIMIT 1",
        safeCode);
    DBResultSet voucher = SQL_Query(g_DB, query);
    if (voucher == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("RedeemVoucher", error);
        RollbackLockedStoreTransaction("RedeemVoucher");
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!voucher.FetchRow())
    {
        delete voucher;
        RollbackLockedStoreTransaction("RedeemVoucher");
        PrintStorePhrase(client, "%T", "Voucher Not Found", client);
        return false;
    }

    int credits = voucher.FetchInt(0);
    char rewardItem[32];
    voucher.FetchString(1, rewardItem, sizeof(rewardItem));
    int maxUses = voucher.FetchInt(2);
    int uses = voucher.FetchInt(3);
    int expiresAt = voucher.FetchInt(4);
    int disabled = voucher.FetchInt(5);
    delete voucher;

    if (disabled != 0)
    {
        RollbackLockedStoreTransaction("RedeemVoucher");
        PrintStorePhrase(client, "%T", "Voucher Disabled Player", client);
        return false;
    }

    if (expiresAt > 0 && expiresAt < GetTime())
    {
        RollbackLockedStoreTransaction("RedeemVoucher");
        PrintStorePhrase(client, "%T", "Voucher Expired", client);
        return false;
    }

    if (maxUses > 0 && uses >= maxUses)
    {
        RollbackLockedStoreTransaction("RedeemVoucher");
        PrintStorePhrase(client, "%T", "Voucher Used Up", client);
        return false;
    }

    Format(query, sizeof(query),
        "SELECT redeemed_at FROM store_voucher_redemptions WHERE code = '%s' AND steamid = '%s' LIMIT 1",
        safeCode, safeSteamId);
    DBResultSet redemption = SQL_Query(g_DB, query);
    if (redemption == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("RedeemVoucher", error);
        RollbackLockedStoreTransaction("RedeemVoucher");
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    bool alreadyRedeemed = redemption.FetchRow();
    delete redemption;
    if (alreadyRedeemed)
    {
        RollbackLockedStoreTransaction("RedeemVoucher");
        PrintStorePhrase(client, "%T", "Voucher Already Redeemed", client);
        return false;
    }

    StoreItem item;
    bool givesItem = rewardItem[0] != '\0';
    if (givesItem)
    {
        if (!FindStoreItemById(rewardItem, item))
        {
            RollbackLockedStoreTransaction("RedeemVoucher");
            PrintStorePhrase(client, "%T", "Item Not Found", client);
            return false;
        }

        if (PlayerOwnsItem(client, item.id))
        {
            RollbackLockedStoreTransaction("RedeemVoucher");
            PrintStorePhrase(client, "%T", "Already Owns Item", client);
            return false;
        }
    }

    if (credits > 0)
    {
        // Validate against the cap before writing: persisting an unchecked sum
        // here while the in-memory update below is guarded would leave the row
        // and g_iCredits disagreeing, and the next autosave would silently
        // discard the voucher's credits.
        int voucherNewCredits = 0;
        if (!TryComputeCreditBalance(g_iCredits[client], credits, voucherNewCredits))
        {
            RollbackLockedStoreTransaction("RedeemVoucher");
            PrintStorePhrase(client, "%T", "Credit Limit Reached", client);
            return false;
        }

        char playerQuery[512];
        if (!BuildPlayerUpsertQueryForCredits(client, voucherNewCredits, playerQuery, sizeof(playerQuery)) || !ExecuteLockedStoreQuery("RedeemVoucher", playerQuery))
        {
            RollbackLockedStoreTransaction("RedeemVoucher");
            PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
            return false;
        }
    }

    if (givesItem)
    {
        char safeItemId[64];
        EscapeStringSafe(item.id, safeItemId, sizeof(safeItemId));
        Format(query, sizeof(query), "INSERT INTO store_inventory (steamid, item_id, is_equipped) VALUES ('%s', '%s', 0)", safeSteamId, safeItemId);
        if (!ExecuteLockedStoreQuery("RedeemVoucher", query, 1))
        {
            RollbackLockedStoreTransaction("RedeemVoucher");
            PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
            return false;
        }
    }

    Format(query, sizeof(query),
        "INSERT INTO store_voucher_redemptions (code, steamid, player_name, redeemed_at) VALUES ('%s', '%s', '%s', %d)",
        safeCode, safeSteamId, safeName, GetTime());
    if (!ExecuteLockedStoreQuery("RedeemVoucher", query, 1))
    {
        RollbackLockedStoreTransaction("RedeemVoucher");
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    Format(query, sizeof(query), "UPDATE store_vouchers SET uses = uses + 1 WHERE code = '%s'", safeCode);
    if (!ExecuteLockedStoreQuery("RedeemVoucher", query, 1))
    {
        RollbackLockedStoreTransaction("RedeemVoucher");
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!CommitLockedStoreTransaction("RedeemVoucher"))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (credits > 0)
    {
        int newBalance;
        if (TryComputeCreditBalance(g_iCredits[client], credits, newBalance))
        {
            g_iCredits[client] = newBalance;
            char reason[96];
            Format(reason, sizeof(reason), "voucher:%s", code);
            ReportCreditsChanged(client, credits, reason, true, true);
        }
        else
        {
            // Unreachable: the same check gates the committed row above. Logged
            // rather than ignored so a future regression cannot silently leave
            // the database ahead of the in-memory balance.
            LogError("%s Voucher '%s' committed %d credits for client %N but the in-memory balance could not be updated.", STORE_LOG_PREFIX, code, credits, client);
        }
    }

    if (givesItem)
    {
        InventoryItem newInv;
        strcopy(newInv.item_id, sizeof(newInv.item_id), item.id);
        newInv.is_equipped = 0;
        g_hInventory[client].PushArray(newInv, sizeof(InventoryItem));
        InventoryOwnedSet(client, item.id, true);
        MarkInventoryChanged(client);
        ForwardInventoryChanged(client, item.id, "voucher");
    }

    LogAuditEvent(client, client, "voucher_redeem", rewardItem, credits, code);

    if (credits > 0 && givesItem)
    {
        PrintStorePhrase(client, "%T", "Voucher Redeemed Credits Item", client, credits, item.name);
    }
    else if (credits > 0)
    {
        PrintStorePhrase(client, "%T", "Voucher Redeemed Credits", client, credits);
    }
    else if (givesItem)
    {
        PrintStorePhrase(client, "%T", "Voucher Redeemed Item", client, item.name);
    }

    return true;
}

public Action Cmd_RedeemVoucher(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (args < 1)
    {
        PrintStorePhrase(client, "%T", "Voucher Redeem Usage", client);
        return Plugin_Handled;
    }

    char code[64];
    GetCmdArg(1, code, sizeof(code));
    RedeemVoucherCode(client, code);
    return Plugin_Handled;
}

public Action Cmd_CreateVoucher(int client, int args)
{
    if (args < 2)
    {
        ReplyStorePhrase(client, "%T", "Voucher Create Credits Usage", client);
        return Plugin_Handled;
    }

    char code[64], creditsText[16], maxUsesText[16], expiresText[16];
    GetCmdArg(1, code, sizeof(code));
    GetCmdArg(2, creditsText, sizeof(creditsText));
    int credits = 0;
    int maxUses = 1;
    int expiresHours = 0;

    if (!TryParseCreditAmount(creditsText, credits))
    {
        ReplyStorePhrase(client, "%T", "Voucher Invalid Args", client);
        return Plugin_Handled;
    }

    if (args >= 3)
    {
        GetCmdArg(3, maxUsesText, sizeof(maxUsesText));
        if (!TryParseNonNegativeAmount(maxUsesText, maxUses))
        {
            ReplyStorePhrase(client, "%T", "Voucher Invalid Args", client);
            return Plugin_Handled;
        }
    }
    if (args >= 4)
    {
        GetCmdArg(4, expiresText, sizeof(expiresText));
        if (!TryParseNonNegativeAmount(expiresText, expiresHours))
        {
            ReplyStorePhrase(client, "%T", "Voucher Invalid Args", client);
            return Plugin_Handled;
        }
    }

    InsertVoucher(client, code, credits, "", maxUses, expiresHours);
    return Plugin_Handled;
}

public Action Cmd_CreateItemVoucher(int client, int args)
{
    if (args < 2)
    {
        ReplyStorePhrase(client, "%T", "Voucher Create Item Usage", client);
        return Plugin_Handled;
    }

    char code[64], itemId[32], maxUsesText[16], expiresText[16];
    GetCmdArg(1, code, sizeof(code));
    GetCmdArg(2, itemId, sizeof(itemId));
    int maxUses = 1;
    int expiresHours = 0;

    if (args >= 3)
    {
        GetCmdArg(3, maxUsesText, sizeof(maxUsesText));
        if (!TryParseNonNegativeAmount(maxUsesText, maxUses))
        {
            ReplyStorePhrase(client, "%T", "Voucher Invalid Args", client);
            return Plugin_Handled;
        }
    }
    if (args >= 4)
    {
        GetCmdArg(4, expiresText, sizeof(expiresText));
        if (!TryParseNonNegativeAmount(expiresText, expiresHours))
        {
            ReplyStorePhrase(client, "%T", "Voucher Invalid Args", client);
            return Plugin_Handled;
        }
    }

    InsertVoucher(client, code, 0, itemId, maxUses, expiresHours);
    return Plugin_Handled;
}

public Action Cmd_DisableVoucher(int client, int args)
{
    if (args < 1)
    {
        ReplyStorePhrase(client, "%T", "Voucher Disable Usage", client);
        return Plugin_Handled;
    }

    char code[64];
    GetCmdArg(1, code, sizeof(code));
    DisableVoucherCode(client, code);
    return Plugin_Handled;
}

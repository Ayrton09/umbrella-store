// Umbrella Store core: Buying, selling, purchase rules, and item rentals.
// Included by store_core.sp.

int GetSellPrice(int price)
{
    if (price <= 0)
    {
        return 0;
    }

    int sellPercent = (gCvarSellPercent != null) ? gCvarSellPercent.IntValue : STORE_SELL_PERCENT;
    if (sellPercent < 0)
    {
        sellPercent = 0;
    }
    else if (sellPercent > 100)
    {
        sellPercent = 100;
    }

    return (price * sellPercent) / 100;
}

int GetItemSellPrice(const StoreItem item)
{
    if (item.sale_price >= 0)
    {
        return item.sale_price;
    }

    if (item.sell_percent_override >= 0)
    {
        int sellPercent = item.sell_percent_override;
        if (sellPercent < 0)
        {
            sellPercent = 0;
        }
        else if (sellPercent > 100)
        {
            sellPercent = 100;
        }

        return (item.price * sellPercent) / 100;
    }

    return GetSellPrice(item.price);
}

bool CanPlayerUseItem(int client, StoreItem item, bool notify = false)
{
    if (!IsItemActiveForNow(item))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item No Longer Exists", client);
        }
        return false;
    }

    if (!HasAccess(client, item.flag))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "No Access Item", client);
        }
        return false;
    }

    if (item.requires_item[0] != '\0' && !PlayerOwnsItem(client, item.requires_item))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item Not Found", client);
        }
        return false;
    }

    return true;
}

bool IsItemActiveForNow(const StoreItem item)
{
    int now = GetTime();

    if (item.starts_at > 0 && now < item.starts_at)
    {
        return false;
    }

    if (item.ends_at > 0 && now > item.ends_at)
    {
        return false;
    }

    return true;
}

void SetReason(char[] reason, int maxlen, const char[] value)
{
    if (maxlen <= 0)
    {
        return;
    }

    strcopy(reason, maxlen, value);
}

bool CanPurchaseItemEx(int client, const char[] itemId, char[] reason, int maxlen)
{
    SetReason(reason, maxlen, "");

    if (!IsValidHumanClient(client))
    {
        SetReason(reason, maxlen, "invalid_client");
        return false;
    }

    if (!EnsureStoreEnabledForClient(client, false))
    {
        SetReason(reason, maxlen, "store_disabled");
        return false;
    }

    if (!g_bIsLoaded[client] || g_hInventory[client] == null || g_DB == null)
    {
        SetReason(reason, maxlen, "client_not_loaded");
        return false;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        SetReason(reason, maxlen, "item_not_found");
        return false;
    }

    if (item.hidden)
    {
        SetReason(reason, maxlen, "item_hidden");
        return false;
    }

    if (!IsItemActiveForNow(item))
    {
        SetReason(reason, maxlen, "item_unavailable");
        return false;
    }

    if (!HasAccess(client, item.flag))
    {
        SetReason(reason, maxlen, "no_access");
        return false;
    }

    int ownedIndex = FindInventoryIndexByItemId(client, item.id);
    if (ownedIndex != -1)
    {
        InventoryItem ownedInv;
        g_hInventory[client].GetArray(ownedIndex, ownedInv, sizeof(InventoryItem));
        if (ownedInv.expires_at == 0)
        {
            // Owned permanently, nothing left to buy.
            SetReason(reason, maxlen, "already_owned");
            return false;
        }
        // Timed rental: allow re-purchase to renew/extend or upgrade to permanent.
    }

    if (item.requires_item[0] != '\0' && !PlayerOwnsItem(client, item.requires_item))
    {
        SetReason(reason, maxlen, "requires_item");
        return false;
    }

    if (g_iCredits[client] < GetItemMinPlanPrice(item))
    {
        SetReason(reason, maxlen, "not_enough_credits");
        return false;
    }

    SetReason(reason, maxlen, "ok");
    return true;
}

// Parses an item's rental plans from the "plans" metadata key.
// Format: "days:price" pairs separated by ';'. days == 0 means permanent.
// Example: "7:500;30:1500;0:5000". Items without the key get a single
// permanent plan priced at item.price (fully backward compatible).
int GetItemPlans(StoreItem item, int planDays[MAX_ITEM_PLANS], int planPrice[MAX_ITEM_PLANS])
{
    char raw[192];
    if (!GetItemMetadataValue(item.id, "plans", raw, sizeof(raw)) || raw[0] == '\0')
    {
        planDays[0] = 0;
        planPrice[0] = item.price;
        return 1;
    }

    char parts[MAX_ITEM_PLANS][32];
    int n = ExplodeString(raw, ";", parts, sizeof(parts), sizeof(parts[]));
    int count = 0;
    for (int i = 0; i < n && count < MAX_ITEM_PLANS; i++)
    {
        TrimString(parts[i]);
        if (parts[i][0] == '\0')
        {
            continue;
        }

        char kv[2][16];
        if (ExplodeString(parts[i], ":", kv, sizeof(kv), sizeof(kv[])) < 2)
        {
            continue;
        }

        TrimString(kv[0]);
        TrimString(kv[1]);
        int d = StringToInt(kv[0]);
        int p = StringToInt(kv[1]);
        if (d < 0 || p < 0)
        {
            continue;
        }
        if (d > 3650)
        {
            d = 3650;   // cap rental length at 10 years to bound expiry math
        }

        planDays[count] = d;
        planPrice[count] = p;
        count++;
    }

    if (count == 0)
    {
        planDays[0] = 0;
        planPrice[0] = item.price;
        return 1;
    }

    return count;
}

// True if the item explicitly defines a "plans" key (even a single timed plan),
// so the UI routes through the plan menu instead of the flat buy button.
bool ItemHasPlans(StoreItem item)
{
    char raw[192];
    return GetItemMetadataValue(item.id, "plans", raw, sizeof(raw)) && raw[0] != '\0';
}

int GetItemMinPlanPrice(StoreItem item)
{
    int planDays[MAX_ITEM_PLANS], planPrice[MAX_ITEM_PLANS];
    int count = GetItemPlans(item, planDays, planPrice);
    int minPrice = planPrice[0];
    for (int i = 1; i < count; i++)
    {
        if (planPrice[i] < minPrice)
        {
            minPrice = planPrice[i];
        }
    }
    return minPrice;
}

// Expiry for a plan: 0 = permanent. For timed plans, extends from the later of
// "now" and any existing rental so renewals stack instead of resetting.
int ComputeRentalExpiry(int planDays, int currentExpires)
{
    if (planDays <= 0)
    {
        return 0;
    }

    int now = GetTime();
    int base = (currentExpires > now) ? currentExpires : now;
    int addSeconds = planDays * 86400;   // planDays capped at 3650, so this fits

    // Clamp the absolute expiry to avoid 32-bit overflow when renewals stack on
    // top of the current unix time (which is already ~1.7e9).
    if (base > 2000000000 - addSeconds)
    {
        return 2000000000;
    }
    return base + addSeconds;
}

int GetInventoryExpiry(int client, const char[] itemId)
{
    int index = FindInventoryIndexByItemId(client, itemId);
    if (index == -1)
    {
        return 0;
    }

    InventoryItem inv;
    g_hInventory[client].GetArray(index, inv, sizeof(InventoryItem));
    return inv.expires_at;
}

void FormatPlanDuration(int client, int days, char[] buffer, int maxlen)
{
    if (days <= 0)
    {
        Format(buffer, maxlen, "%T", "Plan Permanent", client);
    }
    else
    {
        Format(buffer, maxlen, "%T", "Plan Days", client, days);
    }
}

void FormatRentalRemaining(int client, int expiresAt, char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (expiresAt <= 0)
    {
        return;
    }

    int secondsLeft = expiresAt - GetTime();
    if (secondsLeft < 0)
    {
        secondsLeft = 0;
    }

    int d = secondsLeft / 86400;
    int h = (secondsLeft % 86400) / 3600;
    Format(buffer, maxlen, "%T", "Rental Time Left", client, d, h);
}

void DeleteExpiredInventoryRows(int client, int now)
{
    if (g_DB == null)
    {
        return;
    }

    char steamid[32], safeSteamId[64], query[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return;
    }

    if (!EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId)))
    {
        return;
    }

    Format(query, sizeof(query),
        "DELETE FROM store_inventory WHERE steamid = '%s' AND expires_at > 0 AND expires_at <= %d",
        safeSteamId, now);
    g_DB.Query(OnExpiredRentalDeleted, query);
}

// Unlike the schema-migration queries, this delete must be reported when it
// fails: the rows are already gone from memory, so a silent failure means the
// expired rental comes back on the player's next connect.
public void OnExpiredRentalDeleted(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || error[0] != '\0')
    {
        LogStoreError("DeleteExpiredInventoryRows", error);
    }
}

// Periodic sweep that removes rentals which expired while the player is online.
public Action Timer_ExpireRentals(Handle timer)
{
    int now = GetTime();
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_bIsLoaded[client] || g_hInventory[client] == null)
        {
            continue;
        }

        bool changed = false;
        for (int i = g_hInventory[client].Length - 1; i >= 0; i--)
        {
            InventoryItem inv;
            g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
            if (inv.expires_at <= 0 || inv.expires_at > now)
            {
                continue;
            }

            if (inv.is_equipped)
            {
                SetItemEquipped(client, inv.item_id, false, false, false, true);
            }

            g_hInventory[client].Erase(i);
            InventoryOwnedSet(client, inv.item_id, false);
            changed = true;

            if (IsValidHumanClient(client))
            {
                StoreItem expiredItem;
                char displayName[64];
                if (FindStoreItemById(inv.item_id, expiredItem))
                {
                    strcopy(displayName, sizeof(displayName), expiredItem.name);
                }
                else
                {
                    strcopy(displayName, sizeof(displayName), inv.item_id);
                }
                PrintStorePhrase(client, "%T", "Rental Expired Notify", client, displayName);
            }
        }

        if (changed)
        {
            DeleteExpiredInventoryRows(client, now);
            MarkInventoryChanged(client);
        }
    }

    return Plugin_Continue;
}

void ShowBuyPlanMenu(int client, const char[] itemId)
{
    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        return;
    }

    int planDays[MAX_ITEM_PLANS], planPrice[MAX_ITEM_PLANS];
    int count = GetItemPlans(item, planDays, planPrice);

    Menu menu = new Menu(MenuHandler_BuyPlan);
    char title[128];
    Format(title, sizeof(title), "%T", "Buy Plan Title", client, item.name);
    menu.SetTitle(title);

    for (int i = 0; i < count; i++)
    {
        char info[64], durText[48], priceText[48], label[160];
        Format(info, sizeof(info), "bp_%d_%s", i, item.id);
        FormatPlanDuration(client, planDays[i], durText, sizeof(durText));
        FormatCreditsAmount(client, planPrice[i], priceText, sizeof(priceText));
        Format(label, sizeof(label), "%s - %s", durText, priceText);
        menu.AddItem(info, label);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_BuyPlan(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_ExitBack && g_szLastDetailItem[param1][0] != '\0')
        {
            ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
        }
    }
    else if (action == MenuAction_Select)
    {
        char info[64];
        menu.GetItem(param2, info, sizeof(info));

        // Format: bp_<idx>_<itemId>
        char body[64];
        strcopy(body, sizeof(body), info[3]);
        int sep = FindCharInString(body, '_');
        if (sep <= 0)
        {
            return 0;
        }

        char idxStr[8], itemId[32];
        strcopy(idxStr, sizeof(idxStr), body);
        if (sep < sizeof(idxStr))
        {
            idxStr[sep] = '\0';
        }
        strcopy(itemId, sizeof(itemId), body[sep + 1]);
        int idx = StringToInt(idxStr);

        StoreItem item;
        if (!FindStoreItemById(itemId, item))
        {
            return 0;
        }

        int planDays[MAX_ITEM_PLANS], planPrice[MAX_ITEM_PLANS];
        int count = GetItemPlans(item, planDays, planPrice);
        if (idx >= 0 && idx < count)
        {
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, false))
            {
                BuyItem(param1, itemId, false, true, planDays[idx], planPrice[idx]);
            }
        }
        ShowItemDetailsMenu(param1, itemId);
    }

    return 0;
}

bool BuyItem(int client, const char[] itemId, bool equipAfterPurchase = false, bool notify = true, int planDays = 0, int planPrice = -1)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null || g_DB == null)
    {
        return false;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item No Longer Exists", client);
        }
        return false;
    }

    if (item.price < 0)
    {
        LogError("%s BuyItem: invalid negative price for item '%s' (%d)", STORE_LOG_PREFIX, item.id, item.price);
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item No Longer Exists", client);
        }
        return false;
    }

    char reason[64];
    if (!CanPurchaseItemEx(client, item.id, reason, sizeof(reason)))
    {
        if (notify)
        {
            if (StrEqual(reason, "not_enough_credits"))
            {
                PrintStorePhrase(client, "%T", "Not Enough Credits", client);
            }
            else if (StrEqual(reason, "no_access"))
            {
                PrintStorePhrase(client, "%T", "No Access Item", client);
            }
            else if (StrEqual(reason, "already_owned"))
            {
                PrintStorePhrase(client, "%T", "Already Owns Item", client);
            }
            else
            {
                PrintStorePhrase(client, "%T", "Item No Longer Exists", client);
            }
        }
        return false;
    }

    if (ForwardPurchasePre(client, item.id, equipAfterPurchase) >= Plugin_Handled)
    {
        return false;
    }

    char steamid[32], safeSteamId[64], safeItemId[64], query[256], playerQuery[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(item.id, safeItemId, sizeof(safeItemId));

    // Resolve effective price (selected plan or base price) and the new expiry.
    // Re-buying a timed item the player already owns renews/extends it.
    // If no explicit plan was passed (e.g. the direct buy button), resolve the
    // item's canonical plan so a configured single timed plan is honored instead
    // of silently defaulting to permanent at item.price. With no "plans" key,
    // GetItemPlans returns one permanent plan at item.price (unchanged behavior).
    if (planPrice < 0)
    {
        int canonDays[MAX_ITEM_PLANS], canonPrice[MAX_ITEM_PLANS];
        GetItemPlans(item, canonDays, canonPrice);
        planDays = canonDays[0];
        planPrice = canonPrice[0];
    }

    int effectivePrice = (planPrice >= 0) ? planPrice : item.price;
    if (effectivePrice < 0)
    {
        effectivePrice = 0;
    }
    bool isRenewal = PlayerOwnsItem(client, item.id);
    int newExpiry = ComputeRentalExpiry(planDays, GetInventoryExpiry(client, item.id));

    int newCredits = g_iCredits[client] - effectivePrice;
    if (newCredits < 0)
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Not Enough Credits", client);
        }
        return false;
    }

    if (!BuildPlayerUpsertQueryForCredits(client, newCredits, playerQuery, sizeof(playerQuery)))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (isRenewal)
    {
        Format(query, sizeof(query),
            "UPDATE store_inventory SET expires_at = %d WHERE steamid = '%s' AND item_id = '%s'",
            newExpiry, safeSteamId, safeItemId);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO store_inventory (steamid, item_id, is_equipped, expires_at) VALUES ('%s', '%s', 0, %d)",
            safeSteamId, safeItemId, newExpiry);
    }

    if (!BeginLockedStoreTransaction("BuyItem"))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!ExecuteLockedStoreQuery("BuyItem", playerQuery))
    {
        RollbackLockedStoreTransaction("BuyItem");
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!ExecuteLockedStoreQuery("BuyItem", query, 1, isRenewal))
    {
        RollbackLockedStoreTransaction("BuyItem");
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!CommitLockedStoreTransaction("BuyItem"))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    g_iCredits[client] = newCredits;
    char buyReason[64];
    Format(buyReason, sizeof(buyReason), "buy:%s", item.id);
    ReportCreditsChanged(client, -effectivePrice, buyReason, false, true);

    if (isRenewal)
    {
        int invIndex = FindInventoryIndexByItemId(client, item.id);
        if (invIndex != -1)
        {
            InventoryItem renewInv;
            g_hInventory[client].GetArray(invIndex, renewInv, sizeof(InventoryItem));
            renewInv.expires_at = newExpiry;
            g_hInventory[client].SetArray(invIndex, renewInv, sizeof(InventoryItem));
        }
    }
    else
    {
        InventoryItem newInv;
        strcopy(newInv.item_id, sizeof(newInv.item_id), item.id);
        newInv.is_equipped = 0;
        newInv.expires_at = newExpiry;
        g_hInventory[client].PushArray(newInv, sizeof(InventoryItem));
        InventoryOwnedSet(client, item.id, true);
    }
    MarkInventoryChanged(client);
    ForwardInventoryChanged(client, item.id, "purchase");
    UpdatePlayerStat(client, "purchases_total", 1);

    bool equippedAfterPurchase = false;
    if (equipAfterPurchase)
    {
        equippedAfterPurchase = SetItemEquipped(client, item.id, true, notify, false);
    }

    if (notify)
    {
        char priceText[32], balanceText[32];
        FormatNumberDots(effectivePrice, priceText, sizeof(priceText));
        FormatNumberDots(g_iCredits[client], balanceText, sizeof(balanceText));

        PrintStorePhrase(client, "%T", "Item Bought", client, item.name, priceText);
        PrintStorePhrase(client, "%T", "Balance Current", client, balanceText);
    }

    ForwardItemPurchased(client, item.id);
    ForwardPurchasePost(client, item.id, effectivePrice, equippedAfterPurchase);
    LogAuditEvent(client, client, "purchase", item.id, -effectivePrice, "");
    return true;
}

bool SellItem(int client, const char[] itemId)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null || g_DB == null)
    {
        return false;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        PrintStorePhrase(client, "%T", "Item Missing Config", client);
        return false;
    }

    int index = FindInventoryIndexByItemId(client, item.id);
    if (index == -1)
    {
        PrintStorePhrase(client, "%T", "Item Not Owned", client);
        return false;
    }

    // Rentals cannot be sold back: the sell price is based on the permanent
    // price, which would let a cheap rental be cashed out for full value.
    if (GetInventoryExpiry(client, item.id) > 0)
    {
        PrintStorePhrase(client, "%T", "Rental Not Transferable", client);
        return false;
    }

    if (HasActiveMarketplaceListing(client, item.id))
    {
        PrintStorePhrase(client, "%T", "Market Item Listed Already", client);
        return false;
    }

    InventoryItem inv;
    g_hInventory[client].GetArray(index, inv, sizeof(InventoryItem));
    bool wasEquipped = view_as<bool>(inv.is_equipped);

    char steamid[32], safeSteamId[64], safeItemId[64], query[256], playerQuery[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(item.id, safeItemId, sizeof(safeItemId));
    int refund = GetItemSellPrice(item);
    int newCredits = 0;
    if (!TryComputeCreditBalance(g_iCredits[client], refund, newCredits))
    {
        PrintStorePhrase(client, "%T", "Credit Limit Reached", client);
        return false;
    }

    if (!BuildPlayerUpsertQueryForCredits(client, newCredits, playerQuery, sizeof(playerQuery)))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    Format(query, sizeof(query), "DELETE FROM store_inventory WHERE steamid = '%s' AND item_id = '%s'", safeSteamId, safeItemId);
    if (!BeginLockedStoreTransaction("SellItem"))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!ExecuteLockedStoreQuery("SellItem", query, 1))
    {
        RollbackLockedStoreTransaction("SellItem");
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!ExecuteLockedStoreQuery("SellItem", playerQuery))
    {
        RollbackLockedStoreTransaction("SellItem");
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!CommitLockedStoreTransaction("SellItem"))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    g_hInventory[client].Erase(index);
    InventoryOwnedSet(client, item.id, false);
    MarkInventoryChanged(client);
    g_iCredits[client] = newCredits;
    char sellReason[64];
    Format(sellReason, sizeof(sellReason), "sell:%s", item.id);
    ReportCreditsChanged(client, refund, sellReason, false, true);
    ForwardInventoryChanged(client, item.id, "sell");
    LogAuditEvent(client, client, "sell", item.id, refund, "");
    UpdatePlayerStat(client, "sales_total", 1);

    if (wasEquipped && StrEqual(item.type, "skin"))
    {
        ApplyPlayerSkin(client);
    }

    char refundText[32], balanceText[32];
    FormatNumberDots(refund, refundText, sizeof(refundText));
    FormatNumberDots(g_iCredits[client], balanceText, sizeof(balanceText));

    PrintStorePhrase(client, "%T", "Item Sold", client, item.name, refundText);
    PrintStorePhrase(client, "%T", "Balance Current", client, balanceText);
    return true;
}

void ShowSellConfirmMenu(int client, const char[] itemId)
{
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        PrintStorePhrase(client, "%T", "Item Not Found", client);
        if (g_bDetailFromInventory[client])
        {
            ShowInventoryListMenu(client, g_szInvFilter[client]);
        }
        else
        {
            ShowCurrentBrowseItemsList(client);
        }
        return;
    }

    strcopy(g_szLastDetailItem[client], sizeof(g_szLastDetailItem[]), item.id);

    Menu menu = new Menu(MenuHandler_SellConfirm);

    char title[192];
    char refundText[48];
    char receiveLabel[64];
    char yesLabel[64];
    char noLabel[64];
    // Must match what SellItem actually refunds (honours sale_price and
    // sell_percent_override), otherwise the confirmation quotes a price the
    // player will not receive.
    FormatCreditsAmount(client, GetItemSellPrice(item), refundText, sizeof(refundText));
    Format(receiveLabel, sizeof(receiveLabel), "%T", "Sell Receive Label", client);
    Format(title, sizeof(title), "%T", "Sell Confirm Title Menu", client, receiveLabel, refundText);
    menu.SetTitle(title);

    char yesInfo[64], noInfo[64];
    Format(yesInfo, sizeof(yesInfo), "yes_%s", item.id);
    Format(noInfo, sizeof(noInfo), "no_%s", item.id);
    Format(yesLabel, sizeof(yesLabel), "%T", "Sell Confirm Yes", client);
    Format(noLabel, sizeof(noLabel), "%T", "Sell Confirm No", client);

    menu.AddItem(yesInfo, yesLabel);
    menu.AddItem(noInfo, noLabel);
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_SellConfirm(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        if (g_szLastDetailItem[param1][0] != '\0')
        {
            ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
        }
        else
        {
            ShowCurrentBrowseItemsList(param1);
        }
    }
    else if (action == MenuAction_Select)
    {
        char info[64], itemId[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrContains(info, "yes_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[4]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, true))
            {
                SellItem(param1, itemId);
            }
            if (g_bDetailFromInventory[param1])
            {
                ShowInventoryListMenu(param1, g_szInvFilter[param1]);
            }
            else if (g_bDetailFromSearch[param1])
            {
                ShowSearchResultsMenu(param1, g_szSearchQuery[param1]);
            }
            else
            {
                ShowCurrentBrowseItemsList(param1);
            }
        }
        else if (StrContains(info, "no_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[3]);
            ShowItemDetailsMenu(param1, itemId);
        }
    }

    return 0;
}

// Umbrella Store core: Player marketplace listings, purchases, and menus.
// Included by store_core.sp.

bool IsMarketplaceEnabled()
{
    return (gCvarMarketEnabled == null || gCvarMarketEnabled.BoolValue);
}

int GetMarketplaceMinPrice()
{
    return (gCvarMarketMinPrice != null) ? gCvarMarketMinPrice.IntValue : 50;
}

int GetMarketplaceMaxPrice()
{
    return (gCvarMarketMaxPrice != null) ? gCvarMarketMaxPrice.IntValue : 1000000;
}

int GetMarketplaceListingHours()
{
    return (gCvarMarketListingHours != null) ? gCvarMarketListingHours.IntValue : 72;
}

int GetMarketplaceFeePercent()
{
    return (gCvarMarketFeePercent != null) ? gCvarMarketFeePercent.IntValue : 5;
}

bool HasActiveMarketplaceListingForSteamId(const char[] steamid, const char[] itemId)
{
    if (g_DB == null || steamid[0] == '\0' || itemId[0] == '\0')
    {
        return false;
    }

    char safeSteamId[64], safeItemId[64], query[320];
    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));
    Format(query, sizeof(query),
        "SELECT id FROM store_market_listings WHERE seller_steamid = '%s' AND item_id = '%s' AND sold_at = 0 AND cancelled_at = 0 AND expires_at > %d LIMIT 1",
        safeSteamId, safeItemId, GetTime());

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("HasActiveMarketplaceListingForSteamId", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }

    bool found = results.FetchRow();
    delete results;
    SQL_UnlockDatabase(g_DB);
    return found;
}

bool HasActiveMarketplaceListing(int client, const char[] itemId)
{
    char steamid[32];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    return HasActiveMarketplaceListingForSteamId(steamid, itemId);
}

// Menus that need the listing state of a whole inventory must not run one
// blocking SELECT per item: with a remote MySQL server that stalls the game
// thread once per owned item every time the menu is opened.
StringMap GetActiveMarketplaceListingSet(int client)
{
    StringMap listed = new StringMap();

    char steamid[32];
    if (g_DB == null || !GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return listed;
    }

    char safeSteamId[80], query[320];
    if (!EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId)))
    {
        return listed;
    }

    Format(query, sizeof(query),
        "SELECT item_id FROM store_market_listings WHERE seller_steamid = '%s' AND sold_at = 0 AND cancelled_at = 0 AND expires_at > %d",
        safeSteamId, GetTime());

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("GetActiveMarketplaceListingSet", error);
        SQL_UnlockDatabase(g_DB);
        return listed;
    }

    char itemId[32];
    while (results.FetchRow())
    {
        results.FetchString(0, itemId, sizeof(itemId));
        listed.SetValue(itemId, 1);
    }

    delete results;
    SQL_UnlockDatabase(g_DB);
    return listed;
}

bool CancelMarketplaceListingsForSteamIdItem(const char[] steamid, const char[] itemId)
{
    if (g_DB == null || steamid[0] == '\0' || itemId[0] == '\0')
    {
        return false;
    }

    char safeSteamId[64], safeItemId[64], query[320];
    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));

    if (!BeginLockedStoreTransaction("CancelMarketplaceListingsForSteamIdItem"))
    {
        return false;
    }

    Format(query, sizeof(query),
        "UPDATE store_market_listings SET cancelled_at = %d WHERE seller_steamid = '%s' AND item_id = '%s' AND sold_at = 0 AND cancelled_at = 0",
        GetTime(), safeSteamId, safeItemId);

    if (!ExecuteLockedStoreQuery("CancelMarketplaceListingsForSteamIdItem", query))
    {
        RollbackLockedStoreTransaction("CancelMarketplaceListingsForSteamIdItem");
        return false;
    }

    if (!ReleaseMarketplaceListingLock(safeSteamId, safeItemId))
    {
        RollbackLockedStoreTransaction("CancelMarketplaceListingsForSteamIdItem");
        return false;
    }

    return CommitLockedStoreTransaction("CancelMarketplaceListingsForSteamIdItem");
}

bool CancelMarketplaceListingsForClientItem(int client, const char[] itemId)
{
    char steamid[32];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    return CancelMarketplaceListingsForSteamIdItem(steamid, itemId);
}

bool CleanupStaleMarketplaceLock(const char[] safeSteamId, const char[] safeItemId, int now)
{
    char query[768];
    Format(query, sizeof(query),
        "DELETE FROM store_market_locks WHERE seller_steamid = '%s' AND item_id = '%s' AND NOT EXISTS (SELECT 1 FROM store_market_listings WHERE seller_steamid = '%s' AND item_id = '%s' AND sold_at = 0 AND cancelled_at = 0 AND expires_at > %d)",
        safeSteamId, safeItemId, safeSteamId, safeItemId, now);

    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("CleanupStaleMarketplaceLock", error);
        return false;
    }

    return true;
}

bool TryAcquireMarketplaceListingLock(const char[] safeSteamId, const char[] safeItemId, int now)
{
    if (!CleanupStaleMarketplaceLock(safeSteamId, safeItemId, now))
    {
        return false;
    }

    char query[320];
    Format(query, sizeof(query),
        "INSERT INTO store_market_locks (seller_steamid, item_id, created_at) VALUES ('%s', '%s', %d)",
        safeSteamId, safeItemId, now);

    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("TryAcquireMarketplaceListingLock", error);
        return false;
    }

    return SQL_GetAffectedRows(g_DB) == 1;
}

bool ReleaseMarketplaceListingLock(const char[] safeSteamId, const char[] safeItemId)
{
    char query[256];
    Format(query, sizeof(query),
        "DELETE FROM store_market_locks WHERE seller_steamid = '%s' AND item_id = '%s'",
        safeSteamId, safeItemId);

    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("ReleaseMarketplaceListingLock", error);
        return false;
    }

    return true;
}

void SyncMarketplaceTransferInMemory(const char[] sellerSteamId, int buyer, const char[] itemId, int sellerNetCredits)
{
    int seller = GetOnlineClientBySteamId(sellerSteamId);
    int sellerIndex = (seller > 0) ? FindInventoryIndexByItemId(seller, itemId) : -1;

    if (seller > 0 && sellerIndex != -1)
    {
        g_hInventory[seller].Erase(sellerIndex);
        InventoryOwnedSet(seller, itemId, false);
        MarkInventoryChanged(seller);

        // Mirror the capped value the transaction already committed rather than
        // adding blind, so memory can never drift above STORE_MAX_CREDITS.
        int sellerNewBalance = 0;
        if (!TryComputeCreditBalance(g_iCredits[seller], sellerNetCredits, sellerNewBalance))
        {
            sellerNewBalance = STORE_MAX_CREDITS;
            LogError("%s Marketplace sale credited %d to %N above the store maximum; balance clamped.", STORE_LOG_PREFIX, sellerNetCredits, seller);
        }
        g_iCredits[seller] = sellerNewBalance;
        ReportCreditsChanged(seller, sellerNetCredits, "market_sale", false, true);
        ForwardInventoryChanged(seller, itemId, "market_sale_out");
    }

    if (g_hInventory[buyer] != null && !PlayerOwnsItem(buyer, itemId))
    {
        InventoryItem newInv;
        strcopy(newInv.item_id, sizeof(newInv.item_id), itemId);
        newInv.is_equipped = 0;
        g_hInventory[buyer].PushArray(newInv, sizeof(InventoryItem));
        InventoryOwnedSet(buyer, itemId, true);
        MarkInventoryChanged(buyer);
        ForwardInventoryChanged(buyer, itemId, "market_buy_in");
    }
}

public Action Cmd_Market(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (!IsMarketplaceEnabled())
    {
        PrintStorePhrase(client, "%T", "Market Disabled", client);
        return Plugin_Handled;
    }

    if (g_DB == null)
    {
        PrintStorePhrase(client, "%T", "Store DB Not Ready", client);
        return Plugin_Handled;
    }

    ShowMarketMenu(client);
    return Plugin_Handled;
}

bool CreateMarketplaceListing(int client, const char[] itemId, int price)
{
    if (!IsMarketplaceEnabled() || !IsValidHumanClient(client) || !g_bIsLoaded[client] || g_DB == null || itemId[0] == '\0')
    {
        return false;
    }

    int minPrice = GetMarketplaceMinPrice();
    int maxPrice = GetMarketplaceMaxPrice();
    if (price < minPrice || (maxPrice > 0 && price > maxPrice))
    {
        PrintStorePhrase(client, "%T", "Market Price Invalid", client, minPrice, maxPrice);
        return false;
    }

    int index = FindInventoryIndexByItemId(client, itemId);
    if (index == -1)
    {
        PrintStorePhrase(client, "%T", "Item Not Owned", client);
        return false;
    }

    InventoryItem inv;
    g_hInventory[client].GetArray(index, inv, sizeof(InventoryItem));
    if (view_as<bool>(inv.is_equipped))
    {
        PrintStorePhrase(client, "%T", "Market Item Equipped", client);
        return false;
    }

    // Rentals are time-limited and cannot be listed on the marketplace.
    if (inv.expires_at > 0)
    {
        PrintStorePhrase(client, "%T", "Rental Not Transferable", client);
        return false;
    }

    char steamid[32], safeSteamId[64], safeItemId[64], query[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));
    int now = GetTime();
    int expiresAt = now + (GetMarketplaceListingHours() * 3600);
    int feePercent = GetMarketplaceFeePercent();

    if (!BeginLockedStoreTransaction("CreateMarketplaceListing"))
    {
        PrintStorePhrase(client, "%T", "Market Listing Failed", client);
        return false;
    }

    Format(query, sizeof(query),
        "SELECT id FROM store_market_listings WHERE seller_steamid = '%s' AND item_id = '%s' AND sold_at = 0 AND cancelled_at = 0 AND expires_at > %d LIMIT 1",
        safeSteamId, safeItemId, now);

    DBResultSet activeResults = SQL_Query(g_DB, query);
    if (activeResults == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("CreateMarketplaceListing", error);
        RollbackLockedStoreTransaction("CreateMarketplaceListing");
        PrintStorePhrase(client, "%T", "Market Listing Failed", client);
        return false;
    }

    bool alreadyListed = activeResults.FetchRow();
    delete activeResults;
    if (alreadyListed)
    {
        RollbackLockedStoreTransaction("CreateMarketplaceListing");
        PrintStorePhrase(client, "%T", "Market Item Listed Already", client);
        return false;
    }

    if (!TryAcquireMarketplaceListingLock(safeSteamId, safeItemId, now))
    {
        RollbackLockedStoreTransaction("CreateMarketplaceListing");
        PrintStorePhrase(client, "%T", "Market Item Listed Already", client);
        return false;
    }

    Format(query, sizeof(query),
        "INSERT INTO store_market_listings (seller_steamid, item_id, price, fee_percent, created_at, expires_at, sold_to, sold_at, cancelled_at) VALUES ('%s', '%s', %d, %d, %d, %d, '', 0, 0)",
        safeSteamId, safeItemId, price, feePercent, now, expiresAt);

    if (!ExecuteLockedStoreQuery("CreateMarketplaceListing", query, 1))
    {
        RollbackLockedStoreTransaction("CreateMarketplaceListing");
        PrintStorePhrase(client, "%T", "Market Listing Failed", client);
        return false;
    }

    if (!CommitLockedStoreTransaction("CreateMarketplaceListing"))
    {
        PrintStorePhrase(client, "%T", "Market Listing Failed", client);
        return false;
    }

    StoreItem item;
    FindStoreItemById(itemId, item);
    char priceText[32];
    FormatCreditsAmount(client, price, priceText, sizeof(priceText));
    PrintStorePhrase(client, "%T", "Market Listing Created", client, item.name, priceText);
    LogAuditEvent(client, client, "market_list", itemId, price, "");
    return true;
}

bool GetMarketplaceListingById(int listingId, char[] sellerSteamId, int sellerSteamMax, char[] sellerName, int sellerNameMax, char[] itemId, int itemIdMax, int &price, int &feePercent, int &createdAt, int &expiresAt, int &soldAt, int &cancelledAt, char[] soldTo, int soldToMax)
{
    sellerSteamId[0] = '\0';
    sellerName[0] = '\0';
    itemId[0] = '\0';
    soldTo[0] = '\0';
    price = 0;
    feePercent = 0;
    createdAt = 0;
    expiresAt = 0;
    soldAt = 0;
    cancelledAt = 0;

    if (g_DB == null || listingId <= 0)
    {
        return false;
    }

    char query[512];
    Format(query, sizeof(query),
        "SELECT l.seller_steamid, p.name, l.item_id, l.price, l.fee_percent, l.created_at, l.expires_at, l.sold_at, l.cancelled_at, l.sold_to "
        ... "FROM store_market_listings l LEFT JOIN store_players p ON l.seller_steamid = p.steamid WHERE l.id = %d",
        listingId);

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("GetMarketplaceListingById", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }

    bool found = false;
    if (results.FetchRow())
    {
        results.FetchString(0, sellerSteamId, sellerSteamMax);
        results.FetchString(1, sellerName, sellerNameMax);
        results.FetchString(2, itemId, itemIdMax);
        price = results.FetchInt(3);
        feePercent = results.FetchInt(4);
        createdAt = results.FetchInt(5);
        expiresAt = results.FetchInt(6);
        soldAt = results.FetchInt(7);
        cancelledAt = results.FetchInt(8);
        results.FetchString(9, soldTo, soldToMax);
        if (sellerName[0] == '\0')
        {
            strcopy(sellerName, sellerNameMax, sellerSteamId);
        }
        found = true;
    }

    delete results;
    SQL_UnlockDatabase(g_DB);
    return found;
}

bool ExecuteMarketplacePurchase(int buyer, int listingId)
{
    if (!IsMarketplaceEnabled() || !IsValidHumanClient(buyer) || !g_bIsLoaded[buyer] || g_DB == null || listingId <= 0)
    {
        return false;
    }

    char buyerSteamId[32], safeBuyerSteamId[64];
    if (!GetClientSteamIdSafe(buyer, buyerSteamId, sizeof(buyerSteamId)))
    {
        return false;
    }

    EscapeStringSafe(buyerSteamId, safeBuyerSteamId, sizeof(safeBuyerSteamId));

    if (!BeginLockedStoreTransaction("ExecuteMarketplacePurchase"))
    {
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    char query[768], sellerSteamId[32], sellerName[64], itemId[32], soldTo[32];
    int price = 0, feePercent = 0, expiresAt = 0, soldAt = 0, cancelledAt = 0;

    Format(query, sizeof(query),
        "SELECT l.seller_steamid, p.name, l.item_id, l.price, l.fee_percent, l.created_at, l.expires_at, l.sold_at, l.cancelled_at, l.sold_to "
        ... "FROM store_market_listings l LEFT JOIN store_players p ON l.seller_steamid = p.steamid WHERE l.id = %d",
        listingId);
    DBResultSet listingResults = SQL_Query(g_DB, query);
    if (listingResults == null || !listingResults.FetchRow())
    {
        if (listingResults != null)
        {
            delete listingResults;
        }
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    listingResults.FetchString(0, sellerSteamId, sizeof(sellerSteamId));
    listingResults.FetchString(1, sellerName, sizeof(sellerName));
    listingResults.FetchString(2, itemId, sizeof(itemId));
    price = listingResults.FetchInt(3);
    feePercent = listingResults.FetchInt(4);
    expiresAt = listingResults.FetchInt(6);
    soldAt = listingResults.FetchInt(7);
    cancelledAt = listingResults.FetchInt(8);
    listingResults.FetchString(9, soldTo, sizeof(soldTo));
    delete listingResults;

    if (sellerSteamId[0] == '\0' || itemId[0] == '\0' || soldAt > 0 || cancelledAt > 0 || expiresAt <= GetTime())
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    if (StrEqual(sellerSteamId, buyerSteamId))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Own", buyer);
        return false;
    }

    // The marketplace must honour the same access model as buying, gifting and
    // trading: without this a player could acquire a flag-restricted item they
    // are not allowed to own (and could never equip) by purchasing a listing.
    StoreItem listedItem;
    if (FindStoreItemById(itemId, listedItem) && !HasAccess(buyer, listedItem.flag))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "No Access Item", buyer);
        return false;
    }

    if (g_iCredits[buyer] < price)
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy No Credits", buyer);
        return false;
    }

    char safeSellerSteamId[64], safeItemId[64];
    EscapeStringSafe(sellerSteamId, safeSellerSteamId, sizeof(safeSellerSteamId));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));

    Format(query, sizeof(query),
        "SELECT COUNT(*) FROM store_inventory WHERE steamid = '%s' AND item_id = '%s'",
        safeSellerSteamId, safeItemId);
    DBResultSet sellerInvResults = SQL_Query(g_DB, query);
    if (sellerInvResults == null || !sellerInvResults.FetchRow() || sellerInvResults.FetchInt(0) <= 0)
    {
        if (sellerInvResults != null)
        {
            delete sellerInvResults;
        }
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }
    delete sellerInvResults;

    Format(query, sizeof(query),
        "SELECT COUNT(*) FROM store_inventory WHERE steamid = '%s' AND item_id = '%s'",
        safeBuyerSteamId, safeItemId);
    DBResultSet buyerInvResults = SQL_Query(g_DB, query);
    if (buyerInvResults == null || !buyerInvResults.FetchRow() || buyerInvResults.FetchInt(0) > 0)
    {
        if (buyerInvResults != null)
        {
            delete buyerInvResults;
        }
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }
    delete buyerInvResults;

    int sellerClient = GetOnlineClientBySteamId(sellerSteamId);
    int sellerCredits = 0;
    if (sellerClient > 0 && g_bIsLoaded[sellerClient])
    {
        sellerCredits = g_iCredits[sellerClient];
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT credits FROM store_players WHERE steamid = '%s'",
            safeSellerSteamId);
        DBResultSet sellerCreditResults = SQL_Query(g_DB, query);
        if (sellerCreditResults == null || !sellerCreditResults.FetchRow())
        {
            if (sellerCreditResults != null)
            {
                delete sellerCreditResults;
            }
            RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
            PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
            return false;
        }
        sellerCredits = sellerCreditResults.FetchInt(0);
        delete sellerCreditResults;
    }

    int feeAmount = RoundToFloor(float(price * feePercent) / 100.0);
    int sellerNet = price - feeAmount;
    int buyerNewCredits = g_iCredits[buyer] - price;

    // Pushing the seller past STORE_MAX_CREDITS would make TryComputeCreditBalance
    // reject every later delta for that account, positive and negative alike,
    // locking them out of the entire economy until repaired by hand.
    int sellerNewCredits = 0;
    if (!TryComputeCreditBalance(sellerCredits, sellerNet, sellerNewCredits))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    char buyerPlayerQuery[512];
    if (!BuildPlayerUpsertQueryForCredits(buyer, buyerNewCredits, buyerPlayerQuery, sizeof(buyerPlayerQuery)))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    Format(query, sizeof(query),
        "UPDATE store_market_listings SET sold_to = '%s', sold_at = %d WHERE id = %d AND sold_at = 0 AND cancelled_at = 0",
        safeBuyerSteamId, GetTime(), listingId);
    if (!ExecuteLockedStoreQuery("ExecuteMarketplacePurchase", query, 1))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    Format(query, sizeof(query),
        "UPDATE store_inventory SET steamid = '%s', is_equipped = 0 WHERE steamid = '%s' AND item_id = '%s'",
        safeBuyerSteamId, safeSellerSteamId, safeItemId);
    if (!ExecuteLockedStoreQuery("ExecuteMarketplacePurchase", query, 1))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    if (!ExecuteLockedStoreQuery("ExecuteMarketplacePurchase", buyerPlayerQuery))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    Format(query, sizeof(query), "UPDATE store_players SET credits = %d WHERE steamid = '%s'", sellerNewCredits, safeSellerSteamId);
    if (!ExecuteLockedStoreQuery("ExecuteMarketplacePurchase", query, 1, sellerNewCredits == sellerCredits))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    Format(query, sizeof(query),
        "INSERT INTO store_market_sales (listing_id, seller_steamid, buyer_steamid, item_id, price, fee_amount, created_at) VALUES (%d, '%s', '%s', '%s', %d, %d, %d)",
        listingId, safeSellerSteamId, safeBuyerSteamId, safeItemId, price, feeAmount, GetTime());
    if (!ExecuteLockedStoreQuery("ExecuteMarketplacePurchase", query, 1))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    if (!ReleaseMarketplaceListingLock(safeSellerSteamId, safeItemId))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    if (!CommitLockedStoreTransaction("ExecuteMarketplacePurchase"))
    {
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    g_iCredits[buyer] = buyerNewCredits;
    ReportCreditsChanged(buyer, -price, "market_buy", false, true);
    SyncMarketplaceTransferInMemory(sellerSteamId, buyer, itemId, sellerNet);
    UpdatePlayerStat(buyer, "purchases_total", 1);

    StoreItem item;
    FindStoreItemById(itemId, item);
    char priceText[32];
    FormatCreditsAmount(buyer, price, priceText, sizeof(priceText));
    PrintStorePhrase(buyer, "%T", "Market Listing Bought", buyer, item.name, priceText, sellerName);

    LogAuditEvent(buyer, buyer, "market_buy", itemId, -price, sellerSteamId);
    if (sellerClient > 0)
    {
        LogAuditEvent(0, sellerClient, "market_sale", itemId, sellerNet, buyerSteamId);
    }
    else
    {
        LogAuditEventBySteamId(0, sellerSteamId, sellerName, "market_sale", itemId, sellerNet, buyerSteamId);
    }

    if (sellerClient > 0)
    {
        char sellerNetText[32];
        FormatCreditsAmount(sellerClient, sellerNet, sellerNetText, sizeof(sellerNetText));
        char safeBuyerName[MAX_NAME_LENGTH];
        GetSafeClientName(buyer, safeBuyerName, sizeof(safeBuyerName));
        PrintStorePhrase(sellerClient, "%T", "Market Listing Sold Seller", sellerClient, item.name, sellerNetText, safeBuyerName);
        UpdatePlayerStat(sellerClient, "sales_total", 1);
    }
    else
    {
        LogCreditLedgerBySteamId(sellerSteamId, sellerNewCredits, sellerNet, "market_sale");
        TrackEconomyStatsBySteamId(sellerSteamId, sellerNet);
        UpdatePlayerStatBySteamId(sellerSteamId, "sales_total", 1);
    }

    return true;
}

bool CancelMarketplaceListing(int client, int listingId, bool notify = true)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_DB == null || listingId <= 0)
    {
        return false;
    }

    char steamid[32], safeSteamId[64], query[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));

    if (!BeginLockedStoreTransaction("CancelMarketplaceListing"))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Market Cancel Failed", client);
        }
        return false;
    }

    Format(query, sizeof(query),
        "SELECT item_id FROM store_market_listings WHERE id = %d AND seller_steamid = '%s' AND sold_at = 0 AND cancelled_at = 0 LIMIT 1",
        listingId, safeSteamId);
    DBResultSet results = SQL_Query(g_DB, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("CancelMarketplaceListing", error);
        RollbackLockedStoreTransaction("CancelMarketplaceListing");
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Market Cancel Failed", client);
        }
        return false;
    }

    char itemId[32], safeItemId[64];
    if (!results.FetchRow())
    {
        delete results;
        RollbackLockedStoreTransaction("CancelMarketplaceListing");
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Market Cancel Failed", client);
        }
        return false;
    }

    results.FetchString(0, itemId, sizeof(itemId));
    delete results;
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));

    Format(query, sizeof(query),
        "UPDATE store_market_listings SET cancelled_at = %d WHERE id = %d AND seller_steamid = '%s' AND sold_at = 0 AND cancelled_at = 0",
        GetTime(), listingId, safeSteamId);

    if (!ExecuteLockedStoreQuery("CancelMarketplaceListing", query, 1))
    {
        RollbackLockedStoreTransaction("CancelMarketplaceListing");
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Market Cancel Failed", client);
        }
        return false;
    }

    if (!ReleaseMarketplaceListingLock(safeSteamId, safeItemId))
    {
        RollbackLockedStoreTransaction("CancelMarketplaceListing");
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Market Cancel Failed", client);
        }
        return false;
    }

    if (!CommitLockedStoreTransaction("CancelMarketplaceListing"))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Market Cancel Failed", client);
        }
        return false;
    }

    if (notify)
    {
        PrintStorePhrase(client, "%T", "Market Listing Cancelled", client);
    }

    char listingText[32];
    IntToString(listingId, listingText, sizeof(listingText));
    LogAuditEvent(client, client, "market_cancel", "", 0, listingText);
    return true;
}

void ShowMarketMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Market);
    SetMenuTitlePhrase(menu, client, "Market Menu Title");
    AddMenuItemPhrase(menu, "browse", client, "Market Menu Browse");
    AddMenuItemPhrase(menu, "sell", client, "Market Menu Sell");
    AddMenuItemPhrase(menu, "mine", client, "Market Menu My Listings");
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Market(Menu menu, MenuAction action, int param1, int param2)
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
        if (StrEqual(info, "browse"))
        {
            ShowMarketplaceBrowseMenu(param1);
        }
        else if (StrEqual(info, "sell"))
        {
            ShowMarketplaceSellMenu(param1);
        }
        else if (StrEqual(info, "mine"))
        {
            ShowMarketplaceOwnListingsMenu(param1);
        }
    }
    return 0;
}

void ShowMarketplaceSellMenu(int client)
{
    Menu menu = new Menu(MenuHandler_MarketSell);
    SetMenuTitlePhrase(menu, client, "Market Sell Menu Title");

    bool added = false;
    InventoryItem inv;
    StoreItem item;
    StringMap listed = GetActiveMarketplaceListingSet(client);
    int ignored = 0;
    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (view_as<bool>(inv.is_equipped))
        {
            continue;
        }

        // Rentals cannot be listed (CreateMarketplaceListing rejects them), so
        // offering them here only wastes the player's price prompt.
        if (inv.expires_at > 0)
        {
            continue;
        }

        if (!FindStoreItemById(inv.item_id, item))
        {
            continue;
        }

        if (listed.GetValue(inv.item_id, ignored))
        {
            continue;
        }

        char display[128], suggestedPrice[32];
        FormatCreditsAmount(client, item.price, suggestedPrice, sizeof(suggestedPrice));
        Format(display, sizeof(display), "%s [%s]", item.name, suggestedPrice);
        menu.AddItem(item.id, display);
        added = true;
    }

    delete listed;

    if (!added)
    {
        AddMenuItemPhrase(menu, "empty", client, "Market Sell Empty", ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MarketSell(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowMarketMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char itemId[32];
        menu.GetItem(param2, itemId, sizeof(itemId));
        strcopy(g_szPendingMarketItem[param1], sizeof(g_szPendingMarketItem[]), itemId);
        g_bAwaitingMarketPrice[param1] = true;
        PrintStorePhrase(param1, "%T", "Market Enter Price", param1, GetMarketplaceMinPrice(), GetMarketplaceMaxPrice());
    }
    return 0;
}

void ShowMarketplaceBrowseMenu(int client)
{
    Menu menu = new Menu(MenuHandler_MarketBrowse);
    SetMenuTitlePhrase(menu, client, "Market Browse Menu Title");

    char query[512];
    Format(query, sizeof(query),
        "SELECT l.id, l.item_id, p.name, l.seller_steamid, l.price FROM store_market_listings l "
        ... "LEFT JOIN store_players p ON l.seller_steamid = p.steamid "
        ... "WHERE l.sold_at = 0 AND l.cancelled_at = 0 AND l.expires_at > %d ORDER BY l.created_at DESC LIMIT 100",
        GetTime());

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    bool added = false;
    if (results != null)
    {
        StoreItem item;
        char itemId[32], sellerName[64], sellerSteamId[32], display[192], info[16], priceText[32];
        int listingId = 0;
        while (results.FetchRow())
        {
            listingId = results.FetchInt(0);
            results.FetchString(1, itemId, sizeof(itemId));
            results.FetchString(2, sellerName, sizeof(sellerName));
            results.FetchString(3, sellerSteamId, sizeof(sellerSteamId));
            int price = results.FetchInt(4);

            if (!FindStoreItemById(itemId, item))
            {
                continue;
            }

            if (sellerName[0] == '\0')
            {
                strcopy(sellerName, sizeof(sellerName), sellerSteamId);
            }

            FormatCreditsAmount(client, price, priceText, sizeof(priceText));
            Format(display, sizeof(display), "%T", "Market Listing Entry", client, item.name, sellerName, priceText);
            IntToString(listingId, info, sizeof(info));
            menu.AddItem(info, display);
            added = true;
        }
        delete results;
    }
    else
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("ShowMarketplaceBrowseMenu", error);
    }
    SQL_UnlockDatabase(g_DB);

    if (!added)
    {
        AddMenuItemPhrase(menu, "empty", client, "Market Browse Empty", ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MarketBrowse(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowMarketMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        ShowMarketplaceListingDetails(param1, StringToInt(info), false);
    }
    return 0;
}

void ShowMarketplaceOwnListingsMenu(int client)
{
    Menu menu = new Menu(MenuHandler_MarketOwnListings);
    SetMenuTitlePhrase(menu, client, "Market My Listings Title");

    char steamid[32], safeSteamId[64], query[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        delete menu;
        return;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    Format(query, sizeof(query),
        "SELECT id, item_id, price FROM store_market_listings WHERE seller_steamid = '%s' AND sold_at = 0 AND cancelled_at = 0 AND expires_at > %d ORDER BY created_at DESC LIMIT 100",
        safeSteamId, GetTime());

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    bool added = false;
    if (results != null)
    {
        StoreItem item;
        char itemId[32], display[160], info[16], priceText[32];
        while (results.FetchRow())
        {
            int listingId = results.FetchInt(0);
            results.FetchString(1, itemId, sizeof(itemId));
            int price = results.FetchInt(2);
            if (!FindStoreItemById(itemId, item))
            {
                continue;
            }

            FormatCreditsAmount(client, price, priceText, sizeof(priceText));
            Format(display, sizeof(display), "%T", "Market My Listing Entry", client, item.name, priceText);
            IntToString(listingId, info, sizeof(info));
            menu.AddItem(info, display);
            added = true;
        }
        delete results;
    }
    else
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("ShowMarketplaceOwnListingsMenu", error);
    }
    SQL_UnlockDatabase(g_DB);

    if (!added)
    {
        AddMenuItemPhrase(menu, "empty", client, "Market My Listings Empty", ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MarketOwnListings(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowMarketMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        ShowMarketplaceListingDetails(param1, StringToInt(info), true);
    }
    return 0;
}

void ShowMarketplaceListingDetails(int client, int listingId, bool ownListing)
{
    char sellerSteamId[32], sellerName[64], itemId[32], soldTo[32];
    int price = 0, feePercent = 0, createdAt = 0, expiresAt = 0, soldAt = 0, cancelledAt = 0;
    if (!GetMarketplaceListingById(listingId, sellerSteamId, sizeof(sellerSteamId), sellerName, sizeof(sellerName), itemId, sizeof(itemId), price, feePercent, createdAt, expiresAt, soldAt, cancelledAt, soldTo, sizeof(soldTo)))
    {
        ShowMarketMenu(client);
        return;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        ShowMarketMenu(client);
        return;
    }

    Menu menu = new Menu(MenuHandler_MarketListingDetails);
    char title[192], priceText[32], display[192], whenText[64], info[32];
    Format(title, sizeof(title), "%T", "Market Listing Title", client, item.name);
    menu.SetTitle(title);

    Format(display, sizeof(display), "%T", "Market Listing Seller", client, sellerName);
    AddMenuItemText(menu, "seller", display, ITEMDRAW_DISABLED);

    FormatCreditsAmount(client, price, priceText, sizeof(priceText));
    Format(display, sizeof(display), "%T", "Market Listing Price", client, priceText);
    AddMenuItemText(menu, "price", display, ITEMDRAW_DISABLED);

    int feeAmount = RoundToFloor(float(price * feePercent) / 100.0);
    int netAmount = price - feeAmount;
    FormatCreditsAmount(client, feeAmount, priceText, sizeof(priceText));
    Format(display, sizeof(display), "%T", "Market Listing Fee", client, priceText, feePercent);
    AddMenuItemText(menu, "fee", display, ITEMDRAW_DISABLED);

    FormatCreditsAmount(client, netAmount, priceText, sizeof(priceText));
    Format(display, sizeof(display), "%T", "Market Listing Net", client, priceText);
    AddMenuItemText(menu, "net", display, ITEMDRAW_DISABLED);

    FormatTime(whenText, sizeof(whenText), "%Y-%m-%d %H:%M", expiresAt);
    Format(display, sizeof(display), "%T", "Market Listing Expires", client, whenText);
    AddMenuItemText(menu, "expires", display, ITEMDRAW_DISABLED);

    IntToString(listingId, info, sizeof(info));
    if (ownListing)
    {
        AddMenuItemPhrase(menu, info, client, "Market Listing Cancel");
    }
    else
    {
        AddMenuItemPhrase(menu, info, client, "Market Listing Buy");
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MarketListingDetails(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowMarketMenu(param1);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        int listingId = StringToInt(info);

        char sellerSteamId[32], sellerName[64], itemId[32], soldTo[32], mySteamId[32];
        int price = 0, feePercent = 0, createdAt = 0, expiresAt = 0, soldAt = 0, cancelledAt = 0;
        if (!GetMarketplaceListingById(listingId, sellerSteamId, sizeof(sellerSteamId), sellerName, sizeof(sellerName), itemId, sizeof(itemId), price, feePercent, createdAt, expiresAt, soldAt, cancelledAt, soldTo, sizeof(soldTo)))
        {
            ShowMarketMenu(param1);
            return 0;
        }

        bool ownListing = GetClientSteamIdSafe(param1, mySteamId, sizeof(mySteamId)) && StrEqual(mySteamId, sellerSteamId);
        if (ownListing)
        {
            CancelMarketplaceListing(param1, listingId, true);
            ShowMarketplaceOwnListingsMenu(param1);
        }
        else
        {
            ExecuteMarketplacePurchase(param1, listingId);
            ShowMarketplaceBrowseMenu(param1);
        }
    }
    return 0;
}

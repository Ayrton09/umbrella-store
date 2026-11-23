// Umbrella Store core: Public API natives (umbrella_store.inc).
// Included by store_core.sp.

public any Native_US_Casino_Register(Handle plugin, int numParams)
{
    char id[32], title[64], command[64];
    GetNativeString(1, id, sizeof(id));
    GetNativeString(2, title, sizeof(title));
    GetNativeString(3, command, sizeof(command));
    return CasinoRegisterEntry(id, title, command);
}

public any Native_US_Casino_Unregister(Handle plugin, int numParams)
{
    char id[32];
    GetNativeString(1, id, sizeof(id));
    return CasinoUnregisterEntry(id);
}

public any Native_US_OpenCasinoMenu(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || !IsStoreEnabled())
    {
        return false;
    }

    ShowCasinoMenu(client);
    return true;
}

public any Native_US_IsLoaded(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return (client >= 1 && client <= MaxClients && g_bIsLoaded[client] && IsStoreEnabled());
}

public any Native_US_IsEnabled(Handle plugin, int numParams)
{
    return IsStoreEnabled();
}

public any Native_US_GetCredits(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients)
    {
        return 0;
    }
    return g_iCredits[client];
}

public any Native_US_SetCredits(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int amount = GetNativeCell(2);
    if (!IsStoreEnabled() || client < 1 || client > MaxClients || !g_bIsLoaded[client])
    {
        return false;
    }
    if (amount < 0)
    {
        return false;
    }
    return SetCreditsAtomic(client, amount, "api_set", false);
}

public any Native_US_AddCredits(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int amount = GetNativeCell(2);
    bool notify = (numParams >= 3) ? view_as<bool>(GetNativeCell(3)) : false;
    if (!IsStoreEnabled() || client < 1 || client > MaxClients || !g_bIsLoaded[client] || amount <= 0)
    {
        return false;
    }
    return ApplyCreditDeltasAtomic(client, amount, "api", 0, 0, "", notify, "");
}

public any Native_US_TakeCredits(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int amount = GetNativeCell(2);
    if (!IsStoreEnabled() || client < 1 || client > MaxClients || !g_bIsLoaded[client] || amount <= 0 || g_iCredits[client] < amount)
    {
        return false;
    }
    return ApplyCreditDeltasAtomic(client, -amount, "api_take", 0, 0, "", false, "");
}

public any Native_US_ApplyCreditDelta(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int delta = GetNativeCell(2);
    char reason[64];
    GetNativeString(3, reason, sizeof(reason));
    bool notify = (numParams >= 4) ? view_as<bool>(GetNativeCell(4)) : false;

    if (reason[0] == '\0')
    {
        strcopy(reason, sizeof(reason), "api_delta");
    }

    if (!IsStoreEnabled() || client < 1 || client > MaxClients || !g_bIsLoaded[client] || delta == 0)
    {
        return false;
    }

    return ApplyCreditDeltasAtomic(client, delta, reason, 0, 0, "", notify, "");
}

public any Native_US_ApplyCreditDeltas(Handle plugin, int numParams)
{
    int clientA = GetNativeCell(1);
    int deltaA = GetNativeCell(2);
    int clientB = GetNativeCell(4);
    int deltaB = GetNativeCell(5);
    bool notify = (numParams >= 7) ? view_as<bool>(GetNativeCell(7)) : false;

    char reasonA[64], reasonB[64];
    GetNativeString(3, reasonA, sizeof(reasonA));
    GetNativeString(6, reasonB, sizeof(reasonB));
    if (reasonA[0] == '\0')
    {
        strcopy(reasonA, sizeof(reasonA), "api_delta");
    }
    if (reasonB[0] == '\0')
    {
        strcopy(reasonB, sizeof(reasonB), "api_delta");
    }

    if (!IsStoreEnabled() || (deltaA == 0 && deltaB == 0))
    {
        return false;
    }

    return ApplyCreditDeltasAtomic(clientA, deltaA, reasonA, clientB, deltaB, reasonB, notify, "");
}

public any Native_US_HasItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64];
    GetNativeString(2, itemId, sizeof(itemId));
    if (!IsStoreEnabled() || client < 1 || client > MaxClients || !g_bIsLoaded[client])
    {
        return false;
    }
    return PlayerOwnsItem(client, itemId);
}

public any Native_US_GiveItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64];
    GetNativeString(2, itemId, sizeof(itemId));
    bool equip = (numParams >= 3) ? view_as<bool>(GetNativeCell(3)) : false;
    return GiveItemToClient(client, itemId, equip, true);
}

public any Native_US_RemoveItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64];
    GetNativeString(2, itemId, sizeof(itemId));
    return RemoveItemFromClient(client, itemId, true);
}

public any Native_US_GetApiVersion(Handle plugin, int numParams)
{
    return STORE_API_VERSION;
}

public any Native_US_OpenStoreMenu(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || !EnsureStoreEnabledForClient(client))
    {
        return false;
    }

    ShowStoreMainMenu(client);
    return true;
}

public any Native_US_RegisterMenuSection(Handle plugin, int numParams)
{
    char id[32], title[64], command[64];
    int sortOrder = (numParams >= 4) ? GetNativeCell(4) : 0;
    GetNativeString(1, id, sizeof(id));
    GetNativeString(2, title, sizeof(title));
    GetNativeString(3, command, sizeof(command));
    return RegisterMenuSectionEntry(id, title, command, sortOrder);
}

public any Native_US_UnregisterMenuSection(Handle plugin, int numParams)
{
    char id[32];
    GetNativeString(1, id, sizeof(id));
    return UnregisterMenuSectionEntry(id);
}

public any Native_US_GetItemCount(Handle plugin, int numParams)
{
    return (g_aItems != null) ? g_aItems.Length : 0;
}

public any Native_US_GetItemIdByIndex(Handle plugin, int numParams)
{
    int index = GetNativeCell(1);
    int maxlen = GetNativeCell(3);
    if (g_aItems == null || index < 0 || index >= g_aItems.Length || maxlen <= 0)
    {
        return false;
    }

    StoreItem item;
    g_aItems.GetArray(index, item, sizeof(StoreItem));
    SetNativeString(2, item.id, maxlen, true);
    return true;
}

public any Native_US_GetItemInfo(Handle plugin, int numParams)
{
    char itemId[64], category[32];
    GetNativeString(1, itemId, sizeof(itemId));

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        return false;
    }

    GetItemCategory(item, category, sizeof(category));
    SetNativeString(2, item.name, GetNativeCell(3), true);
    SetNativeString(4, item.type, GetNativeCell(5), true);
    SetNativeCellRef(6, item.price);
    SetNativeCellRef(7, item.team);
    SetNativeString(8, category, GetNativeCell(9), true);
    return true;
}

public any Native_US_GetItemType(Handle plugin, int numParams)
{
    char itemId[64];
    GetNativeString(1, itemId, sizeof(itemId));

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        return false;
    }

    SetNativeString(2, item.type, GetNativeCell(3), true);
    return true;
}

public any Native_US_GetItemPrice(Handle plugin, int numParams)
{
    char itemId[64];
    GetNativeString(1, itemId, sizeof(itemId));

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        return -1;
    }

    return item.price;
}

public any Native_US_GetEquippedItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char type[32], itemId[32];
    GetNativeString(2, type, sizeof(type));

    if (!IsStoreEnabled())
    {
        return false;
    }

    if (!GetEquippedItemByType(client, type, itemId, sizeof(itemId)))
    {
        return false;
    }

    SetNativeString(3, itemId, GetNativeCell(4), true);
    return true;
}

public any Native_US_IsItemEquipped(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64];
    GetNativeString(2, itemId, sizeof(itemId));

    if (!IsStoreEnabled() || client < 1 || client > MaxClients || !g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        return false;
    }

    int index = FindInventoryIndexByItemId(client, itemId);
    if (index == -1)
    {
        return false;
    }

    InventoryItem inv;
    g_hInventory[client].GetArray(index, inv, sizeof(InventoryItem));
    return view_as<bool>(inv.is_equipped);
}

public any Native_US_GetEquippedItemCount(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!IsStoreEnabled() || client < 1 || client > MaxClients || !g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        return 0;
    }

    int count = 0;
    InventoryItem inv;
    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (inv.is_equipped)
        {
            count++;
        }
    }

    return count;
}

public any Native_US_GetEquippedItemIdByIndex(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int targetIndex = GetNativeCell(2);
    int maxlen = GetNativeCell(4);

    if (!IsStoreEnabled() || client < 1 || client > MaxClients || targetIndex < 0 || maxlen <= 0 || !g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        return false;
    }

    int count = 0;
    InventoryItem inv;
    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (!inv.is_equipped)
        {
            continue;
        }

        if (count == targetIndex)
        {
            SetNativeString(3, inv.item_id, maxlen, true);
            return true;
        }

        count++;
    }

    return false;
}

public any Native_US_CanPurchaseItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64], reason[64];
    GetNativeString(2, itemId, sizeof(itemId));

    bool result = CanPurchaseItemEx(client, itemId, reason, sizeof(reason));
    SetNativeString(3, reason, GetNativeCell(4), true);
    return result;
}

public any Native_US_TryPurchaseItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64];
    bool equipAfterPurchase = (numParams >= 3) ? view_as<bool>(GetNativeCell(3)) : false;
    bool notify = (numParams >= 4) ? view_as<bool>(GetNativeCell(4)) : true;
    GetNativeString(2, itemId, sizeof(itemId));
    return BuyItem(client, itemId, equipAfterPurchase, notify);
}

public any Native_US_CanEquipItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64], reason[64];
    GetNativeString(2, itemId, sizeof(itemId));

    bool result = CanEquipItemEx(client, itemId, reason, sizeof(reason), false);
    SetNativeString(3, reason, GetNativeCell(4), true);
    return result;
}

public any Native_US_TryEquipItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64];
    bool notify = (numParams >= 3) ? view_as<bool>(GetNativeCell(3)) : true;
    GetNativeString(2, itemId, sizeof(itemId));
    return SetItemEquipped(client, itemId, true, notify, true);
}

public any Native_US_TryUnequipItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64];
    bool notify = (numParams >= 3) ? view_as<bool>(GetNativeCell(3)) : true;
    GetNativeString(2, itemId, sizeof(itemId));
    return SetItemEquipped(client, itemId, false, notify, true);
}

public any Native_US_SetItemEquipped(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64];
    bool equipped = view_as<bool>(GetNativeCell(3));
    bool notify = (numParams >= 4) ? view_as<bool>(GetNativeCell(4)) : true;
    GetNativeString(2, itemId, sizeof(itemId));
    return SetItemEquipped(client, itemId, equipped, notify, false);
}

public any Native_US_CanUseItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64], reason[64];
    GetNativeString(2, itemId, sizeof(itemId));
    SetReason(reason, sizeof(reason), "");

    if (!IsValidHumanClient(client))
    {
        SetReason(reason, sizeof(reason), "invalid_client");
        SetNativeString(3, reason, GetNativeCell(4), true);
        return false;
    }

    if (!EnsureStoreEnabledForClient(client, false))
    {
        SetReason(reason, sizeof(reason), "store_disabled");
        SetNativeString(3, reason, GetNativeCell(4), true);
        return false;
    }

    if (!g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        SetReason(reason, sizeof(reason), "client_not_loaded");
        SetNativeString(3, reason, GetNativeCell(4), true);
        return false;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        SetReason(reason, sizeof(reason), "item_not_found");
        SetNativeString(3, reason, GetNativeCell(4), true);
        return false;
    }

    if (!IsItemActiveForNow(item))
    {
        SetReason(reason, sizeof(reason), "item_unavailable");
        SetNativeString(3, reason, GetNativeCell(4), true);
        return false;
    }

    if (!HasAccess(client, item.flag))
    {
        SetReason(reason, sizeof(reason), "no_access");
        SetNativeString(3, reason, GetNativeCell(4), true);
        return false;
    }

    if (item.requires_item[0] != '\0' && !PlayerOwnsItem(client, item.requires_item))
    {
        SetReason(reason, sizeof(reason), "requires_item");
        SetNativeString(3, reason, GetNativeCell(4), true);
        return false;
    }

    SetReason(reason, sizeof(reason), "ok");
    SetNativeString(3, reason, GetNativeCell(4), true);
    return true;
}

public any Native_US_RegisterItemType(Handle plugin, int numParams)
{
    char type[32], category[32];
    bool equippable = (numParams >= 3) ? view_as<bool>(GetNativeCell(3)) : true;
    bool exclusive = (numParams >= 4) ? view_as<bool>(GetNativeCell(4)) : false;
    GetNativeString(1, type, sizeof(type));
    GetNativeString(2, category, sizeof(category));
    return RegisterItemTypeInternal(type, category, equippable, exclusive, false);
}

public any Native_US_UnregisterItemType(Handle plugin, int numParams)
{
    char type[32];
    GetNativeString(1, type, sizeof(type));
    return UnregisterItemTypeInternal(type, false);
}

public any Native_US_GetItemMetadata(Handle plugin, int numParams)
{
    char itemId[64], key[64], value[256];
    GetNativeString(1, itemId, sizeof(itemId));
    GetNativeString(2, key, sizeof(key));

    if (!GetItemMetadataValue(itemId, key, value, sizeof(value)))
    {
        return false;
    }

    SetNativeString(3, value, GetNativeCell(4), true);
    return true;
}

public any Native_US_IsDatabaseReady(Handle plugin, int numParams)
{
    return (g_DB != null && g_bLateDatabaseReady);
}

public any Native_US_GetDatabaseConfig(Handle plugin, int numParams)
{
    char dbConfig[64];
    GetDatabaseConfigName(dbConfig, sizeof(dbConfig));
    SetNativeString(1, dbConfig, GetNativeCell(2), true);
    return (dbConfig[0] != '\0');
}

public any Native_US_IsMySQL(Handle plugin, int numParams)
{
    return g_bIsMySQL;
}

public any Native_US_GetDatabaseHandle(Handle plugin, int numParams)
{
    if (g_DB == null)
    {
        return INVALID_HANDLE;
    }

    return CloneHandle(g_DB, plugin);
}

public any Native_US_DB_Escape(Handle plugin, int numParams)
{
    if (g_DB == null)
    {
        return false;
    }

    // Size the buffers from the caller's actual string instead of truncating it
    // to a fixed 256 bytes: a silently shortened value would be escaped
    // correctly but store something different from what the caller passed.
    int length = 0;
    GetNativeStringLength(1, length);
    if (length < 0)
    {
        return false;
    }

    int inputSize = length + 1;
    int outputSize = (length * 2) + 1;
    char[] input = new char[inputSize];
    char[] output = new char[outputSize];

    GetNativeString(1, input, inputSize);
    if (!g_DB.Escape(input, output, outputSize))
    {
        return false;
    }

    SetNativeString(2, output, GetNativeCell(3), true);
    return true;
}

public any Native_US_DB_EnsureTable(Handle plugin, int numParams)
{
    char tableId[64], mysqlQuery[1024], sqliteQuery[1024];
    GetNativeString(1, tableId, sizeof(tableId));
    GetNativeString(2, mysqlQuery, sizeof(mysqlQuery));
    GetNativeString(3, sqliteQuery, sizeof(sqliteQuery));
    return EnsureSharedTableInternal(tableId, mysqlQuery, sqliteQuery);
}

public any Native_US_ApplyCreditDeltaWithQuery(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int delta = GetNativeCell(2);
    bool notify = (numParams >= 5) ? view_as<bool>(GetNativeCell(5)) : false;

    char reason[64], query[1024];
    GetNativeString(3, reason, sizeof(reason));
    GetNativeString(4, query, sizeof(query));
    TrimString(query);

    if (reason[0] == '\0')
    {
        strcopy(reason, sizeof(reason), "api_delta_query");
    }

    if (!IsStoreEnabled() || client < 1 || client > MaxClients || !g_bIsLoaded[client] || delta == 0 || query[0] == '\0')
    {
        return false;
    }

    return ApplyCreditDeltasAtomic(client, delta, reason, 0, 0, "", notify, query);
}

public any Native_US_RegisterStatKey(Handle plugin, int numParams)
{
    char statKey[64];
    GetNativeString(1, statKey, sizeof(statKey));
    return RegisterStatKeyInternal(statKey);
}

public any Native_US_AddStat(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int amount = (numParams >= 3) ? GetNativeCell(3) : 1;
    char statKey[64];
    GetNativeString(2, statKey, sizeof(statKey));
    if (!IsStoreEnabled())
    {
        return false;
    }
    return UpdatePlayerStat(client, statKey, amount, false);
}

public any Native_US_SetStatMax(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int value = GetNativeCell(3);
    char statKey[64];
    GetNativeString(2, statKey, sizeof(statKey));
    if (!IsStoreEnabled())
    {
        return false;
    }
    return UpdatePlayerStat(client, statKey, value, true);
}

public any Native_US_RegisterQuest(Handle plugin, int numParams)
{
    char questId[64], title[96];
    int goal = GetNativeCell(3);
    int rewardCredits = (numParams >= 4) ? GetNativeCell(4) : 0;
    GetNativeString(1, questId, sizeof(questId));
    GetNativeString(2, title, sizeof(title));
    return RegisterQuestInternal(questId, title, goal, rewardCredits);
}

public any Native_US_RegisterQuestEx(Handle plugin, int numParams)
{
    StoreQuestDefinition definition;
    GetNativeString(1, definition.id, sizeof(definition.id));
    GetNativeString(2, definition.title, sizeof(definition.title));
    definition.goal = GetNativeCell(3);
    definition.reward_credits = (numParams >= 4) ? GetNativeCell(4) : 0;
    if (numParams >= 5)
    {
        GetNativeString(5, definition.reward_item, sizeof(definition.reward_item));
    }
    else
    {
        definition.reward_item[0] = '\0';
    }
    definition.reward_item_equip = (numParams >= 6) ? GetNativeCell(6) : 0;
    if (numParams >= 7)
    {
        GetNativeString(7, definition.category, sizeof(definition.category));
    }
    else
    {
        strcopy(definition.category, sizeof(definition.category), "Quest Category General");
    }
    if (numParams >= 8)
    {
        GetNativeString(8, definition.description, sizeof(definition.description));
    }
    else
    {
        definition.description[0] = '\0';
    }
    definition.repeatable = (numParams >= 9) ? GetNativeCell(9) : 0;
    // 0 means "let RegisterQuestDefinitionInternal decide" (1 when the quest is
    // not repeatable, unlimited when it is). numParams is always 13 here because
    // SourcePawn materialises native defaults at the call site, so this cannot
    // rely on an argument-count fallback.
    definition.max_completions = GetNativeCell(10);
    if (numParams >= 11)
    {
        GetNativeString(11, definition.requires_quest, sizeof(definition.requires_quest));
    }
    else
    {
        definition.requires_quest[0] = '\0';
    }
    definition.starts_at = (numParams >= 12) ? GetNativeCell(12) : 0;
    definition.ends_at = (numParams >= 13) ? GetNativeCell(13) : 0;

    return RegisterQuestDefinitionInternal(definition);
}

public any Native_US_UnregisterQuest(Handle plugin, int numParams)
{
    char questId[64];
    GetNativeString(1, questId, sizeof(questId));
    return UnregisterQuestInternal(questId);
}

public any Native_US_AdvanceQuestProgress(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int amount = (numParams >= 3) ? GetNativeCell(3) : 1;
    char questId[64];
    GetNativeString(2, questId, sizeof(questId));
    if (!IsStoreEnabled())
    {
        return false;
    }
    return UpdateQuestProgressInternal(client, questId, amount, false);
}

public any Native_US_SetQuestProgressMax(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int value = GetNativeCell(3);
    char questId[64];
    GetNativeString(2, questId, sizeof(questId));
    if (!IsStoreEnabled())
    {
        return false;
    }
    return UpdateQuestProgressInternal(client, questId, value, true);
}

public any Native_US_GetQuestProgress(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char questId[64];
    int progress = 0;
    int completedAt = 0;
    int rewardedAt = 0;
    GetNativeString(2, questId, sizeof(questId));

    if (!GetQuestProgressState(client, questId, progress, completedAt, rewardedAt))
    {
        return false;
    }

    SetNativeCellRef(3, progress);
    SetNativeCellRef(4, (rewardedAt > 0) ? 1 : 0);
    return true;
}

public any Native_US_RegisterLeaderboard(Handle plugin, int numParams)
{
    char id[32], title[96], statKey[64], entryPhrase[64];
    int sortOrder = (numParams >= 5) ? GetNativeCell(5) : 0;
    GetNativeString(1, id, sizeof(id));
    GetNativeString(2, title, sizeof(title));
    GetNativeString(3, statKey, sizeof(statKey));
    if (numParams >= 4)
    {
        GetNativeString(4, entryPhrase, sizeof(entryPhrase));
    }
    else
    {
        strcopy(entryPhrase, sizeof(entryPhrase), "Top Profit Entry");
    }

    return RegisterLeaderboardInternal(id, title, statKey, entryPhrase, sortOrder);
}

public any Native_US_UnregisterLeaderboard(Handle plugin, int numParams)
{
    char id[32];
    GetNativeString(1, id, sizeof(id));
    return UnregisterLeaderboardInternal(id);
}

public any Native_US_LogAuditEvent(Handle plugin, int numParams)
{
    int actor = GetNativeCell(1);
    int target = GetNativeCell(2);
    int amount = (numParams >= 5) ? GetNativeCell(5) : 0;
    char action[64], itemId[32], details[192];

    GetNativeString(3, action, sizeof(action));
    if (numParams >= 4)
    {
        GetNativeString(4, itemId, sizeof(itemId));
    }
    else
    {
        itemId[0] = '\0';
    }

    if (numParams >= 6)
    {
        GetNativeString(6, details, sizeof(details));
    }
    else
    {
        details[0] = '\0';
    }

    return LogAuditEvent(actor, target, action, itemId, amount, details);
}

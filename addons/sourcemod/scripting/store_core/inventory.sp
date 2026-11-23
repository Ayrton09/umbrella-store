// Umbrella Store core: Ownership, inventory menus, and item grant/removal.
// Included by store_core.sp.

void InventoryOwnedSet(int client, const char[] itemId, bool owned)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    if (g_mInventoryOwned[client] == null)
    {
        g_mInventoryOwned[client] = new StringMap();
    }

    if (owned)
    {
        g_mInventoryOwned[client].SetValue(itemId, 1);
    }
    else
    {
        g_mInventoryOwned[client].Remove(itemId);
    }
}

int FindInventoryIndexByItemId(int client, const char[] itemId)
{
    if (g_hInventory[client] == null)
    {
        return -1;
    }

    InventoryItem inv;
    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (StrEqual(inv.item_id, itemId))
        {
            return i;
        }
    }

    return -1;
}

bool PlayerOwnsItem(int client, const char[] itemId)
{
    if (client < 1 || client > MaxClients)
    {
        return false;
    }

    if (g_mInventoryOwned[client] != null)
    {
        int value;
        if (g_mInventoryOwned[client].GetValue(itemId, value))
        {
            return true;
        }
    }

    return (FindInventoryIndexByItemId(client, itemId) != -1);
}

bool GiveItemToClient(int client, const char[] itemId, bool equip = false, bool saveNow = true)
{
    if (!IsStoreEnabled() || !IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null || g_DB == null)
    {
        return false;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item) || PlayerOwnsItem(client, item.id))
    {
        return false;
    }

    char steamid[32], safeSteamId[64], safeItemId[64], query[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(item.id, safeItemId, sizeof(safeItemId));

    if (g_bIsMySQL)
    {
        Format(query, sizeof(query), "INSERT INTO store_inventory (steamid, item_id, is_equipped) VALUES ('%s', '%s', 0)", safeSteamId, safeItemId);
    }
    else
    {
        Format(query, sizeof(query), "INSERT INTO store_inventory (steamid, item_id, is_equipped) VALUES ('%s', '%s', 0)", safeSteamId, safeItemId);
    }

    if (!BeginLockedStoreTransaction("GiveItemToClient"))
    {
        return false;
    }

    if (!ExecuteLockedStoreQuery("GiveItemToClient", query, 1))
    {
        RollbackLockedStoreTransaction("GiveItemToClient");
        return false;
    }

    if (!CommitLockedStoreTransaction("GiveItemToClient"))
    {
        return false;
    }

    InventoryItem newInv;
    strcopy(newInv.item_id, sizeof(newInv.item_id), item.id);
    newInv.is_equipped = 0;
    g_hInventory[client].PushArray(newInv, sizeof(InventoryItem));
    InventoryOwnedSet(client, item.id, true);
    MarkInventoryChanged(client);
    ForwardInventoryChanged(client, item.id, "give");
    LogAuditEvent(0, client, "give_item", item.id, 0, "core_give");

    if (equip)
    {
        SetItemEquipped(client, item.id, true, true, false);
    }

    if (saveNow)
    {
        SavePlayer(client);
    }

    return true;
}

bool RemoveItemFromClient(int client, const char[] itemId, bool saveNow = true)
{
    if (!IsStoreEnabled() || !IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null || g_DB == null)
    {
        return false;
    }

    int index = FindInventoryIndexByItemId(client, itemId);
    if (index == -1)
    {
        return false;
    }

    char steamid[32], safeSteamId[64], safeItemId[64], query[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));

    InventoryItem inv;
    g_hInventory[client].GetArray(index, inv, sizeof(InventoryItem));
    bool wasEquipped = view_as<bool>(inv.is_equipped);

    Format(query, sizeof(query), "DELETE FROM store_inventory WHERE steamid = '%s' AND item_id = '%s'", safeSteamId, safeItemId);

    if (!BeginLockedStoreTransaction("RemoveItemFromClient"))
    {
        return false;
    }

    if (!ExecuteLockedStoreQuery("RemoveItemFromClient", query, 1))
    {
        RollbackLockedStoreTransaction("RemoveItemFromClient");
        return false;
    }

    if (!CommitLockedStoreTransaction("RemoveItemFromClient"))
    {
        return false;
    }

    CancelMarketplaceListingsForClientItem(client, itemId);

    g_hInventory[client].Erase(index);
    InventoryOwnedSet(client, itemId, false);
    MarkInventoryChanged(client);
    ForwardInventoryChanged(client, itemId, "remove");
    LogAuditEvent(0, client, "remove_item", itemId, 0, "core_remove");

    if (wasEquipped)
    {
        StoreItem item;
        if (FindStoreItemById(itemId, item) && StrEqual(item.type, "skin"))
        {
            ApplyPlayerSkin(client);
        }
    }

    if (saveNow)
    {
        SavePlayer(client);
    }
    return true;
}

void MarkInventoryChanged(int client)
{
    if (client >= 1 && client <= MaxClients)
    {
        g_iInventoryVersion[client]++;
    }
}

bool ValidateInventoryMenuAction(int client, int expectedVersion, const char[] itemId = "", bool mustOwn = false)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        return false;
    }

    if (expectedVersion != g_iInventoryVersion[client])
    {
        PrintStorePhrase(client, "%T", "Inventory Changed Reopen", client);
        return false;
    }

    if (itemId[0] != '\0')
    {
        StoreItem item;
        if (!FindStoreItemById(itemId, item))
        {
            PrintStorePhrase(client, "%T", "Item Missing Config", client);
            return false;
        }

        if (mustOwn && !PlayerOwnsItem(client, itemId))
        {
            PrintStorePhrase(client, "%T", "Item Not Owned", client);
            return false;
        }
    }

    return true;
}

public Action Cmd_Inv(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    ShowInventoryCategoryMenu(client);
    return Plugin_Handled;
}

void ShowInventoryCategoryMenu(int client)
{
    Menu menu = new Menu(MenuHandler_InvCategory);
    SetMenuTitlePhrase(menu, client, "Inventory Category Menu Title");
    AddMenuItemPhrase(menu, "skins", client, "Inventory Category Skins");
    AddMenuItemPhrase(menu, "chat", client, "Inventory Category Chat");
    AddMenuItemPhrase(menu, "accessories", client, "Inventory Category Accessories");
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_InvCategory(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        Cmd_Store(param1, 0);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "skins"))
        {
            ShowInventoryTeamMenu(param1);
        }
        else if (StrEqual(info, "chat"))
        {
            ShowInventoryChatMenu(param1);
        }
        else if (StrEqual(info, "accessories"))
        {
            ShowInventoryAccessoriesMenu(param1);
        }
    }

    return 0;
}

void ShowInventoryTeamMenu(int client)
{
    Menu menu = new Menu(MenuHandler_InvSub);
    SetMenuTitlePhrase(menu, client, "Inventory Teams Menu Title");
    AddMenuItemPhrase(menu, "skin_2", client, "Inventory Teams Menu TT");
    AddMenuItemPhrase(menu, "skin_3", client, "Inventory Teams Menu CT");
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

void ShowInventoryChatMenu(int client)
{
    Menu menu = new Menu(MenuHandler_InvSub);
    char title[192], tagsLabel[64], nameColorLabel[64], chatColorLabel[64];
    Format(title, sizeof(title), "%T", "Inventory Chat Menu Title", client);
    Format(tagsLabel, sizeof(tagsLabel), "%T", "Chat Menu Tags", client);
    Format(nameColorLabel, sizeof(nameColorLabel), "%T", "Chat Menu Name Colors", client);
    Format(chatColorLabel, sizeof(chatColorLabel), "%T", "Chat Menu Chat Colors", client);
    menu.SetTitle(title);
    menu.AddItem("tag", tagsLabel);
    menu.AddItem("namecolor", nameColorLabel);
    menu.AddItem("chatcolor", chatColorLabel);
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

int CountInventoryItemsForFilter(int client, const char[] filter)
{
    if (g_hInventory[client] == null)
    {
        return 0;
    }

    int count = 0;
    InventoryItem inv;
    StoreItem item;
    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (FindStoreItemById(inv.item_id, item) && DoesInventoryItemMatchFilter(filter, item))
        {
            count++;
        }
    }
    return count;
}

void ShowInventoryAccessoriesMenu(int client)
{
    Menu menu = new Menu(MenuHandler_InvSub);
    SetMenuTitlePhrase(menu, client, "Inventory Accessories Menu Title");
    AddCountedMenuItem(menu, client, "hat_hats", "Accessories Menu Hats", CountInventoryItemsForFilter(client, "hat_hats"));
    AddCountedMenuItem(menu, client, "hat_glasses", "Accessories Menu Glasses", CountInventoryItemsForFilter(client, "hat_glasses"));
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_InvSub(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowInventoryCategoryMenu(param1);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        ShowInventoryListMenu(param1, info);
    }

    return 0;
}

bool DoesInventoryItemMatchFilter(const char[] filter, const StoreItem item)
{
    if (StrEqual(filter, "skin_2") && StrEqual(item.type, "skin") && StoreItemTeamMatches(item.team, 2))
    {
        return true;
    }
    if (StrEqual(filter, "skin_3") && StrEqual(item.type, "skin") && StoreItemTeamMatches(item.team, 3))
    {
        return true;
    }
    if (StrEqual(filter, item.type))
    {
        return true;
    }
    if (StrEqual(filter, "hat_hats") && StrEqual(item.type, "hat") && StrEqual(item.category, "hats", false))
    {
        return true;
    }
    if (StrEqual(filter, "hat_glasses") && StrEqual(item.type, "hat") && StrEqual(item.category, "glasses", false))
    {
        return true;
    }
    return false;
}

void AddInventoryItemsToMenu(int client, Menu menu, const char[] filter, bool equippedOnly, int &itemsAdded)
{
    InventoryItem inv;
    StoreItem item;

    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (!FindStoreItemById(inv.item_id, item))
        {
            continue;
        }

        if (!DoesInventoryItemMatchFilter(filter, item) || view_as<bool>(inv.is_equipped) != equippedOnly)
        {
            continue;
        }

        char display[128], itemInfo[64];
        if (inv.is_equipped)
        {
            char equippedSuffix[48];
            Format(equippedSuffix, sizeof(equippedSuffix), "%T", "Inventory Equipped Suffix", client);
            Format(display, sizeof(display), "%s %s", item.name, equippedSuffix);
        }
        else
        {
            strcopy(display, sizeof(display), item.name);
        }

        Format(itemInfo, sizeof(itemInfo), "%s|%s", filter, item.id);
        menu.AddItem(itemInfo, display);
        itemsAdded++;
    }
}

void ShowInventoryListMenu(int client, const char[] filter)
{
    strcopy(g_szInvFilter[client], 32, filter);

    Menu menu = new Menu(MenuHandler_InvList);
    SetMenuTitlePhrase(menu, client, "Inventory List Menu Title");

    int itemsAdded = 0;
    AddInventoryItemsToMenu(client, menu, filter, true, itemsAdded);
    AddInventoryItemsToMenu(client, menu, filter, false, itemsAdded);

    if (itemsAdded == 0)
    {
        char emptyLabel[96];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "Inventory List Empty", client);
        menu.AddItem("none", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_InvList(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        if (StrEqual(g_szInvFilter[param1], "skin_2") || StrEqual(g_szInvFilter[param1], "skin_3"))
        {
            ShowInventoryTeamMenu(param1);
        }
        else if (StrEqual(g_szInvFilter[param1], "hat_hats") || StrEqual(g_szInvFilter[param1], "hat_glasses"))
        {
            ShowInventoryAccessoriesMenu(param1);
        }
        else
        {
            ShowInventoryChatMenu(param1);
        }
    }
    else if (action == MenuAction_Select)
    {
        char info[64], buffers[2][32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "none"))
        {
            return 0;
        }

        ExplodeString(info, "|", buffers, 2, 32);
        g_bDetailFromInventory[param1] = true;
        g_bDetailFromSearch[param1] = false;
        ShowItemDetailsMenu(param1, buffers[1]);
    }

    return 0;
}

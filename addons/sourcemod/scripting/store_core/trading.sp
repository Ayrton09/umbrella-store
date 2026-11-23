// Umbrella Store core: Gifts and player-to-player trades.
// Included by store_core.sp.

bool CanTransferItemToTarget(int sender, int target, const char[] itemId, bool notify = true)
{
    if (!IsValidHumanClient(sender) || !IsValidHumanClient(target))
    {
        return false;
    }

    if (sender == target)
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Cannot Self", sender);
        }
        return false;
    }

    if (!g_bIsLoaded[sender] || !g_bIsLoaded[target] || g_hInventory[sender] == null || g_hInventory[target] == null)
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Target Inventory Not Loaded", sender);
        }
        return false;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Item Not Found", sender);
        }
        return false;
    }

    if (!PlayerOwnsItem(sender, item.id))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Item Not Owned", sender);
        }
        return false;
    }

    // Rentals (timed ownership) are consumed by the renter and cannot be moved
    // to another player; transferring would not carry the expiry correctly.
    if (GetInventoryExpiry(sender, item.id) > 0)
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Rental Not Transferable", sender);
        }
        return false;
    }

    if (PlayerOwnsItem(target, item.id))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Target Already Has Item", sender, target);
        }
        return false;
    }

    if (!HasAccess(target, item.flag))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Target No Access Item", sender, target);
        }
        return false;
    }

    return true;
}

bool TransferOwnedItem(int sender, int target, const char[] itemId, bool notify = true)
{
    if (g_DB == null || !CanTransferItemToTarget(sender, target, itemId, notify))
    {
        return false;
    }

    if (HasActiveMarketplaceListing(sender, itemId))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Market Item Listed Already", sender);
        }
        return false;
    }

    int index = FindInventoryIndexByItemId(sender, itemId);
    if (index == -1 || g_hInventory[target] == null)
    {
        return false;
    }

    char steamidSender[32], steamidTarget[32], safeSender[64], safeTarget[64], safeItemId[64], query[256];
    if (!GetClientSteamIdSafe(sender, steamidSender, sizeof(steamidSender)) || !GetClientSteamIdSafe(target, steamidTarget, sizeof(steamidTarget)))
    {
        return false;
    }

    EscapeStringSafe(steamidSender, safeSender, sizeof(safeSender));
    EscapeStringSafe(steamidTarget, safeTarget, sizeof(safeTarget));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));

    InventoryItem inv;
    g_hInventory[sender].GetArray(index, inv, sizeof(InventoryItem));
    bool wasEquipped = view_as<bool>(inv.is_equipped);

    Format(query, sizeof(query), "UPDATE store_inventory SET steamid = '%s', is_equipped = 0 WHERE steamid = '%s' AND item_id = '%s'", safeTarget, safeSender, safeItemId);
    if (!BeginLockedStoreTransaction("TransferOwnedItem"))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Store Transaction Failed", sender);
        }
        return false;
    }

    if (!ExecuteLockedStoreQuery("TransferOwnedItem", query, 1))
    {
        RollbackLockedStoreTransaction("TransferOwnedItem");
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Store Transaction Failed", sender);
        }
        return false;
    }

    if (!CommitLockedStoreTransaction("TransferOwnedItem"))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Store Transaction Failed", sender);
        }
        return false;
    }

    g_hInventory[sender].Erase(index);
    InventoryOwnedSet(sender, itemId, false);

    InventoryItem newInv;
    strcopy(newInv.item_id, sizeof(newInv.item_id), itemId);
    newInv.is_equipped = 0;
    g_hInventory[target].PushArray(newInv, sizeof(InventoryItem));
    InventoryOwnedSet(target, itemId, true);
    MarkInventoryChanged(sender);
    MarkInventoryChanged(target);
    ForwardInventoryChanged(sender, itemId, "transfer_out");
    ForwardInventoryChanged(target, itemId, "transfer_in");
    LogAuditEvent(sender, target, "gift_item", itemId, 0, "transfer");

    StoreItem item;
    FindStoreItemById(itemId, item);

    if (wasEquipped && StrEqual(item.type, "skin"))
    {
        ApplyPlayerSkin(sender);
    }

    return true;
}

bool ExecuteTrade(int sender, int target, const char[] senderItemId, const char[] targetItemId)
{
    if (sender == target || StrEqual(senderItemId, targetItemId))
    {
        return false;
    }

    if (!CanTransferItemToTarget(sender, target, senderItemId, false) || !CanTransferItemToTarget(target, sender, targetItemId, false))
    {
        return false;
    }

    if (ForwardTradePre(sender, target, senderItemId, targetItemId) >= Plugin_Handled)
    {
        return false;
    }

    if (HasActiveMarketplaceListing(sender, senderItemId) || HasActiveMarketplaceListing(target, targetItemId))
    {
        PrintStorePhrase(sender, "%T", "Market Item Listed Already", sender);
        PrintStorePhrase(target, "%T", "Market Item Listed Already", target);
        return false;
    }

    int senderIndex = FindInventoryIndexByItemId(sender, senderItemId);
    int targetIndex = FindInventoryIndexByItemId(target, targetItemId);
    if (senderIndex == -1 || targetIndex == -1)
    {
        return false;
    }

    char steamidSender[32], steamidTarget[32], safeSender[64], safeTarget[64];
    char safeSenderItemId[64], safeTargetItemId[64];
    if (!GetClientSteamIdSafe(sender, steamidSender, sizeof(steamidSender)) || !GetClientSteamIdSafe(target, steamidTarget, sizeof(steamidTarget)))
    {
        return false;
    }

    EscapeStringSafe(steamidSender, safeSender, sizeof(safeSender));
    EscapeStringSafe(steamidTarget, safeTarget, sizeof(safeTarget));
    EscapeStringSafe(senderItemId, safeSenderItemId, sizeof(safeSenderItemId));
    EscapeStringSafe(targetItemId, safeTargetItemId, sizeof(safeTargetItemId));

    InventoryItem senderInv, targetInv;
    g_hInventory[sender].GetArray(senderIndex, senderInv, sizeof(InventoryItem));
    g_hInventory[target].GetArray(targetIndex, targetInv, sizeof(InventoryItem));

    bool senderWasEquipped = view_as<bool>(senderInv.is_equipped);
    bool targetWasEquipped = view_as<bool>(targetInv.is_equipped);

    StoreItem senderItem, targetItem;
    if (!FindStoreItemById(senderItemId, senderItem) || !FindStoreItemById(targetItemId, targetItem))
    {
        return false;
    }

    char query[256];
    if (!BeginLockedStoreTransaction("ExecuteTrade"))
    {
        return false;
    }

    Format(query, sizeof(query), "UPDATE store_inventory SET steamid = '%s', is_equipped = 0 WHERE steamid = '%s' AND item_id = '%s'", safeTarget, safeSender, safeSenderItemId);
    if (!ExecuteLockedStoreQuery("ExecuteTrade", query, 1))
    {
        RollbackLockedStoreTransaction("ExecuteTrade");
        return false;
    }

    Format(query, sizeof(query), "UPDATE store_inventory SET steamid = '%s', is_equipped = 0 WHERE steamid = '%s' AND item_id = '%s'", safeSender, safeTarget, safeTargetItemId);
    if (!ExecuteLockedStoreQuery("ExecuteTrade", query, 1))
    {
        RollbackLockedStoreTransaction("ExecuteTrade");
        return false;
    }

    if (!CommitLockedStoreTransaction("ExecuteTrade"))
    {
        return false;
    }

    g_hInventory[sender].Erase(senderIndex);
    g_hInventory[target].Erase(targetIndex);
    InventoryOwnedSet(sender, senderItemId, false);
    InventoryOwnedSet(target, targetItemId, false);

    InventoryItem newSenderInv, newTargetInv;
    strcopy(newSenderInv.item_id, sizeof(newSenderInv.item_id), targetItemId);
    newSenderInv.is_equipped = 0;
    strcopy(newTargetInv.item_id, sizeof(newTargetInv.item_id), senderItemId);
    newTargetInv.is_equipped = 0;

    g_hInventory[sender].PushArray(newSenderInv, sizeof(InventoryItem));
    g_hInventory[target].PushArray(newTargetInv, sizeof(InventoryItem));
    InventoryOwnedSet(sender, targetItemId, true);
    InventoryOwnedSet(target, senderItemId, true);
    MarkInventoryChanged(sender);
    MarkInventoryChanged(target);
    ForwardInventoryChanged(sender, senderItemId, "trade_out");
    ForwardInventoryChanged(sender, targetItemId, "trade_in");
    ForwardInventoryChanged(target, targetItemId, "trade_out");
    ForwardInventoryChanged(target, senderItemId, "trade_in");
    ForwardTradePost(sender, target, senderItemId, targetItemId);
    ForwardTradeCompleted(sender, target, senderItemId, targetItemId);
    LogAuditEvent(sender, target, "trade_out", senderItemId, 0, targetItemId);
    LogAuditEvent(target, sender, "trade_out", targetItemId, 0, senderItemId);
    UpdatePlayerStat(sender, "trades_completed", 1);
    UpdatePlayerStat(target, "trades_completed", 1);

    if (senderWasEquipped && StrEqual(senderItem.type, "skin"))
    {
        ApplyPlayerSkin(sender);
    }

    if (targetWasEquipped && StrEqual(targetItem.type, "skin"))
    {
        ApplyPlayerSkin(target);
    }

    return true;
}

void ShowGiftTargetMenu(int client, const char[] itemId)
{
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];

    if (!PlayerOwnsItem(client, itemId))
    {
        ShowItemDetailsMenu(client, itemId);
        return;
    }

    if (HasActiveMarketplaceListing(client, itemId))
    {
        PrintStorePhrase(client, "%T", "Market Item Listed Already", client);
        ShowItemDetailsMenu(client, itemId);
        return;
    }

    strcopy(g_szLastDetailItem[client], sizeof(g_szLastDetailItem[]), itemId);
    strcopy(g_szTradeGiftItem[client], sizeof(g_szTradeGiftItem[]), itemId);

    StoreItem item;
    FindStoreItemById(itemId, item);

    Menu menu = new Menu(MenuHandler_GiftTarget);
    char title[192];
    Format(title, sizeof(title), "%T", "Gift Target Menu Title", client, item.name);
    menu.SetTitle(title);

    int added = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanClient(i) || i == client || !g_bIsLoaded[i])
        {
            continue;
        }

        if (!CanTransferItemToTarget(client, i, itemId, false))
        {
            continue;
        }

        char info[64], name[64];
        Format(info, sizeof(info), "%s|%d", itemId, GetClientUserId(i));
        GetClientName(i, name, sizeof(name));
        menu.AddItem(info, name);
        added++;
    }

    if (added == 0)
    {
        AddMenuItemPhrase(menu, "none", client, "Gift Target Menu Empty", ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_GiftTarget(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
    }
    else if (action == MenuAction_Select)
    {
        char info[64], parts[2][32];
        menu.GetItem(param2, info, sizeof(info));
        if (StrEqual(info, "none"))
        {
            return 0;
        }

        ExplodeString(info, "|", parts, 2, 32);
        if (!ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], parts[0], true))
        {
            ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
            return 0;
        }
        ShowGiftConfirmMenu(param1, parts[0], StringToInt(parts[1]));
    }

    return 0;
}

void ShowGiftConfirmMenu(int client, const char[] itemId, int targetUserId)
{
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];

    int target = GetClientOfUserId(targetUserId);
    if (!CanTransferItemToTarget(client, target, itemId, true))
    {
        ShowGiftTargetMenu(client, itemId);
        return;
    }

    StoreItem item;
    FindStoreItemById(itemId, item);

    Menu menu = new Menu(MenuHandler_GiftConfirm);
    char title[256];
    Format(title, sizeof(title), "%T", "Gift Confirm Menu Title", client, item.name, target);
    menu.SetTitle(title);

    char yesInfo[64], noInfo[64], yesLabel[64], noLabel[64];
    Format(yesInfo, sizeof(yesInfo), "%s|%d", itemId, targetUserId);
    strcopy(noInfo, sizeof(noInfo), itemId);
    Format(yesLabel, sizeof(yesLabel), "%T", "Gift Confirm Yes", client);
    Format(noLabel, sizeof(noLabel), "%T", "Gift Confirm No", client);

    menu.AddItem(yesInfo, yesLabel);
    menu.AddItem(noInfo, noLabel);
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_GiftConfirm(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowGiftTargetMenu(param1, g_szTradeGiftItem[param1]);
    }
    else if (action == MenuAction_Select)
    {
        if (param2 == 0)
        {
            char info[64], parts[2][32];
            menu.GetItem(param2, info, sizeof(info));
            ExplodeString(info, "|", parts, 2, 32);

            int target = GetClientOfUserId(StringToInt(parts[1]));
            if (!ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], parts[0], true))
            {
                ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
                return 0;
            }

            if (TransferOwnedItem(param1, target, parts[0], true))
            {
                StoreItem item;
                FindStoreItemById(parts[0], item);
                PrintStorePhrase(param1, "%T", "Gift Sent", param1, item.name, target);
                char safeGifterName[MAX_NAME_LENGTH];
                GetSafeClientName(param1, safeGifterName, sizeof(safeGifterName));
                PrintStorePhrase(target, "%T", "Gift Received", target, safeGifterName, item.name);
            }

            ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
        }
        else
        {
            ShowGiftTargetMenu(param1, g_szTradeGiftItem[param1]);
        }
    }

    return 0;
}

void ShowTradeTargetMenu(int client, const char[] itemId)
{
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];

    if (!PlayerOwnsItem(client, itemId))
    {
        ShowItemDetailsMenu(client, itemId);
        return;
    }

    if (HasActiveMarketplaceListing(client, itemId))
    {
        PrintStorePhrase(client, "%T", "Market Item Listed Already", client);
        ShowItemDetailsMenu(client, itemId);
        return;
    }

    strcopy(g_szLastDetailItem[client], sizeof(g_szLastDetailItem[]), itemId);
    strcopy(g_szTradeSenderItem[client], sizeof(g_szTradeSenderItem[]), itemId);

    StoreItem item;
    FindStoreItemById(itemId, item);

    Menu menu = new Menu(MenuHandler_TradeTarget);
    char title[192];
    Format(title, sizeof(title), "%T", "Trade Target Menu Title", client, item.name);
    menu.SetTitle(title);

    int added = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanClient(i) || i == client || !g_bIsLoaded[i] || g_hInventory[i] == null || g_hInventory[i].Length == 0)
        {
            continue;
        }

        char info[32], name[64];
        IntToString(GetClientUserId(i), info, sizeof(info));
        GetClientName(i, name, sizeof(name));
        menu.AddItem(info, name);
        added++;
    }

    if (added == 0)
    {
        char emptyLabel[96];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "Trade Target Menu Empty", client);
        menu.AddItem("none", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_TradeTarget(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        if (StrEqual(info, "none"))
        {
            return 0;
        }

        if (!ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], g_szTradeSenderItem[param1], true))
        {
            ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
            return 0;
        }

        ShowTradeTargetItemsMenu(param1, g_szTradeSenderItem[param1], StringToInt(info));
    }

    return 0;
}

void ShowTradeTargetItemsMenu(int client, const char[] senderItemId, int targetUserId)
{
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];

    int target = GetClientOfUserId(targetUserId);
    if (!IsValidHumanClient(target) || !g_bIsLoaded[target] || g_hInventory[target] == null)
    {
        ShowTradeTargetMenu(client, senderItemId);
        return;
    }

    g_iTradeTargetInvVersion[client] = g_iInventoryVersion[target];

    Menu menu = new Menu(MenuHandler_TradeTargetItem);
    StoreItem senderItem;
    FindStoreItemById(senderItemId, senderItem);

    char title[192];
    Format(title, sizeof(title), "%T", "Trade Target Items Menu Title", client, target, senderItem.name);
    menu.SetTitle(title);

    int added = 0;
    InventoryItem inv;
    StoreItem targetItem;
    for (int i = 0; i < g_hInventory[target].Length; i++)
    {
        g_hInventory[target].GetArray(i, inv, sizeof(InventoryItem));
        if (!FindStoreItemById(inv.item_id, targetItem))
        {
            continue;
        }

        if (PlayerOwnsItem(client, targetItem.id) || !HasAccess(client, targetItem.flag))
        {
            continue;
        }

        char info[96], display[128];
        Format(info, sizeof(info), "%d|%s|%s", targetUserId, senderItemId, targetItem.id);
        if (inv.is_equipped)
        {
            char equippedPrefix[48];
            FormatStorePhrase(client, equippedPrefix, sizeof(equippedPrefix), "Trade Equipped Prefix");
            Format(display, sizeof(display), "%s%s", equippedPrefix, targetItem.name);
        }
        else
        {
            strcopy(display, sizeof(display), targetItem.name);
        }
        menu.AddItem(info, display);
        added++;
    }

    if (added == 0)
    {
        char emptyLabel[96];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "Trade Target Items Empty", client);
        menu.AddItem("none", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_TradeTargetItem(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowTradeTargetMenu(param1, g_szTradeSenderItem[param1]);
    }
    else if (action == MenuAction_Select)
    {
        char info[96], parts[3][32];
        menu.GetItem(param2, info, sizeof(info));
        if (StrEqual(info, "none"))
        {
            return 0;
        }

        ExplodeString(info, "|", parts, 3, 32);
        int target = GetClientOfUserId(StringToInt(parts[0]));
        if (!IsValidHumanClient(target))
        {
            ShowTradeTargetMenu(param1, g_szTradeSenderItem[param1]);
            return 0;
        }

        if (!ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], parts[1], true) || g_iTradeTargetInvVersion[param1] != g_iInventoryVersion[target] || !PlayerOwnsItem(target, parts[2]))
        {
            PrintStorePhrase(param1, "%T", "Trade Inventory Changed", param1);
            ShowTradeTargetMenu(param1, g_szTradeSenderItem[param1]);
            return 0;
        }

        strcopy(g_szPendingTradeSenderItem[target], sizeof(g_szPendingTradeSenderItem[]), parts[1]);
        strcopy(g_szTradeTargetItem[target], sizeof(g_szTradeTargetItem[]), parts[2]);
        g_iTradeSender[target] = GetClientUserId(param1);
        g_iTradeSenderInvVersion[target] = g_iInventoryVersion[param1];
        g_iPendingTradeTargetInvVersion[target] = g_iInventoryVersion[target];

        StoreItem myItem, theirItem;
        FindStoreItemById(parts[1], myItem);
        FindStoreItemById(parts[2], theirItem);

        PrintStorePhrase(param1, "%T", "Trade Request Sent", param1, target);
        PrintStorePhrase(target, "%T", "Trade Request Received", target, param1, myItem.name, theirItem.name);
        ShowTradeReceiveMenu(target);
        ShowItemDetailsMenu(param1, parts[1]);
    }

    return 0;
}

void ShowTradeReceiveMenu(int client)
{
    int sender = GetClientOfUserId(g_iTradeSender[client]);
    if (!IsValidHumanClient(client) || !IsValidHumanClient(sender))
    {
        return;
    }

    StoreItem senderItem, targetItem;
    if (!FindStoreItemById(g_szPendingTradeSenderItem[client], senderItem) || !FindStoreItemById(g_szTradeTargetItem[client], targetItem))
    {
        return;
    }

    Menu menu = new Menu(MenuHandler_TradeReceive);
    char title[256];
    Format(title, sizeof(title), "%T", "Trade Receive Menu Title", client, sender, senderItem.name, targetItem.name);
    menu.SetTitle(title);
    char acceptLabel[64], denyLabel[64];
    Format(acceptLabel, sizeof(acceptLabel), "%T", "Trade Receive Accept", client);
    Format(denyLabel, sizeof(denyLabel), "%T", "Trade Receive Deny", client);
    menu.AddItem("accept", acceptLabel);
    menu.AddItem("deny", denyLabel);
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_TradeReceive(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        int sender = GetClientOfUserId(g_iTradeSender[param1]);
        if (!IsValidHumanClient(sender))
        {
            PrintStorePhrase(param1, "%T", "Trade Request Invalid", param1);
            g_iTradeSender[param1] = 0;
            g_szPendingTradeSenderItem[param1][0] = '\0';
            g_szTradeTargetItem[param1][0] = '\0';
            g_iTradeSenderInvVersion[param1] = 0;
            g_iPendingTradeTargetInvVersion[param1] = 0;
            return 0;
        }

        if (param2 == 0)
        {
            if (g_iTradeSenderInvVersion[param1] != g_iInventoryVersion[sender] || g_iPendingTradeTargetInvVersion[param1] != g_iInventoryVersion[param1] || !PlayerOwnsItem(sender, g_szPendingTradeSenderItem[param1]) || !PlayerOwnsItem(param1, g_szTradeTargetItem[param1]))
            {
                PrintStorePhrase(sender, "%T", "Trade Request Invalid", sender);
                PrintStorePhrase(param1, "%T", "Trade Request Invalid", param1);
            }
            else if (ExecuteTrade(sender, param1, g_szPendingTradeSenderItem[param1], g_szTradeTargetItem[param1]))
            {
                StoreItem senderItem, targetItem;
                FindStoreItemById(g_szPendingTradeSenderItem[param1], senderItem);
                FindStoreItemById(g_szTradeTargetItem[param1], targetItem);
                char safeTargetName[MAX_NAME_LENGTH], safeSenderName[MAX_NAME_LENGTH];
                GetSafeClientName(param1, safeTargetName, sizeof(safeTargetName));
                GetSafeClientName(sender, safeSenderName, sizeof(safeSenderName));
                PrintStorePhrase(sender, "%T", "Trade Completed Sender", sender, safeTargetName, senderItem.name, targetItem.name);
                PrintStorePhrase(param1, "%T", "Trade Completed Target", param1, safeSenderName, targetItem.name, senderItem.name);
            }
            else
            {
                PrintStorePhrase(sender, "%T", "Trade Failed", sender);
                PrintStorePhrase(param1, "%T", "Trade Failed", param1);
            }
        }
        else
        {
            char safeRejectorName[MAX_NAME_LENGTH];
            GetSafeClientName(param1, safeRejectorName, sizeof(safeRejectorName));
            PrintStorePhrase(sender, "%T", "Trade Rejected Sender", sender, safeRejectorName);
            PrintStorePhrase(param1, "%T", "Trade Rejected Target", param1, sender);
        }

        g_iTradeSender[param1] = 0;
        g_szPendingTradeSenderItem[param1][0] = '\0';
        g_szTradeTargetItem[param1][0] = '\0';
        g_iTradeSenderInvVersion[param1] = 0;
        g_iPendingTradeTargetInvVersion[param1] = 0;
    }

    return 0;
}

public Action Cmd_Gift(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (args >= 2)
    {
        char arg1[64], arg2[64];
        GetCmdArg(1, arg1, sizeof(arg1));
        GetCmdArg(2, arg2, sizeof(arg2));

        char targetPattern[64];
        int amount = 0;

        if (TryParseCreditAmount(arg1, amount))
        {
            strcopy(targetPattern, sizeof(targetPattern), arg2);
        }
        else if (TryParseCreditAmount(arg2, amount))
        {
            strcopy(targetPattern, sizeof(targetPattern), arg1);
        }
        else
        {
            PrintStorePhrase(client, "%T", "Gift Credits Usage", client);
            return Plugin_Handled;
        }

        int targets[MAXPLAYERS];
        int count = 0;
        if (!TryResolveCreditTargets(client, targetPattern, targets, count) || count != 1)
        {
            ReplyAdminTargetNotFound(client, targetPattern);
            return Plugin_Handled;
        }

        int target = targets[0];
        if (target == client)
        {
            PrintStorePhrase(client, "%T", "Cannot Self", client);
            return Plugin_Handled;
        }

        if (g_iCredits[client] < amount)
        {
            PrintStorePhrase(client, "%T", "Gift Credits Not Enough", client);
            return Plugin_Handled;
        }

        if (!ApplyCreditDeltasAtomic(client, -amount, "gift_credits_sent", target, amount, "gift_credits_received", false, ""))
        {
            PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
            return Plugin_Handled;
        }

        UpdatePlayerStat(client, "gifts_sent", 1);
        UpdatePlayerStat(target, "gifts_received", 1);
        LogAuditEvent(client, target, "gift_credits", "", amount, "");

        PrintStorePhrase(client, "%T", "Gift Credits Sent", client, amount, target);
        char safeSenderName[MAX_NAME_LENGTH];
        GetSafeClientName(client, safeSenderName, sizeof(safeSenderName));
        PrintStorePhrase(target, "%T", "Gift Credits Received", target, safeSenderName, amount);
        return Plugin_Handled;
    }

    if (g_szLastDetailItem[client][0] != '\0' && PlayerOwnsItem(client, g_szLastDetailItem[client]))
    {
        ShowGiftTargetMenu(client, g_szLastDetailItem[client]);
    }
    else
    {
        ShowInventoryCategoryMenu(client);
        PrintStorePhrase(client, "%T", "Open Item To Gift", client);
        PrintStorePhrase(client, "%T", "Gift Credits Usage", client);
    }

    return Plugin_Handled;
}

public Action Cmd_Trade(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (g_szLastDetailItem[client][0] != '\0' && PlayerOwnsItem(client, g_szLastDetailItem[client]))
    {
        ShowTradeTargetMenu(client, g_szLastDetailItem[client]);
    }
    else
    {
        ShowInventoryCategoryMenu(client);
        PrintStorePhrase(client, "%T", "Open Item To Trade", client);
    }

    return Plugin_Handled;
}

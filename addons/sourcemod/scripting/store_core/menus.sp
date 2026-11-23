// Umbrella Store core: Main store menu, browsing, search, and item details.
// Included by store_core.sp.

void RebuildMenuSectionIndex()
{
    if (g_mMenuSectionIndex == null)
    {
        g_mMenuSectionIndex = new StringMap();
    }
    else
    {
        g_mMenuSectionIndex.Clear();
    }

    if (g_aMenuSections == null)
    {
        return;
    }

    StoreMenuSection section;
    for (int i = 0; i < g_aMenuSections.Length; i++)
    {
        g_aMenuSections.GetArray(i, section, sizeof(StoreMenuSection));
        g_mMenuSectionIndex.SetValue(section.id, i);
    }
}

bool RegisterMenuSectionEntry(const char[] id, const char[] title, const char[] command, int sortOrder = 0)
{
    if (id[0] == '\0' || title[0] == '\0' || command[0] == '\0')
    {
        return false;
    }

    if (g_aMenuSections == null)
    {
        g_aMenuSections = new ArrayList(sizeof(StoreMenuSection));
    }

    if (g_mMenuSectionIndex == null)
    {
        g_mMenuSectionIndex = new StringMap();
    }

    StoreMenuSection section;
    strcopy(section.id, sizeof(section.id), id);
    strcopy(section.title, sizeof(section.title), title);
    strcopy(section.command, sizeof(section.command), command);
    section.sort_order = sortOrder;

    int index;
    if (g_mMenuSectionIndex.GetValue(id, index) && index >= 0 && index < g_aMenuSections.Length)
    {
        g_aMenuSections.SetArray(index, section, sizeof(StoreMenuSection));
        return true;
    }

    index = g_aMenuSections.PushArray(section, sizeof(StoreMenuSection));
    if (index < 0)
    {
        return false;
    }

    g_mMenuSectionIndex.SetValue(id, index);
    return true;
}

bool UnregisterMenuSectionEntry(const char[] id)
{
    if (id[0] == '\0' || g_aMenuSections == null || g_mMenuSectionIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mMenuSectionIndex.GetValue(id, index) || index < 0 || index >= g_aMenuSections.Length)
    {
        return false;
    }

    g_aMenuSections.Erase(index);
    RebuildMenuSectionIndex();
    return true;
}

bool TryHandleRegisteredMenuSectionSelection(int client, const char[] id)
{
    if (!IsValidHumanClient(client) || id[0] == '\0' || g_aMenuSections == null || g_mMenuSectionIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mMenuSectionIndex.GetValue(id, index) || index < 0 || index >= g_aMenuSections.Length)
    {
        return false;
    }

    StoreMenuSection section;
    g_aMenuSections.GetArray(index, section, sizeof(StoreMenuSection));
    if (section.command[0] == '\0')
    {
        return false;
    }

    FakeClientCommand(client, "%s", section.command);
    return true;
}

void AddRegisteredMenuSections(Menu menu)
{
    if (g_aMenuSections == null || g_aMenuSections.Length == 0)
    {
        return;
    }

    ArrayList ordered = new ArrayList();
    StoreMenuSection section;
    int insertAt;

    for (int i = 0; i < g_aMenuSections.Length; i++)
    {
        ordered.Push(i);
    }

    for (int i = 1; i < ordered.Length; i++)
    {
        int currentIndex = ordered.Get(i);
        g_aMenuSections.GetArray(currentIndex, section, sizeof(StoreMenuSection));
        int currentOrder = section.sort_order;

        insertAt = i - 1;
        while (insertAt >= 0)
        {
            int compareIndex = ordered.Get(insertAt);
            StoreMenuSection compareSection;
            g_aMenuSections.GetArray(compareIndex, compareSection, sizeof(StoreMenuSection));

            if (compareSection.sort_order < currentOrder || (compareSection.sort_order == currentOrder && strcmp(compareSection.title, section.title, false) <= 0))
            {
                break;
            }

            ordered.Set(insertAt + 1, compareIndex);
            insertAt--;
        }

        ordered.Set(insertAt + 1, currentIndex);
    }

    for (int i = 0; i < ordered.Length; i++)
    {
        int index = ordered.Get(i);
        g_aMenuSections.GetArray(index, section, sizeof(StoreMenuSection));
        menu.AddItem(section.id, section.title);
    }

    delete ordered;
}

void ShowStoreMainMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Main);
    char title[192];
    char creditsText[32];
    char profileLabel[64], questsLabel[64], skinsLabel[64], chatLabel[64], accessoriesLabel[64], petsLabel[64], leaderboardsLabel[64], inventoryLabel[64], casinoLabel[64], marketLabel[64], searchLabel[64];

    FormatNumberDots(g_iCredits[client], creditsText, sizeof(creditsText));
    Format(title, sizeof(title), "%T", "Store Main Menu Title", client, creditsText);
    menu.SetTitle(title);

    Format(profileLabel, sizeof(profileLabel), "%T", "Store Category Profile", client);
    Format(questsLabel, sizeof(questsLabel), "%T", "Store Category Quests", client);
    Format(skinsLabel, sizeof(skinsLabel), "%T", "Store Category Skins", client);
    Format(chatLabel, sizeof(chatLabel), "%T", "Store Category Chat", client);
    Format(accessoriesLabel, sizeof(accessoriesLabel), "%T", "Store Category Accessories", client);
    Format(petsLabel, sizeof(petsLabel), "%T", "Store Category Pets", client);
    Format(leaderboardsLabel, sizeof(leaderboardsLabel), "%T", "Store Category Leaderboards", client);
    Format(inventoryLabel, sizeof(inventoryLabel), "%T", "Store Category Inventory", client);
    Format(casinoLabel, sizeof(casinoLabel), "%T", "Store Category Casino", client);
    Format(marketLabel, sizeof(marketLabel), "%T", "Store Category Marketplace", client);
    Format(searchLabel, sizeof(searchLabel), "%T", "Store Category Search", client);

    menu.AddItem("skins", skinsLabel);
    menu.AddItem("chat", chatLabel);
    menu.AddItem("accessories", accessoriesLabel);
    menu.AddItem("pets", petsLabel);
    menu.AddItem("inventory", inventoryLabel);
    menu.AddItem("casino", casinoLabel);
    menu.AddItem("market", marketLabel);
    menu.AddItem("profile", profileLabel);
    menu.AddItem("quests", questsLabel);
    menu.AddItem("leaderboards", leaderboardsLabel);
    menu.AddItem("search", searchLabel);
    AddRegisteredMenuSections(menu);
    menu.Display(client, MENU_TIME_FOREVER);
}

public Action Cmd_Store(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    ShowStoreMainMenu(client);
    return Plugin_Handled;
}

bool ItemMatchesSearch(StoreItem item, const char[] query)
{
    if (query[0] == '\0')
    {
        return false;
    }

    return StrContains(item.id, query, false) != -1
        || StrContains(item.name, query, false) != -1
        || StrContains(item.type, query, false) != -1
        || StrContains(item.category, query, false) != -1
        || StrContains(item.description, query, false) != -1
        || StrContains(item.rarity, query, false) != -1;
}

void ShowSearchResultsMenu(int client, const char[] query)
{
    strcopy(g_szSearchQuery[client], sizeof(g_szSearchQuery[]), query);

    Menu menu = new Menu(MenuHandler_SearchResults);
    char title[192];
    Format(title, sizeof(title), "%T", "Search Results Title", client, query);
    menu.SetTitle(title);

    int itemsAdded = 0;
    StoreItem item;
    for (int i = 0; i < g_aItems.Length; i++)
    {
        g_aItems.GetArray(i, item, sizeof(StoreItem));

        if (item.hidden || !IsItemActiveForNow(item) || !ItemMatchesSearch(item, query))
        {
            continue;
        }

        char display[160], priceText[48];
        bool owns = PlayerOwnsItem(client, item.id);
        FormatCreditsAmount(client, item.price, priceText, sizeof(priceText));

        if (owns)
        {
            char invSuffix[64];
            Format(invSuffix, sizeof(invSuffix), "%T", "Items List Inventory Suffix", client);
            Format(display, sizeof(display), "%s [%s] %s", item.name, item.type, invSuffix);
        }
        else
        {
            Format(display, sizeof(display), "%s [%s | %s]", item.name, item.type, priceText);
        }

        menu.AddItem(item.id, display, HasAccess(client, item.flag) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
        itemsAdded++;
    }

    if (itemsAdded == 0)
    {
        char emptyLabel[128];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "Search No Results", client, query);
        menu.AddItem("none", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public Action Cmd_StoreSearch(int client, int args)
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
        PrintStorePhrase(client, "%T", "Search Usage", client);
        if (g_szSearchQuery[client][0] != '\0')
        {
            ShowSearchResultsMenu(client, g_szSearchQuery[client]);
        }
        return Plugin_Handled;
    }

    char query[64];
    GetCmdArgString(query, sizeof(query));
    StripQuotes(query);
    TrimString(query);

    if (strlen(query) < 2)
    {
        PrintStorePhrase(client, "%T", "Search Too Short", client);
        return Plugin_Handled;
    }

    ShowSearchResultsMenu(client, query);
    return Plugin_Handled;
}

public int MenuHandler_SearchResults(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowStoreMainMenu(param1);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        if (!StrEqual(info, "none"))
        {
            g_bDetailFromInventory[param1] = false;
            g_bDetailFromSearch[param1] = true;
            ShowItemDetailsMenu(param1, info);
        }
    }

    return 0;
}

public int MenuHandler_Main(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "skins"))
        {
            ShowTeamsMenu(param1);
        }
        else if (StrEqual(info, "profile"))
        {
            ShowProfileMenu(param1);
        }
        else if (StrEqual(info, "quests"))
        {
            ShowQuestMenu(param1);
        }
        else if (StrEqual(info, "chat"))
        {
            ShowChatMenu(param1);
        }
        else if (StrEqual(info, "accessories"))
        {
            ShowAccessoriesMenu(param1);
        }
        else if (StrEqual(info, "pets"))
        {
            ShowItemsListMenuFiltered(param1, "pet", 0, "pets");
        }
        else if (StrEqual(info, "topcredits"))
        {
            Cmd_TopCredits(param1, 0);
        }
        else if (StrEqual(info, "leaderboards"))
        {
            ShowLeaderboardsMenu(param1);
        }
        else if (StrEqual(info, "inventory"))
        {
            ShowInventoryCategoryMenu(param1);
        }
        else if (StrEqual(info, "market"))
        {
            ShowMarketMenu(param1);
        }
        else if (StrEqual(info, "search"))
        {
            if (g_szSearchQuery[param1][0] != '\0')
            {
                ShowSearchResultsMenu(param1, g_szSearchQuery[param1]);
            }
            else
            {
                PrintStorePhrase(param1, "%T", "Search Usage", param1);
                ShowStoreMainMenu(param1);
            }
        }
        else if (StrEqual(info, "casino"))
        {
            ShowCasinoMenu(param1);
        }
        else
        {
            TryHandleRegisteredMenuSectionSelection(param1, info);
        }
    }

    return 0;
}

void ShowTeamsMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Teams);
    char title[192];
    char labelTT[96];
    char labelCT[96];
    Format(title, sizeof(title), "%T", "Teams Menu Title", client);
    Format(labelTT, sizeof(labelTT), "%T", "Teams Menu TT", client);
    Format(labelCT, sizeof(labelCT), "%T", "Teams Menu CT", client);
    menu.SetTitle(title);
    menu.AddItem("2", labelTT);
    menu.AddItem("3", labelCT);
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Teams(Menu menu, MenuAction action, int param1, int param2)
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
        ShowItemsListMenu(param1, "skin", StringToInt(info));
    }

    return 0;
}

void ShowChatMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Chat);
    SetMenuTitlePhrase(menu, client, "Chat Menu Title");
    AddMenuItemPhrase(menu, "tag", client, "Chat Menu Tags");
    AddMenuItemPhrase(menu, "namecolor", client, "Chat Menu Name Colors");
    AddMenuItemPhrase(menu, "chatcolor", client, "Chat Menu Chat Colors");
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Chat(Menu menu, MenuAction action, int param1, int param2)
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
        ShowItemsListMenu(param1, info, 0);
    }

    return 0;
}

bool ItemMatchesBrowseFilter(const StoreItem item, const char[] targetType, int targetTeam, const char[] categoryFilter)
{
    if (!StrEqual(item.type, targetType) || (targetTeam != 0 && !StoreItemTeamMatches(item.team, targetTeam)))
    {
        return false;
    }

    if (categoryFilter[0] != '\0' && !StrEqual(item.category, categoryFilter, false))
    {
        return false;
    }

    return !item.hidden && IsItemActiveForNow(item);
}

int CountAvailableItemsForBrowse(const char[] targetType, int targetTeam, const char[] categoryFilter)
{
    int count = 0;
    StoreItem item;
    for (int i = 0; i < g_aItems.Length; i++)
    {
        g_aItems.GetArray(i, item, sizeof(StoreItem));
        if (ItemMatchesBrowseFilter(item, targetType, targetTeam, categoryFilter))
        {
            count++;
        }
    }
    return count;
}

void AddCountedMenuItem(Menu menu, int client, const char[] info, const char[] phrase, int count)
{
    char baseLabel[64], display[96];
    Format(baseLabel, sizeof(baseLabel), "%T", phrase, client);
    Format(display, sizeof(display), "%s (%d)", baseLabel, count);
    menu.AddItem(info, display, count > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
}

void ShowAccessoriesMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Accessories);
    SetMenuTitlePhrase(menu, client, "Accessories Menu Title");
    AddCountedMenuItem(menu, client, "hats", "Accessories Menu Hats", CountAvailableItemsForBrowse("hat", 0, "hats"));
    AddCountedMenuItem(menu, client, "glasses", "Accessories Menu Glasses", CountAvailableItemsForBrowse("hat", 0, "glasses"));
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Accessories(Menu menu, MenuAction action, int param1, int param2)
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
        if (StrEqual(info, "hats") || StrEqual(info, "glasses"))
        {
            ShowItemsListMenuFiltered(param1, "hat", 0, info);
        }
    }

    return 0;
}

void ShowCurrentBrowseItemsList(int client)
{
    ShowItemsListMenuFiltered(client, g_szBrowseType[client], g_iBrowseTeam[client], g_szBrowseCategory[client]);
}

void ShowItemsListMenu(int client, const char[] targetType, int targetTeam)
{
    ShowItemsListMenuFiltered(client, targetType, targetTeam, "");
}

void ShowItemsListMenuFiltered(int client, const char[] targetType, int targetTeam, const char[] categoryFilter)
{
    strcopy(g_szBrowseType[client], sizeof(g_szBrowseType[]), targetType);
    g_iBrowseTeam[client] = targetTeam;
    strcopy(g_szBrowseCategory[client], sizeof(g_szBrowseCategory[]), categoryFilter);
    g_bDetailFromSearch[client] = false;

    Menu menu = new Menu(MenuHandler_ItemsList);
    char title[192];
    char creditsText[32];
    FormatNumberDots(g_iCredits[client], creditsText, sizeof(creditsText));
    Format(title, sizeof(title), "%T", "Items List Menu Title", client, creditsText);
    menu.SetTitle(title);

    int itemsAdded = 0;
    StoreItem item;

    for (int i = 0; i < g_aItems.Length; i++)
    {
        g_aItems.GetArray(i, item, sizeof(StoreItem));

        if (!ItemMatchesBrowseFilter(item, targetType, targetTeam, categoryFilter))
        {
            continue;
        }

        char display[128];
        bool owns = PlayerOwnsItem(client, item.id);

        if (!HasAccess(client, item.flag))
        {
            char vipSuffix[48];
            Format(vipSuffix, sizeof(vipSuffix), "%T", "Items List VIP Suffix", client);
            Format(display, sizeof(display), "%s %s", item.name, vipSuffix);
            menu.AddItem(item.id, display, ITEMDRAW_DISABLED);
        }
        else if (owns)
        {
            char invSuffix[64];
            Format(invSuffix, sizeof(invSuffix), "%T", "Items List Inventory Suffix", client);
            Format(display, sizeof(display), "%s %s", item.name, invSuffix);
            menu.AddItem(item.id, display, ITEMDRAW_DEFAULT);
        }
        else
        {
            char priceText[48];
            FormatCreditsAmount(client, item.price, priceText, sizeof(priceText));
            Format(display, sizeof(display), "%s [%s]", item.name, priceText);
            menu.AddItem(item.id, display, ITEMDRAW_DEFAULT);
        }

        itemsAdded++;
    }

    if (itemsAdded == 0)
    {
        char emptyLabel[96];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "Items List Empty", client);
        menu.AddItem("none", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ItemsList(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        if (StrEqual(g_szBrowseType[param1], "skin"))
        {
            ShowTeamsMenu(param1);
        }
        else if (StrEqual(g_szBrowseType[param1], "hat"))
        {
            ShowAccessoriesMenu(param1);
        }
        else if (StrEqual(g_szBrowseType[param1], "pet"))
        {
            Cmd_Store(param1, 0);
        }
        else
        {
            ShowChatMenu(param1);
        }
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        g_bDetailFromInventory[param1] = false;
        ShowItemDetailsMenu(param1, info);
    }

    return 0;
}

void ShowItemDetailsMenu(int client, const char[] itemId)
{
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        return;
    }

    strcopy(g_szLastDetailItem[client], sizeof(g_szLastDetailItem[]), item.id);

    bool owns = false;
    bool isEquipped = false;
    int ownedExpiry = 0;
    int invIndex = FindInventoryIndexByItemId(client, itemId);
    if (invIndex != -1)
    {
        owns = true;
        InventoryItem inv;
        g_hInventory[client].GetArray(invIndex, inv, sizeof(InventoryItem));
        isEquipped = view_as<bool>(inv.is_equipped);
        ownedExpiry = inv.expires_at;
    }

    Menu menu = new Menu(MenuHandler_ItemDetails);
    char title[192];

    if (owns)
    {
        char stateText[96];
        Format(stateText, sizeof(stateText), "%T", isEquipped ? "Item State Equipped" : "Item State Inventory", client);
        if (ownedExpiry > 0)
        {
            char remainText[48];
            FormatRentalRemaining(client, ownedExpiry, remainText, sizeof(remainText));
            if (remainText[0] != '\0')
            {
                Format(stateText, sizeof(stateText), "%s (%s)", stateText, remainText);
            }
        }
        Format(title, sizeof(title), "%T", "Item Details Owned Title", client, item.name, stateText);
    }
    else
    {
        char priceText[48];
        FormatCreditsAmount(client, item.price, priceText, sizeof(priceText));
        Format(title, sizeof(title), "%T", "Item Details Buy Title", client, item.name, priceText);
    }

    menu.SetTitle(title);

    if (!owns)
    {
        char buyInfo[64];
        char buyLabel[64];
        if (ItemHasPlans(item))
        {
            Format(buyInfo, sizeof(buyInfo), "plans_%s", item.id);
            FormatStorePhrase(client, buyLabel, sizeof(buyLabel), "Item Details Choose Plan");
        }
        else
        {
            Format(buyInfo, sizeof(buyInfo), "buy_%s", item.id);
            FormatStorePhrase(client, buyLabel, sizeof(buyLabel), "Item Details Buy");
        }
        menu.AddItem(buyInfo, buyLabel);
    }
    else
    {
        char eqInfo[64];
        char equipLabel[64];
        Format(eqInfo, sizeof(eqInfo), "eq_%s", item.id);
        FormatStorePhrase(client, equipLabel, sizeof(equipLabel), isEquipped ? "Item Details Unequip" : "Item Details Equip");
        menu.AddItem(eqInfo, equipLabel);

        if (ownedExpiry > 0)
        {
            char renewInfo[64], renewLabel[64];
            Format(renewInfo, sizeof(renewInfo), "plans_%s", item.id);
            FormatStorePhrase(client, renewLabel, sizeof(renewLabel), "Item Details Renew");
            menu.AddItem(renewInfo, renewLabel);
        }

        // Rentals (timed) cannot be sold, gifted or traded, only equipped/renewed.
        if (ownedExpiry == 0)
        {
            char sellInfo[64], sellText[96];
            Format(sellInfo, sizeof(sellInfo), "sell_%s", item.id);
            char refundText[48];
            FormatCreditsAmount(client, GetItemSellPrice(item), refundText, sizeof(refundText));
            Format(sellText, sizeof(sellText), "%T", "Item Details Sell", client, refundText);
            menu.AddItem(sellInfo, sellText);

            char giftInfo[64], tradeInfo[64];
            char giftLabel[64], tradeLabel[64];
            Format(giftInfo, sizeof(giftInfo), "gift_%s", item.id);
            Format(tradeInfo, sizeof(tradeInfo), "trade_%s", item.id);
            FormatStorePhrase(client, giftLabel, sizeof(giftLabel), "Item Details Gift");
            FormatStorePhrase(client, tradeLabel, sizeof(tradeLabel), "Item Details Trade");
            menu.AddItem(giftInfo, giftLabel);
            menu.AddItem(tradeInfo, tradeLabel);
        }
    }

    if (ItemSupportsPreview(item))
    {
        char previewInfo[64];
        char previewLabel[64];
        Format(previewInfo, sizeof(previewInfo), "prev_%s", item.id);
        FormatStorePhrase(client, previewLabel, sizeof(previewLabel), "Item Details Preview");
        menu.AddItem(previewInfo, previewLabel);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ItemDetails(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
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
    else if (action == MenuAction_Select)
    {
        char info[64], itemId[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrContains(info, "plans_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[6]);
            ShowBuyPlanMenu(param1, itemId);
        }
        else if (StrContains(info, "buy_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[4]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, false))
            {
                BuyItem(param1, itemId);
            }
            ShowItemDetailsMenu(param1, itemId);
        }
        else if (StrContains(info, "eq_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[3]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, true))
            {
                ToggleEquip(param1, itemId);
            }
            ShowItemDetailsMenu(param1, itemId);
        }
        else if (StrContains(info, "sell_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[5]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, true))
            {
                ShowSellConfirmMenu(param1, itemId);
            }
            else
            {
                ShowItemDetailsMenu(param1, itemId);
            }
        }
        else if (StrContains(info, "gift_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[5]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, true))
            {
                ShowGiftTargetMenu(param1, itemId);
            }
            else
            {
                ShowItemDetailsMenu(param1, itemId);
            }
        }
        else if (StrContains(info, "trade_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[6]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, true))
            {
                ShowTradeTargetMenu(param1, itemId);
            }
            else
            {
                ShowItemDetailsMenu(param1, itemId);
            }
        }
        else if (StrContains(info, "prev_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[5]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, false))
            {
                StoreItem item;
                if (FindStoreItemById(itemId, item))
                {
                    PreviewItem(param1, item);
                }
            }
            ShowItemDetailsMenu(param1, itemId);
        }
    }

    return 0;
}

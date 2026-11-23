// Umbrella Store core: Admin commands, admin menu, and admin diagnostics.
// Included by store_core.sp.

public void OnStoreAdminFlagChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RefreshStoreAdminTopMenu();
}

public Action Cmd_ReloadStore(int client, int args)
{
    LoadItemsConfig();
    LoadQuestConfig();

    char msg[192];
    Format(msg, sizeof(msg), "%T", "Store Reloaded", client, g_aItems.Length);
    ReplaceColorTags(msg, sizeof(msg));
    ReplyStoreText(client, msg);

    return Plugin_Handled;
}

bool TryResolveCreditTargets(int admin, const char[] pattern, int targets[MAXPLAYERS], int &count)
{
    count = 0;

    if (StrEqual(pattern, "@all", false))
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidHumanClient(i) && g_bIsLoaded[i])
            {
                targets[count++] = i;
            }
        }
        return (count > 0);
    }

    if (StrEqual(pattern, "@t", false) || StrEqual(pattern, "@ts", false) || StrEqual(pattern, "@team2", false))
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidHumanClient(i) && g_bIsLoaded[i] && GetClientTeam(i) == 2)
            {
                targets[count++] = i;
            }
        }
        return (count > 0);
    }

    if (StrEqual(pattern, "@ct", false) || StrEqual(pattern, "@team3", false))
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidHumanClient(i) && g_bIsLoaded[i] && GetClientTeam(i) == 3)
            {
                targets[count++] = i;
            }
        }
        return (count > 0);
    }

    if (StrEqual(pattern, "@me", false))
    {
        if (admin > 0 && IsValidHumanClient(admin) && g_bIsLoaded[admin])
        {
            targets[count++] = admin;
            return true;
        }
        return false;
    }

    int partialMatch = 0;
    int partialCount = 0;
    char name[MAX_NAME_LENGTH];

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanClient(i) || !g_bIsLoaded[i])
        {
            continue;
        }

        GetClientName(i, name, sizeof(name));

        if (StrEqual(name, pattern, false))
        {
            targets[0] = i;
            count = 1;
            return true;
        }

        if (StrContains(name, pattern, false) != -1)
        {
            partialMatch = i;
            partialCount++;
        }
    }

    if (partialCount == 1)
    {
        targets[0] = partialMatch;
        count = 1;
        return true;
    }

    return false;
}

void ReplyAdminTargetNotFound(int client, const char[] pattern)
{
    char msg[192];
    Format(msg, sizeof(msg), "%T", "Admin Target Not Found", client, pattern);
    ReplaceColorTags(msg, sizeof(msg));
    ReplyStoreText(client, msg);
}

bool ResolveSingleStoreTarget(int admin, const char[] pattern, int &target)
{
    target = 0;

    int targets[MAXPLAYERS];
    int count = 0;
    if (!TryResolveCreditTargets(admin, pattern, targets, count) || count != 1)
    {
        return false;
    }

    target = targets[0];
    return true;
}

void ReplyStoreAdminUsage(int client, const char[] phrase)
{
    char msg[192];
    Format(msg, sizeof(msg), "%T", phrase, client);
    ReplaceColorTags(msg, sizeof(msg));
    ReplyStoreText(client, msg);
}

bool HasStoreAdminAccess(int client)
{
    return (IsValidHumanClient(client) && CheckCommandAccess(client, "sm_storeadmin", GetStoreAdminAccessFlags()));
}

int GetStoreAdminAccessFlags()
{
    char flagString[32];
    flagString[0] = '\0';

    if (gCvarStoreAdminFlag != null)
    {
        gCvarStoreAdminFlag.GetString(flagString, sizeof(flagString));
        TrimString(flagString);
    }

    if (flagString[0] == '\0')
    {
        strcopy(flagString, sizeof(flagString), "z");
    }

    int flags = ReadFlagString(flagString);
    if (flags == 0)
    {
        flags = ADMFLAG_ROOT;
    }

    return flags;
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "adminmenu"))
    {
        g_hAdminMenu = INVALID_HANDLE;
        g_tmoStoreAdmin = INVALID_TOPMENUOBJECT;
    }
}

public void OnAdminMenuReady(Handle topmenu)
{
    if (topmenu == INVALID_HANDLE)
    {
        return;
    }

    g_hAdminMenu = topmenu;
    RefreshStoreAdminTopMenu();
}

void RefreshStoreAdminTopMenu()
{
    if (g_hAdminMenu == INVALID_HANDLE)
    {
        return;
    }

    if (g_tmoStoreAdmin != INVALID_TOPMENUOBJECT)
    {
        RemoveFromTopMenu(g_hAdminMenu, g_tmoStoreAdmin);
        g_tmoStoreAdmin = INVALID_TOPMENUOBJECT;
    }

    int adminFlags = GetStoreAdminAccessFlags();
    g_tmoStoreAdmin = AddToTopMenu(g_hAdminMenu, "Store Admin", TopMenuObject_Category, TopMenuHandler_StoreAdminCategory, INVALID_TOPMENUOBJECT, "sm_storeadmin", adminFlags);
    if (g_tmoStoreAdmin == INVALID_TOPMENUOBJECT)
    {
        return;
    }

    AddToTopMenu(g_hAdminMenu, "umbrella_store_reload", TopMenuObject_Item, TopMenuHandler_StoreAdminItem, g_tmoStoreAdmin, "sm_reloadstore", adminFlags, "reload");
    AddToTopMenu(g_hAdminMenu, "umbrella_store_givecredits", TopMenuObject_Item, TopMenuHandler_StoreAdminItem, g_tmoStoreAdmin, "sm_givecredits", adminFlags, "give_credits");
    AddToTopMenu(g_hAdminMenu, "umbrella_store_setcredits", TopMenuObject_Item, TopMenuHandler_StoreAdminItem, g_tmoStoreAdmin, "sm_setcredits", adminFlags, "set_credits");
    AddToTopMenu(g_hAdminMenu, "umbrella_store_viewinventory", TopMenuObject_Item, TopMenuHandler_StoreAdminItem, g_tmoStoreAdmin, "sm_storeadmin", adminFlags, "view_inventory");
}

public void TopMenuHandler_StoreAdminCategory(TopMenu topmenu, TopMenuAction action, TopMenuObject objectId, int param, char[] buffer, int maxlength)
{
    if (action == TopMenuAction_DisplayTitle || action == TopMenuAction_DisplayOption)
    {
        Format(buffer, maxlength, "%T", "Admin Menu Category", param);
    }
}

public void TopMenuHandler_StoreAdminItem(TopMenu topmenu, TopMenuAction action, TopMenuObject objectId, int param, char[] buffer, int maxlength)
{
    char actionName[32];
    GetTopMenuInfoString(topmenu, objectId, actionName, sizeof(actionName));

    if (action == TopMenuAction_DisplayOption)
    {
        FormatStoreAdminActionText(param, actionName, buffer, maxlength);
    }
    else if (action == TopMenuAction_SelectOption)
    {
        RunStoreAdminAction(param, actionName);
    }
}

public Action Cmd_StoreAdminMenu(int client, int args)
{
    if (!HasStoreAdminAccess(client))
    {
        return Plugin_Handled;
    }

    ShowStoreAdminMenu(client);
    return Plugin_Handled;
}

void ShowStoreAdminMenu(int client)
{
    if (!HasStoreAdminAccess(client))
    {
        return;
    }

    Menu menu = new Menu(MenuHandler_StoreAdminMain);
    SetMenuTitlePhrase(menu, client, "Admin Menu Title");
    AddStoreAdminMenuItem(menu, "reload", client);
    AddStoreAdminMenuItem(menu, "give_credits", client);
    AddStoreAdminMenuItem(menu, "set_credits", client);
    AddStoreAdminMenuItem(menu, "view_inventory", client);
    menu.Display(client, MENU_TIME_FOREVER);
}

void AddStoreAdminMenuItem(Menu menu, const char[] actionName, int client)
{
    char label[128];
    FormatStoreAdminActionText(client, actionName, label, sizeof(label));
    menu.AddItem(actionName, label);
}

void FormatStoreAdminActionText(int client, const char[] actionName, char[] buffer, int maxlength)
{
    if (StrEqual(actionName, "reload"))
    {
        Format(buffer, maxlength, "%T", "Admin Menu Reload", client);
        return;
    }

    if (StrEqual(actionName, "give_credits"))
    {
        Format(buffer, maxlength, "%T", "Admin Menu Give Credits", client);
        return;
    }

    if (StrEqual(actionName, "set_credits"))
    {
        Format(buffer, maxlength, "%T", "Admin Menu Set Credits", client);
        return;
    }

    if (StrEqual(actionName, "view_inventory"))
    {
        Format(buffer, maxlength, "%T", "Admin Menu View Inventory", client);
        return;
    }

    if (StrEqual(actionName, "debug_player"))
    {
        Format(buffer, maxlength, "%T", "Admin Menu Debug Player", client);
        return;
    }

    if (StrEqual(actionName, "debug_quests"))
    {
        Format(buffer, maxlength, "%T", "Admin Menu Debug Quests", client);
        return;
    }

    if (StrEqual(actionName, "export_profile"))
    {
        Format(buffer, maxlength, "%T", "Admin Menu Export Profile", client);
        return;
    }

    if (StrEqual(actionName, "audit_global"))
    {
        Format(buffer, maxlength, "%T", "Admin Menu Audit Global", client);
        return;
    }

    if (StrEqual(actionName, "audit_player"))
    {
        Format(buffer, maxlength, "%T", "Admin Menu Audit Player", client);
        return;
    }

    Format(buffer, maxlength, "%T", "Admin Menu Open Store", client);
}

public int MenuHandler_StoreAdminMain(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char actionName[32];
        menu.GetItem(param2, actionName, sizeof(actionName));
        RunStoreAdminAction(param1, actionName);
    }

    return 0;
}

void ReloadStoreAdminConfigs(int client)
{
    LoadItemsConfig();
    LoadQuestConfig();

    char msg[192];
    Format(msg, sizeof(msg), "%T", "Store Reloaded", client, g_aItems.Length);
    ReplaceColorTags(msg, sizeof(msg));
    CPrintToChat(client, "%s", msg);
}

void ShowStoreAdminReloadConfirmMenu(int client)
{
    if (!HasStoreAdminAccess(client))
    {
        return;
    }

    Menu menu = new Menu(MenuHandler_StoreAdminReloadConfirm);
    SetMenuTitlePhrase(menu, client, "Admin Reload Confirm Title");
    AddMenuItemPhrase(menu, "yes", client, "Admin Reload Confirm Yes");
    AddMenuItemPhrase(menu, "no", client, "Admin Reload Confirm No");
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_StoreAdminReloadConfirm(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowStoreAdminMenu(param1);
    }
    else if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        if (StrEqual(info, "yes"))
        {
            ReloadStoreAdminConfigs(param1);
        }

        ShowStoreAdminMenu(param1);
    }

    return 0;
}

void RunStoreAdminAction(int client, const char[] actionName)
{
    if (!HasStoreAdminAccess(client))
    {
        return;
    }

    if (StrEqual(actionName, "reload"))
    {
        ShowStoreAdminReloadConfirmMenu(client);
        return;
    }

    if (StrEqual(actionName, "audit_global"))
    {
        RequestStoreAudit(client, 0, 20, false);
        return;
    }

    if (StrEqual(actionName, "open_store"))
    {
        if (!g_bIsLoaded[client] || !EnsureStoreEnabledForClient(client))
        {
            return;
        }

        ShowStoreMainMenu(client);
        return;
    }

    if (StrEqual(actionName, "give_credits"))
    {
        ShowStoreAdminTargetMenu(client, StoreAdminAction_GiveCredits);
    }
    else if (StrEqual(actionName, "set_credits"))
    {
        ShowStoreAdminTargetMenu(client, StoreAdminAction_SetCredits);
    }
    else if (StrEqual(actionName, "view_inventory"))
    {
        ShowStoreAdminTargetMenu(client, StoreAdminAction_ViewInventory);
    }
    else if (StrEqual(actionName, "debug_player"))
    {
        ShowStoreAdminTargetMenu(client, StoreAdminAction_DebugPlayer);
    }
    else if (StrEqual(actionName, "debug_quests"))
    {
        ShowStoreAdminTargetMenu(client, StoreAdminAction_DebugQuests);
    }
    else if (StrEqual(actionName, "export_profile"))
    {
        ShowStoreAdminTargetMenu(client, StoreAdminAction_ExportProfile);
    }
    else if (StrEqual(actionName, "audit_player"))
    {
        ShowStoreAdminTargetMenu(client, StoreAdminAction_AuditPlayer);
    }
}

void FormatStoreAdminActionLabel(StoreAdminAction action, int client, char[] buffer, int maxlength)
{
    switch (action)
    {
        case StoreAdminAction_GiveCredits:
        {
            Format(buffer, maxlength, "%T", "Admin Menu Give Credits", client);
            return;
        }
        case StoreAdminAction_SetCredits:
        {
            Format(buffer, maxlength, "%T", "Admin Menu Set Credits", client);
            return;
        }
        case StoreAdminAction_ViewInventory:
        {
            Format(buffer, maxlength, "%T", "Admin Menu View Inventory", client);
            return;
        }
        case StoreAdminAction_DebugPlayer:
        {
            Format(buffer, maxlength, "%T", "Admin Menu Debug Player", client);
            return;
        }
        case StoreAdminAction_DebugQuests:
        {
            Format(buffer, maxlength, "%T", "Admin Menu Debug Quests", client);
            return;
        }
        case StoreAdminAction_ExportProfile:
        {
            Format(buffer, maxlength, "%T", "Admin Menu Export Profile", client);
            return;
        }
        case StoreAdminAction_AuditPlayer:
        {
            Format(buffer, maxlength, "%T", "Admin Menu Audit Player", client);
            return;
        }
    }

    Format(buffer, maxlength, "%T", "Admin Menu Open Store", client);
}

void ShowStoreAdminTargetMenu(int client, StoreAdminAction action)
{
    if (!HasStoreAdminAccess(client))
    {
        return;
    }

    g_AdminMenuAction[client] = action;

    char actionLabel[96], title[192];
    FormatStoreAdminActionLabel(action, client, actionLabel, sizeof(actionLabel));
    Format(title, sizeof(title), "%T", "Admin Target Menu Title", client, actionLabel);

    Menu menu = new Menu(MenuHandler_StoreAdminTarget);
    menu.SetTitle(title);
    menu.ExitBackButton = true;

    int count = AddLoadedPlayersToStoreAdminMenu(menu, client, true);
    if (count == 0)
    {
        char emptyLabel[128];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "Admin No Loaded Players", client);
        menu.AddItem("none", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

int AddLoadedPlayersToStoreAdminMenu(Menu menu, int admin, bool showCredits)
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanClient(i) || !g_bIsLoaded[i])
        {
            continue;
        }

        if (admin > 0 && i != admin && !CanUserTarget(admin, i))
        {
            continue;
        }

        char info[16], name[MAX_NAME_LENGTH], display[128], creditsText[32];
        IntToString(GetClientUserId(i), info, sizeof(info));
        GetClientName(i, name, sizeof(name));

        if (showCredits)
        {
            FormatNumberDots(g_iCredits[i], creditsText, sizeof(creditsText));
            Format(display, sizeof(display), "%s - %s credits", name, creditsText);
        }
        else
        {
            strcopy(display, sizeof(display), name);
        }

        menu.AddItem(info, display);
        count++;
    }

    return count;
}

// g_iAdminMenuTarget stores a userid, not a slot index: admin credit/inventory
// menus stay open across disconnects, and a raw index would silently retarget
// whoever takes over the freed slot.
int ResolveStoreAdminTarget(int admin)
{
    if (admin < 1 || admin > MaxClients)
    {
        return 0;
    }

    int userid = g_iAdminMenuTarget[admin];
    if (userid <= 0)
    {
        return 0;
    }

    int target = GetClientOfUserId(userid);
    return (target > 0) ? target : 0;
}

bool IsValidStoreAdminTarget(int admin, int target)
{
    if (!IsValidHumanClient(target) || !g_bIsLoaded[target])
    {
        PrintStorePhrase(admin, "%T", "Admin Target Not Loaded", admin);
        return false;
    }

    if (admin > 0 && target != admin && !CanUserTarget(admin, target))
    {
        ReplyAdminTargetNotFound(admin, "target");
        return false;
    }

    return true;
}

public int MenuHandler_StoreAdminTarget(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowStoreAdminMenu(param1);
    }
    else if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        int target = GetClientOfUserId(StringToInt(info));

        if (!IsValidStoreAdminTarget(param1, target))
        {
            ShowStoreAdminTargetMenu(param1, g_AdminMenuAction[param1]);
            return 0;
        }

        g_iAdminMenuTarget[param1] = GetClientUserId(target);

        switch (g_AdminMenuAction[param1])
        {
            case StoreAdminAction_GiveCredits, StoreAdminAction_SetCredits:
            {
                ShowStoreAdminCreditAmountMenu(param1, g_AdminMenuAction[param1]);
            }
            case StoreAdminAction_ViewInventory:
            {
                ShowStoreAdminInventoryMenu(param1, target);
            }
            case StoreAdminAction_DebugPlayer:
            {
                PrintStoreDebugForTarget(param1, target);
                ShowStoreAdminTargetMenu(param1, StoreAdminAction_DebugPlayer);
            }
            case StoreAdminAction_DebugQuests:
            {
                PrintStoreQuestsDebugForTarget(param1, target);
                ShowStoreAdminTargetMenu(param1, StoreAdminAction_DebugQuests);
            }
            case StoreAdminAction_ExportProfile:
            {
                ExportStoreProfileForTarget(param1, target);
                ShowStoreAdminTargetMenu(param1, StoreAdminAction_ExportProfile);
            }
            case StoreAdminAction_AuditPlayer:
            {
                RequestStoreAudit(param1, target, 20, true);
                ShowStoreAdminTargetMenu(param1, StoreAdminAction_AuditPlayer);
            }
        }
    }

    return 0;
}

void AddStoreAdminCreditAmountMenuItem(Menu menu, StoreAdminAction action, const char[] amount, const char[] display)
{
    char info[24];
    Format(info, sizeof(info), "%d:%s", view_as<int>(action), amount);
    menu.AddItem(info, display);
}

bool ParseStoreAdminCreditAmountMenuInfo(const char[] info, StoreAdminAction &action, char[] amount, int maxlen)
{
    char parts[2][16];
    if (ExplodeString(info, ":", parts, sizeof(parts), sizeof(parts[])) != 2)
    {
        return false;
    }

    int actionValue = StringToInt(parts[0]);
    if (actionValue != view_as<int>(StoreAdminAction_GiveCredits) && actionValue != view_as<int>(StoreAdminAction_SetCredits))
    {
        return false;
    }

    action = view_as<StoreAdminAction>(actionValue);
    strcopy(amount, maxlen, parts[1]);
    return true;
}

void ShowStoreAdminCreditAmountMenu(int client, StoreAdminAction action, int firstItem = 0)
{
    int target = ResolveStoreAdminTarget(client);
    if (!IsValidStoreAdminTarget(client, target))
    {
        ShowStoreAdminTargetMenu(client, action);
        return;
    }

    g_AdminMenuAction[client] = action;

    char actionLabel[96], title[192], creditsText[32];
    FormatStoreAdminActionLabel(action, client, actionLabel, sizeof(actionLabel));
    FormatNumberDots(g_iCredits[target], creditsText, sizeof(creditsText));
    Format(title, sizeof(title), "%T", "Admin Amount Menu Title", client, actionLabel, target, creditsText);

    Menu menu = new Menu(MenuHandler_StoreAdminCreditAmount);
    menu.SetTitle(title);
    menu.ExitBackButton = true;

    if (action == StoreAdminAction_GiveCredits)
    {
        AddStoreAdminCreditAmountMenuItem(menu, action, "10", "+10");
        AddStoreAdminCreditAmountMenuItem(menu, action, "100", "+100");
        AddStoreAdminCreditAmountMenuItem(menu, action, "500", "+500");
        AddStoreAdminCreditAmountMenuItem(menu, action, "1000", "+1.000");
        AddStoreAdminCreditAmountMenuItem(menu, action, "5000", "+5.000");
        AddStoreAdminCreditAmountMenuItem(menu, action, "10000", "+10.000");

        char customLabel[96];
        Format(customLabel, sizeof(customLabel), "%T", "Admin Credit Custom", client);
        AddStoreAdminCreditAmountMenuItem(menu, action, "custom", customLabel);

        AddStoreAdminCreditAmountMenuItem(menu, action, "-10000", "-10.000");
        AddStoreAdminCreditAmountMenuItem(menu, action, "-5000", "-5.000");
        AddStoreAdminCreditAmountMenuItem(menu, action, "-1000", "-1.000");
        AddStoreAdminCreditAmountMenuItem(menu, action, "-500", "-500");
        AddStoreAdminCreditAmountMenuItem(menu, action, "-100", "-100");
        AddStoreAdminCreditAmountMenuItem(menu, action, "-10", "-10");
    }
    else if (action == StoreAdminAction_SetCredits)
    {
        char customLabel[96];
        Format(customLabel, sizeof(customLabel), "%T", "Admin Credit Custom", client);
        AddStoreAdminCreditAmountMenuItem(menu, action, "custom", customLabel);
        AddStoreAdminCreditAmountMenuItem(menu, action, "0", "0");
        AddStoreAdminCreditAmountMenuItem(menu, action, "10", "10");
        AddStoreAdminCreditAmountMenuItem(menu, action, "100", "100");
        AddStoreAdminCreditAmountMenuItem(menu, action, "500", "500");
        AddStoreAdminCreditAmountMenuItem(menu, action, "1000", "1.000");
        AddStoreAdminCreditAmountMenuItem(menu, action, "5000", "5.000");
        AddStoreAdminCreditAmountMenuItem(menu, action, "10000", "10.000");
    }

    if (firstItem > 0)
    {
        menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
    }
    else
    {
        menu.Display(client, MENU_TIME_FOREVER);
    }
}

bool ApplyStoreAdminCreditAmount(int admin, int target, StoreAdminAction action, int amount)
{
    if (!IsValidStoreAdminTarget(admin, target))
    {
        return false;
    }

    char amountText[32];
    FormatNumberDots(amount, amountText, sizeof(amountText));

    if (action == StoreAdminAction_GiveCredits)
    {
        if (!ApplyCreditDeltasAtomic(target, amount, "admin_menu_give", 0, 0, "", false, ""))
        {
            PrintStorePhrase(admin, "%T", "Admin Credit Failed", admin);
            return false;
        }

        LogAuditEvent(admin, target, "admin_menu_give_credits", "", amount, "");
        PrintStorePhrase(admin, "%T", "Admin Give Single", admin, amountText, target);
        return true;
    }

    if (action == StoreAdminAction_SetCredits)
    {
        if (amount < 0 || !SetCreditsAtomic(target, amount, "admin_menu_set", false))
        {
            PrintStorePhrase(admin, "%T", "Admin Credit Failed", admin);
            return false;
        }

        LogAuditEvent(admin, target, "admin_menu_set_credits", "", amount, "");
        PrintStorePhrase(admin, "%T", "Admin Set Single", admin, amountText, target);
        return true;
    }

    return false;
}

void PromptStoreAdminCreditAmount(int client, StoreAdminAction action)
{
    int target = ResolveStoreAdminTarget(client);
    if (!IsValidStoreAdminTarget(client, target))
    {
        ShowStoreAdminTargetMenu(client, action);
        return;
    }

    g_AdminMenuAction[client] = action;
    g_bAwaitingAdminCreditAmount[client] = true;

    char actionLabel[96];
    FormatStoreAdminActionLabel(action, client, actionLabel, sizeof(actionLabel));
    PrintStorePhrase(client, "%T", "Admin Credit Prompt", client, actionLabel, target);
}

Action HandleStoreAdminCreditAmountInput(int client, const char[] rawText)
{
    char text[192];
    strcopy(text, sizeof(text), rawText);
    TrimString(text);

    if (text[0] == '/')
    {
        strcopy(text, sizeof(text), text[1]);
        TrimString(text);
    }

    StoreAdminAction action = g_AdminMenuAction[client];
    int target = ResolveStoreAdminTarget(client);

    if (StrEqual(text, "cancel", false) || StrEqual(text, "cancelar", false))
    {
        g_bAwaitingAdminCreditAmount[client] = false;
        PrintStorePhrase(client, "%T", "Admin Credit Cancelled", client);
        ShowStoreAdminCreditAmountMenu(client, action);
        return Plugin_Handled;
    }

    if (!HasStoreAdminAccess(client) || (action != StoreAdminAction_GiveCredits && action != StoreAdminAction_SetCredits) || !IsValidStoreAdminTarget(client, target))
    {
        g_bAwaitingAdminCreditAmount[client] = false;
        return Plugin_Handled;
    }

    int amount = 0;
    bool validAmount = (action == StoreAdminAction_SetCredits)
        ? TryParseNonNegativeAmount(text, amount)
        : TryParseSignedCreditAmount(text, amount);

    if (!validAmount)
    {
        PrintStorePhrase(client, "%T", action == StoreAdminAction_SetCredits ? "Admin Credit Invalid Set" : "Admin Credit Invalid Signed", client);
        return Plugin_Handled;
    }

    g_bAwaitingAdminCreditAmount[client] = false;
    ApplyStoreAdminCreditAmount(client, target, action, amount);
    ShowStoreAdminCreditAmountMenu(client, action);
    return Plugin_Handled;
}

public int MenuHandler_StoreAdminCreditAmount(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowStoreAdminTargetMenu(param1, g_AdminMenuAction[param1]);
    }
    else if (action == MenuAction_Select)
    {
        int firstItem = GetMenuSelectionPosition();
        int target = ResolveStoreAdminTarget(param1);
        if (!IsValidStoreAdminTarget(param1, target))
        {
            ShowStoreAdminTargetMenu(param1, g_AdminMenuAction[param1]);
            return 0;
        }

        char info[24], amountText[16];
        menu.GetItem(param2, info, sizeof(info));
        StoreAdminAction creditAction;
        if (!ParseStoreAdminCreditAmountMenuInfo(info, creditAction, amountText, sizeof(amountText)))
        {
            ShowStoreAdminTargetMenu(param1, g_AdminMenuAction[param1]);
            return 0;
        }

        if (StrEqual(amountText, "custom"))
        {
            PromptStoreAdminCreditAmount(param1, creditAction);
            return 0;
        }

        ApplyStoreAdminCreditAmount(param1, target, creditAction, StringToInt(amountText));

        ShowStoreAdminCreditAmountMenu(param1, creditAction, firstItem);
    }

    return 0;
}

void ShowStoreAdminInventoryMenu(int client, int target)
{
    if (!IsValidStoreAdminTarget(client, target))
    {
        ShowStoreAdminTargetMenu(client, StoreAdminAction_ViewInventory);
        return;
    }

    g_iAdminMenuTarget[client] = GetClientUserId(target);

    Menu menu = new Menu(MenuHandler_StoreAdminInventory);
    char title[192];
    Format(title, sizeof(title), "%T", "Admin Inventory Category Title", client, target);
    menu.SetTitle(title);
    menu.ExitBackButton = true;

    AddStoreAdminInventoryCategoryItem(menu, client, target, "equipped", "Admin Inventory Category Equipped");
    AddStoreAdminInventoryCategoryItem(menu, client, target, "skins", "Store Category Skins");
    AddStoreAdminInventoryCategoryItem(menu, client, target, "chat", "Store Category Chat");
    AddStoreAdminInventoryCategoryItem(menu, client, target, "other", "Admin Inventory Category Other");

    menu.Display(client, MENU_TIME_FOREVER);
}

void ShowStoreAdminInventorySkinsMenu(int client, int target)
{
    if (!IsValidStoreAdminTarget(client, target))
    {
        ShowStoreAdminTargetMenu(client, StoreAdminAction_ViewInventory);
        return;
    }

    g_iAdminMenuTarget[client] = GetClientUserId(target);

    Menu menu = new Menu(MenuHandler_StoreAdminInventorySub);
    char title[192];
    Format(title, sizeof(title), "%T", "Admin Inventory Skins Title", client, target);
    menu.SetTitle(title);
    menu.ExitBackButton = true;

    AddStoreAdminInventoryCategoryItem(menu, client, target, "skin_2", "Inventory Teams Menu TT");
    AddStoreAdminInventoryCategoryItem(menu, client, target, "skin_3", "Inventory Teams Menu CT");

    menu.Display(client, MENU_TIME_FOREVER);
}

void ShowStoreAdminInventoryChatMenu(int client, int target)
{
    if (!IsValidStoreAdminTarget(client, target))
    {
        ShowStoreAdminTargetMenu(client, StoreAdminAction_ViewInventory);
        return;
    }

    g_iAdminMenuTarget[client] = GetClientUserId(target);

    Menu menu = new Menu(MenuHandler_StoreAdminInventorySub);
    char title[192];
    Format(title, sizeof(title), "%T", "Admin Inventory Chat Title", client, target);
    menu.SetTitle(title);
    menu.ExitBackButton = true;

    AddStoreAdminInventoryCategoryItem(menu, client, target, "tag", "Chat Menu Tags");
    AddStoreAdminInventoryCategoryItem(menu, client, target, "namecolor", "Chat Menu Name Colors");
    AddStoreAdminInventoryCategoryItem(menu, client, target, "chatcolor", "Chat Menu Chat Colors");

    menu.Display(client, MENU_TIME_FOREVER);
}

void AddStoreAdminInventoryCategoryItem(Menu menu, int client, int target, const char[] filter, const char[] phrase)
{
    int count = CountStoreAdminInventoryItems(target, filter);

    char label[96], display[128];
    Format(label, sizeof(label), "%T", phrase, client);
    Format(display, sizeof(display), "%s (%d)", label, count);
    menu.AddItem(filter, display, count > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
}

bool DoesStoreAdminInventoryItemMatchFilter(const char[] filter, const StoreItem item, bool equipped)
{
    if (StrEqual(filter, "all"))
    {
        return true;
    }

    if (StrEqual(filter, "equipped"))
    {
        return equipped;
    }

    if (StrEqual(filter, "skins"))
    {
        return StrEqual(item.type, "skin");
    }

    if (StrEqual(filter, "chat"))
    {
        return IsBuiltinChatCosmeticType(item.type);
    }

    if (StrEqual(filter, "other"))
    {
        return !StrEqual(item.type, "skin") && !IsBuiltinChatCosmeticType(item.type);
    }

    return DoesInventoryItemMatchFilter(filter, item);
}

int CountStoreAdminInventoryItems(int target, const char[] filter)
{
    if (g_hInventory[target] == null || g_aItems == null)
    {
        return 0;
    }

    int count = 0;
    StoreItem item;
    for (int i = 0; i < g_aItems.Length; i++)
    {
        g_aItems.GetArray(i, item, sizeof(StoreItem));
        int invIndex = FindInventoryIndexByItemId(target, item.id);
        if (invIndex == -1)
        {
            continue;
        }

        InventoryItem inv;
        g_hInventory[target].GetArray(invIndex, inv, sizeof(InventoryItem));
        if (DoesStoreAdminInventoryItemMatchFilter(filter, item, view_as<bool>(inv.is_equipped)))
        {
            count++;
        }
    }

    return count;
}

void AddStoreAdminInventoryItemsToMenu(int target, Menu menu, const char[] filter, bool equippedOnly, int &itemsAdded)
{
    if (g_hInventory[target] == null || g_aItems == null)
    {
        return;
    }

    StoreItem item;
    InventoryItem inv;
    for (int i = 0; i < g_aItems.Length; i++)
    {
        g_aItems.GetArray(i, item, sizeof(StoreItem));
        int invIndex = FindInventoryIndexByItemId(target, item.id);
        if (invIndex == -1)
        {
            continue;
        }

        g_hInventory[target].GetArray(invIndex, inv, sizeof(InventoryItem));
        bool equipped = view_as<bool>(inv.is_equipped);
        if (equipped != equippedOnly || !DoesStoreAdminInventoryItemMatchFilter(filter, item, equipped))
        {
            continue;
        }

        char display[160];
        if (equipped)
        {
            Format(display, sizeof(display), "[E] %s [%s]", item.name, item.type);
        }
        else
        {
            Format(display, sizeof(display), "%s [%s]", item.name, item.type);
        }

        menu.AddItem(item.id, display);
        itemsAdded++;
    }
}

void ShowStoreAdminInventoryListMenu(int client, int target, const char[] filter)
{
    if (!IsValidStoreAdminTarget(client, target))
    {
        ShowStoreAdminTargetMenu(client, StoreAdminAction_ViewInventory);
        return;
    }

    g_iAdminMenuTarget[client] = GetClientUserId(target);
    strcopy(g_szInvFilter[client], sizeof(g_szInvFilter[]), filter);

    char filterName[96], title[192];
    FormatStoreAdminInventoryFilterName(client, filter, filterName, sizeof(filterName));
    Format(title, sizeof(title), "%T", "Admin Inventory List Title", client, target, filterName);

    Menu menu = new Menu(MenuHandler_StoreAdminInventoryList);
    menu.SetTitle(title);
    menu.ExitBackButton = true;

    int itemsAdded = 0;
    AddStoreAdminInventoryItemsToMenu(target, menu, filter, true, itemsAdded);
    AddStoreAdminInventoryItemsToMenu(target, menu, filter, false, itemsAdded);

    if (itemsAdded == 0)
    {
        char emptyLabel[128];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "Admin Inventory Empty", client);
        menu.AddItem("empty", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_StoreAdminInventory(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowStoreAdminTargetMenu(param1, StoreAdminAction_ViewInventory);
    }
    else if (action == MenuAction_Select)
    {
        char filter[32];
        menu.GetItem(param2, filter, sizeof(filter));
        if (StrEqual(filter, "skins"))
        {
            ShowStoreAdminInventorySkinsMenu(param1, ResolveStoreAdminTarget(param1));
        }
        else if (StrEqual(filter, "chat"))
        {
            ShowStoreAdminInventoryChatMenu(param1, ResolveStoreAdminTarget(param1));
        }
        else
        {
            ShowStoreAdminInventoryListMenu(param1, ResolveStoreAdminTarget(param1), filter);
        }
    }

    return 0;
}

public int MenuHandler_StoreAdminInventorySub(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowStoreAdminInventoryMenu(param1, ResolveStoreAdminTarget(param1));
    }
    else if (action == MenuAction_Select)
    {
        char filter[32];
        menu.GetItem(param2, filter, sizeof(filter));
        ShowStoreAdminInventoryListMenu(param1, ResolveStoreAdminTarget(param1), filter);
    }

    return 0;
}

void ShowStoreAdminInventoryParentMenuForFilter(int client, int target, const char[] filter)
{
    if (StrEqual(filter, "skin_2") || StrEqual(filter, "skin_3"))
    {
        ShowStoreAdminInventorySkinsMenu(client, target);
        return;
    }

    if (StrEqual(filter, "tag") || StrEqual(filter, "namecolor") || StrEqual(filter, "chatcolor"))
    {
        ShowStoreAdminInventoryChatMenu(client, target);
        return;
    }

    ShowStoreAdminInventoryMenu(client, target);
}

public int MenuHandler_StoreAdminInventoryList(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowStoreAdminInventoryParentMenuForFilter(param1, ResolveStoreAdminTarget(param1), g_szInvFilter[param1]);
    }
    else if (action == MenuAction_Select)
    {
        char itemId[32];
        menu.GetItem(param2, itemId, sizeof(itemId));
        if (!StrEqual(itemId, "empty"))
        {
            ShowStoreAdminInventoryItemMenu(param1, ResolveStoreAdminTarget(param1), itemId);
        }
    }

    return 0;
}

void FormatStoreAdminInventoryFilterName(int client, const char[] filter, char[] buffer, int maxlength)
{
    if (StrEqual(filter, "equipped"))
    {
        Format(buffer, maxlength, "%T", "Admin Inventory Category Equipped", client);
        return;
    }

    if (StrEqual(filter, "skins"))
    {
        Format(buffer, maxlength, "%T", "Store Category Skins", client);
        return;
    }

    if (StrEqual(filter, "chat"))
    {
        Format(buffer, maxlength, "%T", "Store Category Chat", client);
        return;
    }

    if (StrEqual(filter, "skin_2"))
    {
        Format(buffer, maxlength, "%T", "Inventory Teams Menu TT", client);
        return;
    }

    if (StrEqual(filter, "skin_3"))
    {
        Format(buffer, maxlength, "%T", "Inventory Teams Menu CT", client);
        return;
    }

    if (StrEqual(filter, "tag"))
    {
        Format(buffer, maxlength, "%T", "Chat Menu Tags", client);
        return;
    }

    if (StrEqual(filter, "namecolor"))
    {
        Format(buffer, maxlength, "%T", "Chat Menu Name Colors", client);
        return;
    }

    if (StrEqual(filter, "chatcolor"))
    {
        Format(buffer, maxlength, "%T", "Chat Menu Chat Colors", client);
        return;
    }

    if (StrEqual(filter, "other"))
    {
        Format(buffer, maxlength, "%T", "Admin Inventory Category Other", client);
        return;
    }

    Format(buffer, maxlength, "%T", "Admin Inventory Category All", client);
}

void ShowStoreAdminInventoryItemMenu(int client, int target, const char[] itemId)
{
    if (!IsValidStoreAdminTarget(client, target))
    {
        ShowStoreAdminTargetMenu(client, StoreAdminAction_ViewInventory);
        return;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        PrintStorePhrase(client, "%T", "Item Not Found", client);
        ShowStoreAdminInventoryListMenu(client, target, g_szInvFilter[client]);
        return;
    }

    int invIndex = FindInventoryIndexByItemId(target, itemId);
    if (invIndex == -1)
    {
        PrintStorePhrase(client, "%T", "Item Not In Inventory", client);
        ShowStoreAdminInventoryListMenu(client, target, g_szInvFilter[client]);
        return;
    }

    InventoryItem inv;
    g_hInventory[target].GetArray(invIndex, inv, sizeof(InventoryItem));
    bool equipped = view_as<bool>(inv.is_equipped);

    char stateText[64], title[192];
    Format(stateText, sizeof(stateText), "%T", equipped ? "Item State Equipped" : "Item State Inventory", client);
    Format(title, sizeof(title), "%T", "Admin Inventory Item Title", client, target, item.name, item.type, stateText);

    Menu menu = new Menu(MenuHandler_StoreAdminInventoryItem);
    menu.SetTitle(title);
    menu.ExitBackButton = true;

    if (IsItemTypeEquippable(item.type))
    {
        char label[96];
        Format(label, sizeof(label), "%T", equipped ? "Admin Inventory Unequip Item" : "Admin Inventory Equip Item", client);
        menu.AddItem(item.id, label);
    }
    else
    {
        char label[96];
        Format(label, sizeof(label), "%T", "Admin Inventory Not Equippable", client);
        menu.AddItem("not_equippable", label, ITEMDRAW_DISABLED);
    }

    char idLine[128];
    Format(idLine, sizeof(idLine), "ID: %s", item.id);
    menu.AddItem("id", idLine, ITEMDRAW_DISABLED);
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_StoreAdminInventoryItem(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowStoreAdminInventoryListMenu(param1, ResolveStoreAdminTarget(param1), g_szInvFilter[param1]);
    }
    else if (action == MenuAction_Select)
    {
        char itemId[32];
        menu.GetItem(param2, itemId, sizeof(itemId));
        if (StrEqual(itemId, "id") || StrEqual(itemId, "not_equippable"))
        {
            return 0;
        }

        int target = ResolveStoreAdminTarget(param1);
        if (!IsValidStoreAdminTarget(param1, target))
        {
            return 0;
        }

        int invIndex = FindInventoryIndexByItemId(target, itemId);
        if (invIndex == -1)
        {
            PrintStorePhrase(param1, "%T", "Item Not In Inventory", param1);
            ShowStoreAdminInventoryListMenu(param1, target, g_szInvFilter[param1]);
            return 0;
        }

        InventoryItem inv;
        g_hInventory[target].GetArray(invIndex, inv, sizeof(InventoryItem));
        bool equipNow = !view_as<bool>(inv.is_equipped);

        if (SetItemEquipped(target, itemId, equipNow, false, false, true))
        {
            LogAuditEvent(param1, target, equipNow ? "admin_equip_item" : "admin_unequip_item", itemId, 0, "");
            PrintStorePhrase(param1, "%T", equipNow ? "Admin Inventory Equipped Item" : "Admin Inventory Unequipped Item", param1, target);
        }
        else
        {
            PrintStorePhrase(param1, "%T", "Admin Inventory Toggle Failed", param1);
        }

        ShowStoreAdminInventoryItemMenu(param1, target, itemId);
    }

    return 0;
}

void PrintStoreDebugForTarget(int client, int target)
{
    char steamid[32], creditsText[32], amountTextA[32], amountTextB[32];
    StoreProfileSnapshot snapshot;
    BuildProfileSnapshot(target, snapshot);
    GetClientSteamIdSafe(target, steamid, sizeof(steamid));

    ReplyStorePhrase(client, "%T", "Admin Debug Header", client, target, steamid);
    ReplyStorePhrase(client, "%T", "Admin Debug Identity", client,
        g_bIsLoaded[target], g_bIsLoading[target], snapshot.credits, snapshot.owned_items, snapshot.equipped_items);

    FormatNumberDots(snapshot.credits_earned, amountTextA, sizeof(amountTextA));
    FormatNumberDots(snapshot.credits_spent, amountTextB, sizeof(amountTextB));
    ReplyStorePhrase(client, "%T", "Admin Debug Economy", client,
        amountTextA, amountTextB, snapshot.purchases_total, snapshot.sales_total, snapshot.gifts_sent, snapshot.gifts_received, snapshot.trades_completed);

    FormatNumberDots(snapshot.total_casino_profit, creditsText, sizeof(creditsText));
    ReplyStorePhrase(client, "%T", "Admin Debug Progress", client,
        snapshot.daily_best_streak, snapshot.quests_completed, snapshot.total_casino_activity, creditsText);

    FormatNumberDots(snapshot.blackjack_profit, amountTextA, sizeof(amountTextA));
    FormatNumberDots(snapshot.coinflip_profit, amountTextB, sizeof(amountTextB));
    ReplyStorePhrase(client, "%T", "Admin Debug Casino A", client,
        snapshot.blackjack_games, amountTextA, snapshot.coinflip_games, amountTextB);

    FormatNumberDots(snapshot.crash_profit, amountTextA, sizeof(amountTextA));
    FormatNumberDots(snapshot.roulette_profit, amountTextB, sizeof(amountTextB));
    ReplyStorePhrase(client, "%T", "Admin Debug Casino B", client,
        snapshot.crash_rounds, amountTextA, snapshot.roulette_games, amountTextB);
}

void PrintStoreQuestsDebugForTarget(int client, int target)
{
    ArrayList questRows = new ArrayList(sizeof(StoreQuestProgressSnapshot));
    StringMap questIndex = new StringMap();
    int completedCount = 0;
    LoadQuestProgressSnapshot(target, questRows, questIndex, completedCount);

    ReplyStorePhrase(client, "%T", "Admin Quests Debug Header", client, target);
    ReplyStorePhrase(client, "%T", "Admin Quests Debug Summary", client, (g_aQuestDefinitions != null) ? g_aQuestDefinitions.Length : 0, completedCount);

    if (g_aQuestDefinitions != null)
    {
        StoreQuestDefinition definition;
        for (int i = 0; i < g_aQuestDefinitions.Length; i++)
        {
            g_aQuestDefinitions.GetArray(i, definition, sizeof(StoreQuestDefinition));

            int progress = 0, completedAt = 0, rewardedAt = 0, completionCount = 0;
            GetQuestSnapshotState(questRows, questIndex, definition.id, progress, completedAt, rewardedAt, completionCount);

            bool lockedByWindow = false;
            bool lockedByRequirement = false;
            bool maxedOut = false;
            GetQuestAvailabilityStateFromSnapshot(definition, rewardedAt, completionCount, questRows, questIndex, lockedByWindow, lockedByRequirement, maxedOut);

            ReplyStorePhrase(client, "%T", "Admin Quest Debug Entry", client,
                definition.id, progress, definition.goal, (rewardedAt > 0), definition.repeatable, completionCount, definition.max_completions,
                lockedByWindow, lockedByRequirement, maxedOut);
        }
    }

    delete questRows;
    delete questIndex;
}

void ExportStoreProfileForTarget(int client, int target)
{
    char filePath[PLATFORM_MAX_PATH];
    if (!ExportProfileSnapshotInternal(client, target, filePath, sizeof(filePath)))
    {
        ReplyStoreAdminUsage(client, "Admin Export Failed");
        return;
    }

    ReplyStorePhrase(client, "%T", "Admin Export Target Success", client, target, filePath);
}

public Action Cmd_GiveCredits(int client, int args)
{
    if (args < 2)
    {
        ReplyStorePhrase(client, "%T", "Admin Give Usage", client);
        return Plugin_Handled;
    }

    char arg1[64], arg2[16];
    GetCmdArg(1, arg1, sizeof(arg1));
    GetCmdArg(2, arg2, sizeof(arg2));

    int amount = 0;
    if (!TryParseCreditAmount(arg2, amount))
    {
        ReplyStorePhrase(client, "%T", "Admin Amount Positive", client);
        return Plugin_Handled;
    }

    int targets[MAXPLAYERS];
    int count = 0;
    if (!TryResolveCreditTargets(client, arg1, targets, count))
    {
        ReplyAdminTargetNotFound(client, arg1);
        return Plugin_Handled;
    }

    for (int i = 0; i < count; i++)
    {
        int target = targets[i];
        if (ApplyCreditDeltasAtomic(target, amount, "admin_give", 0, 0, "", false, ""))
        {
            LogAuditEvent(client, target, "admin_give_credits", "", amount, "");
        }
    }

    char amountText[32];
    FormatNumberDots(amount, amountText, sizeof(amountText));

    if (count == 1)
    {
        ReplyStorePhrase(client, "%T", "Admin Give Single", client, amountText, targets[0]);
    }
    else
    {
        ReplyStorePhrase(client, "%T", "Admin Give Multi", client, amountText, count);
    }

    return Plugin_Handled;
}

public Action Cmd_SetCredits(int client, int args)
{
    if (args < 2)
    {
        ReplyStorePhrase(client, "%T", "Admin Set Usage", client);
        return Plugin_Handled;
    }

    char arg1[64], arg2[16];
    GetCmdArg(1, arg1, sizeof(arg1));
    GetCmdArg(2, arg2, sizeof(arg2));

    int amount = 0;
    if (!TryParseNonNegativeAmount(arg2, amount))
    {
        ReplyStorePhrase(client, "%T", "Admin Amount NonNegative", client);
        return Plugin_Handled;
    }

    int targets[MAXPLAYERS];
    int count = 0;
    if (!TryResolveCreditTargets(client, arg1, targets, count))
    {
        ReplyAdminTargetNotFound(client, arg1);
        return Plugin_Handled;
    }

    for (int i = 0; i < count; i++)
    {
        int target = targets[i];
        if (SetCreditsAtomic(target, amount, "admin_set", false))
        {
            LogAuditEvent(client, target, "admin_set_credits", "", amount, "");
        }
    }

    char amountText[32];
    FormatNumberDots(amount, amountText, sizeof(amountText));

    if (count == 1)
    {
        ReplyStorePhrase(client, "%T", "Admin Set Single", client, amountText, targets[0]);
    }
    else
    {
        ReplyStorePhrase(client, "%T", "Admin Set Multi", client, amountText, count);
    }

    return Plugin_Handled;
}

public Action Cmd_StoreDebug(int client, int args)
{
    if (args < 1)
    {
        ReplyStoreAdminUsage(client, "Admin Debug Usage");
        return Plugin_Handled;
    }

    char argTarget[64], steamid[32], creditsText[32], amountTextA[32], amountTextB[32];
    GetCmdArg(1, argTarget, sizeof(argTarget));

    int target = 0;
    if (!ResolveSingleStoreTarget(client, argTarget, target))
    {
        ReplyAdminTargetNotFound(client, argTarget);
        return Plugin_Handled;
    }

    StoreProfileSnapshot snapshot;
    BuildProfileSnapshot(target, snapshot);
    GetClientSteamIdSafe(target, steamid, sizeof(steamid));

    ReplyStorePhrase(client, "%T", "Admin Debug Header", client, target, steamid);
    ReplyStorePhrase(client, "%T", "Admin Debug Identity", client,
        g_bIsLoaded[target], g_bIsLoading[target], snapshot.credits, snapshot.owned_items, snapshot.equipped_items);

    FormatNumberDots(snapshot.credits_earned, amountTextA, sizeof(amountTextA));
    FormatNumberDots(snapshot.credits_spent, amountTextB, sizeof(amountTextB));
    ReplyStorePhrase(client, "%T", "Admin Debug Economy", client,
        amountTextA, amountTextB, snapshot.purchases_total, snapshot.sales_total, snapshot.gifts_sent, snapshot.gifts_received, snapshot.trades_completed);

    FormatNumberDots(snapshot.total_casino_profit, creditsText, sizeof(creditsText));
    ReplyStorePhrase(client, "%T", "Admin Debug Progress", client,
        snapshot.daily_best_streak, snapshot.quests_completed, snapshot.total_casino_activity, creditsText);

    FormatNumberDots(snapshot.blackjack_profit, amountTextA, sizeof(amountTextA));
    FormatNumberDots(snapshot.coinflip_profit, amountTextB, sizeof(amountTextB));
    ReplyStorePhrase(client, "%T", "Admin Debug Casino A", client,
        snapshot.blackjack_games, amountTextA, snapshot.coinflip_games, amountTextB);

    FormatNumberDots(snapshot.crash_profit, amountTextA, sizeof(amountTextA));
    FormatNumberDots(snapshot.roulette_profit, amountTextB, sizeof(amountTextB));
    ReplyStorePhrase(client, "%T", "Admin Debug Casino B", client,
        snapshot.crash_rounds, amountTextA, snapshot.roulette_games, amountTextB);
    return Plugin_Handled;
}

public Action Cmd_StoreQuestsDebug(int client, int args)
{
    if (args < 1)
    {
        ReplyStoreAdminUsage(client, "Admin Quests Debug Usage");
        return Plugin_Handled;
    }

    char argTarget[64];
    GetCmdArg(1, argTarget, sizeof(argTarget));

    int target = 0;
    if (!ResolveSingleStoreTarget(client, argTarget, target))
    {
        ReplyAdminTargetNotFound(client, argTarget);
        return Plugin_Handled;
    }

    ArrayList questRows = new ArrayList(sizeof(StoreQuestProgressSnapshot));
    StringMap questIndex = new StringMap();
    int completedCount = 0;
    LoadQuestProgressSnapshot(target, questRows, questIndex, completedCount);

    ReplyStorePhrase(client, "%T", "Admin Quests Debug Header", client, target);
    ReplyStorePhrase(client, "%T", "Admin Quests Debug Summary", client, (g_aQuestDefinitions != null) ? g_aQuestDefinitions.Length : 0, completedCount);

    if (g_aQuestDefinitions != null)
    {
        StoreQuestDefinition definition;
        for (int i = 0; i < g_aQuestDefinitions.Length; i++)
        {
            g_aQuestDefinitions.GetArray(i, definition, sizeof(StoreQuestDefinition));

            int progress = 0, completedAt = 0, rewardedAt = 0, completionCount = 0;
            GetQuestSnapshotState(questRows, questIndex, definition.id, progress, completedAt, rewardedAt, completionCount);

            bool lockedByWindow = false;
            bool lockedByRequirement = false;
            bool maxedOut = false;
            GetQuestAvailabilityStateFromSnapshot(definition, rewardedAt, completionCount, questRows, questIndex, lockedByWindow, lockedByRequirement, maxedOut);

            ReplyStorePhrase(client, "%T", "Admin Quest Debug Entry", client,
                definition.id, progress, definition.goal, (rewardedAt > 0), definition.repeatable, completionCount, definition.max_completions,
                lockedByWindow, lockedByRequirement, maxedOut);
        }
    }

    delete questRows;
    delete questIndex;
    return Plugin_Handled;
}

public Action Cmd_StoreExportTarget(int client, int args)
{
    if (args < 1)
    {
        ReplyStoreAdminUsage(client, "Admin Export Usage");
        return Plugin_Handled;
    }

    char argTarget[64];
    GetCmdArg(1, argTarget, sizeof(argTarget));

    int target = 0;
    if (!ResolveSingleStoreTarget(client, argTarget, target))
    {
        ReplyAdminTargetNotFound(client, argTarget);
        return Plugin_Handled;
    }

    char filePath[PLATFORM_MAX_PATH];
    if (!ExportProfileSnapshotInternal(client, target, filePath, sizeof(filePath)))
    {
        ReplyStoreAdminUsage(client, "Admin Export Failed");
        return Plugin_Handled;
    }

    ReplyStorePhrase(client, "%T", "Admin Export Target Success", client, target, filePath);
    return Plugin_Handled;
}

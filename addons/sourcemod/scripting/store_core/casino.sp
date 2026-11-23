// Umbrella Store core: Casino module registry and casino menu.
// Included by store_core.sp.

void RebuildCasinoIndex()
{
    if (g_mCasinoIndex == null)
    {
        g_mCasinoIndex = new StringMap();
    }
    else
    {
        g_mCasinoIndex.Clear();
    }

    if (g_aCasinoIds == null)
    {
        return;
    }

    char id[32];
    for (int i = 0; i < g_aCasinoIds.Length; i++)
    {
        g_aCasinoIds.GetString(i, id, sizeof(id));
        if (id[0] != '\0')
        {
            g_mCasinoIndex.SetValue(id, i);
        }
    }
}

bool CasinoRegisterEntry(const char[] id, const char[] title, const char[] command)
{
    if (id[0] == '\0' || title[0] == '\0' || command[0] == '\0')
    {
        return false;
    }

    if (g_aCasinoIds == null)
    {
        g_aCasinoIds = new ArrayList(32);
    }

    if (g_mCasinoTitles == null)
    {
        g_mCasinoTitles = new StringMap();
    }

    if (g_mCasinoCommands == null)
    {
        g_mCasinoCommands = new StringMap();
    }

    if (g_mCasinoIndex == null)
    {
        g_mCasinoIndex = new StringMap();
    }

    int index;
    if (g_mCasinoIndex.GetValue(id, index))
    {
        if (index < 0 || index >= g_aCasinoIds.Length)
        {
            RebuildCasinoIndex();
            if (g_mCasinoIndex.GetValue(id, index) && index >= 0 && index < g_aCasinoIds.Length)
            {
                g_mCasinoTitles.SetString(id, title);
                g_mCasinoCommands.SetString(id, command);
                return true;
            }
        }
        else
        {
            g_mCasinoTitles.SetString(id, title);
            g_mCasinoCommands.SetString(id, command);
            return true;
        }
    }

    int pushed = g_aCasinoIds.PushString(id);
    if (pushed < 0)
    {
        return false;
    }

    g_mCasinoIndex.SetValue(id, pushed);
    g_mCasinoTitles.SetString(id, title);
    g_mCasinoCommands.SetString(id, command);
    return true;
}

bool CasinoUnregisterEntry(const char[] id)
{
    if (g_aCasinoIds == null || g_mCasinoIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mCasinoIndex.GetValue(id, index))
    {
        return false;
    }

    if (index < 0 || index >= g_aCasinoIds.Length)
    {
        RebuildCasinoIndex();
        if (!g_mCasinoIndex.GetValue(id, index) || index < 0 || index >= g_aCasinoIds.Length)
        {
            return false;
        }
    }

    g_aCasinoIds.Erase(index);
    if (g_mCasinoTitles != null)
    {
        g_mCasinoTitles.Remove(id);
    }
    if (g_mCasinoCommands != null)
    {
        g_mCasinoCommands.Remove(id);
    }
    RebuildCasinoIndex();
    return true;
}

void ShowCasinoMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Casino);
    char title[128];
    char soonLabel[64];

    Format(title, sizeof(title), "%T", "Casino Menu Title", client);
    Format(soonLabel, sizeof(soonLabel), "%T", "Casino Menu Soon", client);

    menu.SetTitle(title);

    if (g_aCasinoIds == null || g_aCasinoIds.Length == 0)
    {
        menu.AddItem("none", soonLabel, ITEMDRAW_DISABLED);
    }
    else
    {
        int added = 0;
        char id[32];
        char entryTitle[64];

        for (int i = 0; i < g_aCasinoIds.Length; i++)
        {
            g_aCasinoIds.GetString(i, id, sizeof(id));
            if (id[0] == '\0')
            {
                continue;
            }

            if (g_mCasinoTitles == null || !g_mCasinoTitles.GetString(id, entryTitle, sizeof(entryTitle)))
            {
                strcopy(entryTitle, sizeof(entryTitle), id);
            }

            menu.AddItem(id, entryTitle);
            added++;
        }

        if (added == 0)
        {
            menu.AddItem("none", soonLabel, ITEMDRAW_DISABLED);
        }
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Casino(Menu menu, MenuAction action, int param1, int param2)
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

        if (StrEqual(info, "none"))
        {
            return 0;
        }

        char command[64];
        if (g_mCasinoCommands != null && g_mCasinoCommands.GetString(info, command, sizeof(command)) && command[0] != '\0')
        {
            FakeClientCommand(param1, "%s", command);
        }
    }

    return 0;
}

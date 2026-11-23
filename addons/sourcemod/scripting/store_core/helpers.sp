// Umbrella Store core: General helpers: client validation, access checks, store state.
// Included by store_core.sp.

bool IsValidClientConnected(int client)
{
    return (client > 0 && client <= MaxClients && IsClientConnected(client) && !IsFakeClient(client));
}

bool IsValidHumanClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

bool IsStoreEnabled()
{
    return (gCvarStoreEnabled == null || gCvarStoreEnabled.BoolValue);
}

bool EnsureStoreEnabledForClient(int client, bool notify = true)
{
    if (IsStoreEnabled())
    {
        return true;
    }

    if (notify && IsValidHumanClient(client))
    {
        PrintStorePhrase(client, "%T", "Store Disabled", client);
    }

    return false;
}

void ResetClientData(int client, bool clearInventory)
{
    if (g_mInventoryOwned[client] == null)
    {
        g_mInventoryOwned[client] = new StringMap();
    }
    else
    {
        g_mInventoryOwned[client].Clear();
    }

    g_iCredits[client] = 0;
    g_bIsLoaded[client] = false;
    g_bIsLoading[client] = false;
    g_bDetailFromInventory[client] = false;
    g_bDetailFromSearch[client] = false;
    g_szBrowseType[client][0] = '\0';
    g_iBrowseTeam[client] = 0;
    g_szBrowseCategory[client][0] = '\0';
    g_szInvFilter[client][0] = '\0';
    g_szSearchQuery[client][0] = '\0';
    g_szLastDetailItem[client][0] = '\0';
    g_bCreditsDirty[client] = false;
    g_iInventoryVersion[client] = 0;
    g_iMenuInventoryVersion[client] = 0;
    g_iTradeSenderInvVersion[client] = 0;
    g_iTradeTargetInvVersion[client] = 0;
    g_iPendingTradeTargetInvVersion[client] = 0;
    g_szPendingTradeSenderItem[client][0] = '\0';
    g_bAwaitingMarketPrice[client] = false;
    g_szPendingMarketItem[client][0] = '\0';
    g_AdminMenuAction[client] = StoreAdminAction_None;
    g_iAdminMenuTarget[client] = 0;
    g_bAwaitingAdminCreditAmount[client] = false;
    g_fLastActivity[client] = GetGameTime();
    g_iCreditReasonTime[client] = 0;
    g_iCreditReasonKill[client] = 0;
    g_iCreditReasonHeadshot[client] = 0;
    g_iCreditReasonRoundWin[client] = 0;
    g_iCreditReasonPlant[client] = 0;
    g_iCreditReasonDefuse[client] = 0;
    g_fNextPreview[client] = 0.0;
    g_fNextEquipTime[client] = 0.0;
    g_szDefaultPlayerModel[client][0] = '\0';

    if (g_hCreditNotifyTimer[client] != null)
    {
        KillTimer(g_hCreditNotifyTimer[client]);
        g_hCreditNotifyTimer[client] = null;
    }

    if (g_hPreviewTimer[client] != null)
    {
        KillTimer(g_hPreviewTimer[client]);
        g_hPreviewTimer[client] = null;
    }

    RemovePreview(client);
    g_iPreviewEntity[client] = INVALID_ENT_REFERENCE;

    if (clearInventory && g_hInventory[client] != null)
    {
        delete g_hInventory[client];
        g_hInventory[client] = null;
    }
}

bool HasAccess(int client, const char[] flagString)
{
    if (flagString[0] == '\0')
    {
        return true;
    }

    int flags = ReadFlagString(flagString);
    return CheckCommandAccess(client, "", flags, true);
}

void LogStoreError(const char[] where, const char[] error)
{
    if (error[0] != '\0')
    {
        LogError("%s %s: %s", STORE_LOG_PREFIX, where, error);
    }
}

bool GetClientSteamIdSafe(int client, char[] steamid, int maxlen)
{
    if (!GetClientAuthId(client, AuthId_Steam2, steamid, maxlen))
    {
        steamid[0] = '\0';
        return false;
    }

    return true;
}

int GetOnlineClientBySteamId(const char[] steamid)
{
    char currentSteamId[32];
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanClient(i) || !g_bIsLoaded[i])
        {
            continue;
        }

        if (GetClientSteamIdSafe(i, currentSteamId, sizeof(currentSteamId)) && StrEqual(currentSteamId, steamid))
        {
            return i;
        }
    }

    return 0;
}

void SanitizeFilenameComponent(const char[] input, char[] output, int maxlen)
{
    int len = strlen(input);
    int out = 0;

    for (int i = 0; i < len && out < maxlen - 1; i++)
    {
        int c = input[i];
        if ((c >= 'a' && c <= 'z')
            || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9')
            || c == '_'
            || c == '-'
            || c == '.')
        {
            output[out++] = c;
        }
        else
        {
            output[out++] = '_';
        }
    }

    if (out == 0 && maxlen > 1)
    {
        output[out++] = '0';
    }

    output[out] = '\0';
}

public void OnStoreEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    bool enabled = StringToInt(newValue) != 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanClient(i))
        {
            continue;
        }

        RemovePreview(i);

        if (!IsPlayerAlive(i))
        {
            continue;
        }

        if (enabled && ArePlayerSkinsEnabled())
        {
            ApplyPlayerSkin(i);
        }
        else if (!enabled)
        {
            ResetPlayerModelToDefault(i);
        }
    }

    ForwardStoreEnabledChanged(enabled);
}

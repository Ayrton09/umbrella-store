// Umbrella Store core: Equip logic, team rules, and player skins.
// Included by store_core.sp.

bool GetEquippedItemByType(int client, const char[] type, char[] itemId, int maxlen)
{
    itemId[0] = '\0';

    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null || type[0] == '\0')
    {
        return false;
    }

    InventoryItem inv;
    StoreItem item;
    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (!inv.is_equipped)
        {
            continue;
        }

        if (!FindStoreItemById(inv.item_id, item))
        {
            continue;
        }

        if (StrEqual(item.type, type))
        {
            strcopy(itemId, maxlen, item.id);
            return true;
        }
    }

    return false;
}

int CountEquippedItems(int client)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null)
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

bool CanEquipItemEx(int client, const char[] itemId, char[] reason, int maxlen, bool respectCooldown = false)
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

    if (!g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        SetReason(reason, maxlen, "client_not_loaded");
        return false;
    }

    if (respectCooldown)
    {
        float cooldown = (gCvarEquipCooldown != null) ? gCvarEquipCooldown.FloatValue : 0.0;
        if (cooldown > 0.0 && GetGameTime() < g_fNextEquipTime[client])
        {
            SetReason(reason, maxlen, "equip_cooldown");
            return false;
        }
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        SetReason(reason, maxlen, "item_not_found");
        return false;
    }

    if (!PlayerOwnsItem(client, item.id))
    {
        SetReason(reason, maxlen, "item_not_owned");
        return false;
    }

    if (!CanPlayerUseItem(client, item, false))
    {
        SetReason(reason, maxlen, "item_not_usable");
        return false;
    }

    if (!IsItemTypeEquippable(item.type))
    {
        SetReason(reason, maxlen, "type_not_equippable");
        return false;
    }

    if (StrEqual(item.type, "skin") && !ArePlayerSkinsEnabled())
    {
        SetReason(reason, maxlen, "player_skins_disabled");
        return false;
    }

    SetReason(reason, maxlen, "ok");
    return true;
}

bool IsAnyStoreTeam(int team)
{
    return team == 0 || team == 4;
}

bool StoreItemTeamMatches(int itemTeam, int clientTeam)
{
    return IsAnyStoreTeam(itemTeam) || itemTeam == clientTeam;
}

bool StoreItemTeamsCanConflict(int firstTeam, int secondTeam)
{
    return IsAnyStoreTeam(firstTeam) || IsAnyStoreTeam(secondTeam) || firstTeam == secondTeam;
}

bool ShouldUnequipSameCategory(StoreItem targetItem, StoreItem otherItem)
{
    if (StrEqual(targetItem.type, "pet") && StrEqual(otherItem.type, "pet"))
    {
        return true;
    }

    if (StrEqual(targetItem.type, "skin") && StrEqual(otherItem.type, "skin"))
    {
        return StoreItemTeamsCanConflict(targetItem.team, otherItem.team);
    }

    if (StrEqual(targetItem.type, "tag") && StrEqual(otherItem.type, "tag"))
    {
        return true;
    }

    if (StrEqual(targetItem.type, "namecolor") && StrEqual(otherItem.type, "namecolor"))
    {
        return true;
    }

    if (StrEqual(targetItem.type, "chatcolor") && StrEqual(otherItem.type, "chatcolor"))
    {
        return true;
    }

    if (IsItemTypeExclusive(targetItem.type) && StrEqual(targetItem.type, otherItem.type))
    {
        return StoreItemTeamsCanConflict(targetItem.team, otherItem.team);
    }

    char targetCategory[32], otherCategory[32];
    GetItemCategory(targetItem, targetCategory, sizeof(targetCategory));
    GetItemCategory(otherItem, otherCategory, sizeof(otherCategory));

    if (!StrEqual(targetItem.type, otherItem.type)
        && IsBuiltinChatCosmeticType(targetItem.type)
        && IsBuiltinChatCosmeticType(otherItem.type))
    {
        return false;
    }

    if (targetCategory[0] != '\0' && StrEqual(targetCategory, otherCategory) && IsItemTypeExclusive(targetItem.type))
    {
        return StoreItemTeamsCanConflict(targetItem.team, otherItem.team);
    }

    return false;
}

void ResetPlayerModelToDefault(int client)
{
    if (!IsValidHumanClient(client) || !IsPlayerAlive(client))
    {
        return;
    }

    if (GetFeatureStatus(FeatureType_Native, "CS_UpdateClientModel") == FeatureStatus_Available)
    {
        CS_UpdateClientModel(client);
    }
    else if (g_szDefaultPlayerModel[client][0] != '\0')
    {
        SetEntityModel(client, g_szDefaultPlayerModel[client]);
    }

    if (HasEntProp(client, Prop_Send, "m_szArmsModel"))
    {
        SetEntPropString(client, Prop_Send, "m_szArmsModel", "");
    }
}

void CaptureClientDefaultModel(int client)
{
    if (!IsValidHumanClient(client))
    {
        return;
    }

    char modelPath[PLATFORM_MAX_PATH];
    GetClientModel(client, modelPath, sizeof(modelPath));
    if (modelPath[0] != '\0')
    {
        strcopy(g_szDefaultPlayerModel[client], sizeof(g_szDefaultPlayerModel[]), modelPath);
    }
}

void GetReadableTeamName(int client, char[] buffer, int maxlen)
{
    int team = GetClientTeam(client);
    buffer[0] = '\0';

    if (team > 0)
    {
        GetTeamName(team, buffer, maxlen);
    }

    if (buffer[0] == '\0')
    {
        if (team <= 1)
        {
            strcopy(buffer, maxlen, "Spectator");
        }
        else
        {
            Format(buffer, maxlen, "Team %d", team);
        }
    }
}

bool ArePlayerSkinsEnabled()
{
    return IsStoreEnabled() && (gCvarEnablePlayerSkins == null || gCvarEnablePlayerSkins.BoolValue);
}

public void OnPlayerSkinsToggleChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    bool enabled = StringToInt(newValue) != 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanClient(i) || !IsPlayerAlive(i))
        {
            continue;
        }

        if (enabled && IsStoreEnabled())
        {
            ApplyPlayerSkin(i);
        }
        else if (!enabled)
        {
            ResetPlayerModelToDefault(i);
        }
    }
}

void ApplyPlayerSkin(int client)
{
    if (!IsValidHumanClient(client) || !IsPlayerAlive(client) || g_hInventory[client] == null)
    {
        return;
    }

    if (!ArePlayerSkinsEnabled())
    {
        return;
    }

    ResetPlayerModelToDefault(client);

    int team = GetClientTeam(client);
    InventoryItem inv;
    StoreItem item;

    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (!inv.is_equipped)
        {
            continue;
        }

        if (!FindStoreItemById(inv.item_id, item))
        {
            continue;
        }

        if (!StrEqual(item.type, "skin") || !StoreItemTeamMatches(item.team, team))
        {
            continue;
        }

        if (item.szModel[0] == '\0' || !FileExists(item.szModel, true))
        {
            LogError("%s Skin equipada inválida para %N: %s", STORE_LOG_PREFIX, client, item.id);
            return;
        }

        PrecacheModel(item.szModel, true);
        SetEntityModel(client, item.szModel);

        if (item.szArms[0] != '\0' && FileExists(item.szArms, true) && HasEntProp(client, Prop_Send, "m_szArmsModel"))
        {
            PrecacheModel(item.szArms, true);
            SetEntPropString(client, Prop_Send, "m_szArmsModel", item.szArms);
        }

        return;
    }
}

bool CanUseEquipAction(int client)
{
    float cooldown = (gCvarEquipCooldown != null) ? gCvarEquipCooldown.FloatValue : 0.0;
    if (cooldown <= 0.0)
    {
        return true;
    }

    float now = GetGameTime();
    if (now < g_fNextEquipTime[client])
    {
        char cooldownText[16];
        FormatCooldownText(g_fNextEquipTime[client] - now, cooldownText, sizeof(cooldownText));
        PrintStorePhrase(client, "%T", "Equip Cooldown", client, cooldownText);
        return false;
    }

    return true;
}

// Charged only once an equip actually goes through: starting the cooldown in
// the check above meant a rejected attempt (item not owned, no access, listed
// on the market) blocked the legitimate equip that followed it.
void ConsumeEquipCooldown(int client)
{
    float cooldown = (gCvarEquipCooldown != null) ? gCvarEquipCooldown.FloatValue : 0.0;
    if (cooldown > 0.0)
    {
        g_fNextEquipTime[client] = GetGameTime() + cooldown;
    }
}

bool SetItemEquipped(int client, const char[] itemId, bool equipNow, bool notify = true, bool respectCooldown = true, bool force = false)
{
    if (!IsStoreEnabled() || !IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        return false;
    }

    if (respectCooldown && !CanUseEquipAction(client))
    {
        return false;
    }

    StoreItem targetItem;
    if (!FindStoreItemById(itemId, targetItem))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item Not Found", client);
        }
        return false;
    }

    int targetIndex = FindInventoryIndexByItemId(client, itemId);
    if (targetIndex == -1)
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item Not In Inventory", client);
        }
        return false;
    }

    InventoryItem targetInv;
    g_hInventory[client].GetArray(targetIndex, targetInv, sizeof(InventoryItem));

    if (view_as<bool>(targetInv.is_equipped) == equipNow)
    {
        if (equipNow && UnequipConflictingItemsForTarget(client, targetIndex, targetItem))
        {
            MarkInventoryChanged(client);
        }

        return true;
    }

    if (equipNow)
    {
        if (!force && !CanPlayerUseItem(client, targetItem, notify))
        {
            return false;
        }

        if (!force && StrEqual(targetItem.type, "skin") && !ArePlayerSkinsEnabled())
        {
            if (notify)
            {
                PrintStorePhrase(client, "%T", "Player Skins Disabled", client);
            }
            return false;
        }
    }

    if (!force && ForwardEquipPre(client, itemId, equipNow) >= Plugin_Handled)
    {
        return false;
    }

    if (!force && equipNow && HasActiveMarketplaceListing(client, itemId))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Market Item Listed Already", client);
        }
        return false;
    }

    if (respectCooldown)
    {
        ConsumeEquipCooldown(client);
    }

    if (equipNow)
    {
        UnequipConflictingItemsForTarget(client, targetIndex, targetItem);

        targetInv.is_equipped = 1;
        g_hInventory[client].SetArray(targetIndex, targetInv, sizeof(InventoryItem));
        SaveInventoryEquipState(client, itemId, 1);

        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item Equipped", client);
        }

        ForwardItemEquipped(client, itemId, true);
        ForwardEquipPost(client, itemId, true);
        ForwardInventoryChanged(client, itemId, "equip");
        LogAuditEvent(client, client, "equip", itemId, 0, "");
    }
    else
    {
        targetInv.is_equipped = 0;
        g_hInventory[client].SetArray(targetIndex, targetInv, sizeof(InventoryItem));
        SaveInventoryEquipState(client, itemId, 0);

        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item Unequipped", client);
        }

        ForwardItemEquipped(client, itemId, false);
        ForwardEquipPost(client, itemId, false);
        ForwardInventoryChanged(client, itemId, "unequip");
        LogAuditEvent(client, client, "unequip", itemId, 0, "");
    }

    MarkInventoryChanged(client);

    if (StrEqual(targetItem.type, "skin"))
    {
        ApplyPlayerSkin(client);
    }

    return true;
}

void ToggleEquip(int client, const char[] itemId)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        return;
    }

    int targetIndex = FindInventoryIndexByItemId(client, itemId);
    if (targetIndex == -1)
    {
        PrintStorePhrase(client, "%T", "Item Not In Inventory", client);
        return;
    }

    InventoryItem targetInv;
    g_hInventory[client].GetArray(targetIndex, targetInv, sizeof(InventoryItem));
    SetItemEquipped(client, itemId, !view_as<bool>(targetInv.is_equipped), true, true);
}

bool UnequipConflictingItemsForTarget(int client, int targetIndex, StoreItem targetItem)
{
    bool changed = false;
    InventoryItem inv;
    StoreItem otherItem;

    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        if (i == targetIndex)
        {
            continue;
        }

        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (!inv.is_equipped)
        {
            continue;
        }

        if (!FindStoreItemById(inv.item_id, otherItem))
        {
            continue;
        }

        if (!ShouldUnequipSameCategory(targetItem, otherItem))
        {
            continue;
        }

        inv.is_equipped = 0;
        g_hInventory[client].SetArray(i, inv, sizeof(InventoryItem));
        SaveInventoryEquipState(client, inv.item_id, 0);
        ForwardItemEquipped(client, inv.item_id, false);
        ForwardEquipPost(client, inv.item_id, false);
        ForwardInventoryChanged(client, inv.item_id, "unequip");
        changed = true;
    }

    return changed;
}

void NormalizeEquippedItemConflicts(int client)
{
    if (!IsValidHumanClient(client) || g_hInventory[client] == null)
    {
        return;
    }

    InventoryItem keeperInv, otherInv;
    StoreItem keeperItem, otherItem;
    bool changed = false;

    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, keeperInv, sizeof(InventoryItem));
        if (!keeperInv.is_equipped || !FindStoreItemById(keeperInv.item_id, keeperItem))
        {
            continue;
        }

        for (int j = i + 1; j < g_hInventory[client].Length; j++)
        {
            g_hInventory[client].GetArray(j, otherInv, sizeof(InventoryItem));
            if (!otherInv.is_equipped || !FindStoreItemById(otherInv.item_id, otherItem))
            {
                continue;
            }

            if (!ShouldUnequipSameCategory(keeperItem, otherItem))
            {
                continue;
            }

            otherInv.is_equipped = 0;
            g_hInventory[client].SetArray(j, otherInv, sizeof(InventoryItem));
            SaveInventoryEquipState(client, otherInv.item_id, 0);
            ForwardItemEquipped(client, otherInv.item_id, false);
            ForwardEquipPost(client, otherInv.item_id, false);
            ForwardInventoryChanged(client, otherInv.item_id, "unequip");
            changed = true;
        }
    }

    if (changed)
    {
        MarkInventoryChanged(client);
    }
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        RemovePreview(client);
    }

    if (client > 0 && ArePlayerSkinsEnabled() && IsValidHumanClient(client) && IsPlayerAlive(client) && g_bIsLoaded[client])
    {
        CaptureClientDefaultModel(client);
        CreateTimer(0.1, Timer_ApplySkin, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }

    return Plugin_Continue;
}

public Action Timer_ApplySkin(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && ArePlayerSkinsEnabled() && IsValidHumanClient(client) && IsPlayerAlive(client))
    {
        ApplyPlayerSkin(client);
    }

    return Plugin_Stop;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        RemovePreview(client);
    }

    if (client > 0 && ArePlayerSkinsEnabled() && IsValidHumanClient(client) && IsPlayerAlive(client) && g_bIsLoaded[client])
    {
        CreateTimer(0.1, Timer_ApplySkin, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }

    return Plugin_Continue;
}

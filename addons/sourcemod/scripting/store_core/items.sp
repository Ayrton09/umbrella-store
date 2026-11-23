// Umbrella Store core: Item registry, item types, metadata, and item config loading.
// Included by store_core.sp.

void BuildItemMetadataKey(const char[] itemId, const char[] key, char[] buffer, int maxlen)
{
    Format(buffer, maxlen, "%s::%s", itemId, key);
}

void ClearItemMetadataForItem(const char[] itemId)
{
    if (g_mItemMetadata == null)
    {
        return;
    }

    StringMapSnapshot snapshot = g_mItemMetadata.Snapshot();
    char key[192];

    for (int i = snapshot.Length - 1; i >= 0; i--)
    {
        snapshot.GetKey(i, key, sizeof(key));
        if (StrContains(key, itemId, false) == 0 && key[strlen(itemId)] == ':' && key[strlen(itemId) + 1] == ':')
        {
            g_mItemMetadata.Remove(key);
        }
    }

    delete snapshot;
}

void SetItemMetadataValue(const char[] itemId, const char[] key, const char[] value)
{
    if (g_mItemMetadata == null || itemId[0] == '\0' || key[0] == '\0')
    {
        return;
    }

    char metadataKey[192];
    BuildItemMetadataKey(itemId, key, metadataKey, sizeof(metadataKey));
    g_mItemMetadata.SetString(metadataKey, value);
}

void SetItemMetadataValueIfNotEmpty(const char[] itemId, const char[] key, const char[] value)
{
    if (value[0] == '\0')
    {
        return;
    }

    SetItemMetadataValue(itemId, key, value);
}

void SetItemMetadataIntValue(const char[] itemId, const char[] key, int value)
{
    char buffer[32];
    IntToString(value, buffer, sizeof(buffer));
    SetItemMetadataValue(itemId, key, buffer);
}

void TrimMetadataToken(char[] buffer)
{
    TrimString(buffer);

    int len = strlen(buffer);
    if (len >= 2 && ((buffer[0] == '"' && buffer[len - 1] == '"') || (buffer[0] == '\'' && buffer[len - 1] == '\'')))
    {
        for (int i = 1; i < len - 1; i++)
        {
            buffer[i - 1] = buffer[i];
        }
        buffer[len - 2] = '\0';
        TrimString(buffer);
    }
}

void ParseItemMetadataPairs(const char[] itemId, const char[] raw)
{
    if (itemId[0] == '\0' || raw[0] == '\0')
    {
        return;
    }

    char buffer[256];
    strcopy(buffer, sizeof(buffer), raw);
    ReplaceString(buffer, sizeof(buffer), "\n", ";");
    ReplaceString(buffer, sizeof(buffer), "\r", ";");

    int start = 0;
    int len = strlen(buffer);
    while (start < len)
    {
        int end = start;
        while (end < len && buffer[end] != ';')
        {
            end++;
        }

        char token[256];
        int tokenLen = end - start;
        if (tokenLen >= sizeof(token))
        {
            tokenLen = sizeof(token) - 1;
        }

        for (int i = 0; i < tokenLen; i++)
        {
            token[i] = buffer[start + i];
        }
        token[tokenLen] = '\0';

        TrimString(token);
        if (token[0] != '\0')
        {
            int sep = FindCharInString(token, '=');
            if (sep == -1)
            {
                sep = FindCharInString(token, ':');
            }

            if (sep > 0)
            {
                char key[64], value[192];
                strcopy(key, sizeof(key), token);
                key[sep] = '\0';
                strcopy(value, sizeof(value), token[sep + 1]);
                TrimMetadataToken(key);
                TrimMetadataToken(value);

                if (key[0] != '\0' && value[0] != '\0')
                {
                    SetItemMetadataValue(itemId, key, value);
                }
            }
        }

        start = end + 1;
    }
}

void StoreConfigStringMetadata(KeyValues kv, const char[] itemId, const char[] configKey, const char[] metadataKey)
{
    char value[PLATFORM_MAX_PATH];
    kv.GetString(configKey, value, sizeof(value), "");
    SetItemMetadataValueIfNotEmpty(itemId, metadataKey, value);
}

void StoreConfigNestedDecalsMetadata(KeyValues kv, const char[] itemId)
{
    char existing[512];
    if (GetItemMetadataValue(itemId, "decals", existing, sizeof(existing)) && existing[0] != '\0')
    {
        return;
    }

    if (!kv.JumpToKey("Decals", false))
    {
        return;
    }

    char decals[512], material[PLATFORM_MAX_PATH];
    if (kv.GotoFirstSubKey())
    {
        do
        {
            kv.GetString("material", material, sizeof(material), "");
            TrimString(material);
            if (material[0] == '\0')
            {
                continue;
            }

            if (decals[0] != '\0')
            {
                StrCat(decals, sizeof(decals), ";");
            }
            StrCat(decals, sizeof(decals), material);
        }
        while (kv.GotoNextKey());

        kv.GoBack();
    }

    kv.GoBack();
    SetItemMetadataValueIfNotEmpty(itemId, "decals", decals);
}

void StoreCommonItemMetadata(KeyValues kv, StoreItem item)
{
    SetItemMetadataValueIfNotEmpty(item.id, "name", item.name);
    SetItemMetadataValueIfNotEmpty(item.id, "type", item.type);
    SetItemMetadataValueIfNotEmpty(item.id, "category", item.category);
    SetItemMetadataValueIfNotEmpty(item.id, "description", item.description);
    SetItemMetadataValueIfNotEmpty(item.id, "rarity", item.rarity);
    SetItemMetadataValueIfNotEmpty(item.id, "value", item.szValue);
    SetItemMetadataValueIfNotEmpty(item.id, "model", item.szModel);
    SetItemMetadataValueIfNotEmpty(item.id, "arms", item.szArms);
    SetItemMetadataValueIfNotEmpty(item.id, "requires_item", item.requires_item);
    SetItemMetadataValueIfNotEmpty(item.id, "bundle_id", item.bundle_id);
    SetItemMetadataValueIfNotEmpty(item.id, "flag", item.flag);
    SetItemMetadataIntValue(item.id, "price", item.price);
    SetItemMetadataIntValue(item.id, "sale_price", item.sale_price);
    SetItemMetadataIntValue(item.id, "team", item.team);
    SetItemMetadataIntValue(item.id, "sort_order", item.sort_order);
    SetItemMetadataIntValue(item.id, "starts_at", item.starts_at);
    SetItemMetadataIntValue(item.id, "ends_at", item.ends_at);
    SetItemMetadataIntValue(item.id, "sell_percent_override", item.sell_percent_override);
    SetItemMetadataIntValue(item.id, "hidden", item.hidden);

    StoreConfigStringMetadata(kv, item.id, "material", "material");
    StoreConfigStringMetadata(kv, item.id, "color", "color");
    StoreConfigStringMetadata(kv, item.id, "width", "width");
    StoreConfigStringMetadata(kv, item.id, "lifetime", "lifetime");
    StoreConfigStringMetadata(kv, item.id, "life", "life");
    StoreConfigStringMetadata(kv, item.id, "attachment", "attachment");
    StoreConfigStringMetadata(kv, item.id, "position", "position");
    StoreConfigStringMetadata(kv, item.id, "angles", "angles");
    StoreConfigStringMetadata(kv, item.id, "slot", "slot");
    StoreConfigStringMetadata(kv, item.id, "bonemerge", "bonemerge");
    StoreConfigStringMetadata(kv, item.id, "grenade", "grenade");
    StoreConfigStringMetadata(kv, item.id, "sound", "sound");
    StoreConfigStringMetadata(kv, item.id, "effect", "effect");
    StoreConfigStringMetadata(kv, item.id, "effect_name", "effect");
    StoreConfigStringMetadata(kv, item.id, "particle", "effect");
    StoreConfigStringMetadata(kv, item.id, "particle_name", "effect");
    StoreConfigStringMetadata(kv, item.id, "file", "file");
    StoreConfigStringMetadata(kv, item.id, "duration", "duration");
    StoreConfigStringMetadata(kv, item.id, "trigger", "trigger");
    StoreConfigStringMetadata(kv, item.id, "cooldown", "cooldown");
    StoreConfigStringMetadata(kv, item.id, "origin", "origin");
    StoreConfigStringMetadata(kv, item.id, "volume", "volume");
    StoreConfigStringMetadata(kv, item.id, "radius", "radius");
    StoreConfigStringMetadata(kv, item.id, "alpha", "alpha");
    StoreConfigStringMetadata(kv, item.id, "decal", "decal");
    StoreConfigStringMetadata(kv, item.id, "decals", "decals");
    StoreConfigStringMetadata(kv, item.id, "idle", "idle");
    StoreConfigStringMetadata(kv, item.id, "idle2", "idle2");
    StoreConfigStringMetadata(kv, item.id, "run", "run");
    StoreConfigStringMetadata(kv, item.id, "spawn", "spawn");
    StoreConfigStringMetadata(kv, item.id, "death", "death");
    StoreConfigStringMetadata(kv, item.id, "spawn_delay", "spawn_delay");
    StoreConfigStringMetadata(kv, item.id, "scale", "scale");
    StoreConfigStringMetadata(kv, item.id, "rainbow", "rainbow");
    StoreConfigStringMetadata(kv, item.id, "random", "random");

    StoreConfigStringMetadata(kv, item.id, "rgb color", "rgb_color");
    StoreConfigStringMetadata(kv, item.id, "rgb_color", "rgb_color");
    StoreConfigStringMetadata(kv, item.id, "start size", "start_size");
    StoreConfigStringMetadata(kv, item.id, "start_size", "start_size");
    StoreConfigStringMetadata(kv, item.id, "end size", "end_size");
    StoreConfigStringMetadata(kv, item.id, "end_size", "end_size");
    StoreConfigStringMetadata(kv, item.id, "base spread", "base_spread");
    StoreConfigStringMetadata(kv, item.id, "base_spread", "base_spread");
    StoreConfigStringMetadata(kv, item.id, "speed spread", "spread_speed");
    StoreConfigStringMetadata(kv, item.id, "spread speed", "spread_speed");
    StoreConfigStringMetadata(kv, item.id, "spread_speed", "spread_speed");
    StoreConfigStringMetadata(kv, item.id, "speed", "speed");
    StoreConfigStringMetadata(kv, item.id, "rate", "rate");
    StoreConfigStringMetadata(kv, item.id, "jet length", "jet_length");
    StoreConfigStringMetadata(kv, item.id, "jet_length", "jet_length");
    StoreConfigStringMetadata(kv, item.id, "twist", "twist");
    StoreConfigStringMetadata(kv, item.id, "density", "density");
    StoreConfigNestedDecalsMetadata(kv, item.id);

    if (item.metadata[0] != '\0')
    {
        SetItemMetadataValue(item.id, "raw", item.metadata);
        ParseItemMetadataPairs(item.id, item.metadata);
    }
}

bool GetItemMetadataValue(const char[] itemId, const char[] key, char[] value, int maxlen)
{
    value[0] = '\0';

    if (g_mItemMetadata == null || itemId[0] == '\0' || key[0] == '\0')
    {
        return false;
    }

    char metadataKey[192];
    BuildItemMetadataKey(itemId, key, metadataKey, sizeof(metadataKey));
    return g_mItemMetadata.GetString(metadataKey, value, maxlen);
}

bool RegisterItemTypeInternal(const char[] type, const char[] category, bool equippable, bool exclusive, bool isBuiltin = false)
{
    if (type[0] == '\0')
    {
        return false;
    }

    if (g_aItemTypes == null)
    {
        g_aItemTypes = new ArrayList(sizeof(StoreItemTypeDefinition));
    }

    if (g_mItemTypeIndex == null)
    {
        g_mItemTypeIndex = new StringMap();
    }

    StoreItemTypeDefinition definition;
    strcopy(definition.type, sizeof(definition.type), type);
    strcopy(definition.category, sizeof(definition.category), category);
    definition.equippable = equippable ? 1 : 0;
    definition.exclusive = exclusive ? 1 : 0;
    definition.is_builtin = isBuiltin ? 1 : 0;

    int index;
    if (g_mItemTypeIndex.GetValue(type, index) && index >= 0 && index < g_aItemTypes.Length)
    {
        g_aItemTypes.SetArray(index, definition, sizeof(StoreItemTypeDefinition));
        return true;
    }

    index = g_aItemTypes.PushArray(definition, sizeof(StoreItemTypeDefinition));
    if (index < 0)
    {
        return false;
    }

    g_mItemTypeIndex.SetValue(type, index);
    return true;
}

bool UnregisterItemTypeInternal(const char[] type, bool allowBuiltin = false)
{
    if (type[0] == '\0' || g_aItemTypes == null || g_mItemTypeIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mItemTypeIndex.GetValue(type, index) || index < 0 || index >= g_aItemTypes.Length)
    {
        return false;
    }

    StoreItemTypeDefinition definition;
    g_aItemTypes.GetArray(index, definition, sizeof(StoreItemTypeDefinition));
    if (definition.is_builtin && !allowBuiltin)
    {
        return false;
    }

    g_aItemTypes.Erase(index);
    g_mItemTypeIndex.Remove(type);

    for (int i = index; i < g_aItemTypes.Length; i++)
    {
        g_aItemTypes.GetArray(i, definition, sizeof(StoreItemTypeDefinition));
        g_mItemTypeIndex.SetValue(definition.type, i);
    }

    return true;
}

bool FindItemTypeDefinition(const char[] type, StoreItemTypeDefinition definition)
{
    if (type[0] == '\0' || g_aItemTypes == null || g_mItemTypeIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mItemTypeIndex.GetValue(type, index) || index < 0 || index >= g_aItemTypes.Length)
    {
        return false;
    }

    g_aItemTypes.GetArray(index, definition, sizeof(StoreItemTypeDefinition));
    return true;
}

void RegisterBuiltinItemTypes()
{
    RegisterItemTypeInternal("skin", "skins", true, true, true);
    RegisterItemTypeInternal("tag", "chat", true, true, true);
    RegisterItemTypeInternal("namecolor", "chat", true, true, true);
    RegisterItemTypeInternal("chatcolor", "chat", true, true, true);
}

void GetItemCategory(const StoreItem item, char[] buffer, int maxlen)
{
    if (item.category[0] != '\0')
    {
        strcopy(buffer, maxlen, item.category);
        return;
    }

    StoreItemTypeDefinition definition;
    if (FindItemTypeDefinition(item.type, definition) && definition.category[0] != '\0')
    {
        strcopy(buffer, maxlen, definition.category);
        return;
    }

    strcopy(buffer, maxlen, item.type);
}

bool IsItemTypeEquippable(const char[] type)
{
    StoreItemTypeDefinition definition;
    if (FindItemTypeDefinition(type, definition))
    {
        return view_as<bool>(definition.equippable);
    }

    return false;
}

bool IsItemTypeExclusive(const char[] type)
{
    if (StrEqual(type, "pet"))
    {
        return true;
    }

    StoreItemTypeDefinition definition;
    if (FindItemTypeDefinition(type, definition))
    {
        return view_as<bool>(definition.exclusive);
    }

    return false;
}

bool IsBuiltinChatCosmeticType(const char[] type)
{
    return StrEqual(type, "tag") || StrEqual(type, "namecolor") || StrEqual(type, "chatcolor");
}

void InvalidateItemCache()
{
    g_bItemCacheReady = false;

    if (g_mItemIndex != null)
    {
        g_mItemIndex.Clear();
    }

    if (g_mItemMetadata != null)
    {
        g_mItemMetadata.Clear();
    }
}

void RebuildItemCache()
{
    if (g_mItemIndex == null)
    {
        g_mItemIndex = new StringMap();
    }
    else
    {
        g_mItemIndex.Clear();
    }

    StoreItem item;
    for (int i = 0; i < g_aItems.Length; i++)
    {
        g_aItems.GetArray(i, item, sizeof(StoreItem));
        g_mItemIndex.SetValue(item.id, i);
    }

    g_bItemCacheReady = true;
}

int FindStoreItemIndexById(const char[] itemId)
{
    if (itemId[0] == '\0' || g_aItems == null)
    {
        return -1;
    }

    if (!g_bItemCacheReady || g_mItemIndex == null)
    {
        RebuildItemCache();
    }

    int index;
    if (g_mItemIndex != null && g_mItemIndex.GetValue(itemId, index) && index >= 0 && index < g_aItems.Length)
    {
        return index;
    }

    RebuildItemCache();

    if (g_mItemIndex != null && g_mItemIndex.GetValue(itemId, index) && index >= 0 && index < g_aItems.Length)
    {
        return index;
    }

    return -1;
}

bool FindStoreItemById(const char[] itemId, StoreItem item)
{
    int index = FindStoreItemIndexById(itemId);
    if (index == -1)
    {
        return false;
    }

    g_aItems.GetArray(index, item, sizeof(StoreItem));
    return true;
}

void AddDownloadIfExists(const char[] filePath)
{
    if (filePath[0] != '\0' && FileExists(filePath, true))
    {
        AddFileToDownloadsTable(filePath);
    }
}

void RegisterModelDownloads(const char[] modelPath)
{
    if (modelPath[0] == '\0' || !FileExists(modelPath, true))
    {
        return;
    }

    AddFileToDownloadsTable(modelPath);

    int len = strlen(modelPath);
    if (len < 5)
    {
        return;
    }

    char base[PLATFORM_MAX_PATH];
    strcopy(base, sizeof(base), modelPath);
    base[len - 4] = '\0';

    char filePath[PLATFORM_MAX_PATH];

    Format(filePath, sizeof(filePath), "%s.vvd", base);
    AddDownloadIfExists(filePath);

    Format(filePath, sizeof(filePath), "%s.dx80.vtx", base);
    AddDownloadIfExists(filePath);

    Format(filePath, sizeof(filePath), "%s.dx90.vtx", base);
    AddDownloadIfExists(filePath);

    Format(filePath, sizeof(filePath), "%s.sw.vtx", base);
    AddDownloadIfExists(filePath);

    Format(filePath, sizeof(filePath), "%s.vtx", base);
    AddDownloadIfExists(filePath);

    Format(filePath, sizeof(filePath), "%s.xbox.vtx", base);
    AddDownloadIfExists(filePath);

    Format(filePath, sizeof(filePath), "%s.phy", base);
    AddDownloadIfExists(filePath);
}

bool HasTxtExtension(const char[] fileName)
{
    int len = strlen(fileName);
    if (len < 5)
    {
        return false;
    }

    return StrEqual(fileName[len - 4], ".txt", false);
}

bool LoadItemsConfigFile(const char[] path, int &loadedSkins, int &loadedTags, int &loadedNameColors, int &loadedChatColors, int &loadedCustom)
{
    if (!FileExists(path))
    {
        LogError("%s Item config was not found: %s", STORE_LOG_PREFIX, path);
        return false;
    }

    KeyValues kv = new KeyValues("Items");
    if (!kv.ImportFromFile(path))
    {
        LogError("%s Failed to load item config: %s", STORE_LOG_PREFIX, path);
        delete kv;
        return false;
    }

    if (!kv.GotoFirstSubKey())
    {
        delete kv;
        return true;
    }

    StoreItem item;
    do
    {
        item.id[0] = '\0';
        item.name[0] = '\0';
        item.type[0] = '\0';
        item.category[0] = '\0';
        item.description[0] = '\0';
        item.rarity[0] = '\0';
        item.szModel[0] = '\0';
        item.szArms[0] = '\0';
        item.szValue[0] = '\0';
        item.metadata[0] = '\0';
        item.requires_item[0] = '\0';
        item.bundle_id[0] = '\0';
        item.flag[0] = '\0';
        item.price = 0;
        item.sale_price = -1;
        item.team = 0;
        item.sort_order = 0;
        item.starts_at = 0;
        item.ends_at = 0;
        item.sell_percent_override = -1;
        item.hidden = 0;

        kv.GetSectionName(item.id, sizeof(item.id));
        if (item.id[0] == '\0')
        {
            LogError("%s Item entry with empty section name was skipped in %s.", STORE_LOG_PREFIX, path);
            continue;
        }

        int existingIndex;
        if (g_mItemIndex != null && g_mItemIndex.GetValue(item.id, existingIndex))
        {
            LogError("%s Duplicate item id in config: %s from %s", STORE_LOG_PREFIX, item.id, path);
            continue;
        }

        ClearItemMetadataForItem(item.id);

        kv.GetString("name", item.name, sizeof(item.name), "Item");
        kv.GetString("type", item.type, sizeof(item.type), "skin");
        kv.GetString("category", item.category, sizeof(item.category), "");
        kv.GetString("description", item.description, sizeof(item.description), "");
        kv.GetString("rarity", item.rarity, sizeof(item.rarity), "common");
        kv.GetString("model", item.szModel, sizeof(item.szModel), "");
        kv.GetString("arms", item.szArms, sizeof(item.szArms), "");
        kv.GetString("value", item.szValue, sizeof(item.szValue), "");
        kv.GetString("metadata", item.metadata, sizeof(item.metadata), "");
        kv.GetString("requires_item", item.requires_item, sizeof(item.requires_item), "");
        kv.GetString("bundle_id", item.bundle_id, sizeof(item.bundle_id), "");
        kv.GetString("flag", item.flag, sizeof(item.flag), "");
        item.price = kv.GetNum("price", 0);
        item.sale_price = kv.GetNum("sale_price", -1);
        item.team = kv.GetNum("team", 0);
        item.sort_order = kv.GetNum("sort_order", 0);
        item.starts_at = kv.GetNum("starts_at", 0);
        item.ends_at = kv.GetNum("ends_at", 0);
        item.sell_percent_override = kv.GetNum("sell_percent_override", -1);
        item.hidden = kv.GetNum("hidden", 0);

        if (item.price < 0)
        {
            LogError("%s Item '%s' has an invalid negative price %d. It was clamped to 0.", STORE_LOG_PREFIX, item.id, item.price);
            item.price = 0;
        }

        if (item.sale_price < -1)
        {
            item.sale_price = -1;
        }

        if (item.sell_percent_override > 100)
        {
            item.sell_percent_override = 100;
        }
        else if (item.sell_percent_override < -1)
        {
            item.sell_percent_override = -1;
        }

        if (item.ends_at > 0 && item.starts_at > 0 && item.ends_at < item.starts_at)
        {
            LogError("%s Item '%s' has ends_at earlier than starts_at. ends_at was ignored.", STORE_LOG_PREFIX, item.id);
            item.ends_at = 0;
        }

        if (StrEqual(item.requires_item, item.id))
        {
            LogError("%s Item '%s' cannot require itself. requires_item was ignored.", STORE_LOG_PREFIX, item.id);
            item.requires_item[0] = '\0';
        }

        if (StrEqual(item.type, "skin"))
        {
            if (item.szModel[0] == '\0' || !FileExists(item.szModel, true))
            {
                LogError("%s Invalid skin '%s': missing model '%s'", STORE_LOG_PREFIX, item.id, item.szModel);
                continue;
            }

            PrecacheModel(item.szModel, true);
            RegisterModelDownloads(item.szModel);

            if (item.szArms[0] != '\0')
            {
                if (FileExists(item.szArms, true))
                {
                    PrecacheModel(item.szArms, true);
                    RegisterModelDownloads(item.szArms);
                }
                else
                {
                    LogError("%s Invalid arms for '%s': '%s'", STORE_LOG_PREFIX, item.id, item.szArms);
                    item.szArms[0] = '\0';
                }
            }
        }

        int pushedIndex = g_aItems.PushArray(item, sizeof(StoreItem));
        if (g_mItemIndex != null)
        {
            g_mItemIndex.SetValue(item.id, pushedIndex);
        }

        StoreCommonItemMetadata(kv, item);

        if (StrEqual(item.type, "skin"))
        {
            loadedSkins++;
        }
        else if (StrEqual(item.type, "tag"))
        {
            loadedTags++;
        }
        else if (StrEqual(item.type, "namecolor"))
        {
            loadedNameColors++;
        }
        else if (StrEqual(item.type, "chatcolor"))
        {
            loadedChatColors++;
        }
        else
        {
            loadedCustom++;
        }
    }
    while (kv.GotoNextKey());

    delete kv;
    return true;
}

void LoadItemsConfigDirectory(const char[] dirPath, int &loadedSkins, int &loadedTags, int &loadedNameColors, int &loadedChatColors, int &loadedCustom)
{
    DirectoryListing listing = OpenDirectory(dirPath);
    if (listing == null)
    {
        return;
    }

    ArrayList files = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    char entry[PLATFORM_MAX_PATH], filePath[PLATFORM_MAX_PATH];
    FileType fileType;

    while (listing.GetNext(entry, sizeof(entry), fileType))
    {
        if (fileType != FileType_File || !HasTxtExtension(entry))
        {
            continue;
        }

        Format(filePath, sizeof(filePath), "%s/%s", dirPath, entry);
        files.PushString(filePath);
    }

    delete listing;

    SortADTArray(files, Sort_Ascending, Sort_String);
    for (int i = 0; i < files.Length; i++)
    {
        files.GetString(i, filePath, sizeof(filePath));
        LoadItemsConfigFile(filePath, loadedSkins, loadedTags, loadedNameColors, loadedChatColors, loadedCustom);
    }

    delete files;
}

void LoadItemsConfig()
{
    g_aItems.Clear();
    InvalidateItemCache();

    if (g_mItemIndex == null)
    {
        g_mItemIndex = new StringMap();
    }

    int loadedSkins = 0;
    int loadedTags = 0;
    int loadedNameColors = 0;
    int loadedChatColors = 0;
    int loadedCustom = 0;

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), STORE_ITEMS_CONFIG);
    if (!LoadItemsConfigFile(path, loadedSkins, loadedTags, loadedNameColors, loadedChatColors, loadedCustom))
    {
        return;
    }

    BuildPath(Path_SM, path, sizeof(path), STORE_ITEMS_DIR);
    LoadItemsConfigDirectory(path, loadedSkins, loadedTags, loadedNameColors, loadedChatColors, loadedCustom);

    RebuildItemCache();
    LogMessage("%s Loaded item config: %d items (skins=%d, tags=%d, namecolors=%d, chatcolors=%d, custom=%d).",
        STORE_LOG_PREFIX,
        g_aItems.Length,
        loadedSkins,
        loadedTags,
        loadedNameColors,
        loadedChatColors,
        loadedCustom);
    ForwardItemsReloaded();
}

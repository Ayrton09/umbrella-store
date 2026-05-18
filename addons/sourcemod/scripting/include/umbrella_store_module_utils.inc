#if defined _umbrella_store_module_utils_included
 #endinput
#endif
#define _umbrella_store_module_utils_included

#include <sourcemod>
#include <sdktools>
#include <umbrella_store>

#define USM_MAX_EQUIPPED_ITEMS 128
#define USM_TEAM_T 2
#define USM_TEAM_CT 3

stock bool USM_IsValidClient(int client, bool alive = false)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
    {
        return false;
    }

    return !alive || IsPlayerAlive(client);
}

stock bool USM_IsPlayableClient(int client, bool alive = false)
{
    if (!USM_IsValidClient(client, alive))
    {
        return false;
    }

    int team = GetClientTeam(client);
    return team == USM_TEAM_T || team == USM_TEAM_CT;
}

stock bool USM_ItemMatchesType(const char[] itemId, const char[] type)
{
    char itemType[32];
    return US_GetItemType(itemId, itemType, sizeof(itemType)) && StrEqual(itemType, type, false);
}

stock bool USM_GetMetadata(const char[] itemId, const char[] key, char[] value, int maxlen, const char[] defaultValue = "")
{
    if (US_GetItemMetadata(itemId, key, value, maxlen))
    {
        return true;
    }

    strcopy(value, maxlen, defaultValue);
    return false;
}

stock int USM_GetMetadataInt(const char[] itemId, const char[] key, int defaultValue = 0)
{
    char value[64];
    if (!US_GetItemMetadata(itemId, key, value, sizeof(value)) || value[0] == '\0')
    {
        return defaultValue;
    }

    return StringToInt(value);
}

stock float USM_GetMetadataFloat(const char[] itemId, const char[] key, float defaultValue = 0.0)
{
    char value[64];
    if (!US_GetItemMetadata(itemId, key, value, sizeof(value)) || value[0] == '\0')
    {
        return defaultValue;
    }

    return StringToFloat(value);
}

stock bool USM_GetMetadataBool(const char[] itemId, const char[] key, bool defaultValue = false)
{
    char value[32];
    if (!US_GetItemMetadata(itemId, key, value, sizeof(value)) || value[0] == '\0')
    {
        return defaultValue;
    }

    return StringToInt(value) != 0 || StrEqual(value, "true", false) || StrEqual(value, "yes", false);
}

stock void USM_ParseVector(const char[] input, float vec[3], const float defaultVec[3])
{
    vec[0] = defaultVec[0];
    vec[1] = defaultVec[1];
    vec[2] = defaultVec[2];

    if (input[0] == '\0')
    {
        return;
    }

    char parts[3][32];
    int count = ExplodeString(input, " ", parts, sizeof(parts), sizeof(parts[]));
    if (count < 3)
    {
        count = ExplodeString(input, ",", parts, sizeof(parts), sizeof(parts[]));
    }

    if (count >= 3)
    {
        vec[0] = StringToFloat(parts[0]);
        vec[1] = StringToFloat(parts[1]);
        vec[2] = StringToFloat(parts[2]);
    }
}

stock void USM_ParseColor(const char[] input, int color[4], int r = 255, int g = 255, int b = 255, int a = 255)
{
    color[0] = r;
    color[1] = g;
    color[2] = b;
    color[3] = a;

    if (input[0] == '\0')
    {
        return;
    }

    char parts[4][16];
    int count = ExplodeString(input, " ", parts, sizeof(parts), sizeof(parts[]));
    if (count < 3)
    {
        count = ExplodeString(input, ",", parts, sizeof(parts), sizeof(parts[]));
    }

    if (count >= 3)
    {
        color[0] = StringToInt(parts[0]);
        color[1] = StringToInt(parts[1]);
        color[2] = StringToInt(parts[2]);
        if (count >= 4)
        {
            color[3] = StringToInt(parts[3]);
        }
    }

    for (int i = 0; i < 4; i++)
    {
        if (color[i] < 0)
        {
            color[i] = 0;
        }
        else if (color[i] > 255)
        {
            color[i] = 255;
        }
    }
}

stock void USM_AddDownloadIfExists(const char[] path)
{
    if (path[0] == '\0')
    {
        return;
    }

    if (FileExists(path, true))
    {
        AddFileToDownloadsTable(path);
    }
    else
    {
        LogError("[Umbrella Store] Missing download asset: %s", path);
    }
}

stock void USM_AddModelDownloads(const char[] modelPath)
{
    if (modelPath[0] == '\0')
    {
        return;
    }

    if (!FileExists(modelPath, true))
    {
        LogError("[Umbrella Store] Missing model asset: %s", modelPath);
        return;
    }

    AddFileToDownloadsTable(modelPath);

    char base[PLATFORM_MAX_PATH];
    strcopy(base, sizeof(base), modelPath);
    ReplaceString(base, sizeof(base), ".mdl", "");

    char path[PLATFORM_MAX_PATH];
    Format(path, sizeof(path), "%s.sw.vtx", base);
    if (FileExists(path, true))
    {
        AddFileToDownloadsTable(path);
    }
    Format(path, sizeof(path), "%s.dx80.vtx", base);
    if (FileExists(path, true))
    {
        AddFileToDownloadsTable(path);
    }
    Format(path, sizeof(path), "%s.dx90.vtx", base);
    if (FileExists(path, true))
    {
        AddFileToDownloadsTable(path);
    }
    Format(path, sizeof(path), "%s.vtx", base);
    if (FileExists(path, true))
    {
        AddFileToDownloadsTable(path);
    }
    Format(path, sizeof(path), "%s.xbox.vtx", base);
    if (FileExists(path, true))
    {
        AddFileToDownloadsTable(path);
    }
    Format(path, sizeof(path), "%s.vvd", base);
    if (FileExists(path, true))
    {
        AddFileToDownloadsTable(path);
    }
    Format(path, sizeof(path), "%s.phy", base);
    if (FileExists(path, true))
    {
        AddFileToDownloadsTable(path);
    }
}

stock void USM_AddMaterialDownloads(const char[] materialPath)
{
    if (materialPath[0] == '\0')
    {
        return;
    }

    if (!FileExists(materialPath, true))
    {
        LogError("[Umbrella Store] Missing material asset: %s", materialPath);
        return;
    }

    AddFileToDownloadsTable(materialPath);

    char texture[PLATFORM_MAX_PATH];
    strcopy(texture, sizeof(texture), materialPath);
    ReplaceString(texture, sizeof(texture), ".vmt", ".vtf");
    if (!StrEqual(texture, materialPath) && FileExists(texture, true))
    {
        AddFileToDownloadsTable(texture);
    }
}

stock void USM_AddConfiguredDownloads(const char[] itemId)
{
    char downloads[512];
    if (!US_GetItemMetadata(itemId, "downloads", downloads, sizeof(downloads)) || downloads[0] == '\0')
    {
        return;
    }

    char parts[16][PLATFORM_MAX_PATH];
    int count = ExplodeString(downloads, ";", parts, sizeof(parts), sizeof(parts[]));
    for (int i = 0; i < count; i++)
    {
        TrimString(parts[i]);
        USM_AddDownloadIfExists(parts[i]);
    }
}

stock int USM_GetEquippedItemsOfType(int client, const char[] type, char itemIds[][64], int maxItems)
{
    if (!USM_IsValidClient(client) || maxItems <= 0)
    {
        return 0;
    }

    int count = 0;
    int equippedCount = US_GetEquippedItemCount(client);
    char itemId[64];
    for (int i = 0; i < equippedCount && count < maxItems; i++)
    {
        if (!US_GetEquippedItemIdByIndex(client, i, itemId, sizeof(itemId)))
        {
            continue;
        }

        if (!USM_ItemMatchesType(itemId, type))
        {
            continue;
        }

        strcopy(itemIds[count], 64, itemId);
        count++;
    }

    return count;
}

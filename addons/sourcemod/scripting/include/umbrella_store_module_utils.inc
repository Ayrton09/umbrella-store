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

stock bool USM_ItemAllowedForClientTeam(int client, const char[] itemId)
{
    if (!USM_IsValidClient(client) || itemId[0] == '\0')
    {
        return false;
    }

    char name[64], type[32], category[32];
    int price, team;
    if (!US_GetItemInfo(itemId, name, sizeof(name), type, sizeof(type), price, team, category, sizeof(category)))
    {
        return true;
    }

    return team == 0 || team == 4 || team == GetClientTeam(client);
}

stock bool USM_GetItemTeam(const char[] itemId, int &team)
{
    char name[64], type[32], category[32];
    int price;
    if (!US_GetItemInfo(itemId, name, sizeof(name), type, sizeof(type), price, team, category, sizeof(category)))
    {
        team = 0;
        return false;
    }

    return true;
}

stock bool USM_ItemTeamsCanConflict(const char[] firstItemId, const char[] secondItemId)
{
    int firstTeam = 0;
    int secondTeam = 0;
    USM_GetItemTeam(firstItemId, firstTeam);
    USM_GetItemTeam(secondItemId, secondTeam);

    return firstTeam == 0 || firstTeam == 4 || secondTeam == 0 || secondTeam == 4 || firstTeam == secondTeam;
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

StringMap g_USM_DownloadCache = null;

#define USM_MAX_MODEL_MATERIALS 64

static const char g_USM_ModelExts[][] =
{
    ".phy",
    ".sw.vtx",
    ".dx80.vtx",
    ".dx90.vtx",
    ".vtx",
    ".xbox.vtx",
    ".vvd"
};

static const char g_USM_MaterialKeys[][] =
{
    "$basetexture",
    "$bumpmap",
    "$lightwarptexture",
    "$phongexponenttexture",
    "$envmapmask",
    "$selfillummask",
    "$detail"
};

stock bool USM_AddDownloadFile(const char[] path, bool logMissing = true)
{
    if (path[0] == '\0')
    {
        return false;
    }

    if (!FileExists(path, true))
    {
        if (logMissing)
        {
            LogError("[Umbrella Store] Missing download asset: %s", path);
        }
        return false;
    }

    if (g_USM_DownloadCache == null)
    {
        g_USM_DownloadCache = new StringMap();
    }

    int cached;
    if (g_USM_DownloadCache.GetValue(path, cached))
    {
        return true;
    }

    AddFileToDownloadsTable(path);
    g_USM_DownloadCache.SetValue(path, 1);
    return true;
}

stock void USM_AddDownloadIfExists(const char[] path)
{
    USM_AddDownloadFile(path);
}

stock bool USM_ReadFileStringUntilNull(File file, char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (file == null || maxlen <= 0)
    {
        return false;
    }

    int data;
    int written = 0;
    while (!IsEndOfFile(file) && ReadFileCell(file, data, 1) == 1)
    {
        if (data == 0)
        {
            break;
        }

        if (written < maxlen - 1)
        {
            buffer[written++] = data;
        }
    }
    buffer[written] = '\0';
    return written > 0;
}

stock int USM_ParseModelMaterialFiles(const char[] modelPath, char materials[][PLATFORM_MAX_PATH], int maxMaterials, int maxlen)
{
    if (maxMaterials <= 0 || maxlen <= 0)
    {
        return 0;
    }

    File file = OpenFile(modelPath, "rb");
    if (file == null)
    {
        return 0;
    }

    int modelId;
    int version;
    int textureCount;
    int textureOffset;
    int textureDirCount;
    int textureDirOffset;

    ReadFileCell(file, modelId, 4);
    ReadFileCell(file, version, 4);

    FileSeek(file, 204, SEEK_SET);
    ReadFileCell(file, textureCount, 4);
    ReadFileCell(file, textureOffset, 4);
    ReadFileCell(file, textureDirCount, 4);
    ReadFileCell(file, textureDirOffset, 4);

    if (textureCount <= 0 || textureOffset <= 0 || textureDirCount <= 0 || textureDirOffset <= 0)
    {
        delete file;
        return 0;
    }

    int dirStringOffset;
    char materialDir[PLATFORM_MAX_PATH];
    materialDir[0] = '\0';

    FileSeek(file, textureDirOffset, SEEK_SET);
    ReadFileCell(file, dirStringOffset, 4);
    if (dirStringOffset > 0)
    {
        FileSeek(file, dirStringOffset, SEEK_SET);
        USM_ReadFileStringUntilNull(file, materialDir, sizeof(materialDir));
    }

    ReplaceString(materialDir, sizeof(materialDir), "\\", "/");

    int count = 0;
    char materialName[PLATFORM_MAX_PATH];
    for (int i = 0; i < textureCount && count < maxMaterials; i++)
    {
        int nameOffset;
        FileSeek(file, textureOffset + (i * 64), SEEK_SET);
        ReadFileCell(file, nameOffset, 4);
        if (nameOffset <= 0)
        {
            continue;
        }

        FileSeek(file, textureOffset + (i * 64) + nameOffset, SEEK_SET);
        if (!USM_ReadFileStringUntilNull(file, materialName, sizeof(materialName)) || materialName[0] == '\0')
        {
            continue;
        }

        ReplaceString(materialName, sizeof(materialName), "\\", "/");
        Format(materials[count], maxlen, "materials/%s%s.vmt", materialDir, materialName);
        count++;
    }

    delete file;
    return count;
}

stock bool USM_ExtractVmtMaterialValue(const char[] line, const char[] key, char[] value, int maxlen)
{
    value[0] = '\0';

    int pos = StrContains(line, key, false);
    if (pos < 0)
    {
        return false;
    }

    pos += strlen(key);
    while (line[pos] == ' ' || line[pos] == '\t' || line[pos] == '"')
    {
        pos++;
    }

    int written = 0;
    while (line[pos] != '\0' && line[pos] != '"' && line[pos] != '\r' && line[pos] != '\n' && line[pos] != ' ' && line[pos] != '\t')
    {
        if (written < maxlen - 1)
        {
            value[written++] = line[pos];
        }
        pos++;
    }
    value[written] = '\0';

    if (value[0] == '\0')
    {
        return false;
    }

    ReplaceString(value, maxlen, "\\", "/");
    ReplaceString(value, maxlen, ".vtf", "", false);
    return true;
}

stock void USM_AddVmtTextureDownloads(const char[] materialPath)
{
    File file = OpenFile(materialPath, "r");
    if (file == null)
    {
        return;
    }

    char line[512];
    char materialValue[PLATFORM_MAX_PATH];
    char texturePath[PLATFORM_MAX_PATH];

    while (!IsEndOfFile(file) && ReadFileLine(file, line, sizeof(line)))
    {
        TrimString(line);
        if (line[0] == '\0' || StrContains(line, "//") == 0)
        {
            continue;
        }

        for (int i = 0; i < sizeof(g_USM_MaterialKeys); i++)
        {
            if (!USM_ExtractVmtMaterialValue(line, g_USM_MaterialKeys[i], materialValue, sizeof(materialValue)))
            {
                continue;
            }

            if (StrContains(materialValue, "materials/", false) == 0)
            {
                Format(texturePath, sizeof(texturePath), "%s.vtf", materialValue);
            }
            else
            {
                Format(texturePath, sizeof(texturePath), "materials/%s.vtf", materialValue);
            }

            USM_AddDownloadFile(texturePath, false);
        }
    }

    delete file;
}

stock void USM_AddModelSidecarDownloads(const char[] modelPath)
{
    char internalName[PLATFORM_MAX_PATH];
    internalName[0] = '\0';

    File file = OpenFile(modelPath, "rb");
    if (file != null)
    {
        int ignored;
        ReadFileCell(file, ignored, 4);
        ReadFileCell(file, ignored, 4);
        FileSeek(file, 4, SEEK_CUR);
        USM_ReadFileStringUntilNull(file, internalName, sizeof(internalName));
        delete file;
    }

    char base[PLATFORM_MAX_PATH];
    strcopy(base, sizeof(base), modelPath);
    ReplaceString(base, sizeof(base), ".mdl", "");

    char internalBase[PLATFORM_MAX_PATH];
    internalBase[0] = '\0';
    if (internalName[0] != '\0')
    {
        Format(internalBase, sizeof(internalBase), "models/%s", internalName);
        ReplaceString(internalBase, sizeof(internalBase), "\\", "/");
        ReplaceString(internalBase, sizeof(internalBase), ".mdl", "");
    }

    char path[PLATFORM_MAX_PATH];
    for (int i = 0; i < sizeof(g_USM_ModelExts); i++)
    {
        Format(path, sizeof(path), "%s%s", base, g_USM_ModelExts[i]);
        if (USM_AddDownloadFile(path, false))
        {
            continue;
        }

        if (internalBase[0] != '\0')
        {
            Format(path, sizeof(path), "%s%s", internalBase, g_USM_ModelExts[i]);
            USM_AddDownloadFile(path, false);
        }
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

    USM_AddDownloadFile(modelPath, false);

    char materials[USM_MAX_MODEL_MATERIALS][PLATFORM_MAX_PATH];
    int count = USM_ParseModelMaterialFiles(modelPath, materials, sizeof(materials), sizeof(materials[]));
    for (int i = 0; i < count; i++)
    {
        USM_AddMaterialDownloads(materials[i]);
    }

    USM_AddModelSidecarDownloads(modelPath);
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

    if (!USM_AddDownloadFile(materialPath, false))
    {
        return;
    }

    if (StrContains(materialPath, ".vmt", false) != -1)
    {
        USM_AddVmtTextureDownloads(materialPath);
    }
    else if (StrContains(materialPath, ".vtf", false) == -1)
    {
        char texture[PLATFORM_MAX_PATH];
        Format(texture, sizeof(texture), "%s.vtf", materialPath);
        USM_AddDownloadFile(texture, false);
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

stock bool USM_GetEquippedItemForClientTeam(int client, const char[] type, char[] itemId, int maxlen)
{
    itemId[0] = '\0';

    if (!USM_IsValidClient(client) || maxlen <= 0)
    {
        return false;
    }

    int equippedCount = US_GetEquippedItemCount(client);
    char currentId[64];
    for (int i = 0; i < equippedCount; i++)
    {
        if (!US_GetEquippedItemIdByIndex(client, i, currentId, sizeof(currentId)))
        {
            continue;
        }

        if (!USM_ItemMatchesType(currentId, type) || !USM_ItemAllowedForClientTeam(client, currentId))
        {
            continue;
        }

        strcopy(itemId, maxlen, currentId);
        return true;
    }

    return false;
}

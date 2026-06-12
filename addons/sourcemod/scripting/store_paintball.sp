#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <umbrella_store>
#include <umbrella_store_module_utils>

ConVar gCvarEnabled;
bool g_bHidePaintball[MAXPLAYERS + 1];
StringMap g_mPaintballDecals = null;
Cookie g_hHideCookie;

public Plugin myinfo =
{
    name = "[Umbrella Store] Paintball",
    author = "Ayrton09",
    description = "Bullet impact decal item module for Umbrella Store",
    version = "1.4.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store.phrases");

    gCvarEnabled = CreateConVar("umbrella_store_paintball_enabled", "1", "Enable Umbrella Store paintball decals.", FCVAR_NONE, true, 0.0, true, 1.0);
    AutoExecConfig(true, "umbrella_store_paintball");

    g_hHideCookie = new Cookie("umbrella_store_hide_paintball", "Hide Umbrella Store paintball decals", CookieAccess_Private);

    US_RegisterItemType("paintball", "paintball", true, true);
    RegConsoleCmd("sm_hidepaintball", Command_HidePaintball);
    HookEvent("bullet_impact", Event_BulletImpact, EventHookMode_Post);
}

public void OnMapStart()
{
    delete g_mPaintballDecals;
    g_mPaintballDecals = new StringMap();
    PrecachePaintballDecals();
}

public void US_OnItemsReloaded(int itemCount)
{
    delete g_mPaintballDecals;
    g_mPaintballDecals = new StringMap();
    PrecachePaintballDecals();
}

public void OnClientDisconnect(int client)
{
    g_bHidePaintball[client] = false;
}

public void OnPluginEnd()
{
    delete g_mPaintballDecals;
}

public void OnClientCookiesCached(int client)
{
    char value[8];
    g_hHideCookie.Get(client, value, sizeof(value));
    g_bHidePaintball[client] = (value[0] != '\0' && StringToInt(value) != 0);
}

public Action Command_HidePaintball(int client, int args)
{
    if (!USM_IsValidClient(client))
    {
        return Plugin_Handled;
    }

    g_bHidePaintball[client] = !g_bHidePaintball[client];
    if (AreClientCookiesCached(client))
    {
        g_hHideCookie.Set(client, g_bHidePaintball[client] ? "1" : "0");
    }

    PrintToChat(client, "[Umbrella Store] %T", g_bHidePaintball[client] ? "Module Hidden" : "Module Visible", client, "Paintball");
    return Plugin_Handled;
}

void NormalizeDecalPath(const char[] input, char[] decalPath, int decalMax, char[] downloadPath, int downloadMax)
{
    decalPath[0] = '\0';
    downloadPath[0] = '\0';

    if (input[0] == '\0')
    {
        return;
    }

    strcopy(decalPath, decalMax, input);
    TrimString(decalPath);

    if (StrContains(decalPath, "materials/", false) == 0)
    {
        strcopy(downloadPath, downloadMax, decalPath);
        ReplaceString(decalPath, decalMax, "materials/", "", false);
    }
    else
    {
        Format(downloadPath, downloadMax, "materials/%s", decalPath);
    }
}

void PrecacheOnePaintballDecal(const char[] rawPath)
{
    char decalPath[PLATFORM_MAX_PATH], downloadPath[PLATFORM_MAX_PATH];
    NormalizeDecalPath(rawPath, decalPath, sizeof(decalPath), downloadPath, sizeof(downloadPath));

    if (decalPath[0] == '\0')
    {
        return;
    }

    if (FileExists(downloadPath, true))
    {
        int index = PrecacheDecal(decalPath, true);
        if (g_mPaintballDecals != null)
        {
            g_mPaintballDecals.SetValue(decalPath, index);
        }
        AddFileToDownloadsTable(downloadPath);

        char texturePath[PLATFORM_MAX_PATH];
        strcopy(texturePath, sizeof(texturePath), downloadPath);
        ReplaceString(texturePath, sizeof(texturePath), ".vmt", ".vtf");
        if (!StrEqual(texturePath, downloadPath) && FileExists(texturePath, true))
        {
            AddFileToDownloadsTable(texturePath);
        }
    }
    else
    {
        LogError("[Umbrella Store] Missing paintball decal: %s", downloadPath);
    }
}

int GetPaintballDecalIndex(const char[] decalPath)
{
    int index = -1;
    if (g_mPaintballDecals != null && g_mPaintballDecals.GetValue(decalPath, index))
    {
        return index;
    }

    index = PrecacheDecal(decalPath, true);
    if (g_mPaintballDecals != null)
    {
        g_mPaintballDecals.SetValue(decalPath, index);
    }
    return index;
}

void PrecachePaintballDecals()
{
    int count = US_GetItemCount();
    char itemId[64], type[32], decals[512], single[PLATFORM_MAX_PATH];

    for (int i = 0; i < count; i++)
    {
        if (!US_GetItemIdByIndex(i, itemId, sizeof(itemId)) || !US_GetItemType(itemId, type, sizeof(type)) || !StrEqual(type, "paintball", false))
        {
            continue;
        }

        if (US_GetItemMetadata(itemId, "decals", decals, sizeof(decals)) && decals[0] != '\0')
        {
            char parts[16][PLATFORM_MAX_PATH];
            int partCount = ExplodeString(decals, ";", parts, sizeof(parts), sizeof(parts[]));
            for (int j = 0; j < partCount; j++)
            {
                PrecacheOnePaintballDecal(parts[j]);
            }
        }

        if (US_GetItemMetadata(itemId, "decal", single, sizeof(single)) && single[0] != '\0')
        {
            PrecacheOnePaintballDecal(single);
        }

    }
}

bool PickPaintballDecal(const char[] itemId, char[] decalPath, int maxlen)
{
    char decals[512];
    if (US_GetItemMetadata(itemId, "decals", decals, sizeof(decals)) && decals[0] != '\0')
    {
        char parts[16][PLATFORM_MAX_PATH];
        int count = ExplodeString(decals, ";", parts, sizeof(parts), sizeof(parts[]));
        if (count > 0)
        {
            strcopy(decalPath, maxlen, parts[GetRandomInt(0, count - 1)]);
            TrimString(decalPath);
            return decalPath[0] != '\0';
        }
    }

    return US_GetItemMetadata(itemId, "decal", decalPath, maxlen) && decalPath[0] != '\0';
}

public Action Event_BulletImpact(Event event, const char[] name, bool dontBroadcast)
{
    if (!US_IsEnabled() || !gCvarEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!USM_IsPlayableClient(client, true))
    {
        return Plugin_Continue;
    }

    char itemId[64], rawDecal[PLATFORM_MAX_PATH], decalPath[PLATFORM_MAX_PATH], downloadPath[PLATFORM_MAX_PATH];
    if (!USM_GetEquippedItemForClientTeam(client, "paintball", itemId, sizeof(itemId)) || !PickPaintballDecal(itemId, rawDecal, sizeof(rawDecal)))
    {
        return Plugin_Continue;
    }

    NormalizeDecalPath(rawDecal, decalPath, sizeof(decalPath), downloadPath, sizeof(downloadPath));
    if (decalPath[0] == '\0' || !FileExists(downloadPath, true))
    {
        return Plugin_Continue;
    }

    int clients[MAXPLAYERS];
    int clientCount = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!USM_IsValidClient(i) || g_bHidePaintball[i])
        {
            continue;
        }

        clients[clientCount++] = i;
    }

    if (clientCount <= 0)
    {
        return Plugin_Continue;
    }

    float impact[3];
    impact[0] = event.GetFloat("x");
    impact[1] = event.GetFloat("y");
    impact[2] = event.GetFloat("z");

    TE_Start("World Decal");
    TE_WriteVector("m_vecOrigin", impact);
    TE_WriteNum("m_nIndex", GetPaintballDecalIndex(decalPath));
    TE_Send(clients, clientCount);

    return Plugin_Continue;
}

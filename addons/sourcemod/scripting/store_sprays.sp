#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <umbrella_store>
#include <umbrella_store_module_utils>

ConVar gCvarEnabled;
ConVar gCvarCooldown;
ConVar gCvarDistance;

int g_iNextSprayTime[MAXPLAYERS + 1];
bool g_bUsePressed[MAXPLAYERS + 1];
StringMap g_mSprayDecals = null;

public Plugin myinfo =
{
    name = "[Umbrella Store] Sprays",
    author = "Ayrton09",
    description = "Custom wall spray item module for Umbrella Store",
    version = "1.5.0",
    url = ""
};

public void OnPluginStart()
{
    gCvarEnabled = CreateConVar("umbrella_store_sprays_enabled", "1", "Enable Umbrella Store sprays.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarCooldown = CreateConVar("umbrella_store_sprays_cooldown", "30", "Seconds between two sprays per player.", FCVAR_NONE, true, 0.0);
    gCvarDistance = CreateConVar("umbrella_store_sprays_distance", "115.0", "Maximum distance from player eye to spray surface.", FCVAR_NONE, true, 1.0);
    AutoExecConfig(true, "umbrella_store_sprays");

    US_RegisterItemType("spray", "sprays", true, true);
}

public void OnMapStart()
{
    delete g_mSprayDecals;
    g_mSprayDecals = new StringMap();
    PrecacheConfiguredSprays();
    PrecacheSound("player/sprayer.wav", true);
}

public void US_OnItemsReloaded(int itemCount)
{
    delete g_mSprayDecals;
    g_mSprayDecals = new StringMap();
    PrecacheConfiguredSprays();
}

public void OnClientDisconnect(int client)
{
    g_iNextSprayTime[client] = 0;
    g_bUsePressed[client] = false;
}

public void OnPluginEnd()
{
    delete g_mSprayDecals;
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

    ReplaceString(decalPath, decalMax, ".vmt", "", false);
}

void PrecacheOneSpray(const char[] rawPath)
{
    char decalPath[PLATFORM_MAX_PATH], downloadPath[PLATFORM_MAX_PATH];
    NormalizeDecalPath(rawPath, decalPath, sizeof(decalPath), downloadPath, sizeof(downloadPath));

    if (decalPath[0] == '\0')
    {
        return;
    }

    if (!FileExists(downloadPath, true))
    {
        LogError("[Umbrella Store] Missing spray material: %s", downloadPath);
        return;
    }

    int index = PrecacheDecal(decalPath, true);
    if (g_mSprayDecals != null)
    {
        g_mSprayDecals.SetValue(decalPath, index);
    }
    USM_AddMaterialDownloads(downloadPath);
}

int GetSprayDecalIndex(const char[] decalPath)
{
    int index = -1;
    if (g_mSprayDecals != null && g_mSprayDecals.GetValue(decalPath, index))
    {
        return index;
    }

    index = PrecacheDecal(decalPath, true);
    if (g_mSprayDecals != null)
    {
        g_mSprayDecals.SetValue(decalPath, index);
    }
    return index;
}

void PrecacheConfiguredSprays()
{
    int count = US_GetItemCount();
    char itemId[64], type[32], material[PLATFORM_MAX_PATH];

    for (int i = 0; i < count; i++)
    {
        if (!US_GetItemIdByIndex(i, itemId, sizeof(itemId)) || !US_GetItemType(itemId, type, sizeof(type)) || !StrEqual(type, "spray", false))
        {
            continue;
        }

        USM_GetMetadata(itemId, "material", material, sizeof(material));
        if (material[0] == '\0')
        {
            LogError("[Umbrella Store] Spray item '%s' has no material.", itemId);
            continue;
        }

        PrecacheOneSpray(material);
    }
}

public bool TraceRayDontHitSelf(int entity, int contentsMask, any data)
{
    return entity != data;
}

bool GetPlayerEyeViewPoint(int client, float position[3])
{
    float eye[3], angles[3];
    GetClientEyePosition(client, eye);
    GetClientEyeAngles(client, angles);

    Handle trace = TR_TraceRayFilterEx(eye, angles, MASK_ALL, RayType_Infinite, TraceRayDontHitSelf, client);
    bool hit = TR_DidHit(trace);
    TR_GetEndPosition(position, trace);
    delete trace;

    return hit;
}

void CreateSpray(int client, const char[] itemId)
{
    char rawMaterial[PLATFORM_MAX_PATH], decalPath[PLATFORM_MAX_PATH], downloadPath[PLATFORM_MAX_PATH];
    USM_GetMetadata(itemId, "material", rawMaterial, sizeof(rawMaterial));
    NormalizeDecalPath(rawMaterial, decalPath, sizeof(decalPath), downloadPath, sizeof(downloadPath));

    if (decalPath[0] == '\0' || !FileExists(downloadPath, true))
    {
        return;
    }

    float eye[3], hit[3];
    GetClientEyePosition(client, eye);
    if (!GetPlayerEyeViewPoint(client, hit))
    {
        return;
    }

    if (GetVectorDistance(eye, hit) > gCvarDistance.FloatValue)
    {
        return;
    }

    TE_Start("World Decal");
    TE_WriteVector("m_vecOrigin", hit);
    TE_WriteNum("m_nIndex", GetSprayDecalIndex(decalPath));
    TE_SendToAll();

    EmitSoundToAll("player/sprayer.wav", client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.6);
    g_iNextSprayTime[client] = GetTime() + gCvarCooldown.IntValue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (!US_IsEnabled() || !gCvarEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    if ((buttons & IN_USE) == 0)
    {
        g_bUsePressed[client] = false;
        return Plugin_Continue;
    }

    if (g_bUsePressed[client])
    {
        return Plugin_Continue;
    }
    g_bUsePressed[client] = true;

    if (!USM_IsPlayableClient(client, true))
    {
        return Plugin_Continue;
    }

    if (g_iNextSprayTime[client] > GetTime())
    {
        return Plugin_Continue;
    }

    char itemId[64];
    if (USM_GetEquippedItemForClientTeam(client, "spray", itemId, sizeof(itemId)))
    {
        CreateSpray(client, itemId);
    }

    return Plugin_Continue;
}

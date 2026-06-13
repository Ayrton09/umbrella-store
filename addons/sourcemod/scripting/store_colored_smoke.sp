#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <umbrella_store>
#include <umbrella_store_module_utils>

ConVar gCvarEnabled;
ArrayList g_aSmokeRefs = null;

public Plugin myinfo =
{
    name = "[Umbrella Store] Colored Smoke",
    author = "Ayrton09",
    description = "Colored smoke grenade item module for Umbrella Store",
    version = "1.5.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store.phrases");
    g_aSmokeRefs = new ArrayList();

    gCvarEnabled = CreateConVar("umbrella_store_colored_smoke_enabled", "1", "Enable Umbrella Store colored smoke.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarEnabled.AddChangeHook(Cvar_EnabledChanged);
    AutoExecConfig(true, "umbrella_store_colored_smoke");

    US_RegisterItemType("coloredsmoke", "colored_smoke", true, true);
    US_RegisterItemType("ColoredSmoke", "colored_smoke", true, true);
    HookEvent("smokegrenade_detonate", Event_SmokeDetonate, EventHookMode_Pre);
}

public void OnMapStart()
{
    PrecacheConfiguredSmokeMaterials();
}

public void US_OnItemsReloaded(int itemCount)
{
    PrecacheConfiguredSmokeMaterials();
    RemoveAllColoredSmokes();
}

public void OnPluginEnd()
{
    RemoveAllColoredSmokes();
    delete g_aSmokeRefs;
}

public void US_OnStoreEnabledChanged(bool enabled)
{
    if (!enabled)
    {
        RemoveAllColoredSmokes();
    }
}

public void Cvar_EnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (!convar.BoolValue)
    {
        RemoveAllColoredSmokes();
    }
}

bool GetEquippedSmokeItem(int client, char[] itemId, int maxlen)
{
    if (USM_GetEquippedItemForClientTeam(client, "coloredsmoke", itemId, maxlen))
    {
        return true;
    }

    return USM_GetEquippedItemForClientTeam(client, "ColoredSmoke", itemId, maxlen);
}

void AddSmokeMaterialDownload(const char[] material)
{
    if (material[0] == '\0')
    {
        return;
    }

    char path[PLATFORM_MAX_PATH];
    if (StrContains(material, "materials/", false) == 0)
    {
        strcopy(path, sizeof(path), material);
    }
    else
    {
        Format(path, sizeof(path), "materials/%s", material);
    }

    if (FileExists(path, true))
    {
        USM_AddMaterialDownloads(path);
    }
    else
    {
        LogError("[Umbrella Store] Colored smoke material is missing: %s", path);
    }
}

void PrecacheConfiguredSmokeMaterials()
{
    int count = US_GetItemCount();
    char itemId[64], type[32], material[PLATFORM_MAX_PATH];

    for (int i = 0; i < count; i++)
    {
        if (!US_GetItemIdByIndex(i, itemId, sizeof(itemId)) || !US_GetItemType(itemId, type, sizeof(type)))
        {
            continue;
        }

        if (!StrEqual(type, "coloredsmoke", false) && !StrEqual(type, "ColoredSmoke", false))
        {
            continue;
        }

        USM_GetMetadata(itemId, "material", material, sizeof(material), "particle/particle_smokegrenade1.vmt");
        AddSmokeMaterialDownload(material);
    }
}

void GetSmokeKey(const char[] itemId, const char[] key, const char[] defaultValue, char[] buffer, int maxlen)
{
    USM_GetMetadata(itemId, key, buffer, maxlen, defaultValue);
}

public Action Event_SmokeDetonate(Event event, const char[] name, bool dontBroadcast)
{
    if (!US_IsEnabled() || !gCvarEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!USM_IsPlayableClient(client))
    {
        return Plugin_Continue;
    }

    char itemId[64];
    if (!GetEquippedSmokeItem(client, itemId, sizeof(itemId)))
    {
        return Plugin_Continue;
    }

    int oldEntity = event.GetInt("entityid");
    if (oldEntity > MaxClients && IsValidEntity(oldEntity))
    {
        AcceptEntityInput(oldEntity, "Kill");
    }

    float origin[3];
    origin[0] = event.GetFloat("x");
    origin[1] = event.GetFloat("y");
    origin[2] = event.GetFloat("z");

    int smoke = CreateEntityByName("env_smokestack");
    if (smoke == -1)
    {
        return Plugin_Continue;
    }

    char rgb[64], baseSpread[32], spreadSpeed[32], speed[32], startSize[32], endSize[32], rate[32], jetLength[32], twist[32], density[32], material[PLATFORM_MAX_PATH];
    GetSmokeKey(itemId, "rgb_color", "0 255 0", rgb, sizeof(rgb));
    GetSmokeKey(itemId, "base_spread", "100", baseSpread, sizeof(baseSpread));
    GetSmokeKey(itemId, "spread_speed", "70", spreadSpeed, sizeof(spreadSpeed));
    GetSmokeKey(itemId, "speed", "80", speed, sizeof(speed));
    GetSmokeKey(itemId, "start_size", "200", startSize, sizeof(startSize));
    GetSmokeKey(itemId, "end_size", "2", endSize, sizeof(endSize));
    GetSmokeKey(itemId, "rate", "30", rate, sizeof(rate));
    GetSmokeKey(itemId, "jet_length", "150", jetLength, sizeof(jetLength));
    GetSmokeKey(itemId, "twist", "20", twist, sizeof(twist));
    GetSmokeKey(itemId, "density", "200", density, sizeof(density));
    GetSmokeKey(itemId, "material", "particle/particle_smokegrenade1.vmt", material, sizeof(material));

    DispatchKeyValueVector(smoke, "origin", origin);
    DispatchKeyValue(smoke, "BaseSpread", baseSpread);
    DispatchKeyValue(smoke, "SpreadSpeed", spreadSpeed);
    DispatchKeyValue(smoke, "Speed", speed);
    DispatchKeyValue(smoke, "StartSize", startSize);
    DispatchKeyValue(smoke, "EndSize", endSize);
    DispatchKeyValue(smoke, "Rate", rate);
    DispatchKeyValue(smoke, "JetLength", jetLength);
    DispatchKeyValue(smoke, "Twist", twist);
    DispatchKeyValue(smoke, "RenderColor", rgb);
    DispatchKeyValue(smoke, "RenderAmt", density);
    DispatchKeyValue(smoke, "SmokeMaterial", material);
    DispatchSpawn(smoke);
    AcceptEntityInput(smoke, "TurnOn");
    TrackColoredSmoke(smoke);

    float lifetime = USM_GetMetadataFloat(itemId, "lifetime", 10.0);
    if (lifetime > 0.0)
    {
        CreateTimer(lifetime, Timer_RemoveSmoke, EntIndexToEntRef(smoke), TIMER_FLAG_NO_MAPCHANGE);
    }

    return Plugin_Continue;
}

public Action Timer_RemoveSmoke(Handle timer, any ref)
{
    RemoveColoredSmokeByRef(ref);

    return Plugin_Stop;
}

void TrackColoredSmoke(int entity)
{
    if (g_aSmokeRefs == null)
    {
        return;
    }

    g_aSmokeRefs.Push(EntIndexToEntRef(entity));
}

void UntrackColoredSmoke(int ref)
{
    if (g_aSmokeRefs == null)
    {
        return;
    }

    int index = g_aSmokeRefs.FindValue(ref);
    if (index != -1)
    {
        g_aSmokeRefs.Erase(index);
    }
}

void RemoveColoredSmokeByRef(int ref, bool untrack = true)
{
    int entity = EntRefToEntIndex(ref);
    if (entity != INVALID_ENT_REFERENCE && entity > 0 && IsValidEntity(entity))
    {
        AcceptEntityInput(entity, "TurnOff");
        AcceptEntityInput(entity, "Kill");
    }

    if (untrack)
    {
        UntrackColoredSmoke(ref);
    }
}

void RemoveAllColoredSmokes()
{
    if (g_aSmokeRefs == null)
    {
        return;
    }

    for (int i = 0; i < g_aSmokeRefs.Length; i++)
    {
        RemoveColoredSmokeByRef(g_aSmokeRefs.Get(i), false);
    }

    g_aSmokeRefs.Clear();
}

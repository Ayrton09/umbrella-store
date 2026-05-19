#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <umbrella_store>
#include <umbrella_store_module_utils>

ConVar gCvarEnabled;
ConVar gCvarDefaultLife;

int g_iTrailEntity[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
bool g_bHideTrail[MAXPLAYERS + 1];
Cookie g_hHideCookie;

public Plugin myinfo =
{
    name = "[Umbrella Store] Trails",
    author = "Ayrton09",
    description = "Player sprite trail item module for Umbrella Store",
    version = "1.2.1",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store.phrases");

    gCvarEnabled = CreateConVar("umbrella_store_trails_enabled", "1", "Enable Umbrella Store player trails.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarDefaultLife = CreateConVar("umbrella_store_trails_default_life", "1.0", "Default trail lifetime in seconds.", FCVAR_NONE, true, 0.1, true, 10.0);
    AutoExecConfig(true, "umbrella_store_trails");

    g_hHideCookie = new Cookie("umbrella_store_hide_trails", "Hide Umbrella Store trails", CookieAccess_Private);

    US_RegisterItemType("trail", "trails", true, true);
    RegConsoleCmd("sm_hidetrail", Command_HideTrail);
    RegConsoleCmd("sm_hidetrails", Command_HideTrail);

    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
}

public void OnMapStart()
{
    PrecacheConfiguredTrails();
}

public void OnClientDisconnect(int client)
{
    RemoveTrail(client);
    g_bHideTrail[client] = false;
}

public void OnPluginEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        RemoveTrail(i);
    }
}

public void OnClientCookiesCached(int client)
{
    char value[8];
    g_hHideCookie.Get(client, value, sizeof(value));
    g_bHideTrail[client] = (value[0] != '\0' && StringToInt(value) != 0);
}

public Action Command_HideTrail(int client, int args)
{
    if (!USM_IsValidClient(client))
    {
        return Plugin_Handled;
    }

    g_bHideTrail[client] = !g_bHideTrail[client];
    if (AreClientCookiesCached(client))
    {
        g_hHideCookie.Set(client, g_bHideTrail[client] ? "1" : "0");
    }

    PrintToChat(client, "[Umbrella Store] %T", g_bHideTrail[client] ? "Module Hidden" : "Module Visible", client, "Trails");
    return Plugin_Handled;
}

void PrecacheConfiguredTrails()
{
    int count = US_GetItemCount();
    char itemId[64], type[32], material[PLATFORM_MAX_PATH];

    for (int i = 0; i < count; i++)
    {
        if (!US_GetItemIdByIndex(i, itemId, sizeof(itemId)) || !US_GetItemType(itemId, type, sizeof(type)) || !StrEqual(type, "trail", false))
        {
            continue;
        }

        USM_GetMetadata(itemId, "material", material, sizeof(material));
        if (material[0] == '\0')
        {
            LogError("[Umbrella Store] Trail item '%s' has no material.", itemId);
            continue;
        }

        if (FileExists(material, true))
        {
            PrecacheModel(material, true);
            USM_AddMaterialDownloads(material);
        }
        else
        {
            LogError("[Umbrella Store] Trail item '%s' material is missing: %s", itemId, material);
        }
    }
}

public void US_OnEquipPost(int client, const char[] itemId, bool equip)
{
    if (USM_ItemMatchesType(itemId, "trail"))
    {
        CreateTimer(0.1, Timer_RecreateTrail, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    CreateTimer(0.2, Timer_RecreateTrail, event.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    RemoveTrail(client);
    return Plugin_Continue;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    RemoveTrail(client);
    return Plugin_Continue;
}

public Action Timer_RecreateTrail(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    RemoveTrail(client);
    CreateTrail(client);
    return Plugin_Stop;
}

void RemoveTrail(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    int entity = EntRefToEntIndex(g_iTrailEntity[client]);
    g_iTrailEntity[client] = INVALID_ENT_REFERENCE;

    if (entity != INVALID_ENT_REFERENCE && entity > 0 && IsValidEntity(entity))
    {
        SDKUnhook(entity, SDKHook_SetTransmit, Hook_TrailTransmit);
        AcceptEntityInput(entity, "Kill");
    }
}

void CreateTrail(int client)
{
    if (!gCvarEnabled.BoolValue || !USM_IsPlayableClient(client, true))
    {
        return;
    }

    char itemId[64];
    if (!US_GetEquippedItem(client, "trail", itemId, sizeof(itemId)))
    {
        return;
    }

    char material[PLATFORM_MAX_PATH];
    USM_GetMetadata(itemId, "material", material, sizeof(material));
    if (material[0] == '\0' || !FileExists(material, true))
    {
        return;
    }

    char colorText[64], widthText[16], lifeText[16];
    int color[4];
    USM_GetMetadata(itemId, "color", colorText, sizeof(colorText), "255 255 255 255");
    USM_ParseColor(colorText, color);

    float width = USM_GetMetadataFloat(itemId, "width", 8.0);
    float life = USM_GetMetadataFloat(itemId, "lifetime", gCvarDefaultLife.FloatValue);
    FloatToString(width, widthText, sizeof(widthText));
    FloatToString(life, lifeText, sizeof(lifeText));

    int entity = CreateEntityByName("env_spritetrail");
    if (entity == -1)
    {
        return;
    }

    char renderColor[32], renderAlpha[8];
    Format(renderColor, sizeof(renderColor), "%d %d %d", color[0], color[1], color[2]);
    IntToString(color[3], renderAlpha, sizeof(renderAlpha));

    DispatchKeyValue(entity, "renderamt", renderAlpha);
    DispatchKeyValue(entity, "rendercolor", renderColor);
    DispatchKeyValue(entity, "lifetime", lifeText);
    DispatchKeyValue(entity, "rendermode", "5");
    DispatchKeyValue(entity, "spritename", material);
    DispatchKeyValue(entity, "startwidth", widthText);
    DispatchKeyValue(entity, "endwidth", widthText);
    DispatchSpawn(entity);

    float origin[3];
    GetClientAbsOrigin(client, origin);
    origin[2] += 8.0;
    TeleportEntity(entity, origin, NULL_VECTOR, NULL_VECTOR);

    SetVariantString("!activator");
    AcceptEntityInput(entity, "SetParent", client, entity);
    SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);

    g_iTrailEntity[client] = EntIndexToEntRef(entity);
    SDKHook(entity, SDKHook_SetTransmit, Hook_TrailTransmit);
}

public Action Hook_TrailTransmit(int entity, int client)
{
    if (USM_IsValidClient(client) && g_bHideTrail[client])
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

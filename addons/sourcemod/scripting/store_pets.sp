#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <umbrella_store>
#include <umbrella_store_module_utils>

ConVar gCvarEnabled;

int g_iPetEntity[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
bool g_bHidePet[MAXPLAYERS + 1];
Cookie g_hHideCookie;

public Plugin myinfo =
{
    name = "[Umbrella Store] Pets",
    author = "Ayrton09",
    description = "Attached pet model item module for Umbrella Store",
    version = "1.2.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store.phrases");

    gCvarEnabled = CreateConVar("umbrella_store_pets_enabled", "1", "Enable Umbrella Store pets.", FCVAR_NONE, true, 0.0, true, 1.0);
    AutoExecConfig(true, "umbrella_store_pets");

    g_hHideCookie = new Cookie("umbrella_store_hide_pets", "Hide Umbrella Store pets", CookieAccess_Private);

    US_RegisterItemType("pet", "pets", true, true);
    RegConsoleCmd("sm_hidepet", Command_HidePet);
    RegConsoleCmd("sm_hidepets", Command_HidePet);

    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerRemove, EventHookMode_Post);
    HookEvent("player_team", Event_PlayerRemove, EventHookMode_Post);
}

public void OnMapStart()
{
    PrecacheConfiguredPets();
}

public void OnClientDisconnect(int client)
{
    RemovePet(client);
    g_bHidePet[client] = false;
}

public void OnClientCookiesCached(int client)
{
    char value[8];
    g_hHideCookie.Get(client, value, sizeof(value));
    g_bHidePet[client] = (value[0] != '\0' && StringToInt(value) != 0);
}

public Action Command_HidePet(int client, int args)
{
    if (!USM_IsValidClient(client))
    {
        return Plugin_Handled;
    }

    g_bHidePet[client] = !g_bHidePet[client];
    if (AreClientCookiesCached(client))
    {
        g_hHideCookie.Set(client, g_bHidePet[client] ? "1" : "0");
    }

    PrintToChat(client, "[Umbrella Store] %T", g_bHidePet[client] ? "Module Hidden" : "Module Visible", client, "Pets");
    return Plugin_Handled;
}

void PrecacheConfiguredPets()
{
    int count = US_GetItemCount();
    char itemId[64], type[32], model[PLATFORM_MAX_PATH];

    for (int i = 0; i < count; i++)
    {
        if (!US_GetItemIdByIndex(i, itemId, sizeof(itemId)) || !US_GetItemType(itemId, type, sizeof(type)) || !StrEqual(type, "pet", false))
        {
            continue;
        }

        USM_GetMetadata(itemId, "model", model, sizeof(model));
        if (model[0] == '\0')
        {
            LogError("[Umbrella Store] Pet item '%s' has no model.", itemId);
            continue;
        }

        if (FileExists(model, true))
        {
            PrecacheModel(model, true);
            USM_AddModelDownloads(model);
            USM_AddConfiguredDownloads(itemId);
        }
        else
        {
            LogError("[Umbrella Store] Pet item '%s' model is missing: %s", itemId, model);
        }
    }
}

public void US_OnEquipPost(int client, const char[] itemId, bool equip)
{
    if (USM_ItemMatchesType(itemId, "pet"))
    {
        CreateTimer(0.1, Timer_RecreatePet, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    CreateTimer(0.2, Timer_RecreatePet, event.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

public Action Event_PlayerRemove(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    RemovePet(client);
    return Plugin_Continue;
}

public Action Timer_RecreatePet(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    RemovePet(client);
    CreatePet(client);
    return Plugin_Stop;
}

void RemovePet(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    int entity = EntRefToEntIndex(g_iPetEntity[client]);
    g_iPetEntity[client] = INVALID_ENT_REFERENCE;

    if (entity != INVALID_ENT_REFERENCE && entity > 0 && IsValidEntity(entity))
    {
        SDKUnhook(entity, SDKHook_SetTransmit, Hook_PetTransmit);
        AcceptEntityInput(entity, "Kill");
    }
}

void CreatePet(int client)
{
    if (!gCvarEnabled.BoolValue || !USM_IsPlayableClient(client, true))
    {
        return;
    }

    char itemId[64];
    if (!US_GetEquippedItem(client, "pet", itemId, sizeof(itemId)))
    {
        return;
    }

    char model[PLATFORM_MAX_PATH];
    USM_GetMetadata(itemId, "model", model, sizeof(model));
    if (model[0] == '\0' || !FileExists(model, true))
    {
        return;
    }

    char positionText[64], anglesText[64], idle[64];
    float defaultPosition[3] = { 40.0, -48.0, 8.0 };
    float defaultAngles[3] = { 0.0, 0.0, 0.0 };
    float offset[3], addAngles[3];
    USM_GetMetadata(itemId, "position", positionText, sizeof(positionText), "40 -48 8");
    USM_GetMetadata(itemId, "angles", anglesText, sizeof(anglesText), "0 0 0");
    USM_GetMetadata(itemId, "idle", idle, sizeof(idle));
    USM_ParseVector(positionText, offset, defaultPosition);
    USM_ParseVector(anglesText, addAngles, defaultAngles);

    float origin[3], angles[3], fwd[3], right[3], up[3];
    GetClientAbsOrigin(client, origin);
    GetClientAbsAngles(client, angles);
    angles[0] += addAngles[0];
    angles[1] += addAngles[1];
    angles[2] += addAngles[2];
    GetAngleVectors(angles, fwd, right, up);

    origin[0] += right[0] * offset[0] + fwd[0] * offset[1] + up[0] * offset[2];
    origin[1] += right[1] * offset[0] + fwd[1] * offset[1] + up[1] * offset[2];
    origin[2] += right[2] * offset[0] + fwd[2] * offset[1] + up[2] * offset[2];

    int entity = CreateEntityByName("prop_dynamic_override");
    if (entity == -1)
    {
        return;
    }

    DispatchKeyValue(entity, "model", model);
    DispatchKeyValue(entity, "spawnflags", "256");
    DispatchKeyValue(entity, "solid", "0");
    SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
    DispatchSpawn(entity);
    AcceptEntityInput(entity, "TurnOn");
    TeleportEntity(entity, origin, angles, NULL_VECTOR);

    SetVariantString("!activator");
    AcceptEntityInput(entity, "SetParent", client, entity);

    if (idle[0] != '\0')
    {
        SetVariantString(idle);
        AcceptEntityInput(entity, "SetAnimation");
    }

    g_iPetEntity[client] = EntIndexToEntRef(entity);
    SDKHook(entity, SDKHook_SetTransmit, Hook_PetTransmit);
}

public Action Hook_PetTransmit(int entity, int client)
{
    if (USM_IsValidClient(client) && g_bHidePet[client])
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <umbrella_store>
#include <umbrella_store_module_utils>

#define MAX_CLIENT_HATS 8

ConVar gCvarEnabled;
ConVar gCvarHideOwn;

int g_iHatEntities[MAXPLAYERS + 1][MAX_CLIENT_HATS];

public Plugin myinfo =
{
    name = "[Umbrella Store] Hats",
    author = "Ayrton09",
    description = "Attached hat model item module for Umbrella Store",
    version = "1.5.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store.phrases");

    gCvarEnabled = CreateConVar("umbrella_store_hats_enabled", "1", "Enable Umbrella Store hats.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarEnabled.AddChangeHook(Cvar_EnabledChanged);
    gCvarHideOwn = CreateConVar("umbrella_store_hats_hide_own", "1", "Hide a player's own hat in first person.", FCVAR_NONE, true, 0.0, true, 1.0);
    AutoExecConfig(true, "umbrella_store_hats");

    US_RegisterItemType("hat", "hats", true, false);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerRemove, EventHookMode_Post);
    HookEvent("player_team", Event_PlayerRemove, EventHookMode_Post);

    ResetHatRefs();
}

public void OnMapStart()
{
    ResetHatRefs();
    PrecacheConfiguredHats();
}

public void US_OnItemsReloaded(int itemCount)
{
    PrecacheConfiguredHats();
    RecreateAllHats();
}

public void OnClientDisconnect(int client)
{
    RemoveHats(client);
}

public void OnPluginEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        RemoveHats(i);
    }
}

void ResetHatRefs()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        for (int i = 0; i < MAX_CLIENT_HATS; i++)
        {
            g_iHatEntities[client][i] = INVALID_ENT_REFERENCE;
        }
    }
}

void PrecacheConfiguredHats()
{
    int count = US_GetItemCount();
    char itemId[64], type[32], model[PLATFORM_MAX_PATH];

    for (int i = 0; i < count; i++)
    {
        if (!US_GetItemIdByIndex(i, itemId, sizeof(itemId)) || !US_GetItemType(itemId, type, sizeof(type)) || !StrEqual(type, "hat", false))
        {
            continue;
        }

        USM_GetMetadata(itemId, "model", model, sizeof(model));
        if (model[0] == '\0')
        {
            LogError("[Umbrella Store] Hat item '%s' has no model.", itemId);
            continue;
        }

        if (FileExists(model, true))
        {
            PrecacheModel(model, true);
            USM_AddModelDownloads(model);
        }
        else
        {
            LogError("[Umbrella Store] Hat item '%s' model is missing: %s", itemId, model);
        }
    }
}

int GetHatSlot(const char[] itemId)
{
    return USM_GetMetadataInt(itemId, "slot", -1);
}

bool FindEquippedHatInSlot(int client, int slot, const char[] targetItemId, const char[] ignoreItemId = "")
{
    if (slot < 0)
    {
        return false;
    }

    char itemIds[MAX_CLIENT_HATS][64];
    int count = USM_GetEquippedItemsOfType(client, "hat", itemIds, sizeof(itemIds));
    for (int i = 0; i < count; i++)
    {
        if (ignoreItemId[0] != '\0' && StrEqual(itemIds[i], ignoreItemId))
        {
            continue;
        }

        if (targetItemId[0] != '\0' && !USM_ItemTeamsCanConflict(targetItemId, itemIds[i]))
        {
            continue;
        }

        if (GetHatSlot(itemIds[i]) == slot)
        {
            return true;
        }
    }

    return false;
}

public Action US_OnEquipPre(int client, const char[] itemId, bool equip)
{
    if (!equip || !USM_ItemMatchesType(itemId, "hat"))
    {
        return Plugin_Continue;
    }

    int slot = GetHatSlot(itemId);
    if (slot >= 0 && slot < MAX_CLIENT_HATS && FindEquippedHatInSlot(client, slot, itemId, itemId))
    {
        PrintToChat(client, "[Umbrella Store] %T", "Hat Slot In Use", client);
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public void US_OnEquipPost(int client, const char[] itemId, bool equip)
{
    if (USM_ItemMatchesType(itemId, "hat"))
    {
        CreateTimer(0.1, Timer_RecreateHats, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void US_OnStoreEnabledChanged(bool enabled)
{
    if (!enabled)
    {
        RemoveAllHats();
        return;
    }

    RecreateAllHats();
}

public void Cvar_EnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar.BoolValue)
    {
        RecreateAllHats();
    }
    else
    {
        RemoveAllHats();
    }
}

void RecreateAllHats()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (USM_IsPlayableClient(i, true))
        {
            CreateTimer(0.1, Timer_RecreateHats, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    CreateTimer(0.2, Timer_RecreateHats, event.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

public Action Event_PlayerRemove(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    RemoveHats(client);
    return Plugin_Continue;
}

public Action Timer_RecreateHats(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    RemoveHats(client);
    CreateHats(client);
    return Plugin_Stop;
}

void RemoveHats(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    for (int i = 0; i < MAX_CLIENT_HATS; i++)
    {
        int entity = EntRefToEntIndex(g_iHatEntities[client][i]);
        g_iHatEntities[client][i] = INVALID_ENT_REFERENCE;

        if (entity != INVALID_ENT_REFERENCE && entity > 0 && IsValidEntity(entity))
        {
            SDKUnhook(entity, SDKHook_SetTransmit, Hook_HatTransmit);
            AcceptEntityInput(entity, "Kill");
        }
    }
}

void RemoveAllHats()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        RemoveHats(i);
    }
}

void CreateHats(int client)
{
    if (!US_IsEnabled() || !gCvarEnabled.BoolValue || !USM_IsPlayableClient(client, true))
    {
        return;
    }

    char itemIds[MAX_CLIENT_HATS][64];
    int count = USM_GetEquippedItemsOfType(client, "hat", itemIds, sizeof(itemIds));
    bool usedSlots[MAX_CLIENT_HATS];

    for (int i = 0; i < count; i++)
    {
        if (!USM_ItemAllowedForClientTeam(client, itemIds[i]))
        {
            continue;
        }

        int slot = GetHatSlot(itemIds[i]);
        if (slot < 0 || slot >= MAX_CLIENT_HATS || usedSlots[slot])
        {
            slot = -1;
            for (int j = 0; j < MAX_CLIENT_HATS; j++)
            {
                if (!usedSlots[j])
                {
                    slot = j;
                    break;
                }
            }
        }

        if (slot == -1)
        {
            continue;
        }

        usedSlots[slot] = true;
        CreateHat(client, itemIds[i], slot);
    }
}

void ApplyBonemerge(int entity)
{
    int effects = GetEntProp(entity, Prop_Send, "m_fEffects");
    effects &= ~32;
    effects |= 1;
    effects |= 128;
    SetEntProp(entity, Prop_Send, "m_fEffects", effects);
}

void CreateHat(int client, const char[] itemId, int index)
{
    char model[PLATFORM_MAX_PATH];
    USM_GetMetadata(itemId, "model", model, sizeof(model));
    if (model[0] == '\0' || !FileExists(model, true))
    {
        return;
    }

    char positionText[64], anglesText[64], attachment[64];
    float defaultPosition[3] = { 0.0, 0.0, 72.0 };
    float defaultAngles[3] = { 0.0, 0.0, 0.0 };
    float offset[3], addAngles[3];
    USM_GetMetadata(itemId, "position", positionText, sizeof(positionText), "0 0 72");
    USM_GetMetadata(itemId, "angles", anglesText, sizeof(anglesText), "0 0 0");
    USM_GetMetadata(itemId, "attachment", attachment, sizeof(attachment), "forward");
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

    if (USM_GetMetadataBool(itemId, "bonemerge"))
    {
        ApplyBonemerge(entity);
    }

    TeleportEntity(entity, origin, angles, NULL_VECTOR);

    SetVariantString("!activator");
    AcceptEntityInput(entity, "SetParent", client, entity);

    SetVariantString(attachment);
    AcceptEntityInput(entity, "SetParentAttachmentMaintainOffset", entity, entity);

    g_iHatEntities[client][index] = EntIndexToEntRef(entity);
    SDKHook(entity, SDKHook_SetTransmit, Hook_HatTransmit);
}

public Action Hook_HatTransmit(int entity, int client)
{
    if (!gCvarHideOwn.BoolValue)
    {
        return Plugin_Continue;
    }

    int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    if (client == owner && !IsClientViewingOwnModel(client))
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

bool IsClientViewingOwnModel(int client)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return false;
    }

    if (HasEntProp(client, Prop_Send, "m_iObserverMode"))
    {
        return GetEntProp(client, Prop_Send, "m_iObserverMode") != 0;
    }

    return false;
}

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <umbrella_store>
#include <umbrella_store_module_utils>

#define PET_ANIM_NONE 0
#define PET_ANIM_RUN 1
#define PET_ANIM_IDLE 2
#define PET_ANIM_DEATH 3

ConVar gCvarEnabled;
ConVar gCvarFollowMode;

int g_iPetEntity[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
bool g_bPetThinkHooked[MAXPLAYERS + 1];
bool g_bHidePet[MAXPLAYERS + 1];
int g_iLastAnimation[MAXPLAYERS + 1];
int g_iNextRareIdleAt[MAXPLAYERS + 1];
float g_fAnimationBlockedUntil[MAXPLAYERS + 1];
float g_fNextMoveAt[MAXPLAYERS + 1];
Cookie g_hHideCookie;

char g_sPetItem[MAXPLAYERS + 1][64];
char g_sPetIdle[MAXPLAYERS + 1][64];
char g_sPetIdle2[MAXPLAYERS + 1][64];
char g_sPetRun[MAXPLAYERS + 1][64];
float g_fPetOffset[MAXPLAYERS + 1][3];
float g_fPetAngles[MAXPLAYERS + 1][3];

public Plugin myinfo =
{
    name = "[Umbrella Store] Pets",
    author = "Ayrton09",
    description = "Pet model item module for Umbrella Store",
    version = "1.4.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store.phrases");

    gCvarEnabled = CreateConVar("umbrella_store_pets_enabled", "1", "Enable Umbrella Store pets.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarEnabled.AddChangeHook(Cvar_PetsChanged);
    gCvarFollowMode = CreateConVar("umbrella_store_pets_follow_mode", "0", "Pet follow mode: 0 = legacy attached to player, 1 = moving follower.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarFollowMode.AddChangeHook(Cvar_PetsChanged);
    AutoExecConfig(true, "umbrella_store_pets");

    g_hHideCookie = new Cookie("umbrella_store_hide_pets", "Hide Umbrella Store pets", CookieAccess_Private);

    US_RegisterItemType("pet", "pets", true, true);
    RegConsoleCmd("sm_hidepet", Command_HidePet);
    RegConsoleCmd("sm_hidepets", Command_HidePet);

    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
}

public void OnMapStart()
{
    PrecacheConfiguredPets();
}

public void OnMapEnd()
{
    RemoveAllPets();
}

public void OnClientPutInServer(int client)
{
    ResetPetState(client);
}

public void OnClientDisconnect(int client)
{
    RemovePet(client);
    ResetPetState(client);
}

public void OnPluginEnd()
{
    RemoveAllPets();
}

public void OnClientCookiesCached(int client)
{
    char value[8];
    g_hHideCookie.Get(client, value, sizeof(value));
    g_bHidePet[client] = (value[0] != '\0' && StringToInt(value) != 0);
}

public void US_OnClientLoaded(int client)
{
    CreateTimer(0.2, Timer_RecreatePet, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public void US_OnItemsReloaded(int itemCount)
{
    PrecacheConfiguredPets();
    RecreateAllPets();
}

public void US_OnStoreEnabledChanged(bool enabled)
{
    if (!enabled)
    {
        RemoveAllPets();
        return;
    }

    RecreateAllPets();
}

public void Cvar_PetsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (gCvarEnabled.BoolValue)
    {
        RecreateAllPets();
    }
    else
    {
        RemoveAllPets();
    }
}

bool UseMovingPetMode()
{
    return gCvarFollowMode != null && gCvarFollowMode.IntValue == 1;
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

void ResetPetState(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    g_iPetEntity[client] = INVALID_ENT_REFERENCE;
    g_bPetThinkHooked[client] = false;
    g_bHidePet[client] = false;
    g_iLastAnimation[client] = PET_ANIM_NONE;
    g_iNextRareIdleAt[client] = 0;
    g_fAnimationBlockedUntil[client] = 0.0;
    g_fNextMoveAt[client] = 0.0;
    g_sPetItem[client][0] = '\0';
    g_sPetIdle[client][0] = '\0';
    g_sPetIdle2[client][0] = '\0';
    g_sPetRun[client][0] = '\0';
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

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client < 1)
    {
        return Plugin_Continue;
    }

    PlayDeathAnimationOrRemove(client);
    return Plugin_Continue;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client < 1)
    {
        return Plugin_Continue;
    }

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

void RecreateAllPets()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (USM_IsPlayableClient(i, true))
        {
            CreateTimer(0.1, Timer_RecreatePet, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

void RemoveAllPets()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        RemovePet(i);
    }
}

void HookPetThink(int client)
{
    if (!g_bPetThinkHooked[client])
    {
        SDKHook(client, SDKHook_PreThink, Hook_PetThink);
        g_bPetThinkHooked[client] = true;
    }
}

void UnhookPetThink(int client)
{
    if (client >= 1 && client <= MaxClients && g_bPetThinkHooked[client])
    {
        SDKUnhook(client, SDKHook_PreThink, Hook_PetThink);
        g_bPetThinkHooked[client] = false;
    }
}

void RemovePet(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    UnhookPetThink(client);

    int entity = EntRefToEntIndex(g_iPetEntity[client]);
    g_iPetEntity[client] = INVALID_ENT_REFERENCE;
    g_iLastAnimation[client] = PET_ANIM_NONE;
    g_fAnimationBlockedUntil[client] = 0.0;

    if (entity != INVALID_ENT_REFERENCE && entity > 0 && IsValidEntity(entity))
    {
        SDKUnhook(entity, SDKHook_SetTransmit, Hook_PetTransmit);
        AcceptEntityInput(entity, "Kill");
    }
}

bool CachePetConfig(int client, const char[] itemId)
{
    char positionText[64], anglesText[64];
    float defaultPosition[3] = { 25.0, -20.0, 0.0 };
    float defaultAngles[3] = { 0.0, 0.0, 0.0 };

    USM_GetMetadata(itemId, "position", positionText, sizeof(positionText), "25 -20 0");
    USM_GetMetadata(itemId, "angles", anglesText, sizeof(anglesText), "0 0 0");
    USM_ParseVector(positionText, g_fPetOffset[client], defaultPosition);
    USM_ParseVector(anglesText, g_fPetAngles[client], defaultAngles);

    USM_GetMetadata(itemId, "idle", g_sPetIdle[client], sizeof(g_sPetIdle[]), "");
    USM_GetMetadata(itemId, "idle2", g_sPetIdle2[client], sizeof(g_sPetIdle2[]), "");
    USM_GetMetadata(itemId, "run", g_sPetRun[client], sizeof(g_sPetRun[]), "");
    strcopy(g_sPetItem[client], sizeof(g_sPetItem[]), itemId);

    return true;
}

void ApplyModelScaleIfSupported(int entity, float scale)
{
    if (scale <= 0.0 || FloatAbs(scale - 1.0) < 0.001)
    {
        return;
    }

    if (FindSendPropInfo("CBaseAnimating", "m_flModelScale") != -1)
    {
        SetEntPropFloat(entity, Prop_Send, "m_flModelScale", scale);
    }
}

void CreatePet(int client)
{
    if (!US_IsEnabled() || !gCvarEnabled.BoolValue || !USM_IsPlayableClient(client, true))
    {
        return;
    }

    char itemId[64];
    if (!USM_GetEquippedItemForClientTeam(client, "pet", itemId, sizeof(itemId)))
    {
        return;
    }

    char model[PLATFORM_MAX_PATH];
    USM_GetMetadata(itemId, "model", model, sizeof(model));
    if (model[0] == '\0' || !FileExists(model, true))
    {
        return;
    }

    CachePetConfig(client, itemId);

    float origin[3], angles[3];
    GetPetSpawnPosition(client, origin, angles);

    int entity = CreateEntityByName("prop_dynamic_override");
    if (entity == -1)
    {
        return;
    }

    DispatchKeyValue(entity, "model", model);
    DispatchKeyValue(entity, "spawnflags", "256");
    DispatchKeyValue(entity, "solid", "0");
    SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
    ApplyModelScaleIfSupported(entity, USM_GetMetadataFloat(itemId, "scale", 1.0));

    DispatchSpawn(entity);
    AcceptEntityInput(entity, "TurnOn");
    TeleportEntity(entity, origin, angles, NULL_VECTOR);
    if (!UseMovingPetMode())
    {
        AttachLegacyPet(client, entity);
    }

    g_iPetEntity[client] = EntIndexToEntRef(entity);
    g_iLastAnimation[client] = PET_ANIM_NONE;
    g_iNextRareIdleAt[client] = GetTime() + 15;
    ClearAlwaysTransmitFlag(entity);
    SDKHook(entity, SDKHook_SetTransmit, Hook_PetTransmit);
    HookPetThink(client);

    char spawn[64];
    USM_GetMetadata(itemId, "spawn", spawn, sizeof(spawn));
    if (spawn[0] != '\0')
    {
        SetVariantString(spawn);
        AcceptEntityInput(entity, "SetAnimation");
        g_fAnimationBlockedUntil[client] = GetGameTime() + USM_GetMetadataFloat(itemId, "spawn_delay", 1.0);
    }
    else
    {
        SetPetIdleAnimation(client, false);
    }
}

void AttachLegacyPet(int client, int entity)
{
    SetVariantString("!activator");
    AcceptEntityInput(entity, "SetParent", client, entity, 0);
}

void GetPetSpawnPosition(int client, float origin[3], float angles[3])
{
    float clientAngles[3], fwd[3], right[3], up[3];
    GetClientAbsOrigin(client, origin);
    GetClientAbsAngles(client, clientAngles);

    angles[0] = g_fPetAngles[client][0];
    angles[1] = clientAngles[1] + g_fPetAngles[client][1];
    angles[2] = g_fPetAngles[client][2];

    GetAngleVectors(clientAngles, fwd, right, up);
    origin[0] += right[0] * g_fPetOffset[client][0] + fwd[0] * g_fPetOffset[client][1] + up[0] * g_fPetOffset[client][2];
    origin[1] += right[1] * g_fPetOffset[client][0] + fwd[1] * g_fPetOffset[client][1] + up[1] * g_fPetOffset[client][2];
    origin[2] += right[2] * g_fPetOffset[client][0] + fwd[2] * g_fPetOffset[client][1] + up[2] * g_fPetOffset[client][2];
}

void SetPetIdleAnimation(int client, bool allowRare)
{
    int entity = EntRefToEntIndex(g_iPetEntity[client]);
    if (entity == INVALID_ENT_REFERENCE || entity <= 0 || !IsValidEntity(entity))
    {
        return;
    }

    char animation[64];
    int now = GetTime();
    if (allowRare && g_sPetIdle2[client][0] != '\0' && now >= g_iNextRareIdleAt[client])
    {
        strcopy(animation, sizeof(animation), g_sPetIdle2[client]);
        g_iNextRareIdleAt[client] = now + 15;
        g_fAnimationBlockedUntil[client] = GetGameTime() + 2.0;
    }
    else if (g_sPetIdle[client][0] != '\0')
    {
        strcopy(animation, sizeof(animation), g_sPetIdle[client]);
    }

    if (animation[0] != '\0')
    {
        SetVariantString(animation);
        AcceptEntityInput(entity, "SetAnimation");
    }

    g_iLastAnimation[client] = PET_ANIM_IDLE;
}

void UpdatePetAnimation(int client)
{
    if (GetGameTime() < g_fAnimationBlockedUntil[client])
    {
        return;
    }

    int entity = EntRefToEntIndex(g_iPetEntity[client]);
    if (entity == INVALID_ENT_REFERENCE || entity <= 0 || !IsValidEntity(entity))
    {
        return;
    }

    float velocity[3];
    GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
    float speed = GetVectorLength(velocity);

    if (speed > 4.0 && g_sPetRun[client][0] != '\0')
    {
        if (g_iLastAnimation[client] != PET_ANIM_RUN)
        {
            SetVariantString(g_sPetRun[client]);
            AcceptEntityInput(entity, "SetAnimation");
            g_iLastAnimation[client] = PET_ANIM_RUN;
        }
    }
    else if (g_iLastAnimation[client] != PET_ANIM_IDLE || (g_sPetIdle2[client][0] != '\0' && GetTime() >= g_iNextRareIdleAt[client]))
    {
        SetPetIdleAnimation(client, true);
    }
}

public void Hook_PetThink(int client)
{
    if (!US_IsEnabled() || !gCvarEnabled.BoolValue || !USM_IsPlayableClient(client, true))
    {
        RemovePet(client);
        return;
    }

    int entity = EntRefToEntIndex(g_iPetEntity[client]);
    if (entity == INVALID_ENT_REFERENCE || entity <= 0 || !IsValidEntity(entity))
    {
        RemovePet(client);
        return;
    }

    bool movingMode = UseMovingPetMode();
    float now = GetGameTime();
    if (now < g_fNextMoveAt[client])
    {
        return;
    }
    g_fNextMoveAt[client] = now + (movingMode ? 0.03 : 0.15);

    if (movingMode)
    {
        MovePetTowardsOwner(client, entity);
    }
    UpdatePetAnimation(client);
}

void MovePetTowardsOwner(int client, int entity)
{
    float petPos[3], petAngles[3], clientPos[3], clientAngles[3], target[3];
    float fwd[3], right[3], up[3], delta[3];
    GetEntPropVector(entity, Prop_Data, "m_vecOrigin", petPos);
    GetEntPropVector(entity, Prop_Data, "m_angRotation", petAngles);
    GetClientAbsOrigin(client, clientPos);
    GetClientAbsAngles(client, clientAngles);
    GetAngleVectors(clientAngles, fwd, right, up);

    target[0] = clientPos[0] + right[0] * g_fPetOffset[client][0] + fwd[0] * g_fPetOffset[client][1];
    target[1] = clientPos[1] + right[1] * g_fPetOffset[client][0] + fwd[1] * g_fPetOffset[client][1];
    target[2] = clientPos[2] + 100.0;

    float distZ = GetClientDistanceToGround(entity, client, target[2]);
    if (distZ < 300.0 && distZ > -300.0)
    {
        target[2] -= distZ;
    }
    target[2] += g_fPetOffset[client][2];

    float distance = GetVectorDistance(petPos, target);
    if (distance > 1024.0)
    {
        GetPetSpawnPosition(client, petPos, petAngles);
        TeleportEntity(entity, petPos, petAngles, NULL_VECTOR);
        return;
    }

    if (distance > 4.0)
    {
        delta[0] = target[0] - petPos[0];
        delta[1] = target[1] - petPos[1];
        delta[2] = target[2] - petPos[2];
        NormalizeVector(delta, delta);

        float step = (distance - 64.0) / 54.0;
        step = ClampFloat(step, 0.35, 4.0);
        if (step > distance)
        {
            step = distance;
        }

        petPos[0] += delta[0] * step;
        petPos[1] += delta[1] * step;
        petPos[2] += delta[2] * step;
    }

    petAngles[0] = g_fPetAngles[client][0];
    petAngles[1] = RadToDeg(ArcTangent2(clientPos[1] - petPos[1], clientPos[0] - petPos[0])) + g_fPetAngles[client][1];
    petAngles[2] = g_fPetAngles[client][2];
    TeleportEntity(entity, petPos, petAngles, NULL_VECTOR);
}

void PlayDeathAnimationOrRemove(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    int entity = EntRefToEntIndex(g_iPetEntity[client]);
    if (entity == INVALID_ENT_REFERENCE || entity <= 0 || !IsValidEntity(entity))
    {
        RemovePet(client);
        return;
    }

    char death[64];
    if (g_sPetItem[client][0] == '\0' || !USM_GetMetadata(g_sPetItem[client], "death", death, sizeof(death)) || death[0] == '\0')
    {
        RemovePet(client);
        return;
    }

    UnhookPetThink(client);
    g_iLastAnimation[client] = PET_ANIM_DEATH;
    SetVariantString(death);
    AcceptEntityInput(entity, "SetAnimation");
    HookSingleEntityOutput(entity, "OnAnimationDone", Output_PetDeathAnimationDone, true);
    CreateTimer(5.0, Timer_KillPetEntity, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
}

public void Output_PetDeathAnimationDone(const char[] output, int caller, int activator, float delay)
{
    KillPetEntity(caller);
}

public Action Timer_KillPetEntity(Handle timer, any ref)
{
    int entity = EntRefToEntIndex(ref);
    if (entity != INVALID_ENT_REFERENCE && entity > 0 && IsValidEntity(entity))
    {
        KillPetEntity(entity);
    }

    return Plugin_Stop;
}

void KillPetEntity(int entity)
{
    int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    if (owner >= 1 && owner <= MaxClients && EntIndexToEntRef(entity) == g_iPetEntity[owner])
    {
        g_iPetEntity[owner] = INVALID_ENT_REFERENCE;
        g_iLastAnimation[owner] = PET_ANIM_NONE;
    }

    SDKUnhook(entity, SDKHook_SetTransmit, Hook_PetTransmit);
    AcceptEntityInput(entity, "Kill");
}

public Action Hook_PetTransmit(int entity, int client)
{
    ClearAlwaysTransmitFlag(entity);

    if (!US_IsEnabled())
    {
        return Plugin_Handled;
    }

    if (USM_IsValidClient(client) && g_bHidePet[client])
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

float ClampFloat(float value, float minValue, float maxValue)
{
    if (value < minValue)
    {
        return minValue;
    }

    if (value > maxValue)
    {
        return maxValue;
    }

    return value;
}

float GetClientDistanceToGround(int entity, int client, float zPosition)
{
    float origin[3], ground[3], angle[3];
    GetEntPropVector(entity, Prop_Data, "m_vecOrigin", origin);
    origin[2] = zPosition + 100.0;
    angle[0] = 90.0;

    TR_TraceRayFilter(origin, angle, MASK_PLAYERSOLID, RayType_Infinite, TraceRayNoPlayers, client);
    if (TR_DidHit())
    {
        TR_GetEndPosition(ground);
        origin[2] -= 100.0;
        return GetVectorDistance(origin, ground);
    }

    return 0.0;
}

public bool TraceRayNoPlayers(int entity, int mask, any data)
{
    if (entity == data || (entity >= 1 && entity <= MaxClients))
    {
        return false;
    }

    return true;
}

void ClearAlwaysTransmitFlag(int entity)
{
    int flags = GetEdictFlags(entity);
    if ((flags & FL_EDICT_ALWAYS) != 0)
    {
        SetEdictFlags(entity, flags ^ FL_EDICT_ALWAYS);
    }
}

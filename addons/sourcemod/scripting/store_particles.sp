#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <umbrella_store>
#include <umbrella_store_module_utils>

#define PARTICLE_AURA 0
#define PARTICLE_TRAIL 1
#define PARTICLE_SPAWN 2
#define PARTICLE_KILL 3
#define PARTICLE_HIT 4
#define PARTICLE_SLOT_COUNT 5

ConVar gCvarEnabled;

int g_iAttachedParticle[2][MAXPLAYERS + 1];
bool g_bHideParticles[MAXPLAYERS + 1];
Cookie g_hHideCookie;
StringMap g_mParticleIndexes = null;

public Plugin myinfo =
{
    name = "[Umbrella Store] Particles",
    author = "Ayrton09",
    description = "Aura, trail, spawn, kill, and hit particle item module for Umbrella Store",
    version = "1.2.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store.phrases");

    gCvarEnabled = CreateConVar("umbrella_store_particles_enabled", "1", "Enable Umbrella Store particles.", FCVAR_NONE, true, 0.0, true, 1.0);
    AutoExecConfig(true, "umbrella_store_particles");

    g_hHideCookie = new Cookie("umbrella_store_hide_particles", "Hide Umbrella Store particles", CookieAccess_Private);

    US_RegisterItemType("particle", "particles", true, false);
    RegConsoleCmd("sm_hideparticle", Command_HideParticles);
    RegConsoleCmd("sm_hideparticles", Command_HideParticles);

    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("bullet_impact", Event_BulletImpact, EventHookMode_Post);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
}

public void OnMapStart()
{
    delete g_mParticleIndexes;
    g_mParticleIndexes = new StringMap();
    PrecacheConfiguredParticles();
}

public void OnPluginEnd()
{
    delete g_mParticleIndexes;
}

public void OnClientDisconnect(int client)
{
    RemoveAttachedParticle(client, PARTICLE_AURA);
    RemoveAttachedParticle(client, PARTICLE_TRAIL);
    g_bHideParticles[client] = false;
}

public void OnClientCookiesCached(int client)
{
    char value[8];
    g_hHideCookie.Get(client, value, sizeof(value));
    g_bHideParticles[client] = (value[0] != '\0' && StringToInt(value) != 0);
}

public Action Command_HideParticles(int client, int args)
{
    if (!USM_IsValidClient(client))
    {
        return Plugin_Handled;
    }

    g_bHideParticles[client] = !g_bHideParticles[client];
    if (AreClientCookiesCached(client))
    {
        g_hHideCookie.Set(client, g_bHideParticles[client] ? "1" : "0");
    }

    PrintToChat(client, "[Umbrella Store] %T", g_bHideParticles[client] ? "Module Hidden" : "Module Visible", client, "Particles");
    return Plugin_Handled;
}

bool GetParticleEffectName(const char[] itemId, char[] effect, int maxlen)
{
    return USM_GetMetadata(itemId, "effect", effect, maxlen) && effect[0] != '\0';
}

bool GetParticleFile(const char[] itemId, char[] file, int maxlen)
{
    return USM_GetMetadata(itemId, "file", file, maxlen) && file[0] != '\0';
}

int GetParticleSlotFromName(const char[] slotName)
{
    if (StrEqual(slotName, "aura", false))
    {
        return PARTICLE_AURA;
    }
    if (StrEqual(slotName, "trail", false))
    {
        return PARTICLE_TRAIL;
    }
    if (StrEqual(slotName, "spawn", false))
    {
        return PARTICLE_SPAWN;
    }
    if (StrEqual(slotName, "kill", false))
    {
        return PARTICLE_KILL;
    }
    if (StrEqual(slotName, "hit", false))
    {
        return PARTICLE_HIT;
    }

    return -1;
}

int GetParticleSlot(const char[] itemId)
{
    char slotName[32];
    USM_GetMetadata(itemId, "slot", slotName, sizeof(slotName));
    return GetParticleSlotFromName(slotName);
}

void PrecacheConfiguredParticles()
{
    int count = US_GetItemCount();
    char itemId[64], type[32], effect[64], file[PLATFORM_MAX_PATH];

    for (int i = 0; i < count; i++)
    {
        if (!US_GetItemIdByIndex(i, itemId, sizeof(itemId)) || !US_GetItemType(itemId, type, sizeof(type)) || !StrEqual(type, "particle", false))
        {
            continue;
        }

        if (!GetParticleEffectName(itemId, effect, sizeof(effect)))
        {
            LogError("[Umbrella Store] Particle item '%s' has no effect.", itemId);
            continue;
        }

        if (!GetParticleFile(itemId, file, sizeof(file)) || !FileExists(file, true))
        {
            LogError("[Umbrella Store] Particle item '%s' is missing file: %s", itemId, file);
            continue;
        }

        PrecacheParticleSystem(effect);
        PrecacheGeneric(file, true);
        AddFileToDownloadsTable(file);
        USM_AddConfiguredDownloads(itemId);
    }
}

bool GetEquippedParticleForSlot(int client, int slot, char[] itemId, int maxlen)
{
    char items[USM_MAX_EQUIPPED_ITEMS][64], slotName[32];
    int count = USM_GetEquippedItemsOfType(client, "particle", items, sizeof(items));

    for (int i = 0; i < count; i++)
    {
        USM_GetMetadata(items[i], "slot", slotName, sizeof(slotName));
        if (GetParticleSlotFromName(slotName) == slot)
        {
            strcopy(itemId, maxlen, items[i]);
            return true;
        }
    }

    return false;
}

public Action US_OnEquipPre(int client, const char[] itemId, bool equip)
{
    if (!equip || !USM_ItemMatchesType(itemId, "particle"))
    {
        return Plugin_Continue;
    }

    int slot = GetParticleSlot(itemId);
    if (slot < 0)
    {
        return Plugin_Continue;
    }

    char equipped[USM_MAX_EQUIPPED_ITEMS][64], otherSlotName[32];
    int count = USM_GetEquippedItemsOfType(client, "particle", equipped, sizeof(equipped));

    for (int i = 0; i < count; i++)
    {
        if (StrEqual(equipped[i], itemId, false))
        {
            continue;
        }

        USM_GetMetadata(equipped[i], "slot", otherSlotName, sizeof(otherSlotName));
        if (GetParticleSlotFromName(otherSlotName) == slot)
        {
            PrintToChat(client, "[Umbrella Store] %T", "Particle Slot In Use", client);
            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}

public void US_OnEquipPost(int client, const char[] itemId, bool equip)
{
    if (!USM_ItemMatchesType(itemId, "particle"))
    {
        return;
    }

    int slot = GetParticleSlot(itemId);
    if (slot != PARTICLE_AURA && slot != PARTICLE_TRAIL)
    {
        return;
    }

    if (equip)
    {
        SetAttachedParticle(client, slot);
    }
    else
    {
        RemoveAttachedParticle(client, slot);
    }
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    int team = event.GetInt("team");
    if (team <= 1)
    {
        RemoveAttachedParticle(client, PARTICLE_AURA);
        RemoveAttachedParticle(client, PARTICLE_TRAIL);
    }

    return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    RemoveAttachedParticle(victim, PARTICLE_AURA);
    RemoveAttachedParticle(victim, PARTICLE_TRAIL);

    if (!gCvarEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (!USM_IsPlayableClient(victim) || !USM_IsPlayableClient(attacker) || attacker == victim)
    {
        return Plugin_Continue;
    }

    char itemId[64];
    if (!GetEquippedParticleForSlot(attacker, PARTICLE_KILL, itemId, sizeof(itemId)))
    {
        return Plugin_Continue;
    }

    float origin[3];
    GetClientAbsOrigin(victim, origin);
    SpawnPointParticle(itemId, origin);

    return Plugin_Continue;
}

public Action Event_BulletImpact(Event event, const char[] name, bool dontBroadcast)
{
    if (!gCvarEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!USM_IsPlayableClient(client, true))
    {
        return Plugin_Continue;
    }

    char itemId[64];
    if (!GetEquippedParticleForSlot(client, PARTICLE_HIT, itemId, sizeof(itemId)))
    {
        return Plugin_Continue;
    }

    float origin[3];
    origin[0] = event.GetFloat("x");
    origin[1] = event.GetFloat("y");
    origin[2] = event.GetFloat("z");
    SpawnPointParticle(itemId, origin);

    return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        CreateTimer(0.1, Timer_ApplySpawnParticles, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }

    return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        RemoveAttachedParticle(i, PARTICLE_AURA);
        RemoveAttachedParticle(i, PARTICLE_TRAIL);
    }

    return Plugin_Continue;
}

public Action Timer_ApplySpawnParticles(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!USM_IsPlayableClient(client, true))
    {
        return Plugin_Stop;
    }

    SetAttachedParticle(client, PARTICLE_AURA);
    SetAttachedParticle(client, PARTICLE_TRAIL);

    if (gCvarEnabled.BoolValue)
    {
        char itemId[64];
        if (GetEquippedParticleForSlot(client, PARTICLE_SPAWN, itemId, sizeof(itemId)))
        {
            float origin[3];
            GetClientAbsOrigin(client, origin);
            SpawnPointParticle(itemId, origin);
        }
    }

    return Plugin_Stop;
}

void SetAttachedParticle(int client, int slot)
{
    if (!gCvarEnabled.BoolValue || (slot != PARTICLE_AURA && slot != PARTICLE_TRAIL) || !USM_IsPlayableClient(client, true))
    {
        return;
    }

    RemoveAttachedParticle(client, slot);

    char itemId[64], effect[64], file[PLATFORM_MAX_PATH];
    if (!GetEquippedParticleForSlot(client, slot, itemId, sizeof(itemId)) || !GetParticleEffectName(itemId, effect, sizeof(effect)) || !GetParticleFile(itemId, file, sizeof(file)) || !FileExists(file, true))
    {
        return;
    }

    PrecacheParticleSystem(effect);
    PrecacheGeneric(file, true);

    float origin[3];
    GetClientAbsOrigin(client, origin);

    int particle = CreateEntityByName("info_particle_system");
    if (particle == -1)
    {
        return;
    }

    DispatchKeyValue(particle, "start_active", "0");
    DispatchKeyValue(particle, "effect_name", effect);
    DispatchSpawn(particle);
    ActivateEntity(particle);
    TeleportEntity(particle, origin, NULL_VECTOR, NULL_VECTOR);

    SetVariantString("!activator");
    AcceptEntityInput(particle, "SetParent", client, particle, 0);

    g_iAttachedParticle[slot][client] = EntIndexToEntRef(particle);
    CreateTimer(0.1, Timer_StartParticle, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
}

void RemoveAttachedParticle(int client, int slot)
{
    if (client < 1 || client > MaxClients || (slot != PARTICLE_AURA && slot != PARTICLE_TRAIL))
    {
        return;
    }

    int entity = EntRefToEntIndex(g_iAttachedParticle[slot][client]);
    if (entity != INVALID_ENT_REFERENCE && entity > 0 && IsValidEdict(entity))
    {
        SDKUnhook(entity, SDKHook_SetTransmit, Hook_SetTransmit);
        AcceptEntityInput(entity, "Kill");
    }

    g_iAttachedParticle[slot][client] = 0;
}

void SpawnPointParticle(const char[] itemId, float origin[3])
{
    char effect[64], file[PLATFORM_MAX_PATH];
    if (!GetParticleEffectName(itemId, effect, sizeof(effect)) || !GetParticleFile(itemId, file, sizeof(file)) || !FileExists(file, true))
    {
        return;
    }

    PrecacheParticleSystem(effect);
    PrecacheGeneric(file, true);

    int particle = CreateEntityByName("info_particle_system");
    if (particle == -1)
    {
        return;
    }

    DispatchKeyValue(particle, "start_active", "0");
    DispatchKeyValue(particle, "effect_name", effect);
    DispatchSpawn(particle);
    ActivateEntity(particle);
    TeleportEntity(particle, origin, NULL_VECTOR, NULL_VECTOR);
    AcceptEntityInput(particle, "Start");
    ClearAlwaysTransmitFlag(particle);
    SDKHook(particle, SDKHook_SetTransmit, Hook_SetTransmit);

    float duration = USM_GetMetadataFloat(itemId, "duration", 1.5);
    if (duration <= 0.0)
    {
        duration = 1.5;
    }
    CreateTimer(duration, Timer_ClearParticle, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_StartParticle(Handle timer, any ref)
{
    int entity = EntRefToEntIndex(ref);
    if (entity != INVALID_ENT_REFERENCE && entity > 0 && IsValidEdict(entity))
    {
        AcceptEntityInput(entity, "Start");
        ClearAlwaysTransmitFlag(entity);
        SDKHook(entity, SDKHook_SetTransmit, Hook_SetTransmit);
    }

    return Plugin_Stop;
}

public Action Timer_ClearParticle(Handle timer, any ref)
{
    int entity = EntRefToEntIndex(ref);
    if (entity != INVALID_ENT_REFERENCE && entity > 0 && IsValidEdict(entity))
    {
        SDKUnhook(entity, SDKHook_SetTransmit, Hook_SetTransmit);
        AcceptEntityInput(entity, "Kill");
    }

    return Plugin_Stop;
}

public Action Hook_SetTransmit(int entity, int client)
{
    ClearAlwaysTransmitFlag(entity);

    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    return g_bHideParticles[client] ? Plugin_Handled : Plugin_Continue;
}

void ClearAlwaysTransmitFlag(int entity)
{
    int flags = GetEdictFlags(entity);
    if ((flags & FL_EDICT_ALWAYS) != 0)
    {
        SetEdictFlags(entity, flags ^ FL_EDICT_ALWAYS);
    }
}

int PrecacheParticleSystem(const char[] particleSystem)
{
    static int particleEffectNames = INVALID_STRING_TABLE;

    int cached = INVALID_STRING_INDEX;
    if (g_mParticleIndexes != null && g_mParticleIndexes.GetValue(particleSystem, cached))
    {
        return cached;
    }

    if (particleEffectNames == INVALID_STRING_TABLE)
    {
        particleEffectNames = FindStringTable("ParticleEffectNames");
        if (particleEffectNames == INVALID_STRING_TABLE)
        {
            return INVALID_STRING_INDEX;
        }
    }

    int index = FindStringIndexInTable(particleEffectNames, particleSystem);
    if (index != INVALID_STRING_INDEX)
    {
        if (g_mParticleIndexes != null)
        {
            g_mParticleIndexes.SetValue(particleSystem, index);
        }
        return index;
    }

    int count = GetStringTableNumStrings(particleEffectNames);
    if (count >= GetStringTableMaxStrings(particleEffectNames))
    {
        return INVALID_STRING_INDEX;
    }

    AddToStringTable(particleEffectNames, particleSystem);
    if (g_mParticleIndexes != null)
    {
        g_mParticleIndexes.SetValue(particleSystem, count);
    }
    return count;
}

int FindStringIndexInTable(int tableidx, const char[] value)
{
    char current[1024];
    int count = GetStringTableNumStrings(tableidx);
    for (int i = 0; i < count; i++)
    {
        ReadStringTable(tableidx, i, current, sizeof(current));
        if (StrEqual(current, value))
        {
            return i;
        }
    }

    return INVALID_STRING_INDEX;
}

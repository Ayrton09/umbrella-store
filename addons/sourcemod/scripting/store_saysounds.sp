#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <umbrella_store>
#include <umbrella_store_module_utils>

ConVar gCvarEnabled;
ConVar gCvarMaxUses;
ConVar gCvarResetMode;
ConVar gCvarDefaultCooldown;
ConVar gCvarDefaultVolume;

int g_iUses[MAXPLAYERS + 1];
int g_iNextSoundTime[MAXPLAYERS + 1];
ArrayList g_aSaySoundItems = null;

public Plugin myinfo =
{
    name = "[Umbrella Store] Say Sounds",
    author = "Ayrton09",
    description = "Chat-triggered sound item module for Umbrella Store",
    version = "1.5.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store.phrases");

    gCvarEnabled = CreateConVar("umbrella_store_saysounds_enabled", "1", "Enable Umbrella Store say sounds.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarMaxUses = CreateConVar("umbrella_store_saysounds_max_uses", "3", "Maximum say sound uses per reset window. 0 = unlimited.", FCVAR_NONE, true, 0.0);
    gCvarResetMode = CreateConVar("umbrella_store_saysounds_reset_mode", "1", "0 = reset on map, 1 = reset on round.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarDefaultCooldown = CreateConVar("umbrella_store_saysounds_default_cooldown", "30", "Default per-player cooldown in seconds.", FCVAR_NONE, true, 0.0);
    gCvarDefaultVolume = CreateConVar("umbrella_store_saysounds_default_volume", "0.8", "Default say sound volume.", FCVAR_NONE, true, 0.05, true, 1.0);
    AutoExecConfig(true, "umbrella_store_saysounds");

    US_RegisterItemType("saysound", "say_sounds", false, false);
    HookEvent("player_say", Event_PlayerSay, EventHookMode_Post);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
    ResetUses();
    RebuildSaySoundCache();
    PrecacheConfiguredSounds();
}

public void US_OnItemsReloaded(int itemCount)
{
    RebuildSaySoundCache();
    PrecacheConfiguredSounds();
}

public void OnPluginEnd()
{
    delete g_aSaySoundItems;
}

public void OnClientDisconnect(int client)
{
    g_iUses[client] = 0;
    g_iNextSoundTime[client] = 0;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (gCvarResetMode.IntValue == 1)
    {
        ResetUses();
    }

    return Plugin_Continue;
}

void ResetUses()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iUses[i] = 0;
    }
}

void PrecacheConfiguredSounds()
{
    if (g_aSaySoundItems == null)
    {
        RebuildSaySoundCache();
    }

    char itemId[64], sound[PLATFORM_MAX_PATH], download[PLATFORM_MAX_PATH];
    for (int i = 0; i < g_aSaySoundItems.Length; i++)
    {
        g_aSaySoundItems.GetString(i, itemId, sizeof(itemId));

        USM_GetMetadata(itemId, "sound", sound, sizeof(sound));
        if (sound[0] == '\0')
        {
            LogError("[Umbrella Store] Say sound item '%s' has no sound.", itemId);
            continue;
        }

        Format(download, sizeof(download), "sound/%s", sound);
        if (FileExists(download, true))
        {
            PrecacheSound(sound, true);
            AddFileToDownloadsTable(download);
        }
        else
        {
            LogError("[Umbrella Store] Say sound item '%s' sound is missing: %s", itemId, download);
        }
    }
}

void RebuildSaySoundCache()
{
    delete g_aSaySoundItems;
    g_aSaySoundItems = new ArrayList(ByteCountToCells(64));

    int count = US_GetItemCount();
    char itemId[64], type[32];
    for (int i = 0; i < count; i++)
    {
        if (!US_GetItemIdByIndex(i, itemId, sizeof(itemId)) || !US_GetItemType(itemId, type, sizeof(type)) || !StrEqual(type, "saysound", false))
        {
            continue;
        }

        g_aSaySoundItems.PushString(itemId);
    }
}

bool TextMatchesTrigger(const char[] text, const char[] trigger)
{
    if (trigger[0] == '\0')
    {
        return false;
    }

    if (StrEqual(text, trigger, false))
    {
        return true;
    }

    char bangTrigger[96];
    Format(bangTrigger, sizeof(bangTrigger), "!%s", trigger);
    return StrEqual(text, bangTrigger, false);
}

bool FindTriggeredSound(int client, const char[] text, char[] itemId, int itemMax)
{
    if (g_aSaySoundItems == null)
    {
        RebuildSaySoundCache();
    }

    char currentId[64], trigger[64];

    for (int i = 0; i < g_aSaySoundItems.Length; i++)
    {
        g_aSaySoundItems.GetString(i, currentId, sizeof(currentId));
        if (!US_HasItem(client, currentId))
        {
            continue;
        }

        if (!USM_ItemAllowedForClientTeam(client, currentId))
        {
            continue;
        }

        USM_GetMetadata(currentId, "trigger", trigger, sizeof(trigger));
        if (TextMatchesTrigger(text, trigger))
        {
            strcopy(itemId, itemMax, currentId);
            return true;
        }
    }

    return false;
}

public Action Event_PlayerSay(Event event, const char[] name, bool dontBroadcast)
{
    if (!US_IsEnabled() || !gCvarEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!USM_IsValidClient(client) || !US_IsLoaded(client))
    {
        return Plugin_Continue;
    }

    char text[192];
    event.GetString("text", text, sizeof(text));
    StripQuotes(text);
    TrimString(text);

    char itemId[64];
    if (!FindTriggeredSound(client, text, itemId, sizeof(itemId)))
    {
        return Plugin_Continue;
    }

    int now = GetTime();
    if (g_iNextSoundTime[client] > now)
    {
        PrintToChat(client, "[Umbrella Store] %T", "Say Sound Cooldown", client, g_iNextSoundTime[client] - now);
        return Plugin_Continue;
    }

    int maxUses = gCvarMaxUses.IntValue;
    if (maxUses > 0 && g_iUses[client] >= maxUses)
    {
        PrintToChat(client, "[Umbrella Store] %T", "Say Sound Limit Reached", client);
        return Plugin_Continue;
    }

    char sound[PLATFORM_MAX_PATH], download[PLATFORM_MAX_PATH];
    USM_GetMetadata(itemId, "sound", sound, sizeof(sound));
    Format(download, sizeof(download), "sound/%s", sound);
    if (sound[0] == '\0' || !FileExists(download, true))
    {
        LogError("[Umbrella Store] Say sound item '%s' cannot play missing sound: %s", itemId, download);
        return Plugin_Continue;
    }

    int originMode = USM_GetMetadataInt(itemId, "origin", 1);
    float volume = USM_GetMetadataFloat(itemId, "volume", gCvarDefaultVolume.FloatValue);
    int cooldown = USM_GetMetadataInt(itemId, "cooldown", gCvarDefaultCooldown.IntValue);

    PrecacheSound(sound, true);
    EmitSoundToAll(sound, originMode > 1 ? client : SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, volume);

    g_iUses[client]++;
    g_iNextSoundTime[client] = now + cooldown;
    return Plugin_Continue;
}

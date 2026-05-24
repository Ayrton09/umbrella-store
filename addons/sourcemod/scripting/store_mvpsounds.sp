#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <umbrella_store>
#include <umbrella_store_module_utils>

#define MVP_VOLUME_STEP 0.2

ConVar gCvarEnabled;
ConVar gCvarDefaultVolume;

float g_fPlayerVolume[MAXPLAYERS + 1];
Cookie g_hVolumeCookie;

public Plugin myinfo =
{
    name = "[Umbrella Store] MVP Sounds",
    author = "Ayrton09",
    description = "Round MVP sound item module for Umbrella Store",
    version = "1.3.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store.phrases");

    gCvarEnabled = CreateConVar("umbrella_store_mvpsounds_enabled", "1", "Enable Umbrella Store MVP sounds.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarDefaultVolume = CreateConVar("umbrella_store_mvpsounds_default_volume", "0.5", "Default MVP sound item volume.", FCVAR_NONE, true, 0.05, true, 1.0);
    AutoExecConfig(true, "umbrella_store_mvpsounds");

    g_hVolumeCookie = new Cookie("umbrella_store_mvpsound_volume", "Umbrella Store MVP sound volume", CookieAccess_Private);

    US_RegisterItemType("mvp_sound", "mvp_sounds", true, true);
    RegConsoleCmd("sm_mvpvolume", Command_MvpVolume);
    RegConsoleCmd("sm_mvpvol", Command_MvpVolume);
    HookEvent("round_mvp", Event_RoundMVP, EventHookMode_Post);

    for (int i = 1; i <= MaxClients; i++)
    {
        g_fPlayerVolume[i] = 1.0;
        if (USM_IsValidClient(i) && AreClientCookiesCached(i))
        {
            OnClientCookiesCached(i);
        }
    }
}

public void OnMapStart()
{
    PrecacheConfiguredSounds();
}

public void US_OnItemsReloaded(int itemCount)
{
    PrecacheConfiguredSounds();
}

public void OnClientPutInServer(int client)
{
    g_fPlayerVolume[client] = 1.0;
}

public void OnClientDisconnect(int client)
{
    g_fPlayerVolume[client] = 1.0;
}

public void OnClientCookiesCached(int client)
{
    char value[16];
    g_hVolumeCookie.Get(client, value, sizeof(value));
    if (value[0] != '\0')
    {
        g_fPlayerVolume[client] = ClampVolume(StringToFloat(value), 0.0);
    }
}

float ClampVolume(float value, float minValue)
{
    if (value < minValue)
    {
        return minValue;
    }

    if (value > 1.0)
    {
        return 1.0;
    }

    return value;
}

public Action Command_MvpVolume(int client, int args)
{
    if (!USM_IsValidClient(client))
    {
        return Plugin_Handled;
    }

    g_fPlayerVolume[client] -= MVP_VOLUME_STEP;
    if (g_fPlayerVolume[client] < 0.0)
    {
        g_fPlayerVolume[client] = 1.0;
    }

    char value[16];
    FloatToString(g_fPlayerVolume[client], value, sizeof(value));
    if (AreClientCookiesCached(client))
    {
        g_hVolumeCookie.Set(client, value);
    }

    PrintToChat(client, "[Umbrella Store] %T", "MVP Volume Set", client, RoundToNearest(g_fPlayerVolume[client] * 100.0));
    return Plugin_Handled;
}

void PrecacheConfiguredSounds()
{
    int count = US_GetItemCount();
    char itemId[64], type[32], sound[PLATFORM_MAX_PATH], download[PLATFORM_MAX_PATH];

    for (int i = 0; i < count; i++)
    {
        if (!US_GetItemIdByIndex(i, itemId, sizeof(itemId)) || !US_GetItemType(itemId, type, sizeof(type)) || !StrEqual(type, "mvp_sound", false))
        {
            continue;
        }

        USM_GetMetadata(itemId, "sound", sound, sizeof(sound));
        Format(download, sizeof(download), "sound/%s", sound);
        if (sound[0] == '\0' || !FileExists(download, true))
        {
            LogError("[Umbrella Store] MVP sound item '%s' is missing sound: %s", itemId, download);
            continue;
        }

        PrecacheSound(sound, true);
        AddFileToDownloadsTable(download);
    }
}

public Action Event_RoundMVP(Event event, const char[] name, bool dontBroadcast)
{
    if (!US_IsEnabled() || !gCvarEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!USM_IsValidClient(client))
    {
        return Plugin_Continue;
    }

    char itemId[64], sound[PLATFORM_MAX_PATH], download[PLATFORM_MAX_PATH];
    if (!USM_GetEquippedItemForClientTeam(client, "mvp_sound", itemId, sizeof(itemId)))
    {
        return Plugin_Continue;
    }

    USM_GetMetadata(itemId, "sound", sound, sizeof(sound));
    Format(download, sizeof(download), "sound/%s", sound);
    if (sound[0] == '\0' || !FileExists(download, true))
    {
        LogError("[Umbrella Store] MVP sound item '%s' cannot play missing sound: %s", itemId, download);
        return Plugin_Continue;
    }

    float itemVolume = ClampVolume(USM_GetMetadataFloat(itemId, "volume", gCvarDefaultVolume.FloatValue), 0.05);
    PrecacheSound(sound, true);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!USM_IsValidClient(i))
        {
            continue;
        }

        ClientCommand(i, "playgamesound Music.StopAllMusic");

        if (RoundToNearest(g_fPlayerVolume[i] * 100.0) > 0)
        {
            EmitSoundToClient(i, sound, SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NORMAL, SND_NOFLAGS, itemVolume * g_fPlayerVolume[i]);
        }
    }

    return Plugin_Continue;
}

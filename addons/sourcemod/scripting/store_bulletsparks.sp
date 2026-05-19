#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <umbrella_store>
#include <umbrella_store_module_utils>

ConVar gCvarEnabled;
ConVar gCvarMagnitude;
ConVar gCvarTrailLength;

bool g_bHideBulletSparks[MAXPLAYERS + 1];
Cookie g_hHideCookie;

public Plugin myinfo =
{
    name = "[Umbrella Store] Bullet Sparks",
    author = "Ayrton09",
    description = "Bullet spark impact item module for Umbrella Store",
    version = "1.2.2",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store.phrases");

    gCvarEnabled = CreateConVar("umbrella_store_bulletsparks_enabled", "1", "Enable Umbrella Store bullet sparks.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarMagnitude = CreateConVar("umbrella_store_bulletsparks_magnitude", "2500", "Spark magnitude.", FCVAR_NONE, true, 1.0);
    gCvarTrailLength = CreateConVar("umbrella_store_bulletsparks_trail_length", "5000", "Spark trail length.", FCVAR_NONE, true, 1.0);
    AutoExecConfig(true, "umbrella_store_bulletsparks");

    g_hHideCookie = new Cookie("umbrella_store_hide_bulletsparks", "Hide Umbrella Store bullet sparks", CookieAccess_Private);

    US_RegisterItemType("bulletsparks", "bullet_sparks", true, true);
    RegConsoleCmd("sm_hidebulletspark", Command_HideBulletSparks);
    RegConsoleCmd("sm_hidebulletsparks", Command_HideBulletSparks);
    HookEvent("bullet_impact", Event_BulletImpact, EventHookMode_Post);
}

public void OnClientDisconnect(int client)
{
    g_bHideBulletSparks[client] = false;
}

public void OnClientCookiesCached(int client)
{
    char value[8];
    g_hHideCookie.Get(client, value, sizeof(value));
    g_bHideBulletSparks[client] = (value[0] != '\0' && StringToInt(value) != 0);
}

public Action Command_HideBulletSparks(int client, int args)
{
    if (!USM_IsValidClient(client))
    {
        return Plugin_Handled;
    }

    g_bHideBulletSparks[client] = !g_bHideBulletSparks[client];
    if (AreClientCookiesCached(client))
    {
        g_hHideCookie.Set(client, g_bHideBulletSparks[client] ? "1" : "0");
    }

    PrintToChat(client, "[Umbrella Store] %T", g_bHideBulletSparks[client] ? "Module Hidden" : "Module Visible", client, "Bullet Sparks");
    return Plugin_Handled;
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
    if (!US_GetEquippedItem(client, "bulletsparks", itemId, sizeof(itemId)))
    {
        return Plugin_Continue;
    }

    int clients[MAXPLAYERS];
    int clientCount = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!USM_IsValidClient(i) || g_bHideBulletSparks[i])
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
    float direction[3] = {0.0, 0.0, 0.0};
    impact[0] = event.GetFloat("x");
    impact[1] = event.GetFloat("y");
    impact[2] = event.GetFloat("z");

    TE_SetupSparks(impact, direction, gCvarMagnitude.IntValue, gCvarTrailLength.IntValue);
    TE_Send(clients, clientCount);

    return Plugin_Continue;
}

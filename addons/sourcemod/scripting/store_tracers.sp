#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <umbrella_store>
#include <umbrella_store_module_utils>

ConVar gCvarEnabled;
ConVar gCvarMaterial;
ConVar gCvarLife;
ConVar gCvarWidth;

int g_iBeamModel = -1;
bool g_bHideTracer[MAXPLAYERS + 1];
Cookie g_hHideCookie;

public Plugin myinfo =
{
    name = "[Umbrella Store] Tracers",
    author = "Ayrton09",
    description = "Bullet tracer item module for Umbrella Store",
    version = "1.4.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store.phrases");

    gCvarEnabled = CreateConVar("umbrella_store_tracers_enabled", "1", "Enable Umbrella Store tracers.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarMaterial = CreateConVar("umbrella_store_tracers_material", "materials/sprites/laserbeam.vmt", "Beam material used by tracer items.");
    gCvarLife = CreateConVar("umbrella_store_tracers_life", "0.45", "Tracer lifetime in seconds.", FCVAR_NONE, true, 0.05, true, 5.0);
    gCvarWidth = CreateConVar("umbrella_store_tracers_width", "1.5", "Tracer beam width.", FCVAR_NONE, true, 0.1, true, 32.0);
    AutoExecConfig(true, "umbrella_store_tracers");

    g_hHideCookie = new Cookie("umbrella_store_hide_tracers", "Hide Umbrella Store tracers", CookieAccess_Private);

    US_RegisterItemType("tracer", "tracers", true, true);
    RegConsoleCmd("sm_hidetracer", Command_HideTracer);
    RegConsoleCmd("sm_hidetracers", Command_HideTracer);
    HookEvent("bullet_impact", Event_BulletImpact, EventHookMode_Post);
}

public void OnMapStart()
{
    char material[PLATFORM_MAX_PATH];
    gCvarMaterial.GetString(material, sizeof(material));

    if (material[0] != '\0' && FileExists(material, true))
    {
        g_iBeamModel = PrecacheModel(material, true);
        USM_AddMaterialDownloads(material);
    }
    else
    {
        g_iBeamModel = -1;
        LogError("[Umbrella Store] Tracer material is missing: %s", material);
    }
}

public void OnClientDisconnect(int client)
{
    g_bHideTracer[client] = false;
}

public void OnClientCookiesCached(int client)
{
    char value[8];
    g_hHideCookie.Get(client, value, sizeof(value));
    g_bHideTracer[client] = (value[0] != '\0' && StringToInt(value) != 0);
}

public Action Command_HideTracer(int client, int args)
{
    if (!USM_IsValidClient(client))
    {
        return Plugin_Handled;
    }

    g_bHideTracer[client] = !g_bHideTracer[client];
    if (AreClientCookiesCached(client))
    {
        g_hHideCookie.Set(client, g_bHideTracer[client] ? "1" : "0");
    }

    PrintToChat(client, "[Umbrella Store] %T", g_bHideTracer[client] ? "Module Hidden" : "Module Visible", client, "Tracers");
    return Plugin_Handled;
}

public Action Event_BulletImpact(Event event, const char[] name, bool dontBroadcast)
{
    if (!US_IsEnabled() || !gCvarEnabled.BoolValue || g_iBeamModel < 0)
    {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!USM_IsPlayableClient(client, true))
    {
        return Plugin_Continue;
    }

    char itemId[64];
    if (!USM_GetEquippedItemForClientTeam(client, "tracer", itemId, sizeof(itemId)))
    {
        return Plugin_Continue;
    }

    char colorText[64];
    int color[4];
    USM_GetMetadata(itemId, "color", colorText, sizeof(colorText), "255 255 255 255");
    USM_ParseColor(colorText, color);

    if (USM_GetMetadataBool(itemId, "rainbow") || USM_GetMetadataBool(itemId, "random"))
    {
        color[0] = GetRandomInt(0, 255);
        color[1] = GetRandomInt(0, 255);
        color[2] = GetRandomInt(0, 255);
        color[3] = 255;
    }

    float start[3], end[3];
    GetClientEyePosition(client, start);
    end[0] = event.GetFloat("x");
    end[1] = event.GetFloat("y");
    end[2] = event.GetFloat("z");

    TE_SetupBeamPoints(start, end, g_iBeamModel, 0, 0, 0, gCvarLife.FloatValue, gCvarWidth.FloatValue, gCvarWidth.FloatValue, 1, 0.0, color, 0);

    int clients[MAXPLAYERS];
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!USM_IsValidClient(i) || g_bHideTracer[i])
        {
            continue;
        }

        clients[count++] = i;
    }

    if (count > 0)
    {
        TE_Send(clients, count);
    }

    return Plugin_Continue;
}

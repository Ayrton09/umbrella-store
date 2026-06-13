#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <umbrella_store>
#include <umbrella_store_module_utils>

ConVar gCvarEnabled;
ConVar gCvarBeamMaterial;
ConVar gCvarDotMaterial;
ConVar gCvarBeamLife;
ConVar gCvarBeamWidth;
ConVar gCvarDotLife;
ConVar gCvarDotSize;
ConVar gCvarUpdateInterval;

StringMap g_mSniperWeapons;
int g_iLaserBeam = -1;
int g_iLaserDot = -1;
float g_fNextLaserAt[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "[Umbrella Store] Laser Sight",
    author = "Ayrton09",
    description = "Scoped sniper laser sight item module for Umbrella Store",
    version = "1.5.0",
    url = ""
};

public void OnPluginStart()
{
    gCvarEnabled = CreateConVar("umbrella_store_lasersight_enabled", "1", "Enable Umbrella Store laser sights.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarBeamMaterial = CreateConVar("umbrella_store_lasersight_material", "materials/sprites/laserbeam.vmt", "Beam material used by laser sights.");
    gCvarDotMaterial = CreateConVar("umbrella_store_lasersight_dot_material", "materials/sprites/redglow1.vmt", "Dot material used by laser sights.");
    gCvarBeamLife = CreateConVar("umbrella_store_lasersight_beam_life", "0.1", "Laser beam lifetime.", FCVAR_NONE, true, 0.05, true, 1.0);
    gCvarBeamWidth = CreateConVar("umbrella_store_lasersight_beam_width", "0.12", "Laser beam width.", FCVAR_NONE, true, 0.01, true, 8.0);
    gCvarDotLife = CreateConVar("umbrella_store_lasersight_dot_life", "0.1", "Laser dot lifetime.", FCVAR_NONE, true, 0.05, true, 1.0);
    gCvarDotSize = CreateConVar("umbrella_store_lasersight_dot_size", "0.25", "Laser dot size.", FCVAR_NONE, true, 0.01, true, 8.0);
    gCvarUpdateInterval = CreateConVar("umbrella_store_lasersight_update_interval", "0.05", "Seconds between laser sight updates per player.", FCVAR_NONE, true, 0.01, true, 0.25);
    AutoExecConfig(true, "umbrella_store_lasersight");

    US_RegisterItemType("lasersight", "laser_sights", true, true);
    BuildSniperWeaponMap();
}

public void OnMapStart()
{
    char beam[PLATFORM_MAX_PATH], dot[PLATFORM_MAX_PATH];
    gCvarBeamMaterial.GetString(beam, sizeof(beam));
    gCvarDotMaterial.GetString(dot, sizeof(dot));

    g_iLaserBeam = PrecacheLaserMaterial(beam, "laser sight beam");
    g_iLaserDot = PrecacheLaserMaterial(dot, "laser sight dot");
}

public void OnClientDisconnect(int client)
{
    g_fNextLaserAt[client] = 0.0;
}

void BuildSniperWeaponMap()
{
    g_mSniperWeapons = new StringMap();
    g_mSniperWeapons.SetValue("awp", 1);
    g_mSniperWeapons.SetValue("scout", 1);
    g_mSniperWeapons.SetValue("sg550", 1);
    g_mSniperWeapons.SetValue("sg552", 1);
    g_mSniperWeapons.SetValue("sg556", 1);
    g_mSniperWeapons.SetValue("g3sg1", 1);
    g_mSniperWeapons.SetValue("aug", 1);
    g_mSniperWeapons.SetValue("scar17", 1);
    g_mSniperWeapons.SetValue("scar20", 1);
    g_mSniperWeapons.SetValue("ssg08", 1);
    g_mSniperWeapons.SetValue("spring", 1);
    g_mSniperWeapons.SetValue("k98s", 1);
}

int PrecacheLaserMaterial(const char[] material, const char[] label)
{
    if (material[0] == '\0' || !FileExists(material, true))
    {
        LogError("[Umbrella Store] Missing %s material: %s", label, material);
        return -1;
    }

    USM_AddMaterialDownloads(material);
    return PrecacheModel(material, true);
}

bool IsLaserWeapon(const char[] weapon)
{
    char shortName[64];
    strcopy(shortName, sizeof(shortName), weapon);
    ReplaceString(shortName, sizeof(shortName), "weapon_", "", false);

    int ignored;
    return g_mSniperWeapons.GetValue(shortName, ignored);
}

public bool TraceRayDontHitSelf(int entity, int contentsMask, any data)
{
    return entity != data;
}

void GetClientSightEnd(int client, float end[3])
{
    float eye[3], angles[3], fwd[3];
    GetClientEyePosition(client, eye);
    GetClientEyeAngles(client, angles);

    Handle trace = TR_TraceRayFilterEx(eye, angles, MASK_SHOT, RayType_Infinite, TraceRayDontHitSelf, client);
    if (TR_DidHit(trace))
    {
        TR_GetEndPosition(end, trace);
    }
    else
    {
        GetAngleVectors(angles, fwd, NULL_VECTOR, NULL_VECTOR);
        end[0] = eye[0] + fwd[0] * 8192.0;
        end[1] = eye[1] + fwd[1] * 8192.0;
        end[2] = eye[2] + fwd[2] * 8192.0;
    }
    delete trace;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (!US_IsEnabled() || !gCvarEnabled.BoolValue || g_iLaserBeam < 0 || g_iLaserDot < 0)
    {
        return Plugin_Continue;
    }

    if (!USM_IsPlayableClient(client, true))
    {
        return Plugin_Continue;
    }

    float now = GetGameTime();
    if (now < g_fNextLaserAt[client])
    {
        return Plugin_Continue;
    }
    g_fNextLaserAt[client] = now + gCvarUpdateInterval.FloatValue;

    int fov = GetEntProp(client, Prop_Data, "m_iFOV");
    if (fov == 0 || fov == 90)
    {
        return Plugin_Continue;
    }

    char weaponName[64];
    GetClientWeapon(client, weaponName, sizeof(weaponName));
    if (!IsLaserWeapon(weaponName))
    {
        return Plugin_Continue;
    }

    char itemId[64];
    if (!USM_GetEquippedItemForClientTeam(client, "lasersight", itemId, sizeof(itemId)))
    {
        return Plugin_Continue;
    }

    char colorText[64];
    int color[4];
    USM_GetMetadata(itemId, "color", colorText, sizeof(colorText), "255 0 0 255");
    USM_ParseColor(colorText, color);

    float origin[3], impact[3];
    GetClientEyePosition(client, origin);
    GetClientSightEnd(client, impact);

    TE_SetupBeamPoints(origin, impact, g_iLaserBeam, 0, 0, 0, gCvarBeamLife.FloatValue, gCvarBeamWidth.FloatValue, 0.0, 1, 0.0, color, 0);
    TE_SendToAll();

    TE_SetupGlowSprite(impact, g_iLaserDot, gCvarDotLife.FloatValue, gCvarDotSize.FloatValue, color[3]);
    TE_SendToAll();

    return Plugin_Continue;
}

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <umbrella_store>
#include <umbrella_store_module_utils>

ConVar gCvarEnabled;
ConVar gCvarLife;

public Plugin myinfo =
{
    name = "[Umbrella Store] Grenade Trails",
    author = "Ayrton09",
    description = "Grenade projectile trail item module for Umbrella Store",
    version = "1.4.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store.phrases");

    gCvarEnabled = CreateConVar("umbrella_store_grenade_trails_enabled", "1", "Enable Umbrella Store grenade trails.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarLife = CreateConVar("umbrella_store_grenade_trails_life", "2.0", "Grenade trail lifetime in seconds.", FCVAR_NONE, true, 0.1, true, 10.0);
    AutoExecConfig(true, "umbrella_store_grenade_trails");

    US_RegisterItemType("grenadetrail", "grenade_trails", true, true);
}

public void OnMapStart()
{
    PrecacheConfiguredTrailMaterials();
}

public void US_OnItemsReloaded(int itemCount)
{
    PrecacheConfiguredTrailMaterials();
}

void PrecacheConfiguredTrailMaterials()
{
    int count = US_GetItemCount();
    char itemId[64], type[32], material[PLATFORM_MAX_PATH];

    for (int i = 0; i < count; i++)
    {
        if (!US_GetItemIdByIndex(i, itemId, sizeof(itemId)) || !US_GetItemType(itemId, type, sizeof(type)) || !StrEqual(type, "grenadetrail", false))
        {
            continue;
        }

        USM_GetMetadata(itemId, "material", material, sizeof(material));
        if (material[0] == '\0')
        {
            LogError("[Umbrella Store] Grenade trail item '%s' has no material.", itemId);
            continue;
        }

        if (FileExists(material, true))
        {
            PrecacheModel(material, true);
            USM_AddMaterialDownloads(material);
        }
        else
        {
            LogError("[Umbrella Store] Grenade trail item '%s' material is missing: %s", itemId, material);
        }
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!US_IsEnabled() || !gCvarEnabled.BoolValue || StrContains(classname, "_projectile", false) == -1)
    {
        return;
    }

    SDKHook(entity, SDKHook_SpawnPost, OnProjectileSpawned);
}

public void OnProjectileSpawned(int entity)
{
    if (!US_IsEnabled() || !IsValidEntity(entity))
    {
        return;
    }

    int client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    if (!USM_IsPlayableClient(client))
    {
        return;
    }

    char itemId[64];
    if (!USM_GetEquippedItemForClientTeam(client, "grenadetrail", itemId, sizeof(itemId)))
    {
        return;
    }

    char material[PLATFORM_MAX_PATH], colorText[64];
    USM_GetMetadata(itemId, "material", material, sizeof(material));
    if (material[0] == '\0' || !FileExists(material, true))
    {
        return;
    }

    int color[4];
    USM_GetMetadata(itemId, "color", colorText, sizeof(colorText), "255 255 255 255");
    USM_ParseColor(colorText, color);

    float width = USM_GetMetadataFloat(itemId, "width", 8.0);
    float life = USM_GetMetadataFloat(itemId, "lifetime", gCvarLife.FloatValue);
    int model = PrecacheModel(material, true);
    TE_SetupBeamFollow(entity, model, 0, life, width, width, 10, color);
    TE_SendToAll();
}

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <umbrella_store>
#include <umbrella_store_module_utils>

ConVar gCvarEnabled;

public Plugin myinfo =
{
    name = "[Umbrella Store] Grenade Skins",
    author = "Ayrton09",
    description = "Grenade projectile model item module for Umbrella Store",
    version = "1.2.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store.phrases");

    gCvarEnabled = CreateConVar("umbrella_store_grenade_skins_enabled", "1", "Enable Umbrella Store grenade skins.", FCVAR_NONE, true, 0.0, true, 1.0);
    AutoExecConfig(true, "umbrella_store_grenade_skins");

    US_RegisterItemType("grenadeskin", "grenade_skins", true, false);
}

public void OnMapStart()
{
    PrecacheConfiguredGrenadeSkins();
}

bool GrenadeSkinSlotConflicts(const char[] equippedItemId, const char[] targetGrenade)
{
    char equippedGrenade[64];
    USM_GetMetadata(equippedItemId, "grenade", equippedGrenade, sizeof(equippedGrenade));

    if (targetGrenade[0] == '\0' || equippedGrenade[0] == '\0')
    {
        return true;
    }

    return StrEqual(targetGrenade, equippedGrenade, false);
}

public Action US_OnEquipPre(int client, const char[] itemId, bool equip)
{
    if (!equip || !USM_ItemMatchesType(itemId, "grenadeskin"))
    {
        return Plugin_Continue;
    }

    char targetGrenade[64], equipped[USM_MAX_EQUIPPED_ITEMS][64];
    USM_GetMetadata(itemId, "grenade", targetGrenade, sizeof(targetGrenade));

    int count = USM_GetEquippedItemsOfType(client, "grenadeskin", equipped, sizeof(equipped));
    for (int i = 0; i < count; i++)
    {
        if (StrEqual(equipped[i], itemId))
        {
            continue;
        }

        if (GrenadeSkinSlotConflicts(equipped[i], targetGrenade))
        {
            PrintToChat(client, "[Umbrella Store] %T", "Grenade Skin Slot In Use", client);
            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}

void PrecacheConfiguredGrenadeSkins()
{
    int count = US_GetItemCount();
    char itemId[64], type[32], model[PLATFORM_MAX_PATH];

    for (int i = 0; i < count; i++)
    {
        if (!US_GetItemIdByIndex(i, itemId, sizeof(itemId)) || !US_GetItemType(itemId, type, sizeof(type)) || !StrEqual(type, "grenadeskin", false))
        {
            continue;
        }

        USM_GetMetadata(itemId, "model", model, sizeof(model));
        if (model[0] == '\0')
        {
            LogError("[Umbrella Store] Grenade skin item '%s' has no model.", itemId);
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
            LogError("[Umbrella Store] Grenade skin item '%s' model is missing: %s", itemId, model);
        }
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!gCvarEnabled.BoolValue || StrContains(classname, "_projectile", false) == -1)
    {
        return;
    }

    SDKHook(entity, SDKHook_SpawnPost, OnProjectileSpawned);
}

void GetProjectileGrenadeName(int entity, char[] buffer, int maxlen)
{
    GetEdictClassname(entity, buffer, maxlen);

    int underscore = FindCharInString(buffer, '_');
    if (underscore > 0)
    {
        buffer[underscore] = '\0';
    }
}

bool GrenadeNameMatches(const char[] projectileName, const char[] configuredName)
{
    if (configuredName[0] == '\0')
    {
        return true;
    }

    return StrEqual(projectileName, configuredName, false);
}

bool FindGrenadeSkinForProjectile(int client, const char[] projectileName, char[] itemId, int itemMax)
{
    char equipped[USM_MAX_EQUIPPED_ITEMS][64];
    int count = USM_GetEquippedItemsOfType(client, "grenadeskin", equipped, sizeof(equipped));
    char grenade[64];

    for (int i = 0; i < count; i++)
    {
        USM_GetMetadata(equipped[i], "grenade", grenade, sizeof(grenade));
        if (GrenadeNameMatches(projectileName, grenade))
        {
            strcopy(itemId, itemMax, equipped[i]);
            return true;
        }
    }

    return false;
}

public void OnProjectileSpawned(int entity)
{
    if (!IsValidEntity(entity))
    {
        return;
    }

    int client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    if (!USM_IsPlayableClient(client))
    {
        return;
    }

    char projectileName[64], itemId[64], model[PLATFORM_MAX_PATH];
    GetProjectileGrenadeName(entity, projectileName, sizeof(projectileName));

    if (!FindGrenadeSkinForProjectile(client, projectileName, itemId, sizeof(itemId)))
    {
        return;
    }

    USM_GetMetadata(itemId, "model", model, sizeof(model));
    if (model[0] == '\0' || !FileExists(model, true))
    {
        return;
    }

    PrecacheModel(model, true);
    SetEntityModel(entity, model);
}

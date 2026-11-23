// Umbrella Store core: Item previews.
// Included by store_core.sp.

void RemovePreview(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    if (g_hPreviewTimer[client] != null)
    {
        KillTimer(g_hPreviewTimer[client]);
        g_hPreviewTimer[client] = null;
    }

    int ent = EntRefToEntIndex(g_iPreviewEntity[client]);
    if (ent != INVALID_ENT_REFERENCE && ent != -1 && IsValidEntity(ent))
    {
        AcceptEntityInput(ent, "Kill");
    }

    g_iPreviewEntity[client] = INVALID_ENT_REFERENCE;
}

void SpawnPreview(int client, const char[] modelPath)
{
    if (!IsValidHumanClient(client) || !IsPlayerAlive(client))
    {
        PrintStorePhrase(client, "%T", "Preview Need Alive", client);
        return;
    }

    float now = GetGameTime();
    float previewCooldown = (gCvarPreviewCooldown != null) ? gCvarPreviewCooldown.FloatValue : 0.0;
    if (previewCooldown > 0.0 && now < g_fNextPreview[client])
    {
        char cooldownText[16];
        FormatCooldownText(g_fNextPreview[client] - now, cooldownText, sizeof(cooldownText));
        PrintStorePhrase(client, "%T", "Preview Cooldown", client, cooldownText);
        return;
    }

    if (modelPath[0] == '\0' || !FileExists(modelPath, true))
    {
        PrintStorePhrase(client, "%T", "Preview Missing Model", client);
        return;
    }

    RemovePreview(client);

    PrecacheModel(modelPath, true);

    int ent = CreateEntityByName("prop_dynamic_override");
    if (ent == -1)
    {
        PrintStorePhrase(client, "%T", "Preview Failed Create", client);
        return;
    }

    DispatchKeyValue(ent, "model", modelPath);
    DispatchKeyValue(ent, "solid", "0");
    DispatchKeyValue(ent, "DefaultAnim", "idle");
    DispatchSpawn(ent);
    SDKHook(ent, SDKHook_SetTransmit, Hook_PreviewSetTransmit);

    float pos[3], ang[3], fwd[3];
    GetClientEyePosition(client, pos);
    GetClientEyeAngles(client, ang);
    GetAngleVectors(ang, fwd, NULL_VECTOR, NULL_VECTOR);

    float previewDistance = (gCvarPreviewDistance != null) ? gCvarPreviewDistance.FloatValue : PREVIEW_DISTANCE;
    float previewZOffset = (gCvarPreviewZOffset != null) ? gCvarPreviewZOffset.FloatValue : PREVIEW_Z_OFFSET;
    float previewLifetime = (gCvarPreviewLifetime != null) ? gCvarPreviewLifetime.FloatValue : PREVIEW_LIFETIME;

    pos[0] += fwd[0] * previewDistance;
    pos[1] += fwd[1] * previewDistance;
    pos[2] -= previewZOffset;

    ang[0] = 0.0;
    ang[1] += 180.0;
    ang[2] = 0.0;

    TeleportEntity(ent, pos, ang, NULL_VECTOR);
    SetVariantString("idle");
    AcceptEntityInput(ent, "SetAnimation");

    g_iPreviewEntity[client] = EntIndexToEntRef(ent);
    g_fNextPreview[client] = now + previewCooldown;
    g_hPreviewTimer[client] = CreateTimer(previewLifetime, Timer_RemovePreview, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

    char lifetimeText[16];
    Format(lifetimeText, sizeof(lifetimeText), "%d", RoundToFloor(previewLifetime));
    PrintStorePhrase(client, "%T", "Preview Started", client, lifetimeText);
}

bool ResolvePreviewMaterial(const char[] rawMaterial, char[] material, int materialMax, char[] downloadPath, int downloadMax)
{
    material[0] = '\0';
    downloadPath[0] = '\0';

    if (rawMaterial[0] == '\0')
    {
        return false;
    }

    strcopy(material, materialMax, rawMaterial);
    TrimString(material);

    if (StrContains(material, "materials/", false) == 0)
    {
        strcopy(downloadPath, downloadMax, material);
    }
    else
    {
        Format(downloadPath, downloadMax, "materials/%s", material);
    }

    return FileExists(downloadPath, true);
}

void FinishPreviewEntity(int client, int entity, float previewLifetime)
{
    g_iPreviewEntity[client] = EntIndexToEntRef(entity);
    g_hPreviewTimer[client] = CreateTimer(previewLifetime, Timer_RemovePreview, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

    char lifetimeText[16];
    Format(lifetimeText, sizeof(lifetimeText), "%d", RoundToFloor(previewLifetime));
    PrintStorePhrase(client, "%T", "Preview Started", client, lifetimeText);
}

bool PrepareNonModelPreview(int client)
{
    if (!IsValidHumanClient(client) || !IsPlayerAlive(client))
    {
        PrintStorePhrase(client, "%T", "Preview Need Alive", client);
        return false;
    }

    float now = GetGameTime();
    float previewCooldown = (gCvarPreviewCooldown != null) ? gCvarPreviewCooldown.FloatValue : 0.0;
    if (previewCooldown > 0.0 && now < g_fNextPreview[client])
    {
        char cooldownText[16];
        FormatCooldownText(g_fNextPreview[client] - now, cooldownText, sizeof(cooldownText));
        PrintStorePhrase(client, "%T", "Preview Cooldown", client, cooldownText);
        return false;
    }

    RemovePreview(client);
    g_fNextPreview[client] = now + previewCooldown;
    return true;
}

void GetPreviewPosition(int client, float pos[3], float ang[3])
{
    float fwd[3];
    GetClientEyePosition(client, pos);
    GetClientEyeAngles(client, ang);
    GetAngleVectors(ang, fwd, NULL_VECTOR, NULL_VECTOR);

    float previewDistance = (gCvarPreviewDistance != null) ? gCvarPreviewDistance.FloatValue : PREVIEW_DISTANCE;
    float previewZOffset = (gCvarPreviewZOffset != null) ? gCvarPreviewZOffset.FloatValue : PREVIEW_Z_OFFSET;

    pos[0] += fwd[0] * previewDistance;
    pos[1] += fwd[1] * previewDistance;
    pos[2] -= previewZOffset;

    ang[0] = 0.0;
    ang[1] += 180.0;
    ang[2] = 0.0;
}

void SpawnSpritePreview(int client, const char[] rawMaterial)
{
    char material[PLATFORM_MAX_PATH], downloadPath[PLATFORM_MAX_PATH];
    if (!ResolvePreviewMaterial(rawMaterial, material, sizeof(material), downloadPath, sizeof(downloadPath)))
    {
        PrintStorePhrase(client, "%T", "Preview Missing Model", client);
        return;
    }

    if (!PrepareNonModelPreview(client))
    {
        return;
    }

    PrecacheModel(material, true);

    int ent = CreateEntityByName("env_sprite_oriented");
    if (ent == -1)
    {
        PrintStorePhrase(client, "%T", "Preview Failed Create", client);
        return;
    }

    DispatchKeyValue(ent, "model", material);
    DispatchKeyValue(ent, "rendermode", "5");
    DispatchKeyValue(ent, "renderamt", "255");
    DispatchKeyValue(ent, "scale", "0.35");
    DispatchSpawn(ent);
    AcceptEntityInput(ent, "Enable");
    SDKHook(ent, SDKHook_SetTransmit, Hook_PreviewSetTransmit);

    float pos[3], ang[3];
    GetPreviewPosition(client, pos, ang);
    TeleportEntity(ent, pos, ang, NULL_VECTOR);

    float previewLifetime = (gCvarPreviewLifetime != null) ? gCvarPreviewLifetime.FloatValue : PREVIEW_LIFETIME;
    FinishPreviewEntity(client, ent, previewLifetime);
}

void SpawnSmokePreview(int client, const char[] itemId)
{
    if (!PrepareNonModelPreview(client))
    {
        return;
    }

    int ent = CreateEntityByName("env_smokestack");
    if (ent == -1)
    {
        PrintStorePhrase(client, "%T", "Preview Failed Create", client);
        return;
    }

    char rgb[64], baseSpread[32], spreadSpeed[32], speed[32], startSize[32], endSize[32], rate[32], jetLength[32], twist[32], density[32], material[PLATFORM_MAX_PATH];
    GetItemMetadataValue(itemId, "rgb_color", rgb, sizeof(rgb));
    GetItemMetadataValue(itemId, "base_spread", baseSpread, sizeof(baseSpread));
    GetItemMetadataValue(itemId, "spread_speed", spreadSpeed, sizeof(spreadSpeed));
    GetItemMetadataValue(itemId, "speed", speed, sizeof(speed));
    GetItemMetadataValue(itemId, "start_size", startSize, sizeof(startSize));
    GetItemMetadataValue(itemId, "end_size", endSize, sizeof(endSize));
    GetItemMetadataValue(itemId, "rate", rate, sizeof(rate));
    GetItemMetadataValue(itemId, "jet_length", jetLength, sizeof(jetLength));
    GetItemMetadataValue(itemId, "twist", twist, sizeof(twist));
    GetItemMetadataValue(itemId, "density", density, sizeof(density));
    GetItemMetadataValue(itemId, "material", material, sizeof(material));

    if (rgb[0] == '\0') strcopy(rgb, sizeof(rgb), "0 255 0");
    if (baseSpread[0] == '\0') strcopy(baseSpread, sizeof(baseSpread), "80");
    if (spreadSpeed[0] == '\0') strcopy(spreadSpeed, sizeof(spreadSpeed), "55");
    if (speed[0] == '\0') strcopy(speed, sizeof(speed), "60");
    if (startSize[0] == '\0') strcopy(startSize, sizeof(startSize), "120");
    if (endSize[0] == '\0') strcopy(endSize, sizeof(endSize), "2");
    if (rate[0] == '\0') strcopy(rate, sizeof(rate), "25");
    if (jetLength[0] == '\0') strcopy(jetLength, sizeof(jetLength), "120");
    if (twist[0] == '\0') strcopy(twist, sizeof(twist), "20");
    if (density[0] == '\0') strcopy(density, sizeof(density), "200");
    if (material[0] == '\0') strcopy(material, sizeof(material), "particle/particle_smokegrenade1.vmt");

    float pos[3], ang[3];
    GetPreviewPosition(client, pos, ang);
    DispatchKeyValueVector(ent, "origin", pos);
    DispatchKeyValue(ent, "BaseSpread", baseSpread);
    DispatchKeyValue(ent, "SpreadSpeed", spreadSpeed);
    DispatchKeyValue(ent, "Speed", speed);
    DispatchKeyValue(ent, "StartSize", startSize);
    DispatchKeyValue(ent, "EndSize", endSize);
    DispatchKeyValue(ent, "Rate", rate);
    DispatchKeyValue(ent, "JetLength", jetLength);
    DispatchKeyValue(ent, "Twist", twist);
    DispatchKeyValue(ent, "RenderColor", rgb);
    DispatchKeyValue(ent, "RenderAmt", density);
    DispatchKeyValue(ent, "SmokeMaterial", material);
    DispatchSpawn(ent);
    AcceptEntityInput(ent, "TurnOn");
    SDKHook(ent, SDKHook_SetTransmit, Hook_PreviewSetTransmit);

    float previewLifetime = (gCvarPreviewLifetime != null) ? gCvarPreviewLifetime.FloatValue : PREVIEW_LIFETIME;
    FinishPreviewEntity(client, ent, previewLifetime);
}

void PlaySoundPreview(int client, const char[] itemId)
{
    char sound[PLATFORM_MAX_PATH], download[PLATFORM_MAX_PATH];
    if (!GetItemMetadataValue(itemId, "sound", sound, sizeof(sound)) || sound[0] == '\0')
    {
        PrintStorePhrase(client, "%T", "Preview Missing Model", client);
        return;
    }

    Format(download, sizeof(download), "sound/%s", sound);
    if (!FileExists(download, true))
    {
        PrintStorePhrase(client, "%T", "Preview Missing Model", client);
        return;
    }

    if (!PrepareNonModelPreview(client))
    {
        return;
    }

    PrecacheSound(sound, true);
    EmitSoundToClient(client, sound, client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.8);
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

int PrecacheParticleEffectName(const char[] effect)
{
    // Not cached in a static: string table ids are rebuilt per map, so a stale
    // id would make later maps read and write the wrong table.
    int particleTable = FindStringTable("ParticleEffectNames");
    if (particleTable == INVALID_STRING_TABLE)
    {
        return INVALID_STRING_INDEX;
    }

    int index = FindStringIndexInTable(particleTable, effect);
    if (index != INVALID_STRING_INDEX)
    {
        return index;
    }

    int count = GetStringTableNumStrings(particleTable);
    if (count >= GetStringTableMaxStrings(particleTable))
    {
        return INVALID_STRING_INDEX;
    }

    AddToStringTable(particleTable, effect);
    return count;
}

bool GetParticlePreviewEffect(const char[] itemId, char[] effect, int maxlen)
{
    return GetItemMetadataValue(itemId, "effect", effect, maxlen) && effect[0] != '\0';
}

bool GetParticlePreviewFile(const char[] itemId, char[] file, int maxlen)
{
    return GetItemMetadataValue(itemId, "file", file, maxlen) && file[0] != '\0';
}

bool ItemHasParticlePreview(const char[] itemId)
{
    char effect[64], file[PLATFORM_MAX_PATH];
    if (!GetParticlePreviewEffect(itemId, effect, sizeof(effect)) || !GetParticlePreviewFile(itemId, file, sizeof(file)))
    {
        return false;
    }

    return FileExists(file, true);
}

void ClearAlwaysTransmitFlag(int entity)
{
    int flags = GetEdictFlags(entity);
    if ((flags & FL_EDICT_ALWAYS) != 0)
    {
        SetEdictFlags(entity, flags ^ FL_EDICT_ALWAYS);
    }
}

void SpawnParticlePreview(int client, const char[] itemId)
{
    char effect[64], file[PLATFORM_MAX_PATH];
    if (!GetParticlePreviewEffect(itemId, effect, sizeof(effect)) || !GetParticlePreviewFile(itemId, file, sizeof(file)) || !FileExists(file, true))
    {
        PrintStorePhrase(client, "%T", "Preview Missing Model", client);
        return;
    }

    if (!PrepareNonModelPreview(client))
    {
        return;
    }

    PrecacheGeneric(file, true);
    PrecacheParticleEffectName(effect);

    int ent = CreateEntityByName("info_particle_system");
    if (ent == -1)
    {
        PrintStorePhrase(client, "%T", "Preview Failed Create", client);
        return;
    }

    DispatchKeyValue(ent, "start_active", "0");
    DispatchKeyValue(ent, "effect_name", effect);
    DispatchSpawn(ent);
    ActivateEntity(ent);

    float pos[3], ang[3];
    GetPreviewPosition(client, pos, ang);
    pos[2] += 30.0;
    TeleportEntity(ent, pos, NULL_VECTOR, NULL_VECTOR);

    AcceptEntityInput(ent, "Start");
    ClearAlwaysTransmitFlag(ent);
    SDKHook(ent, SDKHook_SetTransmit, Hook_PreviewSetTransmit);

    float previewLifetime = (gCvarPreviewLifetime != null) ? gCvarPreviewLifetime.FloatValue : PREVIEW_LIFETIME;
    FinishPreviewEntity(client, ent, previewLifetime);
}

bool ItemSupportsPreview(StoreItem item)
{
    if (item.szModel[0] != '\0' && FileExists(item.szModel, true))
    {
        return true;
    }

    if (StrEqual(item.type, "coloredsmoke", false) || StrEqual(item.type, "ColoredSmoke", false))
    {
        return true;
    }

    if (StrEqual(item.type, "particle", false) && ItemHasParticlePreview(item.id))
    {
        return true;
    }

    char value[PLATFORM_MAX_PATH], material[PLATFORM_MAX_PATH], downloadPath[PLATFORM_MAX_PATH];
    if (GetItemMetadataValue(item.id, "material", value, sizeof(value)) && ResolvePreviewMaterial(value, material, sizeof(material), downloadPath, sizeof(downloadPath)))
    {
        return true;
    }

    if (GetItemMetadataValue(item.id, "sound", value, sizeof(value)) && value[0] != '\0')
    {
        Format(downloadPath, sizeof(downloadPath), "sound/%s", value);
        return FileExists(downloadPath, true);
    }

    return false;
}

void PreviewItem(int client, StoreItem item)
{
    if (item.szModel[0] != '\0')
    {
        SpawnPreview(client, item.szModel);
        return;
    }

    if (StrEqual(item.type, "coloredsmoke", false) || StrEqual(item.type, "ColoredSmoke", false))
    {
        SpawnSmokePreview(client, item.id);
        return;
    }

    if (StrEqual(item.type, "particle", false))
    {
        SpawnParticlePreview(client, item.id);
        return;
    }

    char value[PLATFORM_MAX_PATH];
    if (GetItemMetadataValue(item.id, "material", value, sizeof(value)) && value[0] != '\0')
    {
        SpawnSpritePreview(client, value);
        return;
    }

    if (GetItemMetadataValue(item.id, "sound", value, sizeof(value)) && value[0] != '\0')
    {
        PlaySoundPreview(client, item.id);
        return;
    }

    PrintStorePhrase(client, "%T", "Preview Missing Model", client);
}

public Action Timer_RemovePreview(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client < 1 || client > MaxClients)
    {
        return Plugin_Stop;
    }

    if (g_hPreviewTimer[client] != timer)
    {
        return Plugin_Stop;
    }

    g_hPreviewTimer[client] = null;
    RemovePreview(client);
    return Plugin_Stop;
}

int GetPreviewOwnerFromEntity(int entity)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (EntRefToEntIndex(g_iPreviewEntity[i]) == entity)
        {
            return i;
        }
    }

    return 0;
}

public Action Hook_PreviewSetTransmit(int entity, int client)
{
    ClearAlwaysTransmitFlag(entity);

    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    int owner = GetPreviewOwnerFromEntity(entity);
    if (owner <= 0)
    {
        return Plugin_Handled;
    }

    return (client == owner) ? Plugin_Continue : Plugin_Handled;
}

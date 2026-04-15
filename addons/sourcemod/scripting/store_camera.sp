#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <multicolors>

#define US_CHAT_TAG " {purple}[Umbrella Store]{default}"
#define MIRROR_BASE_YAW 90

enum CameraMode
{
    Camera_FirstPerson = 0,
    Camera_ThirdPerson,
    Camera_Mirror
};

CameraMode g_CameraMode[MAXPLAYERS + 1];

ConVar gCvarAllowThirdPerson;
ConVar gCvarCameraEnabled;
ConVar gCvarDisabledMaps;
ConVar gCvarTpDistance;
ConVar gCvarMirrorDistance;
ConVar gCvarTpPitch;
ConVar gCvarMirrorPitch;
ConVar gCvarMirrorYaw;
ConVar gCvarAnnounceCommands;
ConVar gCvarResetOnDeath;

bool g_bMapAllowed = true;

public Plugin myinfo =
{
    name = "[Umbrella Store] Camera",
    author = "Ayrton09",
    description = "Thirdperson and mirror camera for Umbrella Store player inspection",
    version = "1.1.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store_camera.phrases");

    RegConsoleCmd("sm_tp", Command_ThirdPerson);
    RegConsoleCmd("sm_thirdperson", Command_ThirdPerson);

    RegConsoleCmd("sm_mirror", Command_Mirror);

    RegConsoleCmd("sm_fp", Command_FirstPerson);
    RegConsoleCmd("sm_firstperson", Command_FirstPerson);

    HookEventEx("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEventEx("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEventEx("player_team", Event_PlayerTeam, EventHookMode_Post);

    gCvarAllowThirdPerson = FindConVar("sv_allow_thirdperson");

    gCvarCameraEnabled = CreateConVar(
        "umbrella_store_camera_enabled",
        "1",
        "Enable or disable the camera system.",
        FCVAR_NOTIFY,
        true, 0.0,
        true, 1.0
    );

    gCvarDisabledMaps = CreateConVar(
        "umbrella_store_camera_disabled_maps",
        "de_,cs_,fy_,awp_,aim_",
        "Map prefixes where !tp and !mirror are disabled.",
        FCVAR_NOTIFY
    );

    gCvarTpDistance = CreateConVar(
        "umbrella_store_camera_tp_distance",
        "120",
        "Camera distance for thirdperson mode.",
        FCVAR_NOTIFY,
        true, 40.0,
        true, 300.0
    );

    gCvarMirrorDistance = CreateConVar(
        "umbrella_store_camera_mirror_distance",
        "100",
        "Camera distance for mirror mode.",
        FCVAR_NOTIFY,
        true, 40.0,
        true, 300.0
    );

    gCvarTpPitch = CreateConVar(
        "umbrella_store_camera_tp_pitch",
        "0",
        "Camera pitch for thirdperson mode.",
        FCVAR_NOTIFY,
        true, -89.0,
        true, 89.0
    );

    gCvarMirrorPitch = CreateConVar(
        "umbrella_store_camera_mirror_pitch",
        "0",
        "Camera pitch for mirror mode.",
        FCVAR_NOTIFY,
        true, -89.0,
        true, 89.0
    );

    gCvarMirrorYaw = CreateConVar(
        "umbrella_store_camera_mirror_yaw",
        "0",
        "Mirror yaw fine offset. 0 = front-facing baseline (legacy 180 is treated as front).",
        FCVAR_NOTIFY,
        true, -180.0,
        true, 180.0
    );

    gCvarAnnounceCommands = CreateConVar(
        "umbrella_store_camera_announce",
        "1",
        "If 1, announce camera commands on join.",
        FCVAR_NOTIFY,
        true, 0.0,
        true, 1.0
    );

    gCvarResetOnDeath = CreateConVar(
        "umbrella_store_camera_reset_on_death",
        "1",
        "If 1, force firstperson on death or spectator.",
        FCVAR_NOTIFY,
        true, 0.0,
        true, 1.0
    );

    AutoExecConfig(true, "umbrella_store_camera");
}

public void OnConfigsExecuted()
{
    if (gCvarAllowThirdPerson != null)
    {
        gCvarAllowThirdPerson.SetInt(1);
    }

    RefreshMapCameraState();
}

public void OnMapStart()
{
    RefreshMapCameraState();
}

public void OnClientPutInServer(int client)
{
    g_CameraMode[client] = Camera_FirstPerson;

    if (IsFakeClient(client))
    {
        return;
    }

    if (gCvarAnnounceCommands.BoolValue)
    {
        CreateTimer(8.0, Timer_AnnounceClient, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnClientDisconnect(int client)
{
    g_CameraMode[client] = Camera_FirstPerson;
}

public Action Timer_AnnounceClient(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsValidRealClient(client))
    {
        return Plugin_Stop;
    }

    if (!gCvarCameraEnabled.BoolValue || !g_bMapAllowed)
    {
        return Plugin_Stop;
    }

    CameraChatPhrase(client, "Camera Announce Commands");
    return Plugin_Stop;
}

public Action Command_ThirdPerson(int client, int args)
{
    if (!CanUseCamera(client))
    {
        return Plugin_Handled;
    }

    if (g_CameraMode[client] == Camera_ThirdPerson)
    {
        g_CameraMode[client] = Camera_FirstPerson;
        ForceFirstPerson(client);
        CameraChatPhrase(client, "Camera Thirdperson Off");
        return Plugin_Handled;
    }

    g_CameraMode[client] = Camera_ThirdPerson;
    ApplyCameraMode(client);
    CameraChatPhrase(client, "Camera Thirdperson On");
    return Plugin_Handled;
}

public Action Command_Mirror(int client, int args)
{
    if (!CanUseCamera(client))
    {
        return Plugin_Handled;
    }

    if (g_CameraMode[client] == Camera_Mirror)
    {
        g_CameraMode[client] = Camera_FirstPerson;
        ForceFirstPerson(client);
        CameraChatPhrase(client, "Camera Mirror Off");
        return Plugin_Handled;
    }

    g_CameraMode[client] = Camera_Mirror;
    ApplyCameraMode(client);
    CameraChatPhrase(client, "Camera Mirror On");
    return Plugin_Handled;
}

public Action Command_FirstPerson(int client, int args)
{
    if (!IsValidRealClient(client))
    {
        return Plugin_Handled;
    }

    g_CameraMode[client] = Camera_FirstPerson;
    ForceFirstPerson(client);
    CameraChatPhrase(client, "Camera Firstperson On");
    return Plugin_Handled;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (!IsValidRealClient(client))
    {
        return;
    }

    CreateTimer(0.25, Timer_ReapplyCamera, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ReapplyCamera(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsValidRealClient(client))
    {
        return Plugin_Stop;
    }

    if (!IsPlayerAlive(client))
    {
        return Plugin_Stop;
    }

    if (GetClientTeam(client) <= 1)
    {
        return Plugin_Stop;
    }

    if (!gCvarCameraEnabled.BoolValue || !g_bMapAllowed)
    {
        ForceFirstPerson(client);
        return Plugin_Stop;
    }

    ApplyCameraMode(client);
    return Plugin_Stop;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!gCvarResetOnDeath.BoolValue)
    {
        return;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidRealClient(client))
    {
        return;
    }

    ForceFirstPerson(client);
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidRealClient(client))
    {
        return;
    }

    if (!gCvarResetOnDeath.BoolValue)
    {
        return;
    }

    if (event.GetInt("team") <= 1)
    {
        ForceFirstPerson(client);
    }
}

void ApplyCameraMode(int client)
{
    if (!IsValidRealClient(client))
    {
        return;
    }

    if (g_CameraMode[client] == Camera_FirstPerson)
    {
        ForceFirstPerson(client);
        return;
    }

    if (!gCvarCameraEnabled.BoolValue || !g_bMapAllowed)
    {
        ForceFirstPerson(client);
        return;
    }

    if (GetClientTeam(client) <= 1 || !IsPlayerAlive(client))
    {
        ForceFirstPerson(client);
        return;
    }

    if (gCvarAllowThirdPerson != null)
    {
        gCvarAllowThirdPerson.SetInt(1);
    }

    ClientCommand(client, "thirdperson");

    switch (g_CameraMode[client])
    {
        case Camera_ThirdPerson:
        {
            SendCameraFloatCmd(client, "cam_idealdist", gCvarTpDistance.FloatValue);
            SendCameraFloatCmd(client, "cam_idealpitch", gCvarTpPitch.FloatValue);
            SendCameraIntCmd(client, "cam_idealyaw", 0);
        }

        case Camera_Mirror:
        {
            float mirrorDist = FloatAbs(gCvarMirrorDistance.FloatValue);
            int yawOffset = gCvarMirrorYaw.IntValue;
            // Backward compatibility for old configs that used 180 as "front".
            if (yawOffset == 180 || yawOffset == -180)
            {
                yawOffset = 0;
            }

            int mirrorYaw = MIRROR_BASE_YAW + yawOffset;
            while (mirrorYaw > 180)
            {
                mirrorYaw -= 360;
            }
            while (mirrorYaw < -180)
            {
                mirrorYaw += 360;
            }

            SendCameraFloatCmd(client, "cam_idealdist", mirrorDist);
            SendCameraFloatCmd(client, "cam_idealpitch", gCvarMirrorPitch.FloatValue);
            SendCameraIntCmd(client, "cam_idealyaw", mirrorYaw);
        }

        default:
        {
            ForceFirstPerson(client);
        }
    }
}

bool CanUseCamera(int client)
{
    if (!IsValidRealClient(client))
    {
        return false;
    }

    if (!gCvarCameraEnabled.BoolValue)
    {
        CameraChatPhrase(client, "Camera Disabled");
        return false;
    }

    if (!g_bMapAllowed)
    {
        CameraChatPhrase(client, "Camera Map Disabled");
        return false;
    }

    if (GetClientTeam(client) <= 1)
    {
        CameraChatPhrase(client, "Camera Blocked Spectator");
        return false;
    }

    if (!IsPlayerAlive(client))
    {
        CameraChatPhrase(client, "Camera Blocked Dead");
        return false;
    }

    return true;
}

void RefreshMapCameraState()
{
    g_bMapAllowed = true;

    char map[64];
    GetCurrentMap(map, sizeof(map));

    char disabled[256];
    gCvarDisabledMaps.GetString(disabled, sizeof(disabled));
    if (disabled[0] == '\0')
    {
        return;
    }

    char maps[32][64];
    int count = ExplodeString(disabled, ",", maps, sizeof(maps), sizeof(maps[]));
    for (int i = 0; i < count; i++)
    {
        TrimString(maps[i]);
        if (maps[i][0] == '\0')
        {
            continue;
        }

        if (StrContains(map, maps[i], false) == 0)
        {
            g_bMapAllowed = false;
            return;
        }
    }
}

void SendCameraFloatCmd(int client, const char[] cmd, float value)
{
    char buffer[64];
    FormatEx(buffer, sizeof(buffer), "%s %.1f", cmd, value);
    ClientCommand(client, buffer);
}

void SendCameraIntCmd(int client, const char[] cmd, int value)
{
    char buffer[64];
    FormatEx(buffer, sizeof(buffer), "%s %d", cmd, value);
    ClientCommand(client, buffer);
}

void ForceFirstPerson(int client)
{
    if (!IsValidRealClient(client))
    {
        return;
    }

    ClientCommand(client, "firstperson");
}

void CameraChatPhrase(int client, const char[] phrase)
{
    if (!IsValidRealClient(client))
    {
        return;
    }

    char buffer[256], highlighted[320];
    if (TranslationPhraseExists(phrase))
    {
        Format(buffer, sizeof(buffer), "%T", phrase, client);
    }
    else
    {
        strcopy(buffer, sizeof(buffer), phrase);
    }

    HighlightChatCommands(buffer, highlighted, sizeof(highlighted));
    CPrintToChat(client, "%s %s", US_CHAT_TAG, highlighted);
}

bool IsCommandContinuationChar(int c)
{
    return (c >= 'a' && c <= 'z')
        || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9')
        || c == '_'
        || c == '-'
        || c == '/';
}

void AppendLiteral(char[] output, int maxlen, int &outPos, const char[] literal)
{
    int literalLen = strlen(literal);
    for (int i = 0; i < literalLen && outPos < maxlen - 1; i++)
    {
        output[outPos++] = literal[i];
    }
}

void HighlightChatCommands(const char[] input, char[] output, int maxlen)
{
    int inLen = strlen(input);
    int outPos = 0;
    bool inCommand = false;
    static const char commandStart[] = "{green}";
    static const char commandEnd[] = "{default}";

    for (int i = 0; i < inLen && outPos < maxlen - 1; i++)
    {
        int ch = input[i];

        if (!inCommand && ch == '!' && (i + 1) < inLen && IsCommandContinuationChar(input[i + 1]))
        {
            AppendLiteral(output, maxlen, outPos, commandStart);
            output[outPos++] = ch;
            inCommand = true;
            continue;
        }

        if (inCommand && !IsCommandContinuationChar(ch))
        {
            AppendLiteral(output, maxlen, outPos, commandEnd);
            inCommand = false;
        }

        if (outPos < maxlen - 1)
        {
            output[outPos++] = ch;
        }
    }

    if (inCommand && outPos < maxlen - 1)
    {
        AppendLiteral(output, maxlen, outPos, commandEnd);
    }

    output[outPos] = '\0';
}

bool IsValidRealClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

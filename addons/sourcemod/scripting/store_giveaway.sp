#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <umbrella_store>

#define US_CHAT_TAG " \x03[Umbrella Store]\x01"

public Plugin myinfo =
{
    name = "[Umbrella Store] Giveaway",
    author = "Ayrton09",
    description = "Giveaway global con animacion HUD para Umbrella Store",
    version = "1.0.0",
    url = ""
};

// =========================
// ConVars
// =========================
ConVar gCvarEnable;
ConVar gCvarMinPlayers;
ConVar gCvarTeamOnly;
ConVar gCvarAdminFlag;
ConVar gCvarStartDelay;
ConVar gCvarTickInterval;
ConVar gCvarRollTicks;
ConVar gCvarWinnerHoldTime;
ConVar gCvarAnnounce;
ConVar gCvarHudChannel;

ConVar gCvarSoundEnable;
ConVar gCvarRollSound;
ConVar gCvarSlowRollSound;
ConVar gCvarWinnerSound;
ConVar gCvarSlowRollSoundVolume;
ConVar gCvarWinnerSoundVolume;

// =========================
// Giveaway state
// =========================
bool g_bGiveawayActive = false;
bool g_bRolling = false;

int g_iPrizeCredits = 0;

int g_iParticipants[MAXPLAYERS + 1];
int g_iParticipantCount = 0;

int g_iWinnerClient = 0;
int g_iCurrentDisplayClient = 0;

int g_iRollTick = 0;
float g_fNextChangeTime = 0.0;

Handle g_hStartTimer = null;
Handle g_hRollTimer = null;
Handle g_hWinnerHoldTimer = null;

// =========================
// Plugin start
// =========================
public void OnPluginStart()
{
    LoadTranslations("umbrella_store_giveaway.phrases");

    gCvarEnable              = CreateConVar("sm_store_giveaway_enable", "1", "Enable giveaway module.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarMinPlayers          = CreateConVar("sm_store_giveaway_min_players", "2", "Minimum valid players required to start giveaway.", FCVAR_NONE, true, 1.0);
    gCvarTeamOnly            = CreateConVar("sm_store_giveaway_team_only", "1", "1 = TT/CT only, 0 = any in-game player.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarAdminFlag           = CreateConVar("sm_store_giveaway_admin_flag", "z", "Required admin flag to use giveaway.");
    gCvarStartDelay          = CreateConVar("sm_store_giveaway_start_delay", "3.0", "Seconds before animation starts.");
    gCvarTickInterval        = CreateConVar("sm_store_giveaway_tick_interval", "0.10", "Base timer interval for animation.");
    gCvarRollTicks           = CreateConVar("sm_store_giveaway_roll_ticks", "38", "Total number of animation ticks.");
    gCvarWinnerHoldTime      = CreateConVar("sm_store_giveaway_winner_hold_time", "4.0", "Time to hold winner on screen.");
    gCvarAnnounce            = CreateConVar("sm_store_giveaway_announce", "1", "Announce messages in chat.");
    gCvarHudChannel          = CreateConVar("sm_store_giveaway_hud_channel", "4", "HUD channel to use.");

    gCvarSoundEnable         = CreateConVar("sm_store_giveaway_sound_enable", "1", "Enable giveaway sounds.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarRollSound           = CreateConVar("sm_store_giveaway_roll_sound", "", "Roulette roll sound path. Empty = disabled.");
    gCvarSlowRollSound       = CreateConVar("sm_store_giveaway_slow_roll_sound", "buttons/button17.wav", "Sound played while roulette slows down.");
    gCvarWinnerSound         = CreateConVar("sm_store_giveaway_winner_sound", "buttons/bell1.wav", "Sound played when winner is selected.");
        gCvarSlowRollSoundVolume = CreateConVar("sm_store_giveaway_slow_roll_sound_volume", "0.75", "Slowdown sound volume.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarWinnerSoundVolume   = CreateConVar("sm_store_giveaway_winner_sound_volume", "0.95", "Winner sound volume.", FCVAR_NONE, true, 0.0, true, 1.0);

    AutoExecConfig(true, "umbrella_store_giveaway");

    char giveawayCmdHelp[128];
    char giveawayCancelCmdHelp[128];
    Format(giveawayCmdHelp, sizeof(giveawayCmdHelp), "%T", "Giveaway Cmd Help", LANG_SERVER);
    Format(giveawayCancelCmdHelp, sizeof(giveawayCancelCmdHelp), "%T", "Giveaway Cmd Cancel Help", LANG_SERVER);
    RegConsoleCmd("sm_giveaway", Command_Giveaway, giveawayCmdHelp);
    RegConsoleCmd("sm_giveawaycancel", Command_GiveawayCancel, giveawayCancelCmdHelp);
}

public void OnMapStart()
{
    PrecacheGiveawaySounds();
}

public void OnLibraryRemoved(const char[] name)
{
    if (!StrEqual(name, "umbrella_store"))
    {
        return;
    }

    if (g_bGiveawayActive)
    {
        PrintStoreMessageAll("%t", "Giveaway Cancelled Store Missing");
        ResetGiveawayState(true);
    }
}

// =========================
// Helpers
// =========================
bool HasGiveawayAccess(int client)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return false;
    }

    char sFlag[8];
    gCvarAdminFlag.GetString(sFlag, sizeof(sFlag));

    if (sFlag[0] == '\0')
    {
        return true;
    }

    int neededBits = ReadFlagString(sFlag);
    if (neededBits == 0)
    {
        return true;
    }

    return (GetUserFlagBits(client) & neededBits) == neededBits || CheckCommandAccess(client, "sm_giveaway_override", ADMFLAG_ROOT, true);
}

bool IsValidGiveawayClient(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return false;
    }

    if (!IsClientInGame(client) || IsFakeClient(client))
    {
        return false;
    }

    if (!LibraryExists("umbrella_store") || !US_IsLoaded(client))
    {
        return false;
    }

    if (gCvarTeamOnly.BoolValue)
    {
        int team = GetClientTeam(client);
        if (team != 2 && team != 3)
        {
            return false;
        }
    }

    return true;
}

void RebuildParticipantList()
{
    g_iParticipantCount = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidGiveawayClient(client))
        {
            continue;
        }

        g_iParticipants[g_iParticipantCount++] = client;
    }
}

int GetRandomParticipant()
{
    if (g_iParticipantCount <= 0)
    {
        return 0;
    }

    int index = GetRandomInt(0, g_iParticipantCount - 1);
    return g_iParticipants[index];
}

int GetRandomParticipantExcept(int exceptClient)
{
    if (g_iParticipantCount <= 0)
    {
        return 0;
    }

    if (g_iParticipantCount == 1)
    {
        return g_iParticipants[0];
    }

    int tries = 32;
    while (tries-- > 0)
    {
        int client = g_iParticipants[GetRandomInt(0, g_iParticipantCount - 1)];
        if (client != exceptClient)
        {
            return client;
        }
    }

    for (int i = 0; i < g_iParticipantCount; i++)
    {
        if (g_iParticipants[i] != exceptClient)
        {
            return g_iParticipants[i];
        }
    }

    return g_iParticipants[0];
}

void ClearAllTimers()
{
    if (g_hStartTimer != null)
    {
        KillTimer(g_hStartTimer);
        g_hStartTimer = null;
    }

    if (g_hRollTimer != null)
    {
        KillTimer(g_hRollTimer);
        g_hRollTimer = null;
    }

    if (g_hWinnerHoldTimer != null)
    {
        KillTimer(g_hWinnerHoldTimer);
        g_hWinnerHoldTimer = null;
    }
}

void ClearHudForAll()
{
    int channel = gCvarHudChannel.IntValue;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client))
        {
            continue;
        }

        ShowHudText(client, channel, " ");
    }
}

void ResetGiveawayState(bool clearHud = true)
{
    ClearAllTimers();

    g_bGiveawayActive = false;
    g_bRolling = false;
    g_iPrizeCredits = 0;
    g_iParticipantCount = 0;
    g_iWinnerClient = 0;
    g_iCurrentDisplayClient = 0;
    g_iRollTick = 0;
    g_fNextChangeTime = 0.0;

    for (int i = 0; i < MAXPLAYERS + 1; i++)
    {
        g_iParticipants[i] = 0;
    }

    if (clearHud)
    {
        ClearHudForAll();
    }
}

void PrintStoreMessageAll(const char[] format, any ...)
{
    if (!gCvarAnnounce.BoolValue)
    {
        return;
    }

    char buffer[256], highlighted[320];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client))
        {
            continue;
        }

        SetGlobalTransTarget(client);
        VFormat(buffer, sizeof(buffer), format, 2);
        HighlightChatCommands(buffer, highlighted, sizeof(highlighted));
        PrintToChat(client, "%s %s", US_CHAT_TAG, highlighted);
    }
}

void ReplyStoreMessage(int client, const char[] format, any ...)
{
    char buffer[256], highlighted[320];
    if (client > 0 && client <= MaxClients)
    {
        SetGlobalTransTarget(client);
    }
    else
    {
        SetGlobalTransTarget(LANG_SERVER);
    }

    VFormat(buffer, sizeof(buffer), format, 3);
    HighlightChatCommands(buffer, highlighted, sizeof(highlighted));
    if (client > 0 && client <= MaxClients)
    {
        ReplyToCommand(client, "%s %s", US_CHAT_TAG, highlighted);
    }
    else
    {
        ReplyToCommand(client, "[Umbrella Store] %s", highlighted);
    }
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

void HighlightChatCommands(const char[] input, char[] output, int maxlen)
{
    int inLen = strlen(input);
    int outPos = 0;
    bool inCommand = false;

    for (int i = 0; i < inLen && outPos < maxlen - 1; i++)
    {
        int ch = input[i];

        if (!inCommand && ch == '!' && (i + 1) < inLen && IsCommandContinuationChar(input[i + 1]))
        {
            if (outPos < maxlen - 1)
            {
                output[outPos++] = '\x04';
            }
            output[outPos++] = ch;
            inCommand = true;
            continue;
        }

        if (inCommand && !IsCommandContinuationChar(ch))
        {
            if (outPos < maxlen - 1)
            {
                output[outPos++] = '\x01';
            }
            inCommand = false;
        }

        if (outPos < maxlen - 1)
        {
            output[outPos++] = ch;
        }
    }

    if (inCommand && outPos < maxlen - 1)
    {
        output[outPos++] = '\x01';
    }

    output[outPos] = '\0';
}

void ShowHudForClient(int client, const char[] title, const char[] subtitle, const char[] name, int r, int g, int b)
{
    int channel = gCvarHudChannel.IntValue;
    char message[256];
    Format(message, sizeof(message), "%s\n%s\n\n%s", title, subtitle, name);
    SetHudTextParams(-1.0, 0.70, 2.0, r, g, b, 255, 0, 0.0, 0.0, 0.0);
    ShowHudText(client, channel, message);
}

void ShowGiveawayHudStatic(const char[] titleKey, const char[] subtitleKey, const char[] nameKey, int r, int g, int b)
{
    char title[128];
    char subtitle[128];
    char name[128];

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client))
        {
            continue;
        }

        Format(title, sizeof(title), "%T", titleKey, client);
        Format(subtitle, sizeof(subtitle), "%T", subtitleKey, client);
        Format(name, sizeof(name), "%T", nameKey, client);
        ShowHudForClient(client, title, subtitle, name, r, g, b);
    }
}

void ShowGiveawayHudRolling(const char[] playerName, int r, int g, int b)
{
    char title[128];
    char subtitle[128];

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client))
        {
            continue;
        }

        Format(title, sizeof(title), "%T", "Giveaway HUD Title", client);
        Format(subtitle, sizeof(subtitle), "%T", "Giveaway HUD Prize", client, g_iPrizeCredits);
        ShowHudForClient(client, title, subtitle, playerName, r, g, b);
    }
}

void ShowGiveawayHudWinner(const char[] winnerName, int r, int g, int b)
{
    char title[128];
    char subtitle[128];
    char name[128];

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client))
        {
            continue;
        }

        Format(title, sizeof(title), "%T", "Giveaway HUD Winner Title", client);
        Format(subtitle, sizeof(subtitle), "%T", "Giveaway HUD Prize", client, g_iPrizeCredits);
        Format(name, sizeof(name), "%T", "Giveaway HUD Winner Name", client, winnerName);
        ShowHudForClient(client, title, subtitle, name, r, g, b);
    }
}

float GetRollStepDelay(int tick, int totalTicks)
{
    float base = gCvarTickInterval.FloatValue;

    if (tick < totalTicks / 4)
    {
        return base;
    }
    else if (tick < totalTicks / 2)
    {
        return base * 1.35;
    }
    else if (tick < (totalTicks * 3) / 4)
    {
        return base * 1.9;
    }
    else if (tick < totalTicks - 3)
    {
        return base * 2.7;
    }

    return base * 4.0;
}

bool IsSlowPhase(int tick, int totalTicks)
{
    return (tick >= ((totalTicks * 3) / 4));
}

void PickInitialWinner()
{
    g_iWinnerClient = GetRandomParticipant();
    if (g_iWinnerClient == 0)
    {
        RebuildParticipantList();
        g_iWinnerClient = GetRandomParticipant();
    }
}

int ResolveFinalWinner()
{
    if (IsValidGiveawayClient(g_iWinnerClient))
    {
        return g_iWinnerClient;
    }

    RebuildParticipantList();
    if (g_iParticipantCount <= 0)
    {
        return 0;
    }

    g_iWinnerClient = GetRandomParticipant();
    return g_iWinnerClient;
}

void PrecacheIfValid(const char[] path)
{
    if (path[0] == '\0')
    {
        return;
    }

    PrecacheSound(path, true);
}

void PrecacheGiveawaySounds()
{
    char soundPath[PLATFORM_MAX_PATH];

    gCvarRollSound.GetString(soundPath, sizeof(soundPath));
    TrimString(soundPath);
    PrecacheIfValid(soundPath);

    gCvarSlowRollSound.GetString(soundPath, sizeof(soundPath));
    TrimString(soundPath);
    PrecacheIfValid(soundPath);

    gCvarWinnerSound.GetString(soundPath, sizeof(soundPath));
    TrimString(soundPath);
    PrecacheIfValid(soundPath);
}

void EmitGiveawaySoundToAll(const char[] sample, float volume)
{
    if (!gCvarSoundEnable.BoolValue || sample[0] == '\0')
    {
        return;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client))
        {
            continue;
        }

        EmitSoundToClient(
            client,
            sample,
            SOUND_FROM_PLAYER,
            SNDCHAN_AUTO,
            SNDLEVEL_NORMAL,
            SND_NOFLAGS,
            volume,
            SNDPITCH_NORMAL
        );
    }
}


void PlaySlowRollSound()
{
    char soundPath[PLATFORM_MAX_PATH];
    gCvarSlowRollSound.GetString(soundPath, sizeof(soundPath));
    TrimString(soundPath);
    EmitGiveawaySoundToAll(soundPath, gCvarSlowRollSoundVolume.FloatValue);
}

void PlayWinnerSound()
{
    char soundPath[PLATFORM_MAX_PATH];
    gCvarWinnerSound.GetString(soundPath, sizeof(soundPath));
    TrimString(soundPath);
    EmitGiveawaySoundToAll(soundPath, gCvarWinnerSoundVolume.FloatValue);
}

void FinishGiveaway()
{
    int winner = ResolveFinalWinner();

    if (winner == 0)
    {
        PrintStoreMessageAll("%t", "Giveaway Cancelled No Players");
        ResetGiveawayState(true);
        return;
    }

    if (!LibraryExists("umbrella_store"))
    {
        PrintStoreMessageAll("%t", "Giveaway Reward Failed Store Missing");
        ResetGiveawayState(true);
        return;
    }

    if (!US_AddCredits(winner, g_iPrizeCredits, true))
    {
        PrintStoreMessageAll("%t", "Giveaway Reward Failed");
        ResetGiveawayState(true);
        return;
    }

    char winnerName[MAX_NAME_LENGTH];
    GetClientName(winner, winnerName, sizeof(winnerName));

    ShowGiveawayHudWinner(winnerName, 0, 255, 120);
    PlayWinnerSound();

    PrintStoreMessageAll("%t", "Giveaway Winner Broadcast", winnerName, g_iPrizeCredits);

    g_hWinnerHoldTimer = CreateTimer(gCvarWinnerHoldTime.FloatValue, Timer_ClearWinnerHud, _, TIMER_FLAG_NO_MAPCHANGE);
}

// =========================
// Commands
// =========================
public Action Command_Giveaway(int client, int args)
{
    if (!gCvarEnable.BoolValue)
    {
        ReplyStoreMessage(client, "%t", "Giveaway Disabled");
        return Plugin_Handled;
    }

    if (client > 0 && !HasGiveawayAccess(client))
    {
        ReplyStoreMessage(client, "%t", "Giveaway No Access");
        return Plugin_Handled;
    }

    if (args < 1)
    {
        ReplyStoreMessage(client, "%t", "Giveaway Usage");
        return Plugin_Handled;
    }

    if (g_bGiveawayActive)
    {
        ReplyStoreMessage(client, "%t", "Giveaway Already Active");
        return Plugin_Handled;
    }

    if (!LibraryExists("umbrella_store"))
    {
        ReplyStoreMessage(client, "%t", "Giveaway Store Missing");
        return Plugin_Handled;
    }

    char sAmount[32];
    GetCmdArg(1, sAmount, sizeof(sAmount));

    int amount = StringToInt(sAmount);
    if (amount <= 0)
    {
        ReplyStoreMessage(client, "%t", "Giveaway Invalid Amount");
        return Plugin_Handled;
    }

    RebuildParticipantList();

    int minPlayers = gCvarMinPlayers.IntValue;
    if (g_iParticipantCount < minPlayers)
    {
        ReplyStoreMessage(client, "%t", "Giveaway Not Enough Players", minPlayers, g_iParticipantCount);
        return Plugin_Handled;
    }

    g_bGiveawayActive = true;
    g_bRolling = false;
    g_iPrizeCredits = amount;
    g_iRollTick = 0;
    g_fNextChangeTime = 0.0;
    g_iCurrentDisplayClient = 0;

    PickInitialWinner();

    char starterName[MAX_NAME_LENGTH];
    if (client > 0 && IsClientInGame(client))
    {
        GetClientName(client, starterName, sizeof(starterName));
    }
    else
    {
        Format(starterName, sizeof(starterName), "%T", "Giveaway Starter Console", LANG_SERVER);
    }

    PrintStoreMessageAll("%t", "Giveaway Started", starterName, g_iPrizeCredits);
    PrintStoreMessageAll("%t", "Giveaway Participants", g_iParticipantCount, gCvarStartDelay.FloatValue);
    ShowGiveawayHudStatic("Giveaway HUD Title", "Giveaway HUD Preparing", "Giveaway HUD Good Luck", 255, 180, 40);

    g_hStartTimer = CreateTimer(gCvarStartDelay.FloatValue, Timer_StartRoll, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}

public Action Command_GiveawayCancel(int client, int args)
{
    if (!g_bGiveawayActive)
    {
        ReplyStoreMessage(client, "%t", "Giveaway None Active");
        return Plugin_Handled;
    }

    if (client > 0 && !HasGiveawayAccess(client))
    {
        ReplyStoreMessage(client, "%t", "Giveaway No Access");
        return Plugin_Handled;
    }

    PrintStoreMessageAll("%t", "Giveaway Cancelled");
    ResetGiveawayState(true);
    return Plugin_Handled;
}

// =========================
// Timers
// =========================
public Action Timer_StartRoll(Handle timer)
{
    g_hStartTimer = null;

    if (!g_bGiveawayActive)
    {
        return Plugin_Stop;
    }

    RebuildParticipantList();
    if (g_iParticipantCount < gCvarMinPlayers.IntValue)
    {
        PrintStoreMessageAll("%t", "Giveaway Cancelled Not Enough Players");
        ResetGiveawayState(true);
        return Plugin_Stop;
    }

    g_bRolling = true;
    g_iRollTick = 0;
    g_fNextChangeTime = GetGameTime();

    PrintStoreMessageAll("%t", "Giveaway Rolling");
    g_hRollTimer = CreateTimer(gCvarTickInterval.FloatValue, Timer_RollGiveaway, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_RollGiveaway(Handle timer)
{
    if (!g_bGiveawayActive || !g_bRolling)
    {
        g_hRollTimer = null;
        return Plugin_Stop;
    }

    int totalTicks = gCvarRollTicks.IntValue;
    if (totalTicks < 8)
    {
        totalTicks = 8;
    }

    float now = GetGameTime();
    if (now < g_fNextChangeTime)
    {
        return Plugin_Continue;
    }

    g_iRollTick++;

    char currentName[MAX_NAME_LENGTH];

    if (g_iRollTick >= totalTicks)
    {
        g_iCurrentDisplayClient = ResolveFinalWinner();
        if (g_iCurrentDisplayClient == 0)
        {
            PrintStoreMessageAll("%t", "Giveaway Cancelled No Players");
            ResetGiveawayState(true);
            g_hRollTimer = null;
            return Plugin_Stop;
        }

        GetClientName(g_iCurrentDisplayClient, currentName, sizeof(currentName));
        ShowGiveawayHudRolling(currentName, 0, 255, 120);

        g_bRolling = false;
        g_hRollTimer = null;
        FinishGiveaway();
        return Plugin_Stop;
    }

    RebuildParticipantList();
    if (g_iParticipantCount <= 0)
    {
        PrintStoreMessageAll("%t", "Giveaway Cancelled No Players");
        ResetGiveawayState(true);
        g_hRollTimer = null;
        return Plugin_Stop;
    }

    if (g_iRollTick >= totalTicks - 1)
    {
        g_iCurrentDisplayClient = g_iWinnerClient;
    }
    else
    {
        if (!IsValidGiveawayClient(g_iWinnerClient))
        {
            PickInitialWinner();
        }

        g_iCurrentDisplayClient = GetRandomParticipantExcept(g_iCurrentDisplayClient);
        if (g_iCurrentDisplayClient == 0)
        {
            g_iCurrentDisplayClient = g_iWinnerClient;
        }
    }

    if (!IsValidGiveawayClient(g_iCurrentDisplayClient))
    {
        g_iCurrentDisplayClient = GetRandomParticipant();
    }

    if (g_iCurrentDisplayClient == 0)
    {
        PrintStoreMessageAll("%t", "Giveaway Cancelled No Players");
        ResetGiveawayState(true);
        g_hRollTimer = null;
        return Plugin_Stop;
    }

    GetClientName(g_iCurrentDisplayClient, currentName, sizeof(currentName));

    if (IsSlowPhase(g_iRollTick, totalTicks))
    {
        ShowGiveawayHudRolling(currentName, 255, 200, 60);
        PlaySlowRollSound();
    }
    else
    {
        ShowGiveawayHudRolling(currentName, 255, 255, 255);
        // Roll sound disabled (requested)
    }

    g_fNextChangeTime = now + GetRollStepDelay(g_iRollTick, totalTicks);
    return Plugin_Continue;
}

public Action Timer_ClearWinnerHud(Handle timer)
{
    g_hWinnerHoldTimer = null;
    ResetGiveawayState(true);
    return Plugin_Stop;
}



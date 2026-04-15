#include <sourcemod>
#include <sdktools>
#include <umbrella_store>
#include <multicolors>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name = "[Umbrella Store] Crash",
    author = "Ayrton09",
    description = "Crash module for Umbrella Store",
    version = "1.1.0",
    url = ""
};

#define CRASH_CHAT_TAG "{green}[Crash]{default}"

enum CrashState
{
    CrashState_Idle = 0,
    CrashState_Waiting,
    CrashState_Running,
    CrashState_Crashed
};

enum AutoMethod
{
    AutoMethod_None = 0,
    AutoMethod_ChatBet,
    AutoMethod_ChatAuto
};

CrashState g_State = CrashState_Idle;

ConVar gCvarEnabled;
ConVar gCvarMinBet;
ConVar gCvarMaxBet;
ConVar gCvarCountdown;
ConVar gCvarTickInterval;
ConVar gCvarGrowthPerSecond;
ConVar gCvarGrowthCurve;
ConVar gCvarWarmupSeconds;
ConVar gCvarLowCrashChance;
ConVar gCvarLowCrashMin;
ConVar gCvarLowCrashMax;
ConVar gCvarEpicChance;
ConVar gCvarEpicBoostPerSecond;
ConVar gCvarEpicBoostCurve;
ConVar gCvarEpicStartMin;
ConVar gCvarEpicStartMax;
ConVar gCvarEpicMinCrash;
ConVar gCvarRestartDelay;
ConVar gCvarMinSpamGap;
ConVar gCvarStartSound;
ConVar gCvarCashoutSound;
ConVar gCvarCrashSound;
ConVar gCvarAnnounce;
ConVar gCvarHistoryMax;
ConVar gCvarCashoutSafety;

Handle g_hWaitingTimer = null;
Handle g_hRunTimer = null;
Handle g_hRestartTimer = null;
Handle g_hMenuRefreshTimer = null;

float g_fCountdownEnd = 0.0;
float g_fRoundStartTime = 0.0;
float g_fCurrentMultiplier = 1.0;
float g_fCrashAt = 1.0;
float g_fLastCrashAt = 0.0;
bool g_bEpicSurgeRound = false;
bool g_bEpicSurgeAnnounced = false;
float g_fEpicSurgeStart = 0.0;

bool g_bRegistered = false;
bool g_bPanelOpen[MAXPLAYERS + 1];
int g_iLastShownCountdown[MAXPLAYERS + 1];
bool g_bHasBet[MAXPLAYERS + 1];
bool g_bCashedOut[MAXPLAYERS + 1];
int g_iBet[MAXPLAYERS + 1];
int g_iLastPayout[MAXPLAYERS + 1];
float g_fAutoCashout[MAXPLAYERS + 1];
AutoMethod g_AwaitMethod[MAXPLAYERS + 1];
float g_fNextActionAt[MAXPLAYERS + 1];
float g_fNextMenuAt[MAXPLAYERS + 1];
ArrayList g_History = null;

void TrackCrashResolved(int client, int net, bool cashedOut)
{
    if (!IsValidHumanClient(client))
    {
        return;
    }

    US_AddStat(client, "crash_rounds", 1);
    US_AddStat(client, cashedOut ? "crash_cashouts" : "crash_losses", 1);

    if (net != 0)
    {
        US_AddStat(client, "crash_profit", net);
    }

    if (cashedOut)
    {
        US_AdvanceQuestProgress(client, "crash_cashouts_5", 1);
    }
}

void RegisterCrashQuests()
{
    if (!LibraryExists("umbrella_store"))
    {
        return;
    }

    US_RegisterQuestEx("crash_cashouts_5", "Quest Title Crash Cashouts I", 5, 225, "", false, "Quest Category Casino", "Quest Desc Crash Cashouts I");
}

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    LoadTranslations("umbrella_store_crash.phrases");

    gCvarEnabled = CreateConVar("umbrella_store_crash_enabled", "1", "Enable Crash module.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarMinBet = CreateConVar("umbrella_store_crash_min_bet", "100", "Minimum bet.", FCVAR_NONE, true, 1.0);
    gCvarMaxBet = CreateConVar("umbrella_store_crash_max_bet", "1000000", "Maximum bet.", FCVAR_NONE, true, 1.0);
    gCvarCountdown = CreateConVar("umbrella_store_crash_countdown", "8.0", "Countdown seconds before round starts.", FCVAR_NONE, true, 1.0);
    gCvarTickInterval = CreateConVar("umbrella_store_crash_tick_interval", "0.05", "Multiplier update interval.", FCVAR_NONE, true, 0.03);
    gCvarGrowthPerSecond = CreateConVar("umbrella_store_crash_growth_per_second", "0.22", "Linear growth per second.", FCVAR_NONE, true, 0.03);
    gCvarGrowthCurve = CreateConVar("umbrella_store_crash_growth_curve", "0.035", "Additional quadratic growth per second.", FCVAR_NONE, true, 0.0);
    gCvarWarmupSeconds = CreateConVar("umbrella_store_crash_warmup_seconds", "4.0", "Initial smooth acceleration duration in seconds for multiplier. 0 = disabled.", FCVAR_NONE, true, 0.0, true, 30.0);
    gCvarLowCrashChance = CreateConVar("umbrella_store_crash_low_chance", "0.40", "Percentage chance of low crash (x1.00/x1.01/x1.02).", FCVAR_NONE, true, 0.0, true, 100.0);
    gCvarLowCrashMin = CreateConVar("umbrella_store_crash_low_min", "1.00", "Minimum multiplier for low crash.", FCVAR_NONE, true, 1.0, true, 2.0);
    gCvarLowCrashMax = CreateConVar("umbrella_store_crash_low_max", "1.02", "Maximum multiplier for low crash.", FCVAR_NONE, true, 1.0, true, 2.0);
    gCvarEpicChance = CreateConVar("umbrella_store_crash_epic_chance", "0.8", "Percentage chance of an epic boost per round.", FCVAR_NONE, true, 0.0, true, 100.0);
    gCvarEpicBoostPerSecond = CreateConVar("umbrella_store_crash_epic_boost_per_second", "0.65", "Extra linear acceleration during epic boost.", FCVAR_NONE, true, 0.0, true, 10.0);
    gCvarEpicBoostCurve = CreateConVar("umbrella_store_crash_epic_boost_curve", "0.11", "Extra curve acceleration during epic boost.", FCVAR_NONE, true, 0.0, true, 10.0);
    gCvarEpicStartMin = CreateConVar("umbrella_store_crash_epic_start_min", "1.2", "Minimum second to start an epic boost.", FCVAR_NONE, true, 0.0, true, 30.0);
    gCvarEpicStartMax = CreateConVar("umbrella_store_crash_epic_start_max", "3.0", "Maximum second to start an epic boost.", FCVAR_NONE, true, 0.0, true, 30.0);
    gCvarEpicMinCrash = CreateConVar("umbrella_store_crash_epic_min_crash", "3.5", "Forced minimum crash value when epic boost triggers.", FCVAR_NONE, true, 1.1, true, 100.0);
    gCvarRestartDelay = CreateConVar("umbrella_store_crash_restart_delay", "3.0", "Delay after crash before returning to idle.", FCVAR_NONE, true, 0.0);
    gCvarMinSpamGap = CreateConVar("umbrella_store_crash_antispam", "0.35", "Anti-spam cooldown for actions.", FCVAR_NONE, true, 0.05);
    gCvarStartSound = CreateConVar("umbrella_store_crash_start_sound", "buttons/blip1.wav", "Sound played when round starts. Empty = disabled.");
    gCvarCashoutSound = CreateConVar("umbrella_store_crash_cashout_sound", "buttons/button14.wav", "Sound played on cashout. Empty = disabled.");
    gCvarCrashSound = CreateConVar("umbrella_store_crash_crash_sound", "weapons/hegrenade/explode5.wav", "Sound played on crash. Empty = disabled.");
    gCvarAnnounce = CreateConVar("umbrella_store_crash_announce_chat", "1", "Announce important events in chat.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarHistoryMax = CreateConVar("umbrella_store_crash_history_max", "10", "Number of entries kept in history.", FCVAR_NONE, true, 1.0, true, 12.0);
    gCvarCashoutSafety = CreateConVar("umbrella_store_crash_cashout_safety", "0.02", "Anti-exploit safety margin before crash where cashout is blocked.", FCVAR_NONE, true, 0.0, true, 0.25);

    AutoExecConfig(true, "umbrella_store_crash");
    HookConVarChange(gCvarEnabled, OnCrashEnabledChanged);

    RegConsoleCmd("sm_crash", Cmd_Crash);
    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say_team");

    g_History = new ArrayList();

    for (int i = 1; i <= MaxClients; i++)
    {
        g_iLastShownCountdown[i] = -1;
        ResetClientRoundData(i, true);
    }
}

public void OnConfigsExecuted()
{
    RegisterWithStore();
    PrecacheConfiguredSounds();
}

public void OnAllPluginsLoaded()
{
    RegisterCrashQuests();
    RegisterWithStore();
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "umbrella_store"))
    {
        RegisterCrashQuests();
        g_bRegistered = false;
        RegisterWithStore();
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "umbrella_store"))
    {
        g_bRegistered = false;
    }
}

public void OnCrashEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RegisterWithStore();
}

public void OnMapStart()
{
    PrecacheConfiguredSounds();
}

public void OnPluginEnd()
{
    if (g_bRegistered && LibraryExists("umbrella_store"))
    {
        US_Casino_Unregister("crash");
    }
    g_bRegistered = false;

    KillTimerSafe(g_hWaitingTimer);
    KillTimerSafe(g_hRunTimer);
    KillTimerSafe(g_hRestartTimer);
    KillTimerSafe(g_hMenuRefreshTimer);
}

public void OnMapEnd()
{
    RefundAllOpenBets(true);
    ResetRoundState(true);
}

public void OnClientDisconnect(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    if (g_bHasBet[client] && !g_bCashedOut[client])
    {
        RefundBet(client, false, false);
    }

    g_bPanelOpen[client] = false;
    g_iLastShownCountdown[client] = -1;
    ResetClientRoundData(client, false);
}

public Action Cmd_Crash(int client, int args)
{
    if (!IsValidHumanClient(client))
    {
        return Plugin_Handled;
    }

    if (!gCvarEnabled.BoolValue)
    {
        CrashReply(client, "%T", "Crash Disabled", client);
        return Plugin_Handled;
    }

    if (!US_IsLoaded(client))
    {
        CrashReply(client, "%T", "Crash Store Not Loaded", client);
        return Plugin_Handled;
    }

    if (args < 1)
    {
        if (!AllowMenuOpen(client))
        {
            return Plugin_Handled;
        }

        g_bPanelOpen[client] = true;
        ShowCrashPanel(client);
        return Plugin_Handled;
    }

    char arg1[64];
    GetCmdArg(1, arg1, sizeof(arg1));
    TrimString(arg1);

    if (StrEqual(arg1, "cashout", false) || StrEqual(arg1, "retirar", false))
    {
        TryCashout(client);
        return Plugin_Handled;
    }

    if (StrEqual(arg1, "cancel", false) || StrEqual(arg1, "cancelar", false))
    {
        TryCancelBet(client);
        return Plugin_Handled;
    }

    int bet = StringToInt(arg1);
    if (bet > 0)
    {
        TryPlaceBet(client, bet, true);
        return Plugin_Handled;
    }

    g_bPanelOpen[client] = true;
    ShowCrashPanel(client);
    return Plugin_Handled;
}

public Action Command_Say(int client, const char[] command, int argc)
{
    if (!IsValidHumanClient(client))
    {
        return Plugin_Continue;
    }

    if (g_AwaitMethod[client] == AutoMethod_None)
    {
        return Plugin_Continue;
    }

    char text[192];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);

    if (text[0] == '\0')
    {
        return Plugin_Handled;
    }

    // While waiting for chat input, allow explicit crash menu reopen
    // and do not block unrelated chat commands from other plugins.
    if (text[0] == '!' || text[0] == '/')
    {
        if (StrEqual(text, "!crash", false) || StrEqual(text, "/crash", false))
        {
            g_AwaitMethod[client] = AutoMethod_None;
            if (AllowMenuOpen(client))
            {
                g_bPanelOpen[client] = true;
                ShowCrashPanel(client);
            }
            return Plugin_Handled;
        }

        if (StrEqual(text, "!cancel", false) || StrEqual(text, "/cancel", false))
        {
            g_AwaitMethod[client] = AutoMethod_None;
            CrashReply(client, "%T", "Crash Input Cancelled", client);
            return Plugin_Handled;
        }

        return Plugin_Continue;
    }

    if (StrEqual(text, "cancel", false) || StrEqual(text, "cancelar", false) || StrEqual(text, "0"))
    {
        g_AwaitMethod[client] = AutoMethod_None;
        CrashReply(client, "%T", "Crash Input Cancelled", client);
        return Plugin_Handled;
    }

    if (g_AwaitMethod[client] == AutoMethod_ChatBet)
    {
        g_AwaitMethod[client] = AutoMethod_None;
        int bet = StringToInt(text);
        TryPlaceBet(client, bet, true);
        return Plugin_Handled;
    }

    if (g_AwaitMethod[client] == AutoMethod_ChatAuto)
    {
        g_AwaitMethod[client] = AutoMethod_None;
        float value = StringToFloat(text);
        if (value <= 0.0)
        {
            g_fAutoCashout[client] = 0.0;
            CrashReply(client, "%T", "Crash Auto Disabled", client);
            return Plugin_Handled;
        }

        if (value < 1.10)
        {
            CrashReply(client, "%T", "Crash Auto Too Low", client, 1.10);
            return Plugin_Handled;
        }

        g_fAutoCashout[client] = value;
        CrashReply(client, "%T", "Crash Auto Set", client, value);
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public Action Timer_Waiting(Handle timer)
{
    if (timer != g_hWaitingTimer)
    {
        return Plugin_Stop;
    }

    if (g_State != CrashState_Waiting)
    {
        g_hWaitingTimer = null;
        return Plugin_Stop;
    }

    if (CountActiveBets(false) <= 0)
    {
        ResetRoundState(false);
        return Plugin_Stop;
    }

    if (GetGameTime() >= g_fCountdownEnd)
    {
        StartRunningRound();
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

public Action Timer_Running(Handle timer)
{
    if (timer != g_hRunTimer)
    {
        return Plugin_Stop;
    }

    if (g_State != CrashState_Running)
    {
        g_hRunTimer = null;
        return Plugin_Stop;
    }

    float elapsed = GetGameTime() - g_fRoundStartTime;
    if (g_bEpicSurgeRound && !g_bEpicSurgeAnnounced && elapsed >= g_fEpicSurgeStart)
    {
        g_bEpicSurgeAnnounced = true;
        AnnouncePhraseSimple("Crash Epic Surge");
    }
    g_fCurrentMultiplier = ComputeRunningMultiplier(elapsed);

    float safety = gCvarCashoutSafety.FloatValue;
    if (g_fCurrentMultiplier >= (g_fCrashAt - safety))
    {
        g_fCurrentMultiplier = g_fCrashAt;
        DoCrash();
        return Plugin_Stop;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHumanClient(client) || !g_bHasBet[client] || g_bCashedOut[client])
        {
            continue;
        }

        if (g_fAutoCashout[client] > 0.0 && g_fCurrentMultiplier >= g_fAutoCashout[client])
        {
            DoCashout(client);
        }
    }

    return Plugin_Continue;
}

public Action Timer_Restart(Handle timer)
{
    if (timer != g_hRestartTimer)
    {
        return Plugin_Stop;
    }

    g_hRestartTimer = null;
    if (g_State == CrashState_Crashed)
    {
        g_State = CrashState_Idle;
    }
    return Plugin_Stop;
}

public Action Timer_MenuRefresh(Handle timer)
{
    if (timer != g_hMenuRefreshTimer)
    {
        return Plugin_Stop;
    }

    if (g_State != CrashState_Waiting && g_State != CrashState_Running)
    {
        g_hMenuRefreshTimer = null;
        return Plugin_Stop;
    }

    bool anyOpen = false;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_bPanelOpen[client] || !IsValidHumanClient(client))
        {
            continue;
        }

        anyOpen = true;

        if (g_State == CrashState_Waiting)
        {
            float timeLeft = g_fCountdownEnd - GetGameTime();
            if (timeLeft < 0.0)
            {
                timeLeft = 0.0;
            }

            int countdown = RoundToCeil(timeLeft);
            if (countdown == g_iLastShownCountdown[client])
            {
                continue;
            }

            g_iLastShownCountdown[client] = countdown;
        }

        ShowCrashPanel(client);
    }

    if (!anyOpen)
    {
        g_hMenuRefreshTimer = null;
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

void EnsureMenuRefreshTimer()
{
    if (g_State != CrashState_Waiting && g_State != CrashState_Running)
    {
        return;
    }

    if (g_hMenuRefreshTimer == null)
    {
        g_hMenuRefreshTimer = CreateTimer(0.15, Timer_MenuRefresh, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

void RegisterWithStore()
{
    if (!LibraryExists("umbrella_store"))
    {
        g_bRegistered = false;
        return;
    }

    if (gCvarEnabled.BoolValue)
    {
        if (!g_bRegistered)
        {
            g_bRegistered = US_Casino_Register("crash", "Crash", "sm_crash");
        }
    }
    else if (g_bRegistered)
    {
        US_Casino_Unregister("crash");
        g_bRegistered = false;
    }
}


void ShowCrashPanel(int client)
{
    if (!IsValidHumanClient(client))
    {
        return;
    }

    Menu menu = new Menu(CrashMenuHandler);

    char title[512];
    BuildPanelTitle(client, title, sizeof(title));
    menu.SetTitle(title);
    menu.ExitButton = false;
    menu.Pagination = MENU_NO_PAGINATION;

    int layout = GetPanelLayout(client);
    char label[128];

    if (layout == 0)
    {
        Format(label, sizeof(label), "%T", "Crash Option Bet Min", client, GetMinBetForClient());
        menu.AddItem("betmin", label);
        Format(label, sizeof(label), "%T", "Crash Option Bet Max", client, GetMaxBetForClient(client));
        menu.AddItem("betmax", label);
        Format(label, sizeof(label), "%T", "Crash Option Bet Random", client, GetMinBetForClient(), GetMaxBetForClient(client));
        menu.AddItem("betrandom", label);
        if (g_fAutoCashout[client] > 0.0)
        {
            Format(label, sizeof(label), "%T", "Crash Option Auto Off", client);
        }
        else
        {
            Format(label, sizeof(label), "%T", "Crash Option Auto On", client);
        }
        menu.AddItem("auto", label);
        Format(label, sizeof(label), "%T", "Crash Option Info", client);
        menu.AddItem("info", label);
        Format(label, sizeof(label), "%T", "Crash Option Close", client);
        menu.AddItem("close", label);
    }
    else if (layout == 1)
    {
        Format(label, sizeof(label), "%T", "Crash Option Cancel Bet", client);
        menu.AddItem("cancel", label);
        if (g_fAutoCashout[client] > 0.0)
        {
            Format(label, sizeof(label), "%T", "Crash Option Auto Off", client);
        }
        else
        {
            Format(label, sizeof(label), "%T", "Crash Option Auto On", client);
        }
        menu.AddItem("auto", label);
        Format(label, sizeof(label), "%T", "Crash Option Info", client);
        menu.AddItem("info", label);
        Format(label, sizeof(label), "%T", "Crash Option Close", client);
        menu.AddItem("close", label);
    }
    else if (layout == 2)
    {
        Format(label, sizeof(label), "%T", "Crash Option Cashout", client);
        menu.AddItem("cashout", label);
        Format(label, sizeof(label), "%T", "Crash Option Info", client);
        menu.AddItem("info", label);
        if (g_fAutoCashout[client] > 0.0)
        {
            Format(label, sizeof(label), "%T", "Crash Option Auto Off", client);
        }
        else
        {
            Format(label, sizeof(label), "%T", "Crash Option Auto On", client);
        }
        menu.AddItem("auto", label);
        Format(label, sizeof(label), "%T", "Crash Option Close", client);
        menu.AddItem("close", label);
    }
    else if (layout == 4)
    {
        Format(label, sizeof(label), "%T", "Crash Option Info", client);
        menu.AddItem("info", label);
        Format(label, sizeof(label), "%T", "Crash Option Close", client);
        menu.AddItem("close", label);
    }
    else
    {
        Format(label, sizeof(label), "%T", "Crash Option Info", client);
        menu.AddItem("info", label);
        Format(label, sizeof(label), "%T", "Crash Option Close", client);
        menu.AddItem("close", label);
    }

    if (g_State == CrashState_Waiting)
    {
        float timeLeft = g_fCountdownEnd - GetGameTime();
        if (timeLeft < 0.0)
        {
            timeLeft = 0.0;
        }
        g_iLastShownCountdown[client] = RoundToCeil(timeLeft);
    }
    else
    {
        g_iLastShownCountdown[client] = -1;
    }

    menu.Display(client, 8);
    EnsureMenuRefreshTimer();
}

int GetPanelLayout(int client)
{
    if (g_State == CrashState_Running && g_bHasBet[client] && !g_bCashedOut[client])
    {
        return 2;
    }

    if (g_State == CrashState_Waiting && g_bHasBet[client] && !g_bCashedOut[client])
    {
        return 1;
    }

    if (!g_bHasBet[client])
    {
        if (g_State == CrashState_Running)
        {
            return 4;
        }
        return 0;
    }

    return 3;
}

public int CrashMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }

    if (client < 1 || client > MaxClients)
    {
        return 0;
    }

    if (action == MenuAction_Cancel)
    {
        if (param2 != MenuCancel_Interrupted)
        {
            g_bPanelOpen[client] = false;
            g_iLastShownCountdown[client] = -1;
        }
        return 0;
    }

    if (action != MenuAction_Select)
    {
        return 0;
    }

    char info[32];
    menu.GetItem(param2, info, sizeof(info));

    if (StrEqual(info, "close"))
    {
        g_bPanelOpen[client] = false;
        g_iLastShownCountdown[client] = -1;
        return 0;
    }
    else if (StrEqual(info, "info"))
    {
        SendGameInfo(client);
    }
    else if (StrEqual(info, "betmin"))
    {
        TryPlaceBet(client, GetMinBetForClient(), false);
    }
    else if (StrEqual(info, "betmax"))
    {
        TryPlaceBet(client, GetMaxBetForClient(client), false);
    }
    else if (StrEqual(info, "betrandom"))
    {
        TryPlaceBet(client, GetRandomBetForClient(client), false);
    }
    else if (StrEqual(info, "cancel"))
    {
        TryCancelBet(client);
    }
    else if (StrEqual(info, "cashout"))
    {
        TryCashout(client);
    }
    else if (StrEqual(info, "auto"))
    {
        HandleAutoOption(client);
    }

    if (g_bPanelOpen[client] && IsValidHumanClient(client))
    {
        ShowCrashPanel(client);
    }

    return 0;
}

void BuildPanelTitle(int client, char[] buffer, int maxlen)
{
    char autoText[32];
    if (g_fAutoCashout[client] > 0.0)
    {
        Format(autoText, sizeof(autoText), "x%.2f", g_fAutoCashout[client]);
    }
    else
    {
        Format(autoText, sizeof(autoText), "%T", "Crash Auto Off", client);
    }

    char betText[32];
    char gainedText[32];
    if (g_iBet[client] > 0)
    {
        FormatNumberDots(g_iBet[client], betText, sizeof(betText));
    }
    else
    {
        strcopy(betText, sizeof(betText), "0");
    }

    int gained = 0;
    if (g_iBet[client] > 0)
    {
        if (g_bCashedOut[client])
        {
            gained = g_iLastPayout[client];
        }
        else if (g_State == CrashState_Running)
        {
            gained = RoundToFloor(float(g_iBet[client]) * g_fCurrentMultiplier);
        }
    }
    FormatNumberDots(gained, gainedText, sizeof(gainedText));

    char historyText[96];
    BuildHistoryPreview(historyText, sizeof(historyText));

    if (g_State == CrashState_Waiting)
    {
        float timeLeft = g_fCountdownEnd - GetGameTime();
        if (timeLeft < 0.0)
        {
            timeLeft = 0.0;
        }

        int countdown = RoundToCeil(timeLeft);

        if (g_bHasBet[client])
        {
            Format(buffer, maxlen,
                "%T\n%T\n%T\n%T\n%T\n%T",
                "Crash Title", client,
                "Crash Starting", client, countdown,
                "Crash Auto Line", client, autoText,
                "Crash Bet Line", client, betText,
                "Crash History Line", client, historyText,
                "Crash Choose Option", client);
        }
        else
        {
            Format(buffer, maxlen,
                "%T\n%T\n%T\n%T\n%T\n%T",
                "Crash Title", client,
                "Crash Starting", client, countdown,
                "Crash Type Chat Bet", client,
                "Crash Auto Line", client, autoText,
                "Crash History Line", client, historyText,
                "Crash Choose Option", client);
        }
        return;
    }

    if (g_State == CrashState_Running)
    {
        if (g_bHasBet[client])
        {
            Format(buffer, maxlen,
                "%T\n%T\n%T\n%T\n%T\n%T",
                "Crash Title", client,
                "Crash Multiplier", client, g_fCurrentMultiplier,
                "Crash Gained Line", client, gainedText,
                "Crash Auto Line", client, autoText,
                "Crash Bet Line", client, betText,
                "Crash Choose Option", client);
        }
        else
        {
            int watching = CountActiveBets(true);
            Format(buffer, maxlen,
                "%T\n%T\n%T\n%T\n%T",
                "Crash Title", client,
                "Crash Multiplier", client, g_fCurrentMultiplier,
                "Crash Watching Line", client, watching,
                "Crash History Line", client, historyText,
                "Crash Choose Option", client);
        }
        return;
    }

    if (g_State == CrashState_Crashed)
    {
        Format(buffer, maxlen,
            "%T\n%T\n%T\n%T\n%T\n%T",
            "Crash Title", client,
            "Crash Crashed At", client, g_fLastCrashAt,
            "Crash Auto Line", client, autoText,
            "Crash Bet Line", client, betText,
            "Crash History Line", client, historyText,
            "Crash Choose Option", client);
        return;
    }

    if (g_bHasBet[client])
    {
        Format(buffer, maxlen,
            "%T\n%T\n%T\n%T\n%T\n%T",
            "Crash Title", client,
            "Crash Waiting Players", client,
            "Crash Auto Line", client, autoText,
            "Crash Bet Line", client, betText,
            "Crash History Line", client, historyText,
            "Crash Choose Option", client);
    }
    else
    {
        Format(buffer, maxlen,
            "%T\n%T\n%T\n%T\n%T\n%T",
            "Crash Title", client,
            "Crash Waiting Players", client,
            "Crash Type Chat Bet", client,
            "Crash Auto Line", client, autoText,
            "Crash History Line", client, historyText,
            "Crash Choose Option", client);
    }
}

void SendGameInfo(int client)
{
    CrashReply(client, "%T", "Crash Info 1", client);
    CrashReply(client, "%T", "Crash Info 2", client);
    CrashReply(client, "%T", "Crash Info 3", client);
}

void HandleAutoOption(int client)
{
    if (g_fAutoCashout[client] > 0.0)
    {
        g_fAutoCashout[client] = 0.0;
        CrashReply(client, "%T", "Crash Auto Disabled", client);
        return;
    }

    g_AwaitMethod[client] = AutoMethod_ChatAuto;
    CrashReply(client, "%T", "Crash Auto Prompt", client);
}

bool TryPlaceBet(int client, int amount, bool viaChat)
{
    if (!AllowAction(client))
    {
        return false;
    }

    if (g_State == CrashState_Running)
    {
        CrashReply(client, "%T", "Crash Round Already Running", client);
        return false;
    }

    if (g_bHasBet[client])
    {
        CrashReply(client, "%T", "Crash Already Bet", client);
        return false;
    }

    int minBet = GetMinBetForClient();
    int maxBet = GetMaxBetForClient(client);

    if (amount <= 0)
    {
        if (viaChat)
        {
            CrashReply(client, "%T", "Crash Bet Prompt", client);
            g_AwaitMethod[client] = AutoMethod_ChatBet;
        }
        return false;
    }

    if (amount < minBet)
    {
        CrashReply(client, "%T", "Crash Bet Too Low", client, minBet);
        return false;
    }

    if (amount > maxBet)
    {
        CrashReply(client, "%T", "Crash Bet Too High", client, maxBet);
        return false;
    }

    if (!US_TakeCredits(client, amount))
    {
        CrashReply(client, "%T", "Crash Not Enough Credits", client);
        return false;
    }

    g_bHasBet[client] = true;
    g_bCashedOut[client] = false;
    g_iBet[client] = amount;
    g_iLastPayout[client] = 0;

    char amountText[32];
    FormatNumberDots(amount, amountText, sizeof(amountText));
    CrashReply(client, "%T", "Crash Bet Placed", client, amountText);

    if (g_State == CrashState_Idle || g_State == CrashState_Crashed)
    {
        StartWaitingRound();
    }

    g_bPanelOpen[client] = true;
    ShowCrashPanel(client);

    return true;
}

bool TryCancelBet(int client)
{
    if (!AllowAction(client))
    {
        return false;
    }

    if (!g_bHasBet[client])
    {
        CrashReply(client, "%T", "Crash No Active Bet", client);
        return false;
    }

    if (g_State != CrashState_Waiting)
    {
        if (g_State == CrashState_Running && !g_bCashedOut[client])
        {
            return TryCashout(client);
        }

        CrashReply(client, "%T", "Crash Cannot Cancel Now", client);
        return false;
    }

    RefundBet(client, true, true);
    g_bPanelOpen[client] = true;
    ShowCrashPanel(client);

    return true;
}

bool TryCashout(int client)
{
    if (!AllowAction(client))
    {
        return false;
    }

    if (g_State != CrashState_Running)
    {
        CrashReply(client, "%T", "Crash Cannot Cashout Now", client);
        return false;
    }

    if (!g_bHasBet[client])
    {
        CrashReply(client, "%T", "Crash No Active Bet", client);
        return false;
    }

    if (g_bCashedOut[client])
    {
        CrashReply(client, "%T", "Crash Already Cashed", client);
        return false;
    }

    float safety = gCvarCashoutSafety.FloatValue;
    if (g_fCurrentMultiplier >= (g_fCrashAt - safety))
    {
        CrashReply(client, "%T", "Crash Cannot Cashout Now", client);
        return false;
    }

    DoCashout(client);
    g_bPanelOpen[client] = true;
    ShowCrashPanel(client);

    return true;
}

void StartWaitingRound()
{
    KillTimerSafe(g_hRestartTimer);
    KillTimerSafe(g_hRunTimer);
    KillTimerSafe(g_hWaitingTimer);

    g_State = CrashState_Waiting;
    g_fCurrentMultiplier = 1.0;
    g_fCrashAt = 1.0;
    g_bEpicSurgeRound = false;
    g_bEpicSurgeAnnounced = false;
    g_fEpicSurgeStart = 0.0;
    g_fCountdownEnd = GetGameTime() + gCvarCountdown.FloatValue;
    for (int client = 1; client <= MaxClients; client++)
    {
        g_iLastShownCountdown[client] = -1;
    }

    g_hWaitingTimer = CreateTimer(0.10, Timer_Waiting, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    EnsureMenuRefreshTimer();
}

void StartRunningRound()
{
    KillTimerSafe(g_hWaitingTimer);

    g_State = CrashState_Running;
    g_fRoundStartTime = GetGameTime();
    g_fCurrentMultiplier = 1.0;
    g_bEpicSurgeRound = false;
    g_bEpicSurgeAnnounced = false;
    g_fEpicSurgeStart = 0.0;
    g_fCrashAt = GenerateCrashPoint();

    float epicChance = gCvarEpicChance.FloatValue;
    if (epicChance > 0.0 && g_fCrashAt > (gCvarLowCrashMax.FloatValue + 0.001) && GetRandomFloat(0.0, 100.0) <= epicChance)
    {
        g_bEpicSurgeRound = true;

        float startMin = gCvarEpicStartMin.FloatValue;
        float startMax = gCvarEpicStartMax.FloatValue;
        if (startMax < startMin)
        {
            float swap = startMin;
            startMin = startMax;
            startMax = swap;
        }
        g_fEpicSurgeStart = GetRandomFloat(startMin, startMax);

        float minCrash = gCvarEpicMinCrash.FloatValue;
        if (g_fCrashAt < minCrash)
        {
            g_fCrashAt = minCrash + GetRandomFloat(0.0, 8.0);
        }
    }

    EmitConfiguredSoundAll(gCvarStartSound);
    AnnouncePhraseSimple("Crash Round Started");
    if (g_fCrashAt >= 50.0)
    {
        AnnouncePhraseSimple("Crash Rare Jackpot");
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        g_iLastShownCountdown[client] = -1;
        if (g_bPanelOpen[client] && IsValidHumanClient(client))
        {
            ShowCrashPanel(client);
        }
    }

    g_hRunTimer = CreateTimer(gCvarTickInterval.FloatValue, Timer_Running, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    EnsureMenuRefreshTimer();
}

void DoCrash()
{
    KillTimerSafe(g_hRunTimer);
    KillTimerSafe(g_hMenuRefreshTimer);

    g_State = CrashState_Crashed;
    g_fLastCrashAt = g_fCrashAt;
    PushHistory(g_fCrashAt);
    EmitConfiguredSoundAll(gCvarCrashSound);
    AnnouncePhraseFloat("Crash Round Crashed", g_fCrashAt);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_bPanelOpen[client] && IsValidHumanClient(client))
        {
            ShowCrashPanel(client);
        }

        if (!IsValidHumanClient(client) || !g_bHasBet[client] || g_bCashedOut[client])
        {
            continue;
        }

        CrashReply(client, "%T", "Crash Lost", client, g_fCrashAt);
        TrackCrashResolved(client, -g_iBet[client], false);
        ResetClientRoundData(client, false);
    }

    float delay = gCvarRestartDelay.FloatValue;
    if (delay > 0.0)
    {
        g_hRestartTimer = CreateTimer(delay, Timer_Restart, _, TIMER_FLAG_NO_MAPCHANGE);
    }
    else
    {
        g_State = CrashState_Idle;
    }
}

void DoCashout(int client)
{
    int payout = RoundToFloor(float(g_iBet[client]) * g_fCurrentMultiplier);
    if (payout < g_iBet[client])
    {
        payout = g_iBet[client];
    }

    US_AddCredits(client, payout, false);
    g_bCashedOut[client] = true;
    g_iLastPayout[client] = payout;
    TrackCrashResolved(client, payout - g_iBet[client], true);

    char payoutText[32];
    FormatNumberDots(payout, payoutText, sizeof(payoutText));
    CrashReply(client, "%T", "Crash Cashed Out", client, payoutText, g_fCurrentMultiplier);
    EmitConfiguredSoundClient(client, gCvarCashoutSound);

    ResetClientRoundData(client, true);

}

void RefundBet(int client, bool showMessage, bool cancelled)
{
    if (!g_bHasBet[client] || g_bCashedOut[client])
    {
        ResetClientRoundData(client, false);
        return;
    }

    int refund = g_iBet[client];
    if (refund > 0)
    {
        US_AddCredits(client, refund, false);
    }

    if (showMessage)
    {
        char refundText[32];
        FormatNumberDots(refund, refundText, sizeof(refundText));
        if (cancelled)
        {
            CrashReply(client, "%T", "Crash Bet Cancelled", client, refundText);
        }
        else
        {
            CrashReply(client, "%T", "Crash Bet Refunded", client, refundText);
        }
    }

    ResetClientRoundData(client, false);
}

void RefundAllOpenBets(bool showMessage)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHumanClient(client) || !g_bHasBet[client] || g_bCashedOut[client])
        {
            continue;
        }

        RefundBet(client, showMessage, false);
    }
}

void ResetRoundState(bool closePanels)
{
    KillTimerSafe(g_hWaitingTimer);
    KillTimerSafe(g_hRunTimer);
    KillTimerSafe(g_hRestartTimer);
    KillTimerSafe(g_hMenuRefreshTimer);

    g_State = CrashState_Idle;
    g_fCountdownEnd = 0.0;
    g_fRoundStartTime = 0.0;
    g_fCurrentMultiplier = 1.0;
    g_fCrashAt = 1.0;
    g_bEpicSurgeRound = false;
    g_bEpicSurgeAnnounced = false;
    g_fEpicSurgeStart = 0.0;

    for (int client = 1; client <= MaxClients; client++)
    {
        ResetClientRoundData(client, closePanels);
    }
}

void ResetClientRoundData(int client, bool keepAuto)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    g_bHasBet[client] = false;
    g_bCashedOut[client] = false;
    g_iBet[client] = 0;
    g_iLastPayout[client] = 0;
    g_AwaitMethod[client] = AutoMethod_None;

    if (!keepAuto)
    {
        g_fAutoCashout[client] = 0.0;
        g_bPanelOpen[client] = false;
    }

    g_iLastShownCountdown[client] = -1;
}

int CountActiveBets(bool includeCashedOut)
{
    int count = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHumanClient(client) || !g_bHasBet[client])
        {
            continue;
        }

        if (!includeCashedOut && g_bCashedOut[client])
        {
            continue;
        }

        count++;
    }
    return count;
}

int GetMinBetForClient()
{
    int minBet = gCvarMinBet.IntValue;
    return (minBet < 1) ? 1 : minBet;
}

int GetMaxBetForClient(int client)
{
    int maxBet = gCvarMaxBet.IntValue;
    int credits = US_GetCredits(client);
    if (maxBet > credits)
    {
        maxBet = credits;
    }

    int minBet = GetMinBetForClient();
    if (maxBet < minBet)
    {
        maxBet = minBet;
    }
    return maxBet;
}

int GetRandomBetForClient(int client)
{
    int minBet = GetMinBetForClient();
    int maxBet = GetMaxBetForClient(client);
    if (maxBet <= minBet)
    {
        return minBet;
    }

    return GetRandomInt(minBet, maxBet);
}

float GenerateCrashPoint()
{
    float lowChance = gCvarLowCrashChance.FloatValue;
    if (lowChance > 0.0 && GetRandomFloat(0.0, 100.0) <= lowChance)
    {
        float lowMin = gCvarLowCrashMin.FloatValue;
        float lowMax = gCvarLowCrashMax.FloatValue;
        if (lowMax < lowMin)
        {
            float swap = lowMin;
            lowMin = lowMax;
            lowMax = swap;
        }

        if (lowMin < 1.0)
        {
            lowMin = 1.0;
        }
        if (lowMax < 1.0)
        {
            lowMax = 1.0;
        }

        return GetRandomFloat(lowMin, lowMax);
    }

    int roll = GetRandomInt(1, 10000);
    if (roll <= 3500)
    {
        return GetRandomFloat(1.03, 1.55);
    }
    if (roll <= 7200)
    {
        return GetRandomFloat(1.55, 2.40);
    }
    if (roll <= 9100)
    {
        return GetRandomFloat(2.40, 5.00);
    }
    if (roll <= 9800)
    {
        return GetRandomFloat(5.00, 12.00);
    }
    if (roll <= 9960)
    {
        return GetRandomFloat(12.00, 30.00);
    }
    if (roll <= 9992)
    {
        return GetRandomFloat(30.00, 50.00);
    }
    return GetRandomFloat(50.00, 100.00);
}

float ComputeRunningMultiplier(float elapsed)
{
    if (elapsed < 0.0)
    {
        elapsed = 0.0;
    }

    float linear = gCvarGrowthPerSecond.FloatValue * elapsed;
    float curve = gCvarGrowthCurve.FloatValue * elapsed * elapsed;

    float factor = 1.0;
    float warmup = gCvarWarmupSeconds.FloatValue;
    if (warmup > 0.0)
    {
        float t = elapsed / warmup;
        if (t < 0.0)
        {
            t = 0.0;
        }
        else if (t > 1.0)
        {
            t = 1.0;
        }

        // During warmup we start slower and ramp up to full speed smoothly.
        factor = 0.22 + (0.78 * t * t);
    }

    float result = 1.0 + ((linear + curve) * factor);

    if (g_bEpicSurgeRound && elapsed >= g_fEpicSurgeStart)
    {
        float epicElapsed = elapsed - g_fEpicSurgeStart;
        float epicLinear = gCvarEpicBoostPerSecond.FloatValue * epicElapsed;
        float epicCurve = gCvarEpicBoostCurve.FloatValue * epicElapsed * epicElapsed;
        result += epicLinear + epicCurve;
    }

    return result;
}

void PushHistory(float value)
{
    if (g_History == null)
    {
        return;
    }

    if (g_History.Length >= gCvarHistoryMax.IntValue)
    {
        g_History.Erase(0);
    }
    g_History.Push(RoundToFloor(value * 100.0));
}

void BuildHistoryPreview(char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (g_History == null || g_History.Length <= 0)
    {
        strcopy(buffer, maxlen, "-");
        return;
    }

    char piece[16];
    for (int i = g_History.Length - 1; i >= 0; i--)
    {
        int raw = g_History.Get(i);
        float value = float(raw) / 100.0;
        Format(piece, sizeof(piece), "x%.2f", value);
        if (buffer[0] == '\0')
        {
            strcopy(buffer, maxlen, piece);
        }
        else
        {
            Format(buffer, maxlen, "%s, %s", buffer, piece);
        }
    }
}

bool AllowAction(int client)
{
    float now = GetGameTime();
    if (now < g_fNextActionAt[client])
    {
        return false;
    }

    g_fNextActionAt[client] = now + gCvarMinSpamGap.FloatValue;
    return true;
}

bool AllowMenuOpen(int client)
{
    float now = GetGameTime();
    if (now < g_fNextMenuAt[client])
    {
        return false;
    }

    g_fNextMenuAt[client] = now + 0.25;
    return true;
}

bool IsValidHumanClient(int client)
{
    return (client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

void KillTimerSafe(Handle &timer)
{
    if (timer != null)
    {
        KillTimer(timer);
        timer = null;
    }
}

void EmitConfiguredSoundAll(ConVar cvar)
{
    char sound[PLATFORM_MAX_PATH];
    cvar.GetString(sound, sizeof(sound));
    TrimString(sound);
    if (sound[0] == '\0')
    {
        return;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHumanClient(client))
        {
            continue;
        }

        // Only notify players actively participating in the current crash round.
        if (!g_bHasBet[client] || g_bCashedOut[client])
        {
            continue;
        }

        EmitSoundToClient(client, sound, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL);
    }
}

void EmitConfiguredSoundClient(int client, ConVar cvar)
{
    char sound[PLATFORM_MAX_PATH];
    cvar.GetString(sound, sizeof(sound));
    TrimString(sound);
    if (sound[0] == '\0')
    {
        return;
    }

    EmitSoundToClient(client, sound, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL);
}



void AnnouncePhraseSimple(const char[] phrase)
{
    if (!gCvarAnnounce.BoolValue || phrase[0] == '\0')
    {
        return;
    }

    char message[256], highlighted[320];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHumanClient(client))
        {
            continue;
        }

        Format(message, sizeof(message), "%T", phrase, client);
        HighlightChatCommands(message, highlighted, sizeof(highlighted));
        CPrintToChat(client, "%s %s", CRASH_CHAT_TAG, highlighted);
    }
}

void AnnouncePhraseFloat(const char[] phrase, float value)
{
    if (!gCvarAnnounce.BoolValue || phrase[0] == '\0')
    {
        return;
    }

    char message[256], highlighted[320];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHumanClient(client))
        {
            continue;
        }

        Format(message, sizeof(message), "%T", phrase, client, value);
        HighlightChatCommands(message, highlighted, sizeof(highlighted));
        CPrintToChat(client, "%s %s", CRASH_CHAT_TAG, highlighted);
    }
}

void PrecacheConfiguredSounds()
{
    PrecacheConfiguredSound(gCvarStartSound);
    PrecacheConfiguredSound(gCvarCashoutSound);
    PrecacheConfiguredSound(gCvarCrashSound);
}

void PrecacheConfiguredSound(ConVar cvar)
{
    char sound[PLATFORM_MAX_PATH];
    cvar.GetString(sound, sizeof(sound));
    TrimString(sound);
    if (sound[0] == '\0')
    {
        return;
    }

    PrecacheSound(sound, true);
}

void FormatNumberDots(int value, char[] buffer, int maxlen)
{
    char digits[32];
    IntToString(value, digits, sizeof(digits));

    int len = strlen(digits);
    int out = 0;
    int group = len % 3;
    if (group == 0)
    {
        group = 3;
    }

    for (int i = 0; i < len && out < maxlen - 1; i++)
    {
        buffer[out++] = digits[i];
        if (i == len - 1)
        {
            continue;
        }

        if (group > 0)
        {
            group--;
        }

        if (group == 0)
        {
            if (out < maxlen - 1)
            {
                buffer[out++] = '.';
            }
            group = 3;
        }
    }

    buffer[out] = '\0';
}

void CrashReply(int client, const char[] fmt, any ...)
{
    char message[256], highlighted[320];
    VFormat(message, sizeof(message), fmt, 3);
    HighlightChatCommands(message, highlighted, sizeof(highlighted));
    CPrintToChat(client, "%s %s", CRASH_CHAT_TAG, highlighted);
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

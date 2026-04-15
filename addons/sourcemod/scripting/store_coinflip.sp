#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <umbrella_store>
#include <multicolors>

#define US_CHAT_TAG " {purple}[Umbrella Store]{default}"

#define CASINO_ID "coinflip"

enum CoinflipFlow
{
    Flow_None = 0,
    Flow_House,
    Flow_PvP
};

public Plugin myinfo =
{
    name        = "[Umbrella Store] Casino - Coinflip",
    author      = "Ayrton09",
    description = "Coinflip contra la casa y versus jugador para Umbrella Store",
    version     = "1.1.0",
    url         = ""
};

ConVar gCvarEnabled;
ConVar gCvarMinBet;
ConVar gCvarMaxBet;
ConVar gCvarCooldown;
ConVar gCvarWinMultiplier;
ConVar gCvarWinSound;
ConVar gCvarLoseSound;
ConVar gCvarAnnounceBig;
ConVar gCvarAnnounceThreshold;
ConVar gCvarAnimEnabled;
ConVar gCvarAnimSteps;
ConVar gCvarAnimDelay;
ConVar gCvarAnimMode;
ConVar gCvarPvpEnabled;
ConVar gCvarPvpTimeout;
ConVar gCvarPvpChallengeCooldown;
ConVar gLegacyCvarEnabled;
ConVar gLegacyCvarMinBet;
ConVar gLegacyCvarMaxBet;
ConVar gLegacyCvarCooldown;
ConVar gLegacyCvarWinMultiplier;
ConVar gLegacyCvarWinSound;
ConVar gLegacyCvarLoseSound;
ConVar gLegacyCvarAnnounceBig;
ConVar gLegacyCvarAnnounceThreshold;
ConVar gLegacyCvarAnimEnabled;
ConVar gLegacyCvarAnimSteps;
ConVar gLegacyCvarAnimDelay;
ConVar gLegacyCvarAnimMode;
ConVar gLegacyCvarPvpEnabled;
ConVar gLegacyCvarPvpTimeout;
ConVar gLegacyCvarPvpChallengeCooldown;
bool g_bSyncingCvarAliases = false;

float g_fNextUse[MAXPLAYERS + 1];
float g_fNextChallenge[MAXPLAYERS + 1];

int g_iPendingBet[MAXPLAYERS + 1];
int g_iPendingTarget[MAXPLAYERS + 1];
CoinflipFlow g_iFlow[MAXPLAYERS + 1];

bool g_bWaitingBet[MAXPLAYERS + 1];
bool g_bRolling[MAXPLAYERS + 1];

Handle g_hAnimTimer[MAXPLAYERS + 1];
int g_iAnimStep[MAXPLAYERS + 1];
int g_iAnimChoice[MAXPLAYERS + 1];
int g_iAnimBet[MAXPLAYERS + 1];
int g_iAnimResult[MAXPLAYERS + 1];
bool g_bAnimPvp[MAXPLAYERS + 1];
int g_iAnimOpponent[MAXPLAYERS + 1];

/* Fix for PvP stuck state */
bool g_bPvpReady[MAXPLAYERS + 1];
bool g_bPvpResolved[MAXPLAYERS + 1];

int g_iChallengeFrom[MAXPLAYERS + 1];
int g_iChallengeAmount[MAXPLAYERS + 1];
Handle g_hChallengeTimer[MAXPLAYERS + 1];

void TrackCoinflipResult(int client, int net, bool win)
{
    if (!IsValidClient(client))
    {
        return;
    }

    US_AddStat(client, "coinflip_games", 1);
    US_AddStat(client, win ? "coinflip_wins" : "coinflip_losses", 1);

    if (net != 0)
    {
        US_AddStat(client, "coinflip_profit", net);
    }

    if (win)
    {
        US_AdvanceQuestProgress(client, "coinflip_wins_5", 1);
    }
}

void RegisterCoinflipQuests()
{
    if (!LibraryExists("umbrella_store"))
    {
        return;
    }

    US_RegisterQuestEx("coinflip_wins_5", "Quest Title Coinflip Wins I", 5, 200, "", false, "Quest Category Casino", "Quest Desc Coinflip Wins I");
}

void SyncCoinflipCvarPair(ConVar source, ConVar target)
{
    if (source == null || target == null)
    {
        return;
    }

    char value[PLATFORM_MAX_PATH];
    source.GetString(value, sizeof(value));
    target.SetString(value);
}

void SyncCoinflipLegacyCvarsFromCanonical()
{
    g_bSyncingCvarAliases = true;
    SyncCoinflipCvarPair(gCvarEnabled, gLegacyCvarEnabled);
    SyncCoinflipCvarPair(gCvarMinBet, gLegacyCvarMinBet);
    SyncCoinflipCvarPair(gCvarMaxBet, gLegacyCvarMaxBet);
    SyncCoinflipCvarPair(gCvarCooldown, gLegacyCvarCooldown);
    SyncCoinflipCvarPair(gCvarWinMultiplier, gLegacyCvarWinMultiplier);
    SyncCoinflipCvarPair(gCvarWinSound, gLegacyCvarWinSound);
    SyncCoinflipCvarPair(gCvarLoseSound, gLegacyCvarLoseSound);
    SyncCoinflipCvarPair(gCvarAnnounceBig, gLegacyCvarAnnounceBig);
    SyncCoinflipCvarPair(gCvarAnnounceThreshold, gLegacyCvarAnnounceThreshold);
    SyncCoinflipCvarPair(gCvarAnimEnabled, gLegacyCvarAnimEnabled);
    SyncCoinflipCvarPair(gCvarAnimSteps, gLegacyCvarAnimSteps);
    SyncCoinflipCvarPair(gCvarAnimDelay, gLegacyCvarAnimDelay);
    SyncCoinflipCvarPair(gCvarAnimMode, gLegacyCvarAnimMode);
    SyncCoinflipCvarPair(gCvarPvpEnabled, gLegacyCvarPvpEnabled);
    SyncCoinflipCvarPair(gCvarPvpTimeout, gLegacyCvarPvpTimeout);
    SyncCoinflipCvarPair(gCvarPvpChallengeCooldown, gLegacyCvarPvpChallengeCooldown);
    g_bSyncingCvarAliases = false;
}

public void OnCoinflipAliasCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (g_bSyncingCvarAliases)
    {
        return;
    }

    g_bSyncingCvarAliases = true;

    if (convar == gCvarEnabled) gLegacyCvarEnabled.SetString(newValue);
    else if (convar == gLegacyCvarEnabled) gCvarEnabled.SetString(newValue);
    else if (convar == gCvarMinBet) gLegacyCvarMinBet.SetString(newValue);
    else if (convar == gLegacyCvarMinBet) gCvarMinBet.SetString(newValue);
    else if (convar == gCvarMaxBet) gLegacyCvarMaxBet.SetString(newValue);
    else if (convar == gLegacyCvarMaxBet) gCvarMaxBet.SetString(newValue);
    else if (convar == gCvarCooldown) gLegacyCvarCooldown.SetString(newValue);
    else if (convar == gLegacyCvarCooldown) gCvarCooldown.SetString(newValue);
    else if (convar == gCvarWinMultiplier) gLegacyCvarWinMultiplier.SetString(newValue);
    else if (convar == gLegacyCvarWinMultiplier) gCvarWinMultiplier.SetString(newValue);
    else if (convar == gCvarWinSound) gLegacyCvarWinSound.SetString(newValue);
    else if (convar == gLegacyCvarWinSound) gCvarWinSound.SetString(newValue);
    else if (convar == gCvarLoseSound) gLegacyCvarLoseSound.SetString(newValue);
    else if (convar == gLegacyCvarLoseSound) gCvarLoseSound.SetString(newValue);
    else if (convar == gCvarAnnounceBig) gLegacyCvarAnnounceBig.SetString(newValue);
    else if (convar == gLegacyCvarAnnounceBig) gCvarAnnounceBig.SetString(newValue);
    else if (convar == gCvarAnnounceThreshold) gLegacyCvarAnnounceThreshold.SetString(newValue);
    else if (convar == gLegacyCvarAnnounceThreshold) gCvarAnnounceThreshold.SetString(newValue);
    else if (convar == gCvarAnimEnabled) gLegacyCvarAnimEnabled.SetString(newValue);
    else if (convar == gLegacyCvarAnimEnabled) gCvarAnimEnabled.SetString(newValue);
    else if (convar == gCvarAnimSteps) gLegacyCvarAnimSteps.SetString(newValue);
    else if (convar == gLegacyCvarAnimSteps) gCvarAnimSteps.SetString(newValue);
    else if (convar == gCvarAnimDelay) gLegacyCvarAnimDelay.SetString(newValue);
    else if (convar == gLegacyCvarAnimDelay) gCvarAnimDelay.SetString(newValue);
    else if (convar == gCvarAnimMode) gLegacyCvarAnimMode.SetString(newValue);
    else if (convar == gLegacyCvarAnimMode) gCvarAnimMode.SetString(newValue);
    else if (convar == gCvarPvpEnabled) gLegacyCvarPvpEnabled.SetString(newValue);
    else if (convar == gLegacyCvarPvpEnabled) gCvarPvpEnabled.SetString(newValue);
    else if (convar == gCvarPvpTimeout) gLegacyCvarPvpTimeout.SetString(newValue);
    else if (convar == gLegacyCvarPvpTimeout) gCvarPvpTimeout.SetString(newValue);
    else if (convar == gCvarPvpChallengeCooldown) gLegacyCvarPvpChallengeCooldown.SetString(newValue);
    else if (convar == gLegacyCvarPvpChallengeCooldown) gCvarPvpChallengeCooldown.SetString(newValue);

    g_bSyncingCvarAliases = false;
}

public void OnPluginStart()
{
    LoadTranslations("umbrella_store_coinflip.phrases");

    RegConsoleCmd("sm_coinflip", Command_Coinflip);
    RegConsoleCmd("sm_cf", Command_Coinflip);

    RegConsoleCmd("sm_coinflipvs", Command_CoinflipVs);
    RegConsoleCmd("sm_cfvs", Command_CoinflipVs);
    RegConsoleCmd("sm_coinflipaccept", Command_CoinflipAccept);
    RegConsoleCmd("sm_cfa", Command_CoinflipAccept);
    RegConsoleCmd("sm_coinflipdeny", Command_CoinflipDeny);
    RegConsoleCmd("sm_cfd", Command_CoinflipDeny);

    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say_team");

    gCvarEnabled = CreateConVar("umbrella_store_coinflip_enabled", "1", "Enable the coinflip module.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarMinBet = CreateConVar("umbrella_store_coinflip_min_bet", "50", "Minimum bet.", FCVAR_NONE, true, 1.0);
    gCvarMaxBet = CreateConVar("umbrella_store_coinflip_max_bet", "1000000", "Maximum bet. 0 = no limit.", FCVAR_NONE, true, 0.0);
    gCvarCooldown = CreateConVar("umbrella_store_coinflip_cooldown", "2.0", "Cooldown between uses.", FCVAR_NONE, true, 0.0);
    gCvarWinMultiplier = CreateConVar("umbrella_store_coinflip_multiplier", "2.0", "Multiplier when winning against the house.", FCVAR_NONE, true, 1.0);

    gCvarWinSound = CreateConVar("umbrella_store_coinflip_win_sound", "items/itempickup.wav", "Sound played on win.");
    gCvarLoseSound = CreateConVar("umbrella_store_coinflip_lose_sound", "buttons/button10.wav", "Sound played on loss.");

    gCvarAnnounceBig = CreateConVar("umbrella_store_coinflip_announce_big", "1", "Announce large bets globally.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarAnnounceThreshold = CreateConVar("umbrella_store_coinflip_announce_threshold", "2000", "Threshold for global announcement.", FCVAR_NONE, true, 1.0);

    gCvarAnimEnabled = CreateConVar("umbrella_store_coinflip_anim_enabled", "1", "Enable non-graphical animation.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarAnimSteps = CreateConVar("umbrella_store_coinflip_anim_steps", "6", "Number of animation steps.", FCVAR_NONE, true, 1.0, true, 20.0);
    gCvarAnimDelay = CreateConVar("umbrella_store_coinflip_anim_delay", "0.35", "Delay between animation steps.", FCVAR_NONE, true, 0.05, true, 3.0);
    gCvarAnimMode = CreateConVar("umbrella_store_coinflip_anim_mode", "2", "1 = center text, 2 = hint text.", FCVAR_NONE, true, 1.0, true, 2.0);

    gCvarPvpEnabled = CreateConVar("umbrella_store_coinflip_pvp_enabled", "1", "Enable player-vs-player coinflip.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarPvpTimeout = CreateConVar("umbrella_store_coinflip_pvp_timeout", "20.0", "Time to accept a PvP coinflip.", FCVAR_NONE, true, 5.0, true, 120.0);
    gCvarPvpChallengeCooldown = CreateConVar("umbrella_store_coinflip_pvp_challenge_cooldown", "8.0", "Cooldown between PvP challenges to prevent spam.", FCVAR_NONE, true, 0.0, true, 120.0);

    gLegacyCvarEnabled = CreateConVar("sm_umbrella_store_coinflip_enabled", "1", "Legacy alias for umbrella_store_coinflip_enabled.", FCVAR_DONTRECORD, true, 0.0, true, 1.0);
    gLegacyCvarMinBet = CreateConVar("sm_umbrella_store_coinflip_min_bet", "50", "Legacy alias for umbrella_store_coinflip_min_bet.", FCVAR_DONTRECORD, true, 1.0);
    gLegacyCvarMaxBet = CreateConVar("sm_umbrella_store_coinflip_max_bet", "1000000", "Legacy alias for umbrella_store_coinflip_max_bet.", FCVAR_DONTRECORD, true, 0.0);
    gLegacyCvarCooldown = CreateConVar("sm_umbrella_store_coinflip_cooldown", "2.0", "Legacy alias for umbrella_store_coinflip_cooldown.", FCVAR_DONTRECORD, true, 0.0);
    gLegacyCvarWinMultiplier = CreateConVar("sm_umbrella_store_coinflip_multiplier", "2.0", "Legacy alias for umbrella_store_coinflip_multiplier.", FCVAR_DONTRECORD, true, 1.0);
    gLegacyCvarWinSound = CreateConVar("sm_umbrella_store_coinflip_win_sound", "items/itempickup.wav", "Legacy alias for umbrella_store_coinflip_win_sound.", FCVAR_DONTRECORD);
    gLegacyCvarLoseSound = CreateConVar("sm_umbrella_store_coinflip_lose_sound", "buttons/button10.wav", "Legacy alias for umbrella_store_coinflip_lose_sound.", FCVAR_DONTRECORD);
    gLegacyCvarAnnounceBig = CreateConVar("sm_umbrella_store_coinflip_announce_big", "1", "Legacy alias for umbrella_store_coinflip_announce_big.", FCVAR_DONTRECORD, true, 0.0, true, 1.0);
    gLegacyCvarAnnounceThreshold = CreateConVar("sm_umbrella_store_coinflip_announce_threshold", "2000", "Legacy alias for umbrella_store_coinflip_announce_threshold.", FCVAR_DONTRECORD, true, 1.0);
    gLegacyCvarAnimEnabled = CreateConVar("sm_umbrella_store_coinflip_anim_enabled", "1", "Legacy alias for umbrella_store_coinflip_anim_enabled.", FCVAR_DONTRECORD, true, 0.0, true, 1.0);
    gLegacyCvarAnimSteps = CreateConVar("sm_umbrella_store_coinflip_anim_steps", "6", "Legacy alias for umbrella_store_coinflip_anim_steps.", FCVAR_DONTRECORD, true, 1.0, true, 20.0);
    gLegacyCvarAnimDelay = CreateConVar("sm_umbrella_store_coinflip_anim_delay", "0.35", "Legacy alias for umbrella_store_coinflip_anim_delay.", FCVAR_DONTRECORD, true, 0.05, true, 3.0);
    gLegacyCvarAnimMode = CreateConVar("sm_umbrella_store_coinflip_anim_mode", "2", "Legacy alias for umbrella_store_coinflip_anim_mode.", FCVAR_DONTRECORD, true, 1.0, true, 2.0);
    gLegacyCvarPvpEnabled = CreateConVar("sm_umbrella_store_coinflip_pvp_enabled", "1", "Legacy alias for umbrella_store_coinflip_pvp_enabled.", FCVAR_DONTRECORD, true, 0.0, true, 1.0);
    gLegacyCvarPvpTimeout = CreateConVar("sm_umbrella_store_coinflip_pvp_timeout", "20.0", "Legacy alias for umbrella_store_coinflip_pvp_timeout.", FCVAR_DONTRECORD, true, 5.0, true, 120.0);
    gLegacyCvarPvpChallengeCooldown = CreateConVar("sm_umbrella_store_coinflip_pvp_challenge_cooldown", "8.0", "Legacy alias for umbrella_store_coinflip_pvp_challenge_cooldown.", FCVAR_DONTRECORD, true, 0.0, true, 120.0);

    HookConVarChange(gCvarEnabled, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarMinBet, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarMaxBet, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarCooldown, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarWinMultiplier, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarWinSound, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarLoseSound, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarAnnounceBig, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarAnnounceThreshold, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarAnimEnabled, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarAnimSteps, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarAnimDelay, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarAnimMode, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarPvpEnabled, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarPvpTimeout, OnCoinflipAliasCvarChanged);
    HookConVarChange(gCvarPvpChallengeCooldown, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarEnabled, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarMinBet, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarMaxBet, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarCooldown, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarWinMultiplier, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarWinSound, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarLoseSound, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarAnnounceBig, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarAnnounceThreshold, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarAnimEnabled, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarAnimSteps, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarAnimDelay, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarAnimMode, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarPvpEnabled, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarPvpTimeout, OnCoinflipAliasCvarChanged);
    HookConVarChange(gLegacyCvarPvpChallengeCooldown, OnCoinflipAliasCvarChanged);

    AutoExecConfig(true, "umbrella_store_coinflip");
    SyncCoinflipLegacyCvarsFromCanonical();
    RegisterCoinflipQuests();
    RegisterCasinoEntry();
}

public void OnMapStart()
{
    PrecacheConfiguredSound(gCvarWinSound);
    PrecacheConfiguredSound(gCvarLoseSound);
}

public void OnAllPluginsLoaded()
{
    RegisterCasinoEntry();
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "umbrella_store"))
    {
        RegisterCoinflipQuests();
        RegisterCasinoEntry();
    }
}

void RegisterCasinoEntry()
{
    if (LibraryExists("umbrella_store"))
    {
        char title[64];
        Format(title, sizeof(title), "%T", "CF Casino Title", LANG_SERVER);
        US_Casino_Register(CASINO_ID, title, "sm_coinflip");
    }
}

public void OnPluginEnd()
{
    if (LibraryExists("umbrella_store"))
    {
        US_Casino_Unregister(CASINO_ID);
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        CleanupState(i);
    }
}

public void OnClientDisconnect(int client)
{
    ResolvePvpDisconnect(client);
    CleanupState(client);

    int target = FindChallengeTargetByChallenger(client);
    if (target > 0)
    {
        ClearIncomingChallenge(target, true);
    }
}

void ResolvePvpDisconnect(int client)
{
    if (client < 1 || client > MaxClients || !g_bAnimPvp[client] || !g_bRolling[client] || g_bPvpResolved[client])
    {
        return;
    }

    int opponent = g_iAnimOpponent[client];
    int amount = g_iAnimBet[client];
    if (!IsValidClient(opponent) || !g_bAnimPvp[opponent] || g_iAnimOpponent[opponent] != client)
    {
        return;
    }

    g_bPvpResolved[client] = true;
    g_bPvpResolved[opponent] = true;

    if (amount > 0)
    {
        US_AddCredits(opponent, amount * 2, false);
    }

    TrackCoinflipResult(opponent, amount, true);

    EmitConfiguredSound(opponent, gCvarWinSound);
    CF_Print(opponent, "%t", "CF PvP Opponent Disconnected", amount * 2);
    g_fNextUse[opponent] = GetGameTime() + gCvarCooldown.FloatValue;
    ResetAnimState(opponent);
}

void CleanupState(int client)
{
    if (g_hAnimTimer[client] != null)
    {
        KillTimer(g_hAnimTimer[client]);
        g_hAnimTimer[client] = null;
    }

    if (g_hChallengeTimer[client] != null)
    {
        KillTimer(g_hChallengeTimer[client]);
        g_hChallengeTimer[client] = null;
    }

    g_fNextUse[client] = 0.0;
    g_fNextChallenge[client] = 0.0;
    g_iPendingBet[client] = 0;
    g_iPendingTarget[client] = 0;
    g_iFlow[client] = Flow_None;
    g_bWaitingBet[client] = false;
    ResetAnimState(client);
    g_iChallengeFrom[client] = 0;
    g_iChallengeAmount[client] = 0;
}

public Action Command_Coinflip(int client, int args)
{
    if (!CanUseCoinflip(client))
    {
        return Plugin_Handled;
    }

    if (args >= 1)
    {
        char sBet[32];
        GetCmdArg(1, sBet, sizeof(sBet));

        int bet = ParseBetInput(client, sBet);
        if (!ValidateBet(client, bet))
        {
            return Plugin_Handled;
        }

        g_iFlow[client] = Flow_House;
        g_iPendingBet[client] = bet;
        ShowSideMenu(client);
        return Plugin_Handled;
    }

    ShowMainMenu(client);
    return Plugin_Handled;
}

public Action Command_CoinflipVs(int client, int args)
{
    if (!CanUseCoinflip(client))
    {
        return Plugin_Handled;
    }

    if (!gCvarPvpEnabled.BoolValue)
    {
        CF_Print(client, "%t", "CF PvP Disabled");
        return Plugin_Handled;
    }

    if (args < 2)
    {
        ShowPlayerSelectMenu(client);
        return Plugin_Handled;
    }

    char sTarget[64], sAmount[32];
    GetCmdArg(1, sTarget, sizeof(sTarget));
    GetCmdArg(2, sAmount, sizeof(sAmount));

    int target = FindTarget(client, sTarget, true, false);
    if (target <= 0)
    {
        return Plugin_Handled;
    }

    StartPvPChallenge(client, target, ParseBetInput(client, sAmount));
    return Plugin_Handled;
}

public Action Command_CoinflipAccept(int client, int args)
{
    HandleChallengeResponse(client, true);
    return Plugin_Handled;
}

public Action Command_CoinflipDeny(int client, int args)
{
    HandleChallengeResponse(client, false);
    return Plugin_Handled;
}

void HandleChallengeResponse(int client, bool accept)
{
    if (!IsValidClient(client))
    {
        return;
    }

    int challenger = g_iChallengeFrom[client];
    int amount = g_iChallengeAmount[client];

    if (challenger <= 0 || !IsValidClient(challenger))
    {
        CF_Print(client, "%t", "CF No Pending Challenge");
        ClearIncomingChallenge(client, false);
        return;
    }

    if (!accept)
    {
        ClearIncomingChallenge(client, true);
        return;
    }

    if (!ValidateBetSilent(client, amount))
    {
        CF_Print(client, "%t", "CF Accept Not Enough");
        ShowChallengeMenu(client);
        return;
    }

    if (!ValidateBetSilent(challenger, amount))
    {
        CF_Print(client, "%t", "CF Opponent Cannot Pay");
        CF_Print(challenger, "%t", "CF Duel Cancelled Vs", client);
        ClearIncomingChallenge(client, false);
        return;
    }

    if (!US_TakeCredits(challenger, amount))
    {
        CF_Print(client, "%t", "CF Opponent Debit Failed");
        ClearIncomingChallenge(client, false);
        return;
    }

    if (!US_TakeCredits(client, amount))
    {
        US_AddCredits(challenger, amount, false);
        CF_Print(client, "%t", "CF Not Enough Credits");
        ShowChallengeMenu(client);
        return;
    }

    CF_PrintAll("%t", "CF PvP Start Broadcast", challenger, client, amount);
    ClearIncomingChallenge(client, false);
    StartPvpCoinflip(challenger, client, amount);
}

public Action Command_Say(int client, const char[] command, int argc)
{
    if (!IsValidClient(client) || !g_bWaitingBet[client])
    {
        return Plugin_Continue;
    }

    char text[192];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);

    if (StrEqual(text, "cancelar", false) || StrEqual(text, "cancel", false))
    {
        g_bWaitingBet[client] = false;
        if (g_iFlow[client] == Flow_PvP)
        {
            ShowPlayerSelectMenu(client);
        }
        else
        {
            ShowBetMenu(client);
        }
        return Plugin_Handled;
    }

    int bet = ParseBetInput(client, text);
    if (!ValidateBet(client, bet))
    {
        CF_Print(client, "%t", "CF Invalid Bet Input");
        return Plugin_Handled;
    }

    g_bWaitingBet[client] = false;
    g_iPendingBet[client] = bet;

    if (g_iFlow[client] == Flow_PvP)
    {
        if (!IsValidClient(g_iPendingTarget[client]))
        {
            CF_Print(client, "%t", "CF Selected Player Unavailable");
            ShowPlayerSelectMenu(client);
            return Plugin_Handled;
        }
        StartPvPChallenge(client, g_iPendingTarget[client], bet);
    }
    else
    {
        ShowSideMenu(client);
    }

    return Plugin_Handled;
}

void ShowMainMenu(int client)
{
    Menu menu = new Menu(MenuHandler_MainMenu);

    char title[192];
    Format(title, sizeof(title), "%T", "CF Main Menu Title", client, US_GetCredits(client));
    menu.SetTitle(title);

    char houseLabel[64];
    char pvpLabel[64];
    Format(houseLabel, sizeof(houseLabel), "%T", "CF Mode House", client);
    Format(pvpLabel, sizeof(pvpLabel), "%T", "CF Mode PvP", client);
    menu.AddItem("house", houseLabel);
    menu.AddItem("pvp", pvpLabel, gCvarPvpEnabled.BoolValue ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MainMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        if (IsValidClient(client))
        {
            US_OpenCasinoMenu(client);
        }
    }
    else if (action == MenuAction_Select && IsValidClient(client))
    {
        char info[16];
        menu.GetItem(item, info, sizeof(info));
        if (StrEqual(info, "house"))
        {
            g_iFlow[client] = Flow_House;
            g_iPendingTarget[client] = 0;
            ShowBetMenu(client);
        }
        else if (StrEqual(info, "pvp"))
        {
            g_iFlow[client] = Flow_PvP;
            ShowPlayerSelectMenu(client);
        }
    }
    return 0;
}

void ShowPlayerSelectMenu(int client)
{
    Menu menu = new Menu(MenuHandler_PlayerSelect);

    char title[128];
    Format(title, sizeof(title), "%T", "CF Player Select Title", client);
    menu.SetTitle(title);

    bool found = false;
    char uid[16], name[MAX_NAME_LENGTH];
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidClient(i) || i == client)
        {
            continue;
        }
        IntToString(GetClientUserId(i), uid, sizeof(uid));
        GetClientName(i, name, sizeof(name));
        menu.AddItem(uid, name);
        found = true;
    }

    if (!found)
    {
        char emptyLabel[96];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "CF Player Select Empty", client);
        menu.AddItem("none", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_PlayerSelect(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        if (IsValidClient(client))
        {
            ShowMainMenu(client);
        }
    }
    else if (action == MenuAction_Select && IsValidClient(client))
    {
        char info[16];
        menu.GetItem(item, info, sizeof(info));
        int target = GetClientOfUserId(StringToInt(info));
        if (!IsValidClient(target) || target == client)
        {
            CF_Print(client, "%t", "CF Selected Player Unavailable");
            ShowPlayerSelectMenu(client);
            return 0;
        }
        g_iPendingTarget[client] = target;
        g_iFlow[client] = Flow_PvP;
        ShowBetMenu(client);
    }
    return 0;
}

void ShowBetMenu(int client)
{
    Menu menu = new Menu(MenuHandler_BetMenu);
    int credits = US_GetCredits(client);
    char title[256];

    if (g_iFlow[client] == Flow_PvP && IsValidClient(g_iPendingTarget[client]))
    {
        Format(title, sizeof(title), "%T", "CF Bet Menu PvP Title", client, g_iPendingTarget[client], credits);
    }
    else
    {
        Format(title, sizeof(title), "%T", "CF Bet Menu Title", client, credits);
    }

    menu.SetTitle(title);
    AddBetItem(menu, client, 50);
    AddBetItem(menu, client, 100);
    AddBetItem(menu, client, 250);
    AddBetItem(menu, client, 500);
    AddBetItem(menu, client, 1000);
    AddBetItem(menu, client, 2500);
    char allLabel[32];
    char customLabel[64];
    Format(allLabel, sizeof(allLabel), "%T", "CF Bet All", client);
    Format(customLabel, sizeof(customLabel), "%T", "CF Bet Custom", client);
    menu.AddItem("all", allLabel, credits >= gCvarMinBet.IntValue ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    menu.AddItem("custom", customLabel);
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

void AddBetItem(Menu menu, int client, int amount)
{
    char info[16], display[32];
    IntToString(amount, info, sizeof(info));
    Format(display, sizeof(display), "%T", "CF Bet Amount", client, amount);
    menu.AddItem(info, display, ValidateBetSilent(client, amount) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
}

public int MenuHandler_BetMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        if (!IsValidClient(client))
        {
            return 0;
        }
        if (g_iFlow[client] == Flow_PvP)
        {
            ShowPlayerSelectMenu(client);
        }
        else
        {
            ShowMainMenu(client);
        }
    }
    else if (action == MenuAction_Select && IsValidClient(client))
    {
        char info[32];
        menu.GetItem(item, info, sizeof(info));

        if (StrEqual(info, "custom"))
        {
            g_bWaitingBet[client] = true;
            CF_Print(client, "%t", "CF Enter Bet Chat");
            return 0;
        }

        int bet = ParseBetInput(client, info);
        if (!ValidateBet(client, bet))
        {
            return 0;
        }

        g_iPendingBet[client] = bet;
        if (g_iFlow[client] == Flow_PvP)
        {
            if (!IsValidClient(g_iPendingTarget[client]))
            {
                CF_Print(client, "%t", "CF Selected Player Unavailable");
                ShowPlayerSelectMenu(client);
                return 0;
            }
            StartPvPChallenge(client, g_iPendingTarget[client], bet);
        }
        else
        {
            ShowSideMenu(client);
        }
    }
    return 0;
}

void ShowSideMenu(int client)
{
    Menu menu = new Menu(MenuHandler_SideMenu);
    char title[160];
    Format(title, sizeof(title), "%T", "CF Side Menu Title", client, g_iPendingBet[client]);
    menu.SetTitle(title);

    char headsLabel[32];
    char tailsLabel[32];
    Format(headsLabel, sizeof(headsLabel), "%T", "CF Side Heads", client);
    Format(tailsLabel, sizeof(tailsLabel), "%T", "CF Side Tails", client);
    menu.AddItem("0", headsLabel);
    menu.AddItem("1", tailsLabel);
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_SideMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        if (IsValidClient(client))
        {
            ShowBetMenu(client);
        }
    }
    else if (action == MenuAction_Select && IsValidClient(client))
    {
        if (!CanUseCoinflip(client) || !ValidateBet(client, g_iPendingBet[client]))
        {
            return 0;
        }

        char info[8];
        menu.GetItem(item, info, sizeof(info));
        StartHouseCoinflip(client, g_iPendingBet[client], StringToInt(info));
    }
    return 0;
}

void ShowChallengeMenu(int client)
{
    if (!IsValidClient(client) || g_iChallengeFrom[client] == 0)
    {
        return;
    }

    int challenger = g_iChallengeFrom[client];
    int amount = g_iChallengeAmount[client];
    int credits = US_GetCredits(client);
    bool canAccept = ValidateBetSilent(client, amount);

    Menu menu = new Menu(MenuHandler_ChallengeMenu);
    char title[384];
    char status[128];
    Format(status, sizeof(status), "%T", canAccept ? "CF Challenge Status Can Accept" : "CF Challenge Status No Credits", client);
    Format(title, sizeof(title), "%T", "CF Challenge Menu Title", client, challenger, amount, credits, status);
    menu.SetTitle(title);

    char acceptLabel[32];
    char denyLabel[32];
    Format(acceptLabel, sizeof(acceptLabel), "%T", "CF Challenge Accept", client);
    Format(denyLabel, sizeof(denyLabel), "%T", "CF Challenge Deny", client);
    menu.AddItem("accept", acceptLabel, canAccept ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    menu.AddItem("deny", denyLabel);
    menu.ExitButton = false;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ChallengeMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select && IsValidClient(client))
    {
        char info[16];
        menu.GetItem(item, info, sizeof(info));
        HandleChallengeResponse(client, StrEqual(info, "accept"));
    }
    return 0;
}

void StartPvPChallenge(int client, int target, int amount)
{
    if (!gCvarPvpEnabled.BoolValue)
    {
        CF_Print(client, "%t", "CF PvP Disabled");
        return;
    }
    if (target == client)
    {
        CF_Print(client, "%t", "CF Cannot Challenge Self");
        return;
    }
    if (!IsValidClient(target))
    {
        CF_Print(client, "%t", "CF Invalid Target");
        return;
    }
    if (!ValidateBet(client, amount))
    {
        return;
    }
    if (!ValidateBetSilent(target, amount))
    {
        CF_Print(client, "%t", "CF Target Not Enough Credits", target);
        return;
    }
    if (g_bRolling[client] || g_bRolling[target])
    {
        CF_Print(client, "%t", "CF Someone Already Rolling");
        return;
    }
    if (g_iChallengeFrom[target] != 0)
    {
        CF_Print(client, "%t", "CF Target Has Pending Challenge");
        return;
    }
    if (FindChallengeTargetByChallenger(client) > 0)
    {
        CF_Print(client, "%t", "CF You Already Challenged");
        return;
    }

    float now = GetGameTime();
    if (g_fNextChallenge[client] > now)
    {
        CF_Print(client, "%t", "CF Challenge Cooldown", g_fNextChallenge[client] - now);
        return;
    }

    g_fNextChallenge[client] = now + gCvarPvpChallengeCooldown.FloatValue;
    g_iChallengeFrom[target] = client;
    g_iChallengeAmount[target] = amount;
    g_hChallengeTimer[target] = CreateTimer(gCvarPvpTimeout.FloatValue, Timer_ChallengeExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);

    CF_Print(client, "%t", "CF Challenge Sent", target, amount);
    CF_Print(target, "%t", "CF Challenge Received", client, amount);
    ShowChallengeMenu(target);

    g_iFlow[client] = Flow_PvP;
    g_iPendingTarget[client] = target;
    g_iPendingBet[client] = amount;
}

public Action Timer_ChallengeExpire(Handle timer, any userid)
{
    int target = GetClientOfUserId(userid);
    if (target > 0 && g_hChallengeTimer[target] == timer)
    {
        int challenger = g_iChallengeFrom[target];
        if (IsValidClient(target))
        {
            CF_Print(target, "%t", "CF Challenge Expired");
        }
        if (IsValidClient(challenger))
        {
            CF_Print(challenger, "%t", "CF Challenge No Response", target);
        }
        g_hChallengeTimer[target] = null;
        g_iChallengeFrom[target] = 0;
        g_iChallengeAmount[target] = 0;
    }
    return Plugin_Stop;
}

void ClearIncomingChallenge(int target, bool notify)
{
    int challenger = g_iChallengeFrom[target];
    if (g_hChallengeTimer[target] != null)
    {
        KillTimer(g_hChallengeTimer[target]);
        g_hChallengeTimer[target] = null;
    }
    g_iChallengeFrom[target] = 0;
    g_iChallengeAmount[target] = 0;

    if (challenger > 0 && notify)
    {
        if (IsValidClient(target))
        {
            CF_Print(target, "%t", "CF Challenge Cancelled");
        }
        if (IsValidClient(challenger))
        {
            CF_Print(challenger, "%t", "CF Challenge ToTarget Cancelled", target);
        }
    }
}

int FindChallengeTargetByChallenger(int challenger)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_iChallengeFrom[i] == challenger)
        {
            return i;
        }
    }
    return 0;
}

void StartHouseCoinflip(int client, int bet, int choice)
{
    if (!US_TakeCredits(client, bet))
    {
        CF_Print(client, "%t", "CF Not Enough Credits");
        return;
    }

    g_bRolling[client] = true;
    g_iAnimStep[client] = 0;
    g_iAnimChoice[client] = choice;
    g_iAnimBet[client] = bet;
    g_iAnimResult[client] = GetRandomInt(0, 1);
    g_bAnimPvp[client] = false;
    g_iAnimOpponent[client] = 0;
    g_bPvpReady[client] = false;
    g_bPvpResolved[client] = false;

    if (!gCvarAnimEnabled.BoolValue)
    {
        FinishHouseCoinflip(client);
        return;
    }

    ShowRollText(client, 0, false);
    g_hAnimTimer[client] = CreateTimer(gCvarAnimDelay.FloatValue, Timer_HouseAnimation, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void StartPvpCoinflip(int client1, int client2, int amount)
{
    int winner = (GetRandomInt(0, 1) == 0) ? client1 : client2;
    SetupPvpAnim(client1, client2, amount, winner == client1);
    SetupPvpAnim(client2, client1, amount, winner == client2);

    if (!gCvarAnimEnabled.BoolValue)
    {
        FinishPvpCoinflip(client1, client2, winner, (winner == client1) ? client2 : client1, amount);
        return;
    }

    ShowRollText(client1, 0, false);
    ShowRollText(client2, 0, false);
    g_hAnimTimer[client1] = CreateTimer(gCvarAnimDelay.FloatValue, Timer_PvpAnimation, GetClientUserId(client1), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    g_hAnimTimer[client2] = CreateTimer(gCvarAnimDelay.FloatValue, Timer_PvpAnimation, GetClientUserId(client2), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void SetupPvpAnim(int client, int opponent, int amount, bool win)
{
    g_bRolling[client] = true;
    g_iAnimStep[client] = 0;
    g_iAnimBet[client] = amount;
    g_iAnimResult[client] = win ? 1 : 0;
    g_bAnimPvp[client] = true;
    g_iAnimOpponent[client] = opponent;
    g_bPvpReady[client] = false;
    g_bPvpResolved[client] = false;
}

public Action Timer_HouseAnimation(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client) || !g_bRolling[client])
    {
        return Plugin_Stop;
    }

    g_iAnimStep[client]++;
    if (g_iAnimStep[client] >= gCvarAnimSteps.IntValue)
    {
        g_hAnimTimer[client] = null;
        FinishHouseCoinflip(client);
        return Plugin_Stop;
    }
    ShowRollText(client, g_iAnimStep[client], false);
    return Plugin_Continue;
}

public Action Timer_PvpAnimation(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client) || !g_bRolling[client])
    {
        return Plugin_Stop;
    }

    g_iAnimStep[client]++;
    if (g_iAnimStep[client] < gCvarAnimSteps.IntValue)
    {
        ShowRollText(client, g_iAnimStep[client], false);
        return Plugin_Continue;
    }

    g_hAnimTimer[client] = null;
    g_bPvpReady[client] = true;

    int opponent = g_iAnimOpponent[client];

    if (!IsValidClient(opponent) || !g_bRolling[opponent])
    {
        ResolvePvpDisconnect(client);
        ResetAnimState(client);
        return Plugin_Stop;
    }

    /* wait until both finished, then only one side resolves */
    if (!g_bPvpReady[opponent])
    {
        return Plugin_Stop;
    }

    if (g_bPvpResolved[client] || g_bPvpResolved[opponent])
    {
        return Plugin_Stop;
    }

    g_bPvpResolved[client] = true;
    g_bPvpResolved[opponent] = true;

    int winner = (g_iAnimResult[client] == 1) ? client : opponent;
    int loser = (winner == client) ? opponent : client;
    FinishPvpCoinflip(client, opponent, winner, loser, g_iAnimBet[client]);
    return Plugin_Stop;
}

void FinishHouseCoinflip(int client)
{
    bool win = (g_iAnimChoice[client] == g_iAnimResult[client]);
    int bet = g_iAnimBet[client];
    ShowRollText(client, g_iAnimStep[client], true);

    char chosen[16], rolled[16];
    Format(chosen, sizeof(chosen), "%T", (g_iAnimChoice[client] == 0) ? "CF Side Heads" : "CF Side Tails", client);
    Format(rolled, sizeof(rolled), "%T", (g_iAnimResult[client] == 0) ? "CF Side Heads" : "CF Side Tails", client);

    if (win)
    {
        int reward = RoundToFloor(float(bet) * gCvarWinMultiplier.FloatValue);
        if (reward < 1)
        {
            reward = 1;
        }

        US_AddCredits(client, reward, false);
        TrackCoinflipResult(client, reward - bet, true);
        EmitConfiguredSound(client, gCvarWinSound);
        CF_Print(client, "%t", "CF House Win", chosen, rolled, reward - bet);

        if (gCvarAnnounceBig.BoolValue && bet >= gCvarAnnounceThreshold.IntValue)
        {
            CF_PrintAll("%t", "CF Big Win Broadcast", client, reward - bet);
        }
    }
    else
    {
        TrackCoinflipResult(client, -bet, false);
        EmitConfiguredSound(client, gCvarLoseSound);
        CF_Print(client, "%t", "CF House Lose", chosen, rolled, bet);
    }

    g_fNextUse[client] = GetGameTime() + gCvarCooldown.FloatValue;
    ResetAnimState(client);
}

void FinishPvpCoinflip(int clientA, int clientB, int winner, int loser, int amount)
{
    if (!IsValidClient(winner) || !IsValidClient(loser))
    {
        if (IsValidClient(clientA))
        {
            ResetAnimState(clientA);
        }
        if (IsValidClient(clientB) && clientB != clientA)
        {
            ResetAnimState(clientB);
        }
        return;
    }

    ShowRollText(clientA, g_iAnimStep[clientA], true);
    if (clientB != clientA)
    {
        ShowRollText(clientB, g_iAnimStep[clientB], true);
    }

    US_AddCredits(winner, amount * 2, false);
    TrackCoinflipResult(winner, amount, true);
    TrackCoinflipResult(loser, -amount, false);
    EmitConfiguredSound(winner, gCvarWinSound);
    EmitConfiguredSound(loser, gCvarLoseSound);
    CF_PrintAll("%t", "CF PvP Winner Broadcast", winner, loser, amount * 2);
    g_fNextUse[winner] = GetGameTime() + gCvarCooldown.FloatValue;
    g_fNextUse[loser] = GetGameTime() + gCvarCooldown.FloatValue;
    ResetAnimState(winner);
    ResetAnimState(loser);
}

void ShowRollText(int client, int step, bool finalFrame)
{
    char buffer[256];

    if (!g_bAnimPvp[client])
    {
        char chosen[16], alt[16], current[16];
        Format(chosen, sizeof(chosen), "%T", (g_iAnimChoice[client] == 0) ? "CF Side Heads" : "CF Side Tails", client);
        Format(alt, sizeof(alt), "%T", (g_iAnimChoice[client] == 0) ? "CF Side Tails" : "CF Side Heads", client);
        if (finalFrame)
        {
            Format(current, sizeof(current), "%T", (g_iAnimResult[client] == 0) ? "CF Side Heads" : "CF Side Tails", client);
        }
        else
        {
            strcopy(current, sizeof(current), (step % 2 == 0) ? chosen : alt);
        }

        if (finalFrame)
        {
            Format(buffer, sizeof(buffer), "%T", "CF HUD House Final", client, g_iAnimBet[client], chosen, current);
        }
        else
        {
            Format(buffer, sizeof(buffer), "%T", "CF HUD House Rolling", client, g_iAnimBet[client], chosen, current);
        }
    }
    else
    {
        static const char spinner[4][8] = { "|", "/", "-", "\\" };
        if (finalFrame)
        {
            char resultText[32];
            Format(resultText, sizeof(resultText), "%T", (g_iAnimResult[client] == 1) ? "CF Result Win" : "CF Result Lose", client);
            Format(buffer, sizeof(buffer), "%T", "CF HUD PvP Final", client, g_iAnimOpponent[client], g_iAnimBet[client], resultText);
        }
        else
        {
            Format(buffer, sizeof(buffer), "%T", "CF HUD PvP Rolling", client, g_iAnimOpponent[client], g_iAnimBet[client], spinner[step % 4]);
        }
    }

    if (gCvarAnimMode.IntValue == 2)
    {
        PrintHintText(client, "%s", buffer);
    }
    else
    {
        PrintCenterText(client, "%s", buffer);
    }
}

void EmitConfiguredSound(int client, ConVar cvar)
{
    char sound[PLATFORM_MAX_PATH];
    cvar.GetString(sound, sizeof(sound));
    TrimString(sound);

    if (sound[0] != '\0')
    {
        EmitSoundToClient(client, sound);
    }
}

void PrecacheConfiguredSound(ConVar cvar)
{
    char sound[PLATFORM_MAX_PATH];
    cvar.GetString(sound, sizeof(sound));
    TrimString(sound);
    if (sound[0] != '\0')
    {
        PrecacheSound(sound, true);
    }
}

int ParseBetInput(int client, const char[] input)
{
    if (StrEqual(input, "all", false) || StrEqual(input, "todo", false))
    {
        return US_GetCredits(client);
    }

    int len = strlen(input);
    if (len <= 0)
    {
        return 0;
    }

    for (int i = 0; i < len; i++)
    {
        if (input[i] < '0' || input[i] > '9')
        {
            return 0;
        }
    }

    return StringToInt(input);
}

bool CanUseCoinflip(int client)
{
    if (!IsValidClient(client))
    {
        return false;
    }
    if (!gCvarEnabled.BoolValue)
    {
        CF_Print(client, "%t", "CF Disabled");
        return false;
    }
    if (g_bRolling[client])
    {
        CF_Print(client, "%t", "CF Already Rolling");
        return false;
    }
    if (g_fNextUse[client] > GetGameTime())
    {
        CF_Print(client, "%t", "CF Cooldown");
        return false;
    }
    return true;
}

bool ValidateBet(int client, int bet)
{
    if (bet <= 0)
    {
        CF_Print(client, "%t", "CF Bet Invalid");
        return false;
    }
    if (bet < gCvarMinBet.IntValue)
    {
        CF_Print(client, "%t", "CF Bet Min", gCvarMinBet.IntValue);
        return false;
    }
    if (gCvarMaxBet.IntValue > 0 && bet > gCvarMaxBet.IntValue)
    {
        CF_Print(client, "%t", "CF Bet Max", gCvarMaxBet.IntValue);
        return false;
    }
    if (US_GetCredits(client) < bet)
    {
        CF_Print(client, "%t", "CF Not Enough Credits");
        return false;
    }
    return true;
}

bool ValidateBetSilent(int client, int bet)
{
    if (!IsValidClient(client) || bet <= 0 || bet < gCvarMinBet.IntValue)
    {
        return false;
    }
    if (gCvarMaxBet.IntValue > 0 && bet > gCvarMaxBet.IntValue)
    {
        return false;
    }
    return US_GetCredits(client) >= bet;
}

void CF_Print(int client, const char[] format, any ...)
{
    if (!IsValidClient(client))
    {
        return;
    }

    char buffer[256], highlighted[320];
    SetGlobalTransTarget(client);
    VFormat(buffer, sizeof(buffer), format, 3);
    HighlightChatCommands(buffer, highlighted, sizeof(highlighted));
    CPrintToChat(client, "%s %s", US_CHAT_TAG, highlighted);
}

void CF_PrintAll(const char[] format, any ...)
{
    char buffer[256], highlighted[320];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidClient(client))
        {
            continue;
        }

        SetGlobalTransTarget(client);
        VFormat(buffer, sizeof(buffer), format, 2);
        HighlightChatCommands(buffer, highlighted, sizeof(highlighted));
        CPrintToChat(client, "%s %s", US_CHAT_TAG, highlighted);
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

void ResetAnimState(int client)
{
    g_bRolling[client] = false;
    g_iAnimStep[client] = 0;
    g_iAnimChoice[client] = 0;
    g_iAnimBet[client] = 0;
    g_iAnimResult[client] = 0;
    g_bAnimPvp[client] = false;
    g_iAnimOpponent[client] = 0;
    g_bPvpReady[client] = false;
    g_bPvpResolved[client] = false;
}

bool IsValidClient(int client)
{
    return (client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

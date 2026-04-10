#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <umbrella_store>

#define BJ_MAX_HAND_CARDS 12
#define BJ_MAX_HISTORY 8
#define BJ_MENU_TIME 30
#define BJ_CASINO_ID "blackjack"

#define BJ_SOUND_BET "buttons/button14.wav"
#define BJ_SOUND_WIN "ui/pickup_secret01.wav"
#define BJ_SOUND_LOSE "buttons/button11.wav"
#define BJ_SOUND_PUSH "buttons/blip1.wav"
#define BJ_SOUND_CARD "buttons/button17.wav"
#define BJ_CHAT_TAG " \x03[Blackjack]\x01"

#define BJ_PVP_INVITE_TIMEOUT 20.0
#define BJ_TABLE_MAX_PLAYERS 4
#define BJ_TABLE_MIN_PLAYERS 2
#define BJ_TABLE_START_DELAY 5.0
#define BJ_TABLE_TURN_TIME 12.0

enum BlackjackMode
{
    BJMODE_NONE = 0,
    BJMODE_SINGLE,
    BJMODE_PVP,
    BJMODE_TABLE
};

BlackjackMode g_iMode[MAXPLAYERS + 1];

char g_sResultHistory[MAXPLAYERS + 1][BJ_MAX_HISTORY][192];
int g_iHistoryCount[MAXPLAYERS + 1];

int g_iStatGames[MAXPLAYERS + 1];
int g_iStatWins[MAXPLAYERS + 1];
int g_iStatLosses[MAXPLAYERS + 1];
int g_iStatPushes[MAXPLAYERS + 1];
int g_iStatBlackjacks[MAXPLAYERS + 1];
int g_iStatProfit[MAXPLAYERS + 1];
int g_iWinStreak[MAXPLAYERS + 1];
int g_iBestWinStreak[MAXPLAYERS + 1];

bool g_bRoundFinished[MAXPLAYERS + 1];
bool g_bCanDouble[MAXPLAYERS + 1];
bool g_bUsedDouble[MAXPLAYERS + 1];
bool g_bCanSplit[MAXPLAYERS + 1];
bool g_bHasSplit[MAXPLAYERS + 1];
bool g_bPlayingSplitHand[MAXPLAYERS + 1];
bool g_bSplitHandDone[MAXPLAYERS + 1];
int g_iBet[MAXPLAYERS + 1];
int g_iDealerCards[MAXPLAYERS + 1][BJ_MAX_HAND_CARDS];
int g_iPlayerCards[MAXPLAYERS + 1][2][BJ_MAX_HAND_CARDS];
int g_iDealerCount[MAXPLAYERS + 1];
int g_iPlayerCount[MAXPLAYERS + 1][2];
float g_fNextOpenCmd[MAXPLAYERS + 1];
float g_fNextAction[MAXPLAYERS + 1];

int g_iPvPOpponent[MAXPLAYERS + 1];
int g_iPvPBet[MAXPLAYERS + 1];
int g_iPvPCards[MAXPLAYERS + 1][BJ_MAX_HAND_CARDS];
int g_iPvPCount[MAXPLAYERS + 1];
bool g_bPvPStood[MAXPLAYERS + 1];
bool g_bPvPRevealed[MAXPLAYERS + 1];
int g_iPvPCurrentTurn[MAXPLAYERS + 1];

int g_iPvPInviteFrom[MAXPLAYERS + 1];
int g_iPvPInviteBet[MAXPLAYERS + 1];
Handle g_hPvPInviteTimer[MAXPLAYERS + 1];
Handle g_hPvPTurnTimer[MAXPLAYERS + 1];
int g_iPvPMenuTarget[MAXPLAYERS + 1];
bool g_bPvPAwaitingCustomBet[MAXPLAYERS + 1];

enum BlackjackTableState
{
    BJTABLE_IDLE = 0,
    BJTABLE_WAITING,
    BJTABLE_PLAYING,
    BJTABLE_RESOLVING
};

BlackjackTableState g_iTableState = BJTABLE_IDLE;
bool g_bTableSeated[MAXPLAYERS + 1];
bool g_bTableStood[MAXPLAYERS + 1];
bool g_bTableBusted[MAXPLAYERS + 1];
bool g_bTableStakeTaken[MAXPLAYERS + 1];
int g_iTableBet[MAXPLAYERS + 1];
int g_iTableCards[MAXPLAYERS + 1][BJ_MAX_HAND_CARDS];
int g_iTableCount[MAXPLAYERS + 1];
int g_iTableDealerCards[BJ_MAX_HAND_CARDS];
int g_iTableDealerCount = 0;
int g_iTableOrder[BJ_TABLE_MAX_PLAYERS];
int g_iTableSeatCount = 0;
int g_iTableCurrentTurn = -1;
Handle g_hTableStartTimer = null;
Handle g_hTableTurnTimer = null;

ConVar gCvarMinBet;
ConVar gCvarMaxBet;
ConVar gCvarBlackjackPayNum;
ConVar gCvarBlackjackPayDen;
ConVar gCvarDealerHitSoft17;
ConVar gCvarActionCooldown;
ConVar gCvarCommandCooldown;
ConVar gCvarEnableSounds;
ConVar gCvarPvPEnabled;
ConVar gCvarPvPInviteTimeout;
ConVar gCvarPvPTurnTimeout;
ConVar gCvarBigWinAnnounce;
ConVar gCvarBigWinMinNet;
ConVar gCvarAnnounceNaturalBlackjack;
ConVar gCvarAnnounceStreaks;

public Plugin myinfo =
{
    name = "[Umbrella Store] Blackjack",
    author = "Ayrton09",
    description = "Blackjack module for Umbrella Store",
    version = "1.0.0",
    url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
    RegPluginLibrary("umbrella_store_blackjack");
    return APLRes_Success;
}

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    LoadTranslations("umbrella_store_blackjack.phrases");

    gCvarMinBet = CreateConVar("umbrella_store_blackjack_min_bet", "100", "Minimum blackjack bet.", _, true, 1.0);
    gCvarMaxBet = CreateConVar("umbrella_store_blackjack_max_bet", "1000000", "Maximum blackjack bet.", _, true, 1.0);
    gCvarBlackjackPayNum = CreateConVar("umbrella_store_blackjack_blackjack_pay_num", "3", "Numerator for natural blackjack payout.", _, true, 1.0);
    gCvarBlackjackPayDen = CreateConVar("umbrella_store_blackjack_blackjack_pay_den", "2", "Denominator for natural blackjack payout.", _, true, 1.0);
    gCvarDealerHitSoft17 = CreateConVar("umbrella_store_blackjack_dealer_hit_soft17", "0", "If 1, dealer hits on soft 17.", _, true, 0.0, true, 1.0);
    gCvarActionCooldown = CreateConVar("umbrella_store_blackjack_action_cooldown", "0.35", "Cooldown between menu actions.", _, true, 0.0);
    gCvarCommandCooldown = CreateConVar("umbrella_store_blackjack_command_cooldown", "0.75", "Cooldown between blackjack open commands.", _, true, 0.0);
    gCvarEnableSounds = CreateConVar("umbrella_store_blackjack_sounds", "1", "Enable blackjack sounds.", _, true, 0.0, true, 1.0);
    gCvarPvPEnabled = CreateConVar("umbrella_store_blackjack_pvp_enabled", "1", "Enable player-vs-player mode.", _, true, 0.0, true, 1.0);
    gCvarPvPInviteTimeout = CreateConVar("umbrella_store_blackjack_pvp_invite_timeout", "20.0", "Time to accept a PvP challenge.", _, true, 5.0, true, 60.0);
    gCvarPvPTurnTimeout = CreateConVar("umbrella_store_blackjack_pvp_turn_timeout", "15.0", "Maximum time per PvP turn before auto-stand.", _, true, 5.0, true, 45.0);
    gCvarBigWinAnnounce = CreateConVar("umbrella_store_blackjack_bigwin_announce", "1", "Announce big wins globally.", _, true, 0.0, true, 1.0);
    gCvarBigWinMinNet = CreateConVar("umbrella_store_blackjack_bigwin_min_net", "15000", "Minimum net profit required for global announcement.", _, true, 0.0);
    gCvarAnnounceNaturalBlackjack = CreateConVar("umbrella_store_blackjack_announce_natural", "1", "Announce natural blackjacks globally.", _, true, 0.0, true, 1.0);
    gCvarAnnounceStreaks = CreateConVar("umbrella_store_blackjack_announce_streaks", "1", "Announce notable win streaks globally.", _, true, 0.0, true, 1.0);

    AutoExecConfig(true, "umbrella_store_blackjack");

    RegConsoleCmd("sm_blackjack", Cmd_Blackjack);
    RegConsoleCmd("sm_bj", Cmd_Blackjack);
    AddCommandListener(CommandListener_Say, "say");
    AddCommandListener(CommandListener_Say, "say_team");

    for (int i = 1; i <= MaxClients; i++)
    {
        ResetBlackjackClient(i, true);
    }
}

public void OnMapStart()
{
    PrecacheSound(BJ_SOUND_BET, true);
    PrecacheSound(BJ_SOUND_WIN, true);
    PrecacheSound(BJ_SOUND_LOSE, true);
    PrecacheSound(BJ_SOUND_PUSH, true);
    PrecacheSound(BJ_SOUND_CARD, true);
}

public void OnAllPluginsLoaded()
{
    TryRegisterCasinoEntry();
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "umbrella_store"))
    {
        TryRegisterCasinoEntry();
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "umbrella_store"))
    {
        // The core library is unloading; its casino registry is destroyed there.
        // Avoid native calls during teardown to prevent dependency-order errors.
    }
}

public void OnPluginEnd()
{
    if (LibraryExists("umbrella_store"))
    {
        US_Casino_Unregister(BJ_CASINO_ID);
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        ClearInvite(i);
    }
}

public void OnClientDisconnect(int client)
{
    HandleClientLeave(client);
}

void TryRegisterCasinoEntry()
{
    if (!LibraryExists("umbrella_store"))
    {
        return;
    }

    char title[64];
    Format(title, sizeof(title), "%T", "Blackjack Title", LANG_SERVER);
    US_Casino_Register(BJ_CASINO_ID, title, "sm_bj");
}

public Action CommandListener_Say(int client, const char[] command, int argc)
{
    if (!IsValidClient(client))
    {
        return Plugin_Continue;
    }

    char text[192];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);

    if (StrEqual(text, "!bj", false) || StrEqual(text, "/bj", false) || StrEqual(text, "!blackjack", false) || StrEqual(text, "/blackjack", false))
    {
        g_bPvPAwaitingCustomBet[client] = false;
        OpenBlackjackMenu(client);
        return Plugin_Handled;
    }

    if (g_bPvPAwaitingCustomBet[client])
    {
        if (text[0] == '!' || text[0] == '/')
        {
            if (StrEqual(text, "!cancel", false) || StrEqual(text, "/cancel", false))
            {
                g_bPvPAwaitingCustomBet[client] = false;
                ChatInfo(client, "%T", "PvP Custom Bet Cancelled", client);
                ShowPvPBetMenu(client);
                return Plugin_Handled;
            }
            return Plugin_Continue;
        }

        if (StrEqual(text, "cancel", false) || StrEqual(text, "cancelar", false) || StrEqual(text, "0"))
        {
            g_bPvPAwaitingCustomBet[client] = false;
            ChatInfo(client, "%T", "PvP Custom Bet Cancelled", client);
            ShowPvPBetMenu(client);
            return Plugin_Handled;
        }

        int bet = 0;
        if (!TryParseBetInput(text, bet))
        {
            ChatError(client, "%T", "PvP Custom Bet Invalid", client);
            return Plugin_Handled;
        }

        g_bPvPAwaitingCustomBet[client] = false;
        int target = g_iPvPMenuTarget[client];
        TryCreatePvPInviteTarget(client, target, bet);
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

bool TryParseBetInput(const char[] input, int &bet)
{
    char digits[32];
    int out = 0;
    int len = strlen(input);

    for (int i = 0; i < len; i++)
    {
        int c = input[i];
        if (c >= '0' && c <= '9')
        {
            if (out >= sizeof(digits) - 1)
            {
                return false;
            }
            digits[out++] = c;
            continue;
        }

        if (c == ' ' || c == '.' || c == ',' || c == '_')
        {
            continue;
        }

        return false;
    }

    if (out == 0)
    {
        return false;
    }

    digits[out] = '\0';
    bet = StringToInt(digits);
    return (bet > 0);
}

void OpenBlackjackMenu(int client)
{
    if (!IsValidClient(client))
    {
        return;
    }

    if (!LibraryExists("umbrella_store"))
    {
        Chat(client, "%T", "Error Missing Core", client);
        return;
    }

    if (!US_IsLoaded(client))
    {
        Chat(client, "%T", "Error Store Not Loaded", client);
        return;
    }

    if (!CheckOpenCooldown(client))
    {
        return;
    }

    if (g_iMode[client] == BJMODE_SINGLE && !g_bRoundFinished[client])
    {
        ShowSingleGameMenu(client);
    }
    else if (g_iMode[client] == BJMODE_PVP)
    {
        ShowPvPMenu(client);
    }
    else if (g_iMode[client] == BJMODE_TABLE)
    {
        ShowTableMenu(client);
    }
    else
    {
        ShowMainMenu(client);
    }
}


void OpenBlackjackMenuNoCooldown(int client)
{
    if (!IsValidClient(client))
    {
        return;
    }

    if (!LibraryExists("umbrella_store"))
    {
        Chat(client, "%T", "Error Missing Core", client);
        return;
    }

    if (!US_IsLoaded(client))
    {
        Chat(client, "%T", "Error Store Not Loaded", client);
        return;
    }

    if (g_iMode[client] == BJMODE_SINGLE && !g_bRoundFinished[client])
    {
        ShowSingleGameMenu(client);
    }
    else if (g_iMode[client] == BJMODE_PVP)
    {
        ShowPvPMenu(client);
    }
    else if (g_iMode[client] == BJMODE_TABLE)
    {
        ShowTableMenu(client);
    }
    else
    {
        ShowMainMenu(client);
    }
}

public Action Cmd_Blackjack(int client, int args)
{
    if (!IsValidClient(client))
    {
        return Plugin_Handled;
    }

    if (!LibraryExists("umbrella_store"))
    {
        Chat(client, "%T", "Error Missing Core", client);
        return Plugin_Handled;
    }

    if (!US_IsLoaded(client))
    {
        Chat(client, "%T", "Error Store Not Loaded", client);
        return Plugin_Handled;
    }

    if (args < 1)
    {
        OpenBlackjackMenuNoCooldown(client);
        return Plugin_Handled;
    }

    if (!CheckOpenCooldown(client))
    {
        return Plugin_Handled;
    }

    if (args >= 1)
    {
        char arg1[64];
        GetCmdArg(1, arg1, sizeof(arg1));

        if (StrEqual(arg1, "table", false) || StrEqual(arg1, "mesa", false))
        {
            ShowTableMenu(client);
            return Plugin_Handled;
        }

        if (StrEqual(arg1, "join", false) || StrEqual(arg1, "unirme", false))
        {
            if (args < 2)
            {
                ChatInfo(client, "%T", "Table Join Usage", client);
                return Plugin_Handled;
            }

            char betArg[32];
            GetCmdArg(2, betArg, sizeof(betArg));
            TableJoin(client, StringToInt(betArg));
            return Plugin_Handled;
        }

        if (StrEqual(arg1, "leave", false) || StrEqual(arg1, "salir", false))
        {
            TableLeave(client, true);
            return Plugin_Handled;
        }

        if (StrEqual(arg1, "start", false) || StrEqual(arg1, "iniciar", false))
        {
            TableForceStart(client);
            return Plugin_Handled;
        }

        if (StrEqual(arg1, "history", false) || StrEqual(arg1, "historial", false))
        {
            ShowHistoryMenu(client);
            return Plugin_Handled;
        }

        if (StrEqual(arg1, "stats", false) || StrEqual(arg1, "estadisticas", false) || StrEqual(arg1, "racha", false))
        {
            ShowStatsMenu(client);
            return Plugin_Handled;
        }

        if (StrEqual(arg1, "accept", false) || StrEqual(arg1, "aceptar", false))
        {
            AcceptPvPInvite(client);
            return Plugin_Handled;
        }

        if (StrEqual(arg1, "decline", false) || StrEqual(arg1, "rechazar", false))
        {
            DeclinePvPInvite(client);
            return Plugin_Handled;
        }

        if (StrEqual(arg1, "pvp", false) || StrEqual(arg1, "duel", false) || StrEqual(arg1, "reto", false))
        {
            ChatInfo(client, "%T", "PvP Menu Only", client);
            OpenBlackjackMenuNoCooldown(client);
            return Plugin_Handled;
        }

        StartBlackjackRound(client, StringToInt(arg1));
        return Plugin_Handled;
    }

    OpenBlackjackMenu(client);
    return Plugin_Handled;
}

void ResetBlackjackClient(int client, bool fullReset)
{
    ClearPvPTurnTimer(client);
    g_iMode[client] = BJMODE_NONE;
    g_bRoundFinished[client] = false;
    g_bCanDouble[client] = false;
    g_bUsedDouble[client] = false;
    g_bCanSplit[client] = false;
    g_bHasSplit[client] = false;
    g_bPlayingSplitHand[client] = false;
    g_bSplitHandDone[client] = false;
    g_iBet[client] = 0;
    g_iDealerCount[client] = 0;
    g_fNextAction[client] = 0.0;

    if (fullReset)
    {
        g_fNextOpenCmd[client] = 0.0;
    }

    for (int hand = 0; hand < 2; hand++)
    {
        g_iPlayerCount[client][hand] = 0;
        for (int i = 0; i < BJ_MAX_HAND_CARDS; i++)
        {
            g_iPlayerCards[client][hand][i] = 0;
        }
    }

    for (int i = 0; i < BJ_MAX_HAND_CARDS; i++)
    {
        g_iDealerCards[client][i] = 0;
        g_iPvPCards[client][i] = 0;
    }

    g_iPvPOpponent[client] = 0;
    g_iPvPBet[client] = 0;
    g_iPvPCount[client] = 0;
    g_bPvPStood[client] = false;
    g_bPvPRevealed[client] = false;
    g_iPvPCurrentTurn[client] = 0;
    g_iPvPMenuTarget[client] = 0;
    g_bPvPAwaitingCustomBet[client] = false;
}

void HandleClientLeave(int client)
{
    int from = g_iPvPInviteFrom[client];
    if (from > 0 && from <= MaxClients)
    {
        Chat(from, "%T", "PvP Invite Cancelled Left", from, client);
    }
    ClearInvite(client);

    if (g_iMode[client] == BJMODE_TABLE)
    {
        TableClientDisconnected(client);
    }

    if (g_iMode[client] == BJMODE_PVP)
    {
        int opponent = g_iPvPOpponent[client];
        int refund = g_iPvPBet[client];

        if (IsValidClient(opponent) && g_iMode[opponent] == BJMODE_PVP && g_iPvPOpponent[opponent] == client)
        {
            int reward = refund * 2;
            if (reward > 0)
            {
                US_AddCredits(opponent, reward, true);
            }

            Chat(opponent, "%T", "PvP Opponent Left", opponent, client);
            { char hist[192]; Format(hist, sizeof(hist), "%T", "History PvP Opponent Left", opponent, client); AddHistory(opponent, "%s", hist); }
            PlayClientSound(opponent, BJ_SOUND_WIN);
            ResetBlackjackClient(opponent, false);
            ShowMainMenu(opponent);
        }
    }

    ResetBlackjackClient(client, true);
}

void ShowMainMenu(int client)
{
    Menu menu = new Menu(MenuHandler_MainMenu);

    int creditsValue = US_GetCredits(client);
    int minBetValue = gCvarMinBet.IntValue;
    int maxBetValue = gCvarMaxBet.IntValue;

    char credits[32], title[384];
    FormatCredits(creditsValue, credits, sizeof(credits));

    Format(title, sizeof(title), "%T", "Main Menu Title", client, credits, g_iWinStreak[client]);
    menu.SetTitle(title);

    { char text[128]; GetPhrase(client, "Menu Section Quick Bets", text, sizeof(text)); menu.AddItem("section_quick", text, ITEMDRAW_DISABLED); }

    int addedQuickBets = 0;
    int usedQuickBets[6];
    for (int i = 0; i < sizeof(usedQuickBets); i++)
    {
        usedQuickBets[i] = -1;
    }

    AddQuickBetOption(menu, client, minBetValue, "Menu Quick Bet Min", usedQuickBets, sizeof(usedQuickBets), addedQuickBets);
    AddQuickBetOption(menu, client, creditsValue / 4, "Menu Quick Bet Low", usedQuickBets, sizeof(usedQuickBets), addedQuickBets);
    AddQuickBetOption(menu, client, creditsValue / 2, "Menu Quick Bet Medium", usedQuickBets, sizeof(usedQuickBets), addedQuickBets);
    int highBet = (creditsValue < maxBetValue) ? creditsValue : maxBetValue;
    AddQuickBetOption(menu, client, highBet, "Menu Quick Bet High", usedQuickBets, sizeof(usedQuickBets), addedQuickBets);
    AddQuickBetOption(menu, client, creditsValue, "Menu Quick Bet AllIn", usedQuickBets, sizeof(usedQuickBets), addedQuickBets);

    if (addedQuickBets == 0)
    {
        { char text[128]; GetPhrase(client, "Menu Quick Bet Unavailable", text, sizeof(text)); menu.AddItem("quick_unavailable", text, ITEMDRAW_DISABLED); }
    }

    { char text[128]; GetPhrase(client, "Menu Section Modes", text, sizeof(text)); menu.AddItem("section_modes", text, ITEMDRAW_DISABLED); }
    { char text2[128]; GetPhrase(client, "Menu Table", text2, sizeof(text2)); menu.AddItem("table", text2); }

    if (gCvarPvPEnabled.BoolValue)
    {
        { char text[128]; GetPhrase(client, "Menu PvP Challenge", text, sizeof(text)); menu.AddItem("pvp_challenge", text); }
        { char text[128]; GetPhrase(client, "Menu PvP Help", text, sizeof(text)); menu.AddItem("pvp_help", text); }
    }
    else
    {
        { char text[128]; GetPhrase(client, "Menu PvP Disabled", text, sizeof(text)); menu.AddItem("pvp_disabled", text, ITEMDRAW_DISABLED); }
    }

    { char text[128]; GetPhrase(client, "Menu Section Utilities", text, sizeof(text)); menu.AddItem("section_utils", text, ITEMDRAW_DISABLED); }
    { char text[128]; GetPhrase(client, "Menu History", text, sizeof(text)); menu.AddItem("history", text); }
    { char text[128]; GetPhrase(client, "Menu Stats", text, sizeof(text)); menu.AddItem("stats", text); }

    menu.ExitBackButton = true;
    menu.Display(client, BJ_MENU_TIME);
}

void AddQuickBetOption(Menu menu, int client, int betCandidate, const char[] phraseKey, int[] usedBets, int maxUsed, int &usedCount)
{
    int minBet = gCvarMinBet.IntValue;
    int maxBet = gCvarMaxBet.IntValue;
    int credits = US_GetCredits(client);

    int bet = betCandidate;
    if (bet < minBet)
    {
        bet = minBet;
    }
    if (bet > maxBet)
    {
        bet = maxBet;
    }
    if (bet > credits)
    {
        bet = credits;
    }
    if (bet < minBet)
    {
        return;
    }

    for (int i = 0; i < usedCount; i++)
    {
        if (usedBets[i] == bet)
        {
            return;
        }
    }

    char label[128], amount[32], info[16];
    FormatCredits(bet, amount, sizeof(amount));
    Format(label, sizeof(label), "%T", phraseKey, client, amount);
    IntToString(bet, info, sizeof(info));
    menu.AddItem(info, label);

    if (usedCount < maxUsed)
    {
        usedBets[usedCount++] = bet;
    }
}

public int MenuHandler_MainMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        if (LibraryExists("umbrella_store"))
        {
            US_OpenCasinoMenu(client);
        }
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(item, info, sizeof(info));

        if (StrEqual(info, "table"))
        {
            ShowTableMenu(client);
            return 0;
        }

        if (StrEqual(info, "pvp_challenge"))
        {
            ShowPvPPlayerMenu(client);
            return 0;
        }

        if (StrEqual(info, "pvp_help"))
        {
            ShowPvPHelpMenu(client);
            return 0;
        }

        if (StrEqual(info, "history"))
        {
            ShowHistoryMenu(client);
            return 0;
        }

        if (StrEqual(info, "stats"))
        {
            ShowStatsMenu(client);
            return 0;
        }

        StartBlackjackRound(client, StringToInt(info));
    }

    return 0;
}

void ShowPvPHelpMenu(int client)
{
    Menu menu = new Menu(MenuHandler_PvPHelp);
    { char text[128]; GetPhrase(client, "PvP Help Title", text, sizeof(text)); menu.SetTitle(text); }
    { char text[128]; GetPhrase(client, "PvP Help Line 1", text, sizeof(text)); menu.AddItem("a", text, ITEMDRAW_DISABLED); }
    { char text[128]; GetPhrase(client, "PvP Help Line 2", text, sizeof(text)); menu.AddItem("b", text, ITEMDRAW_DISABLED); }
    { char text[128]; GetPhrase(client, "PvP Help Line 3", text, sizeof(text)); menu.AddItem("c", text, ITEMDRAW_DISABLED); }
    { char text[128]; GetPhrase(client, "PvP Help Line 4", text, sizeof(text)); menu.AddItem("d", text, ITEMDRAW_DISABLED); }
    menu.ExitBackButton = true;
    menu.Display(client, BJ_MENU_TIME);
}

public int MenuHandler_PvPHelp(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        ShowMainMenu(client);
    }
    return 0;
}

void ShowPvPPlayerMenu(int client)
{
    if (!gCvarPvPEnabled.BoolValue)
    {
        Chat(client, "%T", "PvP Disabled", client);
        ShowMainMenu(client);
        return;
    }

    if (g_iMode[client] != BJMODE_NONE)
    {
        Chat(client, "%T", "Already In Game", client);
        OpenBlackjackMenuNoCooldown(client);
        return;
    }

    Menu menu = new Menu(MenuHandler_PvPPlayerMenu);

    char title[256];
    Format(title, sizeof(title), "%T", "PvP Player Menu Title", client);
    menu.SetTitle(title);

    int available = 0;
    for (int target = 1; target <= MaxClients; target++)
    {
        if (target == client || !IsValidClient(target))
        {
            continue;
        }

        if (!US_IsLoaded(target) || g_iMode[target] != BJMODE_NONE || g_iPvPInviteFrom[target] != 0)
        {
            continue;
        }

        char info[16], label[128], creditsText[32];
        IntToString(GetClientUserId(target), info, sizeof(info));
        FormatCredits(US_GetCredits(target), creditsText, sizeof(creditsText));
        Format(label, sizeof(label), "%T", "PvP Player Menu Entry", client, target, creditsText);
        menu.AddItem(info, label);
        available++;
    }

    if (available == 0)
    {
        char text[128];
        GetPhrase(client, "PvP Player Menu Empty", text, sizeof(text));
        menu.AddItem("none", text, ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, BJ_MENU_TIME);
}

public int MenuHandler_PvPPlayerMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        ShowMainMenu(client);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(item, info, sizeof(info));

        if (StrEqual(info, "none"))
        {
            ShowPvPPlayerMenu(client);
            return 0;
        }

        int userId = StringToInt(info);
        int target = GetClientOfUserId(userId);
        if (!IsValidClient(target) || target == client)
        {
            Chat(client, "%T", "PvP Target Invalid", client);
            ShowPvPPlayerMenu(client);
            return 0;
        }

        g_iPvPMenuTarget[client] = target;
        ShowPvPBetMenu(client);
    }

    return 0;
}

void ShowPvPBetMenu(int client)
{
    int target = g_iPvPMenuTarget[client];
    if (!IsValidClient(target) || target == client)
    {
        Chat(client, "%T", "PvP Target Invalid", client);
        ShowPvPPlayerMenu(client);
        return;
    }

    if (!US_IsLoaded(target))
    {
        Chat(client, "%T", "PvP Target Not Loaded", client);
        ShowPvPPlayerMenu(client);
        return;
    }

    if (g_iMode[target] != BJMODE_NONE)
    {
        Chat(client, "%T", "PvP Target Busy", client, target);
        ShowPvPPlayerMenu(client);
        return;
    }

    if (g_iPvPInviteFrom[target] != 0)
    {
        Chat(client, "%T", "PvP Target Has Invite", client, target);
        ShowPvPPlayerMenu(client);
        return;
    }

    Menu menu = new Menu(MenuHandler_PvPBetMenu);

    char creditsText[32], title[256];
    FormatCredits(US_GetCredits(client), creditsText, sizeof(creditsText));
    Format(title, sizeof(title), "%T", "PvP Bet Menu Title", client, target, creditsText);
    menu.SetTitle(title);

    int usedQuickBets[6];
    int usedCount = 0;
    for (int i = 0; i < sizeof(usedQuickBets); i++)
    {
        usedQuickBets[i] = -1;
    }

    int credits = US_GetCredits(client);
    int maxBet = gCvarMaxBet.IntValue;
    int highBet = (credits < maxBet) ? credits : maxBet;

    AddQuickBetOption(menu, client, gCvarMinBet.IntValue, "Menu Quick Bet Min", usedQuickBets, sizeof(usedQuickBets), usedCount);
    AddQuickBetOption(menu, client, credits / 4, "Menu Quick Bet Low", usedQuickBets, sizeof(usedQuickBets), usedCount);
    AddQuickBetOption(menu, client, credits / 2, "Menu Quick Bet Medium", usedQuickBets, sizeof(usedQuickBets), usedCount);
    AddQuickBetOption(menu, client, highBet, "Menu Quick Bet High", usedQuickBets, sizeof(usedQuickBets), usedCount);
    AddQuickBetOption(menu, client, credits, "Menu Quick Bet AllIn", usedQuickBets, sizeof(usedQuickBets), usedCount);

    char customText[128];
    GetPhrase(client, "PvP Bet Menu Custom", customText, sizeof(customText));
    menu.AddItem("custom_bet", customText);

    if (usedCount == 0)
    {
        char text[128];
        GetPhrase(client, "Menu Quick Bet Unavailable", text, sizeof(text));
        menu.AddItem("quick_unavailable", text, ITEMDRAW_DISABLED);
    }

    char backText[128];
    GetPhrase(client, "PvP Bet Menu Back", backText, sizeof(backText));
    menu.AddItem("back_players", backText);

    menu.ExitBackButton = true;
    menu.Display(client, BJ_MENU_TIME);
}

public int MenuHandler_PvPBetMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        g_bPvPAwaitingCustomBet[client] = false;
        ShowPvPPlayerMenu(client);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(item, info, sizeof(info));

        if (StrEqual(info, "back_players"))
        {
            g_bPvPAwaitingCustomBet[client] = false;
            ShowPvPPlayerMenu(client);
            return 0;
        }

        if (StrEqual(info, "custom_bet"))
        {
            g_bPvPAwaitingCustomBet[client] = true;
            ChatInfo(client, "%T", "PvP Custom Bet Prompt", client);
            return 0;
        }

        int bet = StringToInt(info);
        if (bet <= 0)
        {
            ShowPvPBetMenu(client);
            return 0;
        }

        g_bPvPAwaitingCustomBet[client] = false;
        int target = g_iPvPMenuTarget[client];
        TryCreatePvPInviteTarget(client, target, bet);
    }

    return 0;
}

bool StartBlackjackRound(int client, int bet)
{
    if (!ValidateBet(client, bet, true))
    {
        return false;
    }

    if (g_iMode[client] != BJMODE_NONE)
    {
        Chat(client, "%T", "Already In Game", client);
        if (g_iMode[client] == BJMODE_SINGLE)
        {
            ShowSingleGameMenu(client);
        }
        else if (g_iMode[client] == BJMODE_TABLE)
        {
            ShowTableMenu(client);
        }
        else
        {
            ShowPvPMenu(client);
        }
        return false;
    }

    // Limpieza agresiva para evitar heredar cartas/contadores de una ronda previa.
    ResetBlackjackClient(client, false);
    ResetSingleRoundState(client);

    if (!US_TakeCredits(client, bet))
    {
        Chat(client, "%T", "Error Take Credits", client);
        return false;
    }

    g_iMode[client] = BJMODE_SINGLE;
    g_iBet[client] = bet;
    g_bCanDouble[client] = true;

    PlayerDraw(client, 0);
    DealerDraw(client);
    PlayerDraw(client, 0);
    DealerDraw(client);
    UpdateSplitAvailability(client);

    // Sanity checks: una mano inicial valida siempre debe arrancar con 2 cartas por lado
    // y el jugador jamas deberia iniciar por encima de 21.
    if (g_iPlayerCount[client][0] != 2 || g_iDealerCount[client] != 2 || GetBestHandValue(g_iPlayerCards[client][0], g_iPlayerCount[client][0]) > 21)
    {
        US_AddCredits(client, bet, true);
        ResetBlackjackClient(client, false);
        ChatError(client, "%T", "Round Invalid Start State", client);
        RequestShowMainMenu(client);
        return false;
    }

    PlayClientSound(client, BJ_SOUND_BET);

    bool playerBJ = IsNaturalBlackjack(g_iPlayerCards[client][0], g_iPlayerCount[client][0]);
    bool dealerBJ = IsNaturalBlackjack(g_iDealerCards[client], g_iDealerCount[client]);

    if (playerBJ || dealerBJ)
    {
        if (playerBJ && dealerBJ)
        {
            FinishSinglePush(client, "%T", "Round Push Both Blackjack", client);
        }
        else if (playerBJ)
        {
            int payout = CalculateBlackjackPayout(g_iBet[client]);
            US_AddCredits(client, payout, true);
            char sPayout[32];
            FormatCredits(payout, sPayout, sizeof(sPayout));
            FinishSingleWin(client, "%T", "Round Natural Blackjack Win", client, sPayout);
            MaybeAnnounceNaturalBlackjack(client);
        }
        else
        {
            FinishSingleLose(client, "%T", "Round Dealer Blackjack", client);
        }
        return true;
    }

    ShowSingleGameMenu(client);
    return true;
}

void ResetSingleRoundState(int client)
{
    g_bRoundFinished[client] = false;
    g_bCanDouble[client] = false;
    g_bUsedDouble[client] = false;
    g_bCanSplit[client] = false;
    g_bHasSplit[client] = false;
    g_bPlayingSplitHand[client] = false;
    g_bSplitHandDone[client] = false;
    g_iDealerCount[client] = 0;

    for (int hand = 0; hand < 2; hand++)
    {
        g_iPlayerCount[client][hand] = 0;
        for (int i = 0; i < BJ_MAX_HAND_CARDS; i++)
        {
            g_iPlayerCards[client][hand][i] = 0;
        }
    }

    for (int i = 0; i < BJ_MAX_HAND_CARDS; i++)
    {
        g_iDealerCards[client][i] = 0;
    }
}


void RequestShowMainMenu(int client)
{
    RequestFrame(Frame_ShowMainMenu, GetClientUserId(client));
}

public void Frame_ShowMainMenu(any userId)
{
    int client = GetClientOfUserId(userId);
    if (IsValidClient(client))
    {
        ShowMainMenu(client);
    }
}

void RequestShowSingleGameMenu(int client)
{
    RequestFrame(Frame_ShowSingleGameMenu, GetClientUserId(client));
}

public void Frame_ShowSingleGameMenu(any userId)
{
    int client = GetClientOfUserId(userId);
    if (IsValidClient(client) && g_iMode[client] == BJMODE_SINGLE)
    {
        ShowSingleGameMenu(client);
    }
}

void ShowSingleGameMenu(int client)
{
    if (g_iMode[client] != BJMODE_SINGLE)
    {
        ShowMainMenu(client);
        return;
    }

    Menu menu = new Menu(MenuHandler_SingleGameMenu);

    char hand0[256], hand1[256], dealerHand[256], sBet[32], sCredits[32], title[1200];
    int activeHand = GetActiveHand(client);
    BuildPlayerHandString(client, 0, hand0, sizeof(hand0));
    BuildDealerHandString(client, false, dealerHand, sizeof(dealerHand));
    FormatCredits(g_iBet[client], sBet, sizeof(sBet));
    FormatCredits(US_GetCredits(client), sCredits, sizeof(sCredits));

    if (g_bHasSplit[client])
    {
        BuildPlayerHandString(client, 1, hand1, sizeof(hand1));
        Format(title, sizeof(title), "%T", "Single Menu Title Split", client, sBet, sCredits, g_iWinStreak[client], activeHand + 1, dealerHand, hand0, hand1);
    }
    else
    {
        Format(title, sizeof(title), "%T", "Single Menu Title", client, sBet, sCredits, g_iWinStreak[client], dealerHand, hand0);
    }

    menu.SetTitle(title);
    { char text[128]; GetPhrase(client, "Menu Hit", text, sizeof(text)); menu.AddItem("hit", text); }
    { char text[128]; GetPhrase(client, "Menu Stand", text, sizeof(text)); menu.AddItem("stand", text); }

    if (CanShowDouble(client))
    {
        char label[96], extra[32];
        FormatCredits(g_iBet[client], extra, sizeof(extra));
        Format(label, sizeof(label), "%T", "Menu Double", client, extra);
        menu.AddItem("double", label);
    }
    else
    {
        { char text[128]; GetPhrase(client, "Menu Double Disabled", text, sizeof(text)); menu.AddItem("double_disabled", text, ITEMDRAW_DISABLED); }
    }

    if (CanShowSplit(client))
    {
        char label[96], extra[32];
        FormatCredits(g_iBet[client], extra, sizeof(extra));
        Format(label, sizeof(label), "%T", "Menu Split", client, extra);
        menu.AddItem("split", label);
    }
    else
    {
        { char text[128]; GetPhrase(client, "Menu Split Disabled", text, sizeof(text)); menu.AddItem("split_disabled", text, ITEMDRAW_DISABLED); }
    }

    { char text[128]; GetPhrase(client, "Menu History", text, sizeof(text)); menu.AddItem("history", text); }
    { char text[128]; GetPhrase(client, "Menu Stats", text, sizeof(text)); menu.AddItem("stats", text); }
    menu.ExitBackButton = true;
    menu.Display(client, BJ_MENU_TIME);
}

public int MenuHandler_SingleGameMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        RequestShowMainMenu(client);
    }
    else if (action == MenuAction_Select)
    {
        if (g_iMode[client] != BJMODE_SINGLE || g_bRoundFinished[client])
        {
            RequestShowMainMenu(client);
            return 0;
        }

        if (!CheckActionCooldown(client))
        {
            RequestShowSingleGameMenu(client);
            return 0;
        }

        char info[32];
        menu.GetItem(item, info, sizeof(info));

        if (StrEqual(info, "hit"))
        {
            SinglePlayerHit(client);
        }
        else if (StrEqual(info, "stand"))
        {
            SinglePlayerStand(client);
        }
        else if (StrEqual(info, "double"))
        {
            SinglePlayerDouble(client);
        }
        else if (StrEqual(info, "split"))
        {
            SinglePlayerSplit(client);
        }
        else if (StrEqual(info, "history"))
        {
            ShowHistoryMenu(client);
        }
        else if (StrEqual(info, "stats"))
        {
            ShowStatsMenu(client);
        }
    }

    return 0;
}

void SinglePlayerHit(int client)
{
    int hand = GetActiveHand(client);
    g_bCanDouble[client] = false;
    g_bCanSplit[client] = false;

    PlayerDraw(client, hand);
    PlayClientSound(client, BJ_SOUND_CARD);

    int value = GetBestHandValue(g_iPlayerCards[client][hand], g_iPlayerCount[client][hand]);
    if (value > 21)
    {
        if (g_bHasSplit[client] && hand == 0 && !g_bSplitHandDone[client])
        {
            g_bSplitHandDone[client] = true;
            g_bPlayingSplitHand[client] = true;
            Chat(client, "%T", "Round Hand One Bust Continue", client, value);
            RequestShowSingleGameMenu(client);
            return;
        }

        if (g_bHasSplit[client] && hand == 1)
        {
            ResolveSplitDealer(client);
            return;
        }

        FinishSingleLose(client, "%T", "Round Bust", client, value);
        return;
    }

    RequestShowSingleGameMenu(client);
}

void SinglePlayerStand(int client)
{
    g_bCanDouble[client] = false;
    g_bCanSplit[client] = false;

    if (g_bHasSplit[client] && !g_bPlayingSplitHand[client])
    {
        g_bSplitHandDone[client] = true;
        g_bPlayingSplitHand[client] = true;
        Chat(client, "%T", "Round Move To Hand Two", client);
        RequestShowSingleGameMenu(client);
        return;
    }

    DealerPlayAndResolve(client);
}

void SinglePlayerDouble(int client)
{
    if (!CanShowDouble(client))
    {
        RequestShowSingleGameMenu(client);
        return;
    }

    if (US_GetCredits(client) < g_iBet[client])
    {
        Chat(client, "%T", "Round No Credits Double", client);
        RequestShowSingleGameMenu(client);
        return;
    }

    if (!US_TakeCredits(client, g_iBet[client]))
    {
        Chat(client, "%T", "Error Take Credits", client);
        RequestShowSingleGameMenu(client);
        return;
    }

    int hand = GetActiveHand(client);
    g_bUsedDouble[client] = true;
    g_bCanDouble[client] = false;
    g_bCanSplit[client] = false;

    PlayClientSound(client, BJ_SOUND_BET);
    PlayerDraw(client, hand);
    PlayClientSound(client, BJ_SOUND_CARD);

    int value = GetBestHandValue(g_iPlayerCards[client][hand], g_iPlayerCount[client][hand]);
    if (value > 21)
    {
        if (g_bHasSplit[client] && hand == 0 && !g_bSplitHandDone[client])
        {
            g_bSplitHandDone[client] = true;
            g_bPlayingSplitHand[client] = true;
            Chat(client, "%T", "Round Double Bust Continue", client, value);
            RequestShowSingleGameMenu(client);
            return;
        }

        if (g_bHasSplit[client] && hand == 1)
        {
            ResolveSplitDealer(client);
            return;
        }

        FinishSingleLose(client, "%T", "Round Double Bust", client, value);
        return;
    }

    if (g_bHasSplit[client] && hand == 0)
    {
        g_bSplitHandDone[client] = true;
        g_bPlayingSplitHand[client] = true;
        Chat(client, "%T", "Round Move To Hand Two", client);
        RequestShowSingleGameMenu(client);
        return;
    }

    DealerPlayAndResolve(client);
}

void SinglePlayerSplit(int client)
{
    if (!CanShowSplit(client))
    {
        RequestShowSingleGameMenu(client);
        return;
    }

    if (US_GetCredits(client) < g_iBet[client])
    {
        Chat(client, "%T", "Round No Credits Split", client);
        RequestShowSingleGameMenu(client);
        return;
    }

    if (!US_TakeCredits(client, g_iBet[client]))
    {
        Chat(client, "%T", "Error Take Credits", client);
        RequestShowSingleGameMenu(client);
        return;
    }

    PlayClientSound(client, BJ_SOUND_BET);

    int secondCard = g_iPlayerCards[client][0][1];
    g_iPlayerCards[client][0][1] = 0;
    g_iPlayerCount[client][0] = 1;

    g_iPlayerCards[client][1][0] = secondCard;
    g_iPlayerCount[client][1] = 1;

    g_bHasSplit[client] = true;
    g_bCanSplit[client] = false;
    g_bCanDouble[client] = true;
    g_bPlayingSplitHand[client] = false;
    g_bSplitHandDone[client] = false;

    PlayerDraw(client, 0);
    PlayerDraw(client, 1);
    PlayClientSound(client, BJ_SOUND_CARD);

    Chat(client, "%T", "Round Split Done", client);
    RequestShowSingleGameMenu(client);
}

void DealerPlayAndResolve(int client)
{
    g_bCanDouble[client] = false;
    g_bCanSplit[client] = false;

    while (DealerShouldHit(client))
    {
        DealerDraw(client);
    }

    if (g_bHasSplit[client])
    {
        ResolveSplitDealer(client);
        return;
    }

    int dealerValue = GetBestHandValue(g_iDealerCards[client], g_iDealerCount[client]);
    int playerValue = GetBestHandValue(g_iPlayerCards[client][0], g_iPlayerCount[client][0]);

    if (dealerValue > 21)
    {
        int payout = GetCurrentBaseBet(client) * 2;
        US_AddCredits(client, payout, true);
        char sPayout[32];
        FormatCredits(payout, sPayout, sizeof(sPayout));
        FinishSingleWin(client, "%T", "Round Dealer Bust Win", client, dealerValue, sPayout);
        return;
    }

    if (playerValue > dealerValue)
    {
        int payout = GetCurrentBaseBet(client) * 2;
        US_AddCredits(client, payout, true);
        char sPayout[32];
        FormatCredits(payout, sPayout, sizeof(sPayout));
        FinishSingleWin(client, "%T", "Round Compare Win", client, sPayout, playerValue, dealerValue);
    }
    else if (playerValue < dealerValue)
    {
        FinishSingleLose(client, "%T", "Round Compare Lose", client, playerValue, dealerValue);
    }
    else
    {
        FinishSinglePush(client, "%T", "Round Compare Push", client, playerValue);
    }
}

void ResolveSplitDealer(int client)
{
    int dealerValue = GetBestHandValue(g_iDealerCards[client], g_iDealerCount[client]);
    int payout = 0;
    int pushes = 0;
    char result[256];
    result[0] = '\0';

    for (int hand = 0; hand < 2; hand++)
    {
        int value = GetBestHandValue(g_iPlayerCards[client][hand], g_iPlayerCount[client][hand]);
        char part[96];

        if (value > 21)
        {
            Format(part, sizeof(part), "%T", "Split Result Lose", client, hand + 1, value);
        }
        else if (dealerValue > 21 || value > dealerValue)
        {
            payout += g_iBet[client] * 2;
            Format(part, sizeof(part), "%T", "Split Result Win", client, hand + 1, value);
        }
        else if (value == dealerValue)
        {
            payout += g_iBet[client];
            pushes++;
            Format(part, sizeof(part), "%T", "Split Result Push", client, hand + 1, value);
        }
        else
        {
            Format(part, sizeof(part), "%T", "Split Result Lose", client, hand + 1, value);
        }

        if (hand > 0)
        {
            StrCat(result, sizeof(result), " | ");
        }
        StrCat(result, sizeof(result), part);
    }

    if (payout > 0)
    {
        US_AddCredits(client, payout, true);
    }

    if (dealerValue > 21)
    {
        FinishSingleWin(client, "%T", "Split Dealer Bust Summary", client, dealerValue, result);
    }
    else if (payout == 0)
    {
        FinishSingleLose(client, "%T", "Split Dealer Summary", client, result, dealerValue);
    }
    else
    {
        FinishSingleWin(client, "%T", "Split Dealer Summary", client, result, dealerValue);
    }
}


void RecordSingleStats(int client, int net, bool win, bool push, bool naturalBlackjack)
{
    g_iStatGames[client]++;
    g_iStatProfit[client] += net;

    if (naturalBlackjack)
    {
        g_iStatBlackjacks[client]++;
    }

    if (push)
    {
        g_iStatPushes[client]++;
        g_iWinStreak[client] = 0;
        return;
    }

    if (win)
    {
        g_iStatWins[client]++;
        g_iWinStreak[client]++;
        if (g_iWinStreak[client] > g_iBestWinStreak[client])
        {
            g_iBestWinStreak[client] = g_iWinStreak[client];
        }
    }
    else
    {
        g_iStatLosses[client]++;
        g_iWinStreak[client] = 0;
    }
}


bool ShouldAnnounceStreak(int streak)
{
    return (streak == 3 || streak == 5 || (streak > 5 && (streak % 5) == 0));
}

void MaybeAnnounceNaturalBlackjack(int client)
{
    if (!gCvarAnnounceNaturalBlackjack.BoolValue)
    {
        return;
    }

            PrintToChatAll("%s %t", BJ_CHAT_TAG, "Announce Natural Blackjack", client);
}

void MaybeAnnounceStreak(int client)
{
    if (!gCvarAnnounceStreaks.BoolValue || !ShouldAnnounceStreak(g_iWinStreak[client]))
    {
        return;
    }

            PrintToChatAll("%s %t", BJ_CHAT_TAG, "Announce Win Streak", client, g_iWinStreak[client]);
}


void MaybeAnnounceBigWin(int client, int net)
{
    if (!gCvarBigWinAnnounce.BoolValue || net < gCvarBigWinMinNet.IntValue)
    {
        return;
    }

    char sNet[32];
    FormatCredits(net, sNet, sizeof(sNet));
        PrintToChatAll("%s %t", BJ_CHAT_TAG, "Announce Big Win", client, sNet);
}

void FinishSingleWin(int client, const char[] format, any ...)
{
    int totalBet = GetCurrentBaseBet(client);
    bool naturalBlackjack = IsNaturalBlackjack(g_iPlayerCards[client][0], g_iPlayerCount[client][0]) && !g_bHasSplit[client];
    int net = naturalBlackjack ? (CalculateBlackjackPayout(g_iBet[client]) - totalBet) : totalBet;

    char buffer[256];
    VFormat(buffer, sizeof(buffer), format, 3);

    char dealerHand[256], playerHand[320], sBalance[32];
    BuildDealerHandString(client, true, dealerHand, sizeof(dealerHand));
    BuildSummaryPlayerHands(client, playerHand, sizeof(playerHand));
    FormatCredits(US_GetCredits(client), sBalance, sizeof(sBalance));

    ChatSuccess(client, "%s", buffer);
    ChatInfo(client, "%T", "Round Summary Line", client, dealerHand, playerHand);
    ChatInfo(client, "%T", "Round Balance Line", client, sBalance);
    AddHistory(client, "%s", buffer);
    PlayClientSound(client, BJ_SOUND_WIN);
    RecordSingleStats(client, net, true, false, naturalBlackjack);
    MaybeAnnounceBigWin(client, net);
    MaybeAnnounceStreak(client);

    ResetBlackjackClient(client, false);
    RequestShowMainMenu(client);
}

void FinishSingleLose(int client, const char[] format, any ...)
{
    int totalBet = GetCurrentBaseBet(client);

    char buffer[256];
    VFormat(buffer, sizeof(buffer), format, 3);

    char dealerHand[256], playerHand[320], sBalance[32];
    BuildDealerHandString(client, true, dealerHand, sizeof(dealerHand));
    BuildSummaryPlayerHands(client, playerHand, sizeof(playerHand));
    FormatCredits(US_GetCredits(client), sBalance, sizeof(sBalance));

    ChatError(client, "%s", buffer);
    ChatInfo(client, "%T", "Round Summary Line", client, dealerHand, playerHand);
    ChatInfo(client, "%T", "Round Balance Line", client, sBalance);
    AddHistory(client, "%s", buffer);
    PlayClientSound(client, BJ_SOUND_LOSE);
    RecordSingleStats(client, -totalBet, false, false, false);

    ResetBlackjackClient(client, false);
    RequestShowMainMenu(client);
}

void FinishSinglePush(int client, const char[] format, any ...)
{
    US_AddCredits(client, GetCurrentBaseBet(client), true);

    char buffer[256];
    VFormat(buffer, sizeof(buffer), format, 3);

    char dealerHand[256], playerHand[320], sBalance[32];
    BuildDealerHandString(client, true, dealerHand, sizeof(dealerHand));
    BuildSummaryPlayerHands(client, playerHand, sizeof(playerHand));
    FormatCredits(US_GetCredits(client), sBalance, sizeof(sBalance));

    ChatNotice(client, "%s", buffer);
    ChatInfo(client, "%T", "Round Summary Line", client, dealerHand, playerHand);
    ChatInfo(client, "%T", "Round Balance Line", client, sBalance);
    AddHistory(client, "%s", buffer);
    PlayClientSound(client, BJ_SOUND_PUSH);
    RecordSingleStats(client, 0, false, true, false);

    ResetBlackjackClient(client, false);
    RequestShowMainMenu(client);
}

int GetCurrentBaseBet(int client)
{
    int total = g_iBet[client];
    if (g_bUsedDouble[client])
    {
        total += g_iBet[client];
    }
    if (g_bHasSplit[client])
    {
        total += g_iBet[client];
    }
    return total;
}

bool ValidateBet(int client, int bet, bool showMenu)
{
    int minBet = gCvarMinBet.IntValue;
    int maxBet = gCvarMaxBet.IntValue;

    if (bet < minBet)
    {
        char sMin[32];
        FormatCredits(minBet, sMin, sizeof(sMin));
        Chat(client, "%T", "Error Min Bet", client, sMin);
        if (showMenu)
        {
            ShowMainMenu(client);
        }
        return false;
    }

    if (bet > maxBet)
    {
        char sMax[32];
        FormatCredits(maxBet, sMax, sizeof(sMax));
        Chat(client, "%T", "Error Max Bet", client, sMax);
        if (showMenu)
        {
            ShowMainMenu(client);
        }
        return false;
    }

    int credits = US_GetCredits(client);
    if (credits < bet)
    {
        char sCredits[32];
        FormatCredits(credits, sCredits, sizeof(sCredits));
        Chat(client, "%T", "Error Not Enough Credits", client, sCredits);
        if (showMenu)
        {
            ShowMainMenu(client);
        }
        return false;
    }

    return true;
}

void TryCreatePvPInviteTarget(int client, int target, int bet)
{
    if (!gCvarPvPEnabled.BoolValue)
    {
        Chat(client, "%T", "PvP Disabled", client);
        return;
    }

    if (g_iMode[client] != BJMODE_NONE)
    {
        Chat(client, "%T", "Already In Game", client);
        return;
    }

    if (!ValidateBet(client, bet, false))
    {
        return;
    }

    if (target == client)
    {
        Chat(client, "%T", "PvP Self Challenge", client);
        return;
    }

    if (!IsValidClient(target))
    {
        Chat(client, "%T", "PvP Target Invalid", client);
        return;
    }

    if (!US_IsLoaded(target))
    {
        Chat(client, "%T", "PvP Target Not Loaded", client);
        return;
    }

    if (g_iMode[target] != BJMODE_NONE)
    {
        Chat(client, "%T", "PvP Target Busy", client, target);
        return;
    }

    if (g_iPvPInviteFrom[target] != 0)
    {
        Chat(client, "%T", "PvP Target Has Invite", client, target);
        return;
    }

    g_iPvPInviteFrom[target] = client;
    g_iPvPInviteBet[target] = bet;
    ClearInvite(client);
    ClearInvite(target);
    g_iPvPInviteFrom[target] = client;
    g_iPvPInviteBet[target] = bet;
    g_hPvPInviteTimer[target] = CreateTimer(gCvarPvPInviteTimeout.FloatValue, Timer_PvPInviteExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);

    char sBet[32];
    FormatCredits(bet, sBet, sizeof(sBet));
    Chat(client, "%T", "PvP Invite Sent", client, target, sBet);
    Chat(target, "%T", "PvP Invite Received", target, client, sBet);
    Chat(target, "%T", "PvP Invite Commands", target);
}

public Action Timer_PvPInviteExpire(Handle timer, any userId)
{
    int target = GetClientOfUserId(userId);
    if (!IsValidClient(target))
    {
        return Plugin_Stop;
    }

    int challenger = g_iPvPInviteFrom[target];
    if (challenger > 0)
    {
        Chat(target, "%T", "PvP Invite Expired Target", target);
        if (IsValidClient(challenger))
        {
            Chat(challenger, "%T", "PvP Invite Expired Challenger", challenger, target);
        }
    }

    ClearInvite(target);
    return Plugin_Stop;
}

void ClearInvite(int target)
{
    g_iPvPInviteFrom[target] = 0;
    g_iPvPInviteBet[target] = 0;

    if (g_hPvPInviteTimer[target] != null)
    {
        KillTimer(g_hPvPInviteTimer[target]);
        g_hPvPInviteTimer[target] = null;
    }
}

void ClearPvPTurnTimer(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    if (g_hPvPTurnTimer[client] != null)
    {
        KillTimer(g_hPvPTurnTimer[client]);
        g_hPvPTurnTimer[client] = null;
    }
}

void StartPvPTurnTimer(int client)
{
    if (!IsValidClient(client) || g_iMode[client] != BJMODE_PVP || !IsPvPTurn(client) || g_bPvPStood[client])
    {
        return;
    }

    ClearPvPTurnTimer(client);
    g_hPvPTurnTimer[client] = CreateTimer(gCvarPvPTurnTimeout.FloatValue, Timer_PvPTurnTimeout, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_PvPTurnTimeout(Handle timer, any userId)
{
    int client = GetClientOfUserId(userId);
    if (!IsValidClient(client))
    {
        return Plugin_Stop;
    }

    if (g_hPvPTurnTimer[client] != timer)
    {
        return Plugin_Stop;
    }
    g_hPvPTurnTimer[client] = null;

    if (g_iMode[client] != BJMODE_PVP || !IsPvPTurn(client) || g_bPvPStood[client])
    {
        return Plugin_Stop;
    }

    int opponent = g_iPvPOpponent[client];
    Chat(client, "%T", "PvP Turn Timeout Self", client);
    if (IsValidClient(opponent) && g_iMode[opponent] == BJMODE_PVP)
    {
        Chat(opponent, "%T", "PvP Turn Timeout Opponent", opponent, client);
    }

    PvPPlayerStand(client);
    return Plugin_Stop;
}

void AcceptPvPInvite(int client)
{
    int challenger = g_iPvPInviteFrom[client];
    int bet = g_iPvPInviteBet[client];

    if (challenger <= 0 || !IsValidClient(challenger))
    {
        Chat(client, "%T", "PvP No Invite", client);
        ClearInvite(client);
        return;
    }

    if (g_iMode[client] != BJMODE_NONE || g_iMode[challenger] != BJMODE_NONE)
    {
        Chat(client, "%T", "PvP Accept Busy", client);
        Chat(challenger, "%T", "PvP Accept Busy Challenger", challenger, client);
        ClearInvite(client);
        return;
    }

    if (!ValidateBet(client, bet, false) || !ValidateBet(challenger, bet, false))
    {
        Chat(client, "%T", "PvP Accept Failed Credits", client);
        Chat(challenger, "%T", "PvP Accept Failed Challenger", challenger, client);
        ClearInvite(client);
        return;
    }

    bool tookClient = US_TakeCredits(client, bet);
    bool tookChallenger = US_TakeCredits(challenger, bet);
    if (!tookClient || !tookChallenger)
    {
        if (tookClient)
        {
            US_AddCredits(client, bet, true);
        }
        if (tookChallenger)
        {
            US_AddCredits(challenger, bet, true);
        }

        Chat(client, "%T", "Error Take Credits", client);
        Chat(challenger, "%T", "Error Take Credits", challenger);
        ClearInvite(client);
        return;
    }

    StartPvPRound(challenger, client, bet);
    ClearInvite(client);
}

void DeclinePvPInvite(int client)
{
    int challenger = g_iPvPInviteFrom[client];
    if (challenger <= 0)
    {
        Chat(client, "%T", "PvP No Invite", client);
        return;
    }

    if (IsValidClient(challenger))
    {
        Chat(challenger, "%T", "PvP Invite Declined", challenger, client);
    }
    Chat(client, "%T", "PvP You Declined", client);
    ClearInvite(client);
}

void StartPvPRound(int challenger, int opponent, int bet)
{
    ResetBlackjackClient(challenger, false);
    ResetBlackjackClient(opponent, false);

    g_iMode[challenger] = BJMODE_PVP;
    g_iMode[opponent] = BJMODE_PVP;

    g_iPvPOpponent[challenger] = opponent;
    g_iPvPOpponent[opponent] = challenger;
    g_iPvPBet[challenger] = bet;
    g_iPvPBet[opponent] = bet;

    g_iPvPCurrentTurn[challenger] = challenger;
    g_iPvPCurrentTurn[opponent] = challenger;

    PvPDraw(challenger);
    PvPDraw(opponent);
    PvPDraw(challenger);
    PvPDraw(opponent);

    PlayClientSound(challenger, BJ_SOUND_BET);
    PlayClientSound(opponent, BJ_SOUND_BET);

    char sBet[32];
    FormatCredits(bet, sBet, sizeof(sBet));
    Chat(challenger, "%T", "PvP Round Started Challenger", challenger, opponent, sBet);
    Chat(opponent, "%T", "PvP Round Started Opponent", opponent, challenger, sBet);

    if (IsNaturalBlackjack(g_iPvPCards[challenger], g_iPvPCount[challenger]) || IsNaturalBlackjack(g_iPvPCards[opponent], g_iPvPCount[opponent]))
    {
        ResolvePvPRound(challenger);
        return;
    }

    StartPvPTurnTimer(challenger);
    ShowPvPMenu(challenger);
    ShowPvPMenu(opponent);
}

void ShowPvPMenu(int client)
{
    if (g_iMode[client] != BJMODE_PVP)
    {
        ShowMainMenu(client);
        return;
    }

    int opponent = g_iPvPOpponent[client];
    if (!IsValidClient(opponent))
    {
        ResetBlackjackClient(client, false);
        ShowMainMenu(client);
        return;
    }

    Menu menu = new Menu(MenuHandler_PvPMenu);

    char myHand[256], enemyHand[256], title[1024], sBet[32];
    BuildPvPHandString(client, myHand, sizeof(myHand));
    BuildPvPOpponentHandString(client, enemyHand, sizeof(enemyHand));
    FormatCredits(g_iPvPBet[client], sBet, sizeof(sBet));

    if (IsPvPTurn(client))
    {
        Format(title, sizeof(title), "%T", "PvP Menu Title Turn", client, opponent, sBet, myHand, enemyHand);
    }
    else
    {
        Format(title, sizeof(title), "%T", "PvP Menu Title Wait", client, opponent, sBet, myHand, enemyHand);
    }

    menu.SetTitle(title);

    if (IsPvPTurn(client) && !g_bPvPStood[client] && GetBestHandValue(g_iPvPCards[client], g_iPvPCount[client]) < 21)
    {
        { char text[128]; GetPhrase(client, "Menu Hit", text, sizeof(text)); menu.AddItem("hit", text); }
        { char text[128]; GetPhrase(client, "Menu Stand", text, sizeof(text)); menu.AddItem("stand", text); }
    }
    else
    {
        { char text[128]; GetPhrase(client, "PvP Menu Waiting Disabled", text, sizeof(text)); menu.AddItem("wait1", text, ITEMDRAW_DISABLED); }
    }

    { char text[128]; GetPhrase(client, "Menu History", text, sizeof(text)); menu.AddItem("history", text); }
    { char text[128]; GetPhrase(client, "Menu Stats", text, sizeof(text)); menu.AddItem("stats", text); }
    menu.ExitBackButton = true;
    menu.Display(client, BJ_MENU_TIME);
}

public int MenuHandler_PvPMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        ShowMainMenu(client);
    }
    else if (action == MenuAction_Select)
    {
        if (g_iMode[client] != BJMODE_PVP)
        {
            RequestShowMainMenu(client);
            return 0;
        }

        char info[32];
        menu.GetItem(item, info, sizeof(info));

        if (StrEqual(info, "history"))
        {
            ShowHistoryMenu(client);
            return 0;
        }

        if (StrEqual(info, "stats"))
        {
            ShowStatsMenu(client);
            return 0;
        }

        if (!CheckActionCooldown(client))
        {
            ShowPvPMenu(client);
            return 0;
        }

        if (!IsPvPTurn(client))
        {
            Chat(client, "%T", "PvP Not Your Turn", client);
            ShowPvPMenu(client);
            return 0;
        }

        if (StrEqual(info, "hit"))
        {
            PvPPlayerHit(client);
        }
        else if (StrEqual(info, "stand"))
        {
            PvPPlayerStand(client);
        }
    }

    return 0;
}

bool IsPvPTurn(int client)
{
    return (g_iMode[client] == BJMODE_PVP && g_iPvPCurrentTurn[client] == client);
}

void PvPPlayerHit(int client)
{
    int opponent = g_iPvPOpponent[client];
    PvPDraw(client);
    PlayClientSound(client, BJ_SOUND_CARD);
    PlayClientSound(opponent, BJ_SOUND_CARD);

    int value = GetBestHandValue(g_iPvPCards[client], g_iPvPCount[client]);
    if (value >= 21)
    {
        g_bPvPStood[client] = true;
        AdvancePvPTurn(client);
    }
    else
    {
        StartPvPTurnTimer(client);
        ShowPvPMenu(client);
        ShowPvPMenu(opponent);
    }
}

void PvPPlayerStand(int client)
{
    g_bPvPStood[client] = true;
    AdvancePvPTurn(client);
}

void AdvancePvPTurn(int client)
{
    int opponent = g_iPvPOpponent[client];
    ClearPvPTurnTimer(client);
    ClearPvPTurnTimer(opponent);

    if (!IsValidClient(opponent) || g_iMode[opponent] != BJMODE_PVP)
    {
        ResetBlackjackClient(client, false);
        ShowMainMenu(client);
        return;
    }

    if (g_bPvPStood[client] && g_bPvPStood[opponent])
    {
        ResolvePvPRound(client);
        return;
    }

    if (!g_bPvPStood[opponent])
    {
        g_iPvPCurrentTurn[client] = opponent;
        g_iPvPCurrentTurn[opponent] = opponent;
        Chat(opponent, "%T", "PvP Your Turn", opponent);
        StartPvPTurnTimer(opponent);
    }
    else
    {
        g_iPvPCurrentTurn[client] = client;
        g_iPvPCurrentTurn[opponent] = client;
        Chat(client, "%T", "PvP Your Turn", client);
        StartPvPTurnTimer(client);
    }

    ShowPvPMenu(client);
    ShowPvPMenu(opponent);
}

void ResolvePvPRound(int anyClient)
{
    int client = anyClient;
    int opponent = g_iPvPOpponent[client];
    if (!IsValidClient(opponent))
    {
        ResetBlackjackClient(client, false);
        ShowMainMenu(client);
        return;
    }

    ClearPvPTurnTimer(client);
    ClearPvPTurnTimer(opponent);

    int valueA = GetBestHandValue(g_iPvPCards[client], g_iPvPCount[client]);
    int valueB = GetBestHandValue(g_iPvPCards[opponent], g_iPvPCount[opponent]);
    bool natA = IsNaturalBlackjack(g_iPvPCards[client], g_iPvPCount[client]);
    bool natB = IsNaturalBlackjack(g_iPvPCards[opponent], g_iPvPCount[opponent]);

    int winner = 0;
    if (natA && !natB)
    {
        winner = client;
    }
    else if (natB && !natA)
    {
        winner = opponent;
    }
    else if (valueA > 21 && valueB > 21)
    {
        winner = 0;
    }
    else if (valueA > 21)
    {
        winner = opponent;
    }
    else if (valueB > 21)
    {
        winner = client;
    }
    else if (valueA > valueB)
    {
        winner = client;
    }
    else if (valueB > valueA)
    {
        winner = opponent;
    }

    char handA[256], handB[256];
    BuildVisibleHandString(g_iPvPCards[client], g_iPvPCount[client], true, handA, sizeof(handA));
    BuildVisibleHandString(g_iPvPCards[opponent], g_iPvPCount[opponent], true, handB, sizeof(handB));

    int pot = g_iPvPBet[client] + g_iPvPBet[opponent];
    if (winner == 0)
    {
        US_AddCredits(client, g_iPvPBet[client], true);
        US_AddCredits(opponent, g_iPvPBet[opponent], true);

        Chat(client, "%T", "PvP Result Push", client, opponent, handA, handB);
        Chat(opponent, "%T", "PvP Result Push", opponent, client, handB, handA);
        { char hist[192]; Format(hist, sizeof(hist), "%T", "History PvP Push", client, opponent); AddHistory(client, "%s", hist); }
        { char hist[192]; Format(hist, sizeof(hist), "%T", "History PvP Push", opponent, client); AddHistory(opponent, "%s", hist); }
        PlayClientSound(client, BJ_SOUND_PUSH);
        PlayClientSound(opponent, BJ_SOUND_PUSH);
    }
    else
    {
        US_AddCredits(winner, pot, true);
        int loser = (winner == client) ? opponent : client;
        char sPot[32], winnerHand[256], loserHand[256];
        FormatCredits(pot, sPot, sizeof(sPot));

        if (winner == client)
        {
            strcopy(winnerHand, sizeof(winnerHand), handA);
            strcopy(loserHand, sizeof(loserHand), handB);
        }
        else
        {
            strcopy(winnerHand, sizeof(winnerHand), handB);
            strcopy(loserHand, sizeof(loserHand), handA);
        }

        Chat(winner, "%T", "PvP Result Win", winner, loser, sPot, winnerHand, loserHand);
        Chat(loser, "%T", "PvP Result Lose", loser, winner, sPot, loserHand, winnerHand);
        { char hist[192]; Format(hist, sizeof(hist), "%T", "History PvP Win", winner, loser, sPot); AddHistory(winner, "%s", hist); }
        { char hist[192]; Format(hist, sizeof(hist), "%T", "History PvP Lose", loser, winner, sPot); AddHistory(loser, "%s", hist); }
        PlayClientSound(winner, BJ_SOUND_WIN);
        PlayClientSound(loser, BJ_SOUND_LOSE);
    }

    ResetBlackjackClient(client, false);
    ResetBlackjackClient(opponent, false);
    ShowMainMenu(client);
    ShowMainMenu(opponent);
}

bool DealerShouldHit(int client)
{
    int value = GetBestHandValue(g_iDealerCards[client], g_iDealerCount[client]);
    if (value < 17)
    {
        return true;
    }

    if (value > 17)
    {
        return false;
    }

    if (!gCvarDealerHitSoft17.BoolValue)
    {
        return false;
    }

    return HandIsSoft(g_iDealerCards[client], g_iDealerCount[client]);
}

void PlayerDraw(int client, int hand)
{
    if (g_iPlayerCount[client][hand] < BJ_MAX_HAND_CARDS)
    {
        g_iPlayerCards[client][hand][g_iPlayerCount[client][hand]++] = DrawCard();
    }
}

void DealerDraw(int client)
{
    if (g_iDealerCount[client] < BJ_MAX_HAND_CARDS)
    {
        g_iDealerCards[client][g_iDealerCount[client]++] = DrawCard();
    }
}

void PvPDraw(int client)
{
    if (g_iPvPCount[client] < BJ_MAX_HAND_CARDS)
    {
        g_iPvPCards[client][g_iPvPCount[client]++] = DrawCard();
    }
}

int DrawCard()
{
    return GetRandomInt(0, 51);
}

bool IsNaturalBlackjack(int cards[BJ_MAX_HAND_CARDS], int count)
{
    return count == 2 && GetBestHandValue(cards, count) == 21;
}

int CalculateBlackjackPayout(int bet)
{
    int num = gCvarBlackjackPayNum.IntValue;
    int den = gCvarBlackjackPayDen.IntValue;

    if (den <= 0)
    {
        den = 2;
    }

    return bet + ((bet * num) / den);
}

int GetBestHandValue(int cards[BJ_MAX_HAND_CARDS], int count)
{
    int total = 0;
    int aces = 0;

    for (int i = 0; i < count; i++)
    {
        total += GetCardBlackjackValue(cards[i]);
        if (GetCardRank(cards[i]) == 1)
        {
            aces++;
        }
    }

    while (aces > 0 && total + 10 <= 21)
    {
        total += 10;
        aces--;
    }

    return total;
}

bool HandIsSoft(int cards[BJ_MAX_HAND_CARDS], int count)
{
    int total = 0;
    int aces = 0;

    for (int i = 0; i < count; i++)
    {
        total += GetCardBlackjackValue(cards[i]);
        if (GetCardRank(cards[i]) == 1)
        {
            aces++;
        }
    }

    return (aces > 0 && total + 10 <= 21);
}

int GetCardRank(int card)
{
    return (card % 13) + 1;
}

int GetCardSuit(int card)
{
    return card / 13;
}

int GetCardBlackjackValue(int card)
{
    int rank = GetCardRank(card);

    if (rank == 1)
    {
        return 1;
    }

    if (rank >= 10)
    {
        return 10;
    }

    return rank;
}

void BuildPlayerHandString(int client, int hand, char[] buffer, int maxlen)
{
    BuildVisibleHandString(g_iPlayerCards[client][hand], g_iPlayerCount[client][hand], true, buffer, maxlen);
}

void BuildDealerHandString(int client, bool revealAll, char[] buffer, int maxlen)
{
    BuildVisibleHandString(g_iDealerCards[client], g_iDealerCount[client], revealAll, buffer, maxlen);
}

void BuildPvPHandString(int client, char[] buffer, int maxlen)
{
    BuildVisibleHandString(g_iPvPCards[client], g_iPvPCount[client], true, buffer, maxlen);
}

void BuildPvPOpponentHandString(int client, char[] buffer, int maxlen)
{
    int opponent = g_iPvPOpponent[client];
    if (!IsValidClient(opponent))
    {
        GetPhrase(LANG_SERVER, "Value Dash", buffer, maxlen);
        return;
    }

    // PvP is intended to be fully visible so both players can track live cards and totals.
    bool reveal = true;
    BuildVisibleHandString(g_iPvPCards[opponent], g_iPvPCount[opponent], reveal, buffer, maxlen);
}

void BuildVisibleHandString(int cards[BJ_MAX_HAND_CARDS], int count, bool revealAll, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    char cardName[16];
    int visibleCards[BJ_MAX_HAND_CARDS];
    int visibleCount = 0;

    for (int i = 0; i < count; i++)
    {
        if (!revealAll && i >= 1)
        {
            if (buffer[0] != '\0')
            {
                StrCat(buffer, maxlen, " ");
            }
            StrCat(buffer, maxlen, "?");
            continue;
        }

        GetCardName(cards[i], cardName, sizeof(cardName));
        if (buffer[0] != '\0')
        {
            StrCat(buffer, maxlen, " ");
        }

        StrCat(buffer, maxlen, cardName);
        visibleCards[visibleCount++] = cards[i];
    }

    char valuePart[32];
    BuildHandValueText(visibleCards, visibleCount, valuePart, sizeof(valuePart));
    StrCat(buffer, maxlen, valuePart);
}


void BuildHandValueText(int cards[BJ_MAX_HAND_CARDS], int count, char[] buffer, int maxlen)
{
    if (count <= 0)
    {
        GetPhrase(LANG_SERVER, "Hand Value Zero", buffer, maxlen);
        return;
    }

    int hardTotal = 0;
    int aces = 0;

    for (int i = 0; i < count; i++)
    {
        hardTotal += GetCardBlackjackValue(cards[i]);
        if (GetCardRank(cards[i]) == 1)
        {
            aces++;
        }
    }

    if (aces > 0 && hardTotal + 10 <= 21)
    {
        Format(buffer, maxlen, "%T", "Hand Value Soft", LANG_SERVER, hardTotal, hardTotal + 10);
    }
    else
    {
        Format(buffer, maxlen, "%T", "Hand Value Hard", LANG_SERVER, hardTotal);
    }
}

void BuildSummaryPlayerHands(int client, char[] buffer, int maxlen)
{
    char hand0[180];
    BuildPlayerHandString(client, 0, hand0, sizeof(hand0));

    if (!g_bHasSplit[client])
    {
        Format(buffer, maxlen, "%T", "Summary Player", client, hand0);
        return;
    }

    char hand1[180];
    BuildPlayerHandString(client, 1, hand1, sizeof(hand1));
    Format(buffer, maxlen, "%T", "Summary Split", client, hand0, hand1);
}

void GetCardName(int card, char[] buffer, int maxlen)
{
    int rank = GetCardRank(card);
    int suit = GetCardSuit(card);

    char rankText[4];
    switch (rank)
    {
        case 1:  strcopy(rankText, sizeof(rankText), "A");
        case 11: strcopy(rankText, sizeof(rankText), "J");
        case 12: strcopy(rankText, sizeof(rankText), "Q");
        case 13: strcopy(rankText, sizeof(rankText), "K");
        default: IntToString(rank, rankText, sizeof(rankText));
    }

    char suitText[4];
    switch (suit)
    {
        // ASCII-only suits avoid chat/log mojibake on servers with legacy encodings.
        case 0: strcopy(suitText, sizeof(suitText), "S");
        case 1: strcopy(suitText, sizeof(suitText), "H");
        case 2: strcopy(suitText, sizeof(suitText), "D");
        default: strcopy(suitText, sizeof(suitText), "C");
    }

    Format(buffer, maxlen, "%s%s", rankText, suitText);
}

void FormatCredits(int amount, char[] buffer, int maxlen)
{
    char raw[32];
    IntToString(amount, raw, sizeof(raw));

    int len = strlen(raw);
    int out = 0;

    for (int i = 0; i < len; i++)
    {
        if (i > 0 && ((len - i) % 3) == 0)
        {
            if (out < maxlen - 1)
            {
                buffer[out++] = '.';
            }
        }

        if (out < maxlen - 1)
        {
            buffer[out++] = raw[i];
        }
    }

    buffer[out] = '\0';
}


void FormatSignedCredits(int amount, char[] buffer, int maxlen)
{
    char value[32];
    int absValue = (amount < 0) ? -amount : amount;
    FormatCredits(absValue, value, sizeof(value));

    if (amount > 0)
    {
        Format(buffer, maxlen, "+%s", value);
    }
    else if (amount < 0)
    {
        Format(buffer, maxlen, "-%s", value);
    }
    else
    {
        strcopy(buffer, maxlen, "0");
    }
}

void ChatInfo(int client, const char[] format, any ...)
{
    char buffer[256], highlighted[320];
    VFormat(buffer, sizeof(buffer), format, 3);
    HighlightChatCommands(buffer, highlighted, sizeof(highlighted));
    PrintToChat(client, "%s %s", BJ_CHAT_TAG, highlighted);
}

void ChatSuccess(int client, const char[] format, any ...)
{
    char buffer[256], highlighted[320];
    VFormat(buffer, sizeof(buffer), format, 3);
    HighlightChatCommands(buffer, highlighted, sizeof(highlighted));
    PrintToChat(client, "%s \x04%s\x01", BJ_CHAT_TAG, highlighted);
}

void ChatError(int client, const char[] format, any ...)
{
    char buffer[256], highlighted[320];
    VFormat(buffer, sizeof(buffer), format, 3);
    HighlightChatCommands(buffer, highlighted, sizeof(highlighted));
    PrintToChat(client, "%s %s", BJ_CHAT_TAG, highlighted);
}

void ChatNotice(int client, const char[] format, any ...)
{
    char buffer[256], highlighted[320];
    VFormat(buffer, sizeof(buffer), format, 3);
    HighlightChatCommands(buffer, highlighted, sizeof(highlighted));
    PrintToChat(client, "%s %s", BJ_CHAT_TAG, highlighted);
}

void Chat(int client, const char[] format, any ...)
{
    char buffer[256], highlighted[320];
    VFormat(buffer, sizeof(buffer), format, 3);
    HighlightChatCommands(buffer, highlighted, sizeof(highlighted));
    PrintToChat(client, "%s %s", BJ_CHAT_TAG, highlighted);
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

void AddHistory(int client, const char[] format, any ...)
{
    char buffer[192];
    VFormat(buffer, sizeof(buffer), format, 3);

    for (int i = BJ_MAX_HISTORY - 1; i > 0; i--)
    {
        strcopy(g_sResultHistory[client][i], 192, g_sResultHistory[client][i - 1]);
    }

    strcopy(g_sResultHistory[client][0], 192, buffer);
    if (g_iHistoryCount[client] < BJ_MAX_HISTORY)
    {
        g_iHistoryCount[client]++;
    }
}



int TablePlayerCount()
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_bTableSeated[i])
        {
            count++;
        }
    }
    return count;
}

bool IsClientAtTable(int client)
{
    return (client > 0 && client <= MaxClients && g_bTableSeated[client]);
}

void TableCancelStartTimer()
{
    if (g_hTableStartTimer != null)
    {
        KillTimer(g_hTableStartTimer);
        g_hTableStartTimer = null;
    }
}

void TableCancelTurnTimer()
{
    if (g_hTableTurnTimer != null)
    {
        KillTimer(g_hTableTurnTimer);
        g_hTableTurnTimer = null;
    }
}

void TableClearRoundData()
{
    g_iTableDealerCount = 0;
    g_iTableCurrentTurn = -1;
    for (int i = 0; i < BJ_MAX_HAND_CARDS; i++)
    {
        g_iTableDealerCards[i] = 0;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        g_bTableStood[client] = false;
        g_bTableBusted[client] = false;
        g_iTableCount[client] = 0;
        for (int i = 0; i < BJ_MAX_HAND_CARDS; i++)
        {
            g_iTableCards[client][i] = 0;
        }
    }
}

void TableRebuildOrder()
{
    for (int i = 0; i < BJ_TABLE_MAX_PLAYERS; i++)
    {
        g_iTableOrder[i] = 0;
    }

    int slot = 0;
    for (int client = 1; client <= MaxClients && slot < BJ_TABLE_MAX_PLAYERS; client++)
    {
        if (g_bTableSeated[client])
        {
            g_iTableOrder[slot++] = client;
        }
    }

    g_iTableSeatCount = slot;
}

void TableRemoveSeat(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    g_bTableSeated[client] = false;
    g_bTableStood[client] = false;
    g_bTableBusted[client] = false;
    g_bTableStakeTaken[client] = false;
    g_iTableBet[client] = 0;
    g_iTableCount[client] = 0;
    g_iMode[client] = BJMODE_NONE;

    for (int i = 0; i < BJ_MAX_HAND_CARDS; i++)
    {
        g_iTableCards[client][i] = 0;
    }
}

void TableResetAll()
{
    TableCancelStartTimer();
    TableCancelTurnTimer();

    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_iMode[client] == BJMODE_TABLE)
        {
            g_iMode[client] = BJMODE_NONE;
        }

        TableRemoveSeat(client);
    }

    for (int i = 0; i < BJ_MAX_HAND_CARDS; i++)
    {
        g_iTableDealerCards[i] = 0;
    }

    for (int i = 0; i < BJ_TABLE_MAX_PLAYERS; i++)
    {
        g_iTableOrder[i] = 0;
    }

    g_iTableDealerCount = 0;
    g_iTableSeatCount = 0;
    g_iTableCurrentTurn = -1;
    g_iTableState = BJTABLE_IDLE;
}

void BuildTablePlayersSummary(char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    for (int i = 0; i < g_iTableSeatCount; i++)
    {
        int client = g_iTableOrder[i];
        if (!IsClientAtTable(client))
        {
            continue;
        }

        char credits[32], line[96];
        FormatCredits(g_iTableBet[client], credits, sizeof(credits));
        Format(line, sizeof(line), "%T", "Table Seat Player", LANG_SERVER, client, credits);

        if (buffer[0] != '\0')
        {
            StrCat(buffer, maxlen, "\n");
        }
        StrCat(buffer, maxlen, line);
    }

    if (buffer[0] == '\0')
    {
        GetPhrase(LANG_SERVER, "Value Dash", buffer, maxlen);
    }
}

void BuildTablePlayerHandString(int client, char[] buffer, int maxlen)
{
    BuildVisibleHandString(g_iTableCards[client], g_iTableCount[client], true, buffer, maxlen);
}

void BuildTableDealerHandString(bool revealAll, char[] buffer, int maxlen)
{
    BuildVisibleHandString(g_iTableDealerCards, g_iTableDealerCount, revealAll, buffer, maxlen);
}

int GetTableCurrentClient()
{
    if (g_iTableCurrentTurn < 0 || g_iTableCurrentTurn >= g_iTableSeatCount)
    {
        return 0;
    }

    int client = g_iTableOrder[g_iTableCurrentTurn];
    if (!IsClientAtTable(client))
    {
        return 0;
    }
    return client;
}

bool IsTableTurn(int client)
{
    return (g_iTableState == BJTABLE_PLAYING && client == GetTableCurrentClient() && IsClientAtTable(client) && !g_bTableStood[client] && !g_bTableBusted[client]);
}

void ShowTableMenu(int client)
{
    Menu menu = new Menu(MenuHandler_TableMenu);
    char title[768];

    if (g_iTableState == BJTABLE_PLAYING || g_iTableState == BJTABLE_RESOLVING)
    {
        char dealer[128], players[512], turnLine[96];
        BuildTableDealerHandString(g_iTableState == BJTABLE_RESOLVING, dealer, sizeof(dealer));
        players[0] = '\0';

        for (int i = 0; i < g_iTableSeatCount; i++)
        {
            int target = g_iTableOrder[i];
            if (!IsClientAtTable(target))
            {
                continue;
            }

            char hand[128], line[196], bet[32];
            BuildTablePlayerHandString(target, hand, sizeof(hand));
            FormatCredits(g_iTableBet[target], bet, sizeof(bet));

            if (g_bTableBusted[target])
            {
                char status[48];
                GetPhrase(client, "Table Player Status Bust", status, sizeof(status));
                Format(line, sizeof(line), "%T", "Table Player Line Status", client, target, bet, hand, status);
            }
            else if (g_bTableStood[target])
            {
                char status[48];
                GetPhrase(client, "Table Player Status Stand", status, sizeof(status));
                Format(line, sizeof(line), "%T", "Table Player Line Status", client, target, bet, hand, status);
            }
            else
            {
                Format(line, sizeof(line), "%T", "Table Player Line", client, target, bet, hand);
            }

            if (players[0] != '\0')
            {
                StrCat(players, sizeof(players), "\n");
            }
            StrCat(players, sizeof(players), line);
        }

        int turnClient = GetTableCurrentClient();
        if (g_iTableState == BJTABLE_RESOLVING || turnClient == 0)
        {
            GetPhrase(client, "Table Resolving", turnLine, sizeof(turnLine));
        }
        else
        {
            Format(turnLine, sizeof(turnLine), "%T", "Table Turn", client, turnClient);
        }

        Format(title, sizeof(title), "%T", "Table Title Playing", client, turnLine, dealer, players);
        menu.SetTitle(title);

        if (IsTableTurn(client))
        {
            { char text2[128]; GetPhrase(client, "Table Action Hit", text2, sizeof(text2)); menu.AddItem("hit", text2); }
            { char text2[128]; GetPhrase(client, "Table Action Stand", text2, sizeof(text2)); menu.AddItem("stand", text2); }
        }
        else
        {
            { char text2[128]; GetPhrase(client, "Table Waiting Turn", text2, sizeof(text2)); menu.AddItem("wait", text2, ITEMDRAW_DISABLED); }
        }

        { char text2[128]; GetPhrase(client, "Menu History", text2, sizeof(text2)); menu.AddItem("history", text2); }
        { char text2[128]; GetPhrase(client, "Menu Stats", text2, sizeof(text2)); menu.AddItem("stats", text2); }
    }
    else
    {
        char players[256], state[64];
        BuildTablePlayersSummary(players, sizeof(players));
        if (g_iTableState == BJTABLE_WAITING)
        {
            GetPhrase(client, "Table Waiting", state, sizeof(state));
        }
        else
        {
            GetPhrase(client, "Table Idle", state, sizeof(state));
        }
        Format(title, sizeof(title), "%T", "Table Title Waiting", client, state, TablePlayerCount(), BJ_TABLE_MAX_PLAYERS, players);
        menu.SetTitle(title);

        if (IsClientAtTable(client))
        {
            { char text2[128]; GetPhrase(client, "Table Leave", text2, sizeof(text2)); menu.AddItem("leave", text2); }
            if (TablePlayerCount() >= BJ_TABLE_MIN_PLAYERS)
            {
                { char text2[128]; GetPhrase(client, "Table Start", text2, sizeof(text2)); menu.AddItem("start", text2); }
            }
            else
            {
                { char text2[128]; GetPhrase(client, "Table Need Players", text2, sizeof(text2)); menu.AddItem("start_disabled", text2, ITEMDRAW_DISABLED); }
            }
        }
        else if (TablePlayerCount() >= BJ_TABLE_MAX_PLAYERS)
        {
            { char text2[128]; GetPhrase(client, "Table Full", text2, sizeof(text2)); menu.AddItem("full", text2, ITEMDRAW_DISABLED); }
        }
        else
        {
            { char text2[128]; GetPhrase(client, "Table Join Info", text2, sizeof(text2)); menu.AddItem("join_info", text2, ITEMDRAW_DISABLED); }
        }

        { char text2[128]; GetPhrase(client, "Menu History", text2, sizeof(text2)); menu.AddItem("history", text2); }
        { char text2[128]; GetPhrase(client, "Menu Stats", text2, sizeof(text2)); menu.AddItem("stats", text2); }
    }

    menu.ExitBackButton = true;
    menu.Display(client, BJ_MENU_TIME);
}

public int MenuHandler_TableMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        ShowMainMenu(client);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(item, info, sizeof(info));

        if (StrEqual(info, "hit"))
        {
            TablePlayerHit(client);
        }
        else if (StrEqual(info, "stand"))
        {
            TablePlayerStand(client);
        }
        else if (StrEqual(info, "leave"))
        {
            TableLeave(client, true);
        }
        else if (StrEqual(info, "start"))
        {
            TableForceStart(client);
        }
        else if (StrEqual(info, "history"))
        {
            ShowHistoryMenu(client);
        }
        else if (StrEqual(info, "stats"))
        {
            ShowStatsMenu(client);
        }
    }

    return 0;
}

void TableAnnounceState()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && IsClientAtTable(i))
        {
            ShowTableMenu(i);
        }
    }
}

void TableMaybeScheduleStart()
{
    if (g_iTableState != BJTABLE_WAITING)
    {
        return;
    }

    if (TablePlayerCount() < BJ_TABLE_MIN_PLAYERS)
    {
        TableCancelStartTimer();
        return;
    }

    if (g_hTableStartTimer == null)
    {
        g_hTableStartTimer = CreateTimer(BJ_TABLE_START_DELAY, Timer_TableStart);
            PrintToChatAll("%s %t", BJ_CHAT_TAG, "Table Countdown", RoundToCeil(BJ_TABLE_START_DELAY));
    }
}

public Action Timer_TableStart(Handle timer)
{
    g_hTableStartTimer = null;

    if (g_iTableState != BJTABLE_WAITING || TablePlayerCount() < BJ_TABLE_MIN_PLAYERS)
    {
        return Plugin_Stop;
    }

    StartTableRound();
    return Plugin_Stop;
}

bool TableJoin(int client, int bet)
{
    if (!ValidateBet(client, bet, false))
    {
        return false;
    }

    if (g_iMode[client] != BJMODE_NONE && g_iMode[client] != BJMODE_TABLE)
    {
        ChatError(client, "%T", "Already In Game", client);
        return false;
    }

    if (IsClientAtTable(client))
    {
        ChatNotice(client, "%T", "Table Already Seated", client);
        ShowTableMenu(client);
        return false;
    }

    if (g_iTableState == BJTABLE_PLAYING || g_iTableState == BJTABLE_RESOLVING)
    {
        ChatError(client, "%T", "Table Busy", client);
        return false;
    }

    if (TablePlayerCount() >= BJ_TABLE_MAX_PLAYERS)
    {
        ChatError(client, "%T", "Table Full Chat", client);
        return false;
    }

    g_iMode[client] = BJMODE_TABLE;
    g_bTableSeated[client] = true;
    g_bTableStakeTaken[client] = false;
    g_iTableBet[client] = bet;
    g_bTableStood[client] = false;
    g_bTableBusted[client] = false;
    g_iTableCount[client] = 0;
    if (g_iTableState == BJTABLE_IDLE)
    {
        g_iTableState = BJTABLE_WAITING;
    }

    TableRebuildOrder();
    char sBet[32];
    FormatCredits(bet, sBet, sizeof(sBet));
    PrintToChatAll("%s %t", BJ_CHAT_TAG, "Table Join Notice", client, sBet);

    TableMaybeScheduleStart();
    TableAnnounceState();
    return true;
}

void TableLeave(int client, bool showMenu)
{
    if (!IsClientAtTable(client))
    {
        if (showMenu)
        {
            ShowTableMenu(client);
        }
        return;
    }

    if (g_iTableState == BJTABLE_WAITING)
    {
        int refund = g_bTableStakeTaken[client] ? g_iTableBet[client] : 0;
        if (refund > 0 && IsValidClient(client))
        {
            US_AddCredits(client, refund, true);
        }

    PrintToChatAll("%s %t", BJ_CHAT_TAG, "Table Left", client);
        TableRemoveSeat(client);
        TableRebuildOrder();

        if (TablePlayerCount() <= 0)
        {
            TableResetAll();
        }
        else
        {
            g_iTableState = BJTABLE_WAITING;
            if (TablePlayerCount() < BJ_TABLE_MIN_PLAYERS)
            {
                TableCancelStartTimer();
            }
        }

        if (showMenu && IsValidClient(client))
        {
            ShowMainMenu(client);
        }
        TableAnnounceState();
        return;
    }

    ChatNotice(client, "%T", "Table Cannot Leave", client);
    if (showMenu)
    {
        ShowTableMenu(client);
    }
}

void TableForceStart(int client)
{
    if (!IsClientAtTable(client))
    {
        ChatError(client, "%T", "Table Not Seated", client);
        return;
    }

    if (g_iTableState != BJTABLE_WAITING)
    {
        ChatNotice(client, "%T", "Table Not Waiting", client);
        return;
    }

    if (TablePlayerCount() < BJ_TABLE_MIN_PLAYERS)
    {
        ChatError(client, "%T", "Table Need Two", client);
        return;
    }

    TableCancelStartTimer();
    StartTableRound();
}

void StartTableRound()
{
    TableCancelStartTimer();
    TableCancelTurnTimer();
    TableClearRoundData();
    TableRebuildOrder();

    if (g_iTableSeatCount < BJ_TABLE_MIN_PLAYERS)
    {
        g_iTableState = (g_iTableSeatCount > 0) ? BJTABLE_WAITING : BJTABLE_IDLE;
        TableAnnounceState();
        return;
    }

    int removed[BJ_TABLE_MAX_PLAYERS];
    int removedCount = 0;

    for (int i = 0; i < g_iTableSeatCount; i++)
    {
        int client = g_iTableOrder[i];
        if (!IsClientAtTable(client))
        {
            continue;
        }

        if (!US_TakeCredits(client, g_iTableBet[client]))
        {
            removed[removedCount++] = client;
            continue;
        }

        g_bTableStakeTaken[client] = true;
    }

    for (int i = 0; i < removedCount; i++)
    {
        int client = removed[i];
        if (!IsClientAtTable(client))
        {
            continue;
        }

        ChatError(client, "%T", "Error Take Credits", client);
        PrintToChatAll("%s %t", BJ_CHAT_TAG, "Table Removed No Credits", client);
        TableRemoveSeat(client);
    }

    TableRebuildOrder();

    if (g_iTableSeatCount < BJ_TABLE_MIN_PLAYERS)
    {
        for (int i = 0; i < g_iTableSeatCount; i++)
        {
            int client = g_iTableOrder[i];
            if (!IsClientAtTable(client) || !g_bTableStakeTaken[client])
            {
                continue;
            }

            US_AddCredits(client, g_iTableBet[client], true);
            g_bTableStakeTaken[client] = false;
        }

        g_iTableState = (g_iTableSeatCount > 0) ? BJTABLE_WAITING : BJTABLE_IDLE;
        TableAnnounceState();
        return;
    }

    g_iTableState = BJTABLE_PLAYING;

    for (int i = 0; i < g_iTableSeatCount; i++)
    {
        int client = g_iTableOrder[i];
        if (!IsClientAtTable(client))
        {
            continue;
        }

        g_bTableStood[client] = false;
        g_bTableBusted[client] = false;
        g_iTableCount[client] = 0;
        g_iTableCards[client][g_iTableCount[client]++] = DrawCard();
        g_iTableCards[client][g_iTableCount[client]++] = DrawCard();
        PlayClientSound(client, BJ_SOUND_BET);
    }

    g_iTableDealerCards[g_iTableDealerCount++] = DrawCard();
    g_iTableDealerCards[g_iTableDealerCount++] = DrawCard();

        PrintToChatAll("%s %t", BJ_CHAT_TAG, "Table Round Started");

    g_iTableCurrentTurn = -1;
    TableAdvanceTurn();
}

void TableBeginTurn()
{
    TableCancelTurnTimer();

    int client = GetTableCurrentClient();
    if (!IsValidClient(client) || !IsClientAtTable(client))
    {
        TableAdvanceTurn();
        return;
    }

    int value = GetBestHandValue(g_iTableCards[client], g_iTableCount[client]);
    if (value >= 21)
    {
        g_bTableStood[client] = true;
        if (value > 21)
        {
            g_bTableBusted[client] = true;
        }
        TableAdvanceTurn();
        return;
    }

    PrintToChatAll("%s %t", BJ_CHAT_TAG, "Table Turn Notice", client);
    g_hTableTurnTimer = CreateTimer(BJ_TABLE_TURN_TIME, Timer_TableTurn, GetClientUserId(client));
    TableAnnounceState();
}

public Action Timer_TableTurn(Handle timer, any userId)
{
    g_hTableTurnTimer = null;
    int client = GetClientOfUserId(userId);

    if (!IsValidClient(client) || !IsTableTurn(client))
    {
        return Plugin_Stop;
    }

    ChatNotice(client, "%T", "Table Timeout", client);
    TablePlayerStand(client);
    return Plugin_Stop;
}

void TableAdvanceTurn()
{
    TableCancelTurnTimer();

    bool anyAlive = false;
    for (int i = 0; i < g_iTableSeatCount; i++)
    {
        int c = g_iTableOrder[i];
        if (IsClientAtTable(c) && !g_bTableStood[c] && !g_bTableBusted[c])
        {
            anyAlive = true;
            break;
        }
    }

    if (!anyAlive)
    {
        ResolveTableRound();
        return;
    }

    int start = g_iTableCurrentTurn + 1;
    if (start < 0)
    {
        start = 0;
    }

    for (int step = 0; step < g_iTableSeatCount; step++)
    {
        int idx = (start + step) % g_iTableSeatCount;
        int client = g_iTableOrder[idx];
        if (IsClientAtTable(client) && !g_bTableStood[client] && !g_bTableBusted[client])
        {
            g_iTableCurrentTurn = idx;
            TableBeginTurn();
            return;
        }
    }

    ResolveTableRound();
}

void TablePlayerHit(int client)
{
    if (!CheckActionCooldown(client))
    {
        return;
    }

    if (!IsTableTurn(client))
    {
        ShowTableMenu(client);
        return;
    }

    if (g_iTableCount[client] < BJ_MAX_HAND_CARDS)
    {
        g_iTableCards[client][g_iTableCount[client]++] = DrawCard();
        PlayClientSound(client, BJ_SOUND_CARD);
    }

    int value = GetBestHandValue(g_iTableCards[client], g_iTableCount[client]);
    if (value > 21)
    {
        g_bTableBusted[client] = true;
        g_bTableStood[client] = true;
        ChatError(client, "%T", "Table Bust", client);
        TableAdvanceTurn();
        return;
    }

    if (value == 21)
    {
        g_bTableStood[client] = true;
        ChatSuccess(client, "%T", "Table TwentyOne", client);
        TableAdvanceTurn();
        return;
    }

    ShowTableMenu(client);
    TableAnnounceState();
}

void TablePlayerStand(int client)
{
    if (!IsTableTurn(client))
    {
        ShowTableMenu(client);
        return;
    }

    g_bTableStood[client] = true;
    TableAdvanceTurn();
}

void ResolveTableRound()
{
    g_iTableState = BJTABLE_RESOLVING;
    TableCancelTurnTimer();

    for (;;)
    {
        int value = GetBestHandValue(g_iTableDealerCards, g_iTableDealerCount);
        bool soft = HandIsSoft(g_iTableDealerCards, g_iTableDealerCount);

        if (value < 17 || (value == 17 && soft && gCvarDealerHitSoft17.BoolValue))
        {
            if (g_iTableDealerCount < BJ_MAX_HAND_CARDS)
            {
                g_iTableDealerCards[g_iTableDealerCount++] = DrawCard();
            }
        }
        else
        {
            break;
        }
    }

    int dealerValue = GetBestHandValue(g_iTableDealerCards, g_iTableDealerCount);
    bool dealerNatural = IsNaturalBlackjack(g_iTableDealerCards, g_iTableDealerCount);

    for (int i = 0; i < g_iTableSeatCount; i++)
    {
        int client = g_iTableOrder[i];
        if (!IsClientAtTable(client) || !IsValidClient(client))
        {
            continue;
        }

        int bet = g_iTableBet[client];
        int value = GetBestHandValue(g_iTableCards[client], g_iTableCount[client]);
        bool natural = IsNaturalBlackjack(g_iTableCards[client], g_iTableCount[client]);
        char hand[128], dealer[128], betText[32];
        BuildTablePlayerHandString(client, hand, sizeof(hand));
        BuildTableDealerHandString(true, dealer, sizeof(dealer));
        FormatCredits(bet, betText, sizeof(betText));

        if (g_bTableBusted[client] || value > 21)
        {
            ChatError(client, "%T", "Table Result Lose", client, betText);
            ChatInfo(client, "%T", "Table Hand Summary", client, dealer, hand);
            RecordSingleStats(client, -bet, false, false, false);
            { char hist[192]; Format(hist, sizeof(hist), "%T", "History Table Lose", client, betText); AddHistory(client, "%s", hist); }
            PlayClientSound(client, BJ_SOUND_LOSE);
            continue;
        }

        if (natural && !dealerNatural)
        {
            int payout = CalculateBlackjackPayout(bet);
            US_AddCredits(client, payout, true);
            int net = payout - bet;
            char netText[32]; FormatSignedCredits(net, netText, sizeof(netText));
            ChatSuccess(client, "%T", "Table Result Natural", client, netText);
            ChatInfo(client, "%T", "Table Hand Summary", client, dealer, hand);
            RecordSingleStats(client, net, true, false, true);
            { char hist[192]; Format(hist, sizeof(hist), "%T", "History Table Blackjack", client, netText); AddHistory(client, "%s", hist); }
            PlayClientSound(client, BJ_SOUND_WIN);
            MaybeAnnounceNaturalBlackjack(client);
            MaybeAnnounceBigWin(client, net);
            MaybeAnnounceStreak(client);
            continue;
        }

        if (dealerValue > 21 || value > dealerValue)
        {
            US_AddCredits(client, bet * 2, true);
            ChatSuccess(client, "%T", "Table Result Win", client, betText);
            ChatInfo(client, "%T", "Table Hand Summary", client, dealer, hand);
            RecordSingleStats(client, bet, true, false, false);
            { char hist[192]; Format(hist, sizeof(hist), "%T", "History Table Win", client, betText); AddHistory(client, "%s", hist); }
            PlayClientSound(client, BJ_SOUND_WIN);
            MaybeAnnounceBigWin(client, bet);
            MaybeAnnounceStreak(client);
        }
        else if (value == dealerValue)
        {
            US_AddCredits(client, bet, true);
            ChatNotice(client, "%T", "Table Result Push", client);
            ChatInfo(client, "%T", "Table Hand Summary", client, dealer, hand);
            RecordSingleStats(client, 0, false, true, false);
            { char hist[192]; Format(hist, sizeof(hist), "%T", "History Table Push", client); AddHistory(client, "%s", hist); }
            PlayClientSound(client, BJ_SOUND_PUSH);
        }
        else
        {
            ChatError(client, "%T", "Table Result Lose", client, betText);
            ChatInfo(client, "%T", "Table Hand Summary", client, dealer, hand);
            RecordSingleStats(client, -bet, false, false, false);
            { char hist[192]; Format(hist, sizeof(hist), "%T", "History Table Lose", client, betText); AddHistory(client, "%s", hist); }
            PlayClientSound(client, BJ_SOUND_LOSE);
        }
    }

    PrintToChatAll("%s %t", BJ_CHAT_TAG, "Table Round End");

    int reopen[BJ_TABLE_MAX_PLAYERS];
    int reopenCount = 0;
    for (int i = 0; i < g_iTableSeatCount; i++)
    {
        int client = g_iTableOrder[i];
        if (IsValidClient(client))
        {
            reopen[reopenCount++] = GetClientUserId(client);
        }
    }

    TableResetAll();

    for (int i = 0; i < reopenCount; i++)
    {
        int client = GetClientOfUserId(reopen[i]);
        if (IsValidClient(client))
        {
            RequestShowMainMenu(client);
        }
    }
}

void TableClientDisconnected(int client)
{
    if (!IsClientAtTable(client))
    {
        return;
    }

    if (g_iTableState == BJTABLE_WAITING)
    {
        g_bTableSeated[client] = false;
        g_bTableStakeTaken[client] = false;
        g_iTableBet[client] = 0;
        g_iTableCount[client] = 0;
        g_iMode[client] = BJMODE_NONE;
        TableRebuildOrder();
        if (TablePlayerCount() < BJ_TABLE_MIN_PLAYERS)
        {
            TableCancelStartTimer();
        }
        if (TablePlayerCount() <= 0)
        {
            TableResetAll();
        }
        return;
    }

    bool wasCurrent = (client == GetTableCurrentClient());

    if (g_iTableState == BJTABLE_PLAYING || g_iTableState == BJTABLE_RESOLVING)
    {
        g_bTableStood[client] = true;
        g_bTableBusted[client] = true;
    }

    TableRemoveSeat(client);
    TableRebuildOrder();

    if (TablePlayerCount() <= 0)
    {
        TableResetAll();
        return;
    }

    if (g_iTableState == BJTABLE_WAITING)
    {
        if (TablePlayerCount() < BJ_TABLE_MIN_PLAYERS)
        {
            TableCancelStartTimer();
        }
        TableAnnounceState();
        return;
    }

    if (wasCurrent)
    {
        g_iTableCurrentTurn = -1;
        TableAdvanceTurn();
    }
    else
    {
        TableAnnounceState();
    }
}


void ShowStatsMenu(int client)
{
    Menu menu = new Menu(MenuHandler_StatsMenu);

    char title[512], sProfit[32];
    FormatSignedCredits(g_iStatProfit[client], sProfit, sizeof(sProfit));
    int winRate = (g_iStatGames[client] > 0) ? RoundToFloor(float(g_iStatWins[client]) * 100.0 / float(g_iStatGames[client])) : 0;
    Format(title, sizeof(title), "%T", "Stats Title", client, g_iStatGames[client], g_iStatWins[client], g_iStatLosses[client], g_iStatPushes[client], g_iStatBlackjacks[client], sProfit, g_iWinStreak[client], g_iBestWinStreak[client], winRate);
    menu.SetTitle(title);

    { char text[128]; GetPhrase(client, "Stats Hint", text, sizeof(text)); menu.AddItem("hint", text, ITEMDRAW_DISABLED); }
    menu.ExitBackButton = true;
    menu.Display(client, BJ_MENU_TIME);
}

public int MenuHandler_StatsMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        if (g_iMode[client] == BJMODE_SINGLE)
        {
            ShowSingleGameMenu(client);
        }
        else if (g_iMode[client] == BJMODE_PVP)
        {
            ShowPvPMenu(client);
        }
        else if (g_iMode[client] == BJMODE_TABLE)
        {
            ShowTableMenu(client);
        }
        else
        {
            ShowMainMenu(client);
        }
    }

    return 0;
}

void ShowHistoryMenu(int client)
{
    Menu menu = new Menu(MenuHandler_HistoryMenu);
    { char text[128]; GetPhrase(client, "History Title", text, sizeof(text)); menu.SetTitle(text); }

    if (g_iHistoryCount[client] <= 0)
    {
        { char text[128]; GetPhrase(client, "History Empty", text, sizeof(text)); menu.AddItem("none", text, ITEMDRAW_DISABLED); }
    }
    else
    {
        for (int i = 0; i < g_iHistoryCount[client]; i++)
        {
            char idx[8];
            IntToString(i, idx, sizeof(idx));
            menu.AddItem(idx, g_sResultHistory[client][i], ITEMDRAW_DISABLED);
        }
    }

    menu.ExitBackButton = true;
    menu.Display(client, BJ_MENU_TIME);
}

public int MenuHandler_HistoryMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        if (g_iMode[client] == BJMODE_SINGLE)
        {
            ShowSingleGameMenu(client);
        }
        else if (g_iMode[client] == BJMODE_PVP)
        {
            ShowPvPMenu(client);
        }
        else if (g_iMode[client] == BJMODE_TABLE)
        {
            ShowTableMenu(client);
        }
        else
        {
            ShowMainMenu(client);
        }
    }

    return 0;
}

int GetActiveHand(int client)
{
    if (g_bHasSplit[client] && g_bPlayingSplitHand[client])
    {
        return 1;
    }
    return 0;
}

void UpdateSplitAvailability(int client)
{
    g_bCanSplit[client] = false;

    if (g_bHasSplit[client] || g_iPlayerCount[client][0] != 2)
    {
        return;
    }

    int cardA = g_iPlayerCards[client][0][0];
    int cardB = g_iPlayerCards[client][0][1];

    if (GetCardBlackjackValue(cardA) == GetCardBlackjackValue(cardB) && US_GetCredits(client) >= g_iBet[client])
    {
        g_bCanSplit[client] = true;
    }
}

bool CanShowDouble(int client)
{
    int hand = GetActiveHand(client);
    return g_bCanDouble[client] && !g_bUsedDouble[client] && US_GetCredits(client) >= g_iBet[client] && g_iPlayerCount[client][hand] == 2;
}

bool CanShowSplit(int client)
{
    return g_bCanSplit[client] && !g_bHasSplit[client] && g_iPlayerCount[client][0] == 2;
}

bool CheckOpenCooldown(int client)
{
    float now = GetGameTime();
    if (now < g_fNextOpenCmd[client])
    {
        return false;
    }

    g_fNextOpenCmd[client] = now + gCvarCommandCooldown.FloatValue;
    return true;
}

bool CheckActionCooldown(int client)
{
    float now = GetGameTime();
    if (now < g_fNextAction[client])
    {
        Chat(client, "%T", "Cooldown Action", client);
        return false;
    }

    g_fNextAction[client] = now + gCvarActionCooldown.FloatValue;
    return true;
}

void PlayClientSound(int client, const char[] sample)
{
    if (!gCvarEnableSounds.BoolValue || !IsValidClient(client))
    {
        return;
    }

    EmitSoundToClient(client, sample, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL);
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

void GetPhrase(int client, const char[] phrase, char[] buffer, int maxlen)
{
    if (TranslationPhraseExists(phrase))
    {
        Format(buffer, maxlen, "%T", phrase, client);
    }
    else
    {
        strcopy(buffer, maxlen, phrase);
    }
}


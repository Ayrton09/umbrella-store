#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <umbrella_store>
#include <umbrella_store_module_utils>
#include <multicolors>

#define JP_TAG " {green}[Umbrella Store]{default}"
#define JP_CASINO_ID "jackpot"
#define JP_MAX_CREDITS 2000000000

enum JackpotState
{
    JP_Idle = 0,
    JP_Open
}

ConVar gCvarEnabled;
ConVar gCvarMinEntry;
ConVar gCvarMaxEntry;
ConVar gCvarRoundTime;
ConVar gCvarMinPlayers;
ConVar gCvarRakePercent;
ConVar gCvarWinSound;

JackpotState g_State = JP_Idle;
int g_iPot = 0;
int g_iContributors = 0;
int g_iContribution[MAXPLAYERS + 1];
Handle g_hRoundTimer = null;
bool g_bRegistered = false;
bool g_bResolving = false;   // guards against reentrant joins while paying out

public Plugin myinfo =
{
    name = "[Umbrella Store] Casino - Jackpot",
    author = "Ayrton09",
    description = "Bote multijugador para Umbrella Store",
    version = "1.5.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store_jackpot.phrases");

    RegConsoleCmd("sm_jackpot", Command_Jackpot);
    RegConsoleCmd("sm_jp", Command_Jackpot);
    RegConsoleCmd("sm_bote", Command_Jackpot);

    gCvarEnabled     = CreateConVar("umbrella_store_jackpot_enabled", "1", "Enable the jackpot module.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarMinEntry    = CreateConVar("umbrella_store_jackpot_min_entry", "100", "Minimum credits per entry.", FCVAR_NONE, true, 1.0);
    gCvarMaxEntry    = CreateConVar("umbrella_store_jackpot_max_entry", "100000", "Maximum total credits a player can put in one round. 0 = no limit.", FCVAR_NONE, true, 0.0);
    gCvarRoundTime   = CreateConVar("umbrella_store_jackpot_round_time", "30.0", "Seconds the pot stays open after the first entry.", FCVAR_NONE, true, 5.0, true, 300.0);
    gCvarMinPlayers  = CreateConVar("umbrella_store_jackpot_min_players", "2", "Minimum distinct players for the round to pay out.", FCVAR_NONE, true, 2.0);
    gCvarRakePercent = CreateConVar("umbrella_store_jackpot_rake_percent", "0", "House cut percent taken from the pot.", FCVAR_NONE, true, 0.0, true, 50.0);
    gCvarWinSound    = CreateConVar("umbrella_store_jackpot_win_sound", "items/itempickup.wav", "Sound played to the winner.");

    AutoExecConfig(true, "umbrella_store_jackpot");
}

public void OnConfigsExecuted()
{
    PrecacheConfiguredSound(gCvarWinSound);
    RegisterCasinoEntry();
}

public void OnMapStart()
{
    PrecacheConfiguredSound(gCvarWinSound);
}

public void OnMapEnd()
{
    // Refund everyone if a round is still open across a map change.
    if (g_State == JP_Open)
    {
        RefundAll();
        ResetRound();
    }
}

public void OnAllPluginsLoaded()
{
    RegisterCasinoEntry();
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "umbrella_store"))
    {
        RegisterCasinoEntry();
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "umbrella_store"))
    {
        g_bRegistered = false;
    }
}

public void OnPluginEnd()
{
    if (g_State == JP_Open)
    {
        RefundAll();
        ResetRound();
    }

    if (g_bRegistered && LibraryExists("umbrella_store"))
    {
        US_Casino_Unregister(JP_CASINO_ID);
    }
    g_bRegistered = false;
}

public void OnClientPutInServer(int client)
{
    // Defensive: never inherit a previous occupant's contribution on this slot.
    g_iContribution[client] = 0;
}

public void OnClientDisconnect(int client)
{
    // A player who leaves an open round gets their contribution back so credits
    // are never lost; this keeps g_iPot equal to the connected contributors' sum.
    if (g_State == JP_Open && g_iContribution[client] > 0)
    {
        int refund = g_iContribution[client];
        g_iContribution[client] = 0;
        g_iPot -= refund;
        g_iContributors--;
        if (!US_AddCredits(client, refund, false))
        {
            // Only possible if the player sits at the credit cap; the entry cannot
            // be returned. Logged rather than failing silently. The pot invariant
            // (g_iPot == sum of connected contributions) is preserved.
            LogError("[Umbrella Store] Jackpot could not refund %d to disconnecting client %d (at credit cap).", refund, client);
        }

        if (g_iContributors <= 0)
        {
            ResetRound();
        }
    }
    else
    {
        g_iContribution[client] = 0;
    }
}

void RegisterCasinoEntry()
{
    if (LibraryExists("umbrella_store"))
    {
        char title[64];
        Format(title, sizeof(title), "%T", "JP Casino Title", LANG_SERVER);
        if (US_Casino_Register(JP_CASINO_ID, title, "sm_jackpot"))
        {
            g_bRegistered = true;
        }
    }
}

public Action Command_Jackpot(int client, int args)
{
    if (!USM_IsValidClient(client))
    {
        return Plugin_Handled;
    }

    if (!gCvarEnabled.BoolValue || !US_IsEnabled() || !US_IsLoaded(client))
    {
        JP_Print(client, "%t", "JP Disabled");
        return Plugin_Handled;
    }

    ShowJackpotMenu(client);
    return Plugin_Handled;
}

void ShowJackpotMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Jackpot);

    char title[160];
    int secondsLeft = 0;
    if (g_State == JP_Open && g_hRoundTimer != null)
    {
        secondsLeft = GetRoundSecondsLeft();
    }

    Format(title, sizeof(title), "%T", "JP Menu Title", client, g_iPot, g_iContribution[client], secondsLeft, US_GetCredits(client));
    menu.SetTitle(title);

    AddEntryOptions(menu, client);

    if (menu.ItemCount == 0)
    {
        delete menu;
        JP_Print(client, "%t", "JP Not Enough");
        return;
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

void AddEntryOptions(Menu menu, int client)
{
    int credits = US_GetCredits(client);
    int minEntry = gCvarMinEntry.IntValue;
    int maxEntry = gCvarMaxEntry.IntValue;
    int already = g_iContribution[client];

    int ladder[6];
    ladder[0] = minEntry;
    ladder[1] = 500;
    ladder[2] = 1000;
    ladder[3] = 5000;
    ladder[4] = 10000;
    ladder[5] = 50000;

    int lastAdded = 0;
    for (int i = 0; i < sizeof(ladder); i++)
    {
        int amount = ladder[i];
        if (amount < minEntry || amount <= lastAdded || amount > credits)
        {
            continue;
        }
        // Respect the per-round per-player cap (total contribution).
        if (maxEntry > 0 && already + amount > maxEntry)
        {
            continue;
        }

        char info[16], label[32];
        IntToString(amount, info, sizeof(info));
        Format(label, sizeof(label), "%d", amount);
        menu.AddItem(info, label);
        lastAdded = amount;
    }
}

public int MenuHandler_Jackpot(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select && USM_IsValidClient(param1))
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        JoinJackpot(param1, StringToInt(info));
    }
    return 0;
}

void JoinJackpot(int client, int amount)
{
    if (!gCvarEnabled.BoolValue || !US_IsEnabled() || !US_IsLoaded(client))
    {
        JP_Print(client, "%t", "JP Disabled");
        return;
    }

    // Reject entries while a round is being resolved/paid out.
    if (g_bResolving)
    {
        return;
    }

    int minEntry = gCvarMinEntry.IntValue;
    int maxEntry = gCvarMaxEntry.IntValue;

    if (amount < minEntry)
    {
        JP_Print(client, "%t", "JP Min Entry", minEntry);
        return;
    }

    if (maxEntry > 0 && g_iContribution[client] + amount > maxEntry)
    {
        JP_Print(client, "%t", "JP Max Entry", maxEntry);
        return;
    }

    if (US_GetCredits(client) < amount)
    {
        JP_Print(client, "%t", "JP Not Enough");
        return;
    }

    if (!US_TakeCredits(client, amount))
    {
        JP_Print(client, "%t", "JP Transaction Failed");
        return;
    }

    bool firstEntryForClient = (g_iContribution[client] == 0);
    g_iContribution[client] += amount;
    g_iPot += amount;
    if (firstEntryForClient)
    {
        g_iContributors++;
    }

    if (g_State == JP_Idle)
    {
        StartRound();
    }

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    CPrintToChatAll("%s %t", JP_TAG, "JP Joined Broadcast", name, amount, g_iPot);
}

void StartRound()
{
    g_State = JP_Open;
    if (g_hRoundTimer != null)
    {
        KillTimer(g_hRoundTimer);
    }
    g_hRoundTimer = CreateTimer(gCvarRoundTime.FloatValue, Timer_RoundEnd, _, TIMER_FLAG_NO_MAPCHANGE);

    CPrintToChatAll("%s %t", JP_TAG, "JP Round Started", RoundToNearest(gCvarRoundTime.FloatValue));
}

public Action Timer_RoundEnd(Handle timer, any data)
{
    g_hRoundTimer = null;
    ResolveJackpot();
    return Plugin_Stop;
}

void ResolveJackpot()
{
    if (g_State != JP_Open)
    {
        return;
    }

    // Block any reentrant JoinJackpot triggered by credit forwards during payout.
    g_bResolving = true;

    if (g_iContributors < gCvarMinPlayers.IntValue || g_iPot <= 0)
    {
        CPrintToChatAll("%s %t", JP_TAG, "JP Not Enough Players");
        RefundAll();
        ResetRound();
        return;
    }

    int winner = PickWeightedWinner();
    if (winner < 1)
    {
        // No eligible connected winner (should not happen); refund.
        RefundAll();
        ResetRound();
        return;
    }

    int pot = g_iPot;
    int rake = RoundToFloor(float(pot) * gCvarRakePercent.FloatValue / 100.0);
    if (rake < 0)
    {
        rake = 0;
    }
    int payout = pot - rake;
    if (payout < 0)
    {
        payout = 0;
    }
    if (payout > JP_MAX_CREDITS)
    {
        payout = JP_MAX_CREDITS;
    }

    char winnerName[MAX_NAME_LENGTH];
    GetClientName(winner, winnerName, sizeof(winnerName));

    if (payout > 0 && !US_AddCredits(winner, payout, false))
    {
        // Could not pay the winner; refund everyone instead of losing credits.
        LogError("[Umbrella Store] Jackpot failed to pay %d to client %d, refunding pot.", payout, winner);
        RefundAll();
        ResetRound();
        return;
    }

    US_AddStat(winner, "jackpot_wins", 1);

    EmitConfiguredSound(winner, gCvarWinSound);
    CPrintToChatAll("%s %t", JP_TAG, "JP Winner Broadcast", winnerName, payout, g_iContributors);

    ResetRound();
}

int PickWeightedWinner()
{
    if (g_iPot <= 0)
    {
        return -1;
    }

    int roll = GetRandomInt(0, g_iPot - 1);
    int acc = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_iContribution[client] <= 0 || !USM_IsValidClient(client))
        {
            continue;
        }

        acc += g_iContribution[client];
        if (roll < acc)
        {
            return client;
        }
    }

    // Rounding safety: return the last eligible contributor.
    for (int client = MaxClients; client >= 1; client--)
    {
        if (g_iContribution[client] > 0 && USM_IsValidClient(client))
        {
            return client;
        }
    }

    return -1;
}

void RefundAll()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_iContribution[client] > 0)
        {
            if (USM_IsValidClient(client))
            {
                if (US_AddCredits(client, g_iContribution[client], false))
                {
                    JP_Print(client, "%t", "JP Refunded", g_iContribution[client]);
                }
                else
                {
                    LogError("[Umbrella Store] Jackpot could not refund %d to client %d (at credit cap).", g_iContribution[client], client);
                }
            }
            g_iContribution[client] = 0;
        }
    }
}

void ResetRound()
{
    if (g_hRoundTimer != null)
    {
        KillTimer(g_hRoundTimer);
        g_hRoundTimer = null;
    }

    for (int client = 0; client <= MaxClients; client++)
    {
        g_iContribution[client] = 0;
    }

    g_iPot = 0;
    g_iContributors = 0;
    g_State = JP_Idle;
    g_bResolving = false;
}

int GetRoundSecondsLeft()
{
    // Approximate remaining time for display purposes only.
    return RoundToNearest(gCvarRoundTime.FloatValue);
}

void PrecacheConfiguredSound(ConVar cvar)
{
    if (cvar == null)
    {
        return;
    }

    char path[PLATFORM_MAX_PATH];
    cvar.GetString(path, sizeof(path));
    if (path[0] == '\0')
    {
        return;
    }

    char full[PLATFORM_MAX_PATH];
    Format(full, sizeof(full), "sound/%s", path);
    if (FileExists(full, true))
    {
        PrecacheSound(path, true);
    }
}

void EmitConfiguredSound(int client, ConVar cvar)
{
    if (cvar == null || !USM_IsValidClient(client))
    {
        return;
    }

    char path[PLATFORM_MAX_PATH];
    cvar.GetString(path, sizeof(path));
    if (path[0] != '\0')
    {
        EmitSoundToClient(client, path);
    }
}

void JP_Print(int client, const char[] format, any ...)
{
    if (!USM_IsValidClient(client))
    {
        return;
    }

    char buffer[192];
    SetGlobalTransTarget(client);
    VFormat(buffer, sizeof(buffer), format, 3);
    CPrintToChat(client, "%s %s", JP_TAG, buffer);
}

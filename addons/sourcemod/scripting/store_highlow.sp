#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <umbrella_store>
#include <umbrella_store_module_utils>
#include <multicolors>

#define HL_TAG " {green}[Umbrella Store]{default}"
#define HL_CASINO_ID "highlow"
#define HL_MIN_CARD 1
#define HL_MAX_CARD 13

ConVar gCvarEnabled;
ConVar gCvarMinBet;
ConVar gCvarMaxBet;
ConVar gCvarCooldown;
ConVar gCvarMultiplier;
ConVar gCvarWinSound;
ConVar gCvarLoseSound;

float g_fNextUse[MAXPLAYERS + 1];
int g_iPendingBet[MAXPLAYERS + 1];
int g_iBaseCard[MAXPLAYERS + 1];
bool g_bStaked[MAXPLAYERS + 1];   // bet already charged for the current hand
bool g_bRegistered = false;

public Plugin myinfo =
{
    name = "[Umbrella Store] Casino - High or Low",
    author = "Ayrton09",
    description = "Mayor o menor contra la casa para Umbrella Store",
    version = "1.5.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store_highlow.phrases");

    RegConsoleCmd("sm_highlow", Command_HighLow);
    RegConsoleCmd("sm_hilo", Command_HighLow);
    RegConsoleCmd("sm_mayoromenor", Command_HighLow);

    gCvarEnabled    = CreateConVar("umbrella_store_highlow_enabled", "1", "Enable the high-or-low module.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarMinBet     = CreateConVar("umbrella_store_highlow_min_bet", "50", "Minimum bet.", FCVAR_NONE, true, 1.0);
    gCvarMaxBet     = CreateConVar("umbrella_store_highlow_max_bet", "1000000", "Maximum bet. 0 = no limit.", FCVAR_NONE, true, 0.0);
    gCvarCooldown   = CreateConVar("umbrella_store_highlow_cooldown", "2.0", "Cooldown between rounds.", FCVAR_NONE, true, 0.0);
    gCvarMultiplier = CreateConVar("umbrella_store_highlow_multiplier", "1.9", "Payout multiplier on a correct guess.", FCVAR_NONE, true, 1.0);
    gCvarWinSound   = CreateConVar("umbrella_store_highlow_win_sound", "items/itempickup.wav", "Sound played on win.");
    gCvarLoseSound  = CreateConVar("umbrella_store_highlow_lose_sound", "buttons/button10.wav", "Sound played on loss.");

    AutoExecConfig(true, "umbrella_store_highlow");
}

public void OnConfigsExecuted()
{
    PrecacheConfiguredSound(gCvarWinSound);
    PrecacheConfiguredSound(gCvarLoseSound);
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
    if (g_bRegistered && LibraryExists("umbrella_store"))
    {
        US_Casino_Unregister(HL_CASINO_ID);
    }
    g_bRegistered = false;
}

public void OnClientDisconnect(int client)
{
    // A committed-but-unguessed hand is forfeited (the base card was already
    // seen); the stake is not refunded, which is what removes the re-roll edge.
    g_fNextUse[client] = 0.0;
    g_iPendingBet[client] = 0;
    g_iBaseCard[client] = 0;
    g_bStaked[client] = false;
}

void RegisterCasinoEntry()
{
    if (LibraryExists("umbrella_store"))
    {
        char title[64];
        Format(title, sizeof(title), "%T", "HL Casino Title", LANG_SERVER);
        if (US_Casino_Register(HL_CASINO_ID, title, "sm_highlow"))
        {
            g_bRegistered = true;
        }
    }
}

public Action Command_HighLow(int client, int args)
{
    if (!USM_IsValidClient(client))
    {
        return Plugin_Handled;
    }

    if (!gCvarEnabled.BoolValue || !US_IsEnabled() || !US_IsLoaded(client))
    {
        HL_Print(client, "%t", "HL Disabled");
        return Plugin_Handled;
    }

    ShowBetMenu(client);
    return Plugin_Handled;
}

void ShowBetMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Bet);
    char title[96];
    Format(title, sizeof(title), "%T", "HL Bet Title", client, US_GetCredits(client));
    menu.SetTitle(title);

    AddBetOptions(menu, client);

    if (menu.ItemCount == 0)
    {
        delete menu;
        HL_Print(client, "%t", "HL Not Enough");
        return;
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

void AddBetOptions(Menu menu, int client)
{
    int credits = US_GetCredits(client);
    int minBet = gCvarMinBet.IntValue;
    int maxBet = gCvarMaxBet.IntValue;

    int ladder[6];
    ladder[0] = minBet;
    ladder[1] = 100;
    ladder[2] = 500;
    ladder[3] = 1000;
    ladder[4] = 5000;
    ladder[5] = 10000;

    int lastAdded = 0;
    for (int i = 0; i < sizeof(ladder); i++)
    {
        int amount = ladder[i];
        if (amount < minBet || amount <= lastAdded || amount > credits)
        {
            continue;
        }
        if (maxBet > 0 && amount > maxBet)
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

public int MenuHandler_Bet(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select && USM_IsValidClient(param1))
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        int bet = StringToInt(info);
        if (!ValidateBet(param1, bet))
        {
            ShowBetMenu(param1);
            return 0;
        }

        if (GetGameTime() < g_fNextUse[param1])
        {
            HL_Print(param1, "%t", "HL Cooldown");
            return 0;
        }

        // Charge the stake when the hand starts (and the base card is revealed),
        // not at guess time. This makes peeking at the base card cost the bet, so
        // a player cannot back out and re-roll a favorable card for free.
        if (!US_TakeCredits(param1, bet))
        {
            HL_Print(param1, "%t", "HL Transaction Failed");
            return 0;
        }

        g_iPendingBet[param1] = bet;
        g_bStaked[param1] = true;
        g_fNextUse[param1] = GetGameTime() + gCvarCooldown.FloatValue;
        // Base card avoids the extremes so both guesses stay viable.
        g_iBaseCard[param1] = GetRandomInt(HL_MIN_CARD + 1, HL_MAX_CARD - 1);
        ShowGuessMenu(param1);
    }
    return 0;
}

void ShowGuessMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Guess);
    char title[128];
    Format(title, sizeof(title), "%T", "HL Guess Title", client, g_iBaseCard[client], g_iPendingBet[client]);
    menu.SetTitle(title);

    char higher[64], lower[64];
    Format(higher, sizeof(higher), "%T", "HL Option Higher", client, gCvarMultiplier.FloatValue);
    Format(lower, sizeof(lower), "%T", "HL Option Lower", client, gCvarMultiplier.FloatValue);

    menu.AddItem("high", higher);
    menu.AddItem("low", lower);
    // No back button: the bet is already committed; backing out forfeits it.
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Guess(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel)
    {
        // Closing the menu after the base card was shown forfeits the committed bet.
        if (g_bStaked[param1])
        {
            ForfeitHighLow(param1);
        }
    }
    else if (action == MenuAction_Select && USM_IsValidClient(param1))
    {
        char info[8];
        menu.GetItem(param2, info, sizeof(info));
        ResolveHighLow(param1, StrEqual(info, "high"));
    }
    return 0;
}

void ResolveHighLow(int client, bool guessHigher)
{
    if (!g_bStaked[client] || g_iBaseCard[client] <= 0)
    {
        ShowBetMenu(client);
        return;
    }

    int bet = g_iPendingBet[client];
    int baseCard = g_iBaseCard[client];

    // The stake was already charged when the hand started; clear committed state.
    g_bStaked[client] = false;
    g_iPendingBet[client] = 0;
    g_iBaseCard[client] = 0;

    if (!gCvarEnabled.BoolValue || !US_IsEnabled() || !US_IsLoaded(client))
    {
        // Game went away mid-hand: refund the committed stake.
        US_AddCredits(client, bet, false);
        HL_Print(client, "%t", "HL Disabled");
        return;
    }

    int nextCard = GetRandomInt(HL_MIN_CARD, HL_MAX_CARD);

    US_AddStat(client, "highlow_games", 1);

    if (nextCard == baseCard)
    {
        // Push: refund the stake.
        if (!US_AddCredits(client, bet, false))
        {
            LogError("[Umbrella Store] HighLow failed to refund push %d to client %d.", bet, client);
            HL_Print(client, "%t", "HL Transaction Failed");
            return;
        }
        HL_Print(client, "%t", "HL Push", baseCard, nextCard);
        return;
    }

    bool win = guessHigher ? (nextCard > baseCard) : (nextCard < baseCard);

    if (win)
    {
        int payout = USM_SafePayout(bet, gCvarMultiplier.FloatValue);
        if (!US_AddCredits(client, payout, false))
        {
            if (!US_AddCredits(client, bet, false))
            {
                LogError("[Umbrella Store] HighLow failed to refund stake %d to client %d.", bet, client);
            }
            HL_Print(client, "%t", "HL Transaction Failed");
            return;
        }

        US_AddStat(client, "highlow_wins", 1);
        US_AddStat(client, "highlow_profit", payout - bet);
        EmitConfiguredSound(client, gCvarWinSound);
        HL_Print(client, "%t", "HL Win", baseCard, nextCard, payout - bet);
    }
    else
    {
        US_AddStat(client, "highlow_losses", 1);
        US_AddStat(client, "highlow_profit", -bet);
        EmitConfiguredSound(client, gCvarLoseSound);
        HL_Print(client, "%t", "HL Lose", baseCard, nextCard, bet);
    }
}

// Player backed out / disconnected after the base card was shown: the committed
// stake is lost (already charged, not refunded). This is what prevents free
// re-rolling of a favorable base card.
void ForfeitHighLow(int client)
{
    int bet = g_iPendingBet[client];
    g_bStaked[client] = false;
    g_iPendingBet[client] = 0;
    g_iBaseCard[client] = 0;

    US_AddStat(client, "highlow_games", 1);
    US_AddStat(client, "highlow_losses", 1);
    US_AddStat(client, "highlow_profit", -bet);

    if (USM_IsValidClient(client))
    {
        HL_Print(client, "%t", "HL Forfeit", bet);
    }
}

bool ValidateBet(int client, int bet)
{
    int minBet = gCvarMinBet.IntValue;
    int maxBet = gCvarMaxBet.IntValue;

    if (bet <= 0 || bet < minBet)
    {
        HL_Print(client, "%t", "HL Min Bet", minBet);
        return false;
    }

    if (maxBet > 0 && bet > maxBet)
    {
        HL_Print(client, "%t", "HL Max Bet", maxBet);
        return false;
    }

    if (US_GetCredits(client) < bet)
    {
        HL_Print(client, "%t", "HL Not Enough");
        return false;
    }

    return true;
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

void HL_Print(int client, const char[] format, any ...)
{
    if (!USM_IsValidClient(client))
    {
        return;
    }

    char buffer[192];
    SetGlobalTransTarget(client);
    VFormat(buffer, sizeof(buffer), format, 3);
    CPrintToChat(client, "%s %s", HL_TAG, buffer);
}

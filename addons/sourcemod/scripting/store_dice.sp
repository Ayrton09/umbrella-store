#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <umbrella_store>
#include <umbrella_store_module_utils>
#include <multicolors>

#define DICE_TAG " {green}[Umbrella Store]{default}"
#define DICE_CASINO_ID "dice"

enum
{
    Predict_Low = 0,   // sum 2-6
    Predict_Seven,     // sum == 7
    Predict_High       // sum 8-12
}

ConVar gCvarEnabled;
ConVar gCvarMinBet;
ConVar gCvarMaxBet;
ConVar gCvarCooldown;
ConVar gCvarMultLowHigh;
ConVar gCvarMultSeven;
ConVar gCvarWinSound;
ConVar gCvarLoseSound;

float g_fNextUse[MAXPLAYERS + 1];
int g_iPendingBet[MAXPLAYERS + 1];
bool g_bRegistered = false;

public Plugin myinfo =
{
    name = "[Umbrella Store] Casino - Dice",
    author = "Ayrton09",
    description = "Dados (bajo/siete/alto) contra la casa para Umbrella Store",
    version = "1.5.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store_dice.phrases");

    RegConsoleCmd("sm_dice", Command_Dice);
    RegConsoleCmd("sm_dados", Command_Dice);
    RegConsoleCmd("sm_dado", Command_Dice);

    gCvarEnabled     = CreateConVar("umbrella_store_dice_enabled", "1", "Enable the dice module.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarMinBet      = CreateConVar("umbrella_store_dice_min_bet", "50", "Minimum bet.", FCVAR_NONE, true, 1.0);
    gCvarMaxBet      = CreateConVar("umbrella_store_dice_max_bet", "1000000", "Maximum bet. 0 = no limit.", FCVAR_NONE, true, 0.0);
    gCvarCooldown    = CreateConVar("umbrella_store_dice_cooldown", "2.0", "Cooldown between rolls.", FCVAR_NONE, true, 0.0);
    gCvarMultLowHigh = CreateConVar("umbrella_store_dice_mult_lowhigh", "2.0", "Payout multiplier for low/high wins.", FCVAR_NONE, true, 1.0);
    gCvarMultSeven   = CreateConVar("umbrella_store_dice_mult_seven", "5.0", "Payout multiplier for an exact seven.", FCVAR_NONE, true, 1.0);
    gCvarWinSound    = CreateConVar("umbrella_store_dice_win_sound", "items/itempickup.wav", "Sound played on win.");
    gCvarLoseSound   = CreateConVar("umbrella_store_dice_lose_sound", "buttons/button10.wav", "Sound played on loss.");

    AutoExecConfig(true, "umbrella_store_dice");
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
        US_Casino_Unregister(DICE_CASINO_ID);
    }
    g_bRegistered = false;
}

public void OnClientDisconnect(int client)
{
    g_fNextUse[client] = 0.0;
    g_iPendingBet[client] = 0;
}

void RegisterCasinoEntry()
{
    if (LibraryExists("umbrella_store"))
    {
        char title[64];
        Format(title, sizeof(title), "%T", "Dice Casino Title", LANG_SERVER);
        if (US_Casino_Register(DICE_CASINO_ID, title, "sm_dice"))
        {
            g_bRegistered = true;
        }
    }
}

public Action Command_Dice(int client, int args)
{
    if (!USM_IsValidClient(client))
    {
        return Plugin_Handled;
    }

    if (!gCvarEnabled.BoolValue || !US_IsEnabled() || !US_IsLoaded(client))
    {
        Dice_Print(client, "%t", "Dice Disabled");
        return Plugin_Handled;
    }

    ShowBetMenu(client);
    return Plugin_Handled;
}

void ShowBetMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Bet);
    char title[96];
    Format(title, sizeof(title), "%T", "Dice Bet Title", client, US_GetCredits(client));
    menu.SetTitle(title);

    AddBetOptions(menu, client);

    if (menu.ItemCount == 0)
    {
        delete menu;
        Dice_Print(client, "%t", "Dice Not Enough");
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
        g_iPendingBet[param1] = bet;
        ShowPredictMenu(param1);
    }
    return 0;
}

void ShowPredictMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Predict);
    char title[96];
    Format(title, sizeof(title), "%T", "Dice Predict Title", client, g_iPendingBet[client]);
    menu.SetTitle(title);

    char low[64], seven[64], high[64];
    Format(low, sizeof(low), "%T", "Dice Option Low", client, gCvarMultLowHigh.FloatValue);
    Format(seven, sizeof(seven), "%T", "Dice Option Seven", client, gCvarMultSeven.FloatValue);
    Format(high, sizeof(high), "%T", "Dice Option High", client, gCvarMultLowHigh.FloatValue);

    menu.AddItem("0", low);
    menu.AddItem("1", seven);
    menu.AddItem("2", high);
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Predict(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_ExitBack && USM_IsValidClient(param1))
        {
            ShowBetMenu(param1);
        }
    }
    else if (action == MenuAction_Select && USM_IsValidClient(param1))
    {
        char info[8];
        menu.GetItem(param2, info, sizeof(info));
        ResolveDice(param1, StringToInt(info));
    }
    return 0;
}

void ResolveDice(int client, int prediction)
{
    if (!gCvarEnabled.BoolValue || !US_IsEnabled() || !US_IsLoaded(client))
    {
        Dice_Print(client, "%t", "Dice Disabled");
        return;
    }

    if (GetGameTime() < g_fNextUse[client])
    {
        Dice_Print(client, "%t", "Dice Cooldown");
        return;
    }

    int bet = g_iPendingBet[client];
    if (!ValidateBet(client, bet))
    {
        ShowBetMenu(client);
        return;
    }

    if (!US_TakeCredits(client, bet))
    {
        Dice_Print(client, "%t", "Dice Transaction Failed");
        return;
    }

    g_fNextUse[client] = GetGameTime() + gCvarCooldown.FloatValue;
    g_iPendingBet[client] = 0;

    int d1 = GetRandomInt(1, 6);
    int d2 = GetRandomInt(1, 6);
    int sum = d1 + d2;

    int outcome;       // 0 low, 1 seven, 2 high
    if (sum == 7)
    {
        outcome = Predict_Seven;
    }
    else if (sum < 7)
    {
        outcome = Predict_Low;
    }
    else
    {
        outcome = Predict_High;
    }

    bool win = (outcome == prediction);

    US_AddStat(client, "dice_games", 1);

    if (win)
    {
        float mult = (prediction == Predict_Seven) ? gCvarMultSeven.FloatValue : gCvarMultLowHigh.FloatValue;
        int payout = USM_SafePayout(bet, mult);

        if (!US_AddCredits(client, payout, false))
        {
            // Refund the stake if the payout could not be granted.
            if (!US_AddCredits(client, bet, false))
            {
                LogError("[Umbrella Store] Dice failed to refund stake %d to client %d.", bet, client);
            }
            Dice_Print(client, "%t", "Dice Transaction Failed");
            return;
        }

        US_AddStat(client, "dice_wins", 1);
        US_AddStat(client, "dice_profit", payout - bet);
        EmitConfiguredSound(client, gCvarWinSound);
        Dice_Print(client, "%t", "Dice Win", d1, d2, sum, payout - bet);
    }
    else
    {
        US_AddStat(client, "dice_losses", 1);
        US_AddStat(client, "dice_profit", -bet);
        EmitConfiguredSound(client, gCvarLoseSound);
        Dice_Print(client, "%t", "Dice Lose", d1, d2, sum, bet);
    }
}

bool ValidateBet(int client, int bet)
{
    int minBet = gCvarMinBet.IntValue;
    int maxBet = gCvarMaxBet.IntValue;

    if (bet <= 0 || bet < minBet)
    {
        Dice_Print(client, "%t", "Dice Min Bet", minBet);
        return false;
    }

    if (maxBet > 0 && bet > maxBet)
    {
        Dice_Print(client, "%t", "Dice Max Bet", maxBet);
        return false;
    }

    if (US_GetCredits(client) < bet)
    {
        Dice_Print(client, "%t", "Dice Not Enough");
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

void Dice_Print(int client, const char[] format, any ...)
{
    if (!USM_IsValidClient(client))
    {
        return;
    }

    char buffer[192];
    SetGlobalTransTarget(client);
    VFormat(buffer, sizeof(buffer), format, 3);
    CPrintToChat(client, "%s %s", DICE_TAG, buffer);
}

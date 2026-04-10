#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <umbrella_store>

#define US_CHAT_TAG " \x03[Umbrella Store]\x01"
#define ROULETTE_TAG "\x03[Roulette]\x01"
#define ROULETTE_CASINO_ID "roulette"
#define ROULETTE_MAX_NUMBER 36

static const int g_RouletteWheelOrder[ROULETTE_MAX_NUMBER + 1] =
{
    0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
    5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26
};

enum RouletteBetType
{
    RouletteBet_None = 0,
    RouletteBet_Red,
    RouletteBet_Black,
    RouletteBet_Green,
    RouletteBet_Number
};

public Plugin myinfo =
{
    name = "[Umbrella Store] Casino - Roulette",
    author = "Ayrton09",
    description = "Roulette module for Umbrella Store",
    version = "1.0.0",
    url = ""
};

ConVar gCvarEnabled;
ConVar gCvarMinBet;
ConVar gCvarMaxBet;
ConVar gCvarCooldown;
ConVar gCvarColorMultiplier;
ConVar gCvarGreenMultiplier;
ConVar gCvarNumberMultiplier;
ConVar gCvarAnnounceBigWin;
ConVar gCvarAnnounceThreshold;
ConVar gCvarSpinSound;
ConVar gCvarWinSound;
ConVar gCvarLoseSound;
ConVar gCvarAnimEnabled;
ConVar gCvarAnimMode;
ConVar gCvarAnimSteps;
ConVar gCvarAnimDelayMin;
ConVar gCvarAnimDelayMax;

bool g_bRegistered = false;
float g_fNextUse[MAXPLAYERS + 1];
bool g_bAwaitingCustomBet[MAXPLAYERS + 1];
RouletteBetType g_iPendingType[MAXPLAYERS + 1];
int g_iPendingNumber[MAXPLAYERS + 1];
bool g_bSpinning[MAXPLAYERS + 1];
Handle g_hSpinTimer[MAXPLAYERS + 1];
int g_iSpinStep[MAXPLAYERS + 1];
int g_iSpinTotalSteps[MAXPLAYERS + 1];
RouletteBetType g_iSpinType[MAXPLAYERS + 1];
int g_iSpinSelectedNumber[MAXPLAYERS + 1];
int g_iSpinResult[MAXPLAYERS + 1];
int g_iSpinBet[MAXPLAYERS + 1];
int g_iSpinDisplay[MAXPLAYERS + 1];
int g_iQueuedBetAmount[MAXPLAYERS + 1];

public void OnPluginStart()
{
    LoadTranslations("umbrella_store_roulette.phrases");

    RegConsoleCmd("sm_roulette", Command_Roulette);
    RegConsoleCmd("sm_ruleta", Command_Roulette);
    RegConsoleCmd("sm_ru", Command_Roulette);
    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say_team");
    HookEventEx("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

    gCvarEnabled = CreateConVar("umbrella_store_roulette_enabled", "1", "Enable roulette module.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarMinBet = CreateConVar("umbrella_store_roulette_min_bet", "100", "Minimum roulette bet.", FCVAR_NONE, true, 1.0);
    gCvarMaxBet = CreateConVar("umbrella_store_roulette_max_bet", "1000000", "Maximum roulette bet. 0 = no limit.", FCVAR_NONE, true, 0.0);
    gCvarCooldown = CreateConVar("umbrella_store_roulette_cooldown", "0.4", "Cooldown between roulette actions.", FCVAR_NONE, true, 0.0);
    gCvarColorMultiplier = CreateConVar("umbrella_store_roulette_color_multiplier", "2.0", "Payout multiplier for red/black wins.", FCVAR_NONE, true, 1.0);
    gCvarGreenMultiplier = CreateConVar("umbrella_store_roulette_green_multiplier", "14.0", "Payout multiplier for green wins.", FCVAR_NONE, true, 1.0);
    gCvarNumberMultiplier = CreateConVar("umbrella_store_roulette_number_multiplier", "36.0", "Payout multiplier for exact number wins.", FCVAR_NONE, true, 1.0);
    gCvarAnnounceBigWin = CreateConVar("umbrella_store_roulette_announce_big_win", "1", "Announce big roulette wins globally.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarAnnounceThreshold = CreateConVar("umbrella_store_roulette_big_win_threshold", "20000", "Minimum net profit for big-win announcement.", FCVAR_NONE, true, 1.0);
    gCvarSpinSound = CreateConVar("umbrella_store_roulette_spin_sound", "buttons/blip1.wav", "Sound played when spinning roulette.");
    gCvarWinSound = CreateConVar("umbrella_store_roulette_win_sound", "items/itempickup.wav", "Sound played on roulette win.");
    gCvarLoseSound = CreateConVar("umbrella_store_roulette_lose_sound", "buttons/button10.wav", "Sound played on roulette loss.");
    gCvarAnimEnabled = CreateConVar("umbrella_store_roulette_anim_enabled", "1", "Enable roulette HUD spin animation.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarAnimMode = CreateConVar("umbrella_store_roulette_anim_mode", "2", "Roulette animation mode. 1=center text, 2=hint text.", FCVAR_NONE, true, 1.0, true, 2.0);
    gCvarAnimSteps = CreateConVar("umbrella_store_roulette_anim_steps", "54", "Minimum visual steps for roulette animation.", FCVAR_NONE, true, 20.0, true, 120.0);
    gCvarAnimDelayMin = CreateConVar("umbrella_store_roulette_anim_delay_min", "0.20", "Initial delay between animation steps.", FCVAR_NONE, true, 0.08, true, 1.2);
    gCvarAnimDelayMax = CreateConVar("umbrella_store_roulette_anim_delay_max", "0.90", "Final delay between animation steps.", FCVAR_NONE, true, 0.20, true, 2.5);

    HookConVarChange(gCvarEnabled, OnRouletteEnabledChanged);

    AutoExecConfig(true, "umbrella_store_roulette");

    for (int i = 1; i <= MaxClients; i++)
    {
        ResetClientState(i, true);
    }

    RegisterCasinoEntry();
}

public void OnConfigsExecuted()
{
    PrecacheConfiguredSound(gCvarSpinSound);
    PrecacheConfiguredSound(gCvarWinSound);
    PrecacheConfiguredSound(gCvarLoseSound);
    RegisterCasinoEntry();
}

public void OnMapStart()
{
    PrecacheConfiguredSound(gCvarSpinSound);
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
        US_Casino_Unregister(ROULETTE_CASINO_ID);
    }

    g_bRegistered = false;

    for (int i = 1; i <= MaxClients; i++)
    {
        RefundPendingSpin(i);
        ResetClientState(i, true);
    }
}

public void OnMapEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        RefundPendingSpin(i);
        ResetClientState(i, true);
    }
}

public void OnClientDisconnect(int client)
{
    RefundPendingSpin(client);
    ResetClientState(client, true);
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client >= 1 && client <= MaxClients)
    {
        RefundPendingSpin(client);
    }
}

public void OnRouletteEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RegisterCasinoEntry();
}

void RegisterCasinoEntry()
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
            char title[64];
            Format(title, sizeof(title), "%T", "Roulette Casino Title", LANG_SERVER);
            g_bRegistered = US_Casino_Register(ROULETTE_CASINO_ID, title, "sm_roulette");
        }
    }
    else if (g_bRegistered)
    {
        US_Casino_Unregister(ROULETTE_CASINO_ID);
        g_bRegistered = false;
    }
}

public Action Command_Roulette(int client, int args)
{
    if (!IsValidHumanClient(client))
    {
        return Plugin_Handled;
    }

    if (!CanUseRoulette(client, true))
    {
        return Plugin_Handled;
    }

    g_bAwaitingCustomBet[client] = false;
    g_iQueuedBetAmount[client] = 0;

    if (args < 1)
    {
        OpenRouletteMenu(client);
        return Plugin_Handled;
    }

    char arg1[64];
    GetCmdArg(1, arg1, sizeof(arg1));
    TrimString(arg1);

    if (args == 1)
    {
        int quickAmount = 0;
        bool parsedAsAmount = ParseBetArgument(client, arg1, quickAmount);
        if (parsedAsAmount)
        {
            bool isSingleNumberSelection = false;
            int parsedNumber = 0;
            if (TryParseStrictInt(arg1, parsedNumber) && parsedNumber >= 0 && parsedNumber <= ROULETTE_MAX_NUMBER)
            {
                isSingleNumberSelection = true;
            }

            if (!isSingleNumberSelection)
            {
                g_iQueuedBetAmount[client] = quickAmount;
                OpenRouletteMenu(client);
                return Plugin_Handled;
            }
        }
    }

    RouletteBetType type = RouletteBet_None;
    int number = -1;
    if (!ParseRouletteSelection(arg1, type, number))
    {
        RoulettePrint(client, "%t", "Roulette Command Help");
        OpenRouletteMenu(client);
        return Plugin_Handled;
    }

    g_iPendingType[client] = type;
    g_iPendingNumber[client] = number;

    if (type == RouletteBet_Number && number < 0)
    {
        ShowNumberMenu(client);
        return Plugin_Handled;
    }

    if (args >= 2)
    {
        char arg2[64];
        GetCmdArg(2, arg2, sizeof(arg2));
        TrimString(arg2);

        int amount = 0;
        if (!ParseBetArgument(client, arg2, amount))
        {
            RoulettePrint(client, "%t", "Roulette Custom Invalid");
            ShowBetMenu(client);
            return Plugin_Handled;
        }

        bool started = PlaceBet(client, amount);
        if (!started || !g_bSpinning[client])
        {
            ShowBetMenu(client);
        }
        return Plugin_Handled;
    }

    ShowBetMenu(client);
    return Plugin_Handled;
}

public Action Command_Say(int client, const char[] command, int argc)
{
    if (!IsValidHumanClient(client))
    {
        return Plugin_Continue;
    }

    char text[192];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);

    if (text[0] == '\0')
    {
        return Plugin_Continue;
    }

    if (StrEqual(text, "!roulette", false) || StrEqual(text, "/roulette", false) || StrEqual(text, "!ruleta", false) || StrEqual(text, "/ruleta", false) || StrEqual(text, "!ru", false) || StrEqual(text, "/ru", false))
    {
        g_bAwaitingCustomBet[client] = false;
        g_iQueuedBetAmount[client] = 0;
        if (CanUseRoulette(client, true))
        {
            OpenRouletteMenu(client);
        }
        return Plugin_Handled;
    }

    if (!g_bAwaitingCustomBet[client])
    {
        return Plugin_Continue;
    }

    if (text[0] == '!' || text[0] == '/')
    {
        if (StrEqual(text, "!cancel", false) || StrEqual(text, "/cancel", false))
        {
            g_bAwaitingCustomBet[client] = false;
            RoulettePrint(client, "%t", "Roulette Custom Cancelled");
            ShowBetMenu(client);
            return Plugin_Handled;
        }
        return Plugin_Continue;
    }

    if (StrEqual(text, "cancel", false) || StrEqual(text, "cancelar", false) || StrEqual(text, "0"))
    {
        g_bAwaitingCustomBet[client] = false;
        RoulettePrint(client, "%t", "Roulette Custom Cancelled");
        ShowBetMenu(client);
        return Plugin_Handled;
    }

    int amount = 0;
    if (!TryParseAmountInput(text, amount))
    {
        RoulettePrint(client, "%t", "Roulette Custom Invalid");
        return Plugin_Handled;
    }

    g_bAwaitingCustomBet[client] = false;
    bool started = PlaceBet(client, amount);
    if (!started || !g_bSpinning[client])
    {
        ShowBetMenu(client);
    }
    return Plugin_Handled;
}

void OpenRouletteMenu(int client)
{
    if (!CanUseRoulette(client, true))
    {
        return;
    }

    ShowMainMenu(client);
}

void ShowMainMenu(int client)
{
    Menu menu = new Menu(MenuHandler_MainMenu);

    char creditsText[32], minText[32], maxText[32], title[256];
    FormatNumberDots(US_GetCredits(client), creditsText, sizeof(creditsText));
    FormatNumberDots(GetMinBet(), minText, sizeof(minText));
    FormatNumberDots(GetConfiguredMaxBet(), maxText, sizeof(maxText));
    Format(title, sizeof(title), "%T", "Roulette Menu Title", client, creditsText, minText, maxText);
    menu.SetTitle(title);

    char label[128];
    Format(label, sizeof(label), "%T", "Roulette Menu Red", client);
    menu.AddItem("red", label);
    Format(label, sizeof(label), "%T", "Roulette Menu Black", client);
    menu.AddItem("black", label);
    Format(label, sizeof(label), "%T", "Roulette Menu Green", client);
    menu.AddItem("green", label);
    Format(label, sizeof(label), "%T", "Roulette Menu Number", client);
    menu.AddItem("number", label);
    Format(label, sizeof(label), "%T", "Roulette Menu Info", client);
    menu.AddItem("info", label);

    menu.ExitBackButton = true;
    menu.Display(client, 30);
}

public int MenuHandler_MainMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }

    if (!IsValidHumanClient(client))
    {
        return 0;
    }

    if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        g_iQueuedBetAmount[client] = 0;
        if (LibraryExists("umbrella_store"))
        {
            US_OpenCasinoMenu(client);
        }
        return 0;
    }

    if (action != MenuAction_Select)
    {
        return 0;
    }

    char info[32];
    menu.GetItem(item, info, sizeof(info));

    if (StrEqual(info, "red"))
    {
        g_iPendingType[client] = RouletteBet_Red;
        g_iPendingNumber[client] = -1;
        if (!TryPlaceQueuedBet(client))
        {
            ShowBetMenu(client);
        }
    }
    else if (StrEqual(info, "black"))
    {
        g_iPendingType[client] = RouletteBet_Black;
        g_iPendingNumber[client] = -1;
        if (!TryPlaceQueuedBet(client))
        {
            ShowBetMenu(client);
        }
    }
    else if (StrEqual(info, "green"))
    {
        g_iPendingType[client] = RouletteBet_Green;
        g_iPendingNumber[client] = -1;
        if (!TryPlaceQueuedBet(client))
        {
            ShowBetMenu(client);
        }
    }
    else if (StrEqual(info, "number"))
    {
        g_iPendingType[client] = RouletteBet_Number;
        g_iPendingNumber[client] = -1;
        ShowNumberMenu(client);
    }
    else
    {
        RoulettePrint(client, "%t", "Roulette Info 1");
        RoulettePrint(client, "%t", "Roulette Info 2");
        RoulettePrint(client, "%t", "Roulette Info 3");
        ShowMainMenu(client);
    }

    return 0;
}

void ShowNumberMenu(int client)
{
    Menu menu = new Menu(MenuHandler_NumberMenu);

    char title[192];
    Format(title, sizeof(title), "%T", "Roulette Number Menu Title", client);
    menu.SetTitle(title);

    char info[16], label[64];
    for (int i = 0; i <= ROULETTE_MAX_NUMBER; i++)
    {
        IntToString(i, info, sizeof(info));
        Format(label, sizeof(label), "%T", "Roulette Number Entry", client, i);
        menu.AddItem(info, label);
    }

    menu.ExitBackButton = true;
    menu.Display(client, 30);
}

public int MenuHandler_NumberMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }

    if (!IsValidHumanClient(client))
    {
        return 0;
    }

    if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        ShowMainMenu(client);
        return 0;
    }

    if (action != MenuAction_Select)
    {
        return 0;
    }

    char info[16];
    menu.GetItem(item, info, sizeof(info));

    int number = StringToInt(info);
    if (number < 0 || number > ROULETTE_MAX_NUMBER)
    {
        RoulettePrint(client, "%t", "Roulette Number Invalid");
        ShowNumberMenu(client);
        return 0;
    }

    g_iPendingType[client] = RouletteBet_Number;
    g_iPendingNumber[client] = number;
    if (!TryPlaceQueuedBet(client))
    {
        ShowBetMenu(client);
    }
    return 0;
}

bool TryPlaceQueuedBet(int client)
{
    int amount = g_iQueuedBetAmount[client];
    if (amount <= 0)
    {
        return false;
    }

    g_iQueuedBetAmount[client] = 0;
    bool started = PlaceBet(client, amount);
    if (!started || !g_bSpinning[client])
    {
        ShowBetMenu(client);
    }
    return true;
}

void ShowBetMenu(int client)
{
    if (g_iPendingType[client] == RouletteBet_None)
    {
        ShowMainMenu(client);
        return;
    }

    if (g_iPendingType[client] == RouletteBet_Number && g_iPendingNumber[client] < 0)
    {
        ShowNumberMenu(client);
        return;
    }

    Menu menu = new Menu(MenuHandler_BetMenu);

    char choice[96], creditsText[32], title[256];
    FormatBetChoice(client, g_iPendingType[client], g_iPendingNumber[client], choice, sizeof(choice));
    FormatNumberDots(US_GetCredits(client), creditsText, sizeof(creditsText));
    Format(title, sizeof(title), "%T", "Roulette Bet Menu Title", client, choice, creditsText);
    menu.SetTitle(title);

    int used[8];
    int usedCount = 0;
    for (int i = 0; i < sizeof(used); i++)
    {
        used[i] = -1;
    }

    int credits = US_GetCredits(client);
    int minBet = GetMinBet();
    int maxBet = GetMaxBetForClient(client);
    int highBet = (credits < maxBet) ? credits : maxBet;

    AddQuickBetOption(menu, client, minBet, "Roulette Quick Bet Min", used, sizeof(used), usedCount);
    AddQuickBetOption(menu, client, credits / 4, "Roulette Quick Bet Low", used, sizeof(used), usedCount);
    AddQuickBetOption(menu, client, credits / 2, "Roulette Quick Bet Medium", used, sizeof(used), usedCount);
    AddQuickBetOption(menu, client, highBet, "Roulette Quick Bet High", used, sizeof(used), usedCount);
    AddQuickBetOption(menu, client, credits, "Roulette Quick Bet AllIn", used, sizeof(used), usedCount);

    if (usedCount == 0)
    {
        char noQuick[128];
        Format(noQuick, sizeof(noQuick), "%T", "Roulette Quick Bet Unavailable", client);
        menu.AddItem("quick_unavailable", noQuick, ITEMDRAW_DISABLED);
    }

    char label[128];
    Format(label, sizeof(label), "%T", "Roulette Bet Menu Custom", client);
    menu.AddItem("custom", label);
    Format(label, sizeof(label), "%T", "Roulette Bet Menu Back", client);
    menu.AddItem("back", label);

    menu.ExitBackButton = true;
    menu.Display(client, 30);
}

public int MenuHandler_BetMenu(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }

    if (!IsValidHumanClient(client))
    {
        return 0;
    }

    if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        g_bAwaitingCustomBet[client] = false;
        if (g_iPendingType[client] == RouletteBet_Number)
        {
            ShowNumberMenu(client);
        }
        else
        {
            ShowMainMenu(client);
        }
        return 0;
    }

    if (action != MenuAction_Select)
    {
        return 0;
    }

    char info[32];
    menu.GetItem(item, info, sizeof(info));

    if (StrEqual(info, "back"))
    {
        g_bAwaitingCustomBet[client] = false;
        if (g_iPendingType[client] == RouletteBet_Number)
        {
            ShowNumberMenu(client);
        }
        else
        {
            ShowMainMenu(client);
        }
        return 0;
    }

    if (StrEqual(info, "custom"))
    {
        g_bAwaitingCustomBet[client] = true;
        RoulettePrint(client, "%t", "Roulette Custom Prompt", GetMinBet(), GetMaxBetForClient(client));
        return 0;
    }

    int amount = StringToInt(info);
    if (amount <= 0)
    {
        ShowBetMenu(client);
        return 0;
    }

    g_bAwaitingCustomBet[client] = false;
    bool started = PlaceBet(client, amount);
    if (!started || !g_bSpinning[client])
    {
        ShowBetMenu(client);
    }
    return 0;
}

bool PlaceBet(int client, int amount)
{
    if (!CanUseRoulette(client, true))
    {
        return false;
    }

    if (!CanDoAction(client, true))
    {
        return false;
    }

    RouletteBetType type = g_iPendingType[client];
    int selectedNumber = g_iPendingNumber[client];

    if (type == RouletteBet_None)
    {
        RoulettePrint(client, "%t", "Roulette Invalid Bet Type");
        return false;
    }

    if (type == RouletteBet_Number && (selectedNumber < 0 || selectedNumber > ROULETTE_MAX_NUMBER))
    {
        RoulettePrint(client, "%t", "Roulette Number Invalid");
        return false;
    }

    int minBet = GetMinBet();
    int maxBet = GetMaxBetForClient(client);

    if (maxBet < minBet)
    {
        RoulettePrint(client, "%t", "Roulette Not Enough Credits");
        return false;
    }

    if (amount < minBet)
    {
        char minText[32];
        FormatNumberDots(minBet, minText, sizeof(minText));
        RoulettePrint(client, "%t", "Roulette Bet Too Low", minText);
        return false;
    }

    if (amount > maxBet)
    {
        char maxText[32];
        FormatNumberDots(maxBet, maxText, sizeof(maxText));
        RoulettePrint(client, "%t", "Roulette Bet Too High", maxText);
        return false;
    }

    if (!US_TakeCredits(client, amount))
    {
        RoulettePrint(client, "%t", "Roulette Not Enough Credits");
        return false;
    }

    g_fNextUse[client] = GetGameTime() + gCvarCooldown.FloatValue;
    StartSpinAnimation(client, amount, type, selectedNumber);
    return true;
}

void StartSpinAnimation(int client, int amount, RouletteBetType type, int selectedNumber)
{
    if (!IsValidHumanClient(client))
    {
        return;
    }

    g_bSpinning[client] = true;
    g_iSpinBet[client] = amount;
    g_iSpinType[client] = type;
    g_iSpinSelectedNumber[client] = selectedNumber;
    g_iSpinResult[client] = GetRandomInt(0, ROULETTE_MAX_NUMBER);
    g_iSpinDisplay[client] = GetRandomInt(0, ROULETTE_MAX_NUMBER);
    g_iSpinStep[client] = 0;
    g_iSpinTotalSteps[client] = 1;
    if (!gCvarAnimEnabled.BoolValue)
    {
        EmitConfiguredSoundClient(client, gCvarSpinSound);
        ScheduleSpinStep(client, 0.01);
        return;
    }

    int wheelSize = sizeof(g_RouletteWheelOrder);
    int startIndex = GetWheelIndex(g_iSpinDisplay[client]);
    int finalIndex = GetWheelIndex(g_iSpinResult[client]);
    int prevIndex = finalIndex - 1;
    if (prevIndex < 0)
    {
        prevIndex += wheelSize;
    }

    int baseDistance = prevIndex - startIndex;
    if (baseDistance < 0)
    {
        baseDistance += wheelSize;
    }

    int minPlannedSteps = gCvarAnimSteps.IntValue - 1;
    if (minPlannedSteps < 4)
    {
        minPlannedSteps = 4;
    }

    int plannedSteps = baseDistance;
    while (plannedSteps < minPlannedSteps)
    {
        plannedSteps += wheelSize;
    }

    g_iSpinTotalSteps[client] = plannedSteps + 1;
    EmitConfiguredSoundClient(client, gCvarSpinSound);
    ScheduleSpinStep(client, gCvarAnimDelayMin.FloatValue);
}

void ScheduleSpinStep(int client, float delay)
{
    if (!IsValidHumanClient(client))
    {
        return;
    }

    if (delay < 0.01)
    {
        delay = 0.01;
    }

    if (g_hSpinTimer[client] != null)
    {
        KillTimer(g_hSpinTimer[client]);
        g_hSpinTimer[client] = null;
    }

    g_hSpinTimer[client] = CreateTimer(delay, Timer_SpinStep, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_SpinStep(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidHumanClient(client))
    {
        return Plugin_Stop;
    }

    if (g_hSpinTimer[client] != timer)
    {
        return Plugin_Stop;
    }

    g_hSpinTimer[client] = null;

    if (!g_bSpinning[client])
    {
        return Plugin_Stop;
    }

    g_iSpinStep[client]++;
    bool isFinal = (g_iSpinStep[client] >= g_iSpinTotalSteps[client]);

    int previewNumber = isFinal ? g_iSpinResult[client] : AdvanceSpinPreview(client);
    ShowSpinHud(client, previewNumber, isFinal);

    if (isFinal)
    {
        ResolveSpinResult(client);
        return Plugin_Stop;
    }

    float minDelay = gCvarAnimDelayMin.FloatValue;
    float maxDelay = gCvarAnimDelayMax.FloatValue;
    if (maxDelay < minDelay)
    {
        float swap = minDelay;
        minDelay = maxDelay;
        maxDelay = swap;
    }

    float progress = float(g_iSpinStep[client]) / float(g_iSpinTotalSteps[client]);
    if (progress < 0.0)
    {
        progress = 0.0;
    }
    else if (progress > 1.0)
    {
        progress = 1.0;
    }

    float eased = progress;
    float nextDelay = minDelay + ((maxDelay - minDelay) * eased);
    ScheduleSpinStep(client, nextDelay);
    return Plugin_Stop;
}

void ShowSpinHud(int client, int previewNumber, bool finalStep)
{
    if (!IsValidHumanClient(client))
    {
        return;
    }

    char choiceText[96], colorText[64], betText[32], line1[192], line2[192], line3[256], message[640];
    FormatBetChoice(client, g_iSpinType[client], g_iSpinSelectedNumber[client], choiceText, sizeof(choiceText));
    GetResultColorText(client, previewNumber, colorText, sizeof(colorText));
    FormatNumberDots(g_iSpinBet[client], betText, sizeof(betText));
    BuildRouletteReelLine(client, previewNumber, finalStep, line3, sizeof(line3));

    Format(line1, sizeof(line1), "%T", "Roulette Spin HUD Header", client, choiceText, betText);
    if (finalStep)
    {
        Format(line2, sizeof(line2), "%T", "Roulette Spin HUD Final", client, previewNumber, colorText);
    }
    else
    {
        Format(line2, sizeof(line2), "%T", "Roulette Spin HUD Rolling", client, previewNumber, colorText);
    }

    Format(message, sizeof(message), "%s\n%s\n%s", line1, line2, line3);
    if (finalStep)
    {
        PrintCenterText(client, "%s", message);
        if (gCvarAnimMode.IntValue == 2)
        {
            PrintHintText(client, "%s", message);
        }
    }
    else if (gCvarAnimMode.IntValue == 1)
    {
        PrintCenterText(client, "%s", message);
    }
    else
    {
        PrintHintText(client, "%s", message);
    }
}

void ResolveSpinResult(int client)
{
    if (!IsValidHumanClient(client))
    {
        return;
    }

    RouletteBetType type = g_iSpinType[client];
    int selectedNumber = g_iSpinSelectedNumber[client];
    int amount = g_iSpinBet[client];
    int result = g_iSpinResult[client];

    g_bSpinning[client] = false;
    g_iSpinType[client] = RouletteBet_None;
    g_iSpinSelectedNumber[client] = -1;
    g_iSpinBet[client] = 0;
    g_iSpinResult[client] = 0;
    g_iSpinDisplay[client] = 0;
    g_iSpinStep[client] = 0;
    g_iSpinTotalSteps[client] = 0;

    bool win = DidBetWin(type, selectedNumber, result);
    float multiplier = GetBetMultiplier(type);

    char choiceText[96], colorText[64], amountText[32];
    FormatBetChoice(client, type, selectedNumber, choiceText, sizeof(choiceText));
    GetResultColorText(client, result, colorText, sizeof(colorText));
    FormatNumberDots(amount, amountText, sizeof(amountText));

    if (win)
    {
        int payout = RoundToFloor(float(amount) * multiplier);
        if (payout < amount)
        {
            payout = amount;
        }

        US_AddCredits(client, payout, false);
        EmitConfiguredSoundClient(client, gCvarWinSound);

        int net = payout - amount;
        char payoutText[32];
        FormatNumberDots(payout, payoutText, sizeof(payoutText));
        RoulettePrint(client, "%t", "Roulette Result Win", choiceText, result, colorText, payoutText, multiplier);

        if (gCvarAnnounceBigWin.BoolValue && net >= gCvarAnnounceThreshold.IntValue)
        {
            char netText[32];
            FormatNumberDots(net, netText, sizeof(netText));
            RoulettePrintAll("%t", "Roulette Big Win Announce", client, netText, choiceText, result, colorText);
        }
    }
    else
    {
        EmitConfiguredSoundClient(client, gCvarLoseSound);
        RoulettePrint(client, "%t", "Roulette Result Lose", choiceText, result, colorText, amountText);
    }
}

void RefundPendingSpin(int client)
{
    if (client < 1 || client > MaxClients || !IsClientConnected(client) || IsFakeClient(client))
    {
        return;
    }

    if (!g_bSpinning[client] || g_iSpinBet[client] <= 0)
    {
        return;
    }

    if (!LibraryExists("umbrella_store") || !US_IsLoaded(client))
    {
        LogError("[Umbrella Store] Roulette could not refund unresolved spin for client %d because the store was not available.", client);
        return;
    }

    int refund = g_iSpinBet[client];
    if (!US_AddCredits(client, refund, false))
    {
        LogError("[Umbrella Store] Roulette failed to refund %d credits for unresolved spin on client %d.", refund, client);
    }
}

bool CanUseRoulette(int client, bool notify)
{
    if (!gCvarEnabled.BoolValue)
    {
        if (notify)
        {
            RoulettePrint(client, "%t", "Roulette Disabled");
        }
        return false;
    }

    if (!US_IsLoaded(client))
    {
        if (notify)
        {
            RoulettePrint(client, "%t", "Roulette Store Not Loaded");
        }
        return false;
    }

    return true;
}

bool CanDoAction(int client, bool notify)
{
    if (g_bSpinning[client])
    {
        if (notify)
        {
            RoulettePrint(client, "%t", "Roulette Already Spinning");
        }
        return false;
    }

    float now = GetGameTime();
    if (now < g_fNextUse[client])
    {
        if (notify)
        {
            float remain = g_fNextUse[client] - now;
            if (remain < 0.0)
            {
                remain = 0.0;
            }
            RoulettePrint(client, "%t", "Roulette Cooldown", remain);
        }
        return false;
    }
    return true;
}

void ResetClientState(int client, bool clearCooldown)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    g_bAwaitingCustomBet[client] = false;
    g_iPendingType[client] = RouletteBet_None;
    g_iPendingNumber[client] = -1;
    g_bSpinning[client] = false;
    g_iSpinStep[client] = 0;
    g_iSpinTotalSteps[client] = 0;
    g_iSpinType[client] = RouletteBet_None;
    g_iSpinSelectedNumber[client] = -1;
    g_iSpinResult[client] = 0;
    g_iSpinBet[client] = 0;
    g_iSpinDisplay[client] = 0;
    g_iQueuedBetAmount[client] = 0;
    if (g_hSpinTimer[client] != null)
    {
        KillTimer(g_hSpinTimer[client]);
        g_hSpinTimer[client] = null;
    }
    if (clearCooldown)
    {
        g_fNextUse[client] = 0.0;
    }
}

bool ParseRouletteSelection(const char[] input, RouletteBetType &type, int &number)
{
    type = RouletteBet_None;
    number = -1;

    if (StrEqual(input, "red", false) || StrEqual(input, "rojo", false) || StrEqual(input, "r", false))
    {
        type = RouletteBet_Red;
        return true;
    }

    if (StrEqual(input, "black", false) || StrEqual(input, "negro", false) || StrEqual(input, "b", false))
    {
        type = RouletteBet_Black;
        return true;
    }

    if (StrEqual(input, "green", false) || StrEqual(input, "verde", false) || StrEqual(input, "g", false))
    {
        type = RouletteBet_Green;
        return true;
    }

    if (StrEqual(input, "number", false) || StrEqual(input, "numero", false) || StrEqual(input, "num", false) || StrEqual(input, "n", false))
    {
        type = RouletteBet_Number;
        number = -1;
        return true;
    }

    int parsed = 0;
    if (TryParseStrictInt(input, parsed) && parsed >= 0 && parsed <= ROULETTE_MAX_NUMBER)
    {
        type = RouletteBet_Number;
        number = parsed;
        return true;
    }

    return false;
}

bool ParseBetArgument(int client, const char[] input, int &amount)
{
    if (StrEqual(input, "all", false) || StrEqual(input, "todo", false))
    {
        amount = US_GetCredits(client);
        return true;
    }

    return TryParseAmountInput(input, amount);
}

bool TryParseStrictInt(const char[] input, int &value)
{
    int len = strlen(input);
    if (len <= 0)
    {
        return false;
    }

    for (int i = 0; i < len; i++)
    {
        int c = input[i];
        if (c < '0' || c > '9')
        {
            return false;
        }
    }

    value = StringToInt(input);
    return true;
}

bool TryParseAmountInput(const char[] input, int &amount)
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
    amount = StringToInt(digits);
    return (amount > 0);
}

void AddQuickBetOption(Menu menu, int client, int betCandidate, const char[] phraseKey, int[] used, int maxUsed, int &usedCount)
{
    int minBet = GetMinBet();
    int maxBet = GetMaxBetForClient(client);

    if (maxBet < minBet)
    {
        return;
    }

    int bet = betCandidate;
    if (bet < minBet)
    {
        bet = minBet;
    }
    if (bet > maxBet)
    {
        bet = maxBet;
    }

    if (bet < minBet)
    {
        return;
    }

    for (int i = 0; i < usedCount; i++)
    {
        if (used[i] == bet)
        {
            return;
        }
    }

    if (usedCount >= maxUsed)
    {
        return;
    }

    used[usedCount++] = bet;

    char info[16], amountText[32], display[128];
    IntToString(bet, info, sizeof(info));
    FormatNumberDots(bet, amountText, sizeof(amountText));
    Format(display, sizeof(display), "%T", phraseKey, client, amountText);
    menu.AddItem(info, display);
}

int GetMinBet()
{
    int minBet = gCvarMinBet.IntValue;
    return (minBet < 1) ? 1 : minBet;
}

int GetConfiguredMaxBet()
{
    int maxBet = gCvarMaxBet.IntValue;
    return (maxBet <= 0) ? 2147483647 : maxBet;
}

int GetMaxBetForClient(int client)
{
    int credits = US_GetCredits(client);
    int maxBet = gCvarMaxBet.IntValue;

    if (maxBet <= 0 || maxBet > credits)
    {
        maxBet = credits;
    }

    return maxBet;
}

float GetBetMultiplier(RouletteBetType type)
{
    switch (type)
    {
        case RouletteBet_Red, RouletteBet_Black:
        {
            return gCvarColorMultiplier.FloatValue;
        }
        case RouletteBet_Green:
        {
            return gCvarGreenMultiplier.FloatValue;
        }
        case RouletteBet_Number:
        {
            return gCvarNumberMultiplier.FloatValue;
        }
    }
    return 1.0;
}

bool DidBetWin(RouletteBetType type, int selectedNumber, int result)
{
    switch (type)
    {
        case RouletteBet_Red:
        {
            return (result != 0 && IsRedNumber(result));
        }
        case RouletteBet_Black:
        {
            return (result != 0 && !IsRedNumber(result));
        }
        case RouletteBet_Green:
        {
            return (result == 0);
        }
        case RouletteBet_Number:
        {
            return (result == selectedNumber);
        }
    }
    return false;
}

int AdvanceSpinPreview(int client)
{
    int index = GetWheelIndex(g_iSpinDisplay[client]);
    int wheelSize = sizeof(g_RouletteWheelOrder);
    index = (index + 1) % wheelSize;
    g_iSpinDisplay[client] = g_RouletteWheelOrder[index];
    return g_iSpinDisplay[client];
}

void BuildRouletteReelLine(int client, int center, bool finalStep, char[] buffer, int maxlen)
{
    int left3 = GetWheelNeighbor(center, -3);
    int left2 = GetWheelNeighbor(center, -2);
    int left1 = GetWheelNeighbor(center, -1);
    int right1 = GetWheelNeighbor(center, 1);
    int right2 = GetWheelNeighbor(center, 2);
    int right3 = GetWheelNeighbor(center, 3);

    char centerToken[16];
    if (finalStep)
    {
        Format(centerToken, sizeof(centerToken), "[[%02d]]", center);
    }
    else
    {
        Format(centerToken, sizeof(centerToken), "[%02d]", center);
    }

    int shift = (g_iSpinStep[client] % 2);
    if (shift == 0)
    {
        Format(buffer, maxlen, ">>> %02d %02d %02d %s %02d %02d %02d >>>",
            left3, left2, left1, centerToken, right1, right2, right3);
    }
    else
    {
        Format(buffer, maxlen, " >> %02d %02d %02d %s %02d %02d %02d >> ",
            left3, left2, left1, centerToken, right1, right2, right3);
    }
}

int GetWheelNeighbor(int center, int offset)
{
    int centerIndex = GetWheelIndex(center);
    int wheelSize = sizeof(g_RouletteWheelOrder);
    int targetIndex = centerIndex + offset;
    while (targetIndex < 0)
    {
        targetIndex += wheelSize;
    }
    return g_RouletteWheelOrder[targetIndex % wheelSize];
}

int GetWheelIndex(int number)
{
    for (int i = 0; i < sizeof(g_RouletteWheelOrder); i++)
    {
        if (g_RouletteWheelOrder[i] == number)
        {
            return i;
        }
    }
    return 0;
}

bool IsRedNumber(int number)
{
    switch (number)
    {
        case 1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36:
        {
            return true;
        }
    }
    return false;
}

void FormatBetChoice(int client, RouletteBetType type, int selectedNumber, char[] buffer, int maxlen)
{
    switch (type)
    {
        case RouletteBet_Red:
        {
            Format(buffer, maxlen, "%T", "Roulette Bet Choice Red", client);
        }
        case RouletteBet_Black:
        {
            Format(buffer, maxlen, "%T", "Roulette Bet Choice Black", client);
        }
        case RouletteBet_Green:
        {
            Format(buffer, maxlen, "%T", "Roulette Bet Choice Green", client);
        }
        case RouletteBet_Number:
        {
            Format(buffer, maxlen, "%T", "Roulette Bet Choice Number", client, selectedNumber);
        }
        default:
        {
            Format(buffer, maxlen, "%T", "Roulette Invalid Bet Type", client);
        }
    }
}

void GetResultColorText(int client, int result, char[] buffer, int maxlen)
{
    if (result == 0)
    {
        Format(buffer, maxlen, "%T", "Roulette Color Green", client);
    }
    else if (IsRedNumber(result))
    {
        Format(buffer, maxlen, "%T", "Roulette Color Red", client);
    }
    else
    {
        Format(buffer, maxlen, "%T", "Roulette Color Black", client);
    }
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

void EmitConfiguredSoundClient(int client, ConVar cvar)
{
    if (!IsValidHumanClient(client))
    {
        return;
    }

    char sound[PLATFORM_MAX_PATH];
    cvar.GetString(sound, sizeof(sound));
    TrimString(sound);
    if (sound[0] == '\0')
    {
        return;
    }

    EmitSoundToClient(client, sound, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL);
}

void FormatNumberDots(int value, char[] buffer, int maxlen)
{
    char raw[32];
    IntToString(value, raw, sizeof(raw));

    int len = strlen(raw);
    if (len <= 3)
    {
        strcopy(buffer, maxlen, raw);
        return;
    }

    char temp[32];
    int out = 0;
    for (int i = 0; i < len; i++)
    {
        temp[out++] = raw[i];
        int remaining = len - i - 1;
        if (remaining > 0 && (remaining % 3) == 0)
        {
            temp[out++] = '.';
        }
    }

    temp[out] = '\0';
    strcopy(buffer, maxlen, temp);
}

bool IsValidHumanClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

void RoulettePrint(int client, const char[] format, any ...)
{
    if (!IsValidHumanClient(client))
    {
        return;
    }

    char buffer[256], highlighted[320];
    SetGlobalTransTarget(client);
    VFormat(buffer, sizeof(buffer), format, 3);
    HighlightChatCommands(buffer, highlighted, sizeof(highlighted));
    PrintToChat(client, "%s %s %s", US_CHAT_TAG, ROULETTE_TAG, highlighted);
}

void RoulettePrintAll(const char[] format, any ...)
{
    char buffer[256], highlighted[320];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHumanClient(client))
        {
            continue;
        }

        SetGlobalTransTarget(client);
        VFormat(buffer, sizeof(buffer), format, 2);
        HighlightChatCommands(buffer, highlighted, sizeof(highlighted));
        PrintToChat(client, "%s %s %s", US_CHAT_TAG, ROULETTE_TAG, highlighted);
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

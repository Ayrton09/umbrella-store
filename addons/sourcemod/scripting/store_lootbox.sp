#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <umbrella_store>
#include <umbrella_store_module_utils>
#include <multicolors>

#define LB_CHAT_TAG " {green}[Umbrella Store]{default}"
#define LB_MENU_SECTION "lootbox"
#define LB_MAX_BOXES 64
#define LB_MAX_CREDITS 2000000000

enum
{
    Reward_Credits = 0,
    Reward_Item
}

enum struct LootBox
{
    char id[32];
    char name[64];
    char command[32];
    int price;
    int rewardStart;   // first index into g_aRewards
    int rewardCount;   // number of rewards belonging to this box
    int totalWeight;   // sum of reward weights (cached)
}

enum struct LootReward
{
    int type;            // Reward_Credits | Reward_Item
    int weight;
    int creditsMin;
    int creditsMax;
    char itemId[32];
    int fallbackCredits; // granted instead if the player already owns the item
}

ArrayList g_aBoxes;
ArrayList g_aRewards;
bool g_bRegistered = false;

ConVar gCvarEnabled;
ConVar gCvarCooldown;
ConVar gCvarOpenSound;
ConVar gCvarWinSound;
ConVar gCvarAnimEnabled;
ConVar gCvarAnimTicks;
ConVar gCvarAnimInterval;

float g_fNextUse[MAXPLAYERS + 1];

// Cosmetic reveal state (the reward is already granted before the animation).
Handle g_hAnimTimer[MAXPLAYERS + 1];
int g_iAnimBox[MAXPLAYERS + 1];
int g_iAnimTick[MAXPLAYERS + 1];
char g_szAnimResult[MAXPLAYERS + 1][128];

public Plugin myinfo =
{
    name = "[Umbrella Store] Lootbox",
    author = "Ayrton09",
    description = "Cajas con premios de creditos e items para Umbrella Store",
    version = "1.5.0",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("umbrella_store_lootbox.phrases");

    RegConsoleCmd("sm_lootbox", Command_Lootbox);
    RegConsoleCmd("sm_cajas", Command_Lootbox);
    RegConsoleCmd("sm_case", Command_Lootbox);

    gCvarEnabled      = CreateConVar("umbrella_store_lootbox_enabled", "1", "Enable the lootbox module.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarCooldown     = CreateConVar("umbrella_store_lootbox_cooldown", "1.0", "Seconds between opening boxes.", FCVAR_NONE, true, 0.0);
    gCvarOpenSound    = CreateConVar("umbrella_store_lootbox_open_sound", "buttons/blip1.wav", "Sound played while opening a box.");
    gCvarWinSound     = CreateConVar("umbrella_store_lootbox_win_sound", "items/itempickup.wav", "Sound played when the reward is revealed.");
    gCvarAnimEnabled  = CreateConVar("umbrella_store_lootbox_anim_enabled", "1", "Enable the HUD reveal animation.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarAnimTicks    = CreateConVar("umbrella_store_lootbox_anim_ticks", "12", "Number of spin ticks before the reward is revealed.", FCVAR_NONE, true, 1.0, true, 40.0);
    gCvarAnimInterval = CreateConVar("umbrella_store_lootbox_anim_interval", "0.12", "Seconds between spin ticks.", FCVAR_NONE, true, 0.03, true, 1.0);

    AutoExecConfig(true, "umbrella_store_lootbox");

    g_aBoxes = new ArrayList(sizeof(LootBox));
    g_aRewards = new ArrayList(sizeof(LootReward));
}

public void OnConfigsExecuted()
{
    LoadLootboxConfig();
    PrecacheConfiguredSound(gCvarOpenSound);
    PrecacheConfiguredSound(gCvarWinSound);
    RegisterMenuEntry();
}

public void OnMapStart()
{
    PrecacheConfiguredSound(gCvarOpenSound);
    PrecacheConfiguredSound(gCvarWinSound);
}

public void OnAllPluginsLoaded()
{
    RegisterMenuEntry();
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "umbrella_store"))
    {
        RegisterMenuEntry();
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
        US_UnregisterMenuSection(LB_MENU_SECTION);
    }
    g_bRegistered = false;

    for (int i = 1; i <= MaxClients; i++)
    {
        ResetAnim(i);
    }
}

public void OnClientDisconnect(int client)
{
    ResetAnim(client);
    g_fNextUse[client] = 0.0;
}

void RegisterMenuEntry()
{
    if (!LibraryExists("umbrella_store") || g_aBoxes == null || g_aBoxes.Length == 0)
    {
        return;
    }

    char title[64];
    Format(title, sizeof(title), "%T", "Lootbox Menu Title", LANG_SERVER);
    if (US_RegisterMenuSection(LB_MENU_SECTION, title, "sm_lootbox", 50))
    {
        g_bRegistered = true;
    }
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
    if (!FileExists(full, true))
    {
        return;
    }

    PrecacheSound(path, true);
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

// =========================
// Config
// =========================
void LoadLootboxConfig()
{
    g_aBoxes.Clear();
    g_aRewards.Clear();

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/umbrella_store/umbrella_store_lootboxes.txt");
    if (!FileExists(path))
    {
        return;
    }

    KeyValues kv = new KeyValues("Lootboxes");
    if (!kv.ImportFromFile(path))
    {
        delete kv;
        LogError("[Umbrella Store] Failed to parse lootbox config: %s", path);
        return;
    }

    if (!kv.GotoFirstSubKey())
    {
        delete kv;
        return;
    }

    do
    {
        if (g_aBoxes.Length >= LB_MAX_BOXES)
        {
            LogError("[Umbrella Store] Lootbox limit (%d) reached, ignoring extra boxes.", LB_MAX_BOXES);
            break;
        }

        LootBox box;
        kv.GetSectionName(box.id, sizeof(box.id));
        kv.GetString("name", box.name, sizeof(box.name), box.id);
        kv.GetString("command", box.command, sizeof(box.command), "");
        box.price = kv.GetNum("price", 0);
        if (box.price < 0)
        {
            box.price = 0;
        }

        box.rewardStart = g_aRewards.Length;
        box.rewardCount = 0;
        box.totalWeight = 0;

        if (kv.JumpToKey("rewards") && kv.GotoFirstSubKey())
        {
            do
            {
                LootReward reward;
                char typeStr[16];
                kv.GetString("type", typeStr, sizeof(typeStr), "credits");
                reward.type = StrEqual(typeStr, "item", false) ? Reward_Item : Reward_Credits;
                reward.weight = kv.GetNum("weight", 1);
                if (reward.weight < 1)
                {
                    reward.weight = 1;
                }
                reward.creditsMin = kv.GetNum("min", 0);
                reward.creditsMax = kv.GetNum("max", reward.creditsMin);
                if (reward.creditsMax < reward.creditsMin)
                {
                    reward.creditsMax = reward.creditsMin;
                }
                kv.GetString("item", reward.itemId, sizeof(reward.itemId), "");
                reward.fallbackCredits = kv.GetNum("fallback_credits", 0);
                if (reward.fallbackCredits < 0)
                {
                    reward.fallbackCredits = 0;
                }

                if (reward.type == Reward_Item && reward.itemId[0] == '\0')
                {
                    continue; // malformed item reward
                }

                g_aRewards.PushArray(reward, sizeof(LootReward));
                box.rewardCount++;
                box.totalWeight += reward.weight;
            }
            while (kv.GotoNextKey());

            kv.GoBack();
            kv.GoBack();
        }

        if (box.rewardCount > 0)
        {
            g_aBoxes.PushArray(box, sizeof(LootBox));
        }
    }
    while (kv.GotoNextKey());

    delete kv;
}

// =========================
// Menu
// =========================
public Action Command_Lootbox(int client, int args)
{
    if (!USM_IsValidClient(client))
    {
        return Plugin_Handled;
    }

    if (!gCvarEnabled.BoolValue || !US_IsEnabled())
    {
        LB_Print(client, "%t", "Lootbox Disabled");
        return Plugin_Handled;
    }

    ShowBoxMenu(client);
    return Plugin_Handled;
}

void ShowBoxMenu(int client)
{
    if (g_aBoxes == null || g_aBoxes.Length == 0)
    {
        LB_Print(client, "%t", "Lootbox None Available");
        return;
    }

    Menu menu = new Menu(MenuHandler_Boxes);
    char title[96];
    Format(title, sizeof(title), "%T", "Lootbox Menu Title", client);
    menu.SetTitle(title);

    LootBox box;
    for (int i = 0; i < g_aBoxes.Length; i++)
    {
        g_aBoxes.GetArray(i, box, sizeof(LootBox));
        char info[16], label[128];
        IntToString(i, info, sizeof(info));
        Format(label, sizeof(label), "%s - %d", box.name, box.price);
        menu.AddItem(info, label);
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Boxes(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        int boxIndex = StringToInt(info);
        OpenBox(param1, boxIndex);
    }
    return 0;
}

// =========================
// Opening
// =========================
void OpenBox(int client, int boxIndex)
{
    if (!USM_IsValidClient(client) || g_aBoxes == null || boxIndex < 0 || boxIndex >= g_aBoxes.Length)
    {
        return;
    }

    if (!gCvarEnabled.BoolValue || !US_IsEnabled() || !US_IsLoaded(client))
    {
        LB_Print(client, "%t", "Lootbox Disabled");
        return;
    }

    if (g_hAnimTimer[client] != null)
    {
        LB_Print(client, "%t", "Lootbox Busy");
        return;
    }

    if (GetGameTime() < g_fNextUse[client])
    {
        LB_Print(client, "%t", "Lootbox Cooldown");
        return;
    }

    LootBox box;
    g_aBoxes.GetArray(boxIndex, box, sizeof(LootBox));

    if (US_GetCredits(client) < box.price)
    {
        LB_Print(client, "%t", "Lootbox Not Enough", box.price);
        ShowBoxMenu(client);
        return;
    }

    // Charge the box price atomically before granting anything.
    if (box.price > 0 && !US_TakeCredits(client, box.price))
    {
        LB_Print(client, "%t", "Lootbox Transaction Failed");
        return;
    }

    LootReward reward;
    if (!RollReward(box, reward))
    {
        // Should not happen (boxes with no rewards are dropped at load), refund.
        if (box.price > 0 && !US_AddCredits(client, box.price, false))
        {
            LogError("[Umbrella Store] Lootbox could not refund price %d to client %d (at credit cap).", box.price, client);
        }
        LB_Print(client, "%t", "Lootbox Transaction Failed");
        return;
    }

    // Grant the reward immediately so a mid-animation disconnect never loses it.
    char resultText[128];
    if (!GrantReward(client, reward, resultText, sizeof(resultText)))
    {
        // Granting failed: refund the box price so the player is not worse off.
        if (box.price > 0 && !US_AddCredits(client, box.price, false))
        {
            LogError("[Umbrella Store] Lootbox could not refund price %d to client %d (at credit cap).", box.price, client);
        }
        LB_Print(client, "%t", "Lootbox Transaction Failed");
        return;
    }

    g_fNextUse[client] = GetGameTime() + gCvarCooldown.FloatValue;
    UpdateLootboxStats(client);

    if (gCvarAnimEnabled.BoolValue)
    {
        StartReveal(client, boxIndex, resultText);
    }
    else
    {
        EmitConfiguredSound(client, gCvarWinSound);
        LB_Print(client, "%t", "Lootbox Reward", resultText);
    }
}

bool RollReward(LootBox box, LootReward reward)
{
    if (box.rewardCount <= 0 || box.totalWeight <= 0)
    {
        return false;
    }

    int roll = GetRandomInt(0, box.totalWeight - 1);
    int acc = 0;
    for (int i = 0; i < box.rewardCount; i++)
    {
        LootReward candidate;
        g_aRewards.GetArray(box.rewardStart + i, candidate, sizeof(LootReward));
        acc += candidate.weight;
        if (roll < acc)
        {
            reward = candidate;
            return true;
        }
    }

    // Fallback to the last reward (rounding safety).
    g_aRewards.GetArray(box.rewardStart + box.rewardCount - 1, reward, sizeof(LootReward));
    return true;
}

// Grants the reward and writes a human-readable description into resultText.
bool GrantReward(int client, LootReward reward, char[] resultText, int maxlen)
{
    if (reward.type == Reward_Credits)
    {
        int amount = reward.creditsMin;
        if (reward.creditsMax > reward.creditsMin)
        {
            amount = GetRandomInt(reward.creditsMin, reward.creditsMax);
        }
        if (amount < 0)
        {
            amount = 0;
        }
        if (amount > LB_MAX_CREDITS)
        {
            amount = LB_MAX_CREDITS;
        }

        if (amount > 0 && !US_AddCredits(client, amount, false))
        {
            return false;
        }

        Format(resultText, maxlen, "%T", "Lootbox Won Credits", client, amount);
        return true;
    }

    // Item reward. If the player already owns it, fall back to credits.
    char itemName[64];
    GetItemDisplayName(reward.itemId, itemName, sizeof(itemName));

    if (US_HasItem(client, reward.itemId))
    {
        int fallback = reward.fallbackCredits;
        if (fallback > 0)
        {
            if (!US_AddCredits(client, fallback, false))
            {
                return false;
            }
            Format(resultText, maxlen, "%T", "Lootbox Won Duplicate", client, itemName, fallback);
        }
        else
        {
            Format(resultText, maxlen, "%T", "Lootbox Won Duplicate No Credits", client, itemName);
        }
        return true;
    }

    if (!US_GiveItem(client, reward.itemId, false))
    {
        return false;
    }

    Format(resultText, maxlen, "%T", "Lootbox Won Item", client, itemName);
    return true;
}

void GetItemDisplayName(const char[] itemId, char[] buffer, int maxlen)
{
    char name[64], type[32], category[32];
    int price, team;
    if (US_GetItemInfo(itemId, name, sizeof(name), type, sizeof(type), price, team, category, sizeof(category)) && name[0] != '\0')
    {
        strcopy(buffer, maxlen, name);
    }
    else
    {
        strcopy(buffer, maxlen, itemId);
    }
}

void UpdateLootboxStats(int client)
{
    US_AddStat(client, "lootbox_opened", 1);
    US_AdvanceQuestProgress(client, "lootbox_open_5", 1);
}

// =========================
// Cosmetic reveal animation
// =========================
void StartReveal(int client, int boxIndex, const char[] resultText)
{
    ResetAnim(client);

    g_iAnimBox[client] = boxIndex;
    g_iAnimTick[client] = 0;
    strcopy(g_szAnimResult[client], sizeof(g_szAnimResult[]), resultText);

    EmitConfiguredSound(client, gCvarOpenSound);
    g_hAnimTimer[client] = CreateTimer(gCvarAnimInterval.FloatValue, Timer_Reveal, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Reveal(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!USM_IsValidClient(client) || timer != g_hAnimTimer[client])
    {
        return Plugin_Stop;
    }

    int ticks = gCvarAnimTicks.IntValue;
    g_iAnimTick[client]++;

    if (g_iAnimTick[client] >= ticks)
    {
        g_hAnimTimer[client] = null;
        EmitConfiguredSound(client, gCvarWinSound);
        PrintCenterText(client, "%t", "Lootbox Reveal Final", g_szAnimResult[client]);
        LB_Print(client, "%t", "Lootbox Reward", g_szAnimResult[client]);
        return Plugin_Stop;
    }

    char spinText[128];
    GetRandomRewardText(client, g_iAnimBox[client], spinText, sizeof(spinText));
    PrintCenterText(client, "%t", "Lootbox Reveal Spin", spinText);
    EmitConfiguredSound(client, gCvarOpenSound);
    return Plugin_Continue;
}

void GetRandomRewardText(int client, int boxIndex, char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (boxIndex < 0 || boxIndex >= g_aBoxes.Length)
    {
        return;
    }

    LootBox box;
    g_aBoxes.GetArray(boxIndex, box, sizeof(LootBox));
    if (box.rewardCount <= 0)
    {
        return;
    }

    int pick = GetRandomInt(0, box.rewardCount - 1);
    LootReward reward;
    g_aRewards.GetArray(box.rewardStart + pick, reward, sizeof(LootReward));

    if (reward.type == Reward_Credits)
    {
        Format(buffer, maxlen, "%T", "Lootbox Won Credits", client, reward.creditsMax);
    }
    else
    {
        char itemName[64];
        GetItemDisplayName(reward.itemId, itemName, sizeof(itemName));
        strcopy(buffer, maxlen, itemName);
    }
}

void ResetAnim(int client)
{
    if (g_hAnimTimer[client] != null)
    {
        KillTimer(g_hAnimTimer[client]);
        g_hAnimTimer[client] = null;
    }
    g_iAnimBox[client] = -1;
    g_iAnimTick[client] = 0;
    g_szAnimResult[client][0] = '\0';
}

// =========================
// Helpers
// =========================
void LB_Print(int client, const char[] format, any ...)
{
    if (!USM_IsValidClient(client))
    {
        return;
    }

    char buffer[192];
    SetGlobalTransTarget(client);
    VFormat(buffer, sizeof(buffer), format, 3);
    CPrintToChat(client, "%s %s", LB_CHAT_TAG, buffer);
}

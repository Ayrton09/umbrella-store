#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>

// =========================================================================
// CONFIG
// =========================================================================
#define STORE_DB_CONFIG          "store"
#define STORE_ITEMS_CONFIG       "configs/umbrella_store/umbrella_store_items.txt"
#define STORE_LOG_PREFIX         "[Umbrella Store]"
#define STORE_SELL_PERCENT       50
#define PREVIEW_LIFETIME         15.0
#define PREVIEW_DISTANCE         100.0
#define PREVIEW_Z_OFFSET         60.0

// =========================================================================
// ESTRUCTURAS Y LISTAS
// =========================================================================
enum struct StoreItem
{
    char id[32];
    char name[64];
    char type[16];
    char szModel[256];
    char szArms[256];
    char szValue[64];
    int price;
    int team;
    char flag[16];
}

enum struct InventoryItem
{
    char item_id[32];
    int is_equipped;
}

ArrayList g_aItems;
ArrayList g_hInventory[MAXPLAYERS + 1];
ArrayList g_aCasinoIds;
StringMap g_mItemIndex;
StringMap g_mInventoryOwned[MAXPLAYERS + 1];
StringMap g_mCasinoTitles;
StringMap g_mCasinoCommands;
StringMap g_mCasinoIndex;
bool g_bItemCacheReady = false;

// =========================================================================
// VARIABLES GLOBALES Y PREVIEW
// =========================================================================
Database g_DB = null;
bool g_bIsMySQL = false;
bool g_bLateDatabaseReady = false;
int g_iPendingTableQueries = 0;

int g_iCredits[MAXPLAYERS + 1] = {0, ...};
bool g_bIsLoaded[MAXPLAYERS + 1] = {false, ...};
bool g_bIsLoading[MAXPLAYERS + 1] = {false, ...};
bool g_bDetailFromInventory[MAXPLAYERS + 1] = {false, ...};
int g_iPreviewEntity[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
char g_szBrowseType[MAXPLAYERS + 1][16];
int g_iBrowseTeam[MAXPLAYERS + 1] = {0, ...};
char g_szInvFilter[MAXPLAYERS + 1][32];
char g_szLastDetailItem[MAXPLAYERS + 1][32];
int g_iTradeSender[MAXPLAYERS + 1] = {0, ...};
char g_szTradeSenderItem[MAXPLAYERS + 1][32];
char g_szTradeTargetItem[MAXPLAYERS + 1][32];
char g_szTradeGiftItem[MAXPLAYERS + 1][32];
int g_iInventoryVersion[MAXPLAYERS + 1] = {0, ...};
int g_iMenuInventoryVersion[MAXPLAYERS + 1] = {0, ...};
int g_iTradeSenderInvVersion[MAXPLAYERS + 1] = {0, ...};
int g_iTradeTargetInvVersion[MAXPLAYERS + 1] = {0, ...};
float g_fNextPreview[MAXPLAYERS + 1] = {0.0, ...};
float g_fNextEquipTime[MAXPLAYERS + 1] = {0.0, ...};
char g_szDefaultPlayerModel[MAXPLAYERS + 1][PLATFORM_MAX_PATH];

ConVar gCvarDatabase;
ConVar gCvarStoreEnabled;
ConVar gCvarCreditsTimeEnabled;
ConVar gCvarCreditsTimeAmount;
ConVar gCvarCreditsTimeInterval;
ConVar gCvarCreditsKillEnabled;
ConVar gCvarCreditsKillAmount;
ConVar gCvarCreditsHeadshotBonus;
ConVar gCvarCreditsRoundWinEnabled;
ConVar gCvarCreditsRoundWinAmount;
ConVar gCvarCreditsPlantEnabled;
ConVar gCvarCreditsPlantAmount;
ConVar gCvarCreditsDefuseEnabled;
ConVar gCvarCreditsDefuseAmount;
ConVar gCvarCreditsAfkMax;
ConVar gCvarCreditsNotifyDelay;
ConVar gCvarCreditsAutosaveInterval;
ConVar gCvarInitialCredits;
ConVar gCvarSellPercent;
ConVar gCvarPreviewLifetime;
ConVar gCvarPreviewDistance;
ConVar gCvarPreviewZOffset;
ConVar gCvarEnablePlayerSkins;
ConVar gCvarPreviewCooldown;
ConVar gCvarEquipCooldown;
ConVar gCvarExtendedChatColors;
ConVar gCvarExtendedChatAutoFallback;

Handle g_hCreditsTimeTimer = null;
Handle g_hCreditsAutosaveTimer = null;
Handle g_hCreditNotifyTimer[MAXPLAYERS + 1] = {null, ...};
Handle g_hPreviewTimer[MAXPLAYERS + 1] = {null, ...};
bool g_bCreditsDirty[MAXPLAYERS + 1] = {false, ...};
int g_iCreditSaveToken[MAXPLAYERS + 1] = {0, ...};
int g_iCreditSaveInFlight[MAXPLAYERS + 1] = {0, ...};
float g_fLastActivity[MAXPLAYERS + 1] = {0.0, ...};
int g_iCreditReasonTime[MAXPLAYERS + 1] = {0, ...};
int g_iCreditReasonKill[MAXPLAYERS + 1] = {0, ...};
int g_iCreditReasonHeadshot[MAXPLAYERS + 1] = {0, ...};
int g_iCreditReasonRoundWin[MAXPLAYERS + 1] = {0, ...};
int g_iCreditReasonPlant[MAXPLAYERS + 1] = {0, ...};
int g_iCreditReasonDefuse[MAXPLAYERS + 1] = {0, ...};


Handle g_hFwdCreditsGiven = null;
Handle g_hFwdItemPurchased = null;
Handle g_hFwdItemEquipped = null;
Handle g_hFwdTradeCompleted = null;

// =========================================================================
// API PÚBLICA
// =========================================================================
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("CS_UpdateClientModel");

    RegPluginLibrary("umbrella_store");
    CreateNative("US_IsLoaded", Native_US_IsLoaded);
    CreateNative("US_GetCredits", Native_US_GetCredits);
    CreateNative("US_SetCredits", Native_US_SetCredits);
    CreateNative("US_AddCredits", Native_US_AddCredits);
    CreateNative("US_TakeCredits", Native_US_TakeCredits);
    CreateNative("US_HasItem", Native_US_HasItem);
    CreateNative("US_GiveItem", Native_US_GiveItem);
    CreateNative("US_RemoveItem", Native_US_RemoveItem);
    CreateNative("US_Casino_Register", Native_US_Casino_Register);
    CreateNative("US_Casino_Unregister", Native_US_Casino_Unregister);
    CreateNative("US_OpenCasinoMenu", Native_US_OpenCasinoMenu);
    return APLRes_Success;
}

public Plugin myinfo =
{
    name = "[Umbrella Store] Core",
    author = "Ayrton09",
    description = "Core store module for Umbrella Store",
    version = "1.0.0",
    url = ""
};

// =========================================================================
// FORWARDS PRINCIPALES
// =========================================================================
public void OnPluginStart()
{
    g_aItems = new ArrayList(sizeof(StoreItem));
    g_aCasinoIds = new ArrayList(32);
    g_mItemIndex = new StringMap();
    g_mCasinoTitles = new StringMap();
    g_mCasinoCommands = new StringMap();
    g_mCasinoIndex = new StringMap();

    LoadTranslations("umbrella_store.phrases");
    gCvarDatabase = CreateConVar("store_database", STORE_DB_CONFIG, "Explicit database entry name from databases.cfg (no automatic fallback).");
    g_hFwdCreditsGiven = CreateGlobalForward("OnStoreCreditsGiven", ET_Ignore, Param_Cell, Param_Cell, Param_String);
    g_hFwdItemPurchased = CreateGlobalForward("OnStoreItemPurchased", ET_Ignore, Param_Cell, Param_String);
    g_hFwdItemEquipped = CreateGlobalForward("OnStoreItemEquipped", ET_Ignore, Param_Cell, Param_String, Param_Cell);
    g_hFwdTradeCompleted = CreateGlobalForward("OnStoreTradeCompleted", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_String);

    RegConsoleCmd("sm_store", Cmd_Store);
    RegConsoleCmd("sm_tienda", Cmd_Store);

    RegConsoleCmd("sm_creditos", Cmd_Credits);
    RegConsoleCmd("sm_credits", Cmd_Credits);
    RegConsoleCmd("sm_topcredits", Cmd_TopCredits);

    RegConsoleCmd("sm_inv", Cmd_Inv);
    RegConsoleCmd("sm_inventory", Cmd_Inv);
    RegConsoleCmd("sm_inventario", Cmd_Inv);
    RegConsoleCmd("sm_gift", Cmd_Gift);
    RegConsoleCmd("sm_regalar", Cmd_Gift);
    RegConsoleCmd("sm_trade", Cmd_Trade);
    RegConsoleCmd("sm_tradear", Cmd_Trade);

    RegAdminCmd("sm_givecredits", Cmd_GiveCredits, ADMFLAG_ROOT);
    RegAdminCmd("sm_setcredits", Cmd_SetCredits, ADMFLAG_ROOT);
    RegAdminCmd("sm_storeaudit", Cmd_StoreAudit, ADMFLAG_ROOT);
    RegAdminCmd("sm_reloadstore", Cmd_ReloadStore, ADMFLAG_ROOT);

    SetupCreditCvars();
    HookConVarChange(gCvarEnablePlayerSkins, OnPlayerSkinsToggleChanged);

    HookEventEx("player_spawn", Event_PlayerSpawn);
    HookEventEx("player_death", Event_PlayerDeath);
    HookEventEx("player_team", Event_PlayerTeam);
    HookEventEx("round_end", Event_RoundEnd);
    HookEventEx("teamplay_round_win", Event_TeamplayRoundWin);
    HookEventEx("bomb_planted", Event_BombPlanted);
    HookEventEx("bomb_defused", Event_BombDefused);

    StartCreditTimers();

    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_SayTeam, "say_team");

    for (int i = 1; i <= MaxClients; i++)
    {
        ResetClientData(i, false);
    }

    LoadItemsConfig();
}

public void OnConfigsExecuted()
{
    if (g_DB == null)
    {
        ConnectDatabase();
    }
}

public void OnMapStart()
{
    LoadItemsConfig();
}

public void OnMapEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        RemovePreview(i);
    }
}

public void OnClientDisconnect(int client)
{
    if (!IsFakeClient(client) && g_bIsLoaded[client])
    {
        SavePlayer(client);
    }

    ResetClientData(client, true);
}

public void OnClientAuthorized(int client, const char[] auth)
{
    if (!IsValidClientConnected(client))
    {
        return;
    }

    if (g_bLateDatabaseReady && !g_bIsLoaded[client] && !g_bIsLoading[client])
    {
        LoadPlayer(client);
    }
}

public void OnClientPutInServer(int client)
{
    if (!IsValidClientConnected(client))
    {
        return;
    }

    if (g_bLateDatabaseReady && !g_bIsLoaded[client] && !g_bIsLoading[client])
    {
        LoadPlayer(client);
    }
}

// =========================================================================
// HELPERS GENERALES
// =========================================================================

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (client > 0 && client <= MaxClients && !IsFakeClient(client) && IsClientInGame(client))
    {
        if (buttons != 0 || FloatAbs(vel[0]) > 0.1 || FloatAbs(vel[1]) > 0.1 || FloatAbs(vel[2]) > 0.1)
        {
            g_fLastActivity[client] = GetGameTime();
        }
    }

    return Plugin_Continue;
}

bool IsValidClientConnected(int client)
{
    return (client > 0 && client <= MaxClients && IsClientConnected(client) && !IsFakeClient(client));
}

bool IsValidHumanClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

bool IsStoreEnabled()
{
    return (gCvarStoreEnabled == null || gCvarStoreEnabled.BoolValue);
}

bool EnsureStoreEnabledForClient(int client, bool notify = true)
{
    if (IsStoreEnabled())
    {
        return true;
    }

    if (notify && IsValidHumanClient(client))
    {
        PrintStorePhrase(client, "%T", "Store Disabled", client);
    }

    return false;
}

void FormatCooldownText(float seconds, char[] buffer, int maxlen)
{
    if (seconds < 0.1)
    {
        seconds = 0.1;
    }

    Format(buffer, maxlen, "%.1f", seconds);
}

void ResetClientData(int client, bool clearInventory)
{
    if (g_mInventoryOwned[client] == null)
    {
        g_mInventoryOwned[client] = new StringMap();
    }
    else
    {
        g_mInventoryOwned[client].Clear();
    }

    g_iCredits[client] = 0;
    g_bIsLoaded[client] = false;
    g_bIsLoading[client] = false;
    g_bDetailFromInventory[client] = false;
    g_szBrowseType[client][0] = '\0';
    g_iBrowseTeam[client] = 0;
    g_szInvFilter[client][0] = '\0';
    g_szLastDetailItem[client][0] = '\0';
    g_bCreditsDirty[client] = false;
    g_iCreditSaveToken[client] = 0;
    g_iCreditSaveInFlight[client] = 0;
    g_iInventoryVersion[client] = 0;
    g_iMenuInventoryVersion[client] = 0;
    g_iTradeSenderInvVersion[client] = 0;
    g_iTradeTargetInvVersion[client] = 0;
    g_fLastActivity[client] = GetGameTime();
    g_iCreditReasonTime[client] = 0;
    g_iCreditReasonKill[client] = 0;
    g_iCreditReasonHeadshot[client] = 0;
    g_iCreditReasonRoundWin[client] = 0;
    g_iCreditReasonPlant[client] = 0;
    g_iCreditReasonDefuse[client] = 0;
    g_fNextPreview[client] = 0.0;
    g_fNextEquipTime[client] = 0.0;
    g_szDefaultPlayerModel[client][0] = '\0';

    if (g_hCreditNotifyTimer[client] != null)
    {
        KillTimer(g_hCreditNotifyTimer[client]);
        g_hCreditNotifyTimer[client] = null;
    }

    if (g_hPreviewTimer[client] != null)
    {
        KillTimer(g_hPreviewTimer[client]);
        g_hPreviewTimer[client] = null;
    }

    RemovePreview(client);
    g_iPreviewEntity[client] = INVALID_ENT_REFERENCE;

    if (clearInventory && g_hInventory[client] != null)
    {
        delete g_hInventory[client];
        g_hInventory[client] = null;
    }
}

bool HasAccess(int client, const char[] flagString)
{
    if (flagString[0] == '\0')
    {
        return true;
    }

    int flags = ReadFlagString(flagString);
    return CheckCommandAccess(client, "", flags, true);
}

void LogStoreError(const char[] where, const char[] error)
{
    if (error[0] != '\0')
    {
        LogError("%s %s: %s", STORE_LOG_PREFIX, where, error);
    }
}

bool GetClientSteamIdSafe(int client, char[] steamid, int maxlen)
{
    if (!GetClientAuthId(client, AuthId_Steam2, steamid, maxlen))
    {
        steamid[0] = '\0';
        return false;
    }

    return true;
}

void EscapeStringSafe(const char[] input, char[] output, int maxlen)
{
    if (g_DB == null)
    {
        strcopy(output, maxlen, input);
        return;
    }

    g_DB.Escape(input, output, maxlen);
}

void InvalidateItemCache()
{
    g_bItemCacheReady = false;

    if (g_mItemIndex != null)
    {
        g_mItemIndex.Clear();
    }
}

void RebuildItemCache()
{
    if (g_mItemIndex == null)
    {
        g_mItemIndex = new StringMap();
    }
    else
    {
        g_mItemIndex.Clear();
    }

    StoreItem item;
    for (int i = 0; i < g_aItems.Length; i++)
    {
        g_aItems.GetArray(i, item, sizeof(StoreItem));
        g_mItemIndex.SetValue(item.id, i);
    }

    g_bItemCacheReady = true;
}

int FindStoreItemIndexById(const char[] itemId)
{
    if (itemId[0] == ' ' || g_aItems == null)
    {
        return -1;
    }

    if (!g_bItemCacheReady || g_mItemIndex == null)
    {
        RebuildItemCache();
    }

    int index;
    if (g_mItemIndex != null && g_mItemIndex.GetValue(itemId, index) && index >= 0 && index < g_aItems.Length)
    {
        return index;
    }

    RebuildItemCache();

    if (g_mItemIndex != null && g_mItemIndex.GetValue(itemId, index) && index >= 0 && index < g_aItems.Length)
    {
        return index;
    }

    return -1;
}

bool FindStoreItemById(const char[] itemId, StoreItem item)
{
    int index = FindStoreItemIndexById(itemId);
    if (index == -1)
    {
        return false;
    }

    g_aItems.GetArray(index, item, sizeof(StoreItem));
    return true;
}

void InventoryOwnedSet(int client, const char[] itemId, bool owned)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    if (g_mInventoryOwned[client] == null)
    {
        g_mInventoryOwned[client] = new StringMap();
    }

    if (owned)
    {
        g_mInventoryOwned[client].SetValue(itemId, 1);
    }
    else
    {
        g_mInventoryOwned[client].Remove(itemId);
    }
}

int FindInventoryIndexByItemId(int client, const char[] itemId)
{
    if (g_hInventory[client] == null)
    {
        return -1;
    }

    InventoryItem inv;
    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (StrEqual(inv.item_id, itemId))
        {
            return i;
        }
    }

    return -1;
}

bool PlayerOwnsItem(int client, const char[] itemId)
{
    if (client < 1 || client > MaxClients)
    {
        return false;
    }

    if (g_mInventoryOwned[client] != null)
    {
        int value;
        if (g_mInventoryOwned[client].GetValue(itemId, value))
        {
            return true;
        }
    }

    return (FindInventoryIndexByItemId(client, itemId) != -1);
}

int GetSellPrice(int price)
{
    if (price <= 0)
    {
        return 0;
    }

    int sellPercent = (gCvarSellPercent != null) ? gCvarSellPercent.IntValue : STORE_SELL_PERCENT;
    if (sellPercent < 0)
    {
        sellPercent = 0;
    }
    else if (sellPercent > 100)
    {
        sellPercent = 100;
    }

    return (price * sellPercent) / 100;
}

void FormatNumberDots(int value, char[] buffer, int maxlen)
{
    char raw[32];
    IntToString(value, raw, sizeof(raw));

    int len = strlen(raw);
    int start = 0;
    bool negative = false;

    if (raw[0] == '-')
    {
        negative = true;
        start = 1;
    }

    char temp[32];
    int out = 0;

    if (negative)
    {
        temp[out++] = '-';
    }

    for (int i = start; i < len; i++)
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

void FormatCreditsAmount(int client, int value, char[] buffer, int maxlen)
{
    char number[32];
    FormatNumberDots(value, number, sizeof(number));
    Format(buffer, maxlen, "%T", "Credits Amount", client, number);
}

void GetStorePrefix(int client, char[] buffer, int maxlen)
{
    Format(buffer, maxlen, "%T", "Store Prefix", client);
    ReplaceColorTags(buffer, maxlen);
}

void FormatStorePhrase(int client, char[] buffer, int maxlen, const char[] phrase)
{
    Format(buffer, maxlen, "%T", phrase, client);
}

void SetMenuTitlePhrase(Menu menu, int client, const char[] phrase)
{
    char title[192];
    FormatStorePhrase(client, title, sizeof(title), phrase);
    menu.SetTitle(title);
}

void AddMenuItemPhrase(Menu menu, const char[] info, int client, const char[] phrase, int style = ITEMDRAW_DEFAULT)
{
    char display[192];
    FormatStorePhrase(client, display, sizeof(display), phrase);
    menu.AddItem(info, display, style);
}

void PrintStorePhrase(int client, const char[] format, any ...)
{
    if (!IsValidHumanClient(client))
    {
        return;
    }

    char prefix[64], translated[256], highlighted[320], finalMsg[448];
    GetStorePrefix(client, prefix, sizeof(prefix));
    SetGlobalTransTarget(client);
    VFormat(translated, sizeof(translated), format, 3);
    ReplaceColorTags(translated, sizeof(translated));
    HighlightChatCommands(translated, highlighted, sizeof(highlighted));
    Format(finalMsg, sizeof(finalMsg), " %s %s", prefix, highlighted);
    PrintToChat(client, "%s", finalMsg);
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

void ForwardCreditsGiven(int client, int amount, const char[] reason)
{
    if (g_hFwdCreditsGiven == null)
    {
        return;
    }
    Call_StartForward(g_hFwdCreditsGiven);
    Call_PushCell(client);
    Call_PushCell(amount);
    Call_PushString(reason);
    Call_Finish();
}

void ForwardItemPurchased(int client, const char[] itemId)
{
    if (g_hFwdItemPurchased == null)
    {
        return;
    }
    Call_StartForward(g_hFwdItemPurchased);
    Call_PushCell(client);
    Call_PushString(itemId);
    Call_Finish();
}

void ForwardItemEquipped(int client, const char[] itemId, bool equipped)
{
    if (g_hFwdItemEquipped == null)
    {
        return;
    }
    Call_StartForward(g_hFwdItemEquipped);
    Call_PushCell(client);
    Call_PushString(itemId);
    Call_PushCell(equipped);
    Call_Finish();
}

void ForwardTradeCompleted(int sender, int target, const char[] senderItemId, const char[] targetItemId)
{
    if (g_hFwdTradeCompleted == null)
    {
        return;
    }
    Call_StartForward(g_hFwdTradeCompleted);
    Call_PushCell(sender);
    Call_PushCell(target);
    Call_PushString(senderItemId);
    Call_PushString(targetItemId);
    Call_Finish();
}

bool GiveItemToClient(int client, const char[] itemId, bool equip = false, bool saveNow = true)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null || g_DB == null)
    {
        return false;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item) || PlayerOwnsItem(client, item.id))
    {
        return false;
    }

    char steamid[32], safeSteamId[64], safeItemId[64], query[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(item.id, safeItemId, sizeof(safeItemId));

    if (g_bIsMySQL)
    {
        Format(query, sizeof(query), "INSERT INTO store_inventory (steamid, item_id, is_equipped) VALUES ('%s', '%s', 0)", safeSteamId, safeItemId);
    }
    else
    {
        Format(query, sizeof(query), "INSERT INTO store_inventory (steamid, item_id, is_equipped) VALUES ('%s', '%s', 0)", safeSteamId, safeItemId);
    }

    if (!BeginLockedStoreTransaction("GiveItemToClient"))
    {
        return false;
    }

    if (!ExecuteLockedStoreQuery("GiveItemToClient", query, 1))
    {
        RollbackLockedStoreTransaction("GiveItemToClient");
        return false;
    }

    if (!CommitLockedStoreTransaction("GiveItemToClient"))
    {
        return false;
    }

    InventoryItem newInv;
    strcopy(newInv.item_id, sizeof(newInv.item_id), item.id);
    newInv.is_equipped = 0;
    g_hInventory[client].PushArray(newInv, sizeof(InventoryItem));
    InventoryOwnedSet(client, item.id, true);
    MarkInventoryChanged(client);

    if (equip)
    {
        ToggleEquip(client, item.id);
    }

    if (saveNow)
    {
        SavePlayer(client);
    }

    return true;
}

bool RemoveItemFromClient(int client, const char[] itemId, bool saveNow = true)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null || g_DB == null)
    {
        return false;
    }

    int index = FindInventoryIndexByItemId(client, itemId);
    if (index == -1)
    {
        return false;
    }

    char steamid[32], safeSteamId[64], safeItemId[64], query[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));

    InventoryItem inv;
    g_hInventory[client].GetArray(index, inv, sizeof(InventoryItem));
    bool wasEquipped = view_as<bool>(inv.is_equipped);

    Format(query, sizeof(query), "DELETE FROM store_inventory WHERE steamid = '%s' AND item_id = '%s'", safeSteamId, safeItemId);

    if (!BeginLockedStoreTransaction("RemoveItemFromClient"))
    {
        return false;
    }

    if (!ExecuteLockedStoreQuery("RemoveItemFromClient", query, 1))
    {
        RollbackLockedStoreTransaction("RemoveItemFromClient");
        return false;
    }

    if (!CommitLockedStoreTransaction("RemoveItemFromClient"))
    {
        return false;
    }

    g_hInventory[client].Erase(index);
    InventoryOwnedSet(client, itemId, false);
    MarkInventoryChanged(client);

    if (wasEquipped)
    {
        StoreItem item;
        if (FindStoreItemById(itemId, item) && StrEqual(item.type, "skin"))
        {
            ApplyPlayerSkin(client);
        }
    }

    if (saveNow)
    {
        SavePlayer(client);
    }
    return true;
}

void SetupCreditCvars()
{
    gCvarStoreEnabled = CreateConVar("store_enabled", "1", "Enable or disable Umbrella Store globally.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gCvarCreditsTimeEnabled = CreateConVar("store_credits_time_enabled", "1", "Enable credits for time played.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarCreditsTimeAmount = CreateConVar("store_credits_time_amount", "10", "Credits earned per time interval.", FCVAR_NONE, true, 0.0);
    gCvarCreditsTimeInterval = CreateConVar("store_credits_time_interval", "60", "Interval in seconds for time-based credits.", FCVAR_NONE, true, 10.0);
    gCvarCreditsKillEnabled = CreateConVar("store_credits_kill_enabled", "1", "Enable credits for kills.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarCreditsKillAmount = CreateConVar("store_credits_kill_amount", "2", "Credits earned per kill.", FCVAR_NONE, true, 0.0);
    gCvarCreditsHeadshotBonus = CreateConVar("store_credits_headshot_bonus", "1", "Extra credits for headshots.", FCVAR_NONE, true, 0.0);
    gCvarCreditsRoundWinEnabled = CreateConVar("store_credits_roundwin_enabled", "1", "Enable credits for round wins.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarCreditsRoundWinAmount = CreateConVar("store_credits_roundwin_amount", "3", "Credits earned per round win.", FCVAR_NONE, true, 0.0);
    gCvarCreditsPlantEnabled = CreateConVar("store_credits_plant_enabled", "1", "Enable credits for bomb plant.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarCreditsPlantAmount = CreateConVar("store_credits_plant_amount", "2", "Credits earned for bomb plant.", FCVAR_NONE, true, 0.0);
    gCvarCreditsDefuseEnabled = CreateConVar("store_credits_defuse_enabled", "1", "Enable credits for bomb defuse.", FCVAR_NONE, true, 0.0, true, 1.0);
    gCvarCreditsDefuseAmount = CreateConVar("store_credits_defuse_amount", "3", "Credits earned for bomb defuse.", FCVAR_NONE, true, 0.0);
    gCvarCreditsAfkMax = CreateConVar("store_credits_afk_max", "90", "Maximum idle seconds allowed to receive time-based credits.", FCVAR_NONE, true, 15.0);
    gCvarCreditsNotifyDelay = CreateConVar("store_credits_notify_delay", "2.0", "Delay in seconds to group credit messages and reduce spam.", FCVAR_NONE, true, 0.1);
    gCvarCreditsAutosaveInterval = CreateConVar("store_credits_autosave_interval", "120.0", "Auto-save interval for credits in seconds.", FCVAR_NONE, true, 30.0);
    gCvarInitialCredits = CreateConVar("store_initial_credits", "50000", "Initial credits for new players.", FCVAR_NONE, true, 0.0);
    gCvarSellPercent = CreateConVar("store_sell_percent", "50", "Refund percentage when selling items.", FCVAR_NONE, true, 0.0, true, 100.0);
    gCvarPreviewLifetime = CreateConVar("store_preview_lifetime", "15.0", "Preview lifetime in seconds.", FCVAR_NONE, true, 1.0);
    gCvarPreviewDistance = CreateConVar("store_preview_distance", "100.0", "Distance at which preview appears.", FCVAR_NONE, true, 1.0);
    gCvarPreviewZOffset = CreateConVar("store_preview_zoffset", "60.0", "Vertical offset for preview.", FCVAR_NONE, true, -500.0, true, 500.0);
    gCvarEnablePlayerSkins = CreateConVar("store_enable_player_skins", "1", "Enable or disable store player skins.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gCvarPreviewCooldown = CreateConVar("store_preview_cooldown", "3.0", "Cooldown between skin previews in seconds.", FCVAR_NONE, true, 0.0);
    gCvarEquipCooldown = CreateConVar("store_equip_cooldown", "0.35", "Cooldown between equip and unequip actions in seconds.", FCVAR_NONE, true, 0.0);
    gCvarExtendedChatColors = CreateConVar("store_chat_extended_colors", "1", "Enable extended chat color palette for tags/namecolor/chatcolor. 0 = compatible, 1 = extended.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gCvarExtendedChatAutoFallback = CreateConVar("store_chat_extended_autofallback", "1", "If 1, automatically fallback to basic palette on untested engines for extended colors.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    HookConVarChange(gCvarCreditsTimeInterval, OnCreditTimerSettingsChanged);
    HookConVarChange(gCvarCreditsAutosaveInterval, OnCreditTimerSettingsChanged);

    AutoExecConfig(true, "umbrella_store_core");
}

public void OnCreditTimerSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    StartCreditTimers();
}

void StartCreditTimers()
{
    if (g_hCreditsTimeTimer != null)
    {
        KillTimer(g_hCreditsTimeTimer);
        g_hCreditsTimeTimer = null;
    }

    if (g_hCreditsAutosaveTimer != null)
    {
        KillTimer(g_hCreditsAutosaveTimer);
        g_hCreditsAutosaveTimer = null;
    }

    g_hCreditsTimeTimer = CreateTimer(float(gCvarCreditsTimeInterval.IntValue), Timer_GiveTimeCredits, _, TIMER_REPEAT);
    g_hCreditsAutosaveTimer = CreateTimer(gCvarCreditsAutosaveInterval.FloatValue, Timer_AutoSaveCredits, _, TIMER_REPEAT);
}

void MarkClientActive(int client)
{
    if (client > 0 && client <= MaxClients)
    {
        g_fLastActivity[client] = GetGameTime();
    }
}

bool IsClientEligibleForTimeCredits(int client)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return false;
    }

    int team = GetClientTeam(client);
    if (team < 2)
    {
        return false;
    }

    float afkSeconds = GetGameTime() - g_fLastActivity[client];
    return (afkSeconds <= gCvarCreditsAfkMax.FloatValue);
}

void QueueCreditNotification(int client, int amount, const char[] reason)
{
    if (!IsValidHumanClient(client) || amount <= 0)
    {
        return;
    }

    if (StrEqual(reason, "time"))
    {
        g_iCreditReasonTime[client] += amount;
    }
    else if (StrEqual(reason, "kill"))
    {
        g_iCreditReasonKill[client] += amount;
    }
    else if (StrEqual(reason, "headshot"))
    {
        g_iCreditReasonHeadshot[client] += amount;
    }
    else if (StrEqual(reason, "roundwin"))
    {
        g_iCreditReasonRoundWin[client] += amount;
    }
    else if (StrEqual(reason, "plant"))
    {
        g_iCreditReasonPlant[client] += amount;
    }
    else if (StrEqual(reason, "defuse"))
    {
        g_iCreditReasonDefuse[client] += amount;
    }

    if (g_hCreditNotifyTimer[client] == null)
    {
        g_hCreditNotifyTimer[client] = CreateTimer(gCvarCreditsNotifyDelay.FloatValue, Timer_FlushCreditNotify, GetClientUserId(client));
    }
}

void LogCreditLedger(int client, int amount, const char[] reason)
{
    if (amount == 0 || g_DB == null || !IsValidClientConnected(client) || reason[0] == '\0')
    {
        return;
    }

    char steamid[32], safeSteamId[64], safeReason[128], query[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(reason, safeReason, sizeof(safeReason));

    Format(query, sizeof(query),
        "INSERT INTO store_credits_ledger (steamid, amount, reason, balance_after, created_at) VALUES ('%s', %d, '%s', %d, %d)",
        safeSteamId, amount, safeReason, g_iCredits[client], GetTime());

    g_DB.Query(DummyCallback, query);
}

void AddCreditsEx(int client, int amount, const char[] reason, bool notify = true)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || amount <= 0)
    {
        return;
    }

    g_iCredits[client] += amount;
    g_bCreditsDirty[client] = true;
    LogCreditLedger(client, amount, reason);

    if (notify)
    {
        QueueCreditNotification(client, amount, reason);
    }

    ForwardCreditsGiven(client, amount, reason);
}

void SaveDirtyPlayers()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_bCreditsDirty[i] && g_bIsLoaded[i] && IsValidClientConnected(i))
        {
            SavePlayer(i);
        }
    }
}

public Action Timer_GiveTimeCredits(Handle timer, any data)
{
    if (!IsStoreEnabled() || !gCvarCreditsTimeEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int amount = gCvarCreditsTimeAmount.IntValue;
    if (amount <= 0)
    {
        return Plugin_Continue;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientEligibleForTimeCredits(i))
        {
            AddCreditsEx(i, amount, "time", true);
        }
    }

    return Plugin_Continue;
}

public Action Timer_AutoSaveCredits(Handle timer, any data)
{
    SaveDirtyPlayers();
    return Plugin_Continue;
}

public Action Timer_FlushCreditNotify(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Stop;
    }

    g_hCreditNotifyTimer[client] = null;

    int total = g_iCreditReasonTime[client] + g_iCreditReasonKill[client] + g_iCreditReasonHeadshot[client] + g_iCreditReasonRoundWin[client] + g_iCreditReasonPlant[client] + g_iCreditReasonDefuse[client];
    if (total <= 0)
    {
        return Plugin_Stop;
    }

    char amountText[32];
    FormatNumberDots(total, amountText, sizeof(amountText));

    if (g_iCreditReasonTime[client] > 0 && total == g_iCreditReasonTime[client])
    {
        PrintStorePhrase(client, "%T", "Credits Time", client, amountText);
    }
    else if (g_iCreditReasonRoundWin[client] > 0 && total == g_iCreditReasonRoundWin[client])
    {
        PrintStorePhrase(client, "%T", "Credits Round Win", client, amountText);
    }
    else if (g_iCreditReasonPlant[client] > 0 && total == g_iCreditReasonPlant[client])
    {
        PrintStorePhrase(client, "%T", "Credits Plant", client, amountText);
    }
    else if (g_iCreditReasonDefuse[client] > 0 && total == g_iCreditReasonDefuse[client])
    {
        PrintStorePhrase(client, "%T", "Credits Defuse", client, amountText);
    }
    else if (g_iCreditReasonKill[client] > 0 && total == (g_iCreditReasonKill[client] + g_iCreditReasonHeadshot[client]))
    {
        if (g_iCreditReasonHeadshot[client] > 0 && g_iCreditReasonKill[client] > 0)
        {
            PrintStorePhrase(client, "%T", "Credits Kill Combo", client, amountText);
        }
        else if (g_iCreditReasonHeadshot[client] > 0)
        {
            PrintStorePhrase(client, "%T", "Credits Kill Headshot", client, amountText);
        }
        else
        {
            PrintStorePhrase(client, "%T", "Credits Kill", client, amountText);
        }
    }
    else
    {
        char details[192];
        details[0] = ' ';
        bool first = true;
        char part[64];
        char partAmount[32];

        if (g_iCreditReasonTime[client] > 0)
        {
            FormatNumberDots(g_iCreditReasonTime[client], partAmount, sizeof(partAmount));
            Format(part, sizeof(part), "%T", "Credits Detail Time", client, partAmount);
            StrCat(details, sizeof(details), part);
            first = false;
        }

        if (g_iCreditReasonKill[client] > 0)
        {
            if (!first)
            {
                StrCat(details, sizeof(details), ", ");
            }
            FormatNumberDots(g_iCreditReasonKill[client], partAmount, sizeof(partAmount));
            Format(part, sizeof(part), "%T", "Credits Detail Kill", client, partAmount);
            StrCat(details, sizeof(details), part);
            first = false;
        }

        if (g_iCreditReasonHeadshot[client] > 0)
        {
            if (!first)
            {
                StrCat(details, sizeof(details), ", ");
            }
            FormatNumberDots(g_iCreditReasonHeadshot[client], partAmount, sizeof(partAmount));
            Format(part, sizeof(part), "%T", "Credits Detail Headshot", client, partAmount);
            StrCat(details, sizeof(details), part);
            first = false;
        }

        if (g_iCreditReasonRoundWin[client] > 0)
        {
            if (!first)
            {
                StrCat(details, sizeof(details), ", ");
            }
            FormatNumberDots(g_iCreditReasonRoundWin[client], partAmount, sizeof(partAmount));
            Format(part, sizeof(part), "%T", "Credits Detail Round Win", client, partAmount);
            StrCat(details, sizeof(details), part);
            first = false;
        }

        if (g_iCreditReasonPlant[client] > 0)
        {
            if (!first)
            {
                StrCat(details, sizeof(details), ", ");
            }
            FormatNumberDots(g_iCreditReasonPlant[client], partAmount, sizeof(partAmount));
            Format(part, sizeof(part), "%T", "Credits Detail Plant", client, partAmount);
            StrCat(details, sizeof(details), part);
            first = false;
        }

        if (g_iCreditReasonDefuse[client] > 0)
        {
            if (!first)
            {
                StrCat(details, sizeof(details), ", ");
            }
            FormatNumberDots(g_iCreditReasonDefuse[client], partAmount, sizeof(partAmount));
            Format(part, sizeof(part), "%T", "Credits Detail Defuse", client, partAmount);
            StrCat(details, sizeof(details), part);
        }

        PrintStorePhrase(client, "%T", "Credits Mixed Breakdown", client, amountText, details);
    }

    g_iCreditReasonTime[client] = 0;
    g_iCreditReasonKill[client] = 0;
    g_iCreditReasonHeadshot[client] = 0;
    g_iCreditReasonRoundWin[client] = 0;
    g_iCreditReasonPlant[client] = 0;
    g_iCreditReasonDefuse[client] = 0;

    return Plugin_Stop;
}


bool CanTransferItemToTarget(int sender, int target, const char[] itemId, bool notify = true)
{
    if (!IsValidHumanClient(sender) || !IsValidHumanClient(target))
    {
        return false;
    }

    if (sender == target)
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Cannot Self", sender);
        }
        return false;
    }

    if (!g_bIsLoaded[sender] || !g_bIsLoaded[target] || g_hInventory[sender] == null || g_hInventory[target] == null)
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Target Inventory Not Loaded", sender);
        }
        return false;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Item Not Found", sender);
        }
        return false;
    }

    if (!PlayerOwnsItem(sender, item.id))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Item Not Owned", sender);
        }
        return false;
    }

    if (PlayerOwnsItem(target, item.id))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Target Already Has Item", sender, target);
        }
        return false;
    }

    if (!HasAccess(target, item.flag))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Target No Access Item", sender, target);
        }
        return false;
    }

    return true;
}


void MarkInventoryChanged(int client)
{
    if (client >= 1 && client <= MaxClients)
    {
        g_iInventoryVersion[client]++;
    }
}

bool ValidateInventoryMenuAction(int client, int expectedVersion, const char[] itemId = "", bool mustOwn = false)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        return false;
    }

    if (expectedVersion != g_iInventoryVersion[client])
    {
        PrintStorePhrase(client, "%T", "Inventory Changed Reopen", client);
        return false;
    }

    if (itemId[0] != '\0')
    {
        StoreItem item;
        if (!FindStoreItemById(itemId, item))
        {
            PrintStorePhrase(client, "%T", "Item Missing Config", client);
            return false;
        }

        if (mustOwn && !PlayerOwnsItem(client, itemId))
        {
            PrintStorePhrase(client, "%T", "Item Not Owned", client);
            return false;
        }
    }

    return true;
}

bool TransferOwnedItem(int sender, int target, const char[] itemId, bool notify = true)
{
    if (g_DB == null || !CanTransferItemToTarget(sender, target, itemId, notify))
    {
        return false;
    }

    int index = FindInventoryIndexByItemId(sender, itemId);
    if (index == -1 || g_hInventory[target] == null)
    {
        return false;
    }

    char steamidSender[32], steamidTarget[32], safeSender[64], safeTarget[64], safeItemId[64], query[256];
    if (!GetClientSteamIdSafe(sender, steamidSender, sizeof(steamidSender)) || !GetClientSteamIdSafe(target, steamidTarget, sizeof(steamidTarget)))
    {
        return false;
    }

    EscapeStringSafe(steamidSender, safeSender, sizeof(safeSender));
    EscapeStringSafe(steamidTarget, safeTarget, sizeof(safeTarget));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));

    InventoryItem inv;
    g_hInventory[sender].GetArray(index, inv, sizeof(InventoryItem));
    bool wasEquipped = view_as<bool>(inv.is_equipped);

    Format(query, sizeof(query), "UPDATE store_inventory SET steamid = '%s', is_equipped = 0 WHERE steamid = '%s' AND item_id = '%s'", safeTarget, safeSender, safeItemId);
    if (!BeginLockedStoreTransaction("TransferOwnedItem"))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Store Transaction Failed", sender);
        }
        return false;
    }

    if (!ExecuteLockedStoreQuery("TransferOwnedItem", query, 1))
    {
        RollbackLockedStoreTransaction("TransferOwnedItem");
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Store Transaction Failed", sender);
        }
        return false;
    }

    if (!CommitLockedStoreTransaction("TransferOwnedItem"))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Store Transaction Failed", sender);
        }
        return false;
    }

    g_hInventory[sender].Erase(index);
    InventoryOwnedSet(sender, itemId, false);

    InventoryItem newInv;
    strcopy(newInv.item_id, sizeof(newInv.item_id), itemId);
    newInv.is_equipped = 0;
    g_hInventory[target].PushArray(newInv, sizeof(InventoryItem));
    InventoryOwnedSet(target, itemId, true);
    MarkInventoryChanged(sender);
    MarkInventoryChanged(target);

    StoreItem item;
    FindStoreItemById(itemId, item);

    if (wasEquipped && StrEqual(item.type, "skin"))
    {
        ApplyPlayerSkin(sender);
    }

    return true;
}

bool ExecuteTrade(int sender, int target, const char[] senderItemId, const char[] targetItemId)
{
    if (sender == target || StrEqual(senderItemId, targetItemId))
    {
        return false;
    }

    if (!CanTransferItemToTarget(sender, target, senderItemId, false) || !CanTransferItemToTarget(target, sender, targetItemId, false))
    {
        return false;
    }

    int senderIndex = FindInventoryIndexByItemId(sender, senderItemId);
    int targetIndex = FindInventoryIndexByItemId(target, targetItemId);
    if (senderIndex == -1 || targetIndex == -1)
    {
        return false;
    }

    char steamidSender[32], steamidTarget[32], safeSender[64], safeTarget[64];
    char safeSenderItemId[64], safeTargetItemId[64];
    if (!GetClientSteamIdSafe(sender, steamidSender, sizeof(steamidSender)) || !GetClientSteamIdSafe(target, steamidTarget, sizeof(steamidTarget)))
    {
        return false;
    }

    EscapeStringSafe(steamidSender, safeSender, sizeof(safeSender));
    EscapeStringSafe(steamidTarget, safeTarget, sizeof(safeTarget));
    EscapeStringSafe(senderItemId, safeSenderItemId, sizeof(safeSenderItemId));
    EscapeStringSafe(targetItemId, safeTargetItemId, sizeof(safeTargetItemId));

    InventoryItem senderInv, targetInv;
    g_hInventory[sender].GetArray(senderIndex, senderInv, sizeof(InventoryItem));
    g_hInventory[target].GetArray(targetIndex, targetInv, sizeof(InventoryItem));

    bool senderWasEquipped = view_as<bool>(senderInv.is_equipped);
    bool targetWasEquipped = view_as<bool>(targetInv.is_equipped);

    StoreItem senderItem, targetItem;
    if (!FindStoreItemById(senderItemId, senderItem) || !FindStoreItemById(targetItemId, targetItem))
    {
        return false;
    }

    char query[256];
    if (!BeginLockedStoreTransaction("ExecuteTrade"))
    {
        return false;
    }

    Format(query, sizeof(query), "UPDATE store_inventory SET steamid = '%s', is_equipped = 0 WHERE steamid = '%s' AND item_id = '%s'", safeTarget, safeSender, safeSenderItemId);
    if (!ExecuteLockedStoreQuery("ExecuteTrade", query, 1))
    {
        RollbackLockedStoreTransaction("ExecuteTrade");
        return false;
    }

    Format(query, sizeof(query), "UPDATE store_inventory SET steamid = '%s', is_equipped = 0 WHERE steamid = '%s' AND item_id = '%s'", safeSender, safeTarget, safeTargetItemId);
    if (!ExecuteLockedStoreQuery("ExecuteTrade", query, 1))
    {
        RollbackLockedStoreTransaction("ExecuteTrade");
        return false;
    }

    if (!CommitLockedStoreTransaction("ExecuteTrade"))
    {
        return false;
    }

    g_hInventory[sender].Erase(senderIndex);
    g_hInventory[target].Erase(targetIndex);
    InventoryOwnedSet(sender, senderItemId, false);
    InventoryOwnedSet(target, targetItemId, false);

    InventoryItem newSenderInv, newTargetInv;
    strcopy(newSenderInv.item_id, sizeof(newSenderInv.item_id), targetItemId);
    newSenderInv.is_equipped = 0;
    strcopy(newTargetInv.item_id, sizeof(newTargetInv.item_id), senderItemId);
    newTargetInv.is_equipped = 0;

    g_hInventory[sender].PushArray(newSenderInv, sizeof(InventoryItem));
    g_hInventory[target].PushArray(newTargetInv, sizeof(InventoryItem));
    InventoryOwnedSet(sender, targetItemId, true);
    InventoryOwnedSet(target, senderItemId, true);
    MarkInventoryChanged(sender);
    MarkInventoryChanged(target);

    if (senderWasEquipped && StrEqual(senderItem.type, "skin"))
    {
        ApplyPlayerSkin(sender);
    }

    if (targetWasEquipped && StrEqual(targetItem.type, "skin"))
    {
        ApplyPlayerSkin(target);
    }

    return true;
}

bool CanPlayerUseItem(int client, StoreItem item, bool notify = false)
{
    if (!HasAccess(client, item.flag))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "No Access Item", client);
        }
        return false;
    }

    if (StrEqual(item.type, "skin"))
    {
        int team = GetClientTeam(client);
        if (item.team != 0 && team > 1 && item.team != team)
        {
            if (notify)
            {
                PrintStorePhrase(client, "%T", "Skin Wrong Team", client);
            }
            return false;
        }
    }

    return true;
}

void RemovePreview(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    if (g_hPreviewTimer[client] != null)
    {
        KillTimer(g_hPreviewTimer[client]);
        g_hPreviewTimer[client] = null;
    }

    int ent = EntRefToEntIndex(g_iPreviewEntity[client]);
    if (ent != INVALID_ENT_REFERENCE && ent != -1 && IsValidEntity(ent))
    {
        AcceptEntityInput(ent, "Kill");
    }

    g_iPreviewEntity[client] = INVALID_ENT_REFERENCE;
}

// =========================================================================
// PREVIEW
// =========================================================================
void SpawnPreview(int client, const char[] modelPath)
{
    if (!IsValidHumanClient(client) || !IsPlayerAlive(client))
    {
        PrintStorePhrase(client, "%T", "Preview Need Alive", client);
        return;
    }

    float now = GetGameTime();
    float previewCooldown = (gCvarPreviewCooldown != null) ? gCvarPreviewCooldown.FloatValue : 0.0;
    if (previewCooldown > 0.0 && now < g_fNextPreview[client])
    {
        char cooldownText[16];
        FormatCooldownText(g_fNextPreview[client] - now, cooldownText, sizeof(cooldownText));
        PrintStorePhrase(client, "%T", "Preview Cooldown", client, cooldownText);
        return;
    }

    if (modelPath[0] == '\0' || !FileExists(modelPath, true))
    {
        PrintStorePhrase(client, "%T", "Preview Missing Model", client);
        return;
    }

    RemovePreview(client);

    PrecacheModel(modelPath, true);

    int ent = CreateEntityByName("prop_dynamic_override");
    if (ent == -1)
    {
        PrintStorePhrase(client, "%T", "Preview Failed Create", client);
        return;
    }

    DispatchKeyValue(ent, "model", modelPath);
    DispatchKeyValue(ent, "solid", "0");
    DispatchKeyValue(ent, "DefaultAnim", "idle");
    DispatchSpawn(ent);
    SDKHook(ent, SDKHook_SetTransmit, Hook_PreviewSetTransmit);

    float pos[3], ang[3], fwd[3];
    GetClientEyePosition(client, pos);
    GetClientEyeAngles(client, ang);
    GetAngleVectors(ang, fwd, NULL_VECTOR, NULL_VECTOR);

    float previewDistance = (gCvarPreviewDistance != null) ? gCvarPreviewDistance.FloatValue : PREVIEW_DISTANCE;
    float previewZOffset = (gCvarPreviewZOffset != null) ? gCvarPreviewZOffset.FloatValue : PREVIEW_Z_OFFSET;
    float previewLifetime = (gCvarPreviewLifetime != null) ? gCvarPreviewLifetime.FloatValue : PREVIEW_LIFETIME;

    pos[0] += fwd[0] * previewDistance;
    pos[1] += fwd[1] * previewDistance;
    pos[2] -= previewZOffset;

    ang[0] = 0.0;
    ang[1] += 180.0;
    ang[2] = 0.0;

    TeleportEntity(ent, pos, ang, NULL_VECTOR);
    SetVariantString("idle");
    AcceptEntityInput(ent, "SetAnimation");

    g_iPreviewEntity[client] = EntIndexToEntRef(ent);
    g_fNextPreview[client] = now + previewCooldown;
    g_hPreviewTimer[client] = CreateTimer(previewLifetime, Timer_RemovePreview, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

    char lifetimeText[16];
    Format(lifetimeText, sizeof(lifetimeText), "%d", RoundToFloor(previewLifetime));
    PrintStorePhrase(client, "%T", "Preview Started", client, lifetimeText);
}

public Action Timer_RemovePreview(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client < 1 || client > MaxClients)
    {
        return Plugin_Stop;
    }

    if (g_hPreviewTimer[client] != timer)
    {
        return Plugin_Stop;
    }

    g_hPreviewTimer[client] = null;
    RemovePreview(client);
    return Plugin_Stop;
}

// =========================================================================
// COLORES Y CONFIG
// =========================================================================
bool ShouldUseExtendedChatColors()
{
    if (gCvarExtendedChatColors == null || !gCvarExtendedChatColors.BoolValue)
    {
        return false;
    }

    if (gCvarExtendedChatAutoFallback == null || !gCvarExtendedChatAutoFallback.BoolValue)
    {
        return true;
    }

    switch (GetEngineVersion())
    {
        case Engine_CSGO, Engine_CSS, Engine_TF2, Engine_Left4Dead, Engine_Left4Dead2, Engine_DODS, Engine_HL2DM, Engine_SDK2013, Engine_Insurgency, Engine_DOI:
        {
            return true;
        }
    }

    return false;
}

void ReplaceColorTags(char[] buffer, int maxlen)
{
    bool useExtended = ShouldUseExtendedChatColors();

    ReplaceString(buffer, maxlen, "{DEFAULT}", "\x01");
    ReplaceString(buffer, maxlen, "{default}", "\x01");
    ReplaceString(buffer, maxlen, "{TEAM}", "\x03");
    ReplaceString(buffer, maxlen, "{team}", "\x03");
    ReplaceString(buffer, maxlen, "{GREEN}", "\x04");
    ReplaceString(buffer, maxlen, "{green}", "\x04");

    if (useExtended)
    {
        ReplaceString(buffer, maxlen, "{RED}", "\x02");
        ReplaceString(buffer, maxlen, "{red}", "\x02");
        ReplaceString(buffer, maxlen, "{LIME}", "\x05");
        ReplaceString(buffer, maxlen, "{lime}", "\x05");
        ReplaceString(buffer, maxlen, "{LIGHTGREEN}", "\x06");
        ReplaceString(buffer, maxlen, "{lightgreen}", "\x06");
        ReplaceString(buffer, maxlen, "{LIGHTRED}", "\x07");
        ReplaceString(buffer, maxlen, "{lightred}", "\x07");
        ReplaceString(buffer, maxlen, "{GRAY}", "\x08");
        ReplaceString(buffer, maxlen, "{gray}", "\x08");
        ReplaceString(buffer, maxlen, "{YELLOW}", "\x09");
        ReplaceString(buffer, maxlen, "{yellow}", "\x09");
        ReplaceString(buffer, maxlen, "{LIGHTBLUE}", "\x0A");
        ReplaceString(buffer, maxlen, "{lightblue}", "\x0A");
        ReplaceString(buffer, maxlen, "{BLUE}", "\x0B");
        ReplaceString(buffer, maxlen, "{blue}", "\x0B");
        ReplaceString(buffer, maxlen, "{PURPLE}", "\x0E");
        ReplaceString(buffer, maxlen, "{purple}", "\x0E");
        return;
    }

    // Compatibility mode: keep only \x01/\x03/\x04 for cross-game stability.
    ReplaceString(buffer, maxlen, "{RED}", "\x01");
    ReplaceString(buffer, maxlen, "{red}", "\x01");
    ReplaceString(buffer, maxlen, "{LIME}", "\x04");
    ReplaceString(buffer, maxlen, "{lime}", "\x04");
    ReplaceString(buffer, maxlen, "{LIGHTGREEN}", "\x04");
    ReplaceString(buffer, maxlen, "{lightgreen}", "\x04");
    ReplaceString(buffer, maxlen, "{LIGHTRED}", "\x01");
    ReplaceString(buffer, maxlen, "{lightred}", "\x01");
    ReplaceString(buffer, maxlen, "{GRAY}", "\x01");
    ReplaceString(buffer, maxlen, "{gray}", "\x01");
    ReplaceString(buffer, maxlen, "{YELLOW}", "\x04");
    ReplaceString(buffer, maxlen, "{yellow}", "\x04");
    ReplaceString(buffer, maxlen, "{LIGHTBLUE}", "\x04");
    ReplaceString(buffer, maxlen, "{lightblue}", "\x04");
    ReplaceString(buffer, maxlen, "{BLUE}", "\x04");
    ReplaceString(buffer, maxlen, "{blue}", "\x04");
    ReplaceString(buffer, maxlen, "{PURPLE}", "\x04");
    ReplaceString(buffer, maxlen, "{purple}", "\x04");

    // If values were saved with legacy extended bytes, normalize them too.
    ReplaceString(buffer, maxlen, "\x02", "\x01");
    ReplaceString(buffer, maxlen, "\x05", "\x04");
    ReplaceString(buffer, maxlen, "\x06", "\x04");
    ReplaceString(buffer, maxlen, "\x07", "\x01");
    ReplaceString(buffer, maxlen, "\x08", "\x01");
    ReplaceString(buffer, maxlen, "\x09", "\x04");
    ReplaceString(buffer, maxlen, "\x0A", "\x04");
    ReplaceString(buffer, maxlen, "\x0B", "\x04");
    ReplaceString(buffer, maxlen, "\x0E", "\x04");
}


void AddDownloadIfExists(const char[] filePath)
{
    if (filePath[0] != '\0' && FileExists(filePath, true))
    {
        AddFileToDownloadsTable(filePath);
    }
}

void RegisterModelDownloads(const char[] modelPath)
{
    if (modelPath[0] == '\0' || !FileExists(modelPath, true))
    {
        return;
    }

    AddFileToDownloadsTable(modelPath);

    int len = strlen(modelPath);
    if (len < 5)
    {
        return;
    }

    char base[PLATFORM_MAX_PATH];
    strcopy(base, sizeof(base), modelPath);
    base[len - 4] = '\0';

    char filePath[PLATFORM_MAX_PATH];

    Format(filePath, sizeof(filePath), "%s.vvd", base);
    AddDownloadIfExists(filePath);

    Format(filePath, sizeof(filePath), "%s.dx80.vtx", base);
    AddDownloadIfExists(filePath);

    Format(filePath, sizeof(filePath), "%s.dx90.vtx", base);
    AddDownloadIfExists(filePath);

    Format(filePath, sizeof(filePath), "%s.sw.vtx", base);
    AddDownloadIfExists(filePath);

    Format(filePath, sizeof(filePath), "%s.phy", base);
    AddDownloadIfExists(filePath);
}

int GetPreviewOwnerFromEntity(int entity)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (EntRefToEntIndex(g_iPreviewEntity[i]) == entity)
        {
            return i;
        }
    }

    return 0;
}

public Action Hook_PreviewSetTransmit(int entity, int client)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    int owner = GetPreviewOwnerFromEntity(entity);
    if (owner <= 0)
    {
        return Plugin_Handled;
    }

    return (client == owner) ? Plugin_Continue : Plugin_Handled;
}


void LoadItemsConfig()
{
    g_aItems.Clear();
    InvalidateItemCache();

    if (g_mItemIndex == null)
    {
        g_mItemIndex = new StringMap();
    }

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), STORE_ITEMS_CONFIG);

    if (!FileExists(path))
    {
        LogError("%s No se encontró el config de ítems: %s", STORE_LOG_PREFIX, path);
        return;
    }

    KeyValues kv = new KeyValues("Items");
    if (!kv.ImportFromFile(path))
    {
        LogError("%s No se pudo cargar el config: %s", STORE_LOG_PREFIX, path);
        delete kv;
        return;
    }

    if (kv.GotoFirstSubKey())
    {
        StoreItem item;
        do
        {
            item.id[0] = '\0';
            item.name[0] = '\0';
            item.type[0] = '\0';
            item.szModel[0] = '\0';
            item.szArms[0] = '\0';
            item.szValue[0] = '\0';
            item.flag[0] = '\0';
            item.price = 0;
            item.team = 0;

            kv.GetSectionName(item.id, sizeof(item.id));
            kv.GetString("name", item.name, sizeof(item.name), "Item");
            kv.GetString("type", item.type, sizeof(item.type), "skin");
            kv.GetString("model", item.szModel, sizeof(item.szModel), "");
            kv.GetString("arms", item.szArms, sizeof(item.szArms), "");
            kv.GetString("value", item.szValue, sizeof(item.szValue), "");
            kv.GetString("flag", item.flag, sizeof(item.flag), "");
            item.price = kv.GetNum("price", 0);
            item.team = kv.GetNum("team", 0);

            if (StrEqual(item.type, "skin"))
            {
                if (item.szModel[0] == '\0' || !FileExists(item.szModel, true))
                {
                    LogError("%s Skin inválida '%s': modelo faltante '%s'", STORE_LOG_PREFIX, item.id, item.szModel);
                    continue;
                }

                PrecacheModel(item.szModel, true);
                RegisterModelDownloads(item.szModel);

                if (item.szArms[0] != '\0')
                {
                    if (FileExists(item.szArms, true))
                    {
                        PrecacheModel(item.szArms, true);
                        RegisterModelDownloads(item.szArms);
                    }
                    else
                    {
                        LogError("%s Arms inválidos '%s': '%s'", STORE_LOG_PREFIX, item.id, item.szArms);
                        item.szArms[0] = '\0';
                    }
                }
            }

            int existingIndex;
            if (g_mItemIndex != null && g_mItemIndex.GetValue(item.id, existingIndex))
            {
                LogError("%s Item duplicado en config: %s", STORE_LOG_PREFIX, item.id);
                continue;
            }

            int pushedIndex = g_aItems.PushArray(item, sizeof(StoreItem));
            if (g_mItemIndex != null)
            {
                g_mItemIndex.SetValue(item.id, pushedIndex);
            }
        }
        while (kv.GotoNextKey());
    }

    delete kv;

    RebuildItemCache();
    LogMessage("%s Config cargado: %d ítems (cache: %d)", STORE_LOG_PREFIX, g_aItems.Length, g_aItems.Length);
}

public Action Cmd_ReloadStore(int client, int args)
{
    LoadItemsConfig();

    char msg[192];
    Format(msg, sizeof(msg), "%T", "Store Reloaded", client, g_aItems.Length);
    ReplaceColorTags(msg, sizeof(msg));
    ReplyToCommand(client, " %s", msg);

    return Plugin_Handled;
}

// =========================================================================
// BASE DE DATOS
// =========================================================================
void ConnectDatabase()
{
    char dbConfig[64];
    if (gCvarDatabase != null)
    {
        gCvarDatabase.GetString(dbConfig, sizeof(dbConfig));
    }
    else
    {
        strcopy(dbConfig, sizeof(dbConfig), STORE_DB_CONFIG);
    }

    if (dbConfig[0] == '\0')
    {
        strcopy(dbConfig, sizeof(dbConfig), STORE_DB_CONFIG);
    }

    if (SQL_CheckConfig(dbConfig))
    {
        Database.Connect(OnDatabaseConnected, dbConfig);
        return;
    }

    char failMsg[256];
    Format(failMsg, sizeof(failMsg), "%s Database config '%s' not found in databases.cfg. Set store_database to a valid entry.", STORE_LOG_PREFIX, dbConfig);
    LogError("%s", failMsg);
    SetFailState("%s", failMsg);
}

public void OnDatabaseConnected(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogStoreError("OnDatabaseConnected", error);
        char failMsg[256];
        char dbConfig[64];
        if (gCvarDatabase != null)
        {
            gCvarDatabase.GetString(dbConfig, sizeof(dbConfig));
        }
        else
        {
            strcopy(dbConfig, sizeof(dbConfig), STORE_DB_CONFIG);
        }
        if (dbConfig[0] == '\0')
        {
            strcopy(dbConfig, sizeof(dbConfig), STORE_DB_CONFIG);
        }

        if (error[0] == '\0')
        {
            Format(failMsg, sizeof(failMsg), "%s Unable to connect database '%s'.", STORE_LOG_PREFIX, dbConfig);
        }
        else
        {
            Format(failMsg, sizeof(failMsg), "%s Database '%s' connection failed: %s", STORE_LOG_PREFIX, dbConfig, error);
        }
        SetFailState("%s", failMsg);
        return;
    }

    g_DB = db;
    SetupDatabaseMode();
    CreateTables();
}

void SetupDatabaseMode()
{
    if (g_DB == null)
    {
        return;
    }

    char driver[16];
    g_DB.Driver.GetIdentifier(driver, sizeof(driver));
    g_bIsMySQL = StrEqual(driver, "mysql", false);
}

void CreateTables()
{
    if (g_DB == null)
    {
        return;
    }

    char query1[512];
    char query2[512];
    char query3[512];
    char query4[512];
    char query5[512];
    query3[0] = '\0';
    query5[0] = '\0';

    if (g_bIsMySQL)
    {
        Format(query1, sizeof(query1),
            "CREATE TABLE IF NOT EXISTS store_players (steamid VARCHAR(32) NOT NULL PRIMARY KEY, name VARCHAR(64) NOT NULL, credits INT NOT NULL DEFAULT 0)");
        Format(query2, sizeof(query2),
            "CREATE TABLE IF NOT EXISTS store_inventory (steamid VARCHAR(32) NOT NULL, item_id VARCHAR(32) NOT NULL, is_equipped INT NOT NULL DEFAULT 0, PRIMARY KEY (steamid, item_id))");
        Format(query4, sizeof(query4),
            "CREATE TABLE IF NOT EXISTS store_credits_ledger (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, steamid VARCHAR(32) NOT NULL, amount INT NOT NULL, reason VARCHAR(64) NOT NULL, balance_after INT NOT NULL, created_at INT NOT NULL, INDEX idx_store_credits_ledger_steamid (steamid), INDEX idx_store_credits_ledger_created (created_at))");
    }
    else
    {
        Format(query1, sizeof(query1),
            "CREATE TABLE IF NOT EXISTS store_players (steamid TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, credits INTEGER NOT NULL DEFAULT 0)");
        Format(query2, sizeof(query2),
            "CREATE TABLE IF NOT EXISTS store_inventory (steamid TEXT NOT NULL, item_id TEXT NOT NULL, is_equipped INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, item_id))");
        Format(query3, sizeof(query3),
            "CREATE INDEX IF NOT EXISTS idx_store_inventory_steamid ON store_inventory (steamid)");
        Format(query4, sizeof(query4),
            "CREATE TABLE IF NOT EXISTS store_credits_ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, steamid TEXT NOT NULL, amount INTEGER NOT NULL, reason TEXT NOT NULL, balance_after INTEGER NOT NULL, created_at INTEGER NOT NULL)");
        Format(query5, sizeof(query5),
            "CREATE INDEX IF NOT EXISTS idx_store_credits_ledger_steamid ON store_credits_ledger (steamid)");
    }

    g_iPendingTableQueries = 0;
    if (query1[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query2[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query3[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query4[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query5[0] != '\0')
    {
        g_iPendingTableQueries++;
    }

    g_DB.Query(OnTableCreated, query1);
    g_DB.Query(OnTableCreated, query2);
    g_DB.Query(OnTableCreated, query4);

    if (query3[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query3);
    }

    if (query5[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query5);
    }
}

public void OnTableCreated(Database db, DBResultSet results, const char[] error, any data)
{
    if (g_iPendingTableQueries > 0)
    {
        g_iPendingTableQueries--;
    }

    if (db == null)
    {
        LogStoreError("OnTableCreated", error);
    }
    else if (error[0] != '\0')
    {
        LogStoreError("CreateTables", error);
    }

    if (!g_bLateDatabaseReady && g_iPendingTableQueries == 0)
    {
        g_bLateDatabaseReady = true;
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidClientConnected(i) && !g_bIsLoaded[i] && !g_bIsLoading[i])
            {
                LoadPlayer(i);
            }
        }
    }
}

public void DummyCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || error[0] == '\0')
    {
        return;
    }

    LogStoreError("DummyCallback", error);
}

void LoadPlayer(int client)
{
    if (!IsValidClientConnected(client) || g_bIsLoading[client])
    {
        return;
    }

    g_bIsLoading[client] = true;
    g_iCredits[client] = 0;
    g_bIsLoaded[client] = false;

    if (g_hInventory[client] != null)
    {
        delete g_hInventory[client];
    }
    g_hInventory[client] = new ArrayList(sizeof(InventoryItem));

    if (g_mInventoryOwned[client] == null)
    {
        g_mInventoryOwned[client] = new StringMap();
    }
    else
    {
        g_mInventoryOwned[client].Clear();
    }

    if (g_DB == null)
    {
        g_bIsLoading[client] = false;
        return;
    }

    char steamid[32], safeSteamId[64];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        g_bIsLoading[client] = false;
        return;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));

    char query[256];
    Format(query, sizeof(query), "SELECT credits FROM store_players WHERE steamid = '%s'", safeSteamId);
    g_DB.Query(OnPlayerLoaded, query, GetClientUserId(client));
}

public void OnPlayerLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (!IsValidClientConnected(client))
    {
        return;
    }

    if (db == null || results == null)
    {
        g_bIsLoading[client] = false;
        LogStoreError("OnPlayerLoaded", error);
        return;
    }

    if (results.FetchRow())
    {
        g_iCredits[client] = results.FetchInt(0);
    }
    else
    {
        CreatePlayerRow(client);
    }

    char steamid[32], safeSteamId[64], queryInv[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        g_bIsLoading[client] = false;
        return;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    Format(queryInv, sizeof(queryInv), "SELECT item_id, is_equipped FROM store_inventory WHERE steamid = '%s'", safeSteamId);
    g_DB.Query(OnInventoryLoaded, queryInv, GetClientUserId(client));
}

void CreatePlayerRow(int client)
{
    if (g_DB == null || !IsValidClientConnected(client))
    {
        return;
    }

    char steamid[32], name[64], safeSteamId[64], safeName[128], query[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return;
    }

    GetClientName(client, name, sizeof(name));
    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(name, safeName, sizeof(safeName));

    int initialCredits = (gCvarInitialCredits != null) ? gCvarInitialCredits.IntValue : 0;
    g_iCredits[client] = initialCredits;
    g_bCreditsDirty[client] = false;

    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "INSERT IGNORE INTO store_players (steamid, name, credits) VALUES ('%s', '%s', %d)",
            safeSteamId, safeName, initialCredits);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT OR IGNORE INTO store_players (steamid, name, credits) VALUES ('%s', '%s', %d)",
            safeSteamId, safeName, initialCredits);
    }

    SQL_LockDatabase(g_DB);
    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("CreatePlayerRow", error);
    }
    SQL_UnlockDatabase(g_DB);
}

bool BuildPlayerUpsertQueryForCredits(int client, int creditsValue, char[] query, int maxlen)
{
    if (g_DB == null || !IsValidClientConnected(client))
    {
        return false;
    }

    char steamid[32], name[64], safeSteamId[64], safeName[128];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    GetClientName(client, name, sizeof(name));
    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(name, safeName, sizeof(safeName));

    if (g_bIsMySQL)
    {
        Format(query, maxlen,
            "INSERT INTO store_players (steamid, name, credits) VALUES ('%s', '%s', %d) ON DUPLICATE KEY UPDATE name = VALUES(name), credits = VALUES(credits)",
            safeSteamId, safeName, creditsValue);
    }
    else
    {
        Format(query, maxlen,
            "INSERT OR REPLACE INTO store_players (steamid, name, credits) VALUES ('%s', '%s', %d)",
            safeSteamId, safeName, creditsValue);
    }

    return true;
}

bool BeginLockedStoreTransaction(const char[] where)
{
    if (g_DB == null)
    {
        return false;
    }

    SQL_LockDatabase(g_DB);
    if (SQL_FastQuery(g_DB, "BEGIN"))
    {
        return true;
    }

    char error[256];
    SQL_GetError(g_DB, error, sizeof(error));
    LogStoreError(where, error);
    SQL_UnlockDatabase(g_DB);
    return false;
}

bool ExecuteLockedStoreQuery(const char[] where, const char[] query, int expectedAffected = -1)
{
    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError(where, error);
        LogError("%s %s query failed: %s", STORE_LOG_PREFIX, where, query);
        return false;
    }

    if (expectedAffected >= 0)
    {
        int affected = SQL_GetAffectedRows(g_DB);
        if (affected != expectedAffected)
        {
            LogError("%s %s unexpected affected rows (%d != %d). Query: %s", STORE_LOG_PREFIX, where, affected, expectedAffected, query);
            return false;
        }
    }

    return true;
}

void RollbackLockedStoreTransaction(const char[] where)
{
    if (g_DB != null && !SQL_FastQuery(g_DB, "ROLLBACK"))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError(where, error);
    }

    if (g_DB != null)
    {
        SQL_UnlockDatabase(g_DB);
    }
}

bool CommitLockedStoreTransaction(const char[] where)
{
    if (!SQL_FastQuery(g_DB, "COMMIT"))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError(where, error);
        RollbackLockedStoreTransaction(where);
        return false;
    }

    SQL_UnlockDatabase(g_DB);
    return true;
}

public void OnInventoryLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (!IsValidClientConnected(client))
    {
        return;
    }

    if (db == null || results == null)
    {
        g_bIsLoading[client] = false;
        LogStoreError("OnInventoryLoaded", error);
        return;
    }

    InventoryItem inv;
    while (results.FetchRow())
    {
        results.FetchString(0, inv.item_id, sizeof(inv.item_id));
        inv.is_equipped = results.FetchInt(1);
        g_hInventory[client].PushArray(inv, sizeof(InventoryItem));
        InventoryOwnedSet(client, inv.item_id, true);
    }

    g_bIsLoaded[client] = true;
    g_bIsLoading[client] = false;
    MarkInventoryChanged(client);
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];
}

bool SavePlayer(int client)
{
    if (!IsValidClientConnected(client) || g_DB == null)
    {
        return false;
    }

    char query[512];
    int creditsSnapshot = g_iCredits[client];
    if (!BuildPlayerUpsertQueryForCredits(client, creditsSnapshot, query, sizeof(query)))
    {
        return false;
    }

    SQL_LockDatabase(g_DB);
    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("SavePlayerSync", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }
    SQL_UnlockDatabase(g_DB);

    if (g_iCredits[client] == creditsSnapshot)
    {
        g_bCreditsDirty[client] = false;
    }

    return true;
}

public void OnPlayerSaved(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int serial = pack.ReadCell();
    int token = pack.ReadCell();
    int creditsSnapshot = pack.ReadCell();
    delete pack;

    int client = GetClientFromSerial(serial);
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    if (db == null || error[0] != '\0')
    {
        LogStoreError("OnPlayerSaved", error);
        return;
    }

    if (token != g_iCreditSaveInFlight[client])
    {
        return;
    }

    if (g_iCredits[client] == creditsSnapshot)
    {
        g_bCreditsDirty[client] = false;
    }
}

void SaveInventoryEquipState(int client, const char[] itemId, int equipped)
{
    if (g_DB == null)
    {
        return;
    }

    char steamid[32], safeSteamId[64], safeItemId[64], query[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));

    Format(query, sizeof(query),
        "UPDATE store_inventory SET is_equipped = %d WHERE steamid = '%s' AND item_id = '%s'",
        equipped, safeSteamId, safeItemId);

    SQL_LockDatabase(g_DB);
    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("SaveInventoryEquipState", error);
    }
    SQL_UnlockDatabase(g_DB);
}

// =========================================================================
// CHAT
// =========================================================================
public Action Command_Say(int client, const char[] command, int argc)
{
    return ProcessChat(client, false);
}

public Action Command_SayTeam(int client, const char[] command, int argc)
{
    return ProcessChat(client, true);
}

Action ProcessChat(int client, bool isTeamChat)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null || !IsStoreEnabled())
    {
        return Plugin_Continue;
    }

    MarkClientActive(client);

    char text[192];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);

    if (text[0] == '\0' || text[0] == '/')
    {
        return Plugin_Continue;
    }

    char tag[64] = "";
    char nameColor[32] = "\x03";
    char chatColor[32] = "\x01";
    bool hasCustomChat = false;

    InventoryItem inv;
    StoreItem item;

    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (!inv.is_equipped)
        {
            continue;
        }

        if (!FindStoreItemById(inv.item_id, item))
        {
            continue;
        }

        if (StrEqual(item.type, "tag"))
        {
            char tagValue[64];
            strcopy(tagValue, sizeof(tagValue), item.szValue);
            ReplaceColorTags(tagValue, sizeof(tagValue));
            Format(tag, sizeof(tag), " %s", tagValue);
            hasCustomChat = true;
        }
        else if (StrEqual(item.type, "namecolor"))
        {
            strcopy(nameColor, sizeof(nameColor), item.szValue);
            ReplaceColorTags(nameColor, sizeof(nameColor));
            hasCustomChat = true;
        }
        else if (StrEqual(item.type, "chatcolor"))
        {
            strcopy(chatColor, sizeof(chatColor), item.szValue);
            ReplaceColorTags(chatColor, sizeof(chatColor));
            hasCustomChat = true;
        }
    }

    if (!hasCustomChat)
    {
        return Plugin_Continue;
    }

    char clientName[64], finalMsg[256], prefix[64] = "";
    GetClientName(client, clientName, sizeof(clientName));

    if (!IsPlayerAlive(client))
    {
        StrCat(prefix, sizeof(prefix), " \x01*MUERTO*");
    }

    if (isTeamChat)
    {
        char teamName[64];
        char teamPrefix[80];
        GetReadableTeamName(client, teamName, sizeof(teamName));
        Format(teamPrefix, sizeof(teamPrefix), " \x01(%s)", teamName);
        StrCat(prefix, sizeof(prefix), teamPrefix);
    }

    Format(finalMsg, sizeof(finalMsg), "%s%s %s%s\x01 : %s%s", prefix, tag, nameColor, clientName, chatColor, text);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanClient(i))
        {
            continue;
        }

        if (isTeamChat && GetClientTeam(i) != GetClientTeam(client))
        {
            continue;
        }

        PrintToChat(i, "%s", finalMsg);
    }

    return Plugin_Handled;
}

// =========================================================================
// EQUIPAMIENTO / SKINS
// =========================================================================
bool ShouldUnequipSameCategory(StoreItem targetItem, StoreItem otherItem)
{
    if (StrEqual(targetItem.type, "skin") && StrEqual(otherItem.type, "skin") && targetItem.team == otherItem.team)
    {
        return true;
    }

    if (StrEqual(targetItem.type, "tag") && StrEqual(otherItem.type, "tag"))
    {
        return true;
    }

    if (StrEqual(targetItem.type, "namecolor") && StrEqual(otherItem.type, "namecolor"))
    {
        return true;
    }

    if (StrEqual(targetItem.type, "chatcolor") && StrEqual(otherItem.type, "chatcolor"))
    {
        return true;
    }

    return false;
}

void ResetPlayerModelToDefault(int client)
{
    if (!IsValidHumanClient(client) || !IsPlayerAlive(client))
    {
        return;
    }

    if (GetFeatureStatus(FeatureType_Native, "CS_UpdateClientModel") == FeatureStatus_Available)
    {
        CS_UpdateClientModel(client);
    }
    else if (g_szDefaultPlayerModel[client][0] != '\0')
    {
        SetEntityModel(client, g_szDefaultPlayerModel[client]);
    }

    SetEntPropString(client, Prop_Send, "m_szArmsModel", "");
}

void CaptureClientDefaultModel(int client)
{
    if (!IsValidHumanClient(client))
    {
        return;
    }

    char modelPath[PLATFORM_MAX_PATH];
    GetClientModel(client, modelPath, sizeof(modelPath));
    if (modelPath[0] != '\0')
    {
        strcopy(g_szDefaultPlayerModel[client], sizeof(g_szDefaultPlayerModel[]), modelPath);
    }
}

void GetReadableTeamName(int client, char[] buffer, int maxlen)
{
    int team = GetClientTeam(client);
    buffer[0] = '\0';

    if (team > 0)
    {
        GetTeamName(team, buffer, maxlen);
    }

    if (buffer[0] == '\0')
    {
        if (team <= 1)
        {
            strcopy(buffer, maxlen, "Spectator");
        }
        else
        {
            Format(buffer, maxlen, "Team %d", team);
        }
    }
}


bool ArePlayerSkinsEnabled()
{
    return (gCvarEnablePlayerSkins == null || gCvarEnablePlayerSkins.BoolValue);
}

public void OnPlayerSkinsToggleChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    bool enabled = StringToInt(newValue) != 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanClient(i) || !IsPlayerAlive(i))
        {
            continue;
        }

        if (enabled)
        {
            ApplyPlayerSkin(i);
        }
        else
        {
            ResetPlayerModelToDefault(i);
        }
    }
}

void ApplyPlayerSkin(int client)
{
    if (!IsValidHumanClient(client) || !IsPlayerAlive(client) || g_hInventory[client] == null)
    {
        return;
    }

    ResetPlayerModelToDefault(client);

    if (!ArePlayerSkinsEnabled())
    {
        return;
    }

    int team = GetClientTeam(client);
    InventoryItem inv;
    StoreItem item;

    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (!inv.is_equipped)
        {
            continue;
        }

        if (!FindStoreItemById(inv.item_id, item))
        {
            continue;
        }

        if (!StrEqual(item.type, "skin") || item.team != team)
        {
            continue;
        }

        if (item.szModel[0] == '\0' || !FileExists(item.szModel, true))
        {
            LogError("%s Skin equipada inválida para %N: %s", STORE_LOG_PREFIX, client, item.id);
            return;
        }

        PrecacheModel(item.szModel, true);
        SetEntityModel(client, item.szModel);

        if (item.szArms[0] != '\0' && FileExists(item.szArms, true))
        {
            PrecacheModel(item.szArms, true);
            SetEntPropString(client, Prop_Send, "m_szArmsModel", item.szArms);
        }

        return;
    }
}


bool CanUseEquipAction(int client)
{
    float cooldown = (gCvarEquipCooldown != null) ? gCvarEquipCooldown.FloatValue : 0.0;
    if (cooldown <= 0.0)
    {
        return true;
    }

    float now = GetGameTime();
    if (now < g_fNextEquipTime[client])
    {
        char cooldownText[16];
        FormatCooldownText(g_fNextEquipTime[client] - now, cooldownText, sizeof(cooldownText));
        PrintStorePhrase(client, "%T", "Equip Cooldown", client, cooldownText);
        return false;
    }

    g_fNextEquipTime[client] = now + cooldown;
    return true;
}

void ToggleEquip(int client, const char[] itemId)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        return;
    }

    if (!CanUseEquipAction(client))
    {
        return;
    }

    StoreItem targetItem;
    if (!FindStoreItemById(itemId, targetItem))
    {
        PrintStorePhrase(client, "%T", "Item Not Found", client);
        return;
    }

    int targetIndex = FindInventoryIndexByItemId(client, itemId);
    if (targetIndex == -1)
    {
        PrintStorePhrase(client, "%T", "Item Not In Inventory", client);
        return;
    }

    if (!CanPlayerUseItem(client, targetItem, true))
    {
        return;
    }

    InventoryItem targetInv;
    g_hInventory[client].GetArray(targetIndex, targetInv, sizeof(InventoryItem));

    bool equipNow = !view_as<bool>(targetInv.is_equipped);

    if (equipNow && StrEqual(targetItem.type, "skin") && !ArePlayerSkinsEnabled())
    {
        PrintStorePhrase(client, "%T", "Player Skins Disabled", client);
        return;
    }

    if (equipNow)
    {
        InventoryItem inv;
        StoreItem otherItem;

        for (int i = 0; i < g_hInventory[client].Length; i++)
        {
            if (i == targetIndex)
            {
                continue;
            }

            g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
            if (!inv.is_equipped)
            {
                continue;
            }

            if (!FindStoreItemById(inv.item_id, otherItem))
            {
                continue;
            }

            if (ShouldUnequipSameCategory(targetItem, otherItem))
            {
                inv.is_equipped = 0;
                g_hInventory[client].SetArray(i, inv, sizeof(InventoryItem));
                SaveInventoryEquipState(client, inv.item_id, 0);
            }
        }

        targetInv.is_equipped = 1;
        g_hInventory[client].SetArray(targetIndex, targetInv, sizeof(InventoryItem));
        SaveInventoryEquipState(client, itemId, 1);
        PrintStorePhrase(client, "%T", "Item Equipped", client);
        ForwardItemEquipped(client, itemId, true);
    }
    else
    {
        targetInv.is_equipped = 0;
        g_hInventory[client].SetArray(targetIndex, targetInv, sizeof(InventoryItem));
        SaveInventoryEquipState(client, itemId, 0);
        PrintStorePhrase(client, "%T", "Item Unequipped", client);
        ForwardItemEquipped(client, itemId, false);
    }

    MarkInventoryChanged(client);

    if (StrEqual(targetItem.type, "skin"))
    {
        ApplyPlayerSkin(client);
    }
}

bool BuyItem(int client, const char[] itemId)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null || g_DB == null)
    {
        return false;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        PrintStorePhrase(client, "%T", "Item No Longer Exists", client);
        return false;
    }

    if (item.price < 0)
    {
        LogError("%s BuyItem: invalid negative price for item '%s' (%d)", STORE_LOG_PREFIX, item.id, item.price);
        PrintStorePhrase(client, "%T", "Item No Longer Exists", client);
        return false;
    }

    if (!HasAccess(client, item.flag))
    {
        PrintStorePhrase(client, "%T", "No Access Item", client);
        return false;
    }

    if (PlayerOwnsItem(client, item.id))
    {
        PrintStorePhrase(client, "%T", "Already Owns Item", client);
        return false;
    }

    if (g_iCredits[client] < item.price)
    {
        PrintStorePhrase(client, "%T", "Not Enough Credits", client);
        return false;
    }

    char steamid[32], safeSteamId[64], safeItemId[64], query[256], playerQuery[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(item.id, safeItemId, sizeof(safeItemId));
    int newCredits = g_iCredits[client] - item.price;

    if (!BuildPlayerUpsertQueryForCredits(client, newCredits, playerQuery, sizeof(playerQuery)))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "INSERT INTO store_inventory (steamid, item_id, is_equipped) VALUES ('%s', '%s', 0)",
            safeSteamId, safeItemId);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO store_inventory (steamid, item_id, is_equipped) VALUES ('%s', '%s', 0)",
            safeSteamId, safeItemId);
    }

    if (!BeginLockedStoreTransaction("BuyItem"))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!ExecuteLockedStoreQuery("BuyItem", playerQuery))
    {
        RollbackLockedStoreTransaction("BuyItem");
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!ExecuteLockedStoreQuery("BuyItem", query, 1))
    {
        RollbackLockedStoreTransaction("BuyItem");
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!CommitLockedStoreTransaction("BuyItem"))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    g_iCredits[client] = newCredits;
    g_bCreditsDirty[client] = false;
    char buyReason[64];
    Format(buyReason, sizeof(buyReason), "buy:%s", item.id);
    LogCreditLedger(client, -item.price, buyReason);

    InventoryItem newInv;
    strcopy(newInv.item_id, sizeof(newInv.item_id), item.id);
    newInv.is_equipped = 0;
    g_hInventory[client].PushArray(newInv, sizeof(InventoryItem));
    InventoryOwnedSet(client, item.id, true);
    MarkInventoryChanged(client);

    char priceText[32], balanceText[32];
    FormatNumberDots(item.price, priceText, sizeof(priceText));
    FormatNumberDots(g_iCredits[client], balanceText, sizeof(balanceText));

    PrintStorePhrase(client, "%T", "Item Bought", client, item.name, priceText);
    PrintStorePhrase(client, "%T", "Balance Current", client, balanceText);
    ForwardItemPurchased(client, item.id);
    return true;
}

bool SellItem(int client, const char[] itemId)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null || g_DB == null)
    {
        return false;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        PrintStorePhrase(client, "%T", "Item Missing Config", client);
        return false;
    }

    int index = FindInventoryIndexByItemId(client, item.id);
    if (index == -1)
    {
        PrintStorePhrase(client, "%T", "Item Not Owned", client);
        return false;
    }

    InventoryItem inv;
    g_hInventory[client].GetArray(index, inv, sizeof(InventoryItem));
    bool wasEquipped = view_as<bool>(inv.is_equipped);

    char steamid[32], safeSteamId[64], safeItemId[64], query[256], playerQuery[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(item.id, safeItemId, sizeof(safeItemId));
    int refund = GetSellPrice(item.price);
    int newCredits = g_iCredits[client] + refund;
    if (!BuildPlayerUpsertQueryForCredits(client, newCredits, playerQuery, sizeof(playerQuery)))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    Format(query, sizeof(query), "DELETE FROM store_inventory WHERE steamid = '%s' AND item_id = '%s'", safeSteamId, safeItemId);
    if (!BeginLockedStoreTransaction("SellItem"))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!ExecuteLockedStoreQuery("SellItem", query, 1))
    {
        RollbackLockedStoreTransaction("SellItem");
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!ExecuteLockedStoreQuery("SellItem", playerQuery))
    {
        RollbackLockedStoreTransaction("SellItem");
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    if (!CommitLockedStoreTransaction("SellItem"))
    {
        PrintStorePhrase(client, "%T", "Store Transaction Failed", client);
        return false;
    }

    g_hInventory[client].Erase(index);
    InventoryOwnedSet(client, item.id, false);
    MarkInventoryChanged(client);
    g_iCredits[client] = newCredits;
    g_bCreditsDirty[client] = false;
    char sellReason[64];
    Format(sellReason, sizeof(sellReason), "sell:%s", item.id);
    LogCreditLedger(client, refund, sellReason);

    if (wasEquipped && StrEqual(item.type, "skin"))
    {
        ApplyPlayerSkin(client);
    }

    char refundText[32], balanceText[32];
    FormatNumberDots(refund, refundText, sizeof(refundText));
    FormatNumberDots(g_iCredits[client], balanceText, sizeof(balanceText));

    PrintStorePhrase(client, "%T", "Item Sold", client, item.name, refundText);
    PrintStorePhrase(client, "%T", "Balance Current", client, balanceText);
    return true;
}


// =========================================================================
// MENÚ PRINCIPAL Y TIENDA
// =========================================================================
public Action Cmd_Store(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    Menu menu = new Menu(MenuHandler_Main);
    char title[192];
    char creditsText[32];
    char skinsLabel[64], chatLabel[64], topLabel[64], inventoryLabel[64], casinoLabel[64];

    FormatNumberDots(g_iCredits[client], creditsText, sizeof(creditsText));
    Format(title, sizeof(title), "%T", "Store Main Menu Title", client, creditsText);
    menu.SetTitle(title);

    Format(skinsLabel, sizeof(skinsLabel), "%T", "Store Category Skins", client);
    Format(chatLabel, sizeof(chatLabel), "%T", "Store Category Chat", client);
    Format(topLabel, sizeof(topLabel), "%T", "Store Category Top Credits", client);
    Format(inventoryLabel, sizeof(inventoryLabel), "%T", "Store Category Inventory", client);
    Format(casinoLabel, sizeof(casinoLabel), "%T", "Store Category Casino", client);

    menu.AddItem("skins", skinsLabel);
    menu.AddItem("chat", chatLabel);
    menu.AddItem("topcredits", topLabel);
    menu.AddItem("inventory", inventoryLabel);
    menu.AddItem("casino", casinoLabel);
    menu.Display(client, MENU_TIME_FOREVER);
    return Plugin_Handled;
}

public Action Cmd_Inv(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    ShowInventoryCategoryMenu(client);
    return Plugin_Handled;
}

public int MenuHandler_Main(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "skins"))
        {
            ShowTeamsMenu(param1);
        }
        else if (StrEqual(info, "chat"))
        {
            ShowChatMenu(param1);
        }
        else if (StrEqual(info, "topcredits"))
        {
            Cmd_TopCredits(param1, 0);
        }
        else if (StrEqual(info, "inventory"))
        {
            ShowInventoryCategoryMenu(param1);
        }
        else if (StrEqual(info, "casino"))
        {
            ShowCasinoMenu(param1);
        }
    }

    return 0;
}

void ShowTeamsMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Teams);
    char title[192];
    char labelTT[96];
    char labelCT[96];
    Format(title, sizeof(title), "%T", "Teams Menu Title", client);
    Format(labelTT, sizeof(labelTT), "%T", "Teams Menu TT", client);
    Format(labelCT, sizeof(labelCT), "%T", "Teams Menu CT", client);
    menu.SetTitle(title);
    menu.AddItem("2", labelTT);
    menu.AddItem("3", labelCT);
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Teams(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        Cmd_Store(param1, 0);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        ShowItemsListMenu(param1, "skin", StringToInt(info));
    }

    return 0;
}

void ShowChatMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Chat);
    SetMenuTitlePhrase(menu, client, "Chat Menu Title");
    AddMenuItemPhrase(menu, "tag", client, "Chat Menu Tags");
    AddMenuItemPhrase(menu, "namecolor", client, "Chat Menu Name Colors");
    AddMenuItemPhrase(menu, "chatcolor", client, "Chat Menu Chat Colors");
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Chat(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        Cmd_Store(param1, 0);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        ShowItemsListMenu(param1, info, 0);
    }

    return 0;
}

void ShowItemsListMenu(int client, const char[] targetType, int targetTeam)
{
    strcopy(g_szBrowseType[client], 16, targetType);
    g_iBrowseTeam[client] = targetTeam;

    Menu menu = new Menu(MenuHandler_ItemsList);
    char title[192];
    char creditsText[32];
    FormatNumberDots(g_iCredits[client], creditsText, sizeof(creditsText));
    Format(title, sizeof(title), "%T", "Items List Menu Title", client, creditsText);
    menu.SetTitle(title);

    int itemsAdded = 0;
    StoreItem item;

    for (int i = 0; i < g_aItems.Length; i++)
    {
        g_aItems.GetArray(i, item, sizeof(StoreItem));

        if (!StrEqual(item.type, targetType) || (targetTeam != 0 && item.team != targetTeam))
        {
            continue;
        }

        char display[128];
        bool owns = PlayerOwnsItem(client, item.id);

        if (!HasAccess(client, item.flag))
        {
            char vipSuffix[48];
            Format(vipSuffix, sizeof(vipSuffix), "%T", "Items List VIP Suffix", client);
            Format(display, sizeof(display), "%s %s", item.name, vipSuffix);
            menu.AddItem(item.id, display, ITEMDRAW_DISABLED);
        }
        else if (owns)
        {
            char invSuffix[64];
            Format(invSuffix, sizeof(invSuffix), "%T", "Items List Inventory Suffix", client);
            Format(display, sizeof(display), "%s %s", item.name, invSuffix);
            menu.AddItem(item.id, display, ITEMDRAW_DEFAULT);
        }
        else
        {
            char priceText[48];
            FormatCreditsAmount(client, item.price, priceText, sizeof(priceText));
            Format(display, sizeof(display), "%s [%s]", item.name, priceText);
            menu.AddItem(item.id, display, ITEMDRAW_DEFAULT);
        }

        itemsAdded++;
    }

    if (itemsAdded == 0)
    {
        char emptyLabel[96];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "Items List Empty", client);
        menu.AddItem("none", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ItemsList(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        if (StrEqual(g_szBrowseType[param1], "skin"))
        {
            ShowTeamsMenu(param1);
        }
        else
        {
            ShowChatMenu(param1);
        }
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        g_bDetailFromInventory[param1] = false;
        ShowItemDetailsMenu(param1, info);
    }

    return 0;
}

void ShowSellConfirmMenu(int client, const char[] itemId)
{
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        PrintStorePhrase(client, "%T", "Item Not Found", client);
        if (g_bDetailFromInventory[client])
        {
            ShowInventoryListMenu(client, g_szInvFilter[client]);
        }
        else
        {
            ShowItemsListMenu(client, g_szBrowseType[client], g_iBrowseTeam[client]);
        }
        return;
    }

    strcopy(g_szLastDetailItem[client], sizeof(g_szLastDetailItem[]), item.id);

    Menu menu = new Menu(MenuHandler_SellConfirm);

    char title[192];
    char refundText[48];
    char receiveLabel[64];
    char yesLabel[64];
    char noLabel[64];
    FormatCreditsAmount(client, GetSellPrice(item.price), refundText, sizeof(refundText));
    Format(receiveLabel, sizeof(receiveLabel), "%T", "Sell Receive Label", client);
    Format(title, sizeof(title), "%T", "Sell Confirm Title Menu", client, receiveLabel, refundText);
    menu.SetTitle(title);

    char yesInfo[64], noInfo[64];
    Format(yesInfo, sizeof(yesInfo), "yes_%s", item.id);
    Format(noInfo, sizeof(noInfo), "no_%s", item.id);
    Format(yesLabel, sizeof(yesLabel), "%T", "Sell Confirm Yes", client);
    Format(noLabel, sizeof(noLabel), "%T", "Sell Confirm No", client);

    menu.AddItem(yesInfo, yesLabel);
    menu.AddItem(noInfo, noLabel);
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_SellConfirm(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        if (g_szLastDetailItem[param1][0] != '\0')
        {
            ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
        }
        else
        {
            ShowItemsListMenu(param1, g_szBrowseType[param1], g_iBrowseTeam[param1]);
        }
    }
    else if (action == MenuAction_Select)
    {
        char info[64], itemId[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrContains(info, "yes_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[4]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, true))
            {
                SellItem(param1, itemId);
            }
            if (g_bDetailFromInventory[param1])
            {
                ShowInventoryListMenu(param1, g_szInvFilter[param1]);
            }
            else
            {
                ShowItemsListMenu(param1, g_szBrowseType[param1], g_iBrowseTeam[param1]);
            }
        }
        else if (StrContains(info, "no_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[3]);
            ShowItemDetailsMenu(param1, itemId);
        }
    }

    return 0;
}

void ShowItemDetailsMenu(int client, const char[] itemId)
{
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        return;
    }

    strcopy(g_szLastDetailItem[client], sizeof(g_szLastDetailItem[]), item.id);

    bool owns = false;
    bool isEquipped = false;
    int invIndex = FindInventoryIndexByItemId(client, itemId);
    if (invIndex != -1)
    {
        owns = true;
        InventoryItem inv;
        g_hInventory[client].GetArray(invIndex, inv, sizeof(InventoryItem));
        isEquipped = view_as<bool>(inv.is_equipped);
    }

    Menu menu = new Menu(MenuHandler_ItemDetails);
    char title[192];

    if (owns)
    {
        char stateText[64];
        Format(stateText, sizeof(stateText), "%T", isEquipped ? "Item State Equipped" : "Item State Inventory", client);
        Format(title, sizeof(title), "%T", "Item Details Owned Title", client, item.name, stateText);
    }
    else
    {
        char priceText[48];
        FormatCreditsAmount(client, item.price, priceText, sizeof(priceText));
        Format(title, sizeof(title), "%T", "Item Details Buy Title", client, item.name, priceText);
    }

    menu.SetTitle(title);

    if (!owns)
    {
        char buyInfo[64];
        char buyLabel[64];
        Format(buyInfo, sizeof(buyInfo), "buy_%s", item.id);
        FormatStorePhrase(client, buyLabel, sizeof(buyLabel), "Item Details Buy");
        menu.AddItem(buyInfo, buyLabel);
    }
    else
    {
        char eqInfo[64];
        char equipLabel[64];
        Format(eqInfo, sizeof(eqInfo), "eq_%s", item.id);
        FormatStorePhrase(client, equipLabel, sizeof(equipLabel), isEquipped ? "Item Details Unequip" : "Item Details Equip");
        menu.AddItem(eqInfo, equipLabel);

        char sellInfo[64], sellText[96];
        Format(sellInfo, sizeof(sellInfo), "sell_%s", item.id);
        char refundText[48];
        FormatCreditsAmount(client, GetSellPrice(item.price), refundText, sizeof(refundText));
        Format(sellText, sizeof(sellText), "%T", "Item Details Sell", client, refundText);
        menu.AddItem(sellInfo, sellText);

        char giftInfo[64], tradeInfo[64];
        char giftLabel[64], tradeLabel[64];
        Format(giftInfo, sizeof(giftInfo), "gift_%s", item.id);
        Format(tradeInfo, sizeof(tradeInfo), "trade_%s", item.id);
        FormatStorePhrase(client, giftLabel, sizeof(giftLabel), "Item Details Gift");
        FormatStorePhrase(client, tradeLabel, sizeof(tradeLabel), "Item Details Trade");
        menu.AddItem(giftInfo, giftLabel);
        menu.AddItem(tradeInfo, tradeLabel);
    }

    if (StrEqual(item.type, "skin"))
    {
        char previewInfo[64];
        char previewLabel[64];
        Format(previewInfo, sizeof(previewInfo), "prev_%s", item.id);
        FormatStorePhrase(client, previewLabel, sizeof(previewLabel), "Item Details Preview");
        menu.AddItem(previewInfo, previewLabel);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ItemDetails(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        if (g_bDetailFromInventory[param1])
        {
            ShowInventoryListMenu(param1, g_szInvFilter[param1]);
        }
        else
        {
            ShowItemsListMenu(param1, g_szBrowseType[param1], g_iBrowseTeam[param1]);
        }
    }
    else if (action == MenuAction_Select)
    {
        char info[64], itemId[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrContains(info, "buy_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[4]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, false))
            {
                BuyItem(param1, itemId);
            }
            ShowItemDetailsMenu(param1, itemId);
        }
        else if (StrContains(info, "eq_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[3]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, true))
            {
                ToggleEquip(param1, itemId);
            }
            ShowItemDetailsMenu(param1, itemId);
        }
        else if (StrContains(info, "sell_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[5]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, true))
            {
                ShowSellConfirmMenu(param1, itemId);
            }
            else
            {
                ShowItemDetailsMenu(param1, itemId);
            }
        }
        else if (StrContains(info, "gift_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[5]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, true))
            {
                ShowGiftTargetMenu(param1, itemId);
            }
            else
            {
                ShowItemDetailsMenu(param1, itemId);
            }
        }
        else if (StrContains(info, "trade_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[6]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, true))
            {
                ShowTradeTargetMenu(param1, itemId);
            }
            else
            {
                ShowItemDetailsMenu(param1, itemId);
            }
        }
        else if (StrContains(info, "prev_") == 0)
        {
            strcopy(itemId, sizeof(itemId), info[5]);
            if (ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], itemId, false))
            {
                StoreItem item;
                if (FindStoreItemById(itemId, item))
                {
                    SpawnPreview(param1, item.szModel);
                }
            }
            ShowItemDetailsMenu(param1, itemId);
        }
    }

    return 0;
}



void ShowGiftTargetMenu(int client, const char[] itemId)
{
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];

    if (!PlayerOwnsItem(client, itemId))
    {
        ShowItemDetailsMenu(client, itemId);
        return;
    }

    strcopy(g_szLastDetailItem[client], sizeof(g_szLastDetailItem[]), itemId);
    strcopy(g_szTradeGiftItem[client], sizeof(g_szTradeGiftItem[]), itemId);

    StoreItem item;
    FindStoreItemById(itemId, item);

    Menu menu = new Menu(MenuHandler_GiftTarget);
    char title[192];
    Format(title, sizeof(title), "%T", "Gift Target Menu Title", client, item.name);
    menu.SetTitle(title);

    int added = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanClient(i) || i == client || !g_bIsLoaded[i])
        {
            continue;
        }

        if (!CanTransferItemToTarget(client, i, itemId, false))
        {
            continue;
        }

        char info[64], name[64];
        Format(info, sizeof(info), "%s|%d", itemId, GetClientUserId(i));
        GetClientName(i, name, sizeof(name));
        menu.AddItem(info, name);
        added++;
    }

    if (added == 0)
    {
        AddMenuItemPhrase(menu, "none", client, "Gift Target Menu Empty", ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_GiftTarget(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
    }
    else if (action == MenuAction_Select)
    {
        char info[64], parts[2][32];
        menu.GetItem(param2, info, sizeof(info));
        if (StrEqual(info, "none"))
        {
            return 0;
        }

        ExplodeString(info, "|", parts, 2, 32);
        if (!ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], parts[0], true))
        {
            ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
            return 0;
        }
        ShowGiftConfirmMenu(param1, parts[0], StringToInt(parts[1]));
    }

    return 0;
}

void ShowGiftConfirmMenu(int client, const char[] itemId, int targetUserId)
{
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];

    int target = GetClientOfUserId(targetUserId);
    if (!CanTransferItemToTarget(client, target, itemId, true))
    {
        ShowGiftTargetMenu(client, itemId);
        return;
    }

    StoreItem item;
    FindStoreItemById(itemId, item);

    Menu menu = new Menu(MenuHandler_GiftConfirm);
    char title[256];
    Format(title, sizeof(title), "%T", "Gift Confirm Menu Title", client, item.name, target);
    menu.SetTitle(title);

    char yesInfo[64], noInfo[64], yesLabel[64], noLabel[64];
    Format(yesInfo, sizeof(yesInfo), "%s|%d", itemId, targetUserId);
    strcopy(noInfo, sizeof(noInfo), itemId);
    Format(yesLabel, sizeof(yesLabel), "%T", "Gift Confirm Yes", client);
    Format(noLabel, sizeof(noLabel), "%T", "Gift Confirm No", client);

    menu.AddItem(yesInfo, yesLabel);
    menu.AddItem(noInfo, noLabel);
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_GiftConfirm(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowGiftTargetMenu(param1, g_szTradeGiftItem[param1]);
    }
    else if (action == MenuAction_Select)
    {
        if (param2 == 0)
        {
            char info[64], parts[2][32];
            menu.GetItem(param2, info, sizeof(info));
            ExplodeString(info, "|", parts, 2, 32);

            int target = GetClientOfUserId(StringToInt(parts[1]));
            if (!ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], parts[0], true))
            {
                ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
                return 0;
            }

            if (TransferOwnedItem(param1, target, parts[0], true))
            {
                StoreItem item;
                FindStoreItemById(parts[0], item);
                PrintStorePhrase(param1, "%T", "Gift Sent", param1, item.name, target);
                PrintStorePhrase(target, "%T", "Gift Received", target, param1, item.name);
            }

            ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
        }
        else
        {
            ShowGiftTargetMenu(param1, g_szTradeGiftItem[param1]);
        }
    }

    return 0;
}

void ShowTradeTargetMenu(int client, const char[] itemId)
{
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];

    if (!PlayerOwnsItem(client, itemId))
    {
        ShowItemDetailsMenu(client, itemId);
        return;
    }

    strcopy(g_szLastDetailItem[client], sizeof(g_szLastDetailItem[]), itemId);
    strcopy(g_szTradeSenderItem[client], sizeof(g_szTradeSenderItem[]), itemId);

    StoreItem item;
    FindStoreItemById(itemId, item);

    Menu menu = new Menu(MenuHandler_TradeTarget);
    char title[192];
    Format(title, sizeof(title), "%T", "Trade Target Menu Title", client, item.name);
    menu.SetTitle(title);

    int added = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanClient(i) || i == client || !g_bIsLoaded[i] || g_hInventory[i] == null || g_hInventory[i].Length == 0)
        {
            continue;
        }

        char info[32], name[64];
        IntToString(GetClientUserId(i), info, sizeof(info));
        GetClientName(i, name, sizeof(name));
        menu.AddItem(info, name);
        added++;
    }

    if (added == 0)
    {
        char emptyLabel[96];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "Trade Target Menu Empty", client);
        menu.AddItem("none", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_TradeTarget(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        if (StrEqual(info, "none"))
        {
            return 0;
        }

        if (!ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], g_szTradeSenderItem[param1], true))
        {
            ShowItemDetailsMenu(param1, g_szLastDetailItem[param1]);
            return 0;
        }

        ShowTradeTargetItemsMenu(param1, g_szTradeSenderItem[param1], StringToInt(info));
    }

    return 0;
}

void ShowTradeTargetItemsMenu(int client, const char[] senderItemId, int targetUserId)
{
    g_iMenuInventoryVersion[client] = g_iInventoryVersion[client];

    int target = GetClientOfUserId(targetUserId);
    if (!IsValidHumanClient(target) || !g_bIsLoaded[target] || g_hInventory[target] == null)
    {
        ShowTradeTargetMenu(client, senderItemId);
        return;
    }

    g_iTradeTargetInvVersion[client] = g_iInventoryVersion[target];

    Menu menu = new Menu(MenuHandler_TradeTargetItem);
    StoreItem senderItem;
    FindStoreItemById(senderItemId, senderItem);

    char title[192];
    Format(title, sizeof(title), "%T", "Trade Target Items Menu Title", client, target, senderItem.name);
    menu.SetTitle(title);

    int added = 0;
    InventoryItem inv;
    StoreItem targetItem;
    for (int i = 0; i < g_hInventory[target].Length; i++)
    {
        g_hInventory[target].GetArray(i, inv, sizeof(InventoryItem));
        if (!FindStoreItemById(inv.item_id, targetItem))
        {
            continue;
        }

        if (PlayerOwnsItem(client, targetItem.id) || !HasAccess(client, targetItem.flag))
        {
            continue;
        }

        char info[96], display[128];
        Format(info, sizeof(info), "%d|%s|%s", targetUserId, senderItemId, targetItem.id);
        if (inv.is_equipped)
        {
            char equippedPrefix[48];
            FormatStorePhrase(client, equippedPrefix, sizeof(equippedPrefix), "Trade Equipped Prefix");
            Format(display, sizeof(display), "%s%s", equippedPrefix, targetItem.name);
        }
        else
        {
            strcopy(display, sizeof(display), targetItem.name);
        }
        menu.AddItem(info, display);
        added++;
    }

    if (added == 0)
    {
        char emptyLabel[96];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "Trade Target Items Empty", client);
        menu.AddItem("none", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_TradeTargetItem(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowTradeTargetMenu(param1, g_szTradeSenderItem[param1]);
    }
    else if (action == MenuAction_Select)
    {
        char info[96], parts[3][32];
        menu.GetItem(param2, info, sizeof(info));
        if (StrEqual(info, "none"))
        {
            return 0;
        }

        ExplodeString(info, "|", parts, 3, 32);
        int target = GetClientOfUserId(StringToInt(parts[0]));
        if (!IsValidHumanClient(target))
        {
            ShowTradeTargetMenu(param1, g_szTradeSenderItem[param1]);
            return 0;
        }

        if (!ValidateInventoryMenuAction(param1, g_iMenuInventoryVersion[param1], parts[1], true) || g_iTradeTargetInvVersion[param1] != g_iInventoryVersion[target] || !PlayerOwnsItem(target, parts[2]))
        {
            PrintStorePhrase(param1, "%T", "Trade Inventory Changed", param1);
            ShowTradeTargetMenu(param1, g_szTradeSenderItem[param1]);
            return 0;
        }

        strcopy(g_szTradeSenderItem[target], sizeof(g_szTradeSenderItem[]), parts[1]);
        strcopy(g_szTradeTargetItem[target], sizeof(g_szTradeTargetItem[]), parts[2]);
        g_iTradeSender[target] = GetClientUserId(param1);
        g_iTradeSenderInvVersion[target] = g_iInventoryVersion[param1];
        g_iTradeTargetInvVersion[target] = g_iInventoryVersion[target];

        StoreItem myItem, theirItem;
        FindStoreItemById(parts[1], myItem);
        FindStoreItemById(parts[2], theirItem);

        PrintStorePhrase(param1, "%T", "Trade Request Sent", param1, target);
        PrintStorePhrase(target, "%T", "Trade Request Received", target, param1, myItem.name, theirItem.name);
        ShowTradeReceiveMenu(target);
        ShowItemDetailsMenu(param1, parts[1]);
    }

    return 0;
}

void ShowTradeReceiveMenu(int client)
{
    int sender = GetClientOfUserId(g_iTradeSender[client]);
    if (!IsValidHumanClient(client) || !IsValidHumanClient(sender))
    {
        return;
    }

    StoreItem senderItem, targetItem;
    if (!FindStoreItemById(g_szTradeSenderItem[client], senderItem) || !FindStoreItemById(g_szTradeTargetItem[client], targetItem))
    {
        return;
    }

    Menu menu = new Menu(MenuHandler_TradeReceive);
    char title[256];
    Format(title, sizeof(title), "%T", "Trade Receive Menu Title", client, sender, senderItem.name, targetItem.name);
    menu.SetTitle(title);
    char acceptLabel[64], denyLabel[64];
    Format(acceptLabel, sizeof(acceptLabel), "%T", "Trade Receive Accept", client);
    Format(denyLabel, sizeof(denyLabel), "%T", "Trade Receive Deny", client);
    menu.AddItem("accept", acceptLabel);
    menu.AddItem("deny", denyLabel);
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_TradeReceive(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        int sender = GetClientOfUserId(g_iTradeSender[param1]);
        if (!IsValidHumanClient(sender))
        {
            PrintStorePhrase(param1, "%T", "Trade Request Invalid", param1);
            g_iTradeSender[param1] = 0;
            g_szTradeSenderItem[param1][0] = '\0';
            g_szTradeTargetItem[param1][0] = '\0';
            g_iTradeSenderInvVersion[param1] = 0;
            g_iTradeTargetInvVersion[param1] = 0;
            return 0;
        }

        if (param2 == 0)
        {
            if (g_iTradeSenderInvVersion[param1] != g_iInventoryVersion[sender] || g_iTradeTargetInvVersion[param1] != g_iInventoryVersion[param1] || !PlayerOwnsItem(sender, g_szTradeSenderItem[param1]) || !PlayerOwnsItem(param1, g_szTradeTargetItem[param1]))
            {
                PrintStorePhrase(sender, "%T", "Trade Request Invalid", sender);
                PrintStorePhrase(param1, "%T", "Trade Request Invalid", param1);
            }
            else if (ExecuteTrade(sender, param1, g_szTradeSenderItem[param1], g_szTradeTargetItem[param1]))
            {
                StoreItem senderItem, targetItem;
                FindStoreItemById(g_szTradeSenderItem[param1], senderItem);
                FindStoreItemById(g_szTradeTargetItem[param1], targetItem);
                PrintStorePhrase(sender, "%T", "Trade Completed Sender", sender, param1, senderItem.name, targetItem.name);
                PrintStorePhrase(param1, "%T", "Trade Completed Target", param1, sender, targetItem.name, senderItem.name);
                ForwardTradeCompleted(sender, param1, g_szTradeSenderItem[param1], g_szTradeTargetItem[param1]);
            }
            else
            {
                PrintStorePhrase(sender, "%T", "Trade Failed", sender);
                PrintStorePhrase(param1, "%T", "Trade Failed", param1);
            }
        }
        else
        {
            PrintStorePhrase(sender, "%T", "Trade Rejected Sender", sender, param1);
            PrintStorePhrase(param1, "%T", "Trade Rejected Target", param1, sender);
        }

        g_iTradeSender[param1] = 0;
        g_szTradeSenderItem[param1][0] = '\0';
        g_szTradeTargetItem[param1][0] = '\0';
        g_iTradeSenderInvVersion[param1] = 0;
        g_iTradeTargetInvVersion[param1] = 0;
    }

    return 0;
}

public Action Cmd_Gift(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (args >= 2)
    {
        char arg1[64], arg2[64];
        GetCmdArg(1, arg1, sizeof(arg1));
        GetCmdArg(2, arg2, sizeof(arg2));

        char targetPattern[64];
        int amount = 0;

        if (IsStringNumeric(arg1))
        {
            amount = StringToInt(arg1);
            strcopy(targetPattern, sizeof(targetPattern), arg2);
        }
        else if (IsStringNumeric(arg2))
        {
            amount = StringToInt(arg2);
            strcopy(targetPattern, sizeof(targetPattern), arg1);
        }
        else
        {
            PrintStorePhrase(client, "%T", "Gift Credits Usage", client);
            return Plugin_Handled;
        }

        if (amount <= 0)
        {
            PrintStorePhrase(client, "%T", "Gift Credits Invalid Amount", client);
            return Plugin_Handled;
        }

        int targets[MAXPLAYERS];
        int count = 0;
        if (!TryResolveCreditTargets(client, targetPattern, targets, count) || count != 1)
        {
            ReplyAdminTargetNotFound(client, targetPattern);
            return Plugin_Handled;
        }

        int target = targets[0];
        if (target == client)
        {
            PrintStorePhrase(client, "%T", "Cannot Self", client);
            return Plugin_Handled;
        }

        if (g_iCredits[client] < amount)
        {
            PrintStorePhrase(client, "%T", "Gift Credits Not Enough", client);
            return Plugin_Handled;
        }

        g_iCredits[client] -= amount;
        g_iCredits[target] += amount;
        g_bCreditsDirty[client] = true;
        g_bCreditsDirty[target] = true;
        LogCreditLedger(client, -amount, "gift_credits_sent");
        LogCreditLedger(target, amount, "gift_credits_received");
        SavePlayer(client);
        SavePlayer(target);

        PrintStorePhrase(client, "%T", "Gift Credits Sent", client, amount, target);
        PrintStorePhrase(target, "%T", "Gift Credits Received", target, client, amount);
        return Plugin_Handled;
    }

    if (g_szLastDetailItem[client][0] != ' ' && PlayerOwnsItem(client, g_szLastDetailItem[client]))
    {
        ShowGiftTargetMenu(client, g_szLastDetailItem[client]);
    }
    else
    {
        ShowInventoryCategoryMenu(client);
        PrintStorePhrase(client, "%T", "Open Item To Gift", client);
        PrintStorePhrase(client, "%T", "Gift Credits Usage", client);
    }

    return Plugin_Handled;
}

public Action Cmd_Trade(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (g_szLastDetailItem[client][0] != '\0' && PlayerOwnsItem(client, g_szLastDetailItem[client]))
    {
        ShowTradeTargetMenu(client, g_szLastDetailItem[client]);
    }
    else
    {
        ShowInventoryCategoryMenu(client);
        PrintStorePhrase(client, "%T", "Open Item To Trade", client);
    }

    return Plugin_Handled;
}

// =========================================================================
// CASINO
// =========================================================================
void RebuildCasinoIndex()
{
    if (g_mCasinoIndex == null)
    {
        g_mCasinoIndex = new StringMap();
    }
    else
    {
        g_mCasinoIndex.Clear();
    }

    if (g_aCasinoIds == null)
    {
        return;
    }

    char id[32];
    for (int i = 0; i < g_aCasinoIds.Length; i++)
    {
        g_aCasinoIds.GetString(i, id, sizeof(id));
        if (id[0] != '\0')
        {
            g_mCasinoIndex.SetValue(id, i);
        }
    }
}

bool CasinoRegisterEntry(const char[] id, const char[] title, const char[] command)
{
    if (id[0] == '\0' || title[0] == '\0' || command[0] == '\0')
    {
        return false;
    }

    if (g_aCasinoIds == null)
    {
        g_aCasinoIds = new ArrayList(32);
    }

    if (g_mCasinoTitles == null)
    {
        g_mCasinoTitles = new StringMap();
    }

    if (g_mCasinoCommands == null)
    {
        g_mCasinoCommands = new StringMap();
    }

    if (g_mCasinoIndex == null)
    {
        g_mCasinoIndex = new StringMap();
    }

    int index;
    if (g_mCasinoIndex.GetValue(id, index))
    {
        if (index < 0 || index >= g_aCasinoIds.Length)
        {
            RebuildCasinoIndex();
            if (g_mCasinoIndex.GetValue(id, index) && index >= 0 && index < g_aCasinoIds.Length)
            {
                g_mCasinoTitles.SetString(id, title);
                g_mCasinoCommands.SetString(id, command);
                return true;
            }
        }
        else
        {
            g_mCasinoTitles.SetString(id, title);
            g_mCasinoCommands.SetString(id, command);
            return true;
        }
    }

    int pushed = g_aCasinoIds.PushString(id);
    if (pushed < 0)
    {
        return false;
    }

    g_mCasinoIndex.SetValue(id, pushed);
    g_mCasinoTitles.SetString(id, title);
    g_mCasinoCommands.SetString(id, command);
    return true;
}

bool CasinoUnregisterEntry(const char[] id)
{
    if (g_aCasinoIds == null || g_mCasinoIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mCasinoIndex.GetValue(id, index))
    {
        return false;
    }

    if (index < 0 || index >= g_aCasinoIds.Length)
    {
        RebuildCasinoIndex();
        if (!g_mCasinoIndex.GetValue(id, index) || index < 0 || index >= g_aCasinoIds.Length)
        {
            return false;
        }
    }

    g_aCasinoIds.Erase(index);
    if (g_mCasinoTitles != null)
    {
        g_mCasinoTitles.Remove(id);
    }
    if (g_mCasinoCommands != null)
    {
        g_mCasinoCommands.Remove(id);
    }
    RebuildCasinoIndex();
    return true;
}

void ShowCasinoMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Casino);
    char title[128];
    char soonLabel[64];

    Format(title, sizeof(title), "%T", "Casino Menu Title", client);
    Format(soonLabel, sizeof(soonLabel), "%T", "Casino Menu Soon", client);

    menu.SetTitle(title);

    if (g_aCasinoIds == null || g_aCasinoIds.Length == 0)
    {
        menu.AddItem("none", soonLabel, ITEMDRAW_DISABLED);
    }
    else
    {
        int added = 0;
        char id[32];
        char entryTitle[64];

        for (int i = 0; i < g_aCasinoIds.Length; i++)
        {
            g_aCasinoIds.GetString(i, id, sizeof(id));
            if (id[0] == '\0')
            {
                continue;
            }

            if (g_mCasinoTitles == null || !g_mCasinoTitles.GetString(id, entryTitle, sizeof(entryTitle)))
            {
                strcopy(entryTitle, sizeof(entryTitle), id);
            }

            menu.AddItem(id, entryTitle);
            added++;
        }

        if (added == 0)
        {
            menu.AddItem("none", soonLabel, ITEMDRAW_DISABLED);
        }
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Casino(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        Cmd_Store(param1, 0);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "none"))
        {
            return 0;
        }

        char command[64];
        if (g_mCasinoCommands != null && g_mCasinoCommands.GetString(info, command, sizeof(command)) && command[0] != '\0')
        {
            FakeClientCommand(param1, "%s", command);
        }
    }

    return 0;
}

// =========================================================================
// INVENTARIO
// =========================================================================
void ShowInventoryCategoryMenu(int client)
{
    Menu menu = new Menu(MenuHandler_InvCategory);
    SetMenuTitlePhrase(menu, client, "Inventory Category Menu Title");
    AddMenuItemPhrase(menu, "skins", client, "Inventory Category Skins");
    AddMenuItemPhrase(menu, "chat", client, "Inventory Category Chat");
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_InvCategory(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        Cmd_Store(param1, 0);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "skins"))
        {
            ShowInventoryTeamMenu(param1);
        }
        else if (StrEqual(info, "chat"))
        {
            ShowInventoryChatMenu(param1);
        }
    }

    return 0;
}

void ShowInventoryTeamMenu(int client)
{
    Menu menu = new Menu(MenuHandler_InvSub);
    SetMenuTitlePhrase(menu, client, "Inventory Teams Menu Title");
    AddMenuItemPhrase(menu, "skin_2", client, "Inventory Teams Menu TT");
    AddMenuItemPhrase(menu, "skin_3", client, "Inventory Teams Menu CT");
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

void ShowInventoryChatMenu(int client)
{
    Menu menu = new Menu(MenuHandler_InvSub);
    char title[192], tagsLabel[64], nameColorLabel[64], chatColorLabel[64];
    Format(title, sizeof(title), "%T", "Inventory Chat Menu Title", client);
    Format(tagsLabel, sizeof(tagsLabel), "%T", "Chat Menu Tags", client);
    Format(nameColorLabel, sizeof(nameColorLabel), "%T", "Chat Menu Name Colors", client);
    Format(chatColorLabel, sizeof(chatColorLabel), "%T", "Chat Menu Chat Colors", client);
    menu.SetTitle(title);
    menu.AddItem("tag", tagsLabel);
    menu.AddItem("namecolor", nameColorLabel);
    menu.AddItem("chatcolor", chatColorLabel);
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_InvSub(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowInventoryCategoryMenu(param1);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        ShowInventoryListMenu(param1, info);
    }

    return 0;
}

bool DoesInventoryItemMatchFilter(const char[] filter, const StoreItem item)
{
    if (StrEqual(filter, "skin_2") && StrEqual(item.type, "skin") && item.team == 2)
    {
        return true;
    }
    if (StrEqual(filter, "skin_3") && StrEqual(item.type, "skin") && item.team == 3)
    {
        return true;
    }
    if (StrEqual(filter, item.type))
    {
        return true;
    }
    return false;
}

void AddInventoryItemsToMenu(int client, Menu menu, const char[] filter, bool equippedOnly, int &itemsAdded)
{
    InventoryItem inv;
    StoreItem item;

    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (!FindStoreItemById(inv.item_id, item))
        {
            continue;
        }

        if (!DoesInventoryItemMatchFilter(filter, item) || view_as<bool>(inv.is_equipped) != equippedOnly)
        {
            continue;
        }

        char display[128], itemInfo[64];
        if (inv.is_equipped)
        {
            char equippedSuffix[48];
            Format(equippedSuffix, sizeof(equippedSuffix), "%T", "Inventory Equipped Suffix", client);
            Format(display, sizeof(display), "%s %s", item.name, equippedSuffix);
        }
        else
        {
            strcopy(display, sizeof(display), item.name);
        }

        Format(itemInfo, sizeof(itemInfo), "%s|%s", filter, item.id);
        menu.AddItem(itemInfo, display);
        itemsAdded++;
    }
}

void ShowInventoryListMenu(int client, const char[] filter)
{
    strcopy(g_szInvFilter[client], 32, filter);

    Menu menu = new Menu(MenuHandler_InvList);
    SetMenuTitlePhrase(menu, client, "Inventory List Menu Title");

    int itemsAdded = 0;
    AddInventoryItemsToMenu(client, menu, filter, true, itemsAdded);
    AddInventoryItemsToMenu(client, menu, filter, false, itemsAdded);

    if (itemsAdded == 0)
    {
        char emptyLabel[96];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "Inventory List Empty", client);
        menu.AddItem("none", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_InvList(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        if (StrEqual(g_szInvFilter[param1], "skin_2") || StrEqual(g_szInvFilter[param1], "skin_3"))
        {
            ShowInventoryTeamMenu(param1);
        }
        else
        {
            ShowInventoryChatMenu(param1);
        }
    }
    else if (action == MenuAction_Select)
    {
        char info[64], buffers[2][32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "none"))
        {
            return 0;
        }

        ExplodeString(info, "|", buffers, 2, 32);
        g_bDetailFromInventory[param1] = true;
        ShowItemDetailsMenu(param1, buffers[1]);
    }

    return 0;
}

// =========================================================================
// EVENTOS DE CRÉDITOS
// =========================================================================
public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (victim > 0)
    {
        RemovePreview(victim);
    }

    if (!IsStoreEnabled() || !gCvarCreditsKillEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (!IsValidHumanClient(attacker) || !IsValidHumanClient(victim) || attacker == victim || GetClientTeam(attacker) < 2 || GetClientTeam(victim) < 2 || GetClientTeam(attacker) == GetClientTeam(victim))
    {
        return Plugin_Continue;
    }

    MarkClientActive(attacker);
    AddCreditsEx(attacker, gCvarCreditsKillAmount.IntValue, "kill", true);

    if (event.GetBool("headshot"))
    {
        AddCreditsEx(attacker, gCvarCreditsHeadshotBonus.IntValue, "headshot", true);
    }

    return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsStoreEnabled() || !gCvarCreditsRoundWinEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int winner = event.GetInt("winner");
    if (winner < 2)
    {
        return Plugin_Continue;
    }

    int amount = gCvarCreditsRoundWinAmount.IntValue;
    if (amount <= 0)
    {
        return Plugin_Continue;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidHumanClient(i) && g_bIsLoaded[i] && GetClientTeam(i) == winner)
        {
            AddCreditsEx(i, amount, "roundwin", true);
        }
    }

    return Plugin_Continue;
}

public Action Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsStoreEnabled() || !gCvarCreditsPlantEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidHumanClient(client))
    {
        MarkClientActive(client);
        AddCreditsEx(client, gCvarCreditsPlantAmount.IntValue, "plant", true);
    }

    return Plugin_Continue;
}

public Action Event_BombDefused(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsStoreEnabled() || !gCvarCreditsDefuseEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidHumanClient(client))
    {
        MarkClientActive(client);
        AddCreditsEx(client, gCvarCreditsDefuseAmount.IntValue, "defuse", true);
    }

    return Plugin_Continue;
}

// =========================================================================
// SPAWN
// =========================================================================
public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        RemovePreview(client);
    }

    if (client > 0 && IsValidHumanClient(client) && IsPlayerAlive(client) && g_bIsLoaded[client])
    {
        CaptureClientDefaultModel(client);
        CreateTimer(0.1, Timer_ApplySkin, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }

    return Plugin_Continue;
}

public Action Timer_ApplySkin(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsValidHumanClient(client) && IsPlayerAlive(client))
    {
        ApplyPlayerSkin(client);
    }

    return Plugin_Stop;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        RemovePreview(client);
    }

    return Plugin_Continue;
}

public Action Event_TeamplayRoundWin(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsStoreEnabled() || !gCvarCreditsRoundWinEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int winner = event.GetInt("team");
    if (winner < 2)
    {
        return Plugin_Continue;
    }

    int amount = gCvarCreditsRoundWinAmount.IntValue;
    if (amount <= 0)
    {
        return Plugin_Continue;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidHumanClient(i) && g_bIsLoaded[i] && GetClientTeam(i) == winner)
        {
            AddCreditsEx(i, amount, "roundwin", true);
        }
    }

    return Plugin_Continue;
}


bool IsStringNumeric(const char[] value)
{
    int len = strlen(value);
    if (len <= 0)
    {
        return false;
    }

    for (int i = 0; i < len; i++)
    {
        if (!IsCharNumeric(value[i]))
        {
            return false;
        }
    }

    return true;
}

bool TryResolveCreditTargets(int admin, const char[] pattern, int targets[MAXPLAYERS], int &count)
{
    count = 0;

    if (StrEqual(pattern, "@all", false))
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidHumanClient(i) && g_bIsLoaded[i])
            {
                targets[count++] = i;
            }
        }
        return (count > 0);
    }

    if (StrEqual(pattern, "@t", false) || StrEqual(pattern, "@ts", false) || StrEqual(pattern, "@team2", false))
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidHumanClient(i) && g_bIsLoaded[i] && GetClientTeam(i) == 2)
            {
                targets[count++] = i;
            }
        }
        return (count > 0);
    }

    if (StrEqual(pattern, "@ct", false) || StrEqual(pattern, "@team3", false))
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidHumanClient(i) && g_bIsLoaded[i] && GetClientTeam(i) == 3)
            {
                targets[count++] = i;
            }
        }
        return (count > 0);
    }

    if (StrEqual(pattern, "@me", false))
    {
        if (admin > 0 && IsValidHumanClient(admin) && g_bIsLoaded[admin])
        {
            targets[count++] = admin;
            return true;
        }
        return false;
    }

    int partialMatch = 0;
    int partialCount = 0;
    char name[MAX_NAME_LENGTH];

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanClient(i) || !g_bIsLoaded[i])
        {
            continue;
        }

        GetClientName(i, name, sizeof(name));

        if (StrEqual(name, pattern, false))
        {
            targets[0] = i;
            count = 1;
            return true;
        }

        if (StrContains(name, pattern, false) != -1)
        {
            partialMatch = i;
            partialCount++;
        }
    }

    if (partialCount == 1)
    {
        targets[0] = partialMatch;
        count = 1;
        return true;
    }

    return false;
}

void ReplyAdminTargetNotFound(int client, const char[] pattern)
{
    char msg[192];
    Format(msg, sizeof(msg), "%T", "Admin Target Not Found", client, pattern);
    ReplaceColorTags(msg, sizeof(msg));
    ReplyToCommand(client, " %s", msg);
}

// =========================================================================
// ADMIN
// =========================================================================
public Action Cmd_Credits(int client, int args)
{
    if (client > 0 && !EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (client > 0 && g_bIsLoaded[client])
    {
        char creditsText[32];
        FormatNumberDots(g_iCredits[client], creditsText, sizeof(creditsText));

        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsValidHumanClient(i))
            {
                continue;
            }

            PrintStorePhrase(i, "%T", "Credits Broadcast", i, client, creditsText);
        }
    }
    return Plugin_Handled;
}


public Action Cmd_TopCredits(int client, int args)
{
    if (client > 0 && !EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (g_DB == null)
    {
        char msg[192];
        Format(msg, sizeof(msg), "%T", "Store DB Not Ready", client);
        ReplaceColorTags(msg, sizeof(msg));
        ReplyToCommand(client, " %s", msg);
        return Plugin_Handled;
    }

    char query[256];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query), "SELECT name, credits FROM store_players ORDER BY credits DESC, name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query), "SELECT name, credits FROM store_players ORDER BY credits DESC, name COLLATE NOCASE ASC LIMIT 10");
    }

    g_DB.Query(OnTopCreditsLoaded, query, GetClientUserId(client));
    return Plugin_Handled;
}

public void OnTopCreditsLoaded(Database db, DBResultSet results, const char[] error, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0] != '\0' || results == null)
    {
        LogStoreError("OnTopCreditsLoaded", error);
        PrintStorePhrase(client, "%T", "Top Credits Load Failed", client);
        return;
    }

    Menu menu = new Menu(MenuHandler_TopCredits);
    SetMenuTitlePhrase(menu, client, "Top Credits Menu Title");

    char playerName[64];
    int credits;
    char display[160];
    char info[8];
    int pos = 1;

    while (results.FetchRow())
    {
        results.FetchString(0, playerName, sizeof(playerName));
        credits = results.FetchInt(1);
        char creditsText[32];
        FormatNumberDots(credits, creditsText, sizeof(creditsText));
        Format(display, sizeof(display), "%T", "Top Credits Entry", client, pos, playerName, creditsText);
        IntToString(pos, info, sizeof(info));
        menu.AddItem(info, display, ITEMDRAW_DISABLED);
        pos++;
    }

    if (pos == 1)
    {
        char emptyLabel[96];
        Format(emptyLabel, sizeof(emptyLabel), "%T", "Top Credits Empty", client);
        menu.AddItem("empty", emptyLabel, ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, 20);
}

public int MenuHandler_TopCredits(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        Cmd_Store(param1, 0);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

void ReplyAuditOutput(int client, const char[] format, any ...)
{
    char buffer[256];
    VFormat(buffer, sizeof(buffer), format, 3);

    if (client > 0)
    {
        if (StrContains(buffer, "[Umbrella Store]") == 0)
        {
            ReplaceString(buffer, sizeof(buffer), "[Umbrella Store]", " \x03[Umbrella Store]\x01");
        }
        ReplyToCommand(client, "%s", buffer);
    }
    else
    {
        PrintToServer("%s", buffer);
    }
}

public Action Cmd_StoreAudit(int client, int args)
{
    if (g_DB == null || !g_bLateDatabaseReady)
    {
        ReplyAuditOutput(client, "[Umbrella Store] Database no lista.");
        return Plugin_Handled;
    }

    int limit = 20;
    if (args == 1)
    {
        char argLimit[16];
        GetCmdArg(1, argLimit, sizeof(argLimit));
        if (IsStringNumeric(argLimit))
        {
            limit = StringToInt(argLimit);
            if (limit < 1)
            {
                limit = 1;
            }
            else if (limit > 100)
            {
                limit = 100;
            }
        }
    }
    else if (args >= 2)
    {
        char argLimit[16];
        GetCmdArg(2, argLimit, sizeof(argLimit));
        if (!IsStringNumeric(argLimit))
        {
            ReplyAuditOutput(client, "[Umbrella Store] Uso: sm_storeaudit [target] [limit]");
            return Plugin_Handled;
        }

        limit = StringToInt(argLimit);
        if (limit < 1)
        {
            limit = 1;
        }
        else if (limit > 100)
        {
            limit = 100;
        }
    }

    bool filterByTarget = false;
    char safeTargetSteamId[64];
    safeTargetSteamId[0] = '\0';
    char targetLabel[64];
    strcopy(targetLabel, sizeof(targetLabel), "global");

    bool firstArgIsLimit = false;
    if (args == 1)
    {
        char firstArg[64];
        GetCmdArg(1, firstArg, sizeof(firstArg));
        firstArgIsLimit = IsStringNumeric(firstArg);
    }

    if (args >= 1 && !firstArgIsLimit)
    {
        char argTarget[64];
        GetCmdArg(1, argTarget, sizeof(argTarget));

        if (StrEqual(argTarget, "@all", false) || StrEqual(argTarget, "all", false) || StrEqual(argTarget, "global", false))
        {
            filterByTarget = false;
            strcopy(targetLabel, sizeof(targetLabel), "global");
        }
        else
        {
            int targets[MAXPLAYERS];
            int count = 0;
            if (!TryResolveCreditTargets(client, argTarget, targets, count) || count != 1)
            {
                ReplyAdminTargetNotFound(client, argTarget);
                return Plugin_Handled;
            }

            int target = targets[0];
            char targetSteamId[32];
            if (!GetClientSteamIdSafe(target, targetSteamId, sizeof(targetSteamId)))
            {
                ReplyAuditOutput(client, "[Umbrella Store] No se pudo obtener SteamID del objetivo.");
                return Plugin_Handled;
            }

            EscapeStringSafe(targetSteamId, safeTargetSteamId, sizeof(safeTargetSteamId));
            GetClientName(target, targetLabel, sizeof(targetLabel));
            filterByTarget = true;
        }
    }
    else if (client > 0)
    {
        char targetSteamId[32];
        if (GetClientSteamIdSafe(client, targetSteamId, sizeof(targetSteamId)))
        {
            EscapeStringSafe(targetSteamId, safeTargetSteamId, sizeof(safeTargetSteamId));
            GetClientName(client, targetLabel, sizeof(targetLabel));
            filterByTarget = true;
        }
    }

    char query[512];
    if (filterByTarget)
    {
        Format(query, sizeof(query),
            "SELECT steamid, amount, reason, balance_after, created_at FROM store_credits_ledger WHERE steamid = '%s' ORDER BY id DESC LIMIT %d",
            safeTargetSteamId, limit);
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT steamid, amount, reason, balance_after, created_at FROM store_credits_ledger ORDER BY id DESC LIMIT %d",
            limit);
    }

    DataPack pack = new DataPack();
    pack.WriteCell((client > 0) ? GetClientUserId(client) : 0);
    pack.WriteCell(limit);
    pack.WriteCell(filterByTarget ? 1 : 0);
    pack.WriteString(targetLabel);

    g_DB.Query(OnStoreAuditLoaded, query, pack);
    ReplyAuditOutput(client, "[Umbrella Store] Cargando auditoria de creditos...");
    return Plugin_Handled;
}

public void OnStoreAuditLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int requesterUserId = pack.ReadCell();
    int limit = pack.ReadCell();
    bool filtered = view_as<bool>(pack.ReadCell());
    char targetLabel[64];
    pack.ReadString(targetLabel, sizeof(targetLabel));
    delete pack;

    int client = GetClientOfUserId(requesterUserId);
    bool toConsole = (requesterUserId == 0);
    if (!toConsole && (client <= 0 || !IsClientInGame(client)))
    {
        return;
    }

    if (db == null || results == null || error[0] != '\0')
    {
        ReplyAuditOutput(client, "[Umbrella Store] Error cargando auditoria: %s", error);
        return;
    }

    if (filtered)
    {
        ReplyAuditOutput(client, "========== Store Audit (%s, ultimo %d) ==========", targetLabel, limit);
    }
    else
    {
        ReplyAuditOutput(client, "========== Store Audit (global, ultimo %d) ==========", limit);
    }

    bool hasRows = false;
    while (results.FetchRow())
    {
        hasRows = true;

        char steamid[32], reason[96], when[32], amountText[32], balanceText[32];
        int amount = 0;
        int balanceAfter = 0;
        int createdAt = 0;

        results.FetchString(0, steamid, sizeof(steamid));
        amount = results.FetchInt(1);
        results.FetchString(2, reason, sizeof(reason));
        balanceAfter = results.FetchInt(3);
        createdAt = results.FetchInt(4);

        FormatTime(when, sizeof(when), "%Y-%m-%d %H:%M:%S", createdAt);
        FormatNumberDots(amount, amountText, sizeof(amountText));
        FormatNumberDots(balanceAfter, balanceText, sizeof(balanceText));

        ReplyAuditOutput(client, "[%s] %s | delta=%s | balance=%s | reason=%s", when, steamid, amountText, balanceText, reason);
    }

    if (!hasRows)
    {
        ReplyAuditOutput(client, "[Umbrella Store] No hay registros de auditoria para ese criterio.");
    }
}

public Action Cmd_GiveCredits(int client, int args)
{
    if (args < 2)
    {
        ReplyToCommand(client, "%T", "Admin Give Usage", client);
        return Plugin_Handled;
    }

    char arg1[64], arg2[16];
    GetCmdArg(1, arg1, sizeof(arg1));
    GetCmdArg(2, arg2, sizeof(arg2));

    int amount = StringToInt(arg2);
    if (amount <= 0)
    {
        ReplyToCommand(client, "%T", "Admin Amount Positive", client);
        return Plugin_Handled;
    }

    int targets[MAXPLAYERS];
    int count = 0;
    if (!TryResolveCreditTargets(client, arg1, targets, count))
    {
        ReplyAdminTargetNotFound(client, arg1);
        return Plugin_Handled;
    }

    for (int i = 0; i < count; i++)
    {
        int target = targets[i];
        g_iCredits[target] += amount;
        g_bCreditsDirty[target] = true;
        LogCreditLedger(target, amount, "admin_give");
        SavePlayer(target);
    }

    char amountText[32];
    FormatNumberDots(amount, amountText, sizeof(amountText));

    if (count == 1)
    {
        ReplyToCommand(client, "%T", "Admin Give Single", client, amountText, targets[0]);
    }
    else
    {
        ReplyToCommand(client, "%T", "Admin Give Multi", client, amountText, count);
    }

    return Plugin_Handled;
}

public Action Cmd_SetCredits(int client, int args)
{
    if (args < 2)
    {
        ReplyToCommand(client, "%T", "Admin Set Usage", client);
        return Plugin_Handled;
    }

    char arg1[64], arg2[16];
    GetCmdArg(1, arg1, sizeof(arg1));
    GetCmdArg(2, arg2, sizeof(arg2));

    int amount = StringToInt(arg2);
    if (amount < 0)
    {
        ReplyToCommand(client, "%T", "Admin Amount NonNegative", client);
        return Plugin_Handled;
    }

    int targets[MAXPLAYERS];
    int count = 0;
    if (!TryResolveCreditTargets(client, arg1, targets, count))
    {
        ReplyAdminTargetNotFound(client, arg1);
        return Plugin_Handled;
    }

    for (int i = 0; i < count; i++)
    {
        int target = targets[i];
        int delta = amount - g_iCredits[target];
        g_iCredits[target] = amount;
        g_bCreditsDirty[target] = true;
        LogCreditLedger(target, delta, "admin_set");
        SavePlayer(target);
    }

    char amountText[32];
    FormatNumberDots(amount, amountText, sizeof(amountText));

    if (count == 1)
    {
        ReplyToCommand(client, "%T", "Admin Set Single", client, amountText, targets[0]);
    }
    else
    {
        ReplyToCommand(client, "%T", "Admin Set Multi", client, amountText, count);
    }

    return Plugin_Handled;
}


// =========================================================================
// NATIVES - UMBRELLA STORE API
// =========================================================================
public any Native_US_Casino_Register(Handle plugin, int numParams)
{
    char id[32], title[64], command[64];
    GetNativeString(1, id, sizeof(id));
    GetNativeString(2, title, sizeof(title));
    GetNativeString(3, command, sizeof(command));
    return CasinoRegisterEntry(id, title, command);
}

public any Native_US_Casino_Unregister(Handle plugin, int numParams)
{
    char id[32];
    GetNativeString(1, id, sizeof(id));
    return CasinoUnregisterEntry(id);
}

public any Native_US_OpenCasinoMenu(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || !IsStoreEnabled())
    {
        return false;
    }

    ShowCasinoMenu(client);
    return true;
}

// =========================================================================
// NATIVES - UMBRELLA STORE API
// =========================================================================
public any Native_US_IsLoaded(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return (client >= 1 && client <= MaxClients && g_bIsLoaded[client] && IsStoreEnabled());
}

public any Native_US_GetCredits(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients)
    {
        return 0;
    }
    return g_iCredits[client];
}

public any Native_US_SetCredits(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int amount = GetNativeCell(2);
    if (client < 1 || client > MaxClients || !g_bIsLoaded[client])
    {
        return false;
    }
    if (amount < 0)
    {
        amount = 0;
    }
    int delta = amount - g_iCredits[client];
    g_iCredits[client] = amount;
    g_bCreditsDirty[client] = true;
    LogCreditLedger(client, delta, "api_set");
    SavePlayer(client);
    return true;
}

public any Native_US_AddCredits(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int amount = GetNativeCell(2);
    bool notify = (numParams >= 3) ? view_as<bool>(GetNativeCell(3)) : false;
    if (client < 1 || client > MaxClients || !g_bIsLoaded[client] || amount <= 0)
    {
        return false;
    }
    AddCreditsEx(client, amount, "api", notify);
    SavePlayer(client);
    return true;
}

public any Native_US_TakeCredits(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int amount = GetNativeCell(2);
    if (client < 1 || client > MaxClients || !g_bIsLoaded[client] || amount <= 0 || g_iCredits[client] < amount)
    {
        return false;
    }
    g_iCredits[client] -= amount;
    g_bCreditsDirty[client] = true;
    LogCreditLedger(client, -amount, "api_take");
    SavePlayer(client);
    return true;
}

public any Native_US_HasItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64];
    GetNativeString(2, itemId, sizeof(itemId));
    if (client < 1 || client > MaxClients || !g_bIsLoaded[client])
    {
        return false;
    }
    return PlayerOwnsItem(client, itemId);
}

public any Native_US_GiveItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64];
    GetNativeString(2, itemId, sizeof(itemId));
    bool equip = (numParams >= 3) ? view_as<bool>(GetNativeCell(3)) : false;
    return GiveItemToClient(client, itemId, equip, true);
}

public any Native_US_RemoveItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64];
    GetNativeString(2, itemId, sizeof(itemId));
    return RemoveItemFromClient(client, itemId, true);
}


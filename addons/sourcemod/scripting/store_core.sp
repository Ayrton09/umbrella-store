#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>

// =========================================================================
// CONFIG
// =========================================================================
#define STORE_DB_CONFIG          "store"
#define STORE_ITEMS_CONFIG       "configs/umbrella_store/umbrella_store_items.txt"
#define STORE_QUESTS_CONFIG      "configs/umbrella_store/umbrella_store_quests.txt"
#define STORE_LOG_PREFIX         "[Umbrella Store]"
#define STORE_API_VERSION        2
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
    char type[32];
    char category[32];
    char description[128];
    char rarity[32];
    char szModel[PLATFORM_MAX_PATH];
    char szArms[PLATFORM_MAX_PATH];
    char szValue[128];
    char icon[128];
    char metadata[256];
    char requires_item[32];
    char bundle_id[32];
    int price;
    int sale_price;
    int team;
    int sort_order;
    int starts_at;
    int ends_at;
    int sell_percent_override;
    int hidden;
    char flag[16];
}

enum struct StoreMenuSection
{
    char id[32];
    char title[64];
    char command[64];
    int sort_order;
}

enum struct StoreItemTypeDefinition
{
    char type[32];
    char category[32];
    int equippable;
    int exclusive;
    int is_builtin;
}

enum struct StoreQuestDefinition
{
    char id[64];
    char title[96];
    char category[32];
    char description[128];
    char reward_item[32];
    int reward_item_equip;
    int goal;
    int reward_credits;
    int repeatable;
    int max_completions;
    char requires_quest[64];
    int starts_at;
    int ends_at;
}

enum struct StoreLeaderboardDefinition
{
    char id[32];
    char title[96];
    char stat_key[64];
    char entry_phrase[64];
    int sort_order;
}

enum struct StoreQuestProgressSnapshot
{
    char quest_id[64];
    int progress;
    int completed_at;
    int rewarded_at;
    int completion_count;
}

enum struct StoreProfileSnapshot
{
    int credits;
    int owned_items;
    int equipped_items;
    int credits_earned;
    int credits_spent;
    int purchases_total;
    int sales_total;
    int gifts_sent;
    int gifts_received;
    int trades_completed;
    int daily_best_streak;
    int quests_completed;
    int blackjack_games;
    int blackjack_profit;
    int coinflip_games;
    int coinflip_profit;
    int crash_rounds;
    int crash_profit;
    int roulette_games;
    int roulette_profit;
    int total_casino_activity;
    int total_casino_profit;
}

enum struct InventoryItem
{
    char item_id[32];
    int is_equipped;
}

ArrayList g_aItems;
ArrayList g_hInventory[MAXPLAYERS + 1];
ArrayList g_aCasinoIds;
ArrayList g_aMenuSections;
ArrayList g_aItemTypes;
ArrayList g_aQuestDefinitions;
ArrayList g_aQuestConfigIds;
ArrayList g_aQuestConfigBaseDefinitions;
ArrayList g_aQuestConfigBaseValid;
ArrayList g_aLeaderboards;
StringMap g_mItemIndex;
StringMap g_mInventoryOwned[MAXPLAYERS + 1];
StringMap g_mCasinoTitles;
StringMap g_mCasinoCommands;
StringMap g_mCasinoIndex;
StringMap g_mMenuSectionIndex;
StringMap g_mItemTypeIndex;
StringMap g_mQuestIndex;
StringMap g_mItemMetadata;
StringMap g_mEnsuredTables;
StringMap g_mAllowedStats;
StringMap g_mLeaderboardIndex;
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
char g_szPendingMarketItem[MAXPLAYERS + 1][32];
bool g_bAwaitingMarketPrice[MAXPLAYERS + 1] = {false, ...};
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
ConVar gCvarMarketEnabled;
ConVar gCvarMarketMinPrice;
ConVar gCvarMarketMaxPrice;
ConVar gCvarMarketListingHours;
ConVar gCvarMarketFeePercent;

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
Handle g_hFwdPurchasePre = null;
Handle g_hFwdPurchasePost = null;
Handle g_hFwdEquipPre = null;
Handle g_hFwdEquipPost = null;
Handle g_hFwdTradePre = null;
Handle g_hFwdTradePost = null;
Handle g_hFwdCreditsChanged = null;
Handle g_hFwdInventoryChanged = null;
Handle g_hFwdQuestCompleted = null;

// =========================================================================
// API PÚBLICA
// =========================================================================
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("CS_UpdateClientModel");

    RegPluginLibrary("umbrella_store");
    CreateNative("US_GetApiVersion", Native_US_GetApiVersion);
    CreateNative("US_IsLoaded", Native_US_IsLoaded);
    CreateNative("US_GetCredits", Native_US_GetCredits);
    CreateNative("US_SetCredits", Native_US_SetCredits);
    CreateNative("US_AddCredits", Native_US_AddCredits);
    CreateNative("US_TakeCredits", Native_US_TakeCredits);
    CreateNative("US_HasItem", Native_US_HasItem);
    CreateNative("US_GiveItem", Native_US_GiveItem);
    CreateNative("US_RemoveItem", Native_US_RemoveItem);
    CreateNative("US_OpenStoreMenu", Native_US_OpenStoreMenu);
    CreateNative("US_RegisterMenuSection", Native_US_RegisterMenuSection);
    CreateNative("US_UnregisterMenuSection", Native_US_UnregisterMenuSection);
    CreateNative("US_GetItemCount", Native_US_GetItemCount);
    CreateNative("US_GetItemIdByIndex", Native_US_GetItemIdByIndex);
    CreateNative("US_GetItemInfo", Native_US_GetItemInfo);
    CreateNative("US_GetItemType", Native_US_GetItemType);
    CreateNative("US_GetItemPrice", Native_US_GetItemPrice);
    CreateNative("US_GetEquippedItem", Native_US_GetEquippedItem);
    CreateNative("US_CanPurchaseItem", Native_US_CanPurchaseItem);
    CreateNative("US_TryPurchaseItem", Native_US_TryPurchaseItem);
    CreateNative("US_CanEquipItem", Native_US_CanEquipItem);
    CreateNative("US_TryEquipItem", Native_US_TryEquipItem);
    CreateNative("US_RegisterItemType", Native_US_RegisterItemType);
    CreateNative("US_UnregisterItemType", Native_US_UnregisterItemType);
    CreateNative("US_GetItemMetadata", Native_US_GetItemMetadata);
    CreateNative("US_IsDatabaseReady", Native_US_IsDatabaseReady);
    CreateNative("US_GetDatabaseConfig", Native_US_GetDatabaseConfig);
    CreateNative("US_IsMySQL", Native_US_IsMySQL);
    CreateNative("US_GetDatabaseHandle", Native_US_GetDatabaseHandle);
    CreateNative("US_DB_Escape", Native_US_DB_Escape);
    CreateNative("US_DB_EnsureTable", Native_US_DB_EnsureTable);
    CreateNative("US_RegisterStatKey", Native_US_RegisterStatKey);
    CreateNative("US_AddStat", Native_US_AddStat);
    CreateNative("US_SetStatMax", Native_US_SetStatMax);
    CreateNative("US_RegisterQuest", Native_US_RegisterQuest);
    CreateNative("US_RegisterQuestEx", Native_US_RegisterQuestEx);
    CreateNative("US_UnregisterQuest", Native_US_UnregisterQuest);
    CreateNative("US_AdvanceQuestProgress", Native_US_AdvanceQuestProgress);
    CreateNative("US_SetQuestProgressMax", Native_US_SetQuestProgressMax);
    CreateNative("US_GetQuestProgress", Native_US_GetQuestProgress);
    CreateNative("US_RegisterLeaderboard", Native_US_RegisterLeaderboard);
    CreateNative("US_UnregisterLeaderboard", Native_US_UnregisterLeaderboard);
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
    version = "1.1.0",
    url = ""
};

// =========================================================================
// FORWARDS PRINCIPALES
// =========================================================================
public void OnPluginStart()
{
    g_aItems = new ArrayList(sizeof(StoreItem));
    g_aCasinoIds = new ArrayList(32);
    g_aMenuSections = new ArrayList(sizeof(StoreMenuSection));
    g_aItemTypes = new ArrayList(sizeof(StoreItemTypeDefinition));
    g_aQuestDefinitions = new ArrayList(sizeof(StoreQuestDefinition));
    g_aQuestConfigIds = new ArrayList(64);
    g_aQuestConfigBaseDefinitions = new ArrayList(sizeof(StoreQuestDefinition));
    g_aQuestConfigBaseValid = new ArrayList();
    g_aLeaderboards = new ArrayList(sizeof(StoreLeaderboardDefinition));
    g_mItemIndex = new StringMap();
    g_mCasinoTitles = new StringMap();
    g_mCasinoCommands = new StringMap();
    g_mCasinoIndex = new StringMap();
    g_mMenuSectionIndex = new StringMap();
    g_mItemTypeIndex = new StringMap();
    g_mQuestIndex = new StringMap();
    g_mItemMetadata = new StringMap();
    g_mEnsuredTables = new StringMap();
    g_mAllowedStats = new StringMap();
    g_mLeaderboardIndex = new StringMap();

    LoadTranslations("umbrella_store.phrases");
    gCvarDatabase = CreateConVar("store_database", STORE_DB_CONFIG, "Explicit database entry name from databases.cfg (no automatic fallback).");
    g_hFwdCreditsGiven = CreateGlobalForward("OnStoreCreditsGiven", ET_Ignore, Param_Cell, Param_Cell, Param_String);
    g_hFwdItemPurchased = CreateGlobalForward("OnStoreItemPurchased", ET_Ignore, Param_Cell, Param_String);
    g_hFwdItemEquipped = CreateGlobalForward("OnStoreItemEquipped", ET_Ignore, Param_Cell, Param_String, Param_Cell);
    g_hFwdTradeCompleted = CreateGlobalForward("OnStoreTradeCompleted", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_String);
    g_hFwdPurchasePre = CreateGlobalForward("US_OnPurchasePre", ET_Hook, Param_Cell, Param_String, Param_Cell);
    g_hFwdPurchasePost = CreateGlobalForward("US_OnPurchasePost", ET_Ignore, Param_Cell, Param_String, Param_Cell, Param_Cell);
    g_hFwdEquipPre = CreateGlobalForward("US_OnEquipPre", ET_Hook, Param_Cell, Param_String, Param_Cell);
    g_hFwdEquipPost = CreateGlobalForward("US_OnEquipPost", ET_Ignore, Param_Cell, Param_String, Param_Cell);
    g_hFwdTradePre = CreateGlobalForward("US_OnTradePre", ET_Hook, Param_Cell, Param_Cell, Param_String, Param_String);
    g_hFwdTradePost = CreateGlobalForward("US_OnTradePost", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_String);
    g_hFwdCreditsChanged = CreateGlobalForward("US_OnCreditsChanged", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_String);
    g_hFwdInventoryChanged = CreateGlobalForward("US_OnInventoryChanged", ET_Ignore, Param_Cell, Param_String, Param_String);
    g_hFwdQuestCompleted = CreateGlobalForward("US_OnQuestCompleted", ET_Ignore, Param_Cell, Param_String, Param_Cell);

    RegConsoleCmd("sm_store", Cmd_Store);
    RegConsoleCmd("sm_tienda", Cmd_Store);
    RegConsoleCmd("sm_profile", Cmd_Profile);
    RegConsoleCmd("sm_perfil", Cmd_Profile);
    RegConsoleCmd("sm_market", Cmd_Market);
    RegConsoleCmd("sm_mercado", Cmd_Market);
    RegConsoleCmd("sm_profileexport", Cmd_ProfileExport);
    RegConsoleCmd("sm_exportprofile", Cmd_ProfileExport);
    RegConsoleCmd("sm_quests", Cmd_Quests);
    RegConsoleCmd("sm_misiones", Cmd_Quests);
    RegConsoleCmd("sm_tops", Cmd_Leaderboards);
    RegConsoleCmd("sm_leaderboards", Cmd_Leaderboards);
    RegConsoleCmd("sm_rankings", Cmd_Leaderboards);

    RegConsoleCmd("sm_creditos", Cmd_Credits);
    RegConsoleCmd("sm_credits", Cmd_Credits);
    RegConsoleCmd("sm_topcredits", Cmd_TopCredits);
    RegConsoleCmd("sm_topprofit", Cmd_TopProfit);
    RegConsoleCmd("sm_topdaily", Cmd_TopDaily);
    RegConsoleCmd("sm_topstreak", Cmd_TopDaily);
    RegConsoleCmd("sm_topbj", Cmd_TopBlackjack);
    RegConsoleCmd("sm_topblackjack", Cmd_TopBlackjack);
    RegConsoleCmd("sm_topcf", Cmd_TopCoinflip);
    RegConsoleCmd("sm_topcoinflip", Cmd_TopCoinflip);
    RegConsoleCmd("sm_topcrash", Cmd_TopCrash);
    RegConsoleCmd("sm_toproulette", Cmd_TopRoulette);
    RegConsoleCmd("sm_topru", Cmd_TopRoulette);

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
    RegAdminCmd("sm_storedebug", Cmd_StoreDebug, ADMFLAG_ROOT);
    RegAdminCmd("sm_storequestsdebug", Cmd_StoreQuestsDebug, ADMFLAG_ROOT);
    RegAdminCmd("sm_storeexport", Cmd_StoreExportTarget, ADMFLAG_ROOT);

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

    RegisterBuiltinItemTypes();
    RegisterBuiltinStatKeys();
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
    LoadQuestConfig();
}

public void OnAllPluginsLoaded()
{
    LoadQuestConfig();
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
    g_bAwaitingMarketPrice[client] = false;
    g_szPendingMarketItem[client][0] = '\0';
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

bool IsWholeNumberString(const char[] value)
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

bool GetDatabaseConfigName(char[] buffer, int maxlen)
{
    if (gCvarDatabase != null)
    {
        gCvarDatabase.GetString(buffer, maxlen);
        TrimString(buffer);
    }
    else
    {
        strcopy(buffer, maxlen, STORE_DB_CONFIG);
    }

    if (buffer[0] == '\0')
    {
        strcopy(buffer, maxlen, STORE_DB_CONFIG);
    }

    return (buffer[0] != '\0');
}

bool IsMarketplaceEnabled()
{
    return (gCvarMarketEnabled == null || gCvarMarketEnabled.BoolValue);
}

int GetMarketplaceMinPrice()
{
    return (gCvarMarketMinPrice != null) ? gCvarMarketMinPrice.IntValue : 50;
}

int GetMarketplaceMaxPrice()
{
    return (gCvarMarketMaxPrice != null) ? gCvarMarketMaxPrice.IntValue : 1000000;
}

int GetMarketplaceListingHours()
{
    return (gCvarMarketListingHours != null) ? gCvarMarketListingHours.IntValue : 72;
}

int GetMarketplaceFeePercent()
{
    return (gCvarMarketFeePercent != null) ? gCvarMarketFeePercent.IntValue : 5;
}

int GetOnlineClientBySteamId(const char[] steamid)
{
    char currentSteamId[32];
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanClient(i) || !g_bIsLoaded[i])
        {
            continue;
        }

        if (GetClientSteamIdSafe(i, currentSteamId, sizeof(currentSteamId)) && StrEqual(currentSteamId, steamid))
        {
            return i;
        }
    }

    return 0;
}

bool HasActiveMarketplaceListingForSteamId(const char[] steamid, const char[] itemId)
{
    if (g_DB == null || steamid[0] == '\0' || itemId[0] == '\0')
    {
        return false;
    }

    char safeSteamId[64], safeItemId[64], query[320];
    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));
    Format(query, sizeof(query),
        "SELECT id FROM store_market_listings WHERE seller_steamid = '%s' AND item_id = '%s' AND sold_at = 0 AND cancelled_at = 0 AND expires_at > %d LIMIT 1",
        safeSteamId, safeItemId, GetTime());

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("HasActiveMarketplaceListingForSteamId", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }

    bool found = results.FetchRow();
    delete results;
    SQL_UnlockDatabase(g_DB);
    return found;
}

bool HasActiveMarketplaceListing(int client, const char[] itemId)
{
    char steamid[32];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    return HasActiveMarketplaceListingForSteamId(steamid, itemId);
}

bool CancelMarketplaceListingsForSteamIdItem(const char[] steamid, const char[] itemId)
{
    if (g_DB == null || steamid[0] == '\0' || itemId[0] == '\0')
    {
        return false;
    }

    char safeSteamId[64], safeItemId[64], query[320];
    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));
    Format(query, sizeof(query),
        "UPDATE store_market_listings SET cancelled_at = %d WHERE seller_steamid = '%s' AND item_id = '%s' AND sold_at = 0 AND cancelled_at = 0",
        GetTime(), safeSteamId, safeItemId);

    SQL_LockDatabase(g_DB);
    bool ok = SQL_FastQuery(g_DB, query);
    if (!ok)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("CancelMarketplaceListingsForSteamIdItem", error);
    }
    SQL_UnlockDatabase(g_DB);
    return ok;
}

bool CancelMarketplaceListingsForClientItem(int client, const char[] itemId)
{
    char steamid[32];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    return CancelMarketplaceListingsForSteamIdItem(steamid, itemId);
}

void SyncMarketplaceTransferInMemory(const char[] sellerSteamId, int buyer, const char[] itemId, int sellerNetCredits)
{
    int seller = GetOnlineClientBySteamId(sellerSteamId);
    int sellerIndex = (seller > 0) ? FindInventoryIndexByItemId(seller, itemId) : -1;

    if (seller > 0 && sellerIndex != -1)
    {
        g_hInventory[seller].Erase(sellerIndex);
        InventoryOwnedSet(seller, itemId, false);
        MarkInventoryChanged(seller);
        g_iCredits[seller] += sellerNetCredits;
        ReportCreditsChanged(seller, sellerNetCredits, "market_sale", false, true);
        ForwardInventoryChanged(seller, itemId, "market_sale_out");
    }

    if (g_hInventory[buyer] != null && !PlayerOwnsItem(buyer, itemId))
    {
        InventoryItem newInv;
        strcopy(newInv.item_id, sizeof(newInv.item_id), itemId);
        newInv.is_equipped = 0;
        g_hInventory[buyer].PushArray(newInv, sizeof(InventoryItem));
        InventoryOwnedSet(buyer, itemId, true);
        MarkInventoryChanged(buyer);
        ForwardInventoryChanged(buyer, itemId, "market_buy_in");
    }
}

void BuildItemMetadataKey(const char[] itemId, const char[] key, char[] buffer, int maxlen)
{
    Format(buffer, maxlen, "%s::%s", itemId, key);
}

void ClearItemMetadataForItem(const char[] itemId)
{
    if (g_mItemMetadata == null)
    {
        return;
    }

    StringMapSnapshot snapshot = g_mItemMetadata.Snapshot();
    char key[192];

    for (int i = snapshot.Length - 1; i >= 0; i--)
    {
        snapshot.GetKey(i, key, sizeof(key));
        if (StrContains(key, itemId, false) == 0 && key[strlen(itemId)] == ':' && key[strlen(itemId) + 1] == ':')
        {
            g_mItemMetadata.Remove(key);
        }
    }

    delete snapshot;
}

void SetItemMetadataValue(const char[] itemId, const char[] key, const char[] value)
{
    if (g_mItemMetadata == null || itemId[0] == '\0' || key[0] == '\0')
    {
        return;
    }

    char metadataKey[192];
    BuildItemMetadataKey(itemId, key, metadataKey, sizeof(metadataKey));
    g_mItemMetadata.SetString(metadataKey, value);
}

bool GetItemMetadataValue(const char[] itemId, const char[] key, char[] value, int maxlen)
{
    value[0] = '\0';

    if (g_mItemMetadata == null || itemId[0] == '\0' || key[0] == '\0')
    {
        return false;
    }

    char metadataKey[192];
    BuildItemMetadataKey(itemId, key, metadataKey, sizeof(metadataKey));
    return g_mItemMetadata.GetString(metadataKey, value, maxlen);
}

bool RegisterItemTypeInternal(const char[] type, const char[] category, bool equippable, bool exclusive, bool isBuiltin = false)
{
    if (type[0] == '\0')
    {
        return false;
    }

    if (g_aItemTypes == null)
    {
        g_aItemTypes = new ArrayList(sizeof(StoreItemTypeDefinition));
    }

    if (g_mItemTypeIndex == null)
    {
        g_mItemTypeIndex = new StringMap();
    }

    StoreItemTypeDefinition definition;
    strcopy(definition.type, sizeof(definition.type), type);
    strcopy(definition.category, sizeof(definition.category), category);
    definition.equippable = equippable ? 1 : 0;
    definition.exclusive = exclusive ? 1 : 0;
    definition.is_builtin = isBuiltin ? 1 : 0;

    int index;
    if (g_mItemTypeIndex.GetValue(type, index) && index >= 0 && index < g_aItemTypes.Length)
    {
        g_aItemTypes.SetArray(index, definition, sizeof(StoreItemTypeDefinition));
        return true;
    }

    index = g_aItemTypes.PushArray(definition, sizeof(StoreItemTypeDefinition));
    if (index < 0)
    {
        return false;
    }

    g_mItemTypeIndex.SetValue(type, index);
    return true;
}

bool UnregisterItemTypeInternal(const char[] type, bool allowBuiltin = false)
{
    if (type[0] == '\0' || g_aItemTypes == null || g_mItemTypeIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mItemTypeIndex.GetValue(type, index) || index < 0 || index >= g_aItemTypes.Length)
    {
        return false;
    }

    StoreItemTypeDefinition definition;
    g_aItemTypes.GetArray(index, definition, sizeof(StoreItemTypeDefinition));
    if (definition.is_builtin && !allowBuiltin)
    {
        return false;
    }

    g_aItemTypes.Erase(index);
    g_mItemTypeIndex.Remove(type);

    for (int i = index; i < g_aItemTypes.Length; i++)
    {
        g_aItemTypes.GetArray(i, definition, sizeof(StoreItemTypeDefinition));
        g_mItemTypeIndex.SetValue(definition.type, i);
    }

    return true;
}

bool FindItemTypeDefinition(const char[] type, StoreItemTypeDefinition definition)
{
    if (type[0] == '\0' || g_aItemTypes == null || g_mItemTypeIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mItemTypeIndex.GetValue(type, index) || index < 0 || index >= g_aItemTypes.Length)
    {
        return false;
    }

    g_aItemTypes.GetArray(index, definition, sizeof(StoreItemTypeDefinition));
    return true;
}

void RegisterBuiltinItemTypes()
{
    RegisterItemTypeInternal("skin", "skins", true, true, true);
    RegisterItemTypeInternal("tag", "chat", true, true, true);
    RegisterItemTypeInternal("namecolor", "chat", true, true, true);
    RegisterItemTypeInternal("chatcolor", "chat", true, true, true);
}

void RegisterBuiltinStatKeys()
{
    if (g_mAllowedStats == null)
    {
        g_mAllowedStats = new StringMap();
    }

    static const char builtinStats[][] =
    {
        "credits_earned",
        "credits_spent",
        "purchases_total",
        "sales_total",
        "gifts_sent",
        "gifts_received",
        "trades_completed",
        "daily_claims",
        "daily_best_streak",
        "blackjack_games",
        "blackjack_wins",
        "blackjack_losses",
        "blackjack_pushes",
        "blackjack_blackjacks",
        "blackjack_profit",
        "blackjack_best_streak",
        "coinflip_games",
        "coinflip_wins",
        "coinflip_losses",
        "coinflip_profit",
        "crash_rounds",
        "crash_cashouts",
        "crash_losses",
        "crash_profit",
        "roulette_games",
        "roulette_wins",
        "roulette_losses",
        "roulette_profit"
    };

    for (int i = 0; i < sizeof(builtinStats); i++)
    {
        g_mAllowedStats.SetValue(builtinStats[i], 1);
    }
}

bool RegisterQuestInternal(const char[] questId, const char[] title, int goal, int rewardCredits)
{
    if (questId[0] == '\0' || goal <= 0)
    {
        return false;
    }

    if (g_aQuestDefinitions == null)
    {
        g_aQuestDefinitions = new ArrayList(sizeof(StoreQuestDefinition));
    }

    if (g_mQuestIndex == null)
    {
        g_mQuestIndex = new StringMap();
    }

    StoreQuestDefinition definition;
    strcopy(definition.id, sizeof(definition.id), questId);
    strcopy(definition.title, sizeof(definition.title), title);
    strcopy(definition.category, sizeof(definition.category), "Quest Category General");
    definition.description[0] = '\0';
    definition.reward_item[0] = '\0';
    definition.reward_item_equip = 0;
    definition.goal = goal;
    definition.reward_credits = rewardCredits;

    int index;
    if (g_mQuestIndex.GetValue(questId, index) && index >= 0 && index < g_aQuestDefinitions.Length)
    {
        g_aQuestDefinitions.SetArray(index, definition, sizeof(StoreQuestDefinition));
        return true;
    }

    index = g_aQuestDefinitions.PushArray(definition, sizeof(StoreQuestDefinition));
    if (index < 0)
    {
        return false;
    }

    g_mQuestIndex.SetValue(questId, index);
    return true;
}

void SanitizeFilenameComponent(const char[] input, char[] output, int maxlen)
{
    int len = strlen(input);
    int out = 0;

    for (int i = 0; i < len && out < maxlen - 1; i++)
    {
        int c = input[i];
        if ((c >= 'a' && c <= 'z')
            || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9')
            || c == '_'
            || c == '-'
            || c == '.')
        {
            output[out++] = c;
        }
        else
        {
            output[out++] = '_';
        }
    }

    if (out == 0 && maxlen > 1)
    {
        output[out++] = '0';
    }

    output[out] = '\0';
}

bool RegisterQuestDefinitionInternal(StoreQuestDefinition definition)
{
    if (definition.id[0] == '\0' || definition.goal <= 0)
    {
        return false;
    }

    if (definition.category[0] == '\0')
    {
        strcopy(definition.category, sizeof(definition.category), "Quest Category General");
    }

    if (!definition.repeatable)
    {
        definition.max_completions = 1;
    }
    else if (definition.max_completions == 0)
    {
        definition.max_completions = -1;
    }

    if (g_aQuestDefinitions == null)
    {
        g_aQuestDefinitions = new ArrayList(sizeof(StoreQuestDefinition));
    }

    if (g_mQuestIndex == null)
    {
        g_mQuestIndex = new StringMap();
    }

    int index;
    if (g_mQuestIndex.GetValue(definition.id, index) && index >= 0 && index < g_aQuestDefinitions.Length)
    {
        g_aQuestDefinitions.SetArray(index, definition, sizeof(StoreQuestDefinition));
        return true;
    }

    index = g_aQuestDefinitions.PushArray(definition, sizeof(StoreQuestDefinition));
    if (index < 0)
    {
        return false;
    }

    g_mQuestIndex.SetValue(definition.id, index);
    return true;
}

void ClearLoadedQuestConfigEntries()
{
    if (g_aQuestConfigIds == null || g_aQuestConfigBaseDefinitions == null || g_aQuestConfigBaseValid == null)
    {
        return;
    }

    char questId[64];
    StoreQuestDefinition baseDefinition;
    for (int i = g_aQuestConfigIds.Length - 1; i >= 0; i--)
    {
        g_aQuestConfigIds.GetString(i, questId, sizeof(questId));
        bool hadBase = view_as<bool>(g_aQuestConfigBaseValid.Get(i));
        if (hadBase)
        {
            g_aQuestConfigBaseDefinitions.GetArray(i, baseDefinition, sizeof(StoreQuestDefinition));
            RegisterQuestDefinitionInternal(baseDefinition);
        }
        else
        {
            UnregisterQuestInternal(questId);
        }
    }

    g_aQuestConfigIds.Clear();
    g_aQuestConfigBaseDefinitions.Clear();
    g_aQuestConfigBaseValid.Clear();
}

void LoadQuestConfig()
{
    ClearLoadedQuestConfigEntries();

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), STORE_QUESTS_CONFIG);
    if (!FileExists(path))
    {
        return;
    }

    KeyValues kv = new KeyValues("Quests");
    if (!kv.ImportFromFile(path))
    {
        LogError("%s Failed to load quest config: %s", STORE_LOG_PREFIX, path);
        delete kv;
        return;
    }

    if (!kv.GotoFirstSubKey())
    {
        delete kv;
        return;
    }

    do
    {
        StoreQuestDefinition definition;
        kv.GetSectionName(definition.id, sizeof(definition.id));
        kv.GetString("title", definition.title, sizeof(definition.title), definition.id);
        kv.GetString("category", definition.category, sizeof(definition.category), "Quest Category General");
        kv.GetString("description", definition.description, sizeof(definition.description), "");
        kv.GetString("reward_item", definition.reward_item, sizeof(definition.reward_item), "");
        definition.reward_item_equip = kv.GetNum("reward_item_equip", 0);
        definition.repeatable = kv.GetNum("repeatable", 0);
        definition.max_completions = kv.GetNum("max_completions", definition.repeatable ? -1 : 1);
        kv.GetString("requires_quest", definition.requires_quest, sizeof(definition.requires_quest), "");
        definition.starts_at = kv.GetNum("starts_at", 0);
        definition.ends_at = kv.GetNum("ends_at", 0);

        int enabled = kv.GetNum("enabled", 1);
        definition.goal = kv.GetNum("goal", 0);
        definition.reward_credits = kv.GetNum("reward_credits", 0);

        if (!enabled)
        {
            continue;
        }

        if (definition.id[0] == '\0' || definition.goal <= 0)
        {
            LogError("%s Invalid quest in %s. id='%s' goal=%d", STORE_LOG_PREFIX, path, definition.id, definition.goal);
            continue;
        }

        StoreQuestDefinition previousDefinition;
        previousDefinition.id[0] = '\0';
        previousDefinition.title[0] = '\0';
        previousDefinition.category[0] = '\0';
        previousDefinition.description[0] = '\0';
        previousDefinition.reward_item[0] = '\0';
        previousDefinition.reward_item_equip = 0;
        previousDefinition.goal = 0;
        previousDefinition.reward_credits = 0;
        previousDefinition.repeatable = 0;
        previousDefinition.max_completions = 1;
        previousDefinition.requires_quest[0] = '\0';
        previousDefinition.starts_at = 0;
        previousDefinition.ends_at = 0;
        bool hadPrevious = FindQuestDefinition(definition.id, previousDefinition);

        if (!RegisterQuestDefinitionInternal(definition))
        {
            LogError("%s Failed to register quest '%s' from %s", STORE_LOG_PREFIX, definition.id, path);
            continue;
        }

        g_aQuestConfigIds.PushString(definition.id);
        g_aQuestConfigBaseValid.Push(hadPrevious ? 1 : 0);
        g_aQuestConfigBaseDefinitions.PushArray(previousDefinition, sizeof(StoreQuestDefinition));
    }
    while (kv.GotoNextKey());

    delete kv;
}

bool UnregisterQuestInternal(const char[] questId)
{
    if (questId[0] == '\0' || g_aQuestDefinitions == null || g_mQuestIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mQuestIndex.GetValue(questId, index) || index < 0 || index >= g_aQuestDefinitions.Length)
    {
        return false;
    }

    g_aQuestDefinitions.Erase(index);
    g_mQuestIndex.Remove(questId);

    StoreQuestDefinition definition;
    for (int i = index; i < g_aQuestDefinitions.Length; i++)
    {
        g_aQuestDefinitions.GetArray(i, definition, sizeof(StoreQuestDefinition));
        g_mQuestIndex.SetValue(definition.id, i);
    }

    return true;
}

bool FindQuestDefinition(const char[] questId, StoreQuestDefinition definition)
{
    if (questId[0] == '\0' || g_aQuestDefinitions == null || g_mQuestIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mQuestIndex.GetValue(questId, index) || index < 0 || index >= g_aQuestDefinitions.Length)
    {
        return false;
    }

    g_aQuestDefinitions.GetArray(index, definition, sizeof(StoreQuestDefinition));
    return true;
}

void GetItemCategory(const StoreItem item, char[] buffer, int maxlen)
{
    if (item.category[0] != '\0')
    {
        strcopy(buffer, maxlen, item.category);
        return;
    }

    StoreItemTypeDefinition definition;
    if (FindItemTypeDefinition(item.type, definition) && definition.category[0] != '\0')
    {
        strcopy(buffer, maxlen, definition.category);
        return;
    }

    strcopy(buffer, maxlen, item.type);
}

bool IsItemTypeEquippable(const char[] type)
{
    StoreItemTypeDefinition definition;
    if (FindItemTypeDefinition(type, definition))
    {
        return view_as<bool>(definition.equippable);
    }

    return false;
}

bool IsItemTypeExclusive(const char[] type)
{
    StoreItemTypeDefinition definition;
    if (FindItemTypeDefinition(type, definition))
    {
        return view_as<bool>(definition.exclusive);
    }

    return false;
}

bool IsBuiltinChatCosmeticType(const char[] type)
{
    return StrEqual(type, "tag") || StrEqual(type, "namecolor") || StrEqual(type, "chatcolor");
}

void RebuildMenuSectionIndex()
{
    if (g_mMenuSectionIndex == null)
    {
        g_mMenuSectionIndex = new StringMap();
    }
    else
    {
        g_mMenuSectionIndex.Clear();
    }

    if (g_aMenuSections == null)
    {
        return;
    }

    StoreMenuSection section;
    for (int i = 0; i < g_aMenuSections.Length; i++)
    {
        g_aMenuSections.GetArray(i, section, sizeof(StoreMenuSection));
        g_mMenuSectionIndex.SetValue(section.id, i);
    }
}

bool RegisterMenuSectionEntry(const char[] id, const char[] title, const char[] command, int sortOrder = 0)
{
    if (id[0] == '\0' || title[0] == '\0' || command[0] == '\0')
    {
        return false;
    }

    if (g_aMenuSections == null)
    {
        g_aMenuSections = new ArrayList(sizeof(StoreMenuSection));
    }

    if (g_mMenuSectionIndex == null)
    {
        g_mMenuSectionIndex = new StringMap();
    }

    StoreMenuSection section;
    strcopy(section.id, sizeof(section.id), id);
    strcopy(section.title, sizeof(section.title), title);
    strcopy(section.command, sizeof(section.command), command);
    section.sort_order = sortOrder;

    int index;
    if (g_mMenuSectionIndex.GetValue(id, index) && index >= 0 && index < g_aMenuSections.Length)
    {
        g_aMenuSections.SetArray(index, section, sizeof(StoreMenuSection));
        return true;
    }

    index = g_aMenuSections.PushArray(section, sizeof(StoreMenuSection));
    if (index < 0)
    {
        return false;
    }

    g_mMenuSectionIndex.SetValue(id, index);
    return true;
}

bool UnregisterMenuSectionEntry(const char[] id)
{
    if (id[0] == '\0' || g_aMenuSections == null || g_mMenuSectionIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mMenuSectionIndex.GetValue(id, index) || index < 0 || index >= g_aMenuSections.Length)
    {
        return false;
    }

    g_aMenuSections.Erase(index);
    RebuildMenuSectionIndex();
    return true;
}

void RebuildLeaderboardIndex()
{
    if (g_mLeaderboardIndex == null)
    {
        g_mLeaderboardIndex = new StringMap();
    }
    else
    {
        g_mLeaderboardIndex.Clear();
    }

    if (g_aLeaderboards == null)
    {
        return;
    }

    StoreLeaderboardDefinition definition;
    for (int i = 0; i < g_aLeaderboards.Length; i++)
    {
        g_aLeaderboards.GetArray(i, definition, sizeof(StoreLeaderboardDefinition));
        g_mLeaderboardIndex.SetValue(definition.id, i);
    }
}

bool RegisterLeaderboardInternal(const char[] id, const char[] title, const char[] statKey, const char[] entryPhrase = "Top Profit Entry", int sortOrder = 0)
{
    if (id[0] == '\0' || title[0] == '\0' || statKey[0] == '\0' || !IsSafeStatKey(statKey))
    {
        return false;
    }

    if (g_aLeaderboards == null)
    {
        g_aLeaderboards = new ArrayList(sizeof(StoreLeaderboardDefinition));
    }

    if (g_mLeaderboardIndex == null)
    {
        g_mLeaderboardIndex = new StringMap();
    }

    StoreLeaderboardDefinition definition;
    strcopy(definition.id, sizeof(definition.id), id);
    strcopy(definition.title, sizeof(definition.title), title);
    strcopy(definition.stat_key, sizeof(definition.stat_key), statKey);
    if (entryPhrase[0] != '\0' && TranslationPhraseExists(entryPhrase))
    {
        strcopy(definition.entry_phrase, sizeof(definition.entry_phrase), entryPhrase);
    }
    else
    {
        strcopy(definition.entry_phrase, sizeof(definition.entry_phrase), "Top Profit Entry");
    }
    definition.sort_order = sortOrder;

    int index;
    if (g_mLeaderboardIndex.GetValue(id, index) && index >= 0 && index < g_aLeaderboards.Length)
    {
        g_aLeaderboards.SetArray(index, definition, sizeof(StoreLeaderboardDefinition));
        return true;
    }

    index = g_aLeaderboards.PushArray(definition, sizeof(StoreLeaderboardDefinition));
    if (index < 0)
    {
        return false;
    }

    g_mLeaderboardIndex.SetValue(id, index);
    if (g_mAllowedStats != null)
    {
        g_mAllowedStats.SetValue(statKey, 1);
    }
    return true;
}

bool UnregisterLeaderboardInternal(const char[] id)
{
    if (id[0] == '\0' || g_aLeaderboards == null || g_mLeaderboardIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mLeaderboardIndex.GetValue(id, index) || index < 0 || index >= g_aLeaderboards.Length)
    {
        return false;
    }

    g_aLeaderboards.Erase(index);
    RebuildLeaderboardIndex();
    return true;
}

void InvalidateItemCache()
{
    g_bItemCacheReady = false;

    if (g_mItemIndex != null)
    {
        g_mItemIndex.Clear();
    }

    if (g_mItemMetadata != null)
    {
        g_mItemMetadata.Clear();
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
    if (itemId[0] == '\0' || g_aItems == null)
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

bool GetEquippedItemByType(int client, const char[] type, char[] itemId, int maxlen)
{
    itemId[0] = '\0';

    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null || type[0] == '\0')
    {
        return false;
    }

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

        if (StrEqual(item.type, type))
        {
            strcopy(itemId, maxlen, item.id);
            return true;
        }
    }

    return false;
}

int CountEquippedItems(int client)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        return 0;
    }

    int count = 0;
    InventoryItem inv;
    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (inv.is_equipped)
        {
            count++;
        }
    }

    return count;
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

int GetItemSellPrice(const StoreItem item)
{
    if (item.sale_price >= 0)
    {
        return item.sale_price;
    }

    if (item.sell_percent_override >= 0)
    {
        int sellPercent = item.sell_percent_override;
        if (sellPercent < 0)
        {
            sellPercent = 0;
        }
        else if (sellPercent > 100)
        {
            sellPercent = 100;
        }

        return (item.price * sellPercent) / 100;
    }

    return GetSellPrice(item.price);
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

void AddMenuItemText(Menu menu, const char[] info, const char[] text, int style = ITEMDRAW_DEFAULT)
{
    menu.AddItem(info, text, style);
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
    CPrintToChat(client, "%s", finalMsg);
}

void ReplyStorePhrase(int client, const char[] format, any ...)
{
    char translated[384], highlighted[448];
    SetGlobalTransTarget(client);
    VFormat(translated, sizeof(translated), format, 3);
    ReplaceColorTags(translated, sizeof(translated));
    HighlightChatCommands(translated, highlighted, sizeof(highlighted));
    CReplyToCommand(client, " %s", highlighted);
}

void ReplyStoreText(int client, const char[] text)
{
    if (client <= 0 || client > MaxClients)
    {
        ReplyToCommand(client, "%s", text);
        return;
    }

    char prefix[64], finalMsg[640];
    GetStorePrefix(client, prefix, sizeof(prefix));
    Format(finalMsg, sizeof(finalMsg), " %s %s", prefix, text);
    CReplyToCommand(client, "%s", finalMsg);
}

bool LoadPlayerStatSnapshot(int client, StringMap stats)
{
    if (stats == null || g_DB == null || !IsValidClientConnected(client))
    {
        return false;
    }

    char steamid[32], safeSteamId[64], query[192];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    Format(query, sizeof(query),
        "SELECT stat_key, stat_value FROM store_player_stats WHERE steamid = '%s'",
        safeSteamId);

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("LoadPlayerStatSnapshot", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }

    char statKey[64];
    while (results.FetchRow())
    {
        results.FetchString(0, statKey, sizeof(statKey));
        stats.SetValue(statKey, results.FetchInt(1));
    }

    delete results;
    SQL_UnlockDatabase(g_DB);
    return true;
}

int GetSnapshotStatValue(StringMap stats, const char[] statKey)
{
    if (stats == null || statKey[0] == '\0')
    {
        return 0;
    }

    int value = 0;
    stats.GetValue(statKey, value);
    return value;
}

bool LoadQuestProgressSnapshot(int client, ArrayList rows, StringMap indexMap, int &completedCount)
{
    completedCount = 0;

    if (rows == null || indexMap == null || g_DB == null || !IsValidClientConnected(client))
    {
        return false;
    }

    char steamid[32], safeSteamId[64], query[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    Format(query, sizeof(query),
        "SELECT q.quest_id, q.progress, q.completed_at, q.rewarded_at, COALESCE(c.completion_count, 0) "
        ... "FROM store_player_quests q "
        ... "LEFT JOIN store_player_quest_counts c ON q.steamid = c.steamid AND q.quest_id = c.quest_id "
        ... "WHERE q.steamid = '%s'",
        safeSteamId);

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("LoadQuestProgressSnapshot", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }

    StoreQuestProgressSnapshot state;
    while (results.FetchRow())
    {
        results.FetchString(0, state.quest_id, sizeof(state.quest_id));
        state.progress = results.FetchInt(1);
        state.completed_at = results.FetchInt(2);
        state.rewarded_at = results.FetchInt(3);
        state.completion_count = results.FetchInt(4);

        int rowIndex = rows.PushArray(state, sizeof(StoreQuestProgressSnapshot));
        if (rowIndex >= 0)
        {
            indexMap.SetValue(state.quest_id, rowIndex);
        }

        if (state.completion_count > 0)
        {
            completedCount += state.completion_count;
        }
        else if (state.rewarded_at > 0)
        {
            completedCount++;
        }
    }

    delete results;
    SQL_UnlockDatabase(g_DB);
    return true;
}

void GetQuestSnapshotState(ArrayList rows, StringMap indexMap, const char[] questId, int &progress, int &completedAt, int &rewardedAt, int &completionCount)
{
    progress = 0;
    completedAt = 0;
    rewardedAt = 0;
    completionCount = 0;

    if (rows == null || indexMap == null || questId[0] == '\0')
    {
        return;
    }

    int rowIndex = -1;
    if (!indexMap.GetValue(questId, rowIndex) || rowIndex < 0 || rowIndex >= rows.Length)
    {
        return;
    }

    StoreQuestProgressSnapshot state;
    rows.GetArray(rowIndex, state, sizeof(StoreQuestProgressSnapshot));
    progress = state.progress;
    completedAt = state.completed_at;
    rewardedAt = state.rewarded_at;
    completionCount = state.completion_count;
}

bool HasQuestRewardedInSnapshot(ArrayList rows, StringMap indexMap, const char[] questId)
{
    int progress = 0;
    int completedAt = 0;
    int rewardedAt = 0;
    int completionCount = 0;
    GetQuestSnapshotState(rows, indexMap, questId, progress, completedAt, rewardedAt, completionCount);
    return (rewardedAt > 0 || completionCount > 0);
}

bool BuildProfileSnapshot(int client, StoreProfileSnapshot snapshot)
{
    snapshot.credits = g_iCredits[client];
    snapshot.owned_items = (g_hInventory[client] != null) ? g_hInventory[client].Length : 0;
    snapshot.equipped_items = CountEquippedItems(client);

    StringMap stats = new StringMap();
    LoadPlayerStatSnapshot(client, stats);

    ArrayList questRows = new ArrayList(sizeof(StoreQuestProgressSnapshot));
    StringMap questIndex = new StringMap();
    LoadQuestProgressSnapshot(client, questRows, questIndex, snapshot.quests_completed);

    snapshot.credits_earned = GetSnapshotStatValue(stats, "credits_earned");
    snapshot.credits_spent = GetSnapshotStatValue(stats, "credits_spent");
    snapshot.purchases_total = GetSnapshotStatValue(stats, "purchases_total");
    snapshot.sales_total = GetSnapshotStatValue(stats, "sales_total");
    snapshot.gifts_sent = GetSnapshotStatValue(stats, "gifts_sent");
    snapshot.gifts_received = GetSnapshotStatValue(stats, "gifts_received");
    snapshot.trades_completed = GetSnapshotStatValue(stats, "trades_completed");
    snapshot.daily_best_streak = GetSnapshotStatValue(stats, "daily_best_streak");
    snapshot.blackjack_games = GetSnapshotStatValue(stats, "blackjack_games");
    snapshot.blackjack_profit = GetSnapshotStatValue(stats, "blackjack_profit");
    snapshot.coinflip_games = GetSnapshotStatValue(stats, "coinflip_games");
    snapshot.coinflip_profit = GetSnapshotStatValue(stats, "coinflip_profit");
    snapshot.crash_rounds = GetSnapshotStatValue(stats, "crash_rounds");
    snapshot.crash_profit = GetSnapshotStatValue(stats, "crash_profit");
    snapshot.roulette_games = GetSnapshotStatValue(stats, "roulette_games");
    snapshot.roulette_profit = GetSnapshotStatValue(stats, "roulette_profit");
    snapshot.total_casino_activity = snapshot.blackjack_games + snapshot.coinflip_games + snapshot.crash_rounds + snapshot.roulette_games;
    snapshot.total_casino_profit = snapshot.blackjack_profit + snapshot.coinflip_profit + snapshot.crash_profit + snapshot.roulette_profit;

    delete stats;
    delete questRows;
    delete questIndex;
    return true;
}

void FormatQuestTitle(int client, const StoreQuestDefinition definition, char[] buffer, int maxlen)
{
    if (definition.title[0] == '\0')
    {
        buffer[0] = '\0';
        return;
    }

    if (TranslationPhraseExists(definition.title))
    {
        Format(buffer, maxlen, "%T", definition.title, client);
        return;
    }

    strcopy(buffer, maxlen, definition.title);
}

void FormatQuestText(int client, const char[] value, char[] buffer, int maxlen)
{
    if (value[0] == '\0')
    {
        buffer[0] = '\0';
        return;
    }

    if (TranslationPhraseExists(value))
    {
        Format(buffer, maxlen, "%T", value, client);
        return;
    }

    strcopy(buffer, maxlen, value);
}

void FormatQuestRewardText(int client, const StoreQuestDefinition definition, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    char creditsText[64];
    char itemText[96];
    creditsText[0] = '\0';
    itemText[0] = '\0';

    if (definition.reward_credits > 0)
    {
        FormatCreditsAmount(client, definition.reward_credits, creditsText, sizeof(creditsText));
    }

    if (definition.reward_item[0] != '\0')
    {
        StoreItem rewardItem;
        if (FindStoreItemById(definition.reward_item, rewardItem))
        {
            strcopy(itemText, sizeof(itemText), rewardItem.name);
        }
        else
        {
            strcopy(itemText, sizeof(itemText), definition.reward_item);
        }
    }

    if (creditsText[0] != '\0' && itemText[0] != '\0')
    {
        Format(buffer, maxlen, "%s + %s", creditsText, itemText);
    }
    else if (creditsText[0] != '\0')
    {
        strcopy(buffer, maxlen, creditsText);
    }
    else if (itemText[0] != '\0')
    {
        strcopy(buffer, maxlen, itemText);
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

    if (inCommand)
    {
        AppendLiteral(output, maxlen, outPos, commandEnd);
    }

    output[outPos] = '\0';
}

void SanitizeChatRenderInput(char[] buffer, int maxlen)
{
    ReplaceString(buffer, maxlen, "{", "(");
    ReplaceString(buffer, maxlen, "}", ")");
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

Action ForwardPurchasePre(int client, const char[] itemId, bool equipAfterPurchase)
{
    Action result = Plugin_Continue;

    if (g_hFwdPurchasePre == null)
    {
        return result;
    }

    Call_StartForward(g_hFwdPurchasePre);
    Call_PushCell(client);
    Call_PushString(itemId);
    Call_PushCell(equipAfterPurchase);
    Call_Finish(result);
    return result;
}

void ForwardPurchasePost(int client, const char[] itemId, int price, bool equippedAfterPurchase)
{
    if (g_hFwdPurchasePost == null)
    {
        return;
    }

    Call_StartForward(g_hFwdPurchasePost);
    Call_PushCell(client);
    Call_PushString(itemId);
    Call_PushCell(price);
    Call_PushCell(equippedAfterPurchase);
    Call_Finish();
}

Action ForwardEquipPre(int client, const char[] itemId, bool equip)
{
    Action result = Plugin_Continue;

    if (g_hFwdEquipPre == null)
    {
        return result;
    }

    Call_StartForward(g_hFwdEquipPre);
    Call_PushCell(client);
    Call_PushString(itemId);
    Call_PushCell(equip);
    Call_Finish(result);
    return result;
}

void ForwardEquipPost(int client, const char[] itemId, bool equip)
{
    if (g_hFwdEquipPost == null)
    {
        return;
    }

    Call_StartForward(g_hFwdEquipPost);
    Call_PushCell(client);
    Call_PushString(itemId);
    Call_PushCell(equip);
    Call_Finish();
}

Action ForwardTradePre(int sender, int target, const char[] senderItemId, const char[] targetItemId)
{
    Action result = Plugin_Continue;

    if (g_hFwdTradePre == null)
    {
        return result;
    }

    Call_StartForward(g_hFwdTradePre);
    Call_PushCell(sender);
    Call_PushCell(target);
    Call_PushString(senderItemId);
    Call_PushString(targetItemId);
    Call_Finish(result);
    return result;
}

void ForwardTradePost(int sender, int target, const char[] senderItemId, const char[] targetItemId)
{
    if (g_hFwdTradePost == null)
    {
        return;
    }

    Call_StartForward(g_hFwdTradePost);
    Call_PushCell(sender);
    Call_PushCell(target);
    Call_PushString(senderItemId);
    Call_PushString(targetItemId);
    Call_Finish();
}

void ForwardCreditsChanged(int client, int delta, const char[] reason)
{
    if (g_hFwdCreditsChanged == null || client < 1 || client > MaxClients)
    {
        return;
    }

    Call_StartForward(g_hFwdCreditsChanged);
    Call_PushCell(client);
    Call_PushCell(delta);
    Call_PushCell(g_iCredits[client]);
    Call_PushString(reason);
    Call_Finish();
}

void ForwardInventoryChanged(int client, const char[] itemId, const char[] operation)
{
    if (g_hFwdInventoryChanged == null)
    {
        return;
    }

    Call_StartForward(g_hFwdInventoryChanged);
    Call_PushCell(client);
    Call_PushString(itemId);
    Call_PushString(operation);
    Call_Finish();
}

void ForwardQuestCompleted(int client, const char[] questId, int rewardCredits)
{
    if (g_hFwdQuestCompleted == null)
    {
        return;
    }

    Call_StartForward(g_hFwdQuestCompleted);
    Call_PushCell(client);
    Call_PushString(questId);
    Call_PushCell(rewardCredits);
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
    ForwardInventoryChanged(client, item.id, "give");

    if (equip)
    {
        SetItemEquipped(client, item.id, true, true, false);
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

    CancelMarketplaceListingsForClientItem(client, itemId);

    g_hInventory[client].Erase(index);
    InventoryOwnedSet(client, itemId, false);
    MarkInventoryChanged(client);
    ForwardInventoryChanged(client, itemId, "remove");

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
    CreateConVar("store_chat_extended_colors", "1", "Legacy compatibility cvar. Umbrella Store now renders chat through the Multi-Colors backend.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gCvarMarketEnabled = CreateConVar("umbrella_store_market_enabled", "1", "Enable or disable the Umbrella Store marketplace.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gCvarMarketMinPrice = CreateConVar("umbrella_store_market_min_price", "50", "Minimum price for marketplace listings.", FCVAR_NONE, true, 1.0);
    gCvarMarketMaxPrice = CreateConVar("umbrella_store_market_max_price", "1000000", "Maximum price for marketplace listings. 0 disables the cap.", FCVAR_NONE, true, 0.0);
    gCvarMarketListingHours = CreateConVar("umbrella_store_market_listing_hours", "72", "Hours before a marketplace listing expires.", FCVAR_NONE, true, 1.0, true, 720.0);
    gCvarMarketFeePercent = CreateConVar("umbrella_store_market_fee_percent", "5", "Marketplace fee percentage applied to completed sales.", FCVAR_NONE, true, 0.0, true, 100.0);
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

void LogCreditLedgerBySteamId(const char[] steamid, int balanceAfter, int amount, const char[] reason)
{
    if (amount == 0 || g_DB == null || steamid[0] == '\0' || reason[0] == '\0')
    {
        return;
    }

    char safeSteamId[64], safeReason[128], query[512];
    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(reason, safeReason, sizeof(safeReason));

    Format(query, sizeof(query),
        "INSERT INTO store_credits_ledger (steamid, amount, reason, balance_after, created_at) VALUES ('%s', %d, '%s', %d, %d)",
        safeSteamId, amount, safeReason, balanceAfter, GetTime());

    g_DB.Query(DummyCallback, query);
}

void LogCreditLedger(int client, int amount, const char[] reason)
{
    if (amount == 0 || g_DB == null || !IsValidClientConnected(client) || reason[0] == '\0')
    {
        return;
    }

    char steamid[32];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return;
    }

    LogCreditLedgerBySteamId(steamid, g_iCredits[client], amount, reason);
}

bool IsSafeStatKey(const char[] statKey)
{
    if (statKey[0] == '\0')
    {
        return false;
    }

    int length = strlen(statKey);
    for (int i = 0; i < length; i++)
    {
        int c = statKey[i];
        if ((c >= 'a' && c <= 'z')
            || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9')
            || c == '_'
            || c == '-'
            || c == '.'
            || c == ':')
        {
            continue;
        }

        return false;
    }

    return true;
}

bool RegisterStatKeyInternal(const char[] statKey)
{
    if (!IsSafeStatKey(statKey))
    {
        return false;
    }

    if (g_mAllowedStats == null)
    {
        g_mAllowedStats = new StringMap();
    }

    g_mAllowedStats.SetValue(statKey, 1);
    return true;
}

bool TryHandleRegisteredMenuSectionSelection(int client, const char[] id)
{
    if (!IsValidHumanClient(client) || id[0] == '\0' || g_aMenuSections == null || g_mMenuSectionIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mMenuSectionIndex.GetValue(id, index) || index < 0 || index >= g_aMenuSections.Length)
    {
        return false;
    }

    StoreMenuSection section;
    g_aMenuSections.GetArray(index, section, sizeof(StoreMenuSection));
    if (section.command[0] == '\0')
    {
        return false;
    }

    FakeClientCommand(client, "%s", section.command);
    return true;
}

bool UpdatePlayerStatBySteamId(const char[] steamid, const char[] statKey, int value, bool setMax = false)
{
    if (g_DB == null || steamid[0] == '\0' || !IsSafeStatKey(statKey))
    {
        return false;
    }

    if (g_mAllowedStats != null)
    {
        g_mAllowedStats.SetValue(statKey, 1);
    }

    char safeSteamId[64], safeStatKey[128], query[768];
    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(statKey, safeStatKey, sizeof(safeStatKey));

    if (g_bIsMySQL)
    {
        if (setMax)
        {
            Format(query, sizeof(query),
                "INSERT INTO store_player_stats (steamid, stat_key, stat_value, updated_at) VALUES ('%s', '%s', %d, %d) "
                ... "ON DUPLICATE KEY UPDATE stat_value = GREATEST(stat_value, VALUES(stat_value)), updated_at = VALUES(updated_at)",
                safeSteamId, safeStatKey, value, GetTime());
        }
        else
        {
            Format(query, sizeof(query),
                "INSERT INTO store_player_stats (steamid, stat_key, stat_value, updated_at) VALUES ('%s', '%s', %d, %d) "
                ... "ON DUPLICATE KEY UPDATE stat_value = stat_value + VALUES(stat_value), updated_at = VALUES(updated_at)",
                safeSteamId, safeStatKey, value, GetTime());
        }
    }
    else
    {
        if (setMax)
        {
            Format(query, sizeof(query),
                "INSERT INTO store_player_stats (steamid, stat_key, stat_value, updated_at) VALUES ('%s', '%s', %d, %d) "
                ... "ON CONFLICT(steamid, stat_key) DO UPDATE SET stat_value = MAX(store_player_stats.stat_value, excluded.stat_value), updated_at = excluded.updated_at",
                safeSteamId, safeStatKey, value, GetTime());
        }
        else
        {
            Format(query, sizeof(query),
                "INSERT INTO store_player_stats (steamid, stat_key, stat_value, updated_at) VALUES ('%s', '%s', %d, %d) "
                ... "ON CONFLICT(steamid, stat_key) DO UPDATE SET stat_value = store_player_stats.stat_value + excluded.stat_value, updated_at = excluded.updated_at",
                safeSteamId, safeStatKey, value, GetTime());
        }
    }

    g_DB.Query(DummyCallback, query);
    return true;
}

bool UpdatePlayerStat(int client, const char[] statKey, int value, bool setMax = false)
{
    if (g_DB == null || !IsValidClientConnected(client) || !g_bIsLoaded[client] || !IsSafeStatKey(statKey))
    {
        return false;
    }

    char steamid[32];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    return UpdatePlayerStatBySteamId(steamid, statKey, value, setMax);
}

void TrackEconomyStats(int client, int delta)
{
    if (delta > 0)
    {
        UpdatePlayerStat(client, "credits_earned", delta);
    }
    else if (delta < 0)
    {
        UpdatePlayerStat(client, "credits_spent", -delta);
    }
}

void TrackEconomyStatsBySteamId(const char[] steamid, int delta)
{
    if (steamid[0] == '\0')
    {
        return;
    }

    if (delta > 0)
    {
        UpdatePlayerStatBySteamId(steamid, "credits_earned", delta);
    }
    else if (delta < 0)
    {
        UpdatePlayerStatBySteamId(steamid, "credits_spent", -delta);
    }
}

void ReportCreditsChanged(int client, int delta, const char[] reason, bool notify = false, bool persisted = false)
{
    if (!IsValidClientConnected(client))
    {
        return;
    }

    g_bCreditsDirty[client] = !persisted;

    if (delta == 0)
    {
        return;
    }

    LogCreditLedger(client, delta, reason);
    TrackEconomyStats(client, delta);

    if (notify && delta > 0)
    {
        QueueCreditNotification(client, delta, reason);
    }

    if (delta > 0)
    {
        ForwardCreditsGiven(client, delta, reason);
    }

    ForwardCreditsChanged(client, delta, reason);
}

void AddCreditsEx(int client, int amount, const char[] reason, bool notify = true)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || amount <= 0)
    {
        return;
    }

    g_iCredits[client] += amount;
    ReportCreditsChanged(client, amount, reason, notify, false);
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
        details[0] = '\0';
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

    if (HasActiveMarketplaceListing(sender, itemId))
    {
        if (notify)
        {
            PrintStorePhrase(sender, "%T", "Market Item Listed Already", sender);
        }
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
    ForwardInventoryChanged(sender, itemId, "transfer_out");
    ForwardInventoryChanged(target, itemId, "transfer_in");

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

    if (ForwardTradePre(sender, target, senderItemId, targetItemId) >= Plugin_Handled)
    {
        return false;
    }

    if (HasActiveMarketplaceListing(sender, senderItemId) || HasActiveMarketplaceListing(target, targetItemId))
    {
        PrintStorePhrase(sender, "%T", "Market Item Listed Already", sender);
        PrintStorePhrase(target, "%T", "Market Item Listed Already", target);
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
    ForwardInventoryChanged(sender, senderItemId, "trade_out");
    ForwardInventoryChanged(sender, targetItemId, "trade_in");
    ForwardInventoryChanged(target, targetItemId, "trade_out");
    ForwardInventoryChanged(target, senderItemId, "trade_in");
    ForwardTradePost(sender, target, senderItemId, targetItemId);
    ForwardTradeCompleted(sender, target, senderItemId, targetItemId);
    UpdatePlayerStat(sender, "trades_completed", 1);
    UpdatePlayerStat(target, "trades_completed", 1);

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
    if (!IsItemActiveForNow(item))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item No Longer Exists", client);
        }
        return false;
    }

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

    if (item.requires_item[0] != '\0' && !PlayerOwnsItem(client, item.requires_item))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item Not Found", client);
        }
        return false;
    }

    return true;
}

bool IsItemActiveForNow(const StoreItem item)
{
    int now = GetTime();

    if (item.starts_at > 0 && now < item.starts_at)
    {
        return false;
    }

    if (item.ends_at > 0 && now > item.ends_at)
    {
        return false;
    }

    return true;
}

void SetReason(char[] reason, int maxlen, const char[] value)
{
    if (maxlen <= 0)
    {
        return;
    }

    strcopy(reason, maxlen, value);
}

bool CanPurchaseItemEx(int client, const char[] itemId, char[] reason, int maxlen)
{
    SetReason(reason, maxlen, "");

    if (!IsValidHumanClient(client))
    {
        SetReason(reason, maxlen, "invalid_client");
        return false;
    }

    if (!EnsureStoreEnabledForClient(client, false))
    {
        SetReason(reason, maxlen, "store_disabled");
        return false;
    }

    if (!g_bIsLoaded[client] || g_hInventory[client] == null || g_DB == null)
    {
        SetReason(reason, maxlen, "client_not_loaded");
        return false;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        SetReason(reason, maxlen, "item_not_found");
        return false;
    }

    if (item.hidden)
    {
        SetReason(reason, maxlen, "item_hidden");
        return false;
    }

    if (!IsItemActiveForNow(item))
    {
        SetReason(reason, maxlen, "item_unavailable");
        return false;
    }

    if (!HasAccess(client, item.flag))
    {
        SetReason(reason, maxlen, "no_access");
        return false;
    }

    if (PlayerOwnsItem(client, item.id))
    {
        SetReason(reason, maxlen, "already_owned");
        return false;
    }

    if (item.requires_item[0] != '\0' && !PlayerOwnsItem(client, item.requires_item))
    {
        SetReason(reason, maxlen, "requires_item");
        return false;
    }

    if (g_iCredits[client] < item.price)
    {
        SetReason(reason, maxlen, "not_enough_credits");
        return false;
    }

    SetReason(reason, maxlen, "ok");
    return true;
}

bool CanEquipItemEx(int client, const char[] itemId, char[] reason, int maxlen, bool respectCooldown = false)
{
    SetReason(reason, maxlen, "");

    if (!IsValidHumanClient(client))
    {
        SetReason(reason, maxlen, "invalid_client");
        return false;
    }

    if (!EnsureStoreEnabledForClient(client, false))
    {
        SetReason(reason, maxlen, "store_disabled");
        return false;
    }

    if (!g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        SetReason(reason, maxlen, "client_not_loaded");
        return false;
    }

    if (respectCooldown)
    {
        float cooldown = (gCvarEquipCooldown != null) ? gCvarEquipCooldown.FloatValue : 0.0;
        if (cooldown > 0.0 && GetGameTime() < g_fNextEquipTime[client])
        {
            SetReason(reason, maxlen, "equip_cooldown");
            return false;
        }
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        SetReason(reason, maxlen, "item_not_found");
        return false;
    }

    if (!PlayerOwnsItem(client, item.id))
    {
        SetReason(reason, maxlen, "item_not_owned");
        return false;
    }

    if (!CanPlayerUseItem(client, item, false))
    {
        SetReason(reason, maxlen, "item_not_usable");
        return false;
    }

    if (!IsItemTypeEquippable(item.type))
    {
        SetReason(reason, maxlen, "type_not_equippable");
        return false;
    }

    if (StrEqual(item.type, "skin") && !ArePlayerSkinsEnabled())
    {
        SetReason(reason, maxlen, "player_skins_disabled");
        return false;
    }

    SetReason(reason, maxlen, "ok");
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
void ReplaceColorTags(char[] buffer, int maxlen)
{
    ReplaceString(buffer, maxlen, "{DEFAULT}", "{default}");
    ReplaceString(buffer, maxlen, "{default}", "{default}");
    ReplaceString(buffer, maxlen, "{TEAM}", "{teamcolor}");
    ReplaceString(buffer, maxlen, "{team}", "{teamcolor}");
    ReplaceString(buffer, maxlen, "{TEAMCOLOR}", "{teamcolor}");
    ReplaceString(buffer, maxlen, "{teamcolor}", "{teamcolor}");
    ReplaceString(buffer, maxlen, "{GREEN}", "{green}");
    ReplaceString(buffer, maxlen, "{green}", "{green}");
    ReplaceString(buffer, maxlen, "{RED}", "{red}");
    ReplaceString(buffer, maxlen, "{red}", "{red}");
    ReplaceString(buffer, maxlen, "{LIME}", "{lime}");
    ReplaceString(buffer, maxlen, "{lime}", "{lime}");
    ReplaceString(buffer, maxlen, "{LIGHTGREEN}", "{lightgreen}");
    ReplaceString(buffer, maxlen, "{lightgreen}", "{lightgreen}");
    ReplaceString(buffer, maxlen, "{LIGHTRED}", "{lightred}");
    ReplaceString(buffer, maxlen, "{lightred}", "{lightred}");
    ReplaceString(buffer, maxlen, "{GRAY}", "{grey}");
    ReplaceString(buffer, maxlen, "{gray}", "{grey}");
    ReplaceString(buffer, maxlen, "{GREY}", "{grey}");
    ReplaceString(buffer, maxlen, "{grey}", "{grey}");
    ReplaceString(buffer, maxlen, "{YELLOW}", "{yellow}");
    ReplaceString(buffer, maxlen, "{yellow}", "{yellow}");
    ReplaceString(buffer, maxlen, "{LIGHTBLUE}", "{lightblue}");
    ReplaceString(buffer, maxlen, "{lightblue}", "{lightblue}");
    ReplaceString(buffer, maxlen, "{BLUE}", "{blue}");
    ReplaceString(buffer, maxlen, "{blue}", "{blue}");
    ReplaceString(buffer, maxlen, "{PURPLE}", "{purple}");
    ReplaceString(buffer, maxlen, "{purple}", "{purple}");
    ReplaceString(buffer, maxlen, "{ORCHID}", "{orchid}");
    ReplaceString(buffer, maxlen, "{orchid}", "{orchid}");
    ReplaceString(buffer, maxlen, "{PINK}", "{pink}");
    ReplaceString(buffer, maxlen, "{pink}", "{pink}");

    if (GetEngineVersion() == Engine_CSGO)
    {
        ReplaceString(buffer, maxlen, "{PINK}", "{orchid}");
        ReplaceString(buffer, maxlen, "{pink}", "{orchid}");
        ReplaceString(buffer, maxlen, "{LIGHTPINK}", "{orchid}");
        ReplaceString(buffer, maxlen, "{lightpink}", "{orchid}");
        ReplaceString(buffer, maxlen, "{HOTPINK}", "{orchid}");
        ReplaceString(buffer, maxlen, "{hotpink}", "{orchid}");
        ReplaceString(buffer, maxlen, "{DEEPPINK}", "{purple}");
        ReplaceString(buffer, maxlen, "{deeppink}", "{purple}");
        ReplaceString(buffer, maxlen, "{MAGENTA}", "{purple}");
        ReplaceString(buffer, maxlen, "{magenta}", "{purple}");
        ReplaceString(buffer, maxlen, "{VIOLET}", "{purple}");
        ReplaceString(buffer, maxlen, "{violet}", "{purple}");
        ReplaceString(buffer, maxlen, "{CYAN}", "{lightblue}");
        ReplaceString(buffer, maxlen, "{cyan}", "{lightblue}");
        ReplaceString(buffer, maxlen, "{AQUA}", "{lightblue}");
        ReplaceString(buffer, maxlen, "{aqua}", "{lightblue}");
        ReplaceString(buffer, maxlen, "{TEAL}", "{bluegrey}");
        ReplaceString(buffer, maxlen, "{teal}", "{bluegrey}");
        ReplaceString(buffer, maxlen, "{WHITE}", "{default}");
        ReplaceString(buffer, maxlen, "{white}", "{default}");
    }
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
        LogError("%s Item config was not found: %s", STORE_LOG_PREFIX, path);
        return;
    }

    KeyValues kv = new KeyValues("Items");
    if (!kv.ImportFromFile(path))
    {
        LogError("%s Failed to load item config: %s", STORE_LOG_PREFIX, path);
        delete kv;
        return;
    }

    int loadedSkins = 0;
    int loadedTags = 0;
    int loadedNameColors = 0;
    int loadedChatColors = 0;
    int loadedCustom = 0;

    if (kv.GotoFirstSubKey())
    {
        StoreItem item;
        do
        {
            item.id[0] = '\0';
            item.name[0] = '\0';
            item.type[0] = '\0';
            item.category[0] = '\0';
            item.description[0] = '\0';
            item.rarity[0] = '\0';
            item.szModel[0] = '\0';
            item.szArms[0] = '\0';
            item.szValue[0] = '\0';
            item.icon[0] = '\0';
            item.metadata[0] = '\0';
            item.requires_item[0] = '\0';
            item.bundle_id[0] = '\0';
            item.flag[0] = '\0';
            item.price = 0;
            item.sale_price = -1;
            item.team = 0;
            item.sort_order = 0;
            item.starts_at = 0;
            item.ends_at = 0;
            item.sell_percent_override = -1;
            item.hidden = 0;

            kv.GetSectionName(item.id, sizeof(item.id));
            ClearItemMetadataForItem(item.id);
            if (item.id[0] == '\0')
            {
                LogError("%s Item entry with empty section name was skipped.", STORE_LOG_PREFIX);
                continue;
            }

            kv.GetString("name", item.name, sizeof(item.name), "Item");
            kv.GetString("type", item.type, sizeof(item.type), "skin");
            kv.GetString("category", item.category, sizeof(item.category), "");
            kv.GetString("description", item.description, sizeof(item.description), "");
            kv.GetString("rarity", item.rarity, sizeof(item.rarity), "common");
            kv.GetString("model", item.szModel, sizeof(item.szModel), "");
            kv.GetString("arms", item.szArms, sizeof(item.szArms), "");
            kv.GetString("value", item.szValue, sizeof(item.szValue), "");
            kv.GetString("icon", item.icon, sizeof(item.icon), "");
            kv.GetString("metadata", item.metadata, sizeof(item.metadata), "");
            kv.GetString("requires_item", item.requires_item, sizeof(item.requires_item), "");
            kv.GetString("bundle_id", item.bundle_id, sizeof(item.bundle_id), "");
            kv.GetString("flag", item.flag, sizeof(item.flag), "");
            item.price = kv.GetNum("price", 0);
            item.sale_price = kv.GetNum("sale_price", -1);
            item.team = kv.GetNum("team", 0);
            item.sort_order = kv.GetNum("sort_order", 0);
            item.starts_at = kv.GetNum("starts_at", 0);
            item.ends_at = kv.GetNum("ends_at", 0);
            item.sell_percent_override = kv.GetNum("sell_percent_override", -1);
            item.hidden = kv.GetNum("hidden", 0);

            if (item.price < 0)
            {
                LogError("%s Item '%s' has an invalid negative price %d. It was clamped to 0.", STORE_LOG_PREFIX, item.id, item.price);
                item.price = 0;
            }

            if (item.sale_price < -1)
            {
                item.sale_price = -1;
            }

            if (item.sell_percent_override > 100)
            {
                item.sell_percent_override = 100;
            }
            else if (item.sell_percent_override < -1)
            {
                item.sell_percent_override = -1;
            }

            if (item.ends_at > 0 && item.starts_at > 0 && item.ends_at < item.starts_at)
            {
                LogError("%s Item '%s' has ends_at earlier than starts_at. ends_at was ignored.", STORE_LOG_PREFIX, item.id);
                item.ends_at = 0;
            }

            if (StrEqual(item.requires_item, item.id))
            {
                LogError("%s Item '%s' cannot require itself. requires_item was ignored.", STORE_LOG_PREFIX, item.id);
                item.requires_item[0] = '\0';
            }

            if (StrEqual(item.type, "skin"))
            {
                if (item.szModel[0] == '\0' || !FileExists(item.szModel, true))
                {
                    LogError("%s Invalid skin '%s': missing model '%s'", STORE_LOG_PREFIX, item.id, item.szModel);
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
                        LogError("%s Invalid arms for '%s': '%s'", STORE_LOG_PREFIX, item.id, item.szArms);
                        item.szArms[0] = '\0';
                    }
                }
            }

            int existingIndex;
            if (g_mItemIndex != null && g_mItemIndex.GetValue(item.id, existingIndex))
            {
                LogError("%s Duplicate item id in config: %s", STORE_LOG_PREFIX, item.id);
                continue;
            }

            int pushedIndex = g_aItems.PushArray(item, sizeof(StoreItem));
            if (g_mItemIndex != null)
            {
                g_mItemIndex.SetValue(item.id, pushedIndex);
            }

            if (item.metadata[0] != '\0')
            {
                SetItemMetadataValue(item.id, "raw", item.metadata);
            }

            if (StrEqual(item.type, "skin"))
            {
                loadedSkins++;
            }
            else if (StrEqual(item.type, "tag"))
            {
                loadedTags++;
            }
            else if (StrEqual(item.type, "namecolor"))
            {
                loadedNameColors++;
            }
            else if (StrEqual(item.type, "chatcolor"))
            {
                loadedChatColors++;
            }
            else
            {
                loadedCustom++;
            }
        }
        while (kv.GotoNextKey());
    }

    delete kv;

    RebuildItemCache();
    LogMessage("%s Loaded item config: %d items (skins=%d, tags=%d, namecolors=%d, chatcolors=%d, custom=%d).",
        STORE_LOG_PREFIX,
        g_aItems.Length,
        loadedSkins,
        loadedTags,
        loadedNameColors,
        loadedChatColors,
        loadedCustom);
}

public Action Cmd_ReloadStore(int client, int args)
{
    LoadItemsConfig();

    char msg[192];
    Format(msg, sizeof(msg), "%T", "Store Reloaded", client, g_aItems.Length);
    ReplaceColorTags(msg, sizeof(msg));
    ReplyStoreText(client, msg);

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
    char query6[512];
    char query7[512];
    char query8[512];
    char query9[512];
    char query10[512];
    char query11[512];
    char query12[768];
    char query13[512];
    char query14[512];
    char query15[512];
    query3[0] = '\0';
    query5[0] = '\0';
    query7[0] = '\0';
    query9[0] = '\0';
    query11[0] = '\0';
    query13[0] = '\0';
    query15[0] = '\0';

    if (g_bIsMySQL)
    {
        Format(query1, sizeof(query1),
            "CREATE TABLE IF NOT EXISTS store_players (steamid VARCHAR(32) NOT NULL PRIMARY KEY, name VARCHAR(64) NOT NULL, credits INT NOT NULL DEFAULT 0)");
        Format(query2, sizeof(query2),
            "CREATE TABLE IF NOT EXISTS store_inventory (steamid VARCHAR(32) NOT NULL, item_id VARCHAR(32) NOT NULL, is_equipped INT NOT NULL DEFAULT 0, PRIMARY KEY (steamid, item_id))");
        Format(query4, sizeof(query4),
            "CREATE TABLE IF NOT EXISTS store_credits_ledger (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, steamid VARCHAR(32) NOT NULL, amount INT NOT NULL, reason VARCHAR(64) NOT NULL, balance_after INT NOT NULL, created_at INT NOT NULL, INDEX idx_store_credits_ledger_steamid (steamid), INDEX idx_store_credits_ledger_created (created_at))");
        Format(query6, sizeof(query6),
            "CREATE TABLE IF NOT EXISTS store_player_stats (steamid VARCHAR(32) NOT NULL, stat_key VARCHAR(64) NOT NULL, stat_value INT NOT NULL DEFAULT 0, updated_at INT NOT NULL DEFAULT 0, PRIMARY KEY (steamid, stat_key), INDEX idx_store_player_stats_key (stat_key))");
        Format(query8, sizeof(query8),
            "CREATE TABLE IF NOT EXISTS store_player_quests (steamid VARCHAR(32) NOT NULL, quest_id VARCHAR(64) NOT NULL, progress INT NOT NULL DEFAULT 0, completed_at INT NOT NULL DEFAULT 0, rewarded_at INT NOT NULL DEFAULT 0, PRIMARY KEY (steamid, quest_id), INDEX idx_store_player_quests_quest (quest_id))");
        Format(query10, sizeof(query10),
            "CREATE TABLE IF NOT EXISTS store_player_quest_counts (steamid VARCHAR(32) NOT NULL, quest_id VARCHAR(64) NOT NULL, completion_count INT NOT NULL DEFAULT 0, updated_at INT NOT NULL DEFAULT 0, PRIMARY KEY (steamid, quest_id), INDEX idx_store_player_quest_counts_quest (quest_id))");
        Format(query12, sizeof(query12),
            "CREATE TABLE IF NOT EXISTS store_market_listings (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, seller_steamid VARCHAR(32) NOT NULL, item_id VARCHAR(32) NOT NULL, price INT NOT NULL, fee_percent INT NOT NULL DEFAULT 0, created_at INT NOT NULL, expires_at INT NOT NULL, sold_to VARCHAR(32) NOT NULL DEFAULT '', sold_at INT NOT NULL DEFAULT 0, cancelled_at INT NOT NULL DEFAULT 0, INDEX idx_store_market_seller (seller_steamid), INDEX idx_store_market_active (sold_at, cancelled_at, expires_at))");
        Format(query14, sizeof(query14),
            "CREATE TABLE IF NOT EXISTS store_market_sales (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, listing_id INT NOT NULL, seller_steamid VARCHAR(32) NOT NULL, buyer_steamid VARCHAR(32) NOT NULL, item_id VARCHAR(32) NOT NULL, price INT NOT NULL, fee_amount INT NOT NULL DEFAULT 0, created_at INT NOT NULL, INDEX idx_store_market_sales_seller (seller_steamid), INDEX idx_store_market_sales_buyer (buyer_steamid))");
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
        Format(query6, sizeof(query6),
            "CREATE TABLE IF NOT EXISTS store_player_stats (steamid TEXT NOT NULL, stat_key TEXT NOT NULL, stat_value INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, stat_key))");
        Format(query7, sizeof(query7),
            "CREATE INDEX IF NOT EXISTS idx_store_player_stats_key ON store_player_stats (stat_key)");
        Format(query8, sizeof(query8),
            "CREATE TABLE IF NOT EXISTS store_player_quests (steamid TEXT NOT NULL, quest_id TEXT NOT NULL, progress INTEGER NOT NULL DEFAULT 0, completed_at INTEGER NOT NULL DEFAULT 0, rewarded_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, quest_id))");
        Format(query9, sizeof(query9),
            "CREATE INDEX IF NOT EXISTS idx_store_player_quests_quest ON store_player_quests (quest_id)");
        Format(query10, sizeof(query10),
            "CREATE TABLE IF NOT EXISTS store_player_quest_counts (steamid TEXT NOT NULL, quest_id TEXT NOT NULL, completion_count INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (steamid, quest_id))");
        Format(query11, sizeof(query11),
            "CREATE INDEX IF NOT EXISTS idx_store_player_quest_counts_quest ON store_player_quest_counts (quest_id)");
        Format(query12, sizeof(query12),
            "CREATE TABLE IF NOT EXISTS store_market_listings (id INTEGER PRIMARY KEY AUTOINCREMENT, seller_steamid TEXT NOT NULL, item_id TEXT NOT NULL, price INTEGER NOT NULL, fee_percent INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, sold_to TEXT NOT NULL DEFAULT '', sold_at INTEGER NOT NULL DEFAULT 0, cancelled_at INTEGER NOT NULL DEFAULT 0)");
        Format(query13, sizeof(query13),
            "CREATE INDEX IF NOT EXISTS idx_store_market_active ON store_market_listings (sold_at, cancelled_at, expires_at)");
        Format(query14, sizeof(query14),
            "CREATE TABLE IF NOT EXISTS store_market_sales (id INTEGER PRIMARY KEY AUTOINCREMENT, listing_id INTEGER NOT NULL, seller_steamid TEXT NOT NULL, buyer_steamid TEXT NOT NULL, item_id TEXT NOT NULL, price INTEGER NOT NULL, fee_amount INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)");
        Format(query15, sizeof(query15),
            "CREATE INDEX IF NOT EXISTS idx_store_market_sales_seller ON store_market_sales (seller_steamid)");
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
    if (query6[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query7[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query8[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query9[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query10[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query11[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query12[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query13[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query14[0] != '\0')
    {
        g_iPendingTableQueries++;
    }
    if (query15[0] != '\0')
    {
        g_iPendingTableQueries++;
    }

    g_DB.Query(OnTableCreated, query1);
    g_DB.Query(OnTableCreated, query2);
    g_DB.Query(OnTableCreated, query4);
    g_DB.Query(OnTableCreated, query6);
    g_DB.Query(OnTableCreated, query8);
    g_DB.Query(OnTableCreated, query10);
    g_DB.Query(OnTableCreated, query12);
    g_DB.Query(OnTableCreated, query14);

    if (query3[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query3);
    }

    if (query5[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query5);
    }

    if (query7[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query7);
    }

    if (query9[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query9);
    }

    if (query11[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query11);
    }

    if (query13[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query13);
    }

    if (query15[0] != '\0')
    {
        g_DB.Query(OnTableCreated, query15);
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

bool EnsureSharedTableInternal(const char[] tableId, const char[] mysqlQuery, const char[] sqliteQuery)
{
    if (g_DB == null || tableId[0] == '\0')
    {
        return false;
    }

    if (g_mEnsuredTables == null)
    {
        g_mEnsuredTables = new StringMap();
    }

    int cached;
    if (g_mEnsuredTables.GetValue(tableId, cached) && cached == 1)
    {
        return true;
    }

    char query[1024];
    if (g_bIsMySQL)
    {
        strcopy(query, sizeof(query), mysqlQuery);
    }
    else
    {
        strcopy(query, sizeof(query), sqliteQuery);
    }

    if (query[0] == '\0')
    {
        return false;
    }

    SQL_LockDatabase(g_DB);
    if (!SQL_FastQuery(g_DB, query))
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("EnsureSharedTableInternal", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }
    SQL_UnlockDatabase(g_DB);

    g_mEnsuredTables.SetValue(tableId, 1);
    return true;
}

bool GetQuestProgressState(int client, const char[] questId, int &progress, int &completedAt, int &rewardedAt)
{
    progress = 0;
    completedAt = 0;
    rewardedAt = 0;

    if (g_DB == null || !IsValidClientConnected(client) || questId[0] == '\0')
    {
        return false;
    }

    char steamid[32], safeSteamId[64], safeQuestId[128], query[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(questId, safeQuestId, sizeof(safeQuestId));
    Format(query, sizeof(query),
        "SELECT progress, completed_at, rewarded_at FROM store_player_quests WHERE steamid = '%s' AND quest_id = '%s'",
        safeSteamId, safeQuestId);

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("GetQuestProgressState", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }

    if (results.FetchRow())
    {
        progress = results.FetchInt(0);
        completedAt = results.FetchInt(1);
        rewardedAt = results.FetchInt(2);
    }

    delete results;
    SQL_UnlockDatabase(g_DB);
    return true;
}

bool GetQuestCompletionCount(int client, const char[] questId, int &count)
{
    count = 0;

    if (g_DB == null || !IsValidClientConnected(client) || questId[0] == '\0')
    {
        return false;
    }

    char steamid[32], safeSteamId[64], safeQuestId[128], query[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(questId, safeQuestId, sizeof(safeQuestId));
    Format(query, sizeof(query),
        "SELECT completion_count FROM store_player_quest_counts WHERE steamid = '%s' AND quest_id = '%s'",
        safeSteamId, safeQuestId);

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("GetQuestCompletionCount", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }

    if (results.FetchRow())
    {
        count = results.FetchInt(0);
    }

    delete results;
    SQL_UnlockDatabase(g_DB);
    return true;
}

bool PersistQuestCompletionCount(int client, const char[] questId, int count)
{
    if (g_DB == null || !IsValidClientConnected(client) || questId[0] == '\0')
    {
        return false;
    }

    char steamid[32], safeSteamId[64], safeQuestId[128], query[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(questId, safeQuestId, sizeof(safeQuestId));

    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "INSERT INTO store_player_quest_counts (steamid, quest_id, completion_count, updated_at) VALUES ('%s', '%s', %d, %d) "
            ... "ON DUPLICATE KEY UPDATE completion_count = VALUES(completion_count), updated_at = VALUES(updated_at)",
            safeSteamId, safeQuestId, count, GetTime());
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO store_player_quest_counts (steamid, quest_id, completion_count, updated_at) VALUES ('%s', '%s', %d, %d) "
            ... "ON CONFLICT(steamid, quest_id) DO UPDATE SET completion_count = excluded.completion_count, updated_at = excluded.updated_at",
            safeSteamId, safeQuestId, count, GetTime());
    }

    SQL_LockDatabase(g_DB);
    bool ok = SQL_FastQuery(g_DB, query);
    if (!ok)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("PersistQuestCompletionCount", error);
    }
    SQL_UnlockDatabase(g_DB);
    return ok;
}

bool IsQuestWithinWindow(const StoreQuestDefinition definition, int now)
{
    if (definition.starts_at > 0 && now < definition.starts_at)
    {
        return false;
    }

    if (definition.ends_at > 0 && now > definition.ends_at)
    {
        return false;
    }

    return true;
}

bool HasQuestRewardedAtLeastOnce(int client, const char[] questId)
{
    int progress = 0;
    int completedAt = 0;
    int rewardedAt = 0;
    if (!GetQuestProgressState(client, questId, progress, completedAt, rewardedAt))
    {
        return false;
    }

    if (rewardedAt > 0)
    {
        return true;
    }

    int completionCount = 0;
    GetQuestCompletionCount(client, questId, completionCount);
    return (completionCount > 0);
}

void GetQuestAvailabilityState(int client, const StoreQuestDefinition definition, int rewardedAt, int completionCount, bool &lockedByWindow, bool &lockedByRequirement, bool &maxedOut)
{
    lockedByWindow = false;
    lockedByRequirement = false;
    maxedOut = false;

    int now = GetTime();
    if (!IsQuestWithinWindow(definition, now))
    {
        lockedByWindow = true;
    }

    if (definition.requires_quest[0] != '\0' && !HasQuestRewardedAtLeastOnce(client, definition.requires_quest))
    {
        lockedByRequirement = true;
    }

    if (definition.repeatable)
    {
        if (definition.max_completions > 0 && completionCount >= definition.max_completions)
        {
            maxedOut = true;
        }
    }
    else if (rewardedAt > 0 || completionCount > 0)
    {
        maxedOut = true;
    }
}

void GetQuestAvailabilityStateFromSnapshot(const StoreQuestDefinition definition, int rewardedAt, int completionCount, ArrayList questRows, StringMap questIndex, bool &lockedByWindow, bool &lockedByRequirement, bool &maxedOut)
{
    lockedByWindow = false;
    lockedByRequirement = false;
    maxedOut = false;

    int now = GetTime();
    if (!IsQuestWithinWindow(definition, now))
    {
        lockedByWindow = true;
    }

    if (definition.requires_quest[0] != '\0' && !HasQuestRewardedInSnapshot(questRows, questIndex, definition.requires_quest))
    {
        lockedByRequirement = true;
    }

    if (definition.repeatable)
    {
        if (definition.max_completions > 0 && completionCount >= definition.max_completions)
        {
            maxedOut = true;
        }
    }
    else if (rewardedAt > 0 || completionCount > 0)
    {
        maxedOut = true;
    }
}

bool PersistQuestProgressState(int client, const char[] questId, int progress, int completedAt, int rewardedAt)
{
    if (g_DB == null || !IsValidClientConnected(client) || questId[0] == '\0')
    {
        return false;
    }

    char steamid[32], safeSteamId[64], safeQuestId[128], query[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(questId, safeQuestId, sizeof(safeQuestId));

    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "INSERT INTO store_player_quests (steamid, quest_id, progress, completed_at, rewarded_at) VALUES ('%s', '%s', %d, %d, %d) "
            ... "ON DUPLICATE KEY UPDATE progress = VALUES(progress), completed_at = VALUES(completed_at), rewarded_at = VALUES(rewarded_at)",
            safeSteamId, safeQuestId, progress, completedAt, rewardedAt);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO store_player_quests (steamid, quest_id, progress, completed_at, rewarded_at) VALUES ('%s', '%s', %d, %d, %d) "
            ... "ON CONFLICT(steamid, quest_id) DO UPDATE SET progress = excluded.progress, completed_at = excluded.completed_at, rewarded_at = excluded.rewarded_at",
            safeSteamId, safeQuestId, progress, completedAt, rewardedAt);
    }

    SQL_LockDatabase(g_DB);
    bool ok = SQL_FastQuery(g_DB, query);
    if (!ok)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("PersistQuestProgressState", error);
    }
    SQL_UnlockDatabase(g_DB);
    return ok;
}

bool UpdateQuestProgressInternal(int client, const char[] questId, int value, bool setMax = false)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || value <= 0)
    {
        return false;
    }

    StoreQuestDefinition definition;
    if (!FindQuestDefinition(questId, definition))
    {
        return false;
    }

    int currentProgress = 0;
    int completedAt = 0;
    int rewardedAt = 0;
    int completionCount = 0;
    if (!GetQuestProgressState(client, questId, currentProgress, completedAt, rewardedAt))
    {
        return false;
    }
    if (!GetQuestCompletionCount(client, questId, completionCount))
    {
        completionCount = 0;
    }

    bool lockedByWindow = false;
    bool lockedByRequirement = false;
    bool maxedOut = false;
    GetQuestAvailabilityState(client, definition, rewardedAt, completionCount, lockedByWindow, lockedByRequirement, maxedOut);
    if (lockedByWindow || lockedByRequirement || maxedOut)
    {
        return false;
    }

    int newProgress = setMax ? ((value > currentProgress) ? value : currentProgress) : (currentProgress + value);
    int now = GetTime();
    bool shouldComplete = (newProgress >= definition.goal);

    if (shouldComplete && completedAt <= 0)
    {
        completedAt = now;
    }

    bool shouldReward = (shouldComplete && rewardedAt <= 0);
    if (shouldReward)
    {
        rewardedAt = now;
    }

    if (shouldReward)
    {
        completionCount++;
        if (!PersistQuestCompletionCount(client, questId, completionCount))
        {
            return false;
        }
    }

    int persistedProgress = newProgress;
    int persistedCompletedAt = completedAt;
    int persistedRewardedAt = rewardedAt;

    if (shouldReward && definition.repeatable)
    {
        bool reachedCap = (definition.max_completions > 0 && completionCount >= definition.max_completions);
        if (!reachedCap)
        {
            persistedProgress = 0;
            persistedCompletedAt = 0;
            persistedRewardedAt = 0;
        }
        else
        {
            persistedProgress = definition.goal;
            persistedCompletedAt = now;
            persistedRewardedAt = now;
        }
    }

    if (!PersistQuestProgressState(client, questId, persistedProgress, persistedCompletedAt, persistedRewardedAt))
    {
        return false;
    }

    if (shouldReward)
    {
        if (definition.reward_credits > 0)
        {
            g_iCredits[client] += definition.reward_credits;

            char reason[96];
            Format(reason, sizeof(reason), "quest:%s", questId);
            ReportCreditsChanged(client, definition.reward_credits, reason, false, false);
            SavePlayer(client);
        }

        if (definition.reward_item[0] != '\0')
        {
            if (!GiveItemToClient(client, definition.reward_item, view_as<bool>(definition.reward_item_equip), true))
            {
                LogError("%s Quest '%s' could not reward item '%s' to client %N.", STORE_LOG_PREFIX, questId, definition.reward_item, client);
            }
        }

        char rewardText[128];
        FormatQuestRewardText(client, definition, rewardText, sizeof(rewardText));
        if (rewardText[0] != '\0')
        {
            PrintStorePhrase(client, "%T", "Quest Rewarded", client, rewardText);
        }

        ForwardQuestCompleted(client, questId, definition.reward_credits);
    }

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

    if (g_bAwaitingMarketPrice[client])
    {
        if (StrEqual(text, "cancel", false) || StrEqual(text, "cancelar", false))
        {
            g_bAwaitingMarketPrice[client] = false;
            g_szPendingMarketItem[client][0] = '\0';
            PrintStorePhrase(client, "%T", "Market Price Cancelled", client);
            return Plugin_Handled;
        }

        if (!IsWholeNumberString(text))
        {
            PrintStorePhrase(client, "%T", "Market Price Invalid", client, GetMarketplaceMinPrice(), GetMarketplaceMaxPrice());
            return Plugin_Handled;
        }

        int price = StringToInt(text);
        char itemId[32];
        strcopy(itemId, sizeof(itemId), g_szPendingMarketItem[client]);
        g_bAwaitingMarketPrice[client] = false;
        g_szPendingMarketItem[client][0] = '\0';
        CreateMarketplaceListing(client, itemId, price);
        ShowMarketMenu(client);
        return Plugin_Handled;
    }

    char tag[96] = "";
    char nameColor[64] = "{teamcolor}";
    char chatColor[64] = "{default}";
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
            char tagValue[96];
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

    char clientName[64], safeText[256], finalMsg[384], prefix[64] = "";
    GetClientName(client, clientName, sizeof(clientName));
    SanitizeChatRenderInput(clientName, sizeof(clientName));
    strcopy(safeText, sizeof(safeText), text);
    SanitizeChatRenderInput(safeText, sizeof(safeText));

    if (!IsPlayerAlive(client))
    {
        StrCat(prefix, sizeof(prefix), " {default}*MUERTO*");
    }

    if (isTeamChat)
    {
        char teamName[64];
        char teamPrefix[80];
        GetReadableTeamName(client, teamName, sizeof(teamName));
        SanitizeChatRenderInput(teamName, sizeof(teamName));
        Format(teamPrefix, sizeof(teamPrefix), " {default}(%s)", teamName);
        StrCat(prefix, sizeof(prefix), teamPrefix);
    }

    Format(finalMsg, sizeof(finalMsg), "%s%s %s%s{default} : %s%s", prefix, tag, nameColor, clientName, chatColor, safeText);

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

        CPrintToChatEx(i, client, "%s", finalMsg);
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

    if (IsItemTypeExclusive(targetItem.type) && StrEqual(targetItem.type, otherItem.type))
    {
        return true;
    }

    char targetCategory[32], otherCategory[32];
    GetItemCategory(targetItem, targetCategory, sizeof(targetCategory));
    GetItemCategory(otherItem, otherCategory, sizeof(otherCategory));

    if (!StrEqual(targetItem.type, otherItem.type)
        && IsBuiltinChatCosmeticType(targetItem.type)
        && IsBuiltinChatCosmeticType(otherItem.type))
    {
        return false;
    }

    if (targetCategory[0] != '\0' && StrEqual(targetCategory, otherCategory) && IsItemTypeExclusive(targetItem.type))
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

    if (HasEntProp(client, Prop_Send, "m_szArmsModel"))
    {
        SetEntPropString(client, Prop_Send, "m_szArmsModel", "");
    }
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

        if (item.szArms[0] != '\0' && FileExists(item.szArms, true) && HasEntProp(client, Prop_Send, "m_szArmsModel"))
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

bool SetItemEquipped(int client, const char[] itemId, bool equipNow, bool notify = true, bool respectCooldown = true)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        return false;
    }

    if (respectCooldown && !CanUseEquipAction(client))
    {
        return false;
    }

    StoreItem targetItem;
    if (!FindStoreItemById(itemId, targetItem))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item Not Found", client);
        }
        return false;
    }

    int targetIndex = FindInventoryIndexByItemId(client, itemId);
    if (targetIndex == -1)
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item Not In Inventory", client);
        }
        return false;
    }

    InventoryItem targetInv;
    g_hInventory[client].GetArray(targetIndex, targetInv, sizeof(InventoryItem));

    if (view_as<bool>(targetInv.is_equipped) == equipNow)
    {
        return true;
    }

    if (equipNow)
    {
        if (!CanPlayerUseItem(client, targetItem, notify))
        {
            return false;
        }

        if (StrEqual(targetItem.type, "skin") && !ArePlayerSkinsEnabled())
        {
            if (notify)
            {
                PrintStorePhrase(client, "%T", "Player Skins Disabled", client);
            }
            return false;
        }
    }

    if (ForwardEquipPre(client, itemId, equipNow) >= Plugin_Handled)
    {
        return false;
    }

    if (equipNow && HasActiveMarketplaceListing(client, itemId))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Market Item Listed Already", client);
        }
        return false;
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
                ForwardItemEquipped(client, inv.item_id, false);
                ForwardEquipPost(client, inv.item_id, false);
                ForwardInventoryChanged(client, inv.item_id, "unequip");
            }
        }

        targetInv.is_equipped = 1;
        g_hInventory[client].SetArray(targetIndex, targetInv, sizeof(InventoryItem));
        SaveInventoryEquipState(client, itemId, 1);

        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item Equipped", client);
        }

        ForwardItemEquipped(client, itemId, true);
        ForwardEquipPost(client, itemId, true);
        ForwardInventoryChanged(client, itemId, "equip");
    }
    else
    {
        targetInv.is_equipped = 0;
        g_hInventory[client].SetArray(targetIndex, targetInv, sizeof(InventoryItem));
        SaveInventoryEquipState(client, itemId, 0);

        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item Unequipped", client);
        }

        ForwardItemEquipped(client, itemId, false);
        ForwardEquipPost(client, itemId, false);
        ForwardInventoryChanged(client, itemId, "unequip");
    }

    MarkInventoryChanged(client);

    if (StrEqual(targetItem.type, "skin"))
    {
        ApplyPlayerSkin(client);
    }

    return true;
}

void ToggleEquip(int client, const char[] itemId)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null)
    {
        return;
    }

    int targetIndex = FindInventoryIndexByItemId(client, itemId);
    if (targetIndex == -1)
    {
        PrintStorePhrase(client, "%T", "Item Not In Inventory", client);
        return;
    }

    InventoryItem targetInv;
    g_hInventory[client].GetArray(targetIndex, targetInv, sizeof(InventoryItem));
    SetItemEquipped(client, itemId, !view_as<bool>(targetInv.is_equipped), true, true);
}

bool BuyItem(int client, const char[] itemId, bool equipAfterPurchase = false, bool notify = true)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_hInventory[client] == null || g_DB == null)
    {
        return false;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item No Longer Exists", client);
        }
        return false;
    }

    if (item.price < 0)
    {
        LogError("%s BuyItem: invalid negative price for item '%s' (%d)", STORE_LOG_PREFIX, item.id, item.price);
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Item No Longer Exists", client);
        }
        return false;
    }

    char reason[64];
    if (!CanPurchaseItemEx(client, item.id, reason, sizeof(reason)))
    {
        if (notify)
        {
            if (StrEqual(reason, "not_enough_credits"))
            {
                PrintStorePhrase(client, "%T", "Not Enough Credits", client);
            }
            else if (StrEqual(reason, "no_access"))
            {
                PrintStorePhrase(client, "%T", "No Access Item", client);
            }
            else if (StrEqual(reason, "already_owned"))
            {
                PrintStorePhrase(client, "%T", "Already Owns Item", client);
            }
            else
            {
                PrintStorePhrase(client, "%T", "Item No Longer Exists", client);
            }
        }
        return false;
    }

    if (ForwardPurchasePre(client, item.id, equipAfterPurchase) >= Plugin_Handled)
    {
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
    char buyReason[64];
    Format(buyReason, sizeof(buyReason), "buy:%s", item.id);
    ReportCreditsChanged(client, -item.price, buyReason, false, true);

    InventoryItem newInv;
    strcopy(newInv.item_id, sizeof(newInv.item_id), item.id);
    newInv.is_equipped = 0;
    g_hInventory[client].PushArray(newInv, sizeof(InventoryItem));
    InventoryOwnedSet(client, item.id, true);
    MarkInventoryChanged(client);
    ForwardInventoryChanged(client, item.id, "purchase");
    UpdatePlayerStat(client, "purchases_total", 1);

    bool equippedAfterPurchase = false;
    if (equipAfterPurchase)
    {
        equippedAfterPurchase = SetItemEquipped(client, item.id, true, notify, false);
    }

    if (notify)
    {
        char priceText[32], balanceText[32];
        FormatNumberDots(item.price, priceText, sizeof(priceText));
        FormatNumberDots(g_iCredits[client], balanceText, sizeof(balanceText));

        PrintStorePhrase(client, "%T", "Item Bought", client, item.name, priceText);
        PrintStorePhrase(client, "%T", "Balance Current", client, balanceText);
    }

    ForwardItemPurchased(client, item.id);
    ForwardPurchasePost(client, item.id, item.price, equippedAfterPurchase);
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

    if (HasActiveMarketplaceListing(client, item.id))
    {
        PrintStorePhrase(client, "%T", "Market Item Listed Already", client);
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
    int refund = GetItemSellPrice(item);
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
    char sellReason[64];
    Format(sellReason, sizeof(sellReason), "sell:%s", item.id);
    ReportCreditsChanged(client, refund, sellReason, false, true);
    ForwardInventoryChanged(client, item.id, "sell");
    UpdatePlayerStat(client, "sales_total", 1);

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
void AddRegisteredMenuSections(Menu menu)
{
    if (g_aMenuSections == null || g_aMenuSections.Length == 0)
    {
        return;
    }

    ArrayList ordered = new ArrayList();
    StoreMenuSection section;
    int insertAt;

    for (int i = 0; i < g_aMenuSections.Length; i++)
    {
        ordered.Push(i);
    }

    for (int i = 1; i < ordered.Length; i++)
    {
        int currentIndex = ordered.Get(i);
        g_aMenuSections.GetArray(currentIndex, section, sizeof(StoreMenuSection));
        int currentOrder = section.sort_order;

        insertAt = i - 1;
        while (insertAt >= 0)
        {
            int compareIndex = ordered.Get(insertAt);
            StoreMenuSection compareSection;
            g_aMenuSections.GetArray(compareIndex, compareSection, sizeof(StoreMenuSection));

            if (compareSection.sort_order < currentOrder || (compareSection.sort_order == currentOrder && strcmp(compareSection.title, section.title, false) <= 0))
            {
                break;
            }

            ordered.Set(insertAt + 1, compareIndex);
            insertAt--;
        }

        ordered.Set(insertAt + 1, currentIndex);
    }

    for (int i = 0; i < ordered.Length; i++)
    {
        int index = ordered.Get(i);
        g_aMenuSections.GetArray(index, section, sizeof(StoreMenuSection));
        menu.AddItem(section.id, section.title);
    }

    delete ordered;
}

void ShowStoreMainMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Main);
    char title[192];
    char creditsText[32];
    char profileLabel[64], questsLabel[64], skinsLabel[64], chatLabel[64], leaderboardsLabel[64], inventoryLabel[64], casinoLabel[64], marketLabel[64];

    FormatNumberDots(g_iCredits[client], creditsText, sizeof(creditsText));
    Format(title, sizeof(title), "%T", "Store Main Menu Title", client, creditsText);
    menu.SetTitle(title);

    Format(profileLabel, sizeof(profileLabel), "%T", "Store Category Profile", client);
    Format(questsLabel, sizeof(questsLabel), "%T", "Store Category Quests", client);
    Format(skinsLabel, sizeof(skinsLabel), "%T", "Store Category Skins", client);
    Format(chatLabel, sizeof(chatLabel), "%T", "Store Category Chat", client);
    Format(leaderboardsLabel, sizeof(leaderboardsLabel), "%T", "Store Category Leaderboards", client);
    Format(inventoryLabel, sizeof(inventoryLabel), "%T", "Store Category Inventory", client);
    Format(casinoLabel, sizeof(casinoLabel), "%T", "Store Category Casino", client);
    Format(marketLabel, sizeof(marketLabel), "%T", "Store Category Marketplace", client);

    menu.AddItem("profile", profileLabel);
    menu.AddItem("quests", questsLabel);
    menu.AddItem("skins", skinsLabel);
    menu.AddItem("chat", chatLabel);
    menu.AddItem("leaderboards", leaderboardsLabel);
    menu.AddItem("inventory", inventoryLabel);
    menu.AddItem("market", marketLabel);
    AddRegisteredMenuSections(menu);
    menu.AddItem("casino", casinoLabel);
    menu.Display(client, MENU_TIME_FOREVER);
}

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

    ShowStoreMainMenu(client);
    return Plugin_Handled;
}

public Action Cmd_Profile(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    ShowProfileMenu(client);
    return Plugin_Handled;
}

public Action Cmd_Market(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    if (!IsMarketplaceEnabled())
    {
        PrintStorePhrase(client, "%T", "Market Disabled", client);
        return Plugin_Handled;
    }

    if (g_DB == null)
    {
        PrintStorePhrase(client, "%T", "Store DB Not Ready", client);
        return Plugin_Handled;
    }

    ShowMarketMenu(client);
    return Plugin_Handled;
}

public Action Cmd_Quests(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    ShowQuestMenu(client);
    return Plugin_Handled;
}

public Action Cmd_ProfileExport(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    ExportProfileSnapshot(client);
    return Plugin_Handled;
}

public Action Cmd_Leaderboards(int client, int args)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client])
    {
        return Plugin_Handled;
    }

    if (!EnsureStoreEnabledForClient(client))
    {
        return Plugin_Handled;
    }

    ShowLeaderboardsMenu(client);
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
        else if (StrEqual(info, "profile"))
        {
            ShowProfileMenu(param1);
        }
        else if (StrEqual(info, "quests"))
        {
            ShowQuestMenu(param1);
        }
        else if (StrEqual(info, "chat"))
        {
            ShowChatMenu(param1);
        }
        else if (StrEqual(info, "topcredits"))
        {
            Cmd_TopCredits(param1, 0);
        }
        else if (StrEqual(info, "leaderboards"))
        {
            ShowLeaderboardsMenu(param1);
        }
        else if (StrEqual(info, "inventory"))
        {
            ShowInventoryCategoryMenu(param1);
        }
        else if (StrEqual(info, "market"))
        {
            ShowMarketMenu(param1);
        }
        else if (StrEqual(info, "casino"))
        {
            ShowCasinoMenu(param1);
        }
        else
        {
            TryHandleRegisteredMenuSectionSelection(param1, info);
        }
    }

    return 0;
}

void ShowLeaderboardsMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Leaderboards);
    SetMenuTitlePhrase(menu, client, "Leaderboards Menu Title");

    AddMenuItemPhrase(menu, "credits", client, "Leaderboards Credits");
    AddMenuItemPhrase(menu, "profit", client, "Leaderboards Profit");
    AddMenuItemPhrase(menu, "daily", client, "Leaderboards Daily");
    AddMenuItemPhrase(menu, "blackjack", client, "Leaderboards Blackjack");
    AddMenuItemPhrase(menu, "coinflip", client, "Leaderboards Coinflip");
    AddMenuItemPhrase(menu, "crash", client, "Leaderboards Crash");
    AddMenuItemPhrase(menu, "roulette", client, "Leaderboards Roulette");
    AddRegisteredLeaderboards(menu, client);

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

void AddRegisteredLeaderboards(Menu menu, int client)
{
    if (g_aLeaderboards == null || g_aLeaderboards.Length <= 0)
    {
        return;
    }

    ArrayList ordered = new ArrayList();
    for (int i = 0; i < g_aLeaderboards.Length; i++)
    {
        ordered.Push(i);
    }

    StoreLeaderboardDefinition current;
    StoreLeaderboardDefinition compare;
    for (int i = 1; i < ordered.Length; i++)
    {
        int currentIndex = ordered.Get(i);
        g_aLeaderboards.GetArray(currentIndex, current, sizeof(StoreLeaderboardDefinition));

        int insertAt = i - 1;
        while (insertAt >= 0)
        {
            int compareIndex = ordered.Get(insertAt);
            g_aLeaderboards.GetArray(compareIndex, compare, sizeof(StoreLeaderboardDefinition));
            if (compare.sort_order <= current.sort_order)
            {
                break;
            }
            ordered.Set(insertAt + 1, compareIndex);
            insertAt--;
        }

        ordered.Set(insertAt + 1, currentIndex);
    }

    char title[128];
    for (int i = 0; i < ordered.Length; i++)
    {
        int index = ordered.Get(i);
        g_aLeaderboards.GetArray(index, current, sizeof(StoreLeaderboardDefinition));
        FormatQuestText(client, current.title, title, sizeof(title));
        menu.AddItem(current.id, title);
    }

    delete ordered;
}

public int MenuHandler_Leaderboards(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowStoreMainMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "credits"))
        {
            OpenTopCreditsLeaderboard(param1, true);
        }
        else if (StrEqual(info, "profit"))
        {
            OpenTopProfitLeaderboard(param1, true);
        }
        else if (StrEqual(info, "daily"))
        {
            OpenTopDailyLeaderboard(param1, true);
        }
        else if (StrEqual(info, "blackjack"))
        {
            OpenTopBlackjackLeaderboard(param1, true);
        }
        else if (StrEqual(info, "coinflip"))
        {
            OpenTopCoinflipLeaderboard(param1, true);
        }
        else if (StrEqual(info, "crash"))
        {
            OpenTopCrashLeaderboard(param1, true);
        }
        else if (StrEqual(info, "roulette"))
        {
            OpenTopRouletteLeaderboard(param1, true);
        }
        else
        {
            OpenRegisteredLeaderboard(param1, info, true);
        }
    }

    return 0;
}

bool OpenRegisteredLeaderboard(int client, const char[] leaderboardId, bool backToHub = false)
{
    if (leaderboardId[0] == '\0' || g_aLeaderboards == null || g_mLeaderboardIndex == null)
    {
        return false;
    }

    int index;
    if (!g_mLeaderboardIndex.GetValue(leaderboardId, index) || index < 0 || index >= g_aLeaderboards.Length)
    {
        return false;
    }

    StoreLeaderboardDefinition definition;
    g_aLeaderboards.GetArray(index, definition, sizeof(StoreLeaderboardDefinition));

    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = '%s' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name ASC LIMIT 10",
            definition.stat_key);
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = '%s' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name COLLATE NOCASE ASC LIMIT 10",
            definition.stat_key);
    }

    RequestLeaderboardMenu(client, query, definition.title, definition.entry_phrase, backToHub);
    return true;
}

void ShowProfileMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Profile);
    char title[192];
    char creditsText[32];
    StoreProfileSnapshot snapshot;
    BuildProfileSnapshot(client, snapshot);

    FormatNumberDots(snapshot.credits, creditsText, sizeof(creditsText));
    Format(title, sizeof(title), "%T", "Profile Menu Title", client, creditsText);
    menu.SetTitle(title);

    char numberA[32], numberB[32], display[192];

    FormatNumberDots(snapshot.owned_items, numberA, sizeof(numberA));
    Format(display, sizeof(display), "%T", "Profile Summary Owned", client, numberA);
    AddMenuItemText(menu, "owned", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.equipped_items, numberA, sizeof(numberA));
    Format(display, sizeof(display), "%T", "Profile Summary Equipped", client, numberA);
    AddMenuItemText(menu, "equipped", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.credits_earned, numberA, sizeof(numberA));
    Format(display, sizeof(display), "%T", "Profile Summary Credits Earned", client, numberA);
    AddMenuItemText(menu, "earned", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.credits_spent, numberA, sizeof(numberA));
    Format(display, sizeof(display), "%T", "Profile Summary Credits Spent", client, numberA);
    AddMenuItemText(menu, "spent", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.purchases_total, numberA, sizeof(numberA));
    Format(display, sizeof(display), "%T", "Profile Summary Purchases", client, numberA);
    AddMenuItemText(menu, "purchases", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.sales_total, numberA, sizeof(numberA));
    Format(display, sizeof(display), "%T", "Profile Summary Sales", client, numberA);
    AddMenuItemText(menu, "sales", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.gifts_sent, numberA, sizeof(numberA));
    FormatNumberDots(snapshot.gifts_received, numberB, sizeof(numberB));
    Format(display, sizeof(display), "%T", "Profile Summary Gifts", client, numberA, numberB);
    AddMenuItemText(menu, "gifts", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.trades_completed, numberA, sizeof(numberA));
    Format(display, sizeof(display), "%T", "Profile Summary Trades", client, numberA);
    AddMenuItemText(menu, "trades", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.daily_best_streak, numberA, sizeof(numberA));
    Format(display, sizeof(display), "%T", "Profile Summary Daily Streak", client, numberA);
    AddMenuItemText(menu, "daily", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.quests_completed, numberA, sizeof(numberA));
    Format(display, sizeof(display), "%T", "Profile Summary Quests Completed", client, numberA);
    AddMenuItemText(menu, "quests_done", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.total_casino_activity, numberA, sizeof(numberA));
    FormatNumberDots(snapshot.total_casino_profit, numberB, sizeof(numberB));
    Format(display, sizeof(display), "%T", "Profile Summary Casino Activity", client, numberA, numberB);
    AddMenuItemText(menu, "casino_activity", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.blackjack_games, numberA, sizeof(numberA));
    FormatNumberDots(snapshot.blackjack_profit, numberB, sizeof(numberB));
    Format(display, sizeof(display), "%T", "Profile Summary Module Profit", client, "Blackjack", numberA, numberB);
    AddMenuItemText(menu, "bj_profile", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.coinflip_games, numberA, sizeof(numberA));
    FormatNumberDots(snapshot.coinflip_profit, numberB, sizeof(numberB));
    Format(display, sizeof(display), "%T", "Profile Summary Module Profit", client, "Coinflip", numberA, numberB);
    AddMenuItemText(menu, "cf_profile", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.crash_rounds, numberA, sizeof(numberA));
    FormatNumberDots(snapshot.crash_profit, numberB, sizeof(numberB));
    Format(display, sizeof(display), "%T", "Profile Summary Module Profit", client, "Crash", numberA, numberB);
    AddMenuItemText(menu, "cr_profile", display, ITEMDRAW_DISABLED);

    FormatNumberDots(snapshot.roulette_games, numberA, sizeof(numberA));
    FormatNumberDots(snapshot.roulette_profit, numberB, sizeof(numberB));
    Format(display, sizeof(display), "%T", "Profile Summary Module Profit", client, "Roulette", numberA, numberB);
    AddMenuItemText(menu, "ru_profile", display, ITEMDRAW_DISABLED);

    AddMenuItemPhrase(menu, "quests", client, "Profile Action Quests");
    AddMenuItemPhrase(menu, "inventory", client, "Profile Action Inventory");
    AddMenuItemPhrase(menu, "ledger", client, "Profile Action Ledger");
    AddMenuItemPhrase(menu, "leaderboards", client, "Profile Action Leaderboards");
    AddMenuItemPhrase(menu, "export", client, "Profile Action Export");
    AddMenuItemPhrase(menu, "topdaily", client, "Profile Action Top Daily");

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Profile(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowStoreMainMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "quests"))
        {
            ShowQuestMenu(param1);
        }
        else if (StrEqual(info, "inventory"))
        {
            ShowInventoryCategoryMenu(param1);
        }
        else if (StrEqual(info, "ledger"))
        {
            ShowProfileLedgerMenu(param1);
        }
        else if (StrEqual(info, "leaderboards"))
        {
            ShowLeaderboardsMenu(param1);
        }
        else if (StrEqual(info, "export"))
        {
            ExportProfileSnapshot(param1);
        }
        else if (StrEqual(info, "topdaily"))
        {
            Cmd_TopDaily(param1, 0);
        }
    }

    return 0;
}

bool ExportProfileSnapshotInternal(int viewer, int target, char[] filePath, int maxlen)
{
    char steamid[32], name[MAX_NAME_LENGTH];
    if (!GetClientSteamIdSafe(target, steamid, sizeof(steamid)))
    {
        return false;
    }

    GetClientName(target, name, sizeof(name));

    char dataDir[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, dataDir, sizeof(dataDir), "data/umbrella_store");
    if (!DirExists(dataDir))
    {
        CreateDirectory(dataDir, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC|FPERM_G_READ|FPERM_G_EXEC|FPERM_O_READ|FPERM_O_EXEC);
    }

    char exportDir[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, exportDir, sizeof(exportDir), "data/umbrella_store/profile_exports");
    if (!DirExists(exportDir))
    {
        CreateDirectory(exportDir, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC|FPERM_G_READ|FPERM_G_EXEC|FPERM_O_READ|FPERM_O_EXEC);
    }

    char safeSteamId[64];
    SanitizeFilenameComponent(steamid, safeSteamId, sizeof(safeSteamId));

    BuildPath(Path_SM, filePath, maxlen, "data/umbrella_store/profile_exports/%s.txt", safeSteamId);

    File file = OpenFile(filePath, "wt");
    if (file == null)
    {
        if (viewer > 0)
        {
            PrintStorePhrase(viewer, "%T", "Profile Export Failed", viewer);
        }
        return false;
    }

    StoreProfileSnapshot snapshot;
    BuildProfileSnapshot(target, snapshot);

    ArrayList questRows = new ArrayList(sizeof(StoreQuestProgressSnapshot));
    StringMap questIndex = new StringMap();
    int ignoredCompletedCount = 0;
    LoadQuestProgressSnapshot(target, questRows, questIndex, ignoredCompletedCount);

    file.WriteLine("Umbrella Store Profile Export");
    file.WriteLine("============================");
    file.WriteLine("Player: %s", name);
    file.WriteLine("SteamID: %s", steamid);
    file.WriteLine("Credits: %d", snapshot.credits);
    file.WriteLine("");
    file.WriteLine("Inventory");
    file.WriteLine("- Owned items: %d", snapshot.owned_items);
    file.WriteLine("- Equipped items: %d", snapshot.equipped_items);
    file.WriteLine("");
    file.WriteLine("Economy");
    file.WriteLine("- Credits earned: %d", snapshot.credits_earned);
    file.WriteLine("- Credits spent: %d", snapshot.credits_spent);
    file.WriteLine("- Purchases: %d", snapshot.purchases_total);
    file.WriteLine("- Sales: %d", snapshot.sales_total);
    file.WriteLine("- Gifts sent: %d", snapshot.gifts_sent);
    file.WriteLine("- Gifts received: %d", snapshot.gifts_received);
    file.WriteLine("- Trades completed: %d", snapshot.trades_completed);
    file.WriteLine("");
    file.WriteLine("Progression");
    file.WriteLine("- Best daily streak: %d", snapshot.daily_best_streak);
    file.WriteLine("- Completed quests: %d", snapshot.quests_completed);
    file.WriteLine("");
    file.WriteLine("Casino summary");
    file.WriteLine("- Blackjack games/profit: %d / %d", snapshot.blackjack_games, snapshot.blackjack_profit);
    file.WriteLine("- Coinflip games/profit: %d / %d", snapshot.coinflip_games, snapshot.coinflip_profit);
    file.WriteLine("- Crash rounds/profit: %d / %d", snapshot.crash_rounds, snapshot.crash_profit);
    file.WriteLine("- Roulette games/profit: %d / %d", snapshot.roulette_games, snapshot.roulette_profit);
    file.WriteLine("");
    file.WriteLine("Quest progress");

    if (g_aQuestDefinitions != null && g_aQuestDefinitions.Length > 0)
    {
        StoreQuestDefinition definition;
        char questTitle[128];
        for (int i = 0; i < g_aQuestDefinitions.Length; i++)
        {
            g_aQuestDefinitions.GetArray(i, definition, sizeof(StoreQuestDefinition));
            int progress = 0, completedAt = 0, rewardedAt = 0, completionCount = 0;
            GetQuestSnapshotState(questRows, questIndex, definition.id, progress, completedAt, rewardedAt, completionCount);
            if (progress > definition.goal)
            {
                progress = definition.goal;
            }
            FormatQuestTitle(viewer > 0 ? viewer : target, definition, questTitle, sizeof(questTitle));
            file.WriteLine("- [%s] %s (%d/%d) completions=%d", (rewardedAt > 0) ? "done" : "open", questTitle, progress, definition.goal, completionCount);
        }
    }
    else
    {
        file.WriteLine("- No registered quests.");
    }

    delete questRows;
    delete questIndex;
    delete file;

    if (viewer > 0)
    {
        PrintStorePhrase(viewer, "%T", "Profile Export Saved", viewer, filePath);
        PrintToConsole(viewer, "Umbrella Store profile exported to: %s", filePath);
    }
    return true;
}

void ExportProfileSnapshot(int client)
{
    char filePath[PLATFORM_MAX_PATH];
    ExportProfileSnapshotInternal(client, client, filePath, sizeof(filePath));
}

void ShowQuestMenu(int client)
{
    Menu menu = new Menu(MenuHandler_QuestCategories);
    char title[192];
    int questCount = (g_aQuestDefinitions != null) ? g_aQuestDefinitions.Length : 0;

    Format(title, sizeof(title), "%T", "Quests Menu Title", client, questCount);
    menu.SetTitle(title);

    if (questCount <= 0)
    {
        AddMenuItemPhrase(menu, "empty", client, "Quests Empty", ITEMDRAW_DISABLED);
    }
    else
    {
        StoreQuestDefinition definition;
        StringMap seen = new StringMap();
        char category[64];
        char info[72];
        for (int i = 0; i < g_aQuestDefinitions.Length; i++)
        {
            g_aQuestDefinitions.GetArray(i, definition, sizeof(StoreQuestDefinition));
            FormatQuestText(client, definition.category, category, sizeof(category));

            int existing = 0;
            if (seen.GetValue(category, existing))
            {
                continue;
            }

            seen.SetValue(category, 1);
            strcopy(info, sizeof(info), definition.category);
            menu.AddItem(info, category);
        }

        delete seen;

        AddMenuItemPhrase(menu, "all", client, "Quests Category All");
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_QuestCategories(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowStoreMainMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[72];
        menu.GetItem(param2, info, sizeof(info));
        ShowQuestListMenu(param1, info);
    }

    return 0;
}

void ShowQuestListMenu(int client, const char[] categoryFilter)
{
    Menu menu = new Menu(MenuHandler_QuestList);
    char title[192];
    char categoryLabel[64];
    ArrayList questRows = new ArrayList(sizeof(StoreQuestProgressSnapshot));
    StringMap questIndex = new StringMap();
    int ignoredCompletedCount = 0;
    LoadQuestProgressSnapshot(client, questRows, questIndex, ignoredCompletedCount);

    if (StrEqual(categoryFilter, "all"))
    {
        Format(categoryLabel, sizeof(categoryLabel), "%T", "Quests Category All", client);
    }
    else
    {
        FormatQuestText(client, categoryFilter, categoryLabel, sizeof(categoryLabel));
    }

    Format(title, sizeof(title), "%T", "Quests Category Menu Title", client, categoryLabel);
    menu.SetTitle(title);

    bool added = false;
    StoreQuestDefinition definition;
    char questTitle[128];
    char rewardText[128];
    char display[256];
    char info[72];

    for (int i = 0; i < g_aQuestDefinitions.Length; i++)
    {
        g_aQuestDefinitions.GetArray(i, definition, sizeof(StoreQuestDefinition));
        if (!StrEqual(categoryFilter, "all") && !StrEqual(definition.category, categoryFilter))
        {
            continue;
        }

        int progress = 0;
        int completedAt = 0;
        int rewardedAt = 0;
        int completionCount = 0;
        GetQuestSnapshotState(questRows, questIndex, definition.id, progress, completedAt, rewardedAt, completionCount);

        if (progress > definition.goal)
        {
            progress = definition.goal;
        }

        FormatQuestTitle(client, definition, questTitle, sizeof(questTitle));
        FormatQuestRewardText(client, definition, rewardText, sizeof(rewardText));

        bool lockedByWindow = false;
        bool lockedByRequirement = false;
        bool maxedOut = false;
        GetQuestAvailabilityStateFromSnapshot(definition, rewardedAt, completionCount, questRows, questIndex, lockedByWindow, lockedByRequirement, maxedOut);

        if (rewardedAt > 0)
        {
            Format(display, sizeof(display), "%T", "Quest Entry Completed", client, questTitle, definition.goal, definition.goal, rewardText);
        }
        else if (lockedByWindow || lockedByRequirement || maxedOut)
        {
            Format(display, sizeof(display), "%T", "Quest Entry Locked", client, questTitle, progress, definition.goal, rewardText);
        }
        else
        {
            Format(display, sizeof(display), "%T", "Quest Entry In Progress", client, questTitle, progress, definition.goal, rewardText);
        }

        Format(info, sizeof(info), "quest:%s", definition.id);
        menu.AddItem(info, display);
        added = true;
    }

    if (!added)
    {
        AddMenuItemPhrase(menu, "empty", client, "Quests Empty", ITEMDRAW_DISABLED);
    }

    delete questRows;
    delete questIndex;
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_QuestList(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowQuestMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[72];
        menu.GetItem(param2, info, sizeof(info));
        if (StrContains(info, "quest:") == 0)
        {
            char questId[64];
            strcopy(questId, sizeof(questId), info[6]);
            ShowQuestDetailsMenu(param1, questId);
        }
    }

    return 0;
}

void ShowQuestDetailsMenu(int client, const char[] questId)
{
    StoreQuestDefinition definition;
    if (!FindQuestDefinition(questId, definition))
    {
        ShowQuestMenu(client);
        return;
    }

    Menu menu = new Menu(MenuHandler_QuestDetails);
    char title[192];
    char questTitle[128];
    char description[192];
    char rewardText[128];
    char display[256];

    FormatQuestTitle(client, definition, questTitle, sizeof(questTitle));
    Format(title, sizeof(title), "%T", "Quest Details Menu Title", client, questTitle);
    menu.SetTitle(title);

    ArrayList questRows = new ArrayList(sizeof(StoreQuestProgressSnapshot));
    StringMap questIndex = new StringMap();
    int ignoredCompletedCount = 0;
    LoadQuestProgressSnapshot(client, questRows, questIndex, ignoredCompletedCount);

    int progress = 0;
    int completedAt = 0;
    int rewardedAt = 0;
    int completionCount = 0;
    GetQuestSnapshotState(questRows, questIndex, definition.id, progress, completedAt, rewardedAt, completionCount);
    if (progress > definition.goal)
    {
        progress = definition.goal;
    }

    Format(display, sizeof(display), "%T", "Quest Details Progress", client, progress, definition.goal);
    AddMenuItemText(menu, "progress", display, ITEMDRAW_DISABLED);

    FormatQuestRewardText(client, definition, rewardText, sizeof(rewardText));
    Format(display, sizeof(display), "%T", "Quest Details Reward", client, rewardText);
    AddMenuItemText(menu, "reward", display, ITEMDRAW_DISABLED);

    if (definition.repeatable)
    {
        int maxCompletions = definition.max_completions;
        if (maxCompletions <= 0)
        {
            Format(display, sizeof(display), "%T", "Quest Details Repeatable Unlimited", client, completionCount);
        }
        else
        {
            Format(display, sizeof(display), "%T", "Quest Details Repeatable Limited", client, completionCount, maxCompletions);
        }
        AddMenuItemText(menu, "repeatable", display, ITEMDRAW_DISABLED);
    }

    FormatQuestText(client, definition.category, description, sizeof(description));
    Format(display, sizeof(display), "%T", "Quest Details Category", client, description);
    AddMenuItemText(menu, "category", display, ITEMDRAW_DISABLED);

    FormatQuestText(client, definition.description, description, sizeof(description));
    if (description[0] != '\0')
    {
        Format(display, sizeof(display), "%T", "Quest Details Description", client, description);
        AddMenuItemText(menu, "description", display, ITEMDRAW_DISABLED);
    }

    if (definition.requires_quest[0] != '\0')
    {
        char requiresText[128];
        StoreQuestDefinition requiredDefinition;
        if (FindQuestDefinition(definition.requires_quest, requiredDefinition))
        {
            FormatQuestTitle(client, requiredDefinition, requiresText, sizeof(requiresText));
        }
        else
        {
            FormatQuestText(client, definition.requires_quest, requiresText, sizeof(requiresText));
        }
        Format(display, sizeof(display), "%T", "Quest Details Requires", client, requiresText);
        AddMenuItemText(menu, "requires", display, ITEMDRAW_DISABLED);
    }

    if (definition.starts_at > 0 || definition.ends_at > 0)
    {
        char startText[64];
        char endText[64];
        if (definition.starts_at > 0)
        {
            FormatTime(startText, sizeof(startText), "%Y-%m-%d %H:%M", definition.starts_at);
        }
        else
        {
            strcopy(startText, sizeof(startText), "-");
        }

        if (definition.ends_at > 0)
        {
            FormatTime(endText, sizeof(endText), "%Y-%m-%d %H:%M", definition.ends_at);
        }
        else
        {
            strcopy(endText, sizeof(endText), "-");
        }

        Format(display, sizeof(display), "%T", "Quest Details Window", client, startText, endText);
        AddMenuItemText(menu, "window", display, ITEMDRAW_DISABLED);
    }

    bool lockedByWindow = false;
    bool lockedByRequirement = false;
    bool maxedOut = false;
    GetQuestAvailabilityStateFromSnapshot(definition, rewardedAt, completionCount, questRows, questIndex, lockedByWindow, lockedByRequirement, maxedOut);

    if (rewardedAt > 0 && !definition.repeatable)
    {
        AddMenuItemPhrase(menu, "state", client, "Quest Details State Completed", ITEMDRAW_DISABLED);
    }
    else if (maxedOut)
    {
        AddMenuItemPhrase(menu, "state", client, "Quest Details State Maxed", ITEMDRAW_DISABLED);
    }
    else if (lockedByRequirement)
    {
        AddMenuItemPhrase(menu, "state", client, "Quest Details State Locked", ITEMDRAW_DISABLED);
    }
    else if (lockedByWindow)
    {
        AddMenuItemPhrase(menu, "state", client, "Quest Details State Scheduled", ITEMDRAW_DISABLED);
    }
    else if (completedAt > 0)
    {
        AddMenuItemPhrase(menu, "state", client, "Quest Details State Ready", ITEMDRAW_DISABLED);
    }
    else
    {
        AddMenuItemPhrase(menu, "state", client, "Quest Details StateActive", ITEMDRAW_DISABLED);
    }

    delete questRows;
    delete questIndex;
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_QuestDetails(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowQuestMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

bool CreateMarketplaceListing(int client, const char[] itemId, int price)
{
    if (!IsMarketplaceEnabled() || !IsValidHumanClient(client) || !g_bIsLoaded[client] || g_DB == null || itemId[0] == '\0')
    {
        return false;
    }

    int minPrice = GetMarketplaceMinPrice();
    int maxPrice = GetMarketplaceMaxPrice();
    if (price < minPrice || (maxPrice > 0 && price > maxPrice))
    {
        PrintStorePhrase(client, "%T", "Market Price Invalid", client, minPrice, maxPrice);
        return false;
    }

    int index = FindInventoryIndexByItemId(client, itemId);
    if (index == -1)
    {
        PrintStorePhrase(client, "%T", "Item Not Owned", client);
        return false;
    }

    InventoryItem inv;
    g_hInventory[client].GetArray(index, inv, sizeof(InventoryItem));
    if (view_as<bool>(inv.is_equipped))
    {
        PrintStorePhrase(client, "%T", "Market Item Equipped", client);
        return false;
    }

    if (HasActiveMarketplaceListing(client, itemId))
    {
        PrintStorePhrase(client, "%T", "Market Item Listed Already", client);
        return false;
    }

    char steamid[32], safeSteamId[64], safeItemId[64], query[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));
    int now = GetTime();
    int expiresAt = now + (GetMarketplaceListingHours() * 3600);
    int feePercent = GetMarketplaceFeePercent();

    Format(query, sizeof(query),
        "INSERT INTO store_market_listings (seller_steamid, item_id, price, fee_percent, created_at, expires_at, sold_to, sold_at, cancelled_at) VALUES ('%s', '%s', %d, %d, %d, %d, '', 0, 0)",
        safeSteamId, safeItemId, price, feePercent, now, expiresAt);

    SQL_LockDatabase(g_DB);
    bool ok = SQL_FastQuery(g_DB, query);
    if (!ok)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("CreateMarketplaceListing", error);
    }
    SQL_UnlockDatabase(g_DB);

    if (!ok)
    {
        PrintStorePhrase(client, "%T", "Market Listing Failed", client);
        return false;
    }

    StoreItem item;
    FindStoreItemById(itemId, item);
    char priceText[32];
    FormatCreditsAmount(client, price, priceText, sizeof(priceText));
    PrintStorePhrase(client, "%T", "Market Listing Created", client, item.name, priceText);
    return true;
}

bool GetMarketplaceListingById(int listingId, char[] sellerSteamId, int sellerSteamMax, char[] sellerName, int sellerNameMax, char[] itemId, int itemIdMax, int &price, int &feePercent, int &createdAt, int &expiresAt, int &soldAt, int &cancelledAt, char[] soldTo, int soldToMax)
{
    sellerSteamId[0] = '\0';
    sellerName[0] = '\0';
    itemId[0] = '\0';
    soldTo[0] = '\0';
    price = 0;
    feePercent = 0;
    createdAt = 0;
    expiresAt = 0;
    soldAt = 0;
    cancelledAt = 0;

    if (g_DB == null || listingId <= 0)
    {
        return false;
    }

    char query[512];
    Format(query, sizeof(query),
        "SELECT l.seller_steamid, p.name, l.item_id, l.price, l.fee_percent, l.created_at, l.expires_at, l.sold_at, l.cancelled_at, l.sold_to "
        ... "FROM store_market_listings l LEFT JOIN store_players p ON l.seller_steamid = p.steamid WHERE l.id = %d",
        listingId);

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    if (results == null)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("GetMarketplaceListingById", error);
        SQL_UnlockDatabase(g_DB);
        return false;
    }

    bool found = false;
    if (results.FetchRow())
    {
        results.FetchString(0, sellerSteamId, sellerSteamMax);
        results.FetchString(1, sellerName, sellerNameMax);
        results.FetchString(2, itemId, itemIdMax);
        price = results.FetchInt(3);
        feePercent = results.FetchInt(4);
        createdAt = results.FetchInt(5);
        expiresAt = results.FetchInt(6);
        soldAt = results.FetchInt(7);
        cancelledAt = results.FetchInt(8);
        results.FetchString(9, soldTo, soldToMax);
        if (sellerName[0] == '\0')
        {
            strcopy(sellerName, sellerNameMax, sellerSteamId);
        }
        found = true;
    }

    delete results;
    SQL_UnlockDatabase(g_DB);
    return found;
}

bool ExecuteMarketplacePurchase(int buyer, int listingId)
{
    if (!IsMarketplaceEnabled() || !IsValidHumanClient(buyer) || !g_bIsLoaded[buyer] || g_DB == null || listingId <= 0)
    {
        return false;
    }

    char buyerSteamId[32], safeBuyerSteamId[64];
    if (!GetClientSteamIdSafe(buyer, buyerSteamId, sizeof(buyerSteamId)))
    {
        return false;
    }

    EscapeStringSafe(buyerSteamId, safeBuyerSteamId, sizeof(safeBuyerSteamId));

    if (!BeginLockedStoreTransaction("ExecuteMarketplacePurchase"))
    {
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    char query[768], sellerSteamId[32], sellerName[64], itemId[32], soldTo[32];
    int price = 0, feePercent = 0, expiresAt = 0, soldAt = 0, cancelledAt = 0;

    Format(query, sizeof(query),
        "SELECT l.seller_steamid, p.name, l.item_id, l.price, l.fee_percent, l.created_at, l.expires_at, l.sold_at, l.cancelled_at, l.sold_to "
        ... "FROM store_market_listings l LEFT JOIN store_players p ON l.seller_steamid = p.steamid WHERE l.id = %d",
        listingId);
    DBResultSet listingResults = SQL_Query(g_DB, query);
    if (listingResults == null || !listingResults.FetchRow())
    {
        if (listingResults != null)
        {
            delete listingResults;
        }
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    listingResults.FetchString(0, sellerSteamId, sizeof(sellerSteamId));
    listingResults.FetchString(1, sellerName, sizeof(sellerName));
    listingResults.FetchString(2, itemId, sizeof(itemId));
    price = listingResults.FetchInt(3);
    feePercent = listingResults.FetchInt(4);
    expiresAt = listingResults.FetchInt(6);
    soldAt = listingResults.FetchInt(7);
    cancelledAt = listingResults.FetchInt(8);
    listingResults.FetchString(9, soldTo, sizeof(soldTo));
    delete listingResults;

    if (sellerSteamId[0] == '\0' || itemId[0] == '\0' || soldAt > 0 || cancelledAt > 0 || expiresAt <= GetTime())
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    if (StrEqual(sellerSteamId, buyerSteamId))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Own", buyer);
        return false;
    }

    if (g_iCredits[buyer] < price)
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy No Credits", buyer);
        return false;
    }

    char safeSellerSteamId[64], safeItemId[64];
    EscapeStringSafe(sellerSteamId, safeSellerSteamId, sizeof(safeSellerSteamId));
    EscapeStringSafe(itemId, safeItemId, sizeof(safeItemId));

    Format(query, sizeof(query),
        "SELECT COUNT(*) FROM store_inventory WHERE steamid = '%s' AND item_id = '%s'",
        safeSellerSteamId, safeItemId);
    DBResultSet sellerInvResults = SQL_Query(g_DB, query);
    if (sellerInvResults == null || !sellerInvResults.FetchRow() || sellerInvResults.FetchInt(0) <= 0)
    {
        if (sellerInvResults != null)
        {
            delete sellerInvResults;
        }
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }
    delete sellerInvResults;

    Format(query, sizeof(query),
        "SELECT COUNT(*) FROM store_inventory WHERE steamid = '%s' AND item_id = '%s'",
        safeBuyerSteamId, safeItemId);
    DBResultSet buyerInvResults = SQL_Query(g_DB, query);
    if (buyerInvResults == null || !buyerInvResults.FetchRow() || buyerInvResults.FetchInt(0) > 0)
    {
        if (buyerInvResults != null)
        {
            delete buyerInvResults;
        }
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }
    delete buyerInvResults;

    int sellerCredits = 0;
    Format(query, sizeof(query),
        "SELECT credits FROM store_players WHERE steamid = '%s'",
        safeSellerSteamId);
    DBResultSet sellerCreditResults = SQL_Query(g_DB, query);
    if (sellerCreditResults == null || !sellerCreditResults.FetchRow())
    {
        if (sellerCreditResults != null)
        {
            delete sellerCreditResults;
        }
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }
    sellerCredits = sellerCreditResults.FetchInt(0);
    delete sellerCreditResults;

    int feeAmount = RoundToFloor(float(price * feePercent) / 100.0);
    int sellerNet = price - feeAmount;
    int buyerNewCredits = g_iCredits[buyer] - price;
    int sellerNewCredits = sellerCredits + sellerNet;

    char buyerPlayerQuery[512];
    if (!BuildPlayerUpsertQueryForCredits(buyer, buyerNewCredits, buyerPlayerQuery, sizeof(buyerPlayerQuery)))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    Format(query, sizeof(query),
        "UPDATE store_market_listings SET sold_to = '%s', sold_at = %d WHERE id = %d AND sold_at = 0 AND cancelled_at = 0",
        safeBuyerSteamId, GetTime(), listingId);
    if (!ExecuteLockedStoreQuery("ExecuteMarketplacePurchase", query, 1))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    Format(query, sizeof(query),
        "UPDATE store_inventory SET steamid = '%s', is_equipped = 0 WHERE steamid = '%s' AND item_id = '%s'",
        safeBuyerSteamId, safeSellerSteamId, safeItemId);
    if (!ExecuteLockedStoreQuery("ExecuteMarketplacePurchase", query, 1))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    if (!ExecuteLockedStoreQuery("ExecuteMarketplacePurchase", buyerPlayerQuery))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    Format(query, sizeof(query), "UPDATE store_players SET credits = %d WHERE steamid = '%s'", sellerNewCredits, safeSellerSteamId);
    if (!ExecuteLockedStoreQuery("ExecuteMarketplacePurchase", query, 1))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    Format(query, sizeof(query),
        "INSERT INTO store_market_sales (listing_id, seller_steamid, buyer_steamid, item_id, price, fee_amount, created_at) VALUES (%d, '%s', '%s', '%s', %d, %d, %d)",
        listingId, safeSellerSteamId, safeBuyerSteamId, safeItemId, price, feeAmount, GetTime());
    if (!ExecuteLockedStoreQuery("ExecuteMarketplacePurchase", query, 1))
    {
        RollbackLockedStoreTransaction("ExecuteMarketplacePurchase");
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    if (!CommitLockedStoreTransaction("ExecuteMarketplacePurchase"))
    {
        PrintStorePhrase(buyer, "%T", "Market Buy Failed", buyer);
        return false;
    }

    g_iCredits[buyer] = buyerNewCredits;
    ReportCreditsChanged(buyer, -price, "market_buy", false, true);
    SyncMarketplaceTransferInMemory(sellerSteamId, buyer, itemId, sellerNet);
    UpdatePlayerStat(buyer, "purchases_total", 1);

    StoreItem item;
    FindStoreItemById(itemId, item);
    char priceText[32];
    FormatCreditsAmount(buyer, price, priceText, sizeof(priceText));
    PrintStorePhrase(buyer, "%T", "Market Listing Bought", buyer, item.name, priceText, sellerName);

    int sellerClient = GetOnlineClientBySteamId(sellerSteamId);
    if (sellerClient > 0)
    {
        char sellerNetText[32];
        FormatCreditsAmount(sellerClient, sellerNet, sellerNetText, sizeof(sellerNetText));
        PrintStorePhrase(sellerClient, "%T", "Market Listing Sold Seller", sellerClient, item.name, sellerNetText, buyer);
        UpdatePlayerStat(sellerClient, "sales_total", 1);
    }
    else
    {
        LogCreditLedgerBySteamId(sellerSteamId, sellerNewCredits, sellerNet, "market_sale");
        TrackEconomyStatsBySteamId(sellerSteamId, sellerNet);
        UpdatePlayerStatBySteamId(sellerSteamId, "sales_total", 1);
    }

    return true;
}

bool CancelMarketplaceListing(int client, int listingId, bool notify = true)
{
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || g_DB == null || listingId <= 0)
    {
        return false;
    }

    char steamid[32], safeSteamId[64], query[320];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return false;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    Format(query, sizeof(query),
        "UPDATE store_market_listings SET cancelled_at = %d WHERE id = %d AND seller_steamid = '%s' AND sold_at = 0 AND cancelled_at = 0",
        GetTime(), listingId, safeSteamId);

    SQL_LockDatabase(g_DB);
    bool ok = SQL_FastQuery(g_DB, query);
    int affected = SQL_GetAffectedRows(g_DB);
    if (!ok)
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("CancelMarketplaceListing", error);
    }
    SQL_UnlockDatabase(g_DB);

    if (!ok || affected <= 0)
    {
        if (notify)
        {
            PrintStorePhrase(client, "%T", "Market Cancel Failed", client);
        }
        return false;
    }

    if (notify)
    {
        PrintStorePhrase(client, "%T", "Market Listing Cancelled", client);
    }
    return true;
}

void ShowMarketMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Market);
    SetMenuTitlePhrase(menu, client, "Market Menu Title");
    AddMenuItemPhrase(menu, "browse", client, "Market Menu Browse");
    AddMenuItemPhrase(menu, "sell", client, "Market Menu Sell");
    AddMenuItemPhrase(menu, "mine", client, "Market Menu My Listings");
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Market(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowStoreMainMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        if (StrEqual(info, "browse"))
        {
            ShowMarketplaceBrowseMenu(param1);
        }
        else if (StrEqual(info, "sell"))
        {
            ShowMarketplaceSellMenu(param1);
        }
        else if (StrEqual(info, "mine"))
        {
            ShowMarketplaceOwnListingsMenu(param1);
        }
    }
    return 0;
}

void ShowMarketplaceSellMenu(int client)
{
    Menu menu = new Menu(MenuHandler_MarketSell);
    SetMenuTitlePhrase(menu, client, "Market Sell Menu Title");

    bool added = false;
    InventoryItem inv;
    StoreItem item;
    for (int i = 0; i < g_hInventory[client].Length; i++)
    {
        g_hInventory[client].GetArray(i, inv, sizeof(InventoryItem));
        if (view_as<bool>(inv.is_equipped))
        {
            continue;
        }

        if (!FindStoreItemById(inv.item_id, item))
        {
            continue;
        }

        if (HasActiveMarketplaceListing(client, inv.item_id))
        {
            continue;
        }

        char display[128], suggestedPrice[32];
        FormatCreditsAmount(client, item.price, suggestedPrice, sizeof(suggestedPrice));
        Format(display, sizeof(display), "%s [%s]", item.name, suggestedPrice);
        menu.AddItem(item.id, display);
        added = true;
    }

    if (!added)
    {
        AddMenuItemPhrase(menu, "empty", client, "Market Sell Empty", ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MarketSell(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowMarketMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char itemId[32];
        menu.GetItem(param2, itemId, sizeof(itemId));
        strcopy(g_szPendingMarketItem[param1], sizeof(g_szPendingMarketItem[]), itemId);
        g_bAwaitingMarketPrice[param1] = true;
        PrintStorePhrase(param1, "%T", "Market Enter Price", param1, GetMarketplaceMinPrice(), GetMarketplaceMaxPrice());
    }
    return 0;
}

void ShowMarketplaceBrowseMenu(int client)
{
    Menu menu = new Menu(MenuHandler_MarketBrowse);
    SetMenuTitlePhrase(menu, client, "Market Browse Menu Title");

    char query[512];
    Format(query, sizeof(query),
        "SELECT l.id, l.item_id, p.name, l.seller_steamid, l.price FROM store_market_listings l "
        ... "LEFT JOIN store_players p ON l.seller_steamid = p.steamid "
        ... "WHERE l.sold_at = 0 AND l.cancelled_at = 0 AND l.expires_at > %d ORDER BY l.created_at DESC LIMIT 100",
        GetTime());

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    bool added = false;
    if (results != null)
    {
        StoreItem item;
        char itemId[32], sellerName[64], sellerSteamId[32], display[192], info[16], priceText[32];
        int listingId = 0;
        while (results.FetchRow())
        {
            listingId = results.FetchInt(0);
            results.FetchString(1, itemId, sizeof(itemId));
            results.FetchString(2, sellerName, sizeof(sellerName));
            results.FetchString(3, sellerSteamId, sizeof(sellerSteamId));
            int price = results.FetchInt(4);

            if (!FindStoreItemById(itemId, item))
            {
                continue;
            }

            if (sellerName[0] == '\0')
            {
                strcopy(sellerName, sizeof(sellerName), sellerSteamId);
            }

            FormatCreditsAmount(client, price, priceText, sizeof(priceText));
            Format(display, sizeof(display), "%T", "Market Listing Entry", client, item.name, sellerName, priceText);
            IntToString(listingId, info, sizeof(info));
            menu.AddItem(info, display);
            added = true;
        }
        delete results;
    }
    else
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("ShowMarketplaceBrowseMenu", error);
    }
    SQL_UnlockDatabase(g_DB);

    if (!added)
    {
        AddMenuItemPhrase(menu, "empty", client, "Market Browse Empty", ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MarketBrowse(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowMarketMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        ShowMarketplaceListingDetails(param1, StringToInt(info), false);
    }
    return 0;
}

void ShowMarketplaceOwnListingsMenu(int client)
{
    Menu menu = new Menu(MenuHandler_MarketOwnListings);
    SetMenuTitlePhrase(menu, client, "Market My Listings Title");

    char steamid[32], safeSteamId[64], query[512];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        delete menu;
        return;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    Format(query, sizeof(query),
        "SELECT id, item_id, price FROM store_market_listings WHERE seller_steamid = '%s' AND sold_at = 0 AND cancelled_at = 0 AND expires_at > %d ORDER BY created_at DESC LIMIT 100",
        safeSteamId, GetTime());

    SQL_LockDatabase(g_DB);
    DBResultSet results = SQL_Query(g_DB, query);
    bool added = false;
    if (results != null)
    {
        StoreItem item;
        char itemId[32], display[160], info[16], priceText[32];
        while (results.FetchRow())
        {
            int listingId = results.FetchInt(0);
            results.FetchString(1, itemId, sizeof(itemId));
            int price = results.FetchInt(2);
            if (!FindStoreItemById(itemId, item))
            {
                continue;
            }

            FormatCreditsAmount(client, price, priceText, sizeof(priceText));
            Format(display, sizeof(display), "%T", "Market My Listing Entry", client, item.name, priceText);
            IntToString(listingId, info, sizeof(info));
            menu.AddItem(info, display);
            added = true;
        }
        delete results;
    }
    else
    {
        char error[256];
        SQL_GetError(g_DB, error, sizeof(error));
        LogStoreError("ShowMarketplaceOwnListingsMenu", error);
    }
    SQL_UnlockDatabase(g_DB);

    if (!added)
    {
        AddMenuItemPhrase(menu, "empty", client, "Market My Listings Empty", ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MarketOwnListings(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowMarketMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        ShowMarketplaceListingDetails(param1, StringToInt(info), true);
    }
    return 0;
}

void ShowMarketplaceListingDetails(int client, int listingId, bool ownListing)
{
    char sellerSteamId[32], sellerName[64], itemId[32], soldTo[32];
    int price = 0, feePercent = 0, createdAt = 0, expiresAt = 0, soldAt = 0, cancelledAt = 0;
    if (!GetMarketplaceListingById(listingId, sellerSteamId, sizeof(sellerSteamId), sellerName, sizeof(sellerName), itemId, sizeof(itemId), price, feePercent, createdAt, expiresAt, soldAt, cancelledAt, soldTo, sizeof(soldTo)))
    {
        ShowMarketMenu(client);
        return;
    }

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        ShowMarketMenu(client);
        return;
    }

    Menu menu = new Menu(MenuHandler_MarketListingDetails);
    char title[192], priceText[32], display[192], whenText[64], info[32];
    Format(title, sizeof(title), "%T", "Market Listing Title", client, item.name);
    menu.SetTitle(title);

    Format(display, sizeof(display), "%T", "Market Listing Seller", client, sellerName);
    AddMenuItemText(menu, "seller", display, ITEMDRAW_DISABLED);

    FormatCreditsAmount(client, price, priceText, sizeof(priceText));
    Format(display, sizeof(display), "%T", "Market Listing Price", client, priceText);
    AddMenuItemText(menu, "price", display, ITEMDRAW_DISABLED);

    int feeAmount = RoundToFloor(float(price * feePercent) / 100.0);
    int netAmount = price - feeAmount;
    FormatCreditsAmount(client, feeAmount, priceText, sizeof(priceText));
    Format(display, sizeof(display), "%T", "Market Listing Fee", client, priceText, feePercent);
    AddMenuItemText(menu, "fee", display, ITEMDRAW_DISABLED);

    FormatCreditsAmount(client, netAmount, priceText, sizeof(priceText));
    Format(display, sizeof(display), "%T", "Market Listing Net", client, priceText);
    AddMenuItemText(menu, "net", display, ITEMDRAW_DISABLED);

    FormatTime(whenText, sizeof(whenText), "%Y-%m-%d %H:%M", expiresAt);
    Format(display, sizeof(display), "%T", "Market Listing Expires", client, whenText);
    AddMenuItemText(menu, "expires", display, ITEMDRAW_DISABLED);

    IntToString(listingId, info, sizeof(info));
    if (ownListing)
    {
        AddMenuItemPhrase(menu, info, client, "Market Listing Cancel");
    }
    else
    {
        AddMenuItemPhrase(menu, info, client, "Market Listing Buy");
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MarketListingDetails(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowMarketMenu(param1);
    }
    else if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        int listingId = StringToInt(info);

        char sellerSteamId[32], sellerName[64], itemId[32], soldTo[32], mySteamId[32];
        int price = 0, feePercent = 0, createdAt = 0, expiresAt = 0, soldAt = 0, cancelledAt = 0;
        if (!GetMarketplaceListingById(listingId, sellerSteamId, sizeof(sellerSteamId), sellerName, sizeof(sellerName), itemId, sizeof(itemId), price, feePercent, createdAt, expiresAt, soldAt, cancelledAt, soldTo, sizeof(soldTo)))
        {
            ShowMarketMenu(param1);
            return 0;
        }

        bool ownListing = GetClientSteamIdSafe(param1, mySteamId, sizeof(mySteamId)) && StrEqual(mySteamId, sellerSteamId);
        if (ownListing)
        {
            CancelMarketplaceListing(param1, listingId, true);
            ShowMarketplaceOwnListingsMenu(param1);
        }
        else
        {
            ExecuteMarketplacePurchase(param1, listingId);
            ShowMarketplaceBrowseMenu(param1);
        }
    }
    return 0;
}

void ShowProfileLedgerMenu(int client)
{
    if (g_DB == null)
    {
        PrintStorePhrase(client, "%T", "Leaderboard Load Failed", client);
        return;
    }

    char steamid[32], safeSteamId[64], query[256];
    if (!GetClientSteamIdSafe(client, steamid, sizeof(steamid)))
    {
        return;
    }

    EscapeStringSafe(steamid, safeSteamId, sizeof(safeSteamId));
    Format(query, sizeof(query),
        "SELECT amount, reason, balance_after, created_at FROM store_credits_ledger WHERE steamid = '%s' ORDER BY id DESC LIMIT 10",
        safeSteamId);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    g_DB.Query(OnProfileLedgerLoaded, query, pack);
}

public void OnProfileLedgerLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userid = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (db == null || results == null || error[0] != '\0')
    {
        LogStoreError("OnProfileLedgerLoaded", error);
        PrintStorePhrase(client, "%T", "Leaderboard Load Failed", client);
        return;
    }

    Menu menu = new Menu(MenuHandler_ProfileLedger);
    SetMenuTitlePhrase(menu, client, "Profile Ledger Menu Title");

    bool added = false;
    int amount, balanceAfter, createdAt;
    char reason[96], display[256], amountText[32], balanceText[32], when[32];

    while (results.FetchRow())
    {
        amount = results.FetchInt(0);
        results.FetchString(1, reason, sizeof(reason));
        balanceAfter = results.FetchInt(2);
        createdAt = results.FetchInt(3);

        FormatNumberDots(amount, amountText, sizeof(amountText));
        FormatNumberDots(balanceAfter, balanceText, sizeof(balanceText));
        FormatTime(when, sizeof(when), "%d/%m %H:%M", createdAt);
        Format(display, sizeof(display), "%T", "Profile Ledger Entry", client, amountText, reason, balanceText, when);
        menu.AddItem("entry", display, ITEMDRAW_DISABLED);
        added = true;
    }

    if (!added)
    {
        AddMenuItemPhrase(menu, "empty", client, "Profile Ledger Empty", ITEMDRAW_DISABLED);
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ProfileLedger(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowProfileMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
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

        if (item.hidden || !IsItemActiveForNow(item))
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
        FormatCreditsAmount(client, GetItemSellPrice(item), refundText, sizeof(refundText));
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

    if (HasActiveMarketplaceListing(client, itemId))
    {
        PrintStorePhrase(client, "%T", "Market Item Listed Already", client);
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

    if (HasActiveMarketplaceListing(client, itemId))
    {
        PrintStorePhrase(client, "%T", "Market Item Listed Already", client);
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
        ReportCreditsChanged(client, -amount, "gift_credits_sent", false, false);
        ReportCreditsChanged(target, amount, "gift_credits_received", false, false);
        UpdatePlayerStat(client, "gifts_sent", 1);
        UpdatePlayerStat(target, "gifts_received", 1);
        SavePlayer(client);
        SavePlayer(target);

        PrintStorePhrase(client, "%T", "Gift Credits Sent", client, amount, target);
        PrintStorePhrase(target, "%T", "Gift Credits Received", target, client, amount);
        return Plugin_Handled;
    }

    if (g_szLastDetailItem[client][0] != '\0' && PlayerOwnsItem(client, g_szLastDetailItem[client]))
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
    ReplyStoreText(client, msg);
}

bool ResolveSingleStoreTarget(int admin, const char[] pattern, int &target)
{
    target = 0;

    int targets[MAXPLAYERS];
    int count = 0;
    if (!TryResolveCreditTargets(admin, pattern, targets, count) || count != 1)
    {
        return false;
    }

    target = targets[0];
    return true;
}

void ReplyStoreAdminUsage(int client, const char[] phrase)
{
    char msg[192];
    Format(msg, sizeof(msg), "%T", phrase, client);
    ReplaceColorTags(msg, sizeof(msg));
    ReplyStoreText(client, msg);
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

void RequestLeaderboardMenu(int client, const char[] query, const char[] titlePhrase, const char[] entryPhrase, bool backToHub = false)
{
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(backToHub ? 1 : 0);
    pack.WriteString(titlePhrase);
    if (entryPhrase[0] != '\0' && TranslationPhraseExists(entryPhrase))
    {
        pack.WriteString(entryPhrase);
    }
    else
    {
        pack.WriteString("Top Profit Entry");
    }
    g_DB.Query(OnLeaderboardLoaded, query, pack);
}

public void OnLeaderboardLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userid = pack.ReadCell();
    bool backToHub = view_as<bool>(pack.ReadCell());
    char titlePhrase[64], entryPhrase[64];
    pack.ReadString(titlePhrase, sizeof(titlePhrase));
    pack.ReadString(entryPhrase, sizeof(entryPhrase));
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    if (error[0] != '\0' || results == null)
    {
        LogStoreError("OnLeaderboardLoaded", error);
        PrintStorePhrase(client, "%T", "Leaderboard Load Failed", client);
        return;
    }

    Menu menu = new Menu(backToHub ? MenuHandler_LeaderboardHubView : MenuHandler_TopCredits);
    char title[192];
    FormatQuestText(client, titlePhrase, title, sizeof(title));
    menu.SetTitle(title);

    char playerName[64];
    int metric;
    char display[160];
    char info[8];
    int pos = 1;

    while (results.FetchRow())
    {
        results.FetchString(0, playerName, sizeof(playerName));
        metric = results.FetchInt(1);

        char metricText[32];
        FormatNumberDots(metric, metricText, sizeof(metricText));
        Format(display, sizeof(display), "%T", entryPhrase, client, pos, playerName, metricText);
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

void OpenTopCreditsLeaderboard(int client, bool backToHub = false)
{
    char query[256];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT name, credits FROM store_players ORDER BY credits DESC, name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT name, credits FROM store_players ORDER BY credits DESC, name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Credits Menu Title", "Top Credits Entry", backToHub);
}

void OpenTopProfitLeaderboard(int client, bool backToHub = false)
{
    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, COALESCE(SUM(CASE WHEN s.stat_key = 'credits_earned' THEN s.stat_value WHEN s.stat_key = 'credits_spent' THEN -s.stat_value ELSE 0 END), 0) AS metric "
            ... "FROM store_players p LEFT JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key IN ('credits_earned', 'credits_spent') "
            ... "GROUP BY p.steamid, p.name ORDER BY metric DESC, p.name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, COALESCE(SUM(CASE WHEN s.stat_key = 'credits_earned' THEN s.stat_value WHEN s.stat_key = 'credits_spent' THEN -s.stat_value ELSE 0 END), 0) AS metric "
            ... "FROM store_players p LEFT JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key IN ('credits_earned', 'credits_spent') "
            ... "GROUP BY p.steamid, p.name ORDER BY metric DESC, p.name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Profit Menu Title", "Top Profit Entry", backToHub);
}

void OpenTopDailyLeaderboard(int client, bool backToHub = false)
{
    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'daily_best_streak' "
            ... "WHERE s.stat_value > 0 ORDER BY s.stat_value DESC, p.name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'daily_best_streak' "
            ... "WHERE s.stat_value > 0 ORDER BY s.stat_value DESC, p.name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Daily Menu Title", "Top Daily Entry", backToHub);
}

void OpenTopBlackjackLeaderboard(int client, bool backToHub = false)
{
    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'blackjack_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'blackjack_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Blackjack Profit Menu Title", "Top Profit Entry", backToHub);
}

void OpenTopCoinflipLeaderboard(int client, bool backToHub = false)
{
    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'coinflip_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'coinflip_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Coinflip Profit Menu Title", "Top Profit Entry", backToHub);
}

void OpenTopCrashLeaderboard(int client, bool backToHub = false)
{
    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'crash_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'crash_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Crash Profit Menu Title", "Top Profit Entry", backToHub);
}

void OpenTopRouletteLeaderboard(int client, bool backToHub = false)
{
    char query[512];
    if (g_bIsMySQL)
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'roulette_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name ASC LIMIT 10");
    }
    else
    {
        Format(query, sizeof(query),
            "SELECT p.name, s.stat_value FROM store_players p "
            ... "INNER JOIN store_player_stats s ON p.steamid = s.steamid AND s.stat_key = 'roulette_profit' "
            ... "WHERE s.stat_value <> 0 ORDER BY s.stat_value DESC, p.name COLLATE NOCASE ASC LIMIT 10");
    }

    RequestLeaderboardMenu(client, query, "Top Roulette Profit Menu Title", "Top Profit Entry", backToHub);
}

public Action Cmd_TopProfit(int client, int args)
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
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopProfitLeaderboard(client, false);
    return Plugin_Handled;
}

public Action Cmd_TopDaily(int client, int args)
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
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopDailyLeaderboard(client, false);
    return Plugin_Handled;
}

public Action Cmd_TopBlackjack(int client, int args)
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
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopBlackjackLeaderboard(client, false);
    return Plugin_Handled;
}

public Action Cmd_TopCoinflip(int client, int args)
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
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopCoinflipLeaderboard(client, false);
    return Plugin_Handled;
}

public Action Cmd_TopCrash(int client, int args)
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
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopCrashLeaderboard(client, false);
    return Plugin_Handled;
}

public Action Cmd_TopRoulette(int client, int args)
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
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopRouletteLeaderboard(client, false);
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
        ReplyStoreText(client, msg);
        return Plugin_Handled;
    }

    OpenTopCreditsLeaderboard(client, false);
    return Plugin_Handled;
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

public int MenuHandler_LeaderboardHubView(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowLeaderboardsMenu(param1);
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
            ReplaceString(buffer, sizeof(buffer), "[Umbrella Store]", " {purple}[Umbrella Store]{default}");
        }
        CReplyToCommand(client, "%s", buffer);
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
        ReplyStorePhrase(client, "%T", "Admin Give Usage", client);
        return Plugin_Handled;
    }

    char arg1[64], arg2[16];
    GetCmdArg(1, arg1, sizeof(arg1));
    GetCmdArg(2, arg2, sizeof(arg2));

    int amount = StringToInt(arg2);
    if (amount <= 0)
    {
        ReplyStorePhrase(client, "%T", "Admin Amount Positive", client);
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
        ReportCreditsChanged(target, amount, "admin_give", false, false);
        SavePlayer(target);
    }

    char amountText[32];
    FormatNumberDots(amount, amountText, sizeof(amountText));

    if (count == 1)
    {
        ReplyStorePhrase(client, "%T", "Admin Give Single", client, amountText, targets[0]);
    }
    else
    {
        ReplyStorePhrase(client, "%T", "Admin Give Multi", client, amountText, count);
    }

    return Plugin_Handled;
}

public Action Cmd_SetCredits(int client, int args)
{
    if (args < 2)
    {
        ReplyStorePhrase(client, "%T", "Admin Set Usage", client);
        return Plugin_Handled;
    }

    char arg1[64], arg2[16];
    GetCmdArg(1, arg1, sizeof(arg1));
    GetCmdArg(2, arg2, sizeof(arg2));

    int amount = StringToInt(arg2);
    if (amount < 0)
    {
        ReplyStorePhrase(client, "%T", "Admin Amount NonNegative", client);
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
        ReportCreditsChanged(target, delta, "admin_set", false, false);
        SavePlayer(target);
    }

    char amountText[32];
    FormatNumberDots(amount, amountText, sizeof(amountText));

    if (count == 1)
    {
        ReplyStorePhrase(client, "%T", "Admin Set Single", client, amountText, targets[0]);
    }
    else
    {
        ReplyStorePhrase(client, "%T", "Admin Set Multi", client, amountText, count);
    }

    return Plugin_Handled;
}

public Action Cmd_StoreDebug(int client, int args)
{
    if (args < 1)
    {
        ReplyStoreAdminUsage(client, "Admin Debug Usage");
        return Plugin_Handled;
    }

    char argTarget[64], steamid[32], creditsText[32], amountTextA[32], amountTextB[32];
    GetCmdArg(1, argTarget, sizeof(argTarget));

    int target = 0;
    if (!ResolveSingleStoreTarget(client, argTarget, target))
    {
        ReplyAdminTargetNotFound(client, argTarget);
        return Plugin_Handled;
    }

    StoreProfileSnapshot snapshot;
    BuildProfileSnapshot(target, snapshot);
    GetClientSteamIdSafe(target, steamid, sizeof(steamid));

    ReplyStorePhrase(client, "%T", "Admin Debug Header", client, target, steamid);
    ReplyStorePhrase(client, "%T", "Admin Debug Identity", client,
        g_bIsLoaded[target], g_bIsLoading[target], snapshot.credits, snapshot.owned_items, snapshot.equipped_items);

    FormatNumberDots(snapshot.credits_earned, amountTextA, sizeof(amountTextA));
    FormatNumberDots(snapshot.credits_spent, amountTextB, sizeof(amountTextB));
    ReplyStorePhrase(client, "%T", "Admin Debug Economy", client,
        amountTextA, amountTextB, snapshot.purchases_total, snapshot.sales_total, snapshot.gifts_sent, snapshot.gifts_received, snapshot.trades_completed);

    FormatNumberDots(snapshot.total_casino_profit, creditsText, sizeof(creditsText));
    ReplyStorePhrase(client, "%T", "Admin Debug Progress", client,
        snapshot.daily_best_streak, snapshot.quests_completed, snapshot.total_casino_activity, creditsText);

    FormatNumberDots(snapshot.blackjack_profit, amountTextA, sizeof(amountTextA));
    FormatNumberDots(snapshot.coinflip_profit, amountTextB, sizeof(amountTextB));
    ReplyStorePhrase(client, "%T", "Admin Debug Casino A", client,
        snapshot.blackjack_games, amountTextA, snapshot.coinflip_games, amountTextB);

    FormatNumberDots(snapshot.crash_profit, amountTextA, sizeof(amountTextA));
    FormatNumberDots(snapshot.roulette_profit, amountTextB, sizeof(amountTextB));
    ReplyStorePhrase(client, "%T", "Admin Debug Casino B", client,
        snapshot.crash_rounds, amountTextA, snapshot.roulette_games, amountTextB);
    return Plugin_Handled;
}

public Action Cmd_StoreQuestsDebug(int client, int args)
{
    if (args < 1)
    {
        ReplyStoreAdminUsage(client, "Admin Quests Debug Usage");
        return Plugin_Handled;
    }

    char argTarget[64];
    GetCmdArg(1, argTarget, sizeof(argTarget));

    int target = 0;
    if (!ResolveSingleStoreTarget(client, argTarget, target))
    {
        ReplyAdminTargetNotFound(client, argTarget);
        return Plugin_Handled;
    }

    ArrayList questRows = new ArrayList(sizeof(StoreQuestProgressSnapshot));
    StringMap questIndex = new StringMap();
    int completedCount = 0;
    LoadQuestProgressSnapshot(target, questRows, questIndex, completedCount);

    ReplyStorePhrase(client, "%T", "Admin Quests Debug Header", client, target);
    ReplyStorePhrase(client, "%T", "Admin Quests Debug Summary", client, (g_aQuestDefinitions != null) ? g_aQuestDefinitions.Length : 0, completedCount);

    if (g_aQuestDefinitions != null)
    {
        StoreQuestDefinition definition;
        for (int i = 0; i < g_aQuestDefinitions.Length; i++)
        {
            g_aQuestDefinitions.GetArray(i, definition, sizeof(StoreQuestDefinition));

            int progress = 0, completedAt = 0, rewardedAt = 0, completionCount = 0;
            GetQuestSnapshotState(questRows, questIndex, definition.id, progress, completedAt, rewardedAt, completionCount);

            bool lockedByWindow = false;
            bool lockedByRequirement = false;
            bool maxedOut = false;
            GetQuestAvailabilityStateFromSnapshot(definition, rewardedAt, completionCount, questRows, questIndex, lockedByWindow, lockedByRequirement, maxedOut);

            ReplyStorePhrase(client, "%T", "Admin Quest Debug Entry", client,
                definition.id, progress, definition.goal, (rewardedAt > 0), definition.repeatable, completionCount, definition.max_completions,
                lockedByWindow, lockedByRequirement, maxedOut);
        }
    }

    delete questRows;
    delete questIndex;
    return Plugin_Handled;
}

public Action Cmd_StoreExportTarget(int client, int args)
{
    if (args < 1)
    {
        ReplyStoreAdminUsage(client, "Admin Export Usage");
        return Plugin_Handled;
    }

    char argTarget[64];
    GetCmdArg(1, argTarget, sizeof(argTarget));

    int target = 0;
    if (!ResolveSingleStoreTarget(client, argTarget, target))
    {
        ReplyAdminTargetNotFound(client, argTarget);
        return Plugin_Handled;
    }

    char filePath[PLATFORM_MAX_PATH];
    if (!ExportProfileSnapshotInternal(client, target, filePath, sizeof(filePath)))
    {
        ReplyStoreAdminUsage(client, "Admin Export Failed");
        return Plugin_Handled;
    }

    ReplyStorePhrase(client, "%T", "Admin Export Target Success", client, target, filePath);
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
    ReportCreditsChanged(client, delta, "api_set", false, false);
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
    ReportCreditsChanged(client, -amount, "api_take", false, false);
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

public any Native_US_GetApiVersion(Handle plugin, int numParams)
{
    return STORE_API_VERSION;
}

public any Native_US_OpenStoreMenu(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!IsValidHumanClient(client) || !g_bIsLoaded[client] || !EnsureStoreEnabledForClient(client))
    {
        return false;
    }

    ShowStoreMainMenu(client);
    return true;
}

public any Native_US_RegisterMenuSection(Handle plugin, int numParams)
{
    char id[32], title[64], command[64];
    int sortOrder = (numParams >= 4) ? GetNativeCell(4) : 0;
    GetNativeString(1, id, sizeof(id));
    GetNativeString(2, title, sizeof(title));
    GetNativeString(3, command, sizeof(command));
    return RegisterMenuSectionEntry(id, title, command, sortOrder);
}

public any Native_US_UnregisterMenuSection(Handle plugin, int numParams)
{
    char id[32];
    GetNativeString(1, id, sizeof(id));
    return UnregisterMenuSectionEntry(id);
}

public any Native_US_GetItemCount(Handle plugin, int numParams)
{
    return (g_aItems != null) ? g_aItems.Length : 0;
}

public any Native_US_GetItemIdByIndex(Handle plugin, int numParams)
{
    int index = GetNativeCell(1);
    int maxlen = GetNativeCell(3);
    if (g_aItems == null || index < 0 || index >= g_aItems.Length || maxlen <= 0)
    {
        return false;
    }

    StoreItem item;
    g_aItems.GetArray(index, item, sizeof(StoreItem));
    SetNativeString(2, item.id, maxlen, true);
    return true;
}

public any Native_US_GetItemInfo(Handle plugin, int numParams)
{
    char itemId[64], category[32];
    GetNativeString(1, itemId, sizeof(itemId));

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        return false;
    }

    GetItemCategory(item, category, sizeof(category));
    SetNativeString(2, item.name, GetNativeCell(3), true);
    SetNativeString(4, item.type, GetNativeCell(5), true);
    SetNativeCellRef(6, item.price);
    SetNativeCellRef(7, item.team);
    SetNativeString(8, category, GetNativeCell(9), true);
    return true;
}

public any Native_US_GetItemType(Handle plugin, int numParams)
{
    char itemId[64];
    GetNativeString(1, itemId, sizeof(itemId));

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        return false;
    }

    SetNativeString(2, item.type, GetNativeCell(3), true);
    return true;
}

public any Native_US_GetItemPrice(Handle plugin, int numParams)
{
    char itemId[64];
    GetNativeString(1, itemId, sizeof(itemId));

    StoreItem item;
    if (!FindStoreItemById(itemId, item))
    {
        return -1;
    }

    return item.price;
}

public any Native_US_GetEquippedItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char type[32], itemId[32];
    GetNativeString(2, type, sizeof(type));

    if (!GetEquippedItemByType(client, type, itemId, sizeof(itemId)))
    {
        return false;
    }

    SetNativeString(3, itemId, GetNativeCell(4), true);
    return true;
}

public any Native_US_CanPurchaseItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64], reason[64];
    GetNativeString(2, itemId, sizeof(itemId));

    bool result = CanPurchaseItemEx(client, itemId, reason, sizeof(reason));
    SetNativeString(3, reason, GetNativeCell(4), true);
    return result;
}

public any Native_US_TryPurchaseItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64];
    bool equipAfterPurchase = (numParams >= 3) ? view_as<bool>(GetNativeCell(3)) : false;
    bool notify = (numParams >= 4) ? view_as<bool>(GetNativeCell(4)) : true;
    GetNativeString(2, itemId, sizeof(itemId));
    return BuyItem(client, itemId, equipAfterPurchase, notify);
}

public any Native_US_CanEquipItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64], reason[64];
    GetNativeString(2, itemId, sizeof(itemId));

    bool result = CanEquipItemEx(client, itemId, reason, sizeof(reason), false);
    SetNativeString(3, reason, GetNativeCell(4), true);
    return result;
}

public any Native_US_TryEquipItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemId[64];
    bool notify = (numParams >= 3) ? view_as<bool>(GetNativeCell(3)) : true;
    GetNativeString(2, itemId, sizeof(itemId));
    return SetItemEquipped(client, itemId, true, notify, true);
}

public any Native_US_RegisterItemType(Handle plugin, int numParams)
{
    char type[32], category[32];
    bool equippable = (numParams >= 3) ? view_as<bool>(GetNativeCell(3)) : true;
    bool exclusive = (numParams >= 4) ? view_as<bool>(GetNativeCell(4)) : false;
    GetNativeString(1, type, sizeof(type));
    GetNativeString(2, category, sizeof(category));
    return RegisterItemTypeInternal(type, category, equippable, exclusive, false);
}

public any Native_US_UnregisterItemType(Handle plugin, int numParams)
{
    char type[32];
    GetNativeString(1, type, sizeof(type));
    return UnregisterItemTypeInternal(type, false);
}

public any Native_US_GetItemMetadata(Handle plugin, int numParams)
{
    char itemId[64], key[64], value[256];
    GetNativeString(1, itemId, sizeof(itemId));
    GetNativeString(2, key, sizeof(key));

    if (!GetItemMetadataValue(itemId, key, value, sizeof(value)))
    {
        return false;
    }

    SetNativeString(3, value, GetNativeCell(4), true);
    return true;
}

public any Native_US_IsDatabaseReady(Handle plugin, int numParams)
{
    return (g_DB != null && g_bLateDatabaseReady);
}

public any Native_US_GetDatabaseConfig(Handle plugin, int numParams)
{
    char dbConfig[64];
    GetDatabaseConfigName(dbConfig, sizeof(dbConfig));
    SetNativeString(1, dbConfig, GetNativeCell(2), true);
    return (dbConfig[0] != '\0');
}

public any Native_US_IsMySQL(Handle plugin, int numParams)
{
    return g_bIsMySQL;
}

public any Native_US_GetDatabaseHandle(Handle plugin, int numParams)
{
    if (g_DB == null)
    {
        return INVALID_HANDLE;
    }

    return CloneHandle(g_DB, plugin);
}

public any Native_US_DB_Escape(Handle plugin, int numParams)
{
    char input[256], output[512];
    GetNativeString(1, input, sizeof(input));

    if (g_DB == null)
    {
        return false;
    }

    g_DB.Escape(input, output, sizeof(output));
    SetNativeString(2, output, GetNativeCell(3), true);
    return true;
}

public any Native_US_DB_EnsureTable(Handle plugin, int numParams)
{
    char tableId[64], mysqlQuery[1024], sqliteQuery[1024];
    GetNativeString(1, tableId, sizeof(tableId));
    GetNativeString(2, mysqlQuery, sizeof(mysqlQuery));
    GetNativeString(3, sqliteQuery, sizeof(sqliteQuery));
    return EnsureSharedTableInternal(tableId, mysqlQuery, sqliteQuery);
}

public any Native_US_RegisterStatKey(Handle plugin, int numParams)
{
    char statKey[64];
    GetNativeString(1, statKey, sizeof(statKey));
    return RegisterStatKeyInternal(statKey);
}

public any Native_US_AddStat(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int amount = (numParams >= 3) ? GetNativeCell(3) : 1;
    char statKey[64];
    GetNativeString(2, statKey, sizeof(statKey));
    return UpdatePlayerStat(client, statKey, amount, false);
}

public any Native_US_SetStatMax(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int value = GetNativeCell(3);
    char statKey[64];
    GetNativeString(2, statKey, sizeof(statKey));
    return UpdatePlayerStat(client, statKey, value, true);
}

public any Native_US_RegisterQuest(Handle plugin, int numParams)
{
    char questId[64], title[96];
    int goal = GetNativeCell(3);
    int rewardCredits = (numParams >= 4) ? GetNativeCell(4) : 0;
    GetNativeString(1, questId, sizeof(questId));
    GetNativeString(2, title, sizeof(title));
    return RegisterQuestInternal(questId, title, goal, rewardCredits);
}

public any Native_US_RegisterQuestEx(Handle plugin, int numParams)
{
    StoreQuestDefinition definition;
    GetNativeString(1, definition.id, sizeof(definition.id));
    GetNativeString(2, definition.title, sizeof(definition.title));
    definition.goal = GetNativeCell(3);
    definition.reward_credits = (numParams >= 4) ? GetNativeCell(4) : 0;
    if (numParams >= 5)
    {
        GetNativeString(5, definition.reward_item, sizeof(definition.reward_item));
    }
    else
    {
        definition.reward_item[0] = '\0';
    }
    definition.reward_item_equip = (numParams >= 6) ? GetNativeCell(6) : 0;
    if (numParams >= 7)
    {
        GetNativeString(7, definition.category, sizeof(definition.category));
    }
    else
    {
        strcopy(definition.category, sizeof(definition.category), "Quest Category General");
    }
    if (numParams >= 8)
    {
        GetNativeString(8, definition.description, sizeof(definition.description));
    }
    else
    {
        definition.description[0] = '\0';
    }
    definition.repeatable = (numParams >= 9) ? GetNativeCell(9) : 0;
    definition.max_completions = (numParams >= 10) ? GetNativeCell(10) : (definition.repeatable ? -1 : 1);
    if (numParams >= 11)
    {
        GetNativeString(11, definition.requires_quest, sizeof(definition.requires_quest));
    }
    else
    {
        definition.requires_quest[0] = '\0';
    }
    definition.starts_at = (numParams >= 12) ? GetNativeCell(12) : 0;
    definition.ends_at = (numParams >= 13) ? GetNativeCell(13) : 0;

    return RegisterQuestDefinitionInternal(definition);
}

public any Native_US_UnregisterQuest(Handle plugin, int numParams)
{
    char questId[64];
    GetNativeString(1, questId, sizeof(questId));
    return UnregisterQuestInternal(questId);
}

public any Native_US_AdvanceQuestProgress(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int amount = (numParams >= 3) ? GetNativeCell(3) : 1;
    char questId[64];
    GetNativeString(2, questId, sizeof(questId));
    return UpdateQuestProgressInternal(client, questId, amount, false);
}

public any Native_US_SetQuestProgressMax(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int value = GetNativeCell(3);
    char questId[64];
    GetNativeString(2, questId, sizeof(questId));
    return UpdateQuestProgressInternal(client, questId, value, true);
}

public any Native_US_GetQuestProgress(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char questId[64];
    int progress = 0;
    int completedAt = 0;
    int rewardedAt = 0;
    GetNativeString(2, questId, sizeof(questId));

    if (!GetQuestProgressState(client, questId, progress, completedAt, rewardedAt))
    {
        return false;
    }

    SetNativeCellRef(3, progress);
    SetNativeCellRef(4, (rewardedAt > 0) ? 1 : 0);
    return true;
}

public any Native_US_RegisterLeaderboard(Handle plugin, int numParams)
{
    char id[32], title[96], statKey[64], entryPhrase[64];
    int sortOrder = (numParams >= 5) ? GetNativeCell(5) : 0;
    GetNativeString(1, id, sizeof(id));
    GetNativeString(2, title, sizeof(title));
    GetNativeString(3, statKey, sizeof(statKey));
    if (numParams >= 4)
    {
        GetNativeString(4, entryPhrase, sizeof(entryPhrase));
    }
    else
    {
        strcopy(entryPhrase, sizeof(entryPhrase), "Top Profit Entry");
    }

    return RegisterLeaderboardInternal(id, title, statKey, entryPhrase, sortOrder);
}

public any Native_US_UnregisterLeaderboard(Handle plugin, int numParams)
{
    char id[32];
    GetNativeString(1, id, sizeof(id));
    return UnregisterLeaderboardInternal(id);
}


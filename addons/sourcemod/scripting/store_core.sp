#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#undef REQUIRE_PLUGIN
#include <adminmenu>
#define REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#include <cstrike>
#define REQUIRE_EXTENSIONS
#include <sdktools>
#include <sdkhooks>
#include <multicolors>

// =========================================================================
// CONFIG
// =========================================================================
#define STORE_DB_CONFIG          "store"
#define STORE_ITEMS_CONFIG       "configs/umbrella_store/umbrella_store_items.txt"
#define STORE_ITEMS_DIR          "configs/umbrella_store/items.d"
#define STORE_QUESTS_CONFIG      "configs/umbrella_store/umbrella_store_quests.txt"
#define STORE_LOG_PREFIX         "[Umbrella Store]"
#define STORE_API_VERSION        7
#define STORE_MAX_CREDITS        2000000000
#define STORE_SELL_PERCENT       50
#define PREVIEW_LIFETIME         15.0
#define PREVIEW_DISTANCE         100.0
#define PREVIEW_Z_OFFSET         60.0
#define MAX_ITEM_PLANS 6

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
    int expires_at;   // 0 = permanent; otherwise unix time when the rental ends
}

enum StoreAdminAction
{
    StoreAdminAction_None = 0,
    StoreAdminAction_GiveCredits,
    StoreAdminAction_SetCredits,
    StoreAdminAction_ViewInventory,
    StoreAdminAction_DebugPlayer,
    StoreAdminAction_DebugQuests,
    StoreAdminAction_ExportProfile,
    StoreAdminAction_AuditPlayer
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
bool g_bTableSetupFailed = false;
int g_iPendingTableQueries = 0;

int g_iCredits[MAXPLAYERS + 1] = {0, ...};
bool g_bIsLoaded[MAXPLAYERS + 1] = {false, ...};
bool g_bIsLoading[MAXPLAYERS + 1] = {false, ...};
bool g_bDetailFromInventory[MAXPLAYERS + 1] = {false, ...};
bool g_bDetailFromSearch[MAXPLAYERS + 1] = {false, ...};
int g_iPreviewEntity[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
char g_szBrowseType[MAXPLAYERS + 1][32];   // must match StoreItem.type
int g_iBrowseTeam[MAXPLAYERS + 1] = {0, ...};
char g_szBrowseCategory[MAXPLAYERS + 1][32];
char g_szInvFilter[MAXPLAYERS + 1][32];
char g_szSearchQuery[MAXPLAYERS + 1][64];
char g_szLastDetailItem[MAXPLAYERS + 1][32];
int g_iTradeSender[MAXPLAYERS + 1] = {0, ...};
char g_szTradeSenderItem[MAXPLAYERS + 1][32];
// Incoming-offer state, kept apart from the outgoing browse state above so a
// received request cannot clobber a trade the player is still composing.
char g_szPendingTradeSenderItem[MAXPLAYERS + 1][32];
int g_iPendingTradeTargetInvVersion[MAXPLAYERS + 1] = {0, ...};
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
ConVar gCvarStoreAdminFlag;
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
Handle g_hRentalExpireTimer = null;
Handle g_hCreditNotifyTimer[MAXPLAYERS + 1] = {null, ...};
Handle g_hPreviewTimer[MAXPLAYERS + 1] = {null, ...};
Handle g_hAdminMenu = INVALID_HANDLE;
TopMenuObject g_tmoStoreAdmin = INVALID_TOPMENUOBJECT;
StoreAdminAction g_AdminMenuAction[MAXPLAYERS + 1];
int g_iAdminMenuTarget[MAXPLAYERS + 1] = {0, ...};
bool g_bAwaitingAdminCreditAmount[MAXPLAYERS + 1] = {false, ...};
bool g_bCreditsDirty[MAXPLAYERS + 1] = {false, ...};
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
Handle g_hFwdStoreEnabledChanged = null;
Handle g_hFwdClientLoaded = null;
Handle g_hFwdItemsReloaded = null;

// =========================================================================
// API PÚBLICA
// =========================================================================
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    RegPluginLibrary("umbrella_store");
    CreateNative("US_GetApiVersion", Native_US_GetApiVersion);
    CreateNative("US_IsLoaded", Native_US_IsLoaded);
    CreateNative("US_IsEnabled", Native_US_IsEnabled);
    CreateNative("US_GetCredits", Native_US_GetCredits);
    CreateNative("US_SetCredits", Native_US_SetCredits);
    CreateNative("US_AddCredits", Native_US_AddCredits);
    CreateNative("US_TakeCredits", Native_US_TakeCredits);
    CreateNative("US_ApplyCreditDelta", Native_US_ApplyCreditDelta);
    CreateNative("US_ApplyCreditDeltas", Native_US_ApplyCreditDeltas);
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
    CreateNative("US_IsItemEquipped", Native_US_IsItemEquipped);
    CreateNative("US_GetEquippedItemCount", Native_US_GetEquippedItemCount);
    CreateNative("US_GetEquippedItemIdByIndex", Native_US_GetEquippedItemIdByIndex);
    CreateNative("US_CanPurchaseItem", Native_US_CanPurchaseItem);
    CreateNative("US_TryPurchaseItem", Native_US_TryPurchaseItem);
    CreateNative("US_CanEquipItem", Native_US_CanEquipItem);
    CreateNative("US_TryEquipItem", Native_US_TryEquipItem);
    CreateNative("US_TryUnequipItem", Native_US_TryUnequipItem);
    CreateNative("US_SetItemEquipped", Native_US_SetItemEquipped);
    CreateNative("US_CanUseItem", Native_US_CanUseItem);
    CreateNative("US_RegisterItemType", Native_US_RegisterItemType);
    CreateNative("US_UnregisterItemType", Native_US_UnregisterItemType);
    CreateNative("US_GetItemMetadata", Native_US_GetItemMetadata);
    CreateNative("US_IsDatabaseReady", Native_US_IsDatabaseReady);
    CreateNative("US_GetDatabaseConfig", Native_US_GetDatabaseConfig);
    CreateNative("US_IsMySQL", Native_US_IsMySQL);
    CreateNative("US_GetDatabaseHandle", Native_US_GetDatabaseHandle);
    CreateNative("US_DB_Escape", Native_US_DB_Escape);
    CreateNative("US_DB_EnsureTable", Native_US_DB_EnsureTable);
    CreateNative("US_ApplyCreditDeltaWithQuery", Native_US_ApplyCreditDeltaWithQuery);
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
    CreateNative("US_LogAuditEvent", Native_US_LogAuditEvent);
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
    version = "1.5.4",
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
    gCvarDatabase = CreateConVar("store_database", STORE_DB_CONFIG, "Explicit database entry name from databases.cfg.");
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
    g_hFwdStoreEnabledChanged = CreateGlobalForward("US_OnStoreEnabledChanged", ET_Ignore, Param_Cell);
    g_hFwdClientLoaded = CreateGlobalForward("US_OnClientLoaded", ET_Ignore, Param_Cell);
    g_hFwdItemsReloaded = CreateGlobalForward("US_OnItemsReloaded", ET_Ignore, Param_Cell);

    RegConsoleCmd("sm_store", Cmd_Store);
    RegConsoleCmd("sm_tienda", Cmd_Store);
    RegConsoleCmd("sm_profile", Cmd_Profile);
    RegConsoleCmd("sm_perfil", Cmd_Profile);
    RegConsoleCmd("sm_market", Cmd_Market);
    RegConsoleCmd("sm_mercado", Cmd_Market);
    RegConsoleCmd("sm_storesearch", Cmd_StoreSearch);
    RegConsoleCmd("sm_searchstore", Cmd_StoreSearch);
    RegConsoleCmd("sm_buscarstore", Cmd_StoreSearch);
    RegConsoleCmd("sm_buscar", Cmd_StoreSearch);
    RegConsoleCmd("sm_redeem", Cmd_RedeemVoucher);
    RegConsoleCmd("sm_voucher", Cmd_RedeemVoucher);
    RegConsoleCmd("sm_codigo", Cmd_RedeemVoucher);
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
    RegAdminCmd("sm_storelogs", Cmd_StoreAudit, ADMFLAG_ROOT);
    RegAdminCmd("sm_createvoucher", Cmd_CreateVoucher, ADMFLAG_ROOT);
    RegAdminCmd("sm_createitemvoucher", Cmd_CreateItemVoucher, ADMFLAG_ROOT);
    RegAdminCmd("sm_disablevoucher", Cmd_DisableVoucher, ADMFLAG_ROOT);
    RegAdminCmd("sm_reloadstore", Cmd_ReloadStore, ADMFLAG_ROOT);
    RegAdminCmd("sm_storedebug", Cmd_StoreDebug, ADMFLAG_ROOT);
    RegAdminCmd("sm_storequestsdebug", Cmd_StoreQuestsDebug, ADMFLAG_ROOT);
    RegAdminCmd("sm_storeexport", Cmd_StoreExportTarget, ADMFLAG_ROOT);
    RegConsoleCmd("sm_storeadmin", Cmd_StoreAdminMenu);
    RegConsoleCmd("sm_store_admin", Cmd_StoreAdminMenu);

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

    if (LibraryExists("adminmenu"))
    {
        Handle topmenu = GetAdminTopMenu();
        if (topmenu != INVALID_HANDLE)
        {
            OnAdminMenuReady(topmenu);
        }
    }
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

public void OnPluginEnd()
{
    // A plugin unload or reload is not a client disconnect, so nothing else
    // flushes pending balances: without this every credit earned since the last
    // autosave tick is lost for everyone currently online.
    SaveDirtyPlayers();

    for (int i = 1; i <= MaxClients; i++)
    {
        RemovePreview(i);
    }
}

public void OnMapEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        // Preview timers are created with TIMER_FLAG_NO_MAPCHANGE, so the timer
        // system disposes of them itself at level shutdown. Forget the handle
        // first: calling KillTimer on it here can hit an already-freed handle.
        g_hPreviewTimer[i] = null;
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
// MODULES
// =========================================================================
#include "store_core/helpers.sp"
#include "store_core/messages.sp"
#include "store_core/items.sp"
#include "store_core/database.sp"
#include "store_core/credits.sp"
#include "store_core/inventory.sp"
#include "store_core/equipment.sp"
#include "store_core/purchase.sp"
#include "store_core/trading.sp"
#include "store_core/marketplace.sp"
#include "store_core/vouchers.sp"
#include "store_core/quests.sp"
#include "store_core/profile.sp"
#include "store_core/leaderboards.sp"
#include "store_core/casino.sp"
#include "store_core/preview.sp"
#include "store_core/menus.sp"
#include "store_core/audit.sp"
#include "store_core/admin.sp"
#include "store_core/forwards.sp"
#include "store_core/natives.sp"

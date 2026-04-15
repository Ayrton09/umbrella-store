#if defined _umbrella_store_included
 #endinput
#endif
#define _umbrella_store_included

#define UMBRELLA_STORE_API_VERSION 2

/**
 * Legacy natives kept for backward compatibility.
 */
native bool US_IsLoaded(int client);
native int US_GetCredits(int client);
native bool US_SetCredits(int client, int amount);
native bool US_AddCredits(int client, int amount, bool notify = false);
native bool US_TakeCredits(int client, int amount);
native bool US_HasItem(int client, const char[] itemId);
native bool US_GiveItem(int client, const char[] itemId, bool equip = false);
native bool US_RemoveItem(int client, const char[] itemId);
native bool US_Casino_Register(const char[] id, const char[] title, const char[] command);
native bool US_Casino_Unregister(const char[] id);
native bool US_OpenCasinoMenu(int client);

/**
 * Recommended v2 API.
 */
native int US_GetApiVersion();
native bool US_OpenStoreMenu(int client);
native bool US_RegisterMenuSection(const char[] id, const char[] title, const char[] command, int sortOrder = 0);
native bool US_UnregisterMenuSection(const char[] id);

native int US_GetItemCount();
native bool US_GetItemIdByIndex(int index, char[] itemId, int maxlen);
native bool US_GetItemInfo(const char[] itemId, char[] name, int nameMax, char[] type, int typeMax, int &price, int &team, char[] category, int categoryMax);
native bool US_GetItemType(const char[] itemId, char[] type, int maxlen);
native int US_GetItemPrice(const char[] itemId);
native bool US_GetEquippedItem(int client, const char[] type, char[] itemId, int maxlen);
native bool US_CanPurchaseItem(int client, const char[] itemId, char[] reason, int maxlen);
native bool US_TryPurchaseItem(int client, const char[] itemId, bool equipAfterPurchase = false, bool notify = true);
native bool US_CanEquipItem(int client, const char[] itemId, char[] reason, int maxlen);
native bool US_TryEquipItem(int client, const char[] itemId, bool notify = true);
native bool US_RegisterItemType(const char[] type, const char[] category = "", bool equippable = true, bool exclusive = false);
native bool US_UnregisterItemType(const char[] type);
native bool US_GetItemMetadata(const char[] itemId, const char[] key, char[] value, int maxlen);

/**
 * Shared storage helpers exposed by the core.
 * Plugins can reuse the core database/config instead of opening their own
 * connection or duplicating escaping/bootstrap logic.
 */
native bool US_IsDatabaseReady();
native bool US_GetDatabaseConfig(char[] buffer, int maxlen);
native bool US_IsMySQL();
native Handle US_GetDatabaseHandle();
native bool US_DB_Escape(const char[] input, char[] output, int maxlen);
native bool US_DB_EnsureTable(const char[] tableId, const char[] mysqlQuery, const char[] sqliteQuery);

/**
 * Initial stats/progression helpers.
 */
native bool US_RegisterStatKey(const char[] statKey);
native bool US_AddStat(int client, const char[] statKey, int amount = 1);
native bool US_SetStatMax(int client, const char[] statKey, int value);
native bool US_RegisterQuest(const char[] questId, const char[] title, int goal, int rewardCredits = 0);
native bool US_RegisterQuestEx(const char[] questId, const char[] title, int goal, int rewardCredits = 0, const char[] rewardItem = "", bool equipRewardItem = false, const char[] category = "Quest Category General", const char[] description = "", bool repeatable = false, int maxCompletions = 1, const char[] requiresQuest = "", int startsAt = 0, int endsAt = 0);
native bool US_UnregisterQuest(const char[] questId);
native bool US_AdvanceQuestProgress(int client, const char[] questId, int amount = 1);
native bool US_SetQuestProgressMax(int client, const char[] questId, int value);
native bool US_GetQuestProgress(int client, const char[] questId, int &progress, bool &rewarded);
native bool US_RegisterLeaderboard(const char[] id, const char[] title, const char[] statKey, const char[] entryPhrase = "Top Profit Entry", int sortOrder = 0);
native bool US_UnregisterLeaderboard(const char[] id);

/**
 * Legacy forwards kept for compatibility.
 */
forward void OnStoreCreditsGiven(int client, int amount, const char[] reason);
forward void OnStoreItemPurchased(int client, const char[] itemId);
forward void OnStoreItemEquipped(int client, const char[] itemId, bool equipped);
forward void OnStoreTradeCompleted(int sender, int target, const char[] senderItemId, const char[] targetItemId);

/**
 * Recommended v2 forwards.
 * Pre hooks may return Plugin_Handled or Plugin_Stop to veto the action.
 */
forward Action US_OnPurchasePre(int client, const char[] itemId, bool equipAfterPurchase);
forward void US_OnPurchasePost(int client, const char[] itemId, int price, bool equippedAfterPurchase);
forward Action US_OnEquipPre(int client, const char[] itemId, bool equip);
forward void US_OnEquipPost(int client, const char[] itemId, bool equip);
forward Action US_OnTradePre(int sender, int target, const char[] senderItemId, const char[] targetItemId);
forward void US_OnTradePost(int sender, int target, const char[] senderItemId, const char[] targetItemId);
forward void US_OnCreditsChanged(int client, int delta, int newBalance, const char[] reason);
forward void US_OnInventoryChanged(int client, const char[] itemId, const char[] operation);
forward void US_OnQuestCompleted(int client, const char[] questId, int rewardCredits);

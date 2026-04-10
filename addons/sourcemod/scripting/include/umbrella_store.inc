#if defined _umbrella_store_included
 #endinput
#endif
#define _umbrella_store_included

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

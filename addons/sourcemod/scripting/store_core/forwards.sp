// Umbrella Store core: Global forward dispatch.
// Included by store_core.sp.

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

void ForwardStoreEnabledChanged(bool enabled)
{
    if (g_hFwdStoreEnabledChanged == null)
    {
        return;
    }

    Call_StartForward(g_hFwdStoreEnabledChanged);
    Call_PushCell(enabled ? 1 : 0);
    Call_Finish();
}

void ForwardClientLoaded(int client)
{
    if (g_hFwdClientLoaded == null)
    {
        return;
    }

    Call_StartForward(g_hFwdClientLoaded);
    Call_PushCell(client);
    Call_Finish();
}

void ForwardItemsReloaded()
{
    if (g_hFwdItemsReloaded == null)
    {
        return;
    }

    Call_StartForward(g_hFwdItemsReloaded);
    Call_PushCell(g_aItems != null ? g_aItems.Length : 0);
    Call_Finish();
}

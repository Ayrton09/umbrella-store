// Umbrella Store core: Chat rendering, phrases, and player-facing text helpers.
// Included by store_core.sp.

void FormatCooldownText(float seconds, char[] buffer, int maxlen)
{
    if (seconds < 0.1)
    {
        seconds = 0.1;
    }

    Format(buffer, maxlen, "%.1f", seconds);
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

// Player names reach chat through phrases that are colour-tagged afterwards, so
// a name such as "{green}[ADMIN]{default}" would render as real colours and let
// a player spoof staff tags in store notifications. Phrases that show one
// player's name to another take a sanitized name via %s instead of %N.
void GetSafeClientName(int client, char[] buffer, int maxlen)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        strcopy(buffer, maxlen, "?");
        return;
    }

    GetClientName(client, buffer, maxlen);
    SanitizeChatRenderInput(buffer, maxlen);
}

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
    if (!IsValidHumanClient(client))
    {
        return Plugin_Continue;
    }

    char text[192];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);

    if (g_bAwaitingAdminCreditAmount[client])
    {
        return HandleStoreAdminCreditAmountInput(client, text);
    }

    if (!g_bIsLoaded[client] || g_hInventory[client] == null || !IsStoreEnabled())
    {
        return Plugin_Continue;
    }

    MarkClientActive(client);

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

        int price = 0;
        if (!TryParseCreditAmount(text, price))
        {
            PrintStorePhrase(client, "%T", "Market Price Invalid", client, GetMarketplaceMinPrice(), GetMarketplaceMaxPrice());
            return Plugin_Handled;
        }

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

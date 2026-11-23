# Umbrella Store

[![Release](https://img.shields.io/github/v/release/Ayrton09/umbrella-store?label=release&color=blue)](https://github.com/Ayrton09/umbrella-store/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Ayrton09/umbrella-store/total?color=brightgreen)](https://github.com/Ayrton09/umbrella-store/releases)
![SourceMod](https://img.shields.io/badge/SourceMod-1.12%2B-orange)
![Game](https://img.shields.io/badge/game-CS%3AS-orange)
![Database](https://img.shields.io/badge/database-MySQL%20%2F%20SQLite-lightgrey)
![Plugins](https://img.shields.io/badge/plugins-25-informational)
![API](https://img.shields.io/badge/API-v7-purple)
![Languages](https://img.shields.io/badge/languages-7-yellow)
[![License](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE)

A modular store suite for SourceMod: persistent economy, ten casino games, fourteen cosmetic modules, quests, a player marketplace, and a public API for third-party modules.

Umbrella Store is not a patched legacy fork. `store_core` provides the economy, inventory, database, and extension backbone, and every game or cosmetic ships as an independent plugin on top of it. Load only the modules you want.

**[Download the latest release](https://github.com/Ayrton09/umbrella-store/releases/latest)** · [Installation](#installation) · [Commands](#commands) · [ConVars](#convars) · [API](#extending-the-store)

---

## Highlights

- **Economy**: credits for playtime, kills, headshots, round wins, and bomb objectives, with AFK protection and batched chat notifications.
- **Inventory**: buy, sell, equip, preview, gift, and trade items; rentals, sales, bundles, timed availability, and access flags per item.
- **Marketplace** (`!market`): players list items for each other, with listing expiry, price limits, and a configurable fee. Every transfer runs in a database transaction.
- **Vouchers** (`!redeem`): credit and item codes with use limits and expiry.
- **Quests and leaderboards**: file-defined or API-registered quests, persistent stats, and `!tops` boards for credits, profit, daily streaks, and each casino game.
- **Audit trail**: admin actions, trades, vouchers, and credit changes are logged to `store_audit_log` and a credit ledger, browsable with `sm_storeaudit`.
- **Chat cosmetics built in**: tags, name colors, and chat colors through MultiColors, plus player skins.
- **Translated**: English, Spanish, Russian, Chinese, Portuguese, French, and German.
- **Per-player preferences**: every visual cosmetic can be hidden locally (`!hidetrails`, `!hidepets`, `!hidelaser`, ...).

## Modules

### Casino

| Plugin | Game | Commands |
| --- | --- | --- |
| `store_blackjack` | Blackjack: single, PvP, and table modes with splits and doubles | `!blackjack` `!bj` |
| `store_roulette` | Roulette with animated HUD spin; color, green, and number bets | `!roulette` `!ruleta` `!ru` |
| `store_crash` | Crash with live multiplier and cash-out | `!crash` |
| `store_coinflip` | Coinflip against the house or another player | `!coinflip` `!cf` · PvP: `!cfvs` `!cfa` `!cfd` |
| `store_dice` | Two dice: low, high, or exact seven | `!dice` `!dados` |
| `store_highlow` | Guess whether the next number is higher or lower | `!highlow` `!hilo` |
| `store_jackpot` | Pooled jackpot, winner chance weighted by entry | `!jackpot` `!jp` `!bote` |
| `store_lootbox` | Lootboxes with weighted credit and item rewards | `!lootbox` `!cajas` `!case` |
| `store_daily` | Daily reward with streak bonus | `!daily` `!diario` |
| `store_giveaway` | Admin-run giveaway with HUD roulette | `!giveaway` `!giveawaycancel` |

### Cosmetics

| Plugin | Item type | What it does |
| --- | --- | --- |
| `store_hats` | `hat` | Props attached to the head |
| `store_trails` | `trail` | Sprite trail behind the player |
| `store_pets` | `pet` | Model that follows the player |
| `store_particles` | `particle` | Aura, trail, spawn, kill, and hit particle effects |
| `store_tracers` | `tracer` | Beam along each shot to the impact point |
| `store_bulletsparks` | `bulletsparks` | Sparks on bullet impact |
| `store_paintball` | `paintball` | Decals on bullet impact |
| `store_grenade_skins` | `grenadeskin` | Custom thrown grenade models |
| `store_grenade_trails` | `grenadetrail` | Trail behind thrown grenades |
| `store_colored_smoke` | `coloredsmoke` | Tinted smoke grenades |
| `store_lasersight` | `lasersight` | Laser sight while scoped with a sniper |
| `store_sprays` | `spray` | Custom sprays placed with the use key |
| `store_saysounds` | `saysound` | Sounds triggered by chat keywords |
| `store_camera` | | Thirdperson and mirror camera (`!tp`, `!mirror`, `!fp`) |

`store_core` itself provides the `skin`, `tag`, `namecolor`, and `chatcolor` item types.

## Requirements

- **SourceMod 1.12 or newer.** The shipped plugins are built with the latest stable 1.12 release (build 7260).
- SDKTools, SDKHooks, and ClientPrefs (included with SourceMod).
- A MySQL or SQLite database entry in `databases.cfg`.
- Optional: the `adminmenu` plugin adds a Store Admin category to `!admin`, and the `cstrike` extension is used for skin model resets on CS:S. The core loads without either.

## Installation

1. Download `umbrella_store_X.Y.Z.zip` from the [latest release](https://github.com/Ayrton09/umbrella-store/releases/latest) and extract `addons/`, `materials/`, and `models/` into your game folder (for example `cstrike/`).
2. Add a database entry to `addons/sourcemod/configs/databases.cfg`. The core looks for an entry named `store` (change it with `store_database`):

   ```
   "store"
   {
       "driver"    "sqlite"
       "database"  "umbrella_store"
   }
   ```

   For MySQL use `"driver" "mysql"` with `host`, `database`, `user`, and `pass`. Tables are created automatically on first start.
3. Start the server once. Each plugin writes its cfg to `cfg/sourcemod/` (see [ConVars](#convars)).
4. Replace the examples in `configs/umbrella_store/umbrella_store_items.txt` with your items. Per-module examples live in `config_examples/`; files placed in `items.d/*.txt` are loaded too.
5. Upload the shipped models and materials, plus any your items reference, to your FastDL. The release includes `umbrella_store_X.Y.Z_fastdl.zip` with every file already `.bz2`-compressed.
6. Optionally define quests in `configs/umbrella_store/umbrella_store_quests.txt`.
7. Restart the server, or run `sm_reloadstore` after editing items or quests.

## Configuration

### Items

Each item is a block in `umbrella_store_items.txt` or any `items.d/*.txt` file:

```
"Items"
{
    "hat_sombrero"
    {
        "name"        "Sombrero"
        "type"        "hat"
        "category"    "hats"
        "description" "Example attached hat model."
        "model"       "models/gmod_tower/sombrero.mdl"
        "position"    "0.0 -1.0 6.0"
        "angles"      "0 0 0"
        "price"       "5000"
        "team"        "0"
    }
}
```

Common keys for every item type:

| Key | Description |
| --- | --- |
| `name`, `type`, `category`, `description` | Display data and the module that handles the item |
| `price`, `sale_price`, `sell_percent_override` | Buy price, discounted price, and custom sell refund |
| `team` | `0` any team, `2` T only, `3` CT only |
| `flag` | SourceMod admin flag required to buy or use the item |
| `rarity`, `sort_order`, `hidden` | Menu presentation |
| `starts_at`, `ends_at` | Unix timestamps for limited-time items |
| `requires_item`, `bundle_id` | Prerequisites and bundles |
| `value`, `model`, `metadata` | Type-specific payload |

The commented header of `umbrella_store_items.txt` documents every key with examples.

### Quests

```
"Quests"
{
    "daily_claims_3"
    {
        "title"          "Quest Title Daily Claims I"
        "category"       "Quest Category Daily"
        "description"    "Quest Desc Daily Claims I"
        "goal"           "3"
        "reward_credits" "150"
        "enabled"        "1"
    }
}
```

Quests also support `reward_item`, `repeatable`, `max_completions`, `requires_quest`, `starts_at`, and `ends_at`. Titles, categories, and descriptions can be translation phrase keys or raw text.

## Commands

### Players

| Command | Description |
| --- | --- |
| `!store` / `!tienda` | Open the store menu |
| `!inv` / `!inventory` / `!inventario` | Open your inventory |
| `!credits` / `!creditos` | Show your credit balance |
| `!gift` / `!regalar` | Gift an item or credits to another player |
| `!trade` / `!tradear` | Propose an item trade to another player |
| `!market` / `!mercado` | Marketplace: browse, list, buy, cancel |
| `!redeem` / `!voucher` / `!codigo <code>` | Redeem a voucher code |
| `!storesearch` / `!buscar <text>` | Search the item catalog |
| `!profile` / `!perfil` | Your persistent stats |
| `!profileexport` | Export a text snapshot of your profile |
| `!quests` / `!misiones` | Quest progress |
| `!tops` / `!leaderboards` | Leaderboard hub |
| `!topcredits` `!topprofit` `!topdaily` `!topbj` `!topcf` `!topcrash` `!toproulette` | Individual leaderboards |
| `!hidetrails` `!hidetracers` `!hidepaintball` `!hidepets` `!hidebulletsparks` `!hideparticles` `!hidelaser` | Hide a cosmetic for yourself |

Casino and camera commands are listed in [Modules](#modules). Say sounds trigger from chat text.

### Admins

| Command | Description |
| --- | --- |
| `sm_storeadmin` | Admin menu: credits, inventory, audit, debug, reload |
| `sm_givecredits <target> <amount>` | Give credits (`@all`, `@t`, `@ct`, `@me` supported) |
| `sm_setcredits <target> <amount>` | Set a credit balance |
| `sm_storeaudit` / `sm_storelogs [target\|global] [limit]` | Recent audit events |
| `sm_storedebug <player>` | Economy and profile snapshot to console |
| `sm_storequestsdebug <player>` | Quest state, completions, and lock reasons |
| `sm_storeexport <player>` | Export another player's snapshot |
| `sm_createvoucher <code> <credits> [max_uses] [expires_hours]` | Create a credit voucher |
| `sm_createitemvoucher <code> <item_id> [max_uses] [expires_hours]` | Create an item voucher |
| `sm_disablevoucher <code>` | Disable a voucher |
| `sm_reloadstore` | Reload item and quest configs |

The admin menu flag is set with `store_admin_flag` (default `z`, root).

## ConVars

Every plugin generates its own file in `cfg/sourcemod/`. Click a module to expand its ConVars.

<details>
<summary><b>Core</b> · <code>store_core</code> · <code>cfg/sourcemod/umbrella_store_core.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `store_database` | `store` | Database entry name from databases.cfg. |
| `store_enabled` | `1` | Enable or disable Umbrella Store globally. |
| `store_credits_time_enabled` | `1` | Enable credits for time played. |
| `store_credits_time_amount` | `10` | Credits earned per time interval. |
| `store_credits_time_interval` | `60` | Interval in seconds for time-based credits. |
| `store_credits_kill_enabled` | `1` | Enable credits for kills. |
| `store_credits_kill_amount` | `2` | Credits earned per kill. |
| `store_credits_headshot_bonus` | `1` | Extra credits for headshots. |
| `store_credits_roundwin_enabled` | `1` | Enable credits for round wins. |
| `store_credits_roundwin_amount` | `3` | Credits earned per round win. |
| `store_credits_plant_enabled` | `1` | Enable credits for bomb plant. |
| `store_credits_plant_amount` | `2` | Credits earned for bomb plant. |
| `store_credits_defuse_enabled` | `1` | Enable credits for bomb defuse. |
| `store_credits_defuse_amount` | `3` | Credits earned for bomb defuse. |
| `store_credits_afk_max` | `90` | Maximum idle seconds allowed to receive time-based credits. |
| `store_credits_notify_delay` | `2.0` | Delay in seconds to group credit messages and reduce spam. |
| `store_credits_autosave_interval` | `120.0` | Auto-save interval for credits in seconds. |
| `store_admin_flag` | `z` | SourceMod admin flag required for the Umbrella Store admin menu. Default z = root. |
| `store_initial_credits` | `50000` | Initial credits for new players. |
| `store_sell_percent` | `50` | Refund percentage when selling items. |
| `store_preview_lifetime` | `15.0` | Preview lifetime in seconds. |
| `store_preview_distance` | `100.0` | Distance at which preview appears. |
| `store_preview_zoffset` | `60.0` | Vertical offset for preview. |
| `store_enable_player_skins` | `1` | Enable or disable store player skins. |
| `store_preview_cooldown` | `3.0` | Cooldown between skin previews in seconds. |
| `store_equip_cooldown` | `0.35` | Cooldown between equip and unequip actions in seconds. |
| `store_chat_extended_colors` | `1` | Legacy compatibility cvar. Umbrella Store now renders chat through the Multi-Colors backend. |
| `umbrella_store_market_enabled` | `1` | Enable or disable the Umbrella Store marketplace. |
| `umbrella_store_market_min_price` | `50` | Minimum price for marketplace listings. |
| `umbrella_store_market_max_price` | `1000000` | Maximum price for marketplace listings. 0 disables the cap. |
| `umbrella_store_market_listing_hours` | `72` | Hours before a marketplace listing expires. |
| `umbrella_store_market_fee_percent` | `5` | Marketplace fee percentage applied to completed sales. |

</details>

<details>
<summary><b>Blackjack</b> · <code>store_blackjack</code> · <code>cfg/sourcemod/umbrella_store_blackjack.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_blackjack_min_bet` | `100` | Minimum blackjack bet. |
| `umbrella_store_blackjack_max_bet` | `1000000` | Maximum blackjack bet. |
| `umbrella_store_blackjack_blackjack_pay_num` | `3` | Numerator for natural blackjack payout. |
| `umbrella_store_blackjack_blackjack_pay_den` | `2` | Denominator for natural blackjack payout. |
| `umbrella_store_blackjack_dealer_hit_soft17` | `0` | If 1, dealer hits on soft 17. |
| `umbrella_store_blackjack_action_cooldown` | `0.35` | Cooldown between menu actions. |
| `umbrella_store_blackjack_command_cooldown` | `0.75` | Cooldown between blackjack open commands. |
| `umbrella_store_blackjack_sounds` | `1` | Enable blackjack sounds. |
| `umbrella_store_blackjack_pvp_enabled` | `1` | Enable player-vs-player mode. |
| `umbrella_store_blackjack_pvp_invite_timeout` | `20.0` | Time to accept a PvP challenge. |
| `umbrella_store_blackjack_pvp_turn_timeout` | `15.0` | Maximum time per PvP turn before auto-stand. |
| `umbrella_store_blackjack_bigwin_announce` | `1` | Announce big wins globally. |
| `umbrella_store_blackjack_bigwin_min_net` | `15000` | Minimum net profit required for global announcement. |
| `umbrella_store_blackjack_announce_natural` | `1` | Announce natural blackjacks globally. |
| `umbrella_store_blackjack_announce_streaks` | `1` | Announce notable win streaks globally. |

</details>

<details>
<summary><b>Roulette</b> · <code>store_roulette</code> · <code>cfg/sourcemod/umbrella_store_roulette.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_roulette_enabled` | `1` | Enable roulette module. |
| `umbrella_store_roulette_min_bet` | `100` | Minimum roulette bet. |
| `umbrella_store_roulette_max_bet` | `1000000` | Maximum roulette bet. 0 = no limit. |
| `umbrella_store_roulette_cooldown` | `0.4` | Cooldown between roulette actions. |
| `umbrella_store_roulette_color_multiplier` | `2.0` | Payout multiplier for red/black wins. |
| `umbrella_store_roulette_green_multiplier` | `14.0` | Payout multiplier for green wins. |
| `umbrella_store_roulette_number_multiplier` | `36.0` | Payout multiplier for exact number wins. |
| `umbrella_store_roulette_announce_big_win` | `1` | Announce big roulette wins globally. |
| `umbrella_store_roulette_big_win_threshold` | `20000` | Minimum net profit for big-win announcement. |
| `umbrella_store_roulette_spin_sound` | `buttons/blip1.wav` | Sound played when spinning roulette. |
| `umbrella_store_roulette_win_sound` | `items/itempickup.wav` | Sound played on roulette win. |
| `umbrella_store_roulette_lose_sound` | `buttons/button10.wav` | Sound played on roulette loss. |
| `umbrella_store_roulette_anim_enabled` | `1` | Enable roulette HUD spin animation. |
| `umbrella_store_roulette_anim_mode` | `2` | Roulette animation mode. 1=center text, 2=hint text. |
| `umbrella_store_roulette_anim_steps` | `18` | Minimum visual steps for roulette animation. |
| `umbrella_store_roulette_anim_delay_min` | `0.03` | Initial delay between animation steps. |
| `umbrella_store_roulette_anim_delay_max` | `0.12` | Final delay between animation steps. |

</details>

<details>
<summary><b>Crash</b> · <code>store_crash</code> · <code>cfg/sourcemod/umbrella_store_crash.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_crash_enabled` | `1` | Enable Crash module. |
| `umbrella_store_crash_min_bet` | `100` | Minimum bet. |
| `umbrella_store_crash_max_bet` | `1000000` | Maximum bet. |
| `umbrella_store_crash_countdown` | `8.0` | Countdown seconds before round starts. |
| `umbrella_store_crash_tick_interval` | `0.05` | Multiplier update interval. |
| `umbrella_store_crash_growth_per_second` | `0.22` | Linear growth per second. |
| `umbrella_store_crash_growth_curve` | `0.035` | Additional quadratic growth per second. |
| `umbrella_store_crash_warmup_seconds` | `4.0` | Initial smooth acceleration duration in seconds for multiplier. 0 = disabled. |
| `umbrella_store_crash_low_chance` | `0.40` | Percentage chance of low crash (x1.00/x1.01/x1.02). |
| `umbrella_store_crash_low_min` | `1.00` | Minimum multiplier for low crash. |
| `umbrella_store_crash_low_max` | `1.02` | Maximum multiplier for low crash. |
| `umbrella_store_crash_epic_chance` | `0.8` | Percentage chance of an epic boost per round. |
| `umbrella_store_crash_epic_boost_per_second` | `0.65` | Extra linear acceleration during epic boost. |
| `umbrella_store_crash_epic_boost_curve` | `0.11` | Extra curve acceleration during epic boost. |
| `umbrella_store_crash_epic_start_min` | `1.2` | Minimum second to start an epic boost. |
| `umbrella_store_crash_epic_start_max` | `3.0` | Maximum second to start an epic boost. |
| `umbrella_store_crash_epic_min_crash` | `3.5` | Forced minimum crash value when epic boost triggers. |
| `umbrella_store_crash_restart_delay` | `3.0` | Delay after crash before returning to idle. |
| `umbrella_store_crash_antispam` | `0.35` | Anti-spam cooldown for actions. |
| `umbrella_store_crash_start_sound` | `buttons/blip1.wav` | Sound played when round starts. Empty = disabled. |
| `umbrella_store_crash_cashout_sound` | `buttons/button14.wav` | Sound played on cashout. Empty = disabled. |
| `umbrella_store_crash_crash_sound` | `weapons/hegrenade/explode5.wav` | Sound played on crash. Empty = disabled. |
| `umbrella_store_crash_announce_chat` | `1` | Announce important events in chat. |
| `umbrella_store_crash_history_max` | `10` | Number of entries kept in history. |
| `umbrella_store_crash_cashout_safety` | `0.02` | Anti-exploit safety margin before crash where cashout is blocked. |

</details>

<details>
<summary><b>Coinflip</b> · <code>store_coinflip</code> · <code>cfg/sourcemod/umbrella_store_coinflip.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_coinflip_enabled` | `1` | Enable the coinflip module. |
| `umbrella_store_coinflip_min_bet` | `50` | Minimum bet. |
| `umbrella_store_coinflip_max_bet` | `1000000` | Maximum bet. 0 = no limit. |
| `umbrella_store_coinflip_cooldown` | `2.0` | Cooldown between uses. |
| `umbrella_store_coinflip_multiplier` | `2.0` | Multiplier when winning against the house. |
| `umbrella_store_coinflip_win_sound` | `items/itempickup.wav` | Sound played on win. |
| `umbrella_store_coinflip_lose_sound` | `buttons/button10.wav` | Sound played on loss. |
| `umbrella_store_coinflip_announce_big` | `1` | Announce large bets globally. |
| `umbrella_store_coinflip_announce_threshold` | `2000` | Threshold for global announcement. |
| `umbrella_store_coinflip_anim_enabled` | `1` | Enable non-graphical animation. |
| `umbrella_store_coinflip_anim_steps` | `6` | Number of animation steps. |
| `umbrella_store_coinflip_anim_delay` | `0.35` | Delay between animation steps. |
| `umbrella_store_coinflip_anim_mode` | `2` | 1 = center text, 2 = hint text. |
| `umbrella_store_coinflip_pvp_enabled` | `1` | Enable player-vs-player coinflip. |
| `umbrella_store_coinflip_pvp_timeout` | `20.0` | Time to accept a PvP coinflip. |
| `umbrella_store_coinflip_pvp_challenge_cooldown` | `8.0` | Cooldown between PvP challenges to prevent spam. |

</details>

<details>
<summary><b>Dice</b> · <code>store_dice</code> · <code>cfg/sourcemod/umbrella_store_dice.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_dice_enabled` | `1` | Enable the dice module. |
| `umbrella_store_dice_min_bet` | `50` | Minimum bet. |
| `umbrella_store_dice_max_bet` | `1000000` | Maximum bet. 0 = no limit. |
| `umbrella_store_dice_cooldown` | `2.0` | Cooldown between rolls. |
| `umbrella_store_dice_mult_lowhigh` | `2.0` | Payout multiplier for low/high wins. |
| `umbrella_store_dice_mult_seven` | `5.0` | Payout multiplier for an exact seven. |
| `umbrella_store_dice_win_sound` | `items/itempickup.wav` | Sound played on win. |
| `umbrella_store_dice_lose_sound` | `buttons/button10.wav` | Sound played on loss. |

</details>

<details>
<summary><b>High-Low</b> · <code>store_highlow</code> · <code>cfg/sourcemod/umbrella_store_highlow.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_highlow_enabled` | `1` | Enable the high-or-low module. |
| `umbrella_store_highlow_min_bet` | `50` | Minimum bet. |
| `umbrella_store_highlow_max_bet` | `1000000` | Maximum bet. 0 = no limit. |
| `umbrella_store_highlow_cooldown` | `2.0` | Cooldown between rounds. |
| `umbrella_store_highlow_multiplier` | `1.9` | Payout multiplier on a correct guess. |
| `umbrella_store_highlow_win_sound` | `items/itempickup.wav` | Sound played on win. |
| `umbrella_store_highlow_lose_sound` | `buttons/button10.wav` | Sound played on loss. |

</details>

<details>
<summary><b>Jackpot</b> · <code>store_jackpot</code> · <code>cfg/sourcemod/umbrella_store_jackpot.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_jackpot_enabled` | `1` | Enable the jackpot module. |
| `umbrella_store_jackpot_min_entry` | `100` | Minimum credits per entry. |
| `umbrella_store_jackpot_max_entry` | `100000` | Maximum total credits a player can put in one round. 0 = no limit. |
| `umbrella_store_jackpot_round_time` | `30.0` | Seconds the pot stays open after the first entry. |
| `umbrella_store_jackpot_min_players` | `2` | Minimum distinct players for the round to pay out. |
| `umbrella_store_jackpot_rake_percent` | `0` | House cut percent taken from the pot. |
| `umbrella_store_jackpot_win_sound` | `items/itempickup.wav` | Sound played to the winner. |

</details>

<details>
<summary><b>Lootbox</b> · <code>store_lootbox</code> · <code>cfg/sourcemod/umbrella_store_lootbox.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_lootbox_enabled` | `1` | Enable the lootbox module. |
| `umbrella_store_lootbox_cooldown` | `1.0` | Seconds between opening boxes. |
| `umbrella_store_lootbox_open_sound` | `buttons/blip1.wav` | Sound played while opening a box. |
| `umbrella_store_lootbox_win_sound` | `items/itempickup.wav` | Sound played when the reward is revealed. |
| `umbrella_store_lootbox_anim_enabled` | `1` | Enable the HUD reveal animation. |
| `umbrella_store_lootbox_anim_ticks` | `12` | Number of spin ticks before the reward is revealed. |
| `umbrella_store_lootbox_anim_interval` | `0.12` | Seconds between spin ticks. |

</details>

<details>
<summary><b>Daily</b> · <code>store_daily</code> · <code>cfg/sourcemod/umbrella_store_daily.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_daily_enabled` | `1` | Enable !daily module. |
| `umbrella_store_daily_base_credits` | `50` | Base credits for daily reward. |
| `umbrella_store_daily_streak_bonus` | `25` | Extra bonus for each streak day. |
| `umbrella_store_daily_max_streak_days` | `7` | Maximum streak days that scale the reward. |
| `umbrella_store_daily_cooldown_hours` | `24` | Required hours between claims. |
| `umbrella_store_daily_grace_hours` | `48` | If more than this many hours pass, streak resets. |
| `umbrella_store_daily_announce_on_join` | `1` | Announce on join that !daily exists. |

</details>

<details>
<summary><b>Giveaway</b> · <code>store_giveaway</code> · <code>cfg/sourcemod/umbrella_store_giveaway.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_giveaway_enabled` | `1` | Enable giveaway module. |
| `umbrella_store_giveaway_min_players` | `2` | Minimum valid players required to start giveaway. |
| `umbrella_store_giveaway_team_only` | `1` | 1 = TT/CT only, 0 = any in-game player. |
| `umbrella_store_giveaway_admin_flag` | `z` | Required admin flag to use giveaway. |
| `umbrella_store_giveaway_start_delay` | `3.0` | Seconds before animation starts. |
| `umbrella_store_giveaway_tick_interval` | `0.10` | Base timer interval for animation. |
| `umbrella_store_giveaway_roll_ticks` | `38` | Total number of animation ticks. |
| `umbrella_store_giveaway_winner_hold_time` | `4.0` | Time to hold winner on screen. |
| `umbrella_store_giveaway_announce` | `1` | Announce messages in chat. |
| `umbrella_store_giveaway_hud_channel` | `4` | HUD channel to use. |
| `umbrella_store_giveaway_sound_enable` | `1` | Enable giveaway sounds. |
| `umbrella_store_giveaway_roll_sound` | *(empty)* | Roulette roll sound path. Empty = disabled. |
| `umbrella_store_giveaway_slow_roll_sound` | `buttons/button17.wav` | Sound played while roulette slows down. |
| `umbrella_store_giveaway_winner_sound` | `buttons/bell1.wav` | Sound played when winner is selected. |
| `umbrella_store_giveaway_slow_roll_sound_volume` | `0.75` | Slowdown sound volume. |
| `umbrella_store_giveaway_winner_sound_volume` | `0.95` | Winner sound volume. |

</details>

<details>
<summary><b>Hats</b> · <code>store_hats</code> · <code>cfg/sourcemod/umbrella_store_hats.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_hats_enabled` | `1` | Enable Umbrella Store hats. |
| `umbrella_store_hats_hide_own` | `1` | Hide a player's own hat in first person. |

</details>

<details>
<summary><b>Trails</b> · <code>store_trails</code> · <code>cfg/sourcemod/umbrella_store_trails.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_trails_enabled` | `1` | Enable Umbrella Store player trails. |
| `umbrella_store_trails_default_life` | `1.0` | Default trail lifetime in seconds. |

</details>

<details>
<summary><b>Pets</b> · <code>store_pets</code> · <code>cfg/sourcemod/umbrella_store_pets.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_pets_enabled` | `1` | Enable Umbrella Store pets. |
| `umbrella_store_pets_follow_mode` | `0` | Pet follow mode: 0 = legacy attached to player, 1 = moving follower. |

</details>

<details>
<summary><b>Particles</b> · <code>store_particles</code> · <code>cfg/sourcemod/umbrella_store_particles.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_particles_enabled` | `1` | Enable Umbrella Store particles. |
| `umbrella_store_particles_hit_interval` | `0.15` | Minimum seconds between hit particles spawned by the same player. |
| `umbrella_store_particles_max_active` | `48` | Maximum simultaneous point particle entities spawned by this module (edict-exhaustion guard). |

</details>

<details>
<summary><b>Tracers</b> · <code>store_tracers</code> · <code>cfg/sourcemod/umbrella_store_tracers.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_tracers_enabled` | `1` | Enable Umbrella Store tracers. |
| `umbrella_store_tracers_material` | `materials/sprites/laserbeam.vmt` | Beam material used by tracer items. |
| `umbrella_store_tracers_life` | `0.45` | Tracer lifetime in seconds. |
| `umbrella_store_tracers_width` | `1.5` | Tracer beam width. |
| `umbrella_store_tracers_interval` | `0.05` | Minimum seconds between tracer beams from the same player. |

</details>

<details>
<summary><b>Bullet sparks</b> · <code>store_bulletsparks</code> · <code>cfg/sourcemod/umbrella_store_bulletsparks.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_bulletsparks_enabled` | `1` | Enable Umbrella Store bullet sparks. |
| `umbrella_store_bulletsparks_magnitude` | `250` | Spark magnitude. |
| `umbrella_store_bulletsparks_trail_length` | `500` | Spark trail length. |
| `umbrella_store_bulletsparks_interval` | `0.1` | Minimum seconds between spark effects from the same player. |

</details>

<details>
<summary><b>Paintball</b> · <code>store_paintball</code> · <code>cfg/sourcemod/umbrella_store_paintball.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_paintball_enabled` | `1` | Enable Umbrella Store paintball decals. |
| `umbrella_store_paintball_interval` | `0.1` | Minimum seconds between paintball decals from the same player. |

</details>

<details>
<summary><b>Grenade skins</b> · <code>store_grenade_skins</code> · <code>cfg/sourcemod/umbrella_store_grenade_skins.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_grenade_skins_enabled` | `1` | Enable Umbrella Store grenade skins. |

</details>

<details>
<summary><b>Grenade trails</b> · <code>store_grenade_trails</code> · <code>cfg/sourcemod/umbrella_store_grenade_trails.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_grenade_trails_enabled` | `1` | Enable Umbrella Store grenade trails. |
| `umbrella_store_grenade_trails_life` | `2.0` | Grenade trail lifetime in seconds. |

</details>

<details>
<summary><b>Colored smoke</b> · <code>store_colored_smoke</code> · <code>cfg/sourcemod/umbrella_store_colored_smoke.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_colored_smoke_enabled` | `1` | Enable Umbrella Store colored smoke. |

</details>

<details>
<summary><b>Laser sight</b> · <code>store_lasersight</code> · <code>cfg/sourcemod/umbrella_store_lasersight.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_lasersight_enabled` | `1` | Enable Umbrella Store laser sights. |
| `umbrella_store_lasersight_material` | `materials/sprites/laserbeam.vmt` | Beam material used by laser sights. |
| `umbrella_store_lasersight_dot_material` | `materials/sprites/redglow1.vmt` | Dot material used by laser sights. |
| `umbrella_store_lasersight_beam_life` | `0.1` | Laser beam lifetime. |
| `umbrella_store_lasersight_beam_width` | `0.12` | Laser beam width. |
| `umbrella_store_lasersight_dot_life` | `0.1` | Laser dot lifetime. |
| `umbrella_store_lasersight_dot_size` | `0.25` | Laser dot size. |
| `umbrella_store_lasersight_update_interval` | `0.05` | Seconds between laser sight updates per player. |

</details>

<details>
<summary><b>Sprays</b> · <code>store_sprays</code> · <code>cfg/sourcemod/umbrella_store_sprays.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_sprays_enabled` | `1` | Enable Umbrella Store sprays. |
| `umbrella_store_sprays_cooldown` | `30` | Seconds between two sprays per player. |
| `umbrella_store_sprays_distance` | `115.0` | Maximum distance from player eye to spray surface. |

</details>

<details>
<summary><b>Say sounds</b> · <code>store_saysounds</code> · <code>cfg/sourcemod/umbrella_store_saysounds.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_saysounds_enabled` | `1` | Enable Umbrella Store say sounds. |
| `umbrella_store_saysounds_max_uses` | `3` | Maximum say sound uses per reset window. 0 = unlimited. |
| `umbrella_store_saysounds_reset_mode` | `1` | 0 = reset on map, 1 = reset on round. |
| `umbrella_store_saysounds_default_cooldown` | `30` | Default per-player cooldown in seconds. |
| `umbrella_store_saysounds_min_cooldown` | `3` | Lower bound applied to any per-item cooldown. |
| `umbrella_store_saysounds_alive_only` | `1` | Only living players on a playing team can trigger say sounds. |
| `umbrella_store_saysounds_default_volume` | `0.8` | Default say sound volume. |

</details>

<details>
<summary><b>Camera</b> · <code>store_camera</code> · <code>cfg/sourcemod/umbrella_store_camera.cfg</code></summary>

| ConVar | Default | Description |
| --- | --- | --- |
| `umbrella_store_camera_enabled` | `1` | Enable or disable the camera system. |
| `umbrella_store_camera_disabled_maps` | `de_,cs_,fy_,awp_,aim_` | Map prefixes where !tp and !mirror are disabled. |
| `umbrella_store_camera_tp_distance` | `120` | Legacy compatibility only. CS:S blocks server-side cam_* camera commands. |
| `umbrella_store_camera_mirror_distance` | `100` | Legacy compatibility only. CS:S blocks server-side cam_* camera commands. |
| `umbrella_store_camera_tp_pitch` | `0` | Legacy compatibility only. CS:S blocks server-side cam_* camera commands. |
| `umbrella_store_camera_mirror_pitch` | `0` | Legacy compatibility only. CS:S blocks server-side cam_* camera commands. |
| `umbrella_store_camera_mirror_yaw` | `0` | Legacy compatibility only. CS:S blocks server-side cam_* camera commands. |
| `umbrella_store_camera_announce` | `1` | If 1, announce camera commands on join. |
| `umbrella_store_camera_reset_on_death` | `1` | If 1, force firstperson on death or spectator. |

</details>

Some modules also register older `sm_`/`store_` prefixed aliases of these ConVars so existing configs keep working.

## Extending the store

Third-party plugins integrate through the public API (v7) in [`umbrella_store.inc`](addons/sourcemod/scripting/include/umbrella_store.inc) without editing the core: menu sections, custom item types, item metadata, equipped-item enumeration, transaction-safe credit deltas, shared database access, stats, quests, leaderboards, audit events, and pre/post forwards for purchase, equip, trade, credits, and inventory changes.

```c
#include <sourcemod>
#include <umbrella_store>

public void OnPluginStart()
{
    US_RegisterMenuSection("my_module", "My Module", "sm_mymodule", 40);
    US_RegisterItemType("player_badge", "cosmetics", true, false);
    RegConsoleCmd("sm_mymodule", Command_MyModule);
}

public Action Command_MyModule(int client, int args)
{
    if (US_IsLoaded(client))
    {
        US_OpenStoreMenu(client);
    }
    return Plugin_Handled;
}

public Action US_OnPurchasePre(int client, const char[] itemId, bool equipAfterPurchase)
{
    return Plugin_Continue;
}
```

To make the store an optional dependency of your plugin, include it with `REQUIRE_PLUGIN` undefined and check `LibraryExists("umbrella_store")` before calling natives:

```c
#undef REQUIRE_PLUGIN
#include <umbrella_store>
#define REQUIRE_PLUGIN
```

## Building from source

Only the SourceMod compiler is needed; [MultiColors](https://github.com/Bara/Multi-Colors) is bundled under `scripting/include`.

```
cd addons/sourcemod/scripting
spcomp64 -i <sourcemod>/scripting/include -i include store_core.sp -o ../plugins/store_core.smx
```

## Repository layout

| Path | Contents |
| --- | --- |
| `addons/sourcemod/plugins` | Compiled plugins |
| `addons/sourcemod/scripting` | SourcePawn sources |
| `addons/sourcemod/scripting/include` | Public API include, module helpers, bundled MultiColors |
| `addons/sourcemod/configs/umbrella_store` | Items, quests, `items.d/`, and `config_examples/` |
| `addons/sourcemod/translations` | Phrase files |
| `materials`, `models` | Shipped cosmetic assets |

## Compatibility

- Built for Counter-Strike: Source. The economy, casino, and chat modules use generic SourceMod APIs; the cosmetic modules rely on CS:S entities, temp entities, and projectile classnames.
- The camera module depends on the server allowing thirdperson.
- On CS:GO, chat colors are limited to the classic MultiColors subset.

## License

[GNU General Public License v3.0](LICENSE)

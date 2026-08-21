# Umbrella Store

A modular SourceMod store suite for Source 1 servers — persistent economy, casino games, cosmetics, quests, marketplace, and a public API for third-party modules.

**Current version:** `1.5.2` · **Requires:** SourceMod 1.12+ · **License:** GPLv3

Umbrella Store is not a patched legacy fork. It is built as a framework: `store_core` provides the economy, inventory, storage, and extension backbone, and every game or cosmetic feature ships as an independent module on top of it.

---

## Features

### Economy & platform (`store_core`)

- Persistent credits, inventory, and equip state (SQLite or MySQL)
- Item schema v2 with backward compatibility for old item configs
- Player-to-player **marketplace** (`!market`) with transaction-safe ownership transfers
- **Voucher** redemption (`!redeem`) for credit and item codes
- **Quests** (`!quests`) and persistent **stats/leaderboards** (`!tops`, `!profile`)
- Item search (`!storesearch`), gifting, and trading
- Persistent audit log (`store_audit_log`, `sm_storeaudit`) and credit ledger
- Multi-Colors chat backend (broader palette on Source 2009 games; CS:GO uses its supported subset)
- Per-player preferences for hiding trails, tracers, paintball, pets, bullet sparks, particles, and laser sights

### Casino modules

| Module | Game |
| --- | --- |
| `store_blackjack` | Blackjack — single, PvP, and table modes with splits and doubles |
| `store_roulette` | Roulette with animated HUD spin |
| `store_crash` | Crash with live multiplier and cash-out |
| `store_coinflip` | Coinflip vs house or PvP |
| `store_dice` | Dice |
| `store_highlow` | High-Low |
| `store_jackpot` | Pooled jackpot |
| `store_lootbox` | Lootboxes |
| `store_daily` | Daily reward with streaks |
| `store_giveaway` | Admin-run giveaways |

### Cosmetic modules (Source 1 / CS:S style)

| Module | Item type |
| --- | --- |
| `store_hats` | Head props |
| `store_trails` | Player trails |
| `store_pets` | Following pets |
| `store_particles` | Aura / trail / spawn / kill / hit particles |
| `store_tracers` | Bullet tracers |
| `store_bulletsparks` | Impact sparks |
| `store_paintball` | Impact decals |
| `store_grenade_skins` | Grenade models |
| `store_grenade_trails` | Grenade trails |
| `store_colored_smoke` | Colored smoke grenades |
| `store_lasersight` | Scoped sniper laser sight |
| `store_sprays` | Custom sprays (use key) |
| `store_saysounds` | Chat-triggered sounds |
| `store_camera` | Thirdperson / mirror camera |

Player skins ship as the built-in `skin` item type inside `store_core`.

---

## Requirements

- **SourceMod 1.12 or newer** — the shipped plugins are built with the latest stable 1.12 release, currently build 7249
- SDKTools and SDKHooks (included with SourceMod)
- SQLite or MySQL, depending on the database entry you configure in `databases.cfg`

## Installation

1. Copy the `addons` folder into the game server.
2. Configure the `store_database` entry in `addons/sourcemod/configs/databases.cfg`.
3. Load the plugins once so SourceMod generates the cfg files automatically.
4. Adjust the generated cfg files under `addons/sourcemod/cfg/sourcemod`.
5. Replace the examples in `addons/sourcemod/configs/umbrella_store/umbrella_store_items.txt` with your real items.
6. Use `config_examples/` as per-module references, and drop real per-module item files into `items.d/*.txt` if you want the core to load them separately.
7. Add the model, material, sound, and decal files referenced by your items to the server and your FastDL delivery path.
8. Optionally define quests in `umbrella_store_quests.txt`.
9. Restart the server or reload the plugins.

## Player commands

| Command | Description |
| --- | --- |
| `!store` | Open the store menu |
| `!market` / `!mercado` | Player marketplace: browse, list, buy, cancel |
| `!redeem` / `!voucher` / `!codigo <code>` | Redeem a voucher code |
| `!storesearch` / `!buscar <text>` | Search the item catalog |
| `!profile` / `!perfil` | Player summary backed by persistent stats |
| `!quests` / `!misiones` | Quest progress menu |
| `!tops` / `!leaderboards` | Leaderboard hub |
| `!topcredits` `!topprofit` `!topdaily` `!topbj` `!topcf` `!topcrash` `!toproulette` | Individual leaderboards |
| `!profileexport` | Export a text snapshot of your profile |
| `!hidetrails` `!hidetracers` `!hidepaintball` `!hidepets` `!hidebulletsparks` `!hideparticles` `!hidelaser` | Hide cosmetic rendering locally |

Say sounds trigger from chat text; equipped sprays are placed with the use key while aiming at a nearby surface.

## Admin commands

| Command | Description |
| --- | --- |
| `sm_storeadmin` | Admin menu: credits, inventory, config reload |
| `sm_storeaudit [target\|global] [limit]` | Recent audit events from `store_audit_log` |
| `sm_storedebug <player>` | Economy/profile snapshot to console |
| `sm_storequestsdebug <player>` | Quest state, completions, and lock reasons |
| `sm_storeexport <player>` | Export another player's snapshot |
| `sm_createvoucher <code> <credits> [max_uses] [expires_hours]` | Create a credit voucher |
| `sm_createitemvoucher <code> <item_id> [max_uses] [expires_hours]` | Create an item voucher |
| `sm_disablevoucher <code>` | Disable a voucher |
| `sm_reloadstore` | Reload item and quest configs |

## Extending the store

Third-party modules integrate through the public API (v7) in [`umbrella_store.inc`](addons/sourcemod/scripting/include/umbrella_store.inc) without editing the core: menu sections, custom item types, item metadata, equipped-item enumeration, transaction-safe credit deltas, shared DB access, stats, quests, leaderboards, and pre/post forwards for purchase, equip, trade, credits, and inventory changes.

```c
#include <sourcemod>
#include <umbrella_store>

public void OnPluginStart()
{
    US_RegisterMenuSection("my_module", "My Module", "sm_mymodule", 40);
    US_RegisterItemType("player_badge", "cosmetics", true, false);
}

public Action Command_MyModule(int client, int args)
{
    if (!US_IsLoaded(client))
    {
        return Plugin_Handled;
    }

    US_OpenStoreMenu(client);
    return Plugin_Handled;
}

public Action US_OnPurchasePre(int client, const char[] itemId, bool equipAfterPurchase)
{
    return Plugin_Continue;
}
```

## Repository layout

| Path | Contents |
| --- | --- |
| `addons/sourcemod/plugins` | Compiled plugins |
| `addons/sourcemod/scripting` | SourcePawn sources |
| `addons/sourcemod/scripting/include/umbrella_store.inc` | Public include for modules |
| `addons/sourcemod/configs/umbrella_store/umbrella_store_items.txt` | Item schema examples |
| `addons/sourcemod/configs/umbrella_store/items.d` | Optional real item config fragments |
| `addons/sourcemod/configs/umbrella_store/config_examples` | Per-module config examples |
| `addons/sourcemod/configs/umbrella_store/umbrella_store_quests.txt` | Optional quest definitions |
| `addons/sourcemod/translations` | Phrase files (es, en, ru, chi, pt, fr, de) |

## Compatibility notes

- Targets Source 1 / SourceMod servers.
- Cosmetic modules target Counter-Strike: Source style Source 2009 entities, temp entities, and projectile classnames.
- The camera module depends on thirdperson behavior being allowed by the game/server.

# Migration Notes

This document describes the current migration story as Umbrella Store moves from a modular suite toward a framework-oriented Source 1 platform.

## Compatibility guarantees for this phase

The current implementation keeps these compatibility promises:

- legacy natives remain available
- existing item configs continue to load
- existing player/admin commands keep working
- the database entry is still controlled by `store_database`
- modules do not need to migrate all at once

## Public API migration

Old modules may keep using:

- `US_IsLoaded`
- `US_GetCredits`
- `US_SetCredits`
- `US_AddCredits`
- `US_TakeCredits`
- `US_HasItem`
- `US_GiveItem`
- `US_RemoveItem`
- `US_Casino_Register`
- `US_Casino_Unregister`
- `US_OpenCasinoMenu`

New or updated modules should target the v5 API for:

- opening the main store menu
- registering menu sections
- discovering item catalog data
- purchase/equip validation
- purchase/equip execution
- item type registration
- item metadata lookup
- equipped item enumeration
- shared storage access
- stats reporting
- audit logging

API v5 keeps the previous public surface and adds these module-facing natives:

- `US_IsItemEquipped`
- `US_GetEquippedItemCount`
- `US_GetEquippedItemIdByIndex`
- `US_LogAuditEvent`
- `US_ApplyCreditDelta`
- `US_ApplyCreditDeltas`
- `US_ApplyCreditDeltaWithQuery`

Those natives are used by the Source 1 cosmetic modules that need to inspect all active items on a player, such as multiple hats, grenade skins by grenade type, and say sounds owned by trigger.
Particle items also use equipped-item enumeration so aura, trail, spawn, kill, and hit particle slots can coexist without making `particle` globally exclusive.

## `store_daily` migration

Before this phase, `store_daily` duplicated:

- database bootstrap
- driver detection
- table creation logic
- escaping helpers
- its own manual DB ownership

Now `store_daily`:

- reuses the database configured by the core
- clones the core DB handle through `US_GetDatabaseHandle()`
- ensures its table through `US_DB_EnsureTable()`
- escapes through `US_DB_Escape()`
- completes claim persistence and credit reward in one core-owned transaction
- exposes canonical `umbrella_store_daily_*` cvars while preserving `store_daily_*` as hidden legacy aliases

This is the reference pattern for future first-party modules that need persistent storage.

## Item schema migration

No forced migration is required.

Legacy items still load.

Recommended gradual upgrade path:

1. keep existing item ids unchanged
2. add `category` where grouping matters
3. add `description` and `rarity` for clearer store menus
4. use `sale_price` or `sell_percent_override` if the default global sell logic is not enough
5. use `requires_item`, `starts_at`, and `ends_at` for progression/seasonal content
6. use `metadata` for module-specific payloads

## Source 1 cosmetic modules

This phase adds first-party modules for:

- player skins through the built-in core `skin` item type
- hats
- trails
- grenade trails
- tracers
- paintball impacts
- say sounds
- pets
- colored smoke
- grenade skins
- bullet sparks
- laser sights
- MVP sounds
- sprays
- particles

Their separated item examples live in:

- `addons/sourcemod/configs/umbrella_store/config_examples`

The examples are references only. Real installs must provide the exact model, material, decal, and sound files referenced by their item configs.

Real per-module item configs can now be split into:

- `addons/sourcemod/configs/umbrella_store/items.d/*.txt`

The core loads `umbrella_store_items.txt` first and then loads `items.d/*.txt` in sorted filename order. Duplicate item ids are rejected so one item id has one authoritative definition.

Cosmetic runtime settings now generate their own `cfg/sourcemod/umbrella_store_<module>.cfg` files. Hide preferences for trails, tracers, paintball, pets, bullet sparks, and particles are persisted through ClientPrefs cookies. MVP sound volume is also persisted through ClientPrefs.

Particle configs should use `effect` for the Source particle effect name and `file` for the `.pcf` path. Zephyrus examples use `name` for the effect name, but Umbrella Store reserves `name` for the item display name in its current item schema.

## Cvar naming story

The repository still contains legacy cvar namespaces for compatibility.

Current reality:

- core still uses established `store_*` cvars for its long-lived public surface
- `daily`, `coinflip`, and `giveaway` now expose canonical `umbrella_store_*` cvars while preserving their old names as hidden aliases
- older modules still use their previous namespaces where changing them would break installs
- new framework-facing documentation recommends `umbrella_store_*` for future module work

In practice, migration should be handled gradually and deliberately, not through destructive renames.

## Chat color backend migration

The core now renders store chat output through the bundled Multi-Colors backend.

Current reality:

- legacy tags such as `{DEFAULT}`, `{TEAM}`, `{GREEN}`, `{PURPLE}`, and similar still work
- those legacy tags are normalized to Multi-Colors names internally
- item configs may now also use Multi-Colors color names directly such as `{orchid}`, `{lightblue}`, or `{teamcolor}`
- Source 2009 games can use the broader Multi-Colors / MoreColors palette
- CS:GO uses the classic Multi-Colors profile, so only its supported subset is guaranteed there
- the core remaps some common CS:GO aliases automatically, for example `{pink}` -> `{orchid}` and `{cyan}` -> `{lightblue}`
- the old `store_chat_extended_colors` cvar remains only as legacy compatibility surface and no longer controls chat color behavior

## Stats base

This phase introduces a new persistent table:

- `store_player_stats`

It is intended as the first reusable base for:

- progression
- profile views
- module metrics
- future leaderboards
- future quests

Current built-in stats are intentionally conservative and can be expanded safely later.

The current platform already uses this base for:

- daily streak tracking
- module profit tracking for blackjack, coinflip, crash, and roulette
- leaderboard commands such as `!topprofit`, `!topdaily`, `!topbj`, `!topcf`, `!topcrash`, and `!toproulette`

This phase also introduces the first persistent quest scaffolding through:

- `store_player_quests`
- `store_player_quest_counts`
- quest registration natives in the current API
- daily and casino module quest examples built on top of the shared core
- quest titles that may be registered as raw text or translation phrase keys
- built-in `!profile` / `!perfil` and `!quests` / `!misiones` menus that consume the shared stats and quest layers
- built-in `!tops` / `!leaderboards` / `!rankings` menu for shared rankings
- optional file-defined quests in `addons/sourcemod/configs/umbrella_store/umbrella_store_quests.txt`
- config-defined quests can now add presentation and reward metadata such as `category`, `description`, `reward_item`, `repeatable`, `max_completions`, `requires_quest`, `starts_at`, and `ends_at`
- root admin support commands such as `sm_storedebug`, `sm_storequestsdebug`, and `sm_storeexport`
- built-in player marketplace commands such as `!market` / `!mercado`
- new core-owned marketplace tables: `store_market_listings` and `store_market_sales`

Marketplace migration notes:

- no migration is required for existing installs
- marketplace data lives in new core-owned tables and is created automatically
- listed items are now intentionally blocked from equip, sell, gift, and trade flows while a listing is active
- the canonical marketplace cvars use the `umbrella_store_market_*` namespace

## Search, vouchers, and audit

This phase also adds core-owned administrative tables:

- `store_audit_log`
- `store_vouchers`
- `store_voucher_redemptions`

Players can use `!storesearch <text>` to search the loaded item catalog and `!redeem <code>` to redeem credit or item vouchers. Root admins can create or disable vouchers through `sm_createvoucher`, `sm_createitemvoucher`, and `sm_disablevoucher`.

`sm_storeaudit` now reads the general audit log instead of only the credit ledger. The old credit ledger remains available internally as `store_credits_ledger`, while module authors should use `US_LogAuditEvent` for module-specific events.

## What still counts as legacy

The following are still legacy concepts even though they remain supported:

- older one-off natives that do not expose rich validation or menu/extensibility behavior
- module-local assumptions that bypass the current public API when a better public primitive now exists
- module-specific DB bootstrap patterns outside the shared core storage layer

## Recommended migration strategy for third-party developers

1. keep legacy integration working first
2. detect and target API version 4+
3. move validation to `US_CanPurchaseItem` / `US_CanEquipItem`
4. move execution to `US_TryPurchaseItem` / `US_TryEquipItem`
5. register menu sections instead of patching core menus manually
6. register item types instead of hardcoding custom type assumptions in the core
7. report module stats through `US_AddStat` / `US_SetStatMax`
8. register custom stat keys and leaderboards through `US_RegisterStatKey` / `US_RegisterLeaderboard` when your module exposes public rankings
9. write module audit entries through `US_LogAuditEvent` for player-facing rewards, purchases, redemptions, or admin actions

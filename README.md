# Palworld Autonomy

An autonomous capture and gathering mod for [Palworld Mods](../palworld-mods).
The controller runs locally inside the game; no AI service, network API, desktop
input driver or external mod loader is used.

## Use

Install **Autonomy** from **Options → Mods → Manage mods**. Configure it from the
Mods page, join a temporary world, then turn **Running** on. Installation and
launch never start the controller automatically.

Capture modes are **all**, **selected** and **off**. The default all-species quota
is five lifetime captures. Selected targets use `Lamball=5; Cattiva=3`; the
catalogue also accepts game character IDs. Materials use `Wood=100; Stone=50` or
the dedicated Wood and Stone controls. Set the radius, level ceiling, sphere
reserve, retreat health and session duration before starting.

The controller observes nearby eligible wild Pals and natural resources, plans
walking routes, aligns the camera before actions, confirms captures using the
replicated capture history, and confirms gathering through inventory changes.
It pauses in menus, releases inputs on travel/disable, stops on death, and can
return to the session's starting point. It does not spawn items or bypass the
host's ordinary game rules. Supply spheres, food and suitable equipment first.

## Scope

This is an on-foot controller. It does not provide universal quest completion,
base construction, flying navigation, guaranteed dungeon solving or every combat
strategy. Unreachable routes, missing supplies and unreplicated objects can stop
progress. Do not interpret a unit-test pass as a complete multiplayer playtest.

The first independent release preserves the controller and validates its state
machine, native observations and installation. Full capture/gather sessions on
the new native runtime remain a separate gameplay validation requirement.

## Language

Requires Palworld Mods 0.3.0 or later. All labels, choices and hints follow the
shared **Options → Mods → Language** preference. Automatic uses the actual game
language; manual selection persists between sessions. All 17 locales ship in
`locales/*.json`, with stable keys and an English fallback. Settings keep their
original IDs when the display language changes. Status and event messages are
rendered in the current language without resetting the running controller. Parsed
Pal and material IDs, such as `Lamball` and `Wood`, stay unchanged in every language.

New features must include every translation and pass `scripts/check_localization.py`.
See the runtime's [localization contract](../palworld-mods/docs/localization.md).

## Develop

`runner.lua` contains the injected decision state machine. `settings.lua` holds
pure goal rules. The backend delegates engine access to the shared runtime;
no copy of an external loader or another mod is included.

```sh
python3 scripts/verify.py
lua tests/runner.lua
lua tests/presentation.lua
```

Place this repository beside `palworld-mods` before packaging the app. Personal
capture histories, inventories, worlds, configuration and logs are never source
fixtures and are excluded from Git.

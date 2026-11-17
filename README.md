# ASA Profiles

**Keep several single-player setups for ARK: Survival Ascended on one PC, each with its own settings, active mods and saves, and switch between them in one click.**

ASA only has one set of single-player settings and one save per map. If you play a vanilla run on The Island and a modded run (Dino Overhaul X 2, Primal Fear…) on the side, the settings and mods of one leak into the other, and a second game on the same map overwrites the first. Loading a modded save without its mods can even wipe the modded content from it.

ASA Profiles gives each playthrough its own copy of the game's `Saved` folder:

- settings (`GameUserSettings.ini`, `Game.ini`), including multipliers and graphics
- the list of **active mods** for single player
- mods' own settings (`Saved\SaveGames`)
- all your single-player worlds and your survivor

The mods you have downloaded stay shared, so each mod is only downloaded once. Each profile just decides which ones are active.

*Français : voir [plus bas](#français).*

---

## Download and start

1. Download **`ASA-Profiles.cmd`** from the [latest release](../../releases/latest).
2. Double-click it.
3. Windows may show a SmartScreen warning because the file is not signed. Click **More info → Run anyway**. The file is plain text: you can open it in Notepad and read it before running it.

That's it. There is nothing to install. The tool finds your ASA installation through Steam on its own (any drive or Steam library). If it can't, it asks you for the folder.

The tool is in English or French depending on your Windows language.

> **Before your first switch, make a backup.** Use the *Back up (zip)* button, or copy `…\ARK Survival Ascended\ShooterGame\Saved` somewhere safe. The tool never deletes anything, but your saves are worth a copy.

## Usage

| Button | What it does |
|---|---|
| **Activate and launch ASA** | Puts the selected profile in place and starts the game through Steam. Double-clicking a profile does the same. |
| **Activate only** | Puts the selected profile in place without starting the game. |
| **New profile…** | Creates an empty profile. Leave the box ticked to copy the active profile's settings and mods (but not its saves) as a starting point. |
| **Back up (zip)** | Zips the selected profile to `Documents\ASA-Profiles-Backups`. |
| **Open folder** | Opens the folder where inactive profiles are kept. |

**First run:** if you already have a game, the tool asks for a name for it (for example *Vanilla The Island*). It becomes your first profile.

**Typical workflow:**
1. Name your current game, e.g. *Vanilla*.
2. Click **New profile…** and enter *DOX2 Ragnarok*.
3. Select it and click **Activate and launch ASA**.
4. In game, pick the mods and settings for this run and start playing.
5. Next time, open the tool, pick the profile you want and click **Activate and launch ASA**.

Close ASA before switching. The tool refuses to switch while the game is running.

## How it works

The game always reads `ShooterGame\Saved`. The tool moves the active profile's `Saved` folder into a storage folder and moves the profile you chose back into its place:

```
ARK Survival Ascended\ShooterGame\
├── Saved\                ← the active profile (what the game reads)
└── ASA-Profiles\
    ├── Vanilla\          ← inactive profiles, untouched
    └── Primal Fear\
```

Both folders are on the same drive, so a switch is an instant rename: nothing is copied or deleted, however big your saves are. A small hidden file `Saved\.asa-profile` records which profile is active.

The tool's own settings are kept in `%APPDATA%\ASA-Profiles\config.json`.

## Good to know

- **Uninstalling ASA through Steam may delete the `ASA-Profiles` folder** with the rest of the game folder. Back up your profiles (zip button) before uninstalling.
- **Steam Cloud.** If Steam Cloud is in use for ASA on your account, the tool warns you on first run. Turn it off for ASA (Steam → right-click the game → Properties → General) so Steam can't put another profile's save back.
- **Only one game per map, per profile.** That's how ASA works. To keep two separate games on The Island, use two profiles.
- **Steam version on Windows only.** The Xbox / Microsoft Store version keeps its files elsewhere and is not supported yet.
- **Advanced:** if you need extra files outside `Saved` to follow each profile, add their paths (relative to `ShooterGame`) to `ExtraPaths` in `config.json`. A standard Steam install doesn't need this.

## Running the PowerShell script directly

`ASA-Profiles.ps1` contains the same code without the small launcher at the top of the `.cmd`. If you prefer it, right-click → *Run with PowerShell*. If your execution policy blocks it, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\ASA-Profiles.ps1
```

## Requirements

Windows 10 or 11, with Windows PowerShell 5.1 (built into Windows). ARK: Survival Ascended on Steam.

## License

MIT, see [LICENSE](LICENSE). Provided as is, without warranty. This is a fan-made tool, not affiliated with or endorsed by Studio Wildcard.

---

## Français

**Plusieurs parties solo d'ARK: Survival Ascended sur un même PC, chacune avec ses réglages, ses mods actifs et ses sauvegardes, et on passe de l'une à l'autre en un clic.**

En solo, ASA n'a qu'un seul jeu de réglages et une seule sauvegarde par map : les réglages et les mods d'une partie s'appliquent aux autres, et une deuxième partie sur la même map écrase la première. ASA Profiles donne à chaque partie sa propre copie du dossier `Saved` : réglages, mods actifs, réglages des mods, mondes et personnage. Les mods téléchargés restent communs, chaque profil choisit seulement ceux qui sont activés.

**Utilisation :** télécharge `ASA-Profiles.cmd` et double-clique dessus. Si Windows affiche un avertissement : *Informations complémentaires → Exécuter quand même*. L'outil trouve ASA tout seul via Steam et s'affiche en français si Windows est en français.

**Avant le premier changement de profil, fais une sauvegarde** (bouton *Sauvegarder (zip)*, ou copie du dossier `ShooterGame\Saved`). Ferme ASA avant de changer de profil.

**À savoir :** une désinstallation d'ASA par Steam peut supprimer le dossier `ASA-Profiles` avec le reste du jeu, donc sauvegarde tes profils avant. Seule la version Steam sur Windows est prise en charge.

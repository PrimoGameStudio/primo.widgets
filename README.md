# PrimoWidgets

Desktop widgets for [Omarchy](https://omarchy.org/) that render **behind all open windows** on the bottom layer — a clean, wallpaper-like desktop layer above the wallpaper.

![Preview](preview.png)

## Widgets

| Widget | Description | Default |
|--------|-------------|---------|
| **Clock** | Large time display with 12h/24h, seconds, theme-aware color | enabled |
| **Date** | Full date line (`Monday, August 27`) | disabled |
| **Cava** | Round (radial) audio visualizer powered by `cava` — system audio, hides when idle | disabled |
| **Steam** | Capsule-art grid of recently played Steam games — local files only, click to launch | disabled |

All text widgets share one bottom-layer surface per output.

## Features

- `WlrLayer.Bottom` + `ExclusionMode.Ignore` — behind every app window; visible on empty desktop.
- Wallpaper-like stays click-through by default; interactive widgets capture input via a per-tile `Region` mask.
- Theme-aware color for text widgets (`Color.bar.text`). Bundled **Inter** + **Plus Jakarta Sans** OFL fonts.
- Per-output filtering via `outputs` array.
- Hot-reloaded (~2s); supports legacy `~/.config/omaclock/config.json`.

## Requirements


## Install

```bash
omarchy plugin add https://github.com/primo/primo.widgets
omarchy restart shell
```

## Configure

Primary config: `~/.config/omarchy/plugins/primo.widgets/config.json` (symlinked from plugin `config.json`). Falls back to `~/.config/omaclock/config.json` and flat legacy keys. Edit → reloads in ~2s.

### Top-level

| Key | Default | Description |
|-----|---------|-------------|
| `namespace` | `primo.widgets` | Layer-shell namespace |
| `outputs` | `["DP-2"]` | Outputs to show on. `[]` or `[""]` = all screens. Legacy `clockOutput` also accepted. |

### Per-widget (`widgets.clock` / `widgets.date`)

Accepted by every widget (`clock`, `date`, `cava`, `steam`), so it is listed once here rather than repeated in each table.

| Key | Default | Description |
|-----|---------|-------------|
| `workspace` | `"all"` | Show only on this Hyprland workspace. `"all"` (or omit the key) shows it everywhere; otherwise a single workspace, matched against the workspace **name** — so `2`, `"web"` and `"special:cliamp"` all work, case-insensitively |

Scoping is **per output**: a widget pinned to workspace `2` appears on whichever
monitor currently has workspace 2 active, and is hidden on the others. Special
workspaces only match if you name them explicitly, so a widget pinned to `1`
stays hidden on `special:cliamp`.

The workspace does **not** need to exist yet. A widget pinned to `8` stays
hidden on every workspace you currently have, and appears by itself as soon as
workspace 8 is created and focused — no config edit needed.

Layer-shell surfaces are not compositor-managed windows, so Hyprland cannot
scope them with a `windowrulev2`; visibility is tracked from the active
workspace instead. If the workspace state is not readable yet (at startup) the
widget is shown rather than hidden, so nothing silently disappears.

| Key | Clock | Date | Description |
|-----|-------|------|-------------|
| `enabled` | `true` | `false` | Show/hide |
| `format` | `h:mm` | `dddd, MMMM d` | Qt date/time format |
| `showSeconds` | `false` | — | Tick per second |
| `fontFamily` | `""` | `""` | `""`=Inter, `"system"`=platform, or family |
| `fontWeight` | `200` | `300` | 100–900 |
| `fontScale` | `0.15` | `0.06` | Fraction of screen height |
| `letterSpacing` | `-3` | `0` | Glyph spacing |
| `color` | `""` | `""` | `""`=bar text, or CSS |
| `opacity` | `0.92` | `0.85` | 0–1 |
| `position` | `top` | `top` | `top`/`center`/`bottom` when `yRatio` is `null` |
| `xRatio` | `0.5` | `0.5` | Horizontal 0–1 |
| `yRatio` | `0.20` | `0.33` | Vertical 0–1 |

### Cava (`widgets.cava`)

Round audio visualizer. Requires the `cava` binary (reads system audio via
PipeWire monitor of the default sink — no configuration needed). Uses an inline
`cava -p /dev/stdin` config, so your `~/.config/cava/config` is never touched.
Display-only and click-through. One `cava` process runs per visible screen.

| Key | Default | Description |
|-----|---------|-------------|
| `enabled` | `false` | Show/hide |
| `xRatio` | `0.5` | Horizontal center 0–1 |
| `yRatio` | `0.5` | Vertical center 0–1 |
| `size` | `280` | Ring diameter px (≥120) |
| `bars` | `48` | Bars around the ring (8–256) |
| `framerate` | `60` | Frames per second (15–120) |
| `innerRadiusRatio` | `0.35` | Inner ring radius as fraction of half size |
| `barSpacing` | `2` | Gap between bars px |
| `barThickness` | `0` | Explicit bar width px (`0` = auto from spacing/circumference, 1–256px explicit; silent dots capped at 12px, base ring at 8px) |
| `color` | `""` | `""`=bar text, `"system"`=theme palette gradient (muted → foreground → accent from ~45% height → urgent on peaks, follows theme switches), or CSS |
| `opacity` | `0.9` | 0–1 |
| `hideWhenIdle` | `true` | Hide ring after silence (process keeps running) |
| `idleTimeout` | `3.0` | Seconds of silence before hiding |
| `sensitivity` | `100` | Cava sensitivity % |
| `ringPulse` | `1.0` | Base-ring throb with music 0–1 (`0` = static ring): radius breathes +10%, brightens, warms toward accent in `system` mode |

Enable centered below the clock:

```json
{
  "widgets": {
    "cava": { "enabled": true, "xRatio": 0.5, "yRatio": 0.5, "size": 280, "bars": 48 }
  }
}
```

### Steam (`widgets.steam`)

Recently played Steam games as a capsule-art grid. **Local files only** —
no network, no API key. Recency comes from
`~/.local/share/Steam/userdata/*/config/localconfig.vdf`, names from
installed `appmanifest_*.acf` files across all library folders, art from the
local `appcache/librarycache` (both old `header.jpg` and new hashed
`library_capsule.jpg` layouts). Refreshed every `refreshInterval` seconds.
Click a tile to launch via `steam://rungameid` (needs `interactive`,
shares the input mask); uninstalled games with cached art still launch
(Steam will prompt to install).

Non-Steam shortcuts merge into the same recency-sorted grid from
`userdata/*/config/shortcuts.vdf` (`LastPlayTime`, playtime from
`localconfig.vdf` under the signed id) with art from the local
`config/grid` custom artwork (`_hero.jpg` first). Shortcut tiles carry a
small `non-Steam` badge and fall back to a letter tile when no custom art is
set — set artwork in the Steam client (Manage → Set custom artwork) to
promote one to a full capsule on the next poll. Like Steam games, shortcuts
launch via `steam://rungameid` using the 64-bit shortcut id
(`(unsigned 32-bit appid << 32) | 0x02000000`), so Steam applies the
shortcut's own launch options.

Battle.net games (umu-launcher prefix, e.g. `~/Games/battlenet`) merge into
the same grid from the local `Battle.net.config` (`Games.<uid>.LastPlayed`,
`LastActioned` fallback — no network). Names/launch codes come from a local
uid table (`hs_beta` → Hearthstone, `s1` → StarCraft, …), art from the local
Lutris coverart (`~/.local/share/lutris/coverart`, cropped to capsule).
Battle.net tiles carry a `Battle.net` badge, fall back to a letter tile when
no cover exists, and launch directly via
`umu-run Battle.net.exe --exec="launch <CODE>"`.

| Key | Default | Description |
|-----|---------|-------------|
| `enabled` | `false` | Show/hide |
| `count` | `5` | Games to show (1–15, most recent first) |
| `tileWidth` | `208` | Tile width px (≥120) |
| `tileHeight` | `120` | Art height px (≥60, cropped via `PreserveAspectCrop`) |
| `spacing` | `12` | Gap between tiles px |
| `cornerRadius` | `10` | Tile clip radius px |
| `showName` | `true` | Game name under tile |
| `showMeta` | `true` | Relative last-played + total hours (`3d ago  •  340h`) |
| `showBigPicture` | `true` | Extra Steam-logo tile at the end linking to Big Picture mode (`steam://open/bigpicture`); hidden when `interactive: false` |
| `bigPictureLabel` | `"Big Picture"` | Label under the Big Picture tile |
| `fontFamily` | `""` | `""`=Inter, `"system"`=platform, or family |
| `color` | `"#ffffff"` | Name and metadata text color |
| `opacity` | `0.95` | 0–1 |
| `interactive` | `true` | Click-to-launch via mask; `false` = display-only |
| `xRatio` | `0.17` | Horizontal center 0–1 |
| `yRatio` | `0.90` | Vertical center 0–1 |
| `refreshInterval` | `60` | Re-poll helper, seconds (≥15) |
| `requireArt` | `true` | Skip Steam games with no local capsule art (shortcuts always show — letter tile fallback) |
| `showShortcuts` | `true` | Merge non-Steam shortcuts into the grid |
| `showSourceBadge` | `true` | `non-Steam` badge on shortcut tiles, `Battle.net` badge on Battle.net tiles |
| `showBattlenet` | `true` | Merge Battle.net games (local umu prefix) into the grid |
| `battlenetPrefix` | `""` | `""`=auto (`~/Games/battlenet`); override prefix path |
| `battlenetConfig` | `""` | `""`=auto (newest `Battle.net.config` under the prefix); override path |
| `lutrisCoverDir` | `""` | `""`=auto (`~/.local/share/lutris/coverart`); art dir for Battle.net tiles |
| `hideIds` | `["480"]` | Appids to skip (Spacewar test app) |
| `steamId` | `""` | `""`=merge all `userdata/*`; or pin one id |
| `steamRoot` | `""` | `""`=auto (`~/.local/share/Steam`); override path |
| `names` | `{}` | Manual `{"appid": "Name"}` overrides (e.g. uninstalled games showing `App <id>`) |

Bottom-left below the clock:

```json
{
  "widgets": {
    "steam": { "enabled": true, "count": 5, "xRatio": 0.17, "yRatio": 0.9 }
  }
}
```


### Examples

Clock everywhere, but only show the Steam row on workspace 8 — which need not
exist yet; the row appears on its own once you create and focus it:

```json
{
  "outputs": ["DP-2", "DP-3"],
  "widgets": {
    "clock": { "workspace": "all" },
    "steam": { "enabled": true, "workspace": 8 }
  }
}
```

Enable date below clock:

```json
{
  "outputs": ["DP-2"],
  "widgets": {
    "clock": { "format": "h:mm", "yRatio": 0.20 },
    "date":  { "enabled": true, "format": "dddd, MMMM d", "yRatio": 0.33 }
  }
}
```


## Adding a new widget

1. Create `widgets/MyWidget.qml` with `property var widgetSettings` + `property color themeColor` (see `Clock.qml`, `Date.qml`, `Cava.qml`, `Steam.qml`).
2. Add defaults in `Service.qml` (`defaults.widgets.myWidget`). For clickable widgets, expose tile items via a `clickTargets` array (see `Steam.qml`) and merge them into the panel input mask.
3. Instantiate in `Service.qml` surface (for array widgets: `Repeater` + `Widgets.MyWidget { surfaceItem: surface; widgetSettings: modelData }`).
4. Add entry in `config.json` and document.

## Structure

```
primo.widgets/
  Service.qml        # host: config, screens, shared PanelWindow + mask
  steam_recent.py    # helper: local Steam recents -> JSON (no network)
  widgets/
    Clock.qml
    Date.qml
    Cava.qml         # cava-powered round audio visualizer
    Steam.qml        # recent-games capsule grid (uses steam_recent.py)
  fonts/
  config.json
  manifest.json
```

`DesktopClock.qml` remains as deprecated shim.

## Notes

- **Layer:** `Bottom` is behind tiled windows — widgets only usable on empty desktop by design. If you need over-windows, change `WlrLayershell.layer` to `Top`/`Overlay` in `Service.qml`.

## License

- Plugin code: [MIT](LICENSE)
- Bundled Inter font: [SIL OFL 1.1](fonts/OFL.txt)
- Bundled Plus Jakarta Sans font: [SIL OFL 1.1](fonts/PlusJakartaSans-OFL.txt)

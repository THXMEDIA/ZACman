// Intentionally minimal: the game runs entirely inside the loaded page and
// needs no Node/Electron APIs exposed to it. This file exists as the place
// to bridge a future Steamworks SDK (achievements, cloud saves, rich
// presence) into window.* for web/index.html to call — see
// ../docs/STEAM_ROADMAP.md, "Steamworks-Integration".

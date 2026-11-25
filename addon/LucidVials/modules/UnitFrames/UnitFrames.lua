-- Einheitenrahmen (Spieler, Ziel, Ziel des Ziels): Unterbefehle von /vials. UnitFrames.sub ist dieselbe Tabelle wie
-- ns.commands (Core.lua): was ein Rahmen-Modul dort eintraegt, ist direkt ein /vials-Befehl. Der Rahmen-Skin (Skin.lua) traegt
-- on/off/test/debug/slosh/style/auren/fx/debuffs ein, XP.lua "xp", die Diagnose-Probe (Probe.lua, nur Entwicklung) "probe".
-- Die Hilfezeilen stehen hier in fester Reihenfolge; /vials ohne Argument zeigt sie (ns.PrintHelp).
local _, ns = ...

local UnitFrames = ns.UnitFrames or {}
ns.UnitFrames = UnitFrames
UnitFrames.sub = ns.commands

for _, key in ipairs({ "HELP_FRAMES", "HELP_FRAMES_SLOSH", "HELP_FRAMES_STYLE", "HELP_FRAMES_AUREN", "HELP_FRAMES_FX",
    "HELP_FRAMES_TESTFX", "HELP_FRAMES_TESTZIEL", "HELP_FRAMES_XP" }) do
    ns.AddHelp(key)
end

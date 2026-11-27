-- Texte des Einstellungsfensters mit Reitern (Delta Ausbau 1.1.0, E2): Reiter, Rahmen-Waehler, Allgemein, Fluessigkeit,
-- Profile. Fuegt Schluessel in beide Sprachen ein (geladen nach enUS/deDE). Die Texte der einzelnen Reiter
-- Portrait, Texte & Zahlen und Schrift stehen in den Locale-Dateien ihrer Etappen; die Reiter-Beschriftungen aller sechs
-- Reiter stehen hier, damit die Leiste vollstaendig ist.
local _, ns = ...
ns.Locales = ns.Locales or {}

local en = ns.Locales.enUS
local de = ns.Locales.deDE

local function add(target, texts)
    for k, v in pairs(texts) do target[k] = v end
end

add(en, {
    UI_DEFAULT_MARK = "(default)",
    UI_DEFAULT_VALUE = "Default: %s",
    UI_DEFAULT_RESET = "Right-click: back to default",
    UI_DEFAULT_ON = "on",
    UI_DEFAULT_OFF = "off",
    -- Hilfezeile ueberschreibt die aus enUS.lua
    HELP_CONFIG = "/vials config [tab] - open or close the settings window; with a tab (general, liquid, portrait, text, font, profiles) it opens that tab",
    UI_CONFIG_UNKNOWN_TAB = "Unknown tab \"%s\". Available tabs: %s.",

    -- Reiter
    UI_TAB_GENERAL = "General",
    UI_TAB_LIQUID = "Liquid",
    UI_TAB_PORTRAIT = "Portrait",
    UI_TAB_TEXT = "Text & numbers",
    UI_TAB_FONT = "Font",
    UI_TAB_PROFILES = "Profiles",

    -- Rahmen-Waehler
    UI_SCOPE_LABEL = "Applies to",
    UI_SCOPE_ALL = "All frames",
    UI_SCOPE_PLAYER = "Player",
    UI_SCOPE_TARGET = "Target",
    UI_SCOPE_TOT = "Target of target",
    UI_SCOPE_PICK_TIP = "Choose whether the settings on this tab apply to all frames or to one frame only.",
    UI_SCOPE_OWN = "Own settings for this frame",
    UI_SCOPE_OWN_TIP = "On: this frame gets its own copy of the settings on this tab (starting from the “all frames” values) and no longer follows later changes to “all frames”. Off: it follows “all frames” again.",
    UI_SCOPE_RESET = "Reset to “all frames”",
    UI_SCOPE_RESET_TIP = "Deletes this frame's own settings on this tab; it follows “all frames” again.",
    UI_SCOPE_HINT_ALL = "Changes apply to every frame that has no own settings.",
    UI_SCOPE_HINT_INHERIT = "This frame follows “all frames” (grey values). Tick the box to set it separately.",
    UI_SCOPE_HINT_OWN = "This frame has its own settings; changes to “all frames” do not affect it.",

    -- Allgemein
    UI_GENERAL_HEAD_OTHER = "Other unit frame addons",
    UI_GENERAL_FOREIGN_NOTE = "Addons such as ElvUI, Shadowed Unit Frames or PitBull replace Blizzard's unit frames. While one of them is active, Lucid Vials stays off and says so here. More settings are on the other tabs: liquid, portrait, text, font and profiles.",

    -- Fluessigkeit
    UI_LIQUID_HEAD_SLOSH = "Sloshing (the same for all frames)",
    UI_LIQUID_SLOSH_GLOBAL = "Sloshing is one physics for all frames. Choose “All frames” above to change it.",
    UI_LIQUID_REGEN = "Show regeneration clearly",
    UI_LIQUID_REGEN_TIP = "Your own mana tube only: when mana regeneration starts again after the five-second rule, a bright pulse flashes at the end of the liquid and the bubbling starts at full strength. Applies to all frames.",
    UI_LIQUID_COUNTDOWN = "Countdown to regeneration",
    UI_LIQUID_COUNTDOWN_TIP = "Your own mana tube only: after each spell a small ring next to the end of the tube fills up over the five seconds until mana regeneration resumes. With “Show regeneration clearly” the pulse follows. Applies to all frames.",
    UI_LIQUID_SECONDS = "Show seconds",
    UI_LIQUID_SECONDS_TIP = "Shows the remaining seconds inside the countdown ring. Only with “Countdown to regeneration” switched on.",
    UI_LIQUID_HEAL_STRENGTH = "Heal preview strength",
    UI_LIQUID_HEAL_STRENGTH_TIP = "How strongly the incoming heal preview stands out from the liquid: higher values give a brighter, more opaque layer with a soft shimmer at its edge. 100 % is the usual look. Applies to all frames.",

    -- Profile
    UI_PROF_HEAD_ACTIVE = "Profile of this character",
    UI_PROF_INFO = "This character uses the profile “%s”. Characters without their own choice use “Default”.",
    UI_PROF_PICK = "Profile for this character",
    UI_PROF_PICK_TIP = "Every character can use its own profile. Switching applies immediately, no /reload.",
    UI_PROF_HEAD_MANAGE = "Manage profiles",
    UI_PROF_NAME = "Name for new, copy and rename",
    UI_PROF_NEW = "New",
    UI_PROF_NEW_TIP = "Creates a profile with the default values under the entered name and switches this character to it.",
    UI_PROF_COPY = "Copy",
    UI_PROF_COPY_TIP = "Copies the active profile under the entered name and switches this character to the copy.",
    UI_PROF_RENAME = "Rename",
    UI_PROF_RENAME_TIP = "Gives the active profile the entered name. “Default” cannot be renamed.",
    UI_PROF_RESET = "Reset",
    UI_PROF_RESET_TIP = "Sets the active profile back to the default values. Click twice to confirm.",
    UI_PROF_DELETE = "Delete",
    UI_PROF_DELETE_TIP = "Deletes the active profile; characters that used it fall back to “Default”. “Default” cannot be deleted. Click twice to confirm.",
    UI_PROF_CONFIRM = "Really?",
    UI_PROF_DONE_NEW = "Profile “%s” created and activated.",
    UI_PROF_DONE_COPY = "Profile “%s” copied and activated.",
    UI_PROF_DONE_RENAME = "Profile renamed to “%s”.",
    UI_PROF_DONE_RESET = "Profile “%s” reset to the default values.",
    UI_PROF_DONE_DELETE = "Profile “%s” deleted.",
    UI_PROF_ERR_NAME = "Please enter a valid name (1 to %d characters, no control characters, no vertical bar).",
    UI_PROF_ERR_EXISTS = "A profile named “%s” already exists.",
    UI_PROF_ERR_DEFAULT = "The profile “Default” cannot be renamed or deleted.",
    UI_PROF_ERR_FAILED = "That did not work (%s).",
})

add(de, {
    UI_DEFAULT_MARK = "(Standard)",
    UI_DEFAULT_VALUE = "Standard: %s",
    UI_DEFAULT_RESET = "Rechtsklick: zurück auf Standard",
    UI_DEFAULT_ON = "an",
    UI_DEFAULT_OFF = "aus",
    HELP_CONFIG = "/vials config [Reiter] - öffnet oder schließt das Einstellungsfenster; mit Reiter (general, liquid, portrait, text, font, profiles) öffnet es direkt diesen Reiter",
    UI_CONFIG_UNKNOWN_TAB = "Unbekannter Reiter \"%s\". Verfügbare Reiter: %s.",

    UI_TAB_GENERAL = "Allgemein",
    UI_TAB_LIQUID = "Flüssigkeit",
    UI_TAB_PORTRAIT = "Portrait",
    UI_TAB_TEXT = "Texte & Zahlen",
    UI_TAB_FONT = "Schrift",
    UI_TAB_PROFILES = "Profile",

    UI_SCOPE_LABEL = "Gilt für",
    UI_SCOPE_ALL = "Für alle Rahmen",
    UI_SCOPE_PLAYER = "Spieler",
    UI_SCOPE_TARGET = "Ziel",
    UI_SCOPE_TOT = "Ziel des Ziels",
    UI_SCOPE_PICK_TIP = "Wähle, ob die Einstellungen dieses Reiters für alle Rahmen oder nur für einen Rahmen gelten.",
    UI_SCOPE_OWN = "Eigene Einstellungen für diesen Rahmen",
    UI_SCOPE_OWN_TIP = "An: Dieser Rahmen bekommt eine eigene Kopie der Einstellungen dieses Reiters (zunächst mit den Werten von „für alle“) und folgt späteren Änderungen von „für alle“ nicht mehr. Aus: Er folgt wieder „für alle“.",
    UI_SCOPE_RESET = "Auf „für alle“ zurücksetzen",
    UI_SCOPE_RESET_TIP = "Löscht die eigenen Einstellungen dieses Rahmens auf diesem Reiter; er folgt wieder „für alle“.",
    UI_SCOPE_HINT_ALL = "Änderungen gelten für jeden Rahmen ohne eigene Einstellungen.",
    UI_SCOPE_HINT_INHERIT = "Dieser Rahmen folgt „für alle“ (graue Werte). Setze den Haken, um ihn getrennt einzustellen.",
    UI_SCOPE_HINT_OWN = "Dieser Rahmen hat eigene Einstellungen; Änderungen bei „für alle“ betreffen ihn nicht.",

    UI_GENERAL_HEAD_OTHER = "Andere Einheitenrahmen-Addons",
    UI_GENERAL_FOREIGN_NOTE = "Addons wie ElvUI, Shadowed Unit Frames oder PitBull ersetzen Blizzards Einheitenrahmen. Solange eines davon aktiv ist, bleibt Lucid Vials aus und sagt es hier. Weitere Einstellungen findest du auf den anderen Reitern: Flüssigkeit, Portrait, Texte, Schrift und Profile.",

    UI_LIQUID_HEAD_SLOSH = "Schwappen (für alle Rahmen gleich)",
    UI_LIQUID_SLOSH_GLOBAL = "Das Schwappen ist eine gemeinsame Physik für alle Rahmen. Wähle oben „Für alle Rahmen“, um es zu ändern.",
    UI_LIQUID_REGEN = "Regeneration deutlich zeigen",
    UI_LIQUID_REGEN_TIP = "Nur deine eigene Mana-Röhre: Setzt die Mana-Regeneration nach der Fünf-Sekunden-Regel wieder ein, blitzt am Ende der Flüssigkeit ein heller Impuls auf und das Sprudeln startet mit voller Stärke. Gilt für alle Rahmen.",
    UI_LIQUID_COUNTDOWN = "Countdown bis zur Regeneration",
    UI_LIQUID_COUNTDOWN_TIP = "Nur deine eigene Mana-Röhre: Nach jedem Zauber läuft neben dem Ende der Röhre ein kleiner Ring in den fünf Sekunden voll, bis die Mana-Regeneration wieder einsetzt. Mit „Regeneration deutlich zeigen“ folgt danach der Impuls. Gilt für alle Rahmen.",
    UI_LIQUID_SECONDS = "Sekunden anzeigen",
    UI_LIQUID_SECONDS_TIP = "Zeigt die restlichen Sekunden im Countdown-Ring. Nur mit eingeschaltetem „Countdown bis zur Regeneration“.",
    UI_LIQUID_HEAL_STRENGTH = "Heil-Vorschau-Stärke",
    UI_LIQUID_HEAL_STRENGTH_TIP = "Wie deutlich sich die Vorschau eingehender Heilung von der Flüssigkeit abhebt: Höhere Werte ergeben eine hellere, kräftigere Lage mit einem dezenten Schimmer an ihrer Kante. 100 % ist die gewohnte Optik. Gilt für alle Rahmen.",


    UI_PROF_HEAD_ACTIVE = "Profil dieses Charakters",
    UI_PROF_INFO = "Dieser Charakter nutzt das Profil „%s“. Charaktere ohne eigene Wahl nutzen „Default“.",
    UI_PROF_PICK = "Profil für diesen Charakter",
    UI_PROF_PICK_TIP = "Jeder Charakter kann ein eigenes Profil nutzen. Das Umschalten wirkt sofort, ohne /reload.",
    UI_PROF_HEAD_MANAGE = "Profile verwalten",
    UI_PROF_NAME = "Name für Neu, Kopieren und Umbenennen",
    UI_PROF_NEW = "Neu",
    UI_PROF_NEW_TIP = "Legt ein Profil mit den Standardwerten unter dem eingegebenen Namen an und schaltet diesen Charakter darauf um.",
    UI_PROF_COPY = "Kopieren",
    UI_PROF_COPY_TIP = "Kopiert das aktive Profil unter dem eingegebenen Namen und schaltet diesen Charakter auf die Kopie um.",
    UI_PROF_RENAME = "Umbenennen",
    UI_PROF_RENAME_TIP = "Gibt dem aktiven Profil den eingegebenen Namen. „Default“ lässt sich nicht umbenennen.",
    UI_PROF_RESET = "Zurücksetzen",
    UI_PROF_RESET_TIP = "Setzt das aktive Profil auf die Standardwerte zurück. Zur Bestätigung zweimal klicken.",
    UI_PROF_DELETE = "Löschen",
    UI_PROF_DELETE_TIP = "Löscht das aktive Profil; Charaktere, die es nutzten, fallen auf „Default“ zurück. „Default“ lässt sich nicht löschen. Zur Bestätigung zweimal klicken.",
    UI_PROF_CONFIRM = "Wirklich?",
    UI_PROF_DONE_NEW = "Profil „%s“ angelegt und aktiviert.",
    UI_PROF_DONE_COPY = "Profil „%s“ kopiert und aktiviert.",
    UI_PROF_DONE_RENAME = "Profil umbenannt in „%s“.",
    UI_PROF_DONE_RESET = "Profil „%s“ auf die Standardwerte zurückgesetzt.",
    UI_PROF_DONE_DELETE = "Profil „%s“ gelöscht.",
    UI_PROF_ERR_NAME = "Bitte einen gültigen Namen eingeben (1 bis %d Zeichen, keine Steuerzeichen, kein senkrechter Strich).",
    UI_PROF_ERR_EXISTS = "Ein Profil namens „%s“ gibt es schon.",
    UI_PROF_ERR_DEFAULT = "Das Profil „Default“ lässt sich nicht umbenennen oder löschen.",
    UI_PROF_ERR_FAILED = "Das hat nicht geklappt (%s).",
})

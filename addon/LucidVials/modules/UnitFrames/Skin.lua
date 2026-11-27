-- Einheitenrahmen im Lucid-Stil (Delta "Fluessiges Leben", E1 + E2): Reskin von Spieler-, Ziel- und Ziel-des-Ziels-Rahmen.
--
-- Kein eigener Secure-Rahmen: Klicks, Rechtsklick-Menue, Fokus und Bearbeitungsmodus bleiben Blizzard. Lucid
--   * macht Blizzards Zier-Texturen (Rahmen, Glanz/Blitz, Status, Ruf-Farbe, Stufen-Kreis, Name, Stufe, sofortige Fuellung der
--     Lebens-/Ressourcenleiste, Verlust-Animation) per SetAlpha(0) unsichtbar - nie SetPoint/SetSize/SetScale/Show/Hide an
--     Blizzard-Frames, keine Felder an Blizzard-Frames, keine ersetzten Methoden. Ausschalten setzt das Alpha sofort auf 1 (ohne
--     /reload). Blizzards Alpha wird nie gelesen (Spieler-Texturen haben laut S0 ein secret Alpha),
--   * legt eigene Kind-Frames in die Blizzard-Rahmen: Bronze-Portraetring, je eine Fluessigkeits-Roehre (ns.Liquid) im
--     Bronze-Kapselrahmen fuer Leben und Ressource (beim Ziel gespiegelt), Name in Marcellus (Pergament-Gold, Tintenschatten), Stufen-Plaettchen. Als Kinder
--     wandern sie im Bearbeitungsmodus mit und erben Sichtbarkeit/Alpha (Ausblenden-Modul, Fader),
--   * speist die Roehren per Weg A (S0-Entscheidung): UNIT_HEALTH/UNIT_MAXHEALTH, UNIT_POWER_UPDATE/UNIT_MAXPOWER/
--     UNIT_DISPLAYPOWER, Zielwechsel, PLAYER_ENTERING_WORLD; das Ziel des Ziels hat keine Einheiten-Ereignisse und wird
--     (wie bei Blizzard) abgefragt (TOT_POLL). Werte gehen unveraendert (oft secret) an die eigene StatusBar.
-- Blizzards Lebens-/Ressourcentext, Heilvorhersage und Absorb bleiben sichtbar: die Roehren liegen auf einer Ebene UNTER
-- Blizzards Leiste. Fremde Einheitenrahmen-Addons (CONFLICT_ADDONS) => der Skin bleibt aus. Im Fahrzeug bleibt der
-- Spielerrahmen Blizzard (eigene Fahrzeug-Optik). Optionen: Reiter "Allgemein"/"Fluessigkeit" (UI/ConfigGeneral.lua, UI/ConfigLiquid.lua) und /vials on|off|test|debug
-- und /vials slosh (E3: Schwappen aus der Bewegungsphysik ns.LiquidPhysics, Regler unitframes.liquid.slosh*) sowie
-- /vials style kante|kolben (Darstellung unitframes.liquid.style: Fluessigkeitskante oder Kolben-Kammer) und
-- /vials fx|debuffs on|off (Effekte aus LiquidFx.lua: Schaden, Heilung, Ressourcen-Strom; Schwaechungs-Schlieren).
-- Profil-Schema 2 (Schema.lua): Werte "fuer alle" plus Eigenwerte je Rahmen; die Fluessigkeit (style/smooth/trail/fx/debuffs)
-- wirkt je Rahmen, das Schwappen global. Weitere Module haengen sich ueber Skin.OnConfigChanged und Skin.RegisterTest an.
local _, ns = ...
local Compat, Store, L = ns.Compat, ns.Store, ns.L
local Style, Liquid, Physics = ns.Style, ns.Liquid, ns.LiquidPhysics
local UnitFrames = ns.UnitFrames

local Skin = {}
UnitFrames.Skin = Skin
ns.UnitFrameSkin = Skin

Skin.FRAMES = { "player", "target", "tot" }
Skin.TOT_POLL = 0.25             -- s, Abfrage des Ziels des Ziels
Skin.TEST_STEP = 1.6             -- s je Testwert
Skin.TEST_MAX = 100
Skin.TEST_SEQ = { 100, 72, 78, 41, 46, 88, 18, 25, 64, 100 } -- Testwerte (Leben); Ressource laeuft versetzt
Skin.TEST_SLOSH = { "run", "turn", "jump" } -- Testmodus: simulierte Bewegung je Testschritt (reihum), damit es im Stand schwappt
-- Testmodus: Schwaechungs-Schlieren je Testschritt (reihum), Heilung/Treffer folgen den Testwerten
Skin.TEST_DEBUFFS = { {}, { "Poison" }, { "Poison", "Curse" }, { "Magic", "Disease", "Curse", "Poison" }, { "Magic" } }
-- /vials test <wort>: Einzel-Effekte ohne echten Kampf (de/en); Bannarten zeigen ihre Schlieren LiquidFx.INK.testSecs s
Skin.TEST_ARGS = { gift = { "Poison" }, poison = { "Poison" }, fluch = { "Curse" }, curse = { "Curse" },
    krankheit = { "Disease" }, disease = { "Disease" }, magie = { "Magic" }, magic = { "Magic" },
    alle = { "Magic", "Curse", "Disease", "Poison" }, all = { "Magic", "Curse", "Disease", "Poison" },
    heilung = "heal", heal = "heal", treffer = "hit", hit = "hit", mana = "mana", schwappen = "slosh", slosh = "slosh",
    schild = "shield", shield = "shield",
    aus = "off", off = "off" }
-- Quelle der Dispel-Typ-IDs in /vials debug
Skin.ID_SOURCE = { learned = "gelernt", ["learned+fallback"] = "gelernt+annahme", enum = "enum", fallback = "annahme" }
Skin.TEST_FX_CRIT = 30           -- Testwert-Sprung ab dem Heilung/Treffer als kritisch gezeigt werden
Skin.RING_SCALE = 1.24           -- Ring-Durchmesser / Portraet (Innenradius der Textur 0,79 => Ring liegt am Portraetrand)
Skin.PLATE = { square = 0.40, round = 0.40, inset = 0.10, font = 0.5 }
Skin.NAME = { color = { 0.90, 0.80, 0.60 }, shadow = { 0.08, 0.04, 0.016, 0.85 }, x = 3, y = 1 }
local MEDIA = "Interface\\AddOns\\LucidVials\\Media\\"
Skin.RING_TEX = MEDIA .. "uf-ring"          -- Gemini-Ring (scripts/gen-unitframe-media.mjs), Innen durchsichtig
Skin.PLATE_TEX = { square = MEDIA .. "uf-level-square", round = MEDIA .. "uf-level-round" }

-- Fluessigkeitsfarben (Leben): Spieler gruen-gold, Ziel nach Reaktion
Skin.TINTS = {
    player = { tex = "mono", color = { 0.46, 0.82, 0.30 } }, -- wie freundliche Ziele (15.11.)
    hostile = { tex = "color", color = { 1, 1, 1 }, base = { 0.42, 0.07, 0.04 } },
    neutral = { tex = "mono", color = { 1.0, 0.80, 0.24 } },
    friendly = { tex = "mono", color = { 0.46, 0.82, 0.30 } },
    tapped = { tex = "mono", color = { 0.58, 0.55, 0.52 } },
}
-- Ersatzfarbe fuer unbekannte Ressourcen-Tokens (PowerBarColor ohne Eintrag oder unlesbar): neutrales Hellblau. Nicht fuer Mana
-- gedacht - Mana hat in PowerBarColor einen eigenen Eintrag und kommt von dort.
Skin.POWER_DEFAULT = { 0.20, 0.45, 1.0 }
-- Kinder von Blizzards ManaBar (parentKeys), die Reste ueber der Lucid-Roehre zeigen: Puls bei voller Ressource, Gewinn-/
-- Verlust-Blitz, Kosten-Vorschau, Funke. Je Rahmen nur, wenn vorhanden (fehlen sie im Client, ist das kein Befund).
Skin.MANA_PARTS = { "FullPowerFrame", "FeedbackFrame", "ManaCostPredictionBar", "Spark" }

-- Je Rahmen: Einheit, Blizzard-Teile (parentKeys, Alpha 0), Name/Stufe/Portraet, Spiegelung (Portraet rechts), Plaettchen,
-- Schriftgroesse, Ersatzmasse (wenn Groessen nicht lesbar sind)
local SPEC = {
    player = { unit = "player", hide = { "FrameTexture", "AlternatePowerFrameTexture", "FrameFlash", "StatusTexture",
            "LevelBackgroundCircle", "PlayerFrameHealthBarAnimatedLoss" },
        name = { "PlayerName", "Name" }, level = { "PlayerLevelText", "LevelText" }, portrait = { "PlayerPortrait", "Portrait" },
        mirrored = false, plate = "square", nameSize = 13, portraitSize = 60, health = { 124, 20 }, power = { 124, 10 } },
    target = { unit = "target", hide = { "FrameTexture", "Flash", "ReputationColor", "LevelBackgroundCircle", "HighLevelTexture" },
        -- optional (Deco.lua ersetzt sie; fehlen sie im Client, ist das kein Befund): Boss-Drache, Rar-Stern, Quest-Zeichen, Raidmarker
        hideOpt = { "BossPortraitFrameTexture", "BossIcon", "QuestIcon", "RaidTargetIcon" },
        name = { "Name" }, level = { "LevelText" }, portrait = { "Portrait" },
        mirrored = true, plate = "badge", nameSize = 13, portraitSize = 58, health = { 124, 20 }, power = { 124, 10 } },
    tot = { unit = "targettarget", hide = { "FrameTexture" },
        name = { "Name" }, level = {}, portrait = { "Portrait" },
        mirrored = false, plate = "round", nameSize = 10, portraitSize = 37, health = { 70, 10 }, power = { 70, 6 } },
}
Skin.SPEC = SPEC

-- Fremde Einheitenrahmen-Addons: ist eines geladen, bleibt der Skin aus (ElvUI nur mit aktivem Einheitenrahmen-Modul).
-- HaboonOrbs fehlt bewusst: es ersetzt die Rahmen nur in einem Modus, der sich nicht verlaesslich erkennen laesst (Delta).
Skin.CONFLICT_ADDONS = { "ElvUI", "ShadowedUnitFrames", "PitBull4", "UnitFramesLite", "XPerl", "EasyFrames", "GlassUnitFrames" }

-- Profil ----------------------------------------------------------------------------------------------------------------
-- Schema 2 (Schema.lua): Werte "fuer alle" plus Eigenwerte je Rahmen (unitframes.per), Bereiche per Skin.RegisterArea.
local Schema = ns.UnitFrameSchema
Skin.AURA_SIZE = Schema.AURA_SIZE
Skin.STYLES = Schema.STYLES
Skin.Defaults = Schema.Defaults
Skin.Validate = Schema.Validate
Skin.RegisterArea = Schema.RegisterArea

Store.RegisterSection("unitframes", { default = Skin.Defaults, validate = Skin.Validate })

local function storedConfig()
    if not Store.db then return nil end
    local p = Store.GetActive()
    return p and p.unitframes
end

--- wirksame Einstellungen: ohne frameId "fuer alle" (wie bisher), mit frameId ("player"|"target"|"tot") die aufgeloesten
--- Werte des Rahmens; "xp" (XP-Roehre) erbt "fuer alle"
function Skin.GetConfig(frameId)
    local stored = storedConfig()
    local c = (type(stored) == "table" and (Skin.Validate(stored))) or Skin.Defaults()
    return Schema.Resolve(c, frameId)
end

function Skin.GetFrameConfig(frameId) return Skin.GetConfig(frameId) end

-- Beobachter: fn(frameId|nil, area|nil) nach jeder Aenderung (nil, nil = Profilwechsel/-neuinhalt)
local changeListeners = {}
function Skin.OnConfigChanged(fn)
    assert(type(fn) == "function", "LucidVials: OnConfigChanged braucht eine Funktion")
    changeListeners[#changeListeners + 1] = fn
end

local function configChanged(frameId, area)
    for _, fn in ipairs(changeListeners) do xpcall(function() fn(frameId, area) end, geterrorhandler()) end
end

local function commit(clean, frameId, area)
    Store.GetActive().unitframes = clean
    Skin.Refresh()
    configChanged(frameId, area)
    return true
end

--- Feld setzen (path z. B. "enabled", "frames.tot", "liquid.trail", "font.health.face"); nur nach Pruefung im Profil.
--- frameId nil = "fuer alle", sonst Eigenwert des Rahmens (nur mit Skin.SetOverride an). Liefert true oder nil.
function Skin.Set(path, value, frameId)
    local clean, area = Schema.Apply(Store.GetActive().unitframes, path, value, frameId)
    if not clean then return nil end
    return commit(clean, frameId, area)
end

--- Eigenwert eines Bereichs fuer einen Rahmen an (kopiert "fuer alle") bzw. aus (erbt wieder). Liefert true oder nil.
function Skin.SetOverride(frameId, area, on)
    local clean = Schema.Override(Store.GetActive().unitframes, frameId, area, on == true)
    if not clean then return nil end
    return commit(clean, frameId, area)
end

function Skin.HasOverride(frameId, area)
    local stored = storedConfig()
    return Schema.HasOverride(type(stored) == "table" and (Skin.Validate(stored)) or nil, frameId, area)
end

-- Hilfen ----------------------------------------------------------------------------------------------------------------
local function field(t, key)
    if type(t) ~= "table" or Compat.IsSecret(t) then return nil end
    local ok, v = pcall(function() return t[key] end)
    if ok and not Compat.IsSecret(v) then return v end
    return nil
end

local function isObject(v)
    return type(v) == "table" and not Compat.IsSecret(v) and type(field(v, "GetObjectType")) == "function"
end

local function call(obj, method, ...)
    local fn = field(obj, method)
    if type(fn) ~= "function" then return false end
    return pcall(fn, obj, ...)
end

local function num(obj, method)
    local ok, v = call(obj, method)
    return ok and Compat.Num(v) or nil
end

local function readFlag(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or Compat.IsSecret(v) then return nil end
    return v
end

local function addonLoaded(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, name)
    return ok and (v == true or v == 1)
end

local function elvUnitFramesOn()
    local ok, on = pcall(function()
        local E = _G.ElvUI and _G.ElvUI[1]
        local uf = E and E.private and E.private.unitframe
        if type(uf) ~= "table" or type(uf.enable) ~= "boolean" then return true end
        return uf.enable
    end)
    return not ok or on ~= false
end

--- Name des geladenen Fremd-Einheitenrahmen-Addons oder nil
function Skin.Conflict()
    for _, name in ipairs(Skin.CONFLICT_ADDONS) do
        if addonLoaded(name) and (name ~= "ElvUI" or elvUnitFramesOn()) then return name end
    end
    return nil
end

--- Breitensuche ueber parentKeys (nur echte Kinder: GetParent() == Knoten); exclude wird nicht betreten (der ToT-Rahmen ist
--- ein Kind des Zielrahmens). Liefert key -> Objekt (erster, flachster Treffer).
local SEARCH_DEPTH, SEARCH_MAX = 6, 400
local function survey(root, exclude)
    local found = {}
    local queue, seen, visits, qi = { { obj = root, depth = 0 } }, { [root] = true }, 0, 1
    if exclude then seen[exclude] = true end
    while qi <= #queue and visits < SEARCH_MAX do
        local node = queue[qi]
        qi = qi + 1
        local keys = {}
        pcall(function()
            for k, v in pairs(node.obj) do
                if type(k) == "string" and type(v) == "table" then keys[#keys + 1] = k end
            end
        end)
        table.sort(keys)
        for _, k in ipairs(keys) do
            local v = field(node.obj, k)
            if isObject(v) and not seen[v] then
                local okP, p = call(v, "GetParent")
                if not okP or p == node.obj then
                    seen[v] = true
                    visits = visits + 1
                    if found[k] == nil then found[k] = v end
                    if node.depth + 1 < SEARCH_DEPTH then queue[#queue + 1] = { obj = v, depth = node.depth + 1 } end
                end
            end
        end
    end
    return found
end

local function totRoot()
    if isObject(_G.TargetFrameToT) then return _G.TargetFrameToT end
    local t = field(_G.TargetFrame, "totFrame")
    if isObject(t) then return t end
    return nil
end

local function rootOf(id)
    if id == "player" then return isObject(_G.PlayerFrame) and _G.PlayerFrame or nil end
    if id == "target" then return isObject(_G.TargetFrame) and _G.TargetFrame or nil end
    return totRoot()
end

local function first(found, keys)
    for _, k in ipairs(keys) do if found[k] then return found[k] end end
    return nil
end

-- Zustand ---------------------------------------------------------------------------------------------------------------
local skins = {}          -- id -> Skin-Zustand (eigene Frames, gefundene Blizzard-Teile, versteckte Regionen)
local active = false      -- Modul aktiv (nach PLAYER_LOGIN)
local cfg = nil           -- Einstellungen (Refresh)
local blocker = nil       -- Fremd-Addon oder nil
local testActive = false
local testTicker, testIndex = nil, 0
local totTicker = nil
local hooksInstalled = false
local errors, errorCount = {}, 0
local reapplyQueued = false
local setListening -- Ereignis-Anmeldung (unten definiert)

local function recordError(err)
    errorCount = errorCount + 1
    errors[#errors + 1] = string.sub(tostring(err), 1, 160)
    while #errors > 5 do table.remove(errors, 1) end
end
Skin.RecordError = recordError -- auch fuer XP.lua (Fehler landen in /vials debug)

local function engaged() return active and cfg ~= nil and not blocker and (cfg.enabled or testActive) end

local function inVehicle()
    return readFlag(_G.UnitHasVehicleUI, "player") == true
end

local function wanted(id)
    if not engaged() or not cfg.frames[id] then return false end
    if id == "player" and inVehicle() then return false end
    return true
end

-- Blizzard-Teile ausblenden / zurueckstellen (Alpha nur setzen, nie lesen) -------------------------------------------------
-- Blizzard pulsiert manche Teile selbst per SetAlpha in jedem Bild (StatusTexture: rot im Kampf, gelb beim Ausruhen;
-- FrameFlash). Darum je ausgeblendetem Teil ein Nach-Haken auf SetAlpha, das wieder 0 setzt, solange der Teil versteckt ist.
local hiddenBy = {}    -- Region -> sk, der sie gerade versteckt (nil = nicht versteckt)
local alphaHooked = {} -- Region -> true
local rezeroing = false
local function rezero(r)
    if rezeroing or not hiddenBy[r] then return end
    rezeroing = true
    call(r, "SetAlpha", 0)
    rezeroing = false
end

local function hideRegion(sk, r)
    if not isObject(r) then return end
    if not sk.hidden[r] then
        sk.hidden[r] = true
        sk.hiddenCount = sk.hiddenCount + 1
    end
    hiddenBy[r] = sk
    if not alphaHooked[r] and type(hooksecurefunc) == "function" then
        alphaHooked[r] = pcall(hooksecurefunc, r, "SetAlpha", rezero) or nil
    end
    call(r, "SetAlpha", 0)
end

local function fillTexture(bar)
    local ok, t = call(bar, "GetStatusBarTexture")
    if ok and isObject(t) then return t end
    return nil
end

Skin.HideRegion = hideRegion

--- versteckten Teil wieder freigeben (Alpha 1, SetAlpha-Haken greift nicht mehr)
function Skin.ShowRegion(sk, r)
    if not (isObject(r) and sk.hidden[r]) then return end
    sk.hidden[r] = nil
    sk.hiddenCount = sk.hiddenCount - 1
    if hiddenBy[r] == sk then hiddenBy[r] = nil end
    call(r, "SetAlpha", 1)
end

local function hideBlizzard(sk)
    for _, k in ipairs(SPEC[sk.id].hide) do hideRegion(sk, sk.found[k]) end
    for _, k in ipairs(SPEC[sk.id].hideOpt or {}) do hideRegion(sk, sk.found[k]) end
    if Skin.Deco then Skin.Deco.HideBlizzard(sk) end
    hideRegion(sk, sk.nameFs)
    hideRegion(sk, sk.levelFs)
    hideRegion(sk, fillTexture(sk.hb))
    hideRegion(sk, fillTexture(sk.mb))
    -- Reste der ManaBar: Blizzard animiert deren Alpha nur an den Texturen in den Kind-Frames (Spike-/Puls-Textur, Blitz-Texturen),
    -- nie am Kind-Frame selbst; darum wird der Frame verdeckt (Kinder erben sein Alpha). Setzt Blizzard dessen Alpha neu
    -- (FullPowerFrame:SetAlpha), greift der SetAlpha-Nachhaken aus hideRegion. Ausschalten: restoreBlizzard gibt alles frei.
    if sk.mb then
        for _, k in ipairs(Skin.MANA_PARTS) do hideRegion(sk, field(sk.mb, k)) end
    end
end

-- Heil-Vorschau im Design (Liquid.AddHealGhost): Blizzards flache Fuellung der eigenen/fremden Vorschau (Segment .Fill) per
-- Alpha 0, Lucids Geist-Lage reicht bis zum rechten Rand der Segment-Maske (.FillMask), die Blizzard aus den Werten legt.
-- Nach jedem UpdateFillPosition und Zeigen/Verbergen der Segmente neu verankert (Nachher-Hooks, nichts ersetzt).
Skin.HEAL_BARS = { "MyHealPredictionBar", "OtherHealPredictionBar" }
local ghostHooked = {}

-- Schild/Heil-Absorption (Liquid.AddSegment) und ihr Glimmen (Liquid.AddSegGlow): Blizzards Teile per Alpha 0, Lucids Lagen
-- zwischen linkem und rechtem Rand der Segment-Maske. Glows folgen Show/Hide von Blizzards Glow-Textur.
Skin.SEG_BARS = { TotalAbsorbBar = "shield", HealAbsorbBar = "healAbsorb" }
Skin.SEG_HIDE = { "Fill", "TiledFillOverlay", "LeftShadow", "RightShadow" }
Skin.SEG_GLOWS = { OverAbsorbGlow = "over", OverHealAbsorbGlow = "overHeal" }

local function syncHealGhost(sk)
    if not (sk and sk.applied and sk.health) then return end
    if sk.health.ghost then
        local region
        for i = #Skin.HEAL_BARS, 1, -1 do -- fremde Heilung liegt hinter der eigenen: ihr Ende zuerst
            local seg = sk.found and sk.found[Skin.HEAL_BARS[i]]
            if not region and isObject(seg) and Compat.QueryBool(seg, "IsShown") == true then
                local m = field(seg, "FillMask")
                if isObject(m) then region = m end
            end
        end
        Liquid.SetHealGhost(sk.health, region)
    end
    for bk, key in pairs(Skin.SEG_BARS) do
        local seg = sk.found and sk.found[bk]
        local m = isObject(seg) and Compat.QueryBool(seg, "IsShown") == true and field(seg, "FillMask") or nil
        Liquid.SetSegment(sk.health, key, isObject(m) and m or nil)
    end
    for gk, key in pairs(Skin.SEG_GLOWS) do
        local tex = sk.found and sk.found[gk]
        Liquid.SetSegGlow(sk.health, key, isObject(tex) and Compat.QueryBool(tex, "IsShown") == true)
    end
end
Skin.SyncPrediction = function(id) syncHealGhost(skins[id]) end

local function hookSync(sk, obj, isTex)
    if ghostHooked[obj] or type(hooksecurefunc) ~= "function" then return end
    ghostHooked[obj] = true
    local function upd() syncHealGhost(skins[sk.id]) end
    if isTex then
        for _, m in ipairs({ "Show", "Hide", "SetShown" }) do
            if type(field(obj, m)) == "function" then pcall(hooksecurefunc, obj, m, upd) end
        end
        return
    end
    if type(field(obj, "UpdateFillPosition")) == "function" then pcall(hooksecurefunc, obj, "UpdateFillPosition", upd) end
    call(obj, "HookScript", "OnShow", upd)
    call(obj, "HookScript", "OnHide", upd)
end

local function healGhost(sk)
    local any = false
    for _, k in ipairs(Skin.HEAL_BARS) do
        local seg = sk.found and sk.found[k]
        if isObject(seg) then
            any = true
            hideRegion(sk, field(seg, "Fill"))
            hookSync(sk, seg)
        end
    end
    if any then Liquid.AddHealGhost(sk.health) end
    for bk, key in pairs(Skin.SEG_BARS) do
        local seg = sk.found and sk.found[bk]
        if isObject(seg) then
            for _, part in ipairs(Skin.SEG_HIDE) do hideRegion(sk, field(seg, part)) end
            hookSync(sk, seg)
            Liquid.AddSegment(sk.health, key)
        end
    end
    for gk, key in pairs(Skin.SEG_GLOWS) do
        local tex = sk.found and sk.found[gk]
        if isObject(tex) then
            hideRegion(sk, tex)
            hookSync(sk, tex, true)
            Liquid.AddSegGlow(sk.health, key)
        end
    end
    syncHealGhost(sk)
end

--- Ausschalten: Alpha 1, nicht "das alte Alpha" - Blizzards Alpha wird nie gelesen (Spieler-Texturen liefern laut S0 ein
--- secret Alpha). Diese Zier-Texturen stehen bei Blizzard auf 1; Blitz/Status steuert Blizzard ueber Show/Hide bzw. eigene
--- Animationen, die Lucid nicht anfasst.
local function restoreBlizzard(sk)
    for r in pairs(sk.hidden) do
        if hiddenBy[r] == sk then hiddenBy[r] = nil end
        call(r, "SetAlpha", 1)
    end
    sk.hidden = {}
    sk.hiddenCount = 0
end

-- Aufbau ------------------------------------------------------------------------------------------------------------------
--- Schrift eines Textes setzen (Fonts.lua, ns.Fonts): mit element ("name"|"level") gilt die gewaehlte Schrift samt Groesse, Kontur und
--- Schatten des Rahmens frameId, size ist dann die Auto-Groesse (heutige Groesse); ohne element die feste Standard-Optik
--- (Marcellus mit Tintenschatten) fuer Texte ohne eigene Einstellung (Aura-Zaehler).
local function setFont(fs, size, element, frameId)
    local F = ns.Fonts
    if F then
        if element then F.Apply(fs, element, frameId, size) else F.ApplyDefault(fs, size) end
        return
    end
    -- ohne Fonts.lua: der bisherige Weg (Marcellus, Tintenschatten, Rueckfall auf die Standardschrift)
    local path = (Style and Style.FontPath and Style.FontPath("marcellus")) or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local ok, r = call(fs, "SetFont", path, size, "")
    if not ok or r == false then call(fs, "SetFont", _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "") end
    local N = Skin.NAME
    call(fs, "SetShadowColor", N.shadow[1], N.shadow[2], N.shadow[3], N.shadow[4])
    call(fs, "SetShadowOffset", 1, -1)
end
Skin.SetFont = setFont

--- Blizzard-Teile eines Rahmens suchen (einmal je Wurzel; neu, wenn die Wurzel wechselt)
local function discover(sk, root)
    local exclude = (sk.id ~= "tot") and totRoot() or nil
    local found = survey(root, exclude)
    sk.found = found
    local S = SPEC[sk.id]
    local hb = field(root, "healthbar")
    sk.hb = isObject(hb) and hb or found.HealthBar
    local mb = field(root, "manabar")
    sk.mb = isObject(mb) and mb or found.ManaBar
    local nm = field(root, "name")
    sk.nameFs = isObject(nm) and nm or first(found, S.name)
    sk.levelFs = first(found, S.level)
    sk.portrait = first(found, S.portrait)
    local missing = {}
    for _, k in ipairs(S.hide) do if not found[k] then missing[#missing + 1] = k end end
    if not sk.hb then missing[#missing + 1] = "HealthBar" end
    if not sk.mb then missing[#missing + 1] = "ManaBar" end
    if not sk.portrait then missing[#missing + 1] = "Portrait" end
    sk.missing = missing
    sk.root = root
end

local function build(sk, root)
    local holder = CreateFrame("Frame", nil, root)
    holder:SetAllPoints(root)
    sk.holder = holder
    sk.ringFrame = CreateFrame("Frame", nil, holder)
    sk.ring = sk.ringFrame:CreateTexture(nil, "ARTWORK")
    sk.ring:SetTexture(Skin.RING_TEX)
    sk.deco = CreateFrame("Frame", nil, holder)
    sk.name = sk.deco:CreateFontString(nil, "OVERLAY")
    if sk.name.SetWordWrap then sk.name:SetWordWrap(false) end
    local plate = SPEC[sk.id].plate
    if plate then
        sk.plate = sk.deco:CreateTexture(nil, "ARTWORK")
        sk.plate:SetTexture(Skin.PLATE_TEX[plate])
        sk.levelText = sk.deco:CreateFontString(nil, "OVERLAY")
        sk.levelText:SetJustifyH("CENTER")
        if sk.levelText.SetJustifyV then sk.levelText:SetJustifyV("MIDDLE") end
    end
    local mirror = SPEC[sk.id].mirrored -- Ziel: Zierkappe aussen (links), schlichtes Ende am Portraet
    sk.health = Liquid.Create(holder, { frame = "health", mirror = mirror, trail = true })
    sk.power = Liquid.Create(holder, { frame = "power", mirror = mirror, trail = false })
    for _, t in ipairs({ sk.ring, sk.plate }) do if Style and Style.SnapTexture then Style.SnapTexture(t) end end
    if Skin.Deco then Skin.Deco.Build(sk) end -- Flansch, Ziel-Zier, Auren (Deco.lua)
    holder:Hide()
end

local function level(obj) return num(obj, "GetFrameLevel") end

local function layout(sk)
    local S = SPEC[sk.id]
    local root = sk.root
    sk.holder:ClearAllPoints()
    sk.holder:SetAllPoints(root)
    -- Ebenen: Roehren unter Blizzards Leiste (Text, Heilvorhersage, Absorb bleiben darueber)
    local hbL = level(sk.hb) or ((level(root) or 1) + 4)
    local okP, hbParent = call(sk.hb, "GetParent")
    local parentL = okP and level(hbParent) or nil
    local textL = parentL and math.min(hbL, parentL) or hbL
    local base = math.max(0, textL - 3)
    local mbL = level(sk.mb)
    local okMP, mbParent = call(sk.mb, "GetParent")
    local mParentL = okMP and level(mbParent) or nil
    local mtextL = mbL and (mParentL and math.min(mbL, mParentL) or mbL) or textL
    local mbase = math.max(0, mtextL - 3)
    if sk.hb then Liquid.Layout(sk.health, sk.hb, base, S.health[1], S.health[2]) end
    if sk.mb then Liquid.Layout(sk.power, sk.mb, mbase, S.power[1], S.power[2]) end
    -- Portraet-Ring und Plaettchen ueber dem Portraet (und ueber den Roehren-Enden)
    local okPP, portraitParent = call(sk.portrait, "GetParent")
    local pL = okPP and level(portraitParent) or (level(root) or 1)
    local ringL = math.max(pL + 1, base + 4) -- ueber dem Roehren-Rahmen (base + 3)
    sk.ringFrame:SetFrameLevel(ringL)
    sk.deco:SetFrameLevel(ringL + 1)
    local pw = num(sk.portrait, "GetWidth")
    if not (pw and pw > 4) then pw = S.portraitSize end
    sk.pw = pw
    local anchor = sk.portrait or root
    local size = math.floor(pw * Skin.RING_SCALE + 0.5)
    sk.ring:ClearAllPoints()
    sk.ring:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    sk.ring:SetSize(size, size)
    sk.ringSize, sk.anchor = size, anchor
    if sk.plate then
        local P = Skin.PLATE
        local ps = math.floor(pw * P[S.plate] + 0.5)
        local inset = math.floor(pw * P.inset + 0.5)
        sk.plate:ClearAllPoints()
        if S.mirrored then
            sk.plate:SetPoint("CENTER", anchor, "BOTTOMRIGHT", -inset, inset)
        else
            sk.plate:SetPoint("CENTER", anchor, "BOTTOMLEFT", inset, inset)
        end
        sk.plate:SetSize(ps, ps)
        sk.levelText:ClearAllPoints()
        sk.levelText:SetAllPoints(sk.plate)
        setFont(sk.levelText, math.max(7, math.floor(ps * P.font + 0.5)), "level", sk.id)
        local c = Skin.NAME.color
        sk.levelText:SetTextColor(c[1], c[2], c[3])
    end
    -- Name ueber der Lebensroehre (gespiegelt: rechtsbuendig zum Portraet hin)
    local N = Skin.NAME
    local padT = (sk.health.pad and sk.health.pad.top) or 0
    sk.name:ClearAllPoints()
    -- Zwei Anker (links und rechts an der Roehre): der Name ist so breit wie die Roehre und wird mit "..." gekuerzt
    -- (SetWordWrap(false)), statt ueber Ring/Roehre hinauszulaufen. Die Seite, an der er buendig sitzt, bleibt wie bisher.
    if S.mirrored then
        sk.name:SetPoint("BOTTOMRIGHT", sk.health.root, "TOPRIGHT", -N.x, padT + N.y)
        sk.name:SetPoint("BOTTOMLEFT", sk.health.root, "TOPLEFT", N.x, padT + N.y)
        sk.name:SetJustifyH("RIGHT")
    else
        sk.name:SetPoint("BOTTOMLEFT", sk.health.root, "TOPLEFT", N.x, padT + N.y)
        sk.name:SetPoint("BOTTOMRIGHT", sk.health.root, "TOPRIGHT", -N.x, padT + N.y)
        sk.name:SetJustifyH("LEFT")
    end
    setFont(sk.name, S.nameSize, "name", sk.id)
    sk.name:SetTextColor(N.color[1], N.color[2], N.color[3])
    if Skin.Deco then Skin.Deco.Layout(sk) end -- Roehrenenden am Ring (offen), Flansch, Zier-Lagen
end

-- Inhalte -----------------------------------------------------------------------------------------------------------------
local function unitExists(unit)
    local ok, v = pcall(UnitExists, unit)
    return ok and Compat.Bool(v)
end

local function healthTint(sk)
    if sk.id == "player" then return Skin.TINTS.player end
    local u = SPEC[sk.id].unit
    if readFlag(_G.UnitIsUnit, u, "player") == true then return Skin.TINTS.player end
    local stance = Style and Style.Stance and Style.Stance(u)
    return Skin.TINTS[stance or "friendly"] or Skin.TINTS.friendly
end

local function powerTint(sk)
    local u = SPEC[sk.id].unit
    local c = Skin.POWER_DEFAULT
    local ok, ptype, token = pcall(UnitPowerType, u)
    local pbc = _G.PowerBarColor
    if ok and type(pbc) == "table" and not Compat.IsSecret(ptype) and not Compat.IsSecret(token) then
        local e = (type(token) == "string" and pbc[token]) or (Compat.Num(ptype) and pbc[ptype])
        if type(e) == "table" and Compat.Num(e.r) and Compat.Num(e.g) and Compat.Num(e.b) then c = { e.r, e.g, e.b } end
    end
    return { tex = "mono", color = { math.min(1, c[1] * 1.1 + 0.05), math.min(1, c[2] * 1.1 + 0.05), math.min(1, c[3] * 1.1 + 0.05) } }
end

--- Anzeigename: In Forever liefert UnitName (Vorname, Nachname) - dann "Vorname Nachname". In Retail ist die zweite
--- Rueckgabe der Realm (nie anhaengen). Nur zusammensetzen, wenn beide Teile lesbar sind (Compat.Str: nicht secret,
--- nicht leer); sonst bleibt Blizzards Text (ggf. secret, dann unveraendert durchgereicht). NPCs ohne Nachnamen: unveraendert.
local function composeName(vorname, nachname)
    if not Compat.isForever then return vorname end
    local a, b = Compat.Str(vorname), Compat.Str(nachname)
    if a and b then return a .. " " .. b end
    return vorname
end

local function updateText(sk)
    local u = SPEC[sk.id].unit
    -- Name und Stufe koennen secret sein: unveraendert an SetText (nil leert den Text); verglichen wird nur die lesbare
    -- Zahl aus Compat.Num, nachdem Compat.IsSecret ausgeschlossen ist. Gesetzt wird nur unser eigener FontString (sk.name),
    -- Blizzards Namens-Text bleibt unberuehrt (Alpha 0).
    local ok, name, surname = pcall(UnitName, u)
    if ok then pcall(sk.name.SetText, sk.name, composeName(name, surname)) else sk.name:SetText("") end
    if sk.levelText then
        local okL, lvl = pcall(UnitLevel, u)
        if not okL then
            sk.levelText:SetText("")
        elseif Compat.IsSecret(lvl) then
            pcall(sk.levelText.SetText, sk.levelText, lvl)
        else
            local n = Compat.Num(lvl)
            if not n then
                sk.levelText:SetText("")
            elseif n < 1 then
                sk.levelText:SetText("??")
            else
                sk.levelText:SetText(tostring(n))
            end
        end
        if Skin.Deco then Skin.Deco.UpdateLevel(sk) end -- Ziel: Stein in Schwierigkeitsfarbe, Totenkopf bei ??
    end
end

local function testValue(offset)
    local seq = Skin.TEST_SEQ
    return seq[((testIndex + offset) % #seq) + 1]
end

--- Werte einspeisen. how = "snap" (sofort, Zielwechsel), "health", "maxhealth", "power", "maxpower"
local function feed(sk, how)
    if not sk.applied then return end
    if Skin.Text then Skin.Text.Update(sk, how) end -- Dauer-Zahlen (Text.lua)
    local u = SPEC[sk.id].unit
    if testActive then
        local hv, pv = testValue(sk.id == "target" and 3 or (sk.id == "tot" and 5 or 0)), testValue(2)
        if how == "snap" then
            for _, x in ipairs({ { sk.health, hv }, { sk.power, pv } }) do
                Liquid.Snap(x[1])
                Liquid.SnapMax(x[1], Skin.TEST_MAX)
                Liquid.SnapValue(x[1], x[2])
            end
        else
            Liquid.SetMax(sk.health, Skin.TEST_MAX)
            Liquid.SetMax(sk.power, Skin.TEST_MAX)
            Liquid.SetValue(sk.health, hv)
            Liquid.SetValue(sk.power, pv)
        end
        return
    end
    -- Secret-Regel: mx/v/pmx/pv koennen secret sein. Nur der pcall-Erfolg (lesbar) entscheidet; die Werte gehen
    -- unveraendert an Liquid (nie in Bedingungen, and/or, Vergleichen, Schluesseln, tostring/format).
    if how == "snap" then
        Liquid.Snap(sk.health)
        local okM, mx = pcall(UnitHealthMax, u)
        if okM then Liquid.SnapMax(sk.health, mx) end
        local okV, v = pcall(UnitHealth, u)
        if okV then Liquid.SnapValue(sk.health, v) end
        Liquid.Snap(sk.power)
        local okPM, pmx = pcall(UnitPowerMax, u)
        if okPM then Liquid.SnapMax(sk.power, pmx) end
        local okP, pv = pcall(UnitPower, u)
        if okP then Liquid.SnapValue(sk.power, pv) end
    elseif how == "maxhealth" then
        local okM, mx = pcall(UnitHealthMax, u)
        if okM then Liquid.SetMax(sk.health, mx) end
        local okV, v = pcall(UnitHealth, u)
        if okV then Liquid.SetValue(sk.health, v) end
    elseif how == "health" then
        local okV, v = pcall(UnitHealth, u)
        if okV then Liquid.SetValue(sk.health, v) end
    elseif how == "maxpower" then
        local okM, mx = pcall(UnitPowerMax, u)
        if okM then Liquid.SetMax(sk.power, mx) end
        local okP, pv = pcall(UnitPower, u)
        if okP then Liquid.SetValue(sk.power, pv) end
    elseif how == "power" then
        local okP, pv = pcall(UnitPower, u)
        if okP then Liquid.SetValue(sk.power, pv) end
    end
end

-- Mini-Vorschau (Preview.lua): derselbe Aufbau und dieselbe Lage auf einem Schein-Rahmen (sk.preview, eigene Ersatz-Regionen
-- statt Blizzards Balken/Portrait; nie in skins, nie ausgeblendete Blizzard-Teile) und die Ressourcenfarbe des Spielers
Skin.PreviewBuild = function(sk, root) return build(sk, root) end
Skin.PreviewLayout = function(sk) return layout(sk) end
Skin.PowerTint = function(sk) return powerTint(sk) end

--- Schluessel der aktuellen Ressource (Token oder Typnummer als Text); nil, wenn nicht lesbar (secret) - dann kein Neufaerben
local function powerKey(sk)
    local ok, ptype, token = pcall(UnitPowerType, SPEC[sk.id].unit)
    if not ok or Compat.IsSecret(ptype) or Compat.IsSecret(token) then return nil end
    if type(token) == "string" then return token end
    local n = Compat.Num(ptype)
    return n and ("#" .. n) or nil
end

local function recolor(sk)
    if not sk.applied then return end
    Liquid.SetTint(sk.health, healthTint(sk))
    Liquid.SetTint(sk.power, powerTint(sk))
    sk.powerKey = powerKey(sk)
end

--- Einheit neu: Farben, Texte, Werte einrasten
local function refreshUnit(sk)
    if not sk.applied then return end
    recolor(sk)
    updateText(sk)
    feed(sk, "snap")
    hideBlizzard(sk) -- Blizzard kann Teile beim Zielwechsel neu gesetzt haben
    if Skin.Deco then Skin.Deco.Refresh(sk) end
    if Skin.Portrait then Skin.Portrait.Refresh(sk) end -- Portrait-Stile (Portrait.lua): Textur/Pegel zur neuen Einheit
end

-- Anwenden / Zurueckstellen -------------------------------------------------------------------------------------------------
local function remove(sk)
    if not sk then return end
    if sk.applied then
        if Skin.Deco then pcall(Skin.Deco.Remove, sk) end
        if Skin.Text then pcall(Skin.Text.Detach, sk) end -- Blizzards Statustext wieder Alpha 1
        if Skin.Portrait then pcall(Skin.Portrait.Detach, sk) end -- vor restoreBlizzard: gibt Blizzards Portrait frei
        restoreBlizzard(sk)
        Liquid.SetHealGhost(sk.health, nil)
        for k in pairs(Liquid.SEGMENTS) do Liquid.SetSegment(sk.health, k, nil) end
        for k in pairs(Liquid.SEG_GLOWS) do Liquid.SetSegGlow(sk.health, k, false) end
        Liquid.SetFx(sk.health, nil, false, false)
        Liquid.SetFx(sk.power, nil, false, false)
        Liquid.Hide(sk.health)
        Liquid.Hide(sk.power)
        sk.holder:Hide()
        sk.applied = false
    end
end

-- Fluessigkeit blendet mit dem Rahmen aus: nach jedem SetAlpha/SetAlphaFromBoolean eines Rahmens (Ausblenden-Modul/Fader, Blizzard) zieht die
-- Roehre ihren Alpha-Ausgleich sofort nach (Liquid.SyncFade; sonst erst beim naechsten Bild). Nachher-Hook wie der des Faders,
-- keine ersetzte Methode, kein Eingriff in Blizzards Alpha.
local fadeHooked = {}
local function hookFade(root)
    if fadeHooked[root] or type(hooksecurefunc) ~= "function" then return end
    if pcall(hooksecurefunc, root, "SetAlpha", function() Liquid.SyncFadeAll() end) then fadeHooked[root] = true end
    -- Retail 12.x: SetAlphaFromBoolean laeuft am SetAlpha-Hook vorbei (wie in Fader.lua)
    if type(root.SetAlphaFromBoolean) == "function" then
        pcall(hooksecurefunc, root, "SetAlphaFromBoolean", function() Liquid.SyncFadeAll() end)
    end
end

local function apply(id)
    local root = rootOf(id)
    local sk = skins[id]
    if not wanted(id) or not root then
        remove(sk)
        return
    end
    if not sk then
        sk = { id = id, hidden = {}, hiddenCount = 0, missing = {} }
        skins[id] = sk
    end
    if sk.root ~= root then
        if sk.applied then remove(sk) end
        discover(sk, root)
        if sk.holder then
            sk.holder:SetParent(root)
        else
            local ok, err = pcall(build, sk, root)
            if not ok then -- halb gebaut: verwerfen, das naechste apply baut neu
                if sk.holder then pcall(sk.holder.Hide, sk.holder) end
                sk.holder, sk.health, sk.power, sk.root = nil, nil, nil, nil
                error(err, 0)
            end
        end
    end
    if not sk.hb then
        remove(sk) -- ohne Lebensleiste kein Skin (unbekannter Aufbau)
        return
    end
    local lq = Schema.Resolve(cfg, id).liquid -- Fluessigkeit je Rahmen (Eigenwert oder "fuer alle")
    Liquid.SetStyle(sk.health, lq.style) -- vor dem Layout (Reichweite der Fluessigkeit, Glut-Anker)
    Liquid.SetStyle(sk.power, lq.style)
    layout(sk)
    if Skin.Portrait then
        local okP, errP = pcall(Skin.Portrait.Attach, sk, id) -- Portrait-Stil aus dem Profil (Portrait.lua)
        if not okP then recordError(errP) end
    end
    -- ToT: keine Schadensspur - er wird abgefragt (TOT_POLL), eine Spur je Abfrage waere eine Timer-Flut
    Liquid.SetOptions(sk.health, lq.smooth, lq.trail and id ~= "tot")
    Liquid.SetOptions(sk.power, lq.smooth, false)
    -- Effekte (LiquidFx): nicht beim ToT (abgefragt); Ressourcen-Strom und Schlieren nur beim Spieler
    local fxOn = lq.fx and id ~= "tot"
    Liquid.SetFx(sk.health, id .. "-health", fxOn, lq.debuffs and id == "player" or false)
    Liquid.SetFx(sk.power, id .. "-power", fxOn and id == "player", false)
    -- Regeneration deutlich zeigen (LiquidFizz): nur die eigene Mana-Roehre
    if ns.LiquidFizz then ns.LiquidFizz.SetPulse(sk.power, id == "player" and lq.regenPulse == true) end
    hookFade(root)
    sk.holder:Show()
    Liquid.Show(sk.health)
    if sk.mb then Liquid.Show(sk.power) else Liquid.Hide(sk.power) end
    sk.applied = true
    if Skin.Text then Skin.Text.Attach(sk, id) end -- Dauer-Zahlen (Text.lua)
    refreshUnit(sk)
    healGhost(sk)
end

local function reapplyAlpha()
    reapplyQueued = false
    for _, sk in pairs(skins) do
        if sk.applied then
            local ok, err = pcall(hideBlizzard, sk)
            if not ok then recordError(err) end
        end
    end
end

--- Blizzard setzt Teile in seinen Handlern neu (Kampf-Blitz, Fahrzeug, Ressourcenart): danach erneut Alpha 0
local function queueReapply()
    if reapplyQueued or not engaged() then return end
    reapplyQueued = true
    C_Timer.After(0, reapplyAlpha)
end

-- Globale Blizzard-Funktionen, nach denen die Zier-Texturen neu gesetzt sein koennen (Nachher-Hooks, nur wenn vorhanden)
Skin.REAPPLY_HOOKS = { "UnitFrameManaBar_UpdateType", "PlayerFrame_UpdateStatus", "PlayerFrame_ToPlayerArt",
    "PlayerFrame_ToVehicleArt", "TargetFrame_CheckClassification", "TargetFrame_Update" }
local hookStatus = {}

local function installHooks()
    if hooksInstalled then return end
    hooksInstalled = true
    for _, name in ipairs(Skin.REAPPLY_HOOKS) do
        if type(_G[name]) == "function" then
            local ok = pcall(hooksecurefunc, name, function() queueReapply() end)
            hookStatus[name] = ok and "ok" or "failed"
        else
            hookStatus[name] = "missing"
        end
    end
end

local function stopTestTicker()
    if testTicker then
        testTicker:Cancel()
        testTicker = nil
    end
end

local function stopTot()
    if totTicker then
        totTicker:Cancel()
        totTicker = nil
    end
end

local function pollTot()
    local sk = skins.tot
    if not (sk and sk.applied) then
        stopTot()
        return
    end
    if testActive or not unitExists("targettarget") then return end
    feed(sk, "maxhealth") -- Maximum mit nachziehen
    feed(sk, "maxpower")
    -- Ressourcen-Typwechsel des Ziels des Ziels (kein UNIT_DISPLAYPOWER fuer targettarget): Toenung neu
    local key = powerKey(sk)
    if key and key ~= sk.powerKey then
        sk.powerKey = key
        Liquid.SetTint(sk.power, powerTint(sk))
    end
end

local function ensureTot()
    local sk = skins.tot
    if sk and sk.applied and not totTicker then totTicker = C_Timer.NewTicker(Skin.TOT_POLL, pollTot) end
    if not (sk and sk.applied) then stopTot() end
end

--- Einstellungen neu lesen und alle Rahmen anwenden bzw. zurueckstellen (sofort, auch im Kampf: nur Alpha/eigene Frames)
function Skin.Refresh()
    cfg = Skin.GetConfig()
    blocker = Skin.Conflict()
    if engaged() then installHooks() end
    if Physics then
        Physics.Configure(cfg.liquid.slosh, cfg.liquid.sloshStrength, cfg.liquid.sloshDamping)
        if engaged() and cfg.liquid.slosh then Physics.InstallJumpHook() end
    end
    for _, id in ipairs(Skin.FRAMES) do
        local ok, err = pcall(apply, id)
        if not ok then recordError(err) end
    end
    ensureTot()
    setListening(engaged())
    if testActive and not engaged() then -- Fremd-Addon oder Modul aus: Testmodus endet
        testActive = false
        stopTestTicker()
    end
    if Skin.XP then -- Erfahrungsleiste (XP.lua) folgt dem Skin
        local ok, err = pcall(Skin.XP.Refresh, engaged())
        if not ok then recordError(err) end
    end
end

-- Testmodus -----------------------------------------------------------------------------------------------------------------
local function testSlosh()
    if not Physics then return end
    local seq = Skin.TEST_SLOSH
    Physics.Simulate(seq[(testIndex % #seq) + 1])
end

--- Testmodus: Heilung/Treffer nach dem Sprung der (lesbaren) Testwerte des Spielers, Schlieren reihum
local function testFx()
    local Fx = ns.LiquidFx
    if not Fx then return end
    local hv, prev = testValue(0), testValue(-1)
    if hv > prev then
        Fx.Heal(hv - prev >= Skin.TEST_FX_CRIT)
    elseif hv < prev then
        Fx.Hit(prev - hv >= Skin.TEST_FX_CRIT)
    end
    if Fx.TestDebuffsActive() then return end -- /vials test <bannart> laeuft: nicht ueberschreiben
    local seq = Skin.TEST_DEBUFFS
    Fx.SetTestDebuffs(seq[(testIndex % #seq) + 1])
end

local function testStep()
    testIndex = testIndex + 1
    testSlosh()
    pcall(testFx)
    for _, sk in pairs(skins) do
        if sk.applied then
            local ok, err = pcall(feed, sk, "health")
            if not ok then recordError(err) end
        end
    end
end

--- Testmodus an/aus. Liefert true (an), false (aus) oder nil, Grund ("blocked")
function Skin.ToggleTest()
    if testActive then
        testActive = false
        stopTestTicker()
        Skin.Refresh()
        for _, sk in pairs(skins) do if sk.applied then pcall(feed, sk, "snap") end end
        if ns.LiquidFx then -- Test-Schlieren weg, echter Stand
            ns.LiquidFx.SetTestDebuffs({})
            pcall(ns.LiquidFx.ScanDebuffs)
        end
        return false
    end
    cfg = Skin.GetConfig()
    blocker = Skin.Conflict()
    if blocker then return nil, "blocked" end
    testActive = true
    testIndex = 0
    Skin.Refresh()
    stopTestTicker()
    testTicker = C_Timer.NewTicker(Skin.TEST_STEP, testStep)
    testSlosh()
    return true
end

function Skin.IsTesting() return testActive end
function Skin.ErrorCount() return errorCount end
function Skin.Blocker() return blocker end
function Skin.IsEngaged() return engaged() end -- Skin wirkt (Modul aktiv, kein Fremd-Addon, Profil an oder Test laeuft); Reiter "Rahmen"
function Skin.IsApplied(id) return skins[id] ~= nil and skins[id].applied == true end
--- Zustand eines Rahmens (Debug/Tests; nur lesen)
function Skin.Get(id) return skins[id] end

-- Ereignisse -----------------------------------------------------------------------------------------------------------------
local UNIT_ID = { player = "player", target = "target" }

local function onUnitEvent(event, unit)
    if not engaged() or type(unit) ~= "string" or Compat.IsSecret(unit) then return end
    local id = UNIT_ID[unit]
    local sk = id and skins[id]
    if not (sk and sk.applied) then return end
    if testActive and event ~= "UNIT_DISPLAYPOWER" and event ~= "UNIT_NAME_UPDATE" and event ~= "UNIT_LEVEL"
        and event ~= "UNIT_FACTION" then return end
    if event == "UNIT_HEALTH" then
        feed(sk, "health")
    elseif event == "UNIT_MAXHEALTH" then
        feed(sk, "maxhealth")
    elseif event == "UNIT_POWER_UPDATE" then
        feed(sk, "power")
    elseif event == "UNIT_MAXPOWER" then
        feed(sk, "maxpower")
    elseif event == "UNIT_DISPLAYPOWER" then
        recolor(sk)
        feed(sk, "snap")
        queueReapply()
    elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
        updateText(sk)
    elseif event == "UNIT_FACTION" then
        recolor(sk)
    end
end

local function safeUnitEvent(event, unit)
    local ok, err = pcall(onUnitEvent, event, unit)
    if not ok then recordError(err) end
end

-- Einheiten-Ereignisse nur, solange der Skin wirkt, und mit Einheitenfilter (je Einheit ein eigener Frame: der Client
-- filtert, kein Raid-/Plaketten-UNIT_HEALTH laeuft durch Lucid). Muster wie Style.lua updateListeners.
local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION" }
local EXTRA_EVENTS = { player = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }, target = { "UNIT_TARGET" } }
local onUnitTarget, onVehicle
local evFrames = {}
local function evFrame(unit)
    if evFrames[unit] then return evFrames[unit] end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event, u)
        if event == "UNIT_TARGET" then
            onUnitTarget(u)
        elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
            onVehicle(u)
        else
            safeUnitEvent(event, u)
        end
    end)
    evFrames[unit] = f
    return f
end
local listening = false
local function listenUnit(f, ev, unit)
    if pcall(f.RegisterUnitEvent, f, ev, unit) then return end
    pcall(f.RegisterEvent, f, ev) -- aelterer Client: ungefiltert (die Handler pruefen die Einheit)
end
setListening = function(on)
    on = on and true or false
    if on == listening then return end
    listening = on
    for _, unit in ipairs({ "player", "target" }) do
        local f = evFrame(unit)
        local list = {}
        for _, ev in ipairs(UNIT_EVENTS) do list[#list + 1] = ev end
        for _, ev in ipairs(EXTRA_EVENTS[unit]) do list[#list + 1] = ev end
        for _, ev in ipairs(list) do
            if on then listenUnit(f, ev, unit) else pcall(f.UnregisterEvent, f, ev) end
        end
    end
end
function Skin.IsListening() return listening end

local function onTargetChanged()
    if not engaged() then return end
    for _, id in ipairs({ "target", "tot" }) do
        local sk = skins[id]
        if sk and sk.applied then
            local ok, err = pcall(refreshUnit, sk)
            if not ok then recordError(err) end
        end
    end
end
Compat.TryOn("PLAYER_TARGET_CHANGED", onTargetChanged)
onUnitTarget = function(unit)
    if unit ~= "target" or not engaged() then return end
    local sk = skins.tot
    if sk and sk.applied then
        local ok, err = pcall(refreshUnit, sk)
        if not ok then recordError(err) end
    end
end

-- Fahrzeug: Spielerrahmen zurueck an Blizzard bzw. wieder skinnen
onVehicle = function(unit)
    if unit == "player" and active then C_Timer.After(0, function() pcall(apply, "player") end) end
end
for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING" }) do
    Compat.TryOn(ev, function() queueReapply() end)
end
Compat.TryOn("PLAYER_ENTERING_WORLD", function()
    if active then Skin.Refresh() end
end)
Compat.TryOn("PLAYER_LEVEL_UP", function()
    local sk = skins.player
    if sk and sk.applied then C_Timer.After(0, function() pcall(updateText, sk) end) end
end)
-- spaet geladene Fremd-Addons
ns.On("ADDON_LOADED", function(_, name)
    if not active then return end
    for _, n in ipairs(Skin.CONFLICT_ADDONS) do
        if n == name then Skin.Refresh() return end
    end
end)
-- Bearbeitungsmodus: Rahmengroesse/-art kann sich geaendert haben => neu legen (eigener Owner, Compat gehoert dem Fader)
if EventRegistry and EventRegistry.RegisterCallback then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", function()
        if active then Skin.Refresh() end
    end, Skin)
end

ns.RegisterModule("unitframes", {
    OnEnable = function()
        active = true
        Skin.Refresh()
    end,
    OnDisable = function()
        active = false
        testActive = false
        stopTestTicker()
        Skin.Refresh()
    end,
})

Store.RegisterCallback(function()
    if active then Skin.Refresh() end
    configChanged(nil, nil) -- Profilwechsel/-neuinhalt: alle Bereiche aller Rahmen
end)

-- Slash /vials on|off|test|debug --------------------------------------------------------------------------------------
local function yn(b) return b and L.NP_YES or L.NP_NO end

local function setEnabled(on)
    if not Skin.Set("enabled", on) then
        ns.Print(L.FRAMES_VALUE_INVALID)
        return
    end
    ns.Print(on and L.FRAMES_ENABLED or L.FRAMES_DISABLED)
    if on and blocker then ns.Print(L.FRAMES_BLOCKED, blocker) end
end

function Skin.Debug()
    local c = cfg or Skin.GetConfig()
    ns.Print("frames.skin enabled=%s test=%s engaged=%s blocker=%s lockdown=%s vehicle=%s glide=%s",
        yn(c.enabled), yn(testActive), yn(engaged()), tostring(blocker or "-"), yn(InCombatLockdown() == true),
        yn(inVehicle()), yn(Liquid.CanGlide()))
    ns.Print("frames.config player=%s target=%s tot=%s smooth=%s trail=%s style=%s", yn(c.frames.player),
        yn(c.frames.target), yn(c.frames.tot), yn(c.liquid.smooth), yn(c.liquid.trail), c.liquid.style)
    for _, id in ipairs(Skin.FRAMES) do -- Eigenwerte je Rahmen (Schema 2)
        local own = type(c.per) == "table" and type(c.per[id]) == "table" and c.per[id].liquid
        if type(own) == "table" then
            ns.Print("frames.%s.liquid style=%s smooth=%s trail=%s fx=%s debuffs=%s", id, tostring(own.style), yn(own.smooth),
                yn(own.trail), yn(own.fx), yn(own.debuffs))
        end
    end
    local ink = ns.LiquidFx and ns.LiquidFx.DebuffState() or { n = 0, secret = 0 }
    ns.Print("frames.fx on=%s debuffs=%s auras=%s ink=%d secret=%d", yn(c.liquid.fx), yn(c.liquid.debuffs),
        yn(ns.LiquidFx and ns.LiquidFx.IsListeningAuras()), ink.n or 0, ink.secret or 0)
    if ns.LiquidFx then
        local ids, src = ns.LiquidFx.DispelIds()
        ns.Print("frames.dispel quelle=%s magie=%s fluch=%s krankheit=%s gift=%s", Skin.ID_SOURCE[src] or tostring(src),
            tostring(ids.Magic), tostring(ids.Curse), tostring(ids.Disease), tostring(ids.Poison))
        if type(ns.LiquidFx.DebugLines) == "function" then
            for _, l in ipairs(ns.LiquidFx.DebugLines()) do ns.Print(l) end
        end
    end
    local fs = ns.LiquidFizz and ns.LiquidFizz.State()
    if fs then
        local sk = skins.player
        local a, nb, nsp, on = ns.LiquidFizz.TubeInfo(sk and sk.power)
        local tnow = GetTime and GetTime() or 0
        local lock = (fs.mana and fs.castAt) and math.max(0, ns.LiquidFizz.CFG.castLock - (tnow - fs.castAt)) or 0
        ns.Print("frames.fizz on=%s listening=%s mode=%s cur=%s max=%s regen=%s mana=%s token=%s grund=%s sperre5s=%.1f "
            .. "tick=%s alpha=%.2f kurve=%s setalpha=%s bubbles=%d sparks=%d test=%s impuls=%s/%d", yn(on),
            yn(ns.LiquidFizz.IsListening()),
            tostring(fs.mode), fs.cur and tostring(fs.cur) or "-", fs.max and tostring(fs.max) or "-", yn(fs.regen),
            yn(fs.mana), tostring(fs.token or "-"), tostring(fs.reason), lock,
            fs.tickAt and string.format("%.1fs", tnow - fs.tickAt) or "-", a or 0, fs.innerSecret and "secret" or "1",
            fs.alphaOk == nil and "-" or yn(fs.alphaOk), nb or 0, nsp or 0, yn((fs.testUntil or 0) > tnow),
            yn(sk and sk.power and sk.power.fx and sk.power.fx.fizz and sk.power.fx.fizz.pulseOn), fs.pulses or 0)
    end
    local pi = Physics and Physics.Info() or {}
    ns.Print("frames.slosh on=%s strength=%d damping=%d awake=%s tilt=%.2f wave=%.2f speed=%s turn=%s jumpHook=%s steps=%d",
        yn(c.liquid.slosh), math.floor(c.liquid.sloshStrength * 100 + 0.5), math.floor(c.liquid.sloshDamping * 100 + 0.5),
        yn(pi.awake), pi.tilt or 0, pi.wave or 0, tostring(pi.speedSrc or "-"), tostring(pi.facing or "-"),
        tostring(pi.jumpHook or "-"), pi.steps or 0)
    for _, id in ipairs(Skin.FRAMES) do
        local sk = skins[id]
        local root = rootOf(id)
        if not sk then
            ns.Print("frames.%s root=%s applied=%s", id, yn(root ~= nil), L.NP_NO)
        else
            ns.Print("frames.%s root=%s applied=%s hidden=%d health=%s power=%s portrait=%s name=%s level=%s levels=%s/%s",
                id, yn(root ~= nil), yn(sk.applied), sk.hiddenCount or 0, yn(sk.hb ~= nil), yn(sk.mb ~= nil),
                yn(sk.portrait ~= nil), yn(sk.nameFs ~= nil), yn(sk.levelFs ~= nil), tostring(level(sk.hb) or "?"),
                tostring(sk.health and sk.health.root and level(sk.health.root) or "?"))
            ns.Print("frames.%s.missing=%s", id, #sk.missing > 0 and table.concat(sk.missing, ",") or L.NP_NONE)
        end
    end
    local hooks = {}
    for _, name in ipairs(Skin.REAPPLY_HOOKS) do hooks[#hooks + 1] = name .. "=" .. tostring(hookStatus[name] or "-") end
    ns.Print("frames.hooks %s", table.concat(hooks, " "))
    if Skin.Deco then Skin.Deco.Debug() end
    if Skin.Portrait then Skin.Portrait.Debug() end
    if Skin.XP then Skin.XP.Debug() end
    ns.Print("frames.driver active=%s errors=%d", yn(Style and Style.DriverActive and Style.DriverActive()), errorCount)
    for i, e in ipairs(errors) do ns.Print("frames.error.%d %s", i, (e:gsub("|", "||"))) end
end

UnitFrames.sub.on = function() setEnabled(true) end
UnitFrames.sub.an = UnitFrames.sub.on
UnitFrames.sub.off = function() setEnabled(false) end
UnitFrames.sub.aus = UnitFrames.sub.off
--- Einzel-Effekt bzw. Bannart testen (Rahmen muessen sichtbar sein: /vials on oder test)
local function testEffect(what, word)
    local Fx = ns.LiquidFx
    if what == "off" then
        if Fx then Fx.TestDebuffs({}) end
        if Skin.XP then Skin.XP.StopTest() end
        if Skin.Text then Skin.Text.StopTest() end
        if testActive then
            Skin.ToggleTest()
            ns.Print(L.FRAMES_TEST_OFF)
        end
        return
    end
    if not engaged() or not Fx then
        ns.Print(L.FRAMES_TEST_NEED_ON)
        return
    end
    if type(what) == "table" then
        Fx.TestDebuffs(what)
        ns.Print(L.FRAMES_TEST_FX, word, Fx.INK.testSecs)
        return
    end
    if what == "heal" then
        Fx.TestHeal()
    elseif what == "hit" then
        Fx.TestHit()
    elseif what == "mana" then
        if ns.LiquidFizz then ns.LiquidFizz.Test() end
    elseif what == "shield" then
        Skin.TestShield()
    elseif what == "slosh" then
        for _, sk in pairs(skins) do
            if sk.applied then
                for _, lb in ipairs({ sk.health, sk.power }) do pcall(Liquid.BreakWave, lb) end
            end
        end
        if Physics and Physics.Jolt then Physics.Jolt("land", 1, -Physics.WAVE.land * 24) end
    end
    ns.Print(L.FRAMES_TEST_FX1, word)
end

-- /vials test schild: Heil-Vorschau, Schild, Heil-Absorption und Ueberschild-Gluehen an der Spieler-Roehre fuer
-- TEST_SHIELD_SECS s an eigenen, unsichtbaren Ankern (Anteile der Roehrenlaenge), danach wieder Blizzards echter Stand
Skin.TEST_SHIELD_SECS = 8
-- wie im Spiel: Leben bei level, Heil-Absorption am Lebensende, Vorschau und Schild dahinter (erste Fassung lag ueber vollem Leben)
Skin.TEST_SHIELD = { level = 0.45, healAbsorb = { 0.36, 0.45 }, ghost = { 0.45, 0.62 }, shield = { 0.62, 0.86 } }
local shieldTestUntil = 0
function Skin.TestShield()
    local sk = skins.player
    if not (sk and sk.applied) then return false end
    local lb = sk.health
    Liquid.AddHealGhost(lb)
    for key in pairs(Liquid.SEGMENTS) do Liquid.AddSegment(lb, key) end
    for key in pairs(Liquid.SEG_GLOWS) do Liquid.AddSegGlow(lb, key) end
    lb.testAnchors = lb.testAnchors or {}
    local w = lb.w or 100
    local function anchor(name, a, b)
        local t = lb.testAnchors[name] or lb.root:CreateTexture()
        lb.testAnchors[name] = t
        t:SetAlpha(0)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", lb.root, "TOPLEFT", a * w, 0)
        t:SetPoint("BOTTOMLEFT", lb.root, "BOTTOMLEFT", a * w, 0)
        t:SetWidth(math.max(1, (b - a) * w))
        return t
    end
    local T = Skin.TEST_SHIELD
    Liquid.SnapMax(lb, 1)
    Liquid.SnapValue(lb, T.level)
    Liquid.SetHealGhost(lb, anchor("ghost", T.ghost[1], T.ghost[2]))
    Liquid.SetSegment(lb, "shield", anchor("shield", T.shield[1], T.shield[2]))
    Liquid.SetSegment(lb, "healAbsorb", anchor("healAbsorb", T.healAbsorb[1], T.healAbsorb[2]))
    Liquid.SetSegGlow(lb, "over", true)
    shieldTestUntil = (GetTime and GetTime() or 0) + Skin.TEST_SHIELD_SECS
    if C_Timer and C_Timer.After then
        C_Timer.After(Skin.TEST_SHIELD_SECS, function()
            if (GetTime and GetTime() or 0) + 0.01 < shieldTestUntil then return end
            for key in pairs(Liquid.SEGMENTS) do Liquid.SetSegment(lb, key, nil) end
            Liquid.SetSegGlow(lb, "over", false)
            Liquid.SetHealGhost(lb, nil)
            local cur = skins.player
            if cur and cur.applied then pcall(feed, cur, "snap") end
            syncHealGhost(cur)
        end)
    end
    return true
end

-- weitere Testwoerter der Module (/vials test <wort> [rest]); eingebaute Woerter gehen vor und sind nicht belegbar
local testWords = {}
Skin.XP_TEST_WORDS = { xp = true, xprest = true, levelup = true, stufe = true } -- XP.lua (falls noch nicht geladen)
function Skin.RegisterTest(word, fn)
    assert(type(word) == "string" and word == word:lower() and word:match("^[^%s%c|]+$") and type(fn) == "function",
        "LucidVials: Testwort braucht Kleinbuchstaben ohne Leerzeichen und eine Funktion: " .. tostring(word))
    local xpWords = (Skin.XP and Skin.XP.TEST_WORDS) or Skin.XP_TEST_WORDS
    assert(not Skin.TEST_ARGS[word] and not xpWords[word] and not Skin.XP_TEST_WORDS[word] and word ~= "ziel"
        and word ~= "target" and not testWords[word],
        "LucidVials: Testwort schon belegt: " .. word)
    testWords[word] = fn
end

UnitFrames.sub.test = function(arg)
    local word, rest = (arg or ""):lower():match("^%s*(%S*)%s*(.-)$")
    word = word or ""
    if (word == "ziel" or word == "target") and Skin.Deco then -- /vials test ziel <art> (Deco.lua)
        Skin.Deco.TestCommand(rest)
        return
    end
    if Skin.XP and Skin.XP.TEST_WORDS[word] then -- /vials test xp|xprest|levelup (XP.lua)
        Skin.XP.TestCommand(word)
        return
    end
    local custom = testWords[word]
    if custom then
        xpcall(function() custom(rest) end, geterrorhandler())
        return
    end
    if word ~= "" then
        local what = Skin.TEST_ARGS[word]
        if not what then
            -- Wortliste samt der angemeldeten Testwoerter (Skin.RegisterTest: portrait, zahlen/numbers, ...)
            local extra = {}
            for w in pairs(testWords) do extra[#extra + 1] = w end
            table.sort(extra)
            ns.Print(L.FRAMES_TEST_USAGE, table.concat(extra, "||"))
            return
        end
        testEffect(what, word)
        return
    end
    local res = Skin.ToggleTest()
    if res == nil then
        ns.Print(L.FRAMES_BLOCKED, blocker or "?")
    else
        ns.Print(res and L.FRAMES_TEST_ON or L.FRAMES_TEST_OFF)
    end
end
-- Debug zusaetzlich im Kopierfenster (Regel: Diagnosen immer kopierbar); ns.Print nur waehrend des Aufrufs umgeleitet
UnitFrames.sub.debug = function()
    local P, lines = ns.Print, {}
    ns.Print = function(fmt, ...)
        local ok, s = pcall(string.format, tostring(fmt), ...)
        s = ok and s or tostring(fmt)
        -- Kopierfenster zeigt Rohtext: Chat-Escapes ("||" = "|", Farbcodes) wie im Chat dargestellt
        local box = ns.CopyBox
        lines[#lines + 1] = (box and box.Clean) and box.Clean(s) or s
        return P(fmt, ...)
    end
    local ok, err = pcall(Skin.Debug)
    ns.Print = P
    if not ok then geterrorhandler()(err) end
    local box = ns.CopyBox
    if #lines > 0 and box and box.Show then pcall(box.Show, "Lucid Vials debug", table.concat(lines, "\n")) end
end

local function pct(x) return math.floor(x * 100 + 0.5) end

--- /vials slosh on|off|<0-100>|damping <0-100>
local function percentArg(a)
    local n = a and a:match("^(%d+)%%?$") and tonumber(a:match("^(%d+)")) or nil
    if not n or n > 100 then return nil end
    return n / 100
end

UnitFrames.sub.slosh = function(arg)
    local a, b = (arg or ""):lower():match("^(%S*)%s*(%S*)$")
    local ok
    if a == "on" or a == "an" then
        ok = Skin.Set("liquid.slosh", true)
    elseif a == "off" or a == "aus" then
        ok = Skin.Set("liquid.slosh", false)
    elseif (a == "damping" or a == "daempfung" or a == "dämpfung") and percentArg(b) then
        ok = Skin.Set("liquid.sloshDamping", percentArg(b))
    elseif a ~= "" and b == "" and percentArg(a) then
        ok = Skin.Set("liquid.sloshStrength", percentArg(a))
    else
        ns.Print(L.FRAMES_SLOSH_USAGE)
        return
    end
    if not ok then
        ns.Print(L.FRAMES_VALUE_INVALID)
        return
    end
    local c = Skin.GetConfig().liquid
    ns.Print(c.slosh and L.FRAMES_SLOSH_ON or L.FRAMES_SLOSH_OFF, pct(c.sloshStrength), pct(c.sloshDamping))
end
UnitFrames.sub.schwappen = UnitFrames.sub.slosh

--- /vials style kante|kolben (auch edge|piston): Darstellung der Fluessigkeit
local STYLE_ARGS = { kante = "edge", edge = "edge", kolben = "piston", piston = "piston" }
UnitFrames.sub.style = function(arg)
    local s = STYLE_ARGS[(arg or ""):lower():match("^%s*(%S*)") or ""]
    if not s then
        ns.Print(L.FRAMES_STYLE_USAGE)
        return
    end
    if not Skin.Set("liquid.style", s) then
        ns.Print(L.FRAMES_VALUE_INVALID)
        return
    end
    ns.Print(L.FRAMES_STYLE_SET, s == "piston" and L.FRAMES_STYLE_PISTON or L.FRAMES_STYLE_EDGE)
end
UnitFrames.sub.darstellung = UnitFrames.sub.style

--- /vials auren [<14-36>]: Groesse der Buff-/Debuff-Symbole am Ziel; ohne Zahl der aktuelle Wert
UnitFrames.sub.auren = function(arg)
    local R = Skin.AURA_SIZE
    local a = (arg or ""):match("^%s*(%S*)") or ""
    if a == "" then
        ns.Print(L.FRAMES_AURA_SIZE, Skin.GetConfig().auraSize, R.min, R.max, R.default)
        return
    end
    local n = a:match("^%d+$") and tonumber(a) or nil
    if not n or n < R.min or n > R.max then
        ns.Print(L.FRAMES_AURA_INVALID, R.min, R.max)
        return
    end
    if not Skin.Set("auraSize", n) then
        ns.Print(L.FRAMES_VALUE_INVALID)
        return
    end
    ns.Print(L.FRAMES_AURA_SET, n)
end
UnitFrames.sub.auras = UnitFrames.sub.auren

ns.AddHelp("HELP_FRAMES")

--- /vials fx on|off (Effekte: Schaden, Heilung, Ressourcen-Strom) und /vials debuffs on|off (Schlieren)
local function fxSwitch(key)
    return function(arg)
        local a = (arg or ""):lower():match("^%s*(%S*)") or ""
        local v
        if a == "on" or a == "an" then v = true elseif a == "off" or a == "aus" then v = false end
        if v == nil then
            ns.Print(L.FRAMES_FX_USAGE)
            return
        end
        if not Skin.Set("liquid." .. key, v) then
            ns.Print(L.FRAMES_VALUE_INVALID)
            return
        end
        local c = Skin.GetConfig().liquid
        ns.Print(L.FRAMES_FX_SET, c.fx and L.NP_YES or L.NP_NO, c.debuffs and L.NP_YES or L.NP_NO)
    end
end
UnitFrames.sub.fx = fxSwitch("fx")
UnitFrames.sub.effekte = UnitFrames.sub.fx
UnitFrames.sub.debuffs = fxSwitch("debuffs")
UnitFrames.sub.schlieren = UnitFrames.sub.debuffs

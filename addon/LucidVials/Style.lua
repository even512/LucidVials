-- Gemeinsame Bausteine der Rahmen (aus Lucids Plaketten-Stil uebernommen, ohne die Plaketten selbst): Texturpfade der Roehre,
-- Stroemungs-Animation der Fluessigkeits-Lagen, Pixel-Einrasten, Haltung einer Einheit, Schrift, Questie-Bruecke fuer das
-- Quest-Symbol am Ziel-Portraet und der eigene Animations-Treiber (OnUpdate).
--
-- Treiber: ein eigener, unsichtbarer Frame mit OnUpdate. Fast-Stepper laufen jedes Bild (die Fluessigkeit, Liquid.StepAll),
-- normale Stepper im ~30-Hz-Takt. Ein Stepper liefert true, solange er laeuft; laeuft keiner mehr, ruht der Treiber (Hide),
-- bis WakeDriver ihn weckt. Fehler eines Steppers stoppen die anderen nicht (pcall, Zaehler fuer /vials debug).
local ADDON_NAME, ns = ...
local Compat = ns.Compat

local Style = {}
ns.Style = Style

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
Style.FILL_TEX = MEDIA .. "np-fill"
Style.FRAME_TEX = MEDIA .. "np-frame"
-- Lebensfluessigkeit (waagrecht nahtlos): farbig (feindlich) und entsaettigt (zum Toenen)
Style.FLOW_TEX = MEDIA .. "np-liquid"
Style.FLOW_TEX_MONO = MEDIA .. "np-liquid-mono"
-- Rahmen-Textur: Breite, Hoehe, Kappenbreite und Lage des durchsichtigen Schlitzes (Bandstaerke oben/unten, Einzug
-- links/rechts) in Textur-Pixeln
Style.FRAME_GEOMETRY = { w = 256, h = 32, cap = 32, top = 7, bottom = 6, left = 22, right = 22 }
Style.SKULL_TEX = MEDIA .. "np-skull"
Style.QUEST_TEX = MEDIA .. "np-quest"
Style.MASK_TEX = MEDIA .. "np-mask-capsule"
Style.INSET_TEX = MEDIA .. "np-inset"
Style.GLASS_TEX = MEDIA .. "np-glass"
Style.OBJ_TEX = { loot = MEDIA .. "np-obj-loot", slay = MEDIA .. "np-obj-slay", interact = MEDIA .. "np-obj-interact" }

-- Stroemung: zwei Lagen derselben Textur fliessen in dieselbe Richtung mit verschiedenen, langsamen Geschwindigkeiten
-- (speedA/speedB in Texturbreiten/s), B gespiegelt und versetzt; beide wogen leicht senkrecht (sway, Perioden swayA/swayB in s)
-- und pulsieren in der Helligkeit. A (normal gemischt) traegt das Bild, B (additiv) laesst Lichtfaeden aufscheinen.
Style.ANIM = {
    repeatA = 0.55, repeatB = 0.75, vA = 0.0625, vB = 0.5625, vSpan = 0.375,
    speedA = 0.010, speedB = 0.017, sway = 0.03, swayA = 6.3, swayB = 7.9,
    aAlpha = 0.92, aBright = 0.86, aPulse = 0.14, aPeriod = 3.1, bBase = 0.2, bAmp = 0.14, bPeriod = 4.7,
    edgeBase = 0.35, edgeAmp = 0.15, edgeRate = 3.1,
}
-- Roehre: Schlitz-Hintergrund (Verlauf oben/unten), Meniskus, innerer Schatten, Glasglanz
Style.TUBE = {
    backTop = { 0.13, 0.04, 0.03, 0.90 }, backBottom = { 0.06, 0.02, 0.015, 0.94 },
    meniscusHeight = 1,
    insetAlpha = 0.75, glassAlpha = 0.22, glassTop = 0.12, glassHeight = 0.16,
    underX = 4, underY = 2,
}

-- Hilfen ------------------------------------------------------------------------------------------
local function field(t, key)
    if type(t) ~= "table" or Compat.IsSecret(t) then return nil end
    local ok, v = pcall(function() return t[key] end)
    if ok and not Compat.IsSecret(v) then return v end
    return nil
end

local function readFlag(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or Compat.IsSecret(v) then return nil end
    return v
end

--- Textur auf ganze Bildschirmpixel einrasten (verhindert Flimmern beim Gleiten)
local function snapTex(t)
    if type(t) ~= "table" then return t end
    if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, true) end
    if t.SetTexelSnappingBias then pcall(t.SetTexelSnappingBias, t, 0) end
    return t
end
Style.SnapTexture = snapTex

--- Haltung der Einheit: "hostile" | "neutral" | "friendly" | "tapped" | nil (nicht lesbar)
function Style.Stance(unit)
    if type(unit) ~= "string" then return nil end
    if readFlag(UnitIsTapDenied, unit) then return "tapped" end
    local reaction = Compat.Num(readFlag(UnitReaction, unit, "player"))
    if reaction then
        if reaction >= 5 then return "friendly" end
        if reaction == 4 then return "neutral" end
        return "hostile"
    end
    local attack = readFlag(UnitCanAttack, "player", unit)
    if attack == nil then return nil end
    return attack and "hostile" or "friendly"
end

--- Zustand der beiden Fluessigkeits-Lagen zum Zeitpunkt t: TexCoords, Alpha, Helligkeit. Lage B ist gespiegelt (u0 > u1) und
--- um eine halbe Wiederholung versetzt. la/lb werden wiederverwendet (keine neuen Tabellen je Bild).
function Style.FlowState(t, phase, la, lb)
    local A = Style.ANIM
    la, lb = la or {}, lb or {}
    phase = phase or 0
    local p = phase * 6.28
    local ua = (phase + t * A.speedA) % 1
    local ub = (phase + 0.5 + t * A.speedB) % 1
    local va = A.vA + A.sway * math.sin(t * 2 * math.pi / A.swayA + p)
    local vb = A.vB + A.sway * math.sin(t * 2 * math.pi / A.swayB + p + 1.1)
    la.u0, la.u1, la.v0, la.v1, la.alpha = ua, ua + A.repeatA, va, va + A.vSpan, A.aAlpha
    la.bright = A.aBright + A.aPulse * math.sin(t * 2 * math.pi / A.aPeriod + p)
    lb.u0, lb.u1, lb.v0, lb.v1, lb.bright = ub + A.repeatB, ub, vb, vb + A.vSpan, 1
    lb.alpha = math.max(0, A.bBase + A.bAmp * math.sin(t * 2 * math.pi / A.bPeriod + p + 1.9))
    return la, lb
end

-- Schrift: Marcellus liegt im Addon (Fonts\, SIL OFL); Clients mit nicht-lateinischer Schrift nehmen die Client-Schrift.
Style.FONT_PATHS = { marcellus = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\Marcellus-Regular.ttf" }
local NON_LATIN = { koKR = true, zhCN = true, zhTW = true, ruRU = true }
local function clientFont() return _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end
Style.NON_LATIN = NON_LATIN -- Clients ohne lateinische Schrift (auch fuer Fonts.lua)
Style.ClientFont = clientFont

--- Schriftpfad zu einem Schriftnamen ("marcellus"); sonst bzw. bei nicht-lateinischer Client-Sprache die Client-Schrift
function Style.FontPath(face)
    local loc = type(GetLocale) == "function" and GetLocale() or "enUS"
    local path = Style.FONT_PATHS[face]
    if not path or NON_LATIN[loc] then return clientFont() end
    return path
end

-- Quest-Symbol (Ziel-Portraet): Questie-Bruecke ----------------------------------------------------
-- Ist Questie geladen und bereit, ist Questie.API.GetQuestObjectiveIconForUnit(guid) die Wahrheit fuer das Ziel-Symbol. Der
-- gelieferte Icon-Pfad wird ueber Questies eigene Tabellen (Questie.icons, Profil ICON_*) auf einen Typ abgebildet: loot ->
-- Beutel, slay -> gekreuzte Schwerter, interact/event/talk -> Panzerhandschuh. Kein Icon = kein Ziel (auch kein "!").
-- Ohne Questie: "!" ueber C_QuestLog.UnitIsRelatedToActiveQuest. Nur Lesen in Questies Tabellen, kein Schreiben in Questie.
Style.QUESTIE_KINDS = { -- Questie.icons-Schluessel bzw. Profilfeld -> Typ
    icons = { loot = "loot", slay = "slay", interact = "interact", event = "interact", talk = "interact" },
    profile = { ICON_LOOT = "loot", ICON_SLAY = "slay", ICON_INTERACT = "interact", ICON_EVENT = "interact",
        ICON_TALK = "interact" },
}

--- true, wenn die Einheit zu einer aktiven Quest gehoert (secret/Fehler = nein)
function Style.QuestRelated(unit)
    if type(unit) ~= "string" then return false end
    local q = C_QuestLog and field(C_QuestLog, "UnitIsRelatedToActiveQuest")
    return readFlag(q, unit) == true
end

local function normPath(p)
    if Compat.IsSecret(p) then return nil end
    if type(p) == "number" then return tostring(p) end
    if type(p) ~= "string" then return nil end
    return (p:lower():gsub("/", "\\"))
end

--- Questie, falls bereit: API-Funktion und Questie-Tabelle
local function questieReady()
    local Q = _G.Questie
    if type(Q) ~= "table" then return nil end
    local api = field(Q, "API")
    if type(api) ~= "table" or field(api, "isReady") ~= true then return nil end
    local fn = field(api, "GetQuestObjectiveIconForUnit")
    if type(fn) ~= "function" then return nil end
    return fn, Q
end

--- Pfad -> Typ (false = mehrdeutig) und Menge aller bekannten Questie-Symbolpfade, aus Questies Tabellen;
--- zwischengespeichert, neu nur wenn sich Questie-Tabelle, Icon-Tabelle oder die Profil-Symbole aendern
local mapCache = { sig = nil, kinds = nil, all = nil, builds = 0 }
function Style.QuestieMapBuilds() return mapCache.builds end
local function questieSig(Q)
    local profile = field(field(Q, "db"), "profile")
    local sig = tostring(Q) .. "|" .. tostring(field(Q, "icons")) .. "|" .. tostring(profile)
    if type(profile) == "table" then
        for key in pairs(Style.QUESTIE_KINDS.profile) do sig = sig .. "|" .. tostring(field(profile, key)) end
    end
    return sig
end
local function buildQuestieMaps(Q)
    local kinds, all = {}, {}
    local function add(path, kind)
        local k = normPath(path)
        if not k then return end
        all[k] = true
        if kind == nil then return end
        if kinds[k] == nil then kinds[k] = kind elseif kinds[k] ~= kind then kinds[k] = false end
    end
    local icons = field(Q, "icons")
    if type(icons) == "table" then
        for key, path in pairs(icons) do add(path, Style.QUESTIE_KINDS.icons[key] or "other") end
    end
    local profile = field(field(Q, "db"), "profile")
    if type(profile) == "table" then
        for key, kind in pairs(Style.QUESTIE_KINDS.profile) do add(field(profile, key), kind) end
    end
    return kinds, all
end
local function questieMaps(Q)
    local sig = questieSig(Q)
    if mapCache.sig ~= sig then
        mapCache.kinds, mapCache.all = buildQuestieMaps(Q)
        mapCache.sig, mapCache.builds = sig, mapCache.builds + 1
    end
    return mapCache.kinds, mapCache.all
end

--- Ziel-Typ der Einheit nach Questie: kind ("loot"|"slay"|"interact") oder nil, Status ("ok"|"none"|"unknown"|
--- "unavailable"), Pfad
function Style.QuestieKind(unit)
    local fn, Q = questieReady()
    if not fn then return nil, "unavailable" end
    local guid = readFlag(UnitGUID, unit)
    if type(guid) ~= "string" then return nil, "unavailable" end
    local ok, path = pcall(fn, guid)
    if not ok then return nil, "unavailable" end
    if path == nil then return nil, "none" end
    local kinds = questieMaps(Q)
    local kind = kinds[normPath(path) or ""]
    if kind == "loot" or kind == "slay" or kind == "interact" then return kind, "ok", path end
    return nil, "unknown", path
end

--- Quest-Symbol einer Einheit: want (Symbol zeigen), kind ("loot"|"slay"|"interact" oder nil fuer das "!"), Status (wie
--- QuestieKind). Questie ist die Wahrheit; ohne Questie "!" ueber C_QuestLog.
function Style.QuestSymbol(unit)
    local k, status = Style.QuestieKind(unit)
    if status == "unavailable" then return Style.QuestRelated(unit), nil, status end
    return k ~= nil, k, status
end

--- true, wenn path ein Symbolpfad aus Questies Tabellen ist (nur lesen; Ziel-Portraet, Deco.lua)
function Style.IsQuestieIcon(path)
    if Compat.IsSecret(path) or (type(path) ~= "string" and type(path) ~= "number") then return false end
    local Q = _G.Questie
    if type(Q) ~= "table" then return false end
    local _, all = questieMaps(Q)
    return all ~= nil and all[normPath(path) or ""] == true
end

-- Treiber ----------------------------------------------------------------------------------------
Style.DRIVER_DT = 0.033   -- s, Takt der normalen Stepper (~30 Hz)
Style.MAX_ERRORS = 5

local driver, driverOn = nil, false
local driverTime, driverAcc = 0, 0
local steppers, fastSteppers = {}, {}
local errors, errorCount = {}, 0

local function recordError(err)
    errorCount = errorCount + 1
    errors[#errors + 1] = string.sub(tostring(err), 1, 160)
    while #errors > Style.MAX_ERRORS do table.remove(errors, 1) end
end

local function driverStep(dt)
    driverTime = driverTime + dt
    driverAcc = driverAcc + dt
    local fastBusy = false
    for _, fn in ipairs(fastSteppers) do
        local ok, more = pcall(fn, driverTime)
        if not ok then recordError(more) elseif more then fastBusy = true end
    end
    if driverAcc < Style.DRIVER_DT then return end -- zwischen zwei Takten: erst der naechste Takt entscheidet ueber das Ruhen
    driverAcc = 0
    local busy = false
    for _, fn in ipairs(steppers) do
        local ok, more = pcall(fn, driverTime)
        if not ok then recordError(more) elseif more then busy = true end
    end
    if not busy and not fastBusy and driver then
        driverOn = false
        driver:Hide()
    end
end

function Style.DriverActive() return driverOn == true end
function Style.DriverErrors() return errors, errorCount end

--- Animation am Treiber anmelden (einmalig, ~30 Hz); fn(t) liefert true, solange sie laeuft
function Style.AddStepper(fn)
    for _, f in ipairs(steppers) do if f == fn then return end end
    steppers[#steppers + 1] = fn
end

--- Animation, die jedes Bild laufen soll (nicht im 30-Hz-Takt), am Treiber anmelden (einmalig)
function Style.AddFastStepper(fn)
    for _, f in ipairs(fastSteppers) do if f == fn then return end end
    fastSteppers[#fastSteppers + 1] = fn
end

--- Treiber wecken (legt ihn beim ersten Mal an)
function Style.WakeDriver()
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", function(_, dt)
            local ok, err = pcall(driverStep, dt)
            if not ok then recordError(err) end
        end)
    end
    if not driverOn then
        driverOn = true
        driver:Show()
    end
end

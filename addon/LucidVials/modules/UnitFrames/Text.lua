-- Dauer-Zahlen (Ausbau 1.1.0, K3): Werte fuer Leben, Ressource und Erfahrung auf den Roehren von Skin.lua und XP.lua.
--
-- Bereich "text" im Profil (Skin.RegisterArea): je Roehre (health, power) Format, Darstellung und Wertfarbe, je Rahmen
-- abweichend moeglich (Vererbung ueber Skin.GetFrameConfig); dazu die XP-Formate (nur "fuer alle").
-- Eine secret-sichere Kette fuer alle Faelle (Recherche A): Leben/Ressource sind im Kampf (Forever teils immer) secret. Die
-- Rohwerte gehen nur an Blizzards Format-APIs (AbbreviateNumbers, BreakUpLargeNumbers, C_StringUtil, UnitHealthPercent mit
-- Kurve) und von dort per SetFormattedText mit %s/%.0f an eigene FontStrings - nie verglichen, gerechnet, verkettet oder
-- gelesen; alles in pcall. Nach dem Setzen wird kein Text und keine Breite gelesen (feste Breite, keine Messung).
-- Formate: Aus, Wie Blizzard (Standard: nichts wird angefasst), Blizzard-Muster dauerhaft (folgt der CVar statusTextDisplay,
-- CVAR_UPDATE), Zahl kurz, Zahl voll, Prozent, Zahl + Prozent, aktuell / max (kurz, voll), Defizit (volle Zahl, leer bei voll).
-- Darstellungen: Blizzard-Stil (mittig, Blizzard-Schrift), Auf dem Glas (mittig, eigene Schrift), Schwimmt auf dem Pegel (haengt
-- an der Fuellkante lb.barTex der unsichtbaren StatusBar, im Roehren-Clip, feste Breite, wippt mit den eigenen, lesbaren
-- Schwapp-Zahlen lb.tilt/lb.wave; fuellt die Leiste umgekehrt, haengt er an der gespiegelten Kante), Ins Glas graviert (mittig,
-- Aetz-Optik aus drei Kopien). Wertfarbe fest oder per Farbkurve (C_CurveUtil, Farbe nur an SetTextColor durchgereicht).
-- Blizzards Statustext (HealthBarText/ManaBarText/LeftText/RightText der Leiste) wird nur bei eigenen Formaten (auch "Aus")
-- per SetAlpha(0) verdeckt und beim Zurueckwechseln auf 1 gestellt - nie CVar setzen, keine Hooks, keine Felder an
-- TextStatusBar, kein Show/Hide an Blizzard. XP ist nicht secret: freie Formate (aktuell / max, Prozent, Rest, Ruhebonus).
-- Haken: Skin.lua (apply -> Attach, feed/refreshUnit -> Update, remove -> Detach), XP.lua (AttachXP/UpdateXP/DetachXP).
-- /vials test zahlen zeigt alle Roehren mit lesbaren Beispielwerten.
-- Mini-Vorschau (Preview.lua): sk.text.values = { health = { cur, max }, power = { cur, max } } (eigene, lesbare Zahlen je
-- Instanz, Quelle VALUES statt LIVE/TEST); "Wie Blizzard" zeigt dort das Blizzard-Muster in Blizzards Schrift (es gibt keinen
-- Blizzard-Text, der stehen bleiben koennte) und spiegelt Blizzards Statustext-Einstellung (Text.BlizzardMode): NONE = nur bei
-- Maus ueber der Buehne (Text.SetHover), NUMERIC = aktuell / max, PERCENT = Prozent, BOTH = Prozent links, Zahl rechts (wie
-- Blizzards LeftText/RightText), Blizzards Farbe. XP-Roehre der Vorschau: st.preview, Werte nur ueber Text.UpdateXP.
local _, ns = ...
local Compat, L = ns.Compat, ns.L
local Style = ns.Style
local Skin = ns.UnitFrameSkin

local Text = {}
ns.UnitText = Text
Skin.Text = Text

Text.FORMATS = { "off", "blizzard", "pattern", "short", "full", "percent", "numPercent", "curmaxShort", "curmaxFull", "deficit" }
Text.DISPLAYS = { "blizzard", "glass", "float", "engraved" }
Text.COLOR_KEYS = { "light", "white", "gold", "curve" }
-- Lage der Zahlen bei "Wie Blizzard": blizzard = Blizzards eigener Text an seiner Stelle (Standard, nichts angefasst);
-- center = Blizzards Text per SetAlpha(0) verdeckt, eigener FontString mittig auf der Roehre mit Blizzards Muster, Schrift und
-- Farbe; bei Blizzards Einstellung "nur bei Maus" (NONE) gedrosselt ueber IsMouseOver am Blizzard-Rahmen (nur gelesen)
Text.PLACES = { "blizzard", "center" }
Text.HOVER_POLL = 0.1
Text.COLORS = { light = { 0.96, 0.91, 0.78 }, white = { 1, 1, 1 }, gold = { 1.0, 0.82, 0.38 } }
-- Farbkurve "nach Stand" (Anteil 0..1 -> Farbe): rot, bernstein, gold, hell
Text.CURVE = { { 0, { 0.92, 0.22, 0.16 } }, { 0.35, { 1.0, 0.58, 0.20 } }, { 0.7, { 1.0, 0.84, 0.40 } }, { 1, { 0.96, 0.91, 0.78 } } }
Text.XP_PARTS = { "curmax", "percent", "remaining", "rested" }
Text.BARS = { "health", "power" }
-- Blizzards Statustext je Leiste (parentKeys): an der Leiste selbst und (Leben) am HealthBarsContainer
Text.BLIZZ_KEYS = { bar = { "TextString", "HealthBarText", "ManaBarText", "LeftText", "RightText" },
    parent = { "HealthBarText", "LeftText", "RightText" } }
Text.SIZE = { rel = 0.62, min = 7, max = 14, xp = 0.8, inset = 4 } -- Schriftgroesse x Roehrenhoehe, Rand in px
Text.BOB = { wave = 0.45, tilt = 0.25, max = 0.2, step = 0.5 }      -- Wippen: x Roehrenhoehe, Schwelle in px
-- "Schwimmt auf dem Pegel": zwei Kopien, links der Kante (in der Fluessigkeit) und rechts davon (im leeren Glas). Welche zu sehen
-- ist, entscheidet eine Alpha-Kurve ueber den Fuellanteil (UnitHealthPercent/UnitPowerPercent mit Kurve, secret-sicher, nur an
-- SetAlpha): unter der Schwelle (Textbreite + Rand passt nicht mehr links der Kante) wechselt der Wert weich (fade = Breite der
-- Ueberblendung im Anteil) auf die andere Seite. Textbreite aus GetStringWidth, wenn lesbar, sonst geschaetzt (chars x Groesse).
Text.FLOAT = { margin = 4, fade = 0.03, min = 0.02, max = 0.98, charW = 0.55,
    chars = { short = 6, full = 9, percent = 5, numPercent = 12, both = 14, curmaxShort = 13, curmaxFull = 19, deficit = 9 } }
-- "Ins Glas graviert": mattierte Aetzung im Glas ueber der Fluessigkeit - Grundschrift hell-kuehl mit niedriger Deckkraft (die
-- Fluessigkeit scheint durch), eingelassene Kante aus Lichtkante (helle Kopie lightPx Pixel tiefer) und Schattenkante (dunkle Kopie
-- darkPx Pixel hoeher), Grundschrift obenauf; keine Kontur, kein Schatten (ueberstimmt die Schrift-Einstellungen). Offsets in
-- ganzen Bildschirmpixeln. Helle Fluessigkeit (Leuchtdichte der eigenen Farbe ueber brightLum): Lichtkante x brightK.
Text.ENGRAVE = { base = { 0.90, 0.95, 1.0 }, baseA = 0.24, light = { 1, 1, 1 }, lightA = 0.3, lightPx = 1,
    dark = { 0, 0, 0 }, darkA = 0.3, darkPx = 1, brightLum = 0.75, brightK = 0.55 }
Text.SHADOW = { 0, 0, 0, 0.9 }
-- /vials test zahlen: lesbare Beispielwerte je Rahmen; Formate "Aus"/"Wie Blizzard" zeigen dabei Zahl + Prozent auf dem Glas
Text.TEST = {
    player = { health = { 12345, 16842 }, power = { 4210, 6000 } },
    target = { health = { 84210, 120000 }, power = { 35, 100 } },
    tot = { health = { 2500, 5000 }, power = { 80, 100 } },
    xp = { 4200, 9800, 1500 },
}
Text.TEST_FORMAT, Text.TEST_DISPLAY = "numPercent", "glass"
Text.TEST_WORDS = { "zahlen", "numbers" }

local FORMAT_SET, DISPLAY_SET, COLOR_SET, PLACE_SET = {}, {}, {}, {}
for _, k in ipairs(Text.PLACES) do PLACE_SET[k] = true end
for _, k in ipairs(Text.FORMATS) do FORMAT_SET[k] = true end
for _, k in ipairs(Text.DISPLAYS) do DISPLAY_SET[k] = true end
for _, k in ipairs(Text.COLOR_KEYS) do COLOR_SET[k] = true end

-- Profil-Bereich "text" ------------------------------------------------------------------------------------------------
function Text.Defaults()
    return { health = { format = "blizzard", display = "glass", color = "light", place = "blizzard" },
        power = { format = "blizzard", display = "glass", color = "light", place = "blizzard" },
        xp = { curmax = false, percent = false, remaining = false, rested = false } }
end

local function pick(v, set, default)
    if type(v) == "string" and set[v] then return v end
    return default
end

--- Bereich pruefen (feldweise: ein ungueltiges Feld faellt auf seinen Standard, unbekannte Felder fallen weg)
function Text.Validate(t)
    if type(t) ~= "table" then return nil end
    local out = Text.Defaults()
    for _, kind in ipairs(Text.BARS) do
        local src, d = t[kind], out[kind]
        if type(src) == "table" then
            d.format = pick(src.format, FORMAT_SET, d.format)
            d.display = pick(src.display, DISPLAY_SET, d.display)
            d.color = pick(src.color, COLOR_SET, d.color)
            d.place = pick(src.place, PLACE_SET, d.place)
        end
    end
    if type(t.xp) == "table" then
        for _, k in ipairs(Text.XP_PARTS) do
            if type(t.xp[k]) == "boolean" then out.xp[k] = t.xp[k] end
        end
    end
    return out
end

Skin.RegisterArea("text", { defaults = Text.Defaults, validate = Text.Validate })

--- wirksamer Bereich fuer einen Rahmen ("player"|"target"|"tot"|"xp"); Fehler => Standard (nichts wird angefasst)
function Text.Config(frameId)
    local ok, c = pcall(frameId and Skin.GetFrameConfig or Skin.GetConfig, frameId) -- ohne Rahmen: "fuer alle"
    local t = ok and type(c) == "table" and c.text or nil
    return (type(t) == "table" and Text.Validate(t)) or Text.Defaults()
end

--- true, wenn das Format eine eigene Anzeige bedeutet (dann ist Blizzards Statustext verdeckt; "Aus" zeigt nichts)
function Text.IsOwn(format) return format ~= "blizzard" end
function Text.Shows(format) return format ~= "blizzard" and format ~= "off" end

-- Hilfen (Muster wie Skin.lua: nie ungeschuetzt in Blizzard-Tabellen greifen) --------------------------------------------
local function getField(t, k) return t[k] end
local function field(t, key)
    if type(t) ~= "table" or Compat.IsSecret(t) then return nil end
    local ok, v = pcall(getField, t, key)
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

local function isFontString(o)
    local ok, t = call(o, "GetObjectType")
    return ok and t == "FontString"
end

local function cvar(name)
    local fn = (_G.C_CVar and _G.C_CVar.GetCVar) or _G.GetCVar
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, name)
    if ok and type(v) == "string" and not Compat.IsSecret(v) then return v end
    return nil
end

-- Wertquellen: LIVE reicht die (oft secret) Rohwerte der Einheit durch, TEST liefert lesbare Beispielwerte. Beide speisen
-- dieselbe Kette (compose) -------------------------------------------------------------------------------------------------
local LIVE = {}
function LIVE.cur(unit, kind, pt)
    if kind == "health" then return UnitHealth(unit) end
    return UnitPower(unit, pt)
end
function LIVE.max(unit, kind, pt)
    if kind == "health" then return UnitHealthMax(unit) end
    return UnitPowerMax(unit, pt)
end
function LIVE.pct(unit, kind, pt, curve)
    if kind == "health" then return UnitHealthPercent(unit, true, curve) end
    return UnitPowerPercent(unit, pt, false, curve)
end
function LIVE.miss(unit, kind, pt)
    if kind == "health" then return UnitHealthMissing(unit, true) end
    return UnitPowerMissing(unit, pt)
end

local testOn = false
local TEST = {}
local function testPair(unit, kind)
    local id = unit == "targettarget" and "tot" or unit
    local t = Text.TEST[id] or Text.TEST.player
    return t[kind] or t.health
end
function TEST.cur(unit, kind) return testPair(unit, kind)[1] end
function TEST.max(unit, kind) return testPair(unit, kind)[2] end
function TEST.pct(unit, kind, _, curve)
    local p = testPair(unit, kind)
    local frac = p[1] / p[2]
    if curve == Text.ScaleCurve() then return frac * 100 end
    return curve:Evaluate(frac)
end
function TEST.miss(unit, kind)
    local p = testPair(unit, kind)
    return p[2] - p[1]
end

-- Mini-Vorschau: Werte je Instanz (statt unit kommt die Wertetabelle der Vorschau an)
local VALUES = {}
local function valuePair(v, kind) return v[kind] or v.health end
function VALUES.cur(v, kind) return valuePair(v, kind)[1] end
function VALUES.max(v, kind) return valuePair(v, kind)[2] end
function VALUES.pct(v, kind, _, curve)
    local p = valuePair(v, kind)
    local frac = p[2] > 0 and math.max(0, math.min(1, p[1] / p[2])) or 0
    if curve == Text.ScaleCurve() then return frac * 100 end
    return curve:Evaluate(frac)
end
function VALUES.miss(v, kind)
    local p = valuePair(v, kind)
    return math.max(0, p[2] - p[1])
end

--- Quelle der Kette: Vorschau-Werte (e.values) vor Testwerten vor Live-Werten
local function source(e, unit)
    if e.values then return VALUES, e.values end
    return testOn and TEST or LIVE, unit
end

-- Kurven (einmal angelegt): Prozent 0..100 (CurveConstants.ScaleTo100, sonst eigene lineare Kurve) und die Wertfarbe
local scaleCurve, colorCurve
function Text.ScaleCurve()
    if scaleCurve ~= nil then return scaleCurve or nil end
    scaleCurve = false
    local K = _G.CurveConstants
    if type(K) == "table" and K.ScaleTo100 ~= nil then
        scaleCurve = K.ScaleTo100
        return scaleCurve
    end
    local C = _G.C_CurveUtil
    if not (C and type(C.CreateCurve) == "function") then return nil end
    local ok, c = pcall(C.CreateCurve)
    if not ok or c == nil then return nil end
    if pcall(c.AddPoint, c, 0, 0) and pcall(c.AddPoint, c, 1, 100) then scaleCurve = c end
    return scaleCurve or nil
end

function Text.ColorCurve()
    if colorCurve ~= nil then return colorCurve or nil end
    colorCurve = false
    local C = _G.C_CurveUtil
    if not (C and type(C.CreateColorCurve) == "function" and type(CreateColor) == "function") then return nil end
    local ok, c = pcall(C.CreateColorCurve)
    if not ok or c == nil then return nil end
    for _, p in ipairs(Text.CURVE) do
        if not pcall(c.AddPoint, c, p[1], CreateColor(p[2][1], p[2][2], p[2][3], 1)) then return nil end
    end
    colorCurve = c
    return c
end

-- CVars von Blizzards Statustext (nur gelesen, nie gesetzt): statusTextDisplay (NONE/NUMERIC/PERCENT/BOTH), aeltere Clients
-- statusText (0 = nur bei Maus, 1 = immer) + statusTextPercentage (1 = Prozent)
Text.STATUS_CVARS = { statustextdisplay = true, statustext = true, statustextpercentage = true }
local MODES = { NONE = true, NUMERIC = true, PERCENT = true, BOTH = true }

--- Blizzards Statustext-Einstellung: "NONE" (nur bei Maus) | "NUMERIC" | "PERCENT" | "BOTH"; unlesbar => "NUMERIC"
function Text.BlizzardMode()
    local v = cvar("statusTextDisplay")
    if v and MODES[v] then return v end
    local on = cvar("statusText")
    if on == "0" then return "NONE" end
    if on == "1" then return cvar("statusTextPercentage") == "1" and "PERCENT" or "NUMERIC" end
    return "NUMERIC"
end

--- Blizzard-Muster: Format aus Blizzards Statustext-Einstellung (Text.BlizzardMode). Beides = Prozent + Zahl (Ressource nur bei
--- Mana, sonst wie Blizzard nur die aktuelle Zahl); Zahl, Keiner und Unbekanntes = aktuell / max.
function Text.PatternFormat(kind, pt)
    local v = Text.BlizzardMode()
    if v == "PERCENT" then return "percent" end
    if v == "BOTH" then
        if kind == "health" or pt == 0 then return "both" end
        return "full"
    end
    return "curmaxFull"
end

-- Die Kette: liefert Formatmuster, Anzahl der Argumente und die (ggf. secret) Argumente. Nur Durchreichen an Format-APIs.
local function compose(api, unit, kind, fmt, pt)
    if fmt == "pattern" then fmt = Text.PatternFormat(kind, pt) end
    if fmt == "short" then
        return "%s", 1, AbbreviateNumbers(api.cur(unit, kind, pt))
    elseif fmt == "full" then
        return "%s", 1, BreakUpLargeNumbers(api.cur(unit, kind, pt))
    elseif fmt == "percent" then
        return L.TEXT_PAT_PCT, 1, api.pct(unit, kind, pt, Text.ScaleCurve())
    elseif fmt == "numPercent" then
        return L.TEXT_PAT_NUMPCT, 2, AbbreviateNumbers(api.cur(unit, kind, pt)), api.pct(unit, kind, pt, Text.ScaleCurve())
    elseif fmt == "both" then
        return L.TEXT_PAT_BOTH, 2, api.pct(unit, kind, pt, Text.ScaleCurve()), BreakUpLargeNumbers(api.cur(unit, kind, pt))
    elseif fmt == "curmaxShort" then
        return "%s / %s", 2, AbbreviateNumbers(api.cur(unit, kind, pt)), AbbreviateNumbers(api.max(unit, kind, pt))
    elseif fmt == "curmaxFull" then
        return "%s / %s", 2, BreakUpLargeNumbers(api.cur(unit, kind, pt)), BreakUpLargeNumbers(api.max(unit, kind, pt))
    elseif fmt == "deficit" then
        local S = C_StringUtil
        return "%s", 1, S.WrapString(S.TruncateWhenZero(api.miss(unit, kind, pt)), "-")
    end
    return "%s", 1, ""
end
Text.Compose = compose

local function setAll(e, pat, n, a, b)
    for _, fs in ipairs(e.list) do
        if n == 2 then fs:SetFormattedText(pat, a, b) else fs:SetFormattedText(pat, a) end
    end
end

local function clearAll(e)
    for _, fs in ipairs(e.list) do pcall(fs.SetText, fs, "") end
end

local function powerType(unit)
    local ok, pt = pcall(UnitPowerType, unit)
    return ok and Compat.Num(pt) or nil
end

--- Wert einer Roehre setzen (secret-sicher). Liefert true, wenn die Kette lief.
local function renderValue(e, unit)
    local api, src = source(e, unit)
    local pt = e.kind == "power" and powerType(e.values and "player" or unit) or nil
    local ok, pat, n, a, b = pcall(compose, api, src, e.kind, e.fmt, pt) -- ohne neue Closure je Ereignis
    if ok then ok = pcall(setAll, e, pat, n, a, b) end
    if not ok then clearAll(e) end
    return ok
end

--- Vorschau, "Wie Blizzard": Blizzards Anordnung - BOTH = Prozent links (LeftText), Zahl rechts (RightText), sonst mittig
local function renderMirror(e, unit)
    local api, src = source(e, unit)
    local pt = e.kind == "power" and powerType(e.values and "player" or unit) or nil
    local fmt = Text.PatternFormat(e.kind, pt)
    local split = e.split and fmt == "both" -- Blizzards Lage: Prozent links, Zahl rechts; mittig: beides zusammen
    -- Vorschau in Blizzards Lage: Anker an der Ersatz-Leiste (wie Blizzards TextString), sonst die Roehre
    local A = e.anchor
    local root, I, dy = A and A.region or e.lb.root, Text.SIZE.inset, A and A.dy or 0
    local okW, rw = pcall(root.GetWidth, root)
    rw = okW and Compat.Num(rw) or nil
    local w = math.max(1, (rw or e.lb.w or 100) - 2 * I)
    e.main:ClearAllPoints()
    e.hi:ClearAllPoints()
    if split then
        e.main:SetJustifyH("LEFT")
        e.main:SetPoint("LEFT", root, "LEFT", I, dy)
        e.hi:SetJustifyH("RIGHT")
        e.hi:SetPoint("RIGHT", root, "RIGHT", -I, dy)
        e.main:SetWidth(w / 2)
        e.hi:SetWidth(w / 2)
    else
        e.main:SetJustifyH("CENTER")
        e.main:SetPoint("CENTER", root, "CENTER", 0, dy)
        e.main:SetWidth(w)
        e.hi:SetText("")
    end
    e.hi:SetShown(split)
    local ok, pat, n, a, b = pcall(compose, api, src, e.kind, split and "percent" or fmt, pt)
    if ok then ok = pcall(setAll, e, pat, n, a, b) end
    if ok and split then
        local ok2, pat2, n2, a2 = pcall(compose, api, src, e.kind, "full", pt)
        ok = ok2 and pcall(e.hi.SetFormattedText, e.hi, pat2, a2) and n2 == 1
        local c = Text.COLORS.white
        e.hi:SetTextColor(c[1], c[2], c[3], 1)
        e.hi:SetAlpha(1)
    end
    if not ok then
        clearAll(e)
        e.hi:SetText("")
    end
    return ok
end

local plainFont, pixel -- Gravur-Hilfen (unten)

--- Gravur: feste Aetz-Farben; Lichtkante bei heller Fluessigkeit zurueckgenommen (eigene, lesbare Tint-Farbe, kein Wert)
local function paintEngraved(e)
    local E = Text.ENGRAVE
    local t = e.lb and e.lb.tintArg
    local c = type(t) == "table" and ((t.tex == "color" and t.base) or t.color) or nil
    local la = E.lightA
    if type(c) == "table" and Compat.Num(c[1]) and Compat.Num(c[2]) and Compat.Num(c[3])
        and 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3] > E.brightLum then
        la = la * E.brightK
    end
    e.main:SetTextColor(E.base[1], E.base[2], E.base[3], 1)
    e.lo:SetTextColor(E.light[1], E.light[2], E.light[3], 1)
    e.hi:SetTextColor(E.dark[1], E.dark[2], E.dark[3], 1)
    e.main:SetAlpha(E.baseA)
    e.lo:SetAlpha(la)
    e.hi:SetAlpha(E.darkA)
end

--- Wertfarbe: fest, oder Farbe aus der Kurve (secret ColorMixin, nur an SetTextColor); Gravur: eigene Aetz-Farben
local function paintValue(e, unit)
    if e.display == "engraved" then
        paintEngraved(e)
        return
    end
    local fs = e.main
    if e.color == "curve" then
        local curve = Text.ColorCurve()
        if curve then
            local api, src = source(e, unit)
            local pt = e.kind == "power" and powerType(e.values and "player" or unit) or nil
            local ok = pcall(function()
                local col = api.pct(src, e.kind, pt, curve)
                fs:SetTextColor(col:GetRGBA())
                e.alt:SetTextColor(col:GetRGBA())
            end)
            if ok then return end
        end
    end
    local c = Text.COLORS[e.color] or Text.COLORS.light
    pcall(fs.SetTextColor, fs, c[1], c[2], c[3], 1)
    pcall(e.alt.SetTextColor, e.alt, c[1], c[2], c[3], 1)
end

-- Aufbau je Roehre -------------------------------------------------------------------------------------------------------
local floats = {}   -- Eintrag -> true (Darstellung "Schwimmt auf dem Pegel", wippt)
local bobOn = false

--- Gravur: Kontur und Schatten aus (Schrift und Groesse bleiben die gewaehlten)
plainFont = function(fs)
    local ok, path, size = call(fs, "GetFont")
    if ok and type(path) == "string" and Compat.Num(size) then call(fs, "SetFont", path, size, "") end
    call(fs, "SetShadowOffset", 0, 0)
    call(fs, "SetShadowColor", 0, 0, 0, 0)
end

--- ein Bildschirmpixel in UI-Einheiten des Frames (ganzzahlige Offsets bei jeder Skalierung); unlesbar => 1
pixel = function(frame)
    local P = _G.PixelUtil
    local okF, f = pcall(function() return P.GetPixelToUIUnitFactor() end)
    f = okF and Compat.Num(f) or nil
    local s = num(frame, "GetEffectiveScale")
    if f and f > 0 and s and s > 0 then return f / s end
    return 1
end

local function fallbackFont(fs, size)
    local path = (Style and Style.FontPath and Style.FontPath("marcellus")) or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local ok, r = call(fs, "SetFont", path, size, "OUTLINE")
    if not ok or r == false then call(fs, "SetFont", _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE") end
end

--- Schrift einer Kopie: Blizzard-Stil = Blizzards Statustext-Schrift; sonst ns.Fonts (Schrift-Reiter) bzw. Marcellus
-- Schrift nicht (wie gewaehlt) gesetzt (z. B. Schriftdatei beim Login noch nicht geladen => Rueckfall): spaeter erneut anwenden
local fontRetry = false

local function applyFont(fs, display, element, frameId, size)
    local ownShadow = true -- Schatten setzen wir selbst, ausser ns.Fonts hat ihn schon nach der Wahl im Schrift-Reiter gesetzt
    if display == "blizzard" then
        local obj = _G.TextStatusBarText
        if not (obj and call(fs, "SetFontObject", obj)) then
            call(fs, "SetFont", _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
        end
    elseif ns.Fonts and type(ns.Fonts.Apply) == "function" then
        -- size ist die Auto-Groesse dieses Textes (Fonts.Apply nutzt sie, solange im Schrift-Reiter die Groesse auf Auto steht)
        local ok, applied, used = pcall(ns.Fonts.Apply, fs, element, frameId, size)
        if ok and applied then ownShadow = false else fallbackFont(fs, size) end
        if not (ok and applied) then
            fontRetry = true
        elseif type(ns.Fonts.Spec) == "function" and type(ns.Fonts.Resolve) == "function" then
            local okS, spec = pcall(ns.Fonts.Spec, element, frameId)
            local okR, want = pcall(ns.Fonts.Resolve, okS and type(spec) == "table" and spec.face or nil)
            if okR and type(want) == "string" and used ~= want then fontRetry = true end
        end
    else
        fallbackFont(fs, size)
    end
    if ownShadow then
        local S = Text.SHADOW
        call(fs, "SetShadowColor", S[1], S[2], S[3], S[4])
        call(fs, "SetShadowOffset", 1, -1)
    end
end

local function newEntry(lb, kind)
    local e = { lb = lb, kind = kind, dy = 0 }
    e.frame = CreateFrame("Frame", nil, lb.root)
    e.frame:SetAllPoints(lb.root)
    pcall(e.frame.SetClipsChildren, e.frame, true)
    e.lo = e.frame:CreateFontString(nil, "OVERLAY")
    e.hi = e.frame:CreateFontString(nil, "OVERLAY")
    e.main = e.frame:CreateFontString(nil, "OVERLAY")
    e.alt = e.frame:CreateFontString(nil, "OVERLAY") -- "Schwimmt": Kopie rechts der Kante (wenig Fuellung)
    for i, fs in ipairs({ e.lo, e.hi, e.main, e.alt }) do
        call(fs, "SetDrawLayer", "OVERLAY", i)
        call(fs, "SetWordWrap", false)
        if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
    end
    e.frame:Hide()
    return e
end

--- Kante, an der der Wert schwimmt: Ende der Fuellung (eigene StatusBar; umgekehrt gefuellt => linke Kante)
local function edgeOf(lb)
    if Compat.QueryBool(lb.bar, "GetReverseFill") == true then return "LEFT" end
    return "RIGHT"
end

local function anchorFloat(e)
    local lb, I = e.lb, Text.SIZE.inset
    local edge = e.edge
    local x = edge == "RIGHT" and -I or I
    local anchor = lb.barTex or lb.root
    e.main:ClearAllPoints() -- "Schwimmt": Wert in der Fluessigkeit an der Kante, die Kopie e.alt jenseits der Kante
    e.main:SetPoint(edge, anchor, edge, x, e.dy)
    local opp = edge == "RIGHT" and "LEFT" or "RIGHT"
    e.alt:ClearAllPoints()
    e.alt:SetPoint(opp, anchor, edge, -x, e.dy)
end

-- Alpha-Kurven je Schwelle (in 1-%-Stufen, einmal angelegt): main = 0 unter, 1 ueber der Schwelle; alt umgekehrt
local sideCurves = {}
local function curvesAt(th)
    local key = math.floor(th * 100 + 0.5)
    local c = sideCurves[key]
    if c ~= nil then return c or nil end
    sideCurves[key] = false
    local C = _G.C_CurveUtil
    if not (C and type(C.CreateCurve) == "function") then return nil end
    local t, f = key / 100, Text.FLOAT.fade / 2
    local pair = {}
    for i, pts in ipairs({ { { 0, 0 }, { t - f, 0 }, { t + f, 1 }, { 1, 1 } }, { { 0, 1 }, { t - f, 1 }, { t + f, 0 }, { 1, 0 } } }) do
        local ok, cv = pcall(C.CreateCurve)
        if not ok or cv == nil then return nil end
        local linear = type(Enum) == "table" and type(Enum.LuaCurveType) == "table" and Enum.LuaCurveType.Linear or 0
        pcall(cv.SetType, cv, linear)
        for _, p in ipairs(pts) do
            if not pcall(cv.AddPoint, cv, math.max(0, math.min(1, p[1])), p[2]) then return nil end
        end
        pair[i] = cv
    end
    sideCurves[key] = pair
    return pair
end

--- Schwelle (Fuellanteil), ab der der Wert links der Kante Platz hat (nur eigene, lesbare Zahlen)
local function floatThreshold(e)
    local F, I = Text.FLOAT, Text.SIZE.inset
    local okW, tw = pcall(e.main.GetStringWidth, e.main)
    tw = okW and Compat.Num(tw) or nil
    if not (tw and tw > 0) then tw = (F.chars[e.fmt] or 10) * (e.size or 10) * F.charW end
    local w = e.lb.w or 100
    return math.max(F.min, math.min(F.max, (tw + 2 * I + F.margin) / math.max(1, w)))
end

--- "Schwimmt": Seite per Kurven-Alpha (secret nur durchgereicht); ohne Kurve wie bisher nur links der Kante
local function floatSides(e, unit)
    local pair = curvesAt(floatThreshold(e))
    if pair then
        local api, src = source(e, unit)
        local pt = e.kind == "power" and powerType(e.values and "player" or unit) or nil
        local okA, a = pcall(api.pct, src, e.kind, pt, pair[1])
        local okB, b = pcall(api.pct, src, e.kind, pt, pair[2])
        if okA and okB and pcall(e.main.SetAlpha, e.main, a) and pcall(e.alt.SetAlpha, e.alt, b) then return end
    end
    e.main:SetAlpha(1)
    e.alt:SetAlpha(0)
end

local function layoutEntry(e, frameId)
    local lb = e.lb
    local h, w, I = lb.h or 10, lb.w or 100, Text.SIZE.inset
    local S = Text.SIZE
    local size = math.max(S.min, math.min(S.max, math.floor(h * S.rel + 0.5)))
    local topL = num(lb.top, "GetFrameLevel") or 1
    e.frame:SetFrameLevel(topL + 1)
    local engraved = e.display == "engraved"
    e.size = size
    local float = e.display == "float"
    for _, fs in ipairs({ e.lo, e.hi, e.main, e.alt }) do
        applyFont(fs, e.display, e.kind, frameId, size)
        fs:SetWidth(math.max(1, w - 2 * I))
    end
    e.list = engraved and { e.main, e.hi, e.lo } or (float and { e.main, e.alt } or { e.main })
    e.alt:SetShown(float)
    if not float then
        e.alt:SetText("")
        e.alt:SetAlpha(0)
    end
    e.hi:SetShown(engraved)
    e.lo:SetShown(engraved)
    if not engraved then
        e.hi:SetText("")
        e.lo:SetText("")
    end
    local E = Text.ENGRAVE
    if engraved then
        for _, fs in ipairs({ e.main, e.hi, e.lo }) do plainFont(fs) end
        paintEngraved(e)
    else
        e.main:SetAlpha(1)
    end
    floats[e] = nil
    if e.display == "float" then
        e.edge, e.dy = edgeOf(lb), 0
        for _, fs in ipairs({ e.lo, e.hi, e.main }) do fs:SetJustifyH(e.edge) end
        e.alt:SetJustifyH(e.edge == "RIGHT" and "LEFT" or "RIGHT")
        anchorFloat(e)
        floats[e] = true
    else
        local px = pixel(e.frame)
        -- e.hi = Schattenkante (hoeher), e.lo = Lichtkante (tiefer); Zeichenebenen lo < hi < main (newEntry)
        local pts = { { e.main, 0, 0 }, { e.hi, 0, E.darkPx * px }, { e.lo, 0, -E.lightPx * px } }
        for _, p in ipairs(pts) do
            p[1]:SetJustifyH("CENTER")
            p[1]:ClearAllPoints()
            p[1]:SetPoint("CENTER", lb.root, "CENTER", p[2], p[3])
        end
    end
end

--- Wippen der schwimmenden Werte mit lb.tilt/lb.wave (lesbare Zahlen der Bewegungsphysik); laeuft im Liquid-Treiber mit,
--- haelt ihn nicht selbst wach
local function bobStep()
    local B = Text.BOB
    for e in pairs(floats) do
        local lb = e.lb
        local h = lb.h or 10
        local dy = ((Compat.Num(lb.wave) or 0) * B.wave + (Compat.Num(lb.tilt) or 0) * B.tilt) * h
        local lim = B.max * h
        if dy > lim then dy = lim elseif dy < -lim then dy = -lim end
        if math.abs(dy - e.dy) >= B.step then
            e.dy = dy
            anchorFloat(e)
        end
    end
    return false
end
Text.BobStep = bobStep

local function ensureBob()
    if bobOn or not next(floats) or not (Style and Style.AddFastStepper) then return end
    bobOn = true
    Style.AddFastStepper(bobStep)
end

-- Blizzards Statustext verdecken / zurueckstellen (nur Alpha, nur setzen) ----------------------------------------------------
local function blizzTexts(sk, kind)
    local bar = kind == "health" and sk.hb or sk.mb
    local out, seen = {}, {}
    local function add(o)
        if isObject(o) and not seen[o] and isFontString(o) then
            seen[o] = true
            out[#out + 1] = o
        end
    end
    if not isObject(bar) then return out end
    for _, k in ipairs(Text.BLIZZ_KEYS.bar) do add(field(bar, k)) end
    if kind == "health" then
        local ok, parent = call(bar, "GetParent")
        if ok and isObject(parent) and parent ~= sk.root then
            for _, k in ipairs(Text.BLIZZ_KEYS.parent) do add(field(parent, k)) end
        end
    end
    return out
end
Text.BlizzTexts = blizzTexts

local function hideBlizz(st, sk, kind)
    local set = st.hidden[kind]
    for _, fs in ipairs(blizzTexts(sk, kind)) do
        set[fs] = true
        call(fs, "SetAlpha", 0)
    end
end

local function restoreBlizz(st, kind)
    for fs in pairs(st.hidden[kind]) do call(fs, "SetAlpha", 1) end
    st.hidden[kind] = {}
end

-- Rahmen (Skin.lua) ----------------------------------------------------------------------------------------------------------
local function unitOf(sk)
    local S = Skin.SPEC and Skin.SPEC[sk.id]
    return S and S.unit or sk.id
end

local function unitExists(unit)
    local ok, v = pcall(UnitExists, unit)
    return ok and Compat.Bool(v)
end

-- "Mittig" + Blizzards Einstellung "nur bei Maus": Maus ueber dem Blizzard-Rahmen gedrosselt lesen (IsMouseOver, nur lesen; kein
-- EnableMouse an eigenen Frames, Klicks bleiben Blizzards). Laeuft nur, solange ein echter Rahmen das braucht.
local hoverWatch = {} -- sk -> true
local hoverTicker = nil

local function mouseOver(sk)
    for _, f in ipairs({ sk.root, sk.hb, sk.mb }) do
        if isObject(f) and Compat.QueryBool(f, "IsMouseOver") == true then return true end
    end
    return false
end

local function pollHover()
    for sk in pairs(hoverWatch) do
        local st = sk.text
        if not (st and sk.applied) then
            hoverWatch[sk] = nil
        else
            local over = mouseOver(sk)
            if over ~= (st.hover == true) then
                st.hover = over
                Text.Update(sk)
            end
        end
    end
    if not next(hoverWatch) and hoverTicker then
        hoverTicker:Cancel()
        hoverTicker = nil
    end
end

local function watchHover(sk, on)
    hoverWatch[sk] = on and true or nil
    if not on and sk.text then sk.text.hover = false end
    if on and not hoverTicker and C_Timer and C_Timer.NewTicker then
        hoverTicker = C_Timer.NewTicker(Text.HOVER_POLL, pollHover)
    elseif not next(hoverWatch) and hoverTicker then
        hoverTicker:Cancel()
        hoverTicker = nil
    end
end
function Text.IsWatchingHover(sk) return hoverWatch[sk] == true and hoverTicker ~= nil end

--- Rahmen anwenden (aus Skin.lua apply): Einstellungen lesen, Blizzards Text verdecken bzw. zurueckstellen, Werte zeigen
function Text.Attach(sk, frameId)
    local st = sk.text
    if not st then
        st = { entries = {}, hidden = { health = {}, power = {} } }
        sk.text = st
    end
    st.frameId = frameId or sk.id
    local cfg = Text.Config(st.frameId)
    for _, kind in ipairs(Text.BARS) do
        local c = cfg[kind]
        local fmt, display = c.format, c.display
        local mirror, color, anchor, split = false, c.color, nil, false
        if st.values then -- Vorschau: kein Blizzard-Text da, "Wie Blizzard" spiegelt Blizzards Einstellung in seiner Schrift
            if fmt == "blizzard" then
                -- Blizzards Lage: Blizzards eigener Text (Blizzard-Schrift, die Schrift-Einstellungen wirken dort nicht);
                -- mittig: unser Text, Schrift/Kontur/Schatten aus dem Reiter Schrift (wie am echten Rahmen)
                fmt, display, mirror, color = "pattern", c.place == "center" and "glass" or "blizzard", true, "white"
                if c.place ~= "center" then -- Blizzards Lage nachgebildet (Anker der Vorschau, sonst mittig)
                    anchor, split = st.blizzAnchor and st.blizzAnchor[kind] or nil, true
                end
            end
        elseif fmt == "blizzard" and c.place == "center" then
            -- mittig: Blizzards Text verdeckt, eigener mit seinem Muster; unser FontString folgt dem Reiter Schrift
            fmt, display, mirror, color = "pattern", "glass", true, "white"
        elseif testOn and not Text.Shows(fmt) then
            fmt, display = Text.TEST_FORMAT, Text.TEST_DISPLAY
        end
        if Text.IsOwn(fmt) then hideBlizz(st, sk, kind) else restoreBlizz(st, kind) end
        local e = st.entries[kind]
        local lb = sk[kind]
        if Text.Shows(fmt) and lb and lb.root and (kind == "health" or sk.mb) then
            if not e then
                e = newEntry(lb, kind)
                st.entries[kind] = e
            end
            e.fmt, e.display, e.color, e.values, e.mirror = fmt, display, color, st.values, mirror
            e.anchor, e.split = anchor, split
            layoutEntry(e, st.frameId)
            pcall(e.frame.SetClipsChildren, e.frame, anchor == nil) -- Blizzards Lage darf unter der Roehre liegen
            e.frame:Show()
            e.on = true
        elseif e then
            e.on = false
            floats[e] = nil
            e.frame:Hide()
        end
    end
    ensureBob()
    if not st.values then -- echte Rahmen: Maus nur abfragen, wenn "mittig" bei Blizzards "nur bei Maus" laeuft
        local need = false
        for _, e in pairs(st.entries) do if e.on and e.mirror then need = true end end
        need = need and Text.BlizzardMode() == "NONE"
        if need and not st.hover then st.hover = mouseOver(sk) end
        watchHover(sk, need)
    end
    Text.Update(sk)
end

local HOW_KIND = { health = "health", maxhealth = "health", power = "power", maxpower = "power" }

--- Werte neu setzen (aus feed/refreshUnit); how wie in Skin.lua feed (nil/"snap" = beide Roehren)
function Text.Update(sk, how)
    local st = sk and sk.text
    if not st then return end
    local only = how and HOW_KIND[how] or nil
    local unit = unitOf(sk)
    local live = st.values ~= nil or testOn or unitExists(unit)
    for _, kind in ipairs(Text.BARS) do
        local e = st.entries[kind]
        if e and e.on and (not only or only == kind) then
            if e.mirror and (not live or (not st.hover and Text.BlizzardMode() == "NONE")) then -- wie Blizzard: nur bei Maus
                clearAll(e)
                e.hi:SetText("")
            elseif e.mirror then
                paintValue(e, unit)
                renderMirror(e, unit)
            elseif live then
                renderValue(e, unit)
                paintValue(e, unit)
                if e.display == "float" then floatSides(e, unit) end
            else
                clearAll(e)
            end
        end
    end
end

--- Vorschau: Maus ueber der Buehne (fuer "Wie Blizzard" bei Blizzards Einstellung "nur bei Maus")
function Text.SetHover(sk, on)
    local st = sk and sk.text
    if not st then return end
    st.hover = on == true
    Text.Update(sk)
end

--- Rahmen zurueckstellen (aus Skin.lua remove): Blizzards Text Alpha 1, eigene Werte weg
function Text.Detach(sk)
    local st = sk and sk.text
    if not st then return end
    if hoverWatch[sk] then watchHover(sk, false) end
    for _, kind in ipairs(Text.BARS) do
        restoreBlizz(st, kind)
        local e = st.entries[kind]
        if e then
            e.on = false
            floats[e] = nil
            clearAll(e)
            e.frame:Hide()
        end
    end
end

-- Erfahrung (XP.lua) ---------------------------------------------------------------------------------------------------------
local xpStates = setmetatable({}, { __mode = "k" })

local function blizzXpText(st)
    local t = field(field(st.xb, "OverlayFrame"), "Text")
    if isObject(t) and isFontString(t) then return t end
    return nil
end

local function xpParts()
    local p = Text.Config("xp").xp
    if testOn and not (p.curmax or p.percent or p.remaining or p.rested) then
        return { curmax = true, percent = true, remaining = false, rested = true }
    end
    return p
end

local function readXP()
    local okV, v = pcall(UnitXP, "player")
    local okM, mx = pcall(UnitXPMax, "player")
    local okE, e = pcall(GetXPExhaustion)
    return okV, v, okM, mx, okE and Compat.Num(e) or nil
end

--- XP-Roehre anwenden (aus XP.lua apply)
function Text.AttachXP(st)
    xpStates[st] = true
    local p = xpParts()
    local any = p.curmax or p.percent or p.remaining or p.rested
    local x = st.textXP
    local bt = blizzXpText(st)
    if any and st.lb and st.lb.root then
        if not x then
            x = { lb = st.lb }
            x.frame = CreateFrame("Frame", nil, st.lb.root)
            x.frame:SetAllPoints(st.lb.root)
            pcall(x.frame.SetClipsChildren, x.frame, true)
            x.fs = x.frame:CreateFontString(nil, "OVERLAY")
            call(x.fs, "SetWordWrap", false)
            st.textXP = x
        end
        local lb, S = st.lb, Text.SIZE
        x.frame:SetFrameLevel((num(lb.top, "GetFrameLevel") or 1) + 1)
        local size = math.max(S.min, math.min(S.max, math.floor((lb.h or 10) * S.xp + 0.5)))
        applyFont(x.fs, "glass", "xp", nil, size)
        x.fs:ClearAllPoints()
        x.fs:SetPoint("CENTER", lb.root, "CENTER", 0, 0)
        x.fs:SetWidth(math.max(1, (lb.w or 100) - 2 * S.inset))
        x.fs:SetJustifyH("CENTER")
        local c = Text.COLORS.light
        x.fs:SetTextColor(c[1], c[2], c[3], 1)
        x.parts, x.on = p, true
        x.frame:Show()
        if bt then
            x.blizz = bt
            call(bt, "SetAlpha", 0)
        end
        if x.last then
            Text.UpdateXP(st, unpack(x.last, 1, 5))
        elseif not st.preview then -- Vorschau: Werte kommen nur ueber Text.UpdateXP
            Text.UpdateXP(st, readXP())
        end
    elseif x then
        x.on = false
        x.frame:Hide()
        if x.blizz then
            call(x.blizz, "SetAlpha", 1)
            x.blizz = nil
        end
    end
end

local function xpString(p, v, mx, ne)
    local out = {}
    local B = BreakUpLargeNumbers
    if p.curmax then out[#out + 1] = B(v) .. " / " .. B(mx) end
    if p.percent then out[#out + 1] = L.TEXT_PAT_PCT:format(math.floor(v / mx * 100)) end
    if p.remaining then out[#out + 1] = L.TEXT_XP_REMAINING:format(B(math.max(0, mx - v))) end
    if p.rested and ne and ne > 0 then out[#out + 1] = L.TEXT_XP_RESTED:format(B(ne)) end
    return table.concat(out, "  ")
end
Text.XpString = xpString

--- XP-Wert setzen (aus XP.lua feed). XP ist nicht secret; trotzdem zaehlen nur lesbare Zahlen (Compat.Num), sonst leer.
function Text.UpdateXP(st, okV, v, okM, mx, ne)
    local x = st and st.textXP
    if not x then return end
    x.last = { okV, v, okM, mx, ne }
    if not x.on then return end
    local nv, nm, nr = okV and Compat.Num(v) or nil, okM and Compat.Num(mx) or nil, Compat.Num(ne)
    if testOn and not st.preview then
        local T = Text.TEST.xp
        nv, nm, nr = T[1], T[2], T[3]
    end
    if not (nv and nm and nm > 0) then
        x.fs:SetText("")
        return
    end
    local ok, s = pcall(xpString, x.parts, nv, nm, nr)
    x.fs:SetText(ok and s or "")
end

function Text.DetachXP(st)
    local x = st and st.textXP
    if not x then return end
    x.on = false
    x.frame:Hide()
    x.fs:SetText("")
    if x.blizz then
        call(x.blizz, "SetAlpha", 1)
        x.blizz = nil
    end
end

-- Alles neu anwenden (Einstellung, CVar, Testwort) -------------------------------------------------------------------------
function Text.RefreshAll()
    for _, id in ipairs(Skin.FRAMES) do
        local sk = Skin.Get(id)
        if sk and sk.applied then
            local ok, err = pcall(Text.Attach, sk, id)
            if not ok and Skin.RecordError then Skin.RecordError(err) end
        end
    end
    for st in pairs(xpStates) do
        if st.applied then
            local ok, err = pcall(Text.AttachXP, st)
            if not ok and Skin.RecordError then Skin.RecordError(err) end
        end
    end
end

-- Schrift je Element nach jedem (Neu-)Aufbau: Weltwechsel/Reload (PLAYER_ENTERING_WORLD, danach noch zweimal verzoegert, falls eine
-- Schriftdatei erst spaet bereitsteht) und Leisten-Typwechsel (UNIT_DISPLAYPOWER); bei Rueckfall erneut, hoechstens FONT_RETRY.n Mal
Text.FONT_RETRY = { delays = { 0.5, 2 }, n = 3, wait = 1 }
local retries = 0
local function reapplyFonts()
    fontRetry = false
    Text.RefreshAll()
    if fontRetry and retries < Text.FONT_RETRY.n and C_Timer and C_Timer.After then
        retries = retries + 1
        C_Timer.After(Text.FONT_RETRY.wait, reapplyFonts)
    end
end
Text.ReapplyFonts = reapplyFonts

Compat.TryOn("PLAYER_ENTERING_WORLD", function()
    retries = 0
    reapplyFonts()
    if C_Timer and C_Timer.After then
        for _, d in ipairs(Text.FONT_RETRY.delays) do C_Timer.After(d, function() reapplyFonts() end) end
    end
end)
Compat.TryOn("UNIT_DISPLAYPOWER", function(_, unit)
    if type(unit) == "string" and not Compat.IsSecret(unit) and (unit == "player" or unit == "target") then Text.RefreshAll() end
end)

Skin.OnConfigChanged(function(_, area)
    if area == nil or area == "text" then Text.RefreshAll() end
end)

Compat.TryOn("CVAR_UPDATE", function(_, name)
    if type(name) == "string" and not Compat.IsSecret(name) and Text.STATUS_CVARS[name:lower()] then Text.RefreshAll() end
end)

-- /vials test zahlen ---------------------------------------------------------------------------------------------------------
function Text.IsTesting() return testOn end

function Text.StopTest()
    if not testOn then return false end
    testOn = false
    Text.RefreshAll()
    return true
end

--- Testwort: Beispielwerte an/aus (Rahmen muessen sichtbar sein)
function Text.TestCommand()
    if testOn then
        Text.StopTest()
        ns.Print(L.TEXT_TEST_OFF)
        return false
    end
    if not Skin.IsEngaged() then
        ns.Print(L.FRAMES_TEST_NEED_ON)
        return nil
    end
    testOn = true
    Text.RefreshAll()
    ns.Print(L.TEXT_TEST_ON)
    return true
end

for _, word in ipairs(Text.TEST_WORDS) do Skin.RegisterTest(word, function() Text.TestCommand() end) end
ns.AddHelp("HELP_FRAMES_TESTZAHLEN")

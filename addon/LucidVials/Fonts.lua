-- Schriften (Delta "Ausbau 1.1.0", E3): Schriftwahl je Textelement (Name, Stufe, Lebenswert, Ressourcenwert, XP-Wert).
--
-- Quellen der Schriftliste (ns.Fonts.List):
--   * mitgeliefert (Fonts\, SIL OFL, unveraendert): Marcellus (Standard), Philosopher, Almendra, MedievalSharp,
--   * Blizzard: Friz Quadrata, Arial Narrow, Morpheus, Skurri - ueber Blizzards Font-Objekte. Der Pfad kommt zur Laufzeit aus
--     <Objekt>:GetFont() und behaelt damit die Sprachdatei des Clients (koKR/zhCN/... behalten ihre Zeichen); ein fester Pfad ist
--     nur der Rueckfall,
--   * LibSharedMedia-3.0, falls ein anderes Addon sie mitbringt: nur lesen (LibStub, List, Fetch), nie mitgeliefert, spaet
--     aufgeloest (PLAYER_LOGIN, beim Lesen der Liste, Rueckruf LibSharedMedia_Registered).
-- Gespeichert wird der NAME, nie der Pfad. Ein unbekannter Name (z. B. LSM-Addon entfernt) zeigt still Marcellus; der gespeicherte
-- Name wird dabei nie ueberschrieben. Nicht-lateinische Clients (koKR/zhCN/zhTW/ruRU): wie bisher die Client-Schrift, ausser die
-- Schrift hat die Zeichen (Philosopher in ruRU). SetFont immer mit Rueckfall (SetFont meldet fehlende Dateien mit false).
--
-- Bereich "font" im Profil (Skin.RegisterArea, Vertrag V1): je Element { face, size, outline = none|thin|thick, shadow }.
-- size 0 = Auto (die heutige Groesse des Aufrufers: Name je Rahmen, Stufe nach Plaettchen). Standard = heutige Optik
-- (Marcellus, ohne Kontur, Tintenschatten 1/-1).
local ADDON_NAME, ns = ...
local Style = ns.Style

local Fonts = {}
ns.Fonts = Fonts

local DIR = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\"

Fonts.DEFAULT = "Marcellus"
Fonts.ELEMENTS = { "name", "level", "health", "power", "xp" }
local ELEMENT_SET = {}
for _, e in ipairs(Fonts.ELEMENTS) do ELEMENT_SET[e] = true end
Fonts.OUTLINES = { "none", "thin", "thick" }
local FLAGS = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
Fonts.SIZE = { min = 6, max = 32 }                  -- feste Groesse; 0 = Auto
Fonts.AUTO_SIZE = { name = 13, level = 14, health = 10, power = 10, xp = 10 } -- wenn der Aufrufer keine Auto-Groesse nennt
Fonts.SHADOW = { 0.08, 0.04, 0.016, 0.85, 1, -1 } -- Tintenschatten wie bisher (Skin.NAME.shadow), Versatz x, y
Fonts.MAX_NAME = 64

-- mitgelieferte Schriften (name = gespeicherter Name; cyrillic: hat kyrillische Zeichen)
Fonts.BUNDLED = {
    { name = "Marcellus", file = "Marcellus-Regular.ttf" },
    { name = "Philosopher", file = "Philosopher-Regular.ttf", cyrillic = true },
    { name = "Almendra", file = "Almendra-Regular.ttf" },
    { name = "MedievalSharp", file = "MedievalSharp.ttf" },
}
-- Blizzard-Schriften: Font-Objekte (erster vorhandener gilt), fester Rueckfallpfad, Dateistamm zur Plausibilitaetspruefung
Fonts.BLIZZARD = {
    { name = "Friz Quadrata", objects = { "GameFontNormal" }, path = "Fonts\\FRIZQT__.TTF", stem = "frizqt" },
    { name = "Arial Narrow", objects = { "NumberFontNormal", "ChatFontNormal" }, path = "Fonts\\ARIALN.TTF", stem = "arialn" },
    { name = "Morpheus", objects = { "ItemTextFontNormal", "MailTextFontNormal" }, path = "Fonts\\MORPHEUS.ttf", stem = "morpheus" },
    { name = "Skurri", objects = { "NumberFontNormalHuge" }, path = "Fonts\\skurri.ttf", stem = "skurri" },
}

local function locale() return type(GetLocale) == "function" and GetLocale() or "enUS" end

local function lower(s) return (tostring(s):lower()) end

local function normPath(p) return (tostring(p):lower():gsub("/", "\\")) end

-- Eintraege nach Name (exakt, dann ohne Gross-/Kleinschreibung)
local byName, byLower = {}, {}
for _, e in ipairs(Fonts.BUNDLED) do
    e.kind, e.path = "bundled", DIR .. e.file
    byName[e.name], byLower[lower(e.name)] = e, e
end
for _, e in ipairs(Fonts.BLIZZARD) do
    e.kind = "blizzard"
    byName[e.name], byLower[lower(e.name)] = e, e
end

-- Eingabepruefung ----------------------------------------------------------------------------------------------------
--- gueltiger Schrift-/LSM-Name: String, 1 bis 64 Byte, ohne "|" und Steuerzeichen
function Fonts.ValidName(s)
    return type(s) == "string" and #s >= 1 and #s <= Fonts.MAX_NAME and not s:find("|", 1, true) and not s:find("%c") and true or false
end

local function validSize(v)
    if type(v) ~= "number" or v ~= v or v ~= math.floor(v) then return false end
    return v == 0 or (v >= Fonts.SIZE.min and v <= Fonts.SIZE.max)
end

local function defaultSpec() return { face = Fonts.DEFAULT, size = 0, outline = "none", shadow = true } end

--- Standard des Bereichs: alle fuenf Elemente wie die heutige Optik
function Fonts.Defaults()
    local out = {}
    for _, e in ipairs(Fonts.ELEMENTS) do out[e] = defaultSpec() end
    return out
end

--- Bereich pruefen (Vertrag RegisterArea): vollstaendige bereinigte Kopie; ein ungueltiges Feld faellt auf seinen Standard zurueck,
--- Unbekanntes faellt weg. nil nur, wenn kein Bereich (Tabelle) vorliegt.
function Fonts.Validate(t)
    if type(t) ~= "table" then return nil end
    local out = Fonts.Defaults()
    for _, e in ipairs(Fonts.ELEMENTS) do
        local v, d = t[e], out[e]
        if type(v) == "table" then
            if Fonts.ValidName(v.face) then d.face = v.face end
            if validSize(v.size) then d.size = v.size end
            if type(v.outline) == "string" and FLAGS[v.outline] then d.outline = v.outline end
            if type(v.shadow) == "boolean" then d.shadow = v.shadow end
        end
    end
    return out
end

-- LibSharedMedia (nur lesen) -------------------------------------------------------------------------------------------
local lsm, lsmHooked, listCache = nil, false, nil

local function findLSM()
    local ls = _G.LibStub
    if ls == nil then return nil end
    local ok, lib = pcall(ls, "LibSharedMedia-3.0", true)
    if ok and type(lib) == "table" then return lib end
    return nil
end

--- Rueckruf von LSM (wenn ein Addon eine Schrift neu anmeldet): Liste beim naechsten Lesen neu bauen
function Fonts:OnLsmRegistered(_, mediaType)
    if mediaType == nil or mediaType == "font" then listCache = nil end
end

--- LSM spaet suchen (PLAYER_LOGIN, Lesen der Liste): LSM kann nach uns geladen werden
function Fonts.RefreshLSM()
    local lib = findLSM()
    if lib ~= lsm then listCache = nil end
    lsm = lib
    if lsm and not lsmHooked and type(lsm.RegisterCallback) == "function" then
        lsmHooked = pcall(lsm.RegisterCallback, Fonts, "LibSharedMedia_Registered", "OnLsmRegistered") == true
    elseif not lsm then
        lsmHooked = false
    end
    return lsm ~= nil
end

local function lsmPath(name)
    local lib = lsm or findLSM()
    if not (lib and type(lib.Fetch) == "function") then return nil end
    local ok, p = pcall(lib.Fetch, lib, "font", name, true)
    if ok and type(p) == "string" and p ~= "" then return p end
    return nil
end

-- Aufloesung --------------------------------------------------------------------------------------------------------------
local function clientFont()
    if Style.ClientFont then return Style.ClientFont() end
    return _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function nonLatin() return Style.NON_LATIN and Style.NON_LATIN[locale()] == true end

local function blizzardPath(e)
    for _, objName in ipairs(e.objects) do
        local obj = _G[objName]
        local fn = type(obj) == "table" and obj.GetFont
        if type(fn) == "function" then
            local ok, p = pcall(fn, obj)
            if ok and type(p) == "string" and p ~= "" then
                -- lateinische Clients: nur die erwartete Datei (schuetzt vor einem falsch geratenen Font-Objekt);
                -- andere Sprachen: die Sprachdatei des Objekts behalten
                if nonLatin() or lower(p):find(e.stem, 1, true) then return p end
            end
        end
    end
    return e.path
end

local function entryPath(e)
    if e.kind == "blizzard" then return blizzardPath(e) end
    if nonLatin() and not (e.cyrillic and locale() == "ruRU") then return clientFont() end
    return e.path
end

local function lookup(name)
    if type(name) ~= "string" then return nil end
    return byName[name] or byLower[lower(name)]
end

--- Pfad zu einem Schriftnamen. Liefert pfad, bekannt (false = unbekannter Name, der Pfad ist dann Marcellus), eintrag.
--- Unbekannte oder ungueltige Namen zeigen Marcellus; Marcellus selbst folgt der Regel fuer nicht-lateinische Clients.
function Fonts.Resolve(name)
    local e = lookup(name)
    if e then return entryPath(e), true, e end
    if Fonts.ValidName(name) then
        local p = lsmPath(name)
        if p then
            if nonLatin() then p = clientFont() end -- Zeichenabdeckung fremder Schriften ist nicht lesbar: Client-Schrift
            return p, true, { name = name, kind = "lsm", path = p }
        end
    end
    return entryPath(byName[Fonts.DEFAULT]), false, nil
end

--- Schriftliste fuer die Auswahl: { { name, kind = "bundled"|"blizzard"|"lsm" }, ... }; mitgeliefert zuerst (Marcellus vorn),
--- dann Blizzard, dann LSM-Schriften alphabetisch (ohne Doppelte: gleicher Name oder dieselbe Blizzard-Datei)
function Fonts.List()
    Fonts.RefreshLSM()
    if listCache then return listCache end
    local out, seen, fixed = {}, {}, {}
    for _, e in ipairs(Fonts.BUNDLED) do
        out[#out + 1] = { name = e.name, kind = "bundled" }
        seen[lower(e.name)] = true
    end
    for _, e in ipairs(Fonts.BLIZZARD) do
        out[#out + 1] = { name = e.name, kind = "blizzard" }
        seen[lower(e.name)] = true
        fixed[normPath(e.path)] = true
    end
    if lsm and type(lsm.List) == "function" then
        local ok, names = pcall(lsm.List, lsm, "font")
        if ok and type(names) == "table" then
            local extra = {}
            for _, n in ipairs(names) do
                if Fonts.ValidName(n) and not seen[lower(n)] then
                    local p = lsmPath(n)
                    if p and not fixed[normPath(p)] then
                        seen[lower(n)] = true
                        extra[#extra + 1] = n
                    end
                end
            end
            table.sort(extra, function(a, b) return lower(a) < lower(b) end)
            for _, n in ipairs(extra) do out[#out + 1] = { name = n, kind = "lsm" } end
        end
    end
    listCache = out
    return out
end

--- true, wenn der Name eine bekannte Schrift ist (sonst zeigt die Anzeige Marcellus)
function Fonts.IsKnown(name)
    local _, known = Fonts.Resolve(name)
    return known
end

-- Anwenden ------------------------------------------------------------------------------------------------------------------
--- Wirksame Einstellung eines Elements fuer einen Rahmen ("player"|"target"|"tot", "xp" oder nil = fuer alle): geprueft, nie nil
function Fonts.Spec(element, frameId)
    if not ELEMENT_SET[element] then return nil end
    local Skin = ns.UnitFrameSkin
    local area
    if Skin and type(Skin.GetFrameConfig) == "function" then
        local ok, cfg = pcall(Skin.GetFrameConfig, frameId)
        if ok and type(cfg) == "table" then area = cfg.font end
    end
    local clean = Fonts.Validate({ [element] = type(area) == "table" and area[element] or nil })
    return clean[element]
end

local function trySetFont(fs, path, size, flags)
    if type(path) ~= "string" or path == "" then return false end
    local ok, r = pcall(fs.SetFont, fs, path, size, flags)
    return ok and r ~= false -- ohne Rueckgabe (aeltere Clients) gilt es als gelungen
end

local function setShadow(fs, on)
    local S = Fonts.SHADOW
    if fs.SetShadowColor then
        if on then pcall(fs.SetShadowColor, fs, S[1], S[2], S[3], S[4]) else pcall(fs.SetShadowColor, fs, 0, 0, 0, 0) end
    end
    if fs.SetShadowOffset then
        if on then pcall(fs.SetShadowOffset, fs, S[5], S[6]) else pcall(fs.SetShadowOffset, fs, 0, 0) end
    end
end

--- Schrift setzen mit Rueckfall: gewaehlte Schrift -> Marcellus -> Client-Schrift. Liefert true, wenn eine Schrift gesetzt wurde,
--- und den benutzten Pfad.
local function applySpec(fs, spec, size)
    if type(fs) ~= "table" or type(fs.SetFont) ~= "function" then return false end
    local flags = FLAGS[spec.outline] or ""
    local path = Fonts.Resolve(spec.face)
    local used
    if trySetFont(fs, path, size, flags) then
        used = path
    else
        local marcellus = entryPath(byName[Fonts.DEFAULT])
        if marcellus ~= path and trySetFont(fs, marcellus, size, flags) then
            used = marcellus
        elseif trySetFont(fs, clientFont(), size, flags) then
            used = clientFont()
        end
    end
    setShadow(fs, spec.shadow)
    return used ~= nil, used
end

--- Schrift, Groesse, Kontur und Schatten eines Textelements auf einen FontString anwenden. frameId: "player"|"target"|"tot"|"xp"
--- oder nil (fuer alle). autoSize: Groesse, wenn das Element auf Auto steht (heutige Groesse des Aufrufers).
function Fonts.Apply(fs, element, frameId, autoSize)
    local spec = Fonts.Spec(element, frameId)
    if not spec then return false end
    local size = spec.size
    if size == 0 then size = tonumber(autoSize) or Fonts.AUTO_SIZE[element] end
    return applySpec(fs, spec, size)
end

--- Feste Standard-Optik (Marcellus, ohne Kontur, Tintenschatten) fuer Texte ohne eigene Einstellung (Aura-Zaehler, Stufe im Stein)
function Fonts.ApplyDefault(fs, size)
    return applySpec(fs, defaultSpec(), size)
end

-- Anmeldung ---------------------------------------------------------------------------------------------------------------------
ns.UnitFrameSkin.RegisterArea("font", { defaults = Fonts.Defaults, validate = Fonts.Validate })

ns.On("PLAYER_LOGIN", function() Fonts.RefreshLSM() end)

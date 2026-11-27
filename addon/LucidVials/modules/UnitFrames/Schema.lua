-- Profil-Schema der Einheitenrahmen (Schema 2, Ausbau 1.1.0 K1): Abschnitt "unitframes" mit Bereichen, die einen Wert
-- "fuer alle" und optional einen Eigenwert je Rahmen haben. Reine Daten-Logik ohne Frames; Skin.lua reicht die Funktionen
-- als Skin.Defaults/Validate/RegisterArea/GetConfig/Set/SetOverride/HasOverride nach aussen.
--
-- Aufbau:  { enabled, frames = { player, target, tot }, xp, auraSize,
--            liquid = {...}, text = {...}, font = {...}, portrait = {...},          -- "fuer alle"
--            per = { player = { <bereich> = {...} }, target = ..., tot = ... } }   -- Eigenwert je Rahmen (fehlt = erbt)
--
--   * Eigenwerte gibt es je Bereich als Block: SetOverride(an) kopiert die "fuer alle"-Werte, SetOverride(aus) loescht ihn.
--   * Pruefung feldweise: ein ungueltiges Feld faellt auf seinen Standard zurueck, nie der ganze Abschnitt.
--   * Bereiche melden ihre Module per RegisterArea an (liquid hier, font/text/portrait in ihren Modulen). Ein Vertrags-Bereich
--     ohne Anmeldung (Modul fehlt) wird unveraendert durchgereicht, andere unbekannte Felder fallen weg.
--   * Globale Felder eines Bereichs (liquid.slosh*: die Bewegungsphysik ist eine fuer alle Roehren) kommen immer aus "fuer alle".
--   * Das Element "xp" (text/font) gibt es nur unter "fuer alle"; Portrait-Eigenwerte nur fuer Spieler und Ziel.
local _, ns = ...
local Store = ns.Store

local Schema = {}
ns.UnitFrameSchema = Schema

Schema.FRAMES = { "player", "target", "tot" }
local FRAME_SET = { player = true, target = true, tot = true }
Schema.FRAME_SET = FRAME_SET
-- Bereiche aus dem Vertrag (werden ohne Anmeldung durchgereicht), in dieser Reihenfolge
Schema.CONTRACT_AREAS = { liquid = true, text = true, font = true, portrait = true }
-- Rahmen mit Eigenwert je Bereich (fehlt = alle drei); das Ziel des Ziels hat immer das statische Portrait
Schema.AREA_FRAMES = { portrait = { player = true, target = true } }
Schema.SHARED_ELEMENT = "xp" -- text/font-Element, das nur "fuer alle" gilt (die XP-Roehre ist kein Rahmen)
-- Felder auf oberster Ebene, die keine Bereiche sind
local RESERVED = { enabled = true, frames = true, xp = true, auraSize = true, per = true }

-- Auren-Groesse am Ziel (unitframes.auraSize, ganze Pixel/UI-Einheiten; Deco.lua legt Knoepfe, Abstaende und Reihen danach aus)
Schema.AURA_SIZE = { default = 22, min = 14, max = 36 }

local copy = Store.DeepCopy

-- Bereiche ----------------------------------------------------------------------------------------------------------------
local areas, areaOrder = {}, {}

local function toSet(list)
    if type(list) ~= "table" then return nil end
    local s = {}
    for k, v in pairs(list) do
        if type(k) == "number" then s[v] = true elseif v then s[k] = true end
    end
    return s
end

--- Bereich anmelden: def.defaults() -> vollstaendige Tabelle, def.validate(t) -> bereinigte Kopie (feldweise, optional
--- zweite Rueckgabe = erstes ungueltiges Feld) oder nil. Optional def.frames (Rahmen mit Eigenwert, Liste oder Menge) und
--- def.global (Felder, die immer "fuer alle" gelten).
function Schema.RegisterArea(name, def)
    assert(type(name) == "string" and name:match("^%a%w*$") and not RESERVED[name] and not areas[name],
        "LucidVials: Bereich fehlt, ist reserviert oder doppelt: " .. tostring(name))
    assert(type(def) == "table" and type(def.defaults) == "function" and type(def.validate) == "function",
        "LucidVials: Bereich braucht defaults und validate: " .. name)
    areas[name] = { defaults = def.defaults, validate = def.validate,
        frames = toSet(def.frames) or Schema.AREA_FRAMES[name], global = toSet(def.global) or {} }
    areaOrder[#areaOrder + 1] = name
end

function Schema.IsArea(name) return areas[name] ~= nil end

local function knownArea(name) return areas[name] ~= nil or Schema.CONTRACT_AREAS[name] == true end

--- darf der Rahmen fuer den Bereich einen Eigenwert haben?
local function frameAllowed(area, frameId)
    if not FRAME_SET[frameId] or not knownArea(area) then return false end
    local set = (areas[area] and areas[area].frames) or Schema.AREA_FRAMES[area]
    return set == nil or set[frameId] == true
end
Schema.FrameAllowed = frameAllowed

local function isGlobal(area, fieldName)
    local a = areas[area]
    return a ~= nil and a.global[fieldName] == true
end
Schema.IsGlobal = isGlobal

--- Bereich pruefen: bereinigte Tabelle (nie nil) und ggf. das erste ungueltige Feld
local function checkArea(name, v)
    local a = areas[name]
    if type(v) ~= "table" then return a.defaults(), "" end
    local ok, res, detail = pcall(a.validate, v)
    if not ok or type(res) ~= "table" then return a.defaults(), "" end
    return res, detail
end

-- Fluessigkeit ------------------------------------------------------------------------------------------------------------
-- Felder: "bool", "unit" (Zahl 0..1) oder "style" (Darstellung "edge" = Fluessigkeitskante, "piston" = Kolben-Kammer).
-- style/smooth/trail/fx/debuffs je Rahmen, slosh* global (Bewegungsphysik), regenPulse global (nur die eigene Mana-Roehre:
-- Impuls beim Einsetzen der Regeneration nach der 5-Sekunden-Regel, Standard aus).
Schema.STYLES = { edge = true, piston = true }
local LIQUID_KEYS = { smooth = "bool", trail = "bool", slosh = "bool", sloshStrength = "unit", sloshDamping = "unit",
    style = "style", fx = "bool", debuffs = "bool", regenPulse = "bool" }

function Schema.LiquidDefaults()
    return { smooth = true, trail = true, slosh = true, sloshStrength = 0.6, sloshDamping = 0.4, style = "piston",
        fx = true, debuffs = true, regenPulse = false }
end

local function validLiquid(kind, v)
    if kind == "bool" then return type(v) == "boolean" end
    if kind == "style" then return type(v) == "string" and Schema.STYLES[v] == true end
    return type(v) == "number" and v == v and v >= 0 and v <= 1
end

--- Fluessigkeit feldweise pruefen: ungueltige Felder bekommen ihren Standard, unbekannte fallen weg
function Schema.ValidateLiquid(t)
    local out, bad = Schema.LiquidDefaults(), nil
    for k, v in pairs(t) do
        local kind = LIQUID_KEYS[k]
        if kind then
            if validLiquid(kind, v) then out[k] = v elseif not bad then bad = tostring(k) end
        end
    end
    return out, bad
end

Schema.RegisterArea("liquid", { defaults = Schema.LiquidDefaults, validate = Schema.ValidateLiquid,
    global = { "slosh", "sloshStrength", "sloshDamping", "regenPulse" } })

-- Abschnitt ---------------------------------------------------------------------------------------------------------------
function Schema.Defaults()
    local out = { enabled = true, frames = { player = true, target = true, tot = true }, xp = true,
        auraSize = Schema.AURA_SIZE.default }
    for _, name in ipairs(areaOrder) do out[name] = areas[name].defaults() end
    return out
end

--- Eigenwerte pruefen: { [rahmen] = { [bereich] = block } } oder nil (leer), erstes ungueltiges Feld
local function validatePer(x)
    if type(x) ~= "table" then return nil, "per" end
    local per, bad = nil, nil
    for fid, blocks in pairs(x) do
        if FRAME_SET[fid] and type(blocks) == "table" then
            for area, block in pairs(blocks) do
                if type(area) == "string" and frameAllowed(area, fid) and type(block) == "table" then
                    local clean, detail
                    if areas[area] then clean, detail = checkArea(area, block) else clean = copy(block) end
                    clean[Schema.SHARED_ELEMENT] = nil -- xp gilt nur "fuer alle"
                    if detail and not bad then bad = "per." .. fid .. "." .. area .. (detail ~= "" and ("." .. detail) or "") end
                    per = per or {}
                    per[fid] = per[fid] or {}
                    per[fid][area] = clean
                end -- verbotener Rahmen (z. B. per.tot.portrait) oder unbekannter Bereich: verworfen
            end
        end
    end
    return per, bad
end

--- Abschnitt "unitframes" feldweise pruefen: vollstaendige bereinigte Kopie und das erste ungueltige Feld (nil = alles gut).
--- Nur ein Nicht-Table liefert nil, "type".
function Schema.Validate(v)
    if type(v) ~= "table" then return nil, "type" end
    local out, bad = Schema.Defaults(), nil
    local function mark(k) if not bad then bad = k end end
    for k, x in pairs(v) do
        if k == "enabled" or k == "xp" then -- xp: Erfahrungsleiste als Roehre (XP.lua)
            if type(x) == "boolean" then out[k] = x else mark(k) end
        elseif k == "auraSize" then
            local R = Schema.AURA_SIZE
            if type(x) == "number" and x == x and x == math.floor(x) and x >= R.min and x <= R.max then out[k] = x else mark(k) end
        elseif k == "frames" then
            if type(x) ~= "table" then
                mark(k)
            else
                for fk, fv in pairs(x) do
                    if FRAME_SET[fk] then
                        if type(fv) == "boolean" then out.frames[fk] = fv else mark(k .. "." .. tostring(fk)) end
                    end -- unbekannte Rahmen fallen weg
                end
            end
        elseif k == "per" then
            local per, d = validatePer(x)
            out.per = per
            if d then mark(d) end
        elseif type(k) == "string" and areas[k] then
            local clean, d = checkArea(k, x)
            out[k] = clean
            if d then mark(k .. (d ~= "" and ("." .. d) or "")) end
        elseif type(k) == "string" and Schema.CONTRACT_AREAS[k] and type(x) == "table" then
            out[k] = copy(x) -- Bereich ohne Anmeldung (Modul fehlt): unveraendert durchreichen
        end -- unbekannte Felder fallen weg
    end
    return out, bad
end

--- wirksame Werte fuer einen Rahmen (frameId nil, "xp" oder unbekannt = "fuer alle"). Liefert c selbst, wenn der Rahmen
--- keine Eigenwerte hat, sonst eine flache Kopie mit den Bloecken des Rahmens (globale Felder aus "fuer alle").
function Schema.Resolve(c, frameId)
    if type(c) ~= "table" or not FRAME_SET[frameId] then return c end
    local own = type(c.per) == "table" and c.per[frameId] or nil
    if type(own) ~= "table" or next(own) == nil then return c end
    local r = {}
    for k, x in pairs(c) do r[k] = x end
    for area, block in pairs(own) do
        local merged = block
        local a = areas[area]
        local all = c[area]
        local shared = type(all) == "table" and all[Schema.SHARED_ELEMENT] or nil
        if type(all) == "table" and ((a and next(a.global) ~= nil) or shared ~= nil) then
            merged = {}
            for k, x in pairs(block) do merged[k] = x end
            if a then for f in pairs(a.global) do merged[f] = all[f] end end
            merged[Schema.SHARED_ELEMENT] = shared -- Element xp immer aus "fuer alle"
        end
        r[area] = merged
    end
    return r
end

local function splitPath(path)
    if type(path) ~= "string" or path == "" or path:find("^%.") or path:find("%.$") or path:find("%.%.") then return nil end
    local parts = {}
    for s in path:gmatch("[^%.]+") do parts[#parts + 1] = s end
    if #parts > 3 then return nil end
    return parts
end

--- Feld setzen auf einer Kopie von stored. path = "feld", "bereich.feld" oder "bereich.element.feld"; nur Skalare.
--- frameId nil = "fuer alle", sonst Eigenwert (nur wenn der Rahmen fuer den Bereich einen Eigenwert hat; keine globalen
--- Felder, kein Element "xp"). Liefert die bereinigte neue Fassung und den Bereich (oder nil), sonst nil.
function Schema.Apply(stored, path, value, frameId)
    local parts = splitPath(path)
    local tv = type(value)
    if not parts or not (tv == "boolean" or tv == "number" or tv == "string") then return nil end
    local area = parts[1]
    local cand = type(stored) == "table" and (Schema.Validate(stored)) or Schema.Defaults()
    local target, from = cand, 1
    if frameId ~= nil then
        if not areas[area] or #parts < 2 or not frameAllowed(area, frameId) or isGlobal(area, parts[2]) then return nil end
        if #parts == 3 and parts[2] == Schema.SHARED_ELEMENT then return nil end
        local own = cand.per and cand.per[frameId] and cand.per[frameId][area]
        if type(own) ~= "table" then return nil end -- kein Eigenwert: erst SetOverride
        target, from = own, 2
    elseif area == "per" or (#parts > 1 and not RESERVED[area] and not areas[area]) then
        return nil -- Eigenwerte nur ueber frameId; Bereich ohne Modul ist nicht pruefbar
    end
    local t = target
    for i = from, #parts - 1 do
        if type(t[parts[i]]) ~= "table" then t[parts[i]] = {} end
        t = t[parts[i]]
    end
    t[parts[#parts]] = value
    local clean = Schema.Validate(cand)
    if not clean then return nil end
    -- feldweise Pruefung: der gesetzte Wert muss die Bereinigung ueberstehen (sonst ungueltig oder unbekanntes Feld)
    local chk = clean
    if frameId ~= nil then chk = clean.per and clean.per[frameId] and clean.per[frameId][area] end
    for i = from, #parts do
        if type(chk) ~= "table" then return nil end
        chk = chk[parts[i]]
    end
    if chk ~= value then return nil end
    return clean, knownArea(area) and area or nil
end

--- Eigenwert eines Bereichs an (Kopie der "fuer alle"-Werte; ist er schon an, bleibt er) oder aus (Block geloescht).
--- Liefert die bereinigte neue Fassung oder nil (unbekannter Rahmen/Bereich, Rahmen ohne Eigenwert fuer den Bereich).
function Schema.Override(stored, frameId, area, on)
    if not areas[area] or not frameAllowed(area, frameId) then return nil end
    local cand = type(stored) == "table" and (Schema.Validate(stored)) or Schema.Defaults()
    local per = cand.per or {}
    if on then
        per[frameId] = per[frameId] or {}
        if type(per[frameId][area]) ~= "table" then
            local block = copy(cand[area])
            block[Schema.SHARED_ELEMENT] = nil -- xp gilt nur "fuer alle"
            per[frameId][area] = block
        end
    elseif per[frameId] then
        per[frameId][area] = nil
        if next(per[frameId]) == nil then per[frameId] = nil end
    end
    cand.per = next(per) ~= nil and per or nil
    return cand
end

--- hat der Rahmen fuer den Bereich einen Eigenwert?
function Schema.HasOverride(stored, frameId, area)
    if type(stored) ~= "table" or type(stored.per) ~= "table" or not frameAllowed(area, frameId) then return false end
    local own = stored.per[frameId]
    return type(own) == "table" and type(own[area]) == "table"
end

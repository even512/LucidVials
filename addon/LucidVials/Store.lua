-- Store: LucidVialsDB (SavedVariables) mit Profilen und Schema-Version. Schlanke Kopie des Lucid-Stores (ohne Export/Import
-- und ohne Charakter-Daten); der Aufbau ist derselbe, damit die Rahmen-Module unveraendert bleiben.
--
-- Aufbau:  LucidVialsDB.schema               Schema-Version der Datenbank
--          LucidVialsDB.profiles[name]       Profilinhalt; Abschnitte (z. B. "unitframes") melden Module per RegisterSection an
--          LucidVialsDB.charProfile["Realm-Char"] = name   abweichendes Profil je Charakter (fehlt => "Default")
--          LucidVialsDB.dispelIds            gelernte Dispel-Typ-IDs (LiquidFx.lua, global, kein Profilinhalt)
--          LucidVialsDB.configPos            Position des Einstellungsfensters (UI/Config.lua)
local _, ns = ...
local L = ns.L

local Store = {}
ns.Store = Store

Store.SCHEMA = 1            -- aktuelle Schema-Version (DB und Profilinhalt)
Store.DEFAULT = "Default"
Store.NAME_MAX = 48         -- Bytes

-- Migrationen: migrations[n] hebt die DB von n-1 auf n, profileMigrations[n] einen Profilinhalt.
Store.migrations = {
    [1] = function(db)
        if type(db.profiles) ~= "table" then db.profiles = {} end
        if type(db.charProfile) ~= "table" then db.charProfile = {} end
    end,
}
Store.profileMigrations = {}

-- Abschnitte ------------------------------------------------------------------------------------
local sections, sectionOrder = {}, {}

--- Abschnitt im Profil anmelden. def.default() liefert den Startwert,
--- def.validate(v) liefert eine bereinigte Kopie oder nil, Detail.
function Store.RegisterSection(key, def)
    assert(type(key) == "string" and not sections[key], "LucidVials: Abschnitt fehlt oder doppelt: " .. tostring(key))
    assert(type(def) == "table" and type(def.default) == "function" and type(def.validate) == "function",
        "LucidVials: Abschnitt braucht default und validate: " .. key)
    sections[key] = def
    sectionOrder[#sectionOrder + 1] = key
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deepCopy(x) end
    return t
end
Store.DeepCopy = deepCopy

--- neues Profil mit den Startwerten aller Abschnitte
function Store.NewProfile()
    local p = {}
    for _, key in ipairs(sectionOrder) do p[key] = sections[key].default() end
    return p
end

--- Profilinhalt gegen alle Abschnitte pruefen. Unbekannte Abschnitte fallen weg, fehlende bekommen
--- den Startwert. Liefert bereinigte Kopie oder nil, "PROFILE_INVALID", Detail.
function Store.SanitizeProfile(data)
    if type(data) ~= "table" then return nil, "PROFILE_INVALID", "profile" end
    local clean = {}
    for _, key in ipairs(sectionOrder) do
        local v = data[key]
        if v == nil then
            clean[key] = sections[key].default()
        else
            local ok, res, detail = pcall(sections[key].validate, v)
            if not ok or res == nil then return nil, "PROFILE_INVALID", key .. (detail and ("." .. detail) or "") end
            clean[key] = res
        end
    end
    return clean
end

-- Namen ------------------------------------------------------------------------------------------
--- gueltiger Profilname (getrimmt) oder nil. Keine Steuerzeichen, kein "|" (Escape-Zeichen im Chat).
function Store.ValidName(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" or #name > Store.NAME_MAX or name:find("[%c|]") then return nil end
    return name
end

local function charKey()
    local n, r = UnitName and UnitName("player"), GetRealmName and GetRealmName()
    if type(n) ~= "string" or type(r) ~= "string" then return nil end
    return r .. "-" .. n
end
Store.CharKey = charKey

-- Callbacks: fn(reason) bei Wechsel oder Neuinhalt des aktiven Profils ------------------------
local callbacks = {}
function Store.RegisterCallback(fn) callbacks[#callbacks + 1] = fn end
local function notify(reason)
    for _, fn in ipairs(callbacks) do xpcall(function() fn(reason) end, geterrorhandler()) end
end

-- Laden + Migration ------------------------------------------------------------------------------
local db

--- DB vorbereiten (bei ADDON_LOADED): migrieren und Struktur reparieren, ohne Fremdes zu loeschen.
function Store.Init(raw)
    db = raw
    local from = tonumber(db.schema) or 0
    if from > Store.SCHEMA then
        -- von einer neueren Version gespeichert: nichts umbauen, nur das Noetigste sicherstellen
        ns.Print(L.DB_NEWER)
    else
        for n = from + 1, Store.SCHEMA do
            if Store.migrations[n] then Store.migrations[n](db) end
            if Store.profileMigrations[n] and type(db.profiles) == "table" then
                for _, p in pairs(db.profiles) do
                    if type(p) == "table" then Store.profileMigrations[n](p) end
                end
            end
        end
        db.schema = Store.SCHEMA
    end
    if type(db.profiles) ~= "table" then db.profiles = {} end
    if type(db.charProfile) ~= "table" then db.charProfile = {} end
    for name, p in pairs(db.profiles) do
        if type(name) ~= "string" or type(p) ~= "table" or Store.ValidName(name) ~= name then
            db.profiles[name] = nil   -- unzulaessiger Name (Steuerzeichen, "|", zu lang, unsauber getrimmt): verwerfen
        end
    end
    if not db.profiles[Store.DEFAULT] then db.profiles[Store.DEFAULT] = Store.NewProfile() end
    for _, p in pairs(db.profiles) do
        for _, key in ipairs(sectionOrder) do
            if p[key] == nil then p[key] = sections[key].default() end
        end
    end
    for key, name in pairs(db.charProfile) do
        if type(name) ~= "string" or not db.profiles[name] then db.charProfile[key] = nil end
    end
    Store.db = db
    return db
end

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ns.name then return end
    if type(ns.db) ~= "table" then
        if type(LucidVialsDB) ~= "table" then LucidVialsDB = {} end
        ns.db = LucidVialsDB
    end
    Store.Init(ns.db)
end)

local function requireDb()
    assert(db, "LucidVials: Store vor ADDON_LOADED benutzt")
    return db
end

-- Profile ----------------------------------------------------------------------------------------
function Store.GetActiveName()
    local d = requireDb()
    local key = charKey()
    local name = key and d.charProfile[key]
    if name and d.profiles[name] then return name end
    return Store.DEFAULT
end

function Store.GetActive()
    return requireDb().profiles[Store.GetActiveName()]
end

function Store.GetProfile(name)
    return requireDb().profiles[name]
end

--- Profil auf die Startwerte zuruecksetzen (Tabelle bleibt dieselbe, Verweise bleiben gueltig)
function Store.ResetProfile(name)
    local d = requireDb()
    local p = d.profiles[name]
    if not p then return nil, "PROFILE_NOT_FOUND" end
    for k in pairs(p) do p[k] = nil end
    for k, v in pairs(Store.NewProfile()) do p[k] = v end
    if Store.GetActiveName() == name then notify("reset") end
    return true
end

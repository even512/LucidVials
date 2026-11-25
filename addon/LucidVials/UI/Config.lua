-- Einstellungsfenster: eigenes, ungeschuetztes Fenster (Grundgeruest aus Lucid, ohne Reiterleiste und Zustands-Simulation).
-- /vials config oeffnet bzw. schliesst es, ESC schliesst es (UISpecialFrames), verschiebbar, Position im DB
-- (LucidVialsDB.configPos). Inhalt meldet sich per Config.RegisterPage an (UI/ConfigFrames.lua) und wird beim ersten Oeffnen
-- gebaut (kein Aufwand beim Login). Alle Aenderungen laufen ueber die Modul-APIs (Skin.Set) und wirken sofort.
--
-- Taint/Kampf: das Fenster darf im Kampf offen sein und bedient werden. Es fasst selbst keine Blizzard-Frames an.
local _, ns = ...
local Store = ns.Store
local W = ns.Widgets
local L = ns.L
local C = W.COLORS

local Config = {}
ns.Config = Config

Config.FRAME_NAME = "LucidVialsConfigFrame"
Config.WIDTH, Config.HEIGHT = 800, 590
Config.pages, Config.pageOrder = {}, {}

local frame

--- Seite anmelden. def = { label = Locale-Schluessel, build = function(page), refresh = function(page), onClose = function(page) }
function Config.RegisterPage(id, def)
    assert(type(id) == "string" and not Config.pages[id], "LucidVials: Seite fehlt oder doppelt: " .. tostring(id))
    def.id = id
    Config.pages[id] = def
    Config.pageOrder[#Config.pageOrder + 1] = id
end

-- Position --------------------------------------------------------------------------------------------
local POINTS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}
local function finite(v) return type(v) == "number" and v == v and v > -10000 and v < 10000 end

local function savePosition()
    local db = Store.db
    if not (db and frame and frame.GetPoint) then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if POINTS[point] and POINTS[relPoint] and finite(x) and finite(y) then
        db.configPos = { point = point, relPoint = relPoint, x = x, y = y }
    end
end

local function restorePosition()
    frame:ClearAllPoints()
    local p = Store.db and Store.db.configPos
    if type(p) == "table" and POINTS[p.point] and POINTS[p.relPoint] and finite(p.x) and finite(p.y) then
        frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end
Config.RestorePosition = function() if frame then restorePosition() end end

-- Seiten -----------------------------------------------------------------------------------------------
--- Seite zeigen (es gibt derzeit nur "frames"; die Funktion bleibt fuer weitere Seiten)
function Config.SelectTab(id)
    if not frame or not Config.pages[id] then return false end
    Config.current = id
    for pid, def in pairs(Config.pages) do
        if pid == id then def.page:Show() else def.page:Hide() end
    end
    Config.Refresh()
    return true
end

--- aktuelle Seite (bzw. alle mit all = true) aus dem Profil neu zeichnen
function Config.Refresh(all)
    if not frame then return end
    for id, def in pairs(Config.pages) do
        if (all or id == Config.current) and def.refresh then
            xpcall(def.refresh, geterrorhandler(), def.page)
        end
    end
end

-- Aufbau ---------------------------------------------------------------------------------------------
local function build()
    frame = CreateFrame("Frame", Config.FRAME_NAME, UIParent)
    Config.frame = frame
    frame:SetSize(Config.WIDTH, Config.HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    W.Fill(frame, C.bg)
    W.Border(frame, { C.accent[1], C.accent[2], C.accent[3], 0.35 })

    -- Kopf: Name, Leitidee, Schliessen
    local title = W.Text(frame, "GameFontNormalLarge", C.accent)
    title:SetPoint("TOPLEFT", 20, -16)
    title:SetText(ns.title)
    frame.title = title
    local tagline = W.Text(frame, "GameFontHighlightSmall", C.muted)
    tagline:SetPoint("LEFT", title, "RIGHT", 10, -1)
    tagline:SetText(L.UI_TAGLINE)
    frame.tagline = tagline

    local ok, close = pcall(CreateFrame, "Button", nil, frame, "UIPanelCloseButton")
    if not ok or not close then
        close = W.Button(frame, "X", 24)
    end
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() Config.Close() end)
    frame.close = close

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4])
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 12, -44)
    rule:SetPoint("TOPRIGHT", -12, -44)

    for _, id in ipairs(Config.pageOrder) do
        local def = Config.pages[id]
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", 16, -56)
        page:SetPoint("BOTTOMRIGHT", -16, 16)
        page:Hide()
        def.page = page
        def.build(page)
    end

    -- Schliessen beendet laufende Vorschau-Tests der Seiten
    frame:SetScript("OnHide", function()
        for _, def in pairs(Config.pages) do
            if def.onClose then xpcall(def.onClose, geterrorhandler(), def.page) end
        end
    end)
    frame:SetScript("OnShow", function() Config.Refresh() end)

    -- ESC schliesst das Fenster (Liste des Clients, nur ein Eintrag mit unserem Namen)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Config.FRAME_NAME) end

    restorePosition()
    frame:Hide()
    Config.SelectTab(Config.pageOrder[1])
end

function Config.IsShown() return frame ~= nil and frame:IsShown() == true end

function Config.Open(tab)
    if not frame then build() end
    if tab then Config.SelectTab(tab) end
    frame:Show()
    if frame.Raise then frame:Raise() end
end

function Config.Close()
    if frame then frame:Hide() end
end

function Config.Toggle()
    if Config.IsShown() then Config.Close() else Config.Open() end
end

-- Aenderungen von aussen (Profil-Reset, Slash-Befehle) ins offene Fenster uebernehmen
Store.RegisterCallback(function()
    if Config.IsShown() then Config.Refresh(true) end
end)

-- /vials config oeffnet bzw. schliesst das Fenster (Hilfezeile HELP_CONFIG steht fest in Core.lua)
ns.commands.config = function() Config.Toggle() end
ns.commands.optionen = ns.commands.config

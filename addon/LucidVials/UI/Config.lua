-- Einstellungsfenster: eigenes, ungeschuetztes Fenster mit Reiterleiste (Delta Ausbau 1.1.0, E2). Reiter: Allgemein, Fluessigkeit,
-- Portrait, Texte & Zahlen, Schrift, Profile (Seiten-Ids general, liquid, portrait, text, font, profiles); Vorschau und Tests stehen in der
-- Vorschau-Spalte rechts (UI/ConfigPreview.lua), der fruehere Reiter "Vorschau & Tests" (tests) entfaellt und oeffnet "general".
-- Jede Seite meldet sich per Config.RegisterPage an (UI/Config*.lua) und wird beim ersten Oeffnen gebaut (kein Aufwand beim Login);
-- fehlt eine Seite (Modul nicht geladen), fehlt nur ihr Reiter. Seiten haben Inhaltsbreite 740 und rollen, wenn sie hoeher sind als
-- der Inhaltsbereich. /vials config oeffnet bzw. schliesst das Fenster, /vials config <reiter> oeffnet direkt einen Reiter, ESC
-- schliesst es (UISpecialFrames), verschiebbar, Position im DB (LucidVialsDB.configPos), gewaehlter Reiter pro Sitzung gemerkt.
-- Alle Aenderungen laufen ueber die Modul-APIs (Skin.Set) und wirken sofort.
--
-- Mini-Vorschau (Anhang 4): rechts neben den Seiten steht eine feste Spalte (UI/ConfigPreview.lua, Config.PreviewPanel) mit einem Nachbau
-- des Rahmens, Schiebern und Test-Knoepfen; sie liegt nicht im Bildlauf der Seiten und fehlt nur im Reiter "profiles". Passt das
-- breite Fenster nicht auf den Bildschirm, wird es bis auf den Faktor PreviewPanel.MIN_SCALE verkleinert; wird es dafuer zu klein,
-- entfaellt die Spalte (Fenster dann wie vorher 800 breit).
--
-- Optik (Redesign nach docs/config-src/entwurf-config-v1.jpg): Flaechenkachel mit Bronzerand, Titelschild oben mittig, Reiter
-- mit Bronze-Oberkante; Teile und Widgets in UI/ConfigWidgets.lua (W.WindowSkin, W.Tab, W.SKIN).
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
Config.PAGE_WIDTH = 800 -- Fensterbreite ohne Vorschau-Spalte
Config.WIDTH, Config.HEIGHT = Config.PAGE_WIDTH, 640 -- WIDTH wird beim Bauen auf die echte Breite gesetzt (mit Spalte PAGE_WIDTH + PreviewPanel.EXTRA)
Config.CONTENT_WIDTH = 740
Config.TAB_Y, Config.TAB_HEIGHT = -50, 26
Config.CONTENT_TOP = -86
Config.TITLE_HEIGHT, Config.TITLE_RAISE, Config.TITLE_MIN_WIDTH = 34, 6, 180 -- Titelschild: Hoehe, Ueberstand ueber den Rand, Mindestbreite
Config.pages, Config.pageOrder = {}, {}

-- Alte und deutsche Bezeichnungen fuer /vials config <reiter> und Config.Open
Config.TAB_ALIASES = {
    frames = "general", rahmen = "general", allgemein = "general",
    fluessigkeit = "liquid", ["flüssigkeit"] = "liquid",
    texte = "text", zahlen = "text", ["texte&zahlen"] = "text",
    schrift = "font", vorschau = "general", test = "general", tests = "general", ["vorschau&tests"] = "general", -- Reiter entfallen
    -- (die Vorschau steht in der Spalte rechts)
    profile = "profiles", profil = "profiles",
}

local frame

--- Seite anmelden. def = { label = Locale-Schluessel, order = Zahl (10 Allgemein, 20 Fluessigkeit, 30 Portrait, 40 Texte & Zahlen,
--- 50 Schrift, 70 Profile), height = Seitenhoehe (Standard: Inhaltsbereich), build = function(page),
--- refresh = function(page), onClose = function(page), holes = function(page) -> { { x, y, w, h }, ... } (Durchsicht-Felder bei
--- "Spielwelt", Seitenkoordinaten nach unten positiv), background = function(page, modus) (Hintergrund-Wahl der Vorschau) }. page ist der Inhaltsrahmen (Breite 740) in einer Bildlauf-Flaeche.
local buildPage, layoutTabs
function Config.RegisterPage(id, def)
    assert(type(id) == "string" and not Config.pages[id], "LucidVials: Seite fehlt oder doppelt: " .. tostring(id))
    def.id = id
    def.order = tonumber(def.order) or (1000 + #Config.pageOrder)
    Config.pages[id] = def
    Config.pageOrder[#Config.pageOrder + 1] = id
    table.sort(Config.pageOrder, function(a, b)
        local oa, ob = Config.pages[a].order, Config.pages[b].order
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    -- spaet angemeldete Seite bei offenem Fenster: Reiter nachtragen
    if frame then
        buildPage(def)
        layoutTabs()
    end
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

-- Reiter ------------------------------------------------------------------------------------------------
--- Reiter-Name (Seiten-Id, alter oder deutscher Name, Gross-/Kleinschreibung egal) -> Seiten-Id einer angemeldeten Seite, sonst nil
function Config.ResolveTab(name)
    if type(name) ~= "string" then return nil end
    name = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    local id = Config.TAB_ALIASES[name] or name
    if Config.pages[id] then return id end
    return nil
end

local function paintTab(def)
    local on = Config.current == def.id
    def.tab:SetSelected(on)
    W.Color(def.tab.label, on and C.accent or C.muted) -- gewaehlt: Hellgold
    if on then def.tab.under:Show() else def.tab.under:Hide() end
end

--- Reiter zeigen (Seiten-Id oder Alias). false, wenn es die Seite nicht gibt (z. B. Modul fehlt) oder das Fenster noch nicht gebaut ist.
function Config.SelectTab(id)
    id = Config.ResolveTab(id)
    if not frame or not id then return false end
    Config.current = id
    for _, pid in ipairs(Config.pageOrder) do
        local def = Config.pages[pid]
        if def.scroll then
            if pid == id then
                def.scroll:Show()
                def.page:Show()
            else
                def.scroll:Hide()
                def.page:Hide()
            end
        end
        if def.tab then paintTab(def) end
    end
    local cur = Config.pages[id]
    if cur.scroll and cur.scroll.UpdateBar then cur.scroll.UpdateBar() end
    Config.Refresh()
    return true
end

--- aktuelle Seite (bzw. alle mit all = true) aus dem Profil neu zeichnen
function Config.Refresh(all)
    if not frame then return end
    for id, def in pairs(Config.pages) do
        if def.page and (all or id == Config.current) and def.refresh then
            xpcall(def.refresh, geterrorhandler(), def.page)
        end
    end
    -- Vorschau-Spalte an Reiter, Rahmen-Wahl und Fensterzustand anpassen (zeigt/versteckt die Buehne, schaltet ihren Treiber)
    local P = Config.PreviewPanel
    if P and Config.hasPreview and P.Sync then xpcall(P.Sync, geterrorhandler()) end
end

--- Hoehe einer Seite aendern (Inhalt waechst, z. B. weitere Knoepfe); der Bildlauf passt sich an
function Config.SetPageHeight(page, height)
    page:SetHeight(height)
    for _, def in pairs(Config.pages) do
        if def.page == page and def.scroll and def.scroll.UpdateBar then def.scroll.UpdateBar() end
    end
end

--- Hintergrund der Vorschau fuer Musterfelder der Seiten: "dark" | "light" | "world" (ohne Vorschau-Spalte immer "dark")
function Config.PreviewBackground()
    local P = Config.PreviewPanel
    if Config.hasPreview and P and P.GetBackground then return P.GetBackground() end
    return "dark"
end

--- Wahl des Rahmen-Waehlers der Seite fuer den Bereich ("liquid", "portrait", "text", "font"): Rahmen-Id oder nil (= fuer alle)
function Config.CurrentFrame(area)
    return W.scopeChoice[area]
end

-- Aufbau ---------------------------------------------------------------------------------------------
function buildPage(def)
    local contentHeight = Config.HEIGHT - 16 + Config.CONTENT_TOP
    local scroll, page = W.ScrollPage(frame, Config.CONTENT_WIDTH, tonumber(def.height) or contentHeight)
    scroll:SetPoint("TOPLEFT", 16, Config.CONTENT_TOP)
    scroll:SetPoint("BOTTOMRIGHT", -36 - (Config.hasPreview and Config.PreviewPanel.EXTRA or 0), 16)
    scroll:Hide()
    page:Hide()
    def.scroll, def.page = scroll, page
    -- Bildlauf der gezeigten Seite verschiebt ihre Durchsicht-Felder: Loecher im Fensterhintergrund neu legen (nur "Spielwelt")
    scroll.onScroll = function()
        local P = Config.PreviewPanel
        if Config.current == def.id and P and P.PaintHoles and Config.hasPreview then P.PaintHoles() end
    end
    if def.build then xpcall(def.build, geterrorhandler(), page) end

    -- Reiter: flach (tab-off), gewaehlt mit Bronze-Oberkante (tab.under, tab-on)
    local tab = W.Tab(frame, 90, Config.TAB_HEIGHT, "GameFontHighlight")
    tab.label:SetText(L[def.label] or def.id)
    tab:SetScript("OnClick", function() Config.SelectTab(def.id) end)
    def.tab = tab
end

--- Reiter nebeneinander in Seiten-Reihenfolge anordnen; Breite nach Beschriftung, bei Platzmangel gleichmaessig verkleinert
function layoutTabs()
    local widths, total = {}, 0
    for i, id in ipairs(Config.pageOrder) do
        local label = Config.pages[id].tab.label
        local w = (label.GetStringWidth and label:GetStringWidth() or 60)
        if type(w) ~= "number" or w ~= w then w = 60 end
        widths[i] = math.max(70, math.ceil(w) + 26)
        total = total + widths[i] + 2
    end
    local room = Config.WIDTH - 32
    local k = (total > room) and (room / total) or 1
    local x = 16
    for i, id in ipairs(Config.pageOrder) do
        local tab = Config.pages[id].tab
        local w = math.floor(widths[i] * k)
        tab:SetWidth(w)
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", frame, "TOPLEFT", x, Config.TAB_Y)
        x = x + w + math.floor(2 * k)
    end
end

--- Fensterbreite, Skalierung und Vorschau-Spalte passend zum Bildschirm: -> Breite, Skalierung, mit Spalte?
local function fitWidth()
    local P = Config.PreviewPanel
    local width = Config.PAGE_WIDTH + (P and P.EXTRA or 0)
    local screen = UIParent.GetWidth and UIParent:GetWidth()
    local scale = 1
    if type(screen) == "number" and screen > 300 then
        local fit = (screen - 20) / width
        if fit < 1 and P and fit < P.MIN_SCALE then
            -- selbst verkleinert zu breit: ohne Spalte, wie vorher
            P = nil
            width = Config.PAGE_WIDTH
            fit = (screen - 20) / width
        end
        if fit < 1 then scale = math.max(0.5, fit) end
    end
    return width, scale, P ~= nil
end

local function build()
    frame = CreateFrame("Frame", Config.FRAME_NAME, UIParent)
    Config.frame = frame
    local scale
    Config.WIDTH, scale, Config.hasPreview = fitWidth()
    if scale < 1 then frame:SetScale(scale) end
    -- auf kleinen Bildschirmen nicht hoeher als der Bildschirm (die Seiten rollen ohnehin)
    local height = Config.HEIGHT
    local screen = UIParent.GetHeight and UIParent:GetHeight()
    if type(screen) == "number" and screen > 300 and screen - 40 < height then height = math.floor(screen - 40) end
    Config.HEIGHT = height
    frame:SetSize(Config.WIDTH, height)
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
    -- Fenster-Optik: Flaechenkachel (frame.bg; die Vorschau-Spalte ersetzt sie bei "Spielwelt" durch Teilstuecke mit Loch) und
    -- Bronzerand aus Ecken und Kanten
    frame.skin = W.WindowSkin(frame, Config.WIDTH, height)
    frame.bg = frame.skin.bg

    -- Kopf: Titelschild oben mittig (ragt ueber den Rand), Schliessen rechts oben
    local plate = CreateFrame("Frame", nil, frame)
    plate:SetHeight(Config.TITLE_HEIGHT)
    plate:SetPoint("TOP", frame, "TOP", 0, Config.TITLE_RAISE)
    plate.parts = W.Slice3(plate, "title", Config.TITLE_HEIGHT, "ARTWORK", 0)
    local title = W.Text(plate, "GameFontNormalLarge", C.accent)
    title:SetPoint("CENTER", 0, 0)
    if title.SetJustifyH then title:SetJustifyH("CENTER") end
    title:SetText(ns.title)
    local tw = title.GetStringWidth and title:GetStringWidth()
    if type(tw) ~= "number" or tw ~= tw then tw = 100 end
    -- Breite mit gleicher Paritaet wie das Fenster: mittig ohne halbe Pixel
    local pw = math.max(Config.TITLE_MIN_WIDTH, math.ceil(tw) + plate.parts.capL + plate.parts.capR + 24)
    if (Config.WIDTH - pw) % 2 ~= 0 then pw = pw + 1 end
    plate:SetWidth(pw)
    for _, t in ipairs(plate.parts) do W.NoSnap(t) end
    -- Innenflaeche des Schildes ist durchsichtig: darunter dieselbe Flaechenkachel wie im Fenster (Ausschnitt nach Lage, nahtlos);
    -- sie reicht bis unter den Bronzerand des Schildes, damit der Fensterrand nicht durchscheint
    local px, py = (Config.WIDTH - pw) / 2, -Config.TITLE_RAISE
    local inX, inY = math.floor(plate.parts.capL * 0.6), 3
    local pbg = W.NoSnap(W.FillTexture(plate))
    pbg:SetPoint("TOPLEFT", plate, "TOPLEFT", inX, -inY)
    pbg:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", -inX, inY)
    W.TileRect(pbg, px + inX, py + inY, pw - 2 * inX, Config.TITLE_HEIGHT - 2 * inY)
    plate.bg = pbg
    frame.title, frame.titlePlate = title, plate

    local close = W.Button(frame, "X", 20, function() Config.Close() end)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -14, -14)
    frame.close = close

    -- Grundlinie der Reiter bis an den Rand: genau die Fuss-Zeilen aus tab-off (gleiche Zeilen, gleiche Hoehe -> pixelgleich)
    local footTop, th = W.TAB_FOOT_TOP, Config.TAB_HEIGHT
    local rule2 = W.NoSnap(W.SkinTexture(frame, "tab-off", "BORDER", 2))
    rule2:SetHeight(th - footTop)
    rule2:SetPoint("TOPLEFT", W.FRAME_BORDER, Config.TAB_Y - footTop)
    rule2:SetPoint("TOPRIGHT", -W.FRAME_BORDER, Config.TAB_Y - footTop)
    rule2:SetTexCoord(0.02, 0.04, footTop / th, 1)
    frame.tabRule = rule2

    for _, id in ipairs(Config.pageOrder) do buildPage(Config.pages[id]) end
    layoutTabs()
    if Config.hasPreview then xpcall(Config.PreviewPanel.Build, geterrorhandler(), frame) end

    -- Schliessen beendet laufende Vorschau-Tests der Seiten und stoppt die Vorschau-Spalte
    frame:SetScript("OnHide", function()
        local P = Config.PreviewPanel
        if P and Config.hasPreview and P.OnClose then xpcall(P.OnClose, geterrorhandler()) end
        for _, def in pairs(Config.pages) do
            if def.onClose and def.page then xpcall(def.onClose, geterrorhandler(), def.page) end
        end
    end)
    frame:SetScript("OnShow", function() Config.Refresh() end)

    -- ESC schliesst das Fenster (Liste des Clients, nur ein Eintrag mit unserem Namen)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Config.FRAME_NAME) end

    restorePosition()
    frame:Hide()
    local first = Config.pages[Config.current or ""] and Config.current or Config.pageOrder[1]
    if first then Config.SelectTab(first) end
end

function Config.IsShown() return frame ~= nil and frame:IsShown() == true end

--- Fenster zeigen; tab (Seiten-Id oder Alias) waehlt den Reiter, sonst bleibt der zuletzt gezeigte
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

-- /vials config [reiter]: ohne Reiter oeffnet bzw. schliesst es das Fenster, mit Reiter oeffnet es diesen (Hilfezeile HELP_CONFIG)
ns.commands.config = function(arg)
    arg = type(arg) == "string" and arg:match("^%s*(.-)%s*$") or ""
    if arg == "" then
        Config.Toggle()
        return
    end
    local id = Config.ResolveTab(arg)
    if not id then
        local names = {}
        for _, pid in ipairs(Config.pageOrder) do names[#names + 1] = pid end
        ns.Print(L.UI_CONFIG_UNKNOWN_TAB, (arg:gsub("[%c|]", "")):sub(1, 20), table.concat(names, ", "))
        return
    end
    Config.Open(id)
end
ns.commands.optionen = ns.commands.config

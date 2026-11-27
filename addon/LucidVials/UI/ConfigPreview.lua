-- Mini-Vorschau im Einstellungsfenster (Delta Ausbau 1.1.0, Anhang 4, E10): feste Spalte rechts neben den Seiten (nicht im Bildlauf der
-- Seiten) mit der Buehne aus ns.Preview.New (Nachbau des Rahmens mit den echten Bausteinen, Kern in modules/UnitFrames/Preview.lua),
-- einem Rahmen-Umschalter Spieler/Ziel, drei Pegel-Schiebern (Leben, Ressource, Erfahrung), der Ziel-Art und Test-Knoepfen je Reiter.
-- Die Spalte steht auf allen Reitern ausser "profiles". Sie gehoert dem Config-Fenster: Config.lua baut sie (Build), zeichnet sie bei
-- jedem Config.Refresh neu (Sync) und stoppt sie beim Schliessen (OnClose). Konfig-Aenderungen von aussen (Skin.OnConfigChanged)
-- zeichnen die Buehne neu, solange sie laeuft. Fehlt ns.Preview, zeigt die Spalte nur einen Hinweis.
--
-- Aufbau der Spalte: Kopfzeile (Titel + Hintergrund-Wahl dunkel/hell/Spielwelt) und Buehne stehen fest am Fenster (die Buehne rollt
-- nie weg und ihre Lage ist bekannt), darunter rollt der Rest (Umschalter, Schieber, Ziel-Art, Test-Knoepfe).
-- Hintergrund "Spielwelt": die Buehne ist durchsichtig und der Fensterhintergrund hat dort ein Loch: statt der einen Flaeche
-- (frame.bg aus Config.lua) liegen Teilstuecke der Flaechenkachel um das Buehnen-Rechteck und um die Durchsicht-Felder der gezeigten
-- Seite (def.holes, z. B. Schriftmuster; beim Bildlauf neu gelegt, Texturen aus einem Vorrat); def.background(page, modus) stellt
-- solche Felder bei jeder Wahl sofort um. Die Wahl
-- steht global in LucidVialsDB.previewBg ("dark" | "light" | "world", fehlt = dark), nicht im Profil. Um die Buehne liegt die
-- Vorschau-Mulde (Bronze-Rand ausserhalb des Lochs).
--
-- Vertrag zum Kern (E9): st = ns.Preview.New(parent); st:SetFrame("player"|"target"), st:SetLevel("health"|"power"|"xp", 0..1),
-- st:SetKind("normal"|"elite"|"rare"|"rareelite"|"boss"), st:SetBackground("dark"|"light"|"world"), st:Test(wort), st:Refresh(),
-- st:Show()/st:Hide() (Treiber an/aus), ns.Preview.TESTS_BY_PAGE[seite] = Liste der Test-Woerter. Die Buehne wird einmal gebaut und
-- danach nur noch gezeigt/versteckt (Frames lassen sich im Client nicht freigeben; Destroy wuerde nur beim naechsten Oeffnen neu bauen).
-- Fasst keine Blizzard-Frames an; die Buehne zeigt nur eigene Beispielwerte, keine Secrets; im Kampf bedienbar.
local _, ns = ...
local Skin = ns.UnitFrameSkin
local Store = ns.Store
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local P = {}
Config.PreviewPanel = P

P.COL_W = 260 -- Breite der Buehne und der Spalte
P.EXTRA = 280 -- Platz, den die Spalte dem Fenster zusaetzlich gibt (Rand, Rollleiste der Seite, Trennlinie)
P.MIN_SCALE = 0.8 -- so stark darf das Fenster auf schmalen Bildschirmen schrumpfen, bevor die Spalte entfaellt
local COL_H = 330
local STAGE_H = 200
local RIGHT_PAD = 28 -- Abstand der Spalte zum rechten Fensterrand
local HEAD_H = 24 -- Hoehe der Kopfzeile (Titel + Hintergrund-Wahl) ueber der Buehne
P.INSET = 6 -- Breite der Mulde (Bronze-Rand aussen um die Buehne)
local BACKGROUNDS = { "dark", "light", "world" }
local BG_TEXT = { dark = "UI_PREVIEW_BG_DARK", light = "UI_PREVIEW_BG_LIGHT", world = "UI_PREVIEW_BG_WORLD" }

-- Rahmen-Wahl der Reiter -> Bereich des Rahmen-Waehlers (Config.CurrentFrame); Allgemein und Profile haben keinen Waehler
local AREA = { liquid = "liquid", portrait = "portrait", text = "text", font = "font" }
local NO_PREVIEW = { profiles = true }

local KINDS = {
    { value = "normal", text = "UI_PREVIEW_KIND_NORMAL" },
    { value = "elite", text = "UI_PREVIEW_KIND_ELITE" },
    { value = "rare", text = "UI_PREVIEW_KIND_RARE" },
    { value = "rareelite", text = "UI_PREVIEW_KIND_RAREELITE" },
    { value = "boss", text = "UI_PREVIEW_KIND_BOSS" },
}

-- Zustand der Vorschau (gilt fuer die Sitzung): Pegel in Prozent, Ziel-Art, von Hand gewaehlter Rahmen (nil = dem Reiter folgen)
P.levels = { health = 80, power = 65, xp = 45 }
P.kind = "normal"
P.manual = nil
P.active = false
P.testButtons = {}
P.bgButtons = {}
P.holePieces = {}

local st -- Buehne (ns.Preview.New), nil wenn es den Kern nicht gibt

--- Methode der Buehne sicher aufrufen: ein Fehler im Kern darf das Fenster nicht lahmlegen
local function call(method, ...)
    if not st then return end
    local fn = st[method]
    if type(fn) ~= "function" then return end
    return xpcall(fn, geterrorhandler(), st, ...)
end

--- Rahmen der Buehne: von Hand gewaehlt, sonst der Rahmen-Waehler des Reiters (Ziel des Ziels und "fuer alle" -> Spieler)
local function followedFrame(scope)
    if scope == "target" then return "target" end
    return "player"
end

local function applyLevels()
    for _, kind in ipairs({ "health", "power", "xp" }) do call("SetLevel", kind, P.levels[kind] / 100) end
end

local function percent(v) return ("%d %%"):format(v) end

-- Hintergrund-Wahl (global gespeichert) ---------------------------------------------------------------------------------------
--- gewaehlter Hintergrund: "dark" (Standard) | "light" | "world"; Unbekanntes im Store gilt als dark
function P.GetBackground()
    local v = Store.db and Store.db.previewBg
    if v == "light" or v == "world" then return v end
    return "dark"
end

--- Geometrie der Buehne im Fenster (Versatz der linken oberen Ecke von der linken oberen Fensterecke, nach unten negativ)
local function stageRect()
    return Config.WIDTH - RIGHT_PAD - P.COL_W, Config.CONTENT_TOP - HEAD_H
end

--- Rechtecke, die bei "Spielwelt" durchsichtig sein sollen (Fensterkoordinaten: links, oben, Breite, Hoehe; nach unten positiv):
--- die Buehne (bei sichtbarer Spalte) und die Durchsicht-Felder der gezeigten Seite (def.holes(page) -> Liste { x, y, w, h } in
--- Seitenkoordinaten, z. B. die Schriftmuster), um den Bildlauf verschoben und auf die Bildlauf-Flaeche geschnitten
function P.HoleRects(visible)
    local rects = {}
    if visible and P.holder then
        local x, y = stageRect()
        rects[#rects + 1] = { x, -y, P.COL_W, STAGE_H }
    end
    local def = Config.current and Config.pages[Config.current]
    if def and def.holes and def.page and def.scroll then
        local ok, list = pcall(def.holes, def.page)
        if ok and type(list) == "table" then
            local off = def.scroll:GetVerticalScroll() or 0
            local cx0, cy0 = 16, -Config.CONTENT_TOP
            local cx1 = Config.WIDTH - 36 - (Config.hasPreview and P.EXTRA or 0)
            local cy1 = Config.HEIGHT - 16
            for _, r in ipairs(list) do
                local x0, y0 = math.max(cx0, cx0 + r[1]), math.max(cy0, cy0 + r[2] - off)
                local x1, y1 = math.min(cx1, cx0 + r[1] + r[3]), math.min(cy1, cy0 + r[2] + r[4] - off)
                if x1 > x0 and y1 > y0 then rects[#rects + 1] = { x0, y0, x1 - x0, y1 - y0 } end
            end
        end
    end
    return rects
end

--- Flaeche des Fensters ohne die Loecher als Teilstuecke: waagrechte Baender zwischen allen Lochkanten, je Band die Luecken
--- zwischen den Loechern -> Liste { x, y, w, h } (Fensterkoordinaten, innerhalb FILL_INSET)
function P.Decompose(holes)
    local I = W.FILL_INSET
    local rx0, ry0, rx1, ry1 = I, I, Config.WIDTH - I, Config.HEIGHT - I
    local ys = { ry0, ry1 }
    for _, h in ipairs(holes) do
        ys[#ys + 1] = math.max(ry0, math.min(ry1, h[2]))
        ys[#ys + 1] = math.max(ry0, math.min(ry1, h[2] + h[4]))
    end
    table.sort(ys)
    local out = {}
    for i = 1, #ys - 1 do
        local y0, y1 = ys[i], ys[i + 1]
        if y1 > y0 then
            local spans = {}
            for _, h in ipairs(holes) do
                if h[2] < y1 and h[2] + h[4] > y0 then spans[#spans + 1] = { math.max(rx0, h[1]), math.min(rx1, h[1] + h[3]) } end
            end
            table.sort(spans, function(p1, p2) return p1[1] < p2[1] end)
            local x = rx0
            for _, sp in ipairs(spans) do
                if sp[1] > x then out[#out + 1] = { x, y0, sp[1] - x, y1 - y0 } end
                if sp[2] > x then x = sp[2] end
            end
            if rx1 > x then out[#out + 1] = { x, y0, rx1 - x, y1 - y0 } end
        end
    end
    return out
end

--- Loecher im Fensterhintergrund: bei "world" liegen statt der einen Flaeche (frame.bg) Teilstuecke der Flaechenkachel um die
--- Loch-Rechtecke (P.HoleRects); die Texturen kommen aus einem Vorrat (P.holePieces) und werden nur neu gelegt, nie neu erzeugt,
--- wenn der Vorrat reicht. Aufruf bei Reiterwechsel, Hintergrund-Wahl und Bildlauf der Seite.
local function paintHole(visible)
    local frame = Config.frame
    if not (frame and frame.bg) then return end
    if visible ~= nil then P.visible = visible end
    local rects = (P.GetBackground() == "world") and P.HoleRects(P.visible) or {}
    local hole = #rects > 0
    local pieces = hole and P.Decompose(rects) or {}
    for i, r in ipairs(pieces) do
        local t = P.holePieces[i]
        if not t then
            t = W.NoSnap(W.FillTexture(frame))
            P.holePieces[i] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", r[1], -r[2])
        t:SetSize(r[3], r[4])
        W.TileRect(t, r[1], r[2], r[3], r[4])
        t.rect = r
        t:Show()
    end
    for i = #pieces + 1, #P.holePieces do P.holePieces[i]:Hide() end
    frame.bg:SetShown(not hole)
end
P.PaintHoles = function() paintHole(nil) end

local function paintChips(list, current)
    for id, b in pairs(list) do
        local on = (id == current)
        b:SetSelected(on)
        W.Color(b.label, on and C.text or C.muted)
        if on then b.under:Show() else b.under:Hide() end
    end
end

--- Hintergrund waehlen (Klick) bzw. anwenden (value nil): Buehne, Auswahl-Knoepfe und Fensterhintergrund; Klick merkt die Wahl im Store
function P.SetBackground(value)
    if value ~= nil then
        if not (value == "dark" or value == "light" or value == "world") then return end
        if Store.db then Store.db.previewBg = (value ~= "dark") and value or nil end
    end
    local mode = P.GetBackground()
    call("SetBackground", mode)
    paintChips(P.bgButtons, mode)
    local id = Config.current
    paintHole(id ~= nil and not NO_PREVIEW[id])
    -- Seiten mit Durchsicht-Feldern (Schriftmuster) sofort umstellen, auch nicht gezeigte, schon gebaute
    for _, def in pairs(Config.pages) do
        if def.page and def.background then xpcall(def.background, geterrorhandler(), def.page, mode) end
    end
end

-- Aufbau ---------------------------------------------------------------------------------------------------------------------
--- kleiner Auswahl-Knopf (Umschalter, Hintergrund-Wahl): Feld mit Rand, gewaehlter bekommt eine Bronze-Linie darunter
local function makeChip(parent, width, height, text, font)
    local b = W.FlatButton(parent, width, height, font or "GameFontHighlight")
    b.label:SetJustifyH("CENTER")
    b.label:SetText(text)
    W.Fill(b, C.panel, "BACKGROUND")
    W.Border(b)
    b.under = b:CreateTexture(nil, "ARTWORK")
    b.under:SetColorTexture(C.bronze[1], C.bronze[2], C.bronze[3], 1)
    b.under:SetHeight(2)
    b.under:SetPoint("BOTTOMLEFT", 2, 0)
    b.under:SetPoint("BOTTOMRIGHT", -2, 0)
    b.under:Hide()
    return b
end

local function makeSwitch(content, id, textKey, x)
    local b = makeChip(content, 128, 24, L[textKey])
    b:SetPoint("TOPLEFT", x, 0)
    b:SetScript("OnClick", function()
        P.manual = id
        P.Sync()
    end)
    W.Tooltip(b, function() return L.UI_PREVIEW_HEAD, L.UI_PREVIEW_FRAME_TIP end)
    b.frameId = id
    return b
end

local function makeLevel(content, kind, labelKey, tipKey, y)
    local s = W.Slider(content, L[labelKey], 0, 100, 1, P.COL_W, percent, function(v)
        P.levels[kind] = v
        call("SetLevel", kind, v / 100)
    end)
    s:SetPoint("TOPLEFT", 0, y)
    s:SetValue(P.levels[kind])
    W.Tooltip(s, function() return L[labelKey], L[tipKey] end)
    return s
end

--- Fenster-Rahmen frame um die Spalte ergaenzen (einmal, beim ersten Oeffnen des Fensters; Aufruf aus Config.lua)
function P.Build(frame)
    local x, y = stageRect()
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4])
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", x - 8, Config.CONTENT_TOP)
    divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x - 8, 16)
    P.divider = divider

    -- Kopfzeile: Titel (die Linie darunter liegt auf der Buehnen-Oberkante)
    local head = W.Header(frame, L.UI_PREVIEW_HEAD, P.COL_W)
    head:SetPoint("TOPLEFT", frame, "TOPLEFT", x, Config.CONTENT_TOP)
    P.head = head

    -- Rest der Spalte rollt unter der Buehne
    local belowStage = y - STAGE_H - 6
    local scroll, content = W.ScrollPage(frame, P.COL_W, COL_H)
    scroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -RIGHT_PAD, belowStage)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -RIGHT_PAD, 16)
    scroll:SetWidth(P.COL_W)
    scroll:Hide()
    P.scroll, P.content = scroll, content

    local Preview = ns.Preview
    if type(Preview) ~= "table" or type(Preview.New) ~= "function" then
        local note = W.Note(content, 0, -8, P.COL_W, "GameFontHighlightSmall", C.warn)
        note:SetText(L.UI_PREVIEW_MISSING)
        return
    end

    -- Buehne: fester Rahmen am Fenster (ihr Hintergrund kommt vom Kern: dunkel, hell oder durchsichtig)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(P.COL_W, STAGE_H)
    holder:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    -- Vorschau-Mulde: Bronze-Rand (9-Slice ohne Mitte) aussen um die Buehne; die Kopfzeile braucht darunter keine Linie mehr
    P.inset = W.Slice9(holder, "inset", P.INSET, "ARTWORK", 0, holder, { outside = true })
    for _, tx in ipairs(P.inset) do W.NoSnap(tx) end
    if head.line then
        head.line:Hide()
        head.line = nil
    end
    holder:Hide()
    P.holder = holder
    local ok, stage = xpcall(Preview.New, geterrorhandler(), holder)
    if not ok or type(stage) ~= "table" then
        P.holder = nil
        local note = W.Note(content, 0, -8, P.COL_W, "GameFontHighlightSmall", C.warn)
        note:SetText(L.UI_PREVIEW_MISSING)
        return
    end
    st = stage
    if st.frame and st.frame.SetPoint then
        st.frame:ClearAllPoints()
        st.frame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    end
    call("Hide") -- laeuft erst, wenn Reiter und Fenster sichtbar sind (Sync)

    -- Hintergrund-Wahl rechts in der Kopfzeile
    local bx = P.COL_W
    for i = #BACKGROUNDS, 1, -1 do
        local mode = BACKGROUNDS[i]
        local w = (mode == "world") and 66 or 50
        local b = makeChip(frame, w, 18, L[BG_TEXT[mode]], "GameFontHighlightSmall")
        bx = bx - w
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", x + bx, Config.CONTENT_TOP + 1)
        bx = bx - 3
        b:SetScript("OnClick", function() P.SetBackground(mode) end)
        W.Tooltip(b, function() return L[BG_TEXT[mode]], L[BG_TEXT[mode] .. "_TIP"] end)
        P.bgButtons[mode] = b
    end

    P.switch = {
        player = makeSwitch(content, "player", "UI_PREVIEW_FRAME_PLAYER", 0),
        target = makeSwitch(content, "target", "UI_PREVIEW_FRAME_TARGET", P.COL_W - 128),
    }
    P.slHealth = makeLevel(content, "health", "UI_PREVIEW_LVL_HEALTH", "UI_PREVIEW_LVL_HEALTH_TIP", -30)
    P.slPower = makeLevel(content, "power", "UI_PREVIEW_LVL_POWER", "UI_PREVIEW_LVL_POWER_TIP", -64)
    P.slXp = makeLevel(content, "xp", "UI_PREVIEW_LVL_XP", "UI_PREVIEW_LVL_XP_TIP", -98)

    local kindLabel = W.Text(content, "GameFontNormalSmall", C.muted)
    kindLabel:SetPoint("TOPLEFT", 0, -144)
    kindLabel:SetText(L.UI_PREVIEW_KIND)
    local dd = W.Dropdown(content, 180, function(v)
        P.kind = v
        call("SetKind", v)
        P.Paint()
    end)
    dd:SetPoint("TOPLEFT", P.COL_W - 180, -138)
    local options = {}
    for _, k in ipairs(KINDS) do options[#options + 1] = { value = k.value, text = L[k.text] } end
    dd:SetOptions(options)
    dd:SetValue(P.kind)
    W.Tooltip(dd, function() return L.UI_PREVIEW_KIND, L.UI_PREVIEW_KIND_TIP end)
    P.kindDropdown = dd

    P.testHead = W.Header(content, L.UI_PREVIEW_HEAD_TESTS, P.COL_W)
    P.testHead:SetPoint("TOPLEFT", 0, -172)
    P.note = W.Note(content, 0, -250, P.COL_W, "GameFontHighlightSmall", C.muted)
    P.note:SetText(L.UI_PREVIEW_NOTE)

    -- Anfangszustand an die Buehne weitergeben
    call("SetKind", P.kind)
    applyLevels()
    P.SetBackground()
end

-- Test-Knoepfe ---------------------------------------------------------------------------------------------------------------
local BTN_H, BTN_GAP = 22, 4
local TESTS_Y = -196

local function testButton(i)
    local b = P.testButtons[i]
    if b then return b end
    b = W.Button(P.content, "", 80, function(self)
        if self.word then call("Test", self.word) end
    end)
    W.Tooltip(b, function(self)
        if not self.word then return nil end
        local key = "UI_PREVIEW_T_" .. self.word:upper()
        return L[key], L[key .. "_TIP"]
    end)
    P.testButtons[i] = b
    return b
end

--- Test-Knoepfe fuer den Reiter anordnen: bis zu zwei Woerter ueber die ganze Breite, sonst in drei Spalten
local function layoutTests(pageId)
    local list = (ns.Preview and ns.Preview.TESTS_BY_PAGE and ns.Preview.TESTS_BY_PAGE[pageId]) or {}
    local n = #list
    local cols = (n >= 5) and 3 or (n >= 2 and 2 or 1)
    local w = math.floor((P.COL_W - (cols - 1) * BTN_GAP) / cols)
    for i, word in ipairs(list) do
        local b = testButton(i)
        b.word = word
        b:SetText(L["UI_PREVIEW_T_" .. tostring(word):upper()])
        b:SetWidth(w)
        b:ClearAllPoints()
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        b:SetPoint("TOPLEFT", col * (w + BTN_GAP), TESTS_Y - row * (BTN_H + BTN_GAP))
        b:Show()
    end
    for i = n + 1, #P.testButtons do
        P.testButtons[i].word = nil
        P.testButtons[i]:Hide()
    end
    P.testHead:SetShown(n > 0)
    local rows = math.ceil(n / cols)
    local noteY = TESTS_Y - rows * (BTN_H + BTN_GAP) - 6
    if n == 0 then noteY = -172 end
    P.note:ClearAllPoints()
    P.note:SetPoint("TOPLEFT", 0, noteY)
    local height = -noteY + 50
    P.content:SetHeight(math.max(height, 100))
    if P.scroll.UpdateBar then P.scroll.UpdateBar() end
end

-- Abgleich mit Fenster und Reiter -------------------------------------------------------------------------------------------
--- Rahmen, den die Buehne wirklich zeigt: eine Ziel-Art ausser "normal" zeigt die Ziel-Optik, auch wenn "Spieler" gewaehlt ist
local function shownFrame()
    local f
    if st and type(st.ShownFrame) == "function" then
        local ok, r = pcall(st.ShownFrame, st)
        if ok then f = r end
    end
    if f ~= "player" and f ~= "target" then f = (P.kind ~= "normal") and "target" or P.stageFrame end
    return f
end

--- Umschalter und Erfahrungs-Schieber nach der gezeigten Buehne ausrichten
--- (Erfahrungsroehre gibt es nur am Spieler; im Reiter Texte & Zahlen bleibt der Regler bedienbar: Format der XP-Zahl)
function P.Paint()
    if not (st and P.switch) then return end
    local shown = shownFrame()
    paintChips(P.switch, shown)
    P.slXp:SetActive(shown == "player" or P.page == "text")
end

--- Spalte und Buehne an den Zustand des Fensters anpassen (aus Config.Refresh: Reiterwechsel, Rahmen-Wahl, Oeffnen). Idempotent.
function P.Sync()
    local frame = Config.frame
    if not (P.scroll and frame) then return end
    local id = Config.current
    local visible = id ~= nil and not NO_PREVIEW[id]
    P.scroll:SetShown(visible)
    P.divider:SetShown(visible)
    P.head:SetShown(visible)
    if P.head.line then P.head.line:SetShown(visible) end
    if P.holder then P.holder:SetShown(visible) end
    for _, b in pairs(P.bgButtons) do b:SetShown(visible) end
    paintHole(visible)
    if not st then return end

    local want = visible and frame:IsShown() == true
    if not want then
        if P.active then
            P.active = false
            call("Hide")
        end
        return
    end

    -- Reiterwechsel oder neue Wahl im Rahmen-Waehler: wieder dem Reiter folgen (statt der letzten Handwahl)
    local area = AREA[id]
    local scope = area and Config.CurrentFrame(area) or nil
    local pageChanged = (id ~= P.page)
    if pageChanged or scope ~= P.scope then P.manual = nil end
    P.page, P.scope = id, scope

    local stageFrame = P.manual or followedFrame(scope)
    local frameChanged = (stageFrame ~= P.stageFrame)
    if frameChanged then
        P.stageFrame = stageFrame
        call("SetFrame", stageFrame)
        applyLevels()
    end
    if pageChanged then layoutTests(id) end

    if not P.active then
        P.active = true
        call("Show")
        call("Refresh")
    elseif pageChanged or frameChanged then
        call("Refresh")
    end
    P.Paint()
end

--- Fenster schliesst: Buehne und Treiber aus
function P.OnClose()
    if P.active then
        P.active = false
        call("Hide")
    end
    P.page, P.stageFrame = nil, nil
end

-- Aenderungen am Profil (auch per Slash-Befehl oder Profilwechsel) zeichnen die laufende Buehne neu
Skin.OnConfigChanged(function()
    if P.active then call("Refresh") end
end)

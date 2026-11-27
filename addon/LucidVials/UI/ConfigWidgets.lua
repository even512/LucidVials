-- Eigene, schlichte Widgets fuer das Konfig-Fenster (B4). Keine Fremd-Bibliotheken, keine geschuetzten Templates.
-- Alles hier sind ungeschuetzte, eigene Frames; Blizzard-Templates nur, wo sie ungeschuetzt und seit Langem stabil
-- sind (UIPanelButtonTemplate, UIPanelCloseButton) - jeweils per pcall mit eigenem Ersatz.
--
-- Dropdowns: in Retail 12.x / Forever das neue Menue-System (MenuUtil + WowStyle1DropdownTemplate, kein
-- UIDropDownMenu => kein Taint der alten Dropdown-Liste), per Existenzpruefung; sonst eine eigene einfache Liste.
--
-- Sicherheit: dynamischer Text (Profilnamen, Fehlerdetails, Eingaben) geht nur ueber Widgets.Plain in FontStrings,
-- Tooltips und Menues: "|" wird verdoppelt, damit keine Escape-Codes (|c, |T, |H ...) wirken.
local _, ns = ...

local W = {}
ns.Widgets = W

-- Farben nach dem Entwurf des Optionsfensters (docs/config-src/entwurf-config-v1.jpg): dunkle Braun-Grau-Flaeche, Bronze,
-- warmes Hellgold fuer Ueberschriften (accent), gedecktes Beige fuer Text; keine Leuchteffekte
W.COLORS = {
    bg = { 0.165, 0.14, 0.13, 0.97 },
    panel = { 0.11, 0.095, 0.085, 0.92 },
    line = { 0.78, 0.6, 0.38, 0.32 },
    accent = { 0.93, 0.79, 0.53 },
    text = { 0.88, 0.83, 0.74 },
    muted = { 0.66, 0.6, 0.51 },
    disabled = { 0.45, 0.42, 0.38 },
    warn = { 1, 0.6, 0.45 },
    ok = { 0.55, 0.88, 0.62 },
    select = { 0.85, 0.66, 0.4, 0.16 },
    bronze = { 0.82, 0.62, 0.34 },   -- Bronze der Rahmen (Linien unter Reitern, Auswahl-Knoepfe)
}
local C = W.COLORS

-- Fenster-Optik (Redesign nach Textur-Bogen docs/config-src/sheet-config-v1.jpg, geschnitten von scripts/cut-config.mjs) -------------
W.MEDIA = "Interface\\AddOns\\LucidVials\\Media\\config\\"
--- Quellmasse der Teile im Bogen (Breite w, Hoehe h, 3-Slice-Kappen l/r, 9-Slice-Ecke s9, Lage der Box bei den Haekchen);
--- muessen zu PARTS in scripts/cut-config.mjs passen (tests/config-skin.test.mjs)
W.SKIN = {
    corner = { w = 240, h = 240 },
    ["edge-h"] = { w = 192, h = 48 },
    ["edge-v"] = { w = 48, h = 192 },
    title = { w = 1326, h = 266, l = 153, r = 153 },
    ["tab-off"] = { w = 608, h = 192, l = 76, r = 76 },
    ["tab-on"] = { w = 586, h = 202, l = 84, r = 81 },
    inset = { w = 508, h = 508, s9 = 58 },
    ["slider-track"] = { w = 956, h = 74, l = 39, r = 39 },
    ["slider-knob"] = { w = 124, h = 124 },
    ["check-off"] = { w = 216, h = 216, box = { 8, 44, 166, 166 }, s9 = 34 },
    ["check-on"] = { w = 216, h = 216, box = { 8, 44, 166, 166 } },
    dropdown = { w = 740, h = 156, l = 37, r = 131 },
    ["scroll-up"] = { w = 111, h = 108 },
    ["scroll-down"] = { w = 111, h = 108 },
    ["scroll-track"] = { w = 111, h = 380 },
    ["scroll-thumb"] = { w = 79, h = 84 },
    divider = { w = 851, h = 76, l = 503, r = 26 },
    fill = { w = 256, h = 256 },
}
-- Anzeige-Masse (UI-Einheiten bei Skalierung 1): Randleiste BORDER, Ecke CORNER (Ecke 240 Quellpunkte, Rand 48 -> gleiche Dichte;
-- die Kanten stammen aus den geraden Armen derselben Ecke),
-- eine Rand-Kachel ist EDGE_TILE lang (192 Quellpunkte), die Flaechenkachel FILL_TILE (1 Texel = 1 Einheit); die Flaeche liegt
-- FILL_INSET unter dem Rand (die Aussenecken sind abgerundet)
W.FRAME_BORDER = 9
W.FRAME_CORNER = 45
W.EDGE_TILE = 36
W.FILL_TILE = 256
W.FILL_INSET = 3
W.EDGE_OVERLAP = 2
-- Reiter-Fuss: Zeilen 22..26 eines 26 hohen Reiters (Texturzeilen 55..62 von 64); die Grundlinie neben den Reitern zeigt genau
-- diese Zeilen aus dem Fuss von tab-off, damit sie pixelgleich anschliesst
W.TAB_FOOT_TOP = 22

--- Textur aus Media/config/ (file ohne Endung); wrap = kachelbar (REPEAT, ohne Zusatzargumente auf aelteren Clients)
local function skinTex(parent, file, layer, sub, wrap)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    if sub and t.SetDrawLayer then t:SetDrawLayer(layer or "ARTWORK", sub) end
    local path = W.MEDIA .. file
    if wrap then
        if not pcall(t.SetTexture, t, path, "REPEAT", "REPEAT") then t:SetTexture(path) end
    else
        t:SetTexture(path)
    end
    t.skinFile = file
    return t
end
W.SkinTexture = skinTex

--- Rahmenteile wie Blizzards NineSlice: nicht einzeln aufs Pixelraster schnappen (sonst entstehen bei UI-Skalierung ungleich 1
--- Luecken oder Doppelpixel zwischen aneinanderhaengenden Teilen); die Lage selbst ist ganzzahlig
local function noSnap(t)
    if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, false) end
    if t.SetTexelSnappingBias then pcall(t.SetTexelSnappingBias, t, 0) end
    return t
end
W.NoSnap = noSnap

--- Kachel-Ausschnitt: Textur tex zeigt das Stueck (x, y, w, h) der Flaeche (in Fensterkoordinaten ab links oben), damit
--- Teilstuecke nahtlos aneinander passen
function W.TileRect(tex, x, y, w, h)
    local T = W.FILL_TILE
    tex:SetTexCoord(x / T, (x + w) / T, y / T, (y + h) / T)
end

--- Flaechenkachel (Fensterhintergrund) auf frame, Lage und Ausschnitt setzt der Aufrufer
function W.FillTexture(frame)
    return skinTex(frame, "fill", "BACKGROUND", -8, true)
end

--- 3-Slice waagrecht: drei Texturen auf owner, senkrecht mittig an anchor (Standard owner), Hoehe height; Kappen in der Breite
--- aus dem Seitenverhaeltnis des Bogens. Liefert { l, m, r, capL, capR }.
function W.Slice3(owner, file, height, layer, sub, anchor)
    local s = W.SKIN[file]
    anchor = anchor or owner
    local capL = math.floor(height * s.l / s.h + 0.5)
    local capR = math.floor(height * s.r / s.h + 0.5)
    local uL, uR = s.l / s.w, 1 - s.r / s.w
    local l = skinTex(owner, file, layer, sub)
    l:SetPoint("LEFT", anchor, "LEFT", 0, 0)
    l:SetSize(capL, height)
    l:SetTexCoord(0, uL, 0, 1)
    local r = skinTex(owner, file, layer, sub)
    r:SetPoint("RIGHT", anchor, "RIGHT", 0, 0)
    r:SetSize(capR, height)
    r:SetTexCoord(uR, 1, 0, 1)
    local m = skinTex(owner, file, layer, sub)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT", 0, 0)
    m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT", 0, 0)
    m:SetTexCoord(uL, uR, 0, 1)
    return { l, m, r, capL = capL, capR = capR }
end

--- Teile (Liste von Texturen) zeigen/verstecken bzw. abdunkeln
local function partsShown(parts, on)
    for _, t in ipairs(parts) do t:SetShown(on) end
end
local function partsAlpha(parts, a)
    for _, t in ipairs(parts) do t:SetAlpha(a) end
end
W.PartsShown, W.PartsAlpha = partsShown, partsAlpha

--- 9-Slice: acht Rand-Texturen (und mit center die Mitte) auf owner. outside = Rand liegt aussen um anchor (Mulde um die Buehne),
--- sonst fuellt das Ganze anchor. c = Eckgroesse in UI-Einheiten. Liefert die Liste der Texturen.
function W.Slice9(owner, file, c, layer, sub, anchor, opts)
    opts = opts or {}
    anchor = anchor or owner
    local s = W.SKIN[file]
    local box = s.box or { 0, 0, s.w, s.h }
    local u0, v0 = box[1] / s.w, box[2] / s.h
    local u3, v3 = (box[1] + box[3]) / s.w, (box[2] + box[4]) / s.h
    local u1, v1 = u0 + s.s9 / s.w, v0 + s.s9 / s.h
    local u2, v2 = u3 - s.s9 / s.w, v3 - s.s9 / s.h
    local out = opts.outside and c or 0
    local parts = {}
    local function piece(l, r, t, b)
        local tx = skinTex(owner, file, layer, sub)
        tx:SetTexCoord(l, r, t, b)
        parts[#parts + 1] = tx
        return tx
    end
    local tl = piece(u0, u1, v0, v1)
    tl:SetSize(c, c)
    tl:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
    local tr = piece(u2, u3, v0, v1)
    tr:SetSize(c, c)
    tr:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", out, out)
    local bl = piece(u0, u1, v2, v3)
    bl:SetSize(c, c)
    bl:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -out, -out)
    local br = piece(u2, u3, v2, v3)
    br:SetSize(c, c)
    br:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
    local top = piece(u1, u2, v0, v1)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
    top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT", 0, 0)
    local bottom = piece(u1, u2, v2, v3)
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
    local left = piece(u0, u1, v1, v2)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT", 0, 0)
    local right = piece(u2, u3, v1, v2)
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
    if opts.center then
        local mid = piece(u1, u2, v1, v2)
        mid:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT", 0, 0)
        mid:SetPoint("BOTTOMRIGHT", br, "TOPLEFT", 0, 0)
    end
    return parts
end

--- Fenster-Optik auf frame (Groesse width x height, fest beim Bauen): Flaechenkachel (frame.bg, FILL_INSET unter dem Rand),
--- Bronzerand aus vier Ecken (eine Textur, gespiegelt) und vier kachelnden Kanten. Liefert { bg, corners = {...}, edges = {...} }.
function W.WindowSkin(frame, width, height)
    local B, CN, T, I = W.FRAME_BORDER, W.FRAME_CORNER, W.EDGE_TILE, W.FILL_INSET
    local bg = noSnap(W.FillTexture(frame))
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", I, -I)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -I, I)
    W.TileRect(bg, I, I, width - 2 * I, height - 2 * I)

    local corners = {}
    local function corner(point, l, r, t, b)
        local c = noSnap(skinTex(frame, "corner", "BORDER", 1))
        c:SetSize(CN, CN)
        c:SetPoint(point, frame, point, 0, 0)
        c:SetTexCoord(l, r, t, b)
        corners[#corners + 1] = c
    end
    corner("TOPLEFT", 0, 1, 0, 1)
    corner("TOPRIGHT", 1, 0, 0, 1)
    corner("BOTTOMLEFT", 0, 1, 1, 0)
    corner("BOTTOMRIGHT", 1, 0, 1, 0)

    -- Kanten laufen EDGE_OVERLAP unter die Ecken (gleiches Profil, die Ecke liegt darueber), damit an der Stossstelle nichts aufreisst
    local O = W.EDGE_OVERLAP
    local lenH, lenV = math.max(0, width - 2 * (CN - O)), math.max(0, height - 2 * (CN - O))
    local edges = {}
    local function edge(file, p1, x1, y1, p2, x2, y2, l, r, t, b, horiz)
        local e = noSnap(skinTex(frame, file, "BORDER", 0, true))
        e:SetPoint(p1, frame, p1, x1, y1)
        e:SetPoint(p2, frame, p2, x2, y2)
        if horiz then e:SetHeight(B) else e:SetWidth(B) end
        e:SetTexCoord(l, r, t, b)
        edges[#edges + 1] = e
    end
    local E = CN - O
    edge("edge-h", "TOPLEFT", E, 0, "TOPRIGHT", -E, 0, 0, lenH / T, 0, 1, true)
    edge("edge-h", "BOTTOMLEFT", E, 0, "BOTTOMRIGHT", -E, 0, 0, lenH / T, 1, 0, true)
    edge("edge-v", "TOPLEFT", 0, -E, "BOTTOMLEFT", 0, E, 0, 1, 0, lenV / T, false)
    edge("edge-v", "TOPRIGHT", 0, -E, "BOTTOMRIGHT", 0, E, 1, 0, 0, lenV / T, false)
    return { bg = bg, corners = corners, edges = edges }
end

--- Text fuer FontString/Tooltip/Menue ohne wirksame Escape-Codes
function W.Plain(s)
    return (tostring(s == nil and "" or s):gsub("|", "||"))
end

local function color(fs, c)
    if fs and fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3]) end
end
W.Color = color

function W.Fill(frame, c, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints(frame)
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return t
end

--- feiner Rahmen (1 px) aus vier Linien
function W.Border(frame, c)
    c = c or C.line
    local function line(p1, p2, horiz)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if horiz then t:SetHeight(1) else t:SetWidth(1) end
        return t
    end
    line("TOPLEFT", "TOPRIGHT", true)
    line("BOTTOMLEFT", "BOTTOMRIGHT", true)
    line("TOPLEFT", "BOTTOMLEFT", false)
    line("TOPRIGHT", "BOTTOMRIGHT", false)
end

--- FontString mit Schrift (Font-Objekt-Name) und Farbe
function W.Text(parent, font, c, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    local obj = _G[font or "GameFontHighlight"] or _G.GameFontHighlight
    if obj then fs:SetFontObject(obj) end
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    color(fs, c or C.text)
    return fs
end

-- Tooltip ------------------------------------------------------------------------------------------
--- Tooltip an ein Widget haengen. fn() -> titel, text (beide bereits als Plain-Text oder Locale-Text)
--- Zusatzzeilen (Standardwert, Zuruecksetzen) aus widget.defaultLines(widget) haengen hinten an, in Hellgold. Bei Schiebern haengt
--- der Tooltip auch am eigentlichen Slider (er faengt die Maus, der Rahmen darum nicht).
local function showTip(owner, anchor)
    local tip = GameTooltip
    if not (tip and owner.tooltipFn) then return end
    local title, text = owner.tooltipFn(owner)
    if not title then return end
    tip:SetOwner(anchor, "ANCHOR_RIGHT")
    tip:SetText(title, 1, 1, 1)
    if text then tip:AddLine(text, nil, nil, nil, true) end
    if owner.defaultLines then
        local ok, lines = pcall(owner.defaultLines, owner)
        if ok and type(lines) == "table" then
            for _, line in ipairs(lines) do tip:AddLine(line, C.accent[1], C.accent[2], C.accent[3], true) end
        end
    end
    tip:Show()
end

function W.Tooltip(widget, fn)
    widget.tooltipFn = fn
    if widget.lucidTooltipHooked then return end
    widget.lucidTooltipHooked = true
    local function hook(target)
        target:HookScript("OnEnter", function(self) showTip(widget, self) end)
        target:HookScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end
    hook(widget)
    if widget.slider and widget.slider.HookScript then hook(widget.slider) end
end

-- Standardwerte (Nachtrag Anhang 4) --------------------------------------------------------------------------------------------
--- Standardwert zu einem Pfad wie bei Skin.Set ("liquid.sloshStrength", "font.health.size", "auraSize") aus den Schema-Defaults
--- (Skin.Defaults, eine Quelle fuer alle Bereiche; Eigenwerte je Rahmen starten mit denselben Werten). nil, wenn unbekannt.
function W.DefaultValue(path)
    local Skin = ns.UnitFrameSkin
    if type(path) ~= "string" or not (Skin and type(Skin.Defaults) == "function") then return nil end
    local ok, t = pcall(Skin.Defaults)
    if not ok then return nil end
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

--- Getter fuer :SetDefault aus Pfad (optional in die Anzeige umgerechnet, toUi(v)) oder Funktion; der Pfad bleibt als .defaultPath
local function defaultGetter(widget, src, toUi)
    if type(src) == "function" then
        widget.defaultPath = nil
        return src
    end
    widget.defaultPath = src
    return function()
        local v = W.DefaultValue(src)
        if v ~= nil and toUi then v = toUi(v) end
        return v
    end
end
local function callDefault(widget)
    if not widget.defaultGetter then return nil end
    local ok, v = pcall(widget.defaultGetter)
    if ok then return v end
    return nil
end
W.GetDefault = callDefault

-- Knoepfe ------------------------------------------------------------------------------------------
--- Knopf in Fenster-Optik: Bronzerand mit dunkler Flaeche (9-Slice aus der Haekchen-Box), Beschriftung beige, inaktiv gedaempft
local BUTTON_CORNER = 5
function W.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.skin = W.Slice9(b, "check-off", BUTTON_CORNER, "BACKGROUND", 0, b, { center = true })
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 2, -2)
    hl:SetPoint("BOTTOMRIGHT", -2, 2)
    hl:SetColorTexture(1, 0.9, 0.7, 0.07)
    local fs = W.Text(b, "GameFontHighlight")
    fs:SetPoint("CENTER", 0, 0)
    if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
    b.label = fs
    b.SetText = function(_, t) fs:SetText(t) end
    b.GetText = function() return fs:GetText() end
    local function paint(self)
        local on = not (self.IsEnabled and not self:IsEnabled())
        color(fs, on and C.text or C.disabled)
        partsAlpha(self.skin, on and 1 or 0.6)
    end
    b:SetScript("OnEnable", paint)
    b:SetScript("OnDisable", paint)
    -- gedrueckt: Beschriftung 1 px nach unten
    b:SetScript("OnMouseDown", function(self)
        if self.IsEnabled and not self:IsEnabled() then return end
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", 1, -1)
    end)
    b:SetScript("OnMouseUp", function()
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", 0, 0)
    end)
    b:SetSize(width or 110, 22)
    b:SetText(text or "")
    paint(b)
    if onClick then b:SetScript("OnClick", function(self) onClick(self) end) end
    return b
end

--- Reiter in Fenster-Optik: inaktiv flach (tab-off), gewaehlt mit Bronze-Oberkante (tab-on, in b.under); beide 3-Slice mit Fuss
function W.Tab(parent, width, height, font)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    -- beide Optiken als Texturen direkt auf dem Reiter (BACKGROUND), die Beschriftung liegt darueber (OVERLAY desselben Frames);
    -- ein Kind-Frame wuerde ueber allen Regionen des Reiters und damit ueber der Beschriftung zeichnen
    b.skinOff = W.Slice3(b, "tab-off", height, "BACKGROUND", 0)
    b.skinOn = W.Slice3(b, "tab-on", height, "BACKGROUND", 1)
    partsShown(b.skinOn, false)
    -- b.under: Schalter der gewaehlten Optik (Show/Hide/IsShown/SetShown wie ein Frame)
    b.under = {
        shown = false,
        Show = function(self) self.shown = true; partsShown(b.skinOn, true) end,
        Hide = function(self) self.shown = false; partsShown(b.skinOn, false) end,
        SetShown = function(self, on) if on then self:Show() else self:Hide() end end,
        IsShown = function(self) return self.shown end,
    }
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 4, -3)
    hl:SetPoint("BOTTOMRIGHT", -4, 3)
    hl:SetColorTexture(1, 0.9, 0.7, 0.05)
    b.label = W.Text(b, font or "GameFontHighlight", nil, "OVERLAY")
    b.label:SetPoint("LEFT", 6, 1)
    b.label:SetPoint("RIGHT", -6, 1)
    if b.label.SetJustifyH then b.label:SetJustifyH("CENTER") end
    b.SetSelected = function(self, on)
        partsShown(self.skinOff, not on)
        if on then self.under:Show() else self.under:Hide() end
        self.selected = on and true or false
    end
    return b
end

--- flacher Text-Knopf (Listeneintraege, Auswahl-Knoepfe) mit Auswahl-Hintergrund
function W.FlatButton(parent, width, height, font)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    b.sel = W.Fill(b, C.select, "BACKGROUND")
    b.sel:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.06)
    b.label = W.Text(b, font or "GameFontHighlight")
    b.label:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("RIGHT", -4, 0)
    b.SetSelected = function(self, on)
        if on then self.sel:Show() else self.sel:Hide() end
        self.selected = on and true or false
    end
    return b
end

-- Haken ----------------------------------------------------------------------------------------------
--- Haken mit Beschriftung. onChange(checked) nur bei Nutzer-Klick; SetValue setzt still.
-- Die Box liegt in check-off/check-on links unten (der Haken ragt rechts oben heraus); die Texturen werden um CHECK_LIFT nach
-- oben geschoben, damit die Box senkrecht mittig zum Klickfeld und zur Beschriftung steht
local CHECK_SIZE, CHECK_LIFT = 22, 2
local function placeCheckTex(t)
    if not (t and t.ClearAllPoints) then return end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", 0, CHECK_LIFT)
    t:SetSize(CHECK_SIZE, CHECK_SIZE)
end
function W.Check(parent, label, onChange)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(CHECK_SIZE, CHECK_SIZE)
    cb:SetNormalTexture(W.MEDIA .. "check-off")
    cb:SetPushedTexture(W.MEDIA .. "check-off")
    cb:SetHighlightTexture(W.MEDIA .. "check-off", "ADD")
    cb:SetCheckedTexture(W.MEDIA .. "check-on")
    cb:SetDisabledCheckedTexture(W.MEDIA .. "check-on")
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture",
        "GetDisabledCheckedTexture" }) do
        if cb[get] then placeCheckTex(cb[get](cb)) end
    end
    if cb.GetHighlightTexture then
        local hl = cb:GetHighlightTexture()
        if hl and hl.SetAlpha then hl:SetAlpha(0.25) end
    end
    if cb.GetDisabledCheckedTexture then
        local dc = cb:GetDisabledCheckedTexture()
        if dc and dc.SetVertexColor then dc:SetVertexColor(0.55, 0.55, 0.55) end
    end
    cb.label = W.Text(cb, "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(label or "")
    cb:SetScript("OnClick", function(self)
        if onChange then onChange(self:GetChecked() and true or false) end
    end)
    cb.SetValue = function(self, v) self:SetChecked(v and true or false) end
    --- Standardwert (Pfad wie bei Skin.Set oder Funktion): Tooltip-Zeile "Standard: an/aus"
    cb.SetDefault = function(self, src)
        self.defaultGetter = defaultGetter(self, src)
        if not self.tooltipFn then W.Tooltip(self, function() return self.label:GetText() end) end
        self.defaultLines = function(b)
            local d = callDefault(b)
            if d == nil then return {} end
            return { ns.L.UI_DEFAULT_VALUE:format(d and ns.L.UI_DEFAULT_ON or ns.L.UI_DEFAULT_OFF) }
        end
    end
    cb.SetActive = function(self, on)
        if on then self:Enable() else self:Disable() end
        color(self.label, on and C.text or C.disabled)
        local n = self.GetNormalTexture and self:GetNormalTexture()
        if n and n.SetAlpha then n:SetAlpha(on and 1 or 0.55) end
    end
    return cb
end

-- Schieberegler --------------------------------------------------------------------------------------
local function round(v, step)
    if not step or step <= 0 then return v end
    local r = math.floor(v / step + 0.5) * step
    -- Gleitkomma-Rest (0.15000000000000002) entfernen
    return tonumber(("%.4f"):format(r))
end
W.Round = round

--- Schieberegler mit Beschriftung und Wertanzeige. fmt(v) -> Anzeige. onChange(v) nur bei Nutzer-Aenderung.
function W.Slider(parent, label, min, max, step, width, fmt, onChange)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width or 220, 40)
    box.title = W.Text(box, "GameFontNormalSmall", C.muted)
    box.title:SetPoint("TOPLEFT", 0, 0)
    box.title:SetText(label or "")
    box.value = W.Text(box, "GameFontHighlightSmall")
    box.value:SetPoint("TOPRIGHT", 0, 0)
    if box.value.SetJustifyH then box.value:SetJustifyH("RIGHT") end

    local s = CreateFrame("Slider", nil, box)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(16)
    s:SetPoint("TOPLEFT", 0, -16)
    s:SetPoint("TOPRIGHT", 0, -16)
    -- Rinne (3-Slice, 8 hoch, mittig) und runder Bronzeknopf (16 x 16) als Daumen
    box.track = W.Slice3(s, "slider-track", 8, "BACKGROUND", 0)
    s:SetThumbTexture(W.MEDIA .. "slider-knob")
    local thumb = s.GetThumbTexture and s:GetThumbTexture()
    if thumb and thumb.SetSize then thumb:SetSize(16, 16) end
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepCount then s:SetObeyStepCount(true) end
    if s.EnableMouseWheel then s:EnableMouseWheel(true) end
    box.slider, box.step, box.fmt = s, step, fmt or function(v) return ("%g"):format(v) end
    box.min, box.max, box.width = min, max, width or 220

    -- Standard-Marke: kleine Bronze-Kerbe auf der Rinne an der Lage des Standardwerts (Knopfmitte), erst mit :SetDefault sichtbar
    box.mark = s:CreateTexture(nil, "BACKGROUND")
    if box.mark.SetDrawLayer then box.mark:SetDrawLayer("BACKGROUND", 2) end
    box.mark:SetColorTexture(C.bronze[1], C.bronze[2], C.bronze[3], 0.9)
    box.mark:SetSize(2, 12)
    box.mark:Hide()

    local quiet = false
    s:SetScript("OnValueChanged", function(_, v)
        v = round(v, step)
        box.value:SetText(box.fmt(v))
        if quiet or box.current == v then return end
        box.current = v
        if onChange then onChange(v) end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        if self.IsEnabled and not self:IsEnabled() then return end
        local lo, hi = self:GetMinMaxValues()
        local v = round((box.current or lo) + delta * step, step)
        if v < lo then v = lo elseif v > hi then v = hi end
        self:SetValue(v)
    end)

    --- Wert setzen ohne onChange
    box.SetValue = function(self, v)
        v = round(v, step)
        quiet = true
        self.current = v
        s:SetValue(v)
        quiet = false
        self.value:SetText(self.fmt(v))
    end
    box.GetValue = function(self) return self.current end

    --- Standardwert (Pfad wie bei Skin.Set, toUi rechnet in Regler-Einheiten um, oder Funktion): Marke, Tooltip-Zeilen,
    --- Rechtsklick setzt zurueck
    box.SetDefault = function(self, src, toUi)
        self.defaultGetter = defaultGetter(self, src, toUi)
        if not self.tooltipFn then W.Tooltip(self, function() return self.title:GetText() end) end
        self.defaultLines = function(b)
            local d = b:GetDefault()
            if d == nil then return {} end
            return { ns.L.UI_DEFAULT_VALUE:format(b.fmt(d)), ns.L.UI_DEFAULT_RESET }
        end
        self:UpdateDefault()
    end
    --- Standardwert in Regler-Einheiten (auf Bereich und Schritt gebracht) oder nil
    box.GetDefault = function(self)
        local d = callDefault(self)
        if type(d) ~= "number" or d ~= d then return nil end
        if d < self.min then d = self.min elseif d > self.max then d = self.max end
        return round(d, step)
    end
    --- Lage der Marke: Mitte des Knopfs (16 breit) bei diesem Wert, ganzzahlig
    box.MarkX = function(self, v)
        local span = self.max - self.min
        local frac = span > 0 and (v - self.min) / span or 0
        return math.floor(8 + (self.width - 16) * frac + 0.5)
    end
    box.UpdateDefault = function(self)
        local d = self:GetDefault()
        if d == nil then
            self.mark:Hide()
            return
        end
        self.mark:ClearAllPoints()
        self.mark:SetPoint("CENTER", s, "LEFT", self:MarkX(d), 0)
        self.mark:Show()
    end
    --- auf Standard zuruecksetzen wie durch den Nutzer (onChange, also Pruefung und Profil); nicht, wenn gesperrt
    box.ResetToDefault = function(self)
        if s.IsEnabled and not s:IsEnabled() then return false end
        local d = self:GetDefault()
        if d == nil then return false end
        s:SetValue(d)
        return true
    end
    s:HookScript("OnMouseUp", function(_, button)
        if button == "RightButton" then box:ResetToDefault() end
    end)
    box.SetActive = function(self, on)
        if on then s:Enable() else s:Disable() end
        color(self.title, on and C.muted or C.disabled)
        color(self.value, on and C.text or C.disabled)
        partsAlpha(self.track, on and 1 or 0.55)
        local th = s.GetThumbTexture and s:GetThumbTexture()
        if th and th.SetAlpha then th:SetAlpha(on and 1 or 0.45) end
    end
    return box
end

-- Eingabefelder ------------------------------------------------------------------------------------
--- einzeiliges Eingabefeld mit eigenem Hintergrund
function W.Input(parent, width, maxLetters)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width or 180, 22)
    e:SetAutoFocus(false)
    e:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlight)
    e:SetTextInsets(6, 6, 0, 0)
    e:SetMaxLetters(maxLetters or 64)
    W.Fill(e, { 0, 0, 0, 0.55 })
    W.Border(e)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end

--- mehrzeiliges Eingabefeld in einer Rollflaeche (Export/Import). Liefert den Rahmen; .edit ist die EditBox.
function W.TextArea(parent, width, height, maxLetters)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, height)
    W.Fill(box, { 0, 0, 0, 0.55 })
    W.Border(box)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    local e = CreateFrame("EditBox", nil, scroll)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject(_G.ChatFontSmall or _G.ChatFontNormal or _G.GameFontHighlightSmall)
    e:SetWidth(width - 12)
    e:SetMaxLetters(maxLetters or 0)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(e)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
        local v = (self:GetVerticalScroll() or 0) - delta * 20
        if v < 0 then v = 0 elseif v > range then v = range end
        self:SetVerticalScroll(v)
    end)
    -- Cursor im sichtbaren Bereich halten (Blizzard-Helfer, falls vorhanden)
    e:SetScript("OnCursorChanged", function(self, x, y, w, h)
        if type(ScrollingEdit_OnCursorChanged) == "function" then ScrollingEdit_OnCursorChanged(self, x, y, w, h) end
    end)
    -- Klick irgendwo in die Flaeche setzt den Fokus
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() e:SetFocus() end)
    box.edit, box.scroll = e, scroll
    return box
end

-- Dropdown -------------------------------------------------------------------------------------------
-- Optionen: { { value = <Wert>, text = <Plain-Text>, disabled = bool, tooltip = <Text>|nil }, ... }
-- onSelect(value) nur bei Auswahl durch den Nutzer (Menue/Liste oder dd:Select). SetValue setzt still.

local function menuSystem()
    return type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function"
end

local function optionText(dd, value)
    for _, o in ipairs(dd.options) do
        if o.value == value then return o.text end
    end
    return dd.placeholder or ""
end

--- Text eines Eintrags in der Liste: der Standard-Eintrag bekommt " (Standard)"
local function listText(dd, o)
    local d = callDefault(dd)
    if d ~= nil and o.value == d then return o.text .. " " .. ns.L.UI_DEFAULT_MARK end
    return o.text
end

-- eigene, einfache Liste (Ersatz, wenn es das neue Menue-System nicht gibt)
local LIST_ROWS = 12
local function buildList(dd)
    local list = CreateFrame("Frame", nil, dd)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    list:SetWidth(dd.width)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    W.Fill(list, { 0.05, 0.06, 0.08, 0.98 })
    W.Border(list)
    list.rows, list.offset = {}, 0
    for i = 1, LIST_ROWS do
        local b = W.FlatButton(list, dd.width - 4, 18, "GameFontHighlightSmall")
        b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 18)
        b:SetScript("OnClick", function(self)
            if self.option and not self.option.disabled then
                list:Hide()
                dd:Select(self.option.value)
            end
        end)
        W.Tooltip(b, function(self)
            local o = self.option
            if o and o.tooltip then return o.text, o.tooltip end
        end)
        list.rows[i] = b
    end
    list:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, #dd.options - LIST_ROWS)
        self.offset = math.min(max, math.max(0, self.offset - delta))
        dd:RenderList()
    end)
    list:Hide()
    return list
end

function W.Dropdown(parent, width, onSelect, placeholder)
    local dd
    if menuSystem() then
        local ok, b = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        if ok and b and type(b.SetupMenu) == "function" then
            dd = b
            dd.usesMenu = true
            -- eigene Optik statt der Vorlagen-Grafik: Hintergrund und Pfeil der Vorlage nur unsichtbar (Alpha), nicht umgebaut
            for _, key in ipairs({ "Background", "Arrow" }) do
                local r = dd[key]
                if type(r) == "table" and type(r.SetAlpha) == "function" then r:SetAlpha(0) end
            end
        end
    end
    if not dd then
        dd = CreateFrame("Button", nil, parent)
        dd.text = W.Text(dd, "GameFontHighlightSmall")
        dd.text:SetPoint("LEFT", 8, 0)
        dd.text:SetPoint("RIGHT", -22, 0)
        local hl = dd:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 3, -3)
        hl:SetPoint("BOTTOMRIGHT", -3, 3)
        hl:SetColorTexture(1, 0.9, 0.7, 0.06)
        dd:SetScript("OnClick", function(self)
            if not self.list then self.list = buildList(self) end
            if self.list:IsShown() then self.list:Hide() else self.list.offset = 0; self:RenderList(); self.list:Show() end
        end)
        dd:SetScript("OnHide", function(self) if self.list then self.list:Hide() end end)
    end
    dd.width, dd.options, dd.placeholder = width or 180, {}, placeholder
    dd:SetSize(dd.width, 22)
    -- Feld mit Pfeil-Knopf rechts (3-Slice, rechte Kappe traegt den Pfeil)
    dd.skin = W.Slice3(dd, "dropdown", 22, "BACKGROUND", -1)

    function dd:RenderList()
        local list = self.list
        if not list then return end
        local n = math.min(LIST_ROWS, #self.options)
        list:SetHeight(n * 18 + 4)
        for i, b in ipairs(list.rows) do
            local o = self.options[i + list.offset]
            b.option = o
            if o and i <= n then
                b.label:SetText(listText(self, o))
                color(b.label, o.disabled and C.disabled or C.text)
                b:SetSelected(o.value == self.value)
                b:Show()
            else
                b:Hide()
            end
        end
    end

    function dd:Refresh()
        if self.usesMenu then
            -- Knopftext = gewaehlte Radio-Option (das Menue-System liest isSelected beim Neuaufbau),
            -- ohne Auswahl der Platzhalter
            if self.placeholder and type(self.SetDefaultText) == "function" then pcall(self.SetDefaultText, self, self.placeholder) end
            if type(self.GenerateMenu) == "function" then pcall(self.GenerateMenu, self) end
        else
            self.text:SetText(optionText(self, self.value))
            if self.list and self.list:IsShown() then self:RenderList() end
        end
    end

    function dd:SetOptions(options)
        self.options = options or {}
        if self.usesMenu then
            self:SetupMenu(function(_, root)
                -- lange Listen (Verzierungs-Stile samt Zonen-Motiven): Menue scrollt statt ueber den Bildschirm zu ragen
                if #self.options > 16 and type(root.SetScrollMode) == "function" then pcall(root.SetScrollMode, root, 16 * 20) end
                for _, o in ipairs(self.options) do
                    local value = o.value
                    local desc = root:CreateRadio(listText(self, o),
                        function() return self.value == value end,
                        function()
                            self:Select(value)
                            return _G.MenuResponse and _G.MenuResponse.Close or nil
                        end, value)
                    if desc then
                        if o.disabled and type(desc.SetEnabled) == "function" then desc:SetEnabled(false) end
                        if o.tooltip and type(desc.SetTooltip) == "function" then
                            desc:SetTooltip(function(tip)
                                tip:SetText(o.text, 1, 1, 1)
                                tip:AddLine(o.tooltip, nil, nil, nil, true)
                            end)
                        end
                    end
                end
            end)
        end
        self:Refresh()
    end

    function dd:SetValue(v)
        self.value = v
        self:Refresh()
    end

    function dd:GetValue() return self.value end

    --- Auswahl wie durch den Nutzer: gesperrte oder unbekannte Optionen werden abgewiesen (false)
    function dd:Select(v)
        for _, o in ipairs(self.options) do
            if o.value == v then
                if o.disabled then return false end
                self.value = v
                self:Refresh()
                if onSelect then onSelect(v) end
                return true
            end
        end
        return false
    end

    function dd:GetOptions() return self.options end

    --- Standardwert (Pfad wie bei Skin.Set oder Funktion): Eintrag in der Liste markiert, Tooltip-Zeile "Standard: <Eintrag>"
    function dd:SetDefault(src)
        self.defaultGetter = defaultGetter(self, src)
        self.defaultLines = function(b)
            local d = callDefault(b)
            if d == nil then return {} end
            for _, o in ipairs(b.options) do
                if o.value == d then return { ns.L.UI_DEFAULT_VALUE:format(o.text) } end
            end
            return {}
        end
        self:SetOptions(self.options)
    end

    function dd:SetActive(on)
        if on then self:Enable() else self:Disable() end
        partsAlpha(self.skin, on and 1 or 0.55)
    end
    return dd
end

-- Abschnitts-Ueberschrift (Hellgold) mit Bronze-Trennlinie (3-Slice, kleines Ornament links); fs.line ist ein Rahmen mit den Teilen
W.DIVIDER_H = 8
function W.Header(parent, text, width)
    local fs = W.Text(parent, "GameFontNormal", C.accent)
    fs:SetText(text)
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(W.DIVIDER_H)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", -2, 0)
    line:SetWidth(math.max(70, width or 200))
    line.parts = W.Slice3(line, "divider", W.DIVIDER_H, "ARTWORK", 0)
    fs.line = line
    return fs
end

-- Seiten-Bausteine (Delta Ausbau 1.1.0, E2) ---------------------------------------------------------------------------------
--- kleine Beschriftung (gedaempft) an Position x, y der Seite
function W.Label(page, text, x, y)
    local fs = W.Text(page, "GameFontNormalSmall", C.muted)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

--- mehrzeiliger Hinweistext (feste Breite, linksbuendig)
function W.Note(page, x, y, width, font, c)
    local fs = W.Text(page, font or "GameFontHighlightSmall", c or C.muted)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width or 740)
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    return fs
end

--- Haken an Position x, y mit optionalem Tooltip
function W.CheckAt(page, text, tip, x, y, onChange)
    local cb = W.Check(page, text, onChange)
    cb:SetPoint("TOPLEFT", x, y)
    if tip then W.Tooltip(cb, function() return text, tip end) end
    return cb
end

--- Regler an Position x, y (Breite 340) mit optionalem Tooltip
function W.SliderAt(page, text, tip, x, y, lo, hi, step, fmt, onChange)
    local s = W.Slider(page, text, lo, hi, step, 340, fmt, onChange)
    s:SetPoint("TOPLEFT", x, y)
    if tip then W.Tooltip(s, function() return text, tip end) end
    return s
end

-- Seite mit Bildlauf ---------------------------------------------------------------------------------------------
local SCROLL_STEP = 48
local SCROLL_BAR_W, SCROLL_ARROW, SCROLL_GAP = 14, 14, 4
W.SCROLL_BAR_W, W.SCROLL_ARROW = SCROLL_BAR_W, SCROLL_ARROW

--- Bildlauf-Flaeche: liefert scroll (ScrollFrame, vom Aufrufer verankert), content (Kind mit fester Breite, hierhin kommt der
--- Seiteninhalt) und bar (Rollleiste, nur sichtbar, wenn der Inhalt hoeher ist als die Flaeche). Mausrad rollt.
function W.ScrollPage(parent, contentWidth, contentHeight)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(contentWidth, contentHeight or 100)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)

    -- Rollleiste in Fenster-Optik: Rinne (scroll-track), kleiner Bronze-Daumen, Pfeil-Knoepfe oben/unten (je SCROLL_ARROW hoch,
    -- ausserhalb des Schiebebereichs); die Leiste steht SCROLL_GAP rechts neben der Flaeche
    local bar = CreateFrame("Slider", nil, scroll)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(SCROLL_BAR_W)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", SCROLL_GAP, -SCROLL_ARROW)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", SCROLL_GAP, SCROLL_ARROW)
    local track = skinTex(bar, "scroll-track", "BACKGROUND", 0)
    track:SetAllPoints(bar)
    local thumb = skinTex(bar, "scroll-thumb", "OVERLAY", 0)
    thumb:SetSize(SCROLL_BAR_W - 4, SCROLL_BAR_W - 3)
    bar:SetThumbTexture(thumb)
    bar.track, bar.thumb = track, thumb
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:Hide()

    local quiet = false
    -- scroll.onScroll (vom Aufrufer gesetzt) nach jeder Verschiebung, z. B. Loecher im Fensterhintergrund neu legen
    local function moved()
        if scroll.onScroll then xpcall(scroll.onScroll, geterrorhandler(), scroll) end
    end
    local function showAt(v)
        quiet = true
        bar:SetValue(v)
        quiet = false
        moved()
    end
    local function range()
        local r = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or 0
        if type(r) ~= "number" or r ~= r or r < 0 then r = 0 end
        return r
    end
    --- Rollleiste an den Inhalt anpassen (Hoehe geaendert, Seite gezeigt)
    function scroll.UpdateBar()
        local r = range()
        local cur = scroll:GetVerticalScroll() or 0
        if r <= 0 then
            if cur ~= 0 then
                scroll:SetVerticalScroll(0)
                moved()
            end
            bar:Hide()
            return
        end
        if cur > r then
            cur = r
            scroll:SetVerticalScroll(cur)
        end
        bar:SetMinMaxValues(0, r)
        showAt(cur)
        bar:Show()
    end
    scroll:SetScript("OnScrollRangeChanged", function() scroll.UpdateBar() end)
    scroll:SetScript("OnVerticalScroll", function(_, offset) if type(offset) == "number" then showAt(offset) end end)
    local function step(delta)
        local v = (scroll:GetVerticalScroll() or 0) - delta * SCROLL_STEP
        local r = range()
        if v > r then v = r end
        if v < 0 then v = 0 end
        scroll:SetVerticalScroll(v)
        showAt(v)
    end
    scroll:SetScript("OnMouseWheel", function(_, delta) step(delta) end)

    -- Pfeil-Knoepfe: ein Klick rollt wie ein Mausrad-Schritt
    local function arrow(file, point, relPoint, delta)
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(SCROLL_BAR_W, SCROLL_ARROW)
        b:SetPoint(point, bar, relPoint, 0, 0)
        local t = skinTex(b, file, "ARTWORK", 0)
        t:SetAllPoints(b)
        local hl = skinTex(b, file, "HIGHLIGHT", 0)
        hl:SetAllPoints(b)
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.3)
        b:SetScript("OnClick", function() step(delta) end)
        return b
    end
    bar.up = arrow("scroll-up", "BOTTOM", "TOP", 1)
    bar.down = arrow("scroll-down", "TOP", "BOTTOM", -1)
    bar:SetScript("OnValueChanged", function(_, v)
        if not quiet then
            scroll:SetVerticalScroll(v)
            moved()
        end
    end)
    scroll.content, scroll.bar = content, bar
    return scroll, content, bar
end

-- Rahmen-Waehler (Vertrag V2) ------------------------------------------------------------------------------------
local SCOPE_FRAMES = { "player", "target", "tot" }
local SCOPE_TEXT = { player = "UI_SCOPE_PLAYER", target = "UI_SCOPE_TARGET", tot = "UI_SCOPE_TOT" }
W.scopeChoice = {} -- Bereich -> Rahmen-Id der Wahl (nur diese Sitzung; fehlt = "Fuer alle Rahmen")

--- Rahmen-Waehler oben auf einer Seite (Hoehe 56, Inhalt der Seite beginnt darunter).
--- area: "liquid" | "portrait" | "text" | "font"; onChange(scope) nach jeder Wahl/Umschaltung; opts.frames: erlaubte Einzelrahmen
--- (Standard player, target, tot). "Fuer alle Rahmen" gibt es immer.
--- scope:GetFrame() (nil = fuer alle), scope:IsInherited() (Einzelrahmen ohne Eigenwert), scope:Refresh(), dazu
--- scope:Cfg() (wirksame Werte des gewaehlten Rahmens) und scope:Set(pfad, wert) (Skin.Set mit Rahmen, nur mit Eigenwert).
function W.FrameScope(page, area, onChange, opts)
    opts = opts or {}
    local Skin = ns.UnitFrameSkin
    local L = ns.L
    local ids = {}
    for _, id in ipairs(opts.frames or SCOPE_FRAMES) do
        if SCOPE_TEXT[id] then ids[#ids + 1] = id end
    end
    local allowed = {}
    for _, id in ipairs(ids) do allowed[id] = true end

    local scope = CreateFrame("Frame", nil, page)
    scope:SetSize(740, 56)
    scope:SetPoint("TOPLEFT", 0, 0)
    scope.area, scope.ids = area, ids

    local cap = W.Text(scope, "GameFontNormalSmall", C.muted)
    cap:SetPoint("TOPLEFT", 4, 0)
    cap:SetText(L.UI_SCOPE_LABEL)

    local dd = W.Dropdown(scope, 210, function(v)
        W.scopeChoice[area] = (v ~= "all") and v or nil
        scope:Refresh()
        if onChange then onChange(scope) end
    end)
    dd:SetPoint("TOPLEFT", 4, -16)
    local options = { { value = "all", text = L.UI_SCOPE_ALL } }
    for _, id in ipairs(ids) do options[#options + 1] = { value = id, text = L[SCOPE_TEXT[id]] } end
    dd:SetOptions(options)
    W.Tooltip(dd, function() return L.UI_SCOPE_LABEL, L.UI_SCOPE_PICK_TIP end)

    local own = W.Check(scope, L.UI_SCOPE_OWN, function(on)
        local f = scope:GetFrame()
        if f then Skin.SetOverride(f, area, on) end
        scope:Refresh()
        if onChange then onChange(scope) end
    end)
    own:SetPoint("TOPLEFT", 240, -17)
    W.Tooltip(own, function() return L.UI_SCOPE_OWN, L.UI_SCOPE_OWN_TIP end)

    local reset = W.Button(scope, L.UI_SCOPE_RESET, 190, function()
        local f = scope:GetFrame()
        if f then Skin.SetOverride(f, area, false) end
        scope:Refresh()
        if onChange then onChange(scope) end
    end)
    reset:SetPoint("TOPLEFT", 548, -16)
    W.Tooltip(reset, function() return L.UI_SCOPE_RESET, L.UI_SCOPE_RESET_TIP end)

    local hint = W.Note(scope, 4, -42, 736, "GameFontHighlightSmall", C.muted)

    scope.dropdown, scope.own, scope.reset, scope.hint = dd, own, reset, hint

    function scope:GetFrame()
        local f = W.scopeChoice[area]
        if f and allowed[f] then return f end
        return nil
    end
    function scope:IsInherited()
        local f = self:GetFrame()
        return f ~= nil and not Skin.HasOverride(f, area)
    end
    function scope:Cfg() return Skin.GetConfig(self:GetFrame()) end
    function scope:Set(path, value)
        if self:IsInherited() then return nil end
        return Skin.Set(path, value, self:GetFrame())
    end
    function scope:Refresh()
        local f = self:GetFrame()
        dd:SetValue(f or "all")
        own:SetShown(f ~= nil)
        reset:SetShown(f ~= nil)
        if f then
            local has = Skin.HasOverride(f, area) and true or false
            own:SetValue(has)
            reset:SetEnabled(has)
            hint:SetText(has and L.UI_SCOPE_HINT_OWN or L.UI_SCOPE_HINT_INHERIT)
        else
            hint:SetText(L.UI_SCOPE_HINT_ALL)
        end
    end

    scope:Refresh()
    return scope
end

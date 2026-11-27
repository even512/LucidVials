-- Reiter "Schrift" (Delta "Ausbau 1.1.0", E3, Seite "font", Reihenfolge 50): je Textelement (Name, Stufe, Lebenswert, Ressourcenwert,
-- XP-Wert) Schrift, Groesse, Kontur und Schatten, oben der Rahmen-Waehler (W.FrameScope, Vertrag V2). Jede Zeile zeigt ein
-- Schriftmuster, gezeichnet mit derselben Funktion wie die echten Texte (ns.Fonts.Apply), also genau so, wie es im Rahmen aussieht.
-- Alle Werte gehen ueber Skin.Set("font.<element>.<feld>", wert, rahmen) (Pruefung, Profil, sofort anwenden). Bei einem Einzelrahmen
-- ohne Eigenwert sind die Regler grau und zeigen den geerbten Wert; der XP-Wert gilt nur unter "fuer alle".
-- Namen fremder Schriften (LibSharedMedia) gehen nur ueber W.Plain in Texte und Menues.
-- Der Grund der Muster folgt der Hintergrund-Wahl der Vorschau (dunkel / hell / Spielwelt mit Loch im Fensterhintergrund).
local _, ns = ...
local Skin, Fonts = ns.UnitFrameSkin, ns.Fonts
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local Tab = {}
Config.Font = Tab

-- Zeilen: Element, Beschriftung (Locale-Schluessel), Beispieltext (Locale-Schluessel)
Tab.ROWS = {
    { "name", "UI_FONT_EL_NAME", "UI_FONT_SAMPLE_NAME" },
    { "level", "UI_FONT_EL_LEVEL", "UI_FONT_SAMPLE_LEVEL" },
    { "health", "UI_FONT_EL_HEALTH", "UI_FONT_SAMPLE_NUMBERS" },
    { "power", "UI_FONT_EL_POWER", "UI_FONT_SAMPLE_NUMBERS" },
    { "xp", "UI_FONT_EL_XP", "UI_FONT_SAMPLE_NUMBERS" },
}
Tab.ROW_H = 70
-- Schriftmuster-Feld je Zeile (Seitenkoordinaten) und sein Grund je Hintergrund-Wahl der Vorschau (Schrift bleibt in Originalfarbe;
-- "world" = kein Grund, der Fensterhintergrund hat dort ein Loch)
Tab.SAMPLE_X, Tab.SAMPLE_W, Tab.SAMPLE_H = 240, 500, 24
-- Gleiche Farben wie die Buehne der Vorschau (eine Quelle: ns.Preview.BACKGROUNDS im Kern); ohne Kern die gleichen Werte als Ersatz
local PREVIEW_BG = ns.Preview and ns.Preview.BACKGROUNDS
Tab.SAMPLE_BG = {
    dark = PREVIEW_BG and PREVIEW_BG.dark or { 0.045, 0.035, 0.03, 0.92 },
    light = PREVIEW_BG and PREVIEW_BG.light or { 1, 1, 1, 1 },
}
Tab.TOP = -64 -- unter dem Rahmen-Waehler (Hoehe 56)
-- Regler: Stufe 5 steht fuer "Auto" (Groesse 0), darueber die Pixelgroesse
Tab.SIZE_AUTO_STEP = Fonts.SIZE.min - 1

local function setStatus(page, text, c)
    page.status:SetText(text or "")
    W.Color(page.status, c or C.muted)
end

local function outlineText(key)
    return ({ none = L.UI_FONT_OUTLINE_NONE, thin = L.UI_FONT_OUTLINE_THIN, thick = L.UI_FONT_OUTLINE_THICK })[key]
end

local function sizeText(v)
    if v <= Tab.SIZE_AUTO_STEP then return L.UI_FONT_SIZE_AUTO end
    return L.UI_FONT_SIZE_PX:format(v)
end

--- Rahmen, auf den sich die Zeile bezieht: der Wahl des Waehlers; der XP-Wert gilt nur "fuer alle"
local function targetFrame(page, element)
    if element == "xp" then return nil end
    return page.scope:GetFrame()
end

--- Wert ueber die Profil-Pruefung setzen, Anzeige nachziehen
local function set(page, element, field, value)
    if Skin.Set("font." .. element .. "." .. field, value, targetFrame(page, element)) then
        setStatus(page, "")
    else
        setStatus(page, L.UI_FONT_INVALID, C.warn)
    end
    Config.Refresh()
end

local function buildRow(page, i, def)
    local element, labelKey, sampleKey = def[1], def[2], def[3]
    local y = Tab.TOP - (i - 1) * Tab.ROW_H
    local row = { element = element }

    row.title = W.Text(page, "GameFontNormal", C.accent)
    row.title:SetPoint("TOPLEFT", 0, y - 3)
    row.title:SetText(L[labelKey])

    -- Schriftmuster auf dem Grund der Vorschau-Wahl (dunkel / hell / Spielwelt = durchsichtig, Loch im Fensterhintergrund)
    row.sampleBox = CreateFrame("Frame", nil, page)
    row.sampleBox:SetSize(Tab.SAMPLE_W, Tab.SAMPLE_H)
    row.sampleBox:SetPoint("TOPLEFT", Tab.SAMPLE_X, y)
    row.sampleBg = W.Fill(row.sampleBox, Tab.SAMPLE_BG.dark)
    W.Border(row.sampleBox)
    row.sample = W.Text(row.sampleBox, "GameFontHighlight", Skin.NAME.color)
    row.sample:SetPoint("LEFT", 10, 0)
    row.sample:SetText(L[sampleKey])

    row.face = W.Dropdown(page, 220, function(v) set(page, element, "face", v) end)
    row.face:SetPoint("TOPLEFT", 0, y - 28)
    W.Tooltip(row.face, function() return L[labelKey], L.UI_FONT_FACE_TIP end)

    row.outline = W.Dropdown(page, 110, function(v) set(page, element, "outline", v) end)
    row.outline:SetPoint("TOPLEFT", 240, y - 28)
    local opts = {}
    for _, key in ipairs(Fonts.OUTLINES) do opts[#opts + 1] = { value = key, text = outlineText(key) } end
    row.outline:SetOptions(opts)
    W.Tooltip(row.outline, function() return L[labelKey], L.UI_FONT_OUTLINE_TIP end)

    row.shadow = W.Check(page, L.UI_FONT_SHADOW, function(v) set(page, element, "shadow", v) end)
    row.shadow:SetPoint("TOPLEFT", 366, y - 28)
    W.Tooltip(row.shadow, function() return L.UI_FONT_SHADOW, L.UI_FONT_SHADOW_TIP end)

    row.size = W.Slider(page, L.UI_FONT_SIZE, Tab.SIZE_AUTO_STEP, Fonts.SIZE.max, 1, 250, sizeText, function(v)
        set(page, element, "size", v <= Tab.SIZE_AUTO_STEP and 0 or v)
    end)
    row.size:SetPoint("TOPLEFT", 490, y - 24)
    W.Tooltip(row.size, function() return L.UI_FONT_SIZE, L.UI_FONT_SIZE_TIP end)
    -- Standardwerte aus den Schema-Defaults; Groesse 0 = Auto liegt am linken Ende (Stufe SIZE_AUTO_STEP)
    row.face:SetDefault("font." .. element .. ".face")
    row.outline:SetDefault("font." .. element .. ".outline")
    row.shadow:SetDefault("font." .. element .. ".shadow")
    row.size:SetDefault("font." .. element .. ".size", function(v) return v == 0 and Tab.SIZE_AUTO_STEP or v end)
    return row
end

--- Schriftliste in die Auswahl der Zeilen schreiben (nur, wenn sich die Liste geaendert hat, z. B. ein LSM-Addon dazukam)
local function syncList(page, list)
    if page.listRef == list then return end
    page.listRef = list
    local opts = {}
    for _, f in ipairs(list) do opts[#opts + 1] = { value = f.name, text = W.Plain(f.name) } end
    for _, row in ipairs(page.rows) do row.face:SetOptions(opts) end
end

--- Grund der Schriftmuster nach der Hintergrund-Wahl der Vorschau
local function paintSamples(page, mode)
    local c = Tab.SAMPLE_BG[mode]
    for _, row in ipairs(page.rows or {}) do
        if c then
            row.sampleBg:SetColorTexture(c[1], c[2], c[3], c[4])
            row.sampleBg:Show()
        else
            row.sampleBg:Hide()
        end
    end
    page.sampleMode = mode
end
Tab.PaintSamples = paintSamples

local function refreshRow(page, row, frame, editable)
    local element = row.element
    local spec = Fonts.Spec(element, element == "xp" and "xp" or frame)
    local known = Fonts.IsKnown(spec.face)
    row.face.placeholder = (not known) and W.Plain(L.UI_FONT_MISSING:format(spec.face)) or nil
    row.face:SetValue(spec.face)
    row.outline:SetValue(spec.outline)
    row.shadow:SetValue(spec.shadow)
    row.size:SetValue(spec.size == 0 and Tab.SIZE_AUTO_STEP or spec.size)
    row.face:SetActive(editable)
    row.outline:SetActive(editable)
    row.shadow:SetActive(editable)
    row.size:SetActive(editable)
    -- Muster: dieselbe Funktion wie die echten Texte (Auto-Groesse: heutige Groesse des Rahmens)
    Fonts.Apply(row.sample, element, element == "xp" and "xp" or frame, Fonts.AUTO_SIZE[element])
    local c = Skin.NAME.color
    W.Color(row.sample, editable and c or { c[1] * 0.7, c[2] * 0.7, c[3] * 0.7 })
end

Config.RegisterPage("font", {
    label = "UI_TAB_FONT",
    order = 50,
    build = function(page)
        Tab.page = page
        page.scope = W.FrameScope(page, "font", function() Config.Refresh() end)
        if type(page.scope.SetPoint) == "function" then page.scope:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0) end
        page.rows = {}
        for i, def in ipairs(Tab.ROWS) do
            page.rows[i] = buildRow(page, i, def)
        end
        local yEnd = Tab.TOP - #Tab.ROWS * Tab.ROW_H
        page.note = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.note:SetPoint("TOPLEFT", 4, yEnd - 2)
        page.note:SetWidth(730)
        if page.note.SetJustifyH then page.note:SetJustifyH("LEFT") end
        page.note:SetText(L.UI_FONT_HINT)
        page.xpNote = W.Text(page, "GameFontNormalSmall", C.warn)
        page.xpNote:SetPoint("TOPLEFT", 4, yEnd - 40)
        page.xpNote:SetWidth(730)
        if page.xpNote.SetJustifyH then page.xpNote:SetJustifyH("LEFT") end
        page.status = W.Text(page, "GameFontNormalSmall", C.muted)
        page.status:SetPoint("TOPLEFT", 4, yEnd - 60)
        page.status:SetWidth(730)
        if page.status.SetJustifyH then page.status:SetJustifyH("LEFT") end
    end,
    refresh = function(page)
        local scope = page.scope
        if type(scope.Refresh) == "function" then scope:Refresh() end
        local frame = scope:GetFrame()
        local inherited = frame ~= nil and scope:IsInherited()
        syncList(page, Fonts.List())
        for _, row in ipairs(page.rows) do
            local editable
            if row.element == "xp" then editable = frame == nil else editable = not inherited end
            refreshRow(page, row, frame, editable)
        end
        page.xpNote:SetText(frame ~= nil and L.UI_FONT_XP_ALL_ONLY or "")
        paintSamples(page, Config.PreviewBackground())
    end,
    -- Hintergrund-Wahl der Vorschau: Grund der Muster sofort umstellen
    background = function(page, mode) paintSamples(page, mode) end,
    -- "Spielwelt": die Musterfelder sind Loecher bis in die Spielwelt
    holes = function(page)
        local out = {}
        for i = 1, #(page.rows or {}) do
            out[#out + 1] = { Tab.SAMPLE_X, -(Tab.TOP - (i - 1) * Tab.ROW_H), Tab.SAMPLE_W, Tab.SAMPLE_H }
        end
        return out
    end,
})

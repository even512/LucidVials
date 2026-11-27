-- Reiter "Texte & Zahlen" (Ausbau 1.1.0, E4): je Roehre (Leben, Ressource) Format, Darstellung und Wertfarbe der
-- Dauer-Zahlen (modules/UnitFrames/Text.lua), oben der Rahmen-Waehler (W.FrameScope: fuer alle oder je Rahmen mit eigenen
-- Einstellungen); die XP-Formate nur unter "Fuer alle Rahmen". Darstellung und Wertfarbe sind bei "Aus"/"Wie Blizzard"
-- ausgegraut; "Lage der Zahlen" (Wie Blizzard / Mittig in der Roehre) gilt nur bei "Wie Blizzard". Alle Werte gehen ueber Skin.Set (Pruefung, Profil, sofort, kein /reload); die Vorschau steht in der Spalte rechts
-- (UI/ConfigPreview.lua). Fasst keine Blizzard-Frames an; im Kampf bedienbar.
local _, ns = ...
local Skin = ns.UnitFrameSkin
local Text = ns.UnitText
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local Tab = {}
Config.Text = Tab

Tab.FORMAT_LABELS = { off = "UI_TEXT_FMT_OFF", blizzard = "UI_TEXT_FMT_BLIZZARD", pattern = "UI_TEXT_FMT_PATTERN",
    short = "UI_TEXT_FMT_SHORT", full = "UI_TEXT_FMT_FULL", percent = "UI_TEXT_FMT_PERCENT", numPercent = "UI_TEXT_FMT_NUMPERCENT",
    curmaxShort = "UI_TEXT_FMT_CURMAXSHORT", curmaxFull = "UI_TEXT_FMT_CURMAXFULL", deficit = "UI_TEXT_FMT_DEFICIT" }
Tab.DISPLAY_LABELS = { blizzard = "UI_TEXT_DSP_BLIZZARD", glass = "UI_TEXT_DSP_GLASS", float = "UI_TEXT_DSP_FLOAT",
    engraved = "UI_TEXT_DSP_ENGRAVED" }
Tab.COLOR_LABELS = { light = "UI_TEXT_COL_LIGHT", white = "UI_TEXT_COL_WHITE", gold = "UI_TEXT_COL_GOLD",
    curve = "UI_TEXT_COL_CURVE" }
Tab.PLACE_LABELS = { blizzard = "UI_TEXT_PLC_BLIZZARD", center = "UI_TEXT_PLC_CENTER" }
Tab.XP_LABELS = { curmax = "UI_TEXT_XP_CURMAX", percent = "UI_TEXT_XP_PERCENT", remaining = "UI_TEXT_XP_REMAINING",
    rested = "UI_TEXT_XP_RESTED" }
Tab.ROWS = { health = { head = "UI_TEXT_HEAD_HEALTH", y = -64 }, power = { head = "UI_TEXT_HEAD_POWER", y = -140 } }

local function options(list, labels)
    local out = {}
    for _, k in ipairs(list) do out[#out + 1] = { value = k, text = L[labels[k]] } end
    return out
end

local function setStatus(page, text, c)
    page.status:SetText(text or "")
    W.Color(page.status, c or C.muted)
end

--- gewaehlter Rahmen des Rahmen-Waehlers (nil = fuer alle)
function Tab.Frame(page)
    return page.scope and page.scope:GetFrame() or nil
end

--- Wert setzen (path z. B. "text.health.format") fuer den gewaehlten Rahmen bzw. fuer alle; Anzeige nachziehen
function Tab.Set(page, path, value)
    if Skin.Set(path, value, Tab.Frame(page)) then
        setStatus(page, "")
    else
        setStatus(page, L.FRAMES_VALUE_INVALID, C.warn)
    end
    Config.Refresh()
end

local function label(page, text, x, y)
    local fs = W.Text(page, "GameFontNormalSmall", C.muted)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function dropdown(page, kind, fieldName, text, tip, x, y, width, list, labels)
    label(page, text, x, y)
    local dd = W.Dropdown(page, width, function(v) Tab.Set(page, "text." .. kind .. "." .. fieldName, v) end)
    dd:SetPoint("TOPLEFT", x, y - 16)
    dd:SetOptions(options(list, labels))
    dd:SetDefault("text." .. kind .. "." .. fieldName)
    W.Tooltip(dd, function() return text, tip end)
    return dd
end

local function buildRow(page, kind)
    local R = Tab.ROWS[kind]
    local h = W.Header(page, L[R.head], 740)
    h:SetPoint("TOPLEFT", 0, R.y)
    local y = R.y - 24
    page[kind] = {
        format = dropdown(page, kind, "format", L.UI_TEXT_FORMAT, L.UI_TEXT_FORMAT_TIP, 4, y, 175, Text.FORMATS,
            Tab.FORMAT_LABELS),
        place = dropdown(page, kind, "place", L.UI_TEXT_PLACE, L.UI_TEXT_PLACE_TIP, 189, y, 175, Text.PLACES,
            Tab.PLACE_LABELS),
        display = dropdown(page, kind, "display", L.UI_TEXT_DISPLAY, L.UI_TEXT_DISPLAY_TIP, 374, y, 175, Text.DISPLAYS,
            Tab.DISPLAY_LABELS),
        color = dropdown(page, kind, "color", L.UI_TEXT_COLOR, L.UI_TEXT_COLOR_TIP, 559, y, 175, Text.COLOR_KEYS,
            Tab.COLOR_LABELS),
    }
end

Config.RegisterPage("text", {
    label = "UI_TAB_TEXT",
    order = 40,
    build = function(page)
        Tab.page = page
        page.scope = W.FrameScope(page, "text", function() Config.Refresh() end)
        page.scope:SetPoint("TOPLEFT", 0, 0)
        buildRow(page, "health")
        buildRow(page, "power")

        local hx = W.Header(page, L.UI_TEXT_HEAD_XP, 740)
        hx:SetPoint("TOPLEFT", 0, -216)
        page.xp = {}
        for i, k in ipairs(Text.XP_PARTS) do
            local cb = W.Check(page, L[Tab.XP_LABELS[k]], function(v) Tab.Set(page, "text.xp." .. k, v) end)
            cb:SetPoint("TOPLEFT", (i - 1) * 185, -240)
            cb:SetDefault("text.xp." .. k)
            page.xp[k] = cb
        end
        page.xpNote = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.xpNote:SetPoint("TOPLEFT", 4, -268)
        page.xpNote:SetWidth(740)
        if page.xpNote.SetJustifyH then page.xpNote:SetJustifyH("LEFT") end
        page.xpNote:SetText(L.UI_TEXT_XP_NOTE)

        page.note = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.note:SetPoint("TOPLEFT", 4, -296)
        page.note:SetWidth(740)
        if page.note.SetJustifyH then page.note:SetJustifyH("LEFT") end
        page.note:SetText(L.UI_TEXT_NOTE)

        page.status = W.Text(page, "GameFontNormalSmall", C.muted)
        page.status:SetPoint("TOPLEFT", 164, -350)
        page.status:SetWidth(576)
        if page.status.SetJustifyH then page.status:SetJustifyH("LEFT") end
    end,
    refresh = function(page)
        if page.scope.Refresh then page.scope:Refresh() end
        local frameId = Tab.Frame(page)
        local editable = frameId == nil or not page.scope:IsInherited()
        local cfg = Text.Config(frameId)
        for _, kind in ipairs(Text.BARS) do
            local row, c = page[kind], cfg[kind]
            row.format:SetValue(c.format)
            row.display:SetValue(c.display)
            row.color:SetValue(c.color)
            row.place:SetValue(c.place)
            local shows = Text.Shows(c.format)
            row.format:SetActive(editable)
            row.place:SetActive(editable and c.format == "blizzard")
            row.display:SetActive(editable and shows)
            row.color:SetActive(editable and shows and c.display ~= "engraved") -- Gravur: feste Aetz-Farben
        end
        local all = frameId == nil
        for _, k in ipairs(Text.XP_PARTS) do
            local cb = page.xp[k]
            cb:SetValue(cfg.xp[k])
            cb:SetActive(all)
            cb:SetShown(all)
        end
        page.xpNote:SetShown(not all)
    end,
    -- Fenster schliesst: ein laufender Zahlen-Test (Vorschau-Spalte) endet
    onClose = function() Text.StopTest() end,
})

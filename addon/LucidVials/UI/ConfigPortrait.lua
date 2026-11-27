-- Reiter "Portrait" (Delta "Ausbau 1.1.0", E5, Seiten-ID "portrait", Reihenfolge 30): Stil der Portraits (statisch, lebendes Gemaelde,
-- im Kolben versunken, ggf. reagierendes Modell) und Staerke der Effekte, "fuer alle" oder je Rahmen (nur Spieler und Ziel, der
-- Rahmen-Waehler W.FrameScope kommt aus UI/ConfigWidgets.lua). Alle Werte gehen ueber Skin.Set (Pruefung, Profil, sofort anwenden);
-- die Vorschau steht in der Spalte rechts (UI/ConfigPreview.lua). Fasst keine Blizzard-Frames an; im Kampf bedienbar.
local _, ns = ...
local Skin, Portrait = ns.UnitFrameSkin, ns.UnitPortrait
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local Tab = {}
Config.Portrait = Tab

Tab.AREA = "portrait"
Tab.FRAMES = { "player", "target" } -- das Ziel des Ziels bleibt immer statisch
Tab.LABEL = { static = "PORTRAIT_STYLE_STATIC", painting = "PORTRAIT_STYLE_PAINTING", submerged = "PORTRAIT_STYLE_SUBMERGED",
    model = "PORTRAIT_STYLE_MODEL", modelplain = "PORTRAIT_STYLE_MODELPLAIN" }
Tab.DESC = { static = "UI_PORTRAIT_DESC_STATIC", painting = "UI_PORTRAIT_DESC_PAINTING", submerged = "UI_PORTRAIT_DESC_SUBMERGED",
    model = "UI_PORTRAIT_DESC_MODEL", modelplain = "UI_PORTRAIT_DESC_MODELPLAIN" }

local function pctFmt(v) return ("%d %%"):format(v) end

local function setStatus(page, text, c)
    page.status:SetText(text or "")
    W.Color(page.status, c or C.muted)
end

--- Wert ueber die Profil-Pruefung setzen (Rahmen aus dem Waehler; nil = fuer alle), Anzeige nachziehen
local function set(page, path, value)
    if Skin.Set(path, value, page.scope:GetFrame()) then
        setStatus(page, "")
    else
        setStatus(page, L.FRAMES_VALUE_INVALID, C.warn)
    end
    Config.Refresh()
end

--- Auswahlliste: angemeldete Stile; ein gespeicherter, aber nicht angemeldeter Stil (z. B. Modell ohne Modul) bleibt sichtbar, gesperrt
local function styleOptions(current)
    local out, seen = {}, {}
    for _, key in ipairs(Portrait.StyleKeys()) do
        out[#out + 1] = { value = key, text = L[Tab.LABEL[key]] }
        seen[key] = true
    end
    if current and not seen[current] and Tab.LABEL[current] then
        out[#out + 1] = { value = current, text = L[Tab.LABEL[current]], disabled = true }
    end
    return out
end

local function signature(options)
    local keys = {}
    for _, o in ipairs(options) do keys[#keys + 1] = o.value .. (o.disabled and "!" or "") end
    return table.concat(keys, ",")
end

--- Modell gewaehlt, aber gerade im Rueckfall (z. B. fremde Einheit in einer Instanz): Zusatzzeile mit den betroffenen Rahmen
local FRAME_LABEL = { player = "UI_FRAMES_PLAYER", target = "UI_FRAMES_TARGET" }
local FALLBACK_NOTE = { model = "UI_PORTRAIT_MODEL_FALLBACK", modelplain = "UI_PORTRAIT_MODELPLAIN_FALLBACK" }

--- Rueckfall: "model" laeuft dann als Gemaelde, "modelplain" zeigt im eigenen Rahmen das statische Bild (Zustand still)
local function inFallback(id, style)
    if style == "modelplain" then
        local sk = Skin.Get(id)
        local s = sk and sk.pfx and sk.pfx.s and sk.pfx.s.model
        return Portrait.ActiveKey(id) == "modelplain" and s ~= nil and s.active == true and s.still == true
    end
    return Portrait.ActiveKey(id) == "painting"
end

function Tab.FallbackNote(style, frame)
    if not FALLBACK_NOTE[style] or not Portrait.GetStyle(style) then return "" end
    local list = {}
    for _, id in ipairs(Tab.FRAMES) do
        local ok, c = pcall(Skin.GetFrameConfig, id)
        local own = ok and type(c) == "table" and type(c.portrait) == "table" and c.portrait.style or nil
        if (frame == nil or frame == id) and own == style and inFallback(id, style) then
            list[#list + 1] = L[FRAME_LABEL[id]]
        end
    end
    if #list == 0 then return "" end
    return "\n" .. L[FALLBACK_NOTE[style]]:format(table.concat(list, ", "))
end

Config.RegisterPage("portrait", {
    label = "UI_TAB_PORTRAIT",
    order = 30,
    build = function(page)
        Tab.page = page
        page.scope = W.FrameScope(page, Tab.AREA, function() Config.Refresh() end, { frames = Tab.FRAMES })

        local h1 = W.Header(page, L.UI_PORTRAIT_HEAD_STYLE, 740)
        h1:SetPoint("TOPLEFT", 0, -66)
        local lbl = W.Text(page, "GameFontNormalSmall", C.muted)
        lbl:SetPoint("TOPLEFT", 4, -92)
        lbl:SetText(L.UI_PORTRAIT_STYLE)
        page.style = W.Dropdown(page, 260, function(v) set(page, "portrait.style", v) end)
        page.style:SetPoint("TOPLEFT", 4, -108)
        W.Tooltip(page.style, function() return L.UI_PORTRAIT_STYLE, L.UI_PORTRAIT_STYLE_TIP end)
        page.desc = W.Text(page, "GameFontHighlightSmall", C.text)
        page.desc:SetPoint("TOPLEFT", 4, -140)
        page.desc:SetWidth(700)
        if page.desc.SetJustifyH then page.desc:SetJustifyH("LEFT") end

        page.intensity = W.Slider(page, L.UI_PORTRAIT_INTENSITY, 0, 100, 5, 340, pctFmt,
            function(v) set(page, "portrait.intensity", v / 100) end)
        page.intensity:SetPoint("TOPLEFT", 4, -196)
        W.Tooltip(page.intensity, function() return L.UI_PORTRAIT_INTENSITY, L.UI_PORTRAIT_INTENSITY_TIP end)
        -- Standardwerte aus den Schema-Defaults
        page.style:SetDefault("portrait.style")
        page.intensity:SetDefault("portrait.intensity", function(v) return math.floor(v * 100 + 0.5) end)

        page.status = W.Text(page, "GameFontNormalSmall", C.muted)
        page.status:SetPoint("TOPLEFT", 4, -246)
        page.status:SetWidth(700)
        if page.status.SetJustifyH then page.status:SetJustifyH("LEFT") end
        page.note = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.note:SetPoint("TOPLEFT", 4, -274)
        page.note:SetWidth(700)
        if page.note.SetJustifyH then page.note:SetJustifyH("LEFT") end
        page.note:SetText(L.UI_PORTRAIT_NOTE)
    end,
    refresh = function(page)
        local frame = page.scope:GetFrame()
        page.scope:Refresh()
        local cfg = Skin.GetConfig(frame)
        local pc = type(cfg) == "table" and type(cfg.portrait) == "table" and cfg.portrait or Portrait.Defaults()
        local options = styleOptions(pc.style)
        local sig = signature(options)
        if page.sig ~= sig then
            page.sig = sig
            page.style:SetOptions(options)
        end
        page.style:SetValue(pc.style)
        page.intensity:SetValue(math.floor(pc.intensity * 100 + 0.5))
        local own = not page.scope:IsInherited()
        page.style:SetActive(own)
        page.intensity:SetActive(own and pc.style ~= "static")
        page.desc:SetText(L[Tab.DESC[pc.style] or Tab.DESC.static] .. Tab.FallbackNote(pc.style, frame))
    end,
    -- Fenster schliesst: ein laufender Portrait-Test (Vorschau-Spalte) endet
    onClose = function()
        pcall(Portrait.StopTest)
    end,
})

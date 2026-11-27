-- Reiter "Fluessigkeit" (Delta Ausbau 1.1.0, E2): Darstellung, Gleiten, Schadensspur, Effekte, Debuff-Toenung und Schwappen.
-- Oben der Rahmen-Waehler: die Darstellung gilt fuer alle Rahmen oder je Rahmen einzeln (Eigenwert, sonst erbt der Rahmen
-- "fuer alle" - dann sind die Regler grau und zeigen den geerbten Wert). Schwappen ist eine gemeinsame Physik: bei einem
-- Einzelrahmen sind Haken und Regler grau mit Hinweis. Alle Werte gehen ueber Skin.Set (sofort wirksam, kein /reload).
local _, ns = ...
local Skin = ns.UnitFrameSkin
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local function pctFmt(v) return ("%d %%"):format(v) end
local function pct100(x) return math.floor(x * 100 + 0.5) end

local function report(page, ok)
    if ok then
        page.status:SetText("")
    else
        page.status:SetText(L.FRAMES_VALUE_INVALID)
        W.Color(page.status, C.warn)
    end
    Config.Refresh()
end

--- Darstellungswert des gewaehlten Rahmens (bzw. "fuer alle") setzen
local function setLiquid(page, field, value)
    report(page, page.scope:Set("liquid." .. field, value))
end

--- globaler Wert (Schwappen): immer "fuer alle", auch wenn der Rahmen-Waehler auf einem Rahmen steht (dann sind die Regler grau)
local function setGlobal(page, field, value)
    report(page, Skin.Set("liquid." .. field, value))
end

Config.RegisterPage("liquid", {
    label = "UI_TAB_LIQUID",
    order = 20,
    height = 356,
    build = function(page)
        page.scope = W.FrameScope(page, "liquid", function() Config.Refresh() end)

        local h1 = W.Header(page, L.UI_FRAMES_HEAD_LIQUID, 740)
        h1:SetPoint("TOPLEFT", 0, -66)
        W.Label(page, L.UI_FRAMES_STYLE, 4, -92)
        page.style = W.Dropdown(page, 220, function(v) setLiquid(page, "style", v) end)
        page.style:SetPoint("TOPLEFT", 4, -108)
        page.style:SetOptions({
            { value = "piston", text = L.FRAMES_STYLE_PISTON },
            { value = "edge", text = L.FRAMES_STYLE_EDGE },
        })
        W.Tooltip(page.style, function() return L.UI_FRAMES_STYLE, L.UI_FRAMES_STYLE_TIP end)
        page.smooth = W.CheckAt(page, L.UI_FRAMES_SMOOTH, L.UI_FRAMES_SMOOTH_TIP, 394, -96,
            function(v) setLiquid(page, "smooth", v) end)
        page.trail = W.CheckAt(page, L.UI_FRAMES_TRAIL, L.UI_FRAMES_TRAIL_TIP, 570, -96,
            function(v) setLiquid(page, "trail", v) end)
        page.fx = W.CheckAt(page, L.UI_FRAMES_FX, L.UI_FRAMES_FX_TIP, 394, -122,
            function(v) setLiquid(page, "fx", v) end)
        page.debuffs = W.CheckAt(page, L.UI_FRAMES_DEBUFFS, L.UI_FRAMES_DEBUFFS_TIP, 570, -122,
            function(v) setLiquid(page, "debuffs", v) end)
        -- Regeneration deutlich zeigen: eine Einstellung fuer alle (wirkt nur an der eigenen Mana-Roehre)
        page.regenPulse = W.CheckAt(page, L.UI_LIQUID_REGEN, L.UI_LIQUID_REGEN_TIP, 394, -148,
            function(v) setGlobal(page, "regenPulse", v) end)

        local h2 = W.Header(page, L.UI_LIQUID_HEAD_SLOSH, 740)
        h2:SetPoint("TOPLEFT", 0, -188)
        page.sloshNote = W.Note(page, 4, -212, 736, "GameFontNormalSmall", C.warn)
        page.slosh = W.CheckAt(page, L.UI_FRAMES_SLOSH, L.UI_FRAMES_SLOSH_TIP, 0, -238,
            function(v) setGlobal(page, "slosh", v) end)
        page.strength = W.SliderAt(page, L.UI_FRAMES_STRENGTH, L.UI_FRAMES_STRENGTH_TIP, 4, -268, 0, 100, 5, pctFmt,
            function(v) setGlobal(page, "sloshStrength", v / 100) end)
        page.damping = W.SliderAt(page, L.UI_FRAMES_DAMPING, L.UI_FRAMES_DAMPING_TIP, 394, -268, 0, 100, 5, pctFmt,
            function(v) setGlobal(page, "sloshDamping", v / 100) end)

        page.status = W.Note(page, 4, -326, 736, "GameFontNormalSmall", C.muted)

        -- Standardwerte aus den Schema-Defaults (je Rahmen starten Eigenwerte mit denselben Werten; Schwappen gilt global)
        page.style:SetDefault("liquid.style")
        for _, key in ipairs({ "smooth", "trail", "fx", "debuffs", "slosh", "regenPulse" }) do
            page[key]:SetDefault("liquid." .. key)
        end
        page.strength:SetDefault("liquid.sloshStrength", pct100)
        page.damping:SetDefault("liquid.sloshDamping", pct100)
    end,
    refresh = function(page)
        local scope = page.scope
        scope:Refresh()
        local frame = scope:GetFrame()
        local mine = not scope:IsInherited() -- Eigenwert oder "fuer alle": bedienbar; geerbt: grau mit dem geerbten Wert
        local liquid = Skin.GetConfig(frame).liquid
        page.style:SetValue(liquid.style)
        page.smooth:SetValue(liquid.smooth)
        page.trail:SetValue(liquid.trail)
        page.fx:SetValue(liquid.fx)
        page.debuffs:SetValue(liquid.debuffs)
        for _, key in ipairs({ "smooth", "trail", "fx", "debuffs" }) do page[key]:SetActive(mine) end
        page.style:SetActive(mine)

        -- Schwappen: immer der globale Wert; nur bei "fuer alle" bedienbar
        local g = Skin.GetConfig().liquid
        local all = frame == nil
        page.regenPulse:SetValue(g.regenPulse)
        page.slosh:SetValue(g.slosh)
        page.strength:SetValue(pct100(g.sloshStrength))
        page.damping:SetValue(pct100(g.sloshDamping))
        page.slosh:SetActive(all)
        page.strength:SetActive(all and g.slosh)
        page.damping:SetActive(all and g.slosh)
        page.sloshNote:SetText(all and "" or L.UI_LIQUID_SLOSH_GLOBAL)
    end,
})

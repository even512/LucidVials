-- Reiter "Allgemein" (Delta Ausbau 1.1.0, E2): Ein/Aus, welche Rahmen, Erfahrungsroehre, Auren-Groesse am Ziel und der Hinweis auf
-- Fremd-Einheitenrahmen-Addons. Alle Werte gehen ueber Skin.Set (Pruefung, Profil, sofort anwenden, kein /reload).
-- Fasst keine Blizzard-Frames an; im Kampf bedienbar (der Skin arbeitet nur mit Alpha und eigenen Frames).
local _, ns = ...
local Skin = ns.UnitFrameSkin
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local function pxFmt(v) return ("%d px"):format(v) end

--- Wert ueber die Profil-Pruefung setzen (path wie bei Skin.Set), Anzeige nachziehen
local function set(page, path, value)
    if Skin.Set(path, value) then
        page.status:SetText("")
    else
        page.status:SetText(L.FRAMES_VALUE_INVALID)
        W.Color(page.status, C.warn)
    end
    Config.Refresh()
end

Config.RegisterPage("general", {
    label = "UI_TAB_GENERAL",
    order = 10,
    height = 340,
    build = function(page)
        page.enabled = W.CheckAt(page, L.UI_FRAMES_ENABLE, L.UI_FRAMES_ENABLE_TIP, 0, -4,
            function(v) set(page, "enabled", v) end)
        page.blockNote = W.Note(page, 4, -30, 740, "GameFontNormalSmall", C.warn)

        local h1 = W.Header(page, L.UI_FRAMES_HEAD_FRAMES, 740)
        h1:SetPoint("TOPLEFT", 0, -72)
        page.player = W.CheckAt(page, L.UI_FRAMES_PLAYER, L.UI_FRAMES_PLAYER_TIP, 0, -96,
            function(v) set(page, "frames.player", v) end)
        page.target = W.CheckAt(page, L.UI_FRAMES_TARGET, L.UI_FRAMES_TARGET_TIP, 160, -96,
            function(v) set(page, "frames.target", v) end)
        page.tot = W.CheckAt(page, L.UI_FRAMES_TOT, L.UI_FRAMES_TOT_TIP, 320, -96,
            function(v) set(page, "frames.tot", v) end)
        page.xp = W.CheckAt(page, L.UI_FRAMES_XP, L.UI_FRAMES_XP_TIP, 520, -96,
            function(v) set(page, "xp", v) end)

        local h2 = W.Header(page, L.UI_FRAMES_HEAD_TARGET, 740)
        h2:SetPoint("TOPLEFT", 0, -136)
        local R = Skin.AURA_SIZE
        page.auraSize = W.SliderAt(page, L.UI_FRAMES_AURA, L.UI_FRAMES_AURA_TIP:format(R.min, R.max, R.default), 4, -162,
            R.min, R.max, 1, pxFmt, function(v) set(page, "auraSize", v) end)
        -- Standardwerte aus den Schema-Defaults (Marke, Tooltip, Zuruecksetzen per Rechtsklick)
        page.enabled:SetDefault("enabled")
        page.player:SetDefault("frames.player")
        page.target:SetDefault("frames.target")
        page.tot:SetDefault("frames.tot")
        page.xp:SetDefault("xp")
        page.auraSize:SetDefault("auraSize")
        page.auraReset = W.Button(page, L.UI_FRAMES_AURA_RESET, 150, function() set(page, "auraSize", R.default) end)
        page.auraReset:SetPoint("TOPLEFT", 394, -172)

        local h3 = W.Header(page, L.UI_GENERAL_HEAD_OTHER, 740)
        h3:SetPoint("TOPLEFT", 0, -218)
        page.foreignNote = W.Note(page, 4, -242, 736, "GameFontHighlightSmall", C.muted)
        page.foreignNote:SetText(L.UI_GENERAL_FOREIGN_NOTE)

        page.status = W.Note(page, 4, -312, 736, "GameFontNormalSmall", C.muted)
    end,
    refresh = function(page)
        local cfg = Skin.GetConfig()
        local blocker = Skin.Conflict()
        page.enabled:SetValue(cfg.enabled)
        page.player:SetValue(cfg.frames.player)
        page.target:SetValue(cfg.frames.target)
        page.tot:SetValue(cfg.frames.tot)
        page.xp:SetValue(cfg.xp)
        page.auraSize:SetValue(cfg.auraSize)
        page.auraReset:SetEnabled(cfg.auraSize ~= Skin.AURA_SIZE.default)
        page.blockNote:SetText(blocker and L.UI_FRAMES_BLOCKED:format(W.Plain(blocker)) or "")
    end,
    -- Fenster schliesst: laufende Tests der echten Rahmen (/vials test ...: Rahmen-Test, Wirkungen, XP) enden wie bei /vials test off
    onClose = function()
        local Fx, XP = ns.LiquidFx, Skin.XP
        if Skin.IsTesting() or (XP and XP.TestMode()) or (Fx and Fx.TestDebuffsActive()) then
            xpcall(ns.UnitFrames.sub.test, geterrorhandler(), "off")
        end
    end,
})

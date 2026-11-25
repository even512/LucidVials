-- Reiter "Rahmen" (Delta "Fluessiges Leben", E5): Einheitenrahmen im Lucid-Stil (Spieler, Ziel, Ziel des Ziels), Erfahrungsroehre,
-- Fluessigkeit (Darstellung, Gleiten, Schadensspur, Effekte, Debuff-Toenung, Schwappen), Auren-Groesse am Ziel und
-- Simulations-Knoepfe. Alle Werte gehen ueber Skin.Set (Pruefung, Profil, sofort anwenden, kein /reload); die Knoepfe rufen
-- dieselbe Funktion wie /vials test <Wort>. Ist ein Fremd-Einheitenrahmen-Addon geladen, nennt der Reiter es.
-- Fasst keine Blizzard-Frames an; im Kampf bedienbar (der Skin arbeitet nur mit Alpha und eigenen Frames).
local _, ns = ...
local Skin, UnitFrames = ns.UnitFrameSkin, ns.UnitFrames
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local Tab = {}
Config.Frames = Tab

local function pctFmt(v) return ("%d %%"):format(v) end
local function pxFmt(v) return ("%d px"):format(v) end
local function pct100(x) return math.floor(x * 100 + 0.5) end

-- Simulations-Knoepfe: { Beschriftung, Wort fuer /vials test, Tooltip } (Locale-Schluessel); Wort ohne Sprache
Tab.TESTS = {
    { "UI_FRAMES_T_HEAL", "heal", "UI_FRAMES_T_HEAL_TIP" },
    { "UI_FRAMES_T_HIT", "hit", "UI_FRAMES_T_HIT_TIP" },
    { "UI_FRAMES_T_MANA", "mana", "UI_FRAMES_T_MANA_TIP" },
    { "UI_FRAMES_T_SLOSH", "slosh", "UI_FRAMES_T_SLOSH_TIP" },
    { "UI_FRAMES_T_SHIELD", "shield", "UI_FRAMES_T_SHIELD_TIP" },
    { "UI_FRAMES_T_WEAK", "weak", "UI_FRAMES_T_WEAK_TIP" },
    { "UI_FRAMES_T_POISON", "poison", "UI_FRAMES_T_DEBUFF_TIP" },
    { "UI_FRAMES_T_CURSE", "curse", "UI_FRAMES_T_DEBUFF_TIP" },
    { "UI_FRAMES_T_DISEASE", "disease", "UI_FRAMES_T_DEBUFF_TIP" },
    { "UI_FRAMES_T_MAGIC", "magic", "UI_FRAMES_T_DEBUFF_TIP" },
    { "UI_FRAMES_T_XP", "xp", "UI_FRAMES_T_XP_TIP" },
    { "UI_FRAMES_T_LEVELUP", "levelup", "UI_FRAMES_T_LEVELUP_TIP" },
}

local function setStatus(page, text, c)
    page.status:SetText(text or "")
    W.Color(page.status, c or C.muted)
end

--- Wert ueber die Profil-Pruefung setzen (path wie bei Skin.Set), Anzeige nachziehen
local function set(page, path, value)
    if Skin.Set(path, value) then
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

local function check(page, key, path, text, tip, x, y)
    local cb = W.Check(page, text, function(v) set(page, path, v) end)
    cb:SetPoint("TOPLEFT", x, y)
    if tip then W.Tooltip(cb, function() return text, tip end) end
    page[key] = cb
    return cb
end

local function slider(page, key, text, tip, x, y, lo, hi, step, fmt, onChange)
    local s = W.Slider(page, text, lo, hi, step, 340, fmt, onChange)
    s:SetPoint("TOPLEFT", x, y)
    if tip then W.Tooltip(s, function() return text, tip end) end
    page[key] = s
    return s
end

--- Test ausloesen wie /vials test <word> ("" = Rahmen-Test an/aus, "off" = alles beenden; gleiche Funktion, gleiche
--- Chat-Meldung), mit Hinweis im Reiter, wenn es nicht geht. Liefert true, wenn der Befehl lief.
function Tab.RunTest(page, word)
    local blocker = Skin.Conflict()
    if blocker then
        setStatus(page, L.UI_FRAMES_BLOCKED_SHORT:format(W.Plain(blocker)), C.warn)
        return false
    end
    if word ~= "" and word ~= "off" and not Skin.IsEngaged() then
        setStatus(page, L.UI_FRAMES_NEED_ON, C.warn)
        return false
    end
    setStatus(page, "")
    xpcall(UnitFrames.sub.test, geterrorhandler(), word)
    Config.Refresh()
    return true
end

local function testButton(page, text, tip, word, w, x, y)
    local b = W.Button(page, text, w, function() Tab.RunTest(page, word) end)
    b:SetPoint("TOPLEFT", x, y)
    if tip then W.Tooltip(b, function() return text, tip end) end
    return b
end

-- Lage der Test-Knoepfe (nach dem Rahmen-Test-Knopf): Reihe 1 fuenf, Reihe 2 sechs, Reihe 3 einer (+ "Tests beenden")
local BW = 108
local function slotOf(i)
    if i <= 5 then return 156 + (i - 1) * 114, -376 end
    if i <= 11 then return (i - 6) * 114, -402 end
    return 0, -428
end

Config.RegisterPage("frames", {
    label = "UI_TAB_FRAMES",
    build = function(page)
        Tab.page = page
        check(page, "enabled", "enabled", L.UI_FRAMES_ENABLE, L.UI_FRAMES_ENABLE_TIP, 0, -4)
        page.blockNote = W.Text(page, "GameFontNormalSmall", C.warn)
        page.blockNote:SetPoint("TOPLEFT", 4, -30)
        page.blockNote:SetWidth(740)
        if page.blockNote.SetJustifyH then page.blockNote:SetJustifyH("LEFT") end

        local h1 = W.Header(page, L.UI_FRAMES_HEAD_FRAMES, 740)
        h1:SetPoint("TOPLEFT", 0, -62)
        check(page, "player", "frames.player", L.UI_FRAMES_PLAYER, L.UI_FRAMES_PLAYER_TIP, 0, -86)
        check(page, "target", "frames.target", L.UI_FRAMES_TARGET, L.UI_FRAMES_TARGET_TIP, 160, -86)
        check(page, "tot", "frames.tot", L.UI_FRAMES_TOT, L.UI_FRAMES_TOT_TIP, 320, -86)
        check(page, "xp", "xp", L.UI_FRAMES_XP, L.UI_FRAMES_XP_TIP, 520, -86)

        local h2 = W.Header(page, L.UI_FRAMES_HEAD_LIQUID, 740)
        h2:SetPoint("TOPLEFT", 0, -118)
        label(page, L.UI_FRAMES_STYLE, 4, -142)
        page.style = W.Dropdown(page, 220, function(v) set(page, "liquid.style", v) end)
        page.style:SetPoint("TOPLEFT", 4, -158)
        page.style:SetOptions({
            { value = "piston", text = L.FRAMES_STYLE_PISTON },
            { value = "edge", text = L.FRAMES_STYLE_EDGE },
        })
        W.Tooltip(page.style, function() return L.UI_FRAMES_STYLE, L.UI_FRAMES_STYLE_TIP end)
        check(page, "smooth", "liquid.smooth", L.UI_FRAMES_SMOOTH, L.UI_FRAMES_SMOOTH_TIP, 394, -146)
        check(page, "trail", "liquid.trail", L.UI_FRAMES_TRAIL, L.UI_FRAMES_TRAIL_TIP, 570, -146)
        check(page, "fx", "liquid.fx", L.UI_FRAMES_FX, L.UI_FRAMES_FX_TIP, 394, -172)
        check(page, "debuffs", "liquid.debuffs", L.UI_FRAMES_DEBUFFS, L.UI_FRAMES_DEBUFFS_TIP, 570, -172)
        check(page, "slosh", "liquid.slosh", L.UI_FRAMES_SLOSH, L.UI_FRAMES_SLOSH_TIP, 0, -200)
        slider(page, "strength", L.UI_FRAMES_STRENGTH, L.UI_FRAMES_STRENGTH_TIP, 4, -226, 0, 100, 5, pctFmt,
            function(v) set(page, "liquid.sloshStrength", v / 100) end)
        slider(page, "damping", L.UI_FRAMES_DAMPING, L.UI_FRAMES_DAMPING_TIP, 394, -226, 0, 100, 5, pctFmt,
            function(v) set(page, "liquid.sloshDamping", v / 100) end)

        local h3 = W.Header(page, L.UI_FRAMES_HEAD_TARGET, 740)
        h3:SetPoint("TOPLEFT", 0, -276)
        local R = Skin.AURA_SIZE
        slider(page, "auraSize", L.UI_FRAMES_AURA, L.UI_FRAMES_AURA_TIP:format(R.min, R.max, R.default), 4, -300,
            R.min, R.max, 1, pxFmt, function(v) set(page, "auraSize", v) end)
        page.auraReset = W.Button(page, L.UI_FRAMES_AURA_RESET, 150, function() set(page, "auraSize", R.default) end)
        page.auraReset:SetPoint("TOPLEFT", 394, -310)

        local h4 = W.Header(page, L.UI_FRAMES_HEAD_TEST, 740)
        h4:SetPoint("TOPLEFT", 0, -350)
        page.status = W.Text(page, "GameFontNormalSmall", C.muted)
        page.status:SetPoint("TOPLEFT", 140, -352)
        page.status:SetWidth(600)
        if page.status.SetJustifyH then page.status:SetJustifyH("LEFT") end

        page.testBtn = W.Button(page, L.UI_FRAMES_TEST_START, 150, function() Tab.RunTest(page, "") end)
        page.testBtn:SetPoint("TOPLEFT", 0, -376)
        W.Tooltip(page.testBtn, function() return L.UI_FRAMES_TEST_START, L.UI_FRAMES_TEST_TIP end)
        page.tests = {}
        for i, t in ipairs(Tab.TESTS) do
            local x, y = slotOf(i)
            page.tests[#page.tests + 1] = testButton(page, L[t[1]], L[t[3]], t[2], BW, x, y)
        end
        page.stopBtn = W.Button(page, L.UI_FRAMES_TEST_STOP_ALL, 150, function() Tab.RunTest(page, "off") end)
        page.stopBtn:SetPoint("TOPLEFT", 114, -428)
        W.Tooltip(page.stopBtn, function() return L.UI_FRAMES_TEST_STOP_ALL, L.UI_FRAMES_TEST_STOP_ALL_TIP end)

        page.note = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.note:SetPoint("TOPLEFT", 4, -458)
        page.note:SetWidth(740)
        if page.note.SetJustifyH then page.note:SetJustifyH("LEFT") end
        page.note:SetText(L.UI_FRAMES_NOTE)
    end,
    refresh = function(page)
        local cfg = Skin.GetConfig()
        local blocker = Skin.Conflict()
        page.enabled:SetValue(cfg.enabled)
        page.player:SetValue(cfg.frames.player)
        page.target:SetValue(cfg.frames.target)
        page.tot:SetValue(cfg.frames.tot)
        page.xp:SetValue(cfg.xp)
        page.style:SetValue(cfg.liquid.style)
        page.smooth:SetValue(cfg.liquid.smooth)
        page.trail:SetValue(cfg.liquid.trail)
        page.fx:SetValue(cfg.liquid.fx)
        page.debuffs:SetValue(cfg.liquid.debuffs)
        page.slosh:SetValue(cfg.liquid.slosh)
        page.strength:SetValue(pct100(cfg.liquid.sloshStrength))
        page.damping:SetValue(pct100(cfg.liquid.sloshDamping))
        page.strength:SetActive(cfg.liquid.slosh)
        page.damping:SetActive(cfg.liquid.slosh)
        page.auraSize:SetValue(cfg.auraSize)
        page.auraReset:SetEnabled(cfg.auraSize ~= Skin.AURA_SIZE.default)
        page.blockNote:SetText(blocker and L.UI_FRAMES_BLOCKED:format(W.Plain(blocker)) or "")
        page.testBtn:SetText(Skin.IsTesting() and L.UI_FRAMES_TEST_STOP or L.UI_FRAMES_TEST_START)
        local free = blocker == nil
        page.testBtn:SetEnabled(free)
        page.stopBtn:SetEnabled(free)
        for _, b in ipairs(page.tests) do b:SetEnabled(free) end
    end,
    -- Fenster schliesst: laufende Vorschau-Tests enden (wie die Zustands-Simulation)
    onClose = function()
        local Fx, XP = ns.LiquidFx, Skin.XP
        if Skin.IsTesting() or (XP and XP.TestMode()) or (Fx and Fx.TestDebuffsActive()) then
            xpcall(UnitFrames.sub.test, geterrorhandler(), "off")
        end
    end,
})

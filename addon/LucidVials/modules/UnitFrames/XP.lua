-- Erfahrungsleiste als Fluessigkeits-Roehre (Delta "Fluessiges Leben", Wunsch 17.11.: "Die Fluessigkeit soll exakt auch
-- so fuer die XP-Leiste umgesetzt sein").
--
-- Dieselbe Roehre wie die Lebensroehre (ns.Liquid: Kolben-Kammer bzw. Kante nach unitframes.liquid.style, Bewegungsphysik,
-- Glasreflexe, Effekte aus LiquidFx), im schmalen Bronze-Kapselrahmen uf-frame-power (3-Slice, an die Laenge angepasst, eigene
-- Kapselmaske uf-mask-xp), nur laenger/schmaler an der Stelle von Blizzards XP-Leiste.
-- Blizzard-Leiste (wow-ui-source, Retail 12.x Blizzard_ActionBar, Forever Blizzard_StatusTrackingBar, beide Mainline-Familie):
--   MainStatusTrackingBarContainer / SecondaryStatusTrackingBarContainer .bars[StatusTrackingBarInfo.BarsEnum.Experience] =
--   ExpBar (Frame, Maus + Tooltip) mit .StatusBar (Fuellung, Hintergrund, Gewinn-/Stufen-Animation), .ExhaustionLevelFillBar
--   (Ruhe-Abschnitt), .ExhaustionTick (Ruhe-Marke, eigener Tooltip); am Container .BarFrameTexture (Rahmen) und Segment-
--   Teiler (Forever 20) als Pool-Frames mit .BarDividerTexture. Je nach Prioritaet steht die XP-Leiste im ersten oder
--   zweiten Container => je ExpBar (hoechstens zwei) eine eigene Roehre. Aeltere Clients: MainMenuExpBar.
-- Lucid
--   * legt je ExpBar einen eigenen Kind-Frame mit der Roehre an: er erbt Sichtbarkeit und Alpha (Blizzards Ein-/Ausblenden,
--     Fader, Bearbeitungsmodus); kein Secure-Frame, keine Maus - Tooltip und Text (OverlayFrame) bleiben Blizzards,
--   * macht nur Blizzards Optik per SetAlpha(0) unsichtbar (StatusBar-Frame samt Animationen, Ruhe-Abschnitt, Ruhe-Marke;
--     Rahmen und Teiler des Containers nur, solange die XP-Leiste darin gezeigt wird), nie Show/Hide/SetPoint an Blizzard.
--     Aus => Alpha 1 sofort, ohne /reload. Blizzards Alpha wird nie gelesen.
-- Farben wie Blizzard (Classic Blizzard_ActionBar/Classic/ExpBarOverrides.lua UpdateStatusBarTextures; Retail/Forever zeichnen
-- dieselben Toene als Atlas UI-HUD-ExperienceBar-Fill-Experience/-Rested): normal violett (0,58 / 0 / 0,55), ausgeruht blau
-- (0 / 0,39 / 0,88). Im Ruhebonus ist die ganze Fluessigkeit blau, vor dem Kolben eine dunklere Reserve-Lage bis
-- XP + GetXPExhaustion(), gedeckelt auf das Maximum (Liquid.AddReserve); nicht ausgeruht violett ohne Abschnitt.
-- Zufluss-Leuchten bei Gewinn: Anstiegsband von LiquidFx (jeder Anstieg) und Fx.Glow (Lichtstreifen, Funkeln, Stern).
-- Stufenaufstieg (PLAYER_LEVEL_UP): die Roehre fuellt sich, schaeumt golden ueber (Gischt-Krone, Schaum an der Glasdecke,
-- Tropfen, Welle - alles im Glas), leert sich sichtbar und fuellt dann auf den neuen Stand. Dafuer eigene, lesbare Zahlen 0..1.
-- Secret-Regel: UnitXP/UnitXPMax/GetXPExhaustion sind laut API-Doku nicht secret; trotzdem gehen die Rohwerte nur durchgereicht
-- an Liquid, gerechnet (Reserve-Ende, Gewinn, Anteil) wird nur mit Compat.Num-lesbaren Zahlen - sonst kein Abschnitt.
-- Hoechststufe oder Erfahrung abgeschaltet (IsXPUserDisabled): keine Roehre, Blizzard zeigt bzw. verbirgt seine Leiste selbst.
-- Profil unitframes.xp (Standard an, wirkt mit /vials on), /vials xp on|off, /vials test xp|xprest|levelup.
local _, ns = ...
local Compat, L = ns.Compat, ns.L
local Liquid = ns.Liquid
local UnitFrames, Skin = ns.UnitFrames, ns.UnitFrameSkin

local XP = {}
Skin.XP = XP
ns.UnitFrameXP = XP

XP.COLORS = { normal = { 0.58, 0.0, 0.55 }, rested = { 0.0, 0.39, 0.88 }, gold = { 1.0, 0.80, 0.38 } }
XP.TINTS = { normal = { tex = "mono", color = XP.COLORS.normal }, rested = { tex = "mono", color = XP.COLORS.rested },
    gold = { tex = "mono", color = XP.COLORS.gold } }
XP.FALLBACK = { retail = { 565, 11 }, forever = { 1189, 14 } } -- Leistengroesse, wenn sie nicht lesbar ist (Blizzard-Konstanten)
XP.BAR_INDEX = 4 -- StatusTrackingBarInfo.BarsEnum.Experience, falls die Tabelle fehlt
XP.CONTAINERS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }
XP.MOTION = 0.25 -- Bewegung der Fluessigkeit gegenueber Leben/Ressource (lange Roehre kippt sonst zu stark)
XP.ART_RECHECK = { 0.5, 2 } -- s nach dem Anlegen: Teiler nachsammeln (Blizzard baut den Pool teils spaeter)
XP.CLASSIC_ART = { "MainMenuXPBarTexture0", "MainMenuXPBarTexture1", "MainMenuXPBarTexture2", "MainMenuXPBarTexture3" }
XP.GAIN_CRIT = 0.1 -- Gewinn ab diesem Anteil am Maximum leuchtet stark
-- Stufenaufstieg (s ab Beginn): rise = Anstieg auf voll, breaks = Ueberschwappen (Gischt, Abklingzeit Liquid.BREAK.cooldown),
-- jolt = Stossstaerke, drain/drainT = Leeren, refill = neuer Stand; tick = Takt der eigenen Werte
-- recent = so kurz vor PLAYER_LEVEL_UP gilt ein gesunkener Wert als "schon der neue Stand" (Reihenfolge der Ereignisse offen)
XP.LEVELUP = { rise = 0.35, breaks = { 0.4, 1.05 }, jolt = 0.9, drain = 1.45, drainT = 0.85, refill = 2.45, tick = 1 / 30,
    recent = 1.5 }
XP.TEST_MAX = 1000
XP.TEST_SEQ = { 80, 210, 260, 420, 470, 640, 700, 860, 930 } -- danach Stufenaufstieg
XP.TEST_EXH = 300
XP.TEST_STEP = 1.6
XP.TEST_WORDS = { xp = "xp", xprest = "xprest", levelup = "levelup", stufe = "levelup" }
XP.EVENTS = { "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING", "ENABLE_XP_GAIN",
    "DISABLE_XP_GAIN", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }

-- Zustand ---------------------------------------------------------------------------------------------------------------
local bars = {}            -- ExpBar -> { xb, sb, container, holder, lb, hidden, art, applied, ... }
local engagedNow = false   -- letzter Stand aus Skin.Refresh (Skin aktiv, keine Sperre, an oder Testmodus)
local wantNow = false
local testMode, testTicker, testIndex = nil, nil, 0
local lu = nil             -- laufender Stufenaufstieg { t0, stage, ticker }
local listening, evf = false, nil
local cfg = nil

local function now() return type(GetTime) == "function" and GetTime() or 0 end

-- Hilfen (Muster wie Skin.lua: nie ungeschuetzt in Blizzard-Tabellen greifen) -------------------------------------------------
local function getField(t, k) return t[k] end
local function field(t, key)
    if type(t) ~= "table" or Compat.IsSecret(t) then return nil end
    local ok, v = pcall(getField, t, key)
    if ok and not Compat.IsSecret(v) then return v end
    return nil
end

local function isObject(v)
    return type(v) == "table" and not Compat.IsSecret(v) and type(field(v, "GetObjectType")) == "function"
end

local function call(obj, method, ...)
    local fn = field(obj, method)
    if type(fn) ~= "function" then return false end
    return pcall(fn, obj, ...)
end

local function num(obj, method)
    local ok, v = call(obj, method)
    return ok and Compat.Num(v) or nil
end

local function readFlag(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or Compat.IsSecret(v) then return nil end
    return v
end

local function readNum(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    return ok and Compat.Num(v) or nil
end

--- Hoechststufe erreicht oder Erfahrung abgeschaltet (nur lesbare Antworten zaehlen)
function XP.Maxed()
    if readFlag(_G.IsXPUserDisabled) == true then return true end
    local G = _G.GameRulesUtil
    local v = readFlag(field(G, "IsPlayerAtEffectiveMaxLevel"))
    if v ~= nil then return v == true end
    local lvl = readNum(_G.UnitLevel, "player")
    local cap = readNum(_G.GetMaxLevelForPlayerExpansion) or readNum(_G.GetMaxPlayerLevel) or Compat.Num(_G.MAX_PLAYER_LEVEL)
    if lvl and cap and cap > 0 then return lvl >= cap end
    return false
end

-- Blizzard-Leiste finden ------------------------------------------------------------------------------------------------------
--- Liste { xb, sb, container } der vorhandenen XP-Leisten (Retail/Forever: je Container eine, sonst MainMenuExpBar)
local function findBars()
    local list = {}
    local idx = Compat.Num(field(field(_G.StatusTrackingBarInfo, "BarsEnum"), "Experience")) or XP.BAR_INDEX
    for _, name in ipairs(XP.CONTAINERS) do
        local c = _G[name]
        local xb = isObject(c) and field(field(c, "bars"), idx) or nil
        local sb = field(xb, "StatusBar")
        if isObject(xb) and isObject(sb) then list[#list + 1] = { xb = xb, sb = sb, container = c } end
    end
    if #list == 0 and isObject(_G.MainMenuExpBar) then
        list[1] = { xb = _G.MainMenuExpBar, sb = _G.MainMenuExpBar }
    end
    return list
end

-- Blizzard-Optik verdecken / zurueckstellen (Alpha nur setzen, nie lesen) --------------------------------------------------
local function hideRegion(set, r)
    if not isObject(r) then return end
    set[r] = true
    call(r, "SetAlpha", 0)
end

local function hideBlizzard(st)
    local xb, sb, h = st.xb, st.sb, st.hidden
    if sb ~= xb then
        hideRegion(h, sb) -- Fuellung, Hintergrund, Gewinn-/Stufen-Animation (Text liegt im OverlayFrame)
    else -- MainMenuExpBar: die Leiste ist selbst die StatusBar (Elternteil der Roehre) => nur ihre Texturen
        local ok, t = call(sb, "GetStatusBarTexture")
        if ok then hideRegion(h, t) end
        for _, n in ipairs(XP.CLASSIC_ART) do hideRegion(h, _G[n]) end
    end
    hideRegion(h, field(xb, "ExhaustionLevelFillBar") or (sb == xb and _G.ExhaustionLevelFillBar) or nil)
    hideRegion(h, field(xb, "ExhaustionTick") or (sb == xb and _G.ExhaustionTick) or nil)
end

--- Rahmen und Teiler des Containers (gehoeren allen Leisten darin): sammeln, verdeckt nur solange die XP-Leiste gezeigt wird
local function kidCount(c) return select("#", c:GetChildren()) end

-- Teiler/Rahmen bleiben verdeckt, auch wenn Blizzard sie neu setzt (17.11.: "mal mit Trennern, mal ohne"): Nach-Haken auf
-- SetAlpha der Textur und OnShow des Teiler-Frames setzen wieder 0, solange die XP-Roehre im Container gezeigt wird (st.artOn).
local artOwner = {}    -- Textur -> st
local artHooked = {}   -- Textur/Frame -> true
local rezeroing = false
local function rezeroArt(r)
    local st = artOwner[r]
    if rezeroing or not (st and st.artOn and st.art[r]) then return end
    rezeroing = true
    call(r, "SetAlpha", 0)
    rezeroing = false
end

local function guardArt(st, r, holder)
    if not isObject(r) then return end
    artOwner[r] = st
    if type(hooksecurefunc) ~= "function" then return end
    if not artHooked[r] then artHooked[r] = pcall(hooksecurefunc, r, "SetAlpha", rezeroArt) or nil end
    if holder and not artHooked[holder] then
        artHooked[holder] = call(holder, "HookScript", "OnShow", function() rezeroArt(r) end) or nil
    end
end

local function collectArt(st)
    local c = st.container
    if not c then return end
    local ok, n = pcall(kidCount, c)
    st.artKids = ok and n or nil
    local frameTex = field(c, "BarFrameTexture")
    hideRegion(st.art, frameTex)
    guardArt(st, frameTex)
    local kids = { call(c, "GetChildren") }
    for i = 2, #kids do
        local d = field(kids[i], "BarDividerTexture")
        if d then
            hideRegion(st.art, d)
            guardArt(st, d, kids[i])
        end
    end
end

local function syncArt(st)
    local on = st.applied and Compat.QueryBool(st.xb, "IsShown") == true
    st.artOn = on
    for r in pairs(st.art) do call(r, "SetAlpha", on and 0 or 1) end
end

--- Spaeter angelegte Teiler (Pool waechst, z. B. Forever beim Umbau): nur neu sammeln, wenn sich die Kinderzahl aenderte
--- (sonst keine Tabelle je Ereignis)
local function refreshArt(st, force)
    local c = st.container
    if not c then return end
    local ok, n = pcall(kidCount, c)
    if force or (ok and n ~= st.artKids) then
        collectArt(st)
        syncArt(st)
    end
end

local function onBarShown(xb)
    local st = bars[xb]
    if st then syncArt(st) end
end

local function restore(st)
    st.artOn = false
    for r in pairs(st.hidden) do
        call(r, "SetAlpha", 1)
        st.hidden[r] = nil
    end
    for r in pairs(st.art) do
        call(r, "SetAlpha", 1)
        st.art[r] = nil
    end
end

-- Roehre ------------------------------------------------------------------------------------------------------------------
local function build(st)
    local holder = CreateFrame("Frame", nil, st.xb)
    holder:SetAllPoints(st.xb)
    st.holder = holder
    st.lb = Liquid.Create(holder, { frame = "power", trail = false, mask = Liquid.MASK_XP_TEX, dy = 0, fizz = false,
        motion = XP.MOTION })
    Liquid.AddReserve(st.lb)
    if not st.hooked then -- Container-Rahmen folgt dem Zeigen/Verbergen der XP-Leiste (Nachher-Hooks, kein Eingriff)
        st.hooked = true
        call(st.xb, "HookScript", "OnShow", onBarShown)
        call(st.xb, "HookScript", "OnHide", onBarShown)
        -- Container legt Teiler neu an (Pool waechst/wird umgebaut): nach jeder Methode, die nach Teilern/Layout klingt, neu sammeln
        local c = st.container
        if c and type(hooksecurefunc) == "function" then
            local names = {}
            for k, v in pairs(c) do
                if type(k) == "string" and type(v) == "function" and (k:find("Divider") or k:find("Tick") or k:find("Layout")
                    or k:find("UpdateBar") or k:find("SetBar") or k:find("BarFrame")) then
                    names[#names + 1] = k
                end
            end
            table.sort(names)
            for _, k in ipairs(names) do
                pcall(hooksecurefunc, c, k, function() if st.applied then refreshArt(st, true) end end)
            end
            call(c, "HookScript", "OnShow", function() if st.applied then refreshArt(st, true) end end)
        end
    end
end

--- Roehre auf Blizzards StatusBar; die Bronze-Kappen liegen innerhalb der Leiste (Enden um den Kappenrand eingerueckt)
local function layout(st)
    local S = Compat.isRetail and XP.FALLBACK.retail or XP.FALLBACK.forever
    local base = (num(st.sb, "GetFrameLevel") or num(st.xb, "GetFrameLevel") or 1) + 1
    Liquid.SetEnds(st.lb, 0, 0)
    Liquid.Layout(st.lb, st.sb, base, S[1], S[2])
    local pad = st.lb.pad and st.lb.pad.x or 0
    if pad > 0 then
        Liquid.SetEnds(st.lb, pad, -pad)
        Liquid.Layout(st.lb, st.sb, base, S[1], S[2])
    end
end

local function tintFor(st, key)
    if st.tintKey == key then return end
    st.tintKey = key
    Liquid.SetTint(st.lb, XP.TINTS[key])
    Liquid.SetReserveTint(st.lb, XP.COLORS[key])
end

local function testValue()
    local seq = XP.TEST_SEQ
    return seq[(testIndex % #seq) + 1]
end

local function isRested(ne)
    if testMode then return testMode == "xprest" end
    local ok, id = pcall(GetRestState)
    local n = ok and Compat.Num(id) or nil
    if n then return n == 1 end -- 1 = ausgeruht, 2 = normal (Blizzard ExhaustionTickMixin:UpdateExhaustionColor)
    return ne ~= nil and ne > 0
end

--- Werte einer Roehre einspeisen (snap = ohne Gleiten). Liefert true, wenn Erfahrung dazukam (lesbar: echter Anstieg;
--- secret nur mit glow = Ereignis PLAYER_XP_UPDATE), und ob der Gewinn gross war. Secret-Regel: mx/v/e gehen nur an Liquid
--- bzw. Compat.Num.
local function feed(st, snap, glow)
    local lb = st.lb
    local okV, v, okM, mx, ne
    if testMode then
        okV, v, okM, mx = true, testValue(), true, XP.TEST_MAX
        ne = testMode == "xprest" and XP.TEST_EXH or 0
    else
        okM, mx = pcall(UnitXPMax, "player")
        okV, v = pcall(UnitXP, "player")
        local okE, e = pcall(GetXPExhaustion)
        ne = okE and Compat.Num(e) or nil -- nil: kein Ruhebonus (Blizzard liefert dann nil) oder nicht lesbar
    end
    local rested = isRested(ne)
    tintFor(st, rested and "rested" or "normal")
    if snap then
        Liquid.Snap(lb)
        if okM then Liquid.SnapMax(lb, mx) end
        if okV then Liquid.SnapValue(lb, v) end
    else
        if okM then Liquid.SetMax(lb, mx) end
        if okV then Liquid.SetValue(lb, v) end
    end
    local nv = okV and Compat.Num(v) or nil
    local nm = okM and Compat.Num(mx) or nil
    -- Ruhe-Abschnitt: von der Fuellung bis XP + Ruhebonus, gedeckelt auf das Maximum (nur lesbare Zahlen)
    local endV = nil
    if rested and nv and nm and ne and ne > 0 and nm > 0 then endV = math.min(nv + ne, nm) end
    if endV then Liquid.SetReserve(lb, endV, nm, snap) end
    Liquid.ShowReserve(lb, endV ~= nil)
    if Skin.Text then Skin.Text.UpdateXP(st, okV, v, okM, mx, ne) end -- XP-Zahlen (Text.lua)
    local gain, big = false, false
    if not snap then
        if nv and st.lastV and nm and nm > 0 then
            gain = nv > st.lastV
            big = gain and (nv - st.lastV) >= XP.GAIN_CRIT * nm
        elseif not nv and okV and glow then
            gain = true -- secret: Erfahrung steigt nur (der Stufenaufstieg hat seinen eigenen Ablauf)
        end
        st.prevFrac, st.fracAt = st.frac, now() -- Stand vor diesem Wert (Stufenaufstieg startet von oben)
    end
    st.lastV = nv
    st.frac = (nv and nm and nm > 0) and math.max(0, math.min(1, nv / nm)) or nil
    return gain, big
end

--- glow: Leuchten erlaubt (PLAYER_XP_UPDATE, Testschritt, Neu-Fuellen nach dem Stufenaufstieg) - nicht bei Ruhe-Ereignissen
local function feedAll(snap, glow)
    if lu then return end -- Stufenaufstieg laeuft: danach mit dem neuen Stand
    local gain, big = false, false
    for _, st in pairs(bars) do
        if st.applied then
            local g, b = feed(st, snap, glow)
            gain, big = gain or g, big or b
        end
    end
    if gain and glow and ns.LiquidFx and ns.LiquidFx.Glow then ns.LiquidFx.Glow("player-xp", big) end
end

-- Anwenden / Zurueckstellen -------------------------------------------------------------------------------------------------
local function remove(st)
    if not st.applied then return end
    st.applied = false
    if Skin.Text then Skin.Text.DetachXP(st) end
    restore(st)
    Liquid.SetFx(st.lb, nil, false, false)
    Liquid.Hide(st.lb)
    st.holder:Hide()
end

local function apply(st)
    if not st.lb then build(st) end
    local c = cfg.liquid
    Liquid.SetStyle(st.lb, c.style) -- vor dem Layout (wie Skin.lua)
    layout(st)
    Liquid.SetOptions(st.lb, c.smooth, false) -- keine Schadensspur: Erfahrung sinkt nicht
    Liquid.SetFx(st.lb, "player-xp", c.fx, false)
    st.tintKey = nil
    st.holder:Show()
    Liquid.Show(st.lb)
    st.applied = true
    hideBlizzard(st)
    if Skin.Text then Skin.Text.AttachXP(st) end -- XP-Zahlen (Text.lua)
    collectArt(st)
    syncArt(st)
    -- Teiler, die Blizzard erst nach dem Laden anlegt: kurz danach noch zweimal nachsammeln
    if C_Timer and C_Timer.After then
        for _, d in ipairs(XP.ART_RECHECK) do
            C_Timer.After(d, function() if st.applied then refreshArt(st, true) end end)
        end
    end
    if lu then -- laufender Stufenaufstieg: eigene Werte 0..1, auf dem aktuellen Stand einsteigen
        Liquid.Snap(st.lb)
        Liquid.SnapMax(st.lb, 1)
        Liquid.SnapValue(st.lb, lu.v)
        Liquid.ShowReserve(st.lb, false)
        st.luFrom = lu.v
        tintFor(st, "gold")
    else
        feed(st, true)
    end
end

local function stopLevelUp()
    if lu and lu.ticker then lu.ticker:Cancel() end
    lu = nil
end

local function stopTicker()
    if testTicker then
        testTicker:Cancel()
        testTicker = nil
    end
end

local function setListening(on)
    if on == listening then return end
    listening = on
    if not evf then
        evf = CreateFrame("Frame")
        evf:SetScript("OnEvent", function(_, event)
            local ok, err = pcall(XP.OnEvent, event)
            if not ok and Skin.RecordError then Skin.RecordError(err) end
        end)
    end
    for _, ev in ipairs(XP.EVENTS) do
        if on then pcall(evf.RegisterEvent, evf, ev) else pcall(evf.UnregisterEvent, evf, ev) end
    end
end

--- Aus Skin.Refresh: engaged = Skin wirkt (an oder Rahmen-Test, keine Sperre). Legt Roehren an bzw. stellt Blizzard her.
function XP.Refresh(engaged)
    engagedNow = engaged == true
    cfg = Skin.GetConfig()
    wantNow = engagedNow and (cfg.xp == true or testMode ~= nil)
    local list = (wantNow and (testMode or not XP.Maxed())) and findBars() or {}
    local seen = {}
    for _, f in ipairs(list) do
        local st = bars[f.xb]
        if not st then
            st = { xb = f.xb, hidden = {}, art = {} }
            bars[f.xb] = st
        end
        st.sb, st.container = f.sb, f.container
        seen[f.xb] = true
        apply(st)
    end
    for xb, st in pairs(bars) do
        if not seen[xb] then remove(st) end
    end
    setListening(wantNow)
    if not wantNow then
        stopLevelUp()
        if testMode then
            testMode = nil
            stopTicker()
        end
    end
end

-- Stufenaufstieg --------------------------------------------------------------------------------------------------------------
local function overflow(st)
    local lb = st.lb
    local w = lb.w or 100
    Liquid.BreakWave(lb, (0.25 + 0.5 * math.random()) * w)
    Liquid.Jolt(lb, "land", XP.LEVELUP.jolt)
end

local function setAll(v)
    if lu then lu.v = v < 0 and 0 or v end
    for _, st in pairs(bars) do
        if st.applied then Liquid.SnapValue(st.lb, v < 0 and 0 or v) end
    end
end

local function finishLevelUp()
    stopLevelUp()
    for _, st in pairs(bars) do
        if st.applied then
            Liquid.Snap(st.lb)
            Liquid.SnapMax(st.lb, 1)
            Liquid.SnapValue(st.lb, 0)
            st.lastV, st.tintKey = 0, nil
        end
    end
    if not testMode and XP.Maxed() then -- Hoechststufe erreicht: Blizzard uebernimmt
        XP.Refresh(engagedNow)
        return
    end
    feedAll(false, true) -- fuellt vom leeren Rohr auf den neuen Stand (Anstiegsband + Leuchten)
end

--- Ein Takt des Stufenaufstiegs (eigene Zahlen 0..1, keine Tabellen)
local function stepLevelUp()
    if not lu then return end
    local U, age = XP.LEVELUP, now() - lu.t0
    local stage = lu.stage
    if stage == 0 then -- Anstieg auf voll
        local k = math.min(1, age / U.rise)
        lu.v = (lu.from or 0) + (1 - (lu.from or 0)) * k
        for _, st in pairs(bars) do
            if st.applied then
                local f = st.luFrom or 0
                Liquid.SnapValue(st.lb, f + (1 - f) * k)
            end
        end
        if k >= 1 then lu.stage = 1 end
    elseif stage <= #U.breaks then -- goldenes Ueberschwappen
        if age >= U.breaks[stage] then
            for _, st in pairs(bars) do
                if st.applied then overflow(st) end
            end
            if ns.LiquidFx and ns.LiquidFx.Glow then ns.LiquidFx.Glow("player-xp", true) end
            lu.stage = stage + 1
        end
        lu.v = 1
    elseif age < U.drain then -- voll halten, die Welle laeuft aus
        return
    elseif age < U.drain + U.drainT then -- sichtbar leeren (weich)
        local k = (age - U.drain) / U.drainT
        setAll(1 - k * k * (3 - 2 * k))
    elseif age < U.refill then
        setAll(0)
    else
        finishLevelUp()
    end
end

--- Stufenaufstieg zeigen (PLAYER_LEVEL_UP bzw. Test). Liefert true, wenn eine Roehre aktiv ist.
function XP.LevelUp()
    if not wantNow then return false end
    stopLevelUp()
    local any, from, t = false, 1, now()
    for _, st in pairs(bars) do
        if st.applied then
            any = true
            -- Stand vor dem Aufstieg: kam PLAYER_XP_UPDATE (neuer, kleiner Wert) kurz davor, gilt der Stand davor
            local f = st.frac
            if st.prevFrac and st.fracAt and t - st.fracAt <= XP.LEVELUP.recent and (not f or st.prevFrac > f) then
                f = st.prevFrac
            end
            st.luFrom = f or 0.9
            from = math.min(from, st.luFrom)
            Liquid.Snap(st.lb)
            Liquid.SnapMax(st.lb, 1)
            Liquid.SnapValue(st.lb, st.luFrom)
            Liquid.ShowReserve(st.lb, false)
            tintFor(st, "gold")
        end
    end
    if not any then return false end
    lu = { t0 = t, stage = 0, from = from, v = from }
    lu.ticker = C_Timer.NewTicker(XP.LEVELUP.tick, stepLevelUp)
    if ns.LiquidFx and ns.LiquidFx.Glow then ns.LiquidFx.Glow("player-xp", true) end
    Liquid.Wake()
    return true
end

function XP.IsLevelingUp() return lu ~= nil end

-- Ereignisse ------------------------------------------------------------------------------------------------------------------
function XP.OnEvent(event)
    if not wantNow then return end
    if event == "PLAYER_LEVEL_UP" then
        if not testMode then XP.LevelUp() end
    elseif event == "ENABLE_XP_GAIN" or event == "DISABLE_XP_GAIN" or event == "DISPLAY_SIZE_CHANGED"
        or event == "UI_SCALE_CHANGED" then
        XP.Refresh(engagedNow)
    elseif not testMode then -- PLAYER_XP_UPDATE, UPDATE_EXHAUSTION, PLAYER_UPDATE_RESTING
        feedAll(false, event == "PLAYER_XP_UPDATE")
        for _, st in pairs(bars) do
            if st.applied then -- Blizzard kann Teile neu gesetzt bzw. Teiler neu angelegt haben (nur Alpha)
                hideBlizzard(st)
                refreshArt(st)
            end
        end
    end
end

-- Testmodus -----------------------------------------------------------------------------------------------------------------
local function testStep()
    if lu then return end -- Stufenaufstieg laeuft: die Reihe wartet
    testIndex = testIndex + 1
    if testIndex % #XP.TEST_SEQ == 0 then
        XP.LevelUp()
    else
        feedAll(false, true)
    end
end

local function visibleTube()
    for _, st in pairs(bars) do
        if st.applied and Compat.QueryBool(st.lb.root, "IsVisible") ~= false then return true end
    end
    return false
end

function XP.StopTest()
    if not testMode then return false end
    testMode = nil
    stopTicker()
    stopLevelUp()
    XP.Refresh(engagedNow)
    return true
end

--- /vials test xp|xprest|levelup (xp/xprest schalten den Testlauf um)
function XP.TestCommand(word)
    local what = XP.TEST_WORDS[word]
    if not engagedNow then
        ns.Print(L.FRAMES_TEST_NEED_ON)
        return
    end
    if what == "levelup" then
        if not XP.LevelUp() then ns.Print(L.FRAMES_XP_NOBAR) return end
        ns.Print(L.FRAMES_TEST_FX1, word)
        return
    end
    if testMode == what then
        XP.StopTest()
        ns.Print(L.FRAMES_XP_TEST_OFF)
        return
    end
    stopTicker()
    stopLevelUp()
    testMode, testIndex = what, 0
    XP.Refresh(engagedNow)
    testTicker = C_Timer.NewTicker(XP.TEST_STEP, testStep)
    ns.Print(L.FRAMES_XP_TEST_ON, word)
    if not visibleTube() then ns.Print(L.FRAMES_XP_NOBAR) end
end

function XP.TestMode() return testMode end
--- Zustand je Blizzard-Leiste (Tests/Debug, nur lesen)
function XP.Get(xb) return bars[xb] end
function XP.Count()
    local n = 0
    for _, st in pairs(bars) do if st.applied then n = n + 1 end end
    return n
end

function XP.Debug()
    local c = cfg or Skin.GetConfig()
    local okV, v = pcall(UnitXP, "player")
    local secret = okV and Compat.IsSecret(v)
    local okE, e = pcall(GetXPExhaustion)
    ns.Print("frames.xp on=%s want=%s maxed=%s bars=%d visible=%s rested=%s exh=%s secret=%s test=%s levelup=%s",
        c.xp and L.NP_YES or L.NP_NO, wantNow and L.NP_YES or L.NP_NO, XP.Maxed() and L.NP_YES or L.NP_NO, XP.Count(),
        visibleTube() and L.NP_YES or L.NP_NO, isRested(okE and Compat.Num(e) or nil) and L.NP_YES or L.NP_NO,
        tostring(okE and Compat.Num(e) or "-"), secret and L.NP_YES or L.NP_NO, tostring(testMode or "-"),
        lu and L.NP_YES or L.NP_NO)
end

-- Slash /vials xp on|off ---------------------------------------------------------------------------------------------
UnitFrames.sub.xp = function(arg)
    local a = (arg or ""):lower():match("^%s*(%S*)") or ""
    local v
    if a == "on" or a == "an" then v = true elseif a == "off" or a == "aus" then v = false end
    if v == nil then
        ns.Print(L.FRAMES_XP_USAGE)
        return
    end
    if not Skin.Set("xp", v) then
        ns.Print(L.FRAMES_VALUE_INVALID)
        return
    end
    ns.Print(L.FRAMES_XP_SET, v and L.NP_YES or L.NP_NO)
    if v and not Skin.GetConfig().enabled then ns.Print(L.FRAMES_XP_NEED_ON) end
end
UnitFrames.sub.erfahrung = UnitFrames.sub.xp

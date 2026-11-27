-- Sprudeln der Ressourcen-Fluessigkeit beim Regenerieren (Spieltest 16.11.: "richtig ein Sprudeln"; die Roehre ist im Spiel
-- nur ~220 x 10 px, darum grobe Sprites statt feiner Texturen). Nur die Ressourcenroehre des Spielers ("player-power"),
-- angelegt aus LiquidFx.Attach. Sprites aus dem freigegebenen Gemini-Bogen v2 (gen-unitframe-media.mjs FX2), Pfade in TEX.
--
-- Darstellung:
--   Blasen    Pool (BUBBLES), 3-7 px gross, steigen vom Boden auf, wackeln seitlich, platzen an der Oberflaeche (Platz-Atlas,
--             4 Phasen) mit kleinem Lichtpunkt. Im Fluessigkeits-Clip (nichts ueber dem Leerglas).
--   Funken    Pool (SPARKS): magische Lichtpuenktchen in heller Ressourcenfarbe rieseln NUR am Kolben (Fuellungsende, Anker an
--             lb.barTex wie der Kolben) nach unten/leicht seitlich aus der Roehre, verglimmen nach 0,5-1 s - nur beim
--             Auffuellen, bei voller Ressource nichts. Einziger Effekt AUSSERHALB des Glases (nicht geclippter Frame).
--   Welle     Kolben-Kammer: kleine Anregungen (sanft unruhige Oberflaeche), nur wenn sicher regeneriert wird.
--   Frames    je Bereich aeusserer Frame (Ein-/Ausblenden, eigene Zahl) und innerer Frame ("nicht voll" als secret Alpha, Weg b);
--             getrennt, damit sich die Alphas nicht ueberschreiben. Die frueheren vollflaechigen Lagen sind weg (sie bildeten an
--             Fuellungsende und Luftspalt ein hartkantiges hellblaues Rechteck).
-- Erkennung "regeneriert" (Wecker UNIT_POWER_FREQUENT/UNIT_POWER_UPDATE/UNIT_DISPLAYPOWER fuer "player"):
--   a) UnitPower/UnitPowerMax nicht secret: vergleichen - steigt => an (bis CFG.hold s nach dem letzten Anstieg), cur >= max
--      oder sinkt => sofort aus.
--   b) secret: Ressourcenart mit Regeneration (TYPES) => an; "nicht voll" ueber UnitPowerPercent("player", art, false, Kurve)
--      als secret Alpha an die inneren Frames (Blasen UND Funken; voll => unsichtbar). Die Kurve deckt beide moeglichen Skalen
--      ab (0..1 und 0..100): ab 99,5 % des Endwerts 0 (Spieltest: bei vollem Mana rieselte es trotzdem).
--   5-Sekunden-Regel (Mana, classic-artig): nach jedem eigenen erfolgreichen Zauber (UNIT_SPELLCAST_SUCCEEDED "player", nur
--      der Zeitpunkt) beginnt die Anzeige erst CFG.castLock s spaeter. Energie/Fokus ohne Sperre.
--   Ereignis-Takt (Hauptweg bei secret Werten, Spieltest: in Forever ist UnitPower auch ausserhalb des Kampfs secret, und
--      das Kurven-Alpha blendete nicht aus): UNIT_POWER_FREQUENT/UNIT_POWER_UPDATE kommen nur, wenn sich die Ressource aendert;
--      bei voller Ressource kommt nichts mehr. Also "regeneriert" <=> letzte Aenderung der eigenen Ressource (Payload-Token nach
--      Secret-Pruefung; secret/fehlend => jedes Ereignis) vor weniger als CFG.tickWindow s (Forever-Tick ~2 s) UND die
--      5-s-Sperre ist vorbei (Ausgeben faellt damit weg). Das Kurven-Alpha bleibt nur Zusatz (Debug zeigt, ob es greift).
-- state.reason nennt den Grund (fuer /vials debug): aktiv | aktiv(tick) | voll | 5s-regel | kein-anstieg | kein-tick |
-- keine-regeneration | test.
-- TYPES: Mana, Fokus, Energie regenerieren von selbst; Wut, Runenmacht, Astralmacht, Wahnsinn, Zorn, Pein usw. nicht.
-- /vials test mana: CFG.testSecs s Sprudeln und Funkenspruehen, auch bei voller Ressource.
local ADDON_NAME, ns = ...
local Compat = ns.Compat

local Fizz = {}
ns.LiquidFizz = Fizz

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
-- Texturen (austauschbar): Atlanten mit n Zellen (waagrecht); cells = genutzte Zellen
Fizz.TEX = {
    bubble = { path = MEDIA .. "uf-fx2-bubbles", n = 8, cells = { 1, 2, 3, 4, 5 } },
    pop = { path = MEDIA .. "uf-fx2-pop", n = 4, cells = { 2, 3, 4 } },
    spark = { path = MEDIA .. "uf-fx2-sparks", n = 8, cells = { 2, 3, 4, 6, 7 } },
}
Fizz.TYPES = { [0] = true, [2] = true, [3] = true }           -- Enum.PowerType: Mana, Focus, Energy
Fizz.TOKENS = { MANA = true, FOCUS = true, ENERGY = true }
-- hold: an nach dem letzten Anstieg (s); fadeIn/fadeOut (1/s); bright: Aufhellung der Ressourcenfarbe;
-- Blasen: Pool, Abstand (s), Groesse px (min..max), Steigzeit (s), Wackeln (px, Hz), Platzdauer (s), Alpha;
-- Funken: Pool, Abstand (s), Groesse px, Anfangs-Fall (x Hoehe/s), Schwerkraft (x Hoehe/s^2), seitlich (x Hoehe/s), Leben (s);
-- kick*: Wellen-Anregung (s, Staerke); testSecs: Testdauer
Fizz.CFG = { hold = 2.0, castLock = 5, tickWindow = 2.5, fadeIn = 3, fadeOut = 1.2, bright = 0.6,
    bubbles = 8, bubbleEvery = 0.32, sizeMin = 3, sizeMax = 7, riseMin = 1.7, riseMax = 3.3, wobble = 1.0, wobbleHz = 0.8,
    popT = 0.26, bubbleA = 0.95,
    sparks = 10, sparkEvery = 0.13, sparkMin = 4, sparkMax = 8, sparkFall = 0.6, sparkG = 4.5, sparkDrift = 0.4,
    sparkLifeMin = 0.5, sparkLifeMax = 1.0, sparkA = 1.0,
    kickEvery = 0.28, kickStr = 0.12, testSecs = 6 }

local tubes = setmetatable({}, { __mode = "k" })
local WHITE = { 1, 1, 1 }
local state = { mode = "none", prev = nil, last = nil, regen = false, testUntil = 0, castAt = nil, mana = false,
    reason = "-" } -- Spieler (global)
local notFullCurve
local listening, evFrame = false, nil
local update -- unten (Ereignis-Auswertung)

local function now() return type(GetTime) == "function" and GetTime() or 0 end

local function free(t)
    if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, false) end
    if t.SetTexelSnappingBias then pcall(t.SetTexelSnappingBias, t, 0) end
    return t
end

local function cell(t, A, i)
    t:SetTexCoord((i - 1) / A.n, i / A.n, 0, 1)
end

local function sprite(frame, layer, sub, path)
    local t = free(frame:CreateTexture(nil, layer, nil, sub))
    t:SetTexture(path)
    if t.SetBlendMode then t:SetBlendMode("ADD") end
    t:Hide()
    return t
end

--- Anlegen (aus LiquidFx.Attach, nur Ressourcenroehre)
function Fizz.Attach(lb)
    local fx = lb.fx
    local C = Fizz.CFG
    local outer = CreateFrame("Frame", nil, fx.clip)       -- Blasen: im Fluessigkeits-Clip
    local inner = CreateFrame("Frame", nil, outer)
    local sOuter = CreateFrame("Frame", nil, lb.root)       -- Funken: ueber dem Glas, nicht geclippt
    local sInner = CreateFrame("Frame", nil, sOuter)
    local fz = { outer = outer, inner = inner, sOuter = sOuter, sInner = sInner, a = 0, shownA = nil, on = false, kickT = 0,
        sign = 1, nextB = 0, nextS = 0,
        b = {}, bOn = {}, bX = {}, bY = {}, bV = {}, bS = {}, bPh = {}, bPop = {},
        s = {}, sOn = {}, sX = {}, sY = {}, sVX = {}, sVY = {}, sT = {}, sL = {}, sS = {} }
    local ok, m = pcall(inner.CreateMaskTexture, inner)
    if ok and m and pcall(m.SetTexture, m, ns.Liquid.MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then fz.mask = m end
    for i = 1, C.bubbles do
        local t = sprite(inner, "ARTWORK", 5, Fizz.TEX.bubble.path)
        if fz.mask then pcall(t.AddMaskTexture, t, fz.mask) end
        fz.b[i], fz.bOn[i], fz.bX[i], fz.bY[i], fz.bV[i], fz.bS[i], fz.bPh[i], fz.bPop[i] = t, false, 0, 0, 0, 4, 0, nil
    end
    for i = 1, C.sparks do
        fz.s[i], fz.sOn[i], fz.sX[i], fz.sY[i], fz.sVX[i], fz.sVY[i], fz.sT[i], fz.sL[i], fz.sS[i] =
            sprite(sInner, "OVERLAY", 4, Fizz.TEX.spark.path), false, 0, 0, 0, 0, 0, 1, 5
    end
    for _, f in ipairs({ outer, sOuter }) do
        f:SetAlpha(0)
        f:Hide()
    end
    fx.fizz = fz
    tubes[lb] = true
end

local function hideAll(fz)
    for i = 1, #fz.b do fz.bOn[i] = false; fz.b[i]:Hide() end
    for i = 1, #fz.s do fz.sOn[i] = false; fz.s[i]:Hide() end
    fz.outer:Hide()
    fz.sOuter:Hide()
end

--- an/aus (Rolle "player-power" bzw. "preview-power" und Effekte an). own = Roehre der Mini-Vorschau (Preview.lua): sprudelt
--- nur im eigenen Test (Fizz.TestTube), echte Ressourcen-Ereignisse und /vials test mana erreichen sie nie
function Fizz.Configure(lb, on, own)
    local fz = lb.fx and lb.fx.fizz
    if not fz then return end
    fz.on = on == true
    fz.own = own == true
    if not fz.on or fz.own then fz.testUntil = 0 end
    if not fz.on then
        fz.a, fz.shownA = 0, nil
        hideAll(fz)
    end
    Fizz.UpdateListening()
    if fz.on and not fz.own then pcall(update) end
end

function Fizz.SetLevel(lb, level)
    local fz = lb.fx.fizz
    fz.outer:SetFrameLevel(level)
    fz.inner:SetFrameLevel(level)
    fz.sOuter:SetFrameLevel(level + 3) -- ueber Glas und Rahmen (lb.top = Grund + 3)
    fz.sInner:SetFrameLevel(level + 3)
end

function Fizz.Layout(lb)
    local fz = lb.fx.fizz
    local root = lb.root
    for _, f in ipairs({ fz.outer, fz.inner, fz.sOuter, fz.sInner }) do
        f:ClearAllPoints()
        f:SetAllPoints(root)
    end
    if fz.mask then
        if lb.maskPath then pcall(fz.mask.SetTexture, fz.mask, lb.maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
        fz.mask:ClearAllPoints()
        fz.mask:SetAllPoints(root)
    end
    fz.tint = nil
end

-- Erkennung ------------------------------------------------------------------------------------------------------------------
-- liefert Art (oder nil), regeneriert?, Mana? (unbekannt: wie Mana mit Regeneration)
local function powerType()
    local ok, ptype, token = pcall(UnitPowerType, "player")
    if not ok then return nil, true, true end
    if Compat.IsSecret(ptype) then return nil, true, true end
    local tok = type(token) == "string" and not Compat.IsSecret(token) and token or nil
    state.token = tok
    local mana = ptype == 0 or tok == "MANA"
    if tok and Fizz.TOKENS[tok] then return ptype, true, mana end
    return ptype, Fizz.TYPES[ptype] == true, mana
end

local function curveNotFull()
    if notFullCurve ~= nil then return notFullCurve or nil end
    notFullCurve = false
    local C = _G.C_CurveUtil
    if not (C and type(C.CreateCurve) == "function") then return nil end
    local ok, c = pcall(C.CreateCurve)
    if not ok or (type(c) ~= "table" and type(c) ~= "userdata") then return nil end
    -- linear, beide Skalen: 0..1 (voll = 1) und 0..100 (voll = 100); nur um 1 % Fuellung (Skala 0..100) faelschlich aus
    local linear = type(Enum) == "table" and type(Enum.LuaCurveType) == "table" and Enum.LuaCurveType.Linear or 0
    pcall(c.SetType, c, linear)
    for _, p in ipairs({ { 0, 1 }, { 0.985, 1 }, { 0.995, 0 }, { 1.5, 0 }, { 1.6, 1 }, { 98.5, 1 }, { 99.5, 0 }, { 1000, 0 } }) do
        pcall(c.AddPoint, c, p[1], p[2])
    end
    notFullCurve = c
    return c
end

local function setInner(alpha)
    state.innerSecret = Compat.IsSecret(alpha)
    local okAll = true
    for lb in pairs(tubes) do
        local fz = lb.fx and lb.fx.fizz
        if fz and fz.on and not fz.own then
            local ok1 = pcall(fz.inner.SetAlpha, fz.inner, alpha)
            local ok2 = pcall(fz.sInner.SetAlpha, fz.sInner, alpha)
            okAll = okAll and ok1 and ok2
        end
    end
    state.alphaOk = okAll -- Debug: nahm Frame:SetAlpha den (secret) Wert an?
end

local function wakeAll()
    local any = false
    for lb in pairs(tubes) do
        local fz = lb.fx and lb.fx.fizz
        if fz and fz.on and not fz.own then
            lb.fx.busy = true
            any = true
        end
    end
    if any and ns.Liquid.Wake then ns.Liquid.Wake() end
end

--- Ressource des Spielers neu lesen (Ereignis): Weg a (lesbar, vergleichen) oder Weg b (secret, Kurve)
function update()
    local ptype, regen, mana = powerType()
    state.regen, state.mana = regen, mana
    local okC, cur = pcall(UnitPower, "player")
    local okM, mx = pcall(UnitPowerMax, "player")
    local c, m = okC and Compat.Num(cur) or nil, okM and Compat.Num(mx) or nil
    local testing = now() < state.testUntil
    if c and m then
        if state.mode ~= "num" or testing then setInner(1) end
        state.mode, state.cur, state.max = "num", c, m
        if regen and state.prev and c > state.prev and c < m then state.last = now() end
        if c >= m or (state.prev and c < state.prev) then state.last = nil end
        state.prev = c
    else
        state.mode, state.prev, state.last, state.cur, state.max = "secret", nil, nil, nil, nil
        local curve = regen and not testing and curveNotFull() or nil
        local fn = _G.UnitPowerPercent
        if curve and type(fn) == "function" then
            local ok, a = pcall(fn, "player", ptype, false, curve)
            if ok and (Compat.IsSecret(a) or a ~= nil) then setInner(a) else setInner(1) end -- secret Alpha nur durchgereicht
        else
            setInner(1)
        end
    end
    wakeAll()
end
Fizz.Update = update

local function onEvent(_, event, unit, token)
    if unit ~= "player" then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        state.castAt = now() -- 5-Sekunden-Regel (nur der Zeitpunkt)
        state.last = nil
        return
    end
    if event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
        -- Takt: Aenderung der eigenen Ressource (fremder Token, z. B. Combo-Punkte, zaehlt nicht)
        local tok = type(token) == "string" and not Compat.IsSecret(token) and token or nil
        if not tok or not state.token or tok == state.token then state.tickAt = now() end
    end
    pcall(update)
end

--- Soll gerade sprudeln? Liefert want, sure (sicher regenerierend: Welle anregen), Grund
local function decide(t)
    local C = Fizz.CFG
    if t < state.testUntil then return true, true, "test" end
    if not state.regen then return false, false, "keine-regeneration" end
    if state.mana and state.castAt and t - state.castAt < C.castLock then return false, false, "5s-regel" end
    if state.mode == "num" then
        if state.cur and state.max and state.cur >= state.max then return false, false, "voll" end
        if state.last and t - state.last < C.hold then return true, true, "aktiv" end
        return false, false, "kein-anstieg"
    end
    if state.mode == "secret" then
        if state.tickAt and t - state.tickAt < C.tickWindow then return true, false, "aktiv(tick)" end
        return false, false, "kein-tick"
    end
    return false, false, "-"
end

--- Ereignisse nur, solange eine Ressourcenroehre sprudeln darf
function Fizz.UpdateListening()
    local want = false
    for lb in pairs(tubes) do
        local fz = lb.fx and lb.fx.fizz
        if fz and fz.on and not fz.own then want = true end
    end
    if want == listening then return end
    listening = want
    if not evFrame then
        evFrame = CreateFrame("Frame")
        evFrame:SetScript("OnEvent", onEvent)
    end
    for _, ev in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_DISPLAYPOWER", "UNIT_SPELLCAST_SUCCEEDED" }) do
        if want then
            if not pcall(evFrame.RegisterUnitEvent, evFrame, ev, "player") then pcall(evFrame.RegisterEvent, evFrame, ev) end
        else
            pcall(evFrame.UnregisterEvent, evFrame, ev)
        end
    end
    if not want then state.mode, state.prev, state.last = "none", nil, nil end
end
function Fizz.IsListening() return listening end
function Fizz.State() return state end

--- Zustand einer Roehre fuer /vials debug: Ausblend-Alpha, aktive Blasen/Funken
function Fizz.TubeInfo(lb)
    local fz = lb and lb.fx and lb.fx.fizz
    if not fz then return nil end
    local nb, ns_ = 0, 0
    for i = 1, #fz.b do if fz.bOn[i] then nb = nb + 1 end end
    for i = 1, #fz.s do if fz.sOn[i] then ns_ = ns_ + 1 end end
    return fz.a, nb, ns_, fz.on
end

--- Testmodus: sprudelt CFG.testSecs s ohne echte Regeneration, auch bei voller Ressource
function Fizz.Test()
    state.testUntil = now() + Fizz.CFG.testSecs
    setInner(1)
    wakeAll()
end

--- Mini-Vorschau: eine eigene Roehre CFG.testSecs s sprudeln lassen (unabhaengig vom Spieler-Zustand). Liefert true, wenn sie
--- sprudeln darf (Effekte an).
function Fizz.TestTube(lb)
    local fz = lb and lb.fx and lb.fx.fizz
    if not (fz and fz.on and fz.own) then return false end
    fz.testUntil = now() + Fizz.CFG.testSecs
    pcall(fz.inner.SetAlpha, fz.inner, 1)
    pcall(fz.sInner.SetAlpha, fz.sInner, 1)
    lb.fx.busy = true
    if ns.Liquid.Wake then ns.Liquid.Wake() end
    return true
end

-- Bild ------------------------------------------------------------------------------------------------------------------------
local function spawnSpark(fz, x, y, h)
    local C = Fizz.CFG
    for i = 1, #fz.s do
        if not fz.sOn[i] then
            local r = math.random()
            fz.sOn[i], fz.sX[i], fz.sY[i], fz.sT[i] = true, x, y, 0
            fz.sVX[i] = (math.random() - 0.5) * 2 * C.sparkDrift * h
            fz.sVY[i] = -C.sparkFall * h * (0.3 + 0.9 * r) -- nach unten (WoW: y nach oben positiv)
            fz.sL[i] = C.sparkLifeMin + (C.sparkLifeMax - C.sparkLifeMin) * math.random()
            fz.sS[i] = C.sparkMin + (C.sparkMax - C.sparkMin) * r
            local A = Fizz.TEX.spark
            cell(fz.s[i], A, A.cells[math.random(#A.cells)])
            fz.s[i]:SetSize(fz.sS[i], fz.sS[i])
            return
        end
    end
end

local function spawnBubble(fz, len, h, top)
    local C = Fizz.CFG
    for i = 1, #fz.b do
        if not fz.bOn[i] then
            local t, r = fz.b[i], math.random()
            fz.bOn[i], fz.bPop[i], fz.bPh[i] = true, nil, math.random() * 6.28
            fz.bS[i] = C.sizeMin + (C.sizeMax - C.sizeMin) * r
            fz.bX[i] = (0.04 + 0.92 * math.random()) * len
            fz.bY[i] = -h + fz.bS[i] * 0.6
            fz.bV[i] = (h - top) / (C.riseMin + (C.riseMax - C.riseMin) * (1 - r)) -- grosse Blasen steigen schneller
            t:SetTexture(Fizz.TEX.bubble.path)
            local A = Fizz.TEX.bubble
            cell(t, A, A.cells[math.random(#A.cells)])
            t:SetSize(fz.bS[i], fz.bS[i])
            t:SetAlpha(C.bubbleA)
            return
        end
    end
end

-- Blasen steigen, wackeln, platzen an der Oberflaeche; liefert, ob noch eine lebt
local function stepBubbles(lb, fz, t, dt, spawn, h, top, len)
    local C = Fizz.CFG
    local any = false
    if spawn and t >= fz.nextB then
        fz.nextB = t + C.bubbleEvery * (0.6 + 0.8 * math.random())
        spawnBubble(fz, len, h, top)
    end
    for i = 1, #fz.b do
        if fz.bOn[i] then
            any = true
            local tex = fz.b[i]
            if fz.bPop[i] then
                local u = (t - fz.bPop[i]) / C.popT
                if u >= 1 then
                    fz.bOn[i] = false
                    tex:Hide()
                else
                    local A = Fizz.TEX.pop
                    cell(tex, A, A.cells[math.min(#A.cells, math.floor(u * #A.cells) + 1)])
                    local s = fz.bS[i] * (1.3 + 0.8 * u)
                    tex:SetSize(s, s)
                    tex:SetAlpha(C.bubbleA * (1 - u))
                end
            else
                fz.bY[i] = fz.bY[i] + fz.bV[i] * dt
                local x = fz.bX[i] + C.wobble * math.sin(t * C.wobbleHz * 6.2832 + fz.bPh[i])
                if fz.bY[i] >= -top - fz.bS[i] * 0.5 then -- Oberflaeche: platzen (Lichtpunkt), ggf. Funke
                    fz.bPop[i] = t
                    fz.bY[i] = -top - fz.bS[i] * 0.3
                    tex:SetTexture(Fizz.TEX.pop.path)
                end
                tex:ClearAllPoints()
                tex:SetPoint("CENTER", lb.root, "TOPLEFT", x, fz.bY[i])
                tex:Show()
            end
        end
    end
    return any
end

-- Funken am Kolben: rieseln aus dem Fuellungsende nach unten/leicht seitlich, verglimmen (nur beim Auffuellen; secret:
-- zusaetzlich das "nicht voll"-Alpha am inneren Frame, voll => unsichtbar)
local function stepSparks(lb, fz, t, dt, spawn, h, top, len)
    local C = Fizz.CFG
    local any = false
    if spawn and t >= fz.nextS then
        fz.nextS = t + C.sparkEvery * (0.6 + 0.8 * math.random())
        -- nur am Kolben (Fuellungsende): Lage relativ zum Ende der Fuellung (Anker wie der Kolben, keine Breite gelesen)
        local P = ns.Liquid.PISTON
        spawnSpark(fz, -P.piston * h * (0.2 + 0.6 * math.random()), -h * (0.2 + 0.25 * math.random()), h)
    end
    for i = 1, #fz.s do
        if fz.sOn[i] then
            fz.sT[i] = fz.sT[i] + dt
            local u = fz.sT[i] / fz.sL[i]
            local tex = fz.s[i]
            if u >= 1 then
                fz.sOn[i] = false
                tex:Hide()
            else
                any = true
                fz.sX[i] = fz.sX[i] + fz.sVX[i] * dt
                fz.sY[i] = fz.sY[i] + fz.sVY[i] * dt
                fz.sVY[i] = fz.sVY[i] - C.sparkG * h * dt -- faellt
                fz.sVX[i] = fz.sVX[i] * (1 - 0.6 * dt)
                tex:ClearAllPoints()
                tex:SetPoint("CENTER", lb.barTex or lb.root, "RIGHT", fz.sX[i], fz.sY[i])
                tex:SetAlpha(C.sparkA * (1 - u) ^ 1.3)
                tex:Show()
            end
        end
    end
    return any
end

--- Ein Bild (aus LiquidFx.Step); liefert true, solange es sprudelt, ausblendet oder Sprites leben
function Fizz.Step(lb, t, dt)
    local fz = lb.fx.fizz
    if not fz.on then return false end
    local C = Fizz.CFG
    local want, sure
    if fz.own then -- Vorschau: nur der eigene Test
        want = t < (fz.testUntil or 0)
        sure = want
    else
        local reason
        want, sure, reason = decide(t)
        state.reason = reason
    end
    local a = fz.a
    if want then a = math.min(1, a + dt * C.fadeIn) else a = math.max(0, a - dt * C.fadeOut) end
    fz.a = a
    if fz.shownA ~= a then
        if fz.shownA == nil and a > 0 then
            fz.outer:Show()
            fz.sOuter:Show()
        end
        fz.shownA = a > 0 and a or nil
        fz.outer:SetAlpha(a)
        fz.sOuter:SetAlpha(a)
    end
    if fz.tint ~= lb.tint then -- Ressourcenfarbe, aufgehellt (nur bei Farbwechsel)
        fz.tint = lb.tint
        local c, k = lb.tint or WHITE, C.bright
        local r, g, b = c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k
        for i = 1, #fz.b do fz.b[i]:SetVertexColor(r, g, b) end
        for i = 1, #fz.s do fz.s[i]:SetVertexColor(r, g, b) end
    end
    local h, w = lb.h or 10, lb.w or 100
    local top = lb.style == "piston" and ns.Liquid.PISTON.gap * h or 0
    local len = math.min(lb.lenPx or w, w)
    local spawn = want and a > 0.3
    local b1 = stepBubbles(lb, fz, t, dt, spawn, h, top, len)
    local b2 = stepSparks(lb, fz, t, dt, spawn, h, top, len)
    if a <= 0 and not b1 and not b2 then
        if fz.outer:IsShown() then
            fz.outer:Hide()
            fz.sOuter:Hide()
        end
        return want
    end
    -- sanft unruhige Oberflaeche (Kolben-Kammer), nur wenn sicher regeneriert wird
    if sure and lb.style == "piston" and lb.field and t - fz.kickT > C.kickEvery then
        fz.kickT = t
        fz.sign = -fz.sign
        ns.LiquidWave.Kick(lb.field, "land", C.kickStr * a * (0.6 + 0.8 * math.random()), fz.sign)
    end
    return true
end

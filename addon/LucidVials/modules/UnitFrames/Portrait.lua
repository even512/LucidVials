-- Einheitenrahmen: animierte 2D-Portraits (Delta "Ausbau 1.1.0", E5). Ergaenzt Skin.lua ueber die Haken Skin.Portrait.Attach/
-- Refresh/Detach/Debug (Muster wie Deco.lua); nur eigene Frames/Texturen, an Blizzards Portrait nur SetAlpha (ueber
-- Skin.HideRegion/ShowRegion), nur bei nicht-statischem Stil.
--
-- Stile (Registry, Portrait.RegisterStyle(key, impl)); Bereich "portrait" = { style, intensity 0..1 } je Rahmen (nur Spieler und
-- Ziel; das Ziel des Ziels bleibt immer statisch):
--   static     Standard, das heutige Bild: Blizzards Portrait bleibt unberuehrt, es wird nichts angelegt, nichts angemeldet.
--   painting   "Lebendes Gemaelde": eigene Portrait-Textur (SetPortraitTexture ohne Blizzard-Maske + eigene Kreismaske),
--              Atmen (Zoom per TexCoord) und Kerzenlicht (warmes Flackern in unregelmaessigen Stufen), beides im Treiber
--              (Style.AddFastStepper, ruht bei unsichtbarem Rahmen; keine Abhaengigkeit von Engine-Animationen), Vignette, bei
--              wenig Leben Glasrisse (kuehl, mit Schattenkopie) und Roete per Kurven-Alpha (UnitHealthPercent mit Kurve ->
--              SetAlpha, secret-sicher), Treffer (roter Blitz) und Heilung (warmer Schein) ueber UNIT_COMBAT, Ausruhen
--              (ruhigeres Atmen/Licht), Tod (entsaettigt).
--   submerged  "Im Kolben versunken": die obere Kopie klar, darunter ganze Kopien in einem Clip bis zum Lebenspegel (eigene
--              unsichtbare vertikale StatusBar, Anker an deren Fuell-Textur wie die Fluessigkeit): Hauptkopie mit Tiefen-Toenung
--              (oben klar, unten dichter), zwei Geisterkopien waabern gegenlaeufig (Unschaerfe, keine Naehte), Kaustik-Netze,
--              Wasserlinie mit Meniskus, Blasen (Atlas uf-fx2-bubbles). Treiber wie oben, folgt auch dem Schwappen der Physik.
--   model      (E6, PortraitModel.lua) meldet sich ueber RegisterStyle an; fehlt der Stil oder faellt er aus (Portrait.Fallback),
--              gilt "painting".
-- Stil-Schnittstelle (alle Funktionen optional ausser Activate/Deactivate; P = Zustand je Rahmen, P.sk, P.id, P.unit, P.frame,
-- P.base, P.mask, P.cfg, P.s[key] = eigener Zustand des Stils):
--   Activate(P, cfg) / Deactivate(P)   Stil beginnt/endet (Blizzards Portrait ist dann verborgen bzw. zurueck)
--   Configure(P, cfg)                  Einstellungen (Staerke) geaendert
--   Layout(P)                          Groesse/Lage neu (P.size)
--   Refresh(P)                         Einheit/Portrait neu (Zielwechsel, UNIT_PORTRAIT_UPDATE)
--   OnHealth(P)                        UNIT_HEALTH/UNIT_MAXHEALTH
--   Tint(P)                            Fluessigkeitsfarbe geaendert (UNIT_FACTION)
--   React(P, what, arg)                "hit"|"heal" (arg = kritisch), "rest" (arg = ruht), "dead" (arg = tot); nur aus dem Testwort
--                                      ausserdem "cast", "combat" (arg = an) und "reset" (unbekannte Reaktionen still uebergehen)
--   Debug()                            optional: eigene Zeilen fuer /vials debug
--   TestLow(P, on)                     Testwort: "wenig Leben" erzwingen
--   Usable(P)                          false => Rueckfall auf "painting"
--   noGloss = true                     (Feld) kein Glasglanz ueber dem Stil (painting/submerged bekommen ihn von Portrait.lua)
-- Mini-Vorschau (Preview.lua, sk.preview): derselbe Zustand P auf einem Schein-Rahmen mit Einheit "player"; P.preview = true,
-- keine Ereignisse, kein Rueckfall-Signal an echte Rahmen; Pegel aus P.fakeFraction (eigene Zahl 0..1) statt UnitHealth, Tod
-- aus P.fakeDead. Modell-Stile ohne impl.previewSafe zeigen dort das Gemaelde (model) bzw. das Bild (modelplain).
-- Secret-Regel: Leben/Maximum gehen unveraendert (pcall) nur an StatusBar/SetAlpha, nie in Vergleiche, Rechnung, Schluessel,
-- tostring/format (tests/unitframes-portrait.test.mjs prueft die Funktionen statisch). UNIT_COMBAT: nur das Ereignis (und, wenn
-- lesbar, der Text); die Menge wird nie gelesen. Kein CLEU, keine Hooks auf Blizzard-Frames, nichts Geschuetztes.
-- Blickrichtung (Hotfix 1.1.4, Felder mirrorPlayer/mirrorTarget im Bereich "portrait", global: gelten immer getrennt je Rahmen,
-- unabhaengig vom Rahmen-Waehler; Standard false = wie bisher, nichts wird angefasst; ein frueheres gemeinsames Feld mirror wird
-- beim Pruefen uebernommen, Portrait.Migrate). frameConfig(id) liefert daraus cfg.mirror des Rahmens. Gespiegelt
-- tauschen alle Bild-Lagen links und rechts der TexCoords (P.mirror; texCoord/texCoord8/fullCoords unten): Gemaelde samt Zoom und
-- Effekt-Lagen (Vignette, Kerzenlicht, Risse samt Schattenkopie, Blitze), versunkene Kopien samt Wabern (Neigungs-Versatz mit
-- umgekehrtem Vorzeichen, damit er auf dem Bildschirm weiter der Physik folgt), die obere klare Kopie. Kreismaske, Glanz, Kaustik,
-- Wasserlinie und Blasen bleiben (symmetrisch bzw. Licht/Fluessigkeit der Welt). "static" + gespiegelt laeuft als interner Stil
-- "flat": eigenes rundes Bild (SetPortraitTexture in P.base, gespiegelt), Blizzards Portrait Alpha 0 (Blizzards Textur bekommt nie
-- ein SetTexCoord); ohne Glanz, ohne Reaktionen, nicht im Testwort. Modelle: PortraitModel.lua (SetFacing).
-- Texturen: Portrait.TEX (Platzhalter aus scripts/gen-portrait-placeholders.mjs, die Gemini-Bilder ersetzen die Dateien 1:1).
local _, ns = ...
local Compat, L = ns.Compat, ns.L
local Style = ns.Style
local Skin = ns.UnitFrameSkin

local Portrait = {}
ns.UnitPortrait = Portrait
Skin.Portrait = Portrait

local MEDIA = "Interface\\AddOns\\LucidVials\\Media\\"
-- Dateien (je 256 x 256, RGBA-TGA 32 bit, aus dem Gemini-Bogen docs/unitframe-src/sheet-portrait-v1.jpg per scripts/cut-portrait.mjs):
-- Vignette (schwarz, Alpha zum Rand), Glasrisse leicht/stark (kaltweiss), Kerzenlicht und Heilschein (weiss, ADD, Farbe per Vertexfarbe),
-- Glasglanz (weiss, ADD)
Portrait.TEX = { vignette = MEDIA .. "uf-portrait-vignette", cracks = MEDIA .. "uf-portrait-cracks",
    crackHeavy = MEDIA .. "uf-portrait-cracks-heavy", candle = MEDIA .. "uf-portrait-candle", heal = MEDIA .. "uf-portrait-heal",
    gloss = MEDIA .. "uf-portrait-gloss", mask = "Interface\\CharacterFrame\\TempPortraitAlphaMask" }
Portrait.WATERLINE = MEDIA .. "uf-portrait-waterline" -- 8 x 64, Lichtlinie bei Zeile 13, darunter ausklingender Glow
Portrait.BUBBLES = { path = MEDIA .. "uf-fx2-bubbles", n = 8, cells = { 1, 2, 3, 4, 5 } } -- wie LiquidFizz.TEX.bubble
Portrait.UNIT = { player = "player", target = "target" }
Portrait.STYLE_ORDER = { "static", "painting", "submerged", "model" }
Portrait.DEFAULT = { style = "static", intensity = 0.6, mirrorPlayer = false, mirrorTarget = false }
Portrait.MIRROR_FIELD = { player = "mirrorPlayer", target = "mirrorTarget" }
Portrait.PAINT = { breathBase = 0.02, breathScale = 0.05, breathSecs = 4.4, calmSecs = 7, vignetteBase = 0.3, vignette = 1.0,
    candle = 0.85, flickerMin = 0.3, flickerSecs = { 0.25, 1.1 }, flickerRate = 7, flickerJitter = 0.04, calmLight = 0.6,
    flash = { hit = { 0.55, 0.1, 0.8 }, heal = { 0.7, 0.15, 1.1 } }, -- { Spitze, Anstieg s, Abklingen s } (Spitze x Staerke)
    cracks = { { 0, 1 }, { 0.15, 1 }, { 0.4, 0 }, { 1, 0 } }, heavy = { { 0, 1 }, { 0.06, 1 }, { 0.18, 0 }, { 1, 0 } }, gloss = 0.9,
    blood = { { 0, 0.85 }, { 0.2, 0.55 }, { 0.5, 0 }, { 1, 0 } },
    -- Gemaelde: Risse wie Glas (kuehl, BLEND, nicht grell), Schattenkopie 1 px versetzt; starke Risse erst bei sehr wenig Leben
    crackColor = { 0.66, 0.78, 0.92 }, crackMax = 0.55, heavyMax = 0.5, shadowK = 0.5,
    heavyP = { { 0, 1 }, { 0.04, 1 }, { 0.09, 0.4 }, { 0.16, 0 }, { 1, 0 } },
    healColor = { 1, 0.82, 0.45 }, hitColor = { 0.9, 0.08, 0.05 }, candleColor = { 1, 0.62, 0.2 }, bloodColor = { 0.85, 0.05, 0.03 },
    crit = 1.4, testLow = 1 }
-- Im Kolben versunken: Geisterkopien (Alpha, Zoom, Wellengeschwindigkeit/-phase, drift = Mittelpunkt-Schwimmen, breath = Zoom-Atem),
-- Hauptkopie (main, kleine Amplitude), Tiefen-Toenung, Kaustik, Wasserlinie, Blasen. Wellen in TexCoord-Einheiten (60 px Portrait: 0.04 = ~2,4 px);
-- wUp/wLow gewichten die oberen/unteren Ecken (unten staerker, bleibt eine weiche Verzerrung ohne Naehte); waveCap deckelt das Treffer-Aufruehren
Portrait.SUB = { ghost = { { alpha = 0.42, zoom = 0.88, speed = 0.9, phase = 0, drift = 0.025, breath = 0.03 },
        { alpha = 0.32, zoom = 0.85, speed = 1.35, phase = 2.1, drift = 0.03, breath = 0.04 } },
    main = { zoom = 0.95, speed = 0.7, phase = 1.0, drift = 0.006, breath = 0.01 }, mainWave = 0.018, mainCap = 0.03,
    wave = 0.04, waveMax = 0.07, waveCap = 0.11, wUp = 0.7, wLow = 1.4, tilt = 0.02, boost = 1.8, boostK = 0.4, boostDecay = 1.4, calm = 0.5,
    topMix = { 0.08, 0.26 }, deepMix = { 0.5, 0.9 }, deepDark = 0.45, desat = 0.3,
    -- Tiefen-Toenung als eigener Verlauf ab der Wasserlinie (Anker am Clip): oben fast klar, nach unten tiefer (kein Toenungssprung an der Kante)
    tintTopA = 0.1, tintDeepA = { 0.45, 0.85 }, tintDeepK = 0.4,
    caustic = 0.14, causticTile = 2.0, causticMove = { { 0.02, 0.013 }, { -0.015, 0.021 } },
    -- Wasserlinie: eine weiche Verlaufstextur (uf-portrait-waterline) je Haelfte, im Treiber geneigt/gewellt (Neigung folgt physicsTilt)
    surfAlpha = 0.26, surfHeight = 0.2, surfSway = 0.09, surfTilt = 0.12,
    bubbles = 4, bubbleSize = { 0.085, 0.125 }, bubbleAlpha = 0.8, bubbleSecs = { 3.2, 4.1, 3.7, 4.6 }, bubbleX = { 0.28, 0.5, 0.68, 0.4 },
    testLow = 0.25 }

-- Hilfen --------------------------------------------------------------------------------------------------------------------
local function call(obj, method, ...)
    if type(obj) ~= "table" then return false end
    local fn = obj[method]
    if type(fn) ~= "function" then return false end
    return pcall(fn, obj, ...)
end

local function recordError(err)
    if Skin.RecordError then Skin.RecordError(err) end
end

local function readFlag(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or Compat.IsSecret(v) then return nil end
    return v
end

--- Blickrichtung: TexCoords (4-Wert-Form) mit getauschtem Links/Rechts, wenn der Rahmen gespiegelt ist
local function texCoord(P, tex, u0, u1, v0, v1)
    if P and P.mirror then return tex:SetTexCoord(u1, u0, v0, v1) end
    return tex:SetTexCoord(u0, u1, v0, v1)
end

--- dasselbe fuer die 8-Wert-Form (Ecken oben links, unten links, oben rechts, unten rechts): linke und rechte Ecken tauschen
local function texCoord8(P, tex, ulx, uly, llx, lly, urx, ury, lrx, lry)
    if P and P.mirror then return tex:SetTexCoord(urx, ury, lrx, lry, ulx, uly, llx, lly) end
    return tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

--- ganze Textur gespiegelt bzw. zurueck; ungespiegelt und nie gespiegelt: kein Aufruf (Standard unveraendert)
local mirroredTex = setmetatable({}, { __mode = "k" })
local function fullCoords(P, tex)
    if not tex then return end
    if P and P.mirror then
        tex:SetTexCoord(1, 0, 0, 1)
        mirroredTex[tex] = true
    elseif mirroredTex[tex] then
        tex:SetTexCoord(0, 1, 0, 1)
        mirroredTex[tex] = nil
    end
end

local function fullCoordsAll(P, list)
    for _, t in ipairs(list) do fullCoords(P, t) end
end

--- Textur ungespiegelt zuruecklassen (sie gehoert auch den anderen Stilen)
local function unmirror(tex) fullCoords(nil, tex) end

local function clamp01(x) return math.max(0, math.min(1, x)) end

local function mix(a, b, k) return a + (b - a) * k end

local stats = { setCalls = 0, steps = 0, ms = 0, msMax = 0, combat = {}, lastAction = {}, curve = {}, errors = 0 }
local prof = type(debugprofilestop) == "function" and debugprofilestop or nil

local function newMask(frame)
    local ok, m = pcall(frame.CreateMaskTexture, frame)
    if not ok or not m then return nil end
    if not pcall(m.SetTexture, m, Portrait.TEX.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then return nil end
    return m
end

local function addMask(tex, mask)
    if tex and mask then pcall(tex.AddMaskTexture, tex, mask) end
end

--- Textur mit Pfad, Kreismaske und Zeichenebene in einem Frame anlegen
local function layer(frame, mask, drawLayer, sub, path)
    local t = frame:CreateTexture(nil, drawLayer, nil, sub)
    if path then t:SetTexture(path) end
    t:SetAllPoints(frame)
    addMask(t, mask)
    return t
end

local IMMEDIATE, EXP
local function readEnum()
    local e = type(Enum) == "table" and Enum.StatusBarInterpolation or nil
    if type(e) ~= "table" then return end
    IMMEDIATE, EXP = Compat.Num(e.Immediate), Compat.Num(e.ExponentialEaseOut)
end

--- Wert an eine StatusBar (secret erlaubt, nur durchgereicht); interp = Engine-Gleiten oder sofort
local function setBarValue(bar, v, glide)
    if IMMEDIATE == nil then readEnum() end
    local interp = glide and EXP or IMMEDIATE
    if interp ~= nil and pcall(bar.SetValue, bar, v, interp) then return true end
    return (pcall(bar.SetValue, bar, v))
end

--- Maximum und Wert des Lebens an eine StatusBar (secret erlaubt, nur durchgereicht)
local function feedBar(bar, unit, glide)
    local okM, mx = pcall(UnitHealthMax, unit)
    if okM then pcall(bar.SetMinMaxValues, bar, 0, mx) end
    local okV, v = pcall(UnitHealth, unit)
    if okV then setBarValue(bar, v, glide) end
end

--- Alpha einer Textur auf das (secret) Ergebnis einer Prozent-Kurve; false, wenn die Kurve/API fehlt oder wirft
local function curveAlpha(tex, unit, curve)
    if curve == nil then return false end
    local okF, v = pcall(UnitHealthPercent, unit, false, curve)
    if not okF then return false end
    return (pcall(tex.SetAlpha, tex, v))
end

--- Lesbarer Lebensanteil 0..1 (nur wenn weder Leben noch Maximum secret sind), sonst nil
local function readableFraction(unit)
    local okV, hp = pcall(UnitHealth, unit)
    local okM, mx = pcall(UnitHealthMax, unit)
    if not (okV and okM) then return nil end
    local cur, max = Compat.Num(hp), Compat.Num(mx)
    if cur and max and max > 0 then return clamp01(cur / max) end
    return nil
end

local function evalPoints(points, x)
    if x <= points[1][1] then return points[1][2] end
    for i = 2, #points do
        if x <= points[i][1] then
            local a, b = points[i - 1], points[i]
            if b[1] == a[1] then return b[2] end
            return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
        end
    end
    return points[#points][2]
end

-- Kurven (C_CurveUtil, secret-sicher): Lebensanteil 0..1 -> Alpha; je Staerke einmal angelegt (Staerke in 5-%-Stufen)
local curveCache = {}
local function makeCurve(points, k)
    local C = _G.C_CurveUtil
    if not (C and type(C.CreateCurve) == "function") then return nil end
    local ok, c = pcall(C.CreateCurve)
    if not ok or (type(c) ~= "table" and type(c) ~= "userdata") then return nil end
    local linear = type(Enum) == "table" and type(Enum.LuaCurveType) == "table" and Enum.LuaCurveType.Linear or 0
    pcall(c.SetType, c, linear)
    for _, p in ipairs(points) do pcall(c.AddPoint, c, p[1], p[2] * k) end
    return c
end

--- Kurven (cracks, blood, heavy); painting = true liefert die Gemaelde-Fassung: cracks, blood, heavy, Schatten cracks, Schatten heavy
local function curvesFor(intensity, painting)
    local key = math.floor(intensity * 20 + 0.5)
    local c = curveCache[key]
    if not c then
        local k, P = key / 20, Portrait.PAINT
        c = { cracks = makeCurve(P.cracks, k) or false, blood = makeCurve(P.blood, k) or false, heavy = makeCurve(P.heavy, k) or false }
        curveCache[key] = c
    end
    if painting then
        if not c.pCracks then
            local k, P = key / 20, Portrait.PAINT
            c.pCracks = makeCurve(P.cracks, k * P.crackMax) or false
            c.pHeavy = makeCurve(P.heavyP, k * P.heavyMax) or false
            c.sCracks = makeCurve(P.cracks, k * P.crackMax * P.shadowK) or false
            c.sHeavy = makeCurve(P.heavyP, k * P.heavyMax * P.shadowK) or false
        end
        return c.pCracks or nil, c.blood or nil, c.pHeavy or nil, c.sCracks or nil, c.sHeavy or nil
    end
    return c.cracks or nil, c.blood or nil, c.heavy or nil
end

-- Animationen (Engine) ------------------------------------------------------------------------------------------------------
local function newGroup(region, loop)
    local ok, g = pcall(region.CreateAnimationGroup, region)
    if not ok or type(g) ~= "table" then return nil end
    if loop then call(g, "SetLooping", loop) end
    return g
end

local function newAnim(g, kind, order, secs)
    if not g then return nil end
    local ok, a = pcall(g.CreateAnimation, g, kind)
    if not ok or type(a) ~= "table" then return nil end
    call(a, "SetOrder", order)
    call(a, "SetDuration", secs)
    return a
end

local function setScale(a, from, to)
    if type(a.SetScaleFrom) == "function" and type(a.SetScaleTo) == "function" then
        pcall(a.SetScaleFrom, a, from, from)
        pcall(a.SetScaleTo, a, to, to)
    elseif type(a.SetFromScale) == "function" and type(a.SetToScale) == "function" then
        pcall(a.SetFromScale, a, from, from)
        pcall(a.SetToScale, a, to, to)
    elseif type(a.SetScale) == "function" then
        pcall(a.SetScale, a, to, to)
    end
end

local function playGroup(g)
    if not g then return end
    call(g, "Stop")
    call(g, "Play")
end

-- Portrait-Texturen ---------------------------------------------------------------------------------------------------------
local function setPortrait(tex, unit)
    stats.setCalls = stats.setCalls + 1
    if type(SetPortraitTexture) ~= "function" then return false end
    return (pcall(SetPortraitTexture, tex, unit, true)) -- true: ohne Blizzards Maske, die Kreismaske ist unsere
end

local function setDesaturated(tex, on) call(tex, "SetDesaturated", on and true or false) end

local function physicsTilt()
    local P = ns.LiquidPhysics
    if not (P and type(P.Current) == "function") then return 0 end
    local ok, tilt = pcall(P.Current)
    tilt = ok and Compat.Num(tilt) or nil
    if not tilt then return 0 end
    local limit = Compat.Num(P.LIMIT) or 1
    if limit <= 0 then limit = 1 end
    return math.max(-1, math.min(1, tilt / limit))
end

--- Fluessigkeitsfarbe des Rahmens (Lebensroehre), auf vergleichbare Helligkeit gehoben
local function liquidColor(P)
    local lb = P.sk and P.sk.health
    local t = lb and lb.tintArg
    local c = type(t) == "table" and ((t.tex == "color" and t.base) or t.color) or nil
    if type(c) ~= "table" or not (Compat.Num(c[1]) and Compat.Num(c[2]) and Compat.Num(c[3])) then c = { 0.46, 0.82, 0.30 } end
    local m = math.max(c[1], c[2], c[3], 0.01)
    local k = 0.85 / m
    return math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k)
end

-- Stil "painting" -----------------------------------------------------------------------------------------------------------
local Painting = {}

local function flashGroup(tex)
    local g = newGroup(tex)
    local up, down = newAnim(g, "Alpha", 1, 0.1), newAnim(g, "Alpha", 2, 0.5)
    if up then call(up, "SetFromAlpha", 0); call(up, "SetToAlpha", 0.5); call(up, "SetSmoothing", "OUT") end
    if down then call(down, "SetFromAlpha", 0.5); call(down, "SetToAlpha", 0); call(down, "SetSmoothing", "IN") end
    return { g = g, up = up, down = down }
end

--- Kopie von layer() ohne SetAllPoints: Schattenkopie der Risse, 1 px nach rechts unten versetzt (gibt den Rissen Tiefe)
local function shadowLayer(f, mask, sub, path)
    local t = layer(f, mask, "OVERLAY", sub, path)
    t:SetVertexColor(0, 0, 0)
    t:SetAlpha(0)
    return t
end

local function placeShadow(t, f, off)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", f, "TOPLEFT", off, -off)
    t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", off, -off)
end

local function buildPainting(P)
    local C, T = Portrait.PAINT, Portrait.TEX
    local f, s = P.frame, {}
    local ck = C.crackColor
    s.blood = layer(f, P.mask, "OVERLAY", 0, T.vignette)
    s.blood:SetVertexColor(C.bloodColor[1], C.bloodColor[2], C.bloodColor[3])
    s.blood:SetAlpha(0)
    s.vig = layer(f, P.mask, "OVERLAY", 1, T.vignette)
    s.vig2 = layer(f, P.mask, "OVERLAY", 1, T.vignette) -- doppelt gelegt: die Randabdunkelung wird deutlich (Alpha 1 - (1 - a)^2)
    s.candle = layer(f, P.mask, "OVERLAY", 2, T.candle)
    s.candle:SetVertexColor(C.candleColor[1], C.candleColor[2], C.candleColor[3])
    call(s.candle, "SetBlendMode", "ADD")
    s.crackS = shadowLayer(f, P.mask, 3, T.cracks)
    s.cracks = layer(f, P.mask, "OVERLAY", 4, T.cracks)
    s.cracks:SetVertexColor(ck[1], ck[2], ck[3])
    s.cracks:SetAlpha(0)
    s.heavyS = shadowLayer(f, P.mask, 5, T.crackHeavy)
    s.heavy = layer(f, P.mask, "OVERLAY", 6, T.crackHeavy) -- sehr wenig Leben
    s.heavy:SetVertexColor(ck[1], ck[2], ck[3])
    s.heavy:SetAlpha(0)
    s.heal = layer(f, P.mask, "OVERLAY", 7, T.heal)
    s.heal:SetVertexColor(C.healColor[1], C.healColor[2], C.healColor[3])
    call(s.heal, "SetBlendMode", "ADD")
    s.heal:SetAlpha(0)
    s.hit = layer(f, P.mask, "OVERLAY", 7, T.vignette)
    s.hit:SetVertexColor(C.hitColor[1], C.hitColor[2], C.hitColor[3])
    s.hit:SetAlpha(0)
    s.all = { s.vig, s.vig2, s.candle, s.cracks, s.crackS, s.heavy, s.heavyS, s.blood, s.heal, s.hit }
    -- Atmen und Kerzenlicht laufen im Treiber (Portrait.Step, jedes Bild, ruht bei unsichtbarem Rahmen): Zoom per TexCoord des
    -- Portraits, Flackern als Alpha der Kerzenlicht-Textur in unregelmaessigen, weich eingeschwungenen Stufen
    s.phase, s.zoom, s.cLevel, s.cTarget, s.cNext = 0, 1, 0.7, 0.7, 0
    s.healFx, s.hitFx = flashGroup(s.heal), flashGroup(s.hit)
    return s
end

--- Staerkeabhaengige Festwerte (Vignette); Atmen/Kerzenlicht setzt der Treiber
local function applyPainting(P, s)
    local C, i = Portrait.PAINT, P.cfg.intensity
    s.lastI = i
    local a = math.min(1, (C.vignetteBase + C.vignette * i) * math.min(1, i * 8))
    s.vig:SetAlpha(a)
    s.vig2:SetAlpha(a)
end

--- Atmen und Kerzenlicht eines sichtbaren Gemaelde-Rahmens um dt Sekunden (Zeit t) weiterschalten
local function stepPainting(P, s, t, dt)
    local C, i = Portrait.PAINT, P.cfg.intensity
    local f = math.min(1, i * 8) -- Staerke 0 schaltet beides ab
    local calm = P.calm and true or false
    s.phase = (s.phase + dt * 6.2831853 / (calm and C.calmSecs or C.breathSecs)) % 6.2831853
    local z = 1 + (C.breathBase + C.breathScale * i) * f * (0.5 - 0.5 * math.cos(s.phase))
    if math.abs(z - s.zoom) > 0.0002 then
        s.zoom = z
        local h = 0.5 / z
        texCoord(P, P.base, 0.5 - h, 0.5 + h, 0.5 - h, 0.5 + h)
    end
    if t >= s.cNext then
        s.cTarget = C.flickerMin + (1 - C.flickerMin) * math.random()
        s.cNext = t + C.flickerSecs[1] + (C.flickerSecs[2] - C.flickerSecs[1]) * math.random()
    end
    s.cLevel = s.cLevel + (s.cTarget - s.cLevel) * math.min(1, dt * C.flickerRate)
    local jitter = C.flickerJitter * math.sin(t * 23.0)
    local lvl = math.max(0, math.min(1, s.cLevel + jitter))
    s.candleAlpha = C.candle * (0.3 + 0.7 * lvl) * (0.3 + 0.7 * i) * f * (calm and C.calmLight or 1)
    s.candle:SetAlpha(s.candleAlpha)
end

--- wenig Leben: Glasrisse (mit Schattenkopie) und Roete per Kurven-Alpha (secret-sicher); lesbar rechnet Lua dieselben Kurven selbst
local function updateLow(P)
    local s, C = P.s.painting, Portrait.PAINT
    if not s then return end
    local i = P.cfg.intensity
    if P.testLow then
        s.cracks:SetAlpha(C.testLow * i * C.crackMax)
        s.crackS:SetAlpha(C.testLow * i * C.crackMax * C.shadowK)
        s.heavy:SetAlpha(C.testLow * i * C.heavyMax)
        s.heavyS:SetAlpha(C.testLow * i * C.heavyMax * C.shadowK)
        s.blood:SetAlpha(C.testLow * i * C.blood[1][2])
        return
    end
    local frac = P.fakeFraction -- Mini-Vorschau: eigene, lesbare Zahl
    if frac == nil then
        local cc, bc, hc, cs, hs = curvesFor(i, true)
        local ok = curveAlpha(s.cracks, P.unit, cc)
        ok = curveAlpha(s.crackS, P.unit, cs) and ok
        ok = curveAlpha(s.heavy, P.unit, hc) and ok
        ok = curveAlpha(s.heavyS, P.unit, hs) and ok
        ok = curveAlpha(s.blood, P.unit, bc) and ok
        stats.curve[P.id] = ok and "kurve" or "lua"
        if ok then return end
        frac = readableFraction(P.unit)
    end
    if frac then
        local c, h = evalPoints(C.cracks, frac) * i * C.crackMax, evalPoints(C.heavyP, frac) * i * C.heavyMax
        s.cracks:SetAlpha(c)
        s.crackS:SetAlpha(c * C.shadowK)
        s.heavy:SetAlpha(h)
        s.heavyS:SetAlpha(h * C.shadowK)
        s.blood:SetAlpha(evalPoints(C.blood, frac) * i)
    else
        for _, t in ipairs({ s.cracks, s.crackS, s.heavy, s.heavyS, s.blood }) do t:SetAlpha(0) end
        stats.curve[P.id] = "aus"
    end
end

--- tot? Mini-Vorschau: eigener Schalter P.fakeDead (die Einheit "player" der Vorschau ist nur das Bild)
local function isDead(P)
    if P.preview then return P.fakeDead == true end
    return readFlag(UnitIsDeadOrGhost, P.unit) == true
end

local function updateDead(P, s)
    local dead = isDead(P)
    setDesaturated(P.base, dead)
    return dead
end

local paintList = {} -- aktive Gemaelde (fuer den Treiber)

local function addTo(list, P)
    for _, x in ipairs(list) do if x == P then return end end
    list[#list + 1] = P
end

local function dropFrom(list, P)
    for k = #list, 1, -1 do if list[k] == P then table.remove(list, k) end end
end

function Painting.Activate(P, cfg)
    local s = P.s.painting
    if not s then
        s = buildPainting(P)
        P.s.painting = s
    end
    for _, t in ipairs(s.all) do t:Show() end
    P.calm = not P.preview and P.unit == "player" and readFlag(IsResting) == true or false
    P.cfg = cfg
    s.cNext = 0
    s.zoom, s.mirror = 0, P.mirror -- Blickrichtung kann gewechselt haben: der Treiber setzt den Zoom neu
    fullCoordsAll(P, s.all)
    applyPainting(P, s)
    Painting.Layout(P)
    Painting.Refresh(P)
    addTo(paintList, P)
    Portrait.Wake()
end

function Painting.Deactivate(P)
    local s = P.s.painting
    dropFrom(paintList, P)
    if not s then return end
    for _, g in ipairs({ s.healFx.g, s.hitFx.g }) do call(g, "Stop") end
    for _, t in ipairs(s.all) do t:Hide() end
    P.base:SetTexCoord(0, 1, 0, 1) -- Zoom des Atmens zuruecknehmen (die Textur gehoert auch den anderen Stilen)
    mirroredTex[P.base] = nil
    s.zoom = 1
    setDesaturated(P.base, false)
    P.testLow = nil
    s.lastI = nil
end

function Painting.Layout(P)
    local s = P.s.painting
    if not s then return end
    local off = math.max(1, (P.size or 50) / 50)
    placeShadow(s.crackS, P.frame, off)
    placeShadow(s.heavyS, P.frame, off)
end

function Painting.Configure(P, cfg)
    local s = P.s.painting
    if not s then return end
    P.cfg = cfg
    if s.mirror ~= P.mirror then -- Blickrichtung umgeschaltet: Effekt-Lagen spiegeln, der Treiber setzt den Zoom neu
        s.mirror = P.mirror
        fullCoordsAll(P, s.all)
        s.zoom = 0
    end
    if s.lastI ~= cfg.intensity then applyPainting(P, s) end
    updateLow(P)
end

function Painting.Refresh(P)
    local s = P.s.painting
    if not s then return end
    setPortrait(P.base, P.unit)
    s.zoom = 0 -- SetPortraitTexture kann die TexCoords zuruecksetzen: der Treiber setzt den Zoom neu
    updateDead(P, s)
    updateLow(P)
end

function Painting.OnHealth(P)
    updateLow(P)
    if P.s.painting then updateDead(P, P.s.painting) end -- Tod auch ueber UNIT_HEALTH (Ziel hat kein PLAYER_DEAD)
end

function Painting.TestLow(P, on)
    P.testLow = on and true or nil
    updateLow(P)
end

local function flash(fx, name, i, crit)
    local C = Portrait.PAINT.flash[name]
    local peak = math.min(1, C[1] * i * (crit and Portrait.PAINT.crit or 1))
    call(fx.g, "Stop") -- Werte nur im Stand setzen (die Engine erlaubt es waehrend des Laufs nicht ueberall)
    if fx.up then call(fx.up, "SetFromAlpha", 0); call(fx.up, "SetToAlpha", peak); call(fx.up, "SetDuration", C[2]) end
    if fx.down then call(fx.down, "SetFromAlpha", peak); call(fx.down, "SetToAlpha", 0); call(fx.down, "SetDuration", C[3]) end
    call(fx.g, "Play")
end

function Painting.React(P, what, arg)
    local s = P.s.painting
    if not s then return end
    local i = P.cfg.intensity
    if what == "hit" then
        flash(s.hitFx, "hit", i, arg)
    elseif what == "heal" then
        flash(s.healFx, "heal", i, arg)
    elseif what == "rest" then
        P.calm = arg and true or false -- der Treiber liest P.calm (ruhigeres Atmen, ruhigeres Licht)
    elseif what == "dead" then
        setDesaturated(P.base, arg)
    end
end

-- Stil "submerged" ----------------------------------------------------------------------------------------------------------
-- Unter dem Lebenspegel (Clip an der Fuell-Textur einer vertikalen StatusBar) liegen ganze Portrait-Kopien statt Streifen (keine
-- Naehte): die Hauptkopie klar getoent, darueber zwei Geisterkopien mit niedriger Alpha, die gegenlaeufig waabern (Zoom und
-- Eckverzerrung per 8-Wert-TexCoord im Treiber) = Unschaerfe und Lichtbrechung. Toenung nimmt zur Tiefe zu (oben klar, unten
-- dichter, dunkler, leicht entsaettigt: Farbverlauf), zwei Kaustik-Netze wandern langsam darueber, an der Pegelkante liegt eine
-- helle Wasserlinie mit Lichtband und leicht hellerem Rand (Meniskus). Oberhalb des Pegels bleibt das Portrait klar.
local Submerged = {}
local subList = {}    -- aktive Zustaende (fuer den Treiber)
local stepperOn = false

--- Farbverlauf (unten -> oben) auf eine Textur; ohne SetGradient eine flache Mittelfarbe. Farben { r, g, b, a }
local function setGradient(tex, bottom, top)
    local ok = type(CreateColor) == "function" and call(tex, "SetGradient", "VERTICAL",
        CreateColor(bottom[1], bottom[2], bottom[3], bottom[4]), CreateColor(top[1], top[2], top[3], top[4]))
    if not ok then
        tex:SetVertexColor((bottom[1] + top[1]) / 2, (bottom[2] + top[2]) / 2, (bottom[3] + top[3]) / 2, (bottom[4] + top[4]) / 2)
    end
end

local function buildSubmerged(P)
    local S, B = Portrait.SUB, Portrait.BUBBLES
    local f, s = P.frame, { copies = {}, bubbles = {}, boost = 0 }
    s.bar = CreateFrame("StatusBar", nil, f)
    s.bar:SetAllPoints(f)
    pcall(s.bar.SetOrientation, s.bar, "VERTICAL")
    pcall(s.bar.SetStatusBarTexture, s.bar, "Interface\\Buttons\\WHITE8X8")
    pcall(s.bar.SetMinMaxValues, s.bar, 0, 1)
    local okT, tex = pcall(s.bar.GetStatusBarTexture, s.bar)
    s.barTex = okT and type(tex) == "table" and tex or nil
    if s.barTex then s.barTex:SetAlpha(0) end
    -- Clip: von der Fuellkante (Anker an der Fuell-Textur, wie die Fluessigkeit) bis zum Boden des Portraits
    s.clip = CreateFrame("Frame", nil, f)
    call(s.clip, "SetClipsChildren", true)
    s.clip:SetPoint("TOPLEFT", s.barTex or f, "TOPLEFT", 0, 0)
    s.clip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    s.mask = newMask(s.clip)
    if s.mask then s.mask:SetAllPoints(f) end
    -- Kopien: 1 = Hauptkopie, 2.. = Geisterkopien (je ein SetPortraitTexture, nur bei Ereignissen)
    for k = 1, 1 + #S.ghost do
        local t = s.clip:CreateTexture(nil, "ARTWORK", nil, k - 1)
        t:SetAllPoints(f)
        addMask(t, s.mask)
        s.copies[k] = t
    end
    -- Tiefen-Toenung: Verlauf ueber den Clip (an der Wasserlinie ~ klar, am Boden tief), BLEND ueber den Kopien, unter der Kaustik
    s.tint = s.clip:CreateTexture(nil, "ARTWORK", nil, 3)
    s.tint:SetTexture("Interface\\Buttons\\WHITE8X8")
    s.tint:SetAllPoints(s.clip)
    addMask(s.tint, s.mask)
    -- Kaustik: zwei kachelbare Netze (ADD), im Treiber gegenlaeufig verschoben
    local cpath = ns.Liquid and ns.Liquid.CAUSTIC_TEX or (MEDIA .. "uf-caustic")
    s.caustics = {}
    for k = 1, 2 do
        local t = s.clip:CreateTexture(nil, "ARTWORK", nil, 3 + k)
        t:SetTexture(cpath, "REPEAT", "REPEAT")
        t:SetAllPoints(f)
        call(t, "SetBlendMode", "ADD")
        addMask(t, s.mask)
        s.caustics[k] = t
    end
    -- Wasserlinie: weicher Verlauf (Lichtlinie + ausklingender Glow), zwei Haelften an der Fuellkante; die Kreismaske schneidet die Seiten
    -- sauber (keine Rechteck-Kanten), im Treiber neigt/wellt 8-Wert-TexCoord die Haelften (Knick in der Mitte = Woge)
    s.surf, s.surfFx = {}, {}
    for k = 1, 2 do
        local t = s.clip:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetTexture(Portrait.WATERLINE)
        call(t, "SetBlendMode", "ADD")
        addMask(t, s.mask)
        s.surf[k] = t
        s.surfFx[k] = flashGroup(t)
    end
    -- Blasen: Atlas-Zellen, steigen im Clip auf (Translation, wiederholt); sie verschwinden an der Fluessigkeitskante
    for k = 1, S.bubbles do
        local t = s.clip:CreateTexture(nil, "OVERLAY", nil, 3)
        t:SetTexture(B.path)
        local cell = B.cells[((k - 1) % #B.cells) + 1]
        t:SetTexCoord((cell - 1) / B.n, cell / B.n, 0, 1)
        addMask(t, s.mask)
        local g = newGroup(t, "REPEAT")
        local move = newAnim(g, "Translation", 1, S.bubbleSecs[((k - 1) % #S.bubbleSecs) + 1])
        s.bubbles[k] = { tex = t, g = g, move = move }
    end
    return s
end

--- Toenung: Kopien ungetoent; Tiefen-Verlauf (s.tint) ab der Wasserlinie oben klar, nach unten dichter/dunkler; Wasserlinie in heller Fluessigkeitsfarbe
local function tintSubmerged(P, s)
    local S, i = Portrait.SUB, P.cfg.intensity
    local r, g, b = liquidColor(P)
    local dm = mix(S.deepMix[1], S.deepMix[2], i)
    local deep = { mix(1, r, dm), mix(1, g, dm), mix(1, b, dm) }
    local lum = 0.3 * deep[1] + 0.59 * deep[2] + 0.11 * deep[3]
    for c = 1, 3 do deep[c] = mix(deep[c], lum, S.desat) * mix(1, S.deepDark, i) end
    for k, t in ipairs(s.copies) do
        t:SetVertexColor(1, 1, 1, k == 1 and 1 or S.ghost[k - 1].alpha * (0.5 + 0.5 * i)) -- Kopien ungetoent, die Toenung liegt als Verlauf darueber
    end
    local dk, da = S.tintDeepK, mix(S.tintDeepA[1], S.tintDeepA[2], i)
    -- gleiche dunkle Farbe oben und unten, nur die Deckkraft steigt (kein Aufhellen/Ausbleichen des Bildes an der Wasserlinie)
    local tc = { deep[1] * dk, deep[2] * dk, deep[3] * dk }
    setGradient(s.tint, { tc[1], tc[2], tc[3], da }, { tc[1], tc[2], tc[3], S.tintTopA * i })
    local wr, wg, wb = mix(1, r, 0.45), mix(1, g, 0.45), mix(1, b, 0.45)
    local ca = S.caustic * (0.4 + 0.6 * i)
    for _, t in ipairs(s.caustics) do t:SetVertexColor(wr, wg, wb, ca) end
    for k, t in ipairs(s.surf) do
        t:SetVertexColor(wr, wg, wb, S.surfAlpha * math.min(1, i * 2))
        local fx = s.surfFx[k]
        if fx.up then
            local peak = math.min(1, S.surfAlpha * 2 * i)
            call(fx.up, "SetToAlpha", peak)
            call(fx.down, "SetFromAlpha", peak)
        end
    end
end

local function layoutSubmerged(P, s)
    local S, size = Portrait.SUB, P.size or 40
    s.clip:SetFrameLevel(P.frame:GetFrameLevel() + 1) -- ueber dem Portrait-Frame, unter dem Glanz (+ 2)
    for k, t in ipairs(s.surf) do
        t:ClearAllPoints()
        t:SetPoint(k == 1 and "TOPLEFT" or "TOP", s.clip, k == 1 and "TOPLEFT" or "TOP", 0, 0)
        t:SetPoint(k == 1 and "TOP" or "TOPRIGHT", s.clip, k == 1 and "TOP" or "TOPRIGHT", 0, 0)
        t:SetHeight(math.max(4, size * S.surfHeight))
    end
    for k, bb in ipairs(s.bubbles) do
        local px = math.max(3, math.floor(size * mix(S.bubbleSize[1], S.bubbleSize[2], (k % 2 == 0) and 1 or 0) + 0.5))
        bb.tex:SetSize(px, px)
        bb.tex:ClearAllPoints()
        bb.tex:SetPoint("BOTTOM", P.frame, "BOTTOMLEFT", size * S.bubbleX[((k - 1) % #S.bubbleX) + 1], 1)
        if bb.move then
            call(bb.move, "SetOffset", ((k % 2 == 0) and 1 or -1) * size * 0.04, size * 0.95)
        end
    end
end

local function playBubbles(P, s)
    local i = P.cfg.intensity
    for _, bb in ipairs(s.bubbles) do
        call(bb.g, "Stop")
        bb.tex:SetAlpha(Portrait.SUB.bubbleAlpha * i)
        if i > 0 then call(bb.g, "Play") end
    end
end

local function levelSubmerged(P, s, glide)
    if P.testLow then
        pcall(s.bar.SetMinMaxValues, s.bar, 0, 1)
        setBarValue(s.bar, Portrait.SUB.testLow, glide)
        return
    end
    if P.fakeFraction ~= nil then -- Mini-Vorschau: eigene Zahl 0..1
        pcall(s.bar.SetMinMaxValues, s.bar, 0, 1)
        setBarValue(s.bar, P.fakeFraction, glide)
        return
    end
    feedBar(s.bar, P.unit, glide)
end

function Portrait.Wake()
    if #subList + #paintList == 0 or not (Style and Style.AddFastStepper and Style.WakeDriver) then return end
    if not stepperOn then
        stepperOn = true
        Style.AddFastStepper(Portrait.Step)
    end
    Style.WakeDriver()
end

--- Wabern einer Kopie (Haupt- und Geisterkopien): Mittelpunkt schwimmt (drift, u/v verschieden schnell), Zoom atmet (breath) und je
--- Ecke eine eigene Welle (8-Wert-TexCoord: weiche Verzerrung ohne Naehte, ein Aufruf, keine neuen Anker); untere Ecken staerker.
--- Geht die 8-Wert-Form im Client nicht, gilt dieselbe Bewegung ohne Eckwelle in der 4-Wert-Form (Versatz + Zoom bleiben sichtbar)
--- Welle einer Ecke k (ohne Closure je Bild)
local function wave(amp, t, w, ph, k) return amp * math.sin(t * w + ph + k * 1.7) end

local warp8 = true

local function warp(P, tex, t, amp, g, shift)
    local S = Portrait.SUB
    local w, ph = g.speed, g.phase
    local h = 0.5 * g.zoom * (1 + g.breath * math.sin(t * w * 0.8 + ph + 0.9))
    local cx = 0.5 + shift + g.drift * math.sin(t * w + ph)
    local cy = 0.5 + g.drift * 0.8 * math.sin(t * w * 0.7 + ph + 1.3)
    local u0, u1, v0, v1 = cx - h, cx + h, cy - h, cy + h
    if warp8 then
        local up, lo = amp * S.wUp, amp * S.wLow
        local ok = pcall(texCoord8, P, tex, u0 + wave(up, t, w, ph, 0), v0 + wave(up, t, w, ph, 1), u0 + wave(lo, t, w, ph, 2),
            v1 + wave(lo, t, w, ph, 3), u1 + wave(up, t, w, ph, 4), v0 + wave(up, t, w, ph, 5), u1 + wave(lo, t, w, ph, 6),
            v1 + wave(lo, t, w, ph, 7))
        if ok then return end
        warp8 = false
    end
    texCoord(P, tex, u0, u1, v0, v1)
end

--- Wasserlinie neigen/wellen: je Haelfte ein 8-Wert-TexCoord, der den Verlauf senkrecht verschiebt (links dL, Mitte dM, rechts dR; + = Linie
--- hoeher); gemeinsame Naht in der Mitte (dM). Ohne 8-Wert-Form: eine mittlere Verschiebung (4-Wert), die Linie bleibt gerade
local function surfWave(s, t, tilt, i, calm)
    local S = Portrait.SUB
    local sw = S.surfSway * (0.4 + 0.6 * i) * calm
    local tl = tilt * S.surfTilt
    local dL = sw * math.sin(t * 0.9) + tl
    local dM = sw * 0.8 * math.sin(t * 1.3 + 1.0)
    local dR = sw * math.sin(t * 0.8 + 2.3) - tl
    local a, b = s.surf[1], s.surf[2]
    if warp8 then
        local ok = pcall(a.SetTexCoord, a, 0, dL, 0, 1 + dL, 1, dM, 1, 1 + dM)
        if ok and pcall(b.SetTexCoord, b, 0, dM, 0, 1 + dM, 1, dR, 1, 1 + dR) then return end
    end
    local d = (dL + dM + dR) / 3
    a:SetTexCoord(0, 1, d, 1 + d)
    b:SetTexCoord(0, 1, d, 1 + d)
end

--- Rahmen sichtbar und nicht (lesbar) fast durchsichtig (Ausblenden-Modul/Fader): sonst ruht die Arbeit des Treibers
local function frameActive(P)
    if Compat.QueryBool(P.frame, "IsVisible") == false then return false end
    local ok, a = call(P.frame, "GetEffectiveAlpha")
    a = ok and Compat.Num(a) or nil -- secret/unlesbar: weiterlaufen
    return not (a and a < 0.02)
end

local lastT
--- Treiber (jedes Bild, nur solange ein Gemaelde/eine versunkene Kopie sichtbar ist): Atmen, Kerzenlicht, Waabern, Kaustik
function Portrait.Step(t)
    local t0 = prof and prof() or nil
    local dt = lastT and math.max(0, math.min(0.25, t - lastT)) or 0
    lastT = t
    local busy = false
    for _, P in ipairs(paintList) do
        local s = P.s.painting
        if s and frameActive(P) then
            busy = true
            stepPainting(P, s, t, dt)
        end
    end
    local S, tilt = Portrait.SUB, nil
    for _, P in ipairs(subList) do
        local s = P.s.submerged
        if s and frameActive(P) then
            busy = true
            tilt = tilt or physicsTilt()
            s.boost = math.max(0, s.boost - dt * S.boostDecay)
            local i = P.cfg.intensity
            local stir = (1 + S.boostK * s.boost * s.boost) * (P.calm and S.calm or 1)
            local amp = math.min(S.waveCap, (S.wave + (S.waveMax - S.wave) * i) * stir)
            stats.amp = amp
            local shift = tilt * S.tilt * i * (P.mirror and -1 or 1) -- gespiegelt: gleiche Richtung auf dem Bildschirm
            surfWave(s, t, tilt, i, P.calm and S.calm or 1)
            warp(P, s.copies[1], t, math.min(S.mainCap, S.mainWave * (0.5 + 0.5 * i) * stir), S.main, 0)
            for k, g in ipairs(S.ghost) do warp(P, s.copies[k + 1], t, amp, g, shift * (k == 1 and 1 or -0.7)) end
            for k, tex in ipairs(s.caustics) do
                local c = S.causticMove[k]
                local u, v = (t * c[1]) % 1, (t * c[2]) % 1
                tex:SetTexCoord(u, u + S.causticTile, v, v + S.causticTile * 0.7)
            end
        end
    end
    if not busy then lastT = nil end
    if t0 then
        local ms = prof() - t0
        stats.steps = stats.steps + 1
        stats.ms = stats.ms + (ms - stats.ms) / math.min(stats.steps, 120)
        if ms > stats.msMax then stats.msMax = ms end
    end
    return busy
end

function Submerged.Activate(P, cfg)
    local s = P.s.submerged
    if not s then
        s = buildSubmerged(P)
        P.s.submerged = s
    end
    P.cfg = cfg
    P.calm = not P.preview and P.unit == "player" and readFlag(IsResting) == true or false
    s.bar:Show()
    s.clip:Show()
    Submerged.Layout(P)
    Submerged.Configure(P, cfg)
    Submerged.Refresh(P)
    addTo(subList, P)
    Portrait.Wake()
end

function Submerged.Deactivate(P)
    local s = P.s.submerged
    dropFrom(subList, P)
    if not s then return end
    for _, bb in ipairs(s.bubbles) do call(bb.g, "Stop") end
    for _, fx in ipairs(s.surfFx) do call(fx.g, "Stop") end
    s.clip:Hide()
    s.bar:Hide()
    setDesaturated(P.base, false)
    unmirror(P.base)
    P.testLow = nil
    s.lastI = nil -- naechstes Configure startet die Blasen neu
end

function Submerged.Layout(P)
    local s = P.s.submerged
    if s then layoutSubmerged(P, s) end
end

--- Rahmen wurde sichtbar (OnShow): Engine-Animationen starten nicht, solange der Rahmen verborgen ist - erneut abspielen
function Submerged.Resume(P)
    local s = P.s.submerged
    if s then playBubbles(P, s) end
end

function Submerged.Configure(P, cfg)
    local s = P.s.submerged
    if not s then return end
    P.cfg = cfg
    fullCoords(P, P.base)
    tintSubmerged(P, s)
    if s.lastI ~= cfg.intensity then
        s.lastI = cfg.intensity
        playBubbles(P, s)
    end
end

function Submerged.Refresh(P)
    local s = P.s.submerged
    if not s then return end
    setPortrait(P.base, P.unit)
    fullCoords(P, P.base) -- SetPortraitTexture kann die TexCoords zuruecksetzen
    for _, t in ipairs(s.copies) do setPortrait(t, P.unit) end
    tintSubmerged(P, s)
    Submerged.UpdateDead(P)
    levelSubmerged(P, s, false)
end

function Submerged.UpdateDead(P)
    local s = P.s.submerged
    if not s then return end
    local dead = isDead(P)
    setDesaturated(P.base, dead)
    for _, t in ipairs(s.copies) do setDesaturated(t, dead) end
end

function Submerged.OnHealth(P)
    local s = P.s.submerged
    if not s then return end
    levelSubmerged(P, s, true)
    Submerged.UpdateDead(P)
end

function Submerged.Tint(P)
    local s = P.s.submerged
    if s then tintSubmerged(P, s) end
end

function Submerged.TestLow(P, on)
    P.testLow = on and true or nil
    Submerged.OnHealth(P)
end

function Submerged.React(P, what, arg)
    local s = P.s.submerged
    if not s then return end
    if what == "hit" then
        s.boost = Portrait.SUB.boost * (arg and 1.4 or 1)
        Portrait.Wake()
    elseif what == "heal" then
        for _, fx in ipairs(s.surfFx) do playGroup(fx.g) end
    elseif what == "rest" then
        P.calm = arg and true or false
    elseif what == "dead" then
        setDesaturated(P.base, arg)
        for _, t in ipairs(s.copies) do setDesaturated(t, arg) end
    end
end

-- Gemeinsame Hilfen fuer Stile in eigenen Dateien (E6 PortraitModel.lua): dieselben secret-sicheren Bausteine wie oben
Portrait.Util = { texCoord = texCoord, fullCoords = fullCoords, fullCoordsAll = fullCoordsAll, unmirror = unmirror, call = call, readFlag = readFlag, recordError = recordError, newMask = newMask, addMask = addMask, layer = layer,
    curvesFor = curvesFor, curveAlpha = curveAlpha, readableFraction = readableFraction, evalPoints = evalPoints,
    flashGroup = flashGroup, flash = flash, liquidColor = liquidColor, setDesaturated = setDesaturated, stats = stats }

-- Registry ------------------------------------------------------------------------------------------------------------------
local STYLES = {}

--- Stil anmelden (key z. B. "model", impl siehe Kopf); ersetzt einen gleichnamigen Stil und wendet die Rahmen neu an
function Portrait.RegisterStyle(key, impl)
    assert(type(key) == "string" and type(impl) == "table", "LucidVials: Portrait-Stil ungueltig")
    STYLES[key] = impl
    if Portrait.Reapply then Portrait.Reapply() end
end

function Portrait.GetStyle(key) return STYLES[key] end

--- Schluessel der angemeldeten Stile in Anzeigereihenfolge (fuer die Auswahl im Reiter)
function Portrait.StyleKeys()
    local out = {}
    for _, k in ipairs(Portrait.STYLE_ORDER) do if STYLES[k] then out[#out + 1] = k end end
    return out
end

-- "flat" (intern, nicht waehlbar): statisches Bild, aber gespiegelt (static + mirror); P.base im runden Portrait-Frame
local Flat = { flat = true, noGloss = true }
function Flat.Activate(P, cfg)
    P.cfg = cfg
    call(P.base, "Show")
    Flat.Refresh(P)
end
function Flat.Configure(P, cfg)
    P.cfg = cfg
    fullCoords(P, P.base)
end
function Flat.Refresh(P)
    setPortrait(P.base, P.unit)
    fullCoords(P, P.base) -- SetPortraitTexture kann die TexCoords zuruecksetzen
end
function Flat.Deactivate(P) unmirror(P.base) end

Portrait.RegisterStyle("static", { static = true })
Portrait.RegisterStyle("flat", Flat)
Portrait.RegisterStyle("painting", Painting)
Portrait.RegisterStyle("submerged", Submerged)

-- Bereich "portrait" ------------------------------------------------------------------------------------------------------
local KNOWN = { static = true, painting = true, submerged = true, model = true, modelplain = true } -- Modell-Stile bleiben gespeichert, auch ohne E6

function Portrait.Defaults()
    local D = Portrait.DEFAULT
    return { style = D.style, intensity = D.intensity, mirrorPlayer = D.mirrorPlayer, mirrorTarget = D.mirrorTarget }
end

--- Bereich pruefen: feldweise, ein ungueltiges Feld faellt auf seinen Standard (nie der ganze Bereich)
function Portrait.Validate(t)
    if type(t) ~= "table" then return nil, "type" end
    local out = Portrait.Defaults()
    if type(t.style) == "string" and KNOWN[t.style] then out.style = t.style end
    local x = t.intensity
    if type(x) == "number" and x == x and x >= 0 and x <= 1 then out.intensity = x end
    for _, f in pairs(Portrait.MIRROR_FIELD) do
        if type(t[f]) == "boolean" then out[f] = t[f] end
    end
    return out
end

--- altes gemeinsames Feld mirror (erste 1.1.4-Fassung, "fuer alle" oder Eigenwert je Rahmen) in mirrorPlayer/mirrorTarget
--- uebernehmen, solange das neue Feld nicht selbst gesetzt ist; der Eigenwert des Rahmens geht vor
function Portrait.Migrate(out, raw)
    local all = type(raw.portrait) == "table" and raw.portrait or nil
    local function legacy(block)
        if type(block) == "table" and type(block.mirror) == "boolean" then return block.mirror end
        return nil
    end
    for id, f in pairs(Portrait.MIRROR_FIELD) do
        if not (all and type(all[f]) == "boolean") then
            local per = type(raw.per) == "table" and type(raw.per[id]) == "table" and raw.per[id].portrait or nil
            local v = legacy(per)
            if v == nil then v = legacy(all) end
            if v ~= nil then out.portrait[f] = v end
        end
    end
end

Skin.RegisterArea("portrait", { defaults = Portrait.Defaults, validate = Portrait.Validate, migrate = Portrait.Migrate,
    global = { "mirrorPlayer", "mirrorTarget" } })

local function frameConfig(id)
    local ok, c = pcall(Skin.GetFrameConfig, id)
    local p = ok and type(c) == "table" and c.portrait or nil
    local out = Portrait.Validate(p) or Portrait.Defaults()
    local f = Portrait.MIRROR_FIELD[id]
    out.mirror = f ~= nil and out[f] == true -- Blickrichtung dieses Rahmens
    return out
end

--- wirksamer Stil eines Rahmens: ToT immer statisch; unbekannt => statisch; "model" ohne Anmeldung/bei Ausfall => painting
local function resolveStyle(P, id, cfg)
    if not Portrait.UNIT[id] then return "static" end
    local key = cfg.style
    if key == "static" then return "static" end
    local impl = STYLES[key]
    if not impl then
        if key == "model" then return "painting" end
        return "static"
    end
    -- Mini-Vorschau: Modell-Stile nur, wenn sie die Vorschau ausdruecklich koennen (eigene Ereignisse/Rueckfall sonst am echten Rahmen)
    if P and P.preview and (key == "model" or key == "modelplain") and impl.previewSafe ~= true then
        return key == "model" and "painting" or "static"
    end
    if key == "model" and P and P.fallback then return "painting" end
    if type(impl.Usable) == "function" then
        local ok, usable = pcall(impl.Usable, P)
        if ok and usable == false then return "painting" end
    end
    return key
end

--- dazu die Blickrichtung: statisch und gespiegelt => "flat" (nur Spieler und Ziel)
local function resolveKey(P, id, cfg)
    local key = resolveStyle(P, id, cfg)
    if key == "static" and cfg.mirror == true and Portrait.UNIT[id] and STYLES.flat then return "flat" end
    return key
end

-- Ereignisse (je Einheit ein Frame mit Einheitenfilter, nur solange der Stil nicht statisch ist) ---------------------------------
local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_COMBAT", "UNIT_FACTION" }
local UNIT_EVENT_SET = {}
for _, ev in ipairs(UNIT_EVENTS) do UNIT_EVENT_SET[ev] = true end
local PLAYER_EVENTS = { "PLAYER_UPDATE_RESTING", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
local evFrames, listening = {}, {}

local function activeState(id)
    local sk = Skin.Get(id)
    local P = sk and sk.applied and sk.pfx or nil
    if P and P.impl and not P.impl.static then return P end
    return nil
end

local function callImpl(P, name, ...)
    local fn = P.impl and P.impl[name]
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, P, ...)
    if not ok then
        stats.errors = stats.errors + 1
        recordError(err)
    end
end

--- Reaktion an einen Rahmen (auch fuer E6): "hit"|"heal" (arg = kritisch), "rest" (arg = ruht), "dead" (arg = tot)
function Portrait.React(id, what, arg)
    local P = activeState(id)
    if P then callImpl(P, "React", what, arg) end
end

local function refreshAll(P)
    callImpl(P, "Refresh")
end

local function onEvent(id, event, unit, action, flag)
    local P = activeState(id)
    if not P then return end
    if UNIT_EVENT_SET[event] and (type(unit) ~= "string" or Compat.IsSecret(unit) or unit ~= P.unit) then return end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        callImpl(P, "OnHealth")
    elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
        refreshAll(P)
    elseif event == "UNIT_FACTION" then
        -- Skin.lua faerbt die Roehre im selben Ereignis um (Reihenfolge offen): erst im naechsten Bild die Farbe lesen
        C_Timer.After(0, function()
            local P2 = activeState(id)
            if P2 then callImpl(P2, "Tint") end
        end)
    elseif event == "UNIT_COMBAT" then
        -- nur das Ereignis (action "WOUND"/"HEAL"/...) und der Text sind lesbar; die Menge wird nie gelesen
        if type(action) ~= "string" or Compat.IsSecret(action) then return end
        stats.combat[id] = (stats.combat[id] or 0) + 1
        stats.lastAction[id] = action
        local crit = type(flag) == "string" and not Compat.IsSecret(flag) and (flag == "CRITICAL" or flag == "CRUSHING")
        if action == "HEAL" then
            callImpl(P, "React", "heal", crit)
        else
            local PH = ns.LiquidPhysics
            local hits = PH and PH.HIT_EVENTS or { WOUND = true }
            if hits[action] then callImpl(P, "React", "hit", crit) end
        end
    elseif event == "PLAYER_UPDATE_RESTING" then
        callImpl(P, "React", "rest", readFlag(IsResting) == true)
    elseif event == "PLAYER_DEAD" then
        callImpl(P, "React", "dead", true)
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        callImpl(P, "React", "dead", readFlag(UnitIsDeadOrGhost, "player") == true)
        callImpl(P, "OnHealth")
    end
end

local function evFrame(id)
    if evFrames[id] then return evFrames[id] end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event, ...)
        local ok, err = pcall(onEvent, id, event, ...)
        if not ok then
            stats.errors = stats.errors + 1
            recordError(err)
        end
    end)
    evFrames[id] = f
    return f
end

local function listen(id, on)
    on = on and true or false
    if (listening[id] or false) == on then return end
    listening[id] = on
    local f, unit = evFrame(id), Portrait.UNIT[id]
    for _, ev in ipairs(UNIT_EVENTS) do
        if on then
            if not pcall(f.RegisterUnitEvent, f, ev, unit) then pcall(f.RegisterEvent, f, ev) end
        else
            pcall(f.UnregisterEvent, f, ev)
        end
    end
    if id == "player" then
        for _, ev in ipairs(PLAYER_EVENTS) do
            if on then pcall(f.RegisterEvent, f, ev) else pcall(f.UnregisterEvent, f, ev) end
        end
    end
end
function Portrait.IsListening(id) return listening[id] == true end

-- Anbindung an Skin.lua ----------------------------------------------------------------------------------------------------
local function newState(sk, id)
    local preview = sk.preview == true -- Mini-Vorschau: Bild des Spielers, keine Ereignisse
    local P = { sk = sk, id = id, unit = preview and "player" or Portrait.UNIT[id], preview = preview, s = {} }
    local f = CreateFrame("Frame", nil, sk.holder)
    f:Hide()
    f:SetScript("OnShow", function()
        Portrait.Wake()
        if P.impl and type(P.impl.Resume) == "function" then callImpl(P, "Resume") end
    end)
    P.frame = f
    P.base = f:CreateTexture(nil, "ARTWORK")
    P.mask = newMask(f)
    if P.mask then P.mask:SetAllPoints(f) end
    addMask(P.base, P.mask)
    P.base:SetAllPoints(f)
    sk.pfx = P
    return P
end

--- Glasglanz ueber dem Portrait (Ebene des Portrait-Frames + 2, unter dem Ring), fuer painting/submerged; Staerke folgt dem Regler
local function updateGloss(P)
    local G = P.gloss
    if not G then return end
    local show = P.impl ~= nil and P.impl.noGloss ~= true
    G.frame:SetShown(show)
    G.tex:SetAlpha(Portrait.PAINT.gloss * (P.cfg and P.cfg.intensity or 0))
end

local function ensureGloss(P)
    if P.gloss then return end
    local f = CreateFrame("Frame", nil, P.frame)
    f:SetAllPoints(P.frame)
    local mask = newMask(f)
    if mask then mask:SetAllPoints(f) end
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetTexture(Portrait.TEX.gloss)
    t:SetAllPoints(f)
    call(t, "SetBlendMode", "ADD")
    addMask(t, mask)
    P.gloss = { frame = f, tex = t }
end

local function layoutState(P)
    local sk = P.sk
    local size = math.max(8, math.floor((sk.pw or 40) + 0.5))
    P.size = size
    P.frame:ClearAllPoints()
    P.frame:SetPoint("CENTER", sk.ring or sk.anchor or sk.root, "CENTER", 0, 0)
    P.frame:SetSize(size, size)
    local ok, ringL = call(sk.ringFrame, "GetFrameLevel")
    ringL = ok and Compat.Num(ringL) or 2
    -- unter Ring und Zier (Glanz, Schwappen, Plaketten bleiben davor) UND unter den Roehren (Ebene base .. base + 3): Roehren-Enden
    -- am Ring duerfen nie verdeckt werden; +1 Clip, +2 Glanz
    local lowest = ringL
    for _, lb in ipairs({ sk.health, sk.power }) do
        local okL, lvl = call(lb and lb.root, "GetFrameLevel")
        lvl = okL and Compat.Num(lvl) or nil
        if lvl and lvl < lowest then lowest = lvl end
    end
    P.frame:SetFrameLevel(math.max(0, lowest - 3))
    if P.gloss then P.gloss.frame:SetFrameLevel(P.frame:GetFrameLevel() + 2) end
    if P.impl and type(P.impl.Layout) == "function" then callImpl(P, "Layout") end
end

--- Blizzards Portrait nur bei nicht-statischem Stil verbergen (Alpha 0), sonst zurueck auf 1
local function blizzardPortrait(P, hide)
    local sk = P.sk
    if hide then
        if sk.portrait and not P.hidden then
            Skin.HideRegion(sk, sk.portrait)
            P.hidden = true
        end
    elseif P.hidden then
        Skin.ShowRegion(sk, sk.portrait)
        P.hidden = false
    end
end

local function deactivate(P)
    if P.impl then callImpl(P, "Deactivate") end
    P.impl, P.key = nil, nil
    updateGloss(P)
    P.frame:Hide()
    blizzardPortrait(P, false)
    if not P.preview then listen(P.id, false) end
end

--- Stil des Rahmens aus dem Profil anwenden (idempotent; aus Skin.apply nach dem Layout und bei Konfig-Aenderungen)
function Portrait.Attach(sk, id)
    id = id or sk.id
    local P = sk.pfx
    local cfg = frameConfig(id)
    if (cfg.style == "static" and cfg.mirror ~= true) or not Portrait.UNIT[id] then -- Standard: nichts anlegen, nichts anfassen
        if P and P.impl then deactivate(P) end
        return
    end
    if not P then P = newState(sk, id) end
    local key = resolveKey(P, id, cfg)
    if key == "static" then
        if P.impl then deactivate(P) end
        return
    end
    P.cfg = cfg
    P.mirror = cfg.mirror == true
    layoutState(P)
    if P.key ~= key then
        if P.impl then callImpl(P, "Deactivate") end
        P.key, P.impl = key, STYLES[key]
        blizzardPortrait(P, true)
        P.frame:Show()
        if not P.preview then listen(id, true) end
        ensureGloss(P)
        layoutState(P) -- Ebene des Glanzes
        callImpl(P, "Activate", cfg)
    else
        P.frame:Show()
        callImpl(P, "Configure", cfg)
    end
    updateGloss(P)
end

--- Rahmen zurueckstellen (Skin.remove): alles verbergen, Blizzards Portrait zurueck
function Portrait.Detach(sk)
    local P = sk and sk.pfx
    if P and P.impl then deactivate(P) elseif P then blizzardPortrait(P, false) end
end

--- Einheit neu (Zielwechsel, aus Skin.refreshUnit): Portrait-Texturen, Farbe und Pegel neu
function Portrait.Refresh(sk)
    local P = sk and sk.pfx
    if not (P and P.impl and not P.impl.static) then return end
    P.fallback = nil
    local key = resolveKey(P, sk.id, P.cfg or frameConfig(sk.id))
    if key ~= P.key then Portrait.Attach(sk, sk.id) return end
    refreshAll(P)
end

--- alle (bzw. einen) Rahmen neu anwenden, z. B. nach Konfig-Aenderung oder neu angemeldetem Stil
function Portrait.Reapply(frameId)
    for _, id in ipairs(Skin.FRAMES) do
        local sk = Skin.Get(id)
        if sk and sk.applied and (frameId == nil or frameId == id) then
            local ok, err = pcall(Portrait.Attach, sk, id)
            if not ok then recordError(err) end
        end
    end
end

--- Stil eines Rahmens ausgefallen (z. B. Modell: SetUnit scheitert): Rueckfall auf painting (E6)
function Portrait.Fallback(id, on)
    local sk = Skin.Get(id)
    local P = sk and sk.pfx
    if not P then return end
    P.fallback = on ~= false or nil
    Portrait.Reapply(id)
end

--- wirksamer Stil (Schluessel) eines Rahmens; "static", wenn nichts laeuft
function Portrait.ActiveKey(id)
    local sk = Skin.Get(id)
    local P = sk and sk.pfx
    return P and P.key or "static"
end

Skin.OnConfigChanged(function(frameId, area)
    if area ~= nil and area ~= "portrait" then return end
    Portrait.Reapply(frameId)
end)

-- Testwort /vials test portrait ---------------------------------------------------------------------------------------------
-- cast/combat: nur das Modell reagiert darauf (die 2D-Stile uebergehen unbekannte Reaktionen); "reset" am Ende stellt den echten Zustand her
Portrait.TEST = { hit = 0.2, cast = 1.3, heal = 2.4, low = 4.6, combat = 4.6, lowEnd = 7.4, rest = 7.8, restEnd = 10.6, done = 11 }
local testEpoch = 0

local function testStates()
    local list = {}
    for _, id in ipairs({ "player", "target" }) do
        local P = activeState(id)
        if P and not P.impl.flat then list[#list + 1] = P end -- gespiegeltes statisches Bild: nichts zu testen
    end
    return list
end

local function each(fn)
    for _, P in ipairs(testStates()) do
        local ok, err = pcall(fn, P)
        if not ok then recordError(err) end
    end
end

function Portrait.StopTest()
    testEpoch = testEpoch + 1
    each(function(P)
        if P.testLow then callImpl(P, "TestLow", false) end
        if P.id == "player" then callImpl(P, "React", "rest", readFlag(IsResting) == true) end
        callImpl(P, "React", "reset")
    end)
end

--- Reaktionen der aktiven Portraits durchspielen: Treffer, Heilung, wenig Leben, Ruhe. Liefert die Zahl der beteiligten Rahmen.
function Portrait.RunTest()
    local n = #testStates()
    if n == 0 then return 0 end
    testEpoch = testEpoch + 1
    local epoch, T = testEpoch, Portrait.TEST
    local function at(secs, fn)
        C_Timer.After(secs, function()
            if epoch == testEpoch then each(fn) end
        end)
    end
    at(T.hit, function(P) callImpl(P, "React", "hit", false) end)
    at(T.cast, function(P) callImpl(P, "React", "cast", false) end)
    at(T.heal, function(P) callImpl(P, "React", "heal", false) end)
    at(T.low, function(P) callImpl(P, "TestLow", true) end)
    at(T.combat, function(P) callImpl(P, "React", "combat", true) end)
    at(T.lowEnd, function(P)
        callImpl(P, "TestLow", false)
        callImpl(P, "React", "combat", false)
    end)
    at(T.rest, function(P) if P.id == "player" then callImpl(P, "React", "rest", true) end end)
    at(T.restEnd, function(P) if P.id == "player" then callImpl(P, "React", "rest", false) end end)
    C_Timer.After(T.done, function() if epoch == testEpoch then Portrait.StopTest() end end)
    return n
end

function Portrait.TestCommand()
    if not Skin.IsEngaged() then
        ns.Print(L.FRAMES_TEST_NEED_ON)
        return
    end
    local n = Portrait.RunTest()
    if n == 0 then ns.Print(L.PORTRAIT_TEST_STATIC) else ns.Print(L.PORTRAIT_TEST_RUN, n) end
end

Skin.RegisterTest("portrait", function() Portrait.TestCommand() end)

-- Debug (/vials debug) --------------------------------------------------------------------------------------------------------
function Portrait.Debug()
    local function yn(b) return b and L.NP_YES or L.NP_NO end
    for _, id in ipairs({ "player", "target" }) do
        local sk = Skin.Get(id)
        local P = sk and sk.pfx
        ns.Print("frames.portrait.%s style=%s hidden=%s listening=%s combat=%d last=%s curve=%s", id,
            tostring(P and P.key or "static"), yn(P and P.hidden), yn(listening[id]), stats.combat[id] or 0,
            tostring(stats.lastAction[id] or "-"), tostring(stats.curve[id] or "-"))
        -- Animationen: laufen sie wirklich? (Treiber, Sichtbarkeit, Atmen/Kerzenlicht, Engine-Gruppen)
        local sp, ss = P and P.s.painting, P and P.s.submerged
        local vis = P and Compat.QueryBool(P.frame, "IsVisible")
        local function pl(g) local ok, v = call(g, "IsPlaying"); return ok and v == true and L.NP_YES or L.NP_NO end
        ns.Print("frames.portrait.%s.anim driver=%s visible=%s zoom=%.3f candle=%.2f hit=%s heal=%s bubbles=%s", id,
            yn(Style and Style.DriverActive and Style.DriverActive()), yn(vis), sp and sp.zoom or 0, sp and sp.candleAlpha or 0,
            sp and pl(sp.hitFx.g) or "-", sp and pl(sp.healFx.g) or "-", ss and ss.bubbles[1] and pl(ss.bubbles[1].g) or "-")
    end
    ns.Print("frames.portrait.cost setPortrait=%d copies=%d steps=%d avgMs=%.3f maxMs=%.3f errors=%d wave=%.3f warp8=%s", stats.setCalls,
        1 + #Portrait.SUB.ghost, stats.steps, stats.ms, stats.msMax, stats.errors, stats.amp or 0, yn(warp8))
    for _, key in ipairs(Portrait.STYLE_ORDER) do -- Stile aus eigenen Dateien haengen ihre Zeilen an (E6: Modell)
        local impl = STYLES[key]
        if impl and type(impl.Debug) == "function" then
            local ok, err = pcall(impl.Debug)
            if not ok then recordError(err) end
        end
    end
end

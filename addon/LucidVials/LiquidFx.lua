-- Fluessigkeits-Effekte (Delta "Fluessiges Leben", Wuensche 16.11.): Schaden, Heilung ("Licht des Blitzes"), Ressourcen-
-- Regeneration und Schwaechungs-Schlieren in den Roehren von Liquid.lua. Texturen aus dem freigegebenen Gemini-Bogen
-- sheet-effekte-v1.jpg (scripts/gen-unitframe-media.mjs FX: uf-fx-*).
--
-- Anstiegsband (gewonnener Abschnitt ohne jeden Vergleich, Leben ist oft secret, die Fuellbreite in Forever ebenso):
--   fx.old    unsichtbare eigene StatusBar; bekommt jeden Wert RISE.delay s SPAETER (wie die Schadensspur lb.trail, nur dass
--             hier der Abschnitt zwischen altem und neuem Ende zaehlt, wenn das neue weiter rechts liegt).
--   fx.clip   Clip-Frame ueber der Fluessigkeit (Rohrbeginn bis Fuellungsende = lb.barTex rechts): rechts davon nichts.
--   Maske     uf-mask-fadein mit CLAMP ab dem Ende von fx.old: links davon durchsichtig, dann weich voll.
--   => Sichtbar ist genau der gewonnene Abschnitt [alt, neu]; bei Verlust (alt > neu) ist er leer. Lua liest dafuer keinen
--      Wert: die Engine legt die Kanten (SetValue/SetMinMaxValues nehmen Secrets, die Werte werden nur durchgereicht).
-- Effekte (alle additiv ausser den Schlieren, weiche Kanten, nicht aufs Pixelraster gerastet):
--   Heilung   jeder Anstieg: goldenes Nachgluehen im gewonnenen Abschnitt, das in die Fluessigkeitsfarbe uebergeht; dazu bei
--             UNIT_COMBAT "HEAL" (Spieler): Lichtstreifen laeuft einmal von links nach rechts durch den Abschnitt, Funkeln
--             steigt auf, Heilstern am Fuellungsende (Kolben). CRITICAL staerker. Schnelle Folgen (HoT) werden gebuendelt.
--   Schaden   UNIT_COMBAT "WOUND" (Spieler, dieselbe Einteilung wie LiquidPhysics.HIT_EVENTS) mit Wucht (Spieltest
--             16.11.): greller Aufblitz am Bruchpunkt (weisser Kern + roter Halo), Funken fliegen ballistisch heraus (Pool),
--             roter Trefferblitz durch die Fluessigkeit, Spritzkrone, die verlorene Fluessigkeit brennt im Glut-Abschnitt sichtbar
--             ab (Glutkoerper mit Hitzeflimmern auf lb.glow, sackt mit der Schadensspur von rechts nach links zusammen und
--             glimmt nach), kurzer roter Puls auf Glas und Rahmen, Zittern (Liquid.Nudge). Die Verlustmenge ist secret: Staerke
--             nur nach WOUND/CRITICAL. Treffer innerhalb HIT.cooldown buendeln (kein Dauerflackern).
--   Ressource Sprudeln der ganzen Ressourcen-Fluessigkeit beim Regenerieren: LiquidFizz.lua.
--   Debuffs   Spieler: je Bannart eine Schlieren-Ebene (Gift dunkelgruen, Fluch lila, Krankheit gelb, Magie blau), bis
--             INK.max gleichzeitig, treiben langsam (UV-Drift, Gegenbewegung je Ebene), blenden weich. Erkennung bei UNIT_AURA
--             (nur Wecker, gebuendelt): dispelName lesbar => Art direkt; secret => je Aura-Instanz die Farbe der Bannart ueber
--             C_UnitAuras.GetAuraDispelTypeColor mit einer Stufen-Farbkurve (Ergebnis secret, geht nur an SetVertexColor).
-- Werte von Leben/Ressource/Auren werden nie verglichen, gerechnet oder ausgegeben; Tabellen entstehen nur bei UNIT_AURA bzw.
-- beim Anlegen. Im Ruhezustand (keine Animation, keine Schlieren) kehrt Fx.Step sofort zurueck.
local ADDON_NAME, ns = ...
local Compat = ns.Compat

local Fx = {}
ns.LiquidFx = Fx

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
Fx.TEX = { sweep = MEDIA .. "uf-fx-sweep", burst = MEDIA .. "uf-fx-burst", sparkles = MEDIA .. "uf-fx-sparkles",
    splash = MEDIA .. "uf-fx-splash", flash = MEDIA .. "uf-fx-flash", ink = MEDIA .. "uf-fx-ink", mana = MEDIA .. "uf-fx-mana",
    ramp = MEDIA .. "uf-mask-fadein",
    -- Status (Spieltest 16.11., Effektbogen v2): Farbschicht ueber dem Koerper (uf-body),
    -- Zusatz je Bannart (aufsteigende Blaeschen bei Gift/Krankheit, Funkeln bei Magie) - austauschbar
    tint = MEDIA .. "uf-body", dark = "Interface\\Buttons\\WHITE8X8", pBubble = MEDIA .. "uf-fx2-bubbles",
    pPop = MEDIA .. "uf-fx2-pop", rise = MEDIA .. "uf-bubbles", twinkle = MEDIA .. "uf-fx-sparkles" }
-- delay: alter Stand (Heilung) so lange halten; ramp: weicher Einlauf am alten Ende (x Hoehe)
Fx.RISE = { delay = 0.9, ramp = 0.5 }
-- Heilung: Nachgluehen (glow: Grundwert bei jedem Anstieg, healGlow: bei HEAL), Lichtstreifen (Breite x Hoehe, Laufzeit,
-- Weg x Roehrenbreite), Funkeln (Breite x Hoehe, Steigen x Hoehe), Heilstern (Groesse x Hoehe), Dauer, crit-Faktor, Buendeln
Fx.HEAL = { dur = 0.85, glow = 0.22, healGlow = 0.5, gold = { 1.0, 0.80, 0.38 }, sweepW = 2.6, sweepT = 0.6, sweepRun = 1.0,
    sweepA = 0.95, sparkW = 3.2, sparkRise = 0.45, sparkA = 0.85, starSize = 2.0, starT = 0.7, starA = 0.95, crit = 1.4,
    cooldown = 0.3 }
-- Schaden: dur = Gesamtdauer (s); Blitz (Breite x Hoehe, Alpha, Farbe, flashT); Spritzkrone; Aufblitz am Bruchpunkt (core
-- weiss / halo rot: Groesse x Hoehe, Dauer, Alpha); Funken (Anzahl normal/crit, Groesse x Hoehe, Tempo x Hoehe/s, Schwerkraft
-- x Hoehe/s^2, Lebensdauer, Farbe); Puls auf Glas/Rahmen (pulseA, pulseT, frame = Rot-Anteil am Bronze-Rahmen); Glut-Abbrand
-- (burn*: Breite x Hoehe, Alpha, Dauer, Nachgluehen tau, Flimmern, Farbe); Zittern (px, Frequenz, Abklingen); crit-Faktor
Fx.HIT = { dur = 1.6, flashW = 4.5, flashA = 0.7, flashT = 0.4, color = { 1.0, 0.16, 0.08 }, splashW = 1.5, splashH = 0.85,
    splashA = 0.75, splashT = 0.45, coreSize = 1.6, coreT = 0.22, coreA = 1.0, haloSize = 3.4, haloT = 0.42, haloA = 0.85,
    haloColor = { 1.0, 0.12, 0.04 }, sparks = 5, sparksCrit = 9, sparkSize = 0.45, sparkV = 9, sparkG = 22, sparkT = 0.7,
    sparkColor = { 1.0, 0.55, 0.15 }, pulseA = 0.28, pulseT = 0.35, frame = 0.55, burnW = 6, burnA = 0.95, burnT = 1.6,
    burnTau = 0.55, burnFlicker = 0.9, burnColor = { 1.0, 0.42, 0.10 }, shakePx = 2.0, shakeHz = 26, shakeTau = 0.12,
    crit = 1.7, cooldown = 0.18 }
-- Schlieren: Ebenen, Alpha, Ein-/Ausblenden (1/s), Kachelbreite (x Hoehe), Drift je Ebene (Texturbreiten/s, Vorzeichen =
-- Richtung), Pendeln, Farben je Bannart. ids: Dispel-Typ-IDs fuer die Farbkurve (UNGEPRUEFT: weder Retail 12.1.5 noch Forever
-- 1.60.1 deklarieren ein Enum; zur Laufzeit wird Enum.DispelType/AuraDispelType bevorzugt, die Probe /vials probe fx
-- rechnet sie zurueck). debounce: UNIT_AURA buendeln (s).
-- Status (Spieltest 16.11., Runde 4): die GANZE Lebensfluessigkeit wird in die Farbe der vorherrschenden Bannart getoent
-- (Farbschicht uf-body ueber dem Koerper, unter Luft/Glas, Deckkraft tintA je Art, weich ueberblendet in 1/tintFade s) und der
-- Koerper abgedunkelt (dim je Art: Liquid lb.bodyDim) - Gift ist trueb-oliv und deutlich dunkler als das normale Gruen. Keine
-- Wolken/Schlieren mehr ("nicht realistisch"). Zusatz je vorherrschender Art (sparsam): Gift/Krankheit feine aufsteigende
-- Blaeschen, Fluch leichtes Flackern der Toenung, Magie Funkeln. max = gemerkte Bannarten (vorherrschend = erste).
-- testSecs = Dauer von /vials test <bannart>. secret: Farbe und Deckkraft aus der Kurve (Alpha 0 ohne Bannart).
Fx.INK = { max = 4, tintFade = 2.5, tintDrift = 0.006, tintSpan = 1,
    tintA = { Poison = 0.92, Disease = 0.8, Curse = 0.8, Magic = 0.8 }, secretA = 0.8,
    dim = { Poison = 0.35, Disease = 0.85, Curse = 0.72, Magic = 0.78 }, secretDim = 0.75,
    -- secret: schwarze Kurven-Lage statt bodyDim (Deckkraft je Art, 0 ohne Bannart)
    darkA = { Poison = 0.6, Disease = 0.1, Curse = 0.2, Magic = 0.15 },
    -- Oberflaechenlicht (Lichtband der Kolben-Kammer, sonst immer in Fluessigkeitsfarbe gruen) je Art umfaerben (lesbar):
    -- das helle gruene Band ueber der Toenung war der Grund, warum Gift kaum zu sehen war (Spieltest)
    glow = { Poison = { 0.16, 0.34, 0.08 }, Disease = { 0.95, 0.85, 0.3 }, Curse = { 0.7, 0.35, 0.95 },
        Magic = { 0.35, 0.6, 1.0 } }, glowMix = 0.85,
    -- Gift: "giftig-trueb mit Blasen" - leuchtende Blasen (Pool, Groesse px, Steigzeit s, Abstand s, Farbe) und kraenkliches
    -- Pulsieren (Hz, Tiefe) der Truebung und des Leuchtens
    poison = { bubbles = 7, sizeMin = 3, sizeMax = 6, riseMin = 2.0, riseMax = 3.5, every = 0.35, wobble = 0.8, wobbleHz = 0.7,
        color = { 0.45, 1.0, 0.25 }, popT = 0.3, pulseHz = 0.5, pulse = 0.12, glowPulse = 0.35 },
    extra = { Disease = "rise", Magic = "twinkle" }, extraA = 0.4, riseSpeed = 0.35, flicker = 0.18,
    testSecs = 10,
    order = { "Magic", "Curse", "Disease", "Poison" },
    colors = { Magic = { 0.20, 0.45, 1.0 }, Curse = { 0.55, 0.20, 0.85 }, Disease = { 0.90, 0.75, 0.15 },
        Poison = { 0.05, 0.15, 0.03 } },
    -- Bannart nicht bestimmbar (Forever im Kampf: secret, Kurve wirft): KEINE Toenung, keine Schlieren, keine Abdunklung
    -- (Delta "Kampf-Debuff" 26.11., der fruehere graue Schleier "Weak" stoerte); die echte Farbe kommt mit der ersten
    -- lesbaren Abtastung (UNIT_AURA bzw. PLAYER_REGEN_ENABLED nach dem Kampf).
    ids = { Magic = 1, Curse = 2, Disease = 3, Poison = 4 }, idsVerified = false, debounce = 0.15, scanMax = 40,
    learnMax = 15 }
-- Dispel-Typ-IDs (fuer die Farbkurve bei secret dispelName): Blizzard baut die Kurve nirgends mit festen x-Werten
-- (wow-ui-source live, Blizzard_CustomAuraButton.lua: customDispelColorCurve kommt nur als Option des Aufrufers; die Doku
-- sagt nur "dispel type ID used as the 'x' value"). Darum: Enum zur Laufzeit, sonst SELBSTKALIBRIERUNG (Fx.Learn): ist ein
-- Debuff mit lesbarem dispelName und lesbarer Kurvenfarbe da, ergibt die Identitaets-Kurve (x = k -> Rot k/16) die ID; sie
-- steht dann global in LucidVialsDB.dispelIds. Sonst die Annahme Fx.INK.ids (Werte der alten SpellDispelType-Tabelle, ungeprueft).

local tubes = setmetatable({}, { __mode = "k" }) -- angelegte Roehren
local IMMEDIATE
local WHITE = { 1, 1, 1 }
Fx.QUEUE_MAX = 32               -- verzoegerte Werte je Anker-Bar hoechstens (voll: der juengste ueberschreibt den letzten)
local debuffOn = false
local inkState = { n = 0, kinds = {}, colors = {}, secret = 0 } -- aktuelle Schlieren (nur bei UNIT_AURA neu)

local function now() return type(GetTime) == "function" and GetTime() or 0 end

local function free(t)
    if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, false) end
    if t.SetTexelSnappingBias then pcall(t.SetTexelSnappingBias, t, 0) end
    return t
end

local function newMask(frame, path, wrap)
    local ok, m = pcall(frame.CreateMaskTexture, frame)
    if not ok or not m then return nil end
    wrap = wrap or "CLAMPTOBLACKADDITIVE"
    if not pcall(m.SetTexture, m, path, wrap, wrap) then return nil end
    return m
end

local function addMask(t, m) if t and m then pcall(t.AddMaskTexture, t, m) end end

local function readEnum()
    local e = type(Enum) == "table" and Enum.StatusBarInterpolation or nil
    IMMEDIATE = type(e) == "table" and Compat.Num(e.Immediate) or nil
end

-- Wert an eine eigene Bar (secret erlaubt; nur durchgereicht)
local function setValue(bar, v, m)
    if m ~= nil and pcall(bar.SetValue, bar, v, m) then return end
    pcall(bar.SetValue, bar, v)
end

local function anchorBar(parent)
    local b = CreateFrame("StatusBar", nil, parent)
    local ok = pcall(b.SetStatusBarTexture, b, "Interface\\Buttons\\WHITE8X8")
    local okT, tex = pcall(b.GetStatusBarTexture, b)
    tex = (ok and okT and type(tex) == "table") and tex or nil
    if tex then tex:SetAlpha(0) end
    return b, tex
end

local function fxTex(frame, layer, sub, path, add)
    local t = free(frame:CreateTexture(nil, layer, nil, sub))
    if path then t:SetTexture(path) end
    if add and t.SetBlendMode then t:SetBlendMode("ADD") end
    t:Hide()
    return t
end

--- Effekte einer Roehre anlegen (aus Liquid.Create): Anker-Bars, Clip, Masken, Effekt-Texturen. Ohne Rolle bleibt alles aus.
function Fx.Attach(lb)
    local root = lb.root
    local fx = { role = nil, on = false, debuffs = false, epoch = 0, healT = nil, hitT = nil, glowT = nil,
        busy = false, hitAmp = 0, healAmp = 0, glowAmp = 0 }
    lb.fx = fx
    fx.old, fx.oldTex = anchorBar(root)
    fx.qOld = { v = {}, t = {}, head = 1, tail = 0, bar = fx.old, delay = Fx.RISE.delay }
    local clip = CreateFrame("Frame", nil, root)
    pcall(clip.SetClipsChildren, clip, true)
    fx.clip = clip
    fx.cap = newMask(clip, ns.Liquid.MASK_TEX)
    fx.gainMask = newMask(clip, Fx.TEX.ramp, "CLAMP")
    -- Farbschicht: im Fluessigkeits-Frame unter Luft/Abdeckung (folgt der Oberflaeche), Kapselmaske der Fluessigkeit
    fx.tint = free(lb.fillIn:CreateTexture(nil, "BORDER", nil, 1))
    fx.tint:SetTexture(Fx.TEX.tint, "REPEAT", "REPEAT")
    addMask(fx.tint, lb.fillMask)
    fx.tint:Hide()
    fx.tintA, fx.tR, fx.tG, fx.tB = 0, 1, 1, 1
    -- secret: je secret Aura eine Toen- und eine Abdunkel-Lage (Farbe/Deckkraft aus der Kurve, 0 ohne Bannart). So gewinnt eine
    -- Gift-Aura auch dann, wenn vor ihr eine Aura ohne Bannart liegt (im Kampf ist nicht erkennbar, welche es ist).
    fx.tintS, fx.darkS = {}, {}
    for i = 1, Fx.INK.max do
        local t = free(lb.fillIn:CreateTexture(nil, "BORDER", nil, 1))
        t:SetTexture(Fx.TEX.tint, "REPEAT", "REPEAT")
        addMask(t, lb.fillMask)
        t:Hide()
        local d = free(lb.fillIn:CreateTexture(nil, "BORDER", nil, 2))
        d:SetTexture(Fx.TEX.dark)
        addMask(d, lb.fillMask)
        d:Hide()
        fx.tintS[i], fx.darkS[i] = t, d
    end
    fx.dark = fx.darkS[1]
    -- Rahmen-Toenung im Kampf (LiquidBorder.lua): je Debuff eine Ebene aus Blizzards Rahmenbild, beide Wege in der
    -- Fluessigkeit wie tintS (fillIn BORDER unter Abdeckung/Luft, Kapselmaske fillMask): die Form folgt exakt der
    -- Fluessigkeit (Clip lb.fill am Fuellungsende, Meniskus/Welle durch die Abdeckung), nie ueber leeres Glas
    fx.borderL, fx.borderN = {}, 0
    local BD = ns.LiquidBorder
    if BD then
        for i = 1, Fx.INK.max do fx.borderL[i] = BD.NewLayer(lb.fillIn, lb.fillMask, "BORDER", 1) end
    end
    -- Gift-Blasen: eigener Frame (Puls/Ausblenden), Farbe je Blase (lesbar Leuchtgruen, secret aus der Gift-Kurve)
    local PO = Fx.INK.poison
    local pf = CreateFrame("Frame", nil, clip)
    pf:Hide()
    local pm = newMask(pf, ns.Liquid.MASK_TEX)
    fx.pFrame, fx.pMask, fx.pB, fx.pOn, fx.pX, fx.pY, fx.pV, fx.pS, fx.pPh, fx.pPop = pf, pm, {}, {}, {}, {}, {}, {}, {}, {}
    for i = 1, PO.bubbles do
        local t = fxTex(pf, "ARTWORK", 6, Fx.TEX.pBubble, true)
        t:SetTexCoord(0, 1 / 8, 0, 1)
        addMask(t, pm)
        fx.pB[i], fx.pOn[i], fx.pX[i], fx.pY[i], fx.pV[i], fx.pS[i], fx.pPh[i], fx.pPop[i] = t, false, 0, 0, 0, 4, 0, nil
    end
    fx.pA, fx.pNext = 0, 0
    fx.extra = fxTex(clip, "ARTWORK", 4, nil, true)
    addMask(fx.extra, fx.cap)
    fx.glow = fxTex(clip, "ARTWORK", 4, nil, true)
    fx.glow:SetColorTexture(1, 1, 1, 1)
    fx.sweep = fxTex(clip, "ARTWORK", 5, Fx.TEX.sweep, true)
    fx.spark = fxTex(clip, "ARTWORK", 6, Fx.TEX.sparkles, true)
    for _, t in ipairs({ fx.glow, fx.sweep, fx.spark }) do
        addMask(t, fx.cap)
        addMask(t, fx.gainMask)
    end
    fx.flash = fxTex(clip, "ARTWORK", 7, Fx.TEX.flash, true)
    addMask(fx.flash, fx.cap)
    local hc = Fx.HIT.color
    fx.flash:SetVertexColor(hc[1], hc[2], hc[3])
    fx.star = fxTex(lb.top, "ARTWORK", 7, Fx.TEX.burst, true)
    addMask(fx.star, lb.topMask) -- alles bleibt im Glas (nur die Mana-Funken spruehen hinaus, LiquidFizz)
    fx.splash = fxTex(lb.top, "ARTWORK", 6, Fx.TEX.splash, true)
    addMask(fx.splash, lb.topMask)
    -- Treffer mit Wucht: Aufblitz (Kern weiss, Halo rot) und Funken ueber allem, Puls im Glas, Glut-Abbrand im Glut-Abschnitt
    local K = Fx.HIT
    fx.halo = fxTex(lb.top, "ARTWORK", 6, Fx.TEX.burst, true)
    addMask(fx.halo, lb.topMask)
    fx.halo:SetVertexColor(K.haloColor[1], K.haloColor[2], K.haloColor[3])
    fx.core = fxTex(lb.top, "ARTWORK", 7, Fx.TEX.burst, true)
    addMask(fx.core, lb.topMask)
    fx.sparks, fx.spX, fx.spY, fx.spVX, fx.spVY = {}, {}, {}, {}, {}
    for i = 1, K.sparksCrit do
        local sp = fxTex(lb.top, "ARTWORK", 7, Fx.TEX.burst, true)
        addMask(sp, lb.topMask)
        sp:SetVertexColor(K.sparkColor[1], K.sparkColor[2], K.sparkColor[3])
        fx.sparks[i], fx.spX[i], fx.spY[i], fx.spVX[i], fx.spVY[i] = sp, 0, 0, 0, 0
    end
    fx.pulse = fxTex(lb.top, "ARTWORK", 7, nil, true)
    fx.pulse:SetColorTexture(1, 0.18, 0.08, 1)
    addMask(fx.pulse, lb.topMask)
    if lb.glow then
        fx.burn = fxTex(lb.glow, "ARTWORK", 1, nil, true)
        fx.burn:SetTexture(Fx.TEX.ink, "REPEAT", "REPEAT")
        fx.burn:SetVertexColor(K.burnColor[1], K.burnColor[2], K.burnColor[3])
        addMask(fx.burn, lb.glowMask)
        addMask(fx.burn, lb.glowIn)
    end
    if ns.LiquidFizz and lb.opts and lb.opts.frame == "power" and lb.opts.fizz ~= false then ns.LiquidFizz.Attach(lb) end
    tubes[lb] = true
end

--- Rolle und Schalter (aus Skin.lua): role = "player-health"|"player-power"|"target-health"|... oder nil; on = Effekte,
--- debuffs = Schlieren (nur "player-health")
function Fx.Configure(lb, role, on, debuffs)
    local fx = lb.fx
    if not fx then return end
    fx.role = role
    fx.on = on == true and role ~= nil
    fx.debuffs = debuffs == true and role == "player-health" -- unabhaengig vom Effekt-Schalter
    if not fx.on then
        fx.healT, fx.hitT, fx.glowT = nil, nil, nil
        for _, t in ipairs({ fx.glow, fx.sweep, fx.spark, fx.flash, fx.star, fx.splash, fx.halo, fx.core, fx.pulse }) do t:Hide() end
        for _, t in ipairs(fx.sparks) do t:Hide() end
        if fx.burn then fx.burn:Hide() end
        if ns.Liquid.Nudge then ns.Liquid.Nudge(lb, 0, 0) end
    end
    if fx.fizz then ns.LiquidFizz.Configure(lb, fx.on and role == "player-power") end
    if not fx.debuffs then
        fx.tint:Hide()
        fx.extra:Hide()
        fx.tintA, fx.tintSecret, fx.tintTarget, fx.extraKind = 0, false, nil, nil
        for i = 1, #fx.tintS do fx.tintS[i]:Hide(); fx.darkS[i]:Hide() end
        for i = 1, #fx.borderL do ns.LiquidBorder.Hide(fx.borderL[i]) end
        fx.borderN = 0
        fx.pWant, fx.pA = false, 0
        fx.pFrame:Hide()
        for i = 1, #fx.pB do fx.pOn[i] = false; fx.pB[i]:Hide() end
        Fx.GlowOverride(lb, nil, 0)
        lb.bodyDim = nil
    end
    Fx.UpdateDebuffListening()
    if fx.debuffs then Fx.ApplyInk(lb) end
end

function Fx.SetLevel(lb, level)
    local fx = lb.fx
    if not fx then return end
    fx.old:SetFrameLevel(level)
    fx.clip:SetFrameLevel(level + 2)
    fx.pFrame:SetFrameLevel(level + 2)
    if fx.fizz then ns.LiquidFizz.SetLevel(lb, level + 2) end
end

--- Lagen legen (aus Liquid.Layout, nach SetStyle): Clip = Fluessigkeit, Effekte im Koerper (Kolben-Kammer: unter dem Luftspalt)
function Fx.Layout(lb)
    local fx = lb.fx
    if not fx then return end
    local root, h = lb.root, lb.h or 10
    local fill = lb.barTex or root
    local top = lb.style == "piston" and ns.Liquid.PISTON.gap * h or 0
    fx.top, fx.bodyH = top, h - top
    fx.old:ClearAllPoints()
    fx.old:SetAllPoints(root)
    local clip = fx.clip
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    if fx.cap then
        if lb.maskPath then pcall(fx.cap.SetTexture, fx.cap, lb.maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
        fx.cap:ClearAllPoints()
        fx.cap:SetAllPoints(root)
    end
    local ramp = math.max(1, Fx.RISE.ramp * h)
    local m, a = fx.gainMask, fx.oldTex or fx.old
    if m then
        m:ClearAllPoints()
        m:SetPoint("TOPLEFT", a, "TOPRIGHT", 0, 0)
        m:SetPoint("BOTTOMLEFT", a, "BOTTOMRIGHT", 0, 0)
        m:SetWidth(ramp)
    end
    fx.pFrame:ClearAllPoints()
    fx.pFrame:SetAllPoints(root)
    if fx.pMask then
        if lb.maskPath then pcall(fx.pMask.SetTexture, fx.pMask, lb.maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
        fx.pMask:ClearAllPoints()
        fx.pMask:SetAllPoints(root)
    end
    for i = 1, #fx.tintS do
        fx.tintS[i]:ClearAllPoints()
        fx.tintS[i]:SetAllPoints(lb.fillIn)
        fx.darkS[i]:ClearAllPoints()
        fx.darkS[i]:SetAllPoints(lb.fillIn)
    end
    local body = { fx.glow, fx.extra }
    for _, t in ipairs(body) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -top)
        t:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    end
    local H, K = Fx.HEAL, Fx.HIT
    fx.sweep:SetSize(H.sweepW * h, fx.bodyH * 1.3)
    fx.spark:SetSize(H.sparkW * h, fx.bodyH)
    fx.flash:ClearAllPoints()
    fx.flash:SetPoint("RIGHT", fill, "RIGHT", 0, -top / 2)
    fx.flash:SetSize(K.flashW * h, fx.bodyH * 1.4)
    fx.star:ClearAllPoints()
    fx.star:SetPoint("CENTER", fill, "RIGHT", 0, -top / 2)
    fx.splash:ClearAllPoints()
    fx.splash:SetPoint("BOTTOM", fill, "TOPRIGHT", -0.2 * h, -top - 0.12 * h)
    fx.splash:SetSize(K.splashW * h, K.splashH * h)
    for _, t in ipairs({ fx.core, fx.halo }) do
        t:ClearAllPoints()
        t:SetPoint("CENTER", fill, "RIGHT", 0, -top / 2)
    end
    fx.pulse:ClearAllPoints()
    fx.pulse:SetAllPoints(root)
    if fx.burn then
        fx.burn:ClearAllPoints()
        fx.burn:SetPoint("RIGHT", lb.trailTex or lb.trail, "RIGHT", 0, 0)
        fx.burn:SetSize(K.burnW * h, h)
    end
    fx.layoutW, fx.layoutH = lb.w or 100, h
    fx.inkTile = 0.35 -- Kachelanteil der Zusatz-Lage
    fx.tint:ClearAllPoints()
    fx.tint:SetAllPoints(lb.fillIn)
    fx.tintTile = math.max(0.2, (lb.w or 100) / (ns.Liquid.PISTON.bodyTile * h))
    Fx.LayoutBorder(lb)
    if fx.fizz then ns.LiquidFizz.Layout(lb) end
end

--- Rahmen-Toenung legen (Weg "clip"): Streifen gestreckt ueber die ganze Flaeche von fillIn (Roehre + Ueberstand lb.under
--- je Seite, volle Hoehe wie tintS); was darueber hinausragt, schneidet die Kapselmaske (CLAMPTOBLACKADDITIVE) und der
--- Fluessigkeits-Clip ab. Bei Layout und bei jeder Aenderung des Ausschnitts, nie pro Bild.
function Fx.LayoutBorder(lb)
    local fx, BD = lb.fx, ns.LiquidBorder
    if not (fx and BD and #fx.borderL > 0) then return end
    local strip = BD.Strip()
    local u = lb.under or 0
    for i = 1, #fx.borderL do
        BD.Place(fx.borderL[i], lb.fillIn, (lb.w or 100) + 2 * u, lb.h or 10, 0, strip)
    end
    fx.borderStrip = strip
end

-- Werte (aus Liquid.SetValue/SetMax/Snap*) ------------------------------------------------------------------------------
-- Verzoegerte Werte ohne Closures: je Anker-Bar eine Ringliste (vorab angelegte Tabellen, Werte nur gespeichert/durchgereicht)
-- und EIN gemeinsamer Zeitgeber mit einer festen Funktion (kein Timer je Wert, keine Flut beim abgefragten ToT).
local timerDue = math.huge
local flushQueues

local function clearQueue(q)
    if not q then return end
    for i = q.head, q.tail do q.v[i], q.t[i] = nil, nil end
    q.head, q.tail = 1, 0
end

local function schedule(due)
    if due >= timerDue - 0.001 then return end
    timerDue = due
    C_Timer.After(math.max(0, due - now()), flushQueues)
end

local function push(q, v, t)
    local due = t + q.delay
    if q.tail - q.head + 1 >= Fx.QUEUE_MAX then
        q.v[q.tail] = v -- voll: juengster Wert ersetzt den letzten (Zeitpunkt bleibt)
        return
    end
    q.tail = q.tail + 1
    q.v[q.tail], q.t[q.tail] = v, due
    schedule(due)
end

-- faellige Werte einer Liste an ihre Bar; liefert den naechsten Faelligkeitszeitpunkt (oder nextDue)
local function drain(q, glide, t, nextDue)
    if not q then return nextDue end
    while q.head <= q.tail and q.t[q.head] <= t + 0.001 do
        setValue(q.bar, q.v[q.head], glide)
        q.v[q.head], q.t[q.head] = nil, nil
        q.head = q.head + 1
    end
    if q.head > q.tail then
        q.head, q.tail = 1, 0
        return nextDue
    end
    if not nextDue or q.t[q.head] < nextDue then return q.t[q.head] end
    return nextDue
end

flushQueues = function()
    local t = now()
    if t >= timerDue - 0.001 then timerDue = math.huge end
    local nextDue
    for lb in pairs(tubes) do
        local fx = lb.fx
        nextDue = drain(fx.qOld, fx.glide, t, nextDue)
    end
    if nextDue then schedule(nextDue) end
end
Fx.FlushQueues = flushQueues

--- Neuer Wert (secret erlaubt): alter Stand folgt verzoegert; startet Nachgluehen bzw. Ressourcen-Strom. Effekte aus (ToT,
--- Schalter): die Anker-Bars bekommen den Wert sofort (kein Band, keine Warteschlange).
function Fx.OnValue(lb, value, glide)
    local fx = lb.fx
    if not fx then return end
    if not fx.on then
        if IMMEDIATE == nil then readEnum() end
        clearQueue(fx.qOld)
        setValue(fx.old, value, IMMEDIATE)
        return
    end
    fx.glide = glide
    local t = now()
    fx.lastValue = value -- nur gemerkt (secret erlaubt), fuer /vials test heilung
    push(fx.qOld, value, t)
    if not fx.fizz then -- Ressource: Sprudeln statt Nachgluehen (LiquidFizz)
        fx.glowT, fx.glowAmp = t, math.max(fx.glowT and fx.glowAmp or 0, Fx.HEAL.glow)
        fx.busy = true
    end
    if ns.Liquid.Wake then ns.Liquid.Wake() end
end

function Fx.OnMax(lb, maxValue)
    local fx = lb.fx
    if not fx then return end
    pcall(fx.old.SetMinMaxValues, fx.old, 0, maxValue)
end

--- Einrasten (Zielwechsel, Login): offene Nachzieh-Auftraege verfallen
function Fx.OnSnap(lb)
    local fx = lb.fx
    if not fx then return end
    fx.epoch = fx.epoch + 1
    clearQueue(fx.qOld)
    fx.glowT, fx.healT = nil, nil
end

function Fx.OnSnapValue(lb, value)
    local fx = lb.fx
    if not fx then return end
    if IMMEDIATE == nil then readEnum() end
    setValue(fx.old, value, IMMEDIATE)
    fx.lastValue = value
end

--- /vials test heilung: der alte Stand springt auf 0 (die ganze Fluessigkeit gilt als gewonnen) und zieht nach
--- RISE.delay wieder auf den aktuellen Wert; dazu die volle Heilung (crit). Nur Spieler-Leben.
function Fx.TestHeal()
    local any = false
    for lb in pairs(tubes) do
        local fx = lb.fx
        if fx.on and fx.role == "player-health" then
            if IMMEDIATE == nil then readEnum() end
            if fx.lastValue ~= nil then
                setValue(fx.old, 0, IMMEDIATE)
                push(fx.qOld, fx.lastValue, now())
            end
            any = true
        end
    end
    Fx.Heal(true)
    return any
end

--- /vials test treffer: Schadensspur ueber den leeren Teil (Liquid.TestLoss) und ein kritischer Treffer
function Fx.TestHit()
    local any = false
    for lb in pairs(tubes) do
        local fx = lb.fx
        if fx.on and fx.role == "player-health" then
            pcall(ns.Liquid.TestLoss, lb)
            any = true
        end
    end
    Fx.Hit(true)
    return any
end

-- Ausloeser -------------------------------------------------------------------------------------------------------------------
local function forRole(role, fn, ...)
    local hit = false
    for lb in pairs(tubes) do
        local fx = lb.fx
        if fx and fx.on and fx.role == role then
            fn(lb, fx, ...)
            hit = true
        end
    end
    return hit
end

local function startHeal(lb, fx, st)
    local t = now()
    if fx.healT and t - fx.healT < Fx.HEAL.cooldown then
        fx.healAmp = math.max(fx.healAmp, st) -- HoT-Ticks/Mehrfachheilung: buendeln
        return
    end
    fx.healT, fx.healAmp = t, st
    fx.glowT, fx.glowAmp = t, Fx.HEAL.healGlow * st
    fx.busy = true
end

local function startHit(lb, fx, st)
    local t = now()
    if fx.hitT and t - fx.hitT < Fx.HIT.cooldown then
        fx.hitAmp = math.max(fx.hitAmp, st)
        return
    end
    fx.hitT, fx.hitAmp = t, st
    -- Funken: wenige Sprites aus dem Pool, nach rechts oben aus dem Bruchpunkt (ballistisch in stepHit)
    local K, h = Fx.HIT, lb.h or 10
    fx.spN = st > 1 and K.sparksCrit or K.sparks
    for i = 1, #fx.sparks do
        local ang = (-0.35 + 1.6 * math.random()) -- rad: leicht unter waagrecht bis steil nach oben/links
        local v = K.sparkV * h * (0.5 + 0.7 * math.random()) * (st > 1 and 1.2 or 1)
        fx.spX[i], fx.spY[i] = 0, 0
        fx.spVX[i], fx.spVY[i] = v * math.cos(ang), v * math.sin(ang) + 0.3 * K.sparkV * h
        if i > fx.spN then fx.sparks[i]:Hide() end
    end
    fx.busy = true
end

--- Heilung (crit: staerker); "player" = Spieler-Lebensroehre
function Fx.Heal(crit)
    if forRole("player-health", startHeal, crit and Fx.HEAL.crit or 1) and ns.Liquid.Wake then ns.Liquid.Wake() end
end

--- Zufluss-Leuchten wie bei der Heilung (Lichtstreifen, Funkeln, Stern, goldenes Nachgluehen) fuer eine andere Rolle, z. B.
--- "player-xp" (Erfahrungsleiste: Erfahrung gewonnen, Stufenaufstieg)
function Fx.Glow(role, crit)
    if forRole(role, startHeal, crit and Fx.HEAL.crit or 1) and ns.Liquid.Wake then ns.Liquid.Wake() end
end

--- Treffer (crit: staerker)
function Fx.Hit(crit)
    if forRole("player-health", startHit, crit and Fx.HIT.crit or 1) and ns.Liquid.Wake then ns.Liquid.Wake() end
end

--- UNIT_COMBAT fuer "player": nur das Ereignis und (wenn lesbar) der Text; die Menge (secret) wird nie gelesen
local function onCombat(unit, ev, flagText)
    if Compat.IsSecret(unit) or unit ~= "player" then return end
    if type(ev) ~= "string" or Compat.IsSecret(ev) then return end
    local crit = type(flagText) == "string" and not Compat.IsSecret(flagText)
        and (flagText == "CRITICAL" or flagText == "CRUSHING")
    if ev == "HEAL" then
        Fx.Heal(crit)
        return
    end
    local PH = ns.LiquidPhysics
    local hits = PH and PH.HIT_EVENTS or { WOUND = true }
    if hits[ev] then Fx.Hit(crit) end
end
Fx.OnCombat = onCombat
do
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, _, unit, ev, flagText) pcall(onCombat, unit, ev, flagText) end)
    if not pcall(f.RegisterUnitEvent, f, "UNIT_COMBAT", "player") then pcall(f.RegisterEvent, f, "UNIT_COMBAT") end
    Fx.combatFrame = f
end

-- Debuffs ---------------------------------------------------------------------------------------------------------------------
local curve -- Stufen-Farbkurve Dispel-Typ-ID -> Farbe (einmal angelegt)

--- gelernte IDs (LucidVialsDB.dispelIds, global) - nur gueltige ganze Zahlen 0..learnMax
local function learned()
    local db = ns.Store and ns.Store.db
    local t = type(db) == "table" and db.dispelIds or nil
    if type(t) ~= "table" then return nil end
    return t
end

local function validId(v)
    return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= Fx.INK.learnMax
end

--- Dispel-Typ-IDs je Bannart: gelernt (Selbstkalibrierung) > Enum zur Laufzeit > Annahme Fx.INK.ids.
--- Liefert ids, Quelle ("learned" | "learned+fallback" | "enum" | "fallback")
local function dispelIds()
    local L = learned()
    local E = type(Enum) == "table" and (Enum.DispelType or Enum.AuraDispelType or Enum.SpellDispelType) or nil
    local enum = type(E) == "table"
    local out, nL, nE = {}, 0, 0
    for _, k in ipairs(Fx.INK.order) do
        local v = L and L[k]
        if validId(v) then
            nL = nL + 1
        else
            v = enum and Compat.Num(E[k]) or nil
            if v then nE = nE + 1 else v = Fx.INK.ids[k] end
        end
        out[k] = v
    end
    if nL == #Fx.INK.order then return out, "learned" end
    if nL > 0 then return out, "learned+fallback" end
    if nE == #Fx.INK.order then return out, "enum" end
    return Fx.INK.ids, "fallback"
end
Fx.DispelIds = dispelIds

local function colorCurve()
    if curve ~= nil then return curve or nil end
    curve = false
    local C = _G.C_CurveUtil
    if not (C and type(C.CreateColorCurve) == "function" and type(CreateColor) == "function") then return nil end
    local ok, c = pcall(C.CreateColorCurve)
    if not ok or (type(c) ~= "table" and type(c) ~= "userdata") then return nil end
    local step = type(Enum) == "table" and type(Enum.LuaCurveType) == "table" and Enum.LuaCurveType.Step or 1
    pcall(c.SetType, c, step)
    local ids = dispelIds()
    local maxId = 0
    for _, k in ipairs(Fx.INK.order) do
        local col = Fx.INK.colors[k]
        pcall(c.AddPoint, c, ids[k], CreateColor(col[1], col[2], col[3], Fx.INK.tintA[k] or Fx.INK.secretA))
        if ids[k] > maxId then maxId = ids[k] end
    end
    pcall(c.AddPoint, c, 0, CreateColor(0, 0, 0, 0))
    pcall(c.AddPoint, c, maxId + 1, CreateColor(0, 0, 0, 0))
    curve = c
    return c
end
Fx.ColorCurve = colorCurve

-- Zusatz-Kurven (secret): Gift-Blasen (nur Gift leuchtgruen, sonst Alpha 0) und Abdunkeln (schwarz, Deckkraft je Art)
local poisonCurve, darkCurve
local function makeCurve(colorOf)
    local C = _G.C_CurveUtil
    if not (C and type(C.CreateColorCurve) == "function" and type(CreateColor) == "function") then return false end
    local ok, c = pcall(C.CreateColorCurve)
    if not ok or (type(c) ~= "table" and type(c) ~= "userdata") then return false end
    local step = type(Enum) == "table" and type(Enum.LuaCurveType) == "table" and Enum.LuaCurveType.Step or 1
    pcall(c.SetType, c, step)
    local ids = dispelIds()
    local maxId = 0
    for _, k in ipairs(Fx.INK.order) do
        local r, g, b, a = colorOf(k)
        pcall(c.AddPoint, c, ids[k], CreateColor(r, g, b, a))
        if ids[k] > maxId then maxId = ids[k] end
    end
    pcall(c.AddPoint, c, 0, CreateColor(0, 0, 0, 0))
    pcall(c.AddPoint, c, maxId + 1, CreateColor(0, 0, 0, 0))
    return c
end
local function poisonColorOf(k)
    local c = Fx.INK.poison.color
    if k == "Poison" then return c[1], c[2], c[3], 1 end
    return 0, 0, 0, 0
end
local function darkColorOf(k) return 0, 0, 0, Fx.INK.darkA[k] or 0 end
local function extraCurves()
    if poisonCurve == nil then poisonCurve = makeCurve(poisonColorOf) end
    if darkCurve == nil then darkCurve = makeCurve(darkColorOf) end
    return poisonCurve or nil, darkCurve or nil
end

local function auraField(a, key)
    if type(a) ~= "table" or Compat.IsSecret(a) then return nil, true end
    local ok, v = pcall(function() return a[key] end)
    if not ok then return nil, true end
    if Compat.IsSecret(v) then return nil, true end
    return v, false
end

--- Harmful-Auren des Spielers als Liste { data, id } (Tabellen nur hier, bei UNIT_AURA), dazu der Zweig ("ids" | "auras" |
--- "index" | "debuffindex"). Instanz-IDs duerfen secret sein: sie werden nur an die Aura-APIs durchgereicht.
local function harmful()
    local U = _G.C_UnitAuras
    if type(U) ~= "table" then return nil, "nil" end
    local list, M = {}, Fx.INK.scanMax
    if type(U.GetUnitAuraInstanceIDs) == "function" then
        local ok, ids = pcall(U.GetUnitAuraInstanceIDs, "player", "HARMFUL", M)
        if ok and type(ids) == "table" and not Compat.IsSecret(ids) then
            for i = 1, math.min(#ids, M) do
                local id = ids[i]
                local okD, d = false, nil
                if type(U.GetAuraDataByAuraInstanceID) == "function" then okD, d = pcall(U.GetAuraDataByAuraInstanceID, "player", id) end
                list[#list + 1] = { data = okD and d or nil, id = id }
            end
            return list, "ids"
        end
    end
    if type(U.GetUnitAuras) == "function" then
        local ok, auras = pcall(U.GetUnitAuras, "player", "HARMFUL")
        if ok and type(auras) == "table" and not Compat.IsSecret(auras) then
            for i = 1, math.min(#auras, M) do
                local id = auraField(auras[i], "auraInstanceID")
                list[#list + 1] = { data = auras[i], id = id }
            end
            return list, "auras"
        end
    end
    -- Rueckfall je Index: GetAuraDataByIndex(..., "HARMFUL"), sonst GetDebuffDataByIndex; die auraInstanceID wird roh
    -- durchgereicht (auch secret), damit die Kurve sie im Kampf noch faerben kann
    for _, v in ipairs({ { U.GetAuraDataByIndex, "index", "HARMFUL" }, { U.GetDebuffDataByIndex, "debuffindex" } }) do
        local fn, tag, filter = v[1], v[2], v[3]
        if type(fn) == "function" then
            local okAll = true
            for i = 1, M do
                local ok, d
                if filter then ok, d = pcall(fn, "player", i, filter) else ok, d = pcall(fn, "player", i) end
                if not ok then okAll = false; break end
                if d == nil then break end
                local id
                if type(d) == "table" and not Compat.IsSecret(d) then
                    local okI, v2 = pcall(function() return d.auraInstanceID end)
                    if okI then id = v2 end
                end
                list[#list + 1] = { data = d, id = id }
            end
            if okAll then return list, tag end
            list = {}
        end
    end
    return nil, "nil"
end

--- Rueckfall im Kampf (Forever: RequiresUnitAuraAccess => jede C_UnitAuras-Abfrage wirft, Log 18.11. "zweig=nil"):
--- Blizzards eigene Debuff-Leiste (Blizzard_BuffFrame, DebuffFrameMixin:UpdateAuras) laeuft ungetaintet und legt je Debuff
--- auraInfo[i] = { auraType = "Debuff", debuffType = auraData.dispelName, ... } ab; der Wert ist dort ein gewoehnlicher Text
--- (AuraUtil.SetAuraBorderAtlas indiziert damit DEBUFF_DISPLAY_INFO). Nur gelesen, nie geschrieben; secret => uebersprungen.
--- Liste wie harmful() ({ data = { dispelName = <Text|nil> } }) oder nil, wenn die Leiste fehlt.
local function blizzDebuffs()
    local f = _G.DebuffFrame
    if type(f) ~= "table" then return nil end
    local ok, info = pcall(function() return f.auraInfo end)
    if not ok or type(info) ~= "table" or Compat.IsSecret(info) then return nil end
    local list = {}
    for i = 1, math.min(#info, Fx.INK.scanMax) do
        local e = info[i]
        if type(e) == "table" and not Compat.IsSecret(e) then
            local okT, kind, name, id = pcall(function() return e.auraType, e.debuffType, e.auraInstanceID end)
            if okT and not Compat.IsSecret(kind) and kind == "Debuff" then
                -- secret Bannart (Log 18.11.: auch hier im Kampf secret) bleibt secret => Farbkurven-Weg mit der
                -- auraInstanceID (roh durchgereicht); lesbarer Text => direkt
                list[#list + 1] = { data = { dispelName = name }, id = id, blizz = true, src = e }
            end
        end
    end
    -- Diagnose: Rahmen-Atlas des passenden Knopfs (Blizzard faerbt ihn je Bannart, wenn "Bannart zeigen" an ist)
    local okF, frames = pcall(function() return f.auraFrames end)
    if okF and type(frames) == "table" then
        for _, b in ipairs(frames) do
            local okB, bi, border = pcall(function() return b.buttonInfo, b.DebuffBorder end)
            if okB and bi ~= nil and not Compat.IsSecret(bi) then
                for _, item in ipairs(list) do
                    if item.src == bi and type(border) == "table" then
                        local okA, atlas = pcall(border.GetAtlas, border)
                        item.border = not okA and "fehler" or Compat.IsSecret(atlas) and "secret" or tostring(atlas)
                    end
                end
            end
        end
    end
    return list
end
Fx.BlizzDebuffs = blizzDebuffs

--- Instanz-IDs der bannbaren schaedlichen Auren ("HARMFUL|RAID") als Menge (nur lesbare IDs; Tabelle nur bei UNIT_AURA)
local function dispellableSet()
    local set = {}
    local U = _G.C_UnitAuras
    if type(U) ~= "table" or type(U.GetUnitAuraInstanceIDs) ~= "function" then return set end
    local ok, ids = pcall(U.GetUnitAuraInstanceIDs, "player", "HARMFUL|RAID", Fx.INK.scanMax)
    if not ok or type(ids) ~= "table" or Compat.IsSecret(ids) then return set end
    for i = 1, math.min(#ids, Fx.INK.scanMax) do
        local id = ids[i]
        if id ~= nil and not Compat.IsSecret(id) then set[id] = true end
    end
    return set
end

local idCurveObj -- Identitaets-Kurve x = k -> Rot k/16 (Selbstkalibrierung, einmal angelegt)
local function idCurve()
    if idCurveObj ~= nil then return idCurveObj or nil end
    idCurveObj = false
    local C = _G.C_CurveUtil
    if not (C and type(C.CreateColorCurve) == "function" and type(CreateColor) == "function") then return nil end
    local ok, c = pcall(C.CreateColorCurve)
    if not ok or (type(c) ~= "table" and type(c) ~= "userdata") then return nil end
    local step = type(Enum) == "table" and type(Enum.LuaCurveType) == "table" and Enum.LuaCurveType.Step or 1
    pcall(c.SetType, c, step)
    for k = 0, Fx.INK.learnMax do pcall(c.AddPoint, c, k, CreateColor(k / 16, 0, 0, 1)) end
    idCurveObj = c
    return c
end

--- Selbstkalibrierung: lesbarer dispelName + lesbare Kurvenfarbe => Typ-ID dieser Bannart in LucidVialsDB.dispelIds (global).
--- Nur ausserhalb der Sperre moeglich (sonst secret: nichts gelernt). Liefert true, wenn sich etwas geaendert hat.
function Fx.Learn(name, id)
    local U = _G.C_UnitAuras
    local db = ns.Store and ns.Store.db
    if type(db) ~= "table" or not Fx.INK.colors[name] or id == nil or Compat.IsSecret(id) then return false end
    if type(U) ~= "table" or type(U.GetAuraDispelTypeColor) ~= "function" then return false end
    local L = learned()
    if L and validId(L[name]) then return false end -- schon gelernt
    local c = idCurve()
    if not c then return false end
    local ok, col = pcall(U.GetAuraDispelTypeColor, "player", id, c)
    if not ok or Compat.IsSecret(col) or col == nil then return false end
    local okR, r = pcall(function()
        if type(col.GetRGBA) == "function" then return (col:GetRGBA()) end
        return col.r
    end)
    if not okR or Compat.IsSecret(r) or type(r) ~= "number" then return false end
    local v = math.floor(r * 16 + 0.5)
    if not validId(v) or v == 0 then return false end -- 0 = keine Bannart
    if type(db.dispelIds) ~= "table" then db.dispelIds = {} end
    for other, ov in pairs(db.dispelIds) do
        if other ~= name and ov == v then return false end -- Doppelbelegung: unplausibel, nicht speichern
    end
    db.dispelIds[name] = v
    curve, poisonCurve, darkCurve = nil, nil, nil -- Kurven mit den gelernten IDs neu anlegen
    return true
end

--- Schlieren-Zustand neu bestimmen: lesbare Bannarten zuerst (je Art eine Ebene), dann secret Auren (je Instanz eine Ebene,
--- Farbe aus der Kurve). Fehler (Aura-Zugriff gesperrt) => alter Zustand bleibt (kein Flackern).
-- Kampf-Protokoll (Ringpuffer, nur bei UNIT_AURA): eine Zeile je Abtastung, fuer /vials debug (Fx.DebugLines)
Fx.LOG_MAX = 20
local logLines, logHead = {}, 0
local function logScan(branch, n, nSecretId, results)
    local ids, src = dispelIds()
    local inCombat = type(InCombatLockdown) == "function" and InCombatLockdown() == true
    logHead = logHead % Fx.LOG_MAX + 1
    logLines[logHead] = string.format("t=%.1f kampf=%s zweig=%s auren=%d secretIds=%d [%s] ids=%s(M%s C%s D%s P%s)",
        type(GetTime) == "function" and GetTime() or 0, inCombat and "ja" or "nein", branch, n, nSecretId,
        table.concat(results, ","), tostring(src), tostring(ids.Magic), tostring(ids.Curse), tostring(ids.Disease),
        tostring(ids.Poison))
end

--- Zeilen fuer /vials debug: Zustand und Kampf-Protokoll (aelteste zuerst)
function Fx.DebugLines()
    local out = {}
    local ids, src = dispelIds()
    local BD = ns.LiquidBorder
    local strip = BD and BD.Strip() or nil
    out[#out + 1] = string.format("frames.ink n=%d secret=%d quelle=%s magie=%s fluch=%s krankheit=%s gift=%s rahmen=%d"
        .. " rahmen.weg=%s rahmen.quelle=%s", inkState.n or 0, inkState.secret or 0, tostring(src), tostring(ids.Magic),
        tostring(ids.Curse), tostring(ids.Disease), tostring(ids.Poison), inkState.border or 0,
        strip and strip.mode or "-", strip and strip.src or "-")
    for k = 1, Fx.LOG_MAX do
        local idx = (logHead + k - 1) % Fx.LOG_MAX + 1
        if logLines[idx] then out[#out + 1] = "frames.ink.log " .. logLines[idx] end
    end
    return out
end

function Fx.ScanDebuffs()
    -- Rahmen-Geometrie einmal ausserhalb des Kampfs messen (LiquidBorder; im Kampf no-op, danach gemerkt)
    if ns.LiquidBorder then pcall(ns.LiquidBorder.Measure) end -- gemerkt; ohne Treffer gedrosselt neu
    local list, branch = harmful()
    if not list then
        list = blizzDebuffs()
        if list then branch = "blizz" end
    end
    if not list then
        logScan(branch or "nil", 0, 0, { "fehler: alter Zustand bleibt" })
        return false
    end
    local I = Fx.INK
    local seen, secretIds, rest = {}, {}, {}
    local raid = dispellableSet()
    local results, nSecretId = {}, 0
    for _, e in ipairs(list) do
        if Compat.IsSecret(e.id) then nSecretId = nSecretId + 1 end
        if e.blizz then
            local raw = e.data and e.data.dispelName
            results[#results + 1] = "blizz:" .. (Compat.IsSecret(raw) and "secret" or type(raw)) .. "/id="
                .. (Compat.IsSecret(e.id) and "secret" or type(e.id)) .. "/rand=" .. tostring(e.border or "-")
        end
        local name, secret = auraField(e.data, "dispelName")
        if e.data == nil then secret = true end
        if type(name) == "string" and I.colors[name] then
            seen[name] = true
            results[#results + 1] = name
            if not e.blizz then pcall(Fx.Learn, name, e.id) end
        elseif not secret then
            results[#results + 1] = "keine"
        elseif e.id == nil then
            results[#results + 1] = "secret:ohne-id"
        elseif secret and e.id ~= nil then
            -- bannbare zuerst (haben sicher eine Bannart); die uebrigen nur in freie Ebenen
            local key = not Compat.IsSecret(e.id) and e.id or nil
            if key ~= nil and raid[key] then secretIds[#secretIds + 1] = e.id else rest[#rest + 1] = e.id end
        end
    end
    for _, id in ipairs(rest) do secretIds[#secretIds + 1] = id end
    local kinds, colors = {}, {}
    for _, k in ipairs(I.order) do
        if seen[k] and #kinds < I.max then
            kinds[#kinds + 1] = k
            colors[#colors + 1] = I.colors[k]
        end
    end
    local nSecret = 0
    local poisonCols, darkCols = {}, {}
    local U = _G.C_UnitAuras
    local c = #secretIds > 0 and colorCurve() or nil
    if c and type(U.GetAuraDispelTypeColor) == "function" then
        for _, id in ipairs(secretIds) do
            if #kinds >= I.max then break end
            local ok, col = pcall(U.GetAuraDispelTypeColor, "player", id, c)
            if ok and not Compat.IsSecret(col) and col == nil then ok = false end
            if ok then
                kinds[#kinds + 1] = "secret"
                colors[#colors + 1] = col -- secret ColorMixin: nur an SetVertexColor
                nSecret = nSecret + 1
                -- je secret Aura Gift-Blasen- und Abdunkel-Farbe (secret, nur durchgereicht)
                local pc, dc = extraCurves()
                local okP, colP = false, nil
                if pc then okP, colP = pcall(U.GetAuraDispelTypeColor, "player", id, pc) end
                local okD, colD = false, nil
                if dc then okD, colD = pcall(U.GetAuraDispelTypeColor, "player", id, dc) end
                poisonCols[nSecret] = okP and colP or false
                darkCols[nSecret] = okD and colD or false
                results[#results + 1] = "secret:kurve-ok"
            else
                results[#results + 1] = "secret:kurve-fehl"
            end
        end
    elseif #secretIds > 0 then
        for _ = 1, #secretIds do results[#results + 1] = "secret:keine-kurve" end
    end
    -- Farbe aus Blizzards Debuff-Rahmen (LiquidBorder, Delta "Kampf-Toenung" 26.11.): je Knopf der Leiste (Reihenfolge der
    -- Leiste, hoechstens freie Ebenen) nach LiquidBorder.Classify - secret Atlas => Rahmen-Ebene, lesbarer Farb-Rahmen =>
    -- eigene Palette dieser Art (schon gesehene Arten nicht doppelt). Unabhaengig von dispelName/debuffType (Kampftest:
    -- im Kampf auch lesbar nil). Fehlt die Leiste oder wirft etwas: ohne Toenung (kein grauer Schleier).
    -- Zuordnung Knopf <-> Aura ist nicht sicher moeglich (auraInstanceID secret, nicht vergleichbar): darum der Rahmen-Weg NUR,
    -- wenn keine secret Aura ueber die Kurve geklaert wurde (nSecret == 0); sonst gelten allein die Kurven-Farben (ein Rahmen
    -- koennte die Farbe einer schon geklaerten Aura doppeln).
    local unresolved = 0
    for _, r in ipairs(results) do
        if r == "secret:kurve-fehl" or r == "secret:keine-kurve" or r == "secret:ohne-id" then unresolved = unresolved + 1 end
    end
    local nBorder = 0
    if nSecret == 0 and #kinds < I.max and ns.LiquidBorder then
        local okB, cands = pcall(ns.LiquidBorder.Candidates, I.scanMax)
        if okB and type(cands) == "table" then
            for _, info in ipairs(cands) do
                if #kinds >= I.max then break end
                local k = info.class
                if k == "border" then
                    kinds[#kinds + 1] = "border"
                    colors[#colors + 1] = info -- { atlas = <secret>, vc = {...} }: nur an SetAtlas/SetVertexColor
                    nBorder = nBorder + 1
                elseif I.colors[k] and not seen[k] then
                    seen[k] = true -- lesbarer Farb-Rahmen: eigene Palette (inkl. Gift-Blasen ueber inkState.poison)
                    kinds[#kinds + 1] = k
                    colors[#colors + 1] = I.colors[k]
                    results[#results + 1] = "rahmen:" .. k
                end
            end
        end
        if not okB then results[#results + 1] = "rahmen:fehler"
        elseif nBorder > 0 then results[#results + 1] = "rahmen:" .. nBorder end
    end
    if unresolved > 0 and #kinds == 0 then results[#results + 1] = "ohne-toenung" end
    inkState.poisonCols, inkState.darkCols = poisonCols, darkCols
    inkState.poisonCol, inkState.darkCol = poisonCols[1] or nil, darkCols[1] or nil
    logScan(branch, #list, nSecretId, results)
    inkState.poison = seen.Poison == true
    inkState.n, inkState.kinds, inkState.colors, inkState.secret = #kinds, kinds, colors, nSecret
    inkState.border = nBorder
    for lb in pairs(tubes) do
        if lb.fx and lb.fx.debuffs then Fx.ApplyInk(lb) end
    end
    return true
end

--- Testmodus/Tests: Schlieren direkt setzen (Liste von Bannarten)
function Fx.SetTestDebuffs(list)
    local kinds, colors = {}, {}
    for _, k in ipairs(list or {}) do
        if Fx.INK.colors[k] and #kinds < Fx.INK.max then
            kinds[#kinds + 1] = k
            colors[#colors + 1] = Fx.INK.colors[k]
        end
    end
    inkState.poisonCol, inkState.darkCol, inkState.poisonCols, inkState.darkCols = nil, nil, {}, {}
    inkState.poison = false
    for _, k in ipairs(kinds) do if k == "Poison" then inkState.poison = true end end
    inkState.n, inkState.kinds, inkState.colors, inkState.secret, inkState.border = #kinds, kinds, colors, 0, 0
    for lb in pairs(tubes) do
        if lb.fx and lb.fx.debuffs then Fx.ApplyInk(lb) end
    end
end

--- Farben auf die Ebenen einer Roehre (bei Aenderung, nie pro Bild)
function Fx.ApplyInk(lb)
    local fx = lb.fx
    -- Toenung: vorherrschende (erste) Art; secret => Farbe direkt (Alpha aus der Kurve), lesbar => weich ueberblenden
    local kind, col = inkState.kinds[1], inkState.colors[1]
    -- secret Auren: je Aura eigene Toen-/Abdunkel-Lage (Farbe und Deckkraft aus den Kurven, 0 ohne Bannart; kein SetAlpha danach)
    local js = 0
    for i = 1, inkState.n do
        if inkState.kinds[i] == "secret" and js < #fx.tintS then
            js = js + 1
            local tc, dk = inkState.colors[i], inkState.darkCols and inkState.darkCols[js]
            local t, d = fx.tintS[js], fx.darkS[js]
            local ok = pcall(function() t:SetVertexColor(tc:GetRGBA()) end)
            if not ok then ok = pcall(function() t:SetVertexColor(tc.r, tc.g, tc.b, tc.a) end) end
            if ok then t:Show() else t:Hide() end
            if dk and pcall(function() d:SetVertexColor(dk:GetRGBA()) end) then d:Show() else d:Hide() end
        end
    end
    for i = js + 1, #fx.tintS do
        fx.tintS[i]:Hide()
        fx.darkS[i]:Hide()
    end
    fx.secretN = js
    -- Rahmen-Ebenen (Kampf, Bannart secret): Blizzards Rahmenbild, nur Farbe (keine Abdunklung, Blasen oder Zusatz-Lage)
    local jb, BD = 0, ns.LiquidBorder
    if BD and #fx.borderL > 0 then
        local strip = BD.Strip()
        if strip ~= fx.borderStrip then Fx.LayoutBorder(lb) end -- Ausschnitt neu gemessen
        for i = 1, inkState.n do
            if inkState.kinds[i] == "border" and jb < #fx.borderL then
                jb = jb + 1
                local okP, painted = pcall(BD.Paint, fx.borderL[jb], inkState.colors[i], strip)
                if not (okP and painted) then BD.Hide(fx.borderL[jb]) end
            end
        end
        for i = jb + 1, #fx.borderL do BD.Hide(fx.borderL[i]) end
    end
    fx.borderN = jb
    if inkState.n > 0 and kind == "border" then
        if fx.tintSecret then fx.tint:Hide() end
        fx.tintSecret, fx.tintTarget = false, nil -- eigene Palette blendet aus
    elseif inkState.n > 0 and kind == "secret" and col then
        if not fx.tintSecret then fx.tint:Hide() end
        fx.tintSecret, fx.tintTarget = js > 0, nil
    elseif inkState.n > 0 and col then
        if fx.tintSecret then fx.tintA = 0 end
        fx.tintSecret, fx.tintTarget = false, col
    else
        if fx.tintSecret then fx.tint:Hide() end
        fx.tintSecret, fx.tintTarget = false, nil
    end
    -- Gift-Blasen: lesbar bei jeder Gift-Aura; secret: Blase i bekommt die Gift-Kurvenfarbe der secret Aura (i mod Anzahl),
    -- nur die der Gift-Aura sind sichtbar (sonst Alpha 0)
    local PC = Fx.INK.poison.color
    local pcs = inkState.poisonCols or {}
    if inkState.poison then
        for i = 1, #fx.pB do fx.pB[i]:SetVertexColor(PC[1], PC[2], PC[3], 1) end
        fx.pWant = true
    elseif js > 0 and #pcs > 0 then
        local ok = false
        for i = 1, #fx.pB do
            local t, pc = fx.pB[i], pcs[(i - 1) % #pcs + 1]
            if pc and pcall(function() t:SetVertexColor(pc:GetRGBA()) end) then ok = true
            else pcall(t.SetVertexColor, t, 0, 0, 0, 0) end
        end
        fx.pWant = ok
    else
        fx.pWant = false
    end
    local ex = inkState.n > 0 and Fx.INK.extra[kind] or nil
    if ex ~= fx.extraKind or (ex and kind ~= fx.extraFor) then
        fx.extraKind, fx.extraFor = ex, ex and kind or nil
        if ex then
            fx.extra:SetTexture(Fx.TEX[ex], "REPEAT", "REPEAT")
            local c = col
            fx.extra:SetVertexColor(0.5 + 0.5 * c[1], 0.5 + 0.5 * c[2], 0.5 + 0.5 * c[3])
        else
            fx.extra:Hide()
        end
    end
    fx.busy = true
    if ns.Liquid.Wake then ns.Liquid.Wake() end
end

function Fx.DebuffState() return inkState end

local testUntil = 0 -- Ende der Test-Schlieren (GetTime); ein spaeter gestarteter Test verlaengert, kein Timer-Abbruch noetig
local function endTestDebuffs()
    if now() < testUntil - 0.01 then return end -- ein neuerer Test laeuft noch
    testUntil = 0
    Fx.SetTestDebuffs({})
    if debuffOn then pcall(Fx.ScanDebuffs) end
end

function Fx.TestDebuffsActive() return now() < testUntil end

--- /vials test <bannart>: Schlieren ohne echten Debuff fuer INK.testSecs s (leere Liste = sofort beenden)
function Fx.TestDebuffs(list)
    if #list == 0 then
        testUntil = 0
        endTestDebuffs()
        return
    end
    testUntil = now() + Fx.INK.testSecs
    Fx.SetTestDebuffs(list)
    C_Timer.After(Fx.INK.testSecs, endTestDebuffs)
end

local auraFrame, scanQueued, blizzHooked = nil, false, false
local function runScan()
    scanQueued = false
    if debuffOn then pcall(Fx.ScanDebuffs) end
end
local function onAura(_, event, unit)
    -- Kampfende: die Bannart ist wieder lesbar => sofort echte Farbe (sonst erst beim naechsten UNIT_AURA)
    if event == "PLAYER_REGEN_ENABLED" then unit = "player" end
    if unit ~= "player" or scanQueued or not debuffOn then return end
    scanQueued = true
    C_Timer.After(Fx.INK.debounce, runScan)
end

--- UNIT_AURA (Spieler) nur, solange eine Roehre Schlieren zeigt
function Fx.UpdateDebuffListening()
    local want = false
    for lb in pairs(tubes) do
        if lb.fx and lb.fx.debuffs then want = true end
    end
    if want == debuffOn then return end
    debuffOn = want
    if not auraFrame then
        auraFrame = CreateFrame("Frame")
        auraFrame:SetScript("OnEvent", onAura)
    end
    if want then
        if not pcall(auraFrame.RegisterUnitEvent, auraFrame, "UNIT_AURA", "player") then
            pcall(auraFrame.RegisterEvent, auraFrame, "UNIT_AURA")
        end
        pcall(auraFrame.RegisterEvent, auraFrame, "PLAYER_REGEN_ENABLED")
        -- nach Blizzards Debuff-Leiste neu lesen (Rueckfall-Quelle im Kampf ist erst danach aktuell); Nach-Haken, einmal
        local df = _G.DebuffFrame
        if not blizzHooked and type(df) == "table" and type(hooksecurefunc) == "function" and type(df.UpdateAuras) == "function" then
            blizzHooked = pcall(hooksecurefunc, df, "UpdateAuras", function() onAura(nil, nil, "player") end)
        end
        pcall(Fx.ScanDebuffs)
    else
        pcall(auraFrame.UnregisterEvent, auraFrame, "UNIT_AURA")
        pcall(auraFrame.UnregisterEvent, auraFrame, "PLAYER_REGEN_ENABLED")
        inkState.n = 0
    end
end
function Fx.IsListeningAuras() return debuffOn end

-- Bild ------------------------------------------------------------------------------------------------------------------------
local function env(age, dur) -- schneller Anstieg, weiches Abklingen (0..1)
    if age < 0 or age >= dur then return 0 end
    local u = age / dur
    local a = u < 0.12 and u / 0.12 or 1
    local b = 1 - u
    return a * b * b * (3 - 2 * b)
end

local function stepHeal(lb, fx, t, h)
    local H = Fx.HEAL
    local busy = false
    if fx.glowT then
        local age = t - fx.glowT
        if age >= H.dur then
            fx.glowT = nil
            fx.glow:Hide()
        else
            local k = 1 - age / H.dur
            local c, g = lb.tint or H.gold, H.gold
            local m = k * k -- erst Gold, dann Fluessigkeitsfarbe
            fx.glow:SetVertexColor(c[1] + (g[1] - c[1]) * m, c[2] + (g[2] - c[2]) * m, c[3] + (g[3] - c[3]) * m)
            fx.glow:SetAlpha(fx.glowAmp * k)
            fx.glow:Show()
            busy = true
        end
    end
    if fx.healT then
        local age = t - fx.healT
        local st = fx.healAmp
        if age >= math.max(H.sweepT, H.starT, H.dur) then
            fx.healT = nil
            fx.sweep:Hide()
            fx.spark:Hide()
            fx.star:Hide()
        else
            local anchor = fx.oldTex or fx.old
            local u = age / H.sweepT
            if u < 1 then
                fx.sweep:ClearAllPoints()
                fx.sweep:SetPoint("LEFT", anchor, "RIGHT", u * H.sweepRun * (lb.w or 100) - 0.3 * H.sweepW * h, -fx.top / 2)
                fx.sweep:SetAlpha(math.min(1, H.sweepA * st * math.sin(math.pi * u)))
                fx.sweep:Show()
            else
                fx.sweep:Hide()
            end
            local sp = age / H.dur
            fx.spark:ClearAllPoints()
            fx.spark:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, sp * H.sparkRise * h)
            fx.spark:SetAlpha(math.min(1, H.sparkA * st * env(age, H.dur)))
            fx.spark:Show()
            local su = age / H.starT
            if su < 1 then
                local s = H.starSize * h * (0.55 + 0.6 * su) * (st > 1 and 1.15 or 1)
                fx.star:SetSize(s, s)
                fx.star:SetAlpha(math.min(1, H.starA * st * env(age, H.starT)))
                if fx.star.SetRotation then pcall(fx.star.SetRotation, fx.star, su * 0.6) end
                fx.star:Show()
            else
                fx.star:Hide()
            end
            busy = true
        end
    end
    return busy
end

-- Rahmen-Puls: Bronze-Rahmen kurz rot (k 0..1); k = 0 stellt zurueck
local function tintFrame(lb, k)
    if not lb.left then return end
    local K = Fx.HIT
    local g, b = 1 - K.frame * k, 1 - K.frame * 1.1 * k
    for _, t in ipairs(lb.frameTex) do t:SetVertexColor(1, g, b) end
end

local function hideHit(lb, fx)
    for _, t in ipairs({ fx.flash, fx.splash, fx.core, fx.halo, fx.pulse }) do t:Hide() end
    for _, t in ipairs(fx.sparks) do t:Hide() end
    if fx.burn then fx.burn:Hide() end
    if fx.framed then
        fx.framed = false
        tintFrame(lb, 0)
    end
    if ns.Liquid.Nudge then ns.Liquid.Nudge(lb, 0, 0) end
end

-- Aufblitz, Funken, Puls (der Moment des Treffers)
local function stepImpact(lb, fx, age, st, h, dt)
    local K = Fx.HIT
    local ec, eh = env(age, K.coreT), env(age, K.haloT)
    if ec > 0 then
        local s = K.coreSize * h * (0.7 + 0.6 * age / K.coreT) * (st > 1 and 1.2 or 1)
        fx.core:SetSize(s, s)
        fx.core:SetAlpha(math.min(1, K.coreA * ec))
        fx.core:Show()
    else
        fx.core:Hide()
    end
    if eh > 0 then
        local s = K.haloSize * h * (0.6 + 0.6 * age / K.haloT) * (st > 1 and 1.25 or 1)
        fx.halo:SetSize(s, s)
        fx.halo:SetAlpha(math.min(1, K.haloA * eh * math.min(1.3, st)))
        fx.halo:Show()
    else
        fx.halo:Hide()
    end
    local ep = env(age, K.pulseT)
    if ep > 0 then
        fx.pulse:SetAlpha(K.pulseA * ep * math.min(1.4, st))
        fx.pulse:Show()
        fx.framed = true
        tintFrame(lb, ep * math.min(1, st))
    else
        fx.pulse:Hide()
        if fx.framed then
            fx.framed = false
            tintFrame(lb, 0)
        end
    end
    local sa = 1 - age / K.sparkT
    local fill = lb.barTex or lb.root
    for i = 1, fx.spN or 0 do
        local sp = fx.sparks[i]
        if sa > 0 then
            fx.spVY[i] = fx.spVY[i] - K.sparkG * h * dt
            fx.spX[i] = fx.spX[i] + fx.spVX[i] * dt
            fx.spY[i] = fx.spY[i] + fx.spVY[i] * dt
            local sz = K.sparkSize * h * (0.6 + 0.4 * sa)
            sp:SetSize(sz, sz)
            sp:ClearAllPoints()
            sp:SetPoint("CENTER", fill, "RIGHT", fx.spX[i], fx.spY[i] - (fx.top or 0) / 2)
            sp:SetAlpha(sa * sa)
            sp:Show()
        else
            sp:Hide()
        end
    end
end

-- Glut-Abbrand im verlorenen Abschnitt (lb.glow: nur rechts vom Fuellungsende, blendet mit der Schadensspur aus)
local function stepBurn(fx, age, st, t)
    local K = Fx.HIT
    if not fx.burn then return end
    if age >= K.burnT then
        fx.burn:Hide()
        return
    end
    local a = (age < 0.08 and age / 0.08 or math.exp(-(age - 0.08) / K.burnTau) * 0.75 + 0.25 * (1 - age / K.burnT))
    local fl = 1 - K.burnFlicker * 0.15 * (math.sin(t * 37) * 0.5 + math.sin(t * 23 + 1.3) * 0.5)
    fx.burn:SetAlpha(math.min(1, K.burnA * a * fl * math.min(1.2, st)))
    local v = -t * 0.9 -- Hitze steigt
    local u = 0.03 * math.sin(t * 11)
    fx.burn:SetTexCoord(u, u + 0.5, v, v + 0.6)
    fx.burn:Show()
end

local function stepHit(lb, fx, t, h, dt)
    local K = Fx.HIT
    if not fx.hitT then return false end
    local age = t - fx.hitT
    local st = fx.hitAmp
    if age >= K.dur then
        fx.hitT = nil
        hideHit(lb, fx)
        return false
    end
    stepImpact(lb, fx, age, st, h, dt)
    stepBurn(fx, age, st, t)
    local e = env(age, K.flashT)
    if e > 0 then
        fx.flash:SetAlpha(math.min(1, K.flashA * st * e))
        local u = age / K.flashT
        fx.flash:SetTexCoord(0.08 * u, 1 + 0.08 * u, 0, 1) -- Blitz zieht leicht mit
        fx.flash:Show()
    else
        fx.flash:Hide()
    end
    local es = env(age, K.splashT)
    if es > 0 then
        local u = age / K.splashT
        fx.splash:SetSize(K.splashW * h * math.min(1.3, st), K.splashH * h * (0.6 + 0.5 * u) * math.min(1.3, st))
        fx.splash:SetAlpha(math.min(1, K.splashA * es))
        local c = lb.tint or WHITE
        fx.splash:SetVertexColor(0.5 + 0.5 * c[1], 0.5 + 0.5 * c[2], 0.5 + 0.5 * c[3])
        fx.splash:Show()
    else
        fx.splash:Hide()
    end
    local amp = K.shakePx * st * math.exp(-age / K.shakeTau)
    if amp > 0.05 then
        local ph = age * K.shakeHz * 2 * math.pi
        if ns.Liquid.Nudge then ns.Liquid.Nudge(lb, amp * math.sin(ph), amp * 0.6 * math.cos(ph * 1.3)) end
    elseif ns.Liquid.Nudge then
        ns.Liquid.Nudge(lb, 0, 0)
    end
    return true
end

--- Lichtband der Kolben-Kammer in die Statusfarbe mischen (k 0..1, nur lesbare Zahlen; k = 0 stellt zurueck). Liquid
--- liest lb.glowR/G/B beim naechsten Zeichnen (pDirty); setzt Liquid.SetTint neu, wird die Basis neu gemerkt.
function Fx.GlowOverride(lb, col, k)
    if not lb.fxGlowBase or lb.glowR ~= lb.fxGlowSet then
        if k <= 0 and not lb.fxGlowBase then return end
        lb.fxGlowBase = lb.fxGlowBase or {}
        local b = lb.fxGlowBase
        b[1], b[2], b[3] = lb.glowR or 1, lb.glowG or 1, lb.glowB or 1
    end
    local b = lb.fxGlowBase
    if k <= 0 or not col then
        lb.glowR, lb.glowG, lb.glowB = b[1], b[2], b[3]
        lb.fxGlowBase, lb.fxGlowSet = nil, nil
    else
        lb.glowR = b[1] + (col[1] - b[1]) * k
        lb.glowG = b[2] + (col[2] - b[2]) * k
        lb.glowB = b[3] + (col[3] - b[3]) * k
        lb.fxGlowSet = lb.glowR
    end
    lb.pDirty = true
end

-- Gift-Blasen: steigen langsam, wackeln, platzen an der Oberflaeche; Frame pulsiert kraenklich
local function stepPoison(lb, fx, t, dt)
    local PO = Fx.INK.poison
    local a = fx.pA
    if fx.pWant then a = math.min(1, a + dt * 1.5) else a = math.max(0, a - dt * 1.5) end
    fx.pA = a
    local any = false
    local h, w = lb.h or 10, lb.w or 100
    local top = lb.style == "piston" and ns.Liquid.PISTON.gap * h or 0
    local len = math.min(lb.lenPx or w, w)
    if fx.pWant and t >= fx.pNext then
        fx.pNext = t + PO.every * (0.6 + 0.8 * math.random())
        for i = 1, #fx.pB do
            if not fx.pOn[i] then
                local r = math.random()
                fx.pOn[i], fx.pPop[i], fx.pPh[i] = true, nil, math.random() * 6.28
                fx.pS[i] = PO.sizeMin + (PO.sizeMax - PO.sizeMin) * r
                fx.pX[i] = (0.04 + 0.92 * math.random()) * len
                fx.pY[i] = -h + fx.pS[i] * 0.6
                fx.pV[i] = (h - top) / (PO.riseMin + (PO.riseMax - PO.riseMin) * (1 - r))
                local tex = fx.pB[i]
                tex:SetTexture(Fx.TEX.pBubble)
                local c = math.random(5)
                tex:SetTexCoord((c - 1) / 8, c / 8, 0, 1)
                tex:SetSize(fx.pS[i], fx.pS[i])
                break
            end
        end
    end
    for i = 1, #fx.pB do
        if fx.pOn[i] then
            any = true
            local tex = fx.pB[i]
            if fx.pPop[i] then
                local u = (t - fx.pPop[i]) / PO.popT
                if u >= 1 then
                    fx.pOn[i] = false
                    tex:Hide()
                else
                    local c = math.min(4, math.floor(u * 3) + 2)
                    tex:SetTexCoord((c - 1) / 4, c / 4, 0, 1)
                    local s = fx.pS[i] * (1.3 + 0.6 * u)
                    tex:SetSize(s, s)
                end
            else
                fx.pY[i] = fx.pY[i] + fx.pV[i] * dt
                local x = fx.pX[i] + PO.wobble * math.sin(t * PO.wobbleHz * 6.2832 + fx.pPh[i])
                if fx.pY[i] >= -top - fx.pS[i] * 0.5 then
                    fx.pPop[i] = t
                    tex:SetTexture(Fx.TEX.pPop)
                end
                tex:ClearAllPoints()
                tex:SetPoint("CENTER", lb.root, "TOPLEFT", x, fx.pY[i])
                tex:Show()
            end
        end
    end
    if a > 0 or any then
        -- kraenkliches Pulsieren (Alpha-Zahl nur am eigenen Frame; die Blasenfarbe bleibt, secret oder nicht)
        fx.pFrame:SetAlpha(a * (1 - PO.glowPulse * 0.5 + PO.glowPulse * 0.5 * math.sin(t * PO.pulseHz * 6.2832)))
        if not fx.pFrame:IsShown() then fx.pFrame:Show() end
        return true
    end
    if fx.pFrame:IsShown() then fx.pFrame:Hide() end
    return false
end

-- Toenung der ganzen Fluessigkeit (lesbar: weich ueberblenden, Fluch flackert, Gift pulsiert) und Zusatz-Lage; secret: Drift
local function stepTint(lb, fx, t, dt)
    local I = Fx.INK
    local tex = fx.tint
    local busy = false
    if fx.tintSecret or fx.tintTarget or fx.tintA > 0 or (fx.secretN or 0) > 0 then
        local u = (t * I.tintDrift + (lb.phase or 0)) % 1
        tex:SetTexCoord(u, u + (fx.tintTile or 1), 0.004, 0.996)
        for i = 1, fx.secretN or 0 do fx.tintS[i]:SetTexCoord(u, u + (fx.tintTile or 1), 0.004, 0.996) end
        busy = true
    end
    if not fx.tintSecret then
        local tgt = fx.tintTarget
        local a = fx.tintA
        if tgt then a = math.min(1, a + dt * I.tintFade) else a = math.max(0, a - dt * I.tintFade) end
        fx.tintA = a
        if a > 0 then
            if tgt then
                local k = math.min(1, dt * I.tintFade * 1.5)
                fx.tR, fx.tG, fx.tB = fx.tR + (tgt[1] - fx.tR) * k, fx.tG + (tgt[2] - fx.tG) * k, fx.tB + (tgt[3] - fx.tB) * k
            end
            local fl = 1
            local kind = inkState.kinds[1]
            if kind == "Curse" and tgt then
                fl = 1 - I.flicker * (0.5 + 0.5 * math.sin(t * 13.7) * math.sin(t * 5.3 + 1.1))
            elseif kind == "Poison" and tgt then -- Gift: langsames kraenkliches Pulsieren der Truebung
                fl = 1 - I.poison.pulse * (0.5 + 0.5 * math.sin(t * I.poison.pulseHz * 6.2832))
            end
            if tgt then fx.tKind = kind end
            local ta = I.tintA[fx.tKind] or I.secretA
            tex:SetVertexColor(fx.tR, fx.tG, fx.tB)
            tex:SetAlpha(math.min(1, ta * a * fl))
            tex:Show()
            lb.bodyDim = 1 - (1 - (I.dim[fx.tKind] or I.secretDim)) * a -- Koerper abdunkeln (Liquid stepBody)
            Fx.GlowOverride(lb, I.glow[fx.tKind], I.glowMix * a)
            busy = true
        else
            if tex:IsShown() then tex:Hide() end
            lb.bodyDim = nil
            if lb.fxGlowBase then Fx.GlowOverride(lb, nil, 0) end
        end
    else
        lb.bodyDim = nil -- secret: Deckkraft unbekannt (Auren ohne Bannart => Kurven-Alpha 0), Koerper nicht abdunkeln
    end
    local ex = fx.extraKind
    if ex and (fx.tintA > 0 or fx.tintSecret) then
        local tile = fx.inkTile * 3
        if ex == "rise" then
            local v = (t * I.riseSpeed) % 1
            fx.extra:SetTexCoord(0, tile, v, v + 0.6)
            fx.extra:SetAlpha(I.extraA * math.max(fx.tintA, fx.tintSecret and 1 or 0))
        else
            local u = (t * 0.01) % 1
            fx.extra:SetTexCoord(u, u + tile, 0, 1)
            fx.extra:SetAlpha(I.extraA * (0.55 + 0.45 * math.sin(t * 4.1)) * math.max(fx.tintA, fx.tintSecret and 1 or 0))
        end
        fx.extra:Show()
        busy = true
    end
    return busy
end

--- Ein Bild (aus Liquid.Step). Ruhe: sofort zurueck, keine Setter. Gerechnet wird mit GetTime (dieselbe Uhr wie die
--- Ausloeser); die Treiberzeit wird nur fuer UV-Laeufe nicht gebraucht.
function Fx.Step(lb)
    local fx = lb.fx
    if not fx or not fx.busy then return end
    local t = now()
    local dt = t - (fx.lastT or t)
    fx.lastT = t
    if dt > 0.1 then dt = 0.1 elseif dt < 0 then dt = 0 end
    local h = lb.h or 10
    local b1 = fx.on and stepHeal(lb, fx, t, h) or false
    local b2 = fx.on and stepHit(lb, fx, t, h, dt) or false
    local b3 = fx.fizz and ns.LiquidFizz.Step(lb, t, dt) or false
    local b4 = fx.debuffs and stepTint(lb, fx, t, dt) or false
    if fx.debuffs and stepPoison(lb, fx, t, dt) then b4 = true end
    fx.busy = b1 or b2 or b3 or b4
    if not fx.busy then fx.lastT = nil end
end

function Fx.IsBusy(lb) return lb.fx ~= nil and lb.fx.busy == true end

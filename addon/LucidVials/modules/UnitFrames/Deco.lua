-- Einheitenrahmen: Zier am Portraet (Delta "Fluessiges Leben", Ziel-Portraet Variante A). Ergaenzt Skin.lua ueber die
-- Haken Skin.Deco.Build/Layout/Refresh/UpdateLevel/HideBlizzard/Remove; nur eigene Texturen/Frames, an Blizzard-Teilen
-- nur SetAlpha (ueber Skin.HideRegion, beim Ausschalten zurueck auf 1).
--   * Roehrenenden (alle Rahmen): die Glasroehren enden aussen am Portraetring statt unter dem Portraet (Blizzards Balken
--     reichen beim Ziel bis unter das Portraet). Aus den Bildschirm-Rechtecken von Balken und Portraet: Ende gerade im
--     Ringband: ringseitig offen (gerade, ohne Kapsel-Rundung und Endkappe, Liquid.SetOpenEnd), Ring liegt darueber.
--     Spieler und Ziel: statt uf-ring der Ring mit Rohraufnahmen (Skin.SOCKET, Gemini-Bogen sheet-ring-aufnahme-v3.jpg;
--     Ringkreis deckungsgleich mit uf-ring, Spieler gespiegelt): je Roehre Manschette -> offenes Fenster -> Sockel. Die
--     Roehre wird senkrecht auf ihr Fenster gerueckt (Liquid.SetEnds dy) und endet verdeckt im Sockel. Liegt eine Roehre zu
--     weit neben ihrem Fenster (fremder Aufbau), bleibt es beim schlichten uf-ring. Rechtecke unlesbar => wie bisher.
--   * Klassifikation (Ziel): Elite = Gold-Drache, Rar = Silber-Drache, Rar-Elite = Silber-Gold-Drache, Weltboss/Boss/Stufe
--     ?? = Boss-Kamm (Hoerner + Totenkopf; bei ?? Totenkopf statt Zahl). Lucids uf-ring bleibt; jedes Teil liegt in zwei
--     Lagen: hinten (unter dem Ring: Fluegel, Kopf, Schwanz) und vorn (ueber dem Ring: Krallen/Hals; der eigene Ring des
--     Teils ist per radialer Maske entfernt, scripts/gen-unitframe-media.mjs decoImages). Boss: hinten die Hoerner (Ansatz
--     unter dem Ring), vorn nur der Totenkopf unten mittig ueber dem Ringband (bossImages, ohne seitliche Dornen).
--   * Raidmarker oben auf dem Ring (grosse Fassung), Quest-Symbol oben aussen (kleine Fassung; Boss: rechts zwischen Horn
--     und Plakette) - dieselben Symbole wie an
--     den Plaketten (Style.QuestSymbol: Questie zuerst, sonst "!" ueber C_QuestLog). Zeigt Lucid ein Questie-Symbol,
--     wird Questies eigenes Symbol am Zielrahmen (profile.nameplateTargetFrameEnabled) per SetAlpha(0) verborgen.
--   * Stufen-Plakette mit Edelstein in Schwierigkeitsfarbe (nur angreifbare Ziele, sonst neutral).
--   * Auren: eigener CustomAuraContainer (Blizzard rechnet secret intern), runde Fassungen in je einer Reihe Debuffs und
--     Buffs unter den Roehren; fehlt die Vorlage, bleiben Blizzards Auren sichtbar. Groesse: unitframes.auraSize (Standard 22,
--     14-36, /vials auren), wirkt sofort (vorhandene Knoepfe werden umdimensioniert).
-- /vials test ziel <art> zeigt die Zier ohne passendes Ziel (am Ziel bzw. an einem eigenen Testrahmen).
-- Mini-Vorschau (Preview.lua, sk.preview): Ziel-Art je Instanz (sk.previewKind statt des modulglobalen S.test), ohne Auren,
-- Raidmarker und Quest-Symbol, Stufe aus sk.previewLevel; echte Ziele und Questie bleiben unberuehrt.
local _, ns = ...
local Compat, L = ns.Compat, ns.L
local Style, Liquid = ns.Style, ns.Liquid
local Skin = ns.UnitFrameSkin

local Deco = {}
ns.UnitFrameDeco = Deco
Skin.Deco = Deco

local MEDIA = "Interface\\AddOns\\LucidVials\\Media\\"
-- Lagen aus scripts/gen-unitframe-media.mjs zielMeasurements() (der Test vergleicht): Ringmitte (cx, cy) der Hinterlage
-- je Art (tall = Vorderlage im Rahmen der Hinterlage statt quadratisch um die Ringmitte), Plakette (Scheibenmitte/-radius,
-- Stein-Fassung), Innenflaeche der Fassungen
Deco.GEO = { rin = 76, backW = 256, backH = 512, front = 256,
    elite = { cx = 0.4099, cy = 0.4926 }, rare = { cx = 0.4291, cy = 0.4914 },
    rareelite = { cx = 0.4234, cy = 0.4707 }, boss = { cx = 0.5025, cy = 0.5097, tall = true },
    level = { cx = 0.5, cy = 0.469, r = 0.4592, gx = 0.4991, gy = 0.8723 },
    aura = { inner = 0.7075 }, marker = { inner = 0.5729 },
    socket = { cx = 0.5512, cy = 0.4992, size = 1.0967, inner = 0.7837, outer = 0.9932,
        health = { top = 0.3678, bot = -0.2368, rimTop = 0.3918, rimBot = -0.2608, cuff = -1.1991, win = -1.1403,
            sock = -0.9867, endX = -0.8734 },
        power = { top = -0.3544, bot = -0.6519, rimTop = -0.3328, rimBot = -0.6759, cuff = -1.2003, win = -1.1403,
            sock = -0.9867, endX = -0.8296 } } }
-- uf-ring: Innen-/Aussenradius als Anteil des halben Durchmessers (Innen = ringInner der Messung, Aussen gemessen)
Deco.RING = { inner = 0.7925, outer = 0.9844 }
Deco.KIND_TEX = { elite = MEDIA .. "uf-ziel-elite", rare = MEDIA .. "uf-ziel-rare",
    rareelite = MEDIA .. "uf-ziel-rareelite", boss = MEDIA .. "uf-ziel-boss" }
Deco.TEX = { marker = MEDIA .. "uf-ziel-marker", markerSmall = MEDIA .. "uf-ziel-marker-small", gem = MEDIA .. "uf-ziel-gem",
    aura = MEDIA .. "uf-ziel-aura", level = MEDIA .. "uf-ziel-level",
    raid = "Interface\\TargetingFrame\\UI-RaidTargetingIcons", mask = "Interface\\CharacterFrame\\TempPortraitAlphaMask" }
Skin.PLATE_TEX.badge = Deco.TEX.level
Skin.PLATE.badge = 0.46
-- UnitClassification -> Zier
Deco.CLASS = { elite = "elite", rare = "rare", rareelite = "rareelite", worldboss = "boss" }
-- Lage (Anteile des Ring-Aussendurchmessers bzw. der Plakette); Winkel in Grad gegen den Uhrzeigersinn ab rechts
-- questAngleKind: eigener Platz je Zier (Boss: zwischen rechtem Horn und Stufen-Plakette, nicht auf dem Horn)
Deco.LAYOUT = { marker = 0.32, markerAngle = 90, raidIcon = 1.15, quest = 0.26, questAngle = 36, questIcon = 0.66,
    questAngleKind = { boss = 10 }, gem = 0.2, skull = 0.52, levelFont = 0.4 }
Deco.GEM_NEUTRAL = { 0.80, 0.76, 0.70 }
Deco.GEM_TEST = { 1.0, 0.50, 0.25 }
-- Auren: Symbolgroesse aus dem Profil (unitframes.auraSize, Skin.AURA_SIZE); gap/rowGap gelten bei refSize und wachsen
-- proportional mit. Abstand unter der Roehre, Anteil der Innenflaeche fuers Symbol
Deco.AURA = { refSize = 18, gap = 2, rowGap = 3, top = 3, iconFill = 1.04, perRowMax = 12 }
-- Ring mit Rohraufnahmen (uf-ring-aufnahme, 512 x 512; Lage in GEO.socket aus scripts/gen-unitframe-media.mjs
-- socketGeometry: Ringmitte cx/cy und Texturbreite size x Ring-Durchmesser; je Roehre Fenster-Innenkanten top/bot, Haarlinien
-- rimTop/rimBot, Manschette cuff, Fensterbeginn win, Sockelbeginn sock, Roehrenende endX - Anteile des halben Ring-
-- Durchmessers zur Ringmitte, Ring rechts wie am Ziel). ids = Rahmen mit Aufnahmen; maxDy = groesster senkrechter Versatz
-- (Anteil des halben Durchmessers), um den eine Roehre auf ihr Fenster gerueckt wird - mehr => schlichter uf-ring.
Skin.SOCKET = { path = MEDIA .. "uf-ring-aufnahme", ids = { player = true, target = true }, maxDy = 0.2 }
Deco.ENDS_INSET = 0.02    -- Abstand der geraden Kante zum Ring-Innenrand (Anteil des Ringradius), nie ins Portraet
Deco.ENDS_MAX = 80        -- groesster Versatz eines Roehrenendes (UI); groesser = unbekannter Aufbau, nichts verschieben
Deco.ENDS_RETRY = 0.5     -- s, erneuter Versuch, wenn die Rechtecke noch nicht lesbar sind (hoechstens ENDS_TRIES)
Deco.ENDS_TRIES = 4
Deco.QUEST_DELAY, Deco.QUESTIE_RECHECK = 0.3, 0.05
Deco.TEST_ARGS = { elite = "elite", rare = "rare", rareelite = "rareelite", boss = "boss", normal = "normal",
    aus = "off", off = "off" }
Deco.TEST_FRAME = { x = 260, y = 120, w = 170, h = 120 }

local S = { test = nil, tf = nil, errors = {}, errorCount = 0, questPending = false, questieHooked = false,
    questieHidden = setmetatable({}, { __mode = "k" }), questieHiddenN = 0, auraInitFail = false,
    auraFrames = setmetatable({}, { __mode = "k" }) } -- Aura-Knoepfe -> { icon, count } (zum Umdimensionieren)

-- Hilfen ----------------------------------------------------------------------------------------------------------------
local function field(t, key)
    if type(t) ~= "table" or Compat.IsSecret(t) then return nil end
    local ok, v = pcall(function() return t[key] end)
    if ok and not Compat.IsSecret(v) then return v end
    return nil
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

local function recordError(err)
    S.errorCount = S.errorCount + 1
    S.errors[#S.errors + 1] = string.sub(tostring(err), 1, 160)
    while #S.errors > 3 do table.remove(S.errors, 1) end
end

local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then recordError(err) end
    return ok
end

--- weiche Kanten: kein Einrasten aufs Pixelraster (Zier wird frei skaliert)
local function free(t)
    if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, false) end
    if t.SetTexelSnappingBias then pcall(t.SetTexelSnappingBias, t, 0) end
    return t
end

local function newTex(frame, layer, path, sub)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    if path then t:SetTexture(path) end
    free(t)
    t:Hide()
    return t
end

--- effektive Skalierung (Texturen: die ihres Elternframes)
local function eff(obj)
    local s = num(obj, "GetEffectiveScale")
    if s and s > 0 then return s end
    local ok, p = call(obj, "GetParent")
    s = ok and num(p, "GetEffectiveScale") or nil
    return (s and s > 0) and s or nil
end

local function center(obj)
    local ok, x, y = call(obj, "GetCenter")
    if not ok then return nil end
    return Compat.Num(x), Compat.Num(y)
end

-- Roehrenenden + Rohraufnahmen ----------------------------------------------------------------------------------------------
--- Bildschirm-Lage einer Roehre zum Ring: Kanten des Balkens, Ringmitte, Roehrenmitte ohne eigenen Hoehenversatz (endDy)
--- relativ zur Ringmitte, halber Ring-Durchmesser (alles Bildschirm-Pixel). nil = Rechtecke unlesbar.
local function tubeRect(sk, lb, region)
    local effR, effP, effH = eff(region), eff(sk.anchor), eff(sk.holder)
    local l, r = num(region, "GetLeft"), num(region, "GetRight")
    local _, ry = center(region)
    local px, py = center(sk.anchor)
    if not (effR and effP and effH and l and r and ry and px and py and sk.ringSize) then return nil end
    local ringY = py * effP
    return { effR = effR, effH = effH, l = l * effR, r = r * effR, ringX = px * effP,
        yc = (ry + (lb.regionDy or 0) - (lb.endDy or 0)) * effR - ringY, half = sk.ringSize / 2 * effH }
end

--- Versatz der portraetseitigen Roehrenkante (UI des Balkens), wenn sie dEnd (Bildschirm-Pixel) vor der Ringmitte endet
local function endShift(t, dEnd, mirrored)
    local shift
    if mirrored then
        shift = ((t.ringX - dEnd) - t.r) / t.effR
    else
        shift = ((t.ringX + dEnd) - t.l) / t.effR
    end
    if shift ~= shift or math.abs(shift) > Deco.ENDS_MAX then return nil end
    return shift
end

--- schlichter Ring: Versatz der Roehrenkante und Ring-Aussenpunkt (UI des Holders); nil = unplausibel; 0 = Roehre laeuft
--- am Ring vorbei (rund).
local function bandEnd(t, lb, mirrored)
    local R = Deco.RING
    local yc, half = t.yc, t.half
    local rIn, rMid, rOut = half * R.inner, half * (R.inner + R.outer) / 2, half * R.outer
    if math.abs(yc) >= rMid then return 0 end
    -- gerade Kante des Rahmens (Hoehe hf x 2) muss in jeder Zeile unter dem Ringband liegen: nicht ins Portraet (lo),
    -- moeglichst nicht ueber den Ring hinaus (hi); passt beides nicht, gewinnt das Portraet
    local pad = lb.pad or {}
    local hf = ((lb.h or 10) + (pad.top or 0) + (pad.bottom or 0)) / 2 * t.effR
    local y0, y1 = yc - hf, yc + hf
    local yMin = (y0 <= 0 and y1 >= 0) and 0 or math.min(math.abs(y0), math.abs(y1))
    local yMax = math.max(math.abs(y0), math.abs(y1))
    local lo = math.sqrt(math.max(0, rIn * rIn - yMin * yMin)) + Deco.ENDS_INSET * half
    local hi = math.sqrt(math.max(0, rOut * rOut - yMax * yMax))
    local shift = endShift(t, lo <= hi and (lo + hi) / 2 or lo, mirrored)
    if shift == nil then return nil end
    return shift, true
end

--- Ring mit Aufnahmen: senkrechter Versatz (UI des Balkens) auf die Fenstermitte und Versatz der Roehrenkante (Ende im
--- Sockel); nil = Roehre liegt zu weit neben ihrem Fenster bzw. unplausibel.
local function socketEnd(t, key, mirrored)
    local W = Deco.GEO.socket[key]
    local d = (W.top + W.bot) / 2 * t.half - t.yc
    if math.abs(d) > Skin.SOCKET.maxDy * t.half then return nil end
    local shift = endShift(t, -W.endX * t.half, mirrored)
    if shift == nil then return nil end
    return shift, d / t.effR
end

--- Lage der Aufnahmen-Textur zur Ringmitte (UI): Versatz der Texturmitte x/y (y nach oben) und Kantenlaenge; mirrored =
--- Ring links der Roehren (Spieler, Textur gespiegelt)
function Deco.SocketPlace(ringSize, mirrored)
    local G = Deco.GEO.socket
    local size = ringSize * G.size
    local x = (0.5 - G.cx) * size
    return mirrored and -x or x, (G.cy - 0.5) * size, size
end

local function showSocket(sk, on)
    sk.socketOn = on
    if not sk.socket then return end
    if on then
        local spec = Skin.SPEC[sk.id]
        local x, y, size = Deco.SocketPlace(sk.ringSize, not spec.mirrored)
        sk.socket:ClearAllPoints()
        sk.socket:SetPoint("CENTER", sk.ring, "CENTER", x, y)
        sk.socket:SetSize(size, size)
        if spec.mirrored then sk.socket:SetTexCoord(0, 1, 0, 1) else sk.socket:SetTexCoord(1, 0, 0, 1) end
        sk.socket:Show()
        sk.ring:SetAlpha(0) -- bleibt Anker der Zier (Drachen, Marker, Plakette)
    else
        sk.socket:Hide()
        sk.ring:SetAlpha(1)
    end
end

local layoutEnds
local function retryEnds(sk)
    if not (C_Timer and C_Timer.After) or (sk.endsTries or 0) >= Deco.ENDS_TRIES then return end
    sk.endsTries = (sk.endsTries or 0) + 1
    C_Timer.After(Deco.ENDS_RETRY, function()
        if sk.applied and not sk.endsOk then safe(layoutEnds, sk) end
    end)
end

layoutEnds = function(sk)
    if not (sk.health and sk.anchor) then return end
    local spec = Skin.SPEC[sk.id]
    local parts = { { "health", sk.hb, spec.health }, { "power", sk.mb, spec.power } }
    local rects, okAll = {}, true
    for i, part in ipairs(parts) do
        local lb, region = sk[part[1]], part[2]
        if lb and region and lb.geo then rects[i] = tubeRect(sk, lb, region) end
        if not rects[i] then okAll = okAll and not (lb and region and lb.geo) end
    end
    -- Aufnahmen nur, wenn beide Roehren lesbar sind und je auf ihr Fenster passen
    local socket = sk.socket ~= nil and rects[1] ~= nil and rects[2] ~= nil
    local plan = {}
    for i, part in ipairs(parts) do
        local t = rects[i]
        if t then
            local shift, dy
            if socket then shift, dy = socketEnd(t, part[1], spec.mirrored) end
            if shift == nil then socket = false end
            plan[i] = { shift = shift, dy = dy }
        end
    end
    if sk.socket and rects[1] and rects[2] then showSocket(sk, socket) end
    -- aeussere Kapsel-Enden buendig: Blizzards Ressourcenbalken ist am Ziel anders breit/verankert als der Lebensbalken;
    -- die Ressourcenroehre beginnt aussen genau ueber der Lebensroehre (Ziel links, Spieler rechts)
    local outer = 0
    if rects[1] and rects[2] then
        local a, b = rects[1], rects[2]
        outer = (spec.mirrored and (a.l - b.l) or (a.r - b.r)) / b.effR
        if outer ~= outer or math.abs(outer) > Deco.ENDS_MAX then outer = 0 end
    end
    sk.ends = sk.ends or {}
    for i, part in ipairs(parts) do
        local key, fb, t = part[1], part[3], rects[i]
        local lb = sk[key]
        local shift, open, dy
        if t and socket then
            shift, open, dy = plan[i].shift, true, plan[i].dy
        elseif t then
            shift, open = bandEnd(t, lb, spec.mirrored)
            dy = 0
        end
        if shift == nil then
            if lb then Liquid.SetOpenEnd(lb, nil) end -- kein veraltetes offenes Ende stehen lassen
            if t then okAll = false end
        else
            -- ringseitig offen (keine Kapsel-Rundung, keine Endkappe) nur, wenn das Ende unter dem Ring liegt
            Liquid.SetOpenEnd(lb, open and (spec.mirrored and "right" or "left") or nil)
            local o = (i == 2) and outer or 0
            if spec.mirrored then Liquid.SetEnds(lb, o, shift, dy) else Liquid.SetEnds(lb, shift, o, dy) end
            Liquid.Layout(lb, part[2], nil, fb[1], fb[2])
        end
        sk.ends[key] = shift
    end
    sk.endsOk = okAll
    if not okAll then retryEnds(sk) end
end

-- Aufbau ------------------------------------------------------------------------------------------------------------------
--- Symbolgroesse (Profil, nur eigene Zahl) und die mitwachsenden Abstaende zwischen/unter den Symbolen
local function auraMetrics()
    local A, R = Deco.AURA, Skin.AURA_SIZE
    local s = Skin.GetConfig().auraSize
    if type(s) ~= "number" or s < R.min or s > R.max then s = R.default end
    local k = s / A.refSize
    return s, math.max(1, math.floor(A.gap * k + 0.5)), math.max(1, math.floor(A.rowGap * k + 0.5))
end

--- Groesse eines Aura-Knopfes setzen: Knopf, Symbol-Einzug (innerhalb der Fassung), Stapelzahl-Schrift
local function sizeAura(f, parts, s)
    local A, G = Deco.AURA, Deco.GEO
    pcall(f.SetSize, f, s, s)
    local inset = s * (1 - G.aura.inner * A.iconFill) / 2
    local icon = parts.icon
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    if parts.count then Skin.SetFont(parts.count, math.max(7, math.floor(s * 0.5 + 0.5))) end
end

local function initAura(f)
    local icon = f:CreateTexture(nil, "ARTWORK")
    local parts = { icon = icon }
    S.auraFrames[f] = parts
    sizeAura(f, parts, (auraMetrics()))
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if f.CreateMaskTexture then
        local okM, m = pcall(f.CreateMaskTexture, f)
        if okM and m then
            pcall(m.SetTexture, m, Deco.TEX.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(icon)
            pcall(icon.AddMaskTexture, icon, m)
        end
    end
    if not call(f, "SetIcon", icon) then S.auraInitFail = true end -- ohne SetIcon: leere Reihe => Rueckfall auf Blizzard
    local okC, cd = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
    if okC and cd then
        cd:SetAllPoints(icon)
        call(cd, "SetSwipeTexture", Deco.TEX.mask)
        call(cd, "SetUseCircularEdge", true)
        call(cd, "SetDrawEdge", false)
        call(cd, "SetHideCountdownNumbers", true)
        call(cd, "SetReverse", true) -- wie Blizzards Ziel-Auren: neu hell, der Kreis dunkelt zum Ablauf hin ab
        call(f, "SetDurationCooldown", cd)
    end
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints(f)
    top:SetFrameLevel((num(f, "GetFrameLevel") or 1) + 3)
    local ring = top:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(Deco.TEX.aura)
    ring:SetAllPoints(top)
    free(ring)
    local count = top:CreateFontString(nil, "OVERLAY")
    count:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 1, -1)
    parts.count = count
    Skin.SetFont(count, math.max(7, math.floor((auraMetrics()) * 0.5 + 0.5)))
    call(f, "SetApplicationCount", count)
end
Deco.InitAura = initAura

--- Rueckfall: Knoepfe ohne SetIcon (Vorlage anders als erwartet) => eigener Container weg, Blizzards Auren sichtbar
local function auraFallback(sk)
    if sk.auras then pcall(sk.auras.Hide, sk.auras) end
    sk.auras, sk.auraState = nil, "noicon"
    local r = sk.found and sk.found.Auras
    if r and sk.hidden and sk.hidden[r] then Skin.ShowRegion(sk, r) end
end

local function auraLayout(index, newLine)
    local s, gap, rowGap = auraMetrics()
    return { elementSpacing = gap, lineSpacing = rowGap, elementWidth = s, elementHeight = s,
        forceNewLine = newLine, layoutIndex = index }
end

--- eigener Aura-Container (Fallback: ohne Vorlage bleibt alles bei Blizzard)
local function buildAuras(sk)
    sk.auraState = "missing"
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, sk.holder, "CustomAuraContainerTemplate")
    if not ok or type(c) ~= "table" or type(field(c, "AddAuraGroup")) ~= "function" then
        if ok and type(c) == "table" then pcall(c.Hide, c) end
        return
    end
    local sortM, sortD = _G.AuraContainerSortMethod, _G.AuraContainerSortDirection
    local dOpts = { initializeFrame = initAura, maxFrameCount = Deco.AURA.perRowMax, layout = auraLayout(1, false) }
    if type(sortM) == "table" and type(sortD) == "table" and sortM.UnitFrameDebuff and sortD.Normal then
        dOpts.sortMethod, dOpts.sortDirection = sortM.UnitFrameDebuff, sortD.Normal -- eigene Schwaechungen zuerst
    end
    local okU = call(c, "SetUnit", "target")
    local ok1 = call(c, "AddAuraGroup", "debuffs", "HARMFUL", dOpts)
    local ok2 = call(c, "AddAuraGroup", "buffs", "HELPFUL",
        { initializeFrame = initAura, maxFrameCount = Deco.AURA.perRowMax, layout = auraLayout(2, true) })
    if not (okU and ok1 and ok2) then
        pcall(c.Hide, c)
        sk.auraState = "failed"
        return
    end
    sk.auras, sk.auraState, sk.auraHostile, sk.auraSize = c, "ok", true, (auraMetrics())
    if S.auraInitFail then auraFallback(sk) end
end

local function buildTarget(sk)
    sk.zBack = newTex(sk.ringFrame, "BORDER")           -- unter uf-ring (ARTWORK desselben Frames)
    sk.zFront = newTex(sk.deco, "BACKGROUND")           -- ueber dem Ring, unter Plakette und Fassungen
    sk.mSock = newTex(sk.deco, "ARTWORK", Deco.TEX.marker, 1)
    sk.mIcon = newTex(sk.deco, "OVERLAY", Deco.TEX.raid)
    sk.qSock = newTex(sk.deco, "ARTWORK", Deco.TEX.markerSmall, 1)
    sk.qIcon = newTex(sk.deco, "OVERLAY")
    sk.gem = newTex(sk.deco, "ARTWORK", Deco.TEX.gem, 2)
    sk.skull = newTex(sk.deco, "OVERLAY", Style and Style.SKULL_TEX)
end

function Deco.Build(sk)
    -- Ring mit Aufnahmen: im Ring-Frame neben uf-ring (gleiche Ebene ueber den Roehren, Zier-Hinterlage darunter)
    if Skin.SOCKET.ids[sk.id] then sk.socket = newTex(sk.ringFrame, "ARTWORK", Skin.SOCKET.path) end
    if sk.id ~= "target" then return end
    buildTarget(sk)
    if not sk.preview then buildAuras(sk) end -- Vorschau: keine Auren (der Container zeigte die des echten Ziels)
end

-- Lage --------------------------------------------------------------------------------------------------------------------
local function polar(tex, ring, angle, radius, size)
    local a = math.rad(angle)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", ring, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
    tex:SetSize(size, size)
end

--- Quest-Fassung: Platz haengt von der Zier ab (Boss-Hoerner)
local function placeQuest(sk)
    local Lt = Deco.LAYOUT
    local size = sk.ringSize or 72
    local rm = size / 2 * (Deco.RING.inner + Deco.RING.outer) / 2
    local a = (sk.zKind and Lt.questAngleKind[sk.zKind]) or Lt.questAngle
    local qa = Skin.SPEC.target.mirrored and a or (180 - a)
    polar(sk.qSock, sk.ring, qa, rm, size * Lt.quest)
    polar(sk.qIcon, sk.ring, qa, rm, size * Lt.quest * Lt.questIcon)
    sk.qIconSize = size * Lt.quest * Lt.questIcon
end

local function placeKind(sk)
    local kind = sk.zKind
    placeQuest(sk)
    if not kind then
        sk.zBack:Hide()
        sk.zFront:Hide()
        return
    end
    local G, size = Deco.GEO, sk.ringSize or 72
    local k = size / 2 * Deco.RING.inner / G.rin
    local g = G[kind]
    sk.zBack:SetTexture(Deco.KIND_TEX[kind])
    sk.zBack:ClearAllPoints()
    sk.zBack:SetPoint("TOPLEFT", sk.ring, "CENTER", -g.cx * G.backW * k, g.cy * G.backH * k)
    sk.zBack:SetSize(G.backW * k, G.backH * k)
    sk.zFront:SetTexture(Deco.KIND_TEX[kind] .. "-front")
    sk.zFront:ClearAllPoints()
    if g.tall then
        sk.zFront:SetPoint("TOPLEFT", sk.ring, "CENTER", -g.cx * G.backW * k, g.cy * G.backH * k)
        sk.zFront:SetSize(G.backW * k, G.backH * k)
    else
        sk.zFront:SetPoint("CENTER", sk.ring, "CENTER", 0, 0)
        sk.zFront:SetSize(G.front * k, G.front * k)
    end
    sk.zBack:Show()
    sk.zFront:Show()
end

local function layoutTarget(sk)
    local Lt, G = Deco.LAYOUT, Deco.GEO
    local size = sk.ringSize or 72
    local rm = size / 2 * (Deco.RING.inner + Deco.RING.outer) / 2
    polar(sk.mSock, sk.ring, Lt.markerAngle, rm, size * Lt.marker)
    polar(sk.mIcon, sk.ring, Lt.markerAngle, rm, size * Lt.marker * G.marker.inner * Lt.raidIcon)
    placeKind(sk) -- samt Quest-Fassung (Platz je Zier)
    if sk.plate then
        local ps = num(sk.plate, "GetWidth") or (sk.pw or 58) * Skin.PLATE.badge
        local P = G.level
        sk.gem:ClearAllPoints()
        sk.gem:SetPoint("CENTER", sk.plate, "TOPLEFT", P.gx * ps, -P.gy * ps)
        sk.gem:SetSize(ps * Lt.gem, ps * Lt.gem)
        sk.levelText:ClearAllPoints()
        sk.levelText:SetPoint("CENTER", sk.plate, "TOPLEFT", P.cx * ps, -P.cy * ps)
        sk.levelText:SetSize(2 * P.r * ps, 2 * P.r * ps)
        Skin.SetFont(sk.levelText, math.max(7, math.floor(ps * Lt.levelFont + 0.5)), "level", sk.id)
        sk.skull:ClearAllPoints()
        sk.skull:SetPoint("CENTER", sk.plate, "TOPLEFT", P.cx * ps, -P.cy * ps)
        sk.skull:SetSize(ps * Lt.skull, ps * Lt.skull)
    end
end

--- Auren-Groesse geaendert (/vials auren): vorhandene Knoepfe neu dimensionieren, beide Gruppen neu auslegen
local function resizeAuras(sk, s)
    sk.auraSize = s
    for f, parts in pairs(S.auraFrames) do safe(sizeAura, f, parts, s) end
    local hostile = sk.auraHostile == true
    call(sk.auras, "SetAuraGroupLayout", "debuffs", auraLayout(hostile and 1 or 2, not hostile))
    call(sk.auras, "SetAuraGroupLayout", "buffs", auraLayout(hostile and 2 or 1, hostile))
    call(sk.auras, "UpdateAllAuras")
end

local function layoutAuras(sk)
    local c, A = sk.auras, Deco.AURA
    local size, gap = auraMetrics()
    if sk.auraSize ~= size then resizeAuras(sk, size) end
    local lb = sk.mb and sk.power or sk.health
    local pad = lb.pad or {}
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", lb.root, "TOPLEFT", 0, -((lb.h or 10) + (pad.bottom or 0) + A.top))
    local w = lb.w or Skin.SPEC.target.health[1]
    local n = math.max(1, math.min(A.perRowMax, math.floor((w + gap) / (size + gap))))
    call(c, "SetFlowLayoutMaximumLineSize", w)
    call(c, "SetAuraGroupMaxFrameCount", "debuffs", n)
    call(c, "SetAuraGroupMaxFrameCount", "buffs", n)
    sk.auraPerRow = n
end

function Deco.Layout(sk)
    if sk.id == "target" and sk.zBack then layoutTarget(sk) end
    if sk.auras then safe(layoutAuras, sk) end
    sk.endsTries = 0
    layoutEnds(sk)
end

-- Inhalte -----------------------------------------------------------------------------------------------------------------
--- Klassifikation einer Einheit: kind ("elite"|"rare"|"rareelite"|"boss"|nil), skull (Stufe ??), Rohwert
function Deco.Classify(unit)
    local c = readFlag(_G.UnitClassification, unit)
    local boss = readFlag(_G.UnitIsBossMob, unit) == true
    local lvl = Compat.Num(readFlag(_G.UnitEffectiveLevel or _G.UnitLevel, unit))
    local skull = lvl ~= nil and lvl <= 0
    local kind = (boss or c == "worldboss" or skull) and "boss" or Deco.CLASS[c]
    return kind, skull, type(c) == "string" and c or nil
end

local function unitExists(unit)
    local ok, v = pcall(UnitExists, unit)
    return ok and Compat.Bool(v)
end

--- Schwierigkeitsfarbe (nur angreifbare Ziele); nil = neutral
function Deco.GemColor(unit)
    if readFlag(_G.UnitCanAttack, "player", unit) ~= true then return nil end
    local c
    local cpi = _G.C_PlayerInfo
    local d = readFlag(field(cpi, "GetContentDifficultyCreatureForPlayer"), unit)
    if d ~= nil then c = readFlag(_G.GetDifficultyColor, d) end
    if type(c) ~= "table" then
        local lvl = Compat.Num(readFlag(_G.UnitEffectiveLevel or _G.UnitLevel, unit))
        if lvl and lvl > 0 then c = readFlag(_G.GetCreatureDifficultyColor, lvl) or readFlag(_G.GetQuestDifficultyColor, lvl) end
    end
    local r, g, b = Compat.Num(field(c, "r")), Compat.Num(field(c, "g")), Compat.Num(field(c, "b"))
    if not (r and g and b) then return nil end
    return { r, g, b }
end

--- Stufenzahl wie Skin.updateText (secret nur durchgereicht); Testrahmen: "30"
local function restoreLevel(sk)
    if sk.testFrame then
        sk.levelText:SetText("30")
        return
    end
    if sk.preview then
        sk.levelText:SetText(tostring(sk.previewLevel or 30))
        return
    end
    local ok, lvl = pcall(UnitLevel, "target")
    if not ok then return end
    if Compat.IsSecret(lvl) then
        pcall(sk.levelText.SetText, sk.levelText, lvl)
        return
    end
    local n = Compat.Num(lvl)
    if n and n >= 1 then sk.levelText:SetText(tostring(n)) elseif n then sk.levelText:SetText("??") end
end

--- Stufen-Plakette: Stein (Farbe), Totenkopf bei ?? (statt Zahl)
function Deco.UpdateLevel(sk)
    if not sk.gem then return end
    local skull, color
    if sk.preview then
        skull, color = sk.previewKind == "boss", Deco.GEM_TEST
    elseif S.test then
        skull, color = S.test == "boss", Deco.GEM_TEST
    else
        local _, sk2 = Deco.Classify("target")
        skull, color = sk2, Deco.GemColor("target")
    end
    if skull then
        sk.levelText:SetText("")
        sk.skull:Show()
    else
        sk.skull:Hide()
        restoreLevel(sk) -- nach Totenkopf (Test boss/aus, Klassifikationswechsel) wieder die Zahl
    end
    local c = color or Deco.GEM_NEUTRAL
    sk.gem:SetVertexColor(c[1], c[2], c[3])
    sk.gem:Show()
    sk.gemColor = color and "diff" or "neutral"
end

local function setRaidIcon(tex, idx)
    local fn = _G.SetRaidTargetIconTexture
    if type(fn) == "function" and pcall(fn, tex, idx) then return true end
    local n = Compat.Num(idx)
    if not n then return false end
    local col, row = (n - 1) % 4, math.floor((n - 1) / 4)
    tex:SetTexCoord(col / 4, (col + 1) / 4, row / 4, (row + 1) / 4)
    return true
end

local function refreshMarker(sk)
    local idx
    if S.test then
        idx = 1
    elseif unitExists("target") then
        local ok, v = pcall(_G.GetRaidTargetIndex, "target")
        if ok then idx = v end
    end
    local show
    if Compat.IsSecret(idx) then
        show = setRaidIcon(sk.mIcon, idx) -- secret: nur durchgereicht (SetRaidTargetIconTexture -> SetSpriteSheetCell)
        sk.markerState = show and "secret" or "-"
    else
        local n = Compat.Num(idx)
        show = n ~= nil and n >= 1 and n <= 8 and setRaidIcon(sk.mIcon, n)
        sk.markerState = show and tostring(n) or "-"
    end
    sk.mIcon:SetShown(show and true or false)
    sk.mSock:SetShown(show and true or false)
end

-- Questies Symbol am Zielrahmen: QuestieNameplate.GetTargetFrameIconFrame legt ein Frame (Kind von TargetFrame, Ebene 11,
-- Mittelpunkt RIGHT/RIGHT, quadratisch 16 x Skala) mit Textur .Icon an und zeigt/versteckt es in DrawTargetFrame bzw.
-- HideCurrentTargetFrame. Erkennung (nur lesen): Icon-Pfad aus Questies Tabellen ODER dieser Bauplan (der Client kann
-- GetTexture als Dateinummer liefern, dann passt kein Pfad); Alpha 0 statt Hide (Questie zeigt/versteckt selbst).
local QUESTIE_LEVEL = 11
local function isQuestieTargetFrame(f, tf, isQ)
    if type(field(f, "Icon")) ~= "table" then return false end
    local okT, path = call(field(f, "Icon"), "GetTexture")
    if okT and not Compat.IsSecret(path) and (type(path) == "string" or type(path) == "number") then
        local okQ, v = pcall(isQ, path)
        if okQ and v == true then return true end
    end
    if type(_G.Questie) ~= "table" then return false end
    local okL, lvl = call(f, "GetFrameLevel")
    if not (okL and Compat.Num(lvl) == QUESTIE_LEVEL) then return false end
    local okP, point, rel, relPoint = call(f, "GetPoint", 1)
    if not (okP and point == "RIGHT" and (rel == nil or rel == tf) and (relPoint == nil or relPoint == "RIGHT")) then
        return false
    end
    local w, h = num(f, "GetWidth"), num(f, "GetHeight")
    return w ~= nil and h ~= nil and w > 0 and math.abs(w - h) < 0.01
end

local function syncQuestieTarget(replace)
    local tf = _G.TargetFrame
    local isQ = Style and Style.IsQuestieIcon
    if replace and type(isQ) == "function" and type(tf) == "table" and type(field(tf, "GetChildren")) == "function" then
        local kids = { pcall(tf.GetChildren, tf) }
        for i = 2, #kids do
            local f = kids[i]
            if not S.questieHidden[f] and isQuestieTargetFrame(f, tf, isQ) then
                local okA, a = call(f, "GetAlpha")
                S.questieHidden[f] = (okA and Compat.Num(a)) or 1 -- Original-Alpha merken
                S.questieHiddenN = S.questieHiddenN + 1
            end
            if S.questieHidden[f] then call(f, "SetAlpha", 0) end
        end
        return
    end
    for f, a in pairs(S.questieHidden) do call(f, "SetAlpha", a) end
    S.questieHidden, S.questieHiddenN = setmetatable({}, { __mode = "k" }), 0
end
Deco.SyncQuestieTarget = syncQuestieTarget

local function refreshQuest(sk)
    local want, kind, status = false, nil, "-"
    if S.test then
        want, kind, status = true, "slay", "test"
    elseif unitExists("target") and Style and Style.QuestSymbol then
        local ok, w, k, st = pcall(Style.QuestSymbol, "target")
        if ok then want, kind, status = w == true, k, st end
    end
    sk.questWant, sk.questKind, sk.questStatus = want, kind, status
    if want and not Style then want = false end -- Testmodus ohne Plaketten-Stil: kein Symbol
    if want then
        local tex = kind and Style.OBJ_TEX[kind] or Style.QUEST_TEX
        sk.qIcon:SetTexture(tex)
        local s = sk.qIconSize or 12
        sk.qIcon:SetSize(kind and s or s / 2, s) -- "!" halb so breit wie die Ziel-Symbole (wie an den Plaketten)
    end
    sk.qIcon:SetShown(want)
    sk.qSock:SetShown(want)
    if not sk.testFrame then syncQuestieTarget(want and kind ~= nil and status == "ok") end
end

--- Klassifikations-Zier
local function refreshKind(sk)
    local kind, _, raw
    if sk.preview then
        local pk = sk.previewKind
        kind = (pk and pk ~= "normal" and Deco.KIND_TEX[pk]) and pk or nil
        raw = "preview"
    elseif S.test then
        kind = S.test ~= "normal" and S.test or nil
        raw = "test"
    elseif unitExists("target") then
        kind, _, raw = Deco.Classify("target")
    end
    sk.zKind, sk.zRaw = kind, raw
    placeKind(sk)
end

--- Reihenfolge der Auren: bei Gegnern Schwaechungen zuerst, sonst Staerkungen
local function refreshAuras(sk)
    local c = sk.auras
    if not c then return end
    local hostile = readFlag(_G.UnitCanAttack, "player", "target") == true
    if hostile ~= sk.auraHostile then
        sk.auraHostile = hostile
        call(c, "SetAuraGroupLayout", "debuffs", auraLayout(hostile and 1 or 2, not hostile))
        call(c, "SetAuraGroupLayout", "buffs", auraLayout(hostile and 2 or 1, hostile))
    end
    call(c, "UpdateAllAuras")
end

local function refreshTarget(sk)
    refreshKind(sk)
    Deco.UpdateLevel(sk)
    if sk.preview then -- Vorschau: kein Raidmarker, kein Quest-Symbol (haengen am echten Ziel)
        for _, t in ipairs({ sk.mIcon, sk.mSock, sk.qIcon, sk.qSock }) do t:Hide() end
        return
    end
    refreshMarker(sk)
    safe(refreshQuest, sk) -- Questie-Fehler bricht den Rest nicht ab
end

local function hookQuestie()
    if S.questieHooked then return end
    local api = field(_G.Questie, "API")
    local reg = field(api, "RegisterForQuestUpdates")
    if type(reg) ~= "function" then return end
    S.questieHooked = true
    pcall(reg, function() Deco.OnQuest() end)
    local ready = field(api, "RegisterOnReady")
    if type(ready) == "function" then pcall(ready, function() Deco.OnQuest() end) end
end

--- Nach Questies Zielrahmen-Zeichnung (DrawTargetFrame/RedrawFrameIcon) sofort neu abgleichen, statt nur nach Zeitfenster.
--- Nachher-Hook auf Questies eigener Modul-Tabelle (nie auf Blizzard-Frames); fehlt Questie oder das Modul: nichts.
local function hookQuestieNameplate()
    if S.questieNpHooked ~= nil then return end
    local mod
    local loader = _G.QuestieLoader
    local mods = field(loader, "_modules")
    if type(mods) == "table" then mod = field(mods, "QuestieNameplate") end
    if type(mod) ~= "table" then
        if type(field(_G, "Questie")) ~= "table" then return end -- Questie (noch) nicht da: spaeter erneut versuchen
        S.questieNpHooked = false -- Questie da, Modul nicht erreichbar: bleibt beim Zeitfenster
        return
    end
    local ok = type(hooksecurefunc) == "function"
    if ok then
        for _, name in ipairs({ "DrawTargetFrame", "RedrawFrameIcon" }) do
            if type(field(mod, name)) == "function" then
                ok = pcall(hooksecurefunc, mod, name, function() Deco.OnQuestieDraw() end) and ok
            end
        end
    end
    S.questieNpHooked = ok
end

function Deco.Refresh(sk)
    if sk.id ~= "target" or not sk.zBack then return end
    refreshTarget(sk)
    if sk.preview then
        sk.endsTries = 0
        layoutEnds(sk)
        return
    end
    safe(refreshAuras, sk)
    hookQuestie()
    hookQuestieNameplate()
    -- Blizzard legt Balken/Klassifikation beim Zielwechsel neu (Kleinvieh: kuerzerer Balken): Enden neu messen, jetzt und
    -- nach dem naechsten Bild; Questie zeichnet sein Symbol im selben Ereignis (Reihenfolge offen): kurz danach erneut
    sk.endsTries = 0
    layoutEnds(sk)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() if sk.applied then safe(layoutEnds, sk) end end)
        C_Timer.After(Deco.QUESTIE_RECHECK, function() if sk.applied then safe(refreshQuest, sk) end end)
    end
end

--- Blizzards Auren nur verbergen, wenn der eigene Container laeuft (sonst bleiben sie sichtbar)
function Deco.HideBlizzard(sk)
    if S.auraInitFail and sk.auras then auraFallback(sk) end -- spaet erzeugte Knoepfe ohne SetIcon
    if sk.auras and sk.found then Skin.HideRegion(sk, sk.found.Auras) end
end

function Deco.Remove(sk)
    if sk.id == "target" and not sk.preview then syncQuestieTarget(false) end
    for _, key in ipairs({ "health", "power" }) do
        if sk[key] then Liquid.SetOpenEnd(sk[key], nil) end
    end
    if sk.socket then showSocket(sk, false) end
end

-- Ereignisse --------------------------------------------------------------------------------------------------------------
local function targetSk()
    local sk = Skin.Get("target")
    if sk and sk.applied and sk.zBack then return sk end
    return nil
end

--- Questie hat sein Zielrahmen-Symbol gerade (neu) gezeichnet: Lucids Abgleich laeuft im selben Bild
function Deco.OnQuestieDraw()
    local sk = targetSk()
    if sk then safe(refreshQuest, sk) end
end

local function questRefresh()
    S.questPending = false
    local sk = targetSk()
    if sk then safe(refreshQuest, sk) end
end

function Deco.OnQuest()
    if S.questPending or not targetSk() then return end
    S.questPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(Deco.QUEST_DELAY, questRefresh)
    else
        questRefresh()
    end
end

for _, ev in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do
    Compat.TryOn(ev, function() Deco.OnQuest() end)
end
Compat.TryOn("RAID_TARGET_UPDATE", function()
    local sk = targetSk()
    if sk then safe(refreshMarker, sk) end
end)
Compat.TryOn("UNIT_CLASSIFICATION_CHANGED", function(_, unit)
    if type(unit) ~= "string" or Compat.IsSecret(unit) or unit ~= "target" then return end
    local sk = targetSk()
    if sk then
        safe(refreshKind, sk)
        safe(Deco.UpdateLevel, sk)
    end
end)

-- Testmodus /vials test ziel <art> --------------------------------------------------------------------------------
--- eigener Testrahmen (Portraet des Spielers, Ring, Plakette, Zier) fuer den Fall ohne Ziel
local function testFrame()
    if S.tf then return S.tf end
    local T = Deco.TEST_FRAME
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(T.w, T.h)
    f:SetPoint("CENTER", UIParent, "CENTER", T.x, T.y)
    f:SetFrameStrata("MEDIUM")
    local pw = Skin.SPEC.target.portraitSize
    local sk = { id = "target", testFrame = true, holder = f, pw = pw }
    local por = f:CreateTexture(nil, "BACKGROUND")
    por:SetSize(pw, pw)
    por:SetPoint("RIGHT", f, "RIGHT", -24, 0)
    if type(_G.SetPortraitTexture) == "function" then pcall(_G.SetPortraitTexture, por, "player") end
    sk.anchor = por
    sk.ringSize = math.floor(pw * Skin.RING_SCALE + 0.5)
    sk.ringFrame = CreateFrame("Frame", nil, f)
    sk.ringFrame:SetFrameLevel((num(f, "GetFrameLevel") or 1) + 2)
    sk.ring = free(sk.ringFrame:CreateTexture(nil, "ARTWORK"))
    sk.ring:SetTexture(Skin.RING_TEX)
    sk.ring:SetPoint("CENTER", por, "CENTER", 0, 0)
    sk.ring:SetSize(sk.ringSize, sk.ringSize)
    sk.deco = CreateFrame("Frame", nil, f)
    sk.deco:SetFrameLevel((num(f, "GetFrameLevel") or 1) + 3)
    local ps = math.floor(pw * Skin.PLATE.badge + 0.5)
    local inset = math.floor(pw * Skin.PLATE.inset + 0.5)
    sk.plate = free(sk.deco:CreateTexture(nil, "ARTWORK"))
    sk.plate:SetTexture(Skin.PLATE_TEX.badge)
    sk.plate:SetPoint("CENTER", por, "BOTTOMRIGHT", -inset, inset)
    sk.plate:SetSize(ps, ps)
    sk.levelText = sk.deco:CreateFontString(nil, "OVERLAY")
    sk.levelText:SetJustifyH("CENTER")
    local c = Skin.NAME.color
    sk.levelText:SetTextColor(c[1], c[2], c[3])
    buildTarget(sk)
    layoutTarget(sk)
    S.tf = sk
    return sk
end

function Deco.TestKind() return S.test end
function Deco.TestFrame() return S.tf end

--- /vials test ziel <art>; word = Rest der Eingabe
function Deco.TestCommand(word)
    local w = (word or ""):lower():match("^%s*(%S*)") or ""
    local what = Deco.TEST_ARGS[w]
    if not what then
        ns.Print(L.FRAMES_DECO_USAGE)
        return
    end
    S.test = what ~= "off" and what or nil
    local real = targetSk()
    if real then
        safe(refreshTarget, real)
    end
    if S.test and not (real and unitExists("target")) then
        local tf = testFrame()
        tf.holder:Show()
        tf.levelText:SetText("30")
        safe(refreshTarget, tf)
    elseif S.tf then
        S.tf.holder:Hide()
    end
    if S.test then ns.Print(L.FRAMES_DECO_TEST_ON, w) else ns.Print(L.FRAMES_DECO_TEST_OFF) end
end

-- Diagnose ----------------------------------------------------------------------------------------------------------------
local function fmtEnd(v)
    if v == nil then return "-" end
    return string.format("%.1f", v)
end

function Deco.Debug()
    local yn = function(b) return b and L.NP_YES or L.NP_NO end
    local sk = Skin.Get("target")
    if sk and sk.zBack then
        local blizz = sk.found and sk.found.Auras
        ns.Print("frames.ziel klasse=%s zier=%s totenkopf=%s stein=%s quest=%s art=%s status=%s marker=%s auren=%s je_reihe=%s "
            .. "blizzAuren=%s questieVerborgen=%d questieHook=%s test=%s", tostring(sk.zRaw or "-"), tostring(sk.zKind or "-"),
            yn(sk.skull and sk.skull:IsShown()), tostring(sk.gemColor or "-"), yn(sk.questWant), tostring(sk.questKind or "!"),
            tostring(sk.questStatus or "-"), tostring(sk.markerState or "-"), tostring(sk.auraState or "-"),
            tostring(sk.auraPerRow or "-"), blizz and (sk.auras and "verborgen" or "sichtbar") or "fehlt", S.questieHiddenN,
            S.questieNpHooked == nil and "-" or (S.questieNpHooked and "ja" or "nein"), tostring(S.test or "-"))
    else
        ns.Print("frames.ziel aufgebaut=%s test=%s", L.NP_NO, tostring(S.test or "-"))
    end
    local parts, sockets = {}, {}
    for _, id in ipairs(Skin.FRAMES) do
        local s = Skin.Get(id)
        local e = s and s.ends or {}
        parts[#parts + 1] = string.format("%s=%s/%s%s", id, fmtEnd(e.health), fmtEnd(e.power), (s and s.endsOk) and "" or "?")
        if s and s.socket then sockets[#sockets + 1] = id .. ":" .. yn(s.socketOn) end
    end
    ns.Print("frames.enden %s aufnahmen=%s errors=%d", table.concat(parts, " "),
        #sockets > 0 and table.concat(sockets, ",") or "-", S.errorCount)
    for i, e in ipairs(S.errors) do ns.Print("frames.ziel.error.%d %s", i, (e:gsub("|", "||"))) end
end

ns.AddHelp("HELP_FRAMES_TESTZIEL")

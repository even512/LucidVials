-- Debuff-Toenung ueber Blizzards Rahmenbild (Delta "Kampf-Toenung" 26.11.). Forever sperrt im Kampf jede C_UnitAuras-Abfrage
-- (auch GetAuraDispelTypeColor); Blizzards eigene Debuff-Leiste zeigt die Bannart aber weiter als farbigen Rahmen. Die Farbe
-- wird hier sichtbar gemacht, OHNE sie zu lesen (Kampftest 26.11., Probe B2: Streifen per Clip-Rahmen war blau):
--   Quelle   DebuffFrame.auraFrames[i].DebuffBorder:GetAtlas() (im Kampf secret), nur gelesen. Erkennung allein am Rahmen
--            (B.Classify, EINE Stelle): Rahmen lesbar sichtbar und Atlas secret => Rahmen-Weg; Atlas lesbar und einer der
--            vier Farb-Rahmen => eigene Palette dieser Art; lesbarer Default-Rahmen (Debuff ohne Bannart, rot) => Rahmen-
--            Weg, solange B.TINT_UNTYPED; anderer/kein Atlas => keine Toenung. buttonInfo.debuffType
--            zaehlt NICHT (Kampftest 26.11.: bei Magie lesbar nil, beim ersten Test secret).
--   Ziel     eigene Textur SetAtlas(<secret Atlas>) (Katalog Forever 1.60.1: SimpleTextureBaseAPI:SetAtlas SecretArguments
--            AllowedWhenTainted), Rahmenfarbe GetVertexColor -> SetVertexColor durchgereicht (ebenso AllowedWhenTainted).
--   Ausschnitt nur der volle Farbrand: B.STRIP (Anteile der Atlas-Zelle), gestreckt ueber den Fluessigkeitskoerper. Die
--            Atlas-Geometrie kommt aus
--            C_Texture.GetAtlasInfo der LESBAREN Atlasnamen (ausserhalb des Kampfs gemessen und gemerkt; GetAtlasInfo nimmt
--            Secrets nur ungetaintet, darum nie mit dem secret Namen aus dem Kampf).
--   Wege     "texcoord": alle fuenf Atlanten liegen im selben Ausschnitt (eigene Dateien) => SetTexCoord mit den gemessenen
--            Zahlen, Textur direkt in der Fluessigkeit (unter Luft/Glas). "clip": sonst (Atlanten in einem Bogen an
--            verschiedenen Stellen, oder nicht gemessen) => Textur ebenfalls in der Fluessigkeit, aber so gross gelegt, dass
--            genau der Streifen die Flaeche fuellt; den Ueberstand schneiden Kapselmaske und Fluessigkeits-Clip ab (wie die
--            Probe B2; die Engine rechnet, Lua nie mit einem Secret). Beide Wege folgen damit exakt der Fluessigkeitsform.
-- Atlasnamen: zur Laufzeit aus DEBUFF_DISPLAY_INFO (FrameXML, AuraUtil.SetAuraBorderAtlas; die Tabelle steht nicht im API-
-- Katalog und lokal liegt keine wow-ui-source), sonst die UNGEPRUEFTEN Rueckfallnamen B.FALLBACK (Schema
-- "ui-debuff-border-<art>-icon", wie Blizzards Rahmen-Atlanten in der Probe erscheinen). Die Probe /vials probe dispel zeigt
-- Namen, Quelle und Geometrie (rahmen.*). Jeder Zugriff in pcall, keine Schreibzugriffe auf Blizzard-Frames, Secrets werden
-- nie verglichen, gerechnet, verkettet oder ausgegeben.
local _, ns = ...
local Compat = ns.Compat

local B = {}
ns.LiquidBorder = B

B.KINDS = { "Magic", "Curse", "Disease", "Poison" }
B.DEFAULT = "Default"                           -- Schluessel des Rahmens ohne Bannart in B.geo
B.DEFAULT_KEYS = { "None", "none", "Default" }  -- moegliche Schluessel in DEBUFF_DISPLAY_INFO
-- Rueckfallnamen wie in Blizzards AuraUtil (live, DEBUFF_DISPLAY_INFO): dispelAtlas "-icon" (mit Bann-Symbol oben rechts),
-- basicAtlas "-noicon" (ohne Symbol, bei showDispelType=false). Debuffs ohne Bannart ("None") haben nur
-- "ui-debuff-border-default-noicon" (Rahmen sichtbar, Farbe DEBUFF_TYPE_NONE_COLOR rot); ein "default-icon" gibt es nicht.
B.FALLBACK = { Magic = "ui-debuff-border-magic-icon", Curse = "ui-debuff-border-curse-icon",
    Disease = "ui-debuff-border-disease-icon", Poison = "ui-debuff-border-poison-icon",
    Default = "ui-debuff-border-default-noicon" }
B.PATTERN = "ui-debuff-border-%s-icon"
B.PATTERN_NOICON = "ui-debuff-border-%s-noicon"
B.NOICON = ".noicon"                             -- Schluesselzusatz der -noicon-Zellen in B.geo (z. B. "Magic.noicon")
-- Streifen im Farbrand als Anteile der Atlas-Zelle (0..1 je Achse, l < r, t < b), fuer alle Arten gleich (im Kampf ist die
-- Art unbekannt). Gemessen an der echten Textur (Datei 7582803 interface/hud/uidebuffframes2x.blp, Zelle 40 x 40 = 80 x 80
-- Texel): untere Kante, Texelzeilen 70..71 (rel 0.875..0.900), x 13..67 (rel 0.1625..0.8375) - einfarbig, deckend, ohne
-- Eckrundung und ohne Bann-Symbol (das sitzt oben rechts). t/b liegen auf den TEXELMITTEN 70.5/80 und 71.5/80: bei
-- bilinearer Filterung mischen Abtastungen ausserhalb der Mitten die Nachbarzeilen ein (69 = schwarzer Ring, 72 =
-- transparent), was beim 80-fachen Strecken als dunkler/durchsichtiger Saum oben/unten in der Fluessigkeit laege.
B.STRIP = { l = 0.1625, r = 0.8375, t = 70.5 / 80, b = 71.5 / 80 }
-- Debuffs ohne Bannart (sichtbarer Default-Rahmen, rot) mittoenen? Entscheidung 26.11.: ja. Im Kampf ist der Atlas
-- secret und Default von Farb-Rahmen nicht zu unterscheiden - false wirkt darum nur auf LESBARE Atlanten (ausserhalb des
-- Kampfs); im Kampf toenen typlose Debuffs immer mit.
B.TINT_UNTYPED = true
-- alpha = Gesamtstaerke wie Fx.INK.tintA/secretA; scanMax: Knoepfe hoechstens
B.CFG = { alpha = 0.8, blend = "BLEND", scanMax = 40 }

B.geo = nil       -- gemessene Geometrie (B.Measure), nil = noch nicht gemessen
B.RETRY = 10      -- s: ohne gemessenen Farb-Rahmen (Tabelle/Atlanten noch nicht da) hoechstens so oft neu messen
local stripCache  -- aus B.geo abgeleiteter Ausschnitt (B.Strip)

local function lockdown() return type(InCombatLockdown) == "function" and InCombatLockdown() == true end

--- Feld einer lesbaren Tabelle (nil bei secret/fehlend/Fehler)
function B.Field(t, key)
    if type(t) ~= "table" or Compat.IsSecret(t) then return nil end
    local ok, v = pcall(function() return t[key] end)
    if ok then return v end
    return nil
end
local field = B.Field

--- Wert vorhanden (secret zaehlt als vorhanden; kein Vergleich auf einem Secret)
local function present(v) return Compat.IsSecret(v) or v ~= nil end

local function num(t, key)
    local v = field(t, key)
    if type(v) ~= "number" or Compat.IsSecret(v) then return nil end
    return v
end

--- Geometrie eines lesbaren Atlasnamens: { name, w, h, l, r, t, b, tiles, file } oder nil
local function atlasInfo(name)
    local T = _G.C_Texture
    if type(T) ~= "table" or type(T.GetAtlasInfo) ~= "function" then return nil end
    if type(name) ~= "string" or Compat.IsSecret(name) or name == "" then return nil end
    local ok, info = pcall(T.GetAtlasInfo, name)
    if not ok or type(info) ~= "table" or Compat.IsSecret(info) then return nil end
    local g = { name = name, w = num(info, "width"), h = num(info, "height"), l = num(info, "leftTexCoord"),
        r = num(info, "rightTexCoord"), t = num(info, "topTexCoord"), b = num(info, "bottomTexCoord") }
    if not (g.w and g.h and g.l and g.r and g.t and g.b) then return nil end
    g.tiles = field(info, "tilesHorizontally") == true or field(info, "tilesVertically") == true
    local file = field(info, "filename")
    if file == nil then file = field(info, "file") end
    g.file = (type(file) == "string" or type(file) == "number") and not Compat.IsSecret(file) and file or nil
    return g
end
B.AtlasInfo = atlasInfo

--- lesbare Texte eines DEBUFF_DISPLAY_INFO-Eintrags (Rahmen-Namen zuerst), nil ohne Tabelle
local function displayStrings(key)
    local D = _G.DEBUFF_DISPLAY_INFO
    local e = field(D, key)
    if type(e) ~= "table" or Compat.IsSecret(e) then return nil end
    local out = {}
    pcall(function()
        for _, v in pairs(e) do
            if type(v) == "string" and not Compat.IsSecret(v) and v ~= "" then out[#out + 1] = v end
        end
    end)
    table.sort(out, function(a, b)
        local pa, pb = a:lower():find("border", 1, true) ~= nil, b:lower():find("border", 1, true) ~= nil
        if pa ~= pb then return pa end
        return a < b
    end)
    return out
end

--- Atlasname je Art: aus DEBUFF_DISPLAY_INFO (zuerst die Felder dispelAtlas/basicAtlas wie in AuraUtil, sonst ein Text, der
--- selbst ein Atlas ist, sonst als Grundname im Schema), sonst Rueckfall. noicon = die -noicon-Zelle (basicAtlas, bei
--- showDispelType=false); der Default-Rahmen hat nur diese.
local function resolveName(kind, noicon)
    local isDefault = kind == B.DEFAULT
    local keys = isDefault and B.DEFAULT_KEYS or { kind }
    local pattern = noicon and B.PATTERN_NOICON or B.PATTERN
    for _, key in ipairs(keys) do
        local direct = field(field(_G.DEBUFF_DISPLAY_INFO, key), (noicon or isDefault) and "basicAtlas" or "dispelAtlas")
        if type(direct) == "string" and not Compat.IsSecret(direct) and atlasInfo(direct) then return direct, "display" end
        local list = displayStrings(key)
        if list then
            for _, s in ipairs(list) do
                local isNo = s:lower():find("noicon", 1, true) ~= nil
                if (isDefault or isNo == (noicon == true)) and atlasInfo(s) then return s, "display" end
            end
            for _, s in ipairs(list) do
                local n = pattern:format(s:lower())
                if atlasInfo(n) then return n, "display" end
            end
        end
    end
    if noicon then return pattern:format(kind:lower()), "fallback" end
    return B.FALLBACK[kind], "fallback"
end

local function sameSize(a, b) return math.abs(a.w - b.w) < 0.5 and math.abs(a.h - b.h) < 0.5 end
local function sameRect(a, b)
    local e = 1e-6
    return math.abs(a.l - b.l) < e and math.abs(a.r - b.r) < e and math.abs(a.t - b.t) < e and math.abs(a.b - b.b) < e
end

--- Rahmen-Geometrie messen und merken (nur ausserhalb des Kampfs; force = neu messen; ohne Farb-Rahmen gedrosselt alle
--- B.RETRY s neu, bis einer gefunden ist). Liefert B.geo (oder nil).
--- geo.by[art] = Geometrie|false, geo.names/src[art], geo.colored = gemessene Farb-Rahmen, geo.ref = erste davon,
--- geo.sameSize/sameRect = alle Farb-Rahmen gleich gross/im selben Ausschnitt, geo.defaultSize/defaultRect (nil = fehlt)
function B.Measure(force)
    local t = type(GetTime) == "function" and GetTime() or 0
    if B.geo and not force and (B.geo.colored > 0 or t - (B.geo.at or 0) < B.RETRY) then return B.geo end
    if lockdown() then return B.geo end
    local T = _G.C_Texture
    if type(T) ~= "table" or type(T.GetAtlasInfo) ~= "function" then return B.geo end
    local geo = { by = {}, names = {}, src = {}, colored = 0, sameSize = true, sameRect = true, tiles = false, at = t }
    for _, k in ipairs(B.KINDS) do
        local name, src = resolveName(k)
        local g = atlasInfo(name)
        geo.names[k], geo.src[k], geo.by[k] = name, src, g or false
        if g then
            geo.colored = geo.colored + 1
            if not geo.ref then geo.ref = g end
            if not sameSize(g, geo.ref) then geo.sameSize = false end
            if not sameRect(g, geo.ref) then geo.sameRect = false end
            if g.tiles then geo.tiles = true end
        end
    end
    -- -noicon-Zellen (showDispelType=false): Groesse wird mitgeprueft (sameSize, gilt fuer den gemeinsamen Streifen), der
    -- Ausschnitt nicht (sie liegen zwangslaeufig anderswo im Bogen; texcoord haengt allein an den -icon-Zellen)
    geo.noicon = 0
    for _, k in ipairs(B.KINDS) do
        local key = k .. B.NOICON
        local nName, nSrc = resolveName(k, true)
        local g = atlasInfo(nName)
        geo.names[key], geo.src[key], geo.by[key] = nName, nSrc, g or false
        if g then
            geo.noicon = geo.noicon + 1
            if geo.ref and not sameSize(g, geo.ref) then geo.sameSize = false end
        end
    end
    local name, src = resolveName(B.DEFAULT)
    local d = atlasInfo(name)
    geo.names[B.DEFAULT], geo.src[B.DEFAULT], geo.by[B.DEFAULT] = name, src, d or false
    if d and geo.ref then geo.defaultSize, geo.defaultRect = sameSize(d, geo.ref), sameRect(d, geo.ref) end
    if geo.colored == 0 then geo.sameSize, geo.sameRect = false, false end
    B.geo = geo
    stripCache = nil
    return geo
end

--- Ausschnitt (B.STRIP, Anteile der Atlas-Zelle) und Weg: { l, r, t, b, mode = "texcoord"|"clip", abs = {l, r, t, b}|nil,
--- src = "gemessen"|"fallback" }. "gemessen", wenn alle gemessenen Farb-Rahmen gleich gross sind; "texcoord" nur, wenn alle
--- fuenf im selben Ausschnitt liegen (der Default darf fehlen, aber nicht abweichen) - dann exakte Datei-Koordinaten.
function B.Strip()
    if stripCache then return stripCache end
    local S, g = B.STRIP, B.geo
    local s = { l = S.l, r = S.r, t = S.t, b = S.b, mode = "clip", src = "fallback" }
    if g and g.ref and g.sameSize and g.ref.w > 0 then
        s.src = "gemessen"
        if g.sameRect and g.colored == #B.KINDS and g.defaultRect ~= false and not g.tiles then
            local R = g.ref
            local dx, dy = R.r - R.l, R.b - R.t
            s.mode = "texcoord"
            s.abs = { R.l + dx * S.l, R.l + dx * S.r, R.t + dy * S.t, R.t + dy * S.b }
        end
    end
    stripCache = s
    return s
end

--- Neuer Ausschnitt (Tests/Feinjustage): Anteile der Zelle, ungueltig => false
function B.SetStrip(l, r, t, b)
    for _, v in ipairs({ l, r, t, b }) do
        if type(v) ~= "number" or v < 0 or v > 1 then return false end
    end
    if l >= r or t >= b then return false end
    B.STRIP = { l = l, r = r, t = t, b = b }
    stripCache = nil
    return true
end

--- sichtbare Debuff-Knoepfe der Blizzard-Leiste in ihrer Reihenfolge (hoechstens max); nil, Grund wenn nicht lesbar
function B.Buttons(max)
    local f = _G.DebuffFrame
    if type(f) ~= "table" then return nil, "DebuffFrame fehlt" end
    local frames = field(f, "auraFrames")
    if type(frames) ~= "table" or Compat.IsSecret(frames) then
        return nil, "auraFrames " .. (frames == nil and "nil" or Compat.IsSecret(frames) and "secret" or type(frames))
    end
    local out = {}
    max = max or B.CFG.scanMax
    local ok = pcall(function()
        for _, b in ipairs(frames) do
            if #out >= max then break end
            if type(b) == "table" then
                local okS, shown = pcall(b.IsShown, b)
                if okS and (Compat.IsSecret(shown) or shown == true) then out[#out + 1] = b end
            end
        end
    end)
    if not ok then return nil, "auraFrames nicht durchlaufbar" end
    return out
end

--- Rahmen eines Knopfs: { atlas (secret erlaubt), kind = "secret"|"none"|"unknown"|<lesbarer Text>, shown, vc = {r,g,b} }
--- oder nil, Grund. Nur gelesen.
function B.Read(b)
    local border = field(b, "DebuffBorder")
    if type(border) ~= "table" then return nil, "fehlt" end
    local okA, atlas = pcall(border.GetAtlas, border)
    if not okA then return nil, "fehler" end
    if not Compat.IsSecret(atlas) and (atlas == nil or atlas == "") then return nil, "ohne" end
    local info = { atlas = atlas, kind = "unknown" }
    local okS, shown = pcall(border.IsShown, border)
    if okS then info.shown = shown end
    local okV, r, g, bl = pcall(border.GetVertexColor, border)
    if okV and present(r) and present(g) and present(bl) then info.vc = { r, g, bl } end
    local okI, bi = pcall(function() return b.buttonInfo end)
    if okI and type(bi) == "table" and not Compat.IsSecret(bi) then
        local okK, k = pcall(function() return bi.debuffType end)
        if okK then
            if Compat.IsSecret(k) then info.kind = "secret"
            elseif k == nil then info.kind = "none"
            elseif type(k) == "string" then info.kind = k end
        end
    end
    return info
end

local function sameName(a, n) return type(a) == "string" and not Compat.IsSecret(a) and a:lower() == n end

--- lesbarer Atlasname -> Art (-icon und -noicon; gemessene/aufgeloeste Namen und Rueckfallnamen, ohne Gross-/Klein-
--- schreibung), B.DEFAULT fuer den Rahmen ohne Bannart, sonst nil
function B.KindOfAtlas(name)
    if type(name) ~= "string" or Compat.IsSecret(name) then return nil end
    local n = name:lower()
    local names = B.geo and B.geo.names or {}
    for _, k in ipairs(B.KINDS) do
        if sameName(names[k], n) or sameName(names[k .. B.NOICON], n) or sameName(B.FALLBACK[k], n)
            or sameName(B.PATTERN_NOICON:format(k:lower()), n) then
            return k
        end
    end
    if sameName(names[B.DEFAULT], n) or sameName(B.FALLBACK[B.DEFAULT], n) then return B.DEFAULT end
    return nil
end

--- EINZIGE Erkennungsregel: "border" (Rahmen-Weg: Atlas secret, oder lesbarer Default-Rahmen bei B.TINT_UNTYPED - dessen
--- Farbe DEBUFF_TYPE_NONE_COLOR kommt wie im Kampf ueber Atlas + Vertexfarbe), <Art> (Atlas lesbar und ein Farb-Rahmen =>
--- eigene Palette) oder nil (Rahmen nicht lesbar sichtbar, anderer/kein Atlas, typlos bei B.TINT_UNTYPED = false)
function B.Classify(info)
    if type(info) ~= "table" then return nil end
    if Compat.IsSecret(info.shown) or info.shown ~= true then return nil end
    if Compat.IsSecret(info.atlas) then return "border" end -- im Kampf: Farb- und Default-Rahmen nicht unterscheidbar
    local k = B.KindOfAtlas(info.atlas)
    if k == B.DEFAULT then return B.TINT_UNTYPED and "border" or nil end
    return k
end

--- Knoepfe der Leiste fuer die Toenung (Reihenfolge wie Blizzards Leiste, hoechstens max): je Knopf info mit
--- info.class = "border" | <Art> (siehe B.Classify)
function B.Candidates(max)
    local out = {}
    if (max or 0) <= 0 then return out end
    local list = B.Buttons(B.CFG.scanMax)
    if not list then return out end
    for _, b in ipairs(list) do
        if #out >= max then break end
        local info = B.Read(b)
        local class = B.Classify(info)
        if class then
            info.class = class
            out[#out + 1] = info
        end
    end
    return out
end

local function free(t)
    if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, false) end
    if t.SetTexelSnappingBias then pcall(t.SetTexelSnappingBias, t, 0) end
    return t
end

--- Toenungsebene im Wirt anlegen: tin = ganze Flaeche (Weg "texcoord"), tclip = uebergross, nur der Streifen liegt auf der
--- Flaeche (Weg "clip"). Den Rest schneidet die Maske (CLAMPTOBLACKADDITIVE: ausserhalb schwarz) bzw. ein clippender Wirt.
function B.NewLayer(host, mask, layer, sub)
    local L = {}
    L.tin = free(host:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0))
    L.tin:SetAllPoints(host)
    L.tclip = free(host:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0))
    if mask then
        pcall(L.tin.AddMaskTexture, L.tin, mask)
        pcall(L.tclip.AddMaskTexture, L.tclip, mask)
    end
    for _, t in ipairs({ L.tin, L.tclip }) do
        if t.SetBlendMode then pcall(t.SetBlendMode, t, B.CFG.blend) end
        t:Hide()
    end
    return L
end

--- Clip-Textur so legen, dass der Streifen genau die Flaeche w x h ab ref TOPLEFT (top px tiefer) fuellt
function B.Place(L, ref, w, h, top, strip)
    strip = strip or B.Strip()
    local W = w / math.max(1e-3, strip.r - strip.l)
    local H = h / math.max(1e-3, strip.b - strip.t)
    local t = L.tclip
    t:ClearAllPoints()
    t:SetSize(W, H)
    t:SetPoint("TOPLEFT", ref, "TOPLEFT", -strip.l * W, -(top or 0) + strip.t * H)
end

function B.Hide(L)
    L.tin:Hide()
    L.tclip:Hide()
end

--- Rahmen info auf die Ebene (Werte nur durchgereicht). Liefert ok, Weg bzw. Grund.
function B.Paint(L, info, strip, alpha)
    strip = strip or B.Strip()
    local use, other = L.tclip, L.tin
    if strip.mode == "texcoord" then use, other = L.tin, L.tclip end
    other:Hide()
    if type(info) ~= "table" or not present(info.atlas) then
        use:Hide()
        return false, "-"
    end
    if not pcall(use.SetAtlas, use, info.atlas, false) then
        use:Hide()
        return false, "fehler"
    end
    if strip.mode == "texcoord" then
        local A = strip.abs
        if not pcall(use.SetTexCoord, use, A[1], A[2], A[3], A[4]) then
            use:Hide()
            return false, "fehler"
        end
    end
    local vc = info.vc
    if not (vc and pcall(use.SetVertexColor, use, vc[1], vc[2], vc[3])) then pcall(use.SetVertexColor, use, 1, 1, 1) end
    pcall(use.SetAlpha, use, alpha or B.CFG.alpha)
    use:Show()
    return true, strip.mode
end

local function f4(v) return type(v) == "number" and ("%.4f"):format(v) or "-" end
local function txt(v) return (tostring(v):gsub("|", "||")) end

--- Zeilen fuer Probe/Debug: Messung, Weg, Ausschnitt, je Art Name/Quelle/Geometrie (alles lesbar)
function B.GeoLines()
    local out = {}
    local g, s = B.geo, B.Strip()
    local function yn(v) if v == nil then return "-" end return v and "ja" or "nein" end
    out[#out + 1] = ("rahmen.geo gemessen=%s farbig=%s noicon=%s gleicheGroesse=%s gleicherAusschnitt=%s"
        .. " default.groesse=%s default.ausschnitt=%s typlos=%s"):format(g and "ja" or "nein",
        g and tostring(g.colored) or "-", g and tostring(g.noicon or 0) or "-", yn(g and g.sameSize), yn(g and g.sameRect),
        yn(g and g.defaultSize), yn(g and g.defaultRect), B.TINT_UNTYPED and "rot" or "aus")
    -- skala = Textur-Groesse je Flaechen-Groesse im Clip-Weg (1 / Streifenanteil, siehe B.Place)
    out[#out + 1] = ("rahmen.streifen weg=%s quelle=%s l=%s r=%s t=%s b=%s skala=%sx%s abs=%s"):format(s.mode, s.src,
        f4(s.l), f4(s.r), f4(s.t), f4(s.b), f4(1 / (s.r - s.l)), f4(1 / (s.b - s.t)),
        s.abs and table.concat({ f4(s.abs[1]), f4(s.abs[2]), f4(s.abs[3]), f4(s.abs[4]) }, ",") or "-")
    if g then
        local keys = {}
        for _, k in ipairs(B.KINDS) do keys[#keys + 1] = k end
        for _, k in ipairs(B.KINDS) do keys[#keys + 1] = k .. B.NOICON end
        keys[#keys + 1] = B.DEFAULT
        for _, k in ipairs(keys) do
            local a = g.by[k]
            if a then
                -- streifen = Lage des Streifens in der Datei (Texturkoordinaten) fuer diese Zelle, zum Nachmessen
                local dx, dy = a.r - a.l, a.b - a.t
                out[#out + 1] = ("rahmen.atlas.%s name=%s quelle=%s w=%s h=%s tc=%s,%s,%s,%s streifen=%s,%s,%s,%s datei=%s")
                    :format(k, txt(a.name), tostring(g.src[k]), f4(a.w), f4(a.h), f4(a.l), f4(a.r), f4(a.t), f4(a.b),
                    f4(a.l + dx * s.l), f4(a.l + dx * s.r), f4(a.t + dy * s.t), f4(a.t + dy * s.b), txt(a.file or "-"))
            else
                out[#out + 1] = ("rahmen.atlas.%s name=%s quelle=%s fehlt"):format(k, txt(g.names[k] or "-"), tostring(g.src[k]))
            end
        end
    end
    return out
end

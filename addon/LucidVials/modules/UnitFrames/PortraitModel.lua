-- Portrait-Stile "model" ("Reagierendes Modell") und "modelplain" ("Animiertes Modell (schlicht)", Delta "Ausbau 1.1.0", E6): ein
-- 3D-Modell (PlayerModel) eng auf Kopf und Schultern im Ring, angemeldet ueber Portrait.RegisterStyle (Schnittstelle im Kopf von
-- Portrait.lua), gemeinsamer Code, nur Spieler und Ziel (das Ziel des Ziels bleibt statisch; Activate prueft es zusaetzlich).
--
-- Rundung: Masken wirken nicht auf Modelle. Das Modell ist ein Quadrat von SIZE x Portrait (Ecken mit halber Diagonale 0,59 x
-- Portrait unter dem Bronzeband des Rings, 0,49..0,62). Darueber liegt im selben Frame (OVERLAY, ueber dem Modell, das per
-- SetModelDrawLayer auf ARTWORK zeichnet) die Abdeckung Media/uf-portrait-model-cover (scripts/gen-model-cover.mjs): ein Kreisring
-- in der Farbe des dunklen Glas-Grundes, innen durchsichtig mit weichem Rand; sie verdeckt die geraden Kanten des Quadrats. Darunter
-- ein runder dunkler Grund (BACKGROUND, Kreismaske). Die 2D-Portrait-Textur des Rahmens (P.base) ist verborgen, Blizzards Portrait
-- per Alpha 0 (Portrait.lua); der Glasglanz (Portrait.lua, Ebene + 2) und der Ring liegen darueber.
--
-- Animationen: nur eine feste Liste, die Kopf und Schultern im Bild laesst (Stehen, Treffer, Kampfbereit, Zaubern mit Handhaltung,
-- Lachen/Reden), und nur IDs, die HasAnimation bestaetigt. Kein Hinlegen: Ausruhen = Stehen + langsam "atmendes" Abdunkeln, Tod und
-- Geist = Stehen eingefroren (FreezeAnimation, sonst Pause) und grau. Kurze Reaktionen kehren ueber OnAnimFinished (Sicherheitsnetz:
-- C_Timer) zur Ruhe zurueck.
-- Reaktionen nur bei "model" (Recherche C.3, ohne CLEU, ohne Wertevergleich): Treffer/Heilung kommen von Portrait.lua (UNIT_COMBAT,
-- die Menge wird nie gelesen), Zaubern ueber UNIT_SPELLCAST_* (nur das Ereignis), Kampfhaltung ueber PLAYER_REGEN_* (Spieler) bzw.
-- UNIT_FLAGS + UnitAffectingCombat (Ziel), Ausruhen nur Spieler. "Wenig Leben" nur als Vignette/Risse/Roete per Kurven-Alpha
-- (Portrait.Util), Licht in Fluessigkeitsfarbe nur mit lesbaren Zahlen. "modelplain" zeigt nur das Modell in Ruhe: keine Reaktionen,
-- keine Effekt-Lagen, neutrales Licht; Abdeckung und Glanz bleiben.
--
-- Ausblenden mit dem Rahmen: Texturen erben das Alpha der Eltern-Kette (Blizzard-Rahmen -> holder -> Portrait-Frame), das 3D-Modell
-- nicht verlaesslich. Darum wird das wirksame Alpha nur lesbar (Secret => unveraendert) nachgefuehrt, und zwar aus denselben Quellen
-- wie die Fluessigkeit: Wurzel der Lebensroehre (Liquid.SyncFade), Portrait-Frame, zuletzt das Modell selbst (kleinster lesbarer
-- Wert gewinnt, das Modell allein war im Spiel nicht verlaesslich). Es wird per SetModelAlpha gesetzt; fehlt die Methode, ersatzweise
-- per SetAlpha am eigenen Modell-Frame (sonst nie; erbt der Frame dort die Eltern-Kette, wirkt im Ersatzweg a x a: nur ein Notnagel).
-- Unter FADE_PAUSE wird das Modell pausiert (beim ersten sichtbaren Schritt sofort wieder gestartet); verborgen (Hide, Show erst ueber
-- FADE_SHOW: Hysterese, dann neu binden) wird es nur im Ersatzweg ohne SetModelAlpha: SetModelAlpha(0) genuegt und das Modell
-- muss beim Einblenden nicht neu laden (Model.ALPHA_GAMMA = 2 gleicht das bei kleinem Alpha deckendere Modell an: Zahlen per Potenz,
-- Secrets ueber eine C_CurveUtil-Kurve y = x ^ Gamma, deren Ergebnis unveraendert an SetModelAlpha geht). Vierte Quelle "hook": ein reiner Nachher-Hook auf SetAlpha der Rahmen-Wurzel (dieselbe wie Skin.hookFade, nur ein Hook
-- je Wurzel, keine Felder am Blizzard-Frame, Merkliste in eigener Tabelle) merkt die uebergebene Zahl, auch wenn jedes
-- GetEffectiveAlpha secret ist (Lucids Fader setzt Zahlen); Secret-Aufrufe und SetAlphaFromBoolean (Wert unbekannt) aendern sie nicht (nur gezaehlt)
-- (Lucid setzt SetAlpha direkt am Wurzel-Frame PlayerFrame/TargetFrame; Skins Hook laeuft vor dem Loeschen: Rest-Unschaerfe).
-- Die Hooks haengen schon beim Laden dieser Datei (ROOTS), nicht erst beim Aktivieren: Lucid wendet sein Alpha ab PLAYER_LOGIN an
-- (Modul "hide": OnEnable -> Elements.SyncAll -> Fader.Register; Fader.ReapplyAll bei PLAYER_ENTERING_WORLD) und setzt es danach nur
-- bei Zustandswechseln neu; ein spaeter Hook sah den Wert nie (Debug dann "hook:keine-zahl" statt "hook:keine"). Ist das wirksame Alpha secret (Retail 12.x, Alpha-Aspekt), wird es einmal per pcall an SetModelAlpha durchgereicht
-- (keine Rechnung, kein Vergleich); Lucids Kurvenmodus setzt SetAlpha(Secret) an der Wurzel (gelingt im Spiel trotz Katalog): der Root-Hook
-- reicht dieses Secret sofort an SetModelAlpha (sonst SetAlpha am Modell-Frame) durch, das Modell bleibt gezeigt, der Takt ueberschreibt
-- es nicht (rootKind), die naechste Zahl setzt wieder normal (Hide/Hysterese). Fuer das Lesen: der API-Katalog nennt dort aber SecretArguments = AllowedWhenUntainted (genau wie SetAlpha), ein
-- Addon wird also meist abgewiesen: dann ruht der Versuch (passDenied) und der letzte Stand bleibt. SetAlphaFromBoolean am Modell
-- braucht eine Bedingung (Boolean), die hier nicht vorliegt; ein Zwischen-Frame hilft nicht belegbar (der Katalog sagt nichts dazu,
-- ob PlayerModel die Eltern-Alpha erbt). /vials debug zeigt je Quelle zahl/secret/fehler/keine, den Weg und die Zaehler.
-- Antrieb: nach jedem Liquid.SyncFadeAll (Skin.lua ruft es nach SetAlpha/SetAlphaFromBoolean des Rahmens), je Bild ueber Liquid.SyncFade der Lebensroehre (Nachher-Hooks
-- auf die eigene Liquid-Tabelle) und unabhaengig davon ein gedrosselter Takt (POLL) am eigenen Treiber-Frame, solange das Modell aktiv ist.
--
-- Mini-Vorschau (Preview.lua, P.preview, impl.previewSafe): dasselbe Modell in der Buehne mit der Einheit "player" als Bild. Dort keine
-- eigenen Ereignisse, kein Takt, keine Root-Hooks (s.root = nil), kein arm/Portrait.Fallback (Rueckfall nur lokal: statisches Bild);
-- Pegel aus P.fakeFraction, Tod aus P.fakeDead, Kampf nur ueber React("combat"); Reaktionen kommen ueber React der Buehne.
--
-- Rueckfall: SetUnit in pcall, vorab UnitExists/UnitIsVisible/CanSetUnit. Scheitert es (fremde Einheit in Instanz, ausser Sicht,
-- kein Modell): "model" ueber Portrait.Fallback(id) auf das lebende Gemaelde; "modelplain" zeigt selbst das statische Bild
-- (SetPortraitTexture in die runde P.base). Ein Waechter-Frame versucht es beim naechsten passenden Ereignis (UNIT_MODEL_CHANGED,
-- UNIT_PORTRAIT_UPDATE, Zielwechsel, Zonenwechsel) erneut. Kosten: nur der gedrosselte Takt (alle POLL s, ein paar API-Aufrufe); verborgen/ausgeblendet pausiert, beim Zeigen neu
-- gebunden; Aufrufe und Lua-Zeit in /vials debug.
local _, ns = ...
local Compat = ns.Compat
local Portrait = ns.UnitPortrait
local U = Portrait.Util

local Model = {}
Portrait.Model = Model
local Plain = {}
Portrait.ModelPlain = Plain

-- Kamera: SetPortraitZoom 1 = Kopf bildfuellend (Blizzards 3D-Portraits); etwas weniger Zoom und mehr Abstand, damit Kopf und
-- Schultern auch bei Treffer/Zaubern/Lachen im Kreis bleiben
Model.ZOOM = 0.85
Model.CAM_DISTANCE = 1.25
Model.SIZE = 0.84          -- Kantenlaenge des Modell-Quadrats / Portrait (Ecken unter dem Ringband, Kanten unter der Abdeckung)
Model.COVER_TEX = "Interface\\AddOns\\LucidVials\\Media\\uf-portrait-model-cover"
Model.BACKDROP = { 0.035, 0.04, 0.05, 1 }
Model.VIGNETTE = 0.45      -- Grund-Vignette (x Staerke)
Model.DEAD_DESAT = 1       -- Entsaettigung bei Tod/Geist
Model.LIGHT = { ambient = 0.75, diffuse = 0.8, mix = 0.45, point = { -1, 1, -1 } } -- mix: Anteil Fluessigkeitsfarbe (x Staerke)
-- Animations-IDs je Zweck, in Vorzugsreihenfolge (AnimationData; nur IDs, die HasAnimation bestaetigt, werden gesetzt). Nur Ober-
-- koerper/Stehen: kein Schlaf/Sitzen (71/72), kein Tod/Liegen (1/6), kein Jubel (68, Arme ragen heraus), kein beidhaendiges Wirken (32).
Model.ANIM = {
    stand = { 0 }, combat = { 25, 26 }, hit = { 9, 8 }, crit = { 10, 9, 8 }, heal = { 70, 60 }, precast = { 51, 31 }, cast = { 53 },
}
Model.ALLOWED = {}
for _, list in pairs(Model.ANIM) do
    for _, id in ipairs(list) do Model.ALLOWED[id] = true end
end
Model.REST = { from = 0.12, to = 0.4, secs = 3.2 } -- Ausruhen: Abdunkeln "atmet" (Alpha x Staerke, BOUNCE)
Model.FADE_PAUSE = 0.02    -- wirksames Alpha darunter: Modell pausiert (mit SetModelAlpha nur das; ohne dessen Verbergen)
Model.FADE_SHOW = 0.05     -- nur im Ersatzweg ohne SetModelAlpha: erst darueber wird das verborgene Modell wieder gezeigt (Hysterese)
Model.ALPHA_GAMMA = 2.0    -- Modell-Alpha = Alpha ^ Gamma: das 3D-Modell wirkt bei kleinem Alpha deckender als 2D, > 1 blendet frueher aus
Model.GAMMA_STEPS = 16     -- Stuetzpunkte der Gamma-Kurve (Secret-Weg, C_CurveUtil), linear dazwischen
Model.POLL = 0.05          -- Takt (s) des eigenen Ausblenden-Treibers, unabhaengig von den Liquid-Hooks
-- Sicherheitsnetz: so lange (s) haelt eine kurze Reaktion hoechstens, falls OnAnimFinished nicht kommt
Model.HOLD = { hit = 0.7, crit = 0.9, heal = 1.6, cast = 1.2 }
Model.RETRY_EVENTS = { "UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE", "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA" }
Model.EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_FLAGS" }
Model.PLAYER_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

local CAST_START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true }
local CAST_END = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_FAILED = true }
local MODEL_KEYS = { model = true, modelplain = true }

local call, readFlag = U.call, U.readFlag
local ROOTS = { player = "PlayerFrame", target = "TargetFrame" } -- Rahmen-Wurzeln, die Lucid ausblendet
-- Wurzel -> "secret" | "number" (Art des letzten SetAlpha); letztes Secret-Argument + Boolean-Flag, ob eines vorliegt (nie ein
-- Vergleich oder Wahrheitstest auf dem Secret selbst, auch nicht gegen nil)
local rootKind, hookSecret, hookHasSecret = {}, {}, {}
local hookAlpha, hooked = {}, {} -- Rahmen-Wurzel -> zuletzt per SetAlpha uebergebene lesbare Zahl | Hook haengt
Model.HookAlpha = hookAlpha -- fuer Tests/Diagnose
local live, byTube = {}, {} -- aktive Zustaende (Ausblenden); Lebensroehre -> Zustand
local mstats = { setUnit = 0, fails = 0, fallbacks = 0, retries = 0, anims = 0, events = 0, ms = 0, msMax = 0, n = 0, reason = {} }
Model.stats = mstats
local prof = type(debugprofilestop) == "function" and debugprofilestop or nil

--- Lua-Zeit einer Arbeit messen (gleitender Mittelwert ueber 120 Aufrufe, Spitze)
local function measure(fn, ...)
    local t0 = prof and prof() or nil
    local ok, err = pcall(fn, ...)
    if not ok then U.recordError(err) end
    if t0 then
        local ms = prof() - t0
        mstats.n = mstats.n + 1
        mstats.ms = mstats.ms + (ms - mstats.ms) / math.min(mstats.n, 120)
        if ms > mstats.msMax then mstats.msMax = ms end
    end
end

--- Rueckgabe einer API nur, wenn sie lesbar ist (secret => nil, nie verglichen)
local function plain(v)
    if Compat.IsSecret(v) then return nil end
    return v
end

local function vec3(x, y, z)
    if type(CreateVector3D) == "function" then
        local ok, v = pcall(CreateVector3D, x, y, z)
        if ok and v then return v end
    end
    return { x = x, y = y, z = z }
end

local function color(r, g, b)
    if type(CreateColor) == "function" then
        local ok, c = pcall(CreateColor, r, g, b, 1)
        if ok and c then return c end
    end
    return { r = r, g = g, b = b, a = 1 }
end

-- Einheit ------------------------------------------------------------------------------------------------------------------
--- Kann das Spiel die Einheit als Modell zeigen? (true | false, Grund); nur lesbare Flags, CanSetUnit wirft/liefert false bei Sperre
function Model.CanShow(unit, m)
    if readFlag(UnitExists, unit) ~= true then return false, "none" end
    if unit ~= "player" and readFlag(UnitIsVisible, unit) == false then return false, "range" end
    if m and type(m.CanSetUnit) == "function" then
        local ok, can = pcall(m.CanSetUnit, m, unit)
        if not ok or plain(can) == false then return false, "blocked" end
    end
    return true
end

--- Modell an die Einheit binden (pcall); false + Grund, wenn es scheitert
local function bind(P, s)
    local m = s.model
    local can, why = Model.CanShow(P.unit, m)
    if not can then return false, why end
    mstats.setUnit = mstats.setUnit + 1
    local ok = pcall(m.SetUnit, m, P.unit, true)
    if not ok then return false, "error" end -- SetUnit liefert nichts zurueck: nur der Fehler zaehlt
    s.anim, s.has, s.boundAt, s.secretDone = nil, {}, GetTime(), nil -- neue Bindung: Secret-Alpha erneut setzen
    call(m, "SetPortraitZoom", Model.ZOOM)
    call(m, "SetCamDistanceScale", Model.CAM_DISTANCE)
    call(m, "SetPosition", 0, 0, 0)
    call(m, "SetParticlesEnabled", false)
    return true
end

-- Pause und Ausblenden -------------------------------------------------------------------------------------------------------
--- Pause aus allen Gruenden: ausgeblendet, eingefroren (ohne FreezeAnimation), statisches Bild
local function applyPause(s)
    call(s.model, "SetPaused", (s.faded or s.freezePaused or s.still) and true or false)
end

--- wirksames Alpha aus den Quellen (Roehren-Wurzel, Portrait-Frame, Modell); kleinster lesbarer Wert, sonst nil (alles secret).
--- Zweiter Rueckgabewert: Name der Quelle des Werts (tube/frame/model)
local SRC = { "tube", "frame", "model", "hook" }

--- eine Quelle lesen und je Quelle festhalten, was sie lieferte (zahl/secret/fehler/keine/nil); secret der Roehre/des Frames merkt
--- s.secretA fuer das Durchreichen (nie das des Modells selbst)
local function readOne(s, i, obj, best, src)
    local r = s.rd[i]
    local ok, a = call(obj, "GetEffectiveAlpha")
    r.v = nil
    if not ok then
        r.k = type(a) == "nil" and "keine" or "fehler" -- a ist hier nur die Fehlermeldung des pcall
    elseif Compat.IsSecret(a) then
        r.k = "secret"
        if i < 3 and not s.hasSecretA then s.secretA, s.hasSecretA = a, true end
    else
        local n = Compat.Num(a)
        if n then
            r.k, r.v = "zahl", n
            if best == nil or n < best then return n, SRC[i] end
        else
            r.k = "nil"
        end
    end
    return best, src
end

local function readFade(s)
    s.secretA, s.hasSecretA = nil, false
    local best, src = readOne(s, 1, s.tube and s.tube.root, nil, nil)
    best, src = readOne(s, 2, s.frame, best, src)
    -- das Modell selbst nur, solange wir seinen Frame-Alpha nicht setzen (Ersatzweg SetAlpha wuerde sich sonst selbst mitlesen)
    if s.hasModelAlpha then
        best, src = readOne(s, 3, s.model, best, src)
    else
        s.rd[3].k, s.rd[3].v = "uebersprungen", nil
    end
    local r, h = s.rd[4], s.root and hookAlpha[s.root] or nil
    if h then
        r.k, r.v = "zahl", h
        if best == nil or h < best then best, src = h, "hook" end
    else
        r.k, r.v = best == nil and "keine-zahl" or "keine", nil -- alles unlesbar und nie eine Zahl per SetAlpha gesehen
    end
    return best, src
end

-- Gamma-Kurve y = x ^ Gamma fuer Secrets (Zahlen rechnet Lua selbst): einmal je Gamma angelegt; false = keine Kurve moeglich
local gammaCurves, curveDenied = {}, false
local function gammaCurve(g)
    if g == 1 then return nil end
    local c = gammaCurves[g]
    if c == nil then
        c = false
        local C = _G.C_CurveUtil
        if C and type(C.CreateCurve) == "function" then
            local ok, cv = pcall(C.CreateCurve)
            if ok and (type(cv) == "table" or type(cv) == "userdata") then
                local linear = type(Enum) == "table" and type(Enum.LuaCurveType) == "table" and Enum.LuaCurveType.Linear or 0
                pcall(cv.SetType, cv, linear)
                for i = 0, Model.GAMMA_STEPS do
                    local x = i / Model.GAMMA_STEPS
                    pcall(cv.AddPoint, cv, x, x ^ g)
                end
                c = cv
            end
        end
        gammaCurves[g] = c
    end
    return c or nil
end

--- Secret durch die Gamma-Kurve schicken (nur durchgereicht, nie verglichen): liefert das Ergebnis und "kurve"; ohne Kurve/bei
--- Ablehnung des Clients das rohe Secret und "roh"/"abgelehnt" (curveDenied: nie wieder versucht)
local function gammaSecret(a)
    local g = Model.ALPHA_GAMMA
    if g ~= 1 and not curveDenied then
        local cv = gammaCurve(g)
        if cv then
            local okE, y = pcall(cv.Evaluate, cv, a)
            if okE then return y, "kurve" end
            curveDenied = true
            return a, "abgelehnt"
        end
    end
    return a, "roh"
end

--- alles unlesbar: ein secret der Roehre/des Frames einmal an SetModelAlpha reichen (pcall); abgewiesen => nie wieder versuchen
local function passSecret(s)
    if s.hasSecretA and s.hasModelAlpha and not s.passDenied then
        local y, how = gammaSecret(s.secretA) -- Gamma wie im Hook (applySecret), mit demselben Rueckfall
        s.gammaVia = how
        if pcall(s.model.SetModelAlpha, s.model, y) then
            s.way, s.passOk, s.alpha = "secret-durchgereicht", s.passOk + 1, nil -- Alpha unbekannt: naechste Zahl setzt sicher neu
        else
            s.way, s.passFail, s.passDenied = "secret-abgelehnt", s.passFail + 1, true
        end
    else
        s.way = s.hasSecretA and "secret-abgelehnt" or "keiner"
    end
    s.secretA, s.hasSecretA = nil, false
end

--- Secret-Alpha der Wurzel (Lucids Kurvenmodus: SetAlpha(UnitHealthPercent(..)) gelingt aus Addon-Code) unveraendert an das Modell
--- reichen (keine Rechnung, kein Vergleich): erst SetModelAlpha, sonst SetAlpha am eigenen Modell-Frame. Das Modell bleibt gezeigt
--- und entpausiert, nur sein Alpha traegt das Ausblenden (kein Hide/Hysterese, die Zahl ist unbekannt)
local function applySecret(s, a)
    if not s.active or s.still then return end -- a ist immer ein vorhandenes Secret (Aufrufer pruefen das Flag, nie das Secret)
    s.secretDone, s.alpha = true, nil
    if s.fadeHidden then
        s.fadeHidden = nil
        s.model:Show() -- OnShow bindet neu; syncFade tut im Secret-Zweig nichts mehr
    end
    if s.faded then
        s.faded = false
        applyPause(s)
    end
    local how
    a, how = gammaSecret(a) -- Gamma auch fuer das Secret (Kurve), sonst roh
    s.gammaVia = how
    if s.hasModelAlpha and pcall(s.model.SetModelAlpha, s.model, a) then
        s.via, s.secPassOk = "modelalpha", s.secPassOk + 1
        if s.viaFrame then call(s.model, "SetAlpha", 1) s.viaFrame = nil end
    elseif pcall(s.model.SetAlpha, s.model, a) then
        s.via, s.viaFrame, s.secPassOk = "alpha", true, s.secPassOk + 1
    else
        s.via, s.secPassFail = "-", s.secPassFail + 1
    end
end

--- wirksames Alpha (nur lesbar) als Modell-Alpha; fast unsichtbar => pausiert und verborgen
local function syncFade(s)
    if not s.active or s.still then return end
    s.nSync = s.nSync + 1
    if rootKind[s.root] == "secret" then -- letztes SetAlpha der Wurzel war secret: nichts mit "letzter Zahl" ueberschreiben
        s.way = "secret-hook"
        if not s.secretDone and hookHasSecret[s.root] then applySecret(s, hookSecret[s.root]) end -- nach neuer Bindung/Aktivierung erneut setzen
        return
    end
    local a, src = readFade(s)
    s.src, s.srcAlpha = src, a
    if a == nil then -- secret/unlesbar: Durchreichen versuchen, sonst bleibt der letzte Stand
        passSecret(s)
        return
    end
    s.way = "zahl"
    a = math.max(0, math.min(1, a))
    if s.alpha == a then return end
    s.alpha = a
    local g = Model.ALPHA_GAMMA
    local ma = g ~= 1 and a ^ g or a -- Zahlen rechnet Lua selbst; Secrets laufen im Hook ueber die Gamma-Kurve (applySecret)
    if s.hasModelAlpha then
        call(s.model, "SetModelAlpha", ma)
    else
        call(s.model, "SetAlpha", ma) -- Ersatz ohne SetModelAlpha (nur dann: sonst verblasst die Eltern-Kette doppelt)
    end
    -- Pause ohne Hysterese: schon beim ersten sichtbaren Schritt laeuft die Animation wieder (kein eingefrorenes Einblenden)
    local faded = a < Model.FADE_PAUSE
    if faded ~= (s.faded or false) then
        s.faded = faded
        applyPause(s)
    end
    if s.hasModelAlpha then return end -- SetModelAlpha(0) genuegt: kein Hide, kein Neubinden beim Einblenden
    -- Ersatzweg ohne SetModelAlpha: nur Verbergen hilft (mit Hysterese), Show bindet neu
    local hide = s.fadeHidden or false
    if a < Model.FADE_PAUSE then hide = true elseif a > Model.FADE_SHOW then hide = false end
    if hide and not s.fadeHidden then
        s.fadeHidden = true
        s.model:Hide() -- nur das eigene Modell; OnHide pausiert
    elseif not hide and s.fadeHidden then
        s.fadeHidden = nil
        s.model:Show() -- OnShow bindet neu (Refresh) und ruft syncFade erneut: unveraendertes Alpha tut nichts
    end
end

--- eigener Takt (unabhaengig von Liquid-Hooks): am Treiber-Frame, nicht am Modell (Hide stoppt dessen OnUpdate)
local function drive(s, on)
    if not s.drv then return end
    s.acc = 0
    s.drv:SetScript("OnUpdate", on and s.tick or nil)
end

--- Nachher-Hook auf SetAlpha der Rahmen-Wurzel (einmal je Wurzel; wirkt nur auf aktive Modelle dieser Wurzel)
local hookInfo = {} -- Rahmen-Wurzel -> Diagnose fuer /vials debug (hookOk, calls, last, bool)
local function hookRoot(root)
    if root == nil or hooked[root] then return end
    local info = hookInfo[root] or { ok = false, boolOk = false, calls = 0, num = 0, sec = 0, bool = 0, lastK = "-" }
    hookInfo[root] = info
    if type(hooksecurefunc) ~= "function" then return end
    local function sync(self)
        for s in pairs(live) do
            if s.root == self then measure(syncFade, s) end
        end
    end
    local okH = pcall(hooksecurefunc, root, "SetAlpha", function(self, a)
        local n = Compat.Num(a)
        info.calls = info.calls + 1
        if n then
            info.num, info.lastNum, info.lastAt = info.num + 1, n, GetTime()
            hookAlpha[self] = n
            if rootKind[self] == "secret" then -- zurueck von Secret zu Zahl: Modelle neu setzen (Frame-Alpha-Ersatz zuruecknehmen)
                for s in pairs(live) do
                    if s.root == self then
                        if s.viaFrame then call(s.model, "SetAlpha", 1) s.viaFrame = nil end
                        s.secretDone, s.alpha = nil, nil
                    end
                end
            end
            rootKind[self], hookSecret[self], hookHasSecret[self] = "number", nil, false
        else
            -- secret/Nicht-Zahl: die gemerkte Zahl bleibt (Lucid korrigiert fremde Werte per Zahl zurueck); nur zaehlen, den ersten
            -- Aufrufer einmalig festhalten (Diagnose: wer setzt das Secret?)
            info.sec = info.sec + 1
            if info.secFrom == nil and type(debugstack) == "function" then
                local okS, st = pcall(debugstack, 3, 2, 0)
                if okS and type(st) == "string" and not Compat.IsSecret(st) then
                    info.secFrom = st:gsub("%s*[\r\n]+%s*", " | "):sub(1, 160)
                else
                    info.secFrom = "?"
                end
            end
        end
        if Compat.IsSecret(a) then
            rootKind[self], hookSecret[self], hookHasSecret[self] = "secret", a, true
            for s in pairs(live) do
                if s.root == self then measure(applySecret, s, a) end
            end
        end
        info.lastK, info.lastV = Compat.IsSecret(a) and "secret" or (n and "zahl" or type(a)), n
        sync(self)
    end)
    info.ok = okH
    if okH then
        hooked[root] = true
        local ok, a = call(root, "GetAlpha")
        hookAlpha[root] = ok and Compat.Num(a) or nil -- Ausgangswert, solange noch kein SetAlpha kam
        if type(root.SetAlphaFromBoolean) == "function" then
            info.boolOk = (pcall(hooksecurefunc, root, "SetAlphaFromBoolean", function() -- Wert unbekannt: Zahl bleibt, nur zaehlen
                info.bool = info.bool + 1
            end))
        end
    end
end

for _, name in pairs(ROOTS) do hookRoot(_G[name]) end -- sofort (vor PLAYER_LOGIN); fehlt der Frame, holt activate es nach

function Model.SyncFadeAll()
    for s in pairs(live) do measure(syncFade, s) end
end

local Liquid = ns.Liquid
if Liquid and type(hooksecurefunc) == "function" then -- Nachher-Hooks auf die eigene Liquid-Tabelle (keine Blizzard-Funktion)
    if type(Liquid.SyncFadeAll) == "function" then pcall(hooksecurefunc, Liquid, "SyncFadeAll", Model.SyncFadeAll) end
    if type(Liquid.SyncFade) == "function" then
        pcall(hooksecurefunc, Liquid, "SyncFade", function(lb)
            local s = byTube[lb]
            if s then measure(syncFade, s) end
        end)
    end
end

-- Waechter: nach einem Rueckfall beim naechsten passenden Ereignis erneut versuchen ------------------------------------------
local armed, watcher = {}, nil

--- gewaehlter Modell-Stil des Rahmens (oder nil)
local function wantedKey(id)
    local ok, c = pcall(ns.UnitFrameSkin.GetFrameConfig, id)
    local p = ok and type(c) == "table" and c.portrait or nil
    local key = type(p) == "table" and p.style or nil
    return MODEL_KEYS[key] and key or nil
end

local function stateOf(id)
    local sk = ns.UnitFrameSkin.Get(id)
    local P = sk and sk.pfx
    return P, P and P.s and P.s.model
end

local function retry(id)
    local key = wantedKey(id)
    if not key then armed[id] = nil return end
    local P, s = stateOf(id)
    local still = s and s.active and s.still
    if Portrait.ActiveKey(id) == key and not still then armed[id] = nil return end
    if not Model.CanShow(Portrait.UNIT[id]) then return end
    mstats.retries = mstats.retries + 1
    armed[id] = nil
    if still then
        Model.Refresh(P) -- schlicht: das statische Bild war der eigene Rueckfall
    else
        Portrait.Fallback(id, false)
    end
end

local function onWatch(_, event, unit)
    mstats.events = mstats.events + 1
    local ids = {} -- erst sammeln: ein Versuch kann ueber Usable neue Rahmen scharf schalten
    for id in pairs(armed) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local u = Portrait.UNIT[id]
        local unitEvent = event == "UNIT_MODEL_CHANGED" or event == "UNIT_PORTRAIT_UPDATE"
        if not unitEvent or (type(unit) == "string" and not Compat.IsSecret(unit) and unit == u) then measure(retry, id) end
    end
    if next(armed) == nil and watcher then
        for _, ev in ipairs(Model.RETRY_EVENTS) do pcall(watcher.UnregisterEvent, watcher, ev) end
    end
end

local function arm(id)
    armed[id] = true
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", onWatch)
    end
    for _, ev in ipairs(Model.RETRY_EVENTS) do pcall(watcher.RegisterEvent, watcher, ev) end
end
function Model.IsArmed(id) return armed[id] == true end

--- schlicht: statisches Bild (wie Blizzards Portrait) in der runden P.base statt des Modells; false = zurueck zum Modell
local function still(P, s, on)
    s.still = on or nil
    for _, t in ipairs(s.base) do -- Grund/Abdeckung liegen auf derselben Ebene wie P.base: im statischen Bild weg damit
        if on then t:Hide() else t:Show() end
    end
    if on then
        call(s.model, s.hasModelAlpha and "SetModelAlpha" or "SetAlpha", 0)
        if type(SetPortraitTexture) == "function" then pcall(SetPortraitTexture, P.base, P.unit, true) end
        call(P.base, "Show")
    else
        call(P.base, "Hide")
        s.alpha = nil -- Ausblenden neu nachfuehren
    end
    applyPause(s)
end

--- Rueckfall: "model" auf das lebende Gemaelde (Portrait.lua wendet den Rahmen neu an; Deactivate raeumt das Modell ab),
--- "modelplain" auf das statische Bild im eigenen Rahmen
local function fallBack(P, s, why)
    if P.preview then -- Mini-Vorschau: Rueckfall nur lokal (statisches Bild in der Buehne), kein arm, kein Rueckfall am echten Rahmen
        still(P, s, true)
        return
    end
    mstats.fails = mstats.fails + 1
    mstats.fallbacks = mstats.fallbacks + 1
    mstats.reason[P.id] = why
    arm(P.id)
    if s.plain then
        still(P, s, true)
    else
        Portrait.Fallback(P.id)
    end
end

-- Animationen --------------------------------------------------------------------------------------------------------------
--- erste erlaubte ID der Liste, die das Modell hat (HasAnimation lesbar true); Ergebnis je Bindung zwischengespeichert
local function pick(s, list)
    local m = s.model
    if type(m.HasAnimation) ~= "function" or type(list) ~= "table" then return nil end
    for _, id in ipairs(list) do
        if Model.ALLOWED[id] then
            local has = s.has[id]
            if has == nil then
                local ok, v = pcall(m.HasAnimation, m, id)
                has = ok and plain(v) == true
                s.has[id] = has
            end
            if has then return id end
        end
    end
    return nil
end

local function setAnim(s, id)
    mstats.anims = mstats.anims + 1
    s.anim = id
    call(s.model, "SetAnimation", id)
end

--- Tod/Geist: Stehen eingefroren (kein Liegen); ohne FreezeAnimation haelt die Pause das Bild an
local function freeze(s)
    if s.frozen then return end
    s.frozen = true
    local id = pick(s, Model.ANIM.stand)
    local ok = false
    if id ~= nil and type(s.model.FreezeAnimation) == "function" then
        mstats.anims = mstats.anims + 1
        ok = (pcall(s.model.FreezeAnimation, s.model, id, 0, 0))
    end
    s.freezePaused = not ok
    s.anim = nil
    applyPause(s)
end

local function unfreeze(s)
    if not s.frozen then return end
    s.frozen, s.freezePaused, s.anim = false, false, nil
    applyPause(s)
end

--- Ausruhen: Abdunkeln "atmet" langsam (Engine-Animation), sonst aus
local function setDim(P, s, on)
    local i = P.cfg and P.cfg.intensity or 0
    on = (on and i > 0) and true or false
    if on == (s.dimOn or false) then return end
    s.dimOn = on
    call(s.dimFx, "Stop")
    if on then
        local R = Model.REST
        call(s.dimAnim, "SetFromAlpha", R.from * i)
        call(s.dimAnim, "SetToAlpha", R.to * i)
        call(s.dimAnim, "SetDuration", R.secs)
        s.dim:SetAlpha(R.from * i)
        call(s.dimFx, "Play")
    else
        s.dim:SetAlpha(0)
    end
end

--- Ruhezustand: tot/Geist > zaubert > Kampf > ruht (nur Spieler) > steht; schlicht immer stehen
local function baseKind(P, s)
    if s.plain then return "stand" end
    if s.dead or s.ghost then return "dead" end
    if s.casting then return "precast" end
    if s.combat or s.testCombat then return "combat" end
    if P.calm then return "rest" end
    return "stand"
end

--- zur Ruheanimation des Zustands zurueck (nur, wenn sie sich aendert oder eine Reaktion endet)
local function settle(P, s)
    s.react = nil
    local kind = baseKind(P, s)
    s.kind = kind
    setDim(P, s, kind == "rest")
    if kind == "dead" then
        freeze(s)
        return
    end
    unfreeze(s)
    local id = pick(s, Model.ANIM[kind]) or pick(s, Model.ANIM.stand)
    if id ~= nil and id ~= s.anim then setAnim(s, id) end
end

--- kurze Reaktion (Treffer, Heilung, Zaubern); kehrt ueber OnAnimFinished oder spaetestens nach HOLD zurueck
local function react(P, s, kind)
    if s.plain or s.dead or s.ghost or (P.cfg and P.cfg.intensity or 0) <= 0 then return false end
    local id = pick(s, Model.ANIM[kind])
    if id == nil then return false end
    s.epoch = (s.epoch or 0) + 1
    s.react = kind
    setAnim(s, id)
    local epoch = s.epoch
    C_Timer.After(Model.HOLD[kind] or 1, function()
        if s.epoch == epoch and s.react then measure(settle, P, s) end
    end)
    return true
end

-- Aufbau -------------------------------------------------------------------------------------------------------------------
local function overlay(s, sub, path, r, g, b)
    local t = s.model:CreateTexture(nil, "OVERLAY", nil, sub)
    if path then t:SetTexture(path) end
    U.addMask(t, s.mask)
    if r then t:SetVertexColor(r, g, b) end
    return t
end

local function build(P)
    local s = { has = {} }
    local m = CreateFrame("PlayerModel", nil, P.frame)
    s.model, s.frame = m, P.frame
    s.hasModelAlpha = type(m.SetModelAlpha) == "function"
    s.rd = { { k = "-" }, { k = "-" }, { k = "-" }, { k = "-" } } -- je Quelle: was GetEffectiveAlpha zuletzt lieferte (nur fuer /vials debug)
    s.way, s.nSync, s.nTick, s.passOk, s.passFail = "-", 0, 0, 0, 0
    s.via, s.secPassOk, s.secPassFail = "-", 0, 0
    s.drv = CreateFrame("Frame")
    s.tick = function(_, dt)
        s.acc = (s.acc or 0) + (Compat.Num(dt) or 0)
        if s.acc < Model.POLL then return end
        s.acc = 0
        s.nTick = s.nTick + 1
        measure(syncFade, s)
    end
    call(m, "SetModelDrawLayer", "ARTWORK")
    s.mask = U.newMask(m)
    s.back = m:CreateTexture(nil, "BACKGROUND")
    local B = Model.BACKDROP
    s.back:SetColorTexture(B[1], B[2], B[3], B[4])
    U.addMask(s.back, s.mask)
    local T, C = Portrait.TEX, Portrait.PAINT
    s.blood = overlay(s, 0, T.vignette, C.bloodColor[1], C.bloodColor[2], C.bloodColor[3])
    s.vig = overlay(s, 1, T.vignette)
    s.cracks = overlay(s, 2, T.cracks)
    s.heavy = overlay(s, 3, T.crackHeavy) -- starke Risse: sehr wenig Leben
    s.heal = overlay(s, 4, T.heal, C.healColor[1], C.healColor[2], C.healColor[3])
    call(s.heal, "SetBlendMode", "ADD")
    s.hit = overlay(s, 5, T.vignette, C.hitColor[1], C.hitColor[2], C.hitColor[3])
    s.dim = overlay(s, 6, nil)
    s.dim:SetColorTexture(0, 0, 0, 1)
    -- Abdeckung zuoberst (ohne Maske: die Textur traegt die Kreisform selbst), Farbe des Glas-Grundes
    s.cover = m:CreateTexture(nil, "OVERLAY", nil, 7)
    s.cover:SetTexture(Model.COVER_TEX)
    s.cover:SetVertexColor(B[1], B[2], B[3])
    s.base = { s.back, s.cover }                                         -- beide Stile
    s.fx = { s.blood, s.vig, s.cracks, s.heavy, s.heal, s.hit, s.dim }   -- nur "model"
    s.overlays = { s.back, s.blood, s.vig, s.cracks, s.heavy, s.heal, s.hit, s.dim, s.cover }
    for _, t in ipairs(s.fx) do t:SetAlpha(0) end
    s.healFx, s.hitFx = U.flashGroup(s.heal), U.flashGroup(s.hit)
    local okG, g = pcall(s.dim.CreateAnimationGroup, s.dim)
    if okG and type(g) == "table" then
        s.dimFx = g
        call(g, "SetLooping", "BOUNCE")
        local okA, a = pcall(g.CreateAnimation, g, "Alpha")
        s.dimAnim = okA and a or nil
        call(s.dimAnim, "SetSmoothing", "IN_OUT")
    end
    m:SetScript("OnAnimFinished", function()
        if s.react then measure(settle, P, s) end
    end)
    -- verborgen: nichts zu zeichnen, Animation anhalten; gezeigt: neu binden (der Client kann das Modell beim Verbergen leeren)
    m:SetScript("OnHide", function() call(m, "SetPaused", true) end)
    m:SetScript("OnShow", function()
        if not s.active or s.boundAt == GetTime() then
            applyPause(s)
            return
        end
        measure(Model.Refresh, P)
    end)
    m:Hide()
    return s
end

local function tint(P, s)
    local L, i = Model.LIGHT, P.cfg and P.cfg.intensity or 0
    local r, g, b = U.liquidColor(P) -- lesbare Zahlen (Skin.TINTS), nie Secrets
    local k = s.plain and 0 or L.mix * i -- schlicht: neutrales Licht
    local cr, cg, cb = 1 + (r - 1) * k, 1 + (g - 1) * k, 1 + (b - 1) * k
    s.light = { cr, cg, cb }
    call(s.model, "SetLight", true, { omnidirectional = false, point = vec3(L.point[1], L.point[2], L.point[3]),
        ambientIntensity = L.ambient, ambientColor = color(cr, cg, cb), diffuseIntensity = L.diffuse,
        diffuseColor = color(cr, cg, cb) })
end

--- wenig Leben: Risse und Roete per Kurven-Alpha (secret-sicher, wie das lebende Gemaelde); lesbar rechnet Lua dieselbe Kurve
local function updateLow(P, s)
    if s.plain then return end
    local i, C = P.cfg.intensity, Portrait.PAINT
    if P.testLow then
        s.cracks:SetAlpha(C.testLow * i)
        s.heavy:SetAlpha(C.testLow * i)
        s.blood:SetAlpha(C.testLow * i * C.blood[1][2])
        return
    end
    local frac = P.fakeFraction -- Mini-Vorschau: eigene, lesbare Zahl 0..1 statt Einheit/Kurve
    if frac == nil then
        local cc, bc, hc = U.curvesFor(i)
        local okC = U.curveAlpha(s.cracks, P.unit, cc)
        local okB = U.curveAlpha(s.blood, P.unit, bc)
        local okH = U.curveAlpha(s.heavy, P.unit, hc)
        if okC and okB and okH then return end
        frac = U.readableFraction(P.unit)
    end
    if frac then
        s.cracks:SetAlpha(U.evalPoints(C.cracks, frac) * i)
        s.heavy:SetAlpha(U.evalPoints(C.heavy, frac) * i)
        s.blood:SetAlpha(U.evalPoints(C.blood, frac) * i)
    else
        s.cracks:SetAlpha(0)
        s.heavy:SetAlpha(0)
        s.blood:SetAlpha(0)
    end
end

--- Tod/Geist (lesbare Flags): grau und eingefroren (schlicht: nichts davon)
local function updateDead(P, s, forceDead)
    local ghost, dead
    if P.preview then -- Mini-Vorschau: die Einheit "player" ist nur das Bild, Tod aus dem eigenen Schalter
        ghost, dead = false, P.fakeDead == true
    else
        ghost = readFlag(UnitIsGhost, P.unit) == true
        dead = not ghost and (forceDead == true or readFlag(UnitIsDead, P.unit) == true)
        -- Clients ohne UnitIsDead/UnitIsGhost: UnitIsDeadOrGhost zaehlt als Tod
        if not (dead or ghost) and readFlag(UnitIsDeadOrGhost, P.unit) == true then dead = true end
    end
    if s.plain then dead, ghost = false, false end
    local changed = s.dead ~= dead or s.ghost ~= ghost
    s.dead, s.ghost = dead, ghost
    call(s.model, "SetDesaturation", (dead or ghost) and Model.DEAD_DESAT or 0)
    for _, t in ipairs({ s.vig, s.cracks, s.heavy, s.blood }) do U.setDesaturated(t, dead or ghost) end
    return changed
end

local function readCombat(P)
    if P.preview then return false end -- Vorschau: Kampf nur ueber das Testwort (testCombat)
    return readFlag(UnitAffectingCombat, P.unit) == true
end

-- Ereignisse des Modells (je Rahmen, nur solange "model" aktiv ist) ----------------------------------------------------------
local function onModelEvent(P, s, event, unit)
    if not s.active or s.plain then return end
    mstats.events = mstats.events + 1
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        s.combat = event == "PLAYER_REGEN_DISABLED"
        if not s.react then settle(P, s) end
        return
    end
    if type(unit) ~= "string" or Compat.IsSecret(unit) or unit ~= P.unit then return end
    if CAST_START[event] then
        s.casting = true
        s.react = nil
        settle(P, s)
    elseif CAST_END[event] then
        if s.casting then
            s.casting = false
            settle(P, s)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        s.casting = false
        if not react(P, s, "cast") then settle(P, s) end
    elseif event == "UNIT_FLAGS" then
        local c = readCombat(P)
        if c ~= s.combat then
            s.combat = c
            if not s.react then settle(P, s) end
        end
    end
end

local function listen(P, s, on)
    if not s.ev then
        s.ev = CreateFrame("Frame")
        s.ev:SetScript("OnEvent", function(_, event, unit) measure(onModelEvent, P, s, event, unit) end)
    end
    local f = s.ev
    for _, ev in ipairs(Model.EVENTS) do
        if on then
            if not pcall(f.RegisterUnitEvent, f, ev, P.unit) then pcall(f.RegisterEvent, f, ev) end
        else
            pcall(f.UnregisterEvent, f, ev)
        end
    end
    if P.unit == "player" then
        for _, ev in ipairs(Model.PLAYER_EVENTS) do
            if on then pcall(f.RegisterEvent, f, ev) else pcall(f.UnregisterEvent, f, ev) end
        end
    end
    s.listening = on
end

-- Stil-Schnittstelle ------------------------------------------------------------------------------------------------------
--- vor dem Anwenden: false => Portrait.lua nimmt das lebende Gemaelde (und der Waechter versucht es spaeter erneut)
function Model.Usable(P)
    if not (P and Portrait.UNIT[P.id]) then return false end
    if P.preview then return true end -- Vorschau: scheitert das Modell, zeigt Refresh lokal das statische Bild (kein arm)
    local s = P.s and P.s.model
    local ok, why = Model.CanShow(P.unit, s and s.model or nil)
    if not ok then
        mstats.reason[P.id] = why
        arm(P.id)
        return false
    end
    return true
end

local function activate(P, cfg, isPlain)
    if not Portrait.UNIT[P.id] then return end -- Ziel des Ziels: nie
    local s = P.s.model
    if not s then
        s = build(P)
        P.s.model = s
    end
    P.cfg = cfg
    s.plain, s.preview = isPlain, P.preview == true
    s.active = false -- OnShow bindet erst, wenn alles steht (Refresh unten)
    s.combat = readCombat(P)
    s.casting, s.testCombat, s.react, s.still, s.alpha, s.faded = false, false, nil, nil, nil, false
    s.fadeHidden, s.src, s.srcAlpha, s.passDenied, s.secretDone = nil, nil, nil, nil, nil
    s.tube = P.sk and P.sk.health or nil
    local rootName = not P.preview and ROOTS[P.id] or nil -- Vorschau: keine Root-Kopplung an PlayerFrame/TargetFrame
    s.root = rootName and type(_G[rootName]) == "table" and _G[rootName] or (not P.preview and P.sk and P.sk.root) or nil
    hookRoot(s.root)
    P.calm = not P.preview and P.unit == "player" and readFlag(IsResting) == true or false
    call(P.base, "Hide") -- die 2D-Portrait-Textur des Rahmens bleibt leer (kein heller Hintergrund); das Modell zeichnet
    for _, t in ipairs(s.base) do t:Show() end
    for _, t in ipairs(s.fx) do
        if isPlain then t:Hide() else t:Show() end
    end
    Model.Layout(P)
    s.model:Show()
    s.active = true
    live[s] = true
    if s.tube then byTube[s.tube] = s end
    if not P.preview then -- Vorschau: kein eigener Takt, keine eigenen Ereignisse (Reaktionen kommen ueber React der Buehne)
        drive(s, true)
        if not isPlain then listen(P, s, true) end
    end
    Model.Configure(P, cfg)
    Model.Refresh(P)
end

function Model.Activate(P, cfg) activate(P, cfg, false) end

function Model.Deactivate(P)
    local s = P.s.model
    call(P.base, "Show")
    if not s then return end
    s.active = false
    live[s] = nil
    drive(s, false)
    for lb, x in pairs(byTube) do
        if x == s then byTube[lb] = nil end
    end
    s.epoch = (s.epoch or 0) + 1 -- offene Rueckkehr-Timer verfallen
    s.react, s.casting, s.testCombat, s.anim, s.still = nil, false, false, nil, nil
    s.frozen, s.freezePaused, s.faded, s.alpha, s.fadeHidden, s.src, s.srcAlpha = false, false, false, nil, nil, nil, nil
    setDim(P, s, false)
    if s.ev then listen(P, s, false) end
    call(s.healFx.g, "Stop")
    call(s.hitFx.g, "Stop")
    for _, t in ipairs(s.overlays) do t:Hide() end
    call(s.model, "SetDesaturation", 0)
    call(s.model, "SetModelAlpha", 1)
    if not s.hasModelAlpha or s.viaFrame then call(s.model, "SetAlpha", 1) end
    s.viaFrame, s.secretDone, s.via = nil, nil, "-"
    call(s.model, "ClearModel")
    s.model:Hide()
    P.testLow = nil
end

function Model.Layout(P)
    local s = P.s.model
    if not s then return end
    local size = P.size or 40
    local m, edge = s.model, math.max(4, math.floor(size * Model.SIZE + 0.5))
    m:ClearAllPoints()
    m:SetPoint("CENTER", P.frame, "CENTER", 0, 0)
    m:SetSize(edge, edge)
    local okL, lvl = call(P.frame, "GetFrameLevel")
    lvl = okL and Compat.Num(lvl) or nil
    if lvl then m:SetFrameLevel(lvl) end -- gleiche Ebene wie der Portrait-Rahmen: Glanz und Ring bleiben darueber
    if s.mask then
        s.mask:ClearAllPoints()
        s.mask:SetPoint("CENTER", m, "CENTER", 0, 0)
        s.mask:SetSize(size, size)
    end
    for _, t in ipairs(s.overlays) do -- Texturen duerfen ueber den Modell-Frame hinausragen: voller Kreis
        t:ClearAllPoints()
        t:SetPoint("CENTER", m, "CENTER", 0, 0)
        t:SetSize(size, size)
    end
end

function Model.Configure(P, cfg)
    local s = P.s.model
    if not s then return end
    P.cfg = cfg
    s.vig:SetAlpha(s.plain and 0 or Model.VIGNETTE * cfg.intensity)
    tint(P, s)
    updateLow(P, s)
    if s.dimOn then -- Staerke geaendert: Abdunkeln neu starten
        setDim(P, s, false)
        settle(P, s)
    end
end

--- Einheit neu (Zielwechsel, UNIT_MODEL_CHANGED/UNIT_PORTRAIT_UPDATE, Zeigen): neu binden, sonst Rueckfall
function Model.Refresh(P)
    local s = P.s.model
    if not (s and s.active) then return end
    local ok, why = bind(P, s)
    if not ok then
        fallBack(P, s, why)
        return
    end
    if s.still then still(P, s, false) end
    mstats.reason[P.id] = nil
    s.frozen, s.freezePaused = false, false -- neue Bindung: die Animation laeuft neu
    applyPause(s)
    s.combat = readCombat(P)
    updateDead(P, s)
    tint(P, s)
    updateLow(P, s)
    settle(P, s)
    syncFade(s)
end

function Model.OnHealth(P)
    local s = P.s.model
    if not (s and s.active) or s.still then return end
    updateLow(P, s)
    if updateDead(P, s) then settle(P, s) end -- Tod/Wiederbelebung des Ziels (Spieler: PLAYER_DEAD/ALIVE ueber React)
end

function Model.Tint(P)
    local s = P.s.model
    if s and s.active then tint(P, s) end
end

function Model.TestLow(P, on)
    local s = P.s.model
    P.testLow = on and true or nil
    if s and s.active then updateLow(P, s) end
end

function Model.React(P, what, arg)
    local s = P.s.model
    if not (s and s.active) or s.plain or s.still then return end
    local i = P.cfg and P.cfg.intensity or 0
    if what == "hit" then
        U.flash(s.hitFx, "hit", i, arg)
        react(P, s, arg and "crit" or "hit")
    elseif what == "heal" then
        U.flash(s.healFx, "heal", i, arg)
        react(P, s, "heal")
    elseif what == "cast" then
        react(P, s, "cast")
    elseif what == "combat" then
        s.testCombat = arg and true or false
        if not s.react then settle(P, s) end
    elseif what == "rest" then
        P.calm = (P.unit == "player" and arg) and true or false
        if not s.react then settle(P, s) end
    elseif what == "dead" then
        updateDead(P, s, arg == true or nil) -- PLAYER_DEAD kann vor den Flags kommen; sonst gelten die Flags
        settle(P, s)
    elseif what == "reset" then
        s.testCombat, s.casting = false, false
        s.combat = readCombat(P)
        settle(P, s)
    end
end

--- eine Zeile je Quelle fuer /vials debug: tube:zahl(0.400)/frame:secret/model:keine
local function readText(s)
    if not (s and s.rd) then return "-" end
    local out = {}
    for i, r in ipairs(s.rd) do
        out[i] = SRC[i] .. ":" .. r.k .. (r.v and string.format("(%.3f)", r.v) or "")
    end
    return table.concat(out, "/")
end

function Model.Debug()
    local yn = function(b) return b and ns.L.NP_YES or ns.L.NP_NO end
    for _, id in ipairs({ "player", "target" }) do
        local _, s = stateOf(id)
        ns.Print("frames.portrait.model.%s active=%s plain=%s anim=%s state=%s alpha=%s src=%s srcAlpha=%s setModelAlpha=%s hidden=%s rd=%s way=%s syncs=%d ticks=%d pass=%d/%d rkind=%s via=%s secPass=%d/%d gamma=%.2f/%s armed=%s fallback=%s",
            id, yn(s and s.active), yn(s and s.plain), tostring(s and s.anim or "-"), tostring(s and s.kind or "-"),
            tostring(s and s.alpha or "-"), tostring(s and s.src or "-"), tostring(s and s.srcAlpha or "-"),
            yn(s and s.hasModelAlpha), yn(s and s.fadeHidden), readText(s), tostring(s and s.way or "-"), s and s.nSync or 0,
            s and s.nTick or 0, s and s.passOk or 0, s and s.passFail or 0, tostring(rootKind[_G[ROOTS[id]] or false] or "-"),
            tostring(s and s.via or "-"), s and s.secPassOk or 0, s and s.secPassFail or 0, Model.ALPHA_GAMMA, tostring(s and s.gammaVia or "-"), yn(armed[id]),
            tostring(mstats.reason[id] or (s and s.still and "still") or "-"))
    end
    -- harte Diagnose je Wurzel: haengt der Hook, wie oft feuerte er, welche Art Argument kam zuletzt
    for _, id in ipairs({ "player", "target" }) do
        local root = _G[ROOTS[id]]
        local info = type(root) == "table" and hookInfo[root] or nil
        local okA, ga = call(root, "GetAlpha")
        local gak = not okA and "fehler" or (Compat.IsSecret(ga) and "secret") or (Compat.Num(ga) and string.format("zahl(%.2f)", ga)) or type(ga)
        local last = info and (info.lastK == "zahl" and string.format("zahl(%.2f)", info.lastV) or info.lastK) or "-"
        local lastNum = info and info.lastNum and string.format("zahl(%.2f) vor %.1fs", info.lastNum, math.max(0, GetTime() - info.lastAt)) or "-"
        ns.Print("frames.portrait.model.root.%s frame=%s hookOk=%s boolHookOk=%s calls=%d num=%d sec=%d last=%s lastNum=%s bool=%d getAlpha=%s hookAlpha=%s secFrom=%s", id,
            ROOTS[id], yn(info and info.ok), yn(info and info.boolOk), info and info.calls or 0, info and info.num or 0, info and info.sec or 0,
            last, lastNum, info and info.bool or 0, gak, tostring(root and hookAlpha[root] or "-"), tostring(info and info.secFrom or "-"))
    end
    ns.Print("frames.portrait.model.cost setUnit=%d fails=%d fallbacks=%d retries=%d anims=%d events=%d avgMs=%.3f maxMs=%.3f",
        mstats.setUnit, mstats.fails, mstats.fallbacks, mstats.retries, mstats.anims, mstats.events, mstats.ms, mstats.msMax)
end

-- "Animiertes Modell (schlicht)": derselbe Code, nur Ruhe, keine Effekte; Rueckfall auf das statische Bild im eigenen Rahmen
for k, v in pairs(Model) do
    if type(v) == "function" and k ~= "Debug" and k ~= "Activate" and k ~= "Usable" then Plain[k] = v end
end
function Plain.Activate(P, cfg) activate(P, cfg, true) end
Model.previewSafe, Plain.previewSafe = true, true -- Mini-Vorschau: Portrait.lua laesst die Modell-Stile in der Buehne zu
--- schlicht: kein Vorab-Rueckfall auf das Gemaelde; scheitert das Modell, zeigt Refresh selbst das statische Bild
function Plain.Usable(P)
    return P ~= nil and Portrait.UNIT[P.id] ~= nil
end

-- Reihenfolge in der Auswahl: hinter "model" (Portrait.STYLE_ORDER gehoert Portrait.lua, hier nur angehaengt)
local inOrder = false
for _, k in ipairs(Portrait.STYLE_ORDER) do
    if k == "modelplain" then inOrder = true end
end
if not inOrder then table.insert(Portrait.STYLE_ORDER, "modelplain") end

Portrait.RegisterStyle("model", Model)
Portrait.RegisterStyle("modelplain", Plain)

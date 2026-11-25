-- Bewegungsphysik "Schwappen" (Delta "Fluessiges Leben", E3 + Feinschliff nach Spieltest 15.11.): ein globaler
-- Feder-Daempfer fuer alle Fluessigkeits-Roehren.
--
-- Der Bildschirm ist das Gefaess (Q2): Eingang ist immer die Bewegung des Spielers (und seiner Kamera), alle Roehren
-- (Spieler, Ziel, ToT, spaeter Plaketten) bekommen dasselbe Ergebnis (je Roehre leicht verstaerkt/abgeschwaecht, Liquid.SetSlosh).
--   theta  Neigung der Oberflaeche (langsam): kippt beim Loslaufen nach hinten (links, zur vollen Seite), schwappt beim
--          Anhalten nach vorn und pendelt aus (Q1).
--   A      Wellenamplitude (schneller): Sprung/Landung, Anfahren/Anhalten, Beginn/Ende einer Drehung, Schrittwippen.
-- Ausgaben sind Bildschirm-Raum (positiv = Oberkante nach rechts), weich begrenzt (keine harten Kanten). Alle Roehren fuellen
-- von links nach rechts (auch das gespiegelte Ziel), also dieselbe Weltrichtung ohne Vorzeichenwechsel.
--
-- Natuerlichkeit: angeregt wird nur durch BESCHLEUNIGUNG (nichts bewegt sich ohne Grund). Geschwindigkeit und Drehrate gehen
-- durch einen kritisch gedaempften Filter 2. Ordnung, seine Ableitung ist die Beschleunigung - sie steigt weich an (Rampe statt
-- Stufe). Sprung/Landung sind Kraftstoesse mit Halbsinus-Verlauf (PULSE), keine Geschwindigkeitsspruenge. Unstetigkeiten
-- (Ladebildschirm/Teleport, Tod, Wiederbelebung, sprunghafte Blickrichtung) setzen die Filter still auf den neuen Wert: kein Stoss.
-- Drehen (Entscheidung 16.11. "Spiegelung wandert"): wie bei einem Glas, das man in der Hand dreht, bewegt sich vor allem
-- die Spiegelung (Physics.yaw/spin -> wanderndes Glanzlicht in Liquid.lua), die Fluessigkeit kaum. Eine gleichmaessige Drehung
-- uebt KEINE bleibende Kraft aus (keine Zentrifugal-Schraeglage); nur die Aenderung der Drehrate (Beginn/Ende, Winkel-
-- beschleunigung) gibt einen kleinen, gedaempften Schwapper, deutlich schwaecher als Anlaufen.
-- Integriert wird halbimplizit in Unterschritten (SUBSTEP), stabil fuer Bildzeiten von 1/240 bis 1/15 s und darueber (MAX_DT).
--
-- Eingaenge (nur freie Werte; jeder Aufruf per pcall, Ergebnisse nur nach Secret-Pruefung ueber Compat.Num/flag):
--   Tempo:      GetUnitSpeed nur ausserhalb des Kampfs (im Kampf secret, S0), sonst IsPlayerMoving (Lauftempo).
--   Richtung:   Nachher-Hooks auf MoveForward/MoveBackward/StrafeLeft/StrafeRight/MoveAndSteer Start/Stop (vor, zurueck,
--               seitwaerts); ohne Taste (Autorun, Klick-Bewegung, Stoss) gilt vorwaerts.
--   Drehen:     GetPlayerFacing-Differenz (Taste UND Maus); nil (Instanzen) => TurnLeft/TurnRight-Hooks (mit Richtung) bzw.
--               PLAYER_STARTED/STOPPED_TURNING (ohne Richtung, nur Wellen).
--   Kamera:     CameraOrSelectOrMoveStart/Stop (Linksziehen: nur Kamera) => GetCursorDelta-x als sanfte Drehung ("Glas in der
--               Hand"); Rechtsziehen dreht den Charakter (Facing). GetCameraZoom-Aenderung regt nur minimal Wellen an.
--   Sprung:     JumpOrAscendStart-Hook; sonst Uebergang IsFalling false -> true. Landung: Stoss je nach Fallzeit.
--   Zustaende:  IsSwimming (traege, stark gedaempft), IsFlying/UnitOnTaxi (weich), IsMounted/UnitInVehicle (Reittier),
--               UnitIsDeadOrGhost (Uebergang ohne Stoss). Die Wechsel blenden weich (PROFILE_BLEND).
-- Gesundheitswerte kommen hier nie vor.
--
-- Anregung fuer die Wellensimulation (Kolben-Kammer, Liquid.lua), allokationsfrei als Felder, jedes Bild aktuell:
--   Physics.ax     Laengsbeschleunigung im Bildschirm-Raum (-1..1, + = Fluessigkeit wird nach links gedrueckt: Anlaufen,
--                  Seitwaerts nach rechts; Beginn einer Linksdrehung kurz nach rechts = negativ, gleichmaessiges Drehen 0)
--   Physics.ay     senkrechte Beschleunigung (-1..1): Abheben leicht negativ, Landung kraeftig positiv je nach Fallzeit,
--                  klingt weich ab (gedaempfte Feder, keine Stufe)
--   Physics.shake  Erschuetterungsenergie 0..1 (klingt mit SHAKE.tau ab; Beginn/Ende einer Drehung nur minimal)
--   Physics.spin   geglaettete Drehrate (rad/s, + = nach links; Charakter und Kamera-Linksziehen), fuer die Spiegelung
--   Physics.yaw    daraus integrierter Drehwinkel (rad, 0..2pi umlaufend): Lage des wandernden Glanzlichts. Springt nie
--                  (Teleport/Ladebildschirm/FACING_JUMP aendern ihn nicht), bleibt beim Einschlafen stehen.
--   Physics.pitch  Pseudo-Neigung der Kamera (-1..1, + = Blick nach oben) fuer die Glasreflexe: der Kamera-Pitch ist nicht
--                  lesbar, darum GetCursorDelta-y waehrend Kamera-Ziehen/Mouselook (Links- und Rechtsziehen) integriert,
--                  geklemmt, federt langsam zur Mitte zurueck (PITCH.ret). Die Physik schlaeft erst, wenn er ruht.
--   Physics.axG    EIN Modell fuer alle Anregungen (Spieltest Runde 4: "es muss sich die Waage halten"): die Beschleunigung
--                  des Glases ("Glas in der Hand") in Erdbeschleunigungen, ungedaempft und unbegrenzt: Laengs aus der
--                  Tempoaenderung (yd/s^2 = gefilterte Tempo-Ableitung x RUN_SPEED), Drehung aus Winkelbeschleunigung x
--                  Hebelarm GLASS.lever (Charakter UND Kamera gleich), geteilt durch GLASS.g (WoW-Schwerkraft 19,29 yd/s^2):
--                  a/g ist physikalisch die Neigung der Wasseroberflaeche. Liquid macht daraus mit EINEM Faktor die Neigung.
--   Physics.joltDv Geschwindigkeitsstoss des letzten diskreten Stosses (yd/s): Landung = Aufprallgeschwindigkeit (g x Fallzeit
--                  abwaerts), Abheben = Sprunggeschwindigkeit, Treffer/Rueckstoss/Aufsitzen = GLASS.dv*; Liquid stoesst die
--                  Welle proportional dazu an (derselbe globale Faktor).
--   Physics.jolts  Zaehler diskreter Stoesse, dazu joltStrength (0..1) und joltKind ("land"|"hit"|"mount"|"knock"):
--                  Liquid loest bei jeder Aenderung einmal Spritzer/Schaum aus.
--   Stoss-Quellen: Landung (Fallzeit; Fallschaden = Treffer kurz vor der Landung verstaerkt), Treffer (UNIT_COMBAT fuer
--   "player": nur das Ereignis und, wenn lesbar, der Text "WOUND"/"CRITICAL"; die Menge ist secret und wird nie gelesen),
--   Aufsitzen/Absitzen (PLAYER_MOUNT_DISPLAY_CHANGED bzw. Profilwechsel), Rueckstoss (Fall-Beginn ohne Sprung kurz nach
--   Treffer/Kontrollverlust, oder ausserhalb des Kampfs ein Tempo-Sprung ohne Bewegungstaste). Teleport/Ladebildschirm: nichts.
--
-- Ruhe: steht alles und ist ausgeschwungen, schlaeft die Physik (keine Rechnung, keine Setter). Geweckt wird sie ueber
-- Ereignisse, die Hooks und eine seltene Schlaf-Probe (PROBE s). Gerechnet wird im gemeinsamen Treiber (Liquid.StepAll).
local _, ns = ...
local Compat = ns.Compat

local Physics = {}
ns.LiquidPhysics = Physics

Physics.RUN_SPEED = 7            -- Yards/s (Normierung; Laufen ohne lesbare Geschwindigkeit)
Physics.SPEED_MAX = 2.5          -- normierte Geschwindigkeit hoechstens (schnelles Reittier)
Physics.ACC_MAX = 12             -- normierte Beschleunigung hoechstens (1/s), z. B. Sturmangriff
Physics.FILTER_HZ = 1.3          -- Eigenfrequenz des Geschwindigkeitsfilters (kritisch gedaempft), am Boden
Physics.TURN_FILTER_HZ = 2.0     -- dasselbe fuer die Drehrate
Physics.TURN_RATE_MAX = 6        -- rad/s
Physics.TURN_FALLBACK = 2.5      -- rad/s angenommene Drehrate ohne GetPlayerFacing
Physics.FACING_JUMP = 1.5        -- rad: groesserer Sprung in einem Bild = Teleport/Ladebildschirm (kein Stoss)
Physics.CAMERA = { scale = 0.004, max = 6, weight = 1 } -- rad je Pixel GetCursorDelta, Obergrenze rad/s, Anteil (wie Charakter)
Physics.PITCH = { scale = 0.006, ret = 0.9, rest = 0.004 } -- Pseudo-Pitch je Pixel Cursor-y, Rueckfedern (1/s), Ruheschwelle
-- Glas-Modell: g = WoW-Schwerkraft (yd/s^2), lever = wirksamer Hebelarm des Glases zur Drehachse (yd), jumpV = Absprung-
-- geschwindigkeit (yd/s), ascent = Steigzeit eines Sprungs (s), vMax = Endgeschwindigkeit im Fall, dvHit = Stoss je Einheit
-- Treffer-Staerke (WOUND 0,35 => 1,5 yd/s), dvKnock/dvMount = Rueckstoss/Aufsitzen (yd/s)
Physics.GLASS = { g = 19.29, lever = 0.6, jumpV = 7.96, ascent = 0.41, vMax = 55, dvHit = 4.2, dvKnock = 6, dvMount = 2.5 }
Physics.ZOOM = { wave = 0.002, max = 30 }                 -- Wellen-Antrieb je Yard/s Zoom (minimal), Obergrenze
-- Neigung / Wellen: Eigenfrequenz (Hz), Daempfung (zeta zwischen min und max nach Regler), Antriebe
Physics.TILT = { freq = 1.5, zetaMin = 0.25, zetaMax = 0.9, acc = 0.11, turn = 0.022 }
Physics.WAVE = { freq = 2.4, zetaMin = 0.2, zetaMax = 0.8, acc = 0.035, turn = 0.018, gait = 0.035,
    jump = 1.0, land = 1.1 }
Physics.PULSE = 0.14             -- s, Dauer eines Kraftstosses (Halbsinus)
Physics.LAND_AIR = 0.8           -- s Fallzeit fuer den vollen Landestoss; darunter schwaecher, darueber bis LAND_MAX
Physics.LAND_MAX = 1.8
-- Bewegungsprofile: Filter-Tempo, Anregung, Frequenz- und Daempfungsfaktor, Schrittwippen, Schrittfrequenz-Grundwert
Physics.PROFILES = {
    ground = { filter = 1.0, excite = 1.0, freq = 1.0, zeta = 1.0, gait = 1.0, gaitHz = 1.5 },
    mounted = { filter = 0.8, excite = 0.9, freq = 1.0, zeta = 1.0, gait = 0.8, gaitHz = 1.9 },
    swim = { filter = 0.5, excite = 0.6, freq = 0.65, zeta = 1.6, gait = 0, gaitHz = 1.0 },
    fly = { filter = 0.45, excite = 0.7, freq = 0.8, zeta = 1.2, gait = 0, gaitHz = 1.0 },
    dead = { filter = 1.0, excite = 0, freq = 1.0, zeta = 1.6, gait = 0, gaitHz = 1.0 },
}
Physics.PROFILE_BLEND = 3        -- 1/s, Ueberblenden zwischen Profilen
Physics.GAIN = 1.4               -- Ausgabe = weich begrenzt(Rohwert x Staerke x GAIN)
Physics.LIMIT = 1
Physics.REST = { pos = 0.003, vel = 0.015, speed = 0.01, turn = 0.03 }
Physics.PROBE = 0.25             -- s, Schlaf-Probe
Physics.MAX_DT = 0.1             -- s, laengere Bilder werden auf diesen Schritt begrenzt
Physics.SUBSTEP = 1 / 120        -- s, Integrationsschritt hoechstens
Physics.JUMP_WINDOW = 0.3        -- s: ein Fall-Beginn so kurz nach dem Sprung-Hook ist derselbe Sprung
Physics.SIM = { run = 0.9, turn = 0.6, turnRate = 3 } -- Testmodus: simuliertes Laufen/Drehen (s, rad/s)
Physics.DEFAULT_STRENGTH = 0.6
-- Wellensimulation: ax = Beschleunigung x scale - Winkelbeschleunigung x turn (nur Beginn/Ende einer Drehung), geglaettet
Physics.AX = { scale = 0.3, turn = 0.006, smooth = 6, gSmooth = 25 } -- gSmooth: nur Rauschglaettung fuer axG (1/s)
-- ay: gedaempfte Feder (freq Hz, zeta), Stoesse als Spitzenwert: Abheben, Landung (x Fallzeit-Faktor), Treffer
Physics.AY = { freq = 3, zeta = 0.7, lift = -0.3, land = 0.55, hit = 0.15 }
-- shake: Abklingzeit (s), Staerken je Stossart, Beginn/Ende einer Drehung hoechstens turnMax (je rad/s^2 turn)
Physics.SHAKE = { tau = 0.55, rest = 0.005, hit = 0.35, crit = 0.6, weak = 0.12, mount = 0.3, knock = 0.7,
    turn = 0.005, turnMax = 0.06, fallHit = 0.3, lift = 0.3 }
Physics.KNOCK_WINDOW = 0.4       -- s nach Treffer/Kontrollverlust: Fall-Beginn ohne Sprung = Rueckstoss
Physics.KNOCK_SPEED = 2.2        -- normierter Tempo-Sprung in einem Bild ohne Taste (nur ausserhalb des Kampfs lesbar)
Physics.FALL_HIT_WINDOW = 0.3    -- s: Treffer so kurz vor/nach der Landung = Fallschaden
Physics.MOUNT_EVENT_WINDOW = 1   -- s: Profilwechsel Reittier so kurz nach dem Ereignis zaehlt nicht doppelt

Physics.ax, Physics.ay, Physics.shake = 0, 0, 0
Physics.spin, Physics.yaw, Physics.pitch = 0, 0, 0
Physics.axG, Physics.joltDv = 0, 0
Physics.jolts, Physics.joltStrength, Physics.joltKind = 0, 0, "-"
Physics.DEFAULT_DAMPING = 0.4

local TWO_PI = 2 * math.pi
local cfgOn, strength, damping = true, Physics.DEFAULT_STRENGTH, Physics.DEFAULT_DAMPING
local awake, settled = false, true
local theta, thetaV, wave, waveV = 0, 0, 0, 0
-- Filter 2. Ordnung: Wert und Ableitung (= Beschleunigung) fuer Vorwaerts-, Seitwaerts- und Drehgeschwindigkeit
local fz, fzV, fx, fxV, fr, frV = 0, 0, 0, 0, 0, 0
local gaitPhase = 0
local prof = { filter = 1, excite = 1, freq = 1, zeta = 1, gait = 1, gaitHz = 1.5 } -- ueberblendetes Profil
local profName = "ground"
local lastT, probeAt = nil, 0
local prevFacing, prevFalling, fallStart, prevZoom, prevDead = nil, false, nil, nil, nil
local turningFlag, lastJumpAt = false, nil
local snapFilters = false        -- naechster Schritt: Filter direkt auf die neuen Ziele (Unstetigkeit)
local keys = { fwd = false, back = false, left = false, right = false, turnL = false, turnR = false, steer = false,
    camera = false, mouselook = false }
local pulses = {}                -- { at, dur, amount } (Wellen-Kraftstoesse)
local simRunUntil, simTurnUntil = nil, nil
local outTilt, outWave = 0, 0
local axS, ayPos, ayVel, shakeE = 0, 0, 0, 0
local yaw = 0                    -- Drehwinkel der Spiegelung (rad, 0..2pi); resetState laesst ihn stehen (kein Sprung)
local pitch, axGS = 0, 0         -- Pseudo-Pitch (-1..1); geglaettete Glas-Beschleunigung (a/g)
local fallJumped = false         -- dieser Fall begann mit einem Sprung (Aufprall nur aus dem Abstieg)
local lastHitAt, controlLostAt, lastMountAt, landAt = nil, nil, nil, nil
local prevMounted, prevS = nil, 0
local stats = { steps = 0, speedSrc = "-", facing = "-", camera = "-", jumpHook = "-", hooks = 0, hooksMissing = 0,
    speedCalls = 0 }

local function now() return type(GetTime) == "function" and GetTime() or 0 end

local function flag(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or Compat.IsSecret(v) then return nil end
    return v ~= nil and v ~= false
end

local function inCombat()
    return flag(_G.InCombatLockdown) == true or flag(_G.UnitAffectingCombat, "player") == true
end

--- Laufgeschwindigkeit (Yards/s) als lesbare Zahl oder nil. Nur ausserhalb des Kampfs (im Kampf secret, S0); cur geht nur an
--- Compat.Num (Secret-Pruefung), nie in Bedingungen oder Rechnungen.
local function readSpeed()
    if inCombat() or type(_G.GetUnitSpeed) ~= "function" then return nil end
    stats.speedCalls = stats.speedCalls + 1
    local ok, cur = pcall(_G.GetUnitSpeed, "player")
    if not ok then return nil end
    return Compat.Num(cur)
end

local function readNum(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return Compat.Num(v)
end

local function readFacing() return readNum(_G.GetPlayerFacing) end
local function readZoom() return readNum(_G.GetCameraZoom) end

--- GetCursorDelta (Pixel seit dem letzten Bild): dx, dy oder nil
local function readCursorDelta()
    if type(_G.GetCursorDelta) ~= "function" then return nil end
    local ok, dx, dy = pcall(_G.GetCursorDelta)
    if not ok then return nil end
    return Compat.Num(dx), Compat.Num(dy)
end

local function clamp(x, lo, hi)
    if x < lo then return lo elseif x > hi then return hi end
    return x
end

-- weiche Begrenzung auf +-lim (linear um 0, nie eine Kante)
local function soft(x, lim) return x / math.sqrt(1 + (x / lim) * (x / lim)) end

local function zeta(Z) return math.min(1.5, (Z.zetaMin + damping * (Z.zetaMax - Z.zetaMin)) * prof.zeta) end

local function wakeDriver()
    local Liquid = ns.Liquid
    if Liquid and Liquid.Wake then pcall(Liquid.Wake) end
end

local function resetState()
    theta, thetaV, wave, waveV = 0, 0, 0, 0
    fz, fzV, fx, fxV, fr, frV = 0, 0, 0, 0, 0, 0
    pulses = {}
    snapFilters = false
    outTilt, outWave = 0, 0
    axS, ayPos, ayVel, shakeE = 0, 0, 0, 0
    axGS = 0
    Physics.ax, Physics.ay, Physics.shake = 0, 0, 0
    Physics.spin, Physics.axG = 0, 0
    pitch, Physics.pitch = 0, 0
    prevS = 0 -- eingeschlafen = stand still (Idle setzt nil: Tempo unbekannt)
end

--- Keine Roehre sichtbar: in Ruhe zuruecksetzen; das Wiedereinblenden beginnt ohne Ruck (Neigung 0, frische Bezugswerte)
function Physics.Idle()
    awake = false
    lastT, prevFacing, fallStart, prevZoom = nil, nil, nil, nil
    prevMounted, prevS = nil, nil
    simRunUntil, simTurnUntil = nil, nil
    resetState()
    settled = true
end

--- Physik wecken (Ereignis, Hook, Test); schlaeft sie, beginnt die Zeitmessung neu
function Physics.Wake()
    if not cfgOn then return end
    -- ohne sichtbare Roehre nicht wecken (sonst veralten awake/lastT/prevFacing bis zum Wiedereinblenden)
    local Liquid = ns.Liquid
    if Liquid and Liquid.AnyVisible and not Liquid.AnyVisible() then
        Physics.Idle()
        return
    end
    if not awake then
        awake = true
        lastT = nil
    end
    settled = false
    wakeDriver()
end

--- Regler: an/aus, Staerke 0..1, Daempfung 0..1 (ungueltig => Standard)
function Physics.Configure(on, s, d)
    s, d = Compat.Num(s), Compat.Num(d)
    strength = (s and s >= 0 and s <= 1) and s or Physics.DEFAULT_STRENGTH
    damping = (d and d >= 0 and d <= 1) and d or Physics.DEFAULT_DAMPING
    local want = on ~= false
    if want == cfgOn then return end
    cfgOn = want
    if not cfgOn then
        awake = false
        resetState()
        settled = false -- einmal (0, 0) verteilen
        wakeDriver()
    end
end

function Physics.IsOn() return cfgOn end
function Physics.IsAwake() return awake end

--- Aktuelle Ausgabe (Neigung, Welle) fuer neu sichtbare Roehren
function Physics.Current() return outTilt, outWave end

-- Kraftstoss auf die Welle (Halbsinus ueber PULSE s); amount = Geschwindigkeitsaenderung (1/s) insgesamt
local function pulse(amount)
    pulses[#pulses + 1] = { at = now(), dur = Physics.PULSE, amount = amount }
end

local function onJump()
    if not cfgOn then return end
    lastJumpAt = now()
    Physics.Wake()
    if awake then -- ohne sichtbare Roehre kein gespeicherter Stoss
        pulse(Physics.WAVE.jump * prof.excite * 16)
        Physics.Jolt("lift", Physics.SHAKE.lift, nil, Physics.GLASS.jumpV) -- Abheben: Stoss = Sprunggeschwindigkeit
    end
end
Physics.OnJump = onJump

-- senkrechter Stoss: Spitzenwert peak (kritisch gedaempfte Antwort A*t*e^(-w*t) hat die Spitze A/(w*e))
local function ayKick(peak)
    local w = TWO_PI * Physics.AY.freq
    ayVel = ayVel + peak * w * math.exp(1)
end

--- Diskreter Stoss (Spritzer/Schaum in Liquid): kind "land"|"hit"|"mount"|"knock", st 0..1. Nur bei sichtbarer Roehre.
local function jolt(kind, st, wavePulse, dv)
    if not cfgOn then return end
    Physics.Wake()
    if not awake then return end
    st = clamp(st * prof.excite, 0, 1)
    if st <= 0 then return end
    shakeE = math.min(1, shakeE + st)
    Physics.jolts = Physics.jolts + 1
    Physics.joltStrength = st
    Physics.joltKind = kind
    Physics.joltDv = (dv or st * Physics.GLASS.dvHit) * prof.excite -- Geschwindigkeitsstoss (yd/s)
    if wavePulse then pulse(wavePulse * prof.excite) end
end
Physics.Jolt = jolt

--- Testmodus (/vials test): kurze Anregung ohne echte Bewegung. kind = "run" (anlaufen, anhalten), "turn", "jump"
function Physics.Simulate(kind)
    if not cfgOn then return false end
    local t = now()
    if kind == "jump" then
        onJump()
        return true
    elseif kind == "turn" then
        simTurnUntil = t + Physics.SIM.turn
    else
        simRunUntil = t + Physics.SIM.run
    end
    Physics.Wake()
    return true
end

-- Zustand: Profil nach Schwimmen/Fliegen/Reittier/Tod
local function currentProfile()
    if flag(_G.UnitIsDeadOrGhost, "player") == true and flag(_G.UnitIsGhost, "player") ~= true then return "dead" end
    if flag(_G.IsSwimming) == true then return "swim" end
    if flag(_G.IsFlying) == true or flag(_G.UnitOnTaxi, "player") == true then return "fly" end
    if flag(_G.IsMounted) == true or flag(_G.UnitInVehicle, "player") == true then return "mounted" end
    return "ground"
end

local function blendProfile(name, dt)
    local target = Physics.PROFILES[name] or Physics.PROFILES.ground
    profName = name
    local k = math.min(1, dt * Physics.PROFILE_BLEND)
    for key, v in pairs(target) do prof[key] = prof[key] + (v - prof[key]) * k end
end

-- Filter 2. Ordnung, kritisch gedaempft (omega): folgt dem Ziel ohne Ueberschwingen, die Ableitung steigt weich an
local function filter(x, v, target, omega, h)
    v = v + (omega * omega * (target - x) - 2 * omega * v) * h
    return x + v * h, v
end

-- Kraftstoesse dieses Unterschritts (Summe der Halbsinus-Beschleunigungen), abgelaufene entfernen
local function pulseAcc(tw)
    local a = 0
    for i = #pulses, 1, -1 do
        local p = pulses[i]
        local u = (tw - p.at) / p.dur
        if u >= 1 then
            table.remove(pulses, i)
        elseif u >= 0 then
            a = a + p.amount * (math.pi / 2) / p.dur * math.sin(math.pi * u)
        end
    end
    return a
end

-- Unstetigkeit (Ladebildschirm, Teleport, Tod, Wiederbelebung): Filter still auf die neuen Werte, kein Stoss
local function discontinuity()
    fzV, fxV, frV = 0, 0, 0
    ayVel = 0
    lastHitAt, controlLostAt, landAt = nil, nil, nil
    prevMounted, prevS = nil, nil
    snapFilters = awake -- schlafend stehen die Filter schon still (sonst verschluckte das naechste Loslaufen seinen Stoss)
    pulses = {}
    prevFacing, prevZoom, fallStart = nil, nil, nil
end

local function restReached(vz, vx, r)
    local R = Physics.REST
    return math.abs(vz) < R.speed and math.abs(vx) < R.speed and math.abs(fz) < R.speed and math.abs(fx) < R.speed
        and math.abs(fzV) < R.vel and math.abs(fxV) < R.vel and math.abs(r) < R.turn and math.abs(fr) < R.turn
        and math.abs(frV) < R.vel and #pulses == 0
        and math.abs(theta) < R.pos and math.abs(thetaV) < R.vel and math.abs(wave) < R.pos and math.abs(waveV) < R.vel
end

-- Schlaf-Probe: eine Handvoll Abfragen alle PROBE s (Maus-Drehen, Rueckstoss, Fallen ohne Ereignis)
local function probe(t)
    if t < probeAt then return end
    probeAt = t + Physics.PROBE
    local f = readFacing()
    if keys.camera or keys.mouselook or flag(_G.IsPlayerMoving) == true or flag(_G.IsFalling, "player") == true
        or (f and prevFacing and math.abs(f - prevFacing) > 0.02) then
        Physics.Wake()
    end
    prevFacing = f
end

-- Richtung aus den Tasten-Hooks: vz (vor +, zurueck -), vx (rechts +, links -), Betrag 1; ohne Taste vorwaerts
local function direction()
    local z = ((keys.fwd or keys.steer) and 1 or 0) - (keys.back and 1 or 0)
    local x = (keys.right and 1 or 0) - (keys.left and 1 or 0)
    if z == 0 and x == 0 then return 1, 0 end
    local n = math.sqrt(z * z + x * x)
    return z / n, x / n
end

-- Teilschritte von Physics.Step (eigene Funktionen: Lua 5.1 erlaubt hoechstens 60 Upvalues je Funktion,
-- scripts/check-lua.mjs prueft das)

--- Rueckstoss per Tempo-Sprung und Aufsitzen/Absitzen ohne Ereignis
local function stepJolts(sp, s, pname, wall)
    -- Rueckstoss: Tempo springt in einem Bild ohne Bewegungstaste (nur lesbar ausserhalb des Kampfs)
    local anyKey = keys.fwd or keys.back or keys.left or keys.right or keys.steer
    if sp and prevS and not anyKey and not snapFilters and s - prevS > Physics.KNOCK_SPEED then
        jolt("knock", Physics.SHAKE.knock, Physics.WAVE.jump * 10, Physics.GLASS.dvKnock)
    end
    prevS = s
    -- Aufsitzen/Absitzen ohne Ereignis (Profilwechsel)
    local mountedNow = pname == "mounted"
    if prevMounted ~= nil and mountedNow ~= prevMounted
        and not (lastMountAt and wall - lastMountAt < Physics.MOUNT_EVENT_WINDOW) then
        lastMountAt = wall
        jolt("mount", Physics.SHAKE.mount, Physics.WAVE.jump * 6, Physics.GLASS.dvMount)
    end
    prevMounted = mountedNow
end

--- Drehrate (rad/s) samt Kamera; liefert r, directed, camMoving
local function stepTurn(dt, wall)
    -- Drehrate (rad/s, positiv = nach links): Facing (Taste und Maus), sonst Tasten-Hooks, sonst TURNING-Ereignisse
    local f = readFacing()
    local r, directed = 0, true
    if f and prevFacing then
        local d = f - prevFacing
        if d > math.pi then d = d - TWO_PI elseif d < -math.pi then d = d + TWO_PI end
        if math.abs(d) > Physics.FACING_JUMP then
            discontinuity() -- Teleport/Ladebildschirm: Blickrichtung springt, kein Stoss
            r = fr
        else
            r = clamp(d / dt, -Physics.TURN_RATE_MAX, Physics.TURN_RATE_MAX)
        end
        stats.facing = "facing"
    elseif not f then
        local k = (keys.turnL and 1 or 0) - (keys.turnR and 1 or 0)
        if k ~= 0 then
            r = k * Physics.TURN_FALLBACK
            stats.facing = "keys"
        else
            directed = false
            r = turningFlag and Physics.TURN_FALLBACK or 0
            stats.facing = "events"
        end
    end
    prevFacing = f
    -- Kamera: Linksziehen dreht nur die Kamera (Rechtsziehen/Mouselook dreht den Charakter und steckt im Facing)
    local camMoving = false
    local cdx, cdy
    if keys.camera or keys.mouselook then cdx, cdy = readCursorDelta() end
    -- Pseudo-Pitch fuer die Glasreflexe: Maus nach oben (dy > 0) = Blick nach oben; Links- und Rechtsziehen
    local P = Physics.PITCH
    if cdy and cdy ~= 0 then
        pitch = clamp(pitch + cdy * P.scale, -1, 1)
        camMoving = true
    end
    pitch = pitch - pitch * math.min(1, P.ret * dt)
    if math.abs(pitch) < P.rest * 0.5 then pitch = 0 end
    Physics.pitch = pitch
    if keys.camera and not keys.mouselook then
        if cdx then
            camMoving = cdx ~= 0
            stats.camera = "delta"
            local C = Physics.CAMERA
            -- Maus nach rechts = Blick nach rechts (wie eine Rechtsdrehung)
            r = r + clamp(-cdx * C.scale / dt, -C.max, C.max) * C.weight
            directed = true
        else
            stats.camera = "nodelta"
        end
    end
    if simTurnUntil then
        if wall < simTurnUntil then r = r + Physics.SIM.turnRate else simTurnUntil = nil end
    end
    return r, directed, camMoving
end

--- Sprung/Landung; liefert falling
local function stepFalling(wall, dead)
    -- Sprung/Landung ueber IsFalling (der Hook hat Vorrang); Landestoss nach Fallzeit
    local falling = flag(_G.IsFalling, "player") == true
    if falling and not prevFalling then
        fallStart = wall
        ayKick(Physics.AY.lift * prof.excite)
        local jumped = lastJumpAt and wall - lastJumpAt < Physics.JUMP_WINDOW
        fallJumped = jumped and true or false
        local hitRecent = (lastHitAt and wall - lastHitAt < Physics.KNOCK_WINDOW)
            or (controlLostAt and wall - controlLostAt < Physics.KNOCK_WINDOW)
        if not jumped then
            if hitRecent then
                jolt("knock", Physics.SHAKE.knock, Physics.WAVE.jump * 16, Physics.GLASS.dvKnock)
            else
                pulse(Physics.WAVE.jump * prof.excite * 16)
            end
        end
    elseif prevFalling and not falling then
        if fallStart and not dead then
            local air = wall - fallStart
            local k = math.min(Physics.LAND_MAX, 0.25 + air / Physics.LAND_AIR)
            ayKick(Physics.AY.land * prof.excite * k)
            local st = clamp((k - 0.15) / (Physics.LAND_MAX - 0.15), 0.05, 1)
            if lastHitAt and wall - lastHitAt < Physics.FALL_HIT_WINDOW then st = st + Physics.SHAKE.fallHit end
            -- Aufprallgeschwindigkeit: g x Fallzeit abwaerts (bei einem Sprung ohne die Steigzeit), Fallschaden wie Treffer
            local Gl = Physics.GLASS
            local dv = math.min(Gl.vMax, Gl.g * math.max(0.05, air - (fallJumped and Gl.ascent or 0)))
            jolt("land", st, -Physics.WAVE.land * 16 * k, dv)
            landAt = wall
        end
        fallStart = nil
    end
    prevFalling = falling
    return falling
end

--- Filter und Feder-Daempfer in Unterschritten; liefert n, h
local function stepIntegrate(dt, vz, vx, r, directed, falling, zoomRate, s, wall)
    if snapFilters then -- Unstetigkeit: neue Geschwindigkeit/Drehrate ohne Beschleunigung uebernehmen
        snapFilters = false
        fz, fx, fr, fzV, fxV, frV = vz, vx, r, 0, 0, 0
    end
    -- Integration in Unterschritten: Filter (Beschleunigung) -> Feder-Daempfer
    local T, W = Physics.TILT, Physics.WAVE
    local wT, wW = TWO_PI * T.freq * prof.freq, TWO_PI * W.freq * prof.freq
    local zT, zW = zeta(T), zeta(W)
    local wF, wR = TWO_PI * Physics.FILTER_HZ * prof.filter, TWO_PI * Physics.TURN_FILTER_HZ * prof.filter
    local n = math.max(1, math.ceil(dt / Physics.SUBSTEP - 1e-9))
    local h = dt / n
    local ex = prof.excite
    local gaitHz = prof.gaitHz + 0.25 * math.min(s, Physics.SPEED_MAX)
    for i = 1, n do
        fz, fzV = filter(fz, fzV, vz, wF, h)
        fx, fxV = filter(fx, fxV, vx, wF, h)
        fr, frV = filter(fr, frV, r, wR, h)
        -- Spiegelung folgt der geglaetteten Drehung (stetig, auch ueber Unstetigkeiten hinweg); ohne Richtung steht sie
        if directed then yaw = yaw + fr * h end
        local acc = clamp(fzV + fxV, -Physics.ACC_MAX, Physics.ACC_MAX) * ex
        local turnAcc = clamp(frV, -Physics.ACC_MAX * 3, Physics.ACC_MAX * 3) * ex
        gaitPhase = (gaitPhase + TWO_PI * gaitHz * h) % TWO_PI
        local speedNow = math.min(1.5, math.sqrt(fz * fz + fx * fx))
        local gait = (falling and 0 or W.gait * prof.gait * speedNow) * math.sin(gaitPhase)
        -- Ruhelagen: Beschleunigung (vor/rechts) kippt nach hinten/links, Linksdrehung schiebt nach rechts
        local tilt0 = -T.acc * acc + (directed and T.turn * turnAcc or 0)
        local wave0 = -W.acc * acc + (directed and W.turn * turnAcc or W.turn * math.abs(turnAcc)) + gait
            + Physics.ZOOM.wave * zoomRate
        thetaV = thetaV + (-wT * wT * (theta - tilt0) - 2 * zT * wT * thetaV) * h
        theta = theta + thetaV * h
        local tw = wall - dt + i * h
        local pa = pulseAcc(tw)
        waveV = waveV + (-wW * wW * (wave - wave0) - 2 * zW * wW * waveV + pa) * h
        wave = wave + waveV * h
    end
    yaw = yaw % TWO_PI
    if yaw ~= yaw then yaw = 0 end -- NaN-Schutz
    local g = strength * Physics.GAIN
    outTilt = soft(theta * g, Physics.LIMIT)
    outWave = soft(wave * g, Physics.LIMIT)
    return n, h
end

--- Anregung der Wellensimulation (ax/ay/shake); liefert true, wenn sie ausgeklungen ist
local function stepExcite(dt, n, h)
    local A, Y, K = Physics.AX, Physics.AY, Physics.SHAKE
    local sg = strength / Physics.DEFAULT_STRENGTH
    -- Drehen: nur die Winkelbeschleunigung (Beginn/Ende), nie die Drehrate selbst (keine bleibende Schraeglage)
    local turnAcc = clamp(frV, -Physics.ACC_MAX * 3, Physics.ACC_MAX * 3)
    local rawAx = (clamp(fzV + fxV, -Physics.ACC_MAX, Physics.ACC_MAX) * A.scale - A.turn * turnAcc) * prof.excite
    axS = axS + (rawAx - axS) * math.min(1, dt * A.smooth)
    -- Glas-Modell (a/g): Laengs = Tempo-Ableitung x RUN_SPEED (yd/s^2), Drehung = Winkelbeschleunigung x Hebelarm; + = die
    -- Fluessigkeit wird nach links gedrueckt (wie ax). Nur leicht gegen Rauschen geglaettet, nicht begrenzt.
    local Gl = Physics.GLASS
    local aG = ((fzV + fxV) * Physics.RUN_SPEED - Gl.lever * frV) / Gl.g * prof.excite
    axGS = axGS + (aG - axGS) * math.min(1, dt * A.gSmooth)
    local wY = TWO_PI * Y.freq * prof.freq
    local zY = Y.zeta * prof.zeta
    for _ = 1, n do
        ayVel = ayVel + (-wY * wY * ayPos - 2 * zY * wY * ayVel) * h
        ayPos = ayPos + ayVel * h
    end
    shakeE = shakeE * math.exp(-dt / (K.tau / math.max(0.5, prof.zeta)))
    local turnShake = math.min(K.turnMax, K.turn * math.abs(turnAcc)) * prof.excite
    if turnShake > shakeE then shakeE = turnShake end
    Physics.ax = soft(axS * sg, 1)
    Physics.axG = axGS * sg
    Physics.ay = soft(ayPos * sg, 1)
    Physics.shake = clamp(shakeE * sg, 0, 1)
    Physics.spin, Physics.yaw = fr, yaw
    return shakeE < K.rest and math.abs(ayPos) < Physics.REST.pos and math.abs(ayVel) < Physics.REST.vel
        and math.abs(axS) < Physics.REST.pos and math.abs(axGS) < Physics.REST.pos
end

--- Ein Bild (aus Liquid.StepAll, t = Treiberzeit; der Abstand zum letzten Aufruf darf beliebig schwanken).
--- Liefert changed, tilt, wave: changed = false => nichts zu setzen.
function Physics.Step(t)
    t = Compat.Num(t) or now()
    if not cfgOn then
        if settled then return false end
        settled = true
        return true, 0, 0
    end
    if not awake then
        probe(t)
        if not awake then
            if settled then return false end
            settled = true
            return true, 0, 0
        end
    end
    local first = lastT == nil
    local dt = first and 0 or (t - lastT)
    lastT = t
    if first or dt <= 0 then
        -- erstes Bild nach dem Wecken: nur Bezugswerte merken (prevFalling bleibt, damit ein Fall-Beginn, der die
        -- Schlaf-Probe geweckt hat, als Sprung zaehlt)
        prevFacing = readFacing()
        prevZoom = readZoom()
        return true, outTilt, outWave
    end
    if dt > Physics.MAX_DT then dt = Physics.MAX_DT end -- Ruckler/niedrige Bildrate: begrenzt weiterrechnen
    stats.steps = stats.steps + 1
    local wall = now()

    -- Zustand und Profil (Tod/Wiederbelebung ohne Stoss)
    local pname = currentProfile()
    local dead = pname == "dead"
    if prevDead ~= nil and dead ~= prevDead then discontinuity() end
    prevDead = dead
    blendProfile(pname, dt)

    -- Tempo (normiert) und Richtung
    local s
    local sp = readSpeed()
    if sp then
        s = sp / Physics.RUN_SPEED
        stats.speedSrc = "speed"
    else
        s = (flag(_G.IsPlayerMoving) == true) and 1 or 0
        stats.speedSrc = "moving"
    end
    if simRunUntil then
        if wall < simRunUntil then s = math.max(s, 1) else simRunUntil = nil end
    end
    if dead then s = 0 end
    s = clamp(s, 0, Physics.SPEED_MAX)
    local dz, dx = direction()
    local vz, vx = s * dz, s * dx
    stepJolts(sp, s, pname, wall)

    local r, directed, camMoving = stepTurn(dt, wall)
    -- Zoom: minimal
    local z = readZoom()
    local zoomRate = (z and prevZoom) and clamp(math.abs(z - prevZoom) / dt, 0, Physics.ZOOM.max) or 0
    prevZoom = z

    local falling = stepFalling(wall, dead)

    local n, h = stepIntegrate(dt, vz, vx, r, directed, falling, zoomRate, s, wall)
    local calm = stepExcite(dt, n, h)
    local still = not falling and not simRunUntil and not simTurnUntil and not turningFlag and not camMoving
        and zoomRate == 0 and calm and pitch == 0
    if still and restReached(vz, vx, r) then
        awake = false
        resetState()
        settled = true
        probeAt = t + Physics.PROBE
        return true, 0, 0
    end
    return true, outTilt, outWave
end

--- Zustand fuer /vials debug und Tests (nur lesen)
function Physics.Info()
    return { on = cfgOn, awake = awake, strength = strength, damping = damping, tilt = outTilt, wave = outWave,
        steps = stats.steps, speedSrc = stats.speedSrc, facing = stats.facing, camera = stats.camera,
        jumpHook = stats.jumpHook, hooks = stats.hooks, hooksMissing = stats.hooksMissing, speedCalls = stats.speedCalls,
        turning = turningFlag, profile = profName, pulses = #pulses, ax = Physics.ax, ay = Physics.ay,
        shake = Physics.shake, spin = Physics.spin, yaw = Physics.yaw, pitch = Physics.pitch, axG = Physics.axG,
        jolts = Physics.jolts,
        joltStrength = Physics.joltStrength, joltKind = Physics.joltKind }
end

-- Eingaenge: Ereignisse (Handler pruefen cfgOn; ohne sichtbare Roehre weckt nichts) ----------------------------------------
local function onMoveEvent() Physics.Wake() end
Compat.TryOn("PLAYER_STARTED_MOVING", onMoveEvent)
Compat.TryOn("PLAYER_STOPPED_MOVING", onMoveEvent)
Compat.TryOn("PLAYER_STARTED_TURNING", function()
    turningFlag = true
    Physics.Wake()
end)
Compat.TryOn("PLAYER_STOPPED_TURNING", function()
    turningFlag = false
    Physics.Wake()
end)
Compat.TryOn("PLAYER_ENTERING_WORLD", function()
    -- Ladebildschirm/Teleport: Bezugswerte verwerfen (Facing springt), Tasten und Drehen enden, kein Stoss
    turningFlag = false
    for k in pairs(keys) do keys[k] = false end
    discontinuity()
    prevFalling = false
    lastT = nil
end)

-- Treffer: UNIT_COMBAT nur fuer "player" (eigener Frame mit Einheitenfilter, kein Raid-/Plaketten-Verkehr). Ausgewertet
-- werden nur das Ereignis selbst und - wenn NICHT secret - der Ereignis-Text (WOUND, CRITICAL/CRUSHING); die Menge (secret)
-- wird nie angefasst. Unlesbarer Text = schwaches Signal (koennte auch Heilung sein).
Physics.HIT_EVENTS = { WOUND = true }
Physics.SOFT_EVENTS = { BLOCK = true, PARRY = true, DODGE = true, RESIST = true, ABSORB = true }
local function onCombat(unit, ev, flagText)
    if not cfgOn or Compat.IsSecret(unit) or unit ~= "player" then return end
    local st
    if type(ev) ~= "string" or Compat.IsSecret(ev) then
        st = Physics.SHAKE.weak
    elseif Physics.HIT_EVENTS[ev] then
        local crit = type(flagText) == "string" and not Compat.IsSecret(flagText)
            and (flagText == "CRITICAL" or flagText == "CRUSHING")
        st = crit and Physics.SHAKE.crit or Physics.SHAKE.hit
    elseif Physics.SOFT_EVENTS[ev] then
        st = Physics.SHAKE.weak
    else
        return -- Heilung, Energie, Verfehlen: kein Stoss
    end
    local t = now()
    lastHitAt = t
    if landAt and t - landAt < Physics.FALL_HIT_WINDOW then st = st + Physics.SHAKE.fallHit end -- Fallschaden
    ayKick(Physics.AY.hit * st)
    jolt("hit", st, Physics.WAVE.jump * 8 * st)
end
Physics.OnCombat = onCombat
do
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, _, unit, ev, flagText) pcall(onCombat, unit, ev, flagText) end)
    if not pcall(f.RegisterUnitEvent, f, "UNIT_COMBAT", "player") then pcall(f.RegisterEvent, f, "UNIT_COMBAT") end
    Physics.combatFrame = f
end
Compat.TryOn("PLAYER_CONTROL_LOST", function() controlLostAt = now() end)
Compat.TryOn("PLAYER_MOUNT_DISPLAY_CHANGED", function()
    if not cfgOn then return end
    lastMountAt = now()
    jolt("mount", Physics.SHAKE.mount, Physics.WAVE.jump * 6, Physics.GLASS.dvMount)
end)

-- Nachher-Hooks (Blizzard-Funktionen bleiben unveraendert; fehlt eine, entfaellt nur dieser Eingang) ----------------------
local function keyHook(key, value)
    return function()
        keys[key] = value
        if cfgOn then Physics.Wake() end
    end
end
Physics.HOOKS = {
    MoveForwardStart = keyHook("fwd", true), MoveForwardStop = keyHook("fwd", false),
    MoveBackwardStart = keyHook("back", true), MoveBackwardStop = keyHook("back", false),
    StrafeLeftStart = keyHook("left", true), StrafeLeftStop = keyHook("left", false),
    StrafeRightStart = keyHook("right", true), StrafeRightStop = keyHook("right", false),
    TurnLeftStart = keyHook("turnL", true), TurnLeftStop = keyHook("turnL", false),
    TurnRightStart = keyHook("turnR", true), TurnRightStop = keyHook("turnR", false),
    MoveAndSteerStart = keyHook("steer", true), MoveAndSteerStop = keyHook("steer", false),
    CameraOrSelectOrMoveStart = keyHook("camera", true), CameraOrSelectOrMoveStop = keyHook("camera", false),
    TurnOrActionStart = keyHook("mouselook", true), TurnOrActionStop = keyHook("mouselook", false),
    MouselookStart = keyHook("mouselook", true), MouselookStop = keyHook("mouselook", false),
}
local hooked = false

--- Alle Hooks einmal setzen (nur hooksecurefunc). Liefert den Status des Sprung-Hooks ("ok"|"missing"|"failed").
function Physics.InstallHooks()
    if hooked then return stats.jumpHook end
    hooked = true
    local canHook = type(hooksecurefunc) == "function"
    if type(_G.JumpOrAscendStart) ~= "function" or not canHook then
        stats.jumpHook = "missing"
    else
        local ok = pcall(hooksecurefunc, "JumpOrAscendStart", function() pcall(onJump) end)
        stats.jumpHook = ok and "ok" or "failed"
    end
    local names = {}
    for name in pairs(Physics.HOOKS) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local fn = Physics.HOOKS[name]
        if canHook and type(_G[name]) == "function"
            and pcall(hooksecurefunc, name, function() pcall(fn) end) then
            stats.hooks = stats.hooks + 1
        else
            stats.hooksMissing = stats.hooksMissing + 1
        end
    end
    return stats.jumpHook
end
Physics.InstallJumpHook = Physics.InstallHooks -- Name aus E3 (Skin.lua)

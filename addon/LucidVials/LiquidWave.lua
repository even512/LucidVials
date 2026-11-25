-- Wellensimulation der Kolben-Kammer (Delta "Fluessiges Leben"): ein 1D-Hoehenfeld je Roehre ueber die Kammer
-- (Rohrbeginn x = 0 -> Kolben x = 1), gedaempfte lineare Flachwasser-Wellengleichung
--     h_tt = c^2 h_xx + nu h_xxt - gamma h_t
-- mit endlicher Laufgeschwindigkeit c (Kammerlaengen/s), Reflexion an beiden Enden (Neumann-Rand ueber Geisterknoten), deren
-- Randsteigung die Laengsneigung vorgibt (Ruhelage = gerade schiefe Oberflaeche wie eine Wasserwaage), Volumenerhaltung
-- (Mittel fix 0) und viskoser Daempfung, die hoehere Moden schneller abklingen laesst als die Grundmode.
-- Einheiten: Hoehen in Roehrenhoehen (+ = nach oben), Geschwindigkeiten in Roehrenhoehen/s, Zeit in s.
-- Stabil fuer Bildabstaende 1/240 ... 1/15 s (feste Unterschritte <= DEF.sub), keine Allokationen pro Schritt (Felder vorab),
-- schlaeft, sobald das Feld in seiner Ruhelage liegt. Rein rechnerisch (keine WoW-API): testbar in tests/liquid-wave.test.mjs.
local _, ns = ...

local Wave = {}
ns.LiquidWave = Wave

-- c: Wellengeschwindigkeit (Kammerlaengen/s, Grundmode T = 2/c), nu: viskose Daempfung (hoehere Moden ~ k^2), gamma: lineare
-- Daempfung, sub: max. Unterschritt (s), maxDt: laengster Bildabstand, der noch gerechnet wird (Ruckler: kuerzen), sleepE:
-- Ruheschwelle (Summe Abweichung^2 + v^2), hMax: harte Notbremse (Roehrenhoehen)
Wave.DEF = { c = 2.3, nu = 0.004, gamma = 0.9, sub = 1 / 240, maxDt = 1 / 15, sleepE = 1e-6, hMax = 0.9 }

local cos, pi, floor, ceil, min, max, abs = math.cos, math.pi, math.floor, math.ceil, math.min, math.max, math.abs

--- Neues Feld mit n Stuetzstellen (>= 4)
function Wave.New(n)
    n = max(4, floor(n or 24))
    local f = { n = n, h = {}, v = {}, a = {}, p1 = {}, p2 = {}, p3 = {}, p4 = {}, slope = 0, awake = false, energy = 0,
        steps = 0 }
    for i = 1, n do
        local x = (i - 1) / (n - 1)
        f.h[i], f.v[i], f.a[i] = 0, 0, 0
        f.p1[i], f.p2[i], f.p3[i], f.p4[i] = cos(pi * x), cos(2 * pi * x), cos(3 * pi * x), cos(4 * pi * x)
    end
    return f
end

--- Randsteigung (Roehrenhoehen je Kammerlaenge; + = zum Kolben hin hoeher). Weckt bei merklicher Aenderung.
function Wave.SetSlope(f, s)
    s = tonumber(s) or 0
    if abs(s - f.slope) > 1e-4 then
        f.slope = s
        f.awake = true
    end
end

-- Stoss-Muster (Geschwindigkeit, Mittel 0): Landung = symmetrisch (Enden gegen Mitte), Treffer = Ruck der Laenge nach plus
-- Oberton, Aufsitzen/Wegstossen = gemischt
local KICK = {
    land = { 0.15, 1.0, 0.0, 0.35 },
    hit = { 0.9, 0.0, 0.45, 0.0 },
    mount = { 0.6, 0.45, 0.0, 0.0 },
    knock = { 0.8, 0.3, 0.25, 0.0 },
    lift = { 0.25, -0.8, 0.0, -0.3 }, -- Sprung-Abheben: Gegenstueck zur Landung
}
Wave.KICK = KICK

--- Stoss: kind ("land"|"hit"|"mount"|"knock"), strength 0..1 (lesbare Zahl), sign +-1 (Richtung der Grundmode)
function Wave.Kick(f, kind, strength, sign)
    local k = KICK[kind] or KICK.land
    local s = (tonumber(strength) or 0) * (sign or 1)
    if s == 0 then return end
    local v, p1, p2, p3, p4 = f.v, f.p1, f.p2, f.p3, f.p4
    for i = 1, f.n do
        v[i] = v[i] + s * (k[1] * p1[i] + k[2] * p2[i] + k[3] * p3[i] + k[4] * p4[i])
    end
    f.awake = true
end

--- Kolbenschub: amount (Roehrenhoehen/s) am Kolbenende; + = Kolben drueckt Fluessigkeit zusammen (hebt sie dort)
function Wave.Push(f, amount)
    amount = tonumber(amount) or 0
    if amount == 0 then return end
    local n, v = f.n, f.v
    v[n] = v[n] + amount
    v[n - 1] = v[n - 1] + amount * 0.6
    v[n - 2] = v[n - 2] + amount * 0.25
    f.awake = true
end

--- Ein Bild (dt in s). Liefert true, solange sich das Feld bewegt (danach liegt es exakt in der Ruhelage).
function Wave.Step(f, dt)
    if not f.awake then return false end
    local D = Wave.DEF
    dt = tonumber(dt) or 0
    if dt <= 0 then return true end
    if dt > D.maxDt then dt = D.maxDt end
    local nsub = ceil(dt / D.sub)
    local sd = dt / nsub
    local n, h, v, a = f.n, f.h, f.v, f.a
    local dx = 1 / (n - 1)
    local c2 = (D.c / dx) ^ 2
    local nuk = D.nu / (dx * dx)
    local g = D.gamma
    local gl, gr = 2 * dx * f.slope, 2 * dx * f.slope -- Geisterknoten: h0 = h2 - 2dx s, h(n+1) = h(n-1) + 2dx s
    local hMax = D.hMax
    local n1 = n - 1
    for _ = 1, nsub do
        -- Raender ueber Geisterknoten (Neumann mit Randsteigung), Mitte ohne Verzweigung
        local h1, hn = h[1], h[n]
        a[1] = c2 * (2 * h[2] - gl - 2 * h1) + nuk * (2 * v[2] - 2 * v[1]) - g * v[1]
        a[n] = c2 * (2 * h[n1] + gr - 2 * hn) + nuk * (2 * v[n1] - 2 * v[n]) - g * v[n]
        local hp, hc, vp, vc = h1, h[2], v[1], v[2]
        for i = 2, n1 do
            local hx, vx = h[i + 1], v[i + 1]
            a[i] = c2 * (hp - 2 * hc + hx) + nuk * (vp - 2 * vc + vx) - g * vc
            hp, hc, vp, vc = hc, hx, vc, vx
        end
        -- halbimplizit (symplektisch): erst Geschwindigkeit, dann Hoehe
        for i = 1, n do
            local vi = v[i] + a[i] * sd
            v[i] = vi
            h[i] = h[i] + vi * sd
        end
    end
    -- Volumen: Mittel (Trapez) bleibt 0; Notbremse gegen Ausreisser
    local sum = 0.5 * (h[1] + h[n])
    for i = 2, n1 do sum = sum + h[i] end
    local m = sum * dx
    for i = 1, n do
        local hi = h[i] - m
        if hi > hMax then hi, v[i] = hMax, 0 elseif hi < -hMax then hi, v[i] = -hMax, 0 end
        h[i] = hi
    end
    f.steps = f.steps + nsub
    -- Ruhe: Abstand zur geraden Ruhelage h = s (x - 1/2) und Bewegung
    local e = 0
    local s = f.slope
    for i = 1, n do
        local d = h[i] - s * ((i - 1) * dx - 0.5)
        e = e + d * d + v[i] * v[i] * 0.02
    end
    f.energy = e / n
    -- NaN/inf-Schutz: ein vergiftetes Feld wird auf die Ruhelage zurueckgesetzt
    if f.energy ~= f.energy or f.energy == math.huge or f.energy < D.sleepE then
        for i = 1, n do
            h[i] = s * ((i - 1) * dx - 0.5)
            v[i] = 0
        end
        f.energy = 0
        f.awake = false
    end
    return true
end

--- Hoehe an x (0..1), Catmull-Rom zwischen den Stuetzstellen (glatt, ohne Knicke); Enden linear fortgesetzt
function Wave.Sample(f, x)
    local n, h = f.n, f.h
    if x <= 0 then return h[1] end
    if x >= 1 then return h[n] end
    local u = x * (n - 1)
    local i = floor(u) + 1
    local t = u - (i - 1)
    local p1, p2 = h[i], h[min(n, i + 1)]
    local p0 = (i > 1) and h[i - 1] or (2 * p1 - p2)
    local p3 = (i + 2 <= n) and h[i + 2] or (2 * p2 - p1)
    local t2, t3 = t * t, t * t * t
    return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

--- Senkrechte Geschwindigkeit an x (linear), fuer Schaum
function Wave.Speed(f, x)
    local n, v = f.n, f.v
    if x <= 0 then return v[1] end
    if x >= 1 then return v[n] end
    local u = x * (n - 1)
    local i = floor(u) + 1
    local t = u - (i - 1)
    return v[i] + (v[min(n, i + 1)] - v[i]) * t
end

--- Mittel der Hoehen (Trapez) - fuer Tests der Volumenerhaltung
function Wave.Mean(f)
    local n, h = f.n, f.h
    local s = 0
    for i = 1, n do s = s + ((i == 1 or i == n) and 0.5 * h[i] or h[i]) end
    return s / (n - 1)
end

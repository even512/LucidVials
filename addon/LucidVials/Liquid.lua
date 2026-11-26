-- Fluessigkeits-Baustein (Delta "Fluessiges Leben", E2): eine Roehre mit lebendiger Fluessigkeit, gemeinsam fuer die
-- Einheitenrahmen (modules/UnitFrames/Skin.lua) und spaeter die Plaketten (E4).
--
-- Aufbau je Roehre (alles eigene Frames, kein Secure-Frame, keine Maus):
--   lb.bar    unsichtbare eigene StatusBar (Fuellungs-Textur Alpha 0). Sie bekommt den Wert per SetMinMaxValues/SetValue mit
--             Enum.StatusBarInterpolation.ExponentialEaseOut; die Engine gleitet selbst (S0: tau ~0,063 s). Lua reicht den
--             (oft secret) Wert nur durch - kein Vergleich, keine Rechnung, kein Lesen.
--   lb.trail  Schadensspur: zweite StatusBar HINTER der Fluessigkeit, glutig-orange; bekommt denselben Wert TRAIL.delay s
--             spaeter (C_Timer). Bei Schaden ragt sie rechts heraus und laeuft hinterher, bei Heilung liegt sie verdeckt unter
--             der Fluessigkeit. Ihr Alpha blendet nach jedem Wert ueber den Treiber aus (lesbare Zeitstempel, nie Leben).
--   lb.fill   Clip-Frame vom linken Roehrenende bis zur rechten Kante der Fuellungs-Textur von lb.bar (nur Anker); darin
--             Lagen fester Groesse wie bei den Plaketten: Grundfarbe, zwei Fluessigkeits-Lagen mit UV-Lauf, Blaeschen.
--   Kante    Die Fluessigkeit wird EDGE.reach x Hoehe ueber das Fuellungsende X hinaus gezeichnet; eine Abdecklage in
--             Leerglas-Farbe (lb.cover, uf-edge-cover, im Clip der Fluessigkeit) bildet die eigentliche Oberflaeche
--             (leichter Meniskus, Mittel genau auf X) und verdeckt den harten Schnitt. Das Randlicht (lb.surface,
--             uf-edge-rim) liegt in derselben Form genau auf dieser Linie. Neigung lb.tilt und Welle lb.wave aus der
--             Bewegungsphysik (LiquidPhysics.lua, E3) verschieben/neigen beide Lagen gleich per SetVertexOffset (begrenzt
--             auf EDGE.maxShift). Endblenden-Masken: Abdeckung laeuft rechts in die Kappe, Randlicht an beiden Enden aus.
--   lb.top    innerer Schatten, Randlicht, Glasglanz und der Bronze-Rahmen.
-- Rahmen: opts.frame = "health" | "power" => Gemini-Kapselrahmen (UF_FRAMES, 3-Slice, gespiegelt mit opts.mirror); die
-- Roehre liegt dann genau in seiner Glasoeffnung. opts.frame = true => alter Plaketten-Rahmen (np-frame, fuer E4).
-- Kapsel-Masken (aus der Glasoeffnung erzeugt) runden die Lagen; Form nach dem Seitenverhaeltnis (uf-mask-capsule / -thin).
-- Plaketten-Variante (opts.lite, E4/E4b, modules/Nameplates/StyleLiquid.lua): Kolben-Kammer-Look wie die Rahmen (Koerper
-- uf-body mit Drift, Luftspalt, Oberflaechen-Lichtband, Blaeschen, Kaustik) mit eigenen Werten fuer ~8 px Hoehe
-- (Liquid.LITE: hoeherer Luftspalt, weniger und breitere Scheiben, schnellere/kraeftigere Schwaden, keine Tropfen); statt
-- des harten Kolbens ein weicher Meniskus (Randlicht uf-edge-rim, im Clip) am Fuellungsende. Ohne Glasreflexe,
-- Ueberschwappen, Effekte (LiquidFx), eigenen Schatten/Glanz und Rahmen (die Plakette hat ihre eigenen); alle Lagen liegen
-- im Fluessigkeits-Clip, damit keine eigene Ebene mit dem Plaketten-Rahmen konkurriert. Wellensimulation nur fuer
-- schwappende Roehren (SetSloshEnabled), die uebrigen bleiben eine glatte Kammer mit Stroemung. Leistung (R6): je Roehre ein Takt (opts.stepEvery
-- s, Treiber laeuft sonst jedes Bild), Schwappen abschaltbar (Liquid.SetSloshEnabled: nur Ziel + naechste Plaketten), eine
-- sammelnde Spur (hoechstens ein Spur-Timer je Roehre), Ruhe fuer versteckte Plaketten (opts.hidden() => kein Schritt).
-- Kosten der Plaketten-Roehren je Bild misst stepAll mit debugprofilestop (Liquid.LiteStats).
-- Animation laeuft im eigenen Treiber (Style.lua: Style.AddFastStepper/WakeDriver, jedes Bild, ruht ohne
-- sichtbare Roehre). Die Physik (ns.LiquidPhysics) rechnet dort einmal je Bild global; im Stand schlaeft sie und es fallen
-- keine Schwapp-Setter an.
local ADDON_NAME, ns = ...
local Compat = ns.Compat
local Style = ns.Style

local Liquid = {}
ns.Liquid = Liquid

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
Liquid.BUBBLES_TEX = MEDIA .. "uf-bubbles"   -- 256 x 64, nahtlos
Liquid.FILL_TEX = MEDIA .. "uf-fill"         -- 512 x 128, grau (Lage A oben, B unten wie np-liquid), per Vertexfarbe getoent
Liquid.GLASS_TEX = MEDIA .. "uf-glass"       -- 512 x 64, Glasglanz (3-Slice)
Liquid.EMBER_TEX = MEDIA .. "uf-ember"       -- 512 x 128, Glut der Schadensspur (hell rechts)
Liquid.MASK_TEX = MEDIA .. "uf-mask-capsule" -- 256 x 64, Glasoeffnung von uf-frame-health (Enden fuer 6,5:1)
Liquid.MASK_THIN_TEX = MEDIA .. "uf-mask-thin" -- 256 x 32, Glasoeffnung von uf-frame-power (Enden fuer 12:1)
Liquid.MASK_THIN_RATIO = 9                     -- ab diesem Seitenverhaeltnis die schmale Maske
Liquid.MASK_XP_TEX = MEDIA .. "uf-mask-xp"     -- 1024 x 16, Glasoeffnung von uf-frame-power (Enden fuer 80:1, XP-Leiste)

-- Fluessigkeitskante (scripts/gen-unitframe-media.mjs, EDGE): Textur ueber [X - R, X + R], R = half x Hoehe, u = 0,5 auf
-- dem Fuellungsende X. reach = wie weit die Fluessigkeit ueber X hinaus gezeichnet wird (x Hoehe); maxShift = Grenze fuer
-- Neigung + Welle (x Hoehe), damit die Abdeckung den Schnitt bei X + reach immer deckt (half - maxShift >= reach).
Liquid.COVER_TEX = MEDIA .. "uf-edge-cover"
Liquid.SURFACE_TEX = MEDIA .. "uf-edge-rim"
Liquid.ENDRIGHT_TEX = MEDIA .. "uf-mask-endright"
Liquid.ENDFADE_TEX = MEDIA .. "uf-mask-endfade"
Liquid.FADEIN_TEX = MEDIA .. "uf-mask-fadein"   -- 64 x 4, Alpha-Rampe 0 -> 1 (weicher Einlauf der Glut am Fuellungsende)
Liquid.EDGE = { half = 1.0, reach = 0.55, maxShift = 0.42 }

-- Darstellung "piston" (Kolben-Kammer): Leben an der Laenge ablesbar; am Fuellungsende ein schmaler Kolben (uf-piston,
-- Breite piston x Hoehe), der die Kammer senkrecht abschliesst. Oben ein Luftspalt (gap x Hoehe).
-- Wasser wie echt: je Roehre ein 1D-Hoehenfeld (ns.LiquidWave, nodes Stuetzstellen Rohrbeginn -> Kolben) mit gedaempfter
-- Flachwasser-Welle, Reflexion an beiden Enden und Volumenerhaltung. Anregung: Laengsbeschleunigung (Physics.ax, sonst aus
-- tilt/wave abgeleitet) als Randsteigung, Stoesse (Physics.jolts/joltStrength/joltKind, sonst aus Spruengen der Welle),
-- Kolbenbewegung (lesbare Fuellbreite) und Treffer-Ruck. Dargestellt in bis zu sliceMax Scheiben ueber die Roehrenbreite: Luft
-- (uf-air, klares Glas), Oberflaechenlicht mit Schaum an bewegten Kaemmen (uf-surfglow, Verlauf je Scheibe) und Naessefilm
-- (uf-wet), jede Scheibe per SetVertexOffset senkrecht geschert (Hoehen der Scheibengrenzen aus Catmull-Rom); Licht und
-- Naesse laufen ueber die Scheiben hinweg nahtlos weiter (TexCoord je Scheibe, glowTile/wetTile x Hoehe). Die Oberflaeche ist
-- immer ein weicher Alpha-Verlauf IN der Textur, nie eine Polygonkante. Der Koerper (uf-body, Rauchschwaden, oben heller)
-- driftet langsam in zwei gegenlaeufigen Lagen; dazu ganz schwache Kaustik (uf-caustic, etwas mehr bei Bewegung), mehr
-- Blaeschen bei Bewegung und Spritzer (uf-drop, Atlas), die am Glas im Luftspalt landen,
-- herunterrinnen und verblassen. Leerglas hinter dem Kolben = uf-glassback (gleiche Farbe wie die Luft). Ausschlaege weich
-- begrenzt (up/down x Hoehe), nichts ragt ueber Glas oder Luftspalt. Alle Texturen aus den Gemini-Vorlagen v2-*.png.
Liquid.PISTON_TEX = MEDIA .. "uf-piston"     -- 32 x 256, Gemini-Kolben (ein Dichtring), ungleichmaessig schmal gestaucht
Liquid.BODY_TEX = MEDIA .. "uf-body"         -- 512 x 128, grau: Fluessigkeitskoerper (oben heller), waagrecht nahtlos
Liquid.AIR_TEX = MEDIA .. "uf-air"           -- 32 x 256, klares Glas ueber weicher Oberflaeche (Oberflaeche bei v = AIR.surf)
Liquid.GLASSBACK_TEX = MEDIA .. "uf-glassback" -- 16 x 64, Leerglas hinter dem Kolben (Farbe wie uf-air)
Liquid.SURFGLOW_TEX = MEDIA .. "uf-surfglow" -- 64 x 256, Lichtlinie + Band + Glow (Lage wie uf-air), waagrecht kachelbar
Liquid.WET_TEX = MEDIA .. "uf-wet"           -- 64 x 256, Naessefilm unter der Linie (Lage wie uf-air), waagrecht kachelbar
Liquid.CAUSTIC_TEX = MEDIA .. "uf-caustic"   -- 256 x 128, Kaustik-Linien, kachelbar
Liquid.DROP_TEX = MEDIA .. "uf-drop"         -- 128 x 32, Atlas aus dropCells Tropfen am Glas
-- AIR: margin = Ueberstand der Lagen ueber/unter dem Glas (x Hoehe); die Textur ist (1 + 2 x margin) Hoehen hoch, die
-- Oberflaeche liegt bei v = (margin + gap) / (1 + 2 x margin) (gen-unitframe-media.mjs AIR, der Test vergleicht).
-- slope: Hoehendifferenz (px) je px Kammer und Einheit Neigung (Ableitung aus tilt/wave); axGain dasselbe fuer Physics.ax
-- (Laufen: nur wenige Pixel). Begrenzung: das GANZE Profil wird gleichmaessig skaliert (Form bleibt), sobald es hoeher als
-- upGap x Luftspalt steigt oder tiefer als down x Hoehe faellt - der Boden liegt nie frei. hRef/thinPow: duennere Roehren
-- werden ruhiger angeregt ((h / hRef)^thinPow). push: Kolbenschub je (px/s)/Hoehe. Ist die Fuellbreite secret (Forever,
-- Spieler), gilt die ganze Roehre als Kammer (fallbackLen 1): die Welle reflektiert dann am verdeckten Roehrenende.
-- Koerper: eine Kachel uf-body = bodyTile Hoehen, Lage A driftet mit bodyDrift (Texturbreiten/s) und pendelt (bodySway,
-- Periode bodySwayT), Lage B gespiegelt gegenlaeufig (bodyDrift2), additiv mit body2Alpha +- body2Amp: die Schwaden
-- verformen sich langsam statt zu scrollen. dropCells/dropScale: Tropfen-Atlas und kleinster Groessenfaktor.
Liquid.PISTON = { piston = 0.15, gap = 0.25, margin = 0.5, slope = 0.05, axGain = 0.09, maxSlope = 1.5, fallbackLen = 1,
    nodes = 24, sliceMax = 16, sliceMin = 6, slicePx = 7, upGap = 0.9, down = 0.3, hRef = 19, thinPow = 1.5,
    joltGain = 2.4, glass = 0.031, eta = 5.2, waveJump = 4, push = 0.04, pushMax = 1.5,
    bodyTile = 3.2, bodyDrift = 0.006, bodyDrift2 = 0.0045, bodySway = 0.025, bodySwayT = 11, bodyAlpha = 0.96,
    bodyBright = 0.46, bodySat = 1.3, body2Alpha = 0.14, body2Amp = 0.06, body2T = 7.3, glowTile = 3, wetTile = 2.4,
    glowAlpha = 0.8, glowWhite = 0.15, foam = 0.3, foamCrest = 0.45,
    wetDecay = 0.22, wetAlpha = 0.3, wetBand = 0.15,
    drops = 6, dropCells = 4, dropScale = 0.5, dropSize = 0.26, dropMin = 0.35, dropG = 14, dropUp1 = 2.8, dropUp2 = 4.6,
    dropTop = 0.035, dropSlide = 0.12, dropFade = 0.45, dropAlpha = 1,
    caustic = 0.008, causticMove = 0.022, causticTile = 1.1, eGain = 6, bubbleBoost = 1.5,
    ruckK = 260, ruckDamp = 14, ruckKick = 0.9, ruckSleep = 0.002,
    colorFromBase = 1.6 }
Liquid.STYLES = { edge = true, piston = true }
-- Plaketten-Kammer (opts.lite): Abweichungen von PISTON fuer ~8 px hohe Roehren (Spieltest 18.11.: "bewegt sich
-- nichts" - bei 8 px waren Drift < 0,2 px/s, Luftspalt 2 px und die Duennen-Daempfung (8/19)^1,5 = 0,27 unsichtbar).
-- gap: Luftspalt (x Hoehe; uf-air wird per v-Ausschnitt angepasst, die Oberflaeche liegt dann wieder auf der Textur-
-- Oberflaeche), hRef: keine Duennen-Daempfung bis hRef px, Scheiben sliceMax/slicePx, drops 0, Schwaden schneller und
-- kraeftiger (bodyDrift ~1 px/s bei 8 px), bubbleAlpha/rimAlpha: Blaeschen und Meniskus am Fuellungsende.
Liquid.LITE = { gap = 0.36, down = 0.34, hRef = 9, sliceMax = 8, sliceMin = 4, slicePx = 14, drops = 0,
    bodyDrift = 0.05, bodyDrift2 = 0.035, bodySway = 0.06, bodySwayT = 6, body2Alpha = 0.24, body2Amp = 0.12, body2T = 4.1,
    bodyBright = 0.62, glowAlpha = 0.95, caustic = 0.03, causticMove = 0.05, bubbleAlpha = 0.5, rimAlpha = 0.8 }
local LITE_P = setmetatable(Liquid.LITE, { __index = Liquid.PISTON })
-- Ueberschwappen (Kolben-Kammer, Spieltest 16.11.): steigt der ungedaempfte Wellenkamm ueber crest x die Darstellungs-
-- grenze (upGap x Luftspalt), bricht die Welle - nur bei kraeftigen Stoessen (Landung aus Hoehe, Sturmangriff, Aufsitzen,
-- harter Stopp), nie beim normalen Laufen (tests/liquid-fx.test.mjs misst das). Dann: Gischt-Krone am Kamm (uf-fx-splash),
-- heller Schaumstreifen oben am Glas (Wasser schlaegt an die Decke), Tropfen am Glas ueber der Fluessigkeit (uf-drop, rinnen
-- herunter). Rein optisch, das Volumen der Wellensimulation bleibt erhalten. cooldown s, drops Anzahl (+ dropsMax bei hohem
-- Kamm), foam*/crown* Dauer (s), Alpha, Groesse (x Hoehe).
-- jolt: Stoss-Staerke (nach Duennen-Daempfung), ab der ein Stoss dieser Art die Welle direkt brechen laesst (normaler Sprung
-- ~0,51, Rueckstoss, Aufsitzen). Messung nach Spieltest (Anregung x2-3, Kamm/Grenze; Bruch ja/nein, tests/liquid-fx):
--   Laufen an/aus 1,43 nein | Reittier-Stopp 2,01 ja | Sturmangriff 3,25 ja | Sprung 0,64 ja (Stoss) | kleiner Hopser 0,24 nein
--   Landung nach 2 s 1,01 ja (Stoss) | Tasten-Drehen 3 rad/s 1,29 nein | schnelles Drehen 6 rad/s 1,71 ja | Treffer krit 0,84 nein
--   Aufsitzen 0,37 ja (Stoss)
-- Gischt (uf-fx2-foam, Effektbogen v2) und Schaumstreifen bleiben im Glas (Glasmaske, Spieltest Runde 4).
-- Runde 4, EIN Modell ("es muss sich die Waage halten"): jede Quelle als physikalische Groesse des Glases ("Glas in der
-- Hand"), dann EIN globaler Faktor PISTON.glass (Neigung = a/g x Kammerlaenge/Hoehe x glass) und fuer Stoesse dieselbe Kette mit
-- der Kopplung eta (Anteil eines senkrechten Geschwindigkeitsstosses, der als Schwappen ankommt). Messung (Kamm/Grenze, Bruch):
--   Quelle                       physikalische Groesse              Kamm   Bruch
--   Laufen 0->7 yd/s, ~0,3 s     Laengs 1,05 g                      0,66   nein
--   Reittier 0->14->0            Laengs 1,95 g                      1,10   ja
--   Sturmangriff 25 yd/s         Laengs 2,64 g (Filtergrenze)       2,17   ja
--   Tasten-Drehen 3,14 rad/s     Winkelbeschl. x 0,6 yd = 0,41 g    0,23   nein
--   schnelles Drehen 6 rad/s     0,80 g                             0,37   nein
--   Kamera-Schwenk (12 px/Bild)  wie Drehen: 0,38 g                 0,15   nein
--   Sprung (Abheben+Landung)     7,96 / 7,5 yd/s                    0,50   nein
--   Fall 1 s / 2 s               Aufprall 19 / 39 yd/s              0,96 / 1,93  ja
--   Treffer / kritisch           1,5 / 2,5 yd/s                     0,10 / 0,18  nein
--   Aufsitzen                    2,5 yd/s                           0,15   nein
-- Warum Laufen vorher kaum wirkte: die Laengsbeschleunigung kam zwar an (Filter 1,3 Hz, Spitze ~1 g), wurde aber auf dem Weg
-- zur Neigung geglaettet (6/s) und weich auf 1 begrenzt, waehrend die Drehung (x8) ungedaempft dazukam. Jetzt laufen alle
-- Quellen ungeglaettet (nur Rauschglaettung 25/s) und unbegrenzt durch dieselbe Formel.
Liquid.BREAK = { crest = 0.95, cooldown = 0.6, drops = 4, dropsMax = 6,
    foamT = 0.6, foamA = 0.9, foamW = 5, foamH = 0.35, crownT = 0.55, crownA = 0.85, crownW = 1.8, crownH = 0.8 }
Liquid.SPLASH_TEX = MEDIA .. "uf-fx2-foam"
-- Wanderndes Glanzlicht (Entscheidung 16.11. "Spiegelung wandert"): beim Drehen gleitet die Spiegelung ueber Glas und
-- Oberflaeche, die Fluessigkeit bleibt fast ruhig. Lage aus Physics.yaw (Drehwinkel, umlaufend): eine volle Drehung = passes
-- Durchlaeufe ueber die Roehre; der Umlauf-Sprung liegt unsichtbar ausserhalb der Enden. glassW/surfW/surfH x Hoehe; Alpha
-- dezent und an beiden Enden ueber fade (Anteil der Laenge) weich ein-/ausgeblendet, waehrend der Drehung etwas heller
-- (spinBoost, voll ab spinRef rad/s). surfOff: Versatz des Oberflaechenglanzes (Anteil des Laufwegs); surfLow: Glanz etwas
-- unter der Linie (x surfH); edgeY: Lage im Kanten-Modus (x Hoehe unter der Oberkante); inset: halber Texel des Atlas.
Liquid.GLINT_TEX = MEDIA .. "uf-glint"       -- 256 x 64, Atlas (gen-unitframe-media.mjs GLINT): rechts Oberflaechenglanz
-- Glasreflexe wie auf einem Glaszylinder (Spieltest Runde 4, Gemini-Glasreflexe v3, gen-unitframe-media.mjs GLAS3):
-- Lagen (scharfe Glanzlinie, sehr dezente Umgebungsspiegelung, feines Glitzern, unteres Randlicht) liegen ueber die ganze
-- Roehrenbreite auf dem Zylinderprofil unter dem Winkel a = a0 + pitch x pitchGain (rad, 0 = Mitte, + = oben): senkrechte Lage
-- 0,5 x Hoehe x sin(a), Dicke x cos(a) (zum Rand gestaucht), Alpha x cos(a)^1,5 (zum Rand ausgeblendet). Laengs wandern sie
-- per UV mit Physics.yaw (span = gezeigter Texturanteil, yawPar = Parallaxe, ganzzahlig damit der yaw-Umlauf 2pi->0 nicht springt: die Glanzlinie wandert staerker als die
-- Umgebung). pitch = Physics.pitch (Cursor-y beim Kamera-Ziehen, federt zurueck). Ersetzt den frueheren uf-glint-Glasreflex
-- (uf-glint bleibt nur fuer den Glanz auf der Fluessigkeitsoberflaeche). Texturen austauschbar (tex je Lage).
Liquid.REFL = { layers = {
    { tex = MEDIA .. "uf-glass-env", a0 = 0.25, pitchGain = -0.35, yawPar = 1, span = 0.45, thick = 1.1, alpha = 0.10 },
    { tex = MEDIA .. "uf-glass-sparkle", a0 = 0.35, pitchGain = -0.5, yawPar = 1, span = 0.5, thick = 0.8, alpha = 0.3 },
    { tex = MEDIA .. "uf-glass-specular", a0 = 0.95, pitchGain = -0.85, yawPar = 2, span = 0.5, thick = 0.24, alpha = 0.42 },
    { tex = MEDIA .. "uf-glass-rim", a0 = -1.12, pitchGain = -0.3, yawPar = 1, span = 0.5, thick = 0.2, alpha = 0.21 },
}, minCos = 0.12, maxA = 1.45, uPerTurn = 1 }
Liquid.GLINT = { passes = 1, glassW = 1.2, glassAlpha = 0.16, surfW = 1.8, surfH = 0.32, surfAlpha = 0.14, surfOff = 0.07,
    surfLow = 0.15, fade = 0.12, spinBoost = 0.5, spinRef = 3, edgeY = 0.2, inset = 1 / 256 }

-- Gemini-Kapselrahmen (Quell-Pixel der Vorlage; Glasoeffnung open*, 3-Slice-Schnitte slice*; gleich in
-- scripts/gen-unitframe-media.mjs measurements(), der Test vergleicht). dy = senkrechter Versatz (x Rahmenhoehe):
-- Lebens- und Ressourcenbalken liegen bei Blizzard dicht uebereinander, die Rahmen ruecken etwas auseinander.
Liquid.UF_FRAMES = {
    health = { tex = MEDIA .. "uf-frame-health", srcW = 1921, srcH = 358, openL = 146, openT = 36, openR = 1743,
        openB = 321, sliceL = 240, sliceR = 1653, dy = 0.08 },
    power = { tex = MEDIA .. "uf-frame-power", srcW = 1920, srcH = 240, openL = 149, openT = 35, openR = 1763,
        openB = 204, sliceL = 210, sliceR = 1702, dy = -0.15 },
}
-- Rahmenhoehe = Hoehe von Blizzards Balken + max(extraMin, extraRel x Hoehe); die Glasoeffnung ergibt sich daraus
Liquid.UF_FRAME = { extraRel = 0.2, extraMin = 3 }
-- Glasglanz (uf-glass): Seitenverhaeltnis der Quelle, Kappe (u) je Seite, Alpha
Liquid.GLASS = { aspect = 6.5431, cap = 0.0764, alpha = 0.55 }
-- Glut der Schadensspur (uf-ember: weicher Schein + Funken, beidseitig auslaufend): Laenge und Hoehe (x Roehrenhoehe),
-- Alpha. Die Spur-StatusBar selbst bleibt unsichtbar (nur Anker der Glut).
Liquid.EMBER = { length = 6, height = 1.0, alpha = 1, fadeIn = 0.6 }

-- Schadensspur: Verzoegerung (s), Halten nach dem Nachziehen, Ausblenden (s), Farbe/Alpha
Liquid.TRAIL = { delay = 0.5, hold = 0.75, fade = 0.85, color = { 1.0, 0.50, 0.14 }, alpha = 0.95 }
-- Blaeschen: Steiggeschwindigkeit (Texturhoehen/s), Alpha, gezeigter Hoehenanteil der Textur, Seitenverhaeltnis der Textur
Liquid.BUBBLES = { speed = 0.09, alpha = 0.32, vSpan = 0.6, aspect = 4, sway = 0.02, swayPeriod = 3.7 }
-- Oberflaeche: Alpha-Grundwert/Flackern, Neigung (Anteil der Hoehe je Einheit tilt)
-- Schwappen (E3): waveTilt = Anteil der Welle an der Neigung, surge = Verschiebung der Oberflaeche je Einheit Welle
-- (x Hoehe), flowShift/bubbleShift = UV-Versatz der Fluessigkeit/Blaeschen je Einheit Welle, foam = Zusatz-Alpha des
-- Randlichts je Einheit |Welle|; rimMix = Anteil Weiss in der Farbe des Randlichts (Rest = Fluessigkeitsfarbe).
Liquid.SURFACE = { alphaBase = 0.26, alphaAmp = 0.05, rate = 2.3, tiltScale = 0.5, waveTilt = 0.6,
    surge = 0.35, flowShift = 0.05, bubbleShift = 0.08, foam = 0.2, rimMix = 0.55 }
-- leerer Teil der Roehre und Glas (wie Style.TUBE)
Liquid.TUBE = { backTop = { 0.10, 0.05, 0.03, 1 }, backBottom = { 0.04, 0.02, 0.015, 1 }, insetAlpha = 0.7,
    glassAlpha = 0.24, glassTop = 0.14, glassHeight = 0.18, under = 0.15 }
-- Bronze-Rahmen um die Roehre (np-frame): Rahmenhoehe = Roehrenhoehe + extra (schmal, weil Blizzards Lebens- und
-- Manaleiste dicht uebereinander liegen; der Schlitz ist dann etwas schmaler als die Roehre, das Band deckt ihre Kanten),
-- seitlicher Ueberstand = Kappenrand x side
Liquid.FRAME = { extra = 4, side = 0.55 }

local MIN_HEIGHT = 2
local tubes = {}         -- alle Roehren (fuer den Treiber), schwache Schluessel
setmetatable(tubes, { __mode = "k" })
local count = 0
local stepperOn = false
local IMMEDIATE, EXP
local interpBroken = false -- SetValue mit zweitem Argument warf einmal: ab dann ohne

local applySlosh, layoutPiston, createChamber -- unten definiert (Layout/Create brauchen sie)
local MASK_KEYS = { "backMask", "trailMask", "fillMask", "topMask", "glowMask" }
local WHITE_RES = { 1, 1, 1 }

local function now() return type(GetTime) == "function" and GetTime() or 0 end

local function readEnum()
    local e = type(Enum) == "table" and Enum.StatusBarInterpolation or nil
    if type(e) ~= "table" then return end
    IMMEDIATE, EXP = Compat.Num(e.Immediate), Compat.Num(e.ExponentialEaseOut)
end

--- true, wenn der Client die Interpolation kennt (Enum vorhanden und nicht als defekt erkannt)
function Liquid.CanGlide()
    if EXP == nil then readEnum() end
    return EXP ~= nil and not interpBroken
end

--- Alpha der Schadensspur (StatusBar = Anker) und ihrer Glut (eigener Frame ueber der Fluessigkeit) gemeinsam
local function setTrailAlpha(lb, a)
    lb.trail:SetAlpha(a)
    if lb.glow then lb.glow:SetAlpha(a) end
end

local function snap(t)
    if Style and Style.SnapTexture then Style.SnapTexture(t) end
    return t
end

--- Kolben-Kammer: Lagen werden per SetVertexOffset geschert - NICHT aufs Pixelraster rasten (sonst Stufen und Versaetze an
--- den Scheibengrenzen); Gegenstueck zu snap()
local function free(t)
    if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, false) end
    if t.SetTexelSnappingBias then pcall(t.SetTexelSnappingBias, t, 0) end
    return t
end

--- Wanderndes Glanzlicht anlegen: Glasreflex vorn auf dem Glas (lb.top, ueber Kolben und Glasglanz, unter dem Rahmen) und
--- Glanz auf dem Oberflaechenband (im Fluessigkeits-Clip). Beide additiv, weiss, nicht aufs Pixelraster gerastet.
local function createReflex(lb)
    local G, R = Liquid.GLINT, Liquid.REFL
    lb.refl = {}
    for i, L in ipairs(R.layers) do
        local t = free(lb.top:CreateTexture(nil, "ARTWORK", nil, 4))
        t:SetTexture(L.tex, "REPEAT", "CLAMP")
        t:SetVertexColor(1, 0.98, 0.95)
        lb.refl[i] = t
    end
    local sf = free(lb.fillIn:CreateTexture(nil, "ARTWORK", nil, 5))
    sf:SetTexture(Liquid.GLINT_TEX)
    sf:SetTexCoord(0.5 + G.inset, 1 - G.inset, 0, 1)
    for _, t in ipairs(lb.refl) do
        if t.SetBlendMode then t:SetBlendMode("ADD") end
        t:SetAlpha(0)
    end
    if sf.SetBlendMode then sf:SetBlendMode("ADD") end
    sf:SetAlpha(0)
    lb.glintG, lb.glintS = lb.refl[3], sf -- glintG = Glanzlinie
    lb.glintDirty = true
end

-- weiche Endblende: 0 ausserhalb von (0, 1), an beiden Enden ueber f (Anteil) per Smoothstep auf 1
local function endFade(u, f)
    if u <= 0 or u >= 1 then return 0 end
    local a = math.min(1, u / f, (1 - u) / f)
    return a * a * (3 - 2 * a)
end

--- Wanderndes Glanzlicht, ein Bild: Lage aus Physics.yaw (lesbare eigene Zahlen, nie Leben). Setter nur, wenn sich Winkel,
--- Drehrate, Layout/Darstellung oder (Kolben-Kammer) die Oberflaeche bewegt haben - im Stand nichts.
local function stepReflex(lb)
    local PH = ns.LiquidPhysics
    local yaw = PH and Compat.Num(PH.yaw) or 0
    local spin = PH and Compat.Num(PH.spin) or 0
    local pitch = PH and Compat.Num(PH.pitch) or 0
    local piston = lb.style == "piston"
    if not lb.glintDirty and lb.glYaw == yaw and lb.glSpin == spin and lb.glPitch == pitch and lb.glStyle == lb.style
        and not (piston and lb.pMoved) then return end
    lb.glintDirty, lb.pMoved, lb.glYaw, lb.glSpin, lb.glPitch = false, false, yaw, spin, pitch
    local G, h, w = Liquid.GLINT, lb.h or 10, lb.w or 100
    local sf = lb.glintS
    if lb.glStyle ~= lb.style then
        lb.glStyle = lb.style
        -- Kolben-Kammer: ueber Luft und Oberflaechenband; Kante: unter der Abdeckung (nie ueber dem Leerglas)
        if piston then sf:SetDrawLayer("ARTWORK", 5) else sf:SetDrawLayer("BORDER", 1) end
    end
    local boost = 1 + G.spinBoost * math.min(1, math.abs(spin) / G.spinRef)
    local pos = (yaw / (2 * math.pi) * G.passes) % 1
    if pos ~= pos then pos = 0 end
    -- Glasreflexe auf dem Zylinder: laengs mit yaw (umlaufend, Parallaxe), senkrecht mit pitch (gestaucht/ausgeblendet am Rand)
    local R = Liquid.REFL
    local cx
    for i, L in ipairs(R.layers) do
        local t = lb.refl[i]
        local a = L.a0 + pitch * L.pitchGain
        if a > R.maxA then a = R.maxA elseif a < -R.maxA then a = -R.maxA end
        local c = math.cos(a)
        local u = (yaw / (2 * math.pi) * R.uPerTurn * L.yawPar + i * 0.31) % 1 -- laengs mit yaw (Parallaxe je Lage)
        if u ~= u then u = 0 end
        t:ClearAllPoints()
        t:SetPoint("LEFT", lb.root, "LEFT", 0, 0.5 * h * math.sin(a))
        t:SetSize(w, math.max(1, L.thick * h * math.max(R.minCos, c)))
        t:SetTexCoord(u, u + L.span, 0, 1)
        t:SetAlpha(L.alpha * boost * (c > 0 and c ^ 1.5 or 0))
        if i == 3 then cx = u end -- Glanzlinie (fuer Tests/Debug: UV-Lage)
    end
    -- Oberflaechenglanz: folgt in der Kolben-Kammer der Wellenhoehe an seiner Stelle (wie die Scheiben in stepPiston)
    local sw = G.surfW * h
    local sx = -sw / 2 + ((pos + G.surfOff) % 1) * (w + sw)
    local sh = G.surfH * h
    local y = -G.edgeY * h
    if piston then
        local P = Liquid.PISTON
        local len = lb.pLen or w
        local xn = len > 0 and sx / len or 0
        if xn > 1 then xn = 1 elseif xn < 0 then xn = 0 end
        y = -P.gap * h + (ns.LiquidWave.Sample(lb.field, xn) * h + (lb.ruck or 0)) * (lb.pScale or 1) - G.surfLow * sh
    end
    sf:ClearAllPoints()
    sf:SetPoint("CENTER", lb.root, "TOPLEFT", sx, y)
    sf:SetSize(sw, sh)
    sf:SetAlpha(G.surfAlpha * boost * endFade(sx / w, G.fade))
    local r, gg, b = lb.glowR or 1, lb.glowG or 1, lb.glowB or 1
    sf:SetVertexColor(0.5 + 0.5 * r, 0.5 + 0.5 * gg, 0.5 + 0.5 * b)
    lb.glX, lb.glSX, lb.glSY = cx, sx, y -- fuer Tests/Debug (glX = scharfer Reflex)
end
Liquid.StepReflex = stepReflex

local function newMask(frame, path)
    local ok, m = pcall(frame.CreateMaskTexture, frame)
    if not ok or not m then return nil end
    if not pcall(m.SetTexture, m, path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then return nil end
    return m
end

local function addMask(t, m) if t and m then pcall(t.AddMaskTexture, t, m) end end

local function setBarTexture(bar, path)
    local ok = pcall(bar.SetStatusBarTexture, bar, path)
    if not ok then return nil end
    local okT, tex = pcall(bar.GetStatusBarTexture, bar)
    return (okT and type(tex) == "table") and tex or nil
end

local function threeSlice(parent, layer, path, capU, sub)
    local l, m, r = parent:CreateTexture(nil, layer, nil, sub), parent:CreateTexture(nil, layer, nil, sub),
        parent:CreateTexture(nil, layer, nil, sub)
    for _, t in ipairs({ l, m, r }) do
        t:SetTexture(path)
        snap(t)
    end
    l:SetTexCoord(0, capU, 0, 1)
    m:SetTexCoord(capU, 1 - capU, 0, 1)
    r:SetTexCoord(1 - capU, 1, 0, 1)
    return l, m, r
end

local backWhite -- weisse Verlaufsfarbe (einmal angelegt) fuer das Leerglas der Kolben-Kammer

--- Leerer Teil der Roehre: Kante = dunkler Verlauf (TUBE back), Kolben-Kammer = klares Glas (uf-glassback, Farbe wie uf-air)
local function setBack(lb, piston)
    local T, b = Liquid.TUBE, lb.back
    if piston then
        b:SetTexture(Liquid.GLASSBACK_TEX)
        backWhite = backWhite or CreateColor(1, 1, 1, 1)
        if not pcall(b.SetGradient, b, "VERTICAL", backWhite, backWhite) then b:SetVertexColor(1, 1, 1, 1) end
        return
    end
    b:SetColorTexture(1, 1, 1, 1)
    local okG = pcall(b.SetGradient, b, "VERTICAL",
        CreateColor(T.backBottom[1], T.backBottom[2], T.backBottom[3], T.backBottom[4]),
        CreateColor(T.backTop[1], T.backTop[2], T.backTop[3], T.backTop[4]))
    if not okG then b:SetColorTexture(T.backTop[1], T.backTop[2], T.backTop[3], T.backTop[4]) end
end

--- Neue Roehre als Kind von parent. opts: { frame = "health"|"power" (Gemini-Kapselrahmen) oder true (np-frame),
--- mirror = true (Rahmen waagrecht gespiegelt, Zierkappe links), trail = true, mask = Pfad (feste Kapsel-Maske statt der Wahl
--- nach Seitenverhaeltnis), dy = senkrechter Versatz x Rahmenhoehe statt UF_FRAMES[frame].dy, fizz = false (kein Sprudeln) }
function Liquid.Create(parent, opts)
    opts = opts or {}
    local T = Liquid.TUBE
    local lb = { opts = opts, tilt = 0, wave = 0, sloshU = 0, trailOn = opts.trail ~= false, smooth = true, epoch = 0 }
    lb.geo = type(opts.frame) == "string" and Liquid.UF_FRAMES[opts.frame] or nil
    count = count + 1
    lb.phase = (count * 0.618) % 1
    lb.sloshGain = 0.88 + 0.24 * lb.phase -- leichter Versatz zwischen den Roehren (gleiche Richtung)
    -- opts.motion: Bewegungs-Daempfung dieser Roehre (Kolben-Kammer: Neigung, Stoesse; 1 = wie Leben/Ressource). Die Neigung
    -- waechst mit der Kammerlaenge in Roehrenhoehen - die lange, schmale XP-Roehre kippte sonst unnatuerlich stark (18.11.)
    lb.motion = type(opts.motion) == "number" and opts.motion >= 0 and opts.motion <= 1 and opts.motion or 1
    local lite = opts.lite == true
    lb.lite = lite
    lb.PP = lite and LITE_P or Liquid.PISTON -- Kolben-Kammer-Werte dieser Roehre
    lb.stepEvery = (lite and type(opts.stepEvery) == "number" and opts.stepEvery > 0) and opts.stepEvery or nil
    lb.hiddenFn = type(opts.hidden) == "function" and opts.hidden or nil
    local root = CreateFrame("Frame", nil, parent)
    lb.root = root
    -- leerer Teil (dunkel, Verlauf), unter allem
    lb.back = root:CreateTexture(nil, "BACKGROUND", nil, 0)
    setBack(lb, false)
    snap(lb.back)
    lb.backMask = newMask(root, Liquid.MASK_TEX)
    addMask(lb.back, lb.backMask)
    -- Schadensspur (eigene StatusBar hinter der Fluessigkeit): die Fuellung selbst bleibt unsichtbar (nur Anker), sichtbar
    -- ist die weiche Glut an ihrem vorderen Ende
    lb.trail = CreateFrame("StatusBar", nil, root)
    lb.trailTex = setBarTexture(lb.trail, Style.FILL_TEX)
    local tc = Liquid.TRAIL.color
    pcall(lb.trail.SetStatusBarColor, lb.trail, tc[1], tc[2], tc[3], 0)
    if lb.trailTex then lb.trailTex:SetAlpha(0) end
    lb.trailMask = newMask(lb.trail, Liquid.MASK_TEX)
    addMask(lb.trailTex, lb.trailMask)
    snap(lb.trailTex)
    -- Glut: Schein + Funken, Spitze am vorderen (rechten) Ende der Spur, nach links weich verloeschend; eigener Frame UEBER
    -- Fluessigkeit und Abdeckung (additiv), der nur rechts vom Fuellungsende zeichnet (Clip ab dem Fuellungsende, weich
    -- eingeblendet): Glut nur im gerade verlorenen Abschnitt, nie ueber der Fluessigkeit (Heilung/Regeneration: die Spur
    -- liegt links vom Fuellungsende und wird ganz weggeschnitten). Blendet mit der Spur aus.
    lb.glow = CreateFrame("Frame", nil, root)
    pcall(lb.glow.SetClipsChildren, lb.glow, true)
    lb.ember = snap(lb.glow:CreateTexture(nil, "ARTWORK", nil, 0))
    lb.ember:SetTexture(Liquid.EMBER_TEX)
    if lb.ember.SetBlendMode then lb.ember:SetBlendMode("ADD") end
    lb.ember:SetAlpha(Liquid.EMBER.alpha)
    lb.glowMask = newMask(lb.glow, Liquid.MASK_TEX)
    addMask(lb.ember, lb.glowMask)
    -- weicher Einlauf am Fuellungsende: Rampe 0 -> 1 ueber GLOWIN x Hoehe, rechts davon per CLAMP voll
    local okM, fm = pcall(lb.glow.CreateMaskTexture, lb.glow)
    if okM and fm and pcall(fm.SetTexture, fm, Liquid.FADEIN_TEX, "CLAMP", "CLAMP") then
        lb.glowIn = fm
        addMask(lb.ember, fm)
    end
    setTrailAlpha(lb, 0)
    -- unsichtbare Treiber-Bar
    lb.bar = CreateFrame("StatusBar", nil, root)
    lb.barTex = setBarTexture(lb.bar, Style.FILL_TEX)
    if lb.barTex then lb.barTex:SetAlpha(0) end
    -- Fluessigkeit im Clip-Frame
    lb.fill = CreateFrame("Frame", nil, root)
    pcall(lb.fill.SetClipsChildren, lb.fill, true)
    lb.fillIn = CreateFrame("Frame", nil, lb.fill)
    local fi = lb.fillIn
    lb.base = snap(fi:CreateTexture(nil, "BORDER", nil, -3))
    lb.base:SetTexture(Style.FILL_TEX)
    lb.flow = snap(fi:CreateTexture(nil, "BORDER", nil, -2))
    lb.flow:SetTexture(Style.FLOW_TEX_MONO, "REPEAT", "REPEAT")
    lb.flow2 = snap(fi:CreateTexture(nil, "BORDER", nil, -1))
    lb.flow2:SetTexture(Style.FLOW_TEX_MONO, "REPEAT", "REPEAT")
    if lb.flow2.SetBlendMode then lb.flow2:SetBlendMode("ADD") end
    lb.bubbles = snap(fi:CreateTexture(nil, "BORDER", nil, 0))
    lb.bubbles:SetTexture(Liquid.BUBBLES_TEX, "REPEAT", "REPEAT")
    if lb.bubbles.SetBlendMode then lb.bubbles:SetBlendMode("ADD") end
    lb.bubbles:SetAlpha(Liquid.BUBBLES.alpha)
    -- Abdeckung in Leerglas-Farbe: bildet die Oberflaeche und verdeckt den Schnitt hinter dem Fuellungsende
    lb.cover = snap(fi:CreateTexture(nil, "ARTWORK", nil, 0))
    lb.cover:SetTexture(Liquid.COVER_TEX)
    local okC = pcall(lb.cover.SetGradient, lb.cover, "VERTICAL",
        CreateColor(T.backBottom[1], T.backBottom[2], T.backBottom[3], 1), CreateColor(T.backTop[1], T.backTop[2], T.backTop[3], 1))
    if not okC then lb.cover:SetVertexColor(T.backTop[1], T.backTop[2], T.backTop[3], 1) end
    lb.fillMask = newMask(fi, Liquid.MASK_TEX)
    for _, t in ipairs({ lb.base, lb.flow, lb.flow2, lb.bubbles, lb.cover }) do addMask(t, lb.fillMask) end
    lb.coverEnd = newMask(fi, Liquid.ENDRIGHT_TEX)
    addMask(lb.cover, lb.coverEnd)
    -- oben: Oberflaeche, Schatten, Glas, Rahmen
    lb.top = CreateFrame("Frame", nil, root)
    -- Randlicht auf der Oberflaechen-Linie (gleiche Form und Verformung wie die Abdeckung); Plaketten-Variante: im Clip
    lb.surface = snap((lite and fi or lb.top):CreateTexture(nil, "ARTWORK", nil, lite and 4 or 0))
    lb.surface:SetTexture(Liquid.SURFACE_TEX)
    if lb.surface.SetBlendMode then lb.surface:SetBlendMode("ADD") end
    if lite then
        addMask(lb.surface, lb.fillMask)
        lb.rimEnd = newMask(fi, Liquid.ENDFADE_TEX)
        createChamber(lb, fi)
        lb.bubbles:SetAlpha(LITE_P.bubbleAlpha)
        Liquid.SetTint(lb, { tex = "mono", color = { 0.46, 0.82, 0.30 } })
        Liquid.SetStyle(lb, "piston")
        root:Hide()
        tubes[lb] = true
        return lb
    end
    lb.inset = snap(lb.top:CreateTexture(nil, "ARTWORK", nil, 1))
    lb.inset:SetTexture(Style.INSET_TEX)
    lb.inset:SetVertexColor(0, 0, 0, T.insetAlpha)
    if lb.geo then
        lb.glassL, lb.glassM, lb.glassR = threeSlice(lb.top, "ARTWORK", Liquid.GLASS_TEX, Liquid.GLASS.cap, 2)
        for _, t in ipairs({ lb.glassL, lb.glassM, lb.glassR }) do t:SetVertexColor(1, 0.98, 0.94, Liquid.GLASS.alpha) end
    else
        lb.glass = snap(lb.top:CreateTexture(nil, "ARTWORK", nil, 2))
        lb.glass:SetTexture(Style.GLASS_TEX)
        lb.glass:SetVertexColor(1, 0.97, 0.92, T.glassAlpha)
    end
    lb.topMask = newMask(lb.top, Liquid.MASK_TEX)
    for _, t in ipairs({ lb.surface, lb.inset }) do addMask(t, lb.topMask) end
    lb.rimEnd = newMask(lb.top, Liquid.ENDFADE_TEX)
    addMask(lb.surface, lb.rimEnd)
    -- wanderndes Glanzlicht (Glas + Oberflaeche), Kapselform wie die Lagen darunter
    createReflex(lb)
    for _, t in ipairs(lb.refl) do addMask(t, lb.topMask) end
    addMask(lb.glintS, lb.fillMask)
    -- Ueberschwappen: Schaumstreifen an der Glasdecke und Gischt-Krone am Kamm (im Glas)
    lb.brkFoam = free(lb.top:CreateTexture(nil, "ARTWORK", nil, 5))
    lb.brkFoam:SetTexture(Liquid.GLINT_TEX)
    lb.brkFoam:SetTexCoord(0.5 + Liquid.GLINT.inset, 1 - Liquid.GLINT.inset, 0, 1)
    lb.brkCrown = free(lb.top:CreateTexture(nil, "ARTWORK", nil, 6))
    lb.brkCrown:SetTexture(Liquid.SPLASH_TEX)
    for _, t in ipairs({ lb.brkFoam, lb.brkCrown }) do
        if t.SetBlendMode then t:SetBlendMode("ADD") end
        t:Hide()
    end
    addMask(lb.brkFoam, lb.topMask)
    addMask(lb.brkCrown, lb.topMask) -- alles bleibt im Glas
    -- Effekte (LiquidFx.lua): Anstiegsband, Heilung, Treffer, Ressourcen-Strom, Schlieren - eigene Lagen, gekapselt
    if ns.LiquidFx then ns.LiquidFx.Attach(lb) end
    createChamber(lb, fi)
    lb.piston = snap(lb.top:CreateTexture(nil, "ARTWORK", nil, 3))
    lb.piston:SetTexture(Liquid.PISTON_TEX)
    addMask(lb.piston, lb.topMask)
    if lb.geo then
        lb.left, lb.mid, lb.right = threeSlice(lb.top, "OVERLAY", lb.geo.tex, lb.geo.sliceL / lb.geo.srcW)
    elseif opts.frame then
        local G = Style.FRAME_GEOMETRY
        lb.left, lb.mid, lb.right = threeSlice(lb.top, "OVERLAY", Style.FRAME_TEX, G.cap / G.w)
    end
    if lb.left then lb.frameTex = { lb.left, lb.mid, lb.right } end -- Treffer-Puls (LiquidFx)
    Liquid.SetTint(lb, { tex = "mono", color = { 0.46, 0.82, 0.30 } })
    Liquid.SetStyle(lb, "edge")
    root:Hide()
    tubes[lb] = true
    return lb
end

--- Kolben-Kammer (Kammer-Clip = Fluessigkeits-Clip): Kaustik, Luft-, Naesse- und Licht-Scheiben, Tropfen
function createChamber(lb, fi)
    local P = lb.PP
    lb.field = ns.LiquidWave.New(P.nodes)
    lb.caustic = free(fi:CreateTexture(nil, "ARTWORK", nil, 0))
    lb.caustic:SetTexture(Liquid.CAUSTIC_TEX, "REPEAT", "REPEAT")
    if lb.caustic.SetBlendMode then lb.caustic:SetBlendMode("ADD") end
    lb.pistonTex = { lb.caustic }
    lb.airS, lb.glowS, lb.wetS, lb.glowC, lb.wetC = {}, {}, {}, {}, {}
    for i = 1, P.sliceMax do
        local a = free(fi:CreateTexture(nil, "ARTWORK", nil, 1))
        a:SetTexture(Liquid.AIR_TEX)
        local wt = free(fi:CreateTexture(nil, "ARTWORK", nil, 2))
        wt:SetTexture(Liquid.WET_TEX, "REPEAT", "CLAMP")
        local g = free(fi:CreateTexture(nil, "ARTWORK", nil, 3))
        g:SetTexture(Liquid.SURFGLOW_TEX, "REPEAT", "CLAMP")
        for _, t in ipairs({ wt, g }) do
            if t.SetBlendMode then t:SetBlendMode("ADD") end
        end
        lb.airS[i], lb.wetS[i], lb.glowS[i] = a, wt, g
    end
    for k = 0, P.sliceMax do -- Farben der Scheibengrenzen (Verlauf je Scheibe, einmal angelegt, im Bild nur Felder gesetzt)
        lb.glowC[k] = CreateColor(1, 1, 1, P.glowAlpha)
        lb.wetC[k] = CreateColor(1, 1, 1, 0)
    end
    lb.gradOK = pcall(lb.glowS[1].SetGradient, lb.glowS[1], "HORIZONTAL", lb.glowC[0], lb.glowC[1])
    for _, t in ipairs(lb.pistonTex) do addMask(t, lb.fillMask) end
    for i = 1, P.sliceMax do
        addMask(lb.airS[i], lb.fillMask)
        addMask(lb.wetS[i], lb.fillMask)
        addMask(lb.glowS[i], lb.fillMask)
    end
    lb.drops = {}
    for i = 1, P.drops do
        local d = free(fi:CreateTexture(nil, "ARTWORK", nil, 4))
        d:SetTexture(Liquid.DROP_TEX)
        if d.SetBlendMode then d:SetBlendMode("ADD") end
        addMask(d, lb.fillMask)
        d:Hide()
        lb.drops[i] = { tex = d, on = false, x = 0, y = 0, vx = 0, vy = 0, stick = false, a = 0 }
    end
    lb.hk, lb.wk, lb.fk = {}, {}, {}
    for k = 0, P.sliceMax do lb.hk[k], lb.wk[k], lb.fk[k] = 0, 0, 0 end
    lb.sliceN, lb.ruck, lb.ruckV, lb.dT, lb.dropsOn, lb.wetOn = P.sliceMax, 0, 0, 0, 0, false
    lb.vtx = lb.airS[1].SetVertexOffset ~= nil
end

local function maskPath(lb)
    if lb.opts.mask then return lb.opts.mask end -- feste Maske (sehr lange Roehre: XP-Leiste)
    local ratio = (lb.w and lb.h and lb.h > 0) and lb.w / lb.h or 6
    local path = ratio >= Liquid.MASK_THIN_RATIO and Liquid.MASK_THIN_TEX or Liquid.MASK_TEX
    -- offenes Ende (Liquid.SetOpenEnd): Maske ohne Kapsel-Rundung auf dieser Seite (uf-mask-*-openl/-openr)
    if lb.openEnd == "left" then return path .. "-openl" elseif lb.openEnd == "right" then return path .. "-openr" end
    return path
end

--- Kapselrahmen (lb.geo) um die Roehre legen: 3-Slice, Kappen unverzerrt, gespiegelt mit opts.mirror. s = Bildschirm-
--- Einheiten je Quell-Pixel. Die Roehre (root) ist genau die Glasoeffnung.
local function layoutUfFrame(lb, s)
    local F, root = lb.geo, lb.root
    local uL, uR = F.sliceL / F.srcW, F.sliceR / F.srcW
    local mL, mR = F.openL, F.srcW - F.openR          -- Rand links/rechts der Oeffnung (Quell-Pixel)
    local cL, cR = F.sliceL, F.srcW - F.sliceR        -- Kappenbreiten
    if lb.opts.mirror then
        mL, mR, cL, cR = mR, mL, cR, cL
        lb.left:SetTexCoord(1, uR, 0, 1)
        lb.mid:SetTexCoord(uR, uL, 0, 1)
        lb.right:SetTexCoord(uL, 0, 0, 1)
    else
        lb.left:SetTexCoord(0, uL, 0, 1)
        lb.mid:SetTexCoord(uL, uR, 0, 1)
        lb.right:SetTexCoord(uR, 1, 0, 1)
    end
    local top, bottom = F.openT * s, (F.srcH - F.openB) * s
    lb.left:ClearAllPoints()
    lb.left:SetPoint("TOPLEFT", root, "TOPLEFT", -mL * s, top)
    lb.left:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", -mL * s, -bottom)
    lb.left:SetWidth(cL * s)
    lb.right:ClearAllPoints()
    lb.right:SetPoint("TOPRIGHT", root, "TOPRIGHT", mR * s, top)
    lb.right:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", mR * s, -bottom)
    lb.right:SetWidth(cR * s)
    -- offenes Ende (ringseitig): keine Endkappe, das Band laeuft gerade bis an die Roehrenkante (Mittelstueck gestreckt)
    local mu0, mu1 = uL, uR
    if lb.opts.mirror then mu0, mu1 = uR, uL end
    if lb.openEnd == "left" then
        lb.left:SetTexCoord(mu0, mu1, 0, 1)
        lb.left:ClearAllPoints()
        lb.left:SetPoint("TOPLEFT", root, "TOPLEFT", 0, top)
        lb.left:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, -bottom)
        lb.left:SetWidth(math.max(1, (cL - mL) * s))
    elseif lb.openEnd == "right" then
        lb.right:SetTexCoord(mu0, mu1, 0, 1)
        lb.right:ClearAllPoints()
        lb.right:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, top)
        lb.right:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, -bottom)
        lb.right:SetWidth(math.max(1, (cR - mR) * s))
    end
    lb.mid:ClearAllPoints()
    lb.mid:SetPoint("TOPLEFT", lb.left, "TOPRIGHT", 0, 0)
    lb.mid:SetPoint("BOTTOMRIGHT", lb.right, "BOTTOMLEFT", 0, 0)
    lb.pad = { x = math.max(mL, mR) * s, top = top, bottom = bottom }
end

--- Glasglanz (3-Slice, Kappe = GLASS.cap x Seitenverhaeltnis x Hoehe) ueber die ganze Oeffnung
local function layoutGlass(lb, h)
    local G, root = Liquid.GLASS, lb.root
    local cap = G.cap * G.aspect * h
    lb.glassL:ClearAllPoints()
    lb.glassL:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    lb.glassL:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
    lb.glassL:SetWidth(cap)
    lb.glassR:ClearAllPoints()
    lb.glassR:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
    lb.glassR:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    lb.glassR:SetWidth(cap)
    lb.glassM:ClearAllPoints()
    lb.glassM:SetPoint("TOPLEFT", lb.glassL, "TOPRIGHT", 0, 0)
    lb.glassM:SetPoint("BOTTOMRIGHT", lb.glassR, "BOTTOMLEFT", 0, 0)
    -- offenes Ende: Glanz ohne Rundung - ein Stueck des Mittelstuecks gleicher Breite (eine einzelne gestreckte Spalte
    -- zeichnet Streifen und eine Kante zum Mittelstueck, sichtbar im Fenster der Rohraufnahme)
    if lb.openEnd == "left" then lb.glassL:SetTexCoord(G.cap, 2 * G.cap, 0, 1) else lb.glassL:SetTexCoord(0, G.cap, 0, 1) end
    if lb.openEnd == "right" then
        lb.glassR:SetTexCoord(1 - 2 * G.cap, 1 - G.cap, 0, 1)
    else
        lb.glassR:SetTexCoord(1 - G.cap, 1, 0, 1)
    end
end

--- Kanten-Lage t (Abdeckung/Randlicht) mittig auf das Fuellungsende legen: [X - half x h, X + half x h], volle Hoehe
local function placeEdge(lb, t)
    local h = lb.h or 10
    local r = Liquid.EDGE.half * h
    t:ClearAllPoints()
    t:SetPoint("TOP", lb.barTex or lb.root, "TOPRIGHT", 0, 0)
    t:SetPoint("BOTTOM", lb.barTex or lb.root, "BOTTOMRIGHT", 0, 0)
    t:SetWidth(2 * r)
end

--- Roehre auf region legen (Blizzards Balken); Groesse lesen (fehlt sie: fallbackW/H). Ohne Kapselrahmen deckungsgleich, mit
--- Kapselrahmen (opts.frame = "health"/"power") ist die Roehre seine Glasoeffnung: volle Breite von region, Hoehe aus der
--- Rahmenhoehe (h + extra), senkrecht um dy versetzt. level = Frame-Ebene der untersten Lage (Spur/Grund); Fluessigkeit +1,
--- Glut +2, Randlicht/Rahmen +3.
function Liquid.Layout(lb, region, level, fallbackW, fallbackH)
    local root = lb.root
    local okW, w = pcall(region.GetWidth, region)
    local okH, h = pcall(region.GetHeight, region)
    w = okW and Compat.Num(w) or nil
    h = okH and Compat.Num(h) or nil
    if not (w and w > 0) then w = fallbackW or 120 end
    if not (h and h >= MIN_HEIGHT) then h = fallbackH or 12 end
    root:ClearAllPoints()
    local F, s, dy = lb.geo, nil, 0
    if F then
        local U = Liquid.UF_FRAME
        local total = h + math.max(U.extraMin, h * U.extraRel)
        s = total / F.srcH
        dy = (lb.opts.dy or F.dy or 0) * total + (lb.endDy or 0)
        -- Enden (Liquid.SetEnds): am Portraet endet die Roehre aussen am Ring statt an Blizzards Balkenende
        local eL, eR = lb.endL or 0, lb.endR or 0
        root:SetPoint("LEFT", region, "LEFT", eL, dy)
        root:SetPoint("RIGHT", region, "RIGHT", eR, dy)
        w = math.max(1, w - eL + eR)
        h = (F.openB - F.openT) * s
        root:SetHeight(h)
    else
        root:SetAllPoints(region)
    end
    lb.region, lb.regionDy, lb.nudged = region, dy, false
    lb.w, lb.h = w, h
    lb.trail:ClearAllPoints()
    lb.trail:SetAllPoints(root)
    lb.bar:ClearAllPoints()
    lb.bar:SetAllPoints(root)
    local T = Liquid.TUBE
    local u = F and 0 or math.floor(h * T.under + 0.5) -- np-frame: unter die Kappen; Kapselrahmen: Maske = Oeffnung
    lb.under = u -- Ueberstand von fillIn/fillMask links und rechts (LiquidFx: Rahmen-Toenung)
    local function under(t)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", root, "TOPLEFT", -u, 0)
        t:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", u, 0)
    end
    under(lb.back)
    lb.fill:ClearAllPoints()
    lb.fill:SetPoint("TOPLEFT", root, "TOPLEFT", -u, 0)
    -- ueber das Fuellungsende hinaus (die Abdeckung bildet die Kante)
    local piston = lb.style == "piston"
    lb.fill:SetPoint("BOTTOMRIGHT", lb.barTex or root, "BOTTOMRIGHT", u + (piston and 0 or Liquid.EDGE.reach * h), 0)
    under(lb.fillIn)
    for _, t in ipairs({ lb.base, lb.flow, lb.flow2, lb.bubbles }) do t:SetAllPoints(lb.fillIn) end
    placeEdge(lb, lb.cover)
    lb.top:ClearAllPoints()
    lb.top:SetAllPoints(root)
    if lb.inset then under(lb.inset) end
    if lb.glassL then
        layoutGlass(lb, h)
    elseif lb.glass then
        lb.glass:ClearAllPoints()
        lb.glass:SetPoint("TOPLEFT", root, "TOPLEFT", math.floor(h * 0.5 + 0.5), -math.floor(h * T.glassTop + 0.5))
        lb.glass:SetPoint("TOPRIGHT", root, "TOPRIGHT", -math.floor(h * 0.5 + 0.5), -math.floor(h * T.glassTop + 0.5))
        lb.glass:SetHeight(math.max(1, math.floor(h * T.glassHeight + 0.5)))
    end
    -- Glut: Spitze auf der Kante der Spur, nach links verloeschend
    local E = Liquid.EMBER
    lb.ember:ClearAllPoints()
    lb.ember:SetPoint("RIGHT", lb.trailTex or lb.trail, "RIGHT", 0, 0)
    lb.ember:SetSize(math.max(2, E.length * h), h * E.height)
    -- Randlicht auf der Oberflaeche
    placeEdge(lb, lb.surface)
    -- Kolben-Kammer
    local P = Liquid.PISTON
    if lb.piston then
        lb.piston:ClearAllPoints()
        lb.piston:SetPoint("CENTER", lb.barTex or root, "RIGHT", 0, 0)
        lb.piston:SetSize(math.max(2, P.piston * h), h)
    end
    layoutPiston(lb)
    -- Masken (Form nach Seitenverhaeltnis)
    local mp = maskPath(lb)
    for _, k in ipairs(MASK_KEYS) do -- einzeln geprueft: fehlt eine Maske (Plaketten-Variante, kein Masken-API), weiter
        local m = lb[k]
        if m and lb.maskPath ~= mp then pcall(m.SetTexture, m, mp, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
    end
    lb.maskPath = mp
    if lb.backMask then under(lb.backMask) end
    if lb.trailMask then under(lb.trailMask) end
    if lb.glowMask then under(lb.glowMask) end
    lb.glow:ClearAllPoints()
    lb.glow:SetPoint("TOPLEFT", lb.barTex or root, "TOPRIGHT", piston and Liquid.PISTON.piston * h * 0.5 or 0, 0)
    lb.glow:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    if lb.glowIn then
        lb.glowIn:ClearAllPoints()
        lb.glowIn:SetPoint("TOPLEFT", lb.barTex or root, "TOPRIGHT", 0, 0)
        lb.glowIn:SetPoint("BOTTOMLEFT", lb.barTex or root, "BOTTOMRIGHT", 0, 0)
        lb.glowIn:SetWidth(math.max(1, Liquid.EMBER.fadeIn * h))
    end
    if lb.fillMask then under(lb.fillMask) end
    if lb.topMask then under(lb.topMask) end
    for _, m in ipairs({ lb.coverEnd, lb.rimEnd }) do if m then under(m) end end
    -- Bronze-Rahmen: Kapselrahmen um die Oeffnung, sonst np-frame (Gesamthoehe h + extra, Schlitz mittig auf der Roehre)
    if F then
        layoutUfFrame(lb, s)
    elseif lb.left then
        local G, F = Style.FRAME_GEOMETRY, Liquid.FRAME
        local scale = (h + F.extra) / G.h
        local off = ((G.h - G.top - G.bottom) * scale - h) / 2 -- negativ: Band deckt die Roehrenkante
        local padT = math.max(0, math.floor(G.top * scale + off + 0.5))
        local padB = math.max(0, math.floor(G.bottom * scale + off + 0.5))
        local padX = math.floor(G.left * scale * F.side + 0.5)
        local cap = math.floor(G.cap * scale + 0.5)
        lb.left:ClearAllPoints()
        lb.left:SetPoint("TOPLEFT", root, "TOPLEFT", -padX, padT)
        lb.left:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", -padX, -padB)
        lb.left:SetWidth(cap)
        lb.right:ClearAllPoints()
        lb.right:SetPoint("TOPRIGHT", root, "TOPRIGHT", padX, padT)
        lb.right:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", padX, -padB)
        lb.right:SetWidth(cap)
        lb.mid:ClearAllPoints()
        lb.mid:SetPoint("TOPLEFT", lb.left, "TOPRIGHT", 0, 0)
        lb.mid:SetPoint("BOTTOMRIGHT", lb.right, "BOTTOMLEFT", 0, 0)
        lb.pad = { x = padX, top = padT, bottom = padB }
    else
        lb.pad = { x = 0, top = 0, bottom = 0 }
    end
    if level then Liquid.SetLevel(lb, level) end
    lb.glintDirty = true
    if lb.fx then ns.LiquidFx.Layout(lb) end
    if lb.res then Liquid.LayoutReserve(lb) end
    if lb.ghost then Liquid.LayoutHealGhost(lb) end
    if lb.segs or lb.segGlows then Liquid.LayoutSegments(lb) end
    applySlosh(lb)
end

--- Enden der Roehre (nur Kapselrahmen): Versatz der linken/rechten Kante gegenueber Blizzards Balken in UI-Einheiten
--- (negativ = nach links), dy = zusaetzlicher senkrechter Versatz (nach oben; Roehre auf das Fenster der Rohraufnahme).
--- Wirkt ab dem naechsten Liquid.Layout (Skin legt danach neu).
function Liquid.SetEnds(lb, dl, dr, dy)
    lb.endL, lb.endR, lb.endDy = Compat.Num(dl) or 0, Compat.Num(dr) or 0, Compat.Num(dy) or 0
end

--- Offenes Ende (nur Kapselrahmen): "left"/"right" = auf dieser Seite keine Kapsel-Rundung und keine Endkappe (die Roehre
--- laeuft gerade unter den Portraetring), nil = beidseitig rund. Wirkt ab dem naechsten Liquid.Layout.
function Liquid.SetOpenEnd(lb, side)
    lb.openEnd = (side == "left" or side == "right") and side or nil
end

function Liquid.SetLevel(lb, level)
    level = math.max(0, math.floor(level))
    lb.root:SetFrameLevel(level)
    lb.trail:SetFrameLevel(level)
    lb.bar:SetFrameLevel(level)
    lb.fill:SetFrameLevel(level + 1)
    lb.fillIn:SetFrameLevel(level + 1)
    lb.glow:SetFrameLevel(level + 2)
    lb.top:SetFrameLevel(level + 3)
    if lb.res then lb.res.clip:SetFrameLevel(level) end
    if lb.ghost then lb.ghost.clip:SetFrameLevel(level) end
    for _, g in pairs(lb.segs or {}) do g.clip:SetFrameLevel(level + 2) end
    for _, g in pairs(lb.segGlows or {}) do g.frame:SetFrameLevel(level + 2) end
    if lb.fx then ns.LiquidFx.SetLevel(lb, level) end
end

--- Roehre kurz versetzen (Treffer-Zittern aus LiquidFx; dx/dy in px, 0/0 = Ruhelage). Nur eigene Anker an Blizzards Balken.
function Liquid.Nudge(lb, dx, dy)
    local region, root = lb.region, lb.root
    if not region then return end
    if dx == 0 and dy == 0 and not lb.nudged then return end
    lb.nudged = dx ~= 0 or dy ~= 0
    root:ClearAllPoints()
    if lb.geo then
        root:SetPoint("LEFT", region, "LEFT", dx + (lb.endL or 0), lb.regionDy + dy)
        root:SetPoint("RIGHT", region, "RIGHT", dx + (lb.endR or 0), lb.regionDy + dy)
    else
        root:SetPoint("TOPLEFT", region, "TOPLEFT", dx, dy)
        root:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", dx, dy)
    end
end

--- Effekte einer Roehre (LiquidFx): role ("player-health", "player-power", "target-health", ... oder nil), Effekte an/aus,
--- Schlieren an/aus (nur Spieler-Leben)
function Liquid.SetFx(lb, role, on, debuffs)
    if lb.fx then ns.LiquidFx.Configure(lb, role, on, debuffs) end
end

--- Farbe: tint = { tex = "color"|"mono", color = {r,g,b}, base = {r,g,b} (optional) }
function Liquid.SetTint(lb, tint)
    lb.tintArg = tint
    local mono = lb.geo and Liquid.FILL_TEX or Style.FLOW_TEX_MONO -- Kapselrahmen: Gemini-Fluessigkeit (uf-fill)
    local path = tint.tex == "color" and Style.FLOW_TEX or mono
    if lb.style == "piston" then path = Liquid.BODY_TEX end -- Kolben-Kammer: Rauchschwaden, immer getoent
    if lb.flowTex ~= path then
        lb.flowTex = path
        lb.flow:SetTexture(path, "REPEAT", "REPEAT")
        lb.flow2:SetTexture(path, "REPEAT", "REPEAT")
    end
    local c = tint.color
    lb.tint = c
    lb.flow2:SetVertexColor(c[1], c[2], c[3])
    local b = tint.base or { c[1] * 0.55, c[2] * 0.55, c[3] * 0.55 }
    lb.base:SetVertexColor(b[1], b[2], b[3])
    lb.flow:SetVertexColor(c[1], c[2], c[3])
    local k = Liquid.SURFACE.rimMix
    lb.surface:SetVertexColor(c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k)
    if lb.glowS then
        -- Kolben-Kammer: sichtbare Fluessigkeitsfarbe (farbige Textur: aus der Grundfarbe, sonst die Toenung)
        local P = lb.PP
        local r, g, bl = c[1], c[2], c[3]
        if tint.tex == "color" then r, g, bl = b[1] * P.colorFromBase, b[2] * P.colorFromBase, b[3] * P.colorFromBase end
        local gk = P.glowWhite
        lb.glowR, lb.glowG, lb.glowB = r + (1 - r) * gk, g + (1 - g) * gk, bl + (1 - bl) * gk
        local sat = P.bodySat -- Koerper satter (Gelbstich weg), gleicher Farbton
        lb.liqR, lb.liqG, lb.liqB = r ^ sat, g ^ sat, bl ^ sat -- Toenung des Koerpers (uf-body)
        if not lb.gradOK then
            for i = 1, P.sliceMax do lb.glowS[i]:SetVertexColor(lb.glowR, lb.glowG, lb.glowB, P.glowAlpha) end
        end
        for i = 1, P.sliceMax do lb.wetS[i]:SetVertexColor(lb.glowR, lb.glowG, lb.glowB) end
        for _, d in ipairs(lb.drops) do d.tex:SetVertexColor(lb.glowR, lb.glowG, lb.glowB) end
        lb.pDirty = true
    end
    if lb.ghost then Liquid.TintHealGhost(lb) end
end

-- Oberflaeche nach lb.tilt/lb.wave verformen (eigene Zahlen): Neigung = Oberkante gegen Unterkante versetzt, Welle =
-- zusaetzlich Neigung und Verschiebung der ganzen Oberflaeche (die Fluessigkeit tuermt sich an der Kante). Abdeckung und
-- Randlicht bekommen dieselben Versaetze (eine Linie); die Summe ist auf EDGE.maxShift begrenzt.
local function shiftEdge(t, sx, dx)
    if t and t.SetVertexOffset then
        pcall(t.SetVertexOffset, t, 1, sx + dx, 0)
        pcall(t.SetVertexOffset, t, 3, sx + dx, 0)
        pcall(t.SetVertexOffset, t, 2, sx - dx, 0)
        pcall(t.SetVertexOffset, t, 4, sx - dx, 0)
    end
end

--- Kolben-Kammer anlegen: sliceN Scheiben gleicher Breite ueber die ganze Roehre (der Kammer-Clip schneidet am Kolben ab),
--- je (1 + 2 x margin) Hoehen hoch, Oberkante margin x Hoehe ueber dem Glas. Die Oberflaeche
--- endet ohne eigene Wand-Kehle direkt am Kolben bzw. Rohrbeginn (Kehlen entfernt: liefen nicht buendig mit Welle/Toenung).
function layoutPiston(lb)
    local P, h, w, root = lb.PP, lb.h or 10, lb.w or 100, lb.root
    local nsl = math.max(P.sliceMin, math.min(P.sliceMax, math.floor(w / P.slicePx + 0.5)))
    lb.sliceN = nsl
    local top, full, sw = P.margin * h, (1 + 2 * P.margin) * h, w / nsl
    local on = lb.style == "piston"
    local gt, wt = P.glowTile * h, P.wetTile * h -- Licht und Naesse laufen ueber die Scheiben nahtlos weiter
    -- anderer Luftspalt als PISTON (Plaketten): v-Ausschnitt der Lagen so, dass die Textur-Oberflaeche auf -gap x h liegt
    local B = Liquid.PISTON
    local v1 = (P.gap ~= B.gap or P.margin ~= B.margin)
        and ((B.margin + B.gap) / (1 + 2 * B.margin)) / ((P.margin + P.gap) / (1 + 2 * P.margin)) or 1
    for i = 1, P.sliceMax do
        if v1 ~= 1 then lb.airS[i]:SetTexCoord(0, 1, 0, v1) end
        for _, t in ipairs({ lb.airS[i], lb.wetS[i], lb.glowS[i] }) do
            if i <= nsl then
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", root, "TOPLEFT", (i - 1) * sw, top)
                t:SetSize(sw, full)
            end
            t:SetShown(on and i <= nsl)
        end
        lb.glowS[i]:SetTexCoord((i - 1) * sw / gt, i * sw / gt, 0, v1)
        lb.wetS[i]:SetTexCoord((i - 1) * sw / wt, i * sw / wt, 0, v1)
    end
    lb.caustic:ClearAllPoints()
    lb.caustic:SetAllPoints(lb.fillIn)
    lb.pDirty = true
end

--- senkrechte Versaetze ohne pcall (Methode einmal geprueft): linke Ecken dl, rechte dr
local function shiftV(lb, t, dl, dr)
    if not lb.vtx then return end
    t:SetVertexOffset(1, 0, dl)
    t:SetVertexOffset(2, 0, dl)
    t:SetVertexOffset(3, 0, dr)
    t:SetVertexOffset(4, 0, dr)
end

--- Hoehe der Oberflaeche an x (px ab Rohrbeginn) relativ zur Glas-Oberkante (WoW: oben positiv)
local function surfaceY(lb, x, len, h)
    local P = lb.PP
    local xn = x / len
    if xn > 1 then xn = 1 elseif xn < 0 then xn = 0 end
    local raw = ns.LiquidWave.Sample(lb.field, xn) * h
    local up = P.upGap * P.gap * h
    return -P.gap * h + (raw > up and up or raw) -- nie ueber die Grenze der Darstellung
end

--- Spritzer: count Tropfen an zufaelligen Stellen der Oberflaeche nach oben schleudern (Kammerlaenge len, Hoehe h)
local function splash(lb, count, len, h, cx)
    local P = lb.PP
    local span = math.min(len, lb.w or len)
    for _, d in ipairs(lb.drops) do
        if count <= 0 then break end
        if not d.on then
            count = count - 1
            d.on, d.stick, d.a = true, false, P.dropAlpha
            if cx then -- am Kamm (Ueberschwappen), leicht gestreut
                d.x = math.max(0.04 * span, math.min(0.96 * span, cx + (math.random() - 0.5) * 1.2 * h))
            else
                d.x = (0.08 + 0.84 * math.random()) * span
            end
            d.y = math.min(surfaceY(lb, d.x, len, h), -P.dropTop * h - 0.05 * h)
            d.vx = (math.random() - 0.5) * 1.5 * h
            d.vy = (P.dropUp1 + (P.dropUp2 - P.dropUp1) * math.random()) * h
            local cell, ds = math.random(P.dropCells), P.dropSize * h * (P.dropScale + (1 - P.dropScale) * math.random())
            d.tex:SetTexCoord((cell - 1) / P.dropCells, cell / P.dropCells, 0, 1)
            d.tex:SetSize(ds, ds)
            d.cell, d.size = cell, ds
            d.tex:SetAlpha(d.a)
            d.tex:Show()
            lb.dropsOn = lb.dropsOn + 1
        end
    end
end

local breakWave -- unten (Ueberschwappen)

--- Stoss in die Fluessigkeit: Welle, ggf. Spritzer, bei Treffer/Wegstossen ein Ruck der ganzen Fluessigkeit
local function jolt(lb, kind, strength, len, h, kickV)
    local P = lb.PP
    strength = math.max(0, math.min(1, strength))
    if strength <= 0 then return end
    lb.joltSign = -(lb.joltSign or 1)
    ns.LiquidWave.Kick(lb.field, kind, kickV or strength * P.joltGain, lb.joltSign)
    if kind == "hit" or kind == "knock" then lb.ruckV = lb.ruckV + strength * P.ruckKick * h * lb.joltSign end
    if strength >= P.dropMin then splash(lb, math.floor(2 + 4 * strength), len, h) end
end

--- Welle bricht am Kamm (x px ab Rohrbeginn): Tropfen ans Glas, Schaumstreifen oben, Gischt-Krone (Abklingzeit)
function breakWave(lb, x, len, h, t)
    local B = Liquid.BREAK
    if lb.brkT and t - lb.brkT < B.cooldown then return end
    lb.brkT, lb.brkX = t, x
    lb.breaks = (lb.breaks or 0) + 1
    local extra = math.min(B.dropsMax - B.drops, math.floor(((lb.crest or 0) - B.crest) * 4))
    splash(lb, B.drops + math.max(0, extra), len, h, x)
    local P = Liquid.PISTON
    lb.brkFoam:ClearAllPoints()
    lb.brkFoam:SetPoint("TOP", lb.root, "TOPLEFT", x, 0)
    lb.brkFoam:SetSize(B.foamW * h, B.foamH * h)
    lb.brkCrown:ClearAllPoints()
    lb.brkCrown:SetPoint("BOTTOM", lb.root, "TOPLEFT", x, -P.gap * h - 0.35 * h)
    local r, g, b = lb.glowR or 1, lb.glowG or 1, lb.glowB or 1
    lb.brkCrown:SetVertexColor(0.5 + 0.5 * r, 0.5 + 0.5 * g, 0.5 + 0.5 * b)
end
Liquid.BreakWave = function(lb, x)
    if lb.style ~= "piston" then return end
    local h = lb.h or 10
    breakWave(lb, x or (lb.w or 100) * 0.5, lb.lenPx or lb.w or 100, h, now())
end
--- Stoss nur in DIESE Roehre (kind "land"|"jump"|"hit"|..., strength 0..1): Welle und Spritzer, ohne die globale Physik
Liquid.Jolt = function(lb, kind, strength)
    if lb.style ~= "piston" then return end
    jolt(lb, kind, Compat.Num(strength) or 0, lb.lenPx or lb.w or 100, lb.h or 10)
    Liquid.Wake()
end

--- Ueberschwappen, ein Bild: Schaumstreifen und Krone blenden aus (nur waehrend lb.brkT)
local function stepBreak(lb, t)
    local B, h = Liquid.BREAK, lb.h or 10
    local age = t - lb.brkT
    local foam, crown = lb.brkFoam, lb.brkCrown
    if age >= math.max(B.foamT, B.crownT) or lb.style ~= "piston" then
        lb.brkT = nil
        foam:Hide()
        crown:Hide()
        return
    end
    local u = age / B.foamT
    if u < 1 then
        foam:SetAlpha(B.foamA * (u < 0.15 and u / 0.15 or (1 - u) / 0.85))
        foam:Show()
    else
        foam:Hide()
    end
    local c = age / B.crownT
    if c < 1 then
        crown:SetSize(B.crownW * h * (0.7 + 0.5 * c), B.crownH * h * (0.5 + 0.7 * c))
        crown:SetAlpha(B.crownA * (1 - c) * (c < 0.2 and c / 0.2 or 1))
        crown:Show()
    else
        crown:Hide()
    end
end

--- Kolben-Kammer, ein Bild: Eingaenge lesen, Feld rechnen, Scheiben/Effekte setzen (nur solange sich etwas bewegt)
local function stepPiston(lb, t)
    local P, S, W = lb.PP, Liquid.SURFACE, ns.LiquidWave
    local f, h, w = lb.field, lb.h or 10, lb.w or 100
    local dt = t - (lb.pT or t)
    lb.pT = t
    if dt > 0.1 then dt = 0.1 elseif dt < 0 then dt = 0 end
    -- Kammerlaenge: lesbare Breite der Fuellung, sonst Annahme (secret: nur an Compat.Num, nie verglichen)
    local len
    if lb.barTex then
        local okW, fw = pcall(lb.barTex.GetWidth, lb.barTex)
        len = okW and Compat.Num(fw) or nil
    end
    -- ohne Schwappen (Plaketten ausserhalb der Auswahl, SetSloshEnabled): glatte Kammer, keine Wellensimulation; nur
    -- Kaustik laeuft weiter (Koerper und Blaeschen in Liquid.Step), die Scheiben werden einmal flach gelegt
    if lb.waveOff then
        lb.caustic:SetTexCoord(t * 0.031, t * 0.031 + w / (P.causticTile * h * 2), t * 0.017, t * 0.017 + 1 / P.causticTile)
        if not lb.pDirty then return end
        lb.caustic:SetAlpha(P.caustic)
    end
    local live = not lb.waveOff
    if len and len >= 1 then
        if live and lb.lenPx and dt > 0 and math.abs(len - lb.lenPx) > 0.25 then
            -- Kolben bewegt sich: faehrt er zum Rohrbeginn (Leben sinkt), drueckt er die Fluessigkeit dort hoch
            local amount = -(len - lb.lenPx) / dt / h * P.push * ((h / P.hRef) ^ P.thinPow > 1 and 1 or (h / P.hRef) ^ P.thinPow)
            if amount > P.pushMax then amount = P.pushMax elseif amount < -P.pushMax then amount = -P.pushMax end
            W.Push(f, amount)
            lb.pDirty = true
        end
        lb.lenPx = len
    else
        len = w * P.fallbackLen
        lb.lenPx = nil
    end
    local calm = (h / P.hRef) ^ P.thinPow -- duenne Roehren ruhiger
    if calm > 1 then calm = 1 end
    calm = calm * (lb.motion or 1)
    -- Laengsbeschleunigung -> Randsteigung (Ruhelage wie eine Wasserwaage); fehlt Physics.ax: aus tilt/wave
    local PH = ns.LiquidPhysics
    local ax = PH and Compat.Num(PH.ax)
    local axG = PH and Compat.Num(PH.axG)
    local s
    if axG then -- Glas-Modell: Neigung = (a/g) x Kammerlaenge in Roehrenhoehen x EIN globaler Faktor
        s = -axG * len / h * P.glass * calm
    elseif ax then
        s = -ax * P.axGain * len / h * calm
    else
        s = (lb.tilt + lb.wave * S.waveTilt) * P.slope * len / h * calm
    end
    if s > P.maxSlope then s = P.maxSlope elseif s < -P.maxSlope then s = -P.maxSlope end
    if not live then s = 0 end
    W.SetSlope(f, s)
    lb.dT = s
    -- Stoesse: Zaehler der Physik, sonst Spruenge der Welle
    local jc = PH and Compat.Num(PH.jolts)
    if not live then
        lb.joltSeen = jc
    elseif jc then
        if lb.joltSeen and jc ~= lb.joltSeen then
            local kind = PH.joltKind
            if type(kind) ~= "string" or not W.KICK[kind] then kind = "land" end
            local dv = Compat.Num(PH.joltDv)
            jolt(lb, kind, (Compat.Num(PH.joltStrength) or 0.5) * calm, len, h, (dv and dv > 0) and dv * P.glass * P.eta * calm or nil)
        end
        lb.joltSeen = jc
    else
        local aw = math.abs(lb.wave or 0)
        if dt > 0 and (aw - (lb.lastAw or 0)) / dt > P.waveJump then jolt(lb, "land", aw * calm, len, h) end
        lb.lastAw = aw
    end
    -- Treffer-Ruck: gedaempfte Feder, verschiebt die ganze Oberflaeche kurz
    local ruckOn = lb.ruck ~= 0 or lb.ruckV ~= 0
    if ruckOn then
        local n = math.ceil(dt / (1 / 120))
        local sd = n > 0 and dt / n or 0
        for _ = 1, n do
            lb.ruckV = lb.ruckV + (-P.ruckK * lb.ruck - P.ruckDamp * lb.ruckV) * sd
            lb.ruck = lb.ruck + lb.ruckV * sd
        end
        if math.abs(lb.ruck) < P.ruckSleep * h and math.abs(lb.ruckV) < P.ruckSleep * h * 10 then lb.ruck, lb.ruckV = 0, 0 end
    end
    local moving = live and W.Step(f, dt)
    -- Bewegungsmass (0..1): Kaustik, Blaeschen, Schaum
    local shake = PH and Compat.Num(PH.shake) or 0
    local e = math.min(1, math.sqrt(f.energy) * P.eGain + shake)
    lb.caustic:SetAlpha(P.caustic + P.causticMove * e)
    local ct = P.causticTile * h
    lb.caustic:SetTexCoord(t * 0.031, t * 0.031 + w / (ct * 2), t * 0.017, t * 0.017 + h / ct)
    lb.bubbles:SetAlpha((P.bubbleAlpha or Liquid.BUBBLES.alpha) * (1 + P.bubbleBoost * e))
    local dropsOn = lb.dropsOn > 0
    if not (moving or ruckOn or lb.pDirty or dropsOn or lb.wetOn) then return end
    lb.pDirty = false
    -- Scheibengrenzen: Hoehe (weich begrenzt), Schaum, Naessefilm
    local nsl = lb.sliceN
    local sw = w / nsl
    local hk, wk, fk = lb.hk, lb.wk, lb.fk
    local upL, dnL = P.upGap * P.gap * h, P.down * h
    local wetAny = false
    local decay = P.wetDecay * h * dt
    -- erst die Rohhoehen, dann EIN Faktor fuer das ganze Profil (Form bleibt, kein Plateau an einer festen Stelle)
    local hi, lo, xHi = 0, 0, 0
    for k = 0, nsl do
        local xn = k * sw / len
        if xn > 1 then xn = 1 end
        local raw = W.Sample(f, xn) * h + lb.ruck
        hk[k] = raw
        if raw > hi then hi, xHi = raw, math.min(k * sw, len) elseif raw < lo then lo = raw end
    end
    local raw1 = W.Sample(f, 1) * h + lb.ruck
    if raw1 > hi then hi, xHi = raw1, math.min(len, w) elseif raw1 < lo then lo = raw1 end
    -- Ueberschwappen: Kamm (ungedaempft) im Verhaeltnis zur Darstellungsgrenze; ueber BREAK.crest bricht die Welle
    lb.crest = upL > 0 and hi / upL or 0
    if lb.crest > Liquid.BREAK.crest and lb.brkFoam then breakWave(lb, xHi, len, h, now()) end
    local scale = 1
    if hi > upL then scale = upL / hi end
    if -lo > dnL and dnL / -lo < scale then scale = dnL / -lo end
    lb.pMoved, lb.pScale, lb.pLen = true, scale, len -- Oberflaeche bewegt: das Glanzlicht folgt (stepReflex)
    lb.pDraws = (lb.pDraws or 0) + 1 -- Zaehler fuer Diagnose/Tests (Oberflaeche neu gezeichnet)
    for k = 0, nsl do
        local xn = k * sw / len
        if xn > 1 then xn = 1 end
        local y = hk[k] * scale
        hk[k] = y
        local foam = math.abs(W.Speed(f, xn)) * P.foam + math.max(0, y / h) * P.foamCrest * e
        fk[k] = foam > 1 and 1 or foam
        local wv = wk[k] - decay
        if wv < y then wv = y end
        wk[k] = wv
        if wv - y > 0.2 then wetAny = true end
    end
    -- Farben: Licht wie Fluessigkeit (lb.glowRGB), Schaum -> weiss und kraeftiger; Naesse nur, wo sie ueber der Oberflaeche liegt
    local gr, gg, gb = lb.glowR or 1, lb.glowG or 1, lb.glowB or 1
    local ga = P.glowAlpha
    for k = 0, nsl do
        local c, fo = lb.glowC[k], fk[k]
        c.r, c.g, c.b = gr + (1 - gr) * fo, gg + (1 - gg) * fo, gb + (1 - gb) * fo
        c.a = ga + (1 - ga) * fo
        local wc = lb.wetC[k]
        local wa = (wk[k] - hk[k]) / (P.wetBand * h)
        wc.r, wc.g, wc.b, wc.a = gr, gg, gb, P.wetAlpha * (wa > 1 and 1 or wa)
    end
    for i = 1, nsl do
        local yl, yr = hk[i - 1], hk[i]
        shiftV(lb, lb.airS[i], yl, yr)
        local g = lb.glowS[i]
        shiftV(lb, g, yl, yr)
        if lb.gradOK then g:SetGradient("HORIZONTAL", lb.glowC[i - 1], lb.glowC[i]) end
        if wetAny or lb.wetOn then
            local wt = lb.wetS[i]
            shiftV(lb, wt, wk[i - 1], wk[i])
            if lb.gradOK then
                wt:SetGradient("HORIZONTAL", lb.wetC[i - 1], lb.wetC[i])
            else
                wt:SetAlpha(wetAny and P.wetAlpha * 0.5 or 0)
            end
        end
    end
    lb.wetOn = wetAny
    -- Spiegelhoehe am Kolben (Heil-Vorschau, Diagnose)
    local y1 = raw1 * scale
    lb.pistonD = y1
    -- Heil-Vorschau setzt die Oberflaeche am Fuellungsende fort (steigt/faellt mit dem Spiegel dort)
    local gh = lb.ghost
    if gh and gh.right and lb.vtx then
        gh.body:SetVertexOffset(1, 0, y1)
        gh.body:SetVertexOffset(3, 0, y1)
        shiftV(lb, gh.line, y1, y1)
        gh.edge:SetVertexOffset(1, 0, y1)
        gh.edge:SetVertexOffset(3, 0, y1)
    end
    -- Tropfen: Flug, Landung am Glas im Luftspalt, Herunterrinnen, Verblassen
    if dropsOn then
        local g, top = P.dropG * h, -P.dropTop * h
        for _, d in ipairs(lb.drops) do
            if d.on then
                local alive = true
                if not d.stick then
                    d.vy = d.vy - g * dt
                    d.x = d.x + d.vx * dt
                    d.y = d.y + d.vy * dt
                    if d.y >= top then
                        d.stick = true
                        d.y = top - math.random() * 0.06 * h
                    elseif d.vy < 0 and d.y < surfaceY(lb, d.x, len, h) then
                        alive = false
                    end
                else
                    d.y = d.y - P.dropSlide * h * dt
                    d.a = d.a - P.dropFade * dt
                    if d.a <= 0 or d.y <= surfaceY(lb, d.x, len, h) then alive = false end
                end
                if alive then
                    d.tex:ClearAllPoints()
                    d.tex:SetPoint("CENTER", lb.root, "TOPLEFT", d.x, d.y)
                    d.tex:SetAlpha(d.a)
                else
                    d.on = false
                    d.tex:Hide()
                    lb.dropsOn = lb.dropsOn - 1
                end
            end
        end
    end
end

--- Darstellung waehlen: "edge" (Fluessigkeitskante) oder "piston" (Kolben-Kammer). Danach Liquid.Layout.
function Liquid.SetStyle(lb, style)
    if not Liquid.STYLES[style] then style = "edge" end
    if lb.lite then style = "piston" end -- Plaketten-Variante: immer Kolben-Kammer
    lb.style = style
    local piston = style == "piston"
    lb.cover:SetShown(not piston)
    lb.surface:SetShown(not piston or lb.lite) -- Plaketten: weicher Meniskus am Fuellungsende statt Kolben
    for _, t in ipairs(lb.pistonTex) do t:SetShown(piston) end
    if lb.airS then
        for i = 1, lb.PP.sliceMax do
            local on = piston and i <= (lb.sliceN or 0)
            lb.airS[i]:SetShown(on)
            lb.wetS[i]:SetShown(on)
            lb.glowS[i]:SetShown(on)
        end
    end
    if lb.piston then lb.piston:SetShown(piston) end
    if not piston then
        for _, d in ipairs(lb.drops) do d.on = false; d.tex:Hide() end
        lb.dropsOn = 0
    end
    setBack(lb, piston)
    if lb.tintArg then Liquid.SetTint(lb, lb.tintArg) end -- Fluessigkeits-Textur haengt von der Darstellung ab
    lb.pDirty = true
end

function applySlosh(lb)
    if lb.style == "piston" then return end -- Kolben-Kammer: stepPiston liest tilt/wave jedes Bild
    local S, h = Liquid.SURFACE, lb.h or 10
    local dx = (lb.tilt + lb.wave * S.waveTilt) * h * S.tiltScale
    local sx = lb.wave * h * S.surge
    local lim = Liquid.EDGE.maxShift * h
    local sum = math.abs(dx) + math.abs(sx)
    if sum > lim then
        dx, sx = dx * lim / sum, sx * lim / sum
    end
    lb.edgeDx, lb.edgeSx = dx, sx
    -- Ecken: 1 oben links, 2 unten links, 3 oben rechts, 4 unten rechts
    shiftEdge(lb.surface, sx, dx) -- ohne Tabelle: laeuft jedes Bild
    shiftEdge(lb.cover, sx, dx)
end

--- Neigung der Oberflaeche direkt setzen (Anteil der Roehrenhoehe; 0 = ruhig), ohne Welle und ohne Roehren-Versatz.
function Liquid.SetTilt(lb, tilt)
    lb.tilt = Compat.Num(tilt) or 0
    lb.wave, lb.sloshU = 0, 0
    applySlosh(lb)
end

--- Ergebnis der Bewegungsphysik (Bildschirm-Raum, je -1..1): Neigung und Welle, mit dem leichten Versatz dieser Roehre.
--- Dieselbe Richtung fuer alle Roehren (das gespiegelte Ziel fuellt ebenfalls von links nach rechts).
function Liquid.SetSlosh(lb, tilt, wave)
    local g = lb.sloshGain or 1
    lb.tilt = (Compat.Num(tilt) or 0) * g
    lb.wave = (Compat.Num(wave) or 0) * g
    lb.sloshU = lb.wave * Liquid.SURFACE.flowShift
    applySlosh(lb)
end

--- Schwappen dieser Roehre an/aus (Plaketten, R6: nur Ziel + naechste schwappen). Aus = Oberflaeche ruhig und glatt; an =
--- sofort der aktuelle Stand der Physik (kein Ruck). Liefert true, wenn sich etwas geaendert hat.
function Liquid.SetSloshEnabled(lb, on)
    on = on ~= false
    if (lb.sloshOn ~= false) == on then return false end
    lb.sloshOn = on
    if lb.field then -- Kolben-Kammer: ohne Schwappen keine Wellensimulation, Oberflaeche einmal glatt legen
        lb.waveOff = not on
        if not on then
            lb.field = ns.LiquidWave.New(lb.PP.nodes)
            lb.ruck, lb.ruckV, lb.lenPx = 0, 0, nil
        end
        lb.pT, lb.pDirty = nil, true
    end
    local P = ns.LiquidPhysics
    if on and P and P.Current then
        Liquid.SetSlosh(lb, P.Current())
    else
        lb.tilt, lb.wave, lb.sloshU = 0, 0, 0
        applySlosh(lb)
    end
    return true
end

-- Secret-Regel: v/hi koennen secret sein. Sie gehen nur als Argument an die Engine (pcall faengt nil oder Fehler ab) und
-- stehen nie in Bedingungen, and/or, Vergleichen, Tabellen-Schluesseln oder tostring/format (tests/unitframes-skin.test.mjs
-- prueft das statisch). m ist eine eigene, lesbare Zahl.
local function setValue(bar, v, m)
    if m ~= nil and not interpBroken then
        if pcall(bar.SetValue, bar, v, m) then return true end
        if pcall(bar.SetValue, bar, v) then
            interpBroken = true -- aelterer Client ohne zweites Argument
            return true
        end
        return false
    end
    return (pcall(bar.SetValue, bar, v))
end

local function setRange(bar, hi)
    if not pcall(bar.SetMinMaxValues, bar, 0, hi) then return false end
    return true
end

local function mode(lb)
    if EXP == nil then readEnum() end
    if lb.smooth and EXP ~= nil then return EXP end
    return IMMEDIATE
end

--- Gleiten an/aus, Spur an/aus
function Liquid.SetOptions(lb, smooth, trail)
    lb.smooth = smooth ~= false
    lb.trailOn = trail ~= false
    lb.trail:SetShown(lb.trailOn)
    lb.glow:SetShown(lb.trailOn)
    if not lb.trailOn then setTrailAlpha(lb, 0) end
end

--- Maximum setzen (secret erlaubt, wird nur durchgereicht)
function Liquid.SetMax(lb, maxValue)
    local ok = setRange(lb.bar, maxValue)
    setRange(lb.trail, maxValue)
    lb.lastMax = maxValue -- nur gemerkt (secret erlaubt), fuer /vials test treffer
    if lb.fx then ns.LiquidFx.OnMax(lb, maxValue) end
    return ok
end

--- Neuer Wert (secret erlaubt): Fluessigkeit gleitet sofort, die Spur folgt TRAIL.delay s spaeter mit demselben Wert.
function Liquid.SetValue(lb, value)
    local ok = setValue(lb.bar, value, mode(lb))
    lb.lastValue = value -- nur gemerkt (secret erlaubt)
    if lb.fx then ns.LiquidFx.OnValue(lb, value, mode(lb)) end
    if lb.trailOn and lb.lite then
        -- Plaketten: sammelnde Spur - hoechstens ein offener Timer je Roehre; er zieht die Spur auf den NEUESTEN Wert nach
        -- (viele Treffer auf viele Gegner erzeugen sonst eine Timer-Flut). lb.trailNext nur gemerkt (secret erlaubt).
        lb.trailNext = value
        lb.trailShown = now()
        lb.trailAt = nil
        setTrailAlpha(lb, Liquid.TRAIL.alpha)
        if lb.trailWait ~= lb.epoch then
            local epoch = lb.epoch
            lb.trailWait = epoch
            C_Timer.After(Liquid.TRAIL.delay, function()
                if lb.trailWait == epoch then lb.trailWait = nil end
                if lb.epoch ~= epoch then return end
                setValue(lb.trail, lb.trailNext, mode(lb))
                lb.trailAt = now()
                Liquid.Wake()
            end)
        end
        Liquid.Wake()
    elseif lb.trailOn then
        local epoch = lb.epoch
        lb.trailShown = now()
        lb.trailAt = nil
        setTrailAlpha(lb, Liquid.TRAIL.alpha)
        C_Timer.After(Liquid.TRAIL.delay, function()
            if lb.epoch ~= epoch then return end -- inzwischen eingerastet (Zielwechsel)
            setValue(lb.trail, value, mode(lb))
            lb.trailAt = now()
            Liquid.Wake()
        end)
        Liquid.Wake()
    end
    return ok
end

--- Sofort einrasten (Zielwechsel, Login): offene Spur-Auftraege verfallen, Spur unsichtbar. Danach SnapMax/SnapValue mit
--- den neuen Werten (getrennt, damit der Aufrufer nie pruefen muss, ob ein secret Wert "da" ist).
function Liquid.Snap(lb)
    lb.epoch = lb.epoch + 1
    lb.trailAt, lb.trailShown = nil, nil
    setTrailAlpha(lb, 0)
    if lb.fx then ns.LiquidFx.OnSnap(lb) end
end

--- Maximum ohne Gleiten auf beide Bars (secret erlaubt)
function Liquid.SnapMax(lb, maxValue)
    setRange(lb.bar, maxValue)
    setRange(lb.trail, maxValue)
    lb.lastMax = maxValue
    if lb.fx then ns.LiquidFx.OnMax(lb, maxValue) end
end

--- Wert ohne Gleiten auf beide Bars (secret erlaubt)
function Liquid.SnapValue(lb, value)
    setValue(lb.bar, value, IMMEDIATE)
    setValue(lb.trail, value, IMMEDIATE)
    lb.lastValue = value
    if lb.fx then ns.LiquidFx.OnSnapValue(lb, value) end
end

--- /vials test treffer: die Schadensspur zeigt kurz den ganzen leeren Teil als verloren (Glut/Abbrand sichtbar), dann
--- zieht sie wie nach einem echten Treffer auf den aktuellen Wert nach. Werte nur durchgereicht.
function Liquid.TestLoss(lb)
    if not (lb.trailOn and lb.lastMax ~= nil and lb.lastValue ~= nil) then return false end
    local epoch, value = lb.epoch, lb.lastValue
    setValue(lb.trail, lb.lastMax, IMMEDIATE)
    lb.trailShown, lb.trailAt = now(), nil
    setTrailAlpha(lb, Liquid.TRAIL.alpha)
    C_Timer.After(Liquid.TRAIL.delay, function()
        if lb.epoch ~= epoch then return end
        setValue(lb.trail, value, mode(lb))
        lb.trailAt = now()
        Liquid.Wake()
    end)
    Liquid.Wake()
    return true
end

-- Gemeinsames Ausblenden mit dem Rahmen (Ausblenden-Modul, Fader) ----------------------------------------------------------
-- Alpha vererbt sich im Client je Textur, es gibt kein Gruppen-Alpha: liegen N deckende Lagen uebereinander, bleibt die Flaeche
-- bei Eltern-Alpha a noch bei 1 - (1 - a)^N deckend, waehrend das einlagige Portraet und der Rahmen schon nur a zeigen: die
-- Fluessigkeit schien erst "kurz danach" zu verschwinden. Im Roehrenbereich liegen DREI deckende Lagen: der dunkle Grund (lb.back,
-- auf der Wurzel), die Fuellungs-Basis (lb.base) und die Stroemung (lb.flow, Alpha ~0,96, als 1 genaehert; alle im Frame lb.fill).
-- Ausgleich: je Lage das Alpha x = 1 - (1 - a)^(1/3), d. h. der Grund (Textur lb.back) und der Fuellungs-Frame bekommen zusaetzlich
-- den Faktor x / a (a = 1 => 1, a -> 0 => 1/3); die drei Lagen zusammen decken dann wieder genau a. Glas-/Rahmenlagen bleiben
-- unberuehrt. Reserve (XP-Roehre, res.clip): dort liegt rechts vom Kolben nur Grund + Reserve-Koerper (zwei Lagen); der Koerper
-- bekommt (1 - (1 - a)^(2/3)) / a, damit mit dem Grund (x) wieder a herauskommt. a ist das wirksame Alpha der Roehre (Eltern-Kette
-- inkl. Blizzard-Rahmen), je Bild und direkt nach jedem SetAlpha/SetAlphaFromBoolean des Rahmens gelesen. Secret/unlesbar
-- (Kurvenmodus) => Faktor 1. Grenze: der leere Teil (nur Grund) blendet damit leicht vor dem Rahmen aus.

--- Faktor (1 - (1 - a)^p) / a fuer das wirksame Alpha a (0..1); p = 1/3 (Grund, Fuellung), 2/3 (Reserve).
--- Alles ausser einer Zahl unter 1 => 1
function Liquid.FadeFactor(a, p)
    if type(a) ~= "number" or a ~= a or a >= 1 then return 1 end
    p = p or 1 / 3
    if a < 1e-6 then return p end
    return (1 - (1 - a) ^ p) / a
end

--- Faktoren der Roehre aus dem wirksamen Alpha ihrer Wurzel nachfuehren (setzt nur bei Aenderung)
function Liquid.SyncFade(lb)
    local f, fr = 1, 1
    local ok, a = pcall(lb.root.GetEffectiveAlpha, lb.root)
    if ok then
        a = Compat.Num(a)
        f, fr = Liquid.FadeFactor(a), Liquid.FadeFactor(a, 2 / 3)
    end
    if lb.fadeF == f then return end
    lb.fadeF, lb.fadeFR = f, fr
    lb.back:SetAlpha(f)
    lb.fill:SetAlpha(f)
    if lb.res then lb.res.clip:SetAlpha(fr) end
    if lb.ghost then lb.ghost.clip:SetAlpha(fr) end
end

--- alle aktiven Roehren nachfuehren (Aufruf direkt nach dem SetAlpha eines Blizzard-Rahmens, siehe Skin)
function Liquid.SyncFadeAll()
    for lb in pairs(tubes) do
        if lb.active then pcall(Liquid.SyncFade, lb) end
    end
end

function Liquid.Show(lb)
    lb.root:Show()
    lb.active = true
    Liquid.SyncFade(lb)
    local P = ns.LiquidPhysics
    if P and P.Current and lb.sloshOn ~= false then Liquid.SetSlosh(lb, P.Current()) end
    Liquid.Wake()
end

function Liquid.Hide(lb)
    lb.active = false
    lb.epoch = lb.epoch + 1
    lb.root:Hide()
    local P = ns.LiquidPhysics
    if P and P.Idle and not Liquid.AnyVisible() then P.Idle() end
end

--- true, wenn mindestens eine aktive Roehre sichtbar ist (fuer die Physik)
function Liquid.AnyVisible()
    for lb in pairs(tubes) do
        if lb.active and Compat.QueryBool(lb.root, "IsVisible") ~= false then return true end
    end
    return false
end

-- Reserve-Lage (XP-Leiste, Ruhebonus; Wunsch 17.11.) -----------------------------------------------------------------
-- Zweite, ruhige Fluessigkeit hinter dem Kolben: ein Clip-Frame vom Rohrbeginn bis zum Ende einer eigenen unsichtbaren
-- StatusBar (res.bar), darin ein Koerper (uf-body, oben derselbe Luftspalt wie die Kammer) und eine schwache Lichtlinie
-- (uf-surfglow). Der Clip liegt auf der Ebene von root, also UNTER der Hauptfluessigkeit (level + 1): sichtbar ist die Lage nur
-- rechts vom Kolben. Kapselmaske wie die Roehre. Werte nur durchgereicht (secret erlaubt). Nur Roehren, die AddReserve aufrufen,
-- haben die Lage - Einheitenrahmen und Plaketten bleiben unberuehrt.
Liquid.RESERVE = { alpha = 1, dim = 1.15, glowAlpha = 0.55, glowWhite = 0.25 }

function Liquid.AddReserve(lb)
    if lb.res then return lb.res end
    local root = lb.root
    local r = {}
    r.bar = CreateFrame("StatusBar", nil, root)
    r.barTex = setBarTexture(r.bar, Style.FILL_TEX)
    if r.barTex then r.barTex:SetAlpha(0) end
    r.clip = CreateFrame("Frame", nil, root)
    pcall(r.clip.SetClipsChildren, r.clip, true)
    r.body = free(r.clip:CreateTexture(nil, "BORDER", nil, 0))
    r.body:SetTexture(Liquid.BODY_TEX, "REPEAT", "REPEAT")
    r.line = free(r.clip:CreateTexture(nil, "BORDER", nil, 1))
    r.line:SetTexture(Liquid.SURFGLOW_TEX, "REPEAT", "CLAMP")
    if r.line.SetBlendMode then r.line:SetBlendMode("ADD") end
    r.mask = newMask(r.clip, Liquid.MASK_TEX)
    addMask(r.body, r.mask)
    addMask(r.line, r.mask)
    r.clip:Hide()
    if lb.fadeFR then r.clip:SetAlpha(lb.fadeFR) end
    lb.res = r
    if lb.root:GetFrameLevel() then r.clip:SetFrameLevel(lb.root:GetFrameLevel()) end
    Liquid.SetReserveTint(lb, lb.tint or WHITE_RES)
    if lb.h then Liquid.LayoutReserve(lb) end
    return r
end

--- Lagen der Reserve auf die Roehre legen (aus Liquid.Layout). Koerper und Linie ueber die ganze Roehre (Texel unverzerrt),
--- der Clip schneidet am Ende der Reserve-Bar ab.
function Liquid.LayoutReserve(lb)
    local r = lb.res
    if not r then return end
    local P, h, w, root = Liquid.PISTON, lb.h or 10, lb.w or 100, lb.root
    r.bar:ClearAllPoints()
    r.bar:SetAllPoints(root)
    r.clip:ClearAllPoints()
    r.clip:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    r.clip:SetPoint("BOTTOMRIGHT", r.barTex or r.bar, "BOTTOMRIGHT", 0, 0)
    r.body:ClearAllPoints()
    r.body:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -P.gap * h)
    r.body:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    r.body:SetTexCoord(0, w / (P.bodyTile * h), 0.2, 0.996)
    r.line:ClearAllPoints()
    r.line:SetPoint("TOPLEFT", root, "TOPLEFT", 0, P.margin * h)
    r.line:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, -P.margin * h)
    r.line:SetTexCoord(0, w / (P.glowTile * h), 0, 1)
    if r.mask then
        if lb.maskPath then pcall(r.mask.SetTexture, r.mask, lb.maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
        r.mask:ClearAllPoints()
        r.mask:SetAllPoints(root)
    end
end

--- Farbe der Reserve (c = {r, g, b}, lesbar): Koerper abgedunkelt (RESERVE.dim), Linie aufgehellt
function Liquid.SetReserveTint(lb, c)
    local r, R = lb.res, Liquid.RESERVE
    if not r then return end
    local k = Liquid.PISTON.bodyBright * R.dim
    r.body:SetVertexColor(c[1] * k, c[2] * k, c[3] * k, R.alpha)
    local wk = R.glowWhite
    r.line:SetVertexColor(c[1] + (1 - c[1]) * wk, c[2] + (1 - c[2]) * wk, c[3] + (1 - c[3]) * wk, R.glowAlpha)
end

-- Heil-Vorschau ("Geist", 18.11.: Blizzards flache gruene Vorschau ans Design anpassen) ---------------------------------------
-- Durchscheinende, hellere Lage aus demselben Fluessigkeitskoerper plus Oberflaechenlicht, im Glas (Kapselmaske, unter dem
-- Luftspalt), sanft pulsierend (AnimationGroup, kein Lua je Bild). Liegt wie die Reserve UNTER der Fuellung (lb.fill deckt den
-- Teil bis zum Kolben); das rechte Ende haengt an Blizzards Vorschau-Maske (Liquid.SetHealGhost) - die Breite rechnet Blizzard
-- aus den (secret) Werten, Lucid liest nichts davon.
-- 18.11.: erste Fassung "zu unscheinbar" => kraeftiger, heller, leuchtende Vorderkante (edgeW x Hoehe, ADD)
Liquid.GHOST = { alpha = 0.85, lighten = 0.55, bright = 2.0, glowAlpha = 1, pulseFrom = 0.6, pulseTo = 1, pulseDur = 0.8,
    edgeW = 1.2, edgeAlpha = 0.9, edgeWhite = 0.5 }

function Liquid.AddHealGhost(lb)
    if lb.ghost then return lb.ghost end
    local root, G = lb.root, Liquid.GHOST
    local g = {}
    g.clip = CreateFrame("Frame", nil, root)
    pcall(g.clip.SetClipsChildren, g.clip, true)
    g.inner = CreateFrame("Frame", nil, g.clip)
    g.inner:SetAllPoints(root)
    g.body = free(g.inner:CreateTexture(nil, "BORDER", nil, 0))
    g.body:SetTexture(Liquid.BODY_TEX, "REPEAT", "REPEAT")
    g.line = free(g.inner:CreateTexture(nil, "BORDER", nil, 1))
    g.line:SetTexture(Liquid.SURFGLOW_TEX, "REPEAT", "CLAMP")
    if g.line.SetBlendMode then g.line:SetBlendMode("ADD") end
    g.edge = free(g.inner:CreateTexture(nil, "BORDER", nil, 2))
    g.edge:SetTexture(Liquid.FADEIN_TEX, "CLAMP", "CLAMP")
    if g.edge.SetBlendMode then g.edge:SetBlendMode("ADD") end
    g.mask = newMask(g.inner, Liquid.MASK_TEX)
    addMask(g.body, g.mask)
    addMask(g.line, g.mask)
    addMask(g.edge, g.mask)
    -- Puls: fehlt eine Animations-API, bleibt die Lage einfach ruhig
    local okA = pcall(function()
        local ag = g.inner:CreateAnimationGroup()
        local an = ag:CreateAnimation("Alpha")
        an:SetFromAlpha(G.pulseFrom)
        an:SetToAlpha(G.pulseTo)
        an:SetDuration(G.pulseDur)
        if an.SetSmoothing then an:SetSmoothing("IN_OUT") end
        ag:SetLooping("BOUNCE")
        g.anim = ag
    end)
    if not okA then g.anim = nil end
    g.clip:Hide()
    if lb.fadeFR then g.clip:SetAlpha(lb.fadeFR) end
    if lb.root:GetFrameLevel() then g.clip:SetFrameLevel(lb.root:GetFrameLevel()) end
    lb.ghost = g
    Liquid.TintHealGhost(lb)
    if lb.h then Liquid.LayoutHealGhost(lb) end
    return g
end

--- Lagen des Geists auf die Roehre legen (aus Liquid.Layout); der Clip bekommt sein rechtes Ende aus SetHealGhost
function Liquid.LayoutHealGhost(lb)
    local g = lb.ghost
    if not g then return end
    local P, h, w, root = Liquid.PISTON, lb.h or 10, lb.w or 100, lb.root
    local top = lb.style == "piston" and P.gap * h or 0
    g.body:ClearAllPoints()
    g.body:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -top)
    g.body:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    g.body:SetTexCoord(0, w / (P.bodyTile * h), 0.2, 0.996)
    g.line:ClearAllPoints()
    g.line:SetPoint("TOPLEFT", root, "TOPLEFT", 0, P.margin * h)
    g.line:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, -P.margin * h)
    g.line:SetTexCoord(0, w / (P.glowTile * h), 0, 1)
    g.edge:ClearAllPoints()
    g.edge:SetPoint("TOPRIGHT", g.clip, "TOPRIGHT", 0, -top)
    g.edge:SetPoint("BOTTOMRIGHT", g.clip, "BOTTOMRIGHT", 0, 0)
    g.edge:SetWidth(Liquid.GHOST.edgeW * h)
    if g.mask then
        if lb.maskPath then pcall(g.mask.SetTexture, g.mask, lb.maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
        g.mask:ClearAllPoints()
        g.mask:SetAllPoints(root)
    end
    if g.right then Liquid.SetHealGhost(lb, g.right) end
end

--- Farbe des Geists aus der Fluessigkeitsfarbe: aufgehellt, durchscheinend
function Liquid.TintHealGhost(lb)
    local g, G = lb.ghost, Liquid.GHOST
    if not g then return end
    local r, gg, b = lb.liqR or 1, lb.liqG or 1, lb.liqB or 1
    local k, P = G.lighten, Liquid.PISTON
    local br = P.bodyBright * G.bright
    g.body:SetVertexColor(math.min(1, (r + (1 - r) * k) * br), math.min(1, (gg + (1 - gg) * k) * br),
        math.min(1, (b + (1 - b) * k) * br), G.alpha)
    local wr, wg, wb = lb.glowR or 1, lb.glowG or 1, lb.glowB or 1
    g.line:SetVertexColor(wr, wg, wb, G.glowAlpha)
    local ew = G.edgeWhite
    g.edge:SetVertexColor(wr + (1 - wr) * ew, wg + (1 - wg) * ew, wb + (1 - wb) * ew, G.edgeAlpha)
end

--- Heil-Vorschau zeigen bis zum rechten Rand von region (Blizzards Vorschau-Maske) bzw. verbergen (region = nil)
function Liquid.SetHealGhost(lb, region)
    local g = lb.ghost
    if not g then return end
    g.right = region
    if not region then
        if g.anim then pcall(function() g.anim:Stop() end) end
        g.clip:Hide()
        return
    end
    g.clip:ClearAllPoints()
    g.clip:SetPoint("TOPLEFT", lb.root, "TOPLEFT", 0, 0)
    g.clip:SetPoint("BOTTOM", lb.root, "BOTTOM", 0, 0)
    if not pcall(g.clip.SetPoint, g.clip, "RIGHT", region, "RIGHT", 0, 0) then
        g.clip:Hide()
        return
    end
    g.clip:Show()
    if g.anim then pcall(function() if not g.anim:IsPlaying() then g.anim:Play() end end) end
end

-- Schild und Heil-Absorption im Design (18.11.) --------------------------------------------------------------------------
-- Statt Blizzards gestreifter Schild-Lage (TotalAbsorbBar) und dunkler Heil-Absorption (HealAbsorbBar): eigene Lagen im Glas,
-- links/rechts an Blizzards Segment-Maske verankert (Breite rechnet Blizzard, Lucid liest sie nie), ueber der Fluessigkeit.
-- Zweite Fassung nach dem Spieltest-Bild ("sieht kaputt aus": ueberstrahlter weisser Block, hartes lila Rechteck, Kreuz-Gluehen):
-- alles in BLEND und zurueckhaltend, weiche Enden (Alpha-Rampen je Seite, Koerper dazwischen), kein addierter Koerper mehr.
--   shield      kuehler Glasschimmer ueber die ganze Glashoehe: zarter Hauch, wanderndes Schild-Muster und Lichtbaender
--               (Saegezahn-Rampe, kachelnd, ADD, sehr schwach), Glanzlinie oben
--   healAbsorb  dunkler Rauchschleier ueber dem Fluessigkeitsende (Koerper unter dem Luftspalt), treibend
-- Glows (OverAbsorbGlow/OverHealAbsorbGlow): weiche Licht-Rampe im Glas am rechten bzw. linken Ende, pulsierend.
Liquid.WHITE_TEX = "Interface\\Buttons\\WHITE8X8"
Liquid.SHIELD_PAT_TEX = "Interface\\RaidFrame\\Shield-Overlay"
Liquid.SEGMENTS = {
    shield = { full = true, color = { 0.78, 0.88, 1.0 }, alpha = 0.18, ramp = 0.7,
        pat = { 0.85, 0.93, 1.0 }, patA = 0.12, patTile = 1.6, patScroll = 0.08,
        sweep = { 0.85, 0.95, 1.0 }, sweepA = 0.16, sweepPeriod = 3, sweepSpeed = 0.35,
        line = { 0.9, 0.96, 1.0 }, lineA = 0.45 },
    healAbsorb = { full = false, color = { 0.08, 0.01, 0.07 }, alpha = 0.5, ramp = 0.6,
        smoke = { 0.32, 0.06, 0.28 }, smokeA = 0.35, drift = 0.05 },
}
Liquid.SEG_GLOWS = {
    over = { side = "RIGHT", color = { 0.8, 0.92, 1.0 }, alpha = 0.75, w = 1.2 },
    overHeal = { side = "LEFT", color = { 0.55, 0.15, 0.5 }, alpha = 0.7, w = 1.2 },
}

local function pulse(frame, from, to, dur)
    local anim
    pcall(function()
        local ag = frame:CreateAnimationGroup()
        local an = ag:CreateAnimation("Alpha")
        an:SetFromAlpha(from)
        an:SetToAlpha(to)
        an:SetDuration(dur)
        if an.SetSmoothing then an:SetSmoothing("IN_OUT") end
        ag:SetLooping("BOUNCE")
        anim = ag
    end)
    return anim
end
local function playAnim(a, on)
    if not a then return end
    pcall(function()
        if on then
            if not a:IsPlaying() then a:Play() end
        else
            a:Stop()
        end
    end)
end

local function segTex(parent, sub, path, blend, c, a, wrap)
    local t = free(parent:CreateTexture(nil, "ARTWORK", nil, sub))
    t:SetTexture(path, wrap or "CLAMP", wrap or "CLAMP")
    if t.SetBlendMode then t:SetBlendMode(blend) end
    t:SetVertexColor(c[1], c[2], c[3], a)
    return t
end

function Liquid.AddSegment(lb, key)
    lb.segs = lb.segs or {}
    if lb.segs[key] then return lb.segs[key] end
    local S, root = Liquid.SEGMENTS[key], lb.root
    if not S then return nil end
    local g = { key = key }
    g.clip = CreateFrame("Frame", nil, root)
    pcall(g.clip.SetClipsChildren, g.clip, true)
    g.inner = CreateFrame("Frame", nil, g.clip)
    g.inner:SetAllPoints(root)
    -- Grundlage mit weichen Enden: Rampe links (0 -> 1), Mitte, Rampe rechts (1 -> 0)
    g.rampL = segTex(g.inner, 0, Liquid.FADEIN_TEX, "BLEND", S.color, S.alpha)
    g.mid = segTex(g.inner, 0, Liquid.WHITE_TEX, "BLEND", S.color, S.alpha)
    g.rampR = segTex(g.inner, 0, Liquid.FADEIN_TEX, "BLEND", S.color, S.alpha)
    g.rampR:SetTexCoord(1, 0, 0, 1)
    if S.smoke then g.smoke = segTex(g.inner, 1, Liquid.BODY_TEX, "BLEND", S.smoke, S.smokeA, "REPEAT") end
    if S.pat then g.pat = segTex(g.inner, 1, Liquid.SHIELD_PAT_TEX, "ADD", S.pat, S.patA, "REPEAT") end
    if S.sweep then g.sweep = segTex(g.inner, 2, Liquid.FADEIN_TEX, "ADD", S.sweep, S.sweepA, "REPEAT") end
    if S.line then
        g.line = segTex(g.inner, 3, Liquid.SURFGLOW_TEX, "ADD", S.line, S.lineA)
        pcall(g.line.SetTexture, g.line, Liquid.SURFGLOW_TEX, "REPEAT", "CLAMP")
    end
    g.mask = newMask(g.inner, Liquid.MASK_TEX)
    for _, t in ipairs({ g.rampL, g.mid, g.rampR, g.smoke, g.pat, g.sweep, g.line }) do addMask(t, g.mask) end
    g.clip:Hide()
    lb.segs[key] = g
    if lb.root:GetFrameLevel() then g.clip:SetFrameLevel(lb.root:GetFrameLevel() + 2) end
    if lb.h then Liquid.LayoutSegments(lb) end
    return g
end

function Liquid.AddSegGlow(lb, key)
    lb.segGlows = lb.segGlows or {}
    if lb.segGlows[key] then return lb.segGlows[key] end
    local G, root = Liquid.SEG_GLOWS[key], lb.root
    if not G then return nil end
    local g = {}
    g.frame = CreateFrame("Frame", nil, root)
    g.frame:SetAllPoints(root)
    g.tex = segTex(g.frame, 4, Liquid.FADEIN_TEX, "ADD", G.color, G.alpha)
    g.mask = newMask(g.frame, Liquid.MASK_TEX)
    addMask(g.tex, g.mask)
    g.anim = pulse(g.frame, 0.5, 1, 0.8)
    g.frame:Hide()
    lb.segGlows[key] = g
    if lb.root:GetFrameLevel() then g.frame:SetFrameLevel(lb.root:GetFrameLevel() + 2) end
    if lb.h then Liquid.LayoutSegments(lb) end
    return g
end

local function vSpan(t, root, top)
    t:SetPoint("TOP", root, "TOP", 0, -top)
    t:SetPoint("BOTTOM", root, "BOTTOM", 0, 0)
end

--- Lagen der Segmente/Glows auf die Roehre legen (aus Liquid.Layout)
function Liquid.LayoutSegments(lb)
    local P, h, w, root = Liquid.PISTON, lb.h or 10, lb.w or 100, lb.root
    local gap = lb.style == "piston" and P.gap * h or 0
    for key, g in pairs(lb.segs or {}) do
        local S = Liquid.SEGMENTS[key]
        local top, rw = S.full and 0 or gap, S.ramp * h
        g.rampL:ClearAllPoints()
        vSpan(g.rampL, root, top)
        g.rampL:SetPoint("LEFT", g.clip, "LEFT", 0, 0)
        g.rampL:SetWidth(rw)
        g.rampR:ClearAllPoints()
        vSpan(g.rampR, root, top)
        g.rampR:SetPoint("RIGHT", g.clip, "RIGHT", 0, 0)
        g.rampR:SetWidth(rw)
        g.mid:ClearAllPoints()
        vSpan(g.mid, root, top)
        g.mid:SetPoint("LEFT", g.rampL, "RIGHT", 0, 0)
        g.mid:SetPoint("RIGHT", g.rampR, "LEFT", 0, 0)
        for _, t in ipairs({ g.smoke, g.pat, g.sweep }) do
            t:ClearAllPoints()
            vSpan(t, root, t == g.smoke and top or 0)
            t:SetPoint("LEFT", root, "LEFT", 0, 0)
            t:SetPoint("RIGHT", root, "RIGHT", 0, 0)
        end
        if g.smoke then g.smoke:SetTexCoord(0, w / (P.bodyTile * h), 0.2, 0.996) end
        if g.pat then
            g.patTW, g.patTH = w / (S.patTile * h), 1 / S.patTile
            g.pat:SetTexCoord(0, g.patTW, 0, g.patTH)
        end
        if g.sweep then
            g.sweepTW = w / (S.sweepPeriod * h)
            g.sweep:SetTexCoord(0, g.sweepTW, 0, 1)
        end
        if g.line then
            g.line:ClearAllPoints()
            g.line:SetPoint("TOPLEFT", root, "TOPLEFT", 0, (P.margin + P.gap) * h)
            g.line:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, -P.margin * h)
            g.line:SetTexCoord(0, w / (P.glowTile * h), 0, 1)
        end
        if g.mask then
            if lb.maskPath then pcall(g.mask.SetTexture, g.mask, lb.maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
            g.mask:ClearAllPoints()
            g.mask:SetAllPoints(root)
        end
        if g.region then Liquid.SetSegment(lb, key, g.region) end
    end
    for key, g in pairs(lb.segGlows or {}) do
        local G = Liquid.SEG_GLOWS[key]
        g.tex:ClearAllPoints()
        g.tex:SetPoint("TOP" .. G.side, root, "TOP" .. G.side, 0, 0)
        g.tex:SetPoint("BOTTOM" .. G.side, root, "BOTTOM" .. G.side, 0, 0)
        g.tex:SetWidth(G.w * h)
        -- Rampe hell zum Ende hin: rechts 0 -> 1, links gespiegelt
        if G.side == "LEFT" then g.tex:SetTexCoord(1, 0, 0, 1) else g.tex:SetTexCoord(0, 1, 0, 1) end
        if g.mask then
            if lb.maskPath then pcall(g.mask.SetTexture, g.mask, lb.maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
            g.mask:ClearAllPoints()
            g.mask:SetAllPoints(root)
        end
    end
end

--- Segment zeigen zwischen linkem und rechtem Rand von region (Blizzards Segment-Maske) bzw. verbergen (nil)
function Liquid.SetSegment(lb, key, region)
    local g = lb.segs and lb.segs[key]
    if not g then return end
    g.region = region
    if not region then
        g.clip:Hide()
        return
    end
    g.clip:ClearAllPoints()
    local ok = pcall(function()
        g.clip:SetPoint("TOP", lb.root, "TOP", 0, 0)
        g.clip:SetPoint("BOTTOM", lb.root, "BOTTOM", 0, 0)
        g.clip:SetPoint("LEFT", region, "LEFT", 0, 0)
        g.clip:SetPoint("RIGHT", region, "RIGHT", 0, 0)
    end)
    g.clip:SetShown(ok)
end

function Liquid.SetSegGlow(lb, key, on)
    local g = lb.segGlows and lb.segGlows[key]
    if not g then return end
    g.frame:SetShown(on and true or false)
    playAnim(g.anim, on)
end

-- je Bild: Schild-Muster und Lichtbaender wandern, Rauch treibt (nur sichtbare Segmente)
local function stepSegments(lb, t)
    for key, g in pairs(lb.segs) do
        if g.region then
            local S = Liquid.SEGMENTS[key]
            if g.pat then
                local u = (t * S.patScroll) % 1
                g.pat:SetTexCoord(u, u + g.patTW, u * 0.5, u * 0.5 + g.patTH)
            end
            if g.sweep then
                local u = -(t * S.sweepSpeed) % 1
                g.sweep:SetTexCoord(u, u + g.sweepTW, 0, 1)
            end
            if g.smoke then
                local tw = (lb.w or 60) / ((lb.h or 10) * Liquid.PISTON.bodyTile)
                local u = lb.phase - t * S.drift
                g.smoke:SetTexCoord(u, u + tw, 0.2, 0.996)
            end
        end
    end
end

--- Reserve zeigen/verbergen
function Liquid.ShowReserve(lb, on)
    if lb.res then lb.res.clip:SetShown(on and true or false) end
end

--- Ende der Reserve setzen (value/maxValue secret erlaubt, nur durchgereicht); snap = ohne Gleiten
function Liquid.SetReserve(lb, value, maxValue, snap)
    local r = lb.res
    if not r then return false end
    setRange(r.bar, maxValue)
    local m = mode(lb) -- liest das Enum beim ersten Mal
    if snap then m = IMMEDIATE end
    return setValue(r.bar, value, m)
end

-- Treiber ---------------------------------------------------------------------------------------------------------------
local fsA, fsB = {}, {}
local WHITE = { 1, 1, 1 }

--- Kolben-Kammer: Koerper (uf-body) in voller Hoehe; Lage A driftet langsam und pendelt, Lage B gespiegelt gegenlaeufig
--- und additiv - die Schwaden verformen sich, statt sichtbar zu scrollen. Nur lesbare Zahlen (Zeit, Groesse, Phase).
local function stepBody(lb, t)
    local P = lb.PP
    local tw = (lb.w or 60) / ((lb.h or 10) * P.bodyTile) -- Kachelbreiten ueber die Roehre (Texel bleiben unverzerrt)
    local p = lb.phase * 6.28
    local ua = lb.phase + t * P.bodyDrift + P.bodySway * math.sin(t * 6.2832 / P.bodySwayT + p)
    lb.flow:SetTexCoord(ua, ua + tw, 0.004, 0.996)
    lb.flow:SetAlpha(P.bodyAlpha)
    local gh = lb.ghost
    if gh and gh.right then gh.body:SetTexCoord(ua, ua + tw, 0.2, 0.996) end -- Heil-Vorschau stroemt mit
    local k = P.bodyBright * (lb.bodyDim or 1) -- bodyDim: Status-Toenung (LiquidFx) dunkelt den Koerper ab
    lb.flow:SetVertexColor((lb.liqR or 1) * k, (lb.liqG or 1) * k, (lb.liqB or 1) * k)
    local ub = lb.phase * 0.37 + 0.5 - t * P.bodyDrift2
    lb.flow2:SetTexCoord(ub + tw, ub, 0.004, 0.996)
    lb.flow2:SetVertexColor(lb.liqR or 1, lb.liqG or 1, lb.liqB or 1)
    lb.flow2:SetAlpha(P.body2Alpha + P.body2Amp * math.sin(t * 6.2832 / P.body2T + p + 1.9))
end
--- Animationsschritt einer Roehre zum Zeitpunkt t (lesbare Zahlen): Fluessigkeit, Blaeschen, Oberflaeche, Spur-Blende.
function Liquid.Step(lb, t)
    Liquid.SyncFade(lb)
    local piston = lb.style == "piston"
    if lb.segs then stepSegments(lb, t) end
    if piston then
        stepBody(lb, t)
    else
        local la, lb2 = Style.FlowState(t, lb.phase, fsA, fsB)
        local c = lb.tint or WHITE
        local su = lb.sloshU or 0 -- Schwappen: die Fluessigkeit wird mitgeschoben (dieselben Setter, keine zusaetzlichen)
        lb.flow:SetTexCoord(la.u0 + su, la.u1 + su, la.v0, la.v1)
        lb.flow:SetAlpha(la.alpha)
        lb.flow:SetVertexColor(c[1] * la.bright, c[2] * la.bright, c[3] * la.bright)
        lb.flow2:SetTexCoord(lb2.u0 + su * 0.6, lb2.u1 + su * 0.6, lb2.v0, lb2.v1)
        lb.flow2:SetAlpha(lb2.alpha)
    end
    local B = Liquid.BUBBLES
    local tile = (lb.w or 60) * B.vSpan / math.max(1, (lb.h or 10) * B.aspect) -- Texel quadratisch
    local v0 = (t * B.speed + lb.phase) % 1
    local S = Liquid.SURFACE
    local u0 = B.sway * math.sin(t * 2 * math.pi / B.swayPeriod + lb.phase * 6.28) + (lb.wave or 0) * S.bubbleShift
    lb.bubbles:SetTexCoord(u0, u0 + tile, v0, v0 + B.vSpan)
    local a = math.min(1, S.alphaBase + S.alphaAmp * math.sin(t * S.rate + lb.phase * 6.28)
        + S.foam * math.abs(lb.wave or 0))
    if piston then
        stepPiston(lb, t)
        if lb.brkT then stepBreak(lb, now()) end
        if lb.lite then lb.surface:SetAlpha(math.min(1, a * lb.PP.rimAlpha / S.alphaBase * 0.5)) end
    else
        lb.surface:SetAlpha(a)
    end
    if lb.refl then stepReflex(lb) end
    if lb.fx and lb.fx.busy then ns.LiquidFx.Step(lb) end
    -- Spur: nach dem Nachziehen hold s halten, dann fade s ausblenden
    local busy = true
    if lb.trailOn and lb.trailAt then
        local T = Liquid.TRAIL
        local age = now() - lb.trailAt - T.hold
        if age >= T.fade then
            setTrailAlpha(lb, 0)
            lb.trailAt = nil
        elseif age > 0 then
            setTrailAlpha(lb, T.alpha * (1 - age / T.fade))
        end
    end
    return busy
end

-- Kosten der Plaketten-Roehren (opts.lite) je Bild in ms (debugprofilestop; fehlt es: keine Messung). n = sichtbare,
-- stepped = in diesem Bild gerechnete, slosh = davon schwappende; avg gleitend (EMA), max seit ResetLiteStats.
local liteStats = { n = 0, stepped = 0, slosh = 0, moved = 0, movedAt = nil, last = 0, avg = 0, max = 0, frames = 0,
    measured = false }
Liquid.LITE_EMA = 0.05

--- Kennzahlen der Plaketten-Roehren (Kopie)
function Liquid.LiteStats()
    local out = {}
    for k, v in pairs(liteStats) do out[k] = v end
    return out
end

function Liquid.ResetLiteStats()
    liteStats.last, liteStats.avg, liteStats.max, liteStats.frames = 0, 0, 0, 0
end

local visibleTubes = {}
local function stepAll(t)
    local busy = false
    local n = 0
    for lb in pairs(tubes) do
        if lb.active and Compat.QueryBool(lb.root, "IsVisible") ~= false then
            -- Plakette von B7 per UnitFrame-Alpha versteckt (IsVisible bleibt true): ruht wie die Plaketten-Fuellung
            if not (lb.hiddenFn and lb.hiddenFn()) then
                n = n + 1
                visibleTubes[n] = lb
            end
        end
    end
    -- Physik einmal je Bild global (nur wenn eine Roehre sichtbar ist); changed = false => im Stand nichts zu setzen
    local changed, tilt, wave = false, 0, 0
    local P = ns.LiquidPhysics
    if n > 0 and P and P.Step then
        local ok, c, ti, wa = pcall(P.Step, t)
        if ok and c then changed, tilt, wave = true, ti, wa end
    elseif P and P.Idle then
        pcall(P.Idle) -- keine Roehre sichtbar: Physik ruht mit frischem Zustand
    end
    local prof = type(debugprofilestop) == "function" and debugprofilestop or nil
    local liteMs, liteN, liteStepped, liteSlosh, liteMoved = 0, 0, 0, 0, 0
    for i = 1, n do
        local lb = visibleTubes[i]
        visibleTubes[i] = nil
        local t0 = (lb.lite and prof) and prof() or nil
        if changed and lb.sloshOn ~= false then pcall(Liquid.SetSlosh, lb, tilt, wave) end
        -- eigener Takt (Plaketten): dazwischen kein Schritt, die Roehre zaehlt aber als laufend (Treiber bleibt wach)
        if lb.stepEvery and lb.lastStep and t - lb.lastStep < lb.stepEvery and t >= lb.lastStep then
            busy = true
        else
            lb.lastStep = t
            local ok = pcall(Liquid.Step, lb, t)
            if ok then busy = true end
            if lb.lite then liteStepped = liteStepped + 1 end
        end
        if lb.lite then
            liteN = liteN + 1
            if lb.sloshOn ~= false then liteSlosh = liteSlosh + 1 end
            if lb.pMoved then -- Oberflaeche in diesem Bild neu gezeichnet (Welle/Kolben bewegt)
                lb.pMoved = false
                liteMoved = liteMoved + 1
                liteStats.movedAt = t
            end
            if t0 then liteMs = liteMs + (prof() - t0) end
        end
    end
    liteStats.n, liteStats.stepped, liteStats.slosh, liteStats.moved = liteN, liteStepped, liteSlosh, liteMoved
    liteStats.now = t
    if liteN > 0 and prof then
        liteStats.measured = true
        liteStats.frames = liteStats.frames + 1
        liteStats.last = liteMs
        local a = liteStats.frames == 1 and 1 or Liquid.LITE_EMA
        liteStats.avg = liteStats.avg + (liteMs - liteStats.avg) * a
        if liteMs > liteStats.max then liteStats.max = liteMs end
    end
    return busy
end
Liquid.StepAll = stepAll

--- Treiber wecken (eigener Treiber in Style.lua; der Stepper meldet sich beim ersten Mal an). Die Fluessigkeit
--- laeuft dort JEDES Bild (AddFastStepper, kein 30-Hz-Takt): Stroemung, Blaeschen, Kante und Spur folgen der echten Zeit,
--- die Physik rechnet mit dem Abstand der Bilder (Physics.Step(t)); ohne sichtbare Roehre ruht der Treiber.
function Liquid.Wake()
    if not (Style and Style.AddStepper and Style.WakeDriver) then return end
    if not stepperOn then
        stepperOn = true
        if Style.AddFastStepper then Style.AddFastStepper(stepAll) else Style.AddStepper(stepAll) end
    end
    Style.WakeDriver()
end

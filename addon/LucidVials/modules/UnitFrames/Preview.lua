-- Mini-Vorschau im Optionsfenster (Ausbau 1.1.0, Anhang 4, E9 Kern): ein nachgebauter Beispielrahmen aus denselben Bausteinen
-- wie die echten Rahmen, fuer die Vorschau-Spalte (UI/ConfigPreview.lua, E10).
--
-- Bauweg "Nachbau mit echten Bausteinen":
--   * Schein-Rahmen sk (sk.preview = true) mit eigenen Ersatz-Regionen an Blizzards Stellen (Portrait-Textur mit dem Bild des
--     Spielers, Balken-Frames in den Massen aus Skin.SPEC); Aufbau und Lage ueber Skin.PreviewBuild/PreviewLayout - dieselben
--     Funktionen wie am echten Rahmen (Ring, Rohraufnahmen, Plakette, Name, Roehren im Kapselrahmen, Zier).
--   * Roehren: Optik aus Skin.GetFrameConfig(buehnenRahmen).liquid, Werte aus den Schiebern (eigene, lesbare Zahlen).
--     Effekte ueber die Rollen "preview-health"/"preview-power"/"preview-xp" (LiquidFx/LiquidFizz): echte Kampf-, Aura- und
--     Ressourcen-Ereignisse treiben die Vorschau nicht, die Tests der Vorschau erreichen die echten Rahmen nicht.
--   * Portrait ueber Portrait.Attach auf dem Schein-Rahmen (Einheit "player", P.fakeFraction/P.fakeDead statt Einheit lesen).
--   * Zahlen ueber dieselbe Kette (Text.Attach/Update mit sk.text.values), Schrift ueber ns.Fonts wie am echten Rahmen.
--   * Zier/Plakette (Ziel) ueber Deco mit sk.previewKind je Instanz statt des modulglobalen Testwerts.
-- Die Buehne lebt nur, solange sie gezeigt wird (Show); Hide/Destroy bauen alles ab (Treiber, Rollen, Portrait-Zustand, Timer).
-- Keine Blizzard-Frames, keine Secrets (nur eigene Zahlen), im Kampf bedienbar (nur eigene, ungeschuetzte Frames).
-- Frames lassen sich im Client nicht freigeben: Destroy legt den Kern in einen Vorrat, Preview.New nimmt ihn wieder.
local _, ns = ...
local Compat = ns.Compat
local Liquid = ns.Liquid
local Skin = ns.UnitFrameSkin

local Preview = {}
ns.Preview = Preview
Skin.Preview = Preview

Preview.SIZE = { w = 260, h = 200 }
Preview.TESTS = { "heal", "hit", "mana", "regen", "slosh", "shield", "poison", "curse", "disease", "magic", "combat", "death",
    "low", "numbers", "all" }
Preview.TESTS_BY_PAGE = { general = { "all" },
    liquid = { "heal", "hit", "mana", "regen", "slosh", "shield", "poison", "curse", "disease", "magic" },
    portrait = { "hit", "heal", "combat", "death", "low" }, text = { "numbers" }, font = { "numbers" } }
Preview.FRAMES = { player = true, target = true }
Preview.KINDS = { normal = true, elite = true, rare = true, rareelite = true, boss = true }
Preview.LEVEL_KINDS = { health = true, power = true, xp = true }
Preview.DEBUFFS = { poison = "Poison", curse = "Curse", disease = "Disease", magic = "Magic" }
-- Beispielrahmen wie Blizzards PlayerFrame/TargetFrame (232 x 100) oben in der Buehne; Ersatz-Regionen (TOPLEFT-Versatz) an
-- Blizzards Stellen; das Ziel ist gespiegelt (Portrait rechts). XP-Roehre unten (nur Spieler-Buehne).
Preview.BOX = { w = 232, h = 100, x = 14, y = -8, level = 10 }
Preview.REGIONS = {
    player = { portrait = { 24, -19 }, health = { 85, -41 }, power = { 85, -62 } },
    target = { portrait = { 150, -19 }, health = { 23, -41 }, power = { 23, -62 } },
}
Preview.XP = { w = 228, h = 9, x = 16, y = -150 }
Preview.BACK = { 0.045, 0.035, 0.03, 0.92 }
-- Hintergruende der Buehne (Stage:SetBackground): dunkel (Standard), hell (weiss), Spielwelt (durchsichtig, false)
Preview.BACKGROUNDS = { dark = Preview.BACK, light = { 1, 1, 1, 1 }, world = false }
Preview.MAX = { player = { health = 16842, power = 6000 }, target = { health = 120000, power = 100 }, xp = 9800, rested = 1500 }
Preview.DEFAULT_LEVEL = { health = 0.72, power = 0.55, xp = 0.43 }
Preview.TARGET_LEVEL = 30
-- "Wie Blizzard" in Blizzards Lage: Versatz der Mitte von Blizzards TextString zur Mitte seiner Leiste (UI); gelesen am echten
-- Rahmen, wenn lesbar, sonst diese Messwerte (Blizzard legt den Statustext mittig auf die Leiste)
Preview.BLIZZ_TEXT_DY = { health = 0, power = 0 }
Preview.BLIZZ_TEXT_MAX = 20
-- Blizzards Statustext-CVars (Text.BlizzardMode); Aenderung => Zahlen der Buehne neu
Preview.STATUS_CVARS = { statustextdisplay = true, statustext = true, statustextpercentage = true }
-- Tests: Dauer (s), niedriges Leben, Zahlenfolge (je Schritt health/power/xp), Schwappen (Schwingung), Ablauf von "all"
Preview.SECS = { debuff = 6, shield = 6, combat = 3, death = 3, low = 3.5 }
Preview.LOW = 0.12
Preview.NUMBERS = { step = 0.7, seq = { { 1, 1, 0.95 }, { 0.61, 0.35, 0.62 }, { 0.33, 0.8, 0.2 }, { 0.08, 0.1, 0.05 },
    { 0.47, 0.6, 0.78 } } }
Preview.SLOSH = { secs = 1.8, hz = 1.2, tau = 0.6, wave = 0.6, tick = 1 / 30, jolt = 0.8 }
Preview.ALL = { { 0.1, "heal" }, { 1.4, "hit" }, { 2.8, "mana" }, { 3.8, "slosh" }, { 5.2, "shield" }, { 6.4, "poison" },
    { 8.0, "low" }, { 12.0, "numbers" } }

-- Hilfen ----------------------------------------------------------------------------------------------------------------
local function recordError(err)
    if Skin.RecordError then Skin.RecordError(err) end
end

local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then recordError(err) end
    return ok
end

local function clamp01(x) return math.max(0, math.min(1, x)) end

local function frameConfig(id)
    local ok, c = pcall(Skin.GetFrameConfig, id)
    if ok and type(c) == "table" then return c end
    return Skin.Defaults()
end

--- lesbare Zahl des Spielers (Stufe) oder nil
local function readNum(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    return ok and Compat.Num(v) or nil
end

--- Portrait-Stil der Vorschau aufrufen (nur, wenn er die Funktion hat)
local function styleCall(sk, name, ...)
    local P = sk and sk.pfx
    local fn = P and P.impl and P.impl[name]
    if type(fn) == "function" then safe(fn, P, ...) end
end

-- Aufbau ------------------------------------------------------------------------------------------------------------------
--- Ersatz-Region an Blizzards Stelle (Balken: Frame in den SPEC-Massen, eigene Ebene ueber der Wurzel)
local function region(root, size, pos, lvl)
    local f = CreateFrame("Frame", nil, root)
    f:SetSize(size[1], size[2])
    f:SetPoint("TOPLEFT", root, "TOPLEFT", pos[1], pos[2])
    f:SetFrameLevel(lvl)
    return f
end

local function buildSk(core, id)
    local spec, R, B = Skin.SPEC[id], Preview.REGIONS[id], Preview.BOX
    local root = CreateFrame("Frame", nil, core.frame)
    root:SetSize(B.w, B.h)
    root:SetPoint("TOPLEFT", core.frame, "TOPLEFT", B.x, B.y)
    local lvl = (core.frame:GetFrameLevel() or 1) + B.level
    root:SetFrameLevel(lvl)
    local ps = spec.portraitSize
    local por = root:CreateTexture(nil, "BACKGROUND") -- Ersatz fuer Blizzards Portrait: Bild des Spielers (Stil "statisch")
    por:SetSize(ps, ps)
    por:SetPoint("TOPLEFT", root, "TOPLEFT", R.portrait[1], R.portrait[2])
    if type(SetPortraitTexture) == "function" then pcall(SetPortraitTexture, por, "player") end
    local sk = { id = id, preview = true, hidden = {}, hiddenCount = 0, missing = {}, found = {}, root = root, portrait = por,
        hb = region(root, spec.health, R.health, lvl + 4), mb = region(root, spec.power, R.power, lvl + 4),
        previewKind = "normal", previewLevel = Preview.TARGET_LEVEL }
    Skin.PreviewBuild(sk, root)
    sk.text = { entries = {}, hidden = { health = {}, power = {} }, values = { health = { 0, 1 }, power = { 0, 1 } } }
    -- Schild-Test: Ersatz fuer Blizzards Segment-Maske, ab dem Fuellungsende ueber einen Teil des leeren Glases
    sk.shieldRegion = CreateFrame("Frame", nil, sk.health.root)
    root:Hide()
    return sk
end

local function buildXP(core)
    local X = Preview.XP
    local host = CreateFrame("Frame", nil, core.frame)
    host:SetAllPoints(core.frame)
    host:SetFrameLevel((core.frame:GetFrameLevel() or 1) + Preview.BOX.level)
    local r = CreateFrame("Frame", nil, host)
    r:SetSize(X.w, X.h)
    r:SetPoint("TOPLEFT", core.frame, "TOPLEFT", X.x, X.y)
    local XPm = ns.UnitFrameXP
    local lb = Liquid.Create(host, { frame = "power", trail = false, mask = Liquid.MASK_XP_TEX, dy = 0, fizz = false,
        motion = XPm and XPm.MOTION or 0.25 })
    Liquid.AddReserve(lb)
    host:Hide()
    core.xp = { host = host, region = r, lb = lb, preview = true, applied = false }
end

local function newCore(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(Preview.SIZE.w, Preview.SIZE.h)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    local c = Preview.BACK
    bg:SetColorTexture(c[1], c[2], c[3], c[4])
    f:Hide()
    local core = { frame = f, bg = bg, sks = {} }
    buildXP(core)
    -- "Wie Blizzard" mit Blizzards Einstellung "nur bei Maus": Zahlen nur, solange die Maus ueber der Buehne ist (eigener Frame)
    local function hover(on)
        core.hover = on
        if core.shown and core.cur and Skin.Text then safe(Skin.Text.SetHover, core.cur, on) end
    end
    f:EnableMouse(true)
    f:HookScript("OnEnter", function() hover(true) end)
    f:HookScript("OnLeave", function() hover(false) end)
    -- Blizzards Statustext-Einstellung geaendert (nur gelesen; angemeldet nur, solange die Buehne gezeigt wird)
    local evf = CreateFrame("Frame")
    evf:SetScript("OnEvent", function(_, _, name)
        if type(name) ~= "string" or Compat.IsSecret(name) or not Preview.STATUS_CVARS[name:lower()] then return end
        local sk = core.shown and core.cur
        if sk and Skin.Text then safe(Skin.Text.Attach, sk, sk.id) end
    end)
    core.evf = evf
    return core
end

--- CVAR_UPDATE nur, solange die Buehne gezeigt wird
local function listenCvars(core, on)
    if on then pcall(core.evf.RegisterEvent, core.evf, "CVAR_UPDATE") else pcall(core.evf.UnregisterEvent, core.evf, "CVAR_UPDATE") end
end

-- Werte ---------------------------------------------------------------------------------------------------------------------
--- wirksamer Stand einer Art: laufender Test (core.over) vor dem Schieber
local function levelOf(core, kind)
    local o = core.over and core.over[kind]
    if o ~= nil then return o end
    return core.levels[kind]
end

local function feedTube(lb, max, cur, glide)
    if glide then
        Liquid.SetMax(lb, max)
        Liquid.SetValue(lb, cur)
    else
        Liquid.Snap(lb)
        Liquid.SnapMax(lb, max)
        Liquid.SnapValue(lb, cur)
    end
end

local function feedXP(core, glide)
    local x = core.xp
    if not x.applied then return end
    local max, rested = Preview.MAX.xp, Preview.MAX.rested
    local cur = math.floor(levelOf(core, "xp") * max + 0.5)
    feedTube(x.lb, max, cur, glide)
    Liquid.SetReserve(x.lb, math.min(cur + rested, max), max, not glide)
    Liquid.ShowReserve(x.lb, true)
    if Skin.Text then safe(Skin.Text.UpdateXP, x, true, cur, true, max, rested) end
end

--- Stand in Roehren, Zahlen und Portrait (glide = gleitend wie ein echter Wert)
local function feedLevels(core, glide)
    local sk = core.cur
    if not sk then return end
    local M = Preview.MAX[sk.id]
    for _, kind in ipairs({ "health", "power" }) do
        local max = M[kind]
        local cur = math.floor(levelOf(core, kind) * max + 0.5)
        feedTube(sk[kind], max, cur, glide)
        local v = sk.text.values[kind]
        v[1], v[2] = cur, max
    end
    if Skin.Text then safe(Skin.Text.Update, sk) end
    local P = sk.pfx
    if P then
        P.fakeFraction = levelOf(core, "health")
        styleCall(sk, "OnHealth")
    end
    feedXP(core, glide)
end

-- Anwenden / Abbauen -----------------------------------------------------------------------------------------------------
local function shownId(core)
    if core.kind ~= "normal" then return "target" end -- Ziel-Art gewaehlt: Ziel-Optik mit Zier
    return core.frameId
end

local function setName(sk)
    local ok, name = pcall(UnitName, "player")
    if not (ok and pcall(sk.name.SetText, sk.name, name)) then sk.name:SetText("") end
    if sk.levelText and sk.id == "player" then
        local lvl = readNum(UnitLevel, "player")
        sk.levelText:SetText(lvl and lvl >= 1 and tostring(lvl) or "")
    end
end

local function applyXP(core, cfg)
    local x = core.xp
    local want = core.cur ~= nil and core.cur.id == "player" and cfg.xp ~= false
    if not want then
        if x.applied then
            x.applied = false
            if Skin.Text then safe(Skin.Text.DetachXP, x) end
            Liquid.SetFx(x.lb, nil, false, false)
            Liquid.Hide(x.lb)
            x.host:Hide()
        end
        return
    end
    local c = frameConfig(nil).liquid -- XP-Roehre: "fuer alle" (wie XP.lua)
    Liquid.SetStyle(x.lb, c.style)
    Liquid.SetEnds(x.lb, 0, 0)
    Liquid.Layout(x.lb, x.region, x.host:GetFrameLevel() + 1, Preview.XP.w, Preview.XP.h)
    local pad = x.lb.pad and x.lb.pad.x or 0
    if pad > 0 then
        Liquid.SetEnds(x.lb, pad, -pad)
        Liquid.Layout(x.lb, x.region, x.host:GetFrameLevel() + 1, Preview.XP.w, Preview.XP.h)
    end
    Liquid.SetOptions(x.lb, c.smooth, false)
    Liquid.SetFx(x.lb, "preview-xp", c.fx, false)
    local XPm = ns.UnitFrameXP
    if XPm then
        Liquid.SetTint(x.lb, XPm.TINTS.rested)
        Liquid.SetReserveTint(x.lb, XPm.COLORS.rested)
    end
    x.host:Show()
    Liquid.Show(x.lb)
    x.applied = true
    if Skin.Text then safe(Skin.Text.AttachXP, x) end
end

local function centerY(obj)
    if type(obj) ~= "table" or type(obj.GetCenter) ~= "function" then return nil end
    local ok, _, y = pcall(obj.GetCenter, obj)
    return ok and Compat.Num(y) or nil
end

--- Versatz von Blizzards Statustext zur Leiste am echten Rahmen (nur gelesen), sonst Messwert
local function blizzTextDy(id, kind)
    local real = Skin.Get(id)
    local bar = real and (kind == "health" and real.hb or real.mb)
    local T = Skin.Text
    local list = (bar and T and T.BlizzTexts) and T.BlizzTexts(real, kind) or {}
    local by, ty = centerY(bar), centerY(list[1])
    if by and ty and math.abs(ty - by) <= Preview.BLIZZ_TEXT_MAX then return ty - by end
    return Preview.BLIZZ_TEXT_DY[kind]
end

--- Einstellungen des Buehnen-Rahmens auf den Schein-Rahmen (wie Skin.apply, ohne Blizzard)
local function applySk(core, sk)
    local cfg = frameConfig(sk.id)
    local lq = cfg.liquid
    sk.applied = true
    sk.root:Show()
    Liquid.SetStyle(sk.health, lq.style) -- vor dem Layout
    Liquid.SetStyle(sk.power, lq.style)
    Skin.PreviewLayout(sk)
    Liquid.SetOptions(sk.health, lq.smooth, lq.trail)
    Liquid.SetOptions(sk.power, lq.smooth, false)
    local player = sk.id == "player"
    -- wie am echten Rahmen: Schlieren und Ressourcen-Effekte nur beim Spieler
    Liquid.SetFx(sk.health, "preview-health", lq.fx, lq.debuffs and player or false)
    Liquid.SetFx(sk.power, "preview-power", lq.fx and player, false)
    if ns.LiquidFizz then ns.LiquidFizz.SetPulse(sk.power, player and lq.regenPulse == true) end
    Liquid.SetTint(sk.health, player and Skin.TINTS.player or Skin.TINTS.hostile)
    Liquid.SetTint(sk.power, Skin.PowerTint({ id = "player" }))
    sk.holder:Show()
    Liquid.Show(sk.health)
    Liquid.Show(sk.power)
    setName(sk)
    sk.text.hover = core.hover == true
    local ok, A = pcall(function()
        return { health = { region = sk.hb, dy = blizzTextDy(sk.id, "health") },
            power = { region = sk.mb, dy = blizzTextDy(sk.id, "power") } }
    end)
    sk.text.blizzAnchor = ok and A or { health = { region = sk.hb, dy = 0 }, power = { region = sk.mb, dy = 0 } }
    if Skin.Text then safe(Skin.Text.Attach, sk, sk.id) end
    if Skin.Portrait then safe(Skin.Portrait.Attach, sk, sk.id) end
    sk.previewKind = core.kind
    if Skin.Deco then safe(Skin.Deco.Refresh, sk) end
    applyXP(core, cfg)
    feedLevels(core, false)
end

local function removeSk(core, sk)
    if not sk then return end
    sk.applied = false
    if Skin.Portrait then safe(Skin.Portrait.Detach, sk) end
    if Skin.Text then safe(Skin.Text.Detach, sk) end
    if Skin.Deco then safe(Skin.Deco.Remove, sk) end
    for _, lb in ipairs({ sk.health, sk.power }) do
        Liquid.SetSegment(lb, "shield", nil)
        Liquid.SetFx(lb, nil, false, false)
        Liquid.Hide(lb)
    end
    if sk.pfx then sk.pfx.fakeFraction, sk.pfx.fakeDead = nil, nil end
    sk.holder:Hide()
    sk.root:Hide()
    if core.cur == sk then core.cur = nil end
end

local function stopTimers(core)
    core.epoch = (core.epoch or 0) + 1
    if core.slosh then
        core.slosh:Cancel()
        core.slosh = nil
    end
    core.over = nil
end

--- gezeigten Rahmen (neu) anwenden; wechselt der Rahmen, wird der alte abgebaut
local function activate(core)
    if not core.shown then return end
    local id = shownId(core)
    if core.cur and core.cur.id ~= id then
        stopTimers(core)
        removeSk(core, core.cur)
    end
    local sk = core.sks[id]
    if not sk then
        sk = buildSk(core, id)
        core.sks[id] = sk
    end
    core.cur = sk
    applySk(core, sk)
end

local function deactivate(core)
    stopTimers(core)
    for _, sk in pairs(core.sks) do if sk.applied then removeSk(core, sk) end end
    core.cur = nil
    applyXP(core, {})
end

-- Tests ---------------------------------------------------------------------------------------------------------------------
local function later(core, secs, fn)
    local epoch = core.epoch
    C_Timer.After(secs, function()
        if core.epoch == epoch and core.shown and core.cur then safe(fn) end
    end)
end

--- voruebergehender Stand (Test), danach zurueck zum Schieber; token: nur der juengste Test stellt zurueck
local function override(core, levels, secs, after)
    core.overToken = (core.overToken or 0) + 1
    local token = core.overToken
    core.over = levels
    feedLevels(core, true)
    later(core, secs, function()
        if core.overToken ~= token then return end
        core.over = nil
        if after then after() end
        feedLevels(core, true)
    end)
end

local function testSlosh(core)
    local cfg = frameConfig(nil).liquid -- Schwappen ist global (Bewegungsphysik)
    if not cfg.slosh then return false end
    local S, sk = Preview.SLOSH, core.cur
    local amp = cfg.sloshStrength or 0.6
    local tubes = { sk.health, sk.power }
    if core.xp.applied then tubes[#tubes + 1] = core.xp.lb end
    for _, lb in ipairs(tubes) do Liquid.Jolt(lb, "land", S.jolt * amp) end
    if core.slosh then core.slosh:Cancel() end
    local t0 = GetTime()
    core.slosh = C_Timer.NewTicker(S.tick, function()
        local t = GetTime() - t0
        local done = t >= S.secs or not core.shown
        local k = done and 0 or amp * math.exp(-t / S.tau)
        local w = 2 * math.pi * S.hz * t
        for _, lb in ipairs(tubes) do Liquid.SetSlosh(lb, k * math.sin(w), k * S.wave * math.sin(w + 1)) end
        if done and core.slosh then
            core.slosh:Cancel()
            core.slosh = nil
        end
    end)
    Liquid.Wake()
    return true
end

local function testShield(core)
    local sk = core.cur
    local lb = sk.health
    Liquid.AddSegment(lb, "shield")
    local r = sk.shieldRegion
    r:ClearAllPoints()
    r:SetPoint("LEFT", lb.barTex or lb.root, "RIGHT", 0, 0)
    r:SetSize(math.max(4, (lb.w or 100) * 0.3), 1)
    Liquid.SetSegment(lb, "shield", r)
    later(core, Preview.SECS.shield, function() Liquid.SetSegment(lb, "shield", nil) end)
    return true
end

local function testDebuff(core, kind)
    local lb = core.cur.health
    local Fx = ns.LiquidFx
    if not (Fx and Fx.SetTubeDebuffs(lb, { kind })) then return false end
    later(core, Preview.SECS.debuff, function() Fx.SetTubeDebuffs(lb, {}) end)
    return true
end

local function testNumbers(core)
    local N = Preview.NUMBERS
    core.overToken = (core.overToken or 0) + 1
    local token = core.overToken
    for i, v in ipairs(N.seq) do
        later(core, (i - 1) * N.step, function()
            if core.overToken ~= token then return end
            core.over = { health = v[1], power = v[2], xp = v[3] }
            feedLevels(core, true)
        end)
    end
    later(core, #N.seq * N.step, function()
        if core.overToken ~= token then return end
        core.over = nil
        feedLevels(core, true)
    end)
    return true
end

local TEST = {}
function TEST.heal(core)
    local Fx, sk = ns.LiquidFx, core.cur
    local any = Fx and Fx.TestTube(sk.health, "heal", true) or false
    styleCall(sk, "React", "heal", false)
    return any or sk.pfx ~= nil
end
function TEST.hit(core)
    local Fx, sk = ns.LiquidFx, core.cur
    local any = Fx and Fx.TestTube(sk.health, "hit", true) or false
    Liquid.Jolt(sk.health, "hit", 0.6)
    styleCall(sk, "React", "hit", false)
    return any or sk.pfx ~= nil
end
function TEST.mana(core)
    local Fizz = ns.LiquidFizz
    return Fizz ~= nil and Fizz.TestTube(core.cur.power) or false
end
--- Regenerations-Impuls (Option liquid.regenPulse; aus => nichts)
function TEST.regen(core)
    local Fizz = ns.LiquidFizz
    return Fizz ~= nil and Fizz.TestPulse(core.cur.power) or false
end
TEST.slosh = testSlosh
TEST.shield = testShield
function TEST.combat(core)
    local sk = core.cur
    styleCall(sk, "React", "combat", true)
    later(core, Preview.SECS.combat, function() styleCall(sk, "React", "combat", false) end)
    return true
end
function TEST.death(core)
    local sk = core.cur
    if sk.pfx then sk.pfx.fakeDead = true end
    styleCall(sk, "React", "dead", true)
    override(core, { health = 0 }, Preview.SECS.death, function()
        if sk.pfx then sk.pfx.fakeDead = nil end
        styleCall(sk, "React", "dead", false)
    end)
    return true
end
function TEST.low(core)
    override(core, { health = Preview.LOW }, Preview.SECS.low)
    return true
end
TEST.numbers = testNumbers
function TEST.all(core)
    for _, step in ipairs(Preview.ALL) do
        later(core, step[1], function() TEST[step[2]](core) end)
    end
    return true
end
for word, kind in pairs(Preview.DEBUFFS) do TEST[word] = function(core) return testDebuff(core, kind) end end

-- Buehnen-Objekt (Vertrag E9 <-> E10) --------------------------------------------------------------------------------------
local Stage = {}
Stage.__index = Stage
local pool = {}

--- Hintergrund der Buehne setzen (core.background: "dark" | "light" | "world")
local function setBackground(core, mode)
    local c = Preview.BACKGROUNDS[mode]
    if c == nil then mode, c = "dark", Preview.BACKGROUNDS.dark end
    core.background = mode
    if c then
        core.bg:SetColorTexture(c[1], c[2], c[3], c[4])
        core.bg:Show()
    else
        core.bg:Hide()
    end
end

--- Buehne anlegen (260 x 200, verborgen; der Aufrufer verankert st.frame und ruft Show, solange sie zu sehen ist)
function Preview.New(parent)
    local core = table.remove(pool)
    if core then
        core.frame:SetParent(parent)
        core.frame:ClearAllPoints()
    else
        core = newCore(parent)
    end
    core.frameId, core.kind, core.shown, core.over = "player", "normal", false, nil
    setBackground(core, "dark")
    core.levels = {}
    for k, v in pairs(Preview.DEFAULT_LEVEL) do core.levels[k] = v end
    return setmetatable({ core = core, frame = core.frame }, Stage)
end

--- Hintergrund der Buehne: "dark" (Standard) | "light" (weiss) | "world" (durchsichtig, der Aufrufer schneidet den Fensterhintergrund aus)
function Stage:SetBackground(mode)
    if self.core then setBackground(self.core, mode) end
end

--- Rahmen der Buehne: "player" | "target" (Optik aus GetFrameConfig(id)); Unbekanntes => "player"
function Stage:SetFrame(id)
    local core = self.core
    if not core then return end
    id = Preview.FRAMES[id] and id or "player"
    if core.frameId == id then return end
    core.frameId = id
    activate(core)
end

--- Pegel kind = "health" | "power" | "xp", frac 0..1 (wirkt nur auf die Buehne)
function Stage:SetLevel(kind, frac)
    local core = self.core
    if not (core and Preview.LEVEL_KINDS[kind] and type(frac) == "number" and frac == frac) then return end
    core.levels[kind] = clamp01(frac)
    if core.shown then feedLevels(core, true) end
end

--- Ziel-Art "normal" | "elite" | "rare" | "rareelite" | "boss"; ungleich normal zeigt die Buehne die Ziel-Optik mit Zier
function Stage:SetKind(art)
    local core = self.core
    if not (core and Preview.KINDS[art]) or core.kind == art then return end
    core.kind = art
    if not core.shown then return end
    if core.cur and core.cur.id == shownId(core) then
        core.cur.previewKind = art
        if Skin.Deco then safe(Skin.Deco.Refresh, core.cur) end
    else
        activate(core)
    end
end

--- Test-Wort aus Preview.TESTS in der Buehne abspielen. Liefert true, wenn etwas laeuft (aus: Effekt im Profil abgeschaltet).
function Stage:Test(word)
    local core = self.core
    local fn = TEST[word]
    if not (core and core.shown and core.cur and fn) then return false end
    local ok, res = pcall(fn, core)
    if not ok then
        recordError(res)
        return false
    end
    return res == true
end

--- nach einer Einstellungs-Aenderung (Skin.OnConfigChanged / Config.Refresh) neu anwenden
function Stage:Refresh()
    local core = self.core
    if core and core.shown then activate(core) end
end

--- zeigen: Treiber, Rollen und Portrait an
function Stage:Show()
    local core = self.core
    if not core or core.shown then return end
    core.shown = true
    core.frame:Show()
    listenCvars(core, true)
    activate(core)
end

--- verbergen: alles abgebaut (Treiber ruhen, Rollen aus, Timer verfallen)
function Stage:Hide()
    local core = self.core
    if not core or not core.shown then return end
    deactivate(core)
    listenCvars(core, false)
    core.shown, core.hover = false, false
    core.frame:Hide()
end

--- endgueltig abbauen; danach ist das Objekt leer (Aufrufe tun nichts), der Kern kommt in den Vorrat
function Stage:Destroy()
    local core = self.core
    if not core then return end
    self:Hide()
    core.frame:ClearAllPoints()
    self.core, self.frame = nil, nil
    pool[#pool + 1] = core
end

--- Rahmen, den die Buehne gerade zeigt ("player" | "target"), bzw. nil, wenn sie verborgen ist
function Stage:ShownFrame()
    local core = self.core
    return core and core.shown and core.cur and core.cur.id or nil
end

--- Zustand (Tests/Debug, nur lesen)
function Stage:State() return self.core end
function Preview.PoolSize() return #pool end

-- Reiter "Profile" (Delta Ausbau 1.1.0, E2): aktives Profil dieses Charakters waehlen, neu anlegen, kopieren, umbenennen,
-- zuruecksetzen, loeschen (ausser "Default"). Die Arbeit machen die Store-Funktionen (CreateProfile, RenameProfile, DeleteProfile,
-- SetCharProfile, ListProfiles, ResetProfile); dieser Reiter prueft nur die Eingabe (Store.ValidName) und meldet das Ergebnis.
-- Profilnamen sind Fremdeingabe: sie gehen nur ueber W.Plain in Texte. Zuruecksetzen und Loeschen brauchen einen zweiten Klick.
-- Fasst keine Blizzard-Frames an; im Kampf bedienbar.
local _, ns = ...
local Store = ns.Store
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local CONFIRM_SECONDS = 4

local function setStatus(page, text, c)
    page.status:SetText(text or "")
    W.Color(page.status, c or C.ok)
end

--- Namen aller Profile (Store.ListProfiles liefert Namen oder Eintraege mit .name)
local function profileNames()
    local names = {}
    for _, e in ipairs(Store.ListProfiles() or {}) do
        local n = type(e) == "table" and e.name or e
        if type(n) == "string" then names[#names + 1] = n end
    end
    return names
end

local function exists(name)
    for _, n in ipairs(profileNames()) do
        if n == name then return true end
    end
    return false
end

--- Fehlercode des Stores in einen verstaendlichen Satz
local function failure(page, name, code)
    local c = tostring(code or ""):upper()
    if c:find("EXIST") then
        setStatus(page, L.UI_PROF_ERR_EXISTS:format(W.Plain(name)), C.warn)
    elseif c:find("DEFAULT") then
        setStatus(page, L.UI_PROF_ERR_DEFAULT, C.warn)
    elseif c:find("NAME") or c:find("INVALID") then
        setStatus(page, L.UI_PROF_ERR_NAME:format(Store.NAME_MAX), C.warn)
    else
        setStatus(page, L.UI_PROF_ERR_FAILED:format(W.Plain(code or "?")), C.warn)
    end
end

--- eingegebener Name (getrimmt) oder nil mit Hinweis
local function enteredName(page)
    local n = Store.ValidName(page.input:GetText())
    if not n then setStatus(page, L.UI_PROF_ERR_NAME:format(Store.NAME_MAX), C.warn) end
    return n
end

-- Zwei-Klick-Bestaetigung: erster Klick zeigt "Wirklich?", ein zweiter innerhalb weniger Sekunden fuehrt aus
local armed
local function disarm()
    if armed then
        armed.button:SetText(armed.text)
        armed = nil
    end
end
local function confirmed(button, text, action)
    if armed and armed.button == button then
        disarm()
        action()
        return
    end
    disarm()
    local token = { button = button, text = text }
    armed = token
    button:SetText(L.UI_PROF_CONFIRM)
    C_Timer.After(CONFIRM_SECONDS, function()
        if armed == token then disarm() end
    end)
end

local function done(page, text)
    page.input:SetText("")
    setStatus(page, text, C.ok)
    Config.Refresh(true)
end

local function actNew(page)
    local name = enteredName(page)
    if not name then return end
    if exists(name) then return failure(page, name, "EXISTS") end
    local ok, err = Store.CreateProfile(name)
    if not ok then return failure(page, name, err) end
    local set, setErr = Store.SetCharProfile(name)
    if not set then return failure(page, name, setErr) end
    done(page, L.UI_PROF_DONE_NEW:format(W.Plain(name)))
end

local function actCopy(page)
    local name = enteredName(page)
    if not name then return end
    if exists(name) then return failure(page, name, "EXISTS") end
    local ok, err = Store.CreateProfile(name, Store.GetActiveName())
    if not ok then return failure(page, name, err) end
    local set, setErr = Store.SetCharProfile(name)
    if not set then return failure(page, name, setErr) end
    done(page, L.UI_PROF_DONE_COPY:format(W.Plain(name)))
end

local function actRename(page)
    local old = Store.GetActiveName()
    if old == Store.DEFAULT then return failure(page, old, "DEFAULT") end
    local name = enteredName(page)
    if not name then return end
    if name ~= old and exists(name) then return failure(page, name, "EXISTS") end
    local ok, err = Store.RenameProfile(old, name)
    if not ok then return failure(page, name, err) end
    local set, setErr = Store.SetCharProfile(name) -- der Charakter bleibt auf dem umbenannten Profil
    if not set then return failure(page, name, setErr) end
    done(page, L.UI_PROF_DONE_RENAME:format(W.Plain(name)))
end

local function actReset(page)
    local name = Store.GetActiveName()
    local ok, err = Store.ResetProfile(name)
    if not ok then return failure(page, name, err) end
    done(page, L.UI_PROF_DONE_RESET:format(W.Plain(name)))
end

local function actDelete(page)
    local name = Store.GetActiveName()
    if name == Store.DEFAULT then return failure(page, name, "DEFAULT") end
    local ok, err = Store.DeleteProfile(name)
    if not ok then return failure(page, name, err) end
    done(page, L.UI_PROF_DONE_DELETE:format(W.Plain(name)))
end

local function actionButton(page, key, textKey, tipKey, x, y, fn, needConfirm)
    local text = L[textKey]
    local b
    b = W.Button(page, text, 130, function()
        if needConfirm then confirmed(b, text, function() fn(page) end) else disarm(); fn(page) end
    end)
    b:SetPoint("TOPLEFT", x, y)
    W.Tooltip(b, function() return text, L[tipKey] end)
    page[key] = b
    return b
end

Config.RegisterPage("profiles", {
    label = "UI_TAB_PROFILES",
    order = 70,
    height = 330,
    build = function(page)
        local h1 = W.Header(page, L.UI_PROF_HEAD_ACTIVE, 740)
        h1:SetPoint("TOPLEFT", 0, 0)
        page.info = W.Note(page, 4, -26, 736, "GameFontHighlightSmall", C.text)
        W.Label(page, L.UI_PROF_PICK, 4, -56)
        page.pick = W.Dropdown(page, 260, function(name)
            disarm()
            local set, setErr = Store.SetCharProfile(name)
            if set then setStatus(page, "") else failure(page, name, setErr) end
            Config.Refresh(true)
        end)
        page.pick:SetPoint("TOPLEFT", 4, -72)
        W.Tooltip(page.pick, function() return L.UI_PROF_PICK, L.UI_PROF_PICK_TIP end)

        local h2 = W.Header(page, L.UI_PROF_HEAD_MANAGE, 740)
        h2:SetPoint("TOPLEFT", 0, -118)
        W.Label(page, L.UI_PROF_NAME, 4, -144)
        page.input = W.Input(page, 260, Store.NAME_MAX)
        page.input:SetPoint("TOPLEFT", 4, -160)

        actionButton(page, "newBtn", "UI_PROF_NEW", "UI_PROF_NEW_TIP", 4, -196, actNew)
        actionButton(page, "copyBtn", "UI_PROF_COPY", "UI_PROF_COPY_TIP", 140, -196, actCopy)
        actionButton(page, "renameBtn", "UI_PROF_RENAME", "UI_PROF_RENAME_TIP", 276, -196, actRename)
        actionButton(page, "resetBtn", "UI_PROF_RESET", "UI_PROF_RESET_TIP", 4, -226, actReset, true)
        actionButton(page, "deleteBtn", "UI_PROF_DELETE", "UI_PROF_DELETE_TIP", 140, -226, actDelete, true)

        page.status = W.Note(page, 4, -266, 736, "GameFontNormalSmall", C.ok)
    end,
    refresh = function(page)
        local active = Store.GetActiveName()
        local options = {}
        for _, n in ipairs(profileNames()) do options[#options + 1] = { value = n, text = W.Plain(n) } end
        page.pick:SetOptions(options)
        page.pick:SetValue(active)
        page.info:SetText(L.UI_PROF_INFO:format(W.Plain(active)))
        local isDefault = active == Store.DEFAULT
        page.renameBtn:SetEnabled(not isDefault)
        page.deleteBtn:SetEnabled(not isDefault)
        -- eine Bestaetigung gilt nur fuer das Profil, bei dem sie angefordert wurde
        disarm()
    end,
    onClose = function() disarm() end,
})

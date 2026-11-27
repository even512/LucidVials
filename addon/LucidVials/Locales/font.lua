-- Texte des Reiters "Schrift" (Delta "Ausbau 1.1.0", E3): fuegt seine Schluessel in enUS und deDE ein (Core.lua liest erst danach).
local _, ns = ...
ns.Locales = ns.Locales or {}
local en, de = ns.Locales.enUS or {}, ns.Locales.deDE or {}
ns.Locales.enUS, ns.Locales.deDE = en, de

local function add(t, texts) for k, v in pairs(texts) do t[k] = v end end

add(en, {
    UI_FONT_HINT = "Pick a font, size, outline and shadow for each text. Fonts come with Lucid Vials, from Blizzard and from addons that provide LibSharedMedia fonts. Changes apply at once.",
    UI_FONT_EL_NAME = "Name",
    UI_FONT_EL_LEVEL = "Level",
    UI_FONT_EL_HEALTH = "Health value",
    UI_FONT_EL_POWER = "Resource value",
    UI_FONT_EL_XP = "Experience value",
    UI_FONT_FACE_TIP = "The font of this text. Bundled fonts are Marcellus (default), Philosopher, Almendra and MedievalSharp.",
    UI_FONT_MISSING = "%s (not available, Marcellus shown)",
    UI_FONT_SIZE = "Size",
    UI_FONT_SIZE_TIP = "Font size in pixels. Auto keeps the size Lucid Vials uses by default.",
    UI_FONT_SIZE_AUTO = "Auto",
    UI_FONT_SIZE_PX = "%d px",
    UI_FONT_OUTLINE_NONE = "No outline",
    UI_FONT_OUTLINE_THIN = "Thin outline",
    UI_FONT_OUTLINE_THICK = "Thick outline",
    UI_FONT_OUTLINE_TIP = "Outline of the letters. Thick helps on bright liquid.",
    UI_FONT_SHADOW = "Shadow",
    UI_FONT_SHADOW_TIP = "A soft ink shadow behind the letters.",
    UI_FONT_XP_ALL_ONLY = "The experience value uses the setting for all frames. Switch to \"For all frames\" to change it.",
    UI_FONT_INVALID = "This value was not accepted.",
    UI_FONT_SAMPLE_NAME = "Aldric Stonehelm",
    UI_FONT_SAMPLE_LEVEL = "60",
    UI_FONT_SAMPLE_NUMBERS = "12.3k / 16,842 (73%)",
})

add(de, {
    UI_FONT_HINT = "Wähle für jeden Text Schrift, Größe, Kontur und Schatten. Die Schriften kommen von Lucid Vials, von Blizzard und von Addons, die LibSharedMedia-Schriften bereitstellen. Änderungen wirken sofort.",
    UI_FONT_EL_NAME = "Name",
    UI_FONT_EL_LEVEL = "Stufe",
    UI_FONT_EL_HEALTH = "Lebenswert",
    UI_FONT_EL_POWER = "Ressourcenwert",
    UI_FONT_EL_XP = "XP-Wert",
    UI_FONT_FACE_TIP = "Die Schrift dieses Textes. Mitgeliefert sind Marcellus (Standard), Philosopher, Almendra und MedievalSharp.",
    UI_FONT_MISSING = "%s (nicht verfügbar, Marcellus wird gezeigt)",
    UI_FONT_SIZE = "Größe",
    UI_FONT_SIZE_TIP = "Schriftgröße in Pixeln. Auto behält die Größe, die Lucid Vials von sich aus nimmt.",
    UI_FONT_SIZE_AUTO = "Auto",
    UI_FONT_SIZE_PX = "%d px",
    UI_FONT_OUTLINE_NONE = "Keine Kontur",
    UI_FONT_OUTLINE_THIN = "Dünne Kontur",
    UI_FONT_OUTLINE_THICK = "Dicke Kontur",
    UI_FONT_OUTLINE_TIP = "Kontur der Buchstaben. Dick hilft auf heller Flüssigkeit.",
    UI_FONT_SHADOW = "Schatten",
    UI_FONT_SHADOW_TIP = "Ein weicher Tintenschatten hinter den Buchstaben.",
    UI_FONT_XP_ALL_ONLY = "Der XP-Wert nimmt die Einstellung „Für alle Rahmen“. Wechsle dorthin, um ihn zu ändern.",
    UI_FONT_INVALID = "Dieser Wert wurde nicht angenommen.",
    UI_FONT_SAMPLE_NAME = "Aldric Steinhelm",
    UI_FONT_SAMPLE_LEVEL = "60",
    UI_FONT_SAMPLE_NUMBERS = "12,3k / 16.842 (73 %)",
})

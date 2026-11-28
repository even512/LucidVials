-- Texte der animierten Portraits (Delta "Ausbau 1.1.0", E5): Reiter "Portrait" und /vials test portrait. Fuegt die Schluessel in
-- ns.Locales.enUS und ns.Locales.deDE ein (TOC: nach enUS/deDE).
local _, ns = ...
ns.Locales = ns.Locales or {}

local EN = {
    UI_PORTRAIT_HEAD_STYLE = "Portrait style",
    UI_PORTRAIT_STYLE = "Style",
    UI_PORTRAIT_STYLE_TIP = "How the portrait inside the ring is drawn. Only the player and target frames can change it; the target-of-target portrait always stays static.",
    UI_PORTRAIT_INTENSITY = "Effect strength",
    UI_PORTRAIT_FACING = "Facing",
    UI_PORTRAIT_FACING_TIP = "Which way the portrait looks, set separately for the player and the target frame. Mirrored flips the picture of every style; the models turn to the other side.",
    UI_PORTRAIT_FACING_NORMAL = "Default",
    UI_PORTRAIT_FACING_MIRRORED = "Mirrored",
    UI_PORTRAIT_INTENSITY_TIP = "How strong breathing, candle light, glass cracks, ripples and flashes are. 0 % shows only the plain picture of the style.",
    PORTRAIT_STYLE_STATIC = "Static (default)",
    PORTRAIT_STYLE_PAINTING = "Living painting",
    PORTRAIT_STYLE_SUBMERGED = "Submerged in the flask",
    PORTRAIT_STYLE_MODEL = "Reactive model",
    UI_PORTRAIT_DESC_STATIC = "The portrait of the game, unchanged.",
    UI_PORTRAIT_DESC_PAINTING = "A painted picture in the ring: it breathes slowly, flickers in candle light, darkens at the edges, shows glass cracks and a red glow at low health, flashes red when hit and warm when healed.",
    UI_PORTRAIT_DESC_SUBMERGED = "The portrait stands in the flask: below the health level a second, tinted copy ripples like seen through liquid, with rising bubbles. Hits stir the ripples, healing lights the surface.",
    PORTRAIT_STYLE_MODELPLAIN = "Animated model (plain)",
    UI_PORTRAIT_DESC_MODEL = "A 3D model of head and shoulders that reacts to hits, healing, casting and combat; resting dims it slowly, death and ghost turn it grey and still. Low health shows as cracks and a red glow. In dungeons and raids the game hides other units' models: there, and out of sight, the frame falls back to the living painting and tries the model again later.",
    UI_PORTRAIT_MODEL_FALLBACK = "Right now the game cannot show the model for: %s. The living painting stands in until it can.",
    UI_PORTRAIT_DESC_MODELPLAIN = "Only the 3D model in its idle animation, like the game's animated portraits: no reactions and no effects, just glass and ring around it. Where the game hides a unit's model (other units in dungeons and raids, out of sight), the static portrait stands in and the model returns later.",
    UI_PORTRAIT_MODELPLAIN_FALLBACK = "Right now the game cannot show the model for: %s. The static portrait stands in until it can.",
    UI_PORTRAIT_NOTE = "Hit and heal reactions at the target only appear when the game sends combat events for the target. Resting only reacts at the player.",
    PORTRAIT_TEST_RUN = "Portrait test: hit, heal, low health and rest on %d frame(s), about 11 seconds.",
    PORTRAIT_TEST_STATIC = "No animated portrait is active. Choose a style on the Portrait page (/vials config portrait).",
}

local DE = {
    UI_PORTRAIT_HEAD_STYLE = "Portrait-Stil",
    UI_PORTRAIT_STYLE = "Stil",
    UI_PORTRAIT_STYLE_TIP = "Wie das Portrait im Ring gezeichnet wird. Nur Spieler- und Zielrahmen lassen sich ändern; das Portrait des Ziels des Ziels bleibt immer statisch.",
    UI_PORTRAIT_INTENSITY = "Stärke der Effekte",
    UI_PORTRAIT_FACING = "Blickrichtung",
    UI_PORTRAIT_FACING_TIP = "Wohin das Portrait schaut, getrennt für Spieler- und Zielrahmen. Gespiegelt dreht das Bild jedes Stils um; die Modelle wenden sich zur anderen Seite.",
    UI_PORTRAIT_FACING_NORMAL = "Standard",
    UI_PORTRAIT_FACING_MIRRORED = "Gespiegelt",
    UI_PORTRAIT_INTENSITY_TIP = "Wie kräftig Atmen, Kerzenlicht, Glasrisse, Wellen und Blitze wirken. Bei 0 % zeigt der Stil nur das schlichte Bild.",
    PORTRAIT_STYLE_STATIC = "Statisch (Standard)",
    PORTRAIT_STYLE_PAINTING = "Lebendes Gemälde",
    PORTRAIT_STYLE_SUBMERGED = "Im Kolben versunken",
    PORTRAIT_STYLE_MODEL = "Reagierendes Modell",
    UI_PORTRAIT_DESC_STATIC = "Das Portrait des Spiels, unverändert.",
    UI_PORTRAIT_DESC_PAINTING = "Ein gemaltes Bild im Ring: es atmet langsam, flackert im Kerzenlicht, dunkelt an den Rändern ab, zeigt bei wenig Leben Glasrisse und Röte, blitzt bei Treffern rot und bei Heilung warm auf.",
    UI_PORTRAIT_DESC_SUBMERGED = "Das Portrait steht im Kolben: unter dem Lebenspegel liegt eine zweite, getönte Kopie, die wie durch Flüssigkeit gesehen wellt, mit aufsteigenden Blasen. Treffer rühren die Wellen auf, Heilung lässt die Oberfläche aufleuchten.",
    PORTRAIT_STYLE_MODELPLAIN = "Animiertes Modell (schlicht)",
    UI_PORTRAIT_DESC_MODEL = "Ein 3D-Modell von Kopf und Schultern, das auf Treffer, Heilung, Zaubern und Kampf reagiert; beim Ausruhen dunkelt es langsam ab, bei Tod und als Geist wird es grau und still. Wenig Leben zeigt sich als Glasrisse und Röte. In Dungeons und Schlachtzügen verbirgt das Spiel die Modelle anderer Einheiten: dort und außer Sicht fällt der Rahmen auf das lebende Gemälde zurück und versucht das Modell später erneut.",
    UI_PORTRAIT_MODEL_FALLBACK = "Das Spiel kann das Modell gerade nicht zeigen für: %s. Bis dahin steht das lebende Gemälde ein.",
    UI_PORTRAIT_DESC_MODELPLAIN = "Nur das 3D-Modell in seiner Ruheanimation, wie die animierten Portraits des Spiels: keine Reaktionen und keine Effekte, nur Glas und Ring drumherum. Wo das Spiel das Modell einer Einheit verbirgt (andere Einheiten in Dungeons und Schlachtzügen, außer Sicht), steht das statische Portrait ein und das Modell kommt später zurück.",
    UI_PORTRAIT_MODELPLAIN_FALLBACK = "Das Spiel kann das Modell gerade nicht zeigen für: %s. Bis dahin steht das statische Portrait ein.",
    UI_PORTRAIT_NOTE = "Treffer- und Heilungsreaktionen am Ziel erscheinen nur, wenn das Spiel Kampfereignisse für das Ziel sendet. Ruhe reagiert nur am Spieler.",
    PORTRAIT_TEST_RUN = "Portrait-Test: Treffer, Heilung, wenig Leben und Ruhe an %d Rahmen, etwa 11 Sekunden.",
    PORTRAIT_TEST_STATIC = "Kein animiertes Portrait aktiv. Wähle einen Stil im Reiter Portrait (/vials config portrait).",
}

for k, v in pairs(EN) do ns.Locales.enUS[k] = v end
for k, v in pairs(DE) do ns.Locales.deDE[k] = v end

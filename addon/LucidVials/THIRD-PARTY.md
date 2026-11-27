# Third-party components / Fremdbestandteile

Everything below keeps its own license. The license texts lie next to the files.
Alle Folgenden behalten ihre eigene Lizenz; die Lizenztexte liegen bei den Dateien.

## Libraries

Lucid Vials embeds no libraries: there is no `Libs` folder and no LibStub copy in the package.

Questie is not shipped either. For the quest symbol on the target portrait Lucid Vials reads Questie's public API
(`Questie.API.GetQuestObjectiveIconForUnit`) and its icon tables, and sets only the transparency of Questie's own icon on the
target frame (and puts it back); no file of Questie is included and nothing is written into Questie.

## Fonts

Four fonts in `Fonts\`, each under the SIL Open Font License 1.1. They are not renamed or modified (byte-identical to the
files in the Google Fonts repository, `ofl/<name>`). The license text of each font lies next to it as `Fonts\OFL-<Name>.txt`.
Marcellus is the default; the others are offered in the font tab of the settings window.

| Font | File | Copyright holder | Reserved Font Name (RFN) | Source |
|---|---|---|---|---|
| Marcellus | `Fonts\Marcellus-Regular.ttf` | Brian J. Bonislawsky DBA Astigmatic (AOETI) | "Marcellus" | see `Fonts\OFL-Marcellus.txt` |
| Philosopher | `Fonts\Philosopher-Regular.ttf` | The Philosopher Project Authors (https://github.com/alexeiva/philosopher) | none | see `Fonts\OFL-Philosopher.txt` |
| Almendra | `Fonts\Almendra-Regular.ttf` | Ana Sanfelippo | "Almendra" | see `Fonts\OFL-Almendra.txt` |
| MedievalSharp | `Fonts\MedievalSharp.ttf` | wmk69 | "MedievalSharp" | see `Fonts\OFL-MedievalSharp.txt` |

Also offered in the font tab, but not part of the package: the Blizzard fonts (Friz Quadrata, Arial Narrow, Morpheus,
Skurri), used through the game's own font objects, and the fonts of other addons that register with LibSharedMedia-3.0.
Lucid Vials only reads that list (`LibStub`, `List`, `Fetch`); LibSharedMedia is not included.

## Graphics and media

The files in `Media\` (unit frame textures, liquid and effect sprites, masks, the addon icon) are not covered by the MIT
license, see `LICENSE`.

Made with Google Gemini and processed by the author: the bronze tube frames, the portrait ring and its tube sockets, the
level plaques, the target ornaments (dragons, boss crest, marker, aura and level settings), the piston, the liquid, glass,
bubble, ember and effect sprites (`Media\uf-*.tga`), the bar frame, liquid fill, skull, quest mark and objective icons
(`np-frame`, `np-liquid`, `np-liquid-mono`, `np-skull`, `np-quest`, `np-obj-*`) and the addon icon. The source images are kept
in the development repository and are not part of the package. Drawn by script, with no third-party image: the masks
(`uf-mask-*`, `np-mask-capsule`), the liquid edge (`uf-edge-cover`, `uf-edge-rim`), the moving glint (`uf-glint`), the air and
back glass of the piston chamber (`uf-air`, `uf-glassback`) and `np-fill`, `np-inset`, `np-glass`.

## Game content

World of Warcraft, its interface and the names of places, zones and spells are (c) Blizzard Entertainment, Inc.
Lucid Vials is not affiliated with or endorsed by Blizzard. It contains no copied Blizzard textures; it only
changes how the game's own interface elements are shown.

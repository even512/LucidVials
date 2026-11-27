-- Texte der Profil-Bedienung (Store.ErrorText, Ausbau 1.1.0 E1). Ergaenzt ns.Locales.enUS/deDE; in der TOC nach enUS/deDE.
local _, ns = ...
local enUS, deDE = ns.Locales.enUS, ns.Locales.deDE

enUS.PROFILE_NAME_INVALID = "Invalid profile name (1-48 characters, no \"||\")."
enUS.PROFILE_EXISTS = "Profile \"%s\" already exists."
enUS.PROFILE_DEFAULT_PROTECTED = "The \"Default\" profile cannot be renamed or deleted."
enUS.PROFILE_NO_CHAR = "Character not known yet, please try again in a moment."

deDE.PROFILE_NAME_INVALID = "Ungültiger Profilname (1-48 Zeichen, kein \"||\")."
deDE.PROFILE_EXISTS = "Das Profil \"%s\" gibt es schon."
deDE.PROFILE_DEFAULT_PROTECTED = "Das Profil \"Default\" lässt sich nicht umbenennen oder löschen."
deDE.PROFILE_NO_CHAR = "Der Charakter ist noch nicht bekannt, bitte gleich noch einmal versuchen."

-- rules.lua — Boggle's two rules texts: solo and "· multiplayer" (shown
-- by ScreenBase:makeModeRulesButtonConfig, each with a button to the other).
local _ = require("i18n")

local SOLO_EN = _([[
Boggle — Rules

Find as many words as possible by connecting adjacent letters in the 4×4 grid.

Rules:
• Letters must be adjacent (horizontally, vertically, or diagonally).
• Each letter in the grid may only be used once per word.
• Minimum word length: 3 letters.
• Longer words score more points.

Tap letters in sequence to build a word, then tap Submit to score it.
The timer counts down — find as many words as you can before it runs out!
]])

local SOLO_FR = [[
Boggle — Règles

Trouvez le plus de mots possible en reliant des lettres adjacentes dans la grille.

Règles :
• Les lettres doivent être adjacentes (horizontalement, verticalement ou en diagonale).
• Chaque lettre de la grille ne peut être utilisée qu'une seule fois par mot.
• Longueur minimale : 3 lettres.
• Les mots plus longs rapportent plus de points.

Appuyez sur les lettres dans l'ordre pour former un mot, puis sur Valider. La minuterie décompte — trouvez le maximum de mots avant la fin !
]]

local PARTY_EN = _([[
Boggle · multiplayer — Rules

The reader lies in the middle of the table and shows one big grid to everyone; each player needs a sheet of paper and a pen. The reader runs the timer, shows the solutions and keeps the scores.

Setup (menu):
• Players: 2 to 8; Player names: tap a seat to type a name (remembered).
• Rounds: 1 to 10 per match. Duration: 2, 3, 4 or 5 minutes per round (the timer can be hidden). Language: the EN or FR word list.

A round:
• Tap Start round: the letters appear and the countdown starts. Everybody searches at the same time and writes down words, in silence. Pause stops the clock.
• Letters must be adjacent (horizontally, vertically or diagonally); each letter is used only once per word; minimum 3 letters.
• At zero (or on Solutions), every word of the grid is shown, grouped by length.

Scoring:
• Each player in turn reads their list aloud. A word found by more than one player is crossed out by everyone who has it. Words not in the list of solutions are crossed out too.
• Then, player by player, tap the length of each word left on that player's sheet: 3 or 4 letters = 1 point, 5 = 2, 6 = 3, 7 = 5, 8 or more = 11. The reader adds them up. Undo removes the last tap (or goes back to the previous player). Next player, then End round adds the round's points to the scores, shown after each round.

End of the match:
• After the last round, the highest total wins. Players with the same best total share the win (a tie). New game starts a new match with the same players.
]])

local PARTY_FR = [[
Boggle · à plusieurs — Règles

La liseuse est posée au milieu de la table et montre une grande grille à tous ; chaque joueur a une feuille et un stylo. La liseuse gère le temps, affiche les solutions et compte les points.

Préparation (menu) :
• Joueurs : de 2 à 8 ; Noms des joueurs : touchez une place pour saisir un nom (mémorisé).
• Manches : de 1 à 10 par partie. Durée : 2, 3, 4 ou 5 minutes par manche (le minuteur peut être masqué). Langue : liste de mots FR ou EN.

Une manche :
• Touchez Commencer la manche : les lettres apparaissent et le compte à rebours démarre. Tout le monde cherche en même temps et note ses mots, en silence. Pause arrête le temps.
• Les lettres doivent être adjacentes (horizontalement, verticalement ou en diagonale) ; chaque lettre ne sert qu'une fois par mot ; 3 lettres minimum.
• À zéro (ou avec Solutions), tous les mots de la grille s'affichent, classés par longueur.

Décompte :
• Chaque joueur lit sa liste à voix haute. Un mot trouvé par plusieurs joueurs est barré par tous ceux qui l'ont. Les mots absents des solutions sont barrés aussi.
• Puis, joueur par joueur, touchez la longueur de chaque mot restant sur sa feuille : 3 ou 4 lettres = 1 point, 5 = 2, 6 = 3, 7 = 5, 8 ou plus = 11. La liseuse fait le total. Annuler retire la dernière touche (ou revient au joueur précédent). Joueur suivant, puis Fin de manche ajoute les points de la manche aux scores, affichés après chaque manche.

Fin de partie :
• Après la dernière manche, le meilleur total gagne. Des joueurs à égalité au meilleur total se partagent la victoire. Nouvelle partie relance une partie avec les mêmes joueurs.
]]

return {
    solo  = { SOLO_EN, SOLO_FR },
    party = { PARTY_EN, PARTY_FR },
}

# Changelog

All notable changes to this project will be documented in this file.

## [1.6.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.6.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.
- Uses less memory: the dictionary loads when the game opens, only for the
  language played, and is freed when it closes.

## [1.6.0] - 2026-11-04

### Changed
- Much faster grids: the word search now stops as soon as a run of letters
  cannot start any word. Rolling a new grid went from about 0.2-0.3 s on a
  desktop (several seconds on a reader) to a few milliseconds; the first
  grid after opening also builds a small prefix list (about 0.03 s on a
  desktop, under a second on a reader). Same words found as before.
- Opening the game with a game in progress no longer rolls and solves a
  throwaway grid before restoring yours: opening went from about 0.5 s on a
  desktop (over 10 s on a reader) to about the time it takes to read the
  dictionary.

## [1.5.1] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.5.0] - 2026-11-02

### Added
- **Boggle · multiplayer** (« Boggle · à plusieurs »), listed under Tools →
  Games → Party & quiz, or **Mode: Multiplayer** in the game's menu. It
  replaces the separate **Boggle Party** plugin, which is retired: Boggle
  Party is now "Boggle · multiplayer". Everything it did is here — the big
  grid for table play, the 2–5 minute countdown where only the timer
  refreshes, the reveal at zero with every word grouped by length and the
  totals, EN/FR word lists, the show/hide timer choice — plus players and
  scores: after the reveal, players cross out the words someone else also
  found and tap the length of each word left, the reader adds up the points;
  a match of 1–10 rounds with a scoreboard after each and a winner at the end.
  Pause/Resume during a round; a match in progress is saved and comes back
  (a running round paused).
- On the first multiplayer launch, Boggle Party's language, duration and
  timer choice are imported, unless multiplayer settings already exist
  (Boggle Party's settings file is only read).

### Changed
- Family-friendly words: the missed-word list, the multiplayer solutions
  and the word total leave out vulgar, sexual, scatological, slur and
  drug-related words (`blocklist.lua`). A player who finds one still scores
  it.

### Fixed
- The English word list could be another game's: it was loaded with
  `require("words_en")`, which searches every word game's directory, so with
  e.g. Word Search or Wordle installed Boggle could end up with their much shorter list and
  rejected ordinary words. It now always reads its own list, and each list is
  loaded once (a restored game used to read the French one twice).

## [1.4.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.4.0] - 2026-10-30

### Changed
- Redesigned play screen: the grid fills the room the controls leave, with the
  found words in a scrolling box above a full-width Submit/Clear/Done bar.
- The status line reads "WORD · Score: 12 · Found: 5/48", the word being
  traced first so it stays visible, and wraps in landscape.
- After Done, every missed word is listed under the found ones in the word
  box, instead of the first twenty on the status line, where they never
  fitted. The status shows the final score.
- Once the round is over, the action bar shows "New game" in place of its
  buttons.
- The language entry in the title-bar menu reads "Language: EN" instead of a
  bare "EN".

### Fixed
- Letters and the small order numbers on traced tiles are fitted to their
  tile; their size used to be scaled by DPI twice, so they overflowed on
  high-DPI screens.

## [1.3.2] - 2026-10-07

### Fixed
- The Tools menu entry is translated again. `main.lua` took `_` from
  KOReader's `gettext`, which knows nothing of this plugin's strings, so the
  menu label stayed English while the game's own screen, which goes through
  `i18n`, was translated. `_` now comes from `i18n` here too.


## [1.3.1] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.3.0] - 2026-09-30

### Added
- French dictionary goes from 47,435 to **132,778 words**, now covering 3-9
  letters instead of stopping at 7. The 3-7 letter words are the original CC0
  Scrabble-valid list; the 8- and 9-letter words come from
  `an-array-of-french-words` (MIT), normalized the same way.
- This removes the asymmetry the English dictionary work had inverted rather
  than fixed: only English could reach the longest words. Both languages now
  cover the full nine-tile draw.


## [1.2.0] - 2026-09-30

### Added
- English dictionary goes from 1,837 to **105,145 words** (3-9 letters), from
  the Public-Domain ENABLE word-game list. On the same 20 grids, findable words
  per grid go from 24.0 to 108.5 — at last the same order of magnitude as the
  French list.

### Fixed
- README advertised dictionaries for "EN, FR, DE, ES"; only EN and FR have ever
  existed.

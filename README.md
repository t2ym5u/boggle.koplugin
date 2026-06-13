# boggle.koplugin

A Boggle-style word search plugin for [KOReader](https://github.com/koreader/koreader).


## Screenshot

*(Screenshot to be added.)*

## Rules

Find words by connecting adjacent letters (horizontally, vertically, or diagonally) in the letter grid. Each letter may be used only once per word. Words must be at least 3 letters long. Longer words score more points — race against the clock!

## Concept

Find as many words as possible in a 4×4 grid of letters by connecting adjacent
letters (including diagonals). Each letter may only be used once per word.
Longer words score more points.

## Features

- **Grid sizes** — 4×4 (classic), 5×5 (extended)
- **Multiple languages** — dictionaries for EN, FR, DE, ES
- **Word validation** — against a bundled dictionary for the chosen language
- **Scoring** — standard Boggle scoring (3 letters = 1 pt, up to 8+ letters = 11 pts)
- **Timer** — configurable countdown (1, 2 or 3 minutes) or untimed mode
- **Word list** — found words listed alphabetically with scores
- **End reveal** — shows all valid words missed after the timer expires
- **High scores** — best scores stored per language and grid size

## Controls

| Action | How |
|--------|-----|
| Start a word path | Tap the first letter |
| Extend the path | Tap adjacent letters in sequence |
| Submit word | Tap **Submit** or re-tap the last letter |
| Cancel current word | Tap **Cancel** |
| New game | Tap **New game** |
| Change language | Tap **Lang** |
| Show rules | Tap **Rules** |

## Why e-ink friendly?

Letter selection is tap-based and discrete. The grid and word list are static
between taps, so e-ink refresh is only triggered on each new letter tap.

## License

GPL-3.0

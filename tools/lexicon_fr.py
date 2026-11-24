#!/usr/bin/env python3
# Widens boggle.koplugin/words_fr.lua with the Grammalecte lexicon, and holds
# the lexicon filter the other word games' build scripts import. Run from the
# monorepo root:
#
#   python3 boggle.koplugin/tools/lexicon_fr.py FR_LEXICON
#
# FR_LEXICON is lexique-grammalecte-fr-v7.7.txt, the Grammalecte / Dicollecte
# list of French inflected forms (Olivier R., https://grammalecte.net, Mozilla
# Public License 2.0), from
# https://www.grammalecte.net/dic/lexique-grammalecte-fr-v7.7.zip -- not
# vendored (55 MB).
#
# words_fr.lua keeps its first block, `raw`, byte for byte: the other games'
# build scripts (anagram, letterpyramid, spellingbee) read only that block, so
# their puzzles do not move. The lexicon's words go in a second block, `extra`,
# that this script rewrites: the 3-9 letter forms (9: numletters' tiles) not
# already in `raw`, filtered by lexicon_words(). Nothing is ever removed from
# `raw`. numletters.koplugin/words_fr.lua is a copy of this file: copy it over.
import glob, os, re, sys, unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
MONOREPO = os.path.dirname(ROOT)
LEXICON_VERSION = "7.7"

# Lexicon entries never taken (column -> tags): pejorative, slang, familiar
# (where most vulgar words sit), sexual; and symbols, abbreviations written as
# such, acronyms, chemical formulas, onomatopoeias. A form with any such entry
# is dropped, whatever its other entries say.
LEXICON_BANNED_TAGS = {
    7: {"péj", "arg", "fam", "symb", "abty", "sig", "cc", "onom"},
    8: {"sexe"},
}

MARK = "-- Added from the Grammalecte lexicon"


def normalize(word):
    # Same normalization as the dictionaries: accents stripped, ligatures
    # spelt out, anything left that is not a-z (apostrophes, hyphens) dropped.
    w = word.lower().replace("œ", "oe").replace("æ", "ae")
    w = "".join(c for c in unicodedata.normalize("NFD", w) if unicodedata.category(c) != "Mn")
    return w.upper() if re.fullmatch(r"[a-z]+", w) else None


def family_blocklist():
    # Every French blocklist of the monorepo's word games, uppercase: the
    # tools/blocklist_fr.txt files, the fr block of each blocklist.lua, and
    # tools/lexicon_blocklist_fr.txt (lexicon words found in review). The
    # lexicon's words are additions, so they get the strictest filter.
    blocked = set()
    paths = glob.glob(os.path.join(MONOREPO, "*.koplugin", "tools", "blocklist_fr.txt"))
    paths.append(os.path.join(ROOT, "tools", "lexicon_blocklist_fr.txt"))
    for path in paths:
        blocked |= {l.strip() for l in open(path, encoding="utf-8") if l.strip() and not l.startswith("#")}
    for path in glob.glob(os.path.join(MONOREPO, "*.koplugin", "blocklist.lua")):
        m = re.search(r"fr\s*=\s*\[\[(.*?)\]\]", open(path, encoding="utf-8").read(), re.S)
        if m:
            blocked |= set(re.findall(r"[A-Z]+", m.group(1)))
    return blocked


def lexicon_words(path, blocked):
    # The Grammalecte lexicon: one tab-separated line per (form, lemma, tags),
    # after a header. Columns: 2 form, 3 lemma, 7 usage notes (fam, péj, arg,
    # vx...), 8 semantic field, 10 sub-dictionary ("*" all spellings, "M"/"R"
    # before / after the 1990 reform, "C" classic, "A" alternative, "X"
    # excluded). Kept: forms starting lowercase (no proper nouns, acronyms or
    # symbols), not in sub-dictionary X, with no banned tag on any of their
    # entries, not blocked, and whose lemma has no form in `blocked`: blocking
    # ENCULER blocks ENCULENT, which no blocklist lists. Uppercase, a-z only.
    entries = []
    for line in open(path, encoding="utf-8"):
        cols = line.rstrip("\n").split("\t")
        if len(cols) < 11 or not cols[0].isdigit():
            continue
        form, lemma = normalize(cols[2]), normalize(cols[3])
        if not form:
            continue
        banned = ("X" in cols[10].split("/") or not cols[2][:1].islower() or any(
            set(cols[c].split()) & tags for c, tags in LEXICON_BANNED_TAGS.items()))
        entries.append((form, lemma, banned))
    blocked_lemmas = {l for f, l, _ in entries if l and (f in blocked or l in blocked)}
    good, bad = set(), set()
    for form, lemma, banned in entries:
        (bad if banned or lemma in blocked_lemmas else good).add(form)
    return good - bad - blocked


def blocks_of(path):
    # The words of each [[...]] block of a word list, uppercase, in order.
    text = open(path, encoding="utf-8").read()
    return [{w.upper() for w in re.findall(r"[A-Za-z]+", b)} for b in re.findall(r"\[\[(.*?)\]\]", text, re.S)]


def wrap(words, width=150):
    lines, line = [], ""
    for w in words:
        if line and len(line) + len(w) + 1 > width:
            lines.append(line)
            line = ""
        line += w + ","
    lines.append(line)
    return "\n".join(lines)


def main(lexicon_path):
    path = os.path.join(ROOT, "words_fr.lua")
    text = open(path, encoding="utf-8").read()
    # Everything up to the raw block's loop; a lexicon block from an earlier
    # run (from MARK on) is dropped and written again.
    head = text.split(MARK)[0]
    if head.endswith("return W\n"):
        head = head[: -len("return W\n")]
    if not head.endswith("end\n"):
        sys.exit("words_fr.lua: unexpected layout (the raw block's loop should come last)")
    raw = blocks_of(path)[0]
    extra = {w for w in lexicon_words(lexicon_path, family_blocklist()) if 3 <= len(w) <= 9} - raw
    with open(path, "w", encoding="utf-8") as f:
        f.write(head)
        f.write(f"""{MARK} v{LEXICON_VERSION} (Olivier R., Dicollecte,
-- https://grammalecte.net, Mozilla Public License 2.0): {len(extra)} more 3-9
-- letter forms, minus those marked familiar, pejorative, slang or sexual,
-- symbols and acronyms, and every form of a word the family blocklists
-- carry. Generated by tools/lexicon_fr.py; `raw` above is never changed by it.
local extra = [[
{wrap(sorted(w.lower() for w in extra))}
]]
for word in extra:gmatch("[a-z]+") do W[word] = true end
return W
""")
    print("words_fr.lua: raw", len(raw), "+ extra", len(extra))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: lexicon_fr.py FR_LEXICON")
    main(sys.argv[1])

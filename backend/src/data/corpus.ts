import { a1Words } from './a1-words.js'
import { a1AdjectiveLexicon } from './lexicon/a1-adjectives.js'
import { a1FunctionLexicon } from './lexicon/a1-function.js'
import { a1NounLexicon } from './lexicon/a1-nouns.js'
import { a1VerbLexicon } from './lexicon/a1-verbs.js'
import { a2CoreLexicon } from './lexicon/a2-core.js'
import { a2NounTable } from './lexicon/a2-nouns.js'
import { adjectiveTable, peopleAdjectiveLexicon } from './lexicon/adjectives.js'
import { b1CoreLexicon } from './lexicon/b1-core.js'
import { b1NounTable } from './lexicon/b1-nouns.js'
import { b2CoreLexicon } from './lexicon/b2-core.js'
import { b2NounTable } from './lexicon/b2-nouns.js'
import { c1CoreLexicon } from './lexicon/c1-core.js'
import { c1NounTable } from './lexicon/c1-nouns.js'
import { expandAdjectiveTable, expandNounTable } from './lexicon/expand-rows.js'
import { extraNounTable } from './lexicon/extra-nouns.js'
import { fillNounTable } from './lexicon/fill-nouns.js'
import { fillVerbLexicon } from './lexicon/fill-verbs.js'
import { gapNounTable } from './lexicon/gap-nouns.js'
import { gapVerbLexicon } from './lexicon/gap-verbs.js'
import { groupLexicon } from './lexicon/groups.js'
import { moreNounTable } from './lexicon/more-nouns.js'
import { skeletonNounTable } from './lexicon/skeleton-nouns.js'
import { parseLexicon } from './parse-lexicon.js'
import type { SeedWord } from './a1-words.js'

const pipeSources: ReadonlyArray<readonly [string, string]> = [
  ['a1-function', a1FunctionLexicon],
  ['a1-verbs', a1VerbLexicon],
  ['a1-nouns', a1NounLexicon],
  ['a1-adjectives', a1AdjectiveLexicon],
  ['a2-core', a2CoreLexicon],
  ['fill-verbs', fillVerbLexicon],
  ['groups', groupLexicon],
  ['people-adjectives', peopleAdjectiveLexicon],
  ['b1-core', b1CoreLexicon],
  ['gap-verbs', gapVerbLexicon],
  ['b2-core', b2CoreLexicon],
  ['c1-core', c1CoreLexicon],
]

const merged: SeedWord[] = [...a1Words]

for (const [origin, source] of pipeSources) {
  merged.push(...parseLexicon(source, origin))
}

const nounTables: ReadonlyArray<readonly [string, string]> = [
  ['skeleton-nouns', skeletonNounTable],
  ['a2-nouns', a2NounTable],
  ['fill-nouns', fillNounTable],
  ['gap-nouns', gapNounTable],
  ['b1-nouns', b1NounTable],
  ['extra-nouns', extraNounTable],
  ['more-nouns', moreNounTable],
  ['b2-nouns', b2NounTable],
  ['c1-nouns', c1NounTable],
]

for (const [origin, source] of nounTables) {
  merged.push(...expandNounTable(source, origin))
}

merged.push(...expandAdjectiveTable(adjectiveTable, 'adjectives'))

const seen = new Set<string>()
for (const word of merged) {
  if (seen.has(word.lemma)) {
    throw new Error(`Duplicate lemma: ${word.lemma}`)
  }
  seen.add(word.lemma)
}

if (merged.length !== 4000) {
  throw new Error(`Curriculum must contain 4000 lemmas, got ${merged.length}`)
}

/**
 * Full curriculum in study order.
 * The original 120 A1 words stay first. Connectors and verbs come before
 * the larger noun sets, because those words build the sentence around the nouns.
 */
export const curriculum: readonly SeedWord[] = merged

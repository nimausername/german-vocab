import type { SeedWord } from '../a1-words.js'
import { parseLexicon } from '../parse-lexicon.js'

const article = (gender: string, lemma: string) => `${gender} ${lemma}`

/**
 * A short everyday sentence for nouns that have no hand-written example.
 * The three frames are situations people actually say.
 */
const nounSentence = (gender: string, lemma: string, gloss: string, index: number) => {
  const nom = article(gender, lemma)
  const object = gender === 'der' ? `den ${lemma}` : nom
  const frame = index % 3

  if (frame === 0) {
    return [`Wo ist ${nom}?`, `Where is the ${gloss}?`]
  }
  if (frame === 1) {
    return [`Ich sehe ${object}.`, `I see the ${gloss}.`]
  }
  return [`Ich brauche ${object}.`, `I need the ${gloss}.`]
}

/**
 * Expands compact noun rows: gender|lemma|plural|gloss|level
 * plural "-" means uncountable. Lemma is the bare noun, without an article.
 */
export const expandNounTable = (source: string, origin: string): SeedWord[] => {
  const rendered: string[] = []
  const lines = source.split('\n')

  for (const [index, raw] of lines.entries()) {
    const line = raw.trim()
    if (!line || line.startsWith('#')) {
      continue
    }

    const parts = line.split('|')
    if (parts.length !== 5) {
      throw new Error(`${origin}:${index + 1} expected 5 fields: ${line}`)
    }

    const gender = parts[0]?.trim() ?? ''
    const lemma = parts[1]?.trim() ?? ''
    const plural = parts[2]?.trim() ?? ''
    const gloss = parts[3]?.trim() ?? ''
    const level = parts[4]?.trim() ?? ''
    const [exampleDe, exampleEn] = nounSentence(gender, lemma, gloss, rendered.length)
    const pluralField = plural === '-' ? '-' : `die ${plural}`

    rendered.push(
      `${article(gender, lemma)}|${gender}|${pluralField}|${gloss}|${level}|noun|${exampleDe}|${exampleEn}`,
    )
  }

  return parseLexicon(rendered.join('\n'), origin)
}

/**
 * Expands compact adjective rows: lemma|gloss|level
 */
export const expandAdjectiveTable = (source: string, origin: string): SeedWord[] => {
  const rendered: string[] = []
  const lines = source.split('\n')

  for (const [index, raw] of lines.entries()) {
    const line = raw.trim()
    if (!line || line.startsWith('#')) {
      continue
    }

    const parts = line.split('|')
    if (parts.length !== 3) {
      throw new Error(`${origin}:${index + 1} expected 3 fields: ${line}`)
    }

    const lemma = parts[0]?.trim() ?? ''
    const gloss = parts[1]?.trim() ?? ''
    const level = parts[2]?.trim() ?? ''

    rendered.push(`${lemma}|-|-|${gloss}|${level}|adjective|Das finde ich ${lemma}.|I find that ${gloss}.`)
  }

  return parseLexicon(rendered.join('\n'), origin)
}

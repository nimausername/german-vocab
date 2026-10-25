import type { SeedWord } from '../a1-words.js'
import { parseLexicon } from '../parse-lexicon.js'

const article = (gender: string, lemma: string) => `${gender} ${lemma}`

const capitalize = (value: string) => value.charAt(0).toUpperCase() + value.slice(1)

/**
 * Builds a nominative sentence that shows the noun's gender.
 * Cards are reviewed one at a time, so the repeated frames teach a usable pattern.
 */
const nounSentence = (gender: string, lemma: string, gloss: string, index: number) => {
  const nom = article(gender, lemma)
  const cap = capitalize(nom)
  const frame = index % 4

  if (frame === 0) {
    return [`${cap} ist wichtig.`, `The ${gloss} is important.`]
  }
  if (frame === 1) {
    return [`Für viele Menschen ist ${nom} wichtig.`, `For many people, the ${gloss} is important.`]
  }
  if (frame === 2) {
    return [`${cap} bleibt wichtig.`, `The ${gloss} stays important.`]
  }
  return [`Heute ist ${nom} wichtig.`, `The ${gloss} is important today.`]
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

    rendered.push(`${lemma}|-|-|${gloss}|${level}|adjective|Das ist ${lemma}.|That is ${gloss}.`)
  }

  return parseLexicon(rendered.join('\n'), origin)
}

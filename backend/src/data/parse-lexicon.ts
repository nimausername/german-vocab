import { z } from 'zod'
import type { SeedWord } from './a1-words.js'

const cefrLevelSchema = z.enum(['A1', 'A2', 'B1', 'B2', 'C1'])

const genderSchema = z.enum(['der', 'die', 'das'])

const tagSchema = z.enum([
  'pronoun',
  'verb',
  'modal',
  'noun',
  'adverb',
  'adjective',
  'conjunction',
  'phrase',
  'question',
  'quantifier',
  'determiner',
  'preposition',
  'number',
  'particle',
])

const seedWordSchema = z
  .object({
    lemma: z.string().trim().min(1).max(128),
    gender: genderSchema.nullable(),
    plural: z.string().trim().min(1).max(128).nullable(),
    glossEn: z.string().trim().min(1).max(256),
    cefrLevel: cefrLevelSchema,
    exampleDe: z.string().trim().min(1),
    exampleEn: z.string().trim().min(1),
    tags: z.array(tagSchema).min(1),
  })
  .superRefine((word, context) => {
    const isNoun = word.tags.includes('noun')
    if (isNoun && !word.gender) {
      context.addIssue({
        code: 'custom',
        message: 'Nouns need a gender',
        path: ['gender'],
      })
    }
    if (!isNoun && word.gender) {
      context.addIssue({
        code: 'custom',
        message: 'Only nouns have a gender',
        path: ['gender'],
      })
    }
  })

/**
 * Parses a pipe-delimited lexicon block into seed words.
 * Columns: lemma|gender|plural|gloss|cefr|tags|exampleDe|exampleEn
 * Use "-" for an empty gender or plural. Lines starting with "#" are comments.
 */
export const parseLexicon = (source: string, origin: string): SeedWord[] => {
  const words: SeedWord[] = []
  const lines = source.split('\n')

  for (const [index, raw] of lines.entries()) {
    const line = raw.trim()
    if (!line || line.startsWith('#')) {
      continue
    }

    const parts = line.split('|')
    if (parts.length !== 8) {
      throw new Error(
        `${origin}:${index + 1} expected 8 fields, got ${parts.length}: ${line.slice(0, 120)}`,
      )
    }

    const lemma = parts[0]?.trim() ?? ''
    const genderRaw = parts[1]?.trim() ?? ''
    const pluralRaw = parts[2]?.trim() ?? ''
    const glossEn = parts[3]?.trim() ?? ''
    const cefrLevel = parts[4]?.trim() ?? ''
    const tagsRaw = parts[5]?.trim() ?? ''
    const exampleDe = parts[6]?.trim() ?? ''
    const exampleEn = parts[7]?.trim() ?? ''

    const parsed = seedWordSchema.safeParse({
      lemma,
      gender: genderRaw === '-' ? null : genderRaw,
      plural: pluralRaw === '-' ? null : pluralRaw,
      glossEn,
      cefrLevel,
      exampleDe,
      exampleEn,
      tags: tagsRaw.split(',').map((tag) => tag.trim()).filter((tag) => tag.length > 0),
    })

    if (!parsed.success) {
      const reason = parsed.error.issues.map((issue) => issue.message).join('; ')
      throw new Error(`${origin}:${index + 1} ${lemma || '(empty)'}: ${reason}`)
    }

    words.push(parsed.data)
  }

  return words
}

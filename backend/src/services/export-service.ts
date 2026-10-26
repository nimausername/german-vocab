import { and, asc, eq } from 'drizzle-orm'
import { db } from '../db/client.js'
import { cards, words, type UserProfile } from '../db/schema.js'

export type ExportFormat = 'csv' | 'anki'

export type ProgressExport = {
  filename: string
  mimeType: string
  content: string
}

type ExportRow = {
  lemma: string
  gender: string | null
  plural: string | null
  glossEn: string
  cefrLevel: string
  exampleDe: string
  exampleEn: string
  reps: number
  lapses: number
  state: number
  due: string
  lastReview: string
  stability: string
  difficulty: string
}

const csvEscape = (value: string): string => {
  if (/[",\n\r]/.test(value)) {
    return `"${value.replaceAll('"', '""')}"`
  }
  return value
}

const articleFor = (gender: string | null): string => {
  if (!gender) return ''
  const key = gender.trim().toLowerCase()
  if (key === 'der' || key === 'm' || key === 'masculine') return 'der'
  if (key === 'die' || key === 'f' || key === 'feminine') return 'die'
  if (key === 'das' || key === 'n' || key === 'neuter') return 'das'
  if (['der', 'die', 'das'].includes(key)) return key
  return ''
}

const headword = (lemma: string, gender: string | null): string => {
  const article = articleFor(gender)
  const trimmed = lemma.trim()
  const parts = trimmed.split(/\s+/, 2)
  const noun =
    parts.length === 2 && ['der', 'die', 'das'].includes(parts[0]!.toLowerCase())
      ? parts[1]!
      : trimmed
  return article ? `${article} ${noun}` : trimmed
}

const loadRows = async (user: UserProfile): Promise<ExportRow[]> => {
  const rows = await db
    .select({
      lemma: words.lemma,
      gender: words.gender,
      plural: words.plural,
      glossEn: words.glossEn,
      cefrLevel: words.cefrLevel,
      exampleDe: words.exampleDe,
      exampleEn: words.exampleEn,
      reps: cards.reps,
      lapses: cards.lapses,
      state: cards.state,
      due: cards.due,
      lastReview: cards.lastReview,
      stability: cards.stability,
      difficulty: cards.difficulty,
      sortOrder: words.sortOrder,
    })
    .from(cards)
    .innerJoin(words, eq(cards.wordId, words.id))
    .where(and(eq(cards.userId, user.id)))
    .orderBy(asc(words.sortOrder))

  return rows.map((row) => ({
    lemma: row.lemma,
    gender: row.gender,
    plural: row.plural,
    glossEn: row.glossEn,
    cefrLevel: row.cefrLevel,
    exampleDe: row.exampleDe,
    exampleEn: row.exampleEn,
    reps: row.reps,
    lapses: row.lapses,
    state: row.state,
    due: row.due.toISOString(),
    lastReview: row.lastReview?.toISOString() ?? '',
    stability: String(row.stability),
    difficulty: String(row.difficulty),
  }))
}

const toCsv = (rows: ExportRow[]): string => {
  const header = [
    'lemma',
    'article',
    'plural',
    'glossEn',
    'cefrLevel',
    'exampleDe',
    'exampleEn',
    'reps',
    'lapses',
    'state',
    'due',
    'lastReview',
    'stability',
    'difficulty',
  ].join(',')

  const lines = rows.map((row) =>
    [
      row.lemma,
      articleFor(row.gender),
      row.plural ?? '',
      row.glossEn,
      row.cefrLevel,
      row.exampleDe,
      row.exampleEn,
      String(row.reps),
      String(row.lapses),
      String(row.state),
      row.due,
      row.lastReview,
      row.stability,
      row.difficulty,
    ]
      .map(csvEscape)
      .join(','),
  )

  return [header, ...lines].join('\n') + '\n'
}

/**
 * Anki text import: Front [tab] Back [tab] Tags
 */
const toAnki = (rows: ExportRow[]): string => {
  const lines = rows.map((row) => {
    const front = headword(row.lemma, row.gender)
    const back = row.glossEn
    const tags = `GermanVocab ${row.cefrLevel}`.replaceAll(/\s+/g, '_')
    return `${front}\t${back}\t${tags}`
  })
  return lines.join('\n') + (lines.length > 0 ? '\n' : '')
}

/**
 * Builds a progress backup for the signed-in learner.
 */
export const buildProgressExport = async (
  user: UserProfile,
  format: ExportFormat,
): Promise<ProgressExport> => {
  const rows = await loadRows(user)
  if (format === 'anki') {
    return {
      filename: `german-vocab-anki-${user.id.slice(0, 8)}.txt`,
      mimeType: 'text/tab-separated-values',
      content: toAnki(rows),
    }
  }
  return {
    filename: `german-vocab-progress-${user.id.slice(0, 8)}.csv`,
    mimeType: 'text/csv',
    content: toCsv(rows),
  }
}

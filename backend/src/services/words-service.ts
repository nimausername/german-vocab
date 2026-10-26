import { and, asc, count, eq, ilike, isNull, or, sql, type SQL } from 'drizzle-orm'
import { db } from '../db/client.js'
import { cards, words, type UserProfile } from '../db/schema.js'
import { practiceSentence } from './practice-sentence.js'

export type WordListStatus = 'all' | 'learned' | 'new'

export type WordListQuery = {
  user: UserProfile
  page: number
  limit: number
  search?: string
  cefrLevel?: string
  gender?: string
  status?: WordListStatus
}

export type WordListItem = {
  id: string
  lemma: string
  gender: string | null
  plural: string | null
  glossEn: string
  cefrLevel: string
  exampleDe: string
  exampleEn: string
  practiceDe: string
  practiceEn: string
  sortOrder: number
  tags: string[]
  progress: {
    learned: boolean
    cardId: string | null
    reps: number
    lapses: number
    state: number | null
    due: string | null
    lastReview: string | null
  }
}

const toWordListItem = (row: {
  word: typeof words.$inferSelect
  cardId: string | null
  reps: number | null
  lapses: number | null
  state: number | null
  due: Date | null
  lastReview: Date | null
}): WordListItem => {
  const reps = row.reps ?? 0
  const practice = practiceSentence({
    lemma: row.word.lemma,
    gender: row.word.gender,
    plural: row.word.plural,
    glossEn: row.word.glossEn,
    tags: row.word.tags,
    sortOrder: row.word.sortOrder,
    exampleDe: row.word.exampleDe,
    exampleEn: row.word.exampleEn,
  })

  return {
    id: row.word.id,
    lemma: row.word.lemma,
    gender: row.word.gender,
    plural: row.word.plural,
    glossEn: row.word.glossEn,
    cefrLevel: row.word.cefrLevel,
    exampleDe: row.word.exampleDe,
    exampleEn: row.word.exampleEn,
    practiceDe: practice.de,
    practiceEn: practice.en,
    sortOrder: row.word.sortOrder,
    tags: row.word.tags,
    progress: {
      learned: reps > 0,
      cardId: row.cardId ?? null,
      reps,
      lapses: row.lapses ?? 0,
      state: row.state ?? null,
      due: row.due?.toISOString() ?? null,
      lastReview: row.lastReview?.toISOString() ?? null,
    },
  }
}

/**
 * Lists curriculum words with optional filters and per-user progress.
 */
export const listWords = async (query: WordListQuery) => {
  const page = Math.max(1, query.page)
  const limit = Math.min(100, Math.max(1, query.limit))
  const offset = (page - 1) * limit

  const filters: SQL[] = []

  if (query.search?.trim()) {
    const term = `%${query.search.trim()}%`
    filters.push(
      or(
        ilike(words.lemma, term),
        ilike(words.glossEn, term),
        ilike(words.exampleDe, term),
      )!,
    )
  }

  if (query.cefrLevel) {
    filters.push(eq(words.cefrLevel, query.cefrLevel.toUpperCase()))
  }

  if (query.gender) {
    filters.push(eq(words.gender, query.gender.toLowerCase()))
  }

  if (query.status === 'learned') {
    filters.push(sql`${cards.reps} > 0`)
  } else if (query.status === 'new') {
    filters.push(or(isNull(cards.id), sql`${cards.reps} = 0`)!)
  }

  const whereClause = filters.length > 0 ? and(...filters) : undefined

  const [totalRow] = await db
    .select({ value: count() })
    .from(words)
    .leftJoin(cards, and(eq(cards.wordId, words.id), eq(cards.userId, query.user.id)))
    .where(whereClause)

  const rows = await db
    .select({
      word: words,
      cardId: cards.id,
      reps: cards.reps,
      lapses: cards.lapses,
      state: cards.state,
      due: cards.due,
      lastReview: cards.lastReview,
    })
    .from(words)
    .leftJoin(cards, and(eq(cards.wordId, words.id), eq(cards.userId, query.user.id)))
    .where(whereClause)
    .orderBy(asc(words.sortOrder))
    .limit(limit)
    .offset(offset)

  const items: WordListItem[] = rows.map((row) => toWordListItem(row))

  const total = totalRow?.value ?? 0

  return {
    items,
    page,
    limit,
    total,
    hasMore: offset + items.length < total,
  }
}

/**
 * Returns one word with the current user's progress.
 */
export const getWordById = async (user: UserProfile, wordId: string) => {
  const [row] = await db
    .select({
      word: words,
      cardId: cards.id,
      reps: cards.reps,
      lapses: cards.lapses,
      state: cards.state,
      due: cards.due,
      lastReview: cards.lastReview,
    })
    .from(words)
    .leftJoin(cards, and(eq(cards.wordId, words.id), eq(cards.userId, user.id)))
    .where(eq(words.id, wordId))
    .limit(1)

  if (!row) {
    return null
  }

  return toWordListItem(row)
}

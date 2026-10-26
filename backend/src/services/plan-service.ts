import { and, asc, desc, eq, gte, isNull, lte } from 'drizzle-orm'
import { db } from '../db/client.js'
import {
  DEFAULT_STUDY_FILTERS,
  cards,
  dailyPlans,
  reviewLogs,
  words,
  type UserProfile,
} from '../db/schema.js'
import { formatDateInTimezone } from '../lib/dates.js'
import { newFsrsCard } from './fsrs-service.js'
import { cardRecallsWord, practiceSentence } from './practice-sentence.js'
import {
  filterNote,
  normalizeStudyFilters,
  wordMatchesStudyFilters,
} from './study-filters.js'

/** Above this many due reviews, new words pause for the day. */
const REVIEW_HEAVY = 40
/** Above this many due reviews, new words are capped at a small number. */
const REVIEW_BUSY = 25
const BUSY_NEW_CAP = 3

export type StudyItem = {
  cardId: string
  wordId: string
  lemma: string
  gender: string | null
  plural: string | null
  glossEn: string
  cefrLevel: string
  exampleDe: string
  exampleEn: string
  practiceDe: string
  practiceEn: string
  blankDe: string
  blankAnswer: string
  /** Young cards write the word from English. Mature cards skip to the blank. */
  recallWord: boolean
  /** Same value as recallWord, kept so older clients still decode the plan. */
  writesSentence: boolean
  kind: 'review' | 'new'
  due: string
}

export type DailyGoal = {
  completed: number
  remaining: number
  total: number
  met: boolean
}

export type TodayPlan = {
  planDate: string
  /** Effective new-word slots after review-pressure pacing. */
  newLimit: number
  /** The learner's Settings value, before pacing. */
  settingsNewLimit: number
  reviewDue: number
  newRemaining: number
  queue: StudyItem[]
  streak: number
  studiedToday: boolean
  dailyGoal: DailyGoal
  /** Null when pacing did not change the new-word limit. */
  pacingNote: string | null
  /** Null when no study filters are active. */
  filterNote: string | null
}

type PlanWord = {
  id: string
  lemma: string
  gender: string | null
  plural: string | null
  glossEn: string
  cefrLevel: string
  exampleDe: string
  exampleEn: string
  sortOrder: number
  tags: string[]
}

type PlanCard = {
  id: string
  state: number
  scheduledDays: number
  due: Date
}

const toStudyItem = (word: PlanWord, card: PlanCard, kind: 'review' | 'new'): StudyItem => {
  const practice = practiceSentence({
    lemma: word.lemma,
    gender: word.gender,
    plural: word.plural,
    glossEn: word.glossEn,
    tags: word.tags,
    sortOrder: word.sortOrder,
    exampleDe: word.exampleDe,
    exampleEn: word.exampleEn,
  })

  return {
    cardId: card.id,
    wordId: word.id,
    lemma: word.lemma,
    gender: word.gender,
    plural: word.plural,
    glossEn: word.glossEn,
    cefrLevel: word.cefrLevel,
    exampleDe: word.exampleDe,
    exampleEn: word.exampleEn,
    practiceDe: practice.de,
    practiceEn: practice.en,
    blankDe: practice.blankDe,
    blankAnswer: practice.blankAnswer,
    recallWord: cardRecallsWord(card.state, card.scheduledDays),
    writesSentence: cardRecallsWord(card.state, card.scheduledDays),
    kind,
    due: card.due.toISOString(),
  }
}

/**
 * Shrinks or pauses new words when the review pile is large.
 */
export const pacedNewLimit = (
  settingsLimit: number,
  reviewDue: number,
): { limit: number; note: string | null } => {
  if (reviewDue >= REVIEW_HEAVY) {
    return {
      limit: 0,
      note: 'Reviews are heavy today. New words pause until the pile shrinks.',
    }
  }
  if (reviewDue >= REVIEW_BUSY) {
    const limit = Math.min(settingsLimit, BUSY_NEW_CAP)
    if (limit < settingsLimit) {
      return {
        limit,
        note: `Reviews are busy. New words are capped at ${limit} today.`,
      }
    }
  }
  return { limit: settingsLimit, note: null }
}

/**
 * Builds today's study queue: due reviews first, then new words.
 */
export const getTodayPlan = async (user: UserProfile): Promise<TodayPlan> => {
  const now = new Date()
  const planDate = formatDateInTimezone(now, user.timezone)
  const filters = normalizeStudyFilters(user.studyFilters ?? DEFAULT_STUDY_FILTERS)

  const dueCardRows = await db
    .select({
      card: cards,
      word: words,
    })
    .from(cards)
    .innerJoin(words, eq(cards.wordId, words.id))
    .where(and(eq(cards.userId, user.id), lte(cards.due, now)))
    .orderBy(asc(cards.due))
    .limit(400)

  const dueCards = dueCardRows.filter(({ word }) => wordMatchesStudyFilters(word, filters))

  const [planRow] = await db
    .select()
    .from(dailyPlans)
    .where(and(eq(dailyPlans.userId, user.id), eq(dailyPlans.planDate, planDate)))
    .limit(1)

  const alreadyIntroducedToday = planRow?.newCount ?? 0
  const paced = pacedNewLimit(user.dailyNewLimit, dueCards.length)
  const newSlots = Math.max(0, paced.limit - alreadyIntroducedToday)

  const newWordRows =
    newSlots === 0
      ? []
      : await db
          .select({ word: words })
          .from(words)
          .leftJoin(cards, and(eq(cards.wordId, words.id), eq(cards.userId, user.id)))
          .where(isNull(cards.id))
          .orderBy(asc(words.sortOrder))
          .limit(Math.max(newSlots * 8, 40))

  const newWords = newWordRows
    .map((row) => row.word)
    .filter((word) => wordMatchesStudyFilters(word, filters))
    .slice(0, newSlots)

  const reviewItems: StudyItem[] = dueCards
    .slice(0, 200)
    .map(({ card, word }) => toStudyItem(word, card, 'review'))

  const newItems: StudyItem[] = []
  for (const word of newWords) {
    const empty = newFsrsCard(now)
    const [created] = await db
      .insert(cards)
      .values({
        userId: user.id,
        wordId: word.id,
        state: empty.state,
        due: empty.due,
        stability: String(empty.stability),
        difficulty: String(empty.difficulty),
        elapsedDays: empty.elapsed_days,
        scheduledDays: empty.scheduled_days,
        learningSteps: empty.learning_steps,
        reps: empty.reps,
        lapses: empty.lapses,
        lastReview: empty.last_review ?? null,
      })
      .onConflictDoNothing()
      .returning()

    const card =
      created ??
      (await db.query.cards.findFirst({
        where: and(eq(cards.userId, user.id), eq(cards.wordId, word.id)),
      }))

    if (!card) {
      continue
    }

    newItems.push(toStudyItem(word, card, 'new'))
  }

  const introducedTotal = alreadyIntroducedToday + newItems.length
  const completedNew = planRow?.completedNew ?? 0
  const completedReview = planRow?.completedReview ?? 0
  const queue = [...reviewItems, ...newItems]
  const completedToday = completedNew + completedReview
  const remaining = queue.length
  const total = completedToday + remaining

  await db
    .insert(dailyPlans)
    .values({
      userId: user.id,
      planDate,
      newCount: introducedTotal,
      reviewCount: reviewItems.length,
      completedNew,
      completedReview,
    })
    .onConflictDoUpdate({
      target: [dailyPlans.userId, dailyPlans.planDate],
      set: {
        newCount: introducedTotal,
        reviewCount: reviewItems.length,
      },
    })

  return {
    planDate,
    newLimit: paced.limit,
    settingsNewLimit: user.dailyNewLimit,
    reviewDue: reviewItems.length,
    newRemaining: Math.max(0, introducedTotal - completedNew),
    queue,
    streak: user.streak,
    studiedToday: user.lastStudyDate === planDate,
    dailyGoal: {
      completed: completedToday,
      remaining,
      total,
      met: remaining === 0,
    },
    pacingNote: paced.note,
    filterNote: filterNote(filters),
  }
}

/**
 * Cards the learner marked Again earlier today, for a short mistake pass.
 */
export const getMistakeQueue = async (
  user: UserProfile,
): Promise<{ planDate: string; queue: StudyItem[] }> => {
  const now = new Date()
  const planDate = formatDateInTimezone(now, user.timezone)
  const lookback = new Date(now.getTime() - 40 * 60 * 60 * 1000)

  const rows = await db
    .select({
      card: cards,
      word: words,
      reviewedAt: reviewLogs.review,
    })
    .from(reviewLogs)
    .innerJoin(cards, eq(reviewLogs.cardId, cards.id))
    .innerJoin(words, eq(cards.wordId, words.id))
    .where(
      and(
        eq(reviewLogs.userId, user.id),
        eq(reviewLogs.rating, 1),
        gte(reviewLogs.review, lookback),
      ),
    )
    .orderBy(desc(reviewLogs.review))
    .limit(100)

  const seen = new Set<string>()
  const queue: StudyItem[] = []
  for (const row of rows) {
    if (formatDateInTimezone(row.reviewedAt, user.timezone) !== planDate) continue
    if (seen.has(row.card.id)) continue
    seen.add(row.card.id)
    queue.push(toStudyItem(row.word, row.card, 'review'))
    if (queue.length >= 20) break
  }

  return { planDate, queue }
}

import { and, asc, eq, isNull, lte } from 'drizzle-orm'
import { db } from '../db/client.js'
import { cards, dailyPlans, words, type UserProfile } from '../db/schema.js'
import { formatDateInTimezone } from '../lib/dates.js'
import { newFsrsCard } from './fsrs-service.js'

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
  kind: 'review' | 'new'
  due: string
}

export type TodayPlan = {
  planDate: string
  newLimit: number
  reviewDue: number
  newRemaining: number
  queue: StudyItem[]
  streak: number
  studiedToday: boolean
}

/**
 * Builds today's study queue: due reviews first, then new words.
 */
export const getTodayPlan = async (user: UserProfile): Promise<TodayPlan> => {
  const now = new Date()
  const planDate = formatDateInTimezone(now, user.timezone)

  const dueCards = await db
    .select({
      card: cards,
      word: words,
    })
    .from(cards)
    .innerJoin(words, eq(cards.wordId, words.id))
    .where(and(eq(cards.userId, user.id), lte(cards.due, now)))
    .orderBy(asc(cards.due))
    .limit(200)

  const [planRow] = await db
    .select()
    .from(dailyPlans)
    .where(and(eq(dailyPlans.userId, user.id), eq(dailyPlans.planDate, planDate)))
    .limit(1)

  const alreadyIntroducedToday = planRow?.newCount ?? 0
  const newSlots = Math.max(0, user.dailyNewLimit - alreadyIntroducedToday)

  const newWordRows =
    newSlots === 0
      ? []
      : await db
          .select({ word: words })
          .from(words)
          .leftJoin(cards, and(eq(cards.wordId, words.id), eq(cards.userId, user.id)))
          .where(isNull(cards.id))
          .orderBy(asc(words.sortOrder))
          .limit(newSlots)

  const newWords = newWordRows.map((row) => row.word)

  const reviewItems: StudyItem[] = dueCards.map(({ card, word }) => ({
    cardId: card.id,
    wordId: word.id,
    lemma: word.lemma,
    gender: word.gender,
    plural: word.plural,
    glossEn: word.glossEn,
    cefrLevel: word.cefrLevel,
    exampleDe: word.exampleDe,
    exampleEn: word.exampleEn,
    kind: 'review',
    due: card.due.toISOString(),
  }))

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

    newItems.push({
      cardId: card.id,
      wordId: word.id,
      lemma: word.lemma,
      gender: word.gender,
      plural: word.plural,
      glossEn: word.glossEn,
      cefrLevel: word.cefrLevel,
      exampleDe: word.exampleDe,
      exampleEn: word.exampleEn,
      kind: 'new',
      due: card.due.toISOString(),
    })
  }

  const introducedTotal = alreadyIntroducedToday + newItems.length

  await db
    .insert(dailyPlans)
    .values({
      userId: user.id,
      planDate,
      newCount: introducedTotal,
      reviewCount: reviewItems.length,
      completedNew: planRow?.completedNew ?? 0,
      completedReview: planRow?.completedReview ?? 0,
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
    newLimit: user.dailyNewLimit,
    reviewDue: reviewItems.length,
    newRemaining: Math.max(0, introducedTotal - (planRow?.completedNew ?? 0)),
    queue: [...reviewItems, ...newItems],
    streak: user.streak,
    studiedToday: user.lastStudyDate === planDate,
  }
}

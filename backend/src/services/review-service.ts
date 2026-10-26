import { and, eq, sql } from 'drizzle-orm'
import { db } from '../db/client.js'
import { cards, dailyPlans, reviewLogs, userProfiles, type UserProfile } from '../db/schema.js'
import { AppError } from '../lib/errors.js'
import { formatDateInTimezone } from '../lib/dates.js'
import {
  ratingFromNumber,
  scheduleReview,
  toFsrsCard,
} from './fsrs-service.js'

type SubmitReviewInput = {
  user: UserProfile
  cardId: string
  rating: number
  durationMs?: number
  clientRequestId?: string
}

type ReviewResult = {
  cardId: string
  due: string
  state: number
  reps: number
  streak: number
}

/**
 * Applies an FSRS rating to a card and updates streak / daily plan counters.
 * The same `clientRequestId` returns the earlier result without grading again.
 */
export const submitReview = async (input: SubmitReviewInput): Promise<ReviewResult> => {
  if (input.clientRequestId) {
    const existing = await db.query.reviewLogs.findFirst({
      where: and(
        eq(reviewLogs.userId, input.user.id),
        eq(reviewLogs.clientRequestId, input.clientRequestId),
      ),
    })
    if (existing) {
      return snapshotForCard(input.user, existing.cardId)
    }
  }

  const card = await db.query.cards.findFirst({
    where: and(eq(cards.id, input.cardId), eq(cards.userId, input.user.id)),
    with: undefined,
  })

  if (!card) {
    throw new AppError(404, 'CARD_NOT_FOUND', 'Card not found')
  }

  const wasNew = card.reps === 0
  const rating = ratingFromNumber(input.rating)
  const now = new Date()
  const result = scheduleReview(toFsrsCard(card), rating, now)
  const next = result.card
  const log = result.log

  const [updated] = await db
    .update(cards)
    .set({
      state: next.state,
      due: next.due,
      stability: String(next.stability),
      difficulty: String(next.difficulty),
      elapsedDays: next.elapsed_days,
      scheduledDays: next.scheduled_days,
      learningSteps: next.learning_steps,
      reps: next.reps,
      lapses: next.lapses,
      lastReview: next.last_review ?? now,
      updatedAt: now,
    })
    .where(eq(cards.id, card.id))
    .returning()

  try {
    await db.insert(reviewLogs).values({
      cardId: card.id,
      userId: input.user.id,
      rating: log.rating,
      state: log.state,
      due: log.due,
      stability: String(log.stability),
      difficulty: String(log.difficulty),
      elapsedDays: log.elapsed_days,
      lastElapsedDays: log.last_elapsed_days,
      scheduledDays: log.scheduled_days,
      learningSteps: log.learning_steps,
      review: log.review,
      durationMs: input.durationMs ?? null,
      clientRequestId: input.clientRequestId ?? null,
    })
  } catch (error) {
    // A concurrent offline retry won the unique clientRequestId race.
    if (input.clientRequestId) {
      return snapshotForCard(input.user, input.cardId)
    }
    throw error
  }

  const planDate = formatDateInTimezone(now, input.user.timezone)
  const lastStudy = input.user.lastStudyDate
  let streak = input.user.streak

  if (lastStudy !== planDate) {
    const yesterday = new Date(now)
    yesterday.setDate(yesterday.getDate() - 1)
    const yesterdayStr = formatDateInTimezone(yesterday, input.user.timezone)
    streak = lastStudy === yesterdayStr ? streak + 1 : 1

    await db
      .update(userProfiles)
      .set({
        streak,
        lastStudyDate: planDate,
        updatedAt: now,
      })
      .where(eq(userProfiles.id, input.user.id))
  }

  await db
    .insert(dailyPlans)
    .values({
      userId: input.user.id,
      planDate,
      newCount: wasNew ? 1 : 0,
      reviewCount: wasNew ? 0 : 1,
      completedNew: wasNew ? 1 : 0,
      completedReview: wasNew ? 0 : 1,
    })
    .onConflictDoUpdate({
      target: [dailyPlans.userId, dailyPlans.planDate],
      set: {
        completedNew: wasNew
          ? sql`${dailyPlans.completedNew} + 1`
          : dailyPlans.completedNew,
        completedReview: wasNew
          ? dailyPlans.completedReview
          : sql`${dailyPlans.completedReview} + 1`,
      },
    })

  return {
    cardId: updated?.id ?? card.id,
    due: (updated?.due ?? next.due).toISOString(),
    state: updated?.state ?? next.state,
    reps: updated?.reps ?? next.reps,
    streak,
  }
}

const snapshotForCard = async (user: UserProfile, cardId: string): Promise<ReviewResult> => {
  const card = await db.query.cards.findFirst({
    where: and(eq(cards.id, cardId), eq(cards.userId, user.id)),
  })
  if (!card) {
    throw new AppError(404, 'CARD_NOT_FOUND', 'Card not found')
  }
  return {
    cardId: card.id,
    due: card.due.toISOString(),
    state: card.state,
    reps: card.reps,
    streak: user.streak,
  }
}

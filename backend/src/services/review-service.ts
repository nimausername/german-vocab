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
}

/**
 * Applies an FSRS rating to a card and updates streak / daily plan counters.
 */
export const submitReview = async (input: SubmitReviewInput) => {
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
  })

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

import { and, count, eq, gte, sql } from 'drizzle-orm'
import { db } from '../db/client.js'
import { cards, reviewLogs, words, type UserProfile } from '../db/schema.js'
import { State } from './fsrs-service.js'

/**
 * Aggregates learning progress for the authenticated user.
 */
export const getUserStats = async (user: UserProfile) => {
  const [learned] = await db
    .select({ value: count() })
    .from(cards)
    .where(and(eq(cards.userId, user.id), sql`${cards.reps} > 0`))

  const [totalWords] = await db.select({ value: count() }).from(words)

  const [dueSoon] = await db
    .select({ value: count() })
    .from(cards)
    .where(
      and(
        eq(cards.userId, user.id),
        gte(cards.due, new Date()),
        sql`${cards.due} < now() + interval '7 days'`,
      ),
    )

  const dayStart = new Date()
  dayStart.setHours(0, 0, 0, 0)

  const [reviewsToday] = await db
    .select({ value: count() })
    .from(reviewLogs)
    .where(and(eq(reviewLogs.userId, user.id), gte(reviewLogs.review, dayStart)))

  const [mature] = await db
    .select({ value: count() })
    .from(cards)
    .where(
      and(
        eq(cards.userId, user.id),
        eq(cards.state, State.Review),
        sql`${cards.scheduledDays} >= 21`,
      ),
    )

  return {
    displayName: user.displayName,
    streak: user.streak,
    dailyNewLimit: user.dailyNewLimit,
    wordsLearned: learned?.value ?? 0,
    wordsTotal: totalWords?.value ?? 0,
    reviewsDueNext7Days: dueSoon?.value ?? 0,
    reviewsToday: reviewsToday?.value ?? 0,
    matureCards: mature?.value ?? 0,
  }
}

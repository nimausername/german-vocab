import {
  Rating,
  State,
  createEmptyCard,
  fsrs,
  type Card as FsrsCard,
  type Grade,
} from 'ts-fsrs'
import type { CardRow } from '../db/schema.js'

const scheduler = fsrs({
  request_retention: 0.9,
  maximum_interval: 365,
  enable_fuzz: true,
})

export const ratingFromNumber = (value: number): Rating => {
  switch (value) {
    case Rating.Again:
      return Rating.Again
    case Rating.Hard:
      return Rating.Hard
    case Rating.Good:
      return Rating.Good
    case Rating.Easy:
      return Rating.Easy
    default:
      throw new Error(`Invalid rating: ${value}`)
  }
}

/**
 * Maps a DB card row into a ts-fsrs Card.
 */
export const toFsrsCard = (row: CardRow): FsrsCard => {
  return {
    due: row.due,
    stability: Number(row.stability),
    difficulty: Number(row.difficulty),
    elapsed_days: row.elapsedDays,
    scheduled_days: row.scheduledDays,
    learning_steps: row.learningSteps,
    reps: row.reps,
    lapses: row.lapses,
    state: row.state as State,
    last_review: row.lastReview ?? undefined,
  }
}

/**
 * Creates an empty FSRS card for first introduction.
 */
export const newFsrsCard = (now = new Date()): FsrsCard => createEmptyCard(now)

/**
 * Applies a rating and returns the next card + review log.
 */
export const scheduleReview = (card: FsrsCard, rating: Rating, now = new Date()) => {
  return scheduler.next(card, now, rating as Grade)
}

export { Rating, State }

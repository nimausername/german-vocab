import {
  integer,
  jsonb,
  numeric,
  pgTable,
  text,
  timestamp,
  unique,
  uuid,
  varchar,
} from 'drizzle-orm/pg-core'

/**
 * Curriculum word entry.
 */
export const words = pgTable(
  'words',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    lemma: varchar('lemma', { length: 128 }).notNull(),
    gender: varchar('gender', { length: 16 }),
    plural: varchar('plural', { length: 128 }),
    glossEn: varchar('gloss_en', { length: 256 }).notNull(),
    cefrLevel: varchar('cefr_level', { length: 8 }).notNull(),
    exampleDe: text('example_de').notNull(),
    exampleEn: text('example_en').notNull(),
    sortOrder: integer('sort_order').notNull(),
    tags: jsonb('tags').$type<string[]>().notNull().default([]),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [unique('words_lemma_uidx').on(table.lemma)],
)

/** New accounts introduce this many words per day until the learner changes it. */
export const DEFAULT_DAILY_NEW_LIMIT = 8

/** Filters applied when building today's study queue. */
export type StudyFilters = {
  /** Empty means every CEFR band. */
  cefrLevels: string[]
  /** When true, only words with a gender (nouns) are studied. */
  nounsOnly: boolean
  /** Empty means every tag. Otherwise the word must include at least one. */
  tags: string[]
}

export const DEFAULT_STUDY_FILTERS: StudyFilters = {
  cefrLevels: [],
  nounsOnly: false,
  tags: [],
}

/**
 * App user mapped from Keycloak subject.
 */
export const userProfiles = pgTable(
  'user_profiles',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    keycloakSub: varchar('keycloak_sub', { length: 64 }).notNull(),
    email: varchar('email', { length: 256 }),
    displayName: varchar('display_name', { length: 128 }),
    dailyNewLimit: integer('daily_new_limit').notNull().default(DEFAULT_DAILY_NEW_LIMIT),
    studyFilters: jsonb('study_filters')
      .$type<StudyFilters>()
      .notNull()
      .default(DEFAULT_STUDY_FILTERS),
    timezone: varchar('timezone', { length: 64 }).notNull().default('Europe/Berlin'),
    streak: integer('streak').notNull().default(0),
    lastStudyDate: varchar('last_study_date', { length: 10 }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [unique('user_profiles_keycloak_sub_uidx').on(table.keycloakSub)],
)

/**
 * Per-user FSRS card state for a word.
 */
export const cards = pgTable(
  'cards',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    userId: uuid('user_id')
      .notNull()
      .references(() => userProfiles.id, { onDelete: 'cascade' }),
    wordId: uuid('word_id')
      .notNull()
      .references(() => words.id, { onDelete: 'cascade' }),
    state: integer('state').notNull().default(0),
    due: timestamp('due', { withTimezone: true }).notNull(),
    stability: numeric('stability', { precision: 12, scale: 6 }).notNull().default('0'),
    difficulty: numeric('difficulty', { precision: 12, scale: 6 }).notNull().default('0'),
    elapsedDays: integer('elapsed_days').notNull().default(0),
    scheduledDays: integer('scheduled_days').notNull().default(0),
    learningSteps: integer('learning_steps').notNull().default(0),
    reps: integer('reps').notNull().default(0),
    lapses: integer('lapses').notNull().default(0),
    lastReview: timestamp('last_review', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [unique('cards_user_word_uidx').on(table.userId, table.wordId)],
)

/**
 * Immutable review history for analytics.
 */
export const reviewLogs = pgTable(
  'review_logs',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    cardId: uuid('card_id')
      .notNull()
      .references(() => cards.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => userProfiles.id, { onDelete: 'cascade' }),
    rating: integer('rating').notNull(),
    state: integer('state').notNull(),
    due: timestamp('due', { withTimezone: true }).notNull(),
    stability: numeric('stability', { precision: 12, scale: 6 }).notNull(),
    difficulty: numeric('difficulty', { precision: 12, scale: 6 }).notNull(),
    elapsedDays: integer('elapsed_days').notNull(),
    lastElapsedDays: integer('last_elapsed_days').notNull(),
    scheduledDays: integer('scheduled_days').notNull(),
    learningSteps: integer('learning_steps').notNull().default(0),
    review: timestamp('review', { withTimezone: true }).notNull(),
    durationMs: integer('duration_ms'),
    /** Client id so offline retries do not grade the same answer twice. */
    clientRequestId: varchar('client_request_id', { length: 64 }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [unique('review_logs_user_client_uidx').on(table.userId, table.clientRequestId)],
)

/**
 * Daily plan snapshot for the user.
 */
export const dailyPlans = pgTable(
  'daily_plans',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    userId: uuid('user_id')
      .notNull()
      .references(() => userProfiles.id, { onDelete: 'cascade' }),
    planDate: varchar('plan_date', { length: 10 }).notNull(),
    newCount: integer('new_count').notNull().default(0),
    reviewCount: integer('review_count').notNull().default(0),
    completedNew: integer('completed_new').notNull().default(0),
    completedReview: integer('completed_review').notNull().default(0),
    completedAt: timestamp('completed_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [unique('daily_plans_user_date_uidx').on(table.userId, table.planDate)],
)

export type Word = typeof words.$inferSelect
export type UserProfile = typeof userProfiles.$inferSelect
export type CardRow = typeof cards.$inferSelect

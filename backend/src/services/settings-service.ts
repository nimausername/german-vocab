import { eq } from 'drizzle-orm'
import { db } from '../db/client.js'
import {
  DEFAULT_STUDY_FILTERS,
  userProfiles,
  type StudyFilters,
  type UserProfile,
} from '../db/schema.js'
import { AppError } from '../lib/errors.js'
import { updateKeycloakNames } from './keycloak-admin.js'
import { normalizeStudyFilters } from './study-filters.js'

export type UserSettings = {
  dailyNewLimit: number
  displayName: string | null
  firstName: string | null
  lastName: string | null
  studyFilters: StudyFilters
}

const splitDisplayName = (
  displayName: string | null,
): { firstName: string | null; lastName: string | null } => {
  if (!displayName?.trim()) {
    return { firstName: null, lastName: null }
  }
  const parts = displayName.trim().split(/\s+/)
  if (parts.length === 1) {
    return { firstName: parts[0]!, lastName: null }
  }
  return {
    firstName: parts[0]!,
    lastName: parts.slice(1).join(' '),
  }
}

const toSettings = (user: UserProfile): UserSettings => {
  const names = splitDisplayName(user.displayName)
  return {
    dailyNewLimit: user.dailyNewLimit,
    displayName: user.displayName,
    firstName: names.firstName,
    lastName: names.lastName,
    studyFilters: normalizeStudyFilters(user.studyFilters ?? DEFAULT_STUDY_FILTERS),
  }
}

/**
 * Returns the learner's editable settings.
 */
export const getUserSettings = async (user: UserProfile): Promise<UserSettings> => toSettings(user)

/**
 * Updates how many new words the daily plan may introduce.
 */
export const updateDailyNewLimit = async (
  user: UserProfile,
  dailyNewLimit: number,
): Promise<UserSettings> => {
  const [updated] = await db
    .update(userProfiles)
    .set({
      dailyNewLimit,
      updatedAt: new Date(),
    })
    .where(eq(userProfiles.id, user.id))
    .returning()

  if (!updated) {
    throw new AppError(404, 'USER_NOT_FOUND', 'User profile not found')
  }

  return toSettings(updated)
}

/**
 * Updates study filters that shape today's plan.
 */
export const updateStudyFilters = async (
  user: UserProfile,
  filters: StudyFilters,
): Promise<UserSettings> => {
  const studyFilters = normalizeStudyFilters(filters)
  const [updated] = await db
    .update(userProfiles)
    .set({
      studyFilters,
      updatedAt: new Date(),
    })
    .where(eq(userProfiles.id, user.id))
    .returning()

  if (!updated) {
    throw new AppError(404, 'USER_NOT_FOUND', 'User profile not found')
  }

  return toSettings(updated)
}

/**
 * Updates first and last name in Keycloak and the local profile.
 */
export const updateDisplayName = async (
  user: UserProfile,
  firstName: string,
  lastName: string,
): Promise<UserSettings> => {
  await updateKeycloakNames(user.keycloakSub, { firstName, lastName })
  const displayName = `${firstName} ${lastName}`.trim()
  const [updated] = await db
    .update(userProfiles)
    .set({
      displayName,
      updatedAt: new Date(),
    })
    .where(eq(userProfiles.id, user.id))
    .returning()

  if (!updated) {
    throw new AppError(404, 'USER_NOT_FOUND', 'User profile not found')
  }

  return toSettings(updated)
}

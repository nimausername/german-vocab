import { eq } from 'drizzle-orm'
import { db } from '../db/client.js'
import { DEFAULT_DAILY_NEW_LIMIT, userProfiles, type UserProfile } from '../db/schema.js'

type EnsureUserInput = {
  keycloakSub: string
  email: string | null
  displayName: string | null
}

/**
 * Finds or creates a local profile for a Keycloak subject.
 */
export const ensureUserProfile = async (
  input: EnsureUserInput,
): Promise<UserProfile> => {
  const existing = await db.query.userProfiles.findFirst({
    where: eq(userProfiles.keycloakSub, input.keycloakSub),
  })

  if (existing) {
    // Keep a Settings-edited display name; only fill from the token when empty.
    const nextDisplayName = existing.displayName ?? input.displayName
    if (existing.email !== input.email || existing.displayName !== nextDisplayName) {
      const [updated] = await db
        .update(userProfiles)
        .set({
          email: input.email,
          displayName: nextDisplayName,
          updatedAt: new Date(),
        })
        .where(eq(userProfiles.id, existing.id))
        .returning()
      return updated ?? existing
    }
    return existing
  }

  const [created] = await db
    .insert(userProfiles)
    .values({
      keycloakSub: input.keycloakSub,
      email: input.email,
      displayName: input.displayName,
      dailyNewLimit: DEFAULT_DAILY_NEW_LIMIT,
    })
    .returning()

  if (!created) {
    throw new Error('Failed to create user profile')
  }

  return created
}

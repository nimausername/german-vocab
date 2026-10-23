import { eq } from 'drizzle-orm'
import { db } from '../db/client.js'
import { userProfiles, type UserProfile } from '../db/schema.js'

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
    if (
      existing.email !== input.email ||
      existing.displayName !== input.displayName
    ) {
      const [updated] = await db
        .update(userProfiles)
        .set({
          email: input.email,
          displayName: input.displayName,
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
    })
    .returning()

  if (!created) {
    throw new Error('Failed to create user profile')
  }

  return created
}

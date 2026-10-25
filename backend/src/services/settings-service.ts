import { eq } from 'drizzle-orm'
import { db } from '../db/client.js'
import { userProfiles, type UserProfile } from '../db/schema.js'
import { AppError } from '../lib/errors.js'

/**
 * Updates how many new words the daily plan may introduce.
 */
export const updateDailyNewLimit = async (
  user: UserProfile,
  dailyNewLimit: number,
): Promise<{ dailyNewLimit: number }> => {
  const [updated] = await db
    .update(userProfiles)
    .set({
      dailyNewLimit,
      updatedAt: new Date(),
    })
    .where(eq(userProfiles.id, user.id))
    .returning({ dailyNewLimit: userProfiles.dailyNewLimit })

  if (!updated) {
    throw new AppError(404, 'USER_NOT_FOUND', 'User profile not found')
  }

  return updated
}

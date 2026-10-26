import { Hono } from 'hono'
import { z } from 'zod'
import type { AuthVariables } from '../middleware/auth.js'
import { requireAuth } from '../middleware/auth.js'
import {
  getUserSettings,
  updateDailyNewLimit,
  updateDisplayName,
  updateStudyFilters,
} from '../services/settings-service.js'

const namePart = z
  .string()
  .trim()
  .min(1, 'Required')
  .max(64)
  .regex(/^[\p{L}\p{M}'' -]+$/u, 'Use letters, spaces, hyphens, or apostrophes')

const settingsSchema = z
  .object({
    dailyNewLimit: z.number().int().min(1).max(50).optional(),
    firstName: namePart.optional(),
    lastName: namePart.optional(),
    studyFilters: z
      .object({
        cefrLevels: z.array(z.string().trim().min(1).max(8)).max(8).optional(),
        nounsOnly: z.boolean().optional(),
        tags: z.array(z.string().trim().min(1).max(32)).max(20).optional(),
      })
      .optional(),
  })
  .refine(
    (body) =>
      body.dailyNewLimit !== undefined ||
      body.firstName !== undefined ||
      body.lastName !== undefined ||
      body.studyFilters !== undefined,
    { message: 'Provide at least one setting to update' },
  )
  .refine(
    (body) =>
      (body.firstName === undefined && body.lastName === undefined) ||
      (body.firstName !== undefined && body.lastName !== undefined),
    { message: 'Provide both firstName and lastName together' },
  )

export const settingsRoutes = new Hono<{ Variables: AuthVariables }>()

settingsRoutes.use('*', requireAuth)

settingsRoutes.get('/', async (c) => {
  const settings = await getUserSettings(c.get('user'))
  return c.json({
    data: settings,
    meta: { requestId: c.get('requestId') },
  })
})

settingsRoutes.patch('/', async (c) => {
  const body = settingsSchema.parse(await c.req.json())
  let user = c.get('user')
  let settings = await getUserSettings(user)

  if (body.dailyNewLimit !== undefined) {
    settings = await updateDailyNewLimit(user, body.dailyNewLimit)
    user = { ...user, dailyNewLimit: settings.dailyNewLimit }
  }

  if (body.studyFilters !== undefined) {
    settings = await updateStudyFilters(user, {
      cefrLevels: body.studyFilters.cefrLevels ?? settings.studyFilters.cefrLevels,
      nounsOnly: body.studyFilters.nounsOnly ?? settings.studyFilters.nounsOnly,
      tags: body.studyFilters.tags ?? settings.studyFilters.tags,
    })
    user = { ...user, studyFilters: settings.studyFilters }
  }

  if (body.firstName !== undefined && body.lastName !== undefined) {
    settings = await updateDisplayName(user, body.firstName, body.lastName)
  }

  return c.json({
    data: settings,
    meta: { requestId: c.get('requestId') },
  })
})

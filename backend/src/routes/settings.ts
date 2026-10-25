import { Hono } from 'hono'
import { z } from 'zod'
import type { AuthVariables } from '../middleware/auth.js'
import { requireAuth } from '../middleware/auth.js'
import { updateDailyNewLimit } from '../services/settings-service.js'

const settingsSchema = z.object({
  dailyNewLimit: z.number().int().min(1).max(50),
})

export const settingsRoutes = new Hono<{ Variables: AuthVariables }>()

settingsRoutes.use('*', requireAuth)

settingsRoutes.patch('/', async (c) => {
  const body = settingsSchema.parse(await c.req.json())
  const settings = await updateDailyNewLimit(c.get('user'), body.dailyNewLimit)

  return c.json({
    data: settings,
    meta: { requestId: c.get('requestId') },
  })
})

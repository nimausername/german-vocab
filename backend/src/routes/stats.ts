import { Hono } from 'hono'
import type { AuthVariables } from '../middleware/auth.js'
import { requireAuth } from '../middleware/auth.js'
import { getUserStats } from '../services/stats-service.js'

export const statsRoutes = new Hono<{ Variables: AuthVariables }>()

statsRoutes.use('*', requireAuth)

statsRoutes.get('/', async (c) => {
  const stats = await getUserStats(c.get('user'))

  return c.json({
    data: stats,
    meta: { requestId: c.get('requestId') },
  })
})

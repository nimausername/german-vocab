import { Hono } from 'hono'
import type { AuthVariables } from '../middleware/auth.js'
import { requireAuth } from '../middleware/auth.js'
import { getTodayPlan } from '../services/plan-service.js'

export const planRoutes = new Hono<{ Variables: AuthVariables }>()

planRoutes.use('*', requireAuth)

planRoutes.get('/today', async (c) => {
  const user = c.get('user')
  const plan = await getTodayPlan(user)

  return c.json({
    data: plan,
    meta: { requestId: c.get('requestId') },
  })
})

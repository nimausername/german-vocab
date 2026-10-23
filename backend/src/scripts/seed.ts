import { count } from 'drizzle-orm'
import { a1Words } from '../data/a1-words.js'
import { db, queryClient } from '../db/client.js'
import { words } from '../db/schema.js'

const main = async () => {
  const [existing] = await db.select({ value: count() }).from(words)
  if ((existing?.value ?? 0) > 0) {
    console.log(`Words already seeded (${existing?.value}). Skipping.`)
    await queryClient.end()
    return
  }

  await db.insert(words).values(
    a1Words.map((word, index) => ({
      lemma: word.lemma,
      gender: word.gender,
      plural: word.plural,
      glossEn: word.glossEn,
      cefrLevel: word.cefrLevel,
      exampleDe: word.exampleDe,
      exampleEn: word.exampleEn,
      sortOrder: index + 1,
      tags: word.tags,
    })),
  )

  console.log(`Seeded ${a1Words.length} A1 words.`)
  await queryClient.end()
}

main().catch(async (error) => {
  console.error(error)
  await queryClient.end()
  process.exit(1)
})

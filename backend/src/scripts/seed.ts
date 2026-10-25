import { eq } from 'drizzle-orm'
import { curriculum } from '../data/corpus.js'
import { db, queryClient } from '../db/client.js'
import { words } from '../db/schema.js'

const chunk = <T>(items: readonly T[], size: number): T[][] => {
  const batches: T[][] = []
  for (let index = 0; index < items.length; index += size) {
    batches.push(items.slice(index, index + size))
  }
  return batches
}

/**
 * Inserts missing curriculum words and refreshes fields for lemmas already stored.
 * Card progress stays attached, because rows are matched by lemma and ids are kept.
 */
const main = async () => {
  const existing = await db.select({ lemma: words.lemma }).from(words)
  const known = new Set(existing.map((row) => row.lemma))

  const rows = curriculum.map((word, index) => ({
    lemma: word.lemma,
    gender: word.gender,
    plural: word.plural,
    glossEn: word.glossEn,
    cefrLevel: word.cefrLevel,
    exampleDe: word.exampleDe,
    exampleEn: word.exampleEn,
    sortOrder: index + 1,
    tags: [...word.tags],
  }))

  const fresh = rows.filter((row) => !known.has(row.lemma))
  const current = rows.filter((row) => known.has(row.lemma))

  for (const batch of chunk(fresh, 200)) {
    await db.insert(words).values(batch)
  }

  for (const batch of chunk(current, 20)) {
    await Promise.all(
      batch.map((row) =>
        db
          .update(words)
          .set({
            gender: row.gender,
            plural: row.plural,
            glossEn: row.glossEn,
            cefrLevel: row.cefrLevel,
            exampleDe: row.exampleDe,
            exampleEn: row.exampleEn,
            sortOrder: row.sortOrder,
            tags: row.tags,
          })
          .where(eq(words.lemma, row.lemma)),
      ),
    )
  }

  console.log(
    `Curriculum synced: ${rows.length} words (${fresh.length} inserted, ${current.length} updated).`,
  )
  await queryClient.end()
}

main().catch(async (error: unknown) => {
  console.error(error)
  await queryClient.end()
  process.exit(1)
})

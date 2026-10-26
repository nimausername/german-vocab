import type { StudyFilters, Word } from '../db/schema.js'
import { DEFAULT_STUDY_FILTERS } from '../db/schema.js'

/**
 * Normalizes stored or request filters into a stable shape.
 */
export const normalizeStudyFilters = (
  value: Partial<StudyFilters> | null | undefined,
): StudyFilters => ({
  cefrLevels: Array.isArray(value?.cefrLevels)
    ? value.cefrLevels.map((level) => level.trim().toUpperCase()).filter(Boolean)
    : DEFAULT_STUDY_FILTERS.cefrLevels,
  nounsOnly: Boolean(value?.nounsOnly),
  tags: Array.isArray(value?.tags)
    ? value.tags.map((tag) => tag.trim().toLowerCase()).filter(Boolean)
    : DEFAULT_STUDY_FILTERS.tags,
})

/**
 * True when a curriculum word passes the learner's study filters.
 */
export const wordMatchesStudyFilters = (
  word: Pick<Word, 'cefrLevel' | 'gender' | 'tags'>,
  filters: StudyFilters,
): boolean => {
  const normalized = normalizeStudyFilters(filters)
  if (
    normalized.cefrLevels.length > 0 &&
    !normalized.cefrLevels.includes(word.cefrLevel.toUpperCase())
  ) {
    return false
  }
  if (normalized.nounsOnly && !word.gender) {
    return false
  }
  if (normalized.tags.length > 0) {
    const tags = (word.tags ?? []).map((tag) => tag.toLowerCase())
    if (!normalized.tags.some((tag) => tags.includes(tag))) {
      return false
    }
  }
  return true
}

/**
 * Short note when filters shrink today's queue.
 */
export const filterNote = (filters: StudyFilters): string | null => {
  const normalized = normalizeStudyFilters(filters)
  const parts: string[] = []
  if (normalized.cefrLevels.length > 0) {
    parts.push(normalized.cefrLevels.join(', '))
  }
  if (normalized.nounsOnly) {
    parts.push('nouns only')
  }
  if (normalized.tags.length > 0) {
    parts.push(`tags: ${normalized.tags.join(', ')}`)
  }
  if (parts.length === 0) return null
  return `Study filters on: ${parts.join(' · ')}.`
}

import { computed, toValue, type MaybeRefOrGetter } from "vue"
import type { MessageWithParts } from "@/api/types"

/**
 * The agent's plan, read out of the transcript.
 *
 * v2 has no todo endpoint — the list only ever exists as the input to the
 * `todowrite` tool, and the newest call is the whole truth. So this walks the
 * transcript backwards and takes the first one it finds rather than trying to
 * accumulate state across calls.
 */

export type TodoStatus = "pending" | "in_progress" | "completed" | "cancelled"

export interface TodoItem {
  id: string
  content: string
  status: TodoStatus
}

const STATUSES = new Set<TodoStatus>(["pending", "in_progress", "completed", "cancelled"])

function toTodos(value: unknown): TodoItem[] | null {
  if (!Array.isArray(value)) return null
  const items: TodoItem[] = []
  for (const [index, entry] of value.entries()) {
    if (typeof entry !== "object" || entry === null) continue
    const record = entry as Record<string, unknown>
    const content = typeof record.content === "string" ? record.content : null
    if (!content) continue
    const status = record.status
    items.push({
      id: typeof record.id === "string" ? record.id : `todo-${index}`,
      content,
      status:
        typeof status === "string" && STATUSES.has(status as TodoStatus)
          ? (status as TodoStatus)
          : "pending",
    })
  }
  return items.length ? items : null
}

export function useSessionTodos(messages: MaybeRefOrGetter<MessageWithParts[]>) {
  const todos = computed<TodoItem[]>(() => {
    const list = toValue(messages)
    for (let index = list.length - 1; index >= 0; index--) {
      const parts = list[index]!.parts
      for (let position = parts.length - 1; position >= 0; position--) {
        const part = parts[position]!
        if (part.type !== "tool" || part.tool !== "todowrite") continue
        const state = part.state
        const input = state && "input" in state ? state.input : undefined
        const parsed = toTodos(input?.todos)
        if (parsed) return parsed
      }
    }
    return []
  })

  const remaining = computed(
    () =>
      todos.value.filter((todo) => todo.status !== "completed" && todo.status !== "cancelled")
        .length,
  )
  const done = computed(() => todos.value.filter((todo) => todo.status === "completed").length)
  const current = computed(() => todos.value.find((todo) => todo.status === "in_progress") ?? null)

  return { todos, remaining, done, current }
}

// Works under Deno (Edge Functions) and Node (unit tests).
export function env(name: string): string | undefined {
  // deno-lint-ignore no-explicit-any
  const deno = (globalThis as any).Deno;
  const value = deno?.env?.get?.(name) ?? (globalThis as any).process?.env?.[name];
  return value === "" ? undefined : value;
}

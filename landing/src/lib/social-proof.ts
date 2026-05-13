const LAUNCH_EPOCH_MS = Date.UTC(2026, 4, 13);
const BASELINE_TOTAL = 240;

const POOL = [
  { name: "María G.", city: "Buenos Aires" },
  { name: "Carlos R.", city: "Lima" },
  { name: "Ana M.", city: "Santiago" },
  { name: "Diego F.", city: "Bogotá" },
  { name: "Lucía B.", city: "Montevideo" },
  { name: "Tomás P.", city: "Rosario" },
  { name: "Sofía L.", city: "CDMX" },
  { name: "Joaquín H.", city: "Córdoba" },
  { name: "Camila V.", city: "Quito" },
  { name: "Mateo A.", city: "Asunción" },
  { name: "Valentina C.", city: "Medellín" },
  { name: "Sebastián O.", city: "Caracas" },
  { name: "Renata S.", city: "Guadalajara" },
  { name: "Bruno T.", city: "Mar del Plata" },
  { name: "Paula D.", city: "Cusco" },
  { name: "Iván W.", city: "Valparaíso" },
  { name: "Florencia E.", city: "Mendoza" },
  { name: "Nicolás Z.", city: "La Paz" },
  { name: "Antonella Q.", city: "Arequipa" },
  { name: "Felipe J.", city: "Concepción" },
] as const;

function hash32(n: number): number {
  let s = ((n + 1) * 2654435761) >>> 0;
  s = Math.imul(s ^ (s >>> 15), 1 | s);
  s = (s + Math.imul(s ^ (s >>> 7), 61 | s)) ^ s;
  return (s ^ (s >>> 14)) >>> 0;
}

export function dayIndex(now: number = Date.now()): number {
  return Math.max(0, Math.floor((now - LAUNCH_EPOCH_MS) / 86_400_000));
}

export function dailyDelta(day: number): number {
  return 12 + (hash32(day) % 24);
}

export function totalSubscribers(now: number = Date.now()): number {
  const today = dayIndex(now);
  let total = BASELINE_TOTAL;
  for (let i = 0; i <= today; i++) total += dailyDelta(i);
  return total;
}

export function weeklySubscribers(now: number = Date.now()): number {
  const today = dayIndex(now);
  let total = 0;
  for (let i = Math.max(0, today - 6); i <= today; i++) total += dailyDelta(i);
  return total;
}

export function todaySubscribers(now: number = Date.now()): number {
  return dailyDelta(dayIndex(now));
}

export type RecentSubscriber = {
  name: string;
  city: string;
  minutesAgo: number;
};

export function recentSubscribers(
  count = 3,
  now: number = Date.now(),
): RecentSubscriber[] {
  const today = dayIndex(now);
  const hourBucket = Math.floor(now / (30 * 60 * 1000));
  const seed = hash32(today * 1000 + hourBucket);
  const result: RecentSubscriber[] = [];
  for (let i = 0; i < count; i++) {
    const userIdx = hash32(seed + i * 7) % POOL.length;
    const minutesAgo = 2 + (hash32(seed + i * 13) % 28);
    const u = POOL[userIdx];
    result.push({ name: u.name, city: u.city, minutesAgo });
  }
  return result.sort((a, b) => a.minutesAgo - b.minutesAgo);
}

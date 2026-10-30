// Copies of /data, kept in sync by tools/sync_function_data.sh (a Swift test fails if they drift).
import atlas from "./data/body-atlas.json" with { type: "json" };

export interface Region {
  id: string;
  name: string;
  group: string;
  side: "left" | "right" | "center";
  aspect: string;
}

export const ATLAS_VERSION: string = atlas.version;
export const REGIONS: Region[] = atlas.regions as Region[];
const IDS = new Set(REGIONS.map((r) => r.id));

export function isRegion(id: string): boolean {
  return IDS.has(id);
}

export function regionName(id: string): string {
  return REGIONS.find((r) => r.id === id)?.name ?? id;
}

/** One line per region, for prompts. Stable order so the prompt prefix caches. */
export const REGION_LIST: string = REGIONS.map((r) => `${r.id}: ${r.name} (${r.group}, ${r.aspect})`).join("\n");

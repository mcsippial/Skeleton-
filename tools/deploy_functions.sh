#!/bin/sh
# Deploys the Edge Functions through the Supabase Management API (no Docker or CLI needed).
# Needs SUPABASE_ACCESS_TOKEN; project ref defaults to the Skeleton project.
set -e
REF="${SUPABASE_PROJECT_REF:-otintmfebdkxkrqgryut}"
cd "$(dirname "$0")/../supabase/functions"
for fn in parse-pain cause-engine; do
  set --
  for f in $fn/index.ts $fn/deno.json _shared/*.ts _shared/data/*.json; do set -- "$@" -F "file=@$f;filename=$f"; done
  meta="{\"entrypoint_path\":\"$fn/index.ts\",\"import_map_path\":\"$fn/deno.json\",\"name\":\"$fn\",\"verify_jwt\":true}"
  curl -sf -X POST "https://api.supabase.com/v1/projects/$REF/functions/deploy?slug=$fn" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -F "metadata=$meta;type=application/json" "$@" \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['slug'],d['status'],'v'+str(d['version']))"
done

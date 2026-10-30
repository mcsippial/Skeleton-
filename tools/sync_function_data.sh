#!/bin/sh
# Edge Functions can only bundle files under supabase/functions, so they get a copy of /data.
# Run after editing anything in /data (SkeletonCore's DataSyncTests fails if the copies drift).
set -e
cd "$(dirname "$0")/.."
cp data/body-atlas.json data/pain-pathways.json data/red-flags.json supabase/functions/_shared/data/
echo "Synced /data → supabase/functions/_shared/data"

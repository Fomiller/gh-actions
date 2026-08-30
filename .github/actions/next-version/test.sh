#!/usr/bin/env bash
# Exercises next-version.sh against a real git history.
set -euo pipefail

NV="$(cd "$(dirname "$0")" && pwd)/next-version.sh"
R="$(mktemp -d)/repo"

rm -rf "$R"; mkdir -p "$R"; cd "$R"
git init -q .; git config user.email t@t; git config user.name t

mkdir -p src helm/thing
c() { # c <file> <subject> [body]
  echo "$RANDOM" > "$1"
  git add -A
  if [ -n "${3:-}" ]; then git commit -q -m "$2" -m "$3"; else git commit -q -m "$2"; fi
}

fail=0
ck() { # ck <label> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "ok   $1 -> $3"; else echo "FAIL $1 -> got $3, want $2"; fail=1; fi
}

c src/a "feat: initial"

# No tag yet: seed is published as-is, not bumped.
ck "seed default"      "0.1.0" "$($NV --prefix app-v)"
ck "seed explicit"     "0.4.0" "$($NV --prefix app-v --seed 0.4.0)"

git tag app-v0.1.0

# Nothing since the tag: patch bump, and the caller detects it via `released`.
ck "no commits"        "0.1.1" "$($NV --prefix app-v)"

c src/b "fix: a bug"
ck "fix -> patch"      "0.1.1" "$($NV --prefix app-v)"

c src/c "feat: a feature"
ck "feat -> minor"     "0.2.0" "$($NV --prefix app-v)"

c src/d "feat!: breaking"
ck "0.x breaking->minor" "0.2.0" "$($NV --prefix app-v)"

git tag app-v1.0.0
c src/e "feat!: breaking again"
ck "1.x breaking->major" "2.0.0" "$($NV --prefix app-v)"

git tag app-v2.0.0
c src/f "chore: body break" "BREAKING CHANGE: yes"
ck "body breaking"     "3.0.0" "$($NV --prefix app-v)"

# Path scoping: the two streams do not see each other's commits.
git tag app-v3.0.0
git tag chart-v0.1.0
c helm/thing/x "feat: chart only"
ck "path scoped app"   "3.0.1" "$($NV --prefix app-v --path src)"
ck "path scoped chart" "0.2.0" "$($NV --prefix chart-v --path helm/thing)"

# Version sort, not lexical: 0.10.0 is newer than 0.9.0.
git tag sort-v0.9.0; git tag sort-v0.10.0
ck "version sort"      "0.10.1" "$($NV --prefix sort-v --path nonexistent)"

# rc numbering counts up per target version.
ck "rc first"          "0.10.1-rc.1" "$($NV --prefix sort-v --path nonexistent --rc)"
git tag sort-v0.10.1-rc.1
ck "rc second"         "0.10.1-rc.2" "$($NV --prefix sort-v --path nonexistent --rc)"
# An rc tag must not become the base for the next stable.
ck "rc ignored as base" "0.10.1" "$($NV --prefix sort-v --path nonexistent)"

# A prefix that is a prefix of another must not steal its tags.
ck "prefix isolation"  "0.2.0" "$($NV --prefix chart-v --path helm/thing)"

# The real pair: the image prefix must not match the chart's tags. "svc-v*"
# does not glob "svc-chart-v0.9.0", but this is the case that would silently
# publish a wrong version if the prefixes were ever built differently.
git tag svc-chart-v0.9.0
ck "image ignores chart tags" "0.1.0" "$($NV --prefix svc-v)"
git tag svc-v0.1.0
ck "chart ignores image tags" "0.9.1" "$($NV --prefix svc-chart-v --path nonexistent)"

exit $fail

#!/usr/bin/env bash
# Print the next version for one release stream, derived from conventional-commit
# subjects since that stream's last tag. Prints the version alone, so callers can
# capture it.
#
#   next-version.sh --prefix blog-v
#   next-version.sh --prefix blog-chart-v --rc --path helm/blog
#
# A stream is identified by its tag prefix. Two artifacts released from one repo
# use two prefixes and never see each other's commits or tags.
#
# Options:
#   --prefix <s>   tag prefix, e.g. "blog-v". Required.
#   --rc           next release candidate instead of the next stable.
#   --seed <v>     version to publish when the stream has no tag yet.
#                  Default 0.1.0. This is published as-is, not bumped: adopting
#                  this on an artifact that already has a version elsewhere
#                  should not jump it a release on the first run.
#   --path <p>     only count commits touching this path. Repeatable. Omit to
#                  count every commit in the range.
#
# Bump rules, highest match wins:
#   breaking  `<type>!:` in the subject, or `BREAKING CHANGE` in the body
#   minor     a `feat` commit
#   patch     anything else
#
# While the major version is still 0 a breaking change bumps the MINOR, not the
# major. Going to 1.0.0 is a deliberate call, not something a `!` should trigger.
#
# Release candidates are numbered per target version: the first rc for 0.3.0 is
# 0.3.0-rc.1, and it keeps counting up until 0.3.0 itself is cut.
set -euo pipefail

prefix=""
rc=0
seed="0.1.0"
paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) prefix="$2"; shift 2 ;;
    --rc)     rc=1; shift ;;
    --seed)   seed="$2"; shift 2 ;;
    --path)   paths+=("$2"); shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$prefix" ]]; then
  echo "--prefix is required" >&2
  exit 1
fi

# Sort by version, not lexically, so 0.10.0 beats 0.9.0. `--sort` applies to the
# whole tag including the prefix, which is constant here, so it does not skew.
last_tag="$(git tag --list "${prefix}*" --sort=-v:refname | grep -v -- '-rc\.' | head -1 || true)"

if [[ -z "$last_tag" ]]; then
  next="$seed"
else
  base="${last_tag#"$prefix"}"
  IFS='.' read -r major minor patch <<< "$base"

  bump="patch"
  while IFS= read -r subject; do
    [[ -z "$subject" ]] && continue
    if [[ "$subject" =~ ^[a-zA-Z]+(\([^\)]*\))?!: ]]; then
      bump="major"
      break
    fi
    if [[ "$subject" =~ ^feat(\([^\)]*\))?: ]]; then
      bump="minor"
    fi
  done < <(git log --format='%s' "${last_tag}..HEAD" -- "${paths[@]+"${paths[@]}"}")

  if git log --format='%B' "${last_tag}..HEAD" -- "${paths[@]+"${paths[@]}"}" | grep -q 'BREAKING CHANGE'; then
    bump="major"
  fi

  case "$bump" in
    major)
      if [[ "$major" == "0" ]]; then
        next="0.$((minor + 1)).0"
      else
        next="$((major + 1)).0.0"
      fi
      ;;
    minor) next="${major}.$((minor + 1)).0" ;;
    patch) next="${major}.${minor}.$((patch + 1))" ;;
  esac
fi

if [[ "$rc" == 1 ]]; then
  n=1
  while git rev-parse -q --verify "refs/tags/${prefix}${next}-rc.${n}" >/dev/null; do
    n=$((n + 1))
  done
  next="${next}-rc.${n}"
fi

printf '%s\n' "$next"

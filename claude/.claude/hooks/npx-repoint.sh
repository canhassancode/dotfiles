#!/bin/bash
# PreToolUse repointer for Bash — rewrites `npx <bin>` to the project's own
# package manager. Claude's first instinct for "test / typecheck / lint" is
# `npx <tool>`, which re-fetches from the registry and ignores the repo's
# pinned deps and package.json scripts. This repoints it:
#
#   npx <name>   →   <pm> run  <name>   when <name> is a package.json script
#   npx <name>   →   <pm> exec <name>   otherwise (runs the local node_modules bin)
#
# <pm> is detected per-invocation from the nearest lockfile above the command's
# cwd (pnpm-lock.yaml → pnpm, yarn.lock → yarn, else npm). No manager is
# hardcoded — the hook is global and must suit whatever repo Claude is in.
#
# Emits a PreToolUse `updatedInput` payload that replaces .command; the normal
# permission flow then re-evaluates the rewritten command (so an allowed
# `pnpm run *` no longer prompts, per settings.json). When nothing is rewritten
# the hook stays silent (exit 0) and the original command runs untouched.
#
# Deliberately conservative — only the command word of a segment is a candidate
# (segment start, after ; && || | (, or after leading FOO=bar env assignments),
# so `npx` inside an echo/commit-message string is left alone. Ambiguous specs
# that don't map to a local bin are skipped: version pins (pkg@1), scoped or
# path-like names (@scope/pkg, ./bin), and the -p/--package/-c/--call forms.
#
# Fail-open: no jq, no command, or a parse failure exits 0 and changes nothing.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

[ -z "$cmd" ] && exit 0
printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|=[^[:space:]]* )[[:space:]]*npx[[:space:]]' || \
  printf '%s' "$cmd" | grep -Eq '^[[:space:]]*npx[[:space:]]' || exit 0

[ -z "$cwd" ] && cwd=$PWD

find_up() {
  local dir=$1 name=$2
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    [ -e "$dir/$name" ] && { printf '%s' "$dir/$name"; return 0; }
    dir=$(dirname "$dir")
  done
  return 1
}

pm=npm
if find_up "$cwd" pnpm-lock.yaml >/dev/null; then
  pm=pnpm
elif find_up "$cwd" yarn.lock >/dev/null; then
  pm=yarn
fi

pkg=$(find_up "$cwd" package.json)
scripts=""
[ -n "$pkg" ] && scripts=$(jq -r '(.scripts // {}) | keys[]' "$pkg" 2>/dev/null)

new=$(PM="$pm" SCRIPTS="$scripts" CMD="$cmd" perl -e '
  my $pm = $ENV{PM};
  my %scripts = map { $_ => 1 } grep { length } split /\n/, $ENV{SCRIPTS};
  my $cmd = $ENV{CMD};

  $cmd =~ s{
    (^|[;&|(]\s*)          # segment boundary
    ((?:\w+=\S+\s+)*)      # optional leading env assignments
    npx\b\s*
    ((?:-{1,2}[\w-]+\s+)*) # npx flags
    (\S+)                  # first bare token
  }{
    my ($pre, $env, $flags, $tok) = ($1, $2, $3, $4);
    my $orig = "${pre}${env}npx ${flags}${tok}";
    if ($flags =~ /(?:^|\s)(?:-p|--package|-c|--call)(?:\s|$)/
        || $tok =~ /[@\/]/) {
      $orig;
    } else {
      my $verb = $scripts{$tok} ? "run" : "exec";
      "${pre}${env}${pm} ${verb} ${tok}";
    }
  }gex;
  print $cmd;
' 2>/dev/null)

[ -z "$new" ] && exit 0
[ "$new" = "$cmd" ] && exit 0

jq -nc --arg c "$new" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:{command:$c}}}' 2>/dev/null
exit 0

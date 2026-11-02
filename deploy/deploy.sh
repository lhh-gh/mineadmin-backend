#!/usr/bin/env bash
set -Eeuo pipefail

# Each release keeps its own Compose file and immutable image digest.
# Shared runtime.env and compose.env stay two directories above this script.
usage() {
  printf '%s\n' \
    'Usage: bash releases/<release-id>/deploy.sh <registry/namespace/image@sha256:digest>' \
    '       bash current/deploy.sh --rollback'
}

log() {
  printf '[deploy] %s\n' "$*" || true
}

die() {
  printf '[deploy] ERROR: %s\n' "$*" >&2
  exit 1
}

valid_image() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9.:-]*/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$ ]]
}

if [[ "${1:-}" == --help && $# == 1 ]]; then
  usage
  exit 0
fi
if [[ $# != 1 ]]; then
  usage >&2
  exit 2
fi
MODE=deploy
if [[ "$1" == --rollback ]]; then
  MODE=rollback
else
  valid_image "$1" || die 'Provide a complete registry image reference pinned to a sha256 digest.'
fi

for required_command in docker flock readlink; do
  command -v "$required_command" > /dev/null || die "Missing command: $required_command"
done
SCRIPT_FILE="$(readlink -f -- "${BASH_SOURCE[0]}")"
RELEASE_DIR="$(dirname -- "$SCRIPT_FILE")"
ROOT_DIR="$(readlink -f -- "$RELEASE_DIR/../..")"
[[ "$(dirname -- "$RELEASE_DIR")" == "$ROOT_DIR/releases" ]] || die 'Place this script in <deploy-root>/releases/<release-id>/ before running it.'
[[ -r "$ROOT_DIR/runtime.env" && -r "$ROOT_DIR/compose.env" ]] || die 'Create readable runtime.env and compose.env in the deployment root first.'

compose_version="$(docker compose version --short)"
compose_version="${compose_version#v}"
[[ "$compose_version" =~ ^([0-9]+)\.([0-9]+) ]] || die 'Cannot read the Docker Compose version.'
compose_major="${BASH_REMATCH[1]}"
compose_minor="${BASH_REMATCH[2]}"
(( 10#$compose_major > 2 || (10#$compose_major == 2 && 10#$compose_minor >= 30) )) || die 'Docker Compose 2.30 or newer is required.'

log 'Waiting for the deployment lock.'
exec 9> "$ROOT_DIR/.deploy.lock"
flock -w 300 9 || die 'Another deployment still holds the lock; retry after it finishes.'

validate_release() {
  local directory="$1"
  [[ -d "$directory" && "$(dirname -- "$directory")" == "$ROOT_DIR/releases" ]] || die 'The release path must be a direct subdirectory of <deploy-root>/releases/.'
  [[ -f "$directory/compose.yml" ]] || die "Missing Compose file in release: $directory"
}

read_release_image() {
  local directory="$1"
  local image
  local -a metadata
  [[ -r "$directory/release.env" ]] || die "Missing image metadata in release: $directory"
  mapfile -t metadata < "$directory/release.env"
  [[ ${#metadata[@]} == 1 && "${metadata[0]}" == APP_IMAGE=* ]] || die 'Release metadata must contain exactly one APP_IMAGE line.'
  image="${metadata[0]#APP_IMAGE=}"
  valid_image "$image" || die 'Release metadata contains an invalid image digest.'
  printf '%s\n' "$image"
}

resolve_release_link() {
  local name="$1"
  local resolved
  if [[ ! -e "$ROOT_DIR/$name" && ! -L "$ROOT_DIR/$name" ]]; then
    return 0
  fi
  [[ -L "$ROOT_DIR/$name" ]] || die "$name must be a release symlink."
  resolved="$(readlink -f -- "$ROOT_DIR/$name")"
  validate_release "$resolved"
  read_release_image "$resolved" > /dev/null
  printf '%s\n' "$resolved"
}

CURRENT_RELEASE="$(resolve_release_link current)"
PREVIOUS_RELEASE="$(resolve_release_link previous)"
[[ -n "$CURRENT_RELEASE" || -z "$PREVIOUS_RELEASE" ]] || die 'A previous release exists without a current release; repair the release links first.'
TARGET_RELEASE="$RELEASE_DIR"
if [[ "$MODE" == rollback ]]; then
  [[ -n "$PREVIOUS_RELEASE" ]] || die 'There is no previous release to roll back to.'
  TARGET_RELEASE="$PREVIOUS_RELEASE"
fi
validate_release "$TARGET_RELEASE"

TEMPORARY_PATHS=()
cleanup() {
  if [[ ${#TEMPORARY_PATHS[@]} -gt 0 ]]; then
    rm -f -- "${TEMPORARY_PATHS[@]}"
  fi
}
trap cleanup EXIT

if [[ "$MODE" == deploy ]]; then
  if [[ -e "$RELEASE_DIR/release.env" ]]; then
    [[ "$(read_release_image "$RELEASE_DIR")" == "$1" ]] || die 'This release already records a different image. Create a new release directory.'
  else
    metadata_temp="$RELEASE_DIR/.release.env.$$"
    TEMPORARY_PATHS+=("$metadata_temp")
    (umask 077; printf 'APP_IMAGE=%s\n' "$1" > "$metadata_temp")
    mv -T -- "$metadata_temp" "$RELEASE_DIR/release.env"
  fi
fi

compose_for() {
  local directory="$1"
  local image
  shift
  image="$(read_release_image "$directory")" || return
  # A shell APP_IMAGE must not override the digest belonging to this release.
  APP_IMAGE="$image" docker compose \
    --project-name mineadmin \
    --env-file "$ROOT_DIR/compose.env" \
    --env-file "$directory/release.env" \
    -f "$directory/compose.yml" "$@"
}

set_release_link() {
  local name="$1"
  local target="$2"
  local temporary_link="$ROOT_DIR/.$name.$$"
  TEMPORARY_PATHS+=("$temporary_link")
  ln -s -- "$target" "$temporary_link" || return
  mv -Tf -- "$temporary_link" "$ROOT_DIR/$name"
}

reset_release_link() {
  local name="$1"
  local target="$2"
  if [[ -n "$target" ]]; then
    set_release_link "$name" "$target" || return
  elif [[ -L "$ROOT_DIR/$name" ]]; then
    rm -f -- "$ROOT_DIR/$name" || return
  elif [[ -e "$ROOT_DIR/$name" ]]; then
    return 1
  fi
  return 0
}

DEPLOYMENT_STARTED=false
METADATA_STARTED=false
on_failure() {
  local status="$1"
  trap - ERR INT TERM HUP
  log 'The release did not complete successfully.'
  if [[ "$DEPLOYMENT_STARTED" == true ]]; then
    if [[ -n "$CURRENT_RELEASE" ]]; then
      log 'Restoring the last recorded healthy release.'
      if compose_for "$CURRENT_RELEASE" up -d --wait --wait-timeout 180 app; then
        log 'The last healthy release has been restored. This deployment still reports failure.'
      else
        log 'ERROR: Automatic recovery also failed. Inspect the application and its MySQL/Redis connections on the server.'
      fi
    else
      log 'This first deployment has no earlier release. Stopping the failed application and retaining its container for diagnosis.'
      if ! compose_for "$TARGET_RELEASE" stop app; then
        log 'ERROR: Could not stop the failed application; inspect it on the server.'
      fi
    fi
  else
    log 'The application replacement had not started; the recorded release is unchanged.'
  fi
  if [[ "$METADATA_STARTED" == true ]]; then
    if ! reset_release_link previous "$PREVIOUS_RELEASE" || ! reset_release_link current "$CURRENT_RELEASE"; then
      log 'ERROR: Could not restore the release symlinks; inspect current and previous on the server.'
    fi
  fi
  exit "$status"
}
trap 'on_failure $?' ERR
trap 'on_failure 130' INT
trap 'on_failure 143' TERM
trap 'on_failure 129' HUP

log "Pulling $(read_release_image "$TARGET_RELEASE")."
compose_for "$TARGET_RELEASE" pull app
DEPLOYMENT_STARTED=true
compose_for "$TARGET_RELEASE" up -d --wait --wait-timeout 180 app

if [[ "$TARGET_RELEASE" != "$CURRENT_RELEASE" ]]; then
  METADATA_STARTED=true
  if [[ -n "$CURRENT_RELEASE" ]]; then
    set_release_link previous "$CURRENT_RELEASE"
  fi
  set_release_link current "$TARGET_RELEASE"
fi
log "Healthy release: $TARGET_RELEASE"
if [[ "$MODE" == rollback ]]; then
  log 'Rollback completed. The version just replaced is available through previous.'
fi

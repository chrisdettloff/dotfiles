#!/usr/bin/env bash

# Set up Elephant and Walker as systemd user services.
# Safe to run repeatedly from a dotfiles bootstrap script.

set -Eeuo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '%s\n' "$*"
}

if ((EUID == 0)); then
  die "run this script as your regular desktop user, not as root"
fi

command -v systemctl >/dev/null 2>&1 || die "systemd is required"

walker_bin="$(command -v walker || true)"
elephant_bin="$(command -v elephant || true)"

[[ -n "$walker_bin" ]] || die "walker is not installed or is not in PATH"
[[ -n "$elephant_bin" ]] || die "elephant is not installed or is not in PATH"

# ExecStart does not run through a shell. Resolve an absolute executable path
# now so the service does not depend on the systemd user manager's PATH.
if [[ "$walker_bin" != /* ]]; then
  walker_bin="$(realpath "$walker_bin")"
fi

[[ "$walker_bin" != *$'\n'* ]] || die "the walker path contains a newline"

# Quote the executable for systemd.syntax(7). A literal percent must be doubled
# because systemd otherwise treats it as the beginning of a specifier.
walker_exec=${walker_bin//\\/\\\\}
walker_exec=${walker_exec//\"/\\\"}
walker_exec=${walker_exec//%/%%}

systemd_user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
walker_unit="$systemd_user_dir/walker.service"

mkdir -p "$systemd_user_dir"

tmp_unit="$(mktemp "$systemd_user_dir/.walker.service.XXXXXX")"
trap 'rm -f "$tmp_unit"' EXIT

cat >"$tmp_unit" <<EOF
[Unit]
Description=Walker application launcher service
After=elephant.service
Wants=elephant.service

[Service]
Type=simple
ExecStart="$walker_exec" --gapplication-service
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=default.target
EOF

if [[ -f "$walker_unit" ]] && cmp -s "$tmp_unit" "$walker_unit"; then
  note "Walker unit is already up to date."
else
  install -m 0644 "$tmp_unit" "$walker_unit"
  note "Installed $walker_unit"
fi

# Elephant owns and generates its service definition.
"$elephant_bin" service enable

systemctl --user daemon-reload
systemctl --user enable --now elephant.service
systemctl --user enable --now walker.service

# Ensure an already-running Walker reloads its configuration and theme after a
# dotfiles update. Restarting Elephant is harmless and applies provider changes.
systemctl --user restart elephant.service walker.service

note
note "Walker and Elephant are enabled and running."
note "Check them with:"
note "  systemctl --user --no-pager --full status elephant.service walker.service"
note
note "After changing Walker's config or theme, reload it with:"
note "  systemctl --user restart walker.service"

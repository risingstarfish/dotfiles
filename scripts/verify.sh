#!/usr/bin/env bash
# scripts/verify.sh
# Comprehensive cross-script verification suite for dotfiles.sh and dotfiles.ps1
# shellcheck disable=SC2317,SC2016

set -euo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-verify.XXXXXX")"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT INT TERM

pass() {
    printf '[PASS] %s\n' "$1"
}

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    exit 1
}

printf '=== Running dotfiles verification suite in %s ===\n\n' "${WORK_DIR}"

# ─────────────────────────────────────────────────────────────
# 1. Bash syntax (bash -n) & ShellCheck per .shellcheckrc + PowerShell AST parse
# ─────────────────────────────────────────────────────────────
printf -- '--- 1. Syntax & Static Analysis ---\n'
bash -n "${REPO_ROOT}/dotfiles.sh" "${REPO_ROOT}"/src/*.sh || fail "bash -n failed"
pass "bash -n clean on dotfiles.sh and src/*.sh"

if command -v shellcheck > /dev/null 2>&1; then
    (cd "${REPO_ROOT}" && shellcheck dotfiles.sh src/*.sh) || fail "shellcheck failed"
    pass "shellcheck clean per .shellcheckrc"
else
    fail "shellcheck not found"
fi

if command -v pwsh > /dev/null 2>&1; then
    REPO_ROOT="${REPO_ROOT}" pwsh -NoProfile -Command '
        $Root = $env:REPO_ROOT
        $files = @("$Root/dotfiles.ps1") +
                 (Get-ChildItem "$Root/src/*.ps1" | ForEach-Object { $_.FullName }) +
                 (Get-ChildItem "$Root/modules/pwsh.windows/*" | ForEach-Object { $_.FullName })
        foreach ($f in $files) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) {
                Write-Error "Parse error in ${f}: $($errors | Out-String)"
                exit 1
            }
        }
    ' || fail "PowerShell AST parse failed"
    pass "PowerShell AST parse clean on dotfiles.ps1, src/*.ps1, and modules/pwsh.windows/*"
else
    fail "pwsh not found"
fi

# ─────────────────────────────────────────────────────────────
# 2. Dry-run pass of EVERY bash action and EVERY ps1 action
# ─────────────────────────────────────────────────────────────
printf '\n--- 2. Dry-Run of Every Action (bash & pwsh) ---\n'
DRY_HOME="${WORK_DIR}/dry_home"
DRY_CACHE="${WORK_DIR}/dry_cache"
DRY_LOGS="${WORK_DIR}/dry_logs"
mkdir -p "${DRY_HOME}" "${DRY_CACHE}" "${DRY_LOGS}"

run_all_dry_runs() {
    local runner="$1"
    local script_path="$2"
    export HOME="${DRY_HOME}"
    export USERPROFILE="${DRY_HOME}"
    export DOTFILES_CACHE_DIR="${DRY_CACHE}"
    export DOTFILES_LOG_DIR="${DRY_LOGS}"
    export DOTFILES_LOCAL_MODS=1

    local -a actions=(
        "--help"
        "--version"
        "--list"
        "--install --dry-run"
        "--update --dry-run"
        "--remove zsh --dry-run"
        "--repair --dry-run"
        "--reset --dry-run"
        "--uninstall --dry-run"
        "--clean --dry-run"
        "--clean 7 --dry-run"
        "--clean-logs --dry-run"
        "--clean-backups --dry-run"
        "--clean-backups 7 --dry-run"
    )

    local act
    for act in "${actions[@]}"; do
        # shellcheck disable=SC2086
        if [[ ${runner} == "bash" ]]; then
            bash "${script_path}" ${act} > /dev/null || fail "bash ${act} failed"
        else
            pwsh -NoProfile -File "${script_path}" ${act} > /dev/null || fail "pwsh ${act} failed"
        fi
    done
}

run_all_dry_runs "bash" "${REPO_ROOT}/dotfiles.sh"
pass "Every bash action dry-run passed with exit 0"

run_all_dry_runs "pwsh" "${REPO_ROOT}/dotfiles.ps1"
pass "Every ps1 action dry-run passed with exit 0"

# ─────────────────────────────────────────────────────────────
# 3. --list sanity (regression guard for T1/T3)
# ─────────────────────────────────────────────────────────────
printf '\n--- 3. --list Sanity & Cross-Script Output Equivalence ---\n'
LIST_SH="${WORK_DIR}/list_sh.txt"
LIST_PS1="${WORK_DIR}/list_ps1.txt"

HOME="${DRY_HOME}" DOTFILES_CACHE_DIR="${DRY_CACHE}" DOTFILES_LOG_DIR="${DRY_LOGS}" \
    bash "${REPO_ROOT}/dotfiles.sh" --list > "${LIST_SH}"
HOME="${DRY_HOME}" DOTFILES_CACHE_DIR="${DRY_CACHE}" DOTFILES_LOG_DIR="${DRY_LOGS}" \
    pwsh -NoProfile -File "${REPO_ROOT}/dotfiles.ps1" --list > "${LIST_PS1}"

diff -u "${LIST_SH}" "${LIST_PS1}" || fail "--list output differs between bash and ps1"
pass "--list output is byte-for-byte identical between bash and ps1"

# Verify every row in DF_MANIFEST is present in --list output
expected_entries=(
    "zshrc" "zsh_options" "zstyles" "zimrc" "p10k.zsh" "exports" "paths" "aliases" "functions" "zshrc.toggles"
    "bashrc"
    "gitconfig" "gitconfig.local" "gitignore" "gitattributes" "diff-so-fancy"
    "config" "allowed_signers"
    "cmakepreset.py" "internal-flags.cmake" "cmake-format.py" "clang-format" "clang-tidy" "editorconfig"
    "topgrade.toml" "config.jsonc" "tmux.conf" "curlrc" "wgetrc" "shellcheckrc"
    "settings.json" "plugin.json"
    "Profile" "Set-MSVC-Environment" "Update-Modules" "Print-Env" "nproc" "sha256" "sha1" "md5" "Exports" "Paths" "Aliases" "Functions"
    "tiger.omp.json" "agnoster.omp.json" "kushal.omp.json" "powerlevel10k_classic.omp.json" "powerlevel10k_lean.omp.json" "powerlevel10k_modern.omp.json"
)

for item_name in "${expected_entries[@]}"; do
    if ! grep -qE "^  (✓|✗|!|\?) ${item_name}\$" "${LIST_SH}"; then
        fail "Manifest row '${item_name}' is missing from --list output!"
    fi
done
pass "All ${#expected_entries[@]} DF_MANIFEST rows are present in --list output (no silent skips)"

# ─────────────────────────────────────────────────────────────
# 4. Manifest parity & cross-read interoperability
# ─────────────────────────────────────────────────────────────
printf '\n--- 4. Manifest Parity & Cross-Script Interoperability ---\n'
M_HOME_SH="${WORK_DIR}/m_home"
M_CACHE_SH="${WORK_DIR}/m_cache_sh"
M_CACHE_PS1="${WORK_DIR}/m_cache_ps1"
M_LOGS="${WORK_DIR}/m_logs"
mkdir -p "${M_HOME_SH}" "${M_CACHE_SH}" "${M_CACHE_PS1}" "${M_LOGS}"

# Seed identical # ref= header in both manifests
printf '# ref=main timestamp=2026-09-24T00:00:00Z\n' > "${M_CACHE_SH}/manifest.tsv"
printf '# ref=main timestamp=2026-09-24T00:00:00Z\r\n' > "${M_CACHE_PS1}/manifest.tsv"

# Install subset (curl;wget;bash) with bash and with pwsh against the same HOME
HOME="${M_HOME_SH}" DOTFILES_CACHE_DIR="${M_CACHE_SH}" DOTFILES_LOG_DIR="${M_LOGS}" \
    bash "${REPO_ROOT}/dotfiles.sh" --install -i "curl;wget;bash" --noconfirm > /dev/null
rm -f "${M_HOME_SH}/.curlrc" "${M_HOME_SH}/.wgetrc" "${M_HOME_SH}/.bashrc"

HOME="${M_HOME_SH}" DOTFILES_CACHE_DIR="${M_CACHE_PS1}" DOTFILES_LOG_DIR="${M_LOGS}" \
    pwsh -NoProfile -File "${REPO_ROOT}/dotfiles.ps1" --install -i "curl;wget;bash" --noconfirm > /dev/null

# Verify neither manifest contains CR and both are byte-identical
tr -d '\r' < "${M_CACHE_SH}/manifest.tsv" > "${WORK_DIR}/m_sh_norm.tsv"
tr -d '\r' < "${M_CACHE_PS1}/manifest.tsv" > "${WORK_DIR}/m_ps1_norm.tsv"
diff -u "${WORK_DIR}/m_sh_norm.tsv" "${WORK_DIR}/m_ps1_norm.tsv" || fail "Bash and PS1 manifests differ!"
diff -u "${M_CACHE_SH}/manifest.tsv" "${M_CACHE_PS1}/manifest.tsv" || fail "Raw manifest bytes differ (line ending mismatch)!"

# Verify 3 TAB-delimited fields per data row and preserved # header
awk -F'\t' '
    NR == 1 { if ($0 !~ /^# ref=main timestamp=/) exit 1; next }
    NF != 3 { exit 2 }
' "${M_CACHE_PS1}/manifest.tsv" || fail "Manifest format validation failed"
pass "Manifests written by bash and ps1 are byte-identical, preserve # header, and have 3 TAB fields"

# Cross-read: break one symlink (.curlrc) and verify both bash and ps1 produce identical --list and --repair decisions
rm -f "${M_HOME_SH}/.curlrc"
HOME="${M_HOME_SH}" DOTFILES_CACHE_DIR="${M_CACHE_PS1}" DOTFILES_LOG_DIR="${M_LOGS}" \
    bash "${REPO_ROOT}/dotfiles.sh" --list > "${WORK_DIR}/cross_list_sh.txt"
HOME="${M_HOME_SH}" DOTFILES_CACHE_DIR="${M_CACHE_SH}" DOTFILES_LOG_DIR="${M_LOGS}" \
    pwsh -NoProfile -File "${REPO_ROOT}/dotfiles.ps1" --list > "${WORK_DIR}/cross_list_ps1.txt"
diff -u "${WORK_DIR}/cross_list_sh.txt" "${WORK_DIR}/cross_list_ps1.txt" || fail "Cross-read --list decisions differ!"
grep -qE "^  ! curlrc\$" "${WORK_DIR}/cross_list_sh.txt" || fail "Broken symlink curlrc not detected as '!'"

# Repair using ps1 against bash-written manifest, then verify healthy in bash
HOME="${M_HOME_SH}" DOTFILES_CACHE_DIR="${M_CACHE_SH}" DOTFILES_LOG_DIR="${M_LOGS}" \
    pwsh -NoProfile -File "${REPO_ROOT}/dotfiles.ps1" --repair --noconfirm > /dev/null
HOME="${M_HOME_SH}" DOTFILES_CACHE_DIR="${M_CACHE_SH}" DOTFILES_LOG_DIR="${M_LOGS}" \
    bash "${REPO_ROOT}/dotfiles.sh" --list > "${WORK_DIR}/repaired_list_sh.txt"
grep -qE "^  ✓ curlrc\$" "${WORK_DIR}/repaired_list_sh.txt" || fail "ps1 --repair did not restore curlrc health for bash!"
pass "Cross-read --list and --repair decisions between bash and ps1 are identical"

# ─────────────────────────────────────────────────────────────
# 5. Backup path equivalence (including .1.bak collision step)
# ─────────────────────────────────────────────────────────────
printf '\n--- 5. Backup Path Equivalence (.bak and .1.bak collisions) ---\n'
FIXED_STAMP="2026-09-24_120000"
B_HOME_SH="${WORK_DIR}/b_home_sh"
B_CACHE_SH="${WORK_DIR}/b_cache_sh"
B_HOME_PS1="${WORK_DIR}/b_home_ps1"
B_CACHE_PS1="${WORK_DIR}/b_cache_ps1"
mkdir -p "${B_HOME_SH}" "${B_CACHE_SH}/backups/${FIXED_STAMP}" \
         "${B_HOME_PS1}" "${B_CACHE_PS1}/backups/${FIXED_STAMP}"

# Pre-seed existing regular file .curlrc and pre-existing .curlrc.bak to force .curlrc.1.bak collision
printf 'user-curl-1\n' > "${B_HOME_SH}/.curlrc"
printf 'old-bak\n' > "${B_CACHE_SH}/backups/${FIXED_STAMP}/.curlrc.bak"
printf 'user-curl-1\n' > "${B_HOME_PS1}/.curlrc"
printf 'old-bak\n' > "${B_CACHE_PS1}/backups/${FIXED_STAMP}/.curlrc.bak"

# Run bash _guard_dest and ps1 _guard_dest with identical DOTFILES_START_TIME
HOME="${B_HOME_SH}" DOTFILES_CACHE_DIR="${B_CACHE_SH}" DOTFILES_LOG_DIR="${M_LOGS}" \
    bash -c "
        source '${REPO_ROOT}/src/logging.sh'
        init_logger --level INFO --quiet
        DOTFILES_BACKUP_DIR='${B_CACHE_SH}/backups'
        DOTFILES_START_TIME='${FIXED_STAMP}'
        DF_FORCE=0; DF_DRY_RUN=0; DF_INTERACTIVE=0; DF_NOCONFIRM=1
        source '${REPO_ROOT}/src/utility.sh'
        source '${REPO_ROOT}/src/action.sh'
        _guard_dest '${B_HOME_SH}/.curlrc' '${REPO_ROOT}/modules/curl/curlrc'
    "

HOME="${B_HOME_PS1}" DOTFILES_CACHE_DIR="${B_CACHE_PS1}" DOTFILES_LOG_DIR="${M_LOGS}" \
    pwsh -NoProfile -Command "
        \$script:DOTFILES_BACKUP_DIR = '${B_CACHE_PS1}/backups'
        \$script:DOTFILES_START_TIME = '${FIXED_STAMP}'
        \$script:DF_FORCE = 0; \$script:DF_DRY_RUN = 0; \$script:DF_INTERACTIVE = 0; \$script:DF_NOCONFIRM = 1
        . '${REPO_ROOT}/src/logging.ps1'
        [void](init_logger '--level' 'INFO' '--quiet')
        . '${REPO_ROOT}/src/utility.ps1'
        . '${REPO_ROOT}/src/print.ps1'
        . '${REPO_ROOT}/src/action.ps1'
        [void](_guard_dest '${B_HOME_PS1}/.curlrc' '${REPO_ROOT}/modules/curl/curlrc')
    "

[[ -f "${B_CACHE_SH}/backups/${FIXED_STAMP}/.curlrc.1.bak" ]] || fail "Bash did not create .curlrc.1.bak"
[[ -f "${B_CACHE_PS1}/backups/${FIXED_STAMP}/.curlrc.1.bak" ]] || fail "PS1 did not create .curlrc.1.bak"
(cd "${B_CACHE_SH}" && find backups -type f | sort) > "${WORK_DIR}/b_paths_sh.txt"
(cd "${B_CACHE_PS1}" && find backups -type f | sort) > "${WORK_DIR}/b_paths_ps1.txt"
diff -u "${WORK_DIR}/b_paths_sh.txt" "${WORK_DIR}/b_paths_ps1.txt" || fail "Backup relative paths differ!"
pass "Backup paths and .1.bak collision handling are 100% identical"

# ─────────────────────────────────────────────────────────────
# 6. Exit codes (0 / 1 / 2 / 130) & Concurrency Lock (D5)
# ─────────────────────────────────────────────────────────────
printf '\n--- 6. Exit Codes (0 / 1 / 2 / 130) & Concurrency Lock (D5) ---\n'
assert_exit() {
    local expected="$1"
    shift
    local actual=0
    "$@" > /dev/null 2>&1 || actual=$?
    if [[ ${actual} -ne ${expected} ]]; then
        fail "Expected exit ${expected}, got ${actual} for: $*"
    fi
}

export HOME="${DRY_HOME}" DOTFILES_CACHE_DIR="${DRY_CACHE}" DOTFILES_LOG_DIR="${DRY_LOGS}"

# 0: OK
assert_exit 0 bash "${REPO_ROOT}/dotfiles.sh" --help
assert_exit 0 pwsh -NoProfile -File "${REPO_ROOT}/dotfiles.ps1" --help

# 2: Usage / invalid flag / conflicting flags
assert_exit 2 bash "${REPO_ROOT}/dotfiles.sh" --nonexistent-flag
assert_exit 2 pwsh -NoProfile -File "${REPO_ROOT}/dotfiles.ps1" --nonexistent-flag
assert_exit 2 bash "${REPO_ROOT}/dotfiles.sh" --install --update
assert_exit 2 pwsh -NoProfile -File "${REPO_ROOT}/dotfiles.ps1" --install --update
assert_exit 2 bash "${REPO_ROOT}/dotfiles.sh" --interactive --noconfirm --install
assert_exit 2 pwsh -NoProfile -File "${REPO_ROOT}/dotfiles.ps1" --interactive --noconfirm --install
assert_exit 2 bash "${REPO_ROOT}/dotfiles.sh" --dry-run --force --install
assert_exit 2 pwsh -NoProfile -File "${REPO_ROOT}/dotfiles.ps1" --dry-run --force --install

# 130: User declined prompt
rc_sh_130=0
echo "n" | bash "${REPO_ROOT}/dotfiles.sh" --uninstall > /dev/null 2>&1 || rc_sh_130=$?
[[ ${rc_sh_130} -eq 130 ]] || fail "Expected bash decline exit 130, got ${rc_sh_130}"

rc_ps1_130=0
echo "n" | pwsh -NoProfile -File "${REPO_ROOT}/dotfiles.ps1" --uninstall > /dev/null 2>&1 || rc_ps1_130=$?
[[ ${rc_ps1_130} -eq 130 ]] || fail "Expected pwsh decline exit 130, got ${rc_ps1_130}"
pass "Exit codes 0, 2, and 130 verified across bash and ps1"

# Concurrency Lock (D5): live lock blocks with exit 1; stale lock recovers with exit 0
printf 'pid=%s\nstart_time=%s\nstamp=%s\nscript=dotfiles.sh\n' "$$" "$(date +%s)" "${FIXED_STAMP}" > "${DRY_CACHE}/dotfiles.lock"
assert_exit 1 bash "${REPO_ROOT}/dotfiles.sh" --install --dry-run
assert_exit 1 pwsh -NoProfile -File "${REPO_ROOT}/dotfiles.ps1" --install --dry-run

# Stale lock (non-existent PID 999999)
printf 'pid=999999\nstart_time=1000\nstamp=%s\nscript=dotfiles.sh\n' "${FIXED_STAMP}" > "${DRY_CACHE}/dotfiles.lock"
assert_exit 0 pwsh -NoProfile -File "${REPO_ROOT}/dotfiles.ps1" --install --dry-run
pass "Concurrency lock (D5) live rejection (exit 1) and stale lock recovery (exit 0) verified"

printf '\n=== ALL VERIFICATION CHECKS PASSED ===\n'
exit 0

#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Zuper-Design · Git Bootstrapper (macOS bash)
#  File: git-script.sh
# ============================================================

BRANCH_NAME=""
FORCE_PUSH="false"
SSH_KEY_PATH=""   # resolved during setup_ssh_key

# -----------------------------
# Pretty output helpers
# -----------------------------
hr () {
  echo "────────────────────────────────────────────"
}

h3 () {
  echo
  hr
  echo "  $1"
  hr
}

banner () {
  echo
  echo "════════════════════════════════════════════"
  echo "  Zuper-Design · Git Setup"
  echo "════════════════════════════════════════════"
}

usage () {
  cat <<'EOF'

────────────────────────────────
  -b, --branch=NAME   Branch to use
  -f, --force        Force push (--force-with-lease)
  -h, --help         Show help

Examples:
  bash git-script.sh
  bash git-script.sh --branch=feature/landing
  bash git-script.sh -f --branch=Main

EOF
}

parse_args () {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch=*)
        BRANCH_NAME="${1#*=}"
        shift
        ;;
      --branch)
        BRANCH_NAME="${2:-}"
        shift 2
        ;;
      -b)
        BRANCH_NAME="${2:-}"
        shift 2
        ;;
      -f|--force)
        FORCE_PUSH="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "❌ Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  if [[ -n "${BRANCH_NAME}" ]]; then
    BRANCH_NAME="$(echo "${BRANCH_NAME}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [[ -z "${BRANCH_NAME}" ]]; then
      echo "❌ Branch name cannot be empty."
      exit 1
    fi
  fi
}

prompt_yes_no () {
  local question="${1}"
  local default="${2:-Y}"
  local reply

  while true; do
    if [[ "$default" == "Y" ]]; then
      read -r -p "${question} [Y/n]: " reply || true
      reply="${reply:-Y}"
    else
      read -r -p "${question} [y/N]: " reply || true
      reply="${reply:-N}"
    fi

    case "${reply}" in
      Y|y) return 0 ;;
      N|n) return 1 ;;
      *) echo "Please answer Y or N." ;;
    esac
  done
}

require_git () {
  if ! command -v git >/dev/null 2>&1; then
    echo "❌ Git is not installed. Install Xcode Command Line Tools:"
    echo "   xcode-select --install"
    exit 1
  fi
}

init_repo_if_needed () {
  h3 "📦 Repository Setup"

  if [[ -d ".git" ]]; then
    echo "✅ Git repo already exists in this folder."
  else
    echo "🧱 Initializing git repo..."
    git init
  fi
}

ensure_gitignore_node_modules () {
  h3 "🛡️  .gitignore Safety"
  if [[ ! -f ".gitignore" ]]; then
    echo "🧩 No .gitignore found. Creating one..."
    cat > .gitignore <<'EOF'
# Dependencies
node_modules/

# Build outputs
dist/
build/
out/
.next/
.nuxt/

# Logs
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*
*.log

# OS / Editor
.DS_Store
.vscode/
.idea/

# Env files
.env
.env.*
EOF
    echo "✅ Created .gitignore (includes node_modules/)."
    return 0
  fi

  if grep -Eq '^[[:space:]]*node_modules/?[[:space:]]*$' ".gitignore"; then
    echo "✅ .gitignore already ignores node_modules/."
  else
    echo "⚠️  .gitignore exists but does not ignore node_modules/."
    if prompt_yes_no "Add 'node_modules/' to .gitignore now?" "Y"; then
      tail -c 1 ".gitignore" | read -r _ || echo >> ".gitignore"
      echo "" >> ".gitignore"
      echo "# Dependencies" >> ".gitignore"
      echo "node_modules/" >> ".gitignore"
      echo "✅ Added node_modules/ to .gitignore."
    else
      echo "⚠️  You may accidentally commit node_modules."
    fi
  fi
}

warn_if_node_modules_tracked () {
  if git ls-files -z | tr '\0' '\n' | grep -qE '^node_modules/'; then
    echo "🚨 node_modules appears to be TRACKED by git already."
    echo "   This usually happens if .gitignore was added after committing."
    if prompt_yes_no "Remove node_modules from tracking (keeps files on disk)?" "Y"; then
      git rm -r --cached node_modules >/dev/null 2>&1 || true
      echo "✅ Removed node_modules from git index (cached)."
      echo "   It will be excluded going forward due to .gitignore."
    else
      echo "⚠️  node_modules tracked. This will bloat the repo."
    fi
  fi
}

ensure_identity () {
  h3 "👤 Git Identity"

  local name email
  name="$(git config user.name || true)"
  email="$(git config user.email || true)"

  if [[ -n "${name}" ]]; then
    echo "👤 Current git user.name (repo): ${name}"
    if ! prompt_yes_no "Is this correct?" "Y"; then
      name=""
    fi
  fi

  if [[ -n "${email}" ]]; then
    echo "📧 Current git user.email (repo): ${email}"
    if ! prompt_yes_no "Is this correct?" "Y"; then
      email=""
    fi
  fi

  if [[ -z "${name}" ]]; then
    read -r -p "Enter your full name (e.g. First Last): " name
    if [[ -z "${name}" ]]; then
      echo "❌ Name cannot be empty."
      exit 1
    fi
    git config user.name "${name}"
  fi

  if [[ -z "${email}" ]]; then
    read -r -p "Enter your work email (e.g. username@zuper.co): " email
    if [[ -z "${email}" ]]; then
      echo "❌ Email cannot be empty."
      exit 1
    fi
    git config user.email "${email}"
  fi

  echo "✅ Using identity:"
  echo "   user.name  = $(git config user.name)"
  echo "   user.email = $(git config user.email)"
}

setup_signoff_helpers () {
  h3 "✍️  Commit Sign-off Helpers"

  git config alias.c  'commit -s'
  git config alias.ci 'commit -s'
  echo "✅ Sign-off helpers added:"
  echo "   Use: git ci -m \"message\""
}

get_current_branch () {
  local b=""
  b="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "${b}" == "HEAD" ]]; then
    echo ""
  else
    echo "${b}"
  fi
}

choose_branch () {
  h3 "🌿 Branch Selection"

  local default_branch="Main"
  local picked=""
  local current_branch=""
  local has_commits="false"

  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    has_commits="true"
    current_branch="$(get_current_branch)"
  fi

  if [[ -n "${BRANCH_NAME}" ]]; then
    picked="${BRANCH_NAME}"
  else
    if [[ "${has_commits}" == "true" ]]; then
      if [[ -n "${current_branch}" ]]; then
        echo "🌿 Detected current branch: ${current_branch}"
        read -r -p "Branch to use [${current_branch}] (Enter = push same, or type new): " picked || true
        picked="${picked:-$current_branch}"
      else
        read -r -p "Enter branch name to use [${default_branch}]: " picked || true
        picked="${picked:-$default_branch}"
      fi
    else
      read -r -p "Enter branch name to use [${default_branch}]: " picked || true
      picked="${picked:-$default_branch}"
    fi

    picked="$(echo "${picked}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  fi

  if [[ -z "${picked}" ]]; then
    echo "❌ Branch name cannot be empty."
    exit 1
  fi

  BRANCH_NAME="${picked}"
  echo "✅ Using branch: ${BRANCH_NAME}"
}

checkout_branch () {
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

  if [[ "${current_branch}" == "HEAD" ]]; then
    return 0
  fi

  if [[ -z "${current_branch}" ]]; then
    return 0
  fi

  if [[ "${current_branch}" == "${BRANCH_NAME}" ]]; then
    echo "✅ Already on branch '${BRANCH_NAME}'."
    return 0
  fi

  if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
    echo "🔀 Switching to existing local branch '${BRANCH_NAME}'..."
    git checkout "${BRANCH_NAME}"
    return 0
  fi

  if git ls-remote --exit-code --heads origin "${BRANCH_NAME}" >/dev/null 2>&1; then
    echo "🔀 Creating local branch '${BRANCH_NAME}' tracking origin/${BRANCH_NAME}..."
    git fetch origin "${BRANCH_NAME}" >/dev/null 2>&1 || true
    git checkout -b "${BRANCH_NAME}" "origin/${BRANCH_NAME}"
  else
    echo "🆕 Creating new branch '${BRANCH_NAME}'..."
    git checkout -b "${BRANCH_NAME}"
  fi
}

ensure_initial_commit () {
  h3 "📝 Commit"

  local has_commits="false"
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    has_commits="true"
  fi

  git add -A

  if [[ "${has_commits}" == "false" ]]; then
    echo "📝 Creating initial commit..."
    git commit -s -m "Initial commit"

    local current_branch
    current_branch="$(git rev-parse --abbrev-ref HEAD)"
    if [[ "${current_branch}" != "${BRANCH_NAME}" ]]; then
      git branch -m "${BRANCH_NAME}"
    fi
  else
    if git diff --cached --quiet; then
      echo "ℹ️ No new changes to commit."
    else
      echo "📝 Committing staged changes..."
      git commit -s -m "Update"
    fi
  fi
}

# ============================================================
#  SSH KEY SETUP
# ============================================================

# Ensure ssh-agent is running and return the key path loaded into it.
# Sets the global SSH_KEY_PATH.
setup_ssh_key () {
  h3 "🔑 SSH Key Setup"

  local ssh_dir="${HOME}/.ssh"
  local config_file="${ssh_dir}/config"
  mkdir -p "${ssh_dir}"
  chmod 700 "${ssh_dir}"

  # ── 1. Look for an existing key ──────────────────────────
  local existing_key=""
  for candidate in \
    "${ssh_dir}/id_ed25519" \
    "${ssh_dir}/id_rsa" \
    "${ssh_dir}/id_ecdsa" \
    "${ssh_dir}/id_zuper"
  do
    if [[ -f "${candidate}" ]]; then
      existing_key="${candidate}"
      break
    fi
  done

  if [[ -n "${existing_key}" ]]; then
    echo "🔑 Found existing SSH key: ${existing_key}"
    if prompt_yes_no "Use this key for GitHub auth?" "Y"; then
      SSH_KEY_PATH="${existing_key}"
    else
      existing_key=""   # fall through to generate
    fi
  fi

  # ── 2. Generate a new key if none chosen ─────────────────
  if [[ -z "${SSH_KEY_PATH}" ]]; then
    local email
    email="$(git config user.email 2>/dev/null || true)"
    if [[ -z "${email}" ]]; then
      read -r -p "Enter your work email for the SSH key: " email
    fi

    local key_file="${ssh_dir}/id_zuper_ed25519"
    echo "🔐 Generating new ed25519 SSH key..."
    echo "   → ${key_file}"
    ssh-keygen -t ed25519 -C "${email}" -f "${key_file}" -N ""
    SSH_KEY_PATH="${key_file}"
    echo "✅ Key generated."
  fi

  # ── 3. Write ~/.ssh/config block for github.com ──────────
  local config_block
  config_block="$(cat <<EOF

# Zuper-Design – added by git-script.sh
Host github.com
  HostName github.com
  User git
  IdentityFile ${SSH_KEY_PATH}
  IdentitiesOnly yes
  AddKeysToAgent yes
EOF
)"

  if [[ ! -f "${config_file}" ]] || ! grep -q "IdentityFile ${SSH_KEY_PATH}" "${config_file}"; then
    echo "${config_block}" >> "${config_file}"
    chmod 600 "${config_file}"
    echo "✅ SSH config updated: ${config_file}"
  else
    echo "✅ SSH config already has an entry for this key."
  fi

  # ── 4. Start ssh-agent and load the key ──────────────────
  # macOS: use the system Keychain agent; fallback to manual agent start.
  if [[ "$(uname -s)" == "Darwin" ]]; then
    # macOS ssh-agent is managed by launchd; just add the key via Keychain
    ssh-add --apple-use-keychain "${SSH_KEY_PATH}" 2>/dev/null \
      || ssh-add "${SSH_KEY_PATH}" 2>/dev/null \
      || true
  else
    # Linux / other: start agent if not running
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
      eval "$(ssh-agent -s)" >/dev/null
    fi
    ssh-add "${SSH_KEY_PATH}" 2>/dev/null || true
  fi

  echo "✅ SSH key loaded into agent: ${SSH_KEY_PATH}"

  # ── 5. Show public key + instructions ────────────────────
  local pub_key_file="${SSH_KEY_PATH}.pub"
  echo
  echo "════════════════════════════════════════════"
  echo "  📋 Your SSH public key (copy this entire line):"
  echo "════════════════════════════════════════════"
  cat "${pub_key_file}"
  echo "════════════════════════════════════════════"
  echo
  echo "  Add it to GitHub:"
  echo "  1. Open  → https://github.com/settings/ssh/new"
  echo "  2. Title → e.g. \"$(hostname -s) – Zuper Design\""
  echo "  3. Paste → the key above"
  echo "  4. Click → Add SSH key"
  echo
  echo "  To push to the zuper-design org, a member with"
  echo "  Owner/Admin access may also need to approve the key"
  echo "  under: https://github.com/orgs/zuper-design/sso"
  echo
  # Copy to clipboard on macOS silently
  if command -v pbcopy >/dev/null 2>&1; then
    cat "${pub_key_file}" | pbcopy
    echo "  ✂️  Public key copied to clipboard automatically."
    echo
  fi

  prompt_yes_no "Press Y once you've added the key to GitHub to continue" "Y" || {
    echo "❌ Aborted. Re-run the script after adding the key."
    exit 1
  }
}

# ============================================================
#  SSH CONNECTION TEST
# ============================================================

test_github_ssh () {
  h3 "🧪 Testing GitHub SSH Connection"

  local result exit_code
  # ssh -T exits with code 1 even on success ("Hi username!"), so capture both
  result="$(ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1)" || exit_code=$?

  if echo "${result}" | grep -q "^Hi "; then
    local gh_user
    gh_user="$(echo "${result}" | sed "s/^Hi //; s/!.*$//")"
    echo "✅ GitHub SSH auth confirmed. Logged in as: ${gh_user}"

    # Warn if the authenticated account isn't obviously a Zuper member
    if ! echo "${gh_user}" | grep -qi "zuper"; then
      echo
      echo "  ⚠️  Heads-up: your GitHub user '${gh_user}' doesn't look like"
      echo "     a Zuper account. Make sure this account has access to"
      echo "     github.com/zuper-design before pushing."
    fi
  else
    echo "❌ SSH handshake failed. GitHub responded:"
    echo "   ${result}"
    echo
    echo "  Possible causes:"
    echo "  • Key not yet added to GitHub (https://github.com/settings/ssh/new)"
    echo "  • Key not authorized for the zuper-design org"
    echo "    (https://github.com/orgs/zuper-design/sso)"
    echo "  • Key not loaded in ssh-agent"
    echo
    if prompt_yes_no "Retry SSH test after fixing the above?" "Y"; then
      test_github_ssh
    else
      echo "❌ Aborting. Fix SSH auth and re-run the script."
      exit 1
    fi
  fi
}

# ============================================================
#  URL NORMALIZATION  (HTTPS → SSH)
# ============================================================

# Converts https://github.com/org/repo.git  →  git@github.com:org/repo.git
# Leaves git@github.com:... URLs untouched.
convert_url_to_ssh () {
  local url="${1}"
  if echo "${url}" | grep -qE '^https://github\.com/'; then
    # Strip protocol + host, keep path
    local path
    path="$(echo "${url}" | sed 's|^https://github\.com/||')"
    echo "git@github.com:${path}"
  else
    echo "${url}"
  fi
}

# ============================================================
#  PUSH
# ============================================================

set_remote_and_push () {
  h3 "🚀 Push to GitHub"

  local remote_url push_flags
  remote_url="$(git remote get-url origin 2>/dev/null || true)"

  if [[ -n "${remote_url}" ]]; then
    echo "🔗 Remote 'origin' already set to:"
    echo "   ${remote_url}"
    if ! prompt_yes_no "Do you want to keep this remote?" "Y"; then
      read -r -p "Paste the correct repo URL (HTTPS or SSH): " remote_url
      git remote set-url origin "${remote_url}"
    fi
  else
    read -r -p "Paste the GitHub repo URL to push to (HTTPS or SSH): " remote_url
    if [[ -z "${remote_url}" ]]; then
      echo "❌ Repo URL cannot be empty."
      exit 1
    fi
    git remote add origin "${remote_url}"
  fi

  # ── Normalise to SSH ──────────────────────────────────────
  local ssh_url
  ssh_url="$(convert_url_to_ssh "${remote_url}")"
  if [[ "${ssh_url}" != "${remote_url}" ]]; then
    echo "🔄 Converting remote from HTTPS → SSH:"
    echo "   ${ssh_url}"
    git remote set-url origin "${ssh_url}"
  fi

  git fetch origin >/dev/null 2>&1 || true
  checkout_branch

  push_flags="-u"
  if [[ "${FORCE_PUSH}" == "true" ]]; then
    echo "⚠️  Force push enabled (using --force-with-lease)."
    push_flags="${push_flags} --force-with-lease"
  fi

  echo "🚀 Pushing to origin (${BRANCH_NAME})..."
  # shellcheck disable=SC2086
  git push ${push_flags} origin "${BRANCH_NAME}"
  echo "✅ Done! Your project is now pushed."
}

# ============================================================
#  MAIN
# ============================================================

main () {
  parse_args "$@"

  banner
  echo "📁 Folder: $(pwd)"

  require_git
  init_repo_if_needed

  ensure_gitignore_node_modules
  warn_if_node_modules_tracked

  choose_branch
  ensure_identity
  setup_signoff_helpers

  # SSH must come after identity (key comment uses email)
  setup_ssh_key
  test_github_ssh

  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
      git checkout "${BRANCH_NAME}"
    else
      git checkout -b "${BRANCH_NAME}"
    fi
  fi

  ensure_initial_commit
  set_remote_and_push

  h3 "✅ Next time"
  echo "  git add -A"
  echo "  git ci -m \"message\""
  echo "  git push"
  echo
  echo "Or run again with:"
  echo "  bash git-script.sh --branch=feature/my-branch"
  echo "  bash git-script.sh -f --branch=Main"
}

main "$@"

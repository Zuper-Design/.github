#!/usr/bin/env bash
set -euo pipefail

# --------------------------------
# Zuper-Design Git bootstrapper
# File: git-script.sh
# macOS bash (no dependencies)
# --------------------------------

BRANCH_NAME=""
FORCE_PUSH="false"

usage () {
  cat <<'EOF'
Usage:
  bash git-script.sh [--branch=<name>] [-b <name>] [-f|--force] [-h|--help]

Options:
  --branch=<name>     Branch name to checkout/push (skips prompt)
  -b <name>           Same as --branch
  -f, --force         Force push (uses --force-with-lease)
  -h, --help          Show help
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
    # trim leading/trailing whitespace
    BRANCH_NAME="$(echo "${BRANCH_NAME}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [[ -z "${BRANCH_NAME}" ]]; then
      echo "❌ Branch name cannot be empty."
      exit 1
    fi
  fi
}

prompt_yes_no () {
  # usage: prompt_yes_no "Question?" "Y"
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
  if [[ -d ".git" ]]; then
    echo "✅ Git repo already exists in this folder."
  else
    echo "🧱 Initializing git repo..."
    git init
  fi
}

ensure_gitignore_node_modules () {
  # Ensure .gitignore exists and contains node_modules/
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

  # .gitignore exists: ensure node_modules is ignored
  if grep -Eq '^[[:space:]]*node_modules/?[[:space:]]*$' ".gitignore"; then
    echo "✅ .gitignore already ignores node_modules/."
  else
    echo "⚠️  .gitignore exists but does not ignore node_modules/."
    if prompt_yes_no "Add 'node_modules/' to .gitignore now?" "Y"; then
      # Add a newline if file doesn't end with one, then append
      tail -c 1 ".gitignore" | read -r _ || echo >> ".gitignore"
      echo "" >> ".gitignore"
      echo "# Dependencies" >> ".gitignore"
      echo "node_modules/" >> ".gitignore"
      echo "✅ Added node_modules/ to .gitignore."
    else
      echo "⚠️  Skipping. You may accidentally commit node_modules."
    fi
  fi
}

warn_if_node_modules_tracked () {
  # If node_modules is already tracked, warn and optionally untrack it.
  if git ls-files -z | tr '\0' '\n' | grep -qE '^node_modules/'; then
    echo "🚨 node_modules appears to be TRACKED by git already."
    echo "   This usually happens if .gitignore was added after committing."
    if prompt_yes_no "Remove node_modules from tracking (keeps files on disk)?" "Y"; then
      git rm -r --cached node_modules >/dev/null 2>&1 || true
      echo "✅ Removed node_modules from git index (cached)."
      echo "   It will be excluded going forward due to .gitignore."
    else
      echo "⚠️  Leaving node_modules tracked. This will bloat the repo."
    fi
  fi
}

ensure_identity () {
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
  # Repo-local aliases that always commit with -s
  git config alias.c  'commit -s'
  git config alias.ci 'commit -s'
  echo "✅ Sign-off helpers added:"
  echo "   Use: git ci -m \"message\""
}

choose_branch () {
  local default_branch="Main"
  local picked=""

  if [[ -n "${BRANCH_NAME}" ]]; then
    picked="${BRANCH_NAME}"
  else
    read -r -p "Enter branch name to use [${default_branch}]: " picked || true
    picked="${picked:-$default_branch}"
    picked="$(echo "${picked}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  fi

  if [[ -z "${picked}" ]]; then
    echo "❌ Branch name cannot be empty."
    exit 1
  fi

  BRANCH_NAME="${picked}"
  echo "🌿 Using branch: ${BRANCH_NAME}"
}

checkout_branch () {
  # Make sure we are on the selected branch every time this script runs.
  # Works for fresh repos and existing repos.
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

  # In a brand new repo with no commits, HEAD is not on a branch yet.
  if [[ "${current_branch}" == "HEAD" || -z "${current_branch}" ]]; then
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

  # If origin has the branch, track it (best effort).
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
  local has_commits="false"
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    has_commits="true"
  fi

  git add -A

  if [[ "${has_commits}" == "false" ]]; then
    echo "📝 Creating initial commit..."
    git commit -s -m "Initial commit"

    # Rename the first branch to the selected branch (common in brand-new repos).
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

set_remote_and_push () {
  local remote_url push_flags
  remote_url="$(git remote get-url origin 2>/dev/null || true)"

  if [[ -n "${remote_url}" ]]; then
    echo "🔗 Remote 'origin' already set to:"
    echo "   ${remote_url}"
    if ! prompt_yes_no "Do you want to keep this remote?" "Y"; then
      read -r -p "Paste the correct repo URL: " remote_url
      git remote set-url origin "${remote_url}"
    fi
  else
    read -r -p "Paste the GitHub repo URL to push to: " remote_url
    if [[ -z "${remote_url}" ]]; then
      echo "❌ Repo URL cannot be empty."
      exit 1
    fi
    git remote add origin "${remote_url}"
  fi

  # Now that origin exists, ensure we are on the chosen branch (and track remote if applicable).
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

main () {
  parse_args "$@"

  echo "--------------------------------------------"
  echo "Zuper-Design Git Setup (macOS)"
  echo "Folder: $(pwd)"
  echo "--------------------------------------------"

  require_git
  init_repo_if_needed

  # Safety first: prevent accidental node_modules commits
  ensure_gitignore_node_modules
  warn_if_node_modules_tracked

  choose_branch
  ensure_identity
  setup_signoff_helpers

  # If repo already has commits, hop to the chosen branch before committing
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    # origin might not exist yet, so only do local switching here.
    if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
      git checkout "${BRANCH_NAME}"
    else
      # create from current HEAD (doesn't touch remote)
      git checkout -b "${BRANCH_NAME}"
    fi
  fi

  ensure_initial_commit
  set_remote_and_push

  echo
  echo "Next time:"
  echo "  git add -A"
  echo "  git ci -m \"message\""
  echo "  git push"
  echo
  echo "Or run again with:"
  echo "  bash git-script.sh --branch=feature/my-branch"
  echo "  bash git-script.sh -f --branch=Main"
}

main "$@"

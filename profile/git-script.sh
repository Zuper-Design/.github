#!/usr/bin/env bash
set -euo pipefail

# --------------------------------
# Zuper-Design Git bootstrapper
# File: git-script.sh
# macOS bash (no dependencies)
# --------------------------------

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

ensure_main_branch () {
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

  if [[ "${current_branch}" == "HEAD" || -z "${current_branch}" ]]; then
    return 0
  fi

  if [[ "${current_branch}" != "main" ]]; then
    if prompt_yes_no "Your current branch is '${current_branch}'. Rename to 'main'?" "Y"; then
      git branch -m main
    fi
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
    local current_branch
    current_branch="$(git rev-parse --abbrev-ref HEAD)"
    if [[ "${current_branch}" != "main" ]]; then
      git branch -m main
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
  local remote_url
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

  echo "🚀 Pushing to origin (main)..."
  git push -u origin main
  echo "✅ Done! Your project is now pushed."
}

main () {
  echo "--------------------------------------------"
  echo "Zuper-Design Git Setup (macOS)"
  echo "Folder: $(pwd)"
  echo "--------------------------------------------"

  require_git
  init_repo_if_needed

  # Safety first: prevent accidental node_modules commits
  ensure_gitignore_node_modules
  warn_if_node_modules_tracked

  ensure_identity
  setup_signoff_helpers
  ensure_main_branch
  ensure_initial_commit
  set_remote_and_push

  echo
  echo "Next time:"
  echo "  git add -A"
  echo "  git ci -m \"message\""
  echo "  git push"
}

main "$@"

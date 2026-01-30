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

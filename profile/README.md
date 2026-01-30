# Zuper-Design — Add your project to GitHub (Cursor + macOS)

This guide helps you initialize a Git repo from a folder and push it to the **Zuper-Design** GitHub org.

## 1) Open the project folder in Cursor
- Open Cursor
- `File → Open Folder…` and select your project folder

## 2) Open Cursor Terminal
- In Cursor: `Terminal → New Terminal`

## 3) Run the setup script (recommended)
From the terminal (you should already be inside the project folder), run:

```bash
curl -fsSL https://raw.githubusercontent.com/Zuper-Design/.github/refs/heads/main/profile/git-script.sh -o git-script.sh
bash git-script.sh

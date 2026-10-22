#!/bin/bash
# Przywraca właściwe nazwy plików (z kropką) i tworzy repozytorium Git.
# Uruchomienie:  bash przygotuj.sh
set -e
cd "$(dirname "$0")"
[ -d github ]       && mv github .github
[ -f gitignore ]    && mv gitignore .gitignore
[ -f dockerignore ] && mv dockerignore .dockerignore
[ -f env.example ]  && mv env.example .env.example
[ -f .env ] || cp .env.example .env

if [ ! -d .git ]; then
  git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main; }
  git add .
  git -c user.name="${GIT_NAME:-Student16}" -c user.email="${GIT_EMAIL:-student16@example.com}" \
      commit -q -m "Rejestr serwerów i usług IT — wersja 1.0"
fi

echo "Gotowe. Pliki (także ukryte):"
ls -la
echo
echo "Pipeline:"; ls .github/workflows

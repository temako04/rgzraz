#!/usr/bin/env bash
set -euo pipefail

# Скрипт генерирует changelog.md на основе коммитов
# с момента последнего git-тега (релиза).
#
# Формат:
# ## [v1.2.0] - 2025-01-01
# - Описание коммита [abc123](https://github.com/user/repo/commit/abc123)
#
# Запуск:
# ./scripts/generate_changelog.sh v1.2.0

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Использование: $0 vX.Y.Z"
  exit 1
fi

DATE="$(date +%F)"
CHANGELOG_FILE="changelog.md"

# --- Поиск последнего тега ---
LAST_TAG=""
if git describe --tags --abbrev=0 >/dev/null 2>&1; then
  LAST_TAG="$(git describe --tags --abbrev=0)"
fi

# --- Определяем GitHub репозиторий ---
REMOTE_URL="$(git config --get remote.origin.url || true)"
BASE_URL=""

if [[ "$REMOTE_URL" == git@github.com:* ]]; then
  REPO="${REMOTE_URL#git@github.com:}"
  REPO="${REPO%.git}"
  BASE_URL="https://github.com/${REPO}"
elif [[ "$REMOTE_URL" == https://github.com/* ]]; then
  BASE_URL="${REMOTE_URL%.git}"
fi

# --- Получаем коммиты ---
RANGE=""
if [[ -n "$LAST_TAG" ]]; then
  RANGE="${LAST_TAG}..HEAD"
fi

COMMITS="$(git log ${RANGE:+$RANGE} --pretty=format:'%h|%s')"

if [[ -z "$COMMITS" ]]; then
  echo "Нет коммитов для changelog."
  exit 0
fi

# --- Создаём changelog.md если его нет ---
if [[ ! -f "$CHANGELOG_FILE" ]]; then
  echo "# Changelog" > "$CHANGELOG_FILE"
  echo "" >> "$CHANGELOG_FILE"
fi

SECTION_HEADER="## [${VERSION}] - ${DATE}"

# Не добавляем дубликат версии
if grep -qE "^## \[${VERSION}\] - " "$CHANGELOG_FILE"; then
  echo "Версия ${VERSION} уже есть в changelog."
  exit 0
fi

# --- Формируем список изменений ---
SECTION_BODY=""
while IFS='|' read -r HASH SUBJECT; do
  if [[ -n "$BASE_URL" ]]; then
    SECTION_BODY+="- ${SUBJECT} [${HASH}](${BASE_URL}/commit/${HASH})"$'\n'
  else
    SECTION_BODY+="- ${SUBJECT} [${HASH}]"$'\n'
  fi
done <<< "$COMMITS"

# --- Вставляем секцию в начало файла ---
TMP_FILE="$(mktemp)"
{
  head -n 2 "$CHANGELOG_FILE"
  echo "${SECTION_HEADER}"
  echo "${SECTION_BODY}"
  tail -n +3 "$CHANGELOG_FILE"
} > "$TMP_FILE"
mv "$TMP_FILE" "$CHANGELOG_FILE"

echo "Changelog обновлён: ${VERSION}"

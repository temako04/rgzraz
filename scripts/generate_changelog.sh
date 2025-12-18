#!/usr/bin/env bash
set -euo pipefail

# Скрипт формирует changelog.md из коммитов между предыдущим тегом и текущим тегом.
# Текущий тег (версия) передаётся аргументом.
#
# Формат по заданию:
#   ## [Версия] - Дата
#   - Описание коммита [abc123](https://github.com/.../commit/abc123)

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Использование: $0 <версия-тег>   (пример: $0 1.1.1)"
  exit 1
fi

DATE="$(date +%F)"
CHANGELOG_FILE="changelog.md"

# --- Определяем GitHub base URL (для ссылок на коммиты) ---
REMOTE_URL="$(git config --get remote.origin.url || true)"
BASE_URL=""

if [[ "$REMOTE_URL" == git@github.com:* ]]; then
  REPO="${REMOTE_URL#git@github.com:}"
  REPO="${REPO%.git}"
  BASE_URL="https://github.com/${REPO}"
elif [[ "$REMOTE_URL" == https://github.com/* ]]; then
  BASE_URL="${REMOTE_URL%.git}"
fi

# --- Проверяем, что тег существует локально ---
if ! git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null; then
  echo "Ошибка: тег '${VERSION}' не найден. Убедись, что теги подтянуты: git fetch --tags"
  exit 1
fi

# --- Находим предыдущий тег относительно текущего (по истории коммитов) ---
# Берём коммит тега
TAG_COMMIT="$(git rev-list -n 1 "${VERSION}")"
PREV_TAG=""
# Пытаемся найти ближайший тег до текущего тега
if git describe --tags --abbrev=0 "${TAG_COMMIT}^" >/dev/null 2>&1; then
  PREV_TAG="$(git describe --tags --abbrev=0 "${TAG_COMMIT}^")"
fi

# --- Формируем диапазон коммитов ---
# Если предыдущего тега нет — берём всё до текущего тега
RANGE=""
if [[ -n "$PREV_TAG" ]]; then
  RANGE="${PREV_TAG}..${VERSION}"
else
  RANGE="${VERSION}"
fi

# --- Получаем список коммитов для секции ---
# Исключаем автокоммиты changelog и skip ci (чтобы не засоряли)
COMMITS="$(git log ${RANGE} --pretty=format:'%h|%s' \
  | grep -v 'Update changelog' \
  | grep -v '\[skip ci\]' || true)"

if [[ -z "$COMMITS" ]]; then
  echo "Нет коммитов для changelog в диапазоне: ${RANGE}"
  exit 0
fi

# --- Создаём файл changelog.md, если его нет ---
if [[ ! -f "$CHANGELOG_FILE" ]]; then
  printf "# Changelog\n\n" > "$CHANGELOG_FILE"
fi

SECTION_HEADER="## [${VERSION}] - ${DATE}"

# Не добавляем дубликаты секций
if grep -qE "^## \[${VERSION}\] - " "$CHANGELOG_FILE"; then
  echo "Секция для версии ${VERSION} уже существует. Пропускаю."
  exit 0
fi

SECTION_BODY=""
while IFS='|' read -r HASH SUBJECT; do
  [[ -z "${HASH}" || -z "${SUBJECT}" ]] && continue

  if [[ -n "$BASE_URL" ]]; then
    SECTION_BODY+="- ${SUBJECT} [${HASH}](${BASE_URL}/commit/${HASH})"$'\n'
  else
    SECTION_BODY+="- ${SUBJECT} [${HASH}]"$'\n'
  fi
done <<< "$COMMITS"

# --- Вставляем новую секцию в начало (сразу после "# Changelog") ---
TMP_FILE="$(mktemp)"
{
  head -n 2 "$CHANGELOG_FILE"
  echo "${SECTION_HEADER}"
  echo "${SECTION_BODY}"
  tail -n +3 "$CHANGELOG_FILE"
} > "$TMP_FILE"
mv "$TMP_FILE" "$CHANGELOG_FILE"

echo "Changelog обновлён для версии ${VERSION} (диапазон: ${RANGE})"

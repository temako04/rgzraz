#!/usr/bin/env bash
set -euo pipefail

# Скрипт формирует changelog.md на основе сообщений коммитов.
# Алгоритм:
# 1) Находит последний тег (релиз) и берёт коммиты после него.
# 2) Генерирует новую секцию в changelog.md: "## [Версия] - Дата".
# 3) Добавляет строки по коммитам: "- Сообщение [abc123](ссылка)"
#
# Запуск:
#   ./scripts/generate_changelog.sh v1.2.0

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Использование: $0 vX.Y.Z"
  exit 1
fi

DATE="$(date +%F)"
CHANGELOG_FILE="changelog.md"

# --- 1) Ищем последний тег (если есть) ---
LAST_TAG=""
if git describe --tags --abbrev=0 >/dev/null 2>&1; then
  LAST_TAG="$(git describe --tags --abbrev=0)"
fi

# --- 2) Определяем базовый URL GitHub репозитория для ссылок на коммиты ---
REMOTE_URL="$(git config --get remote.origin.url || true)"
BASE_URL=""

if [[ "$REMOTE_URL" == git@github.com:* ]]; then
  REPO="${REMOTE_URL#git@github.com:}"
  REPO="${REPO%.git}"
  BASE_URL="https://github.com/${REPO}"
elif [[ "$REMOTE_URL" == https://github.com/* ]]; then
  BASE_URL="${REMOTE_URL%.git}"
fi

# --- 3) Выбираем диапазон коммитов: от последнего тега до HEAD ---
RANGE=""
if [[ -n "$LAST_TAG" ]]; then
  RANGE="${LAST_TAG}..HEAD"
fi

# Берём коммиты: "короткий_хэш|сообщение"
# Дополнительно фильтруем автокоммиты changelog (чтобы не засоряли список изменений)
COMMITS="$(git log ${RANGE:+$RANGE} --pretty=format:'%h|%s' \
  | grep -v 'Update changelog' \
  | grep -v '\[skip ci\]' || true)"

if [[ -z "$COMMITS" ]]; then
  echo "Нет коммитов для формирования changelog (после фильтрации тоже пусто)."
  exit 0
fi

# --- 4) Создаём changelog.md, если его нет ---
if [[ ! -f "$CHANGELOG_FILE" ]]; then
  echo "# Changelog" > "$CHANGELOG_FILE"
  echo "" >> "$CHANGELOG_FILE"
fi

SECTION_HEADER="## [${VERSION}] - ${DATE}"

# Защита от дублирования одной и той же версии
if grep -qE "^## \[${VERSION}\] - " "$CHANGELOG_FILE"; then
  echo "Секция для версии ${VERSION} уже существует. Пропускаю."
  exit 0
fi

# --- 5) Формируем тело секции: список коммитов ---
SECTION_BODY=""
while IFS='|' read -r HASH SUBJECT; do
  # Пропускаем пустые строки (на всякий случай)
  [[ -z "${HASH}" || -z "${SUBJECT}" ]] && continue

  if [[ -n "$BASE_URL" ]]; then
    SECTION_BODY+="- ${SUBJECT} [${HASH}](${BASE_URL}/commit/${HASH})"$'\n'
  else
    SECTION_BODY+="- ${SUBJECT} [${HASH}]"$'\n'
  fi
done <<< "$COMMITS"

# --- 6) Вставляем секцию в начало файла (после заголовка) ---
TMP_FILE="$(mktemp)"
{
  head -n 2 "$CHANGELOG_FILE"
  echo "${SECTION_HEADER}"
  echo "${SECTION_BODY}"
  tail -n +3 "$CHANGELOG_FILE"
} > "$TMP_FILE"
mv "$TMP_FILE" "$CHANGELOG_FILE"

echo "Changelog обновлён: ${CHANGELOG_FILE} (версия ${VERSION})"

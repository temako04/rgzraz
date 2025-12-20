#!/usr/bin/env bash

VERSION="$1"
[[ -z "$VERSION" ]] && echo "Использование: $0 <версия>" && exit 1

DATE=$(date +%F)
CHANGELOG="changelog.md"

# Проверяем существование тега
git rev-parse "refs/tags/$VERSION" >/dev/null 2>&1 || {
    echo "Тег '$VERSION' не найден"
    exit 1
}

# Находим предыдущий тег
PREV_TAG=$(git describe --tags --abbrev=0 "$VERSION^" 2>/dev/null || true)

# Формируем диапазон коммитов
RANGE="$VERSION"
[[ -n "$PREV_TAG" ]] && RANGE="$PREV_TAG..$VERSION"

# Получаем коммиты с полным хэшем, автором и датой
COMMITS=$(git log "$RANGE" --pretty=format:"%H|%s|%an|%ad" --date=short | grep -v "Update changelog\|\[skip ci\]" || true)

[[ -z "$COMMITS" ]] && echo "Нет коммитов" && exit 0

# Создаём заголовок файла если нужно
[[ ! -f "$CHANGELOG" ]] && echo -e "# Changelog\n" > "$CHANGELOG"

# Проверяем дубликат версии
grep -q "^## \[$VERSION\]" "$CHANGELOG" && {
    echo "Версия $VERSION уже существует"
    exit 0
}

# Генерируем секцию changelog
SECTION_BODY=""
while IFS='|' read -r HASH SUBJECT; do
  [[ -z "${HASH}" || -z "${SUBJECT}" ]] && continue

  if [[ -n "$BASE_URL" ]]; then
    SECTION_BODY+="- ${SUBJECT} [${HASH}](${BASE_URL}/commit/${HASH})"$'\n'
  else
    SECTION_BODY+="- ${SUBJECT} [${HASH}]"$'\n'
  fi
done <<< "$COMMITS"

# Вставляем секцию после заголовка
sed -i "1a\\"$'\n'"$SECTION" "$CHANGELOG"

echo "Добавлена версия $VERSION в changelog"

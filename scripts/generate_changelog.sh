#!/usr/bin/env bash

VERSION="$1"
[[ -z "$VERSION" ]] && echo "Использование: $0 <версия>" && exit 1

CHANGELOG="changelog.md"

# Проверка тега
git rev-parse "refs/tags/$VERSION" >/dev/null 2>&1 || {
    echo "Тег '$VERSION' не найден"
    exit 1
}

# Предыдущий тег
PREV_TAG=$(git describe --tags --abbrev=0 "$VERSION^" 2>/dev/null || true)

# Диапазон коммитов
RANGE="$VERSION"
[[ -n "$PREV_TAG" ]] && RANGE="$PREV_TAG..$VERSION"

# Получаем коммиты
COMMITS=$(git log "$RANGE" --pretty=format:"%H|%s" | grep -v "Update changelog\|\[skip ci\]" || true)

[[ -z "$COMMITS" ]] && echo "Нет коммитов" && exit 0

# Создаем файл если нужно
[[ ! -f "$CHANGELOG" ]] && echo -e "# Changelog\n" > "$CHANGELOG"

# Проверяем дубликат
grep -q "^## \[$VERSION\]" "$CHANGELOG" && {
    echo "Версия $VERSION уже существует"
    exit 0
}

# Формируем changelog
SECTION="## [$VERSION] - $(date +%F)\n"
while IFS='|' read -r HASH MSG; do
    [[ -z "$HASH" ]] && continue
    SECTION+="- $MSG (https://github.com/temako04/rgzraz/commit/$HASH)\n"
done <<< "$COMMITS"
SECTION+="\n"

# Вставляем
sed -i "1a\\"$'\n'"$SECTION" "$CHANGELOG"

echo "Добавлена версия $VERSION в changelog"

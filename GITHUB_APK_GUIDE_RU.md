# ChessTeam Beta — загрузка на GitHub и APK

1. Создайте новый репозиторий на GitHub, например `ChessTeam-Beta`.
2. Загрузите в репозиторий содержимое этой папки. Файл `project.godot` должен лежать прямо в корне репозитория.
3. Откройте вкладку **Actions**.
4. Выберите **Build Android APK**.
5. Нажмите **Run workflow** → **Run workflow**.
6. Дождитесь окончания сборки.
7. Откройте завершившийся запуск workflow и скачайте artifact **team-chess-2x2-android**.
8. Внутри будет файл `TeamChess2x2.apk`.

Для создания GitHub Release можно создать тег вида `v0.1.0`. При отправке такого тега workflow автоматически прикрепит APK к Release.

Проект рассчитан на Godot 4.6; GitHub Actions использует Godot 4.6.3 stable.

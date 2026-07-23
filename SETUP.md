# Подключение Claude Code к проекту TikTok House Wars

Инструкция для Windows. Задача: сделать так, чтобы код жил в файлах на диске
(их правит Claude), а Roblox Studio получал изменения автоматически через Rojo.

---

## 0. Как это вообще работает

```
  Claude Code  →  правит .luau файлы в папке src/
                            ↓
                   rojo serve (локальный сервер, порт 34872)
                            ↓
                 плагин Rojo в Roblox Studio (кнопка Connect)
                            ↓
                    скрипты появляются в дереве игры
```

Важно понимать разделение:

| Что | Где живёт | Кто правит |
|---|---|---|
| Скрипты (`.luau`) | файлы в `src/` | Claude / редактор |
| Модели, карта, GUI, ассеты | внутри `.rbxl` в Studio | вы руками в Studio |

Claude **не видит** содержимое `.rbxl` — он не может посмотреть вашу карту,
модели мобов в `ServerStorage.Mobs` или точки маршрута `Workspace.MobPath`.
Про них ему нужно рассказывать словами (или показывать скриншот).
Скрипты Claude видит и правит полностью.

---

## 1. Установка инструментов

### 1.1 Rokit (менеджер тулчейна)

В проекте уже есть [rokit.toml](rokit.toml) — он описывает, какие версии
инструментов нужны. Сам Rokit нужно поставить один раз на систему.

Откройте PowerShell и выполните:

```powershell
irm https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | iex
```

После установки **закройте и откройте PowerShell заново** (чтобы обновился PATH)
и проверьте:

```powershell
rokit --version
```

### 1.2 Установка Rojo и Lune из rokit.toml

В папке проекта:

```powershell
cd "$env:USERPROFILE\Documents\Roblox Projects\TikTokHouseWars"
rokit install
```

Rokit прочитает `rokit.toml` и поставит:
- `rojo 7.7.0` — синхронизация файлов со Studio
- `lune 0.10.5` — запуск Luau-скриптов вне Roblox (для тестов/утилит)

Проверка:

```powershell
rojo --version
lune --version
```

Если команды не находятся — перезапустите терминал ещё раз.
Rokit кладёт шимы в `%USERPROFILE%\.rokit\bin`, эта папка должна быть в PATH.

### 1.3 Плагин Rojo для Roblox Studio

```powershell
rojo plugin install
```

Команда сама положит плагин в папку плагинов Studio. Если Studio была открыта —
перезапустите её. На панели **Plugins** появится вкладка **Rojo**.

Альтернатива: поставить плагин из Creator Store (искать «Rojo»), но версия
плагина должна совпадать по мажорной версии с `rojo` из `rokit.toml` (7.x).

---

## 2. Разрешения в Roblox Studio

Один раз на машину:

1. **File → Studio Settings → Security**
   - `Allow HTTP Requests` → **включить**
   - `Enable Loopback` (иногда `Allow loopback HTTP requests`) → **включить**
2. **File → Game Settings → Security**
   - `Enable Studio Access to API Services` → включить, если планируете
     DataStore (сохранение прогресса игроков).

Без `Allow HTTP Requests` плагин Rojo не сможет достучаться до `localhost:34872`.

---

## 3. Первый запуск синка

### 3.1 Запустить сервер Rojo

В терминале, в папке проекта:

```powershell
rojo serve
```

Вывод должен быть примерно такой:

```
Rojo server listening:
  Address: localhost
  Port:    34872
```

**Это окно терминала нужно оставить открытым** на всё время работы.
Остановить — `Ctrl+C`.

### 3.2 Подключиться из Studio

1. Откройте свой `.rbxl` (или новое пустое место — см. п. 3.3).
2. Вкладка **Plugins → Rojo → Connect**.
3. Адрес по умолчанию `localhost:34872` — нажать **Connect**.

Если всё верно, в дереве Explorer появятся:

- `ReplicatedStorage/Shared` → `Config`, `MobConfig`
- `ServerScriptService/Server` → `init` (Script), `MobSpawner`
- `StarterPlayer/StarterPlayerScripts/Client` → `init`

Теперь любое изменение файла на диске мгновенно применяется в Studio.

### 3.3 Если места ещё нет

Можно сгенерировать пустой `.rbxlx` прямо из проекта:

```powershell
rojo build --output TikTokHouseWars.rbxlx
```

Открыть его в Studio, дальше подключиться как в п. 3.2. Собранные файлы
не коммитятся — они уже в [.gitignore](.gitignore).

---

## 4. Что делать в самой Studio (Claude это сделать не может)

Скрипт [MobSpawner.server.luau](src/server/MobSpawner.server.luau) ожидает
готовую структуру на карте:

1. **`ServerStorage/Mobs`** — папка `Folder` с именем `Mobs`.
   Внутрь положить модели мобов. Имена моделей должны совпадать один-в-один
   с `id` из [MobConfig.luau](src/shared/MobConfig.luau):
   `Noob`, `Guest`, `Bacon`, `Boss`.
   У каждой модели обязателен **PrimaryPart** (иначе моб не поедет).

2. **`Workspace/MobPath`** — папка `Folder` с именем `MobPath`.
   Внутрь — части (`Part`) с именами `1`, `2`, `3`, … Это точки маршрута,
   по ним моб идёт по порядку. Части удобно сделать `Anchored = true`,
   `CanCollide = false`, `Transparency = 1`.

3. **`Workspace/ActiveMobs`** создаётся скриптом сам — руками не нужно.

После этого нажмите **Play** — мобы начнут появляться раз в
`MobConfig.SPAWN_INTERVAL` секунду и ехать по точкам.

---

## 5. Ежедневный цикл работы

```powershell
# 1. Терминал №1 — держим открытым
cd "$env:USERPROFILE\Documents\Roblox Projects\TikTokHouseWars"
rojo serve

# 2. Studio: Plugins → Rojo → Connect

# 3. Терминал №2 — здесь работает Claude Code
claude
```

Дальше просто пишете задачи: «добавь моба Zombie с ценой 1500»,
«сделай, чтобы мобы дохли от урона», «почини баг с движением».
Claude правит файлы → Studio обновляется сама → жмёте Play и проверяете.

**Правило номер один:** после подключения Rojo не редактируйте эти скрипты
внутри Studio. Rojo синхронизирует в одну сторону (файл → Studio), и ваши
правки в Studio будут затёрты при следующем сохранении файла.

---

## 6. Как правильно ставить задачи Claude

Что помогает:

- **Скриншот Explorer / ошибки в Output.** Перетащите картинку в окно Claude
  Code — он прочитает.
- **Текст ошибки целиком** из Output, вместе с именем скрипта и строкой.
- **Описание того, что в Studio.** «У модели Boss PrimaryPart называется HumanoidRootPart»,
  «точек маршрута 12, последняя у базы игрока».
- **Что должно получиться**, а не как это писать. «Моб должен исчезать
  на последней точке и давать игроку деньги» — лучше, чем «добавь цикл в строку 80».

Полезные команды внутри Claude Code:

| Команда | Что делает |
|---|---|
| `/init` | создаст `CLAUDE.md` — постоянные заметки о проекте |
| `/clear` | очистить контекст, начать новую тему |
| `Shift+Tab` | переключить режим разрешений (в т.ч. авто-правки) |

### CLAUDE.md

Крайне рекомендую выполнить `/init` и дописать в получившийся `CLAUDE.md`
то, что Claude не может узнать из кода:

```markdown
- Комментарии и коммиты — на русском.
- Типизация Luau строгая: каждый файл начинается с --!strict.
- Структура карты: ServerStorage/Mobs (модели), Workspace/MobPath (точки 1..N).
- Модели мобов и карту правлю я руками в Studio, в файлах их нет.
```

Этот файл читается автоматически в начале каждой сессии.

---

## 7. Git

Репозиторий уже инициализирован. Работайте как обычно:

```powershell
git status
git add .
git commit -m "Добавлен спавнер мобов"
```

`.rbxl`/`.rbxlx` в `.gitignore` намеренно: бинарный файл места нельзя
нормально сливать в git. Если хотите хранить карту в репозитории —
это делается через `rojo build` в `.rbxlx` (XML) или через отдельный
репозиторий с ассетами.

---

## 8. Частые проблемы

| Симптом | Причина / решение |
|---|---|
| `rojo: command not found` | Не перезапустили терминал после `rokit install`, либо `~\.rokit\bin` не в PATH |
| Плагин пишет `Failed to connect` | Не запущен `rojo serve`, либо выключен `Allow HTTP Requests` в Studio Settings → Security |
| `Rojo plugin version mismatch` | Версия плагина не совпадает с CLI. Переустановить: `rojo plugin install`, перезапустить Studio |
| Скрипты не появились в дереве | Studio подключилась к другому месту/порту; проверьте, что открыт нужный `.rbxl` и адрес `localhost:34872` |
| Правки в Studio пропадают | Так и задумано — правьте файлы на диске, не в Studio |
| `Mobs is not a valid member of ServerStorage` | Не создана папка `ServerStorage/Mobs` (см. п. 4) |
| Порт 34872 занят | `rojo serve --port 34873` и тот же порт указать в плагине |
| Studio не видит изменения после переименования файла | Отключиться/подключиться заново (Disconnect → Connect) |

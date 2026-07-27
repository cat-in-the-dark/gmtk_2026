# План рефакторинга DUCKsumo

## Назначение документа

Этот документ фиксирует результаты полного обзора Godot-проекта и предназначен
как handoff для следующего разработчика или агента. Он описывает:

- текущее устройство проекта;
- подтверждённые проверки;
- сильные стороны, которые важно сохранить;
- архитектурные и технические риски;
- целевое состояние сцен и кода;
- порядок рефакторинга;
- обязательные проверки и критерии готовности.

Обзор выполнен 2026-07-27 для проекта Godot 4.7.1. Исходный контекст: это
небольшая 3D-игра, сделанная одним разработчиком за два дня для GMTK-2026.
Рекомендации следует соотносить с её размером: проекту не нужны тяжёлый DI,
сложный фреймворк сущностей или глобальные менеджеры без конкретной причины.

## Правила работы с репозиторием

Локальная инструкция из `AGENTS.md`:

> После любого редактирования кода обязательно запускать `make lint`.

Также после существенных изменений сцен, импортов или игровой логики нужно
запускать headless smoke test и Web export, описанные ниже.

Нельзя считать этот документ разрешением на удаление исходных моделей,
маркетинговых изображений или других пользовательских ассетов. Сначала следует
отделить runtime-ресурсы от source-art, затем согласовать удаление либо
перемещение.

## Проверенная исходная точка

На момент обзора:

- `981` строка GDScript;
- `330` строк в `.tscn`;
- `709` строк, около 72% GDScript, находятся в `Fighter`, `Player` и `Enemy`;
- автоматических тестов и CI нет;
- Autoload отсутствуют;
- рабочее дерево Git было чистым до создания этого документа.

Проверки исходной версии:

```sh
make lint
```

Результат: `Success: no problems found`.

```sh
godot --headless --path . --quit-after 300
```

Результат: проект запустился и завершился с кодом `0`, runtime-ошибок не было.

```sh
mkdir -p /private/tmp/gmtk-review
godot --headless --path . --export-debug Web \
  /private/tmp/gmtk-review/index.html
```

Результат: Web debug export завершился успешно. Размер получившегося `.pck`
был около `316 KB`; debug WASM около `36 MB`.

## Статус реализации

- Механическая реорганизация каталогов завершена.
- Этап 1 с написанием тестов пропущен по явному решению владельца проекта.
- Этап 2 с сигнальным lifecycle матча завершён 2026-07-27.
- `GameSession` является единственным владельцем переходов активного матча в
  Victory или Game Over.
- При одновременном устранении игрока и последнего врага приоритет имеет
  поражение игрока.
- `EnemySpawner` публикует оставшееся число врагов сигналом и больше не зависит
  от `EnemyCounter`.
- Restart внутри result-сцен пока остаётся локальным и не входит в завершение
  активного матча.
- Pixel-perfect настройка шрифта `deltarune.ttf` завершена 2026-07-27:
  отключены antialiasing, hinting и subpixel positioning, а `Label3D`
  переведены на nearest-фильтрацию и размеры, кратные нативным `10 px`.
- Gameplay-часть этапа 3 с явными collision layers, Hurtbox/Hitbox и
  animation-driven окнами атак завершена 2026-07-27; отдельный
  FPS/one-hit test target в текущем репозитории отсутствует.
- Gameplay tuning от 2026-07-28: глубина hitbox обеих рук игрока увеличена
  с `1.3` до `1.5`, а окно ввода следующего удара в combo увеличено на 10% —
  с `0.20` до `0.22` секунды.
- Этап 4 с единым `FighterState`, централизованными переходами и
  `AnimationTree` как presentation layer завершён 2026-07-28.
- Исправление этапа 4 от 2026-07-28: ввод атаки во время dash/hit больше не
  проверяет combo window с пустым `active_attack`; проверка также защищена
  собственным state guard.
- Этап 5 пропущен по явному решению владельца проекта. Глубокие пути к узлам
  Frog/Duck внутри `Fighter` намеренно остаются текущим техническим долгом.
- Этап 6 с `FighterStats`, `AttackDefinition`, `AttackSequence`,
  `EnemyConfig` и `WaveConfig` завершён 2026-07-28. Значения баланса перенесены
  в `.tres`, дублирующие scene overrides и dynamic `enemy.set()` удалены.

## Текущее устройство проекта

### Главная сцена

`game/game.tscn`:

```text
main (Node3D, game/game.gd)
├── GameSession (game/game_session.gd)
├── EnemySpawner (game/spawning/enemy_spawner.gd)
├── WorldEnvironment
├── Camera3D
├── DirectionalLight3D
├── Character (actors/player/player.tscn)
├── Floor (kill_floor)
└── level
    ├── box1 (box.tscn)
    ├── box2 (box.tscn)
    ├── box3 (box.tscn)
    ├── box4 (box.tscn)
    ├── platform1
    └── EnemyCounter (Label3D, ui/hud/enemy_counter.gd)
```

`EnemySpawner` динамически создаёт врагов как детей корня `main`.
`GameSession` подписан на устранение игрока и завершение спавнера, публикует
состояние счётчика и централизованно завершает активный матч.

### Pixel-perfect типографика

`ui/theme/fonts/deltarune.ttf` является векторным pixel-font с нативным
дизайн-размером `10 px`. Для него зафиксированы следующие инварианты:

- font antialiasing, hinting и subpixel positioning отключены;
- MSDF и mipmaps не используются;
- oversampling зафиксирован в `1.0`;
- 2D `Control` использует размер `10 px` или его целое кратное без
  нецелочисленного `scale`;
- все `Label3D` явно используют `texture_filter = Nearest`;
- размер шрифта у `Label3D` кратен `10`, а физический размер подбирается через
  `pixel_size`, а не через чрезмерный `font_size` с последующим уменьшением.

Текущие согласованные пары для ортографических камер и базового viewport
`320×240`:

```text
EnemyCounter: font_size 100, pixel_size 0.05, outline 10, Camera3D.size 12
Result title: font_size 40, pixel_size 0.025, outline 4, Camera3D.size 6
RestartLabel: font_size 10, Control scale 1
```

Если меняются размер viewport или `Camera3D.size`, `pixel_size` нужно
пересчитать. Для billboard, параллельного экрану, базовая формула:

```text
pixel_size = Camera3D.size / viewport_height
```

Для текста, лежащего в 3D-плоскости под углом, абсолютно одинаковые экранные
пиксели недостижимы из-за проекции, но бинарный растр и nearest-фильтрация
убирают серые ореолы. Если счётчику потребуется строгая экранная сетка, его
следует перенести в `CanvasLayer` как обычный `Label`.

### Персонажи

Игрок:

```text
actors/player/player.tscn
└── frog_character.tscn
    └── CharacterBody3D (FighterBody)
        ├── BodyCollision
        ├── Hurtbox
        ├── frog.glb
        │   ├── AnimationPlayer (source clips for AnimationTree)
        │   ├── visual hierarchy
        │   ├── LeftHandHitbox
        │   └── RightHandHitbox
        ├── AttackWindowPlayer (physics callback)
        └── AnimationTree (physics callback)
```

Враг:

```text
actors/enemy/enemy.tscn
└── actors/enemy/duck/duck_character.tscn
    └── CharacterBody3D (FighterBody)
        ├── BodyCollision
        ├── Hurtbox
        ├── duck.glb
        │   ├── AnimationPlayer (source clips for AnimationTree)
        │   ├── visual hierarchy
        │   ├── LeftHandHitbox
        │   └── RightHandHitbox
        ├── AttackWindowPlayer (physics callback)
        └── AnimationTree (physics callback)
```

Обе сцены используют `actors/fighter/fighter.gd` как общую базовую логику. Корневой скрипт
затем заменяется на `actors/player/player.gd` или `actors/enemy/enemy.gd`.

### Collision model и окна атак

Именованные слои определены в `project.godot`:

```text
1  World
2  FighterBody
3  Hurtbox
4  Hitbox
5  Props
6  KillFloor
```

Текущие правила layer/mask:

```text
FighterBody: layer 2, mask 1 | 2 | 5 | 6
Hurtbox:     layer 3, mask 4
Hitbox:      layer 4, mask 3 | 5
World:       layer 1, mask 2
Props:       layer 5, mask 2
KillFloor:   layer 6, mask 2
```

`FighterHurtbox` является типизированной ссылкой на родительский `Fighter`.
`AttackHitbox` принимает только `FighterHurtbox` и `AttackReceiver3D`.
Ручной широкий запрос атак из `Fighter` удалён; попадания приходят через
`Area3D.area_entered` и `Area3D.body_entered`.

Hitbox сохраняет `monitoring = true`, но gameplay-доступность контролируется
анимируемым свойством `active`. При открытии окна компонент дополнительно
обрабатывает текущие overlaps, поэтому цель, уже находящаяся внутри Area, не
теряется. Изменение `active` находится в дискретных property tracks общего
`actors/combat/attack_windows.tres`:

```text
attack1: RightHandHitbox, 0.033333–0.133333 s
attack2: LeftHandHitbox,  0.033333–0.133333 s
attack3: обе руки,        0.066667–0.233333 s
```

Импортированный model `AnimationPlayer` является источником клипов для
`AnimationTree`. `AnimationTree` и отдельный `AttackWindowPlayer` работают в
physics callback. В wrapper-сцене `AttackWindowPlayer` расположен перед
`AnimationTree`, чтобы при старте следующего combo-удара из callback завершения
оба проигрывателя начали новый клип на одном следующем physics frame.
`Fighter.hit_bodies` остаётся общей one-hit таблицей на всю атаку, поэтому две
руки не могут дважды поразить одну цель.

Friendly fire определяется `Fighter.Faction`, а не scene group. Ящики
реализуют типизированный `AttackReceiver3D`. Domino-механика намеренно оставляет
отдельный `intersect_shape`, но запрос ограничен слоем `FighterBody` и типом
`Enemy`.

Проверка data-driven конфигурации запускается командой:

```sh
make test-data-config
```

Она проверяет загрузку и validation всех default `.tres`, неизменность combo,
тайминга `0.22`, domino-флага, 21 врага, размеров волн, включения dash с третьей
волны и типизированную конфигурацию `Enemy`. Каталог `tests/` исключён из Web
export.

Важно: ранее описанные targets `make test-combat` и
`make test-fighter-state` отсутствуют в текущем репозитории. Реальные границы
hitbox windows при 30/60/120 FPS, общий one-hit двух рук и переходы
state/animation сейчас не покрыты отдельной автоматической проверкой.

### Data-driven конфигурация

Единственные владельцы default-значений баланса:

```text
actors/player/config/player_stats.tres
actors/player/config/player_combo.tres
actors/player/config/attacks/player_attack_{1,2,3}.tres
actors/enemy/config/enemy_stats.tres
actors/enemy/config/enemy_attack.tres
actors/enemy/config/default_enemy.tres
game/spawning/config/default_waves.tres
```

`Fighter` читает движение, процедурные шаги, physics reaction и dash из
`FighterStats`. `Player` читает порядок combo и индивидуальное buffer window из
`AttackSequence`. Активная атака теперь является `AttackDefinition`, а не
строкой: отдельно заданы animation, hitbox profile, сила, knockback,
разрешённые продолжения и domino-семантика.

`EnemyConfig` агрегирует `FighterStats`, атаку, дистанцию/тайминг charge, stun,
domino radius и dash probability. `WaveConfig` владеет enemy scene/config,
spawn-параметрами, общим числом врагов и последовательностью волн.

Все числовые поля имеют явный тип и Inspector ranges. Каждый custom Resource
реализует `get_validation_errors()`. `Fighter`, `Player`, `Enemy` и
`EnemySpawner` дополнительно валидируют ресурсы и совместимость
animation/hitbox/scene ссылок при `_ready()`.

### Остальные сцены

- `world/props/box/box.tscn` — статический ящик с процедурной тряской.
- `ui/result_screen/gameover/gameover.tscn` — отдельный экран поражения.
- `ui/result_screen/gamewin/gamewin.tscn` — отдельный экран победы.
- `world/environment/world_env.tres`, `world/environment/sky/*`, `world/arena/floor/floor.tres` — общие визуальные ресурсы.

## Сильные стороны, которые следует сохранить

### Общая модель бойца

`actors/fighter/fighter.gd` уже устраняет существенное дублирование движения, попаданий,
knockback и процедурной походки. Разделение на `Fighter`, `Player` и `Enemy`
подходит размеру проекта.

Не следует заменять эту иерархию сложной системой компонентов целиком. Лучше
выделить только действительно самостоятельные части: rig, hitbox/hurtbox,
конфигурацию и представление анимаций.

### Использование штатных механизмов Godot

Проект уже правильно использует:

- `CharacterBody3D`;
- `move_and_slide()`;
- Input Map;
- `PackedScene`;
- `@export` для игровых настроек;
- сигналы `attack_finished` и `eliminated`;
- группы `player`, `enemies`, `kill_floor`;
- `AnimationPlayer.animation_finished`;
- общие `.tres`-ресурсы;
- отдельный sky shader.

### Процедурная походка

Логика `Fighter.Leg`, `_try_start_step()`, `_update_leg_step()` и
`_update_leg()` является оправданной процедурной логикой. Она зависит от
физического движения и создаёт характерный визуальный эффект при сравнительно
небольшом объёме кода.

Её не нужно переносить в `AnimationTree` только ради использования более
«продвинутой» функции Godot. Сначала следует изолировать её от конкретной
структуры GLB через `FighterRig`.

### Небольшой масштаб проекта

Отсутствие Autoload сейчас является преимуществом. Централизованный
`GameSession` может быть обычным узлом главной сцены. Autoload потребуется
только при появлении сохраняемого состояния между многими сценами.

## Приоритетные проблемы

Уровни приоритета:

- `P1` — влияет на корректность или сильно блокирует дальнейшее развитие;
- `P2` — заметный долг по архитектуре, тестируемости и поддержке;
- `P3` — чистота, полировка или потенциальная оптимизация.

## P1. Атаки обрабатываются в другом цикле, чем анимации

Статус: устранено на этапе 3.

### Текущее поведение

`AnimationTree`, управляющий импортированным model `AnimationPlayer`, и
`AttackWindowPlayer` работают в physics callback. Ручной
`Fighter._check_attack_hits()` удалён, а `AttackHitbox` получает overlaps от
physics server через сигналы `Area3D`.

Проверенные длины импортированных анимаций:

```text
attack1        0.25000 s
attack2        0.20833 s
attack3        0.29167 s
hit            0.20833 s
idle           0.45833 s
stunned        0.25000 s
duck charge    0.04167 s
```

### Устранённый риск

Анимация рук обновляется на render frames, а пересечение проверяется на physics
frames. На нестабильном или низком FPS физика может видеть предыдущее положение
руки либо пропускать часть короткой траектории. Это делает попадания потенциально
зависимыми от FPS.

`force_update_transform()` синхронизирует текущий трансформ с физическим
сервером, но не продвигает AnimationPlayer до нужного physics timestamp.

### Реализованное изменение

- Model animation и hitbox window используют physics callback.
- One-hit registry общий для обеих рук и очищается только при старте следующей
  атаки.
- Текущие короткие траектории надёжно покрываются `Area3D`; если скорость или
  размер персонажей заметно изменятся, следующим усилением должен стать sweep
  внутри `AttackHitbox`, а не возврат query в `Fighter`.
- Автоматическая FPS/one-hit проверка, ранее описанная как `make test-combat`,
  отсутствует в текущем репозитории и остаётся незакрытой частью validation.

### Критерий готовности

- Результат одной и той же атаки не меняется при 30, 60 и 120 render FPS.
- Анимация и hitbox обновляются в physics callback.
- Один атакующий hitbox не наносит одной цели больше одного удара за атаку.

## P1. Hitbox активен всю анимацию

Статус: устранено на этапе 3.

### Текущее поведение

Обе wrapper-сцены содержат `FighterHurtbox`, `LeftHandHitbox`,
`RightHandHitbox` и `AttackWindowPlayer`. Свойство `AttackHitbox.active`
изменяется дискретными property tracks в `actors/combat/attack_windows.tres`.
Вне активного окна сигналы Area не наносят урон.

### Устранённый риск

- Попадание не привязано к визуальному моменту контакта.
- Настройка новой атаки требует изменения скрипта или структуры модели.
- Размер `combo_window` и длина анимации не описывают реальное окно удара.
- Быстро движущийся hitbox может пропустить цель между physics frames.

### Реализованное изменение

Создать явную структуру:

```text
Fighter
├── BodyCollision
├── Hurtbox (Area3D)
└── Hitboxes
    ├── LeftHandHitbox (Area3D)
    └── RightHandHitbox (Area3D)
```

- `active` меняется дискретным property track.
- `area_entered` обрабатывает только `FighterHurtbox`.
- `body_entered` обрабатывает только `AttackReceiver3D`.
- При открытии окна также проверяются уже существующие overlaps.
- Список поражённых целей хранится в `Fighter` и разделяется двумя руками.

### Критерий готовности

- У каждой атаки явно определено активное окно.
- Попадание невозможно до открытия и после закрытия окна.
- Настройка окна выполняется через сцену/анимацию, а не через условие по
  жёстко заданному времени в GDScript.

## P1. Неявная машина состояний из пересекающихся флагов

Статус: устранено на этапе 4.

### Текущее поведение

`Fighter` содержит ровно одно основное gameplay-состояние:

```gdscript
enum FighterState {
    IDLE,
    MOVE,
    ATTACK,
    HIT,
    DASH,
    CHARGE,
    STUNNED,
    KNOCKBACK,
    ELIMINATED,
}
```

Все изменения проходят через `_change_state()`. Допустимые переходы заданы в
`ALLOWED_STATE_TRANSITIONS`, а `_enter_state()`/`_exit_state()` централизуют
cleanup. Player и Enemy используют hooks `_on_state_entered()` и
`_on_state_exited()` для runtime-данных dash и charge.

`is_attacking`, `is_hit` и `is_eliminated` сохранены только как read-only
проекции текущего состояния для понятных проверок. Отдельные mutable-флаги
`is_dashing` и `is_charging_attack` удалены. Таймеры, combo buffer,
knockback-вектор и domino registry остаются данными активной механики, но не
являются конкурирующими основными состояниями.

### Устранённый риск

- dash, charge, hit, stun и attack не могут быть активны одновременно;
- выход из dash всегда очищает forced movement;
- выход из charge всегда очищает charge timer;
- attack interruption закрывает hitbox window;
- `ELIMINATED` не имеет исходящих переходов;
- невозможные переходы отклоняются общей таблицей.

### Критерий готовности

- В каждый момент времени у бойца одно основное состояние.
- Начало нового состояния гарантированно очищает данные предыдущего.
- Невозможные переходы отклоняются централизованно.
- Прерывание attack/dash/charge/stun реализовано, но отдельный
  `make test-fighter-state` в текущем репозитории отсутствует.

## P1. Гонка между Victory и Game Over

Статус: устранено на этапе 2.

### Текущее поведение

`Fighter` испускает `eliminated`, после чего `GameSession` фиксирует устранение
игрока.

`EnemySpawner` испускает `all_enemies_eliminated` после смерти последнего врага.
Оба события разрешаются `GameSession` через один отложенный вызов.

### Риск

Исход больше не зависит от порядка обработки бойцов. Если оба события приходят
до отложенного разрешения результата, выбирается поражение.

### Требуемое изменение

Реализован один объект, имеющий право завершать матч:

```text
GameSession
├── получает player_eliminated
├── получает all_enemies_eliminated
├── выбирает итог по явно заданному правилу
└── один раз меняет сцену
```

`Player` и `EnemySpawner` должны только испускать события.

Правило одновременного исхода зафиксировано: устранение игрока имеет приоритет.

### Критерий готовности

- В проекте только `GameSession` переключает игровые result-сцены.
- Повторный вызов завершения матча игнорируется.
- Одновременное устранение игрока и последнего врага имеет детерминированный
  результат и тест.

## P1. Fighter зависит от внутренних путей GLB

### Текущее поведение

`actors/fighter/fighter.gd` напрямую обращается к путям вроде:

```text
skin3/blockbench_export
root/arm_left/hand_left/hand_left_mesh/Area3D
root/left_leg/left_boot/ik_locator_left_boot2
```

### Риск

Переименование узла или изменение иерархии в Blockbench ломает персонажа после
реимпорта. Контракт не описан и проверяется только при runtime.

### Требуемое изменение

Создать `FighterRig` — узел или скрипт-адаптер с экспортированными ссылками:

```text
animation_player
visual_root
left_leg_root
left_leg_mesh
left_boot
left_plant
right_leg_root
right_leg_mesh
right_boot
right_plant
left_hand_hitbox
right_hand_hitbox
```

Возможные способы ссылок:

- экспортированные typed Node references;
- scene unique names (`%NodeName`);
- короткие пути внутри контролируемой wrapper-сцены.

`Fighter` должен получать `FighterRig` и не знать структуру GLB.

### Критерий готовности

- В `actors/fighter/fighter.gd` нет путей внутрь `frog.glb` или `duck.glb`.
- Обе модели проходят одинаковую проверку rig-контракта.
- Ошибка конфигурации выдаёт понятное сообщение с именем отсутствующей ссылки.

## P2. Нет явных collision layers

Статус: устранено на этапе 3.

### Текущее поведение

В `project.godot` именованы шесть 3D physics layers. Все gameplay-тела и Area
имеют явные layer/mask. Hitbox получает только Hurtbox и Props, а атака бойца
больше не использует broad manual query.

### Устранённый риск

- Лишние broad-phase результаты.
- Hitbox видит мир, props и прочие объекты, которые затем отбрасываются.
- Правила столкновений нельзя понять из Inspector.
- `has_method("receive_hit")` и `has_method("hit")` скрывают контракт.

### Реализованное изменение

В `project.godot` заданы слои:

```text
1  World
2  FighterBody
3  Hurtbox
4  Hitbox
5  Props
6  KillFloor
```

Правила:

- Fighter body сталкивается с World, FighterBody и Props.
- Fighter body также видит KillFloor для текущей slide-collision механики
  устранения.
- Hitbox проверяет только Hurtbox и Props.
- KillFloor не участвует в атакующих запросах.
- Friendly fire определяется `Fighter.Faction`, а не названием scene group.
- Domino-запрос ограничен FighterBody и типом `Enemy`.

### Критерий готовности

- Каждая физическая сцена имеет явные layer/mask.
- Атака не получает World и KillFloor в результатах запроса.
- Правило `Player vs Enemy` не основано только на строке `"enemies"`.

## P2. EnemySpawner недостаточно типобезопасен

Статус: частично устранено на этапе 6; проверка spawn overlap остаётся.

### Текущее поведение

`EnemySpawner` получает один `WaveConfig`. До запуска первой волны он проверяет
вложенный `EnemyConfig` и инстанцирует scene для проверки, что её корень имеет
тип `Enemy`. Каждый экземпляр получает настройки через
`Enemy.configure(enemy_config, wave_can_dash)`.

`current_wave_alive_count` и `spawned_enemy_count` увеличиваются только после
успешной конфигурации и добавления конкретного `Enemy` в дерево.

### Оставшийся риск

- Удаление врага способом, отличным от `eliminated`, не уменьшает счётчик.
- Вся волна создаётся в один кадр без проверки пересечений; враги могут
  появиться друг в друге.

### Оставшееся изменение

- Проверять spawn point через physics query или заранее расставленные
  `Marker3D`.
- Решить, нужна ли задержка между волнами; если да, использовать `Timer`.
- Если появятся альтернативные способы удаления врага, гарантировать сигнал
  `eliminated` либо отслеживать `tree_exited`.

### Критерий готовности

- Враги не появляются с пересекающимися body collision.

## P2. Прямое преследование врага плохо масштабируется

### Текущее поведение

Enemy каждый physics frame вычисляет прямое направление на первый узел группы
`player`. Уклонение, pathfinding и separation отсутствуют.

### Оценка

Для открытой квадратной арены это разумное упрощение. Не следует добавлять
`NavigationAgent3D` сейчас только ради «продвинутого Godot».

Проблема станет актуальной, если появятся:

- препятствия внутри арены;
- несколько уровней высоты;
- ловушки;
- несколько целей;
- большие группы врагов.

До этого достаточно простого separation/steering, чтобы враги меньше
складывались в одну точку и не блокировали друг друга.

## P2. Анимационная конфигурация исправляется во время runtime

Статус: устранено на этапе 4.

### Текущее поведение

Frog и Duck wrapper-сцены содержат отдельный `AnimationTree`, связанный с
импортированным model `AnimationPlayer`. Gameplay-state однозначно отображается
в presentation-state:

```text
IDLE                  → idle
MOVE                  → move (idle pose через TimeScale = 0)
ATTACK                → active_attack
HIT, KNOCKBACK        → hit
DASH, STUNNED         → stunned
CHARGE                → attack_charge
```

`idle`, а для Duck также `stunned`, зациклены custom timeline настройками
`AnimationNodeAnimation` в `.tres`. Импортированные `Animation` resources
runtime-код больше не изменяет. Состояние `move` использует замороженную
idle-позу и не вмешивается в процедурную постановку ног.

Клип `stunned` пока намеренно переиспользуется как поза dash, поскольку
отдельной dash-анимации в моделях нет. Duck `attack_charge` остаётся коротким
one-shot и удерживает финальную позу до окончания gameplay timer.

### Критерий готовности

- Runtime-код не меняет loop mode общих Animation resources.
- Idle действительно зациклен ресурсом.
- Gameplay-state однозначно отображается в анимационное состояние.

## P2. Баланс и поведение смешаны

Статус: устранено на этапе 6.

### Текущее поведение

Баланс хранится в custom Resources:

```text
FighterStats      — movement, procedural steps, gravity, knockback, dash
AttackDefinition  — animation/hitbox, strength, knockback, combo, domino
AttackSequence    — упорядоченная combo
EnemyConfig       — stats, attack, AI combat/dash
WaveConfig        — enemy factory data, spawn area, wave sequence
```

Combo `attack1 → attack2 → attack2 → attack3` описано
`player_combo.tres`. Окно `0.22` хранится в каждой допускающей продолжение
`AttackDefinition`. Для короткого `attack2` окно намеренно охватывает клип с
начала — это forgiving-настройка, зафиксированная validation test.

Числовые поля имеют явные типы, `@export_range` и runtime validation. Нулевой
`step_duration`, пустая атака/sequence, отрицательные physics values, неверный
порядок combo и неполный wave/enemy config отклоняются с сообщением.

### Критерий готовности

- Выполнено: баланс меняется через `.tres`, не редактируя поведение.
- Выполнено: значения больше не повторяются в скриптах и scene overrides.
- Выполнено: невалидная конфигурация обнаруживается в `_ready()` и
  `make test-data-config`.

## P2. Дублирование character scenes

### Текущее поведение

`actors/enemy/duck/duck_character.tscn` и `actors/player/frog/frog_character.tscn` имеют почти
одинаковую структуру:

- CharacterBody;
- capsule collision;
- skin wrapper;
- imported GLB;
- две Area3D с одинаковыми формами.

Меняется главным образом модель.

### Требуемое изменение

Целевая структура:

```text
fighter_base.tscn
├── BodyCollision
├── RigSocket
├── Hurtbox
└── Hitboxes
```

Duck/Frog могут быть:

- наследованными сценами с разным `FighterRig`;
- либо отдельными rig-сценами, инстанцируемыми в один base.

Не нужно пытаться заставить обе GLB иметь абсолютно одинаковую внутреннюю
иерархию. Для этого и нужен адаптер `FighterRig`.

### Критерий готовности

- Геометрия body/hurtbox/hitbox определяется в одном месте.
- Изменение размера общей формы не требует редактировать две сцены.
- Скин можно заменить без изменения gameplay-кода.

## P2. Game win и Game over дублируются

### Текущее поведение

Обе result-сцены содержат:

- Environment;
- Camera3D;
- 3D-заголовок;
- CanvasLayer с restart label;
- ручное вращение камеры вокруг target;
- обработку `ui_cancel`;
- hardcoded путь к `game/game.tscn`.

`gamewin.gd` дополнительно рекурсивно ищет AnimationPlayer с анимацией
`stunned`, чтобы определить уток.

### Риск

- Неявный контракт поиска моделей.
- Дублирование орбиты и input.
- Изменение стиля требует правки двух сцен.

### Требуемое изменение

Создать:

```text
result_screen_base.tscn
├── WorldEnvironment
├── OrbitPivot
│   └── Camera3D
├── PresentationRoot
└── UI
    ├── Title
    └── RestartHint
```

- Камеру сделать дочерней `OrbitPivot`; вращать pivot через AnimationPlayer
  либо маленький reusable script.
- Модели и focus point передавать экспортированными ссылками.
- Стиль UI вынести в Theme.
- Restart request передавать GameSession/router, если появится общий shell.

### Критерий готовности

- Орбитальная камера реализована один раз.
- Нет рекурсивного поиска персонажей по наличию анимации.
- Victory/Game Over отличаются только presentation data.

## P3. Визуальные эффекты частично лучше описывать сценами

### Box shake

`box/box.gd` вручную вычисляет синусоидальную тряску в `_process()`. Это
работает, но эффект проще настраивать в AnimationPlayer или Tween.

Оставить скрипт допустимо, если эффект должен складываться с повторными ударами.
В этом случае нужно:

- использовать локальный visual child, а не двигать StaticBody;
- не менять position физического тела ради визуального shake;
- отдельно решить поведение повторного hit.

### Result camera orbit

Орбита сейчас пересчитывает позицию и `look_at()` каждый кадр. Pivot node
с дочерней камерой лучше выражает структуру сцены.

### Bounce

Knockback bounce в `Fighter` допустимо оставить кодом, поскольку он связан с
physics-state. Желательно вынести смещение visual skin в presentation/rig,
чтобы gameplay body не зависел от визуального эффекта.

## P3. Runtime и source assets были смешаны

### Подтверждённое поведение экспорта

В `export_presets.cfg` установлен:

```text
export_filter="all_resources"
```

До реорганизации Web export фактически включал:

- `world/camera/camera_follow.gd`;
- `actors/player/legacy/character.gd`;
- `source_art/standalone_models/boot/boot.glb`;
- отдельные модели из `source_art/standalone_models/hand/`;
- импортированные текстуры из `source_art/blockbench/`;
- `docs/media/screenshot1.png`;
- `docs/media/splash.png`.

`docs/media/gameplay.mp4` не был показан среди упакованных Godot resources, но он
занимает около 8 MB в Git. Весь checkout вместе с `.git` на момент обзора был
около 22 MB, из них `.git` около 11 MB.

### Известные неиспользуемые или подозрительные файлы

- `world/camera/camera_follow.gd` не подключён ни к одной сцене.
- `actors/player/legacy/character.gd` состоит из `extends "res://actors/player/player.gd"` и не
  подключён к сцене.
- Standalone-модели в `source_art/standalone_models/` не имеют найденных
  runtime-ссылок.
- `source_art/blockbench/` выглядит как source-art.
- Screenshot, splash и gameplay video используются README/маркетингом, но не
  основной игрой.

### Требуемое изменение

- Каталоги `game/`, `source_art/` и `docs/media/` уже разделены механической
  реорганизацией; `source_art/` и `docs/` содержат `.gdignore`.
- Выбрать экспорт только зависимостей используемых сцен или явный include.
- Удалять файлы только после подтверждения владельца.
- Рассмотреть Git LFS или release attachment для большого gameplay video, если
  история репозитория продолжит расти.

### Критерий готовности

- Export manifest не содержит dead scripts и source-art.
- Marketing assets не импортируются Godot без необходимости.
- Web build по-прежнему запускается.

## P3. Нет тестов и CI

Линтер проверяет стиль, но не ловит:

- неверные NodePath;
- отсутствующие анимации;
- гонку Game Over/Victory;
- застрявшую волну;
- повторные попадания;
- рассинхронизацию анимации и physics;
- ошибки import/export.

### Минимальный набор автоматических проверок

Необязательно сразу подключать большой test framework. Можно начать с
headless GDScript smoke/integration tests.

Обязательные сценарии:

1. Все `.tscn` загружаются и инстанцируются без ошибок.
2. Frog и Duck удовлетворяют контракту `FighterRig`.
3. Каждая обязательная анимация существует.
4. Одна атака задевает одну цель не больше одного раза.
5. Hitbox не работает вне активного окна.
6. Прерывание атаки сбрасывает combo.
7. Dash корректно заканчивается при падении и hit.
8. Сильная атака запускает domino-chain без бесконечного цикла.
9. Волны дают суммарно `total_enemy_count` врагов.
10. Ошибка spawn не оставляет wave state навсегда заблокированным.
11. Одновременная смерть игрока и последнего врага детерминирована.
12. Main scene работает несколько сотен physics frames.

### Минимальный CI

```text
make lint
Godot headless scene tests
Godot headless main smoke
Godot Web release export
```

## Оценка распределения логики

### Логика, которая должна остаться в GDScript

- чтение input;
- движение CharacterBody;
- AI decision making;
- применение knockback;
- правила combo;
- wave progression;
- выбор результата матча;
- процедурная постановка ног;
- runtime state и защита от повторного hit.

### Логика, которую лучше выразить сценами и ресурсами

- активные окна hitbox;
- loop/autoplay и переходы анимаций;
- presentation state через AnimationTree;
- collision layers/masks;
- ссылки на части rig;
- orbit camera hierarchy;
- общая result screen;
- UI theme;
- attack/fighter/enemy/wave configuration;
- задержки между волнами через Timer;
- простые visual effects через AnimationPlayer/Tween.

Оценочно 60–70% нынешнего GDScript является оправданной gameplay или
процедурной логикой. Около 25–35% можно сделать декларативнее без потери
понятности.

## Целевая архитектура сцен

### Главная сцена

```text
Game (Node)
├── GameSession
├── World (Node3D)
│   ├── WorldEnvironment
│   ├── CameraRig
│   ├── Light
│   ├── Level
│   │   ├── Arena
│   │   ├── Props
│   │   └── KillFloor
│   └── Actors
│       ├── Player
│       └── Enemies
├── Spawners
│   └── EnemySpawner
└── UI (CanvasLayer)
    └── EnemyCounter
```

`GameSession`:

- владеет lifecycle матча;
- получает события Player и EnemySpawner;
- один раз определяет результат;
- публикует состояние для UI;
- переключает result scene.

`EnemySpawner`:

- не знает о Label;
- создаёт только `Enemy`;
- сообщает wave/remaining events;
- получает `WaveConfig`.

### Боец

```text
Fighter (CharacterBody3D)
├── BodyCollision
├── Hurtbox
├── Hitboxes
│   ├── LeftHand
│   └── RightHand
├── Rig (FighterRig)
│   └── VisualModel (GLB)
├── AnimationTree
└── OptionalTimers
```

В зависимости от удобства hitbox может оставаться дочерним к hand marker
внутри rig. Главное требование — `Fighter` получает короткие стабильные ссылки
через adapter, а не ходит по GLB path.

### Result screen

```text
ResultScreen
├── WorldEnvironment
├── OrbitPivot
│   └── Camera3D
├── PresentationRoot
└── UI
```

Victory и Game Over создаются как inherited scenes или как одна сцена с
разными presentation resources.

## Рекомендуемый порядок реализации

Каждый этап должен оставлять проект запускаемым. Не следует делать один большой
переписывающий commit.

### Этап 1. Защитная сетка

Статус: пропущен по решению владельца; тесты на этом этапе не добавляются.

1. Добавить smoke tests загрузки сцен и обязательных анимаций.
2. Добавить headless запуск main scene.
3. Добавить CI или локальный `make check`, объединяющий проверки.
4. Зафиксировать текущее gameplay-поведение короткими integration tests.

Результат: последующий рефакторинг можно делать без слепого риска.

### Этап 2. GameSession и детерминированный lifecycle

Статус: завершён.

1. Добавить `GameSession` в main scene.
2. Заменить прямые `change_scene_to_file()` сигналами.
3. Перевести EnemyCounter на сигнал состояния.
4. Добавить тест одновременного исхода.
5. Объединить restart policy.

Результат: ровно один владелец смены игровой сцены.

### Этап 3. Collision model и hitbox windows

Статус: gameplay-часть завершена; отдельные FPS/one-hit tests отсутствуют.

1. Именовать physics layers.
2. Добавить Hurtbox и Hitbox.
3. Перевести AnimationPlayer в physics callback.
4. Добавить animation tracks открытия/закрытия hitbox.
5. Удалить broad manual query, если Area signals покрывают требования.
6. Если нет — оставить query/ShapeCast внутри отдельного Hitbox-компонента.
7. Добавить FPS и one-hit tests.

Результат: визуальный контакт и gameplay hit используют одну временную шкалу.

### Этап 4. Явное состояние и AnimationTree

Статус: завершён.

1. Добавить `FighterState`.
2. Централизовать enter/exit.
3. Перевести Player dash и Enemy dash/charge/stun на общие переходы.
4. Добавить AnimationTree как presentation layer.
5. Убрать ручной replay idle и runtime loop mutation.

Результат: невозможные комбинации состояний исключены структурой.

### Этап 5. FighterRig и общая сцена бойца

Статус: пропущен по решению владельца; не выполнять без нового запроса.

1. Создать адаптер rig.
2. Подключить Frog, не меняя поведение.
3. Подключить Duck.
4. Удалить глубокие GLB paths из Fighter.
5. Объединить повторяющуюся часть character scenes.
6. Добавить validation тест rig.

Результат: модели можно реимпортировать и заменять локально.

### Этап 6. Data-driven конфигурация

Статус: завершён.

1. Создать `FighterStats`.
2. Создать `AttackDefinition` и combo sequence.
3. Создать `EnemyConfig`.
4. Создать `WaveConfig`.
5. Удалить dynamic `enemy.set()`.
6. Убрать дублирующие scene overrides.
7. Добавить ranges и validation.

Результат: баланс меняется через Inspector и `.tres`.

### Этап 7. Result screens и presentation cleanup

1. Создать общую result scene.
2. Перевести камеру на pivot.
3. Экспортировать focus target/model references.
4. Вынести UI Theme.
5. Перевести box shake на visual child.

Результат: визуальные эффекты не двигают gameplay physics body и не
дублируются.

### Этап 8. Asset/export cleanup

1. Получить подтверждение владельца на перемещение/удаление.
2. Отделить source-art и docs media.
3. Удалить или подключить dead scripts.
4. Сузить export filter.
5. Сравнить export manifest и размер.
6. Проверить Web release build.

Результат: в runtime export остаются только необходимые ресурсы.

## Поведенческие инварианты

Во время рефакторинга необходимо сохранить:

- движение WASD/стрелками/D-pad;
- attack через Space/Gamepad A;
- dash через Shift/Gamepad B;
- combo `attack1 → attack2 → attack2 → attack3`, если геймдизайн не изменён
  отдельной задачей;
- сильная финальная атака вызывает domino knockback;
- обычная атака врага не применяет сильный knockback игрока, если это текущее
  намеренное поведение;
- enemy charge телеграфируется визуально;
- новые волны начинаются только после устранения текущей;
- всего создаётся 21 враг при текущем default config;
- dash врагов становится доступен с третьей волны;
- падение врага уменьшает счётчик;
- падение игрока завершает матч;
- R перезапускает main scene;
- result screens принимают `ui_cancel` для restart;
- pixel-perfect viewport 320×240 и integer scaling;
- Web export остаётся рабочим.

Если какой-либо инвариант должен измениться, это нужно оформить как отдельное
геймдизайнерское изменение, а не маскировать под рефакторинг.

## Что не следует делать без новой причины

- Не добавлять Autoload только ради доступа к GameSession.
- Не вводить Entity Component System.
- Не заменять небольшую иерархию `Fighter` на десятки микрокомпонентов.
- Не добавлять NavigationAgent, пока арена остаётся открытой.
- Не переносить процедурную походку в AnimationTree без измеримой пользы.
- Не смешивать state machine gameplay и state machine AnimationTree как два
  независимых источника истины.
- Не удалять source-art или marketing assets без согласования.
- Не менять баланс одновременно с архитектурным рефакторингом.

## Проверки после каждого этапа

Минимум:

```sh
make lint
make test-data-config
godot --headless --path . --quit-after 300
```

После изменений сцен, импортов, шейдеров или export preset:

```sh
mkdir -p /private/tmp/gmtk-refactoring-web
godot --headless --path . --export-debug Web \
  /private/tmp/gmtk-refactoring-web/index.html
```

Дополнительно:

- открыть игру и вручную пройти минимум одну полную волну;
- проверить keyboard и gamepad input;
- проверить падение игрока;
- проверить победу;
- проверить одновременное падение игрока и последнего врага;
- проверить бой при ограничении FPS.

## Итоговая оценка

Для двухдневного jam-проекта исходная база качественная: она читаема, компактна
и использует основные механизмы Godot без лишней инфраструктуры.

Этапы 2, 3, 4 и 6 завершены; этапы 1 и 5 пропущены по решению владельца.
Главный оставшийся архитектурный долг — связь `Fighter` с глубокими путями
внутри импортированных GLB, но возвращаться к нему без нового запроса не
следует. Следующий запланированный этап — общий result screen и presentation
cleanup.

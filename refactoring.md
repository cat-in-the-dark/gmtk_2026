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

## Текущее устройство проекта

### Главная сцена

`game/game.tscn`:

```text
main (Node3D, game/game.gd)
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
    └── EnemyCounter (Label3D)
```

`EnemySpawner` динамически создаёт врагов как детей корня `main`.

### Персонажи

Игрок:

```text
actors/player/player.tscn
└── frog_character.tscn
    ├── CharacterBody3D
    ├── CollisionShape3D
    └── frog.glb
        ├── AnimationPlayer
        ├── visual hierarchy
        └── Area3D на каждой руке, добавленные wrapper-сценой
```

Враг:

```text
actors/enemy/enemy.tscn
└── actors/enemy/duck/duck_character.tscn
    ├── CharacterBody3D
    ├── CollisionShape3D
    └── duck.glb
        ├── AnimationPlayer
        ├── visual hierarchy
        └── Area3D на каждой руке, добавленные wrapper-сценой
```

Обе сцены используют `actors/fighter/fighter.gd` как общую базовую логику. Корневой скрипт
затем заменяется на `actors/player/player.gd` или `actors/enemy/enemy.gd`.

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

### Текущее поведение

Импортированные `AnimationPlayer` у `duck.glb` и `frog.glb` имеют
`callback_mode_process = 1`, то есть работают в idle/process-цикле.

Попадания проверяются из `Fighter._physics_process()`:

- `actors/fighter/fighter.gd::_physics_process()`;
- `actors/fighter/fighter.gd::_check_attack_hits()`.

`_check_attack_hits()` принудительно обновляет трансформы форм и выполняет
`PhysicsDirectSpaceState3D.intersect_shape()`.

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

### Риск

Анимация рук обновляется на render frames, а пересечение проверяется на physics
frames. На нестабильном или низком FPS физика может видеть предыдущее положение
руки либо пропускать часть короткой траектории. Это делает попадания потенциально
зависимыми от FPS.

`force_update_transform()` синхронизирует текущий трансформ с физическим
сервером, но не продвигает AnimationPlayer до нужного physics timestamp.

### Требуемое изменение

- Перевести боевой `AnimationPlayer` или `AnimationTree` в physics callback.
- Выполнять изменение активного hitbox в том же физическом цикле.
- Добавить тест попаданий при нескольких значениях render FPS.
- Проверить быстрые движения рук на tunneling.

### Критерий готовности

- Результат одной и той же атаки не меняется при 30, 60 и 120 render FPS.
- Анимация и hitbox обновляются в physics callback.
- Один атакующий hitbox не наносит одной цели больше одного удара за атаку.

## P1. Hitbox активен всю анимацию

### Текущее поведение

В `actors/enemy/duck/duck_character.tscn` и `actors/player/frog/frog_character.tscn` на обеих руках
есть `Area3D` с `CollisionShape3D`.

Вместо сигналов Area эти формы используются для ручного `intersect_shape()`.
Пока `is_attacking == true`, обе руки считаются активными на протяжении всей
анимации: wind-up, удар и recovery.

### Риск

- Попадание не привязано к визуальному моменту контакта.
- Настройка новой атаки требует изменения скрипта или структуры модели.
- Размер `combo_window` и длина анимации не описывают реальное окно удара.
- Быстро движущийся hitbox может пропустить цель между physics frames.

### Требуемое изменение

Создать явную структуру:

```text
Fighter
├── BodyCollision
├── Hurtbox (Area3D)
└── Hitboxes
    ├── LeftHandHitbox (Area3D)
    └── RightHandHitbox (Area3D)
```

Рекомендуемый вариант:

- `CollisionShape3D.disabled` или `Area3D.monitoring` меняется дискретным
  property track в боевой анимации;
- альтернативно call-method track вызывает `open_hitbox()` и
  `close_hitbox()`;
- `body_entered`/`area_entered` передаёт цель в один обработчик;
- список уже поражённых целей хранится в runtime конкретной атаки.

Если `Area3D` недостаточно надёжен для очень быстрых атак, рассмотреть
`ShapeCast3D` между предыдущим и текущим положением руки.

### Критерий готовности

- У каждой атаки явно определено активное окно.
- Попадание невозможно до открытия и после закрытия окна.
- Настройка окна выполняется через сцену/анимацию, а не через условие по
  жёстко заданному времени в GDScript.

## P1. Неявная машина состояний из пересекающихся флагов

### Текущее поведение

Состояние бойца распределено между:

```text
is_attacking
is_hit
active_attack
knockback_velocity
forced_movement_active
bounce_time_left
is_eliminated
```

Игрок добавляет:

```text
attack_buffered
is_dashing
dash_time_left
dash_cooldown_left
```

Враг добавляет:

```text
is_charging_attack
stun_time_left
is_dashing
dash_time_left
dash_cooldown_left
domino_knockback_active
```

Допустимость действий частично определяется виртуальным `is_busy()`.

### Риск

Допустимые и запрещённые комбинации нигде не заданы явно. При добавлении блока,
прыжка, смерти, особых атак или новых реакций станет легко получить:

- dash и hit одновременно;
- незавершённую forced movement;
- застрявший `is_attacking`;
- анимацию, не соответствующую gameplay-state;
- переход в idle до завершения stun.

### Требуемое изменение

Добавить явное gameplay-состояние:

```gdscript
enum FighterState {
    IDLE,
    MOVE,
    ATTACK,
    HIT,
    DASH,
    STUNNED,
    KNOCKBACK,
    ELIMINATED,
}
```

Необязательно переносить всю логику в отдельный объект State. Для этого
проекта достаточно:

- `state: FighterState`;
- `_enter_state(next_state, context)`;
- `_exit_state(previous_state)`;
- явной таблицы допустимых переходов;
- отдельных runtime-данных для атаки, dash и knockback.

`AnimationTree` должен отображать gameplay-state, а не быть независимой второй
машиной состояний.

### Критерий готовности

- В каждый момент времени у бойца одно основное состояние.
- Начало нового состояния гарантированно очищает данные предыдущего.
- Невозможные переходы отклоняются централизованно.
- Прерывание attack/dash/stun покрыто тестами.

## P1. Гонка между Victory и Game Over

### Текущее поведение

`actors/player/player.gd::_on_reached_kill_floor()` отложенно переключает сцену на Game Over.

`game/spawning/enemy_spawner.gd::_on_spawned_enemy_eliminated()` отложенно переключает сцену
на Victory после смерти последнего врага.

### Риск

Если игрок и последний враг достигнут kill floor в одном physics tick, в очередь
попадут две смены сцены. Результат зависит от порядка обработки узлов.

### Требуемое изменение

Только один объект должен иметь право завершать матч:

```text
GameSession
├── получает player_eliminated
├── получает all_enemies_eliminated
├── выбирает итог по явно заданному правилу
└── один раз меняет сцену
```

`Player` и `EnemySpawner` должны только испускать события.

Следует заранее выбрать правило одновременного исхода. Рекомендация для sumo:
если игрок выбит в том же physics tick, результат считать поражением, если
геймдизайн явно не требует draw/victory.

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

### Текущее поведение

Большинство тел и Area используют стандартные layer/mask. После широкого
physics query объекты фильтруются по группам, `has_method()` и типу.

### Риск

- Лишние broad-phase результаты.
- Hitbox видит мир, props и прочие объекты, которые затем отбрасываются.
- Правила столкновений нельзя понять из Inspector.
- `has_method("receive_hit")` и `has_method("hit")` скрывают контракт.

### Требуемое изменение

Задать именованные physics layers в `project.godot`, например:

```text
1  World
2  FighterBody
3  Hurtbox
4  Hitbox
5  Props
6  KillFloor
```

Точные номера можно изменить, но назначения должны быть документированы.

Рекомендуемые правила:

- Fighter body сталкивается с World, FighterBody и Props.
- Hitbox проверяет только Hurtbox и, при необходимости, Props.
- KillFloor не участвует в атакующих запросах.
- Friendly fire определяется team/faction, а не названием scene group.

### Критерий готовности

- Каждая физическая сцена имеет явные layer/mask.
- Атака не получает World и KillFloor в результатах запроса.
- Правило `Player vs Enemy` не основано только на строке `"enemies"`.

## P2. EnemySpawner недостаточно типобезопасен

### Текущее поведение

`enemy_scene.instantiate()` приводится к `Fighter`, после чего вызывается:

```gdscript
enemy.set("can_dash", wave_can_dash)
```

`can_dash` не является свойством `Fighter`.

`current_wave_alive_count` заранее устанавливается равным ожидаемому числу
созданных врагов.

### Риск

- Неверная сцена приводит к runtime-ошибке.
- Частичная ошибка спавна может навсегда заблокировать следующую волну.
- Удаление врага способом, отличным от `eliminated`, не уменьшает счётчик.
- Вся волна создаётся в один кадр без проверки пересечений; враги могут
  появиться друг в друге.

### Требуемое изменение

- Добавить `class_name Enemy` либо typed factory method.
- Добавить `Enemy.configure(config)` вместо динамического `set()`.
- Увеличивать alive count только после успешного создания врага.
- Проверять spawn point через physics query или заранее расставленные
  `Marker3D`.
- Решить, нужна ли задержка между волнами; если да, использовать `Timer`.
- Разделить состояние волн и отображение счётчика сигналом
  `remaining_enemies_changed`.

### Критерий готовности

- Неверный `enemy_scene` обнаруживается до запуска волны.
- Ошибка одного spawn не блокирует матч без диагностического сообщения.
- Враги не появляются с пересекающимися body collision.
- UI не передаётся спавнеру как обязательная зависимость.

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

### Текущее поведение

- `actors/enemy/enemy.gd::_ready()` меняет loop mode у `stunned`.
- `Fighter._on_model_animation_finished()` вручную повторно запускает `idle`.
- `stunned` используется также как визуальная поза dash.
- Duck `attack_charge` длится около 0.0417 секунды, но charge-state длится 0.5
  секунды и удерживает последний кадр.

### Риск

- Поведение анимаций распределено между импортом и GDScript.
- Название `stunned` используется для нескольких семантически разных состояний.
- Изменение импортированной общей Animation resource во время runtime является
  неявным глобальным действием.

### Требуемое изменение

- Настроить loop для `idle` и нужных циклов в import/wrapper scene.
- Добавить `AnimationTree` с состояниями presentation layer.
- При необходимости создать отдельные названия/позы `dash`, `stunned`,
  `charge`.
- Не мутировать общие импортированные Animation resources из каждого Enemy.

### Критерий готовности

- Runtime-код не меняет loop mode общих Animation resources.
- Idle действительно зациклен ресурсом.
- Gameplay-state однозначно отображается в анимационное состояние.

## P2. Баланс и поведение смешаны

### Текущее поведение

Настройки разбросаны между:

- константами в скриптах;
- значениями `@export`;
- override в `actors/player/player.tscn` и `actors/enemy/enemy.tscn`;
- повторными override инстанса Player в `game/game.tscn`.

Пример: `move_speed := 6` выводится как `int`. `step_duration`, drag, cooldown
и другие значения не всегда ограничены безопасным диапазоном.

Combo использует:

```gdscript
[attack1, attack2, attack2, attack3]
```

При `combo_window = 0.2` и длинах первых атак 0.25/0.208 секунды окно буфера
открывается почти сразу. Это может быть намеренной forgiving-механикой, но
должно быть явно зафиксировано тестом или комментарием.

### Требуемое изменение

Создать custom Resources:

```text
FighterStats
AttackDefinition
AttackSequence
EnemyConfig
WaveConfig
```

Минимальный `AttackDefinition`:

```text
animation_name
damage_or_strength
knockback_strength
combo_buffer_window
allowed_next_attacks
hitbox_profile
is_domino_attack
```

Для числовых экспортов:

- добавить явные `float`/`int`;
- использовать `@export_range`;
- добавить проверки нулевой `step_duration`;
- определить допустимые отрицательные значения.

### Критерий готовности

- Баланс можно менять через `.tres`, не редактируя поведение.
- Одинаковые default values не повторяются в трёх местах.
- Невалидная конфигурация обнаруживается в `_ready()` или editor validation.

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

1. Добавить smoke tests загрузки сцен и обязательных анимаций.
2. Добавить headless запуск main scene.
3. Добавить CI или локальный `make check`, объединяющий проверки.
4. Зафиксировать текущее gameplay-поведение короткими integration tests.

Результат: последующий рефакторинг можно делать без слепого риска.

### Этап 2. GameSession и детерминированный lifecycle

1. Добавить `GameSession` в main scene.
2. Заменить прямые `change_scene_to_file()` сигналами.
3. Перевести EnemyCounter на сигнал состояния.
4. Добавить тест одновременного исхода.
5. Объединить restart policy.

Результат: ровно один владелец смены игровой сцены.

### Этап 3. Collision model и hitbox windows

1. Именовать physics layers.
2. Добавить Hurtbox и Hitbox.
3. Перевести AnimationPlayer в physics callback.
4. Добавить animation tracks открытия/закрытия hitbox.
5. Удалить broad manual query, если Area signals покрывают требования.
6. Если нет — оставить query/ShapeCast внутри отдельного Hitbox-компонента.
7. Добавить FPS и one-hit tests.

Результат: визуальный контакт и gameplay hit используют одну временную шкалу.

### Этап 4. Явное состояние и AnimationTree

1. Добавить `FighterState`.
2. Централизовать enter/exit.
3. Перевести Player dash и Enemy dash/charge/stun на общие переходы.
4. Добавить AnimationTree как presentation layer.
5. Убрать ручной replay idle и runtime loop mutation.

Результат: невозможные комбинации состояний исключены структурой.

### Этап 5. FighterRig и общая сцена бойца

1. Создать адаптер rig.
2. Подключить Frog, не меняя поведение.
3. Подключить Duck.
4. Удалить глубокие GLB paths из Fighter.
5. Объединить повторяющуюся часть character scenes.
6. Добавить validation тест rig.

Результат: модели можно реимпортировать и заменять локально.

### Этап 6. Data-driven конфигурация

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

Главный технический долг сосредоточен не в объёме кода, а в координации:

1. анимация и physics hit detection работают в разных циклах;
2. hit window не описан данными анимации;
3. gameplay-state распределён по множеству флагов;
4. завершение матча имеет двух владельцев;
5. Fighter связан с внутренней структурой импортированных моделей.

Первые четыре этапа плана дают наибольший прирост корректности и должны быть
выполнены раньше визуальной полировки и очистки ассетов.

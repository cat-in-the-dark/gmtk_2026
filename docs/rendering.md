Да, визуально это похоже на low-poly 3D, отрендеренный в низком разрешении, с почти плоскими цветами. Полный Unshaded здесь необязателен.

В Godot режим Unshaded не получает тени и полностью игнорирует освещение. При этом такой MeshInstance3D способен отбрасывать тень на пол, если у него включён Cast Shadow.

Самый простой вариант

Материал персонажа

Используй StandardMaterial3D:

- Shading Mode: Per Vertex или Per Pixel
- Diffuse Mode: Toon
- Specular Mode: Disabled
- Metallic: 0
- Roughness: 1
- Shading > Unshaded: выключено
- Texture Filter: Nearest

Diffuse Mode: Toon создаёт жёсткие переходы между освещёнными и затенёнными участками. Per Vertex хорошо сочетается с геометрией из Blockbench и делает освещение более «гранёным».

Если модель должна выглядеть почти плоской:

- добавь яркое окружающее освещение через WorldEnvironment;
- поставь один слабый DirectionalLight3D;
- уменьши Shadow Opacity примерно до 0.35–0.6;
- отключи блики.

В результате основная палитра сохранится, а тени останутся читаемыми.

Если тень нужна только под персонажем

Можно оставить персонажу Unshaded:

1. У MeshInstance3D:
   - Geometry > Cast Shadow: On.
2. У DirectionalLight3D:
   - Shadow > Enabled: On.
3. Полу дать обычный освещаемый StandardMaterial3D.

Тогда:

- персонаж останется полностью плоским по цвету;
- персонаж отбросит тень на пол;
- собственных теней на руках, лице и одежде у персонажа не будет.

Для референса на изображении этого подхода уже может хватить: главный объём там создают силуэт, контрастные плоскости и тень на поверхности.

Если нужны плоские цвета плюс собственные тени

Можно сделать shader, игнорирующий направление света и использующий только его затенение:

shader_type spatial;

render_mode specular_disabled, ambient_light_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.45;

void fragment() {
    ALBEDO = texture(albedo_texture, UV).rgb;
    ROUGHNESS = 1.0;
}

void light() {
    float visibility = min(
        ATTENUATION.r,
        min(ATTENUATION.g, ATTENUATION.b)
    );

    float brightness = mix(
        1.0 - shadow_strength,
        1.0,
        visibility
    );

    DIFFUSE_LIGHT += vec3(brightness);
}
Он делает освещённую часть модели практически равной исходному цвету текстуры, а в тенях только затемняет её. Лучше использовать с одним DirectionalLight3D, чтобы несколько источников света не складывали яркость.

Как получить пиксельный визуал

Главная часть эффекта создаётся рендером в маленькое разрешение.

Рекомендуемая схема сцены:

SubViewport
└── World3D
    ├── Camera3D
    ├── DirectionalLight3D
    ├── Character
    └── Floor

TextureRect
└── показывает текстуру SubViewport
Например:

- SubViewport Size: 320 × 180 или 426 × 240;
- растянуть результат на окно;
- фильтрация Nearest;
- камера Orthogonal;
- MSAA, TAA и FXAA отключить;
- текстуры импортировать с Filter = Nearest;
- mipmaps для маленьких палитровых текстур отключить.

Низкое разрешение автоматически сделает пиксельными:

- края модели;
- тень;
- мелкие детали;
- переходы toon-освещения.

Рендерить сцену сразу в Full HD с последующим pixelation-шейдером обычно сложнее: тени и контуры могут попадать на разные пиксельные сетки.

Рекомендуемый стартовый пресет

Для визуала с картинки я бы начал так:

- ортографическая камера под углом около 35–45°;
- StandardMaterial3D;
- Diffuse Mode = Toon;
- Specular Mode = Disabled;
- Shading Mode = Per Vertex;
- один DirectionalLight3D;
- Shadow Opacity = 0.45;
- яркий ambient light;
- рендер 320 × 180;
- Nearest scaling;
- плоские normals у модели из Blockbench.

А затем сравнил бы с вариантом, где персонаж полностью Unshaded, а освещается только пол. Для данного референса второй вариант может оказаться ближе всего: плоский персонаж + пиксельная падающая тень + немного заранее нарисованных теневых цветов в текстуре ✨

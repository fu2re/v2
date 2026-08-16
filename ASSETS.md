# Происхождение ассетов

Игра коммерческая (магазин косметики). Каждый ассет обязан иметь здесь запись
о происхождении и лицензии — до того, как попадёт в билд.

**Правила:**

- Только CC0, купленные лицензии или собственное производство
- Никаких моделей и LoRA, обученных на конкретных художниках или чужих франшизах
- Проверяй лицензию генератора на **коммерческое** использование выхода — у многих
  бесплатных тарифов коммерческое использование запрещено
- Сгенерированное дорабатывается вручную: это и качество, и основание для прав на результат

---

## Музыка

| Файл | Происхождение | Лицензия |
|---|---|---|
| `music/demo_disco.ogg` | Синтезирован из кода: `tools/chartgen/beatroot_chartgen/songs/demo_disco.py` | Собственное производство |
| `music/<жанр>_<мотив>_<грейд>_<bpm>.ogg` | Синтезированы из кода: `chartgen build-all` по матрице мотивов | Собственное производство |
| `music/cue/*.ogg` | Синтезированы из кода: `chartgen cues`, спецификации в `beatroot_chartgen/cue.py` | Собственное производство |
| `music/ui/*.ogg` | То же — петли экранов усадьбы | Собственное производство |
| `music/glade/*.ogg` | То же — по пять мелодий на каждый тип поляны | Собственное производство |

## Графика

| Файл | Происхождение | Лицензия |
|---|---|---|
| `icon.svg` | Шаблон проекта Godot | MIT (Godot Engine) |
| `art/palette.json`, `art/palette.png` | Палитра проекта, `tools/artgen` | Собственное производство |
| `art/placeholder/*.png` | Процедурная генерация, `tools/artgen` | Собственное производство |

Плейсхолдеры — временные, на время Фазы 0. Заменяются сгенерированными ассетами
по мере их доводки.

## Заставка

Заставка — это фон и название, больше ничего.

| Файл | Происхождение | Лицензия |
|---|---|---|
| Надпись BEATROOT | Растровые литеры 5×7 в коде, `tools/artgen/beatroot_artgen/splash.py` | Собственное производство |
| `art/splash.png` | Собирается `artgen splash` из фона и надписи | Собственное производство |

Надпись набрана **не шрифтом** намеренно. Свободного шрифта в системе нет,
а лицензировать чужую гарнитуру под коммерческую игру ради восьми букв дороже,
чем нарисовать литеры. Растровые литеры 5×7, увеличенные целым множителем,
заодно дают ровный пиксель вместо сглаженного чужого контура.

## Модели и LoRA

Лежат в `E:\ComfyUI\ComfyUI\ComfyUI\models\checkpoints`.

| Модель | Лицензия | Коммерческое использование | Роль |
|---|---|---|---|
| `flux1-schnell-fp8` | Apache 2.0 | **Да**, выход не обременён | Основная |
| `sd_xl_base_1.0` | CreativeML Open RAIL++-M | **Да** | Контрольная |

Обе лицензии разрешают коммерческий выход — блокер продакшена снят.
**FLUX.1 [dev] брать нельзя**: лицензия некоммерческая. LoRA не используются.

### Почему основная — FLUX

Сравнение на одном промпте (мшистый медвежонок, `artgen comfy` обоими чекпойнтами):

- FLUX уверенно отдаёт объект на чистом белом фоне и попадает в задание.
  SDXL на том же промпте дорисовал каменный постамент под зверем и прочитал
  «sprout child» как «девочка с цветами в волосах»
- После даунскейла и квантования мимика FLUX выживает на 96×96 и читается
  даже в честном размере 1x — то, ради чего вся постобработка и делается

Оговорка, которую надо помнить: FLUX — дистиллят на cfg 1.0, и **негативный
промпт на нём почти не действует**. Всё критичное вынесено в начало позитивного
промпта (`STYLE_POSITIVE_DISTILLED`), а фон режется сегментацией (`--extra cutout`),
а не заливкой от краёв. Профили сэмплера подбираются по имени чекпойнта
в `comfy.py`, вслепую параметры не задаются.

<!-- artgen:begin -->
### Сгенерированные ассеты

Раздел ведёт `artgen promote` — правки руками будут затёрты.
Каждый ассет доводится вручную после переноса: это и качество,
и основание для прав на результат.

| Файл | Происхождение | Лицензия |
|---|---|---|
| `art/gear/acorn_charm.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/icon/app_icon.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/banjo_moth_common.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/banjo_moth_epic.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/banjo_moth_legendary.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/banjo_moth_rare.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/banjo_moth_uncommon.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/banjo_moth_unique.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/bass_bear_common.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/bass_bear_epic.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/bass_bear_legendary.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/bass_bear_rare.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/bass_bear_uncommon.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/bass_bear_unique.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/fruit/bass_plum.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/beat_serpent_common.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/beat_serpent_epic.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/beat_serpent_legendary.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/beat_serpent_rare.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/beat_serpent_uncommon.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/beat_serpent_unique.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/gear/brass_bell.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/building/building_forest.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/building/building_garden.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/building/building_guardians.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/building/building_merchant.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/building/building_storehouse.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/fruit/chord_apple.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/gear/cloud_shoes.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/currency/coin_gold.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/currency/coin_silver.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/cosmetic/crown_of_beats.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/cosmetic/disco_overalls.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/disco_sprout_common.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/disco_sprout_epic.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/disco_sprout_legendary.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/disco_sprout_rare.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/disco_sprout_uncommon.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/disco_sprout_unique.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/fruit/drum_berry.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/fruit/echo_pear.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_01.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_02.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_03.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_04.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_05.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_06.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_07.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_08.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_09.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_10.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_11.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_12.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_13.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_14.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_15.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_16.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_17.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_18.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_19.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/forest/forest_20.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/glade/glade_battle.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/glade/glade_campfire.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/glade/glade_encounter.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/glade/glade_wild_bush.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/gear/heartwood_amulet.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/hero/hero_girl.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/hero/hero_kid.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/fruit/loop_fig.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/tile/mossy_plot.png` | ComfyUI, `sd_xl_base_1.0.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/cosmetic/polka_overalls.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/prop/prop_chest.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/tile/prop_farm_plot.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/prop/prop_seed_pouch.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/gear/river_stone.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/screen/screen_farm.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/screen/screen_guardians.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/screen/screen_inventory.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/screen/screen_lobby.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/screen/screen_merchant.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/gear/soft_slippers.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/splash/splash_bg.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/gear/spring_boots.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/cosmetic/starlight_cloak.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/cosmetic/straw_hat.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/cosmetic/sunflower_hat.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/synth_slime_common.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/synth_slime_epic.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/synth_slime_legendary.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/synth_slime_rare.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/synth_slime_uncommon.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/monster/synth_slime_unique.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/gear/thunder_pick.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/gear/tin_whistle.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
| `art/cosmetic/watering_can.png` | ComfyUI, `flux1-schnell-fp8.safetensors`, постобработка `tools/artgen` | Собственное производство |
<!-- artgen:end -->

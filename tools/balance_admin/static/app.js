/* Балансовая админка BEATROOT — vanilla JS, без сборки.
 *
 * Форма рисуется по схеме с сервера (инференс + hints.json), поэтому
 * новый data/*.json появляется здесь сам. Значения правятся прямо
 * в объекте current.data по пути узла; сервер валидирует весь набор
 * конфигов перед записью и снимает бэкап на каждый успешный PUT.
 */

"use strict";

const $ = (sel, el) => (el || document).querySelector(sel);

let REFS = null;
let current = null;   // {type:'config'|'entities'|'backups', name, data, schema, dirty}
let validateTimer = null;

// Один плеер на всю страницу: две мелодии разом — это каша, а не прослушка
const player = new Audio();
let playingBtn = null;

function togglePlay(stem, btn) {
  if (playingBtn === btn && !player.paused) { stopAudio(); return; }
  stopAudio();
  player.src = `/music/${stem}.ogg`;
  player.play().catch(() => toast(`Не проигрывается: ${stem}.ogg`, true));
  playingBtn = btn;
  btn.classList.add("playing");
  btn.textContent = "■ " + (btn.dataset.label || "");
}

function stopAudio() {
  player.pause();
  if (playingBtn) {
    playingBtn.classList.remove("playing");
    playingBtn.textContent = "▶ " + (playingBtn.dataset.label || "");
    playingBtn = null;
  }
}
player.addEventListener("ended", stopAudio);

function playButton(label, stemGetter) {
  const btn = document.createElement("button");
  btn.className = "play-btn";
  btn.dataset.label = label;
  btn.textContent = "▶ " + label;
  btn.onclick = () => {
    const stem = stemGetter();
    if (!stem) { toast("Трека нет", true); return; }
    togglePlay(stem, btn);
  };
  return btn;
}

const GEAR_SLOTS = ["Пояс", "Плащ", "Головной убор"];
const COSMETIC_SLOTS = ["Наряд", "Головной убор", "Инструмент",
  "Вид грядки", "Эффект нот", "Танцевальное движение"];
const GENRE_NAMES = { rock: "Трава (рок)", disco: "Солнце (диско)",
  folk: "Листва (фолк)", electro: "Искра (электро)", latin: "Ветер (латина)" };

// --- запуск -----------------------------------------------------------------

async function boot() {
  REFS = await getJSON("/api/refs");
  const configs = await getJSON("/api/configs");
  const navConfigs = $("#nav-configs");
  for (const cfg of configs) {
    const btn = document.createElement("button");
    btn.className = "nav-item";
    btn.textContent = cfg.name;
    if (cfg.readonly) btn.innerHTML += '<span class="tag">только чтение</span>';
    btn.onclick = () => openConfig(cfg.name, btn);
    navConfigs.appendChild(btn);
  }
  const kinds = [["monsters", "Монстры"], ["gear", "Снаряжение"],
    ["cosmetics", "Косметика"], ["fruits", "Фрукты"]];
  const navEntities = $("#nav-entities");
  for (const [kind, label] of kinds) {
    const btn = document.createElement("button");
    btn.className = "nav-item";
    btn.textContent = label;
    btn.onclick = () => openEntities(kind, label, btn);
    navEntities.appendChild(btn);
  }
  $('[data-view="backups"]').onclick =
    (e) => openBackups(e.target);
  $("#save-btn").onclick = saveCurrent;
  $("#modal-close").onclick = closeModal;
  $("#modal").onclick = (e) => { if (e.target.id === "modal") closeModal(); };
  $("#melody-close").onclick = closeMelodyModal;
  $("#melody-modal").onclick =
    (e) => { if (e.target.id === "melody-modal") closeMelodyModal(); };
}

function activateNav(btn) {
  document.querySelectorAll(".nav-item.active")
    .forEach((el) => el.classList.remove("active"));
  if (btn) btn.classList.add("active");
}

// --- конфиг: форма по схеме ---------------------------------------------------

async function openConfig(name, btn) {
  if (current?.dirty
      && !confirm("Есть несохранённые правки — бросить их?")) return;
  activateNav(btn);
  stopAudio();
  const payload = await getJSON(`/api/configs/${name}`);
  current = { type: "config", name, data: payload.data,
    schema: payload.schema, readonly: payload.readonly, dirty: false };
  $("#crumbs").textContent = name + (payload.readonly ? " · только чтение" : "");
  $("#save-btn").hidden = payload.readonly;
  $("#save-btn").disabled = true;
  $("#dirty-dot").hidden = true;
  showProblems(null);

  const content = $("#content");
  content.innerHTML = "";
  const schema = payload.schema;
  for (const [key, child] of Object.entries(schema.children || {})) {
    content.appendChild(renderTopLevel(key, child));
  }
}

function renderTopLevel(key, node) {
  const section = document.createElement("section");
  section.className = "block";
  const h = document.createElement("h3");
  h.textContent = key;
  h.onclick = () => section.classList.toggle("folded");
  section.appendChild(h);
  const body = document.createElement("div");
  body.className = "body";
  body.appendChild(renderNode(node, key));
  section.appendChild(body);
  return section;
}

function renderNode(node, label) {
  if (node.kind === "doc") return renderDoc(node);
  if (node.kind === "object") return renderObject(node);
  if (node.kind === "array") return renderArray(node, label);
  return renderLeafField(node, label);
}

function renderDoc(node) {
  const div = document.createElement("div");
  div.className = "doc";
  const value = getByPath(current.data, node.path);
  div.textContent = Array.isArray(value) ? value.join("\n") : String(value ?? "");
  if (node.hint) div.textContent += "\n" + node.hint;
  return div;
}

function renderObject(node) {
  if (node.widget === "grade_map") return renderGradeMap(node);
  if (node.widget === "doc") return renderDoc(node);
  const wrap = document.createElement("div");
  if (node.hint) wrap.appendChild(hintEl(node.hint));
  for (const [key, child] of Object.entries(node.children || {})) {
    if (child.kind === "object" && child.widget !== "grade_map"
        && child.widget !== "doc") {
      const sub = document.createElement("div");
      sub.className = "subobject";
      const h = document.createElement("h4");
      h.textContent = key;
      sub.appendChild(h);
      sub.appendChild(renderNode(child, key));
      wrap.appendChild(sub);
    } else {
      wrap.appendChild(renderNode(child, key));
    }
  }
  if (node.sum_to) attachSumBadge(wrap, node.sum_to);
  return wrap;
}

// Живой индикатор суммы: слушает все числовые поля внутри узла.
// Зелёный на 100 — таблица распределения не лжёт ни игроку, ни дизайнеру.
function attachSumBadge(wrap, target) {
  const badge = document.createElement("span");
  badge.className = "sum-badge";
  const inputs = () => wrap.querySelectorAll('input[type="number"]');
  const update = () => {
    let total = 0;
    for (const input of inputs()) total += Number(input.value) || 0;
    badge.textContent = `Σ ${round2(total)} / ${target}`;
    badge.classList.toggle("ok", Math.abs(total - target) < 0.01);
    badge.classList.toggle("bad", Math.abs(total - target) >= 0.01);
  };
  for (const input of inputs()) input.addEventListener("input", update);
  update();
  wrap.appendChild(badge);
}

function renderGradeMap(node) {
  const wrap = document.createElement("div");
  const table = document.createElement("table");
  table.className = "grade-map";
  const head = table.insertRow();
  const cells = {};
  for (const grade of REFS.grade_keys) {
    if (!(grade in (node.children || {}))) continue;
    const th = document.createElement("th");
    th.textContent = grade;
    head.appendChild(th);
  }
  const row = table.insertRow();
  for (const grade of REFS.grade_keys) {
    const child = (node.children || {})[grade];
    if (!child) continue;
    const td = row.insertCell();
    const input = leafInput(child);
    td.appendChild(input);
    cells[grade] = input;
  }
  wrap.appendChild(table);

  // Прочие ключи внутри карты (например, note) — прозой под таблицей
  for (const [key, child] of Object.entries(node.children || {})) {
    if (!REFS.grade_keys.includes(key)) wrap.appendChild(renderNode(child, key));
  }

  if (node.sum_to) attachSumBadge(wrap, node.sum_to);
  if (node.hint) wrap.appendChild(hintEl(node.hint));
  return wrap;
}

function renderArray(node, label) {
  const value = getByPath(current.data, node.path);
  if (node.widget === "object_table") return renderObjectTable(node, value);
  if (node.widget === "string_list" || node.widget === "multi_select")
    return renderStringList(node, label);
  // Массив чисел (кривая опыта): по инпуту на ступень
  const wrap = document.createElement("div");
  wrap.className = "chips";
  (value || []).forEach((item, index) => {
    const input = document.createElement("input");
    input.type = "number";
    input.step = Number.isInteger(item) ? "1" : "0.01";
    input.value = item;
    input.style.width = "84px";
    input.oninput = () => {
      const arr = getByPath(current.data, node.path);
      arr[index] = parseNum(input.value, item);
      markDirty(input);
    };
    wrap.appendChild(input);
  });
  if (node.hint) wrap.appendChild(hintEl(node.hint));
  return wrap;
}

function renderObjectTable(node, rows) {
  const wrap = document.createElement("div");
  const table = document.createElement("table");
  table.className = "obj-table";
  const columns = Object.keys((rows && rows[0]) || {});
  const skip = new Set(node.sum_skip || []);
  const head = table.insertRow();
  for (const col of columns) {
    const th = document.createElement("th");
    th.textContent = col;
    head.appendChild(th);
  }
  if (node.row_sum_to) {
    const th = document.createElement("th");
    th.textContent = "Σ";
    head.appendChild(th);
  }
  head.appendChild(document.createElement("th"));

  (rows || []).forEach((rowData, rowIndex) => {
    const tr = table.insertRow();
    const rowInputs = {};
    for (const col of columns) {
      const td = tr.insertCell();
      const input = document.createElement("input");
      input.type = "number";
      input.step = Number.isInteger(rowData[col]) ? "1" : "0.1";
      input.value = rowData[col];
      input.oninput = () => {
        const arr = getByPath(current.data, node.path);
        arr[rowIndex][col] = parseNum(input.value, rowData[col]);
        markDirty(input);
        updateRowSum();
      };
      rowInputs[col] = input;
      td.appendChild(input);
    }
    // Бейдж суммы на КАЖДОЙ строке: строка — самостоятельное распределение
    // (например, шансы грейдов с этой глубины) и обязана давать 100
    let updateRowSum = () => {};
    if (node.row_sum_to) {
      const td = tr.insertCell();
      const badge = document.createElement("span");
      badge.className = "sum-badge";
      td.appendChild(badge);
      updateRowSum = () => {
        let total = 0;
        for (const [col, input] of Object.entries(rowInputs))
          if (!skip.has(col)) total += Number(input.value) || 0;
        badge.textContent = `${round2(total)}`;
        badge.classList.toggle("ok", Math.abs(total - node.row_sum_to) < 0.01);
        badge.classList.toggle("bad", Math.abs(total - node.row_sum_to) >= 0.01);
      };
      updateRowSum();
    }
    const actions = tr.insertCell();
    const del = document.createElement("button");
    del.className = "row-btn";
    del.textContent = "−";
    del.onclick = () => {
      const arr = getByPath(current.data, node.path);
      arr.splice(rowIndex, 1);
      markDirty();
      rerenderCurrentConfig();
    };
    actions.appendChild(del);
  });
  wrap.appendChild(table);

  const add = document.createElement("button");
  add.className = "row-btn";
  add.textContent = "+ строка";
  add.onclick = () => {
    const arr = getByPath(current.data, node.path);
    const template = arr.length ? { ...arr[arr.length - 1] } : {};
    arr.push(template);
    markDirty();
    rerenderCurrentConfig();
  };
  wrap.appendChild(add);
  if (node.hint) wrap.appendChild(hintEl(node.hint));
  return wrap;
}

function renderStringList(node, label) {
  const wrap = document.createElement("div");
  wrap.className = "field";
  const lab = document.createElement("label");
  lab.textContent = label;
  wrap.appendChild(lab);
  const chips = document.createElement("div");
  chips.className = "chips";
  wrap.appendChild(chips);

  const options = node.options ? REFS[node.options] : null;

  const redraw = () => {
    chips.innerHTML = "";
    const arr = getByPath(current.data, node.path) || [];
    arr.forEach((item, index) => {
      const chip = document.createElement("span");
      chip.className = "chip";
      chip.textContent = item;
      const del = document.createElement("button");
      del.textContent = "✕";
      del.onclick = () => { arr.splice(index, 1); markDirty(); redraw(); };
      chip.appendChild(del);
      chips.appendChild(chip);
    });
    let adder;
    if (options) {
      adder = document.createElement("select");
      adder.appendChild(new Option("+ добавить…", ""));
      for (const opt of options)
        if (!arr.includes(opt)) adder.appendChild(new Option(opt, opt));
      adder.onchange = () => {
        if (adder.value) { arr.push(adder.value); markDirty(); redraw(); }
      };
    } else {
      adder = document.createElement("input");
      adder.type = "text";
      adder.placeholder = "+ добавить и Enter";
      adder.style.width = "160px";
      adder.onkeydown = (e) => {
        if (e.key === "Enter" && adder.value.trim()) {
          arr.push(adder.value.trim());
          markDirty(); redraw();
        }
      };
    }
    chips.appendChild(adder);
  };
  redraw();
  if (node.hint) wrap.appendChild(hintEl(node.hint));
  return wrap;
}

function renderLeafField(node, label) {
  const wrap = document.createElement("div");
  wrap.className = "field";
  const lab = document.createElement("label");
  lab.textContent = label;
  wrap.appendChild(lab);
  wrap.appendChild(node.widget === "image"
    ? imageWidget(getByPath(current.data, node.path),
        (v) => { setByPath(current.data, node.path, v); markDirty(); })
    : leafInput(node));
  if (node.hint) wrap.appendChild(hintEl(node.hint));
  return wrap;
}

function leafInput(node) {
  const value = getByPath(current.data, node.path);
  if (node.widget === "select") {
    const select = document.createElement("select");
    for (const opt of REFS[node.options] || [])
      select.appendChild(new Option(opt, opt, false, opt === value));
    select.onchange = () => {
      setByPath(current.data, node.path, select.value);
      markDirty(select);
    };
    return select;
  }
  if (node.kind === "bool") {
    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = Boolean(value);
    input.onchange = () => {
      setByPath(current.data, node.path, input.checked);
      markDirty(input);
    };
    return input;
  }
  const input = document.createElement("input");
  if (node.kind === "int" || node.kind === "float") {
    input.type = "number";
    input.step = node.kind === "int" ? "1" : "0.01";
    input.value = value;
    input.oninput = () => {
      setByPath(current.data, node.path, parseNum(input.value, value));
      markDirty(input);
    };
  } else {
    input.type = "text";
    input.value = value ?? "";
    input.oninput = () => {
      setByPath(current.data, node.path, input.value);
      markDirty(input);
    };
  }
  return input;
}

function rerenderCurrentConfig() {
  // Полная перерисовка нужна только структурным правкам (строки таблиц);
  // обычный ввод обновляет data на месте и фокус не теряет
  const { name } = current;
  const data = current.data;
  const schema = current.schema;
  const content = $("#content");
  content.innerHTML = "";
  for (const [key, child] of Object.entries(schema.children || {}))
    content.appendChild(renderTopLevel(key, child));
  void name; void data;
}

// --- сохранение и валидация ---------------------------------------------------

function markDirty(el) {
  if (!current || current.readonly) return;
  current.dirty = true;
  $("#dirty-dot").hidden = false;
  $("#save-btn").disabled = false;
  if (el) el.classList.add("changed");
  if (current.type === "config") {
    clearTimeout(validateTimer);
    validateTimer = setTimeout(dryValidate, 600);
  }
}

async function dryValidate() {
  if (!current || current.type !== "config") return;
  const res = await fetch("/api/validate", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ [current.name]: current.data }),
  });
  showProblems(await res.json());
}

async function saveCurrent() {
  if (!current || current.type !== "config") return;
  const res = await fetch(`/api/configs/${current.name}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(current.data),
  });
  if (res.status === 409) {
    const body = await res.json();
    showProblems(body.detail);
    toast("Не сохранено: валидатор против", true);
    return;
  }
  if (!res.ok) { toast(`Ошибка ${res.status}`, true); return; }
  const body = await res.json();
  current.dirty = false;
  $("#dirty-dot").hidden = true;
  $("#save-btn").disabled = true;
  document.querySelectorAll(".changed")
    .forEach((el) => el.classList.remove("changed"));
  showProblems({ errors: [], warnings: body.warnings || [] });
  toast(`Сохранено · бэкап ${body.backup}`);
}

function showProblems(result) {
  const box = $("#problems");
  if (!result || (!result.errors?.length && !result.warnings?.length)) {
    box.hidden = true;
    box.innerHTML = "";
    return;
  }
  box.hidden = false;
  box.innerHTML = "";
  for (const err of result.errors || []) {
    const div = document.createElement("div");
    div.className = "err";
    div.textContent = "✕ " + err;
    box.appendChild(div);
  }
  for (const warn of result.warnings || []) {
    const div = document.createElement("div");
    div.className = "warn";
    div.textContent = "⚠ " + warn;
    box.appendChild(div);
  }
}

// --- сущности -----------------------------------------------------------------

async function openEntities(kind, label, btn) {
  if (current?.dirty
      && !confirm("Есть несохранённые правки — бросить их?")) return;
  activateNav(btn);
  stopAudio();
  current = { type: "entities", kind, dirty: false };
  $("#crumbs").textContent = label;
  $("#save-btn").hidden = true;
  $("#dirty-dot").hidden = true;
  showProblems(null);

  const extras = {};
  if (kind === "monsters") {
    // Список готовых спрайтов: лента грейдов не должна светить битыми img
    const body = await getJSON("/api/images?dir=monster");
    extras.monsterImages = new Set(body.files || []);
    // Множители грейдов и пороги дружбы: статы грейда = база × множитель,
    // и переключатель обязан показывать именно то, что увидит игрок
    const progression = (await getJSON("/api/configs/progression.json")).data;
    extras.statScale = progression.grade_multipliers.stat_scale;
    extras.strikeScale = progression.grade_multipliers.strike_scale;
    extras.thresholds = progression.friendship.thresholds;
  }

  const rows = await getJSON(`/api/entities/${kind}`);
  const content = $("#content");
  content.innerHTML = "";
  for (const row of rows) content.appendChild(entityCard(kind, row, extras));
}

function entityCard(kind, row, extras) {
  const card = document.createElement("section");
  card.className = "entity-card";
  const title = document.createElement("h3");
  title.textContent = row.identity.display_name || row.id;
  title.innerHTML += `<span class="id">${row.id} · ${row.file}</span>`;
  card.appendChild(title);

  const pending = { identity: {}, stats: {} };
  // Текущее значение с учётом несохранённых правок: кнопка «послушать»
  // обязана играть то, что выбрано в селекте, а не то, что на диске
  const liveValue = (field) => pending.identity[field] ?? row.identity[field];
  const cols = document.createElement("div");
  cols.className = "cols";
  card.appendChild(cols);

  // -- идентичность (.tres)
  const colIdentity = document.createElement("div");
  colIdentity.className = "col";
  colIdentity.innerHTML = "<h5>Идентичность (.tres)</h5>";
  cols.appendChild(colIdentity);

  const identityEls = {};
  // Выбранный грейд — общий переключатель карточки: статы, прослушка
  // и замена спрайта работают с НИМ, а не только с коммоном
  let selectedGrade = "common";
  let renderMonsterStats = null;
  let listenBtn = null;
  let spriteBtn = null;
  const stripFigures = {};

  for (const field of row.editable_identity) {
    if (!(field in row.identity)) continue;
    const value = row.identity[field];
    const wrap = document.createElement("div");
    wrap.className = "field";
    const lab = document.createElement("label");
    lab.textContent = field;
    wrap.appendChild(lab);
    const input = identityInput(kind, row, field, value,
      (v) => { pending.identity[field] = v; enableSave(); });
    identityEls[field] = input;
    wrap.appendChild(input);

    if (kind === "monsters" && field === "motif_id") {
      const currentStem = () => {
        const genreKey = REFS.genre_keys[Number(liveValue("genre"))];
        const tracks = REFS.track_index[`${genreKey}_${liveValue("motif_id")}`] || {};
        // Ремикс выбранного грейда: у каждого грейда свой темп,
        // и слушать надо именно то, что услышит игрок на этом грейде
        return tracks[selectedGrade] || tracks.common || Object.values(tracks)[0];
      };
      listenBtn = playButton(`послушать · ${selectedGrade}`, currentStem);
      wrap.appendChild(listenBtn);
      const pickBtn = document.createElement("button");
      pickBtn.className = "play-btn";
      pickBtn.textContent = "мелодии…";
      pickBtn.onclick = () => openMelodyPicker(
        REFS.genre_keys[Number(liveValue("genre"))],
        liveValue("motif_id"),
        (motif) => {
          pending.identity.motif_id = motif;
          identityEls.motif_id.value = motif;
          enableSave();
        });
      wrap.appendChild(pickBtn);
    }
    colIdentity.appendChild(wrap);
  }

  // -- лента грейдов: спрайты открываются по конвенции <id>_<грейд>.png.
  // Она же — переключатель: выбранный грейд задаёт, чьи статы, чей ремикс
  // и чей спрайт показывает и правит остальная карточка
  if (kind === "monsters" && extras?.monsterImages) {
    const h = document.createElement("h5");
    h.textContent = "Грейды — переключатель карточки";
    colIdentity.appendChild(h);
    const strip = document.createElement("div");
    strip.className = "grade-strip";

    const fillFigure = (fig, grade, bust) => {
      fig.innerHTML = "";
      const file = `${row.id}_${grade}.png`;
      if (extras.monsterImages.has(file)) {
        const img = document.createElement("img");
        img.loading = "lazy";
        img.src = `/art/monster/${file}` + (bust ? `?v=${Date.now()}` : "");
        img.title = file;
        fig.appendChild(img);
      } else {
        const missing = document.createElement("div");
        missing.className = "missing";
        missing.textContent = "нет";
        fig.appendChild(missing);
      }
      const cap = document.createElement("figcaption");
      cap.textContent = grade;
      fig.appendChild(cap);
    };

    for (const grade of REFS.grade_keys) {
      const fig = document.createElement("figure");
      fig.dataset.grade = grade;
      if (grade === selectedGrade) fig.classList.add("active");
      fillFigure(fig, grade, false);
      fig.onclick = () => {
        selectedGrade = grade;
        stopAudio();
        strip.querySelectorAll("figure").forEach(
          (f) => f.classList.toggle("active", f.dataset.grade === grade));
        if (listenBtn) {
          listenBtn.dataset.label = `послушать · ${grade}`;
          listenBtn.textContent = "▶ " + listenBtn.dataset.label;
        }
        if (spriteBtn) spriteBtn.textContent = `заменить спрайт «${grade}»…`;
        if (renderMonsterStats) renderMonsterStats();
      };
      stripFigures[grade] = fig;
      strip.appendChild(fig);
    }
    colIdentity.appendChild(strip);

    // Замена спрайта выбранного грейда: копия выбранной картинки в слот
    // конвенции art/monster/<id>_<грейд>.png (старый файл — в бэкап)
    spriteBtn = document.createElement("button");
    spriteBtn.className = "play-btn";
    spriteBtn.textContent = `заменить спрайт «${selectedGrade}»…`;
    spriteBtn.onclick = () => {
      const grade = selectedGrade;
      openImagePicker(`res://art/monster/${row.id}_${grade}.png`,
        async (chosen) => {
          const res = await fetch(
            `/api/entities/monsters/${row.id}/grade_sprite`, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ grade, source: chosen }),
            });
          if (!res.ok) {
            const body = await res.json().catch(() => ({}));
            toast(body.detail || `Ошибка ${res.status}`, true);
            return;
          }
          const body = await res.json();
          extras.monsterImages.add(`${row.id}_${grade}.png`);
          fillFigure(stripFigures[grade], grade, true);
          stripFigures[grade].classList.add("active");
          toast(body.unchanged
            ? "Это тот же файл — ничего не изменилось"
            : `Спрайт ${grade} заменён · бэкап ${body.backup}`);
        });
    };
    colIdentity.appendChild(spriteBtn);
  }

  // -- статы (JSON)
  const colStats = document.createElement("div");
  colStats.className = "col";
  cols.appendChild(colStats);
  const statKeys = Object.keys(row.stats).filter((k) => !k.startsWith("_"));
  if (kind === "monsters" && extras?.statScale) {
    // У монстра статы грейда = база × глобальный множитель грейда
    // (progression.json). Переключатель показывает эффективные числа
    // выбранного грейда; правка на любом грейде пересчитывает БАЗУ —
    // отдельных статов на грейд в игре нет, лестница едина (GDD §6.3)
    const liveBase = (key) => pending.stats[key] ?? row.stats[key];

    renderMonsterStats = () => {
      const scale = Number(extras.statScale[selectedGrade] || 1);
      colStats.innerHTML =
        `<h5>Числа грейда «${selectedGrade}» (JSON)</h5>`;

      const fields = [
        { key: "base_vibe", label: "Настрой", int: true },
        { key: "base_health", label: "Здоровье", int: true },
        { key: "base_power", label: "Сила удара", int: false },
      ];
      for (const f of fields) {
        const base = Number(liveBase(f.key));
        const effective = f.int
          ? Math.round(base * scale)
          : Math.round(base * scale * 100) / 100;

        const wrap = document.createElement("div");
        wrap.className = "field";
        const lab = document.createElement("label");
        lab.textContent = f.label;
        wrap.appendChild(lab);

        const input = document.createElement("input");
        input.type = "number";
        input.step = f.int ? "1" : "0.01";
        input.value = effective;
        wrap.appendChild(input);

        const hint = document.createElement("div");
        hint.className = "hint";
        const baseText = () => {
          const b = Number(liveBase(f.key));
          return scale === 1
            ? `это база вида (${f.key})`
            : `база ${f.int ? Math.round(b) : b} × ${scale} (${f.key})`;
        };
        hint.textContent = baseText();
        wrap.appendChild(hint);

        input.oninput = () => {
          const raw = Number(input.value);
          if (Number.isNaN(raw)) return;
          // Обратный пересчёт: правка легендарного двигает базу, и вся
          // лестница масштабируется — единственная честная семантика
          // при глобальных множителях
          const newBase = f.int
            ? Math.round(raw / scale)
            : Math.round(raw / scale * 1000) / 1000;
          pending.stats[f.key] = newBase;
          hint.textContent = baseText();
          input.classList.add("changed");
          enableSave();
        };
        colStats.appendChild(wrap);
      }

      // Производные грейда, которые правятся не здесь — но видеть их
      // рядом со статами нужно, иначе грейд опять читается только цифрой
      const derived = document.createElement("div");
      derived.className = "doc";
      derived.textContent =
        `Злость (множитель удара): ×${extras.strikeScale[selectedGrade]}\n`
        + `Порог дружбы: ${extras.thresholds[selectedGrade]}\n`
        + "Множители и пороги общие для всех видов — правятся "
        + "в progression.json → grade_multipliers / friendship.";
      colStats.appendChild(derived);
    };
    renderMonsterStats();
  } else if (statKeys.length) {
    colStats.innerHTML = "<h5>Числа (JSON)</h5>";
    for (const key of statKeys) {
      const value = row.stats[key];
      const wrap = document.createElement("div");
      wrap.className = "field";
      const lab = document.createElement("label");
      lab.textContent = key;
      wrap.appendChild(lab);
      let input;
      if (typeof value === "boolean") {
        input = document.createElement("input");
        input.type = "checkbox";
        input.checked = value;
        input.onchange = () => { pending.stats[key] = input.checked; enableSave(); };
      } else if (typeof value === "string") {
        if (REFS.grade_keys.includes(value)) {
          input = document.createElement("select");
          for (const g of REFS.grade_keys)
            input.appendChild(new Option(g, g, false, g === value));
          input.onchange = () => { pending.stats[key] = input.value; enableSave(); };
        } else {
          input = document.createElement("input");
          input.type = "text";
          input.value = value;
          input.oninput = () => { pending.stats[key] = input.value; enableSave(); };
        }
      } else {
        input = document.createElement("input");
        input.type = "number";
        input.step = Number.isInteger(value) ? "1" : "0.01";
        input.value = value;
        input.oninput = () => {
          pending.stats[key] = parseNum(input.value, value);
          enableSave();
        };
      }
      wrap.appendChild(input);
      colStats.appendChild(wrap);
    }
  } else if (kind === "fruits") {
    colStats.innerHTML = '<h5>Числа</h5><p class="muted">Все числа фруктов — '
      + "по тирам в fruits.json (таблица слева).</p>";
  }

  const saveRow = document.createElement("div");
  saveRow.className = "save-row";
  const saveBtn = document.createElement("button");
  saveBtn.textContent = "Сохранить";
  saveBtn.disabled = true;
  saveRow.appendChild(saveBtn);
  card.appendChild(saveRow);

  function enableSave() { saveBtn.disabled = false; }

  saveBtn.onclick = async () => {
    const res = await fetch(`/api/entities/${kind}/${row.id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(pending),
    });
    if (res.status === 409) {
      showProblems((await res.json()).detail);
      toast("Не сохранено: валидатор против", true);
      return;
    }
    if (!res.ok) { toast(`Ошибка ${res.status}`, true); return; }
    const body = await res.json();
    saveBtn.disabled = true;
    showProblems({ errors: [], warnings: body.warnings || [] });
    toast(`Сохранено · бэкап ${body.backup}`);
  };
  return card;
}

function identityInput(kind, row, field, value, onChange) {
  if (field === "genre") {
    const select = document.createElement("select");
    REFS.genre_keys.forEach((genre, index) => {
      select.appendChild(new Option(GENRE_NAMES[genre] || genre, index,
        false, index === Number(value)));
    });
    select.onchange = () => onChange(Number(select.value));
    return select;
  }
  if (field === "motif_id") {
    const select = document.createElement("select");
    const genreIndex = Number(row.identity.genre ?? -1);
    const genreKey = REFS.genre_keys[genreIndex];
    for (const motif of REFS.motif_ids) {
      const grades = REFS.chart_index[`${genreKey}_${motif}`] || [];
      const complete = REFS.grade_keys.every((g) => grades.includes(g));
      const opt = new Option(
        complete ? motif : `${motif} (чартов: ${grades.length}/6)`,
        motif, false, motif === value);
      // Мотив без полного комплекта чартов выбрать нельзя: бой молча
      // уйдёт на запасной трек, и валидатор такое всё равно не пропустит
      opt.disabled = !complete;
      select.appendChild(opt);
    }
    select.onchange = () => onChange(select.value);
    return select;
  }
  if (field === "favorite_fruit_id") {
    const select = document.createElement("select");
    for (const fruit of REFS.fruit_ids) {
      const label = REFS.display_names.fruits[fruit]
        ? `${REFS.display_names.fruits[fruit]} (${fruit})` : fruit;
      select.appendChild(new Option(label, fruit, false, fruit === value));
    }
    select.onchange = () => onChange(select.value);
    return select;
  }
  if (field === "slot") {
    const names = kind === "gear" ? GEAR_SLOTS
      : kind === "cosmetics" ? COSMETIC_SLOTS : null;
    if (names) {
      const select = document.createElement("select");
      names.forEach((name, index) => {
        select.appendChild(new Option(name, index, false,
          index === Number(value)));
      });
      select.onchange = () => onChange(Number(select.value));
      return select;
    }
  }
  if (field === "rarity") {
    const select = document.createElement("select");
    REFS.grade_keys.forEach((grade, index) => {
      select.appendChild(new Option(grade, index, false,
        index === Number(value)));
    });
    select.onchange = () => onChange(Number(select.value));
    return select;
  }
  if (field === "sprite_path") {
    return imageWidget(value, onChange);
  }
  if (field === "tier") {
    const input = document.createElement("input");
    input.type = "number";
    input.step = "1"; input.min = "0"; input.max = "3";
    input.value = value;
    input.oninput = () => onChange(parseInt(input.value, 10) || 0);
    return input;
  }
  const input = document.createElement("input");
  input.type = "text";
  input.value = value ?? "";
  input.oninput = () => onChange(input.value);
  return input;
}

// --- виджет картинки ----------------------------------------------------------

function imageWidget(value, onChange) {
  const wrap = document.createElement("div");
  wrap.className = "img-field";
  const img = document.createElement("img");
  const path = document.createElement("span");
  path.className = "path";
  const update = (v) => {
    img.src = v ? "/" + String(v).replace("res://", "") : "";
    img.alt = v || "нет";
    path.textContent = v || "не задан";
  };
  update(value);
  const pick = document.createElement("button");
  pick.textContent = "выбрать…";
  pick.onclick = () => openImagePicker(value, (chosen) => {
    update(chosen);
    onChange(chosen);
  });
  wrap.append(img, path, pick);
  return wrap;
}

async function openImagePicker(currentValue, onPick) {
  const modal = $("#modal");
  const tabs = $("#modal-tabs");
  const grid = $("#modal-grid");
  const search = $("#modal-search");
  modal.hidden = false;
  tabs.innerHTML = "";
  grid.innerHTML = "";
  search.value = "";

  const currentDir = String(currentValue || "")
    .replace("res://art/", "").split("/")[0];
  let files = [];
  let activeDir = REFS.image_dirs.includes(currentDir)
    ? currentDir : REFS.image_dirs[0];

  async function loadDir(dir) {
    activeDir = dir;
    tabs.querySelectorAll("button").forEach(
      (b) => b.classList.toggle("active", b.textContent === dir));
    const body = await getJSON(`/api/images?dir=${encodeURIComponent(dir)}`);
    files = body.files || [];
    drawGrid();
  }

  function drawGrid() {
    grid.innerHTML = "";
    const filter = search.value.trim().toLowerCase();
    for (const file of files) {
      if (filter && !file.toLowerCase().includes(filter)) continue;
      const fig = document.createElement("figure");
      const img = document.createElement("img");
      img.loading = "lazy";
      img.src = `/art/${activeDir}/${file}`;
      const cap = document.createElement("figcaption");
      cap.textContent = file;
      fig.append(img, cap);
      fig.onclick = () => {
        onPick(`res://art/${activeDir}/${file}`);
        closeModal();
      };
      grid.appendChild(fig);
    }
  }

  for (const dir of REFS.image_dirs) {
    const btn = document.createElement("button");
    btn.textContent = dir;
    btn.onclick = () => loadDir(dir);
    tabs.appendChild(btn);
  }
  search.oninput = drawGrid;
  await loadDir(activeDir);
}

function closeModal() { $("#modal").hidden = true; }

// --- попап мелодий ------------------------------------------------------------
// Мотив слушают, а не угадывают по имени: каждая строка — все шесть
// ремиксов (грейд = темп). Выбрать можно только мотив с полным комплектом
// чартов текущего жанра — неполный бой молча уйдёт на запасной трек.

function openMelodyPicker(genreKey, currentMotif, onPick) {
  const modal = $("#melody-modal");
  const list = $("#melody-list");
  modal.hidden = false;
  $("#melody-title").textContent =
    `Мелодии · жанр ${GENRE_NAMES[genreKey] || genreKey}`;
  list.innerHTML = "";

  for (const motif of REFS.motif_ids) {
    const pair = `${genreKey}_${motif}`;
    const tracks = REFS.track_index[pair] || {};
    const chartGrades = REFS.chart_index[pair] || [];
    const complete = REFS.grade_keys.every((g) => chartGrades.includes(g));

    const rowEl = document.createElement("div");
    rowEl.className = "melody-row" + (motif === currentMotif ? " current" : "");

    const name = document.createElement("div");
    name.className = "name";
    name.textContent = REFS.motif_titles[motif] || motif;
    const id = document.createElement("span");
    id.className = "id";
    id.textContent = motif + (motif === currentMotif ? " · текущий" : "");
    name.appendChild(id);
    rowEl.appendChild(name);

    const grades = document.createElement("div");
    grades.className = "grades";
    for (const grade of REFS.grade_keys) {
      const stem = tracks[grade];
      if (!stem) continue;
      const bpm = stem.split("_").pop();
      grades.appendChild(playButton(`${grade} · ${bpm}`, () => stem));
    }
    if (!grades.children.length) {
      const none = document.createElement("span");
      none.className = "muted";
      none.textContent = "треков нет";
      grades.appendChild(none);
    }
    rowEl.appendChild(grades);

    const pick = document.createElement("button");
    pick.className = "pick";
    pick.textContent = "выбрать";
    pick.disabled = !complete;
    if (!complete)
      pick.title = `чартов ${chartGrades.length}/6 — выбрать нельзя`;
    pick.onclick = () => { onPick(motif); closeMelodyModal(); };
    rowEl.appendChild(pick);

    list.appendChild(rowEl);
  }
}

function closeMelodyModal() {
  stopAudio();
  $("#melody-modal").hidden = true;
}

// --- бэкапы -------------------------------------------------------------------

async function openBackups(btn) {
  if (current?.dirty
      && !confirm("Есть несохранённые правки — бросить их?")) return;
  activateNav(btn);
  stopAudio();
  current = { type: "backups", dirty: false };
  $("#crumbs").textContent = "Бэкапы";
  $("#save-btn").hidden = true;
  $("#dirty-dot").hidden = true;
  showProblems(null);

  const list = await getJSON("/api/backups");
  const content = $("#content");
  content.innerHTML = "";
  if (!list.length) {
    content.innerHTML = '<p class="muted">Точек пока нет: они появляются '
      + "при каждом сохранении.</p>";
    return;
  }
  for (const meta of list) {
    const row = document.createElement("div");
    row.className = "backup-row";
    const stamp = document.createElement("span");
    stamp.className = "stamp";
    stamp.textContent = meta.stamp;
    const files = document.createElement("span");
    files.className = "files";
    files.textContent = (meta.changed || []).join(", ")
      || meta.note || "полный срез";
    const restore = document.createElement("button");
    restore.textContent = "Откатиться";
    restore.onclick = async () => {
      if (!confirm(`Восстановить все конфиги из точки ${meta.stamp}?\n`
        + "Текущее состояние сохранится отдельной точкой.")) return;
      const res = await fetch(`/api/backups/${meta.stamp}/rollback`,
        { method: "POST" });
      if (!res.ok) { toast(`Ошибка ${res.status}`, true); return; }
      const body = await res.json();
      toast(`Восстановлено файлов: ${body.restored.length}`);
      openBackups(btn);
    };
    row.append(stamp, files, restore);
    content.appendChild(row);
  }
}

// --- утилиты ------------------------------------------------------------------

async function getJSON(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: ${res.status}`);
  return res.json();
}

function getByPath(obj, path) {
  if (!path) return obj;
  let node = obj;
  for (const part of path.split(".")) {
    if (node == null) return undefined;
    node = node[part];
  }
  return node;
}

function setByPath(obj, path, value) {
  const parts = path.split(".");
  let node = obj;
  for (const part of parts.slice(0, -1)) node = node[part];
  node[parts[parts.length - 1]] = value;
}

function parseNum(raw, previous) {
  const num = Number(raw);
  if (Number.isNaN(num)) return previous;
  return num;
}

function round2(x) { return Math.round(x * 100) / 100; }

function hintEl(text) {
  const div = document.createElement("div");
  div.className = "hint";
  div.textContent = text;
  return div;
}

function toast(text, fail) {
  const div = document.createElement("div");
  div.className = "toast" + (fail ? " fail" : "");
  div.textContent = text;
  document.body.appendChild(div);
  setTimeout(() => div.remove(), 3500);
}

boot();

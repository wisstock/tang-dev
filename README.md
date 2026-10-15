# Sipeed Tang Nano 9K - open FPGA stack on macOS

[![Stand With Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/banner-direct-single.svg)](https://stand-with-ukraine.pp.ua)

[English](#english) · [Українська](#українська)

## English

Open-source flow for the Sipeed Tang Nano 9K (Gowin GW1NR-LV9QN88PC6/I5) on Apple Silicon Macs: lint, cocotb simulation, synthesis, place & route, bitstream, programming. All tools live in `.tools/`; nothing is installed system-wide and `Makefile` sets `PATH`.

**Flow:** Yosys `synth_gowin` → `nextpnr-himbaechel` (gowin) → `gowin_pack` → `.fs` → `openFPGALoader -b tangnano9k`

### Repository layout

| Path | Contents | In git |
| --- | --- | --- |
| `FPGA_INTRO.md` | FPGA introduction for beginners: what an FPGA is, bitstream, toolchain, project structure | yes |
| `Makefile` | all targets (see **Make targets**) | yes |
| `Makefile.sim` | generic cocotb runner (Icarus, FST waves), called by `make sim` | yes |
| `demo/<name>/` | one design: `*.sv` (one module per file, named after it), `*.cst` pins, `test_*.py` cocotb tests, `demo.mk` | yes |
| `templates/tangnano9k.cst` | all on-board I/O (clock, 6 LEDs, 2 buttons, UART); copy pins from here | yes |
| `tools.lock` | pinned toolchain: archive, URL, size, SHA-256, tool versions | yes |
| `scripts/check_tools.sh` | used by `make check-tools` | yes |
| `.vscode/` | settings, tasks (design picker), recommended extensions | yes |
| `.tools/oss-cad-suite/` | extracted OSS CAD Suite (yosys, nextpnr, gowin_pack, iverilog, verilator, cocotb, gtkwave, openFPGALoader) | no |
| `downloads/` | OSS CAD Suite archive | no |
| `build/<name>/` | build and simulation output (see **Make targets**) | no |
| `backup/` | `tangnano9k_flash_backup.fs`: Sipeed restore image for the on-chip flash | no |

### Setup

The pinned toolchain (archive, URL, SHA-256, tool versions) is in `tools.lock`; the commands below read it, so nothing needs copying by hand. Run them from the repository root.

1. Download the OSS CAD Suite archive (darwin-arm64, ~520 MB):
   ```bash
   A=$(awk '$1=="archive"{print $3}' tools.lock)
   mkdir -p downloads
   curl -L -o downloads/$A "$(awk '$1=="url"{print $3}' tools.lock)"
   ```
   If a sibling project already has it, an APFS clone needs no download or extra space: `cp -c <other-project>/downloads/$A downloads/`
2. Verify the archive, extract it into `.tools/` and check the tool versions — must end with `check-tools: OK`:
   ```bash
   make check-tools
   ```
3. Check: `make lint sim build` → no lint warnings, `TESTS=3 PASS=3`, last `Max frequency` line `PASS at 27.00 MHz`.

### Make targets

`<demo>` = `DEMO`, `<top>` = `TOP` from its `demo.mk`. `make` alone = `make build`.

| Target | What it does | Output | Board |
| --- | --- | --- | --- |
| `check-tools` | verify the archive hash and tool versions against `tools.lock`; extract `.tools/` if missing; ends with `check-tools: OK` | `.tools/oss-cad-suite/` | no |
| `demos` | list designs in `demo/` | — | no |
| `lint` | Verilator `--lint-only -Wall` on `SOURCES` | — | no |
| `sim` | cocotb `TEST` with Icarus via `Makefile.sim`; `SIM_PARAMS` apply here only | `build/<demo>/results.xml`, `sim_build/<top>.fst` | no |
| `waves` | open the last simulation in gtkwave (run it from your own terminal) | — | no |
| `build` | Yosys `synth_gowin` → nextpnr-himbaechel (27 MHz target, `CST` pins) → `gowin_pack`; rebuilds only what changed | `build/<demo>/<top>.json`, `<top>_pnr.json`, `<top>.fs`, `yosys.log`, `nextpnr.log` | no |
| `detect` | `openFPGALoader --detect`; expect idcode `0x100481b` | — | yes |
| `flash-sram` | build if needed, load `<top>.fs` into SRAM (lost on power-off) | — | yes |
| `flash-perm` | build if needed, erase and write the on-chip flash (starts at power-on) | — | yes |
| `clean` / `clean-all` | remove `build/<demo>` / `build/` | — | no |

| Variable | Default | Meaning |
| --- | --- | --- |
| `DEMO` | `blinky` | design folder in `demo/` (all targets except `demos`, `detect`, `clean-all`) |
| `OSS_CAD` | `.tools/oss-cad-suite` | toolchain location; `Makefile` puts its `bin/` first in `PATH` |

### Without make

The same steps with the tools called directly. Run from the repository root; the example is `btn_counter` — take `TOP`, `SOURCES` (in order), `CST`, `TEST` and `SIM_PARAMS` from the design's `demo.mk`.

```bash
export PATH="$PWD/.tools/oss-cad-suite/bin:$PATH"   # this terminal only
D=demo/btn_counter; TOP=btn_counter; B=build/btn_counter
SRC="$D/button_conditioner.sv $D/btn_counter.sv"
mkdir -p $B
```

Lint:
```bash
verilator --lint-only -Wall --top-module $TOP $SRC
```

Simulation (cocotb Python runner, Icarus; `parameters` = `SIM_PARAMS`):
```bash
D=$D TOP=$TOP B=$B SRC="$SRC" tabbypy3 - <<'EOF'
import os
from cocotb_tools.runner import get_runner
e = os.environ
b = os.path.abspath(e["B"])
r = get_runner("icarus")
r.build(sources=e["SRC"].split(), hdl_toplevel=e["TOP"], parameters={"DEBOUNCE_CYCLES": 8},
        build_dir=b + "/sim_build", waves=True)
r.test(hdl_toplevel=e["TOP"], test_module="test_" + e["TOP"], test_dir=e["D"],
       build_dir=b + "/sim_build", results_xml=b + "/results.xml", waves=True)
EOF
gtkwave $B/sim_build/$TOP.fst
```

Bitstream (synthesis → place & route → pack):
```bash
yosys -q -l $B/yosys.log -p "read_verilog -sv $SRC; synth_gowin -top $TOP -json $B/$TOP.json"
nextpnr-himbaechel --json $B/$TOP.json --write $B/${TOP}_pnr.json \
  --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C --vopt cst=$D/tangnano9k.cst \
  --freq 27 -l $B/nextpnr.log
gowin_pack -d GW1N-9C -o $B/$TOP.fs $B/${TOP}_pnr.json
```

Board:
```bash
openFPGALoader --detect
openFPGALoader -b tangnano9k $B/$TOP.fs      # SRAM, lost on power-off
openFPGALoader -b tangnano9k -f $B/$TOP.fs   # on-chip flash, starts at power-on
```

### Designs

| Design | Behaviour | Tests |
| --- | --- | --- |
| `blinky` | binary counter on the 6 LEDs; S1 resets | 3 |
| `btn_counter` | 6-bit counter: S2 = +1, S1 = −1, both = 0; debounced, wraps | 7 |

New design: copy a folder in `demo/`, edit `demo.mk` (`TOP`, `SOURCES`, `CST`, `TEST`, `SIM_PARAMS`), take pins from `templates/tangnano9k.cst`, add the name to `.vscode/tasks.json`.

### Board I/O

| Signal | Pin | Notes |
| --- | --- | --- |
| `clk` | 52 | 27 MHz, LVCMOS33 |
| `led[0..5]` | 10, 11, 13, 14, 15, 16 | active low, LVCMOS18; `led[0]` is at the S1 end |
| `btn_n[0]`, `btn_n[1]` | 3, 4 | printed S2, S1; active low, pull-up, LVCMOS18 |
| `uart_tx`, `uart_rx` | 17, 18 | USB-UART via BL702, LVCMOS33 |

Sources: Apicula `examples/tangnano9k.cst`, cross-checked with `sipeed/TangNano-9K-example`. Every top-level port needs a CST line, otherwise `ERROR: Unconstrained IO`.

### On-board flash

| | Internal (in GW1NR-9C) | External SPI (PUYA P25Q32H, 4 MiB) |
| --- | --- | --- |
| Holds | configuration (bitstream), loaded at power-on | user data for the design |
| `openFPGALoader -f` | writes it (full erase first; `--verify` not supported) | only with `--external-flash` |
| `--detect -f` / `--dump-flash` | not supported (no readback in openFPGALoader 1.1.1) | `--dump-flash` reads this one; erases SRAM first; ~330 B/s (full dump ≈ 3.5 h) |

No dump of either flash was kept. The restore reference for the internal flash is Sipeed's image from `sipeed/TangNano-9K-example`.

### VS Code

Open the repository folder and install the recommended extensions (Verilog-HDL, Python). Settings and tasks are in `.vscode/` (Terminal → Run Task…, ⇧⌘B builds). `verilog.linting.path` is absolute — fix it if you move the repo. Python is the OSS CAD Suite one; do not use a separate venv for cocotb (extra packages: `.tools/oss-cad-suite/bin/tabbypip install <pkg>`).

Self-test: delete a `;` in a `.sv` file → a Verilator error appears in Problems; tasks "1. Simulate (cocotb)" and "3. Build bitstream" for `blinky` give the results from **Setup** step 3.

### Notes

- `gowin_pack` warns that Numpy/Msgspec/fastcrc are missing — speed only, safe to ignore.
- gtkwave and other tools write to `~/.config/yosyshq`; run them from your own terminal.
- Verified on hardware (2026-10-15): `make detect`, `make flash-sram` (both designs), `make flash-perm DEMO=btn_counter` (starts after a power cycle).
- Restore the Sipeed image: `.tools/oss-cad-suite/bin/openFPGALoader -b tangnano9k -f backup/tangnano9k_flash_backup.fs`.

## Українська

Відкритий ланцюжок для Sipeed Tang Nano 9K (Gowin GW1NR-LV9QN88PC6/I5) на Mac з Apple Silicon: лінтинг, симуляція cocotb, синтез, розміщення й трасування, бітстрім, прошивка. Інструменти лежать у `.tools/`, система не змінюється, PATH задає `Makefile`.

**Ланцюжок:** Yosys `synth_gowin` → `nextpnr-himbaechel` (gowin) → `gowin_pack` → `.fs` → `openFPGALoader -b tangnano9k`

### Структура репозиторію

| Шлях | Вміст | У git |
| --- | --- | --- |
| `FPGA_INTRO.md` | вступ до FPGA для початківців: що таке FPGA, бітстрім, інструменти, структура проєкту | так |
| `Makefile` | усі цілі (див. **Цілі make**) | так |
| `Makefile.sim` | загальний запускач cocotb (Icarus, осцилограми FST), викликається з `make sim` | так |
| `demo/<назва>/` | один дизайн: `*.sv` (один модуль на файл, файл названо за модулем), піни `*.cst`, тести cocotb `test_*.py`, `demo.mk` | так |
| `templates/tangnano9k.cst` | усі входи й виходи плати (тактовий сигнал, 6 LED, 2 кнопки, UART); піни беріть звідси | так |
| `tools.lock` | зафіксований набір інструментів: архів, URL, розмір, SHA-256, версії | так |
| `scripts/check_tools.sh` | використовується в `make check-tools` | так |
| `.vscode/` | налаштування, задачі (вибір дизайну), рекомендовані розширення | так |
| `.tools/oss-cad-suite/` | розпакований OSS CAD Suite (yosys, nextpnr, gowin_pack, iverilog, verilator, cocotb, gtkwave, openFPGALoader) | ні |
| `downloads/` | архів OSS CAD Suite | ні |
| `build/<назва>/` | результати збірки й симуляції (див. **Цілі make**) | ні |
| `backup/` | `tangnano9k_flash_backup.fs`: образ Sipeed для відновлення вбудованої flash | ні |

### Налаштування

Зафіксований набір інструментів (архів, URL, SHA-256, версії програм) — у `tools.lock`; команди нижче читають його самі, нічого не треба переписувати вручну. Запускайте їх з кореня репозиторію.

1. Завантажте архів OSS CAD Suite (darwin-arm64, ~520 МБ):
   ```bash
   A=$(awk '$1=="archive"{print $3}' tools.lock)
   mkdir -p downloads
   curl -L -o downloads/$A "$(awk '$1=="url"{print $3}' tools.lock)"
   ```
   Якщо архів уже є в сусідньому проєкті, APFS-клон не потребує ні завантаження, ні місця: `cp -c <інший-проєкт>/downloads/$A downloads/`
2. Перевірте архів, розпакуйте його в `.tools/` і звірте версії програм — має закінчитися `check-tools: OK`:
   ```bash
   make check-tools
   ```
3. Перевірка: `make lint sim build` → лінт без попереджень, `TESTS=3 PASS=3`, останній рядок `Max frequency` — `PASS at 27.00 MHz`.

### Цілі make

`<демо>` = `DEMO`, `<top>` = `TOP` з його `demo.mk`. Просто `make` = `make build`.

| Ціль | Що робить | Результат | Плата |
| --- | --- | --- | --- |
| `check-tools` | звіряє хеш архіву й версії інструментів з `tools.lock`; розпаковує `.tools/`, якщо його немає; закінчується `check-tools: OK` | `.tools/oss-cad-suite/` | ні |
| `demos` | список дизайнів у `demo/` | — | ні |
| `lint` | Verilator `--lint-only -Wall` для `SOURCES` | — | ні |
| `sim` | тест cocotb `TEST` в Icarus через `Makefile.sim`; `SIM_PARAMS` діють лише тут | `build/<демо>/results.xml`, `sim_build/<top>.fst` | ні |
| `waves` | відкриває останню симуляцію в gtkwave (запускайте зі свого терміналу) | — | ні |
| `build` | Yosys `synth_gowin` → nextpnr-himbaechel (ціль 27 МГц, піни з `CST`) → `gowin_pack`; перезбирає лише змінене | `build/<демо>/<top>.json`, `<top>_pnr.json`, `<top>.fs`, `yosys.log`, `nextpnr.log` | ні |
| `detect` | `openFPGALoader --detect`; очікуваний idcode `0x100481b` | — | так |
| `flash-sram` | за потреби збирає, завантажує `<top>.fs` у SRAM (до вимкнення живлення) | — | так |
| `flash-perm` | за потреби збирає, стирає й записує вбудовану flash (стартує при ввімкненні) | — | так |
| `clean` / `clean-all` | видаляє `build/<демо>` / `build/` | — | ні |

| Змінна | Типово | Значення |
| --- | --- | --- |
| `DEMO` | `blinky` | тека дизайну в `demo/` (усі цілі, крім `demos`, `detect`, `clean-all`) |
| `OSS_CAD` | `.tools/oss-cad-suite` | розташування інструментів; `Makefile` ставить його `bin/` першим у `PATH` |

### Без make

Ті самі кроки з прямим викликом інструментів. Запускайте з кореня репозиторію; приклад — `btn_counter`, значення `TOP`, `SOURCES` (у тому ж порядку), `CST`, `TEST` і `SIM_PARAMS` беріть з `demo.mk` дизайну.

```bash
export PATH="$PWD/.tools/oss-cad-suite/bin:$PATH"   # лише для цього терміналу
D=demo/btn_counter; TOP=btn_counter; B=build/btn_counter
SRC="$D/button_conditioner.sv $D/btn_counter.sv"
mkdir -p $B
```

Лінт:
```bash
verilator --lint-only -Wall --top-module $TOP $SRC
```

Симуляція (Python-runner cocotb, Icarus; `parameters` = `SIM_PARAMS`):
```bash
D=$D TOP=$TOP B=$B SRC="$SRC" tabbypy3 - <<'EOF'
import os
from cocotb_tools.runner import get_runner
e = os.environ
b = os.path.abspath(e["B"])
r = get_runner("icarus")
r.build(sources=e["SRC"].split(), hdl_toplevel=e["TOP"], parameters={"DEBOUNCE_CYCLES": 8},
        build_dir=b + "/sim_build", waves=True)
r.test(hdl_toplevel=e["TOP"], test_module="test_" + e["TOP"], test_dir=e["D"],
       build_dir=b + "/sim_build", results_xml=b + "/results.xml", waves=True)
EOF
gtkwave $B/sim_build/$TOP.fst
```

Бітстрім (синтез → розміщення й трасування → пакування):
```bash
yosys -q -l $B/yosys.log -p "read_verilog -sv $SRC; synth_gowin -top $TOP -json $B/$TOP.json"
nextpnr-himbaechel --json $B/$TOP.json --write $B/${TOP}_pnr.json \
  --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C --vopt cst=$D/tangnano9k.cst \
  --freq 27 -l $B/nextpnr.log
gowin_pack -d GW1N-9C -o $B/$TOP.fs $B/${TOP}_pnr.json
```

Плата:
```bash
openFPGALoader --detect
openFPGALoader -b tangnano9k $B/$TOP.fs      # SRAM, до вимкнення живлення
openFPGALoader -b tangnano9k -f $B/$TOP.fs   # вбудована flash, стартує при ввімкненні
```

### Дизайни

| Дизайн | Поведінка | Тести |
| --- | --- | --- |
| `blinky` | двійковий лічильник на 6 LED; S1 скидає | 3 |
| `btn_counter` | 6-бітний лічильник: S2 = +1, S1 = −1, обидві = 0; з фільтром брязкоту й заворотом | 7 |

Новий дизайн: скопіюйте теку в `demo/`, змініть `demo.mk` (`TOP`, `SOURCES`, `CST`, `TEST`, `SIM_PARAMS`), піни беріть з `templates/tangnano9k.cst`, додайте назву в `.vscode/tasks.json`.

### Входи й виходи плати

| Сигнал | Пін | Примітки |
| --- | --- | --- |
| `clk` | 52 | 27 МГц, LVCMOS33 |
| `led[0..5]` | 10, 11, 13, 14, 15, 16 | активний 0, LVCMOS18; `led[0]` — з боку S1 |
| `btn_n[0]`, `btn_n[1]` | 3, 4 | на платі S2, S1; активний 0, підтяжка вгору, LVCMOS18 |
| `uart_tx`, `uart_rx` | 17, 18 | USB-UART через BL702, LVCMOS33 |

Джерела: Apicula `examples/tangnano9k.cst`, звірено з `sipeed/TangNano-9K-example`. Кожен порт верхнього модуля має бути в CST, інакше `ERROR: Unconstrained IO`.

### Флеш на платі

| | Вбудована (у GW1NR-9C) | Зовнішня SPI (PUYA P25Q32H, 4 MiB) |
| --- | --- | --- |
| Що зберігає | конфігурацію (бітстрім), що завантажується при ввімкненні | дані користувача для дизайну |
| `openFPGALoader -f` | пише її (спершу повне стирання; `--verify` не підтримується) | лише з `--external-flash` |
| `--detect -f` / `--dump-flash` | не підтримується (openFPGALoader 1.1.1 не читає її) | `--dump-flash` читає саме її; спершу стирає SRAM; ~330 B/s (повний дамп ≈ 3,5 год) |

Дампу жодної з flash не збережено. Еталон для відновлення вбудованої flash — образ Sipeed із `sipeed/TangNano-9K-example`.

### VS Code

Відкрийте теку репозиторію і встановіть рекомендовані розширення (Verilog-HDL, Python). Налаштування й задачі — у `.vscode/` (Terminal → Run Task…, ⇧⌘B — збірка). `verilog.linting.path` абсолютний — виправте, якщо перенесете репозиторій. Python — з OSS CAD Suite; окремий venv для cocotb не створюйте (додаткові пакети: `.tools/oss-cad-suite/bin/tabbypip install <пакет>`).

Самоперевірка: видаліть `;` у файлі `.sv` → у Problems з'явиться помилка Verilator; задачі «1. Simulate (cocotb)» і «3. Build bitstream» для `blinky` дають результати з кроку 3 **Налаштування**.

### Примітки

- `gowin_pack` попереджає про відсутні Numpy/Msgspec/fastcrc — це лише швидкість, можна ігнорувати.
- gtkwave та інші інструменти пишуть у `~/.config/yosyshq`; запускайте їх зі свого терміналу.
- Перевірено на залізі (2026-10-15): `make detect`, `make flash-sram` (обидва дизайни), `make flash-perm DEMO=btn_counter` (стартує після перепідключення живлення).
- Відновити образ Sipeed: `.tools/oss-cad-suite/bin/openFPGALoader -b tangnano9k -f backup/tangnano9k_flash_backup.fs`.

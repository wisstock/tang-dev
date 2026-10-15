# FPGA for beginners

[English](#english) · [Українська](#українська)

## English

An introduction for people new to FPGAs: what an FPGA is, what a design project consists of, what ends up in the "firmware" (bitstream) and which tools turn Verilog into it. Examples use this repository and the Sipeed Tang Nano 9K (Gowin GW1NR-9C). Commands are in `README.md`.

### 1. What an FPGA is

A microcontroller runs a program: one processor executes instructions one after another. An FPGA (Field-Programmable Gate Array) has no program in that sense. It is a chip full of small, unconnected logic blocks and a programmable wiring network. You describe a **digital circuit**, and the tools configure the blocks and wires so that the chip *becomes* that circuit. Everything in the circuit works in parallel, on every clock edge.

Main building blocks (numbers for the GW1NR-9C, from the nextpnr resource report):

| Block | What it does | GW1NR-9C |
| --- | --- | --- |
| LUT4 (look-up table) | any logic function of 4 inputs, stored as a 16-bit truth table | 8 640 |
| Flip-flop (DFF) | stores 1 bit, updates on a clock edge; registers, counters, state machines | 6 480 |
| ALU / carry chain | fast adders and counters | (inside the logic slices) |
| Block RAM (BSRAM) | on-chip memory blocks | 26 blocks |
| Multipliers (DSP) | hard multipliers, e.g. 18×18 | 20 |
| PLL | makes new clock frequencies from the input clock | 2 |
| I/O blocks | connect internal signals to pins; set voltage standard (LVCMOS33, LVCMOS18…) and pull-ups | 276 sites (fewer bonded on the QN88 package) |
| Routing | programmable wires and switches between all of the above | — |

GW1NR-9C extras: the "R" means 64 Mbit PSRAM is stacked inside the package; there is also on-chip flash that stores the configuration (see section 3).

**Volatile configuration.** The configuration lives in SRAM cells inside the FPGA. It is lost when power is removed. That is why the board also has non-volatile flash: at power-on the FPGA copies its configuration from flash into SRAM and starts.

### 2. What a design project consists of

| File type | Purpose | In this repository |
| --- | --- | --- |
| HDL sources | the circuit, in Verilog / SystemVerilog (`.v`, `.sv`) or VHDL; one **top module** whose ports are the chip pins | `demo/<name>/*.sv` |
| Physical constraints | which pin each top-level port uses, I/O voltage, pull-up/down, drive strength. Gowin format: `.cst` | `demo/<name>/tangnano9k.cst`, template `templates/tangnano9k.cst` |
| Timing constraints | clock frequencies the design must meet (Gowin IDE uses `.sdc`; here `nextpnr --freq 27`) | `FREQ` in `Makefile` |
| Testbenches | simulate the design on a computer before hardware: drive inputs, check outputs | `demo/<name>/test_*.py` (cocotb, Python) |
| IP / memory init files | vendor blocks (PLL, RAM) and memory contents (`.hex`, `.mem`) | not used yet |
| Build scripts | the sequence of tool calls and their options | `Makefile`, `demo/<name>/demo.mk` |
| Build output | netlists, logs, bitstream — generated, not edited, not in git | `build/<name>/` |

Hardware design is different from software in a few ways that matter from day one:
- Every top-level port must be assigned to a real pin, otherwise place & route fails.
- Pin voltages are fixed by the board. On the Tang Nano 9K the LEDs and buttons sit in a 1.8 V bank (LVCMOS18), the clock and UART in 3.3 V banks (LVCMOS33).
- Board signals are often **active low**: on this board an LED is lit when its pin is 0, and a pressed button reads 0.
- Mechanical buttons bounce; a design must filter (debounce) them (see `button_conditioner.sv`).
- Simulation and hardware can differ (initial values, timing, unconstrained pins). Always test both.

### 3. What is inside the "firmware" (bitstream)

The file written to the board is a **bitstream** (Gowin: `.fs`). It is not code and is never "executed". It is a long list of configuration bits that set:

- the truth table of every used LUT;
- the mode of every used flip-flop (clock, enable, reset) and its power-on value;
- every routing switch that connects blocks into your circuit;
- the settings of every used I/O pin (direction, voltage standard, pull mode);
- the configuration and initial contents of block RAM, PLL settings, other hard blocks;
- a header and trailer: device ID, options (security bit, CRC check, loading rate), checksum/CRC so the chip can reject a corrupted file.

The Gowin `.fs` file is plain text: comment lines with the header (`//Part Number: GW1NR-LV9QN88PC6/I5`, `//CheckSum: …`) followed by lines of `0` and `1`. For `btn_counter` it is 728 lines and about 2 MB, although the design uses only ~1 % of the chip: the bitstream always describes the **whole** chip.

Two ways to load it:

| | SRAM | On-chip flash |
| --- | --- | --- |
| Command | `make flash-sram` | `make flash-perm` |
| Speed | a few seconds | longer (erase + write) |
| After power-off | lost; the board starts from flash again | kept; loaded into SRAM at every power-on |
| Use for | everyday testing | the final design |

The board also has a separate external SPI flash (4 MiB). It is not used for configuration; a design may read data from it.

### 4. From Verilog to the board: the toolchain

```
 .sv sources ──► lint ──► simulation            (check on the computer)
      │
      ▼
 synthesis ──► place & route ──► bitstream ──► programmer ──► board
 (Yosys)       (nextpnr)         (gowin_pack)  (openFPGALoader)
                   ▲
             .cst pins, clock frequency
```

| Stage | Tool here | Input → output | What happens |
| --- | --- | --- | --- |
| Lint | Verilator | `.sv` → messages | static check for errors and suspicious code (width mismatches, unused signals) without running anything |
| Simulation | Icarus Verilog + cocotb | `.sv` + `test_*.py` → pass/fail, `.fst` waveforms | runs the design cycle by cycle on the computer; tests drive inputs and check outputs |
| Waveform viewer | GTKWave | `.fst` → graphs | shows every signal over time, for debugging |
| Synthesis | Yosys (`synth_gowin`) | `.sv` → `<top>.json` netlist | reads the HDL, optimises the logic, maps it onto the chip's primitives (LUT4, DFF, ALU, BSRAM…) |
| Place & route (PnR) | nextpnr-himbaechel (Gowin) | netlist + `.cst` → `<top>_pnr.json` | chooses a physical location for each primitive and connects them through the routing network; checks timing (e.g. `Max frequency … PASS at 27.00 MHz`) |
| Bitstream generation | gowin_pack (Apicula project) | `<top>_pnr.json` → `<top>.fs` | converts the placed and routed design into configuration bits |
| Programming | openFPGALoader | `<top>.fs` → board | talks JTAG through the board's USB chip (BL702), loads SRAM or writes flash |

The chip database used by nextpnr and gowin_pack comes from **Apicula**, an open-source project that reverse-engineered the Gowin bitstream format. The vendor alternative is the closed Gowin EDA (IDE), which does the same stages with its own tools.

Useful outputs to read: `build/<name>/yosys.log` (what was synthesised), `build/<name>/nextpnr.log` ("Device utilisation" table, maximum frequency), `build/<name>/results.xml` (test results).

### 5. Typical FPGA project structure, on the Tang Nano 9K

A minimal stand-alone project for one design usually looks like this:

```
my_design/
├── rtl/            HDL sources: top module + submodules
├── constraints/    pins (.cst) and timing (.sdc)
├── sim/            testbenches, test data
├── ip/             vendor IP and memory init files (optional)
├── Makefile        build steps
└── build/          generated output (not in git)
```

This repository holds several designs and shares the tools and build steps between them, so the same parts are arranged per design:

```
tang_dev/
├── Makefile                  build steps for any design: make <target> DEMO=<name>
├── Makefile.sim              simulation steps (cocotb)
├── templates/tangnano9k.cst  every pin of the board, to copy from
├── demo/
│   ├── blinky/               rtl + constraints + sim of one design, together
│   └── btn_counter/
│       ├── btn_counter.sv          top module: ports clk, btn_n[1:0], led[5:0]
│       ├── button_conditioner.sv   submodule: debounce + one pulse per press
│       ├── tangnano9k.cst          pins of the ports above
│       ├── test_btn_counter.py     cocotb tests
│       └── demo.mk                 TOP, SOURCES, CST, TEST, SIM_PARAMS
├── build/btn_counter/        btn_counter.json, btn_counter_pnr.json, btn_counter.fs, logs
└── .tools/oss-cad-suite/     the whole toolchain
```

How the pieces of `btn_counter` fit together:

1. **Top module ports = pins.** `btn_counter.sv` declares `clk`, `btn_n[1:0]`, `led[5:0]`. Nothing else leaves the chip.
2. **The `.cst` file connects each port to a pin of the board:**
   ```
   IO_LOC  "clk" 52;                                   // 27 MHz oscillator
   IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=UP;
   IO_LOC  "btn_n[0]" 3;                               // button S2
   IO_PORT "btn_n[0]" IO_TYPE=LVCMOS18 PULL_MODE=UP;
   IO_LOC  "led[0]" 10;                                // LED next to S1
   IO_PORT "led[0]" IO_TYPE=LVCMOS18 PULL_MODE=NONE;
   ```
3. **Parameters** let one source serve both worlds: on hardware the debounce time is `DEBOUNCE_CYCLES = 270_000` (10 ms at 27 MHz); in simulation `SIM_PARAMS := DEBOUNCE_CYCLES=8` keeps tests short.
4. **Synthesis result** (from `btn_counter.json`): 54 ALU, 56 flip-flops, ~50 LUTs, 9 I/O buffers — about 1 % of the chip.
5. **Bitstream:** `build/btn_counter/btn_counter.fs`, loaded with `make flash-sram DEMO=btn_counter` or written with `make flash-perm DEMO=btn_counter`.

To start a new design: copy `demo/blinky` to `demo/<name>`, rename the module and file, keep only the pins you use from `templates/tangnano9k.cst`, and edit `demo.mk`.

## Українська

Вступ для тих, хто вперше працює з FPGA (ПЛІС): що таке FPGA, з чого складається проєкт дизайну, що потрапляє в «прошивку» (бітстрім) і які інструменти перетворюють на неї Verilog. Приклади взято з цього репозиторію та плати Sipeed Tang Nano 9K (Gowin GW1NR-9C). Команди — у `README.md`.

### 1. Що таке FPGA

Мікроконтролер виконує програму: один процесор послідовно виконує інструкції. У FPGA (Field-Programmable Gate Array, програмована логічна інтегральна схема) програми в такому сенсі немає. Це мікросхема з великою кількістю дрібних, не з'єднаних між собою логічних блоків і програмованою мережею з'єднань. Ви описуєте **цифрову схему**, а інструменти налаштовують блоки й з'єднання так, що мікросхема *стає* цією схемою. Усі частини схеми працюють паралельно, на кожному фронті тактового сигналу.

Основні будівельні блоки (кількість для GW1NR-9C, зі звіту nextpnr про ресурси):

| Блок | Що робить | GW1NR-9C |
| --- | --- | --- |
| LUT4 (таблиця відповідності) | будь-яка логічна функція 4 входів, збережена як таблиця істинності з 16 біт | 8 640 |
| Тригер (DFF) | зберігає 1 біт, оновлюється на фронті такту; регістри, лічильники, автомати станів | 6 480 |
| ALU / ланцюг перенесення | швидкі суматори й лічильники | (у логічних комірках) |
| Блокова пам'ять (BSRAM) | вбудовані блоки пам'яті | 26 блоків |
| Помножувачі (DSP) | апаратні помножувачі, напр. 18×18 | 20 |
| PLL | отримує нові частоти з вхідного тактового сигналу | 2 |
| Блоки вводу-виводу | з'єднують внутрішні сигнали з пінами; задають стандарт напруги (LVCMOS33, LVCMOS18…) і підтяжку | 276 місць (у корпусі QN88 виведено менше) |
| Трасування | програмовані провідники й перемикачі між усім вищезгаданим | — |

Особливості GW1NR-9C: «R» означає, що в корпус вбудовано 64 Мбіт PSRAM; також є вбудована flash, у якій зберігається конфігурація (див. розділ 3).

**Енергозалежна конфігурація.** Конфігурація зберігається в комірках SRAM усередині FPGA і зникає після вимкнення живлення. Тому на платі є енергонезалежна flash: при ввімкненні FPGA копіює конфігурацію з flash у SRAM і стартує.

### 2. З чого складається проєкт дизайну

| Тип файлу | Призначення | У цьому репозиторії |
| --- | --- | --- |
| Джерела HDL | схема мовою Verilog / SystemVerilog (`.v`, `.sv`) або VHDL; один **верхній модуль** (top), порти якого — піни мікросхеми | `demo/<назва>/*.sv` |
| Фізичні обмеження | який пін використовує кожен порт верхнього модуля, напруга вводу-виводу, підтяжка, струм. Формат Gowin: `.cst` | `demo/<назва>/tangnano9k.cst`, шаблон `templates/tangnano9k.cst` |
| Часові обмеження | частоти, на яких дизайн має працювати (Gowin IDE використовує `.sdc`; тут `nextpnr --freq 27`) | `FREQ` у `Makefile` |
| Тестові стенди | симуляція дизайну на комп'ютері до заліза: подають входи, перевіряють виходи | `demo/<назва>/test_*.py` (cocotb, Python) |
| IP-ядра / файли ініціалізації пам'яті | блоки виробника (PLL, RAM) і вміст пам'яті (`.hex`, `.mem`) | поки не використовуються |
| Скрипти збірки | послідовність викликів інструментів і їхні параметри | `Makefile`, `demo/<назва>/demo.mk` |
| Результати збірки | нетлісти, журнали, бітстрім — генеруються, не редагуються, не в git | `build/<назва>/` |

Розробка апаратури відрізняється від програмування в кількох важливих із першого дня речах:
- Кожен порт верхнього модуля має бути прив'язаний до реального піна, інакше розміщення й трасування завершиться помилкою.
- Напруги пінів задає плата. На Tang Nano 9K світлодіоди й кнопки в банку 1,8 В (LVCMOS18), тактовий сигнал і UART — у банках 3,3 В (LVCMOS33).
- Сигнали плати часто **активні низьким рівнем**: тут світлодіод світиться, коли на піні 0, а натиснута кнопка дає 0.
- Механічні кнопки брязкотять; дизайн має це фільтрувати (див. `button_conditioner.sv`).
- Симуляція й залізо можуть відрізнятися (початкові значення, часові затримки, неприв'язані піни). Перевіряйте і там, і там.

### 3. Що всередині «прошивки» (бітстріму)

Файл, який записують на плату, — **бітстрім** (у Gowin: `.fs`). Це не код, і він ніколи не «виконується». Це довгий список конфігураційних бітів, що задають:

- таблицю істинності кожного використаного LUT;
- режим кожного використаного тригера (такт, дозвіл, скидання) і його значення після ввімкнення;
- кожен перемикач трасування, що з'єднує блоки у вашу схему;
- налаштування кожного використаного піна (напрям, стандарт напруги, підтяжка);
- конфігурацію й початковий вміст блокової пам'яті, налаштування PLL та інших апаратних блоків;
- заголовок і завершення: ідентифікатор мікросхеми, параметри (біт захисту, перевірка CRC, швидкість завантаження), контрольну суму/CRC, щоб мікросхема відкинула пошкоджений файл.

Файл `.fs` від Gowin — звичайний текст: рядки-коментарі із заголовком (`//Part Number: GW1NR-LV9QN88PC6/I5`, `//CheckSum: …`), а далі рядки з `0` і `1`. Для `btn_counter` це 728 рядків і близько 2 МБ, хоча дизайн займає лише ~1 % мікросхеми: бітстрім завжди описує **всю** мікросхему.

Два способи завантаження:

| | SRAM | Вбудована flash |
| --- | --- | --- |
| Команда | `make flash-sram` | `make flash-perm` |
| Швидкість | кілька секунд | довше (стирання + запис) |
| Після вимкнення живлення | зникає; плата знову стартує з flash | зберігається; завантажується в SRAM при кожному ввімкненні |
| Для чого | щоденні перевірки | остаточний дизайн |

На платі є ще окрема зовнішня SPI flash (4 MiB). Для конфігурації вона не використовується; дизайн може читати з неї дані.

### 4. Від Verilog до плати: ланцюжок інструментів

```
 джерела .sv ──► лінт ──► симуляція             (перевірка на комп'ютері)
      │
      ▼
 синтез ──► розміщення й трасування ──► бітстрім ──► програматор ──► плата
 (Yosys)    (nextpnr)                   (gowin_pack) (openFPGALoader)
                   ▲
             піни .cst, тактова частота
```

| Етап | Інструмент тут | Вхід → вихід | Що відбувається |
| --- | --- | --- | --- |
| Лінт | Verilator | `.sv` → повідомлення | статична перевірка помилок і підозрілого коду (різна розрядність, невикористані сигнали) без запуску |
| Симуляція | Icarus Verilog + cocotb | `.sv` + `test_*.py` → успіх/провал, осцилограми `.fst` | виконує дизайн такт за тактом на комп'ютері; тести подають входи й перевіряють виходи |
| Перегляд осцилограм | GTKWave | `.fst` → графіки | показує кожен сигнал у часі, для налагодження |
| Синтез | Yosys (`synth_gowin`) | `.sv` → нетліст `<top>.json` | читає HDL, оптимізує логіку, відображає її на примітиви мікросхеми (LUT4, DFF, ALU, BSRAM…) |
| Розміщення й трасування (PnR) | nextpnr-himbaechel (Gowin) | нетліст + `.cst` → `<top>_pnr.json` | вибирає фізичне місце для кожного примітива й з'єднує їх через мережу трасування; перевіряє часові характеристики (напр. `Max frequency … PASS at 27.00 MHz`) |
| Генерація бітстріму | gowin_pack (проєкт Apicula) | `<top>_pnr.json` → `<top>.fs` | перетворює розміщений і протрасований дизайн на конфігураційні біти |
| Програмування | openFPGALoader | `<top>.fs` → плата | працює через JTAG і USB-мікросхему плати (BL702), завантажує SRAM або пише flash |

Базу даних мікросхеми для nextpnr і gowin_pack дає **Apicula** — відкритий проєкт, що відтворив формат бітстріму Gowin зворотною розробкою. Альтернатива від виробника — закрита Gowin EDA (IDE), яка виконує ті самі етапи власними інструментами.

Корисні для читання результати: `build/<назва>/yosys.log` (що синтезовано), `build/<назва>/nextpnr.log` (таблиця «Device utilisation», максимальна частота), `build/<назва>/results.xml` (результати тестів).

### 5. Типова структура проєкту FPGA на прикладі Tang Nano 9K

Мінімальний окремий проєкт для одного дизайну зазвичай виглядає так:

```
my_design/
├── rtl/            джерела HDL: верхній модуль + підмодулі
├── constraints/    піни (.cst) і часові обмеження (.sdc)
├── sim/            тестові стенди, тестові дані
├── ip/             IP-ядра виробника й файли ініціалізації пам'яті (необов'язково)
├── Makefile        кроки збірки
└── build/          згенеровані результати (не в git)
```

Цей репозиторій містить кілька дизайнів і ділить між ними інструменти й кроки збірки, тому ті самі частини розкладено по дизайнах:

```
tang_dev/
├── Makefile                  кроки збірки для будь-якого дизайну: make <ціль> DEMO=<назва>
├── Makefile.sim              кроки симуляції (cocotb)
├── templates/tangnano9k.cst  усі піни плати, звідси копіюють
├── demo/
│   ├── blinky/               rtl + обмеження + симуляція одного дизайну разом
│   └── btn_counter/
│       ├── btn_counter.sv          верхній модуль: порти clk, btn_n[1:0], led[5:0]
│       ├── button_conditioner.sv   підмодуль: фільтр брязкоту + один імпульс на натискання
│       ├── tangnano9k.cst          піни для портів вище
│       ├── test_btn_counter.py     тести cocotb
│       └── demo.mk                 TOP, SOURCES, CST, TEST, SIM_PARAMS
├── build/btn_counter/        btn_counter.json, btn_counter_pnr.json, btn_counter.fs, журнали
└── .tools/oss-cad-suite/     увесь набір інструментів
```

Як складаються частини `btn_counter`:

1. **Порти верхнього модуля = піни.** `btn_counter.sv` оголошує `clk`, `btn_n[1:0]`, `led[5:0]`. Більше нічого не виходить за межі мікросхеми.
2. **Файл `.cst` прив'язує кожен порт до піна плати:**
   ```
   IO_LOC  "clk" 52;                                   // генератор 27 МГц
   IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=UP;
   IO_LOC  "btn_n[0]" 3;                               // кнопка S2
   IO_PORT "btn_n[0]" IO_TYPE=LVCMOS18 PULL_MODE=UP;
   IO_LOC  "led[0]" 10;                                // світлодіод біля S1
   IO_PORT "led[0]" IO_TYPE=LVCMOS18 PULL_MODE=NONE;
   ```
3. **Параметри** дозволяють одному джерелу працювати в обох світах: на залізі час фільтра брязкоту `DEBOUNCE_CYCLES = 270_000` (10 мс при 27 МГц), а в симуляції `SIM_PARAMS := DEBOUNCE_CYCLES=8` робить тести короткими.
4. **Результат синтезу** (з `btn_counter.json`): 54 ALU, 56 тригерів, ~50 LUT, 9 буферів вводу-виводу — близько 1 % мікросхеми.
5. **Бітстрім:** `build/btn_counter/btn_counter.fs`, завантажується `make flash-sram DEMO=btn_counter` або записується `make flash-perm DEMO=btn_counter`.

Щоб почати новий дизайн: скопіюйте `demo/blinky` у `demo/<назва>`, перейменуйте модуль і файл, залиште з `templates/tangnano9k.cst` лише потрібні піни й змініть `demo.mk`.

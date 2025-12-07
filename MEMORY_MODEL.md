# Модель управления памятью Loki

## Философия

**Размещение объекта - это не свойство типа, а свойство его создания.**

В Loki нет различия между "указателем" и "значением" на уровне системы типов. Все объекты имеют одинаковый тип (`Person`), но могут быть размещены в разных местах (stack, heap) в зависимости от контекста.

## Ключевые принципы

### 1. Единая система типов

```loki
Person :: struct {
    name: string,
    age: int,
}

// НЕТ различия между Person и ^Person
// Тип ВСЕГДА один - Person
process :: pc (p: Person) -> void { ... }
```

### 2. Контракт процедуры определяет дефолт

```loki
// БЕЗ контракта -> stack по умолчанию
no_contract :: pc () -> void {
    p: Person              // stack
    x := 42                // stack
    arr := [100]int{...}   // stack
}

// С контрактом -> аллокатор из контекста
with_contract :: pc () -> void in @heap {
    p: Person              // heap (из переданного аллокатора)
    x := 42                // heap
    arr := [100]int{...}   // heap
}

with_size_contract :: pc () -> void in @heap(10 * size.MB)
```

### 3. Явное переопределение через `in`

```loki
no_contract :: pc () -> void {
    p := Person{...}              // stack (дефолт)
    p2 := Person{...} in #malloc  // malloc (переопределение)
}

with_contract :: pc () -> void in @heap {
    p := Person{...}              // heap (дефолт)
    p2 := Person{...} in #stack   // stack (переопределение)
}
```

## Синтаксис создания объектов

### Способ 1: Декларация с типом

```loki
// Создает объект с дефолтными значениями полей
p: Person              // эквивалентно new(Person)
x: int                 // эквивалентно 0
arr: [10]int           // эквивалентно [10]int{0, 0, ...}
```

### Способ 2: Литерал с инициализацией

```loki
// Создает и инициализирует объект
p := Person{name="Alice", age=28}
arr := [10]int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
```

### Способ 3: С явным размещением

```loki
// Любой объект можно разместить где угодно
p := Person{...} in $malloc
x := 42 in $arena(1*MB)
arr := [1000]int{...} in #jemalloc
```

## Контракты процедур

### Контракт `in @heap`

Процедура объявляет, что ей нужен аллокатор для работы:

```loki
process :: pc () -> []int in @heap {
    // Все создания идут из аллокатора в контексте
    data := make([]int, 1000)     // из context.allocator
    temp := [100]int{...}         // из context.allocator
    
    <- data
}
```

### Контракт `in @heap(size)`

Процедура указывает максимальный размер нужной памяти:

```loki
process :: pc () -> void in @heap(10*size.MB) {
    // Компилятор знает, что нужно не больше 10MB
    data := make([]int, 1000)
}

main :: pc () -> void {
    // Передаем аллокатор нужного размера
    process() in #arena(10*MB)
}
```

### Без контракта

Процедура работает только со stack:

```loki
simple :: pc (x: int) -> int {
    // Все на стеке
    temp := [100]int{...}
    <- x * 2
}
```

## Типы аллокаторов

### `$malloc` - системный аллокатор

```loki
p := Person{...} in #malloc

// С явным размером (для проверки)
p := Person{...} in #malloc(1*KB)
```

**Характеристики:**
- Использует системный malloc/free
- Низкий overhead на выделение
- Может быть медленным для множества маленьких аллокаций
- Thread-safe (опционально)

### `$arena` - arena аллокатор

```loki
process :: pc () -> void in @heap {
    data := make([]int, 1000)
}

main :: pc () -> void {
    process() in #arena(10*MB)
} // все освобождается одной операцией
```

**Характеристики:**
- Очень быстрое выделение (bump allocator)
- Освобождение всей арены за O(1)
- Идеально для временных данных
- Не thread-safe (по умолчанию)

### `$jemalloc` - jemalloc аллокатор

```loki
p := Person{...} in #jemalloc
```

**Характеристики:**
- Оптимизирован для многопоточности
- Минимальная фрагментация
- Хорошая производительность для любых размеров
- Thread-safe

### `$stack` - явное размещение на стеке

```loki
with_contract :: pc () -> void in @heap {
    p := Person{...}              // heap (дефолт)
    temp := Person{...} in #stack // stack (переопределение)
}
```

**Характеристики:**
- Самое быстрое выделение (0 overhead)
- Автоматическая очистка
- Ограничен размером стека
- Только для локальных переменных

## Оператор `^` - передача владения

Символ `^` используется **ТОЛЬКО** для передачи владения аллокатором в вызовах функций.

### Без передачи владения (дефолт)

```loki
process :: pc () -> void in @heap {
    data := make([]int, 1000)
    // аллокатор отслеживает выделение
}

main :: pc () -> void {
    process() in #arena(10*MB)
    // arena ВСЕ ЕЩЕ существует
    // используем другие данные из этой же арены
} // arena освобождается ЗДЕСЬ
```

### С передачей владения (`^`)

```loki
process :: pc () -> void in @heap {
    data := make([]int, 1000)
}

main :: pc () -> void {
    process() in #arena(10*MB)^
    //                       ^ передача владения
    // arena УЖЕ освобождена в конце process()
}
```

### Проверка lifetime escape

Компилятор проверяет, что данные не покидают scope аллокатора при передаче владения:

```loki
create :: pc () -> []int in @heap {
    data := make([]int, 1000)
    <- data
}

main :: pc () -> void {
    // ❌ COMPILE ERROR: нельзя возвращать из temporary allocator
    result := create() in $arena(10*MB)^
    //                                 ^ ERROR: lifetime escape!
    
    // ✅ OK: без ^ данные живут в caller scope
    result := create() in $arena(10*MB)
    use(result)
} // arena освобождается здесь
```

## Отслеживание аллокатором

Каждый аллокатор отслеживает все выделенные через него объекты:

```loki
process :: pc () -> []int in @heap {
    data := make([]int, 1000)     // [1] tracked
    temp := make([]int, 100)      // [2] tracked
    buffer := [50]int{...}        // [3] tracked
    
    <- data  // возвращаем [1]
    // Компилятор генерирует код для освобождения [2] и [3]
}

main :: pc () -> void {
    // Вариант 1: без ^
    result := process() in $arena(10*MB)
    // Освобождено в process(): [2], [3]
    // Живет в arena: [1]
    use(result)
} // Освобождается: [1]

main2 :: pc () -> void {
    // Вариант 2: с ^
    process() in $arena(10*MB)^
    // Освобождено все: [1], [2], [3]
}
```

## Примеры использования

### Пример 1: Простая функция (без контракта)

```loki
sum :: pc (arr: []int) -> int {
    total := 0
    for x in arr {
        total += x
    }
    <- total
}

main :: pc () -> void {
    // Все на стеке
    numbers := [10]int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
    result := sum(numbers[:])
    log.info("Sum: %d", result)
}
```

### Пример 2: Временная обработка (arena + ^)

```loki
process_temp :: pc (data: []int) -> int in @heap {
    // Создаем временные структуры
    temp1 := make([]int, len(data))
    temp2 := make([]int, len(data))
    
    // обработка...
    result := 0
    for x in data {
        result += x
    }
    
    <- result
    // temp1 и temp2 будут освобождены
}

main :: pc () -> void {
    data := [1000]int{...}
    
    // Arena освобождается в конце process_temp()
    result := process_temp(data[:]) in #arena(100*KB)^
    //                                                ^ временный аллокатор
    
    log.info("Result: %d", result)
}
```

### Пример 3: Долгоживущие данные (arena без ^)

```loki
load_config :: pc () -> Config in @heap {
    cfg := Config{...}
    cfg.settings = make([]Setting, 100)
    
    // загрузка конфигурации...
    
    <- cfg
}

main :: pc () -> void {
    // Config живет до конца main
    config := load_config() in #arena(1*MB)
    
    // Используем config во всей программе
    server.run(config)
    
} // arena освобождается здесь
```

### Пример 4: Смешанное размещение

```loki
complex_work :: pc () -> Result in @heap {
    // Из контекста (heap)
    main_data := make([]int, 10000)
    
    // Явно на стеке (для маленьких временных данных)
    temp := [100]byte{...} in #stack
    
    // Явно в другом аллокаторе
    big_temp := make([]int, 50000) in #jemalloc
    
    // обработка...
    
    result := Result{data = main_data}
    <- result
    // temp на стеке очищается автоматически
    // big_temp в jemalloc нужно освободить отдельно (TODO: как?)
}

main :: pc () -> void {
    result := complex_work() in #arena(100*MB)
    use(result)
} // arena освобождается
```

### Пример 5: Мутабельные методы

```loki
PersonI => {
    init :: #mut pc (name: string, age: int) -> void,
    birthday :: #mut pc () -> void,
    print :: pc () -> void,
}

p: Person => PersonI => {
    init :: #mut pc (name: string, age: int) -> void {
        p.name = name    // ✅ можно менять: #mut процедура
        p.age = age
    },
    
    birthday :: #mut pc () -> void {
        p.age += 1       // ✅ можно менять: #mut процедура
    },
    
    print :: pc () -> void {
        // p.age = 0     // ❌ COMPILE ERROR: не #mut процедура
        log.info("%s is %d years old", p.name, p.age)
    }
}
```

## Преимущества модели

### 1. Упрощение системы типов

**Традиционный подход:**
```c
Person person;           // значение
Person* person_ptr;      // указатель
void process(Person* p); // указатель в сигнатуре
```

**Loki:**
```loki
Person // всегда один тип
process :: pc (p: Person) -> void // тип одинаковый
```

### 2. Явный контроль размещения

```loki
// Видно сразу где выделяется память
p := Person{...}              // stack (дефолт)
p2 := Person{...} in #malloc  // malloc (явно)
```

### 3. Автоматическое отслеживание

Аллокатор знает все свои объекты и может:
- Освободить все за O(1) (arena)
- Обнаружить утечки (debug mode)
- Собрать статистику использования

### 4. Безопасность lifetime

Компилятор проверяет:
- Не возвращаются ли данные из temporary allocator (с `^`)
- Не используются ли данные после освобождения
- Корректность передачи владения

### 5. Гибкость

Можно легко поменять стратегию размещения:
```loki
// Было: stack
p := Person{...}

// Стало: heap
p := Person{...} in #malloc

// Тип процедуры не меняется!
```

## Статический анализ

Компилятор выполняет следующие проверки:

### 1. Lifetime escape detection

```loki
create :: pc () -> Person in @heap {
    p := Person{...}
    <- p
}

// ❌ ERROR
bad :: pc () -> Person {
    p := create() in #arena(1*KB)^  // temporary allocator
    <- p  // ERROR: p escapes temporary allocator
}

// ✅ OK
good :: pc () -> Person {
    p := create() in #arena(1*KB)   // persistent allocator
    <- p  // OK: p lives until caller frees arena
}
```

### 2. Size contract verification

```loki
// Объявляем максимальный размер
process :: pc () -> void in @heap(10*MB) {
    // ❌ COMPILE WARNING: может превысить лимит
    data := make([]int, 3_000_000)  // ~12MB
}
```

### 3. Use after free detection

```loki
bad :: pc () -> void {
    p := create() in #arena(1*KB)^
    //                            ^ arena освобождена
    use(p)  // ❌ ERROR: use after free
}
```

## Runtime проверки (опционально)

В debug mode можно включить runtime проверки:

```loki
#config {
    memory_tracking = true,
    bounds_checking = true,
}

main :: pc () -> void {
    p := Person{...} in #arena(1*KB)
    
    // Runtime отслеживает все аллокации
    // При освобождении проверяет утечки
}
```

## Сравнение с другими языками

### vs C/C++

**C/C++:**
```c
Person* p = malloc(sizeof(Person));  // ручное управление
// ...
free(p);  // легко забыть или сделать дважды
```

**Loki:**
```loki
p := Person{...} in #arena(1*KB)
// автоматическое освобождение
```

### vs Rust

**Rust:**
```rust
struct Person { ... }
// Borrow checker, lifetimes, &, &mut
fn process<'a>(p: &'a Person) -> &'a str { ... }
```

**Loki:**
```loki
Person :: struct { ... }
// Проще: аллокаторы отслеживают lifetime
process :: pc (p: Person) -> string { ... }
```

### vs Go

**Go:**
```go
type Person struct { ... }
p := &Person{...}  // escape analysis -> heap
// GC управляет памятью
```

**Loki:**
```loki
Person :: struct { ... }
p := Person{...} in #malloc  // явное размещение
// без GC, детерминированное освобождение
```

### vs Odin

**Odin:**
```odin
Person :: struct { ... }
p: ^Person  // указатель
p = new(Person)  // аллокатор из контекста
```

**Loki:**
```loki
Person :: struct { ... }
p: Person  // не указатель, но может быть на heap!
// размещение определяется контрактом и `in`
```

## Заключение

Модель памяти Loki предоставляет:
- ✅ **Простоту** - нет различия pointer/value в типах
- ✅ **Контроль** - явное указание где размещать
- ✅ **Безопасность** - статические проверки lifetime
- ✅ **Производительность** - нет GC, детерминированное управление
- ✅ **Гибкость** - легко менять стратегию размещения

**Ключевая идея:** Размещение - это не часть типа, это часть создания объекта!

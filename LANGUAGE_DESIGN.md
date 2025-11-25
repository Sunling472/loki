# Loki Language Design

## Философия

Loki - системный язык программирования, сочетающий:
- **Явный контроль** над памятью и ресурсами
- **Безопасность** через статический анализ и runtime проверки
- **Простоту** без жертвы производительностью
- **Прагматизм** - "pay for what you use"

Целевая аудитория: системное программирование, высокопроизводительные приложения, embedded системы.

---

## Основные концепции

### 1. Процедуры (Procedures)

В Loki есть только один тип исполняемого кода - **процедуры** (`pc`).

#### Синтаксис
```loki
// Простая процедура
add :: pc (a: int, b: int) -> int {
  return a + b
}

// Процедура без возвращаемого значения
print_hello :: pc () -> void {
  // implementation
}

// Процедура с контрактом на память
process :: pc () -> void in @allocator(10*MB) {
  data := make([]int, 1000)
}
```

#### Особенности
- Все процедуры имеют доступ к **неявному контексту** (#ctx)
- Контекст содержит конструкторы аллокаторов, логгер и другие runtime параметры
- Процедуры могут объявлять **контракт на память** через `in @allocator`

---

## Управление памятью

### Философия управления памятью

Loki предоставляет **явный контроль над аллокацией** без ручного управления временем жизни.

#### Три уровня аллокации:

1. **Stack (по умолчанию)** - автоматическое управление
2. **Heap с контрактом** - управляемая аллокация
3. **Явное управление** - для специальных случаев

### Stack аллокация (по умолчанию)

Без аннотации `in @allocator` все локальные переменные размещаются на стеке:

```loki
compute :: pc (n: int) -> int {
  buffer: [1024]byte  // на стеке
  result := 0
  
  for i in 0..<n {
    result += buffer[i]
  }
  
  return result
}  // buffer автоматически освобождается
```

**Преимущества:**
- Zero overhead
- Автоматическая очистка
- Предсказуемое время жизни
- Отсутствие фрагментации

**Ограничения:**
- Фиксированный размер на этапе компиляции
- Ограниченный размер стека

---

### Heap аллокация с контрактом

Для динамической аллокации используется аннотация `in @allocator`:

```loki
// Объявляем контракт: процедуре нужно до 10MB
process :: pc () -> void in @allocator(10*MB) {
  data := make([]int, 1000)      // heap аллокация
  more := make([]byte, 1024)     // еще одна аллокация
  
  // все аллокации используют context.allocator
}

// можно не указывать размер, тогда любой размер подойдёт
process2 :: pc () -> void in @allocator {}
```

#### Контракт на память

Контракт `in @allocator(size)` означает:
1. Процедура **может** аллоцировать до `size` байт
2. Caller **должен** предоставить аллокатор
3. Компилятор **может** проверить статически (для константных размеров)
4. Runtime **может** проверить динамически (в DEBUG режиме)
5. Allocator **может** быть именным

```loki
main :: pc () -> void {
  // Предоставляем malloc аллокатор с бюджетом 10MB
  process() in #malloc(10*MB) // анонимная аллокация

  // Создание именного аллокатора
  // правила те же, что и для анонимных
  $tmp :: #arena(10Mb, static=true)
  process() in $tmp^ // уничтожится в конце process()
}
```

---

### Типы аллокаторов

Loki предоставляет несколько встроенных стратегий аллокации:

#### 1. `#malloc` - Общий аллокатор

```loki
process() in #malloc(10*MB)
```

- Использует системный malloc/free
- Универсальный, но может фрагментироваться
- Подходит для долгоживущих данных

#### 2. `#arena` - Arena аллокатор

```loki
process() in #arena(10*MB)
```

- Bump-pointer аллокация (очень быстро)
- Освобождение всей арены сразу
- Идеально для временных данных одного scope

#### 3. `#jemalloc` - jemalloc аллокатор

```loki
process() in #jemalloc(10*MB)
```

- Оптимизирован для многопоточности
- Меньше фрагментации чем malloc
- Хорош для высоконагруженных систем

#### 4. `#stack` - Stack-подобный аллокатор

```loki
process() in #stack(4*KB)
```

- Создает stack arena заданного размера
- Быстрая аллокация, автоматическая очистка
- Для небольших временных буферов

---

### Время жизни аллокатора

По умолчанию аллокатор живет до **конца scope** вызывающей функции:

```loki
main :: pc () -> void {
  {
    process() in #arena(10*MB)
    // арена живет
  }  // арена уничтожается здесь, вся память освобождается
}
```

#### Оператор `^` - передача владения

Оператор `^` передает время жизни аллокатора **вызываемой** процедуре:

```loki
process :: pc () -> void in @allocator {
  data := make([]int, 1000)
  // обработка
}  // если вызвано с ^, память освобождается ЗДЕСЬ

main :: pc () -> void {
  process() in #arena(10*MB)^  // арена уничтожается в конце process()
  
  // здесь арена уже не существует
}
```

**Важно:** Компилятор запрещает возвращать данные из аллокатора с `^`:

```loki
// ❌ COMPILE ERROR: нельзя возвращать данные из temporary allocator
get_data :: pc () -> []int in @allocator {
  return make([]int, 1000)
}

main :: pc () -> void {
  data := get_data() in #malloc(1*MB)^  // ERROR: lifetime escape!
}

// ✅ OK: без ^ данные живут в caller scope
main :: pc () -> void {
  data := get_data() in #malloc(1*MB)  // OK
  // используем data
}  // память освобождается здесь
```

---

### Контекст и наследование аллокатора

Контекст передается неявно через call stack:

```loki
helper :: pc () -> void {
  // использует аллокатор из контекста
  data := make([]int, 100)
}

worker :: pc () -> void in @allocator {
  // используем переданный аллокатор
  temp := make([]int, 1000)
  
  // helper наследует аллокатор из контекста
  helper()  // будет использовать тот же аллокатор
}

main :: pc () -> void {
  worker() in #arena(10*MB)  // оба worker и helper используют эту арену
}
```

#### Переопределение аллокатора

Можно переопределить аллокатор для вложенного вызова:

```loki
worker :: pc () -> void in @allocator {
  // используем родительский аллокатор
  data := make([]int, 1000)
  
  // переключаемся на другой аллокатор для temporary работы
  temp_work() in #stack(4*KB)
  
  // снова используем родительский аллокатор
  more := make([]int, 500)
}
```

---

### Глобальный контекст

Глобальный контекст определяет конструкторы аллокаторов:

```loki
// Определяется в стандартной библиотеке
#ctx :: struct {
  malloc:    Allocator,    // конструктор malloc аллокатора
  jemalloc:  Allocator,    // конструктор jemalloc аллокатора
  arena:     Allocator,    // конструктор arena аллокатора
  stack:     Allocator,    // конструктор stack аллокатора
}
```

При вызове `process() in #malloc(10*MB)`:
1. Вызывается `#ctx.malloc.create(10*MB)`
2. Созданный аллокатор помещается в контекст
3. В конце scope вызывается `allocator.destroy()`

Это позволяет:
- Настраивать аллокаторы глобально
- Подменять реализации (для тестов, профилирования)
- Добавлять кастомные аллокаторы

---

## Многопоточность

### Thread-safety аллокаторов

По умолчанию аллокаторы **не thread-safe** (максимальная производительность).

Для многопоточности используйте флаг `mutex`:

```loki
main :: pc () -> void {
  // Создаем thread-safe аллокатор
  shared_work() in #malloc(100*MB, mutex=true)
}

shared_work :: pc () -> void in @allocator {
  // Несколько потоков могут безопасно аллоцировать
  spawn(|| { 
    data := make([]int, 1000)  // thread-safe allocation
  })
  
  spawn(|| {
    more := make([]byte, 2000)  // thread-safe allocation
  })
}
```

**Важно:** `mutex=true` защищает только **операции аллокатора**, не данные!

```loki
main :: pc () -> void {
  process() in #malloc(10*MB, mutex=true)
}

process :: pc () -> void in @allocator {
  data := make([]int, 1000)
  
  // ❌ DATA RACE! mutex не защищает доступ к данным
  spawn(|| { data[0] = 42 })
  spawn(|| { data[0] = 13 })
}
```

### Дополнительные флаги для аллокаторов

```loki
// Различные комбинации флагов
process() in #malloc(10*MB, mutex=true)
process() in #arena(5*MB, track_leaks=true)
process() in #malloc(100*MB, zero_memory=true)

// Композиция свойств
process() in #malloc(
  10*MB,
  mutex = true,
  track_leaks = true,
  zero_memory = false,
)
```

### Thread-local аллокаторы (будущая фича)

```loki
// Каждый поток получает свой аллокатор (нет contention)
parallel_work :: pc () -> void {
  for i in 0..<num_threads {
    spawn(|| {
      // thread-local arena, нет синхронизации
      work(i) in #arena(10*MB, thread_local=true)
    })
  }
}
```

---

## Проверка контрактов

### Статический анализ (compile-time)

Компилятор проверяет контракты для константных размеров:

```loki
// ✅ OK: 40KB < 1MB
calc :: pc () -> void in @allocator(1*MB) {
  data := make([10000]int)  // 40,000 bytes
}

// ❌ COMPILE ERROR: 400 bytes > 100 bytes
calc :: pc () -> void in @allocator(100) {
  data := make([100]int)  // 400 bytes
}
```

### Runtime проверки (опционально)

В DEBUG сборках компилятор автоматически включает runtime tracking:

```loki
process :: pc (n: int) -> void in @allocator(10*MB) {
  for i in 0..<n {
    data := make([]int, 1000)  // размер известен только в runtime
  }
}

main :: pc () -> void {
  when DEBUG {
    // Автоматически включается tracking
    process(1000) in #malloc(10*MB)
    // Если превышен бюджет: PANIC с трассировкой
  } else {
    // В release - zero overhead
    process(1000) in #malloc(10*MB)
  }
}
```

#### Явное управление проверками

```loki
ContractCheckMode :: enum {
  None,        // нет проверок (zero overhead)
  Panic,       // паника при превышении
  Log,         // логирование, продолжаем работу
  Fallback,    // переключение на резервный аллокатор
}

// Явно указываем режим
process() in #malloc(10*MB, check=.Panic)
process() in #malloc(10*MB, check=.Log)
process() in #malloc(10*MB, check=.None)
```

#### Статистика аллокатора

```loki
process :: pc () -> void in @allocator(10*MB) {
  data := make([]int, 1000)
  
  when DEBUG {
    // Получить статистику текущего аллокатора
    stats := context.allocator.stats()
    log.info("Memory: used=%d/%d peak=%d allocs=%d",
             stats.used, stats.budget, stats.peak, stats.count)
  }
}

// Или автоматический отчет
report_work :: pc () -> void in @allocator(10*MB, report_on_exit=true) {
  // ...
}
// Автоматически печатает:
// [ALLOC] report_work(): 2.5MB/10MB peak (127 allocations)
```

#### Реализация tracking (внутренняя)

```loki
// Компилятор генерирует wrapper для проверок:
TrackingAllocator :: struct {
  inner:       Allocator,   // настоящий аллокатор
  budget:      int,         // лимит
  used:        int,         // использовано
  peak_used:   int,         // пиковое использование
  alloc_count: int,         // количество аллокаций
}

// При превышении бюджета:
// PANIC: allocator budget exceeded: used 15.2MB, limit 10MB
//   at process_data() line 42
//   called from main() line 15
```

---

## Система типов

### Базовые типы

#### Целочисленные
```loki
int    // платформо-зависимый (32 или 64 бита)
i32    // 32-bit signed
i64    // 64-bit signed
i128   // 128-bit signed

uint   // платформо-зависимый unsigned
u8     // 8-bit unsigned (byte)
u16    // 16-bit unsigned
u32    // 32-bit unsigned
u64    // 64-bit unsigned
u128   // 128-bit unsigned
```

#### Числа с плавающей точкой
```loki
f32    // 32-bit float
f64    // 64-bit float
f128   // 128-bit float (если поддерживается платформой)
```

#### Другие базовые типы
```loki
bool      // true/false
byte      // alias для u8
rune      // Unicode code point (i32)
string    // UTF-8 строка (managed)
cstring   // C-style null-terminated string
void      // отсутствие значения
```

### Составные типы

#### Массивы фиксированного размера
```loki
arr: [100]int           // 100 элементов на стеке
matrix: [10][10]f32     // двумерный массив

// Инициализация
numbers: [5]int = {1, 2, 3, 4, 5}
zeros: [100]int         // все элементы = 0
```

#### Срезы (slices)
```loki
slice: []int            // динамический срез

// Создание среза (требует аллокатор)
process :: pc () -> void in @allocator {
  data := make([]int, 100)     // срез из 100 элементов
  buffer := make([]byte, 1024) // буфер 1KB
}

// Срез от массива
arr: [10]int
s := arr[:]      // весь массив
s := arr[2:5]    // элементы 2, 3, 4
```

#### Структуры
```loki
Point :: struct {
  x: f32,
  y: f32,
}

Person :: struct {
  name: string,
  age: int,
  address: Address,
}

// Использование
p := Point{x=10.0, y=20.0}
person := Person{
  name = "Alice",
  age = 30,
  address = addr,
}

// Доступ к полям
p.x = 15.0
log.info("Name: %s", person.name)
```

#### Перечисления
```loki
Color :: enum {
  Red,
  Green,
  Blue,
}

HttpStatus :: enum {
  Ok = 200,
  NotFound = 404,
  ServerError = 500,
}

Direction :: enum {
  North,      // 0
  East,       // 1
  South,      // 2
  West,       // 3
}

// Использование
c := Color.Red
status := HttpStatus.Ok
error_status: HttpStatus = .Ok

switch c {
case .Red:
  // обработка красного
case .Green, .Blue:
  // обработка зеленого или синего
}
```

#### Объединения (unions)
```loki
Result :: union {
  Ok: int,
  Error: string,
}

Value :: union {
  Int: i64,
  Float: f64,
  String: string,
  Bool: bool,
}

// Использование
r := Result{Ok=42}
v := Value{Float=3.14}

// Pattern matching
switch r {
case .Ok(value):
  log.info("Success: %d", value)
case .Error(msg):
  log.error("Error: %s", msg)
}
```

#### Словари (maps)
```loki
// Объявление типа
scores: map[string]int
cache: map[int][]byte

// Создание (требует аллокатор)
process :: pc () -> void in @allocator {
  m := make(map[string]int)
  m["alice"] = 100
  m["bob"] = 85
  
  // Проверка наличия ключа
  if value, ok := m["alice"]; ok {
    log.info("Alice: %d", value)
  }
}
```

---

## Синтаксис

### Объявление переменных

```loki
// Тип выводится автоматически
x := 42
name := "Alice"
data := make([]int, 100)

// Явное указание типа
y: int = 42
age: u8 = 25
buffer: [1024]byte

// Константа (compile-time)
PI :: 3.14159
MAX_SIZE :: 1024
NAME :: "Loki"

// Множественное присваивание
a, b := 10, 20
x, y, z := get_coordinates()
```

### Управляющие конструкции

#### If-else
```loki
if x > 0 {
  // code
} else if x < 0 {
  // code
} else {
  // code
}

// If с инициализацией
if value, ok := m["key"]; ok {
  // используем value
}

// If как выражение
result := if condition { value1 } else { value2 }
max := if a > b { a } else { b }
```

#### Циклы
```loki
// For с range
for i in 0..<10 {
  // i от 0 до 9
}

for i in 0..=10 {
  // i от 0 до 10 (включительно)
}

// For с итератором
for item in items {
  // обработка item
}

// For с индексом и значением
for i, item in items {
  log.info("[%d] = %v", i, item)
}

// While-подобный цикл
for condition {
  // пока condition true
}

// Бесконечный цикл
for {
  // бесконечно
  if done { break }
}

// Continue и break
for i in 0..<100 {
  if i % 2 == 0 { continue }
  if i > 50 { break }
  process(i)
}
```

#### Switch
```loki
switch value {
case 0:
  // code
case 1, 2, 3:
  // multiple values
case 4:
  // code
default:
  // default case
}

// Switch с fallthrough
switch x {
case 1:
  do_something()
  fallthrough  // явный fallthrough в следующий case
case 2:
  do_something_else()
}

// Switch как выражение
result := switch value {
case 0: "zero"
case 1: "one"
default: "other"
}

// Switch без значения (альтернатива if-else chain)
switch {
case x > 100:
  // x большой
case x > 10:
  // x средний
default:
  // x маленький
}
```

---

## Операторы

### Арифметические
```loki
+ - * / %        // базовые арифметические
+= -= *= /= %=   // compound assignment
++ --            // инкремент/декремент (постфикс)
```

### Сравнение
```loki
== !=            // равенство
< <= > >=        // сравнение
```

### Логические
```loki
&& ||            // логическое И, ИЛИ
!                // логическое НЕ
```

### Битовые
```loki
& | ^            // AND, OR, XOR
<< >>            // сдвиги
~                // NOT
&= |= ^= <<= >>= // compound assignment
```

### Другие
```loki
:=               // объявление и присваивание
=                // присваивание
::               // константа/тип
.                // доступ к полю
->               // возвращаемый тип
<-               // return
```

---

## Примеры использования

### Пример 1: Простая обработка данных

```loki
// Обработка массива целых чисел
sum :: pc (arr: []int) -> int {
  total := 0
  for x in arr {
    total += x
  }
  return total
}

average :: pc (arr: []int) -> f64 {
  if len(arr) == 0 {
    return 0.0
  }
  total := sum(arr)
  return f64(total) / f64(len(arr))
}

main :: pc () -> void {
  // Массив на стеке
  numbers: [10]int = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
  
  s := sum(numbers[:])
  avg := average(numbers[:])
  
  log.info("Sum: %d, Average: %.2f", s, avg)
}
```

### Пример 2: Динамическая аллокация

```loki
process_data :: pc (size: int) -> []int in @allocator {
  // Динамическое выделение
  data := make([]int, size)
  
  for i in 0..<size {
    data[i] = i * i
  }
  
  return data
}

main :: pc () -> void {
  // Используем arena для временных данных
  result := process_data(1000) in #arena(10*MB)
  
  // Обработка result
  sum := 0
  for x in result {
    sum += x
  }
  
  log.info("Sum of squares: %d", sum)
  
  // arena автоматически очищается в конце scope
}
```

### Пример 3: Работа со структурами

```loki
Vec2 :: struct {
  x: f32,
  y: f32,
}

add :: pc (a: Vec2, b: Vec2) -> Vec2 {
  return Vec2{
    x = a.x + b.x,
    y = a.y + b.y,
  }
}

length :: pc (v: Vec2) -> f32 {
  return sqrt(v.x * v.x + v.y * v.y)
}

main :: pc () -> void {
  v1 := Vec2{x=3.0, y=4.0}
  v2 := Vec2{x=1.0, y=2.0}
  
  v3 := add(v1, v2)
  len := length(v3)
  
  log.info("Result: (%.2f, %.2f), length: %.2f", v3.x, v3.y, len)
}
```

### Пример 4: Многопроходная обработка

```loki
filter_positive :: pc (data: []int) -> []int in @allocator {
  // Подсчитываем сколько положительных
  count := 0
  for x in data {
    if x > 0 { count += 1 }
  }
  
  // Создаем результирующий массив
  result := make([]int, count)
  j := 0
  for x in data {
    if x > 0 {
      result[j] = x
      j += 1
    }
  }
  
  return result
}

multiply :: pc (data: []int, factor: int) -> []int in @allocator {
  result := make([]int, len(data))
  for i, x in data {
    result[i] = x * factor
  }
  return result
}

main :: pc () -> void {
  input: [10]int = {-5, 3, -2, 8, 0, -1, 4, 7, -3, 6}
  
  // Каждый проход использует свою временную арену
  positive := filter_positive(input[:]) in #arena(1*MB)^
  doubled := multiply(positive, 2) in #arena(1*MB)^
  
  log.info("Result count: %d", len(doubled))
  
  // обе арены уже освобождены
}
```

### Пример 5: Работа со словарями

```loki
count_words :: pc (text: string) -> map[string]int in @allocator {
  words := make(map[string]int)
  
  // Разбиваем текст на слова (упрощенно)
  word := ""
  for ch in text {
    if ch == ' ' || ch == '\n' || ch == '\t' {
      if len(word) > 0 {
        words[word] += 1
        word = ""
      }
    } else {
      word += ch
    }
  }
  
  if len(word) > 0 {
    words[word] += 1
  }
  
  return words
}

main :: pc () -> void {
  text := "hello world hello loki world"
  
  counts := count_words(text) in #malloc(1*MB)
  
  for word, count in counts {
    log.info("%s: %d", word, count)
  }
  
  // malloc освобождается здесь
}
```

### Пример 6: Многопоточная обработка

```loki
worker :: pc (id: int, data: []int) -> void {
  log.info("Worker %d processing %d items", id, len(data))
  
  // Обработка данных
  for i in 0..<len(data) {
    data[i] = data[i] * data[i]  // возведение в квадрат
  }
  
  log.info("Worker %d done", id)
}

parallel_process :: pc (data: []int, num_workers: int) -> void {
  chunk_size := len(data) / num_workers
  
  for i in 0..<num_workers {
    start := i * chunk_size
    end := if i == num_workers - 1 { len(data) } else { start + chunk_size }
    
    spawn(|| worker(i, data[start:end]))
  }
  
  wait_all()
}

main :: pc () -> void {
  process :: pc () -> void in @allocator {
    data := make([]int, 10000)
    
    // Заполняем данные
    for i in 0..<len(data) {
      data[i] = i
    }
    
    // Параллельная обработка
    parallel_process(data, 4)
    
    // Проверяем результат
    sum := 0
    for x in data {
      sum += x
    }
    log.info("Sum: %d", sum)
  }
  
  // Thread-safe аллокатор для shared данных
  process() in #malloc(100*MB, mutex=true)
}
```

### Пример 7: Перечисления и паттерн-матчинг

```loki
HttpStatus :: enum {
  Ok = 200,
  Created = 201,
  BadRequest = 400,
  NotFound = 404,
  ServerError = 500,
}

Result :: union {
  Success: string,
  Error: HttpStatus,
}

handle_response :: pc (r: Result) -> void {
  switch r {
  case .Success(data):
    log.info("Success: %s", data)
  case .Error(status):
    switch status {
    case .BadRequest:
      log.error("Bad request")
    case .NotFound:
      log.error("Not found")
    case .ServerError:
      log.error("Server error")
    default:
      log.error("Unknown error: %d", status)
    }
  }
}

main :: pc () -> void {
  r1 := Result{Success="Data received"}
  r2 := Result{Error=HttpStatus.NotFound}
  
  handle_response(r1)
  handle_response(r2)
}
```

---

## Модули и импорты

### Объявление модуля
```loki
module math

// по умолчанию всё публично
add :: pc (a: int, b: int) -> int {
  return a + b
}

multiply :: pc (a: int, b: int) -> int {
  return a * b
}

// Приватные функции помечаются тегом @private

@private
helper :: pc (x: int) -> int {
  return x * 2
}
```

### Импорт модулей
```loki
import "core:log"
import "core:fmt"
import "math"

// Использование
main :: pc () -> void {
  result := math.add(10, 20)
  log.info("Result: %d", result)
}
```

---

## Будущие расширения

### Generics (обобщенное программирование)
```loki
// Обобщенная структура данных
Stack :: struct<T> {
  items: []T,
  count: int,
  capacity: int,
}

push :: pc<T> (s: ^Stack<T>, item: T) -> void in @allocator {
  if s.count >= s.capacity {
    // расширяем capacity
    new_capacity := s.capacity * 2
    new_items := make([]T, new_capacity)
    copy(new_items, s.items)
    s.items = new_items
    s.capacity = new_capacity
  }
  
  s.items[s.count] = item
  s.count += 1
}

pop :: pc<T> (s: ^Stack<T>) -> (T, bool) {
  if s.count == 0 {
    return T{}, false
  }
  
  s.count -= 1
  return s.items[s.count], true
}

// Использование
main :: pc () -> void {
  create_stack :: pc<T> () -> Stack<T> in @allocator {
    return Stack<T>{
      items = make([]T, 10),
      count = 0,
      capacity = 10,
    }
  }
  
  stack := create_stack<int>() in #malloc(1*MB)
  push(&stack, 42)
  push(&stack, 13)
  
  if value, ok := pop(&stack); ok {
    log.info("Popped: %d", value)
  }
}
```

### Интерфейсы
```loki
// Определение интерфейса
Writer => {
  write :: pc (data: []byte) -> int
  flush :: pc () -> void
}

Reader => {
  read :: pc (buffer: []byte) -> int
}

// Реализация
FileWriter :: struct {
  handle: FileHandle,
}

// реализуем оба интерфейса
// fw работает как self
fw: FileWriter => (Writer, Reader) => {
  // метод вызывает мутацию
  write :: pc #mut (data: []byte) -> int {
    // реализация записи в файл
    return len(data)
  }

  flush :: pc #mut () -> void {
    // реализация flush
  }  

  read :: pc (buffer: []byte) -> int {
    // реализация
  }
}



```

### Error handling (Result type)
```loki
// Result type (встроенный)
Result :: union<T, E> {
  Ok: T,
  Err: E,
}

// Использование
open_file :: pc (path: string) -> Result<File, FileError> {
  // пытаемся открыть файл
  if file_exists(path) {
    return Result{Ok=file}
  } else {
    return Result{Err=FileError.NotFound}
  }
}

main :: pc () -> void {
  result := open_file("test.txt")
  
  switch result {
  case .Ok(file):
    // работаем с файлом
    log.info("File opened")
  case .Err(error):
    log.error("Failed to open file: %v", error)
    return
  }
}

// Или с оператором ?
main :: pc () -> Result<void, Error> {
  file := open_file("test.txt")?  // автоматически возвращает Err
  data := read_file(file)?
  process(data)?
  
  return Result{Ok=void}
}
```

### Defer для множественной очистки
```loki
main :: pc () -> void {
  file := open_file("test.txt")
  defer close_file(file)  // выполнится в конце scope
  
  buffer := allocate(1024)
  defer free(buffer)
  
  connection := connect("localhost:8080")
  defer disconnect(connection)
  
  // работа с ресурсами
  // все defer выполнятся в обратном порядке
}
```

---

## Соглашения и best practices

### Управление памятью

```loki
// ✅ ХОРОШО: используйте stack когда возможно
compute :: pc (n: int) -> int {
  buffer: [1024]byte
  // работа
}

// ✅ ХОРОШО: arena для временных данных
process_frame :: pc () -> void in @allocator {
  temp_data := make([]int, 1000)
  // обработка
}

main :: pc () -> void {
  for {
    process_frame() in #arena(10*MB)^  // очищается каждую итерацию
  }
}

// ✅ ХОРОШО: malloc для долгоживущих данных
global_cache := init_cache() in #malloc(100*MB)

// ❌ ПЛОХО: malloc для временных данных каждый кадр
for {
  process() in #malloc(10*MB)  // фрагментация!
}
```

### Контракты

```loki
// ✅ ХОРОШО: явный контракт с запасом
process :: pc () -> void in @allocator(10*MB) {
  // максимум ~8MB используется
}

// ⚠️ ОСТОРОЖНО: слишком точный контракт
process :: pc () -> void in @allocator(8*MB) {
  // может превысить при изменении логики
}

// ✅ ХОРОШО: контракт только когда нужна heap аллокация
simple_calc :: pc (x: int) -> int {
  // только stack, контракт не нужен
  return x * x
}
```

### Многопоточность

```loki
// ✅ ХОРОШО: thread-local для независимых задач
parallel_for(items, |item| {
  process(item) in #arena(1*MB, thread_local=true)
})

// ✅ ХОРОШО: mutex только когда нужен shared доступ
shared_process() in #malloc(100*MB, mutex=true)

// ❌ ПЛОХО: mutex когда не нужно (overhead)
independent_work() in #arena(10*MB, mutex=true)  // зачем?
```

---

## Производительность

### Overhead различных подходов

| Подход         | Overhead на аллокацию | Use case             |
|----------------|-----------------------|----------------------|
| Stack          | ~0ns                  | Фиксированный размер |
| Arena          | ~5-10ns               | Временные данные     |
| malloc         | ~50-100ns             | Долгоживущие данные  |
| malloc + mutex | ~70-120ns             | Shared данные        |
| Debug tracking | +10-20ns              | Разработка           |

### Оптимизация

```loki
// ❌ МЕДЛЕННО: много мелких аллокаций
for i in 0..<10000 {
  temp := make([]int, 10)  // 10000 аллокаций!
  process(temp)
}

// ✅ БЫСТРО: одна большая аллокация
buffer := make([]int, 10 * 10000)
for i in 0..<10000 {
  temp := buffer[i*10:(i+1)*10]
  process(temp)
}

// ✅ БЫСТРО: переиспользование буфера
buffer := make([]int, 10)
for i in 0..<10000 {
  fill_buffer(buffer, i)
  process(buffer)
}
```

---

## Заключение

Loki стремится найти баланс между:
- **Контролем** (как C/C++) 
- **Безопасностью** (как Rust)
- **Простотой** (как Zig/Odin)

### Ключевые преимущества

✅ **Явное управление памятью** без ручного free  
✅ **Контракты на память** для документации и проверок  
✅ **Статическая безопасность** без сложного borrow checker  
✅ **Zero-cost abstractions** - не платите за то, что не используете  
✅ **Простой и предсказуемый** - легко понять что происходит  
✅ **Scope-based lifetime** - автоматическая очистка ресурсов  
✅ **Runtime проверки** в DEBUG режиме для раннего обнаружения багов  
✅ **Гибкие стратегии аллокации** - выбирайте оптимальную для задачи  

### Целевые применения

- 🎯 Системное программирование
- 🎯 Embedded системы
- 🎯 Игровые движки
- 🎯 Высокопроизводительные сервера
- 🎯 Real-time приложения
- 🎯 Компиляторы и интерпретаторы
- 🎯 Операционные системы

### Философия

> "Дайте программисту контроль, но сделайте правильное действие простым"

Loki не пытается быть самым безопасным (как Rust) или самым простым (как Go).  
Вместо этого, Loki стремится дать программисту **полный контроль** с **разумными умолчаниями** и **понятной моделью**.

### Статус проекта

Loki находится в **активной разработке**. Текущая реализация включает:
- ✅ Лексер (полностью функционален)
- ✅ Парсер (базовые типы и литералы)
- 🚧 Семантический анализ (в планах)
- 🚧 Кодогенерация (в планах)
- 🚧 Стандартная библиотека (в планах)

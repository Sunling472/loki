```odin
// default values context
#ctx :: struct {
  malloc:    Allocator,
  jemmalloc: Allocator,
  arena:     Allocator,
  stack:     Allocator,
}

calc :: pc () -> void in @alloc {}

// #stack по умолчанию
main :: pc () -> void {
  $tmp :: #ctx.arena(100*MB)
  calc() in #malloc(10*MB) // or #ctx.malloc(10*MB), #malloc освободится в конце родительского скоупа
  calc() in #malloc(10*MB)^ // #malloc освободится в конце calc()
  calc() in #malloc(mutex=true) // для многопоточности
  calc() in $tmp
}

```

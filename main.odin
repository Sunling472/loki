package loki

import "core:log"
import "lexer"


main :: proc() {
  context.logger = log.create_console_logger()
  data := "// hello world\na := 1"
  res := lexer.tokenize(data)
  log.info(res)
}

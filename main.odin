package loki

import "core:log"
import "parser"


main :: proc() {
  context.logger = log.create_console_logger()
  parser.tt()
}

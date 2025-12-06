package loki

import "core:log"
import "parser"
import "ast"

main :: proc() {
	context.logger = log.create_console_logger()

	p: parser.Parser
	pkg, ok := parser.parse_package_from_path("/home/alise/loki", &p)
	assert(ok)
	
	
}

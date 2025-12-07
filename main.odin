package loki

import "core:fmt"
import "core:image"
import "core:log"
import "parser"
import "tokenizer"
import "ast"

main :: proc() {
	context.logger = log.create_console_logger()

	p: parser.Parser
	p = parser.default_parser()

	pkg, ok := parser.parse_package_from_path("/home/alise/loki/example", &p)
	if !ok {
		return
	}

	for fullpath, file in pkg.files {
		for d in file.decls {
			// log.info(d.derived_stmt)
			// log.info("\n")
			#partial switch v in d.derived_stmt {
			case ^ast.Value_Decl:
				log.info(v.values)
			case ^ast.Block_Stmt:
			}
		}
	}
}

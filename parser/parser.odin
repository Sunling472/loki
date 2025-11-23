package parser

import "core:log"
import "../lexer"

Parser :: struct {
	tokens:    []lexer.Token,
	offset:    int
}

Error :: struct {
	msg: string,
	type: ErrorType
}

ErrorType :: enum {
	None,
	Unexpect_Token
}

make_parser :: proc(tokens: []lexer.Token) -> (p: Parser) {
	p.offset = 0
	p.tokens = tokens

	return
}

advance :: proc(p: ^Parser) -> lexer.Token {
	if p.offset >= len(p.tokens) {
		return lexer.Token{kind=.EOF}
	}
	p.offset += 1
	return p.tokens[p.offset]
}

peek :: proc(p: Parser, offset: int) -> lexer.Token {
	if p.offset + offset >= len(p.tokens) {
		return lexer.Token{kind=.EOF}
	}

	return p.tokens[p.offset+offset]
}

current :: proc(p: Parser) -> lexer.Token {
	return p.tokens[p.offset]
}

expect :: proc(p: ^Parser, kind: lexer.TokenKind) -> (err: Error) {
	current := current(p^)
	if current.kind != kind {
		err.msg = "Unexpected Token"
		err.type = .Unexpect_Token
		return
	}
	p.offset += 1

	return
}

tt :: proc() {
	tokens := lexer.tokenize("a => 1")
	parser := make_parser(tokens[:])

	log.info(expect(&parser, .IDENT))
	log.info(current(parser))
}

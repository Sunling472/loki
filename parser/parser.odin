package parser

import "../lexer"
import "core:log"
import "core:strconv"

Parser :: struct {
	tokens: []lexer.Token,
	offset: int,
}

Error :: struct {
	msg:  string,
	type: ErrorType,
}

ErrorType :: enum {
	None,
	Unexpect_Token,
}

make_parser :: proc(tokens: []lexer.Token) -> (p: Parser) {
	p.offset = 0
	p.tokens = tokens

	return
}

advance :: proc(p: ^Parser) -> lexer.Token {
	if p.offset + 1 >= len(p.tokens) {
		return lexer.Token{kind = .EOF}
	}
	p.offset += 1
	return p.tokens[p.offset]
}

peek :: proc(p: Parser, offset: int = 0) -> lexer.Token {
	if p.offset + offset >= len(p.tokens) {
		return lexer.Token{kind = .EOF}
	}

	return p.tokens[p.offset + offset]
}

current :: proc(p: Parser) -> lexer.Token {
	return peek(p)
}

expect :: proc(p: ^Parser, kind: lexer.TokenKind) -> (ok: bool, err: Error) {
	current := current(p^)
	if current.kind != kind {
		err.msg = "Unexpected Token"
		err.type = .Unexpect_Token
		return
	}

	p.offset += 1
	ok = true

	return
}

consume :: proc(p: ^Parser, kind: lexer.TokenKind) -> bool {
	curr := current(p^)
	if curr.kind != kind {
		return false
	}
	advance(p)
	return true
}

parse_literal :: proc(p: ^Parser) -> (l: Literal) {
	curr := current(p^)
	#partial switch curr.kind {
	case .INT_LIT:
		log.info(curr.lexeme)
		val, ok := strconv.parse_int(curr.lexeme)
		assert(ok)
		l.kind = IntLit(val)
	case .FLOAT_LIT:
		val, ok := strconv.parse_f32(curr.lexeme)
		assert(ok)
		l.kind = FloatLit(val)
	case .STRING_LIT:
		val := curr.lexeme
		l.kind = val
	case .BOOL_LIT:
		val, ok := strconv.parse_bool(curr.lexeme)
		assert(ok)
		l.kind = BoolLit(val)
	case .STRUCT:
	case .ENUM:
	case .UNION:
	}

	return
}

parse_type :: proc(p: ^Parser) -> (t: Type) {
	c := current(p^)

	#partial switch c.kind {
	case .INT:
		t.kind = TypeBasic {
			default = int(0),
			kind    = .Int,
		}
	case .I32:
		t.kind = TypeBasic {
			default = i32(0),
			kind    = .I32,
		}
	case .I64:
		t.kind = TypeBasic {
			default = i64(0),
			kind    = .I64,
		}
	case .I128:
		t.kind = TypeBasic {
			default = i128(0),
			kind    = .I128,
		}

	case .F32:
		t.kind = TypeBasic {
			default = f32(0),
			kind    = .F32,
		}
	case .F64:
		t.kind = TypeBasic {
			default = f64(0),
			kind    = .F64,
		}

	case .STRING:
		t.kind = TypeBasic {
			default = string(""),
			kind    = .String,
		}
	case .CSTRING:
		t.kind = TypeBasic {
			default = cstring(""),
			kind    = .CString,
		}

	case .RUNE:
		t.kind = TypeBasic {
			default = rune(0),
			kind    = .Rune,
		}

	case .BYTE:
		t.kind = TypeBasic {
			default = byte(0),
			kind    = .Byte,
		}

	case .BOOL:
		t.kind = TypeBasic {
			default = false,
			kind    = .Bool,
		}

	case .LBRACK:
		next := peek(p^, 1)
		if next.kind == .INT_LIT do t = parse_array_type(p)
		if next.kind == .RBRACK  do t = parse_slice_type(p)

	case .MAP:
		t = parse_map_type(p)		
	case .STRUCT:
		t = parse_struct_type(p)
	case .ENUM:
		t = parse_enum_type(p)
	}
	return
}

parse_struct_type :: proc(p: ^Parser) -> (t: Type) {
	st: StructType
	fields: [dynamic]StructField

	advance(p)
	ok, _ := expect(p, .LBRACE)
	assert(ok)

	loop: for {
		f: StructField
		c := current(p^)

		#partial switch c.kind {
		case .IDENT:
			f.ident = c.lexeme

			advance(p)
			ok, _ = expect(p, .COLON)
			assert(ok)

			ty := parse_type(p)
			f.type = ty

			append(&fields, f)

			advance(p)
			continue loop
		case .COMMA:
			advance(p)
			continue loop
		case .RBRACE:
			advance(p)
			break loop
		}
	}
	st.fields = fields[:]
	t.kind = st
	return
}

parse_enum_type :: proc(p: ^Parser) -> (t: Type) {
	et: EnumType
	fields: [dynamic]EnumField

	advance(p)
	ok, _ := expect(p, .LBRACE)
	assert(ok)

	loop: for {
		f: EnumField
		c := current(p^)
		#partial switch c.kind {
		case .IDENT:
			f.ident = c.lexeme
			if len(fields) > 0 {
				f.value = fields[len(fields) - 1].value + 1
			}
			advance(p)
			c = current(p^)

			// TODO
			if c.kind == .ASSIGN {
				advance(p)
				lit_tok := current(p^)
				log.info(lit_tok.lexeme)
				val, ok := strconv.parse_int(lit_tok.lexeme)
				assert(ok)
				f.value = val
				advance(p)
			}
			append(&fields, f)
			continue loop
		case .COMMA:
			advance(p)
			continue loop

		case .RBRACE:
			advance(p)
			break loop

		}
	}

	et.values = fields[:]
	t.kind = et

	return
}

parse_array_type :: proc(p: ^Parser) -> (t: Type) {
	advance(p)
	lit := parse_literal(p);advance(p)
	ok, _ := expect(p, .RBRACK)
	ty := parse_type(p)

	t.kind = ArrayType {
		size = lit,
		type = &ty
	}
	
	return
}

parse_slice_type :: proc(p: ^Parser) -> (t: Type) {
	advance(p)
	ok, _ := expect(p, .RBRACK);assert(ok)
	ty := parse_type(p)

	t.kind = SliceType {
		type = &ty
	}
	
	return
}

parse_map_type :: proc(p: ^Parser) -> (t: Type) {
	advance(p)
	ok, _ := expect(p, .LBRACK); assert(ok)
	key_ty := parse_type(p)
	advance(p)
	ok, _ = expect(p, .RBRACK); assert(ok)
	val_ty := parse_type(p)

	t.kind = MapType {
		key = &key_ty,
		value = &val_ty
	}
	
	return
}

tt :: proc() {
	tokens := lexer.tokenize("map[string]int")
	parser := make_parser(tokens[:])
	lit := parse_type(&parser)
	log.info(lit)
}


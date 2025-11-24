package lexer

import "core:log"
import "core:unicode/utf8"

Lexer :: struct {
	using pos: Pos,
	data:      string,
	ch:        rune,
	w:         int,
	lexeme:    string,
}

Error :: struct {
	msg:  string,
	type: ErrorType,
}

ErrorType :: enum {
	None,
	EOF, // Not necessarily an error

	// Tokenizing Errors
	Unterminated_Block_Comment,
	Invalid_Rune,
	Illegal_Character,
	Invalid_Number,
	String_Not_Terminated,
	Invalid_String,


	// Parsing Errors
	Unexpected_Token,
	Expected_String_For_Object_Key,
	Duplicate_Object_Key,
	Expected_Colon_After_Key,

	// Allocating Errors
	Invalid_Allocator,
	Out_Of_Memory,
}

init :: proc(l: ^Lexer, data: string) {
	l.data = data
	l.line = 1
	// l.column = 1
	l.offset = 0
	next_rune(l)
}

clean :: proc(l: ^Lexer) {
	l.pos.line = 1
	l.pos.column = 0
	l.pos.offset = 0
	l.data = ""
	l.ch = 0
	l.w = 0
}

next_rune :: proc(l: ^Lexer) -> rune {
	if l.offset >= len(l.data) do l.ch = utf8.RUNE_EOF
	else {
		l.offset += l.w
		l.column += 1
		l.ch, l.w = utf8.decode_rune_in_string(l.data[l.offset:])

		if l.offset >= len(l.data) do l.ch = utf8.RUNE_EOF
	}

	return l.ch
}

skip_digits :: proc(l: ^Lexer) {
	for l.offset < len(l.data) {
		if '0' <= l.ch && l.ch <= '9' {
			// Okay
		} else {
			return
		}
		next_rune(l)
	}
}
skip_hex_digits :: proc(l: ^Lexer) {
	for l.offset < len(l.data) {
		next_rune(l)
		switch l.ch {
		case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
		// Okay
		case:
			return
		}
	}
}

scan_escape :: proc(l: ^Lexer) -> bool {
	// Мы уже стоим на символе ПОСЛЕ \
	switch l.ch {
	case '"', '\\', '/', '\'', 'b', 'f', 'n', 'r', 't':
		next_rune(l)
		return true
	case 'u':
		next_rune(l) // пропускаем 'u'
		for i := 0; i < 4; i += 1 {
			if l.offset >= len(l.data) {
				return false
			}
			switch l.ch {
			case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
				next_rune(l)
			case:
				return false
			}
		}
		return true
	case:
		// Неизвестная escape-последовательность — просто пропускаем её
		// (как делает Odin, C, Go)
		next_rune(l)
		return true
	}
}

skip_whitespace :: proc(l: ^Lexer) -> rune {
	loop: for l.offset < len(l.data) {
		switch l.ch {
		case ' ', '\t', '\v', '\f', '\r':
			next_rune(l)
		case '\n':
			l.line += 1
			l.column = 0
			next_rune(l)
		case:
			break loop
		}
	}
	return l.ch
}

skip_alphanum :: proc(l: ^Lexer) {
	for l.offset < len(l.data) {
		switch l.ch {
		case 'A' ..= 'Z', 'a' ..= 'z', '0' ..= '9', '_':
			next_rune(l)
			continue
		}

		return
	}
}

scan_string :: proc(l: ^Lexer) -> bool {
	// Мы уже съели открывающую кавычку, начинаем с первого символа внутри
	for l.offset < len(l.data) {
		switch l.ch {
		case '"':
			// Нашли закрывающую кавычку — успех!
			next_rune(l) // пропускаем саму "
			return true

		case '\n':
			next_rune(l)

		case utf8.RUNE_EOF:
			return false

		case '\\':
			// Экранирующая последовательность
			next_rune(l) // пропускаем \
			if l.ch == utf8.RUNE_EOF {
				return false
			}
			if !scan_escape(l) {
				// Неизвестная escape-последовательность — можно либо игнорировать,
				// либо считать ошибкой. Пока игнорируем, как в C/Odin.
			}
		// продолжаем цикл

		case:
			// Обычный символ — просто идём дальше
			next_rune(l)
		}
	}
	// Дошли до конца файла без закрывающей кавычки
	return false
}

skip_decimal_digits :: proc(l: ^Lexer) {
	for l.offset < len(l.data) {
		switch l.ch {
		case '0' ..= '9', '_':
			// разрешаем _ как разделитель (1_000_000)
			next_rune(l)
		case:
			return
		}
	}
}

skip_binary_digits :: proc(l: ^Lexer) {
	for l.offset < len(l.data) {
		switch l.ch {
		case '0' ..= '1', '_':
			next_rune(l)
		case:
			return
		}
	}
}

skip_octal_digits :: proc(l: ^Lexer) {
	for l.offset < len(l.data) {
		switch l.ch {
		case '0' ..= '7', '_':
			next_rune(l)
		case:
			return
		}
	}
}

scan_rune :: proc(l: ^Lexer) -> bool {
	if l.ch == utf8.RUNE_EOF {
		return false
	}

	// Пустой rune '' — ошибка
	if l.ch == '\'' {
		return false
	}

	// Обычный символ: 'a', 'я', '👍'
	if l.ch != '\\' {
		next_rune(l)
	} else {
		// Экранированная последовательность
		next_rune(l) // пропускаем \
		if l.ch == utf8.RUNE_EOF {
			return false
		}

		switch l.ch {
		case '\'', '"', '\\', 'n', 'r', 't', 'b', 'f', 'v', '0':
			next_rune(l)

		case 'u':
			// \uXXXX — 4 hex цифры
			next_rune(l)
			for i := 0; i < 4; i += 1 {
				if l.offset >= len(l.data) {
					return false
				}
				switch l.ch {
				case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
					next_rune(l)
				case:
					return false
				}
			}

		case 'U':
			// \UXXXXXXXX — 8 hex цифр
			next_rune(l)
			for i := 0; i < 8; i += 1 {
				if l.offset >= len(l.data) {
					return false
				}
				switch l.ch {
				case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F':
					next_rune(l)
				case:
					return false
				}
			}

		case:
			// Неизвестный escape — просто пропускаем
			next_rune(l)
		}
	}

	// Должна быть закрывающая кавычка
	if l.ch != '\'' {
		return false
	}
	next_rune(l) // съедаем '
	return true
}

skip_line_comment :: proc(l: ^Lexer) {
	// Мы уже стоим на первом '/', второй уже съеден
	// Просто идём до конца строки или конца файла
	for l.offset < len(l.data) {
		if l.ch == '\n' || l.ch == utf8.RUNE_EOF {
			break
		}
		next_rune(l)
	}
}

skip_block_comment :: proc(l: ^Lexer) -> bool {
	// Мы уже съели /*, ищем */
	depth := 1
	next_rune(l) // пропускаем символ после '*'

	for l.offset < len(l.data) {
		if l.ch == utf8.RUNE_EOF {
			return false
		}

		if l.ch == '*' {
			next_rune(l)
			if l.ch == '/' {
				next_rune(l)
				depth -= 1
				if depth == 0 {
					return true
				}
			}
		} else if l.ch == '/' {
			next_rune(l)
			if l.ch == '*' {
				next_rune(l)
				depth += 1
			}
		} else {
			next_rune(l)
		}
	}

	return false // не нашли закрывающий */
}

get_token :: proc(l: ^Lexer) -> (res: Token, err: Error) {
	skip_whitespace(l)

	res.kind = .INVALID
	res.start_pos = l.pos

	current := l.ch
	next_rune(l)

	block: switch current {
	case utf8.RUNE_ERROR:
		err.type = .Illegal_Character
	case utf8.RUNE_EOF:
		res.kind = .EOF
		err.type = .EOF
	case '\n':
		res.kind = .NEW_LINE
		return
	case 'A' ..= 'Z', 'a' ..= 'z', '_':
		res.kind = .IDENT
		skip_alphanum(l)
	case '#':
		res.kind = .HASH
	case '"':
		lexeme_start := l.offset
		ok := scan_string(l)
		if !ok {
			err.type = .String_Not_Terminated
			res.kind = .INVALID
			return
		}
		res.kind = .STRING_LIT
		res.lexeme = l.data[lexeme_start:l.offset]

	case '\'':
		lexeme_start := l.offset
		res.kind = .RUNE_LIT
		if !scan_rune(l) {
			err.type = .Invalid_Rune
			res.kind = .INVALID
			return res, err
		}

	// res.lexeme = l.data[lexeme_start : l.offset]
	// return res, err
	case '-':
		res.kind = .MINUS
		switch l.ch {
		case '>':
			next_rune(l)
			res.kind = .RARROW
		case '=':
		// TODO
		}
	case '<':
		res.kind = .LT
		switch l.ch {
		case '-':
			next_rune(l)
			res.kind = .LARROW
		case '=':
			next_rune(l)
			res.kind = .LEQ
		}
	case '>':
		res.kind = .GT
		switch l.ch {
		case '=':
			res.kind = .GEQ
		}
	case ':':
		res.kind = .COLON
		switch l.ch {
		case ':':
			next_rune(l)
			res.kind = .DOUBLE_COLON
		case '=':
			next_rune(l)
			res.kind = .COLON_ASSIGN
		}
	case '=':
		res.kind = .ASSIGN
		switch l.ch {
		case '>':
			next_rune(l)
			res.kind = .METHOD_ARROW
		}
	case '(':
		res.kind = .LPAREN
	case ')':
		res.kind = .RPAREN
	case '[':
		res.kind = .LBRACK
	case ']':
		res.kind = .RBRACK
	case '{':
		res.kind = .LBRACE
	case '}':
		res.kind = .RBRACE
	case ',':
		res.kind = .COMMA
	case '0' ..= '9':
		lexeme_start := l.offset
		res.kind = .INT_LIT

		// 1. Съедаем целую часть (включая префиксы 0b, 0o, 0x)
		is_hex := false
		is_binary := false
		is_octal := false

		if current == '0' && l.offset + l.w < len(l.data) {
			peek, _ := utf8.decode_rune_in_string(l.data[l.offset:l.offset + l.w])
			switch peek {
			case 'x', 'X':
				is_hex = true
				next_rune(l);next_rune(l) // съедаем 0x
				skip_hex_digits(l)
			case 'b', 'B':
				is_binary = true
				next_rune(l);next_rune(l)
				skip_binary_digits(l)
			case 'o', 'O':
				is_octal = true
				next_rune(l);next_rune(l)
				skip_octal_digits(l)
			case:
				// просто ноль или обычное начало числа
				next_rune(l)
			}
		} else {
			next_rune(l)
		}

		// 2. Если не hex/bin/oct — пропускаем обычные цифры + _
		if !is_hex && !is_binary && !is_octal {
			skip_decimal_digits(l)
		}

		// 3. Проверяем, есть ли точка → это float
		if l.ch == '.' && !is_hex && !is_binary && !is_octal {
			// Убедимся, что после точки идёт цифра (иначе это может быть метод: 1.to_string)
			if l.offset + l.w < len(l.data) {
				next_char := rune(l.data[l.offset + l.w])
				if '0' <= next_char && next_char <= '9' {
					res.kind = .FLOAT_LIT
					next_rune(l) // съедаем '.'
					skip_decimal_digits(l)
				}
			}
		}

		// 4. Экспонента (e или E), только для десятичных и только если уже float или может стать float
		if (res.kind == .FLOAT_LIT || !is_hex && !is_binary && !is_octal) &&
		   (l.ch == 'e' || l.ch == 'E') {
			res.kind = .FLOAT_LIT
			next_rune(l)

			// Опциональный знак + или -
			if l.ch == '+' || l.ch == '-' {
				next_rune(l)
			}

			if '0' <= l.ch && l.ch <= '9' {
				skip_decimal_digits(l)
			} else {
				err.msg = "Invalid Number"
				err.type = .Invalid_Number
				return
			}
		}

		// 5. Суффиксы: f32, f64, u, i32 и т.д.
		// if l.ch == 'f' || l.ch == 'F' || l.ch == 'd' || l.ch == 'D' {
		// 	res.kind = .FLOAT_LIT
		// 	next_rune(l)
		// 	// можно дальше парсить f32/f64, если нужно
		// }

	case '/':
		// Проверяем, не комментарий ли это
		if l.offset + l.w < len(l.data) {
			next_ch, _ := utf8.decode_rune_in_string(l.data[l.offset:l.w+1])

			if next_ch == '/' {
				// Однострочный комментарий: //
				skip_line_comment(l)
				// После комментария снова пропускаем пробелы и продолжаем
				skip_whitespace(l)
				return get_token(l) // рекурсивно вызываем себя — следующий токен
			}

			if next_ch == '*' {
				// Многострочный комментарий: /* */
				if !skip_block_comment(l) {
					err.type = .Unterminated_Block_Comment
					res.kind = .INVALID
					return res, err
				}
				skip_whitespace(l)
				return get_token(l) // рекурсия
			}
		}

		// Если не комментарий — это просто деление
		res.kind = .DIV
		next_rune(l)
	}

	res.end_pos = l.pos
	res.lexeme = string(l.data[res.start_pos.offset:res.end_pos.offset])

	switch res.lexeme {
	case "pc":
		res.kind = .PC
	case "fn":
		res.kind = .FN
	case "struct":
		res.kind = .STRUCT
	case "enum":
		res.kind = .ENUM
	case "union":
		res.kind = .UNION
	case "map":
		res.kind = .MAP

	case "void":
		res.kind = .VOID

	case "int":
		res.kind = .INT
	case "i32":
		res.kind = .I32
	case "i64":
		res.kind = .I64
	case "i128":
		res.kind = .I128

	case "uint":
		res.kind = .UINT
	case "u8":
		res.kind = .U8
	case "u16":
		res.kind = .U16
	case "u32":
		res.kind = .U32
	case "u64":
		res.kind = .U64
	case "u128":
		res.kind = .U128

	// case "float":
	// 	res.kind = .FLOAT
	case "f32":
		res.kind = .F32
	case "f64":
		res.kind = .F64
	case "f128":
		res.kind = .F128

	case "string":
		res.kind = .STRING
	case "cstring":
		res.kind = .CSTRING
	case "rune":
		res.kind = .RUNE
	case "byte":
		res.kind = .BYTE

	case "if":
		res.kind = .IF
	case "do":
		res.kind = .DO
	case "else":
		res.kind = .ELSE
	case "for":
		res.kind = .FOR
	case "in":
		res.kind = .IN
	case "continue":
		res.kind = .CONTINUE
	case "break":
		res.kind = .BREAK
	case "switch":
		res.kind = .SWITCH
	case "case":
		res.kind = .CASE
	case "fallthrow":
		res.kind = .FALLTHROW
	case "module":
		res.kind = .MODULE
	case "import":
		res.kind = .IMPORT
	case "distinct":
		res.kind = .DISTINCT
	case "true", "false":
		res.kind = .BOOL_LIT
	

	}
	return
}

tokenize :: proc(data: string) -> (res: [dynamic]Token) {
	lex: Lexer;init(&lex, data)
	defer clean(&lex)

	for lex.offset < len(lex.data) {
		t, err := get_token(&lex)
		if err.type != .None do log.panic(err)
		
		append(&res, t)
	}

	return
}


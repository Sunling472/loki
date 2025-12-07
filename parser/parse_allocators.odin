package parser

import "../ast"
import "../tokenizer"

// parse_allocator_expr парсит выражение аллокатора: $arena(10*MB) или $heap или $malloc(flags...)
parse_allocator_expr :: proc(p: ^Parser) -> ^ast.Allocator_Expr {
	if p.curr_tok.kind != .Dollar {
		return nil
	}

	dollar_pos := p.curr_tok.pos
	advance_token(p)

	if p.curr_tok.kind != .Ident {
		error(p, p.curr_tok.pos, "expected allocator name after '$'")
		return nil
	}

	name := parse_ident(p)
	
	allocator := ast.new(ast.Allocator_Expr, dollar_pos, end_pos(p.prev_tok))
	allocator.dollar = dollar_pos
	allocator.name = name
	
	// Проверяем параметры: $arena(10*MB) или $malloc(mutex=true)
	if p.curr_tok.kind == .Open_Paren {
		expect_token(p, .Open_Paren)
		p.expr_level += 1
		
		// Может быть либо выражение (.Dynamic или размер), либо поля (flags)
		if p.curr_tok.kind == .Period {
			// .Dynamic или .Static
			advance_token(p)
			if p.curr_tok.kind == .Ident {
				kind_ident := parse_ident(p)
				allocator.kind = kind_ident
			} else {
				error(p, p.curr_tok.pos, "expected identifier after '.'")
			}
			
			// После .Dynamic может быть размер
			if p.curr_tok.kind == .Comma {
				advance_token(p)
				size := parse_expr(p, false)
				allocator.size = size
			}
		} else if p.curr_tok.kind != .Close_Paren {
			// Может быть размер
			first_expr := parse_expr(p, false)
			
			// Проверяем это ли размер или key=value
			if p.curr_tok.kind == .Eq {
				// Это не размер, это field=value, откатываем
				// TODO: нужен более правильный механизм
				allocator.size = first_expr
			} else if p.curr_tok.kind == .Comma {
				allocator.size = first_expr
				advance_token(p)
				// Возможно следующий элемент - это .Dynamic/.Static (kind)
				if p.curr_tok.kind == .Period {
					advance_token(p)
					if p.curr_tok.kind == .Ident {
						kind_ident := parse_ident(p)
						allocator.kind = kind_ident
					} else {
						error(p, p.curr_tok.pos, "expected identifier after '.' in allocator kind")
					}
					// Если после kind идут дополнительные флаги - парсим их
					if p.curr_tok.kind == .Comma {
						advance_token(p)
						flags := parse_allocator_flags(p)
						allocator.flags = flags
					}
				} else {
					// Теперь должны быть flags
					flags := parse_allocator_flags(p)
					allocator.flags = flags
				}
			} else {
				allocator.size = first_expr
			}
		}
		
		p.expr_level -= 1
		expect_token_after(p, .Close_Paren, "allocator expression")
		allocator.end = end_pos(p.prev_tok)
	}
	
	return allocator
}

// parse_allocator_flags парсит флаги аллокатора: mutex=true, track_leaks=true
parse_allocator_flags :: proc(p: ^Parser) -> []^ast.Field_Value {
	flags := make([dynamic]^ast.Field_Value, context.temp_allocator)
	
	for {
		if p.curr_tok.kind != .Ident {
			break
		}
		
		field_name := parse_ident(p)
		
		if p.curr_tok.kind != .Eq {
			error(p, p.curr_tok.pos, "expected '=' in allocator flag")
			break
		}
		
		eq_pos := p.curr_tok.pos
		advance_token(p)
		
		value := parse_expr(p, false)
		
		fv := ast.new(ast.Field_Value, field_name.pos, end_pos(p.prev_tok))
		fv.field = field_name
		fv.sep = eq_pos
		fv.value = value
		
		append(&flags, fv)
		
		if p.curr_tok.kind != .Comma {
			break
		}
		advance_token(p)
	}
	
	return flags[:]
}

// parse_allocator_contract парсит контракт памяти: in @heap или in @heap(10*MB)
parse_allocator_contract :: proc(p: ^Parser) -> ^ast.Allocator_Expr {
	if p.curr_tok.kind != .At {
		return nil
	}

	at_pos := p.curr_tok.pos
	advance_token(p)
	
	if p.curr_tok.kind != .Ident {
		error(p, p.curr_tok.pos, "expected contract name after '@'")
		return nil
	}
	
	name := parse_ident(p)
	
	contract := ast.new(ast.Allocator_Expr, at_pos, end_pos(p.prev_tok))
	contract.name = name
	
	// Проверяем размер: in @heap(10*MB)
	if p.curr_tok.kind == .Open_Paren {
		expect_token(p, .Open_Paren)
		p.expr_level += 1
		
		size := parse_expr(p, false)
		contract.size = size
		
		p.expr_level -= 1
		expect_token_after(p, .Close_Paren, "contract expression")
		contract.end = end_pos(p.prev_tok)
	}
	
	return contract
}

// parse_allocator_usage парсит использование аллокатора: in $arena(...) или in $arena(...)^
parse_allocator_usage :: proc(p: ^Parser) -> ^ast.Allocator_Usage {
	if p.curr_tok.kind != .In {
		return nil
	}
	
	in_pos := p.curr_tok.pos
	advance_token(p)
	
	// Парсим выражение аллокатора ($tmp, $arena(...), и т.д.)
	allocator := parse_allocator_expr(p)
	if allocator == nil {
		error(p, p.curr_tok.pos, "expected allocator expression after 'in'")
		return nil
	}
	
	transfer_ownership := false
	
	// Проверяем оператор передачи владения ^
	if p.curr_tok.kind == .Caret {
		transfer_ownership = true
		advance_token(p)
	}
	
	usage := ast.new(ast.Allocator_Usage, in_pos, end_pos(p.prev_tok))
	usage.in_pos = in_pos
	usage.allocator = allocator
	usage.transfer_ownership = transfer_ownership
	
	return usage
}

// extend_proc_type_with_allocator_contract расширяет процедурный тип с контрактом памяти
extend_proc_type_with_allocator_contract :: proc(p: ^Parser, pt: ^ast.Proc_Type) {
	// После результатов может быть контракт: -> int in @heap(10*MB)
	if p.curr_tok.kind == .In {
		in_pos := p.curr_tok.pos
		advance_token(p)
		
		// Парсим контракт
		contract := parse_allocator_contract(p)
		if contract != nil {
			// Сохраняем в расширении процедуры
			// TODO: добавить allocator_contract в Proc_Type
		} else {
			error(p, p.curr_tok.pos, "expected allocator contract after 'in'")
		}
	}
}

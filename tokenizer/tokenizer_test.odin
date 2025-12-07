package tokenizer

import "core:fmt"
import "core:log"
import "core:testing"

// Хелпер для быстрого тестирования токенов
tokenize_string :: proc(src: string) -> []Token {
	t: Tokenizer
	init(&t, src, "test.loki", nil)

	tokens := make([dynamic]Token)
	for {
		tok := scan(&t)
		append(&tokens, tok)
		if tok.kind == .EOF {
			break
		}
	}

	return tokens[:]
}

// Хелпер для проверки последовательности токенов
expect_tokens :: proc(
	t: ^testing.T,
	src: string,
	expected: []Token_Kind,
	loc := #caller_location,
) {
	tokens := tokenize_string(src)
	defer delete(tokens)

	if len(tokens) != len(expected) + 1 { 	// +1 для EOF
		testing.expect_assert_message(
			t,
			fmt.aprintf("Expected %d tokens (+ EOF), got %d", len(expected), len(tokens) - 1),
			loc,
		)
		fmt.println("Got tokens:")
		for tok, i in tokens {
			fmt.printf("  [%d] %v (%q)\n", i, tok.kind, tok.text)
		}
		return
	}

	for kind, i in expected {
		if tokens[i].kind != kind {
			testing.expectf(
				t,
				false,
				"Token %d: expected %v, got %v (%q)",
				i,
				kind,
				tokens[i].kind,
				tokens[i].text,
				loc = loc,
			)
		}
	}
}

// ============================================
// Тесты новых токенов Loki
// ============================================

@(test)
test_caret_token :: proc(t: ^testing.T) {
	// ^ теперь Caret, не Pointer
	expect_tokens(t, "^", {.Caret})
}

@(test)
test_left_arrow_token :: proc(t: ^testing.T) {
	// <- для return
	expect_tokens(t, "<-", {.Left_Arrow})
	expect_tokens(t, "<- 42", {.Left_Arrow, .Integer})
}

@(test)
test_fat_arrow_token :: proc(t: ^testing.T) {
	// => для method binding
	expect_tokens(t, "=>", {.Fat_Arrow})
	expect_tokens(t, "=> Interface", {.Fat_Arrow, .Ident})
}

@(test)
test_pc_keyword :: proc(t: ^testing.T) {
	// pc вместо proc
	expect_tokens(t, "pc", {.Pc})
	expect_tokens(t, "pc()", {.Pc, .Open_Paren, .Close_Paren})
}

@(test)
test_dollar_token :: proc(t: ^testing.T) {
	// $ для аллокаторов
	expect_tokens(t, "$", {.Dollar})
	expect_tokens(t, "$arena", {.Dollar, .Ident})
	expect_tokens(t, "$tmp", {.Dollar, .Ident})
}

// ============================================
// Тесты реальных конструкций Loki
// ============================================

@(test)
test_procedure_declaration :: proc(t: ^testing.T) {
	src := "add :: pc (a: int, b: int) -> int"

	expect_tokens(
		t,
		src,
		{
			.Ident, // add
			.Colon, // :
			.Colon, // :
			.Pc, // pc
			.Open_Paren, // (
			.Ident, // a
			.Colon, // :
			.Ident, // int
			.Comma, // ,
			.Ident, // b
			.Colon, // :
			.Ident, // int
			.Close_Paren, // )
			.Arrow_Right, // ->
			.Ident, // int
		},
	)
}

@(test)
test_allocator_contract :: proc(t: ^testing.T) {
	src := "process :: pc () -> void in $heap(10*Mb)"

	expect_tokens(
		t,
		src,
		{
			.Ident, // process
			.Colon,
			.Colon,
			.Pc, // pc
			.Open_Paren,
			.Close_Paren,
			.Arrow_Right, // ->
			.Ident, // void
			.In, // in
			.Dollar, // $
			.Ident, // heap
			.Open_Paren, // (
			.Integer, // 10
			.Mul, // *
			.Ident, // Mb
			.Close_Paren, // )
		},
	)
}

@(test)
test_named_allocator :: proc(t: ^testing.T) {
	src := "$tmp :: $arena(.Dynamic, 10*Mb)"

	expect_tokens(
		t,
		src,
		{
			.Dollar, // $
			.Ident, // tmp
			.Colon,
			.Colon,
			.Dollar, // $
			.Ident, // arena
			.Open_Paren,
			.Period, // .
			.Ident, // Dynamic
			.Comma,
			.Integer, // 10
			.Mul,
			.Ident, // Mb
			.Close_Paren,
		},
	)
}

@(test)
test_allocator_usage_simple :: proc(t: ^testing.T) {
	src := "process() in $tmp"

	expect_tokens(
		t,
		src,
		{
			.Ident, // process
			.Open_Paren,
			.Close_Paren,
			.In, // in
			.Dollar, // $
			.Ident, // tmp
		},
	)
}

@(test)
test_allocator_usage_with_ownership :: proc(t: ^testing.T) {
	src := "process() in $arena(10*Mb)^"

	expect_tokens(
		t,
		src,
		{
			.Ident, // process
			.Open_Paren,
			.Close_Paren,
			.In, // in
			.Dollar, // $
			.Ident, // arena
			.Open_Paren,
			.Integer, // 10
			.Mul,
			.Ident, // Mb
			.Close_Paren,
			.Caret, // ^ (ownership transfer)
		},
	)
}

@(test)
test_allocator_with_flags :: proc(t: ^testing.T) {
	src := "$malloc(10*Mb, mutex=true)"

	expect_tokens(
		t,
		src,
		{
			.Dollar, // $
			.Ident, // malloc
			.Open_Paren,
			.Integer, // 10
			.Mul,
			.Ident, // Mb
			.Comma,
			.Ident, // mutex
			.Eq, // =
			.Ident, // true
			.Close_Paren,
		},
	)
}

@(test)
test_return_with_left_arrow :: proc(t: ^testing.T) {
	src := "<- 42"

	expect_tokens(
		t,
		src,
		{
			.Left_Arrow, // <-
			.Integer, // 42
		},
	)
}

@(test)
test_method_binding :: proc(t: ^testing.T) {
	src := "p: Person => Interface => {"

	expect_tokens(
		t,
		src,
		{
			.Ident, // p
			.Colon, // :
			.Ident, // Person
			.Fat_Arrow, // =>
			.Ident, // Interface
			.Fat_Arrow, // =>
			.Open_Brace, // {
		},
	)
}

// ============================================
// Тесты комплексных примеров
// ============================================

@(test)
test_complete_example_1 :: proc(t: ^testing.T) {
	src := `
main :: pc () {
    $tmp :: $arena(.Dynamic, 10*Mb)
    res := example() in $tmp
}
`

	tokens := tokenize_string(src)
	defer delete(tokens)

	// Просто проверяем что нет ошибок и есть нужные токены
	has_pc := false
	has_dollar := false
	has_in := false

	for tok in tokens {
		if tok.kind == .Pc {has_pc = true}
		if tok.kind == .Dollar {has_dollar = true}
		if tok.kind == .In {has_in = true}
	}

	testing.expect(t, has_pc, "Should have 'pc' keyword")
	testing.expect(t, has_dollar, "Should have '$' token")
	testing.expect(t, has_in, "Should have 'in' keyword")
}

@(test)
test_complete_example_2 :: proc(t: ^testing.T) {
	src := `
example :: pc () -> int in $heap {
    <- 10
}
`

	tokens := tokenize_string(src)
	defer delete(tokens)

	has_left_arrow := false
	has_in := false
	has_dollar := false

	for tok in tokens {
		if tok.kind == .Left_Arrow {has_left_arrow = true}
		if tok.kind == .In {has_in = true}
		if tok.kind == .Dollar {has_dollar = true}
	}

	testing.expect(t, has_left_arrow, "Should have '<-' token")
	testing.expect(t, has_in, "Should have 'in' keyword")
	testing.expect(t, has_dollar, "Should have '$' token")
}

// ============================================
// Тесты что старые токены НЕ работают
// ============================================

@(test)
test_no_proc_keyword :: proc(t: ^testing.T) {
	// "proc" теперь должен быть обычным идентификатором
	src := "proc"
	tokens := tokenize_string(src)
	defer delete(tokens)

	// Первый токен должен быть Ident, а не Proc
	testing.expect(t, tokens[0].kind == .Ident, "proc should be an identifier, not a keyword")
}

// ============================================
// Граничные случаи
// ============================================

@(test)
test_caret_not_confused_with_xor :: proc(t: ^testing.T) {
	// ^ это Caret, ~ это Xor
	expect_tokens(t, "^", {.Caret})
	expect_tokens(t, "~", {.Xor})
}

@(test)
test_left_arrow_vs_lt :: proc(t: ^testing.T) {
	// <- это Left_Arrow
	// < это Lt
	// <-a должно быть Left_Arrow + Ident
	expect_tokens(t, "<-", {.Left_Arrow})
	expect_tokens(t, "<", {.Lt})
	expect_tokens(t, "<-a", {.Left_Arrow, .Ident})
}

@(test)
test_fat_arrow_vs_eq_and_gt :: proc(t: ^testing.T) {
	// => это Fat_Arrow
	// = > это Eq + Gt
	expect_tokens(t, "=>", {.Fat_Arrow})
	expect_tokens(t, "= >", {.Eq, .Gt})
}

@(test)
test_multiple_dollars :: proc(t: ^testing.T) {
	src := "$tmp :: $arena"
	expect_tokens(
		t,
		src,
		{
			.Dollar,
			.Ident, // tmp
			.Colon,
			.Colon,
			.Dollar,
			.Ident, // arena
		},
	)
}

@(test)
test_ownership_transfer_syntax :: proc(t: ^testing.T) {
	// in $tmp^
	src := "in $tmp^"
	expect_tokens(
		t,
		src,
		{
			.In,
			.Dollar,
			.Ident, // tmp
			.Caret, // ^
		},
	)
}

// ============================================
// Тесты позиций и текста токенов
// ============================================

@(test)
test_token_positions :: proc(t: ^testing.T) {
	src := "$tmp :: $arena"
	tokens := tokenize_string(src)
	defer delete(tokens)

	// Проверяем что позиции корректны
	testing.expect(t, tokens[0].pos.offset == 0, "First token should start at 0")
	testing.expect(t, tokens[0].text == "$", "First token text should be '$'")
	testing.expect(t, tokens[1].text == "tmp", "Second token text should be 'tmp'")
}

@(test)
test_token_text :: proc(t: ^testing.T) {
	src := "pc <- =>"
	tokens := tokenize_string(src)
	defer delete(tokens)

	testing.expect(t, tokens[0].text == "pc", "pc text")
	testing.expect(t, tokens[1].text == "<-", "<- text")
	testing.expect(t, tokens[2].text == "=>", "=> text")
}

package loki

import "core:testing"
import "core:fmt"
import "core:os"
import "tokenizer"
import "core:mem"

main :: proc() {
	// Настраиваем окружение
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
	defer mem.tracking_allocator_destroy(&track)
	
	// Запускаем тесты
	t := testing.T{}
	
	fmt.println("=== Running Tokenizer Tests ===\n")
	
	// Новые токены
	fmt.println("Testing new tokens...")
	tokenizer.test_caret_token(&t)
	tokenizer.test_left_arrow_token(&t)
	tokenizer.test_fat_arrow_token(&t)
	tokenizer.test_pc_keyword(&t)
	tokenizer.test_dollar_token(&t)
	
	// Конструкции Loki
	fmt.println("\nTesting Loki constructs...")
	tokenizer.test_procedure_declaration(&t)
	tokenizer.test_allocator_contract(&t)
	tokenizer.test_named_allocator(&t)
	tokenizer.test_allocator_usage_simple(&t)
	tokenizer.test_allocator_usage_with_ownership(&t)
	tokenizer.test_allocator_with_flags(&t)
	tokenizer.test_return_with_left_arrow(&t)
	tokenizer.test_method_binding(&t)
	
	// Комплексные примеры
	fmt.println("\nTesting complete examples...")
	tokenizer.test_complete_example_1(&t)
	tokenizer.test_complete_example_2(&t)
	
	// Граничные случаи
	fmt.println("\nTesting edge cases...")
	tokenizer.test_no_proc_keyword(&t)
	tokenizer.test_caret_not_confused_with_xor(&t)
	tokenizer.test_left_arrow_vs_lt(&t)
	tokenizer.test_fat_arrow_vs_eq_and_gt(&t)
	tokenizer.test_multiple_dollars(&t)
	tokenizer.test_ownership_transfer_syntax(&t)
	
	// Позиции и текст
	fmt.println("\nTesting positions and text...")
	tokenizer.test_token_positions(&t)
	tokenizer.test_token_text(&t)
	
	// Результаты
	fmt.println("\n=== Test Results ===")
	fmt.printf("Failed: %d\n", t.error_count)
	
	if t.error_count > 0 {
		fmt.println("\n❌ Some tests failed!")
		os.exit(1)
	} else {
		fmt.println("\n✅ All tests passed!")
	}
	
	// Проверка утечек памяти
	if len(track.allocation_map) > 0 {
		fmt.println("\n⚠️  Memory leaks detected:")
		for _, entry in track.allocation_map {
			fmt.printf("  %v leaked %d bytes\n", entry.location, entry.size)
		}
	}
}

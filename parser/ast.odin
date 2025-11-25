package parser

Namespace :: map[string]Node

Package :: struct {
	name:      string,
	namespace: Namespace,
	ast:       [dynamic]Node,
}

Node :: union {}

DeclKind :: enum {
	Module,
	Import,
	Var,
	Alias,
	Interface,
}

Decl :: struct {
	ident:   string,
	kind:    DeclKind,
	type:    ^Node,
	literal: ^Node,
}

DeclModule :: struct {
	ident: string,
}

DeclImport :: struct {
	ident: Maybe(string),
	path:  string,
}

DeclVar :: struct {
	ident:   string,
	type:    Node,
	literal: Literal,
}

DeclAlias :: struct {
	ident:   string,
	type:    Node,
	literal: Literal,
}

DeclInterface :: struct {
	ident:   string,
	methods: []ProcType,
}

LiteralKind :: union {
	IntLit,
	FloatLit,
	StringLit,
	BoolLit,
	StructLit,
	EnumLit,
	UnionLit,
	ProcLit,
}

Literal :: struct {
	kind: LiteralKind,
}

IntLit :: int
FloatLit :: f32
StringLit :: string
BoolLit :: bool

StructLit :: struct {
	fields: []StructField,
}

EnumLit :: struct {
	fields: []EnumField,
}

UnionLit :: struct {
	tags: []UnionTag,
}

ProcLit :: struct {
	params: []ProcParam,
	ret_ty: Node,
	body:   []Node,
}

StructField :: struct {
	ident: string,
	type:  Type,
}

EnumField :: struct {
	ident: string,
	value: int,
}

UnionTag :: struct {
	ident: string,
	value: Type,
}

ProcParam :: struct {
	ident:   Maybe(string),
	type:    Type,
	literal: Literal,
}

Type :: struct {
	kind: TypeKind,
}

TypeKind :: union {
	TypeBasic,
	EnumType,
	UnionType,
	StructType,
	ProcType,
	ArrayType,
	SliceType,
	MapType,
}

TypeBasicKind :: enum {
	Int,
	I32,
	I64,
	I128,
	Uint,
	U8,
	U16,
	U32,
	U64,
	U128,
	F32,
	F64,
	F128,
	String,
	CString,
	Rune,
	Byte,
	Bool,
	Void,

	// Struct,
	// Proc,
	// Fn,
	// Enum,
	// Union,
}

DefaultValue :: union {
	int,
	i32,
	i64,
	i128,
	f32,
	f64,
	string,
	cstring,
	bool,
	rune,
	byte,
}

TypeBasic :: struct {
	ident:   Maybe(string),
	kind:    TypeBasicKind,
	default: DefaultValue,
}

ArrayType :: struct {
	size: Literal,
	type: ^Type,
}

SliceType :: struct {
	type: ^Type,
}

MapType :: struct {
	key:   ^Type,
	value: ^Type,
}

StructType :: struct {
	gen_params: []Node,
	fields:     []StructField,
}

EnumType :: struct {
	values: []EnumField,
}

UnionType :: struct {
	gen_params: []Node,
	tags:       []UnionTag,
}

ProcType :: struct {
	gen_params: []Node,
	params:     []ProcParam,
	ret_ty:     ^Type,
}


package parser

Namespace :: map[string]Node

Package :: struct {
	name:      string,
	namespace: Namespace,
	ast:       [dynamic]Node,
}

Node :: union {
	^Stmt,
	^Expr,
	^Type,
}

Stmt :: union {
	^Decl,
}

Expr :: union {
	^Literal,
}

Type :: union {
	^TypeBasic,
	^TypeStruct,
	^TypeEnum,
	^TypeUnion,
	^TypeProc
}

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
	type:    ^Type,
	literal: ^Expr,
}

DeclModule :: struct {
	ident: string
}

DeclImport :: struct {
	ident: Maybe(string),
	path: string
}

DeclVar :: struct {
	ident: string,
	type: Type,
	literal: Literal
}

DeclAlias :: struct {
	ident: string,
	type: Type,
	literal: Literal
}

DeclInterface :: struct {
	ident: string,
	methods: []TypeProc
}

LiteralKind :: enum {
	Int,
	Float,
	String,
	Struct,
	Proc,
	Fn,
	Type,
}

Literal :: struct {
	kind:  LiteralKind,
	type:  ^Type,
	nodes: []Node,
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
	f32,
	string,
	bool,
	rune,
	byte,
}

TypeBasic :: struct {
	ident:   Maybe(string),
	kind:    TypeBasicKind,
	default: DefaultValue,
}

TypeStruct :: struct {
	ident: Maybe(string),
	gen_params: []Node,
	fields: []Node
}

TypeEnum :: struct {
	ident: Maybe(string),
	values: []Node,
}

TypeUnion :: struct {
	ident: Maybe(string),
	gen_params: []Node,
	tags: []Node,
}

TypeProc :: struct {
	ident: Maybe(string),
	gen_params: []Node,
	params: []ProcParam,
	ret_ty: Type,
}

ProcParam :: struct {
	ident: Maybe(string),
	type: Type,
	literal: ^Literal
}

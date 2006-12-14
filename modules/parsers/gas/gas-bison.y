/*
 * GAS-compatible bison parser
 *
 *  Copyright (C) 2005  Peter Johnson
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the author nor the names of other contributors
 *    may be used to endorse or promote products derived from this
 *    software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND OTHER CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR OTHER CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */
%{
#include <util.h>
RCSID("$Id$");

#define YASM_LIB_INTERNAL
#define YASM_EXPR_INTERNAL
#include <libyasm.h>

#ifdef STDC_HEADERS
# include <math.h>
#endif

#include "modules/parsers/gas/gas-parser.h"
#include "modules/parsers/gas/gas-defs.h"

static void define_label(yasm_parser_gas *parser_gas, char *name, int local);
static void define_lcomm(yasm_parser_gas *parser_gas, /*@only@*/ char *name,
			 yasm_expr *size, /*@null@*/ yasm_expr *align);
static yasm_section *gas_get_section
    (yasm_parser_gas *parser_gas, /*@only@*/ char *name, /*@null@*/ char *flags,
     /*@null@*/ char *type, /*@null@*/ yasm_valparamhead *objext_valparams,
     int builtin);
static void gas_switch_section
    (yasm_parser_gas *parser_gas, /*@only@*/ char *name, /*@null@*/ char *flags,
     /*@null@*/ char *type, /*@null@*/ yasm_valparamhead *objext_valparams,
     int builtin);
static yasm_bytecode *gas_parser_align
    (yasm_parser_gas *parser_gas, yasm_section *sect, yasm_expr *boundval,
     /*@null@*/ yasm_expr *fillval, /*@null@*/ yasm_expr *maxskipval,
     int power2);
static yasm_bytecode *gas_parser_dir_align(yasm_parser_gas *parser_gas,
					   yasm_valparamhead *valparams,
					   int power2);
static yasm_bytecode *gas_parser_dir_fill
    (yasm_parser_gas *parser_gas, /*@only@*/ yasm_expr *repeat,
     /*@only@*/ /*@null@*/ yasm_expr *size,
     /*@only@*/ /*@null@*/ yasm_expr *value);
static void gas_parser_directive
    (yasm_parser_gas *parser_gas, const char *name,
     yasm_valparamhead *valparams,
     /*@null@*/ yasm_valparamhead *objext_valparams);

#define gas_parser_error(s)	\
    yasm_error_set(YASM_ERROR_PARSE, "%s", s)
#define YYPARSE_PARAM	parser_gas_arg
#define YYLEX_PARAM	parser_gas_arg
#define parser_gas	((yasm_parser_gas *)parser_gas_arg)
#define gas_parser_debug   (parser_gas->debug)

/*@-usedef -nullassign -memtrans -usereleased -compdef -mustfree@*/
%}

%pure_parser

%union {
    unsigned int int_info;
    char *str_val;
    yasm_intnum *intn;
    yasm_floatnum *flt;
    yasm_symrec *sym;
    unsigned long arch_data[4];
    yasm_effaddr *ea;
    yasm_expr *exp;
    yasm_bytecode *bc;
    yasm_valparamhead valparams;
    yasm_datavalhead datavals;
    yasm_dataval *dv;
    struct {
	yasm_insn_operands operands;
	int num_operands;
    } insn_operands;
    yasm_insn_operand *insn_operand;
    struct {
	char *contents;
	size_t len;
    } str;
}

%token <intn> INTNUM
%token <flt> FLTNUM
%token <str> STRING
%token <int_info> SIZE_OVERRIDE
%token <int_info> DECLARE_DATA
%token <int_info> RESERVE_SPACE
%token <arch_data> INSN PREFIX REG REGGROUP SEGREG TARGETMOD
%token LEFT_OP RIGHT_OP
%token <str_val> ID DIR_ID LABEL
%token LINE
%token DIR_2BYTE DIR_4BYTE DIR_ALIGN DIR_ASCII DIR_ASCIZ DIR_BALIGN
%token DIR_BSS DIR_BYTE DIR_COMM DIR_DATA DIR_DOUBLE DIR_ENDR DIR_EXTERN
%token DIR_EQU DIR_FILE DIR_FILL DIR_FLOAT DIR_GLOBAL DIR_IDENT DIR_INT
%token DIR_LINE DIR_LOC DIR_LOCAL DIR_LCOMM DIR_OCTA DIR_ORG DIR_P2ALIGN
%token DIR_REPT DIR_SECTION DIR_SHORT DIR_SIZE DIR_SKIP DIR_SLEB128 DIR_STRING
%token DIR_TEXT DIR_TFLOAT DIR_TYPE DIR_QUAD DIR_ULEB128 DIR_VALUE DIR_WEAK
%token DIR_WORD DIR_ZERO

%type <bc> lineexp instr

%type <str_val> expr_id label_id
%type <ea> memaddr
%type <exp> expr regmemexpr
%type <sym> explabel
%type <valparams> dirvals dirvals2 dirstrvals dirstrvals2
%type <datavals> strvals datavals strvals2 datavals2
%type <insn_operands> operands
%type <insn_operand> operand

%left '-' '+'
%left '|' '&' '^' '!'
%left '*' '/' '%' LEFT_OP RIGHT_OP
%nonassoc UNARYOP

%%
input: /* empty */
    | input line    {
	yasm_errwarn_propagate(parser_gas->errwarns, cur_line);
	if (parser_gas->save_input)
	    yasm_linemap_add_source(parser_gas->linemap,
		parser_gas->prev_bc,
		(char *)parser_gas->save_line[parser_gas->save_last ^ 1]);
	yasm_linemap_goto_next(parser_gas->linemap);
	parser_gas->dir_line++;	/* keep track for .line followed by .file */
    }
;

line: '\n'
    | linebcs '\n'
    | error '\n'	{
	yasm_error_set(YASM_ERROR_SYNTAX,
		       N_("label or instruction expected at start of line"));
	yyerrok;
    }
;

linebcs: linebc
    | linebc ';' linebcs
;

linebc: lineexp {
	parser_gas->temp_bc =
	    yasm_section_bcs_append(parser_gas->cur_section, $1);
	if (parser_gas->temp_bc)
	    parser_gas->prev_bc = parser_gas->temp_bc;
    }
;

lineexp: instr
    | label_id ':'		{
	$$ = (yasm_bytecode *)NULL;
	define_label(parser_gas, $1, 0);
    }
    | label_id ':' instr	{
	$$ = $3;
	define_label(parser_gas, $1, 0);
    }
    | LABEL		{
	$$ = (yasm_bytecode *)NULL;
	define_label(parser_gas, $1, 0);
    }
    | LABEL instr	{
	$$ = $2;
	define_label(parser_gas, $1, 0);
    }
    /* Line directive */
    | DIR_LINE INTNUM {
	$$ = (yasm_bytecode *)NULL;
	if (yasm_intnum_sign($2) < 0)
	    yasm_error_set(YASM_ERROR_SYNTAX, N_("line number is negative"));
	else {
	    parser_gas->dir_line = yasm_intnum_get_uint($2);
	    yasm_intnum_destroy($2);
 
	    if (parser_gas->dir_fileline == 3) {
		/* Have both file and line */
		yasm_linemap_set(parser_gas->linemap, NULL,
				 parser_gas->dir_line, 1);
	    } else if (parser_gas->dir_fileline == 1) {
		/* Had previous file directive only */
		parser_gas->dir_fileline = 3;
		yasm_linemap_set(parser_gas->linemap, parser_gas->dir_file,
				 parser_gas->dir_line, 1);
	    } else {
		/* Didn't see file yet */
		parser_gas->dir_fileline = 2;
	    }
	}
    }
    /* Macro directives */
    | DIR_REPT expr {
	yasm_intnum *intn = yasm_expr_get_intnum(&$2, 0);

	$$ = (yasm_bytecode *)NULL;
	if (!intn) {
	    yasm_error_set(YASM_ERROR_NOT_ABSOLUTE,
			   N_("rept expression not absolute"));
	} else if (yasm_intnum_sign(intn) < 0) {
	    yasm_error_set(YASM_ERROR_VALUE,
			   N_("rept expression is negative"));
	} else {
	    gas_rept *rept = yasm_xmalloc(sizeof(gas_rept));
	    STAILQ_INIT(&rept->lines);
	    rept->startline = cur_line;
	    rept->numrept = yasm_intnum_get_uint(intn);
	    rept->numdone = 0;
	    rept->line = NULL;
	    rept->linepos = 0;
	    rept->ended = 0;
	    rept->oldbuf = NULL;
	    rept->oldbuflen = 0;
	    rept->oldbufpos = 0;
	    parser_gas->rept = rept;
	}
    }
    | DIR_ENDR {
	$$ = (yasm_bytecode *)NULL;
	/* Shouldn't ever get here unless we didn't get a DIR_REPT first */
	yasm_error_set(YASM_ERROR_SYNTAX, N_("endr without matching rept"));
    }
    /* Alignment directives */
    | DIR_ALIGN dirvals2 {
	/* FIXME: Whether this is power-of-two or not depends on arch and
	 * objfmt.
	 */
	$$ = gas_parser_dir_align(parser_gas, &$2, 0);
    }
    | DIR_P2ALIGN dirvals2 {
	$$ = gas_parser_dir_align(parser_gas, &$2, 1);
    }
    | DIR_BALIGN dirvals2 {
	$$ = gas_parser_dir_align(parser_gas, &$2, 0);
    }
    | DIR_ORG INTNUM {
	/* TODO: support expr instead of intnum */
	$$ = yasm_bc_create_org(yasm_intnum_get_uint($2), cur_line);
    }
    /* Data visibility directives */
    | DIR_LOCAL label_id {
	yasm_symtab_declare(parser_gas->symtab, $2, YASM_SYM_DLOCAL, cur_line);
	yasm_xfree($2);
	$$ = NULL;
    }
    | DIR_GLOBAL label_id {
	yasm_objfmt_global_declare(parser_gas->objfmt, $2, NULL, cur_line);
	yasm_xfree($2);
	$$ = NULL;
    }
    | DIR_COMM label_id ',' expr {
	/* If already explicitly declared local, treat like LCOMM */
	/*@null@*/ /*@dependent@*/ yasm_symrec *sym =
	    yasm_symtab_get(parser_gas->symtab, $2);
	if (sym && yasm_symrec_get_visibility(sym) == YASM_SYM_DLOCAL) {
	    define_lcomm(parser_gas, $2, $4, NULL);
	} else {
	    yasm_objfmt_common_declare(parser_gas->objfmt, $2, $4, NULL,
				       cur_line);
	    yasm_xfree($2);
	}
	$$ = NULL;
    }
    | DIR_COMM label_id ',' expr ',' expr {
	/* If already explicitly declared local, treat like LCOMM */
	/*@null@*/ /*@dependent@*/ yasm_symrec *sym =
	    yasm_symtab_get(parser_gas->symtab, $2);
	if (sym && yasm_symrec_get_visibility(sym)) {
	    define_lcomm(parser_gas, $2, $4, $6);
	} else {
	    /* Give third parameter as objext valparam for use as alignment */
	    yasm_valparamhead vps;
	    yasm_valparam *vp;

	    yasm_vps_initialize(&vps);
	    vp = yasm_vp_create(NULL, $6);
	    yasm_vps_append(&vps, vp);

	    yasm_objfmt_common_declare(parser_gas->objfmt, $2, $4, &vps,
				       cur_line);

	    yasm_vps_delete(&vps);
	    yasm_xfree($2);
	}
	$$ = NULL;
    }
    | DIR_EXTERN label_id {
	/* Go ahead and do it, even though all undef become extern */
	yasm_objfmt_extern_declare(parser_gas->objfmt, $2, NULL, cur_line);
	yasm_xfree($2);
	$$ = NULL;
    }
    | DIR_WEAK label_id {
	yasm_valparamhead vps;
	yasm_valparam *vp;

	yasm_vps_initialize(&vps);
	vp = yasm_vp_create($2, NULL);
	yasm_vps_append(&vps, vp);

	yasm_objfmt_directive(parser_gas->objfmt, "weak", &vps, NULL,
			      cur_line);

	yasm_vps_delete(&vps);
	$$ = NULL;
    }
    | DIR_LCOMM label_id ',' expr {
	define_lcomm(parser_gas, $2, $4, NULL);
	$$ = NULL;
    }
    | DIR_LCOMM label_id ',' expr ',' expr {
	define_lcomm(parser_gas, $2, $4, $6);
	$$ = NULL;
    }
    /* Integer data definition directives */
    | DIR_ASCII strvals {
	$$ = yasm_bc_create_data(&$2, 1, 0, parser_gas->arch, cur_line);
    }
    | DIR_ASCIZ strvals {
	$$ = yasm_bc_create_data(&$2, 1, 1, parser_gas->arch, cur_line);
    }
    | DIR_BYTE datavals {
	$$ = yasm_bc_create_data(&$2, 1, 0, parser_gas->arch, cur_line);
    }
    | DIR_SHORT datavals {
	/* TODO: This should depend on arch */
	$$ = yasm_bc_create_data(&$2, 2, 0, parser_gas->arch, cur_line);
    }
    | DIR_WORD datavals {
	$$ = yasm_bc_create_data(&$2, yasm_arch_wordsize(parser_gas->arch)/8, 0,
				 parser_gas->arch, cur_line);
    }
    | DIR_INT datavals {
	/* TODO: This should depend on arch */
	$$ = yasm_bc_create_data(&$2, 4, 0, parser_gas->arch, cur_line);
    }
    | DIR_VALUE datavals {
	/* XXX: At least on x86, this is two bytes */
	$$ = yasm_bc_create_data(&$2, 2, 0, parser_gas->arch, cur_line);
    }
    | DIR_2BYTE datavals {
	$$ = yasm_bc_create_data(&$2, 2, 0, parser_gas->arch, cur_line);
    }
    | DIR_4BYTE datavals {
	$$ = yasm_bc_create_data(&$2, 4, 0, parser_gas->arch, cur_line);
    }
    | DIR_QUAD datavals {
	$$ = yasm_bc_create_data(&$2, 8, 0, parser_gas->arch, cur_line);
    }
    | DIR_OCTA datavals {
	$$ = yasm_bc_create_data(&$2, 16, 0, parser_gas->arch, cur_line);
    }
    | DIR_ZERO expr {
	yasm_datavalhead dvs;

	yasm_dvs_initialize(&dvs);
	yasm_dvs_append(&dvs, yasm_dv_create_expr(
	    p_expr_new_ident(yasm_expr_int(yasm_intnum_create_uint(0)))));
	$$ = yasm_bc_create_data(&dvs, 1, 0, parser_gas->arch, cur_line);

	yasm_bc_set_multiple($$, $2);
    }
    | DIR_SLEB128 datavals {
	$$ = yasm_bc_create_leb128(&$2, 1, cur_line);
    }
    | DIR_ULEB128 datavals {
	$$ = yasm_bc_create_leb128(&$2, 0, cur_line);
    }
    /* Floating point data definition directives */
    | DIR_FLOAT datavals {
	$$ = yasm_bc_create_data(&$2, 4, 0, parser_gas->arch, cur_line);
    }
    | DIR_DOUBLE datavals {
	$$ = yasm_bc_create_data(&$2, 8, 0, parser_gas->arch, cur_line);
    }
    | DIR_TFLOAT datavals {
	$$ = yasm_bc_create_data(&$2, 10, 0, parser_gas->arch, cur_line);
    }
    /* Empty space / fill data definition directives */
    | DIR_SKIP expr {
	$$ = yasm_bc_create_reserve($2, 1, cur_line);
    }
    | DIR_SKIP expr ',' expr {
	yasm_datavalhead dvs;

	yasm_dvs_initialize(&dvs);
	yasm_dvs_append(&dvs, yasm_dv_create_expr($4));
	$$ = yasm_bc_create_data(&dvs, 1, 0, parser_gas->arch, cur_line);

	yasm_bc_set_multiple($$, $2);
    }
    /* fill data definition directive */
    | DIR_FILL expr {
	$$ = gas_parser_dir_fill(parser_gas, $2, NULL, NULL);
    }
    | DIR_FILL expr ',' expr {
	$$ = gas_parser_dir_fill(parser_gas, $2, $4, NULL);
    }
    | DIR_FILL expr ',' expr ',' expr {
	$$ = gas_parser_dir_fill(parser_gas, $2, $4, $6);
    }
    /* Section directives */
    | DIR_TEXT {
	gas_switch_section(parser_gas, yasm__xstrdup(".text"), NULL, NULL,
			   NULL, 1);
	$$ = NULL;
    }
    | DIR_DATA {
	gas_switch_section(parser_gas, yasm__xstrdup(".data"), NULL, NULL,
			   NULL, 1);
	$$ = NULL;
    }
    | DIR_BSS {
	gas_switch_section(parser_gas, yasm__xstrdup(".bss"), NULL, NULL, NULL,
			   1);
	$$ = NULL;
    }
    | DIR_SECTION label_id {
	gas_switch_section(parser_gas, $2, NULL, NULL, NULL, 0);
	$$ = NULL;
    }
    | DIR_SECTION label_id ',' STRING {
	gas_switch_section(parser_gas, $2, $4.contents, NULL, NULL, 0);
	yasm_xfree($4.contents);
	$$ = NULL;
    }
    | DIR_SECTION label_id ',' STRING ',' '@' label_id {
	gas_switch_section(parser_gas, $2, $4.contents, $7, NULL, 0);
	yasm_xfree($4.contents);
	$$ = NULL;
    }
    | DIR_SECTION label_id ',' STRING ',' '@' label_id ',' dirvals {
	gas_switch_section(parser_gas, $2, $4.contents, $7, &$9, 0);
	yasm_xfree($4.contents);
	$$ = NULL;
    }
    /* Other directives */
    | DIR_IDENT dirstrvals {
	yasm_objfmt_directive(parser_gas->objfmt, "ident", &$2, NULL,
			      cur_line);
	yasm_vps_delete(&$2);
	$$ = NULL;
    }
    | DIR_FILE INTNUM STRING {
	yasm_valparamhead vps;
	yasm_valparam *vp;

	yasm_vps_initialize(&vps);
	vp = yasm_vp_create(NULL, p_expr_new_ident(yasm_expr_int($2)));
	yasm_vps_append(&vps, vp);
	vp = yasm_vp_create($3.contents, NULL);
	yasm_vps_append(&vps, vp);

	yasm_dbgfmt_directive(parser_gas->dbgfmt, "file",
			      parser_gas->cur_section, &vps, cur_line);

	yasm_vps_delete(&vps);
	$$ = NULL;
    }
    | DIR_FILE STRING {
	yasm_valparamhead vps;
	yasm_valparam *vp;

	/* This form also sets the assembler's internal line number */
	if (parser_gas->dir_fileline == 3) {
	    /* Have both file and line */
	    const char *old_fn;
	    unsigned long old_line;

	    yasm_linemap_lookup(parser_gas->linemap, cur_line, &old_fn,
				&old_line);
	    yasm_linemap_set(parser_gas->linemap, $2.contents,
			     old_line, 1);
	} else if (parser_gas->dir_fileline == 2) {
	    /* Had previous line directive only */
	    parser_gas->dir_fileline = 3;
	    yasm_linemap_set(parser_gas->linemap, $2.contents,
			     parser_gas->dir_line, 1);
	} else {
	    /* Didn't see line yet, save file */
	    parser_gas->dir_fileline = 1;
	    if (parser_gas->dir_file)
		yasm_xfree(parser_gas->dir_file);
	    parser_gas->dir_file = yasm__xstrdup($2.contents);
	}

	/* Pass change along to debug format */
	yasm_vps_initialize(&vps);
	vp = yasm_vp_create($2.contents, NULL);
	yasm_vps_append(&vps, vp);

	yasm_dbgfmt_directive(parser_gas->dbgfmt, "file",
			      parser_gas->cur_section, &vps, cur_line);

	yasm_vps_delete(&vps);
	$$ = NULL;
    }
    | DIR_LOC INTNUM INTNUM {
	yasm_valparamhead vps;
	yasm_valparam *vp;

	yasm_vps_initialize(&vps);
	vp = yasm_vp_create(NULL, p_expr_new_ident(yasm_expr_int($2)));
	yasm_vps_append(&vps, vp);
	vp = yasm_vp_create(NULL, p_expr_new_ident(yasm_expr_int($3)));
	yasm_vps_append(&vps, vp);

	yasm_dbgfmt_directive(parser_gas->dbgfmt, "loc",
			      parser_gas->cur_section, &vps, cur_line);

	yasm_vps_delete(&vps);
	$$ = NULL;
    }
    | DIR_LOC INTNUM INTNUM INTNUM {
	yasm_valparamhead vps;
	yasm_valparam *vp;

	yasm_vps_initialize(&vps);
	vp = yasm_vp_create(NULL, p_expr_new_ident(yasm_expr_int($2)));
	yasm_vps_append(&vps, vp);
	vp = yasm_vp_create(NULL, p_expr_new_ident(yasm_expr_int($3)));
	yasm_vps_append(&vps, vp);
	vp = yasm_vp_create(NULL, p_expr_new_ident(yasm_expr_int($4)));
	yasm_vps_append(&vps, vp);

	yasm_dbgfmt_directive(parser_gas->dbgfmt, "loc",
			      parser_gas->cur_section, &vps, cur_line);

	yasm_vps_delete(&vps);
	$$ = NULL;
    }
    | DIR_TYPE label_id ',' '@' label_id {
	yasm_valparamhead vps;
	yasm_valparam *vp;

	yasm_vps_initialize(&vps);
	vp = yasm_vp_create($2, NULL);
	yasm_vps_append(&vps, vp);
	vp = yasm_vp_create($5, NULL);
	yasm_vps_append(&vps, vp);

	yasm_objfmt_directive(parser_gas->objfmt, "type", &vps, NULL,
			      cur_line);

	yasm_vps_delete(&vps);
	$$ = NULL;
    }
    | DIR_SIZE label_id ',' expr {
	yasm_valparamhead vps;
	yasm_valparam *vp;

	yasm_vps_initialize(&vps);
	vp = yasm_vp_create($2, NULL);
	yasm_vps_append(&vps, vp);
	vp = yasm_vp_create(NULL, $4);
	yasm_vps_append(&vps, vp);

	yasm_objfmt_directive(parser_gas->objfmt, "size", &vps, NULL,
			      cur_line);

	yasm_vps_delete(&vps);
	$$ = NULL;
    }
    | DIR_ID dirvals	{
	yasm_warn_set(YASM_WARN_GENERAL, N_("directive `%s' not recognized"),
		      $1);
	$$ = (yasm_bytecode *)NULL;
	yasm_xfree($1);
	yasm_vps_delete(&$2);
    }
    | DIR_ID error	{
	yasm_warn_set(YASM_WARN_GENERAL, N_("directive `%s' not recognized"),
		      $1);
	$$ = (yasm_bytecode *)NULL;
	yasm_xfree($1);
    }
    | label_id '=' expr	{
	$$ = (yasm_bytecode *)NULL;
	yasm_symtab_define_equ(p_symtab, $1, $3, cur_line);
	yasm_xfree($1);
    }
;

instr: INSN		{
	$$ = yasm_bc_create_insn(parser_gas->arch, $1, 0, NULL, cur_line);
    }
    | INSN operands	{
	$$ = yasm_bc_create_insn(parser_gas->arch, $1, $2.num_operands,
				 &$2.operands, cur_line);
    }
    | INSN error	{
	yasm_error_set(YASM_ERROR_SYNTAX, N_("expression syntax error"));
	$$ = NULL;
    }
    | PREFIX instr	{
	$$ = $2;
	yasm_bc_insn_add_prefix($$, $1);
    }
    | SEGREG instr	{
	$$ = $2;
	yasm_bc_insn_add_seg_prefix($$, $1[0]);
    }
    | PREFIX {
	$$ = yasm_bc_create_empty_insn(parser_gas->arch, cur_line);
	yasm_bc_insn_add_prefix($$, $1);
    }
    | SEGREG {
	$$ = yasm_bc_create_empty_insn(parser_gas->arch, cur_line);
	yasm_bc_insn_add_seg_prefix($$, $1[0]);
    }
    | ID {
	yasm_error_set(YASM_ERROR_SYNTAX,
		       N_("instruction not recognized: `%s'"), $1);
	$$ = NULL;
    }
    | ID operands {
	yasm_error_set(YASM_ERROR_SYNTAX,
		       N_("instruction not recognized: `%s'"), $1);
	$$ = NULL;
    }
    | ID error {
	yasm_error_set(YASM_ERROR_SYNTAX,
		       N_("instruction not recognized: `%s'"), $1);
	$$ = NULL;
    }
;

dirvals: /* empty */	{ yasm_vps_initialize(&$$); }
    | dirvals2
;

dirvals2: expr			{
	yasm_valparam *vp = yasm_vp_create(NULL, $1);
	yasm_vps_initialize(&$$);
	yasm_vps_append(&$$, vp);
    }
    | dirvals2 ',' expr	{
	yasm_valparam *vp = yasm_vp_create(NULL, $3);
	yasm_vps_append(&$1, vp);
	$$ = $1;
    }
    | dirvals2 ',' ',' expr	{
	yasm_valparam *vp = yasm_vp_create(NULL, NULL);
	yasm_vps_append(&$1, vp);
	vp = yasm_vp_create(NULL, $4);
	yasm_vps_append(&$1, vp);
	$$ = $1;
    }
;

dirstrvals: /* empty */	{ yasm_vps_initialize(&$$); }
    | dirstrvals2
;

dirstrvals2: STRING	{
	yasm_valparam *vp = yasm_vp_create($1.contents, NULL);
	yasm_vps_initialize(&$$);
	yasm_vps_append(&$$, vp);
    }
    | dirstrvals2 ',' STRING	{
	yasm_valparam *vp = yasm_vp_create($3.contents, NULL);
	yasm_vps_append(&$1, vp);
	$$ = $1;
    }
;

strvals: /* empty */	{ yasm_dvs_initialize(&$$); }
    | strvals2
;

strvals2: STRING		{
	yasm_dataval *dv = yasm_dv_create_string($1.contents, $1.len);
	yasm_dvs_initialize(&$$);
	yasm_dvs_append(&$$, dv);
    }
    | strvals2 ',' STRING	{
	yasm_dataval *dv = yasm_dv_create_string($3.contents, $3.len);
	yasm_dvs_append(&$1, dv);
	$$ = $1;
    }
;

datavals: /* empty */	{ yasm_dvs_initialize(&$$); }
    | datavals2
;

datavals2: expr			{
	yasm_dataval *dv = yasm_dv_create_expr($1);
	yasm_dvs_initialize(&$$);
	yasm_dvs_append(&$$, dv);
    }
    | datavals2 ',' expr	{
	yasm_dataval *dv = yasm_dv_create_expr($3);
	yasm_dvs_append(&$1, dv);
	$$ = $1;
    }
;

/* instruction operands */
operands: operand	    {
	yasm_ops_initialize(&$$.operands);
	yasm_ops_append(&$$.operands, $1);
	$$.num_operands = 1;
    }
    | operands ',' operand  {
	yasm_ops_append(&$1.operands, $3);
	$$.operands = $1.operands;
	$$.num_operands = $1.num_operands+1;
    }
;

regmemexpr: '(' REG ')'	    {
	$$ = p_expr_new_ident(yasm_expr_reg($2[0]));
    }
    | '(' ',' REG ')'	    {
	$$ = p_expr_new(yasm_expr_reg($3[0]), YASM_EXPR_MUL,
			yasm_expr_int(yasm_intnum_create_uint(1)));
    }
    | '(' ',' INTNUM ')'    {
	if (yasm_intnum_get_uint($3) != 1)
	    yasm_warn_set(YASM_WARN_GENERAL,
			  N_("scale factor of %u without an index register"),
			  yasm_intnum_get_uint($3));
	$$ = p_expr_new(yasm_expr_int(yasm_intnum_create_uint(0)),
			YASM_EXPR_MUL, yasm_expr_int($3));
    }
    | '(' REG ',' REG ')'  {
	$$ = p_expr_new(yasm_expr_reg($2[0]), YASM_EXPR_ADD,
	    yasm_expr_expr(p_expr_new(yasm_expr_reg($4[0]), YASM_EXPR_MUL,
		yasm_expr_int(yasm_intnum_create_uint(1)))));
    }
    | '(' ',' REG ',' INTNUM ')'  {
	$$ = p_expr_new(yasm_expr_reg($3[0]), YASM_EXPR_MUL,
			yasm_expr_int($5));
    }
    | '(' REG ',' REG ',' INTNUM ')'  {
	$$ = p_expr_new(yasm_expr_reg($2[0]), YASM_EXPR_ADD,
	    yasm_expr_expr(p_expr_new(yasm_expr_reg($4[0]), YASM_EXPR_MUL,
				      yasm_expr_int($6))));
    }
;

/* memory addresses */
memaddr: expr		    {
	$$ = yasm_arch_ea_create(parser_gas->arch, $1);
    }
    | regmemexpr	    {
	$$ = yasm_arch_ea_create(parser_gas->arch, $1);
	yasm_ea_set_strong($$, 1);
    }
    | expr regmemexpr	    {
	$$ = yasm_arch_ea_create(parser_gas->arch,
				 p_expr_new_tree($2, YASM_EXPR_ADD, $1));
	yasm_ea_set_strong($$, 1);
    }
    | SEGREG ':' memaddr  {
	$$ = $3;
	yasm_ea_set_segreg($$, $1[0]);
    }
;

operand: memaddr	    { $$ = yasm_operand_create_mem($1); }
    | REG		    { $$ = yasm_operand_create_reg($1[0]); }
    | SEGREG		    { $$ = yasm_operand_create_segreg($1[0]); }
    | REGGROUP		    { $$ = yasm_operand_create_reg($1[0]); }
    | REGGROUP '(' INTNUM ')'	{
	unsigned long reg =
	    yasm_arch_reggroup_get_reg(parser_gas->arch, $1[0],
				       yasm_intnum_get_uint($3));
	if (reg == 0) {
	    yasm_error_set(YASM_ERROR_SYNTAX, N_("bad register index `%u'"),
			   yasm_intnum_get_uint($3));
	    $$ = yasm_operand_create_reg($1[0]);
	} else
	    $$ = yasm_operand_create_reg(reg);
	yasm_intnum_destroy($3);
    }
    | '$' expr		    { $$ = yasm_operand_create_imm($2); }
    | '*' REG		    {
	$$ = yasm_operand_create_reg($2[0]);
	$$->deref = 1;
    }
    | '*' memaddr	    {
	$$ = yasm_operand_create_mem($2);
	$$->deref = 1;
    }
;

/* Expressions */
expr: INTNUM		{ $$ = p_expr_new_ident(yasm_expr_int($1)); }
    | FLTNUM		{ $$ = p_expr_new_ident(yasm_expr_float($1)); }
    | explabel		{ $$ = p_expr_new_ident(yasm_expr_sym($1)); }
    | expr '|' expr	{ $$ = p_expr_new_tree($1, YASM_EXPR_OR, $3); }
    | expr '^' expr	{ $$ = p_expr_new_tree($1, YASM_EXPR_XOR, $3); }
    | expr '&' expr	{ $$ = p_expr_new_tree($1, YASM_EXPR_AND, $3); }
    | expr '!' expr	{ $$ = p_expr_new_tree($1, YASM_EXPR_NOR, $3); }
    | expr LEFT_OP expr	{ $$ = p_expr_new_tree($1, YASM_EXPR_SHL, $3); }
    | expr RIGHT_OP expr { $$ = p_expr_new_tree($1, YASM_EXPR_SHR, $3); }
    | expr '+' expr	{ $$ = p_expr_new_tree($1, YASM_EXPR_ADD, $3); }
    | expr '-' expr	{ $$ = p_expr_new_tree($1, YASM_EXPR_SUB, $3); }
    | expr '*' expr	{ $$ = p_expr_new_tree($1, YASM_EXPR_MUL, $3); }
    | expr '/' expr	{ $$ = p_expr_new_tree($1, YASM_EXPR_DIV, $3); }
    | expr '%' expr	{ $$ = p_expr_new_tree($1, YASM_EXPR_MOD, $3); }
    | '+' expr %prec UNARYOP	{ $$ = $2; }
    | '-' expr %prec UNARYOP	{ $$ = p_expr_new_branch(YASM_EXPR_NEG, $2); }
    | '~' expr %prec UNARYOP	{ $$ = p_expr_new_branch(YASM_EXPR_NOT, $2); }
    | '(' expr ')'	{ $$ = $2; }
;

explabel: expr_id	{
	/* "." references the current assembly position */
	if ($1[1] == '\0' && $1[0] == '.')
	    $$ = yasm_symtab_define_curpos(p_symtab, ".", parser_gas->prev_bc,
					   cur_line);
	else
	    $$ = yasm_symtab_use(p_symtab, $1, cur_line);
	yasm_xfree($1);
    }
    | expr_id '@' label_id {
	/* TODO: this is needed for shared objects, e.g. sym@PLT */
	$$ = yasm_symtab_use(p_symtab, $1, cur_line);
	yasm_xfree($1);
	yasm_xfree($3);
    }
;

expr_id: label_id
    | DIR_DATA	{ $$ = yasm__xstrdup(".data"); }
    | DIR_TEXT	{ $$ = yasm__xstrdup(".text"); }
    | DIR_BSS	{ $$ = yasm__xstrdup(".bss"); }
;

label_id: ID | DIR_ID;

%%
/*@=usedef =nullassign =memtrans =usereleased =compdef =mustfree@*/

#undef parser_gas

static void
define_label(yasm_parser_gas *parser_gas, char *name, int local)
{
    if (!local) {
	if (parser_gas->locallabel_base)
	    yasm_xfree(parser_gas->locallabel_base);
	parser_gas->locallabel_base_len = strlen(name);
	parser_gas->locallabel_base =
	    yasm_xmalloc(parser_gas->locallabel_base_len+1);
	strcpy(parser_gas->locallabel_base, name);
    }

    yasm_symtab_define_label(p_symtab, name, parser_gas->prev_bc, 1,
			     cur_line);
    yasm_xfree(name);
}

static void
define_lcomm(yasm_parser_gas *parser_gas, /*@only@*/ char *name,
	     yasm_expr *size, /*@null@*/ yasm_expr *align)
{
    /* Put into .bss section. */
    /*@dependent@*/ yasm_section *bss =
	gas_get_section(parser_gas, yasm__xstrdup(".bss"), NULL, NULL, NULL, 1);

    if (align) {
	/* XXX: assume alignment is in bytes, not power-of-two */
	yasm_section_bcs_append(bss, gas_parser_align(parser_gas, bss, align,
				NULL, NULL, 0));
    }

    yasm_symtab_define_label(p_symtab, name, yasm_section_bcs_last(bss), 1,
			     cur_line);
    yasm_section_bcs_append(bss, yasm_bc_create_reserve(size, 1, cur_line));
    yasm_xfree(name);
}

static yasm_section *
gas_get_section(yasm_parser_gas *parser_gas, char *name,
		/*@null@*/ char *flags, /*@null@*/ char *type,
		/*@null@*/ yasm_valparamhead *objext_valparams,
		int builtin)
{
    yasm_valparamhead vps;
    yasm_valparam *vp;
    char *gasflags;
    yasm_section *new_section;

    yasm_vps_initialize(&vps);
    vp = yasm_vp_create(name, NULL);
    yasm_vps_append(&vps, vp);

    if (!builtin) {
	if (flags) {
	    gasflags = yasm_xmalloc(5+strlen(flags));
	    strcpy(gasflags, "gas_");
	    strcat(gasflags, flags);
	} else
	    gasflags = yasm__xstrdup("gas_");
	vp = yasm_vp_create(gasflags, NULL);
	yasm_vps_append(&vps, vp);
	if (type) {
	    vp = yasm_vp_create(type, NULL);
	    yasm_vps_append(&vps, vp);
	}
    }

    new_section = yasm_objfmt_section_switch(parser_gas->objfmt, &vps,
					     objext_valparams, cur_line);

    yasm_vps_delete(&vps);
    return new_section;
}

static void
gas_switch_section(yasm_parser_gas *parser_gas, char *name,
		   /*@null@*/ char *flags, /*@null@*/ char *type,
		   /*@null@*/ yasm_valparamhead *objext_valparams,
		   int builtin)
{
    yasm_section *new_section;

    new_section = gas_get_section(parser_gas, yasm__xstrdup(name), flags, type,
				  objext_valparams, builtin);
    if (new_section) {
	parser_gas->cur_section = new_section;
	parser_gas->prev_bc = yasm_section_bcs_last(new_section);
    } else
	yasm_error_set(YASM_ERROR_GENERAL, N_("invalid section name `%s'"),
		       name);

    yasm_xfree(name);

    if (objext_valparams)
	yasm_vps_delete(objext_valparams);
}

static yasm_bytecode *
gas_parser_align(yasm_parser_gas *parser_gas, yasm_section *sect,
		 yasm_expr *boundval, /*@null@*/ yasm_expr *fillval,
		 /*@null@*/ yasm_expr *maxskipval, int power2)
{
    yasm_intnum *boundintn;

    /* Convert power of two to number of bytes if necessary */
    if (power2)
	boundval = yasm_expr_create(YASM_EXPR_SHL,
				    yasm_expr_int(yasm_intnum_create_uint(1)),
				    yasm_expr_expr(boundval), cur_line);

    /* Largest .align in the section specifies section alignment. */
    boundintn = yasm_expr_get_intnum(&boundval, 0);
    if (boundintn) {
	unsigned long boundint = yasm_intnum_get_uint(boundintn);

	/* Alignments must be a power of two. */
	if (is_exp2(boundint)) {
	    if (boundint > yasm_section_get_align(sect))
		yasm_section_set_align(sect, boundint, cur_line);
	}
    }

    return yasm_bc_create_align(boundval, fillval, maxskipval,
				yasm_section_is_code(sect) ?
				    yasm_arch_get_fill(parser_gas->arch) : NULL,
				cur_line);
}

static yasm_bytecode *
gas_parser_dir_align(yasm_parser_gas *parser_gas, yasm_valparamhead *valparams,
		     int power2)
{
    /*@dependent@*/ yasm_valparam *bound, *fill = NULL, *maxskip = NULL;
    yasm_expr *boundval, *fillval = NULL, *maxskipval = NULL;

    bound = yasm_vps_first(valparams);
    boundval = bound->param;
    bound->param = NULL;
    if (bound && boundval) {
	fill = yasm_vps_next(bound);
    } else {
	yasm_error_set(YASM_ERROR_SYNTAX,
		       N_("align directive must specify alignment"));
	return NULL;
    }

    if (fill) {
	fillval = fill->param;
	fill->param = NULL;
	maxskip = yasm_vps_next(fill);
    }

    if (maxskip) {
	maxskipval = maxskip->param;
	maxskip->param = NULL;
    }

    yasm_vps_delete(valparams);

    return gas_parser_align(parser_gas, parser_gas->cur_section, boundval,
			    fillval, maxskipval, power2);
}

static yasm_bytecode *
gas_parser_dir_fill(yasm_parser_gas *parser_gas, /*@only@*/ yasm_expr *repeat,
		    /*@only@*/ /*@null@*/ yasm_expr *size,
		    /*@only@*/ /*@null@*/ yasm_expr *value)
{
    yasm_datavalhead dvs;
    yasm_bytecode *bc;
    unsigned int ssize;

    if (size) {
	/*@dependent@*/ /*@null@*/ yasm_intnum *intn;
	intn = yasm_expr_get_intnum(&size, 0);
	if (!intn) {
	    yasm_error_set(YASM_ERROR_NOT_ABSOLUTE,
			   N_("size must be an absolute expression"));
	    yasm_expr_destroy(repeat);
	    yasm_expr_destroy(size);
	    if (value)
		yasm_expr_destroy(value);
	    return NULL;
	}
	ssize = yasm_intnum_get_uint(intn);
    } else
	ssize = 1;

    if (!value)
	value = yasm_expr_create_ident(
	    yasm_expr_int(yasm_intnum_create_uint(0)), cur_line);

    yasm_dvs_initialize(&dvs);
    yasm_dvs_append(&dvs, yasm_dv_create_expr(value));
    bc = yasm_bc_create_data(&dvs, ssize, 0, parser_gas->arch, cur_line);

    yasm_bc_set_multiple(bc, repeat);

    return bc;
}

static void
gas_parser_directive(yasm_parser_gas *parser_gas, const char *name,
		      yasm_valparamhead *valparams,
		      yasm_valparamhead *objext_valparams)
{
    unsigned long line = cur_line;

    /* Handle (mostly) output-format independent directives here */
    if (!yasm_arch_parse_directive(parser_gas->arch, name, valparams,
		    objext_valparams, parser_gas->object, line)) {
	;
    } else if (yasm_objfmt_directive(parser_gas->objfmt, name, valparams,
				     objext_valparams, line)) {
	yasm_error_set(YASM_ERROR_GENERAL, N_("unrecognized directive [%s]"),
		       name);
    }

    yasm_vps_delete(valparams);
    if (objext_valparams)
	yasm_vps_delete(objext_valparams);
}

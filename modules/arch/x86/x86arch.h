/* $Id$
 * x86 Architecture header file
 *
 *  Copyright (C) 2001-2007  Peter Johnson
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
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
#ifndef YASM_X86ARCH_H
#define YASM_X86ARCH_H

/* Available CPU feature flags */
#define CPU_Any     (0UL)       /* Any old cpu will do */
#define CPU_086     CPU_Any
#define CPU_186     (1UL<<0)    /* i186 or better required */
#define CPU_286     (1UL<<1)    /* i286 or better required */
#define CPU_386     (1UL<<2)    /* i386 or better required */
#define CPU_486     (1UL<<3)    /* i486 or better required */
#define CPU_586     (1UL<<4)    /* i585 or better required */
#define CPU_686     (1UL<<5)    /* i686 or better required */
#define CPU_P3      (1UL<<6)    /* Pentium3 or better required */
#define CPU_P4      (1UL<<7)    /* Pentium4 or better required */
#define CPU_IA64    (1UL<<8)    /* IA-64 or better required */
#define CPU_K6      (1UL<<9)    /* AMD K6 or better required */
#define CPU_Athlon  (1UL<<10)   /* AMD Athlon or better required */
#define CPU_Hammer  (1UL<<11)   /* AMD Sledgehammer or better required */
#define CPU_FPU     (1UL<<12)   /* FPU support required */
#define CPU_MMX     (1UL<<13)   /* MMX support required */
#define CPU_SSE     (1UL<<14)   /* Streaming SIMD extensions required */
#define CPU_SSE2    (1UL<<15)   /* Streaming SIMD extensions 2 required */
#define CPU_SSE3    (1UL<<16)   /* Streaming SIMD extensions 3 required */
#define CPU_3DNow   (1UL<<17)   /* 3DNow! support required */
#define CPU_Cyrix   (1UL<<18)   /* Cyrix-specific instruction */
#define CPU_AMD     (1UL<<19)   /* AMD-specific inst. (older than K6) */
#define CPU_SMM     (1UL<<20)   /* System Management Mode instruction */
#define CPU_Prot    (1UL<<21)   /* Protected mode only instruction */
#define CPU_Undoc   (1UL<<22)   /* Undocumented instruction */
#define CPU_Obs     (1UL<<23)   /* Obsolete instruction */
#define CPU_Priv    (1UL<<24)   /* Priveleged instruction */
#define CPU_SVM     (1UL<<25)   /* Secure Virtual Machine instruction */
#define CPU_PadLock (1UL<<25)   /* VIA PadLock instruction */
#define CPU_EM64T   (1UL<<26)   /* Intel EM64T or better */
#define CPU_SSSE3   (1UL<<27)   /* Streaming SIMD extensions 3 required */
#define CPU_SSE41   (1UL<<28)   /* Streaming SIMD extensions 4.1 required */
#define CPU_SSE42   (1UL<<29)   /* Streaming SIMD extensions 4.2 required */
#define CPU_SSE4    (CPU_SSE41|CPU_SSE42)

/* Technically not CPU capabilities, they do affect what instructions are
 * available.  These are tested against BITS==64.
 */
#define CPU_64      (1UL<<30)   /* Only available in 64-bit mode */
#define CPU_Not64   (1UL<<31)   /* Not available (invalid) in 64-bit mode */

typedef struct yasm_arch_x86 {
    yasm_arch_base arch;        /* base structure */

    /* What instructions/features are enabled? */
    unsigned long cpu_enabled;
    unsigned int amd64_machine;
    enum {
        X86_PARSER_NASM,
        X86_PARSER_GAS
    } parser;
    unsigned char mode_bits;
    unsigned char force_strict;
} yasm_arch_x86;

/* 0-15 (low 4 bits) used for register number, stored in same data area.
 * Note 8-15 are only valid for some registers, and only in 64-bit mode.
 */
typedef enum {
    X86_REG8 = 0x1<<4,
    X86_REG8X = 0x2<<4,     /* 64-bit mode only, REX prefix version of REG8 */
    X86_REG16 = 0x3<<4,
    X86_REG32 = 0x4<<4,
    X86_REG64 = 0x5<<4,     /* 64-bit mode only */
    X86_FPUREG = 0x6<<4,
    X86_MMXREG = 0x7<<4,
    X86_XMMREG = 0x8<<4,
    X86_CRREG = 0x9<<4,
    X86_DRREG = 0xA<<4,
    X86_TRREG = 0xB<<4,
    X86_RIP = 0xC<<4        /* 64-bit mode only, always RIP (regnum ignored) */
} x86_expritem_reg_size;

typedef enum {
    X86_LOCKREP = 1,
    X86_ADDRSIZE,
    X86_OPERSIZE,
    X86_SEGREG,
    X86_REX
} x86_parse_insn_prefix;

typedef enum {
    X86_NEAR = 1,
    X86_SHORT,
    X86_FAR,
    X86_TO
} x86_parse_targetmod;

typedef enum {
    JMP_NONE,
    JMP_SHORT,
    JMP_NEAR,
    JMP_SHORT_FORCED,
    JMP_NEAR_FORCED
} x86_jmp_opcode_sel;

typedef enum {
    X86_REX_W = 3,
    X86_REX_R = 2,
    X86_REX_X = 1,
    X86_REX_B = 0
} x86_rex_bit_pos;

/* Sets REX (4th bit) and 3 LS bits from register size/number.  Returns 1 if
 * impossible to fit reg into REX, otherwise returns 0.  Input parameter rexbit
 * indicates bit of REX to use if REX is needed.  Will not modify REX if not
 * in 64-bit mode or if it wasn't needed to express reg.
 */
int yasm_x86__set_rex_from_reg(unsigned char *rex, unsigned char *low3,
                               uintptr_t reg, unsigned int bits,
                               x86_rex_bit_pos rexbit);

/* Effective address type */
typedef struct x86_effaddr {
    yasm_effaddr ea;            /* base structure */

    /* How the spare (register) bits in Mod/RM are handled:
     * Even if valid_modrm=0, the spare bits are still valid (don't overwrite!)
     * They're set in bytecode_create_insn().
     */
    unsigned char modrm;
    unsigned char valid_modrm;  /* 1 if Mod/RM byte currently valid, 0 if not */
    unsigned char need_modrm;   /* 1 if Mod/RM byte needed, 0 if not */

    unsigned char sib;
    unsigned char valid_sib;    /* 1 if SIB byte currently valid, 0 if not */
    unsigned char need_sib;     /* 1 if SIB byte needed, 0 if not,
                                   0xff if unknown */
} x86_effaddr;

void yasm_x86__ea_init(x86_effaddr *x86_ea, unsigned int spare,
                       yasm_bytecode *precbc);

void yasm_x86__ea_set_disponly(x86_effaddr *x86_ea);
x86_effaddr *yasm_x86__ea_create_reg(unsigned long reg, unsigned char *rex,
                                     unsigned int bits);
x86_effaddr *yasm_x86__ea_create_imm
    (/*@keep@*/ yasm_expr *imm, unsigned int im_len);
yasm_effaddr *yasm_x86__ea_create_expr(yasm_arch *arch,
                                       /*@keep@*/ yasm_expr *e);

void yasm_x86__bc_insn_opersize_override(yasm_bytecode *bc,
                                         unsigned int opersize);
void yasm_x86__bc_insn_addrsize_override(yasm_bytecode *bc,
                                         unsigned int addrsize);
void yasm_x86__bc_insn_set_lockrep_prefix(yasm_bytecode *bc,
                                          unsigned int prefix);

/* Bytecode types */
typedef struct x86_common {
    unsigned char addrsize;         /* 0 or =mode_bits => no override */
    unsigned char opersize;         /* 0 or =mode_bits => no override */
    unsigned char lockrep_pre;      /* 0 indicates no prefix */

    unsigned char mode_bits;
} x86_common;

typedef struct x86_opcode {
    unsigned char opcode[3];        /* opcode */
    unsigned char len;
} x86_opcode;

typedef struct x86_insn {
    x86_common common;              /* common x86 information */
    x86_opcode opcode;

    /*@null@*/ x86_effaddr *x86_ea; /* effective address */

    /*@null@*/ yasm_value *imm;     /* immediate or relative value */

    unsigned char def_opersize_64;  /* default operand size in 64-bit mode */
    unsigned char special_prefix;   /* "special" prefix (0=none) */

    unsigned char rex;          /* REX AMD64 extension, 0 if none,
                                   0xff if not allowed (high 8 bit reg used) */

    /* Postponed (from parsing to later binding) action options. */
    enum {
        /* None */
        X86_POSTOP_NONE = 0,

        /* Instructions that take a sign-extended imm8 as well as imm values
         * (eg, the arith instructions and a subset of the imul instructions)
         * should set this and put the imm8 form as the "normal" opcode (in
         * the first one or two bytes) and non-imm8 form in the second or
         * third byte of the opcode.
         */
        X86_POSTOP_SIGNEXT_IMM8,

        /* Override any attempt at address-size override to 16 bits, and never
         * generate a prefix.  This is used for the ENTER opcode.
         */
        X86_POSTOP_ADDRESS16
    } postop;
} x86_insn;

typedef struct x86_jmp {
    x86_common common;          /* common x86 information */
    x86_opcode shortop, nearop;

    yasm_value target;          /* jump target */

    /* which opcode are we using? */
    /* The *FORCED forms are specified in the source as such */
    x86_jmp_opcode_sel op_sel;
} x86_jmp;

/* Direct (immediate) FAR jumps ONLY; indirect FAR jumps get turned into
 * x86_insn bytecodes; relative jumps turn into x86_jmp bytecodes.
 * This bytecode is not legal in 64-bit mode.
 */
typedef struct x86_jmpfar {
    x86_common common;          /* common x86 information */
    x86_opcode opcode;

    yasm_value segment;         /* target segment */
    yasm_value offset;          /* target offset */
} x86_jmpfar;

void yasm_x86__bc_transform_insn(yasm_bytecode *bc, x86_insn *insn);
void yasm_x86__bc_transform_jmp(yasm_bytecode *bc, x86_jmp *jmp);
void yasm_x86__bc_transform_jmpfar(yasm_bytecode *bc, x86_jmpfar *jmpfar);

void yasm_x86__bc_apply_prefixes
    (x86_common *common, unsigned char *rex, unsigned int def_opersize_64,
     int num_prefixes, uintptr_t **prefixes);

/* Check an effective address.  Returns 0 if EA was successfully determined,
 * 1 if invalid EA, or 2 if indeterminate EA.
 */
int yasm_x86__expr_checkea
    (x86_effaddr *x86_ea, unsigned char *addrsize, unsigned int bits,
     int address16_op, unsigned char *rex, yasm_bytecode *bc);

void yasm_x86__parse_cpu(yasm_arch_x86 *arch_x86, const char *cpuid,
                         size_t cpuid_len);

yasm_arch_insnprefix yasm_x86__parse_check_insnprefix
    (yasm_arch *arch, /*@out@*/ uintptr_t data[4], const char *id,
     size_t id_len);
yasm_arch_regtmod yasm_x86__parse_check_regtmod
    (yasm_arch *arch, /*@out@*/ uintptr_t *data, const char *id,
     size_t id_len);

void yasm_x86__finalize_insn
    (yasm_arch *arch, yasm_bytecode *bc, yasm_bytecode *prev_bc,
     const uintptr_t data[4], int num_operands,
     /*@null@*/ yasm_insn_operands *operands, int num_prefixes,
     uintptr_t **prefixes, int num_segregs, const uintptr_t *segregs);

int yasm_x86__floatnum_tobytes
    (yasm_arch *arch, const yasm_floatnum *flt, unsigned char *buf,
     size_t destsize, size_t valsize, size_t shift, int warn);
int yasm_x86__intnum_tobytes
    (yasm_arch *arch, const yasm_intnum *intn, unsigned char *buf,
     size_t destsize, size_t valsize, int shift, const yasm_bytecode *bc,
     int warn);

unsigned int yasm_x86__get_reg_size(yasm_arch *arch, uintptr_t reg);
#endif

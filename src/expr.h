/* $Id: expr.h,v 1.1 2001/07/05 06:28:54 mu Exp $
 * Expression handling header file
 *
 *  Copyright (C) 2001  Michael Urman
 *
 *  This file is part of YASM.
 *
 *  YASM is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  YASM is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */
#ifndef _EXPR_H_
#define _EXPR_H_

typedef enum {
    EXPR_ADD,
    EXPR_SUB,
    EXPR_MUL,
    EXPR_DIV,
    EXPR_MOD,
    EXPR_NEG,
    EXPR_NOT,
    EXPR_OR,
    EXPR_AND,
    EXPR_XOR,
    EXPR_SHL,
    EXPR_SHR,
    EXPR_LOR,
    EXPR_LAND,
    EXPR_LNOT,
    EXPR_LT,
    EXPR_GT,
    EXPR_EQ,
    EXPR_LE,
    EXPR_GE,
    EXPR_NE,
    EXPR_IDENT	    /* if right is IDENT, then the entire expr is just a num */
} ExprOp;

typedef enum {
    EXPR_NONE,	    /* for left side of a NOT, NEG, etc. */
    EXPR_NUM,
    EXPR_EXPR,
    EXPR_SYM
} ExprType;

typedef union expritem_u {
    struct symrec_s *sym;
    struct expr_s *expr;
    int num;
} ExprItem;

typedef struct expr_s {
    ExprType ltype, rtype;
    ExprItem left, right;
    ExprOp op;
} expr;

expr *expr_new (ExprType, ExprItem, ExprOp, ExprType, ExprItem);
int expr_simplify (expr *);

#endif

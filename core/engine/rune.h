/*
 *  rune.h
 *
 *  Runes (Unicode code points) support for Ciao
 *
 *  Copyright (C) 2020 Jose F. Morales, The Ciao Development Team
 */

#ifndef _CIAO_RUNE_H
#define _CIAO_RUNE_H

#define RUNETY_EOF -1
#define RUNETY_LAYOUT 0
#define RUNETY_LOWERCASE 1
#define RUNETY_UPPERCASE 2
#define RUNETY_DIGIT 3
#define RUNETY_SYMBOL 4
#define RUNETY_PUNCT 5
/* auxiliary code classes */
#define RUNETY_X80 6 /* >=0x80 and pending to decode as UTF8 */
#define RUNETY_IDCONT 7 /* 'solo' if first, name continuation otherwise */
#define RUNETY_INVALID 8

extern char runelowtbl[]; /* code class for runes 0x00..0x7F */

void init_runetbl(void); /* initialize rune tables */

int rune_lookup_class(int c);

/* Get equivalence between rune classes (given by rune_lookup_class(c))
   and ASCII code classes */
static inline int rune_equiv_class(c_rune_t c) {
  switch(rune_lookup_class(c)) {
  case 1: /* whitespace (Z*) */
    return RUNETY_LAYOUT; /* treat as layout */
  case 2: /* first char for variables (XID_Start and Lu) */
    return RUNETY_UPPERCASE; /* treat as capital letter */
  case 3: /* first char for atoms (XID_Start and not Lu) */
    return RUNETY_LOWERCASE; /* treat as small letter */
  case 4: /* other name continuation (XID_Continue+No-XID_Start) */
    return RUNETY_IDCONT; /* special, see read_name/6 */
  case 5: /* symbols (S* or P*) */
    return RUNETY_SYMBOL; /* treat as graphic */
  default:
    return RUNETY_INVALID; /* invalid */
  }
}

/* Get next rune R and code class TYP from char pointer CP.  CP is
   moved to the next rune. Invalid encoding moves the pointer 1 byte
   and assigns TYP=RUNETY_INVALID. */
#define NextRune(CP, R, TYP) ({ \
  R=CP[0]; \
  if (R <= 0x7F) { /* fast case */ \
    CP++; TYP=runelowtbl[R]; \
  } else { \
    CP=next_rune_((unsigned char)R, CP, &R, &TYP); \
  } \
})

#define NextRuneByte(X,I) ({ \
  X=(unsigned char)cp[I]; if (((X)&0xC0)!=0x80) goto invalid;       \
})

/* Rune range          | UTF8 byte sequence (base 2)
   --------------------+--------------------------------------
   0000 0000-0000 007F | 0xxxxxxx
   0000 0080-0000 07FF | 110xxxxx 10xxxxxx
   0000 0800-0000 FFFF | 1110xxxx 10xxxxxx 10xxxxxx
   0001 0000-0010 FFFF | 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
*/

/* Continue get next rune (assume b0>=0x80) and code class.
   return next cp */
static inline 
const unsigned char *next_rune_(unsigned char b0,
                                const unsigned char *cp,
                                c_rune_t *r, int *typ) {
  unsigned char b1,b2,b3;
  c_rune_t r_;
  if (b0 <= 0xBF) { /* 1 byte, invalid */
    goto invalid;
  } else if (b0 <= 0xDF) { /* 2 bytes */
    NextRuneByte(b1, 1);
    r_ = ((b0&0x1F)<<6)|(b1&0x3F);
    if (r_ < 0x80) goto invalid;
    cp+=2;
  } else if (b0 <= 0xEF) { /* 3 bytes */
    NextRuneByte(b1, 1);
    NextRuneByte(b2, 2);
    r_ = ((b0&0xF)<<12)|((b1&0x3F)<<6)|(b2&0x3F);
    if (r_ < 0x800) goto invalid;
    cp+=3;
  } else if (b0 <= 0xF7) { /* % 4 bytes */
    NextRuneByte(b1, 1);
    NextRuneByte(b2, 2);
    NextRuneByte(b3, 3);
    r_ = ((b0&0x7)<<18)|((b1&0x3F)<<12)|((b2&0x3F)<<6)|(b3&0x3F);
    if (r_ < 0x10000) goto invalid;
    cp+=4;
  } else { /* invalid */
    goto invalid;
  }
  *r = r_;
  *typ = rune_equiv_class(r_);
  return cp;
 invalid:
  *r = b0; *typ = RUNETY_INVALID; cp++;
  return cp+1;
}

#endif /* _CIAO_RUNE_H */

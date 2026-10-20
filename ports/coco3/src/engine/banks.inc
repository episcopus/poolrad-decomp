* banks.inc: the bank table and the macros the far-call stubs use.
*
* A code bank is two 8 KB MMU slots (4 and 5, logical $8000..$BFFF) holding 16 KB of code,
* in two consecutive physical blocks. Bank ids start at 1; id 0 means "no bank mapped".
* Every bank image starts with a table of 3-byte JMP instructions (BANK_ENTRY_SIZE each) so
* that the resident stubs know every entry address without knowing the bank's symbols.

BANK_WINDOW     EQU     $8000           logical address of the window
BANK_ENTRY_SIZE EQU     3
MMU_SLOT4       EQU     $FFA4           task 0 register for logical $8000
MMU_SLOT5       EQU     $FFA5           task 0 register for logical $A000

BANK_POOL_FIRST EQU     $18             the game's pool of banks: two blocks each from here (gamemap.h)
BANK1_BLK       EQU     $0C             physical blocks $0C,$0D
BANK2_BLK       EQU     $0E             physical blocks $0E,$0F

* Staging: the demo build lets LOADM put each bank image at a fixed address below $6000,
* and _load_banks copies STAGE_BYTES of it into the bank's blocks. (The real loader in
* step 8.3 reads the bank files from disk straight into the window.)
STAGE1          EQU     $4000
STAGE2          EQU     $5000
STAGE_BYTES     EQU     $1000

* FARSTUB name,bank,index: a resident C-callable stub for entry #index of bank #bank.
FARSTUB MACRO
        EXPORT  _\1
_\1     ldx     #BANK_WINDOW+BANK_ENTRY_SIZE*\3
        ldb     #\2
        jmp     __farcall
        ENDM

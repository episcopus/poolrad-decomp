* mailbox.inc: the test mailbox shared by the engine, the C programs and the harnesses.
* It lives in logical RAM at $0100 (slot 0, always mapped, block $38 = physical $70100 on
* a 512 KB machine). The harnesses (lua/mailbox.lua, scripts/xroar_run.sh) poll MB_STATUS.
*
*   $0100  4   magic "PRAD"
*   $0104  1   checkpoint counter, incremented by mb_checkpoint()
*   $0105  1   status: 0 running, 1 finished and every check passed, 2 finished with a failure
*   $0106  2   number of failed checks
*   $0108  8   reserved
*   $0110  64  result words r0..r31, big endian

MB_BASE         EQU     $0100
MB_MAGIC        EQU     MB_BASE+0
MB_CHECKPOINT   EQU     MB_BASE+4
MB_STATUS       EQU     MB_BASE+5
MB_FAILS        EQU     MB_BASE+6
MB_RESULTS      EQU     MB_BASE+$10
MB_SIZE         EQU     $50

* Engine direct page variables (DP = 0). $80..$9F is the engine's.
FC_CURBANK      EQU     $80     byte: bank mapped in the window now (0 = none)
FC_BSPTR        EQU     $81     word: bank stack pointer (grows down)
FC_U            EQU     $83     word: scratch
FC_Y            EQU     $85     word: scratch
FC_X            EQU     $87     word: scratch (target entry)
FC_D            EQU     $89     word: scratch

BANKSTK_TOP     EQU     $2000   bank stack lives in $1F80..$1FFF
SYSSTK_TOP      EQU     $1F80   system stack S, grows down from here

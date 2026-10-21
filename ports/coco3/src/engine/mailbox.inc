* mailbox.inc: the test mailbox shared by the engine, the C programs and the harnesses.
* It lives in logical RAM at $0900 (slot 0, always mapped, block $38 = physical $71000 on
* a 512 KB machine), above Disk BASIC's RAM ($0000..$0DFF: its vectors at $0100, the NMI hook at $0109,
* disk variables from $0600) which DSKCON needs intact. The harnesses (lua/mailbox.lua, scripts/xroar_run.sh) poll MB_STATUS.
*
*   $0900  4   magic "PRAD"
*   $0904  1   checkpoint counter, incremented by mb_checkpoint()
*   $0905  1   status: 0 running, 1 finished and every check passed, 2 finished with a failure
*   $0906  2   number of failed checks
*   $0908  1   mb_hold's acknowledge: the harness sets it nonzero to release mb_hold
*   $0909  7   reserved
*   $0910  64  result words r0..r31, big endian

MB_BASE         EQU     $0900
SHARED_IMG      EQU     $7C00   the image of the shared data ($0700..$08FF) that boot.asm copies into place (tools/mkgame.py strip_low_records)
MB_MAGIC        EQU     MB_BASE+0
MB_CHECKPOINT   EQU     MB_BASE+4
MB_STATUS       EQU     MB_BASE+5
MB_FAILS        EQU     MB_BASE+6
MB_RESULTS      EQU     MB_BASE+$10
MB_ACK          EQU     MB_BASE+8       harness sets it to release mb_hold (nonzero), the program clears it
FC_TASK         EQU     MB_BASE+9       byte: the MMU task the CPU is in (0 the game, 1 the engine); $FF91 cannot be read back.
*                                       Not in the direct page: Disk BASIC's DSKCON uses $8B (found the hard way: a 1 there makes every read fail with status 128)
MB_PAL          EQU     MB_BASE+$50     the 16 EGA palette register values the engine has set
MB_SIZE         EQU     $60

* Engine direct page variables (DP = 0). $80..$9F is the engine's.
FC_CURBANK      EQU     $80     byte: bank mapped in the window now (0 = none)
FC_BSPTR        EQU     $81     word: bank stack pointer (grows down)
FC_U            EQU     $83     word: scratch
FC_Y            EQU     $85     word: scratch
FC_X            EQU     $87     word: scratch (target entry)
FC_D            EQU     $89     word: scratch
FC_TICK         EQU     $90     byte: a counter the far call trampoline advances at every call and return; the loader's idea of time
FC_STAMP        EQU     $91     13 bytes: the tick of the last use of the bank in each pool block, indexed by the block number from BANK_POOL_FIRST (the seventh slot as block $24)

BANKSTK_TOP     EQU     $2000   bank stack lives in $1F80..$1FFF
SYSSTK_TOP      EQU     $1F80   system stack S, grows down from here

* the shadow of MMU slots 4..7 (task 0 registers $FFA4..$FFA7), restored after a DSKCON call
MMU_SH          EQU     $8C

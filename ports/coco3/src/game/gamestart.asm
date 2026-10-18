* gamestart.asm: where the engine's _game_launch (irq.asm) jumps: logical $2000 of the game's MMU task, the first byte of
* CORE.BIN. The engine has loaded the core and DGROUP and given the game its slots; this sets the stack and the direct page
* the way boot.asm does for the engine and enters CMOC's start-up (INILIB, then main in platform.c).

        INCLUDE mailbox.inc

        SECTION boot
        EXPORT  game_start
        IMPORT  program_start
game_start
        lds     #SYSSTK_TOP
        clra
        tfr     a,dp
        jmp     program_start
        ENDSECTION

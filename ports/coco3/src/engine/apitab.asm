* apitab.asm: the engine's entry from __engcall (engcall.asm): the routine number is in _eng_idx; the stack is as the
* game's stub left it. _api_tab (generated into build/game/api_tab.c by tools/mkgame.py) holds the routines in the order of
* build/game/engine_names.txt; entry 0 is the bank loader.

        SECTION code
        EXPORT  _eng_entry
        IMPORT  _eng_idx
        IMPORT  _api_tab
_eng_entry
        ldb     >_eng_idx
        clra
        aslb
        rola
        addd    #_api_tab
        tfr     d,x
        ldx     ,x
        jmp     ,x
        ENDSECTION

* nobanks.asm: _load_banks for programs that have no code banks (probes).
        SECTION code
        EXPORT  _load_banks
_load_banks
        rts
        ENDSECTION

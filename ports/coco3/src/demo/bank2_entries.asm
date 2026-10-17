* bank2_entries.asm: the JMP table at the start of bank 2 ($8000).
        SECTION entries
        IMPORT  _bank2_whoami
        IMPORT  _bank2_mul
        IMPORT  _bank2_bytes
        jmp     _bank2_whoami           entry 0
        jmp     _bank2_mul              entry 1
        jmp     _bank2_bytes            entry 2
        ENDSECTION

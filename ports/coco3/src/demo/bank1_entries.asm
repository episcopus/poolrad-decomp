* bank1_entries.asm: the JMP table at the start of bank 1 ($8000). Entry i is at
* $8000 + 3 * i; the resident stubs in farstubs.asm use those addresses.
        SECTION entries
        IMPORT  _bank1_whoami
        IMPORT  _bank1_add
        IMPORT  _bank1_chain
        jmp     _bank1_whoami           entry 0
        jmp     _bank1_add              entry 1
        jmp     _bank1_chain            entry 2
        ENDSECTION

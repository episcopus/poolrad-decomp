* farstubs.asm: resident stubs for the far entries (the build will generate these from the
* unit-to-bank assignment in step 8.2; they are hand written for the demo).
        INCLUDE banks.inc
        SECTION code
        IMPORT  __farcall
        FARSTUB bank1_whoami,1,0
        FARSTUB bank1_add,1,1
        FARSTUB bank1_chain,1,2
        FARSTUB bank2_whoami,2,0
        FARSTUB bank2_mul,2,1
        FARSTUB bank2_bytes,2,2
        ENDSECTION

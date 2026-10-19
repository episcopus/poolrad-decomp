/* engapi.c: the game's side of the engine's routines (step 8.5d). Most engine routines are called as they are (a stub in the
 * core, tools/mkgame.py: engine_stubs.asm). The ones that take a pointer into the game's memory or give one back are
 * wrapped here: the engine (MMU task 1) sees the stack but not the game's native memory, so a string is copied to this
 * frame and a result comes back as a value. A picture is a handle (1..128) in the low word of the picture variable; 0 is
 * nil, as the original's pointer. Put8x8Symbol (ovl34) is game code that draws through the engine's picture calls. */
#include "game.h"

u16 eng_LoadPicture(const u8 *name, u8 id, u8 flags, u8 color);
u16 eng_AllocatePicture(u16 height, u16 wcols, u8 items, u8 flags);
void eng_ReleasePicture(u16 handle);
void ShowPictureItem(s16 col, s16 row, u16 handle, u8 item);
u16 DaxLoad(const u8 *name, u16 id);
void DaxRead(u16 off, u8 *dst, u16 n);
void eng_RemapPictureColors(const u8 *from, const u8 *to, s16 first, u8 flicker, u16 handle);

void LoadPicture(const u8 *Text_in, u8 BlockId, u8 AllocFlags, u8 Color, void *Target)
{
    u8 name[10];
    u8 n, i;
    u16 h;
    if (*(farptr *)Target != 0)
        ReleasePicture(Target);
    n = Text_in[0];
    if (n > 8)
        n = 8;
    name[0] = n;
    for (i = 0; i < n; i++)
        name[i + 1] = Text_in[i + 1];
    h = eng_LoadPicture(name, BlockId, AllocFlags, Color);
    if (h != 0) {
        *(farptr *)Target = h;
        FlushKeyboard();
    }
}

void AllocatePicture(u16 Height, u16 WidthCols, u8 ItemCount, u8 AllocFlags, void *Pic)
{
    *(farptr *)Pic = eng_AllocatePicture(Height, WidthCols, ItemCount, AllocFlags);
}

void ReleasePicture(void *Pic)
{
    if (*(farptr *)Pic != 0) {
        eng_ReleasePicture((u16)(*(farptr *)Pic));
        *(farptr *)Pic = 0;
    }
}

void RemapPictureColors(farptr FromMap, farptr ToMap, s16 FirstItem, u8 Flicker, farptr Pic)
{
    u8 from[16], to[16];
    if (Pic == 0)
        return;
    memcpy(from, FPD(u8 *, FromMap), 16);
    memcpy(to, FPD(u8 *, ToMap), 16);
    eng_RemapPictureColors(from, to, FirstItem, Flicker, (u16)Pic);
}

/* res05 0802:0303: block BlockId of the DAX file Name (Ext is .dax) into a new heap block: its size, 0 and nil when the volumes
 * have none. The engine unpacks the block into its stage; it comes over in pieces through this frame. */
void LoadDaxBlock(const u8 *Name_in, const u8 *Ext_in, u8 BlockId, u16 *Size, farptr *Block)
{
    u8 name[10], tmp[128];
    u8 n, i;
    u16 size, off, c;
    (void)Ext_in;
    n = Name_in[0];
    if (n > 8)
        n = 8;
    name[0] = n;
    for (i = 0; i < n; i++)
        name[i + 1] = Name_in[i + 1];
    size = DaxLoad(name, BlockId);
    *Size = size;
    if (size == 0) {
        *Block = 0;
        return;
    }
    *Block = rtl_getmem(size);
    for (off = 0; off < size; off = (u16)(off + c)) {
        c = (u16)(size - off) < 128 ? (u16)(size - off) : 128;
        DaxRead(off, tmp, c);
        memcpy(FPD(u8 *, *Block) + off, tmp, c);
    }
}

/* ovl34:015D: symbols 1..$11E live in banks 0..4 of 8x8 tiles; Direct draws into DrawBuf, else onto the screen */
void Put8x8Symbol(s8 XPos, s8 YPos, u16 Symbol, u8 Direct, u8 Attr)
{
    u8 Bank = 0;
    if (Symbol >= 1 && Symbol <= 45)
        Bank = 0;
    else if (Symbol >= 46 && Symbol <= 115)
        Bank = 1;
    else if (Symbol >= 116 && Symbol <= 185)
        Bank = 2;
    else if (Symbol >= 186 && Symbol <= 255)
        Bank = 3;
    else if (Symbol >= 256 && Symbol <= 286)
        Bank = 4;
    else {
        RestoreVideoMode();
        QuitGame();
    }
    if (TileBanks[Bank] != 0) {
        Symbol -= SymbolBase[Bank];
        if (Direct != 0)
            DrawPictureItem(XPos, YPos, (u8)Symbol, Attr, TileBanks[Bank], DrawBuf);
        else
            ShowPictureItem(XPos, YPos, (u16)TileBanks[Bank], (u8)Symbol);
    }
}

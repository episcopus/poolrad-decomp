#include "game.h"

/* 0802:0000. Frees a heap block that AllocHeapBlock allocated: the size is rounded up to the heap's
     8-byte granularity the same way. LoadDaxBlock frees its packed buffer with it. */
void FreeHeapBlock(farptr (*Block), u16 Size)
{
  POOL_TRACE("FreeHeapBlock");
  rtl_freemem((*Block), (((u16)(Size + 7)) & 0xFFF8));
}

/* 0802:0020. Allocates a heap block of Size bytes rounded up to a multiple of 8. LoadDaxBlock
     allocates its packed buffer with it. */
void AllocHeapBlock(farptr (*Block), u16 Size)
{
  POOL_TRACE("AllocHeapBlock");
  (*Block) = rtl_getmem((((u16)(Size + 7)) & 0xFFF8));
}

/* 0802:0040. Writes Count copies of the character Ch at text cell (Col, Row) through the BIOS
     (INT 10h function 2 sets the cursor, function 9 writes the character with its attribute) on the
     page in TextPage. With VideoAdapter 0 the colour goes through the four-colour table TextColorMap4; with
     VideoAdapter 1 the same two calls are repeated on the page in FillTextPage with the colour as it is. */
void WriteCharsAt(u8 Col, u8 Row, u8 Color, u8 Count, u8 Ch)
{
  POOL_TRACE("WriteCharsAt");
  Regs.AH = BiosSetCursor;
  Regs.BH = TextPage;
  Regs.DH = Row;
  Regs.DL = Col;
  rtl_Intr(BiosVideo, &Regs);
  Regs.AH = BiosWriteChar;
  Regs.AL = Ch;
  Regs.BH = TextPage;
  if (VideoAdapter == AdapterCga) {
    Regs.BL = TextColorMap4[Color];
  } else {
    Regs.BL = Color;
  }
  Regs.CX = Count;
  rtl_Intr(BiosVideo, &Regs);
  if (VideoAdapter == AdapterEga) {
    Regs.AH = BiosSetCursor;
    Regs.BH = FillTextPage;
    Regs.DH = Row;
    Regs.DL = Col;
    rtl_Intr(BiosVideo, &Regs);
    Regs.AH = BiosWriteChar;
    Regs.AL = Ch;
    Regs.BH = FillTextPage;
    Regs.BL = Color;
    Regs.CX = Count;
    rtl_Intr(BiosVideo, &Regs);
  }
}

/* 0802:0105. Writes Text from text cell (Col, Row) to the right in Color, one character at a
     time through WriteCharsAt. */
void WriteTextAt(u8 Col, u8 Row, u8 Color, const u8 *Text_in)
{
  POOL_TRACE("WriteTextAt");
  const u8 *Text = Text_in;
  u8 Len = 0;
  u8 I = 0;
  Len = Text[0];
  {
    u8 limit = Len;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          WriteCharsAt(Col, Row, Color, 1, Text[I]);
          Col++;
        if (I == limit) break;
        I++;
      }
    }
  }
}

/* 0802:0175. Fills Count text cells from (Col, Row) to the right with solid blocks in Color
     (character $DB through WriteCharsAt). */
void FillBlocksAt(u8 Col, u8 Row, u8 Color, u8 Count)
{
  POOL_TRACE("FillBlocksAt");
  WriteCharsAt(Col, Row, Color, Count, SolidBlock);
}

/* 0802:0193. Shows Message in Color on the bottom text row, waits for a key (ReadGameKey) and
     clears the row again with black blocks. QUIRK 0802:01D4: the key is stored and never read. */
void ShowBottomMessage(u8 Color, const u8 *Message_in)
{
  POOL_TRACE("ShowBottomMessage");
  const u8 *Message = Message_in;
  u8 Key = 0;
  FillBlocksAt(0, BottomRow, Black, RowWidth);
  WriteTextAt(0, BottomRow, Color, Message);
  Key = ReadGameKey();
  FillBlocksAt(0, BottomRow, Black, RowWidth);
}

/* 0802:0212. Waits until the overlay file game.ovr can be opened: while it cannot, writes
     "Please insert overlay disk." and waits for a key. res08's initialisation calls it. */
void WaitForOverlayDisk(void)
{
  POOL_TRACE("WaitForOverlayDisk");
  u8 Key = 0;
  u8 Found = 0;
  do {
    Found = FileExists(S("\010game.ovr"));
    if (!Found) {
      rtl_write_str(&Output, S("\033Please insert overlay disk."), 0), rtl_write_ln(&Output);
      Key = ReadGameKey();
    }
  } while (!(Found));
}

/* 0802:025D. Opens the file FileName for reading with records of one byte. While it does not
     exist and NoPrompt is 0, shows DiskPrompt (colour 14) and waits for a key, then tries again.
     Returns 1 when the file was found and GameFile is open, 0 otherwise. */
u8 OpenGameFile(const u8 *FileName_in, const u8 *DiskPrompt_in, u8 NoPrompt, FileRec (*GameFile))
{
  POOL_TRACE("OpenGameFile");
  const u8 *FileName = FileName_in;
  const u8 *DiskPrompt = DiskPrompt_in;
  u8 Result = 0;
  u8 Found = 0;
  do {
    Found = FileExists(FileName);
    if (!Found && ((NoPrompt == 0))) {
      ShowBottomMessage(Yellow, DiskPrompt);
    }
  } while (!(Found || ((NoPrompt != 0))));
  if (Found) {
    rtl_assign(&(*GameFile), FileName);
    rtl_reset(&(*GameFile), 1);
  }
  Result = Found;
  return Result;
}

/* 0802:02EB. Tells whether FileName names a file that can be opened: opens and closes it with
     I/O checks off, keeps IOResult in FileProbeResult, and returns True when that is 0 and the name is not
     empty. */
u8 FileExists(const u8 *FileName_in)
{
  POOL_TRACE("FileExists");
  const u8 *FileName = FileName_in;
  u8 Result = 0;
  FileRec Probe = {0};
  rtl_assign(&Probe, FileName);
  rtl_reset(&Probe, 128);
  rtl_close(&Probe);
  FileProbeResult = rtl_IOResult();
  Result = (((FileProbeResult == 0)) && ((FileName[0] != 0)));
  return Result;
}

/* 0802:0356. Returns Text with each occurrence of Pattern deleted. QUIRK 0802:03A2: the last
     start position is computed once, before any deletion, so the loop runs past the shortened text,
     and a match that a deletion moves under the current position is not seen. */
u8 *DeleteAllOccurrences(u8 *Result_out, const u8 *Text_in, const u8 *Pattern_in)
{
  POOL_TRACE("DeleteAllOccurrences");
  u8 Text[256];
  rtl_str_assign(Text, 255, Text_in);
  const u8 *Pattern = Pattern_in;
  u8 *Result = Result_out;
  u8 LastStart = 0;
  u8 PatternLen = 0;
  u8 I = 0;
  u8 t1[256];
  PatternLen = Pattern[0];
  LastStart = (Text[0] - PatternLen) + 1;
  {
    u8 limit = LastStart;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          if (rtl_str_cmp(rtl_str_copy(t1, Text, I, PatternLen), Pattern) == 0) {
            rtl_str_delete(Text, I, PatternLen);
          }
        if (I == limit) break;
        I++;
      }
    }
  }
  rtl_str_assign(Result, 255, Text);
  return Result;
}

/* 0802:0425. Turns Name into a DOS file name: deletes each of the ten characters of
     BadNameChars (space . * , ? / \ : ; |), keeps the first 8 characters and makes them upper case. */
u8 *MakeDosFileName(u8 *Result_out, const u8 *Name_in)
{
  POOL_TRACE("MakeDosFileName");
  u8 Name[256];
  rtl_str_assign(Name, 255, Name_in);
  u8 *Result = Result_out;
  u8 I = 0;
  u8 t1[256];
  u8 t2[2];
  u8 t3[256];
  {
    if (1 <= 10) {
      I = 1;
      for (;;) {
          rtl_str_assign(Name, 255, DeleteAllOccurrences(t1, Name, rtl_str_char(t2, BadNameChars[I])));
        if (I == 10) break;
        I++;
      }
    }
  }
  rtl_str_assign(Name, 255, rtl_str_copy(t3, Name, 1, 8));
  {
    u8 limit = Name[0];
    if (1 <= limit) {
      I = 1;
      for (;;) {
          Name[I] = rtl_upcase(Name[I]);
        if (I == limit) break;
        I++;
      }
    }
  }
  rtl_str_assign(Result, 40, Name);
  return Result;
}

/* 0802:050F. Unpacks the run-length coded block Source^ (PackedSize bytes) into Dest^. A
     code byte 0..$7E is followed by code + 1 literal bytes; a code -127..-1 is followed by one byte
     that is repeated -code times (whitepaper 4.1). UnpackedSize is not read. QUIRK 0802:0574: the
     codes $7F and -128 ($80) match neither arm and InPos does not move, so the loop never ends; the
     1,245 blocks of the shipped DAX files contain neither code (a scan with tools/re/dax.py). */
void UnpackRle(farptr (*Source), farptr (*Dest), u16 (*PackedSize), u16 (*UnpackedSize))
{
  POOL_TRACE("UnpackRle");
  u16 InPos = 0;
  u16 OutPos = 0;
  s8 Code = 0;
  s32 t1;
  InPos = 0;
  OutPos = 0;
  do {
    Code = (*FPD(TByteArray (*), (*Source)))[InPos];
    t1 = Code;
    if ((t1 >= 0 && t1 <= 126)) {
      rtl_Move((void *)&(*FPD(TByteArray (*), (*Source)))[(u16)(InPos + 1)], (void *)&(*FPD(TByteArray (*), (*Dest)))[OutPos], (s16)(Code + 1));
      InPos += (s16)(Code + 2);
      OutPos += (s16)(Code + 1);
    } else if ((t1 >= -127 && t1 <= -1)) {
      Code = (-Code);
      rtl_FillChar((void *)&(*FPD(TByteArray (*), (*Dest)))[OutPos], Code, (*FPD(TByteArray (*), (*Source)))[(u16)(InPos + 1)]);
      InPos += 2;
      OutPos += Code;
    }
  } while (!(InPos >= (*PackedSize)));
}

/* 0802:05CD. Opens the DAX file Name + Ext twice: as DataFile through OpenGameFile (prompting
     with the disk name InsertDiskPrompts[TileSet], the drive letter DiskDriveLetter and a colon; OpenNoPrompt is the NoPrompt
     flag) and as IndexFile. Reads the header size word from IndexFile into HeaderSize, adds 2 for
     the word itself and seeks DataFile there. Returns False when the file was not found. */
u8 OpenDaxFile(const u8 *Name_in, const u8 *Ext_in, u16 (*HeaderSize), FileRec (*DataFile), FileRec (*IndexFile))
{
  POOL_TRACE("OpenDaxFile");
  const u8 *Name = Name_in;
  const u8 *Ext = Ext_in;
  u8 Result = 0;
  u16 Got = 0;
  u8 t1[81];
  u8 t2[2];
  u8 t3[32];
  u8 t4[81];
  if (OpenGameFile(rtl_str_cat(t1, 2, (const u8 *const[]){Name, Ext}), rtl_str_cat(t3, 3, (const u8 *const[]){InsertDiskPrompts[TileSet], rtl_str_char(t2, (u8)DiskDriveLetter), S("\001:")}), OpenNoPrompt, (void *)&(*DataFile)) != 0) {
    rtl_assign(&(*IndexFile), rtl_str_cat(t4, 2, (const u8 *const[]){Name, Ext}));
    rtl_reset(&(*IndexFile), 1);
    rtl_blockread(&(*IndexFile), (void *)&(*HeaderSize), 2, &Got);
    (*HeaderSize) += 2;
    rtl_seek(&(*DataFile), (*HeaderSize));
    Result = 1;
  } else {
    Result = 0;
  }
  return Result;
}

/* 0802:06E7. Closes the data file and the index file of a DAX file that OpenDaxFile
     opened, with I/O checks (LoadDaxBlock). */
void CloseDaxFile(FileRec (*DataFile), FileRec (*IndexFile))
{
  POOL_TRACE("CloseDaxFile");
  rtl_close(&(*DataFile));
  rtl_close(&(*IndexFile));
}

/* 0802:0716. Loads block BlockId of the DAX file Name + Ext (in the directory GameDir) into a new
     heap block Block of Size bytes (whitepaper 4.1). Walks the index (id byte, offset longint, unpacked
     size word, packed size word per entry) until the id matches or the index ends, reads the packed
     bytes into the buffer PackedBuf and unpacks them (UnpackRle). A packed size above
     MaxPackedSize shows "tempsize <n>" and quits. When the file or the block is missing, Size is 0
     and Block is nil. */
void LoadDaxBlock(const u8 *Name_in, const u8 *Ext_in, u8 BlockId, u16 (*Size), farptr (*Block))
{
  POOL_TRACE("LoadDaxBlock");
  const u8 *Name = Name_in;
  const u8 *Ext = Ext_in;
  u16 PackedSize = 0;
  s32 Offset = 0;
  u8 Id = 0;
  u16 Got = 0;
  FileRec DataFile = {0};
  FileRec IndexFile = {0};
  u16 HeaderSize = 0;
  u8 UnusedByte = 0;
  u8 SizeText[7] = {0};
  u8 t1[256];
  u8 t2[16];
  if (!OpenDaxFile(rtl_str_cat(t1, 2, (const u8 *const[]){GameDir, Name}), Ext, &HeaderSize, (void *)&DataFile, (void *)&IndexFile)) {
    (*Size) = 0;
    (*Block) = 0;
    return;
  }
  do {
    rtl_blockread(&IndexFile, (void *)&Id, 1, &Got);
    rtl_blockread(&IndexFile, (void *)&Offset, 4, &Got);
    rtl_blockread(&IndexFile, (void *)&(*Size), 2, &Got);
    rtl_blockread(&IndexFile, (void *)&PackedSize, 2, &Got);
    if (PackedSize > MaxPackedSize) {
      rtl_str_int(SizeText, 6, PackedSize, 0);
      ShowBottomMessage(Yellow, rtl_str_cat(t2, 2, (const u8 *const[]){S("\011tempsize "), SizeText}));
      QuitGame();
    }
  } while (!(((Id == BlockId)) || ((HeaderSize <= rtl_filepos(&IndexFile)))));
  if (Id != BlockId) {
    (*Size) = 0;
    (*Block) = 0;
    CloseDaxFile((void *)&DataFile, (void *)&IndexFile);
  } else {
    AllocHeapBlock(&PackedBuf, PackedSize);
    (*Block) = rtl_getmem((*Size));
    rtl_seek(&DataFile, HeaderSize + Offset);
    rtl_blockread(&DataFile, (void *)&(*FPD(u8 *, PackedBuf)), PackedSize, &Got);
    CloseDaxFile((void *)&DataFile, (void *)&IndexFile);
    UnpackRle(&PackedBuf, &(*Block), &PackedSize, &(*Size));
    FreeHeapBlock(&PackedBuf, PackedSize);
  }
}

/* 0802:094A. Saves TileSet in SavedTileSet, then makes NewSet the current 8X8D file number.
     RestoreTileSet copies SavedTileSet back. ovl07 and ovl17 call this. */
void SelectTileSet(u8 NewSet)
{
  POOL_TRACE("SelectTileSet");
  SavedTileSet = TileSet;
  TileSet = NewSet;
}

/* 0802:095D. Puts back the TileSet that SelectTileSet saved in SavedTileSet. ovl17 calls this. */
void RestoreTileSet(void)
{
  POOL_TRACE("RestoreTileSet");
  TileSet = SavedTileSet;
}

/* Initialisation part of unit RES05. */
void init_RES05(void)
{
  POOL_TRACE("init");
}

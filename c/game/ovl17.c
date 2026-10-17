#include "game.h"

/* ovl17:0010. Reads the save disk's charlist.txt (SaveDir + 'charlist.txt') and builds List as the
     menu list of the saved characters: one 46-byte menu line per line of that file, in file order.
     A name a party member (the PartyListHead list) already carries is prefixed '* ', so the menu shows who
     is already in the party. Does nothing (List stays nil) when the file is missing. Reads SaveDir
     and the party list; writes List; side effects: the disk prompt (CreateSaveDir) and the heap (one
     menu line per saved character). Called by ovl16's character menu and by SaveCharacter (save one
     character). */
void ReadSavedCharacterList(PMenuLine (*List))
{
  POOL_TRACE("ReadSavedCharacterList");
  PMenuLine SavedLine = 0;
  PMenuLine Last = 0;
  PCharacter Who = 0;
  TextRec Names = {0};
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  (*List) = 0;
  CreateSaveDir();
  if (!FileExists(rtl_str_cat(t1, 2, (const u8 *const[]){SaveDir, S("\014charlist.txt")}))) {
    return;
  }
  rtl_assign(&Names, rtl_str_cat(t2, 2, (const u8 *const[]){SaveDir, S("\014charlist.txt")}));
  rtl_reset_text(&Names);
  while (!rtl_eof(&Names)) {
    SavedLine = rtl_getmem(MenuLineBytes);
    rtl_FillChar((void *)&(*FPD(TMenuLine (*), SavedLine)), MenuLineBytes, 0);
    if ((*List) == 0) {
      (*List) = SavedLine;
      Last = (*List);
    } else {
      (*FPD(TMenuLine (*), Last)).Next = SavedLine;
      Last = (*FPD(TMenuLine (*), Last)).Next;
    }
    rtl_read_str(&Names, (*FPD(TMenuLine (*), Last)).Text, 40), rtl_read_ln(&Names);
    Who = PartyListHead;
    while (((Who != 0)) && ((rtl_str_cmp((*FPD(TCharacter (*), Who)).Name, (*FPD(TMenuLine (*), Last)).Text) != 0))) {
      Who = (*FPD(TCharacter (*), Who)).Next;
    }
    if (Who != 0) {
      rtl_str_assign((*FPD(TMenuLine (*), Last)).Text, 40, rtl_str_cat(t3, 2, (const u8 *const[]){S("\002* "), (*FPD(TMenuLine (*), Last)).Text}));
    }
  }
  rtl_close(&Names);
}

/* ovl17:01B8. Rewrites the save disk's charlist.txt from List, the saved-character menu list that
     ReadSavedCharacterList built (and the add-character menu then edited): makes the save directory
     (CreateSaveDir), then opens charlist.txt for rewriting and shows "Put save disk in <drive>:" and
     tries again while the open fails (IOResult non-zero). Writes one line per list entry whose text
     does not start with '*' (the party members are skipped, so they leave the available-character
     file), then closes it. Reads SaveDir and List; writes charlist.txt. Called by the ovl16 add-character
     menu (AddSavedCharacters) and by SaveCharacter. */
void RewriteSavedCharacterList(PMenuLine List)
{
  POOL_TRACE("RewriteSavedCharacterList");
  PMenuLine Line = 0;
  TextRec Names = {0};
  u16 ErrCode = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  CreateSaveDir();
  do {
    rtl_assign(&Names, rtl_str_cat(t1, 2, (const u8 *const[]){SaveDir, S("\014charlist.txt")}));
    rtl_rewrite_text(&Names);
    ErrCode = rtl_IOResult();
    if (ErrCode != 0) {
      ShowMessageLine(Yellow_OVL17, rtl_str_cat(t3, 3, (const u8 *const[]){S("\021Put save disk in "), rtl_str_char(t2, SaveDir[1]), S("\001:")}));
    }
  } while (!(ErrCode == 0));
  Line = List;
  while (Line != 0) {
    if ((*FPD(TMenuLine (*), Line)).Text[1] != '*') {
      rtl_write_str(&Names, (*FPD(TMenuLine (*), Line)).Text, 0), rtl_write_ln(&Names);
    }
    Line = (*FPD(TMenuLine (*), Line)).Next;
  }
  rtl_close(&Names);
}

/* ovl17:02AE. Makes sure the save directory exists on the save disk: MkDir of SaveDir without its
     trailing backslash, and while that fails with anything but success or "already there" it shows
     "Put save disk in <drive>:" (the drive letter SaveDir starts with) and tries again. Reads SaveDir,
     creates the directory on the save disk as a side effect. Called before the save files are touched
     by ReadSavedCharacterList, RewriteSavedCharacterList, SaveCharacter, LoadGame and SaveGame. */
void CreateSaveDir(void)
{
  POOL_TRACE("CreateSaveDir");
  u16 ErrCode = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  do {
    rtl_MkDir(rtl_str_copy(t1, SaveDir, 1, (s16)(SaveDir[0] - 1)));
    ErrCode = rtl_IOResult();
    if (((ErrCode != IoSuccess)) && ((ErrCode != IoDirExists))) {
      ShowMessageLine(Yellow_OVL17, rtl_str_cat(t3, 3, (const u8 *const[]){S("\021Put save disk in "), rtl_str_char(t2, SaveDir[1]), S("\001:")}));
    }
  } while (!(((ErrCode == IoSuccess)) || ((ErrCode == IoDirExists))));
}

/* ovl17:032F. Combines two in-memory pictures, Dest and Source: ORs the tail bytes (the tile ids) of
     Source into Dest and ANDs its pixel bytes into Dest, so Source masks Dest. On the EGA adapter
     (VideoAdapter 1) the tail is ORed over Source^.ByteSize bytes and only the first
     PictureSlots[11].FirstPic^.ByteSize div 4 pixel bytes are ANDed; on the other two adapters (0 and 2)
     both run over Source^.ByteSize bytes. Called by BuildCharacterIcon for each mirrored half of the character
     head and body pictures (slot 11 holds the reference picture). No heap or file effect. */
void MergePictureData(farptr Source, farptr Dest)
{
  POOL_TRACE("MergePictureData");
  u16 Count = 0;
  u16 I = 0;
  switch (VideoAdapter) {
  case AdapterCga:
  case AdapterTandy:
  {
    {
      u16 limit = (u16)((*FPD(TMemPic_OVL17 (*), Source)).ByteSize - 1);
      if (0 <= limit) {
        I = 0;
        for (;;) {
            (*FPD(TMemPic_OVL17 (*), Dest)).Tail[I] = ((*FPD(TMemPic_OVL17 (*), Dest)).Tail[I] | (*FPD(TMemPic_OVL17 (*), Source)).Tail[I]);
            (*FPD(TByteArray_RES07 (*), (*FPD(TMemPic_OVL17 (*), Dest)).Pixels))[I] = ((*FPD(TByteArray_RES07 (*), (*FPD(TMemPic_OVL17 (*), Dest)).Pixels))[I] & (*FPD(TByteArray_RES07 (*), (*FPD(TMemPic_OVL17 (*), Source)).Pixels))[I]);
          if (I == limit) break;
          I++;
        }
      }
    }
    break;
  }
  case AdapterEga:
  {
    {
      u16 limit = (u16)((*FPD(TMemPic_OVL17 (*), Source)).ByteSize - 1);
      if (0 <= limit) {
        I = 0;
        for (;;) {
            (*FPD(TMemPic_OVL17 (*), Dest)).Tail[I] = ((*FPD(TMemPic_OVL17 (*), Dest)).Tail[I] | (*FPD(TMemPic_OVL17 (*), Source)).Tail[I]);
          if (I == limit) break;
          I++;
        }
      }
    }
    Count = ((*FPD(TMemPic_OVL17 (*), PictureSlots[11].FirstPic)).ByteSize / 4) - 1;
    {
      u16 limit = Count;
      if (0 <= limit) {
        I = 0;
        for (;;) {
            (*FPD(TByteArray_RES07 (*), (*FPD(TMemPic_OVL17 (*), Dest)).Pixels))[I] = ((*FPD(TByteArray_RES07 (*), (*FPD(TMemPic_OVL17 (*), Dest)).Pixels))[I] & (*FPD(TByteArray_RES07 (*), (*FPD(TMemPic_OVL17 (*), Source)).Pixels))[I]);
          if (I == limit) break;
          I++;
        }
      }
    }
    break;
  }
  }
}

/* ovl17:0482. Builds the selected character's (SelectedCharacter) combat icon picture. It selects
     8X8D tile set 3, loads the character's CHEAD picture (block Sel^.CHeadBlock, the set name given
     the suffix FigureBankTable[Sel^.Figure[0]]) into picture slot 11 and its CBODY picture (block
     Sel^.CBodyBlock) into the character's icon slot (PictureSlots[Sel^.CombatIcon]), then merges the CHEAD
     halves into the CBODY halves (MergePictureData: OR the tile bytes, AND the pixels), so the head
     masks the body. When Recolor is set it also builds a 16-entry colour map from the six nibble pairs
     Sel^.Figure[1..6] through FigureColorSlots and applies it to both halves of the icon (RemapPictureColors).
     Finally it frees slot 11, restores the tile set and flushes the keyboard. Called by the ovl16
     character menus, by AddMonsterToParty and by LoadGame. */
void BuildCharacterIcon(u8 Recolor)
{
  POOL_TRACE("BuildCharacterIcon");
  u16 stack_mark = rtl_stack_mark();
  u8 UnusedBytes[3] = {0};
  u8 (*MapFrom)[16] = (u8 (*)[16])rtl_stack_alloc(16);
  u8 (*MapTo)[16] = (u8 (*)[16])rtl_stack_alloc(16);
  u8 I = 0;
  u8 UnusedByte = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  SelectTileSet(3);
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), SelectedCharacter));
      LoadPictureSlot(rtl_str_cat(t2, 2, (const u8 *const[]){S("\005CHEAD"), rtl_str_char(t1, FigureBankTable[w1->Figure[0]])}), w1->CHeadBlock, 11);
      LoadPictureSlot(rtl_str_cat(t4, 2, (const u8 *const[]){S("\005CBODY"), rtl_str_char(t3, FigureBankTable[w1->Figure[0]])}), w1->CBodyBlock, w1->CombatIcon);
      MergePictureData(PictureSlots[11].FirstPic, PictureSlots[w1->CombatIcon].FirstPic);
      MergePictureData(PictureSlots[11].SecondPic, PictureSlots[w1->CombatIcon].SecondPic);
      if (Recolor) {
        {
          if (0 <= 15) {
            I = 0;
            for (;;) {
                (*MapFrom)[I] = I;
                (*MapTo)[I] = I;
              if (I == 15) break;
              I++;
            }
          }
        }
        {
          if (1 <= 6) {
            I = 1;
            for (;;) {
                (*MapTo)[FigureColorSlots[I]] = (w1->Figure[I] & 0xF);
                (*MapTo)[(s16)(FigureColorSlots[I] + 8)] = (s16)((u16)((w1->Figure[I] & 0xF0)) >> 4);
              if (I == 6) break;
              I++;
            }
          }
        }
        RemapPictureColors(rtl_far(&(*MapFrom)), rtl_far(&(*MapTo)), 0, 0, PictureSlots[w1->CombatIcon].FirstPic);
        RemapPictureColors(rtl_far(&(*MapFrom)), rtl_far(&(*MapTo)), 0, 0, PictureSlots[w1->CombatIcon].SecondPic);
      }
      FreePictureSlot(11);
      RestoreTileSet();
      FlushKeyboard();
  }
L_exit:
  rtl_stack_release(stack_mark);
}

/* ovl17:069E. Saves the character Who to the save disk. With an empty Name it adds Who's name to the
     saved-character file charlist.txt (ReadSavedCharacterList, a new 46-byte line at the tail,
     RewriteSavedCharacterList, FreeMenuList) and writes to SaveDir + a DOS-cleaned Who^.Name + '.cha';
     with a Name it makes the save directory and writes to SaveDir + Name + '.sav'. It rewrites the
     file (prompting for the save disk while the open fails), BlockWrites the 285-byte character,
     closes it, and (after erasing any old file) writes the 63-byte items of Who^.Items to '.itm' and
     the 9-byte affects of Who^.Affects to '.spc'. Called by RunCharacterMenu, CreateCharacter and SaveGame. */
void SaveCharacter(PCharacter Who, const u8 *Name_in)
{
  POOL_TRACE("SaveCharacter");
  const u8 *Name = Name_in;
  FileRec SaveFile = {0};
  u8 FileName[41] = {0};
  u8 Suffix[5] = {0};
  u16 Unused = 0;
  PItem Item = 0;
  PAffect Affect = 0;
  PMenuLine List = 0;
  PMenuLine Walk = 0;
  PMenuLine Last = 0;
  u16 ErrCode = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  u8 t5[256];
  u8 t6[256];
  u8 t7[256];
  u8 t8[256];
  u8 t9[256];
  u8 t10[256];
  u8 t11[256];
  u8 t12[256];
  u8 t13[256];
  if (rtl_str_cmp(Name, S("\000")) == 0) {
    ReadSavedCharacterList(&List);
    Walk = List;
    if (Walk != 0) {
      while ((*FPD(TMenuLine (*), Walk)).Next != 0) {
        Walk = (*FPD(TMenuLine (*), Walk)).Next;
      }
    }
    Last = rtl_getmem(MenuLineBytes);
    rtl_FillChar((void *)&(*FPD(TMenuLine (*), Last)), MenuLineBytes, 0);
    rtl_str_assign((*FPD(TMenuLine (*), Last)).Text, 40, (*FPD(TCharacter (*), Who)).Name);
    if (Walk != 0) {
      (*FPD(TMenuLine (*), Walk)).Next = Last;
    } else {
      List = Last;
    }
    RewriteSavedCharacterList(List);
    FreeMenuList(&List);
    rtl_str_assign(Suffix, 4, S("\004.cha"));
    rtl_str_assign(FileName, 40, rtl_str_cat(t3, 2, (const u8 *const[]){SaveDir, MakeDosFileName(t1, DeleteAllOccurrences(t2, (*FPD(TCharacter (*), Who)).Name, S("\001.")))}));
  } else {
    CreateSaveDir();
    rtl_str_assign(Suffix, 4, S("\004.sav"));
    rtl_str_assign(FileName, 40, rtl_str_cat(t4, 2, (const u8 *const[]){SaveDir, Name}));
  }
  do {
    rtl_assign(&SaveFile, rtl_str_cat(t5, 2, (const u8 *const[]){FileName, Suffix}));
    rtl_rewrite(&SaveFile, 1);
    ErrCode = rtl_IOResult();
    if (ErrCode != 0) {
      ShowMessageLine(Yellow_OVL17, rtl_str_cat(t7, 3, (const u8 *const[]){S("\021Put save disk in "), rtl_str_char(t6, SaveDir[1]), S("\001:")}));
    }
  } while (!(ErrCode == 0));
  rtl_blockwrite(&SaveFile, (void *)&(*FPD(TCharacter (*), Who)), 285, NULL);
  rtl_close(&SaveFile);
  if (FileExists(rtl_str_cat(t8, 2, (const u8 *const[]){FileName, S("\004.itm")}))) {
    rtl_assign(&SaveFile, rtl_str_cat(t9, 2, (const u8 *const[]){FileName, S("\004.itm")}));
    rtl_erase(&SaveFile);
  }
  if ((*FPD(TCharacter (*), Who)).Items != 0) {
    rtl_assign(&SaveFile, rtl_str_cat(t10, 2, (const u8 *const[]){FileName, S("\004.itm")}));
    rtl_rewrite(&SaveFile, 1);
    Item = (*FPD(TCharacter (*), Who)).Items;
    while (Item != 0) {
      rtl_blockwrite(&SaveFile, (void *)&(*FPD(TMenuLine (*), Item)), 63, NULL);
      Item = (*FPD(TMenuLine (*), Item)).Next;
    }
    rtl_close(&SaveFile);
  }
  if (FileExists(rtl_str_cat(t11, 2, (const u8 *const[]){FileName, S("\004.spc")}))) {
    rtl_assign(&SaveFile, rtl_str_cat(t12, 2, (const u8 *const[]){FileName, S("\004.spc")}));
    rtl_erase(&SaveFile);
  }
  if ((*FPD(TCharacter (*), Who)).Affects != 0) {
    rtl_assign(&SaveFile, rtl_str_cat(t13, 2, (const u8 *const[]){FileName, S("\004.spc")}));
    rtl_rewrite(&SaveFile, 1);
    Affect = (*FPD(TCharacter (*), Who)).Affects;
    while (Affect != 0) {
      rtl_blockwrite(&SaveFile, (void *)&(*FPD(TAffect (*), Affect)), 9, NULL);
      Affect = (*FPD(TAffect (*), Affect)).Next;
    }
    rtl_close(&SaveFile);
  }
}

/* ovl17:0AEC. Loads one character and its item and affect lists from a file. The file lives on the
     save disk (UseSaveDir: FileName is SaveDir + the DOS-cleaned name, and the prompt names SaveDir's
     drive) or on the game disk (the prompt is InsertDiskPrompts[TileSet] + GameDir's drive). SavedGame
     picks the character suffix: '.sav' for a saved game, '.cha' for an available character. It opens
     FileName + Suffix through OpenGameFile and BlockReads the 285-byte character into Who^, then clears
     Who's list links (Next, Items, Affects, Combat), and, when FileName.itm / FileName.spc exist, reads
     the 63-byte item and 9-byte affect lists, each into a GetMem chain that runs to end of file. Reads
     SaveDir, GameDir, TileSet and InsertDiskPrompts; writes SaveFile, Who^ and the heap; then flushes the
     keyboard. The read counterpart of SaveCharacter. Called by AddSavedCharacters and LoadGame. */
void LoadCharacterFile(const u8 *FileName_in, PCharacter Who, u8 SavedGame, u8 UseSaveDir)
{
  POOL_TRACE("LoadCharacterFile");
  u8 FileName[256];
  rtl_str_assign(FileName, 255, FileName_in);
  FileRec SaveFile = {0};
  u16 ReadCount = 0;
  u8 Suffix[5] = {0};
  PItem Item = 0;
  PAffect Affect = 0;
  u8 DiskPrompt[41] = {0};
  u8 Status = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  u8 t5[256];
  u8 t6[256];
  u8 t7[256];
  u8 t8[256];
  u8 t9[256];
  u8 t10[256];
  u8 t11[256];
  if (UseSaveDir != 0) {
    rtl_str_assign(FileName, 255, rtl_str_cat(t2, 2, (const u8 *const[]){SaveDir, MakeDosFileName(t1, FileName)}));
    rtl_str_assign(DiskPrompt, 40, rtl_str_cat(t4, 3, (const u8 *const[]){S("\021Put save disk in "), rtl_str_char(t3, SaveDir[1]), S("\001:")}));
  } else {
    rtl_str_assign(DiskPrompt, 40, rtl_str_cat(t6, 3, (const u8 *const[]){InsertDiskPrompts[TileSet], rtl_str_char(t5, GameDir[1]), S("\001:")}));
  }
  if (SavedGame != 0) {
    rtl_str_assign(Suffix, 4, S("\004.sav"));
  } else {
    rtl_str_assign(Suffix, 4, S("\004.cha"));
  }
  Status = OpenGameFile(rtl_str_cat(t7, 2, (const u8 *const[]){FileName, Suffix}), DiskPrompt, 0, (void *)&SaveFile);
  rtl_blockread(&SaveFile, (void *)&(*FPD(TCharacter (*), Who)), 285, &ReadCount);
  rtl_close(&SaveFile);
  (*FPD(TCharacter (*), Who)).Next = 0;
  (*FPD(TCharacter (*), Who)).Items = 0;
  (*FPD(TCharacter (*), Who)).Affects = 0;
  (*FPD(TCharacter (*), Who)).Combat = 0;
  if (FileExists(rtl_str_cat(t8, 2, (const u8 *const[]){FileName, S("\004.itm")}))) {
    (*FPD(TCharacter (*), Who)).Items = rtl_getmem(63);
    Item = (*FPD(TCharacter (*), Who)).Items;
    Status = OpenGameFile(rtl_str_cat(t9, 2, (const u8 *const[]){FileName, S("\004.itm")}), DiskPrompt, 0, (void *)&SaveFile);
    do {
      rtl_blockread(&SaveFile, (void *)&(*FPD(TMenuLine (*), Item)), 63, &ReadCount);
      (*FPD(TMenuLine (*), Item)).Next = 0;
      if (!rtl_eof(&SaveFile)) {
        (*FPD(TMenuLine (*), Item)).Next = rtl_getmem(63);
        Item = (*FPD(TMenuLine (*), Item)).Next;
      }
    } while (!(rtl_eof(&SaveFile)));
    rtl_close(&SaveFile);
  }
  if (FileExists(rtl_str_cat(t10, 2, (const u8 *const[]){FileName, S("\004.spc")}))) {
    (*FPD(TCharacter (*), Who)).Affects = rtl_getmem(9);
    Affect = (*FPD(TCharacter (*), Who)).Affects;
    Status = OpenGameFile(rtl_str_cat(t11, 2, (const u8 *const[]){FileName, S("\004.spc")}), DiskPrompt, 0, (void *)&SaveFile);
    do {
      rtl_blockread(&SaveFile, (void *)&(*FPD(TAffect (*), Affect)), 9, &ReadCount);
      (*FPD(TAffect (*), Affect)).Next = 0;
      if (!rtl_eof(&SaveFile)) {
        (*FPD(TAffect (*), Affect)).Next = rtl_getmem(9);
        Affect = (*FPD(TAffect (*), Affect)).Next;
      }
    } while (!(rtl_eof(&SaveFile)));
    rtl_close(&SaveFile);
  }
  FlushKeyboard();
}

/* ovl17:0EC4. Loads one monster character and its affect and item lists from the MON<TileSet>*.DAX
     archives. CharSet is Str(TileSet). It loads MON<set>CHA.DAX block Kind into a buffer and, when the
     block is missing, shows 'Unable to load monster' and quits; otherwise it Moves the 285-byte record
     into Who^, clears the character's list links (Items, Affects, Next, Combat) and builds its figure
     descriptor: Figure[0] is 1 for the races 1/3/5 and 2 for 2/4/6/7, Figure[1..3] and Figure[5..6] are
     two random nibble pairs from RollDice(1, 6), and Figure[4] is $C4. Then it loads MON<set>SPC.DAX
     and MON<set>ITM.DAX block Kind and copies their 9-byte affect and 63-byte item records out of the
     buffer (the offset advances to the block size) into GetMem chains. Sets OpenNoPrompt while the lists are
     read and flushes the keyboard. Called by ovl07 LoadCharacter and AddMonsterToParty. */
void LoadMonster(u8 Kind, farptr Who)
{
  POOL_TRACE("LoadMonster");
  u16 Size = 0;
  farptr Block = 0;
  u16 Offset = 0;
  PItem Item = 0;
  PAffect Affect = 0;
  u8 CharSet[2] = {0};
  u8 I = 0;
  u8 Roll = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  rtl_str_int(CharSet, 1, TileSet, 0);
  LoadDaxBlock(rtl_str_cat(t1, 3, (const u8 *const[]){S("\003MON"), CharSet, S("\003CHA")}), S("\004.dax"), Kind, &Size, &Block);
  if (Size == 0) {
    ShowMessageLine(15, S("\026Unable to load monster"));
    QuitGame();
  }
  rtl_Move((void *)&(*FPD(u8 *, Block)), (void *)&(*FPD(u8 *, Who)), 285);
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), Who));
      w1->Items = 0;
      w1->Affects = 0;
      w1->Next = 0;
      w1->Combat = 0;
      switch (w1->Race) {
      case 1:
      case 3:
      case 5:
      {
        w1->Figure[0] = 1;
        break;
      }
      case 2:
      case 4:
      case 6:
      case 7:
      {
        w1->Figure[0] = 2;
        break;
      }
      }
      {
        if (1 <= 3) {
          I = 1;
          for (;;) {
              Roll = RollDice(1, 6);
              w1->Figure[I] = Roll + ((s16)(((s16)(Roll + 8)) << 4));
            if (I == 3) break;
            I++;
          }
        }
      }
      w1->Figure[4] = 0xC4;
      {
        if (5 <= 6) {
          I = 5;
          for (;;) {
              Roll = RollDice(1, 6);
              w1->Figure[I] = Roll + ((s16)(((s16)(Roll + 8)) << 4));
            if (I == 6) break;
            I++;
          }
        }
      }
  }
  rtl_freemem(Block, Size);
  OpenNoPrompt = 1;
  LoadDaxBlock(rtl_str_cat(t2, 3, (const u8 *const[]){S("\003MON"), CharSet, S("\003SPC")}), S("\004.dax"), Kind, &Size, &Block);
  if (Size != 0) {
    Offset = 0;
    (*FPD(TCharacter (*), Who)).Affects = rtl_getmem(9);
    Affect = (*FPD(TCharacter (*), Who)).Affects;
    do {
      rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), Block))[Offset], (void *)&(*FPD(TAffect (*), Affect)), 9);
      (*FPD(TAffect (*), Affect)).Next = 0;
      Offset += 9;
      if (Offset < Size) {
        (*FPD(TAffect (*), Affect)).Next = rtl_getmem(9);
        Affect = (*FPD(TAffect (*), Affect)).Next;
      }
    } while (!(Offset >= Size));
    rtl_freemem(Block, Size);
  }
  LoadDaxBlock(rtl_str_cat(t3, 3, (const u8 *const[]){S("\003MON"), CharSet, S("\003ITM")}), S("\004.dax"), Kind, &Size, &Block);
  if (Size != 0) {
    Offset = 0;
    (*FPD(TCharacter (*), Who)).Items = rtl_getmem(63);
    Item = (*FPD(TCharacter (*), Who)).Items;
    do {
      rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), Block))[Offset], (void *)&(*FPD(TMenuLine (*), Item)), 63);
      (*FPD(TMenuLine (*), Item)).Next = 0;
      Offset += 63;
      if (Offset < Size) {
        (*FPD(TMenuLine (*), Item)).Next = rtl_getmem(63);
        Item = (*FPD(TMenuLine (*), Item)).Next;
      }
    } while (!(Offset >= Size));
    rtl_freemem(Block, Size);
  }
  OpenNoPrompt = 0;
  FlushKeyboard();
}

/* ovl17:1262. Adds a monster of kind Kind to the party. If the party already holds eight members
     (GameVars2^[PartySize] > 7) it does nothing. Otherwise it allocates a 285-byte character and has
     LoadMonster fill it, gives it a random byte at +$AB (Random(256)), collects the classes with a
     positive level (Who^.ClassLevels[0..6]) into Pick[] (Pick[1] = 2 when none qualifies), rolls one of
     them (RollDice(1, Count)) and picks the monster's body picture bank from the FigureBankTable-region
     MonsterBanks tables by the roll and Who^.Sex (the body table of class 0, 5, 6 or the default), and
     its head bank from the head table the same way. Then AddPartyMember adds it and
     BuildCharacterIcon(True) rebuilds the combat icon. Called by AddComputerMemberCommand. */
void AddMonsterToParty(u8 Kind)
{
  POOL_TRACE("AddMonsterToParty");
  farptr Unused = 0;
  PCharacter Who = 0;
  u8 Count = 0;
  s8 I = 0;
  u8 Pick[4] = {0};
  if ((*FPD(TGameVars (*), GameVars2))[830] > 7) {
    return;
  }
  Who = rtl_getmem(285);
  LoadMonster(Kind, Who);
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), Who));
      w1->RandomTag = rtl_Random(256);
      Count = 0;
      {
        if (0 <= AddMonsterToParty_LastClass) {
          I = 0;
          for (;;) {
              if (w1->ClassLevels[I] > 0) {
                Count++;
                Pick[Count - 1] = I;
              }
            if (I == AddMonsterToParty_LastClass) break;
            I++;
          }
        }
      }
      if (Count == 0) {
        Count = 1;
        Pick[Count - 1] = 2;
      }
      Count = RollDice(1, Count);
      switch (Pick[Count - 1]) {
      case 0:
      {
        w1->BodyBank = MonsterBanks.BodyClass0[w1->Sex][RollDice(1, 5)];
        break;
      }
      case 5:
      {
        w1->BodyBank = MonsterBanks.BodyClass5[w1->Sex][RollDice(1, 5)];
        break;
      }
      case 6:
      {
        w1->BodyBank = MonsterBanks.BodyClass6[w1->Sex][RollDice(1, 5)];
        break;
      }
      default:
      {
        w1->BodyBank = MonsterBanks.BodyOther[w1->Sex][RollDice(1, 5)];
      }
      }
      w1->HeadBank = MonsterBanks.Head[w1->Sex][RollDice(1, 8)];
  }
  AddPartyMember(Who);
  BuildCharacterIcon(1);
}

/* ovl17:1446. Adds one character to the party list (PartyListHead) and gives it a combat map icon. Member
     points to the TCharacter to add: its Next is left nil. When the list is empty it becomes the head
     and SelectedCharacter; otherwise it is linked at the tail. Then every icon number 0..7 a member
     already holds is marked Used[], and SelectedCharacter (set to Member) gets the lowest number no one
     holds. Finally the party size word is counted up and the character's class statistics are
     recalculated. Reads the party list and SelectedCharacter; side effects: the party list,
     SelectedCharacter^.CombatIcon, GameVars2^[VarPartySize], and whatever RecalcClassStats writes. */
void AddPartyMember(PCharacter Member)
{
  POOL_TRACE("AddPartyMember");
  PCharacter Who = 0;
  u8 Used[8] = {0};
  (*FPD(TCharacter (*), Member)).CombatIcon = 0xFF;
  if (PartyListHead == 0) {
    PartyListHead = (s32)Member;
    SelectedCharacter = Member;
  } else {
    Who = PartyListHead;
    while ((*FPD(TCharacter (*), Who)).Next != 0) {
      Who = (*FPD(TCharacter (*), Who)).Next;
    }
    (*FPD(TCharacter (*), Who)).Next = Member;
  }
  rtl_FillChar((void *)&Used, 8, 0);
  Who = PartyListHead;
  while (Who != 0) {
    if (((*FPD(TCharacter (*), Who)).CombatIcon >= AddPartyMember_FirstIcon && (*FPD(TCharacter (*), Who)).CombatIcon <= 7)) {
      Used[(*FPD(TCharacter (*), Who)).CombatIcon] = 1;
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  SelectedCharacter = Member;
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), SelectedCharacter));
      w1->CombatIcon = AddPartyMember_FirstIcon;
      while (((w1->CombatIcon < AddPartyMember_IconCount)) && Used[w1->CombatIcon]) {
        w1->CombatIcon++;
      }
  }
  (*FPD(TGameVars (*), GameVars2))[830]++;
  RecalcClassStats(Member);
}

/* ovl17:1602. Loads a saved game from the save disk. It scans the letters A..J for
     SaveDir + 'savgam<letter>.dat', collects the found ones into the 'Load Which Game: ' prompt
     (ReadPromptChoice, Escape cancels) and prompts again until the player picks a slot whose file
     exists. Then it opens the slot through OpenGameFile and reads the game state back: TileSet, the
     three word blocks (GameVars, GameVars2, GameVars3), the ECL code, the party map bytes, AreaViewKind, the
     view mode, and the party list (a member count and the 8 'CHRDAT<slot><n>' names). It restores
     GameSpeed and the picture flags, loads every named member through LoadCharacterFile and
     AddPartyMember, erases the members' old standalone .cha/.itm/.spc files, rebuilds every member's
     combat icon (BuildCharacterIcon(True)), then restores the view: TileSet from $6E12, and either the
     3D view (AreaViewKind < 2: Load3DMap(GameVars^[VarGeoBlock]) and the three wall sets through
     LoadWallSet, the WallSetSlotPairs pairs whose block id is not negative) or, for a map view
     (AreaViewKind > 1), LoadPictureSlot('ICON', 0, 11), which loads ICON block 0 into picture slot 11,
     the scratch slot BuildCharacterIcon freed (the map view's party marker pictures are slots 9..11,
     ovl26 DrawPartyMarker). It animates the doors when the river gate is set, and flushes the
     keyboard. Reads the save files, SaveDir and the party list; writes the game state,
     PartyListHead, SelectedCharacter and the party list. Called by RunCharacterMenu. */
void LoadGame(void)
{
  POOL_TRACE("LoadGame");
  u8 MemberFiles[8][41] = {0};
  FileRec SaveFile = {0};
  u8 I = 0;
  PCharacter Who = 0;
  u8 FileName[41] = {0};
  u16 ReadCount = 0;
  u8 MemberCount = 0;
  u8 Status = 0;
  u8 Slot = 0;
  u8 ExtKey = 0;
  u8 GameList[21] = {0};
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  u8 t5[256];
  u8 t6[256];
  u8 t7[256];
  u8 t8[256];
  u8 t9[256];
  u8 t10[256];
  u8 t11[256];
  u8 t12[256];
  u8 t13[256];
  u8 t14[256];
  u8 t15[256];
  u8 t16[256];
  u8 t17[256];
  u8 t18[256];
  u8 t19[256];
  u8 t20[256];
  u8 t21[256];
  CreateSaveDir();
  rtl_str_assign(GameList, 20, S("\000"));
  {
    if ('A' <= 'J') {
      Slot = 'A';
      for (;;) {
          if (FileExists(rtl_str_cat(t2, 4, (const u8 *const[]){SaveDir, S("\006savgam"), rtl_str_char(t1, Slot), S("\004.dat")}))) {
            rtl_str_assign(GameList, 20, rtl_str_cat(t4, 3, (const u8 *const[]){GameList, rtl_str_char(t3, Slot), S("\001 ")}));
          }
        if (Slot == 'J') break;
        Slot++;
      }
    }
  }
  if (rtl_str_cmp(GameList, S("\000")) == 0) {
    return;
  }
  do {
    Slot = ReadPromptChoice(S("\021Load Which Game: "), GameList, 13, 10, 15, 0, 0, &ExtKey);
  } while (!((((((Slot >= 'A' && Slot <= 'J'))) && FileExists(rtl_str_cat(t6, 4, (const u8 *const[]){SaveDir, S("\006savgam"), rtl_str_char(t5, Slot), S("\004.dat")})))) || ((Slot == 0x00))));
  if (Slot == 0x00) {
    return;
  }
  Status = OpenGameFile(rtl_str_cat(t8, 4, (const u8 *const[]){SaveDir, S("\006savgam"), rtl_str_char(t7, Slot), S("\004.dat")}), rtl_str_cat(t9, 2, (const u8 *const[]){S("\021Put save disk in "), SaveDir}), 1, (void *)&SaveFile);
  ClearPromptLine();
  DrawTextAt(0, 0x18, 0xA, S("\025Loading...Please Wait"));
  rtl_blockread(&SaveFile, (void *)&TileSet, 1, &ReadCount);
  rtl_blockread(&SaveFile, (void *)&(*FPD(TGameVars (*), GameVars)), 0x800, &ReadCount);
  rtl_blockread(&SaveFile, (void *)&(*FPD(TGameVars (*), GameVars2)), 0x800, &ReadCount);
  rtl_blockread(&SaveFile, (void *)&(*FPD(TBlock400 (*), GameVars3)), 0x400, &ReadCount);
  rtl_blockread(&SaveFile, (void *)&(*FPD(TEclCode (*), EclCode)), 0x1E00, &ReadCount);
  rtl_blockread(&SaveFile, (void *)&PartyMapColumn, 5, &ReadCount);
  rtl_blockread(&SaveFile, (void *)&AreaViewKind, 1, &ReadCount);
  rtl_blockread(&SaveFile, (void *)&ViewMode, 1, &ReadCount);
  rtl_blockread(&SaveFile, (void *)&MemberCount, 1, &ReadCount);
  rtl_blockread(&SaveFile, (void *)&MemberFiles, 0x148, &ReadCount);
  rtl_close(&SaveFile);
  ShowMonsterPics = (u16)((u16)(*FPD(TVmWords4900 (*), VarsAt4900))[255] >> 1);
  ShowPortraits = ((*FPD(TVmWords4900 (*), VarsAt4900))[255] & 1);
  GameSpeed = (*FPD(TVmWords4900 (*), VarsAt4900))[252];
  (*FPD(TVmWords6B00 (*), VarsAt6B00))[830] = 0;
  {
    u8 limit = MemberCount;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          rtl_str_assign(FileName, 40, MakeDosFileName(t10, DeleteAllOccurrences(t11, MemberFiles[I - 1], S("\001."))));
          if (FileExists(rtl_str_cat(t12, 3, (const u8 *const[]){SaveDir, FileName, S("\004.sav")}))) {
            Who = rtl_getmem(285);
            LoadCharacterFile(FileName, Who, 1, 1);
            AddPartyMember(Who);
            CreateSaveDir();
          }
        if (I == limit) break;
        I++;
      }
    }
  }
  Who = PartyListHead;
  while (Who != 0) {
    rtl_str_assign(FileName, 40, rtl_str_cat(t15, 2, (const u8 *const[]){SaveDir, MakeDosFileName(t13, DeleteAllOccurrences(t14, (*FPD(TCharacter (*), Who)).Name, S("\001.")))}));
    if (FileExists(rtl_str_cat(t16, 2, (const u8 *const[]){FileName, S("\004.cha")}))) {
      rtl_assign(&SaveFile, rtl_str_cat(t17, 2, (const u8 *const[]){FileName, S("\004.cha")}));
      rtl_erase(&SaveFile);
      if (FileExists(rtl_str_cat(t18, 2, (const u8 *const[]){FileName, S("\004.itm")}))) {
        rtl_assign(&SaveFile, rtl_str_cat(t19, 2, (const u8 *const[]){FileName, S("\004.itm")}));
        rtl_erase(&SaveFile);
      }
      if (FileExists(rtl_str_cat(t20, 2, (const u8 *const[]){FileName, S("\004.spc")}))) {
        rtl_assign(&SaveFile, rtl_str_cat(t21, 2, (const u8 *const[]){FileName, S("\004.spc")}));
        rtl_erase(&SaveFile);
      }
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  SelectedCharacter = PartyListHead;
  while (SelectedCharacter != 0) {
    BuildCharacterIcon(1);
    SelectedCharacter = (*FPD(TCharacter (*), SelectedCharacter)).Next;
  }
  SelectedCharacter = PartyListHead;
  TileSet = (*FPD(TVmWords6B00 (*), VarsAt6B00))[786];
  if (AreaViewKind < 2) {
    Load3DMap((*FPD(TGameVars (*), GameVars))[197]);
  }
  if (AreaViewKind > 1) {
    LoadPictureSlot(S("\004ICON"), 0, 11);
  } else {
    {
      if (1 <= 3) {
        I = 1;
        for (;;) {
            WallSetSlotPairs[I].A = (*FPD(TVmWords4900 (*), VarsAt4900))[(s16)(0x4AF9 + I) - 18688];
            WallSetSlotPairs[I].B = (*FPD(TVmWords4900 (*), VarsAt4900))[(s16)(0x4AFC + I) - 18688];
            if (WallSetSlotPairs[I].A >= 0) {
              LoadWallSet(WallSetSlotPairs[I].A, WallSetSlotPairs[I].B);
            }
          if (I == 3) break;
          I++;
        }
      }
    }
  }
  if ((*FPD(TGameVars (*), GameVars))[418] != 0) {
    AnimateAreaDoors(0);
  }
  FlushKeyboard();
  ClearPromptLine();
}

/* ovl17:1D58. Saves the current game to the save disk. It prompts 'Save Which Game: ' for a slot
     letter A..J (Escape cancels), makes the save directory and opens SaveDir + 'savgam<letter>.dat'
     (showing the disk prompt while the open fails), then writes the whole game state: the three loaded
     wall-set slots (block id and slot) into the ECL variable words at $4AF9 + I and $4AFC + I,
     GameSpeed and the picture flags, TileSet, the three word blocks
     (GameVars, GameVars2, GameVars3), the ECL code, the party map bytes, AreaViewKind and the view mode. Then
     it writes the party list to the slot: a one-byte member count and the 8 'CHRDAT<letter><n>' names,
     and finally saves each member with SaveCharacter and erases the member's old standalone .cha/.itm/
     .spc files. Ends with the heap retry gate HeapErrorStop := 1 and clears the prompt line. Reads the slot
     key, SaveDir, the game state and the party list PartyListHead; writes the save files and HeapErrorStop. Called by
     the heap error handler, MakeCamp, the character menu and SaveAndExit (SaveAndExit). */
void SaveGame(void)
{
  POOL_TRACE("SaveGame");
  u8 MemberFiles[8][41] = {0};
  FileRec SaveFile = {0};
  u8 Count = 0;
  PCharacter Walk = 0;
  u8 NumText[2] = {0};
  u8 FileName[41] = {0};
  u8 ExtKey = 0;
  u8 Key = 0;
  u16 ErrCode = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  u8 t5[256];
  u8 t6[256];
  u8 t7[256];
  u8 t8[256];
  u8 t9[256];
  u8 t10[256];
  u8 t11[256];
  u8 t12[256];
  u8 t13[256];
  u8 t14[256];
  u8 t15[256];
  u8 t16[256];
  u8 t17[256];
  do {
    Key = ReadPromptChoice(S("\021Save Which Game: "), S("\023A B C D E F G H I J"), 13, 10, 15, 0, (ViewMode == 2), &ExtKey);
  } while (!(Key == 0x00 || (Key >= 'A' && Key <= 'J')));
  if (Key == 0x00) {
    return;
  }
  CreateSaveDir();
  do {
    rtl_assign(&SaveFile, rtl_str_cat(t2, 4, (const u8 *const[]){SaveDir, S("\006savgam"), rtl_str_char(t1, Key), S("\004.dat")}));
    rtl_rewrite(&SaveFile, 1);
    ErrCode = rtl_IOResult();
    if (ErrCode != 0) {
      ShowMessageLine(Yellow_OVL17, rtl_str_cat(t4, 3, (const u8 *const[]){S("\021Put save disk in "), rtl_str_char(t3, SaveDir[1]), S("\001:")}));
    }
  } while (!(ErrCode == 0));
  ClearPromptLine();
  DrawTextAt(0, 0x18, 0xA, S("\024Saving...Please Wait"));
  {
    if (1 <= 3) {
      Count = 1;
      for (;;) {
          (*FPD(TVmWords4900 (*), VarsAt4900))[(s16)(0x4AF9 + Count) - 18688] = WallSetSlotPairs[Count].A;
          (*FPD(TVmWords4900 (*), VarsAt4900))[(s16)(0x4AFC + Count) - 18688] = WallSetSlotPairs[Count].B;
        if (Count == 3) break;
        Count++;
      }
    }
  }
  (*FPD(TVmWords4900 (*), VarsAt4900))[252] = GameSpeed;
  (*FPD(TVmWords4900 (*), VarsAt4900))[255] = (ShowMonsterPics * 2) + ShowPortraits;
  (*FPD(TVmWords6B00 (*), VarsAt6B00))[786] = TileSet;
  rtl_blockwrite(&SaveFile, (void *)&TileSet, 1, NULL);
  rtl_blockwrite(&SaveFile, (void *)&(*FPD(TGameVars (*), GameVars)), 0x800, NULL);
  rtl_blockwrite(&SaveFile, (void *)&(*FPD(TGameVars (*), GameVars2)), 0x800, NULL);
  rtl_blockwrite(&SaveFile, (void *)&(*FPD(TBlock400 (*), GameVars3)), 0x400, NULL);
  rtl_blockwrite(&SaveFile, (void *)&(*FPD(TEclCode (*), EclCode)), 0x1E00, NULL);
  rtl_blockwrite(&SaveFile, (void *)&PartyMapColumn, 5, NULL);
  rtl_blockwrite(&SaveFile, (void *)&AreaViewKind, 1, NULL);
  rtl_blockwrite(&SaveFile, (void *)&ViewMode, 1, NULL);
  Count = 0;
  Walk = PartyListHead;
  while (Walk != 0) {
    Count++;
    rtl_str_int(NumText, 1, Count, 0);
    rtl_str_assign(MemberFiles[Count - 1], 40, rtl_str_cat(t6, 3, (const u8 *const[]){S("\006CHRDAT"), rtl_str_char(t5, Key), NumText}));
    Walk = (*FPD(TCharacter (*), Walk)).Next;
  }
  rtl_blockwrite(&SaveFile, (void *)&Count, 1, NULL);
  rtl_blockwrite(&SaveFile, (void *)&MemberFiles, 0x148, NULL);
  rtl_close(&SaveFile);
  Walk = PartyListHead;
  Count = 0;
  while (Walk != 0) {
    Count++;
    rtl_str_int(NumText, 1, Count, 0);
    SaveCharacter(Walk, rtl_str_cat(t8, 3, (const u8 *const[]){S("\006CHRDAT"), rtl_str_char(t7, Key), NumText}));
    rtl_str_assign(FileName, 40, rtl_str_cat(t11, 2, (const u8 *const[]){SaveDir, MakeDosFileName(t9, DeleteAllOccurrences(t10, (*FPD(TCharacter (*), Walk)).Name, S("\001.")))}));
    if (FileExists(rtl_str_cat(t12, 2, (const u8 *const[]){FileName, S("\004.cha")}))) {
      rtl_assign(&SaveFile, rtl_str_cat(t13, 2, (const u8 *const[]){FileName, S("\004.cha")}));
      rtl_erase(&SaveFile);
    }
    if (FileExists(rtl_str_cat(t14, 2, (const u8 *const[]){FileName, S("\004.itm")}))) {
      rtl_assign(&SaveFile, rtl_str_cat(t15, 2, (const u8 *const[]){FileName, S("\004.itm")}));
      rtl_erase(&SaveFile);
    }
    if (FileExists(rtl_str_cat(t16, 2, (const u8 *const[]){FileName, S("\004.spc")}))) {
      rtl_assign(&SaveFile, rtl_str_cat(t17, 2, (const u8 *const[]){FileName, S("\004.spc")}));
      rtl_erase(&SaveFile);
    }
    Walk = (*FPD(TCharacter (*), Walk)).Next;
  }
  HeapErrorStop = 1;
  ClearPromptLine();
}

/* ovl17:22D5. Called by ovl03:0BD1 with the current area's ECL file name (GameDir + 'ECL' +
     Str(TileSet) + '.dax') just before an area transition. When that file exists (a normal area) it
     returns at once; otherwise it shows the 'Save and exit  Insert disk #N' line (N = TileSet)
     through ReadPromptChoice and, when the player presses its hotkey S, steps the party one cell
     back in its facing (wrapping the 16x16 area map), restores the tile set, saves the game
     (SaveGame) and quits. Reads AreaScript, TileSet, PartyMapColumn, PartyMapRow and PartyFacing;
     writes ExtKey and, on S, the party's map cell. Side effects: the prompt line, the save disk
     and the game exit. */
void SaveAndExit(const u8 *AreaScript_in)
{
  POOL_TRACE("SaveAndExit");
  const u8 *AreaScript = AreaScript_in;
  String40_RES06 Prompt = {0};
  u8 NumText[2] = {0};
  u8 Key = 0;
  u8 ExtKey = 0;
  u8 t1[256];
  if (FileExists(AreaScript)) {
    return;
  }
  rtl_str_int(NumText, 1, TileSet, 0);
  rtl_str_assign(Prompt, 40, rtl_str_cat(t1, 2, (const u8 *const[]){S("\034Save and exit  Insert disk #"), NumText}));
  Key = ReadPromptChoice(S("\000"), Prompt, 13, 10, 15, 0, 0, &ExtKey);
  if (((ExtKey == 0)) && ((Key == 'S'))) {
    PartyMapColumn -= DirStepX[PartyFacing];
    if (PartyMapColumn < 0) {
      PartyMapColumn = 0xF;
    }
    if (PartyMapColumn > 0xF) {
      PartyMapColumn = 0;
    }
    PartyMapRow -= DirStepY[PartyFacing];
    if (PartyMapRow < 0) {
      PartyMapRow = 0xF;
    }
    if (PartyMapRow > 0xF) {
      PartyMapRow = 0;
    }
    RestoreTileSet();
    SaveGame();
    QuitGame();
  }
}

/* Initialisation part of unit OVL17. */
void init_OVL17(void)
{
  POOL_TRACE("init");
}

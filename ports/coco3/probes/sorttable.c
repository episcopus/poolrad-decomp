/* sorttable.c: ovl30's SortTable as the translation writes it (its struct swap, the `% 2` compares, the shadowed loop limit), run by CMOC on
 * seven records, against what the Pascal gives (the AI's target choice depends on the order; step 8.7b: the CoCo's fight left the original's dice
 * stream after 778 dice, at a Random(100) where the original rolled Random(1)).
 * r0..r6  Head of records 1..7 after the sort | std = 5 6 3 2 4 1 7
 * r7..r13 Val of records 1..7                 | std = 6 6 7 2 2 3 9
 */
#include "mailbox.h"
typedef unsigned char u8;
typedef short s16;
typedef struct TSortRec { u8 Head; u8 Key; u8 Val_; } TSortRec;
TSortRec SortEntries[8];

void SortTable(void)
{
  u8 I = 0;
  u8 J = 0;
  u8 ValJ = 0;
  u8 ValI = 0;
  TSortRec Swap_;
  Swap_.Head = 0; Swap_.Key = 0; Swap_.Val_ = 0;
  if ((s16)SortEntries[0].Val_ <= 1) {
    return;
  }
  {
    u8 limit = (s16)((s16)SortEntries[0].Val_ - 1);
    if (1 <= limit) {
      I = 1;
      for (;;) {
          {
            u8 limit = SortEntries[0].Val_;
            u8 first = (s16)((s16)I + 1);
            if (first <= limit) {
              J = first;
              for (;;) {
                  ValI = SortEntries[I].Val_;
                  ValJ = SortEntries[J].Val_;
                  if (((SortEntries[J].Key < SortEntries[I].Key)) || (((((SortEntries[J].Key == SortEntries[I].Key)) && ((ValJ < ValI))) && (((((s16)ValJ % 2)) <= (((s16)ValI % 2))))))) {
                    Swap_ = SortEntries[I];
                    SortEntries[I] = SortEntries[J];
                    SortEntries[J] = Swap_;
                  }
                if (J == limit) break;
                J++;
              }
            }
          }
        if (I == limit) break;
        I++;
      }
    }
  }
}

static const u8 heads[7] = {1, 2, 3, 4, 5, 6, 7};
static const u8 keys[7] = {5, 5, 4, 5, 4, 4, 5};
static const u8 vals[7] = {3, 2, 7, 2, 6, 6, 9};

int main(void)
{
    unsigned i;
    scr_clear();
    scr_puts(0, 0, "PROBE SORTTABLE");
    SortEntries[0].Val_ = 7;
    for (i = 0; i < 7; i++) {
        SortEntries[i + 1].Head = heads[i];
        SortEntries[i + 1].Key = keys[i];
        SortEntries[i + 1].Val_ = vals[i];
    }
    SortTable();
    {
        static const u8 eh[7] = {5, 6, 3, 2, 4, 1, 7};
        static const u8 ev[7] = {6, 6, 7, 2, 2, 3, 9};
        for (i = 0; i < 7; i++) {
            mb_check(i, SortEntries[i + 1].Head, eh[i]);
            mb_check(7 + i, SortEntries[i + 1].Val_, ev[i]);
        }
    }
    mb_finish();
    return 0;
}

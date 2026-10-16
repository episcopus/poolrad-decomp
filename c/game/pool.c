#include "game.h"

/* The main program. */
void pool_main(void)
{
  u8 t1[256];
  StartGame();
  if (rtl_str_cmp(rtl_paramstr(t1, 1), S("\005STING")) != 0) {
    ShowTitleScreen();
    CheckCodeWheel();
  }
  RunCharacterMenu();
  SetWallDescriptors(11, 0, 7, 6);
  RunWilderness();
  QuitGame();
}

void pool_init_units(void)
{
  init_RES02();
  init_RES03();
  init_RES04();
  init_RES05();
  init_RES06();
  init_RES07();
  init_RES08();
  init_OVL34();
  init_RES09();
  init_OVL33();
  init_RES10();
  init_OVL32();
  init_OVL31();
  init_OVL30();
  init_RES11();
  init_OVL29();
  init_OVL28();
  init_OVL27();
  init_OVL26();
  init_OVL25();
  init_RES12();
  init_OVL24();
  init_OVL23();
  init_OVL22();
  init_OVL21();
  init_OVL20();
  init_OVL19();
  init_OVL18();
  init_OVL17();
  init_OVL16();
  init_OVL15();
  init_OVL14();
  init_OVL13();
  init_OVL12();
  init_OVL11();
  init_OVL10();
  init_OVL09();
  init_OVL08();
  init_OVL07();
  init_OVL06();
  init_OVL05();
  init_OVL04();
  init_OVL03();
  init_OVL02();
  init_OVL01();
  init_OVL00();
}

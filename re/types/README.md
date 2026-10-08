# Record and enum types

One C header per record family (`player.h`, `item.h`, ...), written in the project's width types, packed, with an offset assert per field:

```c
typedef struct Player {
    u8   name[16];          /* string[15] */
    s16  hit_points;        /* +0x10 */
    /* ... */
} Player;
STATIC_ASSERT(offsetof(Player, hit_points) == 0x10);
STATIC_ASSERT(sizeof(Player) == 0x1A6);
```

Every field gets a comment with its offset and, once known, its evidence. These headers are copied into `src/include/gen/` by the build so the C code and the tools share one definition.

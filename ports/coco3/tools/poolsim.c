/* poolsim.c: the bank pool of the game, as a function, for tools/rebank.py (step 8.11).
 *
 * The pool is `slots` banks, least recently used out first; a bank is read whole when a routine of it runs and it is not there.
 * seq: the routine group numbers of all sessions one after the other, off[s]..off[s+1] the session s.
 * assign[g]: the bank of group g; bsize[b]: the bytes read when bank b is loaded.
 * out_bytes[s], out_loads[s]: what session s cost. Returns the sum of w[s] * out_bytes[s]. */
#include <stdint.h>

double pool_sim(int nsess, const int32_t *off, const int32_t *seq, const int32_t *assign, const int32_t *bsize,
                int slots, const double *w, int64_t *out_bytes, int32_t *out_loads)
{
    double total = 0;
    for (int s = 0; s < nsess; s++) {
        int32_t pool[64];
        uint32_t stamp[64];
        int n = 0;
        uint32_t clock = 0;
        int last = -1;
        int64_t bytes = 0;
        int loads = 0;
        for (int i = off[s]; i < off[s + 1]; i++) {
            int b = assign[seq[i]];
            if (b == last)
                continue;
            last = b;
            clock++;
            int k = -1;
            for (int j = 0; j < n; j++)
                if (pool[j] == b) { k = j; break; }
            if (k >= 0) {
                stamp[k] = clock;
                continue;
            }
            loads++;
            bytes += bsize[b];
            if (n < slots) {
                k = n++;
            } else {
                k = 0;
                for (int j = 1; j < n; j++)
                    if (stamp[j] < stamp[k]) k = j;
            }
            pool[k] = b;
            stamp[k] = clock;
        }
        if (out_bytes) out_bytes[s] = bytes;
        if (out_loads) out_loads[s] = loads;
        total += w[s] * (double)bytes;
    }
    return total;
}

/* The same pool measured in bytes (an experiment, step 8.11: what a pool of any sized banks would do): `capacity` bytes, a bank is loaded whole, the least
 * recently used banks go until it fits. No fragmentation: the address a bank has in the window is not considered. */
double pool_sim_bytes(int nsess, const int32_t *off, const int32_t *seq, const int32_t *assign, const int32_t *bsize,
                      int32_t capacity, const double *w, int64_t *out_bytes, int32_t *out_loads)
{
    double total = 0;
    for (int s = 0; s < nsess; s++) {
        int32_t pool[256];
        uint32_t stamp[256];
        int n = 0;
        int64_t used = 0;
        uint32_t clock = 0;
        int last = -1;
        int64_t bytes = 0;
        int loads = 0;
        for (int i = off[s]; i < off[s + 1]; i++) {
            int b = assign[seq[i]];
            if (b == last)
                continue;
            last = b;
            clock++;
            int k = -1;
            for (int j = 0; j < n; j++)
                if (pool[j] == b) { k = j; break; }
            if (k >= 0) {
                stamp[k] = clock;
                continue;
            }
            loads++;
            bytes += bsize[b];
            while (n > 0 && used + bsize[b] > capacity) {
                int v = 0;
                for (int j = 1; j < n; j++)
                    if (stamp[j] < stamp[v]) v = j;
                used -= bsize[pool[v]];
                pool[v] = pool[n - 1];
                stamp[v] = stamp[n - 1];
                n--;
            }
            pool[n] = b;
            stamp[n] = clock;
            n++;
            used += bsize[b];
        }
        if (out_bytes) out_bytes[s] = bytes;
        if (out_loads) out_loads[s] = loads;
        total += w[s] * (double)bytes;
    }
    return total;
}

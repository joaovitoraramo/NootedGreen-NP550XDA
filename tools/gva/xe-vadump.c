// xe-vadump: carregada pelo plugin VA. Quando um envio do plugin contém comandos do pipeline de mídia, registra no log
// (subsystem "xe.vadump") os buffers do envio e quem chamou. Só diagnóstico; não altera nada do que é enviado.
#include <dlfcn.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <execinfo.h>
#include <sys/mman.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <os/log.h>
#include <unistd.h>
static os_log_t L;
#define T(...) os_log_error(L, __VA_ARGS__)
extern uint64_t IOAccelVideoContextGetDataBufferResource(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
extern uint64_t IOAccelVideoContextSetDataBufferClassUsedBytes(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
extern uint64_t IOAccelVideoContextSubmitDataBuffers(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
extern void *IOAccelResourceGetDataBytes(uint64_t);
extern uint64_t IOAccelResourceGetDataSize(uint64_t);
extern uint64_t IOAccelResourceCreate(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
extern uint64_t IOAccelResourceRelease(uint64_t);
#define NRES 512
static uint64_t gRes[NRES]; static int gResN;
static uint64_t g_rcreate(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f) { uint64_t r = IOAccelResourceCreate(a, b, c, d, e, f); if (r) { for (int i = 0; i < NRES; i++) if (!gRes[i]) { gRes[i] = r; if (i >= gResN) gResN = i + 1; break; } } return r; }
static uint64_t g_rrelease(uint64_t r) { for (int i = 0; i < gResN; i++) if (gRes[i] == r) gRes[i] = 0; return IOAccelResourceRelease(r); }
static int gNoScore = -1;   // /tmp/xe-noscoreboard presente: desliga o scoreboard do MEDIA_VFE_STATE antes do envio (experimento)
#define NCL 16
static struct { uint64_t ctx, res[NCL]; uint32_t used[NCL]; } G[8];
static int slot(uint64_t c) { for (int i = 0; i < 8; i++) if (G[i].ctx == c) return i; for (int i = 0; i < 8; i++) if (!G[i].ctx) { G[i].ctx = c; return i; } return 0; }
static uint64_t g_res(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f) { uint64_t r = IOAccelVideoContextGetDataBufferResource(a, b, c, d, e, f); if (b < NCL) G[slot(a)].res[b] = r; return r; }
static uint64_t g_used(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f) { if (b < NCL) G[slot(a)].used[b] = (uint32_t)c; return IOAccelVideoContextSetDataBufferClassUsedBytes(a, b, c, d, e, f); }
static int nd;
static void despeja(int cl, const uint32_t *p, uint32_t bytes) {
  uint32_t n = bytes / 4, lim = n > 2048 ? 2048 : n; char b[220];
  for (uint32_t i = 0; i < lim; i += 16) { int z = 1; for (uint32_t k = i; k < i + 16 && k < lim; k++) if (p[k]) z = 0; if (z) continue;
    int o = snprintf(b, sizeof b, "c%d +%04x", cl, i * 4); for (uint32_t k = i; k < i + 16 && k < lim; k++) o += snprintf(b + o, sizeof b - o, " %08x", p[k]);
    T("%{public}s", b); }
}
static uint64_t g_sub(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f) {
  int s = slot(a), media = 0;
  for (int k = 0; k < NCL && !media; k++) { if (!G[s].res[k] || !G[s].used[k]) continue; const uint32_t *p = IOAccelResourceGetDataBytes(G[s].res[k]); if (!p) continue;
    uint32_t n = G[s].used[k] / 4; for (uint32_t i = 0; i < n; i++) if (p[i] == 0x69041301 || p[i] == 0x7100000a) { media = 1; break; } }
  if (media && nd < 6) { nd++;
    void *bt[14]; int nb = backtrace(bt, 14); char l[260]; int o = snprintf(l, sizeof l, "ENVIO-MIDIA #%d ctx %llx:", nd, a);
    for (int i = 1; i < nb && o < 240; i++) { Dl_info di; if (dladdr(bt[i], &di) && di.dli_fname && strstr(di.dli_fname, "VADriver")) o += snprintf(l + o, sizeof l - o, " %lx", (unsigned long)((char *)bt[i] - (char *)di.dli_fbase)); }
    T("%{public}s", l);
    for (int k = 0; k < NCL; k++) { if (!G[s].res[k]) continue; const uint32_t *p = IOAccelResourceGetDataBytes(G[s].res[k]); T("classe %d res %llx usado %u tamanho %llu", k, G[s].res[k], G[s].used[k], IOAccelResourceGetDataSize(G[s].res[k])); if (p && G[s].used[k]) despeja(k, p, G[s].used[k]); }
    // 2o nivel: entre todos os recursos (criados pelo plugin OU buffers de dados por classe), os que contem MEDIA_OBJECT
    int achou = 0; uint64_t lista[NRES + NCL]; int nl = 0;
    for (int g = 0; g < 8; g++) for (int k = 0; k < NCL; k++) if (G[g].res[k]) lista[nl++] = G[g].res[k];   // todos os contextos
    for (int i = 0; i < gResN && nl < NRES + NCL; i++) if (gRes[i]) lista[nl++] = gRes[i];
    for (int i = 0; i < nl && achou < 3; i++) { const uint32_t *p = IOAccelResourceGetDataBytes(lista[i]); uint64_t sz = IOAccelResourceGetDataSize(lista[i]); if (!p || sz < 16 || sz > 0x400000) continue;
      uint32_t n = (uint32_t)(sz / 4), first = 0xffffffff, last = 0;
      for (uint32_t j = 0; j < n; j++) { if (p[j] == 0x7100000a && first == 0xffffffff) first = j; if (first == 0xffffffff) continue; if (p[j] == 0x7100000a || p[j] == 0x70040000) last = j; if (p[j] == 0x05000000) break; }
      if (first == 0xffffffff) continue;
      achou++; uint32_t ini = first > 64 ? first - 64 : 0, fim = last + 24 < n ? last + 24 : n;
      T("NIVEL2 res %llx tamanho %llu: MEDIA_OBJECT de +%x a +%x (%u dwords mostrados)", lista[i], sz, first * 4, last * 4, fim - ini);
      despeja(100 + i, p + ini, (fim - ini) * 4);
    }
    if (!achou) { T("NIVEL2: nenhum recurso com MEDIA_OBJECT entre %d recursos", nl); for (int i = 0; i < nl && i < 24; i++) { const uint32_t *p = IOAccelResourceGetDataBytes(lista[i]); T("  res %llx tamanho %llu primeiros %08x %08x %08x %08x", lista[i], IOAccelResourceGetDataSize(lista[i]), p ? p[0] : 0, p ? p[1] : 0, p ? p[2] : 0, p ? p[3] : 0); } }
  }
  if (gNoScore < 0) gNoScore = access("/tmp/xe-noscoreboard", F_OK) == 0;
  if (gNoScore == 1) for (int k = 0; k < NCL; k++) { if (!G[s].res[k] || !G[s].used[k]) continue; uint32_t *p = IOAccelResourceGetDataBytes(G[s].res[k]); if (!p) continue;
    uint32_t n = G[s].used[k] / 4; for (uint32_t i = 0; i + 8 < n; i++) if (p[i] == 0x70000007 && (p[i + 6] & 0x80000000)) { p[i + 6] = 0; p[i + 7] = 0; p[i + 8] = 0; static int nn; if (nn++ < 3) T("NOSCOREBOARD: MEDIA_VFE_STATE em classe %d +%x: scoreboard desligado", k, i * 4); } }
  return IOAccelVideoContextSubmitDataBuffers(a, b, c, d, e, f);
}
static const struct { const char *n; void *w; } HK[] = {
  {"_IOAccelVideoContextGetDataBufferResource", g_res},
  {"_IOAccelVideoContextSetDataBufferClassUsedBytes", g_used},
  {"_IOAccelVideoContextSubmitDataBuffers", g_sub},
  {"_IOAccelResourceCreate", g_rcreate},
  {"_IOAccelResourceRelease", g_rrelease},
};
static void rebind(const struct mach_header_64 *h, intptr_t slide) {
  const struct segment_command_64 *le = NULL; const struct symtab_command *st = NULL; const struct dysymtab_command *dy = NULL;
  const struct load_command *lc = (const void *)(h + 1);
  for (uint32_t i = 0; i < h->ncmds; i++, lc = (const void *)((const char *)lc + lc->cmdsize)) {
    if (lc->cmd == LC_SEGMENT_64 && !strcmp(((const struct segment_command_64 *)lc)->segname, "__LINKEDIT")) le = (const void *)lc;
    else if (lc->cmd == LC_SYMTAB) st = (const void *)lc; else if (lc->cmd == LC_DYSYMTAB) dy = (const void *)lc;
  }
  if (!le || !st || !dy) { T("rebind: comandos não achados"); return; }
  uintptr_t lb = (uintptr_t)slide + le->vmaddr - le->fileoff;
  const struct nlist_64 *sy = (const void *)(lb + st->symoff); const char *str = (const char *)(lb + st->stroff);
  const uint32_t *ind = (const uint32_t *)(lb + dy->indirectsymoff); int n = 0;
  lc = (const void *)(h + 1);
  for (uint32_t i = 0; i < h->ncmds; i++, lc = (const void *)((const char *)lc + lc->cmdsize)) {
    if (lc->cmd != LC_SEGMENT_64) continue;
    const struct segment_command_64 *sg = (const void *)lc; const struct section_64 *sc = (const void *)(sg + 1);
    for (uint32_t j = 0; j < sg->nsects; j++, sc++) {
      uint32_t ty = sc->flags & SECTION_TYPE;
      if (ty != S_LAZY_SYMBOL_POINTERS && ty != S_NON_LAZY_SYMBOL_POINTERS) continue;
      void **ptrs = (void **)((uintptr_t)slide + sc->addr); uint32_t cnt = (uint32_t)(sc->size / 8);
      uintptr_t pg = (uintptr_t)ptrs & ~0xfffUL; mprotect((void *)pg, ((uintptr_t)ptrs + sc->size - pg + 0xfff) & ~0xfffUL, PROT_READ | PROT_WRITE);
      for (uint32_t k = 0; k < cnt; k++) {
        uint32_t si = ind[sc->reserved1 + k]; if (si & (INDIRECT_SYMBOL_ABS | INDIRECT_SYMBOL_LOCAL)) continue;
        const char *nm = str + sy[si].n_un.n_strx;
        for (size_t q = 0; q < sizeof HK / sizeof *HK; q++) if (!strcmp(nm, HK[q].n)) { ptrs[k] = HK[q].w; n++; }
      }
    }
  }
  T("rebind: %d ponteiros redirecionados", n);
}
static void added(const struct mach_header *mh, intptr_t slide) {
  // só o binário do driver (o caminho desta biblioteca também contém "AppleIntelTGLGraphicsVADriver": não se redirecionar)
  Dl_info di; if (!dladdr(mh, &di) || !di.dli_fname) return;
  size_t n = strlen(di.dli_fname), m = strlen("/MacOS/AppleIntelTGLGraphicsVADriver");
  if (n < m || strcmp(di.dli_fname + n - m, "/MacOS/AppleIntelTGLGraphicsVADriver")) return;
  T("driver de vídeo carregado: %{public}s", di.dli_fname); rebind((const struct mach_header_64 *)mh, slide);
}
__attribute__((constructor)) static void init(void) {
  L = os_log_create("xe.vadump", "va"); T("xe-vadump carregado em %{public}s", getprogname());
  _dyld_register_func_for_add_image(added);
}

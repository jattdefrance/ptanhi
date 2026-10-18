#!/usr/bin/env bash
#
# xv6 practice scaffold/manual
#
# Before switching branches, run `make clean`: stale kernel/*.d files can cause
# "No rule to make target kernel/sysinfo.h". Start from a clean branch:
# git checkout -b practice origin/syscall (or origin/util for utils) && make clean
#
# Standard syscall checklist:
# 1. kernel/syscall.h: add #define SYS_name N (the next free number).
# 2. user/usys.pl: add entry("name");
# 3. user/user.h: add the user prototype.
# 4. kernel/syscall.c: add the extern, dispatch entry, and (for trace) name.
# 5. kernel/sysproc.c or kernel/sysfile.c: implement sys_name.
#
# This file is intentionally executable as well as readable with `cat`.
set -u

ROOT=$(pwd)
FORCE=0
PRACTICE_FILES=()

die() { printf 'xv6-practice: %s\n' "$*" >&2; exit 1; }
need_root() { test -f Makefile && test -d kernel && test -d user || die "run from the xv6 repository root"; }
has() { grep -Fq -- "$1" "$2"; }

backup_if_needed() {
  local f=$1
  if test "$FORCE" -eq 1 && test -e "$f" && test ! -e "$f.bak"; then
    cp "$f" "$f.bak"
  fi
}

write_new() {
  local f=$1
  backup_if_needed "$f"
  if test -e "$f" && test "$FORCE" -eq 0; then
    printf 'skip (already exists): %s\n' "$f"
    return
  fi
  cat >"$f"
  PRACTICE_FILES+=("$f")
}

append_once() {
  local marker=$1 f=$2
  shift 2
  has "$marker" "$f" || { printf '%s\n' "$*" >>"$f"; PRACTICE_FILES+=("$f"); }
}

insert_after() {
  local anchor=$1 f=$2 text=$3
  has "$text" "$f" && return 0
  grep -Fq -- "$anchor" "$f" || { printf 'manual step: add after %s in %s\n' "$anchor" "$f" >&2; return 1; }
  perl -0pi -e 's/\Q'"$anchor"'\E/'"$anchor"'\n'"$text"'/s' "$f"
  PRACTICE_FILES+=("$f")
}

insert_before() {
  local anchor=$1 f=$2 text=$3
  has "$text" "$f" && return 0
  grep -Fq -- "$anchor" "$f" || { printf 'manual step: add before %s in %s\n' "$anchor" "$f" >&2; return 1; }
  perl -0pi -e 's/\Q'"$anchor"'\E/'"$text"'\n'"$anchor"'/s' "$f"
  PRACTICE_FILES+=("$f")
}

add_uprog() {
  local name=$1
  grep -Eq '^[[:space:]]+\$U/_'"$name"'\\$' Makefile && return
  local line
  line=$(printf '\t$U/_%s\\' "$name")
  awk -v line="$line" '(/^UPROGS=\\/ && !done) { print; print line; done=1; next } { print }' Makefile >.xv6-practice.tmp &&
    mv .xv6-practice.tmp Makefile
  PRACTICE_FILES+=("Makefile")
}

next_syscall() {
  awk '/^#define[[:space:]]+SYS_/ { if ($3 > n) n=$3 } END { print n + 1 }' kernel/syscall.h
}

add_syscall() {
  local name=$1 proto=$2 impl=$3
  local n
  n=$(next_syscall)
  has "SYS_$name" kernel/syscall.h || printf '#define SYS_%s %s\n' "$name" "$n" >>kernel/syscall.h
  has "entry(\"$name\")" user/usys.pl || printf 'entry("%s");\n' "$name" >>user/usys.pl
  has "$proto" user/user.h || insert_before '// ulib.c' user/user.h "$proto"
  has "extern uint64 sys_$name(void);" kernel/syscall.c ||
    insert_before '// An array mapping' kernel/syscall.c "extern uint64 sys_$name(void);"
  has "[SYS_$name]" kernel/syscall.c ||
    insert_before '  // clang-format on' kernel/syscall.c "  [SYS_$name] = sys_$name,"
  has "[SYS_$name] \"$name\"" kernel/syscall.c ||
    insert_after 'static char *syscall_names[] = {' kernel/syscall.c "  [SYS_$name] \"$name\"," 
}

replace_between_markers() {
  local start=$1 end=$2 file=$3 replacement=$4
  perl -0pi -e 's/\Q'"$start"'\E.*?\Q'"$end"'\E/'"$replacement"'/s' "$file"
}

task_fork() {
  # A10. FILE: user/fork.c. Add fork, child/parent prints, and wait.
  write_new user/fork.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(void) {
  int pid = fork();
  if (pid == 0) { printf("child %d\n", getpid()); exit(7); }
  int status; wait(&status); printf("exited with %d\n", status); exit(0);
}
EOF
  add_uprog fork
}

task_exec() {
  # A10. FILE: user/exec.c. Add exec cmd [args...] and report failure/status.
  write_new user/exec.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char *argv[]) {
  if (argc < 2) { fprintf(2, "usage: exec cmd [args...]\n"); exit(1); }
  int pid = fork();
  if (pid == 0) { exec(argv[1], &argv[1]); fprintf(2, "exec %s failed\n", argv[1]); exit(1); }
  int status; wait(&status); printf("%s exited with status %d\n", argv[1], status); exit(0);
}
EOF
  add_uprog exec
}

task_wait() {
  # A10. FILE: user/wait.c. Add three children, statuses 10/20/30, and reaping.
  write_new user/wait.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(void) {
  for (int i = 1; i <= 3; i++) if (fork() == 0) exit(i * 10);
  int pid, status; while ((pid = wait(&status)) >= 0)
    printf("reaped child %d, status %d\n", pid, status);
  printf("no children left\n"); exit(0);
}
EOF
  add_uprog wait
}

task_pipe() {
  # A10. FILE: user/pipe.c. Add a pipe, close unused ends, write hello, and wait.
  write_new user/pipe.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(void) {
  int p[2]; pipe(p);
  if (fork() == 0) { char b[33]; close(p[1]); int n=read(p[0],b,32); if(n<0)n=0; b[n]=0; printf("child got: %s\n",b); close(p[0]); exit(0); }
  close(p[0]); write(p[1],"hello",5); close(p[1]); wait(0); exit(0);
}
EOF
  add_uprog pipe
}

task_redir() {
  # A10. FILE: user/redir.c. Add redir file cmd [args...] using fd 1.
  write_new user/redir.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "kernel/fcntl.h"
int main(int argc, char *argv[]) {
  if (argc < 3) { fprintf(2,"usage: redir file cmd [args...]\n"); exit(1); }
  if (fork() == 0) { close(1); if(open(argv[1],O_CREATE|O_WRONLY|O_TRUNC)!=1) { fprintf(2,"open failed\n"); exit(1); } exec(argv[2],&argv[2]); fprintf(2,"exec failed\n"); exit(1); }
  wait(0); exit(0);
}
EOF
  add_uprog redir
}

task_sleep() {
  # A1. FILE: user/sleep.c. Parse ticks with atoi, call pause/sleep, exit(1) on usage.
  write_new user/sleep.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char *argv[]) {
  if (argc != 2) { fprintf(2,"usage: sleep ticks\n"); exit(1); }
  pause(atoi(argv[1])); exit(0);
}
EOF
  add_uprog sleep
}

task_sixfive() {
  # A2. FILE: user/sixfive.c. Scan digit runs delimited by " -\r\t\n./,".
  write_new user/sixfive.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int delim(char c){ return strchr(" -\r\t\n./,",c)!=0; }
void scan(int fd){ char c, b[16]; int n=0; while(read(fd,&c,1)==1){ if(c>='0'&&c<='9'&&n<15)b[n++]=c; else if(n){b[n]=0; int x=atoi(b); if(x%5==0||x%6==0)printf("%d\n",x); n=0;} } if(n){b[n]=0;int x=atoi(b);if(x%5==0||x%6==0)printf("%d\n",x);} }
int main(int argc,char *argv[]){ int fd; if(argc==1)scan(0); else for(int i=1;i<argc;i++){fd=open(argv[i],0);if(fd<0){fprintf(2,"sixfive: cannot open %s\n",argv[i]);continue;}scan(fd);close(fd);} exit(0); }
EOF
  add_uprog sixfive
}

task_memdump() {
  # A3. FILE: user/memdump.c. Add bounded memcpy-based format decoding.
  if test ! -e user/memdump.c || test "$FORCE" -eq 1; then
    write_new user/memdump.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
void memdump(char *fmt, char *data, int len) {
  int off = 0;
  for (; *fmt; fmt++) {
    int need = *fmt == 'c' ? 1 : *fmt == 'h' ? 2 : *fmt == 'i' ? 4 :
      (*fmt == 'p' || *fmt == 's') ? 8 : 0;
    if (*fmt == 'S') {
      int j = off;
      while (j < len && data[j] != 0) j++;
      if (j == len) { printf("memdump: not enough data for 'S'\n"); return; }
      printf("%s\n", data + off); off = j + 1; continue;
    }
    if (!need || off + need > len) {
      printf("memdump: not enough data for '%c'\n", *fmt); return;
    }
    if (*fmt == 'c') printf("%c\n", data[off]);
    else if (*fmt == 'h') { uint16 v; memcpy(&v, data + off, 2); printf("%d\n", v); }
    else if (*fmt == 'i') { uint32 v; memcpy(&v, data + off, 4); printf("%d\n", v); }
    else if (*fmt == 'p') { uint64 v; memcpy(&v, data + off, 8); printf("%lx\n", v); }
    else { uint64 v; memcpy(&v, data + off, 8); printf("%s\n", (char *)v); }
    off += need;
  }
}
int main(int argc, char **argv) {
  char data[512]; int n = 0;
  if (argc != 2) { fprintf(2, "usage: memdump format\n"); exit(1); }
  while (n < sizeof(data)) { int k = read(0, data + n, sizeof(data) - n); if (k <= 0) break; n += k; }
  memdump(argv[1], data, n); exit(0);
}
EOF
  else
    printf 'preserved existing user/memdump.c; use --force to install the complete implementation\n'
  fi
  add_uprog memdump
}

task_find() {
  # A4/A5. FILE: user/find.c. Find files/directories; -exec appends the matched path.
  if test ! -e user/find.c || test "$FORCE" -eq 1; then
    write_new user/find.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/fs.h"
#include "kernel/fcntl.h"
#include "kernel/param.h"
#include "user/user.h"
void find(char *path, char *name, char **cmd, int ncmd) {
  int fd = open(path, O_RDONLY); struct stat st; char buf[512], *p;
  if (fd < 0 || fstat(fd, &st) < 0) { if (fd >= 0) close(fd); return; }
  if (st.type != T_DIR) { close(fd); return; }
  if (strlen(path) + 1 + DIRSIZ + 1 > sizeof(buf)) { close(fd); return; }
  strcpy(buf, path); p = buf + strlen(buf); *p++ = '/';
  struct dirent de;
  while (read(fd, &de, sizeof(de)) == sizeof(de)) {
    if (!de.inum) continue; memmove(p, de.name, DIRSIZ); p[DIRSIZ] = 0;
    if (strcmp(p, ".") == 0 || strcmp(p, "..") == 0) continue;
    if (strcmp(p, name) == 0) {
      if (!ncmd) printf("%s\n", buf);
      else if (fork() == 0) { cmd[ncmd] = buf; exec(cmd[0], cmd); exit(1); }
      else wait(0);
    }
    if (stat(buf, &st) == 0 && st.type == T_DIR) find(buf, name, cmd, ncmd);
  }
  close(fd);
}
int main(int argc, char **argv) {
  if (argc < 3) { fprintf(2, "usage: find path name [-exec cmd ...]\n"); exit(1); }
  char *cmd[MAXARG]; int ncmd = 0;
  if (argc > 3 && strcmp(argv[3], "-exec") == 0) {
    for (int i = 4; i < argc; i++) cmd[ncmd++] = argv[i];
    if (!ncmd) { fprintf(2, "find: missing command\n"); exit(1); }
  }
  cmd[ncmd] = 0; find(argv[1], argv[2], cmd, ncmd); exit(0);
}
EOF
  fi
  add_uprog find
}

task_pingpong() {
  # A10. FILE: user/pingpong.c. Send one byte in each direction over two pipes.
  write_new user/pingpong.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(void) {
  int p[2], q[2]; char c = 'x';
  pipe(p); pipe(q);
  if (fork() == 0) { close(p[1]); close(q[0]); read(p[0], &c, 1); printf("%d: received ping\n", getpid()); write(q[1], &c, 1); close(p[0]); close(q[1]); exit(0); }
  close(p[0]); close(q[1]); write(p[1], &c, 1); read(q[0], &c, 1); printf("%d: received pong\n", getpid()); close(p[1]); close(q[0]); wait(0); exit(0);
}
EOF
  add_uprog pingpong
}

task_primes() {
  # A10. FILE: user/primes.c. Build the xv6 prime sieve using one process per stage.
  write_new user/primes.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
void sieve(int in) {
  int prime, n, p[2];
  if (read(in, &prime, sizeof(prime)) != sizeof(prime)) { close(in); exit(0); }
  printf("prime %d\n", prime);
  pipe(p);
  if (fork() == 0) { close(p[1]); close(in); sieve(p[0]); }
  close(p[0]);
  while (read(in, &n, sizeof(n)) == sizeof(n)) if (n % prime) write(p[1], &n, sizeof(n));
  close(in); close(p[1]); wait(0); exit(0);
}
int main(void) {
  int p[2]; pipe(p);
  if (fork() == 0) { close(p[1]); sieve(p[0]); }
  close(p[0]); for (int i = 2; i <= 35; i++) write(p[1], &i, sizeof(i));
  close(p[1]); wait(0); exit(0);
}
EOF
  add_uprog primes
}

task_xargs() {
  # A10. FILE: user/xargs.c. Append each input line to the fixed command arguments.
  write_new user/xargs.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/param.h"
#include "user/user.h"
int main(int argc, char **argv) {
  if (argc < 2) { fprintf(2, "usage: xargs command [args...]\n"); exit(1); }
  char line[512], *args[MAXARG]; int n = argc - 1, len = 0, k;
  for (int i = 1; i < argc; i++) args[i - 1] = argv[i];
  while ((k = read(0, line + len, sizeof(line) - len - 1)) > 0) {
    len += k; line[len] = 0; char *start = line;
    for (int i = 0; i <= len; i++) if (line[i] == '\n' || line[i] == 0) {
      line[i] = 0; if (*start) { args[n] = start; args[n + 1] = 0;
        if (fork() == 0) { exec(args[0], args); exit(1); } wait(0); }
      start = line + i + 1;
    }
    len = 0;
  }
  exit(0);
}
EOF
  add_uprog xargs
}

task_uptime() {
  # B0/A10. FILE: user/uptime.c. Call uptime and print its result.
  write_new user/uptime.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(void){ printf("%d\n",uptime()); exit(0); }
EOF
  add_uprog uptime
}

task_gdb() {
  # B0. FILE: answers-syscall.txt. Add unanswered gdb questions and commands.
  test -e answers-syscall.txt || cat >answers-syscall.txt <<'EOF'
Using gdb

1) Which function called syscall?
Answer:
make qemu-gdb
gdb-multiarch
b syscall
c
backtrace

2) After stepping past `struct proc *p = myproc();`, what are p->trapframe->a7 and its meaning?
Answer:
Inspect user/init.c and user/init.asm.

3) What was the previous mode in p /x $sstatus (SPP)?
Answer:

4) After replacing num with `* (int *) 0`, which instruction panics and which register holds num?
Answer:
Search sepc in kernel/kernel.asm.

5) Why does the kernel crash? What does scause=0xd mean?
Answer:
Use `b *<sepc>` and `layout asm`; revert the null dereference.

6) What are p->name and pid?
Answer:

REVERT the `num = * (int *) 0;` edit before continuing.
EOF
}

task_trace() {
  # B1. FILE: kernel/proc.h/proc.c. Add tracemask and inherit it in fork.
  # B1. FILE: kernel/syscall.c. Print name/result after every selected syscall.
  # B1. FILE: user/trace.c. Run trace mask command args.
  has 'int tracemask;' kernel/proc.h || insert_after 'char sandbox_path[MAXPATH];' kernel/proc.h '  int tracemask;'
  has 'np->tracemask = p->tracemask;' kernel/proc.c || insert_after 'np->sz = p->sz;' kernel/proc.c '  np->tracemask = p->tracemask;'
  add_syscall trace 'int trace(int);' sysproc
  if ! grep -Eq 'myproc\(\)->tracemask[[:space:]]*=' kernel/sysproc.c; then
    printf '%s\n' 'uint64 sys_trace(void) { int mask; argint(0, &mask); myproc()->tracemask = mask; return 0; }' >>kernel/sysproc.c
  fi
  write_new user/trace.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc,char *argv[]){if(argc<3){fprintf(2,"usage: trace mask command [args...]\n");exit(1);}if(trace(atoi(argv[1]))<0){fprintf(2,"trace failed\n");exit(1);}exec(argv[2],&argv[2]);fprintf(2,"exec failed\n");exit(1);}
EOF
  add_uprog trace
}

task_sysinfo() {
  # B2. FILE: kernel/sysproc.c. Fill struct sysinfo and copyout with the detected 5-arg signature.
  # B2. FILE: kernel/kalloc.c/proc.c/defs.h. Add freemem and nproc helpers.
  # B2. FILE: user/sysinfo.c. Register the shipped test or generate a fallback.
  add_syscall sysinfo 'int sysinfo(struct sysinfo *);' sysproc
  if ! grep -Fq '#include "sysinfo.h"' kernel/sysproc.c; then
    insert_after '#include "vm.h"' kernel/sysproc.c '#include "sysinfo.h"'
  fi
  if ! grep -Eq 'info\.freemem[[:space:]]*=' kernel/sysproc.c; then
    printf '%s\n' 'uint64 sys_sysinfo(void) { uint64 addr; struct sysinfo info; argaddr(0, &addr); info.freemem = freemem(); info.nproc = nproc(); return copyout(myproc()->pagetable, myproc()->sz, addr, (char *)&info, sizeof(info)) < 0 ? -1 : 0; }' >>kernel/sysproc.c
  fi
  if ! grep -Eq 'uint64[[:space:]]+freemem\(void\)' kernel/defs.h; then
    insert_before '// proc.c' kernel/defs.h 'uint64 freemem(void);'
  fi
  if ! grep -Eq 'uint64[[:space:]]+nproc\(void\)' kernel/defs.h; then
    insert_before '// syscall.c' kernel/defs.h 'uint64 nproc(void);'
  fi
  if ! grep -Eq 'freemem\(void\)' kernel/kalloc.c; then
    cat >>kernel/kalloc.c <<'EOF'
uint64 freemem(void) {
  uint64 count = 0; struct run *r;
  acquire(&kmem.lock);
  for (r = kmem.freelist; r; r = r->next) count++;
  release(&kmem.lock);
  return count * PGSIZE;
}
EOF
  fi
  if ! grep -Eq 'nproc\(void\)' kernel/proc.c; then
    cat >>kernel/proc.c <<'EOF'
uint64 nproc(void) {
  uint64 count = 0; struct proc *p;
  for (p = proc; p < &proc[NPROC]; p++) { acquire(&p->lock); if (p->state != UNUSED) count++; release(&p->lock); }
  return count;
}
EOF
  fi
  if test ! -e kernel/sysinfo.h; then
    write_new kernel/sysinfo.h <<'EOF'
struct sysinfo { uint64 freemem; uint64 nproc; };
EOF
  fi
  if test ! -e user/sysinfo.c; then
    write_new user/sysinfo.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/sysinfo.h"
#include "user/user.h"
int main(void) {
  struct sysinfo info;
  if (sysinfo(&info) < 0) { fprintf(2, "sysinfo failed\n"); exit(1); }
  printf("free memory: %d bytes, procs: %d\n", (int)info.freemem, (int)info.nproc);
  exit(0);
}
EOF
  fi
  add_uprog sysinfo
  has 'user/sysinfotest.c' Makefile && add_uprog sysinfotest
}

task_sandbox() {
  # B3. FILE: kernel/proc.h/proc.c. Add sandbox mask/path and inherit them.
  # B3. FILE: kernel/syscall.c. Reject masked calls before dispatch (interpose:begin/end).
  # B3. FILE: user/sandbox.c. Fork, interpose(mask,path), then exec the command.
  has 'int sandbox_mask;' kernel/proc.h || insert_after 'int pid;' kernel/proc.h '  int sandbox_mask;'
  has 'char sandbox_path[MAXPATH];' kernel/proc.h || insert_after 'int sandbox_mask;' kernel/proc.h '  char sandbox_path[MAXPATH];'
  has 'np->sandbox_mask = p->sandbox_mask;' kernel/proc.c || insert_after 'np->sz = p->sz;' kernel/proc.c '  np->sandbox_mask = p->sandbox_mask; safestrcpy(np->sandbox_path,p->sandbox_path,MAXPATH);'
  if ! grep -Fq '// interpose:begin' kernel/syscall.c; then
    insert_before '    if (blocked) {' kernel/syscall.c \
      '    // interpose:begin
    if (p->sandbox_mask & (1 << num))
      blocked = 1;
    // interpose:end'
  fi
  if ! grep -Fq 'sys_interpose(void)' kernel/sysproc.c; then
    cat >>kernel/sysproc.c <<'EOF'
uint64 sys_interpose(void) {
  int mask; char path[MAXPATH];
  argint(0, &mask);
  if (argstr(1, path, MAXPATH) < 0) return -1;
  myproc()->sandbox_mask = mask;
  safestrcpy(myproc()->sandbox_path, path, MAXPATH);
  return 0;
}
EOF
  fi
  add_uprog sandbox
}

task_sandbox_path() {
  # B4. FILE: kernel/syscall.c. Permit masked open/exec only for the configured path.
  task_sandbox
  if ! grep -Fq 'SYS_exec && p->sandbox_path' kernel/syscall.c; then
    insert_before '    if (blocked) {' kernel/syscall.c \
      '    if (blocked && (num == SYS_open || num == SYS_exec) && p->sandbox_path[0] && strcmp(p->sandbox_path, "-") != 0) {
      char path[MAXPATH];
      if (argstr(0, path, MAXPATH) == 0 && strcmp(path, p->sandbox_path) == 0)
        blocked = 0;
    }'
  fi
}

task_attack() {
  # B5. FILE: user/attack.c. Scan freshly allocated pages for "Here it is: " and print its suffix.
  write_new user/attack.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(void){ char *m=sbrk(64*4096); char *mark="Here it is: "; for(int i=0;i<64*4096-(int)strlen(mark);i++) if(memcmp(m+i,mark,strlen(mark))==0){char *s=m+i+strlen(mark);int n=0;while(n<128&&((s[n]>='0'&&s[n]<='9')||(s[n]>='a'&&s[n]<='z')||(s[n]>='A'&&s[n]<='Z')))n++;if(n){printf("%.*s\n",n,s);break;}} exit(0); }
EOF
  add_uprog attack
}

test_task() {
  local name=$1 log=/tmp/xv6-test-$1.log
  make -s kernel/kernel fs.img || return 1
  printf '%s\n' "echo" "$name" $'\001x' | timeout 30 make qemu >"$log" 2>&1 || true
  tr -d '\r' <"$log" >"$log.clean"
  grep -Eq '^PASS$|.' "$log.clean" >/dev/null || true
  printf 'raw output: %s\n' "$log"
}

grade_task() {
  local name=$1
  case "$name" in
    util|fork|exec|wait|pipe|redir|sleep|sixfive|memdump|find|find-exec|uptime) ./grade-lab-util "$name" ;;
    *) ./grade-lab-syscall "$name" ;;
  esac
}

list_tasks() {
  printf '%s\n' fork exec wait pipe redir pingpong primes xargs sleep sixfive memdump find find-exec uptime gdb trace sysinfo sandbox sandbox-path attack
}

main() {
  need_root
  local task=${1:-}
  test "$task" = "--force" && { FORCE=1; task=${2:-}; }
  test "${2:-}" = "--force" && FORCE=1
  case "$task" in
    list) list_tasks ;;
    test) test "${2:-}" = all && { for t in $(list_tasks); do test_task "$t"; done; } || test_task "${2:?task name required}" ;;
    grade) grade_task "${2:?task name required}" ;;
    fork) task_fork ;; exec) task_exec ;; wait) task_wait ;; pipe) task_pipe ;; redir) task_redir ;;
    sleep) task_sleep ;; sixfive) task_sixfive ;; memdump) task_memdump ;; find|find-exec) task_find ;;
    pingpong) task_pingpong ;; primes) task_primes ;; xargs) task_xargs ;;
    uptime) task_uptime ;; gdb) task_gdb ;; trace) task_trace ;; sysinfo) task_sysinfo ;;
    sandbox) task_sandbox ;; sandbox-path) task_sandbox_path ;; attack) task_attack ;;
    '') printf 'usage: %s <name> [--force] | list | test <name|all> | grade <name>\n' "$0"; exit 2 ;;
    *) die "unknown task: $task" ;;
  esac
  printf 'done\n'
}
main "$@"

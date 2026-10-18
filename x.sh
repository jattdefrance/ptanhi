#!/usr/bin/env bash

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

replace_between_markers() {
  local start=$1 end=$2 file=$3 replacement=$4
  perl -0pi -e 's/\Q'"$start"'\E.*?\Q'"$end"'\E/'"$replacement"'/s' "$file"
}

task_myecho() {
  write_new user/myecho.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  for (int i = 1; i < argc; i++) {
    if (i > 1) printf(" ");
    printf("%s", argv[i]);
  }
  printf("\n");
  exit(0);
}
EOF
  add_uprog myecho
}

task_sumargs() {
  write_new user/sumargs.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  int sum = 0;
  for (int i = 1; i < argc; i++) sum += atoi(argv[i]);
  printf("%d\n", sum);
  exit(0);
}
EOF
  add_uprog sumargs
}

task_repeat() {
  write_new user/repeat.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  if (argc != 3) { fprintf(2, "usage: repeat N word\n"); exit(1); }
  for (int i = 0; i < atoi(argv[1]); i++) printf("%s\n", argv[2]);
  exit(0);
}
EOF
  add_uprog repeat
}

task_countdown() {
  write_new user/countdown.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  if (argc != 2) { fprintf(2, "usage: countdown N\n"); exit(1); }
  for (int i = atoi(argv[1]); i > 0; i--) {
    printf("%d\n", i);
    pause(10);
  }
  printf("liftoff\n");
  exit(0);
}
EOF
  add_uprog countdown
}

task_later() {
  write_new user/later.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  if (argc != 3) { fprintf(2, "usage: later ticks word\n"); exit(1); }
  pause(atoi(argv[1]));
  printf("%s\n", argv[2]);
  exit(0);
}
EOF
  add_uprog later
}

task_forktwice() {
  write_new user/forktwice.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(void) {
  int first = fork();
  int second = fork();
  printf("%d\n", getpid());
  if (first > 0) wait(0);
  if (second > 0) wait(0);
  exit(0);
}
EOF
  add_uprog forktwice
}

task_exitcode() {
  write_new user/exitcode.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  int status;
  if (argc != 2) { fprintf(2, "usage: exitcode N\n"); exit(1); }
  if (fork() == 0) exit(atoi(argv[1]));
  wait(&status);
  printf("child exited with %d\n", status);
  exit(0);
}
EOF
  add_uprog exitcode
}

task_twice() {
  write_new user/twice.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  if (argc < 2) { fprintf(2, "usage: twice command [args...]\n"); exit(1); }
  for (int i = 0; i < 2; i++) {
    if (fork() == 0) { exec(argv[1], &argv[1]); exit(1); }
    wait(0);
  }
  exit(0);
}
EOF
  add_uprog twice
}

task_double() {
  write_new user/double.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  int p[2], value, result;
  if (argc != 2) { fprintf(2, "usage: double N\n"); exit(1); }
  value = atoi(argv[1]);
  pipe(p);
  if (fork() == 0) {
    close(p[1]);
    read(p[0], &value, sizeof(value));
    result = value * 2;
    printf("%d\n", result);
    close(p[0]);
    exit(0);
  }
  close(p[0]);
  write(p[1], &value, sizeof(value));
  close(p[1]);
  wait(0);
  exit(0);
}
EOF
  add_uprog double
}

task_mycat() {
  write_new user/mycat.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  char buf[512];
  int fd, n;
  if (argc != 2) { fprintf(2, "usage: mycat file\n"); exit(1); }
  fd = open(argv[1], 0);
  if (fd < 0) { fprintf(2, "mycat: cannot open %s\n", argv[1]); exit(1); }
  while ((n = read(fd, buf, sizeof(buf))) > 0) write(1, buf, n);
  close(fd);
  exit(0);
}
EOF
  add_uprog mycat
}

task_lines() {
  write_new user/lines.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  char buf[512];
  int fd, n, count = 0;
  if (argc != 2) { fprintf(2, "usage: lines file\n"); exit(1); }
  fd = open(argv[1], 0);
  if (fd < 0) { fprintf(2, "lines: cannot open %s\n", argv[1]); exit(1); }
  while ((n = read(fd, buf, sizeof(buf))) > 0)
    for (int i = 0; i < n; i++) if (buf[i] == '\n') count++;
  close(fd);
  printf("%d\n", count);
  exit(0);
}
EOF
  add_uprog lines
}

task_touch() {
  write_new user/touch.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/fcntl.h"
#include "user/user.h"
int main(int argc, char **argv) {
  int fd;
  if (argc != 2) { fprintf(2, "usage: touch file\n"); exit(1); }
  fd = open(argv[1], O_CREATE | O_WRONLY);
  if (fd < 0) { fprintf(2, "touch: cannot create %s\n", argv[1]); exit(1); }
  close(fd);
  exit(0);
}
EOF
  add_uprog touch
}

task_mywrite() {
  write_new user/mywrite.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/fcntl.h"
#include "user/user.h"
int main(int argc, char **argv) {
  int fd;
  if (argc != 3) { fprintf(2, "usage: mywrite file text\n"); exit(1); }
  fd = open(argv[1], O_CREATE | O_WRONLY | O_TRUNC);
  if (fd < 0) { fprintf(2, "mywrite: cannot open %s\n", argv[1]); exit(1); }
  fprintf(fd, "%s\n", argv[2]);
  close(fd);
  exit(0);
}
EOF
  add_uprog mywrite
}

task_myrm() {
  write_new user/myrm.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  if (argc != 2) { fprintf(2, "usage: myrm file\n"); exit(1); }
  if (unlink(argv[1]) < 0) {
    fprintf(2, "myrm: cannot remove %s\n", argv[1]);
    exit(1);
  }
  exit(0);
}
EOF
  add_uprog myrm
}

task_kind() {
  write_new user/kind.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  int fd;
  struct stat st;
  if (argc != 2) { fprintf(2, "usage: kind path\n"); exit(1); }
  fd = open(argv[1], 0);
  if (fd < 0 || fstat(fd, &st) < 0) { fprintf(2, "kind: cannot stat %s\n", argv[1]); exit(1); }
  if (st.type == T_DIR) printf("directory\n");
  else if (st.type == T_FILE) printf("file\n");
  else if (st.type == T_DEVICE) printf("device\n");
  close(fd);
  exit(0);
}
EOF
  add_uprog kind
}

task_fsize() {
  write_new user/fsize.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  int fd;
  struct stat st;
  if (argc != 2) { fprintf(2, "usage: fsize file\n"); exit(1); }
  fd = open(argv[1], 0);
  if (fd < 0 || fstat(fd, &st) < 0) { fprintf(2, "fsize: cannot stat %s\n", argv[1]); exit(1); }
  printf("%d\n", (int)st.size);
  close(fd);
  exit(0);
}
EOF
  add_uprog fsize
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
  cat <<'EOF'
TRACE SYSCALL - MANUAL IMPLEMENTATION

Edit kernel/proc.h: add int tracemask; inside struct proc.
Edit kernel/proc.c: initialize p->tracemask = 0 in allocproc(), and copy
np->tracemask = p->tracemask in kfork().

Edit kernel/syscall.h:
  #define SYS_trace 24

Edit user/usys.pl:
  entry("trace");

Edit user/user.h:
  int trace(int);

Edit kernel/syscall.c:
  extern uint64 sys_trace(void);
  [SYS_trace] = sys_trace,
  [SYS_trace] "trace",

After p->trapframe->a0 = syscalls[num](); add:
  if (num < 32 && (p->tracemask & (1 << num))) {
    printk("%d: syscall %s -> %d\n",
           p->pid, syscall_names[num], (int)p->trapframe->a0);
  }

Add this function to kernel/sysproc.c:
  uint64
  sys_trace(void)
  {
    int mask;
    argint(0, &mask);
    myproc()->tracemask = mask;
    return 0;
  }

Create user/trace.c with:
  #include "kernel/types.h"
  #include "kernel/stat.h"
  #include "user/user.h"

  int
  main(int argc, char *argv[])
  {
    if (argc < 3) {
      fprintf(2, "usage: trace mask command [args...]\n");
      exit(1);
    }
    if (trace(atoi(argv[1])) < 0) {
      fprintf(2, "trace: syscall failed\n");
      exit(1);
    }
    exec(argv[2], &argv[2]);
    fprintf(2, "trace: exec %s failed\n", argv[2]);
    exit(1);
  }

Add $U/_trace\ to UPROGS in Makefile, then run make clean && make qemu.
EOF
}

task_sysinfo() {
  cat <<'EOF'
SYSINFO SYSCALL - MANUAL IMPLEMENTATION

Create kernel/sysinfo.h:
  struct sysinfo {
    uint64 freemem;
    uint64 nproc;
  };

Add to kernel/defs.h:
  uint64 freemem(void);
  uint64 nproc(void);

Add to kernel/syscall.h:
  #define SYS_sysinfo 25

Add to user/usys.pl:
  entry("sysinfo");

Add to user/user.h:
  struct sysinfo;
  int sysinfo(struct sysinfo *);

Add to kernel/syscall.c:
  extern uint64 sys_sysinfo(void);
  [SYS_sysinfo] = sys_sysinfo,

Add #include "sysinfo.h" to kernel/sysproc.c, then add:
  uint64
  sys_sysinfo(void)
  {
    uint64 address;
    struct sysinfo info;
    struct proc *p = myproc();

    argaddr(0, &address);
    info.freemem = freemem();
    info.nproc = nproc();
    if (copyout(p->pagetable, p->sz, address,
                (char *)&info, sizeof(info)) < 0)
      return -1;
    return 0;
  }

Add to kernel/kalloc.c:
  uint64
  freemem(void)
  {
    uint64 count = 0;
    struct run *r;
    acquire(&kmem.lock);
    for (r = kmem.freelist; r != 0; r = r->next)
      count++;
    release(&kmem.lock);
    return count * PGSIZE;
  }

Add to kernel/proc.c:
  uint64
  nproc(void)
  {
    uint64 count = 0;
    struct proc *p;
    for (p = proc; p < &proc[NPROC]; p++) {
      acquire(&p->lock);
      if (p->state != UNUSED)
        count++;
      release(&p->lock);
    }
    return count;
  }

Create user/sysinfo.c:
  #include "kernel/types.h"
  #include "kernel/stat.h"
  #include "kernel/sysinfo.h"
  #include "user/user.h"

  int
  main(void)
  {
    struct sysinfo info;
    if (sysinfo(&info) < 0) {
      fprintf(2, "sysinfo: syscall failed\n");
      exit(1);
    }
    printf("free memory: %ld bytes, processes: %ld\n",
           info.freemem, info.nproc);
    exit(0);
  }

Add $U/_sysinfo\ to UPROGS in Makefile, then run make clean && make qemu.
EOF
}

task_sandbox() {
  cat <<'EOF'
SANDBOX/INTERPOSE - MANUAL IMPLEMENTATION

In kernel/proc.h, inside struct proc, add:
  int sandbox_mask;
  char sandbox_path[MAXPATH];

In kernel/proc.c, initialize in allocproc():
  p->sandbox_mask = 0;
  p->sandbox_path[0] = 0;

Copy in kfork():
  np->sandbox_mask = p->sandbox_mask;
  safestrcpy(np->sandbox_path, p->sandbox_path, MAXPATH);

Add to kernel/syscall.h:
  #define SYS_interpose 23

Add to user/usys.pl:
  entry("interpose");

Add to user/user.h:
  int interpose(int, const char *);

Add to kernel/syscall.c:
  extern uint64 sys_interpose(void);
  [SYS_interpose] = sys_interpose,

Before dispatch in syscall(), add:
  int blocked = p->sandbox_mask & (1 << num);
  if ((num == SYS_open || num == SYS_exec) &&
      p->sandbox_path[0] != 0 &&
      strncmp(p->sandbox_path, "-", MAXPATH) != 0) {
    char path[MAXPATH];
    if (argstr(0, path, MAXPATH) < 0)
      blocked = 1;
    else if (num == SYS_open)
      blocked = strncmp(path, p->sandbox_path, MAXPATH) != 0;
    else if (num == SYS_exec && blocked)
      blocked = strncmp(path, p->sandbox_path, MAXPATH) != 0;
  }
  if (blocked) {
    p->trapframe->a0 = -1;
    return;
  }

Add to kernel/sysproc.c:
  uint64
  sys_interpose(void)
  {
    int mask;
    char path[MAXPATH];
    struct proc *p = myproc();

    argint(0, &mask);
    if (argstr(1, path, MAXPATH) < 0)
      return -1;
    if (p->sandbox_mask == 0) {
      p->sandbox_mask = mask;
      safestrcpy(p->sandbox_path, path, MAXPATH);
    }
    return 0;
  }

Create user/sandbox.c:
  #include "kernel/param.h"
  #include "kernel/types.h"
  #include "kernel/stat.h"
  #include "user/user.h"

  int
  main(int argc, char *argv[])
  {
    int pid;
    char *command_argv[MAXARG];

    if (argc < 4) {
      fprintf(2, "usage: sandbox mask path command [args...]\n");
      exit(1);
    }
    for (int i = 3; i < argc; i++)
      command_argv[i - 3] = argv[i];
    command_argv[argc - 3] = 0;

    pid = fork();
    if (pid < 0) {
      fprintf(2, "sandbox: fork failed\n");
      exit(1);
    }
    if (pid == 0) {
      if (interpose(atoi(argv[1]), argv[2]) < 0) {
        fprintf(2, "sandbox: interpose failed\n");
        exit(1);
      }
      exec(command_argv[0], command_argv);
      fprintf(2, "sandbox: exec %s failed\n", command_argv[0]);
      exit(1);
    }
    wait(0);
    exit(0);
  }

Add $U/_sandbox\ to UPROGS in Makefile, then run make clean && make qemu.
EOF
}

task_sandbox_path() {
  task_sandbox
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

task_head() {
  write_new user/head.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
void head(int fd, int limit) {
  char buf[512];
  int n, lines = 0;
  while (lines < limit && (n = read(fd, buf, sizeof(buf))) > 0) {
    for (int i = 0; i < n && lines < limit; i++) {
      write(1, &buf[i], 1);
      if (buf[i] == '\n') lines++;
    }
  }
}
int main(int argc, char **argv) {
  int fd = 0, limit = 10;
  if (argc > 3 || (argc == 2 && argv[1][0] != '-')) {
    fprintf(2, "usage: head [-N] [file]\n");
    exit(1);
  }
  if (argc >= 2) {
    limit = atoi(argv[1] + 1);
    if (argv[1][0] != '-' || limit < 0) { fprintf(2, "head: bad count\n"); exit(1); }
  }
  if (argc == 3) {
    fd = open(argv[2], 0);
    if (fd < 0) { fprintf(2, "head: cannot open %s\n", argv[2]); exit(1); }
  }
  head(fd, limit);
  if (fd != 0) close(fd);
  exit(0);
}
EOF
  add_uprog head
}

task_tail() {
  write_new user/tail.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  int fd = 0, want = 10, count = 0, len = 0, start;
  char *lines, *p;
  if (argc > 3 || (argc == 2 && argv[1][0] != '-')) {
    fprintf(2, "usage: tail [-N] [file]\n"); exit(1);
  }
  if (argc >= 2) {
    want = atoi(argv[1] + 1);
    if (argv[1][0] != '-' || want <= 0 || want > 16) {
      fprintf(2, "tail: count must be 1..16\n"); exit(1);
    }
  }
  if (argc == 3) {
    fd = open(argv[2], 0);
    if (fd < 0) { fprintf(2, "tail: cannot open %s\n", argv[2]); exit(1); }
  }
  lines = malloc(want * 128);
  if (!lines) { fprintf(2, "tail: out of memory\n"); exit(1); }
  char c;
  while (read(fd, &c, 1) == 1) {
    if (len < 127) lines[(count % want) * 128 + len++] = c;
    if (c == '\n') {
      lines[(count % want) * 128 + len] = 0;
      count++; len = 0;
    }
  }
  if (len) { lines[(count % want) * 128 + len] = 0; count++; }
  start = count > want ? count - want : 0;
  for (int i = start; i < count; i++) {
    p = lines + (i % want) * 128;
    write(1, p, strlen(p));
  }
  free(lines);
  if (fd != 0) close(fd);
  exit(0);
}
EOF
  add_uprog tail
}

task_grep() {
  write_new user/grep.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int contains(char *line, char *pat) {
  for (int i = 0; line[i]; i++) {
    int j = 0;
    while (pat[j] && line[i + j] == pat[j]) j++;
    if (!pat[j]) return 1;
  }
  return 0;
}
void grep(int fd, char *pat) {
  char line[512], c;
  int n = 0;
  while (read(fd, &c, 1) == 1) {
    if (n < sizeof(line) - 1) line[n++] = c;
    if (c == '\n') {
      line[n] = 0;
      if (contains(line, pat)) write(1, line, n);
      n = 0;
    }
  }
  if (n) { line[n] = 0; if (contains(line, pat)) write(1, line, n); }
}
int main(int argc, char **argv) {
  int fd;
  if (argc != 2 && argc != 3) { fprintf(2, "usage: grep pattern [file]\n"); exit(1); }
  fd = argc == 3 ? open(argv[2], 0) : 0;
  if (fd < 0) { fprintf(2, "grep: cannot open %s\n", argv[2]); exit(1); }
  grep(fd, argv[1]);
  if (fd != 0) close(fd);
  exit(0);
}
EOF
  add_uprog grep
}

task_uniq() {
  write_new user/uniq.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(void) {
  char prev[256], line[256], c;
  int pn = 0, n = 0, same;
  while (read(0, &c, 1) == 1) {
    if (n < sizeof(line) - 1) line[n++] = c;
    if (c != '\n') continue;
    line[n] = 0; same = n == pn && strcmp(line, prev) == 0;
    if (!same) write(1, line, n);
    strcpy(prev, line); pn = n; n = 0;
  }
  if (n) { line[n] = 0; if (n != pn || strcmp(line, prev)) write(1, line, n); }
  exit(0);
}
EOF
  add_uprog uniq
}

task_seq() {
  write_new user/seq.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  int first = 1, last, step = 1;
  if (argc == 2) last = atoi(argv[1]);
  else if (argc == 3) { first = atoi(argv[1]); last = atoi(argv[2]); }
  else if (argc == 4) { first = atoi(argv[1]); step = atoi(argv[2]); last = atoi(argv[3]); }
  else { fprintf(2, "usage: seq [first] [step] last\n"); exit(1); }
  if (!step) { fprintf(2, "seq: zero step\n"); exit(1); }
  if (step > 0) for (int i = first; i <= last; i += step) printf("%d\n", i);
  else for (int i = first; i >= last; i += step) printf("%d\n", i);
  exit(0);
}
EOF
  add_uprog seq
}

task_tee() {
  write_new user/tee.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/fcntl.h"
#include "user/user.h"
int main(int argc, char **argv) {
  char buf[512];
  int fd, n;
  if (argc != 2) { fprintf(2, "usage: tee file\n"); exit(1); }
  fd = open(argv[1], O_CREATE | O_WRONLY | O_TRUNC);
  if (fd < 0) { fprintf(2, "tee: cannot open %s\n", argv[1]); exit(1); }
  while ((n = read(0, buf, sizeof(buf))) > 0) {
    if (write(1, buf, n) != n || write(fd, buf, n) != n) {
      fprintf(2, "tee: write failed\n"); close(fd); exit(1);
    }
  }
  close(fd); exit(0);
}
EOF
  add_uprog tee
}

task_bufcopy() {
  write_new user/bufcopy.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/fcntl.h"
#include "user/user.h"
int main(int argc, char **argv) {
  char buf[512];
  int in, out, n, chunks = 0, bytes = 0;
  if (argc != 3) { fprintf(2, "usage: bufcopy source destination\n"); exit(1); }
  in = open(argv[1], 0);
  out = open(argv[2], O_CREATE | O_WRONLY | O_TRUNC);
  if (in < 0 || out < 0) { fprintf(2, "bufcopy: open failed\n"); exit(1); }
  while ((n = read(in, buf, sizeof(buf))) > 0) {
    if (write(out, buf, n) != n) { fprintf(2, "bufcopy: write failed\n"); exit(1); }
    bytes += n; chunks++;
  }
  printf("%d bytes in %d buffers\n", bytes, chunks);
  close(in); close(out); exit(0);
}
EOF
  add_uprog bufcopy
}

task_hexdump() {
  write_new user/hexdump.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  char buf[16];
  int fd = 0, n, offset = 0;
  if (argc > 2) { fprintf(2, "usage: hexdump [file]\n"); exit(1); }
  if (argc == 2) { fd = open(argv[1], 0); if (fd < 0) { fprintf(2, "hexdump: open failed\n"); exit(1); } }
  while ((n = read(fd, buf, sizeof(buf))) > 0) {
    printf("%x:", offset);
    for (int i = 0; i < n; i++) printf(" %x", (uint8)buf[i]);
    printf("\n"); offset += n;
  }
  if (fd) close(fd);
  exit(0);
}
EOF
  add_uprog hexdump
}

task_more() {
  write_new user/more.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  char line[256], c;
  int fd = 0, n = 0, lines = 0;
  if (argc > 2) { fprintf(2, "usage: more [file]\n"); exit(1); }
  if (argc == 2) { fd = open(argv[1], 0); if (fd < 0) { fprintf(2, "more: open failed\n"); exit(1); } }
  while (read(fd, &c, 1) == 1) {
    if (n < sizeof(line) - 1) line[n++] = c;
    if (c == '\n') {
      write(1, line, n); n = 0;
      if (++lines == 20) {
        fprintf(2, "-- more -- (enter continues, q quits) ");
        if (read(0, &c, 1) != 1 || c == 'q') break;
        lines = 0;
      }
    }
  }
  if (n) write(1, line, n);
  if (fd) close(fd);
  exit(0);
}
EOF
  add_uprog more
}

task_time() {
  write_new user/time.c <<'EOF'
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
int main(int argc, char **argv) {
  int start, status;
  if (argc < 2) { fprintf(2, "usage: time command [args...]\n"); exit(1); }
  start = uptime();
  if (fork() == 0) { exec(argv[1], &argv[1]); fprintf(2, "time: exec failed\n"); exit(1); }
  wait(&status);
  printf("%d ticks\n", uptime() - start);
  exit(status);
}
EOF
  add_uprog time
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
    util|myecho|sumargs|repeat|countdown|later|forktwice|exitcode|twice|double|mycat|lines|touch|mywrite|myrm|kind|fsize|fork|exec|wait|pipe|redir|sleep|sixfive|memdump|find|find-exec|uptime|head|tail|grep|uniq|seq|tee|bufcopy|hexdump|more|time) ./grade-lab-util "$name" ;;
    *) ./grade-lab-syscall "$name" ;;
  esac
}

list_tasks() {
  printf '%s\n' myecho sumargs repeat countdown later forktwice exitcode twice double mycat lines touch mywrite myrm kind fsize fork exec wait pipe redir pingpong primes xargs sleep sixfive memdump find find-exec uptime head tail grep uniq seq tee bufcopy hexdump more time gdb trace sysinfo sandbox sandbox-path attack
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
    myecho) task_myecho ;; sumargs) task_sumargs ;; repeat) task_repeat ;; countdown) task_countdown ;;
    later) task_later ;; forktwice) task_forktwice ;; exitcode) task_exitcode ;; twice) task_twice ;;
    double) task_double ;; mycat) task_mycat ;; lines) task_lines ;; touch) task_touch ;;
    mywrite) task_mywrite ;; myrm) task_myrm ;; kind) task_kind ;; fsize) task_fsize ;;
    fork) task_fork ;; exec) task_exec ;; wait) task_wait ;; pipe) task_pipe ;; redir) task_redir ;;
    sleep) task_sleep ;; sixfive) task_sixfive ;; memdump) task_memdump ;; find|find-exec) task_find ;;
    pingpong) task_pingpong ;; primes) task_primes ;; xargs) task_xargs ;;
    uptime) task_uptime ;; gdb) task_gdb ;; trace) task_trace ;; sysinfo) task_sysinfo ;;
    sandbox) task_sandbox ;; sandbox-path) task_sandbox_path ;; attack) task_attack ;;
    head) task_head ;; tail) task_tail ;; grep) task_grep ;; uniq) task_uniq ;; seq) task_seq ;;
    tee) task_tee ;; bufcopy) task_bufcopy ;; hexdump) task_hexdump ;; more) task_more ;;
    time) task_time ;;
    '') printf 'usage: %s <name> [--force] | list | test <name|all> | grade <name>\n' "$0"; exit 2 ;;
    *) die "unknown task: $task" ;;
  esac
  printf 'done\n'
}
main "$@"

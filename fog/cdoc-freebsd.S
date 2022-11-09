//@ cdoc-freebsd.S: FreeBSD 5.3 x86 prog to open/close /dev/cdrom tray.
//@ TODO: allow configurable cdrom device specifier
//@ TODO: try it on FreeBSD 9
//@ Compile: gcc -DNDEBUG -c cdoc-freebsd.S
//@ Link   : ld -nostdlib -o s-cdoc cdoc-freebsd.o; strip -s s-cdoc
//
// Created: 2003-01-13  (based on Linux sfcdoc.linux.S, 2002-01-27)
// Public Domain

.code32

.global _start

#define _CDROMDEV   "/dev/cdrom"

.if 0
#include <sys/syscall.h>
#include <sys/fcntl.h>
#include <sys/cdio.h>
.endif

// Syscall numbers
#define __EXIT      SYS_exit
#define __OPEN      SYS_open
#define __CLOSE     SYS_close
#define __IOCTL     SYS_ioctl
#define __WRITE     SYS_write
#define SYSPAD      pushl $-1

// See sys/ioccom.h (need to get rid of the cast..)
#undef _IOC
#define _IOC(INOUT,GROUP,NUM,LEN)\
    (INOUT | ((LEN & IOCPARM_MASK) << 16) | (GROUP << 8) | NUM)

#define _CD_FLAGS   (O_RDONLY | O_NONBLOCK)
#define _CD_EJECT   CDIOCEJECT
#define _CD_CLOSE   CDIOCCLOSE

#ifdef NDEBUG
# define L(label)   .L##label
#else
# define L(label)   .##label
#endif

#define SECTION_TEXT    .section .text, "ax", @progbits
#define SECTION_RODATA  .section .rodata, "a", @progbits
#define SECTION_DATA    .section .data, "aw", @progbits
#define SECTION_BSS     .section .bss, "aw", @nobits

SECTION_TEXT
    .align 16
_start:
    //
    popl %eax               # pop argument count
    cmpl $2, %eax
    jl L(jbaduse)
    ja L(jbaduse)
    # load eff. of arg2
    movl %esp, %eax         # eax=argv
    movl 4(%eax), %eax      # eax=argv[1]
    movw (%eax), %ax        # ax=argv[1][0,1]
    cmpb $'-', %al
    jne L(jbaduse)
    # char 2 must be [oc]
    cmpb $'o', %ah
    je L(jopentray)
    cmpb $'c', %ah
    je L(jclosetray)
    jmp L(jbaduse)
L(jopentray):
    movl $_CD_EJECT, %edx
    jmp L(jgo)
L(jclosetray):
    movl $_CD_CLOSE, %edx

L(jgo): // main part: open, ioctl, close
    # open _CDROMDEV
    pushl $_CD_FLAGS
    pushl $L(cddev)
    SYSPAD
    movl $__OPEN, %eax
    int $0x80
    cmpl $3, %eax
    jl L(jerropen)
    movl %eax, %esi         # save fd in %esi
    # valid fd - ioctl it
    pushl %edx
    pushl %eax
    SYSPAD
    movl $__IOCTL, %eax
    int $0x80
    testl %eax, %eax
    jnz L(jerrioctl)
    # close fd again
    pushl %esi
    SYSPAD
    movl $__CLOSE, %eax
    int $0x80
    testl %eax, %eax
    jnz L(jerrclose)
    pushl $0

L(jexit): //
    SYSPAD
    movl $__EXIT, %eax
    int $0x80
    hlt

    // error block follows
L(jbaduse):
    pushl $L(usage_len)
    pushl $L(usage)
    jmp L(jechoerr)
L(jerropen):
    pushl $L(openfail_len)
    pushl $L(openfail)
    jmp L(jechoerr)
L(jerrioctl):
    pushl $L(ioctlfail_len)
    pushl $L(ioctlfail)
    jmp L(jechoerr)
L(jerrclose):
    pushl $L(closefail_len)
    pushl $L(closefail)
L(jechoerr):
    pushl $2                # STDERR
    SYSPAD
    movl $__WRITE, %eax
    int $0x80
    pushl $1
    jmp L(jexit)
    .align 16

SECTION_RODATA
L(usage):
    .ascii "USAGE: s-cdoc -o(pen) | -c(lose)\n"
    .ascii "Nice little 416 bytes tool to open or close the CDROM tray.\n"
    .ascii "Does not recognize and react on the current status, though.\n"
    .equ L(usage_len), .-L(usage)
    .align 4
L(cddev):
    .asciz _CDROMDEV
    .align 4
L(openfail):
    .ascii "Opening " _CDROMDEV " failed!\n"
    .equ L(openfail_len), .-L(openfail)
    .align 4
L(ioctlfail):
    .ascii "Command failed!\n"
    .equ L(ioctlfail_len), .-L(ioctlfail)
    .align 4
L(closefail):
    .ascii "Closing " _CDROMDEV " failed!\n"
    .equ L(closefail_len), .-L(closefail)
    .align 4

.end
// vim:set fenc=utf-8 filetype=c syntax=c ts=4 sts=4 sw=4 et tw=79:

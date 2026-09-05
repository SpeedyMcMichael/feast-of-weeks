; ============================================================================
; feast_of_weeks.asm
;
; Computes the "Feast of Weeks" date: given an ISO 8601 Gregorian calendar
; date (YYYY-MM-DD), converts it to Unix epoch time, adds 7 weeks
; (49 days = 4,233,600 seconds), then converts the result back to an
; ISO 8601 Gregorian date.
;
; The civil <-> days-since-epoch conversion uses Howard Hinnant's
; well-known proleptic Gregorian algorithm (public domain), which
; correctly accounts for leap years (including the 100/400-year rules).
;
; Build (Linux x86-64, no libc dependency, raw syscalls only):
;   nasm -f elf64 feast_of_weeks.asm -o feast_of_weeks.o
;   ld feast_of_weeks.o -o feast_of_weeks
;
; Run:
;   ./feast_of_weeks 2026-09-04
;   -> 2026-10-23
;
; Notes / assumptions:
;   - Input must be exactly 10 characters: YYYY-MM-DD (4-digit year assumed).
;   - Only non-negative (CE) years are handled by the printing routine.
;   - "Epoch" here means the standard Unix epoch, 1970-01-01T00:00:00Z;
;     all arithmetic is done in whole days/seconds at midnight UTC, so
;     there is no timezone or DST ambiguity.
; ============================================================================

section .data
usage_msg:      db "Usage: feast_of_weeks YYYY-MM-DD", 10
usage_len:      equ $ - usage_msg

WEEKS_IN_SECS:  equ 7 * 7 * 86400      ; 7 weeks = 49 days = 4,233,600 s

section .bss
y:      resq 1
m:      resq 1
d:      resq 1
y2:     resq 1
m2:     resq 1
d2:     resq 1
outbuf: resb 32

section .text
global _start

; ----------------------------------------------------------------------------
; _start: entry point. Stack on entry: [rsp]=argc, [rsp+8]=argv[0],
;         [rsp+16]=argv[1], ...
; ----------------------------------------------------------------------------
_start:
    mov     rax, [rsp]              ; argc
    cmp     rax, 2
    jl      .usage

    mov     rdi, [rsp+16]           ; argv[1] -> "YYYY-MM-DD"
    call    parse_date              ; fills [y], [m], [d]

    ; --- days1 = days_from_civil(y, m, d) ---
    mov     rdi, [y]
    mov     rsi, [m]
    mov     rdx, [d]
    call    days_from_civil
    mov     r12, rax                ; days since 1970-01-01

    ; --- epoch1 = days1 * 86400 (seconds) ---
    mov     rax, r12
    imul    rax, 86400

    ; --- epoch2 = epoch1 + 7 weeks ---
    add     rax, WEEKS_IN_SECS

    ; --- days2 = epoch2 / 86400 ---
    cqo
    mov     rbx, 86400
    idiv    rbx                     ; rax = days2

    ; --- (y2, m2, d2) = civil_from_days(days2) ---
    mov     rdi, rax
    call    civil_from_days

    call    format_and_print

    mov     rax, 60                 ; exit(0)
    xor     rdi, rdi
    syscall

.usage:
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, usage_msg
    mov     rdx, usage_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall

; ============================================================================
; parse_date(rdi = ptr to "YYYY-MM-DD") -> fills [y], [m], [d]
; ============================================================================
parse_date:
    mov     r15, rdi                ; base pointer (start of "YYYY-MM-DD")

    mov     rdi, r15                ; year: 4 digits at offset 0
    mov     rsi, 4
    call    atoi_n
    mov     [y], rax

    lea     rdi, [r15+5]            ; month: 2 digits at offset 5
    mov     rsi, 2
    call    atoi_n
    mov     [m], rax

    lea     rdi, [r15+8]            ; day: 2 digits at offset 8
    mov     rsi, 2
    call    atoi_n
    mov     [d], rax
    ret

; atoi_n(rdi = ptr, rsi = digit count) -> rax = parsed unsigned integer
atoi_n:
    xor     rax, rax
.loop:
    movzx   rcx, byte [rdi]
    sub     rcx, '0'
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    dec     rsi
    jnz     .loop
    ret

; ============================================================================
; days_from_civil(rdi = y, rsi = m, rdx = d) -> rax = days since 1970-01-01
; (Howard Hinnant's algorithm; proleptic Gregorian, handles leap years)
; ============================================================================
days_from_civil:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdx                ; d
    mov     r13, rsi                ; m
    mov     r14, rdi                ; y

    cmp     r13, 2
    jg      .skip_dec
    dec     r14                     ; y -= (m <= 2)
.skip_dec:

    ; era = (y >= 0 ? y : y - 399) / 400
    mov     rax, r14
    cmp     rax, 0
    jge     .era_pos
    sub     rax, 399
.era_pos:
    mov     rbx, 400
    cqo
    idiv    rbx
    mov     r8, rax                 ; era

    ; yoe = y - era*400
    mov     rax, r8
    imul    rax, 400
    mov     r9, r14
    sub     r9, rax                 ; yoe

    ; doy = (153*(m + (m>2 ? -3 : 9)) + 2)/5 + d - 1
    mov     rax, r13
    cmp     r13, 2
    jg      .mgt2
    add     rax, 9
    jmp     .mdone
.mgt2:
    sub     rax, 3
.mdone:
    imul    rax, 153
    add     rax, 2
    mov     rbx, 5
    cqo
    idiv    rbx
    add     rax, r12
    dec     rax
    mov     r10, rax                ; doy

    ; doe = yoe*365 + yoe/4 - yoe/100 + doy
    mov     rax, r9
    imul    rax, 365
    mov     r11, rax

    mov     rax, r9
    mov     rbx, 4
    cqo
    idiv    rbx
    add     r11, rax

    mov     rax, r9
    mov     rbx, 100
    cqo
    idiv    rbx
    sub     r11, rax

    add     r11, r10                ; doe

    ; result = era*146097 + doe - 719468
    mov     rax, r8
    imul    rax, 146097
    add     rax, r11
    sub     rax, 719468

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================================
; civil_from_days(rdi = z) -> fills [y2], [m2], [d2]
; (inverse of days_from_civil; proleptic Gregorian, handles leap years)
; ============================================================================
civil_from_days:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r14, rdi
    add     r14, 719468             ; z += 719468

    ; era = (z >= 0 ? z : z - 146096) / 146097
    mov     rax, r14
    cmp     rax, 0
    jge     .zpos
    sub     rax, 146096
.zpos:
    mov     rbx, 146097
    cqo
    idiv    rbx
    mov     r8, rax                 ; era

    ; doe = z - era*146097
    mov     rax, r8
    imul    rax, 146097
    mov     r9, r14
    sub     r9, rax                 ; doe

    ; yoe = (doe - doe/1460 + doe/36524 - doe/146096) / 365
    mov     rax, r9
    mov     rbx, 1460
    cqo
    idiv    rbx
    mov     r10, rax

    mov     rax, r9
    mov     rbx, 36524
    cqo
    idiv    rbx
    mov     r11, rax

    mov     rax, r9
    mov     rbx, 146096
    cqo
    idiv    rbx
    mov     r12, rax

    mov     rax, r9
    sub     rax, r10
    add     rax, r11
    sub     rax, r12
    mov     rbx, 365
    cqo
    idiv    rbx
    mov     r13, rax                ; yoe

    ; y = yoe + era*400
    mov     rax, r8
    imul    rax, 400
    add     rax, r13
    mov     [y2], rax

    ; doy = doe - (365*yoe + yoe/4 - yoe/100)
    mov     rax, r13
    imul    rax, 365
    mov     r15, rax

    mov     rax, r13
    mov     rbx, 4
    cqo
    idiv    rbx
    add     r15, rax

    mov     rax, r13
    mov     rbx, 100
    cqo
    idiv    rbx
    sub     r15, rax

    mov     rax, r9
    sub     rax, r15
    mov     r15, rax                ; doy

    ; mp = (5*doy + 2)/153
    mov     rax, r15
    imul    rax, 5
    add     rax, 2
    mov     rbx, 153
    cqo
    idiv    rbx
    mov     r12, rax                ; mp

    ; d = doy - (153*mp+2)/5 + 1
    mov     rax, r12
    imul    rax, 153
    add     rax, 2
    mov     rbx, 5
    cqo
    idiv    rbx
    mov     rbx, r15
    sub     rbx, rax
    add     rbx, 1
    mov     [d2], rbx

    ; m = mp + (mp < 10 ? 3 : -9)
    mov     rax, r12
    cmp     r12, 10
    jl      .mp_lt10
    sub     rax, 9
    jmp     .m_done
.mp_lt10:
    add     rax, 3
.m_done:
    mov     [m2], rax

    ; y2 += (m2 <= 2) ? 1 : 0
    mov     rax, [m2]
    cmp     rax, 2
    jg      .no_yinc
    inc     qword [y2]
.no_yinc:

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================================
; format_and_print: writes "[y2]-[m2]-[d2]\n" to stdout
; ============================================================================
format_and_print:
    lea     rdi, [outbuf]

    mov     rax, [y2]
    call    write_int               ; writes year, returns updated rdi

    mov     byte [rdi], '-'
    inc     rdi

    mov     rax, [m2]
    call    write_2digit

    mov     byte [rdi], '-'
    inc     rdi

    mov     rax, [d2]
    call    write_2digit

    mov     byte [rdi], 10          ; '\n'
    inc     rdi

    lea     rsi, [outbuf]
    mov     rdx, rdi
    sub     rdx, rsi                ; length = rdi - outbuf

    mov     rax, 1                  ; sys_write
    mov     rdi, 1                  ; stdout
    syscall
    ret

; write_int(rax = non-negative value, rdi = dest ptr) -> rdi = updated dest ptr
write_int:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi

    test    rax, rax
    jnz     .conv
    mov     byte [r12], '0'
    inc     r12
    jmp     .done

.conv:
    sub     rsp, 32                 ; scratch buffer for reversed digits
    mov     rcx, rsp
    xor     r13, r13                ; digit count
    mov     rbx, 10
.loop_digits:
    xor     rdx, rdx
    div     rbx
    add     dl, '0'
    mov     [rcx + r13], dl
    inc     r13
    test    rax, rax
    jnz     .loop_digits

    mov     r8, r13
.rev_loop:
    dec     r8
    mov     dl, [rcx + r8]
    mov     [r12], dl
    inc     r12
    test    r8, r8
    jnz     .rev_loop
    add     rsp, 32
.done:
    mov     rdi, r12
    pop     r13
    pop     r12
    pop     rbx
    ret

; write_2digit(rax = value 0-99, rdi = dest ptr) -> rdi = dest+2, zero-padded
write_2digit:
    push    rbx
    mov     rbx, 10
    xor     rdx, rdx
    div     rbx                     ; rax = tens, rdx = ones
    add     al, '0'
    mov     [rdi], al
    add     dl, '0'
    mov     [rdi+1], dl
    add     rdi, 2
    pop     rbx
    ret

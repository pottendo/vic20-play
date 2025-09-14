#importonce
#import "pottendos_utils.asm"

//#define HANDLE_MEM_BANK      // enable this if kernal or I/O is potentially banked out

#if LATER
// dest: addr, len: scalar
.macro uport_read_(dest, len) {
    lda #<dest
    ldy #>dest
    sta parport.len
    sta parport.buffer
    sta parport.dest
    sty parport.len + 1
    sty parport.buffer + 1
    sty parport.dest + 1

    clc
    adc #<len
    sta parport.len
    bcc !+
    inc parport.len + 1
!:
    lda parport.len + 1
    clc
    adc #>len
    sta parport.len + 1

    lda #(parport.nread - parport.jm - 2)
    sta parport.jm + 1          // modify operand of ISR branch
    jsr parport.start_isr
    lda parport.read_pending    // busy wait until read is completed
    bne *-3
}

// dest: addr, len: addr
.macro uport_read(dest, len)
{
    adc16(len, dest, parport.len)
    poke16_(parport.buffer, dest)   
    lda #(parport.nread - parport.jm - 2)
    sta parport.jm + 1          // modify operand of ISR branch to
    jsr parport.start_isr       // launch interrupt driven read
    lda parport.read_pending    // busy wait until read is completed
    bne *-3
}

.macro uport_lread(dest)
{
    poke8_(parport.rtail, 0)
    lda #(parport.loopread - parport.jm - 2)
    sta parport.jm + 1  // modify jump address for loopread
    poke16_(parport.buffer, dest)
    jsr parport.start_isr
}

// dest: addr, len in x-reg
.macro uport_sread_f(dest)
{
    poke16_(parport._rf + 1, dest)   
    jsr parport.sync_read_f
}
#endif // LATER

// dest: addr, len: addr
.macro uport_sread(dest, len)
{
    adc16(len, dest, parport.len)
    poke16_(parport.buffer, dest)   
    jsr parport.sync_read
}

.macro uport_stop() {
    jsr parport.stop_isr
}

// from: addr, len: scalar
.macro uport_write_(from, len) {
    poke16_(parport.buffer, from)
    poke16_(parport.len, len)
    jsr parport.write_buffer
}

// from: addr, len: addr
.macro uport_write(from, len) {
    poke16_(parport.buffer, from)
    poke16(parport.len, len)
    jsr parport.write_buffer
}

// from: addr (best to be page alinged ($100)), xreg: len
.macro uport_write_f(from) {
    poke16_(parport._wf+1, from)
    jsr parport.write_buffer_f
}

// write byte from acc to parport
.macro out_byte() {
    pha
    vic_busy(1)   // tell esp we're busy
    pla
    sta VIA1.portB
    vic_busy(0)
    vic_handshake()
}

.macro vic_write(w)
{
.if (w == 0) {
    setbits(VIA1.portA, %00100000)    // set FIRE (=SP2) high
} else {
    clearbits(VIA1.portA, %11011111)    // set FIRE (=SP2) low
}
}

.macro vic_busy(b)
{
.if (b == 0) {
    clearbits(VIA1.PCR, %11011111)    // set CB2 (=PA2) low
} else {
    setbits(VIA1.PCR, %11100000)      // set CB2 (=PA2) to manual and set high
}
}

.macro vic_handshake()
{
    clearbits(VIA1.portA, %10111111)    // Trigger PC2
    setbits(VIA1.portA, %01000000)
}
// .segment _par_drv

parport: {
                .label buffer = $9e   // pointer to destination buffer
len:            .word $0000     // len of requested read
dest:           .word $0400     // destination address
read_pending:   .byte $00       // flag if read is on-going

rtail:          .byte $00
pinput_pending: .byte $00       // #of msg the esp would like to send, inc'ed by NMI/Flag2
_wtmp:          .byte $00
_boc_save:      .byte $00

init:
    lda VIC.BoC
    sta _boc_save
    BoC(4)                     // show we're in init
    poke8_(read_pending, 0)
    sta pinput_pending          // acc still 0

    setbits(VIA1.DDRA, %00100000)   // set FIRE (=SP2 on C64) as output
    setbits(VIA1.portA, %00100000)  // set FIRE to high to tell VIC20 could read

    setbits(VIA1.DDRA, %01000000)   // set CASETTE (=PC2 on C64) as output for manual interrupt triggering
    setbits(VIA1.portA, %01000000)  // set CASETTE (=PC2) to high

    setbits(VIA1.PCR, %11000000)    // set CB2 (=PA2 on C64) to manual
    clearbits(VIA1.PCR, %11011111)  // set CB2 (=PA2 on C64) to manual and set low
    
    jsr cind
    rts

wind:
    lda VIC.BoC
    sta _boc_save
    BoC(2)                     // show we're in write mode
    rts
rind:
    lda VIC.BoC
    sta _boc_save
    BoC(3)                     // show we're in read mode
    rts
cind:
    lda _boc_save
    sta VIC.BoC
    rts

start_isr:
    //BgC(7)
    rts

stop_isr:
    //BgC(8)
    rts

#if LATER    
// Interrupt driven read, finished when read_pending == 1
start_isr:
rin:
    jsr $beef                        // operand modified
    poke8_(CIA2.ICR, $7f)            // stop all interrupts
    poke16_(STD.NMI_VEC, flag_isr)   // reroute NMI
#if HANDLE_MEM_BANK
    poke16_($fffa, flag_isr)         // also HW vector, if KERNAL is banked out (e.g. in soft80 mode, credits @groepaz)
#endif
    poke8_(CIA2.SDR, $ff)            // Signal C64 is in read-mode (safe for CIA)
    poke8_(CIA2.DIRB, $00)           // direction bit 0 -> input
    setbits(CIA2.DIRA, %00000100)    // PortA r/w for PA2
    clearbits(CIA2.PORTA, %11111011) // set PA2 to low to signal we're ready to receive
    lda CIA2.ICR                     // clear interrupt flags by reading
    poke8_(CIA2.ICR, %10010000)      // enable FLAG pin as interrupt source
    poke8_(read_pending, $01)
    rts

stop_isr:
    poke8_(CIA2.ICR, $7f)            // stop all interrupts
    poke16_(STD.NMI_VEC, STD.CONTNMI)    // reroute NMI
#if HANDLE_MEM_BANK
    poke16_($fffa, STD.NMI_VEC)
#endif
    poke8_(CIA2.DIRB, $00)           // direction bits 0 -> input
    poke8_(CIA2.ICR, $80)            // enable interrupts    
rif:
    jsr $beef                        // operand modified
    rts
    
flag_isr:
    sei
    save_regs()
#if HANDLE_MEM_BANK
    lda $01
    pha               // save mem layout
    poke8_($01, $37)  // std mem layout for I/O access
#endif
    lda CIA2.ICR
    and #%10000 // FLAG pin interrupt (bit 4)
jm: bne nread  // modified operand in case of loop read
#if HANDLE_MEM_BANK
    pla             // restore mem layout
    sta $01
    jmp STD.CONTNMI
//    restore_regs()
//    rti
#else
    jmp STD.CONTNMI
#endif
    
    // receive char now
nread:
    setbits(CIA2.PORTA, %00000100)  // set PA2 to high to signal we're busy receiving
    ldy #$00
    lda CIA2.PORTB  // read chr from the parallel port B
    sta (buffer), y
    inc buffer      
    bne !+
    inc buffer + 1
!:
    cmp16(buffer, len) 
    bcc outnread
    uport_stop()
    poke8_(read_pending, $00)
    
outnread:
    clearbits(CIA2.PORTA, %11111011)   // clear PA2 to low to signal we're ready to receive
#if HANDLE_MEM_BANK
    pla         // restore mem layout
    sta $01
#endif
    restore_regs()
    rti

loopread:
    setbits(CIA2.PORTA, %00000100)  // set PA2 to high to signal we're busy receiving
    jsr rindon
    lda CIA2.PORTB  // read chr from the parallel port B
rt1:ldy rtail       // operand potentially modified to point to ccgms
rt2:sta gl.dest_mem,y
rt3:inc rtail       // operand potentially modified to point to ccgms
    tya 
    sec
rt4:sbc $beef       // modified to point to ccgms
    cmp #227         // 227
    php
    jsr rindoff
    plp
    bcc outnread    // enough room in buffer
    //poke8_(VIC.BoC, RED)             // show wer're blocking
    clearbits(CIA2.PORTA, %11111011) // clear PA2 to low to acknowledge last byte
    ora #%00000100
    sta CIA2.PORTA                   // set PA2 to high to signal we're busy -> FlowControl
#if HANDLE_MEM_BANK
    pla             // restore mem layout
    sta $01
#endif
    restore_regs()
    rti



// optimized sync read for small reads (<128 bytes)
// dst address must be poked in _rf+1, x register holds len
sync_read_f:
    poke8_(CIA2.SDR, $ff)
    poke8_(CIA2.DIRB, $00)          // direction bit 0 -> input
    setbits(CIA2.DIRA, %00000100)   // PortA r/w for PA2
    ldy #$00
!nc_f:
    clearbits(CIA2.PORTA, %11111011)  // set PA2 to low to signal we're ready to receive
!:  
    lda CIA2.ICR
    and #%00010000
    beq !-
    setbits(CIA2.PORTA, %00000100)  // set PA2 to high to signal we're busy _f
    lda CIA2.PORTB
_rf:
    sta $beef,y                     // operand modified
    iny
    dex
    bne !nc_f-
!:
    clearbits(CIA2.PORTA, %11111011)
    rts
#endif // LATER

vic_isr:
    sei
    save_regs()
    lda VIA1.IFR
    and #%00010000
    beq !out+
    BoCinc()                     // show we're in vic_isr
    poke8_(P.zpp2, 1)
    restore_regs()
    rti
!out:
    BgCinc()
    restore_regs()
    rti
    jmp STD.CONTIRQ

setup_read:
    //jsr rind
    poke8_(VIA1.DDRB, $00)           // direction bits 0 -> input
    clearbits(VIA1.PCR, %11101111)  // CB1 High->Low edge trigger
    //setbits(VIA1.PCR, %00010000)  // CB1 as interrupt source
    setbits(VIA1.IER, %10010000)  // Interrupt on CB1
    setbits(VIA1.AUX, %00000010)  // latch CB1
//#if LATER    
    poke8_(P.zpp2, 0)
    sei
    lda #<vic_isr
    sta $0314
    lda #>vic_isr
    sta $0315
    cli
//#endif
    vic_write(0)
    rts

close_read:

    sei
    poke16_($0314, STD.CONTIRQ)
    cli
    //jsr cind
    vic_busy(0)

    rts

sync_read:
    jsr setup_read
    ldy #$00
!next:
    vic_busy(0)   // tell esp we're ready to receive
!:  
    //BoCinc()
    //lda VIA1.IFR
    //and #%00010000
    lda P.zpp2
    beq !-
    poke8_(P.zpp2, 0)
    vic_busy(1)  // tell esp we're busy
    vic_handshake()
    
    lda VIA1.portB
    sta (buffer), y
    inc buffer      
    bne !+
    inc buffer + 1
!:
    cmp16(buffer, len) 
    bcc !next-
    
    jmp close_read

// write routines
setup_write:
    sei
    uport_stop()                     // ensure that NMIs are not handled    
    //jsr wind                       
    vic_write(1)
    poke8_(VIA1.DDRB, $ff)           // direction bits 1 -> output
    vic_busy(0)
    
    rts

close_write:
    vic_busy(0)
    poke8_(VIA1.DDRB, $00)           // set for input, to avoid conflict by mistake
    vic_write(0)
wif:
    jsr cind                         
    cli
    rts


// lesser optimized, allowing up to 64k writes
write_buffer:
    // sanity check for len == 0
    lda len + 1
    bne cont
    lda len
    bne cont
    rts
cont:
    jsr setup_write
loop:    
    ldy #$00
    lda (buffer), y
    out_byte()
//!:  
//   lda #%10000     // check if receiver is ready to accept next char
//    bit CIA2.ICR
//    beq !-

    inc buffer
    bne !+
    inc buffer + 1
!:
    dec len
    bne loop
    lda len + 1
    beq done
    dec len + 1
    jmp loop
done:
    jsr close_write
    rts

// optimized write buffer for small packets (<128 bytes)
// pointer to data needs to be poked in _wf+1, x register holds len
write_buffer_f:
    sei 
    vic_write(1)
    poke8_(VIA1.DDRB, $ff)           // direction bits 1 -> output
!n:
    vic_busy(1)   // tell esp we're busy
_wf:
    lda $beef                        // operand modified
    sta VIA1.portB
    vic_handshake()
    vic_busy(0)
//!:  
//    lda #%10000     // check if receiver is ready to accept next char
//    bit CIA2.ICR
//    beq !-
    inc _wf+1                        // advance read address
    dex
    bne !n-

    jmp close_write
} // namespace parport

    
__END__:    nop
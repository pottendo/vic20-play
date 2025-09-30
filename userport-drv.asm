#importonce
#import "pottendos_utils.asm"

//#define HANDLE_MEM_BANK      // enable this if kernal or I/O is potentially banked out

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
    vic_write(1)
    
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
    vic_write(1)
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

.macro clear_cb1()
{
!:  lda VIA1.portB
    lda VIA1.IFR
    and #%00010000
    bne !-
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
    //BoC(4)                     // show we're in init
    poke8_(read_pending, 0)
    sta pinput_pending          // acc still 0

    setbits(VIA1.DDRA, %00100000)   // set FIRE (=SP2 on C64) as output
    vic_write(1)                    // pretend write mode

    setbits(VIA1.DDRA, %01000000)   // set CASETTE (=PC2 on C64) as output for manual interrupt triggering
    setbits(VIA1.portA, %01000000)  // set CASETTE (=PC2) to high

    setbits(VIA1.PCR, %11000000)    // set CB2 (=PA2 on C64) to manual
    vic_busy(0)                    // pretend we're not busy
    
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

// Interrupt driven read, finished when read_pending == 1
start_isr:
    sei
    jsr rind
    //poke8_(VIA1.IER, %01111111)      // stop interrupt on CB1

    poke8_(VIA1.DDRB, $00)           // direction bits 0 -> input
    clearbits(VIA1.PCR, %11101111)  // CB1 High->Low edge trigger
    setbits(VIA1.PCR, %00010000)  // CB1 as interrupt source
    setbits(VIA1.IER, %10010000)  // Interrupt on CB1
    //setbits(VIA1.AUX, %00000010)  // latch CB1
    clearbits(VIA1.AUX, %11111101)  // clear latch CB1
    poke8_(read_pending, $01)
    poke16_(STD.NMI_VEC, vic_isr)

    // make sure CB1 flag is clear
    clear_cb1()

    vic_write(0)    // now we're in read mode
    vic_busy(0)
    cli
    rts

stop_isr:
    poke8_(VIA1.IER, %00010000)      // stop interrupt on CB1
    poke16_(STD.NMI_VEC, STD.CONTNMI)    // reroute NMI
    poke8_(VIA1.DDRB, $00)           // direction bits 0 -> input
    poke8_(VIA1.IER, $80)            // enable interrupts
    jsr cind                        
    rts

vic_isr:
    sei
    save_regs()
    lda VIA1.IFR
    and #%00010000
jm: bne nread   // modified operand in case of loop read
    jmp $feb2    // jump to original vic20 NMI handler

    // receive char now
nread:
    vic_busy(1)   // tell esp we're busy receiving
    //BoCinc()                     // show we're in vic_isr
    ldy #$00
    lda VIA1.portB  // read chr from the parallel port B
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
    //delay(1000)
    BoCinc()
    vic_handshake() // ACK character
    vic_busy(0)   // tell esp we're not busy anymore
    restore_regs()
    rti

#if LATER    

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

#endif // LATER

setup_read:
    jsr rind
    poke8_(VIA1.DDRB, $00)           // direction bits 0 -> input
    clearbits(VIA1.PCR, %11101111)  // CB1 High->Low edge trigger
    //setbits(VIA1.PCR, %00010000)  // CB1 as interrupt source
    //setbits(VIA1.IER, %10010000)  // Interrupt on CB1
    setbits(VIA1.AUX, %00000010)  // latch CB1
    clear_cb1()
    vic_write(0)
    rts

close_read:
    jsr cind
    rts

sync_read:
    jsr setup_read
    vic_busy(0)   // tell esp we're ready to receive
    ldy #$00
    beq ft
!next:
    //BoCinc()                     // show we're in sync_read
    vic_busy(0)   // tell esp we're ready to receive
    delay(3000)
    vic_handshake()
ft: 
!: 
    //BoCinc()                     // show we're in sync_read
    lda VIA1.IFR
    and #%00010000
    beq !-
    vic_busy(1)
    lda VIA1.portB
    sta (buffer), y
    inc buffer      
    bne !+
    inc buffer + 1
!:
    cmp16(buffer, len) 
    bcc !next-
    vic_handshake() // ACK last char
    jmp close_read

// optimized sync read for small reads (<128 bytes)
// dst address must be poked in _rf+1, x register holds len
sync_read_f:
    poke8_(VIA1.DDRB, $00)           // direction bits 0 -> input
    clearbits(VIA1.PCR, %11101111)  // CB1 High->Low edge trigger
    //setbits(VIA1.IER, %10010000)  // Interrupt on CB1
    setbits(VIA1.AUX, %00000010)  // latch CB1
    clear_cb1()
    vic_write(0)    // now we're in read mode
    ldy #$00
    beq ft_f
    vic_busy(0)
    
!nc_f:
    vic_busy(0)
    vic_handshake()
ft_f:
!:  
    BoCinc()                     // show we're in sync_read_f
    lda VIA1.IFR
    and #%00010000
    beq !-
    vic_busy(1)
    //delay(3000)
    lda VIA1.portB
_rf:
    sta $beef,y                     // operand modified
    iny
    dex
    bne !nc_f-
!:
    vic_busy(0)
    rts

// write routines
setup_write:
    sei
    uport_stop()                     // ensure that NMIs are not handled    
    jsr wind                       
    vic_write(1)
    poke8_(VIA1.DDRB, $ff)           // direction bits 1 -> output
    vic_busy(0)
    rts

close_write:
    vic_busy(0)
    poke8_(VIA1.DDRB, $00)           // set for input, to avoid conflict by mistake
    vic_write(1)
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
    BgCinc()                     // show we're in write_buffer
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

trigger_pc2:
    ldx #10
!:
    vic_handshake()
    delay(30000)
    BoCinc()                     // show we're in trigger_pc2
    dex
    bne !-
    rts

trigger_pa2:
    ldx #10
!:
    vic_busy(1)   // tell esp we're busy
    delay(30000)
    vic_busy(0)
    delay(30000)
    BoCinc()                     
    dex
    bne !-
    rts

trigger_sp2:

    ldx #10
!:
    vic_write(1)
    delay(30000)
    vic_write(0)
    delay(30000)
    BgCinc()                     
    dex
    bne !-
    rts

poll_isr:
    poke8_(VIA1.DDRB, $00)           // direction bits 0 -> input
    clearbits(VIA1.PCR, %11101111)  // CB1 High->Low edge trigger
    //setbits(VIA1.PCR, %00010000)  // CB1 as interrupt source - don't use if polling
    //setbits(VIA1.IER, %10010000)  // Interrupt on CB1
    setbits(VIA1.AUX, %00000010)  // latch CB1
    clear_cb1()
    vic_write(0)
    vic_busy(0)
    ldx #1
    stx $1120
    stx $1120-1
    stx $1120-2
    stx $1120+1
    stx $1120+2
    stx $1120+3
    stx $1120+4
    stx $1120+5
next:
    BoCinc()                     // show we're in sync_read
    lda VIA1.IFR
    and #%00010000
    beq next
    vic_busy(1)
    //delay(30000)
    lda VIA1.portB
    sta $1120+8
    pha
    and #%00000010
    beq !+
    inc $1120-1
!:
    pla
    pha
    and #%00000100
    beq !+
    inc $1120
!:
    pla
    pha
    and #%00001000
    beq !+
    inc $1120+1
!:
    pla
    pha
    and #%00010000
    beq !+
    inc $1120+2
!:
    pla
    pha
    and #%00100000
    beq !+
    inc $1120+3
!:
    pla
    pha
    and #%01000000
    beq !+
    inc $1120+4
!:
    pla
    pha
    and #%10000000
    beq !+
    inc $1120+5
!:
    pla
    pha
    and #%00000001
    beq !+
    inc $1120-2
!:
    pla
    vic_busy(0)
    jmp next
    rts


} // namespace parport

    
__END__:    nop
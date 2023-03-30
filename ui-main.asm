//.file [name="ui.prg", segments="_main, _cmds, _screen, _par_drv, _pottendo_utils, _data, _sprites"]
.filenamespace main_
*= $1201 "BasicUpstart"
BasicUpstart(main_entry)

#import "globals.asm"
.const DELAYVAL = $2000

*= $2000 "Program"

// .segment _main
main_entry:
    BoC(6)
    BgC(1)
    AuxC(1)
    show_screen(1, str.screen1)
    jsr loopmenu
exit:
    rts

loopmenu:
//    jsr delay
    jsr STD.GETIN
    beq loopmenu
    ldx #0
!ne:
    cmp cmd_vec,x
    bne !+
    inx
    ldy cmd_vec,x
    sty _s + 1
    inx
    ldy cmd_vec,x
    sty _s+2
_s: jsr $BEEF   // operand modified
    jmp loopmenu
!:
    inx
    inx
    inx
    pha
    lda #$ff    // check if last cmd reached
    cmp cmd_vec,x
    beq !+
    pla
    jmp !ne-
!:
    pla
    jmp loopmenu

cmd0:
    lda _gon
    bne !+
    jsr vic.gfx_on
    inc _gon
    rts
!:  jsr vic.gfx_off
    dec _gon
    rts
_gon: .byte $00

cmd1:
    ldx #239
    ldy #$ff
!:
    tya
    sta vic20.vic_videoram,x
    dey
    dex
    bne !-
    tya
    sta vic20.vic_videoram,x
    rts

cmd2:
    memset(vic20.vic_colorram, _col, 256)
    inc _col
    rts
_col: .byte $00

cmd3:
    memset_(vic20.vic_charset, 0, $0f00)
    memset(vic20.vic_charset + 8 + 16 * 239, _f, 8)
    inc _f
    rts
_f: .byte 00

cmd4:
    poke8_(_xt, 32)
    poke8_(_yt, 0)
    lda #160
!:  pha
    put_pixel(_xt, _yt)
    inc _xt
    inc _yt
    pla
    sec
    sbc #1
    bne !-
    rts
_xt: .byte 0
_yt: .byte 0

cmd5:
    poke16_(_x1t, 0)
    poke16_(_x2t, 0)
    lda #64
!:
    pha
    poke8_(vic.y1, 0)
    poke8_(vic.y2, 159)
    poke8(vic.x1, _x1t)
    poke8(vic.x2, _x2t)
    jsr vic.draw_line
    inc _x1t
    inc _x1t
    inc _x1t
    inc _x2t
    pla
    sec
    sbc #1
    bne !-
skip:
    poke16_(_x1t, 0)
    poke16_(_x2t, 0)

    lda #53
!:
    pha
    poke16_(vic.x1, 191)
    poke16_(vic.x2, 0)
    poke8(vic.y1, _x1t)
    poke8(vic.y2, _x2t)
    jsr vic.draw_line
    inc _x1t
    inc _x1t
    inc _x1t
    inc _x2t
    pla
    sec
    sbc #1
    bne !-
    rts
_x1t: .word 0
_x2t: .word 0

cmd6:
    BoCinc()
    rts
cmd7:
    AuxCinc()
    rts
unset:
    rts
cmd8:
    rts
cmd9:
    print(str.finished)
    pla         // clear stack from last return address
    pla
    jmp exit
lastcmd:
    rts

cmdterminal:
    rts
    
cmdirc:
    rts

delay:
!:  dec16(delay_loop)
    cmp16_(delay_loop, 0)
    bne !-
reload:
    poke16_(delay_loop, DELAYVAL)    // back to start
    rts 
    
cmd_vec:
    cmdp('0', cmd0)
    cmdp('1', cmd1)
    cmdp('2', cmd2)
    cmdp('3', cmd3)
    cmdp('4', cmd4)
    cmdp('5', cmd5)
    cmdp('6', cmd6)
    cmdp('7', cmd7)
    cmdp('8', cmd8)
    cmdp('9', cmd9)
    cmdp('T', cmdterminal)
    cmdp('I', cmdirc)
    cmdp($ff, lastcmd)

.macro cmdp(c, addr)
{
    .byte c
    .word addr
}

// .segment _data

cmd3_:  .text "COMMAND 3"
        .byte $0d, $00
scrstate:   .byte $00
scrfill:    .byte $00
loopc:      .byte $00
selstate:   .byte $02
tmp:        .word $0000
delay_loop: .word $0400
delays:     .word $100, $800, $800, $1000
delay_idx:  .byte $7
// left upper
lu:         .word $0018         // x-coord
            .word $0018         // x-coord lower boundary
            .word $18 + 320 - 1 // x-coord upper boundary: border + 320 - 1
            .byte $32           // y-coord
            .byte $32           // y-coord lower boundary: border
            .byte $32 + 200 - 1 // y-coord upper boundry: border + 200 - 1
// right lower
rl:         .word $18 + 320 - 24*2 // x-coord
            .word $0018 - 24*2 + 1 // x-coord lower boundary: border - sprw + 1
            .word $18 + 320 - 24*2 // x-coord upper boundary: border + 320 - sprw
            .byte $32 + 200 - 21*2 // ycoord
            .byte $32 - 21*2 + 1   // ycoord lower boundary: border - sprw + 1
            .byte $32 + 200 - 21*2 // ycoord upper boundary: border + 200 - sprh

.macro sprite_move(action, addr)
{
    .if (action == "left")
    {
        cmp16(addr, addr + 2)
        beq !+
        dec16(addr)
    !:
    }
    .if (action == "right")
    {
        cmp16(addr, addr + 4)
        beq !+
        inc16(addr)
    !:
    }
    .if (action == "up")
    {
        cmp8(addr + 6, addr + 7)
        beq !+
        dec addr + 6
    !:
    }
    .if (action == "down")
    {
        cmp8(addr + 6, addr + 8)
        beq !+
        inc addr + 6
    !:
    }
}
    
.namespace str {
inputtext:
    .text "TEXT:"
    .byte $00
inputnumber:
    .text "#TO READ:"
    .byte $00
finished: .text "FINISHED."
    .byte $00
invkey: .text "INVALID KEY PRESSED."
    .byte $00
delimiter: .text "|"
    .byte $00

screen1:
.text "0) SCREEN ON/OFF"
.byte $0d
.text "1) FILL SCREEN"
.byte $0d
.text "2) CYCLE COLOR"
.byte $0d
.text "3) FILL"
.byte $0d
.text "4) PLOT"
.byte $0d
.text "5) LINE TEST"
.byte $0d
.text "6) MANDELBROT"
.byte $0d
//.text "7) TOGGLE ATN"
//.byte $0d
.text "8) DUMP DATA C64->ESP"
.byte $0d
.text "T) TERMINAL"
.byte $0d
.text "I) IRC"
.byte $0d
.text "9) EXIT"
.byte $0d
.text "-------------SELECT#"
.byte $0d
.byte $00
}

#import "pottendos_utils.asm"
#import "vic-gfx.asm"
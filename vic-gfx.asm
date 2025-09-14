#import "globals.asm"
#import "pottendos_utils.asm"

.macro put_pixel_(x, y)
{
    ldx #x
    stx vic._x
    ldy #y
    sty vic._y
    jsr vic.plot_pixel
}

.macro put_pixel(x, y)
{
    ldx x
    stx vic._x
    ldy y
    sty vic._y
    jsr vic.plot_pixel
}

.namespace vic
{
// vic registers for caching    
v0: .byte $00
v1: .byte $00
v2: .byte $00
v3: .byte $00
v5: .byte $00

// x, y to plot
.const maxx = 192 
.const maxy = 160

_x: .word $0000
_y: .byte $00
xwidth:     .byte maxx
ywidth:     .byte maxy
pixelcol:   .byte $01

gfx_on:
    lda vic20.vic + 0
    sta v0
    lda vic20.vic + 1
    sta v1
    lda vic20.vic + 2
    sta v2
    lda vic20.vic + 3
    sta v3
    lda vic20.vic + 5
    sta v5

    poke8_(vic20.vic + 0, 10)
    poke8_(vic20.vic + 1, 40)
    clearbits(vic20.vic + 2, %00000000)
    setbits(vic20.vic + 2, 0 + 24)          // 24 colums
    clearbits(vic20.vic + 3, %10000001)
    setbits(vic20.vic + 3, (10 <<1) | 1)    // 20 rows, 8x16 bits/char
    clearbits(vic20.vic + 5, %11110000)
    setbits(vic20.vic + 5, (%00000000) + 12)    // Char/GFX bitmaps at $1000 (12)
    rts

gfx_off:
    lda v0
    sta vic20.vic + 0
    lda v1
    sta vic20.vic + 1
    lda v2
    sta vic20.vic + 2
    lda v3
    sta vic20.vic + 3
    lda v5
    sta vic20.vic + 5
    rts

plot_pixel:
    cmp8_(_x, maxx)
    bcs !out+
    cmp8_(_y, maxy)
    bcs !out+
    jsr prep_pcol_    
    jsr plot_
    rts
!out:
    BoCinc()
    rts
    
// this code is borrowed from here
// https://codebase64.org/doku.php?id=base:various_techniques_to_calculate_adresses_fast_common_screen_formats_for_pixel_graphics    
plot_:
    ldy _y
plot:
    ldx _x
    lda yaddrlow,y
    clc
_p3:adc xaddrlowhr,x
    sta P.zpp1

    lda yaddrhigh,y
XTBmdf:
_p4:adc xaddrhighhr,x
    sta P.zpp1+1

    ldy #0
_p5:lda xmaskhr,x 
    eor #$ff
    and (P.zpp1),y
    ora pixelcol
    sta (P.zpp1),y
    rts

prep_pcol:
_d3:jmp * + 3   // operand modified for hr/mc
    lda pixelcol
    cmp #%11
    bne !+
    poke16_(_d2 + 1, xpixelmc11)
    jmp prep_pcol_
!:
    cmp #%10
    bne !+
    poke16_(_d2 + 1, xpixelmc10)
    jmp prep_pcol_
!:
    cmp #%01
    bne !+
    poke16_(_d2 + 1, xpixelmc01)
    jmp prep_pcol_
!:
    cmp #%00
    bne !+
    poke16_(_d2 + 1, xpixelmc00)
!:
prep_pcol_:
    lda _x
_d1:and #$07
    tax
_d2:lda xpixelhr,x
    sta pixelcol
!out:
    rts

draw_line:
    cld
    sbc16m(x2, x1, dx)
    bpl line1
    eor #$ff
    sta dx + 1
    lda dx
    clc
    eor #$ff
    adc #$01
    sta dx
    bcc !+ 
    inc dx+1
!:  lda #$ff
    sta xadd
    sta xadd + 1
    jmp line2
line1:
    poke16_(xadd, 1)
line2:
    lda dx + 1
    bne line3
    lda dx
    bne line3
    lda #0
    sta rest
    sta rest + 1
    jmp line4
line3:
    lda #$ff
    sta rest
    sta rest + 1 
line4:
    sec
    lda y2 
    sbc y1
    sta dy
    lda #$00
    sbc #$00
    sta dy + 1
    bpl line5
    eor #$ff
    sta dy + 1
    lda dy 
    eor #$ff
    clc 
    adc #$01
    sta dy 
    bcc !+
    inc dy + 1
!:  lda #$ff
    sta yadd
    jmp line6
line5:
    lda #$01
    sta yadd
line6:
    lda dy + 1
    cmp dx + 1
    bcc line7
    lda dy 
    cmp dx
    bcc line7
    lda #$ff
    sta lin 
    jmp line8
line7:
    lda #$01
    sta lin 
line8:
    poke16(_x, x1)
    poke8(_y, y1)
    jsr prep_pcol_
    jsr plot_

line9:
    lda y1
    cmp y2
    bne line10
    lda x1
    cmp x2
    bne line10
    lda x1+1
    cmp x2+1
    bne line10
    rts
line10:
    lda rest + 1
    bmi zweig1
zweig2:
    sbc16m(rest, dx, rest)
    clc
    lda y1
    adc yadd
    sta y1
    lda lin 
    bmi line8
    jmp line9
zweig1:
    adc16m(rest, dy, rest)
    adc16m(x1, xadd, x1)
    lda lin
    bmi line9
    jmp line8

// line draw helpers
x1: .word 0
y1: .byte 100
x2: .word 191
y2: .byte 159
dx: .word 0
dy: .word 0
xadd: .word 0
yadd: .word 0
rest: .word 0
lin: .word 0

// all sort of tables to improve perfomance
yaddrlow:
    .for (var y = 0; y < maxy; y++)
    {  
        .var r = <(vic20.vic_charset + ((y & 15) + (maxx*2 * floor(y / 16))))
        .byte r
    }
yaddrhigh:
    .for (var y = 0; y < maxy; y++)
    {
        .byte >(vic20.vic_charset + ((y & 15) + (maxx*2 * floor(y / 16))))
    }

xaddrlowmc:
    .for (var x = 0; x < maxx; x+=8)
    {
        .for (var t = 0; t < 4; t++)
        {
            .var r = <x
            .byte r
        }
    }
xaddrhighmc:
    .for (var x = 0; x < maxx; x+=8)
    {
        .for (var t = 0; t < 4; t++)
        {
            .var r = >x
            .byte r
        }
    }

xaddrlowhr:
    .for (var x = 0; x < maxx; x+=8)
    {
        .for (var t = 0; t < 8; t++)
        {
            .var r = <(x*2)
            .byte r
        }
    }
xaddrhighhr:
    .for (var x = 0; x < maxx; x+=8)
    {
        .for (var t = 0; t < 8; t++)
        {
            .var r = >(x*2)
            .byte r
        }
    }

xmaskmc:
    .for (var x = 0; x < maxx; x+=2)
    {
        .var r1 = (%11 << (6-((x-8) & $7)))
        .byte r1
    }

xmaskhr:
    .for (var x = 0; x < maxx; x++)
    {
        .var r1 = (%1 << (7-(x & $7)))
        .byte r1
    }

xpixelmc11:
    .byte %11000000, %00110000, %00001100, %00000011
xpixelmc01:
    .byte %01000000, %00010000, %00000100, %00000001
xpixelmc10:
    .byte %10000000, %00100000, %00001000, %00000010
xpixelmc00:
    .byte $0, $0, $0, $0
xpixelhr:
    .byte $80, $40, $20, $10, $08, $04, $02, $01

sine:
    .fill 320, 100 + 100*sin(toRadians(i*360/320)) // Generates a sine curve
}
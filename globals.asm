#importonce

.namespace vic20 {
    .label vic = $9000
    .label vic_charset = $1100 // with mem-exp
    .label vic_colorram = 37888 // or 38400 if vic+2/bit7 is 0 
    .label vic_videoram = $1000
}
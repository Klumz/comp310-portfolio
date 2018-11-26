    .inesprg 1
    .ineschr 1
    .inesmap 0
    .inesmir 1

; ---------------------------------------------------------------------------

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
OAMADDR   = $2003
OAMDATA   = $2004
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
OAMDMA    = $4014
JOYPAD1	  = $4016
JOYPAD2   = $4017

BUTTON_A      = %10000000
BUTTON_UP     = %00001000

	.rsset $0010
joypad1_state       .rs 1
player_speed        .rs 2     ; in subpixels/frames -- 16 bits
player_position_sub .rs 1  ; in subpixels

	.rsset $0200
sprite_player	   .rs 4

	.rsset $0000
SPRITE_Y		   .rs 1
SPRITE_TILE        .rs 1
SPRITE_ATTRIB      .rs 1
SPRITE_X 		   .rs 1

GRAVITY                = 1
FLAP_SPEED             = -1 * 100   ; in subpixels/frame
SCREEN_BOTTOM_Y        = 224

    .bank 0
    .org $C000

; Initialisation code based on https://wiki.nesdev.com/w/index.php/Init_code
RESET:
    SEI        ; ignore IRQs
    CLD        ; disable decimal mode
    LDX #$40
    STX $4017  ; disable APU frame IRQ
    LDX #$ff
    TXS        ; Set up stack
    INX        ; now X = 0
    STX PPUCTRL  ; disable NMI
    STX PPUMASK  ; disable rendering
    STX $4010  ; disable DMC IRQs

    ; Optional (omitted):
    ; Set up mapper and jmp to further init code here.

    ; If the user presses Reset during vblank, the PPU may reset
    ; with the vblank flag still true.  This has about a 1 in 13
    ; chance of happening on NTSC or 2 in 9 on PAL.  Clear the
    ; flag now so the vblankwait1 loop sees an actual vblank.
    BIT PPUSTATUS

    ; First of two waits for vertical blank to make sure that the
    ; PPU has stabilized
vblankwait1:  
    BIT PPUSTATUS
    BPL vblankwait1

    ; We now have about 30,000 cycles to burn before the PPU stabilizes.
    ; One thing we can do with this time is put RAM in a known state.
    ; Here we fill it with $00, which matches what (say) a C compiler
    ; expects for BSS.  Conveniently, X is still 0.
    TXA
clrmem:
    LDA #0
    STA $000,x
    STA $100,x
    STA $300,x
    STA $400,x
    STA $500,x
    STA $600,x
    STA $700,x  ; Remove this if you're storing reset-persistent data

    ; We skipped $200,x on purpose.  Usually, RAM page 2 is used for the
    ; display list to be copied to OAM.  OAM needs to be initialized to
    ; $EF-$FF, not 0, or you'll get a bunch of garbage sprites at (0, 0).

    LDA #$FF
    STA $200,x

    INX
    BNE clrmem

    ; Other things you can do between vblank waits are set up audio
    ; or set up other mapper registers.
   
vblankwait2:
    BIT PPUSTATUS
    BPL vblankwait2

    ; End of initialisation code

	JSR InitialiseGame
	
    LDA #%10000000 ; Enable NMI
    STA PPUCTRL

    LDA #%00010000 ; Enable sprites
    STA PPUMASK

    ; Enter an infinite loop
forever:
    JMP forever

; ---------------------------------------------------------------------------
	
InitialiseGame:   ; Begin subroutine
    ; Reset the PPU high/low latch
    LDA PPUSTATUS

    ; Write address $3F10 (background colour) to the PPU
    LDA #$3F
    STA PPUADDR
    LDA #$10
    STA PPUADDR

    ; Write the background colour
    LDA #$1
    STA PPUDATA

    ; Write the palette colours (your character)
    LDA #$17
    STA PPUDATA
	LDA #$2C
    STA PPUDATA
	LDA #$2D
    STA PPUDATA
	
	LDA #$30
    STA PPUDATA
	LDA #$2C
    STA PPUDATA
	LDA #$2D
    STA PPUDATA
	LDA #$17
    STA PPUDATA
	
	
    ; Write sprite data for sprite 0
    LDA #230    ; Y position
    STA $0200
    LDA #0      ; Tile number
    STA $0201
    LDA #0      ; Attributes
    STA $0202
    LDA #60    ; X position
    STA $0203
	
	; Write sprite data for sprite 1
    LDA #223    ; Y position
    STA $0204
    LDA #1      ; Tile number
    STA $0205
    LDA #0      ; Attributes
    STA $0206
    LDA #190    ; X position
    STA $0207

	RTS ; End subroutine

; NMI is called on every frame
NMI:
	; Increment x position of sprite
    LDA $0207
    CLC
    ADC #-1
    STA $0207


	; Initialise controller 1
	LDA #1
	STA JOYPAD1
	LDA #0
	STA JOYPAD1 

	; Read joypad state
    LDX #0
    STX joypad1_state
ReadController:
    LDA JOYPAD1
    LSR A
    ROL joypad1_state
    INX
    CPX #8
    BNE ReadController
	
	; React to Up button
    LDA joypad1_state
    AND #BUTTON_UP
    BEQ ReadUp_Done  
	; Set player speed
	LDA #LOW(FLAP_SPEED)
	STA player_speed
	LDA #HIGH(FLAP_SPEED)
	STA player_speed+1
ReadUp_Done:


	; Update player sprite
	; First, update speed
	LDA player_speed     ; Low 8 bits
	CLC
	ADC #LOW(GRAVITY)
	STA player_speed
	LDA player_speed+1   ; High 8 bits
	ADC #HIGH(GRAVITY)   ; NB: *don't* clear the carry flag!
	STA player_speed+1
	
	; Second, update position
	LDA player_position_sub     ; Low 8 bits
	CLC
	ADC player_speed
	STA player_position_sub
	LDA sprite_player+SPRITE_Y  ; High 8 bits
	ADC player_speed+1			; NB: *don't* clear the carry flag!
	STA sprite_player+SPRITE_Y
	
	; Check for top or bottom of screen
	CMP #SCREEN_BOTTOM_Y       ; Accumulator already contains y position
	BCC UpdatePlayer_NoClamp
	; Check sign of speed
	LDA player_speed+1
	BMI UpdatePlayer_ClampToTop
	LDA #SCREEN_BOTTOM_Y-1     ; Clamp to bottom
	JMP UpdatePlayer_DoClamping
UpdatePlayer_ClampToTop:
	LDA #0					   ; Clamp to top
UpdatePlayer_DoClamping:
	STA sprite_player+SPRITE_Y
	LDA #0                     ; Set player speed to zero
	STA player_speed           ; (both bytes)  
	STA player_speed+1
	
UpdatePlayer_NoClamp:
	
    ; Copy sprite data to the PPU
    LDA #0
    STA OAMADDR
    LDA #$02
    STA OAMDMA

    RTI         ; Return from interrupt

	
    ; Increment x position of sprite
    ;LDA $0203
    ;CLC
    ;ADC #1
    ;STA $0203

    ; Increment y position of sprite
    ;LDA $0204
    ;CLC
    ;ADC #1
    ;STA $0204

	; Copy sprite data to the PPU
    LDA #0
    STA OAMADDR
    LDA #$02
    STA OAMDMA

    RTI         ; Return from interrupt

; ---------------------------------------------------------------------------

    .bank 1
    .org $FFFA
    .dw NMI
    .dw RESET
    .dw 0

; ---------------------------------------------------------------------------

    .bank 2
    .org $0000
    .incbin "comp310.chr"
	
#!/usr/bin/env fish

# constants
set memory_size 4096
set program_start (math 0x200)
set stack_limit 256
set display_width 64
set display_height 32

# initialize memory for programs; MEMORY[0] doesn't actually exist b/c fish
# is one-indexed, but I don't think programs will care; at each address is
# stored the value as a string decimal number lol
set memory ( jot -b 0 (math $memory_size - 1) )

# initialize the rest
set stack
set reg_pc $program_start
set reg_i
set reg_delay
set reg_sound
set reg_v ( jot -b 0 16 )
set display ( jot -b 0 (math "$display_width * $display_height") ) # 64x32 pixels

# fixme: load font into memory!

argparse "stop-after=" "draw-at-end" -- $argv
if set -q _flag_stop_after
  set stop_after $_flag_stop_after
else
  set stop_after -1
end

if set -q _flag_draw_at_end
  set draw_at_end
end

# load program into memory
set program_file $argv[1]
if test -z $program_file
  echo "Usage: fish8.fish program_file"
  exit 1
end
if test ! -e $program_file
  echo "Couldn't load program file \"$program_file\""
  exit 1
end
# can't directly read binary file with read :shrug: dunno why so I need to
# convert it into hex, and then read that, lol
set program_hex ( od -v -t x1 < $program_file | sed -e 's/^[0-9]* *//g' | tr '\n' ' ' | sed -e 's/  */ /g' | sed -e 's/ *$//' )
set program_dec
for hex in (string split ' ' $program_hex)
  set -a program_dec (math "0x$hex")
end
for i in (seq (count $program_dec))
  set index (math $program_start + $i - 1)
  set memory[$index] $program_dec[$i]
end
# echo $memory

function blit_display
  if set -q draw_at_end
    return
  end

  echo -ne '\e[H'
  for i in (seq (count $display))
    if test $display[$i] -eq 1
      echo -ne '\e[7m \e[0m'
    else
      echo -n ' '
    end
    if test (math "($i - 1)%$display_width") -eq (math $display_width - 1)
      printf "\n"
    end
  end
end

function blit_display_simple
  for i in (seq (count $display))
    if test $display[$i] -eq 1
      echo -ne '#'
    else
      echo -n ' '
    end
    if test (math "($i - 1)%$display_width") -eq (math $display_width - 1)
      printf "\n"
    end
  end
end

function draw -a x y height index
  for yi in (seq $y (math "min($y+$height-1, $display_height-1)"))
    set -l sprite_row $memory[$index]
    set index (math $index + 1)
    for xi in (seq $x (math "min($x+8-1, $display_width-1)"))
      set display_idx (math "$yi * $display_width + $xi + 1")
      set display[$display_idx] (math "bitand($sprite_row, 0x80) / 0x80")
      set sprite_row (math "$sprite_row * 2")
    end
  end
  blit_display
end

function crash
  printf "  cpu state: pc=0x%04x i=0x%02x\n" $reg_pc $reg_i
  printf "instruction: hi_byte=0x%02x lo_byte=0x%02x x=0x%02x y=0x%02x nn=0x%02x nnn=0x%03x\n" $hi_byte $lo_byte $x $y $nn $nnn
  echo "crash! $argv"
  exit 1
end

set cycle 0 # number of cycles since start

# fetch-decode-execute ad infinitum
while :
  set hi_byte $memory[$reg_pc]
  set hi_nibble (math "bitand($hi_byte, 0xF0)/16")
  set reg_pc (math $reg_pc + 1)
  set lo_byte $memory[$reg_pc]
  set reg_pc (math $reg_pc + 1)
  set x (math bitand $hi_byte, 0x0F)
  set y (math "bitand($lo_byte, 0xF0)/16")
  set cycle (math $cycle + 1)

  if test $stop_after -ne -1 -a $cycle -gt $stop_after
    break
  end

  # arrays 1-indexed so reg 0 is stored at 16 instead lol
  if test $x = 0
    set x 16
  end
  if test $y = 0
    set y 16
  end

  set n (math "bitand($lo_byte, 0xF)")
  set nn $lo_byte
  set nnn (math "bitand($hi_byte, 0x0f)*256+$lo_byte")
  if test $hi_byte = 0
    if test $lo_byte = (math 0xe0)
      # clear screen
      set display (jot -b 0 (count $display))
    else
      crash
    end
  else if test (math bitand $hi_byte, 0xF0) = (math 0xa0)
    set reg_i $nnn
  else if test $hi_nibble = (math 0x6)
    set reg_v[$x] $nn
  else if test $hi_nibble = (math 0xD)
    # printf "DRAW X=0x%02x Y=0x%02x N=0x%02x XVAL=0x%02x YVAL=0x%02x I=0x%02x\n" $x $y $n $reg_v[$x] $reg_v[$y] $reg_i
    draw $reg_v[$x] $reg_v[$y] $n $reg_i
  else if test $hi_nibble = (math 0x7)
    set reg_v[$x] (math $reg_v[$x] + $nn)
  else if test $hi_nibble = (math 0x1)
    set reg_pc $nnn
  else
      crash "unknown opcode" (printf "0x%x" $hi_nibble)
  end
end

if set -q draw_at_end
  blit_display_simple
end

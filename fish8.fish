#!/usr/bin/env fish

# constants
set -g memory_size 4096
set -g program_start (math 0x200)
set -g stack_limit 256
set -g display_width 64
set -g display_height 32
set -g speed 720 # 700 cycles (instructions) per second
set -g cycles_per_tick (math $speed / 60)

function main
  parse_args $argv
  initialize
  load_program
  main_loop
end

function initialize
  # initialize memory for programs; MEMORY[0] doesn't actually exist b/c fish
  # is one-indexed, but I don't think programs will care; at each address is
  # stored the value as a string decimal number lol
  set -g memory ( jot -b 0 (math $memory_size - 1) )

  # initialize the rest
  set -g stack
  set -g reg_pc $program_start
  set -g reg_i
  set -g reg_delay 0
  set -g reg_sound
  set -g reg_v ( jot -b 0 16 )
  set -g display ( jot -b 0 (math "$display_width * $display_height") ) # 64x32 pixels
  # fixme: load font into memory!
end

function parse_args
  argparse "stop-after=" "draw-at-end" -- $argv
  if set -q _flag_stop_after
    set -g stop_after $_flag_stop_after
  else
    set -g stop_after -1
  end

  if set -q _flag_draw_at_end
    set -g draw_at_end
  end

  # load program into memory
  set -g program_file $argv[1]
  if test -z $program_file
    echo "Usage: fish8.fish program_file"
    exit 1
  end
  if test ! -e $program_file
    echo "Couldn't load program file \"$program_file\""
    exit 1
  end
end

function load_program
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
end

function main_loop
  set -g cycle 0 # number of cycles since start
  set -g start_time (date +"%s")

  # fetch-decode-execute ad infinitum
  while :
    if test $reg_delay -gt 0
      set reg_delay (math $reg_delay - 1)
    end

    tick

    if ! set -q draw_at_end
      blit_display_half_block
    end

    if test $stop_after -ne -1 -a $cycle -gt $stop_after
      break
    end
  end

  if set -q draw_at_end
    blit_display_simple
  end
end

# do one 1/60 of a second
function tick
  for subcycle in (seq $cycles_per_tick)
    set cycle (math $cycle + 1)
    fetch
    decode_execute
  end
end

# parse the instruction at reg_pc and increment reg_pc
function fetch
  set -g hi_byte $memory[$reg_pc]
  set -g hi_nibble (math "bitand($hi_byte, 0xF0)/16")
  set -g reg_pc (math $reg_pc + 1)
  set -g lo_byte $memory[$reg_pc]
  set -g reg_pc (math $reg_pc + 1)
  set -g x (math bitand $hi_byte, 0x0F)
  set -g y (math "bitand($lo_byte, 0xF0)/16")

  # arrays 1-indexed so reg 0 is stored at 16 instead lol
  set -g real_x $x # without the 16 hack
  if test $x = 0
    set x 16
  end
  if test $y = 0
    set y 16
  end

  set -g n (math "bitand($lo_byte, 0xF)")
  set -g nn $lo_byte
  set -g nnn (math "bitand($hi_byte, 0x0f)*256+$lo_byte")
end

function decode_execute
  if test $hi_byte -eq 0
    if test $lo_byte -eq (math 0xe0) # clear screen
      set display (jot -b 0 (count $display))
    else if test $lo_byte -eq (math 0xee) # return
      if test (count $stack) -eq 0
        crash "stack underflow"
      end
      set reg_pc $stack[(count $stack)]
      set -e stack[(count $stack)]
    else
      crash "unknown 0x00 code:" (printf "0x%02x" $lo_byte)
    end
  else if test $hi_nibble -eq (math 0xa)
    set reg_i $nnn
  else if test $hi_nibble -eq (math 0x6)
    set reg_v[$x] $nn
  else if test $hi_nibble -eq (math 0xD)
    # printf "DRAW X=0x%02x Y=0x%02x N=0x%02x XVAL=0x%02x YVAL=0x%02x I=0x%02x\n" $x $y $n $reg_v[$x] $reg_v[$y] $reg_i
    draw $reg_v[$x] $reg_v[$y] $n $reg_i
  else if test $hi_nibble -eq (math 0x7)
    set reg_v[$x] (math "($reg_v[$x] + $nn) % 256")
  else if test $hi_nibble -eq (math 0x1)
    set reg_pc $nnn
  else if test $hi_nibble -eq (math 0x2) # CALL NNN (subroutine)
    set -a stack $reg_pc
    set reg_pc $nnn
  else if test $hi_nibble -eq (math 0x3) # skip if VX == NN
    if test $reg_v[$x] -eq $nn
      set reg_pc (math $reg_pc + 2)
    end
  else if test $hi_nibble -eq (math 0x4) # skip if VX != NN
    if test $reg_v[$x] -ne $nn
      set reg_pc (math $reg_pc + 2)
    end
  else if test $hi_nibble -eq (math 0x5) # skip if VX == VY
    if test $reg_v[$x] -eq $reg_v[$y]
      set reg_pc (math $reg_pc + 2)
    end
  else if test $hi_nibble -eq (math 0x8) # logic and math
    if test $n -eq 0
      set reg_v[$x] $reg_v[$y]
    else if test $n -eq 1
      set reg_v[$x] (math "bitor($reg_v[$x], $reg_v[$y])")
    else if test $n -eq 2
      set reg_v[$x] (math "bitand($reg_v[$x], $reg_v[$y])")
    else if test $n -eq 3
      set reg_v[$x] (math "bitxor($reg_v[$x], $reg_v[$y])")
    else if test $n -eq 4
      set -l sum (math $reg_v[$x] + $reg_v[$y])
      set -l flag 0
      if test $sum -gt 255
        set sum (math $sum % 256)
        set flag 1
      end
      set reg_v[$x] $sum
      set reg_v[15] $flag
    else if test $n -eq 5
      subtract $reg_v[$x] $reg_v[$y]
    else if test $n -eq 6
      set -f flag (math "bitand($reg_v[$x], 0x01)")
      set reg_v[$x] (math "floor($reg_v[$x] / 2)")
      set reg_v[15] $flag
    else if test $n -eq 7
      subtract $reg_v[$y] $reg_v[$x]
    else if test $n -eq 14
      set -f flag (math "bitand($reg_v[$x], 0x80)/128")
      set reg_v[$x] (math "floor($reg_v[$x] * 2) % 256")
      set reg_v[15] $flag
    else
      crash "unknown math code" (printf "0x%x" $n)
    end
  else if test $hi_nibble -eq (math 0x9) # skip if VX != VY
    if test $reg_v[$x] -ne $reg_v[$y]
      set reg_pc (math $reg_pc + 2)
    end
  else if test $hi_nibble -eq 12
    set -l r (random 0 255)
    set reg_v[$x] (math "bitand($r, $nn)")
  else if test $hi_nibble -eq 14
    if test $lo_byte -eq (math 0x9e) # skip if key pressed
      : # noop b/c no keyboard support
    else if test $lo_byte -eq (math 0xa1) # skip if key not pressed
      # always skip b/c no keyboard support
      set reg_pc (math $reg_pc + 2)
    else
      crash "unknown 0xE0 code:" (printf "0x%02x" $lo_byte)
    end
  else if test $hi_nibble -eq 15
    if test $lo_byte -eq (math 0x07)
      set reg_v[$x] $reg_delay
    else if test $lo_byte -eq (math 0x15)
      set reg_delay $reg_v[$x]
    else if test $lo_byte -eq (math 0x18) # set sound timer
      # no sound support
    else if test $lo_byte -eq (math 0x1e) # i = i + vx
      set reg_i (math $reg_i + $reg_v[$x])
      if test $reg_i -gt (math 0xFFF)
        set reg_i (math $reg_i % 0x1000)
        set reg_v[15] 1
      end
    else if test $lo_byte -eq (math 0x33) # bcd
      set memory[$reg_i] (math "floor($reg_v[$x] / 100 % 10)")
      set memory[(math $reg_i + 1)] (math "floor($reg_v[$x] / 10 % 10)")
      set memory[(math $reg_i + 2)] (math "floor($reg_v[$x] % 10)")
    else if test $lo_byte -eq (math 0x55) # write registers
      for i in (seq 0 $real_x)
        set -f addr (math $i + $reg_i)
        if test $i -eq 0
          set memory[$addr] $reg_v[16]
        else
          set memory[$addr] $reg_v[$i]
        end
      end
    else if test $lo_byte -eq (math 0x65) # load registers
      for i in (seq 0 $real_x)
        set -f addr (math $i + $reg_i)
        set -f value $memory[$addr]
        if test $i -eq 0
          set reg_v[16] $value
        else
          set reg_v[$i] $value
        end
      end
    else
      crash "unknown 0xF0 code:" (printf "0x%02x" $lo_byte)
    end
  else
    crash "unknown opcode" (printf "0x%x" $hi_nibble)
  end
end

function blit_display_half_block
  # echo -ne '\e[?25l' # make cursor invisible
  echo -ne '\e[H' # go to top left
  for y in (seq 0 2 (math $display_height - 1))
    for x in (seq 1 $display_width)
      set -l upper $display[(math "$y*$display_width + $x")]
      set -l lower $display[(math "$y*$display_width + $display_width + $x")]
      if test -z $upper
        reset
        echo $y $display_width $x
        exit
      end
      if test $upper -eq 1
        printf "\e[38;5;255m"
      else
        printf "\e[38;5;0m"
      end
      if test $lower -eq 1
        printf "\e[48;5;255m"
      else
        printf "\e[48;5;0m"
      end
      printf "\u2580"
    end
    echo
  end
  printf "\e[1;0m"
  printf "pc: 0x%03x "  $reg_pc
  printf "i: 0x%03x " $reg_i
  # printf "sk: "
  # for s in $stack
  #   printf "0x%04x " $s
  # end
  set time_passed (math (date +'%s') - $start_time)
  if test $time_passed -gt 1
    printf "cps: %.0f" (math $cycle / $time_passed)
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
  set reg_v[15] 0
  set x (math $x % $display_width)
  set y (math $y % $display_height)
  for yi in (seq $y (math "min($y+$height-1, $display_height-1)"))
    set -l sprite_row $memory[$index]
    set index (math $index + 1)
    for xi in (seq $x (math "min($x+8-1, $display_width-1)"))
      set display_idx (math "$yi * $display_width + $xi + 1")
      set old_pixel $display[$display_idx]
      set new_pixel (math "bitand($sprite_row, 0x80) / 0x80")

      if test $old_pixel -eq 1 -a $new_pixel -eq 1
        set display[$display_idx] 0
        set reg_v[15] 1
      else if test $new_pixel -eq 1
        set display[$display_idx] 1
      end

      set sprite_row (math "$sprite_row * 2")
    end
  end
  # if ! set -q draw_at_end
  #   blit_display_half_block
  # end
end

function subtract -a a b
  set -f flag 0
  if test $a -ge $b
    set -f flag 1
  end
  set reg_v[$x] (math $a - $b)
  if test $flag -eq 0
    set reg_v[$x] (math $reg_v[$x] + 256)
  end
  set reg_v[15] $flag
end

function crash
  printf "  cpu state: pc=0x%04x i=0x%02x\n" $reg_pc $reg_i
  printf "instruction: hi_byte=0x%02x lo_byte=0x%02x x=0x%02x y=0x%02x nn=0x%02x nnn=0x%03x\n" $hi_byte $lo_byte $x $y $nn $nnn
  echo "crash! $argv"
  exit 1
end

main $argv


# Fish8

## Notes on the Fish Shell Language

#### Reading a Binary File
I couldn't figure out a good way to read in a binary file. The [read command](https://fishshell.com/docs/current/cmds/read.html) seemed to choke on the NULL bytes as did `set myvar (cat file.bin)`

#### Arrays are indexed starting at 1
This is painful, at least when writing a program like Fish8. According to the docs, there's a good reason for this, however:

> List indices start at 1 in fish, not 0 like in other languages. This is because it requires less subtracting of 1 and many common Unix tools like seq work better with it (seq 5 prints 1 to 5, not 0 to 5).
[The fish language § Lists](https://fishshell.com/docs/current/language.html#lists)

#### if not / unless
```
if set -q myvar
    echo "myvar is set"
end

# how do I write the inverse? this actually works, but I don't see documentation
# for it
if ! set -q myvar
    echo "myvar is not set"
end
```

#### breakpoints don't work in scripts
https://github.com/fish-shell/fish-shell/issues/4823

## See Also
- [Guide to making a CHIP-8 emulator by Tobias V. Langhoff](https://tobiasvl.github.io/blog/write-a-chip-8-emulator/) &mdash; awesome resource, thanks Tobias!
- [Timendus/chip8-test-suite](https://github.com/Timendus/chip8-test-suite) &mdash; all the test roms are from here; awesome resource!


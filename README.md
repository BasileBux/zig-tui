# Zig TUI

This is in no way a library. It cannot be compiled into a library. But if you want to
do some terminal stuff manually without any library (only std), this can be a good starting point.
I am also in no way claiming that the code is good or will work for your use case. It can
just serve as an example. 

The main code is in `src/term.zig`. The `init` function setups your terminal in raw mode and
creates an alternative screen buffer. The `getInput` function reads the input in a non-blocking
way. 

The `src/ui.zig` file contains an example on how the library can be used and also provides
a basic signal handling for `SIGWINCH` and `SIGINT`.

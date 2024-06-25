# Gcc Arm To Zig

Gcc Arm to Zig, or `gatz`, is both a command line program and a zig module that provides utilities for porting projects using the `gcc-arm-none-eabi` compiler to Zig. It is intended to be used with freestanding Arm Cortex-M targets (micro-controllers). Currently only Cortex-M targets are supported, however this could be expanded in the future if there's demand for it. 

Once mature enough, this project will have releases corresponding to Zig releases. For now, this tracks Zig version `0.13.0`. 
# Installing

Add `gatz` as a dependency to `build.zig.zon` like so:
``` zon
.dependencies = .{
    .gatz = .{
        .url = "git+https://github.com/haydenridd/gcc-arm-to-zig"
    },
},
```

For using the build utilities provided in `build.zig` you can now add:
``` Zig
const gatz = @import("gatz");
```

If you want to use `gatz` in application code you can add the following to `build()` in `build.zig`:
``` Zig
const gatz = b.dependency("gatz", .{});
exe.root_module.addImport("gatz", gatz.module("gatz"));
```


## Command Line Utility
The `gatz` CLI serves a dual purpose:
- Translating GCC "architecture" flags like `-mcpu, -mfpu, -mfloat-abi, -mthumb/-marm` to Zig target arguments
- Validating the combination of flags used (not even GCC does this!)

This utility can save a lot of time because figuring out, for example, that the following flags:
```
--mcpu=cortex-m7 --mfloat-abi=hard --mfpu=fpv5-sp-d16
```

Translate to:
```
-Dtarget=thumb-freestanding-eabihf -Dcpu=cortex_m7+fp_armv8d16sp
```

Is extremely non-trivial and involves lots of datasheet diving. With `gatz` this process is as simple as:
```
gatz --mcpu=cortex-m7 --mfloat-abi=hard --mfpu=fpv5-sp-d16
Translated `zig build` options: -Dtarget=thumb-freestanding-eabihf -Dcpu=cortex_m7+fp_armv8d16sp
```

It will check for invalid configurations:
```
gatz --mcpu=cortex-m7 --mfloat-abi=hard --mfpu=fpv2
--mfpu=fpv2 is not a valid FPU, see info command for valid FPUs
```

And can display valid configurations:
```
gatz info --mcpu=cortex-m7
CPU: cortex-m7       | Float ABIS: soft,softfp,hard | Fpu Types: vfpv4,vfpv4-d16,fpv4-sp-d16,fpv5-d16,fpv5-sp-d16
```

See `gatz -h` for full documentation.

## Build Utilities

`gatz` provides utilities for use in a `build.zig` file that make things like target selection and linking in `arm-none-eabi-gcc`'s pre-compiled Newlib libc much easier than in vanilla Zig. See the [build.zig for an example project using `gatz`](example/build.zig) for a more detailed walkthrough.

## Contributing
Github issues for feature requests/bugs are welcome! PR's are also welcome!

## TODO:
- Add some dummy assembly files that excercise instructions for each possible target combo (fpu, endianness, etc.) + ensure that each target configuration can compile said assembly code
    - Add this to CI
- Expansion beyond Cortex-M targets if enough interest
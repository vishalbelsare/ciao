# Ciao Engine

This directory contains both C (`.h`, `.c`) and Ciao (`.pl`) sources
that corresponds to the Ciao engine and runtime. See `ciaoengine.pl`
for the main module that defines the Ciao engine.

The following source files are not intended to be used as Ciao
modules:

  - `absmach_def.pl`: Abstract machine definitions
  - `ciaoengine.pl`: The main engine
  - `ciaoengine_doc.pl`: Documentation for `ciaoengine.pl`

# Benchmarking

Some engine performance benchmarks can be run (use the pipe for a
short report) with:

```
ciao oc:tests mtsys ciao 2>&1 | grep -e "\(time\|name\)"
```

To see the performance of the `optim-comp` branch in bytecode
mode use the following:
```
ciao oc:tests mtsys ciao2 2>&1 | grep -e "\(time\|name\)"
```

# TODO/Bugs/Issues

 - No initialization directive is executed in engine modules. Show
   warning/error when `:- initialization` is used in those modules?

 - Status of `eval/1` assertions:

   - ADDED TO:
     `arithmetic.pl` `atomic_basic.pl` `basic_props.pl` `basiccontrol.pl`
     `term_basic.pl` `term_typing.pl` `term_compare.pl`

   - MISSING FOR: `attributes.pl` `data_facts.pl`
    `debugger_support.pl` `exceptions.pl` `hiord_rt.pl` `internals.pl`
    `io_aux.pl` `io_basic.pl` `mattr_global.pl` `mexpand.pl`
    `prolog_flags.pl` `stream_basic.pl` `syntax_extensions.pl`
    `system_info.pl`

 - Rebuilding the engine (sometimes) require manually erasing and
   updating dates. E.g.:
```
rm -rf build/eng/ciaoengine; touch core/engine/absmach_def.pl; time ./ciao-boot.sh build --bin core.ciaobase # default
rm -rf build/oc-cache; time ciao oc:build # optim-comp
```

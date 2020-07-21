#!/bin/sh
#
#  build_car.sh
#
#  Builder for .car archive files
#
#  Copyright (C) 2015-2020 Jose F. Morales, Ciao Developer Team
#
# ===========================================================================
#
# Input (environment variables):
#   ENG_CFG (optional)
#
# ---------------------------------------------------------------------------

# Exit immediately if a simple command exits with a non-zero status
set -e

# Physical directory where the script is located
_base=$(e=$0;while test -L "$e";do d=$(dirname "$e");e=$(readlink "$e");\
        cd "$d";done;cd "$(dirname "$e")";pwd -P)

old_dir=`pwd`; cd "$_base/../.."; ciaoroot=`pwd`; cd "$old_dir"; old_dir=
sh_src_dir="$ciaoroot/builder/sh_src"

# ===========================================================================

not_configured() {
    [ ! -f "$bld_cfgdir/config_sh" ] || [ ! -f "$bld_cfgdir/meta_sh" ]
}

# Load config_sh and meta_sh
config_loaded_p=""
ensure_config_loaded() {
    if [ x"$config_loaded_p" != x"" ]; then return; fi
    if not_configured; then
        echo "ERROR: no $eng_cfg configuration found for $cardir" >&2
        exit 1
    fi
    . "$bld_cfgdir/meta_sh"
    . "$bld_cfgdir/config_sh"
    config_loaded_p=yes # Mark as loaded
}

# ---------------------------------------------------------------------------

# Is there a compiled executable?
car_exists_exec() { # cardir
    set_car_vars "$1"
    if not_configured; then return 1; fi
    ensure_config_loaded
    [ -f "$bld_objdir/$eng_name""$EXECSUFFIX" ]
}

# Run an existing executable (with updated environment variables)
# (only for boot)
car_run_exec_boot() { # cardir [opts]
    set_car_vars "$1"; shift
    ensure_config_loaded
    local engexec="$bld_objdir/$eng_name""$EXECSUFFIX"
    # TODO: allow debug, i.e.,
    #   engdbg="lldb -o run -o quit --"
    #   engopts="--trace-calls --trace-instr --debug-gc"
    # TODO: simplify?
    # Select paths for ciao_builder compilation and execution
    # ('crossp' added from "$sh_boot_dir/autoboot.sh")
    #
    # Alias path for ciaobld(_) since bundles are not scanned yet
    local default_ciaoaliaspath="ciaobld=`crossp "$ciaoroot/builder/src"`"
    # Default CIAOPATH for bootstrap (restricts bundle scan and bundle get
    # to <ciaoroot> -- otherwise 'get devenv' will not work)
    # TODO: document
    local default_ciaopath=`crossp "$ciaoroot"`
    CIAOPATH="$default_ciaopath" \
    CIAOALIASPATH="$default_ciaoaliaspath" \
    CIAOROOT=`crossp "$ciaoroot"` \
    CIAOHDIR=`crossp "$bld_hdir"` \
    CIAOENGINE=`crossp "$engexec"` \
        "$engexec" "$@"
}

# Path translation from this script to Ciao
# (for cross-compilation)
case `uname -s` in
    MINGW*) pathtrans=mingw_to_win ;;
    *) pathtrans=no ;;
esac

crossp() {
    if [ x"$pathtrans" = x"mingw_to_win" ]; then
        cygpath -w "$@"
    else
        echo "$@"
    fi
}

# ---------------------------------------------------------------------------
# Clone a bootstrap engdir from $booteng_cdir to $cardir

car_clone_boot() { # booteng_cdir cardir
    local oldpwd=`pwd`
    local booteng_cdir="$1"
    mkdir -p "$2"
    set_car_vars "$2"
    # TODO: copy or link?
    # Link all .c files from booteng_cdir
    mkdir -p "$bld_cdir"
    cd "$bld_cdir"
    # Getting files generated by emugen
    linkhere "$booteng_cdir"/*.c
    linkhere "$booteng_cdir"/"eng_info_mk"
    linkhere "$booteng_cdir"/"eng_info_sh"
    # Link all .h files from booteng_cdir
    mkdir -p "$bld_hdir/ciao"
    cd "$bld_hdir/ciao"
    # Getting files generated by emugen
    linkhere "$booteng_cdir"/*.h
    cd "$oldpwd"

    # TODO: do it here?
    update_file "$bld_cdir/eng_static_mod.c" <<EOF
EOF
}

# ---------------------------------------------------------------------------
# Link imports:
#  - prepare $bld_cdir (for .c source files, including autogenerated)
#  - prepare $bld_hdir (for .h headers using eng_h_alias layout)
#  - source files are taken from the eng_srcpath (the first occurrence has preference)

# TODO: A bit slow (0.2s); reimplement in C? or generate a file list
car_link_imports() {
    local oldpwd=`pwd`

    if [ x"$oc_car" = x"yes" ]; then
        # TODO:[optim_comp] pregenerate and avoid engine__main hack
        CFILES=`c_files_oc`
        update_file "$bld_cdir/eng_info_mk" <<EOF
ENG_STUBMAIN = engine__main.c
ENG_CFILES = $(echo $CFILES)
ENG_HFILES=
ENG_HFILES_NOALIAS=
EOF
        update_file "$bld_cdir/eng_info_sh" <<EOF
ENG_STUBMAIN="engine__main.c"
ENG_CFILES="$CFILES"
ENG_HFILES=""
ENG_HFILES_NOALIAS=""
EOF
    fi

    # Load engine info
    # TODO: add all $eng_srcpath to VPATH?
    . "$bld_cdir/eng_info_sh"

    mkdir -p "$bld_cdir"
    mkdir -p "$bld_hdir"
    mkdir -p "$bld_hdir/$eng_h_alias"

    # Link all .c files
    cd "$bld_cdir"
    # TODO: use ENG_CFILES to avoid autogenerated files?
    local src
    for src in $eng_srcpath; do
        linkhere "$src"/*.c
    done

    # Link all .h files
    if [ x"$oc_car" = x"no" ]; then
        cd "$bld_hdir/$eng_h_alias"
        # TODO: use ENG_CFILES to avoid autogenerated files?
        for src in $eng_srcpath; do
            linkhere "$src"/*.h
        done
        # Link special .h files (without eng_h_alias)
        cd "$bld_hdir"
        for f in $ENG_HFILES_NOALIAS; do
            for src in $eng_srcpath; do
                linkhere "$src"/"$f"
            done
        done
    else
        cd "$bld_cdir"
        for src in $eng_srcpath; do
            linkhere "$src"/*.h
        done
        # TODO:[optim_comp] hack for compatibility (do it properly)
        update_file "$bld_hdir/ciao_prolog.h" <<EOF
#include <engine/engine__ciao_prolog.h>
EOF
        mkdir -p "$bld_hdir/ciao"
        update_file "$bld_hdir/ciao/datadefs.h" <<EOF
#include <engine/basiccontrol.native.h>
EOF
        update_file "$bld_hdir/ciao/support_macros.h" <<EOF
#include <engine/basiccontrol.native.h>
EOF
    fi

    cd "$oldpwd"
}

# Link or copy if newer (if $use_symlinks==no)
# (Do nothing if file does not exist)
linkhere() {
    local i b
    local use_symlinks
    # Do not use symlinks in Windows
    case $CIAOOS in
        Win32) use_symlinks=no ;;
        *) use_symlinks=yes ;;
    esac
    if [ x"$use_symlinks" = x"no" ]; then
        for i in "$@"; do
            b=`basename "$i"`
            if [ ! -r "$i" ]; then
                true
            elif [ -e "$b" -a '(' ! "$i" -nt "$b" ')' ]; then
                true
            else
                cp "$i" "$b"
            fi
        done
    else
        for i in "$@"; do
            b=`basename "$i"`
            if [ ! -r "$i" ]; then
                true
            elif [ -e "$b" ]; then
                true
            else
                ln -s "$i" "$b"
            fi
        done
    fi
}

# Writes the input to FILE, only if contents are different (preserves timestamps)
# TODO: Use 'update_file' in other parts of the build process (for some _auto.pl files and configuration options)
update_file() { # FILE
    local t="$1""-tmp-$$"
    cat > "$t"
    if cmp -s "$1" "$t"; then # same, keep original
        rm "$t"
    else # different or new
        mv "$t" "$1" # atomically replace "$1"
    fi
}

c_files_oc() {
    local has_stub=no
    echo "eng_build_info.c"
    for m in `cat "$cardir"/native_modules`; do
        if [ x"${m}" = x"engine__main" ]; then
            has_stub=yes
            continue
        fi
        echo "${m}.c"
    done
    if [ x"$has_stub" = x"no" ]; then
        touch "$bld_cdir/engine__main.c" # TODO: fake hardwired stub for standalone executables (e.g., ImProlog)
    fi
}

# ---------------------------------------------------------------------------
# Configuration options
# TODO:[optim_comp] merge, update, make sure that docs are available 

config_opts="\
OPTIM_LEVEL \
DEBUG_LEVEL \
DEBUG_TRACE \
LOWRTCHECKS \
PROFILE_INSFREQ \
PROFILE_INS2FREQ \
PROFILE_BLOCKFREQ \
PROFILE_STATS \
USE_THREADS \
OS \
ARCH \
M32 \
M64 \
CUSTOM_CC \
CUSTOM_LD \
EXTRA_CFLAGS \
EXTRA_LDFLAGS"

defval__OPTIM_LEVEL=optimized
#  --optim-level=[optimized]       Optimization level 
#
#    optimized       -- Turn on optimization flags
#    normal          -- Normal emulator (non-optimized code)

defval__DEBUG_LEVEL=nodebug
#  --debug-level=[nodebug]         Level of debugging (CC)
#
#    nodebug         -- Do not include debug information or messages
#    debug           -- Emulator with C level debugging info available
#                       plus extended C compilation warnings
#    paranoid-debug  -- Emulator with C level debugging info available
#                       plus paranoid C compilation warnings
#
#    Enable debugging options in the C compiler

# TODO:[optim-comp] port to core
defval__DEBUG_TRACE=no
#  --debug-trace=[no]
#
#    yes
#    no
#
#    Enable debug trace (controled with runtime options)

# TODO:[optim-comp] port to core
defval__LOWRTCHECKS=no
#  --lowrtchecks=[no]
#
#    yes
#    no
#
#    Enable low-level runtime checks (preconditions, postconditions,
#    etc.) for the engine, emulator and runtime. A bug-free emulator
#    should not violate any of these checks.

# TODO:[optim-comp] port to core
defval__PROFILE_INSFREQ=no
#  --profile-insfreq=[no]
#
#    yes
#    no
#
#    Profile instruction frequencies (note: execute a wamtime profile to
#    ensure that the overhead compensation is correct)

# TODO:[optim-comp] port to core
defval__PROFILE_INS2FREQ=no
#  --profile-ins2freq=[no]
#
#    yes
#    no
#
#    Profile instruction pairs frequencies (note: execute a wamtime profile to
#    ensure that the overhead compensation is correct) (EXPERIMENTAL)

# TODO:[optim-comp] port to core
defval__PROFILE_BLOCKFREQ=no
#  --profile-blockfreq=[no]
#
#    yes
#    no
#
#    Profile block frequencies (EXPERIMENTAL)

# TODO:[optim-comp] port to core
defval__PROFILE_STATS=no
#  --profile-stats=[no]
#
#    yes
#    no
#
#    Collect statistics about the execution (load time of static bytecode,
#    used memory, garbage collections, etc.)

defval__USE_THREADS="yes"
defval__OS=""
defval__ARCH=""
defval__M32=""
defval__M64=""
defval__CUSTOM_CC=""
defval__CUSTOM_LD=""
defval__EXTRA_CFLAG=""
defval__EXTRA_LDFLAGS=""

# ---------------------------------------------------------------------------

# TODO: see scan_bootstrap_opts.sh

# Parse options from command-line, store in opt__<<Name>>
parse_config_opts() {
    local name Name value option
    for option in "$@"; do
        case "$option" in
            --*=*)
                name="`echo "$option" | sed -e 's/=.*//;s/--//'`"
                if test -n "`echo $name | sed 's/[a-z0-9-]//g'`"; then
                    echo "{error: invalid option name $name}" 1>&2
                    exit 1
                fi
                name="`echo "$name" | sed -e 's/-/_/g'`" # replace - by _
                value="`echo "$option" | sed 's/[^=]*=//'`"
                Name=`printf "%s" "$name" | tr '[:lower:]' '[:upper:]'` # name in uppercase
                eval "opt__$Name='$value'" ;;
            *)
                nonoption="$nonoption $option" ;;
        esac
    done

    for s_o in $config_opts; do
        # Set default value of s_o if not set by the user
        eval test -n '"${opt__'${s_o}'}"' || \
            eval opt__${s_o}='"${defval__'${s_o}'}"'
    done
}

# ---------------------------------------------------------------------------
# Configure

# TODO: CIAOOPTS is needed now?
# TODO: CIAOCCOPTS, and CIAOLDOPTS are extra options for ImProlog; better way?

car_config() { # (configure options)
    set_car_vars "$1"; shift

    # Exit if there is an existing configuration
    # TODO: not done for optim_comp, is it OK?
    if ! not_configured && [ x"$oc_car" = x"no" ]; then
        return 0
    fi

    parse_config_opts ${CIAOOPTS} "$@"
    if [ x"$oc_car" = x"no" ]; then
        eng_name="ciaoengine" # TODO: customize
    else
        eng_name="arch" # TODO: customize
    fi

    if [ x"$oc_car" = x"yes" ]; then
        H_PATH="-I$bld_hdir -I$bld_cfgdir" # TODO: better way?
        COMPILER_VERSION=`cat "$cardir"/compiler_version`
        opt__EXTRA_CFLAGS="-Werror -DWITH_COMPILER_VERSION=$COMPILER_VERSION $H_PATH $opt__EXTRA_CFLAGS"
        REQUIRE64=`cat "$cardir"/require64`
        if test x"${REQUIRE64}" = x"yes"; then
            opt__M64=yes
        fi
    fi

    if [ x"$CIAOCCOPTS" != x"" ]; then opt__EXTRA_CFLAGS="$CIAOCCOPTS $opt__EXTRA_CFLAGS"; fi
    if [ x"$CIAOLDOPTS" != x"" ]; then opt__EXTRA_LDFLAGS="$CIAOLDOPTS $opt__EXTRA_LDFLAGS"; fi
    eng_h_alias="ciao"

    if [ x"$oc_car" = x"no" ]; then
        eng_srcpath="$ciaoroot/core/engine"
    else
        eng_srcpath="$ciaoroot/core/engine_oc" # TODO: merge
    fi

    if [ x"$opt__OS" = x"" ]; then
        opt__OS=`"$sh_src_dir"/config-sysdep/ciao_sysconf --os`
    fi
    if [ x"$opt__ARCH" = x"" ]; then
        opt__ARCH=`"$sh_src_dir"/config-sysdep/ciao_sysconf --arch`
        # Force 32-bit architecture
        if [ x"$opt__M32" = x"yes" ] ; then
            case $opt__ARCH in
                Sparc64) opt__ARCH=Sparc ;;
                x86_64)  opt__ARCH=i686 ;;
                ppc64)   opt__ARCH=ppc ;;
                *) true ;; # assume 32-bit
            esac
        fi
        # Force 64-bit architecture
        if [ x"$opt__M64" = x"yes" ] ; then
            case $opt__ARCH in
                Sparc64) true ;;
                x86_64)  true ;;
                ppc64)   true ;;
                *) opt__ARCH=empty ;; # force error # TODO: emit error instead?
                # *) echo "{configuration error: This executable requires a 64 bit architecture}" 1>&2 && exit 1 ;;
            esac
        fi
    fi

    # Create a predefined 'core.bundlecfg_sh' for bootstrap
    # TODO: previously in "$builddir/bundlereg/core.bundlecfg_sh", is it OK?
    ## test -d "$1/bundlereg" || mkdir -p "$1/bundlereg"
    mkdir -p "$bld_cfgdir"
    update_file "$bld_cfgdir/core.bundlecfg_sh" <<EOF
core__USE_THREADS=$opt__USE_THREADS
core__AND_PARALLEL_EXECUTION=no
core__PAR_BACK=no
core__TABLED_EXECUTION=no
core__OPTIM_LEVEL="$opt__OPTIM_LEVEL"
core__DEBUG_LEVEL="$opt__DEBUG_LEVEL"
#
core__ARCH="$opt__ARCH"
core__OS="$opt__OS"
core__CUSTOM_CC="$opt__CUSTOM_CC"
core__CUSTOM_LD="$opt__CUSTOM_LD"
core__EXTRA_CFLAGS="$opt__EXTRA_CFLAGS"
core__EXTRA_LDFLAGS="$opt__EXTRA_LDFLAGS"
EOF

    # Create a predefined 'meta_sh'
    update_file "$bld_cfgdir/meta_sh" <<EOF
eng_name="$eng_name"
eng_h_alias="$eng_h_alias"
eng_srcpath="$eng_srcpath"
eng_use_stat_libs=no
eng_default_ciaoroot="$ciaoroot"
eng_addobj=
eng_addcfg=
eng_core_config="$bld_cfgdir/core.bundlecfg_sh"
EOF

    # Do sysdep configuration
    # (generate 'config_mk' and 'config_sh')
    "$sh_src_dir"/config-sysdep/config-sysdep.sh "$cardir" "$eng_cfg"
}

# ---------------------------------------------------------------------------

car_prebuild_boot_version_info() {
    set_car_vars "$1"; shift
    car_emit_version_info
}

car_emit_version_info() {
    local version
    local major=0
    local minor=0
    local patch=0
    if [ -r "$ciaoroot/core/Manifest/GlobalVersion" ] &&
           [ -r "$ciaoroot/core/Manifest/GlobalPatch" ]; then
        version=`cat "$ciaoroot/core/Manifest/GlobalVersion"`
        major="`echo "$version" | sed -e 's/\..*//'`" 
        minor="`echo "$version" | sed -e 's/[^\.]*\.//'`"
        patch=`cat "$ciaoroot/core/Manifest/GlobalPatch"`
    fi

    # Create version.h and version.c
    mkdir -p "$bld_hdir/ciao"
    update_file "$bld_hdir/ciao/version.h" <<EOF
#define CIAO_VERSION_STRING "Ciao $major.$minor.$patch"
#define CIAO_MAJOR_VERSION $major
#define CIAO_MINOR_VERSION $minor
#define CIAO_PATCH_NUMBER $patch
EOF
    mkdir -p "$bld_cdir"
    update_file "$bld_cdir/version.c" <<EOF
char *ciao_version = "$major.$minor";
char *ciao_patch = "$patch";
char *ciao_commit_branch = "unknown";
char *ciao_commit_id = "unknown";
char *ciao_commit_date = "unknown";
char *ciao_commit_desc = "unknown";
EOF
}

# ---------------------------------------------------------------------------
# Prepare and build the engine from .c sources:
#  - create installation-dependent eng_build_info.c file
#  - determine platform configuration (use preconfigured if exists in source)
#  - build executable, and static and shared libraries
#  - patch binaries (if needed)

car_build() { # cardir
    local eng_deplibs eng_addobj # TODO: eng_addobj is not local!
    set_car_vars "$1"
    ensure_config_loaded
    car_link_imports
    if [ x"$oc_car" = x"yes" ]; then # TODO: make it optional
        ENG_DYNLIB=0
        ENG_FIXSIZE=0
    fi
    #
    mkdir -p "$bld_objdir"
    # Generate version info # TODO: see eng_maker.pl
    if [ x"$oc_car" = x"yes" ]; then car_emit_version_info; fi
    # Generate build info
    car_emit_build_info
    # Generate engine configuration
    if [ x"$oc_car" = x"yes" ]; then car_emit_osarch_info_oc; else car_emit_osarch_info; fi
    # Build exec and lib
    eng_deplibs="$LIBS"
    if [ x"$eng_use_stat_libs" = x"yes" ]; then
        eng_deplibs="$eng_deplibs $STAT_LIBS"
    fi
    car_make engexec ENG_DEPLIBS="$eng_deplibs" ENG_ADDOBJ="$eng_addobj" # TODO: make it optional, depending on ENG_STUBMAIN (which is not visible here)
    if [ x"$ENG_DYNLIB" = x"1" ]; then
        car_make englib ENG_DEPLIBS="$eng_deplibs" ENG_ADDOBJ="$eng_addobj"
    fi
    # Patch exec
    if [ x"$ENG_FIXSIZE" = x"1" ]; then
        car_make fix_size_exec
        "$bld_objdir/fix_size""$EXECSUFFIX" "$bld_objdir/$eng_name""$EXECSUFFIX"
    fi
    if [ x"$oc_car" = x"yes" ]; then
        [ -x "$bld_objdir/$eng_name""$EXECSUFFIX" ] || { \
            echo "{Compilation of $cardir failed}" 1>&2; \
            exit 1; \
            }
        # TODO: see install_aux:eng_active_bld/1
        ( cd "$cardir"/objs ; rm -f "$eng_name""$EXECSUFFIX"; ln -s "$eng_cfg"/"$eng_name""$EXECSUFFIX" "$eng_name""$EXECSUFFIX" )
        car_header_oc # TODO: create a 'config' script for easy linking, or a car-config
    fi
}

# TODO:[optim_comp] merge
# TODO: ENG_CFG=DEFAULT hardwired
car_header_oc() {
    update_file "$cardir"/run <<EOF
#!/bin/sh
# Run executable (.car archive)

# Physical directory where the script is located
_base=\$(e=\$0;while test -L "\$e";do d=\$(dirname "\$e");e=\$(readlink "\$e");\\
        cd "\$d";done;cd "\$(dirname "\$e")";pwd -P)
# Make sure that CIAOROOT and CIAOCACHE are defined
r=\${CIAOROOT:-"$CIAOROOT"}
c="\$r/build/oc-cache"
c=\${CIAOCACHE:-\$c}
CIAOROOT="\$r" CIAOCACHE="\$c" CIAOCCONFIG=\${_base}/cfg/DEFAULT \${_base}/objs/$eng_name "\$@" -C \${_base}/noarch \${CIAORTOPTS}
EOF
    chmod a+x "$cardir"/run
}

# ---------------------------------------------------------------------------

# Generate the build info for the engine:
#   - versions, cc and ld options, OS suffixes, etc.
car_emit_build_info() {
    # Load configuration flags (e.g., core__DEBUG_LEVEL, etc.)
    . "$eng_core_config"

    if [ x"$oc_car" = x"yes" ]; then # TODO:[optim_comp] check
        CCSHARED="${CFLAGS} ${CCSHARED}"
    fi

    # eng_build_info.c: (in $bld_objdir since it depends on $eng_cfg)
    local ciaosuffix=
    case "$CIAOOS" in # (loaded from ensure_config_loaded)
        Win32) ciaosuffix=".cpx" ;;
    esac
    update_file "$bld_objdir/eng_build_info.c" <<EOF
char *eng_architecture = "$CIAOARCH";
char *eng_os = "$CIAOOS";
char *exec_suffix = "$EXECSUFFIX";
char *so_suffix = "$SOSUFFIX";

char *eng_debug_level = "$core__DEBUG_LEVEL";

int eng_is_sharedlib = $ENG_STUBMAIN_DYNAMIC;
char *ciao_suffix = "$ciaosuffix";

char *default_ciaoroot = "$eng_default_ciaoroot";
char *default_c_headers_dir = "$bld_hdir";

char *foreign_opts_cc = "$CC";
char *foreign_opts_ld = "$LD";
char *foreign_opts_ccshared = "$CCSHARED";
char *foreign_opts_ldshared = "$LDSHARED";
EOF
}

# Use an existing preconfiguration or run configure
car_emit_osarch_info() {
    local preconf=""
    local f src
    for src in $eng_srcpath; do
        f="$src/configure.$eng_cross_os$eng_cross_arch.h"
        if [ -r "$f" ]; then
            preconf="$f"
            break
        fi
    done
    # TODO: keep in $bld_objdir or $bld_cfgdir (since it depends on $eng_cfg)
    if [ x"$preconf" = x"" ]; then car_make configexec; fi
    if [ x"$preconf" != x"" ]; then
        dump_cflags; cat "$preconf"
    else
        dump_cflags; "$bld_objdir/configure""$EXECSUFFIX"
    fi | update_file "$bld_hdir/$eng_h_alias/configure.h"
}
# TODO: create together with config_sh instead
# TODO: goes to platform-independent directories! add osach as suffix and do conditional include?
dump_cflags() {
    local flag name
    for flag in $CFLAGS; do
        if ! expr x$flag : x'-D\(..*\)' >/dev/null; then
            continue
        fi
        name=`expr x$flag : x'-D\(..*\)'`
        cat <<EOF
#if !defined($name)
#define $name
#endif
EOF
    done
}

# TODO:[optim_comp] merge
car_emit_osarch_info_oc() {
    CONFIGURE_DIR="$ciaoroot/core/engine_oc"
    # Compile configure exec
    CONFIGURE="$bld_cfgdir/configure"
    ${CC} ${CFLAGS} ${LDFLAGS} -o ${CONFIGURE} \
          ${CONFIGURE_DIR}/configure.c \
          ${CONFIGURE_DIR}/engine__own_mmap.c
    mkdir -p "$bld_cfgdir"/engine
    update_file "$bld_cfgdir/engine/engine__configuration.h" <<EOF
#if !defined(__CONFIGURATION_H__)
#define __CONFIGURATION_H__
`emit_define "${opt__LOWRTCHECKS}" "USE_LOWRTCHECKS"`
`emit_define "${opt__USE_THREADS}" "USE_THREADS"`
`emit_define "${opt__DEBUG_TRACE}" "DEBUG_TRACE"`
`emit_define "${opt__PROFILE_INSFREQ}" "PROFILE_INSFREQ"`
`emit_define "${opt__PROFILE_INS2FREQ}" "PROFILE_INS2FREQ"`
`emit_define "${opt__PROFILE_BLOCKFREQ}" "PROFILE_BLOCKFREQ"`
`emit_define "${opt__PROFILE_STATS}" "PROFILE_STATS"`
`${CONFIGURE}`
#endif /* __CONFIGURATION_H__ */
EOF
    rm "${CONFIGURE}" # clean configure exec
}

emit_define() {
    if test x"$1" = x"yes"; then
        echo "#define $2 1"
    fi
}

# ---------------------------------------------------------------------------

# Invoke engine.mk
car_make() {
    local make="make -s"
    # Use gmake if available, otherwise expect make to be gmake
    if command -v gmake > /dev/null 2>&1; then make="gmake -s"; fi
    $make --no-print-directory -j$PROCESSORS \
          -C "$bld_objdir" \
          -f "$_base/engine.mk" \
          "$@" \
          BLD_CDIR="$bld_cdir" \
          BLD_OBJDIR="$bld_objdir" \
          ENG_NAME="$eng_name" \
          ENG_CFG_MK="$bld_cfgdir/config_mk"
}

# ---------------------------------------------------------------------------

# TODO: missing remove some autogenerated from cdir or objdir?
car_clean() { # cardir
    local f
    set_car_vars "$1"
    # TODO: clean with multiple eng_cfg?
    if [ -x "$bld_objdir" ]; then
        rm -f "$bld_objdir"/*
        rmdir "$bld_objdir"
    fi
    for f in "$cardir"/objs/*; do # TODO: it may leave other eng_cfg
        [ -d "$f" ] || rm -f "$f"
    done
    if [ -x "$bld_cfgdir" ]; then
        rm -f "$bld_cfgdir"/engine/* # TODO: store somewere else (engine__configuration.[ch])
        if [ -x "$bld_cfgdir"/engine ] ; then rmdir "$bld_cfgdir"/engine; fi
        rm -f "$bld_cfgdir"/*
        rmdir "$bld_cfgdir"
    fi
    # Clean all symlinks created by car_link_imports
    local f
    for f in "$bld_cdir"/*.[ch] "$bld_hdir"/*.[ch] "$bld_hdir/$eng_h_alias"/*.[ch]; do
        [ ! -L "$f" ] || rm "$f"
    done
}

car_clean_config() { # cardir
    set_car_vars "$1"
    rm -f "$bld_cfgdir/config_sh"
}

#     if [ -x "$cardir" -a '(' ! -x "$cardir/cfg" ')' ]; then
#         for i in "$cardir/*"; do
#             cat >&2 <<EOF
# INTERNAL ERROR: suspicuous cardir in build_car.sh:
# 
# The directory "$cardir" is not empty and does not look like a
# valid engine build directory. For safety, this script is aborted.
# 
# If correct, please clean manually the contents of the specified directory.
# EOF
#             exit 1
#         done
#     fi
#     rm -rf "$cardir"

# ---------------------------------------------------------------------------

# Select cardir (and auxiliary variables)
set_car_vars() { # cardir
    cardir="$1"
    if [ x"$cardir" = x"" ] || [ ! -x "$cardir" ] ; then
        cat >&2 <<EOF
INTERNAL ERROR: input is not a valid cardir: $cardir
EOF
        exit 1
    fi
    # Absolute path for cardir
    # TODO: required for some C flags; it may be a problem when executables are relocated
    cardir=$(e=$cardir/.;while test -L "$e";do d=$(dirname "$e");e=$(readlink "$e");\
        cd "$d";done;cd "$(dirname "$e")";pwd -P)

    if [ -r "$cardir"/native_modules ]; then
        oc_car=yes
    else
        oc_car=no
    fi

    if [ x"$oc_car" = x"yes" ]; then
        bld_hdir="$cardir/c"
        bld_cdir="$cardir/c/engine"
    else
        bld_hdir="$cardir/include"
        bld_cdir="$cardir/src"
    fi

    if [ x"$ENG_CFG" = x"" ]; then
        eng_cfg=DEFAULT # TODO: used in optim_comp, avoid it?
    else
        eng_cfg=$ENG_CFG
    fi
    bld_objdir="$cardir/objs/$eng_cfg"
    bld_cfgdir="$cardir/cfg/$eng_cfg"
}

# ---------------------------------------------------------------------------

case "$1" in
    clone_boot) shift; car_clone_boot "$@" ;;
    prebuild_boot_version_info) shift; car_prebuild_boot_version_info "$@" ;;
    build) shift; car_config "$@"; car_build "$1" ;;
    clean) shift; car_clean "$@" ;;
    clean_config) shift; car_clean_config "$@" ;;
    exists_exec) shift; car_exists_exec "$@" ;;
    run_exec_boot) shift; car_run_exec_boot "$@" ;;
    *)
        echo "Unknown target '$1' in build_car.sh" >&2
        exit 1
        ;;
esac


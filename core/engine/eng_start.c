/*
 *  eng_start.c
 *
 *  Load and execute a bytecode executable.
 *
 *  Copyright (C) 1996-2002 UPM-CLIP
 *  Copyright (C) 2020 The Ciao Development Team
 */

#if defined(_WIN32) || defined(_WIN64) /* MinGW */
//#include <winsock2.h>
#include <windows.h>
#endif

#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <ctype.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/param.h>

#include <ciao/eng.h>

#if !(defined(__svr4__) || defined(DARWIN) || defined(BSD))
#include <sys/types.h>
#include <malloc.h>
#endif
#include <assert.h>

#if defined(DARWIN) /* for get_execpath() */
#include <stdint.h>
#include <limits.h>
#include <mach-o/dyld.h>
#endif

#if defined(Win32) && !(defined(_WIN32) || defined(_WIN64)) /* MSYS2/Cygwin */
#include <sys/cygwin.h>
#endif

#include <ciao/basiccontrol.h>
#include <ciao/internals.h>
#include <ciao/system.h>
#include <ciao/eng_registry.h>
#include <ciao/eng_start.h>
#include <ciao/qread.h>
#include <ciao/eng_profile.h>
#include <ciao/timing.h>

#if !defined(MAXPATHLEN)
# define MAXPATHLEN 1024
#endif
#if !defined(X_OK)
# define X_OK 1
#endif

union dbl {
  flt64_t as_flt;
  uint32_t as_int[sizeof(flt64_t)/sizeof(uint32_t)];
};
static union dbl fzero = { .as_flt = 0.0 };

/* Check size of C types */
void checkctypes(void)
{
  /* tagged_t must be large enough to encode pointers */
  assert(sizeof(tagged_t) == sizeof(tagged_t *));
  /* checks for 64-bit floats */
  assert((sizeof(flt64_t) == 8));
  assert((fzero.as_int[0]==0 && fzero.as_int[1]==0));
}

/* local declarations */

#define USAGE_STRING "Usage: %s [prolog_args] -C [-i] [-q] [-v] -b bootfile\n"

char **prolog_argv;                                             /* Shared */
int prolog_argc;                                                /* Shared */

/* see prolog_current_executable() */
char source_path[MAXPATHLEN] = "";                             /* Shared */

bool_t interactive_flag_bool = FALSE;      /* Shared --- not really relevant? */

char *ciaoroot_directory = NULL;
char *c_headers_directory = NULL;

int eng_stub_length = 0; /* length of engine executable stub */
bool_t quiet_flag_bool;

CVOID__PROTO(load_ql_files, FILE *qfile)
{
  int more_ql;

  push_qlinfo(NULL);

  more_ql = qread1(w,qfile,&X(0));                  /* ignore version no. */
  w->global_top = NodeGlobalTop(w->node);           /* Reset heap pointer */
  
  while (more_ql) {
    while ((more_ql = qread1(w,qfile,&X(0))) && run_determ_c(w,X(0))) {
      w->global_top = NodeGlobalTop(w->node);
    }
  }
  
  pop_qlinfo(NULL);
}

static void open_exec_skip_stub(const char *file, FILE **stream) {
  if (eng_stub_length == 0) {
    goto usage;
  }

  if (!access(file, X_OK)) {
    struct stat data;
    stat(file,&data);
    if (data.st_size == eng_stub_length) goto usage;
    if ((*stream = fopen(file,"rb")) == NULL) {
      fprintf(stderr,"%s: unable to open for read\n", file);
      engine_exit(1);
    }
    fseek(*stream, eng_stub_length, SEEK_SET);
    return;
  }
  *stream = NULL;
  return;

 usage:
  fprintf(stderr, USAGE_STRING, file);
  engine_exit(1);
}

/* ------------------------------------------------------------------------- */
/* winsock2 initialization (only for MinGW) */
/* NOTE: This is required not only for sockets but also for gethostname() */

#if defined(_WIN32) || defined(_WIN64)
#warning "TODO(MinGW): move socket code back to the engine?"
void init_winsock2(void) {
  /* Initialize winsock2 */
  WSADATA wsaData;
  int iResult = WSAStartup(MAKEWORD(2,2), &wsaData);
  if (iResult != NO_ERROR) {
    fprintf(stderr, "Error at WSAStartup()\n");
    engine_exit(1);
  }
}
#endif

/* ------------------------------------------------------------------------- */

extern char cwd[];

extern char *ciao_suffix;

void ciao_initcode(void); /* initialize foreign interface definitions */

void eng_stub_set_length(int len) {
  eng_stub_length = len;
}

#if defined(Win32)
static void guess_win32_env(const char *boot_path,
                            const char *emulator);
#endif

/* Process engine options after "-C" argument */
void engine_set_opts(const char **optv, int optc, const char **boot_path) {
  int i;
  
  quiet_flag_bool = FALSE;

  for (i = 0; i < optc; i++) {
    if (strcmp(optv[i],"-b") == 0) /* TODO: optim_comp does not use -b */
      *boot_path = optv[++i];
    else if (strcmp(optv[i],"-i") == 0)
      interactive_flag_bool = TRUE;
    else if (strcmp(optv[i],"-q") == 0)             /* To make quiet */
      quiet_flag_bool = TRUE;
    else if (strcmp(optv[i],"-v") == 0)           /* To make verbose */
      quiet_flag_bool = FALSE;
    /*
      else if (strcmp(optv[i],"-L") == 0){    
      #if defined(Win32)
      ciaoroot_directory = checkalloc_ARRAY(char, MAXPATHLEN+1);
      expand_file_name(optv[++i],TRUE,ciaoroot_directory);
      #else
      ciaoroot_directory = optv[++i];
      #endif
      }
    */
    else
#if defined(PROFILE)
      if (strcmp(optv[i], "--profile") == 0)        /* Simple profile */
        profile_eng = TRUE;
      else if (strcmp(optv[i], "--profile-time") == 0)         /* Include time */
        profile_eng = TRUE;
    /* {profile_eng = TRUE; prof_include_time = TRUE;} */
      else
#endif
        if (strcmp(optv[i], "--trace-calls") == 0) /* Trace predicate calls */
          trace_calls = TRUE;
#if defined(DEBUG)
        else if (strcmp(optv[i], "--trace-instr") == 0) /* Trace instructions */
          trace_instr = TRUE;
        else if (strcmp(optv[i], "--debug-chpt") == 0)  /*debug regular choicepoints*/
          debug_choicepoints = TRUE;
        else if (strcmp(optv[i], "--debug-conc-chpt") == 0) /*conc. choicepoints*/
          debug_concchoicepoints = TRUE;
        else if (strcmp(optv[i], "--debug-threads") == 0)           /* debug threads */
          debug_threads = TRUE;
        else if (strcmp(optv[i], "--debug-gc") == 0)      /* debug garb. coll. */
          debug_gc = TRUE;
        else if (strcmp(optv[i], "--debug-mem") == 0)       /* debug mem. man. */
          debug_mem = TRUE;
        else if (strcmp(optv[i], "--debug-conc") == 0)    /* debug concurrency */
          debug_conc = TRUE;
        else if (strcmp(optv[i],"--debug-dynlink") == 0)
          debug_dynlink = TRUE;
#endif
        else if (strcmp(optv[i], "-C") != 0)  /* Ignore other "-C" */
          fprintf(stderr,"Warning: %s ignored\n",optv[i]);
  }
#if defined(PROFILE)
  if (profile||trace_calls) stop_on_pred_calls = TRUE;
#else
  if (trace_calls) stop_on_pred_calls = TRUE;
#endif
}

void set_ciaoroot_directory(const char *boot_path, const char *exec_path);

void engine_init(const char *boot_path, const char *exec_path) {
  checkctypes();

#if defined(_WIN32) || defined(_WIN64)
  /* Initializations for MinGW */
  init_winsock2();
#endif  

  init_alloc();

  tzset();                                       /* Initialize time zone information */
  init_locks();                                  /* global, first of all! */

  init_statistics();                             /* init the statistics related info */

#if defined(DEBUG)
  RESET_COUNTER;
#endif

  compute_cwd();

  set_ciaoroot_directory(boot_path, exec_path);
  
  /* Global initializations */
  /*init_wrb_state_list();*/
  init_goal_desc_list();
  init_once();
  init_some_bytecode();
  current_quiet_flag = quiet_flag_bool ? atom_on : atom_off;
  /*mem_prog_count = 0;*/

  ciao_initcode(); /* initialize foreign interface definitions */
  glb_init_each_time();
}

/* Get executable path (when argv[0] is not reliable) */
char *get_execpath(void) {
  char buffer[MAXPATHLEN+1];
  size_t size = MAXPATHLEN+1;
#if defined(LINUX)
  ssize_t len;
  if ((len = readlink("/proc/self/exe", buffer, size)) == -1) return NULL;
#elif defined(DARWIN)
  uint32_t len = size;
  if (_NSGetExecutablePath(buffer, &len) == -1) return NULL;
#elif defined(_WIN32) || defined(_WIN64) /* MinGW */
  if (GetModuleFileName(NULL, buffer, size) == 0) return NULL;
#else
  return NULL;
  /* TODO: Missing support for other OS:
      - Solaris: getexecname()
      - FreeBSD: sysctl CTL_KERN KERN_PROC KERN_PROC_PATHNAME -1
      - BSD with procfs: readlink /proc/curproc/file
  */
#endif
  return strdup(buffer);
}

int engine_start(int argc, char *argv[]) {
  int i;
  const char *boot_path = NULL;
  
  /* Split program options and engine options from engine arguments */
  int optc = 0;
  const char **optv = NULL;
  prolog_argc = argc;
  prolog_argv = argv;
  /* TODO: rewrite, user programs cannot use -C (JF) */
  for (i=1; i < argc; i++) { /* Detect the first "-C" */
    if (strcmp(argv[i], "-C") == 0) {
      /* set the number of program arguments */
      prolog_argc = i;
      /* skip "-C" */
      i++;
      /* engine options */
      optc = argc - i;
      optv = (const char **)&argv[i];
      break;
    }
  }

  /* Set the options */
  engine_set_opts(optv, optc, &boot_path);

  /* Locate full path of the engine executable */
  const char *exec_path = c_find_exec(argv[0]);
  if (exec_path == NULL) {
    exec_path = get_execpath(); /* Try the other method */
  }
  if (exec_path == NULL) {
    fprintf(stderr, "panic: could not find current executable path\n");
    return 1;
  }
  // fprintf(stderr, "[full emulator path: %s (argv[0]=%s)]\n", exec_path, argv[0]);
  /* TODO: test for standalone executables (-S)
       $ ciaoc -S hw
       $ ./hw
       $ ( P=`pwd`; cd /tmp; "$P"/hw )
       $ ( P=`pwd`; cd ..; "`basename "$P"`"/hw )
       $ ( export PATH=`pwd`:$PATH; cd ..; hw )
   */

  /* Initialize the engine */
  engine_init(boot_path, exec_path);

  /* Load boot */
  FILE *qfile = NULL;
  
  if (boot_path == NULL) {
    /* No source path -- try to open the executable itself and seek
       the file to skip the engine executable stub, where embedded
       bytecode should start */
    open_exec_skip_stub(exec_path, &qfile);
    if (qfile == NULL) { 
      fprintf(stderr,"%s: file not found\n", exec_path);
      return 1;
    }
    expand_file_name(exec_path,TRUE,source_path);
  } else {
    expand_file_name(boot_path,TRUE,source_path);
#if defined(Win32)
    i = strlen(source_path)-4;
    if (i > 0 && strcmp(source_path+i,".bat") == 0){
      int j;
      for (j = 1; ciao_suffix[j] && (i+j < MAXPATHLEN); j++) {
        source_path[i+j] = ciao_suffix[j];
      }
    } else if (i > 0 && strcmp(source_path+i, ciao_suffix) != 0) {
      strcat(source_path, ciao_suffix);
    }

    if (access(source_path,R_OK)) {
      source_path[strlen(source_path)-4] = '\0'; /* Take out ciao_suffix (.cpx) */
    }
#endif
    qfile = fopen(source_path,"rb");
    if (qfile == NULL) {
      fprintf(stderr, "%s: boot file not found\n", source_path);
      return 1;
    }
  }

  /* We have a bootfile we can read from */
  /* Make the first wam.  We need it to load the ql's. Main thread
     is always goal # 0 */
  goal_descriptor_t *first_goal;
  first_goal = init_first_gd_entry();
  load_ql_files(first_goal->worker_registers, qfile);
  fclose(qfile);
  /* wam->next_insn set to boot code in local_init_each_time */
  /*w->node->global_top = w->global_top;*/     /* Isn't this unnecessary? */
  /*  Fills in worker_entry */
  return call_firstgoal(first_goal, init_atom_check("internals:boot"));
}

// #define USE_WINDOWS_REGISTRY 1

/* Find out CIAOROOT directory */
void set_ciaoroot_directory(const char *boot_path, const char *exec_path) {
  /* Use CIAOROOT variable from the environment */
  ciaoroot_directory = getenv("CIAOROOT");
  if (ciaoroot_directory != NULL) {
#if defined(_WIN32) || defined(_WIN64)
#warning "TODO(MinGW): check that normalize path of ciaoroot_directory is ok"
    const char *aux = ciaoroot_directory;
    ciaoroot_directory = checkalloc_ARRAY(char, MAXPATHLEN+1);
    expand_file_name(aux,TRUE,ciaoroot_directory);
#endif
  } else if (ciaoroot_directory == NULL) {
#if defined(Win32) && defined(USE_WINDOWS_REGISTRY)
    if (using_windows()) { /* running in a Windows non-cygwin shell */
      /* Obtain ciaoroot_directory from the Windows registry */
      /* (for Windows executables) and
         set a couple more of variables */
      
      /* These are for the Windows registry */
      HKEY SOFTWAREKey, CiaoPrologKey;
      DWORD buffer_size = MAXPATHLEN;
      char aux[MAXPATHLEN+1];

      ciaoroot_directory = checkalloc_ARRAY(char, MAXPATHLEN+1);
     
      if (( RegOpenKeyEx(HKEY_LOCAL_MACHINE, TEXT("SOFTWARE"), 0, KEY_READ,
                         &SOFTWAREKey) == ERROR_SUCCESS ) &&
          ( RegOpenKeyEx(SOFTWAREKey, TEXT("Ciao Prolog"), 0, KEY_READ,
                         &CiaoPrologKey) == ERROR_SUCCESS ) &&
          ( RegQueryValueEx(CiaoPrologKey, TEXT("ciaoroot"), NULL, NULL,
                            (LPBYTE)aux, &buffer_size) == ERROR_SUCCESS )) {
#if defined(_WIN32) || defined(_WIN64)
#warning "TODO(MinGW): check that normalize path of ciaoroot_directory is ok"
        expand_file_name(aux,TRUE,ciaoroot_directory);
        // strncpy(ciaoroot_directory, aux, MAXPATHLEN);
#else
        cygwin_conv_to_full_posix_path(aux, ciaoroot_directory);
#endif
        RegCloseKey(SOFTWAREKey);
        RegCloseKey(CiaoPrologKey);
      } else if (boot_path != NULL) { // else open the emulator itself
        fprintf(stderr,
                "%s\n%s\n",
                "Registry key not found. Please remember to install Ciao Prolog",
                "or to set the CIAOROOT environment variable!");
        engine_exit(1);
      }

      /* TODO: Guess only in this case? (CIAOROOT not defined) */
      guess_win32_env(boot_path, exec_path);
    } else {
#endif
      /* Revert to installation-defined library directory otherwise */
#if defined(Win32)
      const char *aux = default_ciaoroot;
#if defined(_WIN32) || defined(_WIN64)
#warning "TODO(MinGW): check that normalize path of ciaoroot_directory is ok"
      expand_file_name(aux,TRUE,ciaoroot_directory);
#else
      cygwin_conv_to_full_posix_path(aux, ciaoroot_directory);
#endif
#else
      ciaoroot_directory = default_ciaoroot;
#endif
#if defined(Win32) && defined(USE_WINDOWS_REGISTRY)
    }
#endif
  }
  
  /* If there is a CIAOHDIR variable, we always use its value */
  c_headers_directory = getenv("CIAOHDIR");
  if (c_headers_directory != NULL) {
#if defined(_WIN32) || defined(_WIN64)
#warning "TODO(MinGW): check that normalize path of c_headers_directory is ok"
    const char *aux = c_headers_directory;
    c_headers_directory = checkalloc_ARRAY(char, MAXPATHLEN+1);
    expand_file_name(aux,TRUE,c_headers_directory);
#endif
  } else { /* c_headers_directory == NULL */
    c_headers_directory = default_c_headers_dir;
  }
}

#if defined(Win32)

#if defined(_WIN32) || defined(_WIN64) /* MinGW */
int setenv(const char *name, const char *value, int overwrite);
#endif

/* Guess values for PATH and SHELL environment variables on Win32
   (based on ciaoroot_directory and exec_path)

   We assume that ciaoengine.exe (if there is any), cygwin.dll, and
   sh.exe are in the same directory. The PATH should include the bin/
   directory under the Windows distribution. If not assigned by the
   user, we assign the SHELL variable to the sh.exe binary in that
   directoy.
 */
static void guess_win32_env(const char *boot_path,
                            const char *exec_path) {
  static const char *shexe = "/sh.exe";
  char path[MAXPATHLEN+1];

  /* Try guessing value for binary path */
  char *binpath = NULL;
  if (boot_path != NULL ||
      exec_path == NULL /* TODO: for ciao_prolog.c; try something better */
      ) {
    extern char *eng_os;
    extern char *eng_architecture;
    static const char *rel_builddir = "build";

    /* Construct the <builddir>/eng/<eng_name>/objs/<eng_cfg> directory */

    /* We need the library directory here.  It either points to an
       installation directory, and it is stored in the Windows registry, or
       exists because we got it from an environment variable, or we
       reverted to the "current directory", for "packed"
       distributions.  The last one not yet implemented. */

    /* Guess the directory where the engine lives */
    /* TODO: Use getplatformdeb */
    strcpy(path, ciaoroot_directory);
    strcat(path, rel_builddir);
    strcat(path, "/eng/"); 
    strcat(path, "ciaoengine");
    strcat(path, "/objs/"); 
    strcat(path, eng_os);
    strcat(path, eng_architecture);
    if (access(path, F_OK)) { 
      /* Does not exist --- look in the libdir itself */
      strcpy(path, ciaoroot_directory);
    }
    binpath = path;    
  } else if (exec_path != NULL) { /* open the emulator itself */
    // SHELL and PATH are relative to the emulator directory
    char *aux;
    expand_file_name(exec_path,TRUE,path); /* changes \ to / */
    aux = (char*)strrchr(path,'/');
    if (aux != NULL) {
      *aux = '\0';
      if (strchr(path,'/') != NULL) { /* TODO: allow? */
        binpath = path;
      }
    }
  }

  /* Found a candidate for binpath */
  if (binpath != NULL) {
    /* Add to PATH */
    char *envpath = getenv("PATH");
    if (envpath == NULL) envpath = "";
    char *new_envpath = c_paths_insert_new(envpath, binpath);
    if (new_envpath != NULL) { /* replace */
      setenv("PATH", new_envpath, 1);
      free(new_envpath);
    }
    
    if (!getenv("SHELL")) { /* Guess SHELL value */
      char *shell = (char*)malloc((strlen(path) + strlen(shexe) + 1) * sizeof(char));
      strcpy(shell, path);
      strcat(shell, shexe);
      setenv("SHELL", shell, 1);
      free(shell);
    }
  }
}
#endif

#if defined(PROFILE)
void end_profiler(void);
#endif

void engine_finish(void) {
#if defined(PROFILE)
  end_profiler();
#endif
  fflush(NULL);
}

void engine_exit(int result) {
  engine_finish();
  exit(result);
}

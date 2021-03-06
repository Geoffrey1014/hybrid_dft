open Cil

module E = Errormsg

let g_instrumentedFunctionList = ref ([]: string list)

(** 
	find all instrumented functions in the program under test
	instrumented functions : source code available 
	un-instrumented functions: system calls, library calls, and etc.
	TODO The user can specify some un-instrumented functions.
*)
let find_all_instruemented_funcs (f: file) = 
	E.log "==== Available Instrumented Functions ====\n";
	List.iter
		begin fun g ->
			match g with 
			| GFun (func, loc) -> (* all available function defs *)
				g_instrumentedFunctionList := !g_instrumentedFunctionList @ [func.svar.vname];
				E.log "%s\n" func.svar.vname
			| _ -> ()
		end
	  f.globals;
	E.log "===========\n"

let feature : featureDescr = 
  { fd_name = "fi";              
    fd_enabled = ref false;
    fd_description = "find function to instrument";
    fd_extraopt = [];
    fd_doit = 
    (function (f: file) -> 
      find_all_instruemented_funcs f);
    fd_post_check = true
  }

open Cil

module E = Errormsg
module UD = Usedef

(** 
	In this module, we extract variable information from the original code version.
	On the other hand, we convert the code into the simplified code by "--dosimplify".
	This simplification is mandated by the CAUT kernel.
	So we have to set up the variable mapping between the original code version and the simplified code version.
	The mapping is mainly achieved by line. Note it may be imprecise under some circumstances.

	We do not extract varibale information from the simplified code version because many temporary variables appear. It complicates the static analysis.
	In addition, after code simplification, we re-compute the control flow information.
	Because after the code is simplified, CIL statement ids, succs, preds have to be updated.
	The above steps are done in "cf.ml".

	From CIL documentation, "CFG.clearFileCFG" and "CFG.computeFileCFG" will not affact the variable information because they only update CFG-realted information.

*)



(************************************************)

(** Utility functions *)

(** find the first stmt of a specified function *)
let find_the_first_stmt_of_func (file: Cil.file) (func_name: string) =
	let func = FindCil.fundec_by_name file func_name in
	let the_first_stmt = List.hd func.sallstmts in
	let debug = true in
	if debug = false then begin (* debug *)
		E.log "func : %s \n" func_name;
		E.log "The first stmt: %a\n" d_stmt the_first_stmt
	end;
	the_first_stmt
;;

(** find the callee stmts of a specified function, return stmt list *)
let find_callee_stmts_of_func (file: Cil.file) (func_name:string) (callee_name: string) =
	let func = FindCil.fundec_by_name file func_name in
	let callee_flag = ref 0 in
	let callee_stmts = 
		List.filter
			begin fun st ->
				match st.skind with
				| Instr (instrl) ->
					List.iter
						begin fun ins ->
							match ins with
							| Call (lo, e, el, loc) ->
								if (MyCilUtility.getfunNameFromExp e) = callee_name then
									callee_flag := 1 (* find the callee instruction, set the flag *)
								else
									()
							| _ -> ()
						end
					  instrl;
					if !callee_flag = 1 then begin(* find the callee instruction *)
						callee_flag := 0;
						true
					end	else
						false
				| _ -> false
			end
		  func.sallstmts
	in
	let debug = true in (* debug *)
	if debug = false then begin
		E.log "find callee %s in caller %s\n" callee_name func_name;
		List.iter 
			begin fun st ->
				E.log "-- %a --" d_stmt st
			end
		  callee_stmts
	end;
	callee_stmts
;;

(** just a test function *)
let test_calculate_instruction_distance (file: Cil.file) = 
	let the_first_stmt_of_caller = find_the_first_stmt_of_func file "bar" in
	let the_callee_stmts = find_callee_stmts_of_func file "bar" !MyDfSetting.caut_def_use_fun_name in
	let caller_fn = FindCil.fundec_by_name file "bar" in
	(* let callee_fn = FindCil.fundec_by_name file "CAUT_DEF_USE" in *)
	let the_first_ins_of_caller = Instruction.of_stmt_first file caller_fn the_first_stmt_of_caller in
	List.iter
		begin fun st ->
			let callee_ins = Instruction.of_stmt_first file caller_fn st in
			let dist = DistanceToTargets.find the_first_ins_of_caller ~interprocedural:true [callee_ins]
				(* DistanceToReturn.find callee_ins *)
			in
			E.log "instruction: %a \n" d_stmt st;
			E.log "instruction dist = %d\n" dist
		end
	  the_callee_stmts
;;



(************************************************************)

(** This module is used to find var defs or var uses in a stmt in a function.
	We only consider use and def in a Instr stmt (i.e., CALL or SET)
	The info. will be used to judge an execution path has covered which vars
*)

(** variable definitions in a stmt in a func in the original code 
    We currently only identify the following var definitions:
    1. x=y/foo(...), x is a definition
    2. *p=y/foo(...), p is a "special" definiton
*)
type var_defs ={
	
	mutable var_defs_func_id: int; 
	mutable var_defs_func_name: string; (* the function where the def occurs *)
	mutable var_defs_var_name: string; (* the defined var's name *)
	mutable var_defs_var_id: int; (* the defined var's id *)
	mutable var_defs_var_stmt_id: int;
	mutable var_defs_line: int; (* the line where the def occurs *)
	(* Here we have an assumption, only one def occurs at one line.
		Because we use line as a mapping key between the original code and the simplified code *)
}

(** the global list to store var_defs *)
let my_var_defs_list = ref([]:var_defs list)

type var_uses={

	mutable var_uses_func_id: int;
	mutable var_uses_func_name: string; (* the function where the use occurs *)
	mutable var_uses_var_name: string; (* the use var's name *)
	mutable var_uses_var_id: int; (* the use var's id *)
	mutable var_uses_var_stmt_id: int;
	mutable var_uses_line: int; (* the line where the use occurs *)
}

(** the global list to store var_uses *)
let my_var_uses_list = ref([]:var_uses list)

let print_var_defs (var_defs_list : var_defs list) =
	E.log "\n==== Var Definitions ==== \n";
	List.iter
		begin fun d ->
			E.log "%s %s %d #%d\n" d.var_defs_func_name d.var_defs_var_name d.var_defs_var_id d.var_defs_line
		end
	 var_defs_list
;;

let print_var_uses (var_uses_list : var_uses list) =
	E.log "\n==== Var Uses ==== \n";
	List.iter
		begin fun d ->
			E.log "%s %s %d #%d\n" d.var_uses_func_name d.var_uses_var_name d.var_uses_var_id d.var_uses_line
		end
	 var_uses_list
;;


(** find var_defs and var_uses in a stmt in a func 
	TODO We only consider defs and uses in CALL and SET instrs
	Limitations:
		We only consider Set and Call statements.
*)
class myStmtUseDefInfoVisitor (func: Cil.fundec) = object(self)
	inherit nopCilVisitor

	(** is $lv a simple VAR of pointer type with NO_OFFSET ? *)
	method private isSimpleLvalOfPtr (lv: Cil.lval) : bool = 
		let lh, off = lv in
		match off with
		| Field _ -> false
		| Index _ -> false
		| NoOffset -> 
			(match lh with 
			| Var v -> 
				(match v.vtype with  (* must be a pointer *)
				| TPtr _ -> true
				| _ -> false)
			| Mem _ -> false)

	(** is $lv a Mem with simple lval ? *)
	method private is_mem_of_simple_lval (lv : Cil.lval) : bool = 
		let lh, off = lv in
		match lh with
		| Var _ -> false
		| Mem e ->
			match e with
			| Lval e_lv ->
				self#isSimpleLvalOfPtr e_lv
			| _ -> false

	(** get "p" from "*p" of the expr "*p = ..." *)
	method private get_special_def_var_from_lval (lv: Cil.lval) (line: int) (stmt_id: int) = 
		let lv_lh, lv_off = lv in
		(match lv_lh with
		| Var _ -> ()
		| Mem e -> 
			(match e with
			| Lval e_lv ->
				let e_lv_lh, e_lv_off = e_lv in
				(match e_lv_lh with
				| Var vi ->
					let def_var = { var_defs_func_id = func.svar.vid;
									var_defs_func_name=func.svar.vname; 
									var_defs_var_name=vi.vname; 
									var_defs_var_id=vi.vid; 
									var_defs_var_stmt_id = stmt_id;
									var_defs_line = line
								  } in
			my_var_defs_list := !my_var_defs_list @ [def_var] (* put it into the var defs list *)
				| _ -> ())
			| _ -> ())
		)


	method vstmt st = 
		match st.skind with
		| Instr (instrl) ->
			List.iter 
			  begin fun ins ->
				(match ins with
				| Set (_ , _, loc) | Call(_, _, _, loc) -> (* only consider Set and Call instrs *)

					(** NOTE you could not use UD.computeUseDefStmtKind *)
					let u, d = UD.computeUseDefInstr ins in (* compute var defs and uses *)
        			if not (UD.VS.is_empty d) then begin (* var defs *)
						let iterVars vi = 
			  				begin
			  					(* NOTE: skip definition from pointer assignment  *)
			  					if (Cil.isPointerType vi.vtype) = false then begin
									let def_var = { 
										var_defs_func_id = func.svar.vid;
										var_defs_func_name=func.svar.vname; 
										var_defs_var_name=vi.vname; 
										var_defs_var_id=vi.vid; 
										var_defs_var_stmt_id = st.sid;
										var_defs_line= loc.line} in
				 					my_var_defs_list := !my_var_defs_list @ [def_var] (* put it into the var defs list *)
			 					end
			  				end
						in
	         			UD.VS.iter iterVars d
					end;

					if not (UD.VS.is_empty u) then begin (* var uses *)
						let iterVars vi = 
		  					begin
							
								let use_var = { var_uses_func_id = func.svar.vid;
										var_uses_func_name=func.svar.vname;
										var_uses_var_name=vi.vname; 
										var_uses_var_id=vi.vid; 
										var_uses_var_stmt_id=st.sid;
										var_uses_line= loc.line} in
			 					my_var_uses_list := !my_var_uses_list @ [use_var] (* put it into the var uses list *)
						
		  					end
						in
						UD.VS.iter iterVars u
					end
				| _ -> ()
				);

				(** In Cil's usedef.ml, "p" is not treated as a definition in the"*p=x/fun()" form 
					Here, we regard "p" as a kind of special definition and find it out.
					Although the var "p" pointed to is the real definied variable.
				*)
				match ins with
					| Set(lv,_,loc) ->
						if (self#is_mem_of_simple_lval lv) = true then begin
							self#get_special_def_var_from_lval lv loc.line st.sid
						end
					| Call(lvo,_,_,loc) ->
						(match lvo with
						| Some(some_lvo) -> 
							if (self#is_mem_of_simple_lval some_lvo) = true then begin
								self#get_special_def_var_from_lval some_lvo loc.line st.sid
							end
						| None -> ())
					| _ -> ()
			  end
			 instrl;
			 DoChildren
		| If (e,_,_,loc) ->   (* consider var uses in if-stmt *)
			let u = UD.computeUseExp e in
			if not (UD.VS.is_empty u) then begin (* var uses *)
				let iterVars vi = 
  					begin
					
						let use_var = { var_uses_func_id = func.svar.vid;
								var_uses_func_name=func.svar.vname;
								var_uses_var_name=vi.vname; 
								var_uses_var_id=vi.vid; 
								var_uses_var_stmt_id=st.sid;
								var_uses_line= loc.line} in
	 					my_var_uses_list := !my_var_uses_list @ [use_var] (* put it into the var uses list *)
				
  					end
				in
				UD.VS.iter iterVars u
			end;
			DoChildren
		| _ -> DoChildren

end;;


(** transform var defs into their counterparts in the simplified code
	var id will not change, but after code simplification stmt id may change
	We need to update it.
*)
let transform_var_defs_into_simplified (file: Cil.file)  =

	let find_var_def_stmt func line = (* find the stmt where the var def occurs by line in func *)
		List.find
			begin fun st ->
				match st.skind with
				| Instr (instrl) ->
					List.exists (* does it exists ? *)
						begin fun ins ->
							match ins with
							| Set (_, _, loc) | Call(_, _, _, loc) ->
								if loc.line = line then
									true
								else
									false
							| _ -> false
						end
					  instrl
				| _ -> false
			end
		 func.sallstmts
	in
	List.iter
		begin fun def ->
			let func = FindCil.fundec_by_name file def.var_defs_func_name in
			let var_def_stmt = find_var_def_stmt func def.var_defs_line in
			def.var_defs_var_stmt_id <- var_def_stmt.sid
		end
	  !my_var_defs_list;
	print_var_defs !my_var_defs_list
;;


(** transform var uses into their counterparts in the simplified code
	var id will not change, but after code simplification stmt id may change
	We need to update it.
*)
let transform_var_uses_into_simplified (file: Cil.file) =

	let find_var_use_stmt func line = (* find the stmt where the var use occurs by line in func *)
		List.find
			begin fun st ->
				match st.skind with
				| Instr (instrl) ->
					List.exists (* does it exists ? *)
						begin fun ins ->
							match ins with
							| Set (_, _, loc) | Call(_, _, _, loc) ->
								if loc.line = line then
									true
								else
									false
							| _ -> false
						end
					  instrl
				| If (_,_,_,loc) ->
					if loc.line = line then
						true
					else
						false
				| _ -> false
			end
		 func.sallstmts
	in
	List.iter
		begin fun use ->
			let func = FindCil.fundec_by_name file use.var_uses_func_name in
			let var_use_stmt = find_var_use_stmt func use.var_uses_line in
			use.var_uses_var_stmt_id <- var_use_stmt.sid
		end
	  !my_var_uses_list;
	print_var_uses !my_var_uses_list
;;

(** dump var defs into a file *)
let dump_var_defs (filename: string) (mylist: var_defs list) =
	E.log "Dump Var defs, total %d entries.\n" (List.length mylist);
	let dump_channel = open_out filename in
    List.iter 
		begin fun def -> 
			output_string dump_channel (string_of_int def.var_defs_func_id);
			output_string dump_channel " ";
			output_string dump_channel (string_of_int def.var_defs_var_stmt_id);
			output_string dump_channel " ";
			output_string dump_channel (string_of_int def.var_defs_var_id);
			output_string dump_channel "\n";
			flush dump_channel
		end
	 mylist
;;

(** read var defs from a file*)
let read_var_defs (filename: string) =
    E.log "Read Var defs from the file: %s\n" filename;
    let var_defs_list = ref([]: var_defs list) in
    let lines = ref([]: string list) in
    let chan = open_in filename in
    ignore(begin
        try 
            while true; do
                let line = input_line chan in
                lines := !lines @ [line]
            done; !lines
        with End_of_file ->
            close_in chan;
            List.rev !lines
    end);
    List.iter
        begin fun line ->
            let string_list = Str.split (Str.regexp " ") line in
            let def_var = { var_defs_func_id = int_of_string (List.nth string_list 0);
                            var_defs_var_stmt_id = int_of_string (List.nth string_list 1);
                            var_defs_var_id = int_of_string (List.nth string_list 2);
                            var_defs_var_name = ""; (* do not care about these two fields *)
                            var_defs_func_name = "";
                            var_defs_line = 0;
                          } in
            var_defs_list := !var_defs_list @[def_var] 
            
        end
      !lines;
    !var_defs_list
;;
	
let transform_var_uses_and_defs_into_simplified (file: Cil.file) (to_transform: int) = 

	if to_transform = 1 then begin
		transform_var_defs_into_simplified file;
		transform_var_uses_into_simplified file
	end;
	E.log "debug: var defs cnt: %d\n" (List.length !my_var_defs_list);
	let dump_file_name = file.fileName ^ "." ^ !MyDfSetting.caut_var_defs_dump_file_name in
	dump_var_defs dump_file_name !my_var_defs_list
;;

(** find variable defs and uses *)
let find_var_defs_and_uses (file: Cil.file) = 
	List.iter
		begin fun g ->
			match g with
			| GFun(func, loc) ->	
				if func.svar.vname = !MyDfSetting.caut_def_use_fun_name 
					|| func.svar.vname = "testme" 
					|| func.svar.vname = !MyDfSetting.caut_df_context_fun_name then (* skip "CAUT_DEF_USE" and "testme" function *)
					() 
				else 
					ignore (Cil.visitCilFunction (new myStmtUseDefInfoVisitor func) func)
			| _ -> ()
		end
	  file.globals;
	print_var_defs !my_var_defs_list;
	print_var_uses !my_var_uses_list;
	E.log "defs list size = %d\n" (List.length !my_var_defs_list);
	E.log "uses list size = %d\n" (List.length !my_var_uses_list)
;;




(** def_use mark function's var name in the original code
	Because we fail to find var name after code simplification by "--dosimplify" 
*)
type def_use_mark_fun_var_name = {
	
	mark_fun_line_number: int; (* the line where the mark function locates *)
	mark_fun_var_name: string; (* the var name in the mark function *)
}

(** the global list to store var name in the mark function *)
let mark_fun_var_name_list = ref([]:def_use_mark_fun_var_name list)


let print_mark_fun_var_name_list (my_list: def_use_mark_fun_var_name list) =
	E.log "==== mark fun's arg var name ==== \n";
	List.iter
		begin fun var ->
			E.log "%s #%d\n" var.mark_fun_var_name var.mark_fun_line_number
		end
	  !mark_fun_var_name_list

class markfunVisitor = object(self)
	inherit nopCilVisitor

	method vstmt st = 
		match st.skind with
		| Instr (insl) ->
			List.iter
				begin fun ins ->
					match ins with
					| Call (lo, e, el, loc) ->
						let callee_name = MyCilUtility.getfunNameFromExp e in
						if callee_name = !MyDfSetting.caut_def_use_fun_name then begin (* find "CAUT_DEF_USE" mark function *)
							let var_name = (* get the var name from its first argument *)
								(match (List.hd el) with
								| CastE (_,ce) ->  (* (char* )var_name *)
									(match ce with
									| Const (c) ->
										(match c with
										| CStr (s) -> s
										| _  -> "" (* invalid return value *)
										)
									| _ -> ""
									)
								| _ -> ""
								)
							in
							let item = {mark_fun_line_number = loc.line; mark_fun_var_name=var_name} in
							mark_fun_var_name_list := !mark_fun_var_name_list @ [item]
						end
					 | _ -> ()
				end
			  insl;
			 DoChildren
		| _ -> DoChildren
end

(** find var name in the "use_def" mark function *)
let find_dua_var_name (file: Cil.file) = 
	List.iter
		begin fun g ->
			match g with
			| GFun (func, loc) ->
				if func.svar.vname = !MyDfSetting.caut_def_use_fun_name 
					|| func.svar.vname = "testme" 
					|| func.svar.vname = !MyDfSetting.caut_df_context_fun_name then (* skip "CAUT_DEF_USE" and "testme" function *)
					() 
				else begin
					ignore (Cil.visitCilFunction (new markfunVisitor) func)
				end
			| _ -> ()
		end
	  file.globals;
	print_mark_fun_var_name_list !mark_fun_var_name_list
;;


(*************************************************************)




(**************************************************************)

(** This module is used to analyze interprocedural var def/use with marked data flow context points 
*)



(** data flow context point *)
type df_context_point = {

	mutable df_context_point_file_name: string;
	mutable df_context_point_fun_name: string;
	mutable df_context_point_fun_id: int;
	mutable df_context_point_stmt_id: int;
	mutable df_context_point_line: int;
	mutable df_context_point_var_name: string;
	mutable df_context_point_var_id: int;
	mutable df_context_point_dua_index: int;
	mutable df_context_point_interp_point_type: int;
	mutable df_context_point_interp_point_index: int;
	mutable df_context_point_dua_use_index: int;
}

(** the global list to store data flow context point *)
let g_df_context_point_list = ref([]: df_context_point list)

let get_context_point_type_name (point_type: int) : string =
	match point_type with
	| 1 -> "DF_CALL"
	| 2 -> "DF_ENTRY"
	| 3	-> "DF_EXIT"
	| 4 -> "DF_RETURN"
	| _ -> "UNKNOWN"
;;

let print_df_context_point_list (my_list: df_context_point list) =
	E.log "file func fun_id stmt_id line var_name dua_index interp_point_type interp_point_index use_index\n";
	List.iter
		begin fun p ->
			E.log "%s %s %d %d %d %s %d %d %d %d %d\n" p.df_context_point_file_name p.df_context_point_fun_name p.df_context_point_fun_id p.df_context_point_stmt_id p.df_context_point_line p.df_context_point_var_name p.df_context_point_var_id p.df_context_point_dua_index  p.df_context_point_interp_point_type p.df_context_point_interp_point_index p.df_context_point_dua_use_index
		end
	  my_list

class dfContextPointVisitor (file: Cil.file) (func: Cil.fundec) = object(self)
	inherit nopCilVisitor

	(** get the constant value from exp *)
	method private getConstant (e:exp) = (* find index *)
		match e with
		| Const (c) -> 
			(match c with
			| CInt64 (i64, _,_ ) -> Cil.i64_to_int i64
			| _ -> 0 (* invalid return value *)
			)
		| _ -> 0

	method vstmt st = 
		match st.skind with
		| Instr (insl) ->
			List.iter
				begin fun ins ->
					(match ins with
					| Call (lo, e, el, loc) ->
						let callee_name = MyCilUtility.getfunNameFromExp e in
						if callee_name = !MyDfSetting.caut_df_context_fun_name then begin (* find "CAUT_DF_CONTEXT" mark function *)

							let var_name = (* get the var name from its first argument *)
									(match (List.hd el) with
									| CastE (_,ce) ->  (* "(char* )var_name" *)
										(match ce with
										| Const (c) ->
											(match c with
											| CStr (s) -> s
											| _  -> "" (* invalid return value *)
											)
										| _ -> ""
										)
									| _ -> ""
									)
							in
							
							let var_id = MyCilUtility.findVarIdfromVarName file func var_name 
							in
							
							let item={
								df_context_point_file_name=file.fileName; 
								df_context_point_fun_name=func.svar.vname; 
								df_context_point_fun_id=func.svar.vid; 
								df_context_point_stmt_id=st.sid; 
								df_context_point_line=loc.line;
								df_context_point_var_name = var_name;
								df_context_point_var_id = var_id;
								df_context_point_dua_index=(self#getConstant (List.nth el 1)); 
								df_context_point_interp_point_type=(self#getConstant (List.nth el 2)); 							        df_context_point_interp_point_index=(self#getConstant (List.nth el 3)); 
								df_context_point_dua_use_index=(self#getConstant (List.nth el 4))} 
							in
							
							g_df_context_point_list := !g_df_context_point_list @ [item]
							
						end else begin
					   		()
						end
					| _ -> ()
					)
				end
			  insl;
			 DoChildren
		| _ -> DoChildren

end

(** transform context points into their counterparts in the simplified code
	because after code simplification their stmt ids may change
	We need to update it.
*)
let transform_df_context_point_into_simplified (file: Cil.file) (to_transform: int) =

	let find_df_context_point_stmt func line = (* find the stmt where the context point locates by line in func *)
		List.find
			begin fun st ->
				match st.skind with
				| Instr (instrl) ->
					List.exists (* does it exists ? *)
						begin fun ins ->
							match ins with
							| Set (_, _, loc) | Call(_, _, _, loc) ->
								if loc.line = line then
									true
								else
									false
							| _ -> false
						end
					  instrl
				| _ -> false
			end
		 func.sallstmts
	in
	if to_transform = 1 then begin
		List.iter
			begin fun cp ->
				let func = FindCil.fundec_by_name file cp.df_context_point_fun_name in
				(* find cp's stmt id in the simplified code version *)
				let cp_stmt = find_df_context_point_stmt func cp.df_context_point_line in
				cp.df_context_point_stmt_id <- cp_stmt.sid
			end
		  !g_df_context_point_list
	end;
	E.log "\n==== df context points ==== \n";
	E.log "point nums: %d\n" (List.length !g_df_context_point_list);
	print_df_context_point_list !g_df_context_point_list
;;


let find_df_context_point (file: Cil.file) = 
	List.iter
		begin fun g ->
			match g with
			| GFun (func, loc) ->
				(* skip "CAUT_DEF_USE" and "testme" function *)
				if func.svar.vname = !MyDfSetting.caut_def_use_fun_name 
					|| func.svar.vname = !MyDfSetting.caut_df_context_fun_name 
					|| func.svar.vname = "testme" then 
					() 
				else begin
					ignore (Cil.visitCilFunction (new dfContextPointVisitor file func) func)
				end
			| _ -> ()
		end
	 file.globals;
	E.log "\n==== df context points ==== \n";
	E.log "point nums: %d\n" (List.length !g_df_context_point_list);
	print_df_context_point_list !g_df_context_point_list
;;

(**************************************************************)




(**************************************************************)

(** This module is used to construct def-use associations *)

type myDefOrUse = {

	mutable var_name: string;
	mutable var_id: int;
	mutable var_line: int;
	mutable file_name: string;
	mutable fun_name: string;
	mutable fun_id: int; (* function id *)
	mutable stmt_id: int; (* def id or use id *)
	mutable def_or_use: int; (* 1:def, 0:use *)
	mutable def_index: int; (* a dua's def index, only valid for DEF *)
	mutable use_index: int; (* a dua's use index, i.e., a dua's index in my framework, only valid for USE *)
	
}

(** the global list to store def or use *)
let g_dua_deforuse_list = ref([]: myDefOrUse list)

(** def use association *)
type myDua = {

	mutable dua_id: int;
	mutable dua_def: myDefOrUse; (* the def item in a dua *)
	mutable dua_def_crieds: MyCriticalEdge.criticalEdge list; (* critical edges for the def item *)
	mutable dua_use: myDefOrUse; (* the use item in a dua *)
	mutable dua_use_context_points: df_context_point list; (* sorted context points for the use item *)
	mutable dua_use_crieds: MyCriticalEdge.criticalEdge list; (* critical edges for the use item *)
	mutable dua_interp_or_intrap: int; (* 1: interp. dua 0: intrap. dua *)
	mutable dua_kind: int; (* 0: c-use, 1: p-use-true-branch 2: p-use-false-branch *)
}

(** the global list to store dua *)
let g_dua_list = ref([]: myDua list)

(************************************************************)

(** DEBUG or DUMP functions *)
let print_def_or_use (item: myDefOrUse) =
	E.log "%s %d %s %s #%d %d #%d %d %d %d\n" item.var_name item.var_id item.file_name item.fun_name item.fun_id item.stmt_id item.var_line item.def_or_use item.def_index item.use_index
;;

let print_deforuse_list (mylist: myDefOrUse list) = 
	E.log "==== DEF or USE ... ==== \n";
	let len = List.length mylist in
	for i=0 to len-1 do
		let item = List.nth mylist i in
		print_def_or_use item
	done
;;

let print_dua_list (mylist: myDua list) = 
	E.log "==== Dua ... ==== \n";
	let len = List.length mylist in
	for i=0 to len-1 do
		let item = List.nth mylist i in
		print_def_or_use item.dua_def;
		E.log " ->\n";		
		print_df_context_point_list item.dua_use_context_points;
		E.log "-->\n";
		print_def_or_use item.dua_use;
		if item.dua_interp_or_intrap = 1 then
			E.log "Interp.\n"
		else if item.dua_interp_or_intrap = 0 then
			E.log "Intrap.\n"
		else
			E.log "Unknown?\n"
	done
;;

(** output dua list to a file.
	Y var_id var_line file_name fun_name fun_id def_stmt_id cried(fun_id:b_id:b_choice;fun_id’:b_id’:b_choice’)
	Z var_id var_line file_name fun_name fun_id use_stmt_id cried(fun_id:b_id:b_choice;fun_id’:b_id’:b_choice’)
	Intrap./interp. (0/1)
*)
let dump_dua_list (filename: string) (mylist: myDua list) = 

	let c_use_dua = ref 0 in
	let p_use_dua = ref 0 in
    let dump_channel = open_out filename in
    List.iter 
		begin fun dua -> 
		
		  if dua.dua_kind = 0 then begin
		  	c_use_dua := !c_use_dua + 1
		  end else begin
		  	p_use_dua := !p_use_dua + 1
		  end;
		  
		  output_string dump_channel (string_of_int dua.dua_id); (* dua_id *) 
		  output_string dump_channel " "; 
		  if dua.dua_kind = 0 then begin
		  	output_string dump_channel "0" (* dua_kind *)
		  end else if dua.dua_kind = 1 then begin
		  	output_string dump_channel "1" (* dua_kind *) 
		  end else if dua.dua_kind = 2 then begin
		  	output_string dump_channel "2" (* dua_kind *) 
		  end;
		  output_string dump_channel " ";
		  output_string dump_channel dua.dua_def.var_name; (* var_name *)
		  output_string dump_channel " ";
		  output_string dump_channel (string_of_int dua.dua_def.var_id); (* var_id *)
		  output_string dump_channel " ";
		  output_string dump_channel (string_of_int dua.dua_def.var_line); (* var_line *)
		  output_string dump_channel " ";
		  output_string dump_channel dua.dua_def.file_name; (* file_name *)
		  output_string dump_channel " ";
		  output_string dump_channel dua.dua_def.fun_name; (* fun_name *)
		  output_string dump_channel " ";
		  output_string dump_channel (string_of_int dua.dua_def.fun_id); (* fun_id *)
		  output_string dump_channel " ";
		  output_string dump_channel (string_of_int dua.dua_def.stmt_id); (* stmt_id *)
		  output_string dump_channel " ";

		  (* print crieds for the def item *)
		  let crieds_cnt = List.length dua.dua_def_crieds in
		  if crieds_cnt = 0 then
			 output_string dump_channel "no"
		  else begin
			 for i=0 to crieds_cnt-1 do
			 let cried = List.nth dua.dua_def_crieds i in
				output_string dump_channel (string_of_int cried.MyCriticalEdge.funId);
				output_string dump_channel ":";
				output_string dump_channel (string_of_int cried.MyCriticalEdge.criStmtId);
				output_string dump_channel ":";
				output_string dump_channel (string_of_int cried.MyCriticalEdge.criStmtBranch);
				output_string dump_channel ":";
				output_string dump_channel (string_of_int cried.MyCriticalEdge.criLine);
			if i = crieds_cnt-1 then
			   output_string dump_channel "#"
			else
			   output_string dump_channel ";"
			 done
		  end;
		  
		  output_string dump_channel " ";
		  output_string dump_channel dua.dua_use.var_name; (* var_name *)
		  output_string dump_channel " ";
		  output_string dump_channel (string_of_int dua.dua_use.var_id); (* var_id *)
		  output_string dump_channel " ";
		  output_string dump_channel (string_of_int dua.dua_use.var_line); (* var_line *)
		  output_string dump_channel " ";
		  output_string dump_channel dua.dua_use.file_name; (* file_name *)
		  output_string dump_channel " ";
		  output_string dump_channel dua.dua_use.fun_name; (* fun_name *)
		  output_string dump_channel " ";
		  output_string dump_channel (string_of_int dua.dua_use.fun_id); (* fun_id *)
		  output_string dump_channel " ";
		  output_string dump_channel (string_of_int dua.dua_use.stmt_id); (* stmt_id *)
		  output_string dump_channel " ";

		  (* print crieds for the use item *)
		  let crieds_cnt = List.length dua.dua_use_crieds in
		  if crieds_cnt = 0 then
			 output_string dump_channel "no"
		  else begin
			 for i=0 to crieds_cnt-1 do
			 let cried = List.nth dua.dua_use_crieds i in
				output_string dump_channel (string_of_int cried.MyCriticalEdge.funId);
				output_string dump_channel ":";
				output_string dump_channel (string_of_int cried.MyCriticalEdge.criStmtId);
				output_string dump_channel ":";
				output_string dump_channel (string_of_int cried.MyCriticalEdge.criStmtBranch);
				output_string dump_channel ":";
				output_string dump_channel (string_of_int cried.MyCriticalEdge.criLine);
			if i = crieds_cnt-1 then
			   output_string dump_channel "#"
			else
			   output_string dump_channel ";"
			 done
		  end;

		  (* print interp. / intrap. dua *)
		  if dua.dua_interp_or_intrap = 1 then begin
			 output_string dump_channel " ";
			 output_string dump_channel (string_of_int 1)
		  end else begin
			 output_string dump_channel " ";
			 output_string dump_channel (string_of_int 0)
		  end;
			 

		  output_string dump_channel "\n";
		  flush dump_channel
       end
     !g_dua_list;
     E.log "c-use cnt: %d, p-use cnt: %d\n" !c_use_dua !p_use_dua
;;


let read_duas (filename: string) =

    E.log "Read Duas from the file: %s\n" filename;
    let duas_list = ref([]: myDua list) in
    let lines = ref([]: string list) in
    let chan = open_in filename in
    ignore(begin
        try
            while true; do
            let line = input_line chan in
            lines := !lines @ [line]
            done; !lines
        with End_of_file ->
            close_in chan;
            List.rev !lines
    end);
    List.iter
        begin fun line ->
            let string_list = Str.split (Str.regexp " ") line in
            let def = {
                    var_name = List.nth string_list 2; 
                    var_id = int_of_string(List.nth string_list 3);
                    var_line = int_of_string(List.nth string_list 4);
                    file_name = List.nth string_list 5;
                    fun_name = List.nth string_list 6;
                    fun_id = int_of_string(List.nth string_list 7);
                    stmt_id = int_of_string(List.nth string_list 8);
                    def_or_use = 0; (* we do not care these fields *)
                    def_index = 0;
                    use_index = 0;
                } in
            E.log "var id: %d\n" def.var_id;
            E.log "fun id: %d\n" def.fun_id;
            E.log "stmt id: %d\n" def.stmt_id;
            let use = {
                    var_name = List.nth string_list 10;
                    var_id = int_of_string(List.nth string_list 11);
                    var_line = int_of_string(List.nth string_list 12);
                    file_name = List.nth string_list 13;
                    fun_name = List.nth string_list 14;
                    fun_id = int_of_string(List.nth string_list 15);
                    stmt_id = int_of_string(List.nth string_list 16);
                    def_or_use = 0; (* we do not care these fields *)
                    def_index = 0;
                    use_index = 0;
                } in
            let dua = {
                    dua_id = int_of_string(List.nth string_list 0);
                    dua_kind = int_of_string(List.nth string_list 1);
                    dua_def = def;
                    dua_use = use;
                    dua_def_crieds = []; (* we do not care about this field *)
                    dua_use_crieds = []; 
                    dua_interp_or_intrap = 0;
                    dua_use_context_points = [];
                }
            in
            duas_list := !duas_list @ [dua]
        end
      !lines
    ;
    !duas_list

;;

(************************************************************)

(** count dua numbers
	One var use corresponds to one dua.
	Indicated by the $def_or_use(0) argument
*)
let count_dua (mylist: myDefOrUse list) =
	List.iter 
		begin fun i ->
			if i.def_or_use = 0 then 
				MyDfSetting.caut_dua_count := !MyDfSetting.caut_dua_count + 1
			else
				()
		end
	  mylist
;;

(** find the specified def item
	def_index: the def index
	We assume we could find it.
*)
let findDefItem (def_index: int) (mylist: myDefOrUse list) = 
	List.find
		begin fun item ->
			if item.def_index = def_index && item.def_or_use = 1 then
				true
			else
				false
		end
	  mylist
;;

(** find the specified use item
	use_index: the use item index
	We assume we could find it.
*)
let findUseItem (use_index:int) (mylist: myDefOrUse list) =
	List.find
		begin fun item ->
			if item.use_index = use_index && item.def_or_use = 0 then begin
				true
			end
			else
				false
		end
	  mylist
;;

(** find all context points for the specified use item 
	Note we sort the context points by their indexes
*)
let findContextPoints (use_index:int) (mylist: df_context_point list) = 
	let cps = List.filter (* find context points *)
		begin fun p ->
			if p.df_context_point_dua_use_index = use_index then begin
				true
			end
			else
				false	
		end
	  mylist
	in
	List.sort (* sort context points in a sequential manner *)
		begin fun p q ->
			if p.df_context_point_interp_point_index = q.df_context_point_interp_point_index then
				0
			else if p.df_context_point_interp_point_index < q.df_context_point_interp_point_index then
				-1
			else
				1
		end
	  cps (* return the sorted list *)
;;
		
(** construct DUA
	We need to construct a dua from:
	1. its var def and var use
	2. its df context points
*)
let construct_dua (mylist: myDefOrUse list) (context_points_list: df_context_point list) = 

	count_dua mylist; (* count dua numbers *)
	E.log "dua count = %d\n" !MyDfSetting.caut_dua_count;
	let dua_count = !MyDfSetting.caut_dua_count in
		
	for i=1 to dua_count do (* iterate on each use items *)
		let use_item = findUseItem i mylist in (* get the use item *)
		let def_item = findDefItem use_item.def_index mylist in (* get the corresponding def item by the def index *)
		let context_points = findContextPoints i context_points_list in (* find context points of the dua *)
		let is_intrap_dua = 
			if (List.length context_points) = 0 then
				0
			else
				1
		in
		(* create dua and put it into the list *)
		let dua = {dua_id= use_item.use_index; dua_def=def_item; dua_use=use_item; dua_use_context_points=context_points; dua_def_crieds=[]; dua_use_crieds=[]; dua_interp_or_intrap=is_intrap_dua; dua_kind=0} in
		g_dua_list := !g_dua_list @ [dua] 
	done
;;

(** 

find critical edges for the def item of a dua.

	In the following algorithm, we design a recursive function to compute crieds for a def item of a dua.

	step 0: Check whether the upper caller function (or the def item function) where the callee site (or the def item) locates is just the entry function.
			If it is the entry function, we compute crieds and stop.
			Otherwise, we goto step 1.

	step 1: find all upper callers (a level higher on the call chain) of the caller function.  
			we choose the upper caller with shortest distance from the entry function as the caller argument in the next iteration.
			find all callee sites in this upper caller function.
			we choose the callee site with the shortest distance from the entry of the upper caller as the callee argument in the next iteration. 
			compute the crieds of the original callee at the current function.

	step 2: continue step 1 until satisfying step 0

	TEST SECENARIOS: 
		mutilple caller (test ok), 
		a caller has multiple callees (test ok), 
		correct crieds sequences (multiple conditions) (test ok)
		
*)
let find_def_item_crieds (file: Cil.file) (def_item: myDefOrUse) = 
	
	let def_item_crieds = ref([]: MyCriticalEdge.criticalEdge list) in (* store crieds for the def item *)
	let entry_func = (* catch the exception when the user gives a wrong entry function name *)
		try
			FindCil.fundec_by_name file !MyDfSetting.caut_df_entry_fn (* the entry fn *)
		with Not_found -> 
			E.log "***Error***: the entry function name is not correct, please check it!\n";
			exit (1)

	in
	
	(* a recursive function 
		file: Cil.file
		caller_name: the caller name 
		callee_stmt_id: the callee stmt id
	*)
	let rec find_crieds_backward file caller_name callee_stmt_id = 
		if caller_name = !MyDfSetting.caut_df_entry_fn then begin (* we reach the entry fn *)
			E.log "\n--> find crieds for DEF:\n";
			let crieds = MyCriticalEdge.getCriticalEdges file caller_name callee_stmt_id in (* get its crieds directly *)
			def_item_crieds := crieds @ !def_item_crieds

		end else begin (* if we have not reached the entry fn *)
		
			let caller_func = FindCil.fundec_by_name file caller_name in
			let upper_callers = CilCallgraph.find_callers file caller_func in (* find all upper callers of the caller along the call chain *)

			let index = ref 0 in
			let shortest_distance = ref max_int in

			let upper_callers_cnt = List.length upper_callers in
			for i=0 to upper_callers_cnt-1 do
				let upper_fn = List.nth upper_callers i in (* choose one upper caller *)
				(* compute its function distance from the entry fn. *)
				let fn_dist = CilCallgraph.get_distance file entry_func upper_fn in
				if fn_dist < !shortest_distance then begin (* find the upper caller with the shortest distance from the entry fn *)
					index := i;
					shortest_distance := fn_dist
				end
			done;
	
			let target_upper_caller = List.nth upper_callers !index in (* get the target upper caller *)


			index := 0; (* init. *)
			shortest_distance := max_int; 

			(* find the first stmt of the upper caller *)
			let the_first_stmt_of_upper_caller = find_the_first_stmt_of_func file target_upper_caller.svar.vname in
			(* find the callee stmts in the upper caller *)
			let the_callee_stmts = find_callee_stmts_of_func file target_upper_caller.svar.vname caller_name in
			(* create the first instruction of the upper caller *)
			let the_first_ins_of_upper_caller = Instruction.of_stmt_first file target_upper_caller the_first_stmt_of_upper_caller in
			let the_callee_stmts_cnt = List.length the_callee_stmts in
			for i=0 to the_callee_stmts_cnt-1 do
				let st = List.nth the_callee_stmts i in
				(* create the instruction of the callee stmt *)
				let callee_ins = Instruction.of_stmt_first file target_upper_caller st in
				let ins_dist = DistanceToTargets.find the_first_ins_of_upper_caller ~interprocedural:true [callee_ins] in
				if ins_dist < !shortest_distance then begin
					index := i;
					shortest_distance := ins_dist
				end
			done;
		
			let target_callee_stmt = List.nth the_callee_stmts !index in (* get the target callee stmt in the upper caller *)
			E.log "\n--> find crieds for DEF:\n";
			let crieds = MyCriticalEdge.getCriticalEdges file caller_name callee_stmt_id in (* get its crieds for the callee in the current caller *)
			def_item_crieds := crieds @ !def_item_crieds;

			find_crieds_backward file target_upper_caller.svar.vname target_callee_stmt.sid (* recursive call *)
		end
		
	in
	
	find_crieds_backward file def_item.fun_name def_item.stmt_id; (* find crieds backward *)
	!def_item_crieds	(* return crieds for the def item *)

(** 

find critical edges for duas.

	For an intrap. dua, the crieds for its use item is just the crieds between its def and use item (they are in the same function).

	For an interp. dua, the crieds for its use item should be computed by connecting its use item's context points and find out crieds between these context points (they are in the different functions).

	We believe these context points could be recorded during the process of finding interprocedural def use chains by static incremental data flow analysis.
	So we assume these context points are available.

	For either an intrap. dua or an interp. dua, the crieds for its def item is obtained by following its call chain backward (although it may result in un-realizable paths).

*)
let find_dua_crieds (file: Cil.file) (mylist: myDua list) = 
	
	let updated_dua_list = ref([]: myDua list) in (* a new list to store updated duas *)
	let dua_cnt = List.length mylist in (* get the number of duas *)
	for i=0 to dua_cnt-1 do
		let dua = List.nth mylist i in
		if dua.dua_interp_or_intrap = 0 then begin (** an intrap. dua *)
			if dua.dua_def.fun_name = dua.dua_use.fun_name then begin
				E.log "\n[Process An Intrap. Dua (%d)...]\n" dua.dua_id;
				(* find crieds for the use item 
				   NOTE the sorted crieds between the def item and the use item are regared as the crieds 
				   for the use item.
				*)

                let crieds = MyCriticalEdge.diffCriticalEdges file dua.dua_def.fun_name dua.dua_def.stmt_id  dua.dua_use.stmt_id in 
                (* find more cut points for use *)
                (* let crieds = MyCriticalEdge.getCriticalEdges file dua.dua_def.fun_name dua.dua_use.stmt_id in *)

				(* debug output *)
				E.log "[MyUseDefAssicByHand] use crieds: \n";
				List.iter MyCriticalEdge.print_cried crieds;
				(* update the global dua list *)
				dua.dua_use_crieds <- dua.dua_use_crieds @ crieds;
				
				let def_crieds = find_def_item_crieds file dua.dua_def in (* find crieds for the def item *)
				(* debug output *)
				E.log "[MyUseDefAssicByHand] def crieds: \n";
				List.iter MyCriticalEdge.print_cried def_crieds;

				dua.dua_def_crieds <- dua.dua_def_crieds @ def_crieds;
				updated_dua_list := !updated_dua_list @ [dua];  (* put into the new dua list *)
				E.log "\n[Finish processing dua (%d).] \n" dua.dua_id
			end else begin
				ignore (E.log "**** Intrap. Dua: Function Name Not Same ?? ****\n");
				ignore (exit 2) (* terminate the process *)
			end
		end else if dua.dua_interp_or_intrap = 1 then begin (** an interp. dua *)
			E.log "\nProcess An Interp. Dua ...\n";
			let cps = dua.dua_use_context_points in (* get the dua's context points *)
			let cps_cnt = List.length cps in
			for i=0 to cps_cnt do (* sequentially visit dua's context points including the def and use item *)

				if i = 0 then begin (* DEF --> the first context point *)
					E.log " DEF --> first \n";
					let the_first_p = List.hd cps in
					if dua.dua_def.fun_name = the_first_p.df_context_point_fun_name then begin
						let crieds = MyCriticalEdge.diffCriticalEdges file dua.dua_def.fun_name dua.dua_def.stmt_id the_first_p.df_context_point_stmt_id in 
						(* debug output *)
						E.log "\n[find_dua_crieds]crieds:\n";
						List.iter MyCriticalEdge.print_cried crieds;
						(* update the global dua list *)
						dua.dua_use_crieds <- dua.dua_use_crieds @ crieds
					end
				end else if i = cps_cnt then begin  (* the last context point --> USE *)
					E.log " last --> USE \n";
					let the_last_p = List.nth cps (cps_cnt-1) in
					if dua.dua_use.fun_name = the_last_p.df_context_point_fun_name then begin
						let crieds = MyCriticalEdge.diffCriticalEdges file dua.dua_use.fun_name the_last_p.df_context_point_stmt_id dua.dua_use.stmt_id in 
						(* debug output *)
						E.log "\n[find_dua_crieds]crieds:\n";
						List.iter MyCriticalEdge.print_cried crieds;
						(* update the global dua list *)
						dua.dua_use_crieds <- dua.dua_use_crieds @ crieds
					end
				end else begin
					let the_former_p = List.nth cps (i-1) in (* the one context point --> the next context point *)
					let the_latter_p = List.nth cps i in
					E.log "%s --> %s \n" 
						(get_context_point_type_name the_former_p.df_context_point_interp_point_type)
						(get_context_point_type_name the_latter_p.df_context_point_interp_point_type);
					E.log "%s %s\n" 
						the_former_p.df_context_point_fun_name 
						the_latter_p.df_context_point_fun_name;
					if the_former_p.df_context_point_fun_name = the_latter_p.df_context_point_fun_name then begin
						let crieds = MyCriticalEdge.diffCriticalEdges file
 										the_former_p.df_context_point_fun_name
 										the_former_p.df_context_point_stmt_id
										the_latter_p.df_context_point_stmt_id 
						in 
						(* debug output *)
						E.log "\n[find_dua_crieds]crieds:\n";
						List.iter MyCriticalEdge.print_cried crieds;
						(* update the global dua list *)
						dua.dua_use_crieds <- dua.dua_use_crieds @ crieds
					end
				end
			done;
			(* debug output *)
			E.log "[find_dua_crieds]use crieds: \n";
			List.iter MyCriticalEdge.print_cried dua.dua_use_crieds;
			let def_crieds = find_def_item_crieds file dua.dua_def in (* find crieds for the def item *)
			(* debug output *)
			E.log "[find_dua_crieds]def crieds: \n";
			List.iter MyCriticalEdge.print_cried def_crieds;
			dua.dua_def_crieds <- dua.dua_def_crieds @ def_crieds;
			updated_dua_list := !updated_dua_list @ [dua]  (* put into the new dua list *)
		end else begin
			ignore (E.log "**** Unknown Dua Type ?? ****\n");
			ignore (exit 2) (* terminate the process *)
		end
	done;
	E.log "\n===END===\n";
	g_dua_list := []; (* clear the orignal dua list *)
	g_dua_list := !g_dua_list @ !updated_dua_list; (* reassign the original list *)
	updated_dua_list := [] (* clear the local new dua list *)
;;
	  
(** var defs and uses visitor *)
class defuseVisitor (file:Cil.file) (func: Cil.fundec) = object(self)
	inherit nopCilVisitor


	(** find the var id in a stmt in a function with var_name 
		1: def vars
		0: use vars
		TODO exeception handler
	*)
	method private find_var_id (func_id: int) (stmt_id: int) (var_name: string) (def_or_use: int) = 
		if def_or_use = 1 then begin
			let var_def = List.find
				begin fun var ->
					if var.var_defs_func_id = func_id && var.var_defs_var_stmt_id = stmt_id &&
						var.var_defs_var_name = var_name then
						true
					else
						false
				end
			 !my_var_defs_list
			in
			var_def.var_defs_var_id
		end else begin
			let var_use = List.find 
				begin fun var ->
					if var.var_uses_func_id = func_id && var.var_uses_var_stmt_id = stmt_id &&
						var.var_uses_var_name = var_name then
						true
					else
						false
				end
			 !my_var_uses_list
			in
			var_use.var_uses_var_id
		end

	(** get var name from mark function *)
	method private get_mark_fun_var_name (line: int) =
		let var = List.find
			begin fun var ->
				if var.mark_fun_line_number = line then
					true
				else
					false
			end
		 !mark_fun_var_name_list
		in
		var.mark_fun_var_name

	(** find var id *)
	method private findVar (var_name:string) (sid: int) (def_or_use: int) = 
		
		if def_or_use = 1 then (* find def vars, the mark function "CAUT_DEF_USE" is under the definition *)
			let var_id = self#find_var_id func.svar.vid (sid-1) var_name def_or_use in
			var_id
		else (* find use vars, the mark function "CAUT_DEF_USE" is above the definition *)
			let var_id = self#find_var_id func.svar.vid (sid+1) var_name def_or_use in 
			var_id
		
	(** find var index *)
	method private findIndex (e:exp) = (* find index *)
		match e with
		| Const (c) -> 
			(match c with
			| CInt64 (i64, _,_ ) -> Cil.i64_to_int i64
			| _ -> 0 (* invalid return value *)
			)
		| _ -> 0

	(** find def or use *)
	method private findDou (e:exp) = (* find def or use flag, 1 for def vars, 0 for use vars *)
		match e with
		| Const (c) -> 
			(
			match c with
			| CInt64 (i64, _,_ ) -> Cil.i64_to_int i64
			| _ -> -1 (* invalid return value *)
			)
		| _ -> -1

	(** find def or use *)
	method vstmt st = 
		match st.skind with
		| Instr (insl) ->
			List.iter
				begin fun ins ->
					(match ins with
					| Call (lo, e, el, loc) ->
						let callee_name = MyCilUtility.getfunNameFromExp e in
						if callee_name = !MyDfSetting.caut_def_use_fun_name then begin (* find "CAUT_DEF_USE" mark function *)
							let dou = self#findDou (List.nth el 2) in (* def vars or use vars *)
							let vname = self#get_mark_fun_var_name loc.line in
					   		let vid = self#findVar vname st.sid dou in
							let def_ind = self#findIndex (List.nth el 1) in (* def index *)
							let use_ind = self#findIndex (List.nth el 3) in (* use index *)
							if dou = 1 then
								(* Here, the var's def line is above the "CAUT_DEF_USE" and the var's use line is under the "CAUT_DEF_USE". We directly use the "CAUT_DEF_USE" statement's id as the sid of the def or use. It's O.K. because the "CAUT_DEF_USE" statement is in the same block with the def or use and it will not bring inconsistency. *)
								let item = {var_name = vname; var_id = vid; file_name = file.fileName; fun_name=func.svar.vname; fun_id=func.svar.vid; stmt_id = st.sid; var_line = loc.line-1; def_or_use = dou; def_index = def_ind; use_index=use_ind } in
							g_dua_deforuse_list := !g_dua_deforuse_list @ [item] (* put it into the list *)
							else
								let item = {var_name = vname; var_id = vid; file_name = file.fileName; fun_name=func.svar.vname; fun_id=func.svar.vid; stmt_id = st.sid; var_line = loc.line+1; def_or_use = dou; def_index = def_ind; use_index=use_ind } in
							g_dua_deforuse_list := !g_dua_deforuse_list @ [item] (* put it into the list *)
							
						end else begin
					   		()
						end
					| _ -> ()
					)
				end
			  insl;
			 DoChildren
		| _ -> DoChildren
		
end;;

(** find duas marked by hand *)
let find_dua_by_hand (file: Cil.file) =
	List.iter
		begin fun g ->
			match g with
			| GFun (func, loc) ->
				if func.svar.vname = !MyDfSetting.caut_def_use_fun_name 
					|| func.svar.vname = "testme" 
					|| func.svar.vname = !MyDfSetting.caut_df_context_fun_name then (* skip "CAUT_DEF_USE" and "testme" function *)
					() 
				else begin
					E.log "process %s ...\n" func.svar.vname;
					ignore (Cil.visitCilFunction (new defuseVisitor file func) func)
				end
			| _ -> ()
		end
	 file.globals;
	print_deforuse_list !g_dua_deforuse_list;
	construct_dua !g_dua_deforuse_list !g_df_context_point_list;
	print_dua_list !g_dua_list;
	find_dua_crieds file !g_dua_list;
;;



(** transform a dua's var def or use from the original code version to the simpified code version *)
let transform_dua_deforuse_to_simplified (file: Cil.file) (to_transform: int) = 

	let find_dua_deforuse_stmt func line = (* find the stmt where the var def or use locates at by line in func *)
		List.find
			begin fun st ->
				match st.skind with
				| Instr (instrl) ->
					List.exists (* does it exist ? *)
						begin fun ins ->
							match ins with
							| Set (_, _, loc) | Call(_, _, _, loc) -> (* SET/CALL instruction *)
								if loc.line = line then
									true
								else
									false
							| _ -> false
						end
					  instrl
				| If (_,_,_,loc) ->   (* a predicate use *)
					if loc.line = line then
						true
					else
						false
				| _ -> false
			end
		 func.sallstmts
	in
	if to_transform = 1 then begin
		List.iter
			begin fun item ->
				let func = FindCil.fundec_by_name file item.fun_name in
				let item_stmt = find_dua_deforuse_stmt func item.var_line in
				item.stmt_id <- item_stmt.sid
			end
		  !g_dua_deforuse_list
	end;
	print_deforuse_list !g_dua_deforuse_list
;;

(** transform duas from the original code version to the simpified code version
	The following information should be updated:
	1. df_context_points's stmt id
	2. var def or var use's stmt id
	3. critical edge's stmt id
*)
let transform_dua_to_simplified (file: Cil.file) (to_transform: int) =	
	if to_transform = 1 then begin
	List.iter
		begin fun dua ->
			let use_index = dua.dua_use.use_index in
			let dua_var_use = findUseItem use_index !g_dua_deforuse_list in
			dua.dua_use.stmt_id <- dua_var_use.stmt_id; (* update the var use's stmt id *)
			
			let dua_var_def = findDefItem dua_var_use.def_index !g_dua_deforuse_list in
			dua.dua_def.stmt_id <- dua_var_def.stmt_id; (* update the var def's stmt id *)
			E.log "[finish] update dua def/use (%d).\n" dua.dua_id;
			let context_points = findContextPoints use_index !g_df_context_point_list in
			List.iter2
				begin fun updated_cp orig_cp -> (* update df context point's stmt id *)
					orig_cp.df_context_point_stmt_id <- updated_cp.df_context_point_stmt_id  
				end
			  context_points dua.dua_use_context_points;
			E.log "[finish] update dua context points (%d).\n" dua.dua_id;
			let flip_branch_choice (orig_branch: int) = (* flip branch choice *)
				if orig_branch = 1 then
					0
				else
					1
			in
			  
			List.iter
				begin fun cried ->
					let updated_cried_sid = MyIfConditionMap.search_cried_stmt_id_after_simplified cried.MyCriticalEdge.funId cried.MyCriticalEdge.criLine cried.MyCriticalEdge.criStmtId in
					cried.MyCriticalEdge.criStmtId <- updated_cried_sid;
					(** NOTE: After code simplification, we will re-compute CFG info. As a reslut, the branch choice need to be flipped to its opposite *)
					cried.MyCriticalEdge.criStmtBranch <- flip_branch_choice cried.MyCriticalEdge.criStmtBranch
				end
			  dua.dua_def_crieds; (* update the crieds of the var def *)
			List.iter
				begin fun cried ->
					let updated_cried_sid = MyIfConditionMap.search_cried_stmt_id_after_simplified cried.MyCriticalEdge.funId cried.MyCriticalEdge.criLine cried.MyCriticalEdge.criStmtId in
					cried.MyCriticalEdge.criStmtId <- updated_cried_sid;
					(** NOTE: After code simplification, we will re-compute CFG info. As a reslut, the branch choice need to be flipped to its opposite *)
					cried.MyCriticalEdge.criStmtBranch <- flip_branch_choice cried.MyCriticalEdge.criStmtBranch
				end
			  dua.dua_use_crieds; (* update the crieds of the var use *)
		end
	  !g_dua_list
	end;
	let dump_file_name = file.fileName ^ "." ^ !MyDfSetting.caut_usedef_dump_file_name in
	dump_dua_list dump_file_name !g_dua_list
;;
(************************************************************)

let feature : featureDescr = 
  { fd_name = "dua";              
    fd_enabled = ref false;
    fd_description = "find dua by hand";
    fd_extraopt = [	
		];
    fd_doit = 
    (function (f: file) -> 
      find_dua_by_hand f);
    fd_post_check = true
  }

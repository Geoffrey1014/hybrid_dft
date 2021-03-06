open Cil
open MyCriticalEdge

module UD = Usedef
module E = Errormsg

(** the default filename to dump dua info. *)
let dua_file_name = ref "intrap-dua.txt"

(** use def association structure *)
type useDefAssoc = {
	mutable filName: string;
	mutable funName: string;
	mutable varId: int;
	mutable varName: string;
	mutable defStmtId: int;
	mutable defCriticalEdge: criticalEdge list;
	mutable useStmtId: int;
	mutable useCriticalEdge: criticalEdge list;
}

(** a list to store use def assoc *)
let useDefAssocList = ref ([]:useDefAssoc list)

(** a vid-varinfo hash table *)
let vidVarinfoHash = Hashtbl.create 0 


(** find a usedef assoc with filename, funcname, defOruseSid_list.
    defOrUse == true --> find by use stmt id
    defOrUse == false --> find by def stmt id
*)

(** find all intrap. duas with def/use stmt ids in a specified id list 
    @param defOruseSid_list only contains def stmt ids or use stmt ids
    @return useDefAssoc list
*)
let findIntrapUdas (filename: string) (funcname: string) (defOruseSid_list: int list) (defOruse: bool) : useDefAssoc list =
   
    let isIdInList (targ_id:int) (id_list: int list) = (* check whether the target id is in the id list *)
	List.exists
	   begin fun id ->
	     if targ_id == id then
		true
	     else
		false
	   end
	  id_list
    in
     
    (match defOruse with
    | true -> (* find by useSid *)
	List.filter  (* find all elements satisfying the criterion *)
	 begin fun uda ->
	  if uda.filName == filename && uda.funName == funcname && (isIdInList uda.useStmtId defOruseSid_list) then
	     true
	  else
	     false
	 end 
	!useDefAssocList
    | false -> (* find by defSid *)
	List.filter  (* find all elements satisfying the criterion *)
	 begin fun uda ->
           if uda.filName == filename && uda.funName == funcname && (isIdInList uda.defStmtId defOruseSid_list) then
	     true
	  else
	     false
         end
        !useDefAssocList);;

(** TODO to test findIntrapUdas *)
let do_test_findIntrapDuas () =
   List.iter 
     begin fun dua ->
	let dua_list = findIntrapUdas dua.filName dua.funName [dua.defStmtId] false in
	let def_dua = List.hd dua_list in
	(*if def_dua = [dua] then
	   E.log "test_findIntrapDuas --> PASS! \n"
	else
	   E.log "test_findIntrapDuas --> FAIL? \n"
        ;*)
	E.log "find dua by def --> \n";
	E.log "funname: %s, def: %d, use: %d \n" dua.funName dua.defStmtId dua.useStmtId;
	E.log "funname: %s, def: %d, use: %d \n" def_dua.funName def_dua.defStmtId def_dua.useStmtId;
        let use_list' = findIntrapUdas dua.filName dua.funName [dua.useStmtId] true in
	let use_dua = List.hd use_list' in
	(*if use_dua = [dua] then
	   E.log "test_findIntrapDuas --> PASS! \n"
	else
	   E.log "test_findIntrapDuas --> FAIL? \n"*)
 	E.log "find dua by use --> = \n";
	E.log "funname: %s, def: %d, use: %d \n" dua.funName dua.defStmtId dua.useStmtId;
	E.log "funname: %s, def: %d, use: %d \n" use_dua.funName use_dua.defStmtId use_dua.useStmtId
     end
    !useDefAssocList;;

(** print intraprocedural duas *)
let print_intrapDuas (intrapDuas: useDefAssoc list) = 
   List.iter 
	begin fun def_use_assoc -> 
          (* #file_name *)
          E.log "%s " def_use_assoc.filName;
		  (* #unit_name *)
		  E.log "%s " def_use_assoc.funName;
		  (* #var_id : global *)
		  E.log "%d " def_use_assoc.varId;
		  (* #var_name *)
		  E.log "%s " def_use_assoc.varName;

		  (* #def_stmt_id *)
		  E.log "%d " def_use_assoc.defStmtId;
	
		  (* #defCriticalEdge *)
		  let defCriedsListLen = List.length def_use_assoc.defCriticalEdge in
		  if defCriedsListLen == 0 then
			 E.log "%s" "no"
		  else begin
			 for i=0 to defCriedsListLen-1 do
			let cried = List.nth def_use_assoc.defCriticalEdge i in
			    E.log "%d" cried.criStmtId;
			E.log "%s" ":";
			E.log "%d" cried.criStmtBranch;
			if i == defCriedsListLen-1 then
			   E.log "%s" "#"
			else
			   E.log "%s" ";"
			 done
		  end;
		  
		  (* #use_stmt_id *)
		  E.log " %d " def_use_assoc.useStmtId;
		 	
		  (* #useCriticalEdge *)
		  let useCriedsListLen = List.length def_use_assoc.useCriticalEdge in
		  if useCriedsListLen == 0 then
			 E.log "%s" "no"
		  else begin
			 for i=0 to useCriedsListLen-1 do
			let cried = List.nth def_use_assoc.useCriticalEdge i in
			    E.log "%d" cried.criStmtId;
			E.log "%s" ":";
			E.log "%d" cried.criStmtBranch;
			if i == useCriedsListLen-1 then
			   E.log "%s" "#"
			else
			   E.log "%s" ";"
			 done
		  end;
	
		  E.log "%s" "\n"
       end
     intrapDuas		  

(** for DEGUB use *)
let print_vidmap vidmap = 
    (* su: count hash length *)
    E.log "Reachingdefs.IH length = %d\n" (Reachingdefs.IH.length vidmap);
    Reachingdefs.IH.iter 
        begin fun id set ->
            E.log ":varinfo: %s\n" (Hashtbl.find vidVarinfoHash id).vname;
	    	(* su: print the var id *)
	    	E.log ":varid: %d\n" id;
            Reachingdefs.IOS.iter (
                function
                    | Some defId -> 
						(* Note: DefId is the definition id, not the id of statement where the definition occurs *)
                        let _ = E.log "::DefId: %d, " defId in
						(* su: return the rhs for the definition *)
                        let _ = match Reachingdefs.getSimpRhs defId with
                            | Some (Reachingdefs.RDExp exp) -> E.log "exp: %a\n" d_exp exp
                            | Some (Reachingdefs.RDCall instr) -> E.log "call: %a\n" d_instr instr
                            | None -> E.log "StmtID: None\n"
                        in
                        ()
                    | None -> E.log "::DefId: None\n" 
            ) set
        end vidmap


(** output use def assoc list to a file
	Format:
	#file_name #unit_name #var_id #var_name #def_stmt_id #defCriticalEdge #use_stmt_id #useCriticalEdge
*)
let dump_use_def_assoc dump_channel def_use_assoc_list = 
    
    List.iter 
		begin fun def_use_assoc -> 
		  (* #file_name *)
		  output_string dump_channel def_use_assoc.filName;
		  output_string dump_channel " ";
		  (* #unit_name *)
		  output_string dump_channel def_use_assoc.funName;
		  output_string dump_channel " ";
		  (* #var_id : global *)
		  output_string dump_channel (string_of_int def_use_assoc.varId);
		  output_string dump_channel " ";
		  (* #var_name *)
		  output_string dump_channel def_use_assoc.varName;
		  output_string dump_channel " ";

		  (* #def_stmt_id *)
		  output_string dump_channel (string_of_int def_use_assoc.defStmtId);
		  output_string dump_channel " ";

		  (* #defCriticalEdge *)
		  let defCriedsListLen = List.length def_use_assoc.defCriticalEdge in
		  if defCriedsListLen == 0 then
			 output_string dump_channel "no"
		  else begin
			 for i=0 to defCriedsListLen-1 do
			let cried = List.nth def_use_assoc.defCriticalEdge i in
				output_string dump_channel (string_of_int cried.criStmtId);
			output_string dump_channel ":";
			output_string dump_channel (string_of_int cried.criStmtBranch);
			if i == defCriedsListLen-1 then
			   output_string dump_channel "#"
			else
			   output_string dump_channel ";"
			 done
		  end;
		  
		  (* #use_stmt_id *)
		  output_string dump_channel " ";
		  output_string dump_channel (string_of_int def_use_assoc.useStmtId);
		  output_string dump_channel " ";
		 	
		  (* #useCriticalEdge *)
		  let useCriedsListLen = List.length def_use_assoc.useCriticalEdge in
		  if useCriedsListLen == 0 then
			 output_string dump_channel "no"
		  else begin
			 for i=0 to useCriedsListLen-1 do
			let cried = List.nth def_use_assoc.useCriticalEdge i in
				output_string dump_channel (string_of_int cried.criStmtId);
			output_string dump_channel ":";
			output_string dump_channel (string_of_int cried.criStmtBranch);
			if i == useCriedsListLen-1 then
			   output_string dump_channel "#"
			else
			   output_string dump_channel ";"
			 done
		  end;

		  output_string dump_channel "\n"
       end
     def_use_assoc_list			  

(** compute use def association in a global style. *)
let compute_global_use_def_assoc instrUseVarSet (useStmt: Cil.stmt) (useStmtLine:int) vidmap (file: Cil.file) (func: Cil.fundec) (dua_kind: int) = 
	let debug = false in
	UD.VS.iter
	  (
	  begin fun use_vi ->
	     Reachingdefs.IH.iter 
	     begin fun id set ->
	       let vi = Hashtbl.find vidVarinfoHash id in
		   (* make sure use var's name is equal to def var's name *)
	       if vi.vname == use_vi.vname then
	       begin
	          Reachingdefs.IOS.iter (
		  function
		  | Some defId ->  
			
			(* get the stmt where the definition occurs *)
			(* Note: DefId is the definition id, not the id of statement where the definition occurs *)
			(
			match (Reachingdefs.getDefIdStmt defId) with
			| Some(defStmt) -> 
				if debug = true then begin
				  E.log "defId = %d, def_stmt_id = %d\n" defId defStmt.sid
				end;
    			
    			(* TODO fix the bug, when useStmt.sid == defStmt.sid, there still exsits possibility that dua exits , we have to check whether there exists redefinition behind the current use especially when the def and use are both in the same block *)
				if useStmt.sid != defStmt.sid then begin

				  if debug = true then begin
				    E.log "================\n";
				    E.log "USE = %s USE_ID = %d\n" use_vi.vname useStmt.sid;
				    E.log "DEF = %s DEF_ID = %d\n" vi.vname defStmt.sid;
				    E.log "================\n"
				  end;
				  
				  (* increment dua counter *)
				  MyDfSetting.caut_dua_count := !MyDfSetting.caut_dua_count + 1;
				  
				  (* pad the def item of a dua *)
				  let dua_def_item = {MyUseDefAssocByHand.var_name = vi.vname; 
				  					  MyUseDefAssocByHand.var_id = vi.vid; 
				  					  MyUseDefAssocByHand.file_name = file.fileName;
				  					  MyUseDefAssocByHand.fun_name=func.svar.vname;
				  					  MyUseDefAssocByHand.fun_id=func.svar.vid; 
				  					  MyUseDefAssocByHand.stmt_id = defStmt.sid; 
				  					  MyUseDefAssocByHand.var_line = MyCilUtility.getStmtLoc defStmt;  
				  					  MyUseDefAssocByHand.def_or_use = 1; 
				  					  MyUseDefAssocByHand.def_index = !MyDfSetting.caut_dua_count; 
				  					  MyUseDefAssocByHand.use_index= 0 } in
				   MyUseDefAssocByHand.g_dua_deforuse_list := !MyUseDefAssocByHand.g_dua_deforuse_list @ [dua_def_item]; (* put it into the list *)
				
				   (* pad the use item of a dua *)
				   let dua_use_item = {MyUseDefAssocByHand.var_name = use_vi.vname;
				   					   MyUseDefAssocByHand.var_id = use_vi.vid;
				   					   MyUseDefAssocByHand.file_name = file.fileName;
				   					   MyUseDefAssocByHand.fun_name=func.svar.vname;
				   					   MyUseDefAssocByHand.fun_id=func.svar.vid; 
				   					   MyUseDefAssocByHand.stmt_id = useStmt.sid;
				   					   MyUseDefAssocByHand.var_line = useStmtLine; 
				   					   MyUseDefAssocByHand.def_or_use = 0; 
				   					   MyUseDefAssocByHand.def_index = !MyDfSetting.caut_dua_count ; (* FIXED BUG, in the dua_use_item, $def_index should have the same value as $use_index *)
				   					   MyUseDefAssocByHand.use_index= !MyDfSetting.caut_dua_count } in
				   E.log "dua use item , var: %s, line: %d, sid: %d\n" use_vi.vname useStmtLine useStmt.sid;
				   MyUseDefAssocByHand.g_dua_deforuse_list := !MyUseDefAssocByHand.g_dua_deforuse_list @ [dua_use_item]; (* put it into the list *)
				  
				  (* pad the dua info. *)
				  let dua = {MyUseDefAssocByHand.dua_id= !MyDfSetting.caut_dua_count;
				  			 MyUseDefAssocByHand.dua_def=dua_def_item; 
				  			 MyUseDefAssocByHand.dua_use=dua_use_item; 
				  			 MyUseDefAssocByHand.dua_use_context_points=[]; 
				  			 MyUseDefAssocByHand.dua_def_crieds=[]; 
				  			 MyUseDefAssocByHand.dua_use_crieds=[]; 
				  			 MyUseDefAssocByHand.dua_interp_or_intrap=0;
				  			 MyUseDefAssocByHand.dua_kind = dua_kind
				  			 } in (* intrap. dua *)
				  MyUseDefAssocByHand.g_dua_list := !MyUseDefAssocByHand.g_dua_list @ [dua]
				  
				       
			   end
			| None -> ()
			)
	     | None -> 
			if debug = true then begin
			  E.log "::DefId: None\n"
			end;
			()
	        ) set
		end
	     end vidmap	
			
	   end)
	instrUseVarSet

(** compute critical edges for use/def statements 
    Global: useDefAssocList
    @obsolete
*)
(* let computeCriticalEdgesForUseDef (file: Cil.file) =
    let useDefAssocListLen = List.length !useDefAssocList in
      for i=0 to useDefAssocListLen-1 do
		let item = List.nth !useDefAssocList i in
		let def_crieds = MyCriticalEdge.getCriticalEdges file item.funName item.defStmtId in
		item.defCriticalEdge <- def_crieds;
	
		let use_crieds = MyCriticalEdge.getCriticalEdges file item.funName item.useStmtId in
		item.useCriticalEdge <- use_crieds
      done
*)

(** compute def use associations for all functions in a file *)
(* let do_compute_def_use_associations (file: Cil.file) (dumpFileName: string) =

    let debug = true in

    (* su: TODO check whether the file is opened successfully *)
    let dump_def_use_assoc_file = open_out dumpFileName in
    
    List.iter (* iterate on each function to compute RD *)
        begin function 
            | GFun(func,_) ->
				if debug == true then begin
				    E.log "--> Analyzing Function %s\n" func.svar.vname
				end;

				
                List.iter
                    begin fun stmt -> (* iterate on each statement *)
						if debug == true then begin (* print the stmt *)
                          E.log "----------------------------------------------------------\n";
                          E.log "Stmt %d: %a\n" stmt.sid d_stmt stmt;
                          E.log "**********************************************************\n";
                        end;
                        match Reachingdefs.getRDs stmt.sid with (* get RD. on a statement *)
                        | Some (_,_,vidmap as triple) -> 
			    			if debug == true then begin  (* print vidmap *)
                              print_vidmap vidmap
			    			end;

                            begin match stmt.skind with
                            | Instr instrs -> (* compute RD for instrs, "false" means returning the RD info. before reaching instrs *)
                                let triples = Reachingdefs.instrRDs instrs stmt.sid triple false in
                                List.iter2 (fun instr (_,_,vidmap) ->
  				   				 	if debug == true then begin (* print the instr *)
                                      E.log "Instr: %a\n" d_instr instr;
				      			      print_vidmap vidmap
				    				end;
				    				let instr_line = 
				    					(match instr with
				    					 | Set(_, _, loc) | Call(_, _, _, loc) -> loc.line
				    					 | _ -> -1 (* do not consider ASM *)
				    					)
				    				in
									(* compute the USE set of the instr *)
									let useVarSet, _ = UD.computeUseDefInstr instr in 
									(* compute global use def assoc on this instr *)
				                    compute_global_use_def_assoc useVarSet stmt instr_line vidmap file func 
				                    
                              	) instrs triples

			       
                            | _ -> ()
                            end

                        | None ->  (* no vidmap available *)
							if debug == true then begin
							  E.log ":(None)\n"
							end;
							()
                  end
               func.sallstmts
            | _ -> ()
        end file.globals;

     (* after compute use def assoc, we next compute critical edges for defs/uses*)
     (* computeCriticalEdgesForUseDef file; *)
     (* dump all use def assocs *)
     E.log "dua cnt: %d\n" (List.length !useDefAssocList);
     dump_use_def_assoc dump_def_use_assoc_file !useDefAssocList;
     close_out dump_def_use_assoc_file;; 
*)
     
(** This class identifies intra-procedural duas by RD *)
class intrapDefuseVisitor (file: Cil.file) (func: Cil.fundec) = object(self)
	inherit nopCilVisitor
	
	method vstmt st = 
		let debug = false in
		if debug = true then begin (* print the stmt *)
          E.log "----------------------------------------------------------\n";
          E.log "Stmt %d: %a\n" st.sid d_stmt st;
          E.log "**********************************************************\n";
        end;
        match Reachingdefs.getRDs st.sid with (* get RD. on a statement *)
        | Some (_,_,vidmap as triple) -> 
			if debug = true then begin  (* print vidmap *)
              print_vidmap vidmap
			end;

            (match st.skind with
            | Instr instrs -> (* compute RD for instrs, "false" means returning the RD info. before reaching instrs *)
                let triples = Reachingdefs.instrRDs instrs st.sid triple false in
                List.iter2 (fun instr (_,_,vidmap) ->
   				 	if debug = true then begin (* print the instr *)
                      E.log "Instr: %a\n" d_instr instr;
      			      print_vidmap vidmap
    				end;
    				let instr_line = 
    					(match instr with
    					 | Set(_, _, loc) | Call(_, _, _, loc) -> loc.line
    					 | _ -> -1 (* do not consider ASM *)
    					)
				    in
					(* compute the USE set of the instr *)
					let useVarSet, _ = UD.computeUseDefInstr instr in 
					(* compute global use def assoc on this instr *)
                    compute_global_use_def_assoc useVarSet st instr_line vidmap file func 0 (* c-use *)
                    
              	) instrs triples;
 				DoChildren
   
            | If (e, b1,b2, loc) -> 
            	(* predicate use *)
            	(* compute the USE set of the if exp *)
            	let useVarSet = UD.computeUseExp e in
            	(* compute global use def assoc on this instr *)
                compute_global_use_def_assoc useVarSet st loc.line vidmap file func 1; (* p-use-true-branch *)
                compute_global_use_def_assoc useVarSet st loc.line vidmap file func 2; (* p-use-false-branch *)
            	DoChildren
            | _ -> DoChildren
            )

        | None ->  (* no vidmap available *)
			if debug = true then begin
			  E.log ":(None)\n"
			end;
			DoChildren

end;;

(* 
	For p-use pairs, we need to add the if branch from itself to its critical edges.
	example:
		x = y; 
		if(x<2){...}
	we need to add if-{true-branch} to {x}-p-use pair's crieds.
*)
let add_cried_for_p_use_dua () =

	List.iter
		begin fun dua ->
			(* here, we give a special handle on p-use duas
				we treat the if-branch of p-use itself as its direct critical edge.
			*)
			if dua.MyUseDefAssocByHand.dua_kind=1 then begin (* p-use-true-branch *)
				let p_use_cried={
					MyCriticalEdge.funName = dua.MyUseDefAssocByHand.dua_use.MyUseDefAssocByHand.fun_name;
					MyCriticalEdge.funId = dua.MyUseDefAssocByHand.dua_use.MyUseDefAssocByHand.fun_id;
					MyCriticalEdge.criStmtId = dua.MyUseDefAssocByHand.dua_use.MyUseDefAssocByHand.stmt_id;
					MyCriticalEdge.criStmtBranch = 1;
					MyCriticalEdge.criLine = dua.MyUseDefAssocByHand.dua_use.MyUseDefAssocByHand.var_line;
				} in
				dua.MyUseDefAssocByHand.dua_use_crieds <- dua.MyUseDefAssocByHand.dua_use_crieds @ [p_use_cried]
			end else if dua.MyUseDefAssocByHand.dua_kind=2 then begin (* p-use-false-branch *)
				let p_use_cried={
					MyCriticalEdge.funName = dua.MyUseDefAssocByHand.dua_use.MyUseDefAssocByHand.fun_name;
					MyCriticalEdge.funId = dua.MyUseDefAssocByHand.dua_use.MyUseDefAssocByHand.fun_id;
					MyCriticalEdge.criStmtId = dua.MyUseDefAssocByHand.dua_use.MyUseDefAssocByHand.stmt_id;
					MyCriticalEdge.criStmtBranch = 0;
					MyCriticalEdge.criLine = dua.MyUseDefAssocByHand.dua_use.MyUseDefAssocByHand.var_line;
				} in
				dua.MyUseDefAssocByHand.dua_use_crieds <- dua.MyUseDefAssocByHand.dua_use_crieds @ [p_use_cried]
			end
			
		end
	  !MyUseDefAssocByHand.g_dua_list
;;

(** find intrap duas automatically, rely on the RD computation module in CIL *)
let find_intrap_dua_by_RD (file: Cil.file) = 
	let debug = false in
	if debug = true then begin
    	E.log "\n\n=======[MyUseDefAssoc.ml]Compute Def Use Associations========\n"
    end;
    
    (* su: collect all var declaration including GVar, GVarDecl, GVarFun, varinfo(formals/locals) *)
    Cil.visitCilFileSameGlobals begin object
        inherit Cil.nopCilVisitor
        method vvdec varinfo =
	    (* su: add var_id/var_info to hash table *)
            Hashtbl.add vidVarinfoHash varinfo.vid varinfo;
	
			if debug = true then begin
			  (* su: print var name *)
			  E.log "var name: %s\n" varinfo.vname
			end;
            Cil.SkipChildren
    end end file;
    
    List.iter (* iterate on each function *)
		begin fun g ->
			match g with
			| GFun (func, loc) ->
				if func.svar.vname = !MyDfSetting.caut_def_use_fun_name 
					|| func.svar.vname = "testme" 
					|| func.svar.vname = !MyDfSetting.caut_df_context_fun_name then (* skip "CAUT_DEF_USE" and "testme" function *)
					() 
				else begin
					if debug = true then begin
						E.log "Run Cil's Reaching Definitions on Func <%s>\n" func.svar.vname
					end;
					(* su: compute reaching definition on func *)
                	Reachingdefs.computeRDs func;
					ignore (Cil.visitCilFunction (new intrapDefuseVisitor file func) func)
				end
			| _ -> ()
		end
	 file.globals;
	E.log "total dua cnt:%d\n" (List.length !MyUseDefAssocByHand.g_dua_list);
	MyUseDefAssocByHand.find_dua_crieds file !MyUseDefAssocByHand.g_dua_list;
	(* add a cried for p-use duas *)
   	add_cried_for_p_use_dua ()
;;

(** Example:
	foo(&x);
	x is primitive type
*)
type funcall_by_ref={

	mutable funcall_by_ref_filename: string;
	mutable funcall_by_ref_funcid: int;
	mutable funcall_by_ref_funcname: string;
	mutable funcall_by_ref_stmt_id: int;
	mutable funcall_by_ref_line: int;
	mutable funcall_by_ref_arg_pos: int list; (* start from zero *)
	mutable funcall_by_ref_arg_var: Cil.varinfo list; (* correspond to $funcall_by_ref_arg_pos *)
}

(** the global list to store funcall by ref *)
let g_funcall_by_ref = ref([]: funcall_by_ref list)

(** search all funcalls by ref *)

(** iterate on each funcall by ref in the $g_funcall_by_ref 
    use RD module
*)


let feature : featureDescr = 
  { fd_name = "intrapdua";              
    fd_enabled = ref false;
    fd_description = "find intraprocedural duas";
    fd_extraopt = [
			("--intrapduafile", Arg.Set_string dua_file_name, " set the file name to dump dua info");
			  ];
    fd_doit = 
    (function (f: file) -> 
      find_intrap_dua_by_RD f );
    fd_post_check = true
  }
    

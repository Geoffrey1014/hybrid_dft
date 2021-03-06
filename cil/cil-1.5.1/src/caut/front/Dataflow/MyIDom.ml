open Cil

module E = Errormsg
module IDom = Dominators

(**
	This module is used to find intermediate dominator of a target statement.
	CIL could give "strictly" intermediate dominator.
*)

class myIDomOfStmtVisitor (h: Cil.stmt option Inthash.t) = object(self)
	inherit Cil.nopCilVisitor
	
	method vstmt (st: Cil.stmt) =
		E.log "stmt: %a\n" d_stmt st; 
		let r = IDom.getIdom h st in
		(match r with
		| None -> E.log "--> no idom\n\n"
		| Some (idom_st) -> E.log "\nits idom: %a\n\n" d_stmt idom_st
		);
		DoChildren
		

end

let find_idom (file: Cil.file) = 
	List.iter
		begin fun g ->
			match g with
			| GFun(func, loc) ->	
				E.log "func :%s \n" func.svar.vname;
				let h = IDom.computeIDom func in
				ignore (Cil.visitCilFunction (new myIDomOfStmtVisitor h) func)
			| _ -> ()
		end
	  file.globals;
	 ()
	
	
let feature : featureDescr = 
  { fd_name = "idom";              
    fd_enabled = ref false;
    fd_description = "find immediate dominator";
    fd_extraopt = [	
		];
    fd_doit = 
    (function (f: file) -> 
     find_idom f);
    fd_post_check = true
  }

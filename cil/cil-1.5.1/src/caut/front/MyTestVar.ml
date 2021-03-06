open Cil


let do_test_var_id (file: Cil.file) = 
	List.iter
		begin fun g ->
			match g with
			| GFun (func, loc) ->
				
			| _ -> ()
		end
	 g.globals
	 
	 
type myEdge = {

	mutable funName: string;
	mutable funId: int;
	mutable criStmtId: int; (* <funId, criStmtId> is the KEY *)
	mutable criStmtBranch: int;
	mutable criLine : int;
}
	 
module My_Set = Set.Make(
	struct 
		type t = myEdge
		let compare x y = 
			(* we only concern equality *)
			if (x.funId = y.funId) && (x.criStmtId = y.criStmtId) && (x.criStmtBranch = y.criStmtBranch) then
				0
			else 
			    -1
	end
)


let feature : featureDescr = 
  { fd_name = "testvar";              
    fd_enabled = ref false;
    fd_description = "test var id";
    fd_extraopt = [	
		];
    fd_doit = 
    (function (f: file) -> 
      do_test_var_id f);
    fd_post_check = true
  }

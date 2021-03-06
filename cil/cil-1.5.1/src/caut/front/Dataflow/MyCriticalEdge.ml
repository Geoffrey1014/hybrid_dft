open Cil

module E = Errormsg
module IDom = Dominators

(** critical edge structure, represented as <if_stmt_id, branch_choice> *)
type criticalEdge = {

	mutable funName: string;
	mutable funId: int;
	mutable criStmtId: int; (* <funId, criStmtId> is the KEY *)
	mutable criStmtBranch: int;
	mutable criLine : int;
}

(** the global list to store the critical edges of a stmt *)
let criticalEdgeList = ref([]: criticalEdge list)

module Crieds_Set = Set.Make(
	struct 
		type t = criticalEdge
		let compare x y = 
			(* we only concern equality *)
			if (x.funId = y.funId) && (x.criStmtId = y.criStmtId) && (x.criStmtBranch = y.criStmtBranch) then
				0
			else 
			    -1
	end
)

let print_cried (cried: criticalEdge) =
	E.log "%s #%d %d %d #%d\n" cried.funName cried.funId cried.criStmtId cried.criStmtBranch cried.criLine
;;

(** Get the branch choice.
   Assume @pred is a if stmt and has two succs,
   0 : false branch
   1 : true branch
*)
let getBranchChoice pred stmt = 
	if (List.nth pred.succs 0).sid == stmt.sid then
		1
	else
		0

(** Find the nearest "critical edge" of the @tarStmt 
	Return (stmt.sid, stmt.branch, stmt.line ) 
*)
let rec findNearestCriticalEdge (tarStmt: Cil.stmt) = 
  (* E.log "stmt id = %d, preds count = %d\n" tarStmt.sid (List.length tarStmt.preds); *)
  match tarStmt.preds with
  | [ pred ] -> (* has one pred *)
	if List.length (pred.succs) > 1 then 
		Some( pred.sid, (getBranchChoice pred tarStmt), (MyCilUtility.getStmtLoc pred) )
	else
		findNearestCriticalEdge pred
  | _ -> None (* has no pred or more than one pred *)


(*************************ABANDON************************************)
(** 
	This algorithm is not correct.
	We find it may miss some critical edges.
	Abandon it!
*)

(** Algorithm Find Critical Edges 
   Assume the CFG info has been computed.
   1. intraprocedural
   2. start from the target statement, and tranverse its immediate/intermmediate predecessors 
      in a bfs style. And we tag each visited statements. If encounter a previous visited predecessor (in the presence of loops), we skip it.
   3. tranverse all If statements, if one of its successors is not tagged, then the other side's edge must be a critical edge.
*)

(** record all visited predecessor statements when finding critical edges for a specified statement *)
let visitedPredStmtIdList = ref ([]:int list)
(** store all critical edges for a specified statement *)
let allCriEdgesList = ref([]: criticalEdge list)


(** find @tarStmt's all critical edges in the @func 
    <obsolete>
*)
let getAllIntrapCriticalEdges_2 (func: Cil.fundec) (tarStmt: Cil.stmt) = 
   (* put the target stmt id into the visited list *)
   visitedPredStmtIdList := !visitedPredStmtIdList @ [tarStmt.sid];
   (* put the target stmt into the stmt queue *)
   let stmtQueue = Queue.create () in
   Queue.add tarStmt stmtQueue;
   (
   while not (Queue.is_empty stmtQueue) do
      (* take the head stmt *)
      let sm = Queue.take stmtQueue in
      let smPredCount = List.length sm.preds in
      (* traverse its preds *)
      for i=0 to smPredCount-1 do
		let smPred = List.nth sm.preds i in
		if MyCilUtility.isIdInList smPred.sid !visitedPredStmtIdList then
		   () (* exists, skip it *)
		else begin
		   (* otherwise, keep it *)
		   Queue.add smPred stmtQueue;
		   visitedPredStmtIdList := !visitedPredStmtIdList @ [smPred.sid]
		end
      done
   done
   );
   List.iter
     begin fun stmt ->
       match stmt.skind with
       | If(_,_,_,loc) -> (* traverse all If stmts *)
			(*CAUTION : succs[0] --> true branch, succs[1] --> false branch, but under --domakeCFG, it was reversed*) 
		  let succ1 = List.nth stmt.succs 1 in (* the false branch *)
		  let succ2 = List.nth stmt.succs 0 in (* the true branch *)
		      (* If and only if there is one succ is not visited, then the other covered edge is a critical edge *)
		  if (MyCilUtility.isIdInList succ1.sid !visitedPredStmtIdList) == true && (MyCilUtility.isIdInList succ2.sid !visitedPredStmtIdList) == false then
			 begin
			let cried = {funName = func.svar.vname; funId=func.svar.vid; criStmtId = stmt.sid; criStmtBranch = 1; criLine = loc.line } in
			allCriEdgesList := !allCriEdgesList @ [cried]
			 end;
		  if (MyCilUtility.isIdInList succ1.sid !visitedPredStmtIdList) == false && (MyCilUtility.isIdInList succ2.sid !visitedPredStmtIdList) == true  then
			 begin
			let cried = {funName = func.svar.vname; funId=func.svar.vid; criStmtId = stmt.sid; criStmtBranch = 0; criLine = loc.line  } in
			allCriEdgesList := !allCriEdgesList @ [cried]
	   	     end
       | _ -> ()
     end
    func.sallstmts

(**********************END***************************)

    
(**********************Find Critical Edges*******************************)


(** 
	The algorithm description:
	Critical edges are those cfg edges which we must follow to reach a target statement.
	A critical edge must also be one of an if stmt's outgoing edge (NOTE a stmt has at most two successors).
	In this algorithm, we also use the conception "immediate dominator" to help finding critical edges.
	"immediate dominator" refer to: http://en.wikipedia.org/wiki/Dominator_(graph_theory)
	
	STEPS:
	target stmt : st
	1) if st has one pred
		  (1) if this pred has two succs, then the edge leading to st is its cried.
		  	  recursive call on pred
		  (2) if this pred has only one succ (namely, st), then 
		  	  recursive call on pred
	2) if st has no pred (reach the top entry function)
		  stop the algorithm
    3) if st has at least two preds (NOTE it is possible for a st has more than two preds), then find st's immediate dominator idom (a stmt has a unique idom, or none for the entry stmt).
       		recursive call on idom
	
*)
let getAllIntrapCriticalEdges (func: Cil.fundec) (tarStmt: Cil.stmt) = 
	(* compute idoms for stmts in func, NOTE we do not to compute CFG info again! *)
	let idomHash = IDom.computeIDom ~doCFG:false func in
	
	let rec findNearestCriticalEdge  (st: Cil.stmt) = 
	  match st.preds with
	  | [ pred ] -> (* has one pred *)
		if List.length (pred.succs) > 1 then begin
			let cried = {funName = func.svar.vname; funId=func.svar.vid; criStmtId = pred.sid; 
						criStmtBranch = (getBranchChoice pred st); 
						criLine = (MyCilUtility.getStmtLoc pred) } in
			(* NOTE ensure the strict sequence of crieds *)
			allCriEdgesList := [cried] @ !allCriEdgesList ;
			
			findNearestCriticalEdge pred
		end else begin
			findNearestCriticalEdge pred;
			E.log "return from recursive call\n"
		end
	  | _ as l -> (* has no pred, or has at least two preds, NOTE it is possible for a cfg node to have more than two preds *)
	  		let len = List.length l in
	  		if len = 0 then begin
	  			E.log "STOP because of no preds\n" 
	  		end else begin
	  			E.log "STOP because of %d preds\n" len; (* has no pred or more than one pred *) 
	  			List.iter
	  			  begin fun el ->
	  			  	E.log "id:%d " el.sid
	  			  end
	  			 l;
	  			E.log "\n";
	  			(* find out st's idom *)
	  			match (IDom.getIdom idomHash st) with
	  			| Some(idom) ->
	  				E.log "its idom exist!\n";
	  				findNearestCriticalEdge idom
	  			| None ->
	  				E.log "no idom exist!\n"
	  		end
	in
	findNearestCriticalEdge tarStmt
;;

(** a wrapper to find critical edges 
    Return None or Some(criticalEdge list)
*)
let getCriticalEdges (file: Cil.file) (funName: string) (stmtId: int) =
   
   (* find the fundec *)
   let func = FindCil.fundec_by_name file funName in
   E.log "In func : %s\n" func.svar.vname;
   (
   match MyCilUtility.findStmtbyId func stmtId with (* find the target stmt *)
   | Some (sm) ->  
	 E.log "sm, id = %d, sm = %a\n" stmtId d_stmt sm;
	 ignore (getAllIntrapCriticalEdges func sm) (* find its all critical edges *)
   | None -> 
   	 E.log "Really? we failed to locate the def statement? MyCriticalEdge@getCriticalEdges\n";
   	 exit 1
   );
	E.log "cried count = %d\n" (List.length !allCriEdgesList);
	let ret = !allCriEdgesList in
	allCriEdgesList := []; (* clear the global list after computation *)
	visitedPredStmtIdList := []; 
	ret
;;

(* 
	The following code is obsolete, 
	because we find Set.diff is not implemented correctly.
*)
(* let diffCriticalEdges_2 (file: Cil.file) (funName: string) (above_stmt_id: int) (below_stmt_id: int) =
	E.log "\n--> find crieds for DEF:\n";
	let above_stmt_crieds = getCriticalEdges file funName above_stmt_id in
	E.log "\n--> find crieds for USE:\n";
	let below_stmt_crieds = getCriticalEdges file funName below_stmt_id in
	
	let above_stmt_crieds_set = ref Crieds_Set.empty in (* create an empty set *)
	let below_stmt_crieds_set = ref Crieds_Set.empty in
	
	List.fold_right Crieds_Set.add above_stmt_crieds !above_stmt_crieds_set;
	List.fold_right Crieds_Set.add below_stmt_crieds !below_stmt_crieds_set;
	
	E.log "PRINT SETS:\n";
	E.log "use crieds:\n";
	Crieds_Set.iter print_cried !below_stmt_crieds_set;
	E.log "def crieds:\n";
	Crieds_Set.iter print_cried !above_stmt_crieds_set;
	let diff_crieds_set = Crieds_Set.diff !below_stmt_crieds_set !above_stmt_crieds_set in
	let diff_crieds_list = Crieds_Set.elements diff_crieds_set in(* get elements as a list *) 
	List.sort (* sort the cirieds according to their stmt ids *)
		begin fun item1 item2 ->
			if item1.criStmtId = item2.criStmtId then
				0
			else if item1.criStmtId < item2.criStmtId then (* smaller --> return negative value *)
				-1
			else	(* bigger --> return positive value *)
				1
		end
	  diff_crieds_list
;;
*)


(** diff crieds of two stmts in the same function.
		funName: the function where two stmts locate
		above_stmt_id: the id of the above stmt
		below_stmt_id: the id of the below stmt
	  Intuitively, the above stmt's id should be smaller than that of the below stmt
*)
let diffCriticalEdges (file: Cil.file) (funName: string) (above_stmt_id: int) (below_stmt_id: int) =
	E.log "\n--> find crieds for DEF:\n";
	let above_stmt_crieds = getCriticalEdges file funName above_stmt_id in
	E.log "\n--> find crieds for USE:\n";
	let below_stmt_crieds = getCriticalEdges file funName below_stmt_id in
	
	E.log "PRINT SETS:\n";
	E.log "use crieds:\n";
	List.iter print_cried below_stmt_crieds;
	E.log "def crieds:\n";
	List.iter print_cried above_stmt_crieds;
	
	let diff_crieds = ref([]: criticalEdge list) in
	let below_stmt_cried_cnt = List.length below_stmt_crieds in
	for i=0 to (below_stmt_cried_cnt-1) do
		let c = List.nth below_stmt_crieds i in
		let r = List.mem c above_stmt_crieds in
		if r = true then
			()
		else begin
			diff_crieds := !diff_crieds @ [c]
		end
	done;
	!diff_crieds
;;


	
(*********************Example code of finding critical edges****************************************)
(*
	The following is the correct implementation to find intrap. critical edges.
*)
class myStmtVisitor (func: Cil.fundec)= 

	(* compute idom *)
	let idomHash = IDom.computeIDom ~doCFG:false func in
	
object(self)
	inherit Cil.nopCilVisitor
	
	method private myfunc (tarStmt: Cil.stmt) = 
	  let rec findNearestCriticalEdge (st: Cil.stmt) = 
		  (* E.log "stmt id = %d, preds count = %d\n" st.sid (List.length st.preds); *)
		  match st.preds with
		  | [ pred ] -> (* has one pred *)
			if List.length (pred.succs) > 1 then begin
				(* Some( pred.sid, (getBranchChoice pred st), (MyCilUtility.getStmtLoc pred) ) *)
				E.log "id%d:c%d:line%d\n" pred.sid (getBranchChoice pred st) (MyCilUtility.getStmtLoc pred);
				findNearestCriticalEdge pred
			end else begin
				findNearestCriticalEdge pred;
				E.log "return from recursive call\n"
			end
		  | _ as l -> (* has no pred, or has at least two preds, NOTE it is possible for a cfg node to have more than two preds *)
		  		let len = List.length l in
		  		if len = 0 then begin
		  			E.log "STOP because of no preds\n" 
		  		end else begin
		  			E.log "STOP because of %d preds\n" len; (* has no pred or more than one pred *) 
		  			List.iter
		  			  begin fun el ->
		  			  	E.log "id:%d " el.sid
		  			  end
		  			 l;
		  			E.log "\n";
		  			(* find out st's idom *)
		  			match (IDom.getIdom idomHash st) with
		  			| Some(idom) ->
		  				E.log "its idom exist!\n";
		  				findNearestCriticalEdge idom
		  			| None ->
		  				E.log "no idom exist!\n"
		  		end
		in
		findNearestCriticalEdge tarStmt
	
	method vstmt (st: Cil.stmt) =
		E.log "target stmt(id%d) \n %a \n\n" st.sid d_stmt st;
		self#myfunc st;
		DoChildren
		
end

let findAllIntrapCriticalEdges (file: Cil.file) = 
	List.iter
		begin fun g ->
			match g with
			| GFun(func, loc) ->	
				E.log "=== func :%s ===\n" func.svar.vname;
				Cil.prepareCFG func;
				Cil.computeCFGInfo func false;
				ignore (Cil.visitCilFunction (new myStmtVisitor func) func);
				E.log "====="
			| _ -> ()
		end
	  file.globals
;;

(************************THE END*****************************************)
	
let feature : featureDescr = 
  { fd_name = "cried";              
    fd_enabled = ref false;
    fd_description = "find critical edges";
    fd_extraopt = [	
		];
    fd_doit = 
    (function (f: file) -> 
     findAllIntrapCriticalEdges f);
    fd_post_check = true
  }

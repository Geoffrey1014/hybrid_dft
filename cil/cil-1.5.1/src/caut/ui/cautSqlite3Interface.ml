(** filename : CautSqlite3Interface
   This file provides interfaces for caut front to manipulate sqlite3 database.
   "Sqlite3" is a self-build ocaml library by using open-source "SQLite3 bindings for Objective Caml"
   Ocaml version : 3.11 Sqlite3 version : 3.7.7.1  Ocaml-sqlite3 binding version : 1.6.1
   Copyright (c) 2011 Krave Su <suting1989@gmail.com>
*)
open Sqlite3
open Printf
exception Pair_not_match of string
exception Name_not_match of string

module E = Errormsg


(** Modified database table record *)
(** testable_unit table *)
type testable_unit_record =
	{
		mutable file_name : string ;
		mutable unit_name : string ;
		mutable return_type : string ;
		mutable parameter_list : string ;
		mutable line_number : int ;
	};;
	
(** unit_parameter_variable table *)
type unit_parameter_variable_record = 
	{
		mutable file_name : string ;
		mutable unit_name : string ;
		mutable par_name : string ;
		mutable par_type : string ;
		mutable par_no : int ;
		mutable caut_input : bool ;
		mutable concrete_value : string ;
		mutable line_number : int ;
	};;

(** call_argument_variable table *)
type call_argument_variable_record = 
	{
		mutable file_name : string ;
		mutable unit_name : string ;
		mutable arg_name : string ;
		mutable arg_type : string ;
		mutable arg_no : int ;
		mutable call_unit : string ;
		mutable caut_input : bool ;
		mutable concrete_value : string ;
		mutable line_number : int ;
	};;
	
(** call_return_variable table *)
type call_return_variable_record =
	{
		mutable file_name : string ;
		mutable unit_name : string ;
		mutable return_name : string ;
		mutable return_type : string ;
		mutable call_unit : string ;
		mutable caut_input : bool ;
		mutable concrete_value : string ;
		mutable line_number : int ;
	};;

(** related_global_variable table *)
type related_global_variable_record =
	{
		mutable file_name : string ;
		mutable unit_name : string ;
		mutable glo_name : string ;
		mutable glo_type : string ;
		mutable caut_input : bool ;
		mutable concrete_value : string ;
		mutable line_number : int ;
	};;

(** cfg node table *)
type cfg_node_list_record =
	{
		mutable file_name: string;
		mutable unit_name: string;
		mutable root_id : int ;
		mutable node_id : int ;
		mutable succ_list : string ;
		mutable prec_list : string ;
		mutable prec_choice_list : string ;
		mutable operand_stack : string ;
		mutable cond_id_list : string;
		mutable is_branch : int ;
		(*Fang*)
		mutable line_no : int ;
		mutable branch_expr : string ;
	};;

(**cfg root node table*)
type cfg_root_list_record =
	{
		mutable file_name: string;
		mutable unit_name: string;
		mutable root_id : int ;

	};;

(** rt_cfg_branch_map_list table *)
type rt_cfg_branch_map_list_record =
	{
		mutable file_name: string;
		mutable unit_name: string;
		mutable rt_branch_id : int ;
		mutable rt_branch_choice : int ;
		mutable cfg_branch_id : int ;
		mutable cfg_branch_choice : int ;
		mutable cfg_branch_isLastCondition : int ;
	};;

class cautFrontDatabaseHelper = 

	let debug_flag = false in
	
	object (self)
	
		(*************************GETTER and SETTER***************************)

		
		(** Modified *)
		(** database table name *)
		val caut_testable_unit_tb_name = "testable_unit"
		val caut_unit_parameter_variable_tb_name = "unit_parameter_variable"
		val caut_call_argument_variable_tb_name = "call_argument_variable"
		val caut_call_return_variable_tb_name = "call_return_variable"
		val caut_related_global_variable_tb_name = "related_global_variable"
		val caut_cfg_node_list_tb_name = "node_list"
		val caut_cfg_root_list_tb_name = "root_list"
		val caut_cfg_rt_cfg_branch_map_list_tb_name = "rt_cfg_branch_map_list"
		
		(** database table name getter *)
		method get_caut_testable_unit_tb_name = caut_testable_unit_tb_name
		method get_caut_unit_parameter_variable_tb_name = caut_unit_parameter_variable_tb_name
		method get_caut_call_argument_variable_tb_name = caut_call_argument_variable_tb_name
		method get_caut_call_return_variable_tb_name = caut_call_return_variable_tb_name
		method get_caut_related_global_variable_tb_name = caut_related_global_variable_tb_name
		method get_caut_cfg_node_list_tb_name = caut_cfg_node_list_tb_name
		method get_caut_cfg_root_list_tb_name = caut_cfg_root_list_tb_name
		method get_caut_cfg_rt_cfg_branch_map_list_tb_name = caut_cfg_rt_cfg_branch_map_list_tb_name
		
		(**********************PRIVATE METHOD*************************)
		(** "caut_column_type" finds out the type of specified field_name including TEXT or INTEGER or BOOLEAN.
			For example , "WHERE unit_name='test' " is different from "WHERE unit_name=test "
			This function is just for convenience for generating sql string.
			@param 1 column name in database table
			@return cloumn type name
		*)
		(*Fang Modified*)
		method private get_column_type (column_name:string) : string =
			match column_name with 
			| "file_name" | "unit_name" | "result_type" | "parameter_list" | "par_name" | "par_type" | "glo_name" | "glo_type" 
			| "arg_name" | "arg_type" | "return_name" | "return_type" | "call_unit" 
			| "succ_list" | "prec_list" | "prec_choice_list" | "operand_stack" |"cond_id_list" | "branch_expr" -> "TEXT"
			| "var_no" | "unit_no" | "arg_no" | "par_no" | "line_number" | "line_no"
			| "root_id" | "node_id"| "rt_branch_id" |"rt_branch_choice" | "cfg_branch_id" |  "cfg_branch_choice"
    			| "cfg_branch_isLastCondition" | "is_branch" ->  "INTEGER"
			| "caut_input" -> "BOOLEAN"
			| _ -> ""
			
		(** "caut_generate_pair" generates pair sql clause such as WHERE , SET and etc .
			For example , "WHERE where_name_1 = where_args_1 and where_name_2 = where_args_2" 
			pair_name is corresponding to pair_value and separator is for separating between
			pairs. 
			This function is just for convenience for generating sql string.
			@param 1 pair name
			@param 2 pair value
			@param 3 separator
		*)
		method private caut_generate_pair (pair_name:string list) (pair_value:string list) (separator:string) : string =
			(* if pair not match , raise exception *)
			if (List.length pair_name) != (List.length pair_value) then 
				raise (Pair_not_match "[caut_generate_pair] : pair name and value not match")
			;
			let tmp_buf = Buffer.create 20 in
			let deli = (List.length pair_name)-1 in
			for j = 0 to deli do
				let pair_name_t = List.nth pair_name j in
				let pair_value_t = List.nth pair_value j in
				Buffer.add_string tmp_buf pair_name_t;
				Buffer.add_string tmp_buf "=";
				let type_text = self#get_column_type pair_name_t in
				(
				match type_text with
				| "TEXT" ->
						Buffer.add_string tmp_buf "'";
						Buffer.add_string tmp_buf pair_value_t;
						Buffer.add_string tmp_buf "'"
				| "INTEGER" | "BOOLEAN"  -> 				
						Buffer.add_string tmp_buf pair_value_t
				| _ ->
					raise (Name_not_match "[caut_generate_pair] column type name not match. ") 
				);
				if j < deli then
					begin
						Buffer.add_string tmp_buf " ";
						Buffer.add_string tmp_buf separator;
						Buffer.add_string tmp_buf " "
					end
			done ;
			Buffer.contents tmp_buf
			
		(** "caut_dump_tb" outputs all entries in the specified table using sql selection clause. 
			This function is just for convenience for debugging.
			@param 1 database handler
			@param 2 table name
		*)
		method private caut_dump_tb (db_handler:db) (tb_name:string) = 
			
			printf "[****DEBUG*****]\n" ;
			let tmp_buf = Buffer.create 20 in
			Buffer.add_string tmp_buf "SELECT * FROM ";
			Buffer.add_string tmp_buf tb_name;
			let debug_sql_string = Buffer.contents tmp_buf in
			let debug_stmt = prepare db_handler debug_sql_string in
			let column_count_t = (column_count debug_stmt)-1 in
			printf "\tcolumn count = %d \n" (column_count_t+1) ;
			while (step debug_stmt) == Rc.ROW do
				for i=0 to column_count_t do
					printf "%-10s " (Data.to_string (column debug_stmt i));
				done;
				printf "\n"
			done;
			printf "[**************]\n";
						
		(** The following databse methods include open/close databse , create/drop table,
			update/delete/insert operations on table. For sqlite3 database manipulation , we follow
			such order : generate sql string -> prepare it -> step it -> process the results
			based on the returing code.
			For concrete information , refer to Sqlite3 mannual.
		*)		
		(******************OPEN and CLOSE DATABASE METHOD ******************************)
		
		(** create/open or close database *)
		method caut_open_database (db_name:string) = db_open db_name 
		method caut_close_database (db_handler:db) = db_close db_handler
		
		(*******************CREATE and DROP TABLE METHOD**************************)
		
		(** drop table *)
		method caut_drop_database_table (db_handler:db) (tb_name:string) : bool =
			
			let tmp_buf = Buffer.create 50 in
			Buffer.add_string tmp_buf "DROP TABLE IF EXISTS ";
			Buffer.add_string tmp_buf tb_name;
			
			let drop_tb_sql_string = Buffer.contents tmp_buf in
			let stmt_drop = prepare db_handler drop_tb_sql_string in
			let result = step stmt_drop in
			if result == Rc.DONE then 
				begin 
					if debug_flag then 
						printf "drop table : [ %s ] succeeded \n" tb_name;
					ignore (finalize stmt_drop) ;
					true 
				end
			else 
				begin
					if debug_flag then 
						printf "drop table : [ %s ] failed \n" tb_name ;
					ignore (finalize stmt_drop) ;
					false
				end
			
			
		(** create table *)
		method caut_create_database_table (db_handler:db) (tb_name:string) : bool = 
				
				let sql_string = ref "" in
				(
				match tb_name with 
				| "testable_unit" ->
					sql_string := "CREATE TABLE IF NOT EXISTS testable_unit
									(unit_no INTEGER PRIMARY KEY ASC ,
									 file_name TEXT ,
									 unit_name TEXT ,
									 result_type TEXT ,
									 parameter_list TEXT ,
									 line_number INTEGER 
									)" 
					
				| "unit_parameter_variable" ->
					sql_string := "CREATE TABLE IF NOT EXISTS unit_parameter_variable
									(var_no INTEGER PRIMARY KEY ASC ,
									 file_name TEXT ,
									 unit_name TEXT ,
									 par_name TEXT ,
									 par_type TEXT ,
									 par_no INTEGER ,
									 concrete_value TEXT ,
									 caut_input BOOLEAN , 
									 line_number INTEGER 
									)" 
				| "call_argument_variable" ->
					sql_string := "CREATE TABLE IF NOT EXISTS call_argument_variable
									(var_no INTEGER PRIMARY KEY ASC ,
									 file_name TEXT ,
									 unit_name TEXT ,
									 arg_name TEXT ,
									 arg_type TEXT ,
									 arg_no INTEGER ,
									 call_unit TEXT ,
									 concrete_value TEXT ,
									 caut_input BOOLEAN , 
									 line_number INTEGER 
									)" 
				| "call_return_variable" -> 
					sql_string :=	"CREATE TABLE IF NOT EXISTS call_return_variable
									(var_no INTEGER PRIMARY KEY ASC ,
									 file_name TEXT ,
									 unit_name TEXT ,
									 return_name TEXT ,
									 return_type TEXT ,
									 call_unit TEXT ,
									 concrete_value TEXT ,
									 caut_input BOOLEAN , 
									 line_number INTEGER 
									)" 
				| "related_global_variable" ->
					sql_string :=	"CREATE TABLE IF NOT EXISTS related_global_variable
									(var_no INTEGER PRIMARY KEY ASC ,
									 file_name TEXT ,
									 unit_name TEXT ,
									 glo_name TEXT ,
									 glo_type TEXT ,
									 concrete_value TEXT ,
									 caut_input BOOLEAN , 
									 line_number INTEGER 
									)" 
				| "node_list" ->
					sql_string := "CREATE TABLE IF NOT EXISTS node_list 
										(	file_name TEXT ,
    											unit_name TEXT ,
    											root_id INTEGER,
											node_id INTEGER, 
											succ_list TEXT, 
											prec_list TEXT,
											prec_choice_list TEXT, 
											operand_stack TEXT,
											cond_id_list TEXT,
											is_branch INTEGER,
											line_no INTEGER,
											branch_expr TEXT
										)"  (*Fang*)
				| "root_list" -> 
					sql_string := "CREATE TABLE IF NOT EXISTS root_list 
										( file_name TEXT ,
    									unit_name TEXT ,
    									root_id INTEGER
										)"
										
				| "rt_cfg_branch_map_list" -> 
					sql_string := " CREATE TABLE IF NOT EXISTS rt_cfg_branch_map_list 
										(	file_name TEXT ,
    									unit_name TEXT ,
    									rt_branch_id INTEGER,
   									 	rt_branch_choice INTEGER,
   									 	cfg_branch_id INTEGER,
    								  cfg_branch_choice INTEGER,
   									 	cfg_branch_isLastCondition INTEGER
										)"
					
				| _ -> 
					raise ( Name_not_match "[caut_create_database_table] : database table name not match?" )
				);
				let stmt_ = prepare db_handler !sql_string in
				let result = step stmt_ in
				if result != Rc.DONE then 
					begin
						if debug_flag then 
							printf "**********create table : [ %s ] failed \n" tb_name ;
						ignore (finalize stmt_) ;
						false 
					end
				else 
					begin
						if debug_flag then 
							printf "**********create table : [ %s ] succeeded \n" tb_name ;
						ignore (finalize stmt_) ;
						true 
					end
				
					
					
		(**********************UPDATE METHOD*******************)
		(** update database table 
			@param 1 database handler
			@param 2 table name
			@param 3 coulmn name
			@param 4 column value
			@param 5 where name
			@parame 6 where arg
		*)
		method update_caut_tb (db_handler:db) (tb_name:string) (column_name:string list) (column_value:string list) (where_name : string list) (where_args : string list) : bool =
			let tmp_buf = Buffer.create 200 in
			Buffer.add_string tmp_buf "UPDATE ";
			Buffer.add_string tmp_buf tb_name;
			Buffer.add_string tmp_buf " SET ";
			
			(* generate sql set clause , like "SET column_name_1 = column_value_1 , column_name_2 = column_value_2" *)
			Buffer.add_string tmp_buf (self#caut_generate_pair column_name column_value ",");
			
			Buffer.add_string tmp_buf " WHERE ";
			
			(* generate sql where clause , like "WHERE column_name_1 = column_value_1 and column_name_2 = column_value_2" *)
			Buffer.add_string tmp_buf (self#caut_generate_pair where_name where_args "and");
			
			(* debug *)
			if debug_flag then 
			begin
				printf "*********\n";
				printf "\t%s\n\n" (Buffer.contents tmp_buf);
				printf "*********\n"
			end;
			
			let update_sql_string = Buffer.contents tmp_buf in
			let prepared_stmt = prepare db_handler update_sql_string in
			let result = step prepared_stmt in
			if result == Rc.DONE then
				(
				ignore (finalize prepared_stmt) ;
				if debug_flag then 
					printf "[%s]update entry succeeded! \n" tb_name ;
				true
				)
			else
				(
				ignore (finalize prepared_stmt) ;
				if debug_flag then 
					printf "[%s]update entry failed! \n" tb_name;
				false
				)
					
		(**********************DELETE METHOD*******************)
		(** delete table entry 
		*)
		method delete_caut_tb (db_handler:db) (tb_name:string) (where_name : string list) (where_args : string list) : bool =
			let tmp_buf = Buffer.create 200 in
			Buffer.add_string tmp_buf "DELETE FROM ";
			Buffer.add_string tmp_buf tb_name;
			Buffer.add_string tmp_buf " WHERE ";
			
			(* generate sql where clause , like "WHERE column_name_1 = column_value_1 and column_name_2 = column_value_2" *)
			Buffer.add_string tmp_buf (self#caut_generate_pair where_name where_args "and");
			
			(* debug *)
			if debug_flag then 
			begin
				printf "*********\n";
				printf "\t%s\n\n" (Buffer.contents tmp_buf);
				printf "*********\n"
			end;
			
			let delete_sql_string = Buffer.contents tmp_buf in
			let prepared_stmt = prepare db_handler delete_sql_string in
			let result = step prepared_stmt in
			if result == Rc.DONE then
				(
				ignore (finalize prepared_stmt) ;
				if debug_flag then 
					printf "[%s]Delete entry succeeded! \n" tb_name ;				
				true
				)
			else
				(
				ignore (finalize prepared_stmt) ;
				if debug_flag then 
					printf "[%s]Delete entry failed! \n" tb_name;
				false
				)
			
			
		(***********************QUERY METHOD************************)
		(** query table 
		*)
		method query_caut_tb (db_handler:db) (tb_name:string) (column_name : string list) (where_name : string list) (where_args : string list) : string list = 
			
			let dump =false in
			if dump = true then 
				E.log "****QUERY METHOD***\n";

			let return_list = ref ([]:string list) in
			let tmp_buf = Buffer.create 200 in
			Buffer.add_string tmp_buf "SELECT DISTINCT ";
			let deli = (List.length column_name)-1 in
			for i = 0 to deli do
				let elem = (List.nth column_name i) in
				Buffer.add_string tmp_buf elem;
				if i < deli then 
					Buffer.add_string tmp_buf ","
			done;
			Buffer.add_string tmp_buf " FROM ";
			Buffer.add_string tmp_buf tb_name ;
			
			(* we may have sql like "SELECT xxx FROM yyy" , no where clause *)
			if not (((List.length where_name )== 0) && ((List.length where_args) ==0)) then
				begin
					Buffer.add_string tmp_buf " WHERE " ;
					
					(* generate sql where clause , like "WHERE column_name_1 = column_value_1 and column_name_2 = column_value_2" *)
					Buffer.add_string tmp_buf (self#caut_generate_pair where_name where_args "and")
				end
			;	
			
			if dump = true then 	
			begin
				E.log "*********\n";
				E.log "\t%s\n\n" (Buffer.contents tmp_buf);
				E.log "*********\n"	
			end;

			let select_sql_string = Buffer.contents tmp_buf in
			let prepared_stmt = prepare db_handler select_sql_string in
			let columns_number = (column_count prepared_stmt)-1 in
			while (step prepared_stmt) == Rc.ROW do
				for k = 0 to columns_number do
					let tmp_result = Data.to_string (column prepared_stmt k) in
					return_list := !return_list @ [tmp_result]
				done ;
				if debug_flag then 
					printf "\n"
			done;
			!return_list 
					
		(**************************INSERT METHOD********************************)
		(** insert table entry
		*)
		method insert_caut_tb (db_handler:db) (tb_name:string) (column_name : string list) (column_value : string list) : bool = 
		
			(* if pair not match , raise exception *)
			let column_name_len = List.length column_name in
			let column_value_len = List.length column_value in
			if column_name_len != column_value_len then 
				raise (Pair_not_match "[insert_caut_tb] column name and value length not match." )
			;
			
			let tmp_buf = Buffer.create 200 in
			Buffer.add_string tmp_buf "INSERT INTO " ;
			
			Buffer.add_string tmp_buf tb_name ;
			Buffer.add_string tmp_buf " (" ;
		

			for i = 0 to (column_name_len-1) do
				Buffer.add_string tmp_buf (List.nth column_name i) ;
				if i < (column_name_len -1 ) then
					Buffer.add_string tmp_buf ","
			done;
			
			Buffer.add_string tmp_buf ") VALUES (" ;
			for i=0 to (column_value_len -1) do
				let name_t = List.nth column_name i in
				let value_t = List.nth column_value i in
				(
				match (self#get_column_type name_t) with
				| "TEXT" -> 
						Buffer.add_string tmp_buf "'";
						Buffer.add_string tmp_buf value_t ;
						Buffer.add_string tmp_buf "'";
				| "INTEGER" | "BOOLEAN" -> 
						Buffer.add_string tmp_buf value_t ;
				| _ -> 
						raise ( Name_not_match "[insert_caut_tb] : column type name eorror ")
				);
				if i < column_value_len -1 then
					Buffer.add_string tmp_buf ","
			done;
			
			Buffer.add_string tmp_buf ")" ;
			
			(*debug*)
			if debug_flag then 
			begin
				printf "*********\n" ;
				printf "\t%s\n\n" (Buffer.contents tmp_buf);
				printf "*********\n" 	
			end;
			
			let sql_string = Buffer.contents tmp_buf in
			let stmt_ = prepare db_handler sql_string in
			let result = step stmt_ in
			if result != Rc.DONE then 
				begin
					if debug_flag then 
						printf "**********[ %s ] insert record failed \n" tb_name ;
					ignore (finalize stmt_) ;
					false
				end
			else 
				begin
					if debug_flag then 
						printf "**********[ %s ] insert record succeeded \n" tb_name ;
					ignore (finalize stmt_) ;
					true
				end
							
	end;;
	

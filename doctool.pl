/*

Doctool
     - Select document
     - Run file through GATE/ANNIE
     - Compile results
     - Create data: Document -> Section -> Sentence -> Word -> Node

finder <-file: Exists:[bool], Ext:[name|chain], Dir:[directory], Def:[file]
*/

:- module(doctool,[]).

:- use_module(graph_lib).
:- use_module(fbo_update).
:- use_module(watch).
:- use_module(greplite).
:- use_module(xquery).
:- use_module(library(http/http_ssl_plugin)).
:- use_module(library(http/http_open)).
:- use_module(library(sgml)).
:- use_module(library(sgml_write)).

:- add_graph_dest(neo4j).

:- use_module(library(find_file)).


user:load(File) :-
       get(@finder, file, @on, '*', File).
user:load(File,Ext) :-
        get(@finder, file, @on, Ext, File),
        format('File: ~w\n',[File]).
         
user:add_document :-
               load(File),
               fedbizopps:mine_file(absolute(File), _, _).

user:add_document(Owner) :-
               load(File),
               fedbizopps:mine_file(absolute(File), element(owner,[name=Owner],[]), _).              
              

			  
user:q_document :- q_document(none), !.
user:q_document(Owner) :-
     load(File),
     add_graph_dest(neo4j),
     anal_file_type(File, Type),
     get_time(T0),
     new_node(Doc, check, [type=mine_file,filename=File,owner=Owner,file_type=Type,created=T0]),
     format('Created request to mine file ~w\n',[File]), !.
    
anal_file_type(File, unknown).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  Exec %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	
mine_exec_main :-
		increment(run),
	(
	% TODO - order by priority not working for some stupid reason. Need to reintroduce feature 
%		fcypher_query('match (ck:check {type: "gate"}) return ck.filename,ck.owner,ck.file_type,id(ck) order by ck.priority ', [], row([File,Owner,FileType,Ck])),
		fcypher_query('match (ck:check {type: "mine_file"}) return ck.filename,ck.owner,ck.file_type,id(ck)  ', [], row([File,Owner,FileType,Ck])),
		gephi:del_node(Ck),
		once((
		increment_stat(gate_process_check),
		log_messageF(info(gate_exec,File)),
		get_time(T0),
		catch(must(fedbizopps:mine_file(File,_,_)), Error, (new_node(_, check, [type=gate_retry,filename=File,time=T0,owner=Owner,file_type=FileType,error=Error,retry=5]), increment(gate_error), fail)),
		increment_stat(gate_check_completed))),

	fail;true).
	
:- pce_global(@finder, new(finder)).

user:mine_exec :- start_exec(mine_exec), thread_send_message(mine_exec, periodic(doctool:mine_exec_main,minutes(1))).

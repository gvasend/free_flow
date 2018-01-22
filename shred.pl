 
 :- module(graph_req, []).

:- use_module(library(xpath)).

:- use_module(graph).

:- use_module(argparse).
 
:- use_module(library(dcg/basics)).
:- use_module(library(sha)).

:- dynamic(document/3).
:- dynamic(sentence/2).
:- dynamic(has_sentence/2).

match_topic(Topic,Mess) :-
	debug([fabric,match_topic],'match topic graph_req ~w for ~w',[Topic,Mess]),
	wildcard_match('knowledge.*',Topic), !.
match_topic(Topic,Mess) :-
	debug([fabric,match_topic],'match topic graph_req ~w for ~w',[Topic,Mess]),
	wildcard_match('default.*',Topic), !.


categorize_text(requirement_source,Text) :-
	match(Text).
categorize_text(sentence,Text) :-
	\+ match(Text).
	

category_color(requirement_source, [size=4]).
category_color(_, [size=2]).
	
match(Text) :-					% dep
	downcase_atom(Text,Down),
	req_pattern(Pattern),
	wildcard_match(Pattern, Down), 
	!.
	
match(Text,Cat) :-
	downcase_atom(Text,Down),
	category_pattern(Cat,Pattern),
	wildcard_match(Pattern, Down), 
	!.

:- dynamic(category_pattern/2).	
:- dynamic(section_pattern/2).	


%% load_rules
%
% load requirement tagging rules. can either match patterns in the sentence or target specific sections in the document.

load_rules :-
    debug([match,_],'before load rules\n',[]),
    argparse:argument_value('tagging_rules',Filename),
	load_xml_file(Filename,XML),
	(
		xpath:xpath(XML, //tag_rule(@category=Cat), TagRule),
		retractall(category_pattern(_,_)),
		retractall(section_pattern(_,_)),		(
			xpath:xpath(TagRule, //match(@keyword=Key), _),
			format(atom(Match),'* ~w *',[Key]),
			assert(category_pattern(Cat,Match)),
		fail;true),
		(
			xpath:xpath(TagRule, //section(@match_sect=Match), _),
			assert(section_pattern(Cat,Match)),
		fail;true),
	fail;true).
	
	
match(Id,Section,Text,Pattern,Cat) :-						% any text in these sections are considered requirement text

	section_pattern(Cat,Pattern),
    debug([match,section,before],'befoe match section ~w ~w',[Pattern,Section]),
	wildcard_match(Pattern,Section),
    debug([match,section,after],'after match section ~w ~w',[Pattern,Section]),
	\+ un_requirement(Text),
	!.


wild_member(Elem,List, E) :-
	member(E, List),
	wildcard_match(E, Elem).
	
un_requirement(Text) :-
	count_type(Text, lower, Count),
	Count =0.
	
user:count_type(Str, Type,Total) :-
	atom_codes(Str, Codes),
	findall(Code, (member(Code, Codes), code_type(Code, Type)), Types),
	length(Types, Total).

match(_,_,Text,unknown,Cat) :-							% any text not in a special section gets flagged by presence of keywords
	match(Text,Cat),
    debug([match,keyword],'~w categorized by ~w',[Text,Cat]).

write_csv(CSV, Sect,Text) :-
	clean_string(Text, Clean),
	format(CSV, '~w,"~w"\n', [Sect,Clean]).
	
	
clean_string(In, Out) :-
	atom_codes(In, Codes),
	findall(Code, (member(Code,Codes), (code_type(Code, graph);code_type(Code,white))), OutList),
	atom_codes(Out, OutList).


:- dynamic(section_number/3).
:- dynamic(section_text/5).


	
			
abbreviate_text(In, Out) :-
	atomic_list_concat([Out|_], '\n', In).

user:find_rule(Text, Rule, Name, Remain) :-
				atom_codes(Text, Codes), 
				phrase(graph_req:section(Rule,Name1), Codes, RemainList),
				remove_chars(punct,Name1,Name),
				atom_codes(Remain, RemainList), !.
user:find_rule(Text, null, '', Text).

remove_chars(Type,In,Out) :-
	atom_codes(In,InCodes),
	remove_codes(Type,InCodes,OutCodes),
	atom_codes(Out,OutCodes).
	
remove_codes(Type,[H|T],T1) :-
	remove_code('.',Type,H),
	remove_codes(Type,T,T1).
remove_codes(Type,[H|T],[H|T1]) :-
	\+ remove_code('.',Type,H),
	remove_codes(Type,T,T1).
remove_codes(_,[],[]).

remove_code(Keep, RemoveType, Code) :-
	code_type(Code,RemoveType),
	\+ char_code(Keep,Code).
	
		

shred :-
		(
			graph:node(Doc,document,Attr),
            debug([iterate,document],'document ~w',[Doc]),
            intersection([doc_type=rfp,doc_type=pws,doc_type=sow,doc_type=solicitation],Attr,[DocType|_]),
            debug([iterate,doc_type],'doc type ~w\n',[DocType]),
            graph:edge(_, Doc, Sent, has_sentence, _),
            debug([iterate,sentence],'sentence ~w',[Sent]),
%            graph:node(Sent, sentence, _),
            categorize(Sent),
			fail;true), 
		!.
	
categorize(Sent) :-
        graph:node(Sent, sentence, SentAttr),
        graph:edge(_, Sect, Sent, section_link, _),
        graph:node(Sect, section, SectAttr),
        subset([text=Text], SentAttr),
        once(subset([title=SectTitle], SectAttr);SectTitle=''),
																																						
		once(match(Sent,SectTitle,Text,ReqType,Tag)),
				
        graph:add_node_attributes(Sent, [category=Tag,req_type=ReqType]),
		!.
		
fail_error(G) :-
    catch(G, Error, format('Exception ~w\n',[Error])).
		


:- argparse:add_argument('--input_graph',[default='*graph_output',description='graph input filename']). 
:- argparse:add_argument('--tagging_rules',[default='/home/gvasend/gv-ML-code/freeflow/tagging_rules.xml',description='rules that define how sentences are tagged']). 
		

run :- 
    argparse:argparse, 
    argparse:get_argument('input_graph',File),
    fail_error(graph:load_graphml(File)), 
    fail_error(load_rules),
    format('loaded ~w\n',[File]), 
    shred, 
    graph:save_graphml,
    halt(0).

run :- halt(11).

:- debug(_).
	
:- run.

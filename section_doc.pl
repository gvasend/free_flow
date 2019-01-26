 
 :- module(section_doc, []).

:- use_module(library(xpath)).
 :- use_module(library('http/json')).
 :- use_module(argparse).
 
 :- use_module(document_dcg).

:- use_module(graph).
 
 
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
 
 
 
replace(In, From, To, Out) :-
    atomic_list_concat(L, From, In),
    atomic_list_concat(L, To, Out).
 
argument('--graph_output',[description='graph output filename']). 
argument(X) :- argument(X,_).

 argparse(Exp,ArgList) :-
    findall(Ar, argument(Ar), Exp),
    current_prolog_flag(argv, AllArgs),
    findall(arg(AName,Sarg), (append([Farg, Sarg], Remain, AllArgs), atom_concat('--', AName, Farg)), ArgList1),
    findall(arg(AName,true), (append([Farg], Remain, AllArgs), \+atom_concat('--', AName, Farg), atom_concat('-',AName,Farg)), ArgList2),
    append(ArgList1, ArgList2, ArgList),
    writeln(ArgList).

document_type(Doc,Type) :-
	document(Doc, DocAttr),
	is_list(DocAttr),
	subset([type=Type],DocAttr).


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

	
match(_Id,Section,Text,_Stack,Pattern,Cat) :-						% any text in these sections are considered requirement text

	section_pattern(Cat,Pattern),
	wildcard_match(Pattern,Section),
	\+ un_requirement(Text),
	!.

match1(_Id,_Section,Text,Stack,Sect) :-						% any text in these sections are considered requirement text
	member(indent(rfp_section,Sect), Stack), 
	member(Sect,['C','L','M']),
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

match(_,_,Text,_,unknown,Cat) :-							% any text not in a special section gets flagged by presence of keywords
	match(Text,Cat).

write_csv(CSV, Sect,Text) :-
	clean_string(Text, Clean),
	format(CSV, '~w,"~w"\n', [Sect,Clean]).
	
clean_string(In, Out) :-
	atom_codes(In, Codes),
	findall(Code, (member(Code,Codes), (code_type(Code, graph);code_type(Code,white))), OutList),
	atom_codes(Out, OutList).


:- dynamic(section_number/3).
:- dynamic(section_text/5).

open_graph(Iname,Name) :-
	debug([graph_csv,open_graph],'open_graph ~w ~w',[Iname,Name]),
%	xmind::gdb:open_graph(Name),
	flag(doc_name,_,Name),
	true.
	
			
abbreviate_text(In, Out) :-
	atomic_list_concat([Out|_], '\n', In).

user:find_rule(Text, Rule, Name, Remain) :-
				atom_codes(Text, Codes), 
				phrase(document_dcg:section(Rule,Name1), Codes, RemainList),
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
	

add_event(Node,Name,Type) :-
	get_time(Time).
%	'knowledge.priority'::gdb:new_node(Event, event, [time=Time,name=Name,type=Type,doc_id=Node]),
%	'knowledge.priority'::gdb:new_edge(_, Node, Event, has_event, []).
	

		
		
fail_error(G) :-
    catch(G, Error, format('Exception ~w\n',[Error])).

		
section_new(Doc,Sentences) :-
            format('before concat ~w ~w',[Doc1,Doc]),
%            atom_concat(Doc1, '_document', Doc),
			retractall(section_text(Doc,_,_,_,_)),
			length(Sentences,TotalSent),
			debug([section_doc,section],'analyzing ~w sentences ',[TotalSent]),
			flag(counter, _, 0),
            ( 
              flag(counter, Counter, Counter+1),
              member(sentence(_,Sent), Sentences),
              debug([section_doc,sentences],"Sentence ~w :: ~w",[Counter,Sent]),
            fail;true),
			once(ignore(mark_sections(Doc, [indent(0,'')], Sentences, _Out))),
            listing(section_text),
			debug([section_doc,section],'after mark_sections ',[]),
			(
				section_text(Doc, Id,Sect,Text,Stack),
                log_file(Text),
				debug([section_doc,section],'section text ~w',[sect_text(Id,Sect,Stack)]),
                sleep(0.0),
				visualize_topic_r(Doc, Stream, 'Section', Sect, Leaf, [doc_id=Doc]),		% visualize section outline for knowledge graph
				new_edge(_,Leaf,Id,'SECTION_LINK',[]),				% link to document node
                format('linking ~w -> ~w\n',[Leaf,Id]),
			fail;true), 
			debug([section_doc,section],'after graphing requirements ',[]),
		!.

%    <node id="820d43b5-714b-11e7-ba44-1cc1de329608">
%      <data key="d0">ALL Stock numbered items shall be bar coded.\n\na.</data>
%      <data key="d1">sentence</data>
%      <data key="d2">30</data>
%    </node>
		


    
	
visualize_topic(Topic, Leaf) :-
	visualize_topic(fm, Topic, Leaf).

visualize_topic_r(Prefix, Label, Topic, Leaf) :-
	visualize_topic_r(Prefix, Label, Topic, Leaf, []).
	
visualize_topic_r(Parent, Prefix, Label, Topic1, Leaf, Attributes) :-
	format(atom(Topic2),'~w::.~w',[Parent,Topic1]),								% ensure section structure has unique names by prefixing with document node id
	replace(Topic2, '..', '.', Topic),
	debug([fabric,vizr,topic],'prefix ~w topic ~w',[Prefix, Topic]),
	atomic_list_concat(Topics, '.', Topic),
	reverse(Topics, TopicsR),
	visualize_topic_r1(Prefix, Label, TopicsR, [Leaf|Rest], Attributes),
	debug([fabric,vizr,topic],'first topic ~w',[[Leaf|Rest]]),
	(
		nextto(Lower, Higher, [Leaf|Rest]),
		new_edge(_, Higher, Lower, 'CHILD_TOPIC', []),
	fail;true),
    format('after linking topics\n',[]),
	last(Rest, TopNode),
    format('after last ~w\n',[x(Rest,TopNode)]),
	new_edge(_,Parent,TopNode,'SECTION_ROOT',[]),
	format('after new edge\n',[]).
	
child_topic(S1, S2) :-
	length(S1,L1),
    length(S2, L2),
    L1 > L2,
	new_edge(_, S2, S1, 'CHILD_TOPIC', []).		% child topics should have more characters in title
child_topic(S1, S2) :-
	length(S1,L1),
    length(S2, L2),
    not(L1 > L2),
	new_edge(_, S1, S2, 'CHILD_TOPIC', []).

visualize_topic_r1(Pre, Label, [H|T], [Sect|Ids], Attributes) :-
	reverse([H|T], Rev),
	atomic_list_concat(Rev, '.', Sect),
    make_title(Sect,SectTitle),
	new_node(Sect, Label, [title=SectTitle|Attributes]),
	link_sect_doc(Sect, Attributes),
	visualize_topic_r1(Pre, Label, T, Ids, Attributes).
visualize_topic_r1(_, _, [], [], _).

link_sect_doc(Sect, Attr) :-
    member(doc_id=Doc, Attr),
    \+ graph:edge(_, Sect, Doc, 'BELONGS_TO', []),
    new_edge(_, Sect, Doc, 'BELONGS_TO', []), !.
link_sect_doc(_,_).
	
make_title(In, Title) :-
    atomic_list_concat([_,Title|_], '::.', In), !.
make_title(Title, 'None').
	

mark_sections(Doc, StackIn, [sentence(Id,H)|T], StackOut2) :-
        debug([graph_csv, find_section],'1 ~w',[match_section(StackIn, indent(Rule,NewText), H, Ha)]),
		once(match_section(StackIn, indent(Rule,NewText), H, Ha)),
        debug([graph_csv, find_section],'2 ~w',[match_section(StackIn, indent(Rule,NewText), H, Ha)]),
        debug([graph_csv, find_section],'1 ~w',[apply_section(R, Rule, NewText, StackIn, StackOut1)]),
		once(apply_section(R, Rule, NewText, StackIn, StackOut1)),
       debug([graph_csv, find_section],'2 ~w',[apply_section(R, Rule, NewText, StackIn, StackOut1)]),
		flag(doc_name, Name, Name),
        format_section('', StackOut1, Section),
		
		assert(section_text(Doc,Id,Section,Ha,StackOut1)),
		
        debug([graph_csv, find_section],'3 ~w',[apply_section(R, Rule, NewText, StackIn, StackOut1)]),
		mark_sections(Doc, StackOut1, T, StackOut2).
mark_sections(_, In, [], In).

format_section(Root, Stack, Text) :-
	reverse(Stack, RStack),
	format_section1(RStack, TextList),
	atomic_list_concat(TextList, '.', Text1),
	replace(Text1, ')', '', Text2),
	atomic_list_concat([Root,Text2], Text).
	
format_section1([indent(_,H1)|T], [H1a|T1]) :-
    replace(H1,' ','',H1a),                        % remove any leading/trailing space
	format_section1(T, T1).
format_section1([],[]).

%% apply_section - detect and process section prefixes in a text document
%
% limitation - popping the stack only happens when the section moves 1 level up. need to handle an arbitrary move up the stack

apply_section(1, null, _, [indent(Rule,Val)|Rest], [indent(Rule,Val)|Rest]) :- !.							% no header patterns detected, stack is unchanged
apply_section(2, Rule, Sect, [indent(Rule,_Val)|Rest], [indent(Rule,Sect)|Rest]) :- !.						% stay at same level and replace current section header
apply_section(3, Rule, Sect, [indent(Rule1,_)|Rest], [indent(Rule,Sect)|Rest1]) :-							% pop the current stack level and replace section header
	Rule1 \= Rule, 
    nth1(Ind, Rest, indent(Rule,_)), 
	length(List, Ind), 
	append(List, Rest1, Rest),
	!.
apply_section1(3, Rule, Sect, [indent(Rule1,_),indent(Rule,_)|Rest], [indent(Rule,Sect)|Rest]) :-		% pop the current stack level and replace section header
	Rule1 \= Rule, !.
apply_section(4, Rule, Sect, [indent(Rule1,Val)|Rest], [indent(Rule,Sect)|Stackp]) :-	% push the current stack level and replace section header
	Rule1 \= Rule,
	rule_pri(Rule, Pri),
	prioritize_rules(Pri, [indent(Rule1,Val)|Rest], Stackp).
	
prioritize_rules(Pri, [indent(Rule,Name)|T], [indent(Rule,Name)|T1]) :-
	rule_pri(Rule, Stackpri),
	Pri =< Stackpri,
	prioritize_rules(Pri, T, T1).
prioritize_rules(Pri, [indent(Rule,_Name)|T], T1) :-
	rule_pri(Rule, Stackpri),
	Pri > Stackpri,
	prioritize_rules(Pri, T, T1).
prioritize_rules(_, [], []).


rule_priority(rfp_section,20).
rule_priority(decimal,15).
rule_priority(small_alpha,10).
rule_priority(large_alpha,16).

rule_priority(colon,7).
rule_priority(cdrl_section,3).
rule_priority(attachment_section,3).
rule_priority(double_paren_decimal,6).
rule_priority(single_paren_decimal,9).
rule_priority(single_paren_large_alpha_section,8).
rule_priority(single_paren_small_alpha_section,7).
rule_priority(double_paren_large_alpha_section,5).
rule_priority(double_paren_small_alpha_section,4).
rule_priority(_,3).

rule_pri(Rule,Pri) :-
	rule_priority(Rule,Pri), !.


match_section(_Current, indent(Rule,Head), Text, OutText) :-
 find_rule(Text, Rule, Head, OutText).

match_section([Current|_], Current, Text, OutText) :-
	atomic_list_concat([Head|Remain], ' ', Text),
	atomic_list_concat([''|_Rest], '.', Head),
	atomic_list_concat(Remain, ' ', OutText).
match_section(Current, indent(10,Head), Text, OutText) :-
	atomic_list_concat([Head|Remain], ' ', Text),
	atomic_list_concat([First|_Rest], '.', Head),
	First \= '',
	last(Current, Head),
	atomic_list_concat(Remain, ' ', OutText).
match_section(Current, indent(11,Head), Text, OutText) :-
	atomic_list_concat([Head|Remain], ' ', Text),
	atomic_list_concat([First|_Rest], ')', Head),
	First \= '',
	last(Current, Head),
	atomic_list_concat(Remain, ' ', OutText).
match_section(Current, Current, Text, Text).
	
match_sect(Current, New, Text) :-
	once(match_section(Current, New, Text, _)).
	
mark_sections(_, [], In, In).


mark_sections(_,XML) :-
	xpath:xpath(XML, //'TextWithNodes', element(_,_,Nodes)),
	findall(section(Text,Title,S), 
		(
			xpath:xpath(XML, //'Annotation'(@'Type'=b,@'StartNode'=Start,@'EndNode'=End), _), 
			sect_text(Nodes,Start,End,Text,Title), 
			xnumber(Start,S)
		), Sects),
	assert(sections(Sects)).

xnumber(In, In) :- number(In).
xnumber(In, Out) :- \+number(In), atom_number(In,Out).

handle_arguments(Args) :-
    member(arg('h',true), Args),
    format('usage: \n',[]),
    (
        argument(Arg, Param),
        intersection([description=Desc],Param,_),
        format('~w value \t~w\n',[Arg,Desc]),
    fail;true),
    halt,
    !.
handle_arguments(_).

get_missing_args(Exp, Args, AllArgs) :-
    member(Arg, Exp),
    \+ member(arg(Arg, _), Args),
    \+ tty_mode,
    read_args(json(MoreArgs)),
    findall(arg(Ar1, Ar0a), (member(Ar0=Ar0a, MoreArgs), replace(Ar0, '--', '', Ar1)), MoreArgs1),
    append(Args, MoreArgs1, AllArgs),
    !.
get_missing_args(_, Args, Args).

read_args(JsonTerm) :-
    read_header_data(current_input, Header),
    atom_codes(Atom, Header),
    atomic_list_concat([_,Data|_], '<app_data>', Atom),
    atomic_list_concat([Data1|_], '</app_data>', Data),
    atom_json_term(Data1, JsonTerm, []).
    
read_header_data(Stream, Header) :-
        read_line_to_codes(Stream, Header, Tail),
        read_header_data(Header, Stream, Tail).

read_header_data("\n", _, _) :- !.
read_header_data("", _, _) :- !.

read_header_data([_|_], Stream, Tail) :-
        read_line_to_codes(Stream, Tail, NewTail),
        read_header_data(Tail, Stream, NewTail).
        
read_header_data([], _, _) :- write('EOF\n').

log_file(Message) :-
    open('log.txt', append, Str, []),
    format(Str, 'Log:~w\n', [Message]),
    close(Str).

tty_mode :-
    stream_property(user_input, tty(true)).

analyze :-
    format('start analyze\n',[]),
    graph:node(DocId, 'DocumentRoot', Dattr),
    format('document id ~w\n',[DocId]),
    subset([],Dattr),
    findall(Seq-node(SID,Text), (graph:node(SID, 'Sentence', Attr), subset([seq=Seq,text=Text],Attr)), Sentences1),
    length(Sentences1, Len),
    format('found ~w sentences\n',[Len]),
    keysort(Sentences1, Sorted),
    findall(sentence(SID, Text), member(_-node(SID, Text),Sorted), Sentences2),

    format('sorted: ~w\n',[Sentences2]),
    section_new(DocId,Sentences2),
    concat_sections.
    
concat_sections :-
% aggregate text for each section
    (
      graph:node(Id, 'Section', Attr),
      findall(Seq-Text, section_text(Id, Seq, Text), Sentences),
      sort(Sentences, Sorted),
      findall(Sent, member(_-Sent, Sorted), SortedSent),
      atomic_list_concat(SortedSent, SectText),
      graph:delete_node(Id),
      graph:new_node(Id, 'Section', [text=SectText|Attr]),
      once(graph:new_node(TextId, 'Text', [text=SectText])), % since the Id is a variable I believe it will backtrack once which we don't want to happen '
      graph:new_edge(_, Id, TextId, 'HAS_TEXT', []),
    fail;true).
    
section_text(SectId, Seq, Text) :-
% find all sentence texts associated with this section id
    graph:node(SectId, 'Section', Attr),
    graph:edge(_, SectId, Sub, 'SECTION_LINK', _),
    graph:node(Sub, 'Sentence', SentAttr),
    subset([seq=Seq,text=Text1],SentAttr),
    format('text 1 ~w text2 ~w\n',[Text1,Text]),
    atom_concat(Text1, ' ', Text).              % add an extra space at the end so the sentences have a space between
section_text(SectId, Seq, Text) :-
    graph:node(SectId, 'Section', Attr),
    graph:edge(_, SectId, ChildId, 'CHILD_TOPIC', _),
    section_text(ChildId, Seq, Text).
    
    

:- argparse:add_argument('--input_graph',[default='*graph_output',description='graph input filename']). 
:- argparse:add_argument('--graph_format',[default=graphml,description='graph output format']). 
    
    
:- debug(X).
	
run :- 
    argparse:argparse, 
    argparse:get_argument('input_graph',File),
    argparse:get_argument('graph_format',OutputFormat),
    format('format ~w\n',[OutputFormat]),
    flag(graph_format, _, OutputFormat),
    fail_error(graph:load_graph(File)), 
    format('loaded ~w\n',[File]), 
    analyze, 
    graph:save_graphml,
    halt(0).
    


:- run.

:- module(wordnet, [word_info/1]).

:- use_module(library(http/http_client)).
:- use_module(library(http/json)).
:- use_module(library(http/json_convert)).
:- use_module(graph_lib).

lwn :- load_files('./wordnet/*.pl', [expand(true)]).

:- format('loading wordnet...\n', []), lwn.

user:preload_wordnet :-
	findall(_, 
	(
		fcypher_query('match (n:w) return id(n),n.word', [], row([Id,Word])),
		\+ gephi:neo4j_id(Word,Id),
		assert(gephi:neo4j_id(Word,Id))
	), _).
:- preload_wordnet.

%**************************************************Start Wordnet**************************************************************


% Load wordnet into neo
load_wordnet111 :-
% A s operator is present for every word sense in WordNet. In wn_s.pl , w_num specifies the word number for word in the synset.
	findall(element(synset, [synset_id=Id,word_num=WNum,word=Word,ss_type=Type,sense_number=SenseNumber,tag_count=TagCount],[]),
	(
		s(Id,WNum,Word,Type,SenseNumber,TagCount)
	), Synset),
	findall(Word,
	(
		s(Id,WNum,Word,Type,SenseNumber,TagCount)
	), Words),
	list_to_set(Words, WordSet),
	(
		member(W,WordSet),
		new_node(W, w, [word=W]),
		(
			s(Id,WNum,Word,Type,SenseNumber,TagCount),
			new_edge(_, W, Id, synset),
			fail;true
		),		
	fail;true
	),
	findall(element(gloss,[synset_id=Id,gloss=Gloss],[]),
	(
		g(Id,Gloss)
	), Allg),
	append(Synset,Allg,All),
%	flatten([Synset,Allg],All),
	fedbizopps:compile_xml_gdb(element(wordnet,[],All)).
	
	
user:load_master_wordset :-
	\+ neo_q(fact(master_wordset_loaded,true)),
	format('Constructing master list\n',[]),
	set_neo_mode(Old,import),
	add_graph_dest(neo4j),
	reset_import,
	findall(Word,
	(
		s(Id,WNum,Word,Type,SenseNumber,TagCount)
	), Words),
	list_to_set(Words, WordSet),
	format('Creating import tables\n',[]),
	(
		member(W,WordSet),
		new_node(W, w, [word=W]),
		(
			s(Id,WNum,W,Type,SenseNumber,TagCount),
			new_edge(_, W, Id, w_synset),
			fail;true
		),		
	fail;true
	),
	ignore(fcypher_queryF('CREATE CONSTRAINT ON (n:w) ASSERT n.word is UNIQUE', [], _)),
	format('Flush import\n',[]),
	flush(import),
	format('Execute import\n',[]),
	flush(execute),
	set_neo_mode(Old),
	neo_assert(fact(master_wordset_loaded,true)).

user:load_wordnet :-
	\+ neo_q(fact(wordnet_loaded,true)),
	set_neo_mode(Old,import),
	add_graph_dest(neo4j),
	reset_import,
	format('Loading wordnet ~w\n',[synset]),
% A s operator is present for every word sense in WordNet. In wn_s.pl , w_num specifies the word number for word in the synset.
	(
		s(Id,WNum,Word,Type,SenseNumber,TagCount),
		new_node(Id, wn_synset, [synset_id=Id,word_num=WNum,word=Word,ss_type=Type,sense_number=SenseNumber,tag_count=TagCount]),
	fail;true),
	fcypher_queryF('CREATE CONSTRAINT ON (n:wn_synset) ASSERT n.synset_id is UNIQUE', [], _),
	fcypher_queryF('CREATE INDEX ON :w_synset(word)',[],_),

% The g operator specifies the gloss for a synset.
	format('Loading wordnet ~w\n',[gloss]),
	(
		g(Id,Gloss),
		new_node(Id1, wn_gloss, [synset_id=Id,gloss=Gloss]),
		new_edge(_, Id, Id1, gloss),
	fail;true),
% A sk operator is present for every word sense in WordNet. This gives the WordNet sense key for each word sense.
	format('Loading wordnet ~w\n',[sk]),
	(
		sk(Id,W_num,Sense_key),
		new_node(Id1, wn_gloss, [synset_id=Id,word_num=W_num,sense_key=Sense_key]),
		new_edge(_, Id, Id1, sk),
	fail;true),
% The syntax operator specifies the syntactic marker for a given word sense if one is specified.
	format('Loading wordnet ~w\n',[syntax]),
	(
		syntax(Id,W_num,Syntax),
		new_node(Id1, wn_gloss, [synset_id=Id,word_num=W_num,syntax=Syntax]),
		new_edge(_, Id, Id1, syntax),
	fail;true),
% The hyp operator specifies that the second synset is a hypernym of the first synset. This relation holds for nouns and verbs. The reflexive operator, hyponym, implies that the first synset is a hyponym of the second synse
	format('Loading wordnet ~w\n',[hyp]),
	(
		hyp(Id1,Id2),
		new_edge(_, Id1, Id2, hyp),
	fail;true),
% The ins operator specifies that the first synset is an instance of the second synset. This relation holds for nouns. The reflexive operator, has_instance, implies that the second synset is an instance of the first synset.
	format('Loading wordnet ~w\n',[ins]),
	(
		ins(Id1,Id2),
		new_edge(_, Id1, Id2, ins),
	fail;true),
% The ent operator specifies that the second synset is an entailment of first synset. This relation only holds for verbs.
	format('Loading wordnet ~w\n',[entailment]),
	(
		ent(Id1,Id2),
		new_edge(_, Id1, Id2, entailment),
	fail;true),
% The sim operator specifies that the second synset is similar in meaning to the first synset. This means that the second synset is a satellite the first synset, which is the cluster head. This relation only holds for adjective synsets contained in adjective clusters.
	format('Loading wordnet ~w\n',[sim]),
	(
		sim(Id1,Id2),
		new_edge(_, Id1, Id2, sim),
	fail;true),
% The mm operator specifies that the second synset is a member meronym of the first synset. This relation only holds for nouns. The reflexive operator, member holonym, can be implied.
	format('Loading wordnet ~w\n',[mm]),
	(
		mm(Id1,Id2),
		new_edge(_, Id1, Id2, mm),
	fail;true),
% The der operator specifies that there exists a reflexive lexical morphosemantic relation between the first and second synset terms representing derivational morphology.
%	format('Loading wordnet ~w\n',[der]),
%	(
%		der(Id1,Id2),
%		new_edge(_, Id1, Id2, der),
%	fail;true),
% The cs operator specifies that the second synset is a cause of the first synset. This relation only holds for verbs.
	format('Loading wordnet ~w\n',[cs]),
	(
		cs(Id1,Id2),
		new_edge(_, Id1, Id2, cause),
	fail;true),
	flush(import),
	flush(execute),
	set_neo_mode(Old),
	neo_assert(fact(wordnet_loaded,true)).

% not implemented yet:
% The vgp operator specifies verb synsets that are similar in meaning and should be grouped together when displayed in response to a grouped synset search.
% The cls operator specifies that the first synset has been classified as a member of the class represented by the second synset. Either of the w_num's can be 0, reflecting that the pointer is semantic in the original WordNet database.



user:lookup_word(Word, word(Word,Usage), ID) :-
	s(ID, Wnum, Word1, Usage1, SenseN, TagCount),
	wildcard_match(Word, Word1),
	once(u_match(Usage, Usage1)).

word_info(word(Word,Usage)) :-
	s(ID, Wnum, Word1, Usage1, SenseN, TagCount),
	wildcard_match(Word, Word1),
	once(u_match(Usage, Usage1)),
	g(ID,Def),
	format('ID=~w\nW num=~w\nWord=~w\nSS Type=~w\nDefinition=~w\nSense number=~w\nTag count=~w\n', [ID, Wnum, Word1, Usage1, Def, SenseN, TagCount]).

sense(ID,Sense) :-
	s(ID, Wnum, Word, SSType1, Sense, TagCount).

word(ID,word(Word,SSType)) :-
	s(ID, Wnum, Word, SSType1, SenseN, TagCount),
	once(u_match(SSType,SSType1)).

word(ID,word(Word,SSType,ID)) :-
	s(ID, Wnum, Word, SSType1, SenseN, TagCount),
	once(u_match(SSType,SSType1)).

word(ID,word(Word,SSType,ID, SenseN)) :-
	s(ID, Wnum, Word, SSType1, SenseN, TagCount),
	once(u_match(SSType,SSType1)).


u_match(X,X).
u_match(a,s).	% adjective can be a or s


trans_type(X,Y) :- once(tt(X,Y)).

tt(s,n).
tt('n-u',n).
tt('v-d',v).
tt(e,r).
tt(X,X).

ttype(n, noun).
ttype(v, verb).
ttype(r, adjective).
ttype(_, word).

parse_word(Word, Bare, Post2) :-
	nonvar(Word),
	atomic_list_concat([Bare,Post1], '.', Word),
	trans_type(Post1, Post2), !.
parse_word(Word, Word, Type).


bare_word(Word, Bare) :-
	atomic_list_concat([Bare|Prefix], '.', Word), !.
bare_word(Word, Word).

def(Word,T,Def) :-
	word(ID,word(Word,T)),
	g(ID,Def).

type_of(Word,Generic) :- rel(Word, hyp, Generic).

entail(Word,Word1) :- rel(Word, ent, Word1).

similar_word(Word,Word1) :- rel(Word, sim, Word1).
similar_word(Word,Word1) :- rel(Word, hyp, Word1).

part_of(X,Y) :- rel(X, mp,Y).

composed_of(X,Y) :- rel(X, mm, Y).

holonyms(Word, List) :-
	findall(Word1, meronym(Word,Word1), List).

substance_of(Word,Word1) :- rel(Word, ms, Word1).

parts_of(Word, List) :-
	findall(Word1, part_of(Word,Word1), List).

has_a(W,W1) :- rel(W,mp,W1).


lex_rel(Verb,Verb1) :-
	word(ID,Verb),
	vgp(ID,_,ID1,_),
	word(ID1,Verb1).
	
measure(Word,Measure) :- rel(Word,at,Measure).

opposite_of(Word,Word1) :- rel(Word,ant,Word1).


rel(Word,Rel,Word1) :-
	ground1(Word),
	\+ ground(Word1),
	word(ID,Word),
	wordnet_rel(Rel),
	Pred =.. [Rel,ID,ID1],
	call(Pred),
	word(ID1,Word1).

rel(Word,Rel,Word1) :-
	ground1(Word1),
	\+ground1(Word),
	word(ID1,Word1),
	wordnet_rel(Rel),
	Pred =.. [Rel,ID,ID1],
	call(Pred),
	word(ID,Word).

rel(Word,Rel,Word1) :-
	ground1(Word),
	ground1(Word1),
	word(ID,Word),
	word(ID1,Word1),
	wordnet_rel(Rel),
	Pred =.. [Rel,ID,ID1],
	call(Pred).


also_means(X, Y) :- rel(X, sa, Y).

ant(X,Y) :-
	ant(X, _, Y, _).

sa(X, Y) :-
	sa(X, _, Y, _).

ppl(X, Y) :-
	ppl(X, _, Y, _).

per(X, Y) :-
	per(X, _, Y, _).

pick_attribute(Attribute, Adj) :-
	findset(Sense-word(W,U,ID), (find_attribute(word(W,U,ID), Adj), sense(ID,Sense)), Attributes),
	keysort(Attributes, Sorted),
	member(Attribute, Sorted).

find_attribute(Attribute,Value) :-
	similar(Value, Value1),
	attribute(Attribute, Value1).

similar(W1,W2) :-
	rel(W1, sim, W2).

user:rel_i(Word, Rel, Word1, Max, N, Path) :-
	rel_i(Word, Rel, Max, 0, N, [Word], Path, Word1).

rel2(Word, Rel, Word1) :-
	rel_i(Word, Rel, Word1, 2, _, _).

rel_i(Word, Rel, Max, N, N1, PathIn, PathIn, Word1) :- 
	rel(Word, Rel, Word1), 
	\+ member(Word1, PathIn),
	N1 is N+1.

rel_i(Word, Rel, Max, N, N2, PathIn, PathOut, Word1) :-
	rel(Word, Rel, Word0),
	\+ member(Word0, PathIn),
	N < Max,
	N1 is N+1,
	debug(agent(wordnet), 'rel_i trying ~w ~w ~w', [Word0, N, PathIn]),
	rel_i(Word0, Rel, Max, N1, N2, [ Word0 | PathIn], PathOut, Word1).

wordnet_rel(Rel) :-
	member(Rel, [ant, at, mm, ms, mp, hyp, ent, sim]).

user:attribute(Word) :-
	at(ID,_),
	word(ID,Word).

user:attribute(Attribute, Value) :-
	noun(Attribute),
	once(adjective(Value)),
	rel(Attribute, at, Value).

ground1(Var) :- nonvar(Var), Var =.. [F,A,B|_], Var1 =.. [F,A,B], ground(Var1).

adjective(Word) :- var(Word).
noun(Word) :- var(Word).
adjective(Word) :- nonvar(Word), Word =.. [word , _, U | _], member(U, [a,s]).
noun(Word) :- nonvar(Word), Word =.. [word , _, n | _].

user:sentence_frame(Verb) :-
	s(Num,W_Num,Verb,v,_,_),
	fr(Num,F_Num,W_Num),
	sen(F_Num,String_1,String_2),
	write(String_1),
	write(Verb),
	write(String_2), nl.
user:sentence_frame(Verb) :-
	s(Num,_,Verb,v,_,_),
	fr(Num,F_Num,0),
	sen(F_Num,String_1,String_2),
	write(String_1),
	write(Verb),
	write(String_2), nl.


findset(Element, Goal, Set) :- findall(Element, Goal, List), list_to_set(List, Set).

memberset(Element, Pattern) :-
	findset(Element, Pattern, Set), 
	member(Element, Set).



%**************************************************Wordnet**************************************************************


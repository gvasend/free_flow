
:- module(document_dcg,[]).

:- use_module(library(dcg/basics)). % /
 
replace(In, From, To, Out) :-
    atomic_list_concat(L, From, In),
    atomic_list_concat(L, To, Out).
    
document(S) --> sentences(S).

sentences([S|T]) --> sentence(S), sentences(T).
sentences([]) --> [], {}.

%sentence(S) --> section(_,Name), title_words([H|T]), {atomic_list_concat(['*',Name,' ',H|T],S)}. 
sentence(Sentence) --> optnl, whites, section(_,Name), whites, starting_word(W1), words(Text2), ending_word(W3), {atom_codes(Text1,W1), atom_codes(Text3,W3), format(atom(Text4),'~w ~w ~w ~w.',[Name,Text1,Text2,Text3]), replace(Text4,'  .','.',Sentence), validate_s(Sentence)}.
sentence(Sentence) --> optnl, whites, starting_word(W1), words(Text2), ending_word(W3), {atom_codes(Text1,W1), atom_codes(Text3,W3), format(atom(Text4),'~w ~w ~w.',[Text1,Text2,Text3]), replace(Text4,'  .','.',Sentence), validate_s(Sentence)}.
% sentence(Atom) --> whites, nonblanks([H|T]), whites, { atom_codes(Atom,[H|T]) }.
% sentence(Atom) --> nonblanks([H|T]), { atom_codes(Atom,[H|T]) }.

validate_s(Sentence) :-
%	trace,
	atomic_list_concat(List, ' ', Sentence),
	last(List, Atom),
	atom_codes(Atom,Codes1),
	append(Codes1,[32],Codes),
	\+ phrase(section(_,_), Codes, _).

title_words([Text]) --> title_word(W), title_words([H|T]), {trace,atom_codes(A,W), atomic_list_concat([A,' ',H|T], Text)}.
title_words(['.']) --> whites, "\n".

title_word({H|T}) --> whites, uppers({H|T}).
title_word([H|T]) --> uppers([H|T]).

optnl --> newline.
optnl --> [].

starting_word(A) --> acronym(A).
starting_word(Word) --> capitalized_word(Word).

acronym([H,H1|T]) --> upperc([H]), upperc([H1]), uppers(T).


alphas([H|T]) --> alphac([H]), alphas(T).
alphas([]) --> [].
%alphas(H) --> alphac(H).

uppers([H|T]) --> upperc([H]), uppers(T).
uppers([]) --> [].

lowers([H|T]) --> lowerc([H]), lowers(T).
lowers([]) --> [].

capitalized_word([H|T]) --> upperc([H]), lowers(T), whites.


lowerc([C]) --> [C], {code_type(C,lower)}.
upperc([C]) --> [C], {code_type(C,upper)}.
alphac([C]) --> [C], {code_type(C,alpha)}.


words(Text) --> word(Word), words(Text2), {atom_codes(Text1,Word), format(atom(Text),'~w ~w',[Text1,Text2])}.
words('') --> [].
%words(Text) --> word(Word), {atom_codes(Text,Word)}.

word([H|T]) --> whitesnl, nonblanksp([H|T]), {true}.
word([H|T]) --> nonblanksp([H|T]), {true}.

word1(A) --> acronym(A).
word1(S) --> special_case(S).

special_case("e.g.") --> "e.g.".

ending_word(Word) --> alphas(Word), ".".
ending_word(Word) --> alphas(Word), ":".
ending_word('nl_nl') --> newline, newline.

noncap_word([H|T]) --> whites, lowerc([H]), lowers(T).

sentence(Text1) --> string(Codes), "\n", {atom_codes(Text,Codes),format(atom(Text1),'~w',[Text])}.
sentence('%') --> "\n".
%sentence(Text) --> string(Codes), eos, {atom_codes(Text,Codes), Text \= ''}.

%%	whites// is det.
%
%	Skip white space _inside_ a line.
%
%	@see blanks//0 also skips newlines.

whitesnl -->
	white, !,
	whitesnl.
whitesnl -->
	newline, !,
	whitesnl.
whitesnl -->
	[].
	
newline -->
	[C],
	{ nonvar(C),
	  code_type(C, newline)
	}.


%%	nonblanks(-Codes)// is det.
%
%	Take all =graph= characters

nonblanksp([H|T]) -->
	[H],
	{ 
		code_type(H, graph),
		\+char_code('.',H),
		\+char_code(':',H)
	}, !,
	nonblanksp(T).
nonblanksp([]) -->
	[].

%%	nonblank(-Code)// is semidet.
%
%	Code is the next non-blank (=graph=) character.

nonblankp(H) -->
	[H],
	{ code_type(H, graph)
	}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


section(Rule,Name) --> rfp_section(Rule,Name).
%section(Rule,SectionName) --> cdrl_section(Rule,SectionName).
%section(Rule,SectionName) --> attachment_section(Rule,SectionName).

section(Rule,SectionName) --> large_roman_section(Rule,SectionName).
section(Rule,SectionName) --> small_roman_section(Rule,SectionName).

section(Rule,SectionName) --> double_paren_decimal_section(Rule,SectionName).
section(Rule,SectionName) --> double_paren_large_alpha_section(Rule,SectionName).
section(Rule,SectionName) --> double_paren_small_alpha_section(Rule,SectionName).

section(Rule,SectionName) --> single_paren_decimal_section(Rule,SectionName).
section(Rule,SectionName) --> single_paren_large_alpha_section(Rule,SectionName).
section(Rule,SectionName) --> single_paren_small_alpha_section(Rule,SectionName).

section(Rule,SectionName) --> large_alpha_section(Rule,SectionName).
section(Rule,SectionName) --> small_alpha_section(Rule,SectionName).

section(Rule,SectionName) --> decimal_section(Rule,SectionName), { filter_decimal_section(SectionName)}.

% section(Rule,SectionName) --> colon_section(Rule,SectionName).

filter_decimal_section(Text) :-
	atom_number(Text,Number),
	Number < 20.
filter_decimal_section(Text) :-
	\+ atom_number(Text,_).

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
	
colon_section(colon, Name) -->
		string(Codes), ":", !,
		{ atom_codes(Name, Codes) }.
		
rfp_section(rfp_section,Name) -->
	"SECTION",
	whites,
	section_id(Name), " ".
	
cdrl_section(cdrl_section,Name) -->
	"CDRL",
	whites,
	string(Codes), " ", !,
	{ atom_codes(Name, Codes) }.
	
attachment_section(attachment_section,Name) -->
	"Attachment",
	whites,
	string(Codes), "\n", !,
	{ atom_codes(Name, Codes) }.
	
section_id(Id) -->
	upper(Code), {atom_codes(Id, [Code])}.

decimal_section(decimal,Name) -->
	digit(D0),
	digits(D1),
	".",
	decimal_section1(_,S), { append([D0],D1, Sec), atom_codes(Atom,Sec), format(atom(Name),'~w.~w.',[Atom,S]) }.
	
decimal_section(decimal,Name) -->
	digit(D0),
	digits(D),
	". ", { append([D0], D, NameList), atom_codes(Name1, NameList), atom_concat(Name1, '. ', Name) }.
	
decimal_section1(decimal,Name) -->
	digit(D0),
	digits(D1),
	".",
	decimal_section1(_,S), { append([D0],D1, Sec), atom_codes(Atom,Sec), format(atom(Name),'~w.~w',[Atom,S]) }.
	
decimal_section1(decimal,Name) -->
	digit(D0),
	digits(D),
	". ", { append([D0], D, NameList), atom_codes(Name, NameList) }.
	
decimal_section1(decimal,Name) -->
	digit(D0),
	digits(D), " ",
	 { append([D0], D, NameList), atom_codes(Name, NameList) }.
	
double_paren_decimal_section(double_paren_decimal,Name) -->
	"(", one_or_two_digits(D), ")", { atom_codes(Ch, D), format(atom(Name), '(~w)', [Ch]) }.
double_paren_large_alpha_section(double_paren_large_alpha_section,Name) -->
	"(", upper(D), ")", { atom_codes(Ch, [D]), format(atom(Name), '(~w)', [Ch]) }.
double_paren_small_alpha_section(double_paren_small_alpha_section,Name) -->
	"(", lower(D), ")", { atom_codes(Ch, [D]), format(atom(Name), '(~w)', [Ch]) }.
	
single_paren_decimal_section(single_paren_decimal,Name) -->
	one_or_two_digits(D), ")", { atom_codes(Ch, D), format(atom(Name), '~w)', [Ch]) }.
single_paren_large_alpha_section(single_paren_large_alpha_section,Name) -->
	upper(D), ")", { atom_codes(Ch, [D]), format(atom(Name), '~w)', [Ch]) }.
single_paren_small_alpha_section(single_paren_small_alpha_section,Name) -->
	lower(D), ")", { atom_codes(Ch, [D]), format(atom(Name), '~w)', [Ch]) }.

one_or_two_digits([D]) -->
	digit(D).
one_or_two_digits([D1,D2]) -->
	digit(D1), digit(D2).
	
upper(C) -->
	[C],
	{ code_type(C, upper)
	}.
	
lower(C) -->
	[C],
	{ code_type(C, lower)
	}.

large_alpha_section(large_alpha, Name) -->
	upper(D0),
	".", { atom_codes(Name1,[D0]), format(atom(Name),'~w.',[Name1]) }.
small_alpha_section(small_alpha, Name) -->
	lower(D0),
	".", { atom_codes(Name1,[D0]), format(atom(Name),'~w.',[Name1]) }.	
	
large_roman_section(large_roman, 'I.') -->
	"I.".
large_roman_section(large_roman, 'II.') -->
	"II.".
large_roman_section(large_roman, 'III.') -->
	"III.".
large_roman_section(large_roman, 'IV.') -->
	"IV.".
large_roman_section(large_roman, 'V.') -->
	"V.".
large_roman_section(large_roman, 'VI.') -->
	"VI.".
large_roman_section(large_roman, 'VII.') -->
	"VII.".	
large_roman_section(large_roman, 'VIII.') -->
	"VIII.".
large_roman_section(large_roman, 'IX.') -->
	"IX.".
large_roman_section(large_roman, 'X.') -->
	"X.".	
small_roman_section(small_roman, 'i.') -->
	"i.".
small_roman_section(small_roman, 'ii.') -->
	"ii.".
small_roman_section(small_roman, 'iii.') -->
	"iii.".
small_roman_section(small_roman, 'iv.') -->
	"iv.".
small_roman_section(small_roman, 'v.') -->
	"v.".
small_roman_section(small_roman, 'vi.') -->
	"vi.".
small_roman_section(small_roman, 'vii.') -->
	"vii.".	
small_roman_section(small_roman, 'viii.') -->
	"viii.".
small_roman_section(small_roman, 'ix.') -->
	"ix.".
small_roman_section(small_roman, 'x.') -->
	"x.".	



		




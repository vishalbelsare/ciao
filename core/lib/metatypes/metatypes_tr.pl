:- module(metatypes_tr, [expand_metatypes/2], [noprelude]).

% Add meta_predicate declarations from type declarations

:- use_module(engine(basiccontrol)).
:- use_module(engine(term_basic)).
:- use_module(engine(term_typing)).
:- use_module(engine(arithmetic)).

expand_metatypes((:- meta_regtype(F/A)), Decl) :-
    atom(F), integer(A), !,
    ( A > 1 ->
        Decl = (:- meta_predicate MP),
        functor(MP, F, A),
        meta_of_regtype(A, MP)
    ; Decl = []
    ).

meta_of_regtype(N, MP) :-
    arg(N, MP, ?),
    N1 is N-1,
    meta_of_regtype_(N1, MP).

meta_of_regtype_(N, _) :- N =< 0, !.
meta_of_regtype_(N, MP) :-
    arg(N, MP, pred(1)),
    N1 is N-1,
    meta_of_regtype_(N1, MP).

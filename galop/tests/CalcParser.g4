parser grammar CalcParser;

// galop does not support tokenVocab yet, so the tokens are declared here, in
// CalcLexer.g4's order.
tokens { PLUS, INT }

expr : INT (PLUS INT)* ;

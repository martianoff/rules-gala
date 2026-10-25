parser grammar CalcParser;

options { tokenVocab = CalcLexer; }

expr : expr PLUS expr | INT ;

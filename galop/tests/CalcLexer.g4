lexer grammar CalcLexer;

PLUS : '+' ;
INT  : [0-9]+ ;
WS   : [ \t\r\n]+ -> skip ;

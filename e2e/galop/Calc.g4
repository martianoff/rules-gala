grammar Calc;

prog : expr EOF ;
expr : INT ((PLUS | MINUS) INT)* ;

PLUS  : '+' ;
MINUS : '-' ;
INT   : [0-9]+ ;
WS    : [ \t\r\n]+ -> skip ;

grammar Calc;

expr : expr (PLUS | MINUS) expr | INT ;

PLUS  : '+' ;
MINUS : '-' ;
INT   : [0-9]+ ;
WS    : [ \t\r\n]+ -> skip ;
